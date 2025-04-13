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
curl -s https://raw.githubusercontent.com/<username>/k8s-scripts-public/refs/heads/main/scripts/master.sh | bash -s -- k8s-master.loc

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

# Verify configs
kubectl config view

# Verify the cluster is accessible:
kubectl get nodes

# List contexts:
kubectl config get-contexts

# Switch contexts:
kubectl config use-context kubernetes-admin@kubernetes

# Set a Specific Context as Default
# After merging or using a single file, set the default context:
kubectl config set-context --current --namespace=default

# Managing Multiple Clusters Long-Term
# Rename Contexts: If context names overlap, edit ~/.kube/config or use:
kubectl config rename-context kubernetes-admin@kubernetes multipass-cluster

# If you didn’t save it:
# Generate a new token on the master VM (Replace master with your master VM’s name if different.):
multipass exec k8s-master -- kubeadm token create --print-join-command

# Install kubernetes on worker machines
curl -s https://raw.githubusercontent.com/<username>/k8s-scripts-public/refs/heads/main/scripts/worker.sh | bash -s -- k8s-master.loc <token> <hash>

# Verify that worker node visible in cluster
kubectl get nodes
kubectl get pods -o wide --all-namespaces

# Verify worker node if needed
kubectl describe node k8s-worker-1

# Install metallb
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

# This deploys the MetalLB controller and speaker pods in the metallb-system namespace:
kubectl apply -f https://raw.githubusercontent.com/<username>/k8s-scripts-public/refs/heads/main/yaml-scripts/metallb-config-fixed-and-auto.yaml

# Verify logs of MetalLb
kubectl logs -n metallb-system -l app=metallb

# Host NFS setup
# Enable NFS
./setup-nfs-macos-host.sh <username>

# Verify NFS exports:
showmount -e

# From your Mac, confirm the NFS server is running:
sudo nfsd status

# Required step on multipass vms (master and workers):
sudo apt update
sudo apt install -y nfs-common
# After running the command, check installed packages:
dpkg -l | grep nfs-common
# No new services will be running:
systemctl | grep nfs

# OPTIONAL step, to test NFS service
sudo mkdir -p /mnt/nfs
sudo mount -t nfs 192.168.64.1:/Users/<username>/nfs-share /mnt/nfs
ls /mnt/nfs

# Unmount test mount
sudo umount /mnt/nfs

# Create nfs-provisioner resource in kubernetes via script
./scripts/deploy-nfs-provisioner.sh 192.168.64.1 <username>

# Install the Strimzi Kafka Operator:
# Create a namespace for Kafka:
kubectl create namespace kafka

# Deploy the Strimzi Cluster Operator using the official installation YAML:
kubectl apply -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka

# After applying the Strimzi installation, confirm the CRDs are now available:
kubectl get crd | grep kafka.strimzi.io

# Validate YAML: Ensure your strimzi-kafka.yaml has no syntax errors:
kubectl apply -f kafka-strimzi-cluster.yaml --dry-run=server

# Deployment Steps
# Apply Bridge and Swagger UI First:
kubectl apply -f kafka-bridge-and-swagger.yaml -n kafka
# Apply Registry
kubectl apply -f apicurio-registry.yaml -n kafka
# Apply Kafka Cluster Second:
kubectl apply -f kafka-strimzi-cluster.yaml -n kafka

# Install Metrics Server:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml








Verification

To test idempotency:

    Run ./setup-launch-kube-master.sh <github-username>
    Interrupt at various points (e.g., after NFS, during master setup, after Metrics Server).
    Rerun and check:
        Skipped steps are logged (e.g., “NFS exports already configured”).
        No errors from kubectl config or kubectl apply.
        ~/.kube/config remains intact.
        All components (Metrics Server, MetalLB, NFS provisioner) are deployed.