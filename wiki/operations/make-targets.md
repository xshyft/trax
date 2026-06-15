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

- `REGISTRY=localhost:5555`
- `IMAGE_DAEMONS=trax.daemons`
- `IMAGE_CLIS=trax.clis`
- `TAG=latest`

## Wiki

```bash
make wiki
```

Serves Docsify on `WIKI_PORT`, default `3334`.

## E2E

```bash
make trax-e2e-clean
make trax-e2e-up
make trax-e2e-down
make trax-e2e-full
```

`trax-e2e-full` runs Docker Compose with `--abort-on-container-exit --exit-code-from test-runner`.

## Known Mismatch

`tests/e2e/trax/README.md` mentions `make trax-e2e-logs`, but the current `Makefile` does not define that target.
