# 12. Production Architecture

The submitted environment demonstrates the core PostgreSQL HA architecture using PostgreSQL, Patroni, etcd and HAProxy.

It is intentionally a small lab environment and should not be considered a complete production deployment.

A production implementation would keep the same basic architecture but introduce stronger failure isolation, infrastructure redundancy, security controls, observability, backup and disaster-recovery capabilities, and operational procedures.

## 12.1 Production Architecture

A production deployment could follow this general architecture:

```text
                         Application
                              |
                              v
                    Load Balancer / HAProxy
                              |
                 +------------+------------+
                 |                         |
                 v                         v
           PostgreSQL-1              PostgreSQL-2
              + Patroni                + Patroni
                 \                         /
                  \                       /
                   +------ etcd ----------+
                    3 or more members

                         |
                         v
                 Backup Repository
                 + WAL Archive
```

For higher availability, the PostgreSQL nodes and etcd members should be distributed across separate failure domains.

## 12.2 Failure Domains

The current lab runs on a small set of VMs and does not provide meaningful physical failure-domain isolation.

In production, the PostgreSQL nodes should not depend on a single:

* Physical host.
* Hypervisor.
* Availability zone.
* Rack.
* Power domain.
* Network path.

A typical production deployment could place:

```text
Availability Zone A       Availability Zone B       Availability Zone C

 PostgreSQL + Patroni      PostgreSQL + Patroni
        |                         |
      etcd                      etcd
                                   \
                                    etcd
```

The exact placement depends on the infrastructure platform.

The goal is to ensure that losing one failure domain does not automatically remove both PostgreSQL nodes or the etcd quorum.

## 12.3 Infrastructure Reliability

Production infrastructure should provide redundancy for:

* Compute.
* Network connectivity.
* Power.
* Storage.
* Load-balancing.
* DNS where applicable.
* Monitoring.
* Backup storage.

The HA design protects against individual PostgreSQL node failures, but it does not automatically protect against failure of the infrastructure hosting the entire cluster.

For example, if both PostgreSQL nodes run on the same physical host, a host failure can remove both database nodes even though PostgreSQL itself is configured as HA.

Therefore, infrastructure-level redundancy is part of the database HA design.

## 12.4 Storage Design

Production PostgreSQL storage should use reliable persistent storage with appropriate:

* IOPS.
* Latency.
* Throughput.
* Capacity.
* Redundancy.
* Snapshot/backup capabilities.

The PostgreSQL data directory should not depend on temporary or non-persistent storage.

Storage performance should be measured under realistic database workloads rather than selected only by capacity.

WAL generation and retention should also be monitored because high write workloads can consume storage rapidly, especially when a replica or replication slot is unavailable.

## 12.5 Network Design

Production networking should separate database traffic where appropriate.

The following traffic should be explicitly controlled:

* Application → HAProxy.
* HAProxy → PostgreSQL.
* PostgreSQL → PostgreSQL replication.
* Patroni → etcd.
* etcd → etcd.
* Monitoring → exporters/APIs.
* Backup → backup repository.
* Administrative → infrastructure.

Firewall rules should follow least privilege and only allow the required source/destination combinations.

Network latency between PostgreSQL nodes and etcd members should be predictable because replication and distributed coordination are sensitive to latency and network failures.

Network partition scenarios should also be tested before production deployment.

## 12.6 Backup and Disaster Recovery

HA is not a replacement for backup.

A production deployment should use:

* Regular PostgreSQL base backups.
* Continuous WAL archiving.
* An independent backup repository.
* Defined backup retention.
* Encryption for backup data.
* Monitoring of backup and WAL archival jobs.
* Regular restore tests.
* Documented recovery procedures.

A tool such as pgBackRest can provide a practical implementation for PostgreSQL backup and WAL archiving.

The backup repository should be outside the PostgreSQL cluster's primary failure domain.

For stronger disaster recovery, backups should also be replicated to another site or region.

Recovery should be tested using:

* Full database restore.
* Point-in-time recovery.
* Complete cluster recovery.
* Backup repository failure scenarios.

The recovery process should be documented and executable without relying on a single individual.

## 12.7 Monitoring and Incident Response

Production monitoring should cover both component health and overall platform health.

Important signals include:

* PostgreSQL availability.
* Current primary.
* Replica availability.
* Replication state and lag.
* WAL generation.
* Patroni state.
* etcd quorum.
* HAProxy backend health.
* Connection count.
* Query latency.
* Host resource utilization.
* Disk capacity.
* Backup status.
* WAL archive status.

Alerts should distinguish between:

```text
Component Failure
        |
        v
Platform Degraded
        |
        v
Service Unavailable
```

For example, losing one replica is different from losing the only writable primary.

Incident response should include documented procedures for:

* Primary failure.
* Replica failure.
* Replication failure.
* etcd failure.
* Network partition.
* Storage failure.
* Accidental data deletion.
* Corruption.
* Complete cluster loss.

The monitoring system should also be tested so that operators know that alerts are generated and resolved correctly.

## 12.8 Secrets Management

The current lab uses Ansible Vault to protect PostgreSQL and replication credentials.

This is suitable for the lab and small controlled environments.

For production, secrets should preferably be managed through an approved secret-management system such as:

* HashiCorp Vault.
* A cloud secret manager.
* Another enterprise-approved secrets platform.

Secrets should not be stored as plaintext in Git repositories.

Access to secrets should be based on least privilege and should be auditable.

Secret rotation should also be part of the operational process.

## 12.9 Capacity Planning

Production capacity should be based on measured workload rather than arbitrary resource values.

Capacity planning should consider:

* Requests per second.
* Transactions per second.
* Read/write ratio.
* Concurrent connections.
* Query latency.
* CPU utilization.
* Memory utilization.
* Storage IOPS.
* Storage growth.
* WAL generation rate.
* Replication lag.
* Backup size and duration.

A production capacity model should also include headroom for failure scenarios.

For example, if one PostgreSQL node fails, the remaining node must have enough capacity to handle the expected workload.

This is an important difference between redundancy and usable redundancy.

Two small database nodes may provide failover capability but still fail to provide sufficient capacity when one node is lost.

## 12.10 Upgrades and Maintenance

PostgreSQL, Patroni, etcd and operating-system upgrades should be performed using controlled procedures.

The production process should include:

1. Test the upgrade in a non-production environment.
2. Validate compatibility.
3. Take or verify a recent backup.
4. Confirm replication health.
5. Upgrade one component/node at a time where supported.
6. Verify cluster health after each step.
7. Monitor application behavior.
8. Keep a rollback/recovery procedure available.

Maintenance should avoid unnecessarily taking both PostgreSQL nodes out of service at the same time.

PostgreSQL major-version upgrades require a separate migration strategy and should not be treated as normal package upgrades.

## 12.11 Scaling

The current architecture uses two PostgreSQL nodes.

This provides a simple primary/replica HA model.

Scaling can happen in several directions.

### Vertical Scaling

Increase:

* CPU.
* Memory.
* Storage performance.

This is usually the simplest way to increase the capacity of the primary database.

### Read Scaling

Additional PostgreSQL replicas can be introduced for read-heavy workloads.

However, the application must understand replica lag and read-after-write consistency.

### Connection Scaling

HAProxy and application connection pools should be configured so that application growth does not create an uncontrolled number of PostgreSQL connections.

Connection pooling should be treated as part of the scaling architecture.

### Write Scaling

Adding replicas does not provide write scaling because PostgreSQL still has a single primary for writes in this architecture.

If write throughput eventually exceeds the capacity of one PostgreSQL primary, a different architecture may be required, such as partitioning/sharding or workload decomposition.

That is a larger architectural change and is not solved simply by adding more Patroni replicas.

## 12.12 Operational Ownership

Production operation should have clear ownership.

Responsibilities should include:

### Database/SRE Team

* PostgreSQL and Patroni operation.
* HA and replication.
* Backup and restore.
* Capacity planning.
* Database upgrades.
* Monitoring and alerting.
* Incident response.

### Application Team

* Connection management.
* Retry behavior.
* Transaction handling.
* Query performance.
* Schema migrations.
* Application-level data consistency.
* Application dependency health.

### Infrastructure/Platform Team

* VM or Kubernetes infrastructure.
* Network.
* Storage
