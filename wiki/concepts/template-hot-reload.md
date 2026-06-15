# Template Hot Reload

Template hot reload lets coordinators discover new or changed templates without restarting.

## Triggers

- `trax_template_events` notification after template insert/update/delete.
- periodic fallback reload interval.

## Coordinator Behavior

On reload, the coordinator lists clusters and saga templates, then initializes missing executor inbox bindings for each step.

Deleted templates clear initialized-step tracking so recreated templates can initialize again.

## Why It Matters

TRAX templates are runtime configuration. Without hot reload, operators would need to restart coordinators for template changes, which is too brittle for live workflow systems.

## Related Concepts

- [Saga Template](saga-template.md): reload discovers template changes.
- [Saga Step Template](saga-step-template.md): reload initializes step bindings.
- [Coordinator](coordinator.md): performs reload and tracks initialized steps.
- [Notifications](notifications.md): `trax_template_events` wakes reload loop.
- [RabbitMQ Routing](rabbitmq-routing.md): reload creates executor inbox bindings.
