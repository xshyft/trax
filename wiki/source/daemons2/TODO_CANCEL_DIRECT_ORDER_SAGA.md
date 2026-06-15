# TODO: Cancel Direct Order - TRAX Saga Implementation

> **Status**: NOT STARTED
> **Created**: 2026-03-17
> **Last Updated**: 2026-03-17
> **Parent Reference**: `create_direct_order` saga (prerequisite: order must exist on-chain)
> **Related**: FIX OrderCancelRequest integration — replaces old execution pipeline OCR path

## Overview

TRAX saga template `cancel_direct_order` that cancels an existing trading order on an Agora Engine trading pair via `cancelExternallyIdentifiedDirectOrder(string externalId)`. The saga is owned by **listingmgr** and orchestrates order validation, on-chain cancel submission via LASER, and off-chain order record update.

**Key architectural points**:
- **Saga owner**: listingmgr (same pattern as `create_direct_order`)
- **Smart contract function**: `cancelExternallyIdentifiedDirectOrder(string externalId)` — V1 facet function, takes only the external identifier
- **Caller/signer**: The PLEGP's exchange clearing account submits the on-chain transaction (same as create_direct_order)
- **FIX delivery**: fixreceiver inserts PENDING_CANCEL exec report immediately; tradeidxer naturally produces the final CANCELED exec report when it indexes the on-chain ORDER_CANCEL event (event type 8)
- **No currency resolution needed**: The saga resolves everything (symbol, currency, exec_runtime_name, security_listing_iid, etc.) from the existing order record in `listingmgr.orders`
- **Fully replaces old execution pipeline OCR path**: Old MQ command → cmdprocessor → cmdbcaster flow is replaced entirely

---

## Prerequisites (MUST be validated in Step 1)

1. **Order exists** in `listingmgr.orders` with matching `external_oid` (= FIX OrigClOrdID)
2. **Order is in cancellable status**: `PendingNew`, `New`, `PartialFill`, or `PendingCancel`
3. **SecurityListingDeployment exists and is active** for the order's `security_listing_iid` + `exec_runtime_name` (both extracted from the order record)
4. **PLEGP configured** — `principal_legal_structure_iid` queryable via accmgr `GET /principal-legal-structure`, with ClearingAccount relation
5. **All required saga inputs** are present and valid

---

## Saga Specification

### Inputs

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `external_oid` | string | Yes | — | OrigClOrdID from FIX OCR — maps to `order.ExternalOid` |
| `cancel_cl_ord_id` | string | Yes | — | New ClOrdID for this cancel request (FIX Tag 11) |
| `csd_participant_account_iid` | string | Yes | — | Participant CSD account (from FIX Parties, PartyRole=121) |
| `csd_investor_subacc_iid` | string | Yes | — | Investor sub-account (from FIX Parties, PartyRole=5) |
| `idempotency_key` | string | Yes | — | Idempotency key for TRAX dedup |
| `trace_id` | string | No | auto-generated | Distributed tracing ID |
| `participant_fix_compid` | string | No | "" | FIX session TargetCompID |
| `data` | string | No | "{}" | JSON with FIX context (side, symbol, transact_time, text, fix_version) |

**NOTE**: `security_listing_iid`, `exec_runtime_name`, `participant_oid`, `symbol`, `currency`, `side`, `quantity`, `price` are NOT saga inputs. They are ALL resolved from the order record in Step 1 via `GetOrderByExternalOid()`.

### Outputs

| Field | Type | Description |
|-------|------|-------------|
| `order_iid` | string | IID of the cancelled order |
| `order_event_iid` | string | IID of the Cancel OrderEvent |
| `cancel_tx_hash` | string | On-chain transaction hash of the cancel |
| `order_status_updated` | string | "true" if order status was updated to CANCELED |
| `saga_instance_id` | string | TRAX saga instance ID |

### Non-Cancellable Status Rules

| Status | Error Message | FIX CxlRejReason Equivalent |
|--------|---------------|------------------------------|
| `Fill` | "order fully filled, cannot cancel" | TOO_LATE_TO_CANCEL (0) |
| `Canceled` | "order already cancelled" | DUPLICATE_CLORDID_RECEIVED (6) |
| `Rejected` | "order was rejected, cannot cancel" | TOO_LATE_TO_CANCEL (0) |
| `Expired` | "order has expired, cannot cancel" | TOO_LATE_TO_CANCEL (0) |
| `DoneForDay` | "order is done for day, cannot cancel" | TOO_LATE_TO_CANCEL (0) |
| `Replaced` | "order was replaced, cancel the replacement" | OTHER (99) |
| `Suspended` | "order is suspended, cannot cancel" | OTHER (99) |

### Saga Steps (3 steps)

| Step | Name | Service | Description |
|------|------|---------|-------------|
| 1 | `cdoc_validate_and_resolve` | **listingmgr** | Look up order by external_oid, validate cancellable status, extract all fields from order record, resolve SecurityListingDeployment, resolve PLEGP clearing account |
| 2 | `cdoc_submit_cancel_on_chain` | **listingmgr** | Build ATS function for cancelExternallyIdentifiedDirectOrder, submit LASER async mutation, poll for completion |
| 3 | `cdoc_update_order_record` | **listingmgr** | Update order status to CANCELED, create Cancel OrderEvent |

**Service Distribution**: All 3 steps owned by listingmgr (on-chain call via LASER mutation HTTP API).

---

## cancelExternallyIdentifiedDirectOrder Parameter Mapping

**Solidity signature** (V1 facet):
```solidity
function cancelExternallyIdentifiedDirectOrder(string externalId) external returns();
```

**ATS Argument Mapping**:

| ATS Arg Name | Source | Value |
|-------------|--------|-------|
| ExternalId | Saga input | `external_oid` (= OrigClOrdID = order's ExternalOid) |

**LASER mutation**:
- `mutate_id`: `"mut_id_cancel-direct-order-{idempotency_key}"`
- `from_slot_address`: PLEGP's exchange clearing account slot address (from accmgr `/principal-legal-structure` → ClearingAccount relation)
- `to_slot_address`: Trading mechanism slot address (from SecurityListingDeployment details)
- `async`: true

**Existing ABI encoder**: `pkg/mms/agora/abi/cancel_externally_identified_direct_order.go`

---

## Data Flow Diagram

```
FIX Client ──(OrderCancelRequest 35=F)──> fixreceiver
    │
    ├─ extractCancelFIXParamsV50SP2()
    │   Extracts: OrigClOrdID (Tag 41), ClOrdID (Tag 11), Side (Tag 54),
    │             Symbol (Tag 55), TransactTime (Tag 60), Parties (PartyRole=5,121)
    │
    ├─ BuildCancelDirectOrderRequest()
    │   No order lookup, no currency resolution needed.
    │   Generates: idempotency_key, trace_id, data JSON
    │
    ├─ ListingMgrCli.SubmitCancelDirectOrder()
    │       ──HTTP POST──> listingmgr /api/v1/orders/cancel-direct
    │       │
    │       └─ traxSagaSubmitter.SubmitSaga("cancel_direct_order", sagaInput)
    │               │
    │               ├─ Step 1: cdoc_validate_and_resolve
    │               │   ├─ GetOrderByExternalOid(external_oid)
    │               │   ├─ Validate cancellable status
    │               │   ├─ Extract ALL fields from order record:
    │               │   │   security_listing_iid, exec_runtime_name,
    │               │   │   symbol, currency, side, quantity, price,
    │               │   │   pair_id, chain_id, chain_name, engine_addr
    │               │   ├─ Resolve SecurityListingDeployment
    │               │   │   → trading_mechanism_slot_address
    │               │   └─ queryExchangeClearingAccountSlotAddress()
    │               │       ── HTTP GET ──> accmgr /principal-legal-structure
    │               │       ── HTTP GET ──> accmgr /legal-structures/{iid}/account-relations?relation_type=ClearingAccount
    │               │
    │               ├─ Step 2: cdoc_submit_cancel_on_chain
    │               │   ├─ Build ATS: cancelExternallyIdentifiedDirectOrder(externalId)
    │               │   ├─ Build LASER mutation request
    │               │   ├─ submitAndPollLaserMutation()
    │               │   │   ── HTTP POST ──> lasersvc /executors/{crownIid}/mutation
    │               │   │   ── Poll ──> lasersvc /executors/{crownIid}/poll?future_id=...
    │               │   └─ Extract cancel_tx_hash
    │               │
    │               └─ Step 3: cdoc_update_order_record
    │                   ├─ UpdateOrder(status=CANCELED, metadata += cancel_tx_hash)
    │                   └─ CreateOrderEvent(type=Cancel, index_tx_hash=cancel_tx_hash)
    │
    └─ InsertPendingCancelExecReport()
        ── DB INSERT ──> tradeidxer.execution_reports
        │   ExecType="6" (PENDING_CANCEL), OrdStatus="6"
        │   ClOrdId=CancelClOrdID, OrigClOrdId=OrigClOrdID
        │
        v
    fixsender (polls tradeidxer)
        ──(ExecReport ExecType=6 PENDING_CANCEL)──> FIX Client

    [Meanwhile, on-chain event indexed by tradeidxer]

    tradeidxer ── poll chain events ── detects ORDER_CANCEL (event type 8)
        │
        └─ INSERT execution_report (ExecType=4 CANCELED, OrdStatus=4)
                │
                v
            fixsender ──(ExecReport ExecType=4 CANCELED)──> FIX Client
```

---

## Implementation Phases

### Phase 1: Schema & Model Changes

**File**: `deploy/k8s/init/init_tradeidxer_pgsql.sql`

- [ ] 1.1.1 Add column `orig_cl_ord_id VARCHAR(255) DEFAULT ''` to `tradeidxer.execution_reports` CREATE TABLE statement (after `cl_ord_id` column)

**File**: `pkg/daemons/tradeidxer/stores/models.go`

- [ ] 1.1.2 Add `OrigClOrdId string \`json:"orig_cl_ord_id"\`` field to `ExecutionReport` struct (after `ClOrdId` field, line ~42)

**File**: `pkg/daemons/tradeidxer/stores/pgsql_store.go`

- [ ] 1.1.3 Add `orig_cl_ord_id` to INSERT column list and `$N` placeholder in `InsertExecutionReport()`
- [ ] 1.1.4 Add `orig_cl_ord_id` to SELECT column list and `Scan()` in all `ExecutionReport` query methods:
  - `GetExecutionReportByExecId()`
  - `ListExecutionReports()`
  - `ListExecutionReportsByParticipantFixCompId()`
  - `ListExecutionReportsByCsdParticipantAccountIid()`
  - `ListAllExecutionReports()`
  - `GetLatestExecReportForOrder()`

**File**: `pkg/daemons/fixreceiver/fixsender/exec_report_builder.go`

- [ ] 1.2.1 In `setCommonFields50SP2()`: add `if er.OrigClOrdId != "" { msg.SetString(tag.OrigClOrdID, er.OrigClOrdId) }` (line ~166)
- [ ] 1.2.2 In `setCommonFields50SP1()`: same OrigClOrdID block (line ~199)
- [ ] 1.2.3 In `setCommonFields50()`: same OrigClOrdID block (line ~232)
- [ ] 1.2.4 In `setCommonFields44()`: same OrigClOrdID block (line ~261)

**File**: `deploy/k8s/init/exchange/min/tradeidxer.sql`

- [ ] 1.3.1 If mini records SQL has execution_report INSERT examples, add `orig_cl_ord_id` column

**File**: `deploy/k8s/init/csd/min/tradeidxer.sql`

- [ ] 1.3.2 Same as 1.3.1 for CSD namespace

---

### Phase 2: Saga Template SQL

**File**: `deploy/k8s/init/exchange/min/trax.sql`

- [ ] 2.1.1 Add `cancel_direct_order` saga template INSERT (after the create_direct_order template block):
  ```sql
  INSERT INTO trax.saga_templates (template_id, display_name, description, labels, tags, metadata, saga_step_template_ids)
  VALUES (
      'cancel_direct_order',
      'Cancel Direct Order',
      'Cancels an existing direct order on-chain via cancelExternallyIdentifiedDirectOrder on Agora Engine. Validates order is cancellable, submits LASER mutation, updates order record.',
      '{"short_id": "cdoc"}'::jsonb,
      '["agora", "csd", "saga", "order", "cancel-order", "trading", "listingmgr", "trax-flow"]'::jsonb,
      '{}'::jsonb,
      '["cdoc_validate_and_resolve", "cdoc_submit_cancel_on_chain", "cdoc_update_order_record"]'::jsonb
  )
  ON CONFLICT (template_id) DO UPDATE SET
      display_name = EXCLUDED.display_name,
      description = EXCLUDED.description,
      labels = EXCLUDED.labels,
      tags = EXCLUDED.tags,
      metadata = EXCLUDED.metadata,
      saga_step_template_ids = EXCLUDED.saga_step_template_ids;
  ```

- [ ] 2.1.2 Add Step 1 template: `cdoc_validate_and_resolve`
  ```sql
  INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
  VALUES (
      'cdoc_validate_and_resolve',
      'cancel_direct_order',
      'Validate and Resolve',
      'Look up order by external_oid, validate cancellable status, resolve SecurityListingDeployment, resolve PLEGP exchange clearing account.',
      '{"short_id": "cdoc_s1", "service": "listingmgr"}'::jsonb,
      '["agora", "csd", "saga", "step", "order", "cancel", "validation", "resolve", "plegp"]'::jsonb,
      '{"index": "1"}'::jsonb
  )
  ON CONFLICT (template_id) DO UPDATE SET
      saga_template_id = EXCLUDED.saga_template_id,
      display_name = EXCLUDED.display_name,
      description = EXCLUDED.description,
      labels = EXCLUDED.labels,
      tags = EXCLUDED.tags,
      metadata = EXCLUDED.metadata;
  ```

- [ ] 2.1.3 Add Step 2 template: `cdoc_submit_cancel_on_chain`
  ```sql
  INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
  VALUES (
      'cdoc_submit_cancel_on_chain',
      'cancel_direct_order',
      'Submit Cancel On-Chain',
      'Build ATS function call for cancelExternallyIdentifiedDirectOrder, submit LASER async mutation, poll for tx completion.',
      '{"short_id": "cdoc_s2", "service": "listingmgr"}'::jsonb,
      '["agora", "csd", "saga", "step", "order", "cancel", "on-chain", "laser", "mutation"]'::jsonb,
      '{"index": "2"}'::jsonb
  )
  ON CONFLICT (template_id) DO UPDATE SET
      saga_template_id = EXCLUDED.saga_template_id,
      display_name = EXCLUDED.display_name,
      description = EXCLUDED.description,
      labels = EXCLUDED.labels,
      tags = EXCLUDED.tags,
      metadata = EXCLUDED.metadata;
  ```

- [ ] 2.1.4 Add Step 3 template: `cdoc_update_order_record`
  ```sql
  INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
  VALUES (
      'cdoc_update_order_record',
      'cancel_direct_order',
      'Update Order Record',
      'Update order status to CANCELED in listingmgr.orders, create Cancel OrderEvent in listingmgr.order_events.',
      '{"short_id": "cdoc_s3", "service": "listingmgr"}'::jsonb,
      '["agora", "csd", "saga", "step", "order", "cancel", "record", "event"]'::jsonb,
      '{"index": "3"}'::jsonb
  )
  ON CONFLICT (template_id) DO UPDATE SET
      saga_template_id = EXCLUDED.saga_template_id,
      display_name = EXCLUDED.display_name,
      description = EXCLUDED.description,
      labels = EXCLUDED.labels,
      tags = EXCLUDED.tags,
      metadata = EXCLUDED.metadata;
  ```

**File**: `deploy/k8s/init/csd/min/trax.sql`

- [ ] 2.2.1 Add the same saga template + step template INSERTs if CSD namespace includes saga templates

---

### Phase 3: Saga Executors

New directory: `pkg/daemons/listingmgr/trax/executors/cancel_direct_order/`

#### 3.1 `saga.go` — Package Setup & Registration

- [ ] 3.1.1 Create `saga.go` with package `trax__executors__cancel_direct_order`
- [ ] 3.1.2 Define `sagaTemplateId = "cancel_direct_order"`
- [ ] 3.1.3 Define package-level variables: `pkgListingStore`, `pkgCsdMsgGwBaseURL`, `pkgAccMgrBaseURL`, `pkgLaserBaseURL`, `pkgLaserAuthKey`
- [ ] 3.1.4 Implement `RunExecutorsAsync()` launching 3 goroutines with 30ms stagger:
  - `run_ValidateAndResolve_Executor(ctx, mqClient, clusterId)`
  - `run_SubmitCancelOnChain_Executor(ctx, mqClient, clusterId)`
  - `run_UpdateOrderRecord_Executor(ctx, mqClient, clusterId)`
- [ ] 3.1.5 Implement `UpdateListingStore(store)` for E2E testing

**Pattern from**: `pkg/daemons/listingmgr/trax/executors/create_direct_order/saga.go`

#### 3.2 `laser_helpers.go` — LASER Mutation Helpers

- [ ] 3.2.1 Copy `create_direct_order/laser_helpers.go`, change package name
- [ ] 3.2.2 Include functions: `queryCrownExecutorIid()`, `submitAndPollLaserMutation()`, `queryExchangeClearingAccountSlotAddress()`
- [ ] 3.2.3 Verify package-level variables match (`pkgLaserBaseURL`, `pkgLaserAuthKey`, `pkgAccMgrBaseURL`)

**Pattern from**: `pkg/daemons/listingmgr/trax/executors/create_direct_order/laser_helpers.go`

#### 3.3 `validate_and_resolve.go` — Step 1

- [ ] 3.3.1 Create `validate_and_resolve.go` with `IdempotentService` pattern
- [ ] 3.3.2 Implement `ExecuteSync()`:
  1. Validate required inputs: `external_oid`, `cancel_cl_ord_id`, `csd_participant_account_iid`, `csd_investor_subacc_iid`, `idempotency_key` — fail immediately if any missing
  2. Look up order via `pkgListingStore.GetOrderByExternalOid(ctx, external_oid)` — fail with "order not found for external_oid=%s" if not found
  3. Validate order status is cancellable:
     - Allowed: `PendingNew`, `New`, `PartialFill`, `PendingCancel`
     - `Fill` → error "order fully filled, cannot cancel"
     - `Canceled` → error "order already cancelled"
     - `Rejected` → error "order was rejected, cannot cancel"
     - `Expired` → error "order has expired, cannot cancel"
     - `DoneForDay` → error "order is done for day, cannot cancel"
     - `Replaced` → error "order was replaced, cancel the replacement"
     - `Suspended` → error "order is suspended, cannot cancel"
     - Any other → error "order in non-cancellable status: %s"
  4. Extract from order record: `security_listing_iid`, `exec_runtime_name`, `symbol`, `currency`, `side`, `quantity`, `price`, `pair_id`, `pair_oid`, `chain_id`, `chain_name`, `engine_addr`, `participant_oid`, `on_chain_tx_hash`, `exchange_oid`, `security_listing_deployment_iid`
  5. Resolve SecurityListingDeployment by `security_listing_iid` + `exec_runtime_name` — extract `trading_mechanism_slot_address`
  6. Resolve exchange clearing account via `queryExchangeClearingAccountSlotAddress(ctx)`
- [ ] 3.3.3 Implement `CompensateSync()`: No-op (read-only step)
- [ ] 3.3.4 Implement `run_ValidateAndResolve_Executor()` function

**Output map**: `order_iid`, `order_external_oid`, `order_exchange_oid`, `order_participant_oid`, `order_status`, `order_side`, `order_quantity`, `order_price`, `order_pair_id`, `order_pair_oid`, `order_on_chain_tx_hash`, `security_listing_iid`, `exec_runtime_name`, `trading_mechanism_slot_address`, `exchange_clearing_account_slot_address`, `deployment_iid`, `security_listing_deployment_iid`, `symbol`, `currency`, `chain_id`, `chain_name`, `engine_addr`, `validation_status`

**Pattern from**: `create_direct_order/validate_and_resolve.go` (deployment resolution, PLEGP query)

#### 3.4 `submit_cancel_on_chain.go` — Step 2

- [ ] 3.4.1 Create `submit_cancel_on_chain.go` with `IdempotentService` pattern
- [ ] 3.4.2 Implement `ExecuteSync()`:
  1. Extract from merged input: `external_oid`, `trading_mechanism_slot_address`, `exchange_clearing_account_slot_address`, `idempotency_key`
  2. Build ATS function declaration for `cancelExternallyIdentifiedDirectOrder`:
     - Function name: the appropriate LASER operation name
     - Arguments: `ExternalId` (String type)
  3. Bind arguments: `ExternalId` = `external_oid`
  4. Build LASER mutation request:
     - `mutate_id`: `"mut_id_cancel-direct-order-{idempotency_key}"`
     - `from_slot_address`: `exchange_clearing_account_slot_address`
     - `to_slot_address`: `trading_mechanism_slot_address`
     - `call_data.decl`: ATS function declaration
     - `call_data.arguments`: bound arguments
     - `call_data.returns`: empty
     - `metadata.saga_step`: `"cdoc_submit_cancel_on_chain"`
     - `async`: true
  5. Submit via `submitAndPollLaserMutation()` (500ms poll interval, 180s timeout)
  6. Extract `cancel_tx_hash` from poll result
- [ ] 3.4.3 Implement `CompensateSync()`: Log warning — on-chain cancel is irreversible, no-op
- [ ] 3.4.4 Implement `run_SubmitCancelOnChain_Executor()` function

**Output**: `cancel_tx_hash`

**Pattern from**: `create_direct_order/submit_order_on_chain.go` (ATS function building, LASER mutation)
**ABI reference**: `pkg/mms/agora/abi/cancel_externally_identified_direct_order.go`

#### 3.5 `update_order_record.go` — Step 3

- [ ] 3.5.1 Create `update_order_record.go` with `IdempotentService` pattern
- [ ] 3.5.2 Implement `ExecuteSync()`:
  1. Extract from merged input: `order_iid`, `cancel_tx_hash`, `cancel_cl_ord_id`, and order metadata fields
  2. Fetch order via `pkgListingStore.GetOrder(ctx, order_iid)`
  3. Update order status:
     ```go
     order.Status = fin.OrderStatusEnum_Canceled
     if order.Metadata == nil { order.Metadata = map[string]string{} }
     order.Metadata["cancel_tx_hash"] = cancelTxHash
     order.Metadata["cancel_saga_instance_id"] = sagaInstanceId
     order.Metadata["cancel_cl_ord_id"] = cancelClOrdId
     pkgListingStore.UpdateOrder(ctx, order)
     ```
  4. Create Cancel OrderEvent:
     ```go
     event := &fin.OrderEvent{
         Iid:              "order-event-cancel-" + uuid.New().String(),
         OrderIid:         orderIid,
         Type:             fin.OrderEventTypeEnum_Cancel,
         Timestamp:        time.Now().UTC().Format(time.RFC3339),
         OrderEventType:   fin.OrderEventTypeEnumToInt(fin.OrderEventTypeEnum_Cancel), // = 5
         ChainId:          input["chain_id"],
         ChainName:        input["chain_name"],
         EngineAddr:       input["engine_addr"],
         IndexTxHash:      cancelTxHash,
         OrderIsCancelled: true,
         OrderQuantity:    input["order_quantity"],
         OrderPrice:       input["order_price"],
         OrderIsBid:       input["order_side"] == string(fin.OrderSideEnum_Bid),
         CommandOrigin:    "FIX",
         CommandOperation: "OrderCancelRequest",
         PairId:           input["order_pair_id"],
         Metadata:         map[string]string{"saga_step": "cdoc_update_order_record"},
         DisplayNames:     map[string]string{"en-US": "Cancel Order Event"},
     }
     pkgListingStore.CreateOrderEvent(ctx, event)
     ```
- [ ] 3.5.3 Implement `CompensateSync()`: Log warning — on-chain is already cancelled, no-op
- [ ] 3.5.4 Implement `run_UpdateOrderRecord_Executor()` function

**Output**: `order_event_iid`, `order_status_updated: "true"`

**Pattern from**: `create_direct_order/create_order_record.go`

---

### Phase 4: REST Endpoint in listingmgr

**File**: `pkg/daemons/listingmgr/api/v1/orders_post_cancel_direct.go` (NEW)

- [ ] 4.1.1 Define `cancelDirectOrderRequest` struct:
  ```go
  type cancelDirectOrderRequest struct {
      ExternalOid              string `json:"external_oid" binding:"required"`
      CancelClOrdId            string `json:"cancel_cl_ord_id" binding:"required"`
      CsdParticipantAccountIid string `json:"csd_participant_account_iid" binding:"required"`
      CsdInvestorSubaccIid     string `json:"csd_investor_subacc_iid" binding:"required"`
      IdempotencyKey           string `json:"idempotency_key" binding:"required"`
      TraceId                  string `json:"trace_id"`
      ParticipantFixCompId     string `json:"participant_fix_compid"`
      Data                     string `json:"data"`
  }
  ```
  NOTE: No `security_listing_iid`, `exec_runtime_name`, `symbol`, `currency`, `side`, `participant_oid` — saga Step 1 resolves all from order record.

- [ ] 4.1.2 Define `cancelDirectOrderResponse` struct with `SagaInstanceId` and `Status`
- [ ] 4.1.3 Implement `postCancelDirectOrder` handler:
  1. Check `traxSagaSubmitter` is ready (503 if not)
  2. Bind JSON request (400 on error)
  3. Quick pre-check: `listingStore.GetOrderByExternalOid(ctx, req.ExternalOid)` — 404 if not found
  4. Generate `trace_id` if empty: `fmt.Sprintf("cancel-%d-%s", time.Now().UnixMilli(), common.SecureRandomString(8))`
  5. Build saga input map
  6. Call `traxSagaSubmitter.SubmitSaga()` with template `"cancel_direct_order"`, zone `"order-zone"`, origin `"cancel-order"`, tags `["cancel-order", "trading"]`
  7. Return **202 Accepted** with `{saga_instance_id, status: "submitted"}`

**File**: `pkg/daemons/listingmgr/api/v1/api.go`

- [ ] 4.2.1 Add route: `r.POST(ApiV1UriPrefix+"/orders/cancel-direct", postCancelDirectOrder)`

**Pattern from**: `pkg/daemons/listingmgr/api/v1/orders_post_create_direct.go`

---

### Phase 5: Executor Registration

**File**: `pkg/daemons/listingmgr/trax/executors/run.go`

- [ ] 5.1.1 Add import: `trax__executors__cancel_direct_order "qomet.tech/agora/daemons/pkg/daemons/listingmgr/trax/executors/cancel_direct_order"`
- [ ] 5.1.2 Add to `RunExecutorsAsync()`: `trax__executors__cancel_direct_order.RunExecutorsAsync(ctx, mqClient, clusterId, listingStore, csdmsggwBaseURL, accmgrBaseURL, laserSvcBaseURL, laserClientAuthKey)`
- [ ] 5.1.3 Add to `UpdateListingStore()`: `trax__executors__cancel_direct_order.UpdateListingStore(listingStore)`

---

### Phase 6: fixreceiver Changes

#### 6.1 Cancel Request Builder

**File**: `pkg/daemons/fixreceiver/versions/common/saga_order_builder.go`

- [ ] 6.1.1 Add `CancelDirectOrderFromFIXParams` struct:
  ```go
  type CancelDirectOrderFromFIXParams struct {
      OrigClOrdID              string    // FIX Tag 41 — original order's ClOrdID = external_oid
      CancelClOrdID            string    // FIX Tag 11 — new ClOrdID for this cancel request
      Side                     string    // FIX Tag 54 (enum string "1"/"2")
      Symbol                   string    // FIX Tag 55
      TransactTime             time.Time // FIX Tag 60
      ParticipantData          string    // FIX Tag 58 (Text)
      RequestId                string    // Extracted from Text JSON
      FIXVersion               string
      ParticipantFixCompId     string    // sessionID.TargetCompID
      ParticipantId            string    // common.GetParticipantId(sessionID)
      CsdParticipantAccountIid string    // From FIX Parties (PartyRole=121)
      CsdInvestorSubaccIid     string    // From FIX Parties (PartyRole=5)
      FIXSessionId             string    // sessionID.String()
  }
  ```

- [ ] 6.1.2 Add `CancelDirectOrderRequest` struct:
  ```go
  type CancelDirectOrderRequest struct {
      ExternalOid              string `json:"external_oid"`
      CancelClOrdId            string `json:"cancel_cl_ord_id"`
      CsdParticipantAccountIid string `json:"csd_participant_account_iid"`
      CsdInvestorSubaccIid     string `json:"csd_investor_subacc_iid"`
      IdempotencyKey           string `json:"idempotency_key"`
      TraceId                  string `json:"trace_id"`
      ParticipantFixCompId     string `json:"participant_fix_compid"`
      Data                     string `json:"data"`
  }
  ```

- [ ] 6.1.3 Implement `BuildCancelDirectOrderRequest(ctx, params) (*CancelDirectOrderRequest, error)`:
  1. Validate `params.OrigClOrdID` non-empty — fail immediately
  2. Validate `params.CancelClOrdID` non-empty — fail immediately
  3. Validate `params.CsdParticipantAccountIid` non-empty — fail immediately
  4. Validate `params.CsdInvestorSubaccIid` non-empty — fail immediately
  5. Generate `idempotency_key`: `common.SecureRandomString(16)`
  6. Generate `trace_id`: `fmt.Sprintf("fix-cancel-%s-%d-%s", params.FIXVersion, params.TransactTime.UnixMilli(), common.SecureRandomString(8))`
  7. Build data JSON: `{"fix_version": ..., "side": ..., "symbol": ..., "transact_time": ..., "text": ..., "fix_session_id": ..., "participant_id": ...}`
  8. Return `CancelDirectOrderRequest` with `ExternalOid = params.OrigClOrdID`

**File**: `pkg/daemons/fixreceiver/versions/common/listingmgr_client.go`

- [ ] 6.1.4 Add `SubmitCancelDirectOrder(ctx, req CancelDirectOrderRequest) (string, error)`:
  - HTTP POST to `{BaseURL}/api/v1/orders/cancel-direct`
  - Expect 202 Accepted
  - Parse response for `saga_instance_id`
  - Return `saga_instance_id`

#### 6.2 PENDING_CANCEL Exec Report

**File**: `pkg/daemons/fixreceiver/versions/common/pending_cancel_report.go` (NEW)

- [ ] 6.2.1 Implement `InsertPendingCancelExecReport(ctx, req *CancelDirectOrderRequest, params *CancelDirectOrderFromFIXParams, sagaInstanceId string)`:
  - Same non-fatal pattern as `InsertPendingNewExecReport`
  - `ExecType = "6"` (PENDING_CANCEL)
  - `OrdStatus = "6"` (PENDING_CANCEL)
  - `ClOrdId = params.CancelClOrdID` (cancel request's ClOrdID)
  - `OrigClOrdId = params.OrigClOrdID` (original order's ClOrdID — NEW FIELD)
  - `Symbol = params.Symbol` (from FIX Tag 55, informational)
  - `Side = fixSide(params.Side)`
  - NOTE: OrderQty, Price, LeavesQty, CumQty, AvgPx, Currency NOT set (fixreceiver doesn't look up order)
  - `DisplayNames = map[string]string{"en-US": fmt.Sprintf("PendingCancel %s", execId)}`

**Pattern from**: `pkg/daemons/fixreceiver/versions/common/pending_new_report.go`

#### 6.3 Replace v50sp2 OCR Handler

**File**: `pkg/daemons/fixreceiver/versions/v50sp2/order_cancel_request.go`

- [ ] 6.3.1 Remove function `createExecutionPipelineArgumentsFromFIXMessageForOrderCancelRequestCommnd`
- [ ] 6.3.2 Add function `extractCancelFIXParamsV50SP2(msg, sessionID) (*fixcommon.CancelDirectOrderFromFIXParams, error)`:
  - Extract OrigClOrdID (Tag 41) — required, fail if missing
  - Extract ClOrdID (Tag 11) — required, fail if missing
  - Extract Side (Tag 54) — required, fail if missing
  - Extract Symbol (Tag 55) — required, fail if missing
  - Extract TransactTime (Tag 60) — required, fail if missing
  - Extract Parties: PartyRole=5 → CsdInvestorSubaccIid, PartyRole=121 → CsdParticipantAccountIid
  - Fail if CsdParticipantAccountIid empty: "no Party with PartyRole=ORDER_ORIGINATION_TRADER"
  - Fail if CsdInvestorSubaccIid empty: "no Party with PartyRole=INVESTOR_ID"
  - Extract Text (Tag 58) — optional, parse request_id from JSON if present
- [ ] 6.3.3 Replace `internalOnOrderCancelRequest` with saga-based flow:
  1. Extract FIX params via `extractCancelFIXParamsV50SP2()`
  2. Build cancel request via `fixcommon.BuildCancelDirectOrderRequest()`
  3. Submit to listingmgr via `fixcommon.ListingMgrCli.SubmitCancelDirectOrder()`
  4. Insert PENDING_CANCEL via `fixcommon.InsertPendingCancelExecReport()`
  5. Return sagaId
- [ ] 6.3.4 Update `getOrderCancelRequestHandler` to match NOS handler pattern (log sagaId, handle errors)
- [ ] 6.3.5 Remove imports no longer needed: `execpl`, `execpl/helpers`, `marketds/model/exchange`, `mq/exchange`

#### 6.4 Update Other FIX Version OCR Handlers

Same transformation as v50sp2, using version-specific quickfix types:

**File**: `pkg/daemons/fixreceiver/versions/v44/order_cancel_request.go`

- [ ] 6.4.1 Add `extractCancelFIXParamsV44()` using `fix44ocr.OrderCancelRequest`
- [ ] 6.4.2 Replace `internalOnOrderCancelRequest` with saga flow
- [ ] 6.4.3 Remove old execution pipeline code

**File**: `pkg/daemons/fixreceiver/versions/v50/order_cancel_request.go`

- [ ] 6.4.4 Add `extractCancelFIXParamsV50()` using `fix50ocr.OrderCancelRequest`
- [ ] 6.4.5 Replace `internalOnOrderCancelRequest` with saga flow
- [ ] 6.4.6 Remove old execution pipeline code

**File**: `pkg/daemons/fixreceiver/versions/v50sp1/order_cancel_request.go`

- [ ] 6.4.7 Add `extractCancelFIXParamsV50SP1()` using `fix50sp1ocr.OrderCancelRequest`
- [ ] 6.4.8 Replace `internalOnOrderCancelRequest` with saga flow
- [ ] 6.4.9 Remove old execution pipeline code

**File**: `pkg/daemons/fixreceiver/versions/v42/order_cancel_request.go`

- [ ] 6.4.10 Add `extractCancelFIXParamsV42()` using `fix42ocr.OrderCancelRequest`
- [ ] 6.4.11 Replace `internalOnOrderCancelRequest` with saga flow
- [ ] 6.4.12 Remove old execution pipeline code

---

### Phase 7: Cleanup Old Execution Pipeline OCR Path

- [ ] 7.1.1 Verify `cmdbcaster/broadcast_order_cancel_request.go` is no longer triggered by FIX OCR (keep file — may be used by other non-FIX paths)
- [ ] 7.1.2 Verify `cmdprocessor/process_order_cancel_request.go` is no longer triggered by FIX OCR (keep file)
- [ ] 7.1.3 Remove unused imports from updated OCR handler files (`execpl`, `execpl/helpers`, `marketds/model/exchange`, `mq/exchange`)

---

### Phase 8: E2E Tests (Category 44)

**File**: `tests/e2e/laser/cancel_direct_order_test.go` (NEW)

#### Test Infrastructure

- [ ] 8.0.1 Define global test variables: `cdocGlobalReady`, `cdocTestInfraMap`
- [ ] 8.0.2 Define `cdocTestInfra` struct (embeds CDO test infra + cancel-specific fields)
- [ ] 8.0.3 Implement `setupTestDatabaseForCancelDirectOrder(t)` — database setup function (first line of every test)
- [ ] 8.0.4 Implement `setupCancelDirectOrderTest(t, prefix)` — reuse CDO infrastructure, create orders for cancellation
- [ ] 8.0.5 Implement `submitCancelDirectOrder(t, externalOid, cancelClOrdId, idempotencyKey, csdParticipantAccountIid, csdInvestorSubaccIid) (sagaInstanceId string, httpStatus int)`
- [ ] 8.0.6 Implement `verifyCancelledOrder(t, externalOid)` — verify order status=CANCELED + Cancel OrderEvent exists

#### Green Path Tests

- [ ] 8.1.1 `TestCancelDirectOrder_LimitBid`:
  1. Create limit BID order via create_direct_order saga
  2. Wait for order status=NEW
  3. Submit cancel via POST /api/v1/orders/cancel-direct
  4. Wait for cancel saga completion
  5. Verify order status = CANCELED in listingmgr.orders
  6. Verify OrderEvent of type=Cancel exists
  7. Verify tradeidxer has CANCELED exec report (event type 8)

- [ ] 8.1.2 `TestCancelDirectOrder_LimitAsk`: Same as BID but ASK side

- [ ] 8.1.3 `TestCancelDirectOrder_PendingNewOrder`:
  - Cancel immediately after creation (may still be PENDING_NEW)
  - Verify successful cancellation

- [ ] 8.1.4 `TestCancelDirectOrder_Idempotent`:
  - Submit same cancel twice with same idempotency_key
  - Verify idempotent (no error, same result)

#### Red Path Tests

- [ ] 8.2.1 `TestCancelDirectOrder_NonExistentOrder`:
  - Cancel with external_oid that doesn't exist
  - Expect 404 from REST endpoint pre-check

- [ ] 8.2.2 `TestCancelDirectOrder_AlreadyCancelled`:
  - Cancel order, then cancel again (different idempotency_key)
  - Expect saga failure at Step 1 with "order already cancelled"

- [ ] 8.2.3 `TestCancelDirectOrder_FilledOrder`:
  - Create BID + ASK matching orders, wait for fills
  - Try to cancel filled order
  - Expect saga failure at Step 1 with "order fully filled, cannot cancel"

- [ ] 8.2.4 `TestCancelDirectOrder_MissingRequiredFields`:
  - Missing `external_oid` → 400
  - Missing `idempotency_key` → 400
  - Missing `cancel_cl_ord_id` → 400
  - Missing `csd_participant_account_iid` → 400
  - Missing `csd_investor_subacc_iid` → 400

- [ ] 8.2.5 `TestCancelDirectOrder_ExpiredOrder`:
  - Create order with short expiry (e.g., 5 seconds)
  - Wait for expiration (tradeidxer indexes ORDER_EXPIRE event)
  - Try to cancel
  - Expect failure with "order has expired, cannot cancel"

---

### Phase 9: Makefile & Test Catalog Updates

**File**: `Makefile`

- [ ] 9.1.1 Add `E2E_CAT44_PATTERN := TestCancelDirectOrder` (after E2E_CAT42_PATTERN)
- [ ] 9.1.2 Add target `laser-e2e-ethbc-cat44` following cat42 pattern
- [ ] 9.1.3 Add Cat 44 to `e2e-cat-help` output

**File**: `docs/E2E_TEST_CATALOG.md`

- [ ] 9.2.1 Add Cat 44 entry: `| 44 | ⭐⭐⭐⭐ | Cancel Direct Order | laser-e2e-ethbc-cat44 |`

---

### Phase 10: Documentation Updates

**File**: `docs/SUMMARY-FOR-AGENT.md`

- [ ] 10.1.1 Add entry for `cancel_direct_order` saga under the appropriate section

**File**: `docs/TODO.md`

- [ ] 10.2.1 Add entry: `- [ ] **Cancel Direct Order Saga**: TRAX saga for FIX OrderCancelRequest handling (see TODO_CANCEL_DIRECT_ORDER_SAGA.md)`

---

## Critical Files Summary

### New Files
| File | Description |
|------|-------------|
| `pkg/daemons/listingmgr/trax/executors/cancel_direct_order/saga.go` | Package setup and executor registration |
| `pkg/daemons/listingmgr/trax/executors/cancel_direct_order/laser_helpers.go` | LASER mutation helpers (from create_direct_order) |
| `pkg/daemons/listingmgr/trax/executors/cancel_direct_order/validate_and_resolve.go` | Step 1: Validate order + resolve deployment |
| `pkg/daemons/listingmgr/trax/executors/cancel_direct_order/submit_cancel_on_chain.go` | Step 2: LASER mutation for cancel |
| `pkg/daemons/listingmgr/trax/executors/cancel_direct_order/update_order_record.go` | Step 3: Update order status + OrderEvent |
| `pkg/daemons/listingmgr/api/v1/orders_post_cancel_direct.go` | REST endpoint handler |
| `pkg/daemons/fixreceiver/versions/common/pending_cancel_report.go` | PENDING_CANCEL exec report insertion |
| `tests/e2e/laser/cancel_direct_order_test.go` | E2E tests (Cat 44) |

### Modified Files
| File | Change |
|------|--------|
| `pkg/daemons/tradeidxer/stores/models.go` | Add `OrigClOrdId` field to ExecutionReport |
| `pkg/daemons/tradeidxer/stores/pgsql_store.go` | Add `orig_cl_ord_id` to SQL queries |
| `deploy/k8s/init/init_tradeidxer_pgsql.sql` | Add `orig_cl_ord_id` column |
| `deploy/k8s/init/exchange/min/trax.sql` | Add cancel_direct_order saga template + steps |
| `pkg/daemons/listingmgr/api/v1/api.go` | Add cancel-direct route |
| `pkg/daemons/listingmgr/trax/executors/run.go` | Register cancel_direct_order executors |
| `pkg/daemons/fixreceiver/versions/common/saga_order_builder.go` | Add cancel structs + builder |
| `pkg/daemons/fixreceiver/versions/common/listingmgr_client.go` | Add SubmitCancelDirectOrder |
| `pkg/daemons/fixreceiver/versions/v50sp2/order_cancel_request.go` | Replace exec pipeline with saga |
| `pkg/daemons/fixreceiver/versions/v44/order_cancel_request.go` | Replace exec pipeline with saga |
| `pkg/daemons/fixreceiver/versions/v50/order_cancel_request.go` | Replace exec pipeline with saga |
| `pkg/daemons/fixreceiver/versions/v50sp1/order_cancel_request.go` | Replace exec pipeline with saga |
| `pkg/daemons/fixreceiver/versions/v42/order_cancel_request.go` | Replace exec pipeline with saga |
| `pkg/daemons/fixreceiver/fixsender/exec_report_builder.go` | Set OrigClOrdID tag when present |
| `Makefile` | Add E2E_CAT44_PATTERN + target |
| `docs/E2E_TEST_CATALOG.md` | Add Cat 44 entry |
| `docs/TODO.md` | Add reference |
| `docs/SUMMARY-FOR-AGENT.md` | Add entry |

### Reference Files (patterns to follow)
| File | What to reuse |
|------|---------------|
| `pkg/daemons/listingmgr/trax/executors/create_direct_order/saga.go` | Package structure, executor registration |
| `pkg/daemons/listingmgr/trax/executors/create_direct_order/validate_and_resolve.go` | Deployment resolution, PLEGP clearing account query |
| `pkg/daemons/listingmgr/trax/executors/create_direct_order/submit_order_on_chain.go` | ATS function building, LASER mutation |
| `pkg/daemons/listingmgr/trax/executors/create_direct_order/create_order_record.go` | Order/OrderEvent creation |
| `pkg/daemons/listingmgr/trax/executors/create_direct_order/laser_helpers.go` | LASER helpers to copy |
| `pkg/daemons/listingmgr/api/v1/orders_post_create_direct.go` | REST endpoint pattern |
| `pkg/daemons/fixreceiver/versions/v50sp2/new_order_single.go` | FIX param extraction + saga submission |
| `pkg/daemons/fixreceiver/versions/common/pending_new_report.go` | PENDING_CANCEL report pattern |
| `pkg/mms/agora/abi/cancel_externally_identified_direct_order.go` | V1 ABI encoder reference |
| `tests/e2e/laser/create_direct_order_test.go` | E2E test infrastructure setup |

---

## Success Criteria

- [ ] `cancel_direct_order` saga successfully cancels an on-chain order via LASER
- [ ] Order status updated to CANCELED in `listingmgr.orders`
- [ ] Cancel OrderEvent created in `listingmgr.order_events`
- [ ] PENDING_CANCEL exec report delivered to FIX client immediately
- [ ] CANCELED exec report delivered to FIX client via tradeidxer on-chain event indexing
- [ ] Non-cancellable orders fail fast with descriptive error (no on-chain call attempted)
- [ ] Missing required fields fail immediately (no fallbacks)
- [ ] All E2E green/red path tests pass in ethbc mode
- [ ] Old execution pipeline OCR code replaced (no MQ command publish)
- [ ] All 5 FIX version handlers updated (v42, v44, v50, v50sp1, v50sp2)
