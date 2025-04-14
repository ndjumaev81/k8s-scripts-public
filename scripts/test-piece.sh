#!/bin/bash

GITHUB_USERNAME="$1"
HOST_USERNAME=$(whoami)

# Verify MetalLB controller pod
echo "Waiting for MetalLB controller pod to be ready (up to 300 seconds)..."
for attempt in {1..20}; do
    ready_pods=$(kubectl get pods -n metallb-system -l app=metallb,component=controller --no-headers 2>/tmp/kubectl.err | grep '1/1' | grep -w 'Running' | wc -l | xargs)
    desired_pods=1
    if [ "$ready_pods" -eq "$desired_pods" ]; then
        echo "MetalLB controller pod is ready"
        break
    fi
    if [ $attempt -eq 20 ]; then
        echo "Warning: MetalLB controller pod not ready after 300 seconds ($ready_pods/$desired_pods ready), continuing..."
        kubectl get deployment controller -n metallb-system 2>/dev/null || echo "Controller deployment not found"
        kubectl get pods -n metallb-system 2>/dev/null || echo "No pods found in metallb-system"
        echo "Kubectl error log:"
        cat /tmp/kubectl.err
        break
    fi
    echo "Attempt $attempt/20: Controller pod not ready ($ready_pods/$desired_pods ready), waiting 15 seconds..."
    sleep 15
done

# Verify MetalLB speaker pod
echo "Waiting for MetalLB speaker pod to be ready (up to 300 seconds)..."
for attempt in {1..20}; do
    ready_pods=$(kubectl get pods -n metallb-system -l app=metallb,component=speaker --no-headers 2>/tmp/kubectl.err | grep '1/1' | grep -w 'Running' | wc -l | xargs)
    desired_pods=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -c "k8s-worker")
    if [ "$ready_pods" -eq "$desired_pods" ]; then
        echo "MetalLB speaker pod is ready"
        exit 0
    fi
    if [ $attempt -eq 20 ]; then
        echo "Warning: MetalLB speaker pod not ready after 300 seconds ($ready_pods/$desired_pods ready), continuing..."
        kubectl get daemonset speaker -n metallb-system 2>/dev/null || echo "Speaker daemonset not found"
        kubectl get pods -n metallb-system 2>/dev/null || echo "No pods found in metallb-system"
        echo "Kubectl error log:"
        cat /tmp/kubectl.err
        exit 1
    fi
    echo "Attempt $attempt/20: Speaker pod not ready ($ready_pods/$desired_pods ready), waiting 15 seconds..."
    sleep 15
done