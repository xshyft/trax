# Idempotency

Idempotency is central to TRAX because messages can be retried, services can restart, and callers can submit the same logical operation more than once.

## Durable Idempotency

PostgreSQL enforces unique keys for saga and step instances:

```text
sidk:{cluster_id}.{zone_id}.{saga_template_id}.{saga_instance_id}
ssidk:{cluster_id}.{zone_id}.{saga_template_id}.{saga_step_template_id}.{saga_instance_id}
```

Store methods named `Save*Idempotently` use those keys to make repeated creation safe.

## Executor Idempotency

Executors receive the step idempotency key. The `IdempotentService` implementation is responsible for using it when calling downstream systems.

## Source-system Lessons

Imported docs include `TODO_EXECUTION_IDEMPOTENCY_SEED.md`, `TODO_IDEMPOTENT_TREASURY_VAULT_OPERATIONS.md`, and `TREASURY_IDEMPOTENCY.md`. Those are domain-heavy, but they capture an important TRAX rule: deterministic operation identity must enter at the boundary and flow into every side-effecting step.

## Related Concepts

- [Saga Instance](saga-instance.md): has a unique saga idempotency key.
- [Saga Step Instance](saga-step-instance.md): has a unique step idempotency key.
- [Idempotent Service](idempotent-service.md): must use keys for downstream side effects.
- [Executor](executor.md): has in-flight guards keyed by idempotency key.
- [PostgreSQL Store](postgresql-store.md): enforces uniqueness at the durable layer.
