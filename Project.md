# Senior DevOps / SRE Take-Home Assignment

## High-Availability PostgreSQL Platform

## Objective

Design and implement a **production-oriented, highly available PostgreSQL environment** using Infrastructure as Code.

The objective is not simply to deploy PostgreSQL. The assignment should demonstrate how you approach reliability, automation, failure handling, observability, data protection, security, and day-to-day operations.

There is no single correct architecture or technology choice. Make reasonable assumptions, document your decisions, and validate the behavior of your system.

---

## 1. Core Requirements

Your solution should:

- Provision a highly available PostgreSQL environment.
- Support automated leader election and failover.
- Provide a stable application endpoint for the current primary.
- Include health checks and validation.
- Be reproducible from a clean environment with minimal manual intervention.
- Follow Infrastructure as Code and idempotency principles.
- Include failure and recovery procedures.
- Be submitted as a Git repository.

You may use any technologies you consider appropriate.

**Vagrant and Ansible** are suggested for a reproducible local environment, but they are not required. Alternative approaches are welcome when their use is explained.

---

## 2. Architecture

Design a PostgreSQL HA topology appropriate for the environment.

Your architecture should address:

- Primary and replica topology
- Replication
- Leader election and failover
- Client connectivity and routing
- Health checking and failure detection
- Data consistency and durability
- Network failures
- Recovery and node reintegration

Document:

- The architecture and responsibilities of each component.
- Why you selected this design.
- Alternatives you considered.
- Important assumptions and trade-offs.
- Known limitations.
- How split-brain scenarios are prevented or mitigated.

Include a simple architecture diagram.

---

## 3. Infrastructure as Code

The environment should be reproducible using a flow similar to:

```text
Clone repository
       ↓
Run deployment
       ↓
Provision infrastructure
       ↓
Configure PostgreSQL and HA
       ↓
Run validation
       ↓
Working HA PostgreSQL cluster
```

The implementation should demonstrate:

- Idempotent automation.
- Clear separation between infrastructure and configuration.
- Sensible repository structure.
- Minimal hard-coded, environment-specific values.
- Safe handling of credentials and sensitive data.
- Clear deployment, teardown, and recreation procedures.

Avoid manual configuration wherever reasonably possible.

---

## 4. Failure Testing

High availability should be **demonstrated**, not only described.

Test and document the following scenarios.

### Primary failure

Make the current PostgreSQL primary unavailable and demonstrate:

- How the failure is detected.
- Whether another node is promoted automatically.
- Approximate detection and failover time.
- How clients reconnect.
- The resulting cluster state.
- Whether any data loss occurs under the tested conditions.

### Replica failure

Make a replica unavailable and demonstrate:

- Whether the cluster continues operating.
- How the failure is detected.
- What happens when the replica returns.
- How it is safely reintegrated.

### Network partition

Isolate a PostgreSQL node from the rest of the cluster.

Explain or demonstrate:

- What happens to the isolated node.
- Whether it can continue accepting writes.
- How split brain is prevented.
- How the node is safely recovered.

### Replication failure

Introduce or simulate a replication problem.

Explain or demonstrate:

- How replication health is checked.
- How degradation or failure is detected.
- What operational action is required.
- How replication is recovered.

Document any important failure modes that the submitted implementation does not handle automatically.

---

## 5. RPO and RTO

Define the expected:

- **RPO — Recovery Point Objective**
- **RTO — Recovery Time Objective**

Explain:

- What data loss could occur during a primary failure.
- How long detection and failover are expected to take.
- Which assumptions those expectations depend on.
- How stricter RPO or RTO requirements would affect the architecture.

Clearly distinguish between:

- High availability
- Backup
- Disaster recovery
- Point-in-time recovery

---

## 6. PostgreSQL Configuration and Operational Readiness

Configure PostgreSQL appropriately for the submitted environment and its intended workload.

Document:

- The decisions you made.
- The assumptions behind them.
- The risks and trade-offs involved.
- How your choices affect availability, durability, performance, and recovery.
- How you would validate and refine the configuration in production.

You should determine which areas require attention and which configuration choices are appropriate.

Avoid treating generic recommendations as universally correct. Decisions should be justified based on the environment, expected workload, and reliability requirements.

---

## 7. Backup and Recovery

Implement or document a realistic backup and recovery strategy.

Address:

- Backup approach
- Recovery objectives
- Retention
- Backup monitoring
- Backup validation
- Point-in-time recovery
- Recovery from complete cluster loss

Explain how you would verify that backups are restorable rather than relying only on successful backup commands.

If complete backup and recovery automation is outside the scope of the submission, document how it would be implemented and tested in production.

---

## 8. Observability

Implement or document sufficient observability to operate and troubleshoot the platform.

Determine:

- What should be monitored.
- Which conditions require alerts.
- How failures and degradation are detected.
- What information operators need during an incident.
- How monitoring itself is validated.
- How the platform’s health is distinguished from the health of individual components.

You may use any observability tools you consider appropriate.

Installing monitoring software alone is not sufficient. Explain how the available signals would support incident detection, diagnosis, and recovery.

---

## 9. Security

Apply reasonable security practices to the submitted environment.

Determine and document:

- The relevant security risks.
- Authentication and authorization decisions.
- Credential and secret handling.
- Network exposure.
- Administrative access.
- Encryption requirements.
- Logging and auditability.
- Security assumptions and limitations.

Do not commit plaintext production credentials.

Enterprise security or secret-management systems are not required unless you determine that they are appropriate for your solution.

---

## 10. Application Connectivity

Provide a reliable way for an application to connect to the current PostgreSQL primary.

You may use any connectivity, routing, service-discovery, or connection-management approach you consider appropriate.

Explain:

- How clients discover the current primary.
- How new connections are routed after failover.
- What happens to existing connections.
- How connection management is handled.
- What the application must do during a database failure or failover.
- What assumptions your approach makes about client behavior.

---

## 11. Application-Level Considerations

Describe how the PostgreSQL platform would interact with a high-traffic application.

Identify the application-level concerns you consider relevant to:

- Availability
- Database connectivity
- Failure handling
- Traffic growth
- Data consistency
- Query behavior
- Operational safety

Explain what responsibilities belong to the database platform and what responsibilities belong to the application.

A complete application implementation is not required.

---

## 12. Production Architecture

The submitted environment does not need to be a complete production deployment.

Document how you would evolve it for production, considering:

- Failure domains
- Infrastructure reliability
- Storage and network design
- Backup and disaster recovery
- Monitoring and incident response
- Secrets management
- Capacity planning
- Upgrades and maintenance
- Scaling
- Operational ownership and procedures

Clearly identify which parts of the submitted implementation are suitable for development or testing and which, if any, you consider production-ready.

Be explicit about what the design can and cannot guarantee.

---

## 13. Validation

Provide automated scripts or clear procedures to validate the environment.

Validation should provide confidence that:

```text
✓ The cluster is healthy
✓ The current primary can be identified
✓ Replication is functioning
✓ Client connectivity works
✓ Primary failover works
✓ Replica recovery works
✓ Operational signals are available
✓ Recovery mechanisms can be trusted
```

Determine what additional validation is necessary for your architecture.

Automate validation where practical. Clearly document any checks that require manual execution or interpretation.

---

## 14. Documentation

The repository should include documentation covering the following areas.

### Deployment

- Prerequisites
- Installation and deployment commands
- Environment access
- Validation
- Destruction and recreation

### Architecture

- Architecture diagram
- Component responsibilities
- Data flow
- Client connection flow
- Failover flow
- Design decisions and trade-offs

### Operations

- How to identify the current primary
- How to inspect replication and cluster health
- How to investigate degraded behavior
- How to recover or reintegrate failed nodes
- Common operational procedures

### Failure tests

Record failure-test results in a clear and repeatable format, for example:

```text
Failure:
Primary node terminated.

Detection time:
~X seconds.

Failover time:
~X seconds.

New primary:
postgres-2.

Data loss:
X / none under the tested conditions.

Client impact:
~X seconds.

Final cluster state:
Healthy / degraded / manual action required.
```

### Limitations and production changes

Document:

- Known limitations.
- Unhandled failure modes.
- Manual recovery requirements.
- Security assumptions.
- Changes required before production use.

---

## 15. Optional Extensions

If time permits, you may include additional capabilities that you consider valuable.

Choose optional work based on your understanding of the system’s risks, operational needs, and production priorities.

Optional additions should not come at the expense of a reliable, understandable, and well-validated core solution.

---

## Scope and Prioritization

Please aim to spend approximately **6–10 hours** on the assignment.

You are not expected to implement every possible feature or build a complete production platform within this timeframe.

Use your engineering judgment to decide:

- What is essential to implement.
- What can be documented instead.
- Which risks should be addressed first.
- Where additional complexity is justified.
- What would need to change before production use.

If something cannot reasonably be implemented, explain:

1. How you would implement it.
2. Why it matters.
3. What trade-offs it introduces.
4. Where it would fall in your production priorities.

Clearly document your assumptions, priorities, trade-offs, and known limitations. Be prepared to discuss your decisions during the technical interview.

A focused, working solution is preferable to a broad implementation that cannot be clearly explained or validated.

---

## Submission

Submit a Git repository containing:

- Infrastructure and automation code
- Required configuration and examples
- Tests or validation scripts
- Deployment and operational documentation
- Architecture diagram
- Failure-test results
- Known limitations and production considerations

The repository should be reproducible from a clean environment by following the documented instructions.

During the technical interview, be prepared to demonstrate the environment and explain your architectural and operational decisions.
