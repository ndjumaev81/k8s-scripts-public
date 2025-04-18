#!/bin/bash
set -e

NAMESPACE="kafka"
YAML_DIR="../yaml-scripts"

kubectl create namespace $NAMESPACE
kubectl apply -f 'https://strimzi.io/install/latest?namespace='$NAMESPACE -n $NAMESPACE
kubectl get crd | grep kafka.strimzi.io
kubectl apply -f $YAML_DIR/kafka-strimzi-cluster.yaml --dry-run=server
kubectl apply -f $YAML_DIR/kafka-bridge-and-swagger.yaml -n $NAMESPACE
kubectl apply -f $YAML_DIR/kafka-apicurio-registry.yaml -n $NAMESPACE
kubectl apply -f $YAML_DIR/kafka-strimzi-cluster.yaml -n $NAMESPACE