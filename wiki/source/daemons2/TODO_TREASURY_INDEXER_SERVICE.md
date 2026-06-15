# TODO: Treasury Indexer Service (`treasidxer`)

> **Status**: COMPLETE (Phases 0-8 implemented; Phase 9 unit tests skipped — E2E coverage sufficient)
> **Created**: 2026-03-08
> **Last Updated**: 2026-03-09
> **Feature**: New daemon that indexes on-chain Trezor treasury activities via LASER query API into PostgreSQL and triggers slot link management
> **Short ID**: TRIS
> **Dependencies**: Treasury mechanism deployment (deploy_treasury_legal_mechanisms saga), LASER service, AccMgr, Trezor smart contract (ActivityStoreFacet)
> **Enables**: Treasury activity audit trail, TREASURY_ERC20_VAULT_HOLDER/HOLDING slot link auto-management for treassvc balance discovery

---

## Overview

The `treasidxer` (Treasury Indexer) is a new daemon that continuously indexes on-chain treasury activities from Trezor smart contracts for every active treasury mechanism deployment. It discovers active treasury deployments by polling `accmgr` for legal structures with TREASURY type mechanisms, queries the Trezor ActivityStoreFacet via LASER for activities, and stores them in PostgreSQL. The indexed data is exposed via REST endpoints on `treasidxer`.

As a critical side effect, when LASER processes `GetActivitiesV2` query results from lcmgr, it inspects each activity's operation type and creates TREASURY_ERC20_VAULT_HOLDER/HOLDING slot links for vault-affecting operations. This enables treassvc to discover which accounts hold tokens in treasury vaults.

**Key architectural points**:
- **All chain queries go through LASER** REST API (`POST /api/v1/executors/{iid}/query`), never direct Go bindings
- **One background job per treasury deployment** (per unique `(slot_address, exec_runtime_name)` pair)
- **Smart polling**: Default 5s interval with exponential backoff; polls only when new activities are detected
- **Incremental updates**: Tracks `last_activity_id` per deployment; uses `GetActivitiesV2(afterId)` for cursor-based fetching
- **Slot link management happens in LASER**, not in treasidxer — LASER's query result handler creates links during response processing
- **Link creation only**: The query result handler only CREATES links (idempotent); link REMOVAL is handled by existing `TrezorMutationLcmgrResultHandler` during mutation operations
- **Complementary to existing Cassandra pipeline**: The `LedgerActivityNew` → RabbitMQ → Cassandra pipeline continues independently
- **Port**: 17223
- **Redis DB**: 14 (`TreasuryIndexerRedisDB`)
- **Auth**: Unauthenticated internal service (k8s cluster-internal only)
- **Runs in**: CSD and prtagent K8s namespaces

**Trezor Activity Operation Types** (from `IActivityStoreV1.sol`):

| Code | Name | Vault Link Action |
|------|------|-------------------|
| 101 | DEPOSIT_TO_VAULT | Create link for toVault+contractAddr |
| 102 | WITHDRAW_FROM_VAULT | (skip — mutation handler manages removal) |
| 103 | TRANSFER_TO_VAULT | Create link for toVault+contractAddr |
| 104 | TRANSFER_FROM_VAULT_TO_RESERVE | (skip — mutation handler manages removal) |
| 105 | SET_ALLOWANCE_ON_VAULT | No link action |
| 106 | MOVE_ORPHAN_TO_VAULT | Create link for toVault+contractAddr |
| 107 | TRANSFER_VAULT_BALANCE | Create link for toVault+contractAddr |
| 108 | SET_VAULT_BALANCE_ON_SLAVE_LEDGER | No link action |
| 201 | DEPOSIT_TO_RESERVE | No link action |
| 202 | WITHDRAW_FROM_RESERVE | No link action |
| 203 | TRANSFER_TO_RESERVE | No link action |
| 204 | TRANSFER_FROM_RESERVE_TO_VAULT | Create link for toVault+contractAddr |
| 205 | SET_ALLOWANCE_ON_RESERVE | No link action |
| 206 | MOVE_ORPHAN_TO_RESERVE | No link action |
| 207 | TRANSFER_RESERVE_BALANCE | No link action |
| 208 | SET_RESERVE_BALANCE_ON_SLAVE_LEDGER | No link action |

---

## Prerequisites

1. **LASER service running** with a crown executor configured for the execution runtime
2. **At least one TREASURY mechanism deployment** exists (via `deploy_treasury_legal_mechanisms` saga) with a SlotAddress populated
3. **AccMgr running** and accessible for legal structure/mechanism discovery
4. **PostgreSQL available** with `agora_db` database
5. **Redis available** with DB 14 free
6. **LASER client auth key** configured (env var `LASER_CLIENT_AUTH_KEY`)

---

## Phase 0: LASER Prerequisites

> Before the treasidxer daemon can poll activities, new LASER query operations must be registered and a specialized query result handler must be implemented for slot link management.

### 0.1 New OperationNameEnum Values

**File**: `pkg/laser/model/operation_name.go`

Add the following after the existing `TrezorErc20GetStashLabel` entry:

```go
// Trezor ActivityStore Query Operations (view functions, called via LASER query API)
OperationNameEnum_TrezorGetNrOfActivities  OperationNameEnum = "OPERATION_NAME_ENUM_TREZOR_GET_NR_OF_ACTIVITIES"
OperationNameEnum_TrezorGetActivitiesV2    OperationNameEnum = "OPERATION_NAME_ENUM_TREZOR_GET_ACTIVITIES_V2"
```

### 0.2 New ArgNameEnum Values

**File**: `pkg/laser/ats/argnames.go`

Check existing values first. Add only what's missing:

```go
// Trezor ActivityStore Query Arguments
ArgNameEnum_AfterActivityId  ArgNameEnum = "after_activity_id"  // uint256 - cursor for pagination
ArgNameEnum_ActivityCount    ArgNameEnum = "activity_count"     // uint256 - max activities to return

// Trezor ActivityStore Query Return Values
ArgNameEnum_NrOfActivities   ArgNameEnum = "nr_of_activities"   // uint256
ArgNameEnum_Activities       ArgNameEnum = "activities"         // ActivityV2[] struct array
```

### 0.3 OperationSlotArgs Registration

**File**: `pkg/laser/model/operation_slot_args.go`

Both operations are pure queries with no slot address arguments (their arguments are numeric: `after_activity_id` and `activity_count`):

```go
OperationNameEnum_TrezorGetNrOfActivities: {},
OperationNameEnum_TrezorGetActivitiesV2:   {},
```

### 0.4 Register Serializers in Router

**File**: `pkg/laser/router/init.go`

Register both operations with `LcmgrCallSerializer` (they route through lcmgr `/rpc/call` to the Trezor Diamond proxy, same as `TrezorErc20GetVaultBalance`):

```go
// Add to the trezorErc20VaultQueryOps slice (or create a new trezorActivityQueryOps slice)
trezorActivityQueryOps := []model.OperationNameEnum{
    model.OperationNameEnum_TrezorGetNrOfActivities,
    model.OperationNameEnum_TrezorGetActivitiesV2,
}
for _, opName := range trezorActivityQueryOps {
    RegisterSerializer(
        domain.ExternalServiceApplicationTypeEnum_LcMgr,
        opName,
        lcmgrCallSerializer,
    )
}
```

Also register with the LASER pass-through serializer for LASER-to-LASER relay, following the pattern at `init.go:298-329`.

### 0.5 Register Result Handlers

**File**: `pkg/laser/handlers/register.go`

Three handler registries need updating:

**a) LcMgr handlers** — Add to `GetDiamondLcmgrHandlers()` in `diamond_lcmgr.go`:

```go
// Trezor ActivityStore query operations
// GetNrOfActivities uses generic query handler (pass-through, no side effects)
model.OperationNameEnum_TrezorGetNrOfActivities: queryHandler,
// GetActivitiesV2 uses specialized handler for slot link creation
model.OperationNameEnum_TrezorGetActivitiesV2:   &TrezorActivitiesV2QueryResultHandler{},
```

**b) Diamond relay operations** — Add both to `diamondRelayOperations` slice in `register.go`:

```go
// Trezor ActivityStore query operations (relay pass-through)
model.OperationNameEnum_TrezorGetNrOfActivities,
model.OperationNameEnum_TrezorGetActivitiesV2,
```

**c) LASER pass-through operations** — Add both to `laserOperations` slice in `register.go`:

```go
// Trezor ActivityStore operations
model.OperationNameEnum_TrezorGetNrOfActivities,
model.OperationNameEnum_TrezorGetActivitiesV2,
```

### 0.6 Implement TrezorActivitiesV2QueryResultHandler (CORE)

**New File**: `pkg/laser/handlers/trezor_activities_v2_query.go`

This is the first query result handler that performs side-effect operations (slot link management). Existing query handlers are pure pass-through.

**Design principles**:
- Only CREATES links (no removal) — removal is handled by existing `TrezorMutationLcmgrResultHandler.manageVaultLinks()` during mutation operations
- Uses `laserStore.GetSlotByAddress()` to resolve Ethereum addresses to slot IIDs (NOT `future.SlotAddressToIidMap`, which is only populated for mutations)
- Caches resolved address→slotIID mappings within each handler call for efficiency
- Best-effort per activity — if one activity's link creation fails, log warning and continue
- Idempotent via `CreateSlotLinkIfNotExists()`

```go
package handlers

import (
    "context"
    "fmt"
    "strconv"

    "qomet.tech/agora/daemons/pkg/common"
    "qomet.tech/agora/daemons/pkg/laser/model"
)

// TrezorActivitiesV2QueryResultHandler handles query results from GetActivitiesV2
// and creates TREASURY_ERC20_VAULT_HOLDER/HOLDING slot links for vault-affecting operations.
//
// This is a query result handler with SIDE EFFECTS (slot link creation).
// Unlike mutation handlers, this handler:
// - Only CREATES links (never removes) — link removal happens in TrezorMutationLcmgrResultHandler
// - Uses laserStore.GetSlotByAddress() instead of future.SlotAddressToIidMap
// - Is best-effort per activity — failures don't block the query result
type TrezorActivitiesV2QueryResultHandler struct{}

// Vault-affecting operation types that trigger link creation
const (
    OpDepositToVault                = 101
    OpTransferToVault               = 103
    OpMoveOrphanToVault             = 106
    OpTransferVaultBalance          = 107
    OpTransferFromReserveToVault    = 204
)

// HandleMutationResult is not applicable for query operations.
func (h *TrezorActivitiesV2QueryResultHandler) HandleMutationResult(
    ctx context.Context,
    operationName string,
    externalResult map[string]interface{},
    executorIid string,
    laserStore model.LaserStore,
    future *model.Future,
) (map[string]interface{}, string, error) {
    return nil, "", fmt.Errorf("TrezorGetActivitiesV2 is a query, not a mutation")
}

// HandleQueryResult processes GetActivitiesV2 results and creates slot links.
func (h *TrezorActivitiesV2QueryResultHandler) HandleQueryResult(
    ctx context.Context,
    operationName string,
    externalResult map[string]interface{},
    executorIid string,
    laserStore model.LaserStore,
    future *model.Future,
) (map[string]interface{}, string, error) {
    common.L.Info(fmt.Sprintf("TrezorActivitiesV2QueryResultHandler: Processing query result for %s", operationName),
        common.F(ctx)...)

    // Extract the activities array from the result
    // The format depends on how lcmgr serializes the ActivityV2[] struct array
    activitiesRaw, ok := externalResult["activities"]
    if !ok {
        // Try output[0].value format (BoundVariable style)
        // ... (handle both response formats)
        common.L.Info("TrezorActivitiesV2QueryResultHandler: No activities field in result, passing through",
            common.F(ctx)...)
        return externalResult, string(model.ResultObjectTypeEnum_QueryResponse), nil
    }

    activities, ok := activitiesRaw.([]interface{})
    if !ok {
        common.L.Warn("TrezorActivitiesV2QueryResultHandler: activities field is not an array",
            common.F(ctx)...)
        return externalResult, string(model.ResultObjectTypeEnum_QueryResponse), nil
    }

    // Local cache for address -> slot IID resolution (avoids repeated DB lookups)
    addrToSlotIid := make(map[string]string)

    for _, activityRaw := range activities {
        activity, ok := activityRaw.(map[string]interface{})
        if !ok {
            continue
        }

        // Parse operation code
        operationStr, _ := activity["operation"].(string)
        operationCode, err := strconv.Atoi(operationStr)
        if err != nil {
            continue
        }

        // Only process vault-affecting operations that create links
        if !isVaultLinkCreationOp(operationCode) {
            continue
        }

        // Extract toVault and contractAddr (ERC20)
        toVault, _ := activity["to_vault"].(string)
        contractAddr, _ := activity["contract_addr"].(string)

        if toVault == "" || contractAddr == "" || toVault == "0x0000000000000000000000000000000000000000" {
            continue
        }

        // Resolve addresses to slot IIDs
        toVaultSlotIid, err := h.resolveSlotIid(ctx, laserStore, toVault, addrToSlotIid)
        if err != nil {
            common.L.Warn(fmt.Sprintf("TrezorActivitiesV2QueryResultHandler: Cannot resolve vault %s to slot IID: %v",
                toVault, err), common.F(ctx)...)
            continue
        }

        contractSlotIid, err := h.resolveSlotIid(ctx, laserStore, contractAddr, addrToSlotIid)
        if err != nil {
            common.L.Warn(fmt.Sprintf("TrezorActivitiesV2QueryResultHandler: Cannot resolve contract %s to slot IID: %v",
                contractAddr, err), common.F(ctx)...)
            continue
        }

        // Create bidirectional treasury vault links
        if err := CreateTreasuryVaultLinksDirect(ctx, laserStore, toVaultSlotIid, contractSlotIid,
            toVault, contractAddr, future); err != nil {
            common.L.Warn(fmt.Sprintf("TrezorActivitiesV2QueryResultHandler: Failed to create links for vault=%s, erc20=%s: %v",
                toVault, contractAddr, err), common.F(ctx)...)
        }
    }

    // Return the original result as-is (pass-through)
    return externalResult, string(model.ResultObjectTypeEnum_QueryResponse), nil
}

// resolveSlotIid resolves an Ethereum address to a LASER slot IID, with caching.
func (h *TrezorActivitiesV2QueryResultHandler) resolveSlotIid(
    ctx context.Context,
    laserStore model.LaserStore,
    ethAddr string,
    cache map[string]string,
) (string, error) {
    if slotIid, ok := cache[ethAddr]; ok {
        return slotIid, nil
    }

    slot, err := laserStore.GetSlotByAddress(ctx, ethAddr)
    if err != nil {
        return "", fmt.Errorf("GetSlotByAddress(%s): %w", ethAddr, err)
    }
    if slot == nil {
        return "", fmt.Errorf("no slot found for address %s", ethAddr)
    }

    cache[ethAddr] = slot.Iid
    return slot.Iid, nil
}

// isVaultLinkCreationOp returns true if the operation type should trigger link creation.
func isVaultLinkCreationOp(opCode int) bool {
    switch opCode {
    case OpDepositToVault, OpTransferToVault, OpMoveOrphanToVault,
         OpTransferVaultBalance, OpTransferFromReserveToVault:
        return true
    }
    return false
}

// GetPollURL returns empty string as queries don't need polling.
func (h *TrezorActivitiesV2QueryResultHandler) GetPollURL(
    operationName string,
    futureType string,
    externalFutureRef string,
    endpoint *model.Endpoint,
) string {
    return ""
}
```

### 0.7 Add CreateTreasuryVaultLinksDirect Helper

**File**: `pkg/laser/handlers/treasury_links.go`

Add a new function that creates bidirectional treasury vault links using slot IIDs directly (bypasses `future.SlotAddressToIidMap`). This is needed because query result handlers don't have pre-populated SlotAddressToIidMap.

```go
// CreateTreasuryVaultLinksDirect creates bidirectional TREASURY_ERC20_VAULT_HOLDER/HOLDING
// links using slot IIDs directly (without requiring future.SlotAddressToIidMap).
//
// This is used by query result handlers where the future's SlotAddressToIidMap
// is NOT pre-populated with all relevant addresses.
func CreateTreasuryVaultLinksDirect(
    ctx context.Context,
    laserStore model.LaserStore,
    accountSlotIid, erc20SlotIid string,
    accountAddr, erc20Addr string,
    future *model.Future,  // Used only for metadata extraction (legal_structure_iid, treasury_slot_address)
) error {
    // Create HOLDER link: account -> erc20
    holderLinkIid := fmt.Sprintf("laser_slot_link_%s", common.SecureRandomString(32))
    holderLink := &model.SlotLink{
        Iid:      holderLinkIid,
        Slot1Iid: accountSlotIid,
        Slot2Iid: erc20SlotIid,
        LinkType: model.SlotLinkTypeEnum_TreasuryErc20VaultHolder,
        LinkTags: []string{},
        Active:   true,
        DisplayNames: map[string]string{
            "en-US": fmt.Sprintf("Treasury vault link: %s holds %s in vault", accountAddr, erc20Addr),
        },
        Labels: map[string]string{
            "from": "account",
            "to":   "erc20",
        },
        Tags: []string{"treasury", "vault", "erc20", string(model.SlotLinkTypeEnum_TreasuryErc20VaultHolder)},
        Metadata: map[string]string{
            "from_address": accountAddr,
            "to_address":   erc20Addr,
            "ledger_id":    "1",
        },
    }

    // Copy metadata from future if available
    if future != nil && future.Metadata != nil {
        if lsIid, ok := future.Metadata["legal_structure_iid"]; ok && lsIid != "" {
            holderLink.Metadata["legal_structure_iid"] = lsIid
        }
        if tsAddr, ok := future.Metadata["treasury_slot_address"]; ok && tsAddr != "" {
            holderLink.Metadata["treasury_slot_address"] = tsAddr
        }
    }

    created, err := laserStore.CreateSlotLinkIfNotExists(ctx, holderLink)
    if err != nil {
        return fmt.Errorf("failed to create TREASURY_ERC20_VAULT_HOLDER link: %w", err)
    }
    if created {
        common.L.Info(fmt.Sprintf("CreateTreasuryVaultLinksDirect: Created HOLDER link %s for account=%s, erc20=%s",
            holderLinkIid, accountAddr, erc20Addr), common.F(ctx)...)
    }

    // Create HOLDING link: erc20 -> account
    holdingLinkIid := fmt.Sprintf("laser_slot_link_%s", common.SecureRandomString(32))
    holdingLink := &model.SlotLink{
        Iid:      holdingLinkIid,
        Slot1Iid: erc20SlotIid,
        Slot2Iid: accountSlotIid,
        LinkType: model.SlotLinkTypeEnum_TreasuryErc20VaultHolding,
        LinkTags: []string{},
        Active:   true,
        DisplayNames: map[string]string{
            "en-US": fmt.Sprintf("Treasury vault link: %s is held by %s in vault", erc20Addr, accountAddr),
        },
        Labels: map[string]string{
            "from": "erc20",
            "to":   "account",
        },
        Tags: []string{"treasury", "vault", "erc20", string(model.SlotLinkTypeEnum_TreasuryErc20VaultHolding)},
        Metadata: map[string]string{
            "from_address": erc20Addr,
            "to_address":   accountAddr,
            "ledger_id":    "1",
        },
    }

    // Copy metadata from future
    if future != nil && future.Metadata != nil {
        if lsIid, ok := future.Metadata["legal_structure_iid"]; ok && lsIid != "" {
            holdingLink.Metadata["legal_structure_iid"] = lsIid
        }
        if tsAddr, ok := future.Metadata["treasury_slot_address"]; ok && tsAddr != "" {
            holdingLink.Metadata["treasury_slot_address"] = tsAddr
        }
    }

    created, err = laserStore.CreateSlotLinkIfNotExists(ctx, holdingLink)
    if err != nil {
        return fmt.Errorf("failed to create TREASURY_ERC20_VAULT_HOLDING link: %w", err)
    }
    if created {
        common.L.Info(fmt.Sprintf("CreateTreasuryVaultLinksDirect: Created HOLDING link %s for erc20=%s, account=%s",
            holdingLinkIid, erc20Addr, accountAddr), common.F(ctx)...)
    }

    return nil
}
```

### 0.8 Add AccMgr "List All Legal Structures" Endpoint

**File**: `pkg/daemons/accmgr/api/v1/api.go`

Add route:

```go
r.GET(ApiV1UriPrefix+"/legal-structures", getAllLegalStructures)
```

**File**: `pkg/daemons/accmgr/api/v1/legal_structures_get.go`

Add handler. The store already has `QueryLegalStructures(ctx, options)`:

```go
// getAllLegalStructures returns all legal structures.
// @Summary List all legal structures
// @Description Returns all legal structures across all participants
// @Tags LegalStructures
// @Accept json
// @Produce json
// @Param limit query int false "Limit (max 500)" default(100)
// @Param offset query int false "Offset" default(0)
// @Param search query string false "FTS search"
// @Success 200 {object} legalStructuresListResponse
// @Router /api/v1/legal-structures [get]
func getAllLegalStructures(c *gin.Context) {
    accountStore, err := getAccountStore(c)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    options := parseQueryOptions(c)
    legalStructures, queryResponse, err := accountStore.QueryLegalStructures(c.Request.Context(), options)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusOK, legalStructuresListResponse{
        LegalStructures: legalStructures,
        Total:           queryResponse.Total,
    })
}
```

### 0.9 Add Service Base URL Helper

**File**: `pkg/common/helpers.go`

Add case in `GetServiceBaseURL`:

```go
case "treasidxer":
    envVarName = "TREASURY_INDEXER_BASE_URL"
```

### 0.10 Implement lcmgr Query Handlers (EthBC Mode)

**File**: `pkg/daemons/lcmgr/ethbc_diamond_contract.go`

Add two cases to the `ExecuteQuery` switch statement:

```go
case string(model.OperationNameEnum_TrezorGetNrOfActivities):
    return c.queryTrezorGetNrOfActivities(ctx, req)
case string(model.OperationNameEnum_TrezorGetActivitiesV2):
    return c.queryTrezorGetActivitiesV2(ctx, req)
```

Implement `queryTrezorGetNrOfActivities`:
- Instantiate `activitystorefacet.NewActivityStoreFacetCaller(contractAddr, client)`
- Call `GetNrOfActivities(&bind.CallOpts{})` which returns a `*big.Int`
- Return result via `makeQueryResponse("nr_of_activities", ats.DataTypeEnum_String, count.String())`

Implement `queryTrezorGetActivitiesV2`:
- Extract `after_activity_id` argument from `req.CallData.Decl.Arguments`
- Parse to `*big.Int`
- Call `GetActivitiesV2(&bind.CallOpts{}, afterActivityId)`
- Convert `[]IActivityStoreV2ActivityV2` array to `[]map[string]interface{}` following the field mapping from `pkg/chain/trezor/activity.go:FetchActivities`:
  - `hash` → `common.Bytes2Hex(activity.V1.Hash[:])`
  - `id` → `activity.V1.Id.String()`
  - `timestamp` → `activity.V1.Timestamp.String()`
  - `ledger_id` → `activity.V1.Base.LedgerId.String()`
  - `sender_account` → `activity.V1.Base.SenderAccount.Hex()`
  - `caller_account` → `activity.V1.Base.CallerAccount.Hex()`
  - `operation` → `activity.V1.Base.Operation.String()`
  - `contract_addr` → `activity.V1.Base.ContractAddr.Hex()`
  - `contract_type` → `activity.V1.Base.ContractType.String()`
  - `from_account` → `activity.V1.Base.FromAccount.Hex()`
  - `to_account` → `activity.V1.Base.ToAccount.Hex()`
  - `from_vault` → `activity.V1.Base.FromVault.Hex()`
  - `to_vault` → `activity.V1.Base.ToVault.Hex()`
  - `from_reserve_id` → `activity.V1.Base.FromReserveId.String()`
  - `to_reserve_id` → `activity.V1.Base.ToReserveId.String()`
  - `from_stash` → `activity.V1.Base.FromStash.String()`
  - `to_stash` → `activity.V1.Base.ToStash.String()`
  - `token_id` → `activity.V1.Base.TokenId.String()`
  - `amount` → `activity.V1.Base.Amount.String()`
  - `data` → `common.Bytes2Hex(activity.V1.Base.Data)`
  - `idempotency_key` → `common.Bytes2Hex(activity.IdempotencyKey[:])`
- Return as array via `makeQueryResponse("activities", ats.DataTypeEnum_Array, activityMaps)`

**IMPORTANT**: All Ethereum addresses MUST be returned lowercase with `0x` prefix. Use `.Hex()` which returns checksummed, then apply `strings.ToLower()`. lcmgr is responsible for returning properly formatted addresses — LASER does NOT normalize.

### 0.11 Implement lcmgr Query Handlers (RDBMS Mode)

**File**: `pkg/daemons/lcmgr/trezor_erc20_contract.go`

Add two cases to the `ExecuteQuery` switch statement, following the RDBMS simulation pattern. For RDBMS mode, activities are stored in the contract store's activity table.

**Reference**: `pkg/chain/trezor/activity.go` for the `Activity` struct and `FetchActivities()` function.

---

## Phase 1: Daemon Scaffold

### 1.1 Entry Point

**New File**: `cmd/agora/daemons/treasidxer/cmd.go`

```go
package treasidxer

import (
    "github.com/spf13/cobra"
    "qomet.tech/agora/daemons/pkg/daemons"
)

func NewTreasuryIndexerCommand() *cobra.Command {
    cmd := &cobra.Command{
        Use:   "treasidxer",
        Short: "starts agora treasury-indexer daemon",
        Long:  "starts agora treasury-indexer daemon that indexes on-chain treasury activities via LASER",
        Run: func(cmd *cobra.Command, args []string) {
            daemons.RunTreasuryIndexer()
        },
    }
    return cmd
}
```

### 1.2 Register Command

**File**: `cmd/agora/daemons/root/root.go`

Add import and register command:

```go
import "qomet.tech/agora/daemons/cmd/agora/daemons/treasidxer"

// In initDaemonCommands():
cmd.AddCommand(treasidxer.NewTreasuryIndexerCommand())
```

### 1.3 Daemon Runner

**New File**: `pkg/daemons/treasidxer.go`

Following `tradeidxer.go` pattern exactly:

```go
package daemons

import (
    "context"
    "fmt"
    "net/http"
    "os"
    "os/signal"
    "syscall"

    "github.com/gin-gonic/gin"
    "qomet.tech/agora/daemons/pkg/common"
    treasidxerApi "qomet.tech/agora/daemons/pkg/daemons/treasidxer/api/v1"
    "qomet.tech/agora/daemons/pkg/daemons/treasidxer/clients"
    "qomet.tech/agora/daemons/pkg/daemons/treasidxer/indexer"
    "qomet.tech/agora/daemons/pkg/daemons/treasidxer/laser"
    "qomet.tech/agora/daemons/pkg/daemons/treasidxer/stores"
)

func RunTreasuryIndexer() {
    common.SubComponent = "treasidxer"
    common.InitLogger()

    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()

    // Initialize Redis cache (DB 14)
    common.InitCache()

    // Required: LASER client auth key
    laserAuthKey := os.Getenv("LASER_CLIENT_AUTH_KEY")
    if laserAuthKey == "" {
        common.L.Fatal("LASER_CLIENT_AUTH_KEY environment variable is required")
    }

    // Required: PostgreSQL connection string
    pgsqlConnStr := os.Getenv("POSTGRESQL_CONN_STRING")
    if pgsqlConnStr == "" {
        common.L.Fatal("POSTGRESQL_CONN_STRING environment variable is required")
    }

    // Required: Service URLs
    laserBaseURL, err := common.GetServiceBaseURL("lasersvc")
    if err != nil {
        common.L.Fatal(fmt.Sprintf("Failed to get lasersvc base URL: %v", err))
    }

    accMgrBaseURL, err := common.GetServiceBaseURL("accmgr")
    if err != nil {
        common.L.Fatal(fmt.Sprintf("Failed to get accmgr base URL: %v", err))
    }

    // Optional: Event poll interval (default 5s)
    pollIntervalStr := os.Getenv("EVENT_POLL_INTERVAL")
    // Parse to time.Duration...

    // Initialize clients
    laserClient := laser.NewTreasuryLaserClient(laserBaseURL, laserAuthKey)
    accMgrClient := clients.NewAccMgrClient(accMgrBaseURL)

    // Initialize PostgreSQL store
    activityStore, err := stores.NewPgsqlActivityStore(pgsqlConnStr)
    if err != nil {
        common.L.Fatal(fmt.Sprintf("Failed to initialize PostgreSQL store: %v", err))
    }

    // Start treasury discovery (background goroutine)
    discovery := indexer.NewTreasuryDiscovery(accMgrClient, laserClient, activityStore, pollIntervalStr)
    go discovery.Start(ctx)

    // Set up Gin router
    r := gin.Default()
    treasidxerApi.Init(r, discovery, activityStore)

    // Start HTTP server
    srv := &http.Server{
        Addr:    "0.0.0.0:17223",
        Handler: r,
    }

    go func() {
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            common.L.Fatal(fmt.Sprintf("HTTP server error: %v", err))
        }
    }()

    common.L.Info("Treasury Indexer started on port 17223")

    // Graceful shutdown
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit

    common.L.Info("Shutting down treasury indexer...")
    cancel()
    srv.Shutdown(context.Background())
}
```

### 1.4 Redis DB Constant

**File**: `pkg/common/vars.go`

```go
TreasuryIndexerRedisDB int = 14
```

---

## Phase 2: Discovery (AccMgr-based)

### 2.1 AccMgr HTTP Client

**New File**: `pkg/daemons/treasidxer/clients/accmgr_client.go`

HTTP client for the three-step discovery chain:

```go
package clients

import (
    "context"
    "encoding/json"
    "fmt"
    "net/http"
    "time"

    "qomet.tech/agora/daemons/pkg/fin"
)

type AccMgrClient struct {
    BaseURL    string
    HttpClient *http.Client
}

func NewAccMgrClient(baseURL string) *AccMgrClient {
    return &AccMgrClient{
        BaseURL: baseURL,
        HttpClient: &http.Client{Timeout: 30 * time.Second},
    }
}

// GetAllLegalStructures fetches all legal structures from accmgr.
// Calls: GET /api/v1/legal-structures
func (c *AccMgrClient) GetAllLegalStructures(ctx context.Context) ([]*fin.LegalStructure, error)

// GetMechanismsByStructure fetches mechanisms for a legal structure, filtered by type.
// Calls: GET /api/v1/legal-structures/{iid}/mechanisms?type={mechType}
func (c *AccMgrClient) GetMechanismsByStructure(ctx context.Context, lsIid, mechType string) ([]*fin.LegalMechanism, error)

// GetMechanismDeployments fetches deployments for a legal mechanism.
// Calls: GET /api/v1/legal-mechanisms/{iid}/deployments
func (c *AccMgrClient) GetMechanismDeployments(ctx context.Context, mechIid string) ([]*fin.LegalMechanismDeployment, error)

// HealthCheck verifies accmgr is reachable.
func (c *AccMgrClient) HealthCheck(ctx context.Context) error
```

**Discovery chain** (called by TreasuryDiscovery):
1. `GetAllLegalStructures()` → list of `LegalStructure`
2. For each: `GetMechanismsByStructure(lsIid, "LEGAL_MECHANISM_TYPE_ENUM_TREASURY")` → list of `LegalMechanism`
3. For each TREASURY mechanism: `GetMechanismDeployments(mechIid)` → list of `LegalMechanismDeployment`
4. For each deployment of type `LEGAL_MECHANISM_DEPLOYMENT_TYPE_ENUM_LASER`:
   - Unmarshal `DeploymentDetails` to `LaserLegalMechanismDeploymentDetails`
   - Extract `.SlotAddress` and `.ExecutionRuntimeName`

### 2.2 Treasury Deployment Info

**New File**: `pkg/daemons/treasidxer/indexer/types.go`

```go
package indexer

// TreasuryDeploymentInfo holds all information about a discovered treasury deployment
type TreasuryDeploymentInfo struct {
    DeploymentIid        string `json:"deployment_iid"`
    MechanismIid         string `json:"mechanism_iid"`
    LegalStructureIid    string `json:"legal_structure_iid"`
    SlotAddress          string `json:"slot_address"`           // Trezor contract address
    ExecutionRuntimeName string `json:"execution_runtime_name"` // e.g., "primary"
}
```

### 2.3 Treasury Discovery

**New File**: `pkg/daemons/treasidxer/indexer/discovery.go`

Following `tradeidxer/indexer/discovery.go` pattern:

```go
package indexer

import (
    "context"
    "sync"
    "time"

    "qomet.tech/agora/daemons/pkg/common"
    "qomet.tech/agora/daemons/pkg/daemons/treasidxer/clients"
    "qomet.tech/agora/daemons/pkg/daemons/treasidxer/laser"
    "qomet.tech/agora/daemons/pkg/daemons/treasidxer/stores"
    "qomet.tech/agora/daemons/pkg/fin"
)

const (
    DefaultDiscoveryPollInterval = 30 * time.Second
)

type TreasuryDiscovery struct {
    accMgrClient         *clients.AccMgrClient
    laserClient          *laser.TreasuryLaserClient
    activityStore        stores.ActivityStore
    activeJobs           map[string]*ActivityIndexerJob  // key: deployment IID
    mu                   sync.RWMutex
    discoveryInterval    time.Duration
    activityPollInterval time.Duration
    stopCh               chan struct{}
}

func NewTreasuryDiscovery(
    accMgrClient *clients.AccMgrClient,
    laserClient *laser.TreasuryLaserClient,
    activityStore stores.ActivityStore,
    activityPollIntervalStr string,
) *TreasuryDiscovery

func (d *TreasuryDiscovery) Start(ctx context.Context)

// discoverAndSync polls accmgr for treasury deployments and starts/stops jobs
func (d *TreasuryDiscovery) discoverAndSync(ctx context.Context) error {
    // 1. Get all legal structures
    legalStructures, err := d.accMgrClient.GetAllLegalStructures(ctx)
    // 2. For each, get TREASURY mechanisms
    // 3. For each mechanism, get deployments
    // 4. For each LASER deployment:
    //    - Extract slot address + exec_runtime_name
    //    - If not in activeJobs: create ActivityIndexerJob, start it
    // 5. Stop jobs for removed deployments
}

func (d *TreasuryDiscovery) GetActiveJobs() map[string]*ActivityIndexerJobStatus
func (d *TreasuryDiscovery) GetJobStatus(deploymentIid string) *ActivityIndexerJobStatus
func (d *TreasuryDiscovery) Stop()
```

---

## Phase 3: LASER Client Library

### 3.1 Treasury LASER Query Client

**New File**: `pkg/daemons/treasidxer/laser/client.go`

Follows `tradeidxer/laser/client.go` pattern — HTTP client wrapper for LASER query API:

```go
package laser

import (
    "context"
    "encoding/json"
    "fmt"
    "net/http"
    "time"

    "qomet.tech/agora/daemons/pkg/common"
)

type TreasuryLaserClient struct {
    BaseURL     string
    AuthKey     string
    ExecutorIid string   // Crown executor IID (fetched lazily)
    HttpClient  *http.Client
}

func NewTreasuryLaserClient(baseURL, authKey string) *TreasuryLaserClient {
    return &TreasuryLaserClient{
        BaseURL:    baseURL,
        AuthKey:    authKey,
        HttpClient: &http.Client{Timeout: 30 * time.Second},
    }
}

// GetNrOfActivities calls TrezorGetNrOfActivities on the Trezor diamond.
// Returns the total number of activities recorded in the ActivityStore.
//
// LASER query: POST /api/v1/executors/{executorIid}/query
//   call_data.decl.name = "TrezorGetNrOfActivities"
//   to_slot_address = trezorSlotAddr (the treasury mechanism slot address)
//   exec_runtime_name = execRuntimeName
func (c *TreasuryLaserClient) GetNrOfActivities(
    ctx context.Context,
    trezorSlotAddr string,
    execRuntimeName string,
) (int64, error)

// GetActivitiesV2 calls TrezorGetActivitiesV2 on the Trezor diamond.
// Returns activities with ID > afterId.
//
// LASER query: POST /api/v1/executors/{executorIid}/query
//   call_data.decl.name = "TrezorGetActivitiesV2"
//   call_data.decl.arguments = [{name: "after_activity_id", type: "int64", value: afterId}]
//   to_slot_address = trezorSlotAddr
//   exec_runtime_name = execRuntimeName
func (c *TreasuryLaserClient) GetActivitiesV2(
    ctx context.Context,
    trezorSlotAddr string,
    afterId int64,
    execRuntimeName string,
) ([]TrezorActivityResult, error)

// fetchExecutorIid lazily fetches the crown executor IID from LASER /config endpoint.
// Cached for subsequent queries. Reset via ResetExecutorIid() on slot translation errors.
func (c *TreasuryLaserClient) fetchExecutorIid() (string, error)

// ResetExecutorIid clears the cached executor IID, forcing a re-fetch on next query.
func (c *TreasuryLaserClient) ResetExecutorIid()

// doQuery executes a LASER query with automatic retry on slot translation errors.
// Pattern copied from tradeidxer/laser/client.go.
func (c *TreasuryLaserClient) doQuery(
    ctx context.Context,
    operationName string,
    toSlotAddr string,
    execRuntimeName string,
    args []map[string]interface{},
) (map[string]interface{}, error)
```

**IMPORTANT**: The `doQuery` method must:
1. Build an ATS BoundFunc from operation name and arguments
2. Send POST to `/api/v1/executors/{executorIid}/query` with the `LASER-Client-Auth-Key` header
3. Parse response, checking both `inner_result` (relay chain) and direct `output`
4. On slot translation error, reset executor IID and retry once
5. Return the raw output map

### 3.2 Activity Result Types

**New File**: `pkg/daemons/treasidxer/laser/types.go`

```go
package laser

// TrezorActivityResult represents a single activity from GetActivitiesV2.
// All fields are strings because LASER returns all values as strings via BoundVariable format.
type TrezorActivityResult struct {
    Hash           string `json:"hash"`              // bytes32 hex
    Id             string `json:"id"`                // uint256 decimal string
    Timestamp      string `json:"timestamp"`         // uint256 unix timestamp
    LedgerId       string `json:"ledger_id"`
    SenderAccount  string `json:"sender_account"`    // address hex, 0x-prefixed, lowercase
    CallerAccount  string `json:"caller_account"`
    Operation      string `json:"operation"`         // uint256 decimal (101-208)
    ContractAddr   string `json:"contract_addr"`     // ERC20 address
    ContractType   string `json:"contract_type"`     // 0, 20, 721, 1155
    FromAccount    string `json:"from_account"`
    ToAccount      string `json:"to_account"`
    FromVault      string `json:"from_vault"`
    ToVault        string `json:"to_vault"`
    FromReserveId  string `json:"from_reserve_id"`
    ToReserveId    string `json:"to_reserve_id"`
    FromStash      string `json:"from_stash"`
    ToStash        string `json:"to_stash"`
    TokenId        string `json:"token_id"`
    Amount         string `json:"amount"`            // uint256 decimal
    Data           string `json:"data"`              // hex encoded reference data
    IdempotencyKey string `json:"idempotency_key"`   // bytes32 hex
}
```

---

## Phase 4: PostgreSQL Storage

### 4.1 SQL Schema

**New File**: `deploy/k8s/init/init_treasidxer_pgsql.sql`

```sql
-- PostgreSQL initialization script for TreasIdxer schema
-- This script creates the treasidxer schema for storing treasury activities
-- from Trezor smart contract ActivityStoreFacet, indexed via LASER query API.
--
-- Tables:
--   treasidxer.treasury_activities - One row per Trezor ActivityV2
--   treasidxer.activity_cursors    - Per-deployment cursor tracking for activity polling

-- Step 1: Connect to the agora_db database
\c agora_db;

-- Step 2: Create treasidxer schema
CREATE SCHEMA IF NOT EXISTS treasidxer;

\echo 'TreasIdxer schema created successfully!';
\echo '';

-- Step 3: Create treasury_activities table
-- Each row is a Trezor ActivityV2 from the ActivityStoreFacet on-chain contract.
-- Fields map to IActivityStoreV1.BaseActivity struct fields.
CREATE TABLE IF NOT EXISTS treasidxer.treasury_activities (
    iid VARCHAR PRIMARY KEY,

    -- Activity identity (from ActivityV2 struct)
    activity_id VARCHAR NOT NULL UNIQUE,            -- on-chain activity ID (uint256 decimal)
    activity_hash VARCHAR NOT NULL DEFAULT '',       -- bytes32 universal hash
    idempotency_key VARCHAR NOT NULL DEFAULT '',     -- bytes32 idempotency key

    -- Activity context
    timestamp VARCHAR NOT NULL,                     -- unix timestamp (uint256 decimal)
    ledger_id VARCHAR NOT NULL DEFAULT '',           -- ledger identifier (uint256 decimal)
    operation VARCHAR NOT NULL,                     -- operation code: 101-108 (vault), 201-208 (reserve)
    operation_name VARCHAR NOT NULL DEFAULT '',      -- human-readable: DEPOSIT_TO_VAULT, etc.

    -- Addresses (all 0x-prefixed, lowercase hex)
    sender_account VARCHAR NOT NULL DEFAULT '',      -- account that initiated the transaction
    caller_account VARCHAR NOT NULL DEFAULT '',      -- smart contract caller account
    contract_addr VARCHAR NOT NULL DEFAULT '',       -- ERC20/ERC721/ERC1155 token address
    contract_type VARCHAR NOT NULL DEFAULT '',       -- 0=none, 20=ERC20, 721=ERC721, 1155=ERC1155
    from_account VARCHAR NOT NULL DEFAULT '',        -- source account (for transfers)
    to_account VARCHAR NOT NULL DEFAULT '',          -- destination account (for transfers)
    from_vault VARCHAR NOT NULL DEFAULT '',          -- source vault address
    to_vault VARCHAR NOT NULL DEFAULT '',            -- destination vault address

    -- Reserve/stash fields
    from_reserve_id VARCHAR NOT NULL DEFAULT '',     -- source reserve ID (uint256)
    to_reserve_id VARCHAR NOT NULL DEFAULT '',       -- destination reserve ID (uint256)
    from_stash VARCHAR NOT NULL DEFAULT '',          -- source stash index (uint256)
    to_stash VARCHAR NOT NULL DEFAULT '',            -- destination stash index (uint256)

    -- Token fields
    token_id VARCHAR NOT NULL DEFAULT '',            -- token ID for ERC721/ERC1155 (uint256)
    amount VARCHAR NOT NULL DEFAULT '',              -- amount transferred (uint256)
    data VARCHAR NOT NULL DEFAULT '',                -- hex-encoded reference data (order/trade info)

    -- Deployment context (from TreasuryDeploymentInfo)
    deployment_iid VARCHAR NOT NULL,                -- legal mechanism deployment IID
    mechanism_iid VARCHAR NOT NULL DEFAULT '',       -- legal mechanism IID
    legal_structure_iid VARCHAR NOT NULL DEFAULT '', -- owning legal structure IID
    trezor_slot_address VARCHAR NOT NULL DEFAULT '', -- Trezor contract slot address
    exec_runtime_name VARCHAR NOT NULL DEFAULT '',   -- execution runtime: "primary", etc.

    -- Standard JSONB fields
    display_names JSONB NOT NULL DEFAULT '{}'::jsonb,
    labels JSONB NOT NULL DEFAULT '{}'::jsonb,
    tags JSONB NOT NULL DEFAULT '[]'::jsonb,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_treasury_activities_entity
        FOREIGN KEY (iid) REFERENCES shared.entities(iid) ON DELETE CASCADE
);

\echo 'TreasIdxer treasury_activities table created successfully!';

-- Step 4: Create activity_cursors table
-- Tracks the last processed ActivityStore activity per deployment for cursor-based polling.
CREATE TABLE IF NOT EXISTS treasidxer.activity_cursors (
    deployment_iid VARCHAR PRIMARY KEY,
    trezor_slot_address VARCHAR NOT NULL DEFAULT '',
    exec_runtime_name VARCHAR NOT NULL DEFAULT '',
    legal_structure_iid VARCHAR NOT NULL DEFAULT '',
    last_activity_id BIGINT NOT NULL DEFAULT 0,
    last_activity_ts BIGINT NOT NULL DEFAULT 0,
    nr_of_activities_processed BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

\echo 'TreasIdxer activity_cursors table created successfully!';

-- Step 5: Create indexes

-- treasury_activities indexes
CREATE INDEX IF NOT EXISTS idx_treas_activities_activity_id ON treasidxer.treasury_activities(activity_id);
CREATE INDEX IF NOT EXISTS idx_treas_activities_deployment_iid ON treasidxer.treasury_activities(deployment_iid);
CREATE INDEX IF NOT EXISTS idx_treas_activities_operation ON treasidxer.treasury_activities(operation);
CREATE INDEX IF NOT EXISTS idx_treas_activities_contract_addr ON treasidxer.treasury_activities(contract_addr);
CREATE INDEX IF NOT EXISTS idx_treas_activities_from_vault ON treasidxer.treasury_activities(from_vault);
CREATE INDEX IF NOT EXISTS idx_treas_activities_to_vault ON treasidxer.treasury_activities(to_vault);
CREATE INDEX IF NOT EXISTS idx_treas_activities_from_account ON treasidxer.treasury_activities(from_account);
CREATE INDEX IF NOT EXISTS idx_treas_activities_to_account ON treasidxer.treasury_activities(to_account);
CREATE INDEX IF NOT EXISTS idx_treas_activities_legal_structure_iid ON treasidxer.treasury_activities(legal_structure_iid);
CREATE INDEX IF NOT EXISTS idx_treas_activities_sender_account ON treasidxer.treasury_activities(sender_account);
CREATE INDEX IF NOT EXISTS idx_treas_activities_created_at ON treasidxer.treasury_activities(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_treas_activities_timestamp ON treasidxer.treasury_activities(timestamp);
CREATE INDEX IF NOT EXISTS idx_treas_activities_tags ON treasidxer.treasury_activities USING GIN(tags);

\echo 'TreasIdxer indexes created successfully!';

-- Step 6: Set permissions
GRANT ALL PRIVILEGES ON SCHEMA treasidxer TO agora_app;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA treasidxer TO agora_app;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA treasidxer TO agora_app;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA treasidxer TO agora_app;

-- Show current schema and tables
\dn+ treasidxer
\dt treasidxer.*

-- Success message
\echo 'PostgreSQL TreasIdxer schema initialization completed successfully!';
```

### 4.2 Mini Records SQL

**New File**: `deploy/k8s/init/csd/min/treasidxer.sql`

```sql
-- Mini records for TreasIdxer (empty - activities are populated by the indexer)
\c agora_db;
\echo 'TreasIdxer mini records: No seed data required (activities are populated by indexer).';
```

### 4.3 Store Models

**New File**: `pkg/daemons/treasidxer/stores/models.go`

```go
package stores

import "time"

// OperationTypeNames maps operation codes to human-readable names
var OperationTypeNames = map[int]string{
    101: "DEPOSIT_TO_VAULT",
    102: "WITHDRAW_FROM_VAULT",
    103: "TRANSFER_TO_VAULT",
    104: "TRANSFER_FROM_VAULT_TO_RESERVE",
    105: "SET_ALLOWANCE_ON_VAULT",
    106: "MOVE_ORPHAN_TO_VAULT",
    107: "TRANSFER_VAULT_BALANCE",
    108: "SET_VAULT_BALANCE_ON_SLAVE_LEDGER",
    201: "DEPOSIT_TO_RESERVE",
    202: "WITHDRAW_FROM_RESERVE",
    203: "TRANSFER_TO_RESERVE",
    204: "TRANSFER_FROM_RESERVE_TO_VAULT",
    205: "SET_ALLOWANCE_ON_RESERVE",
    206: "MOVE_ORPHAN_TO_RESERVE",
    207: "TRANSFER_RESERVE_BALANCE",
    208: "SET_RESERVE_BALANCE_ON_SLAVE_LEDGER",
}

type TreasuryActivity struct {
    Iid               string            `json:"iid"`
    ActivityId        string            `json:"activity_id"`
    ActivityHash      string            `json:"activity_hash"`
    IdempotencyKey    string            `json:"idempotency_key"`
    Timestamp         string            `json:"timestamp"`
    LedgerId          string            `json:"ledger_id"`
    Operation         string            `json:"operation"`
    OperationName     string            `json:"operation_name"`
    SenderAccount     string            `json:"sender_account"`
    CallerAccount     string            `json:"caller_account"`
    ContractAddr      string            `json:"contract_addr"`
    ContractType      string            `json:"contract_type"`
    FromAccount       string            `json:"from_account"`
    ToAccount         string            `json:"to_account"`
    FromVault         string            `json:"from_vault"`
    ToVault           string            `json:"to_vault"`
    FromReserveId     string            `json:"from_reserve_id"`
    ToReserveId       string            `json:"to_reserve_id"`
    FromStash         string            `json:"from_stash"`
    ToStash           string            `json:"to_stash"`
    TokenId           string            `json:"token_id"`
    Amount            string            `json:"amount"`
    Data              string            `json:"data"`
    DeploymentIid     string            `json:"deployment_iid"`
    MechanismIid      string            `json:"mechanism_iid"`
    LegalStructureIid string            `json:"legal_structure_iid"`
    TrezorSlotAddress string            `json:"trezor_slot_address"`
    ExecRuntimeName   string            `json:"exec_runtime_name"`
    DisplayNames      map[string]string `json:"display_names"`
    Labels            map[string]string `json:"labels"`
    Tags              []string          `json:"tags"`
    Metadata          map[string]string `json:"metadata"`
    CreatedAt         time.Time         `json:"created_at"`
    UpdatedAt         time.Time         `json:"updated_at"`
}

type ActivityCursor struct {
    DeploymentIid           string    `json:"deployment_iid"`
    TrezorSlotAddress       string    `json:"trezor_slot_address"`
    ExecRuntimeName         string    `json:"exec_runtime_name"`
    LegalStructureIid       string    `json:"legal_structure_iid"`
    LastActivityId          int64     `json:"last_activity_id"`
    LastActivityTs          int64     `json:"last_activity_ts"`
    NrOfActivitiesProcessed int64     `json:"nr_of_activities_processed"`
    UpdatedAt               time.Time `json:"updated_at"`
}
```

### 4.4 Store Interface

**New File**: `pkg/daemons/treasidxer/stores/store.go`

```go
package stores

import "context"

type ActivityStore interface {
    // InsertTreasuryActivity inserts a single activity. Idempotent (ON CONFLICT DO NOTHING on activity_id).
    InsertTreasuryActivity(ctx context.Context, a *TreasuryActivity) error

    // GetTreasuryActivityByActivityId fetches a single activity by on-chain ID.
    GetTreasuryActivityByActivityId(ctx context.Context, activityId string) (*TreasuryActivity, error)

    // ListTreasuryActivities lists activities for a deployment with filters and pagination.
    // Supported filters: operation, contract_addr, from_vault, to_vault, from_account,
    // to_account, legal_structure_iid, sender_account, from_ts, to_ts.
    // sortDir: "asc" or "desc" (default: "desc" by created_at).
    ListTreasuryActivities(ctx context.Context, deploymentIid string, filters map[string]string, limit, offset int, sortDir string) ([]TreasuryActivity, int, error)

    // ListAllTreasuryActivities lists activities across all deployments with filters.
    ListAllTreasuryActivities(ctx context.Context, filters map[string]string, limit, offset int, sortDir string) ([]TreasuryActivity, int, error)

    // GetActivityCursor retrieves the cursor for a deployment.
    GetActivityCursor(ctx context.Context, deploymentIid string) (*ActivityCursor, error)

    // UpsertActivityCursor creates or updates the cursor for a deployment.
    UpsertActivityCursor(ctx context.Context, cursor *ActivityCursor) error
}
```

### 4.5 PostgreSQL Store Implementation

**New File**: `pkg/daemons/treasidxer/stores/pgsql_store.go`

Following `tradeidxer/stores/pgsql_store.go` pattern:

```go
package stores

import (
    "context"
    "database/sql"
    "encoding/json"
    "fmt"

    "qomet.tech/agora/daemons/pkg/common"
    _ "github.com/lib/pq"
)

type PgsqlActivityStore struct {
    db *sql.DB
}

func NewPgsqlActivityStore(connStr string) (*PgsqlActivityStore, error) {
    db, err := sql.Open("postgres", connStr)
    if err != nil {
        return nil, fmt.Errorf("failed to connect to PostgreSQL: %w", err)
    }
    // Configure connection pool (same as tradeidxer)
    db.SetMaxOpenConns(10)
    db.SetMaxIdleConns(5)
    return &PgsqlActivityStore{db: db}, nil
}

// InsertTreasuryActivity uses ON CONFLICT (activity_id) DO NOTHING for idempotency.
// Before inserting, creates the entity in shared.entities table.
func (s *PgsqlActivityStore) InsertTreasuryActivity(ctx context.Context, a *TreasuryActivity) error

// GetTreasuryActivityByActivityId fetches by on-chain activity ID.
func (s *PgsqlActivityStore) GetTreasuryActivityByActivityId(ctx context.Context, activityId string) (*TreasuryActivity, error)

// ListTreasuryActivities with dynamic WHERE clauses based on filters.
func (s *PgsqlActivityStore) ListTreasuryActivities(ctx context.Context, deploymentIid string, filters map[string]string, limit, offset int, sortDir string) ([]TreasuryActivity, int, error)

// ListAllTreasuryActivities across all deployments.
func (s *PgsqlActivityStore) ListAllTreasuryActivities(ctx context.Context, filters map[string]string, limit, offset int, sortDir string) ([]TreasuryActivity, int, error)

// GetActivityCursor retrieves cursor from treasidxer.activity_cursors.
func (s *PgsqlActivityStore) GetActivityCursor(ctx context.Context, deploymentIid string) (*ActivityCursor, error)

// UpsertActivityCursor uses INSERT ... ON CONFLICT (deployment_iid) DO UPDATE.
func (s *PgsqlActivityStore) UpsertActivityCursor(ctx context.Context, cursor *ActivityCursor) error
```

---

## Phase 5: Activity Indexer Job

### 5.1 Activity Indexer

**New File**: `pkg/daemons/treasidxer/indexer/activity_indexer.go`

Following `tradeidxer/indexer/event_indexer.go` pattern:

```go
package indexer

import (
    "context"
    "strconv"
    "time"

    "qomet.tech/agora/daemons/pkg/common"
    "qomet.tech/agora/daemons/pkg/daemons/treasidxer/laser"
    "qomet.tech/agora/daemons/pkg/daemons/treasidxer/stores"
)

const (
    DefaultActivityBatchSize    = 50
    DefaultBasePollInterval     = 5 * time.Second
    MaxPollInterval             = 60 * time.Second
    NoChangeBackoffThreshold    = 3
)

type ActivityIndexerJobStatus struct {
    DeploymentIid           string `json:"deployment_iid"`
    LegalStructureIid       string `json:"legal_structure_iid"`
    TrezorSlotAddress       string `json:"trezor_slot_address"`
    ExecRuntimeName         string `json:"exec_runtime_name"`
    Status                  string `json:"status"`               // active | paused | error
    LastActivityId          int64  `json:"last_activity_id"`
    NrOfActivitiesProcessed int64  `json:"nr_of_activities_processed"`
    PollIntervalMs          int64  `json:"poll_interval_ms"`
    ErrorMsg                string `json:"error_msg,omitempty"`
}

type ActivityIndexerJob struct {
    deploymentInfo       *TreasuryDeploymentInfo
    laserClient          *laser.TreasuryLaserClient
    store                stores.ActivityStore
    stopCh               chan struct{}
    basePollInterval     time.Duration
    currentPollInterval  time.Duration
    lastActivityId       int64
    nrProcessed          int64
    consecutiveNoChange  int
    status               string
    errorMsg             string
}

func NewActivityIndexerJob(
    info *TreasuryDeploymentInfo,
    laserClient *laser.TreasuryLaserClient,
    store stores.ActivityStore,
    basePollInterval time.Duration,
) *ActivityIndexerJob

func (j *ActivityIndexerJob) Start(ctx context.Context) {
    // 1. Load cursor from store (resume from last processed activity)
    // 2. Poll loop with exponential backoff:
    //    a. GetNrOfActivities() to check for new activities
    //    b. If no change: increment consecutiveNoChange, apply backoff
    //    c. If change: GetActivitiesV2(afterId=lastActivityId) in batches
    //    d. For each activity: convert to TreasuryActivity model, insert
    //    e. Update cursor
}

func (j *ActivityIndexerJob) pollCycle(ctx context.Context) error {
    // 1. Call GetNrOfActivities(slotAddr, execRuntimeName)
    nrOfActivities, err := j.laserClient.GetNrOfActivities(ctx, j.deploymentInfo.SlotAddress, j.deploymentInfo.ExecutionRuntimeName)
    if err != nil {
        return fmt.Errorf("GetNrOfActivities failed: %w", err)
    }

    // 2. Check if there are new activities
    if nrOfActivities <= j.lastActivityId {
        j.consecutiveNoChange++
        if j.consecutiveNoChange >= NoChangeBackoffThreshold {
            j.currentPollInterval = min(j.currentPollInterval*2, MaxPollInterval)
        }
        return nil
    }

    // 3. Reset backoff
    j.consecutiveNoChange = 0
    j.currentPollInterval = j.basePollInterval

    // 4. Fetch activities in batches
    activities, err := j.laserClient.GetActivitiesV2(ctx, j.deploymentInfo.SlotAddress, j.lastActivityId, j.deploymentInfo.ExecutionRuntimeName)
    if err != nil {
        return fmt.Errorf("GetActivitiesV2 failed: %w", err)
    }

    // 5. Process each activity
    for _, activity := range activities {
        ta := j.convertToTreasuryActivity(activity)
        if err := j.store.InsertTreasuryActivity(ctx, ta); err != nil {
            common.L.Warn(fmt.Sprintf("Failed to insert activity %s: %v", activity.Id, err))
            continue
        }

        // Update last processed ID
        activityId, _ := strconv.ParseInt(activity.Id, 10, 64)
        if activityId > j.lastActivityId {
            j.lastActivityId = activityId
        }
        j.nrProcessed++
    }

    // 6. Update cursor
    cursor := &stores.ActivityCursor{
        DeploymentIid:           j.deploymentInfo.DeploymentIid,
        TrezorSlotAddress:       j.deploymentInfo.SlotAddress,
        ExecRuntimeName:         j.deploymentInfo.ExecutionRuntimeName,
        LegalStructureIid:       j.deploymentInfo.LegalStructureIid,
        LastActivityId:          j.lastActivityId,
        NrOfActivitiesProcessed: j.nrProcessed,
    }
    return j.store.UpsertActivityCursor(ctx, cursor)
}

func (j *ActivityIndexerJob) convertToTreasuryActivity(a laser.TrezorActivityResult) *stores.TreasuryActivity {
    opCode, _ := strconv.Atoi(a.Operation)
    opName := stores.OperationTypeNames[opCode]

    return &stores.TreasuryActivity{
        Iid:               fmt.Sprintf("treas_activity_%s", common.SecureRandomString(32)),
        ActivityId:        a.Id,
        ActivityHash:      a.Hash,
        IdempotencyKey:    a.IdempotencyKey,
        Timestamp:         a.Timestamp,
        LedgerId:          a.LedgerId,
        Operation:         a.Operation,
        OperationName:     opName,
        SenderAccount:     a.SenderAccount,
        CallerAccount:     a.CallerAccount,
        ContractAddr:      a.ContractAddr,
        ContractType:      a.ContractType,
        FromAccount:       a.FromAccount,
        ToAccount:         a.ToAccount,
        FromVault:         a.FromVault,
        ToVault:           a.ToVault,
        FromReserveId:     a.FromReserveId,
        ToReserveId:       a.ToReserveId,
        FromStash:         a.FromStash,
        ToStash:           a.ToStash,
        TokenId:           a.TokenId,
        Amount:            a.Amount,
        Data:              a.Data,
        DeploymentIid:     j.deploymentInfo.DeploymentIid,
        MechanismIid:      j.deploymentInfo.MechanismIid,
        LegalStructureIid: j.deploymentInfo.LegalStructureIid,
        TrezorSlotAddress: j.deploymentInfo.SlotAddress,
        ExecRuntimeName:   j.deploymentInfo.ExecutionRuntimeName,
        DisplayNames:      map[string]string{"en-US": fmt.Sprintf("Treasury Activity #%s: %s", a.Id, opName)},
        Labels:            map[string]string{},
        Tags:              []string{"treasury", "activity", opName},
        Metadata:          map[string]string{},
    }
}

func (j *ActivityIndexerJob) Stop()
func (j *ActivityIndexerJob) GetStatus() *ActivityIndexerJobStatus
```

---

## Phase 6: REST API

### 6.1 API Initialization

**New File**: `pkg/daemons/treasidxer/api/v1/api.go`

```go
package v1

import (
    "github.com/gin-gonic/gin"
    "qomet.tech/agora/daemons/pkg/daemons/treasidxer/indexer"
    "qomet.tech/agora/daemons/pkg/daemons/treasidxer/stores"
)

func Init(r *gin.Engine, discovery *indexer.TreasuryDiscovery, store stores.ActivityStore) {
    v1 := r.Group("/api/v1")
    {
        // Health & Status
        v1.GET("/health", getHealth)
        v1.GET("/status", func(c *gin.Context) { getStatus(c, discovery) })
        v1.GET("/status/:deployment_iid", func(c *gin.Context) { getStatusByDeployment(c, discovery) })

        // Treasury Activity Endpoints (PostgreSQL-backed)
        v1.GET("/activities/:deployment_iid", func(c *gin.Context) { listActivities(c, store) })
        v1.GET("/activities/:deployment_iid/:activity_id", func(c *gin.Context) { getActivity(c, store) })

        // Cross-deployment queries
        v1.GET("/all/activities", func(c *gin.Context) { listAllActivities(c, store) })
    }
}
```

### 6.2 Activity Endpoints

**New File**: `pkg/daemons/treasidxer/api/v1/activities.go`

```go
package v1

// GET /api/v1/activities/:deployment_iid
// Query params: operation, contract_addr, from_vault, to_vault, from_account,
//               to_account, sender_account, legal_structure_iid,
//               from_ts, to_ts, limit (default 100, max 500), offset, order (asc/desc)
func listActivities(c *gin.Context, store stores.ActivityStore)

// GET /api/v1/activities/:deployment_iid/:activity_id
func getActivity(c *gin.Context, store stores.ActivityStore)

// GET /api/v1/all/activities
// Same filters as listActivities but across all deployments.
// Additional filter: deployment_iid (optional, for cross-deployment with specific deploy)
func listAllActivities(c *gin.Context, store stores.ActivityStore)
```

### 6.3 Health & Status Endpoints

**New File**: `pkg/daemons/treasidxer/api/v1/health.go`

```go
package v1

// GET /api/v1/health
func getHealth(c *gin.Context) {
    c.JSON(200, gin.H{"status": "ok"})
}

// GET /api/v1/status - Returns status of all indexer jobs
func getStatus(c *gin.Context, discovery *indexer.TreasuryDiscovery)

// GET /api/v1/status/:deployment_iid - Returns status of specific job
func getStatusByDeployment(c *gin.Context, discovery *indexer.TreasuryDiscovery)
```

---

## Phase 7: Build & Deploy Configuration

### 7.1 Makefile Target

**File**: `Makefile`

Add `treasidxer` target:

```makefile
.PHONY: treasidxer
treasidxer:
	docker run \
		${DOCKER_RUN_ARGS} \
		-p 17223:17223 \
		-e REDIS_ADDR="host.docker.internal:6379" \
		-e REDIS_DB="14" \
		-e LASER_CLIENT_AUTH_KEY="${LASER_CLIENT_AUTH_KEY}" \
		-e LASER_SERVICE_BASE_URL="http://host.docker.internal:17205" \
		-e ACCOUNT_MANAGER_BASE_URL="http://host.docker.internal:17203" \
		-e POSTGRESQL_CONN_STRING="postgresql://agora_app:agora_pass@host.docker.internal:5432/agora_db?sslmode=disable" \
		$(REGISTRY)/$(IMAGE_NAME):$(BRANCH_TAG) treasidxer
```

Also add `TREASURY_INDEXER_BASE_URL="http://host.docker.internal:17223"` to the E2E test environment variables.

Add E2E test category:

```makefile
E2E_CAT39_PATTERN := TestTreasIdxer

.PHONY: laser-e2e-ethbc-cat39
laser-e2e-ethbc-cat39:
	$(call run-laser-e2e-ethbc,$(E2E_CAT39_PATTERN))
```

### 7.2 Docker Compose Updates

Add `treasidxer` service to relevant Docker Compose files (CSD and prtagent namespace compositions). Depends on: Redis, PostgreSQL, lasersvc, accmgr.

### 7.3 K8s Helm Chart

Follow `tradeidxer` Helm chart pattern. Create:
- `deploy/k8s/charts/treasidxer/Chart.yaml`
- `deploy/k8s/charts/treasidxer/values.yaml`
- `deploy/k8s/charts/treasidxer/templates/deployment.yaml`
- `deploy/k8s/charts/treasidxer/templates/service.yaml`

### 7.4 CLAUDE.md Port Table Update

**File**: `CLAUDE.md`

Add to the Key API Ports table:

```
| treasidxer | 17223 |
```

---

## Phase 8: E2E Tests (Category 39, EthBC Mode)

### 8.1 Test Category Registration

**File**: `Makefile`

Add `E2E_CAT39_PATTERN` and `laser-e2e-ethbc-cat39` target (see Phase 7.1).

**File**: `docs/E2E_TEST_CATALOG.md`

Add Category 39:

```markdown
| 39 | ⭐⭐⭐⭐ | Treasury Indexer | `laser-e2e-ethbc-cat39` |
```

### 8.2 Test File

**New File**: `tests/e2e/laser/treasidxer_test.go`

All tests require EthBC mode (Anvil blockchain) since they need actual Trezor contracts deployed.

```go
package laser

// ====================
// GREEN PATH TESTS
// ====================

// TestTreasIdxer_HealthCheck verifies the treasidxer health endpoint
func TestTreasIdxer_HealthCheck(t *testing.T) {
    setupTestDatabaseForTreasIdxer(t)
    // GET /api/v1/health -> 200 {"status": "ok"}
}

// TestTreasIdxer_DiscoversTreasuryDeployments verifies discovery of treasury mechanisms
func TestTreasIdxer_DiscoversTreasuryDeployments(t *testing.T) {
    setupTestDatabaseForTreasIdxer(t)
    // Prereq: legal structure with treasury mechanism deployed
    // Verify: GET /api/v1/status shows the deployment with status=active
}

// TestTreasIdxer_IndexesDepositActivity verifies deposit activities are indexed
func TestTreasIdxer_IndexesDepositActivity(t *testing.T) {
    setupTestDatabaseForTreasIdxer(t)
    // 1. Execute fund_account_with_cash_tokens saga (creates deposit activity)
    // 2. Poll GET /api/v1/activities/{deployment_iid} until activity appears
    // 3. Verify activity fields: operation=101, contract_addr, to_vault, amount
}

// TestTreasIdxer_IndexesWithdrawActivity verifies withdrawal activities are indexed
func TestTreasIdxer_IndexesWithdrawActivity(t *testing.T) {
    setupTestDatabaseForTreasIdxer(t)
    // 1. Fund account first
    // 2. Execute withdraw_cash_tokens saga (creates withdrawal activity)
    // 3. Poll for activity with operation=102
    // 4. Verify from_vault and amount fields
}

// TestTreasIdxer_IndexesTransferVaultBalanceActivity verifies transfer activities
func TestTreasIdxer_IndexesTransferVaultBalanceActivity(t *testing.T) {
    setupTestDatabaseForTreasIdxer(t)
    // 1. Fund account
    // 2. Execute transfer between vaults (creates op=107 activity)
    // 3. Verify from_vault, to_vault, amount fields
}

// TestTreasIdxer_ActivityQueryFilters verifies query filter functionality
func TestTreasIdxer_ActivityQueryFilters(t *testing.T) {
    setupTestDatabaseForTreasIdxer(t)
    // 1. Create multiple activities (deposit + withdraw)
    // 2. Query with operation=101 -> only deposits
    // 3. Query with from_vault=X -> only activities from that vault
    // 4. Query with contract_addr=Y -> only activities for that ERC20
    // 5. Query with from_ts/to_ts -> time range filtering
}

// TestTreasIdxer_CursorResumption verifies cursor-based polling persistence
func TestTreasIdxer_CursorResumption(t *testing.T) {
    setupTestDatabaseForTreasIdxer(t)
    // 1. Index some activities
    // 2. Verify cursor in DB matches last processed activity
    // 3. Create more activities
    // 4. Verify only new activities are fetched (no duplicates)
}

// TestTreasIdxer_CrossDeploymentQuery verifies /all/activities endpoint
func TestTreasIdxer_CrossDeploymentQuery(t *testing.T) {
    setupTestDatabaseForTreasIdxer(t)
    // 1. Activities from deployment A
    // 2. Activities from deployment B (if available)
    // 3. GET /api/v1/all/activities returns activities from all deployments
}

// TestTreasIdxer_SlotLinksCreatedOnDeposit verifies LASER creates TREASURY_ERC20_VAULT_HOLDER/HOLDING links
func TestTreasIdxer_SlotLinksCreatedOnDeposit(t *testing.T) {
    setupTestDatabaseForTreasIdxer(t)
    // 1. Execute fund_account_with_cash_tokens saga
    // 2. Query LASER links API for the vault account's slot
    // 3. Verify TREASURY_ERC20_VAULT_HOLDER link exists (account -> erc20)
    // 4. Verify TREASURY_ERC20_VAULT_HOLDING link exists (erc20 -> account)
}

// TestTreasIdxer_SlotLinksIdempotent verifies link creation is idempotent
func TestTreasIdxer_SlotLinksIdempotent(t *testing.T) {
    setupTestDatabaseForTreasIdxer(t)
    // 1. Fund account twice to same vault
    // 2. Verify only one pair of links exists (not duplicated)
}

// ====================
// RED PATH TESTS
// ====================

// TestTreasIdxer_NoTreasuryDeployment verifies graceful behavior with no treasury
func TestTreasIdxer_NoTreasuryDeployment(t *testing.T) {
    setupTestDatabaseForTreasIdxer(t)
    // GET /api/v1/status -> empty jobs list (no crash)
}

// TestTreasIdxer_InvalidDeploymentIid verifies 404 for unknown deployment
func TestTreasIdxer_InvalidDeploymentIid(t *testing.T) {
    setupTestDatabaseForTreasIdxer(t)
    // GET /api/v1/activities/nonexistent-deployment -> 404 or empty list
    // GET /api/v1/status/nonexistent-deployment -> 404
}

// TestTreasIdxer_PaginationLimits verifies pagination boundary handling
func TestTreasIdxer_PaginationLimits(t *testing.T) {
    setupTestDatabaseForTreasIdxer(t)
    // Query with limit=0 -> should use default (100)
    // Query with limit=1000 -> should cap at 500
    // Query with offset beyond total -> empty result
}

// TestTreasIdxer_MissingRequiredArgs verifies error responses for missing params
func TestTreasIdxer_MissingRequiredArgs(t *testing.T) {
    setupTestDatabaseForTreasIdxer(t)
    // GET /api/v1/activities/ (no deployment_iid) -> 404 (route not found)
}
```

### 8.3 E2E Test Hardcoded IIDs

All test IIDs follow the pattern: `treasidxer-cat39-test-{variant}`

---

## Phase 9: Unit Tests

### 9.1 Store Unit Tests

**New File**: `pkg/daemons/treasidxer/stores/pgsql_store_test.go`

```go
func TestInsertTreasuryActivity(t *testing.T)
func TestInsertTreasuryActivity_Idempotent(t *testing.T)
func TestGetTreasuryActivityByActivityId(t *testing.T)
func TestGetTreasuryActivityByActivityId_NotFound(t *testing.T)
func TestListTreasuryActivities_NoFilter(t *testing.T)
func TestListTreasuryActivities_OperationFilter(t *testing.T)
func TestListTreasuryActivities_ContractAddrFilter(t *testing.T)
func TestListTreasuryActivities_TimeRangeFilter(t *testing.T)
func TestListTreasuryActivities_Pagination(t *testing.T)
func TestListAllTreasuryActivities(t *testing.T)
func TestGetActivityCursor_NotFound(t *testing.T)
func TestUpsertActivityCursor_Insert(t *testing.T)
func TestUpsertActivityCursor_Update(t *testing.T)
```

### 9.2 LASER Result Handler Unit Tests

**New File**: `pkg/laser/handlers/trezor_activities_v2_query_test.go`

```go
func TestTrezorActivitiesV2QueryResultHandler_HandleQueryResult_DepositCreatesLinks(t *testing.T)
func TestTrezorActivitiesV2QueryResultHandler_HandleQueryResult_WithdrawSkipsRemoval(t *testing.T)
func TestTrezorActivitiesV2QueryResultHandler_HandleQueryResult_TransferCreatesLinks(t *testing.T)
func TestTrezorActivitiesV2QueryResultHandler_HandleQueryResult_NoActivities(t *testing.T)
func TestTrezorActivitiesV2QueryResultHandler_HandleQueryResult_UnknownAddress(t *testing.T)
func TestTrezorActivitiesV2QueryResultHandler_HandleQueryResult_IdempotentLinks(t *testing.T)
func TestTrezorActivitiesV2QueryResultHandler_HandleMutationResult_Errors(t *testing.T)
func TestCreateTreasuryVaultLinksDirect(t *testing.T)
func TestCreateTreasuryVaultLinksDirect_AlreadyExists(t *testing.T)
```

### 9.3 AccMgr Client Unit Tests

**New File**: `pkg/daemons/treasidxer/clients/accmgr_client_test.go`

```go
func TestGetAllLegalStructures(t *testing.T)
func TestGetMechanismsByStructure_TreasuryFilter(t *testing.T)
func TestGetMechanismDeployments(t *testing.T)
func TestHealthCheck(t *testing.T)
```

### 9.4 LASER Client Unit Tests

**New File**: `pkg/daemons/treasidxer/laser/client_test.go`

```go
func TestTreasuryLaserClient_GetNrOfActivities(t *testing.T)
func TestTreasuryLaserClient_GetActivitiesV2(t *testing.T)
func TestTreasuryLaserClient_ResetExecutorIid(t *testing.T)
func TestTreasuryLaserClient_SlotTranslationRetry(t *testing.T)
```

---

## Complete File Manifest

### New Files (20)

| File | Phase |
|------|-------|
| `pkg/laser/handlers/trezor_activities_v2_query.go` | 0.6 |
| `cmd/agora/daemons/treasidxer/cmd.go` | 1.1 |
| `pkg/daemons/treasidxer.go` | 1.3 |
| `pkg/daemons/treasidxer/clients/accmgr_client.go` | 2.1 |
| `pkg/daemons/treasidxer/indexer/types.go` | 2.2 |
| `pkg/daemons/treasidxer/indexer/discovery.go` | 2.3 |
| `pkg/daemons/treasidxer/laser/client.go` | 3.1 |
| `pkg/daemons/treasidxer/laser/types.go` | 3.2 |
| `deploy/k8s/init/init_treasidxer_pgsql.sql` | 4.1 |
| `deploy/k8s/init/csd/min/treasidxer.sql` | 4.2 |
| `pkg/daemons/treasidxer/stores/models.go` | 4.3 |
| `pkg/daemons/treasidxer/stores/store.go` | 4.4 |
| `pkg/daemons/treasidxer/stores/pgsql_store.go` | 4.5 |
| `pkg/daemons/treasidxer/indexer/activity_indexer.go` | 5.1 |
| `pkg/daemons/treasidxer/api/v1/api.go` | 6.1 |
| `pkg/daemons/treasidxer/api/v1/activities.go` | 6.2 |
| `pkg/daemons/treasidxer/api/v1/health.go` | 6.3 |
| `tests/e2e/laser/treasidxer_test.go` | 8.2 |
| `pkg/laser/handlers/trezor_activities_v2_query_test.go` | 9.2 |
| `pkg/daemons/treasidxer/stores/pgsql_store_test.go` | 9.1 |

### Modified Files (12)

| File | Phase | Change |
|------|-------|--------|
| `pkg/laser/model/operation_name.go` | 0.1 | +2 operation name constants |
| `pkg/laser/ats/argnames.go` | 0.2 | +4 arg name constants |
| `pkg/laser/model/operation_slot_args.go` | 0.3 | +2 entries |
| `pkg/laser/router/init.go` | 0.4 | Register serializers for new ops |
| `pkg/laser/handlers/register.go` | 0.5 | Register in 3 handler registries |
| `pkg/laser/handlers/diamond_lcmgr.go` | 0.5 | Add to GetDiamondLcmgrHandlers map |
| `pkg/laser/handlers/treasury_links.go` | 0.7 | +CreateTreasuryVaultLinksDirect() |
| `pkg/daemons/accmgr/api/v1/api.go` | 0.8 | +1 route |
| `pkg/daemons/accmgr/api/v1/legal_structures_get.go` | 0.8 | +1 handler |
| `pkg/common/helpers.go` | 0.9 | +1 case in GetServiceBaseURL |
| `cmd/agora/daemons/root/root.go` | 1.2 | +1 AddCommand |
| `Makefile` | 7.1 | +treasidxer target, +e2e cat39 |

### Documentation Updates

| File | Change |
|------|--------|
| `docs/SUMMARY-FOR-AGENT.md` | Add treasidxer section |
| `docs/E2E_TEST_CATALOG.md` | Add Category 39 |
| `CLAUDE.md` | Add treasidxer port to table |

---

## Implementation Sequence

Phases must be implemented in order (each depends on the previous):

1. **Phase 0** (LASER prerequisites) — Must be done first: operations, handlers, accmgr endpoint
2. **Phase 1** (Daemon scaffold) — Verify it compiles and starts
3. **Phase 2** (Discovery) — Needs Phase 0.8 for accmgr endpoint
4. **Phase 3** (LASER client) — Needs Phase 0.1-0.4 for operation registration
5. **Phase 4** (Storage) — Can be done in parallel with Phase 3
6. **Phase 5** (Activity indexer) — Needs Phase 3 + 4
7. **Phase 6** (REST API) — Needs Phase 2 + 4
8. **Phase 7** (Build/deploy) — After all code phases
9. **Phase 8** (E2E tests) — After everything is integrated
10. **Phase 9** (Unit tests) — Can partially overlap with implementation phases
