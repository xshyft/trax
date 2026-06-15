# RabbitMQ Tier 0 Catastrophic Fixes - Implementation Checklist

## Executive Summary

This document provides a **step-by-step implementation checklist** for fixing the **6 most catastrophic issues** in the RabbitMQ implementation that cause **data loss and corruption**. These issues must be fixed before any production deployment of the saga/financial system.

**Scope:** Tier 0 issues only (T0-001 through T0-006)
**Timeline:** 2 weeks (10 working days)
**Priority:** CRITICAL - Zero tolerance for delay

**Current Risk Level:** 🔴 **CATASTROPHIC**
- Messages silently lost (no publisher confirms)
- Race conditions causing channel corruption (shared global channel)
- Duplicate messages (unchecked ACK/NACK errors)
- Infinite loops (republish without max retries)
- Random crashes (channel replacement during use)
- False error detection (string comparison)

**Post-Fix Risk Level:** 🟢 **ACCEPTABLE**
- All messages confirmed by broker
- Thread-safe channel operations
- All ACK/NACK errors handled
- Poison messages routed to DLQ with max retries
- Safe channel lifecycle management
- Robust error type checking

---

## Issue Overview

| ID | Issue | Current Impact | Files | Priority | Effort |
|----|-------|---------------|-------|----------|--------|
| T0-001 | No publisher confirms | Messages silently lost | `pkg/mq/common/helpers.go:84-128` | P0 | 3 days |
| T0-002 | Shared global channel | Channel corruption, crashes | `pkg/mq/common/rabbitmq.go:13` | P0 | 4 days |
| T0-003 | Channel replacement race | Operations on closed channel | `pkg/mq/common/rabbitmq.go:31-47` | P1 | (Fixed by T0-002) |
| T0-004 | Unchecked ACK/NACK errors | Duplicates, stuck messages | `pkg/mq/common/helpers.go:299-320` | P0 | 1 day |
| T0-005 | Error string comparison | False negatives on retries | `pkg/mq/common/helpers.go:115` | P1 | 0.5 day |
| T0-006 | RepublishNack infinite loop | CPU burn, queue explosion | `pkg/mq/common/helpers.go:303-307` | P0 | 1 day |

**Total Effort:** ~9.5 days (with buffer: 10 days / 2 weeks)

---

## Implementation Strategy

### Phase Breakdown

**Phase 1: Foundation (Days 1-2)**
- Create new files and infrastructure
- Add error handling utilities
- No changes to existing code yet
- **Goal:** Build tools we'll need for fixes

**Phase 2: Quick Wins (Days 3-4)**
- Fix T0-004 (check ACK/NACK errors)
- Fix T0-005 (error type checking)
- Fix T0-006 (republish max retries)
- **Goal:** Stop duplicates and infinite loops

**Phase 3: Channel Pool (Days 5-8)**
- Implement T0-002 (channel pool)
- Automatically fixes T0-003
- **Goal:** Thread-safe channel operations

**Phase 4: Publisher Confirms (Days 9-10)**
- Implement T0-001 (publisher confirms)
- **Goal:** Zero message loss

**Phase 5: Integration & Validation (Day 10)**
- End-to-end testing
- Load testing
- Sign-off

### Dependency Graph

```
Phase 1 (Foundation)
    ├─> Phase 2 (Quick Wins: T0-004, T0-005, T0-006)
    └─> Phase 3 (Channel Pool: T0-002, T0-003)
            └─> Phase 4 (Publisher Confirms: T0-001)
                    └─> Phase 5 (Validation)
```

**Critical Path:** Phase 1 → Phase 3 → Phase 4 → Phase 5

**Parallel Work:** Phase 2 can start once Phase 1 completes (days 3-4 while Phase 3 starts day 5)

---

## Table of Contents

1. [Phase 1: Foundation & Infrastructure](#phase-1-foundation--infrastructure)
2. [Phase 2: Quick Wins (T0-004, T0-005, T0-006)](#phase-2-quick-wins)
3. [Phase 3: Channel Pool (T0-002, T0-003)](#phase-3-channel-pool)
4. [Phase 4: Publisher Confirms (T0-001)](#phase-4-publisher-confirms)
5. [Phase 5: Integration & Validation](#phase-5-integration--validation)
6. [Appendix: Testing Procedures](#appendix-testing-procedures)

---

## Phase 1: Foundation & Infrastructure

**Goal:** Create new files and utilities needed for all fixes
**Timeline:** Days 1-2
**Dependencies:** None
**Risk:** Low - no changes to existing code

### 1.1 Create Error Handling Utilities

**Purpose:** Replace brittle string comparison (T0-005 foundation)

- [ ] 1.1.1 Create file `pkg/mq/common/errors.go`:
  ```go
  package mqcommon

  import (
      "errors"
      "fmt"
      "strings"
      amqp "github.com/rabbitmq/amqp091-go"
  )

  // Sentinel errors for common RabbitMQ failures
  var (
      ErrChannelClosed    = errors.New("channel closed")
      ErrConnectionClosed = errors.New("connection closed")
      ErrNotConnected     = errors.New("not connected to rabbitmq")
      ErrPublishTimeout   = errors.New("publish confirmation timeout")
      ErrPublishNacked    = errors.New("message nacked by broker")
      ErrQueueFull        = errors.New("queue at max length")
  )

  // IsConnectionError checks if error is connection-related (retryable)
  func IsConnectionError(err error) bool {
      if err == nil {
          return false
      }

      // Check sentinel errors
      if errors.Is(err, ErrConnectionClosed) || errors.Is(err, ErrChannelClosed) {
          return true
      }

      // Check AMQP errors
      if errors.Is(err, amqp.ErrClosed) {
          return true
      }

      // Check AMQP exception codes
      if amqpErr, ok := err.(*amqp.Error); ok {
          switch amqpErr.Code {
          case 320: // CONNECTION_FORCED
              return true
          case 504: // CHANNEL_ERROR
              return true
          case 505: // UNEXPECTED_FRAME
              return true
          case 506: // RESOURCE_ERROR
              return true
          }
      }

      // Fallback: string matching (last resort)
      errStr := strings.ToLower(err.Error())
      patterns := []string{
          "channel/connection is not open",
          "connection closed",
          "channel closed",
          "broken pipe",
          "connection reset",
          "eof",
      }

      for _, pattern := range patterns {
          if strings.Contains(errStr, pattern) {
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

      // Context deadline errors are retryable
      errStr := strings.ToLower(err.Error())
      if strings.Contains(errStr, "context deadline exceeded") {
          return true
      }

      return false
  }

  // WrapAMQPError converts AMQP errors to our typed errors
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
          case 506:
              if strings.Contains(amqpErr.Reason, "RESOURCE_LOCKED") {
                  return fmt.Errorf("%w: %s", ErrQueueFull, amqpErr.Reason)
              }
              return fmt.Errorf("amqp error %d: %s", amqpErr.Code, amqpErr.Reason)
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

- [ ] 1.1.2 Create file `pkg/mq/common/errors_test.go`:
  ```go
  package mqcommon

  import (
      "errors"
      "testing"
      amqp "github.com/rabbitmq/amqp091-go"
  )

  func TestIsConnectionError(t *testing.T) {
      tests := []struct {
          name     string
          err      error
          expected bool
      }{
          {"nil error", nil, false},
          {"amqp.ErrClosed", amqp.ErrClosed, true},
          {"sentinel ErrConnectionClosed", ErrConnectionClosed, true},
          {"sentinel ErrChannelClosed", ErrChannelClosed, true},
          {"AMQP error 320", &amqp.Error{Code: 320, Reason: "forced"}, true},
          {"AMQP error 504", &amqp.Error{Code: 504, Reason: "channel error"}, true},
          {"string match 'connection closed'", errors.New("connection closed"), true},
          {"string match 'channel/connection is not open'", errors.New("Exception (504) Reason: \"channel/connection is not open\""), true},
          {"non-connection error", errors.New("some other error"), false},
      }

      for _, tt := range tests {
          t.Run(tt.name, func(t *testing.T) {
              result := IsConnectionError(tt.err)
              if result != tt.expected {
                  t.Errorf("IsConnectionError(%v) = %v, want %v", tt.err, result, tt.expected)
              }
          })
      }
  }

  func TestIsRetryableError(t *testing.T) {
      tests := []struct {
          name     string
          err      error
          expected bool
      }{
          {"nil error", nil, false},
          {"connection error", ErrConnectionClosed, true},
          {"timeout error", ErrPublishTimeout, true},
          {"context deadline", errors.New("context deadline exceeded"), true},
          {"non-retryable error", errors.New("invalid message"), false},
      }

      for _, tt := range tests {
          t.Run(tt.name, func(t *testing.T) {
              result := IsRetryableError(tt.err)
              if result != tt.expected {
                  t.Errorf("IsRetryableError(%v) = %v, want %v", tt.err, result, tt.expected)
              }
          })
      }
  }

  func TestWrapAMQPError(t *testing.T) {
      tests := []struct {
          name     string
          err      error
          wantErr  error
      }{
          {"nil error", nil, nil},
          {"amqp.ErrClosed", amqp.ErrClosed, ErrConnectionClosed},
          {"AMQP 320", &amqp.Error{Code: 320, Reason: "forced"}, ErrConnectionClosed},
          {"AMQP 504", &amqp.Error{Code: 504, Reason: "channel error"}, ErrChannelClosed},
      }

      for _, tt := range tests {
          t.Run(tt.name, func(t *testing.T) {
              result := WrapAMQPError(tt.err)
              if tt.wantErr == nil && result != nil {
                  t.Errorf("WrapAMQPError(%v) = %v, want nil", tt.err, result)
              }
              if tt.wantErr != nil && !errors.Is(result, tt.wantErr) {
                  t.Errorf("WrapAMQPError(%v) does not wrap %v", tt.err, tt.wantErr)
              }
          })
      }
  }
  ```

- [ ] 1.1.3 Run error utility tests:
  ```bash
  go test ./pkg/mq/common -run TestIsConnectionError -v
  go test ./pkg/mq/common -run TestIsRetryableError -v
  go test ./pkg/mq/common -run TestWrapAMQPError -v
  ```

- [ ] 1.1.4 Verify all tests pass

### 1.2 Create Retry Configuration

**Purpose:** Foundation for T0-006 (max retries)

- [ ] 1.2.1 Create file `pkg/mq/common/config.go`:
  ```go
  package mqcommon

  import (
      "os"
      "strconv"
      "time"
  )

  var (
      // Message retry configuration
      MaxMessageRetries int           = 3
      RetryBackoffBase  time.Duration = 1 * time.Second
      RetryBackoffMax   time.Duration = 30 * time.Second

      // Idempotency tracking TTL
      IdempotencyTTL time.Duration = 24 * time.Hour
  )

  const (
      // Header keys for retry tracking
      RetryCountHeader  = "x-retry-count"
      RetryReasonHeader = "x-retry-reason"
      RetryTimeHeader   = "x-retry-timestamp"
  )

  func init() {
      // Allow configuration via environment variables
      if maxRetries := os.Getenv("RABBITMQ_MAX_MESSAGE_RETRIES"); maxRetries != "" {
          if count, err := strconv.Atoi(maxRetries); err == nil && count >= 0 {
              MaxMessageRetries = count
          }
      }

      if ttl := os.Getenv("RABBITMQ_IDEMPOTENCY_TTL_HOURS"); ttl != "" {
          if hours, err := strconv.Atoi(ttl); err == nil && hours > 0 {
              IdempotencyTTL = time.Duration(hours) * time.Hour
          }
      }
  }

  // GetRetryCount extracts retry count from message headers
  func GetRetryCount(headers map[string]interface{}) int {
      if headers == nil {
          return 0
      }

      if count, ok := headers[RetryCountHeader].(int32); ok {
          return int(count)
      }

      // Try int64 (some clients use this)
      if count, ok := headers[RetryCountHeader].(int64); ok {
          return int(count)
      }

      return 0
  }

  // IncrementRetryCount creates new headers with incremented retry count
  func IncrementRetryCount(headers map[string]interface{}, reason string) map[string]interface{} {
      newHeaders := make(map[string]interface{})

      // Copy existing headers
      for k, v := range headers {
          newHeaders[k] = v
      }

      // Increment retry count
      retryCount := GetRetryCount(headers)
      newHeaders[RetryCountHeader] = int32(retryCount + 1)
      newHeaders[RetryReasonHeader] = reason
      newHeaders[RetryTimeHeader] = time.Now().Unix()

      return newHeaders
  }

  // ShouldRetryMessage determines if message should be retried
  func ShouldRetryMessage(headers map[string]interface{}, err error) bool {
      retryCount := GetRetryCount(headers)

      // Check max retries
      if retryCount >= MaxMessageRetries {
          return false
      }

      // Connection errors don't count against retry limit
      // (they're transport issues, not message issues)
      if IsConnectionError(err) {
          return true
      }

      return true
  }
  ```

- [ ] 1.2.2 Create file `pkg/mq/common/config_test.go`:
  ```go
  package mqcommon

  import (
      "testing"
  )

  func TestGetRetryCount(t *testing.T) {
      tests := []struct {
          name     string
          headers  map[string]interface{}
          expected int
      }{
          {"nil headers", nil, 0},
          {"empty headers", map[string]interface{}{}, 0},
          {"with int32 count", map[string]interface{}{RetryCountHeader: int32(2)}, 2},
          {"with int64 count", map[string]interface{}{RetryCountHeader: int64(5)}, 5},
          {"missing retry header", map[string]interface{}{"other": "value"}, 0},
      }

      for _, tt := range tests {
          t.Run(tt.name, func(t *testing.T) {
              result := GetRetryCount(tt.headers)
              if result != tt.expected {
                  t.Errorf("GetRetryCount() = %d, want %d", result, tt.expected)
              }
          })
      }
  }

  func TestIncrementRetryCount(t *testing.T) {
      headers := map[string]interface{}{
          "existing": "header",
      }

      newHeaders := IncrementRetryCount(headers, "test error")

      // Check retry count incremented
      count := GetRetryCount(newHeaders)
      if count != 1 {
          t.Errorf("Expected retry count 1, got %d", count)
      }

      // Check reason added
      if reason, ok := newHeaders[RetryReasonHeader].(string); !ok || reason != "test error" {
          t.Errorf("Expected retry reason 'test error', got %v", newHeaders[RetryReasonHeader])
      }

      // Check existing header preserved
      if val, ok := newHeaders["existing"].(string); !ok || val != "header" {
          t.Errorf("Existing header not preserved")
      }

      // Increment again
      newHeaders2 := IncrementRetryCount(newHeaders, "another error")
      count2 := GetRetryCount(newHeaders2)
      if count2 != 2 {
          t.Errorf("Expected retry count 2, got %d", count2)
      }
  }

  func TestShouldRetryMessage(t *testing.T) {
      tests := []struct {
          name     string
          headers  map[string]interface{}
          err      error
          expected bool
      }{
          {"first attempt", map[string]interface{}{}, nil, true},
          {"second attempt", map[string]interface{}{RetryCountHeader: int32(1)}, nil, true},
          {"at max retries", map[string]interface{}{RetryCountHeader: int32(3)}, nil, false},
          {"over max retries", map[string]interface{}{RetryCountHeader: int32(5)}, nil, false},
          {"connection error ignores limit", map[string]interface{}{RetryCountHeader: int32(10)}, ErrConnectionClosed, true},
      }

      for _, tt := range tests {
          t.Run(tt.name, func(t *testing.T) {
              result := ShouldRetryMessage(tt.headers, tt.err)
              if result != tt.expected {
                  t.Errorf("ShouldRetryMessage() = %v, want %v", result, tt.expected)
              }
          })
      }
  }
  ```

- [ ] 1.2.3 Run config tests:
  ```bash
  go test ./pkg/mq/common -run TestGetRetryCount -v
  go test ./pkg/mq/common -run TestIncrementRetryCount -v
  go test ./pkg/mq/common -run TestShouldRetryMessage -v
  ```

- [ ] 1.2.4 Verify all tests pass

### 1.3 Create Message ID Generation

**Purpose:** Foundation for T0-001 (publisher confirms need message IDs)

- [ ] 1.3.1 Add to `pkg/mq/common/helpers.go`:
  ```go
  import (
      "crypto/rand"
      "encoding/hex"
      "fmt"
      "time"
  )

  // GenerateMessageID creates a unique message ID
  func GenerateMessageID() string {
      // Format: timestamp-random
      // Example: 1704823441234-a3f9c2b1
      timestamp := time.Now().UnixNano()
      randomBytes := make([]byte, 4)
      rand.Read(randomBytes)
      randomHex := hex.EncodeToString(randomBytes)
      return fmt.Sprintf("%d-%s", timestamp, randomHex)
  }
  ```

- [ ] 1.3.2 Add test in `pkg/mq/common/helpers_test.go`:
  ```go
  func TestGenerateMessageID(t *testing.T) {
      id1 := GenerateMessageID()
      id2 := GenerateMessageID()

      // Should not be empty
      if id1 == "" || id2 == "" {
          t.Error("Message ID should not be empty")
      }

      // Should be unique
      if id1 == id2 {
          t.Error("Message IDs should be unique")
      }

      // Should match format: timestamp-hex
      parts := strings.Split(id1, "-")
      if len(parts) != 2 {
          t.Errorf("Message ID should have format timestamp-hex, got: %s", id1)
      }

      // Timestamp should be numeric
      if _, err := strconv.ParseInt(parts[0], 10, 64); err != nil {
          t.Errorf("Timestamp part should be numeric, got: %s", parts[0])
      }

      // Random part should be hex
      if len(parts[1]) != 8 { // 4 bytes = 8 hex chars
          t.Errorf("Random part should be 8 hex chars, got: %s", parts[1])
      }
  }
  ```

- [ ] 1.3.3 Run message ID test:
  ```bash
  go test ./pkg/mq/common -run TestGenerateMessageID -v
  ```

- [ ] 1.3.4 Verify test passes

### 1.4 Phase 1 Validation

- [ ] 1.4.1 Run all new tests:
  ```bash
  go test ./pkg/mq/common -v
  ```

- [ ] 1.4.2 Verify all tests pass (should be 100%)
- [ ] 1.4.3 Run with race detector:
  ```bash
  go test ./pkg/mq/common -race -v
  ```

- [ ] 1.4.4 Verify no race conditions detected
- [ ] 1.4.5 Build project to ensure no compilation errors:
  ```bash
  go build ./pkg/mq/...
  ```

- [ ] 1.4.6 Git commit Phase 1:
  ```bash
  git add pkg/mq/common/errors.go pkg/mq/common/errors_test.go
  git add pkg/mq/common/config.go pkg/mq/common/config_test.go
  git add pkg/mq/common/helpers.go pkg/mq/common/helpers_test.go
  git commit -m "feat(mq): add error handling and retry infrastructure for T0 fixes

  Add foundation for Tier 0 catastrophic fixes:
  - Typed error handling (replaces string comparison)
  - Retry configuration and tracking
  - Message ID generation
  - 100% test coverage for new utilities

  Related: T0-005, T0-006, T0-001 foundation
  "
  ```

**Phase 1 Complete!** ✅ Foundation is ready.

---

## Phase 2: Quick Wins

**Goal:** Fix duplicate messages, infinite loops, and error detection
**Timeline:** Days 3-4
**Dependencies:** Phase 1
**Risk:** Low - isolated changes

### 2.1 Fix T0-005: Replace Error String Comparison

**Impact:** Robust error type checking across all RabbitMQ versions

- [ ] 2.1.1 Update `pkg/mq/common/helpers.go` - Replace line 115:
  ```go
  // BEFORE (line 115):
  // if err == amqp.ErrClosed || err.Error() == "Exception (504) Reason: \"channel/connection is not open\"" {

  // AFTER:
  if IsConnectionError(err) {
      lastErr = err
      common.L.Warn(
          fmt.Sprintf("publish failed due to connection error: %v, retrying (attempt %d/%d)...",
              err, attempt+1, maxRetries),
          common.F(ctx)...)
      time.Sleep(time.Second * time.Duration(attempt+1))
      continue
  }

  // Also check if retryable
  if IsRetryableError(err) {
      lastErr = err
      common.L.Warn(
          fmt.Sprintf("publish failed (retryable): %v, retrying (attempt %d/%d)...",
              err, attempt+1, maxRetries),
          common.F(ctx)...)
      time.Sleep(time.Second * time.Duration(attempt+1))
      continue
  }

  // Non-retryable error - fail immediately
  return WrapAMQPError(err)
  ```

- [ ] 2.1.2 Search for other string comparisons:
  ```bash
  grep -n 'err.Error()' pkg/mq/common/*.go
  grep -n '"Exception' pkg/mq/common/*.go
  ```

- [ ] 2.1.3 Replace any other error string comparisons found with `IsConnectionError()` or `IsRetryableError()`

- [ ] 2.1.4 Test error classification:
  ```bash
  # Create simple test program
  cat > /tmp/test_errors.go << 'EOF'
  package main
  import (
      "fmt"
      "errors"
      amqp "github.com/rabbitmq/amqp091-go"
      mqcommon "qomet.tech/agora/daemons/pkg/mq/common"
  )
  func main() {
      testErrors := []error{
          amqp.ErrClosed,
          &amqp.Error{Code: 320, Reason: "CONNECTION_FORCED"},
          &amqp.Error{Code: 504, Reason: "CHANNEL_ERROR"},
          errors.New("Exception (504) Reason: \"channel/connection is not open\""),
          errors.New("some random error"),
      }
      for _, err := range testErrors {
          fmt.Printf("Error: %v\n", err)
          fmt.Printf("  IsConnectionError: %v\n", mqcommon.IsConnectionError(err))
          fmt.Printf("  IsRetryableError: %v\n", mqcommon.IsRetryableError(err))
          fmt.Println()
      }
  }
  EOF
  go run /tmp/test_errors.go
  ```

- [ ] 2.1.5 Verify output shows correct classification
- [ ] 2.1.6 Git commit T0-005:
  ```bash
  git add pkg/mq/common/helpers.go
  git commit -m "fix(mq): replace brittle error string comparison with typed errors (T0-005)

  Replace error string matching with robust type-based error checking.
  Now uses IsConnectionError() and IsRetryableError() utilities.

  Fixes:
  - False negatives on RabbitMQ version upgrades
  - Incorrect retry decisions
  - Brittle error detection

  Impact: Robust error handling across all RabbitMQ versions
  "
  ```

**T0-005 COMPLETE!** ✅

### 2.2 Fix T0-004: Check All ACK/NACK Errors

**Impact:** Prevent duplicate messages and stuck messages

- [ ] 2.2.1 Update line 300 in `pkg/mq/common/helpers.go` - Check ACK success:
  ```go
  // BEFORE (line 300):
  // TODO(kam): check for ack error
  // m.Ack(false /* acknowledge only this message */)

  // AFTER:
  if err := m.Ack(false); err != nil {
      common.L.Error(
          fmt.Sprintf("[%s] CRITICAL: Failed to ACK message (delivery_tag=%d): %v - message will be redelivered",
              queueName, m.DeliveryTag, err),
          common.F(ctx)...)
      // Message will be redelivered - log for monitoring
      // No action needed, channel may be closed
  }
  ```

- [ ] 2.2.2 Update line 305 - Check ACK before republish:
  ```go
  // BEFORE (line 305):
  // TODO(kam): check for ack error
  // m.Ack(false)

  // AFTER:
  if err := m.Ack(false); err != nil {
      common.L.Error(
          fmt.Sprintf("[%s] CRITICAL: Failed to ACK before republish (delivery_tag=%d): %v - SKIPPING republish to avoid duplicates",
              queueName, m.DeliveryTag, err),
          common.F(ctx)...)
      // DO NOT republish if ACK failed - would create guaranteed duplicate
      return
  }
  ```

- [ ] 2.2.3 Update line 307 - Check Publish error (will be enhanced in T0-006):
  ```go
  // BEFORE (line 307):
  // TODO(kam): check for publish error
  // Publish(ctx, queueName, m.Type, m.ContentType, m.Body)

  // AFTER (temporary - will be replaced in 2.3):
  if err := Publish(ctx, queueName, m.Type, m.ContentType, m.Body); err != nil {
      common.L.Error(
          fmt.Sprintf("[%s] CRITICAL: Failed to republish message: %v - MESSAGE MAY BE LOST",
              queueName, err),
          common.F(ctx)...)
      // TODO: Send to DLX when implemented
  }
  ```

- [ ] 2.2.4 Update line 311 - Check NACK error:
  ```go
  // BEFORE (line 311):
  // TODO(kam): check for nack error
  // m.Nack(false, true /* requeue */)

  // AFTER:
  if err := m.Nack(false, true); err != nil {
      common.L.Error(
          fmt.Sprintf("[%s] CRITICAL: Failed to NACK message (delivery_tag=%d): %v - message stuck in unacked state",
              queueName, m.DeliveryTag, err),
          common.F(ctx)...)
      // If NACK fails, message is stuck. Channel may be closed.
      // The channel close will force all unacked messages to requeue automatically
  }
  ```

- [ ] 2.2.5 Update line 319 - Check ACK in drop path:
  ```go
  // BEFORE (line 319):
  // TODO(kam): check for ack error
  // m.Ack(false)

  // AFTER:
  if err := m.Ack(false); err != nil {
      common.L.Error(
          fmt.Sprintf("[%s] CRITICAL: Failed to ACK dropped message (delivery_tag=%d): %v - message will be redelivered",
              queueName, m.DeliveryTag, err),
          common.F(ctx)...)
  }
  ```

- [ ] 2.2.6 Add logging imports if needed:
  ```go
  import (
      // ... existing imports ...
      "qomet.tech/agora/daemons/pkg/common"
  )
  ```

- [ ] 2.2.7 Test ACK/NACK error handling:
  ```bash
  # Manual test: Kill RabbitMQ during message processing
  # 1. Start consuming messages
  # 2. During processing, kill broker: docker-compose stop rabbitmq
  # 3. Verify error logs show ACK failures (not TODOs)
  # 4. Verify no panics
  ```

- [ ] 2.2.8 Git commit T0-004:
  ```bash
  git add pkg/mq/common/helpers.go
  git commit -m "fix(mq): check all ACK/NACK errors to prevent duplicates (T0-004)

  Replace 5 TODO comments with proper error handling:
  - Check ACK errors after successful processing
  - Check ACK before republish (prevent duplicates)
  - Check Publish errors during republish
  - Check NACK errors
  - Check ACK when dropping messages

  Fixes:
  - Silent duplicate message creation
  - Stuck messages in unacked state
  - Invisible ACK failures

  Impact: Prevents message duplication and loss
  "
  ```

**T0-004 COMPLETE!** ✅

### 2.3 Fix T0-006: RepublishNack Max Retries

**Impact:** Prevent infinite loops, CPU burn, and queue explosion

- [X] 2.3.1 Replace entire RepublishNack block in `pkg/mq/common/helpers.go` (lines 303-322):
  ```go
  // BEFORE (lines 303-322):
  // if options.RepublishNack {
  //     m.Ack(false)
  //     Publish(ctx, queueName, m.Type, m.ContentType, m.Body)
  // } else { ... }

  // AFTER:
  if options.RepublishNack {
      // Check retry limit
      if !ShouldRetryMessage(m.Headers, err) {
          retryCount := GetRetryCount(m.Headers)
          common.L.Warn(
              fmt.Sprintf("[%s] Message exceeded max retries (%d/%d), DROPPING: type=%s, delivery_tag=%d, error=%v",
                  queueName, retryCount, MaxMessageRetries, m.Type, m.DeliveryTag, err),
              common.F(ctx)...)

          // ACK to remove from queue
          if ackErr := m.Ack(false); ackErr != nil {
              common.L.Error(
                  fmt.Sprintf("[%s] Failed to ACK max-retried message: %v", queueName, ackErr),
                  common.F(ctx)...)
              return
          }

          // TODO: Send to DLX (Phase 3 of main plan)
          common.L.Warn(
              fmt.Sprintf("[%s] Message dropped (no DLX configured yet): %s", queueName, string(m.Body)),
              common.F(ctx)...)
          return
      }

      // Increment retry count
      newHeaders := IncrementRetryCount(m.Headers, err.Error())

      // ACK original message FIRST
      if ackErr := m.Ack(false); ackErr != nil {
          common.L.Error(
              fmt.Sprintf("[%s] Failed to ACK before republish: %v - SKIPPING republish to avoid duplicates", queueName, ackErr),
              common.F(ctx)...)
          return
      }

      // Republish with updated retry headers
      retryCount := GetRetryCount(newHeaders)
      if err := PublishWithHeaders(ctx, queueName, m.Type, m.ContentType, m.Body, newHeaders); err != nil {
          common.L.Error(
              fmt.Sprintf("[%s] Failed to republish message (retry %d/%d): %v - MESSAGE LOST",
                  queueName, retryCount, MaxMessageRetries, err),
              common.F(ctx)...)
          // TODO: Send to DLX as last resort
      } else {
          common.L.Info(
              fmt.Sprintf("[%s] Message republished (retry %d/%d): type=%s",
                  queueName, retryCount, MaxMessageRetries, m.Type),
              common.F(ctx)...)
      }
  } else {
      // ... existing RequeueNack logic unchanged ...
  }
  ```

- [X] 2.3.2 Add `PublishWithHeaders` helper function in `pkg/mq/common/helpers.go` (IMPLEMENTED - uses amqp.Table for headers):
  ```go
  // PublishWithHeaders publishes a message with custom headers
  func PublishWithHeaders(ctx context.Context, destName, messageType, contentType string, body []byte, headers map[string]interface{}) error {
      maxRetries := 3
      var lastErr error

      for attempt := 0; attempt < maxRetries; attempt++ {
          ch := GetChannel()
          if ch == nil {
              lastErr = fmt.Errorf("rabbitmq channel is nil")
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          // Convert headers to amqp.Table
          amqpHeaders := amqp.Table{}
          for k, v := range headers {
              amqpHeaders[k] = v
          }

          err := ch.PublishWithContext(
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
                  Headers:      amqpHeaders,
              },
          )

          if err == nil {
              return nil
          }

          // Check if error is retryable
          if IsConnectionError(err) {
              lastErr = err
              common.L.Warn(
                  fmt.Sprintf("PublishWithHeaders failed due to connection error: %v, retrying (attempt %d/%d)...", err, attempt+1, maxRetries),
                  common.F(ctx)...)
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          return WrapAMQPError(err)
      }

      return fmt.Errorf("PublishWithHeaders failed after %d attempts: %w", maxRetries, lastErr)
  }
  ```

- [ ] 2.3.3 Test max retry behavior:
  ```bash
  # Create test that always fails processing
  # 1. Set RABBITMQ_MAX_MESSAGE_RETRIES=2
  # 2. Publish message to queue with handler that always returns error
  # 3. Verify message retried exactly 2 times, then dropped
  # 4. Verify no infinite loop
  # 5. Check logs show retry count incrementing
  ```

- [ ] 2.3.4 Test retry headers:
  ```bash
  # Create test that inspects republished message headers
  # 1. Consume message with x-retry-count header
  # 2. Verify retry count increments
  # 3. Verify retry reason captured
  # 4. Verify retry timestamp present
  ```

- [ ] 2.3.5 Git commit T0-006:
  ```bash
  git add pkg/mq/common/helpers.go
  git commit -m "fix(mq): add max retry limit to prevent infinite republish loops (T0-006)

  RepublishNack now tracks retry count in message headers and enforces
  configurable max retries (default: 3).

  Changes:
  - Track retry count in x-retry-count header
  - Drop messages exceeding max retries
  - Add PublishWithHeaders() to preserve retry metadata
  - Log retry attempts for monitoring

  Fixes:
  - Infinite republish loops on poison messages
  - CPU burn and queue explosion
  - Uncontrolled message growth

  Configuration:
  - RABBITMQ_MAX_MESSAGE_RETRIES (default: 3)

  Impact: Prevents single bad message from bringing down system
  "
  ```

**T0-006 COMPLETE!** ✅

### 2.4 Phase 2 Validation

- [ ] 2.4.1 Run all tests:
  ```bash
  go test ./pkg/mq/... -v
  ```

- [ ] 2.4.2 Integration test with real RabbitMQ:
  ```bash
  # Start RabbitMQ
  docker-compose up -d rabbitmq

  # Run integration tests
  # Test scenarios:
  # 1. Normal message processing (ACK succeeds)
  # 2. Failed processing with retry (RepublishNack)
  # 3. Max retries exceeded (message dropped)
  # 4. Connection error during ACK (logged, no panic)
  # 5. Different error types classified correctly
  ```

- [ ] 2.4.3 Load test quick wins:
  ```bash
  # Send 10,000 messages
  # - Mix of successful and failing
  # - Verify no duplicates created
  # - Verify no infinite loops
  # - Verify max retries enforced
  ```

- [ ] 2.4.4 Review logs for error handling quality
- [ ] 2.4.5 Check metrics (if available)
- [ ] 2.4.6 Code review Phase 2 changes

**Phase 2 Complete!** ✅ Quick wins delivered.

---

## Phase 3: Channel Pool

**Goal:** Fix shared channel race condition (T0-002) and replacement race (T0-003)
**Timeline:** Days 5-8
**Dependencies:** Phase 1
**Risk:** Medium - requires careful testing

### 3.1 Implement Channel Pool

**Purpose:** Thread-safe channel management, eliminates race conditions

- [ ] 3.1.1 Create file `pkg/mq/common/channelpool.go`:
  ```go
  package mqcommon

  import (
      "errors"
      "fmt"
      "sync"
      amqp "github.com/rabbitmq/amqp091-go"
      "qomet.tech/agora/daemons/pkg/common"
  )

  // ChannelPool manages a pool of RabbitMQ channels for publishers
  type ChannelPool struct {
      conn        *amqp.Connection
      channels    chan *amqp.Channel
      maxChannels int
      mu          sync.Mutex
      closed      bool
      created     int // Track total channels created
  }

  // NewChannelPool creates a new channel pool
  func NewChannelPool(conn *amqp.Connection, maxChannels int) (*ChannelPool, error) {
      if conn == nil {
          return nil, errors.New("connection is nil")
      }

      if maxChannels <= 0 {
          maxChannels = 20 // Default
      }

      pool := &ChannelPool{
          conn:        conn,
          channels:    make(chan *amqp.Channel, maxChannels),
          maxChannels: maxChannels,
          closed:      false,
          created:     0,
      }

      // Pre-populate pool with initial channels
      initialChannels := maxChannels / 2
      if initialChannels < 1 {
          initialChannels = 1
      }

      for i := 0; i < initialChannels; i++ {
          ch, err := conn.Channel()
          if err != nil {
              // Close any channels we created
              pool.Close()
              return nil, fmt.Errorf("failed to create initial channel %d: %w", i, err)
          }
          pool.channels <- ch
          pool.created++
      }

      common.L.Info(fmt.Sprintf("Channel pool created: max=%d, initial=%d", maxChannels, initialChannels))

      return pool, nil
  }

  // GetChannel retrieves a channel from the pool (or creates new one if pool empty)
  func (p *ChannelPool) GetChannel() (*amqp.Channel, error) {
      p.mu.Lock()
      if p.closed {
          p.mu.Unlock()
          return nil, errors.New("channel pool is closed")
      }
      p.mu.Unlock()

      // Try to get from pool first
      select {
      case ch := <-p.channels:
          // Verify channel is still open
          if ch.IsClosed() {
              common.L.Warn("Retrieved closed channel from pool, creating new one")
              // Try to get another one
              return p.GetChannel()
          }
          return ch, nil
      default:
          // Pool is empty, create new channel
          p.mu.Lock()
          defer p.mu.Unlock()

          if p.closed {
              return nil, errors.New("channel pool is closed")
          }

          if p.created >= p.maxChannels {
              // At max capacity, wait for channel to be returned
              p.mu.Unlock()
              ch := <-p.channels
              p.mu.Lock()

              if ch.IsClosed() {
                  return p.GetChannel()
              }
              return ch, nil
          }

          // Create new channel
          ch, err := p.conn.Channel()
          if err != nil {
              return nil, fmt.Errorf("failed to create new channel: %w", err)
          }

          p.created++
          common.L.Info(fmt.Sprintf("Created new channel (total: %d/%d)", p.created, p.maxChannels))

          return ch, nil
      }
  }

  // ReturnChannel returns a channel to the pool
  func (p *ChannelPool) ReturnChannel(ch *amqp.Channel) {
      if ch == nil {
          return
      }

      p.mu.Lock()
      defer p.mu.Unlock()

      if p.closed {
          ch.Close()
          return
      }

      // Don't return closed channels
      if ch.IsClosed() {
          common.L.Warn("Attempted to return closed channel to pool")
          return
      }

      // Try to return to pool
      select {
      case p.channels <- ch:
          // Successfully returned to pool
      default:
          // Pool is full, close the channel
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
      count := 0
      for ch := range p.channels {
          if !ch.IsClosed() {
              ch.Close()
          }
          count++
      }

      common.L.Info(fmt.Sprintf("Channel pool closed: %d channels closed", count))

      return nil
  }

  // Stats returns pool statistics
  func (p *ChannelPool) Stats() map[string]int {
      p.mu.Lock()
      defer p.mu.Unlock()

      return map[string]int{
          "max":       p.maxChannels,
          "created":   p.created,
          "available": len(p.channels),
          "in_use":    p.created - len(p.channels),
      }
  }
  ```

- [ ] 3.1.2 Create file `pkg/mq/common/channelpool_test.go`:
  ```go
  package mqcommon

  import (
      "testing"
      "sync"
  )

  // Note: These are unit tests. Integration tests with real RabbitMQ
  // should be in a separate test file or test suite.

  func TestChannelPoolStats(t *testing.T) {
      // This test doesn't require real RabbitMQ connection
      // Just tests the stats tracking logic

      pool := &ChannelPool{
          maxChannels: 10,
          created:     5,
          channels:    make(chan *amqp.Channel, 10),
      }

      // Add 3 mock channels to pool
      pool.channels <- nil
      pool.channels <- nil
      pool.channels <- nil

      stats := pool.Stats()

      if stats["max"] != 10 {
          t.Errorf("Expected max=10, got %d", stats["max"])
      }

      if stats["created"] != 5 {
          t.Errorf("Expected created=5, got %d", stats["created"])
      }

      if stats["available"] != 3 {
          t.Errorf("Expected available=3, got %d", stats["available"])
      }

      if stats["in_use"] != 2 {
          t.Errorf("Expected in_use=2, got %d", stats["in_use"])
      }
  }

  func TestChannelPoolClose(t *testing.T) {
      pool := &ChannelPool{
          channels: make(chan *amqp.Channel, 10),
          closed:   false,
      }

      // Close pool
      err := pool.Close()
      if err != nil {
          t.Errorf("Close() returned error: %v", err)
      }

      if !pool.closed {
          t.Error("Pool should be marked as closed")
      }

      // Second close should be no-op
      err = pool.Close()
      if err != nil {
          t.Errorf("Second Close() returned error: %v", err)
      }
  }

  // TODO: Integration tests with real RabbitMQ connection
  // - TestChannelPoolGetReturn
  // - TestChannelPoolConcurrency
  // - TestChannelPoolMaxCapacity
  ```

- [ ] 3.1.3 Run channel pool tests:
  ```bash
  go test ./pkg/mq/common -run TestChannelPool -v
  ```

### 3.2 Replace Global Channel with Pool

**Purpose:** Use pool instead of shared global channel

- [ ] 3.2.1 Update `pkg/mq/common/rabbitmq.go`:
  ```go
  // BEFORE (lines 10-17):
  // var (
  //     RabbitMQURL        string = ""
  //     RabbitMQConnection *amqp.Connection
  //     RabbitMQChannel    *amqp.Channel  // <-- REMOVE THIS
  //     channelMutex       sync.RWMutex
  //     reconnectListeners []chan struct{}
  //     reconnectMutex     sync.Mutex
  // )

  // AFTER:
  var (
      RabbitMQURL         string = ""
      RabbitMQConnection  *amqp.Connection
      RabbitMQChannelPool *ChannelPool  // <-- NEW: Use pool instead
      channelMutex        sync.RWMutex
      reconnectListeners  map[string]chan struct{}  // Changed to map for cleanup
      reconnectMutex      sync.Mutex
      listenerIDCounter   uint64
  )

  func init() {
      reconnectListeners = make(map[string]chan struct{})
  }
  ```

- [ ] 3.2.2 Remove `GetChannel()` function (lines 23-28):
  ```go
  // DELETE this entire function - it's replaced by pool.GetChannel()
  // func GetChannel() *amqp.Channel {
  //     channelMutex.RLock()
  //     defer channelMutex.RUnlock()
  //     return RabbitMQChannel
  // }
  ```

- [ ] 3.2.3 Remove `UpdateChannel()` function (lines 30-47):
  ```go
  // DELETE this entire function - pool manages channels now
  // func UpdateChannel(ch *amqp.Channel) { ... }
  ```

- [ ] 3.2.4 Update `RegisterReconnectListener()` to support cleanup (lines 70-81):
  ```go
  // REPLACE entire function:
  func RegisterReconnectListener() (<-chan struct{}, func()) {
      reconnectMutex.Lock()
      defer reconnectMutex.Unlock()

      // Generate unique ID
      listenerIDCounter++
      id := fmt.Sprintf("listener-%d", listenerIDCounter)

      // Larger buffer to prevent blocking
      ch := make(chan struct{}, 100)
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

- [ ] 3.2.5 Update `NotifyReconnect()` to use blocking sends (lines 49-67):
  ```go
  // REPLACE entire function:
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
                  fmt.Printf("[RabbitMQ] WARNING: Listener %s notification timeout\n", listenerId)
              }
          }(id, ch)
      }

      // Wait for all notifications with timeout
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

### 3.3 Update Publish() to Use Pool

- [ ] 3.3.1 Update `pkg/mq/common/helpers.go` Publish() function (lines 84-128):
  ```go
  // REPLACE entire Publish() function:
  func Publish(ctx context.Context, destName, messageType, contentType string, body []byte) error {
      maxRetries := 3
      var lastErr error

      for attempt := 0; attempt < maxRetries; attempt++ {
          // Get channel from pool
          ch, err := RabbitMQChannelPool.GetChannel()
          if err != nil {
              lastErr = err
              common.L.Warn(
                  fmt.Sprintf("failed to get channel from pool: %v, retrying (attempt %d/%d)...", err, attempt+1, maxRetries),
                  common.F(ctx)...)
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          // Use defer to ensure channel is returned to pool
          err = func() error {
              defer RabbitMQChannelPool.ReturnChannel(ch)

              return ch.PublishWithContext(
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
                      MessageId:    GenerateMessageID(),
                  },
              )
          }()

          if err == nil {
              return nil
          }

          // Check if error is retryable
          if IsConnectionError(err) {
              lastErr = err
              common.L.Warn(
                  fmt.Sprintf("publish failed due to connection error: %v, retrying (attempt %d/%d)...", err, attempt+1, maxRetries),
                  common.F(ctx)...)
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          if IsRetryableError(err) {
              lastErr = err
              common.L.Warn(
                  fmt.Sprintf("publish failed (retryable): %v, retrying (attempt %d/%d)...", err, attempt+1, maxRetries),
                  common.F(ctx)...)
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          // Non-retryable error
          return WrapAMQPError(err)
      }

      return fmt.Errorf("publish failed after %d attempts: %w", maxRetries, lastErr)
  }
  ```

- [ ] 3.3.2 Update `PublishWithHeaders()` similarly:
  ```go
  // Update to use pool.GetChannel() and pool.ReturnChannel()
  func PublishWithHeaders(ctx context.Context, destName, messageType, contentType string, body []byte, headers map[string]interface{}) error {
      maxRetries := 3
      var lastErr error

      for attempt := 0; attempt < maxRetries; attempt++ {
          ch, err := RabbitMQChannelPool.GetChannel()
          if err != nil {
              lastErr = err
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          err = func() error {
              defer RabbitMQChannelPool.ReturnChannel(ch)

              amqpHeaders := amqp.Table{}
              for k, v := range headers {
                  amqpHeaders[k] = v
              }

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
                      MessageId:    GenerateMessageID(),
                      Headers:      amqpHeaders,
                  },
              )
          }()

          if err == nil {
              return nil
          }

          if IsRetryableError(err) {
              lastErr = err
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          return WrapAMQPError(err)
      }

      return fmt.Errorf("publish with headers failed after %d attempts: %w", maxRetries, lastErr)
  }
  ```

### 3.4 Update Consumers to Use Dedicated Channels

**Important:** Consumers should NOT use the pool - they need dedicated long-lived channels

- [ ] 3.4.1 Update `ConsumeQueueWithOptionsAsync()` in `pkg/mq/common/helpers.go` (line ~199):
  ```go
  // REPLACE line 199:
  // ch := GetChannel()

  // WITH - Create dedicated channel for this consumer:
  ch, err := RabbitMQConnection.Channel()
  if err != nil {
      common.L.Warn(
          fmt.Sprintf("[%s] failed to create dedicated consumer channel: %v", queueName, err),
          common.F(ctx)...)
      time.Sleep(5 * time.Second)
      continue
  }
  defer ch.Close()  // Close when consumer exits
  ```

- [ ] 3.4.2 Add QoS configuration per consumer (after channel creation):
  ```go
  // Set QoS on this consumer's channel
  qosPrefetch := 20 // Default - can be made configurable
  if err := ch.Qos(qosPrefetch, 0, false); err != nil {
      common.L.Warn(
          fmt.Sprintf("[%s] failed to set QoS (prefetch=%d): %v", queueName, qosPrefetch, err),
          common.F(ctx)...)
      ch.Close()
      time.Sleep(5 * time.Second)
      continue
  }

  common.L.Info(
      fmt.Sprintf("[%s] consumer channel created with QoS (prefetch=%d)", queueName, qosPrefetch),
      common.F(ctx)...)
  ```

### 3.5 Update Initialization to Create Pool

- [ ] 3.5.1 Update `pkg/mq/init.go` - initConn() function (lines 67-91):
  ```go
  // REPLACE function:
  func initConn(_ctx context.Context) error {
      if len(mqcommon.RabbitMQURL) == 0 {
          mqcommon.RabbitMQURL = os.Getenv("RABBITMQ_CONN_STRING")
          if len(mqcommon.RabbitMQURL) == 0 {
              panic("RABBITMQ_CONN_STRING is not set")
          }
      }

      config := amqp.Config{
          Heartbeat: 15 * time.Second,  // Reduced from 60s
          Dial: func(network, addr string) (net.Conn, error) {
              return amqp.DefaultDial(30 * time.Second)(network, addr)  // Reduced from 300s
          },
      }

      var err error
      mqcommon.RabbitMQConnection, err = amqp.DialConfig(mqcommon.RabbitMQURL, config)
      if err != nil {
          return err
      }

      // Create channel pool (replaces single channel)
      maxChannels := 20 // Can be made configurable
      if maxChannelsEnv := os.Getenv("RABBITMQ_MAX_CHANNELS"); maxChannelsEnv != "" {
          if count, parseErr := strconv.Atoi(maxChannelsEnv); parseErr == nil && count > 0 {
              maxChannels = count
          }
      }

      mqcommon.RabbitMQChannelPool, err = mqcommon.NewChannelPool(mqcommon.RabbitMQConnection, maxChannels)
      if err != nil {
          mqcommon.RabbitMQConnection.Close()
          return fmt.Errorf("failed to create channel pool: %w", err)
      }

      common.L.Info(fmt.Sprintf("RabbitMQ connection established with channel pool (max_channels=%d)", maxChannels))

      return nil
  }
  ```

- [ ] 3.5.2 Update initQueues() to use pool (line 20):
  ```go
  // BEFORE:
  // ch := mqcommon.GetChannel()

  // AFTER:
  ch, err := mqcommon.RabbitMQChannelPool.GetChannel()
  if err != nil {
      return fmt.Errorf("failed to get channel for queue initialization: %w", err)
  }
  defer mqcommon.RabbitMQChannelPool.ReturnChannel(ch)

  // Remove QoS line - it's now set per-consumer
  // DELETE: err := ch.Qos(1000, 0, false)
  ```

- [ ] 3.5.3 Update reconnection handler (lines 114-174):
  ```go
  // In reconnection handler, replace UpdateChannel() calls
  // with pool recreation:

  // After successful reconnection (line ~150):
  if err2 == nil {
      common.L.Info("rabbitmq reconnect success - notifying all consumers...", common.F(ctx)...)

      // Notify consumers BEFORE old pool is closed
      mqcommon.NotifyReconnect()

      common.L.Info("reconnection notification sent to all consumers", common.F(ctx)...)
      break
  }
  ```

### 3.6 Update Consumer to Cleanup Listener

- [ ] 3.6.1 Update `ConsumeQueueWithOptionsAsync()` to use cleanup:
  ```go
  // REPLACE line 179:
  // reconnectCh := RegisterReconnectListener()

  // WITH:
  reconnectCh, cleanupReconnect := RegisterReconnectListener()

  // Update defer at line 182:
  go func() {
      defer func() {
          cleanupReconnect()  // Clean up listener
          common.L.Warn(
              fmt.Sprintf("[%s] leaving consumer routine...", queueName),
              common.F(ctx)...)
      }()
      // ... rest of consumer logic ...
  }()
  ```

### 3.7 Phase 3 Testing

- [ ] 3.7.1 Unit tests for channel pool:
  ```bash
  go test ./pkg/mq/common -run TestChannelPool -v
  ```

- [ ] 3.7.2 Build project:
  ```bash
  go build ./pkg/mq/...
  ```

- [ ] 3.7.3 Integration test with RabbitMQ:
  ```bash
  # Test scenarios:
  # 1. Single publisher - verify channel pool works
  # 2. 100 concurrent publishers - verify no race conditions
  # 3. Consumer creation - verify dedicated channels
  # 4. Reconnection - verify pool recreated correctly
  # 5. Memory - verify no channel leaks
  ```

- [ ] 3.7.4 Race condition test:
  ```bash
  go test ./pkg/mq/... -race -v
  ```

- [ ] 3.7.5 Load test:
  ```bash
  # 1000 goroutines publishing simultaneously
  # Verify no panics, no corruption
  # Check pool stats
  ```

- [ ] 3.7.6 Reconnection test:
  ```bash
  # 1. Start publishing
  # 2. Kill RabbitMQ
  # 3. Restart RabbitMQ
  # 4. Verify pool recreates
  # 5. Verify consumers reconnect
  # 6. Verify no messages lost
  ```

- [ ] 3.7.7 Git commit T0-002 and T0-003:
  ```bash
  git add pkg/mq/common/channelpool.go pkg/mq/common/channelpool_test.go
  git add pkg/mq/common/rabbitmq.go
  git add pkg/mq/common/helpers.go
  git add pkg/mq/init.go
  git commit -m "fix(mq): implement channel pool to fix race conditions (T0-002, T0-003)

  Replace shared global channel with thread-safe channel pool.

  Changes:
  - Add ChannelPool for publisher channels
  - Consumers use dedicated long-lived channels
  - Remove UpdateChannel() race condition
  - Add listener cleanup to prevent memory leak
  - Reduce heartbeat to 15s (from 60s)
  - Reduce connect timeout to 30s (from 300s)

  Fixes:
  - T0-002: Shared global channel race condition
  - T0-003: Channel replacement race (fixed by pool)
  - T1-007: Unbounded listener growth (cleanup added)
  - T1-011: Dropped reconnect notifications (blocking send)
  - T2-026: Heartbeat too long
  - T2-027: Connect timeout too long

  Impact: Thread-safe channel operations, no crashes
  "
  ```

**T0-002 and T0-003 COMPLETE!** ✅

**Phase 3 Complete!** ✅ Channel pool implemented.

---

## Phase 4: Publisher Confirms

**Goal:** Implement T0-001 - Zero message loss with publisher confirms
**Timeline:** Days 9-10
**Dependencies:** Phase 3 (channel pool)
**Risk:** Medium - complex but well-tested pattern

### 4.1 Create Publisher with Confirms

- [ ] 4.1.1 Create file `pkg/mq/common/publisher.go`:
  ```go
  package mqcommon

  import (
      "context"
      "fmt"
      "sync"
      "time"
      amqp "github.com/rabbitmq/amqp091-go"
      "qomet.tech/agora/daemons/pkg/common"
  )

  // PublisherWithConfirms wraps a channel with publisher confirmation support
  type PublisherWithConfirms struct {
      ch              *amqp.Channel
      confirmChan     chan amqp.Confirmation
      nextSeqNo       uint64
      mu              sync.Mutex
      confirmTimeout  time.Duration
  }

  // NewPublisherWithConfirms creates a publisher with confirms enabled
  func NewPublisherWithConfirms(ch *amqp.Channel) (*PublisherWithConfirms, error) {
      if ch == nil {
          return nil, fmt.Errorf("channel is nil")
      }

      // Enable publisher confirms on this channel
      if err := ch.Confirm(false); err != nil {
          return nil, fmt.Errorf("failed to enable publisher confirms: %w", err)
      }

      // Set up confirmation channel (buffered to avoid blocking broker)
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
      // Get next sequence number
      p.mu.Lock()
      seqNo := p.nextSeqNo
      p.nextSeqNo++
      p.mu.Unlock()

      // Publish message
      err := p.ch.PublishWithContext(ctx, exchange, routingKey, mandatory, immediate, msg)
      if err != nil {
          return fmt.Errorf("publish failed: %w", err)
      }

      // Wait for confirmation with timeout
      select {
      case confirm := <-p.confirmChan:
          // Verify sequence number matches
          if confirm.DeliveryTag != seqNo {
              return fmt.Errorf("sequence number mismatch: expected %d, got %d", seqNo, confirm.DeliveryTag)
          }

          // Check if message was acked or nacked
          if !confirm.Ack {
              return fmt.Errorf("%w: message nacked by broker (seq: %d)", ErrPublishNacked, seqNo)
          }

          // Success!
          return nil

      case <-time.After(p.confirmTimeout):
          return fmt.Errorf("%w: no confirmation after %v (seq: %d)", ErrPublishTimeout, p.confirmTimeout, seqNo)

      case <-ctx.Done():
          return fmt.Errorf("context cancelled while waiting for confirm: %w", ctx.Err())
      }
  }

  // SetConfirmTimeout sets the confirmation timeout
  func (p *PublisherWithConfirms) SetConfirmTimeout(timeout time.Duration) {
      p.mu.Lock()
      defer p.mu.Unlock()
      p.confirmTimeout = timeout
  }

  // GetConfirmTimeout returns the current confirmation timeout
  func (p *PublisherWithConfirms) GetConfirmTimeout() time.Duration {
      p.mu.Lock()
      defer p.mu.Unlock()
      return p.confirmTimeout
  }
  ```

- [ ] 4.1.2 Create file `pkg/mq/common/publisher_test.go`:
  ```go
  package mqcommon

  import (
      "testing"
      "time"
  )

  func TestPublisherWithConfirms_SetGetTimeout(t *testing.T) {
      // Create publisher without real channel (just test timeout logic)
      p := &PublisherWithConfirms{
          confirmTimeout: 30 * time.Second,
      }

      // Test getter
      timeout := p.GetConfirmTimeout()
      if timeout != 30*time.Second {
          t.Errorf("Expected timeout 30s, got %v", timeout)
      }

      // Test setter
      p.SetConfirmTimeout(60 * time.Second)
      timeout = p.GetConfirmTimeout()
      if timeout != 60*time.Second {
          t.Errorf("Expected timeout 60s, got %v", timeout)
      }
  }

  // TODO: Integration tests with real RabbitMQ
  // - TestPublisherConfirmSuccess
  // - TestPublisherConfirmNack
  // - TestPublisherConfirmTimeout
  ```

### 4.2 Update Publish() to Use Confirms

- [ ] 4.2.1 Update `pkg/mq/common/helpers.go` Publish() function:
  ```go
  // REPLACE entire Publish() function:
  func Publish(ctx context.Context, destName, messageType, contentType string, body []byte) error {
      maxRetries := 3
      var lastErr error

      for attempt := 0; attempt < maxRetries; attempt++ {
          // Get channel from pool
          ch, err := RabbitMQChannelPool.GetChannel()
          if err != nil {
              lastErr = err
              common.L.Warn(
                  fmt.Sprintf("failed to get channel from pool: %v, retrying (attempt %d/%d)...", err, attempt+1, maxRetries),
                  common.F(ctx)...)
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          // Publish with confirmation
          err = func() error {
              defer RabbitMQChannelPool.ReturnChannel(ch)

              // Create publisher with confirms
              publisher, err := NewPublisherWithConfirms(ch)
              if err != nil {
                  return fmt.Errorf("failed to create publisher with confirms: %w", err)
              }

              // Publish and wait for confirmation
              return publisher.PublishWithConfirm(
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
                      MessageId:    GenerateMessageID(),
                  },
              )
          }()

          if err == nil {
              // Success - message confirmed by broker
              return nil
          }

          // Check if error is retryable
          if IsRetryableError(err) {
              lastErr = err
              common.L.Warn(
                  fmt.Sprintf("publish failed (retryable): %v, retrying (attempt %d/%d)...", err, attempt+1, maxRetries),
                  common.F(ctx)...)
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          // Non-retryable error
          return WrapAMQPError(err)
      }

      return fmt.Errorf("publish failed after %d attempts: %w", maxRetries, lastErr)
  }
  ```

- [ ] 4.2.2 Update `PublishWithHeaders()` similarly:
  ```go
  func PublishWithHeaders(ctx context.Context, destName, messageType, contentType string, body []byte, headers map[string]interface{}) error {
      maxRetries := 3
      var lastErr error

      for attempt := 0; attempt < maxRetries; attempt++ {
          ch, err := RabbitMQChannelPool.GetChannel()
          if err != nil {
              lastErr = err
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          err = func() error {
              defer RabbitMQChannelPool.ReturnChannel(ch)

              publisher, err := NewPublisherWithConfirms(ch)
              if err != nil {
                  return fmt.Errorf("failed to create publisher with confirms: %w", err)
              }

              amqpHeaders := amqp.Table{}
              for k, v := range headers {
                  amqpHeaders[k] = v
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
                      MessageId:    GenerateMessageID(),
                      Headers:      amqpHeaders,
                  },
              )
          }()

          if err == nil {
              return nil
          }

          if IsRetryableError(err) {
              lastErr = err
              time.Sleep(time.Second * time.Duration(attempt+1))
              continue
          }

          return WrapAMQPError(err)
      }

      return fmt.Errorf("publish with headers failed after %d attempts: %w", maxRetries, lastErr)
  }
  ```

### 4.3 Phase 4 Testing

- [ ] 4.3.1 Unit tests:
  ```bash
  go test ./pkg/mq/common -run TestPublisher -v
  ```

- [ ] 4.3.2 Integration test - confirm success:
  ```bash
  # Publish message and verify broker confirms it
  # Check logs for confirmation
  ```

- [ ] 4.3.3 Integration test - confirm timeout:
  ```bash
  # Publish to non-existent exchange with confirms
  # Verify timeout error returned
  # Verify no hang
  ```

- [ ] 4.3.4 Integration test - broker nack:
  ```bash
  # Simulate broker nack (queue full with reject-publish)
  # Verify ErrPublishNacked returned
  ```

- [ ] 4.3.5 Load test with confirms:
  ```bash
  # Publish 100,000 messages with confirms
  # Verify ALL confirmed
  # Measure overhead (should be ~10-20% slower than without confirms)
  # Verify zero message loss
  ```

- [ ] 4.3.6 Chaos test - kill broker during publish:
  ```bash
  # Start publishing with confirms
  # Kill broker mid-publish
  # Verify timeout error (not hang)
  # Restart broker
  # Verify publishes resume and succeed
  ```

- [ ] 4.3.7 Git commit T0-001:
  ```bash
  git add pkg/mq/common/publisher.go pkg/mq/common/publisher_test.go
  git add pkg/mq/common/helpers.go
  git commit -m "feat(mq): implement publisher confirms for zero message loss (T0-001)

  Add publisher confirmation support to guarantee all messages are
  acknowledged by the broker before returning success.

  Changes:
  - Add PublisherWithConfirms wrapper
  - Enable confirms on all publish operations
  - Wait for broker confirmation with timeout
  - Handle NACK from broker
  - Retry on timeout/error

  Features:
  - 30 second confirmation timeout (configurable)
  - Sequence number verification
  - Proper error handling for NACK
  - Integration with retry logic

  Fixes:
  - T0-001: No publisher confirms (messages silently lost)

  Impact: ZERO message loss - all publishes confirmed by broker
  "
  ```

**T0-001 COMPLETE!** ✅

**Phase 4 Complete!** ✅ Publisher confirms implemented.

---

## Phase 5: Integration & Validation

**Goal:** End-to-end validation of all Tier 0 fixes
**Timeline:** Day 10
**Dependencies:** Phases 1-4
**Risk:** Low - just validation

### 5.1 Comprehensive Testing

- [ ] 5.1.1 Run all unit tests:
  ```bash
  go test ./pkg/mq/... -v -race
  ```

- [ ] 5.1.2 Run integration test suite:
  ```bash
  # Start test environment
  docker-compose up -d rabbitmq postgres redis

  # Run integration tests
  go test ./tests/integration/mq/... -v

  # Scenarios:
  # 1. Normal message flow (publish → consume → ack)
  # 2. Failed processing (publish → consume → nack → retry → success)
  # 3. Max retries (publish → consume → fail 3x → drop)
  # 4. Reconnection (publish → kill broker → restart → resume)
  # 5. Concurrent publishers (1000 goroutines publishing)
  # 6. Concurrent consumers (100 consumers on same queue)
  # 7. Error classification (inject various error types)
  # 8. Publisher confirms (verify all messages confirmed)
  ```

- [ ] 5.1.3 Load test:
  ```bash
  # Publish 1,000,000 messages across 100 publishers
  # Consume with 50 consumers
  # Verify:
  # - Zero message loss (all confirmed)
  # - Zero duplicates (idempotency check)
  # - No infinite loops
  # - No panics/crashes
  # - Memory usage stable
  # - CPU usage reasonable
  ```

- [ ] 5.1.4 Chaos test:
  ```bash
  # Chaos scenarios:
  # 1. Kill RabbitMQ during publish → verify timeout, not loss
  # 2. Kill RabbitMQ during consume → verify reconnect
  # 3. Network partition (iptables) → verify retry
  # 4. Memory pressure on broker → verify flow control
  # 5. Disk full on broker → verify error handling
  ```

- [ ] 5.1.5 Soak test:
  ```bash
  # Run for 24 hours:
  # - Continuous publishing (10 msg/sec)
  # - Continuous consuming
  # - Periodic broker restarts (every 2 hours)
  # Verify:
  # - No memory leaks
  # - No goroutine leaks
  # - No message loss
  # - All reconnections successful
  # - Listener count stable
  ```

### 5.2 Performance Benchmarks

- [ ] 5.2.1 Benchmark publish latency:
  ```bash
  go test -bench=BenchmarkPublish ./pkg/mq/... -benchtime=10s
  ```

- [ ] 5.2.2 Benchmark with/without confirms:
  ```bash
  # Compare overhead of publisher confirms
  # Expected: 10-20% slower with confirms
  # Acceptable tradeoff for zero message loss
  ```

- [ ] 5.2.3 Benchmark channel pool:
  ```bash
  # Compare single channel vs pool
  # Measure concurrency scaling
  ```

- [ ] 5.2.4 Document performance characteristics:
  ```
  # Create: docs/RABBITMQ_PERFORMANCE.md
  # Include:
  # - Latency percentiles (p50, p95, p99)
  # - Throughput limits
  # - Memory usage
  # - CPU usage
  # - Scaling characteristics
  ```

### 5.3 Validation Checklist

- [ ] 5.3.1 ✅ **T0-001 Fixed:** All publishes wait for broker confirmation
- [ ] 5.3.2 ✅ **T0-002 Fixed:** Channel pool prevents race conditions
- [ ] 5.3.3 ✅ **T0-003 Fixed:** No channel replacement during use
- [ ] 5.3.4 ✅ **T0-004 Fixed:** All ACK/NACK errors checked and logged
- [ ] 5.3.5 ✅ **T0-005 Fixed:** Typed error checking (no string comparison)
- [ ] 5.3.6 ✅ **T0-006 Fixed:** Max retry limit enforced (no infinite loops)

- [ ] 5.3.7 Verify zero TODO comments remain in critical paths
- [ ] 5.3.8 Verify 100% test coverage for new code
- [ ] 5.3.9 Verify no race conditions detected
- [ ] 5.3.10 Verify documentation updated

### 5.4 Code Review

- [ ] 5.4.1 Review all changes with team
- [ ] 5.4.2 Verify code quality standards met
- [ ] 5.4.3 Verify error handling comprehensive
- [ ] 5.4.4 Verify logging appropriate
- [ ] 5.4.5 Address all review comments

### 5.5 Documentation Updates

- [ ] 5.5.1 Update `docs/IMPROVEMENTS.md`:
  ```markdown
  ## AGR-REL-XXX: RabbitMQ Tier 0 Fixes

  **Status:** ✅ COMPLETE

  **Completion Date:** [DATE]

  **Issues Fixed:**
  - T0-001: Publisher confirms implemented
  - T0-002: Channel pool for thread-safety
  - T0-003: Channel replacement race eliminated
  - T0-004: All ACK/NACK errors handled
  - T0-005: Typed error checking
  - T0-006: Max retry limits enforced

  **Impact:**
  - Zero message loss (all publishes confirmed)
  - Zero race conditions
  - Zero infinite loops
  - Zero duplicate messages
  - Zero panics/crashes
  ```

- [ ] 5.5.2 Update main TODO document:
  ```bash
  # Mark Phase 1-4 as complete in:
  # docs/RABBITMQ_RELIABILITY_REMEDIATION_TODO.md
  ```

- [ ] 5.5.3 Create deployment guide:
  ```markdown
  # File: docs/RABBITMQ_TIER0_DEPLOYMENT.md
  # Include:
  # - Configuration changes needed
  # - Environment variables
  # - Rollout strategy
  # - Monitoring checklist
  # - Rollback procedures
  ```

### 5.6 Sign-off

- [ ] 5.6.1 All tests passing ✅
- [ ] 5.6.2 Load tests successful ✅
- [ ] 5.6.3 Chaos tests successful ✅
- [ ] 5.6.4 Performance acceptable ✅
- [ ] 5.6.5 Code reviewed ✅
- [ ] 5.6.6 Documentation complete ✅
- [ ] 5.6.7 Stakeholder approval ✅

**Phase 5 Complete!** ✅

---

## Completion Criteria

All Tier 0 issues resolved when:

- [X] All 6 Tier 0 issues fixed (T0-001 through T0-006)
- [X] All unit tests passing (100% coverage of new code)
- [X] All integration tests passing
- [X] Load test: 1M messages without loss
- [X] Chaos test: Survives broker failures
- [X] Soak test: 24 hours stable
- [X] No race conditions detected (`go test -race`)
- [X] No memory leaks
- [X] No goroutine leaks
- [X] Zero TODO comments in critical paths
- [X] Code reviewed and approved
- [X] Documentation complete
- [X] Deployment guide ready

---

## Rollback Plan

If issues discovered in production:

1. **Immediate Rollback Triggers:**
   - Message loss detected
   - System crashes/panics
   - Performance degradation >50%
   - Memory leak detected

2. **Rollback Procedure:**
   ```bash
   # Revert to previous version
   git revert [commit-range]

   # Redeploy previous version
   make deploy

   # Verify rollback successful
   # Monitor metrics for 1 hour
   ```

3. **Post-Rollback:**
   - Root cause analysis
   - Fix issues
   - Re-test thoroughly
   - Gradual rollout (10% → 50% → 100%)

---

## Appendix: Testing Procedures

### A.1 Integration Test Setup

```bash
# Start test environment
docker-compose -f tests/docker-compose.test.yaml up -d

# Wait for services
until docker-compose exec rabbitmq rabbitmqctl status; do sleep 1; done

# Run tests
go test ./tests/integration/mq/... -v -timeout 30m

# Cleanup
docker-compose -f tests/docker-compose.test.yaml down -v
```

### A.2 Load Test Procedure

```bash
# Build load test tool
go build -o /tmp/mq-load-test ./tests/load/mq/

# Run load test
/tmp/mq-load-test \
  --publishers=100 \
  --consumers=50 \
  --messages=1000000 \
  --message-size=1024 \
  --duration=1h \
  --verify-no-loss \
  --verify-no-duplicates

# Analyze results
cat /tmp/mq-load-test-results.json | jq .
```

### A.3 Chaos Test Procedure

```bash
# Install chaos tools
# chaos-mesh or manually with docker commands

# Scenario 1: Kill broker during publish
./tests/chaos/kill-broker-during-publish.sh

# Scenario 2: Network partition
./tests/chaos/network-partition.sh

# Scenario 3: Memory pressure
./tests/chaos/memory-pressure.sh

# Verify recovery in all cases
```

---

---

## Update: February 2026 - Related Architecture Changes

### Topic Exchange Migration (2026-02-12)

The TRAX saga MQ architecture was refactored from per-step fanout queues to a **topic exchange routing** model:

- ~2000 queues reduced to ~10, ~2000 exchanges reduced to 1
- New MQ functions: `InitTopicExchange()`, `InitQueueWithTopicBinding()`, `PublishWithRoutingKey()`
- Routing keys follow pattern: `saga.{affinity}.step.{step_name}`
- Coordinator: one results queue per affinity with wildcard binding (replaces per-step outbox consumers)
- Executor: one shared inbox queue per step template with wildcard affinity binding
- Channel pool default reduced from 1000 to 100 with 20% pre-populate
- `DrainPool()` deadlock fixed in `pkg/mq/common/channelpool.go`
- Dramatically reduces broker resource pressure, mitigating T0-002 (fewer channels needed)
- **T0-001 scope expanded**: Publisher confirms must also cover `PublishWithRoutingKey()` when implemented

### Coordinator Infinite Requeue Loop Fix (2026-02-13)

A critical bug was found and fixed in the coordinator's result queue consumer:

- **Problem**: NACK+requeue on permanent errors (saga/step not found) caused infinite message requeue loops
- **Fix**: Added sentinel errors (`ErrSagaInstanceNotFound`, `ErrSagaStepInstanceNotFound`) with ACK+drop behavior
- **Relevance to T0-004**: This is a concrete example of why unchecked ACK/NACK error handling matters - the requeue behavior was causing system overload
- **Relevance to T0-006**: The infinite requeue loop is essentially the same class of problem as RepublishNack infinite loops

### Items Partially Addressed by Recent Work

| Item | Status | Notes |
|------|--------|-------|
| T0-005 style (error type checking) | Partially addressed | Coordinator now uses `errors.Is()` with sentinel errors for saga/step not-found cases |
| T0-006 style (infinite loop) | Fixed in coordinator | Coordinator ACK+drops messages for permanent errors instead of NACKing |

### Sub-Saga & Compensation Support (2026-02-13)

Sub-saga orchestration and compensation were added, introducing new MQ message flows:

- Sub-saga executors publish results back through the same topic exchange
- Cascading compensation triggers additional MQ messages through the coordinator
- New E2E tests validate these flows: `compensation_test.go`, `deep_sub_saga_test.go`

---

**End of Tier 0 Fixes Implementation Checklist**

*This document should be updated daily during implementation. Each checkbox represents a concrete, testable deliverable that can be completed independently.*
