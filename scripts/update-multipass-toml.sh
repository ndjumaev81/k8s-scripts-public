#!/bin/bash

if [ $# -ne 1 ]; then
  echo "Usage: $0 <registry-ip:port>"
  echo "Example: $0 192.168.64.106:5000"
  exit 1
fi

REGISTRY_IP="$1"

if ! echo "$REGISTRY_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$'; then
  echo "Error: Invalid IP:port format. Use <IP>:<PORT> (e.g., 192.168.64.106:5000)"
  exit 1
fi

nodes=$(multipass list | grep -E 'k8s-master|k8s-worker-' | grep Running | awk '{print $1}')
if [ -z "$nodes" ]; then
  echo "Error: No running k8s-master or k8s-worker-* nodes found."
  exit 1
fi

for node in $nodes; do
  if multipass info $node >/dev/null 2>&1; then
    echo "Generating default containerd config on $node..."
    if ! multipass exec $node -- bash -c "sudo containerd config default > /tmp/default.toml 2>/tmp/default.err"; then
      echo "Error: Failed to generate default config on $node"
      multipass exec $node -- cat /tmp/default.err
      exit 1
    fi
    echo "Verifying default config on $node..."
    if ! multipass exec $node -- test -s /tmp/default.toml; then
      echo "Error: Default config file /tmp/default.toml is empty or missing on $node"
      multipass exec $node -- cat /tmp/default.err
      exit 1
    fi
    echo "Copying default config to /etc/containerd/config.toml on $node..."
    multipass exec $node -- sudo bash -c "cat /tmp/default.toml > /etc/containerd/config.toml"
    echo "Appending insecure registry settings for $REGISTRY_IP on $node..."
    multipass exec $node -- sudo bash -c "cat <<EOF >> /etc/containerd/config.toml
[plugins.\"io.containerd.grpc.v1.cri\".registry.mirrors.\"$REGISTRY_IP\"]
  endpoint = [\"http://$REGISTRY_IP\"]
[plugins.\"io.containerd.grpc.v1.cri\".registry.configs.\"$REGISTRY_IP\".tls]
  insecure_skip_verify = true
EOF"
    echo "Clearing containerd cache on $node..."
    multipass exec $node -- sudo systemctl stop containerd
    multipass exec $node -- sudo rm -rf /run/containerd/io.containerd.content/*
    echo "Restarting containerd on $node..."
    if multipass exec $node -- sudo systemctl start containerd; then
      echo "containerd restarted successfully on $node"
    else
      echo "Error: Failed to restart containerd on $node"
      multipass exec $node -- sudo journalctl -u containerd.service -n 100
      exit 1
    fi
    multipass exec $node -- sudo rm -f /tmp/default.toml /tmp/default.err
  else
    echo "Node $node not found, skipping."
  fi
done

echo "Containerd configuration updated for registry $REGISTRY_IP on all nodes."