#!/bin/bash

# Stop dnsmasq instances
echo "Stopping dnsmasq..."
sudo pkill -f dnsmasq
brew services stop dnsmasq 2>/dev/null || true
sudo brew services stop dnsmasq 2>/dev/null || true
sleep 1
if sudo lsof -i :53 | grep -q dnsmasq; then
    echo "Warning: dnsmasq still running on port 53, forcing stop..."
    sudo killall -KILL dnsmasq 2>/dev/null || true
    sleep 1
fi

# Re-enable mDNSResponder
echo "Re-enabling mDNSResponder..."
# If disabled, enable it first
if sudo launchctl print-disabled system | grep -q "com.apple.mDNSResponder.*=> true"; then
    sudo launchctl enable system/com.apple.mDNSResponder
fi
# Stop any running instance
if sudo lsof -i :53 | grep -q mDNSRespo; then
    sudo killall -TERM mDNSResponder 2>/dev/null || true
    sleep 1
fi
# Start or restart mDNSResponder
sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.mDNSResponder.plist 2>/dev/null || \
    sudo launchctl kickstart -k system/com.apple.mDNSResponder
sleep 2
# Verify mDNSResponder is running
if ! sudo lsof -i :53 | grep -q mDNSRespo; then
    echo "Error: Failed to start mDNSResponder on port 53."
    exit 1
fi

# Reset all active network interfaces to DHCP
echo "Resetting network interfaces to DHCP..."
networksetup -listallnetworkservices | grep -v '^\*' | grep -v "An asterisk" | while read -r INTERFACE; do
    sudo networksetup -setdhcp "$INTERFACE"
    echo "Set $INTERFACE to DHCP"
done
sudo killall -HUP mDNSResponder
sudo dscacheutil -flushcache

echo "dnsmasq disabled; mDNSResponder re-enabled with DHCP DNS for all active interfaces"

# Verify mDNSResponder is running and listening on port 53
echo "Checking mDNSResponder status..."
sudo lsof -i :53

# Verify no dnsmasq on port 5353 (or 53)
echo "Checking for residual dnsmasq..."
sudo lsof -i :5353
sudo lsof -i :53 | grep dnsmasq || echo "No dnsmasq detected on port 53"

# Test system DNS resolution
echo "Testing system DNS resolution..."
dig google.com

# Verify DNS settings
echo "Current DNS settings:"
scutil --dns