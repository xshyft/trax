# Notifications

TRAX uses PostgreSQL `LISTEN/NOTIFY` to wake coordinators quickly after state changes.

## Channels

- `trax_saga_events`: candidate step work is available.
- `trax_template_events`: templates changed and coordinator bindings may need reload.

## Rule

Notifications are wakeups, not source of truth. The coordinator responds to a notification by querying PostgreSQL.

## Fanout

The PostgreSQL store has one listener that can subscribe to multiple channels. The coordinator fans notifications out to channel-specific subscribers.

## Fallback

Template reload also has periodic polling, so a missed notification does not permanently hide a template update.

## Related Concepts

- [Coordinator](coordinator.md): subscribes to notifications through fanout.
- [PostgreSQL Store](postgresql-store.md): emits and listens for notifications.
- [Saga Step Instance](saga-step-instance.md): candidate step changes emit saga events.
- [Template Hot Reload](template-hot-reload.md): template events trigger reload.
- [Step State](step-state.md): candidate states are the notification-relevant states.
