# Deployment Notes

TRAX currently carries Kubernetes-oriented deployment assets from `daemons2`.

## Images

Root Dockerfiles:

- `Dockerfile.daemons`: builds daemon entrypoints.
- `Dockerfile.clis`: builds CLI entrypoints.

Current daemon binaries:

- `traxcoord`
- `traxctrl`

Current CLI binary:

- `traxcli`

## Kubernetes Assets

Helm charts exist under:

- `deploy/k8s/charts/traxctrl`
- `deploy/k8s/charts/traxcoord1`
- `deploy/k8s/charts/traxcoord2`
- `deploy/k8s/charts/traxcoord3`

The three coordinator charts model multiple coordinator affinity groups.

## PostgreSQL Initialization

Base schema init:

- `deploy/k8s/init/init_trax_pgsql.sql`

Namespace/domain seed templates inherited from `daemons2`:

- `deploy/k8s/init/csd/min/trax.sql`
- `deploy/k8s/init/exchange/min/trax.sql`
- `deploy/k8s/init/prtagent/min/trax.sql`
- `deploy/k8s/init/tldinfra/min/trax.sql`

These seed files are useful examples of real saga templates. They are domain-specific and should eventually move to the systems that own those domains.

## Runtime Dependencies

A real deployment needs:

- PostgreSQL database reachable by the TRAX daemons.
- RabbitMQ reachable by TRAX MQ initialization.
- Redis or another configured cache backend when distributed mutexes are required.
- generated Swagger docs if building daemon API packages that import `gen-docs/...`.

## Environment And Config Notes

Known runtime knobs in the extracted code include:

- `TRAX_EXECUTION_TIMEOUT_MS`: step execution timeout in milliseconds, default 15 minutes.
- `TRAX_TEMPLATE_RELOAD_INTERVAL_MS`: fallback polling interval for template reload.
- `V1_SWAGGER_HOST`: Swagger host used by daemon API docs.
- testing endpoint flags from daemon run/config code for database switching and smoke template helpers.

The current repo should fail visibly when required infrastructure is missing. Avoid silent fallbacks in service startup and deployment scripts.

## Extraction Notes

Some imported deployment assets still reference old Agora naming such as `agora_db` or old image names. Treat those as extraction cleanup tasks, not final TRAX contracts.
