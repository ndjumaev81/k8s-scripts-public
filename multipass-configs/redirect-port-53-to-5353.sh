#!/bin/bash

# Ensure pfctl is enabled and configured to redirect port 53 to 5353
PF_CONF="/etc/pf.dns.conf"
sudo bash -c "echo 'rdr pass on lo0 proto { tcp, udp } from any to 127.0.0.1 port 53 -> 127.0.0.1 port 5353' > '$PF_CONF'"
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

# Restart mDNSResponder
sudo killall -HUP mDNSResponder

echo "mDNSResponder now forwards to dnsmasq on 127.0.0.1:5353 with fallback to default DNS."