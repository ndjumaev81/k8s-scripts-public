#!/bin/bash

# Check GitHub username argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 <github-username>"
    exit 1
fi

GITHUB_USERNAME="$1"

HOST_USERNAME=$(whoami)
if [ -z "$HOST_USERNAME" ]; then
    echo "Error: Could not determine current username"
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