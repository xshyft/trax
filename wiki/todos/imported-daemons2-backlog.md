# Imported Source Backlog

This page reconciles source-repo TRAX/saga docs with the current standalone code. The readable source-history files are under [Source Repo History Docs](../source/daemons2/index.md). The extracted knowledge map is [Extracted Source Knowledge](../reference/imported-daemons2-docs.md).

## Already Present In Standalone Code

From the source resilience TODO, these items appear implemented or substantially implemented in the current repo:

- coordinator readiness checks include MQ health;
- submitter announcement has fast exponential backoff;
- store interface includes template update/delete methods;
- PostgreSQL store emits `trax_template_events`;
- store listener supports multiple channels;
- coordinator notification fanout exists;
- coordinator template reload loop uses notifications plus periodic fallback;
- `traxctrl` exposes template and step-template CRUD endpoints;
- TRAX E2E tests include idempotency coverage.

## Needs Verification Or Cleanup

- Confirm all source resilience checklist items against current code and tests, then close or rewrite stale items.
- Generate/restore Swagger docs for standalone `traxcoord` and `traxctrl` builds.
- Normalize old `agora_db` naming in deploy/test assets where TRAX should be standalone.
- Verify image build paths after extraction.
- Run the full unit suite with a modern Go toolchain.
- Run compose-backed TRAX E2E from this repo and record exact commands/results.
- Audit testing endpoints so they are explicitly gated and cannot be enabled accidentally in production.
- Review RabbitMQ reliability source docs and port still-relevant fixes into TRAX-only TODOs.
- Review source domain seed SQL and decide what remains as examples versus what moves to dependent systems.

## Domain Workflow Source Material

The source-history workflow TODOs are not TRAX core backlog. They are examples and migration notes for dependent systems. They should influence TRAX only when they reveal a generic workflow-engine requirement such as idempotency, compensation, sub-saga hierarchy, routing, or observability.
