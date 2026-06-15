# Compensation

Compensation is the reverse path for already-successful steps after a later step fails or after a committed child saga is asked to roll back.

## Forward Versus Compensation Results

Step instances store two result maps:

- `result_data` for forward execution;
- `compensation_result_data` for rollback execution.

## Path

When compensation starts, the coordinator walks successful steps backward. Each step becomes a compensation candidate, receives a compensation request, and reports a compensation result.

## Outcomes

- All required compensations succeed: saga becomes `COMPENSATED`.
- A compensation step cannot proceed: saga becomes `BLOCKED`.
- State invariants are broken: saga becomes `INVALID_STATE`.

## Operator Escape Hatch

`traxctrl` can force-mark a blocked saga as compensated with an audit reason. The store rejects this operation unless the saga is currently blocked.

## Related Concepts

- [Saga State](saga-state.md): compensation changes saga terminal state.
- [Step State](step-state.md): compensation has its own candidate/running/done/blocked states.
- [Executor](executor.md): runs compensation logic.
- [Idempotent Service](idempotent-service.md): exposes compensation methods.
- [Sub-saga](sub-saga.md): committed child sagas can be asked to compensate.
- [Control Plane](control-plane.md): can force-mark blocked sagas as compensated.
