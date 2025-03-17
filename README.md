bash <(curl -s https://raw.githubusercontent.com/<username>/k8s-scripts-public/refs/heads/main/master.sh) 192.168.64.6

# k8s-scripts-public
Multipass kubernetes

Make it executable: chmod +x master.sh

Run it with the master IP: ./master.sh 192.168.64.X

Make it executable: chmod +x worker.sh

Run it with the master IP: ./worker.sh 192.168.64.X


Steps to Test LoadBalancer Type with MetalLB
MetalLB provides load balancer functionality in bare-metal Kubernetes clusters.
Apply MetalLB Manifests: On the master VM:
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

This deploys the MetalLB controller and speaker pods in the metallb-system namespace:
kubectl apply -f https://raw.githubusercontent.com/<username>/k8s-scripts-public/refs/heads/main/metallb-config.yaml

Deploy a Test Pod:
kubectl run nginx-test --image=nginx --restart=Never --port=80

Expose as a LoadBalancer Service:
kubectl expose pod nginx-test --type=LoadBalancer --port=80 --name=nginx-lb-service

Check the service:
kubectl get svc nginx-lb-service

If it stays <pending>, check MetalLB logs:
kubectl logs -n metallb-system -l app=metallb

Test resilience by deleting the pod and recreating it:
kubectl delete pod nginx-test
kubectl run nginx-test --image=nginx --restart=Never --port=80

Clean Up
Remove the test resources:
kubectl delete svc nginx-lb-service
kubectl delete pod nginx-test


NAT Networking: With Multipass NAT (e.g., 192.168.64.x), the LoadBalancer IP (e.g., 192.168.64.100) is only accessible from the macOS host, not other LAN devices, unless you set up port forwarding on the host.
Bridged Networking: If you used bridged networking (e.g., 192.168.1.x), the LoadBalancer IP will be accessible from your entire LAN, making it more realistic for external access testing.

If you don’t want to install MetalLB, you’re limited to NodePort (as tested earlier) or manual port forwarding from the Multipass VMs to your host, but this doesn’t truly simulate a LoadBalancer. MetalLB is the simplest way to test this service type locally.

From your macOS host, use Multipass to copy the file:
multipass copy-files master:/etc/kubernetes/admin.conf ~/kubeconfig-from-master.conf


# Check what kubectl sees in your current configuration:
kubectl config view

# This shows all clusters, users, and contexts from the file specified by KUBECONFIG or ~/.kube/config.

# List available contexts:
kubectl config get-contexts

# Merge Configs into ~/.kube/config
# Merge multiple kubeconfig files into one for easier switching:
# Back up your existing ~/.kube/config:
cp ~/.kube/config ~/.kube/config.backup

# Merge configs (e.g., kubeconfig-from-master into config):
KUBECONFIG=~/.kube/config:~/.kube/multipass-kube-from-master kubectl config view --flatten > ~/.kube/config-merged
mv ~/.kube/config-merged ~/.kube/config
chmod 600 ~/.kube/config

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

# Host NFS setup
# Enable NFS
./setup-nfs-macos.sh <username>

# Manual edition
sudo nano /etc/exports
sudo nfsd update
# sudo nfsd enable
# sudo nfsd start
sudo nfsd restart
sleep 2
# Check Exported Shares:
showmount -e localhost

# Use a directory under your home folder
mkdir -p ~/nfs-mount
sudo mount -t nfs 127.0.0.1:/Users/<username>/nfs-share ~/nfs-mount

# Verify NFS is Running:
sudo nfsd status

# OPTIONAL step, to test NFS service
# Master, Worker1, Worker2
multipass shell master
sudo apt update
sudo apt install -y nfs-common
sudo mkdir -p /mnt/nfs
sudo mount -t nfs 192.168.64.1:/Users/<username>/nfs-share /mnt/nfs
ls /mnt/nfs


# manual test
kubectl apply -f nfs-provisioner.yaml
kubectl get pods -n kube-system -l app=nfs-provisioner
kubectl get storageclass nfs-storage

# kubernetes nfs setup
./deploy-nfs-provisioner.sh 192.168.64.1 /Users/<username>/nfs-share


# Install the Strimzi Kafka Operator:
# Create a namespace for Kafka:
kubectl create namespace kafka

# Deploy the Strimzi Cluster Operator using the official installation YAML:
kubectl apply -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka

# After applying the Strimzi installation, confirm the CRDs are now available:
kubectl get crd | grep kafka.strimzi.io

# Validate YAML: Ensure your strimzi-kafka.yaml has no syntax errors:
kubectl apply -f strimzi-kafka.yaml --dry-run=server

# Deployment Steps
# Apply Bridge and Swagger UI First:
kubectl apply -f kafka-bridge-and-swagger.yaml -n kafka
# Apply Registry
kubectl apply -f apicurio-registry.yaml -n kafka
# Apply Kafka Cluster Second:
kubectl apply -f kafka-strimzi-cluster.yaml -n kafka


# Verify VM resources:
multipass info master
multipass info worker1
multipass info worker2

# Aggregate Info for All VMs
multipass info --all

# Increase VM Resources
multipass stop master worker1 worker2

multipass set local.master.cpus=4
multipass set local.master.memory=6G

multipass set local.worker1.cpus=4
multipass set local.worker1.memory=6G

multipass set local.worker2.cpus=4
multipass set local.worker2.memory=6G

multipass start master worker1 worker2

# Assign a Static IP via Cloud-Init
# Multipass allows setting up an internal static IP using cloud-init:
# Create a cloud-init.yaml file:
#cloud-config
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: no
      addresses:
        - 192.168.64.100/24
      gateway4: 192.168.64.1
      nameservers:
        addresses:
          - 8.8.8.8

# Or launch the instance with the static IP:
multipass launch --name master --cloud-init cloud-init.yaml

# Use multipass alias with multipass shell
# Instead of relying on the IP, use:
multipass alias master shell master
# Then access it by (This avoids needing the IP altogether.):
master

# Install Metrics Server:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# Verify:
kubectl get pods -n kube-system | grep metrics-server
# Wait for it to run, then:
kubectl top nodes
# If it fails (e.g., TLS issues), edit the deployment to skip verification:
kubectl edit deployment metrics-server -n kube-system
# Add --kubelet-insecure-tls to args:
spec:
  template:
    spec:
      containers:
      - args:
        - --kubelet-insecure-tls

# if it will not work then try to restart:
# Trigger Pod Restart
# Wait for Automatic Rollout: Check the pod status to see if a new one starts:
kubectl get pods -n kube-system -l k8s-app=metrics-server
# Force Restart (if needed): If the pod doesn’t update automatically within a minute, manually delete it to force a restart:
kubectl delete pod -n kube-system -l k8s-app=metrics-server

# Verify applied configuration update
kubectl get pods -n kube-system | grep metrics-server 

# output should be:
metrics-server-596474b58-gg7tz     1/1     Running   0          88s

# metrics should be shonw then
kubectl top nodes




sudo nfsd update
sudo nfsd restart
sleep 2

mkdir -p ~/nfs-mount1
sudo mount -t nfs -v 192.168.64.1:/Users/<username>/nfs-share ~/nfs-mount

mount | grep nfs-mount1
sudo umount ~/nfs-mount1

mount | grep nfs-mount1
ls ~/nfs-mount1
rmdir ~/nfs-mount1


sudo cat /etc/exports
/Users/<username>/nfs-share -network 192.168.64.0 -mask 255.255.255.0 -maproot=0 -alldirs

 1616  sudo nano /etc/exports
 1617  sudo nfsd update
 1618  sudo nfsd restart
 1619  sudo showmount -e localhost