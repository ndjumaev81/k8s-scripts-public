# Apply
kubectl apply -f ../yaml-scripts/kafka-strimzi-cluster.yaml -n kafka
# Restart
kubectl rollout restart statefulset my-cluster-kafka -n kafka

# Since Strimzi uses StrimziPodSet instead of StatefulSets, check the resources and pods:
kubectl get strimzipodset -n kafka

# List Pods:
kubectl get pod -n kafka | grep my-cluster

# Check the broker’s configuration:
kubectl exec -it my-cluster-kafka-0 -n kafka -- cat /opt/kafka/config/server.properties

# Create users
kubectl apply -f ../yaml-scripts/kafka-users.yaml 
kubectl get kafkauser -n kafka
kubectl get secret kafka-admin -n kafka -o jsonpath='{.data.password}' | base64 -d
kubectl get secret kafka-connect-user -n kafka -o jsonpath='{.data.password}' | base64 -d

# Apply the updated YAML:
kubectl apply -f ../yaml-scripts/kafka-strimzi-cluster.yaml -n kafka
# Restart the Kafka pods (Strimzi uses StrimziPodSet):
kubectl delete pod -n kafka -l strimzi.io/component-type=kafka
# Wait for pods to restart:
kubectl get pod -n kafka -l strimzi.io/component-type=kafka -w

# Apply ACLs for the Two Users
# Start kafka-client Pod
kubectl run -i --tty --rm kafka-client --image=bitnami/kafka:3.9.0 --namespace=kafka -- bash
# Grant kafka-admin full cluster-wide permissions:
kafka-acls.sh --bootstrap-server my-cluster-kafka-bootstrap.kafka.svc:29092 \
  --add \
  --allow-principal User:kafka-admin \
  --operation All \
  --cluster
kafka-acls.sh --bootstrap-server my-cluster-kafka-bootstrap.kafka.svc:29092 \
  --add \
  --allow-principal User:kafka-admin \
  --operation All \
  --topic '*' \
  --resource-pattern-type any

# Since Strimzi uses StrimziPodSet, you can’t use kubectl rollout restart statefulset. Instead, restart the pods managed by StrimziPodSet:
# kubectl delete pod -n kafka -l strimzi.io/component-type=kafka

# Select the SASL mechanism as "SCRAM-SHA-512" (since your Kafka cluster uses this).
# Retrieve the password from the my-connect-user secret, which was created by the KafkaUser resource in kafka-connect.yaml
kubectl get secret my-connect-user -n kafka -o jsonpath='{.data.password}' | base64 -d


kubectl run -i --tty --rm kafka-client --image=bitnami/kafka:3.9.0 --namespace=kafka -- bash

# Add ACL
kafka-acls.sh --bootstrap-server my-cluster-kafka-bootstrap.kafka.svc:29092 \
  --add \
  --allow-principal User:my-connect \
  --operation Create \
  --topic ORA_TABLE_NAME \
  --resource-pattern-type prefixed

# The following command lists offsets
# --key-deserializer and --value-deserializer to output raw strings, making keys and values human-readable.
# Kept --property print.key=true and --property print.value=true to display both keys and values.
kafka-console-consumer.sh --bootstrap-server my-cluster-kafka-bootstrap.kafka.svc:29092 \
  --topic connect-offsets \
  --from-beginning \
  --property print.key=true \
  --property print.value=true \
  --key-deserializer org.apache.kafka.common.serialization.StringDeserializer \
  --value-deserializer org.apache.kafka.common.serialization.StringDeserializer

# List of available connectors
kubectl get kafkaconnectors -n kafka

# Reset its offsets using the Kafka Connect REST API
curl -X POST http://192.168.64.107:8083/connectors/oracle-jdbc-source/offsets/reset


# 1. Create client.properties locally
cat <<EOF > client.properties
bootstrap.servers=192.168.64.100:9092
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required \
  username="kafka-admin" \
  password="xxxxxxxxxxxxx";
EOF

# 2. Create a ConfigMap in Kubernetes
kubectl create configmap kafka-client-config \
  --from-file=client.properties \
  -n kafka

# 3. Run the Kafka client with the ConfigMap mounted
kubectl run -i --tty --rm kafka-client \
  --image=bitnami/kafka:3.9.0 \
  --namespace=kafka \
  --overrides='
{
  "spec": {
    "containers": [
      {
        "name": "kafka-client",
        "image": "bitnami/kafka:3.9.0",
        "volumeMounts": [
          {
            "mountPath": "/config",
            "name": "client-config"
          }
        ]
      }
    ],
    "volumes": [
      {
        "name": "client-config",
        "configMap": {
          "name": "kafka-client-config"
        }
      }
    ]
  }
}' -- bash


# Verify message, it should contains the version
kubectl run -i --tty --rm kafka-client --image=bitnami/kafka:3.9.0 --namespace=kafka -- bash

kafka-console-consumer.sh --bootstrap-server my-cluster-kafka-bootstrap.kafka.svc:29092 --topic ORA_TABLE_REPORT_SENDS --from-beginning --max-messages 1 | od -tx1 -c


http://192.168.64.103:8282/apis/registry/v2/search/artifacts
http://192.168.64.103:8282/apis/registry/v2/groups/default/artifacts/ORA_TABLE_REPORT_SENDS-value
http://192.168.64.103:8282/apis/registry/v2/groups/default/artifacts/ORA_TABLE_REPORT_SENDS-value/versions