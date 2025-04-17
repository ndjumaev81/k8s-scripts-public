#!/bin/bash

# Exit on any error
set -e

# Step 1: Ensure rpcbind is running (required for NFS)
echo "Checking if rpcbind is running..."
if ! sudo launchctl list com.apple.rpcbind >/dev/null 2>&1; then
    echo "Starting rpcbind..."
    sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.rpcbind.plist
    sudo launchctl start com.apple.rpcbind
    sleep 1
    if ! sudo launchctl list com.apple.rpcbind >/dev/null 2>&1; then
        echo "Warning: Failed to start rpcbind. Checking logs..."
        log show --predicate 'subsystem == "com.apple.rpcbind"' --last 10m --info --debug
    else
        echo "rpcbind started successfully."
    fi
else
    echo "rpcbind is already running."
fi

# Step 2: Enable and restart NFS service
echo "Enabling and restarting NFS service..."
sudo nfsd enable
sudo nfsd update
sudo nfsd start
sleep 2  # Give it time to settle

# Step 3: Verify NFS status
echo "Checking NFS status..."
if sudo nfsd checkexports && sudo nfsd status; then
    echo "NFS service is running."
else
    echo "Failed to start NFS. Checking logs..."
    log show --predicate '(subsystem == "com.apple.nfsd") || (process == "nfsd")' --last 10m --info --debug
    exit 1
fi

# Step 4: Verify RPC registration
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
    fi
fi

echo "NFS setup complete!"