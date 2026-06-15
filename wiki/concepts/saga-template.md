# Saga Template

A saga template is the durable definition of a workflow.

Code type: `pkg/trax/types.go` -> `SagaTemplate`

Store table: `trax.saga_templates`

## Fields

- `template_id`: stable workflow identifier.
- `display_name`: human-facing name.
- `description`: longer explanation.
- `labels`: JSON object for structured filtering.
- `tags`: JSON array for loose categorization.
- `metadata`: JSON object for extra workflow metadata.
- `saga_step_template_ids`: ordered list of step template IDs.

## Runtime Meaning

The ordered `saga_step_template_ids` list defines the forward execution order. When a saga instance is submitted, the coordinator expands this list into concrete saga-step instances.

## Current API Surface

Managed through `traxctrl`:

- list IDs
- list templates
- get by ID
- update
- delete

Template changes emit `trax_template_events` so coordinators can reload queue bindings.

## Boundary

TRAX owns the template mechanism. Domain systems should own the domain-specific templates long term.

## Related Concepts

- [Saga Step Template](saga-step-template.md): ordered children of the saga template.
- [Saga Instance](saga-instance.md): runtime execution created from a saga template.
- [Template Hot Reload](template-hot-reload.md): how changes become visible to coordinators.
- [Coordinator](coordinator.md): expands templates into runtime instances.
- [PostgreSQL Store](postgresql-store.md): persists templates and emits template notifications.
