# Source Repo History Docs

These files came from the original repository where TRAX lived before it became standalone. They are here only as source history and deep background.

A new TRAX reader should start with the curated wiki pages, not these raw files:

- [Architecture v1](../../architecture/v1.md)
- [Code Map](../../code/repo-map.md)
- [Saga Lifecycle](../../flows/saga-lifecycle.md)
- [Coordinator Algorithms](../../architecture/coordinator-algorithms.md)
- [State Machine](../../architecture/state-machine.md)
- [Configuration](../../operations/configuration.md)
- [Current Gaps](../../reference/current-gaps.md)
- [Extracted Source Knowledge](../../reference/imported-daemons2-docs.md)

## Source Documents

### TRAX Core And Reliability

- [TRAX resilience, template hot reload, idempotency](TODO_TRAX_RESILIENCE_TEMPLATE_HOTRELOAD_IDEMPOTENCY.md)
- [Saga coordinator mutex timeout fix](SAGA_COORDINATOR_MUTEX_TIMEOUT_FIX.md)
- [RabbitMQ reliability remediation](RABBITMQ_RELIABILITY_REMEDIATION_TODO.md)
- [RabbitMQ minimal impact plan](RABBITMQ_T0001_MINIMAL_IMPACT_PLAN.md)
- [RabbitMQ tier-0 fixes](RABBITMQ_TIER0_FIXES_TODO.md)

### Idempotency

- [Execution idempotency seed](TODO_EXECUTION_IDEMPOTENCY_SEED.md)
- [Idempotent treasury vault operations](TODO_IDEMPOTENT_TREASURY_VAULT_OPERATIONS.md)
- [Treasury idempotency](TREASURY_IDEMPOTENCY.md)

### Testing And E2E

- [E2E test catalog](E2E_TEST_CATALOG.md)
- [E2E test coverage analysis](E2E_TEST_COVERAGE_ANALYSIS.md)
- [E2E test result capture TODO](E2E_TEST_RESULTS_CAPTURE_TODO.md)
- [Multi-namespace E2E compose TODO](TODO_MULTI_NAMESPACE_E2E_COMPOSE.md)
- [Order E2E 3-namespace infra TODO](TODO_ORDER_E2E_3NS_INFRA.md)
- [Individual saga step E2E tests TODO](TODO_INDIVIDUAL_SAGA_STEP_E2E_TESTS.md)
- [LASER E2E tests TODO](LASER_E2E_TESTS_TODO.md)
- [LASER external call E2E TODO](LASER_EXTERNAL_CALL_E2E_TODO.md)

### Domain Workflow Examples

These are source-system workflow examples. They are useful for understanding complex saga usage, but they are not TRAX core requirements.

- [Create investor order saga](TODO_CREATE_INVESTOR_ORDER_SAGA.md)
- [Create direct order saga](TODO_CREATE_DIRECT_ORDER_SAGA.md)
- [Cancel investor order saga](TODO_CANCEL_INVESTOR_ORDER_SAGA.md)
- [Cancel direct order saga](TODO_CANCEL_DIRECT_ORDER_SAGA.md)
- [Fix new order single saga](TODO_FIX_NEW_ORDER_SINGLE_SAGA.md)
- [Setup new legal participant saga](TODO_SETUP_NEW_LEGAL_PARTICIPANT_SAGA.md)
- [Setup security listing saga](TODO_SETUP_SECURITY_LISTING_SAGA.md)
- [Establish legal structure saga](TODO_ESTABLISH_LEGAL_STRUCTURE_SAGA.md)
- [Onboard new investor saga](TODO_ONBOARD_NEW_INVESTOR_SAGA.md)
- [New investor under participant saga](TODO_NEW_INVESTOR_UNDER_PARTICIPANT_SAGA.md)
- [Cash stash transfer saga](TODO_CASH_STASH_TRANSFER_SAGA.md)
- [Deploy cash token legal mechanism saga](TODO_DEPLOY_CASH_TOKEN_LEGAL_MECHANISM_SAGA.md)
- [Deploy core legal mechanisms saga](TODO_DEPLOY_CORE_LEGAL_MECHANISMS_SAGA.md)
- [Deploy trading legal mechanisms saga](TODO_DEPLOY_TRADING_LEGAL_MECHANISMS_SAGA.md)
- [Deploy treasury legal mechanisms saga](TODO_DEPLOY_TREASURY_LEGAL_MECHANISMS_SAGA.md)
- [Deploy lattice facets saga](TODO_DEPLOY_LATTICE_FACETS_SAGA.md)
- [Legal structure saga diamond facet refactoring](TODO_LEGAL_STRUCTURE_SAGAS_DIAMOND_FACET_REFACTORING.md)
- [Instrument authorization saga refactoring](INSTRUMENT_AUTHORIZATION_SAGA_REFACTORING_TODO.md)

### LASER And Treasury Background

- [LASER execution API implementation](LASER_EXECUTION_API_IMPLEMENTATION.md)
- [LASER execution chain](LASER_EXECUTION_CHAIN.md)
- [Treasury grid implementation plan](TREASURY_GRID_IMPLEMENTATION_PLAN.md)
- [Treasury vault withdraw E2E](TREASURY_VAULT_WITHDRAW_E2E.md)
- [Treasury stash operations](TODO_TREASURY_STASH_OPERATIONS.md)
- [Treasury vault slot links](TODO_TREASURY_VAULT_SLOT_LINKS.md)
- [Treasury indexer service](TODO_TREASURY_INDEXER_SERVICE.md)
- [Execution runtime](TODO_EXECUTION_RUNTIME.md)
