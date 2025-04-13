#!/bin/bash

# Ensure bash (avoid /bin/sh)
if [ -z "$BASH_VERSION" ]; then
    echo "Error: Must run with bash"
    exit 1
fi

# Discover running Multipass VMs with k8s- prefix
echo "Discovering Multipass VMs..."
all_nodes=$(multipass list | grep Running | awk '{print $1}' | grep -E '^k8s-[a-zA-Z0-9_-]+$')
if [ -z "$all_nodes" ]; then
    echo "Error: No running Multipass VMs with 'k8s-' prefix found"
    exit 1
fi

# Identify master node (first k8s- node with 'master' or 'control', or via kubectl)
master_node=""
for node in $all_nodes; do
    if echo "$node" | grep -qiE 'master|control'; then
        master_node="$node"
        break
    fi
done
if [ -z "$master_node" ]; then
    # Fallback: check kubectl for control-plane node
    master_node=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -m1 -E '^k8s-.*(master|control)')
    if [ -z "$master_node" ]; then
        echo "Error: Could not identify master node"
        exit 1
    fi
fi
echo "Master node: $master_node"

# Identify worker nodes (all other k8s- nodes)
worker_nodes=""
for node in $all_nodes; do
    if [ "$node" != "$master_node" ]; then
        worker_nodes="$worker_nodes $node"
    fi
done
worker_nodes=$(echo "$worker_nodes" | xargs) # Trim whitespace
if [ -z "$worker_nodes" ]; then
    echo "Warning: No worker nodes found, proceeding with master only"
fi
echo "Worker nodes: ${worker_nodes:-none}"

# Fetch master IP from multipass
echo "Fetching VM IPs..."
master_ip=$(multipass list | grep "$master_node" | grep Running | grep -oE '192\.168\.[0-9]+\.[0-9]+' | head -n1)
if [ -z "$master_ip" ]; then
    echo "Error: Could not find IP for $master_node"
    exit 1
fi
echo "$master_node IP: $master_ip"

# Step 0: Fix clock sync
for node in $master_node $worker_nodes; do
    echo "Syncing clock on $node..."
    multipass exec "$node" -- sudo bash -c "apt install -y ntpdate && ntpdate pool.ntp.org"
done