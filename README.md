# Install multipass
brew install --cask multipass

# Create dns-server based on CoreDns for multipass vms
./dns-server.sh

# Creates k8s-master 2 CPUs, 4GB memory and 10GB disk.
./launch-vm-1.sh 2 4 10 master

# Creates k8s-workers 4 CPUs, 6GB memory and 10GB disk.
./launch-vm-1.sh 4 6 10 worker-1

# Re-run dns server script to update host's /etc/hosts and CoreDns config with created multipass vm instances
./dns-server.sh

# Install kube control on multipass master vm instance 
./launch-kube-master.sh <github-username>