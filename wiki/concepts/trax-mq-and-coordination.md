# TRAX MQ and Coordination

TRAX coordinates workflows through persisted PostgreSQL state plus RabbitMQ transport.

## Runtime actors

- **Coordinator** — validates submissions, persists instance state, publishes runnable steps, consumes results, and advances state.
- **Executor** — binds to one saga-step request route and performs work.
- **Submitter** — announces to a coordinator and submits new workflow instances.
- **Store** — durable persistence for clusters, templates, workflow state, and notifications.

## Topic shape

Routing keys follow the shape:

```text
{cluster}.{affinity}.{saga}.{step}.{request|response}
```

Executors bind to request routes for a target saga-step pair. Coordinators bind to response routes
for their own affinity group.

## Current runtime notes

- PostgreSQL is the source of truth.
- RabbitMQ is the transport, not the authority.
- Coordinators use readiness checks that should cover both database and MQ health.
- The extracted standalone repo now uses a TRAX-only `pkg/mq/init.go` rather than the broader
  `daemons2` MQ system.
