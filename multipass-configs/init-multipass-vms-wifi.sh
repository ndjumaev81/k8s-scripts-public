#!/bin/bash

# Get the current user (to run Multipass as this user, not root)
CURRENT_USER=$(whoami)
echo "Current user: $CURRENT_USER"

# Install dnsmasq if not installed
if ! command -v dnsmasq &> /dev/null; then
    brew install dnsmasq
fi

# Ensure dnsmasq config directory exists
DNSMASQ_CONF="/usr/local/etc/dnsmasq.conf"
DNSMASQ_HOSTS="/usr/local/etc/dnsmasq.d/multipass_hosts"

# Ensure dnsmasq config directory exists (sudo for root-owned paths)
sudo mkdir -p "$(dirname "$DNSMASQ_HOSTS")"
sudo touch "$DNSMASQ_HOSTS"

# Configure dnsmasq with upstream servers
sudo bash -c "cat <<EOF > '$DNSMASQ_CONF'
server=8.8.8.8
server=8.8.4.4
addn-hosts=$DNSMASQ_HOSTS
listen-address=127.0.0.1
port=5353
bind-interfaces
no-resolv
EOF"

# Generate hosts file from running Multipass VMs
sudo bash -c "echo '# Multipass VM hostnames' > '$DNSMASQ_HOSTS'"
multipass list | tail -n +2 | while read -r name _ ip _; do
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        sudo bash -c "echo '$ip ${name}.loc' >> '$DNSMASQ_HOSTS'"
    fi
done

# Sync hosts to VMs
multipass list | tail -n +2 | while read -r name _ ip _; do
   if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
       multipass exec "$name" -- sudo sh -c "echo '$ip ${name}.loc' >> /etc/hosts"
   fi
done

# Restart dnsmasq with sudo to ensure it runs as root
sudo pkill -f dnsmasq  # Kill any lingering processes
brew services stop dnsmasq 2>/dev/null || true  # Try user-level stop, ignore errors
sudo brew services stop dnsmasq 2>/dev/null || true  # Try root-level stop, ignore errors
sleep 1  # Brief pause to ensure processes terminate

# Start dnsmasq on port 5353
sudo /opt/homebrew/opt/dnsmasq/sbin/dnsmasq -C "$DNSMASQ_CONF" &
sleep 5  # Increased delay for reliability

# Detect active network interface (clean IP parsing)
ACTIVE_INTERFACE=$(networksetup -listallnetworkservices | while read -r service; do
    ip=$(networksetup -getinfo "$service" | grep "IP address" | awk '{print $3}' | head -n1)
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$service"
        break
    fi
done)

# Option 1:
# Reset all common interfaces to DHCP
#for INTERFACE in "Wi-Fi" "AX88179A" "Thunderbolt Bridge"; do
#    sudo networksetup -setdhcp "$INTERFACE"
#done
#sudo killall -HUP mDNSResponder
#echo "DNS set to DHCP for all interfaces; use 127.0.0.1:5353 for local domains"


# Option 2:
# Reset all active network interfaces to DHCP
networksetup -listallnetworkservices | grep -v '^\*' | grep -v "An asterisk" | while read -r INTERFACE; do
    sudo networksetup -setdhcp "$INTERFACE"
done
sudo killall -HUP mDNSResponder
echo "DNS set to DHCP for all active interfaces; use 127.0.0.1:5353 for local domains"

# Option 3:
# Set DNS to DHCP for internet
#if [ -n "$ACTIVE_INTERFACE" ]; then
#    sudo networksetup -setdhcp "$ACTIVE_INTERFACE"
#    sudo killall -HUP mDNSResponder
#    echo "DNS set to DHCP for $ACTIVE_INTERFACE; use 127.0.0.1:5353 for local domains"
#else
#    echo "No active interface found. Set DNS manually."
#fi

# Output created dnsmasq records for verification
echo "Created DNS records:"
cat "$DNSMASQ_HOSTS"

# Verify dnsmasq is running and listening
echo "Checking dnsmasq status..."
sudo lsof -i :5353

# Verify active interface details
echo "Active interface details:"
networksetup -getinfo "$ACTIVE_INTERFACE"

# Test DNS resolution
echo "Testing DNS resolution..."
dig @127.0.0.1 -p 5353 k8s-master.loc
#dig @8.8.8.8 google.com
dig google.com  # Use system DNS instead of direct 8.8.8.8


# Reset Wi-Fi DNS:
#sudo networksetup -setdhcp "Wi-Fi"
#sudo killall -HUP mDNSResponder
#sudo dscacheutil -flushcache

# Verify:
#networksetup -getdnsservers "Wi-Fi"
#ping google.com

# Scenario 1:
# Check current DNS:
#scutil --dns
# Look for nameserver[0] under your active interface (e.g., AX88179A or Wi-Fi).

# If it’s not what you expect (e.g., 127.0.0.1 instead of DHCP), reset to DHCP:
#sudo networksetup -setdhcp "AX88179A"
#sudo networksetup -setdhcp "Wi-Fi"
#sudo killall -HUP mDNSResponder  # Refresh again with new settings

# Scenario 2:
# Restart mDNSResponder to Previous State
# Restart Fully:
#sudo launchctl kickstart -k system/com.apple.mDNSResponder
# This stops and restarts mDNSResponder, reloading it from its default config (/System/Library/LaunchDaemons/com.apple.mDNSResponder.plist).

# Verify:
#sudo lsof -i :53
# Should show mDNSResponder

#ping google.com
# Should work if DNS is set correctly