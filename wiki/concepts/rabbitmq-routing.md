# RabbitMQ Routing

RabbitMQ is the TRAX transport for saga submissions, step requests, and step responses.

## Step Exchange

Each cluster has a topic exchange:

```text
x_{cluster_id}_trax_saga_steps
```

## Request Route

```text
{cluster_id}.{affinity}.{saga_template_id}.{saga_step_template_id}.request
```

## Response Route

```text
{cluster_id}.{affinity}.{saga_template_id}.{saga_step_template_id}.response
```

## Executor Queue

```text
q_{cluster_id}_trax_executor_{saga_template_id}_{saga_step_template_id}_inbox
```

Executor binding:

```text
{cluster_id}.*.{saga_template_id}.{saga_step_template_id}.request
```

## Coordinator Result Queue

```text
q_{cluster_id}_trax_coordinator_{affinity}_results
```

Coordinator binding:

```text
{cluster_id}.{affinity}.*.*.response
```

## Authority Rule

RabbitMQ delivery is not authority. PostgreSQL state is authority. Coordinators always re-check store state before advancing workflows.

## Related Concepts

- [Cluster](cluster.md): exchange and queue names are cluster-scoped.
- [Affinity](affinity.md): routing keys carry coordinator affinity.
- [Coordinator](coordinator.md): publishes requests and consumes result queues.
- [Executor](executor.md): consumes request queues and publishes responses.
- [Submitter](submitter.md): announcement creates submitter inbox/outbox node names.
