# TRAX Compensation and Sub-sagas

TRAX supports rollback-style compensation and nested workflows.

## Compensation

When a forward step fails after earlier steps succeeded, the coordinator can walk backward through completed steps and schedule compensation requests.

Step state stores forward result and compensation result separately:

- `result_data`
- `compensation_result_data`

A compensation path can finish as:

- `SAGA_STATE_ENUM_COMPENSATED` when rollback completes;
- `SAGA_STATE_ENUM_BLOCKED` when manual intervention is needed;
- `SAGA_STATE_ENUM_INVALID_STATE` when the state machine detects an impossible condition.

`traxctrl` provides a force-compensated override for blocked sagas only.

## Sub-sagas

An executor can spawn a child saga through saga context. The child stores:

- parent saga instance ID;
- parent saga step instance ID;
- root saga instance ID;
- saga depth.

Sub-saga-enabled executors can detach long-running execution from the MQ callback and publish the final result later.

## Why This Matters

The imported `daemons2` domain workflows include deep multi-step and nested saga designs. TRAX must preserve those mechanics while keeping the domain-specific templates and executors outside TRAX core long term.

## See Also

- [Sub-sagas and Hierarchy](../flows/sub-sagas.md)
- [Saga Lifecycle](../flows/saga-lifecycle.md)
- [Imported daemons2 Docs](../reference/imported-daemons2-docs.md)

## Related Concepts

- [Compensation](compensation.md): detailed rollback concept.
- [Sub-saga](sub-saga.md): detailed child workflow concept.
- [Saga State](saga-state.md): saga-level compensation and blocked states.
- [Step State](step-state.md): compensation step lifecycle.
- [Executor](executor.md): runs compensation and sub-saga work.
- [Control Plane](control-plane.md): exposes force-compensated operator action.
