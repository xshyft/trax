# TRAX Wiki Index

TRAX is a standalone distributed workflow and saga orchestration system. This wiki tracks the
current extracted state of the repo and the intended stable architecture for other systems that
will depend on it.

## Current direction

- TRAX owns generic multi-step workflow execution, durable saga state, coordinator/control APIs,
  and executor/submitter tooling.
- Domain-specific saga templates and executors should live in dependent systems, not inside TRAX
  long term.
- RabbitMQ is the execution transport; PostgreSQL is the durable store.
- `traxctrl` is the read/control surface; `traxcoord` advances workflows.
- The current standalone repo is extracted from `daemons2`, so some shared utility packages still
  carry legacy breadth that should be narrowed over time.

## Concepts
- [TRAX Saga System](concepts/trax-saga-system.md) — the core model: templates, instances, steps, coordinators, executors, and submitters.
- [TRAX MQ and Coordination](concepts/trax-mq-and-coordination.md) — RabbitMQ topology, coordinator behavior, and runtime flow.
- [TRAX Compensation and Sub-sagas](concepts/trax-compensation-and-sub-sagas.md) — rollback behavior, child workflows, and hierarchy.

## Architecture
- [Architecture v1](architecture/v1.md) — the current standalone TRAX architecture and extraction baseline.
- [Testing and E2E](architecture/testing-and-e2e.md) — unit, integration, and compose-backed E2E test surfaces.

## Components
- [traxctrl](components/traxctrl.md) — control/read API service.
- [traxcoord](components/traxcoord.md) — workflow coordinator daemon.
- [traxcli](components/traxcli.md) — operator, executor, template, and submitter CLI.

## TODOs
- [TRAX Resilience TODO](todos/trax-resilience.md) — extracted resilience, hot-reload, and idempotency backlog.

## Meta
- [README](README.md) — wiki conventions.
- [Glossary](glossary.md) — quick definitions.
