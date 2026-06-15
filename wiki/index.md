# TRAX Wiki Index

TRAX is a standalone distributed workflow and saga orchestration system extracted from `daemons2`. This wiki is the source of truth for the current standalone repo: what the code does now, which imported source docs matter, and what remains to clean up.

## Start Here

- [Architecture v1](architecture/v1.md): current runtime architecture, boundaries, actors, routing, and extraction gaps.
- [TRAX Saga System](concepts/trax-saga-system.md): core concepts and ownership boundary.
- [Saga Lifecycle](flows/saga-lifecycle.md): forward execution, compensation, states, and executor contract.
- [PostgreSQL Data Model](data-model/postgresql.md): durable tables, generated cluster tables, idempotency keys, and notifications.

## Concepts

- [Concepts Index](concepts/index.md)
- [Saga Template](concepts/saga-template.md)
- [Saga Step Template](concepts/saga-step-template.md)
- [Saga Instance](concepts/saga-instance.md)
- [Saga Step Instance](concepts/saga-step-instance.md)
- [Cluster](concepts/cluster.md)
- [Coordinator](concepts/coordinator.md)
- [Submitter](concepts/submitter.md)
- [Executor](concepts/executor.md)
- [Idempotency](concepts/idempotency.md)
- [Compensation](concepts/compensation.md)
- [Sub-saga](concepts/sub-saga.md)
- [TRAX Saga System](concepts/trax-saga-system.md)
- [TRAX MQ and Coordination](concepts/trax-mq-and-coordination.md)
- [TRAX Compensation and Sub-sagas](concepts/trax-compensation-and-sub-sagas.md)

## Flows

- [Saga Lifecycle](flows/saga-lifecycle.md)
- [Template Management and Hot Reload](flows/template-management.md)
- [Sub-sagas and Hierarchy](flows/sub-sagas.md)

## Architecture And Data

- [Architecture v1](architecture/v1.md)
- [Code Map](code/repo-map.md)
- [Startup Paths](code/startup-paths.md)
- [Coordinator Algorithms](architecture/coordinator-algorithms.md)
- [State Machine](architecture/state-machine.md)
- [Executor And CLI Runtime](architecture/executor-and-cli.md)
- [PostgreSQL Data Model](data-model/postgresql.md)
- [Testing and E2E](architecture/testing-and-e2e.md)

## Components

- [traxctrl](components/traxctrl.md)
- [traxcoord](components/traxcoord.md)
- [traxcli](components/traxcli.md)

## Operations

- [Configuration](operations/configuration.md)
- [Local Run](operations/local-run.md)
- [Make Targets](operations/make-targets.md)
- [Deployment Notes](operations/deployment.md)
- [Testing and E2E Operations](operations/testing.md)

## Reference

- [API Surface](reference/api-surface.md)
- [Current Gaps And Mismatches](reference/current-gaps.md)
- [Extracted Source Knowledge](reference/imported-daemons2-docs.md)
- [Source Repo History Docs](source/daemons2/index.md)
- [Glossary](glossary.md)

## TODOs

- [TRAX Resilience TODO](todos/trax-resilience.md)
- [Imported Source Backlog](todos/imported-daemons2-backlog.md)

## Current Direction

- PostgreSQL is the source of truth; RabbitMQ is the transport.
- `traxcoord` advances workflows; `traxctrl` is the read/control plane.
- Domain-specific saga templates and executors should live in dependent systems long term.
- Imported `daemons2` docs are preserved for historical and migration context.
- The wiki should be updated whenever code, runtime behavior, or architecture changes.
