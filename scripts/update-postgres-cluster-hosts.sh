#!/bin/bash
REPLICAS=$1
NAMESPACE="postgres-system"
DB_HOSTS="postgres-0.postgres.${NAMESPACE}.svc.cluster.local:5432:rw"
for i in $(seq 1 $REPLICAS); do
  DB_HOSTS+=",postgres-${i}.postgres.${NAMESPACE}.svc.cluster.local:5432:ro"
done
kubectl set env deployment/pgpool DB_HOSTS="$DB_HOSTS" -n $NAMESPACE
kubectl rollout restart deployment/pgpool -n $NAMESPACE