# Step State

Step state is the lifecycle state of a saga-step instance.

Code enum: `pkg/trax/const.go` -> `SagaStepStateEnum`

## Forward Execution States

- `EXECUTION_PENDING`
- `EXECUTION_CANDIDATE`
- `EXECUTION_RUNNING`
- `EXECUTION_SUCCEEDED`
- `EXECUTION_DONE`
- `EXECUTION_FAILED`
- `EXECUTION_BLOCKED`
- `EXECUTION_ABORTED`

## Compensation States

- `COMPENSATION_PENDING`
- `COMPENSATION_CANDIDATE`
- `COMPENSATION_RUNNING`
- `COMPENSATION_SUCCEEDED`
- `COMPENSATION_DONE`
- `COMPENSATION_FAILED`
- `COMPENSATION_BLOCKED`

## Candidate States

Candidate states are important because PostgreSQL emits `trax_saga_events` notifications when candidate rows are created or updated. Coordinators wake up and scan for candidate work.

## Related Concepts

- [Saga Step Instance](saga-step-instance.md): stores step state.
- [Saga State](saga-state.md): saga-level validity depends on ordered step states.
- [Coordinator](coordinator.md): mutates step state.
- [Notifications](notifications.md): candidate states emit saga work notifications.
- [Execution History](execution-history.md): records attempts associated with state transitions.
