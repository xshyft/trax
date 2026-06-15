# Cluster

A cluster is a TRAX execution namespace.

Code type: `pkg/trax/types.go` -> `Cluster`

Store table: `trax.clusters`

## Responsibilities

A cluster scopes:

- runtime instance tables;
- RabbitMQ topic exchange names;
- coordinator loops;
- submitter cluster membership;
- executor queue names;
- API queries for saga and step instances.

## Table Naming

Cluster IDs are transformed into table-safe names by replacing hyphens with underscores:

```text
trax.{cluster}_saga_instances
trax.{cluster}_saga_step_instances
trax.{cluster}_saga_annexes
```

## Routing Naming

The per-cluster step exchange is:

```text
x_{cluster_id}_trax_saga_steps
```

## Current Open Design Note

Some inherited code has TODO comments around mapping participants or domains to clusters. That is a dependent-system design decision; TRAX itself treats clusters as opaque execution namespaces.

## Related Concepts

- [Coordinator](coordinator.md): starts processing loops per cluster.
- [Submitter](submitter.md): receives cluster IDs after announcement.
- [RabbitMQ Routing](rabbitmq-routing.md): every exchange and queue name is cluster-scoped.
- [PostgreSQL Store](postgresql-store.md): creates cluster-specific instance and annex tables.
- [Affinity](affinity.md): partitions coordinator handling inside a cluster.
