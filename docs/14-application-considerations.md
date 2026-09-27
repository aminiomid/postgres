# 11. Application-Level Considerations

A highly available PostgreSQL platform can provide database failover and replication, but database availability alone does not guarantee application availability.

A high-traffic application must also handle connection failures, retries, transaction boundaries, traffic growth, query performance and operational events correctly.

The responsibilities are therefore divided between the database platform and the application.

## 11.1 Availability

The database platform is responsible for:

* Maintaining PostgreSQL availability.
* Managing primary and replica roles.
* Detecting node failures.
* Performing automatic failover through Patroni.
* Maintaining replication between PostgreSQL nodes.
* Providing a stable database endpoint through HAProxy.
* Monitoring database and cluster health.

The application is responsible for:

* Handling temporary database unavailability.
* Reconnecting after a connection failure.
* Using connection pooling.
* Applying bounded retry and backoff logic.
* Handling failed transactions correctly.
* Avoiding a dependency on a specific PostgreSQL node.

Database failover should therefore be considered a temporary infrastructure event that the application must be designed to tolerate.

## 11.2 Database Connectivity

Applications should connect to the HAProxy endpoint rather than directly to a PostgreSQL node.

```text id="n0g5e8"
Application
     |
     v
  HAProxy
     |
     v
Current PostgreSQL Primary
```

The application should use a connection pool.

The pool should have appropriate limits for:

* Maximum connections.
* Minimum idle connections.
* Connection timeout.
* Idle connection timeout.
* Connection lifetime.

Connection limits are important in high-traffic environments because increasing application traffic does not necessarily mean that the number of database connections should increase proportionally.

For example, an application handling thousands of HTTP requests per second may still operate with a relatively small and controlled PostgreSQL connection pool if requests efficiently reuse connections.

## 11.3 Failure Handling

A PostgreSQL failover can interrupt existing connections.

The application should therefore expect errors such as:

* Connection reset.
* Connection refused.
* Connection timeout.
* Broken database connection.
* Transaction failure.

The application should discard broken connections and establish new connections through HAProxy.

Retries should be:

* Bounded.
* Rate-limited.
* Implemented with backoff.
* Applied only where the operation is safe to retry.

A retry storm can make an already degraded database situation worse.

For example:

```text id="x8shb2"
Database failure
      |
      v
Thousands of requests fail
      |
      v
All requests retry immediately
      |
      v
Connection storm
      |
      v
Additional database pressure
```

The application should instead use controlled retry behavior.

## 11.4 Transaction Handling

A connection failure does not always mean that a transaction was rolled back.

There can be an ambiguous situation where:

1. The application sends a transaction to PostgreSQL.
2. PostgreSQL commits the transaction.
3. The network connection fails before the application receives the response.

The application cannot safely assume that the transaction did not execute.

Therefore, retrying non-idempotent operations blindly can create duplicate operations.

For important business operations, the application should use appropriate mechanisms such as:

* Idempotency keys.
* Unique business constraints.
* Transaction boundaries.
* Application-level request identifiers.
* Safe retry policies.

The database platform provides transaction guarantees, but the application determines how business operations should behave when a transaction result becomes ambiguous.

## 11.5 Traffic Growth

A high-traffic application can increase database load through:

* More requests.
* More concurrent queries.
* Larger result sets.
* More writes.
* Longer-running transactions.
* Increased connection counts.

The platform should monitor:

* CPU.
* Memory.
* Disk I/O.
* Connection count.
* Query latency.
* Transaction rate.
* Lock contention.
* Replication lag.
* WAL generation.

The application should control the workload through:

* Connection pooling.
* Efficient queries.
* Pagination.
* Caching where appropriate.
* Batching.
* Rate limiting.
* Background processing for expensive operations.

Adding more application instances does not automatically mean that PostgreSQL should accept an equivalent number of additional connections.

Connection pool sizing should therefore be considered across all application instances.

## 11.6 Query Behavior

Query performance is primarily an application and database-design concern rather than an HA mechanism.

The application should avoid:

* Unbounded queries.
* Unnecessary full-table scans.
* Very large result sets.
* Long-running transactions.
* Holding transactions open while waiting for external services.
* Excessive polling.
* N+1 query patterns.

Appropriate indexes, query plans and schema design should be validated against realistic workloads.

Slow queries can affect HA indirectly by increasing:

* CPU utilization.
* Memory pressure.
* Connection occupancy.
* Lock contention.
* Transaction duration.
* WAL generation.

Therefore, query performance is also part of overall platform reliability.

## 11.7 Data Consistency

The current platform uses asynchronous PostgreSQL streaming replication.

Under normal operation, the primary commits transactions independently of replica acknowledgement.

This provides good availability and avoids making every write dependent on replica response latency, but it does not guarantee zero data loss in every failure scenario.

The application should therefore understand that:

* The primary is the source of truth for writes.
* The replica may temporarily lag behind.
* A recently committed transaction may not yet exist on the replica when a sudden primary failure occurs.
* HA failover and backup/PITR solve different problems.

If the business requires stronger guarantees for specific transactions, synchronous replication or application-level durability mechanisms may need to be considered.

## 11.8 Read and Write Behavior

The current design uses a single primary for writes.

A replica should not be treated as an automatically available read source unless the application architecture explicitly supports read scaling.

If read traffic is later distributed to replicas, the application must understand that replicas can lag behind the primary.

This can create read-after-write consistency issues.

For example:

```text id="gqf5zq"
Application
    |
    | INSERT
    v
Primary
    |
    | asynchronous replication
    v
Replica
```

If the application immediately reads from the replica, the newly inserted record may not yet be visible.

Applications requiring read-after-write consistency should route the relevant read to the primary or use an architecture that explicitly handles replica lag.

## 11.9 Operational Safety

The application should be designed so that normal operational events do not become large-scale incidents.

Important practices include:

* Graceful handling of database connection errors.
* Bounded retries.
* Request timeouts.
* Circuit breakers where appropriate.
* Controlled connection pool sizes.
* Idempotent operations where possible.
* Health checks that reflect actual application dependencies.
* Avoiding unlimited queues of database work.
* Monitoring application-side database latency and errors.

Deployment processes should also account for database compatibility.

Schema changes should be designed so that application and database versions can temporarily coexist during rolling deployments.

For example, destructive schema changes should not be deployed before all application instances stop depending on the affected schema.

## 11.10 Responsibilities

The following separation defines the main responsibilities.

| Responsibility                        | Database Platform       | Application               |
| ------------------------------------- | ----------------------- | ------------------------- |
| PostgreSQL availability               | Yes                     | No                        |
| Primary/replica management            | Yes                     | No                        |
| Automatic database failover           | Yes                     | No                        |
| Replication                           | Yes                     | No                        |
| Stable database endpoint              | Yes                     | No                        |
| Connection pooling                    | No                      | Yes                       |
| Reconnection after failure            | No                      | Yes                       |
| Retry policy                          | No                      | Yes                       |
| Transaction semantics                 | Provides DB guarantees  | Defines business handling |
| Query efficiency                      | Provides database tools | Primary responsibility    |
| Index/schema design                   | Shared                  | Shared                    |
| Business-level idempotency            | No                      | Yes                       |
| Application traffic control           | No                      | Yes                       |
| Database resource monitoring          | Yes                     | No                        |
| Application database error monitoring | Partial                 | Yes                       |
| Backup and PITR                       | Yes                     | No                        |
| Business data validation              | No                      | Yes                       |

The boundary is important: the database platform can provide infrastructure-level availability, but it cannot make an application resilient to every failure mode.

## 11.11 High-Traffic Scenario

For a high-traffic application, the expected architecture is:

```text id="7xv5fb"
                 Application Instances
              +---------+---------+
              |         |         |
              v         v         v
           Connection Pools
              \         |         /
               \        |        /
                    HAProxy
                       |
                       v
                PostgreSQL Primary
                       |
                Async Replication
                       |
                       v
                PostgreSQL Replica
```

The application layer controls request concurrency, connection usage and retry behavior.

The database platform controls PostgreSQL availability, replication, failover and database-level observability.

This separation allows each layer to handle the failures it is responsible for without assuming that the other layer will automatically solve them.

## 11.12 Summary

The PostgreSQL HA platform provides the infrastructure required to keep a writable database service available during individual node failures.

The application remains responsible for behaving correctly during transient failures.

In particular, the application must:

* Connect through the stable HAProxy endpoint.
* Use connection pooling.
* Reconnect after failed connections.
* Use bounded retries and backoff.
* Handle ambiguous transaction outcomes safely.
* Control connection and query concurrency.
* Avoid inefficient or unbounded queries.
* Consider replication lag when using replicas for reads.
* Use application-level mechanisms such as idempotency where required.

The platform and application should therefore be treated as two cooperating layers of the reliability design rather than assuming that database HA alone provides complete application availability.
