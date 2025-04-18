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
    echo "Executing worker.sh on $node with token: $TOKEN, hash: $HASH"
    multipass exec "$node" -- sudo bash /tmp/worker.sh k8s-master.loc "$TOKEN" "$HASH" 2>&1 | tee "$log_file"
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
    echo "Warning: Failed to retrieve cluster nodes."
    exit 1
fi

echo "Worker node setup complete."