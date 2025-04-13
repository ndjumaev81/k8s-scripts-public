#!/bin/bash

# Ensure bash (avoid /bin/sh)
if [ -z "$BASH_VERSION" ]; then
    echo "Error: Must run with bash"
    exit 1
fi

# Check if master address is provided as an argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 <github-username>"
    exit 1
fi

# Variables
GITHUB_USERNAME="$1"
WORKER_SCRIPT_URL="https://raw.githubusercontent.com/$GITHUB_USERNAME/k8s-scripts-public/main/scripts/multipass_kube_worker.sh"

# Validate nodes exist
for node in k8s-master k8s-worker-1 k8s-worker-2 k8s-worker-3 k8s-worker-4; do
    if ! multipass info "$node" >/dev/null 2>&1; then
        echo "Error: Node $node does not exist"
        exit 1
    fi
done

# Fetch k8s-master IP from multipass
echo "Fetching k8s-master IP..."
master_ip=$(multipass list | grep k8s-master | grep Running | grep -oE '192\.168\.[0-9]+\.[0-9]+' | head -n1)
if [ -z "$master_ip" ]; then
    echo "Error: Could not find IP for k8s-master"
    exit 1
fi
echo "k8s-master IP: $master_ip"

# Fetch token and hash from k8s-master
echo "Generating join token on k8s-master..."
join_output=$(multipass exec k8s-master -- kubeadm token create --print-join-command 2>&1)
if [ $? -ne 0 ]; then
    echo "Error: Failed to generate join token. Output: $join_output"
    exit 1
fi

# Parse token and hash
TOKEN=$(echo "$join_output" | grep -oE '[a-z0-9]{6}\.[a-z0-9]{16}' | head -n1)
HASH=$(echo "$join_output" | grep -oE 'sha256:[a-f0-9]{64}' | head -n1)
if [ -z "$TOKEN" ] || [ -z "$HASH" ]; then
    echo "Error: Could not parse token or hash from output: $join_output"
    exit 1
fi
echo "Using token: $TOKEN, hash: $HASH"

# Sync clocks for workers
for node in k8s-master k8s-worker-1 k8s-worker-2 k8s-worker-3 k8s-worker-4; do
    # Sync clock
    echo "Syncing clock on $node..."
    multipass exec $node -- sudo bash -c "apt update && apt install -y ntpdate && sudo apt upgrade && ntpdate pool.ntp.org"
    if [ $? -ne 0 ]; then
        echo "Error: Clock sync failed on $node"
        exit 1
    fi
done

# Install workers
for node in k8s-worker-1 k8s-worker-2 k8s-worker-3 k8s-worker-4; do
    echo "Checking if $node is already joined..."
    if multipass exec "$node" -- sudo test -f /etc/kubernetes/kubelet.conf >/dev/null 2>&1; then
        echo "Skipping $node: Already joined the cluster"
        continue
    fi
    echo "Running worker setup on $node..."
    echo "Fetching worker.sh from $WORKER_SCRIPT_URL..."
    multipass exec "$node" -- sudo bash -c "curl -s -f '$WORKER_SCRIPT_URL' > /tmp/worker.sh"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download worker.sh from $WORKER_SCRIPT_URL on $node"
        exit 1
    fi
    # Validate worker.sh content
    multipass exec "$node" -- sudo bash -c "grep -q '^#!/bin/bash' /tmp/worker.sh"
    if [ $? -ne 0 ]; then
        echo "Error: Downloaded worker.sh is invalid (not a bash script) on $node"
        multipass exec "$node" -- sudo cat /tmp/worker.sh
        exit 1
    fi
    multipass exec "$node" -- sudo bash /tmp/worker.sh k8s-master.loc "$TOKEN" "$HASH" 2>&1 | tee "/tmp/$node-worker-$(date +%s).log"
    if [ $? -ne 0 ]; then
        echo "Error: Worker setup failed on $node. Check /tmp/$node-worker-*.log"
        exit 1
    fi
    multipass exec "$node" -- sudo rm /tmp/worker.sh
done

echo "All workers set up successfully."