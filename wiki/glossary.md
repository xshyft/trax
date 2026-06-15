# Glossary

- **TRAX** — the standalone distributed workflow and saga orchestration system.
- **Saga template** — the durable definition of a workflow: ordered step templates plus metadata.
- **Saga instance** — one runtime execution of a saga template.
- **Saga step template** — the definition of one workflow step.
- **Saga step instance** — one runtime execution record of a saga step.
- **Coordinator** — the runtime actor that schedules steps, consumes step results, and advances saga state. See [traxcoord](components/traxcoord.md).
- **Control API** — the TRAX read/control surface for templates, clusters, saga status, trees, and operator actions. See [traxctrl](components/traxctrl.md).
- **Executor** — a worker bound to a saga-step route that performs forward execution and, where defined, compensation.
- **Submitter** — a client-side runtime component that submits saga instances into a cluster.
- **Cluster** — an execution namespace for TRAX routing and workflow state partitioning.
- **Compensation** — reverse-path execution for already-committed steps after a failure.
- **Sub-saga** — a child workflow spawned from within a parent step and tracked as part of a saga hierarchy.
