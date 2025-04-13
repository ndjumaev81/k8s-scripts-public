#!/bin/bash

# Ensure bash
if [ -z "$BASH_VERSION" ]; then
  echo "Run with: bash setup_kubelet_certs.sh"
  exit 1
fi

# Step 0: Fix clock sync
for node in k8s-master k8s-worker-1 k8s-worker-2 k8s-worker-3 k8s-worker-4; do
    echo "Syncing clock on $node..."
    multipass exec $node -- sudo bash -c "apt install -y ntpdate && ntpdate pool.ntp.org"
done

# Step 1: Install cfssl
for node in k8s-master k8s-worker-1 k8s-worker-2 k8s-worker-3 k8s-worker-4; do
    echo "Installing cfssl on $node..."
    multipass exec $node -- sudo apt update
    multipass exec $node -- sudo apt install -y golang-cfssl
done

# Step 2: Create ca-config.json
for node in k8s-master k8s-worker-1 k8s-worker-2 k8s-worker-3 k8s-worker-4; do
    multipass exec $node -- sudo bash -c 'mkdir -p /etc/kubernetes/pki; [ -f /etc/kubernetes/pki/ca-config.json ] || echo "{\"signing\":{\"default\":{\"expiry\":\"8760h\"},\"profiles\":{\"kubernetes\":{\"usages\":[\"signing\",\"key encipherment\",\"server auth\",\"client auth\"],\"expiry\":\"8760h\"}}}}" > /etc/kubernetes/pki/ca-config.json'
done

# Step 3: Copy CA files
echo "Fetching CA files from k8s-master..."
multipass exec k8s-master -- sudo cat /etc/kubernetes/pki/ca.crt > ca.crt
multipass exec k8s-master -- sudo cat /etc/kubernetes/pki/ca.key > ca.key
for node in k8s-worker-1 k8s-worker-2 k8s-worker-3 k8s-worker-4; do
    echo "Copying CA files to $node..."
    multipass transfer ca.crt $node:/tmp/ca.crt
    multipass transfer ca.key $node:/tmp/ca.key
    multipass exec $node -- sudo mkdir -p /etc/kubernetes/pki
    multipass exec $node -- sudo mv /tmp/ca.crt /etc/kubernetes/pki/ca.crt
    multipass exec $node -- sudo mv /tmp/ca.key /etc/kubernetes/pki/ca.key
done
rm ca.crt ca.key

# Step 4: Clean CNI
for node in k8s-master k8s-worker-1 k8s-worker-2 k8s-worker-3 k8s-worker-4; do
    echo "Cleaning CNI on $node..."
    multipass exec $node -- sudo bash -c 'rm -rf /etc/cni/net.d/*; ip link delete cni0 2>/dev/null || true; ip link delete flannel.1 2>/dev/null || true'
done

# Step 5: Generate certificates
for node in k8s-master k8s-worker-1 k8s-worker-2 k8s-worker-3 k8s-worker-4; do
    ip=""
    case $node in
        k8s-master) ip="192.168.64.38" ;;
        k8s-worker-1) ip="192.168.64.44" ;;
        k8s-worker-2) ip="192.168.64.45" ;;
        k8s-worker-3) ip="192.168.64.46" ;;
        k8s-worker-4) ip="192.168.64.47" ;;
    esac
    hostname="$node.loc"
    echo "Generating certificate for $node ($ip, $hostname)"

    # Stop kubelet
    multipass exec $node -- sudo systemctl stop kubelet

    # Remove old certs
    multipass exec $node -- sudo bash -c "rm -f /var/lib/kubelet/pki/kubelet.crt /var/lib/kubelet/pki/kubelet.key"

    # Update kubelet flags
    multipass exec $node -- sudo bash -c "echo \"KUBELET_KUBEADM_ARGS=\\\"--container-runtime-endpoint=unix:///var/run/containerd/containerd.sock --pod-infra-container-image=registry.k8s.io/pause:3.9 --node-ip=$ip --hostname-override=$hostname\\\"\" > /var/lib/kubelet/kubeadm-flags.env"

    # Fix CA file ownership
    multipass exec $node -- sudo bash -c "chown root:root /etc/kubernetes/pki/ca.crt /etc/kubernetes/pki/ca.key"

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
    multipass transfer csr.json $node:/tmp/csr.json

    # Generate cert JSON (suppress logs)
    multipass exec $node -- sudo bash -c "cfssl gencert -loglevel 0 -ca=/etc/kubernetes/pki/ca.crt -ca-key=/etc/kubernetes/pki/ca.key -config=/etc/kubernetes/pki/ca-config.json -profile=kubernetes /tmp/csr.json > /tmp/kubelet-cert.json"

    # Check JSON
    multipass exec $node -- sudo bash -c "jq . /tmp/kubelet-cert.json > /dev/null && echo \"JSON valid\" || echo \"Error: Invalid JSON\""

    # Extract cert and key
    multipass exec $node -- sudo bash -c "jq -r .cert /tmp/kubelet-cert.json > /tmp/kubelet.crt"
    multipass exec $node -- sudo bash -c "jq -r .key /tmp/kubelet-cert.json > /tmp/kubelet.key"

    # Check cert files
    multipass exec $node -- sudo bash -c "ls -l /tmp/kubelet.crt /tmp/kubelet.key && [ -s /tmp/kubelet.crt ] && [ -s /tmp/kubelet.key ] || echo \"Error: Certificate files missing or empty\""

    # Move certs
    multipass exec $node -- sudo bash -c "mkdir -p /var/lib/kubelet/pki && mv /tmp/kubelet.crt /var/lib/kubelet/pki/kubelet.crt && mv /tmp/kubelet.key /var/lib/kubelet/pki/kubelet.key"

    rm csr.json
done

# Step 6: Rejoin workers
for node in k8s-worker-1 k8s-worker-2 k8s-worker-3 k8s-worker-4; do
    echo "Rejoining $node..."
    kubectl delete node $node --ignore-not-found
    multipass exec $node -- sudo bash -c "kubeadm reset -f; rm -rf /etc/cni/net.d/*; ip link delete cni0 2>/dev/null || true; ip link delete flannel.1 2>/dev/null || true; iptables -F && iptables -X; ipvsadm --clear 2>/dev/null || true"
    multipass exec k8s-master -- kubeadm token create --print-join-command > join.sh
    multipass transfer join.sh $node:/tmp/join.sh
    multipass exec $node -- sudo bash /tmp/join.sh
    rm join.sh
done

# Step 7: Start kubelet
for node in k8s-master k8s-worker-1 k8s-worker-2 k8s-worker-3 k8s-worker-4; do
    echo "Starting kubelet on $node..."
    multipass exec $node -- sudo systemctl start kubelet
done

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