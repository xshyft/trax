# Sub-saga

A sub-saga is a child workflow spawned from inside a parent saga step.

## Stored Hierarchy

Child sagas store:

- `parent_saga_instance_id`
- `parent_saga_step_instance_id`
- `root_saga_instance_id`
- `saga_depth`

## Runtime API

`SagaContext` exposes `SpawnSubSaga`, which submits a child saga and waits for terminal state through `traxctrl` polling.

## Why It Exists

Sub-sagas let complex workflows compose smaller workflows while preserving independent durability and operator visibility.

## Querying

`traxctrl` exposes children and tree endpoints for hierarchy inspection.

## Related Concepts

- [Saga Instance](saga-instance.md): parent/root/depth fields define hierarchy.
- [Saga Step Instance](saga-step-instance.md): parent step can spawn a child saga.
- [Executor](executor.md): sub-saga-capable executors create child workflows.
- [Submitter](submitter.md): submits child sagas through `SubmitSubSaga`.
- [Compensation](compensation.md): child workflows can be compensated independently.
