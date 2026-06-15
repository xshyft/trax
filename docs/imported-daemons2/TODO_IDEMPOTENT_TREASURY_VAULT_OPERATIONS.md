# TODO: Idempotent Treasury Vault Operations — Erc20VaultIdempFacet Integration

> **Status**: COMPLETE (Phase 13: DONE — both facets kept; Phase 12: deferred)
> **Created**: 2026-03-09
> **Feature**: Protect treasury vault mutations against double-execution via idempotent LASER operations
> **Short ID**: `ITVOP`
> **Dependencies**: Lattice archive containing `Erc20VaultIdempFacet` Go binding, existing treasury mechanism deployment saga
> **Enables**: Safe saga-step retries for vault deposit/withdraw/transfer; future AgoraEngine event deduplication (rev-21)
> **Related Docs**: `TODO_DEPLOY_TREASURY_LEGAL_MECHANISMS_SAGA.md`, `TODO_TREASURY_VAULT_SLOT_LINKS.md`, `TODO_FUND_ACCOUNT_WITH_CASH_TOKENS.md`, `TODO_CREATE_INVESTOR_ORDER_SAGA.md`

---

## Overview

Treasury vault mutations (deposit, withdraw, transfer, transferBalance) are currently **not** protected against double-execution. If a TRAX saga step retries (e.g., due to transient failure, timeout, or coordinator restart), the same vault mutation can execute twice on-chain, causing incorrect balances and corrupted treasury state.

The `Erc20VaultIdempFacet` Solidity contract and its Go binding already exist in the Lattice framework. This facet provides idempotent variants of all 4 vault mutation functions, each taking a `bytes32 idempotencyKey` as the first parameter. On-chain, the facet checks if the idempotency key has been used before; if so, it is a no-op. If not, it executes the operation and marks the key as used.

**Approach**:
1. Add 4 **new** LASER operation names for idempotent vault mutations
2. **Disable** (not remove) the old 4 non-idempotent operations — calls to them return an error with a clear message
3. Add `Erc20VaultIdempFacet` to the treasury Diamond deployment (8th vault facet)
4. Implement idempotent mutation methods in lcmgr (EthBC and RDBMS modes)
5. Switch all saga callers to use the new idempotent operations

**Future (Rev-21)**: Lattice rev-21 will add a `Hash` field to AgoraEngine events (similar to `TrezorActivity.IdempotencyKey`), enabling event-processing deduplication in tradeidxer.

---

## Prerequisites

1. `Erc20VaultIdempFacet` Go binding exists at:
   `contracts/go/contracts/facets/_trezor/erc20-vault/erc20vaultidempfacet/Erc20VaultIdempFacet.go`
2. Lattice archive contains the Erc20VaultIdempFacet contract (deployed by `deploy_lattice_facets` saga)
3. `idempotencyKeyToBytes32(key string) [32]byte` already exists in `pkg/daemons/lcmgr/ethbc_executor_erc20_contract.go:226`
4. `req.IdempotencyKey` is always populated on `MutationRequest` (mandatory field in LASER protocol)
5. Existing treasury deployment saga works (18-step saga, COMPLETE status)

---

## Phase 1: New LASER Operation Definitions

### 1.1 Add 4 new OperationNameEnum values

**File**: `pkg/laser/model/operation_name.go` (EXISTING)

After line 46 (`OperationNameEnum_TrezorErc20TransferVaultBalance`), add a new section:

```go
// TREZOR_ERC20 idempotent vault operations
// These are the idempotent equivalents of the non-idempotent vault operations above.
// Each takes an additional idempotencyKey parameter that prevents double-execution.
// The non-idempotent variants (above) are DISABLED — calls to them return an error.
OperationNameEnum_TrezorErc20IdempDepositToVault       OperationNameEnum = "OPERATION_NAME_ENUM_TREZOR_ERC20_IDEMP_DEPOSIT_TO_VAULT"
OperationNameEnum_TrezorErc20IdempWithdrawFromVault    OperationNameEnum = "OPERATION_NAME_ENUM_TREZOR_ERC20_IDEMP_WITHDRAW_FROM_VAULT"
OperationNameEnum_TrezorErc20IdempTransferFromVault    OperationNameEnum = "OPERATION_NAME_ENUM_TREZOR_ERC20_IDEMP_TRANSFER_FROM_VAULT"
OperationNameEnum_TrezorErc20IdempTransferVaultBalance OperationNameEnum = "OPERATION_NAME_ENUM_TREZOR_ERC20_IDEMP_TRANSFER_VAULT_BALANCE"
```

- [x] 1.1.1 Mark the old 4 operations with a comment: `// DISABLED — use Idemp variant instead`

---

### 1.2 Add slot args for new operations

**File**: `pkg/laser/model/operation_slot_args.go` (EXISTING)

After line 39 (`OperationNameEnum_TrezorErc20TransferVaultBalance`), add:

```go
// Idempotent TrezorERC20 operations (same slot args as non-idempotent variants)
OperationNameEnum_TrezorErc20IdempDepositToVault:       {ats.ArgNameEnum_Caller, ats.ArgNameEnum_Erc20Addr, ats.ArgNameEnum_FromAccount, ats.ArgNameEnum_ToVault},
OperationNameEnum_TrezorErc20IdempWithdrawFromVault:    {ats.ArgNameEnum_Caller, ats.ArgNameEnum_Erc20Addr, ats.ArgNameEnum_FromVault, ats.ArgNameEnum_ToAccount},
OperationNameEnum_TrezorErc20IdempTransferFromVault:    {ats.ArgNameEnum_Caller, ats.ArgNameEnum_Erc20Addr, ats.ArgNameEnum_FromVault, ats.ArgNameEnum_ToVault},
OperationNameEnum_TrezorErc20IdempTransferVaultBalance: {ats.ArgNameEnum_Caller, ats.ArgNameEnum_Erc20Addr, ats.ArgNameEnum_FromVault, ats.ArgNameEnum_ToVault},
```

The slot args are **identical** to the non-idempotent variants — the `idempotencyKey` is NOT a slot address and is derived from `req.IdempotencyKey` internally.

---

### 1.3 Register serializers for new operations

**File**: `pkg/laser/router/init.go` (EXISTING, ~line 344-356)

Add the 4 new operations to the `trezorErc20VaultMutationOps` slice:

```go
trezorErc20VaultMutationOps := []model.OperationNameEnum{
    model.OperationNameEnum_TrezorErc20DepositToVault,       // DISABLED but still registered for error handling
    model.OperationNameEnum_TrezorErc20WithdrawFromVault,    // DISABLED
    model.OperationNameEnum_TrezorErc20TransferFromVault,    // DISABLED
    model.OperationNameEnum_TrezorErc20TransferVaultBalance, // DISABLED
    // Idempotent variants (active)
    model.OperationNameEnum_TrezorErc20IdempDepositToVault,
    model.OperationNameEnum_TrezorErc20IdempWithdrawFromVault,
    model.OperationNameEnum_TrezorErc20IdempTransferFromVault,
    model.OperationNameEnum_TrezorErc20IdempTransferVaultBalance,
}
```

All operations (old + new) go through the same `lcmgrCallSerializer`. The disabled ones will fail at the lcmgr execution layer, not at the serializer layer.

---

### 1.4 Register relay result handlers for new operations

**File**: `pkg/laser/handlers/register.go` (EXISTING)

#### 1.4.1 Relay result handlers (~line 191-198)

Add 4 new operations to `trezorBalanceAffectingOperations`:

```go
trezorBalanceAffectingOperations := []model.OperationNameEnum{
    model.OperationNameEnum_TrezorErc20DepositToVault,       // Keep for graceful error path
    model.OperationNameEnum_TrezorErc20WithdrawFromVault,
    model.OperationNameEnum_TrezorErc20TransferFromVault,
    model.OperationNameEnum_TrezorErc20TransferVaultBalance,
    // Idempotent variants
    model.OperationNameEnum_TrezorErc20IdempDepositToVault,
    model.OperationNameEnum_TrezorErc20IdempWithdrawFromVault,
    model.OperationNameEnum_TrezorErc20IdempTransferFromVault,
    model.OperationNameEnum_TrezorErc20IdempTransferVaultBalance,
}
```

#### 1.4.2 Lcmgr handler operation list (~line 351-355)

Add 4 new operations to the operations list:

```go
// Trezor ERC20 idempotent operations
model.OperationNameEnum_TrezorErc20IdempDepositToVault,
model.OperationNameEnum_TrezorErc20IdempWithdrawFromVault,
model.OperationNameEnum_TrezorErc20IdempTransferFromVault,
model.OperationNameEnum_TrezorErc20IdempTransferVaultBalance,
```

---

### 1.5 Register lcmgr Diamond handlers for new operations

**File**: `pkg/laser/handlers/diamond_lcmgr.go` (EXISTING, ~line 783-786)

Add 4 new entries after line 786:

```go
// Idempotent Trezor ERC20 Facet Operations (called through Diamond proxy)
model.OperationNameEnum_TrezorErc20IdempDepositToVault:       trezorMutationHandler,
model.OperationNameEnum_TrezorErc20IdempWithdrawFromVault:    trezorMutationHandler,
model.OperationNameEnum_TrezorErc20IdempTransferFromVault:    trezorMutationHandler,
model.OperationNameEnum_TrezorErc20IdempTransferVaultBalance: trezorMutationHandler,
```

They use the same `trezorMutationHandler` as the non-idempotent variants because the result handler logic (slot link management based on vault balances) is identical.

---

### 1.6 Add slot IID resolution for new operations in default executor

**File**: `pkg/laser/executors/default_executor.go` (EXISTING, ~line 2632)

After the existing 4 `case` blocks for non-idempotent operations, add 4 new `case` blocks with **identical** logic:

```go
// Idempotent vault operations (same slot resolution as non-idempotent variants)
case model.OperationNameEnum_TrezorErc20IdempDepositToVault:
    // Deposit: tokens from FromAccount -> ToVault (in Treasury)
    roleMap[string(model.OperationRoleEnum_Treasury)] = req.ToSlot
    if req.CallData.Arguments != nil {
        for _, arg := range req.CallData.Arguments {
            switch arg.Decl.Name {
            case string(ats.ArgNameEnum_Erc20Addr):
                if strVal, ok := arg.Value.(string); ok {
                    roleMap[string(model.OperationRoleEnum_Erc20)] = strVal
                }
            case string(ats.ArgNameEnum_ToVault):
                if strVal, ok := arg.Value.(string); ok {
                    roleMap[string(model.OperationRoleEnum_ToVault)] = strVal
                }
            }
        }
    }

case model.OperationNameEnum_TrezorErc20IdempWithdrawFromVault:
    // Withdraw: tokens from FromVault (in Treasury) -> ToAccount
    roleMap[string(model.OperationRoleEnum_Treasury)] = req.ToSlot
    if req.CallData.Arguments != nil {
        for _, arg := range req.CallData.Arguments {
            switch arg.Decl.Name {
            case string(ats.ArgNameEnum_Erc20Addr):
                if strVal, ok := arg.Value.(string); ok {
                    roleMap[string(model.OperationRoleEnum_Erc20)] = strVal
                }
            case string(ats.ArgNameEnum_FromVault):
                if strVal, ok := arg.Value.(string); ok {
                    roleMap[string(model.OperationRoleEnum_FromVault)] = strVal
                }
            }
        }
    }

case model.OperationNameEnum_TrezorErc20IdempTransferFromVault:
    // Transfer: tokens between vaults in same Treasury
    roleMap[string(model.OperationRoleEnum_Treasury)] = req.ToSlot
    if req.CallData.Arguments != nil {
        for _, arg := range req.CallData.Arguments {
            switch arg.Decl.Name {
            case string(ats.ArgNameEnum_Erc20Addr):
                if strVal, ok := arg.Value.(string); ok {
                    roleMap[string(model.OperationRoleEnum_Erc20)] = strVal
                }
            case string(ats.ArgNameEnum_FromVault):
                if strVal, ok := arg.Value.(string); ok {
                    roleMap[string(model.OperationRoleEnum_FromVault)] = strVal
                }
            case string(ats.ArgNameEnum_ToVault):
                if strVal, ok := arg.Value.(string); ok {
                    roleMap[string(model.OperationRoleEnum_ToVault)] = strVal
                }
            }
        }
    }

case model.OperationNameEnum_TrezorErc20IdempTransferVaultBalance:
    // TransferVaultBalance: stash-aware transfer between vaults
    roleMap[string(model.OperationRoleEnum_Treasury)] = req.ToSlot
    if req.CallData.Arguments != nil {
        for _, arg := range req.CallData.Arguments {
            switch arg.Decl.Name {
            case string(ats.ArgNameEnum_Erc20Addr):
                if strVal, ok := arg.Value.(string); ok {
                    roleMap[string(model.OperationRoleEnum_Erc20)] = strVal
                }
            case string(ats.ArgNameEnum_FromVault):
                if strVal, ok := arg.Value.(string); ok {
                    roleMap[string(model.OperationRoleEnum_FromVault)] = strVal
                }
            case string(ats.ArgNameEnum_ToVault):
                if strVal, ok := arg.Value.(string); ok {
                    roleMap[string(model.OperationRoleEnum_ToVault)] = strVal
                }
            }
        }
    }
```

---

## Phase 2: Disable Old (Non-Idempotent) Operations

### 2.1 Disable in EthBC Diamond contract dispatch

**File**: `pkg/daemons/lcmgr/ethbc_diamond_contract.go` (EXISTING, ~line 1834-1841)

Change the 4 old `case` branches to return a disabled error:

```go
// DISABLED non-idempotent vault operations — use Idemp variants
case model.OperationNameEnum_TrezorErc20DepositToVault:
    return nil, nil, fmt.Errorf("operation %s is DISABLED: use %s instead — non-idempotent vault operations are no longer allowed to protect against double-execution",
        model.OperationNameEnum_TrezorErc20DepositToVault, model.OperationNameEnum_TrezorErc20IdempDepositToVault)
case model.OperationNameEnum_TrezorErc20WithdrawFromVault:
    return nil, nil, fmt.Errorf("operation %s is DISABLED: use %s instead — non-idempotent vault operations are no longer allowed to protect against double-execution",
        model.OperationNameEnum_TrezorErc20WithdrawFromVault, model.OperationNameEnum_TrezorErc20IdempWithdrawFromVault)
case model.OperationNameEnum_TrezorErc20TransferFromVault:
    return nil, nil, fmt.Errorf("operation %s is DISABLED: use %s instead — non-idempotent vault operations are no longer allowed to protect against double-execution",
        model.OperationNameEnum_TrezorErc20TransferFromVault, model.OperationNameEnum_TrezorErc20IdempTransferFromVault)
case model.OperationNameEnum_TrezorErc20TransferVaultBalance:
    return nil, nil, fmt.Errorf("operation %s is DISABLED: use %s instead — non-idempotent vault operations are no longer allowed to protect against double-execution",
        model.OperationNameEnum_TrezorErc20TransferVaultBalance, model.OperationNameEnum_TrezorErc20IdempTransferVaultBalance)
```

Add 4 new `case` branches for the idempotent operations:

```go
// Idempotent TrezorErc20 Vault facet operations (via Diamond proxy)
case model.OperationNameEnum_TrezorErc20IdempDepositToVault:
    return c.mutationTrezorErc20IdempDepositToVault(ctx, req)
case model.OperationNameEnum_TrezorErc20IdempWithdrawFromVault:
    return c.mutationTrezorErc20IdempWithdrawFromVault(ctx, req)
case model.OperationNameEnum_TrezorErc20IdempTransferFromVault:
    return c.mutationTrezorErc20IdempTransferFromVault(ctx, req)
case model.OperationNameEnum_TrezorErc20IdempTransferVaultBalance:
    return c.mutationTrezorErc20IdempTransferVaultBalance(ctx, req)
```

---

### 2.2 Disable in RDBMS TrezorErc20Contract dispatch

**File**: `pkg/daemons/lcmgr/trezor_erc20_contract.go` (EXISTING, ~line 70-76)

Same pattern — change old cases to disabled error, add new cases:

```go
// DISABLED non-idempotent vault operations
case model.OperationNameEnum_TrezorErc20DepositToVault:
    return nil, nil, fmt.Errorf("operation %s is DISABLED: use %s instead — non-idempotent vault operations are no longer allowed to protect against double-execution",
        model.OperationNameEnum_TrezorErc20DepositToVault, model.OperationNameEnum_TrezorErc20IdempDepositToVault)
case model.OperationNameEnum_TrezorErc20WithdrawFromVault:
    return nil, nil, fmt.Errorf("operation %s is DISABLED: use %s instead — non-idempotent vault operations are no longer allowed to protect against double-execution",
        model.OperationNameEnum_TrezorErc20WithdrawFromVault, model.OperationNameEnum_TrezorErc20IdempWithdrawFromVault)
case model.OperationNameEnum_TrezorErc20TransferFromVault:
    return nil, nil, fmt.Errorf("operation %s is DISABLED: use %s instead — non-idempotent vault operations are no longer allowed to protect against double-execution",
        model.OperationNameEnum_TrezorErc20TransferFromVault, model.OperationNameEnum_TrezorErc20IdempTransferFromVault)
case model.OperationNameEnum_TrezorErc20TransferVaultBalance:
    return nil, nil, fmt.Errorf("operation %s is DISABLED: use %s instead — non-idempotent vault operations are no longer allowed to protect against double-execution",
        model.OperationNameEnum_TrezorErc20TransferVaultBalance, model.OperationNameEnum_TrezorErc20IdempTransferVaultBalance)

// Idempotent vault operations (active)
case model.OperationNameEnum_TrezorErc20IdempDepositToVault:
    return c.mutationIdempDepositToVault(ctx, req)
case model.OperationNameEnum_TrezorErc20IdempWithdrawFromVault:
    return c.mutationIdempWithdrawFromVault(ctx, req)
case model.OperationNameEnum_TrezorErc20IdempTransferFromVault:
    return c.mutationIdempTransferFromVault(ctx, req)
case model.OperationNameEnum_TrezorErc20IdempTransferVaultBalance:
    return c.mutationIdempTransferVaultBalance(ctx, req)
```

---

## Phase 3: Implement Idempotent Mutations in lcmgr (EthBC Mode)

### 3.1 Add Erc20VaultIdempFacet ABI to EthBCDiamondContract

**File**: `pkg/daemons/lcmgr/ethbc_diamond_contract.go` (EXISTING)

#### 3.1.1 Add import (after line 23)

```go
"qomet.tech/agora/daemons/contracts/go/contracts/facets/_trezor/erc20-vault/erc20vaultidempfacet"
```

#### 3.1.2 Add ABI field to struct (after line 45, after `erc20VaultAdminABI`)

```go
erc20VaultIdempABI abi.ABI // Erc20VaultIdempFacet ABI for idempotent vault operations
```

#### 3.1.3 Parse ABI in NewEthBCDiamondContract

Follow the same pattern as `erc20VaultABI` parsing:

```go
erc20VaultIdempABI, err := abi.JSON(strings.NewReader(erc20vaultidempfacet.Erc20VaultIdempFacetABI))
if err != nil {
    return nil, fmt.Errorf("failed to parse Erc20VaultIdempFacet ABI: %w", err)
}
```

#### 3.1.4 Add to struct initializer

```go
erc20VaultIdempABI: erc20VaultIdempABI,
```

---

### 3.2 Implement `mutationTrezorErc20IdempDepositToVault`

**File**: `pkg/daemons/lcmgr/ethbc_diamond_contract.go` (EXISTING)

Copy from `mutationTrezorErc20DepositToVault` (~line 2803-2911). The **only differences** are:

1. Function name: `mutationTrezorErc20IdempDepositToVault`
2. Before `sendTransactionWithABI`, compute the idempotency key:
   ```go
   idempKey := idempotencyKeyToBytes32(req.IdempotencyKey)
   ```
3. Change `sendTransactionWithABI` call:
   - ABI: `c.erc20VaultIdempABI` (was `c.erc20VaultABI`)
   - Method name: `"idempDepositToErc20Vault"` (was `"depositToErc20Vault"`)
   - Prepend `idempKey` as first argument:
     ```go
     txHash, receipt, err := c.sendTransactionWithABI(ctx, signerAddress, c.erc20VaultIdempABI, "idempDepositToErc20Vault",
         idempKey,  // NEW: idempotency key
         ledgerId,
         common.HexToAddress(callerAccount),
         common.HexToAddress(erc20Addr),
         common.HexToAddress(fromAccount),
         common.HexToAddress(toVault),
         amount,
         data,
     )
     ```
4. All post-transaction logic (vault balance query, metadata, result) remains **identical**

---

### 3.3 Implement `mutationTrezorErc20IdempWithdrawFromVault`

**File**: `pkg/daemons/lcmgr/ethbc_diamond_contract.go` (EXISTING)

Copy from `mutationTrezorErc20WithdrawFromVault` (~line 2913-3011). Differences:

1. Function name: `mutationTrezorErc20IdempWithdrawFromVault`
2. Compute idempotency key: `idempKey := idempotencyKeyToBytes32(req.IdempotencyKey)`
3. Change `sendTransactionWithABI`:
   - ABI: `c.erc20VaultIdempABI`
   - Method: `"idempWithdrawFromErc20VaultTo"`
   - Prepend `idempKey` as first argument:
     ```go
     txHash, receipt, err := c.sendTransactionWithABI(ctx, signerAddress, c.erc20VaultIdempABI, "idempWithdrawFromErc20VaultTo",
         idempKey,
         ledgerId,
         common.HexToAddress(callerAccount),
         common.HexToAddress(erc20Addr),
         common.HexToAddress(toAccount),
         amount,
         data,
     )
     ```

---

### 3.4 Implement `mutationTrezorErc20IdempTransferFromVault`

**File**: `pkg/daemons/lcmgr/ethbc_diamond_contract.go` (EXISTING)

Copy from `mutationTrezorErc20TransferFromVault` (~line 3013-3119). Differences:

1. Function name: `mutationTrezorErc20IdempTransferFromVault`
2. Compute idempotency key: `idempKey := idempotencyKeyToBytes32(req.IdempotencyKey)`
3. Change `sendTransactionWithABI`:
   - ABI: `c.erc20VaultIdempABI`
   - Method: `"idempTransferFromErc20Vault"`
   - Prepend `idempKey`:
     ```go
     txHash, receipt, err := c.sendTransactionWithABI(ctx, signerAddress, c.erc20VaultIdempABI, "idempTransferFromErc20Vault",
         idempKey,
         ledgerId,
         common.HexToAddress(callerAccount),
         common.HexToAddress(erc20Addr),
         common.HexToAddress(fromVault),
         common.HexToAddress(toVault),
         amount,
         data,
     )
     ```

---

### 3.5 Implement `mutationTrezorErc20IdempTransferVaultBalance`

**File**: `pkg/daemons/lcmgr/ethbc_diamond_contract.go` (EXISTING)

Copy from `mutationTrezorErc20TransferVaultBalance` (~line 3122-3254). Differences:

1. Function name: `mutationTrezorErc20IdempTransferVaultBalance`
2. Compute idempotency key: `idempKey := idempotencyKeyToBytes32(req.IdempotencyKey)`
3. Change `sendTransactionWithABI`:
   - ABI: `c.erc20VaultIdempABI` (was `c.erc20VaultAdminABI`)
   - Method: `"idempTransferErc20VaultBalance"` (was `"transferErc20VaultBalance"`)
   - Prepend `idempKey`:
     ```go
     txHash, receipt, err := c.sendTransactionWithABI(ctx, signerAddress, c.erc20VaultIdempABI, "idempTransferErc20VaultBalance",
         idempKey,
         ledgerId,
         common.HexToAddress(callerAccount),
         common.HexToAddress(erc20Addr),
         common.HexToAddress(fromVault),
         common.HexToAddress(toVault),
         fromStash,
         toStash,
         amount,
         data,
     )
     ```

**IMPORTANT NOTE**: This method currently uses `c.erc20VaultAdminABI` and calls `"transferErc20VaultBalance"`. The idempotent variant moves to `c.erc20VaultIdempABI` and calls `"idempTransferErc20VaultBalance"`. Verify that the Solidity idempotent function has identical authorization checks.

---

### 3.6 Both facets deployed — `erc20VaultABI` for queries, `erc20VaultIdempABI` for mutations

Both `Erc20VaultFacet` and `Erc20VaultIdempFacet` are deployed to the treasury Diamond:
- **`Erc20VaultFacet`**: Provides query functions (read-only). Non-idempotent mutations are **disabled at LASER level** (return error with "use idemp variant" message).
- **`Erc20VaultIdempFacet`**: Provides idempotent mutation functions.

Query functions using `c.erc20VaultABI`:
- `getErc20VaultBalance`
- `getErc20VaultTracedErc20s`
- `getErc20VaultTracedStashes`
- `getVaultTotalBalance` (used internally by mutation methods for slot link metadata)

Non-idempotent LASER operations are disabled in `ethbc_diamond_contract.go` (lines 1842-1854) — they return an error directing callers to use the idempotent variants.

---

## Phase 4: Implement Idempotent Mutations in lcmgr (RDBMS Mode)

### 4.1 Add idempotency key tracking table

**File**: `deploy/k8s/init/init_trezor_erc20_pgsql.sql` (EXISTING)

Add new Table 7 at the end (before `GRANT` statements):

```sql
-- ----------------------------------------------------------------------------
-- Table 7: trz_erc20_idempotency_keys
-- ----------------------------------------------------------------------------
-- Tracks used idempotency keys to prevent double-execution in RDBMS mode.
-- EthBC mode uses the on-chain Erc20VaultIdempFacet; this table is the
-- RDBMS equivalent for simulation mode.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS lcmgr.trz_erc20_idempotency_keys (
    -- Identity
    iid VARCHAR PRIMARY KEY,

    -- Scope
    chain_id VARCHAR NOT NULL,
    trezor_contract_address VARCHAR NOT NULL,

    -- Idempotency key (SHA-256 hash of the original key string)
    idempotency_key VARCHAR NOT NULL,

    -- Operation that consumed this key
    operation VARCHAR NOT NULL,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Unique constraint: One key per contract
    CONSTRAINT uk_trz_idemp_key UNIQUE (
        chain_id,
        trezor_contract_address,
        idempotency_key
    )
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_trz_idemp_contract
    ON lcmgr.trz_erc20_idempotency_keys(trezor_contract_address);

CREATE INDEX IF NOT EXISTS idx_trz_idemp_key
    ON lcmgr.trz_erc20_idempotency_keys(idempotency_key);

CREATE INDEX IF NOT EXISTS idx_trz_idemp_created
    ON lcmgr.trz_erc20_idempotency_keys(created_at DESC);

COMMENT ON TABLE lcmgr.trz_erc20_idempotency_keys IS
    'Used idempotency keys for RDBMS-mode vault operations (prevents double-execution)';
```

Add to `GRANT` section:

```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON lcmgr.trz_erc20_idempotency_keys TO agora_app;
```

---

### 4.2 Add idempotency tracking to ContractStore interface

**File**: `pkg/daemons/lcmgr/contract_store.go` (EXISTING)

Add after the TREZOR_ERC20 section (~after line 78):

```go
// Idempotency key tracking (RDBMS mode)
IsIdempotencyKeyUsed(ctx context.Context, contractAddress string, key string) (bool, error)
MarkIdempotencyKeyUsed(ctx context.Context, contractAddress string, key string, operation string) error
```

---

### 4.3 Implement in PostgreSQL store

**File**: `pkg/daemons/lcmgr/contract_store_pgsql.go` (EXISTING)

```go
func (s *PgsqlContractStore) IsIdempotencyKeyUsed(ctx context.Context, contractAddress string, key string) (bool, error) {
    query := `SELECT COUNT(*) FROM lcmgr.trz_erc20_idempotency_keys
              WHERE chain_id = $1 AND trezor_contract_address = $2 AND idempotency_key = $3`
    var count int
    err := s.db.QueryRowContext(ctx, query, s.chainID, contractAddress, key).Scan(&count)
    if err != nil {
        return false, fmt.Errorf("failed to check idempotency key: %w", err)
    }
    return count > 0, nil
}

func (s *PgsqlContractStore) MarkIdempotencyKeyUsed(ctx context.Context, contractAddress string, key string, operation string) error {
    iid := "trz-idemp-" + uuid.New().String()
    query := `INSERT INTO lcmgr.trz_erc20_idempotency_keys (iid, chain_id, trezor_contract_address, idempotency_key, operation)
              VALUES ($1, $2, $3, $4, $5)
              ON CONFLICT (chain_id, trezor_contract_address, idempotency_key) DO NOTHING`
    _, err := s.db.ExecContext(ctx, query, iid, s.chainID, contractAddress, key, operation)
    if err != nil {
        return fmt.Errorf("failed to mark idempotency key: %w", err)
    }
    return nil
}
```

**Note**: `trz_erc20_idempotency_keys` does NOT have an FK to `shared.entities` because it is a denormalized tracking table (same pattern as `trz_erc20_vault_balances`).

---

### 4.4 Implement in in-memory store

**File**: `pkg/daemons/lcmgr/contract_store_inmem.go` (EXISTING)

Add field to struct:

```go
idempotencyKeys map[string]bool // key = "contractAddress:idempotencyKey"
```

Initialize in constructor:

```go
idempotencyKeys: make(map[string]bool),
```

Implement methods:

```go
func (s *InMemContractStore) IsIdempotencyKeyUsed(ctx context.Context, contractAddress string, key string) (bool, error) {
    return s.idempotencyKeys[contractAddress+":"+key], nil
}

func (s *InMemContractStore) MarkIdempotencyKeyUsed(ctx context.Context, contractAddress string, key string, operation string) error {
    s.idempotencyKeys[contractAddress+":"+key] = true
    return nil
}
```

---

### 4.5 Implement 4 idempotent RDBMS mutation methods

**File**: `pkg/daemons/lcmgr/trezor_erc20_contract.go` (EXISTING)

For **each** of the 4 mutations, create an idempotent wrapper. Pattern:

```go
// mutationIdempDepositToVault is the idempotent variant of mutationDepositToVault.
// Checks if the idempotency key has been used; if so, returns a no-op result.
// If the key is new, executes the deposit and marks the key as used.
func (c *TrezorErc20Contract) mutationIdempDepositToVault(ctx context.Context, req laser.MutationRequest) (*model.FutureResult, *TransactionInfo, error) {
    // Check idempotency
    if req.IdempotencyKey != "" {
        used, err := c.store.IsIdempotencyKeyUsed(ctx, c.contractAddress, req.IdempotencyKey)
        if err != nil {
            return nil, nil, fmt.Errorf("failed to check idempotency key: %w", err)
        }
        if used {
            // Key already used — return no-op result
            return &model.FutureResult{
                Metadata: map[string]string{
                    "idempotency_key_reused": "true",
                    "operation":              "idempDepositToVault",
                },
            }, &TransactionInfo{GasUsed: "0", Events: []*ethereum.EventLog{}}, nil
        }
    }

    // Execute the actual deposit (reuse existing logic)
    result, txInfo, err := c.mutationDepositToVault(ctx, req)
    if err != nil {
        return nil, nil, err
    }

    // Mark key as used AFTER successful execution
    if req.IdempotencyKey != "" {
        if markErr := c.store.MarkIdempotencyKeyUsed(ctx, c.contractAddress, req.IdempotencyKey, "idempDepositToVault"); markErr != nil {
            // Log but don't fail — the deposit succeeded
            fmt.Printf("[WARN] failed to mark idempotency key as used: %v\n", markErr)
        }
    }

    return result, txInfo, nil
}
```

**IMPORTANT**: The idempotent methods in RDBMS mode call the **old** internal mutation methods (`c.mutationDepositToVault`, etc.) which remain as private methods. The old operations are disabled at the dispatcher level (Phase 2.2), not at the method level. The internal methods are reused by the new idempotent wrappers.

Repeat this pattern for:
- `mutationIdempWithdrawFromVault` → wraps `c.mutationWithdrawFromVault`
- `mutationIdempTransferFromVault` → wraps `c.mutationTransferFromVault`
- `mutationIdempTransferVaultBalance` → wraps `c.mutationTransferVaultBalance`

---

## Phase 5: Saga Input Chain — Add `erc20_vault_idemp_facet_version`

### 5.1 REST API request struct

**File**: `pkg/daemons/accmgr/api/v1/legal_mechanisms_post_deploy_treasury.go` (EXISTING)

#### 5.1.1 Add field to request struct (after line 25)

```go
Erc20VaultIdempFacetVersion string `json:"erc20_vault_idemp_facet_version"`
```

#### 5.1.2 Add validation (after line 176, `EthVaultFacetVersion` validation)

```go
if req.Erc20VaultIdempFacetVersion == "" {
    c.JSON(http.StatusBadRequest, gin.H{
        "error": "erc20_vault_idemp_facet_version is required",
    })
    return
}
```

**CRITICAL**: No fallback, no default. If missing, the call MUST fail immediately.

#### 5.1.3 Add to saga input map (after line 197)

```go
"erc20_vault_idemp_facet_version": req.Erc20VaultIdempFacetVersion,
```

---

### 5.2 Verify inputs executor

**File**: `pkg/daemons/accmgr/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/verify_inputs.go` (EXISTING)

Add to `facetVersionFields` slice (line 111, after `"eth_vault_facet_version"`):

```go
"erc20_vault_idemp_facet_version",
```

---

### 5.3 Sub-saga spawner

**File**: `pkg/daemons/accmgr/trax/executors/setup_new_legal_participant/spawn_deploy_treasury.go` (EXISTING)

#### 5.3.1 Extract with default (after line 236)

```go
erc20VaultIdempFacetVersion := input["erc20_vault_idemp_facet_version"]
if erc20VaultIdempFacetVersion == "" {
    erc20VaultIdempFacetVersion = "latest"
}
```

#### 5.3.2 Add to sub-saga input map (after line 253)

```go
"erc20_vault_idemp_facet_version": erc20VaultIdempFacetVersion,
```

---

### 5.4 Diamond facet addition executor

**File**: `pkg/daemons/laseragent/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/add_vault_facets.go` (EXISTING)

#### 5.4.1 Extract version (after line 72)

```go
erc20VaultIdempFacetVersion := input["erc20_vault_idemp_facet_version"]
```

#### 5.4.2 Add to validation (line 75-77)

Change:
```go
if erc20VaultAdminFacetVersion == "" || erc20VaultFacetVersion == "" ||
    ledgerListerFacetVersion == "" || rbacFacetVersion == "" ||
    propsFacetVersion == "" || activityStoreFacetVersion == "" || ethVaultFacetVersion == "" {
```
To:
```go
if erc20VaultAdminFacetVersion == "" || erc20VaultFacetVersion == "" ||
    ledgerListerFacetVersion == "" || rbacFacetVersion == "" ||
    propsFacetVersion == "" || activityStoreFacetVersion == "" || ethVaultFacetVersion == "" ||
    erc20VaultIdempFacetVersion == "" {
```

**CRITICAL**: No fallback, no default. If missing, the executor MUST fail immediately with a clear error.

#### 5.4.3 Add to facet slot addresses (after line 94)

```go
fmt.Sprintf("Erc20VaultIdempFacet:%s", erc20VaultIdempFacetVersion),
```

This makes 7 vault facets total (Erc20VaultFacet removed from Lattice deploy — replaced entirely by Erc20VaultIdempFacet):
1. Erc20VaultAdminFacet
2. LedgerListerFacet
3. RBACFacet
4. PropsFacet
5. ActivityStoreFacet
6. EthVaultFacet
7. **Erc20VaultIdempFacet**

---

## Phase 6: Switch All Saga Callers to Idempotent Operations

### 6.1 Cash token initial supply deposit

**File**: `pkg/daemons/laseragent/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/deposit_initial_supply_to_treasury.go` (EXISTING)

Line 746: Change:
```go
funcDecl := ats.Func(string(model.OperationNameEnum_TrezorErc20DepositToVault)).
```
To:
```go
funcDecl := ats.Func(string(model.OperationNameEnum_TrezorErc20IdempDepositToVault)).
```

---

### 6.2 Create investor order — transfer from vault

**File**: `pkg/daemons/treassvc/trax/executors/create_investor_order/laser_helpers.go` (EXISTING)

#### 6.2.1 Line 138: Change:
```go
funcDecl := ats.Func(string(model.OperationNameEnum_TrezorErc20TransferFromVault)).
```
To:
```go
funcDecl := ats.Func(string(model.OperationNameEnum_TrezorErc20IdempTransferFromVault)).
```

#### 6.2.2 Line 245: Change:
```go
funcDecl := ats.Func(string(model.OperationNameEnum_TrezorErc20TransferVaultBalance)).
```
To:
```go
funcDecl := ats.Func(string(model.OperationNameEnum_TrezorErc20IdempTransferVaultBalance)).
```

---

### 6.3 Fund account — deposit & transfer

**File**: `pkg/daemons/treassvc/trax/executors/fund_account_with_cash_tokens/mint_tokens_if_needed.go` (EXISTING)

Line 341: Change:
```go
funcDecl := ats.Func(string(model.OperationNameEnum_TrezorErc20DepositToVault)).
```
To:
```go
funcDecl := ats.Func(string(model.OperationNameEnum_TrezorErc20IdempDepositToVault)).
```

**File**: `pkg/daemons/treassvc/trax/executors/fund_account_with_cash_tokens/transfer_from_clearing_to_destination.go` (EXISTING)

Line 161: Change:
```go
funcDecl := ats.Func(string(model.OperationNameEnum_TrezorErc20TransferFromVault)).
```
To:
```go
funcDecl := ats.Func(string(model.OperationNameEnum_TrezorErc20IdempTransferFromVault)).
```

---

## Phase 7: Update Existing Documentation

### 7.1 Update TODO_DEPLOY_TREASURY_LEGAL_MECHANISMS_SAGA.md

**File**: `docs/TODO_DEPLOY_TREASURY_LEGAL_MECHANISMS_SAGA.md` (EXISTING)

In the **Inputs** table, add a new row:

```
| erc20_vault_idemp_facet_version | string | Yes | Version of erc20-vault-idemp facet |
```

In the **Prerequisites** section, add:

```
- `erc20-vault-idemp` - Idempotent ERC20 vault operations facet
```

In the saga step 12 description, update facet count from 7 to 8:

```
| 12 | add_vault_facets_to_trezor_diamond | lasersvc | admin-partner adds all vault facets (a-h, 8 total) to Trezor diamond |
```

---

### 7.2 Update SUMMARY-FOR-AGENT.md

**File**: `docs/SUMMARY-FOR-AGENT.md` (EXISTING)

Add a note under the LASER/lcmgr section:

```
### Idempotent Treasury Vault Operations
- Vault mutations use idempotent LASER operations (IDEMP_ prefix)
- Non-idempotent variants (DEPOSIT_TO_VAULT, etc.) are DISABLED
- EthBC: Uses Erc20VaultIdempFacet with bytes32 idempotencyKey
- RDBMS: Uses trz_erc20_idempotency_keys table for key tracking
- See: TODO_IDEMPOTENT_TREASURY_VAULT_OPERATIONS.md
```

---

## Phase 8: Update Existing Tests

### 8.1 Update integration tests (unit tests)

**File**: `pkg/daemons/lcmgr/api/v1/api_integration_pgsql_test.go` (EXISTING)

Update operation names in test cases to use idempotent variants:

- Line 1203: Change `OperationNameEnum_TrezorErc20DepositToVault` → `OperationNameEnum_TrezorErc20IdempDepositToVault`
- Line 1289: Change `OperationNameEnum_TrezorErc20WithdrawFromVault` → `OperationNameEnum_TrezorErc20IdempWithdrawFromVault`
- Line 1363: Change `OperationNameEnum_TrezorErc20TransferVaultBalance` → `OperationNameEnum_TrezorErc20IdempTransferVaultBalance`

Each of these tests must also set `IdempotencyKey` on the `MutationRequest`.

---

### 8.2 Add disabled operation unit tests

**File**: `pkg/daemons/lcmgr/api/v1/api_integration_pgsql_test.go` (EXISTING)

Add 4 new test functions verifying disabled operations fail:

```go
func TestTrezorDepositToVaultDisabledPgsql(t *testing.T) {
    api, _, cleanup := setupTestAPIPgsql(t)
    defer cleanup()

    mutReq := laser.MutationRequest{
        CallData: ats.BoundFunc{
            Decl: ats.FuncDecl{Name: string(model.OperationNameEnum_TrezorErc20DepositToVault)},
        },
    }

    _, _, err := api.TrezorContract.ExecuteMutation(context.Background(), mutReq, laser.MutationOptions{})
    assert.Error(t, err)
    assert.Contains(t, err.Error(), "DISABLED")
    assert.Contains(t, err.Error(), string(model.OperationNameEnum_TrezorErc20IdempDepositToVault))
}
```

Repeat for Withdraw, Transfer, TransferVaultBalance (4 tests total).

---

### 8.3 Add idempotency key reuse unit tests (RDBMS)

**File**: `pkg/daemons/lcmgr/api/v1/api_integration_pgsql_test.go` (EXISTING)

```go
func TestTrezorIdempDepositToVaultIdempotencyKeyReusePgsql(t *testing.T) {
    api, _, cleanup := setupTestAPIPgsql(t)
    defer cleanup()

    mutReq := laser.MutationRequest{
        IdempotencyKey: "test-idemp-deposit-001",
        CallData: ats.BoundFunc{
            Decl: ats.FuncDecl{Name: string(model.OperationNameEnum_TrezorErc20IdempDepositToVault)},
            Arguments: []ats.BoundVariable{
                // ... standard deposit arguments
            },
        },
    }

    // First deposit should succeed
    result1, _, err := api.TrezorContract.ExecuteMutation(context.Background(), mutReq, laser.MutationOptions{})
    assert.NoError(t, err)
    assert.NotNil(t, result1)

    // Second deposit with SAME idempotency key should be a no-op
    result2, _, err := api.TrezorContract.ExecuteMutation(context.Background(), mutReq, laser.MutationOptions{})
    assert.NoError(t, err)
    assert.NotNil(t, result2)
    assert.Equal(t, "true", result2.Metadata["idempotency_key_reused"])

    // Verify balance only increased once
    balance, err := api.Store.GetVaultBalance(context.Background(), api.TrezorContractAddr, 1, erc20Addr, vaultAddr, ethereum.STASH_LIQUID)
    assert.NoError(t, err)
    assert.Equal(t, expectedOnceBalance, balance)
}
```

Repeat for Withdraw, Transfer, TransferVaultBalance (4 tests total).

---

### 8.4 Update E2E helper functions to use idempotent operations

The following E2E test helper functions directly reference non-idempotent operation names and MUST be switched:

#### 8.4.1 `erc20_helpers_test.go` — vault operation helpers

**File**: `tests/e2e/laser/erc20_helpers_test.go` (EXISTING)

- Line 1131: `depositToTreasuryVault` — change `OperationNameEnum_TrezorErc20DepositToVault` → `OperationNameEnum_TrezorErc20IdempDepositToVault`
- Line 1012: `withdrawFromTreasuryVault` (full) — change `OperationNameEnum_TrezorErc20WithdrawFromVault` → `OperationNameEnum_TrezorErc20IdempWithdrawFromVault`
- Line 1042: `withdrawFromTreasuryVault` (partial) — same change
- Line 1175: `transferFromTreasuryVault` — change `OperationNameEnum_TrezorErc20TransferFromVault` → `OperationNameEnum_TrezorErc20IdempTransferFromVault`
- Line 1214: `transferVaultBalance` — change `OperationNameEnum_TrezorErc20TransferVaultBalance` → `OperationNameEnum_TrezorErc20IdempTransferVaultBalance`

#### 8.4.2 `indtrxss_common_test.go` — individual saga step helpers

**File**: `tests/e2e/laser/indtrxss_common_test.go` (EXISTING)

- Line 553: Change `OperationNameEnum_TrezorErc20DepositToVault` → `OperationNameEnum_TrezorErc20IdempDepositToVault`
- Line 559: Change `OperationNameEnum_TrezorErc20TransferFromVault` → `OperationNameEnum_TrezorErc20IdempTransferFromVault`
- Line 565: Change `OperationNameEnum_TrezorErc20TransferVaultBalance` → `OperationNameEnum_TrezorErc20IdempTransferVaultBalance`

#### 8.4.3 `indtrxss_saga_fundaccount_treassvc_test.go` — fund account saga step tests

**File**: `tests/e2e/laser/indtrxss_saga_fundaccount_treassvc_test.go` (EXISTING)

- Line 1461: Change `OperationNameEnum_TrezorErc20DepositToVault` → `OperationNameEnum_TrezorErc20IdempDepositToVault`
- Line 1508: Change `OperationNameEnum_TrezorErc20TransferFromVault` → `OperationNameEnum_TrezorErc20IdempTransferFromVault`

#### 8.4.4 `executor_external_call_test.go` — external call tests

**File**: `tests/e2e/laser/executor_external_call_test.go` (EXISTING)

- Line 339: Change `OperationNameEnum_TrezorErc20DepositToVault` → `OperationNameEnum_TrezorErc20IdempDepositToVault`

#### 8.4.5 `init_fund_account_saga.sql` — saga template SQL

**File**: `tests/e2e/laser/init_fund_account_saga.sql` (EXISTING)

- Line 113: Update comment reference from `TrezorErc20DepositToVault` → `TrezorErc20IdempDepositToVault`
- Line 167: Update comment reference from `TrezorErc20TransferFromVault` → `TrezorErc20IdempTransferFromVault`

---

### 8.5 Mark old E2E tests that directly test non-idempotent operations as skipped

The following tests directly test non-idempotent vault operations. They must be **skipped with proper messages** pointing to the idempotent test equivalents in Category 40:

**File**: `tests/e2e/laser/deposit_to_treasury_test.go` (EXISTING)
- Add `t.Skip("SKIPPED: Non-idempotent deposit operations are disabled. See Category 40 idempotent vault tests.")` at the top of each test function that uses the old operation directly.

**File**: `tests/e2e/laser/treasury_vault_withdraw_test.go` (EXISTING)
- Add `t.Skip("SKIPPED: Non-idempotent withdraw operations are disabled. See Category 40 idempotent vault tests.")` at the top of each test function.

**NOTE**: Tests that use vault operations **indirectly** through sagas (fund_account, create_investor_order) do NOT need to be skipped — they will automatically use the new operations once Phase 6 callers are switched.

---

## Phase 9: New E2E Tests (EthBC Mode)

### 9.1 Test: Idempotent deposit — green path

**File**: `tests/e2e/laser/treasury_vault_idemp_test.go` (NEW)

**Category**: Category 11 (Deposit & Treasury, ⭐⭐⭐⭐) or new Category 40

```go
func TestTreasuryVaultIdempDeposit_GreenPath(t *testing.T) {
    // Setup: Deploy full treasury infrastructure (E1/E2, facets, legal structure, treasury mechanisms)
    // Ensure Erc20VaultIdempFacet is in the Diamond
    // Mint ERC20 tokens to a test account

    // Execute: Call TREZOR_ERC20_IDEMP_DEPOSIT_TO_VAULT via LASER
    // Verify: Vault LIQUID balance increased by correct amount
    // Verify: Vault TOTAL stash recalculated
    // Verify: ERC20 was traced for vault
    // Verify: Activity created with correct operation type
    // Verify: Slot links created (TREASURY_ERC20_VAULT_HOLDER/HOLDING)
}
```

### 9.2 Test: Idempotent deposit — key reuse (no double-execution)

```go
func TestTreasuryVaultIdempDeposit_KeyReuse(t *testing.T) {
    // Setup: Same as green path
    // Execute: Deposit 1000 tokens with idempotency key "key-A"
    // Verify: Balance = 1000

    // Execute AGAIN: Deposit with SAME idempotency key "key-A"
    // Verify: Transaction succeeds (no revert)
    // Verify: Balance is STILL 1000 (not 2000) — key was already used
    // Verify: IsErc20VaultIdempKeyUsed("key-A") returns true
}
```

### 9.3 Test: Idempotent withdraw — green path

```go
func TestTreasuryVaultIdempWithdraw_GreenPath(t *testing.T) {
    // Setup: Deposit tokens into vault first
    // Execute: Call TREZOR_ERC20_IDEMP_WITHDRAW_FROM_VAULT
    // Verify: Vault LIQUID decreased
    // Verify: User account ERC20 balance increased
    // Verify: Activity created
}
```

### 9.4 Test: Idempotent withdraw — key reuse

```go
func TestTreasuryVaultIdempWithdraw_KeyReuse(t *testing.T) {
    // Setup: Deposit 1000 tokens
    // Execute: Withdraw 500 with key "key-B"
    // Verify: Vault = 500, account += 500
    // Execute AGAIN: Withdraw 500 with SAME key "key-B"
    // Verify: Vault STILL 500, account unchanged — key was already used
}
```

### 9.5 Test: Idempotent transfer from vault — green path

```go
func TestTreasuryVaultIdempTransferFromVault_GreenPath(t *testing.T) {
    // Setup: Two vaults, deposit tokens into vault-A
    // Execute: Transfer 300 from vault-A to vault-B
    // Verify: vault-A LIQUID decreased by 300
    // Verify: vault-B LIQUID increased by 300
    // Verify: Both vault TOTAL stashes updated
}
```

### 9.6 Test: Idempotent transfer from vault — key reuse

```go
func TestTreasuryVaultIdempTransferFromVault_KeyReuse(t *testing.T) {
    // Same as green path
    // Execute transfer again with same key
    // Verify: balances unchanged (no double-transfer)
}
```

### 9.7 Test: Idempotent transfer vault balance (stash-aware) — green path

```go
func TestTreasuryVaultIdempTransferVaultBalance_GreenPath(t *testing.T) {
    // Setup: Deposit into vault, tokens in LIQUID stash (stash_id=0)
    // Execute: Transfer from stash 0 to stash 2 (custom)
    // Verify: LIQUID stash decreased
    // Verify: Custom stash increased
    // Verify: TOTAL stash unchanged (same vault)
}
```

### 9.8 Test: Idempotent transfer vault balance — key reuse

```go
func TestTreasuryVaultIdempTransferVaultBalance_KeyReuse(t *testing.T) {
    // Same as green path
    // Execute transfer again with same key
    // Verify: stash balances unchanged
}
```

### 9.9 Test: Disabled operation — deposit fails with clear error

```go
func TestTreasuryVaultDisabledDeposit_FailsWithError(t *testing.T) {
    // Setup: Deploy treasury infrastructure
    // Execute: Call OLD operation TREZOR_ERC20_DEPOSIT_TO_VAULT
    // Verify: Fails with error containing "DISABLED"
    // Verify: Error mentions the idempotent alternative
}
```

### 9.10 Test: Disabled operation — withdraw fails with clear error

```go
func TestTreasuryVaultDisabledWithdraw_FailsWithError(t *testing.T) {
    // Same pattern as 9.9 but for withdraw
}
```

### 9.11 Test: Disabled operation — transfer fails with clear error

```go
func TestTreasuryVaultDisabledTransfer_FailsWithError(t *testing.T) {
    // Same pattern as 9.9 but for transfer
}
```

### 9.12 Test: Disabled operation — transferVaultBalance fails with clear error

```go
func TestTreasuryVaultDisabledTransferVaultBalance_FailsWithError(t *testing.T) {
    // Same pattern as 9.9 but for transferVaultBalance
}
```

### 9.13 Test: Different idempotency keys are independent

```go
func TestTreasuryVaultIdempDeposit_DifferentKeysAreIndependent(t *testing.T) {
    // Setup: Fund account with 2000 tokens
    // Execute: Deposit 500 with key "key-X"
    // Verify: Vault = 500
    // Execute: Deposit 500 with key "key-Y" (different key)
    // Verify: Vault = 1000 — both deposits applied
}
```

### 9.14 Test: Treasury deployment includes Erc20VaultIdempFacet

```go
func TestTreasuryDeployment_IncludesIdempFacet(t *testing.T) {
    // Setup: Deploy treasury via full saga
    // Verify: Diamond has 8 vault facets (not 7)
    // Verify: idempDepositToErc20Vault selector is present in the Diamond
    // Verify: isErc20VaultIdempKeyUsed selector is present
}
```

### 9.15 Test: Fund account saga uses idempotent operations

```go
func TestFundAccountSaga_UsesIdempotentDeposit(t *testing.T) {
    // Setup: Full fund_account infrastructure
    // Execute: Run fund_account_with_cash_tokens saga
    // Verify: Saga completes successfully
    // Verify: Treasury balance is correct
    // This test validates that the saga correctly uses the new idemp operation
}
```

### 9.16 Test: Create investor order saga uses idempotent operations

```go
func TestCreateInvestorOrder_UsesIdempotentTransfer(t *testing.T) {
    // Setup: Full investor order infrastructure
    // Execute: Create investor order saga
    // Verify: Treasury transfers use idempotent operations
    // Verify: Correct balances
}
```

### 9.17 Test: Insufficient balance — idempotent deposit still validates

```go
func TestTreasuryVaultIdempDeposit_InsufficientBalance(t *testing.T) {
    // Setup: Account with 100 tokens
    // Execute: Try to deposit 1000 with idemp key
    // Verify: Fails with insufficient balance error (not masked by idempotency)
}
```

### 9.18 Test: Insufficient balance — idempotent withdraw still validates

```go
func TestTreasuryVaultIdempWithdraw_InsufficientBalance(t *testing.T) {
    // Setup: Vault with 100 tokens
    // Execute: Try to withdraw 1000 with idemp key
    // Verify: Fails with insufficient balance error
}
```

---

## Phase 10: Update Makefile and E2E Test Catalog

### 10.1 Add Category 40 to Makefile

**File**: `Makefile` (EXISTING)

Add new E2E category:

```makefile
# Category 40: Idempotent Treasury Vault Operations (⭐⭐⭐⭐, EthBC)
E2E_CAT40_PATTERN := TestTreasuryVaultIdemp|TestTreasuryVaultDisabled|TestTreasuryDeployment_IncludesIdempFacet|TestFundAccountSaga_UsesIdempotent|TestCreateInvestorOrder_UsesIdempotent

laser-e2e-ethbc-cat40:
	$(call run-e2e-ethbc,$(E2E_CAT40_PATTERN))
```

### 10.2 Update E2E_TEST_CATALOG.md

**File**: `docs/E2E_TEST_CATALOG.md` (EXISTING)

Add Category 40 section:

```markdown
### Category 40: Idempotent Treasury Vault Operations

**Complexity**: ⭐⭐⭐⭐
**Mode**: EthBC only
**Makefile Target**: `laser-e2e-ethbc-cat40`
**Test File**: `tests/e2e/laser/treasury_vault_idemp_test.go`

| Test | Complexity | Description | Key Operations |
|------|-----------|-------------|----------------|
| TestTreasuryVaultIdempDeposit_GreenPath | ⭐⭐⭐⭐ | Deposit via idempotent operation | IdempDepositToVault |
| TestTreasuryVaultIdempDeposit_KeyReuse | ⭐⭐⭐⭐ | Verify no double-execution on key reuse | IdempDepositToVault x2 |
| TestTreasuryVaultIdempWithdraw_GreenPath | ⭐⭐⭐⭐ | Withdraw via idempotent operation | IdempWithdrawFromVault |
| TestTreasuryVaultIdempWithdraw_KeyReuse | ⭐⭐⭐⭐ | Verify no double-withdraw on key reuse | IdempWithdrawFromVault x2 |
| TestTreasuryVaultIdempTransferFromVault_GreenPath | ⭐⭐⭐⭐ | Inter-vault transfer via idempotent op | IdempTransferFromVault |
| TestTreasuryVaultIdempTransferFromVault_KeyReuse | ⭐⭐⭐⭐ | Verify no double-transfer on key reuse | IdempTransferFromVault x2 |
| TestTreasuryVaultIdempTransferVaultBalance_GreenPath | ⭐⭐⭐⭐ | Stash-aware transfer via idempotent op | IdempTransferVaultBalance |
| TestTreasuryVaultIdempTransferVaultBalance_KeyReuse | ⭐⭐⭐⭐ | Verify no double-transfer on key reuse | IdempTransferVaultBalance x2 |
| TestTreasuryVaultDisabledDeposit_FailsWithError | ⭐⭐⭐ | Disabled deposit returns error | DepositToVault (disabled) |
| TestTreasuryVaultDisabledWithdraw_FailsWithError | ⭐⭐⭐ | Disabled withdraw returns error | WithdrawFromVault (disabled) |
| TestTreasuryVaultDisabledTransfer_FailsWithError | ⭐⭐⭐ | Disabled transfer returns error | TransferFromVault (disabled) |
| TestTreasuryVaultDisabledTransferVaultBalance_FailsWithError | ⭐⭐⭐ | Disabled transferBalance returns error | TransferVaultBalance (disabled) |
| TestTreasuryVaultIdempDeposit_DifferentKeysAreIndependent | ⭐⭐⭐⭐ | Different keys execute independently | IdempDepositToVault x2 (different keys) |
| TestTreasuryDeployment_IncludesIdempFacet | ⭐⭐⭐⭐ | Diamond has 8 vault facets | DeployTreasuryMechanisms |
| TestFundAccountSaga_UsesIdempotentDeposit | ⭐⭐⭐⭐ | Fund account saga works with idemp ops | Full saga |
| TestCreateInvestorOrder_UsesIdempotentTransfer | ⭐⭐⭐⭐ | Investor order saga works with idemp ops | Full saga |
| TestTreasuryVaultIdempDeposit_InsufficientBalance | ⭐⭐⭐ | Insufficient balance still fails | IdempDepositToVault (error) |
| TestTreasuryVaultIdempWithdraw_InsufficientBalance | ⭐⭐⭐ | Insufficient vault balance still fails | IdempWithdrawFromVault (error) |

**Prerequisites**: Full treasury infrastructure (E1/E2 executors, Lattice facets, legal structure, treasury mechanisms with Erc20VaultIdempFacet)
```

Also add Category 40 to the main CLAUDE.md E2E category table:

```
| 40 | ⭐⭐⭐⭐ | Idempotent Treasury Vault | `laser-e2e-ethbc-cat40` |
```

---

## Phase 11: N/A — No Migration Needed

Not in production yet. All new treasury Diamonds are deployed with 7 vault facets (Erc20VaultFacet removed from Lattice deploy in rev-21, replaced by `Erc20VaultIdempFacet`).

---

## Phase 13: DONE — Keep Both Facets on Treasury Diamond

Both `Erc20VaultFacet` and `Erc20VaultIdempFacet` are deployed to the treasury Diamond:
- **`Erc20VaultFacet`**: Provides query functions (`getErc20VaultBalance`, etc.). Non-idempotent mutations are disabled at the LASER level (see `ethbc_diamond_contract.go` lines 1842-1854).
- **`Erc20VaultIdempFacet`**: Provides idempotent mutation functions (`idempDepositToErc20Vault`, etc.).

`Erc20VaultFacet` was restored to the Lattice deploy saga and `facet_groups.go` treasury group. E2E tests updated to include both facets and pass `erc20_vault_idemp_facet_version` in saga inputs.

### 13.1 Production Code

Remove `erc20_vault_facet_version` saga input and `Erc20VaultFacet` from diamond facet lists:

1. `pkg/daemons/laseragent/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/add_vault_facets.go` — remove `erc20VaultFacetVersion` extraction (line 67), validation (line 76), and `Erc20VaultFacet:%s` from `facetSlotAddresses` (line 91)
2. `pkg/daemons/accmgr/api/v1/legal_mechanisms_post_deploy_treasury.go` — remove `Erc20VaultFacetVersion` from request struct, validation, and saga input map
3. `pkg/daemons/accmgr/trax/executors/setup_new_legal_participant/spawn_deploy_treasury.go` — remove `erc20_vault_facet_version` extraction and forwarding
4. `pkg/daemons/accmgr/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/verify_inputs.go` — remove from required inputs list
5. `docs/TODO_DEPLOY_TREASURY_LEGAL_MECHANISMS_SAGA.md` — remove `erc20_vault_facet_version` from Inputs table

### 13.2 E2E Tests

Remove `"Erc20VaultFacet"` from treasury facet name arrays and `erc20_vault_facet_version` from saga inputs:

1. `tests/e2e/laser/treasury_mechanism_deployment_test.go` — `deployTreasuryFacets()`, comment, `Erc20VaultFacetVersion` struct field, and all callers
2. `tests/e2e/laser/treasury_vault_withdraw_test.go` — `treasuryFacetNames`
3. `tests/e2e/laser/treasury_vault_links_test.go` — `treasuryFacetNames`
4. `tests/e2e/laser/treasury_stash_ops_test.go` — `treasuryFacetNames`
5. `tests/e2e/laser/treasury_vault_idemp_test.go` — `treasuryFacetNames`
6. `tests/e2e/laser/deposit_to_treasury_test.go` — `treasuryFacetNames`
7. `tests/e2e/laser/fund_account_saga_test.go` — facets list + saga input
8. `tests/e2e/laser/pacli_test.go` — `allFacets` list
9. `tests/e2e/laser/indtrxss_saga_treasurymechs_test.go` — versioned facet list, `Erc20VaultFacetVersion` struct field, input builder
10. `tests/e2e/laser/indtrxss_saga_treasurymechs_laser_test.go` — `erc20VaultFacetVersion` extraction, validation, facet slot address, step input builder
11. `tests/e2e/laser/trax_helpers_test.go` — `ensureTreasuryFacetsDeployed()` Erc20VaultFacet block + saga input
12. `tests/e2e/laser/indtrxss_saga_treasurymechs_accmgr_test.go` — required inputs list
13. `tests/e2e/laser/security_listing_deployment_test.go` — saga input
14. `tests/e2e/laser/cash_token_deployment_test.go` — saga input

---

## Phase 12: Future — AgoraEngine Event Hash (Rev-21)

When Lattice rev-21 is integrated:

**File**: `pkg/daemons/tradeidxer/laser/types.go` (EXISTING)

- Add `Hash string` field to `AgoraEngineEventResult` struct
- Use hash for event-processing deduplication in `listing_job.go`

**Not part of current implementation.** Tracked here for planning purposes.

---

## Deployment Order (Critical)

```
Step 1: Deploy Phase 1 + Phase 5 (new operations + facet deployment chain)
        Services: lasersvc, accmgr, laseragent

Step 2: Deploy new treasury Diamonds (with 7 facets including Erc20VaultIdempFacet)
        OR: Run Phase 11 migration for existing Diamonds

Step 3: Deploy Phase 2 + Phase 3 + Phase 4 + Phase 6 (disable old ops, implement idemp, switch callers)
        Services: lcmgr (lasersvc), treassvc, laseragent

        CRITICAL: Old operations MUST be disabled AT THE SAME TIME as callers switch.
        Deploy all services in Step 3 together. If lcmgr is deployed before callers switch,
        existing saga steps will hit the disabled error.
```

---

## Files Summary

| # | File | Status | Changes |
|---|------|--------|---------|
| 1 | `pkg/laser/model/operation_name.go` | EXISTING | Add 4 new idemp operation enums, comment old ones as DISABLED |
| 2 | `pkg/laser/model/operation_slot_args.go` | EXISTING | Add slot args for 4 new ops |
| 3 | `pkg/laser/router/init.go` | EXISTING | Register serializers for new ops |
| 4 | `pkg/laser/handlers/register.go` | EXISTING | Register relay + lcmgr handlers for new ops |
| 5 | `pkg/laser/handlers/diamond_lcmgr.go` | EXISTING | Map new ops → trezorMutationHandler |
| 6 | `pkg/laser/executors/default_executor.go` | EXISTING | Add slot IID resolution cases for new ops |
| 7 | `pkg/daemons/lcmgr/ethbc_diamond_contract.go` | EXISTING | Add idemp ABI, 4 new methods, disable old 4 cases |
| 8 | `pkg/daemons/lcmgr/trezor_erc20_contract.go` | EXISTING | Add 4 new idemp methods, disable old 4 cases |
| 9 | `pkg/daemons/lcmgr/contract_store.go` | EXISTING | Add idempotency key tracking interface |
| 10 | `pkg/daemons/lcmgr/contract_store_pgsql.go` | EXISTING | Implement idempotency key methods |
| 11 | `pkg/daemons/lcmgr/contract_store_inmem.go` | EXISTING | Implement in-memory idempotency tracking |
| 12 | `deploy/k8s/init/init_trezor_erc20_pgsql.sql` | EXISTING | Add trz_erc20_idempotency_keys table |
| 13 | `pkg/daemons/accmgr/api/v1/legal_mechanisms_post_deploy_treasury.go` | EXISTING | Add `erc20_vault_idemp_facet_version` field + validation |
| 14 | `pkg/daemons/accmgr/trax/executors/.../verify_inputs.go` | EXISTING | Add facet version to validation list |
| 15 | `pkg/daemons/accmgr/trax/executors/.../spawn_deploy_treasury.go` | EXISTING | Add facet version to sub-saga input |
| 16 | `pkg/daemons/laseragent/trax/executors/.../add_vault_facets.go` | EXISTING | Add Erc20VaultIdempFacet as 8th facet |
| 17 | `pkg/daemons/laseragent/trax/executors/.../deposit_initial_supply_to_treasury.go` | EXISTING | Switch to idemp deposit op |
| 18 | `pkg/daemons/treassvc/trax/executors/create_investor_order/laser_helpers.go` | EXISTING | Switch to idemp transfer ops |
| 19 | `pkg/daemons/treassvc/trax/executors/fund_account_with_cash_tokens/mint_tokens_if_needed.go` | EXISTING | Switch to idemp deposit op |
| 20 | `pkg/daemons/treassvc/trax/executors/fund_account_with_cash_tokens/transfer_from_clearing_to_destination.go` | EXISTING | Switch to idemp transfer op |
| 21 | `pkg/daemons/lcmgr/api/v1/api_integration_pgsql_test.go` | EXISTING | Update test op names, add disabled + idemp tests |
| 22 | `tests/e2e/laser/treasury_vault_idemp_test.go` | NEW | 18 E2E tests (green/red paths, key reuse, disabled ops) |
| 23 | `tests/e2e/laser/erc20_helpers_test.go` | EXISTING | Switch 5 helper functions to idemp operations |
| 24 | `tests/e2e/laser/indtrxss_common_test.go` | EXISTING | Switch 3 operation references to idemp variants |
| 25 | `tests/e2e/laser/indtrxss_saga_fundaccount_treassvc_test.go` | EXISTING | Switch 2 operation references to idemp variants |
| 26 | `tests/e2e/laser/executor_external_call_test.go` | EXISTING | Switch 1 operation reference to idemp variant |
| 27 | `tests/e2e/laser/init_fund_account_saga.sql` | EXISTING | Update comment references |
| 28 | `tests/e2e/laser/deposit_to_treasury_test.go` | EXISTING | Skip tests with message pointing to Cat 40 |
| 29 | `tests/e2e/laser/treasury_vault_withdraw_test.go` | EXISTING | Skip tests with message pointing to Cat 40 |
| 30 | `docs/TODO_DEPLOY_TREASURY_LEGAL_MECHANISMS_SAGA.md` | EXISTING | Add idemp facet version, update step 12 |
| 31 | `docs/SUMMARY-FOR-AGENT.md` | EXISTING | Add idempotent vault operations note |
| 32 | `docs/E2E_TEST_CATALOG.md` | EXISTING | Add Category 40 entries |
| 33 | `Makefile` | EXISTING | Add Category 40 pattern |
| 34 | `CLAUDE.md` | EXISTING | Add Category 40 to E2E category table |

---

## Key References

- **Erc20VaultIdempFacet Go binding**: `contracts/go/contracts/facets/_trezor/erc20-vault/erc20vaultidempfacet/Erc20VaultIdempFacet.go`
  - Methods: `IdempDepositToErc20Vault`, `IdempWithdrawFromErc20VaultTo`, `IdempTransferFromErc20Vault`, `IdempTransferErc20VaultBalance`, `IdempSetErc20VaultAllowance`
  - Query: `IsErc20VaultIdempKeyUsed(idempotencyKey [32]byte) (bool, error)`
- **idempotencyKeyToBytes32**: `pkg/daemons/lcmgr/ethbc_executor_erc20_contract.go:226` — `sha256.Sum256([]byte(key))`
- **Existing EthBC vault mutations**: `pkg/daemons/lcmgr/ethbc_diamond_contract.go:2803-3254`
- **Existing RDBMS vault mutations**: `pkg/daemons/lcmgr/trezor_erc20_contract.go:282-477`
- **Treasury deployment saga**: `docs/TODO_DEPLOY_TREASURY_LEGAL_MECHANISMS_SAGA.md`
- **Vault slot links**: `docs/TODO_TREASURY_VAULT_SLOT_LINKS.md`
