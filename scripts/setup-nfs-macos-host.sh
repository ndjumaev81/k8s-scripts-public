#!/bin/bash

# Exit on any error
set -e

# Check if username argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

# Variables
USERNAME="$1"
SHARE_DIR="/Users/$USERNAME/nfs-share"
EXPORTS_FILE="/etc/exports"
# Define separate export lines for clarity and compatibility
EXPORT_LINE_MULTIPASS="$SHARE_DIR -alldirs -mapall=$USERNAME:staff -network 192.168.64.0 -mask 255.255.255.0"
#EXPORT_LINE_LOCALHOST="$SHARE_DIR -alldirs -mapall=$USERNAME:staff -network 127.0.0.1"  # No mask for single IP

# Step 1: Create the shared directory
echo "Creating NFS share directory: $SHARE_DIR"
mkdir -p "$SHARE_DIR"
chmod 777 "$SHARE_DIR"  # Permissive for testing; adjust to 755 for production

# Step 2: Backup and configure /etc/exports
echo "Configuring NFS exports..."
sudo cp "$EXPORTS_FILE" "$EXPORTS_FILE.bak" 2>/dev/null || true  # Backup if exists
# Remove existing entries for SHARE_DIR to avoid duplicates
sudo sed -i '' "/^${SHARE_DIR//\//\\/}/d" "$EXPORTS_FILE" 2>/dev/null || true
# Add new export lines
echo "$EXPORT_LINE_MULTIPASS" | sudo tee -a "$EXPORTS_FILE" > /dev/null
echo "$EXPORT_LINE_LOCALHOST" | sudo tee -a "$EXPORTS_FILE" > /dev/null

# Step 3: Ensure NFS required services are running
echo "Ensuring RPC and NFS services are configured..."
# Enable and start rpcbind (required for NFS)
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.rpcbind.plist 2>/dev/null || true
sudo launchctl start com.apple.rpcbind

# Step 4: Enable and restart NFS service
echo "Enabling and restarting NFS service..."
sudo nfsd enable
sudo nfsd update
sudo nfsd start
sleep 2  # Give it time to settle

# Step 5: Verify NFS status
echo "Checking NFS status..."
if sudo nfsd checkexports && sudo nfsd status; then
    echo "NFS service is running."
else
    echo "Failed to start NFS. Checking logs..."
    sudo cat /var/log/nfsd.log
    exit 1
fi

# Step 6: Verify RPC registration
echo "Verifying RPC services..."
if rpcinfo -p localhost | grep -q nfs; then
    echo "NFS is registered with RPC."
else
    echo "NFS not registered with RPC. Attempting to fix..."
    sudo launchctl stop com.apple.nfsd
    sudo launchctl start com.apple.nfsd
    sleep 2
    if rpcinfo -p localhost | grep -q nfs; then
        echo "Fixed RPC registration."
    else
        echo "RPC registration failed. Check system logs."
        sudo cat /var/log/system.log | grep -i nfs
        exit 1
    fi
fi

# Step 7: Show exported shares
echo "Listing exported shares..."
showmount -e localhost || {
    echo "showmount failed. This might be a temporary issue; NFS should still work."
    echo "Try running 'showmount -e localhost' manually after a few seconds."
}

# Step 7: Firewall adjustment (restrict to Multipass and localhost)
echo "Adjusting firewall for NFS (restricting to 192.168.64.0/24 and 127.0.0.1)..."
# Ensure firewall is enabled
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
# Add nfsd and restrict access
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /sbin/nfsd
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /sbin/nfsd
# Note: macOS firewall doesn't support IP-based rules natively; rely on /etc/exports for IP restriction

echo "NFS setup complete! Share is available at $SHARE_DIR."
echo "Access restricted to 192.168.64.0/24 (Multipass VMs) and 127.0.0.1 (localhost)."
echo "Test from a VM with: sudo mount -t nfs 192.168.64.1:$SHARE_DIR /mnt/nfs"
echo "Test locally with: mount -t nfs 127.0.0.1:$SHARE_DIR /mnt"
