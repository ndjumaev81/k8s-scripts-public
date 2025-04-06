# Usage:
./launch-vm-1.sh 10 2 4 20


# Stop the Multipass Daemon:

sudo launchctl stop com.canonical.multipass 2>/dev/null
sudo launchctl remove com.canonical.multipass 2>/dev/null
sudo rm -f /Library/LaunchDaemons/com.canonical.multipass.plist

 # Remove the Application:
sudo rm -rf /Applications/Multipass.app

 # Remove the CLI Binary:
sudo rm -f /usr/local/bin/multipass

# Clean Up Configuration and Data:
rm -rf ~/Library/Application\ Support/multipass*
rm -rf ~/Library/Preferences/multipass*
rm -rf ~/Library/Caches/multipass*
rm -rf ~/.multipass
sudo rm -rf /var/root/Library/Application\ Support/multipassd

# Verify Removal:
which multipass
multipass version

# Creates k8s-master with IP 192.168.64.10, 2 CPUs, 4GB memory, and 20GB disk.
./launch-vm.sh master 192.168.64.10 2 4 20

bash <(curl -s https://raw.githubusercontent.com/<username>/k8s-scripts-public/refs/heads/main/master.sh) 192.168.64.6

# You can run above command from host via:
multipass shell k8s-master -c "bash <(curl -s https://raw.githubusercontent.com/<username>/k8s-scripts-public/refs/heads/main/master.sh) k8s-master.loc"

multipass exec k8s-master -- bash -c "bash <(curl -s https://raw.githubusercontent.com/<username>/k8s-scripts-public/refs/heads/main/master.sh) k8s-master.loc && echo 'Success' || echo 'Failed'"

multipass launch --name master --cpus 2 --memory 4G --disk 30G 22.04
multipass launch --name worker1 --cpus 8 --memory 8G --disk 30G 22.04
multipass launch --name worker2 --cpus 8 --memory 8G --disk 30G 22.04
multipass launch --name worker3 --cpus 8 --memory 8G --disk 30G 22.04
multipass launch --name worker4 --cpus 2 --memory 4G --disk 20G 22.04

# Verify Architecture:
multipass shell master
uname -m
# Expected output:
aarch64


# If you are going to run oracle then you need to use amd64 platform
multipass launch --name k8s-master --cpus 2 --memory 4G --disk 20G --arch amd64
multipass launch --name k8s-worker1 --cpus 2 --memory 4G --disk 20G --arch amd64
multipass launch --name k8s-worker2 --cpus 2 --memory 4G --disk 20G --arch amd64


# Install Kubernetes (e.g., via kubeadm):
sudo apt update
sudo apt install -y kubeadm kubectl kubelet
sudo kubeadm init --pod-network-cidr=192.168.0.0/16
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
# Join Workers: SSH into each worker
multipass shell k8s-worker1
sudo apt update
sudo apt install -y kubeadm kubectl kubelet
sudo <kubeadm join command>


# k8s-scripts-public
Multipass kubernetes

Make it executable: chmod +x master.sh

Run it with the master IP: ./master.sh 192.168.64.X

Make it executable: chmod +x worker.sh

Run it with the master IP: ./worker.sh 192.168.64.X

# Retrieve the kubeadm join Details
# If you saved the original kubeadm init output: Look for something like:
kubeadm join 192.168.64.6:6443 --token 0ab9ad.lbhe66pv4yslcsti --discovery-token-ca-cert-hash sha256:4086e0b...

# If you didn’t save it:
# Generate a new token on the master VM (Replace master with your master VM’s name if different.):
multipass exec master -- kubeadm token create --print-join-command

# From your host, check the cluster:
kubectl get nodes -o wide

# If workerX isn’t Ready, check its logs:
multipass exec worker2 -- journalctl -u kubelet

# Check the Cluster Nodes:
kubectl get nodes

# If you see a stale worker3 (e.g., "NotReady"), delete it from the cluster:
kubectl delete node worker3

# Verify the New Node:
kubectl get nodes
kubectl get pods -o wide


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



 # CASSANDRA
# Do below commands from host machine.
# Add the Cert-Manager Helm Repository:
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install Cert-Manager:
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --kubeconfig ~/.kube/config \
  --version v1.14.4 \
  --set installCRDs=true \
  --kube-context multipass-cluster

# --namespace cert-manager: Installs in a dedicated namespace.
# --create-namespace: Creates the namespace if it doesn’t exist.
# --version v1.14.4: Uses a recent stable version compatible with Kubernetes 1.28 (from your master.sh).
# --set installCRDs=true: Installs the Custom Resource Definitions (CRDs) required by cert-manager.
# --kube-context multipass-cluster: Ensures it uses your cluster’s context.

# Verify Cert-Manager: Wait for the pods to be ready:
kubectl get pods -n cert-manager

# K8ssandra Operator Installation
helm install k8ssandra-operator k8ssandra/k8ssandra-operator \
  --namespace k8ssandra-operator \
  --create-namespace \
  --kubeconfig ~/.kube/config \
  --kube-context multipass-cluster \
  --debug

# OPTION: uninstall if needed
helm uninstall k8ssandra-operator \
  --namespace k8ssandra-operator \
  --kubeconfig ~/.kube/config \
  --kube-context multipass-cluster \
  --debug

# Verify the Installation
kubectl get pods -n k8ssandra-operator

# Install k8ssandra cluster
kubectl apply -f k8ssandra-operator.yaml -n k8ssandra-operator

# Checl taints
kubectl describe nodes | grep -i taint

# Inspect Pending Pods
kubectl get pods -n k8ssandra-operator --field-selector=status.phase!=Running

# After adding new worker to kube cluster to enable NFS don't forget to install "nfs-common"
multipass shell worker3
sudo apt update
sudo apt install -y nfs-common


# Understanding the Stargate Service
# exposes the following ports:
# 8080: REST API endpoint
# 8081: GraphQL API endpoint
# 8082: Stargate Admin API
# 8084: Health check endpoint
# 8085: Metrics endpoint
# 8090: Swagger UI (this is likely what you want for browser access)
# 9042: Native CQL (Cassandra Query Language) port

# Get stargate pod name
kubectl get pods -n k8ssandra-operator

# Inspect Pod Labels
# Run the following command to view the full details of the pod, including its labels:
kubectl get pod demo-dc1-default-stargate-deployment-XXXXXXXX -n k8ssandra-operator -o yaml

# Look for the metadata.labels section in the output. Alternatively, for a more concise view, use:
kubectl get pod demo-dc1-default-stargate-deployment-58c75d8b7f-w5m76 -n k8ssandra-operator -o jsonpath='{.metadata.labels}'

# Get username
CASS_USERNAME=$(kubectl get secret demo-superuser -n k8ssandra-operator -o=jsonpath='{.data.username}' | base64 --decode)
echo $CASS_USERNAME

# Get password
CASS_PASSWORD=$(kubectl get secret demo-superuser -n k8ssandra-operator -o=jsonpath='{.data.password}' | base64 --decode)
echo $CASS_PASSWORD

# Verify cluster status
kubectl exec -it demo-dc1-default-sts-0 -n k8ssandra-operator -c cassandra -- nodetool -u $CASS_USERNAME -pw $CASS_PASSWORD status

# K8ssandra swagger-ui port is 8082:
    Access Document Data API
    Access REST Data API
    Access GraphQL Data API

You can access the following interfaces to make development easier as well:

    Stargate swagger UI: http://192.168.64.104:8082/swagger-ui
    GraphQL Playground: http://192.168.64.104:8080/playground

curl -L -X POST 'http://192.168.64.104:8081/v1/auth' -H 'Content-Type: application/json' --data-raw '{"username": "<k8ssandra-username>", "password": "<k8ssandra-password>"}'

The default ports assignments align to the following services and interfaces:

Port
	

Service/Interface

8080
	

GraphQL interface for CRUD

8081
	

REST authorization service for generating authorization tokens

8082
	

REST interface for CRUD

8084
	

Health check (/healthcheck, /checker/liveness, /checker/readiness) and metrics (/metrics)

8180
	

Document API interface for CRUD

8090
	

gRPC interface for CRUD

9042
	

CQL service



# REAPER
kubectl apply -f k8ssandra-reaper.yaml

# The Reaper custom resource itself provides status information about its deployment.
kubectl get reaper cp-reaper -n k8ssandra-operator

# For more details:
kubectl describe reaper cp-reaper -n k8ssandra-operator

# The k8ssandra-operator creates a pod to run the Reaper application.
kubectl get pods -n k8ssandra-operator | grep reaper

# To see more details:
kubectl describe pod cp-reaper-0 -n k8ssandra-operator

# Check Persistent Volume Claims (PVCs)
kubectl get pvc -n k8ssandra-operator

# For more info:
kubectl describe pvc reaper-data-cp-reaper-0 -n k8ssandra-operator

# A Kubernetes Service is created to expose Reaper’s HTTP management interface (since httpManagement: enabled)
kubectl get svc -n k8ssandra-operator | grep reaper

# Details:
kubectl describe svc cp-reaper-service -n k8ssandra-operator

# Verify Integration with K8ssandraCluster
kubectl get k8ssandracluster demo -n k8ssandra-operator

# WebUI of Reaper
kubectl port-forward svc/cp-reaper-service 8080:8080 -n k8ssandra-operator

# Accessible via the following:
http://localhost:8080/webui

# Extract the JMX Username and Password
# Describe the Secret:
kubectl get secret -n k8ssandra-operator
# Decode the Username:
kubectl get secret demo-superuser -n k8ssandra-operator -o jsonpath='{.data.username}' | base64 -d
# Decode the Password:
kubectl get secret demo-superuser -n k8ssandra-operator -o jsonpath='{.data.password}' | base64 -d

# Verify Reaper’s Configuration
# Check the Reaper Pod’s Configuration
kubectl exec -it cp-reaper-0 -n k8ssandra-operator -- /bin/sh

# Look for the Configuration File


kubectl create configmap reaper-config -n k8ssandra-operator --from-file=cassandra-reaper.yml=cassandra-reaper-updated.yml


# VALID SEED SERVICE ENDPOINT: 
# demo-seed-service.k8ssandra-operator.svc.cluster.local
# The demo-seed-service is a headless service created by the K8ssandra operator to provide a stable DNS entry for the seed nodes of the demo cluster.

kubectl get endpoints demo-seed-service -n k8ssandra-operator -o yaml




# Kafka-connector:
# Visit Confluent Hub JDBC Connector to see available versions.
# use a Maven command to list available versions:
mvn dependency:get -DrepoUrl=https://packages.confluent.io/maven/ -DgroupId=io.confluent -DartifactId=kafka-connect-jdbc -Dversion=10.7.4


# Deploy Kafka Connect:
kubectl apply -f kafka-connect.yaml -n kafka

# Verify Deployment:
kubectl get pods -n kafka

# Check logs
kubectl logs my-connect-connect-0 -n kafka

# Add the Oracle Connector:
# oracle-jdbc-connector.yaml
kubectl apply -f oracle-jdbc-connector.yaml -n kafka

# Validate Data Flow: Check the connector status:
kubectl get kafkaconnector oracle-jdbc-source -n kafka

# Consume messages:
kubectl exec -it my-cluster-kafka-0 -n kafka -- kafka-console-consumer --bootstrap-server localhost:29092 --topic oracle-your_table_name --from-beginning

# Deploy the Docker Registry
# Create a Namespace
kubectl create namespace registry

# Create a Secret for Authentication
# You'll need a username and password for the registry. We'll use htpasswd to generate a basic auth file.
# Install htpasswd if not present (e.g., on Ubuntu: sudo apt install apache2-utils)
## mkdir auth
## htpasswd -Bc auth/htpasswd <username> # Replace <username> with your desired username
# Enter a password when prompted

# Create a Kubernetes Secret from the htpasswd file:
 kubectl create secret generic registry-auth \
  --from-file=htpasswd=auth/htpasswd \
  -n registry

# To confirm the Secret is correctly applied
# Check the Secret exists:
 kubectl get secret -n registry registry-auth -o yaml

# VALID SECRETS 
# Create a docker-registry Secret
kubectl create secret docker-registry registry-auth \
  --docker-server=192.168.64.106:5000 \
  --docker-username=mydockeruser2 \
  --docker-password=<your-password> \
  --docker-email=mydockeruser2@test.com \
  -n kafka

# Delete the existing secret
kubectl delete secret registry-auth -n kafka

# Recreate with http://
kubectl create secret docker-registry registry-auth \
  --docker-server=http://192.168.64.106:5000 \
  --docker-username=mydockeruser2 \
  --docker-password=<your-password> \
  --docker-email=mydockeruser2@test.com \
  -n kafka

# Verify the Secret
kubectl get secret registry-auth -n kafka -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d

# Use wget with basic authentication to confirm the registry works:
kubectl run test --image=busybox --restart=Never --rm -it -- sh
# Inside the pod:
wget --user=mydockeruser2 --password=<your-password> -O- http://192.168.64.106:5000/v2/

# Deploy the Registry
kubectl apply -f registry-deployment.yaml

# Inspect the running pod:
kubectl get pods -n registry
kubectl describe pod -n registry <registry-pod-name>

# Test authentication by logging in:
docker login <registry-address>:5000

# Install kafka-connect
kubectl apply -f kafka-connect.yaml -n kafka

# Verify logs
kubectl logs my-connect-connect-build -n kafka


kubectl create namespace oracle
kubectl apply -f oracle-xe-deployment.yaml -n oracle
kubectl get svc -n default oracle-service

# Verify Your Registry is Accessible
# Check the service:
kubectl get svc -n registry registry-service

# Test connectivity:
curl -v http://192.168.64.106:5000/v2/
# Output:
< HTTP/1.1 401 Unauthorized
< WWW-Authenticate: Basic realm="Registry Realm"

# Log in to Your Private Registry
docker login 192.168.64.106:5000

# If you don’t remember the credentials:
kubectl get secret -n registry registry-auth -o jsonpath='{.data.htpasswd}' | base64 -d

# Tag the Oracle XE Image
docker tag container-registry.oracle.com/database/express:21.3.0-xe 192.168.64.106:5000/oracle-xe:21.3.0

# Verify the tagged image:
docker images

# Push the Image to Your Registry
docker push 192.168.64.106:5000/oracle-xe:21.3.0

# Verify the Image in Your Registry
curl -u <username>:<password> http://192.168.64.106:5000/v2/_catalog
# Expected output:
{"repositories":["oracle-xe"]}

# Check tags for the repository:
curl -u <username>:<password> http://192.168.64.106:5000/v2/oracle-xe/tags/list
# Expected output:
{"name":"oracle-xe","tags":["21.3.0"]}

# Test Pulling from Your Registry
docker rmi 192.168.64.106:5000/oracle-xe:21.3.0
docker pull 192.168.64.106:5000/oracle-xe:21.3.0


Option 2: Share a Secret Across Namespaces

Kubernetes doesn’t natively allow a Secret to be shared across namespaces directly, but you can:

    Copy the Secret: Export it from one namespace and import it into others.
    Use RBAC: Allow pods in other namespaces to reference a Secret in a central namespace (less common and more complex).

For simplicity, copying the Secret is the most practical approach:

    Export the Existing Secret: If registry-auth in the registry namespace is the correct Secret:

kubectl get secret registry-auth -n registry -o yaml > registry-auth.yaml

Edit registry-auth.yaml to remove namespace: registry and any uid/resourceVersion fields:
apiVersion: v1
kind: Secret
metadata:
  name: regcred  # Rename to match your Deployment
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: <base64-encoded-value>

kubectl apply -f registry-auth.yaml -n default


# Steps to Install Oracle 19c (ARM64) on Docker Desktop on macOS M2
# Step 1: Download the ARM64 Binary
# LINUX.ARM64_1919000_db_home.zip
# Step 2: Clone Oracle’s Docker Images Repository
git clone https://github.com/oracle/docker-images.git
cd docker-images/OracleDatabase/SingleInstance/dockerfiles

# Step 3: Prepare the Files
# Copy the downloaded LINUX.ARM64_1919000_db_home.zip into the 19.3.0 directory:
cp /path/to/LINUX.ARM64_1919000_db_home.zip ./19.3.0/

./buildContainerImage.sh -v 19.3.0 -e

# -v 19.3.0: Specifies the base version (19c).
# -e: Builds the Enterprise Edition (required for ARM64, as XE isn’t available).

# Step 5: Run the Container
docker run -d -p 1521:1521 -e ORACLE_PWD=your_password oracle/database:19.3.0-ee
# -e ORACLE_PWD: Sets the password for SYS and SYSTEM users.
# -p 1521:1521: Maps the Oracle port to your host.

The Oracle Docker Images repository provides defaults unless overridden by environment variables (e.g., ORACLE_SID or ORACLE_PDB):

    SID: The default SID for the Container Database (CDB) is ORCLCDB.
    Service Name:
        For the CDB, the default service name is ORCLCDB.
        For the default Pluggable Database (PDB), the service name is ORCLPDB1.

Since your command doesn’t specify -e ORACLE_SID or -e ORACLE_PDB, these defaults apply.