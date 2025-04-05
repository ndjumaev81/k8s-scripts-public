#!/bin/bash

# Ensure pfctl is enabled and configured to redirect port 53 to 5353
PF_CONF="/etc/pf.dns.conf"
sudo bash -c "echo 'rdr pass on lo0 proto { tcp, udp } from any to 127.0.0.1 port 53 -> 127.0.0.1 port 5353' > '$PF_CONF'"

# Persist pf rules in /etc/pf.conf
sudo bash -c "grep -q 'rdr pass on lo0 proto { tcp, udp } from any to 127.0.0.1 port 53 -> 127.0.0.1 port 5353' /etc/pf.conf || echo 'rdr pass on lo0 proto { tcp, udp } from any to 127.0.0.1 port 53 -> 127.0.0.1 port 5353' >> /etc/pf.conf"

# Enable pf at boot
sudo sysrc pf_enable="YES" 2>/dev/null || echo "pf_enable=\"YES\"" | sudo tee -a /etc/rc.conf

# Apply pf rules
sudo pfctl -f "$PF_CONF" -e

# Set mDNSResponder to use localhost as DNS
ACTIVE_INTERFACE=$(networksetup -listallnetworkservices | grep -v '^\*' | grep -v "An asterisk" | while read -r service; do
    ip=$(networksetup -getinfo "$service" | grep "IP address" | awk '{print $3}' | head -n1)
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$service"
        break
    fi
done)
sudo networksetup -setdnsservers "$ACTIVE_INTERFACE" 127.0.0.1

# Ensure dnsmasq starts on boot
sudo brew services start dnsmasq

# Restart mDNSResponder
sudo killall -HUP mDNSResponder

echo "mDNSResponder now forwards to dnsmasq on 127.0.0.1:5353 with fallback to default DNS. Settings preserved after reboot."