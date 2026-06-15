# Coordinator Algorithms

This page describes the main algorithms in `pkg/trax/coordinator.go`.

## Startup

`Start(ctx)`:

1. creates a consumer context;
2. checks DB health;
3. lists clusters;
4. initializes event bus and control bus for each cluster;
5. initializes per-cluster step topic exchange;
6. creates one coordinator results queue per cluster/affinity;
7. consumes result queue messages;
8. consumes control inbox messages;
9. starts `processSagaSteps` per cluster;
10. reloads templates;
11. starts notification broadcaster;
12. starts template reload loop;
13. marks coordinator running.

## Template Reload

`reloadSagaTemplates(ctx)`:

1. lists clusters;
2. lists saga templates;
3. for each step template not already initialized, creates executor inbox queue and topic binding;
4. marks step initialized.

`startTemplateReloadLoop(ctx)` reacts to `trax_template_events` and also polls periodically.

## Notification Fanout

`startNotificationBroadcaster(ctx)` reads the store's single notification channel and fans events out to subscriber channels. This prevents one consumer from starving another.

## Step Processing

`processSagaSteps(ctx, clusterId)` subscribes to `trax_saga_events` and scans for candidate steps. For each candidate, it calls `processStepWithMutex`.

`processStepWithMutex` locks by saga instance so two workers cannot mutate the same saga concurrently. It uses a bounded context inside the mutex.

`processSagaStep` validates the saga and step, sends execution or compensation requests, and persists state transitions.

## Result Processing

The coordinator consumes one aggregated result queue per cluster/affinity. `IN_EXECUTION` results are ignored because they mean an executor has accepted long-running work but has not completed it.

`processSagaStepExecutionResult` wraps DB operations in a transaction and records execution history/result state. It then advances the next step, starts compensation, or marks the saga terminal.

## Submitter Following

Submitter announcements trigger setup of submitter inbox/outbox queues. The coordinator can follow a submitter by publishing a `FOLLOW_SAGA_SUBMITTER` control payload.
