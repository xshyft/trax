# TODO: Deploy Trading Legal Mechanisms for Legal Structure - TRAX Saga Implementation

> **Status**: CODE COMPLETE (Phases 1-10 implemented, compilation verified; E2E runtime testing pending)
> **Created**: 2026-02-09
> **Last Updated**: 2026-04-25
> **Parent Reference**: `deploy_core_legal_mechanisms_for_legal_structure` saga
>
> **Note (2026-04-25)**: References to `create_legal_participant_api_key`
> below are historical — the step was replaced by the generalised
> `create_api_keys` step in 2026-04-25. The trading-legal-mechanism
> deployment saga itself is unaffected; only the upstream
> `setup_new_legal_participant` saga's api-key step changed.

## Overview

TRAX saga template `deploy_trading_legal_mechanisms_for_legal_structure` that deploys Trading governance mechanisms (Agora Engine Diamond) for an existing legal structure that already has Core Legal Mechanisms deployed. This saga is EthBC-only and requires LASER for all contract operations.

**Key architectural difference from Treasury**: Treasury deploys 2 diamonds (RAC + Trezor); Trading Engine deploys a **single** diamond with 10 facets added directly and 2 algo facets referenced as address properties (not added to the diamond).

**Key Concepts**:
- **Agora Engine Diamond**: On-chain order matching, pair management, and settlement engine for exchange infrastructure
- **Algo Facets as Props**: MatcherAlgo and SettlerAlgo facets are pre-deployed standalone contracts whose addresses are stored as properties on the Agora Engine diamond via `PropsFacet.setAddress()` rather than being added as diamond facets
- **DIAMOND_PROPS_SET_ADDRESS**: New generic LASER operation for calling `PropsFacet.setAddress()` on any diamond (replacing the Trezor-specific `TREZOR_SET_ADDRESS` pattern)

---

## Prerequisites (MUST be validated in Step 1)

1. **Legal Structure exists** - must be PARTNERSHIP type
2. **Core Legal Mechanisms are deployed** on the specified Execution Runtime:
   - TaskManagerV2 contract deployed and initialized
   - AuthzDiamond contract deployed, initialized, and has AuthzFacet added
3. **No prior Trading Legal Mechanisms** have been deployed to the specified Exec Runtime
4. **Required facets available in lattice archive** (latest versions):
   - `rbac` - Role-Based Access Control facet
   - `props` - Properties/configuration facet
   - `agora-engine` - Core Agora Engine facet
   - `agora-engine-trade-manager` - Trade management facet
   - `agora-engine-pair-manager` - Trading pair management facet
   - `agora-engine-offer-manager` - Offer management facet
   - `agora-engine-matcher` - Order matching facet
   - `agora-engine-order-stats` - Order statistics facet
   - `agora-engine-direct-order-manager` - Direct order management facet
   - `agora-engine-direct-order-v2` - Direct order v2 + v2 query facets (shared version)
   - `agora-engine-matcher-algo` - Matcher algorithm facet (address prop only, NOT added to diamond)
   - `agora-engine-settler-algo` - Settler algorithm facet (address prop only, NOT added to diamond)
5. **admin_partner** must be:
   - One of the partners of the Legal Structure
   - One of the TaskManager admins
6. **authz_admin** must be one of the AuthzDiamond's admins (from Core deployment)

---

## Saga Specification

### Inputs

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| exec_runtime_name | string | Yes | Execution runtime for deployments (e.g., "primary") |
| locale | string | Yes | Locale for display names (e.g., "en-US") |
| legal_structure_iid | string | Yes | IID of the parent legal structure |
| admin_partner_slot_address | string | Yes | LASER slot address of admin partner (must be partner + TM admin) |
| authz_admin_slot_address | string | Yes | LASER slot address of AuthzDiamond admin (from Core deployment) |
| deployer_account_iid | string | Yes | Account IID with SIGNER slot for deployments |
| deployer_slot_address | string | Yes | LASER slot address for contract deployments |
| rbac_facet_version | string | Yes | Version of RBAC facet from lattice |
| props_facet_version | string | Yes | Version of Props facet from lattice |
| agora_engine_facet_version | string | Yes | Version of AgoraEngineFacet |
| agora_engine_trade_manager_facet_version | string | Yes | Version of AgoraEngineTradeManagerFacet |
| agora_engine_pair_manager_facet_version | string | Yes | Version of AgoraEnginePairManagerFacet |
| agora_engine_offer_manager_facet_version | string | Yes | Version of AgoraEngineOfferManagerFacet |
| agora_engine_matcher_facet_version | string | Yes | Version of AgoraEngineMatcherFacet |
| agora_engine_order_stats_facet_version | string | Yes | Version of AgoraEngineOrderStatsFacet |
| agora_engine_direct_order_manager_facet_version | string | Yes | Version of AgoraEngineDirectOrderManagerFacet |
| agora_engine_direct_order_v2_facet_version | string | Yes | Version of AgoraEngineDirectOrderManagerV2Facet + V2QueryFacet (shared) |
| agora_engine_matcher_algo_facet_version | string | Yes | Version of AgoraEngineMatcherAlgoFacet (address prop, NOT added to diamond) |
| agora_engine_settler_algo_facet_version | string | Yes | Version of AgoraEngineSettlerAlgoFacet (address prop, NOT added to diamond) |

**Note**: The `prefix` for slot/contract names is derived from the existing Core Legal Mechanisms deployment (same prefix used).

### Validation Rules (Step 1)

1. `legal_structure_iid` must reference an existing PARTNERSHIP legal structure
2. Core Legal Mechanisms must exist for this Legal Structure (query LegalMechanism records with types VOTING and AUTHORISATION_SOURCE)
3. No Trading mechanism (type TRADING) exists for this Legal Structure
4. `admin_partner_slot_address` must:
   - Belong to a partner in the Legal Structure's participant list
   - Be one of the TaskManager admins (from Core deployment)
5. `authz_admin_slot_address` must be one of the AuthzDiamond admins (from Core deployment)
6. `deployer_account_iid` must have an active SIGNER-tagged slot
7. All 12 facet version inputs must be non-empty

### Saga Steps (9 steps)

| Step | Name | Service | Description |
|------|------|---------|-------------|
| 1 | `verify_trading_mechanism_inputs` | **accmgr** | Validate inputs, verify Core exists, verify no Trading exists |
| 2 | `create_trading_engine_legal_mechanism` | **accmgr** | Create LegalMechanism record (type=TRADING), slot=`{prefix}-AgoraEngine` |
| 3 | `deploy_trading_engine_diamond_contract` | **laseragent** | Deploy Agora Engine Diamond via LASER using deployer |
| 4 | `initialize_trading_engine_diamond` | **laseragent** | Initialize diamond (admin-partner, AuthzSource, TaskManager, domain="AGORA_ENGINE") |
| 5 | `grant_add_facets_permission_to_admin_trading_engine` | **laseragent** | authz-admin grants addFacets permission to admin-partner on Agora Engine |
| 6 | `add_trading_engine_facets` | **laseragent** | admin-partner adds all 10 facets to Agora Engine diamond |
| 7 | `grant_set_address_permission_trading_engine` | **laseragent** | authz-admin grants setAddress permission to admin-partner on Agora Engine |
| 8 | `configure_algo_address_properties` | **laseragent** | admin-partner sets MatcherAlgo and SettlerAlgo addresses via DIAMOND_PROPS_SET_ADDRESS |
| 9 | `create_trading_engine_deployment_record` | **accmgr** | Create LegalMechanismDeployment for Agora Engine |

**Service Distribution**:
- **accmgr**: Steps 1, 2, 9 (legal mechanism domain records)
- **laseragent**: Steps 3, 4, 5, 6, 7, 8 (LASER contract operations)

---

## Implementation Phases

### Phase 1: Domain Model Updates

**File**: `pkg/fin/legal_mechanism.go`

- [x] 1.1.1 Add `LegalMechanismTypeEnum_Trading LegalMechanismTypeEnum = "LEGAL_MECHANISM_TYPE_ENUM_TRADING"`

---

### Phase 2: New Generic LASER Operations

**File**: `pkg/laser/model/operation_name.go`

- [x] 2.1.1 Add `OperationNameEnum_DiamondPropsSetAddress OperationNameEnum = "OPERATION_NAME_ENUM_DIAMOND_PROPS_SET_ADDRESS"`
- [x] 2.1.2 Add `OperationNameEnum_DiamondPropsSetInt OperationNameEnum = "OPERATION_NAME_ENUM_DIAMOND_PROPS_SET_INT"` (for future use)

**File**: `pkg/daemons/lcmgr/ethbc_diamond_contract.go`

- [x] 2.2.1 Add `mutationDiamondPropsSetAddress()` - clean generic version of `mutationTrezorSetAddress` (without RAC combined-call special case)
- [x] 2.2.2 Add `mutationDiamondPropsSetInt()` - clean generic version of `mutationTrezorSetInt`
- [x] 2.2.3 Add switch cases for the new operations in the main dispatch function

**Implementation notes**:
- `mutationTrezorSetAddress` (existing) has RAC-specific combined-call logic: it calls `setInt("rac.domain.id", ...)` AND `setAddress("rac.address", ...)` in the same transaction. The new generic `mutationDiamondPropsSetAddress` should NOT have this special case - it should only call `PropsFacet.setAddress(keyArr, valueArr)`.
- Pattern: accept `key` + `value` from LASER operation arguments, call `c.sendTransactionWithABI(ctx, signerAddress, c.propsABI, "setAddress", keyArr, valueArr)`
- `mutationDiamondPropsSetInt` follows the same pattern but calls `setInt(keyArr, valueArr)` instead

**File**: `pkg/daemons/lcmgr/ledger/ethbc/mutator.go`

- [x] 2.3.1 Add `OPERATION_NAME_ENUM_DIAMOND_PROPS_SET_ADDRESS` and `OPERATION_NAME_ENUM_DIAMOND_PROPS_SET_INT` to `isDiamondOperation()` switch statement (see Pattern L in Implementation Pattern Reference)
- [x] 2.3.2 Verify the new operations are correctly routed to `EthBCDiamondContract` handler in the `getOrCreateContract()` function

**File**: `pkg/laser/ats/arg_name.go` (may need update)

- [x] 2.4.1 Add `ArgNameEnum_PropsKeys ArgNameEnum = "props_keys"` if not already present
- [x] 2.4.2 Add `ArgNameEnum_PropsValues ArgNameEnum = "props_values"` if not already present

---

### Phase 3: Saga Template (SQL)

**File**: `deploy/k8s/init/csd/min/trax.sql`

- [x] 3.1.1 Add saga template `deploy_trading_legal_mechanisms_for_legal_structure` (follow pattern from treasury saga template at ~line 975)
- [x] 3.1.2 Add 9 saga_step_template records with correct ordering and service labels:

```sql
-- Step template IDs for deploy_trading_legal_mechanisms_for_legal_structure:
-- 1. dtlm_verify_trading_mechanism_inputs         (accmgr)
-- 2. dtlm_create_trading_engine_legal_mechanism    (accmgr)
-- 3. dtlm_deploy_trading_engine_diamond_contract   (laseragent)
-- 4. dtlm_initialize_trading_engine_diamond        (laseragent)
-- 5. dtlm_grant_add_facets_perm_trading_engine     (laseragent)
-- 6. dtlm_add_trading_engine_facets                (laseragent)
-- 7. dtlm_grant_set_address_perm_trading_engine    (laseragent)
-- 8. dtlm_configure_algo_address_properties        (laseragent)
-- 9. dtlm_create_trading_engine_deployment_record  (accmgr)
```

---

### Phase 4: API Endpoint

**File**: `pkg/daemons/accmgr/api/v1/legal_mechanisms_post_deploy_trading.go` (NEW)

- [x] 4.1.1 Create `deployTradingLegalMechanismsRequest` struct with all body input fields (locale + slot addresses + facet versions)
- [x] 4.1.2 Create `deployTradingLegalMechanismsResponse` struct (saga_instance_id, status)
- [x] 4.1.3 Implement `postDeployTradingLegalMechanisms(c *gin.Context)` handler:
  - Extract `legal_structure_iid` and `exec_runtime_name` from URL path params
  - Bind JSON body to request struct
  - Validate all required fields
- [x] 4.1.4 Build saga input map: merge URL path params + body fields into `map[string]string`
- [x] 4.1.5 Submit via `traxSagaSubmitter.SubmitSaga()` with template `deploy_trading_legal_mechanisms_for_legal_structure`
- [x] 4.1.6 Return `201 Created` with saga instance ID

**File**: `pkg/daemons/accmgr/api/v1/api.go`

- [x] 4.2.1 Add route in the legal mechanisms group: `POST /participant/:participant_iid/legal/structure/:legal_structure_iid/mechanism/:exec_runtime_name/trading/deploy` -> `postDeployTradingLegalMechanisms`

**Pattern**: Copy from `legal_mechanisms_post_deploy_treasury.go` and adapt field names (treasury has 8 facet versions, trading has 12).

---

### Phase 5: ACCMGR Executors

**Directory**: `pkg/daemons/accmgr/trax/executors/deploy_trading_legal_mechanisms_for_legal_structure/` (NEW)

#### Step 1: verify_trading_mechanism_inputs
**File**: `verify_inputs.go`

- [x] 5.1.1 Validate all required inputs exist (7 core fields + 12 facet version fields; use loop for facet versions like treasury's `facetVersionFields` slice pattern)
- [x] 5.1.2 Verify legal_structure_iid exists and is PARTNERSHIP type via `pkgAccountStore.GetLegalStructureByIid()`
- [x] 5.1.3 Verify clearing account exists and is ACTIVE (check `legalStructure.Metadata["clearing_account_iid"]`, then `pkgAccountStore.GetAccountByIid()`)
- [x] 5.1.4 Query existing LegalMechanisms via `pkgAccountStore.QueryLegalMechanismsByLegalStructure()`
- [x] 5.1.5 Verify Core mechanisms exist (VOTING + AUTHORISATION_SOURCE types)
- [x] 5.1.6 Verify no Trading mechanism exists (check for `LegalMechanismTypeEnum_Trading`)
- [x] 5.1.7 Retrieve Core deployment details using JSON marshal/unmarshal dance (see Pattern M): extract `task_manager_slot_address` from VOTING deployment, `authz_source_slot_address` from AUTHORISATION_SOURCE deployment, matching on `exec_runtime_name`
- [x] 5.1.8 Extract `prefix` from TaskManager slot address if not provided in input (see Pattern N: strip `-TaskManager` suffix)
- [x] 5.1.9 Verify deployer_account_iid has SIGNER tag (case-insensitive check on `deployerAccount.Tags`)
- [x] 5.1.10 Verify deployer account is ACTIVE status
- [x] 5.1.11 Log slot addresses for debugging (admin_partner, authz_admin, deployer - actual contract validation happens in LASERAGENT steps)
- [x] 5.1.12 Return: `verification_status=success`, `prefix`, `task_manager_contract_slot_address`, `authz_source_diamond_slot_address`
- [x] 5.1.13 COMP: No-op (read-only validation)

#### Step 2: create_trading_engine_legal_mechanism
**File**: `create_trading_engine_mechanism.go`

- [x] 5.2.1 Generate IID: `fmt.Sprintf("legal_mech_%s", common.SecureRandomString(32))`
- [x] 5.2.2 Generate slot_address: `fmt.Sprintf("%s-AgoraEngine", prefix)`
- [x] 5.2.3 Create `fin.LegalMechanism` with (see Pattern H for full field list):
  - Type = `fin.LegalMechanismTypeEnum_Trading`
  - DisplayNames/Descriptions with locale from input
  - Labels: `slot_address`, `legal_structure_iid`
  - Tags: `["legal-mechanism", "trading", "agora-engine"]`
  - Metadata: `created_by_saga`, `idempotent_key`, `slot_address`
- [x] 5.2.4 Call `pkgAccountStore.CreateLegalMechanism()`
- [x] 5.2.5 Return `trading_engine_mechanism_iid`, `trading_engine_diamond_slot_address`
- [x] 5.2.6 COMP: Get `trading_engine_mechanism_iid` from `s.executionResults`, then `pkgAccountStore.DeleteLegalMechanism()`

#### Step 9: create_trading_engine_deployment_record
**File**: `create_trading_engine_deployment.go`

- [x] 5.3.1 Extract `trading_engine_mechanism_iid` and `trading_engine_diamond_slot_address` from previous step outputs
- [x] 5.3.2 Generate IID: `fmt.Sprintf("legal_mech_deploy_%s", common.SecureRandomString(32))`
- [x] 5.3.3 Build `fin.LaserLegalMechanismDeploymentDetails` with `ExecutionRuntimeName` + `SlotAddress` (NOT ETH address - see Pattern I)
- [x] 5.3.4 Create `fin.LegalMechanismDeployment` with:
  - Type = `fin.LegalMechanismDeploymentTypeEnum_Laser`
  - DeploymentDetails = LaserLegalMechanismDeploymentDetails struct
  - DisplayNames/Descriptions, Labels, Tags (include "trading", "agora-engine", "laser"), Metadata
- [x] 5.3.5 Call `pkgAccountStore.CreateLegalMechanismDeployment()`
- [x] 5.3.6 Return `trading_engine_deployment_iid`
- [x] 5.3.7 COMP: Get `trading_engine_deployment_iid` from `s.executionResults`, then `pkgAccountStore.DeleteLegalMechanismDeployment()`

#### Executor Registration
**File**: `saga.go` (see Pattern C for full structure)

- [x] 5.4.1 Create `RunExecutorsAsync()` with `accountStore accmgr.AccountStore` parameter:
  ```
  go run_VerifyTradingMechanismInputs_Executor(ctx, mqClient, clusterId)
  go run_CreateTradingEngineLegalMechanism_Executor(ctx, mqClient, clusterId)
  go run_CreateTradingEngineDeploymentRecord_Executor(ctx, mqClient, clusterId)
  ```
- [x] 5.4.2 Create `UpdateAccountStore(store accmgr.AccountStore)` function for test database switching
- [x] 5.4.3 Package-level `pkgAccountStore` variable

**File**: `pkg/daemons/accmgr/trax/executors/run.go`

- [x] 5.4.4 Add call to new saga's `RunExecutorsAsync()` passing `accountStore`

---

### Phase 6: LASERAGENT Executors

**Directory**: `pkg/daemons/laseragent/trax/executors/deploy_trading_legal_mechanisms_for_legal_structure/` (NEW)

#### Step 3: deploy_trading_engine_diamond_contract
**File**: `deploy_trading_engine_diamond.go`

- [x] 6.1.1 Build ATS declaration for `OperationNameEnum_DeployDiamond` (Pattern E)
- [x] 6.1.2 Contract name = `{prefix}-AgoraEngine`, signer = deployer_slot_address
- [x] 6.1.3 Build LASER async mutation request with `mutate_id = "mut_id_deploy-trading-engine-diamond-{idempotentKey}"` (Pattern F)
- [x] 6.1.4 POST mutation, poll for completion (120s timeout, 500ms interval)
- [x] 6.1.5 Extract `tx_hash` from nested `pollResult.Future.Result.InnerResult.Metadata` (Pattern F)
- [x] 6.1.6 Return `trading_engine_deploy_tx_hash`
- [x] 6.1.7 COMP: No-op (on-chain immutable, Pattern G)

#### Step 4: initialize_trading_engine_diamond
**File**: `initialize_trading_engine_diamond.go`

- [x] 6.2.1 Build ATS declaration for `OperationNameEnum_InitializeDiamond` (Pattern E)
- [x] 6.2.2 Arguments: Admin = admin_partner_slot_address, AuthzSource = authz_source_diamond_slot_address (step 1), TaskManager = task_manager_contract_slot_address (step 1), authzDomain = `"AGORA_ENGINE"`
- [x] 6.2.3 Build LASER async mutation request with `mutate_id = "mut_id_init-trading-engine-diamond-{idempotentKey}"` (Pattern F)
- [x] 6.2.4 POST mutation, poll for completion (120s timeout, 500ms interval)
- [x] 6.2.5 Return `trading_engine_init_tx_hash`
- [x] 6.2.6 COMP: No-op (on-chain immutable)

#### Step 5: grant_add_facets_permission_to_admin_trading_engine
**File**: `grant_add_facets_perm.go`

- [x] 6.3.1 Build ATS declaration for `OperationNameEnum_SimpleAuthzAddAccount` (Pattern E)
- [x] 6.3.2 Signer = authz_admin_slot_address (from saga input)
- [x] 6.3.3 Target (to_slot_address) = authz_source_diamond_slot_address (from step 1 output, NOT the trading engine diamond)
- [x] 6.3.4 Arguments: account = admin_partner_slot_address, target = trading_engine_diamond_slot_address, permission = `addFacets(address[])`
- [x] 6.3.5 Build LASER async mutation, POST, poll (120s timeout)
- [x] 6.3.6 Return `grant_add_facets_trading_engine_tx_hash`
- [x] 6.3.7 COMP: No-op (on-chain immutable)

#### Step 6: add_trading_engine_facets
**File**: `add_trading_engine_facets.go`

- [x] 6.4.1 Extract + validate all facet version inputs (all 10 must be non-empty)
- [x] 6.4.2 Build facet slot addresses slice using `fmt.Sprintf("{ContractName}:%s", version)` format (Pattern J):
  ```go
  facetSlotAddresses := []string{
      fmt.Sprintf("RBACFacet:%s", rbacFacetVersion),
      fmt.Sprintf("PropsFacet:%s", propsFacetVersion),
      fmt.Sprintf("AgoraEngineFacet:%s", agoraEngineFacetVersion),
      fmt.Sprintf("AgoraEngineTradeManagerFacet:%s", agoraEngineTradeManagerFacetVersion),
      fmt.Sprintf("AgoraEnginePairManagerFacet:%s", agoraEnginePairManagerFacetVersion),
      fmt.Sprintf("AgoraEngineOfferManagerFacet:%s", agoraEngineOfferManagerFacetVersion),
      fmt.Sprintf("AgoraEngineMatcherFacet:%s", agoraEngineMatcherFacetVersion),
      fmt.Sprintf("AgoraEngineOrderStatsFacet:%s", agoraEngineOrderStatsFacetVersion),
      fmt.Sprintf("AgoraEngineDirectOrderManagerFacet:%s", agoraEngineDirectOrderManagerFacetVersion),
      fmt.Sprintf("AgoraEngineDirectOrderManagerV2Facet:%s", agoraEngineDirectOrderV2FacetVersion),
      fmt.Sprintf("AgoraEngineDirectOrderManagerV2QueryFacet:%s", agoraEngineDirectOrderV2FacetVersion),
  }
  ```
  **Note**: 11 entries in the array because V2 + V2Query are separate facets sharing version
- [x] 6.4.3 Build ATS declaration for `OperationNameEnum_DiamondAddFacets` with `ats.Array(ArgNameEnum_FacetAddresses, ...)` for the facet addresses array (Pattern E)
- [x] 6.4.4 Signer = admin_partner_slot_address, target = trading_engine_diamond_slot_address
- [x] 6.4.5 Build LASER async mutation, POST, poll (180s timeout for multi-facet operation)
- [x] 6.4.6 Return `add_trading_engine_facets_tx_hash`
- [x] 6.4.7 COMP: No-op (on-chain immutable)

**Note on facet #10**: `AgoraEngineDirectOrderManagerV2Facet` and `AgoraEngineDirectOrderManagerV2QueryFacet` share the same version input (`agora_engine_direct_order_v2_facet_version`) but are separate facet contracts with separate lattice entries. Both must be resolved and added.

#### Step 7: grant_set_address_permission_trading_engine
**File**: `grant_set_address_perm.go`

- [x] 6.5.1 Build ATS declaration for `OperationNameEnum_SimpleAuthzAddAccount` (Pattern E)
- [x] 6.5.2 Signer = authz_admin_slot_address (from saga input)
- [x] 6.5.3 Target (to_slot_address) = authz_source_diamond_slot_address (from step 1 output)
- [x] 6.5.4 Arguments: account = admin_partner_slot_address, target = trading_engine_diamond_slot_address, permission = `setAddress(string[],address[])`
- [x] 6.5.5 Build LASER async mutation, POST, poll (120s timeout)
- [x] 6.5.6 Return `grant_set_address_trading_engine_tx_hash`
- [x] 6.5.7 COMP: No-op (on-chain immutable)

#### Step 8: configure_algo_address_properties
**File**: `configure_algo_properties.go`

- [x] 6.6.1 Signer = admin_partner_slot_address
- [x] 6.6.2 Build algo facet slot addresses (Pattern J):
  ```go
  matcherAlgoSlotAddr := fmt.Sprintf("AgoraEngineMatcherAlgoFacet:%s", input["agora_engine_matcher_algo_facet_version"])
  settlerAlgoSlotAddr := fmt.Sprintf("AgoraEngineSettlerAlgoFacet:%s", input["agora_engine_settler_algo_facet_version"])
  ```
- [x] 6.6.3 Build ATS declaration for `OperationNameEnum_DiamondPropsSetAddress` (NEW operation - see Pattern O):
  - Arguments: Deployer (signer), LedgerContractSlotAddress (target diamond), PropsKeys (string[] keys), PropsValues (string[] slot addresses)
- [x] 6.6.4 Build bound arguments with key/value arrays:
  - Keys: `["agora.engine.global.matching.matcher.algo.facet", "agora.engine.global.matching.settler.algo.facet"]`
  - Values: `[matcherAlgoSlotAddr, settlerAlgoSlotAddr]` (LASER translates slot addresses to ETH addresses)
- [x] 6.6.5 Build LASER async mutation with `mutate_id = "mut_id_configure-algo-props-{idempotentKey}"`, POST, poll (120s timeout)
- [x] 6.6.6 Return `configure_algo_props_tx_hash`
- [x] 6.6.7 COMP: No-op (on-chain immutable)

**Implementation notes for DIAMOND_PROPS_SET_ADDRESS**:
- This calls `PropsFacet.setAddress(string[] keyArr, address[] valueArr)` on the target diamond
- Unlike TREZOR_SET_ADDRESS, this does NOT combine setAddress and setInt in one call
- The operation accepts `key` and `value` arguments via LASER ATS tuple
- Both algo addresses can be set in a single `setAddress` call (arrays with 2 entries each)
- The value slot addresses (e.g., `AgoraEngineMatcherAlgoFacet:latest`) are translated by LASER to actual ETH addresses from the lattice archive

#### Executor Registration
**File**: `saga.go` (see Pattern D for full structure)

- [x] 6.7.1 Create `RunExecutorsAsync()` with `laserConfigStore` parameter and 50ms stagger between each executor startup:
  ```
  run_DeployTradingEngineDiamondContract_Executor → 50ms →
  run_InitializeTradingEngineDiamond_Executor → 50ms →
  run_GrantAddFacetsPermTradingEngine_Executor → 50ms →
  run_AddTradingEngineFacets_Executor → 50ms →
  run_GrantSetAddressPermTradingEngine_Executor → 50ms →
  run_ConfigureAlgoProperties_Executor
  ```
- [x] 6.7.2 Create `UpdateConfigStore()` function for test database switching

**File**: `pkg/daemons/laseragent/trax/executors/run.go`

- [x] 6.7.3 Add call to new saga's `RunExecutorsAsync()` passing `cfgStore`

---

### Phase 7: setup_new_legal_participant Integration

**File**: `pkg/daemons/accmgr/trax/executors/setup_new_legal_participant/spawn_deploy_trading_engine.go` (NEW)

- [x] 7.1.1 Create struct with `mu sync.Mutex` + `inFlight map[string]chan struct{}` (Pattern K):
  ```go
  type spawnDeployTradingEngineMechanisms_IdempotentService struct {
      executionResults    map[string]*trax.IdempotentServiceExecutionResult
      compensationResults map[string]*trax.IdempotentServiceExecutionResult
      mu                  sync.Mutex
      inFlight            map[string]chan struct{}
  }
  ```
- [x] 7.1.2 Implement in-flight concurrency guard at top of `ExecuteSync()` (Pattern K: mutex + channel wait)
- [x] 7.1.3 Decision logic: check `input["force_creation_of_trading_mechanism"] == "true"`, if not set -> return `"trading_skipped": "true"`
- [x] 7.1.4 Pre-flight idempotency check: query `pkgAccountStore.QueryLegalMechanismsByLegalStructure()`, if `LegalMechanismTypeEnum_Trading` exists -> return success with existing data (extract deployment slot_address via JSON marshal/unmarshal dance)
- [x] 7.1.5 Validate required inputs: `legal_structure_iid`, `deployer_account_iid`, `deployer_slot_address`, `exec_runtime_name`
- [x] 7.1.6 Default facet versions to "latest" if not in parent input (12 facet versions)
- [x] 7.1.7 Build sub-saga input map (set `admin_partner_slot_address` and `authz_admin_slot_address` to `deployer_slot_address`)
- [x] 7.1.8 Create sub-saga executor: `trax.NewSubSagaExecutor(pkgSagaSubmitter, pkgTraxCtrlURL)`
- [x] 7.1.9 Spawn with fresh context: `context.WithTimeout(context.Background(), 10*time.Minute)` (Pattern K)
- [x] 7.1.10 Call `subSagaExecutor.SpawnAndWait()` with template `deploy_trading_legal_mechanisms_for_legal_structure`
- [x] 7.1.11 Extract outputs from `subSagaResult.Outputs` and return
- [x] 7.1.12 COMP: Log "sub-saga handles its own compensation" and return success
- [x] 7.1.13 `run_SpawnDeployTradingEngineMechanisms_Executor()`: register with step ID `snlp_spawn_deploy_trading_engine_mechanisms_saga` and init `inFlight: make(map[string]chan struct{})`

**Pattern**: Copy from `spawn_deploy_treasury.go` and adapt:
- Flag: `force_creation_of_trading_mechanism` (treasury uses `force_creation_of_treasury_mechanism`)
- Saga template: `deploy_trading_legal_mechanisms_for_legal_structure`
- Mechanism type check: `LegalMechanismTypeEnum_Trading` (not RAC + Treasury)

**File**: `pkg/daemons/accmgr/trax/executors/setup_new_legal_participant/saga.go`

- [x] 7.2.1 Add `go run_SpawnDeployTradingEngineMechanisms_Executor(ctx, mqClient, clusterId)` to `RunExecutorsAsync()` (after treasury spawner, before cash tokens spawner)
- [x] 7.2.2 Note: NO 50ms stagger needed in SNLP (only LASERAGENT executors need stagger)

**File**: `deploy/k8s/init/csd/min/trax.sql`

- [x] 7.3.1 Add new saga step template: `snlp_spawn_deploy_trading_engine_mechanisms_saga` (accmgr)
- [x] 7.3.2 Update `setup_new_legal_participant` saga_step_template_ids array to include new step between treasury and cash tokens:

```
New step order (8 steps):
1. snlp_create_legal_participant_record
2. snlp_create_or_validate_partner_participants
3. snlp_spawn_establish_legal_structure_saga
4. snlp_spawn_deploy_core_mechanisms_saga
5. snlp_spawn_deploy_treasury_mechanisms_saga
6. snlp_spawn_deploy_trading_engine_mechanisms_saga    <-- NEW
7. snlp_spawn_deploy_cash_tokens_saga
8. snlp_create_legal_participant_api_key
```

---

### Phase 8: SQL & Example Data Updates

**File**: `deploy/k8s/init/csd/min/trax.sql`

- [x] 8.1.1 Add saga template INSERT for `deploy_trading_legal_mechanisms_for_legal_structure`
- [x] 8.1.2 Add 9 saga_step_template INSERTs with correct ordering
- [x] 8.1.3 Add SNLP step template INSERT for `snlp_spawn_deploy_trading_engine_mechanisms_saga`
- [x] 8.1.4 Update SNLP saga_step_template_ids array (from 7 to 8 steps)

**File**: `deploy/k8s/init/prtagent/min/trax.sql`

- [x] 8.2.1 Mirror the setup_new_legal_participant changes if this file also defines the SNLP saga (add trading engine step template and update step array)

**File**: `deploy/k8s/init/init_accmgr_pgsql.sql`

- [x] 8.3.1 Add `LEGAL_MECHANISM_TYPE_ENUM_TRADING` to CHECK constraints or comments if they enumerate legal mechanism types

---

### Phase 9: E2E Tests

**File**: `tests/e2e/laser/trading_mechanism_deployment_test.go` (NEW)

#### Test Setup Functions

- [x] 9.1.1 `setupTestDatabaseForTradingMechanisms(t)` - reuse Diamond test setup pattern:
  - Call `setupDiamondTest(t)` for E1/E2 executor configuration
  - Call `UpdateAccountStore()` / `UpdateConfigStore()` on the trading saga's executor packages to switch database connections
  - Pre-deploy all required facets to lattice archive (12 facets including algo facets)
- [x] 9.1.2 `deployCoreLegalMechanismsPrereqForTrading(t, legalStructureIid)` - deploy Core mechanisms first:
  - Create deployer, partners, legal structure
  - Submit `deploy_core_legal_mechanisms_for_legal_structure` saga
  - Wait for completion
  - Return: admin slot address, authz admin slot address, deployer slot address

#### Green Path Tests

- [x] 9.2.1 `TestDeployTradingLegalMechanisms_FullFlow`
  - Setup: `setupTestDatabaseForTradingMechanisms(t)`, create deployer/partners/legal structure
  - Deploy Core Legal Mechanisms as prerequisite
  - Submit Trading saga via REST endpoint with all valid inputs (all 12 facet versions = "latest")
  - Wait for saga completion (15-minute timeout)
  - Verify saga status = COMMITTED
  - Query accmgr: verify LegalMechanism record (type=TRADING, slot_address = `{prefix}-AgoraEngine`)
  - Query accmgr: verify LegalMechanismDeployment record (type=LASER, ExecutionRuntimeName matches)
  - Use hardcoded IIDs for test entities per E2E test guidelines

- [ ] 9.2.2 `TestDeployTradingLegalMechanisms_VerifyDiamondFacets`
  - Deploy full flow (reuse FullFlow setup)
  - Use LASER CLI or API queries to verify:
    - Agora Engine diamond has all 10 facets (11 entries counting V2+V2Query separately)
    - Query `PropsFacet.getAddress("agora.engine.global.matching.matcher.algo.facet")` returns valid address
    - Query `PropsFacet.getAddress("agora.engine.global.matching.settler.algo.facet")` returns valid address

- [ ] 9.2.3 `TestDeployTradingLegalMechanisms_ViaSetupNewLegalParticipant`
  - Submit `setup_new_legal_participant` with `force_creation_of_trading_mechanism=true`
  - Wait for SNLP saga completion
  - Verify Trading mechanism deployed as part of full participant setup
  - Verify all other SNLP steps (core, treasury, cash tokens) also completed

#### Red Path Tests

- [x] 9.3.1 `TestDeployTradingLegalMechanisms_MissingCoreMechanisms`
  - Create legal structure WITHOUT deploying Core
  - Submit Trading saga
  - Verify saga fails at step 1 (Core mechanisms not found)

- [x] 9.3.2 `TestDeployTradingLegalMechanisms_DuplicateTrading`
  - Deploy Trading successfully
  - Attempt second Trading deployment
  - Verify saga fails at step 1 (Trading already exists)

- [x] 9.3.3 `TestDeployTradingLegalMechanisms_MissingExecRuntimeName`
  - Submit via REST endpoint without exec_runtime_name
  - Verify validation error

- [x] 9.3.4 `TestDeployTradingLegalMechanisms_MissingLegalStructureIid`
  - Submit via REST endpoint without legal_structure_iid
  - Verify validation error

- [x] 9.3.5 `TestDeployTradingLegalMechanisms_MissingAdminPartnerSlotAddress`
  - Submit via REST endpoint without admin_partner_slot_address
  - Verify validation error

- [x] 9.3.6 `TestDeployTradingLegalMechanisms_InvalidLegalStructure`
  - Submit saga with non-existent legal_structure_iid
  - Verify saga fails at step 1

- [ ] 9.3.7 `TestDeployTradingLegalMechanisms_InvalidFacetVersion`
  - Submit saga with non-existent facet version
  - Verify saga fails at step 6 (facet addition)

- [ ] 9.3.8 `TestDeployTradingLegalMechanisms_SkippedWhenFlagNotSet`
  - Submit setup_new_legal_participant WITHOUT `force_creation_of_trading_mechanism` flag
  - Verify trading engine step is skipped (returns success without deploying)

#### Makefile & Catalog Updates

**File**: `Makefile`

- [x] 9.4.1 Update `E2E_CAT4_PATTERN` to include trading tests:
  - Current: `TestDeployCoreLegalMechanisms|TestDeployTreasuryLegalMechanisms`
  - New: `TestDeployCoreLegalMechanisms|TestDeployTreasuryLegalMechanisms|TestDeployTradingLegalMechanisms`

**File**: `docs/E2E_TEST_CATALOG.md`

- [x] 9.4.2 Add trading mechanism deployment tests to Category 4 (Legal Mechanism Deployment)
- [x] 9.4.3 Add new test file: `tests/e2e/laser/trading_mechanism_deployment_test.go`
- [x] 9.4.4 Add test descriptions for all green and red path tests

---

### Phase 10: Documentation

**File**: `docs/SUMMARY-FOR-AGENT.md`

- [x] 10.1.1 Add section on Trading Engine Legal Mechanism deployment saga
- [x] 10.1.2 Document saga inputs/outputs
- [x] 10.1.3 Document relationship: Core mechanisms -> Trading Engine mechanisms (prereq chain)
- [x] 10.1.4 Document single-diamond architecture with algo facets as address props
- [x] 10.1.5 Document DIAMOND_PROPS_SET_ADDRESS as new generic LASER operation

---

## Data Flow Diagram

```
[Prerequisites: Core Legal Mechanisms Deployed]
    |
    v
[Saga Submit: deploy_trading_legal_mechanisms_for_legal_structure]
    |
    v
[Step 1: verify_trading_mechanism_inputs] (ACCMGR)
    |-- VALIDATE: Core mechanisms exist, no Trading exists
    |-- VALIDATE: admin_partner is partner + TM admin
    |-- VALIDATE: authz_admin is AuthzDiamond admin
    |-- VALIDATE: deployer has SIGNER slot
    |-- VALIDATE: all 12 facet versions provided
    |-- OUTPUT: prefix, task_manager_contract_slot_address, authz_source_diamond_slot_address
    v
[Step 2: create_trading_engine_legal_mechanism] (ACCMGR)
    |-- CREATE: LegalMechanism (TRADING), slot_address = {prefix}-AgoraEngine
    |-- OUTPUT: trading_engine_mechanism_iid, trading_engine_diamond_slot_address
    v
[Step 3: deploy_trading_engine_diamond_contract] (LASERAGENT)
    |-- LASER: DEPLOY_DIAMOND (deployer signs)
    |-- Contract name = {prefix}-AgoraEngine
    |-- OUTPUT: trading_engine_diamond_contract_address, trading_engine_deploy_tx_hash
    v
[Step 4: initialize_trading_engine_diamond] (LASERAGENT)
    |-- LASER: INITIALIZE_DIAMOND
    |-- Admin = admin_partner_slot_address
    |-- AuthzSource = authz_source_diamond_slot_address
    |-- TaskManager = task_manager_contract_slot_address
    |-- AuthzDomain = "AGORA_ENGINE"
    |-- OUTPUT: trading_engine_init_tx_hash
    v
[Step 5: grant_add_facets_permission_to_admin_trading_engine] (LASERAGENT)
    |-- LASER: SIMPLE_AUTHZ_ADD_ACCOUNT
    |-- Signer = authz_admin_slot_address
    |-- Grants addFacets to admin_partner on Agora Engine diamond
    |-- OUTPUT: grant_add_facets_trading_engine_tx_hash
    v
[Step 6: add_trading_engine_facets] (LASERAGENT)
    |-- LASER: DIAMOND_ADD_FACETS
    |-- Signer = admin_partner_slot_address
    |-- Adds 10 facets:
    |     1. RBACFacet
    |     2. PropsFacet
    |     3. AgoraEngineFacet
    |     4. AgoraEngineTradeManagerFacet
    |     5. AgoraEnginePairManagerFacet
    |     6. AgoraEngineOfferManagerFacet
    |     7. AgoraEngineMatcherFacet
    |     8. AgoraEngineOrderStatsFacet
    |     9. AgoraEngineDirectOrderManagerFacet
    |    10. AgoraEngineDirectOrderManagerV2Facet + V2QueryFacet
    |-- OUTPUT: add_trading_engine_facets_tx_hash
    v
[Step 7: grant_set_address_permission_trading_engine] (LASERAGENT)
    |-- LASER: SIMPLE_AUTHZ_ADD_ACCOUNT
    |-- Signer = authz_admin_slot_address
    |-- Grants setAddress to admin_partner on Agora Engine diamond
    |-- OUTPUT: grant_set_address_trading_engine_tx_hash
    v
[Step 8: configure_algo_address_properties] (LASERAGENT)
    |-- LASER: DIAMOND_PROPS_SET_ADDRESS (new generic operation)
    |-- Signer = admin_partner_slot_address
    |-- Sets on Agora Engine diamond:
    |     agora.engine.global.matching.matcher.algo.facet = MatcherAlgoFacet address
    |     agora.engine.global.matching.settler.algo.facet = SettlerAlgoFacet address
    |-- OUTPUT: configure_algo_props_tx_hash
    v
[Step 9: create_trading_engine_deployment_record] (ACCMGR)
    |-- CREATE: LegalMechanismDeployment (LASER) with Agora Engine address
    |-- OUTPUT: trading_engine_deployment_iid
    v
[SAGA COMMITTED]
```

---

## Service Execution Summary

```
ACCMGR (3 steps):     1 -> 2 ----------------------------------------> 9
                                \                                        \
LASERAGENT (6 steps):            3 -> 4 -> 5 -> 6 -> 7 -> 8
```

---

## Files Summary

### New Files

| File | Description |
|------|-------------|
| `docs/TODO_DEPLOY_TRADING_LEGAL_MECHANISMS_SAGA.md` | This TODO document |
| `pkg/daemons/accmgr/api/v1/legal_mechanisms_post_deploy_trading.go` | REST endpoint |
| `pkg/daemons/accmgr/trax/executors/deploy_trading_legal_mechanisms_for_legal_structure/saga.go` | ACCMGR executor registration |
| `pkg/daemons/accmgr/trax/executors/deploy_trading_legal_mechanisms_for_legal_structure/verify_inputs.go` | Step 1 |
| `pkg/daemons/accmgr/trax/executors/deploy_trading_legal_mechanisms_for_legal_structure/create_trading_engine_mechanism.go` | Step 2 |
| `pkg/daemons/accmgr/trax/executors/deploy_trading_legal_mechanisms_for_legal_structure/create_trading_engine_deployment.go` | Step 9 |
| `pkg/daemons/laseragent/trax/executors/deploy_trading_legal_mechanisms_for_legal_structure/saga.go` | LASERAGENT executor registration |
| `pkg/daemons/laseragent/trax/executors/deploy_trading_legal_mechanisms_for_legal_structure/deploy_trading_engine_diamond.go` | Step 3 |
| `pkg/daemons/laseragent/trax/executors/deploy_trading_legal_mechanisms_for_legal_structure/initialize_trading_engine_diamond.go` | Step 4 |
| `pkg/daemons/laseragent/trax/executors/deploy_trading_legal_mechanisms_for_legal_structure/grant_add_facets_perm.go` | Step 5 |
| `pkg/daemons/laseragent/trax/executors/deploy_trading_legal_mechanisms_for_legal_structure/add_trading_engine_facets.go` | Step 6 |
| `pkg/daemons/laseragent/trax/executors/deploy_trading_legal_mechanisms_for_legal_structure/grant_set_address_perm.go` | Step 7 |
| `pkg/daemons/laseragent/trax/executors/deploy_trading_legal_mechanisms_for_legal_structure/configure_algo_properties.go` | Step 8 |
| `pkg/daemons/accmgr/trax/executors/setup_new_legal_participant/spawn_deploy_trading_engine.go` | Sub-saga spawner in SNLP |
| `tests/e2e/laser/trading_mechanism_deployment_test.go` | E2E tests |

### Modified Files

| File | Changes |
|------|---------|
| `pkg/fin/legal_mechanism.go` | Add `LegalMechanismTypeEnum_Trading` enum |
| `pkg/laser/model/operation_name.go` | Add `DiamondPropsSetAddress` and `DiamondPropsSetInt` operations |
| `pkg/daemons/lcmgr/ethbc_diamond_contract.go` | Add `mutationDiamondPropsSetAddress()` and `mutationDiamondPropsSetInt()` handlers |
| `pkg/daemons/lcmgr/ledger/ethbc/mutator.go` | Register new operations in supported mutations list |
| `pkg/daemons/accmgr/api/v1/api.go` | Add trading deploy route |
| `pkg/daemons/accmgr/trax/executors/run.go` | Register ACCMGR executors for trading saga |
| `pkg/daemons/laseragent/trax/executors/run.go` | Register LASERAGENT executors for trading saga |
| `pkg/daemons/accmgr/trax/executors/setup_new_legal_participant/saga.go` | Add trading engine spawner to RunExecutorsAsync |
| `deploy/k8s/init/csd/min/trax.sql` | Add saga template (9 steps) + SNLP step (update from 7 to 8 steps) |
| `deploy/k8s/init/prtagent/min/trax.sql` | Mirror SNLP changes if applicable |
| `deploy/k8s/init/init_accmgr_pgsql.sql` | Add TRADING to type constraints/comments if applicable |
| `Makefile` | Add `TestDeployTradingLegalMechanisms` to `E2E_CAT4_PATTERN` |
| `docs/E2E_TEST_CATALOG.md` | Add trading mechanism tests to Category 4 |
| `docs/SUMMARY-FOR-AGENT.md` | Add Trading Engine saga section |

### Patterns to Reuse (copy from treasury saga)

| Source File | Purpose |
|-------------|---------|
| `pkg/daemons/accmgr/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/verify_inputs.go` | Verification pattern (adapt validations for TRADING type) |
| `pkg/daemons/accmgr/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/create_rac_mechanism.go` | Mechanism creation pattern (adapt type + slot name) |
| `pkg/daemons/accmgr/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/create_rac_deployment.go` | Deployment record pattern |
| `pkg/daemons/laseragent/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/deploy_rac_diamond.go` | Diamond deploy pattern |
| `pkg/daemons/laseragent/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/initialize_rac_diamond.go` | Diamond init pattern (adapt authzDomain to "AGORA_ENGINE") |
| `pkg/daemons/laseragent/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/grant_add_facets_perm_rac.go` | Permission grant pattern |
| `pkg/daemons/laseragent/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/add_vault_facets.go` | Multi-facet add pattern (adapt to 10 facets) |
| `pkg/daemons/laseragent/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/grant_set_address_perm.go` | setAddress permission pattern |
| `pkg/daemons/laseragent/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/configure_rac_properties.go` | Props configuration pattern (adapt to use DIAMOND_PROPS_SET_ADDRESS instead of TREZOR_SET_ADDRESS) |
| `pkg/daemons/accmgr/trax/executors/setup_new_legal_participant/spawn_deploy_treasury.go` | Sub-saga spawner pattern |
| `pkg/daemons/accmgr/api/v1/legal_mechanisms_post_deploy_treasury.go` | REST endpoint pattern |
| `tests/e2e/laser/treasury_mechanism_deployment_test.go` | E2E test pattern |

---

## Success Criteria

- [x] Domain model has TRADING type enum
- [x] New generic LASER operations registered (DIAMOND_PROPS_SET_ADDRESS, DIAMOND_PROPS_SET_INT)
- [x] Saga template registered correctly (verify via traxcli)
- [x] All 9 step executors start without errors
- [ ] Green path E2E tests pass (EthBC mode) -- pending runtime verification
- [ ] Red path E2E tests pass (validation failures) -- pending runtime verification
- [ ] Agora Engine diamond deployed with all 10 facets -- pending runtime verification
- [ ] Algo address properties configured (matcher.algo.facet, settler.algo.facet) -- pending runtime verification
- [ ] Deployment record created with correct contract address -- pending runtime verification
- [ ] Sub-saga spawner works via setup_new_legal_participant with force flag -- pending runtime verification
- [x] Documentation updated (SUMMARY-FOR-AGENT.md, E2E_TEST_CATALOG.md)

---

## Implementation Order

1. Phase 1: Domain Model Updates (add Trading type enum)
2. Phase 2: New Generic LASER Operations (DIAMOND_PROPS_SET_ADDRESS, DIAMOND_PROPS_SET_INT)
3. Phase 3: Saga Template SQL (9 steps)
4. Phase 4: API Endpoint on accmgr
5. Phase 5: ACCMGR Step Executors (steps 1, 2, 9)
6. Phase 6: LASERAGENT Step Executors (steps 3-8)
7. Phase 7: setup_new_legal_participant Integration (sub-saga spawner)
8. Phase 8: SQL & Example Data Updates
9. Phase 9: E2E Tests
10. Phase 10: Documentation

---

## Verification

### Unit Tests
```bash
make test
```

### E2E Tests (EthBC mode)
```bash
# Run just the trading mechanism tests
TEST_RUN_PATTERN="TestDeployTradingLegalMechanisms" make laser-e2e-full-ethbc

# Run full Category 4 (legal mechanism deployment)
make laser-e2e-ethbc-cat4
```

### Manual Verification
1. `make bip-daemons` to rebuild Docker images
2. Start e2e environment: `make laser-e2e-up`
3. Verify saga template registered: `make traxcli ARGS="templates list"`
4. Submit saga via REST endpoint and verify completion
5. Verify LegalMechanism record (type=TRADING) in accmgr
6. Verify LegalMechanismDeployment record with correct contract address
7. Verify diamond has 10 facets via LASER query
8. Verify algo address props set correctly

---

## Notes

- **EthBC-only**: This saga only works with real Ethereum blockchain, not RDBMS mode
- **Immutable contracts**: LASER contract deployments cannot be compensated (on-chain immutability)
- **Single-diamond architecture**: Unlike Treasury (RAC + Trezor), Trading Engine is one diamond
- **Permission flow**: authz-admin grants permissions, admin-partner executes operations
- **Core dependency**: This saga REQUIRES Core Legal Mechanisms to be deployed first
- **Prefix reuse**: Uses same prefix as Core deployment (retrieved from existing records)
- **Algo facets are NOT diamond facets**: MatcherAlgo and SettlerAlgo are standalone deployed contracts; their addresses are set as properties via PropsFacet.setAddress() on the Agora Engine diamond
- **DIAMOND_PROPS_SET_ADDRESS vs TREZOR_SET_ADDRESS**: The new generic operation does NOT combine setAddress+setInt like TREZOR_SET_ADDRESS does (no RAC-specific combined-call special case)
- **Facets from lattice**: All 12 facets are pre-deployed in lattice archive, referenced by version
- **DirectOrderV2 shared version**: AgoraEngineDirectOrderManagerV2Facet and AgoraEngineDirectOrderManagerV2QueryFacet share the same version input but are separate contracts
- **Sub-saga spawner**: Controlled by `force_creation_of_trading_mechanism` flag in setup_new_legal_participant; defaults to skip if not set
- **SNLP step ordering**: Trading engine deployment (step 6) runs AFTER treasury (step 5) and BEFORE cash tokens (step 7)

---

## Implementation Pattern Reference

> This section documents the exact patterns from the treasury saga implementation that MUST be replicated for the trading saga. Each pattern is verified against actual codebase source code.

### Pattern A: Idempotent Service Interface (6-method)

Every executor file implements the `trax.IdempotentService` interface with 6 methods:

```go
type <stepName>_IdempotentService struct {
    executionResults    map[string]*trax.IdempotentServiceExecutionResult
    compensationResults map[string]*trax.IdempotentServiceExecutionResult
}

// 1. GetIdempotentKeyExecutionStatus - check in-memory cache
// 2. ExecuteSync - main logic (check cache first, then execute)
// 3. ExecuteAsync - delegates to ExecuteSync in goroutine
// 4. GetIdempotentKeyCompensationStatus - check compensation cache
// 5. CompensateSync - compensation logic (on-chain = no-op, DB = delete)
// 6. CompensateAsync - delegates to CompensateSync in goroutine
```

**Critical**: `ExecuteSync` MUST check `s.executionResults[idempotentKey]` at the top and return the cached result if it exists. This is the idempotency guarantee.

**Error handling**: Errors are returned inside `trax.IdempotentServiceExecutionResult.Error`, NOT via the `error` return value. The `error` return is only for infrastructure failures.

```go
// CORRECT: Error in result struct
return &trax.IdempotentServiceExecutionResult{
    Result: map[string]string{},
    Error:  fmt.Errorf("missing required input field: %s", field),
}, nil

// WRONG: Error in return value
return nil, fmt.Errorf("missing required input")
```

### Pattern B: Executor Registration (run_ function + trax.NewExecutor)

Every executor file ends with a `run_<StepName>_Executor` function:

```go
func run_<StepName>_Executor(
    ctx context.Context,
    mqClient trax.MQClient,
    clusterId string,
) error {
    idempotentService := &<stepName>_IdempotentService{
        executionResults:    make(map[string]*trax.IdempotentServiceExecutionResult),
        compensationResults: make(map[string]*trax.IdempotentServiceExecutionResult),
    }
    trax.NewExecutor(
        mqClient,
        clusterId,
        sagaTemplateId,                // package-level const
        "<saga_step_template_id>",     // must match SQL step template ID
        idempotentService,
    ).Run(ctx)
    return nil
}
```

**Critical**: The `saga_step_template_id` string in `trax.NewExecutor()` MUST exactly match the `saga_step_template.id` in the SQL INSERT. Mismatch = executor never receives messages.

### Pattern C: ACCMGR saga.go Structure

```go
package trax__executors__deploy_trading_legal_mechanisms_for_legal_structure

const sagaTemplateId = "deploy_trading_legal_mechanisms_for_legal_structure"

var pkgAccountStore accmgr.AccountStore

func RunExecutorsAsync(ctx context.Context, mqClient trax.MQClient, clusterId string, accountStore accmgr.AccountStore) {
    pkgAccountStore = accountStore
    // ACCMGR owns steps 1, 2, 9
    go run_VerifyTradingMechanismInputs_Executor(ctx, mqClient, clusterId)
    go run_CreateTradingEngineLegalMechanism_Executor(ctx, mqClient, clusterId)
    go run_CreateTradingEngineDeploymentRecord_Executor(ctx, mqClient, clusterId)
}

func UpdateAccountStore(store accmgr.AccountStore) {
    pkgAccountStore = store
}
```

### Pattern D: LASERAGENT saga.go Structure (50ms stagger)

```go
package trax__executors__deploy_trading_legal_mechanisms_for_legal_structure

const sagaTemplateId = "deploy_trading_legal_mechanisms_for_legal_structure"

var laserConfigStore apiv1.ConfigStore

func RunExecutorsAsync(ctx context.Context, mqClient trax.MQClient, clusterId string, cfgStore apiv1.ConfigStore) {
    laserConfigStore = cfgStore
    // 50ms stagger between executor startups to prevent RabbitMQ channel overload
    go run_DeployTradingEngineDiamondContract_Executor(ctx, mqClient, clusterId)
    time.Sleep(50 * time.Millisecond)
    go run_InitializeTradingEngineDiamond_Executor(ctx, mqClient, clusterId)
    time.Sleep(50 * time.Millisecond)
    // ... repeat for each step
}

func UpdateConfigStore(cfgStore apiv1.ConfigStore) {
    laserConfigStore = cfgStore
}
```

### Pattern E: ATS Builder for LASER Mutations (3-step)

LASER operations use the ATS (Abstract Transaction Specification) builder. Every LASERAGENT step follows this 3-step pattern:

```go
// Step 1: Function declaration (operation name + argument types + return types)
funcDecl := ats.Func(string(model.OperationNameEnum_DiamondAddFacets)).
    Arguments(
        ats.String(string(ats.ArgNameEnum_Deployer)).Build(),
        ats.String(string(ats.ArgNameEnum_LedgerContractSlotAddress)).Build(),
        ats.Array(string(ats.ArgNameEnum_FacetAddresses), ats.String("").Build()).Build(),
    ).
    Returns(
        ats.String("tx_hash").Build(),
    ).
    Build()

// Step 2: Bound arguments (concrete values bound to declaration)
arguments := ats.NewBoundTuple().
    AddVar(ats.String(string(ats.ArgNameEnum_Deployer)).Build(), adminPartnerSlotAddress).
    AddVar(ats.String(string(ats.ArgNameEnum_LedgerContractSlotAddress)).Build(), diamondSlotAddress).
    AddVar(ats.Array(string(ats.ArgNameEnum_FacetAddresses), ats.String("").Build()).Build(), facetSlotAddresses).
    Build()

// Step 3: Build bound function
boundFunc := ats.NewBoundFunc(funcDecl).
    Arguments(arguments).
    Build()
```

**Note for multi-facet array**: Use `ats.Array(string(ats.ArgNameEnum_FacetAddresses), ats.String("").Build()).Build()` for array-type arguments. The second arg `ats.String("").Build()` defines the element type.

### Pattern F: LASER Async Mutation + Future Polling

Every LASERAGENT executor follows this flow:

```go
// 1. Build mutation request
laserMutationReq := map[string]interface{}{
    "mutate_id":         fmt.Sprintf("mut_id_<step-name>-%s", idempotentKey),
    "idempotency_key":   idempotentKey,
    "from_slot_address": signerSlotAddress,
    "to_slot_address":   targetSlotAddress,
    "call_data": map[string]interface{}{
        "decl":      boundFunc.Decl,
        "arguments": boundFunc.Arguments,
        "returns":   []ats.BoundVariable{},
    },
    "metadata": map[string]string{
        "saga_step": "<saga_step_template_id>",
        // additional context keys
    },
    "async": true,
}

// 2. Get LASER base URL + crown executor IID
laserBaseURL := common.GetServiceBaseURL("lasersvc")
cfg := laserConfigStore.GetConfig()
executorIid := cfg.CrownExecutorIid

// 3. POST to /executors/{executorIid}/mutation
// Headers: Content-Type: application/json, LASER_CLIENT_AUTH_KEY from env

// 4. Expect 202 Accepted with future_id

// 5. Poll GET /executors/{executorIid}/poll?future_id={futureId}
// Interval: 500ms
// Timeout: 120s (simple ops) or 180s (multi-facet ops)
// Check for: Completed|Success -> extract tx_hash
//            Error|ResultHandlingError|Timeout|Revert -> return error
```

**tx_hash extraction** (nested structure):
```go
var txHash string
if pollResult.Future.Result != nil {
    if pollResult.Future.Result.InnerResult != nil && pollResult.Future.Result.InnerResult.Metadata != nil {
        txHash = pollResult.Future.Result.InnerResult.Metadata["tx_hash"]
    } else if pollResult.Future.Result.Metadata != nil {
        txHash = pollResult.Future.Result.Metadata["tx_hash"]
    }
}
```

### Pattern G: Compensation Rules

| Step Type | Compensation | Example |
|-----------|-------------|---------|
| Read-only validation | NO-OP | `verify_inputs` |
| DB record creation | DELETE the record | `create_mechanism`, `create_deployment` |
| On-chain operation | NO-OP (log warning) | All LASERAGENT steps |

On-chain NO-OP pattern:
```go
func (s *xxx) CompensateSync(...) {
    common.L.Warn("compensation: <description> cannot be undone on-chain",
        zap.String("idempotent_key", idempotentKey))
    result = &trax.IdempotentServiceExecutionResult{Result: map[string]string{}, Error: nil}
    s.compensationResults[idempotentKey] = result
    return result, nil
}
```

DB record compensation pattern:
```go
func (s *xxx) CompensateSync(...) {
    execResult, exists := s.executionResults[idempotentKey]
    if !exists {
        // Nothing to compensate
        return &trax.IdempotentServiceExecutionResult{Result: map[string]string{}, Error: nil}, nil
    }
    mechanismIid := execResult.Result["trading_engine_mechanism_iid"]
    if mechanismIid != "" {
        err := pkgAccountStore.DeleteLegalMechanism(ctx, mechanismIid)
        // handle error...
    }
}
```

### Pattern H: Entity Creation (LegalMechanism + LegalMechanismDeployment)

**IID generation**:
```go
mechanismIid := fmt.Sprintf("legal_mech_%s", common.SecureRandomString(32))
deploymentIid := fmt.Sprintf("legal_mech_deploy_%s", common.SecureRandomString(32))
```

**LegalMechanism fields**:
```go
legalMechanism := &fin.LegalMechanism{
    Iid:               mechanismIid,
    Identifiers:       []fin.FinIdentifier{},
    Type:              fin.LegalMechanismTypeEnum_Trading,  // NEW enum
    LegalStructureIid: legalStructureIid,
    DisplayNames:      map[string]string{"en-US": fmt.Sprintf("%s Agora Engine", prefix)},
    Descriptions:      map[string]string{"en-US": fmt.Sprintf("Trading engine mechanism for %s legal structure", prefix)},
    Labels: map[string]string{
        "slot_address":        slotAddress,
        "legal_structure_iid": legalStructureIid,
    },
    Tags:     []string{"legal-mechanism", "trading", "agora-engine"},
    Metadata: map[string]string{
        "created_by_saga": sagaTemplateId,
        "idempotent_key":  idempotentKey,
        "slot_address":    slotAddress,
    },
}
```

**LegalMechanismDeployment fields**:
```go
deploymentDetails := fin.LaserLegalMechanismDeploymentDetails{
    ExecutionRuntimeName: execRuntimeName,
    SlotAddress:          tradingEngineDiamondSlotAddress,
    Metadata: map[string]string{
        "trading_engine_diamond_slot_address": tradingEngineDiamondSlotAddress,
    },
}
// NOTE: No eth_address/contract_address - accmgr only stores slot_address (E1 layer).
// Query lasersvc for slot translation if eth_address is needed at runtime.
```

### Pattern I: E1/E2 Layer Separation

**Critical rule**: Sagas NEVER pass Ethereum addresses between steps. Only symbolic slot addresses (E1 layer) flow through saga inputs/outputs. LASER handles E1 slot address -> E2 ETH address translation internally.

- `{prefix}-AgoraEngine` = symbolic slot address (E1 layer)
- `0x1234...abcd` = Ethereum address (E2 layer, NEVER in saga data)
- `RBACFacet:latest` = facet slot address (LASER resolves to ETH address from lattice)

### Pattern J: Facet Slot Address Format

Facets are referenced by `{ContractName}:{version}` format. LASER resolves these to actual ETH addresses from the lattice archive.

```go
facetSlotAddresses := []string{
    fmt.Sprintf("RBACFacet:%s", rbacFacetVersion),
    fmt.Sprintf("PropsFacet:%s", propsFacetVersion),
    fmt.Sprintf("AgoraEngineFacet:%s", agoraEngineFacetVersion),
    // ...
}
```

**Important**: ContractName MUST match the lattice contract name exactly (PascalCase, e.g., `RBACFacet` not `rbac-facet`).

### Pattern K: Sub-Saga Spawner (SNLP Integration)

The spawner needs these additional fields vs regular executors:

```go
type spawnDeployTradingEngineMechanisms_IdempotentService struct {
    executionResults    map[string]*trax.IdempotentServiceExecutionResult
    compensationResults map[string]*trax.IdempotentServiceExecutionResult
    mu                  sync.Mutex                    // concurrency guard
    inFlight            map[string]chan struct{}       // in-flight tracking
}
```

**In-flight concurrency guard** (prevents duplicate sub-saga spawning from MQ redelivery):
```go
s.mu.Lock()
if result, exists := s.executionResults[idempotentKey]; exists {
    s.mu.Unlock()
    return result, nil
}
if ch, ok := s.inFlight[idempotentKey]; ok {
    s.mu.Unlock()
    <-ch  // wait for first execution to complete
    // ... return cached result or retry
}
```

**Fresh context** (sub-saga spawning uses `context.Background()`, not parent context):
```go
subSagaCtx, subSagaCancel := context.WithTimeout(context.Background(), 10*time.Minute)
defer subSagaCancel()
```

**Facet version defaulting** (when spawned from SNLP):
```go
rbacFacetVersion := input["rbac_facet_version"]
if rbacFacetVersion == "" {
    rbacFacetVersion = "latest"
}
```

**Pre-flight idempotency check** (if mechanism already exists, return success):
```go
existingMechanisms, _, err := pkgAccountStore.QueryLegalMechanismsByLegalStructure(ctx, legalStructureIid, nil)
for i := range existingMechanisms {
    if existingMechanisms[i].Type == fin.LegalMechanismTypeEnum_Trading {
        // Already deployed, return success with existing data
    }
}
```

**Decision logic for trading engine spawner**:
```go
forceCreation := input["force_creation_of_trading_mechanism"] == "true"
if !forceCreation {
    // Skip - return success with "trading_skipped": "true"
}
```

### Pattern L: isDiamondOperation Registration (mutator.go)

New operations MUST be added to `isDiamondOperation()` in `pkg/daemons/lcmgr/ledger/ethbc/mutator.go` to be routed to the `EthBCDiamondContract` handler:

```go
func isDiamondOperation(operationName string) bool {
    switch operationName {
    case
        // ... existing entries ...
        // Diamond Props Operations (generic PropsFacet)
        "OPERATION_NAME_ENUM_DIAMOND_PROPS_SET_ADDRESS",
        "OPERATION_NAME_ENUM_DIAMOND_PROPS_SET_INT":
        return true
    }
    return false
}
```

### Pattern M: Verify Inputs - Deployment Details JSON Unmarshaling

The treasury `verify_inputs.go` uses a two-step JSON dance to extract `LaserLegalMechanismDeploymentDetails` from the generic `DeploymentDetails` interface:

```go
detailsBytes, err := json.Marshal(d.DeploymentDetails)
if err != nil { continue }
var laserDetails fin.LaserLegalMechanismDeploymentDetails
if err := json.Unmarshal(detailsBytes, &laserDetails); err != nil { continue }
if laserDetails.ExecutionRuntimeName == execRuntimeName {
    slotAddress = laserDetails.SlotAddress
    break
}
```

This is needed because `DeploymentDetails` is stored as `interface{}` and needs marshal/unmarshal to convert to the concrete type.

### Pattern N: Prefix Extraction

The prefix is NOT passed as a saga input - it's extracted from the existing Core deployment's TaskManager slot address:

```go
prefix := input["prefix"]
if prefix == "" {
    // slot_address is "{prefix}-TaskManager", extract prefix
    if len(taskManagerSlotAddress) > len("-TaskManager") {
        prefix = taskManagerSlotAddress[:len(taskManagerSlotAddress)-len("-TaskManager")]
    }
}
```

### Pattern O: Step 8 - DIAMOND_PROPS_SET_ADDRESS ATS for Algo Facets

Step 8 uses the NEW `DIAMOND_PROPS_SET_ADDRESS` operation. The ATS declaration should use key/value arrays:

```go
// New ATS arg names needed in pkg/laser/ats/arg_name.go:
// ArgNameEnum_PropsKeys   = "props_keys"
// ArgNameEnum_PropsValues = "props_values"

funcDecl := ats.Func(string(model.OperationNameEnum_DiamondPropsSetAddress)).
    Arguments(
        ats.String(string(ats.ArgNameEnum_Deployer)).Build(),                            // signer
        ats.String(string(ats.ArgNameEnum_LedgerContractSlotAddress)).Build(),           // target diamond
        ats.Array(string(ats.ArgNameEnum_PropsKeys), ats.String("").Build()).Build(),    // string[] keys
        ats.Array(string(ats.ArgNameEnum_PropsValues), ats.String("").Build()).Build(),  // address[] values
    ).
    Returns(
        ats.String("tx_hash").Build(),
    ).
    Build()

arguments := ats.NewBoundTuple().
    AddVar(...Deployer..., adminPartnerSlotAddress).
    AddVar(...LedgerContractSlotAddress..., agoraEngineDiamondSlotAddress).
    AddVar(...PropsKeys..., []string{
        "agora.engine.global.matching.matcher.algo.facet",
        "agora.engine.global.matching.settler.algo.facet",
    }).
    AddVar(...PropsValues..., []string{
        matcherAlgoFacetSlotAddress,  // e.g., "AgoraEngineMatcherAlgoFacet:latest"
        settlerAlgoFacetSlotAddress,  // e.g., "AgoraEngineSettlerAlgoFacet:latest"
    }).
    Build()
```

**Note**: The values are SLOT ADDRESSES (e.g., `AgoraEngineMatcherAlgoFacet:latest`), not ETH addresses. LASER translates them to actual addresses. If the new ArgNameEnum values don't exist yet, they need to be added to `pkg/laser/ats/arg_name.go`.

---

## Implementation Gaps Checklist (from audit)

These items were identified as missing or under-specified in the main phases above. Each references the pattern section that documents the solution.

- [x] **Phase 2**: Add `DIAMOND_PROPS_SET_ADDRESS` and `DIAMOND_PROPS_SET_INT` to `isDiamondOperation()` in `mutator.go` (Pattern L)
- [x] **Phase 2**: May need new `ArgNameEnum` values in `pkg/laser/ats/arg_name.go` for `PropsKeys` and `PropsValues` (Pattern O)
- [x] **Phase 2**: `ethbc_diamond_contract.go` dispatch: add switch cases that call `c.sendTransactionWithABI(ctx, signerAddress, c.propsABI, "setAddress", keyArr, valueArr)` for `mutationDiamondPropsSetAddress`
- [x] **Phase 5 (Step 1)**: verify_inputs must use JSON marshal/unmarshal dance to extract `LaserLegalMechanismDeploymentDetails` from `DeploymentDetails` (Pattern M)
- [x] **Phase 5 (Step 1)**: verify_inputs must check for `LegalMechanismTypeEnum_Trading` in existing mechanisms (not RAC/Treasury types used by treasury saga)
- [x] **Phase 5 (Step 1)**: verify_inputs must extract prefix from TaskManager slot address if not provided (Pattern N)
- [x] **Phase 5 (Step 1)**: verify_inputs must verify clearing account exists and is ACTIVE (treasury pattern includes this check)
- [x] **Phase 5 (Step 2)**: IID generation uses `fmt.Sprintf("legal_mech_%s", common.SecureRandomString(32))` (Pattern H)
- [x] **Phase 5 (Step 9)**: IID generation uses `fmt.Sprintf("legal_mech_deploy_%s", common.SecureRandomString(32))` (Pattern H)
- [x] **Phase 5 (Step 9)**: DeploymentDetails must use `fin.LaserLegalMechanismDeploymentDetails` struct with `ExecutionRuntimeName` and `SlotAddress` (Pattern H)
- [x] **Phase 6 (all steps)**: Every LASERAGENT step must use `laserConfigStore.GetConfig().CrownExecutorIid` for LASER API calls (Pattern F)
- [x] **Phase 6 (all steps)**: Every LASERAGENT step must use `os.Getenv("LASER_CLIENT_AUTH_KEY")` for auth header (Pattern F)
- [x] **Phase 6 (all steps)**: Every LASERAGENT step must use `client.LaserClientAuthKeyHeader` for header name (Pattern F)
- [x] **Phase 6 (Step 6)**: Multi-facet array uses `ats.Array(ats.ArgNameEnum_FacetAddresses, ats.String("").Build()).Build()` (Pattern E)
- [x] **Phase 6 (Step 8)**: Use DIAMOND_PROPS_SET_ADDRESS with key/value arrays, NOT TREZOR_SET_ADDRESS (Pattern O)
- [x] **Phase 7**: Spawner struct needs `mu sync.Mutex` and `inFlight map[string]chan struct{}` (Pattern K)
- [x] **Phase 7**: Spawner uses `context.Background()` with 10-min timeout, NOT parent context (Pattern K)
- [x] **Phase 7**: Spawner must include pre-flight check: query existing Trading mechanisms before spawning (Pattern K)
- [x] **Phase 7**: SNLP saga.go must add `go run_SpawnDeployTradingEngineMechanisms_Executor(ctx, mqClient, clusterId)` (no 50ms stagger for SNLP)
- [x] **Phase 9 (E2E tests)**: Test setup must call `UpdateAccountStore()` / `UpdateConfigStore()` for database switching
- [x] **Phase 9 (E2E tests)**: Must pre-deploy facets to lattice archive before testing facet addition
- [x] **Phase 9 (E2E tests)**: Must deploy Core Legal Mechanisms as prerequisite before testing Trading deployment
- [x] **Phase 9 (E2E tests)**: Saga completion timeout for trading saga: ~15 minutes (9 steps vs treasury's 18 steps)

---

## Solidity Contracts Reference

> **Repository**: `/Users/kam/repos/NEW2/qomet/contracts`

### Agora Engine Facets

| Contract | Lattice Name | Description |
|----------|-------------|-------------|
| AgoraEngineFacet | `agora-engine` | Core engine: global state, lifecycle management |
| AgoraEngineTradeManagerFacet | `agora-engine-trade-manager` | Trade lifecycle: open, settle, cancel trades |
| AgoraEnginePairManagerFacet | `agora-engine-pair-manager` | Trading pair CRUD: create, enable, disable, query pairs |
| AgoraEngineOfferManagerFacet | `agora-engine-offer-manager` | Offer lifecycle: create, update, cancel, query offers |
| AgoraEngineMatcherFacet | `agora-engine-matcher` | Order matching engine: match orders against offers |
| AgoraEngineOrderStatsFacet | `agora-engine-order-stats` | Order statistics: volume, count, aggregates |
| AgoraEngineDirectOrderManagerFacet | `agora-engine-direct-order-manager` | Direct (OTC) order management |
| AgoraEngineDirectOrderManagerV2Facet | `agora-engine-direct-order-v2` | Direct order v2: enhanced OTC with settlement |
| AgoraEngineDirectOrderManagerV2QueryFacet | `agora-engine-direct-order-v2` | Direct order v2 query interface (same version as V2Facet) |
| AgoraEngineMatcherAlgoFacet | `agora-engine-matcher-algo` | Matching algorithm implementation (address prop, NOT added to diamond) |
| AgoraEngineSettlerAlgoFacet | `agora-engine-settler-algo` | Settlement algorithm implementation (address prop, NOT added to diamond) |

### Shared Facets (also used by Treasury)

| Contract | Lattice Name | Description |
|----------|-------------|-------------|
| RBACFacet | `rbac` | Role-Based Access Control |
| PropsFacet | `props` | Key-value property storage (setAddress, setInt, setStr, setBytes) |

### Diamond Initialization for Agora Engine

```solidity
1. Create Diamond via DiamondFactory.createDiamond()
2. Call Diamond.initialize() with:
   - Admin = admin_partner
   - AuthzSource = AuthzDiamond address
   - TaskManager = TaskManagerV2 address
   - AuthzDomain = "AGORA_ENGINE"
3. Grant addFacets permission via AuthzDiamond
4. Add 10 facets via Diamond.addFacets(address[])
5. Grant setAddress permission via AuthzDiamond
6. Set Props via PropsFacet.setAddress():
   - "agora.engine.global.matching.matcher.algo.facet" = MatcherAlgoFacet address
   - "agora.engine.global.matching.settler.algo.facet" = SettlerAlgoFacet address
```

### Key Differences from Treasury Diamond Initialization

| Aspect | Treasury (RAC + Trezor) | Trading (Agora Engine) |
|--------|------------------------|----------------------|
| Number of diamonds | 2 (RAC + Trezor) | 1 (Agora Engine) |
| AuthzDomain | Uses default | "AGORA_ENGINE" |
| Facets added to diamond | RAC: 1 facet; Trezor: 7 facets | 10 facets |
| Additional props | rac.domain.id (int), rac.address (address) | 2 algo facet addresses |
| Props operation | TREZOR_SET_ADDRESS (combined setInt+setAddress) | DIAMOND_PROPS_SET_ADDRESS (setAddress only) |
| Ledger creation | YES (DEFAULT ledger, id=1) | NO |
| Cross-diamond auth | Trezor must be whitelisted on RAC's AuthzSource | N/A (single diamond) |
