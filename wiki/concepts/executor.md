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

## Related Concepts

- [Saga Step Template](saga-step-template.md): executor binds to one step template route.
- [Saga Step Instance](saga-step-instance.md): executor receives requests for concrete step instances.
- [Idempotent Service](idempotent-service.md): executor delegates actual work to this contract.
- [RabbitMQ Routing](rabbitmq-routing.md): executor consumes request routes and publishes response routes.
- [Sub-saga](sub-saga.md): some executors can spawn child sagas.
- [Compensation](compensation.md): executor may run rollback logic.
