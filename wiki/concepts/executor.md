# Executor

An executor is a worker bound to one saga-step route.

Code interface: `pkg/trax/executor.go` -> `SagaStepExecutor`

## Responsibilities

- consume execution requests for `(cluster, saga_template, saga_step_template)`;
- call the configured `IdempotentService`;
- publish execution results;
- consume compensation requests;
- call compensation logic;
- publish compensation results;
- protect in-flight work by idempotency key.

## In-flight Guard

Executors keep in-memory maps for forward and compensation executions. If the same idempotency key is already running, a duplicate delivery returns `IN_EXECUTION` quickly instead of starting the same work twice.

## Sub-saga Executors

Executors configured with a submitter and `traxctrl` URL can spawn sub-sagas. Long-running sub-saga work can detach from the MQ callback and publish the final result later.

## Per-step Timeouts and Metadata

The executor reads the [step configuration](step-configuration.md) (`step_configuration`) off the metadata carried on each request and bounds the call accordingly:

- `ExecuteSync` is wrapped with `execution_timeout_msec` (default 180000 ms);
- `CompensateSync` is wrapped with `compensation_timeout_msec` (default 180000 ms).

These per-message deadlines are the real, variable timeouts. They sit inside a generous consumer-level MQ callback ceiling — `DefaultExecutorCallbackTimeout` (2 h, overridable with `WithExecutorCallbackTimeout`) — which is only a safety backstop so the MQ layer never cancels a legitimate long-running step mid-flight. The generic MQ callback default for other consumers is 180 s.

The executor also attaches the step-instance metadata to the context it passes to the service, so the [Idempotent Service](idempotent-service.md) can read it via `StepMetadataFromContext(ctx)` without a database round-trip. The detached sub-saga path receives the metadata but is **not** bounded by the execution timeout.

## Related Concepts

- [Saga Step Template](saga-step-template.md): executor binds to one step template route.
- [Saga Step Instance](saga-step-instance.md): executor receives requests for concrete step instances.
- [Step Configuration](step-configuration.md): per-step execution/compensation timeouts the executor applies.
- [Idempotent Service](idempotent-service.md): executor delegates actual work to this contract.
- [RabbitMQ Routing](rabbitmq-routing.md): executor consumes request routes and publishes response routes.
- [Sub-saga](sub-saga.md): some executors can spawn child sagas.
- [Compensation](compensation.md): executor may run rollback logic.
