# HAProxy Deployment and Validation

## 1. Overview

HAProxy provides a stable endpoint for applications to connect to the PostgreSQL HA cluster.

The application does not connect directly to either PostgreSQL node. Instead, it connects to HAProxy, which forwards new connections to the current PostgreSQL primary.

```text
Application / Test Client
          |
          v
      HAProxy
    127.0.0.1:15432
          |
          v
 Current PostgreSQL Primary
          |
          v
     PostgreSQL Replica
```

Patroni is responsible for PostgreSQL leader election and failover. HAProxy only routes connections based on the health/status of the PostgreSQL nodes.

---

## 2. HAProxy Environment

For this lab, HAProxy runs in Docker on the Ansible control machine (MacBook).

The HAProxy container uses:

```text
HAProxy image: haproxy:3.3.14-alpine3.24
HAProxy container port: 5432
Host port: 15432
Stats/monitoring port: 8404
```

The resulting endpoint for the test client is:

```text
127.0.0.1:15432
```

Docker port mapping:

```text
0.0.0.0:15432 -> 5432
0.0.0.0:8404  -> 8404
```

---

## 3. Deployment with Ansible

HAProxy is deployed using a dedicated Ansible playbook:

```bash
ansible-playbook \
  -i ansible/inventory/hosts.yml \
  ansible/site-haproxy.yml \
  --ask-vault-pass
```

The playbook performs the following steps:

1. Creates the HAProxy working directory.
2. Deploys the HAProxy configuration from the Ansible template.
3. Deploys the Docker Compose file.
4. Starts HAProxy using Docker Compose.

Example successful deployment:

```text
TASK [haproxy : Create HAProxy directory]
ok

TASK [haproxy : Deploy HAProxy configuration]
ok

TASK [haproxy : Deploy Docker Compose file]
ok

TASK [haproxy : Start HAProxy with Docker Compose]
ok
```

The deployment completed successfully with:

```text
ok=4
changed=0
unreachable=0
failed=0
```

---

## 4. Verify the HAProxy Container

After deployment, the container was verified with:

```bash
docker ps
```

The resulting container exposed:

```text
0.0.0.0:8404  -> 8404/tcp
0.0.0.0:15432 -> 5432/tcp
```

The container was running with the expected HAProxy image:

```text
haproxy:3.3.14-alpine3.24
```

---

## 5. PostgreSQL Connectivity Test

The MacBook did not have the PostgreSQL client installed, so a temporary PostgreSQL container was used as the test client.

The following command was used:

```bash
docker run --rm -it \
  -e PGPASSWORD=postgres \
  postgres:16 \
  psql -h host.docker.internal -p 15432 -U postgres -d postgres
```

`host.docker.internal` allows the temporary Docker container to reach the Docker host.

The connection path was:

```text
Temporary PostgreSQL Client
        |
        v
host.docker.internal:15432
        |
        v
HAProxy
        |
        v
PostgreSQL:5432
```

The initial connection was verified with:

```sql
SELECT
    inet_server_addr(),
    inet_server_port(),
    pg_is_in_recovery();
```

Before failover, the result was:

```text
inet_server_addr | inet_server_port | pg_is_in_recovery
-----------------+------------------+------------------
192.168.64.5     |             5432 | f
```

This confirmed that HAProxy was forwarding the connection to `postgres-1`, which was the current writable primary.

---

## 6. HAProxy Failover Test

The failover test was performed while keeping the application/test-client architecture unchanged.

Initial cluster state:

```text
postgres-1  192.168.64.5  Leader
postgres-2  192.168.64.6  Replica
```

The existing client connection was established through:

```text
127.0.0.1:15432
```

Patroni was then stopped on the current primary:

```bash
sudo systemctl stop patroni
```

Patroni detected the failure and promoted `postgres-2`.

The observed cluster state became:

```text
postgres-1  192.168.64.5  Replica  stopped
postgres-2  192.168.64.6  Leader   running
```

The new leader was on timeline 6.

---

## 7. New Client Connection After Failover

After the failover, a new PostgreSQL connection was established through the same HAProxy endpoint:

```text
127.0.0.1:15432
```

The following query was used:

```sql
SELECT
    now(),
    inet_server_addr(),
    inet_server_port(),
    pg_is_in_recovery();
```

The result was:

```text
inet_server_addr | inet_server_port | pg_is_in_recovery
-----------------+------------------+------------------
192.168.64.6     |             5432 | f
```

This confirmed that a new client connection through HAProxy was routed to the newly promoted primary.

The resulting path was:

```text
Client
  |
  v
HAProxy :15432
  |
  v
postgres-2 :5432
  |
  v
Leader
```

---

## 8. Write Test After Failover

A write operation was performed through the HAProxy connection after failover.

A temporary test table was created:

```sql
CREATE TABLE IF NOT EXISTS ha_failover_test (
    id BIGSERIAL PRIMARY KEY,
    message TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

A test row was inserted:

```sql
INSERT INTO ha_failover_test (message)
VALUES ('haproxy-failover-test')
RETURNING *;
```

The insert succeeded:

```text
id | message              | created_at
---+----------------------+-------------------------------
1  | haproxy-failover-test | 2026-09-27 17:22:08.994543+00
```

The row was then queried successfully.

This confirmed that the newly promoted primary was writable through the HAProxy endpoint.

---

## 9. Recovery of the Previous Primary

After the failover test, Patroni was started again on `postgres-1`:

```bash
sudo systemctl start patroni
```

The final cluster state was:

```text
+------------+--------------+---------+-----------+----+-----------+
| Member     | Host         | Role    | State     | TL | Lag in MB |
+------------+--------------+---------+-----------+----+-----------+
| postgres-1 | 192.168.64.5 | Replica | running   |  6 |         0 |
| postgres-2 | 192.168.64.6 | Leader  | running   |  6 |           |
+------------+--------------+---------+-----------+----+-----------+
```

`postgres-1` automatically rejoined the cluster as a replica.

No manual `reinit` was required.

Replication returned to:

```text
Lag: 0 MB
```

---

## 10. Test Result

### HAProxy Primary Failover Test

**Result: PASS under the tested conditions**

The test demonstrated that:

* The client can connect through the HAProxy endpoint.
* HAProxy initially routes the client to the current primary.
* Patroni can promote the replica after primary failure.
* A new connection through the same HAProxy endpoint reaches the new primary.
* The new primary accepts writes.
* The previous primary can return to the cluster as a replica.
* Replication recovers to zero reported lag.

### Observed Architecture

Before failure:

```text
Client
  |
  v
HAProxy
  |
  v
postgres-1
  Leader
  |
  | Streaming Replication
  v
postgres-2
  Replica
```

After failure:

```text
Client
  |
  v
HAProxy
  |
  v
postgres-2
  Leader
```

After recovery:

```text
Client
  |
  v
HAProxy
  |
  v
postgres-2
  Leader
  |
  | Streaming Replication
  v
postgres-1
  Replica
```

---

## 11. Important Limitation

The test verifies **new client connections** after failover.

It does not demonstrate transparent migration of an existing PostgreSQL session.

An established PostgreSQL connection can be terminated when its backend PostgreSQL node fails. The application must therefore be able to reconnect through HAProxy.

For a production application, connection pooling, retry/backoff, transaction handling, and idempotency should be considered separately.

---

## 12. HAProxy Responsibility

HAProxy is responsible for providing a stable connection endpoint and routing connections to the appropriate PostgreSQL node.

Patroni remains responsible for:

* Leader election
* PostgreSQL promotion
* PostgreSQL demotion
* Cluster state management
* Coordination through etcd

The architecture therefore separates responsibilities:

```text
                    +----------------+
                    |   Application  |
                    +-------+--------+
                            |
                            v
                    +---------------+
                    |    HAProxy    |
                    | Stable Endpoint|
                    +-------+-------+
                            |
                            v
                    +---------------+
                    | Current Leader|
                    +-------+-------+
                            |
                     Replication
                            |
                            v
                    +---------------+
                    |    Replica    |
                    +---------------+

             Patroni <----> etcd
                |
                +-- PostgreSQL HA management
```

HAProxy does not perform leader election. It follows the health/state information exposed by the PostgreSQL HA design and provides the stable endpoint used by clients.
