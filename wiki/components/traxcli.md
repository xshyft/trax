# traxcli

`traxcli` is the operator, developer, submitter, and executor CLI for TRAX.

## Code Paths

- entrypoint: `cmd/traxcli/main.go`
- legacy cobra package: `cmd/agora/clis/traxcli`
- runtime package: `pkg/clis/traxcli`
- executor notes: `pkg/clis/traxcli/EXECUTOR.md`

## Responsibilities

- manage templates through `traxctrl` APIs;
- submit saga instances;
- run executors for saga-step templates;
- watch saga progress;
- support local/demo workflows and E2E workers.

## Executor Mode

In executor mode, `traxcli` binds a worker to a cluster, saga template, and saga-step template. The worker receives execution or compensation requests and invokes the configured idempotent service behavior.

## Submitter Mode

In submitter mode, `traxcli` announces to `traxcoord`, receives cluster routing data, publishes saga submission requests, and can wait for completion through `traxctrl`.

## Current Extraction Note

Some CLI code still lives under `cmd/agora/clis/traxcli` because it was copied from `daemons2`. The standalone entrypoint exists at `cmd/traxcli/main.go`; future cleanup should move package names and paths away from old Agora naming where practical.
