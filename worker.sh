#!/bin/bash

# Check if master IP is provided as an argument
if [ -z "$1" ]; then
    echo "Error: Master IP address not provided."
    echo "Usage: $0 <master-ip>"
    exit 1
fi

WORKER_ADDRESS="$1"

# Resolve hostname to IP if not already an IP
if [[ $WORKER_ADDRESS =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    WORKER_IP="$WORKER_ADDRESS"
else
    WORKER_IP=$(dig +short "$WORKER_ADDRESS" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)
    if [ -z "$WORKER_IP" ]; then
        echo "Error: Could not resolve hostname $WORKER_ADDRESS to an IP address."
        exit 1
    fi
    echo "Resolved $WORKER_ADDRESS to $WORKER_IP"
fi

# Validate IP format (basic check)
if ! [[ $WORKER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid IP address format: $WORKER_IP"
    exit 1
fi

# Update and install prerequisites
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl gnupg containerd

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

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

# Prompt for token and discovery token hash from master
echo "Please provide the token from the master's 'kubeadm init' output (e.g., 0ab9ad.lbhe66pv4yslcsti):"
read -r TOKEN
echo "Please provide the discovery-token-ca-cert-hash from the master's 'kubeadm init' output (e.g., sha256:4086e0b...):"
read -r HASH

# Join the cluster
sudo kubeadm join "$WORKER_IP:6443" --token "$TOKEN" --discovery-token-ca-cert-hash "$HASH"

echo "Worker node setup complete."
