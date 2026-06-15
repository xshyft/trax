# Current Gaps And Mismatches

This page lists code/wiki/deployment mismatches found during the documentation sweep.

## Build And Generated Docs

The daemon API packages import generated Swagger packages under `gen-docs/...`. The current `Makefile` `swagger` target only prints a message. A real generation or committed-doc restoration path is needed.

## Makefile Versus E2E README

`tests/e2e/trax/README.md` documents `make trax-e2e-logs`, but the current `Makefile` does not define that target.

## Old Agora Paths

`cmd/traxcli` still imports `cmd/agora/clis/traxcli`. This works as an extraction bridge, but the package path should eventually be renamed.

## Placeholder Daemon Run Files

`pkg/daemons/traxcoord/run.go` and `pkg/daemons/traxctrl/run.go` are old placeholder consumers and are not the real startup path. They should be removed or clearly deprecated in code after confirming no caller uses them.

## Database Naming

The E2E compose file and base init SQL still use `agora_db`. That reflects source repo inheritance. A standalone TRAX database name should be chosen and applied consistently.

## Domain Seed SQL Ownership

`deploy/k8s/init/{csd,exchange,prtagent,tldinfra}/min/trax.sql` contains real domain saga templates. These are useful examples, but they likely belong in dependent systems long term.

## Toolchain

The codebase requires modern Go. During extraction, the active shell Go was observed as too old to compile dependencies. The wiki now documents this, but the repo should enforce/toolchain-document it explicitly.

## Common Package Breadth

`pkg/common` still contains helpers for many source-system services. It should be reduced or split once TRAX standalone boundaries settle.

## Fail-fast Audit

Most required daemon config panics when missing. One inherited helper, `common.GetTraxClusterId`, appears to contain fallback behavior and should be audited against the fail-fast rule if used in active TRAX paths.
