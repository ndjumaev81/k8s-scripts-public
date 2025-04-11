#!/bin/bash

HOSTS_FILE="/etc/hosts"
KUBECTL="kubectl"  # Adjust if kubectl is not in PATH

# Remove all Kubernetes Service entries (where comment starts with #k8s-service_)
sudo sed -i '' '/#k8s-service_/d' "$HOSTS_FILE"

# Get all services with an external IP (e.g., from MetalLB)
while read -r namespace name type cluster_ip external_ip _; do
    if [[ "$type" == "LoadBalancer" && "$external_ip" != "<none>" && "$external_ip" != "<pending>" ]]; then
        # Use the service name and namespace to create a hostname (e.g., my-service.default.loc)
        # Add namespace to the comment (e.g., #k8s-service_default)
        echo "$external_ip ${name}.${namespace}.loc #k8s-service_${namespace}" | sudo tee -a "$HOSTS_FILE"
    fi
done < <($KUBECTL get svc -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.status.loadBalancer.ingress[0].ip" --no-headers)

echo "Updated /etc/hosts with Kubernetes Service IPs for all namespaces."
echo "Current /etc/hosts:"
cat "$HOSTS_FILE"