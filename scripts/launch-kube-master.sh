#!/bin/bash

# Ensure bash
if [ -z "$BASH_VERSION" ]; then
    echo "Error: Must run with bash"
    exit 1
fi

# Check GitHub username argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 <github-username>"
    exit 1
fi

GITHUB_USERNAME="$1"
NFS_SCRIPT_URL="https://raw.githubusercontent.com/$GITHUB_USERNAME/k8s-scripts-public/main/scripts/setup-nfs-macos-host.sh"
MASTER_SCRIPT_URL="https://raw.githubusercontent.com/$GITHUB_USERNAME/k8s-scripts-public/main/scripts/multipass-kube-master.sh"

# Setup NFS on host
echo "Setting up NFS on macOS host..."
curl -s -f "$NFS_SCRIPT_URL" > /tmp/setup-nfs-macos-host.sh
if [ $? -ne 0 ]; then
    echo "Error: Failed to download setup-nfs-macos-host.sh from $NFS_SCRIPT_URL"
    exit 1
fi

# Validate script content
grep -q '^#!/bin/bash' /tmp/setup-nfs-macos-host.sh
if [ $? -ne 0 ]; then
    echo "Error: Downloaded setup-nfs-macos-host.sh is invalid"
    cat /tmp/setup-nfs-macos-host.sh
    exit 1
fi

# Get current macOS username
HOST_USERNAME=$(whoami)
if [ -z "$HOST_USERNAME" ]; then
    echo "Error: Could not determine current username"
    exit 1
fi

# Execute NFS setup script
chmod +x /tmp/setup-nfs-macos-host.sh
/tmp/setup-nfs-macos-host.sh "$HOST_USERNAME"
if [ $? -ne 0 ]; then
    echo "Error: NFS setup failed"
    exit 1
fi

# Verify NFS exports with retry loop
echo "Verifying NFS exports (up to 60 seconds)..."
for attempt in {1..6}; do
    if showmount -e localhost | grep -q "/Users/$HOST_USERNAME/nfs-share/p1000"; then
        echo "NFS exports verified successfully"
        break
    fi
    if [ $attempt -eq 6 ]; then
        echo "Error: NFS exports not verified after 60 seconds"
        exit 1
    fi
    echo "Attempt $attempt/6: NFS exports not ready, waiting 10 seconds..."
    sleep 10
done

# Validate k8s-master exists
if ! multipass info k8s-master >/dev/null 2>&1; then
    echo "Error: k8s-master does not exist"
    exit 1
fi

# Fetch k8s-master IP
echo "Fetching k8s-master IP..."
MASTER_IP=$(multipass list | grep k8s-master | grep Running | grep -oE '192\.168\.[0-9]+\.[0-9]+' | head -n1)
if [ -z "$MASTER_IP" ]; then
    echo "Error: Could not find IP for k8s-master"
    exit 1
fi
echo "k8s-master IP: $MASTER_IP"

# Sync clock on k8s-master
echo "Syncing clock on k8s-master..."
multipass exec k8s-master -- sudo bash -c "apt update && apt install -y ntpdate && ntpdate pool.ntp.org"
if [ $? -ne 0 ]; then
    echo "Error: Clock sync failed on k8s-master"
    exit 1
fi

# Check if k8s-master is already configured
echo "Checking if k8s-master is already configured..."
if multipass exec k8s-master -- sudo test -f /etc/kubernetes/admin.conf >/dev/null 2>&1; then
    echo "k8s-master Kubernetes setup detected"
else
    echo "Running master setup on k8s-master..."
    echo "Fetching multipass-kube-master.sh from $MASTER_SCRIPT_URL..."
    multipass exec k8s-master -- sudo bash -c "curl -s -f '$MASTER_SCRIPT_URL' > /tmp/master.sh"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download multipass-kube-master.sh"
        exit 1
    fi

    multipass exec k8s-master -- sudo bash -c "grep -q '^#!/bin/bash' /tmp/master.sh"
    if [ $? -ne 0 ]; then
        echo "Error: Downloaded multipass-kube-master.sh is invalid"
        multipass exec k8s-master -- sudo cat /tmp/master.sh
        exit 1
    fi

    multipass exec k8s-master -- sudo bash /tmp/master.sh "$MASTER_IP" "$HOST_USERNAME" 2>&1 | tee "/tmp/k8s-master-$(date +%s).log"
    if [ $? -ne 0 ]; then
        echo "Error: Master setup failed. Check /tmp/k8s-master-*.log"
        exit 1
    fi

    multipass exec k8s-master -- sudo rm /tmp/master.sh
fi

# Copy kubeconfig to host
multipass exec k8s-master -- sudo cat /etc/kubernetes/admin.conf > /tmp/k8s-master-config
mkdir -p ~/.kube
sudo mv /tmp/k8s-master-config ~/.kube/config

# Check if kubectl is installed
if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl not installed. Installing..."
    curl -LO "https://dl.k8s.io/release/v1.28.7/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    if ! command -v kubectl >/dev/null 2>&1; then
        echo "Error: kubectl installation failed"
        exit 1
    fi
    echo "kubectl installed successfully"
fi

# Verify and configure kubectl
kubectl get nodes
kubectl config use-context kubernetes-admin@kubernetes
kubectl config set-context --current --namespace=default
kubectl config rename-context kubernetes-admin@kubernetes multipass-cluster
kubectl config get-contexts

# Deploy and configure Metrics Server
echo "Deploying Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
if [ $? -ne 0 ]; then
    echo "Error: Failed to apply Metrics Server manifest"
    exit 1
fi

echo "Configuring Metrics Server with --kubelet-insecure-tls..."
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
if [ $? -ne 0 ]; then
    echo "Error: Failed to patch Metrics Server deployment"
    exit 1
fi

echo "Verifying Metrics Server pod..."
kubectl get pods -n kube-system | grep metrics-server
if [ $? -ne 0 ]; then
    echo "Error: Metrics Server pod not found"
    exit 1
fi

echo "Testing Metrics Server..."
kubectl top nodes
if [ $? -ne 0 ]; then
    echo "Error: Failed to run kubectl top nodes"
    exit 1
fi

# Deploy and configure MetalLB
echo "Deploying MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
if [ $? -ne 0 ]; then
    echo "Error: Failed to apply MetalLB manifest"
    exit 1
fi

echo "Applying MetalLB configuration..."
kubectl apply -f https://raw.githubusercontent.com/$GITHUB_USERNAME/k8s-scripts-public/main/yaml-scripts/metallb-config-fixed-and-auto.yaml
if [ $? -ne 0 ]; then
    echo "Error: Failed to apply MetalLB configuration"
    exit 1
fi

echo "Waiting for MetalLB pods to be ready (up to 60 seconds)..."
for attempt in {1..6}; do
    if kubectl get pods -n metallb-system -l app=metallb -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' | grep -q "^Running$"; then
        echo "MetalLB pods are ready"
        break
    fi
    if [ $attempt -eq 6 ]; then
        echo "Error: MetalLB pods not ready after 60 seconds"
        exit 1
    fi
    echo "Attempt $attempt/6: Pods not ready, waiting 10 seconds..."
    sleep 10
done

echo "Verifying MetalLB pods..."
kubectl get pods -n metallb-system -l app=metallb
if [ $? -ne 0 ]; then
    echo "Error: MetalLB pods not found"
    exit 1
fi

# Deploy NFS provisioner
echo "Deploying NFS provisioner..."
NFS_PROVISIONER_URL="https://raw.githubusercontent.com/$GITHUB_USERNAME/k8s-scripts-public/main/scripts/deploy-nfs-provisioner.sh"
curl -s -f "$NFS_PROVISIONER_URL" > /tmp/deploy-nfs-provisioner.sh
if [ $? -ne 0 ]; then
    echo "Error: Failed to download deploy-nfs-provisioner.sh from $NFS_PROVISIONER_URL"
    exit 1
fi

# Validate script content
grep -q '^#!/bin/bash' /tmp/deploy-nfs-provisioner.sh
if [ $? -ne 0 ]; then
    echo "Error: Downloaded deploy-nfs-provisioner.sh is invalid"
    cat /tmp/deploy-nfs-provisioner.sh
    exit 1
fi

# Test NFS mount from master VM
echo "Testing NFS mount from k8s-master..."
multipass exec k8s-master -- sudo bash -c "mkdir -p /mnt/nfs && mount -t nfs 192.168.64.1:/Users/$HOST_USERNAME/nfs-share/p501 /mnt/nfs && umount /mnt/nfs"
if [ $? -ne 0 ]; then
    echo "Error: NFS mount test failed on k8s-master"
    multipass exec k8s-master -- showmount -e 192.168.64.1
    exit 1
fi

# Execute NFS provisioner script
chmod +x /tmp/deploy-nfs-provisioner.sh
/tmp/deploy-nfs-provisioner.sh 192.168.64.1 "$HOST_USERNAME"
if [ $? -ne 0 ]; then
    echo "Error: NFS provisioner deployment failed"
    exit 1
fi

# Verify NFS provisioner pods
echo "Verifying NFS provisioner pods (up to 60 seconds)..."
for attempt in {1..6}; do
    if kubectl get pods -n kube-system -l app=nfs-provisioner-p501 -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' | grep -q "^Running$"; then
        echo "NFS provisioner pods are ready"
        break
    fi
    if [ $attempt -eq 6 ]; then
        echo "Error: NFS provisioner pods not ready after 60 seconds"
        kubectl get pods -n kube-system -l app=nfs-provisioner-p501
        exit 1
    fi
    echo "Attempt $attempt/6: Pods not ready, waiting 10 seconds..."
    sleep 10
done

echo "Master node setup complete."