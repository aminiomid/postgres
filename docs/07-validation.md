# 13. Validation

The purpose of this section is to verify that the PostgreSQL HA cluster is functioning correctly and that its behavior under failure conditions matches the expected HA design.

Validation was performed at two levels:

* **Automated validation** of the current cluster state
* **Failure testing** to verify HA and recovery behavior

---

## 13.1 Automated Cluster Validation

An automated validation script is provided under:

```text
tests/validate-cluster.sh
```

The script checks:

1. Patroni cluster availability
2. Existence of exactly one leader
3. PostgreSQL connectivity
4. Current PostgreSQL role
5. Replica streaming state
6. Replication details and lag
7. Overall validation result

The script can be executed with:

```bash
chmod +x tests/validate-cluster.sh
sudo ./tests/validate-cluster.sh
```

The validation is intended to be executed on the current PostgreSQL primary.

---

## 13.2 Automated Validation Result

The validation was executed on the current PostgreSQL primary, `postgres-2` (`192.168.64.6`).

The actual result was:

```text
========================================
 PostgreSQL HA Cluster Validation
========================================

== 1. Patroni Cluster ==
+ Cluster: postgres-ha (7689930288296719218) -----+----+-----------+
| Member     | Host         | Role    | State     | TL | Lag in MB |
+------------+--------------+---------+-----------+----+-----------+
| postgres-1 | 192.168.64.5 | Replica | streaming |  4 |         0 |
| postgres-2 | 192.168.64.6 | Leader  | running   |  4 |           |
+------------+--------------+---------+-----------+----+-----------+
PASS: Patroni cluster is reachable

== 2. Leader Check ==
PASS: Exactly one leader exists

== 3. PostgreSQL Connectivity ==
PASS: PostgreSQL is accepting local connections

== 4. PostgreSQL Role ==
PASS: This node is writable primary

== 5. Replication ==
PASS: All replicas are streaming

== 6. Replication Details ==
 application_name | client_addr  |   state   | sync_state | replay_lag_bytes
------------------+--------------+-----------+------------+------------------
 postgres-1       | 192.168.64.5 | streaming | async      |                0
(1 row)

== 7. Final Result ==
PASS: 5
FAIL: 0

RESULT: VALIDATION PASSED
```

The validation confirms that, at the time of testing:

* Patroni was able to communicate with the cluster.
* Exactly one leader was present.
* PostgreSQL was accepting local connections.
* `postgres-2` was the writable primary.
* `postgres-1` was streaming as a replica.
* Replication lag was `0 bytes`.
* All automated validation checks passed.

---

## 13.3 Failure Testing

In addition to the automated health checks, several failure scenarios were tested to verify the HA behavior.

### 13.3.1 Primary Failure

The Patroni service was stopped on the current primary.

Expected behavior:

1. Patroni detects the primary failure.
2. The remaining healthy PostgreSQL node becomes the new leader.
3. The failed node is removed from the active primary role.
4. After recovery, the failed node rejoins as a replica.

Observed result:

* Failover completed in approximately **6 seconds** under the lab conditions.
* `postgres-2` became the new leader.
* A test row written after failover was replicated back to `postgres-1` after recovery.
* No data loss was observed during this test.

**Result: PASS**

---

### 13.3.2 Replica Failure

The Patroni service was stopped on the replica while the primary remained available.

A test row was inserted on the primary during the replica outage.

After restarting Patroni on the replica:

* The replica rejoined the cluster.
* Replication returned to `streaming`.
* The replica automatically caught up with the primary.
* The test data was present on the replica.

**Result: PASS**

---

### 13.3.3 Network Partition

Network access from the replica to the primary and DCS nodes was blocked using firewall rules.

During the partition:

* The isolated node remained a replica.
* It could not become a writable primary.
* Write attempts on the isolated node failed with:

```text
ERROR: cannot execute INSERT in a read-only transaction
```

The network rules were then removed and the node recovered normally.

Final state:

* `postgres-2`: Leader
* `postgres-1`: Replica
* Replication lag: `0`

**Result: PASS**

> This test covered a replica-side network partition. A leader-side network partition was not tested.

---

### 13.3.4 Replication Failure

Replication traffic between the primary and replica was blocked.

During the test:

* The replication connection was terminated.
* `pg_stat_replication` showed no active replication connection.
* New data was written to the primary while replication was unavailable.
* After removing the firewall rules, replication automatically reconnected.
* The replica caught up without requiring reinitialization.

The final replication state was:

```text
state: streaming
lag:   0
```

**Result: PASS**

---

## 13.4 Validation Summary

| Test                    | Expected Result                    | Observed Result            | Status |
| ----------------------- | ---------------------------------- | -------------------------- | ------ |
| Patroni cluster health  | Cluster reachable                  | Cluster reachable          | PASS   |
| Leader detection        | Exactly one leader                 | One leader                 | PASS   |
| PostgreSQL connectivity | Connection succeeds                | Connection succeeds        | PASS   |
| Replica streaming       | Replica remains streaming          | Streaming                  | PASS   |
| Replication lag         | No significant lag                 | 0 bytes                    | PASS   |
| Primary failure         | Automatic failover                 | ~6 seconds                 | PASS   |
| Replica failure         | Service remains available          | Primary remained available | PASS   |
| Network partition       | Isolated replica remains read-only | Confirmed                  | PASS   |
| Replication failure     | Replication recovers               | Automatic recovery         | PASS   |

---

## 13.5 Additional Production Validation

The current tests validate the core PostgreSQL, Patroni, and replication behavior. Before considering the platform production-ready, the following should also be tested:

* HAProxy connectivity to the active primary
* Application connection recovery after failover
* Existing connection behavior during failover
* Connection pool recovery
* HAProxy health-check behavior
* etcd member failure and quorum behavior
* Backup and restore
* Point-in-Time Recovery (PITR)
* Storage failure
* Disk-full conditions
* Long replication lag
* WAL and replication slot retention
* Monitoring and alert delivery
* TLS and certificate rotation
* Planned switchover
* PostgreSQL minor-version upgrade
* PostgreSQL major-version upgrade/migration
* Disaster recovery from a separate failure domain

These tests are outside the scope of the current lab validation but should be included in a production readiness test plan.
