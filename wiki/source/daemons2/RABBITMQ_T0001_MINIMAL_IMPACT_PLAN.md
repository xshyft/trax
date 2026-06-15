# T0-001 Publisher Confirms - Minimal Impact Implementation

## Goal

Add publisher confirms to **eliminate message loss** while keeping **zero breaking changes** to existing code.

**Key Principle:** Existing callers of `Publish()` continue to work exactly as before - confirms happen transparently inside.

---

## Current State

**All existing code uses:**
```go
// 200+ call sites across codebase like this:
err := mqcommon.Publish(ctx, exchangeName, messageType, contentType, body)
if err != nil {
    // handle error
}
```

**We CANNOT change this interface** - too many call sites.

---

## Strategy: Transparent Internal Implementation

### ✅ What DOESN'T Change

1. **Function signature** - stays exactly the same:
   ```go
   func Publish(ctx context.Context, destName, messageType, contentType string, body []byte) error
   ```

2. **Caller code** - zero changes needed:
   ```go
   // This code works before and after - NO CHANGES NEEDED
   err := mqcommon.Publish(ctx, "x_exchange", "ORDER", "application/json", data)
   ```

3. **Error handling** - callers handle errors same way
4. **Imports** - no new imports needed
5. **Configuration** - works with existing config

### ✅ What DOES Change (Internal Only)

1. **Inside Publish()** - add confirms transparently
2. **Feature flag** - control via environment variable
3. **Logging** - more detailed (success/failure)
4. **Behavior** - waits for broker confirmation

---

## Implementation (3 Small Files)

### Step 1: Create Error Types (New File)

**File:** `pkg/mq/common/errors.go`

```go
package mqcommon

import (
    "errors"
)

// Sentinel errors for RabbitMQ operations
var (
    ErrPublishTimeout   = errors.New("publish confirmation timeout")
    ErrPublishNacked    = errors.New("message nacked by broker")
    ErrChannelClosed    = errors.New("channel closed")
    ErrConnectionClosed = errors.New("connection closed")
)

// IsRetryableError checks if error should be retried
func IsRetryableError(err error) bool {
    if err == nil {
        return false
    }

    // These errors are retryable
    return errors.Is(err, ErrPublishTimeout) ||
           errors.Is(err, ErrChannelClosed) ||
           errors.Is(err, ErrConnectionClosed)
}
```

**Impact:** Zero - new file, no changes to existing code

---

### Step 2: Create Confirms Wrapper (New File)

**File:** `pkg/mq/common/publisher.go`

```go
package mqcommon

import (
    "context"
    "fmt"
    "sync"
    "time"
    amqp "github.com/rabbitmq/amqp091-go"
)

// PublisherWithConfirms wraps a channel to add publisher confirmation support
type PublisherWithConfirms struct {
    ch             *amqp.Channel
    confirmChan    chan amqp.Confirmation
    nextSeqNo      uint64
    mu             sync.Mutex
    confirmTimeout time.Duration
}

// NewPublisherWithConfirms creates a publisher with confirms enabled
func NewPublisherWithConfirms(ch *amqp.Channel, timeout time.Duration) (*PublisherWithConfirms, error) {
    if ch == nil {
        return nil, fmt.Errorf("channel is nil")
    }

    // Enable publisher confirms
    if err := ch.Confirm(false); err != nil {
        return nil, fmt.Errorf("failed to enable confirms: %w", err)
    }

    // Create confirmation channel (buffered to avoid blocking broker)
    confirmChan := ch.NotifyPublish(make(chan amqp.Confirmation, 100))

    return &PublisherWithConfirms{
        ch:             ch,
        confirmChan:    confirmChan,
        nextSeqNo:      1,
        confirmTimeout: timeout,
    }, nil
}

// PublishWithConfirm publishes message and waits for broker confirmation
func (p *PublisherWithConfirms) PublishWithConfirm(
    ctx context.Context,
    exchange, routingKey string,
    mandatory, immediate bool,
    msg amqp.Publishing,
) error {
    // Get sequence number
    p.mu.Lock()
    seqNo := p.nextSeqNo
    p.nextSeqNo++
    p.mu.Unlock()

    // Publish message
    if err := p.ch.PublishWithContext(ctx, exchange, routingKey, mandatory, immediate, msg); err != nil {
        return fmt.Errorf("publish failed: %w", err)
    }

    // Wait for confirmation
    select {
    case confirm := <-p.confirmChan:
        if confirm.DeliveryTag != seqNo {
            return fmt.Errorf("sequence mismatch: expected %d, got %d", seqNo, confirm.DeliveryTag)
        }
        if !confirm.Ack {
            return ErrPublishNacked
        }
        return nil // ✅ Success - broker confirmed

    case <-time.After(p.confirmTimeout):
        return fmt.Errorf("%w: after %v (seq %d)", ErrPublishTimeout, p.confirmTimeout, seqNo)

    case <-ctx.Done():
        return fmt.Errorf("context cancelled: %w", ctx.Err())
    }
}
```

**Impact:** Zero - new file, no changes to existing code

---

### Step 3: Update Publish() - Internal Changes Only

**File:** `pkg/mq/common/helpers.go`

**Current Publish() function (lines 84-128):**

```go
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

        err := ch.PublishWithContext(
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
            },
        )

        if err == nil {
            return nil  // ← Currently returns here (no confirmation)
        }

        // ... retry logic ...
    }

    return fmt.Errorf("publish failed after %d attempts: %w", maxRetries, lastErr)
}
```

**NEW Publish() function (SAME SIGNATURE):**

```go
func Publish(ctx context.Context, destName, messageType, contentType string, body []byte) error {
    maxRetries := 3
    var lastErr error

    // Check if publisher confirms are enabled
    useConfirms := os.Getenv("RABBITMQ_PUBLISHER_CONFIRMS") != "false" // Default: enabled

    for attempt := 0; attempt < maxRetries; attempt++ {
        ch := GetChannel()
        if ch == nil {
            lastErr = fmt.Errorf("rabbitmq channel is nil")
            time.Sleep(time.Second * time.Duration(attempt+1))
            continue
        }

        // NEW: Decide whether to use confirms
        var err error
        if useConfirms {
            err = publishWithConfirms(ctx, ch, destName, messageType, contentType, body)
        } else {
            err = publishDirect(ctx, ch, destName, messageType, contentType, body)
        }

        if err == nil {
            return nil // ✅ Success (confirmed or not, depending on flag)
        }

        // Check if retryable
        if IsRetryableError(err) {
            lastErr = err
            common.L.Warn(
                fmt.Sprintf("publish failed (retryable): %v, retry %d/%d", err, attempt+1, maxRetries),
                common.F(ctx)...)
            time.Sleep(time.Second * time.Duration(attempt+1))
            continue
        }

        // Non-retryable error
        return err
    }

    return fmt.Errorf("publish failed after %d attempts: %w", maxRetries, lastErr)
}

// publishWithConfirms publishes with broker confirmation
func publishWithConfirms(ctx context.Context, ch *amqp.Channel, destName, messageType, contentType string, body []byte) error {
    timeout := 30 * time.Second
    if timeoutStr := os.Getenv("RABBITMQ_CONFIRM_TIMEOUT_SECONDS"); timeoutStr != "" {
        if seconds, err := strconv.Atoi(timeoutStr); err == nil && seconds > 0 {
            timeout = time.Duration(seconds) * time.Second
        }
    }

    publisher, err := NewPublisherWithConfirms(ch, timeout)
    if err != nil {
        return err
    }

    return publisher.PublishWithConfirm(
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
        },
    )
}

// publishDirect publishes without confirmation (legacy behavior)
func publishDirect(ctx context.Context, ch *amqp.Channel, destName, messageType, contentType string, body []byte) error {
    return ch.PublishWithContext(
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
        },
    )
}
```

**Impact:**
- ✅ Same function signature
- ✅ Existing callers work unchanged
- ✅ Can enable/disable via environment variable
- ✅ Backward compatible

---

## Feature Flag Configuration

### Enable Publisher Confirms (Recommended)

```bash
# In deployment config / docker-compose / k8s
export RABBITMQ_PUBLISHER_CONFIRMS=true

# Optional: Custom timeout (default 30s)
export RABBITMQ_CONFIRM_TIMEOUT_SECONDS=30
```

### Disable Publisher Confirms (Fallback if issues)

```bash
# Revert to old behavior without code changes
export RABBITMQ_PUBLISHER_CONFIRMS=false
```

### Default Behavior

If environment variable not set:
- **Default: ENABLED** (confirms on)
- Safe default for production
- Can override if needed

---

## Rollout Strategy

### Phase 1: Development Testing
```bash
# Enable in dev environment
export RABBITMQ_PUBLISHER_CONFIRMS=true

# Run existing tests - should all pass
go test ./...

# Run integration tests
make test-integration

# Verify: No code changes needed ✅
```

### Phase 2: Staging with Monitoring
```bash
# Enable in staging
export RABBITMQ_PUBLISHER_CONFIRMS=true

# Monitor metrics:
# - Publish latency (expect +10-20%)
# - Error rates (should decrease)
# - No new errors
```

### Phase 3: Production Gradual Rollout
```bash
# Option A: Canary deployment
# - 10% of pods with confirms enabled
# - Monitor for 24 hours
# - Increase to 50%, 100%

# Option B: Feature flag rollout
# - Enable confirms via config update
# - No code deployment needed
# - Can rollback instantly by changing env var
```

### Rollback Plan
```bash
# If issues found, instant rollback:
export RABBITMQ_PUBLISHER_CONFIRMS=false

# Or remove the environment variable:
unset RABBITMQ_PUBLISHER_CONFIRMS

# Restart services - back to old behavior
```

---

## Testing Checklist

**CRITICAL:** Every fix MUST be tested at all applicable levels:
1. Unit Tests
2. Component Tests
3. Integration Tests
4. End-to-End (E2E) Tests

### 1. Unit Tests

**Purpose:** Test individual functions in isolation

**New Unit Tests Required:**
```bash
# Create pkg/mq/common/errors_test.go
# Test IsRetryableError() with various error types

# Create pkg/mq/common/publisher_test.go
# Test PublisherWithConfirms creation
# Test PublishWithConfirm success/failure/timeout scenarios
# Test sequence number handling
# Test confirmation channel handling

# Update pkg/mq/common/helpers_test.go (if exists, or create new)
# Test Publish() with feature flag enabled/disabled
# Test publishWithConfirms() with various scenarios
# Test publishDirect() maintains legacy behavior
```

**Run Unit Tests:**
```bash
# Test all mq package
go test ./pkg/mq/... -v

# Test specific files
go test ./pkg/mq/common/errors_test.go -v
go test ./pkg/mq/common/publisher_test.go -v
go test ./pkg/mq/common/helpers_test.go -v

# Test with confirms enabled
RABBITMQ_PUBLISHER_CONFIRMS=true go test ./pkg/mq/... -v

# Test with confirms disabled
RABBITMQ_PUBLISHER_CONFIRMS=false go test ./pkg/mq/... -v

# Both should pass ✅
```

### 2. Component Tests

**Purpose:** Test MQ components with real RabbitMQ broker

**Component Test Scenarios:**
```bash
# Test 1: Publisher confirms with single message
# - Publish one message with confirms enabled
# - Verify broker ACK received
# - Verify no errors

# Test 2: Publisher confirms with multiple messages
# - Publish 100 messages rapidly
# - Verify all 100 ACKs received in order
# - Verify sequence numbers match

# Test 3: Publisher timeout handling
# - Configure very short timeout (1ms)
# - Publish message
# - Verify ErrPublishTimeout returned
# - Verify proper retry behavior

# Test 4: Broker NACK handling
# - Configure broker to NACK messages
# - Publish message
# - Verify ErrPublishNacked returned
# - Verify error is non-retryable

# Test 5: Channel closed during publish
# - Start publishing
# - Close channel mid-publish
# - Verify ErrChannelClosed returned
# - Verify error is retryable

# Test 6: Legacy mode (confirms disabled)
# - Set RABBITMQ_PUBLISHER_CONFIRMS=false
# - Publish messages
# - Verify publishDirect() used
# - Verify no confirmation waiting
```

**Run Component Tests:**
```bash
# Requires running RabbitMQ instance
docker-compose up -d rabbitmq

# Run component tests with confirms
RABBITMQ_PUBLISHER_CONFIRMS=true go test ./tests/component/mq/... -v

# Run component tests without confirms
RABBITMQ_PUBLISHER_CONFIRMS=false go test ./tests/component/mq/... -v
```

### 3. Integration Tests

**Purpose:** Test entire service with MQ integration

**Integration Test Scenarios:**
```bash
# Test 1: Exchange service with confirms
# - Start exchange daemon with confirms enabled
# - Publish orders through exchange MQ
# - Verify all messages confirmed
# - Verify no message loss

# Test 2: Trax saga with confirms
# - Start trax coordinator with confirms enabled
# - Submit saga with multiple steps
# - Verify each step message confirmed
# - Verify saga completes successfully

# Test 3: Treasury service with confirms
# - Start treasury service with confirms enabled
# - Publish treasury updates
# - Verify broker confirms all messages
# - Verify downstream consumers receive messages

# Test 4: Multi-service integration
# - Start all services with confirms enabled
# - Simulate real trading flow
# - Verify end-to-end message delivery
# - Verify no message loss across services

# Test 5: Backward compatibility
# - Start services with confirms DISABLED
# - Run same scenarios as above
# - Verify legacy behavior maintained
# - Verify existing code unchanged

# Test 6: Mixed environment
# - Some services with confirms enabled
# - Some services with confirms disabled
# - Verify interoperability
# - Verify no breaking changes
```

**Run Integration Tests:**
```bash
# Start full environment
docker-compose up -d

# Test with confirms enabled (recommended)
export RABBITMQ_PUBLISHER_CONFIRMS=true
go test ./tests/integration/... -v

# Test with confirms disabled (backward compat)
export RABBITMQ_PUBLISHER_CONFIRMS=false
go test ./tests/integration/... -v

# Test with mixed config
export RABBITMQ_PUBLISHER_CONFIRMS=true
# Start some services, then flip flag
export RABBITMQ_PUBLISHER_CONFIRMS=false
# Start other services
go test ./tests/integration/... -v
```

### 4. End-to-End (E2E) Tests

**Purpose:** Test complete user scenarios with confirms

**E2E Test Scenarios:**
```bash
# Test 1: Complete order lifecycle
# - Submit order → exchange → matching → settlement
# - Verify all MQ messages confirmed at each step
# - Verify order completes successfully
# - Verify no message loss in entire flow

# Test 2: Saga execution with confirms
# - Submit complex multi-step saga
# - Verify each saga step message confirmed
# - Verify compensation works if step fails
# - Verify saga state consistency

# Test 3: High-volume stress test
# - Publish 10,000 messages/second
# - Verify all messages confirmed
# - Verify no timeouts with confirms
# - Measure latency increase (should be < 20%)

# Test 4: Network partition recovery
# - Start publishing with confirms
# - Simulate network partition
# - Verify publishes fail with retryable errors
# - Restore network
# - Verify publishes resume and confirm

# Test 5: Broker restart during operations
# - Start publishing with confirms
# - Restart RabbitMQ broker
# - Verify reconnection works
# - Verify publishes resume with confirms
# - Verify no message loss

# Test 6: Performance comparison
# - Run E2E test with confirms DISABLED
# - Measure baseline latency and throughput
# - Run same E2E test with confirms ENABLED
# - Measure new latency and throughput
# - Verify < 20% increase acceptable
```

**Run E2E Tests:**
```bash
# Use existing E2E test framework
# Configure environment with confirms
export RABBITMQ_PUBLISHER_CONFIRMS=true

# Run full E2E test suite
make test-e2e

# Run specific E2E scenarios
go test ./tests/e2e/... -run TestOrderLifecycle -v
go test ./tests/e2e/... -run TestSagaExecution -v
go test ./tests/e2e/... -run TestHighVolume -v
go test ./tests/e2e/... -run TestNetworkPartition -v
go test ./tests/e2e/... -run TestBrokerRestart -v

# Performance comparison
RABBITMQ_PUBLISHER_CONFIRMS=false make test-e2e-perf > baseline.txt
RABBITMQ_PUBLISHER_CONFIRMS=true make test-e2e-perf > with-confirms.txt
diff baseline.txt with-confirms.txt
```

### 5. Backward Compatibility Test

**Purpose:** Ensure zero breaking changes

```bash
# Test existing code without recompilation
# Should work exactly as before

# Step 1: Build with new code
make build

# Step 2: Run existing binaries with flag disabled
export RABBITMQ_PUBLISHER_CONFIRMS=false
./bin/exchange &
./bin/trax &

# Step 3: Run legacy test suite (no changes)
go test ./... -v

# Step 4: All tests should pass ✅
```

### 6. Performance Benchmarks

**Purpose:** Measure performance impact

```bash
# Benchmark publish latency
go test ./pkg/mq/common -bench=BenchmarkPublish -benchmem

# Compare with/without confirms
RABBITMQ_PUBLISHER_CONFIRMS=false go test -bench=. > no-confirms.txt
RABBITMQ_PUBLISHER_CONFIRMS=true go test -bench=. > with-confirms.txt
benchstat no-confirms.txt with-confirms.txt

# Expected results:
# - Latency increase: 10-20%
# - Memory increase: < 5%
# - Throughput decrease: 10-15%
# - Acceptable tradeoff for zero message loss
```

---

## Testing Timeline

| Test Level | Duration | When to Run |
|-----------|----------|-------------|
| Unit Tests | 1-2 hours | After code changes |
| Component Tests | 2-3 hours | After unit tests pass |
| Integration Tests | 3-4 hours | After component tests pass |
| E2E Tests | 4-6 hours | Before deployment to staging |
| Performance Tests | 2-3 hours | After E2E tests pass |
| **Total** | **12-18 hours** | **Before production** |

---

## Test Success Criteria

### ✅ Unit Tests Success
- [ ] All new unit tests pass
- [ ] All existing unit tests pass unchanged
- [ ] Code coverage > 80% for new code
- [ ] No regressions

### ✅ Component Tests Success
- [ ] All component test scenarios pass
- [ ] Confirms enabled: All ACKs received
- [ ] Confirms disabled: Legacy behavior maintained
- [ ] Timeout handling works correctly
- [ ] Error handling works correctly

### ✅ Integration Tests Success
- [ ] All services start successfully
- [ ] End-to-end message delivery verified
- [ ] No message loss detected
- [ ] Backward compatibility verified
- [ ] Mixed environment works

### ✅ E2E Tests Success
- [ ] All E2E scenarios pass
- [ ] Complete workflows function correctly
- [ ] High-volume test passes
- [ ] Network partition recovery works
- [ ] Broker restart recovery works
- [ ] Performance acceptable (< 20% increase)

### ✅ Overall Success
- [ ] All test levels pass
- [ ] Zero breaking changes detected
- [ ] Performance impact acceptable
- [ ] Ready for staging deployment

---

## Migration Path for Existing Code

### Option 1: Do Nothing (Recommended)
```go
// This code works before and after - NO CHANGES
err := mqcommon.Publish(ctx, "x_exchange", "ORDER", "application/json", data)
```

**Result:** Automatically gets publisher confirms when flag enabled

### Option 2: Explicit Control (Optional, Future)
```go
// Optional: New function for explicit control (future enhancement)
// err := mqcommon.PublishWithOptions(ctx, destName, msg, PublishOptions{
//     Confirms: true,
//     Timeout:  30 * time.Second,
// })
```

**Result:** Explicit control, but not needed initially

---

## Benefits of This Approach

### ✅ Zero Breaking Changes
- Existing code works unchanged
- No refactoring needed
- No import changes
- No signature changes

### ✅ Gradual Rollout
- Enable per-environment
- Test in dev first
- Canary in production
- Instant rollback

### ✅ Feature Flag Control
- Enable/disable without deployment
- No code changes to toggle
- Safe experimentation

### ✅ Backward Compatible
- Old behavior available
- Can disable if issues
- No forced migration

### ✅ Forward Compatible
- Future: Add explicit options
- Future: Per-message control
- Future: Advanced features

---

## Implementation Steps

### Step 1: Create New Files (1 hour)
```bash
# Create errors.go
touch pkg/mq/common/errors.go
# Add error types

# Create publisher.go
touch pkg/mq/common/publisher.go
# Add PublisherWithConfirms
```

**Impact:** Zero - new files only

### Step 2: Update Publish() (2 hours)
```bash
# Edit pkg/mq/common/helpers.go
# Add publishWithConfirms() and publishDirect()
# Update Publish() to use feature flag
```

**Impact:** Zero to callers - internal changes only

### Step 3: Test (2 hours)
```bash
# Run existing tests - should all pass
go test ./pkg/mq/...

# Test with flag enabled
RABBITMQ_PUBLISHER_CONFIRMS=true go test ./pkg/mq/...

# Test with flag disabled
RABBITMQ_PUBLISHER_CONFIRMS=false go test ./pkg/mq/...
```

**Impact:** Zero - validates no breaking changes

### Step 4: Deploy to Dev (1 hour)
```bash
# Update dev environment config
export RABBITMQ_PUBLISHER_CONFIRMS=true

# Deploy (no code changes needed elsewhere)
# Monitor logs for "confirmed" messages
```

**Impact:** Zero to code - config change only

### Step 5: Monitor & Rollout (1-2 days)
```bash
# Monitor dev for 24 hours
# Check staging
# Gradual production rollout
```

---

## Total Impact Summary

### Code Changes Required
| Component | Changes | Breaking |
|-----------|---------|----------|
| Callers (200+ sites) | **0 lines** | ❌ No |
| Publish() signature | **0 changes** | ❌ No |
| Imports | **0 new imports** | ❌ No |
| Configuration | **+2 env vars** | ❌ No |
| New files | **+2 files** | ❌ No |
| Modified files | **1 file** | ❌ No |

### Rollout Risk
- 🟢 **Low** - feature flag controlled
- 🟢 **Reversible** - instant rollback
- 🟢 **Testable** - verify in dev/staging
- 🟢 **Gradual** - canary deployment

### Timeline
- **Development:** 4-6 hours
- **Testing:** 2-4 hours
- **Rollout:** 1-2 days
- **Total:** ~3 days (with safety buffer)

---

## Success Criteria

### ✅ Implementation Complete When:
- [ ] New files created (errors.go, publisher.go)
- [ ] Publish() updated with feature flag
- [ ] All existing tests pass unchanged
- [ ] Tests pass with confirms enabled
- [ ] Tests pass with confirms disabled
- [ ] No breaking changes detected

### ✅ Rollout Complete When:
- [ ] Dev environment validated (24 hours)
- [ ] Staging environment validated (24 hours)
- [ ] Production canary successful (24 hours)
- [ ] 100% production deployment
- [ ] Zero message loss confirmed
- [ ] Performance acceptable (<20% latency increase)

---

## Questions & Answers

**Q: Do I need to change all my Publish() call sites?**
**A:** No! Zero changes needed. Confirms happen transparently inside.

**Q: What if confirms cause issues?**
**A:** Set `RABBITMQ_PUBLISHER_CONFIRMS=false` to instantly rollback.

**Q: Will this break my code?**
**A:** No. Same function signature, same behavior from caller perspective.

**Q: What about performance?**
**A:** 10-20% slower publish (one network round-trip). Worth it for zero message loss.

**Q: Can I test before enabling in production?**
**A:** Yes! Test in dev/staging first with feature flag.

**Q: How do I know it's working?**
**A:** Check logs for "confirmed" messages. Monitor error rates (should decrease).

---

## Next Steps

1. **Review this plan** with team
2. **Create the 3 files** (errors.go, publisher.go, update helpers.go)
3. **Test locally** with existing code
4. **Deploy to dev** with flag enabled
5. **Monitor** for 24 hours
6. **Gradual rollout** to production

**Estimated Total Time:** 3 days (development + testing + rollout)

**Risk Level:** 🟢 Low (feature flag controlled, zero breaking changes)

---

**Ready to implement?** The changes are small, isolated, and fully backward compatible.

---

## Update: February 2026 - Architecture Changes Affecting This Plan

### Topic Exchange Migration (2026-02-12)

The MQ architecture was significantly changed with the introduction of **topic exchange routing** for TRAX saga orchestration:

- **Scale of change**: ~2000 queues reduced to ~10, ~2000 exchanges reduced to 1
- **New MQ functions**: `InitTopicExchange()`, `InitQueueWithTopicBinding()`, `PublishWithRoutingKey()`
- **Impact on this plan**: Publisher confirms implementation must also cover `PublishWithRoutingKey()`, not just `Publish()`
- **Routing pattern**: Messages use routing keys like `saga.{affinity}.step.{step_name}` instead of publishing to per-step fanout exchanges
- **Channel pool**: Default reduced from 1000 to 100 channels, `DrainPool()` deadlock fixed
- **Reduced queue count**: Topic exchange dramatically reduces queue count (~99.5%), which reduces surface area for publisher confirm overhead

### Coordinator Error Handling (2026-02-13)

Sentinel errors and ACK+drop behavior were added to the coordinator's result queue consumer:

- Messages for non-existent saga instances/steps are now ACK+dropped instead of NACK+requeued
- This prevents infinite requeue loops that could compound with publisher confirm timeouts
- These changes are in `pkg/trax/coordinator.go` and affect the consumer side, not the publisher side

### Status

This plan document remains **NOT YET IMPLEMENTED**. It is still a valid plan for adding publisher confirms to the `Publish()` and `PublishWithRoutingKey()` functions. The topic exchange change does not invalidate the approach but does expand the scope slightly.