# 10. Application Connectivity

Applications should not connect directly to an individual PostgreSQL node because the identity of the primary can change during a failover.

HAProxy is used as the stable connection endpoint between the application and the PostgreSQL cluster.

The application therefore connects to a single HAProxy endpoint instead of selecting a PostgreSQL node itself.

## 10.1 Connectivity Architecture

The intended connection path is:

```text
                  Application
                       |
                       v
                  HAProxy
                  :5432
                       |
              +--------+--------+
              |                 |
              v                 v
        PostgreSQL-1       PostgreSQL-2
          Primary            Replica
```

HAProxy monitors the PostgreSQL nodes and routes new connections only to the node that is currently available as the writable primary.

The application does not need to know which PostgreSQL node currently holds the primary role.

## 10.2 Primary Discovery

The current primary is discovered by HAProxy through health checks against the PostgreSQL/Patroni nodes.

Patroni exposes cluster state through its REST API, including whether a node is the current leader.

HAProxy can use this information to distinguish between:

* Current primary
* Replica
* Unavailable node

The routing decision is therefore based on the current cluster state rather than a static server configuration.

Conceptually:

```text
PostgreSQL-1 -> Primary -> HAProxy -> accepts new connections
PostgreSQL-2 -> Replica -> HAProxy -> does not accept writes
```

After a failover:

```text
PostgreSQL-1 -> Replica
PostgreSQL-2 -> Primary -> HAProxy -> accepts new connections
```

The application continues to use the same HAProxy address.

## 10.3 New Connections After Failover

When the current primary fails, Patroni promotes the healthy replica.

HAProxy health checks then detect the new primary and update the backend state.

New application connections are routed to the new primary.

For example:

```text
Before failure:

Application
     |
     v
  HAProxy
     |
     v
postgres-1 (Primary)


After failure:

Application
     |
     v
  HAProxy
     |
     v
postgres-2 (New Primary)
```

The application does not need to change its connection string during the failover.

The expected sequence is:

1. PostgreSQL primary fails.
2. Patroni detects the failure.
3. Patroni promotes the replica.
4. The new primary becomes writable.
5. HAProxy detects the new primary.
6. New connections are sent to the new primary.

The actual time available to applications depends on Patroni detection/failover settings and HAProxy health-check intervals.

## 10.4 Existing Connections

Existing TCP connections to the failed PostgreSQL primary cannot be transparently moved to another PostgreSQL server.

If the primary node fails, connections established to that node may be terminated or become unusable.

HAProxy can route **new connections** to the new primary, but it cannot migrate an existing PostgreSQL session from one server to another.

Therefore, the application must be able to handle connection failures.

Typical behavior should be:

```text
Existing connection
       |
       X
 Primary failure
       |
       v
Connection error
       |
       v
Application reconnects
       |
       v
HAProxy
       |
       v
New Primary
```

This is an important distinction between database failover and application-level connection recovery.

## 10.5 Connection Management

The application should use a PostgreSQL connection pool rather than opening a new connection for every database operation.

The connection pool should:

* Detect broken connections.
* Remove failed connections from the pool.
* Establish new connections through HAProxy.
* Retry connection establishment when appropriate.
* Avoid continuously retrying at a high rate during an outage.
* Reuse healthy connections during normal operation.

The pool should have sensible limits for:

* Maximum connections.
* Minimum idle connections.
* Connection timeout.
* Idle timeout.
* Connection lifetime.

These values depend on the application workload and PostgreSQL capacity.

HAProxy also provides a useful control point for limiting the number of connections reaching PostgreSQL.

## 10.6 Application Behavior During Failover

The application should assume that a database failover can temporarily interrupt connectivity.

During a failover, the application should:

1. Detect the connection failure.
2. Close or discard the failed connection.
3. Wait for a short, bounded retry interval.
4. Establish a new connection through HAProxy.
5. Retry the operation only when it is safe to do so.

Retries should be carefully implemented.

Automatically retrying a database operation is not always safe. For example, if a transaction was committed but the client lost the connection before receiving the response, blindly retrying the transaction could result in a duplicate business operation.

For non-idempotent operations, the application should use appropriate transaction handling or idempotency mechanisms.

## 10.7 Connection String

The application should use the HAProxy endpoint rather than the individual PostgreSQL servers.

Conceptually:

```text
postgresql://<user>:<password>@<haproxy-endpoint>:5432/<database>
```

The PostgreSQL node addresses should not be hard-coded into the application as the primary connection target.

This keeps database role changes and failover handling outside the application configuration.

## 10.8 Failure Scenario

Assume the initial state is:

```text
postgres-1 = Primary
postgres-2 = Replica
```

The application connects to HAProxy.

If `postgres-1` fails:

```text
postgres-1 = Failed
postgres-2 = Promoted to Primary
```

Patroni performs the role change and HAProxy updates its backend state.

New connections then follow:

```text
Application
    |
    v
HAProxy
    |
    v
postgres-2
```

Existing connections that were established to `postgres-1` may fail and must be recreated by the application.

When `postgres-1` returns, it should rejoin the cluster as a replica rather than immediately becoming primary.

## 10.9 Client Assumptions

This design assumes that the application:

* Uses HAProxy as its database endpoint.
* Does not depend on a specific PostgreSQL node.
* Uses a connection pool or equivalent connection-management mechanism.
* Can detect broken database connections.
* Can reconnect after a transient database failure.
* Uses bounded retry/backoff logic.
* Handles transactions correctly when a connection is lost.
* Does not assume that an existing TCP connection survives a PostgreSQL failover.

The design does not assume that HAProxy can preserve an existing PostgreSQL session after a node failure.

## 10.10 Validation

The following scenario should be used to validate application connectivity:

1. Start with `postgres-1` as the primary.
2. Connect the application through HAProxy.
3. Generate normal database traffic.
4. Stop Patroni/PostgreSQL on the primary.
5. Verify that Patroni promotes the replica.
6. Verify that HAProxy detects the new primary.
7. Verify that new connections succeed through the same HAProxy endpoint.
8. Verify that existing connections to the failed primary are handled by the application.
9. Verify that the failed node returns as a replica.
10. Verify that normal traffic continues after recovery.

The current lab has validated the PostgreSQL/Patroni failover and recovery path. HAProxy-based application reconnect behavior has not yet been executed as an end-to-end test, so this remains a validation item rather than a completed test result.

## 10.11 Summary

HAProxy provides a stable database endpoint while Patroni manages PostgreSQL primary selection.

This separates responsibilities:

```text
Application
    |
    | Stable endpoint
    v
HAProxy
    |
    | Current primary
    v
Patroni-managed PostgreSQL cluster
```

Patroni handles database role changes, HAProxy routes new connections to the current primary, and the application is responsible for handling broken existing connections and reconnecting through the stable endpoint.

This approach avoids putting primary-discovery logic inside every application and allows database failover to happen without changing the application's connection configuration.
