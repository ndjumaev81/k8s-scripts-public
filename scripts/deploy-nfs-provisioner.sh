#!/bin/bash

# Check if NFS server IP argument is provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <nfs-server-ip>"
    echo "Example: $0 192.168.64.1 <username>"
    exit 1
fi

NFS_SERVER="$1"
USERNAME="$2"

USER_UID=$(id -u "$USERNAME")
USER_GID=$(id -g "$USERNAME")

# Define paths for each subdirectory
NFS_PATH_P1000="/Users/$USERNAME/nfs-share/p1000"
NFS_PATH_P999="/Users/$USERNAME/nfs-share/p999"
NFS_PATH_P501="/Users/$USERNAME/nfs-share/p501"
NFS_PATH_P101="/Users/$USERNAME/nfs-share/p101"

# Export variables for envsubst
export NFS_SERVER

# Generate and apply the YAML for each StorageClass
# StorageClass for P1000 (UID/GID 1000:1000)
export NFS_PATH="$NFS_PATH_P1000"
cat <<EOF | envsubst | kubectl apply -f -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nfs-provisioner-p1000
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: nfs-provisioner-p1000-role
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
  name: nfs-provisioner-p1000-binding
subjects:
- kind: ServiceAccount
  name: nfs-provisioner-p1000
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: nfs-provisioner-p1000-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-provisioner-p1000
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nfs-provisioner-p1000
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: nfs-provisioner-p1000
    spec:
      serviceAccountName: nfs-provisioner-p1000
      containers:
      - name: nfs-provisioner
        image: gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:v4.0.2
        env:
        - name: PROVISIONER_NAME
          value: nfs-provisioner-p1000
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
# StorageClass Definition (Retain Policy)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-p1000-retain
provisioner: nfs-provisioner-p1000
reclaimPolicy: Retain
parameters:
  archiveOnDelete: "false"
mountOptions:
  - vers=3
---
# StorageClass Definition (Delete Policy)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-p1000
provisioner: nfs-provisioner-p1000
reclaimPolicy: Delete
parameters:
  archiveOnDelete: "false"
EOF

# StorageClass for P999 (UID/GID 999:999)
export NFS_PATH="$NFS_PATH_P999"
cat <<EOF | envsubst | kubectl apply -f -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nfs-provisioner-p999
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: nfs-provisioner-p999-role
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
  name: nfs-provisioner-p999-binding
subjects:
- kind: ServiceAccount
  name: nfs-provisioner-p999
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: nfs-provisioner-p999-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-provisioner-p999
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nfs-provisioner-p999
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: nfs-provisioner-p999
    spec:
      serviceAccountName: nfs-provisioner-p999
      containers:
      - name: nfs-provisioner
        image: gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:v4.0.2
        env:
        - name: PROVISIONER_NAME
          value: nfs-provisioner-p999
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
# StorageClass Definition (Retain Policy)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-p999-retain
provisioner: nfs-provisioner-p999
reclaimPolicy: Retain
parameters:
  archiveOnDelete: "false"
mountOptions:
  - vers=3
---
# StorageClass Definition (Delete Policy)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-p999
provisioner: nfs-provisioner-p999
reclaimPolicy: Delete
parameters:
  archiveOnDelete: "false"
EOF

# StorageClass for default (UID/GID 501:20)
export NFS_PATH="$NFS_PATH_P501"
cat <<EOF | envsubst | kubectl apply -f -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nfs-provisioner-p501
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: nfs-provisioner-p501-role
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
  name: nfs-provisioner-p501-binding
subjects:
- kind: ServiceAccount
  name: nfs-provisioner-p501
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: nfs-provisioner-p501-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-provisioner-p501
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nfs-provisioner-p501
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: nfs-provisioner-p501
    spec:
      serviceAccountName: nfs-provisioner-p501
      containers:
      - name: nfs-provisioner
        image: gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:v4.0.2
        env:
        - name: PROVISIONER_NAME
          value: nfs-provisioner-p501
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
# StorageClass Definition (Retain Policy)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-p501-retain
provisioner: nfs-provisioner-p501
reclaimPolicy: Retain
parameters:
  archiveOnDelete: "false"
mountOptions:
  - vers=3
---
# StorageClass Definition (Delete Policy)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-p501
provisioner: nfs-provisioner-p501
reclaimPolicy: Delete
parameters:
  archiveOnDelete: "false"
EOF

# StorageClass for P101 (UID/GID 101:101)
export NFS_PATH="$NFS_PATH_P101"
cat <<EOF | envsubst | kubectl apply -f -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nfs-provisioner-nginx
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: nfs-provisioner-nginx-role
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
  name: nfs-provisioner-nginx-binding
subjects:
- kind: ServiceAccount
  name: nfs-provisioner-nginx
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: nfs-provisioner-nginx-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-provisioner-nginx
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nfs-provisioner-nginx
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: nfs-provisioner-nginx
    spec:
      serviceAccountName: nfs-provisioner-nginx
      containers:
      - name: nfs-provisioner
        image: gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:v4.0.2
        env:
        - name: PROVISIONER_NAME
          value: nfs-provisioner-nginx
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
# StorageClass Definition (Retain Policy)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-p101-retain
provisioner: nfs-provisioner-p101
reclaimPolicy: Retain
parameters:
  archiveOnDelete: "false"
mountOptions:
  - vers=3
---
# StorageClass Definition (Delete Policy)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-p101
provisioner: nfs-provisioner-p101
reclaimPolicy: Delete
parameters:
  archiveOnDelete: "false"
EOF

echo "NFS provisioners deployed with server ${NFS_SERVER}:"
echo "- P1000 (UID/GID 1000:1000) at ${NFS_PATH_P1000}"
echo "- P999 (UID/GID 999:999) at ${NFS_PATH_P999}"
echo "- P101 (UID/GID 101:101) at ${NFS_PATH_P101}"
echo "- P501 (UID/GID ${USER_UID}:${USER_GID}) at ${NFS_PATH_P501}"