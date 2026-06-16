# Executor And CLI Runtime

This page describes the current `traxcli` executor runtime and CLI responsibilities.

## CLI Entrypoint

`cmd/traxcli/main.go` calls `cmd/traxcli/cmd.NewTraxCli()`. The Cobra command package now lives alongside the `traxcli` entrypoint instead of under the old extraction-era command tree.

## Executor Config

`pkg/clis/traxcli/executor.go` defines `ExecutorConfig` with:

- cluster/template/step IDs;
- RabbitMQ URL;
- Redis URL;
- PostgreSQL URL;
- execution simulation fields;
- compensation simulation fields;
- execution shell command fields;
- compensation shell command fields;
- sub-saga template and `traxctrl` URL;
- idempotency backend.

## Modes

The executor requires exactly one forward execution mode:

- simulation mode via `--exec-sim-status`;
- shell mode via `--exec-shell`.

For non-sub-saga executors, compensation must also be configured through simulation or shell mode.

## Idempotency Backend

`--idempotency-storage-backend` is required. Supported values:

- `inmem`
- `redis`
- `pgsql`

Redis mode requires `--redis-addr`. PostgreSQL mode requires `--pgsql-url`.

## Sub-saga Mode

`--exec-sim-status=sub-saga` requires:

- `--sub-saga-template-id`
- `--traxctrl-url`

The executor creates an internal saga submitter and waits for it to become ready before running.

## Current Limitation

The simulation idempotent service keeps results in process memory. That is appropriate for tests and demo workers, but real executors must use durable idempotency around real side effects.
