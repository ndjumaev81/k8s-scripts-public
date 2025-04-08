echo "Stoping dnsmasq..."
sudo brew services stop dnsmasq

wait

echo "Uninstalling dnsmasq..."
brew uninstall dnsmasq

echo "Removing Config Files..."
rm -rf /opt/homebrew/etc/dnsmasq.conf
rm -rf /opt/homebrew/etc/dnsmasq.d/
rm -rf /usr/local/etc/dnsmasq.conf

echo "Reseting macOS DNS: Find your active interface..."
networksetup -listallnetworkservices

echo "Setting DNS to automatic (e.g., for Wi-Fi en0)..."
sudo networksetup -setdnsservers "Wi-Fi" empty
sudo networksetup -setdnsservers "AX88179A" empty

echo "Disabling pfctl Rules..."
sudo pfctl -d
rm -f /etc/pf.dns.conf

# Remove custom rules from /etc/pf.conf if added:
#sudo nano /etc/pf.conf

echo "Unloading Launch Agent (if created)..."
launchctl unload ~/Library/LaunchAgents/com.user.reapplydns.plist
rm ~/Library/LaunchAgents/com.user.reapplydns.plist
sudo rm /usr/local/bin/reapply-dns.sh

echo "Restarting mDNSResponder..."
sudo killall -HUP mDNSResponder

echo "Check DNS..."
nslookup google.com