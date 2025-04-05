# Reset Network Settings:
# reset DNS and flush caches:

sudo networksetup -setdhcp "AX88179A"
sudo networksetup -setdnsservers "AX88179A" empty
sudo killall -HUP mDNSResponder
sudo dscacheutil -flushcache

# Verify
ping google.com

#scutil --dns

# "Wi-Fi"
sudo networksetup -setdhcp "Wi-Fi"
sudo networksetup -setdnsservers "Wi-Fi" empty
sudo killall -HUP mDNSResponder
sudo dscacheutil -flushcache


# To check the DNS service running on your macOS system over Wi-Fi:
# Verify active DNS servers:
networksetup -getdnsservers Wi-Fi
# This should show 127.0.0.1 (dnsmasq) if your setup is active.

# Check dnsmasq process:
sudo lsof -i :5353
# If dnsmasq is running on port 5353, you’ll see it listening.

# Confirm mDNSResponder:
ps aux | grep mDNSResponder
# This confirms mDNSResponder is active (it always is on macOS).

# Test resolution:
dig @127.0.0.1 -p 53 k8s-master.loc
# If dnsmasq answers, your setup is working.
# Your Wi-Fi DNS should route through 127.0.0.1:5353 (dnsmasq) to 192.168.0.1 (network DNS).