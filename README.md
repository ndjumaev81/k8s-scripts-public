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
# Create a Namespace
kubectl create namespace registry

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

# Use wget with basic authentication to confirm the registry works:
kubectl run test --image=busybox --restart=Never --rm -it -- sh
# Inside the pod:
wget --user=mydockeruser2 --password=<your-password> -O- http://192.168.64.106:5000/v2/

# Deploy the Registry
kubectl apply -f docker-registry-deployment.yaml

# Deploy load balancer for registry
kubectl apply -f docker-registry-lb.yaml

# Inspect the running pod:
kubectl get pods -n registry
kubectl describe pod -n registry <registry-pod-name>

# Test authentication by logging in:
docker login <registry-address>:5000


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