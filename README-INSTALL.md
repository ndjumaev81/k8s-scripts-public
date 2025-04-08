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
curl -s https://raw.githubusercontent.com/<username>/k8s-scripts-public/refs/heads/main/master.sh | bash -s -- k8s-master.loc

# If for some reason you have to run script again, don't forget to reset cluster
sudo kubeadm reset -f

# Copy admin config from kubernetes master node
multipass exec k8s-master -- sudo cat /etc/kubernetes/admin.conf > /tmp/k8s-master-config

# This command will replace your ~/.kube/config with new configuration
sudo mv /tmp/k8s-master-config ~/.kube/config

# Or you could merge this config into your ~/.kube/config to preserve exist configurations
export KUBECONFIG=~/.kube/config:/tmp/k8s-master-config
kubectl config view --flatten > ~/.kube/config.new
sudo mv ~/.kube/config.new ~/.kube/config
unset KUBECONFIG

# Verify the cluster is accessible:
kubectl get nodes

# If you didn’t save it:
# Generate a new token on the master VM (Replace master with your master VM’s name if different.):
multipass exec k8s-master -- kubeadm token create --print-join-command

# Install kubernetes on worker machines
curl -s https://raw.githubusercontent.com/<username>/k8s-scripts-public/refs/heads/main/worker.sh | bash -s -- k8s-master.loc <token> <hash>

# Verify that worker node visible in cluster
kubectl get nodes

# Verify worker node
kubectl describe node k8s-worker-1

