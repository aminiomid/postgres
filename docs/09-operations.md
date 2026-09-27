# Operations

This document describes the operational procedures for the PostgreSQL HA cluster, including cluster health checks, primary identification, replication checks, controlled switchover, failover validation, and node recovery.

The procedures are based on the lab topology:

* 3 etcd nodes
* 2 PostgreSQL nodes
* 2 Patroni instances
* 1 HAProxy instance running in Docker

---

## 1. Cluster Health Overview

The cluster health is checked at three levels:

1. etcd quorum and availability
2. Patroni cluster state
3. PostgreSQL replication and database health

HAProxy is checked separately because it provides the application-facing endpoint.

A healthy cluster has:

* A valid etcd quorum
* One PostgreSQL primary
* One PostgreSQL replica
* Healthy Patroni members
* Active streaming replication
* HAProxy routing traffic to the current primary

---

## 2. Check etcd Cluster

The etcd cluster consists of three members.

The member list can be checked with:

```bash
etcdctl member list
```

Cluster endpoint health can be checked with:

```bash
etcdctl endpoint health --cluster
```

Endpoint status can be inspected with:

```bash
etcdctl endpoint status --cluster -w table
```

The expected state is that the etcd members are reachable and the cluster maintains quorum.

A loss of one etcd member does not immediately remove quorum from a three-member cluster.

If quorum is lost, Patroni cannot safely perform normal leader coordination and automatic failover cannot be relied upon.

---

## 3. Check Patroni Cluster

Patroni provides the main view of the PostgreSQL HA state.

The cluster can be inspected with:

```bash
patronictl -c /etc/patroni/config.yml list
```

A healthy cluster contains one member with the `Leader` role and another member with the `Replica` role.

The output is used to verify:

* Current leader
* Replica state
* Replication lag
* Patroni member state
* Timeline
* Cluster health

The exact Patroni configuration path is environment-specific and is defined by the Ansible configuration.

---

## 4. Identify the Current Primary

The current PostgreSQL primary is determined by Patroni rather than by the VM hostname.

The primary can be identified using:

```bash
patronictl -c /etc/patroni/config.yml list
```

The node marked as `Leader` is the current primary.

This is important during failover because the primary hostname can change while the application endpoint remains unchanged.

The application connects to HAProxy and does not need to track the current primary directly.

---

## 5. Check PostgreSQL Service

PostgreSQL service status can be checked with:

```bash
systemctl status postgresql
```

However, service status alone does not indicate whether the node is the current primary.

The PostgreSQL role is determined through Patroni and PostgreSQL state.

A PostgreSQL process can be running while the node is a replica or while Patroni has placed it into an unhealthy state.

---

## 6. Check PostgreSQL Replication

Replication status is checked on the primary with:

```sql
SELECT
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication;
```

On the replica, recovery state can be checked with:

```sql
SELECT
    pg_is_in_recovery();
```

The expected result is:

```text
true
```

for the replica.

The primary should report an active replication connection to the replica.

Replication lag can also be inspected using PostgreSQL statistics and Patroni's cluster view.

---

## 7. Check PostgreSQL Readiness

PostgreSQL availability can be checked using:

```bash
pg_isready -h <host> -p 5432
```

This verifies that PostgreSQL is accepting connections, but it does not determine whether the node is the current primary.

Role-aware health checks are handled through Patroni.

This distinction is important for HAProxy: a running PostgreSQL replica must not receive application traffic intended for the primary.

---

## 8. HAProxy Health

HAProxy provides the stable endpoint for applications.

The HAProxy container can be checked with:

```bash
docker ps
```

Container logs can be inspected with:

```bash
docker logs <haproxy-container>
```

The HAProxy configuration can be validated with:

```bash
haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
```

The exact container name and configuration path are defined by the Docker Compose configuration.

HAProxy health checks distinguish the active PostgreSQL primary from replicas.

---

## 9. Application Connectivity

The application-facing connection uses the HAProxy endpoint instead of a PostgreSQL VM address.

A basic connectivity test can be performed with:

```bash
psql -h <haproxy-host> -p <haproxy-port> -U <user> -d <database>
```

After connecting, the current database role can be checked with:

```sql
SELECT pg_is_in_recovery();
```

For a connection routed to the primary, the expected result is:

```text
false
```

This verifies both network connectivity and correct HAProxy routing.

---

## 10. Controlled Switchover

A planned role change is performed as a switchover rather than a failure test.

Before starting the operation:

1. Verify etcd quorum.
2. Verify both Patroni members are healthy.
3. Verify replication is active.
4. Check replication lag.
5. Confirm that the intended target is eligible for promotion.

The switchover can be initiated through Patroni:

```bash
patronictl -c /etc/patroni/config.yml switchover
```

Patroni coordinates the role transition.

After the switchover, verify:

```bash
patronictl -c /etc/patroni/config.yml list
```

and confirm that:

* The previous replica is now the leader.
* The previous primary is running as a replica.
* Replication is established again.
* HAProxy routes new connections to the new primary.

---

## 11. Failover

Failover is different from a planned switchover.

During failover, the current primary becomes unavailable and Patroni determines whether another member can safely become the leader.

The failure scenarios are tested separately and include:

* PostgreSQL primary failure
* PostgreSQL replica failure
* Network partition
* Replication failure

The exact detection and failover timing is recorded during these tests and documented in `failure-testing.md`.

The operational verification after a failover is:

```bash
patronictl -c /etc/patroni/config.yml list
```

followed by a database connectivity test through HAProxy.

The application endpoint remains unchanged while the backend PostgreSQL primary changes.

---

## 12. Primary Node Recovery

When the failed primary becomes available again, it is not automatically treated as the active primary.

Patroni determines the appropriate role based on the current cluster state.

The recovered node must be verified before it is considered healthy:

```bash
patronictl -c /etc/patroni/config.yml list
```

The node must rejoin the cluster as a valid replica and establish replication from the current primary.

The recovery procedure verifies:

* Patroni member state
* PostgreSQL process state
* Replication connection
* Replication lag
* Timeline consistency

The recovered node is not promoted manually unless the cluster state and operational procedure explicitly require it.

---

## 13. Replica Failure

A replica failure does not immediately interrupt application traffic because the primary remains active.

The main impact is reduced redundancy.

After the replica becomes available again, its Patroni and PostgreSQL state are checked.

The replica must establish streaming replication from the current primary and reach a healthy replication state.

The cluster is considered fully recovered only after the replica is synchronized again.

---

## 14. Network Failure

Network failures require additional care because PostgreSQL processes may remain running while communication between cluster members is interrupted.

The investigation checks:

* Connectivity between PostgreSQL nodes
* Connectivity from PostgreSQL nodes to etcd
* etcd quorum
* Patroni cluster state
* PostgreSQL role
* Replication state
* HAProxy connectivity

A network partition is not treated as equivalent to a PostgreSQL process failure.

The expected behavior is validated through the dedicated network partition test rather than inferred from a simple service health check.

---

## 15. Replication Failure

Replication failure is investigated from both the Patroni and PostgreSQL layers.

First, inspect the cluster:

```bash
patronictl -c /etc/patroni/config.yml list
```

Then inspect PostgreSQL replication:

```sql
SELECT
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication;
```

Relevant causes include:

* PostgreSQL connectivity problems
* Authentication errors
* WAL availability issues
* PostgreSQL configuration problems
* Resource exhaustion
* Timeline mismatch

The replica is considered recovered only after streaming replication is active again.

---

## 16. Operational Validation

The following checks provide a quick cluster overview:

```bash
# Patroni
patronictl -c /etc/patroni/config.yml list

# etcd
etcdctl endpoint health --cluster

# PostgreSQL
pg_isready -h <host> -p 5432

# HAProxy container
docker ps

# HAProxy logs
docker logs <haproxy-container>
```

A complete validation is provided by:

```bash
./tests/validate-cluster.sh
```

The validation script checks the expected cluster state and provides a repeatable health check after deployment or recovery.

---

## 17. Operational Principles

The operational model follows several principles:

* Patroni is the authority for PostgreSQL HA state.
* etcd provides distributed coordination and leader state.
* PostgreSQL remains responsible for data storage and replication.
* HAProxy provides the stable application endpoint.
* Direct connections to individual PostgreSQL nodes are used for administration and troubleshooting, not as the application endpoint.
* Planned role changes use switchover.
* Unplanned failures are handled through Patroni failover.
* Recovery is considered complete only after the failed component has returned to a healthy cluster state.
* Failure timing and data-loss observations are measured during testing rather than assumed from configuration.
