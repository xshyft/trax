# TRAX Saga System

TRAX is a distributed workflow and saga orchestration system for multi-step operations that need
persistent state, asynchronous execution, idempotency, and optional compensation.

## Core pieces

- `traxctrl` — template CRUD, cluster CRUD, saga inspection, tree/children queries, and operator overrides.
- `traxcoord` — coordinator processes that schedule steps, consume results, and move workflows forward or backward.
- saga templates — persistent workflow definitions.
- saga executors — service-owned workers bound to saga-step request streams.
- saga submitters — clients that announce themselves to coordinators and submit workflow instances.
- PostgreSQL store — durable record for templates, clusters, saga instances, step instances, outputs, and compensation outputs.
- RabbitMQ topic exchange — the transport between coordinators and executors.

## What belongs in TRAX

TRAX should own generic workflow mechanics:

- workflow templates and instances;
- step routing and execution state;
- retry/health/coordination mechanics;
- hierarchical workflow metadata;
- generic operator-facing read/control surfaces.

Domain workflows themselves should migrate out to dependent systems over time.
