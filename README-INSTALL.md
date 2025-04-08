# Install multipass
brew install --cask multipass

# Create dns-server based on CoreDns for multipass vms
./dns-server.sh

# Creates k8s-master 2 CPUs, 4GB memory and 20GB disk.
./launch-vm-1.sh 2 4 20 master

# Creates k8s-workers 4 CPUs, 6GB memory and 20GB disk.
./launch-vm-1.sh 4 6 20 worker-1
./launch-vm-1.sh 4 6 20 worker-2
./launch-vm-1.sh 4 6 20 worker-3
./launch-vm-1.sh 4 6 20 worker-4

# Login to k8s-master (k8s-worker-1,..., k8s-worker-4) and run this command
sudo apt update && sudo apt upgrade

# Run this script again to update hosts and coreDns configuration
./dns-server.sh

# Install kubernetes cluster master node via script file:
curl -s https://raw.githubusercontent.com/<username>/k8s-scripts-public/refs/heads/main/master.sh) k8s-master.loc