# traxctrl

`traxctrl` is the TRAX control and read API service. It should be the first API surface operators and dependent services use for inspection and administration.

## Code Paths

- entrypoint: `cmd/traxctrl/main.go`
- legacy wrapper: `cmd/agora/daemons/traxctrl/cmd.go`
- daemon runtime: `pkg/daemons/traxctrl.go`, `pkg/daemons/traxctrl/run.go`
- HTTP API: `pkg/daemons/traxctrl/api/v1`

## Responsibilities

- cluster CRUD;
- saga-template CRUD;
- saga-step-template CRUD;
- saga instance list/get/tree/children queries;
- saga-step instance list/get queries;
- saga annex create/list/get bytes;
- force-mark blocked saga as compensated with audit reason;
- expose testing-only database switching and smoke-template helper where enabled;
- serve Swagger docs when generated docs are available.

## Operator Override

`PUT /api/v1/saga-instances/{sagaInstanceId}/force-compensated` is an escape hatch for blocked sagas. The store only allows this when the current saga state is `SAGA_STATE_ENUM_BLOCKED`, and a reason is required for audit.

This is not normal compensation. It is an operator decision after inspection.

## Annex Ownership

TRAX owns saga annex storage. Gateways can attach bytes to a saga through `traxctrl`; readers can list metadata and fetch bytes later. Annexes are tied to saga instances and should not exist as orphaned external records.
