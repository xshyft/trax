# Extracted Source Knowledge

TRAX was extracted from a larger source repository. The raw source-history docs are readable under [Source Repo History Docs](../source/daemons2/index.md), but a new TRAX reader should not need to know that old repo to understand TRAX.

This page extracts the TRAX-relevant knowledge from those source docs and points to the current wiki pages where each point belongs.

## What Was Extracted Into The TRAX Wiki

### 1. PostgreSQL is authority; RabbitMQ is transport

Source docs repeatedly show that RabbitMQ overload, reconnects, duplicate delivery, and stale consumers are real operational concerns. TRAX must therefore treat RabbitMQ as delivery, not truth. The coordinator must always re-read PostgreSQL before mutating workflow state.

Current wiki pages:

- [Architecture v1](../architecture/v1.md)
- [RabbitMQ Routing](../concepts/rabbitmq-routing.md)
- [Coordinator Algorithms](../architecture/coordinator-algorithms.md)

Source history:

- [RabbitMQ reliability remediation](../source/daemons2/RABBITMQ_RELIABILITY_REMEDIATION_TODO.md)
- [RabbitMQ tier-0 fixes](../source/daemons2/RABBITMQ_TIER0_FIXES_TODO.md)
- [Saga coordinator mutex timeout fix](../source/daemons2/SAGA_COORDINATOR_MUTEX_TIMEOUT_FIX.md)

### 2. Coordinator processing must be guarded by saga-instance locking

The source mutex bug showed what happens when one saga is processed concurrently: invalid state transitions, long-held callbacks, and stuck workflows. TRAX now documents the mutex/timeout rule as part of coordinator behavior.

Current wiki pages:

- [Coordinator](../concepts/coordinator.md)
- [Coordinator Algorithms](../architecture/coordinator-algorithms.md)
- [State Machine](../architecture/state-machine.md)

Source history:

- [Saga coordinator mutex timeout fix](../source/daemons2/SAGA_COORDINATOR_MUTEX_TIMEOUT_FIX.md)

### 3. Candidate states must wake coordinators, but not replace store reads

`trax_saga_events` and `trax_template_events` are wakeup channels. They should reduce latency, but the durable state machine still lives in PostgreSQL.

Current wiki pages:

- [Notifications](../concepts/notifications.md)
- [PostgreSQL Store](../concepts/postgresql-store.md)
- [Template Hot Reload](../concepts/template-hot-reload.md)
- [Template Management and Hot Reload](../flows/template-management.md)

Source history:

- [TRAX resilience, template hot reload, idempotency](../source/daemons2/TODO_TRAX_RESILIENCE_TEMPLATE_HOTRELOAD_IDEMPOTENCY.md)

### 4. Template CRUD and hot reload are core TRAX behavior

The source TODO treated hot reload as a critical resilience item. In current code, template CRUD, `trax_template_events`, notification fanout, and reload loops are part of TRAX core and documented as such.

Current wiki pages:

- [Saga Template](../concepts/saga-template.md)
- [Saga Step Template](../concepts/saga-step-template.md)
- [Template Hot Reload](../concepts/template-hot-reload.md)
- [Template Management and Hot Reload](../flows/template-management.md)

Source history:

- [TRAX resilience, template hot reload, idempotency](../source/daemons2/TODO_TRAX_RESILIENCE_TEMPLATE_HOTRELOAD_IDEMPOTENCY.md)

### 5. Submitter readiness must mean "announced and has clusters"

The source failure mode was not only service availability. A submitter can be technically up but not usable until it has coordinator-provided cluster IDs and inbox/outbox routing names.

Current wiki pages:

- [Submitter](../concepts/submitter.md)
- [TRAX MQ and Coordination](../concepts/trax-mq-and-coordination.md)
- [Saga Lifecycle](../flows/saga-lifecycle.md)

Source history:

- [TRAX resilience, template hot reload, idempotency](../source/daemons2/TODO_TRAX_RESILIENCE_TEMPLATE_HOTRELOAD_IDEMPOTENCY.md)

### 6. Idempotency is not optional for real side effects

The source docs include detailed idempotency seed and treasury idempotency designs. TRAX core should not own treasury-specific rules, but it must preserve the generic rule: one logical operation needs a deterministic identity that survives retries and flows into side-effecting steps.

Current wiki pages:

- [Idempotency](../concepts/idempotency.md)
- [Idempotent Service](../concepts/idempotent-service.md)
- [Executor And CLI Runtime](../architecture/executor-and-cli.md)
- [PostgreSQL Data Model](../data-model/postgresql.md)

Source history:

- [Execution idempotency seed](../source/daemons2/TODO_EXECUTION_IDEMPOTENCY_SEED.md)
- [Idempotent treasury vault operations](../source/daemons2/TODO_IDEMPOTENT_TREASURY_VAULT_OPERATIONS.md)
- [Treasury idempotency](../source/daemons2/TREASURY_IDEMPOTENCY.md)

### 7. Complex domain workflows prove why sub-sagas exist

The source domain docs show workflows that spawn other workflows and require hierarchy inspection. TRAX keeps this as a generic sub-saga mechanism: parent saga ID, parent step ID, root saga ID, and depth.

Current wiki pages:

- [Sub-saga](../concepts/sub-saga.md)
- [Sub-sagas and Hierarchy](../flows/sub-sagas.md)
- [Saga Instance](../concepts/saga-instance.md)
- [Executor](../concepts/executor.md)

Source history:

- [Setup new legal participant saga](../source/daemons2/TODO_SETUP_NEW_LEGAL_PARTICIPANT_SAGA.md)
- [Deploy lattice facets saga](../source/daemons2/TODO_DEPLOY_LATTICE_FACETS_SAGA.md)
- [Cash stash transfer saga](../source/daemons2/TODO_CASH_STASH_TRANSFER_SAGA.md)

### 8. E2E must verify the real distributed shape

The source test docs emphasize compose-backed, multi-service, database-switched, log-captured E2E tests. TRAX's own E2E suite should keep the reusable form: PostgreSQL, RabbitMQ, Redis, `traxctrl`, multiple coordinators, submitter, executors, and result capture.

Current wiki pages:

- [Testing and E2E](../architecture/testing-and-e2e.md)
- [Testing and E2E Operations](../operations/testing.md)
- [Make Targets](../operations/make-targets.md)

Source history:

- [E2E test catalog](../source/daemons2/E2E_TEST_CATALOG.md)
- [E2E test coverage analysis](../source/daemons2/E2E_TEST_COVERAGE_ANALYSIS.md)
- [E2E test result capture TODO](../source/daemons2/E2E_TEST_RESULTS_CAPTURE_TODO.md)
- [Multi-namespace E2E compose TODO](../source/daemons2/TODO_MULTI_NAMESPACE_E2E_COMPOSE.md)

### 9. Domain seed SQL is example/migration material, not TRAX core

The source repo had TRAX templates for CSD, exchange, participant agent, treasury, LASER, and lattice workflows. In standalone TRAX, those files are useful as examples and migration material, but the owning domain systems should eventually own them.

Current wiki pages:

- [Deployment Notes](../operations/deployment.md)
- [Current Gaps And Mismatches](current-gaps.md)
- [Imported Source Backlog](../todos/imported-daemons2-backlog.md)

Source history:

- [Source Repo History Docs](../source/daemons2/index.md)

## Reading Rule

If a source-history doc describes a reusable TRAX mechanism, extract it into a normal wiki page. If it describes a source-system business workflow, keep it linked as an example or migration note and do not make TRAX core depend on it.
