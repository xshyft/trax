# Make Targets

The current `Makefile` exposes these targets.

## Local env

The `Makefile` will load `.env.local` when present. That file is ignored by git and can carry
machine-local settings such as:

```bash
DOCKER_CONFIG=/absolute/path/to/docker-config
```

## Build

```bash
make build-daemons
```

Builds the Linux daemon binaries through the containerized Go builder flow and writes:

- `bin/traxctrl`
- `bin/traxcoord`

```bash
make build-clis
```

Builds the Linux CLI binary through the containerized Go builder flow and writes:

- `bin/traxcli`

The binary build flow mirrors the older daemons2 pattern: a Linux Go builder container runs
against the checked-out repo and writes artifacts into `bin/`. The host OS does not compile the
release binaries directly.

Defaults:

- `DOCKER_HUB_REGISTRY=xshyft`
- `GOLANG_BUILDER_TAG=1.24.latest`
- `GOLANG_BUILDER_IMAGE=$(DOCKER_HUB_REGISTRY)/golang-builder:$(GOLANG_BUILDER_TAG)`

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
make bi
make push-images
```

Builds:

- `$(REGISTRY)/$(IMAGE_DAEMONS):$(BRANCH_TAG)` and `$(REGISTRY)/$(IMAGE_DAEMONS):$(HASH_TAG)` from `Dockerfile.daemons`
- `$(REGISTRY)/$(IMAGE_CLIS):$(BRANCH_TAG)` and `$(REGISTRY)/$(IMAGE_CLIS):$(HASH_TAG)` from `Dockerfile.clis`

Defaults:

- `REGISTRY=xshyft`
- `IMAGE_DAEMONS=trax.daemons`
- `IMAGE_CLIS=trax.clis`
- `BRANCH` comes from `git rev-parse --abbrev-ref HEAD`; detached HEAD remains `HEAD`
- `HASH_TAG` is the full `git rev-parse HEAD` commit hash
- `BRANCH_TAG` is `latest` on `main`; otherwise it is the branch name with `/` replaced by `-`

The default image names therefore resolve to Docker Hub repositories such as `xshyft/trax.daemons:latest` and `xshyft/trax.daemons:<commit-hash>`.

`make bi` first runs the Linux binary build flow and then builds both Docker images.

```bash
make push-images
make bip
```

`make push-images` pushes both the branch tag and the commit-hash tag for the daemon and CLI images.

`make bip` runs `make bi` and then `make push-images`.

## Docker Login

```bash
make docker-login
```

This target requires `DOCKER_CONFIG` to be set, typically through `.env.local`. It will:

- create the `DOCKER_CONFIG` directory when missing
- run `docker --config "$(DOCKER_CONFIG)" login -u "$(DOCKER_USERNAME)"`

Defaults:

- `DOCKER_USERNAME=$(REGISTRY)`

That means the default login user is also `xshyft` unless you override it locally.

## Release

```bash
make release
make release-resume
make release-status
make release-reset
```

These targets wrap `scripts/release.sh`.

- `make release` starts a resumable release from the current `VERSION`
- `make release-resume` continues a failed or interrupted release
- `make release-status` prints the current local release state
- `make release-reset` clears only the local release-state file

See [Release Flow](release-flow.md) for the full sequence and post-release version bump behavior.

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
