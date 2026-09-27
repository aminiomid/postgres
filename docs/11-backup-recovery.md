# Backup and Recovery

## 7.1 Backup Strategy

High availability and backup solve different problems.

The PostgreSQL replica provides availability when a PostgreSQL node fails, but it is not considered a backup. Changes made on the primary, including accidental updates or deletes, are normally replicated to the standby.

The backup strategy therefore uses an independent backup mechanism.

For a production implementation, the recommended approach is:

```text
PostgreSQL Primary
       |
       +---- Physical Base Backup
       |
       +---- WAL Archiving
                    |
                    v
              Backup Storage
```

The proposed backup tool is **pgBackRest**.

pgBackRest provides:

* Physical PostgreSQL backups.
* Incremental backups.
* WAL archiving.
* Backup retention.
* Backup integrity checks.
* Restore operations.
* Point-in-Time Recovery.
* Backup repository management.

The backup repository should not be located only on the PostgreSQL host. A production implementation should use separate storage, preferably in a different failure domain.

Examples include:

* Dedicated backup server.
* Object storage.
* Separate storage cluster.
* Secondary site for disaster recovery.

The exact storage technology depends on the production environment and its availability requirements.

---

## 7.2 Backup Types

The production backup schedule should contain both a regular full backup and more frequent incremental backups.

A possible baseline schedule is:

```text
Weekly     Full backup
Daily      Differential backup
Continuous WAL archiving
```

The exact schedule should be adjusted according to:

* Database size.
* WAL generation rate.
* Backup window.
* Available storage.
* RPO requirements.
* Restore time requirements.

There is no reason to select a backup schedule only because it is a common PostgreSQL recommendation. The final schedule should be validated against the actual database growth and recovery requirements.

---

## 7.3 Recovery Objectives

Backup recovery has different objectives from HA failover.

The HA layer is intended to handle node failures quickly.

Backup and PITR are intended to handle cases such as:

* Accidental data deletion.
* Incorrect application changes.
* Database corruption.
* Loss of the complete PostgreSQL cluster.
* Long-term recovery requirements.

The recovery objectives should therefore be defined separately.

A possible production baseline is:

```text
HA failure RTO:       < 30 seconds
HA RPO:               Near-zero, not guaranteed zero

Backup/PITR RPO:      Based on WAL archive continuity
Backup recovery RTO:  Defined by restore-size and infrastructure tests
```

The backup RTO should not be guessed.

For example, restoring a 500 GB database from object storage may take significantly longer than restoring a 20 GB database from local backup storage.

The actual RTO must be measured using a representative restore.

---

## 7.4 Retention

Backup retention should protect against both operational failures and historical recovery requirements.

An example policy is:

```text
Daily backups:       14 days
Weekly backups:      8 weeks
Monthly backups:     12 months
WAL archives:        Retained according to the PITR retention window
```

These values are an example baseline rather than a universal requirement.

Retention should be based on:

* Business recovery requirements.
* Compliance requirements.
* Storage capacity.
* Database growth.
* Desired PITR window.

Retention must also account for WAL files required by the retained backups.

Deleting old WAL independently of the backup retention policy can make an otherwise valid base backup impossible to restore to the required point in time.

---

## 7.5 WAL Archiving

Continuous WAL archiving is required for reliable Point-in-Time Recovery.

The conceptual flow is:

```text
PostgreSQL
    |
    | WAL
    v
pgBackRest archive
    |
    v
Backup Repository
```

A base backup provides a starting point, while archived WAL provides the changes required to recover the database to a later point in time.

WAL archiving therefore provides much finer recovery granularity than periodic full backups alone.

The production configuration should monitor archive success and failure.

A backup system should not be considered healthy merely because the last full backup succeeded.

---

## 7.6 Backup Monitoring

Backup monitoring should cover both the backup process and the resulting recovery capability.

Important metrics include:

### Backup status

* Last successful full backup.
* Last successful incremental/differential backup.
* Backup duration.
* Backup size.
* Backup failure count.
* Backup age.

### WAL archiving

* Last successfully archived WAL.
* Archive failure count.
* Archive delay.
* WAL archive growth.

### Repository

* Available storage.
* Storage growth.
* Repository connectivity.
* Retention status.

### Recovery validation

* Last successful restore test.
* Restore duration.
* Recovery validation result.

Example operational alerts:

```text
Backup has not succeeded within the expected interval.
WAL archiving has failed.
WAL archive delay exceeds the defined threshold.
Backup repository storage is approaching capacity.
Restore validation has not been performed within the defined period.
```

The exact thresholds should be derived from the defined RPO and retention requirements.

---

## 7.7 Backup Validation

A successful backup command is not proof that the database can be restored.

Backup validation should therefore happen at multiple levels.

### Level 1 — Backup Integrity

Use pgBackRest validation commands to verify that the backup repository and backup contents are consistent.

For example:

```bash
pgbackrest --stanza=main check
```

and:

```bash
pgbackrest --stanza=main info
```

These checks verify backup metadata and repository accessibility, but they are not sufficient by themselves.

### Level 2 — Restore Test

A real restore should periodically be performed on a separate PostgreSQL instance.

The restore environment should not replace or modify the production cluster.

The basic process is:

```text
Backup Repository
       |
       v
Temporary PostgreSQL Instance
       |
       v
Restore
       |
       v
Start PostgreSQL
       |
       v
Run validation queries
```

The restored database should be checked for:

* PostgreSQL startup success.
* Expected databases.
* Expected tables.
* Row counts for important tables.
* Application-level consistency checks.
* Database connectivity.
* Required extensions.
* WAL recovery completion.

### Level 3 — Application Validation

For critical systems, database-level validation alone is not enough.

The application should execute representative read-only checks against the restored database.

For example:

```text
Connect application
      ↓
Run health checks
      ↓
Query critical business tables
      ↓
Validate expected records
      ↓
Confirm application behavior
```

This provides much stronger evidence that the backup is actually usable.

---

## 7.8 Point-in-Time Recovery

Point-in-Time Recovery is required to protect against logical errors that are replicated to the standby.

For example:

```text
10:00  Normal operation
10:15  Accidental DELETE
10:20  Problem detected
```

Because the DELETE may have been replicated to the standby, failover to the standby would not recover the deleted data.

Instead, PITR can restore the database to a point immediately before the unwanted change.

Conceptually:

```text
Base Backup
    |
    +---- WAL 10:01
    +---- WAL 10:05
    +---- WAL 10:10
    +---- WAL 10:15
    +---- WAL 10:16
    ...
             |
             v
      Recovery Target
      10:14:59
```

The recovery target should be selected according to the incident.

PITR should be tested periodically rather than simply documented.

---

## 7.9 Complete Cluster Loss

HA protects against failure of an individual PostgreSQL node.

It does not protect against losing the complete PostgreSQL environment.

For example:

```text
PostgreSQL-1  ─┐
               ├── Complete environment lost
PostgreSQL-2  ─┘
       +
     etcd
```

If both PostgreSQL nodes and the local HA environment are lost, recovery must come from the independent backup repository.

The recovery process would be:

```text
1. Provision replacement infrastructure
              ↓
2. Install PostgreSQL
              ↓
3. Install pgBackRest
              ↓
4. Access backup repository
              ↓
5. Restore the latest valid base backup
              ↓
6. Replay archived WAL
              ↓
7. Recover to the required point in time
              ↓
8. Validate database consistency
              ↓
9. Rebuild Patroni/etcd HA topology
              ↓
10. Restore application connectivity
```

This is fundamentally different from Patroni failover.

Patroni promotes an existing PostgreSQL replica.

Backup recovery reconstructs PostgreSQL from stored recovery data.

---

## 7.10 Backup Storage and Failure Domain

The backup repository should be independent from the PostgreSQL cluster.

Storing backups only on:

```text
postgres-1
postgres-2
```

would not provide meaningful protection against complete infrastructure loss.

A production design should use a separate failure domain.

For example:

```text
                    PostgreSQL HA
                  ┌───────────────┐
                  │ postgres-1    │
                  │ postgres-2    │
                  │ etcd x3       │
                  └───────┬───────┘
                          |
                     WAL / Backup
                          |
                          v
                  ┌───────────────┐
                  │ Backup        │
                  │ Repository    │
                  └───────────────┘
```

For stronger disaster recovery requirements, a second copy should be maintained in another site or failure domain.

The backup repository itself therefore becomes part of the disaster recovery design and must also be monitored and protected.

---

## 7.11 Recovery Testing

A production backup strategy is incomplete until recovery has been tested.

A periodic recovery test should include:

### Full Restore

Restore the latest backup to an isolated PostgreSQL instance.

Verify:

* PostgreSQL starts successfully.
* Databases are present.
* Expected tables are present.
* Important records exist.
* Application connectivity works.

### PITR Test

Select a known recovery target and restore to that point.

Verify that:

* Changes before the recovery target are present.
* Changes after the recovery target are not present.
* PostgreSQL reaches the expected recovery state.

### Complete Cluster Recovery

Periodically perform a disaster recovery exercise:

```text
Simulated total cluster loss
          ↓
Provision new nodes
          ↓
Restore PostgreSQL
          ↓
Replay WAL
          ↓
Validate data
          ↓
Rebuild Patroni/etcd
          ↓
Restore application access
```

The measured duration of this exercise becomes the basis for the real backup recovery RTO.

---

## 7.12 Production Automation

Complete backup automation is outside the scope of the current PostgreSQL HA lab.

The production implementation should automate:

* pgBackRest installation and configuration.
* Backup repository configuration.
* Backup schedules.
* WAL archiving.
* Retention.
* Backup monitoring.
* Alerting.
* Periodic restore validation.
* Disaster recovery exercises.

Ansible can manage the static configuration, while the backup tool handles backup execution and retention.

The automation should also ensure that backup failures are visible to the same operational monitoring system used for PostgreSQL and Patroni.

---

## 7.13 Relationship Between HA and Backup

The final architecture should be understood as several complementary layers:

```text
                 Application Availability
                         |
                      HAProxy
                         |
                ┌───────────────┐
                │    Patroni    │
                └───────┬───────┘
                        |
             PostgreSQL Streaming
                  Replication
                 /           \
                /             \
        PostgreSQL-1       PostgreSQL-2
                \             /
                 \           /
                  Backup / WAL
                        |
                        v
                 Backup Repository
                        |
                        v
                     PITR
```

Each layer solves a different problem:

| Mechanism                  | Purpose                                      |
| -------------------------- | -------------------------------------------- |
| Patroni                    | PostgreSQL HA and automatic failover         |
| Streaming replication      | Maintain a standby for availability          |
| HAProxy                    | Provide a stable client endpoint             |
| pgBackRest                 | Backup and restore                           |
| WAL archiving              | Enable continuous recovery history           |
| PITR                       | Recover from logical mistakes and corruption |
| Separate backup repository | Protect against complete cluster loss        |

The important operational principle is that **a healthy HA cluster does not prove that the database is recoverable**.

The only reliable way to establish recoverability is to periodically restore the backups and verify the restored database.

---

## 7.14 Current Lab Status

The current submission implements and tests PostgreSQL HA and replication behavior.

Backup automation and full PITR automation are outside the current lab scope.

The production implementation should therefore add:

* pgBackRest.
* Independent backup storage.
* Continuous WAL archiving.
* Defined retention.
* Backup monitoring.
* Scheduled restore validation.
* PITR testing.
* Complete cluster recovery testing.

The backup strategy should be considered complete only after a real restore has been successfully performed and the recovery time and recovered data have been validated.
