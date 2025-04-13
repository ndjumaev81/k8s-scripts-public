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

# Step 1: Install cfssl
for node in $master_node $worker_nodes; do
    echo "Installing cfssl on $node..."
    multipass exec "$node" -- sudo apt update
    multipass exec "$node" -- sudo apt install -y golang-cfssl
done

# Step 2: Create ca-config.json
for node in $master_node $worker_nodes; do
    echo "Creating ca-config.json on $node..."
    multipass exec "$node" -- sudo bash -c 'mkdir -p /etc/kubernetes/pki; [ -f /etc/kubernetes/pki/ca-config.json ] || echo "{\"signing\":{\"default\":{\"expiry\":\"8760h\"},\"profiles\":{\"kubernetes\":{\"usages\":[\"signing\",\"key encipherment\",\"server auth\",\"client auth\"],\"expiry\":\"8760h\"}}}}" > /etc/kubernetes/pki/ca-config.json'
done

# Step 3: Copy CA files
echo "Fetching CA files from $master_node..."
multipass exec "$master_node" -- sudo cat /etc/kubernetes/pki/ca.crt > ca.crt
multipass exec "$master_node" -- sudo cat /etc/kubernetes/pki/ca.key > ca.key
for node in $worker_nodes; do
    echo "Copying CA files to $node..."
    multipass transfer ca.crt "$node":/tmp/ca.crt
    multipass transfer ca.key "$node":/tmp/ca.key
    multipass exec "$node" -- sudo mkdir -p /etc/kubernetes/pki
    multipass exec "$node" -- sudo mv /tmp/ca.crt /etc/kubernetes/pki/ca.crt
    multipass exec "$node" -- sudo mv /tmp/ca.key /etc/kubernetes/pki/ca.key
done
rm ca.crt ca.key

# Step 4: Clean CNI
for node in $master_node $worker_nodes; do
    echo "Cleaning CNI on $node..."
    multipass exec "$node" -- sudo bash -c 'rm -rf /etc/cni/net.d/*; ip link delete cni0 2>/dev/null || true; ip link delete flannel.1 2>/dev/null || true'
done

# Step 5: Generate certificates
for node in $master_node $worker_nodes; do
    ip=$(multipass list | grep "$node" | grep Running | grep -oE '192\.168\.[0-9]+\.[0-9]+' | head -n1)
    if [ -z "$ip" ]; then
        echo "Error: Could not find IP for $node"
        exit 1
    fi
    hostname="$node.loc"
    echo "Generating certificate for $node ($ip, $hostname)"

    # Stop kubelet
    multipass exec "$node" -- sudo systemctl stop kubelet

    # Remove old certs
    multipass exec "$node" -- sudo bash -c "rm -f /var/lib/kubelet/pki/kubelet.crt /var/lib/kubelet/pki/kubelet.key"

    # Update kubelet flags
    multipass exec "$node" -- sudo bash -c "echo \"KUBELET_KUBEADM_ARGS=\\\"--container-runtime-endpoint=unix:///var/run/containerd/containerd.sock --pod-infra-container-image=registry.k8s.io/pause:3.9 --node-ip=$ip --hostname-override=$hostname\\\"\" > /var/lib/kubelet/kubeadm-flags.env"

    # Fix CA file ownership
    multipass exec "$node" -- sudo bash -c "chown root:root /etc/kubernetes/pki/ca.crt /etc/kubernetes/pki/ca.key"

    # Create CSR
    cat > csr.json <<EOF
{
  "CN": "system:node:$hostname",
  "hosts": [
    "$hostname",
    "$ip",
    "$node"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "system:nodes"
    }
  ]
}
EOF
    multipass transfer csr.json "$node":/tmp/csr.json

    # Generate cert JSON (suppress logs)
    multipass exec "$node" -- sudo bash -c "cfssl gencert -loglevel 0 -ca=/etc/kubernetes/pki/ca.crt -ca-key=/etc/kubernetes/pki/ca.key -config=/etc/kubernetes/pki/ca-config.json -profile=kubernetes /tmp/csr.json > /tmp/kubelet-cert.json"

    # Check JSON
    multipass exec "$node" -- sudo bash -c "jq . /tmp/kubelet-cert.json > /dev/null && echo \"JSON valid\" || echo \"Error: Invalid JSON\""

    # Extract cert and key
    multipass exec "$node" -- sudo bash -c "jq -r .cert /tmp/kubelet-cert.json > /tmp/kubelet.crt"
    multipass exec "$node" -- sudo bash -c "jq -r .key /tmp/kubelet-cert.json > /tmp/kubelet.key"

    # Check cert files
    multipass exec "$node" -- sudo bash -c "ls -l /tmp/kubelet.crt /tmp/kubelet.key && [ -s /tmp/kubelet.crt ] && [ -s /tmp/kubelet.key ] || echo \"Error: Certificate files missing or empty\""

    # Move certs
    multipass exec "$node" -- sudo bash -c "mkdir -p /var/lib/kubelet/pki && mv /tmp/kubelet.crt /var/lib/kubelet/pki/kubelet.crt && mv /tmp/kubelet.key /var/lib/kubelet/pki/kubelet.key"

    rm csr.json
done

# Step 6: Rejoin workers
for node in $worker_nodes; do
    echo "Rejoining $node..."
    kubectl delete node "$node" --ignore-not-found
    multipass exec "$node" -- sudo bash -c "kubeadm reset -f; rm -rf /etc/cni/net.d/*; ip link delete cni0 2>/dev/null || true; ip link delete flannel.1 2>/dev/null || true; iptables -F && iptables -X; ipvsadm --clear 2>/dev/null || true"
    multipass exec "$master_node" -- kubeadm token create --print-join-command > join.sh
    multipass transfer join.sh "$node":/tmp/join.sh
    multipass exec "$node" -- sudo bash /tmp/join.sh
    rm join.sh
done

# Step 7: Start kubelet
for node in $master_node $worker_nodes; do
    echo "Starting kubelet on $node..."
    multipass exec "$node" -- sudo systemctl start kubelet
done

# Verify control plane is up before CNI and Metrics Server
echo "Verifying API server connectivity..."
for i in {1..30}; do
    if kubectl get nodes >/dev/null 2>&1; then
        echo "API server is up"
        break
    fi
    echo "Waiting for API server ($i/30)..."
    sleep 2
done
if ! kubectl get nodes >/dev/null 2>&1; then
    echo "Error: API server not responding after 60 seconds"
    multipass exec "$master_node" -- sudo journalctl -u kubelet -n 50
    exit 1
fi

# Step 8: Reinstall CNI
echo "Reinstalling CNI..."
kubectl delete -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml || true
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# Step 9: Deploy Metrics Server
echo "Deploying Metrics Server..."
curl -s https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml | \
sed $'s/args:/args:\\n    - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname\\n    - --kubelet-insecure-tls/' | \
kubectl apply -f -

# Verify
echo "Verifying cluster..."
kubectl get nodes
kubectl get pods -n kube-system | grep -E 'metrics-server|flannel'
kubectl top nodes