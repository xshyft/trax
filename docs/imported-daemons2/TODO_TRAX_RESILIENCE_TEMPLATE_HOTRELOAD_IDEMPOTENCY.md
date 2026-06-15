# TODO: TRAX Resilience, Saga Template Hot-Reload & Idempotency Testing

> **Status**: NOT STARTED
> **Created**: 2026-03-23
> **Short ID**: `TRTHI`
> **Feature**: Harden TRAX saga infrastructure against transient failures, enable live template management, and verify idempotency guarantees via E2E tests
> **Dependencies**: PostgreSQL LISTEN/NOTIFY infrastructure (already exists in `pkg/trax/store_psql.go`), RabbitMQ channel pool (`pkg/mq/common/channelpool.go`)
> **Enables**: Zero-downtime template updates, faster saga submitter recovery, verified idempotency guarantees
> **Related Docs**: `SAGA_COORDINATOR_MUTEX_TIMEOUT_FIX.md`, `RABBITMQ_RELIABILITY_REMEDIATION_TODO.md`, `RABBITMQ_TIER0_FIXES_TODO.md`, `TREASURY_IDEMPOTENCY.md`

---

## Table of Contents

1. [Overview](#overview)
2. [Phase 1: Coordinator IsReady() MQ Health Check](#phase-1-coordinator-isready-mq-health-check)
3. [Phase 2: Saga Submitter Exponential Backoff](#phase-2-saga-submitter-exponential-backoff)
4. [Phase 3: Saga Template Hot-Reload via LISTEN/NOTIFY](#phase-3-saga-template-hot-reload-via-listennotify)
   - [3a. Multi-Channel LISTEN Support](#3a-multi-channel-listen-support)
   - [3b. Store Interface: Update/Delete Template Methods](#3b-store-interface-updatedelete-template-methods)
   - [3c. PostgreSQL Store Implementation](#3c-postgresql-store-implementation)
   - [3d. In-Memory Store Implementation](#3d-in-memory-store-implementation)
   - [3e. Notification Fan-Out Broadcaster in Coordinator](#3e-notification-fan-out-broadcaster-in-coordinator)
   - [3f. Template Reload Loop with LISTEN/NOTIFY](#3f-template-reload-loop-with-listennotify)
   - [3g. Template Deletion: Step Un-initialization](#3g-template-deletion-step-un-initialization)
   - [3h. Wire Up LISTEN at Startup](#3h-wire-up-listen-at-startup)
   - [3i. REST Endpoints for Template CRUD on traxctrl](#3i-rest-endpoints-for-template-crud-on-traxctrl)
5. [Phase 4: TRAX Saga Idempotency E2E Tests](#phase-4-trax-saga-idempotency-e2e-tests)
   - [4a. TRAX E2E Tests (RDBMS Mode, cat1a)](#4a-trax-e2e-tests-rdbms-mode-cat1a)
   - [4b. LASER E2E Tests (EthBC Mode)](#4b-laser-e2e-tests-ethbc-mode)
6. [Phase 5: Unit Tests](#phase-5-unit-tests)
7. [Phase 6: Documentation Updates](#phase-6-documentation-updates)
8. [Verification & Testing](#verification--testing)
9. [Implementation Order & Dependencies](#implementation-order--dependencies)

---

## Overview

### Related: Operator escape hatch for BLOCKED sagas

**Force-mark compensated** is a separate, already-shipped resilience capability. When a saga wedges in `BLOCKED` because compensation cannot make progress on its own (the most common cause is a step trying to roll back a row another path already deleted), the operator can short-circuit the wedge:

- `PUT /saga-instances/{sagaInstanceId}/force-compensated` on traxctrl, with `cluster_id` + `reason` in the body. Refuses non-`BLOCKED` sagas at the store layer (`pkg/trax/store.go::ForceMarkSagaCompensated`).
- The `reason` lands on `compensation_reason` prefixed with `[FORCE-MARKED] ` so audit can distinguish operator overrides from organic compensation failures.
- Surfaced in sd_admin's Sagas page (button next to BLOCKED rows) via the `ForceMarkSagaCompensated` RPC on sdappgw / exchappgw. The UI demands a non-empty reason before submitting.

This complements but does not substitute for the resilience phases below — it deals with the *result* of unrecoverable compensation, not the underlying cause.

### Problem Statement

Three production resilience gaps and one testing gap have been identified:

1. **Saga submitter slow recovery**: When a TRAX coordinator is transiently unavailable (restart, MQ reconnection), the saga submitter sleeps the full `announcementInterval` (default 30s) before retrying. A 2-second coordinator blip causes up to 30 seconds of downtime. There is no exponential backoff for fast recovery.

2. **Coordinator reports ready with dead MQ**: `IsReady()` in `pkg/trax/coordinator.go:176-183` only checks `isRunning` and database health. The comment says "Message queue consumers are active" but there is NO actual MQ health check. A coordinator with a dead RabbitMQ connection will accept submitter announcements but cannot process messages, leading to stuck sagas.

3. **Saga template changes require coordinator restart**: New saga templates are picked up within 10 seconds via polling (`templateReloadInterval: 10*time.Second` at line 99). However, template **updates** and **deletions** are not supported at all — the store interface has no `UpdateSagaTemplate` or `DeleteSagaTemplate` methods. Additionally, the polling approach is wasteful when no changes occur and slow when immediate reaction is needed.

4. **Zero E2E test coverage for saga idempotency**: `SaveSagaInstanceIdempotently()` and `SaveSagaStepInstanceIdempotently()` have DB-level idempotency via UNIQUE constraints on `idempotent_key`, but no E2E tests verify this behavior. A regression in idempotency could cause duplicate saga execution with catastrophic financial consequences.

### Architecture Context

**Current LISTEN/NOTIFY usage** (for reference):
- Channel `'trax_saga_events'` is used for saga step state transitions (ExecutionCandidate, CompensationCandidate)
- Store method `Notify()` calls `pg_notify('trax_saga_events', payload)` in `store_psql.go:1150` and `:1180`
- `processSagaSteps()` in `coordinator.go:1348` reads from `store.Notifications()` channel
- The `pq.Listener` is created in `store_psql.go:102-167`

**Current template reload** (for reference):
- `reloadSagaTemplates()` at `coordinator.go:204-260` polls every 10s
- `startTemplateReloadLoop()` at `coordinator.go:262-288` runs the ticker
- `isStepInitialized()` / `markStepInitialized()` track which steps have MQ queues created
- Templates are NOT cached in memory — every saga execution fetches from DB via `GetSagaTemplate()`

**Current submitter announcement** (for reference):
- `StartAnnouncement()` at `submitter.go:216-329` runs infinite loop
- HTTP POST to coordinator `/saga-submitter/announce`
- On success: sets `readyToAcceptSagaSubmissionRequests = true`, populates `clusterIds`
- On failure (line 310-316): sets ready=false, logs warning, sleeps full `announcementInterval`
- `ResetForTesting()` at `submitter.go:734-741` clears state for E2E test isolation

---

## Phase 1: Coordinator IsReady() MQ Health Check

### Problem

`IsReady()` returns `c.isRunning && c.isDatabaseHealthy()` (coordinator.go:182). The RabbitMQ connection could be dead, but the coordinator still reports ready. This causes:
- Submitters announce to a coordinator that can't process messages
- Saga submissions are accepted but never executed
- No error feedback until saga timeout (default 15 minutes)

### 1.1 Add `isMQHealthy()` method

**File**: `pkg/trax/coordinator.go`

After `isDatabaseHealthy()` (line ~160), add:

```go
// isMQHealthy checks if the RabbitMQ connection is usable.
// Without a healthy MQ connection, the coordinator cannot process saga messages
// even if the database is available and the coordinator is running.
func (c *defaultSagaCoordinator) isMQHealthy() bool {
	if mqcommon.RabbitMQConnection == nil || mqcommon.RabbitMQConnection.IsClosed() {
		return false
	}
	return true
}
```

The import `mqcommon "qomet.tech/agora/daemons/pkg/mq/common"` already exists at line 17.

- [ ] 1.1.1 Add `isMQHealthy()` method to `defaultSagaCoordinator`
- [ ] 1.1.2 Update `IsReady()` to: `return c.isRunning && c.isDatabaseHealthy() && c.isMQHealthy()`
- [ ] 1.1.3 Update the comment on `IsReady()` to accurately reflect what it checks

### 1.2 Verify existing callers

`IsReady()` is called by:
- Coordinator announcement handler (when submitters announce)
- Health check endpoints

Both will correctly reject requests when MQ is down after this change.

- [ ] 1.2.1 Grep for all `IsReady()` callers and verify behavior is correct with MQ check added
- [ ] 1.2.2 Verify the health endpoint returns unhealthy when MQ is down

---

## Phase 2: Saga Submitter Exponential Backoff

### Problem

`StartAnnouncement()` (submitter.go:216-329) has a simple loop:
1. HTTP POST to announce
2. If success: process response
3. If failure: set not-ready, sleep `announcementInterval` (30s), repeat

A transient 2-second coordinator blip causes 30 seconds of submitter downtime. In production, this means 30 seconds where no sagas can be submitted from this service (e.g., accmgr, prtagent).

### 2.1 Extract helper methods from monolithic loop

**File**: `pkg/trax/submitter.go`

The current success path (lines 241-308) and failure path (lines 310-327) are inline in the loop. Refactor into:

```go
// announceToCoordinator performs a single HTTP POST to the coordinator's announce endpoint.
// Returns the HTTP response and any error.
func (s *defaultSagaSubmitter) announceToCoordinator(ctx context.Context, baseUrl string) (*http.Response, error) {
	postBody := PostAnnounceSagaSubmitterRequest{
		SagaSubmitterId: s.id,
	}
	postBodyBytes, err := json.Marshal(postBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal post body: %w", err)
	}
	return http.Post(baseUrl+"/saga-submitter/announce", "application/json", bytes.NewBuffer(postBodyBytes))
}

// processAnnouncementResponse decodes a successful announcement response,
// sets the submitter as ready, and starts inbox consumers for new clusters.
func (s *defaultSagaSubmitter) processAnnouncementResponse(ctx context.Context, resp *http.Response) {
	// Move lines 244-308 from StartAnnouncement into this method
	// (decode response, set readyToAcceptSagaSubmissionRequests, start consumers)
}
```

- [ ] 2.1.1 Extract `announceToCoordinator()` method
- [ ] 2.1.2 Extract `processAnnouncementResponse()` method
- [ ] 2.1.3 Update `StartAnnouncement()` to call these helpers

### 2.2 Add exponential backoff retry after failure

After the failure path in `StartAnnouncement()`, instead of immediately sleeping `announcementInterval`, add a fast retry loop:

```go
// On announcement failure, try fast retries with exponential backoff
// before falling back to the normal announcement interval
backoff := 1 * time.Second
maxBackoff := announcementInterval
maxRetries := 5

for retry := 0; retry < maxRetries; retry++ {
	common.L.Info(fmt.Sprintf(
		"fast-retrying announcement for saga submitter '%s' (attempt %d/%d, backoff %v)",
		s.id, retry+1, maxRetries, backoff), common.F(ctx)...)

	// Sleep with context cancellation support
	select {
	case <-ctx.Done():
		return
	case <-time.After(backoff):
	}

	resp, err := s.announceToCoordinator(ctx, traxCoordinatorBaseUrl)
	if err == nil && resp.StatusCode == 200 {
		s.processAnnouncementResponse(ctx, resp)
		resp.Body.Close()
		break // Success — exit backoff loop
	}
	if resp != nil {
		resp.Body.Close()
	}

	// Increase backoff: 1s → 2s → 4s → 8s → 16s (capped at announcementInterval)
	backoff = time.Duration(float64(backoff) * 2)
	if backoff > maxBackoff {
		backoff = maxBackoff
	}
}
// Then sleep the normal announcementInterval as before
```

**Recovery timeline improvement**: Worst case goes from 30s to 1s (first retry). Typical transient failure recovers in 1-3 seconds instead of 30.

- [ ] 2.2.1 Add exponential backoff retry loop in `StartAnnouncement()` failure path
- [ ] 2.2.2 Ensure each backoff sleep checks `ctx.Done()` to not block shutdown
- [ ] 2.2.3 Log each retry attempt with backoff duration for observability
- [ ] 2.2.4 After all retries exhausted, continue to normal `announcementInterval` sleep

### 2.3 Constants

Define at package level in `submitter.go`:

```go
const (
	announcementBackoffInitial    = 1 * time.Second
	announcementBackoffMultiplier = 2.0
	announcementBackoffMaxRetries = 5
)
```

- [ ] 2.3.1 Add backoff constants to `submitter.go`

---

## Phase 3: Saga Template Hot-Reload via LISTEN/NOTIFY

### 3a. Multi-Channel LISTEN Support

**File**: `pkg/trax/store_psql.go`

**Current limitation**: `Listen()` (lines 102-167) creates a `pq.Listener` on the first call and rejects subsequent calls with `"already listening on a channel"`. We need to listen on TWO channels: `trax_saga_events` (existing) and `trax_template_events` (new).

**Solution**: The `pq.Listener` natively supports calling `.Listen(channel)` multiple times. Refactor to track listened channels and allow adding more.

#### Changes to `psqlStore` struct

Add field:

```go
type psqlStore struct {
	// ... existing fields ...
	listenedChannels map[string]bool // NEW: tracks which channels we're listening on
}
```

Initialize in `NewPsqlStore()`:

```go
listenedChannels: make(map[string]bool),
```

#### Changes to `Listen()` (lines 102-167)

Replace the check on line 108 (`if s.listener != nil { return error }`):

```go
func (s *psqlStore) Listen(ctx context.Context, channel string) error {
	s.listenerMutex.Lock()
	defer s.listenerMutex.Unlock()

	// If already listening on this specific channel, skip
	if s.listenedChannels[channel] {
		common.L.Info(fmt.Sprintf("Already listening on channel: %s", channel))
		return nil
	}

	if s.listener == nil {
		// First call: create listener and start forwarding goroutine
		// (keep existing logic from lines 113-163)
		reportProblem := func(ev pq.ListenerEventType, err error) { /* ... */ }
		s.listener = pq.NewListener(s.connectionString, 10*time.Second, time.Minute, reportProblem)
		s.notifChan = make(chan *StoreNotification, 100)
		s.listenerCtx, s.listenerCancel = context.WithCancel(context.Background())
		// Start forwarding goroutine (existing logic)
		go func() { /* ... existing forwarding loop ... */ }()
	}

	// Add new channel to existing listener
	err := s.listener.Listen(channel)
	if err != nil {
		return fmt.Errorf("failed to listen on channel %s: %w", channel, err)
	}
	s.listenedChannels[channel] = true

	common.L.Info(fmt.Sprintf("Successfully started LISTEN on channel: %s (total channels: %d)",
		channel, len(s.listenedChannels)))
	return nil
}
```

#### Changes to `Unlisten()` (lines 169-195)

Only close the entire listener when the last channel is removed:

```go
func (s *psqlStore) Unlisten(ctx context.Context, channel string) error {
	s.listenerMutex.Lock()
	defer s.listenerMutex.Unlock()

	if s.listener == nil {
		return fmt.Errorf("not currently listening on any channel")
	}

	err := s.listener.Unlisten(channel)
	if err != nil {
		return fmt.Errorf("failed to unlisten on channel %s: %w", channel, err)
	}
	delete(s.listenedChannels, channel)

	// Only close the entire listener when no channels remain
	if len(s.listenedChannels) == 0 {
		s.listener.Close()
		s.listener = nil
		if s.listenerCancel != nil {
			s.listenerCancel()
		}
		if s.notifChan != nil {
			close(s.notifChan)
			s.notifChan = nil
		}
	}

	return nil
}
```

- [ ] 3a.1 Add `listenedChannels map[string]bool` to `psqlStore` struct
- [ ] 3a.2 Initialize `listenedChannels` in `NewPsqlStore()`
- [ ] 3a.3 Refactor `Listen()` to support multiple channels
- [ ] 3a.4 Refactor `Unlisten()` to only tear down on last channel
- [ ] 3a.5 Update the `Close()` method to clean up all listened channels

### 3b. Store Interface: Update/Delete Template Methods

**File**: `pkg/trax/store.go`

After line 35 (existing template methods), add 4 new methods:

```go
// Template management: update and delete
UpdateSagaTemplate(ctx context.Context, sagaTemplate *SagaTemplate) error
DeleteSagaTemplate(ctx context.Context, templateId string) error
UpdateSagaStepTemplate(ctx context.Context, sagaStepTemplate *SagaStepTemplate) error
DeleteSagaStepTemplate(ctx context.Context, templateId string) error
```

- [ ] 3b.1 Add `UpdateSagaTemplate` to `Store` interface
- [ ] 3b.2 Add `DeleteSagaTemplate` to `Store` interface
- [ ] 3b.3 Add `UpdateSagaStepTemplate` to `Store` interface
- [ ] 3b.4 Add `DeleteSagaStepTemplate` to `Store` interface

### 3c. PostgreSQL Store Implementation

**File**: `pkg/trax/store_psql.go`

#### `UpdateSagaTemplate`

```go
func (s *psqlStore) UpdateSagaTemplate(ctx context.Context, sagaTemplate *SagaTemplate) error {
	executor := s.getExecutor(ctx)

	labelsJSON, _ := json.Marshal(sagaTemplate.Labels)
	tagsJSON, _ := json.Marshal(sagaTemplate.Tags)
	metadataJSON, _ := json.Marshal(sagaTemplate.Metadata)
	stepIdsJSON, _ := json.Marshal(sagaTemplate.SagaStepTemplateIds)

	result, err := executor.ExecContext(ctx, `
		UPDATE trax.saga_templates
		SET display_name = $1, description = $2, labels = $3, tags = $4,
		    metadata = $5, saga_step_template_ids = $6, updated_at = CURRENT_TIMESTAMP
		WHERE template_id = $7`,
		sagaTemplate.DisplayName, sagaTemplate.Description,
		labelsJSON, tagsJSON, metadataJSON, stepIdsJSON,
		sagaTemplate.TemplateId)
	if err != nil {
		return fmt.Errorf("failed to update saga template: %w", err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return fmt.Errorf("saga template not found: %s", sagaTemplate.TemplateId)
	}

	// Notify coordinators of template change
	payload := fmt.Sprintf(`{"action":"update","type":"saga_template","template_id":"%s"}`, sagaTemplate.TemplateId)
	notifyQuery := "SELECT pg_notify('trax_template_events', $1)"
	_, _ = executor.ExecContext(ctx, notifyQuery, payload)

	return nil
}
```

#### `DeleteSagaTemplate`

```go
func (s *psqlStore) DeleteSagaTemplate(ctx context.Context, templateId string) error {
	executor := s.getExecutor(ctx)

	// Delete step templates first (FK constraint)
	_, err := executor.ExecContext(ctx,
		"DELETE FROM trax.saga_step_templates WHERE saga_template_id = $1", templateId)
	if err != nil {
		return fmt.Errorf("failed to delete step templates: %w", err)
	}

	result, err := executor.ExecContext(ctx,
		"DELETE FROM trax.saga_templates WHERE template_id = $1", templateId)
	if err != nil {
		return fmt.Errorf("failed to delete saga template: %w", err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return fmt.Errorf("saga template not found: %s", templateId)
	}

	// Notify coordinators of template deletion
	payload := fmt.Sprintf(`{"action":"delete","type":"saga_template","template_id":"%s"}`, templateId)
	notifyQuery := "SELECT pg_notify('trax_template_events', $1)"
	_, _ = executor.ExecContext(ctx, notifyQuery, payload)

	return nil
}
```

#### `UpdateSagaStepTemplate` and `DeleteSagaStepTemplate`

Same pattern as above, operating on `trax.saga_step_templates` table.

#### Add pg_notify to existing `SaveSagaTemplateIdempotently`

After a successful INSERT (when `isNew == true`), add:

```go
if isNew {
	payload := fmt.Sprintf(`{"action":"create","type":"saga_template","template_id":"%s"}`, sagaTemplate.TemplateId)
	notifyQuery := "SELECT pg_notify('trax_template_events', $1)"
	_, _ = executor.ExecContext(ctx, notifyQuery, payload)
}
```

Same for `SaveSagaStepTemplateIdempotently`.

- [ ] 3c.1 Implement `UpdateSagaTemplate` in `psqlStore` with pg_notify
- [ ] 3c.2 Implement `DeleteSagaTemplate` in `psqlStore` with cascade delete + pg_notify
- [ ] 3c.3 Implement `UpdateSagaStepTemplate` in `psqlStore` with pg_notify
- [ ] 3c.4 Implement `DeleteSagaStepTemplate` in `psqlStore` with pg_notify
- [ ] 3c.5 Add pg_notify to `SaveSagaTemplateIdempotently` on successful INSERT
- [ ] 3c.6 Add pg_notify to `SaveSagaStepTemplateIdempotently` on successful INSERT

### 3d. In-Memory Store Implementation

**File**: `pkg/trax/store_inmem.go`

```go
func (s *inMemoryStore) UpdateSagaTemplate(ctx context.Context, sagaTemplate *SagaTemplate) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, exists := s.sagaTemplates[sagaTemplate.TemplateId]; !exists {
		return fmt.Errorf("saga template not found: %s", sagaTemplate.TemplateId)
	}
	s.sagaTemplates[sagaTemplate.TemplateId] = sagaTemplate
	return nil
}

func (s *inMemoryStore) DeleteSagaTemplate(ctx context.Context, templateId string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, exists := s.sagaTemplates[templateId]; !exists {
		return fmt.Errorf("saga template not found: %s", templateId)
	}
	// Delete associated step templates first
	for id, step := range s.sagaStepTemplates {
		if step.SagaTemplateId == templateId {
			delete(s.sagaStepTemplates, id)
		}
	}
	delete(s.sagaTemplates, templateId)
	return nil
}

// Similar for UpdateSagaStepTemplate, DeleteSagaStepTemplate
```

- [ ] 3d.1 Implement `UpdateSagaTemplate` in `inMemoryStore`
- [ ] 3d.2 Implement `DeleteSagaTemplate` in `inMemoryStore` with cascade
- [ ] 3d.3 Implement `UpdateSagaStepTemplate` in `inMemoryStore`
- [ ] 3d.4 Implement `DeleteSagaStepTemplate` in `inMemoryStore`

### 3e. Notification Fan-Out Broadcaster in Coordinator

**File**: `pkg/trax/coordinator.go`

**Problem**: `processSagaSteps()` (line 1358) and `startTemplateReloadLoop()` (line 268) both need to read from `store.Notifications()`. But Go channels have single-consumer semantics — if one consumer reads a message, the other misses it.

**Solution**: Add a broadcaster that reads from the single `Notifications()` source and fans out to multiple subscriber channels, filtered by notification channel name.

#### New types and fields on `defaultSagaCoordinator`

```go
// Notification fan-out
type notifSubscription struct {
	channel string                   // PostgreSQL channel to filter on (e.g., "trax_saga_events")
	ch      chan *StoreNotification  // buffered channel for this subscriber
}

// Add to defaultSagaCoordinator struct:
notifSubs      []*notifSubscription
notifSubsMutex sync.RWMutex
```

#### `startNotificationBroadcaster()`

```go
func (c *defaultSagaCoordinator) startNotificationBroadcaster(ctx context.Context) {
	sourceChan := c.GetStore().Notifications()
	if sourceChan == nil {
		return // No LISTEN/NOTIFY support
	}

	c.wg.Add(1)
	go func() {
		defer c.wg.Done()
		for {
			select {
			case <-c.cancelChan:
				return
			case notif, ok := <-sourceChan:
				if !ok {
					return
				}
				c.notifSubsMutex.RLock()
				for _, sub := range c.notifSubs {
					if sub.channel == "" || sub.channel == notif.Channel {
						select {
						case sub.ch <- notif:
						default:
							// Drop if subscriber buffer is full
						}
					}
				}
				c.notifSubsMutex.RUnlock()
			}
		}
	}()
}
```

#### `subscribeNotifications()`

```go
func (c *defaultSagaCoordinator) subscribeNotifications(channel string) <-chan *StoreNotification {
	ch := make(chan *StoreNotification, 100)
	c.notifSubsMutex.Lock()
	c.notifSubs = append(c.notifSubs, &notifSubscription{channel: channel, ch: ch})
	c.notifSubsMutex.Unlock()
	return ch
}
```

#### Wire in `Start()`

In `Start()`, BEFORE starting `processSagaSteps()` and `startTemplateReloadLoop()`:

```go
// Start notification broadcaster (must be before consumers)
c.startNotificationBroadcaster(ctx)
```

#### Update `processSagaSteps()`

Replace line 1358:
```go
// OLD: notifChan := c.GetStore().Notifications()
// NEW:
notifChan := c.subscribeNotifications("trax_saga_events")
```

#### Clean up on `Stop()`

In `Stop()`, after `c.wg.Wait()`, close all subscriber channels:

```go
c.notifSubsMutex.Lock()
for _, sub := range c.notifSubs {
	close(sub.ch)
}
c.notifSubs = nil
c.notifSubsMutex.Unlock()
```

- [ ] 3e.1 Add `notifSubscription` type and fields to coordinator struct
- [ ] 3e.2 Implement `startNotificationBroadcaster()`
- [ ] 3e.3 Implement `subscribeNotifications(channel) <-chan *StoreNotification`
- [ ] 3e.4 Call `startNotificationBroadcaster()` in `Start()` before other goroutines
- [ ] 3e.5 Update `processSagaSteps()` to use `subscribeNotifications("trax_saga_events")`
- [ ] 3e.6 Clean up subscriber channels in `Stop()`

### 3f. Template Reload Loop with LISTEN/NOTIFY

**File**: `pkg/trax/coordinator.go`

#### Make `templateReloadInterval` configurable

In `NewSagaCoordinator()` (around line 99):

```go
// OLD: templateReloadInterval: 10 * time.Second,
// NEW:
templateReloadInterval := 10 * time.Second
if envVal := os.Getenv("TRAX_TEMPLATE_RELOAD_INTERVAL"); envVal != "" {
	if parsed, err := time.ParseDuration(envVal); err == nil && parsed > 0 {
		templateReloadInterval = parsed
	}
}
```

#### Update `startTemplateReloadLoop()` (lines 262-288)

Replace the ticker-only loop with a hybrid LISTEN/NOTIFY + fallback polling loop:

```go
func (c *defaultSagaCoordinator) startTemplateReloadLoop(ctx context.Context) {
	c.wg.Add(1)
	go func() {
		defer c.wg.Done()

		ticker := time.NewTicker(c.templateReloadInterval)
		defer ticker.Stop()

		// Subscribe to template change notifications
		notifChan := c.subscribeNotifications("trax_template_events")

		common.L.Info(fmt.Sprintf(
			"Started saga template reload loop (interval: %v, LISTEN/NOTIFY: %v)",
			c.templateReloadInterval, notifChan != nil), common.F(ctx)...)

		for {
			select {
			case <-c.cancelChan:
				common.L.Info("Template reload loop stopped", common.F(ctx)...)
				return

			case notif, ok := <-notifChan:
				if !ok {
					notifChan = nil
					continue
				}
				common.L.Info(fmt.Sprintf(
					"Template change notification received: %s", notif.Payload), common.F(ctx)...)

				// Parse notification to determine action
				var event struct {
					Action     string `json:"action"`
					Type       string `json:"type"`
					TemplateId string `json:"template_id"`
				}
				if err := json.Unmarshal([]byte(notif.Payload), &event); err == nil {
					if event.Action == "delete" && event.Type == "saga_template" {
						c.handleTemplateDeleted(ctx, event.TemplateId)
					}
				}

				// Reload templates regardless of action type
				if err := c.reloadSagaTemplates(ctx); err != nil {
					common.L.Error(fmt.Sprintf("Failed to reload saga templates: %v", err), common.F(ctx)...)
				}

			case <-ticker.C:
				// Fallback polling
				common.L.Debug("Checking for new saga templates (periodic)...", common.F(ctx)...)
				if err := c.reloadSagaTemplates(ctx); err != nil {
					common.L.Error(fmt.Sprintf("Failed to reload saga templates: %v", err), common.F(ctx)...)
				}
			}
		}
	}()
}
```

- [ ] 3f.1 Make `templateReloadInterval` configurable via `TRAX_TEMPLATE_RELOAD_INTERVAL` env var
- [ ] 3f.2 Update `startTemplateReloadLoop()` to subscribe to `"trax_template_events"`
- [ ] 3f.3 Handle notifications with action parsing (create/update/delete)
- [ ] 3f.4 Keep ticker as fallback polling

### 3g. Template Deletion: Step Un-initialization

**File**: `pkg/trax/coordinator.go`

When a template is deleted, its step MQ queues should be marked as un-initialized so they are cleaned up.

```go
// unmarkStepInitialized removes a step from the initialized set.
// This is called when a saga template is deleted.
func (c *defaultSagaCoordinator) unmarkStepInitialized(clusterId, sagaTemplateId, stepTemplateId string) {
	c.initializedStepsMutex.Lock()
	defer c.initializedStepsMutex.Unlock()
	key := fmt.Sprintf("%s:%s:%s", clusterId, sagaTemplateId, stepTemplateId)
	delete(c.initializedSteps, key)
}

// unmarkAllStepsForTemplate removes all steps for a given template from the initialized set.
func (c *defaultSagaCoordinator) unmarkAllStepsForTemplate(clusterId, sagaTemplateId string) {
	c.initializedStepsMutex.Lock()
	defer c.initializedStepsMutex.Unlock()
	prefix := fmt.Sprintf("%s:%s:", clusterId, sagaTemplateId)
	for key := range c.initializedSteps {
		if strings.HasPrefix(key, prefix) {
			delete(c.initializedSteps, key)
		}
	}
}

// handleTemplateDeleted is called when a template deletion notification is received.
func (c *defaultSagaCoordinator) handleTemplateDeleted(ctx context.Context, templateId string) {
	clusterIds, err := c.GetStore().ListClusterIds(ctx)
	if err != nil {
		common.L.Error(fmt.Sprintf("failed to list cluster IDs for template deletion cleanup: %v", err), common.F(ctx)...)
		return
	}
	for _, clusterId := range clusterIds {
		c.unmarkAllStepsForTemplate(clusterId, templateId)
		common.L.Info(fmt.Sprintf("Uninitialized steps for deleted template '%s' in cluster '%s'",
			templateId, clusterId), common.F(ctx)...)
	}
}
```

- [ ] 3g.1 Add `unmarkStepInitialized()` method
- [ ] 3g.2 Add `unmarkAllStepsForTemplate()` method
- [ ] 3g.3 Add `handleTemplateDeleted()` method
- [ ] 3g.4 Call `handleTemplateDeleted()` from template reload loop on delete notifications
- [ ] 3g.5 Add `"strings"` import if not already present

### 3h. Wire Up LISTEN at Startup

#### traxcoord.go

**File**: `pkg/daemons/traxcoord.go`

After the existing `traxStore.Listen(ctx, "trax_saga_events")` call (line 62):

```go
// Enable LISTEN/NOTIFY for template changes (hot-reload)
if err := traxStore.Listen(ctx, "trax_template_events"); err != nil {
	common.L.Warn(fmt.Sprintf("Failed to enable LISTEN/NOTIFY on channel 'trax_template_events': %v. Template changes will rely on polling.", err))
}
```

#### testing_post_setdbname.go

**File**: `pkg/daemons/traxcoord/api/v1/testing_post_setdbname.go`

After the existing Listen call for `trax_saga_events` (line 100):

```go
if err := newStore.Listen(ctx, "trax_template_events"); err != nil {
	common.L.Warn(fmt.Sprintf("Failed to enable LISTEN/NOTIFY on channel 'trax_template_events' for new store: %v", err))
}
```

- [ ] 3h.1 Add `trax_template_events` Listen in `traxcoord.go` startup
- [ ] 3h.2 Add `trax_template_events` Listen in `testing_post_setdbname.go`

### 3i. REST Endpoints for Template CRUD on traxctrl

**File**: `pkg/daemons/traxctrl/api/v1/api.go` (route registration)

Add routes after existing template routes (line 46):

```go
r.PUT(ApiV1UriPrefix+"/saga-templates/:sagaTemplateId", putSagaTemplate)
r.DELETE(ApiV1UriPrefix+"/saga-templates/:sagaTemplateId", deleteSagaTemplate)
r.PUT(ApiV1UriPrefix+"/saga-step-templates/:sagaStepTemplateId", putSagaStepTemplate)
r.DELETE(ApiV1UriPrefix+"/saga-step-templates/:sagaStepTemplateId", deleteSagaStepTemplate)
```

#### New file: `saga-templates_put.go`

```go
// putSagaTemplate updates an existing saga template
// @router /saga-templates/{sagaTemplateId} [put]
func putSagaTemplate(c *gin.Context) {
	sagaTemplateId := c.Param("sagaTemplateId")
	var req updateSagaTemplateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	sagaTemplate := &trax.SagaTemplate{
		TemplateId:          sagaTemplateId,
		DisplayName:         req.DisplayName,
		Description:         req.Description,
		Labels:              req.Labels,
		Tags:                req.Tags,
		Metadata:            req.Metadata,
		SagaStepTemplateIds: req.SagaStepTemplateIds,
	}
	if err := traxStore.UpdateSagaTemplate(c, sagaTemplate); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "saga template updated"})
}
```

#### New file: `saga-templates_delete.go`

```go
// deleteSagaTemplate deletes a saga template and its step templates
// @router /saga-templates/{sagaTemplateId} [delete]
func deleteSagaTemplate(c *gin.Context) {
	sagaTemplateId := c.Param("sagaTemplateId")
	if err := traxStore.DeleteSagaTemplate(c, sagaTemplateId); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "saga template deleted"})
}
```

Similar files for step templates.

- [ ] 3i.1 Create `saga-templates_put.go` with update endpoint
- [ ] 3i.2 Create `saga-templates_delete.go` with delete endpoint
- [ ] 3i.3 Create `saga-step-templates_put.go` with update endpoint
- [ ] 3i.4 Create `saga-step-templates_delete.go` with delete endpoint
- [ ] 3i.5 Add request types to `types.go`
- [ ] 3i.6 Register routes in `api.go`
- [ ] 3i.7 Add traxcli commands for template update/delete (optional, defer to future)

---

## Phase 4: TRAX Saga Idempotency E2E Tests

### 4a. TRAX E2E Tests (RDBMS Mode, cat1a)

**New file**: `tests/e2e/trax/idempotency_test.go`

These tests run in the existing TRAX E2E environment (RDBMS simulation, no blockchain).

#### Test 1: `TestSagaSubmissionIdempotency`

**Purpose**: Submit the same saga twice with the same origin_idempotency_key → verify only one saga instance is created and it reaches COMMITTED.

```go
func TestSagaSubmissionIdempotency(t *testing.T) {
	// Step 1: Ensure seven_step_sleep_saga template exists (from smoke_templates.sql)
	// Step 2: Submit saga via traxcli submitter with a fixed idempotency key
	//         Use: submitSevenStepSagaWithIdempotencyKey(t, "idemp-test-key-1")
	// Step 3: Wait for saga to complete (COMMITTED)
	// Step 4: Submit same saga again with SAME idempotency key
	// Step 5: Verify the second submission returns the SAME saga_instance_id
	//         OR is rejected/deduplicated
	// Step 6: Verify only 1 saga instance exists for this idempotency key
	//         Query: GET /saga-instances/list?cluster_id=...
	// Step 7: Verify the saga completed correctly (all 7 steps EXEC_DONE)
}
```

**Red path tests**:
- `TestSagaSubmissionIdempotency_DifferentKeys`: Two submissions with different keys → both execute → 2 separate saga instances, both COMMITTED
- `TestSagaSubmissionIdempotency_ConcurrentSubmissions`: Submit same saga 5x concurrently → only 1 saga instance created

#### Test 2: `TestSagaStepIdempotency`

**Purpose**: Verify no duplicate step instances exist after saga completion.

```go
func TestSagaStepIdempotency(t *testing.T) {
	// Step 1: Submit seven_step_sleep_saga
	// Step 2: Wait for COMMITTED
	// Step 3: List all step instances for this saga
	// Step 4: Verify exactly 7 step instances (no duplicates)
	// Step 5: Verify all step idempotent_keys are unique
}
```

#### Test 3: `TestSagaSubmissionIdempotency_AfterCompensation`

**Purpose**: After a saga is compensated, submitting again with the same key should still be idempotent (no re-execution).

```go
func TestSagaSubmissionIdempotency_AfterCompensation(t *testing.T) {
	// Step 1: Submit fail_at_step3_saga (uses compensation test templates)
	// Step 2: Wait for COMPENSATED state
	// Step 3: Re-submit with same idempotency key
	// Step 4: Verify no new saga instance created
}
```

- [ ] 4a.1 Create `tests/e2e/trax/idempotency_test.go`
- [ ] 4a.2 Implement `TestSagaSubmissionIdempotency` (green path)
- [ ] 4a.3 Implement `TestSagaSubmissionIdempotency_DifferentKeys` (green path)
- [ ] 4a.4 Implement `TestSagaSubmissionIdempotency_ConcurrentSubmissions` (red path)
- [ ] 4a.5 Implement `TestSagaStepIdempotency` (green path)
- [ ] 4a.6 Implement `TestSagaSubmissionIdempotency_AfterCompensation` (red path)
- [ ] 4a.7 Add helper: `submitSevenStepSagaWithIdempotencyKey(t, key string) string`
- [ ] 4a.8 Add test names to `E2E_CAT1A_PATTERN` in Makefile

### 4b. LASER E2E Tests (EthBC Mode)

**New file**: `tests/e2e/laser/trax_idempotency_ethbc_test.go`

These tests run in the full LASER E2E environment with Anvil blockchain, verifying idempotency in realistic deployment conditions.

#### Test 1: `TestTraxIdempotency_FundAccountDuplicate`

**Purpose**: Submit `fund_account` saga twice with same idempotency key → verify only one on-chain mint occurs.

```go
func TestTraxIdempotency_FundAccountDuplicate(t *testing.T) {
	// Step 1: Setup infrastructure (legal participant, cash token, etc.)
	// Step 2: Submit fund_account saga with idempotency key "fund-idemp-1"
	// Step 3: Wait for COMMITTED
	// Step 4: Record on-chain balance
	// Step 5: Submit SAME fund_account saga again with SAME idempotency key
	// Step 6: Verify saga is deduplicated (not re-executed)
	// Step 7: Verify on-chain balance unchanged (no double mint)
}
```

#### Test 2: `TestTraxIdempotency_TransferDuplicate`

**Purpose**: Submit `transfer_authorized_instrument` saga twice with same idempotency key → verify only one transfer occurs.

```go
func TestTraxIdempotency_TransferDuplicate(t *testing.T) {
	// Step 1: Setup infrastructure with funded accounts
	// Step 2: Submit transfer saga with idempotency key
	// Step 3: Wait for COMMITTED
	// Step 4: Record balances
	// Step 5: Re-submit with same key
	// Step 6: Verify balances unchanged
}
```

#### Test 3: `TestTraxIdempotency_SetupLegalParticipantDuplicate`

**Purpose**: Submit `setup_new_legal_participant` saga twice → verify no duplicate participant created.

```go
func TestTraxIdempotency_SetupLegalParticipantDuplicate(t *testing.T) {
	// Step 1: Submit setup_new_legal_participant
	// Step 2: Wait for COMMITTED
	// Step 3: Re-submit with same idempotency key
	// Step 4: Verify only 1 legal participant exists
	// Step 5: Verify only 1 legal structure exists
}
```

- [ ] 4b.1 Create `tests/e2e/laser/trax_idempotency_ethbc_test.go`
- [ ] 4b.2 Implement `TestTraxIdempotency_FundAccountDuplicate`
- [ ] 4b.3 Implement `TestTraxIdempotency_TransferDuplicate`
- [ ] 4b.4 Implement `TestTraxIdempotency_SetupLegalParticipantDuplicate`
- [ ] 4b.5 Create new E2E category (cat46 or similar) in Makefile for idempotency tests
- [ ] 4b.6 Update `docs/E2E_TEST_CATALOG.md` with new category

---

## Phase 5: Unit Tests

### 5.1 Submitter backoff unit tests

**File**: `pkg/trax/submitter_test.go` (new or existing)

```go
func TestAnnouncementExponentialBackoff(t *testing.T) {
	// Test that after failure, retry intervals follow: 1s, 2s, 4s, 8s, 16s(capped)
}

func TestAnnouncementBackoff_ContextCancellation(t *testing.T) {
	// Test that backoff loop exits when context is cancelled
}

func TestAnnouncementBackoff_RecoveryOnRetry(t *testing.T) {
	// Test that if coordinator becomes available during backoff, submitter recovers
}
```

- [ ] 5.1.1 Unit test for backoff interval progression
- [ ] 5.1.2 Unit test for context cancellation during backoff
- [ ] 5.1.3 Unit test for successful recovery during backoff

### 5.2 IsReady MQ health check unit tests

**File**: `pkg/trax/coordinator_test.go`

```go
func TestIsReady_MQConnectionClosed(t *testing.T) {
	// Mock RabbitMQConnection as closed → IsReady returns false
}

func TestIsReady_AllHealthy(t *testing.T) {
	// DB healthy + MQ healthy + running → IsReady returns true
}
```

- [ ] 5.2.1 Unit test for IsReady with closed MQ connection
- [ ] 5.2.2 Unit test for IsReady with all components healthy

### 5.3 Store template CRUD unit tests

**File**: `pkg/trax/store_test.go` (new or existing)

```go
func TestUpdateSagaTemplate(t *testing.T)      // Update existing template
func TestUpdateSagaTemplate_NotFound(t *testing.T) // Update non-existent template → error
func TestDeleteSagaTemplate(t *testing.T)      // Delete with cascade
func TestDeleteSagaTemplate_NotFound(t *testing.T) // Delete non-existent → error
func TestDeleteSagaTemplate_CascadeSteps(t *testing.T) // Verify step templates also deleted
// Same pattern for step template CRUD
```

- [ ] 5.3.1 Unit tests for UpdateSagaTemplate (green + red)
- [ ] 5.3.2 Unit tests for DeleteSagaTemplate (green + red + cascade)
- [ ] 5.3.3 Unit tests for UpdateSagaStepTemplate (green + red)
- [ ] 5.3.4 Unit tests for DeleteSagaStepTemplate (green + red)

### 5.4 Multi-channel LISTEN unit tests

**File**: `pkg/trax/store_psql_test.go`

```go
func TestListen_MultipleChannels(t *testing.T)     // Listen on 2 channels, verify both work
func TestListen_DuplicateChannel(t *testing.T)     // Listen on same channel twice → no error (idempotent)
func TestUnlisten_PartialCleanup(t *testing.T)     // Unlisten 1 of 2 → other still works
func TestUnlisten_FullCleanup(t *testing.T)        // Unlisten all → listener fully closed
```

- [ ] 5.4.1 Unit test for multi-channel LISTEN
- [ ] 5.4.2 Unit test for duplicate channel LISTEN
- [ ] 5.4.3 Unit test for partial Unlisten
- [ ] 5.4.4 Unit test for full Unlisten cleanup

### 5.5 Notification broadcaster unit tests

**File**: `pkg/trax/coordinator_test.go`

```go
func TestNotificationBroadcaster_FanOut(t *testing.T)     // 2 subscribers, each gets their channel's notifications
func TestNotificationBroadcaster_ChannelFilter(t *testing.T) // Subscriber only gets its channel
func TestNotificationBroadcaster_BufferFull(t *testing.T)  // Drops message when subscriber buffer is full
```

- [ ] 5.5.1 Unit test for fan-out to multiple subscribers
- [ ] 5.5.2 Unit test for channel filtering
- [ ] 5.5.3 Unit test for buffer-full drop behavior

---

## Phase 6: Documentation Updates

### 6.1 Update `docs/SUMMARY-FOR-AGENT.md`

Add a section about template hot-reload under the TRAX coordinator description:

```markdown
### Saga Template Hot-Reload
Saga templates and step templates can be managed at runtime without coordinator restart:
- **Create**: Templates are discovered within seconds via LISTEN/NOTIFY (fallback: 10s polling)
- **Update**: Changes are propagated immediately via `trax_template_events` PostgreSQL channel
- **Delete**: Coordinator unmarks associated step MQ queues for cleanup
- **REST API**: PUT/DELETE endpoints on traxctrl for template management
- **Environment**: `TRAX_TEMPLATE_RELOAD_INTERVAL` controls polling fallback interval (default: 10s)
```

### 6.2 Update `docs/E2E_TEST_CATALOG.md`

Add new categories:

```markdown
| Cat | Complexity | Description | Makefile Target |
|-----|------------|-------------|-----------------|
| 1a (updated) | ⭐⭐⭐⭐⭐ | TRAX Saga Orchestration + Idempotency | `trax-e2e-cat1` |
| 43 | ⭐⭐⭐⭐ | TRAX Idempotency (EthBC) | `laser-e2e-ethbc-cat46` |
```

### 6.3 Create/Update architecture notes

Update the "Future Considerations" section of `SAGA_COORDINATOR_MUTEX_TIMEOUT_FIX.md` to reference this TODO for MQ health check implementation.

- [ ] 6.1.1 Update `docs/SUMMARY-FOR-AGENT.md` with template hot-reload section
- [ ] 6.2.1 Update `docs/E2E_TEST_CATALOG.md` with idempotency test categories
- [ ] 6.3.1 Add cross-reference in `SAGA_COORDINATOR_MUTEX_TIMEOUT_FIX.md`

---

## Verification & Testing

### Phase 1 verification
```bash
# Existing TRAX tests must still pass
make trax-e2e-cat1
```

### Phase 2 verification
```bash
# Verify submitter recovers faster from coordinator blip
# The previously failing laser-e2e-ethbc-cat9 tests should pass
make laser-e2e-ethbc-cat9
```

### Phase 3 verification
```bash
# Manual test: insert template via SQL while coordinator running
# Verify step queues created within seconds (check coordinator logs for "Initializing new saga step")
docker exec -it laser-postgres-1 psql -U postgres -d agora_db -c "
  INSERT INTO trax.saga_templates (template_id, display_name, saga_step_template_ids)
  VALUES ('hot-reload-test', 'Hot Reload Test', '[\"step1\"]')
  ON CONFLICT DO NOTHING;
"
# Check coordinator logs:
docker logs laser-traxcoord1-1 2>&1 | grep "Template change notification"
```

### Phase 4 verification
```bash
# Run new idempotency tests
make trax-e2e-cat1  # includes new TRAX idempotency tests
make laser-e2e-ethbc-cat46  # new EthBC idempotency tests
```

### Phase 5 verification
```bash
make test  # unit tests
```

---

## Implementation Order & Dependencies

```
Phase 1 (MQ health check) ──────────────────── No dependencies, smallest change
    │
Phase 2 (Submitter backoff) ─────────────────── No dependencies, 1 file
    │
Phase 3a (Multi-channel LISTEN) ─────────────── Foundation for 3e, 3f, 3h
    │
    ├── Phase 3b+3c+3d (Store interface) ────── Can run in parallel with 3e
    │       │
    │       └── Phase 3i (REST endpoints) ───── Depends on 3b+3c+3d
    │
    └── Phase 3e (Notification broadcaster) ─── Depends on 3a
            │
            └── Phase 3f+3g (Template reload) ─ Depends on 3e
                    │
                    └── Phase 3h (Wiring) ───── Final wiring, depends on 3a+3f

Phase 4 (E2E tests) ────────────────────────── Independent, can start anytime
    ├── 4a (TRAX RDBMS) ────────────────────── No code dependencies
    └── 4b (LASER EthBC) ──────────────────── No code dependencies

Phase 5 (Unit tests) ───────────────────────── Write alongside each phase
Phase 6 (Docs) ─────────────────────────────── Write after implementation complete
```

**Estimated total effort**: 5-7 days

| Phase | Effort | Priority |
|-------|--------|----------|
| Phase 1 | 0.5 day | CRITICAL |
| Phase 2 | 1 day | CRITICAL |
| Phase 3 | 2-3 days | HIGH |
| Phase 4 | 1-2 days | HIGH |
| Phase 5 | 0.5 day | MEDIUM |
| Phase 6 | 0.5 day | LOW |

---

**Document Version**: 1.0
**Created**: 2026-03-23
**Author**: Claude Code Agent