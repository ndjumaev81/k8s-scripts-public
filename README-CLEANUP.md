# Force delete pod:
kubectl delete pod <pod_name> -n kafka --force --grace-period=0
kubectl delete pvc <pvc_name> -n kafka --force --grace-period=0

# Remove NFS mount:
# check for stale mounts in multipass vm:
sudo mount | grep nfs

# Unmount if found:
sudo umount /path/to/mount

# Force unmount (in case if default didn't work):
sudo umount -l /path/to/mount

# Find processes using the mount:
sudo lsof /path/to/mount

# Clear NFS directory on server:
sudo rm -rf /path/to/file