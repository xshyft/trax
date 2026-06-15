# TODO: Treasury ERC20 Vault Slot Links Implementation

> **Status**: COMPLETE
> **Created**: 2026-02-05
> **Updated**: 2026-02-06 - **MAJOR ARCHITECTURE CHANGE**: Links now connect account <-> authorized-instrument (ERC20), NOT account <-> treasury
> **Feature**: TREASURY_ERC20_VAULT_HOLDER / TREASURY_ERC20_VAULT_HOLDING slot links
> **Short ID**: `trevl`
> **Dependencies**: Existing Trezor Diamond operations, LASER slot link system
> **Enables**: cat2 E2E tests (TestTRAXSimpleTransferWithTreasuryTracking, etc.)

---

## Overview

Implement slot links for Treasury (Trezor) ERC20 vault operations to track which accounts have non-zero balances in treasury vaults. Links are created/removed based on **stash-1 (TOTAL)** balance after each Trezor operation.

**PRIMARY PURPOSE**: Enable treassvc to discover and track account holdings. The slot links allow treassvc to:
1. Query which accounts hold a specific authorized-instrument in treasury (via TREASURY_ERC20_VAULT_HOLDING links from authorized-instrument slot)
2. Query which authorized-instruments an account holds in treasury (via TREASURY_ERC20_VAULT_HOLDER links from account slot)
3. Provide accurate holdings data for the `/accounts/:iid/holdings` API endpoint

**Without these slot links**, the cat2 tests fail because treassvc cannot discover which accounts hold tokens.

**CRITICAL ARCHITECTURE (2026-02-06 Update):**

**Links are between ACCOUNT and ISSUED-INSTRUMENT (ERC20 token), NOT between account and treasury!**

The treasury is discovered by treassvc through the legal structure -> mechanisms chain:
1. treassvc receives authorized-instrument IID
2. Looks up `LegalStructureToAuthorizedInstrumentRelation` to find the legal structure
3. Queries `LegalMechanisms` for this legal structure with type `TREASURY`
4. Uses the treasury contract address from the mechanism metadata

This mirrors how ERC20 HOLDER/HOLDING links work (account <-> contract).

**Key Design Decisions:**
1. **Links are account <-> authorized-instrument** - NOT account <-> treasury. Treasury is found via legal structure chain.
2. **Two pairs of links (E1 + E2)** - Just like ERC20 operations, links are created in BOTH E2 (lcmgr, eth addresses) AND E1 (relay, IIDs/seeds)
3. **Per ERC20 token granularity** - Each link includes the ERC20 contract address in metadata
4. **Balance passed via lcmgr metadata** - The result handler receives balance info via metadata returned by lcmgr mutations (not via synchronous query)

---

## Part 1: Add New Slot Link Types

### File: `pkg/laser/model/slot_link_type.go`

**STATUS: DONE**

Added two new constants:

```go
// SlotLinkTypeEnum_TreasuryErc20VaultHolder links an account slot to a treasury slot
// Created when an account has non-zero balance in stash-1 (TOTAL) at a treasury for a specific ERC20 token.
// Direction: account -> treasury. Used for querying "which treasuries does this account participate in?"
// Metadata includes erc20_address to distinguish different tokens in the same treasury.
SlotLinkTypeEnum_TreasuryErc20VaultHolder SlotLinkTypeEnum = "SLOT_LINK_TYPE_ENUM_TREASURY_ERC20_VAULT_HOLDER"

// SlotLinkTypeEnum_TreasuryErc20VaultHolding links a treasury slot to an account slot
// Reverse direction for discovery: "what accounts hold tokens in this treasury?"
// Direction: treasury -> account. Created alongside TREASURY_ERC20_VAULT_HOLDER links.
// Metadata includes erc20_address to distinguish different tokens in the same treasury.
SlotLinkTypeEnum_TreasuryErc20VaultHolding SlotLinkTypeEnum = "SLOT_LINK_TYPE_ENUM_TREASURY_ERC20_VAULT_HOLDING"
```

---

## Part 2: Treasury Link Helper Functions

### New File: `pkg/laser/handlers/treasury_links.go`

**STATUS: DONE (Updated 2026-02-06 for account <-> authorized-instrument architecture)**

Created functions following the pattern from `erc20_links.go`:

```go
package handlers

// CreateTreasuryVaultLink creates a single slot link for Treasury vault operations.
// Uses the Future's SlotAddressToIidMap to resolve slot IIDs.
//
// IMPORTANT: Links are between ACCOUNT and ISSUED-INSTRUMENT (ERC20 token), NOT treasury.
// This mirrors how ERC20 links work (account <-> contract).
func CreateTreasuryVaultLink(
    ctx context.Context,
    laserStore model.LaserStore,
    future *model.Future,
    fromAddress, toAddress string,
    linkType model.SlotLinkTypeEnum,
    erc20Addr string,
    fromLabel, toLabel string,
) error

// CreateTreasuryVaultLinks creates bidirectional links between an account and authorized-instrument (ERC20 token).
// Creates both TREASURY_ERC20_VAULT_HOLDER (account -> erc20) and TREASURY_ERC20_VAULT_HOLDING (erc20 -> account).
//
// IMPORTANT: Links are between ACCOUNT and ISSUED-INSTRUMENT (ERC20 token), NOT treasury.
// Treasury is discovered by treassvc through the legal structure -> mechanisms chain.
func CreateTreasuryVaultLinks(
    ctx context.Context,
    laserStore model.LaserStore,
    future *model.Future,
    accountAddr, erc20Addr string,  // NOTE: No longer takes treasuryAddr
) error

// RemoveTreasuryVaultLinks removes both HOLDER and HOLDING links for a specific ERC20.
// Called when account's TOTAL stash balance becomes zero.
func RemoveTreasuryVaultLinks(
    ctx context.Context,
    laserStore model.LaserStore,
    future *model.Future,
    accountAddr, erc20Addr string,  // NOTE: No longer takes treasuryAddr
) error

// ... other helper functions unchanged
```

**Link Metadata:**
```go
Metadata: map[string]string{
    "from_address":  accountAddr,
    "to_address":    erc20Addr,     // Now points to ERC20, not treasury
    "erc20_address": erc20Addr,
    "ledger_id":     "1",
}
```

---

## Part 3: Trezor-Specific Result Handlers (E2 and E1)

### Two-Layer Link Creation (Mirrors ERC20 Pattern)

**CRITICAL (2026-02-06 Update):** Treasury vault links are now created in BOTH executor layers, just like ERC20 operations:

1. **E2 (lcmgr handler)**: Creates links using Ethereum addresses
2. **E1 (relay handler)**: Creates links using IIDs (seeds)

This ensures treassvc can query holdings using IIDs.

### E2 Handler: `pkg/laser/handlers/diamond_lcmgr.go`

**STATUS: DONE (Updated 2026-02-06)**

`TrezorMutationLcmgrResultHandler` creates links in E2 using Ethereum addresses:

```go
// TrezorMutationLcmgrResultHandler handles Trezor vault mutation results and manages slot links.
// After each balance-affecting operation, it reads the TOTAL stash balance from lcmgr metadata and:
// - Creates HOLDER/HOLDING links if balance > 0 and links don't exist
// - Removes HOLDER/HOLDING links if balance == 0
//
// IMPORTANT: Links are between ACCOUNT and ISSUED-INSTRUMENT (ERC20 token), NOT treasury.
type TrezorMutationLcmgrResultHandler struct{}

// manageVaultLinks creates or removes slot links based on vault's TOTAL balance
// Links are between account and authorized-instrument (erc20), NOT treasury
func (h *TrezorMutationLcmgrResultHandler) manageVaultLinks(
    ctx context.Context,
    laserStore model.LaserStore,
    future *model.Future,
    vaultAddr, treasuryAddr, erc20Addr, totalBalance string,
) error {
    // If balance == "0": RemoveTreasuryVaultLinks(ctx, laserStore, future, vaultAddr, erc20Addr)
    // If balance > 0: CreateTreasuryVaultLinks(ctx, laserStore, future, vaultAddr, erc20Addr)
}
```

### E1 Handler: `pkg/laser/handlers/trezor_relay.go` (NEW FILE)

**STATUS: DONE (Added 2026-02-06)**

`TrezorMutationRelayResultHandler` creates links in E1 using IIDs (seeds):

```go
// TrezorMutationRelayResultHandler handles Trezor vault mutation relay results
// and creates treasury vault slot links in E1 using IIDs (seeds).
//
// This mirrors how ERC20 relay handlers work:
// - E2 (lcmgr): Creates links using eth addresses
// - E1 (relay): Creates links using IIDs (seeds)
//
// Links are between ACCOUNT and ISSUED-INSTRUMENT (ERC20 token), NOT treasury.
type TrezorMutationRelayResultHandler struct{}
```

**Registered for balance-affecting operations in `register.go`:**
```go
trezorMutationRelayHandler := &TrezorMutationRelayResultHandler{}
trezorBalanceAffectingOperations := []model.OperationNameEnum{
    model.OperationNameEnum_TrezorErc20DepositToVault,
    model.OperationNameEnum_TrezorErc20WithdrawFromVault,
    model.OperationNameEnum_TrezorErc20TransferFromVault,
    model.OperationNameEnum_TrezorErc20TransferVaultBalance,
}
for _, opName := range trezorBalanceAffectingOperations {
    executors.RegisterRelayResultHandler(model.ActionTypeEnum_Relay, opName, trezorMutationRelayHandler)
}
```

**Operations handled (same list for both E1 and E2):**
- `TrezorErc20DepositToVault` - affects `to_vault` balance
- `TrezorErc20WithdrawFromVault` - affects `from_vault` balance
- `TrezorErc20TransferFromVault` - affects both `from_vault` and `to_vault`
- `TrezorErc20TransferVaultBalance` - affects both vaults (cross-stash)

---

## Part 4: lcmgr Balance Metadata for Slot Link Management

### Modify File: `pkg/daemons/lcmgr/trezor_erc20_contract.go`

**STATUS: DONE**

Updated 4 mutation functions to return balance metadata for result handler:

**mutationDepositToVault** (around line 347-360):
```go
// Query TOTAL stash balance after deposit for result handler to use for slot link management
toVaultTotalBalance, err := c.store.GetVaultBalance(ctx, c.contractAddress, ledgerID, erc20, toVault, ethereum.STASH_TOTAL)
if err != nil {
    return nil, nil, fmt.Errorf("failed to query to_vault TOTAL balance: %w", err)
}

mutationResp := &model.FutureResult{
    Metadata: map[string]string{
        "to_vault":                    toVault,
        "to_vault_total_balance":     toVaultTotalBalance,
        "erc20_address":              erc20,
        "treasury_contract_address":  c.contractAddress,
    },
}
```

**mutationWithdrawFromVault** (around line 470-485):
```go
// Query TOTAL stash balance after withdraw for result handler to use for slot link management
fromVaultTotalBalance, err := c.store.GetVaultBalance(ctx, c.contractAddress, ledgerID, erc20, fromVault, ethereum.STASH_TOTAL)
if err != nil {
    return nil, nil, fmt.Errorf("failed to query from_vault TOTAL balance: %w", err)
}

mutationResp := &model.FutureResult{
    Metadata: map[string]string{
        "from_vault":                   fromVault,
        "from_vault_total_balance":    fromVaultTotalBalance,
        "erc20_address":               erc20,
        "treasury_contract_address":   c.contractAddress,
    },
}
```

**mutationTransferFromVault** (around line 595-616):
```go
// Query TOTAL stash balances after transfer for result handler to use for slot link management
fromVaultTotalBalance, err := c.store.GetVaultBalance(ctx, c.contractAddress, ledgerID, erc20, fromVault, ethereum.STASH_TOTAL)
toVaultTotalBalance, err := c.store.GetVaultBalance(ctx, c.contractAddress, ledgerID, erc20, toVault, ethereum.STASH_TOTAL)

mutationResp := &model.FutureResult{
    Metadata: map[string]string{
        "from_vault":                   fromVault,
        "from_vault_total_balance":    fromVaultTotalBalance,
        "to_vault":                     toVault,
        "to_vault_total_balance":      toVaultTotalBalance,
        "erc20_address":               erc20,
        "treasury_contract_address":   c.contractAddress,
    },
}
```

**mutationTransferVaultBalance** (around line 759-787):
```go
// Query TOTAL stash balances after transfer for result handler to use for slot link management
// TransferVaultBalance can affect one or two vaults depending on whether fromVault == toVault
fromVaultTotalBalance, err := c.store.GetVaultBalance(ctx, c.contractAddress, ledgerID, erc20, fromVault, ethereum.STASH_TOTAL)

metadata := map[string]string{
    "from_vault":                   fromVault,
    "from_vault_total_balance":    fromVaultTotalBalance,
    "erc20_address":               erc20,
    "treasury_contract_address":   c.contractAddress,
}

// If fromVault != toVault, include to_vault balance as well
if fromVault != toVault {
    toVaultTotalBalance, err := c.store.GetVaultBalance(ctx, c.contractAddress, ledgerID, erc20, toVault, ethereum.STASH_TOTAL)
    metadata["to_vault"] = toVault
    metadata["to_vault_total_balance"] = toVaultTotalBalance
}

mutationResp := &model.FutureResult{
    Metadata: metadata,
}
```

---

## Part 5: Operation Slot Args Fix

### Modify File: `pkg/laser/model/operation_slot_args.go`

**STATUS: DONE**

Fixed slot args for proper translation:

```go
// TrezorERC20 operations
OperationNameEnum_TrezorErc20DepositToVault:       {ats.ArgNameEnum_Caller, ats.ArgNameEnum_Erc20Addr, ats.ArgNameEnum_FromAccount, ats.ArgNameEnum_ToVault},
OperationNameEnum_TrezorErc20WithdrawFromVault:    {ats.ArgNameEnum_Caller, ats.ArgNameEnum_Erc20Addr, ats.ArgNameEnum_FromVault, ats.ArgNameEnum_ToAccount},
OperationNameEnum_TrezorErc20TransferFromVault:    {ats.ArgNameEnum_Caller, ats.ArgNameEnum_Erc20Addr, ats.ArgNameEnum_FromVault, ats.ArgNameEnum_ToVault},  // FIXED: Was ToAccount
OperationNameEnum_TrezorErc20TransferVaultBalance: {ats.ArgNameEnum_Caller, ats.ArgNameEnum_Erc20Addr, ats.ArgNameEnum_FromVault, ats.ArgNameEnum_ToVault},  // FIXED: Added FromVault, ToVault
OperationNameEnum_TrezorErc20SetStashLabel:        {ats.ArgNameEnum_Vault, ats.ArgNameEnum_Erc20Addr},
OperationNameEnum_TrezorErc20GetVaultBalance:      {ats.ArgNameEnum_Vault, ats.ArgNameEnum_Erc20Addr},
OperationNameEnum_TrezorErc20GetTracedErc20s:      {},
OperationNameEnum_TrezorErc20GetTracedStashes:     {ats.ArgNameEnum_Erc20Addr},
OperationNameEnum_TrezorErc20GetStashLabel:        {ats.ArgNameEnum_Vault, ats.ArgNameEnum_Erc20Addr},
```

---

## Part 6: Crown Links Query API with Metadata

### Modify File: `pkg/daemons/lasersvc/api/v1/types.go`

**STATUS: DONE**

Extended crown links query request and response:

```go
// CrownLinksQueryRequest is the request for querying slot links
type CrownLinksQueryRequest struct {
    SlotAddresses  []string `json:"slot_addresses" binding:"required"`
    LinkType       string   `json:"link_type,omitempty"`       // e.g., "ERC20_HOLDER", "TREASURY_ERC20_VAULT_HOLDER"
    IncludeDetails bool     `json:"include_details,omitempty"` // If true, return full link details including metadata
}

// CrownLinkDetail represents detailed information about a slot link including metadata
type CrownLinkDetail struct {
    LinkIid      string            `json:"link_iid"`
    LinkedSlot   string            `json:"linked_slot"`   // The address of the other slot in the link
    LinkType     string            `json:"link_type"`     // The type of the link
    Metadata     map[string]string `json:"metadata"`      // Link metadata (e.g., erc20_address for treasury vault links)
    Slot1Iid     string            `json:"slot1_iid"`     // The IID of slot1 in the link
    Slot2Iid     string            `json:"slot2_iid"`     // The IID of slot2 in the link
    Slot1Address string            `json:"slot1_address"` // The address of slot1
    Slot2Address string            `json:"slot2_address"` // The address of slot2
}

// CrownLinkQueryResult represents links for a single slot address
type CrownLinkQueryResult struct {
    SlotAddress string            `json:"slot_address"`
    LinkedSlots []string          `json:"linked_slots"`            // Basic list of linked slot addresses
    LinkDetails []CrownLinkDetail `json:"link_details,omitempty"`  // Detailed link info (only if include_details=true)
    Error       string            `json:"error,omitempty"`
}
```

### Modify File: `pkg/daemons/lasersvc/api/v1/executors_crown_links_query_post.go`

**STATUS: DONE**

Added `queryLinkedSlotAddressesWithDetails()` function:

```go
// queryLinkedSlotAddressesWithDetails finds all linked slot addresses with full link details
// including metadata. Used for treasury vault links where metadata contains erc20_address.
func queryLinkedSlotAddressesWithDetails(ctx context.Context, slotAddress string, linkType string) (CrownLinkQueryResult, error) {
    // 1. Get the slot by address
    // 2. Get all active links for this slot
    // 3. Cache slot lookups for efficiency
    // 4. For each link:
    //    - Get both slot addresses
    //    - Include full metadata
    //    - Build CrownLinkDetail
    // 5. Return result with both LinkedSlots and LinkDetails
}
```

---

## Part 7: treassvc Treasury Holdings Query

### Modify File: `pkg/daemons/treassvc/hold_source_impl.go`

**STATUS: DONE**

Added treasury vault holdings query infrastructure:

```go
// TreasuryVaultHolding represents a holding in a treasury vault for a specific ERC20
type TreasuryVaultHolding struct {
    TreasuryContractAddr string
    Erc20ContractAddr    string
    LiquidBalance        string // stash-0
    TotalBalance         string // stash-1
}

// queryTreasuryVaultHoldings queries treasury vault holdings for an account via TREASURY_ERC20_VAULT_HOLDER links.
// Returns treasury vault holdings with stash-level breakdown (LIQUID and TOTAL).
func (h *HoldSourceImpl) queryTreasuryVaultHoldings(
    ctx context.Context,
    accountSlotAddress string,
    crownExecutorIid string,
) ([]TreasuryVaultHolding, error) {
    // 1. Query TREASURY_ERC20_VAULT_HOLDER links with include_details: true
    // 2. Parse response with link details
    // 3. For each link:
    //    - Extract treasury_contract_address and erc20_address from metadata
    //    - Query TOTAL balance (stash=1) using TrezorErc20GetVaultBalance
    //    - Query LIQUID balance (stash=0) using TrezorErc20GetVaultBalance
    // 4. Return holdings with stash breakdown
}

// queryTrezorVaultBalance queries the balance for a specific vault/stash using LASER
func (h *HoldSourceImpl) queryTrezorVaultBalance(
    ctx context.Context,
    crownExecutorIid string,
    treasuryAddr string,
    erc20Addr string,
    vaultAddr string,
    stash int,
) (string, error) {
    // Build TrezorErc20GetVaultBalance call data
    // ledger_id is always 1 (DEFAULT ledger)
    // Execute query via LASER
    // Parse and return balance
}
```

---

## Part 8: Distributed Mutex Protection

### Existing Implementation - Already Correct

The `fund_account_with_cash_tokens` saga already implements the correct mutex pattern:

**File**: `pkg/daemons/treassvc/trax/executors/fund_account_with_cash_tokens/query_source_vault_balance.go`
- Lock key: `treasury_transfer:{execRuntimeName}:{treasurySlotAddr}:{erc20ContractAddr}`
- TTL: 300 seconds
- Timeout: 120 seconds

### Mutex Pattern for Direct LASER API Calls

For any code that directly calls LASER Trezor operations (not through TRAX saga), add mutex protection:

**Pattern for single-call operations:**
```go
// Key pattern for ANY balance-affecting operation
func BuildBalanceOperationLockKey(execRuntimeName, contractAddr, accountAddr string) string {
    return fmt.Sprintf("balance_op:%s:%s:%s", execRuntimeName, contractAddr, accountAddr)
}

// Usage in direct LASER call (non-saga context):
lockKey := BuildBalanceOperationLockKey(execRuntimeName, treasuryAddr, vaultAddr)
err := cache.Mutex(ctx, lockKey, 60, 30, func() {
    // Execute LASER Trezor operation
})
```

**Ensure all these operations are protected:**
- ERC20 Transfer, TransferFrom, Mint, Burn
- Trezor DepositToVault, WithdrawFromVault, TransferFromVault, TransferVaultBalance

---

## Part 9: treassvc API Endpoint for Treasury Balances

### New File: `pkg/daemons/treassvc/api/v1/authorized_instruments_treasury_balances_get.go`

**STATUS: DONE**

Add new endpoint to return treasury balances for an authorized instrument:

```go
// GET /api/v1/authorized-instruments/:iid/treasury-balances
// Returns treasury vault balances for all accounts holding this instrument

type TreasuryBalanceResponse struct {
    AuthorizedInstrumentIid   string                `json:"authorized_instrument_iid"`
    TreasuryContractAddr  string                `json:"treasury_contract_address"`
    Erc20ContractAddr     string                `json:"erc20_contract_address"`
    LedgerId              int                   `json:"ledger_id"`
    Balances              []AccountVaultBalance `json:"balances"`
}

type AccountVaultBalance struct {
    AccountIid      string `json:"account_iid"`
    VaultAddress    string `json:"vault_address"`
    LiquidBalance   string `json:"liquid_balance"`   // stash=0
    TotalBalance    string `json:"total_balance"`    // stash=1
}
```

### Modify File: `pkg/daemons/treassvc/api/v1/api.go`

**STATUS: DONE**

Register the new endpoint:
```go
r.GET(ApiV1UriPrefix+"/authorized-instruments/:iid/treasury-balances", getAuthorizedInstrumentTreasuryBalances)
```

### Modify File: `pkg/daemons/treassvc/hold_source.go`

**STATUS: DONE**

Add new interface method:
```go
type HoldSource interface {
    // Existing methods...

    // QueryTreasuryBalancesByAuthorizedInstrument returns treasury vault balances
    // The treasury is found from entity relations of the authorized-instrument record
    // with TREASURY mechanism in the same legal structure
    QueryTreasuryBalancesByAuthorizedInstrument(
        ctx context.Context,
        authorizedInstrumentIid string,
    ) (*TreasuryBalanceResponse, error)
}
```

### Implement in: `pkg/daemons/treassvc/hold_source_impl.go`

**STATUS: DONE**

Algorithm to find treasury:
1. Get authorized instrument by IID from instrmgr
2. Query `LegalStructureToAuthorizedInstrumentRelation` to find `legal_structure_iid`
3. Query `LegalMechanisms` for this legal structure with type `TREASURY`
4. Get treasury contract address from mechanism metadata
5. Query LASER for vault balances using slot links (TREASURY_ERC20_VAULT_HOLDING)
6. For each linked account, query on-chain balance via `TrezorErc20GetVaultBalance`

---

## Part 10: E2E Tests (ethbc mode)

### New File: `tests/e2e/laser/treasury_vault_links_test.go`

**STATUS: DONE**

**Green Path Tests:**

1. `TestTreasuryVaultLinks_DepositCreatesLinks`
   - Setup: Deploy treasury, deploy ERC20, fund account
   - Action: Deposit ERC20 to vault
   - Assert: HOLDER and HOLDING links exist with correct metadata

2. `TestTreasuryVaultLinks_WithdrawRemovesLinksOnZero`
   - Setup: Deposit tokens to vault
   - Action: Withdraw ALL tokens from vault
   - Assert: Links are removed (TOTAL balance = 0)

3. `TestTreasuryVaultLinks_TransferCreatesAndRemovesLinks`
   - Setup: Deposit to vault A
   - Action: Transfer from vault A to vault B (all tokens)
   - Assert: Links for A removed, links for B created

4. `TestTreasuryVaultLinks_MultipleERC20sSeparateLinks`
   - Setup: Deposit USD and EUR to same vault
   - Action: Query links
   - Assert: 4 separate links (2 per token), each with correct erc20_address

5. `TestTreasuryVaultLinks_PartialWithdrawKeepsLinks`
   - Setup: Deposit 1000 tokens
   - Action: Withdraw 500 tokens
   - Assert: Links still exist (balance > 0)

**Red Path Tests:**

6. `TestTreasuryVaultLinks_NoLinksForZeroDeposit`
   - Setup: Treasury deployed
   - Action: Attempt deposit of 0 tokens (should fail on-chain)
   - Assert: No links created

### Category: E2E_CAT11 (Deposit & Treasury)

**STATUS: DONE**

Makefile updated:
```makefile
E2E_CAT11_PATTERN := ... |TestTreasuryVaultLinks
```

---

## Implementation Phases

### Phase 1: Core Slot Link Types and Helpers (Est: ~200 lines)
- [x] 1.1 Add new SlotLinkTypeEnum constants to `slot_link_type.go`
- [x] 1.2 Create `treasury_links.go` with CreateTreasuryVaultLinks, RemoveTreasuryVaultLinks

### Phase 2: Trezor Result Handler (Est: ~300 lines)
- [x] 2.1 Create TrezorMutationLcmgrResultHandler in `diamond_lcmgr.go`
- [x] 2.2 Implement balance metadata in lcmgr mutations
- [x] 2.3 Implement link creation/removal logic based on balance
- [x] 2.4 Update handler registration in `GetDiamondLcmgrHandlers()`

### Phase 3: Operation Slot Args Fix (Est: ~10 lines)
- [x] 3.1 Fix TrezorErc20TransferFromVault slot args
- [x] 3.2 Fix TrezorErc20TransferVaultBalance slot args

### Phase 4: Crown Links Query API (Est: ~100 lines)
- [x] 4.1 Add CrownLinkDetail struct to types.go
- [x] 4.2 Add include_details support to crown links query
- [x] 4.3 Implement queryLinkedSlotAddressesWithDetails

### Phase 5: treassvc Holdings Query (Est: ~200 lines)
- [x] 5.1 Add TreasuryVaultHolding struct
- [x] 5.2 Implement queryTreasuryVaultHoldings
- [x] 5.3 Implement queryTrezorVaultBalance

### Phase 6: treassvc API Endpoint (Est: ~250 lines)
- [x] 6.1 Add new endpoint `GET /api/v1/authorized-instruments/:iid/treasury-balances`
- [x] 6.2 Implement HoldSource.QueryTreasuryBalancesByAuthorizedInstrument
- [x] 6.3 Implement treasury discovery from legal structure relations

### Phase 7: E2E Tests (Est: ~500 lines)
- [x] 7.1 Create `treasury_vault_links_test.go`
- [x] 7.2 Implement 6 test cases (5 green, 1 red path)
- [x] 7.3 Update Makefile E2E_CAT11_PATTERN

### Phase 8: Documentation (Est: ~100 lines)
- [x] 8.1 Create `docs/TODO_TREASURY_VAULT_SLOT_LINKS.md`

---

## Files Summary

### New Files
| File | Purpose | Est. Lines | Status |
|------|---------|------------|--------|
| `pkg/laser/handlers/treasury_links.go` | Treasury link helper functions | ~280 | DONE |
| `pkg/daemons/treassvc/api/v1/authorized_instruments_treasury_balances_get.go` | API endpoint | ~200 | DONE |
| `tests/e2e/laser/treasury_vault_links_test.go` | E2E tests | ~500 | DONE |
| `docs/TODO_TREASURY_VAULT_SLOT_LINKS.md` | This documentation | ~600 | DONE |

### Modified Files
| File | Changes | Status |
|------|---------|--------|
| `pkg/laser/model/slot_link_type.go` | Add 2 new constants | DONE |
| `pkg/laser/handlers/diamond_lcmgr.go` | Add TrezorMutationLcmgrResultHandler (~150 lines) | DONE |
| `pkg/daemons/lcmgr/trezor_erc20_contract.go` | Add balance metadata to 4 mutations (~80 lines) | DONE |
| `pkg/laser/model/operation_slot_args.go` | Fix 2 Trezor slot args | DONE |
| `pkg/daemons/lasersvc/api/v1/types.go` | Add CrownLinkDetail struct (~25 lines) | DONE |
| `pkg/daemons/lasersvc/api/v1/executors_crown_links_query_post.go` | Add include_details support (~100 lines) | DONE |
| `pkg/daemons/treassvc/hold_source_impl.go` | Add treasury vault holdings query (~220 lines) | DONE |
| `pkg/daemons/treassvc/api/v1/api.go` | Register new endpoint | DONE |
| `pkg/daemons/treassvc/hold_source.go` | Add interface method | DONE |
| `Makefile` | Update E2E_CAT11_PATTERN | DONE |

---

## Verification Steps

### Unit Tests
```bash
make test
```

### Build Verification
```bash
go build ./pkg/...
```

### E2E Tests (ethbc mode)
```bash
# Start environment
make laser-e2e-up

# PRIMARY SUCCESS CRITERIA: Run cat2 tests (these should pass after implementation)
make laser-e2e-ethbc-cat2

# Key tests that validate this feature:
# - TestTRAXSimpleTransferWithTreasuryTracking (verifies treassvc tracks transfers)
# - TestTRAXSecurityHoldersConfirmation (verifies all holders discovered)
# - TestTRAXTransferLinkManagement (verifies slot links created/removed)
# - TestTRAXTransferZeroBalanceLinkCleanup (verifies link removal on zero balance)

# Run treasury vault link tests
TEST_RUN_PATTERN="TestTreasuryVaultLinks" make laser-e2e-ethbc-cat11

# Full category 11 tests
make laser-e2e-ethbc-cat11
```

### Manual Verification
1. Deploy a legal structure with treasury mechanism
2. Deposit tokens to a vault via fund_account saga
3. Query slot links: `lasercli slot-links list --slot-iid=<vault-slot-iid>`
4. Verify HOLDER/HOLDING links exist with correct metadata
5. Call treassvc API: `curl /api/v1/authorized-instruments/{iid}/treasury-balances`
6. Withdraw all tokens from vault
7. Verify links are removed

---

## Critical Notes

1. **ledger_id is always 1** - The DEFAULT ledger created during treasury deployment
2. **Per-ERC20 granularity** - Each link includes `erc20_address` in metadata to support multiple tokens per treasury
3. **Stash-1 (TOTAL)** is the authoritative balance - It auto-calculates from all non-TOTAL stashes
4. **Balance passed via metadata** - Result handler reads balance from lcmgr mutation response metadata (not via separate query)
5. **No database migration needed** - Slot links use string enums, no schema changes required
6. **Link removal is permanent** - Links are deleted (not deactivated) when balance reaches zero

---

## Dependencies

- Existing Trezor Diamond deployment sagas
- LASER slot link infrastructure
- treassvc daemon and hold_source interface

---

## See Also

- [TODO_FUND_ACCOUNT_WITH_CASH_TOKENS.md](TODO_FUND_ACCOUNT_WITH_CASH_TOKENS.md) - Treasury operations
- [TODO_DEPLOY_TREASURY_LEGAL_MECHANISMS_SAGA.md](TODO_DEPLOY_TREASURY_LEGAL_MECHANISMS_SAGA.md) - Treasury deployment
- [DISTRIBUTED_REDIS_LOCK.md](DISTRIBUTED_REDIS_LOCK.md) - Mutex patterns
- [SUMMARY-FOR-AGENT.md](SUMMARY-FOR-AGENT.md) - Codebase overview
