# PostgreSQL Store

The PostgreSQL store is the durable state backend for TRAX.

Code interface: `pkg/trax/store.go` -> `Store`

Implementation: `pkg/trax/store_psql.go`

## Responsibilities

- initialize tables;
- health checks;
- transaction boundaries;
- cluster CRUD;
- template CRUD;
- saga instance persistence and state updates;
- step instance persistence, state updates, results, and execution history;
- hierarchy queries;
- annex storage;
- `LISTEN/NOTIFY` integration.

## Global Tables

- `trax.clusters`
- `trax.saga_templates`
- `trax.saga_step_templates`

## Cluster Tables

- `trax.{cluster}_saga_instances`
- `trax.{cluster}_saga_step_instances`
- `trax.{cluster}_saga_annexes`

## See Also

- [PostgreSQL Data Model](../data-model/postgresql.md)

## Related Concepts

- [PostgreSQL Data Model](../data-model/postgresql.md): exact table model.
- [Saga Template](saga-template.md): stored globally.
- [Cluster](cluster.md): drives cluster-specific runtime tables.
- [Notifications](notifications.md): store emits PostgreSQL notifications.
- [Idempotency](idempotency.md): store enforces unique keys.
- [Saga Annex](saga-annex.md): binary attachments are store-owned.
