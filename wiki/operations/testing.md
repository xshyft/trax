# Testing And E2E Operations

TRAX has unit tests, package-level tests, and compose-backed E2E tests.

## Unit And Package Tests

Core packages with tests include:

- `pkg/trax`
- `pkg/mq/common`
- `pkg/common`
- `pkg/cache`

The extracted repo currently requires a modern Go toolchain. During extraction, the active shell reported Go 1.17, which is too old for dependencies that use packages such as `cmp`, `slices`, `maps`, `log/slog`, and `crypto/ecdh`.

## TRAX E2E Suite

The dedicated TRAX E2E suite lives under `tests/e2e/trax`.

It uses:

- PostgreSQL
- RabbitMQ
- Redis
- `traxctrl`
- multiple `traxcoord` services
- `traxcli executor` workers
- a Go test runner

Covered scenarios include:

- smoke template creation and submission;
- seven-step successful saga;
- compensation flow;
- deep sub-saga execution;
- saga hierarchy queries;
- topology/routing behavior;
- idempotency behavior.

## Test Isolation

The imported E2E harness includes support for:

- per-run environment management;
- RabbitMQ readiness checks;
- database helpers;
- service checks;
- result capture;
- Docker info, logs, and database dump scripts.

Testing-only endpoints exist for database switching:

- `traxctrl`: `POST /api/v1/experimental/testing/setdbname`
- `traxcoord`: `POST /api/v1/experimental/testing/setdbname`

These are test/admin affordances and must remain gated outside normal production operation.

## Imported E2E Documentation

The old `daemons2` docs imported into `docs/imported-daemons2/` include broader E2E material:

- `E2E_TEST_CATALOG.md`
- `E2E_TEST_COVERAGE_ANALYSIS.md`
- `E2E_TEST_RESULTS_CAPTURE_TODO.md`
- `TODO_MULTI_NAMESPACE_E2E_COMPOSE.md`
- `TODO_ORDER_E2E_3NS_INFRA.md`
- `LASER_E2E_TESTS_TODO.md`
- `LASER_EXTERNAL_CALL_E2E_TODO.md`

Those describe larger Agora/LASER test matrices. Keep them as historical/context material while extracting reusable TRAX-only coverage.
