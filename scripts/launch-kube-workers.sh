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

# Fetch or reuse join token and hash from k8s-master
echo "Checking for existing join token on k8s-master..."
existing_token=$(multipass exec k8s-master -- sudo kubeadm token list | grep -E '[a-z0-9]{6}\.[a-z0-9]{16}' | awk '{print $1}')
if [ -n "$existing_token" ]; then
    echo "Found existing token: $existing_token"
    TOKEN="$existing_token"
    # Fetch discovery-token-ca-cert-hash
    join_output=$(multipass exec k8s-master -- sudo kubeadm token create --print-join-command 2>&1)
    HASH=$(echo "$join_output" | grep -oE 'sha256:[a-f0-9]{64}' | head -n1)
    if [ -z "$HASH" ]; then
        echo "Error: Could not retrieve discovery-token-ca-cert-hash"
        exit 1
    fi
else
    echo "No existing token found, generating new join token..."
    join_output=$(multipass exec k8s-master -- sudo kubeadm token create --print-join-command 2>&1)
    if [ $? -ne 0 ]; then
        echo "Error: Failed to generate token. Output: $join_output"
        exit 1
    fi
    TOKEN=$(echo "$join_output" | grep -oE '[a-z0-9]{6}\.[a-z0-9]{16}' | head -n1)
    HASH=$(echo "$join_output" | grep -oE 'sha256:[a-f0-9]{64}' | head -n1)
    if [ -z "$TOKEN" ] || [ -z "$HASH" ]; then
        echo "Error: Could not parse token or hash from output: $join_output"
        exit 1
    fi
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
    fi
    multipass exec "$node" -- sudo rm /tmp/worker.sh
done

# Deploy MetalLB after workers are processed
if kubectl get deployment controller -n metallb-system >/dev/null 2>&1; then
    echo "MetalLB already deployed, skipping..."
else
    echo "Deploying MetalLB..."
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
    if [ $? -ne 0 ]; then
        echo "Warning: Failed to apply MetalLB manifest, continuing..."
    fi

    echo "Applying MetalLB configuration..."
    kubectl apply -f https://raw.githubusercontent.com/$GITHUB_USERNAME/k8s-scripts-public/main/yaml-scripts/metallb-config-fixed-and-auto.yaml
    if [ $? -ne 0 ]; then
        echo "Warning: Failed to apply MetalLB configuration, continuing..."
        kubectl describe service metallb-webhook-service -n metallb-system 2>/dev/null || echo "Webhook service not found"
        kubectl logs -n metallb-system -l app.kubernetes.io/component=controller 2>/dev/null || echo "No controller pod logs available"
    fi
fi

# Verify MetalLB pods
echo "Waiting for MetalLB controller pod to be ready (up to 300 seconds)..."
for attempt in {1..30}; do
    if kubectl get pods -n metallb-system -l app.kubernetes.io/component=controller -o jsonpath='{.items[*].status.phase}' | grep -q "Running"; then
        echo "MetalLB controller pod is ready"
        break
    fi
    if [ $attempt -eq 30 ]; then
        echo "Warning: MetalLB controller pod not ready after 300 seconds, continuing..."
        kubectl get deployment controller -n metallb-system
        kubectl get pods -n metallb-system
        kubectl describe pod -n metallb-system -l app.kubernetes.io/component=controller 2>/dev/null || echo "No controller pods found"
        break
    fi
    echo "Attempt $attempt/30: Controller pod not ready, waiting 10 seconds..."
    sleep 10
done

echo "Waiting for MetalLB speaker pod to be ready (up to 300 seconds)..."
for attempt in {1..30}; do
    if kubectl get pods -n metallb-system -l app.kubernetes.io/component=speaker -o jsonpath='{.items[*].status.phase}' | grep -q "Running"; then
        echo "MetalLB speaker pod is ready"
        break
    fi
    if [ $attempt -eq 30 ]; then
        echo "Warning: MetalLB speaker pod not ready after 300 seconds, continuing..."
        kubectl get daemonset speaker -n metallb-system
        kubectl get pods -n metallb-system
        kubectl describe pod -n metallb-system -l app.kubernetes.io/component=speaker 2>/dev/null || echo "No speaker pods found"
        break
    fi
    echo "Attempt $attempt/30: Speaker pod not ready, waiting 10 seconds..."
    sleep 10
done

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
            multipass exec "$first_worker" -- sudo bash -c "mkdir -p /mnt/nfs && mount -t nfs 192.168.64.1:/Users/$HOST_USERNAME/nfs-share/p501 /mnt/nfs && umount /mnt/nfs"
            if [ $? -ne 0 ]; then
                echo "Warning: NFS mount test failed on $first_worker, continuing..."
                multipass exec "$first_worker" -- showmount -e 192.168.64.1
            fi

            # Execute NFS provisioner script
            chmod +x /tmp/deploy-nfs-provisioner.sh
            /tmp/deploy-nfs-provisioner.sh 192.168.64.1 "$HOST_USERNAME"
            if [ $? -ne 0 ]; then
                echo "Warning: NFS provisioner deployment failed, continuing..."
            fi
        fi
    fi
fi

# Verify NFS provisioner pods
echo "Verifying NFS provisioner pods (up to 120 seconds)..."
for attempt in {1..12}; do
    if kubectl get pods -n kube-system -l app=nfs-provisioner-p501 -o jsonpath='{.items[*].status.phase}' | grep -q "Running"; then
        echo "NFS provisioner pods are ready"
        break
    fi
    if [ $attempt -eq 12 ]; then
        echo "Warning: NFS provisioner pods not ready after 120 seconds, continuing..."
        kubectl get pods -n kube-system -l app=nfs-provisioner-p501
        kubectl describe pod -n kube-system -l app=nfs-provisioner-p501 2>/dev/null || echo "No NFS provisioner pods found"
        break
    fi
    echo "Attempt $attempt/12: Pods not ready, waiting 10 seconds..."
    sleep 10
done

echo "Worker node setup complete."