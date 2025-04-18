#!/bin/bash

# Check if all arguments are provided
if [ -z "$1" ]; then
    echo "Error: namespace not provided."
    echo "Usage: $0 <namespace>"
    exit 1
fi

NAMESPACE="$1"

# Delete all resources in the namespace
kubectl delete all --all -n "$NAMESPACE"
kubectl delete secret --all -n "$NAMESPACE"
kubectl delete pvc --all -n "$NAMESPACE"
kubectl delete configmap --all -n "$NAMESPACE"
kubectl delete crd --all -n "$NAMESPACE"  # If custom resources are present

# Delete the namespace
kubectl delete namespace "$NAMESPACE"