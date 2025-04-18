# Install multipass
brew install --cask multipass

# Create dns-server based on CoreDns for multipass vms
./dns-server.sh

# Creates k8s-master 2 CPUs, 4GB memory and 10GB disk.
./launch-vm-1.sh 1 2 10 master
# Creates k8s-workers 4 CPUs, 6GB memory and 10GB disk.
./launch-vm-1.sh 3 6 10 worker-1

# Create nfs-server
./nfs-server.sh

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

# Verify docker registry
docker login <registry-address>:5000

# Install kafka cluster
./setup-kafka-cluster.sh

# Run kafka connect builder
kubectl apply -f ../yaml-scripts/kafka-connect.yaml -n kafka


# Check the NFS server for existing PVs:
kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nfs.server}{"\t"}{.spec.nfs.path}{"\n"}{end}'

# Identify PVCs for your services:
kubectl get pvc --all-namespaces

multipass launch 22.04 --name nfs-server --cpus 4 --memory 8G --disk 100G

# Helm commands
# Persist Kubeconfig: Add export KUBECONFIG="$HOME/.kube/config" to your shell profile ~/.zshrc
echo 'export KUBECONFIG="$HOME/.kube/config"' >> ~/.zshrc
source ~/.zshrc

# Create a Test PVC: Create a PersistentVolumeClaim (PVC) using the nfs-client StorageClass:
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: nfs-client
EOF

# Verify the PVC is bound:
kubectl get pvc test-pvc

# Inspect the PersistentVolume (PV): Confirm the PV points to the nfs-server VM.
# Expected: 192.168.64.20
kubectl get pv -o jsonpath="{.items[?(@.spec.claimRef.name=='test-pvc')].spec.nfs.server}"
# Also check the path.
# Expected: /srv/nfs/pvc-<uuid> (subdirectory created by the provisioner)
kubectl get pv -o jsonpath="{.items[?(@.spec.claimRef.name=='test-pvc')].spec.nfs.path}"

# Deploy a Test Pod: Create a pod to mount the PVC and test writing to the NFS volume:
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
  - name: test-container
    image: nginx
    volumeMounts:
    - mountPath: /data
      name: nfs-volume
  volumes:
  - name: nfs-volume
    persistentVolumeClaim:
      claimName: test-pvc
EOF

# Verify the pod is running:
kubectl get pod test-pod

# Test NFS Mount: Write a file to the NFS volume and verify it on the nfs-server VM.
# Expected: File found
kubectl exec test-pod -- sh -c "echo 'Test' > /data/test.txt"
multipass exec nfs-server -- find /srv/nfs -name test.txt
multipass exec nfs-server -- cat /srv/nfs/pvc-<uuid>/test.txt

# Check Provisioner Logs: Inspect the NFS provisioner pod logs for mount activity:
# Look for successful mounts to 192.168.64.X:/srv/nfs/pvc-<uuid>
kubectl -n nfs-provisioning get pods
kubectl -n nfs-provisioning logs -l app=nfs-subdir-external-provisioner