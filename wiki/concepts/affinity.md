# Affinity

Affinity identifies a coordinator group for routing responses and partitioning step processing.

## Why It Exists

Multiple `traxcoord` instances may run for the same cluster. Affinity lets a coordinator publish requests and receive only the responses intended for its group.

## Routing Shape

```text
{cluster_id}.{affinity}.{saga_template_id}.{saga_step_template_id}.request
{cluster_id}.{affinity}.{saga_template_id}.{saga_step_template_id}.response
```

Executor bindings wildcard affinity for requests:

```text
{cluster_id}.*.{saga_template_id}.{saga_step_template_id}.request
```

Coordinator result bindings pin affinity:

```text
{cluster_id}.{affinity}.*.*.response
```

## Stored State

Saga-step instances carry `affinity`, so the coordinator can query candidate work by cluster, affinity, saga state, and step state.

## Related Concepts

- [Cluster](cluster.md): affinity is meaningful inside a cluster.
- [Coordinator](coordinator.md): each coordinator runs with one affinity group.
- [RabbitMQ Routing](rabbitmq-routing.md): affinity appears in request and response routing keys.
- [Saga Step Instance](saga-step-instance.md): stores affinity for candidate processing.
