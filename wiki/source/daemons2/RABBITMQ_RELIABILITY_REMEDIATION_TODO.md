# RabbitMQ Reliability & Robustness Remediation Plan

## Executive Summary

This document provides a comprehensive, step-by-step remediation plan for 50+ critical issues identified in the RabbitMQ implementation (`pkg/mq/`). The current implementation has **catastrophic data loss risks**, race conditions, memory leaks, and silent failures that compromise system reliability and data integrity.

**Impact Assessment:**
- **Tier 0 (Catastrophic)**: 6 issues causing data loss and corruption
- **Tier 1 (Critical)**: 8 issues causing system crashes and hangs
- **Tier 2 (High)**: 13 issues causing silent failures
- **Tier 3 (Medium/Architecture)**: 23+ issues affecting operations and maintainability

**Estimated Timeline:** 6-10 weeks for complete remediation
**Priority:** CRITICAL - Financial/Saga system cannot guarantee data integrity in current state

---

## Table of Contents

1. [Phase 1: Critical Data Loss Prevention (Tier 0)](#phase-1-critical-data-loss-prevention-tier-0)
2. [Phase 2: System Crash & Hang Prevention (Tier 1)](#phase-2-system-crash--hang-prevention-tier-1)
3. [Phase 3: Silent Failure Prevention (Tier 2)](#phase-3-silent-failure-prevention-tier-2)
4. [Phase 4: Architectural Refactoring (Tier 3)](#phase-4-architectural-refactoring-tier-3)
5. [Phase 5: Testing Infrastructure](#phase-5-testing-infrastructure)
6. [Phase 6: Monitoring & Observability](#phase-6-monitoring--observability)
7. [Phase 7: High Availability Configuration](#phase-7-high-availability-configuration)
8. [Phase 8: Documentation & Best Practices](#phase-8-documentation--best-practices)
9. [Phase 9: Migration Strategy](#phase-9-migration-strategy)
10. [Phase 10: Performance Optimization](#phase-10-performance-optimization)
11. [Phase 11: Validation & Sign-off](#phase-11-validation--sign-off)

---

## Recently Completed Fixes (November 2025)

The following critical issues have been addressed as part of the saga coordinator mutex timeout investigation:

### Fix 1: Callback Timeout Wrapper (T1-013 Partial Mitigation)

**Issue**: Goroutine leaks in RabbitMQ message handlers
**File**: `pkg/common/helpers.go:590-624`
**Status**: ✅ COMPLETED (November 24, 2025)

**Implementation**:
Added 25-second timeout wrapper around all RabbitMQ message handler callbacks to detect long-running operations:

```go
callbackWithTimeout := func(delivery amqp.Delivery) {
    done := make(chan struct{})
    startTime := time.Now()

    go func() {
        defer close(done)
        callback(delivery)
    }()

    select {
    case <-done:
        // Callback completed successfully
    case <-time.After(25 * time.Second):
        duration := time.Since(startTime)
        common.L.Warn("potential goroutine leak: callback took longer than 25s to complete",
            map[string]interface{}{
                "callback_duration": duration.String(),
                "queue":            queueName,
            })
    }
}
```

**Impact**:
- Provides visibility into long-running callbacks
- Helps identify goroutine leaks early
- Does NOT kill long-running goroutines (design decision to prevent data loss)
- Enables monitoring and alerting on stuck message handlers

**Related Documentation**: See `docs/SAGA_COORDINATOR_MUTEX_TIMEOUT_FIX.md` for complete context

### Fix 2: RabbitMQ QoS Prefetch Limit (T2-022 Complete Fix)

**Issue**: Global QoS too high causing consumer overload
**File**: `pkg/common/helpers.go:699`
**Status**: ✅ COMPLETED (November 24, 2025)

**Previous State**: No QoS prefetch limit (default unlimited)

**Implementation**:
```go
// Set QoS prefetch to 1 to limit concurrent message processing
err = channel.Qos(
    1,     // prefetchCount - only consume 1 message at a time
    0,     // prefetchSize
    false, // global
)
```

**Impact**:
- Prevents single consumer from hoarding messages
- Ensures fair distribution across multiple consumers
- Reduces memory pressure on individual consumers
- Prevents message handler queue buildup

**Performance**: Slight reduction in throughput per consumer, but significantly improved fairness and stability

### Fix 3: RabbitMQ Consumer Cleanup

**Issue**: Stale consumers from concurrent test runs overwhelming RabbitMQ broker
**Status**: ✅ COMPLETED (November 24, 2025)

**Problem Discovery**:
Multiple concurrent E2E test runs created 6000+ stale consumers (75 per queue × ~80 queues), causing:
- Publisher confirmation timeouts (30+ seconds)
- Message delivery delays
- Broker resource exhaustion

**Before Cleanup**:
```bash
$ docker exec laser-rabbitmq-1 rabbitmqctl list_queues name messages consumers
q_e2e_test_cluster_traxcoord_saga_submitter_accmgr-e2e-test_inbox    0    75
q_e2e_test_cluster_trax_coordinator_1_saga_process_new_...          0    75
...
Total consumers: ~6000
```

**Fix Applied**:
```bash
$ docker restart laser-rabbitmq-1
```

**After Cleanup**:
```bash
$ docker exec laser-rabbitmq-1 rabbitmqctl list_queues name messages consumers
q_e2e_test_cluster_traxcoord_saga_submitter_accmgr-e2e-test_inbox    0    1
...
Total consumers: 143 (97% reduction)
```

**Impact**:
- Publisher confirmations now complete in milliseconds instead of timing out
- Clean test environment for reliable E2E testing
- Eliminated RabbitMQ broker overload during test runs

**Prevention Strategy**:
- Restart RabbitMQ before each test run
- Implement proper consumer cleanup on container shutdown
- Monitor consumer counts in production
- Add health checks to detect stale consumers

### Saga Coordinator Context Issue

**Issue**: Saga coordinator mutex operations exceeding TTL causing invalid state transitions
**File**: `pkg/trax/coordinator.go:1272-1334`
**Status**: ✅ COMPLETED (November 24, 2025)

**Problem**: Operations inside Redis mutex callback taking longer than 60-second TTL, allowing multiple goroutines to process same saga concurrently.

**Fix**: Added 50-second timeout context inside mutex callback to ensure operations complete before TTL expiry.

**Related Documentation**: See `docs/SAGA_COORDINATOR_MUTEX_TIMEOUT_FIX.md` for complete analysis and implementation details.

**Note**: This fix is not part of the RabbitMQ remediation plan but was discovered during investigation of goroutine leak warnings (T1-013).

### Fix 4: Topic Exchange Routing (February 12, 2026)

**Issue**: Per-step fanout queues creating excessive queue/consumer counts
**File**: `pkg/mq/common/helpers.go`, `pkg/trax/coordinator.go`
**Status**: ✅ COMPLETED (February 12, 2026)

**Problem**: Each saga step had its own fanout exchange and dedicated queue, resulting in ~2000 queues and ~2000 exchanges, which contributed to broker overload and resource exhaustion.

**Fix**: Replaced per-step fanout queues with a **topic exchange routing** model:
- Single per-cluster topic exchange replaces all per-step fanout exchanges (~2000 exchanges -> 1)
- Messages routed via routing keys: `saga.{affinity}.step.{step_name}`
- Queue count reduced from ~2000 to ~10 (one per coordinator affinity + one per executor step template)
- New MQ functions: `InitTopicExchange()`, `InitQueueWithTopicBinding()`, `PublishWithRoutingKey()`
- Coordinators bind results queues with wildcard pattern to consume relevant messages
- Executors bind shared inbox queues with wildcard affinity binding
- Channel pool default reduced from 1000 to 100 with 20% pre-populate
- `DrainPool()` deadlock fixed: close channels in background goroutine with 5s timeout

**Impact**:
- ~99.5% reduction in queue count (~2000 -> ~10)
- ~99.95% reduction in exchange count (~2000 -> 1)
- Dramatically reduced broker resource pressure
- Simplified MQ topology
- Better alignment with RabbitMQ best practices
- Reduced surface area for T0-002 (shared channel) issues

### Fix 5: Coordinator Infinite Requeue Loop (February 13, 2026)

**Issue**: Permanent errors in result queue consumer causing infinite NACK+requeue loops
**File**: `pkg/trax/coordinator.go`, `pkg/trax/const.go`, `pkg/trax/store_inmem.go`, `pkg/trax/store_psql.go`
**Status**: ✅ COMPLETED (February 13, 2026)

**Problem**: When the coordinator received a result message for a saga instance or step instance that no longer existed in the database (stale message), it would NACK+requeue the message. Since the instance would never exist again, this created an infinite requeue loop, consuming CPU and blocking the message queue.

**Fix**:
1. Added sentinel errors `ErrSagaInstanceNotFound` and `ErrSagaStepInstanceNotFound` in `pkg/trax/const.go`
2. Both in-memory and PostgreSQL stores return these sentinel errors for not-found cases
3. Coordinator uses `errors.Is()` to detect not-found errors and ACK+drops the message
4. Added state filtering: coordinator ignores results for sagas in terminal states (COMPLETED, FAILED, COMPENSATED, COMPENSATION_FAILED)

**Impact**:
- Eliminates infinite message requeue loops
- Prevents CPU burn from processing stale messages
- Directly addresses T0-005 pattern (typed error checking instead of string comparison)
- Related to T0-006 pattern (prevents infinite loops)

### Fix 6: Sub-Saga & Compensation MQ Flows (February 13, 2026)

**Issue**: New MQ message flows for sub-saga orchestration and compensation
**File**: `pkg/trax/coordinator.go`, `pkg/clis/traxcli/executor.go`
**Status**: ✅ COMPLETED (February 13, 2026)

**New Capabilities**:
- Sub-saga executors publish results through the same topic exchange
- Cascading compensation triggers coordinator-to-coordinator MQ messages
- `SagaContext` injection allows child sagas to reference parent saga/step
- New E2E tests: `compensation_test.go`, `deep_sub_saga_test.go` (13/13 TRAX tests passing)

---

## Issue Reference Map

### Tier 0 - Catastrophic (Data Loss & Corruption)

| ID | Issue | Location | Impact |
|----|-------|----------|--------|
| T0-001 | No publisher confirms | `pkg/mq/common/helpers.go:84-128` | Messages silently lost |
| T0-002 | Shared global channel (race condition) | `pkg/mq/common/rabbitmq.go:13` | Channel state corruption |
| T0-003 | Channel replacement race | `pkg/mq/common/rabbitmq.go:31-47` | Operations on closed channel |
| T0-004 | Unchecked ACK/NACK errors | `pkg/mq/common/helpers.go:299-320` | Duplicate/lost messages |
| T0-005 | Error string comparison | `pkg/mq/common/helpers.go:115` | False negatives on errors |
| T0-006 | RepublishNack infinite loop | `pkg/mq/common/helpers.go:303-307` | Message explosion |

### Tier 1 - Critical (System Crashes & Hangs)

| ID | Issue | Location | Impact |
|----|-------|----------|--------|
| T1-007 | Unbounded reconnect listeners (memory leak) | `pkg/mq/common/rabbitmq.go:15,75` | Memory exhaustion |
| T1-008 | Channel notification race | `pkg/mq/common/helpers.go:256-257` | Consumer hangs forever |
| T1-009 | Missing consumer cancellation monitoring | N/A | Silent consumer death |
| T1-010 | Double channel close panic | `pkg/mq/common/helpers.go:274,287` | Service crash |
| T1-011 | Dropped reconnect notifications | `pkg/mq/common/rabbitmq.go:58-63` | Permanent consumer breakage |
| T1-012 | Context inheritance bug | `pkg/mq/common/helpers.go:176` | Lost parent context |
| T1-013 | Goroutine leaks | `pkg/mq/common/helpers.go:181,261` | Resource exhaustion |
| T1-014 | Blocking channel send | `pkg/mq/common/helpers.go:265` | Goroutine deadlock |

### Tier 2 - High (Silent Failures)

| ID | Issue | Location | Impact |
|----|-------|----------|--------|
| T2-015 | No Dead Letter Exchange | N/A | Poison messages dropped |
| T2-016 | No message TTL | N/A | Queues grow unbounded |
| T2-017 | No queue max length | N/A | Memory explosion |
| T2-018 | No idempotency | N/A | Duplicate processing |
| T2-019 | No message ordering | N/A | Out-of-order saga steps |
| T2-020 | Redelivered flag ignored | N/A | Cannot detect retries |
| T2-021 | No priority queues | N/A | Critical messages delayed |
| T2-022 | Global QoS too high (1000) | `pkg/mq/init.go:24` | Consumer overwhelmed |
| T2-023 | QoS on wrong channel | `pkg/mq/init.go:20-27` | QoS has no effect |
| T2-024 | No publisher returns | N/A | Unroutable messages lost |
| T2-025 | No flow control monitoring | N/A | Mysterious publish failures |
| T2-026 | Heartbeat too long (60s) | `pkg/mq/init.go:75` | Slow partition detection |
| T2-027 | Connection timeout too long (300s) | `pkg/mq/init.go:76-78` | 5-minute hangs |

---

## Phase 1: Critical Data Loss Prevention (Tier 0)

**Goal:** Eliminate all catastrophic data loss and corruption issues
**Timeline:** Week 1-2
**Priority:** HIGHEST

### 1.1 Implement Publisher Confirms (T0-001)

**Current State:** Messages published without confirmation - broker can lose them silently
**Files:** `pkg/mq/common/helpers.go:84-128`

- [ ] 1.1.1 Create new publisher interface with confirms:
  ```go
  // File: pkg/mq/common/publisher.go
  package mqcommon

  import (
      "context"
      "fmt"
      "sync"
      "time"
      amqp "github.com/rabbitmq/amqp091-go"
  )

  // PublisherWithConfirms wraps a channel with publisher confirmation support
  type PublisherWithConfirms struct {
      ch            *amqp.Channel
      confirmChan   chan amqp.Confirmation
      nextSeqNo     uint64
      mu            sync.Mutex
      confirmTimeout time.Duration
  }

  // NewPublisherWithConfirms creates a publisher with confirms enabled
  func NewPublisherWithConfirms(ch *amqp.Channel) (*PublisherWithConfirms, error) {
      if err := ch.Confirm(false); err != nil {
          return nil, fmt.Errorf("failed to enable publisher confirms: %w", err)
      }

      confirmChan := ch.NotifyPublish(make(chan amqp.Confirmation, 100))

      return &PublisherWithConfirms{
          ch:             ch,
          confirmChan:    confirmChan,
          nextSeqNo:      1,
          confirmTimeout: 30 * time.Second,
      }, nil
  }

  // PublishWithConfirm publishes a message and waits for broker confirmation
  func (p *PublisherWithConfirms) PublishWithConfirm(
      ctx context.Context,
      exchange, routingKey string,
      mandatory, immediate bool,
      msg amqp.Publishing,
  ) error {
      p.mu.Lock()
      seqNo := p.nextSeqNo
      p.nextSeqNo++
      p.mu.Unlock()

      // Publish message
      if err := p.ch.PublishWithContext(ctx, exchange, routingKey, mandatory, immediate, msg); err != nil {
          return fmt.Errorf("publish failed: %w", err)
      }

      // Wait for confirmation with timeout
      select {
      case confirm := <-p.confirmChan:
          if confirm.DeliveryTag != seqNo {
              return fmt.Errorf("sequence number mismatch: expected %d, got %d", seqNo, confirm.DeliveryTag)
          }
          if !confirm.Ack {
              return fmt.Errorf("message nacked by broker (seq: %d)", seqNo)
          }
          return nil
      case <-time.After(p.confirmTimeout):
          return fmt.Errorf("confirmation timeout after %v (seq: %d)", p.confirmTimeout, seqNo)
      case <-ctx.Done():
          return fmt.Errorf("context cancelled while waiting for confirm: %w", ctx.Err())
      }
  }
  ```

- [ ] 1.1.2 Update `Publish()` function to use confirms:
  ```go
  // File: pkg/mq/common/helpers.go
  // Replace Publish() function (lines 84-128)

  func Publish(ctx context.Context, destName, messageType, contentType string, body []byte) error {
      maxRetries := 3
      var lastErr error

      for attempt := 0; attempt < maxRetries; attempt++ {
          ch := GetChannel()
          if ch == nil {
              lastErr = fmt.Errorf("rabbitmq channel is nil")
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          // Create publisher with confirms
          publisher, err := NewPublisherWithConfirms(ch)
          if err != nil {
              common.L.Warn(
                  fmt.Sprintf("failed to create publisher with confirms: %v, retrying (attempt %d/%d)...", err, attempt+1, maxRetries),
                  common.F(ctx)...)
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          // Publish with confirmation
          err = publisher.PublishWithConfirm(
              ctx,
              destName, // exchange
              "",       // routing key
              false,    // mandatory
              false,    // immediate
              amqp.Publishing{
                  DeliveryMode: amqp.Persistent,
                  ContentType:  contentType,
                  Type:         messageType,
                  Body:         body,
                  Timestamp:    time.Now(),
                  MessageId:    generateMessageID(), // Add message ID for tracing
              },
          )

          if err == nil {
              return nil
          }

          // Check if error is retryable
          if isRetryableError(err) {
              lastErr = err
              common.L.Warn(
                  fmt.Sprintf("publish failed (retryable): %v, retrying (attempt %d/%d)...", err, attempt+1, maxRetries),
                  common.F(ctx)...)
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          // Non-retryable error
          return fmt.Errorf("publish failed (non-retryable): %w", err)
      }

      return fmt.Errorf("publish failed after %d attempts: %w", maxRetries, lastErr)
  }

  // Helper function to check if error is retryable
  func isRetryableError(err error) bool {
      if err == nil {
          return false
      }

      errStr := err.Error()
      retryableErrors := []string{
          "channel/connection is not open",
          "connection closed",
          "channel closed",
          "timeout",
          "context deadline exceeded",
      }

      for _, retryable := range retryableErrors {
          if strings.Contains(errStr, retryable) {
              return true
          }
      }

      // Also check for specific error types
      if err == amqp.ErrClosed {
          return true
      }

      return false
  }

  // Helper to generate unique message IDs
  func generateMessageID() string {
      return fmt.Sprintf("%d-%s", time.Now().UnixNano(), common.SecureRandomString(8))
  }
  ```

- [ ] 1.1.3 Add unit tests for publisher confirms:
  ```go
  // File: pkg/mq/common/publisher_test.go
  package mqcommon

  import (
      "context"
      "testing"
      "time"
  )

  func TestPublisherWithConfirms(t *testing.T) {
      // Test will use mock channel or integration test against real RabbitMQ
      // Implementation depends on test strategy chosen in Phase 5
  }
  ```

- [ ] 1.1.4 Update all publish call sites to handle confirmation errors
- [ ] 1.1.5 Test with actual RabbitMQ broker
- [ ] 1.1.6 Verify confirmations work across reconnections

### 1.2 Fix Shared Channel Race Condition (T0-002)

**Current State:** Single global channel shared by all goroutines - NOT THREAD-SAFE
**Files:** `pkg/mq/common/rabbitmq.go:13`, `pkg/mq/common/helpers.go`

- [ ] 1.2.1 Design channel management strategy (choose one):

  **Option A: Channel Pool (Recommended)**
  - Pros: Efficient resource usage, controlled concurrency
  - Cons: More complex implementation

  **Option B: Channel-per-Operation**
  - Pros: Simple, no contention
  - Cons: Higher overhead

  **Option C: Channel-per-Goroutine**
  - Pros: Thread-local, no locks
  - Cons: Hard to track lifecycle

  **Decision:** [Document chosen approach here]

- [ ] 1.2.2 Implement Channel Pool (if Option A chosen):
  ```go
  // File: pkg/mq/common/channelpool.go
  package mqcommon

  import (
      "errors"
      "fmt"
      "sync"
      amqp "github.com/rabbitmq/amqp091-go"
  )

  // ChannelPool manages a pool of RabbitMQ channels
  type ChannelPool struct {
      conn        *amqp.Connection
      channels    chan *amqp.Channel
      maxChannels int
      mu          sync.Mutex
      closed      bool
  }

  // NewChannelPool creates a new channel pool
  func NewChannelPool(conn *amqp.Connection, maxChannels int) (*ChannelPool, error) {
      if maxChannels <= 0 {
          maxChannels = 10 // Default
      }

      pool := &ChannelPool{
          conn:        conn,
          channels:    make(chan *amqp.Channel, maxChannels),
          maxChannels: maxChannels,
          closed:      false,
      }

      // Pre-populate pool with initial channels
      for i := 0; i < maxChannels/2; i++ {
          ch, err := conn.Channel()
          if err != nil {
              return nil, fmt.Errorf("failed to create initial channel: %w", err)
          }
          pool.channels <- ch
      }

      return pool, nil
  }

  // GetChannel retrieves a channel from the pool (or creates new one)
  func (p *ChannelPool) GetChannel() (*amqp.Channel, error) {
      p.mu.Lock()
      if p.closed {
          p.mu.Unlock()
          return nil, errors.New("channel pool is closed")
      }
      p.mu.Unlock()

      select {
      case ch := <-p.channels:
          // Verify channel is still open
          if ch.IsClosed() {
              // Try to get another one
              return p.GetChannel()
          }
          return ch, nil
      default:
          // Pool empty, create new channel
          return p.conn.Channel()
      }
  }

  // ReturnChannel returns a channel to the pool
  func (p *ChannelPool) ReturnChannel(ch *amqp.Channel) {
      if ch == nil || ch.IsClosed() {
          return
      }

      p.mu.Lock()
      if p.closed {
          p.mu.Unlock()
          ch.Close()
          return
      }
      p.mu.Unlock()

      select {
      case p.channels <- ch:
          // Returned to pool
      default:
          // Pool full, close channel
          ch.Close()
      }
  }

  // Close closes all channels in the pool
  func (p *ChannelPool) Close() error {
      p.mu.Lock()
      defer p.mu.Unlock()

      if p.closed {
          return nil
      }

      p.closed = true
      close(p.channels)

      // Close all channels in pool
      for ch := range p.channels {
          ch.Close()
      }

      return nil
  }
  ```

- [ ] 1.2.3 Update global state to use pool:
  ```go
  // File: pkg/mq/common/rabbitmq.go
  // Replace global variables (lines 10-17)

  var (
      RabbitMQURL        string = ""
      RabbitMQConnection *amqp.Connection
      RabbitMQChannelPool *ChannelPool  // CHANGED: Use pool instead of single channel
      channelMutex       sync.RWMutex
      reconnectListeners []chan struct{}
      reconnectMutex     sync.Mutex
  )
  ```

- [ ] 1.2.4 Update `Publish()` to use pool:
  ```go
  func Publish(ctx context.Context, destName, messageType, contentType string, body []byte) error {
      maxRetries := 3
      var lastErr error

      for attempt := 0; attempt < maxRetries; attempt++ {
          // Get channel from pool
          ch, err := RabbitMQChannelPool.GetChannel()
          if err != nil {
              lastErr = err
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          // Use defer to ensure channel is returned
          func() {
              defer RabbitMQChannelPool.ReturnChannel(ch)

              // ... publish logic ...
          }()

          // ... rest of retry logic ...
      }
  }
  ```

- [ ] 1.2.5 Update consumers to get dedicated channels:
  ```go
  // Each consumer gets its own channel - NOT from pool
  // Update ConsumeQueueWithOptionsAsync to create dedicated channel
  ```

- [ ] 1.2.6 Test concurrent publishes (1000+ goroutines)
- [ ] 1.2.7 Verify no race conditions with `go test -race`

### 1.3 Fix Channel Replacement Race (T0-003)

**Current State:** Channels replaced while in use by other goroutines
**Files:** `pkg/mq/common/rabbitmq.go:31-47`, `pkg/mq/common/helpers.go:199`

- [ ] 1.3.1 Change from global channel to pool (completed in 1.2)
- [ ] 1.3.2 Remove `UpdateChannel()` function (no longer needed with pool)
- [ ] 1.3.3 Update reconnection logic to recreate pool:
  ```go
  // File: pkg/mq/init.go
  // In reconnection handler (lines 146-170)

  func reconnectHandler(ctx context.Context) {
      for {
          closeCh := make(chan *amqp.Error)
          mqcommon.RabbitMQConnection.NotifyClose(closeCh)

          reason, ok := <-closeCh
          if !ok {
              break
          }

          common.L.Warn(fmt.Sprintf("connection closed: %v, reconnecting...", reason), common.F(ctx)...)

          // Close old pool
          if mqcommon.RabbitMQChannelPool != nil {
              mqcommon.RabbitMQChannelPool.Close()
          }

          // Reconnect
          for attempt := 1; ; attempt++ {
              time.Sleep(calculateBackoff(attempt))

              if err := initConn(ctx); err != nil {
                  common.L.Warn(fmt.Sprintf("reconnect attempt %d failed: %v", attempt, err), common.F(ctx)...)
                  continue
              }

              if err := initQueues(ctx); err != nil {
                  common.L.Warn(fmt.Sprintf("queue init failed: %v", err), common.F(ctx)...)
                  continue
              }

              // Recreate channel pool
              pool, err := mqcommon.NewChannelPool(mqcommon.RabbitMQConnection, 20)
              if err != nil {
                  common.L.Warn(fmt.Sprintf("failed to create channel pool: %v", err), common.F(ctx)...)
                  continue
              }

              mqcommon.RabbitMQChannelPool = pool

              common.L.Info("reconnection successful, notifying consumers...", common.F(ctx)...)
              mqcommon.NotifyReconnect()
              break
          }
      }
  }

  // Exponential backoff with jitter
  func calculateBackoff(attempt int) time.Duration {
      baseDelay := 1 * time.Second
      maxDelay := 60 * time.Second

      delay := time.Duration(1<<uint(attempt-1)) * baseDelay
      if delay > maxDelay {
          delay = maxDelay
      }

      // Add jitter (0-25% of delay)
      jitter := time.Duration(rand.Int63n(int64(delay / 4)))
      return delay + jitter
  }
  ```

- [ ] 1.3.4 Test reconnection under load
- [ ] 1.3.5 Verify no operations fail during reconnection

### 1.4 Check All ACK/NACK/Publish Errors (T0-004)

**Current State:** 5 TODO comments for unchecked critical operations
**Files:** `pkg/mq/common/helpers.go:299-320`

- [ ] 1.4.1 Replace line 300 TODO - Check ACK errors:
  ```go
  // Replace line 300:
  // m.Ack(false)

  if err := m.Ack(false); err != nil {
      common.L.Error(
          fmt.Sprintf("[%s] CRITICAL: Failed to ACK message (delivery_tag=%d): %v - message will be redelivered",
              queueName, m.DeliveryTag, err),
          common.F(ctx)...)
      // Track metrics for ACK failures
      incrementMetric("rabbitmq.ack.errors", map[string]string{
          "queue": queueName,
          "reason": "ack_failed",
      })
  }
  ```

- [ ] 1.4.2 Replace line 305 TODO - Check ACK in republish path:
  ```go
  // Replace line 305:
  // m.Ack(false)

  if err := m.Ack(false); err != nil {
      common.L.Error(
          fmt.Sprintf("[%s] CRITICAL: Failed to ACK before republish (delivery_tag=%d): %v - message may duplicate",
              queueName, m.DeliveryTag, err),
          common.F(ctx)...)
      // Don't republish if ACK failed - would create duplicates
      return
  }
  ```

- [ ] 1.4.3 Replace line 307 TODO - Check Publish error in republish:
  ```go
  // Replace line 307:
  // Publish(ctx, queueName, m.Type, m.ContentType, m.Body)

  if err := Publish(ctx, queueName, m.Type, m.ContentType, m.Body); err != nil {
      common.L.Error(
          fmt.Sprintf("[%s] CRITICAL: Failed to republish message: %v - message lost!",
              queueName, err),
          common.F(ctx)...)

      // Send to DLX if configured
      if dlxExchange := getDLXForQueue(queueName); dlxExchange != "" {
          if err := publishToDLX(ctx, dlxExchange, m); err != nil {
              common.L.Error(
                  fmt.Sprintf("[%s] CATASTROPHIC: Failed to republish to DLX: %v", queueName, err),
                  common.F(ctx)...)
          }
      }

      incrementMetric("rabbitmq.republish.errors", map[string]string{
          "queue": queueName,
      })
  }
  ```

- [ ] 1.4.4 Replace line 311 TODO - Check NACK error:
  ```go
  // Replace line 311:
  // m.Nack(false, true)

  if err := m.Nack(false, true); err != nil {
      common.L.Error(
          fmt.Sprintf("[%s] CRITICAL: Failed to NACK message (delivery_tag=%d): %v",
              queueName, m.DeliveryTag, err),
          common.F(ctx)...)

      // If NACK fails, message is stuck in unacked state
      // Only option is to close channel to force requeue
      incrementMetric("rabbitmq.nack.errors", map[string]string{
          "queue": queueName,
          "requeue": "true",
      })
  }
  ```

- [ ] 1.4.5 Replace line 319 TODO - Check ACK in drop path:
  ```go
  // Replace line 319:
  // m.Ack(false)

  if err := m.Ack(false); err != nil {
      common.L.Error(
          fmt.Sprintf("[%s] CRITICAL: Failed to ACK dropped message (delivery_tag=%d): %v",
              queueName, m.DeliveryTag, err),
          common.F(ctx)...)
  }
  ```

- [ ] 1.4.6 Add helper function for DLX publishing:
  ```go
  // File: pkg/mq/common/helpers.go

  // publishToDLX sends a failed message to dead letter exchange
  func publishToDLX(ctx context.Context, dlxExchange string, originalMsg amqp.Delivery) error {
      // Preserve original message properties and add failure metadata
      headers := amqp.Table{}
      if originalMsg.Headers != nil {
          headers = originalMsg.Headers
      }

      headers["x-first-death-queue"] = originalMsg.RoutingKey
      headers["x-first-death-reason"] = "processing-failed"
      headers["x-death-timestamp"] = time.Now().Unix()

      return Publish(ctx, dlxExchange, originalMsg.Type, originalMsg.ContentType, originalMsg.Body)
  }

  // getDLXForQueue returns the DLX exchange name for a queue (if configured)
  func getDLXForQueue(queueName string) string {
      // TODO: Implement DLX mapping (Phase 3)
      return ""
  }
  ```

- [ ] 1.4.7 Test ACK failure scenarios
- [ ] 1.4.8 Test NACK failure scenarios
- [ ] 1.4.9 Verify metrics are incremented correctly

### 1.5 Replace Error String Comparison (T0-005)

**Current State:** Brittle string matching for error types
**Files:** `pkg/mq/common/helpers.go:115`

- [ ] 1.5.1 Create error type checking utilities:
  ```go
  // File: pkg/mq/common/errors.go
  package mqcommon

  import (
      "errors"
      "strings"
      amqp "github.com/rabbitmq/amqp091-go"
  )

  // Error types for RabbitMQ operations
  var (
      ErrChannelClosed    = errors.New("channel closed")
      ErrConnectionClosed = errors.New("connection closed")
      ErrNotConnected     = errors.New("not connected to rabbitmq")
      ErrPublishTimeout   = errors.New("publish confirmation timeout")
      ErrPublishNacked    = errors.New("message nacked by broker")
  )

  // IsConnectionError checks if error is connection-related
  func IsConnectionError(err error) bool {
      if err == nil {
          return false
      }

      // Check for sentinel errors
      if errors.Is(err, ErrConnectionClosed) || errors.Is(err, ErrChannelClosed) {
          return true
      }

      // Check for amqp.ErrClosed
      if errors.Is(err, amqp.ErrClosed) {
          return true
      }

      // Check for AMQP exception codes
      if amqpErr, ok := err.(*amqp.Error); ok {
          // 320 = CONNECTION_FORCED
          // 504 = CHANNEL_ERROR
          // 505 = UNEXPECTED_FRAME
          // 506 = RESOURCE_ERROR
          return amqpErr.Code == 320 || amqpErr.Code == 504 || amqpErr.Code == 505 || amqpErr.Code == 506
      }

      // Fallback to string matching (last resort)
      errStr := strings.ToLower(err.Error())
      connectionErrors := []string{
          "channel/connection is not open",
          "connection closed",
          "channel closed",
          "broken pipe",
          "connection reset",
          "eof",
      }

      for _, connErr := range connectionErrors {
          if strings.Contains(errStr, connErr) {
              return true
          }
      }

      return false
  }

  // IsRetryableError checks if operation should be retried
  func IsRetryableError(err error) bool {
      if err == nil {
          return false
      }

      // Connection errors are retryable
      if IsConnectionError(err) {
          return true
      }

      // Timeout errors are retryable
      if errors.Is(err, ErrPublishTimeout) {
          return true
      }

      // Check for context errors (may or may not be retryable)
      errStr := strings.ToLower(err.Error())
      if strings.Contains(errStr, "context deadline exceeded") {
          return true
      }

      return false
  }

  // WrapAMQPError converts AMQP errors to our error types
  func WrapAMQPError(err error) error {
      if err == nil {
          return nil
      }

      if amqpErr, ok := err.(*amqp.Error); ok {
          switch amqpErr.Code {
          case 320:
              return fmt.Errorf("%w: %s", ErrConnectionClosed, amqpErr.Reason)
          case 504:
              return fmt.Errorf("%w: %s", ErrChannelClosed, amqpErr.Reason)
          default:
              return fmt.Errorf("amqp error %d: %s", amqpErr.Code, amqpErr.Reason)
          }
      }

      if err == amqp.ErrClosed {
          return ErrConnectionClosed
      }

      return err
  }
  ```

- [ ] 1.5.2 Replace string comparison in `Publish()` (line 115):
  ```go
  // Replace:
  // if err == amqp.ErrClosed || err.Error() == "Exception (504)..." {

  // With:
  if IsConnectionError(err) {
      lastErr = err
      common.L.Warn(
          fmt.Sprintf("publish failed due to connection error: %v, retrying (attempt %d/%d)...",
              err, attempt+1, maxRetries),
          common.F(ctx)...)
      time.Sleep(time.Second * time.Duration(attempt+1))
      continue
  }

  if IsRetryableError(err) {
      // ... retry logic ...
  } else {
      // Non-retryable error, fail fast
      return WrapAMQPError(err)
  }
  ```

- [ ] 1.5.3 Update all error handling to use new utilities
- [ ] 1.5.4 Add tests for error classification
- [ ] 1.5.5 Test against different RabbitMQ versions

### 1.6 Fix RepublishNack Infinite Loop (T0-006)

**Current State:** Failed messages republished to same queue without max retries
**Files:** `pkg/mq/common/helpers.go:303-307`

- [ ] 1.6.1 Add retry tracking to message headers:
  ```go
  // File: pkg/mq/common/helpers.go

  const (
      MaxMessageRetries = 3
      RetryCountHeader  = "x-retry-count"
      RetryReasonHeader = "x-retry-reason"
  )

  // getRetryCount extracts retry count from message headers
  func getRetryCount(m amqp.Delivery) int {
      if m.Headers == nil {
          return 0
      }

      if count, ok := m.Headers[RetryCountHeader].(int32); ok {
          return int(count)
      }

      return 0
  }

  // shouldRetryMessage determines if message should be retried
  func shouldRetryMessage(m amqp.Delivery, err error) bool {
      retryCount := getRetryCount(m)

      // Check max retries
      if retryCount >= MaxMessageRetries {
          return false
      }

      // Check if error is retryable business logic error
      // (not connection errors - those are handled at transport level)
      if IsConnectionError(err) {
          // Connection errors don't count against retry limit
          return true
      }

      // Check if message is already marked as redelivered multiple times
      if m.Redelivered && retryCount >= 1 {
          // Already failed before, be conservative
          return false
      }

      return true
  }
  ```

- [ ] 1.6.2 Replace RepublishNack logic (lines 303-307):
  ```go
  // Replace entire RepublishNack block:

  if options.RepublishNack {
      retryCount := getRetryCount(m)

      if !shouldRetryMessage(m, err) {
          common.L.Warn(
              fmt.Sprintf("[%s] Message exceeded max retries (%d), sending to DLX: %+v",
                  queueName, MaxMessageRetries, m),
              common.F(ctx)...)

          // ACK original message
          if ackErr := m.Ack(false); ackErr != nil {
              common.L.Error(
                  fmt.Sprintf("[%s] Failed to ACK message before DLX: %v", queueName, ackErr),
                  common.F(ctx)...)
              return
          }

          // Send to DLX
          if dlxExchange := getDLXForQueue(queueName); dlxExchange != "" {
              dlxErr := publishToDLX(ctx, dlxExchange, m)
              if dlxErr != nil {
                  common.L.Error(
                      fmt.Sprintf("[%s] CATASTROPHIC: Failed to send to DLX: %v", queueName, dlxErr),
                      common.F(ctx)...)
              }
          } else {
              common.L.Error(
                  fmt.Sprintf("[%s] No DLX configured, message will be lost!", queueName),
                  common.F(ctx)...)
          }
          return
      }

      // Increment retry count
      headers := amqp.Table{}
      if m.Headers != nil {
          headers = m.Headers
      }
      headers[RetryCountHeader] = int32(retryCount + 1)
      headers[RetryReasonHeader] = err.Error()
      headers["x-retry-timestamp"] = time.Now().Unix()

      // ACK original
      if ackErr := m.Ack(false); ackErr != nil {
          common.L.Error(
              fmt.Sprintf("[%s] Failed to ACK before republish: %v", queueName, ackErr),
              common.F(ctx)...)
          return
      }

      // Republish with updated headers
      publishErr := PublishWithHeaders(ctx, queueName, m.Type, m.ContentType, m.Body, headers)
      if publishErr != nil {
          common.L.Error(
              fmt.Sprintf("[%s] Failed to republish (retry %d/%d): %v",
                  queueName, retryCount+1, MaxMessageRetries, publishErr),
              common.F(ctx)...)

          // Try DLX as last resort
          if dlxExchange := getDLXForQueue(queueName); dlxExchange != "" {
              publishToDLX(ctx, dlxExchange, m)
          }
      } else {
          common.L.Info(
              fmt.Sprintf("[%s] Message republished (retry %d/%d)",
                  queueName, retryCount+1, MaxMessageRetries),
              common.F(ctx)...)
      }
  }
  ```

- [ ] 1.6.3 Add `PublishWithHeaders()` helper:
  ```go
  func PublishWithHeaders(ctx context.Context, destName, messageType, contentType string, body []byte, headers amqp.Table) error {
      // Similar to Publish() but allows custom headers
      maxRetries := 3
      var lastErr error

      for attempt := 0; attempt < maxRetries; attempt++ {
          ch, err := RabbitMQChannelPool.GetChannel()
          if err != nil {
              lastErr = err
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          defer RabbitMQChannelPool.ReturnChannel(ch)

          publisher, err := NewPublisherWithConfirms(ch)
          if err != nil {
              lastErr = err
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          err = publisher.PublishWithConfirm(
              ctx,
              destName,
              "",
              false,
              false,
              amqp.Publishing{
                  DeliveryMode: amqp.Persistent,
                  ContentType:  contentType,
                  Type:         messageType,
                  Body:         body,
                  Timestamp:    time.Now(),
                  Headers:      headers,
              },
          )

          if err == nil {
              return nil
          }

          if IsRetryableError(err) {
              lastErr = err
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          return err
      }

      return fmt.Errorf("publish failed after %d attempts: %w", maxRetries, lastErr)
  }
  ```

- [ ] 1.6.4 Add configuration for max retries:
  ```go
  // Allow override via environment variable
  func init() {
      if maxRetries := os.Getenv("RABBITMQ_MAX_MESSAGE_RETRIES"); maxRetries != "" {
          if count, err := strconv.Atoi(maxRetries); err == nil && count > 0 {
              MaxMessageRetries = count
          }
      }
  }
  ```

- [ ] 1.6.5 Test retry limiting with failing consumer
- [ ] 1.6.6 Test DLX routing for max-retried messages
- [ ] 1.6.7 Monitor for infinite loops in production

### 1.7 Phase 1 Integration & Validation

- [ ] 1.7.1 Run all Phase 1 unit tests
- [ ] 1.7.2 Run integration tests with real RabbitMQ
- [ ] 1.7.3 Load test with 10,000 messages/sec
- [ ] 1.7.4 Chaos test: Kill broker during publishing
- [ ] 1.7.5 Verify zero message loss with publisher confirms
- [ ] 1.7.6 Verify no race conditions with `go test -race`
- [ ] 1.7.7 Code review Phase 1 changes
- [ ] 1.7.8 Update IMPROVEMENTS.md with completion status

---

## Phase 2: System Crash & Hang Prevention (Tier 1)

**Goal:** Eliminate all system crash and hang scenarios
**Timeline:** Week 3-4
**Priority:** CRITICAL

### 2.1 Fix Reconnect Listener Memory Leak (T1-007)

**Current State:** Listeners append-only, never removed - memory grows unbounded
**Files:** `pkg/mq/common/rabbitmq.go:15,75`

- [ ] 2.1.1 Change listener storage to support cleanup:
  ```go
  // File: pkg/mq/common/rabbitmq.go
  // Replace reconnectListeners (line 15)

  var (
      reconnectListeners map[string]chan struct{}  // Changed to map with unique IDs
      reconnectMutex     sync.Mutex
      listenerIDCounter  uint64
  )

  func init() {
      reconnectListeners = make(map[string]chan struct{})
  }
  ```

- [ ] 2.1.2 Update `RegisterReconnectListener()`:
  ```go
  // Returns both channel and cleanup function
  func RegisterReconnectListener() (<-chan struct{}, func()) {
      reconnectMutex.Lock()
      defer reconnectMutex.Unlock()

      // Generate unique ID
      listenerIDCounter++
      id := fmt.Sprintf("listener-%d", listenerIDCounter)

      ch := make(chan struct{}, 10)
      reconnectListeners[id] = ch

      fmt.Printf("[RabbitMQ] Registered reconnection listener %s (total: %d)\n", id, len(reconnectListeners))

      // Return cleanup function
      cleanup := func() {
          reconnectMutex.Lock()
          defer reconnectMutex.Unlock()

          if ch, ok := reconnectListeners[id]; ok {
              close(ch)
              delete(reconnectListeners, id)
              fmt.Printf("[RabbitMQ] Deregistered reconnection listener %s (remaining: %d)\n", id, len(reconnectListeners))
          }
      }

      return ch, cleanup
  }
  ```

- [ ] 2.1.3 Update `ConsumeQueueWithOptionsAsync()` to cleanup:
  ```go
  // File: pkg/mq/common/helpers.go
  // Update line 179

  func ConsumeQueueWithOptionsAsync(...) func() {
      if options == nil {
          options = &ConsumeOptions{
              RequeueNack:   true,
              RepublishNack: false,
          }
      }

      var cancel func()
      ctx, cancel = context.WithCancel(ctx)

      // Register with cleanup
      reconnectCh, cleanupReconnect := RegisterReconnectListener()

      go func() {
          defer func() {
              cleanupReconnect()  // Clean up listener on exit
              common.L.Warn(
                  fmt.Sprintf("[%s] leaving consumer routine...", queueName),
                  common.F(ctx)...)
          }()

          // ... rest of consumer logic ...
      }()

      return cancel
  }
  ```

- [ ] 2.1.4 Add metrics for listener tracking:
  ```go
  func GetReconnectListenerCount() int {
      reconnectMutex.Lock()
      defer reconnectMutex.Unlock()
      return len(reconnectListeners)
  }
  ```

- [ ] 2.1.5 Test listener cleanup on consumer stop
- [ ] 2.1.6 Test long-running service (24+ hours)
- [ ] 2.1.7 Monitor listener count in production

### 2.2 Fix Channel Notification Race (T1-008)

**Current State:** NotifyClose() registered after Consume() - notification can be lost
**Files:** `pkg/mq/common/helpers.go:256-257`

- [ ] 2.2.1 Move channel notification setup before Consume():
  ```go
  // File: pkg/mq/common/helpers.go
  // Reorder lines 207-257

  ch := GetChannel()
  if ch == nil {
      common.L.Warn(
          fmt.Sprintf("[%s] channel is nil, waiting for reconnection...", queueName),
          common.F(ctx)...)
      time.Sleep(5 * time.Second)
      continue
  }

  // CRITICAL: Set up close notification BEFORE consuming
  closeCh := make(chan *amqp.Error, 1)  // Buffered to avoid missing notification
  ch.NotifyClose(closeCh)

  // Log channel state before consuming
  common.L.Info(
      fmt.Sprintf("[%s] attempting to consume with channel (closed=%v)", queueName, ch.IsClosed()),
      common.F(ctx)...)

  // Now safe to consume
  tag := common.SecureRandomString(32)
  msgs, err := ch.Consume(
      queueName,
      tag,
      false, // auto-ack
      false, // exclusive
      false, // no-local
      false, // no-wait
      nil,   // args
  )

  if err != nil {
      // ... error handling ...
  }

  // ... rest of consumer logic ...
  ```

- [ ] 2.2.2 Add buffering to notification channels:
  ```go
  // All notification channels should be buffered
  closeCh := make(chan *amqp.Error, 1)
  cancelCh := make(chan string, 1)  // For consumer cancellation
  ```

- [ ] 2.2.3 Test channel close during consume setup
- [ ] 2.2.4 Verify notification never lost

### 2.3 Add Consumer Cancellation Monitoring (T1-009)

**Current State:** Server-side cancellation not detected - consumer hangs silently
**Files:** Missing implementation

- [ ] 2.3.1 Add NotifyCancel() monitoring:
  ```go
  // File: pkg/mq/common/helpers.go
  // Add after NotifyClose (line ~257)

  // Set up consumer cancellation notification
  cancelCh := make(chan string, 1)
  ch.NotifyCancel(cancelCh)

  common.L.Info(
      fmt.Sprintf("[%s] successfully started consuming (tag=%s)", queueName, tag),
      common.F(ctx)...)
  ```

- [ ] 2.3.2 Handle cancellation in select statement:
  ```go
  // Add to select statement in message loop (line ~270)

  case consumerTag := <-cancelCh:
      common.L.Warn(
          fmt.Sprintf("[%s] consumer cancelled by server (tag=%s), will reconnect...",
              queueName, consumerTag),
          common.F(ctx)...)
      cont = false
      incrementMetric("rabbitmq.consumer.cancelled", map[string]string{
          "queue": queueName,
          "tag":   consumerTag,
      })
      break
  ```

- [ ] 2.3.3 Test server-initiated cancellation
- [ ] 2.3.4 Verify consumer recreates itself

### 2.4 Prevent Double Channel Close Panic (T1-010)

**Current State:** ch.Cancel() called on potentially closed channel
**Files:** `pkg/mq/common/helpers.go:274,287`

- [ ] 2.4.1 Add safe cancel helper:
  ```go
  // File: pkg/mq/common/helpers.go

  // safeChannelCancel cancels consumer without panicking on closed channel
  func safeChannelCancel(ch *amqp.Channel, tag string, noWait bool) error {
      if ch == nil {
          return fmt.Errorf("channel is nil")
      }

      if ch.IsClosed() {
          // Channel already closed, cancellation implicit
          return nil
      }

      // Recover from potential panic
      defer func() {
          if r := recover(); r != nil {
              common.L.Warn(fmt.Sprintf("panic during channel cancel: %v", r), common.F(context.Background())...)
          }
      }()

      return ch.Cancel(tag, noWait)
  }
  ```

- [ ] 2.4.2 Replace ch.Cancel() calls (lines 274, 287):
  ```go
  // Replace:
  // ch.Cancel(tag, false)

  // With:
  if err := safeChannelCancel(ch, tag, false); err != nil {
      common.L.Warn(
          fmt.Sprintf("[%s] failed to cancel consumer (tag=%s): %v", queueName, tag, err),
          common.F(ctx)...)
  }
  ```

- [ ] 2.4.3 Test cancellation during channel close
- [ ] 2.4.4 Verify no panics under stress

### 2.5 Fix Dropped Reconnect Notifications (T1-011)

**Current State:** Non-blocking send drops notifications when buffer full
**Files:** `pkg/mq/common/rabbitmq.go:58-63`

- [ ] 2.5.1 Increase buffer size and use blocking send:
  ```go
  // File: pkg/mq/common/rabbitmq.go
  // Update RegisterReconnectListener() (line 74)

  func RegisterReconnectListener() (<-chan struct{}, func()) {
      reconnectMutex.Lock()
      defer reconnectMutex.Unlock()

      listenerIDCounter++
      id := fmt.Sprintf("listener-%d", listenerIDCounter)

      // CHANGED: Larger buffer
      ch := make(chan struct{}, 100)
      reconnectListeners[id] = ch

      // ... rest of function ...
  }
  ```

- [ ] 2.5.2 Use blocking send with timeout in NotifyReconnect():
  ```go
  // Replace NotifyReconnect() (lines 50-67)

  func NotifyReconnect() {
      reconnectMutex.Lock()
      defer reconnectMutex.Unlock()

      fmt.Printf("[RabbitMQ] Broadcasting reconnection to %d listeners...\n", len(reconnectListeners))

      var wg sync.WaitGroup

      for id, ch := range reconnectListeners {
          wg.Add(1)
          go func(listenerId string, listenerCh chan struct{}) {
              defer wg.Done()

              select {
              case listenerCh <- struct{}{}:
                  fmt.Printf("[RabbitMQ] Sent reconnection notification to listener %s\n", listenerId)
              case <-time.After(5 * time.Second):
                  fmt.Printf("[RabbitMQ] WARNING: Listener %s notification timeout - may be stuck\n", listenerId)
                  incrementMetric("rabbitmq.reconnect.notification.timeout", map[string]string{
                      "listener_id": listenerId,
                  })
              }
          }(id, ch)
      }

      // Wait for all notifications (with timeout)
      done := make(chan struct{})
      go func() {
          wg.Wait()
          close(done)
      }()

      select {
      case <-done:
          fmt.Printf("[RabbitMQ] Reconnection broadcast complete\n")
      case <-time.After(10 * time.Second):
          fmt.Printf("[RabbitMQ] WARNING: Reconnection broadcast timeout\n")
      }
  }
  ```

- [ ] 2.5.3 Test with 100+ consumers
- [ ] 2.5.4 Verify all consumers receive notification
- [ ] 2.5.5 Monitor notification timeouts

### 2.6 Fix Context Inheritance Bug (T1-012)

**Current State:** Context overwrite loses parent context
**Files:** `pkg/mq/common/helpers.go:176`

- [ ] 2.6.1 Fix context handling:
  ```go
  // Replace lines 175-176:
  // var cancel func()
  // ctx, cancel = context.WithCancel(ctx)

  // With:
  var cancel func()
  consumerCtx, cancel := context.WithCancel(ctx)

  // Use consumerCtx throughout the function instead of ctx
  ```

- [ ] 2.6.2 Update all ctx references in consumer to consumerCtx
- [ ] 2.6.3 Test parent context cancellation
- [ ] 2.6.4 Verify context values preserved

### 2.7 Fix Goroutine Leaks (T1-013)

**Current State:** Nested goroutines without proper synchronization
**Files:** `pkg/mq/common/helpers.go:181,261`

- [ ] 2.7.1 Add timeout to waitCh receive:
  ```go
  // Replace line 328:
  // <-waitCh

  // With:
  select {
  case <-waitCh:
      common.L.Info(
          fmt.Sprintf("[%s] message reading loop exited normally", queueName),
          common.F(ctx)...)
  case <-time.After(30 * time.Second):
      common.L.Warn(
          fmt.Sprintf("[%s] WARNING: message reading loop exit timeout - potential goroutine leak", queueName),
          common.F(ctx)...)
      incrementMetric("rabbitmq.goroutine.leak.suspected", map[string]string{
          "queue": queueName,
      })
  }
  ```

- [ ] 2.7.2 Make waitCh buffered:
  ```go
  // Line 259:
  waitCh := make(chan bool, 1)  // Buffered to prevent blocking
  ```

- [ ] 2.7.3 Add goroutine leak detection test
- [ ] 2.7.4 Monitor goroutine count in production

### 2.8 Fix Blocking Channel Send (T1-014)

**Current State:** Unbuffered channel can deadlock
**Files:** `pkg/mq/common/helpers.go:265`

- [ ] 2.8.1 Make waitCh buffered (covered in 2.7.2)
- [ ] 2.8.2 Add timeout to all channel sends:
  ```go
  // Replace line 265:
  // waitCh <- true

  // With:
  select {
  case waitCh <- true:
      // Sent successfully
  case <-time.After(5 * time.Second):
      common.L.Warn(
          fmt.Sprintf("[%s] WARNING: waitCh send timeout - receiver may be dead", queueName),
          common.F(ctx)...)
  }
  ```

- [ ] 2.8.3 Test with blocked receiver
- [ ] 2.8.4 Verify no deadlocks

### 2.9 Phase 2 Integration & Validation

- [ ] 2.9.1 Run all Phase 2 unit tests
- [ ] 2.9.2 Run integration tests
- [ ] 2.9.3 Chaos test: Restart broker 100 times
- [ ] 2.9.4 Memory leak test: Run 7 days
- [ ] 2.9.5 Goroutine leak test: 10,000 consumer start/stops
- [ ] 2.9.6 Verify zero panics
- [ ] 2.9.7 Verify zero hangs
- [ ] 2.9.8 Code review Phase 2 changes

---

## Phase 3: Silent Failure Prevention (Tier 2)

**Goal:** Add Dead Letter Queues, message TTL, queue limits, and flow control
**Timeline:** Week 5-6
**Priority:** HIGH

### 3.1 Implement Dead Letter Exchanges (T2-015)

**Current State:** No DLX - poison messages silently dropped

- [ ] 3.1.1 Define DLX naming convention:
  ```go
  // File: pkg/mq/common/dlx.go
  package mqcommon

  const (
      DLXSuffix      = "_dlx"
      DLQSuffix      = "_dlq"
      DLXRoutingKey  = "dead-letter"
  )

  // GetDLXName returns DLX exchange name for a queue
  func GetDLXName(queueName string) string {
      return queueName + DLXSuffix
  }

  // GetDLQName returns DLQ queue name
  func GetDLQName(queueName string) string {
      return queueName + DLQSuffix
  }
  ```

- [ ] 3.1.2 Create DLX setup function:
  ```go
  // File: pkg/mq/common/dlx.go

  // SetupDLX creates dead letter exchange and queue for a queue
  func SetupDLX(ctx context.Context, queueName string) error {
      ch, err := RabbitMQChannelPool.GetChannel()
      if err != nil {
          return fmt.Errorf("failed to get channel: %w", err)
      }
      defer RabbitMQChannelPool.ReturnChannel(ch)

      dlxExchangeName := GetDLXName(queueName)
      dlqName := GetDLQName(queueName)

      // Create DLX exchange
      err = ch.ExchangeDeclare(
          dlxExchangeName,
          "direct",  // Direct exchange for DLX
          true,      // durable
          false,     // auto-delete
          false,     // internal
          false,     // no-wait
          nil,       // arguments
      )
      if err != nil {
          return fmt.Errorf("failed to declare DLX exchange: %w", err)
      }

      // Create DLQ with special properties
      _, err = ch.QueueDeclare(
          dlqName,
          true,  // durable
          false, // delete when unused
          false, // exclusive
          false, // no-wait
          amqp.Table{
              "x-queue-mode": "lazy",  // Optimize for storage, not RAM
              "x-max-length": 100000,  // Prevent DLQ from growing unbounded
          },
      )
      if err != nil {
          return fmt.Errorf("failed to declare DLQ: %w", err)
      }

      // Bind DLQ to DLX
      err = ch.QueueBind(
          dlqName,
          DLXRoutingKey,
          dlxExchangeName,
          false,
          nil,
      )
      if err != nil {
          return fmt.Errorf("failed to bind DLQ: %w", err)
      }

      common.L.Info(
          fmt.Sprintf("DLX setup complete for queue %s (exchange=%s, dlq=%s)",
              queueName, dlxExchangeName, dlqName),
          common.F(ctx)...)

      return nil
  }
  ```

- [ ] 3.1.3 Update queue declaration to use DLX:
  ```go
  // File: pkg/mq/common/helpers.go
  // Update InitExchangeToMultipleQueues() (line 39-61)

  for _, queueName := range queueNames {
      dlxExchangeName := GetDLXName(queueName)

      _, err := ch.QueueDeclare(
          queueName,
          true,  // durable
          false, // delete when unused
          false, // exclusive
          false, // no-wait
          amqp.Table{
              "x-dead-letter-exchange":    dlxExchangeName,
              "x-dead-letter-routing-key": DLXRoutingKey,
          },
      )
      if err != nil {
          return err
      }

      // Set up DLX for this queue
      if err := SetupDLX(ctx, queueName); err != nil {
          return fmt.Errorf("failed to setup DLX for %s: %w", queueName, err)
      }

      // ... binding logic ...
  }
  ```

- [ ] 3.1.4 Update `getDLXForQueue()` implementation (from 1.4.6):
  ```go
  func getDLXForQueue(queueName string) string {
      return GetDLXName(queueName)
  }
  ```

- [ ] 3.1.5 Add DLQ monitoring endpoint:
  ```go
  // File: pkg/mq/common/dlx.go

  // GetDLQDepth returns message count in DLQ
  func GetDLQDepth(queueName string) (int, error) {
      ch, err := RabbitMQChannelPool.GetChannel()
      if err != nil {
          return 0, err
      }
      defer RabbitMQChannelPool.ReturnChannel(ch)

      dlqName := GetDLQName(queueName)

      queue, err := ch.QueueInspect(dlqName)
      if err != nil {
          return 0, err
      }

      return queue.Messages, nil
  }

  // GetDLQMessages retrieves messages from DLQ (for debugging)
  func GetDLQMessages(queueName string, limit int) ([]amqp.Delivery, error) {
      // Implementation for retrieving DLQ messages
      // Used for debugging and message replay
  }
  ```

- [ ] 3.1.6 Test poison message routing to DLQ
- [ ] 3.1.7 Test DLQ depth monitoring
- [ ] 3.1.8 Create DLQ replay mechanism (for reprocessing)

### 3.2 Add Message TTL (T2-016)

**Current State:** Messages can queue forever

- [ ] 3.2.1 Add TTL configuration:
  ```go
  // File: pkg/mq/common/config.go
  package mqcommon

  import (
      "os"
      "strconv"
      "time"
  )

  var (
      DefaultMessageTTL time.Duration = 24 * time.Hour  // 1 day default
      DefaultQueueTTL   time.Duration = 7 * 24 * time.Hour  // 7 days for queues
  )

  func init() {
      // Allow override via environment
      if ttl := os.Getenv("RABBITMQ_MESSAGE_TTL_SECONDS"); ttl != "" {
          if seconds, err := strconv.Atoi(ttl); err == nil {
              DefaultMessageTTL = time.Duration(seconds) * time.Second
          }
      }
  }
  ```

- [ ] 3.2.2 Update queue declarations with TTL:
  ```go
  // Update InitExchangeToMultipleQueues()

  _, err := ch.QueueDeclare(
      queueName,
      true,
      false,
      false,
      false,
      amqp.Table{
          "x-dead-letter-exchange":    dlxExchangeName,
          "x-dead-letter-routing-key": DLXRoutingKey,
          "x-message-ttl":             int64(DefaultMessageTTL.Milliseconds()),  // NEW
      },
  )
  ```

- [ ] 3.2.3 Set per-message TTL for time-sensitive messages:
  ```go
  // Add TTL variant of Publish()

  func PublishWithTTL(ctx context.Context, destName string, messageType, contentType string, body []byte, ttl time.Duration) error {
      // Similar to Publish() but with Expiration set
      // ...
      amqp.Publishing{
          DeliveryMode: amqp.Persistent,
          ContentType:  contentType,
          Type:         messageType,
          Body:         body,
          Expiration:   strconv.FormatInt(ttl.Milliseconds(), 10),  // Per-message TTL
          Timestamp:    time.Now(),
      }
      // ...
  }
  ```

- [ ] 3.2.4 Test message expiration
- [ ] 3.2.5 Verify expired messages go to DLQ

### 3.3 Add Queue Max Length (T2-017)

**Current State:** No limits - potential OOM

- [ ] 3.3.1 Add queue length limits:
  ```go
  // File: pkg/mq/common/config.go

  var (
      DefaultMaxQueueLength int = 1000000  // 1M messages max
  )

  func init() {
      if maxLen := os.Getenv("RABBITMQ_MAX_QUEUE_LENGTH"); maxLen != "" {
          if length, err := strconv.Atoi(maxLen); err == nil {
              DefaultMaxQueueLength = length
          }
      }
  }
  ```

- [ ] 3.3.2 Update queue declarations:
  ```go
  _, err := ch.QueueDeclare(
      queueName,
      true,
      false,
      false,
      false,
      amqp.Table{
          "x-dead-letter-exchange":    dlxExchangeName,
          "x-dead-letter-routing-key": DLXRoutingKey,
          "x-message-ttl":             int64(DefaultMessageTTL.Milliseconds()),
          "x-max-length":              DefaultMaxQueueLength,  // NEW
          "x-overflow":                "reject-publish",      // Reject new messages when full
      },
  )
  ```

- [ ] 3.3.3 Handle rejection when queue full:
  ```go
  // Update Publish() to handle rejection
  // Use NotifyReturn() to detect rejected messages
  ```

- [ ] 3.3.4 Test queue overflow behavior
- [ ] 3.3.5 Alert when queues approach max length

### 3.4 Implement Idempotency (T2-018)

**Current State:** No deduplication - duplicates guaranteed

- [ ] 3.4.1 Create idempotency key generator:
  ```go
  // File: pkg/mq/common/idempotency.go
  package mqcommon

  import (
      "crypto/sha256"
      "encoding/hex"
      "fmt"
  )

  // GenerateIdempotencyKey creates unique key for message deduplication
  func GenerateIdempotencyKey(messageType string, body []byte, extraKeys ...string) string {
      hasher := sha256.New()
      hasher.Write([]byte(messageType))
      hasher.Write(body)
      for _, key := range extraKeys {
          hasher.Write([]byte(key))
      }
      hash := hex.EncodeToString(hasher.Sum(nil))
      return fmt.Sprintf("idem:%s", hash[:16])  // 16 char prefix
  }
  ```

- [ ] 3.4.2 Create idempotency store interface:
  ```go
  // File: pkg/mq/common/idempotency.go

  // IdempotencyStore tracks processed message IDs
  type IdempotencyStore interface {
      // MarkProcessed records that a message was processed
      MarkProcessed(key string, ttl time.Duration) error

      // WasProcessed checks if message was already processed
      WasProcessed(key string) (bool, error)
  }

  // Redis-based implementation
  type RedisIdempotencyStore struct {
      client *redis.Client
  }

  func NewRedisIdempotencyStore(redisAddr string) (*RedisIdempotencyStore, error) {
      // Implementation using Redis SET with TTL
  }

  func (s *RedisIdempotencyStore) MarkProcessed(key string, ttl time.Duration) error {
      return s.client.Set(context.Background(), key, "1", ttl).Err()
  }

  func (s *RedisIdempotencyStore) WasProcessed(key string) (bool, error) {
      val, err := s.client.Get(context.Background(), key).Result()
      if err == redis.Nil {
          return false, nil
      }
      if err != nil {
          return false, err
      }
      return val == "1", nil
  }
  ```

- [ ] 3.4.3 Integrate with consumer:
  ```go
  // Update message processing (line ~297)

  case m, ok := <-msgs:
      if !ok {
          cont = false
          break
      }

      // Check idempotency
      idempotencyKey := m.MessageId  // Or generate from body
      if idempotencyKey != "" {
          wasProcessed, err := IdempotencyStore.WasProcessed(idempotencyKey)
          if err != nil {
              common.L.Warn(
                  fmt.Sprintf("[%s] Failed to check idempotency for %s: %v",
                      queueName, idempotencyKey, err),
                  common.F(ctx)...)
          } else if wasProcessed {
              common.L.Info(
                  fmt.Sprintf("[%s] Message %s already processed, skipping",
                      queueName, idempotencyKey),
                  common.F(ctx)...)
              m.Ack(false)
              incrementMetric("rabbitmq.duplicate.skipped", map[string]string{
                  "queue": queueName,
              })
              continue  // Skip processing
          }
      }

      // Process message
      err := cb(m.Type, m.ContentType, m.Body)
      if err == nil {
          // Mark as processed BEFORE acking
          if idempotencyKey != "" {
              IdempotencyStore.MarkProcessed(idempotencyKey, 24*time.Hour)
          }
          m.Ack(false)
      } else {
          // ... error handling ...
      }
  ```

- [ ] 3.4.4 Add configuration for idempotency:
  ```go
  var (
      IdempotencyEnabled bool = true
      IdempotencyTTL     time.Duration = 24 * time.Hour
  )
  ```

- [ ] 3.4.5 Test duplicate message handling
- [ ] 3.4.6 Benchmark idempotency overhead

### 3.5 Fix Global QoS (T2-022, T2-023)

**Current State:** QoS=1000 on wrong channel, has no effect

- [ ] 3.5.1 Add per-consumer QoS configuration:
  ```go
  // File: pkg/mq/common/config.go

  var (
      DefaultPrefetchCount int = 20  // More reasonable default
  )

  type ConsumerQoS struct {
      PrefetchCount int
      PrefetchSize  int
      Global        bool
  }

  func GetQoSForQueue(queueName string) ConsumerQoS {
      // Allow per-queue override via environment
      envKey := fmt.Sprintf("RABBITMQ_QOS_%s", strings.ToUpper(queueName))
      if qos := os.Getenv(envKey); qos != "" {
          if count, err := strconv.Atoi(qos); err == nil {
              return ConsumerQoS{
                  PrefetchCount: count,
                  PrefetchSize:  0,
                  Global:        false,
              }
          }
      }

      return ConsumerQoS{
          PrefetchCount: DefaultPrefetchCount,
          PrefetchSize:  0,
          Global:        false,
      }
  }
  ```

- [ ] 3.5.2 Apply QoS per consumer channel:
  ```go
  // File: pkg/mq/common/helpers.go
  // Update ConsumeQueueWithOptionsAsync() after getting channel (line ~214)

  // Get dedicated channel for this consumer (not from pool!)
  ch, err := mqcommon.RabbitMQConnection.Channel()
  if err != nil {
      common.L.Warn(
          fmt.Sprintf("[%s] failed to create consumer channel: %v", queueName, err),
          common.F(ctx)...)
      time.Sleep(5 * time.Second)
      continue
  }

  // Apply QoS to THIS consumer's channel
  qos := GetQoSForQueue(queueName)
  if err := ch.Qos(qos.PrefetchCount, qos.PrefetchSize, qos.Global); err != nil {
      common.L.Warn(
          fmt.Sprintf("[%s] failed to set QoS: %v", queueName, err),
          common.F(ctx)...)
      ch.Close()
      time.Sleep(5 * time.Second)
      continue
  }

  common.L.Info(
      fmt.Sprintf("[%s] consumer channel created with QoS (prefetch=%d)",
          queueName, qos.PrefetchCount),
      common.F(ctx)...)

  // IMPORTANT: Close this channel when consumer stops
  defer ch.Close()
  ```

- [ ] 3.5.3 Remove global QoS from init.go (line 24):
  ```go
  // Delete or comment out:
  // err := ch.Qos(1000, 0, false)
  ```

- [ ] 3.5.4 Test QoS limiting
- [ ] 3.5.5 Verify fair message distribution

### 3.6 Fix Heartbeat & Timeout (T2-026, T2-027)

**Current State:** 60s heartbeat, 300s connect timeout

- [ ] 3.6.1 Reduce heartbeat interval:
  ```go
  // File: pkg/mq/init.go
  // Update line 75

  config := amqp.Config{
      Heartbeat: 15 * time.Second,  // Changed from 60s to 15s
      Dial: func(network, addr string) (net.Conn, error) {
          return amqp.DefaultDial(30 * time.Second)(network, addr)  // Changed from 300s to 30s
      },
  }
  ```

- [ ] 3.6.2 Make configurable:
  ```go
  func getHeartbeatInterval() time.Duration {
      if hb := os.Getenv("RABBITMQ_HEARTBEAT_SECONDS"); hb != "" {
          if seconds, err := strconv.Atoi(hb); err == nil {
              return time.Duration(seconds) * time.Second
          }
      }
      return 15 * time.Second  // Default
  }

  func getConnectTimeout() time.Duration {
      if ct := os.Getenv("RABBITMQ_CONNECT_TIMEOUT_SECONDS"); ct != "" {
          if seconds, err := strconv.Atoi(ct); err == nil {
              return time.Duration(seconds) * time.Second
          }
      }
      return 30 * time.Second  // Default
  }

  config := amqp.Config{
      Heartbeat: getHeartbeatInterval(),
      Dial: func(network, addr string) (net.Conn, error) {
          return amqp.DefaultDial(getConnectTimeout())(network, addr)
      },
  }
  ```

- [ ] 3.6.3 Test partition detection time
- [ ] 3.6.4 Test connect timeout under network issues

### 3.7 Add Flow Control Monitoring (T2-024, T2-025)

**Current State:** No NotifyReturn, no NotifyBlocked

- [ ] 3.7.1 Monitor publisher returns:
  ```go
  // File: pkg/mq/common/publisher.go
  // Update PublisherWithConfirms

  type PublisherWithConfirms struct {
      ch            *amqp.Channel
      confirmChan   chan amqp.Confirmation
      returnChan    chan amqp.Return  // NEW
      nextSeqNo     uint64
      mu            sync.Mutex
      confirmTimeout time.Duration
  }

  func NewPublisherWithConfirms(ch *amqp.Channel) (*PublisherWithConfirms, error) {
      if err := ch.Confirm(false); err != nil {
          return nil, fmt.Errorf("failed to enable publisher confirms: %w", err)
      }

      confirmChan := ch.NotifyPublish(make(chan amqp.Confirmation, 100))
      returnChan := ch.NotifyReturn(make(chan amqp.Return, 100))  // NEW

      p := &PublisherWithConfirms{
          ch:             ch,
          confirmChan:    confirmChan,
          returnChan:     returnChan,
          nextSeqNo:      1,
          confirmTimeout: 30 * time.Second,
      }

      // Monitor returns in background
      go p.monitorReturns()

      return p, nil
  }

  func (p *PublisherWithConfirms) monitorReturns() {
      for ret := range p.returnChan {
          common.L.Warn(
              fmt.Sprintf("Message returned by broker: exchange=%s, routing_key=%s, reply_code=%d, reply_text=%s",
                  ret.Exchange, ret.RoutingKey, ret.ReplyCode, ret.ReplyText),
              common.F(context.Background())...)

          incrementMetric("rabbitmq.message.returned", map[string]string{
              "exchange":    ret.Exchange,
              "reply_code":  fmt.Sprintf("%d", ret.ReplyCode),
              "reply_text":  ret.ReplyText,
          })
      }
  }
  ```

- [ ] 3.7.2 Monitor connection blocking:
  ```go
  // File: pkg/mq/init.go
  // Add to initConn() after line 89

  // Monitor connection blocking (memory/disk alarms)
  go monitorConnectionBlocking(mqcommon.RabbitMQConnection, ctx)

  func monitorConnectionBlocking(conn *amqp.Connection, ctx context.Context) {
      blockChan := conn.NotifyBlocked(make(chan amqp.Blocking, 10))

      for blocking := range blockChan {
          if blocking.Active {
              common.L.Error(
                  fmt.Sprintf("RabbitMQ connection BLOCKED: %s", blocking.Reason),
                  common.F(ctx)...)
              incrementMetric("rabbitmq.connection.blocked", map[string]string{
                  "reason": blocking.Reason,
              })
          } else {
              common.L.Info(
                  "RabbitMQ connection UNBLOCKED",
                  common.F(ctx)...)
              incrementMetric("rabbitmq.connection.unblocked", nil)
          }
      }
  }
  ```

- [ ] 3.7.3 Test with memory alarms
- [ ] 3.7.4 Test with disk alarms
- [ ] 3.7.5 Alert on blocking events

### 3.8 Phase 3 Integration & Validation

- [ ] 3.8.1 Run all Phase 3 unit tests
- [ ] 3.8.2 Test DLQ functionality end-to-end
- [ ] 3.8.3 Test message expiration
- [ ] 3.8.4 Test queue overflow
- [ ] 3.8.5 Test idempotency with duplicates
- [ ] 3.8.6 Load test with proper QoS settings
- [ ] 3.8.7 Verify flow control monitoring
- [ ] 3.8.8 Code review Phase 3 changes

---

## Phase 4: Architectural Refactoring (Tier 3)

**Goal:** Refactor for testability, maintainability, and operational excellence
**Timeline:** Week 7-8
**Priority:** MEDIUM

### 4.1 Replace Global State with Dependency Injection

**Current State:** Package-level globals prevent testing and multi-instance
**Files:** `pkg/mq/common/rabbitmq.go:10-17`

- [ ] 4.1.1 Design new architecture:
  ```go
  // File: pkg/mq/client.go
  package mq

  import (
      "context"
      amqp "github.com/rabbitmq/amqp091-go"
  )

  // Client is the main RabbitMQ client interface
  type Client interface {
      // Connection management
      Connect(ctx context.Context) error
      Close() error
      IsConnected() bool

      // Publishing
      Publish(ctx context.Context, exchange, routingKey string, msg Message) error
      PublishWithConfirm(ctx context.Context, exchange, routingKey string, msg Message) error

      // Consuming
      Consume(ctx context.Context, queue string, handler MessageHandler) error
      ConsumeWithOptions(ctx context.Context, queue string, opts ConsumeOptions, handler MessageHandler) error

      // Topology management
      DeclareExchange(ctx context.Context, name string, opts ExchangeOptions) error
      DeclareQueue(ctx context.Context, name string, opts QueueOptions) error
      BindQueue(ctx context.Context, queue, exchange, routingKey string) error

      // Health & metrics
      HealthCheck() error
      GetMetrics() ClientMetrics
  }

  // Config holds all RabbitMQ configuration
  type Config struct {
      URL              string
      Heartbeat        time.Duration
      ConnectTimeout   time.Duration
      MaxChannels      int
      DefaultQoS       int
      IdempotencyStore IdempotencyStore
      MetricsCollector MetricsCollector
  }

  // Message represents a publishable message
  type Message struct {
      Body         []byte
      ContentType  string
      Type         string
      Headers      map[string]interface{}
      TTL          time.Duration
      Priority     uint8
      MessageID    string
  }

  // MessageHandler processes consumed messages
  type MessageHandler func(ctx context.Context, msg DeliveredMessage) error

  // DeliveredMessage wraps amqp.Delivery with helper methods
  type DeliveredMessage struct {
      delivery amqp.Delivery
  }

  func (m *DeliveredMessage) Body() []byte { return m.delivery.Body }
  func (m *DeliveredMessage) Ack() error   { return m.delivery.Ack(false) }
  func (m *DeliveredMessage) Nack(requeue bool) error { return m.delivery.Nack(false, requeue) }
  func (m *DeliveredMessage) Headers() map[string]interface{} { return m.delivery.Headers }
  func (m *DeliveredMessage) MessageID() string { return m.delivery.MessageId }
  func (m *DeliveredMessage) Redelivered() bool { return m.delivery.Redelivered }
  ```

- [ ] 4.1.2 Implement client:
  ```go
  // File: pkg/mq/client_impl.go
  package mq

  type client struct {
      config           Config
      conn             *amqp.Connection
      channelPool      *ChannelPool
      mu               sync.RWMutex
      connected        bool
      reconnectSig     chan struct{}
      closeSig         chan struct{}
      metrics          *clientMetrics
  }

  func NewClient(config Config) (Client, error) {
      // Validate config
      if config.URL == "" {
          return nil, errors.New("rabbitmq url is required")
      }

      if config.Heartbeat == 0 {
          config.Heartbeat = 15 * time.Second
      }

      if config.ConnectTimeout == 0 {
          config.ConnectTimeout = 30 * time.Second
      }

      if config.MaxChannels == 0 {
          config.MaxChannels = 20
      }

      c := &client{
          config:       config,
          reconnectSig: make(chan struct{}),
          closeSig:     make(chan struct{}),
          metrics:      newClientMetrics(),
      }

      return c, nil
  }

  func (c *client) Connect(ctx context.Context) error {
      c.mu.Lock()
      defer c.mu.Unlock()

      // ... connection logic from initConn() ...

      c.connected = true

      // Start reconnection monitor
      go c.monitorConnection(ctx)

      return nil
  }

  func (c *client) Close() error {
      c.mu.Lock()
      defer c.mu.Unlock()

      close(c.closeSig)

      if c.channelPool != nil {
          c.channelPool.Close()
      }

      if c.conn != nil {
          c.conn.Close()
      }

      c.connected = false
      return nil
  }

  func (c *client) Publish(ctx context.Context, exchange, routingKey string, msg Message) error {
      // Implementation using channel pool
  }

  // ... implement all other methods ...
  ```

- [ ] 4.1.3 Create migration path from globals:
  ```go
  // File: pkg/mq/compat.go
  // Provide backward compatibility wrapper

  var defaultClient Client

  func Init(ctx context.Context) {
      // Legacy init function - creates default client
      config := Config{
          URL:            os.Getenv("RABBITMQ_CONN_STRING"),
          Heartbeat:      getHeartbeatInterval(),
          ConnectTimeout: getConnectTimeout(),
          MaxChannels:    20,
      }

      var err error
      defaultClient, err = NewClient(config)
      if err != nil {
          panic(fmt.Sprintf("failed to create rabbitmq client: %v", err))
      }

      if err := defaultClient.Connect(ctx); err != nil {
          panic(fmt.Sprintf("failed to connect to rabbitmq: %v", err))
      }

      // Initialize topology
      initQueuesWithClient(ctx, defaultClient)
  }

  // Legacy Publish function delegates to default client
  func Publish(ctx context.Context, destName, messageType, contentType string, body []byte) error {
      return defaultClient.Publish(ctx, destName, "", Message{
          Body:        body,
          ContentType: contentType,
          Type:        messageType,
      })
  }
  ```

- [ ] 4.1.4 Update all daemons to use new client
- [ ] 4.1.5 Deprecate global functions
- [ ] 4.1.6 Test both old and new APIs

### 4.2 Add Mock Implementation for Testing

- [ ] 4.2.1 Create mock client:
  ```go
  // File: pkg/mq/mock/client.go
  package mock

  type MockClient struct {
      ConnectFunc     func(ctx context.Context) error
      PublishFunc     func(ctx context.Context, exchange, key string, msg Message) error
      ConsumeFunc     func(ctx context.Context, queue string, handler MessageHandler) error

      PublishedMessages []PublishedMessage
      mu                sync.Mutex
  }

  type PublishedMessage struct {
      Exchange   string
      RoutingKey string
      Message    Message
      Timestamp  time.Time
  }

  func NewMockClient() *MockClient {
      return &MockClient{
          PublishedMessages: make([]PublishedMessage, 0),
      }
  }

  func (m *MockClient) Publish(ctx context.Context, exchange, routingKey string, msg Message) error {
      m.mu.Lock()
      defer m.mu.Unlock()

      m.PublishedMessages = append(m.PublishedMessages, PublishedMessage{
          Exchange:   exchange,
          RoutingKey: routingKey,
          Message:    msg,
          Timestamp:  time.Now(),
      })

      if m.PublishFunc != nil {
          return m.PublishFunc(ctx, exchange, routingKey, msg)
      }

      return nil
  }

  func (m *MockClient) GetPublishedMessages() []PublishedMessage {
      m.mu.Lock()
      defer m.mu.Unlock()

      messages := make([]PublishedMessage, len(m.PublishedMessages))
      copy(messages, m.PublishedMessages)
      return messages
  }

  func (m *MockClient) ClearPublishedMessages() {
      m.mu.Lock()
      defer m.mu.Unlock()
      m.PublishedMessages = make([]PublishedMessage, 0)
  }

  // ... implement other methods ...
  ```

- [ ] 4.2.2 Create test helpers:
  ```go
  // File: pkg/mq/testing/helpers.go
  package mqtesting

  // AssertMessagePublished verifies a message was published
  func AssertMessagePublished(t *testing.T, client *mock.MockClient, exchange string, messageType string) {
      messages := client.GetPublishedMessages()
      for _, msg := range messages {
          if msg.Exchange == exchange && msg.Message.Type == messageType {
              return // Found it
          }
      }
      t.Errorf("Expected message (exchange=%s, type=%s) not published", exchange, messageType)
  }
  ```

- [ ] 4.2.3 Write example test:
  ```go
  // File: pkg/mq/client_test.go

  func TestPublish(t *testing.T) {
      mockClient := mock.NewMockClient()

      err := mockClient.Publish(context.Background(), "test-exchange", "test-key", Message{
          Body:        []byte("test"),
          ContentType: "application/json",
          Type:        "test-message",
      })

      assert.NoError(t, err)

      messages := mockClient.GetPublishedMessages()
      assert.Len(t, messages, 1)
      assert.Equal(t, "test-exchange", messages[0].Exchange)
  }
  ```

- [ ] 4.2.4 Test mock with saga system

### 4.3 Add Health Check Implementation

- [ ] 4.3.1 Create health check interface:
  ```go
  // File: pkg/mq/health.go

  type HealthStatus struct {
      Connected      bool
      ConnectionOpen bool
      ChannelCount   int
      QueueStats     map[string]QueueHealth
      LastError      string
      UptimeSeconds  int64
  }

  type QueueHealth struct {
      Messages      int
      Consumers     int
      MessagesReady int
      MessagesUnacked int
  }

  func (c *client) HealthCheck() error {
      c.mu.RLock()
      defer c.mu.RUnlock()

      if !c.connected {
          return errors.New("not connected to rabbitmq")
      }

      if c.conn == nil || c.conn.IsClosed() {
          return errors.New("connection is closed")
      }

      if c.channelPool == nil {
          return errors.New("channel pool is nil")
      }

      // Try to get a channel as liveness check
      ch, err := c.channelPool.GetChannel()
      if err != nil {
          return fmt.Errorf("failed to get channel: %w", err)
      }
      defer c.channelPool.ReturnChannel(ch)

      return nil
  }

  func (c *client) GetHealthStatus() HealthStatus {
      // Detailed health status for monitoring
  }
  ```

- [ ] 4.3.2 Integrate with service health endpoints
- [ ] 4.3.3 Test health check during reconnection

### 4.4 Add Comprehensive Logging

- [ ] 4.4.1 Replace fmt.Printf with structured logging:
  ```go
  // File: pkg/mq/common/rabbitmq.go
  // Replace all fmt.Printf with common.L

  // Before:
  // fmt.Printf("[RabbitMQ] Channel updated ...\n")

  // After:
  common.L.Info(
      "Channel updated",
      zap.Bool("old_closed", oldClosed),
      zap.Bool("new_closed", ch.IsClosed()),
  )
  ```

- [ ] 4.4.2 Add debug logging for troubleshooting:
  ```go
  if logLevel := os.Getenv("RABBITMQ_LOG_LEVEL"); logLevel == "debug" {
      common.L.Debug(
          "Publishing message",
          zap.String("exchange", exchange),
          zap.String("routing_key", routingKey),
          zap.String("message_type", msg.Type),
          zap.Int("body_size", len(msg.Body)),
      )
  }
  ```

- [ ] 4.4.3 Add correlation IDs to all logs
- [ ] 4.4.4 Test log output format

### 4.5 Implement Graceful Shutdown

- [ ] 4.5.1 Add shutdown coordination:
  ```go
  // File: pkg/mq/client_impl.go

  func (c *client) Shutdown(ctx context.Context) error {
      c.mu.Lock()
      defer c.mu.Unlock()

      common.L.Info("Initiating graceful RabbitMQ shutdown...")

      // 1. Stop accepting new operations
      c.connected = false

      // 2. Wait for in-flight messages (with timeout)
      drainCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
      defer cancel()

      if err := c.drainInflightMessages(drainCtx); err != nil {
          common.L.Warn(fmt.Sprintf("Failed to drain messages: %v", err))
      }

      // 3. Close consumers
      if err := c.closeAllConsumers(); err != nil {
          common.L.Warn(fmt.Sprintf("Failed to close consumers: %v", err))
      }

      // 4. Close channel pool
      if c.channelPool != nil {
          if err := c.channelPool.Close(); err != nil {
              common.L.Warn(fmt.Sprintf("Failed to close channel pool: %v", err))
          }
      }

      // 5. Close connection
      if c.conn != nil {
          if err := c.conn.Close(); err != nil {
              common.L.Warn(fmt.Sprintf("Failed to close connection: %v", err))
          }
      }

      common.L.Info("RabbitMQ shutdown complete")
      return nil
  }

  func (c *client) drainInflightMessages(ctx context.Context) error {
      // Wait for pending confirmations and in-flight messages
      ticker := time.NewTicker(100 * time.Millisecond)
      defer ticker.Stop()

      for {
          select {
          case <-ctx.Done():
              return ctx.Err()
          case <-ticker.C:
              if c.metrics.InflightMessages() == 0 {
                  return nil
              }
          }
      }
  }
  ```

- [ ] 4.5.2 Integrate with service shutdown
- [ ] 4.5.3 Test zero message loss during shutdown
- [ ] 4.5.4 Test shutdown timeout handling

### 4.6 Infinite Init Loop Fix

**Current State:** Init() blocks forever if RabbitMQ unavailable
**Files:** `pkg/mq/init.go:94-111`

- [ ] 4.6.1 Add max retry limit to Init():
  ```go
  // File: pkg/mq/init.go
  // Replace infinite loops (lines 94-111)

  const MaxInitRetries = 30  // 5 minutes at 10s intervals

  func Init(ctx context.Context) {
      var err error

      // Connection retry with limit
      for attempt := 1; attempt <= MaxInitRetries; attempt++ {
          err = initConn(ctx)
          if err == nil {
              break
          }

          common.L.Warn(
              fmt.Sprintf("Connection attempt %d/%d failed: %v", attempt, MaxInitRetries, err),
              common.F(ctx)...)

          if attempt == MaxInitRetries {
              panic(fmt.Sprintf("Failed to connect to RabbitMQ after %d attempts: %v", MaxInitRetries, err))
          }

          time.Sleep(10 * time.Second)
      }

      // Queue init retry with limit
      for attempt := 1; attempt <= MaxInitRetries; attempt++ {
          err = initQueues(ctx)
          if err == nil {
              break
          }

          common.L.Warn(
              fmt.Sprintf("Queue init attempt %d/%d failed: %v", attempt, MaxInitRetries, err),
              common.F(ctx)...)

          if attempt == MaxInitRetries {
              panic(fmt.Sprintf("Failed to initialize queues after %d attempts: %v", MaxInitRetries, err))
          }

          time.Sleep(10 * time.Second)
      }

      common.L.Info("rabbitmq connect success", common.F(ctx)...)

      // Start reconnection handler
      go reconnectionHandler(ctx)
  }
  ```

- [ ] 4.6.2 Make retry limit configurable:
  ```go
  func getMaxInitRetries() int {
      if retries := os.Getenv("RABBITMQ_MAX_INIT_RETRIES"); retries != "" {
          if count, err := strconv.Atoi(retries); err == nil && count > 0 {
              return count
          }
      }
      return 30  // Default
  }
  ```

- [ ] 4.6.3 Test init timeout
- [ ] 4.6.4 Test K8s pod startup with unavailable RabbitMQ

### 4.7 Phase 4 Validation

- [ ] 4.7.1 Run all unit tests with new client API
- [ ] 4.7.2 Test mock client in saga tests
- [ ] 4.7.3 Test graceful shutdown
- [ ] 4.7.4 Test health checks
- [ ] 4.7.5 Verify logging improvements
- [ ] 4.7.6 Code review Phase 4 changes

---

## Phase 5: Testing Infrastructure

**Goal:** Comprehensive test coverage for RabbitMQ layer
**Timeline:** Week 9
**Priority:** HIGH

### 5.1 Unit Tests

- [ ] 5.1.1 Test publisher confirms
- [ ] 5.1.2 Test channel pool
- [ ] 5.1.3 Test error classification
- [ ] 5.1.4 Test idempotency store
- [ ] 5.1.5 Test retry logic
- [ ] 5.1.6 Test DLX routing
- [ ] 5.1.7 Achieve 80%+ code coverage

### 5.2 Integration Tests

- [ ] 5.2.1 Set up test RabbitMQ instance (Docker)
- [ ] 5.2.2 Test publish-subscribe flow
- [ ] 5.2.3 Test reconnection scenarios
- [ ] 5.2.4 Test message ordering
- [ ] 5.2.5 Test DLQ functionality
- [ ] 5.2.6 Test TTL expiration
- [ ] 5.2.7 Test queue overflow

### 5.3 Load Tests

- [ ] 5.3.1 Test 10,000 msg/sec throughput
- [ ] 5.3.2 Test 1000 concurrent publishers
- [ ] 5.3.3 Test 100 concurrent consumers
- [ ] 5.3.4 Test memory usage under load
- [ ] 5.3.5 Test CPU usage under load

### 5.4 Chaos Tests

- [ ] 5.4.1 Test broker restart during publishing
- [ ] 5.4.2 Test network partition
- [ ] 5.4.3 Test consumer crash during processing
- [ ] 5.4.4 Test message corruption
- [ ] 5.4.5 Test memory pressure scenarios

---

## Phase 6: Monitoring & Observability

**Goal:** Production-ready monitoring and metrics
**Timeline:** Week 10
**Priority:** HIGH

### 6.1 Metrics Implementation

- [ ] 6.1.1 Define metric schema
- [ ] 6.1.2 Implement Prometheus exporter
- [ ] 6.1.3 Add metrics to all operations
- [ ] 6.1.4 Create Grafana dashboards
- [ ] 6.1.5 Set up alerts

### 6.2 Distributed Tracing

- [ ] 6.2.1 Add trace IDs to messages
- [ ] 6.2.2 Integrate with OpenTelemetry
- [ ] 6.2.3 Trace publish → consume flow
- [ ] 6.2.4 Trace saga execution through MQ

---

## Phase 7: High Availability Configuration

**Goal:** Production HA setup
**Timeline:** Week 11
**Priority:** MEDIUM

### 7.1 Quorum Queues

- [ ] 7.1.1 Enable quorum queues
- [ ] 7.1.2 Test failover scenarios
- [ ] 7.1.3 Test data replication

### 7.2 Cluster Configuration

- [ ] 7.2.1 Document cluster setup
- [ ] 7.2.2 Test multi-node failover
- [ ] 7.2.3 Test split-brain scenarios

---

## Phase 8: Documentation & Best Practices

**Goal:** Complete documentation
**Timeline:** Week 12
**Priority:** MEDIUM

### 8.1 Code Documentation

- [ ] 8.1.1 Add package-level docs
- [ ] 8.1.2 Document all public APIs
- [ ] 8.1.3 Add usage examples
- [ ] 8.1.4 Document configuration options

### 8.2 Operational Runbooks

- [ ] 8.2.1 RabbitMQ Operations Guide
- [ ] 8.2.2 Troubleshooting Guide
- [ ] 8.2.3 Disaster Recovery Procedures
- [ ] 8.2.4 Performance Tuning Guide

---

## Phase 9: Migration Strategy

**Goal:** Zero-downtime migration plan
**Timeline:** Week 13
**Priority:** HIGH

### 9.1 Migration Plan

- [ ] 9.1.1 Create backward compatibility layer
- [ ] 9.1.2 Gradual rollout strategy
- [ ] 9.1.3 Rollback procedures
- [ ] 9.1.4 Validation criteria

---

## Phase 10: Performance Optimization

**Goal:** Optimize for production workload
**Timeline:** Week 14
**Priority:** MEDIUM

### 10.1 Profiling

- [ ] 10.1.1 CPU profiling
- [ ] 10.1.2 Memory profiling
- [ ] 10.1.3 Identify bottlenecks
- [ ] 10.1.4 Optimize hot paths

---

## Phase 11: Validation & Sign-off

**Goal:** Production readiness verification
**Timeline:** Week 15
**Priority:** CRITICAL

### 11.1 Final Validation

- [ ] 11.1.1 All tests passing
- [ ] 11.1.2 Security audit
- [ ] 11.1.3 Performance benchmarks met
- [ ] 11.1.4 Documentation complete
- [ ] 11.1.5 Stakeholder sign-off

---

## Appendix A: Issue Cross-Reference

See detailed analysis in issue map at top of document.

## Appendix B: Configuration Reference

All environment variables and their defaults.

## Appendix C: Metrics Reference

All metrics exposed and their meanings.

## Appendix D: Testing Strategy

Comprehensive test plan and coverage targets.

---

**End of Remediation Plan**

*This document should be updated as implementation progresses. Each checkbox represents a concrete, testable deliverable.*
