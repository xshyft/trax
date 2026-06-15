# Startup Paths

This page follows the real daemon and CLI startup paths from code.

## traxcoord

Binary:

```text
cmd/traxcoord/main.go -> pkg/daemons.RunTraxCoordinator()
```

Startup behavior in `pkg/daemons/traxcoord.go`:

1. Creates background context.
2. Sets `common.SubComponent = "traxcoord"` and initializes logger.
3. Requires `TRAX_COORDINATOR_AFFINITY_GROUP`.
4. Requires `POSTGRESQL_CONN_STRING`.
5. Initializes cache via `cache.Init(ctx)`.
6. Initializes RabbitMQ via `mq.Init(ctx)`.
7. Creates PostgreSQL store and calls `Init(ctx)`.
8. Starts LISTEN on `trax_saga_events`.
9. Starts LISTEN on `trax_template_events`.
10. Creates `trax.NewSagaCoordinator(...)`.
11. Starts coordinator in a goroutine.
12. Creates Gin server with recovery, request logging, CORS, and request/trace middleware.
13. Registers coordinator API routes.
14. Serves on `0.0.0.0:17201`.
15. Blocks until SIGINT/SIGTERM.

## traxctrl

Binary:

```text
cmd/traxctrl/main.go -> pkg/daemons.RunTraxCtrl(useInMemory)
```

Startup behavior in `pkg/daemons/traxctrl.go`:

1. Parses `--in-memory-store` in the entrypoint.
2. Creates background context.
3. Sets `common.SubComponent = "traxctrl"` and initializes logger.
4. Initializes cache and RabbitMQ.
5. If `--in-memory-store` is set, creates in-memory store.
6. Otherwise requires `POSTGRESQL_CONN_STRING`, creates PostgreSQL store.
7. Calls `store.Init(ctx)`.
8. Creates Gin server with recovery, request logging, CORS, and request/trace middleware.
9. Registers control API routes.
10. Serves on `0.0.0.0:17202`.
11. Blocks until SIGINT/SIGTERM.

## traxcli

Binary:

```text
cmd/traxcli/main.go -> cmd/agora/clis/traxcli.NewTraxCli()
```

This is still using an inherited package path from `daemons2`. The standalone entrypoint exists, but the cobra command package should eventually move out of `cmd/agora/...`.

## Placeholder Paths

`pkg/daemons/traxcoord/run.go` and `pkg/daemons/traxctrl/run.go` contain old placeholder consumers over `mqtrax.ConsumeTraxIncomingSagasQueueAsync`. They are not the main startup path used by `cmd/traxcoord` or `cmd/traxctrl`.
