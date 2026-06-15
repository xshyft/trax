# TODO: Create Direct Order - TRAX Saga Implementation

> **Status**: PHASES 1-9, 12-13 COMPLETE (~90%) — remaining: Phase 10 (E2E tests), Phase 11 (documentation)
> **Created**: 2026-02-25
> **Last Updated**: 2026-03-07
> **Parent Reference**: `setup_security_listing` saga (prerequisite: trading pair must be deployed on-chain)
> **Related**: FIX NewOrderSingle integration — see `docs/TODO_FIX_NEW_ORDER_SINGLE_SAGA.md`

## Overview

TRAX saga template `create_direct_order` that submits a new trading order to an already-deployed Agora Engine trading pair via `createExternallyIdentifiedBatchDirectOrderV2`. The saga is owned by **listingmgr** and orchestrates input validation, PLEGP verification, decimal scaling, on-chain order submission via LASER, and off-chain order record persistence.

**Key architectural points**:
- **Saga owner**: listingmgr (same pattern as `setup_security_listing` — domain-owning service runs its own saga steps including on-chain calls via LASER mutation API)
- **Smart contract function**: `createExternallyIdentifiedBatchDirectOrderV2(string externalId, bytes32 pairId, CreateDirectOrderParamsV2[] memory paramsArr)` — batch function, but this saga creates only ONE order per invocation (batch of size 1)
- **Caller/signer**: The PLEGP's admin partner submits the on-chain transaction on behalf of the participant
- **Fee payer**: Defaults to `participant_iid` (the participant's cash account pays fees)
- **V2 order struct**: Separates `participant` (cash account), `investor` (beneficial owner), and `feePayer` addresses — all translated from IIDs to ETH addresses by LASER's E1->E2 relay chain
- **Go bindings prerequisite**: `kam` will generate the Go bindings for `createExternallyIdentifiedBatchDirectOrderV2` from the Solidity ABI. The TODO assumes these exist.

---

## Prerequisites (MUST be validated in Step 1)

1. **Security Listing Deployment exists and is active** for the given `security_listing_iid` + `exec_runtime_name` — the `setup_security_listing` saga must have completed successfully, creating a `SecurityListingDeployment` with a valid `AgoraPairId`
2. **PLEGP configured** — `principal_legal_structure_iid` must be set in configmgr, queryable via accmgr `GET /principal-legal-structure`
3. **Trading mechanism belongs to PLEGP** — the Agora Engine diamond (from `SecurityListingDeployment.DeploymentDetails.TradingMechanismSlotAddress`) must belong to the principal legal structure
4. **Exchange is operating** — basic calendar check: if calendar has entries, verify current time falls within operating hours; if calendar is empty, assume 24/7 operation
5. **All required inputs** are present and valid (format, enum values, quantity > 0, expire_timestamp in future, etc.)

---

## Saga Specification

### Inputs

| Field | Type | Required | Default | Description | Format |
|-------|------|----------|---------|-------------|--------|
| external_oid | string | Yes | — | Broker-generated external order ID | `[a-zA-Z0-9\-_+/\\]{16}+` |
| participant_oid | string | Yes | — | Participant-generated order ID | `part_oid_{[a-zA-Z0-9\-_+/\\]{32}}` |
| exec_runtime_name | string | Yes | — | Execution runtime name (e.g., "primary") | |
| security_listing_iid | string | Yes | — | IID of the SecurityListing | |
| participant_iid | string | Yes | — | Participant slot address (cash account) | Equal to `participant_slot_address` |
| investor_iid | string | Yes | — | Investor slot address (beneficial owner) | Equal to `investor_slot_address` |
| order_type | OrderTypeEnum | Yes | — | Order type | `ORDER_TYPE_ENUM_LIMIT` or `ORDER_TYPE_ENUM_MARKET` |
| quantity | string | Yes | — | Human-readable quantity (e.g., "100.50") | Decimal string, must be > 0 |
| price | string | Yes | — | Human-readable price (e.g., "25.75") | Decimal string; > 0 for LIMIT, 0 for MARKET |
| side | OrderSideEnum | Yes | — | Order side | `ORDER_SIDE_ENUM_BID` or `ORDER_SIDE_ENUM_ASK` |
| idempotency_key | string | Yes | — | Idempotency key for TRAX dedup | |
| expire_timestamp | string | Yes | — | Order expiration time | Unix timestamp (seconds), must be in the future |
| directly_fillable | string | No | "false" | Whether order can be directly filled | "true" or "false" |
| slippage | string | No | "0" | Slippage tolerance | Non-negative integer string |
| trace_id | string | No | "" | Distributed tracing ID | |
| execution_id | string | No | "" | Execution pipeline ID | |
| data | string | No | "{}" | Additional JSON data | Valid JSON string |

### Outputs

| Field | Type | Description |
|-------|------|-------------|
| exchange_oid | string | Listingmgr-generated unique order ID. Format: `exch_oid_{random32}` |
| pair_oid | string | On-chain `orderId` (uint256 decimal string) from `DirectOrderCreate2` event |
| pair_id | string | On-chain `pairId` (bytes32 hex string) from `SecurityListingDeployment.AgoraPairId` |
| order_hash | string | Universal order hash (SHA-512/384 hex string with `0x` prefix) |
| saga_instance_id | string | TRAX saga instance ID |

### Validation Rules (Step 1)

1. All required inputs must be non-empty
2. `external_oid` must match pattern `[a-zA-Z0-9\-_+/\\]{16,}`
3. `participant_oid` must match pattern `part_oid_{[a-zA-Z0-9\-_+/\\]{32}}`
4. `order_type` must be `ORDER_TYPE_ENUM_LIMIT` or `ORDER_TYPE_ENUM_MARKET`
5. `side` must be `ORDER_SIDE_ENUM_BID` or `ORDER_SIDE_ENUM_ASK`
6. `quantity` must be a positive decimal number
7. `price` must be > 0 for LIMIT orders, must be 0 for MARKET orders
8. `expire_timestamp` must be a valid Unix timestamp in the future
9. `slippage` must be a non-negative integer (default "0")
10. `directly_fillable` must be "true" or "false" (default "false")
11. `SecurityListingDeployment` must exist for `security_listing_iid` + `exec_runtime_name`
12. PLEGP must be configured (accmgr `GET /principal-legal-structure` returns valid response)
13. Trading mechanism from the deployment must belong to the principal legal structure
14. Calendar check: if calendar entries exist for the listing, current time must be within operating hours

### Saga Steps (3 steps)

| Step | Name | Service | Description |
|------|------|---------|-------------|
| 1 | `cdo_validate_and_resolve` | **listingmgr** | Validate inputs, find pair_id from SecurityListingDeployment, verify PLEGP, check calendar, resolve admin partner, query token decimals |
| 2 | `cdo_submit_order_on_chain` | **listingmgr** | Build ATS function, scale quantity/price by token decimals, serialize data JSON, submit LASER mutation for createExternallyIdentifiedBatchDirectOrderV2, extract orderId from DirectOrderCreate2 event |
| 3 | `cdo_create_order_record` | **listingmgr** | Generate exchange_oid, compute order_hash, create order record + initial order event in listingmgr PostgreSQL |

**Service Distribution**:
- **listingmgr**: Steps 1-3 (all steps; on-chain call made via LASER mutation HTTP API, same pattern as `ssl_create_pair_on_chain`)

---

## Data Flow Diagram

```
                    REST API Trigger
                          |
                          v
              POST /api/v1/orders/create-direct
                          |
                     Pre-checks:
                     - Required fields present
                     - Enum validation (order_type, side)
                     - SecurityListingDeployment exists & active
                     - PLEGP configured
                     - expire_timestamp in future
                     - quantity > 0, price validation
                          |
                          v
                   [TRAX Coordinator]
                          |
    +---------------------+
    |
    v
Step 1: cdo_validate_and_resolve
    |  - Validate all inputs
    |  - Query listingmgr store: SecurityListingDeployment by
    |    security_listing_iid + exec_runtime_name
    |  - Extract pair_id (AgoraPairId) from deployment details
    |  - Extract trading_mechanism_slot_address from deployment details
    |  - Query accmgr GET /principal-legal-structure -> PLEGP
    |  - Verify trading mechanism belongs to PLEGP's legal structure
    |  - Query SecurityListing -> calendar_iid -> check operating hours
    |  - Query instrmgr for base token decimals (security)
    |  - Query instrmgr for quote token decimals (cash token)
    |  - Resolve PLEGP admin partner slot address
    |  - Resolve PLEGP authz admin slot address
    |  - Resolve trading engine AuthzDiamond slot address
    |
    v
Step 2: cdo_submit_order_on_chain
    |  - Scale quantity by base token decimals
    |  - Scale price by quote token decimals
    |  - Map side: BID -> bid=true, ASK -> bid=false
    |  - Map order_type: LIMIT -> 1, MARKET -> 2
    |  - Serialize data JSON (external_oid, participant_oid, exchange_oid*,
    |    pair_oid*, idempotency_key, trace_id, execution_id,
    |    saga_instance_id, participant_iid, investor_iid, pair_id)
    |    *exchange_oid and pair_oid populated as "" since not yet known
    |  - Build ATS BoundFunc for createExternallyIdentifiedBatchDirectOrderV2
    |  - Submit LASER async mutation:
    |    from_slot_address = PLEGP admin_partner_slot_address
    |    to_slot_address = trading_mechanism_slot_address
    |  - Poll for completion (180s timeout)
    |  - Extract pair_oid (orderId) from DirectOrderCreate2 event metadata
    |  - Extract tx_hash from mutation result
    |
    v
Step 3: cdo_create_order_record
    |  - Generate exchange_oid: "exch_oid_{random32}"
    |  - Compute order_hash: SHA-512/384 of
    |    "agora-direct-order|{chainId}|{chainName}|{engineAddr}|{pairId}|{orderId}|{externalOid}|{exchangeOid}"
    |  - Build Order record with all fields
    |  - Insert into listingmgr.orders
    |  - Build initial OrderEvent (type=CREATE, status=NEW)
    |  - Insert into listingmgr.order_events
    |  - Return: exchange_oid, pair_oid, pair_id, order_hash, saga_instance_id
```

---

## createExternallyIdentifiedBatchDirectOrderV2 Parameter Mapping

**Solidity signature**:
```solidity
function createExternallyIdentifiedBatchDirectOrderV2(
    string memory externalId,
    bytes32 pairId,
    CreateDirectOrderParamsV2[] memory paramsArr
) external returns (uint256 firstDirectOrderId);

struct CreateDirectOrderParamsV2 {
    CreateDirectOrderParams paramsV1;
    address participant;
    address investor;
    address feePayer;
}

struct CreateDirectOrderParams {
    bool bid;
    bool directlyFillable;
    uint256 orderType;        // 1=LIMIT, 2=MARKET
    uint256 quantity;          // scaled by base token decimals
    uint256 price;             // scaled by quote token decimals
    uint256 slippage;
    uint256 expireTs;
    bytes data;
}
```

**ATS Argument Mapping**:

| ATS Arg Name | Source | Value |
|-------------|--------|-------|
| external_id | Saga input | `external_oid` |
| pair_id | Step 1 output | `pair_id` (bytes32 hex from SecurityListingDeployment.AgoraPairId) |
| bid | Saga input | BID -> "true", ASK -> "false" |
| directly_fillable | Saga input | Default "false" |
| order_type | Saga input | LIMIT -> "1", MARKET -> "2" |
| quantity | Step 2 computed | Human-readable quantity * 10^(base_token_decimals) |
| price | Step 2 computed | Human-readable price * 10^(quote_token_decimals) |
| slippage | Saga input | Default "0" |
| expire_ts | Saga input | Unix timestamp (seconds) |
| data | Step 2 computed | UTF-8 bytes of serialized JSON (see Note 13 from requirements) |
| participant | Saga input | `participant_iid` (translated to ETH addr by LASER E1->E2) |
| investor | Saga input | `investor_iid` (translated to ETH addr by LASER E1->E2) |
| fee_payer | Saga input | `participant_iid` (same as participant — fee payer = participant) |

**LASER mutation**:
- `from_slot_address`: PLEGP's admin partner slot address (caller/signer authorized on AuthzDiamond)
- `to_slot_address`: Trading mechanism slot address (Agora Engine diamond)

**Event to extract**:
- `DirectOrderCreate2(uint256 eventId, bytes32 indexed pairId, uint256 indexed orderId)`
- Extract `orderId` from event — this becomes `pair_oid`

---

## Order Hash Computation

**New function**: `GetDirectOrderHash` in `pkg/common/hash.go`

```go
func GetDirectOrderHash(
    chainId DecimalStr,
    chainName string,
    engineAddr HexStrWith0x,
    pairId HexStrWith0x,
    orderId DecimalStr,
    externalOid string,
    exchangeOid string,
) HexStrWith0x {
    hash := sha512.New384()
    str := fmt.Sprintf(
        "agora-direct-order|%s|%s|%s|%s|%s|%s|%s",
        strings.ToLower(string(chainId)),
        strings.ToLower(chainName),
        strings.ToLower(string(engineAddr)),
        strings.ToLower(string(pairId)),
        strings.ToLower(string(orderId)),
        strings.ToLower(externalOid),
        strings.ToLower(exchangeOid),
    )
    hash.Write([]byte(str))
    buf := hash.Sum(nil)
    return HexStrWith0x("0x" + strings.ToLower(hex.EncodeToString(buf)))
}
```

---

## Data Field JSON Structure

The `data` bytes field in `CreateDirectOrderParams` contains a UTF-8 encoded JSON string for off-chain traceability. The smart contract stores it as opaque bytes.

```json
{
    "external_oid": "abc123DEF456test",
    "participant_oid": "part_oid_abcdefghijklmnopqrstuvwxyz012345",
    "exchange_oid": "exch_oid_abcdefghijklmnopqrstuvwxyz012345",
    "pair_oid": "",
    "idempotency_key": "idk_xyz123...",
    "trace_id": "trace_...",
    "execution_id": "exec_...",
    "saga_instance_id": "saga_...",
    "participant_iid": "slot_addr_...",
    "investor_iid": "slot_addr_...",
    "pair_id": "0xabcdef..."
}
```

**Note**: `exchange_oid` and `pair_oid` are populated as empty strings at the time of the on-chain call (Step 2) because they are generated/extracted after the transaction. They are included in the schema for consistency. The full values are available in the off-chain order record (Step 3).

---

## Implementation Phases

### Phase 1: Domain Model Updates

**File**: `pkg/fin/order.go` (NEW)

- [x] 1.1.1 Create `Order` struct aligned with the `listingmgr.orders` table:
  ```go
  type Order struct {
      Iid                          string
      ExternalOid                  string
      ExchangeOid                  string
      ParticipantOid               string
      PairId                       string  // bytes32 hex
      PairOid                      string  // uint256 decimal (on-chain orderId)
      OrderHash                    string  // SHA-512/384 hex
      SecurityListingIid           string
      SecurityListingDeploymentIid string
      ParticipantIid               string  // participant slot address
      InvestorIid                  string  // investor slot address
      Side                         OrderSideEnum
      OrderType                    OrderTypeEnum
      Quantity                     string  // human-readable
      Price                        string  // human-readable
      Slippage                     string
      ExpireTimestamp               string  // unix seconds
      DirectlyFillable             bool
      Status                       OrderStatusEnum
      OnChainTxHash                string
      SagaInstanceId               string
      IdempotencyKey               string
      TraceId                      string
      ExecutionId                  string
      ExecRuntimeName              string
      Symbol                       string  // base token symbol
      Currency                     string  // quote token symbol
      ChainId                      string
      ChainName                    string
      EngineAddr                   string  // trading mechanism ETH address
      Data                         string  // JSON string
      DisplayNames                 map[string]string
      Labels                       map[string]string
      Tags                         []string
      Metadata                     map[string]string
  }
  ```

- [x] 1.1.2 Create `OrderSideEnum` type:
  ```go
  type OrderSideEnum string
  const (
      OrderSideEnum_Bid OrderSideEnum = "ORDER_SIDE_ENUM_BID"
      OrderSideEnum_Ask OrderSideEnum = "ORDER_SIDE_ENUM_ASK"
  )
  ```

- [x] 1.1.3 Create `OrderTypeEnum` type (in `pkg/fin/`, decoupled from `execpl`):
  ```go
  type OrderTypeEnum string
  const (
      OrderTypeEnum_Limit  OrderTypeEnum = "ORDER_TYPE_ENUM_LIMIT"
      OrderTypeEnum_Market OrderTypeEnum = "ORDER_TYPE_ENUM_MARKET"
  )
  ```

- [x] 1.1.4 Create `OrderStatusEnum` type (FIX-aligned, decoupled from `execpl`):
  ```go
  type OrderStatusEnum string
  const (
      OrderStatusEnum_PendingNew   OrderStatusEnum = "ORDER_STATUS_ENUM_PENDING_NEW"
      OrderStatusEnum_New          OrderStatusEnum = "ORDER_STATUS_ENUM_NEW"
      OrderStatusEnum_PartialFill  OrderStatusEnum = "ORDER_STATUS_ENUM_PARTIAL_FILL"
      OrderStatusEnum_Fill         OrderStatusEnum = "ORDER_STATUS_ENUM_FILL"
      OrderStatusEnum_DoneForDay   OrderStatusEnum = "ORDER_STATUS_ENUM_DONE_FOR_DAY"
      OrderStatusEnum_Canceled     OrderStatusEnum = "ORDER_STATUS_ENUM_CANCELED"
      OrderStatusEnum_Replaced     OrderStatusEnum = "ORDER_STATUS_ENUM_REPLACED"
      OrderStatusEnum_PendingCancel OrderStatusEnum = "ORDER_STATUS_ENUM_PENDING_CANCEL"
      OrderStatusEnum_Stopped      OrderStatusEnum = "ORDER_STATUS_ENUM_STOPPED"
      OrderStatusEnum_Rejected     OrderStatusEnum = "ORDER_STATUS_ENUM_REJECTED"
      OrderStatusEnum_Suspended    OrderStatusEnum = "ORDER_STATUS_ENUM_SUSPENDED"
      OrderStatusEnum_Calculated   OrderStatusEnum = "ORDER_STATUS_ENUM_CALCULATED"
      OrderStatusEnum_Expired      OrderStatusEnum = "ORDER_STATUS_ENUM_EXPIRED"
      OrderStatusEnum_Restated     OrderStatusEnum = "ORDER_STATUS_ENUM_RESTATED"
      OrderStatusEnum_PendingReplace OrderStatusEnum = "ORDER_STATUS_ENUM_PENDING_REPLACE"
  )
  ```

**File**: `pkg/fin/order_event.go` (NEW)

- [x] 1.2.1 Create `OrderEvent` struct aligned with the `listingmgr.order_events` table:
  ```go
  type OrderEvent struct {
      Iid                    string
      OrderIid               string
      Type                   OrderEventTypeEnum
      Timestamp              string  // ISO 8601
      // Off-chain command fields
      CommandOrigin          string
      CommandOperation       string
      ExecMsg                string
      // On-chain fields
      ChainId                string
      ChainName              string
      EngineAddr             string
      IndexTs                string
      IndexBlockTs           string
      IndexBlockNr           string
      IndexTxHash            string
      IndexTxLogIdx          int64
      // Pair info
      PairId                 string
      // Order event fields
      OrderEventType         int     // Cassandra-compatible int (1=Create, 2=Replace, etc.)
      OrderEventVersion      string
      OrderEventTs           int64
      OrderEventId           string
      OrderEventHash         string
      OrderEventData         string
      // Order snapshot
      OrderId                string  // uint256 decimal
      OrderHash              string
      OrderQuantity          string
      OrderRemainingQuantity string
      OrderPrice             string
      OrderVolume            string
      OrderRemainingVolume   string
      OrderSlippage          string
      OrderType              string
      OrderIsBid             bool
      OrderIsFilled          bool
      OrderIsCancelled       bool
      OrderIsExpired         bool
      OrderCreateTs          string
      OrderExpireTs          string
      OrderCreatorAddr       string
      OrderIsDirectlyFillable bool
      OrderData              string
      OrderAlarmAbi          string
      OrderAlarmData         string
      // Trade fields (for fill events)
      TradeId                string
      TradeHash              string
      TradeTimestamp         string
      TradeCreatorAddr       string
      TradeType              string
      TradeIsBuy             bool
      TradeBidOrderId        string
      TradeAskOrderId        string
      TradeBidFee            string
      TradeAskFee            string
      TradeQuantity          string
      TradePrice             string
      TradeVolume            string
      // Standard fields
      DisplayNames           map[string]string
      Labels                 map[string]string
      Tags                   []string
      Metadata               map[string]string
  }
  ```

- [x] 1.2.2 Create `OrderEventTypeEnum` type:
  ```go
  type OrderEventTypeEnum string
  const (
      OrderEventTypeEnum_Create         OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_CREATE"
      OrderEventTypeEnum_Replace        OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_REPLACE"
      OrderEventTypeEnum_Fill           OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_FILL"
      OrderEventTypeEnum_Close          OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_CLOSE"
      OrderEventTypeEnum_Cancel         OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_CANCEL"
      OrderEventTypeEnum_Expire         OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_EXPIRE"
      OrderEventTypeEnum_Alarm          OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_ALARM"
      OrderEventTypeEnum_Queue          OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_QUEUE"
      OrderEventTypeEnum_Dequeue        OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_DEQUEUE"
      OrderEventTypeEnum_OrderbookEnter OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_ORDERBOOK_ENTER"
      OrderEventTypeEnum_OrderbookExit  OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_ORDERBOOK_EXIT"
      // Command pipeline events (201-223)
      OrderEventTypeEnum_CommandReceivedFromOrigin       OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_COMMAND_RECEIVED_FROM_ORIGIN"
      OrderEventTypeEnum_CommandPickedUpForProcessing    OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_COMMAND_PICKED_UP_FOR_PROCESSING"
      OrderEventTypeEnum_EnvelopePrepared                OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_ENVELOPE_PREPARED"
      OrderEventTypeEnum_TransactionBroadcasted          OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_TRANSACTION_BROADCASTED"
      OrderEventTypeEnum_ExecutionError                  OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_EXECUTION_ERROR"
      OrderEventTypeEnum_ExecutionComplete               OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_EXECUTION_COMPLETE"
      OrderEventTypeEnum_ExecutionRejected               OrderEventTypeEnum = "ORDER_EVENT_TYPE_ENUM_EXECUTION_REJECTED"
  )
  ```

- [x] 1.2.3 Add mapping function `OrderEventTypeEnumToInt(e OrderEventTypeEnum) int` for Cassandra compatibility

---

### Phase 2: LASER createExternallyIdentifiedBatchDirectOrderV2 Operation

**Prerequisite**: `kam` generates Go bindings from the Solidity ABI. The following items assume Go bindings exist.

**File**: `pkg/laser/model/operation_name.go`

- [x] 2.1.1 Add operation name:
  ```go
  OperationNameEnum_AgoraEngineDirectOrderManagerCreateExternallyIdentifiedBatchDirectOrderV2 OperationNameEnum = "OPERATION_NAME_ENUM_AGORA_ENGINE_DIRECT_ORDER_MANAGER_CREATE_EXTERNALLY_IDENTIFIED_BATCH_DIRECT_ORDER_V2"
  ```

**File**: `pkg/laser/ats/arg_name.go`

- [x] 2.2.1 Add ATS argument names for the function parameters:
  ```go
  ArgNameEnum_ExternalId       ArgNameEnum = "external_id"
  ArgNameEnum_PairId           ArgNameEnum = "pair_id"
  ArgNameEnum_Bid              ArgNameEnum = "bid"
  ArgNameEnum_DirectlyFillable ArgNameEnum = "directly_fillable"
  ArgNameEnum_OrderType        ArgNameEnum = "order_type"
  ArgNameEnum_Quantity         ArgNameEnum = "quantity"
  ArgNameEnum_Price            ArgNameEnum = "price"
  ArgNameEnum_Slippage         ArgNameEnum = "slippage"
  ArgNameEnum_ExpireTs         ArgNameEnum = "expire_ts"
  ArgNameEnum_OrderData        ArgNameEnum = "order_data"
  ArgNameEnum_Participant      ArgNameEnum = "participant"
  ArgNameEnum_Investor         ArgNameEnum = "investor"
  ArgNameEnum_FeePayer         ArgNameEnum = "fee_payer"
  ```
  **Note**: Some names (`Slippage`, `Data`) may already exist from `createPairV2` args. Reuse where possible; add new ones only if needed.

**File**: `pkg/daemons/lcmgr/ethbc_diamond_contract.go`

- [x] 2.3.1 Add `mutationAgoraEngineDirectOrderManagerCreateExternallyIdentifiedBatchDirectOrderV2()` handler:
  - Parse ATS arguments: `external_id`, `pair_id`, `bid`, `directly_fillable`, `order_type`, `quantity`, `price`, `slippage`, `expire_ts`, `order_data`, `participant`, `investor`, `fee_payer`
  - Build `CreateDirectOrderParamsV2` struct (using Go bindings):
    - `paramsV1.Bid` = bid (bool)
    - `paramsV1.DirectlyFillable` = directly_fillable (bool)
    - `paramsV1.OrderType` = order_type (uint256: 1=LIMIT, 2=MARKET)
    - `paramsV1.Quantity` = quantity (uint256, already scaled by caller)
    - `paramsV1.Price` = price (uint256, already scaled by caller)
    - `paramsV1.Slippage` = slippage (uint256)
    - `paramsV1.ExpireTs` = expire_ts (uint256)
    - `paramsV1.Data` = order_data (bytes, UTF-8 JSON)
    - `Participant` = participant (address, from LASER slot translation)
    - `Investor` = investor (address, from LASER slot translation)
    - `FeePayer` = fee_payer (address, from LASER slot translation)
  - Build `paramsArr` as single-element array: `[]CreateDirectOrderParamsV2{params}`
  - Convert `pair_id` from hex string to `[32]byte`
  - Pack the call: `abi.Pack("createExternallyIdentifiedBatchDirectOrderV2", externalId, pairId, paramsArr)`
  - Execute via diamond proxy
  - Parse transaction receipt for `DirectOrderCreate2(uint256 eventId, bytes32 indexed pairId, uint256 indexed orderId)` event
  - Extract `orderId` from event topics
  - Return in mutation result metadata: `order_id` (uint256 decimal string), `pair_id` (bytes32 hex), `event_id` (uint256 decimal string)
- [x] 2.3.2 Add ABI loading for DirectOrderManagerV2 facet (from Go bindings or inline JSON)
- [x] 2.3.3 Handle the `DirectOrderCreate2` event parsing:
  - Event signature: `keccak256("DirectOrderCreate2(uint256,bytes32,uint256)")`
  - `pairId` from `Topics[1]` (indexed)
  - `orderId` from `Topics[2]` (indexed)
  - `eventId` from decoded data (non-indexed)
  - Store in result: `result.Metadata["order_id"]`, `result.Metadata["pair_id"]`, `result.Metadata["event_id"]`

**File**: `pkg/daemons/lcmgr/ledger/ethbc/mutator.go`

- [x] 2.4.1 Add the operation name to `isDiamondOperation()` switch statement
- [x] 2.4.2 Verify routing to `EthBCDiamondContract` handler in `getOrCreateContract()`

---

### Phase 3: Order Hash Function

**File**: `pkg/common/hash.go`

- [x] 3.1.1 Add `GetDirectOrderHash()` function (see "Order Hash Computation" section above)
- [x] 3.1.2 Add unit test for `GetDirectOrderHash()` in `pkg/common/hash_test.go`:
  - Verify deterministic output for same inputs
  - Verify different outputs for different inputs
  - Verify output format: `0x` prefix, lowercase hex, 96 characters (384 bits / 4 = 96 hex chars)

---

### Phase 4: Database Schema Updates

**File**: `deploy/k8s/init/init_listingmgr_pgsql.sql`

- [x] 4.1.1 Add `listingmgr.orders` table:
  ```sql
  CREATE TABLE IF NOT EXISTS listingmgr.orders (
      iid VARCHAR PRIMARY KEY,

      -- Order identifiers
      external_oid VARCHAR NOT NULL,                           -- Broker-generated external order ID
      exchange_oid VARCHAR NOT NULL UNIQUE,                    -- Listingmgr-generated unique order ID
      participant_oid VARCHAR NOT NULL,                        -- Participant-generated order ID

      -- On-chain identifiers
      pair_id VARCHAR NOT NULL,                                -- bytes32 hex - on-chain pair ID
      pair_oid VARCHAR,                                        -- uint256 decimal - on-chain orderId (NULL until confirmed)
      order_hash VARCHAR,                                      -- SHA-512/384 hex - universal order hash (NULL until computed)

      -- Listing references
      security_listing_iid VARCHAR NOT NULL,                   -- FK to security_listings
      security_listing_deployment_iid VARCHAR NOT NULL,        -- FK to security_listing_deployments

      -- Participant references
      participant_iid VARCHAR NOT NULL,                        -- Participant slot address (cash account)
      investor_iid VARCHAR NOT NULL,                           -- Investor slot address (beneficial owner)

      -- Order parameters
      side VARCHAR NOT NULL,                                   -- OrderSideEnum: ORDER_SIDE_ENUM_BID, ORDER_SIDE_ENUM_ASK
      order_type VARCHAR NOT NULL,                             -- OrderTypeEnum: ORDER_TYPE_ENUM_LIMIT, ORDER_TYPE_ENUM_MARKET
      quantity VARCHAR NOT NULL,                               -- Human-readable decimal quantity
      price VARCHAR NOT NULL,                                  -- Human-readable decimal price
      slippage VARCHAR NOT NULL DEFAULT '0',                   -- Slippage tolerance
      expire_timestamp VARCHAR NOT NULL,                       -- Unix timestamp (seconds)
      directly_fillable BOOLEAN NOT NULL DEFAULT FALSE,        -- Whether order can be directly filled

      -- Status and lifecycle
      status VARCHAR NOT NULL,                                 -- OrderStatusEnum

      -- Execution context
      on_chain_tx_hash VARCHAR,                                -- LASER mutation tx hash (NULL until submitted)
      saga_instance_id VARCHAR,                                -- TRAX saga instance ID
      idempotency_key VARCHAR NOT NULL,                        -- Idempotency key
      trace_id VARCHAR NOT NULL DEFAULT '',                    -- Distributed tracing ID
      execution_id VARCHAR NOT NULL DEFAULT '',                -- Execution pipeline ID
      exec_runtime_name VARCHAR NOT NULL,                      -- Execution runtime name

      -- Token/pair info (denormalized from SecurityListing/deployment for queries)
      symbol VARCHAR NOT NULL DEFAULT '',                      -- Base token symbol
      currency VARCHAR NOT NULL DEFAULT '',                    -- Quote token symbol (ISO 4217 where possible)

      -- Chain info (denormalized from execution runtime)
      chain_id VARCHAR NOT NULL DEFAULT '',                    -- Chain identifier
      chain_name VARCHAR NOT NULL DEFAULT '',                  -- Chain name (lowercase, no spaces)
      engine_addr VARCHAR NOT NULL DEFAULT '',                 -- Trading mechanism ETH address (bytes20 hex)

      -- Extra data
      data JSONB NOT NULL DEFAULT '{}'::jsonb,                 -- Additional JSON data (passed to on-chain)

      -- Standard JSONB fields
      display_names JSONB NOT NULL DEFAULT '{}'::jsonb,        -- map[string]string with locales
      labels JSONB NOT NULL DEFAULT '{}'::jsonb,               -- map[string]string
      tags JSONB NOT NULL DEFAULT '[]'::jsonb,                 -- []string
      metadata JSONB NOT NULL DEFAULT '{}'::jsonb,             -- map[string]string

      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

      -- Foreign keys
      CONSTRAINT fk_orders_entity
      FOREIGN KEY (iid) REFERENCES shared.entities(iid) ON DELETE CASCADE,

      CONSTRAINT fk_orders_security_listing
      FOREIGN KEY (security_listing_iid) REFERENCES listingmgr.security_listings(iid) ON DELETE CASCADE,

      CONSTRAINT fk_orders_security_listing_deployment
      FOREIGN KEY (security_listing_deployment_iid) REFERENCES listingmgr.security_listing_deployments(iid) ON DELETE CASCADE
  );
  ```

- [x] 4.1.2 Add indexes for `listingmgr.orders`:
  ```sql
  CREATE INDEX IF NOT EXISTS idx_orders_external_oid ON listingmgr.orders(external_oid);
  CREATE INDEX IF NOT EXISTS idx_orders_exchange_oid ON listingmgr.orders(exchange_oid);
  CREATE INDEX IF NOT EXISTS idx_orders_participant_oid ON listingmgr.orders(participant_oid);
  CREATE INDEX IF NOT EXISTS idx_orders_pair_id ON listingmgr.orders(pair_id);
  CREATE INDEX IF NOT EXISTS idx_orders_pair_oid ON listingmgr.orders(pair_oid);
  CREATE INDEX IF NOT EXISTS idx_orders_order_hash ON listingmgr.orders(order_hash);
  CREATE INDEX IF NOT EXISTS idx_orders_security_listing_iid ON listingmgr.orders(security_listing_iid);
  CREATE INDEX IF NOT EXISTS idx_orders_security_listing_deployment_iid ON listingmgr.orders(security_listing_deployment_iid);
  CREATE INDEX IF NOT EXISTS idx_orders_participant_iid ON listingmgr.orders(participant_iid);
  CREATE INDEX IF NOT EXISTS idx_orders_investor_iid ON listingmgr.orders(investor_iid);
  CREATE INDEX IF NOT EXISTS idx_orders_side ON listingmgr.orders(side);
  CREATE INDEX IF NOT EXISTS idx_orders_order_type ON listingmgr.orders(order_type);
  CREATE INDEX IF NOT EXISTS idx_orders_status ON listingmgr.orders(status);
  CREATE INDEX IF NOT EXISTS idx_orders_idempotency_key ON listingmgr.orders(idempotency_key);
  CREATE INDEX IF NOT EXISTS idx_orders_exec_runtime_name ON listingmgr.orders(exec_runtime_name);
  CREATE INDEX IF NOT EXISTS idx_orders_created_at ON listingmgr.orders(created_at DESC);
  CREATE INDEX IF NOT EXISTS idx_orders_display_names ON listingmgr.orders USING GIN(display_names);
  CREATE INDEX IF NOT EXISTS idx_orders_tags ON listingmgr.orders USING GIN(tags);
  CREATE INDEX IF NOT EXISTS idx_orders_metadata ON listingmgr.orders USING GIN(metadata);
  CREATE INDEX IF NOT EXISTS idx_orders_labels ON listingmgr.orders USING GIN(labels);
  ```

- [x] 4.1.3 Add `listingmgr.order_events` table (full PostgreSQL mirror of Cassandra order events):
  ```sql
  CREATE TABLE IF NOT EXISTS listingmgr.order_events (
      iid VARCHAR PRIMARY KEY,

      order_iid VARCHAR NOT NULL,                              -- FK to listingmgr.orders
      type VARCHAR NOT NULL,                                   -- OrderEventTypeEnum

      timestamp VARCHAR NOT NULL,                              -- ISO 8601 event timestamp

      -- Off-chain command context
      exchange_order_hash VARCHAR,                             -- bytes48 hex
      command_origin VARCHAR,                                  -- FIX, REST, TRAX, etc.
      command_operation VARCHAR,                                -- NewOrderSingle, etc.
      exec_msg VARCHAR,                                        -- Execution messages

      -- On-chain index info
      chain_id VARCHAR,
      chain_name VARCHAR,
      engine_addr VARCHAR,                                     -- bytes20 hex
      index_ts VARCHAR,                                        -- unix timestamp
      index_block_ts VARCHAR,                                  -- unix timestamp
      index_block_nr VARCHAR,                                  -- uint256 hex
      index_tx_hash VARCHAR,                                   -- bytes32 hex
      index_tx_log_idx BIGINT,

      -- Pair info
      pair_id VARCHAR,                                         -- bytes32 hex

      -- Event identity
      order_event_type INT,                                    -- Cassandra-compatible int (1-11, 201-223)
      order_event_version VARCHAR,
      order_event_ts BIGINT,
      order_event_id VARCHAR,                                  -- uint256 decimal
      order_event_hash VARCHAR,                                -- bytes48 hex
      order_event_data TEXT,                                   -- JSON encoded

      -- Order snapshot at time of event
      order_id VARCHAR,                                        -- uint256 decimal (on-chain)
      order_hash VARCHAR,                                      -- bytes48 hex
      order_trezor_stash_id VARCHAR,                           -- uint256 decimal
      order_is_offer BOOLEAN,
      order_offer_ids VARCHAR,                                 -- comma-separated uint256
      order_parent_direct_order_id VARCHAR,                    -- uint256 hex
      order_is_directly_fillable BOOLEAN,
      order_creator_addr VARCHAR,                              -- bytes20 hex
      order_quantity VARCHAR,                                  -- uint256 decimal (scaled)
      order_remaining_quantity VARCHAR,                        -- uint256 decimal (scaled)
      order_price VARCHAR,                                     -- uint256 decimal (scaled)
      order_volume VARCHAR,                                    -- uint256 decimal
      order_remaining_volume VARCHAR,                          -- uint256 decimal
      order_slippage VARCHAR,                                  -- uint256 decimal
      order_type VARCHAR,                                      -- order type string
      order_is_bid BOOLEAN,
      order_is_filled BOOLEAN,
      order_is_cancelled BOOLEAN,
      order_is_expired BOOLEAN,
      order_create_ts VARCHAR,                                 -- unix timestamp
      order_expire_ts VARCHAR,                                 -- unix timestamp
      order_alarm_abi VARCHAR,
      order_alarm_data VARCHAR,                                -- hex data
      order_data VARCHAR,                                      -- hex data

      -- Trade fields (for fill events)
      trade_id VARCHAR,                                        -- uint256 decimal
      trade_hash VARCHAR,                                      -- bytes48 hex
      trade_timestamp VARCHAR,                                 -- unix timestamp
      trade_creator_addr VARCHAR,                              -- bytes20 hex
      trade_type VARCHAR,
      trade_is_buy BOOLEAN,
      trade_bid_order_id VARCHAR,                              -- uint256 decimal
      trade_ask_order_id VARCHAR,                              -- uint256 decimal
      trade_bid_fee VARCHAR,                                   -- uint256 decimal
      trade_ask_fee VARCHAR,                                   -- uint256 decimal
      trade_quantity VARCHAR,                                  -- uint256 decimal
      trade_price VARCHAR,                                     -- uint256 decimal
      trade_volume VARCHAR,                                    -- uint256 decimal

      -- Standard JSONB fields
      display_names JSONB NOT NULL DEFAULT '{}'::jsonb,
      labels JSONB NOT NULL DEFAULT '{}'::jsonb,
      tags JSONB NOT NULL DEFAULT '[]'::jsonb,
      metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

      -- Foreign keys
      CONSTRAINT fk_order_events_entity
      FOREIGN KEY (iid) REFERENCES shared.entities(iid) ON DELETE CASCADE,

      CONSTRAINT fk_order_events_order
      FOREIGN KEY (order_iid) REFERENCES listingmgr.orders(iid) ON DELETE CASCADE
  );
  ```

- [x] 4.1.4 Add indexes for `listingmgr.order_events`:
  ```sql
  CREATE INDEX IF NOT EXISTS idx_order_events_order_iid ON listingmgr.order_events(order_iid);
  CREATE INDEX IF NOT EXISTS idx_order_events_type ON listingmgr.order_events(type);
  CREATE INDEX IF NOT EXISTS idx_order_events_pair_id ON listingmgr.order_events(pair_id);
  CREATE INDEX IF NOT EXISTS idx_order_events_order_event_type ON listingmgr.order_events(order_event_type);
  CREATE INDEX IF NOT EXISTS idx_order_events_order_id ON listingmgr.order_events(order_id);
  CREATE INDEX IF NOT EXISTS idx_order_events_order_hash ON listingmgr.order_events(order_hash);
  CREATE INDEX IF NOT EXISTS idx_order_events_index_tx_hash ON listingmgr.order_events(index_tx_hash);
  CREATE INDEX IF NOT EXISTS idx_order_events_trade_id ON listingmgr.order_events(trade_id);
  CREATE INDEX IF NOT EXISTS idx_order_events_created_at ON listingmgr.order_events(created_at DESC);
  CREATE INDEX IF NOT EXISTS idx_order_events_tags ON listingmgr.order_events USING GIN(tags);
  CREATE INDEX IF NOT EXISTS idx_order_events_metadata ON listingmgr.order_events USING GIN(metadata);
  ```

- [x] 4.1.5 Add SQL comments for new tables and key columns

---

### Phase 5: Store Interface & Implementations

**File**: `pkg/daemons/listingmgr/stores/listing_store.go`

- [x] 5.1.1 Add Order CRUD methods to `ListingStore` interface:
  ```go
  // Order operations
  CreateOrder(ctx context.Context, order *fin.Order) error
  GetOrder(ctx context.Context, iid string) (*fin.Order, error)
  GetOrderByExchangeOid(ctx context.Context, exchangeOid string) (*fin.Order, error)
  GetOrderByExternalOid(ctx context.Context, externalOid string) (*fin.Order, error)
  UpdateOrder(ctx context.Context, order *fin.Order) error
  ListOrders(ctx context.Context, limit, offset int) ([]*fin.Order, error)
  QueryOrders(ctx context.Context, options *common.QueryOptions) ([]*fin.Order, *common.QueryResponse, error)

  // OrderEvent operations
  CreateOrderEvent(ctx context.Context, event *fin.OrderEvent) error
  GetOrderEvent(ctx context.Context, iid string) (*fin.OrderEvent, error)
  ListOrderEventsByOrder(ctx context.Context, orderIid string, limit, offset int) ([]*fin.OrderEvent, error)
  QueryOrderEvents(ctx context.Context, options *common.QueryOptions) ([]*fin.OrderEvent, *common.QueryResponse, error)
  ```

**File**: `pkg/daemons/listingmgr/stores/postgres/listing_store.go`

- [x] 5.2.1 Implement `CreateOrder()` — INSERT into `shared.entities` + `listingmgr.orders`
- [x] 5.2.2 Implement `GetOrder()` — SELECT by IID
- [x] 5.2.3 Implement `GetOrderByExchangeOid()` — SELECT by exchange_oid
- [x] 5.2.4 Implement `GetOrderByExternalOid()` — SELECT by external_oid
- [x] 5.2.5 Implement `UpdateOrder()` — UPDATE by IID
- [x] 5.2.6 Implement `ListOrders()` — SELECT with pagination
- [x] 5.2.7 Implement `QueryOrders()` — QueryOptions-based query (follow accmgr/instrmgr pattern)
- [x] 5.2.8 Implement `CreateOrderEvent()` — INSERT into `shared.entities` + `listingmgr.order_events`
- [x] 5.2.9 Implement `GetOrderEvent()` — SELECT by IID
- [x] 5.2.10 Implement `ListOrderEventsByOrder()` — SELECT by order_iid with pagination
- [x] 5.2.11 Implement `QueryOrderEvents()` — QueryOptions-based query

**File**: `pkg/daemons/listingmgr/stores/memory/listing_store.go`

- [x] 5.3.1 Implement all Order and OrderEvent methods for in-memory store (thread-safe with RWMutex)

---

### Phase 6: Saga Step Executors

**Directory**: `pkg/daemons/listingmgr/trax/executors/create_direct_order/` (NEW)

#### Step 1: cdo_validate_and_resolve
**File**: `validate_and_resolve.go`

- [x] 6.1.1 Validate all required inputs exist and are non-empty
- [x] 6.1.2 Validate `external_oid` format: `[a-zA-Z0-9\-_+/\\]{16,}`
- [x] 6.1.3 Validate `participant_oid` format: `part_oid_{[a-zA-Z0-9\-_+/\\]{32}}`
- [x] 6.1.4 Validate `order_type`: must be `ORDER_TYPE_ENUM_LIMIT` or `ORDER_TYPE_ENUM_MARKET`
- [x] 6.1.5 Validate `side`: must be `ORDER_SIDE_ENUM_BID` or `ORDER_SIDE_ENUM_ASK`
- [x] 6.1.6 Validate `quantity` > 0 (parse as decimal)
- [x] 6.1.7 Validate `price`: > 0 for LIMIT, must be "0" for MARKET
- [x] 6.1.8 Validate `expire_timestamp` is a valid Unix timestamp in the future
- [x] 6.1.9 Validate `slippage` is a non-negative integer (default "0")
- [x] 6.1.10 Validate `directly_fillable` is "true" or "false" (default "false")
- [x] 6.1.11 Query listingmgr store: find `SecurityListingDeployment` for `security_listing_iid` + `exec_runtime_name`
  - List deployments by listing IID
  - Filter by `DeploymentDetails.ExecutionRuntimeName == exec_runtime_name`
  - If no deployment found, FAIL with "no deployment found for security listing on execution runtime"
- [x] 6.1.12 Extract `pair_id` from `DeploymentDetails.AgoraPairId`
- [x] 6.1.13 Extract `trading_mechanism_slot_address` from `DeploymentDetails.TradingMechanismSlotAddress`
- [x] 6.1.14 Extract `security_listing_deployment_iid` from the found deployment
- [x] 6.1.15 Query accmgr `GET /principal-legal-structure`:
  - If PLEGP not configured, FAIL with "PLEGP not configured"
  - Extract `principal_legal_structure_iid` and `principal_participant_iid`
- [x] 6.1.16 Verify trading mechanism belongs to PLEGP:
  - Query accmgr `GET /legal-structures/{pls_iid}/mechanisms?type=LEGAL_MECHANISM_TYPE_ENUM_TRADING`
  - For each mechanism, check deployments for matching `trading_mechanism_slot_address`
  - If no match, FAIL with "trading mechanism does not belong to PLEGP"
- [x] 6.1.17 Calendar check:
  - Get `SecurityListing` by `security_listing_iid`
  - If `CalendarIid` is not empty, query calendar
  - If calendar has entries, check if current time falls within operating hours
  - If outside operating hours, FAIL with "exchange is not operating at this time"
  - If calendar is empty, assume 24/7 operation (pass)
- [x] 6.1.18 Query instrmgr for base token (security) decimals:
  - Extract `security_identifier` from `SecurityListing`
  - Query instrmgr by fin_id_str for the authorized instrument
  - Extract `decimals` from instrument metadata or default config
- [x] 6.1.19 Query instrmgr for quote token (cash token) decimals:
  - Extract `currency_identifier` from `SecurityListing`
  - Query instrmgr by fin_id_str for the cash token
  - Extract `decimals` from instrument metadata or default config
- [x] 6.1.20 Resolve PLEGP admin partner, authz admin, and trading engine AuthzDiamond:
  - Reuse pattern from `ssl_resolve_fee_collector`: `findPartnerAddresses()`, `findAuthzSourceSlotAddress()`
  - Return `admin_partner_slot_address`, `exchange_authz_admin_slot_address`, `trading_engine_authz_diamond_slot_addr`
- [x] 6.1.21 Return step result:
  ```
  pair_id, trading_mechanism_slot_address, security_listing_deployment_iid,
  admin_partner_slot_address, exchange_authz_admin_slot_address,
  trading_engine_authz_diamond_slot_addr, base_token_decimals,
  quote_token_decimals, security_display_name, cash_token_display_name,
  symbol, currency, chain_id, chain_name
  ```
- [x] 6.1.22 COMP: No-op (read-only validation/resolution)

#### Step 2: cdo_submit_order_on_chain
**File**: `submit_order_on_chain.go`

- [x] 6.2.1 Extract all parameters from step 1 output and saga input
- [x] 6.2.2 Scale `quantity` by `base_token_decimals`:
  - Parse quantity as big.Float
  - Multiply by 10^base_token_decimals
  - Verify result is an integer (no excess decimal places)
  - Convert to big.Int string
- [x] 6.2.3 Scale `price` by `quote_token_decimals`:
  - Same pattern as quantity scaling
- [x] 6.2.4 Map `side`: BID -> "true", ASK -> "false"
- [x] 6.2.5 Map `order_type`: LIMIT -> "1", MARKET -> "2"
- [x] 6.2.6 Serialize `data` JSON:
  ```go
  dataObj := map[string]string{
      "external_oid":     input["external_oid"],
      "participant_oid":  input["participant_oid"],
      "exchange_oid":     "",  // not yet generated
      "pair_oid":         "",  // not yet known
      "idempotency_key":  input["idempotency_key"],
      "trace_id":         input["trace_id"],
      "execution_id":     input["execution_id"],
      "saga_instance_id": "", // from TRAX context if available
      "participant_iid":  input["participant_iid"],
      "investor_iid":     input["investor_iid"],
      "pair_id":          input["pair_id"],
  }
  dataJSON, _ := json.Marshal(dataObj)
  dataBytes := string(dataJSON)  // UTF-8 bytes
  ```
- [x] 6.2.7 Build ATS function declaration for the operation:
  ```go
  funcDecl := ats.Func(string(model.OperationNameEnum_AgoraEngineDirectOrderManagerCreateExternallyIdentifiedBatchDirectOrderV2)).
      Arguments(
          ats.String(string(ats.ArgNameEnum_ExternalId)).Build(),
          ats.String(string(ats.ArgNameEnum_PairId)).Build(),
          ats.String(string(ats.ArgNameEnum_Bid)).Build(),
          ats.String(string(ats.ArgNameEnum_DirectlyFillable)).Build(),
          ats.String(string(ats.ArgNameEnum_OrderType)).Build(),
          ats.String(string(ats.ArgNameEnum_Quantity)).Build(),
          ats.String(string(ats.ArgNameEnum_Price)).Build(),
          ats.String(string(ats.ArgNameEnum_Slippage)).Build(),
          ats.String(string(ats.ArgNameEnum_ExpireTs)).Build(),
          ats.String(string(ats.ArgNameEnum_OrderData)).Build(),
          ats.String(string(ats.ArgNameEnum_Participant)).Build(),
          ats.String(string(ats.ArgNameEnum_Investor)).Build(),
          ats.String(string(ats.ArgNameEnum_FeePayer)).Build(),
      ).Build()
  ```
  **Note**: All arguments as String for lcmgr `extractStringArg` compatibility (same pattern as `ssl_create_pair_on_chain`).
- [x] 6.2.8 Build bound arguments with values
- [x] 6.2.9 Build LASER async mutation request:
  ```go
  mutationReq := map[string]interface{}{
      "mutate_id":         fmt.Sprintf("mut_id_create-batch-direct-order-v2-%s", idempotentKey),
      "idempotency_key":   idempotentKey,
      "from_slot_address": adminPartnerSlotAddr,      // PLEGP admin partner (authorized caller)
      "to_slot_address":   tradingMechSlotAddr,        // Agora Engine diamond
      "call_data": map[string]interface{}{
          "decl":      boundFunc.Decl,
          "arguments": boundFunc.Arguments,
          "returns":   []ats.BoundVariable{},
      },
      "metadata": map[string]string{
          "saga_step": "cdo_submit_order_on_chain",
      },
      "async": true,
  }
  ```
- [x] 6.2.10 POST mutation to LASER (reuse `submitAndPollLaserMutation` from `laser_helpers.go`)
- [x] 6.2.11 Extract `order_id` (pair_oid) from poll result metadata
- [x] 6.2.12 Extract `tx_hash` from poll result
- [x] 6.2.13 Return step result:
  ```
  pair_oid (order_id), on_chain_tx_hash, event_id
  ```
- [x] 6.2.14 COMP: No-op (on-chain order creation cannot be reversed; log warning)

#### Step 3: cdo_create_order_record
**File**: `create_order_record.go`

- [x] 6.3.1 Generate `exchange_oid`: `fmt.Sprintf("exch_oid_%s", common.SecureRandomString(32))`
- [x] 6.3.2 Generate order IID: `fmt.Sprintf("order_%s", common.SecureRandomString(32))`
- [x] 6.3.3 Compute `order_hash` using `common.GetDirectOrderHash()`:
  - `chainId` from step 1 output
  - `chainName` from step 1 output
  - `engineAddr`: trading mechanism ETH address (need to resolve from LASER or step 1 output)
  - `pairId` from step 1 output
  - `orderId` (pair_oid) from step 2 output
  - `externalOid` from saga input
  - `exchangeOid` from generated value above
- [x] 6.3.4 Build `fin.Order` struct with all fields:
  - Status = `OrderStatusEnum_New` (on-chain confirmed by step 2 success)
  - All saga input fields
  - All step 1 resolved fields (pair_id, symbol, currency, chain_id, chain_name, engine_addr, deployment_iid)
  - All step 2 output fields (pair_oid, on_chain_tx_hash)
  - DisplayNames: `{locale: "Order: {side} {quantity} {symbol}/{currency} @ {price}"}`
  - Tags: `["order", "direct-order", side, order_type]`
  - Metadata: `created_by_saga`, `idempotency_key`, `external_oid`, `participant_oid`
- [x] 6.3.5 Call `pkgListingStore.CreateOrder(ctx, order)`
- [x] 6.3.6 Generate order event IID: `fmt.Sprintf("order_event_%s", common.SecureRandomString(32))`
- [x] 6.3.7 Build initial `fin.OrderEvent`:
  - Type = `OrderEventTypeEnum_Create`
  - OrderIid = order IID
  - Timestamp = current time (ISO 8601)
  - order_event_type = 1 (Create, Cassandra-compatible)
  - chain_id, chain_name, engine_addr, pair_id from step 1
  - index_tx_hash from step 2
  - order_id = pair_oid from step 2
  - order_hash = computed hash
  - order_quantity, order_price, order_type, order_is_bid, etc. from saga input
  - command_origin = "TRAX" (saga-originated)
  - command_operation = "NewOrderSingle"
- [x] 6.3.8 Call `pkgListingStore.CreateOrderEvent(ctx, event)`
- [x] 6.3.9 Return step result:
  ```
  exchange_oid, pair_oid, pair_id, order_hash, order_iid, order_event_iid
  ```
- [x] 6.3.10 COMP: Delete order event and order record from listingmgr store

#### Executor Registration
**File**: `saga.go`

- [x] 6.4.1 Define `sagaTemplateId = "create_direct_order"`
- [x] 6.4.2 Create package-level variables:
  ```go
  var (
      pkgListingStore    stores.ListingStore
      pkgAccMgrBaseURL   string
      pkgInstrMgrBaseURL string
      pkgLaserBaseURL    string
      pkgLaserAuthKey    string
  )
  ```
- [x] 6.4.3 Create `RunExecutorsAsync()`:
  ```go
  go run_ValidateAndResolve_Executor(ctx, mqClient, clusterId)
  time.Sleep(30 * time.Millisecond)
  go run_SubmitOrderOnChain_Executor(ctx, mqClient, clusterId)
  time.Sleep(30 * time.Millisecond)
  go run_CreateOrderRecord_Executor(ctx, mqClient, clusterId)
  ```
- [x] 6.4.4 Create `UpdateListingStore(store stores.ListingStore)` for E2E test database switching

**File**: `laser_helpers.go`

- [x] 6.4.5 Copy/reuse `submitAndPollLaserMutation`, `queryCrownExecutorIid`, `LaserMutationResult` from `setup_security_listing/laser_helpers.go` — or extract to a shared helper package under `pkg/daemons/listingmgr/trax/helpers/` to avoid duplication

**File**: `pkg/daemons/listingmgr/trax/executors/run.go`

- [x] 6.4.6 Update `RunExecutorsAsync()` to also call `create_direct_order.RunExecutorsAsync()`
- [x] 6.4.7 Update `UpdateListingStore()` to also call `create_direct_order.UpdateListingStore()`

---

### Phase 7: REST API Endpoints

**File**: `pkg/daemons/listingmgr/api/v1/orders_post_create_direct.go` (NEW)

- [x] 7.1.1 Create `createDirectOrderRequest` struct:
  ```go
  type createDirectOrderRequest struct {
      ExternalOid       string `json:"external_oid" binding:"required"`
      ParticipantOid    string `json:"participant_oid" binding:"required"`
      ExecRuntimeName   string `json:"exec_runtime_name" binding:"required"`
      SecurityListingIid string `json:"security_listing_iid" binding:"required"`
      ParticipantIid    string `json:"participant_iid" binding:"required"`
      InvestorIid       string `json:"investor_iid" binding:"required"`
      OrderType         string `json:"order_type" binding:"required"`
      Quantity          string `json:"quantity" binding:"required"`
      Price             string `json:"price" binding:"required"`
      Side              string `json:"side" binding:"required"`
      IdempotencyKey    string `json:"idempotency_key" binding:"required"`
      ExpireTimestamp   string `json:"expire_timestamp" binding:"required"`
      DirectlyFillable  string `json:"directly_fillable"`
      Slippage          string `json:"slippage"`
      TraceId           string `json:"trace_id"`
      ExecutionId       string `json:"execution_id"`
      Data              string `json:"data"`
  }
  ```
- [x] 7.1.2 Create `createDirectOrderResponse` struct:
  ```go
  type createDirectOrderResponse struct {
      SagaInstanceId string `json:"saga_instance_id"`
      Status         string `json:"status"`
  }
  ```
- [x] 7.1.3 Implement `postCreateDirectOrder(c *gin.Context)` handler:
  - Bind JSON body
  - **Pre-checks** (all 8):
    1. Required fields present (Gin binding)
    2. `SecurityListingDeployment` exists for `security_listing_iid` + `exec_runtime_name`
    3. Calendar check: basic operating hours
    4. Participant/investor authorization check (verify they exist)
    5. PLEGP configured (query accmgr `GET /principal-legal-structure`)
    6. `idempotency_key` present (already covered by binding:"required")
    7. Enum validation: `order_type` is `ORDER_TYPE_ENUM_LIMIT` or `ORDER_TYPE_ENUM_MARKET`, `side` is `ORDER_SIDE_ENUM_BID` or `ORDER_SIDE_ENUM_ASK`
    8. `expire_timestamp` is in the future; `quantity` > 0; `price` > 0 for LIMIT, = 0 for MARKET
  - Set defaults: `directly_fillable` = "false", `slippage` = "0", `data` = "{}"
  - Build saga input `map[string]string`
  - Submit saga via `traxSagaSubmitter.SubmitSaga()` with template `create_direct_order`
  - Return `201 Created` with `{saga_instance_id, status: "SUBMITTED"}`
- [x] 7.1.4 On validation failure, return 400 with descriptive error message (fail immediately, no fallback)

**File**: `pkg/daemons/listingmgr/api/v1/orders_get.go` (NEW)

- [x] 7.2.1 Implement `GET /api/v1/orders` — list with pagination:
  - Query params: `limit`, `offset`, `security_listing_iid`, `participant_iid`, `investor_iid`, `side`, `order_type`, `status`
  - Returns: `{orders: [...], total: N}`
- [x] 7.2.2 Implement `GET /api/v1/orders/:iid` — get by IID
- [x] 7.2.3 Implement `GET /api/v1/orders?exchange_oid={oid}` — get by exchange_oid
- [x] 7.2.4 Implement `GET /api/v1/orders?external_oid={oid}` — get by external_oid
- [x] 7.2.5 Implement `GET /api/v1/orders/query` — QueryOptions-based endpoint (follow accmgr/instrmgr pattern)

**File**: `pkg/daemons/listingmgr/api/v1/order_events_get.go` (NEW)

- [x] 7.3.1 Implement `GET /api/v1/order-events?order_iid={iid}` — list events by order
- [x] 7.3.2 Implement `GET /api/v1/order-events/:iid` — get single event by IID
- [x] 7.3.3 Implement `GET /api/v1/order-events/query` — QueryOptions-based endpoint

**File**: `pkg/daemons/listingmgr/api/v1/api.go`

- [x] 7.4.1 Register route: `POST /api/v1/orders/create-direct` -> `postCreateDirectOrder`
- [x] 7.4.2 Register route: `GET /api/v1/orders` -> `getOrders`
- [x] 7.4.3 Register route: `GET /api/v1/orders/:iid` -> `getOrderByIid`
- [x] 7.4.4 Register route: `GET /api/v1/orders/query` -> `queryOrders`
- [x] 7.4.5 Register route: `GET /api/v1/order-events` -> `getOrderEvents`
- [x] 7.4.6 Register route: `GET /api/v1/order-events/:iid` -> `getOrderEventByIid`
- [x] 7.4.7 Register route: `GET /api/v1/order-events/query` -> `queryOrderEvents`
- [x] 7.4.8 **Important**: No DELETE or PUT endpoints for orders (orders cannot be deleted or modified via REST)

---

### Phase 8: Saga Template SQL

**File**: `deploy/k8s/init/csd/min/trax.sql`

- [x] 8.1.1 Add saga template INSERT for `create_direct_order`:
  ```sql
  -- ============================================================================
  -- SAGA TEMPLATE: create_direct_order
  -- ============================================================================
  -- Description: Submits a new trading order to an Agora Engine trading pair via
  --              createExternallyIdentifiedBatchDirectOrderV2. Validates inputs,
  --              resolves PLEGP, checks calendar, submits on-chain, and records
  --              the order in listingmgr.
  -- Steps: 3
  -- ============================================================================

  INSERT INTO trax.saga_templates (
      template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
  ) VALUES (
      'create_direct_order',
      'Create Direct Order',
      'Submits a new direct trading order via createExternallyIdentifiedBatchDirectOrderV2 on Agora Engine',
      '{"short_id": "cdo"}'::jsonb,
      '["agora", "csd", "saga", "order", "direct-order", "trading", "listingmgr", "trax-flow"]'::jsonb,
      '{}'::jsonb,
      '["cdo_validate_and_resolve", "cdo_submit_order_on_chain", "cdo_create_order_record"]'::jsonb
  ) ON CONFLICT (template_id) DO UPDATE SET
      display_name = EXCLUDED.display_name,
      description = EXCLUDED.description,
      labels = EXCLUDED.labels,
      tags = EXCLUDED.tags,
      metadata = EXCLUDED.metadata,
      saga_step_template_ids = EXCLUDED.saga_step_template_ids;
  ```
- [x] 8.1.2 Add 3 saga step template INSERTs:
  - `cdo_validate_and_resolve` (index 1, service: listingmgr)
  - `cdo_submit_order_on_chain` (index 2, service: listingmgr)
  - `cdo_create_order_record` (index 3, service: listingmgr)
- [x] 8.1.3 Update file header comment to include `create_direct_order` in the list

**File**: `deploy/k8s/init/prtagent/min/trax.sql`

- [x] 8.2.1 Add `create_direct_order` saga template and step templates for prtagent flavor

**File**: `deploy/k8s/init/exchange/min/trax.sql`

- [x] 8.3.1 Add `create_direct_order` saga template and step templates for exchange flavor

---

### Phase 9: listingmgr Daemon Updates

**File**: `pkg/daemons/listingmgr.go`

- [x] 9.1.1 Add environment variable: `INSTRUMENT_MANAGER_BASE_URL` (for querying token decimals)
- [x] 9.1.2 Pass `instrMgrBaseURL` to create_direct_order executor package
- [x] 9.1.3 Call `create_direct_order.RunExecutorsAsync()` alongside existing `setup_security_listing.RunExecutorsAsync()`

---

### Phase 10: E2E Tests (ethbc mode)

**File**: `tests/e2e/laser/create_direct_order_test.go` (NEW)

#### Test Setup

- [ ] 10.1.1 `setupTestDatabaseForCreateDirectOrder(t)`:
  - Reuse existing Diamond test setup (E1/E2 executor configuration)
  - Initialize listingmgr schema
  - Update listingmgr executor stores for test database
  - Pre-deploy required facets to lattice archive (including `AgoraEngineDirectOrderManagerV2Facet`)
  - Deploy a full legal participant (PLEGP) via `setup_new_legal_participant` with `force_creation_of_trading_mechanism=true`
  - Issue a security token and a cash token via `process_new_instrument_authorization`
  - Deploy a security listing via `setup_security_listing` saga (creates on-chain pair)
  - Create investor account and fund it (for order submission)
  - Return: all required IIDs and slot addresses for order creation

#### Green Path Tests

- [ ] 10.2.1 `TestCreateDirectOrder_LimitBid`:
  - Submit LIMIT BID order with valid quantity, price, expire_timestamp
  - Wait for saga completion
  - Verify saga status = COMMITTED
  - Query listingmgr: verify Order record exists with status=NEW
  - Verify exchange_oid format: `exch_oid_{32 chars}`
  - Verify pair_oid is a valid uint256 decimal
  - Verify order_hash is a valid hex string with 0x prefix
  - Verify OrderEvent record exists with type=CREATE

- [ ] 10.2.2 `TestCreateDirectOrder_LimitAsk`:
  - Submit LIMIT ASK order
  - Same verifications as LimitBid but with side=ASK

- [ ] 10.2.3 `TestCreateDirectOrder_MarketBid`:
  - Submit MARKET BID order (price=0)
  - Verify saga completion and order record

- [ ] 10.2.4 `TestCreateDirectOrder_VerifyOnChainOrder`:
  - After order creation, query on-chain order state via Anvil JSON-RPC
  - Call `getOrderV2s(pairId, [orderId])` on the Agora Engine diamond
  - Verify order fields: bid, orderType, quantity (scaled), price (scaled), expireTs, participant, investor
  - Verify order data field contains the serialized JSON

- [ ] 10.2.5 `TestCreateDirectOrder_VerifyOrderHash`:
  - Create an order
  - Independently compute the order hash using `GetDirectOrderHash()` with the same inputs
  - Verify it matches the hash stored in the order record

- [ ] 10.2.6 `TestCreateDirectOrder_RESTQueryEndpoints`:
  - Create multiple orders with different parameters
  - Query `GET /api/v1/orders` — verify list returns all orders
  - Query `GET /api/v1/orders/:iid` — verify single order
  - Query `GET /api/v1/orders?exchange_oid=...` — verify by exchange_oid
  - Query `GET /api/v1/orders?external_oid=...` — verify by external_oid
  - Query `GET /api/v1/orders/query` with filters — verify QueryOptions
  - Query `GET /api/v1/order-events?order_iid=...` — verify events

#### Red Path Tests

- [ ] 10.3.1 `TestCreateDirectOrder_MissingRequiredField`:
  - Submit order with missing `external_oid`
  - Verify REST endpoint returns 400 immediately (pre-saga check)

- [ ] 10.3.2 `TestCreateDirectOrder_InvalidOrderType`:
  - Submit order with `order_type = "INVALID"`
  - Verify 400 response

- [ ] 10.3.3 `TestCreateDirectOrder_InvalidSide`:
  - Submit order with `side = "INVALID"`
  - Verify 400 response

- [ ] 10.3.4 `TestCreateDirectOrder_ExpiredTimestamp`:
  - Submit order with `expire_timestamp` in the past
  - Verify 400 response

- [ ] 10.3.5 `TestCreateDirectOrder_ZeroQuantity`:
  - Submit order with `quantity = "0"`
  - Verify 400 response

- [ ] 10.3.6 `TestCreateDirectOrder_MarketOrderWithPrice`:
  - Submit MARKET order with `price = "10.5"`
  - Verify 400 response (MARKET orders must have price=0)

- [ ] 10.3.7 `TestCreateDirectOrder_LimitOrderZeroPrice`:
  - Submit LIMIT order with `price = "0"`
  - Verify 400 response (LIMIT orders must have price > 0)

- [ ] 10.3.8 `TestCreateDirectOrder_NonExistentDeployment`:
  - Submit order with `security_listing_iid` that has no deployment for `exec_runtime_name`
  - Verify 400 response from REST pre-check

- [ ] 10.3.9 `TestCreateDirectOrder_PLEGPNotConfigured`:
  - Submit order when PLEGP is not configured
  - Verify 400 response from REST pre-check

- [ ] 10.3.10 `TestCreateDirectOrder_ExchangeNotOperating`:
  - Create a calendar with entries that exclude the current time
  - Submit order
  - Verify saga FAILS in step 1 with "exchange is not operating" error

- [ ] 10.3.11 `TestCreateDirectOrder_NoDeleteOrModify`:
  - Attempt `DELETE /api/v1/orders/:iid` — verify 404 or 405 (route not registered)
  - Attempt `PUT /api/v1/orders/:iid` — verify 404 or 405 (route not registered)

**File**: `Makefile`

- [ ] 10.4.1 Add test pattern to appropriate E2E category (suggest new category or extend existing):
  - Option A: New category for order creation tests
  - Option B: Add to an existing category based on complexity (probably 4-star)
  - Pattern: `TestCreateDirectOrder`

**File**: `docs/E2E_TEST_CATALOG.md`

- [ ] 10.4.2 Add new test group for Create Direct Order tests with complexity rating, test functions, and Makefile target

---

### Phase 11: Documentation Updates

**File**: `docs/SUMMARY-FOR-AGENT.md`

- [ ] 11.1.1 Add `create_direct_order` to the list of major sagas with brief description
- [ ] 11.1.2 Add listingmgr order management endpoints reference
- [ ] 11.1.3 Document `GetDirectOrderHash()` function

**File**: `docs/TODO.md`

- [ ] 11.2.1 Add TODO item: "Implement listingmgr PostgreSQL order status/events sync from on-chain events (either extend existing Cassandra indexer to also write to listingmgr PostgreSQL, or create new RabbitMQ consumer in listingmgr that subscribes to the same order event exchange)"
- [ ] 11.2.2 Update TODO item for calendar events to reflect that Calendar REST endpoints now exist (Phase 12)

---

### Phase 12: Calendar REST Endpoints (prerequisite for calendar check in Step 1)

**Context**: The `create_direct_order` saga (Step 1 `cdo_validate_and_resolve`) checks the SecurityListing's `calendar_iid` to determine operating hours. Currently the infrastructure is incomplete:
- **Exists**: `fin.Calendar` + `fin.CalendarEntry` domain models, `shared.calendars` + `shared.calendar_entries` PostgreSQL tables, `ListingStore.CreateCalendar()` + `ListingStore.GetCalendarByIid()` store methods
- **Missing**: Update/Delete/List/Query store methods for Calendar, full CRUD for CalendarEntry, zero REST endpoints

Without these endpoints, there is no way to create or manage calendars that the saga depends on.

#### 12.1 Extend ListingStore Interface

**File**: `pkg/daemons/listingmgr/stores/listing_store.go`

- [x] 12.1.1 Add Calendar store methods (existing: `CreateCalendar`, `GetCalendarByIid`):
  ```go
  // Calendar operations (shared.calendars table) — existing
  CreateCalendar(ctx context.Context, calendar *fin.Calendar) error
  GetCalendarByIid(ctx context.Context, iid string) (*fin.Calendar, error)

  // Calendar operations — new
  UpdateCalendar(ctx context.Context, calendar *fin.Calendar) error
  DeleteCalendar(ctx context.Context, iid string) error
  QueryCalendars(ctx context.Context, options *common.QueryOptions) ([]*fin.Calendar, *common.QueryResponse, error)
  ```

- [x] 12.1.2 Add CalendarEntry store methods (all new):
  ```go
  // CalendarEntry operations (shared.calendar_entries table)
  CreateCalendarEntry(ctx context.Context, entry *fin.CalendarEntry) error
  GetCalendarEntryByIid(ctx context.Context, iid string) (*fin.CalendarEntry, error)
  UpdateCalendarEntry(ctx context.Context, entry *fin.CalendarEntry) error
  DeleteCalendarEntry(ctx context.Context, iid string) error
  ListCalendarEntriesByCalendar(ctx context.Context, calendarIid string, limit, offset int) ([]*fin.CalendarEntry, error)
  QueryCalendarEntries(ctx context.Context, options *common.QueryOptions) ([]*fin.CalendarEntry, *common.QueryResponse, error)
  ```

#### 12.2 Implement PostgreSQL Store

**File**: `pkg/daemons/listingmgr/stores/postgres/listing_store.go`

- [x] 12.2.1 Implement `UpdateCalendar` — UPDATE shared.calendars SET display_names, descriptions, labels, tags, metadata, updated_at WHERE iid = $1
- [x] 12.2.2 Implement `DeleteCalendar` — DELETE FROM shared.entities WHERE iid = $1 (cascades to shared.calendars)
- [x] 12.2.3 Implement `QueryCalendars` — follow same QueryOptions pattern as `QuerySecurityListings` (pagination, sorting, search on display_names)
- [x] 12.2.4 Implement `CreateCalendarEntry` — INSERT INTO shared.entities + INSERT INTO shared.calendar_entries (entity_type = `ENTITY_TYPE_ENUM_CALENDAR_ENTRY`)
- [x] 12.2.5 Implement `GetCalendarEntryByIid` — SELECT from shared.calendar_entries WHERE iid = $1
- [x] 12.2.6 Implement `UpdateCalendarEntry` — UPDATE shared.calendar_entries SET type, operational_status, start_ts_ms, end_ts_ms, is_all_day, display_names, descriptions, labels, tags, metadata, updated_at WHERE iid = $1
- [x] 12.2.7 Implement `DeleteCalendarEntry` — DELETE FROM shared.entities WHERE iid = $1 (cascades)
- [x] 12.2.8 Implement `ListCalendarEntriesByCalendar` — SELECT from shared.calendar_entries WHERE calendar_iid = $1 ORDER BY start_ts_ms
- [x] 12.2.9 Implement `QueryCalendarEntries` — QueryOptions pattern with pagination, sorting, search, filter by calendar_iid

#### 12.3 Implement In-Memory Store

**File**: `pkg/daemons/listingmgr/stores/memory/listing_store.go`

- [x] 12.3.1 Add `calendarEntries map[string]*fin.CalendarEntry` field
- [x] 12.3.2 Implement all Calendar methods (Update, Delete, Query)
- [x] 12.3.3 Implement all CalendarEntry methods (Create, Get, Update, Delete, List, Query)

#### 12.4 Calendar REST Endpoints

**File**: `pkg/daemons/listingmgr/api/v1/calendars_post_create.go`

- [x] 12.4.1 `POST /api/v1/calendars` — Create a new calendar
  - Request body: `{ "iid": "...", "display_names": {...}, "descriptions": {...}, "labels": {...}, "tags": [...], "metadata": {...} }`
  - Creates shared.entities record (entity_type = `ENTITY_TYPE_ENUM_CALENDAR`) + shared.calendars record
  - Returns 201 with created calendar

**File**: `pkg/daemons/listingmgr/api/v1/calendars_get.go`

- [x] 12.4.2 `GET /api/v1/calendars` — List/query calendars with pagination
  - Query params: `limit`, `offset`, `order_by`, `order_direction`, `search`
  - Uses `QueryCalendars` with QueryOptions pattern
  - Returns `{ "calendars": [...], "total": N, "limit": N, "offset": N }`

- [x] 12.4.3 `GET /api/v1/calendars/:iid` — Get calendar by IID
  - Returns the calendar with its entries populated
  - 404 if not found

- [x] 12.4.4 `GET /api/v1/calendars/:iid/entries` — List entries for a calendar
  - Query params: `limit`, `offset`
  - Uses `ListCalendarEntriesByCalendar`
  - Returns `{ "calendar_entries": [...], "total": N, "limit": N, "offset": N }`

**File**: `pkg/daemons/listingmgr/api/v1/calendars_put_update.go`

- [x] 12.4.5 `PUT /api/v1/calendars/:iid` — Update calendar metadata
  - Request body: same as create (minus iid)
  - Returns 200 with updated calendar

**File**: `pkg/daemons/listingmgr/api/v1/calendars_delete.go`

- [x] 12.4.6 `DELETE /api/v1/calendars/:iid` — Delete calendar (cascades to entries)
  - Check that no SecurityListing references this calendar_iid before deleting (return 409 Conflict if in use)
  - Returns 204

**File**: `pkg/daemons/listingmgr/api/v1/calendar_entries_post_create.go`

- [x] 12.4.7 `POST /api/v1/calendar-entries` — Create a new calendar entry
  - Request body: `{ "iid": "...", "calendar_iid": "...", "type": "...", "operational_status": "...", "start_ts_ms": N, "end_ts_ms": N, "is_all_day": bool, "display_names": {...}, ... }`
  - Validates that `calendar_iid` references an existing calendar
  - Validates `start_ts_ms < end_ts_ms`
  - Validates `type` is a valid CalendarEntryTypeEnum
  - Validates `operational_status` is a valid CalendarEntryOperationalStatusEnum
  - Returns 201

**File**: `pkg/daemons/listingmgr/api/v1/calendar_entries_get.go`

- [x] 12.4.8 `GET /api/v1/calendar-entries` — List/query calendar entries
  - Query params: `limit`, `offset`, `order_by`, `order_direction`, `search`, `calendar_iid` (optional filter)
  - Uses `QueryCalendarEntries`

- [x] 12.4.9 `GET /api/v1/calendar-entries/:iid` — Get calendar entry by IID
  - 404 if not found

**File**: `pkg/daemons/listingmgr/api/v1/calendar_entries_put_update.go`

- [x] 12.4.10 `PUT /api/v1/calendar-entries/:iid` — Update calendar entry
  - Same validations as create
  - Returns 200

**File**: `pkg/daemons/listingmgr/api/v1/calendar_entries_delete.go`

- [x] 12.4.11 `DELETE /api/v1/calendar-entries/:iid` — Delete calendar entry
  - Returns 204

#### 12.5 Register Calendar Routes

**File**: `pkg/daemons/listingmgr/api/v1/api.go`

- [x] 12.5.1 Add calendar routes to `Init()`:
  ```go
  // Calendar endpoints
  r.POST(ApiV1UriPrefix+"/calendars", postCreateCalendar)
  r.GET(ApiV1UriPrefix+"/calendars", getCalendars)
  r.GET(ApiV1UriPrefix+"/calendars/:iid", getCalendarById)
  r.PUT(ApiV1UriPrefix+"/calendars/:iid", putUpdateCalendar)
  r.DELETE(ApiV1UriPrefix+"/calendars/:iid", deleteCalendarById)
  r.GET(ApiV1UriPrefix+"/calendars/:iid/entries", getCalendarEntriesByCalendarId)

  // CalendarEntry endpoints
  r.POST(ApiV1UriPrefix+"/calendar-entries", postCreateCalendarEntry)
  r.GET(ApiV1UriPrefix+"/calendar-entries", getCalendarEntries)
  r.GET(ApiV1UriPrefix+"/calendar-entries/:iid", getCalendarEntryById)
  r.PUT(ApiV1UriPrefix+"/calendar-entries/:iid", putUpdateCalendarEntry)
  r.DELETE(ApiV1UriPrefix+"/calendar-entries/:iid", deleteCalendarEntryById)
  ```

#### 12.6 E2E Tests for Calendar Endpoints

**File**: `tests/e2e/laser/calendar_crud_test.go`

- [x] 12.6.1 `TestCalendar_Create_Success` — POST calendar, verify 201, GET back
- [x] 12.6.2 `TestCalendar_Get_NotFound` — GET non-existent calendar, verify 404
- [x] 12.6.3 `TestCalendar_Update_Success` — PUT update display_names, verify changes
- [x] 12.6.4 `TestCalendar_Delete_Success` — DELETE calendar, verify 204, GET returns 404
- [x] 12.6.5 `TestCalendar_Delete_InUse_Conflict` — Create calendar, assign to SecurityListing, try DELETE, verify 409
- [x] 12.6.6 `TestCalendar_List_Pagination` — Create multiple calendars, verify pagination
- [x] 12.6.7 `TestCalendarEntry_Create_Success` — POST entry, verify 201, GET back
- [x] 12.6.8 `TestCalendarEntry_Create_InvalidCalendarIid` — POST entry with non-existent calendar_iid, verify 400
- [x] 12.6.9 `TestCalendarEntry_Create_InvalidTimeRange` — POST entry with start > end, verify 400
- [x] 12.6.10 `TestCalendarEntry_Update_Delete` — PUT update, DELETE, verify
- [x] 12.6.11 `TestCalendarEntry_ListByCalendar` — GET /calendars/:iid/entries, verify filtered results
- [x] 12.6.12 `TestCalendarEntry_CascadeDelete` — Delete parent calendar, verify entries also deleted

**E2E Category**: Category 26 (Listing Manager CRUD) — these are RDBMS-only tests, no blockchain needed

**Makefile**: Add test patterns to `E2E_CAT26_PATTERN`:
```makefile
E2E_CAT26_PATTERN := ... |TestCalendar_Create|TestCalendar_Get|TestCalendar_Update|TestCalendar_Delete|TestCalendarEntry_Create|TestCalendarEntry_Update|TestCalendarEntry_ListByCalendar|TestCalendarEntry_CascadeDelete
```

---

## Files Summary

### New Files

| File | Description |
|------|-------------|
| `pkg/fin/order.go` | Order struct, OrderSideEnum, OrderTypeEnum, OrderStatusEnum |
| `pkg/fin/order_event.go` | OrderEvent struct, OrderEventTypeEnum, int mapping |
| `pkg/daemons/listingmgr/trax/executors/create_direct_order/saga.go` | Executor registration, package variables |
| `pkg/daemons/listingmgr/trax/executors/create_direct_order/validate_and_resolve.go` | Step 1: Input validation, deployment lookup, PLEGP check, calendar, decimals |
| `pkg/daemons/listingmgr/trax/executors/create_direct_order/submit_order_on_chain.go` | Step 2: Decimal scaling, ATS build, LASER mutation, event extraction |
| `pkg/daemons/listingmgr/trax/executors/create_direct_order/create_order_record.go` | Step 3: Generate exchange_oid, compute hash, create order+event records |
| `pkg/daemons/listingmgr/trax/executors/create_direct_order/laser_helpers.go` | Shared LASER helpers (or extract to common pkg) |
| `pkg/daemons/listingmgr/api/v1/orders_post_create_direct.go` | REST endpoint: POST /api/v1/orders/create-direct |
| `pkg/daemons/listingmgr/api/v1/orders_get.go` | REST endpoints: GET orders (list, by IID, by exchange_oid, by external_oid, query) |
| `pkg/daemons/listingmgr/api/v1/order_events_get.go` | REST endpoints: GET order-events (list by order, by IID, query) |
| `tests/e2e/laser/create_direct_order_test.go` | E2E tests (ethbc mode) |
| `pkg/daemons/listingmgr/api/v1/calendars_post_create.go` | REST: POST /api/v1/calendars |
| `pkg/daemons/listingmgr/api/v1/calendars_get.go` | REST: GET calendars (list, by IID, entries by calendar) |
| `pkg/daemons/listingmgr/api/v1/calendars_put_update.go` | REST: PUT /api/v1/calendars/:iid |
| `pkg/daemons/listingmgr/api/v1/calendars_delete.go` | REST: DELETE /api/v1/calendars/:iid |
| `pkg/daemons/listingmgr/api/v1/calendar_entries_post_create.go` | REST: POST /api/v1/calendar-entries |
| `pkg/daemons/listingmgr/api/v1/calendar_entries_get.go` | REST: GET calendar-entries (list, by IID) |
| `pkg/daemons/listingmgr/api/v1/calendar_entries_put_update.go` | REST: PUT /api/v1/calendar-entries/:iid |
| `pkg/daemons/listingmgr/api/v1/calendar_entries_delete.go` | REST: DELETE /api/v1/calendar-entries/:iid |
| `tests/e2e/laser/calendar_crud_test.go` | E2E tests for Calendar + CalendarEntry CRUD (RDBMS mode) |

### Modified Files

| File | Changes |
|------|---------|
| `pkg/common/hash.go` | Add `GetDirectOrderHash()` function |
| `pkg/common/hash_test.go` | Add unit tests for `GetDirectOrderHash()` |
| `pkg/laser/model/operation_name.go` | Add `OperationNameEnum_AgoraEngineDirectOrderManagerCreateExternallyIdentifiedBatchDirectOrderV2` |
| `pkg/laser/ats/arg_name.go` | Add new ATS arg names (ExternalId, PairId, Bid, DirectlyFillable, OrderType, Quantity, Price, Slippage, ExpireTs, OrderData, Participant, Investor, FeePayer) |
| `pkg/daemons/lcmgr/ethbc_diamond_contract.go` | Add mutation handler for createExternallyIdentifiedBatchDirectOrderV2 + DirectOrderCreate2 event parsing |
| `pkg/daemons/lcmgr/ledger/ethbc/mutator.go` | Register operation in `isDiamondOperation()` |
| `pkg/daemons/listingmgr/stores/listing_store.go` | Add Order + OrderEvent + Calendar Update/Delete/Query + CalendarEntry CRUD interface methods |
| `pkg/daemons/listingmgr/stores/postgres/listing_store.go` | Implement Order + OrderEvent + Calendar + CalendarEntry CRUD for PostgreSQL |
| `pkg/daemons/listingmgr/stores/memory/listing_store.go` | Implement Order + OrderEvent + Calendar + CalendarEntry CRUD for in-memory |
| `pkg/daemons/listingmgr/trax/executors/run.go` | Add create_direct_order executor registration |
| `pkg/daemons/listingmgr/api/v1/api.go` | Register order + calendar + calendar-entry routes |
| `pkg/daemons/listingmgr.go` | Add instrmgr URL env var, pass to executors |
| `deploy/k8s/init/init_listingmgr_pgsql.sql` | Add orders + order_events tables with indexes |
| `deploy/k8s/init/csd/min/trax.sql` | Add saga template + 3 step templates |
| `deploy/k8s/init/prtagent/min/trax.sql` | Add saga template + 3 step templates |
| `deploy/k8s/init/exchange/min/trax.sql` | Add saga template + 3 step templates |
| `docs/SUMMARY-FOR-AGENT.md` | Add saga and endpoint references |
| `docs/E2E_TEST_CATALOG.md` | Add new test group |
| `docs/TODO.md` | Add TODO items for indexer sync and calendar events |
| `Makefile` | Add test category patterns |

### Patterns to Reuse

| Source File | Purpose |
|-------------|---------|
| `pkg/daemons/listingmgr/trax/executors/setup_security_listing/create_pair_on_chain.go` | ATS BoundFunc build pattern, LASER mutation submit, IdempotentService pattern |
| `pkg/daemons/listingmgr/trax/executors/setup_security_listing/laser_helpers.go` | `submitAndPollLaserMutation`, `queryCrownExecutorIid` |
| `pkg/daemons/listingmgr/trax/executors/setup_security_listing/resolve_fee_collector.go` | accmgr HTTP queries, partner address resolution, AuthzDiamond resolution |
| `pkg/daemons/listingmgr/trax/executors/setup_security_listing/saga.go` | Executor registration, package-level variables |
| `pkg/daemons/listingmgr/stores/postgres/listing_store.go` | PostgreSQL CRUD with JSONB, shared.entities pattern |
| `pkg/daemons/listingmgr/api/v1/security_listings_post_deploy.go` | REST saga trigger pattern |
| `pkg/mms/agora/abi/create_externally_identified_direct_order.go` | Decimal scaling for quantity/price, ABI packing pattern |
| `pkg/common/hash.go` | SHA-512/384 hash pattern |
| `deploy/k8s/init/csd/min/trax.sql` (setup_security_listing) | SQL saga template format |
| `tests/e2e/laser/security_listing_deployment_test.go` | E2E test setup, Anvil direct calls |

---

## Success Criteria

- [ ] Saga creates correct on-chain order with all parameters matching the specification
- [ ] `createExternallyIdentifiedBatchDirectOrderV2` is called with a single-element batch
- [ ] Quantity is correctly scaled by base token decimals
- [ ] Price is correctly scaled by quote token decimals
- [ ] `data` field contains valid UTF-8 JSON with all required traceability fields
- [ ] PLEGP admin partner is the transaction signer
- [ ] `DirectOrderCreate2` event is correctly parsed to extract `orderId`
- [ ] `order_hash` is computed correctly using all 7 fixed identifiers
- [ ] Off-chain Order and OrderEvent records are created in listingmgr PostgreSQL
- [ ] `exchange_oid` is unique per order (UNIQUE constraint)
- [ ] REST pre-checks catch all invalid inputs before saga submission
- [ ] Calendar CRUD endpoints work: create/get/update/delete calendars and calendar entries
- [ ] Calendar cascade delete works: deleting a calendar deletes its entries
- [ ] Calendar delete blocked when referenced by a SecurityListing (409 Conflict)
- [ ] Calendar check in saga works: empty = 24/7, non-empty = operating hours check
- [ ] All order read endpoints work correctly (list, by IID, by exchange_oid, by external_oid, query)
- [ ] No DELETE or PUT endpoints exist for orders
- [ ] All E2E tests pass in ethbc mode
- [ ] On-chain verification via Anvil JSON-RPC confirms order properties
- [ ] Compensation works correctly for step 3 (delete records)
- [ ] Locale defaults to "en-US"

### Phase 13: Saga-Level Execution Reports in tradeidxer PostgreSQL — REMOVED

> **Originally implemented**: 2026-03-07. **Removed**: 2026-03-15. Saga-level exec report emission from listingmgr has been fully removed. Execution reports are now emitted only by fixclient and tradeidxer.

**Reason for removal**: The saga steps no longer emit execution reports. The new execution report lifecycle has only 2 reports per order:
1. **PENDING_NEW/PENDING_NEW** — emitted by fixclient when NOS is successfully submitted to the exchange (`exec_id` = `cl_ord_id`)
2. **NEW/NEW** — emitted by tradeidxer when `DIRECT_ORDER_CREATE` on-chain event is detected (`exec_id` = `event_hash`)

**What was removed**:
- `exec_report_helper.go` (deleted) — contained `insertSagaExecReport()`, `fixSide()`
- `pkgReportStore` package variable and `reportStore` parameter from `create_direct_order` saga and `run.go`
- `ReportStore` construction from `TRADEIDXER_POSTGRESQL_CONN_STRING` in `listingmgr.go`
- `TRADEIDXER_POSTGRESQL_CONN_STRING` env var is no longer needed by listingmgr
- Saga steps `validate_and_resolve`, `submit_order_on_chain`, and `create_order_record` no longer call `insertSagaExecReport()`

---

## Implementation Order

1. Phase 1: Domain model updates (tiny, unblocks everything)
2. Phase 2: LASER operation + lcmgr handler (critical path; depends on Go bindings from `kam`)
3. Phase 3: Order hash function (independent, tiny)
4. Phase 4: Database schema updates (independent)
5. Phase 5: Store interface + implementations (depends on Phases 1, 4)
6. Phase 12: Calendar REST endpoints (depends on Phase 5; **must be done before Phase 6** since saga Step 1 needs calendar query)
7. Phase 6: Saga step executors (depends on Phases 2, 3, 5, 12)
8. Phase 7: REST API endpoints for orders (depends on Phase 5)
9. Phase 8: SQL saga templates (independent, can be done anytime)
10. Phase 9: listingmgr daemon updates (depends on Phase 6)
11. ~~Phase 13: Saga-level execution reports~~ (REMOVED — exec reports now emitted only by fixclient and tradeidxer)
12. Phase 10: E2E tests (depends on all above)
13. Phase 11: Documentation (last)

**Parallelizable**: Phases 2, 3, 4 can be done in parallel. Phase 8 can be done anytime. Phase 12 can be done in parallel with Phases 2 and 3 (only needs Phase 5 store interface).

**Prerequisite from `kam`**: Go bindings for `createExternallyIdentifiedBatchDirectOrderV2` (Phase 2 depends on this).

## Verification

```bash
# Build after all changes
make bip-daemons

# Run specific E2E test
TEST_RUN_PATTERN="TestCreateDirectOrder" make laser-e2e-full-ethbc

# Check test results
cat .test-results/e2e/<session>/logs/test-runner.log

# Verify calendar CRUD via REST
curl http://localhost:17209/api/v1/calendars
curl -X POST http://localhost:17209/api/v1/calendars -d '{"iid":"cal-test","display_names":{"en-US":"Test Calendar"}}'
curl http://localhost:17209/api/v1/calendars/cal-test/entries

# Verify order records via REST
curl http://localhost:17209/api/v1/orders
curl http://localhost:17209/api/v1/orders?exchange_oid=exch_oid_...
curl http://localhost:17209/api/v1/order-events?order_iid=order_...
```

## Notes

- **createExternallyIdentifiedBatchDirectOrderV2 Solidity location**: `/Users/kam/repos/NEW2/qomet/contracts/contracts/facets/_agora/engine/AgoraEngineDirectOrderManagerV2Facet.sol`
- **CreateDirectOrderParamsV2 struct**: Extends V1 with `participant`, `investor`, `feePayer` address fields
- **IAgoraEngineV1Dot5**: Interface defining createExternallyIdentifiedBatchDirectOrderV2
- **DirectOrderCreate2 event**: `DirectOrderCreate2(uint256 eventId, bytes32 indexed pairId, uint256 indexed orderId)` — orderId from Topics[2]
- **LASER slot translation**: All slot addresses (participant_iid, investor_iid, admin_partner) are translated to Ethereum addresses by the E1->E2 chain before the on-chain call
- **Batch size**: Always 1 for this saga — the `paramsArr` contains exactly one `CreateDirectOrderParamsV2`
- **Fee payer**: Always equals `participant_iid` (participant pays their own fees)
- **Locale**: Always "en-US" if not known
- **No database migration**: Schema changes go directly into CREATE statements (no release yet)
- **External ID uniqueness**: The smart contract enforces `externalId` uniqueness via `externalIdMap` — duplicate `external_oid` will cause on-chain revert with "AENI:EXTIDEX"