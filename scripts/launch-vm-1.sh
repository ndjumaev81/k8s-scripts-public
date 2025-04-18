#!/bin/bash

# Default VM name if not provided
VM_NAME=""

# Check if all 3 arguments are provided
if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <CPUs> <Memory_GB> <Disk_GB> [VM_name]"
  echo "Example: $0 2 4 20 custom"
  exit 1
fi

# Assign arguments to variables
CPUS=$1
MEMORY=$2
DISK=$3

# Assign optional VM name if provided
if [ "$#" -eq 4 ]; then
  VM_NAME=$4
fi

VM_FULL_NAME="k8s-$VM_NAME"

# Launch the VM with specified resources [Ubuntu 24.04 LTS]
multipass launch --name "$VM_FULL_NAME" \
  --cpus "$CPUS" \
  --memory "${MEMORY}G" \
  --disk "${DISK}G" \
  24.04

# Get the DHCP-assigned IP to remove it
DHCP_IP=$(multipass list | grep "$VM_FULL_NAME" | awk '{print $3}' | head -n 1)

echo "Assigned IP address: $DHCP_IP"

# Install nfs-common on the new VM
echo "Installing nfs-common on $VM_FULL_NAME..."
multipass exec $VM_FULL_NAME -- sudo apt update
multipass exec $VM_FULL_NAME -- sudo apt install -y nfs-common

# Verify nfs-common installation
if multipass exec $VM_FULL_NAME -- dpkg -l | grep -q nfs-common; then
  echo "nfs-common successfully installed on $VM_FULL_NAME"
else
  echo "Error: Failed to install nfs-common on $VM_FULL_NAME"
  exit 1
fi

echo "Multipass VM installation complete."