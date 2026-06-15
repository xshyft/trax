# TRAX Resilience TODO

This page tracks the TRAX-owned part of the imported backlog from `docs/TODO_TRAX_RESILIENCE_TEMPLATE_HOTRELOAD_IDEMPOTENCY.md`.

The imported source document is preserved verbatim, but it predates the standalone repo state. This page is the current status summary.

## Implemented Or Substantially Present

- Coordinator readiness checks running state, DB circuit state, and RabbitMQ connection health.
- Submitter announcement has fast exponential backoff before falling back to the normal announcement interval.
- Store interface has update/delete methods for saga templates and saga-step templates.
- PostgreSQL store emits `trax_template_events` on template insert/update/delete.
- Store listener supports multiple channels.
- Coordinator has notification fanout and subscribes separately for saga events and template events.
- Template reload reacts to `trax_template_events` and keeps periodic polling as a fallback.
- `traxctrl` exposes template CRUD and step-template CRUD endpoints.
- E2E suite includes idempotency, topology, compensation, deep sub-saga, hierarchy, and seven-step saga scenarios.

## Still Open

- Run the full standalone unit suite with a modern Go toolchain and record results.
- Run standalone compose-backed TRAX E2E and record results.
- Verify all imported resilience checklist items against code and tests, then split stale historical material from live backlog.
- Add generated Swagger docs to the standard build path so image builds do not fail on missing `gen-docs` packages.
- Tighten testing endpoint gating and document the exact enabling env vars.
- Review RabbitMQ reliability docs and port still-relevant fixes into TRAX-only TODOs.
- Normalize deployment/test naming that still assumes the old `agora_db` source environment.
- Decide where domain seed SQL belongs long term: TRAX examples or dependent repos.

## Related Wiki Pages

- [Architecture v1](../architecture/v1.md)
- [Template Management and Hot Reload](../flows/template-management.md)
- [Testing and E2E Operations](../operations/testing.md)
- [Imported daemons2 Backlog](imported-daemons2-backlog.md)
