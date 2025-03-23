#!/bin/bash

# Usage message
usage() {
    echo "Usage: $0 <vm-name-suffix> <ip-address> <cpus> <memory-in-gb> <disk-in-gb>"
    echo "Example: $0 master 192.168.64.1 2 4 20"
    exit 1
}

# Check if all required arguments are provided
if [ $# -ne 5 ]; then
    usage
fi

# Assign arguments
VM_SUFFIX=$1
IP_ADDRESS=$2
CPUS=$3
MEMORY=$4
DISK=$5

# Validate numeric inputs
if ! [[ "$CPUS" =~ ^[0-9]+$ ]] || ! [[ "$MEMORY" =~ ^[0-9]+$ ]] || ! [[ "$DISK" =~ ^[0-9]+$ ]]; then
    echo "Error: CPUs, Memory, and Disk must be numeric values"
    exit 1
fi

# Validate IP address format (basic check)
if ! [[ "$IP_ADDRESS" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid IP address format"
    exit 1
fi

# Construct full VM name with k8s- prefix
VM_NAME="k8s-${VM_SUFFIX}"

# Generate cloud-init.yaml with the provided values
cat <<EOF > cloud-init.yaml
#cloud-config
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh-authorized-keys:
      - $(cat ~/.ssh/id_rsa.pub)  # Your SSH public key
network:
  version: 2
  ethernets:
    enp0s1:
      dhcp4: false
      addresses:
        - ${IP_ADDRESS}/24
      gateway4: 192.168.64.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
EOF

# Launch the VM with the generated cloud-init file and arguments
multipass launch --name "${VM_NAME}" --cpus "${CPUS}" --memory "${MEMORY}G" --disk "${DISK}G" --arch amd64 --cloud-init cloud-init.yaml

# Output result
echo "Launched VM: ${VM_NAME} with IP: ${IP_ADDRESS}, CPUs: ${CPUS}, Memory: ${MEMORY}G, Disk: ${DISK}G"