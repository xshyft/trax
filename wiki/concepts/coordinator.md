# Coordinator

The coordinator is the runtime actor implemented by `traxcoord` and `pkg/trax/coordinator.go`.

## Responsibilities

- accept submitter announcements;
- list available clusters;
- initialize RabbitMQ step topology;
- listen on `trax_saga_events` and `trax_template_events`;
- create saga and step instances from submitted templates;
- transition saga and step state;
- publish execution and compensation requests;
- consume execution and compensation results;
- drive compensation;
- detect invalid state transitions;
- expose readiness.

## Readiness

A coordinator is ready only when:

- it is running;
- database health circuit is healthy;
- RabbitMQ connection is alive.

## Processing Guard

The coordinator uses a mutex around saga-instance processing. The mutex prevents two workers from mutating the same saga at the same time. The mutex body is time-bounded so the lock TTL does not expire while processing is still active.

## Related Concepts

- [Submitter](submitter.md): announces to the coordinator and publishes saga submissions.
- [Executor](executor.md): receives coordinator requests and sends results back.
- [Saga Instance](saga-instance.md): coordinator owns runtime state transitions.
- [Saga Step Instance](saga-step-instance.md): coordinator schedules and updates step instances.
- [Notifications](notifications.md): wake the coordinator for saga work and template changes.
- [Compensation](compensation.md): coordinator drives rollback paths.
- [Affinity](affinity.md): coordinator response routing is affinity-scoped.
