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

# Resource Usage: Monitor the primary’s CPU/memory:
kubectl top pod postgres-0 -n postgres-system

# Master
SELECT datname FROM pg_database;
CREATE DATABASE repl_test_db;
\c repl_test_db
CREATE TABLE test_table (id SERIAL PRIMARY KEY, name TEXT);
INSERT INTO test_table (name) VALUES ('test1'), ('test2');
INSERT INTO test_table (name) VALUES ('test3');

# Replica
SELECT datname FROM pg_database;
\c repl_test_db
SELECT * FROM test_table;

# On the master, check replication status:
SELECT * FROM pg_stat_replication;
# Look for the replica’s state (e.g., streaming), indicating active replication.

# On the replica, verify it’s in recovery mode (read-only):
# -- Run this to determine the instance's role
SELECT pg_is_in_recovery();

#   -- Result 'f' = Master (Primary)
#   -- Result 't' = Replica (Standby)

# Scaling Up to 3 and Down back to 2 Replicas. Don't forget to update pgpool config.
Pgpool Limitation: The PGPOOL_BACKEND_NODES in your YAML is static and doesn’t include postgres-2. You may need to update it dynamically or configure Pgpool’s watchdog for automatic node detection.