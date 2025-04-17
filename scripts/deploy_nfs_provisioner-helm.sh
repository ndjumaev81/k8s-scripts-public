#!/bin/bash

# Set default SHARED_DIR if not provided
SHARED_DIR="${1:-~/nfsdata/shared}"

# Resolve ~ to absolute path
SHARED_DIR=$(eval echo "$SHARED_DIR")
HOST_USERNAME=$(whoami)

# Set FULL_SHARED_DIR based on whether SHARED_DIR is absolute
if [[ "$SHARED_DIR" == /* ]]; then
    FULL_SHARED_DIR="$SHARED_DIR"
else
    FULL_SHARED_DIR="$HOME/$SHARED_DIR"
fi

# Create NFS directory if it doesn't exist
sudo mkdir -p "$FULL_SHARED_DIR"

# Rest of the script remains the same
sudo chown 999:999 "$FULL_SHARED_DIR"
sudo chmod 700 "$FULL_SHARED_DIR"

# Update /etc/exports
EXPORT_LINE="$FULL_SHARED_DIR -alldirs -mapall=999:999 -network 192.168.64.0 -mask 255.255.255.0"
if ! grep -Fx "$EXPORT_LINE" /etc/exports >/dev/null; then
    echo "$EXPORT_LINE" | sudo tee -a /etc/exports
fi

# Restart NFS service
sudo nfsd restart
sudo nfsd checkexports

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
  server: 192.168.64.1
  path: "$FULL_SHARED_DIR"
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

# Check logs if pod is found
if [ -n "$POD_NAME" ]; then
    echo "Retrieving logs for pod $POD_NAME..."
    kubectl -n nfs-provisioning logs "$POD_NAME"
else
    echo "Error: Could not find NFS provisioner pod after 120 seconds"
fi

# Get StorageClass
kubectl get storageclass

# Show exported shares
echo "Listing exported shares..."
showmount -e localhost || {
    echo "showmount failed. Try running 'showmount -e localhost' manually."
}