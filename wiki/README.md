# TRAX Wiki

This is the **project wiki** for TRAX — the canonical, interlinked knowledge base for the
standalone workflow and saga orchestration system.

## What this is

- The source of truth for TRAX concepts, architecture, components, and decisions.
- A durable memory for agents and humans working on TRAX.
- A place to record the current extraction state as TRAX is separated from `daemons2`.

## Layout

```text
wiki/
├── README.md
├── index.md
├── glossary.md
├── concepts/
├── architecture/
├── components/
└── todos/
```

## Conventions

1. One concept per file.
2. Link related pages directly.
3. Keep `index.md` and `glossary.md` current.
4. Prefer describing the current executable truth over historical intent.
5. When extraction leaves legacy coupling behind, document it explicitly.
