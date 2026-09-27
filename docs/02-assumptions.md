# Assumptions

This project is implemented as a local, reproducible laboratory environment for testing PostgreSQL high availability and failure scenarios.

The main focus is on automated failover, cluster state management, client connectivity, failure handling, and node recovery.

The environment is intentionally smaller than a production deployment. Production-specific requirements and limitations are documented separately.

## Environment

The environment runs locally on a MacBook.

Linux virtual machines provide the PostgreSQL and etcd nodes. Ansible runs directly on the MacBook and manages the virtual machines over SSH.

HAProxy runs as a Docker container on the MacBook.

The Linux virtual machines use Ubuntu 24.04 LTS and PostgreSQL 16.

## Topology

The environment contains:

* Two PostgreSQL nodes
* Two Patroni instances, one on each PostgreSQL node
* Three etcd nodes
* One HAProxy instance

Three etcd nodes provide quorum for the Patroni distributed configuration store and allow the etcd cluster to continue operating after the loss of a single node.

## PostgreSQL

PostgreSQL uses streaming replication between the database nodes.

Patroni manages the PostgreSQL instances, leader election, failover, and replica state.

At any given time, one PostgreSQL node acts as the primary and the other node operates as the replica.

## Client Connectivity

Applications connect to HAProxy rather than directly connecting to PostgreSQL nodes.

HAProxy provides a stable endpoint and routes new connections to the current PostgreSQL primary.

Existing database connections may be interrupted during a primary failure. The application is expected to handle connection failures and establish new connections after failover.

## High Availability Scope

The main goal of this implementation is automated failover at the PostgreSQL layer.

When the primary becomes unavailable, Patroni detects the failure and promotes the replica when the required conditions are met.

High availability does not guarantee zero downtime or zero data loss for every failure scenario. The actual result depends on the failure type and the state of replication when the failure occurs.

## Data Durability

High availability and data protection are treated as separate concerns.

Streaming replication provides another copy of the database and reduces the impact of a database node failure. It is not considered a replacement for backups.

Backup and Point-in-Time Recovery are therefore treated separately from the HA mechanism.

## Failure Testing

The environment is tested against the following failure scenarios:

* Primary failure
* Replica failure
* Network partition
* Replication failure

The tests record detection time, failover time, client impact, cluster state, and potential data loss where applicable.

## Resource Constraints

The virtual machines are sized for a local laboratory environment and do not represent production capacity.

PostgreSQL resource settings and performance-related configuration are therefore specific to this environment.

Production sizing and tuning require workload information and performance testing.

## Security

Production credentials and real secrets are not stored in the repository.

Sensitive values used by the laboratory environment are managed separately from regular configuration files.

Network access is limited to the services and ports required by the cluster.

## HAProxy

The laboratory environment uses a single HAProxy instance.

The PostgreSQL layer therefore provides automated failover, while the HAProxy endpoint remains a single point of failure in this implementation.

Production deployment requires redundancy at the client connectivity layer.

## Production Boundary

This implementation demonstrates PostgreSQL high availability and operational behavior in a reproducible local environment.

It is not considered a complete production deployment.

Production-specific requirements such as redundant client connectivity, backup infrastructure, disaster recovery, centralized secret management, monitoring infrastructure, capacity planning, and failure-domain separation are addressed separately.

## Scope

The implementation prioritizes a working and understandable HA environment over implementing every possible production feature.

Capabilities that are outside the scope of the laboratory environment are documented with their intended production approach and associated trade-offs.
