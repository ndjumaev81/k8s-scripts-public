# Run the script with the desired number of replicas: 
./update-postgres-cluster-hosts.sh 3
# This updates the DB_HOSTS variable in your PgPool-II deployment and restarts the pods to apply the changes.


# Check Logs: If the pod still fails, inspect the logs of the init-replica container to identify the exact error:
kubectl logs postgres-1 -n postgres-system -c init-replica


# Testing Database Connectivity
psql -h postgres-0.postgres.postgres-system.svc.cluster.local -U replicator -d postgres -c "SELECT 1;"
# And the output was:
 ?column? 
----------
        1
(1 row)

This simple query’s success tells us several important things:
    DNS Works: The hostname postgres-0.postgres.postgres-system.svc.cluster.local resolved correctly, meaning Kubernetes DNS is functioning and the service is properly configured.
    Network Is Open: The Pgpool container can reach the PostgreSQL pod (postgres-0) on port 5432, indicating no network issues or blocking policies.
    Authentication Succeeds: The replicator user connected successfully, so the credentials are valid and the user has access to the postgres database.
    Query Runs: The database is operational, and the user has permission to execute queries.
# Your test shows that the basic connectivity between Pgpool and at least one PostgreSQL pod (postgres-0) is working.