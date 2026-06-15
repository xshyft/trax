# TRAX MQ and Coordination

TRAX coordinates workflows through PostgreSQL state plus RabbitMQ delivery.

## Coordination Principles

- PostgreSQL is authoritative.
- RabbitMQ carries requests and responses.
- PostgreSQL `LISTEN/NOTIFY` wakes coordinators when new work or template changes exist.
- Coordinators validate state from the store before each mutation.
- Duplicate messages must not create duplicate durable rows or duplicate concurrent step execution.

## RabbitMQ Shape

TRAX uses per-cluster topic exchanges for step traffic:

```text
x_{cluster_id}_trax_saga_steps
```

Request routing key:

```text
{cluster_id}.{affinity}.{saga_template_id}.{saga_step_template_id}.request
```

Response routing key:

```text
{cluster_id}.{affinity}.{saga_template_id}.{saga_step_template_id}.response
```

Executor queue:

```text
q_{cluster_id}_trax_executor_{saga_template_id}_{saga_step_template_id}_inbox
```

Coordinator result queue:

```text
q_{cluster_id}_trax_coordinator_{affinity}_results
```

## Submitter Announcement

Submitters announce to `traxcoord` over HTTP. On success, they receive cluster IDs and inbox/outbox node names. The submitter marks itself ready only when cluster IDs exist.

The submitter has fast exponential backoff after announcement failures to recover quickly from coordinator restarts.

## Coordinator Health

Coordinator readiness requires:

- running flag;
- healthy DB circuit breaker;
- open RabbitMQ connection.

This prevents accepting submitters when the coordinator cannot actually process messages.

## See Also

- [Architecture v1](../architecture/v1.md)
- [traxcoord](../components/traxcoord.md)
- [Deployment Notes](../operations/deployment.md)

## Related Concepts

- [RabbitMQ Routing](rabbitmq-routing.md): concrete exchange, queue, and routing-key model.
- [Coordinator](coordinator.md): owns coordination and result processing.
- [Submitter](submitter.md): announces to the coordinator and publishes submissions.
- [Executor](executor.md): consumes requests and publishes responses.
- [Notifications](notifications.md): PostgreSQL wakeups that complement MQ transport.
- [Affinity](affinity.md): partitions coordinator response routing.
