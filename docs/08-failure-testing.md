# Failure Testing

This document describes the failure scenarios tested against the PostgreSQL HA cluster and the observed behavior during failure and recovery.

The tests were performed on the following cluster:

* `postgres-1` — `192.168.64.5`
* `postgres-2` — `192.168.64.6`
* 3-node etcd cluster
* Patroni 3.2.2
* PostgreSQL 16

The tests were performed in a lab environment and the observed timings and behavior are specific to this environment.

---

## Primary Failure

### Scenario

The current PostgreSQL primary was made unavailable by stopping the Patroni service on `postgres-1`.

Before the failure:

```text
postgres-1  192.168.64.5  Leader   running  TL 3
postgres-2  192.168.64.6  Replica  streaming TL 3
```

Patroni was stopped on `postgres-1`:

```bash
systemctl stop patroni
```

### Failure Detection and Failover

The failure was detected by Patroni and the remaining node was promoted automatically.

The observed cluster state after the failure was:

```text
postgres-1  192.168.64.5  Replica  stopped   unknown
postgres-2  192.168.64.6  Leader   running   TL 4
```

The observed time between stopping Patroni and observing the new leader was approximately **6 seconds** in this test.

The timeline changed from `3` to `4`, confirming that a new primary was promoted.

### Write Availability

After promotion, a write was performed on `postgres-2`:

```sql
INSERT INTO ha_test (message)
VALUES ('primary-failure-test');
```

The write succeeded.

After `postgres-1` was started again:

```bash
systemctl start patroni
```

the cluster returned to:

```text
postgres-1  192.168.64.5  Replica  running  TL 4  Lag 0
postgres-2  192.168.64.6  Leader   running  TL 4
```

The test record was also present on `postgres-1` after it rejoined the cluster.

### Result

**PASS**

* Automatic failover occurred.
* A new primary was promoted.
* Observed failover time was approximately 6 seconds.
* The new primary accepted writes.
* The former primary safely rejoined as a replica.
* No data loss was observed under the tested conditions.

Client reconnection through HAProxy was not part of this test. The test verified direct database connectivity to the newly promoted primary.

---

## Replica Failure

### Scenario

The replica node `postgres-1` was made unavailable by stopping Patroni.

Before the failure:

```text
postgres-1  192.168.64.5  Replica  streaming  TL 4  Lag 0
postgres-2  192.168.64.6  Leader   running    TL 4
```

Patroni was stopped on `postgres-1`:

```bash
systemctl stop patroni
```

### Cluster Behavior

After stopping the replica, the remaining cluster contained only the leader:

```text
postgres-2  192.168.64.6  Leader  running  TL 4
```

The leader continued operating normally.

A write was performed on the primary:

```sql
INSERT INTO ha_test (message)
VALUES ('replica-failure-test');
```

The write succeeded.

### Replica Recovery

The replica was started again:

```bash
systemctl start patroni
```

The cluster returned to:

```text
postgres-1  192.168.64.5  Replica  running  TL 4  Lag 0
postgres-2  192.168.64.6  Leader   running  TL 4
```

The replica received the data generated while it was unavailable, and the test records were present after recovery.

### Result

**PASS**

* The cluster continued operating with the replica unavailable.
* The primary continued accepting writes.
* The replica automatically rejoined after recovery.
* Replication returned to `streaming`.
* Replication lag returned to `0 MB`.
* No manual rebuild or reinitialization was required.

---

## Network Partition

### Scenario

A network partition was introduced on `postgres-1`, isolating it from the primary and the etcd cluster.

The following traffic was blocked on `postgres-1`:

```bash
iptables -A OUTPUT -d 192.168.64.6 -j DROP
iptables -A OUTPUT -d 192.168.64.2 -j DROP
iptables -A OUTPUT -d 192.168.64.3 -j DROP
iptables -A OUTPUT -d 192.168.64.4 -j DROP
```

The affected node was the replica:

```text
postgres-1  192.168.64.5  Replica
postgres-2  192.168.64.6  Leader
```

### Isolated Node Behavior

After the partition, `postgres-1` could no longer communicate with the etcd cluster.

The Patroni status commands showed timeouts when attempting to reach the DCS.

The isolated node was still a PostgreSQL replica and did not become a writable primary.

An attempted write on the isolated node returned:

```text
ERROR: cannot execute INSERT in a read-only transaction
```

### Split Brain Prevention

The tested scenario demonstrated that the isolated replica did not start accepting writes while disconnected from the cluster.

The primary on `postgres-2` continued operating as the leader.

The test therefore did not produce two writable PostgreSQL nodes.

### Recovery

The network rules were removed:

```bash
iptables -D OUTPUT -d 192.168.64.6 -j DROP
iptables -D OUTPUT -d 192.168.64.2 -j DROP
iptables -D OUTPUT -d 192.168.64.3 -j DROP
iptables -D OUTPUT -d 192.168.64.4 -j DROP
```

The cluster returned to:

```text
postgres-1  192.168.64.5  Replica  running  TL 4  Lag 0
postgres-2  192.168.64.6  Leader   running  TL 4
```

### Result

**PASS for the tested scenario**

* The isolated replica did not accept writes.
* The existing primary continued operating.
* No split brain was observed.
* After network connectivity was restored, the cluster returned to a healthy state.

This test isolated the **replica** from the rest of the cluster. A separate test of isolating the current **primary** was not performed.

---

## Replication Failure

### Scenario

A replication-specific failure was introduced without shutting down PostgreSQL or Patroni.

The replication connection between:

```text
postgres-1 (Replica)
        |
        | PostgreSQL replication
        v
postgres-2 (Leader)
```

was interrupted using firewall rules.

The replication connection was first terminated from the primary. The firewall rules then prevented the replica from establishing a new replication connection.

The resulting state on the primary was:

```sql
SELECT pid, client_addr, state
FROM pg_stat_replication;
```

```text
 pid | client_addr | state
-----+-------------+------
(0 rows)
```

Patroni reported:

```text
postgres-1  192.168.64.5  Replica  running
postgres-2  192.168.64.6  Leader   running
```

The important point is that PostgreSQL and Patroni were still running; only the replication connection was unavailable.

### Impact on Writes

The primary continued accepting writes while replication was unavailable.

Three records were inserted on `postgres-2`:

```text
24 | replication-broken-test-1
25 | replication-broken-test-2
26 | replication-broken-test-3
```

The same records were not present on `postgres-1` while replication was broken.

This demonstrated that asynchronous replication failure does not stop the primary from accepting writes.

### Recovery

The firewall rules were removed and connectivity between the nodes was restored.

The replication connection was automatically re-established.

The final Patroni state was:

```text
postgres-1  192.168.64.5  Replica  streaming  TL 4  Lag 0
postgres-2  192.168.64.6  Leader   running    TL 4
```

The previously missing records were then present on `postgres-1`:

```text
24 | replication-broken-test-1
25 | replication-broken-test-2
26 | replication-broken-test-3
```

### Result

**PASS**

* Replication failure was successfully introduced.
* The primary remained available for writes.
* The replica stopped receiving new WAL while the replication connection was unavailable.
* Replication automatically recovered after connectivity was restored.
* The replica caught up using the available WAL.
* Final replication state was `streaming` with `0 MB` lag.
* No replica rebuild or manual reinitialization was required.

### Operational Implication

A replication failure does not necessarily make the primary unavailable. The primary can continue accepting writes while the replica is behind.

Therefore, replication health must be monitored separately from PostgreSQL availability. A healthy primary does not by itself mean that the HA cluster has a fully synchronized replica.

---

## Failure Modes and Limitations

The following limitations were identified during testing:

1. **Client reconnection through HAProxy was not tested.**
   The primary failure test verified Patroni failover and direct database writes, but application-level reconnection through HAProxy was outside the scope of this test.

2. **Primary-side network partition was not tested.**
   The network partition test isolated the replica. A separate test is required to observe the behavior when the current primary loses connectivity to the other PostgreSQL node and the DCS.

3. **Asynchronous replication can temporarily leave the replica behind.**
   During the replication failure test, the primary accepted new writes while the replica was disconnected. The missing WAL was later replayed after connectivity was restored.

4. **Failover timing is environment-dependent.**
   The approximately 6-second failover observed in this lab should not be treated as a guaranteed production failover time. Actual behavior depends on Patroni configuration, DCS availability, network conditions, PostgreSQL state, and workload.

5. **Data-loss testing was limited to the conditions of this lab.**
   No data loss was observed during the tested primary failure. This does not establish a zero-data-loss guarantee for all production failure scenarios.

6. **The tests were performed manually.**
   The failure scenarios were executed using systemd and firewall commands. A production implementation should additionally provide monitoring, alerting, operational runbooks, and controlled recovery procedures.
