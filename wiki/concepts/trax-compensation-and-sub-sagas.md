# TRAX Compensation and Sub-sagas

TRAX can move backward through committed steps when failure requires rollback, and it can spawn
child workflows from within parent steps.

## Compensation model

- Forward outputs and compensation outputs are stored separately.
- Compensation handlers receive original input plus prior forward/rollback outputs.
- A workflow may end as compensated, blocked, or otherwise terminal depending on rollback outcome.
- Compensation is an optional behavior of the platform, not a requirement for every workflow.

## Sub-saga model

Executors can spawn child workflows using saga context metadata that preserves:

- parent saga instance id;
- parent step instance id;
- root saga instance id;
- depth;
- cluster id.

This is the current mechanism for multi-level durable workflow composition.
