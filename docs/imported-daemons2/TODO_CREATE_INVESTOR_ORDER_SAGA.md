# TODO: Create Investor Order Saga (`create_investor_order`)

> **Status**: NOT STARTED
> **Created**: 2026-03-05
> **Last Updated**: 2026-03-05
> **Feature**: TRAX saga for creating investor orders via prtagent with treasury balance verification and cash-token locking
> **Short ID**: CIO
> **Dependencies**: Legal participant setup (PLEGP), Cash token deployment, Security listing deployment, Fund account saga
> **Enables**: Proper investor order lifecycle with balance locks, fee collection, and FIX venue submission
> **Lifecycle Doc**: `docs/INVESTOR_ORDER_LIFECYCLE.md` (must be kept in sync with this implementation)

---

## Overview

The `create_investor_order` saga replaces the current synchronous HTTP relay in prtagent's `CreateOrderAsync()` (which calls `POST /orders/by-listing` on marketmgr) with a proper 6-step TRAX-orchestrated workflow. This saga:

1. **Validates** all inputs and resolves blockchain addresses from the participant's legal structure
2. **Creates** an auditable order request record with embedded event logs (JSONB)
3. **Verifies** sufficient cash-token balance in the investor's holding vault
4. **Locks** the order volume by transferring cash tokens to a dedicated stash
5. **Transfers** the fee to the participant's clearing account
6. **Submits** the order to the FIX venue via fixclient

**Coexistence**: This saga coexists with the existing `create_direct_order` saga (listingmgr). CDO handles on-chain exchange orders via LASER. This saga handles off-chain broker/participant orders via FIX.

```
                                 create_investor_order saga
                                 ═════════════════════════
  gRPC Client                         TRAX Steps                           Backend
  ──────────    ┌──────────────────────────────────────────────────┐    ──────────
                │                                                  │
  CreateOrder ──┤  Step 1: cio_validate_inputs       [prtagent]    │
  Async         │    ├─ Validate fields                            │
                │    ├─ Resolve legal structure addresses           │
                │    ├─ Generate order_stash_index                  │
                │    └─ Pass: all addresses, stash index            │
                │                                                  │
                │  Step 2: cio_create_order_request   [marketmgr]  │──▶ marketmgr.order_requests
                │    ├─ Create order request record                 │
                │    ├─ Add first OrderEventLog                     │
                │    └─ Pass: order_request_iid                     │
                │                                                  │
                │  Step 3: cio_verify_balance          [treassvc]   │──▶ LASER (query vault)
                │    ├─ Query investor vault stash 0 balance        │
                │    ├─ Verify balance >= volume + fee              │
                │    ├─ Verify order_stash has zero balance         │
                │    └─ Pass: verified_balance                      │
                │                                                  │
                │  Step 4: cio_lock_order_volume       [treassvc]   │──▶ LASER (TrezorErc20TransferVaultBalance)
                │    ├─ Transfer volume: stash 0 → order_stash     │
                │    ├─ On investor vault                           │
                │    └─ Pass: lock_tx_hash                          │
                │                                                  │
                │  Step 5: cio_transfer_fee            [treassvc]   │──▶ LASER (TrezorErc20TransferVaultBalance)
                │    ├─ Transfer fee: investor stash 0 →            │
                │    │   clearing account stash 0                   │
                │    └─ Pass: fee_tx_hash                           │
                │                                                  │
                │  Step 6: cio_submit_to_fix           [marketmgr]  │──▶ fixclient REST API
                │    ├─ Resolve venue via Redis                     │
                │    ├─ POST to fixclient                           │
                │    ├─ Update order request record                 │
                │    └─ Return: request_id, venue_iid               │
                │                                                  │
                └──────────────────────────────────────────────────┘

  COMPENSATION (reverse order):
  Step 6: Log failure event, update status to REJECTED
  Step 5: Reverse fee transfer (clearing → investor vault stash 0)
  Step 4: Reverse volume transfer (order_stash → investor vault stash 0)
  Step 3: Log compensation event
  Step 2: Append compensation event logs (DO NOT delete record)
  Step 1: No-op
```

---

## Prerequisites

1. Legal participant fully set up (PLEGP) with:
   - Legal structure with clearing account
   - Cash token mechanism matching the order currency
   - Investor onboarded with holding vault funded
2. Security listing deployed with FIX venue connection active
3. Redis mapping populated (`mktmgr:seclist:venue:{security_listing_iid}`)
4. TRAX cluster running with coordinators
5. RabbitMQ available for executor messaging

---

## Phase 1: Domain Model Changes

### 1.1 New `OrderRequestEventTypeEnum` in `pkg/fin/`

**File**: `pkg/fin/order_request_event.go` [NEW]

This is a **saga-specific** event type enum, distinct from the existing `OrderEventTypeEnum` (which is for on-chain order lifecycle events).

```go
package fin

// OrderRequestEventTypeEnum represents saga step events for investor order requests.
// These track the order request lifecycle through the create_investor_order saga.
type OrderRequestEventTypeEnum string

const (
    OrderRequestEventTypeEnum_Unknown OrderRequestEventTypeEnum = "UNKNOWN"

    // Forward path events (saga execution)
    OrderRequestEventTypeEnum_OrderRequestCreated     OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_ORDER_REQUEST_CREATED"
    OrderRequestEventTypeEnum_BalanceVerified          OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_BALANCE_VERIFIED"
    OrderRequestEventTypeEnum_VolumeLocked             OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_VOLUME_LOCKED"
    OrderRequestEventTypeEnum_FeeTransferred           OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_FEE_TRANSFERRED"
    OrderRequestEventTypeEnum_SubmittedToFix           OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_SUBMITTED_TO_FIX"
    OrderRequestEventTypeEnum_OrderCompleted           OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_ORDER_COMPLETED"

    // Compensation path events (saga rollback)
    OrderRequestEventTypeEnum_CompensationStarted        OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_COMPENSATION_STARTED"
    OrderRequestEventTypeEnum_CompensationVolumeReturned OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_COMPENSATION_VOLUME_RETURNED"
    OrderRequestEventTypeEnum_CompensationFeeReturned    OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_COMPENSATION_FEE_RETURNED"
    OrderRequestEventTypeEnum_CompensationCompleted      OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_COMPENSATION_COMPLETED"

    // Error events
    OrderRequestEventTypeEnum_ValidationFailed      OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_VALIDATION_FAILED"
    OrderRequestEventTypeEnum_BalanceCheckFailed     OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_BALANCE_CHECK_FAILED"
    OrderRequestEventTypeEnum_VolumeLockFailed       OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_VOLUME_LOCK_FAILED"
    OrderRequestEventTypeEnum_FeeTransferFailed      OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_FEE_TRANSFER_FAILED"
    OrderRequestEventTypeEnum_FixSubmissionFailed    OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_FIX_SUBMISSION_FAILED"
)

// OrderRequestEventLog represents a single event log entry embedded in the
// order_requests JSONB event_logs column.
type OrderRequestEventLog struct {
    Id              string                    `json:"id"`               // UUID
    Type            OrderRequestEventTypeEnum `json:"type"`             // Event type
    Message         string                    `json:"message"`          // Human-readable message
    StepName        string                    `json:"step_name"`        // Saga step template ID (e.g., "cio_verify_balance")
    SagaInstanceId  string                    `json:"saga_instance_id"` // TRAX saga instance ID
    Timestamp       string                    `json:"timestamp"`        // ISO 8601
    Details         map[string]string         `json:"details"`          // Step-specific key-value details
}
```

### 1.2 New `OrderRequestStatusEnum` in `pkg/fin/`

**File**: `pkg/fin/order_request.go` [NEW]

```go
package fin

// OrderRequestStatusEnum represents the status of an investor order request
// as it progresses through the create_investor_order saga.
type OrderRequestStatusEnum string

const (
    OrderRequestStatusEnum_Unknown    OrderRequestStatusEnum = "UNKNOWN"
    OrderRequestStatusEnum_Pending    OrderRequestStatusEnum = "ORDER_REQUEST_STATUS_ENUM_PENDING"
    OrderRequestStatusEnum_Validated  OrderRequestStatusEnum = "ORDER_REQUEST_STATUS_ENUM_VALIDATED"
    OrderRequestStatusEnum_Verified   OrderRequestStatusEnum = "ORDER_REQUEST_STATUS_ENUM_VERIFIED"
    OrderRequestStatusEnum_Locked     OrderRequestStatusEnum = "ORDER_REQUEST_STATUS_ENUM_LOCKED"
    OrderRequestStatusEnum_FeeCharged OrderRequestStatusEnum = "ORDER_REQUEST_STATUS_ENUM_FEE_CHARGED"
    OrderRequestStatusEnum_Submitted  OrderRequestStatusEnum = "ORDER_REQUEST_STATUS_ENUM_SUBMITTED"
    OrderRequestStatusEnum_Completed  OrderRequestStatusEnum = "ORDER_REQUEST_STATUS_ENUM_COMPLETED"
    OrderRequestStatusEnum_Rejected   OrderRequestStatusEnum = "ORDER_REQUEST_STATUS_ENUM_REJECTED"
    OrderRequestStatusEnum_Compensated OrderRequestStatusEnum = "ORDER_REQUEST_STATUS_ENUM_COMPENSATED"
    OrderRequestStatusEnum_Failed     OrderRequestStatusEnum = "ORDER_REQUEST_STATUS_ENUM_FAILED"
)

// OrderRequest represents an investor order request record in the marketmgr.order_requests table.
// This is the order request created by the create_investor_order saga, NOT the on-chain order
// managed by listingmgr.orders (which is used by the create_direct_order saga).
type OrderRequest struct {
    Iid string `json:"iid"` // Primary key, format: "ordreq-{uuid}"

    // Order identifiers
    ParticipantOrderId string `json:"participant_order_id"` // Client's order ID (from gRPC request)
    ExternalOrderId     string `json:"external_order_id"`     // External tracking ID

    // Participant references
    ParticipantIid string `json:"participant_iid"` // Participant IID (from auth context)
    InvestorIid    string `json:"investor_iid"`    // Investor external ID (account_iid from gRPC)

    // Resolved addresses (populated by step 1)
    InvestorAccountIid        string `json:"investor_account_iid"`         // Investor's CSD account IID
    removed     string `json:"removed"`      // Participant's CSD account IID
    InvestorVaultLaserSlotAddress         string `json:"investor_vault_laser_slot_address"`           // Investor holding vault ETH/slot address
    ClearingAccountVaultLaserSlotAddress  string `json:"clearing_account_vault_laser_slot_address"`   // Clearing account vault ETH/slot address
    CashTokenLaserSlotAddress     string `json:"cash_token_laser_slot_address"`      // ERC20 cash token contract address
    TreasuryLaserSlotAddress      string `json:"treasury_laser_slot_address"`        // Trezor diamond contract address

    // Security listing
    SecurityListingIid string `json:"security_listing_iid"` // LASER IID of the security listing

    // Order parameters
    Side        string `json:"side"`         // BUY or SELL
    OrderType   string `json:"order_type"`   // LIMIT or MARKET
    Quantity    string `json:"quantity"`      // Human-readable decimal
    Price       string `json:"price"`        // Human-readable decimal (0 for MARKET)
    Currency    string `json:"currency"`     // ISO 4217 3-letter code (e.g., "EUR", "USD")
    FeeAmount   string `json:"fee_amount"`   // Fee in same currency, human-readable decimal
    TimeInForce string `json:"time_in_force"` // DAY, GTC, IOC, FOK

    // Stash management
    OrderStashIndex int64 `json:"order_stash_index"` // Random stash ID [1,000,000,001 .. 11,000,000,001]

    // Status and lifecycle
    Status OrderRequestStatusEnum `json:"status"`

    // Saga context
    SagaInstanceId string `json:"saga_instance_id"` // TRAX saga instance ID
    TraceId        string `json:"trace_id"`
    IdempotencyKey string `json:"idempotency_key"`
    ExecRuntimeName string `json:"exec_runtime_name"` // Execution runtime for LASER calls

    // FIX submission results (populated by step 6)
    FixRequestId string `json:"fix_request_id"` // fixclient request_id from 202 response
    FixVenueIid  string `json:"fix_venue_iid"`  // Resolved venue IID
    FixClOrdId   string `json:"fix_cl_ord_id"`  // ClOrdID sent to FIX
    FixVersion   string `json:"fix_version"`    // FIX protocol version
    FixSentAt    string `json:"fix_sent_at"`    // RFC3339 timestamp of FIX submission

    // Transaction hashes (populated by steps 4, 5)
    VolumeLockTxHash  string `json:"volume_lock_tx_hash"`  // Step 4 transfer tx hash
    FeeTransferTxHash string `json:"fee_transfer_tx_hash"` // Step 5 transfer tx hash

    // Event logs (JSONB)
    EventLogs []OrderRequestEventLog `json:"event_logs"` // Append-only list of saga step events

    // Standard fields
    DisplayNames map[string]string `json:"display_names"`
    Descriptions map[string]string `json:"descriptions"`
    Labels       map[string]string `json:"labels"`
    Tags         []string          `json:"tags"`
    Metadata     map[string]string `json:"metadata"`
}
```

### 1.3 Consolidate execpl Enums into fin Package

**File**: `pkg/execpl/consts.go` [MODIFY]
**File**: `pkg/fin/order.go` [MODIFY]
**File**: `pkg/fin/trading_enums.go` [NEW]

The `execpl` package currently has its own `OrderStatusEnum`, `OrderTypeEnum`, `SideTypeEnum`, `TimeInForceTypeEnum`, `ExecutionTypeEnum`. These must be consolidated into `pkg/fin/` as the canonical source.

**Steps**:
- [ ] 1.3.1 Create `pkg/fin/trading_enums.go` with the consolidated enum definitions. The fin package already has `OrderStatusEnum`, `OrderSideEnum`, `OrderTypeEnum`. Add the missing ones:
  - `TimeInForceEnum` (new in fin)
  - `ExecutionTypeEnum` (new in fin)
  - `SideTypeEnum` (alias to `OrderSideEnum` with extended values from execpl)

- [ ] 1.3.2 In `pkg/execpl/consts.go`, replace the enum type definitions with type aliases pointing to `pkg/fin/`:
  ```go
  // Deprecated: use fin.OrderStatusEnum
  type OrderStatusEnum = fin.OrderStatusEnum
  const OrderStatusEnum_New = fin.OrderStatusEnum_New
  // ... etc
  ```
  This preserves backward compatibility for existing execpl consumers.

- [ ] 1.3.3 Update all direct references in the codebase from `execpl.OrderStatusEnum` to `fin.OrderStatusEnum` where the import is straightforward. Leave the aliases in place for any complex cases.

**Files affected** (search for `execpl.OrderStatusEnum`, `execpl.OrderTypeEnum`, `execpl.SideTypeEnum`):
- `pkg/daemons/fixreceiver/versions/*/execution_report.go`
- `pkg/daemons/fixreceiver/versions/*/convert.go`
- `pkg/daemons/cmdprocessor/process_new_order_single.go`
- `pkg/daemons/cmdbcaster/broadcast_new_order_single.go`
- `pkg/daemons/indexer/event_*.go`
- `pkg/execpl/helpers/publish_helpers.go`

---

## Phase 2: Database Schema

### 2.1 New `marketmgr.order_requests` Table

**File**: `deploy/k8s/init/init_marketmgr_pgsql.sql` [MODIFY]

Add after the existing `marketmgr.instruments` table:

```sql
-- Order requests created by the create_investor_order saga
CREATE TABLE IF NOT EXISTS marketmgr.order_requests (
    iid VARCHAR(128) PRIMARY KEY,

    -- Order identifiers
    participant_order_id VARCHAR(256) NOT NULL,
    external_order_id VARCHAR(256),

    -- Participant references
    participant_iid VARCHAR(256) NOT NULL,
    investor_iid VARCHAR(256) NOT NULL,

    -- Resolved addresses
    investor_account_iid VARCHAR(256),
    removed VARCHAR(256),
    investor_vault_laser_slot_address VARCHAR(256),
    clearing_account_vault_laser_slot_address VARCHAR(256),
    cash_token_laser_slot_address VARCHAR(256),
    treasury_laser_slot_address VARCHAR(256),

    -- Security listing
    security_listing_iid VARCHAR(256) NOT NULL,

    -- Order parameters
    side VARCHAR(10) NOT NULL,              -- BUY or SELL
    order_type VARCHAR(20) NOT NULL,        -- LIMIT or MARKET
    quantity VARCHAR(128) NOT NULL,
    price VARCHAR(128) NOT NULL DEFAULT '0',
    currency VARCHAR(3) NOT NULL,           -- ISO 4217 (e.g., EUR, USD)
    fee_amount VARCHAR(128) NOT NULL DEFAULT '0',
    time_in_force VARCHAR(10) NOT NULL DEFAULT 'DAY',

    -- Stash management
    order_stash_index BIGINT,

    -- Status
    status VARCHAR(64) NOT NULL DEFAULT 'ORDER_REQUEST_STATUS_ENUM_PENDING',

    -- Saga context
    saga_instance_id VARCHAR(128),
    trace_id VARCHAR(128),
    idempotency_key VARCHAR(256),
    exec_runtime_name VARCHAR(256),

    -- FIX submission results
    fix_request_id VARCHAR(128),
    fix_venue_iid VARCHAR(256),
    fix_cl_ord_id VARCHAR(256),
    fix_version VARCHAR(20),
    fix_sent_at TIMESTAMP WITH TIME ZONE,

    -- Transaction hashes
    volume_lock_tx_hash VARCHAR(256),
    fee_transfer_tx_hash VARCHAR(256),

    -- Event logs (JSONB array of OrderRequestEventLog)
    event_logs JSONB NOT NULL DEFAULT '[]'::jsonb,

    -- Standard fields
    display_names JSONB DEFAULT '{}'::jsonb,
    descriptions JSONB DEFAULT '{}'::jsonb,
    labels JSONB DEFAULT '{}'::jsonb,
    tags JSONB DEFAULT '[]'::jsonb,
    metadata JSONB DEFAULT '{}'::jsonb,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Foreign key to shared entities
    CONSTRAINT fk_order_requests_entity FOREIGN KEY (iid) REFERENCES shared.entities(iid) ON DELETE CASCADE
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_order_requests_participant_order_id ON marketmgr.order_requests (participant_order_id);
CREATE INDEX IF NOT EXISTS idx_order_requests_participant_iid ON marketmgr.order_requests (participant_iid);
CREATE INDEX IF NOT EXISTS idx_order_requests_investor_iid ON marketmgr.order_requests (investor_iid);
CREATE INDEX IF NOT EXISTS idx_order_requests_security_listing_iid ON marketmgr.order_requests (security_listing_iid);
CREATE INDEX IF NOT EXISTS idx_order_requests_status ON marketmgr.order_requests (status);
CREATE INDEX IF NOT EXISTS idx_order_requests_saga_instance_id ON marketmgr.order_requests (saga_instance_id);
CREATE INDEX IF NOT EXISTS idx_order_requests_fix_request_id ON marketmgr.order_requests (fix_request_id);
CREATE INDEX IF NOT EXISTS idx_order_requests_currency ON marketmgr.order_requests (currency);
CREATE INDEX IF NOT EXISTS idx_order_requests_created_at ON marketmgr.order_requests (created_at);
```

### 2.2 Update Mini Records SQL

**File**: `deploy/k8s/init/csd/min/marketmgr.sql` [MODIFY] (or create if not exists)

Add sample order request records for testing:

```sql
-- Sample order request (completed)
INSERT INTO shared.entities (iid, type, status, locale) VALUES ('ordreq-sample-001', 'order_request', 'active', 'en-US') ON CONFLICT DO NOTHING;
INSERT INTO marketmgr.order_requests (iid, participant_order_id, participant_iid, investor_iid, security_listing_iid, side, order_type, quantity, price, currency, fee_amount, status, event_logs)
VALUES ('ordreq-sample-001', 'client-ord-001', 'participant-001', 'investor-001', 'seclist-001', 'BUY', 'LIMIT', '100', '25.50', 'EUR', '1.50', 'ORDER_REQUEST_STATUS_ENUM_COMPLETED', '[]'::jsonb)
ON CONFLICT DO NOTHING;
```

---

## Phase 3: Proto Changes

### 3.1 Modify `CreateOrderAsyncRequest`

**File**: `data/api/grpc/prtagent/v1/trading.proto` [MODIFY]

> Note (2026-05-02): the broker-trading-side replacement gateway
> `brktrdapi` will absorb `CreateOrder` once it ships (see
> `docs/TODO_BRKTRDAPI_AND_BRKADMAPI.md`). Until then this proto is
> the only client-facing entrypoint. Broker-admin oversight RPCs
> (sagas + execution/trade reports) are already exposed by the
> already-shipping `brkadmapi` / `brkadmsvc`.

Add two new fields to the existing `CreateOrderAsyncRequest` message:

```protobuf
message CreateOrderAsyncRequest {
  // ... existing fields (1-12) ...

  string currency = 13;                  // REQUIRED: ISO 4217 3-letter currency code (e.g., "EUR", "USD")
  string fee_amount = 14;                // REQUIRED: Fee amount in same currency (human-readable decimal)
}
```

After modifying the proto, run:
```bash
make gen-proto
```

### 3.2 Validate New Fields in gRPC Handler

**File**: `pkg/daemons/prtagent/impl/v1/grpc/trading.go` [MODIFY]

In `CreateOrderAsync()`, add validation for the new fields:

```go
if req.Currency == "" {
    return &grpccommon.ExecutionAsyncResponse{
        AsyncStatus: grpccommon.AsyncResponseStatusEnum_ASYNC_RESPONSE_STATUS_ENUM_BAD_REQUEST,
        Msg:         "currency is required (ISO 4217 3-letter code, e.g., EUR, USD)",
    }, nil
}
if len(req.Currency) != 3 {
    return &grpccommon.ExecutionAsyncResponse{
        AsyncStatus: grpccommon.AsyncResponseStatusEnum_ASYNC_RESPONSE_STATUS_ENUM_BAD_REQUEST,
        Msg:         "currency must be exactly 3 characters (ISO 4217)",
    }, nil
}
if req.FeeAmount == "" {
    return &grpccommon.ExecutionAsyncResponse{
        AsyncStatus: grpccommon.AsyncResponseStatusEnum_ASYNC_RESPONSE_STATUS_ENUM_BAD_REQUEST,
        Msg:         "fee_amount is required",
    }, nil
}
```

---

## Phase 4: Marketmgr Order Request Store

### 4.1 Store Interface

**File**: `pkg/daemons/marketmgr/order_request_store.go` [NEW]

```go
package marketmgr

import (
    "context"
    "qomet.tech/agora/daemons/pkg/common"
    "qomet.tech/agora/daemons/pkg/fin"
)

type OrderRequestStore interface {
    CreateOrderRequest(ctx context.Context, req *fin.OrderRequest) error
    GetOrderRequest(ctx context.Context, iid string) (*fin.OrderRequest, error)
    GetOrderRequestByParticipantOrderId(ctx context.Context, participantOrderIid string) (*fin.OrderRequest, error)
    GetOrderRequestBySagaInstanceId(ctx context.Context, sagaInstanceId string) (*fin.OrderRequest, error)
    UpdateOrderRequest(ctx context.Context, req *fin.OrderRequest) error
    UpdateOrderRequestStatus(ctx context.Context, iid string, status fin.OrderRequestStatusEnum) error
    AppendEventLog(ctx context.Context, iid string, eventLog fin.OrderRequestEventLog) error
    ListOrderRequests(ctx context.Context, opts common.QueryOptions) ([]*fin.OrderRequest, int, error)
    QueryOrderRequests(ctx context.Context, opts common.QueryOptions) ([]*fin.OrderRequest, int, error)
}
```

### 4.2 PostgreSQL Implementation

**File**: `pkg/daemons/marketmgr/order_request_store_psql.go` [NEW]

Follow the same pattern as `pkg/daemons/marketmgr/market_store_psql.go`:
- [ ] 4.2.1 Implement `CreateOrderRequest` — INSERT with entity creation in `shared.entities`
- [ ] 4.2.2 Implement `GetOrderRequest` — SELECT by IID
- [ ] 4.2.3 Implement `GetOrderRequestByParticipantOrderId` — SELECT by participant_order_id
- [ ] 4.2.4 Implement `GetOrderRequestBySagaInstanceId` — SELECT by saga_instance_id
- [ ] 4.2.5 Implement `UpdateOrderRequest` — UPDATE full record
- [ ] 4.2.6 Implement `UpdateOrderRequestStatus` — UPDATE status only + updated_at
- [ ] 4.2.7 Implement `AppendEventLog` — use PostgreSQL JSONB append:
  ```sql
  UPDATE marketmgr.order_requests
  SET event_logs = event_logs || $2::jsonb, updated_at = NOW()
  WHERE iid = $1
  ```
- [ ] 4.2.8 Implement `ListOrderRequests` — SELECT with pagination (limit, offset, sort)
- [ ] 4.2.9 Implement `QueryOrderRequests` — SELECT with `common.QueryOptions` filtering

### 4.3 In-Memory Implementation (for testing)

**File**: `pkg/daemons/marketmgr/order_request_store_inmem.go` [NEW]

Follow the pattern of `pkg/daemons/marketmgr/market_store_inmem.go` with `sync.RWMutex` protection.

### 4.4 REST API Endpoints for Order Requests

**File**: `pkg/daemons/marketmgr/api/v1/order_requests_get.go` [NEW]
**File**: `pkg/daemons/marketmgr/api/v1/order_requests_get_by_id.go` [NEW]

Add read-only REST endpoints (order creation is saga-only):

```
GET /api/v1/order-requests                              — List with pagination
GET /api/v1/order-requests/:iid                         — Get by IID
GET /api/v1/order-requests/by-participant-order/:id     — Get by participant_order_id
GET /api/v1/order-requests/by-saga/:saga_instance_id    — Get by saga_instance_id
```

**File**: `pkg/daemons/marketmgr/api/v1/api.go` [MODIFY]

Register the new routes in the router.

---

## Phase 5: TRAX Executor Registration

### 5.1 PrtAgent TRAX Executor Infrastructure

**File**: `pkg/daemons/prtagent.go` [MODIFY]

PrtAgent currently has a TRAX saga submitter but NO executor. Add executor registration:

```go
// After existing traxSubmitter setup...
// Initialize TRAX executor for create_investor_order saga
if traxClusterId != "" {
    mqClient := trax.NewRabbitMQClient()
    go prtagent_executors.RunExecutorsAsync(ctx, mqClient, traxClusterId, accMgrBaseURL)
}
```

**File**: `pkg/daemons/prtagent/trax/executors/run.go` [NEW]

```go
package executors

import (
    "context"
    "time"

    "qomet.tech/agora/daemons/pkg/trax"
    "qomet.tech/agora/daemons/pkg/daemons/prtagent/trax/executors/create_investor_order"
)

func RunExecutorsAsync(ctx context.Context, mqClient trax.MQClient, clusterId string, accMgrBaseURL string) {
    create_investor_order.SetDependencies(accMgrBaseURL)
    go create_investor_order.RunStep1Executor(ctx, mqClient, clusterId)
    time.Sleep(30 * time.Millisecond)
}
```

### 5.2 MarketMgr TRAX Executor Infrastructure

**File**: `pkg/daemons/marketmgr.go` [MODIFY]

MarketMgr currently has NO TRAX executor. Add:

```go
// After existing store setup...
// Initialize TRAX executor for create_investor_order saga
traxClusterId := os.Getenv("TRAX_CLUSTER_ID")
if traxClusterId != "" {
    mqClient := trax.NewRabbitMQClient()
    go marketmgr_executors.RunExecutorsAsync(ctx, mqClient, traxClusterId, orderRequestStore, fixClientBaseURL, redisClient)
}
```

Environment variables to add:
- `TRAX_CLUSTER_ID` — TRAX cluster identifier
- `RABBITMQ_CONN_STRING` — RabbitMQ connection

**File**: `pkg/daemons/marketmgr/trax/executors/run.go` [NEW]

```go
package executors

import (
    "context"
    "time"

    "qomet.tech/agora/daemons/pkg/trax"
    "qomet.tech/agora/daemons/pkg/daemons/marketmgr"
    "qomet.tech/agora/daemons/pkg/daemons/marketmgr/trax/executors/create_investor_order"
)

var pkgOrderRequestStore marketmgr.OrderRequestStore

func RunExecutorsAsync(ctx context.Context, mqClient trax.MQClient, clusterId string, store marketmgr.OrderRequestStore, fixClientBaseURL string, redisClient interface{}) {
    pkgOrderRequestStore = store
    create_investor_order.SetDependencies(store, fixClientBaseURL, redisClient)
    go create_investor_order.RunStep2Executor(ctx, mqClient, clusterId)
    time.Sleep(30 * time.Millisecond)
    go create_investor_order.RunStep6Executor(ctx, mqClient, clusterId)
}

func UpdateOrderRequestStore(store marketmgr.OrderRequestStore) {
    pkgOrderRequestStore = store
    create_investor_order.UpdateOrderRequestStore(store)
}
```

### 5.3 TreasSvc TRAX Executor Registration

**File**: `pkg/daemons/treassvc/trax/executors/run.go` [MODIFY]

Add the 3 new step executors:

```go
import "qomet.tech/agora/daemons/pkg/daemons/treassvc/trax/executors/create_investor_order"

func RunExecutorsAsync(ctx context.Context, mqClient trax.MQClient, clusterId string, laserBaseURL string, laserAuthKey string) {
    // ... existing fund_account_with_cash_tokens executors ...
    // ... existing withdraw_cash_tokens_from_account executors ...

    // create_investor_order saga steps
    create_investor_order.SetDependencies(laserBaseURL, laserAuthKey)
    go create_investor_order.RunStep3Executor(ctx, mqClient, clusterId)
    time.Sleep(30 * time.Millisecond)
    go create_investor_order.RunStep4Executor(ctx, mqClient, clusterId)
    time.Sleep(30 * time.Millisecond)
    go create_investor_order.RunStep5Executor(ctx, mqClient, clusterId)
}
```

---

## Phase 6: Saga Step Implementations

### Saga Template and Step Naming Convention

| Step | Template ID | Executor | Service |
|------|------------|----------|---------|
| 1 | `cio_validate_inputs` | prtagent | prtagent |
| 2 | `cio_create_order_request` | marketmgr | marketmgr |
| 3 | `cio_verify_balance` | treassvc | treassvc |
| 4 | `cio_lock_order_volume` | treassvc | treassvc |
| 5 | `cio_transfer_fee` | treassvc | treassvc |
| 6 | `cio_submit_to_fix` | marketmgr | marketmgr |

### Saga Input Parameters

These are provided when `SubmitSaga()` is called from prtagent's `CreateOrderAsync()`:

| Parameter | Type | Source | Description |
|-----------|------|--------|-------------|
| `security_listing_iid` | string | gRPC request | Security listing IID |
| `participant_order_id` | string | gRPC request | Client's order ID |
| `account_iid` | string | gRPC request | External investor ID |
| `side` | string | gRPC request | BUY or SELL |
| `order_type` | string | gRPC request | LIMIT or MARKET |
| `quantity` | string | gRPC request | Order quantity |
| `price` | string | gRPC request | Order price (0 for MARKET) |
| `currency` | string | gRPC request | ISO 4217 currency code |
| `fee_amount` | string | gRPC request | Fee amount |
| `time_in_force` | string | gRPC request | DAY, GTC, IOC, FOK |
| `participant_iid` | string | auth context | Participant IID |
| `fee_payer_account_iid` | string | gRPC request | Optional fee payer |
| `csd_account_iid` | string | gRPC request | Optional CSD account |
| `proposed_execution_id` | string | gRPC request | Client's tracking ID |
| `exec_runtime_name` | string | env/config | Execution runtime for LASER |

### 6.1 Step 1: `cio_validate_inputs` (prtagent executor)

**File**: `pkg/daemons/prtagent/trax/executors/create_investor_order/validate_inputs.go` [NEW]

**Execution**:
1. Validate all required input parameters (fail immediately if missing):
   - `security_listing_iid` — non-empty
   - `participant_order_id` — non-empty
   - `account_iid` — non-empty (external investor ID)
   - `side` — must be "BUY" or "SELL"
   - `order_type` — must be "LIMIT" or "MARKET"
   - `quantity` — positive decimal
   - `price` — for LIMIT: positive decimal; for MARKET: must be "0"
   - `currency` — exactly 3 characters (ISO 4217)
   - `fee_amount` — non-negative decimal
   - `time_in_force` — must be "DAY", "GTC", "IOC", or "FOK" (default "DAY" if empty)
   - `participant_iid` — non-empty (from auth context)

2. Resolve investor CSD account IID:
   - Reuse existing `resolveInvestorAccountIid()` logic from `trading.go`
   - Query accmgr: `GET /participants/{participant_iid}/investors?limit=500`
   - Find investor by `account_iid` (external investor ID)
   - Extract `csd_accounts` from investor metadata → `investor_account_iid`

3. Resolve participant's legal structure info:
   - Query accmgr: `GET /participants/{participant_iid}/legal-structures`
   - Get account relations: `GET /legal-structures/{ls_iid}/account-relations`
   - Extract `custody_account_iid` → `removed`
   - Extract clearing account → get `vault_address` from account metadata

4. Resolve cash token + treasury addresses from local legal structure (BUY orders only):
   - Query accmgr: `GET /legal-structures/{ls_iid}/mechanisms`
   - Find CASH_TOKEN mechanism where `metadata["currency_code"]` matches order `currency`
   - Find TREASURY mechanism
   - For each mechanism: `GET /legal-mechanisms/{mech_iid}/deployments` → extract LASER `slot_address`
   - SELL orders skip this step (no cash locking needed)

5. Resolve investor vault address:
   - From the investor's holding account, get the vault slot address
   - Query accmgr: `GET /accounts/{investor_account_iid}` → `metadata["vault_address"]`

8. Generate `order_stash_index`:
   ```go
   // Random int64 in range [1_000_000_001, 11_000_000_001]
   orderStashIndex := rand.Int63n(10_000_000_000) + 1_000_000_001
   ```

**Output** (passed to subsequent steps via saga step result):
```json
{
    "investor_account_iid": "...",
    "removed": "...",
    "investor_vault_laser_slot_address": "...",
    "clearing_account_vault_laser_slot_address": "...",
    "cash_token_laser_slot_address": "...",
    "treasury_laser_slot_address": "...",
    "order_stash_index": "1234567890",
    "validation_status": "ok"
}
```

**Compensation**: No-op (validation-only step, no state changes).

### 6.2 Step 2: `cio_create_order_request` (marketmgr executor)

**File**: `pkg/daemons/marketmgr/trax/executors/create_investor_order/create_order_request.go` [NEW]

**Execution**:
1. Generate IID: `ordreq-{uuid}`
2. Build `OrderRequest` struct from saga inputs + step 1 outputs
3. Set status to `ORDER_REQUEST_STATUS_ENUM_PENDING`
4. Create initial event log entry:
   ```json
   {
       "id": "{uuid}",
       "type": "ORDER_REQUEST_EVENT_TYPE_ENUM_ORDER_REQUEST_CREATED",
       "message": "Order request created with stash index {order_stash_index}",
       "step_name": "cio_create_order_request",
       "saga_instance_id": "{saga_instance_id}",
       "timestamp": "{ISO 8601 now}",
       "details": {
           "participant_order_id": "...",
           "side": "BUY",
           "order_type": "LIMIT",
           "quantity": "100",
           "price": "25.50",
           "currency": "EUR",
           "fee_amount": "1.50",
           "order_stash_index": "1234567890"
       }
   }
   ```
5. Create `shared.entities` record + INSERT into `marketmgr.order_requests`
6. Return `order_request_iid` in step output

**Output**:
```json
{
    "order_request_iid": "ordreq-{uuid}"
}
```

**Compensation**:
- DO NOT delete the record
- Append compensation event log:
  ```json
  {
      "type": "ORDER_REQUEST_EVENT_TYPE_ENUM_COMPENSATION_STARTED",
      "message": "Saga compensation triggered",
      "step_name": "cio_create_order_request",
      ...
  }
  ```
- Update status to `ORDER_REQUEST_STATUS_ENUM_COMPENSATED`

### 6.3 Step 3: `cio_verify_balance` (treassvc executor)

**File**: `pkg/daemons/treassvc/trax/executors/create_investor_order/verify_balance.go` [NEW]

**Execution**:
1. Extract from saga inputs + previous step outputs:
   - `investor_vault_laser_slot_address` (from step 1)
   - `cash_token_laser_slot_address` (from step 1)
   - `treasury_laser_slot_address` (from step 1)
   - `order_stash_index` (from step 1)
   - `quantity`, `price`, `fee_amount` (from saga inputs)
   - `exec_runtime_name` (from saga inputs)
   - `order_request_iid` (from step 2)

2. Calculate required balance using the canonical helpers in
   `pkg/fin/order_lock_amount.go`:
   - LIMIT BUY: `order_volume_raw = ComputeBuyLockAmountRaw(qty, price, currency_divisor)`
   - MARKET BUY: fetch live best ask via marketmgr `/orderbook?security_listing_iid=X&mode=l1`
     (single hop — marketmgr resolves deployment_iid and proxies to
     tradeidxer's L1 snapshot), apply `TREASSVC_MARKET_BUY_SLIPPAGE_BPS`
     (default 1000 = 10%), then `order_volume_raw = ComputeBuyLockAmountRaw(qty, askWithSlippage, currency_divisor)`.
     **Hard saga failure on missing best ask** — locking against a
     guessed price would silently lose money on rejection.
   - SELL: `order_volume_raw = "0"` (no upfront cash lock).
   - `fee_amount_raw = ComputeFeeAmountRaw(fee_amount, currency_divisor)`
   - `total_required_raw = order_volume_raw + fee_amount_raw`

   **Note**: `currency_divisor` is propagated from Step 1 (validate_inputs)
   via TRAX step result chaining. Never assume cash divisibility = 2;
   the helpers handle every divisor combination uniformly. This is the
   load-bearing bit — see `docs/TODO_FIX_DIVISIBILITY_CORRECT_STASH_UNLOCK.md`
   for the bug class this prevents.

3. Query investor vault stash 0 balance via LASER:
   - Use `makeRequest()` pattern (with LASER client auth header)
   - Query crown executor for vault balance: stash_id=0, ledger_id=1
   - The query path follows the same pattern as `query_source_vault_balance.go` in `fund_account_with_cash_tokens`

4. Verify: `stash_0_balance >= total_required`
   - If insufficient → FAIL with error: `"insufficient balance: have {balance}, need {total_required} ({order_volume} + {fee_amount})"`

5. Query investor vault stash `order_stash_index` balance:
   - Must be ZERO. If non-zero → FAIL with error: `"order stash {order_stash_index} has non-zero balance {balance}, expected 0"`

6. Append event log to order request (via marketmgr REST or direct DB access):
   ```json
   {
       "type": "ORDER_REQUEST_EVENT_TYPE_ENUM_BALANCE_VERIFIED",
       "message": "Balance verified: {balance} >= {total_required}",
       "step_name": "cio_verify_balance",
       "details": {
           "stash_0_balance": "...",
           "order_volume": "...",
           "fee_amount": "...",
           "total_required": "...",
           "order_stash_balance": "0"
       }
   }
   ```

**Output**:
```json
{
    "stash_0_balance": "...",
    "order_volume_raw": "...",
    "fee_amount_raw": "...",
    "total_required_raw": "...",
    "crown_executor_iid": "..."
}
```

**Compensation**:
- Append event log: `ORDER_REQUEST_EVENT_TYPE_ENUM_BALANCE_CHECK_FAILED` or compensation event
- No state to reverse (read-only step)

### 6.4 Step 4: `cio_lock_order_volume` (treassvc executor)

**File**: `pkg/daemons/treassvc/trax/executors/create_investor_order/lock_order_volume.go` [NEW]

**Execution**:
1. Extract from previous step outputs:
   - `investor_vault_laser_slot_address`, `cash_token_laser_slot_address`, `treasury_laser_slot_address`
   - `order_stash_index`, `order_volume_raw`, `crown_executor_iid`
   - `exec_runtime_name`, `order_request_iid`

2. Acquire distributed lock:
   ```
   key: "investor_order:{exec_runtime_name}:{investor_vault_laser_slot_address}:{cash_token_laser_slot_address}"
   TTL: 300s, timeout: 120s
   ```

3. Query pre-transfer balances:
   - Liquid (stash 0) balance → `liquidBefore`
   - Total (stash 1) balance → `totalBefore`

4. Execute LASER async mutation: `TrezorErc20TransferVaultBalance` (stash-aware)
   - `ledger_id`: 1
   - `caller`: `investor_vault_laser_slot_address`
   - `erc20_addr`: `cash_token_laser_slot_address`
   - `from_vault`: `investor_vault_laser_slot_address`
   - `to_vault`: `investor_vault_laser_slot_address` (SAME vault, different stash)
   - `from_stash`: 0 (LIQUID)
   - `to_stash`: `order_stash_index`
   - `amount`: `order_volume_raw`
   - `data`: `""` (empty)

   **CRITICAL**: Uses `TransferVaultBalance` NOT `TransferFromVault`. The latter has no stash
   parameters and always operates on DEFAULT_LIQUID_STASH(0) and TOTAL_BALANCE_STASH(1),
   making same-vault transfers a no-op. `TransferVaultBalance` correctly handles intra-vault
   stash transfers: when `fromVault == toVault`, TOTAL is NOT modified.

5. Poll LASER mutation for completion (180s timeout, 500ms interval)

6. Release distributed lock

7. **Mandatory post-transfer balance confirmations** (saga FAILS if any check fails):
   - Liquid (stash 0) == `liquidBefore - order_volume_raw`
   - Total (stash 1) == `totalBefore` (unchanged — intra-vault transfer)
   - Order stash (`order_stash_index`) == `order_volume_raw`

8. Append event log to order request:
   ```json
   {
       "type": "ORDER_REQUEST_EVENT_TYPE_ENUM_VOLUME_LOCKED",
       "message": "Order volume locked in stash {order_stash_index} (confirmed)",
       "step_name": "cio_lock_order_volume",
       "details": {
           "tx_hash": "0x...",
           "from_stash": "0",
           "to_stash": "{order_stash_index}",
           "amount_raw": "...",
           "liquid_before": "...",
           "liquid_after": "...",
           "total_unchanged": "...",
           "order_stash_balance": "...",
           "balance_confirmed": "true"
       }
   }
   ```

**Output**:
```json
{
    "volume_lock_tx_hash": "0x...",
    "treasury_lock_keys": ["key1", "key2"]
}
```

**Compensation** (REVERSE TRANSFER):
1. Execute LASER async mutation: `TrezorErc20TransferVaultBalance`
   - `from_vault`: `investor_vault_laser_slot_address`
   - `from_stash`: `order_stash_index`
   - `to_vault`: `investor_vault_laser_slot_address`
   - `to_stash`: 0 (LIQUID)
   - `amount`: `order_volume_raw`
2. Confirm order stash == 0 after compensation
3. Append event log: `ORDER_REQUEST_EVENT_TYPE_ENUM_COMPENSATION_VOLUME_RETURNED`

### 6.5 Step 5: `cio_transfer_fee` (treassvc executor)

**File**: `pkg/daemons/treassvc/trax/executors/create_investor_order/transfer_fee.go` [NEW]

**Execution**:
1. Extract:
   - `investor_vault_laser_slot_address`, `clearing_account_vault_laser_slot_address`
   - `cash_token_laser_slot_address`, `treasury_laser_slot_address`
   - `fee_amount_raw`, `crown_executor_iid`
   - `exec_runtime_name`, `order_request_iid`

2. If `fee_amount_raw` is "0" → skip transfer, append event log noting "zero fee", return success

3. Query pre-transfer balances:
   - Investor liquid (stash 0) → `invLiquidBefore`
   - Investor total (stash 1) → `invTotalBefore`
   - Clearing liquid (stash 0) → `clrLiquidBefore`
   - Clearing total (stash 1) → `clrTotalBefore`

4. Execute LASER async mutation: `TrezorErc20TransferVaultBalance` (stash-aware)
   - `from_vault`: `investor_vault_laser_slot_address`
   - `to_vault`: `clearing_account_vault_laser_slot_address`
   - `from_stash`: 0 (LIQUID)
   - `to_stash`: 0 (LIQUID)
   - `amount`: `fee_amount_raw`

   **NOTE**: Cross-vault transfer — both liquid AND total change for both vaults.

5. Poll LASER mutation for completion

6. **Mandatory post-transfer balance confirmations** (saga FAILS if any check fails):
   - Investor liquid (stash 0) == `invLiquidBefore - fee_amount_raw`
   - Investor total (stash 1) == `invTotalBefore - fee_amount_raw`
   - Clearing liquid (stash 0) == `clrLiquidBefore + fee_amount_raw`
   - Clearing total (stash 1) == `clrTotalBefore + fee_amount_raw`

7. Append event log:
   ```json
   {
       "type": "ORDER_REQUEST_EVENT_TYPE_ENUM_FEE_TRANSFERRED",
       "message": "Fee transferred to clearing account (confirmed)",
       "step_name": "cio_transfer_fee",
       "details": {
           "tx_hash": "0x...",
           "from_vault": "...",
           "to_vault": "...",
           "amount_raw": "...",
           "inv_liquid_before": "...",
           "inv_liquid_after": "...",
           "clr_liquid_before": "...",
           "clr_liquid_after": "...",
           "balance_confirmed": "true"
       }
   }
   ```

**Output**:
```json
{
    "fee_transfer_tx_hash": "0x..."
}
```

**Compensation** (REVERSE TRANSFER):
1. If `fee_amount_raw` was "0" → no-op
2. Execute LASER async mutation: `TrezorErc20TransferVaultBalance`
   - `from_vault`: `clearing_account_vault_laser_slot_address`
   - `from_stash`: 0
   - `to_vault`: `investor_vault_laser_slot_address`
   - `to_stash`: 0
   - `amount`: `fee_amount_raw`
3. Append event log: `ORDER_REQUEST_EVENT_TYPE_ENUM_COMPENSATION_FEE_RETURNED`

### 6.6 Step 6: `cio_submit_to_fix` (marketmgr executor)

**File**: `pkg/daemons/marketmgr/trax/executors/create_investor_order/submit_to_fix.go` [NEW]

**Execution**:
1. Extract:
   - `security_listing_iid`, `side`, `order_type`, `quantity`, `price`
   - `time_in_force`, `currency`, `participant_order_id`
   - `investor_account_iid`, `removed`
   - `order_request_iid`

2. Resolve venue from security_listing_iid:
   - Use existing `LookupVenueByListingIid()` from `listing_venue_resolver.go`
   - This queries Redis: `mktmgr:seclist:venue:{security_listing_iid}`
   - If cache miss, trigger `refreshAllVenueMappings()` (same as current `/orders/by-listing` endpoint)

3. Build fixclient NOS request body:
   ```json
   {
       "cl_ord_id": "{participant_order_id}",
       "symbol": "{mapping.Symbol}",
       "currency": "{mapping.Currency}",
       "side": "{side}",
       "order_type": "{order_type}",
       "quantity": "{quantity}",
       "price": "{price}",
       "time_in_force": "{time_in_force}",
       "participant_iid": "{removed}",
       "investor_iid": "{investor_account_iid}",
       "handl_inst": "1"
   }
   ```

4. POST to fixclient: `{fixClientBaseURL}/api/v1/venues/{venue_iid}/orders`
   - Expect 202 Accepted
   - If non-202 → FAIL with error (triggers compensation)

5. Parse fixclient response:
   ```json
   {
       "request_id": "...",
       "venue_iid": "...",
       "cl_ord_id": "...",
       "fix_version": "...",
       "sent_at": "..."
   }
   ```

6. Update order request record:
   - Set `fix_request_id`, `fix_venue_iid`, `fix_cl_ord_id`, `fix_version`, `fix_sent_at`
   - Set status to `ORDER_REQUEST_STATUS_ENUM_SUBMITTED`

7. Append event log:
   ```json
   {
       "type": "ORDER_REQUEST_EVENT_TYPE_ENUM_SUBMITTED_TO_FIX",
       "message": "Order submitted to FIX venue {venue_iid}",
       "step_name": "cio_submit_to_fix",
       "details": {
           "fix_request_id": "...",
           "venue_iid": "...",
           "cl_ord_id": "...",
           "fix_version": "...",
           "sent_at": "..."
       }
   }
   ```

**Output**:
```json
{
    "fix_request_id": "...",
    "fix_venue_iid": "...",
    "fix_cl_ord_id": "...",
    "fix_version": "...",
    "fix_sent_at": "..."
}
```

**Compensation**:
1. Append event log: `ORDER_REQUEST_EVENT_TYPE_ENUM_FIX_SUBMISSION_FAILED`
2. Update order request status to `ORDER_REQUEST_STATUS_ENUM_REJECTED`
3. Note: Cannot un-send a FIX NOS that was already sent. If 202 was received but saga compensates due to downstream issues, the FIX order may still be active on the venue. This is logged for manual resolution.

---

## Phase 7: Compensation Logic Summary

| Step | Compensation Action | Event Log |
|------|-------------------|-----------|
| 6 | Log failure, set status=REJECTED | `FIX_SUBMISSION_FAILED` |
| 5 | Reverse fee transfer (clearing→investor vault stash 0) | `COMPENSATION_FEE_RETURNED` |
| 4 | Reverse volume transfer (order_stash→investor vault stash 0) | `COMPENSATION_VOLUME_RETURNED` |
| 3 | Log compensation event | Balance check compensation logged |
| 2 | Append compensation events, set status=COMPENSATED | `COMPENSATION_STARTED`, `COMPENSATION_COMPLETED` |
| 1 | No-op | — |

**Critical**: Each compensation step MUST append to the order request's `event_logs` JSONB. The order request record is NEVER deleted — it serves as an audit trail.

### Compensation Input Enrichment

Each compensation handler receives **enriched input** (not just the original saga input):

1. **Layer 1 — Saga Input**: Original saga submission parameters (`account_iid`, `quantity`, etc.)
2. **Layer 2 — Forward Execution Results**: `Result` from all steps up to the current step. This means Step 2's compensation reliably receives `order_request_iid` (from Step 2's own forward `Result`) without needing it in the saga input.
3. **Layer 3 — Compensation Results**: `CompensationResult` from already-compensated steps (later in sequence). For example, Step 4's compensation can see Step 6's compensation output.

Forward `Result` is stored in `result_data` and is **never overwritten** during compensation. Compensation output is stored separately in `compensation_result_data`.

Each step also receives a `CompensationReason` string (from the failed step's error) explaining why compensation was triggered, available via `SagaStepInstance.CompensationReason`.

---

## Phase 8: PrtAgent gRPC Handler Update

### 8.1 Replace HTTP Relay with Saga Submission

**File**: `pkg/daemons/prtagent/impl/v1/grpc/trading.go` [MODIFY]

Replace the current `CreateOrderAsync()` implementation (lines ~225-449) that does HTTP relay to `POST /orders/by-listing` with TRAX saga submission:

```go
func (s *TradingServer) CreateOrderAsync(ctx context.Context, req *prtagentapiv1.CreateOrderAsyncRequest) (*grpccommon.ExecutionAsyncResponse, error) {
    // ... existing validation (keep) ...
    // ... add new validation for currency, fee_amount ...

    // Get participant IID from auth context
    participantIid, ok := auth.GetParticipantIIDFromContext(ctx)
    // ... existing auth check (keep) ...

    // Build saga input
    sagaInput := map[string]string{
        "security_listing_iid":  req.SecurityListingIid,
        "participant_order_id": req.ParticipantOrderId,
        "account_iid":           req.AccountIid,
        "side":                  sideStr,
        "order_type":            req.OrderType,
        "quantity":              req.Quantity,
        "price":                 req.Price,
        "currency":              req.Currency,
        "fee_amount":            req.FeeAmount,
        "time_in_force":         timeInForce,
        "participant_iid":       participantIid,
        "fee_payer_account_iid": req.FeePayerAccountIid,
        "csd_account_iid":       req.CsdAccountIid,
        "proposed_execution_id": req.ProposedExecutionId,
        "exec_runtime_name":     os.Getenv("EXEC_RUNTIME_NAME"),
    }

    // Submit saga
    clusterId := s.traxSubmitter.GetDefaultClusterId()
    traceId := common.SecureRandomString(32)
    originKey := fmt.Sprintf("cio_%s_%s", participantIid, req.ParticipantOrderId)

    sagaInstanceId, err := s.traxSubmitter.SubmitSaga(
        ctx,
        participantIid,     // participantId
        traceId,            // traceId
        "PRTAGENT_ZONE",    // zoneId
        "prtagent_grpc",    // origin
        originKey,          // origKey (idempotency)
        participantIid,     // issuer
        "",                 // referrer
        []string{"investor_order"}, // tags
        nil,                // metadata
        "create_investor_order", // templateId
        sagaInput,
    )
    if err != nil {
        return &grpccommon.ExecutionAsyncResponse{
            AsyncStatus: grpccommon.AsyncResponseStatusEnum_ASYNC_RESPONSE_STATUS_ENUM_INTERNAL_SERVER_ERROR,
            Msg:         fmt.Sprintf("failed to submit order saga: %v", err),
        }, nil
    }

    return &grpccommon.ExecutionAsyncResponse{
        Id:             common.SecureRandomString(16),
        RefExecutionId: req.ProposedExecutionId,
        AsyncStatus:    grpccommon.AsyncResponseStatusEnum_ASYNC_RESPONSE_STATUS_ENUM_ACCEPTED,
        Msg:            "Order saga submitted",
        AsyncResponseData: map[string]string{
            "saga_instance_id": sagaInstanceId,
            "trace_id":         traceId,
        },
    }, nil
}
```

### 8.2 Remove Old Relay Code

Remove from `trading.go`:
- The HTTP POST to `s.marketMgrBaseURL + "/orders/by-listing"` (lines ~345-448)
- The marketmgr response parsing logic

Keep:
- `resolveInvestorAccountIid()` — this may still be needed by other flows, but for the saga, step 1 will handle resolution. Consider whether to keep as a shared utility or remove.
- `resolveremoved()` — same consideration

**Decision**: Keep both resolve functions as package-level utilities, refactor into a shared helper file if needed. Step 1 executor will reuse the same resolution logic.

---

## Phase 9: Remove Marketmgr `/orders/by-listing` Endpoint

### 9.1 Remove the Endpoint

**File**: `pkg/daemons/marketmgr/api/v1/orders_post_send_by_listing.go` [DELETE or REMOVE handler]
**File**: `pkg/daemons/marketmgr/api/v1/api.go` [MODIFY]

Remove the route registration:
```go
// REMOVE this line:
// v1.POST("/orders/by-listing", postSendOrderByListing(store, ...))
```

**Note**: Keep `POST /venues/:venue_iid/orders` (direct venue relay) — this is used by fixreceiver's NOS→saga path and other internal flows. Only remove the listing-based relay that prtagent was calling.

### 9.2 Verify No Other Callers

Search codebase for `/orders/by-listing` to ensure no other services call this endpoint:
- `prtagent/impl/v1/grpc/trading.go` — this is the primary caller (being replaced)
- Check e2e tests — update any tests that use this endpoint

---

## Phase 10: TRAX Saga Template SQL

### 10.1 Register Saga Template

**File**: `deploy/k8s/init/csd/min/trax.sql` [MODIFY]

```sql
-- create_investor_order saga template
INSERT INTO saga_templates (template_id, display_name, description, version, is_enabled, created_at, updated_at)
VALUES ('create_investor_order', 'Create Investor Order', 'Creates an investor order via prtagent with balance verification, cash-token locking, and FIX venue submission', '1.0', true, NOW(), NOW())
ON CONFLICT (template_id) DO NOTHING;

-- Step 1: Validate inputs (prtagent executor)
INSERT INTO saga_step_templates (template_id, saga_template_id, step_order, display_name, description, is_compensatable, created_at, updated_at)
VALUES ('cio_validate_inputs', 'create_investor_order', 1, 'Validate Inputs', 'Validates all input parameters and resolves legal structure addresses', false, NOW(), NOW())
ON CONFLICT (template_id) DO NOTHING;

-- Step 2: Create order request (marketmgr executor)
INSERT INTO saga_step_templates (template_id, saga_template_id, step_order, display_name, description, is_compensatable, created_at, updated_at)
VALUES ('cio_create_order_request', 'create_investor_order', 2, 'Create Order Request', 'Creates order request record with initial event log', true, NOW(), NOW())
ON CONFLICT (template_id) DO NOTHING;

-- Step 3: Verify balance (treassvc executor)
INSERT INTO saga_step_templates (template_id, saga_template_id, step_order, display_name, description, is_compensatable, created_at, updated_at)
VALUES ('cio_verify_balance', 'create_investor_order', 3, 'Verify Balance', 'Verifies investor vault has sufficient balance for order volume plus fee', true, NOW(), NOW())
ON CONFLICT (template_id) DO NOTHING;

-- Step 4: Lock order volume (treassvc executor)
INSERT INTO saga_step_templates (template_id, saga_template_id, step_order, display_name, description, is_compensatable, created_at, updated_at)
VALUES ('cio_lock_order_volume', 'create_investor_order', 4, 'Lock Order Volume', 'Transfers cash tokens from stash 0 to order stash on investor vault', true, NOW(), NOW())
ON CONFLICT (template_id) DO NOTHING;

-- Step 5: Transfer fee (treassvc executor)
INSERT INTO saga_step_templates (template_id, saga_template_id, step_order, display_name, description, is_compensatable, created_at, updated_at)
VALUES ('cio_transfer_fee', 'create_investor_order', 5, 'Transfer Fee', 'Transfers fee from investor vault stash 0 to clearing account vault stash 0', true, NOW(), NOW())
ON CONFLICT (template_id) DO NOTHING;

-- Step 6: Submit to FIX (marketmgr executor)
INSERT INTO saga_step_templates (template_id, saga_template_id, step_order, display_name, description, is_compensatable, created_at, updated_at)
VALUES ('cio_submit_to_fix', 'create_investor_order', 6, 'Submit to FIX', 'Resolves venue and submits order to fixclient for FIX transmission', true, NOW(), NOW())
ON CONFLICT (template_id) DO NOTHING;
```

---

## Phase 11: E2E Tests

### 11.1 Test Category Assignment

**Category**: 36 — `laser-e2e-ethbc-cat36`
**Complexity**: ⭐⭐⭐⭐ HIGH
**Mode**: EthBC (requires Anvil blockchain for treasury operations)

**File**: `Makefile` [MODIFY]

```makefile
E2E_CAT36_PATTERN := TestCreateInvestorOrder
laser-e2e-ethbc-cat36:
	$(call run-laser-e2e-ethbc,$(E2E_CAT36_PATTERN))
```

### 11.2 Test File

**File**: `tests/e2e/laser/create_investor_order_test.go` [NEW]

### 11.3 Test Infrastructure Setup

Each test requires:
1. Test database setup (marketmgr schema with order_requests table)
2. Legal participant fully deployed (PLEGP) with:
   - Legal structure
   - Clearing account
   - Cash token mechanism (matching test currency, e.g., "EUR")
   - Treasury mechanisms (Trezor diamond)
3. Investor onboarded with holding vault
4. Investor account funded with cash tokens
5. Security listing deployed with FIX venue connection
6. Redis listing→venue mapping populated

**Helper Functions to Implement**:

```go
func setupTestDatabaseForCreateInvestorOrder(t *testing.T) string
// Creates test DB with: shared, marketmgr (with order_requests), fixclient, listingmgr schemas

func submitCreateInvestorOrder(t *testing.T, baseURL string, input map[string]string) string
// Submits create_investor_order saga via prtagent gRPC or traxctrl API, returns sagaInstanceId

func waitForCIOSagaCompletion(t *testing.T, sagaInstanceId string, timeout time.Duration) *watch.WatchResult
// Polls traxctrl for saga completion

func getOrderRequestByIid(t *testing.T, baseURL string, iid string) map[string]interface{}
// GET /api/v1/order-requests/:iid from marketmgr

func getOrderRequestBySagaId(t *testing.T, baseURL string, sagaInstanceId string) map[string]interface{}
// GET /api/v1/order-requests/by-saga/:sagaInstanceId from marketmgr

func verifyOrderRequestEventLogs(t *testing.T, orderRequest map[string]interface{}, expectedTypes []string)
// Verifies event_logs JSONB contains expected event types in order

func queryInvestorVaultBalance(t *testing.T, vaultAddress string, stashId int64, erc20Address string) string
// Queries LASER for vault balance at specific stash
```

### 11.4 Green Path Tests

```go
// Infrastructure setup (shared across tests)
func TestCreateInvestorOrder_Infrastructure(t *testing.T) {
    // Verify PLEGP, cash token, security listing, FIX venue all set up
}

// Basic green path: LIMIT BUY order
func TestCreateInvestorOrder_LimitBuy_GreenPath(t *testing.T) {
    // 1. Fund investor account with enough cash tokens
    // 2. Submit create_investor_order saga with LIMIT BUY
    // 3. Wait for saga COMMITTED
    // 4. Verify order request record created with status=SUBMITTED
    // 5. Verify event_logs contains: CREATED, VERIFIED, LOCKED, FEE_TRANSFERRED, SUBMITTED_TO_FIX
    // 6. Verify investor vault stash 0 balance decreased by (volume + fee)
    // 7. Verify investor vault stash order_stash_index balance = volume
    // 8. Verify clearing account vault stash 0 balance increased by fee
    // 9. Verify fixclient received the NOS (check sent_orders table)
}

// LIMIT SELL order
func TestCreateInvestorOrder_LimitSell_GreenPath(t *testing.T) {
    // Same as BUY but with SELL side
}

// MARKET BUY order (price=0)
func TestCreateInvestorOrder_MarketBuy_GreenPath(t *testing.T) {
    // Market order with price=0
}

// Zero fee order
func TestCreateInvestorOrder_ZeroFee_GreenPath(t *testing.T) {
    // Order with fee_amount=0, step 5 should skip transfer
}

// Verify event logs content and ordering
func TestCreateInvestorOrder_EventLogsVerification(t *testing.T) {
    // Submit order, verify all 5 event log entries in correct order
    // Verify each event has: id, type, message, step_name, saga_instance_id, timestamp, details
}

// REST query endpoints
func TestCreateInvestorOrder_RESTQueryEndpoints(t *testing.T) {
    // Verify: list, get by IID, get by participant_order_id, get by saga_instance_id
}

// Multiple orders from same investor
func TestCreateInvestorOrder_MultipleOrders_SameInvestor(t *testing.T) {
    // Submit 2 orders sequentially from same investor
    // Verify both complete, different stash indexes, correct balances
}
```

### 11.5 Red Path Tests

```go
// Missing required fields
func TestCreateInvestorOrder_MissingSecurityListingIid(t *testing.T) {
    // Submit with empty security_listing_iid → saga fails at step 1
}

func TestCreateInvestorOrder_MissingCurrency(t *testing.T) {
    // Submit with empty currency → saga fails at step 1
}

func TestCreateInvestorOrder_InvalidCurrencyLength(t *testing.T) {
    // Submit with currency="EURO" (4 chars) → saga fails at step 1
}

func TestCreateInvestorOrder_InvalidSide(t *testing.T) {
    // Submit with side="HOLD" → saga fails at step 1
}

func TestCreateInvestorOrder_InvalidOrderType(t *testing.T) {
    // Submit with order_type="STOP" → saga fails at step 1
}

func TestCreateInvestorOrder_ZeroQuantity(t *testing.T) {
    // Submit with quantity="0" → saga fails at step 1
}

func TestCreateInvestorOrder_MarketOrderWithPrice(t *testing.T) {
    // Submit MARKET order with price="25.50" → saga fails at step 1
}

// Insufficient balance → compensation
func TestCreateInvestorOrder_InsufficientBalance_Compensation(t *testing.T) {
    // 1. Fund investor with 100 tokens
    // 2. Submit order for 200 tokens → step 3 fails
    // 3. Wait for saga COMPENSATED
    // 4. Verify order request status=COMPENSATED
    // 5. Verify event_logs contains: CREATED, BALANCE_CHECK_FAILED, COMPENSATION_STARTED, COMPENSATION_COMPLETED
    // 6. Verify no tokens were moved (stash 0 unchanged, order stash still 0)
}

// Non-zero order stash → fail
func TestCreateInvestorOrder_NonZeroOrderStash(t *testing.T) {
    // Pre-populate the target stash with tokens
    // Submit order → step 3 fails because stash has non-zero balance
    // Verify compensation
}

// Currency not matching any cash token mechanism
func TestCreateInvestorOrder_UnknownCurrency_Compensation(t *testing.T) {
    // Submit order with currency="JPY" when participant only has EUR cash token
    // Step 1 fails → no order request created
}

// Volume lock failure → compensation with fee not yet transferred
func TestCreateInvestorOrder_VolumeLockFails_Compensation(t *testing.T) {
    // Simulate step 4 failure
    // Verify compensation: step 3 compensated (no-op), step 2 compensated (event log added)
}

// Fee transfer failure → compensation with volume returned
func TestCreateInvestorOrder_FeeTransferFails_Compensation(t *testing.T) {
    // Step 5 fails → compensation reverses step 4 (volume returned)
    // Verify investor vault stash 0 balance restored
    // Verify order stash balance back to 0
    // Verify event_logs contains COMPENSATION_VOLUME_RETURNED
}

// FIX submission failure → full compensation
func TestCreateInvestorOrder_FixSubmissionFails_FullCompensation(t *testing.T) {
    // Step 6 fails (e.g., venue not connected)
    // Full compensation: fee returned, volume returned
    // Verify all balances restored
    // Verify event_logs contains all compensation events
}
```

### 11.6 Docker Compose Updates

**File**: `tests/e2e/laser/docker-compose.yaml` [MODIFY]

Ensure marketmgr service has:
- `TRAX_CLUSTER_ID` environment variable
- `RABBITMQ_CONN_STRING` environment variable
- PostgreSQL connection for order_requests table

Ensure prtagent service (if present in e2e) has:
- `TRAX_CLUSTER_ID` environment variable
- TRAX executor infrastructure

### 11.7 Makefile Updates

**File**: `Makefile` [MODIFY]

Add new pattern:
```makefile
E2E_CAT36_PATTERN := TestCreateInvestorOrder

laser-e2e-ethbc-cat36:
	$(call run-laser-e2e-ethbc,$(E2E_CAT36_PATTERN))
```

Add to aggregate targets if applicable.

---

## Phase 12: Documentation

### 12.1 Order Lifecycle Document

**File**: `docs/INVESTOR_ORDER_LIFECYCLE.md` [NEW]

See separate file — this documents the complete order lifecycle from gRPC call to FIX submission, including all states, transitions, and compensation paths.

### 12.2 Update SUMMARY-FOR-AGENT.md

**File**: `docs/SUMMARY-FOR-AGENT.md` [MODIFY]

Add a new section after the existing saga documentation:

```markdown
### Create Investor Order Saga (`create_investor_order`)
- 6 steps across prtagent (1), marketmgr (2,6), treassvc (3,4,5)
- Replaces HTTP relay in prtagent CreateOrderAsync
- Creates marketmgr.order_requests record with JSONB event_logs
- Locks order volume in dedicated stash, transfers fee to clearing account
- Submits to FIX venue via fixclient REST API
- Full compensation path: reverse transfers + audit trail
- See: docs/TODO_CREATE_INVESTOR_ORDER_SAGA.md, docs/INVESTOR_ORDER_LIFECYCLE.md
```

### 12.3 Update E2E Test Catalog

**File**: `docs/E2E_TEST_CATALOG.md` [MODIFY]

Add new group:

```markdown
## Group 36: Create Investor Order Saga Tests

**Category**: 36 | **Complexity**: ⭐⭐⭐⭐ HIGH | **Mode**: EthBC
**Makefile Target**: `laser-e2e-ethbc-cat36`
**Pattern**: `TestCreateInvestorOrder`
**File**: `tests/e2e/laser/create_investor_order_test.go`

Tests the `create_investor_order` TRAX saga that creates investor orders via prtagent with
balance verification, cash-token locking in dedicated stash, fee transfer, and FIX venue submission.

### Green Path Tests
| Test | Description |
|------|-------------|
| TestCreateInvestorOrder_Infrastructure | Verify PLEGP, cash token, security listing, FIX venue setup |
| TestCreateInvestorOrder_LimitBuy_GreenPath | Full LIMIT BUY order with balance verification |
| TestCreateInvestorOrder_LimitSell_GreenPath | Full LIMIT SELL order |
| TestCreateInvestorOrder_MarketBuy_GreenPath | MARKET BUY: lock side fetches live best ask via marketmgr `/orderbook?mode=l1`, applies `TREASSVC_MARKET_BUY_SLIPPAGE_BPS` (default 1000 = 10%), locks the resulting notional. `price` from prtagent stays "0" on the wire — the lock notional comes from price discovery. |
| TestCreateInvestorOrder_ZeroFee_GreenPath | Order with zero fee (step 5 skip) |
| TestCreateInvestorOrder_EventLogsVerification | Verify all 5 event logs in order |
| TestCreateInvestorOrder_RESTQueryEndpoints | List, get by IID, by participant order, by saga |
| TestCreateInvestorOrder_MultipleOrders_SameInvestor | Sequential orders from same investor |

### Red Path Tests
| Test | Description |
|------|-------------|
| TestCreateInvestorOrder_MissingSecurityListingIid | Validation failure |
| TestCreateInvestorOrder_MissingCurrency | Validation failure |
| TestCreateInvestorOrder_InvalidCurrencyLength | Validation failure |
| TestCreateInvestorOrder_InvalidSide | Validation failure |
| TestCreateInvestorOrder_InvalidOrderType | Validation failure |
| TestCreateInvestorOrder_ZeroQuantity | Validation failure |
| TestCreateInvestorOrder_MarketOrderWithPrice | Validation failure |
| TestCreateInvestorOrder_InsufficientBalance_Compensation | Step 3 fails, saga compensates |
| TestCreateInvestorOrder_NonZeroOrderStash | Step 3 fails, stash not empty |
| TestCreateInvestorOrder_UnknownCurrency_Compensation | Step 1 fails, no matching cash token |
| TestCreateInvestorOrder_FeeTransferFails_Compensation | Step 5 fails, volume returned |
| TestCreateInvestorOrder_FixSubmissionFails_FullCompensation | Step 6 fails, full rollback |
```

### 12.4 Update TODO.md

**File**: `docs/TODO.md` [MODIFY]

Add entry:

```markdown
- [ ] **Create Investor Order Saga**: TRAX saga for creating investor orders via prtagent with balance verification, cash-token locking, fee transfer, and FIX venue submission. Full specification in `docs/TODO_CREATE_INVESTOR_ORDER_SAGA.md`. Lifecycle doc: `docs/INVESTOR_ORDER_LIFECYCLE.md`.
```

---

## Phase 13: Update Existing Tests

### 13.1 Existing E2E Tests Using `/orders/by-listing`

**File**: `tests/e2e/laser/marketmgr_order_relay_test.go` [MODIFY]

Since `POST /orders/by-listing` is being removed from marketmgr, tests that use `marketmgrSendNOSByListing()` need to be updated:

- [ ] 13.1.1 Review `TestMarketMgrRelay_ByListing` — this test verifies listing-based relay. Since the endpoint is removed, this test should be:
  - **Option A**: Remove entirely (the functionality is now in the saga)
  - **Option B**: Convert to test the saga path instead
  - **Recommended**: Remove the by-listing test, keep direct venue relay tests. The saga E2E tests (Phase 11) cover the new flow.

- [ ] 13.1.2 Keep `TestMarketMgrRelay_DirectNOS_*` tests — these use `POST /venues/:venue_iid/orders` which is NOT being removed.

### 13.2 Existing Trading Mechanism Tests

**File**: `tests/e2e/laser/trading_mechanism_deployment_test.go` [REVIEW]

No changes expected — this tests trading mechanism deployment, not order creation.

### 13.3 Existing FIX NOS Tests

**Files**: `tests/e2e/laser/fix_neworder_saga_test.go`, `fixclient_nos_test.go` [REVIEW]

These test the FIX→saga path (fixreceiver → create_direct_order). They are NOT affected by this change since they don't go through prtagent or `/orders/by-listing`.

---

## Verification Checklist

After implementation, verify:

- [ ] `make gen-proto` succeeds with new proto fields
- [ ] `make build` succeeds
- [ ] `make test` — unit tests pass
- [ ] `make bip` — images build and push
- [ ] Database schema applies cleanly on fresh PostgreSQL
- [ ] Saga template SQL inserts correctly
- [ ] Green path: order creates, volume locked, fee transferred, FIX submitted
- [ ] Red path: insufficient balance triggers compensation, all transfers reversed
- [ ] Event logs: all steps append to JSONB, compensation events present
- [ ] REST endpoints: list, get by IID, by participant order, by saga instance
- [ ] E2E tests: `make laser-e2e-ethbc-cat36` passes
- [ ] No regression: `make laser-e2e-ethbc-cat31` through `cat35` still pass (existing order tests)
- [ ] Lifecycle doc: `docs/INVESTOR_ORDER_LIFECYCLE.md` matches implementation
- [ ] SUMMARY-FOR-AGENT.md: updated with saga info
- [ ] E2E_TEST_CATALOG.md: category 36 documented
- [ ] TODO.md: entry added

---

## Key File Paths Reference

### New Files
| File | Purpose |
|------|---------|
| `pkg/fin/order_request_event.go` | OrderRequestEventTypeEnum, OrderRequestEventLog |
| `pkg/fin/order_request.go` | OrderRequestStatusEnum, OrderRequest struct |
| `pkg/fin/trading_enums.go` | Consolidated trading enums (TimeInForce, ExecutionType) |
| `pkg/daemons/marketmgr/order_request_store.go` | Store interface |
| `pkg/daemons/marketmgr/order_request_store_psql.go` | PostgreSQL implementation |
| `pkg/daemons/marketmgr/order_request_store_inmem.go` | In-memory implementation |
| `pkg/daemons/marketmgr/api/v1/order_requests_get.go` | REST list endpoint |
| `pkg/daemons/marketmgr/api/v1/order_requests_get_by_id.go` | REST get-by-id endpoint |
| `pkg/daemons/prtagent/trax/executors/run.go` | Prtagent executor runner |
| `pkg/daemons/prtagent/trax/executors/create_investor_order/validate_inputs.go` | Step 1 |
| `pkg/daemons/marketmgr/trax/executors/run.go` | Marketmgr executor runner |
| `pkg/daemons/marketmgr/trax/executors/create_investor_order/create_order_request.go` | Step 2 |
| `pkg/daemons/marketmgr/trax/executors/create_investor_order/submit_to_fix.go` | Step 6 |
| `pkg/daemons/treassvc/trax/executors/create_investor_order/verify_balance.go` | Step 3 |
| `pkg/daemons/treassvc/trax/executors/create_investor_order/lock_order_volume.go` | Step 4 |
| `pkg/daemons/treassvc/trax/executors/create_investor_order/transfer_fee.go` | Step 5 |
| `tests/e2e/laser/create_investor_order_test.go` | E2E tests |
| `docs/INVESTOR_ORDER_LIFECYCLE.md` | Lifecycle documentation |
| `docs/TODO_CREATE_INVESTOR_ORDER_SAGA.md` | This TODO document |

### Modified Files
| File | Change |
|------|--------|
| `deploy/k8s/init/init_marketmgr_pgsql.sql` | Add order_requests table |
| `deploy/k8s/init/csd/min/trax.sql` | Add saga template + 6 step templates |
| `deploy/k8s/init/csd/min/marketmgr.sql` | Add sample order request records |
| `data/api/grpc/prtagent/v1/trading.proto` | Add currency, fee_amount fields |
| `pkg/daemons/prtagent/impl/v1/grpc/trading.go` | Replace HTTP relay with saga submission |
| `pkg/daemons/prtagent.go` | Add TRAX executor infrastructure |
| `pkg/daemons/marketmgr.go` | Add TRAX executor infrastructure |
| `pkg/daemons/marketmgr/api/v1/api.go` | Add order request routes, remove /orders/by-listing |
| `pkg/daemons/marketmgr/api/v1/orders_post_send_by_listing.go` | DELETE or empty |
| `pkg/daemons/treassvc/trax/executors/run.go` | Register 3 new step executors |
| `pkg/execpl/consts.go` | Convert enums to fin aliases |
| `tests/e2e/laser/marketmgr_order_relay_test.go` | Remove by-listing tests |
| `tests/e2e/laser/docker-compose.yaml` | Add env vars for marketmgr TRAX |
| `Makefile` | Add cat36 pattern |
| `docs/SUMMARY-FOR-AGENT.md` | Add saga section |
| `docs/E2E_TEST_CATALOG.md` | Add group 36 |
| `docs/TODO.md` | Add entry |

### Existing Files to Reuse (Patterns)
| File | Reuse |
|------|-------|
| `pkg/daemons/treassvc/trax/executors/fund_account_with_cash_tokens/query_source_vault_balance.go` | Vault balance query pattern, distributed lock pattern |
| `pkg/daemons/treassvc/trax/executors/fund_account_with_cash_tokens/transfer_from_clearing_to_destination.go` | TrezorErc20TransferFromVault LASER mutation pattern (cross-vault only) |
| `pkg/daemons/listingmgr/trax/executors/create_direct_order/laser_helpers.go` | LASER mutation submit/poll helpers |
| `pkg/daemons/marketmgr/listing_venue_resolver.go` | Redis venue lookup (LookupVenueByListingIid) |
| `pkg/daemons/marketmgr/api/v1/orders_post_send_by_listing.go` | Venue resolution + fixclient relay pattern (to reuse in step 6) |
| `pkg/daemons/prtagent/impl/v1/grpc/trading.go` | Investor/participant CSD account resolution |
| `pkg/daemons/marketmgr/market_store_psql.go` | PostgreSQL CRUD pattern for new store |
