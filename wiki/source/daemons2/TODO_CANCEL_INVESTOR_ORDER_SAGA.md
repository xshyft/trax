# TODO: Cancel Investor Order - TRAX Saga Implementation

> **Status**: NOT STARTED
> **Created**: 2026-03-17
> **Last Updated**: 2026-03-17
> **Parent Reference**: `create_investor_order` saga (prerequisite: order must be SUBMITTED+ to venue)
> **Related**: cancel_direct_order saga (on-chain cancel), actusvc (handles stash unlock + fee return on CANCELLED ERP)

## Overview

TRAX saga template `cancel_investor_order` that cancels an existing investor order by sending a FIX OrderCancelRequest (MsgType=F) to the venue via fixclient. The saga is triggered by gRPC `CancelOrderAsync` on prtagent, orchestrated across **prtagent** (validation) and **marketmgr** (record update + FIX submission).

**Key architectural points**:
- **Saga owner**: Distributed — prtagent (Step 1) + marketmgr (Steps 2-3)
- **No money transfers**: The saga only sends the FIX cancel. actusvc handles stash unlock + fee return when the venue confirms cancellation via CANCELLED ExecutionReport.
- **SUBMITTED+ only**: Only orders that have been submitted to the FIX venue (status SUBMITTED, ACCEPTED, or PARTIALLY_FILLED) can be cancelled through this saga.
- **gRPC entry point**: `CancelOrderAsync` on prtagent TradingService, accepting `external_order_id` (= investor_order_id from creation)
- **Fixclient cancel endpoint**: New `POST /api/v1/venues/:venue_iid/orders/cancel` endpoint (does not exist yet)
- **New DB table**: `fixclient.sent_cancels` for cancel request tracking (separate from sent_orders)

---

## Prerequisites (MUST be validated in Step 1)

1. **Order request exists** in `marketmgr.order_requests` with matching `external_order_id`
2. **Order is in cancellable status**: `Submitted`, `Accepted`, or `PartiallyFilled`
3. **FIX submission data present**: `fix_venue_iid`, `fix_request_id`, `fix_cl_ord_id` must be non-empty (order was actually sent to venue)
4. **Participant owns the order**: The `participant_iid` from auth context must match the order's `participant_iid`

---

## Saga Specification

### Inputs (from gRPC CancelOrderAsync)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `external_order_id` | string | Yes | Investor's order ID (= `external_order_id` in order_requests table) |
| `participant_iid` | string | Yes | From gRPC auth context — must match order's participant_iid |
| `reason` | string | No | Cancellation reason text |
| `proposed_execution_id` | string | No | Client tracking ID |
| `exec_runtime_name` | string | Yes | From prtagent env config (EXEC_RUNTIME_NAME) |

### Outputs

| Field | Type | Description |
|-------|------|-------------|
| `order_request_iid` | string | IID of the order request being cancelled |
| `cancel_cl_ord_id` | string | New ClOrdID generated for the cancel request |
| `fix_cancel_request_id` | string | fixclient request_id for the cancel |
| `saga_instance_id` | string | TRAX saga instance ID |

### Cancellable Status Rules

| Status | Cancellable? | Reason |
|--------|-------------|--------|
| `Submitted` | YES | Cancel can be fired before the venue's ExecutionReport-New — venue is authoritative for the final outcome (Cancelled vs CancelRejected) |
| `Accepted` | YES | Venue acknowledged order (FIX OrdStatus=NEW) |
| `PartiallyFilled` | YES | Order partially filled, remaining can be cancelled |
| `Pending` | NO | Still being processed by create_investor_order saga |
| `Validated` | NO | Still being processed by create_investor_order saga |
| `Verified` | NO | Still being processed by create_investor_order saga |
| `Locked` | NO | Still being processed by create_investor_order saga |
| `FeeCharged` | NO | Still being processed by create_investor_order saga |
| `Filled` | NO | Order fully filled, nothing to cancel |
| `Cancelled` | NO | Already cancelled |
| `Rejected` | NO | Already rejected by venue |
| `Failed` | NO | Saga failed, compensation handled cleanup |
| `CancelSubmissionPending` | NO | Cancel already in progress |
| `CancelSubmitted` | NO | Cancel already sent to venue |
| `CancelPending` | NO | Cancel confirmation pending from venue |

### Saga Steps (3 steps)

| Step | Name | Service | Description |
|------|------|---------|-------------|
| 1 | `cioc_validate_and_resolve` | **prtagent** | Validate external_order_id, query marketmgr for order_request, check cancellable status, extract FIX venue and order details |
| 2 | `cioc_update_order_request` | **marketmgr** | Defensive re-check status, update to CANCEL_SUBMISSION_PENDING, append event log |
| 3 | `cioc_submit_cancel_to_fix` | **marketmgr** | Generate cancel_cl_ord_id, POST to fixclient /venues/{venue_iid}/orders/cancel, update status to CANCEL_SUBMITTED |

**Service Distribution**: prtagent (Step 1) + marketmgr (Steps 2-3).

---

## Data Flow Diagram

```
Investor ──(gRPC CancelOrderAsync)──> prtagent
    │
    ├─ Validate external_order_id non-empty
    ├─ Extract participant_iid from auth context
    ├─ Submit cancel_investor_order saga
    │       │
    │       └─ TRAX Coordinator
    │               │
    │               ├─ Step 1: cioc_validate_and_resolve (prtagent)
    │               │   ├─ GET {marketmgr}/order-requests/by-external-order/{external_order_id}
    │               │   ├─ Validate cancellable status (SUBMITTED/ACCEPTED/PARTIALLY_FILLED)
    │               │   ├─ Validate participant_iid ownership
    │               │   └─ Extract: order_request_iid, participant_order_id, fix_venue_iid,
    │               │              fix_cl_ord_id, symbol, currency, side, quantity,
    │               │              investor_csd_account_iid, participant_csd_account_iid
    │               │
    │               ├─ Step 2: cioc_update_order_request (marketmgr)
    │               │   ├─ Defensive re-check status is still cancellable
    │               │   ├─ Update status → CANCEL_SUBMISSION_PENDING
    │               │   └─ Append CancelSubmissionPending event log
    │               │
    │               └─ Step 3: cioc_submit_cancel_to_fix (marketmgr)
    │                   ├─ Generate cancel_cl_ord_id: "cancel-{participant_order_id}-{millis}"
    │                   ├─ POST {fixclient}/venues/{fix_venue_iid}/orders/cancel
    │                   │   Body: {orig_cl_ord_id, cancel_cl_ord_id, symbol, currency,
    │                   │          side, quantity, csd_participant_account_iid,
    │                   │          csd_investor_subacc_iid, reason}
    │                   ├─ fixclient builds FIX OCR (MsgType=F), persists to sent_cancels,
    │                   │   sends via quickfix.SendToTarget → FIX Venue
    │                   ├─ Update status → CANCEL_SUBMITTED
    │                   └─ Append CancelSubmittedToFix event log
    │
    └─ Return ExecutionAsyncResponse {saga_instance_id, status: ACCEPTED}

    [Later, venue confirms cancel via ExecutionReport]

    FIX Venue ──(ExecutionReport OrdStatus=4 CANCELLED)──> fixclient
        │
        └─ Persists to fixclient.execution_reports
           pg_notify('actusvc_new_erp', request_id)
                │
                v
            actusvc detects CANCELLED ERP
                ├─ Triggers unlock_order_stash saga (stash → liquid)
                ├─ Triggers fee return saga (clearing → investor)
                └─ Updates order_request status → Cancelled
```

---

## Implementation Phases

### Phase 1: Proto and gRPC Changes

**File**: `data/api/grpc/prtagent/v1/trading.proto`

> Note (2026-05-02): `CancelOrder` will be re-exposed on the
> broker-trading-side gateway `brktrdapi` once it ships (see
> `docs/TODO_BRKTRDAPI_AND_BRKADMAPI.md`). Until then this proto is
> the only client-facing entrypoint.

- [ ] 1.1.1 Rename `CancelOrderAsyncRequest.participant_order_id` (field 2) to `external_order_id`
- [ ] 1.1.2 Run `make gen-proto` to regenerate Go code

**File**: `pkg/daemons/prtagent/impl/v1/grpc/trading.go`

- [ ] 1.2.1 Implement `CancelOrderAsync` handler (replace stub at ~line 741):
  1. Validate `req.ExternalOrderId` non-empty → return BAD_REQUEST if missing
  2. Extract `participant_iid` from auth context via `auth.GetParticipantIIDFromContext(ctx)`
  3. Get `exec_runtime_name` from config/env (same as CreateOrderAsync)
  4. Build saga input map:
     ```go
     sagaInput := map[string]string{
         "external_order_id":    req.ExternalOrderId,
         "participant_iid":      participantIid,
         "reason":               req.Reason,
         "proposed_execution_id": req.ProposedExecutionId,
         "exec_runtime_name":    execRuntimeName,
     }
     ```
  5. Submit saga: `s.traxSubmitter.SubmitSaga(ctx, clusterId, traceId, "order-zone", "cancel-order", originIdempotentKey, "prtagent", "", []string{"cancel-investor-order"}, metadata, "cancel_investor_order", sagaInput)`
     - `originIdempotentKey`: `fmt.Sprintf("cioc_%s_%s", participantIid, req.ExternalOrderId)`
  6. Return `ExecutionAsyncResponse` with ACCEPTED status and saga_instance_id

**Pattern from**: `CreateOrderAsync` handler at lines 363-570 of same file

---

### Phase 2: OrderRequest Model Changes

**File**: `pkg/fin/order_request.go`

- [ ] 2.1.1 Add new status enum values after `OrderRequestStatusEnum_Failed` (line 20):
  ```go
  OrderRequestStatusEnum_CancelSubmissionPending OrderRequestStatusEnum = "ORDER_REQUEST_STATUS_ENUM_CANCEL_SUBMISSION_PENDING"
  OrderRequestStatusEnum_CancelSubmitted         OrderRequestStatusEnum = "ORDER_REQUEST_STATUS_ENUM_CANCEL_SUBMITTED"
  OrderRequestStatusEnum_CancelPending           OrderRequestStatusEnum = "ORDER_REQUEST_STATUS_ENUM_CANCEL_PENDING"
  ```

- [ ] 2.1.2 Update `IsCancelled()` to include `CancelSubmitted` and `CancelPending` (or not — these are in-progress, not terminal). Keep as-is since IsCancelled means terminal.

- [ ] 2.1.3 Update `IsTerminal()` if needed — cancel-in-progress states are NOT terminal.

**File**: `pkg/fin/order_request_event.go`

- [ ] 2.2.1 Add new cancel event types after the error events section (line 46):
  ```go
  // Cancel path events (cancel_investor_order saga)
  OrderRequestEventTypeEnum_CancelValidated         OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_CANCEL_VALIDATED"
  OrderRequestEventTypeEnum_CancelSubmissionPending  OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_CANCEL_SUBMISSION_PENDING"
  OrderRequestEventTypeEnum_CancelSubmittedToFix     OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_CANCEL_SUBMITTED_TO_FIX"
  OrderRequestEventTypeEnum_CancelSubmissionFailed   OrderRequestEventTypeEnum = "ORDER_REQUEST_EVENT_TYPE_ENUM_CANCEL_SUBMISSION_FAILED"
  ```

---

### Phase 3: OrderRequest Store Changes

**File**: `pkg/daemons/marketmgr/order_request_store.go`

- [ ] 3.1.1 Add to interface: `GetOrderRequestByExternalOrderId(ctx context.Context, externalOrderId string) (*fin.OrderRequest, error)`

**File**: `pkg/daemons/marketmgr/order_request_store_psql.go`

- [ ] 3.1.2 Implement `GetOrderRequestByExternalOrderId()`:
  ```sql
  SELECT ... FROM marketmgr.order_requests WHERE external_order_id = $1 ORDER BY created_at DESC LIMIT 1
  ```
  Follow the pattern of `GetOrderRequestByParticipantOrderId`.

**File**: `pkg/daemons/marketmgr/order_request_store_inmem.go` (if exists)

- [ ] 3.1.3 Implement `GetOrderRequestByExternalOrderId()` for in-memory store

**File**: `deploy/k8s/init/init_marketmgr_pgsql.sql`

- [ ] 3.1.4 Add index: `CREATE INDEX IF NOT EXISTS idx_order_requests_external_order_id ON marketmgr.order_requests(external_order_id);`

---

### Phase 4: MarketMgr REST Endpoint for Order Lookup

**File**: `pkg/daemons/marketmgr/api/v1/` (new handler file)

- [ ] 4.1.1 Create `order_request_get_by_external_oid.go` with handler:
  ```go
  func getOrderRequestByExternalOrderId(c *gin.Context) {
      externalOrderId := c.Param("external_order_id")
      if externalOrderId == "" {
          c.JSON(400, gin.H{"error": "external_order_id is required"})
          return
      }
      orderReq, err := orderRequestStore.GetOrderRequestByExternalOrderId(ctx, externalOrderId)
      // ... return 200 with order request or 404
  }
  ```

**File**: `pkg/daemons/marketmgr/api/v1/api.go`

- [ ] 4.1.2 Add route: `r.GET(ApiV1UriPrefix+"/order-requests/by-external-order/:external_order_id", getOrderRequestByExternalOrderId)`

---

### Phase 5: Fixclient Cancel Endpoint

#### 5.1 Cancel Request/Response Types

**File**: `pkg/daemons/fixclient/ocr_params.go` (NEW)

- [ ] 5.1.1 Create `OrderCancelRequestParams` struct:
  ```go
  type OrderCancelRequestParams struct {
      OrigClOrdID              string `json:"orig_cl_ord_id" binding:"required"`
      CancelClOrdID            string `json:"cancel_cl_ord_id" binding:"required"`
      Symbol                   string `json:"symbol" binding:"required"`
      Currency                 string `json:"currency"`
      Side                     string `json:"side" binding:"required"`
      Quantity                 string `json:"quantity" binding:"required"`
      CsdParticipantAccountIid string `json:"csd_participant_account_iid"`
      CsdInvestorSubaccIid     string `json:"csd_investor_subacc_iid"`
      Reason                   string `json:"reason"`
      Text                     string `json:"text"`
  }
  ```

- [ ] 5.1.2 Create `OrderCancelResponseParams` struct:
  ```go
  type OrderCancelResponseParams struct {
      RequestID     string `json:"request_id"`
      VenueIid      string `json:"venue_iid"`
      OrigClOrdID   string `json:"orig_cl_ord_id"`
      CancelClOrdID string `json:"cancel_cl_ord_id"`
      FIXVersion    string `json:"fix_version"`
      SentAt        string `json:"sent_at"`
  }
  ```

#### 5.2 OCR FIX Message Builder

**File**: `pkg/daemons/fixclient/ocr_builder.go` (NEW)

- [ ] 5.2.1 Implement `BuildOrderCancelRequest(req *OrderCancelRequestParams, fixVersion string) (quickfix.Messagable, error)`:
  - Supports: v4.2, v4.4, v5.0, v5.0SP1, v5.0SP2
  - Required FIX tags: OrigClOrdID (41), ClOrdID (11), Symbol (55), Side (54), TransactTime (60), OrderQty (38)
  - Optional: Parties group (PartyRole=5 for investor, PartyRole=121 for participant)
  - Uses quickfix generated OCR types: `fix42/ordercancelrequest`, `fix44/ordercancelrequest`, etc.

**Pattern from**: `pkg/daemons/fixclient/nos_builder.go`

#### 5.3 SentCancel Store

**File**: `pkg/daemons/fixclient/stores/` (update store interface and implementation)

- [ ] 5.3.1 Add `SentCancel` struct:
  ```go
  type SentCancel struct {
      Iid              string
      RequestID        string  // unique
      VenueIid         string
      FIXVersion       string
      OrigClOrdID      string
      CancelClOrdID    string
      Symbol           string
      Side             string
      Quantity         string
      Currency         string
      CsdParticipantAccountIid string
      CsdInvestorSubaccIid     string
      Reason           string
      Status           string  // SENT, ACKED, SEND_FAILED
      RawFIXMessage    string
      Metadata         map[string]string
      CreatedAt        time.Time
      UpdatedAt        time.Time
  }
  ```

- [ ] 5.3.2 Add to OrderStore interface:
  ```go
  InsertSentCancel(ctx context.Context, cancel *SentCancel) error
  GetSentCancelByRequestID(ctx context.Context, requestID string) (*SentCancel, error)
  ```

- [ ] 5.3.3 Implement PostgreSQL store methods

#### 5.4 ConnectionManager SendOrderCancelRequest

**File**: `pkg/daemons/fixclient/connection_manager.go`

- [ ] 5.4.1 Add `SendOrderCancelRequest(conn *VenueConnection, req *OrderCancelRequestParams) (string, error)`:
  1. Generate `requestID`: `fmt.Sprintf("ocr-%s-%d", conn.VenueIid, time.Now().UnixNano())`
  2. Build FIX OCR via `BuildOrderCancelRequest(req, conn.FIXVersion)`
  3. Create `SentCancel` record with status "SENT"
  4. Insert via `orderStore.InsertSentCancel()`
  5. Send via `quickfix.SendToTarget(ocr, conn.SessionID)`
  6. On failure: update status to "SEND_FAILED"
  7. Return requestID

**Pattern from**: `SendNewOrderSingle` (lines ~573-651)

#### 5.5 REST Endpoint

**File**: `pkg/daemons/fixclient/api/v1/ocr_post_send.go` (NEW)

- [ ] 5.5.1 Implement `postSendOrderCancelRequest(c *gin.Context)`:
  1. Extract `venue_iid` from URL path
  2. Bind JSON body to `OrderCancelRequestParams`
  3. Validate required fields (orig_cl_ord_id, cancel_cl_ord_id, symbol, side, quantity)
  4. Get venue connection from connection manager
  5. Call `connMgr.SendOrderCancelRequest(conn, &req)`
  6. Return 202 Accepted with `OrderCancelResponseParams`

**Pattern from**: `pkg/daemons/fixclient/api/v1/nos_post_send.go`

**File**: `pkg/daemons/fixclient/api/v1/api.go`

- [ ] 5.5.2 Add route: `r.POST(ApiV1UriPrefix+"/venues/:venue_iid/orders/cancel", postSendOrderCancelRequest)`

---

### Phase 6: Saga Executor — Step 1 (prtagent)

New directory: `pkg/daemons/prtagent/trax/executors/cancel_investor_order/`

#### 6.1 `saga.go`

- [ ] 6.1.1 Create package setup with:
  ```go
  package cancel_investor_order

  const sagaTemplateId = "cancel_investor_order"
  var pkgMarketMgrBaseURL string

  func SetDependencies(marketMgrBaseURL string) {
      pkgMarketMgrBaseURL = marketMgrBaseURL
  }
  func RunStep1Executor(ctx, mqClient, clusterId) { ... }
  ```

#### 6.2 `validate_and_resolve.go`

- [ ] 6.2.1 Implement `cioc_validate_and_resolve` IdempotentService:
  1. Validate required inputs: `external_order_id`, `participant_iid`
  2. Query marketmgr REST: `GET {pkgMarketMgrBaseURL}/order-requests/by-external-order/{external_order_id}`
  3. Parse response to `fin.OrderRequest`
  4. If not found → fail: "order request not found for external_order_id=%s"
  5. Validate ownership: `orderReq.ParticipantIid == input["participant_iid"]` → fail if mismatch
  6. Validate cancellable status:
     - `Submitted`, `Accepted`, `PartiallyFilled` → OK
     - `Pending`, `Validated`, `Verified`, `Locked`, `FeeCharged` → fail: "order still being processed by create_investor_order saga (status=%s)"
     - `Filled` → fail: "order fully filled, cannot cancel"
     - `Cancelled` → fail: "order already cancelled"
     - `Rejected` → fail: "order was rejected"
     - `Failed` → fail: "order creation failed"
     - `CancelSubmissionPending`, `CancelSubmitted`, `CancelPending` → fail: "cancel already in progress (status=%s)"
     - Any other → fail: "order in non-cancellable status: %s"
  7. Validate FIX data present: `fix_venue_iid`, `fix_cl_ord_id` must be non-empty
  8. Output map:
     ```
     order_request_iid, participant_order_id, fix_venue_iid, fix_request_id, fix_cl_ord_id,
     symbol, currency, side, quantity,
     investor_csd_account_iid, participant_csd_account_iid,
     investor_iid, participant_iid,
     previous_status (for compensation),
     validation_status: "success"
     ```

  Compensation: no-op (read-only)

#### 6.3 Wire into prtagent executor run.go

**File**: `pkg/daemons/prtagent/trax/executors/run.go`

- [ ] 6.3.1 Add import for `cancel_investor_order` package
- [ ] 6.3.2 Add `marketMgrBaseURL` parameter to `RunExecutorsAsync` (from `MARKET_MANAGER_BASE_URL` env var)
- [ ] 6.3.3 Call `cancel_investor_order.SetDependencies(marketMgrBaseURL)` + `go cancel_investor_order.RunStep1Executor(ctx, mqClient, clusterId)`
- [ ] 6.3.4 Update the daemon init that calls `RunExecutorsAsync` to pass the new parameter

---

### Phase 7: Saga Executors — Steps 2 & 3 (marketmgr)

New directory: `pkg/daemons/marketmgr/trax/executors/cancel_investor_order/`

#### 7.1 `saga.go`

- [ ] 7.1.1 Create package setup:
  ```go
  package cancel_investor_order

  const sagaTemplateId = "cancel_investor_order"
  var (
      pkgOrderRequestStore marketmgr.OrderRequestStore
      pkgFixClientBaseURL  string
  )
  func SetDependencies(store, fixClientBaseURL) { ... }
  func RunExecutorsAsync(ctx, mqClient, clusterId) {
      go runStep2Executor(...)
      time.Sleep(30ms)
      go runStep3Executor(...)
  }
  ```

#### 7.2 `update_order_request.go` — Step 2

- [ ] 7.2.1 Implement `cioc_update_order_request` IdempotentService:
  1. Read `order_request_iid` from input
  2. Load order request: `pkgOrderRequestStore.GetOrderRequest(ctx, orderRequestIid)`
  3. Defensive re-check: status must still be cancellable (SUBMITTED/ACCEPTED/PARTIALLY_FILLED)
     - If status changed to non-cancellable between Step 1 and Step 2 → fail
  4. Store `previous_status` in result (for compensation)
  5. Update status to `OrderRequestStatusEnum_CancelSubmissionPending`
  6. Append event log: type `CancelSubmissionPending`, step_name `cioc_update_order_request`
  7. Output: `order_request_iid`, `previous_status`

  Compensation:
  - Restore status to `previous_status` from enriched compensation input
    (available via Layer 2: forward execution `Result` from this step, which includes `previous_status`)
  - Append event log: type `CancelSubmissionFailed`, message "Cancel saga compensated, status restored"
  - The `CompensationReason` field on the step instance provides the human-readable reason for why compensation was triggered (extracted from the failed step's error).
  - Note: Forward `Result` is preserved in `result_data` (never overwritten during compensation).
    Compensation output is stored separately in `compensation_result_data`.

#### 7.3 `submit_cancel_to_fix.go` — Step 3

- [ ] 7.3.1 Implement `cioc_submit_cancel_to_fix` IdempotentService:
  1. Extract from input: `fix_venue_iid`, `participant_order_id` (= orig_cl_ord_id for FIX), `symbol`, `currency`, `side`, `quantity`, `investor_csd_account_iid`, `participant_csd_account_iid`, `order_request_iid`, `reason`
  2. Generate `cancel_cl_ord_id`: `fmt.Sprintf("cancel-%s-%d", participantOrderId, time.Now().UnixMilli())`
  3. Build fixclient cancel request body:
     ```go
     cancelReq := map[string]interface{}{
         "orig_cl_ord_id":              participantOrderId,
         "cancel_cl_ord_id":           cancelClOrdId,
         "symbol":                      symbol,
         "currency":                    currency,
         "side":                        side,
         "quantity":                    quantity,
         "csd_participant_account_iid": participantCsdAccountIid,
         "csd_investor_subacc_iid":     investorCsdAccountIid,
         "reason":                      reason,
     }
     ```
  4. POST to `{pkgFixClientBaseURL}/venues/{fix_venue_iid}/orders/cancel`
  5. Expect 202 Accepted response with `{request_id, venue_iid, orig_cl_ord_id, cancel_cl_ord_id, fix_version, sent_at}`
  6. Update order request:
     - Status → `OrderRequestStatusEnum_CancelSubmitted`
     - Append event log: type `CancelSubmittedToFix`, step_name `cioc_submit_cancel_to_fix`, details: `{cancel_cl_ord_id, fix_cancel_request_id, fix_version, sent_at}`
     - Store `cancel_cl_ord_id` in metadata
  7. Output: `fix_cancel_request_id`, `cancel_cl_ord_id`, `fix_version`

  Compensation:
  - Log warning: "FIX cancel request already sent, cannot un-cancel"
  - Append event log: type `CancelSubmissionFailed`, message "Cancel OCR was sent but saga compensated"
  - Update status to `OrderRequestStatusEnum_Failed` (or restore to previous_status)

**Pattern from**: `create_investor_order/submit_to_fix.go`

#### 7.4 Wire into marketmgr executor run.go

**File**: `pkg/daemons/marketmgr/trax/executors/run.go`

- [ ] 7.4.1 Add import for `cancel_investor_order` package
- [ ] 7.4.2 Call `cancel_investor_order.SetDependencies(orderRequestStore, fixClientBaseURL)` + `cancel_investor_order.RunExecutorsAsync(ctx, mqClient, clusterId)`
- [ ] 7.4.3 Add to `UpdateOrderRequestStore()` if it exists (for E2E testing DB switching)

---

### Phase 8: SQL Schema Changes

#### 8.1 Fixclient sent_cancels table

**File**: `deploy/k8s/init/init_fixclient_pgsql.sql`

- [ ] 8.1.1 Add `sent_cancels` table (after `sent_orders` table):
  ```sql
  CREATE TABLE IF NOT EXISTS fixclient.sent_cancels (
      iid VARCHAR PRIMARY KEY,
      request_id VARCHAR UNIQUE NOT NULL,
      venue_iid VARCHAR NOT NULL,
      fix_version VARCHAR NOT NULL DEFAULT '',
      orig_cl_ord_id VARCHAR NOT NULL,
      cancel_cl_ord_id VARCHAR NOT NULL,
      symbol VARCHAR NOT NULL DEFAULT '',
      side VARCHAR NOT NULL DEFAULT '',
      quantity VARCHAR NOT NULL DEFAULT '',
      currency VARCHAR DEFAULT '',
      csd_participant_account_iid VARCHAR DEFAULT '',
      csd_investor_subacc_iid VARCHAR DEFAULT '',
      reason VARCHAR DEFAULT '',
      text VARCHAR DEFAULT '',
      status VARCHAR NOT NULL DEFAULT 'SENT',
      raw_fix_message TEXT DEFAULT '',
      display_names JSONB DEFAULT '{}',
      labels JSONB DEFAULT '{}',
      tags JSONB DEFAULT '[]',
      metadata JSONB DEFAULT '{}',
      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT fk_sent_cancels_entity FOREIGN KEY (iid) REFERENCES shared.entities(iid)
  );

  CREATE INDEX IF NOT EXISTS idx_sent_cancels_request_id ON fixclient.sent_cancels(request_id);
  CREATE INDEX IF NOT EXISTS idx_sent_cancels_orig_cl_ord_id ON fixclient.sent_cancels(orig_cl_ord_id);
  CREATE INDEX IF NOT EXISTS idx_sent_cancels_venue_iid ON fixclient.sent_cancels(venue_iid);
  CREATE INDEX IF NOT EXISTS idx_sent_cancels_created_at ON fixclient.sent_cancels(created_at);
  ```

#### 8.2 MarketMgr index

**File**: `deploy/k8s/init/init_marketmgr_pgsql.sql`

- [ ] 8.2.1 Add index: `CREATE INDEX IF NOT EXISTS idx_order_requests_external_order_id ON marketmgr.order_requests(external_order_id);`

#### 8.3 Saga template SQL

**File**: `deploy/k8s/init/csd/min/trax.sql`

- [ ] 8.3.1 Add `cancel_investor_order` saga template + 3 step templates (after create_investor_order block):
  ```sql
  INSERT INTO trax.saga_templates (template_id, display_name, description, labels, tags, metadata, saga_step_template_ids)
  VALUES (
      'cancel_investor_order',
      'Cancel Investor Order',
      'Cancels an existing investor order by sending FIX OrderCancelRequest to the venue via fixclient. Validates order is cancellable, updates status, and submits cancel to FIX.',
      '{"short_id": "cioc"}'::jsonb,
      '["agora", "csd", "saga", "order", "cancel-investor-order", "trading", "prtagent", "marketmgr", "trax-flow"]'::jsonb,
      '{}'::jsonb,
      '["cioc_validate_and_resolve", "cioc_update_order_request", "cioc_submit_cancel_to_fix"]'::jsonb
  )
  ON CONFLICT (template_id) DO UPDATE SET ...;

  -- Step 1: cioc_validate_and_resolve (service: prtagent, index: 1)
  -- Step 2: cioc_update_order_request (service: marketmgr, index: 2)
  -- Step 3: cioc_submit_cancel_to_fix (service: marketmgr, index: 3)
  ```

**File**: `deploy/k8s/init/prtagent/min/trax.sql`

- [ ] 8.3.2 Add same saga template + step templates

---

### Phase 9: E2E Tests (Category 45)

**File**: `tests/e2e/laser/cancel_investor_order_test.go` (NEW)

#### Test Infrastructure

- [ ] 9.0.1 Define `ciocTestInfra` struct (reuse CIO test infrastructure + cancel-specific fields)
- [ ] 9.0.2 Implement `setupCIOCTestInfrastructure(t, prefix)` — creates investor order via CIO saga, waits for SUBMITTED status
- [ ] 9.0.3 Implement `submitCancelInvestorOrder(t, externalOrderId, participantIid)` — calls gRPC CancelOrderAsync
- [ ] 9.0.4 Implement `verifyCancelledOrderRequest(t, externalOrderId)` — checks status and event logs

#### Green Path Tests

- [ ] 9.1.1 `TestCancelInvestorOrder_SubmittedOrder`:
  1. Create investor order via CIO saga, wait for SUBMITTED
  2. Call CancelOrderAsync with external_order_id
  3. Wait for cancel saga completion
  4. Verify order_request status = CANCEL_SUBMITTED
  5. Verify CancelSubmittedToFix event in event_logs
  6. Verify sent_cancels table has a record

- [ ] 9.1.2 `TestCancelInvestorOrder_AcceptedOrder`:
  - Same but wait for ACCEPTED status (venue acknowledged) before cancelling

- [ ] 9.1.3 `TestCancelInvestorOrder_Idempotent`:
  - Call CancelOrderAsync twice with same external_order_id
  - Second should succeed or be idempotent (same saga_instance_id)

#### Red Path Tests

- [ ] 9.2.1 `TestCancelInvestorOrder_NonExistentOrder`:
  - Cancel with external_order_id that doesn't exist
  - Saga fails at Step 1 with "order request not found"

- [ ] 9.2.2 `TestCancelInvestorOrder_FilledOrder`:
  - Create order, simulate fill (if testable), then cancel
  - Saga fails at Step 1 with "order fully filled"

- [ ] 9.2.3 `TestCancelInvestorOrder_AlreadyCancelled`:
  - Cancel order, then cancel again (different idempotency key)
  - Saga fails at Step 1 with "cancel already in progress" or "already cancelled"

- [ ] 9.2.4 `TestCancelInvestorOrder_MissingFields`:
  - gRPC call with empty external_order_id → BAD_REQUEST

- [ ] 9.2.5 `TestCancelInvestorOrder_PreSubmittedOrder`:
  - Create order but don't wait for SUBMITTED (if testable in pending states)
  - Cancel → saga fails with "order still being processed"

- [ ] 9.2.6 `TestCancelInvestorOrder_WrongParticipant`:
  - Cancel with participant_iid that doesn't own the order
  - Saga fails at Step 1 with ownership mismatch

---

### Phase 10: Makefile & Test Catalog Updates

**File**: `Makefile`

- [ ] 10.1.1 Add `E2E_CAT45_PATTERN := TestCancelInvestorOrder`
- [ ] 10.1.2 Add target `laser-e2e-ethbc-cat45`
- [ ] 10.1.3 Add Cat 45 to `e2e-cat-help` output

**File**: `docs/E2E_TEST_CATALOG.md`

- [ ] 10.2.1 Add Cat 45 entry: `| 45 | ⭐⭐⭐⭐ | Cancel Investor Order | laser-e2e-ethbc-cat45 |`

---

### Phase 11: Documentation Updates

**File**: `docs/SUMMARY-FOR-AGENT.md`

- [ ] 11.1.1 Add entry for `cancel_investor_order` saga

**File**: `docs/TODO.md`

- [ ] 11.2.1 Add entry: `- [ ] **Cancel Investor Order Saga**: TRAX saga for gRPC CancelOrderAsync via cancel_investor_order saga through prtagent + marketmgr (see TODO_CANCEL_INVESTOR_ORDER_SAGA.md)`

**File**: `docs/INVESTOR_ORDER_LIFECYCLE.md`

- [ ] 11.3.1 Add cancel flow section documenting the new status transitions and event types

---

## Critical Files Summary

### New Files
| File | Description |
|------|-------------|
| `pkg/daemons/prtagent/trax/executors/cancel_investor_order/saga.go` | Step 1 package setup |
| `pkg/daemons/prtagent/trax/executors/cancel_investor_order/validate_and_resolve.go` | Step 1: Validate + resolve order |
| `pkg/daemons/marketmgr/trax/executors/cancel_investor_order/saga.go` | Steps 2-3 package setup |
| `pkg/daemons/marketmgr/trax/executors/cancel_investor_order/update_order_request.go` | Step 2: Update status |
| `pkg/daemons/marketmgr/trax/executors/cancel_investor_order/submit_cancel_to_fix.go` | Step 3: Submit FIX OCR |
| `pkg/daemons/fixclient/ocr_params.go` | Cancel request/response types |
| `pkg/daemons/fixclient/ocr_builder.go` | FIX OCR message builder |
| `pkg/daemons/fixclient/api/v1/ocr_post_send.go` | REST endpoint handler |
| `pkg/daemons/marketmgr/api/v1/order_request_get_by_external_oid.go` | Lookup endpoint |
| `tests/e2e/laser/cancel_investor_order_test.go` | E2E tests (Cat 45) |

### Modified Files
| File | Change |
|------|--------|
| `data/api/grpc/prtagent/v1/trading.proto` | Rename field to external_order_id |
| `pkg/daemons/prtagent/impl/v1/grpc/trading.go` | Implement CancelOrderAsync handler |
| `pkg/fin/order_request.go` | Add cancel status enums |
| `pkg/fin/order_request_event.go` | Add cancel event types |
| `pkg/daemons/marketmgr/order_request_store.go` | Add GetByExternalOrderId to interface |
| `pkg/daemons/marketmgr/order_request_store_psql.go` | Implement GetByExternalOrderId |
| `pkg/daemons/fixclient/api/v1/api.go` | Add cancel route |
| `pkg/daemons/fixclient/connection_manager.go` | Add SendOrderCancelRequest |
| `pkg/daemons/prtagent/trax/executors/run.go` | Register cancel executor |
| `pkg/daemons/marketmgr/trax/executors/run.go` | Register cancel executors |
| `deploy/k8s/init/init_fixclient_pgsql.sql` | Add sent_cancels table |
| `deploy/k8s/init/init_marketmgr_pgsql.sql` | Add external_order_id index |
| `deploy/k8s/init/csd/min/trax.sql` | Add saga template + steps |
| `deploy/k8s/init/prtagent/min/trax.sql` | Add saga template + steps |
| `Makefile` | Add E2E_CAT45 |
| `docs/E2E_TEST_CATALOG.md` | Add Cat 45 |
| `docs/TODO.md` | Add reference |
| `docs/SUMMARY-FOR-AGENT.md` | Add entry |
| `docs/INVESTOR_ORDER_LIFECYCLE.md` | Add cancel flow |

### Reference Files (patterns to follow)
| File | What to reuse |
|------|---------------|
| `pkg/daemons/prtagent/impl/v1/grpc/trading.go` (CreateOrderAsync) | gRPC handler pattern |
| `pkg/daemons/prtagent/trax/executors/create_investor_order/validate_inputs.go` | Step 1 validation pattern |
| `pkg/daemons/marketmgr/trax/executors/create_investor_order/create_order_request.go` | Step 2 record update pattern |
| `pkg/daemons/marketmgr/trax/executors/create_investor_order/submit_to_fix.go` | Step 3 FIX submission pattern |
| `pkg/daemons/fixclient/api/v1/nos_post_send.go` | Fixclient REST endpoint pattern |
| `pkg/daemons/fixclient/nos_builder.go` | FIX NOS message builder pattern |
| `pkg/daemons/fixclient/connection_manager.go` (SendNewOrderSingle) | Connection manager send pattern |
| `pkg/daemons/listingmgr/trax/executors/cancel_direct_order/` | Cancel saga executor pattern |
| `tests/e2e/laser/create_direct_order_test.go` | E2E test infrastructure |

---

## Success Criteria

- [ ] gRPC `CancelOrderAsync` accepts `external_order_id` and submits `cancel_investor_order` saga
- [ ] Saga Step 1 validates order exists, is cancellable, and participant owns it
- [ ] Saga Step 2 updates order_request status to CANCEL_SUBMISSION_PENDING
- [ ] Saga Step 3 sends FIX OrderCancelRequest to venue via fixclient
- [ ] Fixclient builds and sends FIX OCR (MsgType=F) to venue connection
- [ ] Cancel request persisted in fixclient.sent_cancels table
- [ ] Order_request status updated to CANCEL_SUBMITTED after FIX submission
- [ ] Event logs appended at each saga step for audit trail
- [ ] Non-cancellable orders fail immediately with descriptive error
- [ ] Missing required fields fail immediately (no fallbacks)
- [ ] Compensation restores status on failure (except after FIX OCR sent)
- [ ] actusvc handles stash unlock + fee return when CANCELLED ERP arrives (NOT this saga's job)
- [ ] All E2E green/red path tests pass in ethbc mode

---

## Notes

- **actusvc coordination**: This saga does NOT unlock stash or return fees. When the venue confirms cancellation (ExecutionReport with OrdStatus=4/CANCELLED), the existing actusvc state machine detects it and triggers `unlock_order_stash` + fee return sagas automatically. This separation keeps the cancel saga simple and avoids duplicate fund handling.
- **Cancel rejection from exchange**: If the exchange rejects the cancel (e.g., for on-chain `cancel_direct_order`), the listingmgr compensation inserts a `CANCEL_REJECTED` ExecutionReport into tradeidxer, which flows back to the FIX client as an ERP with OrdStatus=8/ExecType=CANCEL_REJECTED.
- **Race condition mitigation**: Step 2 does a defensive re-check of status with atomic update (WHERE status IN cancellable_set) to prevent race between Step 1 validation and Step 2 update.
- **Idempotency**: The origin idempotent key `cioc_{participant_iid}_{external_order_id}` prevents duplicate sagas for the same cancel request.
- **FIX message**: The OCR uses `participant_order_id` as `OrigClOrdID` (Tag 41) since that's the ClOrdID that was sent with the original NOS. The `cancel_cl_ord_id` becomes the new ClOrdID (Tag 11).
