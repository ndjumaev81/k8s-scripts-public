#!/bin/bash

# Launch VMs with specified parameters
#./launch-vm-1.sh 2 4 20 master &
./launch-vm-1.sh 4 6 20 worker-1 &
./launch-vm-1.sh 4 6 20 worker-2 &
./launch-vm-1.sh 4 6 20 worker-3 &
./launch-vm-1.sh 4 6 20 worker-4 &

# echo "multipass vms launched..."

# Wait for all background VM launches to complete
wait