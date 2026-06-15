# Saga State

Saga state is the high-level lifecycle state of a saga instance.

Code enum: `pkg/trax/const.go` -> `SagaStateEnum`

## Active States

- `SAGA_STATE_ENUM_RUNNING`: saga is executing or compensating.
- `SAGA_STATE_ENUM_COMPENSATION_REQUESTED`: a committed child saga has been asked to compensate.

## Terminal States

- `SAGA_STATE_ENUM_COMMITTED`: all forward steps succeeded.
- `SAGA_STATE_ENUM_COMPENSATED`: compensation completed.
- `SAGA_STATE_ENUM_BLOCKED`: manual intervention is required.
- `SAGA_STATE_ENUM_INVALID_STATE`: state machine invariants were violated.

## Reserved/Not Fully Handled

- `SAGA_STATE_ENUM_PAUSED`
- `SAGA_STATE_ENUM_CANCELLED`

These exist in the enum but are not currently the main handled path.

## Related Concepts

- [Saga Instance](saga-instance.md): stores saga state.
- [Step State](step-state.md): ordered step states determine valid saga transitions.
- [Coordinator](coordinator.md): validates and mutates saga state.
- [Compensation](compensation.md): introduces compensated, blocked, and compensation-requested paths.
- [State Machine](../architecture/state-machine.md): diagram of current transitions.
