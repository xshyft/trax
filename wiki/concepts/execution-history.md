# Execution History

Execution history records attempts made against a saga-step instance.

Code type: `pkg/trax/types.go` -> `SagaStepExecutionLog`

Stored field: `SagaStepInstance.ExecutionHistory`

## Fields

- `next_execution_ts`
- `execution_request_sent_ts`
- `execution_timeout_ts`
- `execution_result_received_ts`
- `log_conclusion_ts`
- `execution_result`
- `execution_error`
- `is_compensation`
- `metadata`

## Purpose

Execution history gives operators and tests a structured view of what happened to a step: when it was scheduled, whether it timed out, what result came back, and whether the attempt was forward execution or compensation.

## Related Concepts

- [Saga Step Instance](saga-step-instance.md): owns execution history.
- [Executor](executor.md): produces execution and compensation results.
- [Coordinator](coordinator.md): records result timestamps and conclusions.
- [Step State](step-state.md): history explains how a step reached its current state.
- [Compensation](compensation.md): compensation attempts are marked with `is_compensation`.
