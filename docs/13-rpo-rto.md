# RPO and RTO

## 5.1 Recovery Point Objective (RPO)

**RPO (Recovery Point Objective)** defines the maximum amount of data that may be lost after a failure.

In this architecture, PostgreSQL replication between the primary and replica is asynchronous. Therefore, the architecture does not provide a strict zero-data-loss guarantee.

Under normal conditions, the replica is continuously receiving and replaying WAL from the primary. However, there can be a small amount of WAL that has been generated on the primary but has not yet reached or been replayed by the replica.

During a primary failure, any transactions that existed only on the failed primary and had not been replicated to the surviving node could potentially be lost.

Therefore:

```text
RPO target: Near-zero under normal conditions
Guarantee: Not zero
```

The exact amount of potential data loss depends on the replication lag at the time of failure.

During the failure tests performed in this lab, no data loss was observed. However, this should not be interpreted as a zero-RPO guarantee because the replication mode is asynchronous.

### Factors affecting RPO

The effective RPO depends on:

* PostgreSQL replication mode.
* Replication lag.
* Network latency and connectivity.
* WAL generation rate.
* Replica performance.
* Primary failure timing.
* Availability of the DCS and Patroni during failover.

The replication failure test demonstrated that the primary can continue accepting writes while the replica is temporarily disconnected. New WAL generated during this period is not immediately available on the replica until replication is restored.

---

## 5.2 Recovery Time Objective (RTO)

**RTO (Recovery Time Objective)** defines the maximum acceptable time required to restore service after a failure.

In the primary failure test, Patroni automatically detected the failed primary and promoted the replica.

The observed failover time in the lab was approximately:

```text
~6 seconds
```

This is an observed lab result, not a guaranteed production RTO.

For this implementation, a reasonable initial RTO target is:

```text
RTO target: < 30 seconds
```

The target includes:

1. Failure detection.
2. Leader election through the DCS.
3. Promotion of the surviving PostgreSQL node.
4. PostgreSQL becoming available for writes.
5. Application/client reconnection.

The approximately 6-second value observed during testing covers the database failover portion. Client reconnection through HAProxy was not included in that measurement.

### Factors affecting RTO

Actual recovery time depends on:

* Patroni `ttl`, `loop_wait`, and `retry_timeout` settings.
* etcd availability.
* Network conditions.
* PostgreSQL startup and promotion time.
* HAProxy health-check interval and configuration.
* Application connection pooling and retry behavior.
* Current system load.
* Failure type and failure detection mechanism.

---

## 5.3 RPO and RTO Assumptions

The stated targets assume:

* At least one healthy PostgreSQL replica is available.
* The etcd cluster maintains quorum.
* Patroni is running on the PostgreSQL nodes.
* PostgreSQL WAL is available for replica catch-up.
* Network connectivity between the surviving nodes and DCS is available.
* HAProxy and its health checks are operational.
* The failure does not affect all PostgreSQL nodes simultaneously.
* The failure is recoverable without restoring the database from backup.

These assumptions are important because HA failover is designed primarily for node-level failures, not every possible disaster scenario.

---

## 5.4 How Stricter RPO or RTO Requirements Affect the Architecture

### Stricter RPO

If the requirement changes from near-zero RPO to **strict zero data loss**, asynchronous replication is not sufficient by itself.

Possible architectural changes include:

* Synchronous PostgreSQL replication.
* `synchronous_commit` configuration appropriate to the required durability guarantees.
* Dedicated synchronous standby capacity.
* Additional network and latency considerations.
* Monitoring and operational controls around synchronous replication.

Synchronous replication reduces the possibility of losing committed transactions during a primary failure, but it can increase write latency and may reduce availability if the synchronous standby becomes unavailable, depending on the chosen configuration.

### Stricter RTO

If the required RTO becomes significantly lower, for example a few seconds, the architecture would need tighter control over the complete failover path, not only PostgreSQL promotion.

Potential changes include:

* Tuning Patroni failure-detection parameters.
* Highly available etcd with predictable latency.
* Faster HAProxy health checks.
* Application-level connection retry and pooling configuration.
* Faster service discovery and connection switching.
* Capacity planning so the surviving PostgreSQL node can immediately handle the workload.

Reducing detection intervals too aggressively can also increase the risk of unnecessary failovers caused by temporary network or system conditions. Therefore, RTO tuning must be balanced against cluster stability.

---

## 5.5 HA vs Backup vs Disaster Recovery vs Point-in-Time Recovery

These mechanisms solve different problems.

| Mechanism              | Main Purpose                                              | Protects Against                                     |
| ---------------------- | --------------------------------------------------------- | ---------------------------------------------------- |
| High Availability      | Keep the service available during node failure            | PostgreSQL node failure, service failure             |
| Backup                 | Preserve recoverable copies of data                       | Data corruption, accidental deletion, major failures |
| Disaster Recovery      | Restore service after a major site/infrastructure failure | Datacenter or infrastructure loss                    |
| Point-in-Time Recovery | Restore the database to a specific point in time          | Logical errors, accidental changes, data corruption  |

### High Availability

Patroni, PostgreSQL replication, etcd, and HAProxy provide high availability.

The primary failure test demonstrated that the surviving PostgreSQL node can be promoted automatically.

HA is primarily concerned with **service continuity**, not long-term data protection.

### Backup

Backups provide an independent copy of the database.

For example, if an incorrect SQL statement deletes or corrupts data and the change is successfully replicated to the standby, HA replication does not protect against that event. The replica may contain the same incorrect data.

Backups are therefore required in addition to HA.

### Disaster Recovery

Disaster recovery addresses larger failures such as:

* Loss of the entire PostgreSQL environment.
* Datacenter failure.
* Major infrastructure failure.
* Loss of the primary HA environment.

A separate environment, storage location, or site would normally be required for meaningful disaster recovery.

The current two-node PostgreSQL lab does not by itself provide protection against total environment loss.

### Point-in-Time Recovery

Point-in-Time Recovery (PITR) uses a base backup together with archived WAL to restore PostgreSQL to a selected point in time.

PITR is particularly useful when the database itself is healthy from an infrastructure perspective but the data has been logically damaged.

For example:

```text
10:00  Normal operation
10:15  Accidental DELETE
10:20  Problem detected
```

HA replication would normally replicate the DELETE to the standby.

PITR can instead be used to restore the database to a point before the accidental DELETE.

---

## 5.6 Summary

The current architecture provides automatic PostgreSQL failover through Patroni and etcd, with HAProxy providing a stable client entry point.

The observed lab results were:

```text
Observed failover time: ~6 seconds
Observed data loss during primary failure test: 0
Final replica lag after recovery: 0 MB
```

The target values should be interpreted as:

```text
RPO: Near-zero, but not guaranteed zero
RTO: < 30 seconds target
```

The architecture should not be considered a replacement for backup, disaster recovery, or PITR. High availability addresses service continuity, while backup and recovery mechanisms address data protection and restoration.
