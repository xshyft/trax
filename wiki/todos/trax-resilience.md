# TRAX Resilience TODO

This TODO is derived from the extracted backlog document:

- source: `docs/TODO_TRAX_RESILIENCE_TEMPLATE_HOTRELOAD_IDEMPOTENCY.md`

## Main themes

- coordinator readiness must include RabbitMQ health;
- submitter recovery should use bounded fast retry/backoff rather than only long sleep intervals;
- template hot reload should use PostgreSQL notifications and proper update/delete support;
- idempotency needs stronger E2E coverage.

## Extraction note

This backlog predates the standalone repo split. It should now be treated as TRAX-owned work unless a
specific item is clearly domain-specific.
