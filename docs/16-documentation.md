# 14. Documentation

This repository contains documentation for deployment, architecture, operations, validation, and failure testing of the PostgreSQL High Availability platform.

The documentation is organized by topic so that deployment instructions, operational procedures, and design decisions can be reviewed independently.

## Deployment

The deployment documentation covers the prerequisites, installation process, environment access, validation, and cluster recreation.

### Prerequisites

The lab environment consists of:

* 3 etcd nodes
* 2 PostgreSQL nodes
* 2 Patroni instances, one on each PostgreSQL node
* 1 HAProxy instance
* Ansible as the deployment and configuration tool

The PostgreSQL nodes run PostgreSQL 16 and Patroni 3.2.2. The etcd cluster uses three members to maintain quorum.

The complete environment and node addressing are documented in [Architecture](01-architecture.md).

### Installation and Deployment

The complete deployment is automated with Ansible.

The main entry point is:

```text
ansible/site.yml
```

The deployment is divided into roles:

```text
common
etcd
postgresql
patroni
```

The cluster can be deployed with:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/site.yml --ask-vault-pass
ansible-playbook -i ansible/inventory/hosts.yml ansible/site-haproxy.yml --ask-vault-pass
```

Sensitive values such as PostgreSQL and replication passwords are stored using Ansible Vault and are not kept in plaintext in the repository.

### Environment Access

The PostgreSQL nodes are accessed through SSH for administrative and troubleshooting operations.

Patroni is managed through its virtual environment:

```text
/opt/patroni/venv/bin/patronictl
```

The Patroni configuration is located at:

```text
/etc/patroni/config.yml
```

PostgreSQL listens on port `5432`, while Patroni exposes its REST API on port `8008`.

The HAProxy layer provides the stable endpoint for applications and hides the individual PostgreSQL node addresses from clients.

### Validation

After deployment, the cluster can be validated using:

```bash
sudo ./tests/validate-cluster.sh
```

The validation script checks:

* Patroni cluster availability
* Existence of exactly one leader
* PostgreSQL connectivity
* PostgreSQL role
* Replication status
* Replication lag

A successful validation produces:

```text
PASS: 5
FAIL: 0

RESULT: VALIDATION PASSED
```

Detailed validation procedures are documented in [Validation](07-validation.md).

### Destruction and Recreation

The lab environment is designed to be reproducible.

Individual components can be removed and recreated through Ansible rather than being manually configured on the servers.

For a complete rebuild, the virtual machines can be recreated and the Ansible deployment executed again.

After recreation, the same validation and failure-test procedures should be executed to verify that the cluster has returned to the expected state.

---

## Architecture

The platform consists of PostgreSQL, Patroni, etcd, HAProxy, and Ansible.

The logical architecture is:

```text
                         Application
                              |
                              v
                           HAProxy
                              |
                              v
                     Current Primary
                       PostgreSQL
                              |
                    Streaming Replication
                              |
                              v
                    PostgreSQL Replica


                 +-----------------------+
                 |       Patroni         |
                 +-----------+-----------+
                             |
                             v
                      +-------------+
                      |     etcd    |
                      |   3 nodes   |
                      +-------------+
```

### Component Responsibilities

| Component  | Responsibility                                                                                    |
| ---------- | ------------------------------------------------------------------------------------------------- |
| PostgreSQL | Stores application data and provides database services                                            |
| Patroni    | Manages PostgreSQL HA, leader election and failover                                               |
| etcd       | Provides distributed coordination and leader state storage for Patroni                            |
| HAProxy    | Provides a stable application endpoint and routes traffic to the current writable PostgreSQL node |
| Ansible    | Automates installation and configuration                                                          |

Patroni is responsible for determining which PostgreSQL node is the leader. HAProxy does not perform leader election.

HAProxy uses PostgreSQL/Patroni health information to determine which node should receive application traffic.

### Data Flow

Under normal conditions:

```text
Application
    |
    v
 HAProxy
    |
    v
PostgreSQL Primary
    |
    | WAL / Streaming Replication
    v
PostgreSQL Replica
```

Writes are handled by the current primary.

The replica continuously receives WAL changes from the primary using PostgreSQL physical streaming replication.

### Client Connection Flow

Applications should connect to the HAProxy endpoint instead of connecting directly to a PostgreSQL node.

```text
Application
      |
      v
 HAProxy Endpoint
      |
      v
Current PostgreSQL Primary
```

This prevents the application from having to know which PostgreSQL node is currently the primary.

After a failover, new connections are routed to the new primary.

Existing TCP/database connections are not transparently migrated. Applications must be able to reconnect and should use connection pooling and bounded retry logic.

More details are documented in [Application Connectivity](06-application-connectivity.md).

### Failover Flow

The normal failover sequence is:

```text
Primary PostgreSQL fails
          |
          v
       Patroni
          |
          v
Leader election through etcd
          |
          v
New PostgreSQL Primary
          |
          v
HAProxy detects new writable node
          |
          v
New application connections
          |
          v
New Primary
```

Patroni performs the failover decision and PostgreSQL promotion.

HAProxy only exposes the currently healthy writable node to the application.

### Design Decisions and Trade-offs

The main design decisions are:

* Two PostgreSQL nodes are used to provide database redundancy.
* Three etcd nodes are used to maintain quorum when one etcd member fails.
* Patroni is used instead of implementing custom PostgreSQL failover logic.
* Asynchronous streaming replication is used for the lab.
* HAProxy provides a stable endpoint for applications.
* Ansible is used to make the environment reproducible.
* Ansible Vault is used for repository-level secret protection.

The main trade-off is that asynchronous replication does not provide a strict zero-data-loss guarantee. If the primary fails before WAL has reached the replica, the most recent transactions may not exist on the promoted node.

A stricter RPO would require a different replication configuration, such as synchronous replication, with corresponding latency and availability trade-offs.

---

## Operations

### Identify the Current Primary

The current Patroni leader can be identified with:

```bash
/opt/patroni/venv/bin/patronictl \
  -c /etc/patroni/config.yml list
```

Example:

```text
+ Cluster: postgres-ha -----------------------------+
| Member     | Host         | Role    | State     | TL |
+------------+--------------+---------+-----------+----+
| postgres-1 | 192.168.64.5 | Replica | streaming |  4 |
| postgres-2 | 192.168.64.6 | Leader  | running   |  4 |
+------------+--------------+---------+-----------+----+
```

The node with the `Leader` role is the current writable PostgreSQL node.

### Inspect Replication and Cluster Health

Patroni cluster status:

```bash
/opt/patroni/venv/bin/patronictl \
  -c /etc/patroni/config.yml list
```

PostgreSQL replication status:

```sql
SELECT
    application_name,
    client_addr,
    state,
    sync_state,
    pg_wal_lsn_diff(
        pg_current_wal_lsn(),
        replay_lsn
    ) AS replay_lag_bytes
FROM pg_stat_replication;
```

The expected healthy state is:

```text
state      = streaming
sync_state = async
replay_lag = 0 or within the accepted threshold
```

The validation script combines these checks into a repeatable health check.

### Investigating Degraded Behavior

When investigating a degraded cluster, the following order is useful:

1. Check Patroni cluster state.
2. Identify the current leader.
3. Check whether PostgreSQL is running.
4. Check replication state and lag.
5. Check Patroni logs.
6. Check PostgreSQL logs.
7. Check etcd quorum and connectivity.
8. Check host and network connectivity.
9. Check HAProxy backend health.
10. Check application connectivity.

A replica being unavailable does not necessarily mean that the application is unavailable. It does, however, mean that the HA protection level has been reduced.

### Recovering or Reintegrating Failed Nodes

After a failed PostgreSQL node is recovered:

1. Verify the operating system and PostgreSQL services.
2. Verify network connectivity to the primary and etcd.
3. Start Patroni.
4. Check the Patroni cluster state.
5. Confirm that the node joins as a replica.
6. Confirm that replication returns to `streaming`.
7. Verify replication lag returns to the expected level.

For example:

```bash
systemctl start patroni

/opt/patroni/venv/bin/patronictl \
  -c /etc/patroni/config.yml list
```

The node should return as a `Replica` rather than being manually promoted.

If the PostgreSQL data directory is no longer usable, the node may need to be reinitialized from the current primary using Patroni.

### Common Operational Procedures

Useful operational commands include:

Check Patroni:

```bash
systemctl status patroni
```

Restart Patroni:

```bash
systemctl restart patroni
```

Check PostgreSQL:

```bash
systemctl status postgresql
```

Check the Patroni cluster:

```bash
/opt/patroni/venv/bin/patronictl \
  -c /etc/patroni/config.yml list
```

Check PostgreSQL recovery state:

```sql
SELECT pg_is_in_recovery();
```

Check replication:

```sql
SELECT * FROM pg_stat_replication;
```

Planned primary switchovers should be performed through Patroni rather than manually stopping or promoting PostgreSQL.

---

## Failure Tests

Failure testing was performed to verify the behavior of the cluster under different failure conditions.

### Primary Failure

```text
Failure:
Primary Patroni/PostgreSQL node terminated.

Detection time:
~6 seconds.

Failover time:
~6 seconds until the new leader was observed.

New primary:
postgres-2.

Data loss:
None observed under the tested conditions.

Client impact:
Not measured end-to-end through HAProxy in this test.

Final cluster state:
Healthy.
```

Before the test:

```text
postgres-1  Leader
postgres-2  Replica
```

After stopping Patroni on `postgres-1`:

```text
postgres-1  Replica / stopped
postgres-2  Leader
```

A test record was inserted on the new primary after failover and was later confirmed on the recovered replica.

After restarting Patroni on `postgres-1`, the node automatically rejoined as a replica and replication returned to zero observed lag.

### Replica Failure

```text
Failure:
Replica node terminated.

Detection time:
Observed through Patroni state.

Failover time:
No failover required.

New primary:
postgres-2 remained primary.

Data loss:
None.

Client impact:
No primary-side interruption.

Final cluster state:
Healthy after replica recovery.
```

The primary remained available while the replica was offline.

After the replica was restarted, it automatically rejoined the cluster and caught up with the primary.

### Replica-Side Network Partition

```text
Failure:
Network connectivity from the replica to the primary and DCS was blocked.

Detection time:
Observed through Patroni connectivity failure.

Failover time:
No failover required.

New primary:
postgres-2 remained primary.

Data loss:
None observed.

Client impact:
Primary-side client traffic remained available.

Final cluster state:
Healthy after network connectivity was restored.
```

During the partition, the isolated replica remained read-only and was not promoted.

After the firewall rules were removed, the replica reconnected and returned to the expected cluster state.

This test covered a replica-side partition. A leader-side network partition was not used as the final validation scenario.

### Replication Failure

```text
Failure:
Replication TCP traffic between PostgreSQL nodes was blocked.

Detection time:
Replication connection disappeared from pg_stat_replication.

Failover time:
No failover required.

New primary:
postgres-2 remained primary.

Data loss:
No data loss after replication recovery.

Client impact:
Primary remained available.

Final cluster state:
Healthy after replication recovery.
```

During the test, replication was intentionally blocked and three test records were written to the primary.

The replica stopped receiving new WAL while the connection was blocked.

After network connectivity was restored, replication automatically resumed and the replica caught up without requiring a rebuild or reinitialization.

### Failure Test Summary

| Test                           | Result | Final State |
| ------------------------------ | ------ | ----------- |
| Primary failure                | PASS   | Healthy     |
| Replica failure                | PASS   | Healthy     |
| Replica-side network partition | PASS   | Healthy     |
| Replication failure            | PASS   | Healthy     |

The tests confirmed Patroni failover, replica recovery, replication recovery, and cluster reintegration under the tested conditions.

End-to-end HAProxy client reconnection and application impact have not yet been measured as part of these tests and should be added to the validation plan.

---

## Related Documentation

The repository contains dedicated documentation for the major platform components and operational concerns:

* [Architecture](01-architecture.md)
* [Assumptions](02-assumptions.md)
* [Design Decisions](03-design-decisions.md)
* [PostgreSQL Configuration](04-postgresql-configuration.md)
* [HAProxy](05-haproxy.md)
* [Application Connectivity](06-application-connectivity.md)
* [Validation](07-validation.md)
* [Failure Testing](08-failure-testing.md)
* [Operations](09-operations.md)
* [Security](10-security.md)
* [Backup and Recovery](11-backup-recovery.md)
* [Observability](12-observability.md)
* [RPO and RTO](13-rpo-rto.md)
* [Application-Level Considerations](14-application-considerations.md)
* [Production Architecture](15-production-architecture.md)
* [Documentation](16-documentation.md)
* [Optional Extensions](17-optional-extensions.md)
