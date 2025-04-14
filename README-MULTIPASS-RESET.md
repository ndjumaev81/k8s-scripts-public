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


# Reinstall Multipass
brew install multipass
# Verify Installation:
multipass version
# Check Network:
multipass list