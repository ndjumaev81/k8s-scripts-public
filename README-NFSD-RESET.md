# To reset and disable the macOS nfsd service:
# Stop NFS Service:
sudo nfsd stop

# Disable NFS Service:
sudo nfsd disable
#sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.nfsd.plist

# Stop and Disable rpcbind:
sudo launchctl stop com.apple.rpcbind
#sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.rpcbind.plist

# Clear /etc/exports:
sudo mv /etc/exports /etc/exports.bak 2>/dev/null || true
sudo touch /etc/exports

# Verify Services Are Stopped:
sudo nfsd status
rpcinfo -p localhost
# (Should show no NFS or rpcbind services running.)

# Optional: Remove NFS Logs:
sudo rm /var/log/nfsd.log 2>/dev/null || true

# This fully disables nfsd and related services, resetting the configuration. Reboot to ensure changes take effect:
sudo reboot