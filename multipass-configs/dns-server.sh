#!/bin/bash

# Variables
DNS_VM="dns-server"
HOSTS="/etc/hosts"

# Fetch DNS from active macOS network interface, default to 8.8.8.8
UPSTREAM_DNS=$(scutil --dns | grep 'nameserver\[0\]' | head -n 1 | awk '{print $3}')
if [ -z "$UPSTREAM_DNS" ]; then
    UPSTREAM_DNS="8.8.8.8"
fi

echo "DNS servers: $UPSTREAM_DNS"

# Parse command-line argument for upstream DNS
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dns) UPSTREAM_DNS="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Ensure Bash version (3.2 is fine, but check for < 3)
if [ "${BASH_VERSINFO[0]}" -lt 3 ]; then
    echo "Error: Bash 3.0+ required. Update Bash."
    exit 1
fi

# Check if dns-server exists
if ! multipass info "$DNS_VM" &>/dev/null; then
    multipass launch --name "$DNS_VM" --cpus 1 --memory 512M --disk 4G
else
    multipass start "$DNS_VM"
fi

# Check if CoreDNS is installed; install ARM64 version if missing
if ! multipass exec "$DNS_VM" -- test -f /usr/local/bin/coredns; then
    multipass exec "$DNS_VM" -- sudo apt update
    multipass exec "$DNS_VM" -- sudo apt install -y wget
    multipass exec "$DNS_VM" -- sudo wget -O /tmp/coredns.tar.gz https://github.com/coredns/coredns/releases/download/v1.11.1/coredns_1.11.1_linux_arm64.tgz
    multipass exec "$DNS_VM" -- sudo bash -c "cd /usr/local/bin && tar -xzf /tmp/coredns.tar.gz"
    multipass exec "$DNS_VM" -- sudo chmod +x /usr/local/bin/coredns
    multipass exec "$DNS_VM" -- sudo rm /tmp/coredns.tar.gz
    multipass exec "$DNS_VM" -- sudo mkdir -p /etc/coredns
fi

# Wait for VM to be ready
sleep 5

# Stop systemd-resolved and any old CoreDNS
multipass exec "$DNS_VM" -- sudo systemctl stop systemd-resolved 2>/dev/null
multipass exec "$DNS_VM" -- sudo systemctl disable systemd-resolved 2>/dev/null
multipass exec "$DNS_VM" -- sudo rm -f /etc/resolv.conf
multipass exec "$DNS_VM" -- sudo bash -c "echo 'nameserver $UPSTREAM_DNS' > /etc/resolv.conf"
multipass exec "$DNS_VM" -- sudo pkill -9 -f coredns 2>/dev/null
sleep 2  # Ensure old process terminates

# Get current IPs (required VMs)
DNS_IP=$(multipass info "$DNS_VM" | grep IPv4 | awk '{print $2}')
K8S_MASTER_IP=""
if multipass info k8s-master &>/dev/null; then
    K8S_MASTER_IP=$(multipass info k8s-master | grep IPv4 | awk '{print $2}')
fi

# Check and get IPs for optional workers if running
WORKER_IPS=()
WORKER_NAMES=()
for i in {1..4}; do
    VM="k8s-worker-$i"
    if multipass info "$VM" &>/dev/null; then
        IP=$(multipass info "$VM" | grep IPv4 | awk '{print $2}')
        WORKER_IPS+=("$IP")
        WORKER_NAMES+=("$VM")
    fi
done

# Build CoreDNS hosts block dynamically
HOSTS_BLOCK="$DNS_IP dns-server.loc"
if [ -n "$K8S_MASTER_IP" ]; then
    HOSTS_BLOCK="$K8S_MASTER_IP k8s-master.loc
        $HOSTS_BLOCK"
fi
for i in "${!WORKER_IPS[@]}"; do
    HOSTS_BLOCK="${WORKER_IPS[$i]} ${WORKER_NAMES[$i]}.loc
        $HOSTS_BLOCK"
done

# Update CoreDNS Corefile
multipass exec "$DNS_VM" -- sudo bash -c "cat > /etc/coredns/Corefile" << EOF
.:53 {
    hosts {
        $HOSTS_BLOCK
        fallthrough
    }
    forward . $UPSTREAM_DNS
    log
    errors
}
EOF

# Run CoreDNS manually, suppress output
if ! multipass exec "$DNS_VM" -- sudo ss -tulnp | grep -q :53; then
    multipass exec "$DNS_VM" -- sudo nohup /usr/local/bin/coredns -conf /etc/coredns/Corefile >/dev/null 2>&1 &
else
    echo "Port 53 still in use. Check with 'multipass exec dns-server -- sudo ss -tulnp | grep :53'."
    exit 1
fi

# Configure DNS on k8s-master
if [ -n "$K8S_MASTER_IP" ]; then
    multipass exec k8s-master -- sudo systemctl stop systemd-resolved 2>/dev/null
    multipass exec k8s-master -- sudo systemctl disable systemd-resolved 2>/dev/null
    multipass exec k8s-master -- sudo rm -f /etc/resolv.conf  # Remove symlink
    multipass exec k8s-master -- sudo bash -c "echo 'nameserver $DNS_IP' > /etc/resolv.conf"
fi

# Configure DNS on workers
for VM in "${WORKER_NAMES[@]}"; do
    multipass exec "$VM" -- sudo systemctl stop systemd-resolved 2>/dev/null
    multipass exec "$VM" -- sudo systemctl disable systemd-resolved 2>/dev/null
    multipass exec "$VM" -- sudo rm -f /etc/resolv.conf  # Remove symlink
    multipass exec "$VM" -- sudo bash -c "echo 'nameserver $DNS_IP' > /etc/resolv.conf"
done

# Update /etc/hosts on host: remove only lines with #multipass, append new entries with #multipass
sudo sed -i '' '/#multipass$/d' "$HOSTS"
multipass list | tail -n +2 | while read -r name state ip _; do
    if [[ "$state" == "Running" && "$ip" =~ ^192\.168\.64\.[0-9]+$ ]]; then
        echo "$ip $name.loc #multipass" | sudo tee -a "$HOSTS"
    fi
done

# Debug CoreDNS
echo "Current IPs: DNS=$DNS_IP, Master=$K8S_MASTER_IP"
echo "Using upstream DNS: $UPSTREAM_DNS"
echo "CoreDNS Corefile:"
multipass exec "$DNS_VM" -- cat /etc/coredns/Corefile
echo "Verifying resolution from k8s-master:"
if [ -n "$K8S_MASTER_IP" ]; then
    multipass exec k8s-master -- nslookup dns-server.loc $DNS_IP
    multipass exec k8s-master -- ping -c 4 google.com
fi

echo "Host /etc/hosts:"
cat "$HOSTS"

echo "CoreDNS VM launched at $DNS_IP. Hosts file updated."