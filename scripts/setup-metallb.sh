#!/bin/bash

# Configuration variables
YAML_DIR="../yaml-scripts"
METALLB_CONFIG_PATH="$YAML_DIR/metallb-config-fixed-and-auto.yaml"
METALLB_MANIFEST="https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml"

# Enable error handling
set -e

# Check for cluster-admin permissions
if ! kubectl auth can-i create crd >/dev/null 2>&1; then
  echo "Error: Insufficient permissions to create CRDs. Please run as cluster-admin."
  exit 1
fi

# Function to check MetalLB CRDs
check_metallb_crds() {
  for crd in ipaddresspools.metallb.io l2advertisements.metallb.io; do
    if ! kubectl get crd "$crd" >/dev/null 2>&1; then
      echo "Error: MetalLB CRD '$crd' not found."
      return 1
    fi
  done
  echo "MetalLB CRDs verified."
  return 0
}

# Function to resolve terminating namespace
resolve_terminating_namespace() {
  local namespace="metallb-system"
  if kubectl get namespace "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Terminating"; then
    echo "Namespace $namespace is in Terminating state, attempting to resolve..."
    kubectl patch namespace "$namespace" -p '{"metadata":{"finalizers":null}}' --type=merge
    kubectl delete namespace "$namespace" --force --grace-period=0
    for i in {1..30}; do
      if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        echo "Namespace $namespace successfully deleted."
        return 0
      fi
      echo "Waiting for namespace $namespace to be deleted ($i/30)..."
      sleep 2
    done
    echo "Error: Failed to delete namespace $namespace after 60 seconds."
    exit 1
  fi
  return 0
}

# Deploy or update MetalLB
if kubectl get deployment controller -n metallb-system >/dev/null 2>&1; then
  echo "MetalLB deployment found, checking CRDs..."
  if ! check_metallb_crds; then
    echo "Reinstalling MetalLB due to missing CRDs..."
    resolve_terminating_namespace
    kubectl apply -f "$METALLB_MANIFEST"
    for i in {1..30}; do
      if check_metallb_crds; then
        echo "MetalLB CRDs installed successfully."
        break
      fi
      echo "Waiting for CRDs to be registered ($i/30)..."
      sleep 2
    done
    if ! check_metallb_crds; then
      echo "Error: Failed to install MetalLB CRDs after 60 seconds."
      exit 1
    fi
  fi
else
  echo "Deploying MetalLB..."
  resolve_terminating_namespace
  kubectl apply -f "$METALLB_MANIFEST"
  for i in {1..30}; do
    if check_metallb_crds; then
      echo "MetalLB CRDs installed successfully."
      break
    fi
    echo "Waiting for CRDs to be registered ($i/30)..."
    sleep 2
  done
  if ! check_metallb_crds; then
    echo "Error: Failed to install MetalLB CRDs after 60 seconds."
    exit 1
  fi
fi

# Configure speaker DaemonSet
echo "Checking speaker DaemonSet configuration..."
needs_restart=0
toleration_key=$(kubectl get daemonset speaker -n metallb-system -o jsonpath='{.spec.template.spec.tolerations[?(@.key=="node-role.kubernetes.io/control-plane")].key}' 2>/dev/null)
if [ -n "$toleration_key" ]; then
  echo "Removing control-plane toleration from speaker DaemonSet..."
  toleration_index=$(kubectl get daemonset speaker -n metallb-system -o jsonpath='{range .spec.template.spec.tolerations[*]}{.key}{"\n"}{end}' | grep -n "node-role.kubernetes.io/control-plane" | cut -d: -f1)
  if [ -n "$toleration_index" ]; then
    toleration_index=$((toleration_index-1))
    kubectl patch daemonset speaker -n metallb-system --type='json' -p="[{\"op\": \"remove\", \"path\": \"/spec/template/spec/tolerations/$toleration_index\"}]"
    if [ $? -eq 0 ]; then
      echo "Control-plane toleration removed successfully."
      needs_restart=1
    else
      echo "Warning: Failed to remove control-plane toleration, continuing..."
    fi
  else
    echo "Warning: Could not find control-plane toleration index, skipping patch..."
  fi
else
  echo "No control-plane toleration found, skipping patch..."
fi

if [ $needs_restart -eq 1 ]; then
  echo "Restarting speaker DaemonSet..."
  sleep 2
  kubectl rollout restart daemonset speaker -n metallb-system
  if [ $? -eq 0 ]; then
    echo "Speaker DaemonSet restarted successfully."
  else
    echo "Warning: Failed to restart speaker DaemonSet, continuing..."
  fi
fi

# Wait for MetalLB pods
echo "Waiting for MetalLB controller pod to be ready (up to 300 seconds)..."
for attempt in {1..20}; do
  ready_pods=$(kubectl get pods -n metallb-system -l app=metallb,component=controller --no-headers 2>/tmp/kubectl.err | grep '1/1' | grep -w 'Running' | wc -l | xargs)
  desired_pods=1
  if [ "$ready_pods" -eq "$desired_pods" ]; then
    echo "MetalLB controller pod is ready."
    break
  fi
  if [ $attempt -eq 20 ]; then
    echo "Error: MetalLB controller pod not ready after 300 seconds ($ready_pods/$desired_pods ready)."
    kubectl get deployment controller -n metallb-system 2>/dev/null || echo "Controller deployment not found."
    kubectl get pods -n metallb-system 2>/dev/null || echo "No pods found in metallb-system."
    echo "Kubectl error log:"
    cat /tmp/kubectl.err
    exit 1
  fi
  echo "Attempt $attempt/20: Controller pod not ready ($ready_pods/$desired_pods ready), waiting 15 seconds..."
  sleep 15
done

echo "Waiting for MetalLB speaker pod to be ready (up to 300 seconds)..."
for attempt in {1..20}; do
  ready_pods=$(kubectl get pods -n metallb-system -l app=metallb,component=speaker --no-headers 2>/tmp/kubectl.err | grep '1/1' | grep -w 'Running' | wc -l | xargs)
  desired_pods=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -c "k8s-worker")
  if [ "$ready_pods" -eq "$desired_pods" ]; then
    echo "MetalLB speaker pod is ready."
    break
  fi
  if [ $attempt -eq 20 ]; then
    echo "Error: MetalLB speaker pod not ready after 300 seconds ($ready_pods/$desired_pods ready)."
    kubectl get daemonset speaker -n metallb-system 2>/dev/null || echo "Speaker daemonset not found."
    kubectl get pods -n metallb-system 2>/dev/null || echo "No pods found in metallb-system."
    echo "Kubectl error log:"
    cat /tmp/kubectl.err
    exit 1
  fi
  echo "Attempt $attempt/20: Speaker pod not ready ($ready_pods/$desired_pods ready), waiting 15 seconds..."
  sleep 15
done

# Apply MetalLB configuration
echo "Applying MetalLB configuration..."
kubectl apply -f "$METALLB_CONFIG_PATH"
if [ $? -ne 0 ]; then
  echo "Error: Failed to apply MetalLB configuration."
  kubectl describe service metallb-webhook-service -n metallb-system 2>/dev/null || echo "Webhook service not found."
  kubectl logs -n metallb-system -l app=metallb,component=controller 2>&1 || echo "No controller pod logs available."
  exit 1
fi

echo "MetalLB configuration applied successfully."