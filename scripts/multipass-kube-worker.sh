#!/bin/bash

# Check if all arguments are provided
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Error: Address, token, and discovery token hash not provided."
    echo "Usage: $0 <worker-address> <token> <discovery-token-ca-cert-hash>"
    exit 1
fi

MASTER_ADDRESS="$1"
TOKEN="$2"
HASH="$3"

# Resolve hostname to IP if not already an IP
if [[ $MASTER_ADDRESS =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    MASTER_IP="$MASTER_ADDRESS"
else
    MASTER_IP=$(dig +short "$MASTER_ADDRESS" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)
    if [ -z "$MASTER_IP" ]; then
        echo "Error: Could not resolve hostname $MASTER_ADDRESS to an IP address."
        exit 1
    fi
    echo "Resolved $MASTER_ADDRESS to $MASTER_IP"
fi

# Validate IP format (basic check)
if ! [[ $MASTER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid IP address format: $MASTER_IP"
    exit 1
fi

# Update and install prerequisites
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl gnupg containerd

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
# Set the correct sandbox image for Kubernetes 1.28
sudo sed -i 's|sandbox_image = "registry.k8s.io/pause:.*"|sandbox_image = "registry.k8s.io/pause:3.9"|' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Pull the sandbox image explicitly
sudo crictl pull registry.k8s.io/pause:3.9

# Install Kubernetes packages
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubeadm=1.28.7-1.1 kubelet=1.28.7-1.1 kubectl=1.28.7-1.1
sudo apt-mark hold kubeadm kubelet kubectl

# Load kernel modules and configure sysctl
sudo modprobe bridge
sudo modprobe br_netfilter
sudo tee /etc/modules-load.d/k8s.conf <<EOF
bridge
br_netfilter
EOF
sudo tee /etc/sysctl.d/k8s.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system

# Disable swap
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# Join the cluster
sudo kubeadm join "$MASTER_IP:6443" --token "$TOKEN" --discovery-token-ca-cert-hash "$HASH"

echo "Worker node setup complete."
