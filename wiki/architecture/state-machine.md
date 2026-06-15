# State Machine

This page summarizes the state machine implemented in `pkg/trax/coordinator.go` and enums in `pkg/trax/const.go`.

## Saga States

```mermaid
stateDiagram-v2
    [*] --> RUNNING
    RUNNING --> COMMITTED: all forward steps done
    RUNNING --> COMPENSATED: rollback done
    RUNNING --> BLOCKED: execution or compensation cannot proceed
    RUNNING --> INVALID_STATE: invariant violation
    COMMITTED --> COMPENSATION_REQUESTED: parent requests child rollback
    COMPENSATION_REQUESTED --> COMPENSATED: rollback done
    COMPENSATION_REQUESTED --> BLOCKED: rollback blocked
```

Current enum values also include `PAUSED` and `CANCELLED`, but those are not the active mainline behavior.

## Forward Step States

```mermaid
stateDiagram-v2
    [*] --> EXECUTION_PENDING
    EXECUTION_PENDING --> EXECUTION_CANDIDATE: predecessor done
    EXECUTION_CANDIDATE --> EXECUTION_RUNNING: coordinator publishes request
    EXECUTION_RUNNING --> EXECUTION_SUCCEEDED: executor success
    EXECUTION_SUCCEEDED --> EXECUTION_DONE: coordinator finalizes step
    EXECUTION_RUNNING --> EXECUTION_FAILED: executor failure
    EXECUTION_RUNNING --> EXECUTION_BLOCKED: cannot proceed
    EXECUTION_RUNNING --> EXECUTION_ABORTED: aborted path
```

## Compensation Step States

```mermaid
stateDiagram-v2
    [*] --> COMPENSATION_PENDING
    COMPENSATION_PENDING --> COMPENSATION_CANDIDATE
    COMPENSATION_CANDIDATE --> COMPENSATION_RUNNING
    COMPENSATION_RUNNING --> COMPENSATION_SUCCEEDED
    COMPENSATION_SUCCEEDED --> COMPENSATION_DONE
    COMPENSATION_RUNNING --> COMPENSATION_FAILED
    COMPENSATION_RUNNING --> COMPENSATION_BLOCKED
```

## Validation

`isSagaStateValid`, `validateNonCompensatingMode`, and `validateCompensatingMode` are the key invariant checks. If the current combination of saga state and ordered step states is impossible, the coordinator can mark the saga invalid.

## Notifications

Candidate state transitions emit `trax_saga_events`, waking coordinators to process the next step.
