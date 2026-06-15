# Saga Instance

A saga instance is one runtime execution of a saga template.

Code type: `pkg/trax/types.go` -> `SagaInstance`

Store table: `trax.{cluster}_saga_instances`

## Identity Fields

- `instance_id`: runtime saga ID.
- `cluster_id`: execution namespace.
- `zone_id`: logical zone.
- `trace_id`: trace shared by the saga and its steps.
- `execution_id`: execution ID for the saga creation/submission.
- `saga_template_id`: template being executed.
- `saga_submitter_id`: submitter that created it.

## Origin And Idempotency

- `origin`: source service or logical origin.
- `origin_idempotency_key`: caller/source idempotency key.
- `saga_idempotency_key`: generated and stored uniquely by PostgreSQL.

The generated saga idempotency key format is:

```text
sidk:{cluster_id}.{zone_id}.{saga_template_id}.{saga_instance_id}
```

## Runtime Data

- `input_data`: saga input map.
- `labels`, `tags`, `metadata`: structured metadata.
- `state`: current saga state.
- `compensation_reason`: reason for compensation or force-compensated override.
- `annex_iids`: attached binary content IDs.

## Hierarchy Fields

- `parent_saga_instance_id`
- `parent_saga_step_instance_id`
- `root_saga_instance_id`
- `saga_depth`

These support sub-sagas and tree queries.

## Related Concepts

- [Saga Template](saga-template.md): definition this instance executes.
- [Saga Step Instance](saga-step-instance.md): concrete ordered steps belonging to this instance.
- [Saga State](saga-state.md): lifecycle state stored on the instance.
- [Sub-saga](sub-saga.md): hierarchy fields connect parent and child saga instances.
- [Saga Annex](saga-annex.md): binary attachments owned by this instance.
- [Idempotency](idempotency.md): uniqueness and retry behavior for instance creation.
