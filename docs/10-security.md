# 9. Security

The security design focuses on reducing unnecessary exposure, protecting credentials, restricting administrative access, and making the security limitations of the lab explicit.

The environment is a small PostgreSQL HA lab, so enterprise security systems are not required. However, the same basic principles should be applied when moving the design to production.

## 9.1 Relevant Security Risks

The main security risks for this platform are:

* Unauthorized access to PostgreSQL.
* Unauthorized access to Patroni REST APIs.
* Unauthorized access to etcd.
* Exposure of PostgreSQL replication credentials.
* Exposure of Patroni PostgreSQL credentials.
* Unauthorized administrative access to the servers.
* Network access to database and cluster-management ports.
* Accidental exposure of configuration files containing credentials.
* Insufficient logging of administrative and database activity.
* Misconfiguration of firewall rules or network access.

The most important principle is to avoid exposing database and cluster-management interfaces to networks that do not require access to them.

## 9.2 Authentication and Authorization

PostgreSQL uses separate credentials for different purposes.

The configuration defines:

* A PostgreSQL superuser account used by Patroni.
* A dedicated replication user used for physical replication.

The replication user is not used as the PostgreSQL administrative account.

Client connections use PostgreSQL authentication mechanisms configured through `pg_hba.conf`.

The lab currently uses SCRAM authentication for network connections:

```text
host all all 192.168.64.0/24 scram-sha-256
host replication replicator 192.168.64.0/24 scram-sha-256
```

This limits the intended database access to the lab network and avoids using plaintext passwords over the PostgreSQL authentication exchange.

The local PostgreSQL rule currently uses:

```text
local all all trust
```

This is a lab convenience that allows local administrative access through the Unix socket. It should not automatically be carried over to a production environment. Production access should use an appropriate authentication method and tighter authorization rules.

## 9.3 Credential and Secret Handling

Database credentials are stored in Ansible Vault rather than directly in the repository.

The repository contains references to variables such as:

```text
patroni_postgres_password
patroni_replication_password
```

The actual values are stored in the encrypted Vault file.

The rendered Patroni configuration contains the credentials because Patroni needs them at runtime. The configuration file is therefore protected with restrictive permissions:

```text
/etc/patroni/config.yml
owner: postgres
group: postgres
mode: 0600
```

Plaintext production credentials must not be committed to Git.

For production, a dedicated secret-management solution such as Vault, a cloud secret manager, or another approved enterprise solution could be used if required by the environment.

## 9.4 Network Exposure

The platform contains several different network interfaces and ports.

| Component   |                 Port | Purpose                                 |
| ----------- | -------------------: | --------------------------------------- |
| PostgreSQL  |                 5432 | Database connections and replication    |
| Patroni     |                 8008 | Patroni REST API and health information |
| etcd client |                 2379 | Patroni/DCS communication               |
| etcd peer   |                 2380 | etcd cluster communication              |
| HAProxy     | Application-specific | Client access to PostgreSQL             |

These ports should not be exposed publicly.

The intended communication model is:

```text
Application
     |
     v
   HAProxy
     |
     v
 PostgreSQL
```

While the cluster-management communication remains internal:

```text
Patroni <----> etcd
   |
   +---------> PostgreSQL
```

Firewall rules should restrict access based on source and destination rather than simply opening the ports to the entire network.

For example:

* PostgreSQL access should be limited to application/HAProxy networks and required cluster nodes.
* Replication traffic should only be allowed between PostgreSQL nodes.
* etcd client access should be limited to Patroni nodes and required administrative sources.
* etcd peer traffic should only be allowed between etcd members.
* Patroni API access should be restricted to HAProxy, monitoring and administrative networks as required.

## 9.5 Administrative Access

Administrative access to the servers should be performed through controlled SSH access.

For production:

* SSH access should use keys rather than passwords.
* Direct root login should be disabled.
* Administrative access should use named accounts with `sudo`.
* Access should be limited to the required management network.
* SSH activity should be logged.
* Unused administrative accounts should be removed or disabled.

The current lab uses Ansible with the `ubuntu` account and `sudo`/privilege escalation as required by the playbooks.

The lab inventory does not represent a complete production access-control model and should not be treated as one.

## 9.6 Encryption

Internal database traffic is currently protected by network-level isolation and PostgreSQL authentication, but TLS encryption for PostgreSQL connections is not enabled in this lab.

For a production deployment, TLS should be considered for:

* Application → HAProxy
* HAProxy → PostgreSQL, where required
* Administrative connections
* Other connections carrying sensitive information

The exact TLS termination point depends on the production architecture.

etcd and Patroni management traffic should also use TLS in environments where the network cannot be fully trusted.

For this lab, the nodes communicate over a private VM network:

```text
192.168.64.0/24
```

This is an assumption of the lab environment, not a substitute for encryption in a production environment.

## 9.7 Logging and Auditability

Security-relevant and operational events should be logged centrally where possible.

Important events include:

* SSH authentication attempts.
* Administrative actions.
* PostgreSQL authentication failures.
* PostgreSQL connection activity.
* Patroni leader changes and failover events.
* etcd membership or health changes.
* HAProxy connection and backend errors.
* Firewall changes.
* Backup and restore operations.

For production, logs should be sent to a centralized logging platform and retained according to
