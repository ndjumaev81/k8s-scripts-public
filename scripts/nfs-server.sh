#!/bin/bash
set -e

VM_NAME="nfs-server"
NFS_PATH="/srv/nfs"
NETWORK_RANGE="192.168.64.0/24"

# Function to get VM IP
get_vm_ip() {
  local vm_name=$1
  multipass info $vm_name --format json | jq -r '.info["'"$vm_name"'"].ipv4[0]' | grep -v null
}

# Check if VM exists, create if it doesn't
if ! multipass info $VM_NAME >/dev/null 2>&1; then
  echo "Creating VM $VM_NAME..."
  multipass launch --name $VM_NAME --cpus 3 --memory 4G --disk 144G 22.04
else
  echo "VM $VM_NAME already exists, skipping creation."
fi

# Get the assigned IP
NFS_IP=$(get_vm_ip $VM_NAME)
if [ -z "$NFS_IP" ]; then
  echo "Error: Could not retrieve IP for $VM_NAME."
  exit 1
fi
echo "Using IP $NFS_IP for $VM_NAME."

# Install and configure NFS
multipass exec $VM_NAME -- sudo apt update
multipass exec $VM_NAME -- sudo apt install -y nfs-kernel-server nfs-common
multipass exec $VM_NAME -- sudo mkdir -p $NFS_PATH
multipass exec $VM_NAME -- sudo chown 999:999 $NFS_PATH
multipass exec $VM_NAME -- sudo chmod 700 $NFS_PATH
multipass exec $VM_NAME -- sudo bash -c "grep -q '$NFS_PATH $NETWORK_RANGE' /etc/exports || echo '$NFS_PATH $NETWORK_RANGE(rw,sync,no_subtree_check,no_root_squash)' >> /etc/exports"
multipass exec $VM_NAME -- sudo exportfs -ra
multipass exec $VM_NAME -- sudo systemctl restart nfs-kernel-server
multipass exec $VM_NAME -- sudo systemctl enable nfs-kernel-server

# Add Helm repo
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update

# Set kubeconfig
export KUBECONFIG="$HOME/.kube/config"
chmod 600 "$KUBECONFIG"

# Uninstall existing Helm release if it exists
helm uninstall nfs-subdir-external-provisioner -n nfs-provisioning 2>/dev/null || true
kubectl delete storageclass nfs-client nfs-client-retain 2>/dev/null || true

# Create a temporary Helm values file for primary StorageClass
cat <<EOF > /tmp/nfs-provisioner-values.yaml
nfs:
  server: "$NFS_IP"
  path: "$NFS_PATH"
storageClass:
  create: true
  name: nfs-client
  reclaimPolicy: Delete
  archiveOnDelete: false
EOF

# Install NFS provisioner with values file
helm upgrade --install nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  -f /tmp/nfs-provisioner-values.yaml \
  --namespace nfs-provisioning --create-namespace

# Clean up temporary values file
rm /tmp/nfs-provisioner-values.yaml

# Create secondary StorageClass (nfs-client-retain)
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-client-retain
provisioner: cluster.local/nfs-subdir-external-provisioner
reclaimPolicy: Retain
parameters:
  archiveOnDelete: "false"
EOF

# Get pods
kubectl -n nfs-provisioning get pods

# Initial delay to allow Helm to create pod
echo "Waiting 2 seconds for Helm to initialize pod..."
sleep 2

# Wait for provisioner pod to be ready (up to 120 seconds)
echo "Waiting for NFS provisioner pod to be ready (up to 120 seconds)..."
for i in {1..24}; do
    echo "Check $i: Querying for NFS provisioner pod..."
    # Log raw kubectl output for debugging
    POD_NAME_OUTPUT=$(kubectl -n nfs-provisioning get pods -l app=nfs-subdir-external-provisioner -o jsonpath="{.items[0].metadata.name}")
    if [ $? -eq 0 ]; then
        POD_NAME="$POD_NAME_OUTPUT"
        echo "Check $i: Pod found: $POD_NAME"
        POD_STATUS=$(kubectl -n nfs-provisioning get pod "$POD_NAME" -o jsonpath="{.status.phase}" 2>/dev/null)
        echo "Check $i: Pod status: $POD_STATUS"
        READY_CONDITION=$(kubectl -n nfs-provisioning get pod "$POD_NAME" -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}" 2>/dev/null)
        echo "Check $i: Pod Ready condition: $READY_CONDITION"
        if [ "$POD_STATUS" = "Running" ] && [ "$READY_CONDITION" = "True" ]; then
            echo "Check $i: Pod $POD_NAME is running and ready, exiting early"
            break
        fi
    else
        echo "Check $i: No pod found yet (kubectl error: $POD_NAME_OUTPUT)"
    fi
    sleep 5
done

# Check if pod is ready, exit if not
if [ -z "$POD_NAME" ] || [ "$POD_STATUS" != "Running" ] || [ "$READY_CONDITION" != "True" ]; then
    echo "Error: NFS provisioner pod not ready after 120 seconds"
    exit 1
fi

# Check logs
echo "Retrieving logs for pod $POD_NAME..."
kubectl -n nfs-provisioning logs "$POD_NAME"

# Get StorageClass
kubectl get storageclass

# Show exported shares
echo "Listing exported shares..."
multipass exec $VM_NAME -- showmount -e localhost || {
    echo "showmount failed. Try running 'multipass exec $VM_NAME -- showmount -e localhost' manually."
}

echo "NFS server setup complete. Test with PVC and pod."