# Configuration

This page records runtime configuration discovered from the current code.

## Required For traxcoord

- `TRAX_COORDINATOR_AFFINITY_GROUP`: coordinator affinity group. Missing value panics at startup.
- `POSTGRESQL_CONN_STRING`: PostgreSQL connection string. Missing value panics at startup.
- `RABBITMQ_CONN_STRING`: RabbitMQ connection string. Missing value panics inside MQ init.
- `REDIS_ADDRESS`: used by cache initialization when Redis-backed locking is required.

## Required For traxctrl

- `POSTGRESQL_CONN_STRING`: required unless `--in-memory-store` is passed.
- `RABBITMQ_CONN_STRING`: required by MQ init.
- `REDIS_ADDRESS`: used by cache initialization when Redis-backed cache/lock paths are active.

## Submitter Configuration

- `TRAX_COORDINATOR_BASE_URL`: resolved through `common.GetServiceBaseURL("traxcoord")`; expected to include `/api/v1`.
- `TRAX_SUBMITTER_ANNOUNCEMENT_INTERVAL`: required; parsed as Go duration. Missing or invalid value panics.

## Coordinator Tuning

- `TRAX_EXECUTION_TIMEOUT_MS`: optional; step execution timeout in milliseconds. Default is 900000 ms, or 15 minutes.
- `TRAX_TEMPLATE_RELOAD_INTERVAL`: optional; Go duration string. Default is 10 seconds.

## RabbitMQ Tuning

- `RABBITMQ_MAX_CHANNELS`: optional channel pool size. Default is 500.

RabbitMQ init loops until connection and queue initialization succeed. On connection close, it reconnects and calls `mqcommon.NotifyReconnect()` after reinitializing queues.

## API Docs

- `V1_SWAGGER_HOST`: used to set Swagger host for `traxcoord` and `traxctrl` API docs.

## Testing/Admin

- `ENABLE_TESTING_ENDPOINTS=true`: enables experimental testing endpoints such as database switching. These endpoints must not be enabled in production.

## Logging/Common

Inherited common logger configuration includes:

- `MODE`
- `LOG_LEVEL`
- `VERSION_BRANCH`
- `VERSION_HASH`
- `SU_MODE=active`: logs a warning that SU mode is active.

## Known Problem

`pkg/common.GetTraxClusterId()` still has fallback-like behavior from the source repo. This should be reviewed against the fail-fast rule if that helper is used in active TRAX paths.
