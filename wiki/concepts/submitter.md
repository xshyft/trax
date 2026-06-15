# Submitter

A submitter is a client runtime that submits sagas into TRAX.

Code interface: `pkg/trax/submitter.go` -> `SagaSubmitter`

## Responsibilities

- announce itself to `traxcoord`;
- receive cluster IDs and node names;
- start inbox consumers for submission responses;
- publish saga submission requests;
- submit sub-sagas with hierarchy metadata;
- wait for saga completion through `traxctrl`;
- reset cached cluster state in tests.

## Readiness

A submitter is ready only after a successful announcement that returns at least one cluster ID.

## Backoff

Announcement failures trigger fast exponential retries before the submitter falls back to the normal announcement interval. This improves recovery after coordinator restarts or transient network failures.

## Submission Data

A submission includes template ID, input map, origin, origin idempotency key, trace/execution IDs, metadata, tags, and hierarchy fields for sub-sagas.

## Related Concepts

- [Coordinator](coordinator.md): submitter announces to this service.
- [Saga Instance](saga-instance.md): submitter creates saga submissions that become instances.
- [Sub-saga](sub-saga.md): submitter can submit child workflows with hierarchy metadata.
- [Idempotency](idempotency.md): origin idempotency keys and deterministic saga keys protect retries.
- [RabbitMQ Routing](rabbitmq-routing.md): submitter inbox/outbox node names are MQ resources.
