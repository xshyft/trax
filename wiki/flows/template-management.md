# Template Management And Hot Reload

TRAX templates are durable workflow definitions. They are managed through `traxctrl` and consumed by `traxcoord`.

## Template Objects

A saga template defines the ordered workflow:

```json
{
  "template_id": "book_travel",
  "display_name": "Book Travel",
  "saga_step_template_ids": ["reserve_flight", "reserve_hotel", "charge_card"]
}
```

A saga-step template defines one executable step and points back to a saga template:

```json
{
  "template_id": "reserve_flight",
  "saga_template_id": "book_travel",
  "display_name": "Reserve Flight"
}
```

## CRUD Surface

`traxctrl` exposes:

- `POST /api/v1/saga-templates/list`
- `POST /api/v1/saga-templates/list/ids`
- `POST /api/v1/saga-templates/{sagaTemplateId}`
- `PUT /api/v1/saga-templates/{sagaTemplateId}`
- `DELETE /api/v1/saga-templates/{sagaTemplateId}`
- `PUT /api/v1/saga-step-templates/{sagaStepTemplateId}`
- `DELETE /api/v1/saga-step-templates/{sagaStepTemplateId}`

Testing helpers, gated by runtime configuration, include smoke-template creation.

## Coordinator Reload

The coordinator reload loop has two triggers:

- `trax_template_events` notifications for immediate reloads.
- periodic polling using `TRAX_TEMPLATE_RELOAD_INTERVAL_MS` as a fallback.

When new step templates appear, the coordinator initializes the executor inbox queue and topic binding for each cluster/template/step combination.

When a template is deleted, the coordinator unmarks initialized steps for that template so recreated templates can reinitialize cleanly.

## Current Status Versus Imported TODO

The imported `TODO_TRAX_RESILIENCE_TEMPLATE_HOTRELOAD_IDEMPOTENCY.md` described template CRUD, multi-channel LISTEN, coordinator notification fanout, MQ health checks, and submitter backoff as planned work. In the standalone repo, these are already substantially implemented:

- store interface has update/delete template methods;
- PostgreSQL store emits `trax_template_events`;
- store listener supports multiple channels;
- coordinator has notification fanout;
- coordinator reloads templates from notifications plus periodic fallback;
- `traxctrl` has saga-template and saga-step-template CRUD endpoints;
- coordinator readiness includes MQ health;
- submitter announcement has exponential backoff.

Remaining work is tracked in [Imported Backlog](../todos/imported-daemons2-backlog.md), because some verification, docs, and E2E coverage still need cleanup after extraction.
