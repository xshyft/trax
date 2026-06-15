# traxctrl

`traxctrl` is the TRAX control and read API service.

## Responsibilities

- cluster CRUD;
- saga template CRUD;
- saga-step template CRUD;
- saga instance reads, lists, trees, and children;
- saga-step instance reads and lists;
- operator override actions such as force-mark compensated.

## Paths

- command wrapper: `cmd/traxctrl`
- runtime: `pkg/daemons/traxctrl.go`
- API handlers: `pkg/daemons/traxctrl/api/v1`
