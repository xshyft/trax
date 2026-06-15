# Imported daemons2 Docs

These files were copied from `/Users/kam/repos/NEW2/qomet/agora/daemons2/docs` during the standalone TRAX extraction cleanup.

They preserve source-system knowledge about TRAX, sagas, idempotency, RabbitMQ reliability, E2E strategy, LASER execution, treasury workflows, and domain saga designs.

Read them as source material. The current TRAX interpretation is in `wiki/`, especially:

- `wiki/architecture/v1.md`
- `wiki/reference/imported-daemons2-docs.md`
- `wiki/todos/imported-daemons2-backlog.md`

## Core TRAX/Reliability Docs

- `TODO_TRAX_RESILIENCE_TEMPLATE_HOTRELOAD_IDEMPOTENCY.md`
- `SAGA_COORDINATOR_MUTEX_TIMEOUT_FIX.md`
- `RABBITMQ_RELIABILITY_REMEDIATION_TODO.md`
- `RABBITMQ_T0001_MINIMAL_IMPACT_PLAN.md`
- `RABBITMQ_TIER0_FIXES_TODO.md`

## Idempotency Docs

- `TODO_EXECUTION_IDEMPOTENCY_SEED.md`
- `TODO_IDEMPOTENT_TREASURY_VAULT_OPERATIONS.md`
- `TREASURY_IDEMPOTENCY.md`

## E2E Docs

- `E2E_TEST_CATALOG.md`
- `E2E_TEST_COVERAGE_ANALYSIS.md`
- `E2E_TEST_RESULTS_CAPTURE_TODO.md`
- `TODO_MULTI_NAMESPACE_E2E_COMPOSE.md`
- `TODO_ORDER_E2E_3NS_INFRA.md`
- `TODO_INDIVIDUAL_SAGA_STEP_E2E_TESTS.md`

## Domain Saga Docs

The remaining `TODO_*_SAGA.md`, LASER, and treasury documents are domain workflow material inherited from the source system. They are useful as complex TRAX examples and migration references, but they should not become hard TRAX core dependencies.
