#!/bin/bash

# Check if master IP is provided as an argument
if [ -z "$1" ]; then
    echo "Error: Master IP address not provided."
    echo "Usage: $0 <master-ip>"
    exit 1
fi

MASTER_IP="$1"

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

# Initialize cluster with provided master IP
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address="$MASTER_IP"

# Set up kubectl for the user
mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u)":"$(id -g)" "$HOME/.kube/config"

# Install Flannel pod network
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

echo "Master node setup complete. Save the 'kubeadm join' command output above to join worker nodes."
