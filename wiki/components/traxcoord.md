# traxcoord

`traxcoord` is the coordinator daemon that advances TRAX workflows.

## Responsibilities

- accept submitter announcements;
- validate and persist workflow instances;
- initialize and monitor step routes;
- publish step requests;
- consume step results;
- drive compensation when needed;
- expose health/readiness.

## Paths

- command wrapper: `cmd/traxcoord`
- runtime: `pkg/daemons/traxcoord.go`
- coordinator core: `pkg/trax/coordinator.go`
- API handlers: `pkg/daemons/traxcoord/api/v1`
