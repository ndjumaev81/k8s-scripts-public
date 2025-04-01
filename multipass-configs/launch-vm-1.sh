#!/bin/bash

# Default VM name if not provided
VM_NAME=""

# Check if all 4 arguments are provided
if [ "$#" -lt 4 ]; then
  echo "Usage: $0 <IP_last_octet> <CPUs> <Memory_GB> <Disk_GB> [VM_name]"
  echo "Example: $0 10 2 4 20 custom"
  exit 1
fi

# Assign arguments to variables
IP_OCTET=$1
CPUS=$2
MEMORY=$3
DISK=$4

# Assign optional VM name if provided
if [ "$#" -eq 5 ]; then
  VM_NAME=$5
fi

VM_FULL_NAME="k8s-$VM_NAME-$IP_OCTET"

# Launch the VM with specified resources [Ubuntu 24.04 LTS]
multipass launch --name "$VM_FULL_NAME" \
  --cpus "$CPUS" \
  --memory "${MEMORY}G" \
  --disk "${DISK}G" \
  24.04

# Get the DHCP-assigned IP to remove it
DHCP_IP=$(multipass list | grep "$VM_FULL_NAME" | awk '{print $3}' | head -n 1)

# Add specific additional static IP
#multipass exec "$VM_FULL_NAME" -- bash -c "\
#  sudo ip addr add 192.168.64.$IP_OCTET/24 dev enp0s1 || true"