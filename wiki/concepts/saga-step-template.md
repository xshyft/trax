# Saga Step Template

A saga-step template defines one executable step inside a saga template.

Code type: `pkg/trax/types.go` -> `SagaStepTemplate`

Store table: `trax.saga_step_templates`

## Fields

- `template_id`: stable step identifier.
- `saga_template_id`: parent saga template ID.
- `display_name`: human-facing name.
- `description`: longer explanation.
- `labels`: JSON object for structured filtering.
- `tags`: JSON array for loose categorization.
- `metadata`: JSON object for executor hints. Recognized entries include
  [`step_configuration`](step-configuration.md) (a serialized JSON object carrying
  `execution_timeout_msec` / `compensation_timeout_msec`).

## Runtime Meaning

A step template maps to an executor route. Coordinators publish execution and compensation requests for a specific `(cluster, saga_template_id, saga_step_template_id)` pair.

## Queue Binding

Executor inbox queues are initialized from step templates:

```text
q_{cluster_id}_trax_executor_{saga_template_id}_{saga_step_template_id}_inbox
```

Executors bind with an affinity wildcard so any coordinator affinity can send requests to the same step executor pool.

## Related Concepts

- [Saga Template](saga-template.md): parent workflow definition.
- [Saga Step Instance](saga-step-instance.md): runtime execution record created from this template.
- [Step Configuration](step-configuration.md): per-step timeouts declared in this template's `metadata`.
- [Executor](executor.md): worker that handles this step's route.
- [RabbitMQ Routing](rabbitmq-routing.md): maps the step template to request and response routes.
- [Template Hot Reload](template-hot-reload.md): initializes executor queues for newly loaded step templates.
