#!/bin/bash

# Commands to verify that CoreDns installed and running
# Check if CoreDNS is running:
#ps aux | grep coredns
# Test DNS resolution locally:
#nslookup google.com 127.0.0.1

# Variables
DNS_VM="dns-server"
HOSTS="/etc/hosts"

# Fetch DNS from active macOS network interface, default to 8.8.8.8
UPSTREAM_DNS=$(scutil --dns | grep 'nameserver\[0\]' | head -n 1 | awk '{print $3}')
if [[ -z "$UPSTREAM_DNS" || "$UPSTREAM_DNS" =~ ^fe80:: ]]; then
    # Check if LAN DNS is reachable
    if ping -c 1 192.168.9.101 &>/dev/null; then
        UPSTREAM_DNS="192.168.9.101"
    else
        UPSTREAM_DNS="8.8.8.8"
    fi
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
#multipass exec "$DNS_VM" -- sudo bash -c "echo 'nameserver $UPSTREAM_DNS' > /etc/resolv.conf"
multipass exec "$DNS_VM" -- sudo bash -c "echo 'nameserver 127.0.0.1' > /etc/resolv.conf"

# Stop CoreDNS if running (to avoid port 53 conflict)
multipass exec "$DNS_VM" -- sudo systemctl stop coredns 2>/dev/null
multipass exec "$DNS_VM" -- sudo pkill -9 -f coredns 2>/dev/null
sleep 2  # Ensure old process terminates

# Get current IPs for all running VMs dynamically
DNS_IP=$(multipass info "$DNS_VM" | grep IPv4 | awk '{print $2}')
ALL_VMS=()
ALL_IPS=()
while read -r name state ip _; do
    if [[ "$state" == "Running" && "$ip" =~ ^192\.168\.64\.[0-9]+$ ]]; then
        ALL_VMS+=("$name")
        ALL_IPS+=("$ip")
    fi
done < <(multipass list | tail -n +2)

# Build CoreDNS hosts block dynamically
HOSTS_BLOCK=""
for i in "${!ALL_VMS[@]}"; do
    if [ "${ALL_VMS[$i]}" == "$DNS_VM" ]; then
        HOSTS_BLOCK="$DNS_IP dns-server.loc"
    else
        HOSTS_BLOCK="${ALL_IPS[$i]} ${ALL_VMS[$i]}.loc
$HOSTS_BLOCK"
    fi
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

# Ensure CoreDNS systemd service exists
if ! multipass exec "$DNS_VM" -- sudo test -f /etc/systemd/system/coredns.service; then
    multipass exec "$DNS_VM" -- sudo bash -c "cat > /etc/systemd/system/coredns.service" << EOF
[Unit]
Description=CoreDNS DNS Server
After=network.target

[Service]
ExecStart=/usr/local/bin/coredns -conf /etc/coredns/Corefile
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
fi

# Start CoreDNS
multipass exec "$DNS_VM" -- sudo systemctl daemon-reload
multipass exec "$DNS_VM" -- sudo systemctl enable coredns
multipass exec "$DNS_VM" -- sudo systemctl start coredns

# Configure DNS on all VMs except dns-server
for vm in "${ALL_VMS[@]}"; do
    if [ "$vm" != "$DNS_VM" ]; then
        multipass exec "$vm" -- sudo systemctl stop systemd-resolved 2>/dev/null
        multipass exec "$vm" -- sudo systemctl disable systemd-resolved 2>/dev/null
        multipass exec "$vm" -- sudo rm -f /etc/resolv.conf  # Remove symlink
        multipass exec "$vm" -- sudo bash -c "echo 'nameserver $DNS_IP' > /etc/resolv.conf"
    fi
done

# Update /etc/hosts on host: remove only lines with #multipass, append new entries with #multipass
sudo sed -i '' '/#multipass$/d' "$HOSTS"
for i in "${!ALL_VMS[@]}"; do
    echo "${ALL_IPS[$i]} ${ALL_VMS[$i]}.loc #multipass" | sudo tee -a "$HOSTS"
done

# Debug CoreDNS
echo "Current IPs: DNS=$DNS_IP"
echo "All VMs and IPs: ${ALL_VMS[@]} -> ${ALL_IPS[@]}"
echo "Using upstream DNS: $UPSTREAM_DNS"
echo "CoreDNS Corefile:"
multipass exec "$DNS_VM" -- cat /etc/coredns/Corefile
echo "Verifying resolution from k8s-master (if exists):"
for vm in "${ALL_VMS[@]}"; do
    if [ "$vm" == "k8s-master" ]; then
        multipass exec k8s-master -- nslookup dns-server.loc $DNS_IP
        multipass exec k8s-master -- ping -c 4 google.com
    fi
done

echo "Host /etc/hosts:"
cat "$HOSTS"

echo "CoreDNS VM launched at $DNS_IP. Hosts file updated."