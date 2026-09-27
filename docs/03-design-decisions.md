# Design Decisions

## 1. PostgreSQL HA with Patroni

Patroni is used to manage PostgreSQL high availability and failover.

Patroni monitors the PostgreSQL instances, manages the cluster state, and coordinates leader election through the distributed configuration store.

Using Patroni separates PostgreSQL database management from the HA decision-making process. PostgreSQL remains responsible for data storage and replication, while Patroni manages node roles and failover.

### Alternative: repmgr

`repmgr` provides PostgreSQL replication and failover management, but the design uses Patroni because it provides tighter integration with a distributed consensus store and a clear separation between PostgreSQL and cluster coordination.

---

## 2. etcd as the Distributed Configuration Store

Three etcd nodes are used as the Distributed Configuration Store (DCS) for Patroni.

The three-node etcd cluster provides quorum-based coordination. Patroni uses etcd to store cluster state, leader information, and other coordination data required for failover.

Three nodes are used instead of two because a two-node etcd cluster cannot maintain quorum after losing one member.

The PostgreSQL layer contains two database nodes, while the coordination layer contains three etcd nodes. This keeps the coordination quorum independent from the number of PostgreSQL replicas.

---

## 3. Two PostgreSQL Nodes

The database layer consists of two PostgreSQL nodes:

* PostgreSQL-1
* PostgreSQL-2

One node operates as the primary and the other as the replica.

Streaming replication keeps the replica synchronized with the primary. Patroni manages the PostgreSQL roles and promotes the replica when the primary becomes unavailable.

Two PostgreSQL nodes are sufficient for this lab to demonstrate primary failure, replica failure, replication monitoring, and automated failover.

A larger production deployment may use additional replicas for read scaling, maintenance, or additional failure tolerance.

---

## 4. Streaming Replication

PostgreSQL native streaming replication is used for data replication between the primary and replica.

The replica continuously receives WAL records from the primary and replays them locally.

This approach keeps the replication mechanism within PostgreSQL and avoids introducing an additional replication layer.

The lab uses asynchronous replication. Therefore, an unexpected primary failure can result in some transactions that were committed on the primary but had not yet reached the replica.

The actual replication state and observed data loss are measured during failure testing rather than assumed from the architecture.

---

## 5. HAProxy as the Application Endpoint

Applications connect to HAProxy instead of connecting directly to PostgreSQL nodes.

HAProxy provides a stable endpoint while the PostgreSQL primary can change during failover.

HAProxy determines which PostgreSQL node is currently accepting primary traffic by using health checks against the Patroni-managed PostgreSQL endpoints.

The application therefore does not need to know which database node is currently the primary.

During a failover, existing database connections may be interrupted. HAProxy handles routing for new connections, while the application is responsible for reconnecting failed database sessions.

---

## 6. HAProxy in Docker

HAProxy runs as a Docker container on the MacBook host.

The PostgreSQL and etcd components run inside Linux VMs, while HAProxy provides the client-facing database endpoint from the host environment.

The HAProxy configuration is stored in the repository and deployed as part of the Ansible-managed configuration.

The containerized HAProxy setup keeps the host environment simple and makes the proxy configuration reproducible.

The VM networking configuration provides connectivity between the HAProxy container and the PostgreSQL VM addresses.

---

## 7. Ansible for Infrastructure Configuration

Ansible is used to provision and configure the Linux VMs.

The configuration is divided into roles for:

* Common system configuration
* etcd
* PostgreSQL
* Patroni
* HAProxy

Ansible provides a reproducible configuration path and allows the environment to be recreated without manually configuring individual nodes.

The playbooks use idempotent Ansible modules so that running the deployment multiple times does not continuously modify an already configured environment.

---

## 8. Separation of Infrastructure and Configuration

The environment separates VM creation from software configuration.

The Linux VMs are created using the local virtualization environment on the MacBook. Ansible then connects to those VMs over SSH and configures the operating system and HA components.

This keeps the Ansible repository focused on system configuration rather than tying it to a specific local virtualization provider.

The same Ansible roles can therefore be reused when the underlying VM creation mechanism changes, provided that the resulting nodes meet the expected connectivity and operating system requirements.

---

## 9. Secret Management

Credentials and other sensitive values are not stored directly in the repository as plaintext configuration.

Ansible Vault is used for values such as PostgreSQL credentials and other sensitive configuration parameters.

Non-sensitive environment-specific values remain in inventory and group variables.

This keeps deployment configuration version-controlled while separating secrets from normal configuration data.

---

## 10. Failover and Split-Brain Handling

Failover decisions are coordinated through Patroni and etcd rather than being based only on PostgreSQL health checks.

The etcd cluster provides the coordination quorum required for leader ownership.

A PostgreSQL node does not become the new primary simply because it cannot reach the existing primary. It must successfully acquire the appropriate leader state through the DCS.

This is important during network failures, where two PostgreSQL nodes may still be running but cannot communicate with each other.

Network partition scenarios are explicitly tested to verify the actual cluster behavior.

---

## 11. Alternatives Considered

### repmgr

`repmgr` is a PostgreSQL replication and failover management solution.

It was considered as an alternative to Patroni, but Patroni was selected because its DCS-based architecture provides a clear mechanism for distributed leader coordination and failover.

### Keepalived

Keepalived can provide a virtual IP for high availability.

It is not used as the primary HA mechanism because a virtual IP alone does not determine which PostgreSQL node is the valid primary.

The database role and failover decision still require PostgreSQL-aware cluster management.

### PgBouncer

PgBouncer is useful for connection pooling and reducing PostgreSQL connection overhead.

It is not used as the HA decision layer in this design. HAProxy handles endpoint routing, while Patroni manages database roles.

PgBouncer can be introduced separately if connection pooling becomes a production requirement.

### Kubernetes / CloudNativePG

A Kubernetes-based PostgreSQL operator such as CloudNativePG provides a different operational model and integrates PostgreSQL HA with Kubernetes.

It is outside the scope of this implementation because the target environment is a small VM-based lab and the assignment focuses on understanding PostgreSQL HA components directly.

---

## 12. Main Trade-offs

The selected architecture prioritizes simplicity, reproducibility, and clear separation of responsibilities.

The main trade-offs are:

* Two PostgreSQL nodes provide basic failover but limited redundancy.
* Three etcd nodes provide coordination quorum but add operational components.
* Asynchronous replication allows better availability but does not guarantee zero data loss during an abrupt primary failure.
* A single HAProxy provides a stable endpoint but remains a single point of failure in this lab.
* Running HAProxy in Docker simplifies deployment but introduces an additional networking layer between the proxy and VM-based PostgreSQL nodes.
* Ansible provides reproducibility but requires correct inventory, networking, and secret management.

These limitations are acceptable for the lab implementation and are documented separately as production considerations.

---

## 13. Scope Boundary

The implementation focuses on PostgreSQL high availability, automated failover, reproducible configuration, and failure validation.

Backup and Point-in-Time Recovery are treated separately from HA. A production PostgreSQL platform requires both HA and an independent backup/recovery strategy.

Similarly, production-grade monitoring, centralized logging, TLS, redundant HAProxy instances, and automated backup storage are considered operational extensions beyond the minimum lab topology.
