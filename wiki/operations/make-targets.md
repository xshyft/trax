# Make Targets

The current `Makefile` exposes these targets.

## Build

```bash
make build-daemons
```

Builds:

- `bin/traxctrl`
- `bin/traxcoord`

```bash
make build-clis
```

Builds:

- `bin/traxcli`

## Tests

```bash
make test-unit
```

Runs:

```bash
go test ./pkg/trax/...
```

This is narrower than the full repo. A broader test target should be added after extraction cleanup.

## Swagger

```bash
make swagger
```

Currently only prints that committed Swagger docs are used. The code imports `gen-docs/traxcoord/v1` and `gen-docs/traxctrl/v1`, so a real generation/restoration path is still required if those packages are missing.

## Images

```bash
make images
```

Builds:

- `$(REGISTRY)/$(IMAGE_DAEMONS):$(TAG)` from `Dockerfile.daemons`
- `$(REGISTRY)/$(IMAGE_CLIS):$(TAG)` from `Dockerfile.clis`

Defaults:

- `REGISTRY=xshyft`
- `IMAGE_DAEMONS=trax.daemons`
- `IMAGE_CLIS=trax.clis`
- `TAG=latest`

The default image names therefore resolve to Docker Hub repositories such as `xshyft/trax.daemons:latest`.

## Wiki

```bash
make wiki
```

Serves Docsify on `WIKI_PORT`, default `3334`.

## E2E

```bash
make trax-e2e-clean
make trax-e2e-up
make trax-e2e-logs
make trax-e2e-down
make trax-e2e-full
```

`trax-e2e-up` starts the dependency stack and waits for health without running the test runner.

`trax-e2e-full` brings the stack up, runs `test-runner` as a one-shot container, then tears the stack down.
