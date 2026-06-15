# TODO: Deploy Lattice Framework Facets - TRAX Saga Implementation

> **Status**: IMPLEMENTED
> **Created**: 2026-01-11
> **Completed**: 2026-01-11

## Overview

TRAX saga template `deploy_lattice_facets` that deploys all Lattice Framework facet contracts (EIP-2535 Diamond pattern components). This saga creates both versioned slots (`{FacetName}:{version}`) and `:latest` alias slots with TRANSLATION links for each deployed facet. The saga is EthBC-only and requires LASER for all contract operations. The current default Lattice archive revision is **rev-21**.

This saga must be executed **before** any diamond deployments, as facets must be deployed and available for diamonds to reference.

---

## Key Design Decisions

### 1. Facet List as Input Parameter

The saga accepts a `facets_to_deploy` input (JSON array of facet names). Each step checks if its facet is in the list:
- If facet IS in list: Deploy it
- If facet NOT in list: Skip and return success immediately (`status: SKIPPED`)

This allows E2E tests and production deployments to control which subset of facets to deploy without modifying saga steps.

### 2. Lattice Archive Revision as Input

The saga accepts a `lattice_archive_revision` input (string). This specifies which version of the Lattice contract archive to deploy facets from:
- `"rev-17"` - Current default revision
- `"latest"` - Most recent archive revision (resolves via archive.json)

### 3. Extensibility

The saga steps can be expanded anytime as new facets are added to the Lattice archive:
1. Add new step templates to the saga template definition
2. Add corresponding executor implementations
3. The `facets_to_deploy` input allows selective deployment without changing existing steps

When a new archive revision is released with additional facets, simply add the new steps to the saga.

### 4. Slot Address Format

For each deployed facet, create TWO symbolic slots:
- `{FacetName}:{version}` (e.g., `AuthzFacet:1.0.0`) - versioned, immutable
- `{FacetName}:latest` - alias pointing to most recently deployed version

Both have bidirectional TRANSLATION links to the ETH contract address slot.

### 5. :latest Update Logic (Version Comparison Required)

The `:latest` TRANSLATION link is **only updated if the new version is greater** than the previously deployed version. Versions follow semantic versioning: `v{major}.{minor}.{patch}` (e.g., `v3.1.0`).

When deploying a facet:
1. Create ETH address slot for deployed contract
2. Create versioned symbolic slot (`{FacetName}:{version}`)
3. Create TRANSLATION links between versioned slot and ETH slot
4. If `{FacetName}:latest` slot exists:
   - Get `current_version` and `lattice_archive_revision` from `:latest` slot labels
   - **Compare versions**: Parse both as semver and compare
   - **Update `:latest` only if**:
     - `new_version > current_version`, OR
     - `new_lattice_archive_revision > current_lattice_archive_revision`
   - If update needed: deactivate old TRANSLATION links, create new ones
   - If NOT needed: skip `:latest` update (versioned slot is still created)
5. If `:latest` doesn't exist:
   - Create `{FacetName}:latest` slot
   - Create TRANSLATION links

**Metadata stored in TRANSLATION slot_link records:**
- `lattice_archive_revision` - The archive revision used for this deployment
- `facet_version` - The facet version (e.g., `v3.1.0`)
- `deployed_at` - Timestamp of deployment

**Metadata stored in `:latest` slot labels:**
- `current_version` - Current version pointed to by `:latest`
- `lattice_archive_revision` - Archive revision of current deployment

---

## Saga Specification

### Inputs

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `deployer_account_iid` | string | Yes | Account IID with SIGNER slot for contract deployments |
| `exec_runtime_name` | string | Yes | Execution runtime name (e.g., "primary") |
| `facet_version` | string | Yes | Version string for deployed facets (e.g., "1.0.0") |
| `lattice_archive_revision` | string | Yes | Lattice archive revision to deploy from (e.g., "v3.1.0", "latest") |
| `facets_to_deploy` | []string (JSON) | No | JSON array of facet names to deploy. Empty array or omitted = deploy ALL facets |

### Validation Rules

- `deployer_account_iid` must reference an account with an active SIGNER-tagged slot
- `lattice_archive_revision` must reference a valid archive revision
- All facet names in `facets_to_deploy` must exist in the specified archive revision
- `facet_version` must be a valid semantic version string

### Step Skip Logic

Each facet deployment step implements this logic:

```go
func (s *deployAuthzFacet_IdempotentService) ExecuteSync(...) {
    facetName := "AuthzFacet"

    // Parse facets_to_deploy input
    facetsToDeployJSON := input["facets_to_deploy"]
    var facetsToDeploy []string
    if facetsToDeployJSON != "" {
        json.Unmarshal([]byte(facetsToDeployJSON), &facetsToDeploy)
    }

    // If facets_to_deploy is specified and this facet is NOT in the list, skip
    if len(facetsToDeploy) > 0 && !contains(facetsToDeploy, facetName) {
        return &trax.IdempotentServiceExecutionResult{
            Result: map[string]string{
                "status":     "SKIPPED",
                "facet_name": facetName,
                "reason":     "not in facets_to_deploy list",
            },
            Error: nil,
        }, nil
    }

    // Continue with deployment...
}
```

---

## Complete Facet List (~73 Facets)

### Core/Foundation Module (10 facets)

| Facet Name | Description |
|------------|-------------|
| `AppRegistryFacet` | Application registry for diamond apps |
| `AuthzFacet` | Authorization with role-based access control |
| `SimpleAuthzFacet` | Simplified authorization (addAccount/removeAccount) |
| `RBACFacet` | Role-based access control |
| `RACFacet` | Resource access controller |
| `HasherFacet` | Cryptographic hashing utilities |
| `DiagFacet` | Diagnostics and health checks |
| `PropsFacet` | Property storage |
| `HashAnnotatorFacet` | Hash annotation management |
| `TaskExecutorFacet` | Task execution framework |

### ERC20 Module (2 facets)

| Facet Name | Description |
|------------|-------------|
| `Erc20Facet` | Standard ERC20 token implementation |
| `LASERErc20Facet` | LASER-specific ERC20 extensions |

### Trezor/Treasury Module (20 facets)

| Facet Name | Description |
|------------|-------------|
| `EthReserveFacet` | ETH reserve management |
| `EthReserveAdminFacet` | ETH reserve administration |
| `EthReserveTransferFacet` | ETH reserve transfers |
| `EthVaultFacet` | ETH vault management |
| `EthVaultAdminFacet` | ETH vault administration |
| `EthVaultTransferFacet` | ETH vault transfers |
| `Erc20ReserveFacet` | ERC20 reserve management |
| `Erc20ReserveAdminFacet` | ERC20 reserve administration |
| `Erc20ReserveTransferFacet` | ERC20 reserve transfers |
| `Erc20VaultAdminFacet` | ERC20 vault administration |
| `Erc20VaultTransferFacet` | ERC20 vault transfers |
| `Erc721ReserveFacet` | ERC721 reserve management |
| `Erc721ReserveAdminFacet` | ERC721 reserve administration |
| `Erc721ReserveTransferFacet` | ERC721 reserve transfers |
| `Erc721VaultFacet` | ERC721 vault management |
| `Erc721VaultAdminFacet` | ERC721 vault administration |
| `Erc721VaultTransferFacet` | ERC721 vault transfers |
| `ActivityStoreFacet` | Activity/audit log storage |
| `ReserveListerFacet` | Reserve enumeration |
| `LedgerListerFacet` | Ledger enumeration |

### Prizma/Governance Module (9 facets)

| Facet Name | Description |
|------------|-------------|
| `RegistryFacet` | Entity registry |
| `RegistrarFacet` | Entity registration |
| `RegistrarFactoryFacet` | Registrar factory |
| `CatalogFacet` | Asset catalog |
| `CouncilFacet` | Council governance |
| `CouncilAdminFacet` | Council administration |
| `CouncilPMFacet` | Council project management |
| `BoardFacet` | Board governance |
| `GrantTokenFacet` | Grant token management |

### Agora/Trading Engine Module (9 facets)

| Facet Name | Description |
|------------|-------------|
| `AgoraEngineFacet` | Core trading engine |
| `AgoraEngineDirectOrderManagerFacet` | Direct order management |
| `AgoraEngineOfferManagerFacet` | Offer management |
| `AgoraEngineMatcherFacet` | Order matching |
| `AgoraEngineMatcherAlgoFacet` | Matching algorithms |
| `AgoraEngineSettlerAlgoFacet` | Settlement algorithms |
| `AgoraEngineTradeManagerFacet` | Trade management |
| `AgoraEnginePairManagerFacet` | Trading pair management |
| `AgoraEngineOrderStatsFacet` | Order statistics |

### Korridor/Access Point Module (5 facets)

| Facet Name | Description |
|------------|-------------|
| `AccessPointFacet` | Access point core |
| `AccessPointSendManagerFacet` | Send message management |
| `AccessPointDeliveryManagerFacet` | Delivery management |
| `AccessPointV2Facet` | Access point v2 |
| `AccessPointV3Facet` | Access point v3 |

### Elysium Module (3 facets)

| Facet Name | Description |
|------------|-------------|
| `ElysiumFacet` | Elysium core |
| `ElysiumAdminFacet` | Elysium administration |
| `ElysiumPlanManagerFacet` | Plan management |

### Frenzy/NFT Module (9 facets)

| Facet Name | Description |
|------------|-------------|
| `MinterFacet` | NFT minting |
| `TokenStoreFacet` | Token storage |
| `RoyaltyManagerFacet` | Royalty management |
| `ReserveManagerFacet` | Reserve management |
| `PaymentMethodManagerFacet` | Payment methods |
| `WhitelistManagerFacet` | Whitelist management |
| `PaymentHandlerFacet` | Payment processing |
| `ERC721Facet` | ERC721 implementation |
| `CrossmintFacet` | Crossmint integration |

### UTR Module (2 facets)

| Facet Name | Description |
|------------|-------------|
| `UTRFacet` | Universal Token Registry v1 |
| `UTRV2Facet` | Universal Token Registry v2 |

---

## Saga Structure

### Single Flat Saga (~73 Steps)

One saga template `deploy_lattice_facets` with ~73 sequential steps (one per facet). **No sub-sagas or saga triggers from parent saga**.

| Saga Template ID | Description | Step Count |
|------------------|-------------|------------|
| `deploy_lattice_facets` | Single saga with all facet deployment steps | ~73 |

### Step Sequence

Steps are organized by module in the following order:

| Step Range | Module | Facet Count |
|------------|--------|-------------|
| 1-10 | Core/Foundation | 10 |
| 11-12 | ERC20 | 2 |
| 13-33 | Trezor/Treasury | 21 |
| 34-42 | Prizma/Governance | 9 |
| 43-51 | Agora/Trading | 9 |
| 52-56 | Korridor/Access | 5 |
| 57-59 | Elysium | 3 |
| 60-68 | Frenzy/NFT | 9 |
| 69-70 | UTR | 2 |

### Step Pattern (per facet)

Each facet has one step following this pattern:

```
Step: deploy_{facet_name_snake_case}_facet
Service: lasersvc
Description: Deploy {FacetName} via LASER. Skips if not in facets_to_deploy list.
```

### Complete Step List

```go
SagaStepTemplateIds: []string{
    // Core/Foundation (1-10)
    "deploy_app_registry_facet",
    "deploy_authz_facet",
    "deploy_simple_authz_facet",
    "deploy_rbac_facet",
    "deploy_rac_facet",
    "deploy_hasher_facet",
    "deploy_diag_facet",
    "deploy_props_facet",
    "deploy_hash_annotator_facet",
    "deploy_task_executor_facet",

    // ERC20 (11-12)
    "deploy_erc20_facet",
    "deploy_laser_erc20_facet",

    // Trezor/Treasury (13-33)
    "deploy_eth_reserve_facet",
    "deploy_eth_reserve_admin_facet",
    "deploy_eth_reserve_transfer_facet",
    "deploy_eth_vault_facet",
    "deploy_eth_vault_admin_facet",
    "deploy_eth_vault_transfer_facet",
    "deploy_erc20_reserve_facet",
    "deploy_erc20_reserve_admin_facet",
    "deploy_erc20_reserve_transfer_facet",
    "deploy_erc20_vault_facet",
    "deploy_erc20_vault_admin_facet",
    "deploy_erc20_vault_transfer_facet",
    "deploy_erc721_reserve_facet",
    "deploy_erc721_reserve_admin_facet",
    "deploy_erc721_reserve_transfer_facet",
    "deploy_erc721_vault_facet",
    "deploy_erc721_vault_admin_facet",
    "deploy_erc721_vault_transfer_facet",
    "deploy_activity_store_facet",
    "deploy_reserve_lister_facet",
    "deploy_ledger_lister_facet",

    // Prizma/Governance (34-42)
    "deploy_registry_facet",
    "deploy_registrar_facet",
    "deploy_registrar_factory_facet",
    "deploy_catalog_facet",
    "deploy_council_facet",
    "deploy_council_admin_facet",
    "deploy_council_pm_facet",
    "deploy_board_facet",
    "deploy_grant_token_facet",

    // Agora/Trading (43-51)
    "deploy_agora_engine_facet",
    "deploy_agora_engine_direct_order_manager_facet",
    "deploy_agora_engine_offer_manager_facet",
    "deploy_agora_engine_matcher_facet",
    "deploy_agora_engine_matcher_algo_facet",
    "deploy_agora_engine_settler_algo_facet",
    "deploy_agora_engine_trade_manager_facet",
    "deploy_agora_engine_pair_manager_facet",
    "deploy_agora_engine_order_stats_facet",

    // Korridor/Access (52-56)
    "deploy_access_point_facet",
    "deploy_access_point_send_manager_facet",
    "deploy_access_point_delivery_manager_facet",
    "deploy_access_point_v2_facet",
    "deploy_access_point_v3_facet",

    // Elysium (57-59)
    "deploy_elysium_facet",
    "deploy_elysium_admin_facet",
    "deploy_elysium_plan_manager_facet",

    // Frenzy/NFT (60-68)
    "deploy_minter_facet",
    "deploy_token_store_facet",
    "deploy_royalty_manager_facet",
    "deploy_reserve_manager_facet",
    "deploy_payment_method_manager_facet",
    "deploy_whitelist_manager_facet",
    "deploy_payment_handler_facet",
    "deploy_erc721_facet",
    "deploy_crossmint_facet",

    // UTR (69-70)
    "deploy_utr_facet",
    "deploy_utr_v2_facet",
},
```

---

## Phase 1: Enhance DeployFacetLcmgrResultHandler for :latest

**File**: `pkg/laser/handlers/deploy_facet_lcmgr.go`

### 1.1 Add :latest Slot Logic

- [ ] 1.1.1 After creating versioned symbolic slot, check if `:latest` slot exists
- [ ] 1.1.2 If `:latest` exists: deactivate old TRANSLATION links
- [ ] 1.1.3 Create new TRANSLATION links: `:latest` <-> ETH address slot
- [ ] 1.1.4 If `:latest` doesn't exist: create it with links
- [ ] 1.1.5 Store `current_version` in `:latest` slot labels

```go
// After existing symbolic slot creation...

// Create or update {FacetName}:latest
latestSymbolicAddress := fmt.Sprintf("%s:latest", facetName)

latestSlot, err := laserStore.GetSlotByAddress(ctx, latestSymbolicAddress)
if err == nil && latestSlot != nil {
    // :latest exists - update its TRANSLATION links

    // Deactivate old TRANSLATION links from :latest
    oldLinks, _ := laserStore.GetSlotLinksBySlotIid(ctx, latestSlot.Iid)
    for _, link := range oldLinks {
        if link.LinkType == model.SlotLinkTypeEnum_Translation && link.Active {
            link.Active = false
            laserStore.UpdateSlotLink(ctx, link)
        }
    }

    // Create new TRANSLATION links: :latest <-> ETH address
    // Link 1: :latest -> ETH
    link1 := &model.SlotLink{
        Iid:      fmt.Sprintf("laser_slot_link_%s", common.SecureRandomString(32)),
        Slot1Iid: latestSlot.Iid,
        Slot2Iid: slotIid,  // ETH address slot
        LinkType: model.SlotLinkTypeEnum_Translation,
        Active:   true,
        Labels: map[string]string{
            "direction":     "latest_to_eth",
            "facet_name":    facetName,
            "facet_version": facetVersion,
        },
    }
    laserStore.CreateSlotLinkIfNotExists(ctx, link1)

    // Link 2: ETH -> :latest (bidirectional)
    link2 := &model.SlotLink{
        Iid:      fmt.Sprintf("laser_slot_link_%s", common.SecureRandomString(32)),
        Slot1Iid: slotIid,
        Slot2Iid: latestSlot.Iid,
        LinkType: model.SlotLinkTypeEnum_Translation,
        Active:   true,
        Labels: map[string]string{
            "direction":     "eth_to_latest",
            "facet_name":    facetName,
            "facet_version": facetVersion,
        },
    }
    laserStore.CreateSlotLinkIfNotExists(ctx, link2)

    // Update :latest slot labels with current version
    latestSlot.Labels["current_version"] = facetVersion
    laserStore.UpdateSlot(ctx, latestSlot)

} else {
    // Create new :latest symbolic slot
    latestSlotIid := fmt.Sprintf("laser_slot_%s", common.SecureRandomString(32))
    latestSlot := &model.Slot{
        Iid:         latestSlotIid,
        ExecutorIid: executorIid,
        Address:     latestSymbolicAddress,
        RefSeed:     "",
        Labels: map[string]string{
            "type":            "facet",
            "slot_type":       "latest_alias",
            "facet_name":      facetName,
            "current_version": facetVersion,
        },
        Tags: []string{"ethereum", "facet", "lattice", "diamond", "eip2535", "latest"},
    }
    laserStore.CreateSlot(ctx, latestSlot)

    // Create TRANSLATION links (same as above)
    // ...
}
```

### 1.2 Add Store Methods (if needed)

**File**: `pkg/laser/model/laser_store.go`

- [ ] 1.2.1 Add `GetSlotLinksBySlotIid(ctx, slotIid string) ([]*SlotLink, error)` if not exists
- [ ] 1.2.2 Add `UpdateSlotLink(ctx, link *SlotLink) error` if not exists
- [ ] 1.2.3 Add `UpdateSlot(ctx, slot *Slot) error` if not exists

---

## Phase 2: Create Saga Template

**Directory**: `pkg/trax/templates/agora/csd/`

### 2.1 Single Saga Template

**File**: `deploy_lattice_facets.go` (NEW)

- [ ] 2.1.1 Create saga template `deploy_lattice_facets`
- [ ] 2.1.2 Define all ~73 steps (one per facet, flat structure, no sub-sagas)
- [ ] 2.1.3 Create `CreateDeployLatticeFacetsSagaTemplates()` function

```go
func CreateDeployLatticeFacetsSagaTemplates(clusterId string) []*trax.SagaTemplate {
    return []*trax.SagaTemplate{
        {
            SagaTemplateId: sagaTemplateId, // "deploy_lattice_facets"
            ClusterId:      clusterId,
            DefaultParticipant: trax.ServiceEnumLasersvc,
            SagaStepTemplateIds: []string{
                // Core/Foundation (1-10)
                "deploy_app_registry_facet",
                "deploy_authz_facet",
                "deploy_simple_authz_facet",
                "deploy_rbac_facet",
                "deploy_rac_facet",
                "deploy_hasher_facet",
                "deploy_diag_facet",
                "deploy_props_facet",
                "deploy_hash_annotator_facet",
                "deploy_task_executor_facet",
                // ERC20 (11-12)
                "deploy_erc20_facet",
                "deploy_laser_erc20_facet",
                // Trezor/Treasury (13-33)
                "deploy_eth_reserve_facet",
                // ... (all 21 trezor facets)
                // Prizma/Governance (34-42)
                // ... (all 9 prizma facets)
                // Agora/Trading (43-51)
                // ... (all 9 agora facets)
                // Korridor/Access (52-56)
                // ... (all 5 korridor facets)
                // Elysium (57-59)
                // ... (all 3 elysium facets)
                // Frenzy/NFT (60-68)
                // ... (all 9 frenzy facets)
                // UTR (69-70)
                "deploy_utr_facet",
                "deploy_utr_v2_facet",
            },
        },
    }
}
```

### 2.2 Register Saga Template

**File**: `pkg/trax/templates/agora/csd/index.go`

- [ ] 2.2.1 Add call to `CreateDeployLatticeFacetsSagaTemplates(clusterId)`

---

## Phase 3: Create Step Executors

**Single Directory** - All ~73 step executors in one package:

```
pkg/daemons/lasersvc/trax/executors/deploy_lattice_facets/
    saga.go                           # Saga template ID and RunExecutorsAsync()
    common.go                         # Shared helper functions (skip logic, deploy logic)

    # Core/Foundation (10 files)
    deploy_app_registry_facet.go
    deploy_authz_facet.go
    deploy_simple_authz_facet.go
    deploy_rbac_facet.go
    deploy_rac_facet.go
    deploy_hasher_facet.go
    deploy_diag_facet.go
    deploy_props_facet.go
    deploy_hash_annotator_facet.go
    deploy_task_executor_facet.go

    # ERC20 (2 files)
    deploy_erc20_facet.go
    deploy_laser_erc20_facet.go

    # Trezor/Treasury (21 files)
    deploy_eth_reserve_facet.go
    deploy_eth_reserve_admin_facet.go
    deploy_eth_reserve_transfer_facet.go
    deploy_eth_vault_facet.go
    deploy_eth_vault_admin_facet.go
    deploy_eth_vault_transfer_facet.go
    deploy_erc20_reserve_facet.go
    deploy_erc20_reserve_admin_facet.go
    deploy_erc20_reserve_transfer_facet.go
    deploy_erc20_vault_facet.go
    deploy_erc20_vault_admin_facet.go
    deploy_erc20_vault_transfer_facet.go
    deploy_erc721_reserve_facet.go
    deploy_erc721_reserve_admin_facet.go
    deploy_erc721_reserve_transfer_facet.go
    deploy_erc721_vault_facet.go
    deploy_erc721_vault_admin_facet.go
    deploy_erc721_vault_transfer_facet.go
    deploy_activity_store_facet.go
    deploy_reserve_lister_facet.go
    deploy_ledger_lister_facet.go

    # Prizma/Governance (9 files)
    deploy_registry_facet.go
    deploy_registrar_facet.go
    deploy_registrar_factory_facet.go
    deploy_catalog_facet.go
    deploy_council_facet.go
    deploy_council_admin_facet.go
    deploy_council_pm_facet.go
    deploy_board_facet.go
    deploy_grant_token_facet.go

    # Agora/Trading (9 files)
    deploy_agora_engine_facet.go
    deploy_agora_engine_direct_order_manager_facet.go
    deploy_agora_engine_offer_manager_facet.go
    deploy_agora_engine_matcher_facet.go
    deploy_agora_engine_matcher_algo_facet.go
    deploy_agora_engine_settler_algo_facet.go
    deploy_agora_engine_trade_manager_facet.go
    deploy_agora_engine_pair_manager_facet.go
    deploy_agora_engine_order_stats_facet.go

    # Korridor/Access (5 files)
    deploy_access_point_facet.go
    deploy_access_point_send_manager_facet.go
    deploy_access_point_delivery_manager_facet.go
    deploy_access_point_v2_facet.go
    deploy_access_point_v3_facet.go

    # Elysium (3 files)
    deploy_elysium_facet.go
    deploy_elysium_admin_facet.go
    deploy_elysium_plan_manager_facet.go

    # Frenzy/NFT (9 files)
    deploy_minter_facet.go
    deploy_token_store_facet.go
    deploy_royalty_manager_facet.go
    deploy_reserve_manager_facet.go
    deploy_payment_method_manager_facet.go
    deploy_whitelist_manager_facet.go
    deploy_payment_handler_facet.go
    deploy_erc721_facet.go
    deploy_crossmint_facet.go

    # UTR (2 files)
    deploy_utr_facet.go
    deploy_utr_v2_facet.go
```

### 3.1 Common Helper Functions

**File**: `deploy_lattice_facets/common.go`

- [ ] 3.1.1 Create `shouldSkipFacet(facetName string, input map[string]string) bool`
- [ ] 3.1.2 Create `deployFacetViaLcmgr(ctx, facetName, version, deployerIid, archiveRevision string) (*DeployResult, error)`
- [ ] 3.1.3 Create `createSkippedResult(facetName string) *trax.IdempotentServiceExecutionResult`

```go
// shouldSkipFacet checks if the facet should be skipped based on facets_to_deploy input
func shouldSkipFacet(facetName string, input map[string]string) bool {
    facetsToDeployJSON := input["facets_to_deploy"]
    if facetsToDeployJSON == "" {
        return false // Deploy all if not specified
    }

    var facetsToDeploy []string
    if err := json.Unmarshal([]byte(facetsToDeployJSON), &facetsToDeploy); err != nil {
        return false // Deploy all if parse error
    }

    if len(facetsToDeploy) == 0 {
        return false // Deploy all if empty array
    }

    for _, f := range facetsToDeploy {
        if f == facetName {
            return false // Found in list, deploy
        }
    }
    return true // Not in list, skip
}
```

### 3.2 Create All Step Executors

- [ ] 3.2.1 Create saga.go with `RunExecutorsAsync()` that registers all ~73 step executors
- [ ] 3.2.2 Create executor file for each facet (all follow same pattern)

Each executor follows identical pattern - only `facetName` and `stepTemplateId` differ:

```go
// deploy_authz_facet.go
type deployAuthzFacet_IdempotentService struct {
    executionResults    map[string]*trax.IdempotentServiceExecutionResult
    compensationResults map[string]*trax.IdempotentServiceExecutionResult
}

func (s *deployAuthzFacet_IdempotentService) ExecuteSync(
    ctx context.Context,
    idempotentKey string,
    input map[string]string,
) (*trax.IdempotentServiceExecutionResult, error) {
    facetName := "AuthzFacet"

    // Check if should skip
    if shouldSkipFacet(facetName, input) {
        return createSkippedResult(facetName), nil
    }

    // Deploy facet via lcmgr
    result, err := deployFacetViaLcmgr(ctx, facetName, input)
    // ...
}

func run_DeployAuthzFacet_Executor(ctx context.Context, mqClient trax.MQClient, clusterId string) error {
    trax.NewExecutor(mqClient, clusterId, sagaTemplateId, "deploy_authz_facet", &deployAuthzFacet_IdempotentService{...}).Run(ctx)
    return nil
}
```

### 3.3 Register Executors

**File**: `pkg/daemons/lasersvc/trax/executors/run.go`

- [ ] 3.3.1 Import `deploy_lattice_facets` package
- [ ] 3.3.2 Add call to `deploy_lattice_facets.RunExecutorsAsync(ctx, mqClient, clusterId)`

---

## Phase 4: Test Prep Integration

### 4.1 Create Helper Functions

**File**: `tests/e2e/laser/indtrxss_helpers_facets.go` (NEW)

- [ ] 4.1.1 Create `getAllLatticeFacetNames() []string` returning all ~73 facet names
- [ ] 4.1.2 Create `deployLatticeFacetsForTest(t, deployerSeed string, facetsToDeploy []string)`
- [ ] 4.1.3 Create `verifyFacetSlotExists(t, facetName, version string)`
- [ ] 4.1.4 Create `getLatestFacetAddress(t, facetName string) string`

```go
// deployLatticeFacetsForTest deploys specified facets synchronously for E2E test setup.
// If facetsToDeploy is empty, deploys all facets.
func deployLatticeFacetsForTest(t *testing.T, deployerSeed string, facetsToDeploy []string) {
    t.Helper()

    allFacets := getAllLatticeFacetNames()
    facetsToProcess := allFacets
    if len(facetsToDeploy) > 0 {
        facetsToProcess = facetsToDeploy
    }

    for _, facetName := range facetsToProcess {
        t.Logf("  Deploying %s...", facetName)
        // Deploy via lcmgr
        txHash := lcmgrDeployFacet(t, deployerAddress, facetName, "1.0.0")
        contractAddr := waitForTxReceipt(t, txHash, 30)
        t.Logf("  %s deployed at %s", facetName, contractAddr)
    }
}
```

### 4.2 Update Test Setup

**File**: `tests/e2e/laser/indtrxss_common_test.go`

- [ ] 4.2.1 Add optional facet deployment in `setupTestDatabaseForIndTrxSS()`
- [ ] 4.2.2 Use `facets_to_deploy` parameter to control which facets are deployed

```go
func setupTestDatabaseForIndTrxSS(t *testing.T) (*sql.DB, string) {
    // ... existing setup ...

    // Deploy facets before running tests (EthBC mode only)
    if isEthBCMode() {
        // Deploy only essential facets for tests by default
        essentialFacets := []string{
            "SimpleAuthzFacet",
            "RACFacet",
            "DiagFacet",
            "Erc20VaultFacet",
            "Erc20VaultAdminFacet",
        }
        deployLatticeFacetsForTest(t, "facet-deployer-seed", essentialFacets)
    }
}
```

---

## Phase 5: E2E Tests

**File**: `tests/e2e/laser/deploy_all_facets_test.go` (NEW)

### 5.1 Core Facet Tests

- [ ] 5.1.1 `TestDeployLatticeFacets_Core` - Deploy all 10 core facets
- [ ] 5.1.2 `TestDeployLatticeFacets_Core_Selective` - Deploy subset using `facets_to_deploy`
- [ ] 5.1.3 `TestDeployLatticeFacets_Core_SkipLogic` - Verify skip behavior

### 5.2 Module Tests

- [ ] 5.2.1 `TestDeployLatticeFacets_Trezor` - Deploy all treasury facets
- [ ] 5.2.2 `TestDeployLatticeFacets_Prizma` - Deploy all governance facets
- [ ] 5.2.3 `TestDeployLatticeFacets_Agora` - Deploy all trading facets

### 5.3 Full Deployment Tests

- [ ] 5.3.1 `TestDeployLatticeFacets_All` - Deploy all ~73 facets
- [ ] 5.3.2 `TestDeployLatticeFacets_ViaTRAX` - Deploy via TRAX saga submission

### 5.4 :latest Slot Tests

- [ ] 5.4.1 `TestFacetLatestSlot_Creation` - Verify `:latest` slot created
- [ ] 5.4.2 `TestFacetLatestSlot_UpdateOnRedeploy` - Verify `:latest` updates on redeployment
- [ ] 5.4.3 `TestFacetLatestSlot_TranslationLinks` - Verify TRANSLATION links

---

## Phase 6: Documentation

### 6.1 Update SUMMARY-FOR-AGENT.md

**File**: `docs/SUMMARY-FOR-AGENT.md`

- [ ] 6.1.1 Add section on Lattice facet deployment saga
- [ ] 6.1.2 Document input parameters including `facets_to_deploy` and `lattice_archive_revision`
- [ ] 6.1.3 Document `:latest` slot behavior
- [ ] 6.1.4 Document extensibility for new facets

---

## Data Flow Diagram

```
[Saga Submit: deploy_lattice_facets]
    |
    v
[Step 1: deploy_app_registry_facet] (LASERSVC)
    |-- Check: "AppRegistryFacet" in facets_to_deploy?
    |-- If NO: return SKIPPED
    |-- If YES: Deploy via LASER DEPLOY_FACET
    |           Creates: AppRegistryFacet:1.0.0 slot
    |           Creates: AppRegistryFacet:latest slot (if version > previous)
    |           Creates: TRANSLATION links
    v
[Step 2: deploy_authz_facet] (LASERSVC)
    |-- Check: "AuthzFacet" in facets_to_deploy?
    |-- If NO: return SKIPPED
    |-- If YES: Deploy via LASER DEPLOY_FACET
    |           Creates: AuthzFacet:1.0.0 slot
    |           Creates: AuthzFacet:latest slot (if version > previous)
    |           Creates: TRANSLATION links
    v
[Step 3: deploy_simple_authz_facet] (LASERSVC)
    |-- ...
    v
... (continuing through all ~73 steps sequentially)
    v
[Step 69: deploy_utr_facet] (LASERSVC)
    |-- ...
    v
[Step 70: deploy_utr_v2_facet] (LASERSVC)
    |-- ...
    v
[SAGA COMMITTED]
```

### Per-Step Flow Detail

Each step follows identical logic:

```
[Step N: deploy_{facet_name}_facet]
    |
    |-- 1. Parse facets_to_deploy input
    |       |
    |       +-- If empty or not specified: DEPLOY (deploy all facets)
    |       +-- If facet NOT in list: return SKIPPED
    |       +-- If facet in list: continue to deployment
    |
    |-- 2. Call lcmgr /deploy API with:
    |       - deployer_address (from deployer_account_iid)
    |       - ledger_contract_type: FACET
    |       - facet_name: "{FacetName}"
    |       - facet_version: from input
    |       - lattice_archive_revision: from input
    |
    |-- 3. Poll LASER future for completion
    |
    |-- 4. DeployFacetLcmgrResultHandler creates:
    |       - ETH address slot (0x...)
    |       - Versioned symbolic slot ({FacetName}:{version})
    |       - :latest slot (if new version > previous)
    |       - TRANSLATION links with metadata
    |
    v
[Return result: deployed/skipped]
```

---

## Files Summary

### New Files

**Saga Template (1 file):**

| File | Description |
|------|-------------|
| `pkg/trax/templates/agora/csd/deploy_lattice_facets.go` | Single flat saga template with ~73 steps |

**Executors (Single Directory - ~72 files):**

| File | Description |
|------|-------------|
| `pkg/daemons/lasersvc/trax/executors/deploy_lattice_facets/saga.go` | Saga template ID and `RunExecutorsAsync()` |
| `pkg/daemons/lasersvc/trax/executors/deploy_lattice_facets/common.go` | Shared helper functions |
| `pkg/daemons/lasersvc/trax/executors/deploy_lattice_facets/deploy_app_registry_facet.go` | Core: AppRegistryFacet |
| `pkg/daemons/lasersvc/trax/executors/deploy_lattice_facets/deploy_authz_facet.go` | Core: AuthzFacet |
| `...` | ... (10 core + 2 erc20 + 21 trezor + 9 prizma + 9 agora + 5 korridor + 3 elysium + 9 frenzy + 2 utr = 70 executor files) |

**Tests (2 files):**

| File | Description |
|------|-------------|
| `tests/e2e/laser/indtrxss_helpers_facets.go` | Facet deployment test helpers |
| `tests/e2e/laser/deploy_all_facets_test.go` | E2E tests for facet deployment |

### Modified Files

| File | Changes |
|------|---------|
| `pkg/laser/handlers/deploy_facet_lcmgr.go` | Add `:latest` slot creation/update logic with version comparison |
| `pkg/laser/model/laser_store.go` | Add missing store methods (if needed) |
| `pkg/trax/templates/agora/csd/index.go` | Register `deploy_lattice_facets` saga template |
| `pkg/daemons/lasersvc/trax/executors/run.go` | Register `deploy_lattice_facets` executors |
| `tests/e2e/laser/indtrxss_common_test.go` | Optionally deploy facets in test setup |
| `docs/SUMMARY-FOR-AGENT.md` | Document facet deployment saga |

---

## Success Criteria

- [ ] `DeployFacetLcmgrResultHandler` creates `:latest` slots with TRANSLATION links
- [ ] `:latest` slot updates correctly on redeployment
- [ ] All saga templates registered correctly (verify via `traxcli templates list`)
- [ ] All ~73 step executors start without errors
- [ ] `facets_to_deploy` parameter correctly filters which facets are deployed
- [ ] `lattice_archive_revision` parameter selects correct archive
- [ ] Skip logic works correctly (facets not in list return SKIPPED)
- [ ] Green path E2E tests pass (EthBC mode)
- [ ] Selective deployment E2E tests pass
- [ ] `:latest` slot tests pass
- [ ] Documentation updated

---

## Notes

- **Flat saga structure**: One saga with ~73 sequential steps. NO sub-sagas or saga triggers from parent saga
- **EthBC-only**: This saga only works with real Ethereum blockchain, not RDBMS mode
- **Immutable contracts**: LASER contract deployments cannot be compensated (on-chain immutability)
- **Pre-requisite for diamonds**: Facets must be deployed before any diamond deployments
- **Extensibility**: Add new steps when new facets are added to Lattice archive
- **Selective deployment**: Use `facets_to_deploy` to deploy only needed facets in E2E tests
- **Archive versioning**: Use `lattice_archive_revision` to specify which archive version to deploy from
- **Slot address pattern**: `{FacetName}:{version}` for versioned, `{FacetName}:latest` for alias
- **Version comparison**: `:latest` slot only updated if `new_version > current_version` (semver comparison)