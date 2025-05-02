# Run the script with the desired number of replicas: 
./update-postgres-cluster-hosts.sh 3
# This updates the DB_HOSTS variable in your PgPool-II deployment and restarts the pods to apply the changes.


# Check Logs: If the pod still fails, inspect the logs of the init-replica container to identify the exact error:
kubectl logs postgres-1 -n postgres-system -c init-replica