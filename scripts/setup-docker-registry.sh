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

# Check for nfs-client-retain storage class
if ! kubectl get storageclass nfs-client-retain >/dev/null 2>&1; then
  echo "Error: Storage class 'nfs-client-retain' not found. Please configure it or update docker-registry-deployment.yaml."
  exit 1
fi

# Check for MetalLB readiness
if ! kubectl get deployment controller -n metallb-system >/dev/null 2>&1; then
  echo "Error: MetalLB is not deployed. Please run setup-metallb.sh first."
  exit 1
fi
if ! kubectl get crd ipaddresspools.metallb.io >/dev/null 2>&1; then
  echo "Error: MetalLB CRD 'ipaddresspools.metallb.io' not found. Please run setup-metallb.sh to install MetalLB."
  exit 1
fi

# Create temp directory if it doesn't exist
mkdir -p "$TEMP_DIR"

# Define temporary YAML file in temp directory
TEMP_YAML="$TEMP_DIR/docker-registry-deployment-temp.yaml"

# Clean up temporary file function
cleanup() {
  if [ "${CLEANED_UP:-0}" -eq 0 ]; then
    rm -f "$TEMP_YAML"
    echo "Cleaned up temporary file: $TEMP_YAML"
    CLEANED_UP=1
  fi
}

# Set trap for error, interrupt, and cleanup on exit
trap cleanup ERR INT
trap 'cleanup; exit' EXIT

# Generate .dockerconfigjson content and encode in base64
AUTH=$(echo -n "$DOCKER_USERNAME:$DOCKER_PASSWORD" | base64 -w0)
DOCKERCONFIGJSON=$(cat <<EOF | base64 -w0
{
  "auths": {
    "$SERVER": {
      "username": "$DOCKER_USERNAME",
      "password": "$DOCKER_PASSWORD",
      "email": "$DOCKER_EMAIL",
      "auth": "$AUTH"
    }
  }
}
EOF
)

# Export variables for envsubst
export NAMESPACE ADDRESS DOCKERCONFIGJSON

# Substitute variables in docker-registry-deployment.yaml
cat "$YAML_DIR/docker-registry-deployment.yaml" | envsubst > "$TEMP_YAML"

# Deploy load balancer for registry
kubectl apply -f "$TEMP_YAML" -n "$NAMESPACE"

# Verify the Secret
kubectl get secret registry-auth -n "$NAMESPACE" -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d

# Wait for registry pod to be running
echo "Waiting for registry pod to be running..."
if ! kubectl wait --for=condition=Ready pod -l app=registry -n "$NAMESPACE" --timeout=120s; then
  echo "Error: Registry pod failed to become Ready. Checking pod status..."
  kubectl get pods -n "$NAMESPACE"
  REGISTRY_POD=$(kubectl get pods -n "$NAMESPACE" -l app=registry -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "No pod found")
  if [ -n "$REGISTRY_POD" ] && [ "$REGISTRY_POD" != "No pod found" ]; then
    echo "Pod details:"
    kubectl describe pod -n "$NAMESPACE" "$REGISTRY_POD"
    echo "Pod logs:"
    kubectl logs -n "$NAMESPACE" "$REGISTRY_POD"
  else
    echo "No registry pod found."
  fi
  exit 1
fi

# Get registry pod name
REGISTRY_POD=$(kubectl get pods -n "$NAMESPACE" -l app=registry -o jsonpath='{.items[0].metadata.name}')

# Inspect the running pod
kubectl get pods -n "$NAMESPACE"
kubectl describe pod -n "$NAMESPACE" "$REGISTRY_POD"

# Clean up any existing test pod
kubectl delete pod test -n "$NAMESPACE" --ignore-not-found=true

# Test registry with wget using basic authentication
kubectl run test --image=busybox --restart=Never --rm -it -- sh -c \
  "wget -O- http://$DOCKER_USERNAME:$DOCKER_PASSWORD@$ADDRESS:5000/v2/"

# Test authentication by logging in (run locally, not in cluster)
echo "Testing docker login locally..."
echo "$DOCKER_PASSWORD" | docker login "$ADDRESS:5000" -u "$DOCKER_USERNAME" --password-stdin