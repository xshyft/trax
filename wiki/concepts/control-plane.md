# Control Plane

The control plane is the administrative/read side of TRAX, implemented by `traxctrl`.

## Responsibilities

- cluster CRUD;
- template CRUD;
- step-template CRUD;
- saga instance queries;
- saga-step instance queries;
- hierarchy and tree queries;
- annex storage access;
- force-compensated operator override;
- testing-only helpers when explicitly enabled.

## Rule

The control plane should expose durable state and explicit operator actions. It should not silently mutate workflow state outside documented operations.

## Related Concepts

- [Coordinator](coordinator.md): control plane observes and administers coordinator-owned state.
- [Saga Instance](saga-instance.md): main queried runtime object.
- [Saga Step Instance](saga-step-instance.md): queried for execution detail.
- [Saga Annex](saga-annex.md): managed through control plane endpoints.
- [Compensation](compensation.md): force-compensated override belongs to the control plane.
- [API Surface](../reference/api-surface.md): endpoint list.
