#!/bin/bash

GITHUB_USERNAME="$1"
HOST_USERNAME=$(whoami)

# Deploy MetalLB after workers are processed
if kubectl get deployment controller -n metallb-system >/dev/null 2>&1; then
    echo "MetalLB already deployed, checking configuration..."
    # Patch speaker to remove memberlist volume if needed
    if ! kubectl get secret memberlist -n metallb-system >/dev/null 2>&1; then
        echo "No memberlist secret found, ensuring memberlist volume is removed from speaker..."
        kubectl patch daemonset speaker -n metallb-system --type='json' -p='[{"op": "remove", "path": "/spec/template/spec/volumes/[?(@.name==\"memberlist\")]"}, {"op": "remove", "path": "/spec/template/spec/containers/0/volumeMounts/[?(@.name==\"memberlist\")]"}]'
        if [ $? -ne 0 ]; then
            echo "Warning: Failed to remove memberlist volume, creating fallback secret..."
            kubectl create secret generic memberlist -n metallb-system --from-literal=secretkey=$(openssl rand -base64 32)
            if [ $? -ne 0 ]; then
                echo "Warning: Failed to create memberlist secret, continuing..."
            fi
        fi
    fi
else
    echo "Deploying MetalLB..."
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
    if [ $? -ne 0 ]; then
        echo "Warning: Failed to apply MetalLB manifest, continuing..."
    else
        # Patch speaker to remove memberlist volume
        echo "Checking for memberlist secret..."
        if ! kubectl get secret memberlist -n metallb-system >/dev/null 2>&1; then
            echo "No memberlist secret found, removing memberlist volume from speaker..."
            kubectl patch daemonset speaker -n metallb-system --type='json' -p='[{"op": "remove", "path": "/spec/template/spec/volumes/[?(@.name==\"memberlist\")]"}, {"op": "remove", "path": "/spec/template/spec/containers/0/volumeMounts/[?(@.name==\"memberlist\")]"}]'
            if [ $? -ne 0 ]; then
                echo "Warning: Failed to remove memberlist volume, creating fallback secret..."
                kubectl create secret generic memberlist -n metallb-system --from-literal=secretkey=$(openssl rand -base64 32)
                if [ $? -ne 0 ]; then
                    echo "Warning: Failed to create memberlist secret, continuing..."
                fi
            fi
        fi
    fi
fi