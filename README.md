# Install multipass
brew install --cask multipass

# Create dns-server based on CoreDns for multipass vms
./dns-server.sh

# Creates k8s-master 2 CPUs, 4GB memory and 10GB disk.
./launch-vm-1.sh 2 4 10 master
# Creates k8s-workers 4 CPUs, 6GB memory and 10GB disk.
./launch-vm-1.sh 4 6 10 worker-1

# Re-run dns server script
./dns-server.sh

# Launch NFS service on macos host
./setup-nfs-macos-host.sh

# Install kube control on multipass master vm instance 
./launch-kube-master.sh <github-username>

# Install kube workers on multipass workers vm instance 
./launch-kube-workers.sh <github-username>

# Launch Helm nfs provisioner
./setup-nfs-provisioner-helm.sh

# Launch Metal-LB in kubernetes
./setup-metallb.sh

# Verify Metal-LB installation
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system

# Launch docker registry in kubernetes
./setup-docker-registry.sh