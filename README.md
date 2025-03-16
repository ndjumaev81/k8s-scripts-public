# k8s-scripts-public
Multipass kubernetes

Make it executable: chmod +x master.sh

Run it with the master IP: ./master.sh 192.168.64.X

Make it executable: chmod +x worker.sh

Run it with the master IP: ./worker.sh 192.168.64.X


Steps to Test LoadBalancer Type with MetalLB
MetalLB provides load balancer functionality in bare-metal Kubernetes clusters.
Apply MetalLB Manifests: On the master VM:

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

This deploys the MetalLB controller and speaker pods in the metallb-system namespace.

