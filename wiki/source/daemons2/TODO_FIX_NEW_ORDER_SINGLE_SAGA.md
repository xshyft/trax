# TODO: FIX NewOrderSingle → create_direct_order Saga Integration

> **Status**: IMPLEMENTED (code complete, pending E2E validation)
> **Created**: 2026-02-27
> **Last Updated**: 2026-02-27
> **Feature**: Replace the FIX receiver's NewOrderSingle (MsgType=D) execution pipeline path with TRAX saga-based `create_direct_order` submission via listingmgr REST API
> **Short ID**: FIX-NOS-SAGA
> **Dependencies**: `create_direct_order` saga (PHASES 1-9, 12 COMPLETE — see `docs/TODO_CREATE_DIRECT_ORDER_SAGA.md`)
> **Enables**: FIX protocol clients to place orders through the saga-based workflow with full on-chain settlement, traceability, and off-chain order persistence

---

## Overview

The FIX receiver (`pkg/daemons/fixreceiver/`) currently handles incoming `NewOrderSingle` (MsgType=D) messages by creating an `execpl.Command` and publishing it to the RabbitMQ execution pipeline (`exchange_incoming_commands` → `cmdprocessor` → `cmdbcaster` → market manager). This pipeline is being replaced with the TRAX saga-based `create_direct_order` workflow.

**New flow**:
```
FIX Client
  │
  ▼
fixreceiver (MsgType=D handler)
  │  1. Parse FIX fields (Symbol, Currency, Side, OrdType, Qty, Price, etc.)
  │  2. Validate fields
  │  3. Resolve security_listing_iid from Symbol+Currency via listingmgr
  │  4. Get participant_iid from FIX session config (AuthInfo)
  │  5. Get investor_iid from ClientID (Tag 109) or PartyID (Tag 448+452)
  │  6. Build create_direct_order saga input
  │  7. POST to listingmgr /api/v1/orders/create-direct
  │
  ▼
listingmgr REST API (existing, no changes)
  │  POST /api/v1/orders/create-direct
  │  → Validates, submits TRAX saga
  │
  ▼
TRAX Coordinator
  │  Step 1: cdo_validate_and_resolve (resolve PLEGP, decimals, calendar)
  │  Step 2: cdo_submit_order_on_chain (LASER mutation → on-chain)
  │  Step 3: cdo_create_order_record (persist Order + OrderEvent)
  │  (saga steps do NOT emit execution reports)
  │
  ▼
FIX Client receives Execution Reports (MsgType=8):
  │  1. PENDING_NEW/PENDING_NEW — emitted by fixclient when NOS is successfully submitted (exec_id = cl_ord_id)
  │  2. NEW/NEW — emitted by tradeidxer when DIRECT_ORDER_CREATE on-chain event is detected (exec_id = event_hash)
  │  Failure: ExecType=REJECTED (8), OrdStatus=REJECTED (8)
```

**Key architectural decisions**:
- **fixreceiver calls listingmgr REST API** (not direct TRAX submission) — reuses all existing validation in `orders_post_create_direct.go` and avoids adding RabbitMQ/TRAX dependency to fixreceiver
- **Replace entirely** — the old execution pipeline path is removed from NewOrderSingle handlers (the pipeline infrastructure itself — cmdprocessor, cmdbcaster — remains for other flows)
- **Shared mapping code** — a single shared function in `pkg/daemons/fixreceiver/versions/common/` handles FIX→saga field mapping; version-specific handlers only extract FIX-version-specific fields
- **participant_iid from session config** — extended `AuthInfo` struct carries participant_iid set at Logon time
- **investor_iid from FIX message** — ClientID (Tag 109) for FIX 4.2, Parties group (PartyRole=5, Investor ID) for FIX 4.4/5.0/5.0SP1/5.0SP2
- **exec_runtime_name hardcoded** — always `"primary"`
- **TimeInForce** — accept DAY and GTC only (reject IOC, FOK, etc.)

---

## Prerequisites

1. `create_direct_order` saga is implemented and working (see `docs/TODO_CREATE_DIRECT_ORDER_SAGA.md` — Phases 1-9, 12 COMPLETE)
2. `POST /api/v1/orders/create-direct` endpoint in listingmgr is functional
3. SecurityListing records exist in listingmgr (created via `setup_security_listing` saga)
4. Go bindings for `quickfixgo/fix42`, `quickfixgo/fix44`, `quickfixgo/fix50`, `quickfixgo/fix50sp1`, `quickfixgo/fix50sp2` are available (already in the project)

---

## FIX Field → Saga Input Mapping

### Complete Mapping Table

| FIX Field | FIX Tag | FIX 4.2/4.4 Access | FIX 5.0+ Access | Saga Input Field | Mapping Logic |
|-----------|---------|---------------------|------------------|-----------------|---------------|
| Symbol | 55 | `msg.GetSymbol()` | `msg.GetSymbol()` | → resolve `security_listing_iid` | Query listingmgr `FetchSecurityListings()`, filter by SecurityIdentifier ID portion matching symbol AND CurrencyIdentifier ID portion matching currency |
| Currency | 15 | `msg.GetCurrency()` | `msg.GetCurrency()` | → resolve `security_listing_iid` | Used together with Symbol for resolution |
| Side | 54 | `msg.GetSide()` | `msg.GetSide()` | `side` | BUY (`1`) → `ORDER_SIDE_ENUM_BID`, SELL (`2`) → `ORDER_SIDE_ENUM_ASK`. Other values: REJECT |
| OrdType | 40 | `msg.GetOrdType()` | `msg.GetOrdType()` | `order_type` | MARKET (`1`) → `ORDER_TYPE_ENUM_MARKET`, LIMIT (`2`) → `ORDER_TYPE_ENUM_LIMIT`. Other values: REJECT |
| OrderQty | 38 | `msg.GetOrderQty()` | `msg.GetOrderQty()` | `quantity` | Decimal string. Must be > 0 |
| Price | 44 | `msg.GetPrice()` | `msg.GetPrice()` | `price` | Decimal string. LIMIT: must be > 0. MARKET: must be 0 |
| ClOrdID | 11 | `msg.GetClOrdID()` | `msg.GetClOrdID()` | `external_oid` | Client's order ID, used directly as saga external_oid |
| ExpireTime | 126 | `msg.GetExpireTime()` | `msg.GetExpireTime()` | `expire_timestamp` | Convert to Unix seconds. Must be in the future. If zero/missing with TimeInForce=DAY → set to end of current UTC day |
| TimeInForce | 59 | `msg.GetTimeInForce()` | `msg.GetTimeInForce()` | _(validation only)_ | Accept DAY (`0`) and GTC (`1`) only. REJECT all others (IOC, FOK, etc.) |
| Account | 1 | `msg.GetAccount()` | `msg.GetAccount()` | → stored in `data` JSON | **NOT** used as participant_iid. Stored in saga's `data` field for traceability. See below. |
| ClientID | 109 | `msg.GetClientID()` | _(N/A in 4.4+)_ | `investor_iid` | **FIX 4.2 only**: The investor/beneficial owner slot IID. Required — fail if missing. |
| PartyID+PartyRole | 448+452 | _(N/A in 4.2)_ | Parties repeating group | `investor_iid` | **FIX 4.4/5.0/5.0SP1/5.0SP2**: Find Party where PartyRole=5 (Investor ID per quickfixgo `enum.PartyRole_INVESTOR_ID`). PartyID value = investor_iid. Required — fail if not found. |
| Text | 58 | `msg.GetText()` | `msg.GetText()` | `data` (partial) | Extract `request_id` from JSON if present (existing behavior). Store full text in saga's `data` JSON. |
| TransactTime | 60 | `msg.GetTransactTime()` | `msg.GetTransactTime()` | `trace_id` (partial) | Include in trace_id generation: `fix-{fixVersion}-{transactTime.UnixMilli()}-{randomSuffix}` |
| _(none)_ | — | — | — | `exec_runtime_name` | Hardcoded: `"primary"` |
| _(none)_ | — | — | — | `participant_iid` | From `AuthInfo.ParticipantIid` (FIX session config, set at Logon) |
| _(none)_ | — | — | — | `participant_oid` | Derived: `common.ToParticipantOrderId(participantId, clOrdID, side, symbol)` |
| _(none)_ | — | — | — | `idempotency_key` | Generated: `common.RandomHexString(16)` (32-char hex) |
| _(none)_ | — | — | — | `directly_fillable` | Default: `"false"` |
| _(none)_ | — | — | — | `slippage` | Default: `"0"` |

### Account (Tag 1) vs participant_iid — Detailed Explanation

In the **OLD execution pipeline**:
- Tag 1 (`Account`) was extracted from the FIX message and used as `creatorAccountId` — an off-chain account identifier.
- The same value was assigned to three fields: `ParticipantAccountId`, `InvestorAccountId`, and `ExecutorAccountId` (see `new_order_single.go:186-188` in v42/v50sp2).
- These were off-chain account IDs used by the old market manager system.

In the **NEW saga path**:
- `participant_iid` is a **LASER slot IID** (e.g., `lsrslot-xxx-yyy-zzz`), NOT an off-chain account ID.
- The LASER slot IID identifies the participant's on-chain identity within the CSD infrastructure.
- This value cannot come from the FIX message because FIX clients don't know about LASER slot IIDs.
- Instead, `participant_iid` is configured per FIX session in the session config (`AuthInfo.ParticipantIid`), set by the exchange operator during session provisioning.
- Tag 1 (`Account`) from the FIX message is **still extracted** and stored in the saga's `data` JSON field for off-chain traceability and audit purposes, but it has no functional role in the saga execution.

### Investor IID Extraction — FIX Version Differences

#### FIX 4.2: Tag 109 (ClientID)

FIX 4.2 includes `ClientID` (Tag 109) as a standard field in NewOrderSingle. This field identifies the client/investor on whose behalf the order is placed. Note: FIX 4.4 does NOT have GetClientID — it uses the Parties repeating group instead (same as 5.0+).

```go
// FIX 4.2 only (4.4+ uses Parties group)
investorIid, err := msg.GetClientID()
if err != nil {
    report.AddError("error getting investor_iid (ClientID, Tag 109): " + err.Error())
}
if investorIid == "" {
    report.AddError("investor_iid (ClientID, Tag 109) is required")
}
```

#### FIX 4.4 / 5.0 / 5.0SP1 / 5.0SP2: Parties Repeating Group (Tags 453, 448, 447, 452)

FIX 4.4 and 5.0+ use the Parties component block. The investor is identified via `enum.PartyRole_INVESTOR_ID` (`PartyRole=5` in quickfixgo).

```go
// FIX 5.0+ — extract investor_iid from Parties group
var investorIid string
noPartyIDs, err := msg.GetNoPartyIDs()
if err == nil {
    for i := 0; i < noPartyIDs.IntValue(); i++ {
        group := noPartyIDs.Get(i)
        partyRole, roleErr := group.GetPartyRole()
        if roleErr == nil && partyRole == enum.PartyRole_INVESTOR_ID { // PartyRole=5
            partyID, idErr := group.GetPartyID()
            if idErr == nil {
                investorIid = partyID
                break
            }
        }
    }
}
if investorIid == "" {
    report.AddError("investor_iid not found in Parties group (PartyRole=5 InvestorID required)")
}
```

**Note**: The exact quickfixgo API for iterating Parties groups varies by version. Check the generated fix50/fix50sp1/fix50sp2 newordersingle package for the correct repeating group accessor methods. The quickfixgo library generates typed methods per repeating group.

### Data JSON Construction

The `data` field in the saga input is a JSON string containing FIX-originated metadata for traceability:

```json
{
    "fix_version": "v50sp2",
    "participant_fix_compid": "FIX.5.0SP2:SENDER->TARGET",
    "fix_account": "ACC001",
    "fix_text": "{\"request_id\": \"req-123\", ...}",
    "fix_transact_time": "2026-02-27T10:30:00Z",
    "fix_time_in_force": "DAY",
    "fix_client_order_id": "CLT-ORD-001",
    "fix_participant_id": "SENDER:SUBSENDER"
}
```

---

## Phase 1: FIX Session Config Extension

**File**: `pkg/daemons/fixreceiver/auth/auth.go`

- [ ] 1.1.1 Add `ParticipantIid` field to `AuthInfo` struct:
  ```go
  type AuthInfo struct {
      Provider         string `json:"provider" yaml:"provider"`
      AuthTokenType    string `json:"auth_token_type" yaml:"auth_token_type"`
      AuthToken        string `json:"auth_token" yaml:"auth_token"`
      Identity         string `json:"identity" yaml:"identity"`
      ParticipantIid   string `json:"participant_iid" yaml:"participant_iid"`
  }
  ```

- [ ] 1.1.2 Add validation in `validateAuthInfo()` — if `ParticipantIid` is empty, return error:
  ```go
  func validateAuthInfo(authInfo *AuthInfo) error {
      if authInfo.Provider != "firefence" {
          return fmt.Errorf("auth provider is not supported: '%s'", authInfo.Provider)
      }
      if authInfo.AuthTokenType != "jwt" {
          return fmt.Errorf("auth token type is not supported: '%s'", authInfo.AuthTokenType)
      }
      if authInfo.ParticipantIid == "" {
          return fmt.Errorf("participant_iid is required in auth info")
      }
      return nil
  }
  ```

- [ ] 1.1.3 Update FIX Logon RawData JSON format documentation. The new required Logon RawData format is:
  ```json
  {
      "provider": "firefence",
      "auth_token_type": "jwt",
      "auth_token": "...",
      "identity": "PARTICIPANT_ID",
      "participant_iid": "lsrslot-xxx-yyy-zzz"
  }
  ```

**Impact**: Every FIX session must now include `participant_iid` in the Logon RawData. Sessions without it will be rejected at Logon time. This is a **breaking change** for existing FIX clients — they must update their Logon RawData to include the LASER slot IID.

**CompID consistency**: For non-drop-copy sessions, Logon validation now also checks the RawData `participant_iid` against accmgr. The participant's `metadata.fix_comp_id` must exactly match the QuickFIX session `TargetCompID`; otherwise Logon is rejected before the session is attributed. The receiver ConfigMap is still required because QuickFIX uses it as the acceptor session allowlist, but it is no longer allowed to drift silently from accmgr metadata. Helm deployments enable startup reconciliation with `FIXRECEIVER_VALIDATE_TARGET_COMP_IDS=true`, which requires every non-DCG configured `TargetCompID` to have exactly one matching accmgr participant metadata row for that receiver. The deploy tool also runs an exchange preflight over the union of configured receiver charts before Helm upgrades, catching stale or unexpected accmgr `fix_comp_id` rows such as `TKNSBRK1` before pods are rolled. E2E compose disables the startup check because test participants are created after service start; Logon-level validation remains mandatory there.

---

## Phase 2: SecurityListing Resolution via ListingMgrClient

**File**: `pkg/daemons/fixreceiver/versions/common/listingmgr_client.go`

- [ ] 2.1.1 Add `FindSecurityListingBySymbolCurrency` method to `ListingMgrClient`:

  ```go
  // FindSecurityListingBySymbolCurrency resolves a SecurityListing IID from a FIX Symbol+Currency pair.
  // It queries listingmgr for all SecurityListings and finds one where:
  //   - SecurityIdentifier's ID portion (after "SCHEME:") matches the symbol
  //   - CurrencyIdentifier's ID portion (after "SCHEME:") matches the currency
  //
  // The FinIdentifierString format is "SCHEME:ID" (e.g., "ISIN:US1234567890" or "ISO4217:USD").
  // The symbol from FIX maps to the ID portion after splitting on ':'.
  //
  // Returns error if no matching listing is found (fail immediately, no fallback).
  func (c *ListingMgrClient) FindSecurityListingBySymbolCurrency(
      ctx context.Context, symbol, currency string,
  ) (*fin.SecurityListing, error) {
      listings, err := c.FetchSecurityListings(ctx)
      if err != nil {
          return nil, fmt.Errorf("failed to fetch security listings: %w", err)
      }
      for _, listing := range listings {
          secScheme, secId, err := ParseFinIdentifierString(listing.SecurityIdentifier)
          if err != nil {
              continue // skip malformed identifiers
          }
          curScheme, curId, err := ParseFinIdentifierString(listing.CurrencyIdentifier)
          if err != nil {
              continue
          }
          _ = secScheme // not used for matching
          _ = curScheme // not used for matching
          if secId == symbol && curId == currency {
              return &listing, nil
          }
      }
      return nil, fmt.Errorf("no SecurityListing found for symbol=%s currency=%s", symbol, currency)
  }
  ```

- [ ] 2.1.2 Add in-memory cache with TTL for SecurityListing resolution:
  ```go
  type listingCache struct {
      mu       sync.RWMutex
      listings []fin.SecurityListing
      fetchedAt time.Time
      ttl       time.Duration
  }
  ```
  - Cache TTL: 60 seconds (configurable via env var `FIX_LISTING_CACHE_TTL_SECONDS`, default 60)
  - Cache is refreshed on first request after TTL expiry
  - Thread-safe with `sync.RWMutex`

- [ ] 2.1.3 Add `SubmitCreateDirectOrder` method to `ListingMgrClient`:

  ```go
  // CreateDirectOrderRequest mirrors the listingmgr POST /api/v1/orders/create-direct body.
  type CreateDirectOrderRequest struct {
      ExternalOid        string `json:"external_oid"`
      ParticipantOid     string `json:"participant_oid"`
      ExecRuntimeName    string `json:"exec_runtime_name"`
      SecurityListingIid string `json:"security_listing_iid"`
      ParticipantIid     string `json:"participant_iid"`
      InvestorIid        string `json:"investor_iid"`
      OrderType          string `json:"order_type"`
      Quantity           string `json:"quantity"`
      Price              string `json:"price"`
      Side               string `json:"side"`
      IdempotencyKey     string `json:"idempotency_key"`
      ExpireTimestamp    string `json:"expire_timestamp"`
      DirectlyFillable   string `json:"directly_fillable,omitempty"`
      Slippage           string `json:"slippage,omitempty"`
      TraceId            string `json:"trace_id,omitempty"`
      ExecutionId        string `json:"execution_id,omitempty"`
      Data               string `json:"data,omitempty"`
  }

  // CreateDirectOrderResponse mirrors the listingmgr 201 response.
  type CreateDirectOrderResponse struct {
      SagaInstanceId string `json:"saga_instance_id"`
      Status         string `json:"status"`
  }

  // SubmitCreateDirectOrder calls POST {BaseURL}/orders/create-direct.
  // Returns the saga_instance_id on 201 Created.
  // Returns error on any non-201 response (including the error message from listingmgr).
  func (c *ListingMgrClient) SubmitCreateDirectOrder(
      ctx context.Context, req CreateDirectOrderRequest,
  ) (string, error) {
      url := fmt.Sprintf("%s/orders/create-direct", c.BaseURL)
      jsonData, err := json.Marshal(req)
      if err != nil {
          return "", fmt.Errorf("failed to marshal request: %w", err)
      }
      httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewBuffer(jsonData))
      if err != nil {
          return "", fmt.Errorf("failed to create request: %w", err)
      }
      httpReq.Header.Set("Content-Type", "application/json")
      resp, err := c.HTTPClient.Do(httpReq)
      if err != nil {
          return "", fmt.Errorf("failed to call listingmgr: %w", err)
      }
      defer resp.Body.Close()
      body, _ := io.ReadAll(resp.Body)

      if resp.StatusCode != http.StatusCreated {
          return "", fmt.Errorf("listingmgr returned status %d: %s", resp.StatusCode, string(body))
      }

      var result CreateDirectOrderResponse
      if err := json.Unmarshal(body, &result); err != nil {
          return "", fmt.Errorf("failed to decode response: %w", err)
      }
      return result.SagaInstanceId, nil
  }
  ```

---

## Phase 3: Shared FIX→Saga Mapping Code

**File**: `pkg/daemons/fixreceiver/versions/common/saga_order_builder.go` (NEW)

- [ ] 3.1.1 Create `CreateDirectOrderFromFIXParams` struct:

  ```go
  package common

  import "time"

  // CreateDirectOrderFromFIXParams holds FIX-extracted fields ready for saga input mapping.
  // Each FIX version handler extracts version-specific fields and populates this struct.
  type CreateDirectOrderFromFIXParams struct {
      Symbol          string    // FIX Tag 55
      Currency        string    // FIX Tag 15
      Side            string    // "BUY" or "SELL" (FIX enum string)
      OrderType       string    // "MARKET" or "LIMIT" (FIX enum string)
      Quantity        string    // Decimal string (FIX Tag 38)
      Price           string    // Decimal string (FIX Tag 44)
      ClOrdID         string    // FIX Tag 11
      ExpireTime      time.Time // FIX Tag 126
      TimeInForce     string    // FIX enum: "0"=DAY, "1"=GTC
      InvestorIid     string    // Tag 109 (4.2) or PartyID with PartyRole=5 (4.4/5.0+)
      AccountId       string    // FIX Tag 1 — stored in data JSON for traceability
      ParticipantData string    // FIX Tag 58/Text — stored in data JSON
      TransactTime    time.Time // FIX Tag 60
      RequestId       string    // Extracted from Text JSON if present
      FIXVersion      string    // "v42", "v44", "v50", "v50sp1", "v50sp2"
      ParticipantFixCompId    string    // quickfix.SessionID.String()
      ParticipantId   string    // From common.GetParticipantId(sessionID)
  }
  ```

- [ ] 3.1.2 Create `BuildCreateDirectOrderRequest` function:

  ```go
  // BuildCreateDirectOrderRequest validates FIX params and builds a CreateDirectOrderRequest
  // for submission to listingmgr's POST /api/v1/orders/create-direct.
  //
  // participantIid comes from the FIX session AuthInfo (not from the FIX message).
  //
  // Returns error for any validation failure (fail immediately, no fallback).
  func BuildCreateDirectOrderRequest(
      ctx context.Context,
      params CreateDirectOrderFromFIXParams,
      participantIid string,
  ) (*CreateDirectOrderRequest, error) {
      // 1. Validate participantIid (from session config)
      if participantIid == "" {
          return nil, fmt.Errorf("participant_iid is required (must be set in FIX session config)")
      }

      // 2. Validate investor_iid (from FIX message)
      if params.InvestorIid == "" {
          return nil, fmt.Errorf("investor_iid is required (FIX ClientID Tag 109 for v42, or PartyID with PartyRole=5 for v44+)")
      }

      // 3. Map side: BUY → ORDER_SIDE_ENUM_BID, SELL → ORDER_SIDE_ENUM_ASK
      var sagaSide string
      switch params.Side {
      case "BUY", "1":
          sagaSide = "ORDER_SIDE_ENUM_BID"
      case "SELL", "2":
          sagaSide = "ORDER_SIDE_ENUM_ASK"
      default:
          return nil, fmt.Errorf("invalid side: %s (must be BUY or SELL)", params.Side)
      }

      // 4. Map orderType: MARKET → ORDER_TYPE_ENUM_MARKET, LIMIT → ORDER_TYPE_ENUM_LIMIT
      var sagaOrderType string
      switch params.OrderType {
      case "MARKET", "1":
          sagaOrderType = "ORDER_TYPE_ENUM_MARKET"
      case "LIMIT", "2":
          sagaOrderType = "ORDER_TYPE_ENUM_LIMIT"
      default:
          return nil, fmt.Errorf("invalid orderType: %s (must be MARKET or LIMIT)", params.OrderType)
      }

      // 5. Validate quantity > 0
      qty, err := decimal.NewFromString(params.Quantity)
      if err != nil || qty.LessThanOrEqual(decimal.Zero) {
          return nil, fmt.Errorf("invalid quantity: %s (must be positive)", params.Quantity)
      }

      // 6. Validate price rules
      price, err := decimal.NewFromString(params.Price)
      if err != nil {
          return nil, fmt.Errorf("invalid price: %s", params.Price)
      }
      if sagaOrderType == "ORDER_TYPE_ENUM_MARKET" && !price.Equal(decimal.Zero) {
          return nil, fmt.Errorf("price must be 0 for MARKET orders, got: %s", params.Price)
      }
      if sagaOrderType == "ORDER_TYPE_ENUM_LIMIT" && price.LessThanOrEqual(decimal.Zero) {
          return nil, fmt.Errorf("price must be positive for LIMIT orders, got: %s", params.Price)
      }

      // 7. Validate TimeInForce: only DAY and GTC accepted
      switch params.TimeInForce {
      case "0", "DAY":
          // OK
      case "1", "GTC", "GOOD_TILL_CANCEL":
          // OK
      default:
          return nil, fmt.Errorf("invalid TimeInForce: %s (only DAY and GTC are accepted)", params.TimeInForce)
      }

      // 8. Validate and compute expire_timestamp
      var expireTimestamp string
      if params.ExpireTime.IsZero() {
          // If no ExpireTime set and TimeInForce=DAY, set to end of current UTC day
          if params.TimeInForce == "0" || params.TimeInForce == "DAY" {
              now := time.Now().UTC()
              endOfDay := time.Date(now.Year(), now.Month(), now.Day(), 23, 59, 59, 0, time.UTC)
              expireTimestamp = fmt.Sprintf("%d", endOfDay.Unix())
          } else {
              // GTC with no expire: set to 30 days from now
              expireTimestamp = fmt.Sprintf("%d", time.Now().Add(30*24*time.Hour).Unix())
          }
      } else {
          if params.ExpireTime.Before(time.Now()) {
              return nil, fmt.Errorf("ExpireTime must be in the future: %s", params.ExpireTime.String())
          }
          expireTimestamp = fmt.Sprintf("%d", params.ExpireTime.Unix())
      }

      // 9. Validate Symbol and Currency are non-empty
      if params.Symbol == "" {
          return nil, fmt.Errorf("Symbol (Tag 55) is required")
      }
      if params.Currency == "" {
          return nil, fmt.Errorf("Currency (Tag 15) is required")
      }

      // 10. Resolve security_listing_iid from Symbol+Currency
      listing, err := ListingMgrCli.FindSecurityListingBySymbolCurrency(ctx, params.Symbol, params.Currency)
      if err != nil {
          return nil, fmt.Errorf("failed to resolve SecurityListing for symbol=%s currency=%s: %w",
              params.Symbol, params.Currency, err)
      }

      // 11. Validate ClOrdID
      if params.ClOrdID == "" {
          return nil, fmt.Errorf("ClOrdID (Tag 11) is required")
      }

      // 12. Generate derived fields
      externalOid := params.ClOrdID
      participantOid := common.ToParticipantOrderId(
          params.ParticipantId, params.ClOrdID, sagaSide, params.Symbol)
      idempotencyKey := common.RandomHexString(16) // 32-char hex string
      traceId := fmt.Sprintf("fix-%s-%d-%s",
          params.FIXVersion,
          params.TransactTime.UnixMilli(),
          common.SecureRandomString(8))

      // 13. Build data JSON
      dataMap := map[string]string{
          "fix_version":        params.FIXVersion,
          "participant_fix_compid":     params.ParticipantFixCompId,
          "fix_account":        params.AccountId,
          "fix_text":           params.ParticipantData,
          "fix_transact_time":  params.TransactTime.UTC().Format(time.RFC3339),
          "fix_time_in_force":  params.TimeInForce,
          "fix_client_order_id": params.ClOrdID,
          "fix_participant_id": params.ParticipantId,
      }
      if params.RequestId != "" {
          dataMap["request_id"] = params.RequestId
      }
      dataBytes, _ := json.Marshal(dataMap)
      dataStr := string(dataBytes)

      // 14. Build the request
      return &CreateDirectOrderRequest{
          ExternalOid:        externalOid,
          ParticipantOid:     participantOid,
          ExecRuntimeName:    "primary",
          SecurityListingIid: listing.Iid,
          ParticipantIid:     participantIid,
          InvestorIid:        params.InvestorIid,
          OrderType:          sagaOrderType,
          Quantity:           params.Quantity,
          Price:              params.Price,
          Side:               sagaSide,
          IdempotencyKey:     idempotencyKey,
          ExpireTimestamp:    expireTimestamp,
          DirectlyFillable:   "false",
          Slippage:           "0",
          TraceId:            traceId,
          Data:               dataStr,
      }, nil
  }
  ```

---

## Phase 4: Version-Specific Handler Rewrites

### Phase 4a: FIX 4.2 Handler

**File**: `pkg/daemons/fixreceiver/versions/v42/new_order_single.go`

- [ ] 4a.1.1 Remove `ExecutionError` struct and its methods (move to common if not already there — but NOTE: the common package's `saga_order_builder.go` uses Go errors instead, so this struct is fully removed)
- [ ] 4a.1.2 Remove `createExecutionPipelineArgumentsFromFIXMessageForNewOrderSingleCommnd` function entirely
- [ ] 4a.1.3 Remove `internalOnNewOrderSingle` function entirely
- [ ] 4a.1.4 Remove imports: `execpl`, `execpl/helpers`, `marketds/model/exchange`, `mq/exchange`
- [ ] 4a.1.5 Add new `extractFIXParamsV42` function:

  ```go
  func extractFIXParamsV42(
      msg *fix42nos.NewOrderSingle,
      sessionID quickfix.SessionID,
  ) (*fixcommon.CreateDirectOrderFromFIXParams, error) {
      params := &fixcommon.CreateDirectOrderFromFIXParams{
          FIXVersion:    "v42",
          ParticipantFixCompId:  sessionID.String(),
          ParticipantId: common.GetParticipantId(sessionID),
      }

      // Symbol (Tag 55) — required
      symbol, err := msg.GetSymbol()
      if err != nil {
          return nil, fmt.Errorf("error getting Symbol (Tag 55): %w", err)
      }
      params.Symbol = symbol

      // Currency (Tag 15) — required
      currency, err := msg.GetCurrency()
      if err != nil {
          return nil, fmt.Errorf("error getting Currency (Tag 15): %w", err)
      }
      params.Currency = currency

      // Side (Tag 54)
      enumSide, err := msg.GetSide()
      if err != nil {
          return nil, fmt.Errorf("error getting Side (Tag 54): %w", err)
      }
      params.Side = string(enumSide)

      // OrdType (Tag 40)
      enumOrdType, err := msg.GetOrdType()
      if err != nil {
          return nil, fmt.Errorf("error getting OrdType (Tag 40): %w", err)
      }
      params.OrderType = string(enumOrdType)

      // OrderQty (Tag 38)
      qty, err := msg.GetOrderQty()
      if err != nil {
          return nil, fmt.Errorf("error getting OrderQty (Tag 38): %w", err)
      }
      params.Quantity = qty.String()

      // Price (Tag 44)
      price, err := msg.GetPrice()
      if err != nil {
          return nil, fmt.Errorf("error getting Price (Tag 44): %w", err)
      }
      params.Price = price.String()

      // ClOrdID (Tag 11)
      clOrdID, err := msg.GetClOrdID()
      if err != nil {
          return nil, fmt.Errorf("error getting ClOrdID (Tag 11): %w", err)
      }
      params.ClOrdID = clOrdID

      // ExpireTime (Tag 126) — optional
      expireTime, _ := msg.GetExpireTime()
      params.ExpireTime = expireTime

      // TimeInForce (Tag 59)
      enumTIF, err := msg.GetTimeInForce()
      if err != nil {
          return nil, fmt.Errorf("error getting TimeInForce (Tag 59): %w", err)
      }
      params.TimeInForce = string(enumTIF)

      // ClientID (Tag 109) — investor_iid for FIX 4.2
      clientID, err := msg.GetClientID()
      if err != nil {
          return nil, fmt.Errorf("error getting ClientID (Tag 109, investor_iid): %w", err)
      }
      if clientID == "" {
          return nil, fmt.Errorf("ClientID (Tag 109) is required — it carries the investor_iid")
      }
      params.InvestorIid = clientID

      // Account (Tag 1) — stored in data JSON for traceability
      account, _ := msg.GetAccount()
      params.AccountId = account

      // TransactTime (Tag 60)
      transactTime, err := msg.GetTransactTime()
      if err != nil {
          return nil, fmt.Errorf("error getting TransactTime (Tag 60): %w", err)
      }
      params.TransactTime = transactTime

      // Text (Tag 58) — extract request_id if present
      text, _ := msg.GetText()
      params.ParticipantData = text
      if text != "" {
          type objWithReqId struct {
              RequestId string `json:"request_id"`
          }
          var reqIdObj objWithReqId
          if json.Unmarshal([]byte(text), &reqIdObj) == nil {
              params.RequestId = reqIdObj.RequestId
          }
      }

      return params, nil
  }
  ```

- [ ] 4a.1.6 Add new `internalOnNewOrderSingle` that uses the shared builder:

  ```go
  // internalOnNewOrderSingle returns (participantOrderId, sagaInstanceId, error).
  // participantOrderId is always computed (even on error) so the caller can use it
  // for sendExecutionReport which requires it for ParseParticipantOrderId.
  func internalOnNewOrderSingle(
      ctx context.Context,
      msg fix42nos.NewOrderSingle,
      sessionID quickfix.SessionID,
  ) (participantOrderId string, sagaInstanceId string, err quickfix.MessageRejectError) {
      // 1. Extract FIX params
      params, extractErr := extractFIXParamsV42(&msg, sessionID)
      if extractErr != nil {
          return "", "", quickfix.NewBusinessMessageRejectError(
              extractErr.Error(),
              fixcommon.BusinessRejectReasonInvalidField,
              nil,
          )
      }

      // 2. Compute participantOrderId early — needed for execution reports (both success and reject)
      //    This uses FIX message fields only, no saga dependency.
      participantOrderId = common.ToParticipantOrderId(
          params.ParticipantId, params.ClOrdID, params.Side, params.Symbol)

      // 3. Get participant_iid from session auth info
      authInfo, authErr := auth.GetSessionAuthInfo(ctx, sessionID)
      if authErr != nil {
          return participantOrderId, "", authErr
      }

      // 4. Build saga request via shared builder
      sagaReq, buildErr := fixcommon.BuildCreateDirectOrderRequest(ctx, *params, authInfo.ParticipantIid)
      if buildErr != nil {
          return participantOrderId, "", quickfix.NewBusinessMessageRejectError(
              buildErr.Error(),
              fixcommon.BusinessRejectReasonInvalidField,
              nil,
          )
      }

      // 5. Submit to listingmgr
      sagaId, submitErr := fixcommon.ListingMgrCli.SubmitCreateDirectOrder(ctx, *sagaReq)
      if submitErr != nil {
          return participantOrderId, "", quickfix.NewBusinessMessageRejectError(
              fmt.Sprintf("failed to submit order: %s", submitErr.Error()),
              fixcommon.BusinessRejectReasonInternalError,
              nil,
          )
      }

      common.L.Info("[4.2] create_direct_order saga submitted via listingmgr",
          zap.String("saga_instance_id", sagaId),
          zap.String("external_oid", params.ClOrdID),
          zap.String("sessionID", sessionID.String()))

      return participantOrderId, sagaId, nil
  }
  ```

- [ ] 4a.1.7 Update `getNewOrderSingleHandler` to call the new `internalOnNewOrderSingle` and send appropriate Execution Reports:

  ```go
  func getNewOrderSingleHandler(
      app *fixcommon.Application,
  ) func(fix42nos.NewOrderSingle, quickfix.SessionID) quickfix.MessageRejectError {
      return func(
          msg fix42nos.NewOrderSingle,
          sessionID quickfix.SessionID,
      ) quickfix.MessageRejectError {
          common.L.Info("[4.2] FIX onNewOrderSingle received",
              zap.String("sessionID", sessionID.String()))

          participantOrderId, sagaId, err := internalOnNewOrderSingle(app.Ctx, msg, sessionID)
          if err != nil {
              // Send REJECTED execution report using participantOrderId
              // (participantOrderId may be empty if extraction failed before it could be computed;
              //  in that case, fall back to returning the error directly)
              if participantOrderId != "" {
                  sendExecutionReport(participantOrderId, err.Error(), sessionID)
              }
              common.L.Warn("[4.2] FIX onNewOrderSingle rejected",
                  zap.String("sessionID", sessionID.String()),
                  zap.String("participantOrderId", participantOrderId),
                  zap.Error(err))
              return nil // Don't return error — we handled it via execution report
          }

          // Send NEW execution report (acknowledge order submission)
          sendNewExecutionReport(participantOrderId, sagaId, sessionID)
          common.L.Info("[4.2] FIX onNewOrderSingle submitted",
              zap.String("sessionID", sessionID.String()),
              zap.String("participantOrderId", participantOrderId),
              zap.String("sagaInstanceId", sagaId))
          return nil
      }
  }
  ```

- [ ] 4a.1.8 Add `sendNewExecutionReport` function (sends ExecType=NEW, OrdStatus=NEW):

  ```go
  // sendNewExecutionReport sends an Execution Report (8) with ExecType=NEW, OrdStatus=NEW
  // to acknowledge successful order submission to the saga system.
  // participantOrderId is used as OrderID (Tag 37) — same format as existing sendExecutionReport.
  func sendNewExecutionReport(
      participantOrderId string,
      sagaInstanceId string,
      sessionID quickfix.SessionID,
  ) {
      // Parse participantOrderId to extract clOrdID, side, symbol
      _, clientOrderId, sideStr, symbol, err := common.ParseParticipantOrderId(participantOrderId)
      // Build FIX 4.2 Execution Report message using fix42er.New(...)
      // ExecType (Tag 150) = enum.ExecType_NEW ("0")
      // OrdStatus (Tag 39) = enum.OrdStatus_NEW ("0")
      // OrderID (Tag 37) = participantOrderId
      // ExecID (Tag 17) = sagaInstanceId (or generated)
      // ClOrdID (Tag 11) = clientOrderId (parsed from participantOrderId)
      // Symbol (Tag 55) = symbol (parsed from participantOrderId)
      // Side (Tag 54) = side (parsed from participantOrderId)
      // Text (Tag 58) = saga_instance_id for traceability
      // quickfix.SendToTarget(execReport, sessionID)
  }
  ```

### Phase 4b: FIX 4.4 Handler

**File**: `pkg/daemons/fixreceiver/versions/v44/new_order_single.go`

- [ ] 4b.1.1 through 4b.1.8: Same pattern as Phase 4a, but using `fix44nos.NewOrderSingle` and `fix44` package types
- [ ] 4b.1.5 (specific): Extract investor_iid from Parties repeating group (same as FIX 5.0+ — FIX 4.4 does NOT have GetClientID)

### Phase 4c: FIX 5.0 Handler

**File**: `pkg/daemons/fixreceiver/versions/v50/new_order_single.go`

- [ ] 4c.1.1 through 4c.1.8: Same pattern as Phase 4a, but using `fix50nos.NewOrderSingle` and `fix50` package types
- [ ] 4c.1.5 (specific): Extract investor_iid from Parties repeating group:
  ```go
  // FIX 5.0: Extract investor_iid from Parties group (PartyRole=5)
  var investorIid string
  // Use the fix50 newordersingle generated Parties accessor
  // Iterate through NoPartyIDs group entries
  // Find entry where PartyRole == 13 (INVESTOR_ID)
  // investorIid = PartyID value from that entry
  if investorIid == "" {
      return nil, fmt.Errorf("Parties group must contain PartyRole=5 (InvestorID) with investor_iid as PartyID")
  }
  params.InvestorIid = investorIid
  ```

### Phase 4d: FIX 5.0SP1 Handler

**File**: `pkg/daemons/fixreceiver/versions/v50sp1/new_order_single.go`

- [ ] 4d.1.1 through 4d.1.8: Same pattern as Phase 4c (uses Parties group for investor_iid)

### Phase 4e: FIX 5.0SP2 Handler

**File**: `pkg/daemons/fixreceiver/versions/v50sp2/new_order_single.go`

- [ ] 4e.1.1 through 4e.1.8: Same pattern as Phase 4c (uses Parties group for investor_iid)

---

## Phase 5: Execution Report Functions — SUPERSEDED

> **Note**: Saga-level execution report emission from fixreceiver/listingmgr has been removed. Execution reports are now produced only at two points:
> 1. **fixclient**: Emits PENDING_NEW/PENDING_NEW when NOS is successfully submitted to the exchange (`exec_id` = `cl_ord_id`)
> 2. **tradeidxer**: Emits NEW/NEW when `DIRECT_ORDER_CREATE` on-chain event is detected (`exec_id` = `event_hash`)
>
> The `exec_report_helper.go` file, `pkgReportStore`/`reportStore` parameter, and `TRADEIDXER_POSTGRESQL_CONN_STRING` dependency have been removed from listingmgr. The fixreceiver NOS handler no longer sends immediate NEW ack execution reports — those are delivered asynchronously by fixsender after tradeidxer indexes the on-chain event.

- [x] 5.1.1 ~~Add `sendNewExecutionReport`~~ — REMOVED (exec reports now emitted by fixclient and tradeidxer, not by saga steps)
- [x] 5.1.2 Update existing `sendExecutionReport` (reject) to include:
  - ExecType (Tag 150) = `"8"` (Rejected)
  - OrdStatus (Tag 39) = `"8"` (Rejected)
  - Text (Tag 58) = error message

---

## Phase 6: Remove Old Pipeline Dependencies from NewOrderSingle

**Files** (one per version):
- `pkg/daemons/fixreceiver/versions/v42/new_order_single.go`
- `pkg/daemons/fixreceiver/versions/v44/new_order_single.go`
- `pkg/daemons/fixreceiver/versions/v50/new_order_single.go`
- `pkg/daemons/fixreceiver/versions/v50sp1/new_order_single.go`
- `pkg/daemons/fixreceiver/versions/v50sp2/new_order_single.go`

- [ ] 6.1.1 Remove all imports of:
  - `"qomet.tech/agora/daemons/pkg/execpl"` — execution pipeline types
  - `"qomet.tech/agora/daemons/pkg/execpl/helpers"` — off-chain order event helpers
  - `"qomet.tech/agora/daemons/pkg/marketds/model/exchange"` — exchange event types
  - `mqexchange "qomet.tech/agora/daemons/pkg/mq/exchange"` — RabbitMQ exchange publishing

- [ ] 6.1.2 Verify that the removed imports are NOT used by other handlers in the same package (e.g., `order_cancel_request.go`, `security_definition_request.go`). If they are, keep the import in those files but remove from `new_order_single.go`.

**IMPORTANT**: Do NOT remove the execution pipeline packages themselves (`pkg/execpl/`, `pkg/mq/exchange/`, etc.) — they are still used by `cmdprocessor`, `cmdbcaster`, and other daemons. Only remove their import/usage from `new_order_single.go` files.

**IMPORTANT**: Do NOT touch `execution_report.go` files — they still use `execpl.OutboundSignal` for the outbound signal handler (`handleExecutionReport`), which is a separate flow from NewOrderSingle. The `execpl` import must remain in `execution_report.go`.

---

## Phase 7: Unit Tests

**File**: `pkg/daemons/fixreceiver/versions/common/saga_order_builder_test.go` (NEW)

- [ ] 7.1.1 `TestBuildCreateDirectOrderRequest_ValidLimitBid` — Valid LIMIT BID params → correct saga input with all fields mapped
- [ ] 7.1.2 `TestBuildCreateDirectOrderRequest_ValidMarketBid` — MARKET BID → price=0, ORDER_TYPE_ENUM_MARKET
- [ ] 7.1.3 `TestBuildCreateDirectOrderRequest_ValidLimitAsk` — LIMIT ASK → ORDER_SIDE_ENUM_ASK
- [ ] 7.1.4 `TestBuildCreateDirectOrderRequest_MissingInvestorIid` — Empty investor_iid → error (fail immediately)
- [ ] 7.1.5 `TestBuildCreateDirectOrderRequest_MissingParticipantIid` — Empty participant_iid → error (fail immediately)
- [ ] 7.1.6 `TestBuildCreateDirectOrderRequest_InvalidSide` — Side "X" → error
- [ ] 7.1.7 `TestBuildCreateDirectOrderRequest_InvalidOrderType` — OrderType "STOP" → error
- [ ] 7.1.8 `TestBuildCreateDirectOrderRequest_ZeroQuantity` — Quantity "0" → error
- [ ] 7.1.9 `TestBuildCreateDirectOrderRequest_NegativeQuantity` — Quantity "-5" → error
- [ ] 7.1.10 `TestBuildCreateDirectOrderRequest_MarketOrderWithPrice` — MARKET + price "10.5" → error
- [ ] 7.1.11 `TestBuildCreateDirectOrderRequest_LimitOrderZeroPrice` — LIMIT + price "0" → error
- [ ] 7.1.12 `TestBuildCreateDirectOrderRequest_ExpiredTimestamp` — ExpireTime in past → error
- [ ] 7.1.13 `TestBuildCreateDirectOrderRequest_InvalidTimeInForce_IOC` — TimeInForce "3" (IOC) → error
- [ ] 7.1.14 `TestBuildCreateDirectOrderRequest_InvalidTimeInForce_FOK` — TimeInForce "4" (FOK) → error
- [ ] 7.1.15 `TestBuildCreateDirectOrderRequest_ValidTimeInForce_DAY` — TimeInForce "0" (DAY) → accepted
- [ ] 7.1.16 `TestBuildCreateDirectOrderRequest_ValidTimeInForce_GTC` — TimeInForce "1" (GTC) → accepted
- [ ] 7.1.17 `TestBuildCreateDirectOrderRequest_MissingSymbol` — Empty symbol → error
- [ ] 7.1.18 `TestBuildCreateDirectOrderRequest_MissingCurrency` — Empty currency → error
- [ ] 7.1.19 `TestBuildCreateDirectOrderRequest_MissingClOrdID` — Empty ClOrdID → error
- [ ] 7.1.20 `TestBuildCreateDirectOrderRequest_DataJsonContainsFIXMetadata` — Verify data JSON includes fix_version, participant_fix_compid, fix_account, etc.
- [ ] 7.1.21 `TestBuildCreateDirectOrderRequest_RequestIdExtractedFromText` — Text with `{"request_id":"xxx"}` → request_id in data JSON
- [ ] 7.1.22 `TestBuildCreateDirectOrderRequest_ExecRuntimeAlwaysPrimary` — Verify exec_runtime_name is always "primary"
- [ ] 7.1.23 `TestBuildCreateDirectOrderRequest_DefaultExpireTimeDayTIF` — No ExpireTime + DAY → end of day UTC
- [ ] 7.1.24 `TestBuildCreateDirectOrderRequest_DefaultExpireTimeGTCTIF` — No ExpireTime + GTC → 30 days from now

**Note**: Unit tests for `BuildCreateDirectOrderRequest` require mocking `ListingMgrCli.FindSecurityListingBySymbolCurrency`. Use an interface or inject a mock for the listing client.

---

## Phase 8: E2E Tests (Category 32 — ethbc mode)

**File**: `tests/e2e/laser/fix_new_order_single_saga_test.go` (NEW)

**Category**: 32 — FIX→Saga NewOrderSingle Integration
**Mode**: ethbc (requires Anvil blockchain)
**Makefile target**: `laser-e2e-ethbc-cat32`

### Test Infrastructure

- [ ] 8.1.1 Reuse CDO test infrastructure (`setupCDOTestInfrastructure`) which provides:
  - Deployed SecurityListing with on-chain trading pair
  - ParticipantIid, InvestorIid, ParticipantOid
  - Funded participant/investor accounts (via `fundCDOParticipantAccounts`)
- [ ] 8.1.2 Create FIX test client helper using quickfixgo initiator (or HTTP-based approach if FIX acceptor is not available in the E2E environment):
  - **Option A (recommended)**: Submit directly to listingmgr REST API via the shared `BuildCreateDirectOrderRequest` + `SubmitCreateDirectOrder` — this tests the mapping logic without requiring a running FIX acceptor
  - **Option B (full integration)**: Stand up a quickfixgo initiator in the test, connect to fixreceiver, send actual FIX messages

### Green Path Tests

- [ ] 8.2.1 `TestFIXNewOrderSingle_LimitBid_GreenPath`:
  - Fund accounts → Build FIX-like params (LimitBid) → Call `BuildCreateDirectOrderRequest` → Submit to listingmgr
  - Verify saga COMMITS
  - Verify Order record: side=BID, order_type=LIMIT, quantity, price, status=NEW
  - Verify OrderEvent: type=CREATE

- [ ] 8.2.2 `TestFIXNewOrderSingle_LimitAsk_GreenPath`:
  - Same pattern, side=ASK, verify investor has security tokens

- [ ] 8.2.3 `TestFIXNewOrderSingle_MarketBid_GreenPath`:
  - Same pattern, order_type=MARKET, price=0

- [ ] 8.2.4 `TestFIXNewOrderSingle_OrderFieldsMatchFIXInput`:
  - Submit order → Verify ALL Order fields match the FIX input params
  - Verify data JSON contains fix_version, participant_fix_compid, fix_account

- [ ] 8.2.5 `TestFIXNewOrderSingle_TraceIdGeneration`:
  - Submit order → Verify Order record has a trace_id starting with "fix-"

### Red Path Tests

- [ ] 8.3.1 `TestFIXNewOrderSingle_MissingSymbol`:
  - Empty Symbol → `BuildCreateDirectOrderRequest` returns error

- [ ] 8.3.2 `TestFIXNewOrderSingle_InvalidSide`:
  - Side "3" (SHORT_SELL) → error

- [ ] 8.3.3 `TestFIXNewOrderSingle_InvalidOrderType`:
  - OrdType "3" (STOP) → error

- [ ] 8.3.4 `TestFIXNewOrderSingle_ZeroQuantity`:
  - Quantity "0" → error

- [ ] 8.3.5 `TestFIXNewOrderSingle_MarketOrderWithPrice`:
  - MARKET + price "10.5" → error

- [ ] 8.3.6 `TestFIXNewOrderSingle_LimitOrderZeroPrice`:
  - LIMIT + price "0" → error

- [ ] 8.3.7 `TestFIXNewOrderSingle_ExpiredTimestamp`:
  - ExpireTime in the past → error

- [ ] 8.3.8 `TestFIXNewOrderSingle_InvalidTimeInForce`:
  - TimeInForce "3" (IOC) → error

- [ ] 8.3.9 `TestFIXNewOrderSingle_MissingInvestorIid`:
  - Empty investor_iid → error

- [ ] 8.3.10 `TestFIXNewOrderSingle_NonExistentSymbol`:
  - Symbol "NOSUCH" + Currency "USD" → no listing found → error

- [ ] 8.3.11 `TestFIXNewOrderSingle_MissingParticipantIid`:
  - Empty participant_iid → error

### Compensation Tests

- [ ] 8.4.1 `TestFIXNewOrderSingle_UnfundedAccount_Compensation`:
  - Use UNFUNDED infrastructure → on-chain revert → saga COMPENSATED
  - Verify no residual Order records

- [ ] 8.4.2 `TestFIXNewOrderSingle_CompensationCleanup`:
  - After compensation, query by external_oid → no order found

### Idempotency Tests

- [ ] 8.5.1 `TestFIXNewOrderSingle_IdempotencyKey_NoDuplicates`:
  - Submit same order params twice → only one Order record exists

---

## Phase 9: Makefile Updates

**File**: `Makefile`

- [ ] 9.1.1 Add E2E Category 32 pattern:
  ```makefile
  E2E_CAT32_PATTERN := TestFIXNewOrderSingle
  ```

- [ ] 9.1.2 Add Category 32 target:
  ```makefile
  laser-e2e-ethbc-cat32:
  	@echo "Running E2E Category 32: FIX NewOrderSingle → Saga Integration (ethbc mode)"
  	$(MAKE) laser-e2e-run-ethbc PATTERN="$(E2E_CAT32_PATTERN)"
  ```

- [ ] 9.1.3 Add Category 32 to `e2e-cat-help` target output

---

## Phase 10: Documentation Updates

### 10a: Update E2E Test Catalog

**File**: `docs/E2E_TEST_CATALOG.md`

- [ ] 10a.1.1 Add Group 32 entry:

  ```markdown
  ## Group 32: FIX NewOrderSingle → Saga Integration Tests

  **Complexity**: ⭐⭐⭐⭐ HIGH

  **Makefile Category**: Cat 32 (`make laser-e2e-ethbc-cat32`)

  **Mode**: EthBC (requires Anvil blockchain)

  **Description**: Tests the FIX NewOrderSingle (MsgType=D) → create_direct_order saga integration. Verifies that FIX message fields are correctly mapped to saga inputs, orders are submitted via listingmgr REST API, and the full saga workflow (validate → on-chain → persist) completes. Tests cover all FIX field mapping edge cases, validation failures, compensation cleanup, and idempotency.

  **Services Required**: postgres, redis, rabbitmq, anvil, lasersvc, traxcoord, traxctrl, listingmgr, csdmsggw, instrmgr, accmgr

  **Test File**: `tests/e2e/laser/fix_new_order_single_saga_test.go`

  ### Green Path Tests
  | # | Test Function | Description |
  |---|---|---|
  | 1 | TestFIXNewOrderSingle_LimitBid_GreenPath | FIX Limit Buy → saga COMMITS, verify Order+OrderEvent |
  | 2 | TestFIXNewOrderSingle_LimitAsk_GreenPath | FIX Limit Sell → saga COMMITS |
  | 3 | TestFIXNewOrderSingle_MarketBid_GreenPath | FIX Market Buy → saga COMMITS |
  | 4 | TestFIXNewOrderSingle_OrderFieldsMatchFIXInput | Verify Order fields match FIX input |
  | 5 | TestFIXNewOrderSingle_TraceIdGeneration | Verify trace_id starts with "fix-" |

  ### Red Path Tests
  | # | Test Function | Description |
  |---|---|---|
  | 6 | TestFIXNewOrderSingle_MissingSymbol | Missing Symbol → error |
  | 7 | TestFIXNewOrderSingle_InvalidSide | Invalid Side → error |
  | 8 | TestFIXNewOrderSingle_InvalidOrderType | Invalid OrdType → error |
  | 9 | TestFIXNewOrderSingle_ZeroQuantity | Zero quantity → error |
  | 10 | TestFIXNewOrderSingle_MarketOrderWithPrice | MARKET + price>0 → error |
  | 11 | TestFIXNewOrderSingle_LimitOrderZeroPrice | LIMIT + price=0 → error |
  | 12 | TestFIXNewOrderSingle_ExpiredTimestamp | Past ExpireTime → error |
  | 13 | TestFIXNewOrderSingle_InvalidTimeInForce | IOC → error (only DAY/GTC) |
  | 14 | TestFIXNewOrderSingle_MissingInvestorIid | No investor → error |
  | 15 | TestFIXNewOrderSingle_NonExistentSymbol | Unknown symbol → error |
  | 16 | TestFIXNewOrderSingle_MissingParticipantIid | No participant in session → error |

  ### Compensation Tests
  | # | Test Function | Description |
  |---|---|---|
  | 17 | TestFIXNewOrderSingle_UnfundedAccount_Compensation | Unfunded → COMPENSATED |
  | 18 | TestFIXNewOrderSingle_CompensationCleanup | No residual records after compensation |

  ### Idempotency Tests
  | # | Test Function | Description |
  |---|---|---|
  | 19 | TestFIXNewOrderSingle_IdempotencyKey_NoDuplicates | Same order twice → one record |
  ```

- [ ] 10a.1.2 Add Group 32 to Table of Contents
- [ ] 10a.1.3 Update the "generated" footer line with new date and Group 32 addition

### 10b: Update CDO Saga TODO

**File**: `docs/TODO_CREATE_DIRECT_ORDER_SAGA.md`

- [ ] 10b.1.1 Update status line to reference FIX integration:
  ```
  > **Status**: PHASES 1-9, 12 COMPLETE — remaining: Phase 10 (E2E tests), Phase 11 (documentation)
  > **Related**: FIX NewOrderSingle integration — see `docs/TODO_FIX_NEW_ORDER_SINGLE_SAGA.md`
  ```

### 10c: Update Agent Summary

**File**: `docs/SUMMARY-FOR-AGENT.md`

- [ ] 10c.1.1 Add section about FIX→Saga order flow:

  ```markdown
  ### FIX NewOrderSingle → create_direct_order Saga

  The FIX receiver's NewOrderSingle handler (MsgType=D) submits orders through the
  `create_direct_order` TRAX saga via listingmgr's REST API. This replaces the previous
  execution pipeline (RabbitMQ → cmdprocessor → cmdbcaster).

  **Flow**: FIX message → fixreceiver parses fields → resolves SecurityListing from Symbol+Currency
  → gets participant_iid from session config → gets investor_iid from ClientID/PartyID
  → POSTs to listingmgr /api/v1/orders/create-direct → TRAX saga → on-chain order

  **Key files**:
  - `pkg/daemons/fixreceiver/versions/common/saga_order_builder.go` — shared FIX→saga mapping
  - `pkg/daemons/fixreceiver/versions/common/listingmgr_client.go` — listingmgr HTTP client
  - `pkg/daemons/fixreceiver/auth/auth.go` — AuthInfo with participant_iid

  **See**: `docs/TODO_FIX_NEW_ORDER_SINGLE_SAGA.md` for full specification
  ```

---

## Phase Ordering and Dependencies

```
Phase 1: FIX Session Config Extension (auth.go)
    ↓
Phase 2: ListingMgrClient methods (listingmgr_client.go)
    ↓
Phase 3: Shared FIX→Saga mapping (saga_order_builder.go)
    ↓
Phase 4: Version-specific handler rewrites (5 files, parallelizable)
    ↓
Phase 5: Execution Report functions (5 files, parallelizable with Phase 4)
    ↓
Phase 6: Remove old pipeline imports (5 files, done during Phase 4)
    ↓
Phase 7: Unit tests (saga_order_builder_test.go)
    ↓
Phase 8: E2E tests (fix_new_order_single_saga_test.go)
    ↓
Phase 9: Makefile updates
    ↓
Phase 10: Documentation updates
```

**Parallelizable**: Phases 4a-4e (all 5 version rewrites) can be done in parallel. Phase 5 can be done alongside Phase 4. Phase 7 can start once Phase 3 is done. Phase 10 can be done anytime.

---

## Files to Create/Modify Summary

### New Files
| File | Purpose |
|------|---------|
| `pkg/daemons/fixreceiver/versions/common/saga_order_builder.go` | Shared FIX→saga mapping logic |
| `pkg/daemons/fixreceiver/versions/common/saga_order_builder_test.go` | Unit tests for mapping logic |
| `tests/e2e/laser/fix_new_order_single_saga_test.go` | E2E tests (Category 32) |

### Modified Files
| File | Changes |
|------|---------|
| `pkg/daemons/fixreceiver/auth/auth.go` | Add `ParticipantIid` to `AuthInfo`, validate in `validateAuthInfo` |
| `pkg/daemons/fixreceiver/versions/common/listingmgr_client.go` | Add `FindSecurityListingBySymbolCurrency`, `SubmitCreateDirectOrder`, caching |
| `pkg/daemons/fixreceiver/versions/v42/new_order_single.go` | Replace execution pipeline with saga submission |
| `pkg/daemons/fixreceiver/versions/v44/new_order_single.go` | Replace execution pipeline with saga submission |
| `pkg/daemons/fixreceiver/versions/v50/new_order_single.go` | Replace execution pipeline with saga submission |
| `pkg/daemons/fixreceiver/versions/v50sp1/new_order_single.go` | Replace execution pipeline with saga submission |
| `pkg/daemons/fixreceiver/versions/v50sp2/new_order_single.go` | Replace execution pipeline with saga submission |
| `docs/TODO_CREATE_DIRECT_ORDER_SAGA.md` | Add cross-reference |
| `docs/E2E_TEST_CATALOG.md` | Add Category 32 |
| `docs/SUMMARY-FOR-AGENT.md` | Add FIX→saga architecture note |
| `Makefile` | Add Category 32 targets |

---

## Verification

```bash
# 1. Build after all changes
make bip-daemons

# 2. Run unit tests
make test

# 3. Run E2E Category 32 (FIX→Saga integration)
TEST_RUN_PATTERN="TestFIXNewOrderSingle" make laser-e2e-full-ethbc

# 4. Verify existing CDO tests still pass
make laser-e2e-ethbc-cat31

# 5. Verify category listing
make e2e-cat-help | grep "Cat 32"
```

---

## Out of Scope

1. **prtagent TradingService.CreateOrderAsync** — The gRPC stub in `pkg/daemons/prtagent/impl/v1/grpc/trading.go` should also call listingmgr, but this is a separate TODO. Note (2026-05-02): the broker-trading-side replacement gateway `brktrdapi` will absorb `CreateOrder` when it ships (see `docs/TODO_BRKTRDAPI_AND_BRKADMAPI.md`); the listingmgr-call work also needs to land there.
2. **FIX OrderCancelRequest → saga** — The cancel flow (`order_cancel_request.go`) still uses the old pipeline and will be migrated separately.
3. **FIX Drop Copy Gateway integration** — The DCG system (`TODO_FIX_DROP_COPY_GATEWAY.md`) needs to be updated to log saga-based orders, but this is separate.
4. **Real-time order status updates via FIX** — After saga submission, the FIX client receives a PENDING_NEW from fixclient and a NEW from tradeidxer (via fixsender). Subsequent status updates (fills, cancels) are emitted by tradeidxer from on-chain events and delivered by fixsender.
5. **Multiple execution runtimes** — Currently hardcoded to "primary". Supporting runtime selection per FIX session is a future enhancement.
6. **Batch orders via FIX** — The saga creates one order at a time. FIX batch/list orders are not supported.

---

*Document generated: 2026-02-27. TODO for FIX NewOrderSingle → create_direct_order saga integration. Parent: TODO_CREATE_DIRECT_ORDER_SAGA.md.*
