#!/bin/bash

# Ensure bash
if [ -z "$BASH_VERSION" ]; then
    echo "Error: Must run with bash"
    exit 1
fi

# Check GitHub username argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 <github-username>"
    exit 1
fi

GITHUB_USERNAME="$1"
WORKER_SCRIPT_URL="https://raw.githubusercontent.com/$GITHUB_USERNAME/k8s-scripts-public/main/scripts/multipass-kube-worker.sh"
NFS_PROVISIONER_URL="https://raw.githubusercontent.com/$GITHUB_USERNAME/k8s-scripts-public/main/scripts/deploy-nfs-provisioner.sh"

# Get current macOS username for NFS
HOST_USERNAME=$(whoami)
if [ -z "$HOST_USERNAME" ]; then
    echo "Error: Could not determine current username"
    exit 1
fi

# Validate k8s-master exists
if ! multipass info k8s-master >/dev/null 2>&1; then
    echo "Error: k8s-master does not exist"
    exit 1
fi

# Fetch worker nodes dynamically
worker_nodes=$(multipass list | grep 'k8s-worker-' | grep Running | awk '{print $1}')
if [ -z "$worker_nodes" ]; then
    echo "Error: No k8s-worker-* nodes found"
    exit 1
fi

# Validate worker nodes exist
for node in $worker_nodes; do
    if ! multipass info "$node" >/dev/null 2>&1; then
        echo "Error: Node $node does not exist"
        exit 1
    fi
done

# Fetch k8s-master IP
echo "Fetching k8s-master IP..."
master_ip=$(multipass list | grep k8s-master | grep Running | grep -oE '192\.168\.[0-9]+\.[0-9]+' | head -n1)
if [ -z "$master_ip" ]; then
    echo "Error: Could not find IP for k8s-master"
    exit 1
fi
echo "k8s-master IP: $master_ip"

# Clean up old tokens on k8s-master
echo "Cleaning up old bootstrap tokens on k8s-master..."
multipass exec k8s-master -- sudo kubeadm token list | grep -E '[a-z0-9]{6}\.[a-z0-9]{16}' | awk '{print $1}' | while read -r token; do
    multipass exec k8s-master -- sudo kubeadm token delete "$token"
done

# Generate a new join token
echo "Generating new join token..."
join_output=$(multipass exec k8s-master -- sudo kubeadm token create --print-join-command 2>&1)
if [ $? -ne 0 ]; then
    echo "Error: Failed to generate token. Output: $join_output"
    exit 1
fi
TOKEN=$(echo "$join_output" | grep -oE '[a-z0-9]{6}\.[a-z0-9]{16}' | head -n1)
HASH=$(echo "$join_output" | grep -oE 'sha256:[a-z0-9]{64}' | head -n1)
if [ -z "$TOKEN" ] || [ -z "$HASH" ]; then
    echo "Error: Could not parse token or hash from output: $join_output"
    exit 1
fi

# Validate token format
if ! echo "$TOKEN" | grep -qE '^[a-z0-9]{6}\.[a-z0-9]{16}$'; then
    echo "Error: Invalid token format: $TOKEN"
    exit 1
fi
echo "Using token: $TOKEN, hash: $HASH"

# Sync clocks for workers
for node in $worker_nodes; do
    echo "Syncing clock on $node..."
    multipass exec "$node" -- sudo bash -c "apt update && apt install -y ntpdate && ntpdate pool.ntp.org"
    if [ $? -ne 0 ]; then
        echo "Warning: Clock sync failed on $node, continuing..."
    fi
done

# Install workers
for node in $worker_nodes; do
    echo "Checking if $node is already joined..."
    if multipass exec "$node" -- sudo test -f /etc/kubernetes/kubelet.conf >/dev/null 2>&1; then
        echo "Skipping $node: Already joined the cluster"
        continue
    fi
    echo "Running worker setup on $node..."
    echo "Fetching worker.sh from $WORKER_SCRIPT_URL..."
    multipass exec "$node" -- sudo bash -c "curl -s -f '$WORKER_SCRIPT_URL' > /tmp/worker.sh"
    if [ $? -ne 0 ]; then
        echo "Warning: Failed to download worker.sh from $WORKER_SCRIPT_URL on $node, continuing..."
        continue
    fi
    # Validate worker.sh content
    multipass exec "$node" -- sudo bash -c "grep -q '^#!/bin/bash' /tmp/worker.sh"
    if [ $? -ne 0 ]; then
        echo "Warning: Downloaded worker.sh is invalid (not a bash script) on $node, continuing..."
        multipass exec "$node" -- sudo cat /tmp/worker.sh
        continue
    fi
    # Run worker.sh with correct arguments
    log_file="/tmp/$node-worker-$(date +%s).log"
    echo "Executing worker.sh on $node with token: $TOKEN, hash: $HASH, host_username: $HOST_USERNAME"
    multipass exec "$node" -- sudo bash /tmp/worker.sh k8s-master.loc "$TOKEN" "$HASH" "$HOST_USERNAME" 2>&1 | tee "$log_file"
    if [ $? -ne 0 ]; then
        echo "Warning: Worker setup failed on $node, continuing. Check $log_file"
        continue
    fi
    # Verify join
    if multipass exec "$node" -- sudo test -f /etc/kubernetes/kubelet.conf >/dev/null 2>&1; then
        echo "$node successfully joined the cluster"
    else
        echo "Warning: Worker script ran but $node not joined, continuing. Check $log_file"
        continue
    fi
    # Wait for node to become Ready (up to 120 seconds)
    echo "Waiting for $node to become Ready (up to 120 seconds)..."
    for attempt in {1..12}; do
        if kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' -o jsonpath="{.items[?(@.metadata.name=='$node')].status.conditions[?(@.type=='Ready')].status}" | grep -q "True"; then
            echo "$node is Ready"
            break
        fi
        if [ $attempt -eq 12 ]; then
            echo "Warning: $node not Ready after 120 seconds, continuing..."
            kubectl get nodes -o wide
            kubectl describe node "$node" 2>/dev/null || echo "Failed to describe node $node"
            break
        fi
        echo "Attempt $attempt/12: $node not Ready, waiting 10 seconds..."
        sleep 10
    done
    multipass exec "$node" -- sudo rm /tmp/worker.sh
done

# Verify cluster nodes
echo "Verifying cluster nodes..."
kubectl get nodes -o wide
if [ $? -ne 0 ]; then
    echo "Warning: Failed to retrieve cluster nodes, continuing..."
fi

# Deploy MetalLB after workers are processed
if kubectl get deployment controller -n metallb-system >/dev/null 2>&1; then
    echo "MetalLB already deployed, checking speaker configuration..."
    # Flag to track if restart is needed
    needs_restart=0
    # Check if control-plane toleration exists
    if kubectl get daemonset speaker -n metallb-system -o jsonpath='{.spec.template.spec.tolerations[?(@.key=="node-role.kubernetes.io/control-plane")].key}' | grep -q "node-role.kubernetes.io/control-plane"; then
        echo "Removing control-plane toleration from speaker DaemonSet..."
        # Find index of control-plane toleration
        toleration_index=$(kubectl get daemonset speaker -n metallb-system -o jsonpath='{range .spec.template.spec.tolerations[*]}{.key}{"\n"}{end}' | grep -n "node-role.kubernetes.io/control-plane" | cut -d: -f1)
        if [ -n "$toleration_index" ]; then
            toleration_index=$((toleration_index-1))
            kubectl patch daemonset speaker -n metallb-system --type='json' -p="[{\"op\": \"remove\", \"path\": \"/spec/template/spec/tolerations/$toleration_index\"}]"
            if [ $? -ne 0 ]; then
                echo "Warning: Failed to remove control-plane toleration from speaker DaemonSet, continuing..."
            else
                echo "Control-plane toleration removed successfully."
                needs_restart=1
            fi
        else
            echo "Warning: Could not find control-plane toleration index, skipping toleration patch..."
        fi
    else
        echo "No control-plane toleration found in speaker DaemonSet, skipping toleration patch..."
    fi
    # Perform single restart if any patch was applied
    if [ $needs_restart -eq 1 ]; then
        echo "Restarting speaker DaemonSet to apply changes..."
        sleep 2  # Avoid rate limit
        kubectl rollout restart daemonset speaker -n metallb-system
        if [ $? -ne 0 ]; then
            echo "Warning: Failed to restart speaker DaemonSet, continuing..."
        else
            echo "Speaker DaemonSet restarted successfully."
        fi
    else
        echo "No changes applied to speaker DaemonSet, skipping restart..."
    fi
else
    echo "Deploying MetalLB..."
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
    if [ $? -ne 0 ]; then
        echo "Warning: Failed to apply MetalLB manifest, continuing..."
    else
        echo "Removing control-plane toleration from speaker DaemonSet..."
        toleration_index=$(kubectl get daemonset speaker -n metallb-system -o jsonpath='{range .spec.template.spec.tolerations[*]}{.key}{"\n"}{end}' | grep -n "node-role.kubernetes.io/control-plane" | cut -d: -f1)
        if [ -n "$toleration_index" ]; then
            toleration_index=$((toleration_index-1))
            kubectl patch daemonset speaker -n metallb-system --type='json' -p="[{\"op\": \"remove\", \"path\": \"/spec/template/spec/tolerations/$toleration_index\"}]"
            if [ $? -ne 0 ]; then
                echo "Warning: Failed to remove control-plane toleration from speaker DaemonSet, continuing..."
            fi
        fi
        echo "Restarting speaker DaemonSet to apply changes..."
        sleep 2  # Avoid rate limit
        kubectl rollout restart daemonset speaker -n metallb-system
        if [ $? -ne 0 ]; then
            echo "Warning: Failed to restart speaker DaemonSet, continuing..."
        fi
    fi
fi

# Verify MetalLB pods
echo "Waiting for MetalLB controller pod to be ready (up to 300 seconds)..."
for attempt in {1..20}; do
    ready_pods=$(kubectl get pods -n metallb-system -l app=metallb,component=controller --no-headers 2>/tmp/kubectl.err | grep '1/1' | grep -w 'Running' | wc -l | xargs)
    desired_pods=1
    if [ "$ready_pods" -eq "$desired_pods" ]; then
        echo "MetalLB controller pod is ready"
        break
    fi
    if [ $attempt -eq 20 ]; then
        echo "Warning: MetalLB controller pod not ready after 300 seconds ($ready_pods/$desired_pods ready), continuing..."
        kubectl get deployment controller -n metallb-system 2>/dev/null || echo "Controller deployment not found"
        kubectl get pods -n metallb-system 2>/dev/null || echo "No pods found in metallb-system"
        echo "Kubectl error log:"
        cat /tmp/kubectl.err
        break
    fi
    echo "Attempt $attempt/20: Controller pod not ready ($ready_pods/$desired_pods ready), waiting 15 seconds..."
    sleep 15
done

echo "Waiting for MetalLB speaker pod to be ready (up to 300 seconds)..."
for attempt in {1..20}; do
    ready_pods=$(kubectl get pods -n metallb-system -l app=metallb,component=speaker --no-headers 2>/tmp/kubectl.err | grep '1/1' | grep -w 'Running' | wc -l | xargs)
    desired_pods=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -c "k8s-worker")
    if [ "$ready_pods" -eq "$desired_pods" ]; then
        echo "MetalLB speaker pod is ready"
        break
    fi
    if [ $attempt -eq 20 ]; then
        echo "Warning: MetalLB speaker pod not ready after 300 seconds ($ready_pods/$desired_pods ready), continuing..."
        kubectl get daemonset speaker -n metallb-system 2>/dev/null || echo "Speaker daemonset not found"
        kubectl get pods -n metallb-system 2>/dev/null || echo "No pods found in metallb-system"
        echo "Kubectl error log:"
        cat /tmp/kubectl.err
        break
    fi
    echo "Attempt $attempt/20: Speaker pod not ready ($ready_pods/$desired_pods ready), waiting 15 seconds..."
    sleep 15
done

# Apply MetalLB configuration after pods are ready
echo "Applying MetalLB configuration..."
kubectl apply -f https://raw.githubusercontent.com/$GITHUB_USERNAME/k8s-scripts-public/main/yaml-scripts/metallb-config-fixed-and-auto.yaml
if [ $? -ne 0 ]; then
    echo "Warning: Failed to apply MetalLB configuration, continuing..."
    kubectl describe service metallb-webhook-service -n metallb-system 2>/dev/null || echo "Webhook service not found"
    kubectl logs -n metallb-system -l app=metallb,component=controller 2>&1 || echo "No controller pod logs available"
fi

# Deploy NFS provisioner
if kubectl get deployment nfs-provisioner-p501 -n kube-system >/dev/null 2>&1; then
    echo "NFS provisioner already deployed, skipping..."
else
    echo "Deploying NFS provisioner..."
    curl -s -f "$NFS_PROVISIONER_URL" > /tmp/deploy-nfs-provisioner.sh
    if [ $? -ne 0 ]; then
        echo "Warning: Failed to download deploy-nfs-provisioner.sh from $NFS_PROVISIONER_URL, continuing..."
    else
        # Validate script content
        grep -q '^#!/bin/bash' /tmp/deploy-nfs-provisioner.sh
        if [ $? -ne 0 ]; then
            echo "Warning: Downloaded deploy-nfs-provisioner.sh is invalid, continuing..."
            cat /tmp/deploy-nfs-provisioner.sh
        else
            # Test NFS mount from first worker
            first_worker=$(echo "$worker_nodes" | head -n1)
            echo "Testing NFS mount from $first_worker..."
            multipass exec "$first_worker" -- sudo bash -c "mkdir -p /mnt/nfs && mount -t nfs 192.168.64.1:/Users/Shared/nfs-share/p501 /mnt/nfs && umount /mnt/nfs"
            if [ $? -ne 0 ]; then
                echo "Warning: NFS mount test failed on $first_worker, continuing..."
                multipass exec "$first_worker" -- showmount -e 192.168.64.1
            fi

            # Execute NFS provisioner script
            chmod +x /tmp/deploy-nfs-provisioner.sh
            /tmp/deploy-nfs-provisioner.sh 192.168.64.1
            if [ $? -ne 0 ]; then
                echo "Warning: NFS provisioner deployment failed, continuing..."
            fi
        fi
    fi
fi

# Verify NFS provisioner pods
echo "Verifying NFS provisioner pods (up to 120 seconds)..."
for attempt in {1..12}; do
    ready_pods=$(kubectl get pods -n kube-system -l app=nfs-provisioner-p501 --no-headers 2>/dev/null | grep -E '1/1\s+Running' | wc -l | xargs)
    if [ "$ready_pods" -ge 1 ]; then
        echo "NFS provisioner pods are ready"
        break
    fi
    if [ $attempt -eq 12 ]; then
        echo "Warning: NFS provisioner pods not ready after 120 seconds, continuing..."
        kubectl get pods -n kube-system -l app=nfs-provisioner-p501 2>/dev/null || echo "No NFS provisioner pods found"
        break
    fi
    echo "Attempt $attempt/12: NFS provisioner pods not ready ($ready_pods pods ready), waiting 10 seconds..."
    sleep 10
done

echo "Worker node setup complete."