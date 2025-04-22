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