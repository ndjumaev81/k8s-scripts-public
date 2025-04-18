#!/bin/bash

# Usage message
echo "Usage: $0 [<docker-username>] [<docker-password>] [<registry-ip>] [<namespace>]"

# Prompt for password if not provided or set to default
if [ -z "$2" ] || [ "$2" = "changerequired" ]; then
  read -sp "Enter Docker password: " DOCKER_PASSWORD
  echo
else
  DOCKER_PASSWORD="$2"
fi

# Configuration variables
DOCKER_USERNAME="${1:-dockerreguser}"
ADDRESS="${3:-192.168.64.106}"
NAMESPACE="${4:-registry}"

DOCKER_EMAIL="$DOCKER_USERNAME@test.com"
SERVER="http://$ADDRESS:5000"
YAML_DIR="../yaml-scripts"
TEMP_DIR="../temp"

# Enable error handling
set -e

# Create temp directory if it doesn't exist
mkdir -p "$TEMP_DIR"

# Define temporary YAML file in temp directory
TEMP_YAML="$TEMP_DIR/docker-registry-service-temp.yaml"

# Clean up temporary file on error, exit, or interrupt
trap 'rm -f "$TEMP_YAML"; echo "Cleaned up temporary file: $TEMP_YAML"' EXIT ERR INT

# Create namespace if it doesn't exist
kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

# Create docker-registry Secret
kubectl create secret docker-registry registry-auth \
  --docker-server="$SERVER" \
  --docker-username="$DOCKER_USERNAME" \
  --docker-password="$DOCKER_PASSWORD" \
  --docker-email="$DOCKER_EMAIL" \
  -n "$NAMESPACE"

# Verify the Secret
kubectl get secret registry-auth -n "$NAMESPACE" -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d

# Export ADDRESS for envsubst
export ADDRESS

# Substitute ADDRESS in docker-registry-service.yaml
cat "$YAML_DIR/docker-registry-service.yaml" | envsubst > "$TEMP_YAML"

# Deploy the Registry
kubectl apply -f "$YAML_DIR/docker-registry-deployment.yaml" -n "$NAMESPACE"

# Deploy load balancer for registry
kubectl apply -f "$TEMP_YAML" -n "$NAMESPACE"

# Wait for registry pod to be running
echo "Waiting for registry pod to be running..."
kubectl wait --for=condition=Ready pod -l app=registry -n "$NAMESPACE" --timeout=120s

# Get registry pod name
REGISTRY_POD=$(kubectl get pods -n "$NAMESPACE" -l app=registry -o jsonpath='{.items[0].metadata.name}')

# Inspect the running pod
kubectl get pods -n "$NAMESPACE"
kubectl describe pod -n "$NAMESPACE" "$REGISTRY_POD"

# Test registry with wget using basic authentication
kubectl run test --image=busybox --restart=Never --rm -it -- sh -c \
  "wget -O- http://$DOCKER_USERNAME:$DOCKER_PASSWORD@$ADDRESS:5000/v2/"

# Test authentication by logging in (run locally, not in cluster)
echo "Testing docker login locally..."
echo "$DOCKER_PASSWORD" | docker login "$ADDRESS:5000" -u "$DOCKER_USERNAME" --password-stdin