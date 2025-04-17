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

# Execute NFS setup script
chmod +x /tmp/setup-nfs-macos-host.sh
/tmp/setup-nfs-macos-host.sh
if [ $? -ne 0 ]; then
    echo "Error: NFS setup failed"
    exit 1
fi

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

    multipass exec k8s-master -- sudo bash /tmp/master.sh "$MASTER_IP" 2>&1 | tee "/tmp/k8s-master-$(date +%s).log"
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

# Check k8s-master node readiness
echo "Checking k8s-master node readiness..."
if ! kubectl get node k8s-master -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; then
    echo "Warning: k8s-master is not ready, attempting to proceed..."
    kubectl describe node k8s-master
fi

# Deploy and configure Metrics Server
if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
    echo "Metrics Server already deployed, checking configuration..."
    # Ensure toleration and args are applied
    kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/tolerations", "value": [{"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"}]}, {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
    if [ $? -ne 0 ]; then
        echo "Error: Failed to patch Metrics Server deployment"
        exit 1
    fi
else
    echo "Deploying Metrics Server..."
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    if [ $? -ne 0 ]; then
        echo "Error: Failed to apply Metrics Server manifest"
        exit 1
    fi

    echo "Configuring Metrics Server with toleration and --kubelet-insecure-tls..."
    kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/tolerations", "value": [{"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"}]}, {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
    if [ $? -ne 0 ]; then
        echo "Error: Failed to patch Metrics Server deployment"
        exit 1
    fi
fi

echo "Restarting Metrics Server deployment to apply configuration..."
kubectl rollout restart deployment metrics-server -n kube-system
if [ $? -ne 0 ]; then
    echo "Error: Failed to restart Metrics Server deployment"
    exit 1
fi

echo "Verifying Metrics Server pods (up to 120 seconds)..."
for attempt in {1..12}; do
    if kubectl get pods -n kube-system -l k8s-app=metrics-server -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' | grep -q "^Running$"; then
        echo "Metrics Server pods are ready"
        break
    fi
    if [ $attempt -eq 12 ]; then
        echo "Warning: Metrics Server pods not ready after 120 seconds, continuing..."
        kubectl get pods -n kube-system -l k8s-app=metrics-server
        kubectl describe pod -n kube-system -l k8s-app=metrics-server 2>/dev/null || echo "No Metrics Server pods found"
        break
    fi
    echo "Attempt $attempt/12: Pods not ready, waiting 10 seconds..."
    sleep 10
done

echo "Testing Metrics Server..."
kubectl top nodes
if [ $? -ne 0 ]; then
    echo "Warning: Failed to run kubectl top nodes, continuing..."
    kubectl logs -n kube-system -l k8s-app=metrics-server 2>/dev/null || echo "No Metrics Server pod logs available"
fi

echo "Master node setup complete."