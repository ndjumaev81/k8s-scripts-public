# Stop and Purge All Multipass VMs
multipass list
# Stop VMs:
multipass stop --all
# Delete and Purge:
multipass delete --all
multipass purge
# Verify:
multipass list

# Uninstall Multipass
brew uninstall multipass
# Remove Multipass State:
# Clear configuration and DHCP leases:
rm -rf ~/.local/share/multipass
# Verify Removal:
multipass version

# verify macos host DHCP lease file
cat /var/db/dhcpd_leases

# Clear DHCP lease database: The lease file (/var/db/dhcpd_leases) 
# contains entries up to 192.168.64.74. 
# Remove it to reset IP allocation:
sudo rm -f /var/db/dhcpd_leases

# Reinstall Multipass
brew install multipass
# Verify Installation:
multipass version
# Check Network:
multipass list