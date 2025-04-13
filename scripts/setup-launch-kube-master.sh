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
MASTER_SCRIPT_URL="https://raw.githubusercontent.com/$GITHUB_USERNAME/k8s-scripts-public/main/scripts/multipass-kube-master.sh"

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
    echo "k8s-master already configured, skipping setup"
    exit 0
fi

# Run master setup
echo "Running master setup on k8s-master..."
echo "Fetching multipass-kube-master.sh from $MASTER_SCRIPT_URL..."
multipass exec k8s-master -- sudo bash -c "curl -s -f '$MASTER_SCRIPT_URL' > /tmp/master.sh"
if [ $? -ne 0 ]; then
    echo "Error: Failed to download multipass-kube-master.sh"
    exit 1
fi

# Validate script content
multipass exec k8s-master -- sudo bash -c "grep -q '^#!/bin/bash' /tmp/master.sh"
if [ $? -ne 0 ]; then
    echo "Error: Downloaded multipass-kube-master.sh is invalid"
    multipass exec k8s-master -- sudo cat /tmp/master.sh
    exit 1
fi

# Execute master script
multipass exec k8s-master -- sudo bash /tmp/master.sh "$MASTER_IP" 2>&1 | tee "/tmp/k8s-master-$(date +%s).log"
if [ $? -ne 0 ]; then
    echo "Error: Master setup failed. Check /tmp/k8s-master-*.log"
    exit 1
fi

multipass exec k8s-master -- sudo rm /tmp/master.sh
echo "Master node setup complete."