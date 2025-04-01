#!/bin/bash

# Usage message
usage() {
    echo "Usage: $0 <vm-name-suffix> <cpus> <memory-in-gb> <disk-in-gb>"
    echo "Example: $0 master 2 4 20"
    exit 1
}

# Check if all required arguments are provided
if [ $# -ne 4 ]; then
    usage
fi

# Assign arguments
VM_SUFFIX=$1
#IP_ADDRESS=$2
CPUS=$2
MEMORY=$3
DISK=$4

# Validate numeric inputs
if ! [[ "$CPUS" =~ ^[0-9]+$ ]] || ! [[ "$MEMORY" =~ ^[0-9]+$ ]] || ! [[ "$DISK" =~ ^[0-9]+$ ]]; then
    echo "Error: CPUs, Memory, and Disk must be numeric values"
    exit 1
fi

# Validate IP address format (basic check)
#if ! [[ "$IP_ADDRESS" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
#    echo "Error: Invalid IP address format"
#    exit 1
#fi

# Construct full VM name with k8s- prefix
VM_NAME="k8s-${VM_SUFFIX}"

# Launch the VM with the generated cloud-init file and arguments
multipass launch --name "${VM_NAME}" --cpus "${CPUS}" --memory "${MEMORY}G" --disk "${DISK}G" 24.04

# Output result
echo "Launched VM: ${VM_NAME} with CPUs: ${CPUS}, Memory: ${MEMORY}G, Disk: ${DISK}G"