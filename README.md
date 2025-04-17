# Use the itsthenetwork/nfs-server-alpine image for the NFS server.
# Pull the Image:
docker pull itsthenetwork/nfs-server-alpine:latest
# Verify:
docker images itsthenetwork/nfs-server-alpine
# Run the NFS Server Container
docker run -d \
  --name nfs-server \
  --privileged \
  -v /Users/<username>/nfs-share:/nfsshare \
  -e SHARED_DIRECTORY=/nfsshare \
  -p 2049:2049 \
  itsthenetwork/nfs-server-alpine:latest

# Explanation:
#    -v /Users/<username>/nfs-share:/nfsshare: Mounts ~/nfs-share to /nfsshare in the container.
#    -e SHARED_DIRECTORY=/nfsshare: Exports /nfsshare (and its subfolders) via NFS.
#    -p 2049:2049: Exposes the NFS port.
#    --privileged: Required for NFS kernel operations.
#    -d: Runs in the background.

# Verify Container:
dcoker ps
# If the container exits, check logs:
docker logs nfs-server

# Install multipass
brew install --cask multipass

# Create dns-server based on CoreDns for multipass vms
./dns-server.sh

# Creates k8s-master 2 CPUs, 4GB memory and 10GB disk.
./launch-vm-1.sh 2 4 10 master
# Re-run dns server script
./dns-server.sh
# Install kube control on multipass master vm instance 
./launch-kube-master.sh <github-username>


# Creates k8s-workers 4 CPUs, 6GB memory and 10GB disk.
./launch-vm-1.sh 4 6 10 worker-1
# Re-run dns server script
./dns-server.sh
# Install kube workers on multipass workers vm instance 
./launch-kube-workers.sh <github-username>


# Verify existence of metallb yaml configuration
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
kubectl get bgppeer -n metallb-system

# Re-apply if needed
kubectl apply -f https://raw.githubusercontent.com/<username>/k8s-scripts-public/refs/heads/main/yaml-scripts/metallb-config-fixed-and-auto.yaml

# Verify NFS exports:
showmount -e

# From your Mac, confirm the NFS server is running:
sudo nfsd status


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

# Deploy the Docker Registry
# VALID SECRETS 
# Create a docker-registry Secret
kubectl create secret docker-registry registry-auth \
  --docker-server=http://192.168.64.106:5000 \
  --docker-username=mydockeruser2 \
  --docker-password=<your-password> \
  --docker-email=mydockeruser2@test.com \
  -n kafka

# Verify the Secret
kubectl get secret registry-auth -n kafka -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d

# Deploy the Registry
kubectl apply -f docker-registry-deployment.yaml

# Deploy load balancer for registry
kubectl apply -f docker-registry-lb.yaml

# Inspect the running pod:
kubectl get pods -n registry
kubectl describe pod -n registry <registry-pod-name>

# Use wget with basic authentication to confirm the registry works:
kubectl run test --image=busybox --restart=Never --rm -it -- sh
# Inside the pod:
wget  -O- http://mydockeruser2:<your-password>@192.168.64.106:5000/v2/

# Test authentication by logging in:
docker login <registry-address>:5000

# Run oracle in docker-desktop
# -e ORACLE_PWD: Sets the password for SYS and SYSTEM users.
# -p 1521:1521: Maps the Oracle port to your host.
# The Oracle Docker Images repository provides defaults unless overridden by environment variables (e.g., ORACLE_SID or ORACLE_PDB):
#    SID: The default SID for the Container Database (CDB) is ORCLCDB.
#    Service Name:
#        For the CDB, the default service name is ORCLCDB.
#        For the default Pluggable Database (PDB), the service name is ORCLPDB1.
# Since your command doesn’t specify -e ORACLE_SID or -e ORACLE_PDB, these defaults apply.
docker run -d -p 1521:1521 -e ORACLE_PWD=<password> -e ORACLE_SID=<sid> -e ORACLE_PDB=<pdb>  oracle/database:19.3.0-ee


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