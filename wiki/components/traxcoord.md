# traxcoord

`traxcoord` is the runtime coordinator daemon. It advances workflows by reading durable state, scheduling step execution, consuming step results, and driving compensation.

## Code Paths

- entrypoint: `cmd/traxcoord/main.go`
- daemon runtime: `pkg/daemons/traxcoord.go`, `pkg/daemons/traxcoord/run.go`
- HTTP API: `pkg/daemons/traxcoord/api/v1`
- core coordinator: `pkg/trax/coordinator.go`

## Responsibilities

- initialize store and MQ dependencies;
- listen for submitter announcements;
- return cluster IDs and submitter inbox/outbox node names;
- initialize per-cluster topic exchange and step/result queues;
- listen on PostgreSQL notification channels;
- reload templates after `trax_template_events`;
- process candidate step events after `trax_saga_events`;
- lock saga instances while mutating state;
- publish execution and compensation requests;
- consume execution and compensation results;
- transition saga and step states;
- expose testing-only database switching where enabled.

## Readiness

`IsReady` requires:

- coordinator is running;
- database circuit breaker is healthy;
- RabbitMQ connection exists and is open.

Submitters announcing to a coordinator that is not ready are rejected.

## Processing Model

The coordinator does not trust MQ as source of truth. MQ messages and DB notifications wake it up, but each processing pass re-queries PostgreSQL and validates state before mutation.

The coordinator uses a saga-instance mutex around state-changing processing. The mutex body is bounded so the lock TTL is not allowed to expire while a long operation is still mutating saga state.

## Template Reload

The coordinator reloads templates through:

- `trax_template_events` immediate notification;
- periodic fallback interval from `TRAX_TEMPLATE_RELOAD_INTERVAL_MS`.

New step templates create executor inbox bindings. Deleted templates clear initialized-step tracking.
