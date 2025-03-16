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
kubectl apply -f https://raw.githubusercontent.com/ndjumaev81/k8s-scripts-public/refs/heads/main/metallb-config.yaml

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


Check what kubectl sees in your current configuration:
kubectl config view

This shows all clusters, users, and contexts from the file specified by KUBECONFIG or ~/.kube/config.

List available contexts:
kubectl config get-contexts

Merge Configs into ~/.kube/config
Merge multiple kubeconfig files into one for easier switching:
Back up your existing ~/.kube/config:
cp ~/.kube/config ~/.kube/config.backup

Merge configs (e.g., kubeconfig-from-master into config):
KUBECONFIG=~/.kube/config:~/.kube/multipass-kube-from-master kubectl config view --flatten > ~/.kube/config-merged
mv ~/.kube/config-merged ~/.kube/config
chmod 600 ~/.kube/config

List contexts:
kubectl config get-contexts

Switch contexts:
kubectl config use-context kubernetes-admin@kubernetes

Set a Specific Context as Default
After merging or using a single file, set the default context:
kubectl config set-context --current --namespace=default

Managing Multiple Clusters Long-Term
Rename Contexts: If context names overlap, edit ~/.kube/config or use:
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