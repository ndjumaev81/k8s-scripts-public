#!/bin/bash

# Check if master address is provided as an argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 <github-username>"
    exit 1
fi

# Variables
GITHUB_USERNAME="$1"

# Normalize hash format (add sha256: if missing)
if [[ ! "$HASH" =~ ^sha256: ]]; then
    HASH="sha256:$HASH"
fi

# Validate nodes exist
for node in k8s-master k8s-worker-1 k8s-worker-2 k8s-worker-3 k8s-worker-4; do
    if ! multipass info $node >/dev/null 2>&1; then
        echo "Error: Node $node does not exist"
        exit 1
    fi
done

# Validate k8s-master.loc resolution
echo "Checking DNS resolution for k8s-master.loc..."
master_ip=$(dig +short k8s-master.loc | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)
if [ -z "$master_ip" ]; then
    echo "Error: Could not resolve k8s-master.loc to an IP address"
    exit 1
fi
echo "k8s-master.loc resolves to $master_ip"

# Fetch token and hash from k8s-master
echo "Generating join token on k8s-master..."
join_output=$(multipass exec k8s-master -- kubeadm token create --print-join-command 2>&1)
if [ $? -ne 0 ]; then
    echo "Error: Failed to generate join token. Output: $join_output"
    exit 1
fi

# Parse token and hash
TOKEN=$(echo "$join_output" | grep -oP '(?<=--token )[\w\.]+')
HASH=$(echo "$join_output" | grep -oP '(?<=--discovery-token-ca-cert-hash )sha256:[a-f0-9]+')
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
    if multipass exec $node -- sudo test -f /etc/kubernetes/kubelet.conf >/dev/null 2>&1; then
        echo "Skipping $node: Already joined the cluster"
        continue
    fi

    echo "Running worker setup on $node..."
    multipass exec $node -- sudo bash -c "curl -s https://raw.githubusercontent.com/$GITHUB_USERNAME/k8s-scripts-public/refs/heads/main/scripts/setup_single_kube_worker.sh > /tmp/worker.sh"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download worker.sh on $node"
        exit 1
    fi
    multipass exec $node -- sudo bash /tmp/worker.sh k8s-master.loc $TOKEN $HASH 2>&1 | tee /tmp/$node-worker.log
    if [ $? -ne 0 ]; then
        echo "Error: Worker setup failed on $node. Check /tmp/$node-worker.log"
        exit 1
    fi
    multipass exec $node -- sudo rm /tmp/worker.sh
done

echo "All workers set up successfully."