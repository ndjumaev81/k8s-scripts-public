#!/bin/bash

# Usage message
if [ $# -ne 1 ]; then
  echo "Usage: $0 <registry-ip:port>"
  echo "Example: $0 192.168.64.106:5000"
  exit 1
fi

REGISTRY_IP="$1"

# Validate IP:port format (basic check)
if ! echo "$REGISTRY_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$'; then
  echo "Error: Invalid IP:port format. Use <IP>:<PORT> (e.g., 192.168.64.106:5000)"
  exit 1
fi

# Fetch running Kubernetes nodes dynamically
nodes=$(multipass list | grep -E 'k8s-master|k8s-worker-' | grep Running | awk '{print $1}')
if [ -z "$nodes" ]; then
  echo "Error: No running k8s-master or k8s-worker-* nodes found."
  exit 1
fi

for node in $nodes; do
  if multipass info $node >/dev/null 2>&1; then
    echo "Updating containerd config on $node for registry $REGISTRY_IP..."
    multipass exec $node -- sudo bash -c "cat <<EOF > /etc/containerd/config.toml
version = 2
[plugins]
  [plugins.\"io.containerd.grpc.v1.cri\"]
    [plugins.\"io.containerd.grpc.v1.cri\".registry]
      config_path = \"\"
      [plugins.\"io.containerd.grpc.v1.cri\".registry.mirrors]
        [plugins.\"io.containerd.grpc.v1.cri\".registry.mirrors.\"$REGISTRY_IP\"]
          endpoint = [\"http://$REGISTRY_IP\"]
      [plugins.\"io.containerd.grpc.v1.cri\".registry.configs]
        [plugins.\"io.containerd.grpc.v1.cri\".registry.configs.\"$REGISTRY_IP\".tls]
          insecure_skip_verify = true
EOF"
    echo "Restarting containerd on $node..."
    if multipass exec $node -- sudo systemctl restart containerd; then
      echo "containerd restarted successfully on $node"
    else
      echo "Error: Failed to restart containerd on $node"
      multipass exec $node -- sudo journalctl -u containerd.service -n 100
      exit 1
    fi
  else
    echo "Node $node not found, skipping."
  fi
done

echo "Containerd configuration updated for registry $REGISTRY_IP on all nodes."