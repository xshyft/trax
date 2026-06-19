# Idempotent Service

`IdempotentService` is the executor-side contract for doing real step work safely.

Code type: `pkg/trax/idempotent_service.go` -> `IdempotentService`

## Methods

- `ExecuteSync(ctx, idempotencyKey, input)`
- `ExecuteAsync(ctx, idempotencyKey, input, callback)`
- `CompensateSync(ctx, idempotencyKey, input)`
- `CompensateAsync(ctx, idempotencyKey, input, callback)`

## Context

The `ctx` the executor passes in is already bounded by the step's
[execution / compensation timeout](step-configuration.md), so a slow implementation is cancelled at
the configured deadline. The same context also carries the step-instance metadata — read it with
`trax.StepMetadataFromContext(ctx)` (no database access required).

## Result

`IdempotentServiceExecutionResult` returns:

- result map;
- optional error.

The executor converts this into TRAX execution result status and publishes it back to the coordinator.

## Responsibility Split

TRAX guarantees durable workflow state and passes deterministic idempotency keys. The service implementation must use those keys to protect downstream side effects such as external APIs, ledgers, databases, or model jobs.

## Related Concepts

- [Executor](executor.md): invokes the idempotent service.
- [Idempotency](idempotency.md): provides the key discipline this service must honor.
- [Compensation](compensation.md): service exposes compensation methods.
- [Sub-saga](sub-saga.md): service implementations can use saga context to spawn child workflows.
- [Execution History](execution-history.md): service results are recorded into step execution history.
