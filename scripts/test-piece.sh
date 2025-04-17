#!/bin/bash

GITHUB_USERNAME="$1"
HOST_USERNAME=$(whoami)


NFS_PROVISIONER_URL="https://raw.githubusercontent.com/$GITHUB_USERNAME/k8s-scripts-public/main/scripts/deploy-nfs-provisioner.sh"

# Deploy NFS provisioner
if kubectl get deployment nfs-provisioner-p501 -n kube-system >/dev/null 2>&1; then
    echo "NFS provisioner already deployed, skipping..."
else
    echo "Deploying NFS provisioner..."
    curl -s -f "$NFS_PROVISIONER_URL" > /tmp/deploy-nfs-provisioner.sh
    if [ $? -ne 0 ]; then
        echo "Warning: Failed to download deploy-nfs-provisioner.sh from $NFS_PROVISIONER_URL, continuing..."
    else
        # Validate script content
        grep -q '^#!/bin/bash' /tmp/deploy-nfs-provisioner.sh
        if [ $? -ne 0 ]; then
            echo "Warning: Downloaded deploy-nfs-provisioner.sh is invalid, continuing..."
            cat /tmp/deploy-nfs-provisioner.sh
        else
            # Test NFS mount from first worker
            first_worker=$(echo "$worker_nodes" | head -n1)
            echo "Testing NFS mount from $first_worker..."
            multipass exec "$first_worker" -- sudo bash -c "mkdir -p /mnt/nfs && mount -t nfs 192.168.64.1:/Users/Shared/nfs-share/p501 /mnt/nfs && umount /mnt/nfs"
            if [ $? -ne 0 ]; then
                echo "Warning: NFS mount test failed on $first_worker, continuing..."
                multipass exec "$first_worker" -- showmount -e 192.168.64.1
            fi

            # Execute NFS provisioner script
            chmod +x /tmp/deploy-nfs-provisioner.sh
            /tmp/deploy-nfs-provisioner.sh 192.168.64.1
            if [ $? -ne 0 ]; then
                echo "Warning: NFS provisioner deployment failed, continuing..."
            fi
        fi
    fi
fi

# Verify NFS provisioner pods
echo "Verifying NFS provisioner pods (up to 120 seconds)..."
for attempt in {1..12}; do
    ready_pods=$(kubectl get pods -n kube-system -l app=nfs-provisioner-p501 --no-headers 2>/dev/null | grep -E '1/1\s+Running' | wc -l | xargs)
    if [ "$ready_pods" -ge 1 ]; then
        echo "NFS provisioner pods are ready"
        break
    fi
    if [ $attempt -eq 12 ]; then
        echo "Warning: NFS provisioner pods not ready after 120 seconds, continuing..."
        kubectl get pods -n kube-system -l app=nfs-provisioner-p501 2>/dev/null || echo "No NFS provisioner pods found"
        break
    fi
    echo "Attempt $attempt/12: NFS provisioner pods not ready ($ready_pods pods ready), waiting 10 seconds..."
    sleep 10
done