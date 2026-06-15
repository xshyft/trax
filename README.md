# TRAX

TRAX is a standalone distributed workflow and saga orchestration system extracted from `daemons2`.

It owns:
- durable saga and step state;
- template and cluster management;
- RabbitMQ-based distributed step routing;
- coordinator and control-plane daemons;
- a generic executor and submitter CLI surface;
- TRAX-focused unit and end-to-end tests.

This repository is now the canonical home for TRAX. Other systems should depend on TRAX through
its Go packages, APIs, and runtime binaries rather than carrying private copies of the subsystem.

Start with:
- `wiki/index.md`
- `tests/e2e/trax/README.md`
- `docs/TODO_TRAX_RESILIENCE_TEMPLATE_HOTRELOAD_IDEMPOTENCY.md`
