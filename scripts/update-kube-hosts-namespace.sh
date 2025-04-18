#!/bin/bash

# Check if namespace argument is provided
if [ -z "$1" ]; then
    echo "Error: Namespace not provided."
    echo "Usage: $0 <namespace>"
    exit 1
fi

NAMESPACE="$1"
HOSTS_FILE="/etc/hosts"
KUBECTL="kubectl"  # Adjust if kubectl is not in PATH

# Remove old entries for this specific namespace (exact match for #k8s-service_<namespace>)
sudo sed -i '' "/#k8s-service_${NAMESPACE}$/d" "$HOSTS_FILE"

# Get services in the specified namespace with an external IP (e.g., from MetalLB)
while read -r name type cluster_ip external_ip _; do
    if [[ "$type" == "LoadBalancer" && "$external_ip" != "<none>" && "$external_ip" != "<pending>" ]]; then
        # Use the service name and namespace to create a hostname (e.g., my-service.default.loc)
        # Add namespace to the comment (e.g., #k8s-service_default)
        echo "$external_ip ${name}.${NAMESPACE}.loc #k8s-service_${NAMESPACE}" | sudo tee -a "$HOSTS_FILE"
    fi
done < <($KUBECTL get svc -n "$NAMESPACE" -o custom-columns="NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.status.loadBalancer.ingress[0].ip" --no-headers)

echo "Updated /etc/hosts with Kubernetes Service IPs for namespace $NAMESPACE."
echo "Current /etc/hosts:"
cat "$HOSTS_FILE"