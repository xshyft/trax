# Local Run

This page captures the current local run/build path.

## Build Binaries

```bash
make build-daemons
make build-clis
```

Outputs:

- `bin/traxctrl`
- `bin/traxcoord`
- `bin/traxcli`

## Start Wiki

```bash
make wiki
```

Default URL:

```text
http://localhost:3334
```

## Start E2E Stack

```bash
make trax-e2e-up
```

Run full E2E:

```bash
make trax-e2e-full
```

Stop stack:

```bash
make trax-e2e-down
```

Clean volumes:

```bash
make trax-e2e-clean
```

## Run traxctrl Manually

With PostgreSQL:

```bash
POSTGRESQL_CONN_STRING='postgres://postgres:postgres@localhost:5432/agora_db?sslmode=disable' \
RABBITMQ_CONN_STRING='amqp://guest:guest@localhost:5672/' \
REDIS_ADDRESS='localhost:6379' \
./bin/traxctrl
```

With in-memory store:

```bash
RABBITMQ_CONN_STRING='amqp://guest:guest@localhost:5672/' \
REDIS_ADDRESS='localhost:6379' \
./bin/traxctrl --in-memory-store
```

## Run traxcoord Manually

```bash
TRAX_COORDINATOR_AFFINITY_GROUP=1 \
POSTGRESQL_CONN_STRING='postgres://postgres:postgres@localhost:5432/agora_db?sslmode=disable' \
RABBITMQ_CONN_STRING='amqp://guest:guest@localhost:5672/' \
REDIS_ADDRESS='localhost:6379' \
./bin/traxcoord
```

## Ports

- `traxcoord`: `17201`
- `traxctrl`: `17202`
- E2E `traxctrl` host mapping: `17200 -> 17202`
- E2E coordinators: `17220`, `17221`, `17222` mapped to daemon port `17201`
