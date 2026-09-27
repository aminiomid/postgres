# Architecture

## Overview

The environment uses PostgreSQL streaming replication with Patroni for high availability.

Patroni manages the PostgreSQL instances and uses a three-node etcd cluster as the distributed configuration store and coordination layer.

HAProxy provides a stable endpoint for applications and routes new database connections to the current PostgreSQL primary.

The topology contains two PostgreSQL nodes, three etcd nodes, and one HAProxy instance.

```text
                              Application
                                   |
                                   |
                                HAProxy
                              Docker host
                                   |
                         +---------+---------+
                         |                   |
                         v                   v
                    PostgreSQL-1        PostgreSQL-2
                     Patroni-1           Patroni-2
                         |                   |
                         +---------+---------+
                                   |
                                   |
                         +---------+---------+
                         |         |         |
                         v         v         v
                      etcd-1    etcd-2    etcd-3
```

At any point in time, one PostgreSQL node is the active primary and the other node operates as a replica.

## Components

### PostgreSQL

PostgreSQL stores the application data and provides the database replication mechanism.

The primary accepts write operations and streams WAL changes to the replica.

The replica continuously receives and replays WAL from the primary.

PostgreSQL itself does not perform automatic leader election in this design. Patroni manages the lifecycle and role changes between the PostgreSQL instances.

### Patroni

Patroni manages the PostgreSQL instances and coordinates the HA state.

It is responsible for:

* Managing PostgreSQL startup and shutdown
* Monitoring PostgreSQL health
* Maintaining cluster state
* Managing leader election
* Promoting a replica when the primary fails
* Managing replica configuration
* Coordinating PostgreSQL state through etcd

Patroni does not store the application data. PostgreSQL remains responsible for the database data and replication.

### etcd

The three-node etcd cluster acts as the distributed coordination layer for Patroni.

Patroni uses etcd to store cluster state and the current leader information.

Using three etcd nodes allows the DCS to maintain quorum when one etcd node becomes unavailable.

The etcd cluster is not used to store PostgreSQL application data.

### HAProxy

HAProxy provides the stable database endpoint used by clients.

It does not participate in PostgreSQL leader election.

Instead, HAProxy checks the PostgreSQL nodes through the Patroni-managed health endpoint and routes new connections to the node that currently acts as the primary.

When Patroni promotes the replica, the health status of the nodes changes and HAProxy starts routing new connections to the new primary.

HAProxy runs as a Docker container in the laboratory environment.

## Topology

The database layer contains two PostgreSQL nodes:

```text
postgres-1
    |
    +-- Patroni
    |
    +-- PostgreSQL

postgres-2
    |
    +-- Patroni
    |
    +-- PostgreSQL
```

The coordination layer contains three etcd nodes:

```text
etcd-1
etcd-2
etcd-3
```

The client connectivity layer contains one HAProxy instance:

```text
Application
     |
     v
HAProxy
     |
     +----> postgres-1
     |
     +----> postgres-2
```

The actual PostgreSQL role is determined by Patroni rather than by a static HAProxy configuration.

## Data Flow

Under normal conditions, the data flow is:

```text
Application
     |
     v
HAProxy
     |
     v
PostgreSQL Primary
     |
     | WAL streaming replication
     v
PostgreSQL Replica
```

The application sends write operations to the current primary.

PostgreSQL generates WAL records and streams them to the replica.

The replica replays the WAL and keeps its local database state synchronized with the primary.

Patroni and etcd handle cluster coordination separately from the PostgreSQL data path.

## Client Connection Flow

The application uses the HAProxy endpoint rather than a specific PostgreSQL node.

```text
Application
     |
     v
HAProxy
     |
     +---- Primary: accepts connections
     |
     +---- Replica: does not receive normal application traffic
```

HAProxy determines which PostgreSQL node is currently eligible to receive application traffic.

When the primary changes, new connections are routed to the new primary.

Existing connections that were established before the failure may be terminated. The application is responsible for retrying failed connections and establishing new connections through the HAProxy endpoint.

## Failover Flow

When the current primary becomes unavailable, the failover process follows this general sequence:

```text
PostgreSQL Primary fails
          |
          v
Patroni detects failure
          |
          v
Patroni instances coordinate through etcd
          |
          v
A new leader is elected
          |
          v
Replica is promoted
          |
          v
New primary becomes available
          |
          v
HAProxy detects the new primary
          |
          v
New client connections use the new primary
```

The exact detection and failover time depends on the Patroni configuration, health-check intervals, network conditions, and the state of the replica at the time of failure.

The actual values are measured during the failure tests and documented separately in `failure-testing.md`.

## Leader Election

Patroni uses etcd as the distributed coordination mechanism.

The current PostgreSQL leader is represented in the shared cluster state stored in etcd.

Patroni instances use this shared state to determine which node currently owns the leader role.

A PostgreSQL node does not promote itself simply because it cannot reach the current primary. Promotion requires coordination through the DCS and acquisition of the leader state.

This prevents independent PostgreSQL nodes from promoting themselves at the same time under normal failure conditions.

## Split-Brain Prevention

Split-brain is addressed primarily through the distributed coordination provided by etcd and Patroni.

A node must acquire the appropriate leader state through the DCS before becoming the PostgreSQL primary.

If a PostgreSQL node loses access to the DCS, it cannot independently establish itself as the new leader.

This is particularly important during network partitions. A node that is isolated from the rest of the cluster must not continue accepting writes as an independent primary.

The behavior during network partition is explicitly tested as part of the failure testing phase.

The two-node PostgreSQL topology also has an important limitation: PostgreSQL itself cannot form a majority between two database nodes. The three-node etcd cluster therefore provides the quorum required for leader coordination.

## Why This Design

The design separates the main HA responsibilities between different components.

PostgreSQL handles data storage and replication.

Patroni handles PostgreSQL lifecycle management and failover.

etcd provides distributed coordination and leader state.

HAProxy provides a stable client endpoint and routes traffic according to the current cluster state.

This separation keeps each component focused on a specific responsibility and makes the failure behavior easier to observe and test.

Three etcd nodes are used because a three-node quorum can tolerate the loss of one etcd node while continuing to operate.

Two PostgreSQL nodes are sufficient for this assignment because the main requirement is to demonstrate primary/replica failover without adding unnecessary database nodes to the laboratory environment.

## Alternatives Considered

### PostgreSQL + repmgr

`repmgr` provides PostgreSQL replication and failover management and is a possible alternative to Patroni.

Patroni was selected because it provides a well-defined HA control loop and integrates naturally with a distributed configuration store such as etcd.

### PostgreSQL + Keepalived

Keepalived could provide a virtual IP for client connectivity.

It does not replace the PostgreSQL HA and leader-election layer, so it would still require another mechanism to determine which PostgreSQL node is the active primary.

HAProxy provides more explicit health-check and routing capabilities for this environment.

### PostgreSQL + PgBouncer

PgBouncer is useful for connection pooling and can be added in front of PostgreSQL.

It is not a replacement for Patroni or the DCS because it does not provide database leader election or PostgreSQL failover management.

Connection pooling is therefore treated as a separate concern.

### Kubernetes-based PostgreSQL

A Kubernetes-based implementation could use operators such as CloudNativePG to manage the PostgreSQL cluster.

Kubernetes is not used here because the assignment focuses on PostgreSQL HA rather than Kubernetes orchestration. Using VMs keeps the failure scenarios and underlying HA mechanisms easier to inspect.

## Trade-offs

The architecture keeps the PostgreSQL layer small, which makes the failure scenarios easier to reproduce and understand.

The main trade-off is that the two-node PostgreSQL topology provides limited redundancy compared with a larger database cluster.

The single HAProxy instance is another limitation of the laboratory environment. PostgreSQL can fail over while the client endpoint itself remains a single point of failure.

Using etcd adds another distributed system to the architecture, but it provides the quorum and coordination mechanism required by Patroni.

The environment therefore has more components than a simple primary/replica PostgreSQL setup, but each component has a distinct role in the HA design.

## Known Limitations

The current implementation has the following limitations:

* Only two PostgreSQL nodes are used.
* HAProxy runs as a single instance.
* The environment uses local virtual machines rather than independent physical or cloud failure domains.
* Storage redundancy is limited to PostgreSQL replication.
* The laboratory environment does not provide multi-site disaster recovery.
* Backup infrastructure is separate from the HA implementation.
* Network and hardware failures are limited to the scenarios that can be reproduced in the local environment.
* PostgreSQL configuration is not tuned for a specific production workload.

These limitations are intentional for the scope of the assignment and are addressed as production considerations in `production.md`.
