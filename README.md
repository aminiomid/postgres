# PostgreSQL High Availability

A PostgreSQL High Availability lab built with **PostgreSQL 16, Patroni, etcd, HAProxy, streaming replication, and Ansible**.

The project demonstrates automated PostgreSQL failover, service discovery and coordination through etcd, stable application connectivity through HAProxy, and recovery of a failed PostgreSQL node.

The environment is designed as a reproducible lab and reference architecture rather than a production-ready deployment.

---

## Architecture

```text
                         Application
                              |
                              v
                         +---------+
                         | HAProxy |
                         +----+----+
                              |
                     Current PostgreSQL
                         Primary
                              |
                    Streaming Replication
                              |
                              v
                     PostgreSQL Replica
                              ^
                              |
                         +----+----+
                         | Patroni |
                         +----+----+
                              |
                              v
                   +----------------------+
                   |         etcd         |
                   | 3-node DCS cluster   |
                   +----------------------+
```

### Components

| Component     | Purpose                                           |
| ------------- | ------------------------------------------------- |
| PostgreSQL 16 | Database engine                                   |
| Patroni       | PostgreSQL HA and failover management             |
| etcd          | Distributed Configuration Store (DCS) for Patroni |
| HAProxy       | Stable endpoint for application connections       |
| Ansible       | Infrastructure and configuration automation       |
| Docker        | Runs HAProxy in the lab environment               |

---

## Lab Topology

| Node       | IP               | Role                 |
| ---------- | ---------------- | -------------------- |
| etcd-1     | `192.168.64.2`   | etcd                 |
| etcd-2     | `192.168.64.3`   | etcd                 |
| etcd-3     | `192.168.64.4`   | etcd                 |
| postgres-1 | `192.168.64.5`   | PostgreSQL + Patroni |
| postgres-2 | `192.168.64.6`   | PostgreSQL + Patroni |
| HAProxy    | MacBook / Docker | Application endpoint |

PostgreSQL uses asynchronous physical streaming replication.

At any point in time, one PostgreSQL node is the Patroni leader and the ot
