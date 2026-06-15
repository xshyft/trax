# Testing and E2E

TRAX ships with:

- unit tests in `pkg/trax` and `pkg/mq/common`;
- compose-backed end-to-end tests in `tests/e2e/trax`;
- a reusable E2E harness in `tests/e2e/common`.

## E2E shape

The TRAX E2E environment centers on:

- PostgreSQL
- RabbitMQ
- Redis
- `traxctrl`
- multiple `traxcoord` instances
- one submitter container
- multiple `traxcli executor` containers
- a Go test runner

## Coverage intent

The E2E suite covers:

- saga template creation;
- multi-step committed workflows;
- compensation paths;
- deep sub-saga hierarchy;
- topology and routing behavior;
- idempotency behavior.
