#!/bin/bash

# Check if NFS path argument is provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <nfs-server-ip> <nfs-path>"
    echo "Example: $0 192.168.64.1 /Users/ubuntu/nfs-share"
    exit 1
fi

NFS_SERVER="$1"
NFS_PATH="$2"

# Export variables for envsubst
export NFS_SERVER NFS_PATH

# Generate and apply the YAML
cat <<EOF | envsubst | kubectl apply -f -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nfs-provisioner
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: nfs-provisioner-role
rules:
- apiGroups: [""]
  resources: ["persistentvolumes"]
  verbs: ["get", "list", "watch", "create", "delete"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list", "watch", "update"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["create", "update", "patch"]
- apiGroups: [""]
  resources: ["endpoints"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: nfs-provisioner-binding
subjects:
- kind: ServiceAccount
  name: nfs-provisioner
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: nfs-provisioner-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-provisioner
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nfs-provisioner
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: nfs-provisioner
    spec:
      serviceAccountName: nfs-provisioner
      containers:
      - name: nfs-provisioner
        image: gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:v4.0.2
        env:
        - name: PROVISIONER_NAME
          value: nfs-provisioner
        - name: NFS_SERVER
          value: ${NFS_SERVER}
        - name: NFS_PATH
          value: ${NFS_PATH}
        volumeMounts:
        - name: nfs-client-root
          mountPath: /persistentvolumes
      volumes:
      - name: nfs-client-root
        nfs:
          server: ${NFS_SERVER}
          path: ${NFS_PATH}
---
# StorageClass Definition (Delete Policy)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-storage-delete
provisioner: nfs-provisioner
reclaimPolicy: Delete
parameters:
  archiveOnDelete: "false"

---
# New StorageClass Definition (Retain Policy)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-storage-retain
provisioner: nfs-provisioner
reclaimPolicy: Retain
parameters:
  archiveOnDelete: "false"
EOF

echo "NFS provisioner deployed with server ${NFS_SERVER} and path ${NFS_PATH}."
