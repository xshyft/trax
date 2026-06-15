# TODO: Setup Security Listing - TRAX Saga Implementation

> **Status**: NOT STARTED
> **Created**: 2026-02-09
> **Parent Reference**: `deploy_trading_legal_mechanisms_for_legal_structure` saga (prerequisite: trading engine must be deployed)

## Overview

TRAX saga template `setup_security_listing` that creates a security listing (off-chain record) and deploys a trading pair on-chain using the `createPairV2` function on an already deployed Agora Engine diamond. The saga is owned by **listingmgr** and orchestrates work across csdmsggw, accmgr, and LASER.

**Key architectural points**:
- **Saga owner**: listingmgr (follows treassvc pattern where the domain-owning service runs its own saga steps, including on-chain calls via LASER mutation API)
- **createPairV2**: New `IAgoraEngineV1Dot6` function with separate trezor configurations for base and quote tokens. Currently has no Go bindings, no ATS operation, and no lcmgr handler.
- **csdmsggw config endpoint**: New aggregation endpoint that queries instrmgr (instruments) + accmgr (legal structures, treasury mechanisms) to return deployment configuration.
- **Idempotent listing creation**: If a SecurityListing already exists for the security+currency pair, the saga reuses it and only creates a new deployment for the specified execution runtime.

---

## Prerequisites (MUST be validated in Step 1)

1. **Trading Engine Diamond deployed** on the specified Execution Runtime (via `deploy_trading_legal_mechanisms_for_legal_structure` saga)
2. **Security and Cash Token authorized** and known to the CSD's instrmgr
3. **Treasury mechanisms deployed** for both the security issuer's legal structure and the cash token issuer's legal structure, on the same execution runtime
4. **No existing SecurityListingDeployment** for this security+currency pair on the specified execution runtime
5. **deployment_owner_participant** must have an active legal structure that owns the trading mechanism

---

## Saga Specification

### Inputs

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| security_fin_id_str | FinIdentifierString | Yes | Security identifier (e.g., "TICKER:AAPL", "ISIN:US12345") |
| currency_fin_id_str | FinIdentifierString | Yes | Currency identifier (e.g., "ISO4217:USD") |
| execution_runtime_name | string | Yes | Execution runtime for on-chain deployment (e.g., "primary") |
| trading_mechanism_slot_address | string | Yes | LASER slot address of deployed Agora Engine diamond |
| deployment_owner_participant_iid | string | Yes | Participant IID that owns the exchange deployment (legal structure owns trading mechanism) |
| listing_type | SecurityListingTypeEnum | Yes | Type of listing (e.g., STOCK, BOND, ETF) |
| locale | string | Yes | Locale for display names/descriptions (e.g., "en-US") |
| display_names | JSON string | Yes | Localized display names (e.g., `{"en-US": "AAPL/USD"}`) |
| descriptions | JSON string | Yes | Localized descriptions |
| identifiers | JSON string | No | Additional FinIdentifiers for the listing record |
| settlement_cycle | string | No | Settlement cycle (e.g., "T+2", default if not provided) |
| cfi_code | string | No | ISO 10962 CFI code (populated from CSD config if not provided) |
| labels | JSON string | No | Labels map |
| tags | JSON string | No | Tags array |
| metadata | JSON string | No | Metadata map |

### Validation Rules (Step 1)

1. All required inputs must be non-empty
2. `security_fin_id_str` and `currency_fin_id_str` must be valid FinIdentifierString format (`{Type}:{Identifier}`)
3. `listing_type` must be a valid SecurityListingTypeEnum value
4. If a SecurityListing exists with matching `security_identifier` + `currency_identifier`, verify no SecurityListingDeployment exists for the given `execution_runtime_name`
5. If a deployment already exists for the execution runtime, FAIL the saga
6. `trading_mechanism_slot_address` must be non-empty (actual on-chain verification happens in step 6)

### Saga Steps (7 steps)

| Step | Name | Service | Description |
|------|------|---------|-------------|
| 1 | `ssl_validate_inputs` | **listingmgr** | Validate inputs, check existing listing/deployment |
| 2 | `ssl_query_deployment_config` | **listingmgr** | Call csdmsggw for deployment configuration |
| 3 | `ssl_resolve_fee_collector` | **listingmgr** | Query accmgr for trading mechanism's clearing account |
| 4 | `ssl_create_or_reuse_security_listing` | **listingmgr** | Create or reuse SecurityListing record |
| 5 | `ssl_create_calendar` | **listingmgr** | Create empty Calendar for the listing |
| 6 | `ssl_create_pair_on_chain` | **listingmgr** | ATS+LASER mutation: createPairV2 on Agora Engine diamond |
| 7 | `ssl_create_deployment_and_event_records` | **listingmgr** | Create SecurityListingDeployment + SecurityListingEvent |

**Service Distribution**:
- **listingmgr**: Steps 1-7 (all steps; on-chain call made via LASER mutation HTTP API, same pattern as treassvc/fund_account)

---

## Data Flow Diagram

```
                    REST API Trigger
                          |
                          v
              POST /api/v1/security-listings/deploy
                          |
                          v
                   [TRAX Coordinator]
                          |
    +---------------------+---------------------+
    |                     |                     |
    v                     v                     v
Step 1: Validate    Step 2: Query CSD     Step 3: Resolve
  (listingmgr         (listingmgr           feeCollector
   store query)        -> csdmsggw)          (listingmgr
                          |                    -> accmgr)
                          v
                   csdmsggw aggregates:
                   instrmgr (instruments)
                   accmgr (legal structures,
                           treasury mechanisms)
    |                     |                     |
    v                     v                     v
Step 4: Create/     Step 5: Create        Step 6: createPairV2
 Reuse Listing       Calendar              (listingmgr
 (listingmgr DB)    (shared.calendars)      -> LASER mutation
                                              -> lcmgr
                                              -> Anvil/EVM)
                                                  |
                                                  v
                                           PairCreate event
                                           -> pair_id extracted
    |                     |                     |
    v                     v                     v
              Step 7: Create Deployment + Event Records
              (SecurityListingDeployment with pair_id)
              (SecurityListingEvent type=LISTING_DEPLOYMENT)
```

---

## createPairV2 Parameter Mapping

**Solidity struct**: `AgoraEngineInternal.CreatePairV2Params` (from `IAgoraEngineV1Dot6.sol`)

| CreatePairV2Params field | Source | Value |
|--------------------------|--------|-------|
| baseTokenTrezor | csdmsggw config | Security issuer's treasury slot address |
| baseTokenLedgerId | hardcoded | 1 |
| quoteTokenTrezor | csdmsggw config | Cash token issuer's treasury slot address |
| quoteTokenLedgerId | hardcoded | 1 |
| baseToken | csdmsggw config | `security_laser_slot_addr` (authorized_instrument_iid) |
| quoteToken | csdmsggw config | `cash_token_laser_slot_addr` (authorized_instrument_iid) |
| marker | hardcoded | 1 |
| active | hardcoded | true |
| openHour | hardcoded | 0 |
| closeHour | hardcoded | 0 |
| fixedFee | hardcoded | 0 |
| microPercentageFee | hardcoded | 0 |
| feeCollector | step 3 | Trading mechanism owner's clearing account slot address |
| minOrderVolume | hardcoded | 0 |
| autoMatch | hardcoded | true |
| data | hardcoded | empty bytes |

**Note**: All slot addresses are translated to Ethereum addresses by LASER's E1→E2 chain before the on-chain call.

---

## Implementation Phases

### Phase 1: Domain Model Updates

**File**: `pkg/fin/security_listing.go`

- [ ] 1.1.1 Add `SecurityListingEventTypeEnum_ListingDeployment SecurityListingEventTypeEnum = "SECURITY_LISTING_EVENT_TYPE_ENUM_LISTING_DEPLOYMENT"`

---

### Phase 2: LASER createPairV2 Operation

**File**: `pkg/laser/model/operation_name.go`

- [ ] 2.1.1 Add `OperationNameEnum_AgoraEnginePairManagerCreatePairV2 OperationNameEnum = "OPERATION_NAME_ENUM_AGORA_ENGINE_PAIR_MANAGER_CREATE_PAIR_V2"`

**File**: `pkg/laser/ats/arg_name.go`

- [ ] 2.2.1 Add ATS argument names for createPairV2 parameters:
  ```go
  ArgNameEnum_BaseTokenTrezor    ArgNameEnum = "base_token_trezor"
  ArgNameEnum_BaseTokenLedgerId  ArgNameEnum = "base_token_ledger_id"
  ArgNameEnum_QuoteTokenTrezor   ArgNameEnum = "quote_token_trezor"
  ArgNameEnum_QuoteTokenLedgerId ArgNameEnum = "quote_token_ledger_id"
  ArgNameEnum_BaseToken          ArgNameEnum = "base_token"
  ArgNameEnum_QuoteToken         ArgNameEnum = "quote_token"
  ArgNameEnum_Marker             ArgNameEnum = "marker"
  ArgNameEnum_Active             ArgNameEnum = "active"
  ArgNameEnum_OpenHour           ArgNameEnum = "open_hour"
  ArgNameEnum_CloseHour          ArgNameEnum = "close_hour"
  ArgNameEnum_FixedFee           ArgNameEnum = "fixed_fee"
  ArgNameEnum_MicroPercentageFee ArgNameEnum = "micro_percentage_fee"
  ArgNameEnum_FeeCollector       ArgNameEnum = "fee_collector"
  ArgNameEnum_MinOrderVolume     ArgNameEnum = "min_order_volume"
  ArgNameEnum_AutoMatch          ArgNameEnum = "auto_match"
  ```
  **Note**: `Data` and `LedgerId` arg names may already exist; reuse if so.

**File**: `contracts/go/contracts/facets/_agora/engine/agoraenginepairmanagerfacet/AgoraEnginePairManagerFacet.go`

- [ ] 2.3.1 Regenerate Go bindings to include `createPairV2` and `CreatePairV2Params` struct
- [ ] 2.3.2 Verify `PairCreate(indexed bytes32 pairId)` event is present in generated ABI
- [ ] 2.3.3 Verify `getPairTrezorConfig(bytes32 pairId)` query function is present

**Regeneration command**: Use `abigen` with updated ABI from compiled Solidity (`AgoraEnginePairManagerFacet.json`)

**File**: `pkg/daemons/lcmgr/ethbc_diamond_contract.go`

- [ ] 2.4.1 Add `mutationAgoraEnginePairManagerCreatePairV2()` handler:
  - Parse ATS arguments into `CreatePairV2Params` struct
  - Load PairManager facet ABI (from regenerated Go binding)
  - Pack the call: `pairManagerABI.Pack("createPairV2", params)`
  - Execute via diamond proxy: `c.sendTransactionWithABI(ctx, signerAddress, pairManagerABI, "createPairV2", params)`
  - Parse transaction receipt for `PairCreate` event to extract `pair_id` (bytes32)
  - Return `pair_id` as hex string in mutation result metadata
- [ ] 2.4.2 Add ABI loading for PairManager facet (follow pattern from existing facet ABIs)
- [ ] 2.4.3 Handle the `PairCreate(indexed bytes32 pairId)` event parsing:
  - Event signature: `keccak256("PairCreate(bytes32)")`
  - Extract `pairId` from `logs[0].Topics[1]` (indexed parameter)
  - Store in result: `result.Metadata["pair_id"] = hex.EncodeToString(pairId[:])`

**File**: `pkg/daemons/lcmgr/ledger/ethbc/mutator.go`

- [ ] 2.5.1 Add `OPERATION_NAME_ENUM_AGORA_ENGINE_PAIR_MANAGER_CREATE_PAIR_V2` to `isDiamondOperation()` switch statement
- [ ] 2.5.2 Verify routing to `EthBCDiamondContract` handler in `getOrCreateContract()`

---

### Phase 3: csdmsggw Deployment Config Endpoint

**File**: `pkg/daemons/csdmsggw/clients/accmgr_http_client.go` (NEW)

- [ ] 3.1.1 Create `AccMgrClient` struct with `baseURL` and `httpClient` (follow `InstrMgrClient` pattern from `instrmgr_http_client.go`)
- [ ] 3.1.2 `NewAccMgrClient(baseURL string) (*AccMgrClient, error)` constructor with health check
- [ ] 3.1.3 `GetLegalStructureToAuthorizedInstrumentRelations(ctx, authorizedInstrumentIid string)` - queries accmgr for legal structures linked to an authorized instrument
- [ ] 3.1.4 `GetLegalMechanismsByLegalStructure(ctx, legalStructureIid string, mechanismType string)` - queries accmgr for legal mechanisms with optional type filter
- [ ] 3.1.5 `GetLegalMechanismDeployments(ctx, legalMechanismIid string)` - queries accmgr for deployment records of a legal mechanism

**File**: `pkg/daemons/csdmsggw/api/v1/deployment_config_get.go` (NEW)

- [ ] 3.2.1 Create `SecurityListingDeploymentConfigResponse` struct:
  ```go
  type SecurityListingDeploymentConfigResponse struct {
      SecurityLaserSlotAddr     string `json:"security_laser_slot_addr"`
      CashTokenLaserSlotAddr   string `json:"cash_token_laser_slot_addr"`
      BaseTokenTrezorSlotAddr  string `json:"base_token_trezor_slot_addr"`
      QuoteTokenTrezorSlotAddr string `json:"quote_token_trezor_slot_addr"`
      Marker                   int    `json:"marker"`
      CFICode                  string `json:"cfi_code"`
      IssuerFinIdStr           string `json:"issuer_fin_id_str"`
      CSDIdentifier            string `json:"csd_identifier"`
      SecurityDisplayName      string `json:"security_display_name"`
      CashTokenDisplayName     string `json:"cash_token_display_name"`
  }
  ```
- [ ] 3.2.2 Create handler `getSecurityListingDeploymentConfig(c *gin.Context)`:
  - Query params: `security_fin_id_str`, `currency_fin_id_str`, `execution_runtime_name`
  - Step 1: Query instrmgr for security by fin_id_str search → get `authorized_instrument_iid`
  - Step 2: Query instrmgr for cash token by fin_id_str search → get `authorized_instrument_iid`
  - Step 3: For each authorized instrument, query accmgr for `LegalStructureToAuthorizedInstrumentRelation` → get `legal_structure_iid`
  - Step 4: For each legal structure, query accmgr for treasury legal mechanism (type=TREASURY)
  - Step 5: Get treasury mechanism deployment for the specified `execution_runtime_name` → extract treasury slot address
  - Step 6: Assemble and return config response
- [ ] 3.2.3 Validate all query params are present; return 400 if missing
- [ ] 3.2.4 Return 404 if security, cash token, or treasury not found
- [ ] 3.2.5 Return 200 with config on success

**File**: `pkg/daemons/csdmsggw.go`

- [ ] 3.3.1 Add `ACCOUNT_MANAGER_BASE_URL` environment variable
- [ ] 3.3.2 Initialize `AccMgrClient` alongside existing `InstrMgrClient`
- [ ] 3.3.3 Pass `AccMgrClient` to API initialization

**File**: `pkg/daemons/csdmsggw/api/v1/api.go`

- [ ] 3.4.1 Accept `AccMgrClient` parameter in `InitRESTRoutes()`
- [ ] 3.4.2 Register route: `GET /api/v1/security-listing-deployment-config`

---

### Phase 4: listingmgr TRAX Infrastructure

**File**: `pkg/daemons/listingmgr.go`

- [ ] 4.1.1 Add environment variables:
  - `LASER_SERVICE_BASE_URL` - LASER service URL for mutations
  - `LASER_CLIENT_AUTH_KEY` - LASER auth key
  - `LASER_CROWN_EXECUTOR_IID` - Crown executor IID for mutations
  - `CSDMSGGW_BASE_URL` - csdmsggw service URL for deployment config
  - `ACCOUNT_MANAGER_BASE_URL` - accmgr service URL for legal mechanism queries
  - `TRAX_CLUSTER_ID` - TRAX cluster ID
  - `TRAX_SAGA_SUBMITTER_ID` - Saga submitter ID
  - `TRAX_COORDINATOR_BASE_URL` - TRAX coordinator URL
  - `TRAX_CTRL_BASE_URL` - TRAX controller URL
- [ ] 4.1.2 Initialize TRAX saga submitter (follow `accmgr.go` pattern)
- [ ] 4.1.3 Initialize TRAX MQ client for executor message consumption
- [ ] 4.1.4 Call `trax_executors.RunExecutorsAsync()` to start saga step executors as goroutines
- [ ] 4.1.5 Pass LASER config, csdmsggw URL, and accmgr URL to executor packages via package-level variables

**File**: `pkg/daemons/listingmgr/stores/listing_store.go`

- [ ] 4.2.1 Add Calendar CRUD methods to `ListingStore` interface:
  ```go
  CreateCalendar(ctx context.Context, calendar *fin.Calendar) error
  GetCalendarByIid(ctx context.Context, iid string) (*fin.Calendar, error)
  ```

**File**: `pkg/daemons/listingmgr/stores/postgres/listing_store.go`

- [ ] 4.3.1 Implement `CreateCalendar()` - INSERT into `shared.calendars` + `shared.entities`
- [ ] 4.3.2 Implement `GetCalendarByIid()` - SELECT from `shared.calendars`

**File**: `pkg/daemons/listingmgr/stores/memory/listing_store.go`

- [ ] 4.4.1 Implement `CreateCalendar()` and `GetCalendarByIid()` for in-memory store

---

### Phase 5: Saga Step Executors

**Directory**: `pkg/daemons/listingmgr/trax/executors/setup_security_listing/` (NEW)

#### Step 1: ssl_validate_inputs
**File**: `validate_inputs.go`

- [ ] 5.1.1 Validate all required inputs exist and are non-empty
- [ ] 5.1.2 Parse `security_fin_id_str` and `currency_fin_id_str` to verify FinIdentifierString format
- [ ] 5.1.3 Query listingmgr store: search for existing SecurityListing with matching `security_identifier` + `currency_identifier`
- [ ] 5.1.4 If listing exists: query SecurityListingDeployments for that listing; check if any deployment has matching `execution_runtime_name`
- [ ] 5.1.5 If deployment exists for exec runtime → FAIL with descriptive error
- [ ] 5.1.6 Return: `security_listing_exists` ("true"/"false"), `existing_security_listing_iid` (if exists), `validation_status` = "success"
- [ ] 5.1.7 COMP: No-op (read-only validation)

#### Step 2: ssl_query_deployment_config
**File**: `query_deployment_config.go`

- [ ] 5.2.1 Build csdmsggw config URL: `{csdmsggwBaseURL}/api/v1/security-listing-deployment-config?security_fin_id_str={}&currency_fin_id_str={}&execution_runtime_name={}`
- [ ] 5.2.2 Make HTTP GET request with appropriate timeout (30s)
- [ ] 5.2.3 Parse response into config struct
- [ ] 5.2.4 Validate all required config fields are non-empty (security_laser_slot_addr, cash_token_laser_slot_addr, base_token_trezor_slot_addr, quote_token_trezor_slot_addr)
- [ ] 5.2.5 If cfi_code not provided in saga input, use value from CSD config
- [ ] 5.2.6 Return all config fields as step result map
- [ ] 5.2.7 COMP: No-op (read-only query)

#### Step 3: ssl_resolve_fee_collector
**File**: `resolve_fee_collector.go`

- [ ] 5.3.1 Extract `deployment_owner_participant_iid` from saga input
- [ ] 5.3.2 Query accmgr REST API: get legal structures for the participant
- [ ] 5.3.3 For the participant's legal structure: query legal mechanisms with type=TRADING
- [ ] 5.3.4 Find the trading mechanism matching `trading_mechanism_slot_address` (check Labels["slot_address"])
- [ ] 5.3.5 Get the legal structure that owns the trading mechanism → get `clearing_account_iid` from `legalStructure.Metadata["clearing_account_iid"]`
- [ ] 5.3.6 Query accmgr for the clearing account → get its LASER slot address (from Labels or account record)
- [ ] 5.3.7 Return: `fee_collector_slot_address`
- [ ] 5.3.8 COMP: No-op (read-only query)

#### Step 4: ssl_create_or_reuse_security_listing
**File**: `create_or_reuse_security_listing.go`

- [x] 5.4.1 Check `security_listing_exists` from step 1 output
- [x] 5.4.2 If listing exists: return `existing_security_listing_iid` → done
- [x] 5.4.3 If listing does NOT exist:
  - Generate IID: `fmt.Sprintf("sec_listing_%s", common.SecureRandomString(32))`
  - Parse JSON inputs: display_names, descriptions, identifiers, labels, tags, metadata
  - **Auto-generate TICKER FinIdentifier**: If no TICKER identifier exists in parsed identifiers, extract the ID parts from `security_fin_id_str` (e.g., `"TICKER:SECTKN5"` → `"SECTKN5"`) and `currency_fin_id_str` (e.g., `"TICKER:USD_DIGICLEAR_CSD"` → `"USD_DIGICLEAR_CSD"`), then create a TICKER FinIdentifier with value `"SecurityId/CurrencyId"` (e.g., `"SECTKN5/USD_DIGICLEAR_CSD"`). This is prepended to the identifiers array.
  - **Enrich metadata**: Add `security_fin_id_str`, `currency_fin_id_str`, `listing_type`, and `execution_runtime_name` from saga inputs to the metadata map.
  - Build `fin.SecurityListing` struct with:
    - Type from `listing_type` input
    - Status = `SecurityListingStatusEnum_Pending`
    - FinancialStatus = `SecurityListingFinancialStatusEnum_Normal`
    - SecurityIdentifier = `security_fin_id_str`
    - CurrencyIdentifier = `currency_fin_id_str`
    - CFICode from input or CSD config (step 2)
    - IssuerIdentifier from CSD config (step 2)
    - CSDIdentifier from CSD config (step 2)
    - SettlementCycle from input (or "T+2" default)
    - Metadata: `created_by_saga`, `idempotent_key`, plus enriched fields
  - Call `pkgListingStore.CreateSecurityListing(ctx, listing)`
- [x] 5.4.4 Return: `security_listing_iid`, `listing_created` ("true"/"false")
- [x] 5.4.5 COMP: If `listing_created == "true"`, delete the SecurityListing via `pkgListingStore.DeleteSecurityListing()`

#### Step 5: ssl_create_calendar
**File**: `create_calendar.go`

- [ ] 5.5.1 Generate calendar IID: `fmt.Sprintf("calendar_%s", common.SecureRandomString(32))`
- [ ] 5.5.2 Build `fin.Calendar` with:
  - Empty Entries (no events yet)
  - DisplayNames from locale: `{locale: "Trading Calendar for {security_fin_id_str}/{currency_fin_id_str}"}`
  - Tags: `["security-listing", "trading-calendar"]`
  - Metadata: `created_by_saga`, `security_listing_iid`
- [ ] 5.5.3 Call `pkgListingStore.CreateCalendar(ctx, calendar)`
- [ ] 5.5.4 Update SecurityListing: set `CalendarIid` to new calendar IID via `pkgListingStore.UpdateSecurityListing()`
- [ ] 5.5.5 Return: `calendar_iid`
- [ ] 5.5.6 COMP: Delete calendar (if created), revert SecurityListing.CalendarIid

#### Step 6: ssl_create_pair_on_chain
**File**: `create_pair_on_chain.go`

- [ ] 5.6.1 Extract all required parameters from previous step outputs:
  - `security_laser_slot_addr` (baseToken) from step 2
  - `cash_token_laser_slot_addr` (quoteToken) from step 2
  - `base_token_trezor_slot_addr` (baseTokenTrezor) from step 2
  - `quote_token_trezor_slot_addr` (quoteTokenTrezor) from step 2
  - `fee_collector_slot_address` (feeCollector) from step 3
  - `trading_mechanism_slot_address` from saga input
- [ ] 5.6.2 Get LASER auth key and crown executor IID from package config
- [ ] 5.6.3 Build ATS function declaration for `OperationNameEnum_AgoraEnginePairManagerCreatePairV2`:
  ```go
  funcDecl := ats.Func(string(model.OperationNameEnum_AgoraEnginePairManagerCreatePairV2)).
      Arguments(
          ats.String(string(ats.ArgNameEnum_BaseTokenTrezor)).Build(),
          ats.Int64(string(ats.ArgNameEnum_BaseTokenLedgerId)).Build(),
          ats.String(string(ats.ArgNameEnum_QuoteTokenTrezor)).Build(),
          ats.Int64(string(ats.ArgNameEnum_QuoteTokenLedgerId)).Build(),
          ats.String(string(ats.ArgNameEnum_BaseToken)).Build(),
          ats.String(string(ats.ArgNameEnum_QuoteToken)).Build(),
          ats.Int64(string(ats.ArgNameEnum_Marker)).Build(),
          ats.Bool(string(ats.ArgNameEnum_Active)).Build(),
          ats.Int64(string(ats.ArgNameEnum_OpenHour)).Build(),
          ats.Int64(string(ats.ArgNameEnum_CloseHour)).Build(),
          ats.Int64(string(ats.ArgNameEnum_FixedFee)).Build(),
          ats.Int64(string(ats.ArgNameEnum_MicroPercentageFee)).Build(),
          ats.String(string(ats.ArgNameEnum_FeeCollector)).Build(),
          ats.Int64(string(ats.ArgNameEnum_MinOrderVolume)).Build(),
          ats.Bool(string(ats.ArgNameEnum_AutoMatch)).Build(),
          ats.String(string(ats.ArgNameEnum_Data)).Build(),
      ).
      Build()
  ```
- [ ] 5.6.4 Build bound arguments with values from parameter mapping table
- [ ] 5.6.5 Build LASER async mutation request (follow Pattern from `transfer_from_clearing_to_destination.go`):
  ```go
  mutationReq := map[string]interface{}{
      "mutate_id":         fmt.Sprintf("mut_id_create-pair-v2-%s", idempotentKey),
      "idempotency_key":   idempotentKey,
      "from_slot_address": feeCollectorSlotAddress,  // caller/signer
      "to_slot_address":   tradingMechanismSlotAddress,  // target diamond
      "call_data": map[string]interface{}{
          "decl":      boundFunc.Decl,
          "arguments": boundFunc.Arguments,
          "returns":   []ats.BoundVariable{},
      },
      "metadata": map[string]string{
          "saga_step": "ssl_create_pair_on_chain",
      },
      "async": true,
  }
  ```
- [ ] 5.6.6 POST mutation to `{laserBaseURL}/executors/{crownExecutorIid}/mutation`
- [ ] 5.6.7 Poll `{laserBaseURL}/executors/{crownExecutorIid}/poll?future_id={futureId}` (180s timeout, 500ms interval)
- [ ] 5.6.8 Extract `agora_pair_id` from poll result metadata (lcmgr parses PairCreate event and stores pair_id in metadata)
- [ ] 5.6.9 Return: `agora_pair_id`, `create_pair_tx_hash`
- [ ] 5.6.10 COMP: No-op (on-chain operations cannot be reversed; log warning)

#### Step 7: ssl_create_deployment_and_event_records
**File**: `create_deployment_and_event_records.go`

- [ ] 5.7.1 Generate deployment IID: `fmt.Sprintf("sec_listing_deploy_%s", common.SecureRandomString(32))`
- [ ] 5.7.2 Build `fin.SecurityListingDeployment`:
  - Type = `SecurityListingDeploymentTypeEnum_LaserAndAgora`
  - SecurityListingIid from step 4
  - TradingLegalMechanismIid: query accmgr to get the legal mechanism IID for the trading_mechanism_slot_address
  - DeploymentDetails = `LaserAndAgoraSecurityListingDeploymentDetails{ExecutionRuntimeName, AgoraPairId}`
  - DisplayNames, Tags: `["security-listing-deployment", "laser-and-agora"]`
  - Metadata: `created_by_saga`, `idempotent_key`, `create_pair_tx_hash`
- [ ] 5.7.3 Call `pkgListingStore.CreateSecurityListingDeployment(ctx, deployment)`
- [ ] 5.7.4 Generate event IID: `fmt.Sprintf("sec_listing_event_%s", common.SecureRandomString(32))`
- [ ] 5.7.5 Build `fin.SecurityListingEvent`:
  - Type = `SecurityListingEventTypeEnum_ListingDeployment`
  - SecurityListingIid from step 4
  - Timestamp = current time (ISO 8601)
  - Initiator = `SecurityListingEventInitiatorEnum_System`
  - RelatedReferences: `{"deployment_iid": deploymentIid, "agora_pair_id": pairId, "execution_runtime_name": execRuntimeName}`
  - DisplayNames, Tags: `["security-listing-event", "deployment"]`
- [ ] 5.7.6 Call `pkgListingStore.CreateSecurityListingEvent(ctx, event)`
- [ ] 5.7.7 Update SecurityListing: append event IID to `EventIids`, set Status = `SecurityListingStatusEnum_Active`
- [ ] 5.7.8 Return: `deployment_iid`, `event_iid`
- [ ] 5.7.9 COMP: Delete deployment and event records, revert SecurityListing.EventIids and Status

#### Executor Registration
**File**: `saga.go`

- [ ] 5.8.1 Create `RunExecutorsAsync()` with `listingStore stores.ListingStore` parameter:
  ```go
  go run_ValidateInputs_Executor(ctx, mqClient, clusterId)
  go run_QueryDeploymentConfig_Executor(ctx, mqClient, clusterId)
  go run_ResolveFeeCollector_Executor(ctx, mqClient, clusterId)
  go run_CreateOrReuseSecurityListing_Executor(ctx, mqClient, clusterId)
  go run_CreateCalendar_Executor(ctx, mqClient, clusterId)
  go run_CreatePairOnChain_Executor(ctx, mqClient, clusterId)
  go run_CreateDeploymentAndEventRecords_Executor(ctx, mqClient, clusterId)
  ```
- [ ] 5.8.2 Create `UpdateListingStore(store stores.ListingStore)` for test database switching
- [ ] 5.8.3 Package-level variables: `pkgListingStore`, `pkgLaserBaseURL`, `pkgLaserAuthKey`, `pkgCrownExecutorIid`, `pkgCsdMsgGwBaseURL`, `pkgAccMgrBaseURL`

**File**: `pkg/daemons/listingmgr/trax/executors/run.go` (NEW)

- [ ] 5.8.4 Create `RunExecutorsAsync()` that calls the setup_security_listing saga's `RunExecutorsAsync()`
- [ ] 5.8.5 Create `UpdateListingStore()` for E2E test database switching

---

### Phase 6: REST API Trigger

**File**: `pkg/daemons/listingmgr/api/v1/security_listings_post_deploy.go` (NEW)

- [ ] 6.1.1 Create `setupSecurityListingRequest` struct with all body input fields
- [ ] 6.1.2 Create `setupSecurityListingResponse` struct: `{saga_instance_id, status}`
- [ ] 6.1.3 Implement `postSetupSecurityListing(c *gin.Context)` handler:
  - Bind JSON body to request struct
  - Validate all required fields
  - Build saga input `map[string]string` from request fields (JSON-marshal complex fields)
  - Submit saga via `traxSagaSubmitter.SubmitSaga()` with template `setup_security_listing`
  - Return `201 Created` with saga instance ID

**File**: `pkg/daemons/listingmgr/api/v1/api.go`

- [ ] 6.2.1 Accept TRAX saga submitter in `Init()` function
- [ ] 6.2.2 Register route: `POST /api/v1/security-listings/deploy` -> `postSetupSecurityListing`

---

### Phase 7: Saga Template SQL

**File**: `deploy/k8s/init/csd/min/trax.sql`

- [ ] 7.1.1 Add saga template INSERT for `setup_security_listing`:
  ```sql
  INSERT INTO trax.saga_templates (
      template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
  ) VALUES (
      'setup_security_listing',
      'Setup Security Listing',
      'Creates security listing record and deploys trading pair on-chain via createPairV2',
      '{"short_id": "ssl"}'::jsonb,
      '["agora", "csd", "saga", "security-listing", "pair", "createPairV2"]'::jsonb,
      '{}'::jsonb,
      '["ssl_validate_inputs", "ssl_query_deployment_config", "ssl_resolve_fee_collector", "ssl_create_or_reuse_security_listing", "ssl_create_calendar", "ssl_create_pair_on_chain", "ssl_create_deployment_and_event_records"]'::jsonb
  ) ON CONFLICT (template_id) DO NOTHING;
  ```
- [ ] 7.1.2 Add 7 saga_step_template INSERTs with correct ordering and service labels (all `listingmgr`)
- [ ] 7.1.3 Update file header comment to include the new saga in the list

**File**: `deploy/k8s/init/prtagent/min/trax.sql`

- [ ] 7.2.1 Add `setup_security_listing` saga template and step templates if applicable for prtagent flavor

**File**: `deploy/k8s/init/exchange/min/trax.sql` (if exists)

- [ ] 7.3.1 Add `setup_security_listing` saga template and step templates for exchange flavor

---

### Phase 8: E2E Tests (ethbc mode)

**File**: `tests/e2e/laser/security_listing_deployment_test.go` (NEW)

#### Test Setup

- [ ] 8.1.1 `setupTestDatabaseForSecurityListingDeployment(t)`:
  - Reuse existing Diamond test setup (E1/E2 executor configuration)
  - Initialize listingmgr schema (`initializeListingmgrSchema`)
  - Initialize csdmsggw schema (`initializeCsdmsggwSchema`)
  - Update listingmgr executor stores for test database
  - Pre-deploy required facets to lattice archive
  - Deploy a full legal participant via `setup_new_legal_participant` with `force_creation_of_trading_mechanism=true`
  - Issue a security token and a cash token via `process_new_instrument_authorization`
  - Return: trading_mechanism_slot_address, participant_iid, security_fin_id_str, cash_token_fin_id_str, exec_runtime_name

#### Green Path Tests

- [ ] 8.2.1 `TestSetupSecurityListing_FullFlow`:
  - Setup infrastructure (legal participant, trading mechanism, security, cash token)
  - Submit `setup_security_listing` saga via listingmgr REST endpoint
  - Wait for saga completion (5-minute timeout)
  - Verify saga status = COMMITTED
  - Query listingmgr: verify SecurityListing record exists with correct security_identifier, currency_identifier, status=ACTIVE
  - Query listingmgr: verify SecurityListingDeployment with correct agora_pair_id and execution_runtime_name
  - Query listingmgr: verify SecurityListingEvent with type=LISTING_DEPLOYMENT
  - Query listingmgr: verify Calendar exists and is linked to the listing

- [ ] 8.2.2 `TestSetupSecurityListing_VerifyOnChainPair`:
  - After full flow, verify on-chain pair via Anvil JSON-RPC:
  - Call `getPair(pairId)` on the Agora Engine diamond → verify baseToken, quoteToken, marker=1, active=true, feeCollector, autoMatch=true
  - Call `getPairTrezorConfig(pairId)` → verify baseTokenTrezor, quoteTokenTrezor, ledgerIds=1
  - Verify pair exists in `getPairs()` result

- [ ] 8.2.3 `TestSetupSecurityListing_ReuseExistingListing`:
  - Create listing via first saga run
  - Submit second saga run with DIFFERENT execution_runtime_name
  - Verify same SecurityListing IID is reused
  - Verify second SecurityListingDeployment is created
  - Verify second SecurityListingEvent is created

#### Red Path Tests

- [ ] 8.3.1 `TestSetupSecurityListing_DuplicateDeployment`:
  - Run full saga successfully
  - Submit same saga again with same execution_runtime_name
  - Verify saga FAILS in step 1 with "deployment already exists" error

- [ ] 8.3.2 `TestSetupSecurityListing_MissingTradingMechanism`:
  - Submit saga with non-existent trading_mechanism_slot_address
  - Verify saga FAILS in step 3 (resolve_fee_collector) with "trading mechanism not found" error

- [ ] 8.3.3 `TestSetupSecurityListing_InvalidFinIdStr`:
  - Submit saga with invalid security_fin_id_str (e.g., missing colon separator)
  - Verify saga FAILS in step 1 (validate_inputs) or step 2 (csdmsggw returns 400/404)

- [ ] 8.3.4 `TestSetupSecurityListing_MissingCSDConfig`:
  - Submit saga with a security_fin_id_str that doesn't exist in instrmgr
  - Verify saga FAILS in step 2 (query_deployment_config) with 404 from csdmsggw

#### csdmsggw Config Endpoint Tests

- [ ] 8.4.1 `TestCsdMsgGw_DeploymentConfig_Success`:
  - Setup infrastructure with authorized instruments
  - Call GET /api/v1/security-listing-deployment-config with valid params
  - Verify response contains all expected fields

- [ ] 8.4.2 `TestCsdMsgGw_DeploymentConfig_SecurityNotFound`:
  - Call with non-existent security_fin_id_str
  - Verify 404 response

- [ ] 8.4.3 `TestCsdMsgGw_DeploymentConfig_MissingParams`:
  - Call with missing required query parameters
  - Verify 400 response

**File**: `Makefile`

- [ ] 8.5.1 Add new test category pattern variable (consider adding to an existing category or creating a new one):
  - If new category: `E2E_CAT_SSL_PATTERN := TestSetupSecurityListing|TestCsdMsgGw_DeploymentConfig`
  - Or add to existing CAT23 (CSD Message Gateway) for the config endpoint tests
  - And a new category for the full saga tests (higher complexity)

---

### Phase 9: Documentation Updates

**File**: `docs/SUMMARY-FOR-AGENT.md`

- [ ] 9.1.1 Add `setup_security_listing` to the list of major sagas with brief description
- [ ] 9.1.2 Add listingmgr service description: port 17209, TRAX executor, security listing management
- [ ] 9.1.3 Add csdmsggw deployment config endpoint reference

**File**: `docs/E2E_TEST_CATALOG.md`

- [ ] 9.2.1 Add new test group for Security Listing Deployment tests with complexity rating, test functions, and Makefile target
- [ ] 9.2.2 Update total test count

---

## Files Summary

### New Files

| File | Description |
|------|-------------|
| `pkg/daemons/listingmgr/trax/executors/setup_security_listing/saga.go` | Saga executor registration, package variables |
| `pkg/daemons/listingmgr/trax/executors/setup_security_listing/validate_inputs.go` | Step 1: Input validation |
| `pkg/daemons/listingmgr/trax/executors/setup_security_listing/query_deployment_config.go` | Step 2: Query csdmsggw |
| `pkg/daemons/listingmgr/trax/executors/setup_security_listing/resolve_fee_collector.go` | Step 3: Resolve clearing account |
| `pkg/daemons/listingmgr/trax/executors/setup_security_listing/create_or_reuse_security_listing.go` | Step 4: Create/reuse listing |
| `pkg/daemons/listingmgr/trax/executors/setup_security_listing/create_calendar.go` | Step 5: Create calendar |
| `pkg/daemons/listingmgr/trax/executors/setup_security_listing/create_pair_on_chain.go` | Step 6: ATS+LASER createPairV2 |
| `pkg/daemons/listingmgr/trax/executors/setup_security_listing/create_deployment_and_event_records.go` | Step 7: Create deployment + event |
| `pkg/daemons/listingmgr/trax/executors/run.go` | Central executor registry for listingmgr |
| `pkg/daemons/csdmsggw/api/v1/deployment_config_get.go` | csdmsggw deployment config endpoint |
| `pkg/daemons/csdmsggw/clients/accmgr_http_client.go` | AccMgr HTTP client for csdmsggw |
| `pkg/daemons/listingmgr/api/v1/security_listings_post_deploy.go` | REST API trigger for saga |
| `tests/e2e/laser/security_listing_deployment_test.go` | E2E tests (ethbc mode) |

### Modified Files

| File | Changes |
|------|---------|
| `pkg/fin/security_listing.go` | Add `SecurityListingEventTypeEnum_ListingDeployment` |
| `pkg/laser/model/operation_name.go` | Add `OperationNameEnum_AgoraEnginePairManagerCreatePairV2` |
| `pkg/laser/ats/arg_name.go` | Add 15 new ATS arg names for createPairV2 params |
| `pkg/daemons/lcmgr/ethbc_diamond_contract.go` | Add `mutationAgoraEnginePairManagerCreatePairV2()` handler + PairCreate event parsing |
| `pkg/daemons/lcmgr/ledger/ethbc/mutator.go` | Register createPairV2 in `isDiamondOperation()` |
| `contracts/go/...agoraenginepairmanagerfacet/` | Regenerated Go bindings with createPairV2 |
| `pkg/daemons/listingmgr.go` | Add TRAX infrastructure, LASER config, executor startup |
| `pkg/daemons/listingmgr/stores/listing_store.go` | Add Calendar CRUD interface methods |
| `pkg/daemons/listingmgr/stores/postgres/listing_store.go` | Implement Calendar CRUD for PostgreSQL |
| `pkg/daemons/listingmgr/stores/memory/listing_store.go` | Implement Calendar CRUD for in-memory |
| `pkg/daemons/listingmgr/api/v1/api.go` | Accept saga submitter, register deploy route |
| `pkg/daemons/csdmsggw.go` | Add accmgr client initialization |
| `pkg/daemons/csdmsggw/api/v1/api.go` | Accept AccMgrClient, register config route |
| `deploy/k8s/init/csd/min/trax.sql` | Add saga template + 7 step templates |
| `docs/SUMMARY-FOR-AGENT.md` | Add saga and service references |
| `docs/E2E_TEST_CATALOG.md` | Add new test group |
| `Makefile` | Add test category patterns |

### Patterns to Reuse

| Source File | Purpose |
|-------------|---------|
| `pkg/daemons/treassvc/trax/executors/fund_account_with_cash_tokens/transfer_from_clearing_to_destination.go` | ATS BoundFunc, LASER mutation POST, poll pattern |
| `pkg/daemons/treassvc/trax/executors/fund_account_with_cash_tokens/saga.go` | Executor registration, package variables pattern |
| `pkg/daemons/accmgr/trax/executors/run.go` | Central executor registry pattern |
| `pkg/daemons/csdmsggw/clients/instrmgr_http_client.go` | HTTP client constructor with health check |
| `deploy/k8s/init/csd/min/trax.sql` (process_new_instrument_authorization) | SQL saga template format |
| `tests/e2e/laser/trading_mechanism_deployment_test.go` | E2E test setup, Diamond verification, Anvil direct calls |
| `tests/e2e/laser/listingmgr_crud_test.go` | listingmgr HTTP request helpers, test DB setup |

---

## Success Criteria

- [ ] Saga creates correct on-chain pair with all parameters matching the specification
- [ ] Off-chain SecurityListing, SecurityListingDeployment, SecurityListingEvent records are created correctly
- [ ] Calendar is created and linked to the listing
- [ ] Duplicate deployment is correctly rejected
- [ ] Existing listing is reused when security+currency pair matches
- [ ] csdmsggw config endpoint aggregates data correctly from instrmgr and accmgr
- [ ] PairCreate event is correctly parsed to extract pair_id
- [ ] All E2E tests pass in ethbc mode
- [ ] On-chain verification via Anvil JSON-RPC confirms pair properties
- [ ] Compensation works correctly for steps 4, 5, 7

## Implementation Order

1. Phase 1: Domain model update (tiny, unblocks everything)
2. Phase 2: LASER createPairV2 operation (critical path: Go bindings, lcmgr handler, ATS)
3. Phase 3: csdmsggw config endpoint (independent of Phase 2)
4. Phase 4: listingmgr TRAX infrastructure (depends on Phase 1)
5. Phase 5: Saga step executors (depends on Phases 2, 3, 4)
6. Phase 6: REST API trigger (depends on Phase 4)
7. Phase 7: SQL saga templates (independent, can be done anytime)
8. Phase 8: E2E tests (depends on all above)
9. Phase 9: Documentation (last)

**Parallelizable**: Phases 2 and 3 can be done in parallel. Phase 7 can be done anytime.

## Verification

```bash
# Build after all changes
make bip-daemons

# Run specific E2E test
TEST_RUN_PATTERN="TestSetupSecurityListing" make laser-e2e-full-ethbc

# Run csdmsggw config endpoint tests
TEST_RUN_PATTERN="TestCsdMsgGw_DeploymentConfig" make laser-e2e-full-ethbc

# Check test results
cat .test-results/e2e/<session>/logs/test-runner.log
```

## Notes

- **createPairV2 Solidity location**: `/Users/kam/repos/NEW2/qomet/contracts/contracts/facets/_agora/engine/AgoraEngineInternal.sol` (lines 157-195)
- **PairCreate event**: Defined in `AgoraEnginePairManagerFacet.sol`; signature `PairCreate(indexed bytes32 pairId)`
- **CreatePairV2Params struct**: 16 fields (separate trezor configs for base/quote; V1 had single trezor)
- **IAgoraEngineV1Dot6**: Interface defining createPairV2, updatePairTrezorConfig, getPairTrezorConfig
- **LASER slot translation**: All slot addresses (e.g., authorized_instrument_iid) are translated to Ethereum addresses by the E1→E2 chain before the on-chain call
- **Marker**: Always 1 for this saga (allows deterministic pair ID calculation via `calculatePairId(baseToken, quoteToken, 1)`)
- **No database migration**: Schema changes go directly into CREATE statements (no release yet)
