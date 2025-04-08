# Stop the Multipass Daemon:
sudo launchctl stop com.canonical.multipass 2>/dev/null
sudo launchctl remove com.canonical.multipass 2>/dev/null
sudo rm -f /Library/LaunchDaemons/com.canonical.multipass.plist

 # Remove the Application:
sudo rm -rf /Applications/Multipass.app

 # Remove the CLI Binary:
sudo rm -f /usr/local/bin/multipass

# Clean Up Configuration and Data:
rm -rf ~/Library/Application\ Support/multipass*
rm -rf ~/Library/Preferences/multipass*
rm -rf ~/Library/Caches/multipass*
rm -rf ~/.multipass
sudo rm -rf /var/root/Library/Application\ Support/multipassd

# Verify Removal:
which multipass
multipass version