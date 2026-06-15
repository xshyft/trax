# Saga Annex

A saga annex is binary content attached to a saga instance and owned by TRAX.

Code type: `pkg/trax/types.go` -> `SagaAnnex`

Store table: `trax.{cluster}_saga_annexes`

## Fields

- `iid`: annex ID.
- `cluster_id`
- `saga_instance_id`
- `content_type`
- `content_length`
- `notes`
- `content_data`
- `created_at`, `updated_at`

## API

`traxctrl` exposes annex create/list/get endpoints under saga instances.

## Purpose

Gateways can attach original payloads or binary artifacts to a saga so operators and downstream readers can inspect them through TRAX instead of chasing service-local storage.

## Related Concepts

- [Saga Instance](saga-instance.md): annexes are attached to saga instances.
- [PostgreSQL Store](postgresql-store.md): stores annex metadata and bytes.
- [Control Plane](control-plane.md): exposes annex create/list/get APIs.
- [API Surface](../reference/api-surface.md): lists annex endpoints.
