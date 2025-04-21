# Reset multipass
multipass list
multipass stop --all
multipass delete --all
multipass purge
multipass list
brew uninstall multipass

brew install --cask multipass
multipass version

# Clear DHCP leases:
sudo rm -f /var/db/dhcpd_leases

# Verify macos host DHCP lease file
cat /var/db/dhcpd_leases

# Create dns-server based on CoreDns for multipass vms
./dns-server.sh

# Kubernetes control can't run on vm with CPUs less than 2
# Creates k8s-master 2 CPUs, 4GB memory and 10GB disk.
./launch-vm-1.sh 2 2 10 master
# Creates k8s-workers 4 CPUs, 6GB memory and 10GB disk.
./launch-vm-1.sh 3 6 10 worker-1

# Re-run dns server script
./dns-server.sh

# Install kube control on multipass master vm instance 
./launch-kube-master.sh <github-username>

# Install kube workers on multipass workers vm instance 
./launch-kube-workers.sh <github-username>

# Create nfs-server
./nfs-server.sh

# Launch Metal-LB in kubernetes
./setup-metallb.sh

# Verify Metal-LB installation
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system

# Check the NFS server for existing PVs:
kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nfs.server}{"\t"}{.spec.nfs.path}{"\n"}{end}'

# Identify PVCs for your services:
kubectl get pvc --all-namespaces

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

# Launch docker registry in kubernetes
./setup-docker-registry.sh

# Verify docker registry
docker login <registry-address>:5000

# Install kafka cluster
./setup-kafka-cluster.sh

# Before running kafka connect verify existence of registry-auth
 kubectl -n kafka get secret registry-auth
 kubectl -n kafka get secret registry-auth -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d

# Copy secret from registry to kafka namespace so kafka connect could use it
kubectl -n registry get secret registry-auth -o yaml | sed 's/namespace: registry/namespace: kafka/' | kubectl apply -f -

# Update toml files on each multipass kube vm to support insecure connection to registry.
# To see the default configuration:
multipass exec k8s-worker-3 -- containerd config default > /tmp/default.toml
multipass exec k8s-worker-3 -- cat /tmp/default.toml

# You can generate the default configuration using (in case of any issues with containerd service):
containerd config default > default.toml

# Verify toml file after resetting:
multipass exec k8s-master -- cat /etc/containerd/config.toml

# Append mirrors to toml files
./update-multipass-toml.sh 192.168.64.106:5000

# Verify mirrors
multipass exec $node -- containerd config dump | grep -A 5 "registry.mirrors"

# Run kafka connect builder
kubectl apply -f ../yaml-scripts/kafka-connect.yaml -n kafka

# Verify that builder is running
kubectl -n kafka get pods | grep my-connect-connect-build
curl -k http://192.168.64.106:5000/v2/_catalog
curl -k -u dockerreguser:<password> http://192.168.64.106:5000/v2/_catalog
curl -k -u dockerreguser:<password> http://192.168.64.106:5000/v2/my-oracle-connect/tags/list
kubectl -n kafka get secret registry-auth -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d

# Run Oracle Database 23c Free
# Pull the Image
docker pull gvenzl/oracle-free:latest
# Create a Docker Volume
docker volume create oracle_data
# Run the Container with a simple configuration:
# -e ORACLE_PASSWORD: Set the SYS/SYSTEM password (must meet complexity requirements, e.g., Oracle_123)
# Note: The default SID is FREE, and the default PDB is FREEPDB1.
docker run -d \
  --name oracle_db \
  -p 1521:1521 \
  -e ORACLE_PASSWORD=Oracle_123 \
  -v oracle_data:/opt/oracle/oradata \
  gvenzl/oracle-free:latest

# Monitor Initialization
docker logs -f oracle_db
# Look for:
DATABASE IS READY TO USE!
# Connect to the Database
docker exec -it oracle_db sqlplus / as sysdba
# Verify the database status
# Should show FREE and OPEN.
SELECT INSTANCE_NAME, STATUS FROM V$INSTANCE;
# Switch to the PDB
ALTER SESSION SET CONTAINER = FREEPDB1;
# Create a New User/Schema
CREATE USER wefox IDENTIFIED BY changeit;
GRANT CREATE SESSION, CREATE TABLE, CREATE SEQUENCE, CREATE PROCEDURE, CREATE TRIGGER, CREATE VIEW TO wefox;
GRANT SELECT ANY TABLE, INSERT ANY TABLE, UPDATE ANY TABLE, DELETE ANY TABLE, DROP ANY TABLE, ALTER ANY TABLE TO wefox;
GRANT UNLIMITED TABLESPACE TO wefox;

ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER USER WEFOX QUOTA UNLIMITED ON USERS;

# Check if the Oracle database is running and listening on port 1521:
kubectl run -i --tty --rm debug --image=busybox --restart=Never -- sh
# Inside the debug pod:
wget -qO- <oracle_ip_address>:1521

# Since curl telnet isn’t supported, use nc (netcat) to test connectivity:
# Expected output:
# Ncat: Version 7.92 ( https://nmap.org/ncat )
# Ncat: Connected to 172.24.58.225:1521.
kubectl exec -it my-connect-connect-0 -n kafka -- nc -v 172.24.58.225 1521

# Delete secret:
kubectl delete secret oracle-credentials -n kafka
# Create secret for password:
kubectl create secret generic oracle-credentials -n kafka --from-literal=password=changeit
# Multiple secret passwords:
kubectl create secret generic oracle-credentials -n kafka \
  --from-literal=password_db1=changeit \
  --from-literal=password_db2=anotherpass
# Edit the Existing Secret:
kubectl edit secret oracle-credentials -n kafka
# In the editor, modify the data section to include both passwords (base64-encoded).

# Patch the secret:
kubectl patch secret oracle-credentials -n kafka -p '{"data":{"password_wefo4":"'$(echo -n 'changeit' | base64)'","password_wefox":"'$(echo -n 'changeit' | base64)'"}}'

# Verify the secret:
kubectl get secret oracle-credentials -n kafka -o jsonpath='{.data}' | jq -r .

# Apply the KafkaConnector: Save the YAML to test-oracle-jdbc-source.yaml and apply:
kubectl apply -f ../temp/test-oracle-jdbc-source.yaml -n kafka

# If no logs appear for oracle-jdbc-source, the connector may not be running. Verify:
kubectl get kafkaconnectors -n kafka
kubectl describe kafkaconnector oracle-jdbc-source -n kafka

# Inspect the Kafka Topic
# Consume Messages from the Topic: Use the Kafka consumer to read messages:
# Expected Output:
# {"legacy_id": 1, "column1": "value1", ...}
kubectl exec -it my-cluster-kafka-0 -n kafka -- kafka-console-consumer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap.kafka.svc:29092 \
  --topic oracle-report_sends \
  --from-beginning

# Check Topic Existence: Verify the topic exists:
# If missing, the connector hasn’t created it, indicating it never started processing.
kubectl exec -it my-cluster-kafka-0 -n kafka -- kafka-topics.sh \
  --bootstrap-server my-cluster-kafka-bootstrap.kafka.svc:29092 \
  --list | grep oracle-report_sends

# Use Kafka Connect REST API: Query the connector’s status to see if it’s reporting topic-related errors:
kubectl exec -it my-connect-connect-0 -n kafka -- curl http://localhost:8083/connectors/oracle-jdbc-source/status

# Run Kafka Client Pod:
kubectl run -i --tty --rm kafka-client --image=bitnami/kafka:3.9.0 --namespace=kafka -- bash
# List Topics: Inside the pod:
/opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server my-cluster-kafka-bootstrap.kafka.svc:29092 --list | grep oracle-REPORT_SENDS
# Create the Topic
/opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server my-cluster-kafka-bootstrap.kafka.svc:29092 \
  --create \
  --topic oracle-REPORT_SENDS \
  --partitions 1 \
  --replication-factor 3


# Run Kafka Client Pod: Use the bitnami/kafka:3.9.0 image, which includes Kafka tools:
kubectl run -i --tty --rm kafka-client --image=bitnami/kafka:3.9.0 --namespace=kafka -- bash

# Consume Messages: Inside the pod:
/opt/bitnami/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap.kafka.svc:29092 \
  --topic oracle-REPORT_SENDS \
  --from-beginning

# Step 1: Delete and Recreate the Topic
# 1. Deploy a Kafka Client Pod with Tools
kubectl run -i --tty --rm kafka-client --image=bitnami/kafka:3.9.0 --namespace=kafka -- bash

# 2. Delete the Topic
/opt/bitnami/kafka/bin/kafka-topics.sh \
  --bootstrap-server my-cluster-kafka-bootstrap.kafka.svc:29092 \
  --delete \
  --topic oracle-REPORT_SENDS

# Verify Deletion:
/opt/bitnami/kafka/bin/kafka-topics.sh \
  --bootstrap-server my-cluster-kafka-bootstrap.kafka.svc:29092 \
  --list | grep oracle-REPORT_SENDS

# 3. Recreate the Topic
/opt/bitnami/kafka/bin/kafka-topics.sh \
  --bootstrap-server my-cluster-kafka-bootstrap.kafka.svc:29092 \
  --create \
  --topic oracle-REPORT_SENDS \
  --partitions 1 \
  --replication-factor 2

# Step 2: Reset the Connector’s Offset
# 1. Stop the Connector
kubectl exec -it my-connect-connect-0 -n kafka -- curl -X PUT \
  http://localhost:8083/connectors/oracle-jdbc-source/pause
# Verify:
kubectl exec -it my-connect-connect-0 -n kafka -- curl \
  http://localhost:8083/connectors/oracle-jdbc-source/status

# 2. Delete the Connector’s Offset
/opt/bitnami/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap.kafka.svc:29092 \
  --topic connect-offsets \
  --from-beginning \
  --formatter "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter"

# Delete the Offset:
echo '["oracle-jdbc-source",{"table":"REPORT_SENDS"}]:null' | \
  /opt/bitnami/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap.kafka.svc:29092 \
  --topic connect-offsets \
  --property parse.key=true \
  --property key.separator=:

# Step 3: Verify the Connector Re-Reads the Row
# 1. Resume the Connector (if Paused)
kubectl exec -it my-connect-connect-0 -n kafka -- curl -X PUT \
  http://localhost:8083/connectors/oracle-jdbc-source/resume
# 2. Monitor Logs
kubectl logs -n kafka my-connect-connect-0 --follow
# 3. Consume the Message
kubectl run -i --tty --rm kafka-client --image=bitnami/kafka:3.9.0 --namespace=kafka -- bash
/opt/bitnami/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap.kafka.svc:29092 \
  --topic oracle-REPORT_SENDS \
  --from-beginning
# Step 4: Ensure NFS Logging is Active
kubectl exec -it my-connect-connect-0 -n kafka -- df -h /opt/kafka/custom-logs
kubectl exec -it my-connect-connect-0 -n kafka -- ls -lh /opt/kafka/custom-logs
ssh nfs-server.example.com
du -sh /exports/kafka-logs