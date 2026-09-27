# PostgreSQL Configuration and Operational Readiness

## 6.1 Configuration Approach

The PostgreSQL configuration was designed for a small two-node HA environment managed by Patroni.

The primary goals are:

* Automatic failover.
* Reliable streaming replication.
* Safe replica recovery.
* Reasonable durability.
* Predictable behavior under failure.
* Avoiding unnecessary performance tuning without workload measurements.

The environment used for this implementation is a lab environment with two PostgreSQL nodes:

```text
postgres-1  192.168.64.5
postgres-2  192.168.64.6
```

PostgreSQL 16 is used on both nodes and PostgreSQL lifecycle management is handled by Patroni.

The configuration is intentionally conservative. Performance-related parameters are not aggressively tuned because there is no representative production workload or benchmark data available yet.

---

## 6.2 PostgreSQL Version and Package Management

PostgreSQL 16 is used consistently across both nodes.

The same PostgreSQL major version is maintained on the primary and replica because physical streaming replication requires compatible PostgreSQL versions.

The database installation and configuration are managed through Ansible rather than being configured manually on individual nodes.

This provides:

* Repeatable configuration.
* Consistent settings across nodes.
* Easier recovery and replacement of a node.
* Version-controlled infrastructure changes.

A production implementation should also define a controlled PostgreSQL upgrade strategy rather than treating package upgrades as normal configuration changes.

---

## 6.3 Data Directory

The PostgreSQL data directory is:

```text
/var/lib/postgresql/16/main
```

Patroni manages the PostgreSQL instance using this directory.

The important operational decision is that PostgreSQL data is managed by Patroni rather than by the default Ubuntu PostgreSQL systemd service.

This avoids having two independent service managers attempting to control the same PostgreSQL instance.

### Operational consideration

The data directory should be placed on storage with appropriate:

* IOPS.
* Latency.
* Capacity.
* Filesystem reliability.
* Monitoring.

The lab does not attempt to benchmark or optimize the underlying storage.

In production, storage performance should be validated using representative workload tests before selecting final PostgreSQL parameters.

---

## 6.4 WAL and Replication Configuration

The current replication-related settings are:

```yaml
wal_level: replica
hot_standby: "on"
max_wal_senders: 10
max_replication_slots: 10
```

### `wal_level`

```text
wal_level = replica
```

`replica` is sufficient for physical streaming replication used by this HA setup.

A higher value such as `logical` would only be selected if logical replication or another feature requiring it was actually needed.

Using a higher WAL level without a requirement can introduce additional WAL overhead.

### `hot_standby`

```text
hot_standby = on
```

This allows the standby to accept read-only queries while it is recovering WAL.

The current HA design primarily uses the standby for failover rather than read scaling, but enabling hot standby is useful for operational inspection and future read-only workloads.

### `max_wal_senders`

```text
max_wal_senders = 10
```

The current environment requires only one streaming replica.

The value `10` provides additional capacity for future replication connections, operational tools, or additional replicas without being excessively large for this small environment.

This value should be revisited if the topology changes.

### `max_replication_slots`

```text
max_replication_slots = 10
```

Replication slots are enabled through:

```yaml
use_slots: true
```

Replication slots prevent PostgreSQL from removing WAL that a registered replica still needs.

This helps a temporarily disconnected replica recover without requiring a full reinitialization, provided the required WAL remains available.

However, replication slots introduce an important operational risk: an inactive slot can cause WAL to accumulate on the primary and eventually consume significant disk space.

Therefore, replication slot usage must be monitored in production.

---

## 6.5 PostgreSQL Replication Model

The implementation uses asynchronous physical streaming replication.

This decision provides a balance between:

* Failover capability.
* Write performance.
* Simplicity.
* Availability.

The primary does not have to wait for the replica to acknowledge every transaction before completing a commit.

The trade-off is that a primary failure can theoretically result in the loss of transactions that had not yet reached the replica.

This was also demonstrated conceptually during the replication failure test: while replication was disconnected, the primary continued accepting writes and the replica did not immediately receive those changes.

Therefore, the current implementation provides **high availability with near-zero expected RPO under normal conditions**, but it does not provide a strict zero-data-loss guarantee.

If the workload requires strict durability guarantees, synchronous replication should be evaluated instead.

---

## 6.6 Connection and Access Configuration

The PostgreSQL listener is configured as:

```text
0.0.0.0:5432
```

The node's specific address is advertised to Patroni through:

```text
connect_address
```

This is necessary because other cluster components must be able to reach PostgreSQL on each node.

Access control is enforced through PostgreSQL `pg_hba.conf`, managed by Patroni.

The current lab configuration allows:

* Local PostgreSQL access.
* PostgreSQL client access from the lab subnet.
* Replication connections from the lab subnet.

The lab uses:

```text
192.168.64.0/24
```

as its PostgreSQL network.

This is acceptable for the isolated lab environment, but production access should be restricted to the required application, replication, monitoring, and administration networks.

Broad network access should not be copied from the lab into production without reviewing the actual network topology.

---

## 6.7 Authentication

Two separate PostgreSQL credentials are configured through Patroni:

* PostgreSQL superuser.
* Replication user.

The replication user is separate from the PostgreSQL administrative user.

This follows the principle of using a dedicated identity for replication rather than using the database superuser for all operations.

Credentials are stored using Ansible Vault rather than directly in the repository.

Rendered Patroni configuration files contain the credentials required by the running service and therefore require appropriate filesystem permissions.

The Patroni configuration is currently protected with:

```text
0600
```

and owned by the `postgres` user.

---

## 6.8 PostgreSQL Authentication Rules

The current lab includes:

```text
local all all trust
```

This is intentionally convenient for the local lab, where administrative commands are commonly executed through:

```bash
sudo -u postgres psql
```

It should not automatically be copied to production.

For a production deployment, local authentication should be reviewed and changed to an authentication method appropriate for the operational model.

Network connections use SCRAM authentication:

```text
scram-sha-256
```

This is preferable to storing or transmitting PostgreSQL passwords using older authentication mechanisms.

---

## 6.9 Durability and Commit Behavior

The current implementation does not explicitly override PostgreSQL's default durability-related parameters such as:

```text
fsync
full_page_writes
synchronous_commit
```

The decision is deliberate.

There is currently no workload benchmark or hardware-specific evidence that justifies changing these defaults.

For a production environment, disabling durability-related protections to improve performance would require strong evidence and explicit acceptance of the resulting risk.

The expected approach is:

1. Start with PostgreSQL's safe defaults.
2. Measure the workload.
3. Identify an actual bottleneck.
4. Change only the relevant parameter.
5. Benchmark the effect.
6. Validate failure and recovery behavior again.

Performance should not be optimized by disabling durability mechanisms without understanding the resulting recovery implications.

---

## 6.10 WAL Retention and Disk Capacity

WAL management is particularly important because the cluster uses replication slots.

A replica that remains disconnected can cause WAL to accumulate on the primary.

This creates a failure mode where a replication problem can eventually become a primary storage problem.

Production monitoring should therefore track at least:

* WAL generation rate.
* WAL directory size.
* Replication slot retention.
* Replica replay position.
* Replication lag.
* Available filesystem space.

A suitable operational alert should be based on both absolute disk usage and growth rate rather than relying on a single fixed threshold.

The appropriate thresholds should be determined from observed workload characteristics and available storage capacity.

---

## 6.11 Memory and Connection Configuration

No aggressive memory or connection tuning has been applied to the lab.

Parameters such as:

```text
shared_buffers
work_mem
maintenance_work_mem
effective_cache_size
max_connections
```

depend strongly on:

* Available RAM.
* Application connection behavior.
* Query patterns.
* Concurrent workload.
* Connection pooling.
* Storage performance.

For this reason, applying a generic percentage-based tuning guide would not be appropriate without workload information.

In production, these values should be established through measurement.

Connection pooling should also be considered if the application creates a large number of short-lived PostgreSQL connections. Increasing `max_connections` indefinitely is generally not a substitute for proper connection management.

---

## 6.12 Failover and Recovery Considerations

Patroni is responsible for PostgreSQL lifecycle and failover decisions.

The relevant DCS and Patroni parameters include:

```yaml
ttl: 30
loop_wait: 10
retry_timeout: 10
```

These values determine part of the failure detection and coordination behavior.

The lab observed an automatic failover of approximately 6 seconds during the primary failure test.

The observed result depends on the actual timing of the failure relative to Patroni's control loop and should not be considered a guaranteed failover time.

Reducing these values could improve failure detection time, but overly aggressive settings can increase sensitivity to temporary network latency or DCS problems.

Therefore, these parameters should be tuned based on measured failure behavior rather than simply minimizing them.

---

## 6.13 Operational Monitoring

A production PostgreSQL HA deployment should monitor both database health and cluster health.

Important signals include:

### PostgreSQL

* Database availability.
* Connection count.
* Transaction rate.
* Query latency.
* Errors.
* Locks.
* Deadlocks.
* Long-running queries.
* Checkpoint behavior.
* WAL generation.
* Disk usage.

### Replication

* Replication connection state.
* Replica lag.
* Replay position.
* WAL sender state.
* Replication slot status.
* WAL retained by inactive slots.

### Patroni

* Current leader.
* Replica state.
* Failover events.
* DCS connectivity.
* Cluster membership.

Monitoring only whether PostgreSQL is responding is not sufficient. A primary can be completely healthy from the application's perspective while replication is broken.

The replication failure test demonstrated this behavior in the lab.

---

## 6.14 Backup and Recovery

PostgreSQL HA does not replace backup.

The replica is not considered an independent backup because changes, including accidental or corrupted changes, can be replicated to it.

A production implementation should therefore have:

* Regular base backups.
* WAL archiving.
* Retention policies.
* Backup integrity verification.
* Periodic restore tests.
* Defined RPO/RTO for backup recovery.

Point-in-Time Recovery should be tested using an actual restore rather than being considered complete simply because WAL archiving is configured.

---

## 6.15 Production Validation and Refinement

Before using this configuration for production traffic, the following validation should be performed.

### Workload Testing

Use representative application traffic to measure:

* CPU utilization.
* Memory usage.
* Disk latency.
* IOPS.
* WAL generation.
* Query latency.
* Connection usage.

### Failure Testing

Repeat the failure scenarios under realistic load:

* Primary failure.
* Replica failure.
* Replication interruption.
* Network partition.
* DCS member failure.
* Storage failure where possible.

Measure:

* Detection time.
* Promotion time.
* Application recovery time.
* Data consistency.
* Replication recovery time.

### Capacity Testing

Determine:

* Maximum sustainable connections.
* Maximum transaction rate.
* WAL generation rate.
* Storage growth.
* Required replica capacity.

### Configuration Refinement

Configuration changes should follow an iterative process:

```text
Measure
  ↓
Identify bottleneck or risk
  ↓
Change one relevant parameter
  ↓
Benchmark
  ↓
Failure test
  ↓
Document result
  ↓
Deploy
```

This avoids applying generic PostgreSQL tuning recommendations without evidence that they are appropriate for the actual workload.

---

## 6.16 Configuration Summary

The current configuration prioritizes predictable HA behavior and safe recovery over speculative performance tuning.

The main decisions are:

| Area                | Current Decision                | Reason                                               |
| ------------------- | ------------------------------- | ---------------------------------------------------- |
| PostgreSQL version  | 16                              | Consistent supported major version across nodes      |
| Replication         | Physical asynchronous streaming | Good balance of availability and write latency       |
| WAL level           | `replica`                       | Sufficient for physical HA replication               |
| Hot standby         | Enabled                         | Allows read-only access on replica                   |
| WAL senders         | `10`                            | Headroom beyond the current two-node topology        |
| Replication slots   | Enabled                         | Helps replicas recover after temporary disconnection |
| Authentication      | SCRAM for network access        | Stronger password authentication                     |
| Secrets             | Ansible Vault                   | Avoid plaintext credentials in repository            |
| Durability defaults | Preserved                       | Avoid unsupported performance assumptions            |
| Memory tuning       | Not aggressively tuned          | Requires workload measurements                       |
| Connection tuning   | Not aggressively tuned          | Depends on application behavior                      |
| Failover            | Patroni + etcd                  | Automatic leader management                          |
| Backup              | Separate mechanism required     | HA does not protect against logical data loss        |
| PITR                | Required for production         | Recovery from accidental or logical changes          |

The configuration should therefore be treated as a **baseline for the submitted environment**, not as a universal PostgreSQL production configuration. Final production values should be established after workload, capacity, failure, and recovery testing.
