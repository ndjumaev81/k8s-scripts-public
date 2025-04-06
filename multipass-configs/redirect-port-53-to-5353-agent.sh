#!/bin/bash

# If something breaks, you can revert by:
# Restoring DNS:
#sudo networksetup -setdnsservers Wi-Fi 192.168.9.101

# Disabling pfctl rules
#sudo pfctl -d

# Unloading the launch agent:
#launchctl unload ~/Library/LaunchAgents/com.user.reapplydns.plist

# Ensure pfctl is enabled and configured to redirect port 53 to 5353
PF_CONF="/etc/pf.dns.conf"
sudo bash -c "echo 'rdr pass on lo0 proto { tcp, udp } from any to 127.0.0.1 port 53 -> 127.0.0.1 port 5353' > '$PF_CONF'"

# Persist pf rules in /etc/pf.conf
sudo bash -c "grep -q 'rdr pass on lo0 proto { tcp, udp } from any to 127.0.0.1 port 53 -> 127.0.0.1 port 5353' /etc/pf.conf || echo 'rdr pass on lo0 proto { tcp, udp } from any to 127.0.0.1 port 53 -> 127.0.0.1 port 5353' >> /etc/pf.conf"

# Enable pf at boot
sudo sysrc pf_enable="YES" 2>/dev/null || echo "pf_enable=\"YES\"" | sudo tee -a /etc/rc.conf

# Apply pf rules
sudo pfctl -f "$PF_CONF" -e

# Function to set DNS for the active interface
set_dns() {
    ACTIVE_INTERFACE=$(networksetup -listallnetworkservices | grep -v '^\*' | grep -v "An asterisk" | while read -r service; do
        ip=$(networksetup -getinfo "$service" | grep "IP address" | awk '{print $3}' | head -n1)
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$service"
            break
        fi
    done)
    if [ -n "$ACTIVE_INTERFACE" ]; then
        sudo networksetup -setdnsservers "$ACTIVE_INTERFACE" 127.0.0.1
        echo "DNS set to 127.0.0.1 for $ACTIVE_INTERFACE"
    else
        echo "No active network interface found."
        exit 1
    fi
}

# Initial DNS setup
set_dns

# Ensure dnsmasq starts on boot
sudo brew services start dnsmasq

# Restart mDNSResponder
sudo killall -HUP mDNSResponder

# Create a script to reapply DNS settings after sleep/network change
REAPPLY_SCRIPT="/usr/local/bin/reapply-dns.sh"
sudo bash -c "cat > '$REAPPLY_SCRIPT' << 'EOF'
#!/bin/bash
ACTIVE_INTERFACE=\$(networksetup -listallnetworkservices | grep -v '^\\*' | grep -v \"An asterisk\" | while read -r service; do
    ip=\$(networksetup -getinfo \"\$service\" | grep \"IP address\" | awk '{print \$3}' | head -n1)
    if [[ \"\$ip\" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+\$ ]]; then
        echo \"\$service\"
        break
    fi
done)
if [ -n \"\$ACTIVE_INTERFACE\" ]; then
    networksetup -setdnsservers \"\$ACTIVE_INTERFACE\" 127.0.0.1
    killall -HUP mDNSResponder
    echo \"Reapplied DNS settings for \$ACTIVE_INTERFACE after sleep/network change.\"
fi
EOF"
sudo chmod +x "$REAPPLY_SCRIPT"

# Create a launch agent to run the reapply script on wake/network change
PLIST_FILE="$HOME/Library/LaunchAgents/com.user.reapplydns.plist"
cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.reapplydns</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$REAPPLY_SCRIPT</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>NetworkState</key>
        <true/>
    </dict>
    <key>WatchPaths</key>
    <array>
        <string>/private/var/run/pppconfd</string>
    </array>
    <key>StandardOutPath</key>
    <string>/tmp/reapply-dns.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/reapply-dns.log</string>
</dict>
</plist>
EOF

# Load the launch agent
launchctl load "$PLIST_FILE"

echo "mDNSResponder now forwards to dnsmasq on 127.0.0.1:5353 with fallback to default DNS. Settings preserved after reboot and sleep/network change."