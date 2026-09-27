# 8. Observability

The observability design focuses on detecting failures and degradation at both the component level and the platform level.

The goal is not only to know that a service is down, but also to understand whether the PostgreSQL HA platform is still able to serve traffic, whether replication is healthy, and which component is responsible for a degraded state.

## 8.1 What Should Be Monitored

The following components and signals should be monitored.

| Component   | Signals                                                                                                           |
| ----------- | ----------------------------------------------------------------------------------------------------------------- |
| PostgreSQL  | process availability, connection availability, active connections, errors, transaction rate, locks, database size |
| Replication | replication state, replication lag, WAL sender/receiver status, replication slots, WAL retention                  |
| Patroni     | cluster member state, leader/replica role, REST API health, failover events, DCS connectivity                     |
| etcd        | member health, quorum, leader status, request latency, disk usage, database size                                  |
| HAProxy     | frontend availability, active sessions, backend health, connection errors, HTTP 5xx, response time                |
| Host        | CPU, memory, disk usage, disk I/O, network errors and system load                                                 |
| Backup      | last successful backup, backup duration, WAL archive status and repository capacity                               |

The most important signals are the ones that indicate loss of availability, loss of redundancy, or increasing risk of data loss.

## 8.2 Alert Conditions

Alerts should be based on operational impact rather than simply monitoring whether a process is running.

Examples of important alerts include:

### PostgreSQL

* PostgreSQL is unavailable.
* No writable primary is available.
* Connection failures increase significantly.
* Active connections approach configured limits.
* Critical database errors are detected.

### Replication

* A replica is not streaming.
* Replication lag exceeds the expected threshold.
* A replication slot is inactive or causing excessive WAL retention.
* WAL generation continues while a replica remains disconnected.

Replication alerts are particularly important because the database can remain available while the HA protection is degraded.

For example, if the primary is healthy but the only replica is unavailable, the application may continue working normally while the platform has lost its failover capacity.

### Patroni

* No leader is reported.
* A member unexpectedly changes role.
* A replica enters an unhealthy or stopped state.
* Patroni loses connectivity to the DCS.
* Unexpected failover or leader changes occur.

### etcd

* An etcd member becomes unhealthy.
* Quorum is lost.
* Leader election occurs unexpectedly or repeatedly.
* etcd request latency increases significantly.
* Disk usage or database size approaches operational limits.

A single etcd member failure should normally be treated as a degraded condition rather than a complete platform outage, because the cluster still has quorum with the remaining two members.

### HAProxy

* No healthy PostgreSQL backend is available.
* Backend health checks fail.
* Connection errors increase.
* Client connection queues increase.
* Response latency increases.
* HTTP 5xx responses increase.

### Host

* Disk usage reaches warning/critical thresholds.
* Memory pressure or OOM events occur.
* CPU saturation persists.
* Network errors or packet loss are detected.

### Backup

* No recent successful backup exists.
* WAL archiving is failing or falling behind.
* Backup repository capacity is approaching its limit.
* Scheduled backup jobs fail.

## 8.3 Detecting Failures and Degradation

Different failure types require different signals.

A component-level health check answers:

> Is this component running?

A platform-level health check answers:

> Can the HA platform currently provide a writable PostgreSQL service with the expected redundancy?

For example, PostgreSQL may be running on both nodes while the platform is still unhealthy if:

* no node is the leader,
* replication is broken,
* Patroni cannot communicate with etcd,
* or HAProxy has no healthy backend.

Therefore, monitoring should correlate multiple signals instead of relying on a single process check.

### Example: Replica Failure

If `postgres-1` stops, PostgreSQL on `postgres-2` can continue serving traffic.

The platform should therefore report:

* PostgreSQL primary: healthy
* Application write availability: healthy
* Replica: unavailable
* Replication redundancy: degraded
* HA platform: degraded, but operational

This distinction is important because the immediate service is available, but another failure could cause an outage.

### Example: Primary Failure

A primary failure should produce a sequence similar to:

1. PostgreSQL primary becomes unavailable.
2. Patroni detects the failure.
3. A new leader is elected.
4. The new primary becomes writable.
5. HAProxy health checks detect the new backend state.
6. Client connections are re-established.
7. The former primary returns as a replica.

The monitoring system should capture these state changes and their timestamps so that the actual failover duration can be measured.

### Example: Replication Failure

Replication can fail while both PostgreSQL instances remain available.

In this situation:

* Primary availability may remain healthy.
* Replica availability may remain healthy.
* Replication health becomes degraded.
* RPO risk increases because new WAL is not being applied to the replica.

This should therefore generate an alert even though the application may not yet be affected.

## 8.4 Operator Information During an Incident

During an incident, operators should be able to determine the following without logging into every server manually:

1. Which node is currently the PostgreSQL leader?
2. Which nodes are replicas?
3. Are replicas streaming?
4. What is the current replication lag?
5. Is Patroni healthy?
6. Is etcd healthy and does it have quorum?
7. Does HAProxy have a healthy PostgreSQL backend?
8. Are clients able to connect?
9. Are there recent failover or leader-change events?
10. Is there evidence of WAL or replication problems?
11. Is the problem isolated to one component or affecting the whole platform?

A useful operational dashboard should therefore show both component health and an overall HA status.

## 8.5 Platform Health vs Component Health

The monitoring design distinguishes between component health and platform health.

For example:

| Situation                                   | Component Status          | Platform Status                    |
| ------------------------------------------- | ------------------------- | ---------------------------------- |
| Both PostgreSQL nodes healthy and streaming | Healthy                   | Healthy                            |
| One replica down, primary healthy           | Degraded                  | Degraded but serving               |
| Primary failed, Patroni promoted replica    | Transitional → Healthy    | Temporarily degraded, then healthy |
| Replication stopped                         | PostgreSQL available      | Degraded                           |
| One etcd member down                        | etcd degraded             | Operational                        |
| etcd quorum lost                            | etcd unavailable          | HA control plane unavailable       |
| No healthy PostgreSQL backend in HAProxy    | PostgreSQL may be running | Unavailable                        |

This distinction prevents false confidence from a simple "process is running" check.

## 8.6 Monitoring Validation

Monitoring itself should be tested as part of the failure-testing process.

The failure scenarios from the previous section can be reused to validate the monitoring system:

* Stop the PostgreSQL primary and verify that a primary failure alert is generated.
* Stop the replica and verify that the loss of redundancy is detected.
* Break replication and verify that replication degradation is reported.
* Isolate a node from the DCS and verify that Patroni/DCS problems are visible.
* Remove all healthy PostgreSQL backends from HAProxy and verify that service unavailability is detected.
* Restore each component and verify that alerts resolve correctly.

Alert timestamps should be compared with the actual failure time to determine detection latency.

Monitoring should also be tested for recovery events, not only failures. An alert that remains active after a recovered condition is equally problematic because it does not represent the current platform state.

## 8.7 Recommended Observability Stack

For a production implementation, the platform can be monitored using:

* Prometheus for metrics collection.
* Grafana for dashboards and visualization.
* Alertmanager for alert routing.
* PostgreSQL Exporter for PostgreSQL metrics.
* Node Exporter for host metrics.
* Patroni REST API and cluster status for HA state.
* etcd metrics endpoint for DCS health.
* HAProxy statistics/Prometheus metrics for load-balancer health.
* Centralized logs for PostgreSQL, Patroni, etcd and HAProxy.

The exact tooling is less important than having the required signals available and actionable.

## 8.8 Observability Scope of This Lab

The current lab validates the HA behavior directly using PostgreSQL, Patroni, etcd and system-level checks.

The following operational signals have been identified as required for a production deployment:

* PostgreSQL availability
* Primary/replica role
* Replication state and lag
* Patroni cluster state
* etcd quorum and health
* HAProxy backend availability
* host resource utilization
* backup and WAL archival status
* failover and recovery events

A full Prometheus/Grafana/Alertmanager deployment is not required to demonstrate the HA mechanism itself and is outside the current lab implementation scope. The monitoring design above defines the signals and alert conditions that should be implemented for production operation.

The key principle is that observability must answer two separate questions:

1. **Is each component healthy?**
2. **Is the PostgreSQL HA platform currently capable of providing the expected service and redundancy?**

Both views are required for reliable incident detection, diagnosis and recovery.
