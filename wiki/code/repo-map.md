# Code Map

This page maps the current repository layout to runtime responsibility. It is meant to answer: "where is the thing that does X?"

## Entrypoints

- `cmd/traxcoord/main.go`: binary entrypoint for the coordinator daemon. Calls `daemons.RunTraxCoordinator()`.
- `cmd/traxctrl/main.go`: binary entrypoint for the control daemon. Parses `--in-memory-store`, then calls `daemons.RunTraxCtrl(...)`.
- `cmd/traxcli/main.go`: binary entrypoint for the CLI. Calls the local Cobra command package `cmd/traxcli/cmd`.

## Core Runtime

- `pkg/trax/coordinator.go`: main coordinator state machine, readiness, template reload, notification fanout, step processing, result processing, compensation, and state transitions.
- `pkg/trax/submitter.go`: submitter announcement, readiness, saga submission, sub-saga submission, and wait-for-completion polling.
- `pkg/trax/executor.go`: executor runtime, request consumption, idempotent service invocation, in-flight guard, sub-saga detached execution, and result publishing.
- `pkg/trax/sub_saga_executor.go`: helper for spawning child sagas and polling terminal status.
- `pkg/trax/saga_context.go`: context object passed into idempotent services that need to spawn sub-sagas.
- `pkg/trax/store.go`: storage interface contract.
- `pkg/trax/store_psql.go`: PostgreSQL implementation, table initialization, transactions, CRUD, state updates, LISTEN/NOTIFY, and annex storage.
- `pkg/trax/store_inmem.go`: in-memory store implementation.
- `pkg/trax/types.go`: core data structs.
- `pkg/trax/const.go`: saga, step, and execution result enums.
- `pkg/trax/common.go`: idempotency key and MQ naming helpers.
- `pkg/trax/mq.go`: MQ client interface and RabbitMQ implementation.
- `pkg/trax/messages.go`: TRAX message and payload builders.
- `pkg/trax/watch`: watcher/display helpers used by CLIs and tests.

## Daemons

- `pkg/daemons/traxcoord.go`: real coordinator daemon startup: env checks, store, MQ, cache, LISTEN channels, Gin routes, port `17201`.
- `pkg/daemons/traxctrl.go`: real control daemon startup: store, MQ/cache init, Gin routes, port `17202`.
- `pkg/daemons/traxcoord/run.go`: inherited placeholder consumer path from `daemons2`; not the main binary path.
- `pkg/daemons/traxctrl/run.go`: inherited placeholder consumer path from `daemons2`; not the main binary path.
- `pkg/daemons/traxcoord/api/v1`: coordinator HTTP handlers.
- `pkg/daemons/traxctrl/api/v1`: control HTTP handlers.

## CLI

- `cmd/traxcli/cmd`: Cobra command package used by `cmd/traxcli`.
- `pkg/clis/traxcli/main.go`: interactive/direct API CLI implementation.
- `pkg/clis/traxcli/executor.go`: executor command runtime and simulation/shell idempotent service.
- `pkg/clis/traxcli/EXECUTOR.md`: executor usage notes inherited from source repo.

## Infrastructure Packages

- `pkg/mq/init.go`: TRAX RabbitMQ connection, channel pool, reconnect, and initial TRAX incoming-sagas exchange setup.
- `pkg/mq/common`: RabbitMQ helpers, publisher, channel pool, errors.
- `pkg/mq/trax`: TRAX-specific incoming saga exchange helpers.
- `pkg/cache`: Redis/in-memory locking and cache abstraction.
- `pkg/common`: inherited common helpers, logger, middleware, query helpers, random IDs, DB retry, and test helpers.
- `pkg/execpl`: inherited execution-pipeline message enums and envelope/value helpers.

## API And Proto

- `data/api/grpc/trax/v1/types.proto`: proto data definitions copied from source. Current daemon APIs are HTTP/Gin, not generated from this proto in the active code path.
- `gen-docs/...`: expected generated Swagger packages for daemon build imports. If missing, image/build fails.

## Deployment And Tests

- `deploy/k8s/init/init_trax_pgsql.sql`: base TRAX schema setup for templates and clusters.
- `deploy/k8s/init/*/min/trax.sql`: inherited domain-specific saga template seed SQL.
- `deploy/k8s/charts/traxctrl`, `deploy/k8s/charts/traxcoord*`: Kubernetes Helm charts.
- `tests/e2e/trax`: standalone TRAX compose-backed E2E tests.
- `tests/e2e/common`: reusable E2E framework and result capture helpers. In standalone TRAX, the active harness initializes only TRAX-owned schema and cluster seed data.
