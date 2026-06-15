# PostgreSQL Data Model

TRAX stores all durable state in the `trax` schema. The schema has two layers: global control tables and cluster-scoped runtime tables.

## Global Tables

### `trax.clusters`

Execution namespace registry.

Key fields:

- `id`: cluster ID and primary key
- `display_name`, `description`
- `labels`, `tags`, `metadata` as JSONB
- `created_at`, `updated_at`

### `trax.saga_templates`

Workflow definitions.

Key fields:

- `template_id`: primary key
- `display_name`, `description`
- `labels`, `tags`, `metadata` as JSONB
- `saga_step_template_ids`: ordered JSONB array of step template IDs
- `created_at`, `updated_at`

### `trax.saga_step_templates`

Step definitions.

Key fields:

- `template_id`: primary key
- `saga_template_id`: FK to `trax.saga_templates(template_id)`
- `display_name`, `description`
- `labels`, `tags`, `metadata` as JSONB
- `created_at`, `updated_at`

Template insert/update/delete operations notify `trax_template_events` so coordinators can reload bindings.

## Cluster-scoped Tables

Cluster IDs are transformed into table-safe names by replacing hyphens with underscores.

### `trax.{cluster}_saga_instances`

One row per saga execution.

Important fields:

- `instance_id`: primary key
- `saga_idempotency_key`: unique key produced from cluster, zone, saga template, and instance ID
- `cluster_id`, `zone_id`
- `trace_id`, `execution_id`
- `saga_submitter_id`
- `origin`, `origin_idempotency_key`
- `labels`, `tags`, `metadata`
- `state`
- `saga_template_id`
- `input_data`: JSONB map of saga inputs
- `saga_instance_ids`: JSONB child list/history field
- `parent_saga_instance_id`
- `parent_saga_step_instance_id`
- `root_saga_instance_id`
- `saga_depth`
- `compensation_reason`
- `annex_iids`: JSONB array of attached annex IDs
- `created_at`, `updated_at`

Indexes include state, idempotency key, parent, and root lookup paths.

### `trax.{cluster}_saga_step_instances`

One row per step execution record.

Important fields:

- `instance_id`: primary key
- `saga_idempotency_key`: unique step idempotency key
- `cluster_id`, `zone_id`
- `saga_instance_id`
- `trace_id`, `execution_id`
- `labels`, `tags`, `metadata`
- `affinity`
- `state`
- `result_data`
- `compensation_result_data`
- `saga_template_id`
- `saga_step_template_id`
- `previous_saga_step_instance_id`
- `next_saga_step_instance_id`
- `execution_history`: JSONB array of execution/compensation attempts
- `created_at`, `updated_at`

Indexes include affinity/state, saga instance, template, and idempotency key.

### `trax.{cluster}_saga_annexes`

Binary attachments owned by a saga instance.

Important fields:

- `iid`: annex ID
- `cluster_id`
- `saga_instance_id`
- `content_type`
- `content_length`
- `notes`
- `content_data`
- `created_at`, `updated_at`

Annex metadata is listed separately from byte retrieval. `traxctrl` exposes create/list/get APIs.

## Idempotency Keys

Saga key format:

```text
sidk:{cluster_id}.{zone_id}.{saga_template_id}.{saga_instance_id}
```

Step key format:

```text
ssidk:{cluster_id}.{zone_id}.{saga_template_id}.{saga_step_template_id}.{saga_instance_id}
```

The DB enforces uniqueness for saga and step idempotency keys. Store methods named `Save*Idempotently` use these constraints to make repeated creation safe.

## Notifications

`store_psql.go` emits:

- `trax_template_events` after template insert/update/delete
- `trax_saga_events` after step rows become `EXECUTION_CANDIDATE` or `COMPENSATION_CANDIDATE`

Notifications are wakeups only. The coordinator always re-reads state from PostgreSQL before processing.
