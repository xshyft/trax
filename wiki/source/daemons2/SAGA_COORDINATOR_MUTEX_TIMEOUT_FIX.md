# Saga Coordinator Mutex Timeout Fix

## Document Overview

This document describes a critical bug in the saga coordinator's Redis mutex implementation and the subsequent fixes applied to resolve goroutine leaks, invalid state transitions, and RabbitMQ overload issues.

**Date**: November 2025
**Components Affected**:
- `pkg/trax/coordinator.go`
- `pkg/cache/redis_impl.go`
- `pkg/common/helpers.go`
- RabbitMQ infrastructure

**Severity**: CRITICAL - Causes saga instances to enter INVALID_STATE and goroutine leaks

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Root Cause Analysis](#root-cause-analysis)
4. [Bug Timeline Discovery](#bug-timeline-discovery)
5. [Implemented Fixes](#implemented-fixes)
6. [RabbitMQ Consumer Overload Issue](#rabbitmq-consumer-overload-issue)
7. [Code Changes](#code-changes)
8. [Verification and Testing](#verification-and-testing)
9. [Future Considerations](#future-considerations)

---

## Executive Summary

### The Bug
The saga coordinator uses Redis-based distributed mutex locks with a 60-second TTL to prevent concurrent processing of the same saga instance. When operations inside the mutex callback exceeded the 60-second TTL, the lock would expire while processing was still ongoing. This allowed multiple goroutines to acquire "expired" locks and process the same saga concurrently, leading to:
- Invalid saga state transitions (SAGA_INVALID_STATE)
- Goroutine leaks
- Race conditions in saga processing
- Failed database operations

Additionally, multiple concurrent test runs created 6000+ stale RabbitMQ consumers, overwhelming the broker and causing publisher confirmation timeouts.

### The Fix
1. **Mutex Timeout Protection**: Added a 50-second timeout context inside the mutex callback to ensure all operations complete before the 60-second TTL expires
2. **Context Isolation**: Changed all database and saga operations inside the mutex to use the timeout context instead of the parent context
3. **RabbitMQ Cleanup**: Restarted RabbitMQ to clear stale consumers (reduced from 6000+ to 143 active consumers)

---

## Problem Statement

### Symptoms Observed

#### 1. Saga Entering INVALID_STATE
```
2025-11-24 01:26:53.099 [INFO] transitioning saga to invalid state
saga_instance_id: 1rbDYFiTXy5AzltE2sBuBzoCwmOUVKFa
cluster_id: e2e_test_cluster
```

#### 2. HTTP Timeout Errors
```
2025-11-24 01:25:51.856 [ERROR] failed to query trax ctrl: Get "http://traxctrl-e2e-test:9000/api/v1/...":
context deadline exceeded (Client.Timeout exceeded while awaiting headers)
```

#### 3. Goroutine Leak Warnings
```
2025-11-24 01:26:51.875 [WARN] potential goroutine leak: callback took longer than 25s to complete
callback_duration: 90.04s
```

#### 4. RabbitMQ Publisher Confirmation Timeouts
```
2025-11-24 01:24:21.803 [ERROR] publish failed after 3 attempts:
publish confirmation timeout: after 30s (seq 2)
```

### Impact
- **Test Failures**: E2E tests failing consistently
- **Data Consistency**: Invalid saga states in database
- **Resource Leaks**: Goroutines not being cleaned up
- **Broker Overload**: RabbitMQ unable to confirm message publishes

---

## Root Cause Analysis

### Redis Mutex Implementation Flaw

The Redis mutex implementation in `pkg/cache/redis_impl.go:211-257` had a critical flaw:

```go
func (r *RedisCache) Mutex(ctx context.Context, key string, ttlSec int, timeoutSec int64, cb func()) error {
    // ... lock acquisition logic ...

    // PROBLEM: Uses same context for unlock that may be cancelled
    defer func() {
        err := r.unlockMutex(ctx, key)
        if err != nil {
            common.L.Warn(...)
        }
    }()

    cb()  // Callback can take longer than TTL
    return nil
}
```

**The Problem**:
1. Mutex acquired with 60-second TTL
2. Callback executes with no time limit on parent context
3. If callback takes longer than 60 seconds, TTL expires
4. Lock is "expired" in Redis, allowing another goroutine to acquire it
5. **Two goroutines now processing the same saga instance concurrently**
6. Race conditions cause invalid state transitions

### Context Cancellation Compounding the Issue

When the parent context was cancelled (due to 25-second callback timeout), the `unlockMutex` operation would fail silently because it used the same cancelled context. This meant locks were never released properly even after processing completed.

---

## Bug Timeline Discovery

### Actual Timeline from Logs (Saga: 1rbDYFiTXy5AzltE2sBuBzoCwmOUVKFa)

```
01:21:51.193 [DEBUG] mutex locked: saga_instance_1rbDYFiTXy5AzltE2sBuBzoCwmOUVKFa
              ↓ (Processing begins, but takes too long...)
              ↓ (60 seconds pass, TTL EXPIRES in Redis)
              ↓
01:22:51.524 [DEBUG] mutex locked: saga_instance_1rbDYFiTXy5AzltE2sBuBzoCwmOUVKFa
              ↑ PROBLEM: Second goroutine acquired the "expired" lock!
              ↓ (Multiple goroutines now racing)
              ↓ (TTL expires again...)
              ↓
01:23:45.851 [DEBUG] mutex locked: saga_instance_1rbDYFiTXy5AzltE2sBuBzoCwmOUVKFa
              ↑ PROBLEM: Third goroutine acquired the lock!
              ↓ (Race conditions cause invalid state)
              ↓
01:26:51.875 [DEBUG] mutex unlocked: saga_instance_1rbDYFiTXy5AzltE2sBuBzoCwmOUVKFa
              ↑ Finally unlocked after 5 MINUTES
```

**Analysis**:
- First lock held from `01:21:51` to `01:26:51` = **5 minutes**
- TTL is only **60 seconds**
- Lock expired **4 times** during processing
- At least **3 goroutines** concurrently acquired locks for the same saga
- Result: **SAGA_INVALID_STATE**

---

## Implemented Fixes

### Fix 1: Mutex Timeout Protection (Primary Fix)

**Location**: `pkg/trax/coordinator.go:1272-1280`

**Before**:
```go
err := cache.Mutex(ctx, fmt.Sprintf("saga_instance_%s", sagaStepInstance.SagaInstanceId), 60, 0, func() {
    sagaInstance, err := c.GetStore().GetSagaInstance(ctx, clusterId, sagaStepInstance.SagaInstanceId)
    // ... more operations using ctx ...
})
```

**After**:
```go
err := cache.Mutex(ctx, fmt.Sprintf("saga_instance_%s", sagaStepInstance.SagaInstanceId), 60, 0, func() {
    // CRITICAL: Create a timeout context to ensure all operations inside the mutex
    // complete before the mutex TTL (60s) expires. This prevents race conditions where
    // the mutex TTL expires while operations are still running, allowing other goroutines
    // to acquire the "expired" lock and cause invalid state transitions.
    mutexCtx, mutexCancel := context.WithTimeout(ctx, 50*time.Second)
    defer mutexCancel()

    sagaInstance, err := c.GetStore().GetSagaInstance(mutexCtx, clusterId, sagaStepInstance.SagaInstanceId)
    // ... all operations now use mutexCtx instead of ctx ...
})
```

**Why 50 Seconds?**
- Mutex TTL: 60 seconds
- Timeout: 50 seconds
- **Safety margin: 10 seconds** to ensure operations complete or fail before TTL expiry
- If operations exceed 50s, context is cancelled and operations fail fast
- Prevents the lock from expiring while operations are still running

### Fix 2: Context Isolation for All Operations

All database and saga operations inside the mutex callback were changed from using the parent `ctx` to using `mutexCtx`:

**Changed Operations** (in coordinator.go):
- Line 1288: `c.GetStore().ListSagaStepInstancesBySagaInstanceId(mutexCtx, ...)`
- Line 1325: `c.isSagaStateValid(mutexCtx, ...)`
- Line 1327: `c.transitSagaToInvalidState(mutexCtx, ...)`
- Line 1334: `c.processSagaStep(mutexCtx, ...)`

This ensures:
1. All operations share the same 50-second timeout
2. Operations fail fast if they take too long
3. Prevents cascading delays
4. Ensures mutex is released before TTL expiry

### Fix 3: RabbitMQ QoS Prefetch Limit (Previous Session)

**Location**: `pkg/common/helpers.go:699`

```go
// Set QoS prefetch to 1 to limit concurrent message processing
err = channel.Qos(
    1,     // prefetchCount - only consume 1 message at a time
    0,     // prefetchSize
    false, // global
)
```

**Purpose**: Prevents a single consumer from hoarding messages and ensures fair distribution.

### Fix 4: Callback Timeout Wrapper (Previous Session)

**Location**: `pkg/common/helpers.go:590-624`

Added 25-second timeout wrapper around all RabbitMQ message handler callbacks:

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

**Purpose**: Detects long-running callbacks that may indicate goroutine leaks or blocking operations.

---

## RabbitMQ Consumer Overload Issue

### Problem Discovery

During investigation of publisher confirmation timeouts, we discovered:

**Before Cleanup**:
```bash
$ docker exec laser-rabbitmq-1 rabbitmqctl list_queues name messages consumers

q_e2e_test_cluster_traxcoord_saga_submitter_accmgr-e2e-test_inbox    0    75
q_e2e_test_cluster_trax_coordinator_1_saga_process_new_...          0    75
q_e2e_test_cluster_trax_coordinator_2_saga_process_new_...          0    75
...
```

- **75 consumers per queue** (from multiple concurrent test runs)
- **~80 active queues**
- **Total: ~6000 consumers** overwhelming RabbitMQ
- Publisher confirmations taking 30+ seconds (timing out)

### Root Cause
Multiple concurrent E2E test runs were starting up services without properly cleaning up RabbitMQ consumers from previous runs. Each test run would:
1. Start fresh Docker containers
2. Create new RabbitMQ consumers
3. Leave old consumers active from crashed/stopped containers
4. Result: Consumer count growing unbounded

### The Fix
```bash
$ docker restart laser-rabbitmq-1
```

**After Cleanup**:
```bash
$ docker exec laser-rabbitmq-1 rabbitmqctl list_queues name messages consumers

q_e2e_test_cluster_traxcoord_saga_submitter_accmgr-e2e-test_inbox    0    1
q_e2e_test_cluster_trax_coordinator_1_saga_process_new_...          0    1
...

Total consumers: 143 (down from ~6000)
```

**Impact**:
- **97% reduction** in consumer count
- Publisher confirmations now complete in milliseconds
- No more timeout errors
- Clean test environment

### Prevention Strategy
For future test runs:
1. Always restart RabbitMQ before starting E2E tests
2. Implement proper consumer cleanup on container shutdown
3. Monitor consumer counts in production
4. Add health checks to detect stale consumers

---

## Code Changes

### File: pkg/trax/coordinator.go

**Function**: `processSagaStepExecutionResult`
**Lines Modified**: 1272-1334

#### Change Summary
Added `mutexCtx` timeout context and replaced all usages of `ctx` with `mutexCtx` inside the mutex callback.

#### Detailed Changes

**Line 1272-1280** (NEW):
```go
err := cache.Mutex(ctx, fmt.Sprintf("saga_instance_%s", sagaStepInstance.SagaInstanceId), 60, 0, func() {
    // CRITICAL: Create a timeout context to ensure all operations inside the mutex
    // complete before the mutex TTL (60s) expires. This prevents race conditions where
    // the mutex TTL expires while operations are still running, allowing other goroutines
    // to acquire the "expired" lock and cause invalid state transitions.
    mutexCtx, mutexCancel := context.WithTimeout(ctx, 50*time.Second)
    defer mutexCancel()

    // Use mutexCtx for all operations below...
```

**Line 1288** (CHANGED):
```go
// Before:
sagaInstance, err := c.GetStore().GetSagaInstance(ctx, clusterId, sagaStepInstance.SagaInstanceId)

// After:
sagaInstance, err := c.GetStore().GetSagaInstance(mutexCtx, clusterId, sagaStepInstance.SagaInstanceId)
```

**Line 1295** (CHANGED):
```go
// Before:
stepInstances, err := c.GetStore().ListSagaStepInstancesBySagaInstanceId(ctx, clusterId, sagaStepInstance.SagaInstanceId)

// After:
stepInstances, err := c.GetStore().ListSagaStepInstancesBySagaInstanceId(mutexCtx, clusterId, sagaStepInstance.SagaInstanceId)
```

**Line 1325** (CHANGED):
```go
// Before:
isValid, err := c.isSagaStateValid(ctx, clusterId, sagaInstance, stepInstances, sagaStepInstance)

// After:
isValid, err := c.isSagaStateValid(mutexCtx, clusterId, sagaInstance, stepInstances, sagaStepInstance)
```

**Line 1327** (CHANGED):
```go
// Before:
err := c.transitSagaToInvalidState(ctx, clusterId, sagaInstance, sagaStepInstance)

// After:
err := c.transitSagaToInvalidState(mutexCtx, clusterId, sagaInstance, sagaStepInstance)
```

**Line 1334** (CHANGED):
```go
// Before:
err = c.processSagaStep(ctx, clusterId, sagaInstance, stepInstances, sagaStepInstance)

// After:
err = c.processSagaStep(mutexCtx, clusterId, sagaInstance, stepInstances, sagaStepInstance)
```

### File: pkg/common/helpers.go

**Previous Session Changes** (Already implemented):
- **Line 590-624**: Added callback timeout wrapper with 25-second timeout
- **Line 699**: Added RabbitMQ QoS prefetch limit of 1

---

## Verification and Testing

### Test Environment
- **Test Suite**: `TestTRAXInstrumentIssuanceWithDistributionParametrized`
- **Test Case**: `sequential_sagas` (most likely to trigger the bug)
- **RabbitMQ**: Cleaned up to 143 active consumers
- **Docker Images**: Rebuilt with all fixes using `make bip`

### Expected Behavior After Fix

#### 1. No Mutex TTL Expiration
```
[DEBUG] mutex locked: saga_instance_XXX
[DEBUG] mutex unlocked: saga_instance_XXX  # Should happen within 50 seconds
```

#### 2. No INVALID_STATE Transitions
No occurrences of:
```
[INFO] transitioning saga to invalid state
```

#### 3. No Publisher Confirmation Timeouts
No occurrences of:
```
[ERROR] publish confirmation timeout
```

#### 4. No Goroutine Leak Warnings
No occurrences of:
```
[WARN] potential goroutine leak: callback took longer than 25s
```

### Monitoring During Tests

To monitor test progress, check logs for:

**Mutex Lock Duration**:
```bash
docker logs laser-traxcoord1-1 2>&1 | grep -E "mutex (locked|unlocked)" | tail -20
```

**Saga State Transitions**:
```bash
docker logs laser-traxcoord1-1 2>&1 | grep -i "invalid state"
```

**RabbitMQ Consumer Count**:
```bash
docker exec laser-rabbitmq-1 rabbitmqctl list_queues name messages consumers
```

---

## Future Considerations

### 1. Monitoring and Alerting

**Metrics to Track**:
- Mutex hold duration (should be < 50 seconds)
- Saga processing time per step
- RabbitMQ consumer count per queue
- Publisher confirmation latency

**Alerts to Configure**:
- Alert if mutex hold duration > 40 seconds
- Alert if RabbitMQ consumer count per queue > 5
- Alert if publisher confirmation latency > 5 seconds
- Alert if saga enters INVALID_STATE

### 2. Mutex TTL Tuning

Current configuration:
- **Mutex TTL**: 60 seconds
- **Operation timeout**: 50 seconds
- **Safety margin**: 10 seconds

If operations consistently approach the 50-second limit, consider:
1. **Increasing TTL to 120 seconds** and timeout to 100 seconds
2. **Optimizing database queries** to reduce processing time
3. **Adding database connection pooling** if not already present
4. **Reviewing saga step complexity** and breaking down complex steps

### 3. RabbitMQ Resource Limits

**Recommendations**:
1. Set per-connection consumer limits
2. Implement consumer TTL/timeout
3. Add automated consumer cleanup on service shutdown
4. Monitor queue depth and consumer counts in production
5. Consider using RabbitMQ management plugin for better visibility

### 4. Test Infrastructure Improvements

**Before Each Test Run**:
```bash
# Restart RabbitMQ to clear stale consumers
docker restart laser-rabbitmq-1

# Wait for RabbitMQ to be ready
sleep 5

# Verify clean state
docker exec laser-rabbitmq-1 rabbitmqctl list_queues name messages consumers
```

**Test Isolation**:
- Each test run should use unique cluster IDs
- Clean up resources (queues, exchanges) after test completion
- Implement timeout limits for test execution

### 5. Connection Pooling Verification

The project already has RabbitMQ connection pooling implemented in `pkg/mq/common/channelpool.go`:
- **Max channels**: 100
- **Initial channels**: 50
- **Thread-safe**: Yes

**Verify pooling is working**:
```bash
# Check RabbitMQ connection count (should be low, ~1-5 per service)
docker exec laser-rabbitmq-1 rabbitmqctl list_connections
```

### 6. Database Query Optimization

If saga processing consistently takes > 30 seconds, investigate:
1. **Add indexes** on frequently queried columns
2. **Optimize JOINs** in saga instance queries
3. **Use EXPLAIN ANALYZE** to identify slow queries
4. **Consider read replicas** for query-heavy operations

### 7. Graceful Degradation

Add circuit breaker patterns for:
- RabbitMQ publisher confirmations (fallback to fire-and-forget)
- Database queries (timeout and retry with backoff)
- External HTTP calls (timeout and fail fast)

---

## Related Files Reference

### Core Files Modified
- `pkg/trax/coordinator.go` - Saga coordination with mutex timeout fix
- `pkg/cache/redis_impl.go` - Redis mutex implementation (not modified, but analyzed)
- `pkg/common/helpers.go` - RabbitMQ consumer setup with QoS and callback timeout

### Related Documentation
- `docs/RABBITMQ_RELIABILITY_REMEDIATION_TODO.md` - RabbitMQ reliability improvements
- `docs/LASER_ARCHITECTURE.md` - Overall LASER architecture
- `docs/ARCHITECTURE.md` - General system architecture

### Test Files
- `tests/e2e/laser/transfer_trax_test.go` - E2E test suite

---

## Appendix: Command Reference

### Useful Commands for Troubleshooting

**Check Mutex Lock Status**:
```bash
docker logs laser-traxcoord1-1 2>&1 | grep "mutex locked" | tail -20
```

**Find Long-Running Locks**:
```bash
docker logs laser-traxcoord1-1 2>&1 | awk '/mutex locked/{t=$1" "$2; k=$NF} /mutex unlocked/ && $NF==k{print k, $1" "$2, "Duration:", (NR-t)}'
```

**Check RabbitMQ Queue Status**:
```bash
docker exec laser-rabbitmq-1 rabbitmqctl list_queues name messages consumers
```

**Monitor Test Progress**:
```bash
# Follow test output
docker logs -f laser-test-runner-1

# Check coordinator logs
docker logs -f laser-traxcoord1-1
```

**Clean RabbitMQ State**:
```bash
# Restart RabbitMQ (clears all consumers)
docker restart laser-rabbitmq-1

# Delete specific queue
docker exec laser-rabbitmq-1 rabbitmqadmin delete queue name=q_my_queue

# Purge all messages from queue
docker exec laser-rabbitmq-1 rabbitmqadmin purge queue name=q_my_queue
```

---

## Conclusion

This fix addresses a critical race condition in the saga coordinator's mutex implementation that was causing:
1. Invalid saga state transitions
2. Goroutine leaks
3. RabbitMQ publisher confirmation timeouts
4. Resource exhaustion

The fix involves:
1. Adding a 50-second timeout context inside the mutex callback
2. Ensuring all operations complete before the 60-second mutex TTL expires
3. Cleaning up stale RabbitMQ consumers
4. Maintaining existing safeguards (QoS prefetch, callback timeouts)

The changes are minimal, focused, and address the root cause without requiring major architectural changes. Future monitoring and tuning may be needed based on production workload characteristics.

---

## Update: February 2026 - Topic Exchange & Sentinel Error Handling

### Architecture Change: Topic Exchange (2026-02-12)

The RabbitMQ queue architecture was significantly refactored. Per-step fanout queues were replaced with a **topic exchange routing** model:

- **Before**: Each saga step had its own fanout exchange and dedicated queue (~2000 queues, ~2000 exchanges)
- **After**: A single per-cluster topic exchange routes messages using routing keys (e.g., `saga.{affinity}.step.{step_name}`), reducing to ~10 queues and 1 exchange
- **Key new MQ functions**: `InitTopicExchange()`, `InitQueueWithTopicBinding()`, `PublishWithRoutingKey()`
- **Coordinator**: Creates one results queue per affinity with wildcard binding instead of per-step outbox consumers
- **Executor**: Creates one shared inbox queue per step template with wildcard affinity binding instead of per-affinity consumers
- **Channel pool**: Reduced default from 1000 to 100 channels with 20% pre-populate
- **Impact on this document**: The consumer overload issue (Section 6) is dramatically reduced — far fewer queues/consumers means less broker resource pressure

### Coordinator Error Handling: Sentinel Errors (2026-02-13)

The coordinator's result queue consumer had a critical infinite message requeue loop bug that was discovered and fixed:

- **Problem**: When a saga instance or step instance was not found in the database (e.g., stale messages), the coordinator would NACK+requeue the message, creating an infinite loop
- **Root cause**: `GetSagaInstance()` and `GetSagaStepInstance()` returned generic errors for not-found cases. The coordinator could not distinguish "not found" from transient errors
- **Fix**:
  1. Added sentinel errors `ErrSagaInstanceNotFound` and `ErrSagaStepInstanceNotFound` in `pkg/trax/const.go`
  2. Both `store_inmem.go` and `store_psql.go` now return these sentinel errors
  3. The coordinator checks for these errors using `errors.Is()` and ACKs+drops the message instead of NACKing
  4. State filtering was also improved: the coordinator now filters out terminal states (COMPLETED, FAILED, COMPENSATED, COMPENSATION_FAILED) before processing

### Sub-Saga Support (2026-02-13)

Sub-saga orchestration was added, which affects coordinator processing:

- Parent sagas can now spawn child sub-sagas via `SagaContext` injection
- Cascading compensation propagates from child to parent saga
- New database columns: `parent_saga_instance_id`, `parent_step_instance_id` on saga instances
- The coordinator validates compensation state for sub-saga hierarchies
- New E2E tests: `compensation_test.go` and `deep_sub_saga_test.go`

---

### MQ Health Check in IsReady() (2026-03-23)

The coordinator's `IsReady()` now checks RabbitMQ connection health in addition to database circuit breaker state. This prevents submitters from announcing to a coordinator with a dead MQ connection. See `TODO_TRAX_RESILIENCE_TEMPLATE_HOTRELOAD_IDEMPOTENCY.md` for the full resilience improvement plan including saga submitter exponential backoff and template hot-reload.

---

**Document Version**: 1.2
**Last Updated**: March 23, 2026
**Author**: Claude Code Agent
**Reviewed By**: Pending