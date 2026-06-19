# Step Configuration

Per-step timeout configuration that travels with a saga step, declared once on the step **template**
and applied by the executor for every instance of that step.

Code: `pkg/trax/step_configuration.go` -> `StepConfiguration`, `ParseStepConfiguration`

## Where it lives

It is a single entry in the step template's `metadata` map (`trax.saga_step_templates.metadata`),
keyed `step_configuration`, whose value is a **serialized JSON object**:

```json
{ "execution_timeout_msec": 900000, "compensation_timeout_msec": 180000 }
```

| Field | Meaning |
|---|---|
| `execution_timeout_msec` | deadline for the forward `ExecuteSync` call |
| `compensation_timeout_msec` | deadline for the `CompensateSync` call |

Both are milliseconds. Any field that is **missing, unparseable, or non-positive** falls back to
`DefaultStepTimeoutMsec` = **180000 ms (180 s)**. So a step template with no `step_configuration`
behaves exactly as before this feature existed.

## How it reaches the executor (no database access)

The value is declared on the template, but the [executor](executor.md) never reads the database:

1. When the [coordinator](coordinator.md) creates a [saga step instance](saga-step-instance.md), the
   instance inherits the template's `metadata` (`SagaStepInstance.Metadata = SagaStepTemplate.Metadata`).
2. When the coordinator dispatches the execution / compensation request, it copies
   `SagaStepInstance.Metadata` onto the request payload (`SagaStepExecutionRequestPayload.Metadata` /
   `SagaStepCompensationRequestPayload.Metadata`).
3. The executor reads the metadata off the request it consumes, parses `step_configuration`, and
   bounds the call accordingly.

## How it is enforced

The executor wraps each call's context with the relevant deadline **per message** — execution uses
`execution_timeout_msec`, compensation uses `compensation_timeout_msec`. Because a single executor
consumer handles both paths, the timeout cannot be set once at the consumer level; it is applied per
message.

That per-message deadline sits *inside* the consumer-level MQ callback ceiling
(`DefaultExecutorCallbackTimeout`, see [Executor](executor.md)), which is only a generous safety
backstop — the real, variable deadline is `step_configuration`.

The sub-saga **detached** execution path intentionally does **not** impose the execution timeout
(those steps poll for long periods); it still receives the metadata.

## Metadata for the service implementation

The same step-instance metadata is placed on the context the executor passes to the
[IdempotentService](idempotent-service.md). An implementation can read it without any database access:

```go
md, ok := trax.StepMetadataFromContext(ctx)
```

## Related Concepts

- [Saga Step Template](saga-step-template.md): declares `metadata["step_configuration"]`.
- [Saga Step Instance](saga-step-instance.md): inherits the template metadata at creation.
- [Executor](executor.md): applies the per-step deadlines and exposes metadata to the service.
- [Idempotent Service](idempotent-service.md): may read the metadata via `StepMetadataFromContext`.
- [Compensation](compensation.md): bounded by `compensation_timeout_msec`.
