# Treasury Operation Idempotency: Two-Tier Key Scheme

## Problem

Treasury operations (vault transfers, deposits, withdrawals, mints, burns) execute on-chain transactions through LASER. These operations are triggered by TRAX saga steps, which can be retried by the saga coordinator on failure or redelivery.

A single idempotent key shared between the saga layer and the on-chain contract creates two failure modes:

1. **Key collision across operations**: A saga step that performs multiple on-chain calls (e.g., mint + approve + deposit) would need distinct keys for each call. Using the saga key with manual string suffixes (`key + "-mint"`) is fragile and error-prone.

2. **Key collision between forward and compensation**: A forward transfer and its compensation reversal target the same vault. If both use the same key (or predictably derived keys), the on-chain contract may deduplicate the compensation as a replay of the forward operation.

## Solution: Two-Tier Idempotent Keys

Every treasury on-chain call now uses two separate idempotent keys:

```
┌─────────────────────────────────────────────────┐
│  Saga Layer (TRAX)                              │
│  sagaIdempKey = step-level key from coordinator │
│  Used for: mutate_id, saga dedup, logging       │
├─────────────────────────────────────────────────┤
│  Treasury Layer (On-Chain Contract)             │
│  treasuryOpIdempKey = builder-derived key       │
│  Used for: ATS IdempotencyKey argument,         │
│            on-chain bytes32 dedup               │
└─────────────────────────────────────────────────┘
```

### Key Flow

```
actusvc (ERP arrives)
  │
  ├─ Derives treasuryOpsBaseIdempKey from ERP hash
  │  e.g. "erp-abc123-clearance-idempkey"
  │
  ├─ Passes it in saga payload as "treasury_ops_base_idempkey"
  │
  ▼
accmgr (postHandleFixExecReport)
  │
  ├─ Forwards treasury_ops_base_idempkey in sagaInput
  │
  ▼
handle_fill_fix_exec_report saga
  │
  ├─ unlock_order_stash sub-saga (forwards key in subSagaInput)
  │   └─ transfer_stash executor
  │       ├─ sagaIdempKey = TRAX step key (saga dedup)
  │       └─ treasuryOpIdempKey = builder.For(UnlockStash) (on-chain dedup)
  │
  └─ deposit_fill_proceeds sub-saga (forwards key in subSagaInput)
      └─ fund_account_with_cash_tokens saga
          ├─ mint_tokens_if_needed executor
          │   ├─ builder.For(FundMint)     → mint call
          │   ├─ builder.For(FundApprove)  → approve call
          │   └─ builder.For(FundDeposit)  → deposit call
          │
          └─ transfer_from_clearing_to_destination executor
              └─ builder.For(FundTransfer) → vault transfer call
```

### Builder Usage

The `pkg/treasury/idempkey` package provides a type-safe builder:

```go
import "qomet.tech/agora/daemons/pkg/treasury/idempkey"

// Extract the base key from saga input (fails loudly if missing)
base, err := idempkey.RequireFromInput(input, "step_name")

// Derive operation-specific treasury keys
lockKey := idempkey.New(base).For(idempkey.LockValue)
lockCompKey := idempkey.New(base).For(idempkey.LockValueComp)

// Pass both keys to the transfer helper
executeTransferVaultBalance(ctx, executorIid,
    sagaIdempKey,    // saga-level dedup
    lockKey,         // on-chain dedup
    ...)
```

### Available Suffixes

| Suffix | Operation | Used By |
|--------|-----------|---------|
| `LockValue` | Lock order volume (stash 0 → stash N) | create_investor_order |
| `LockValueComp` | Compensation: unlock volume | create_investor_order |
| `FeeTransfer` | Fee transfer (investor → clearing) | create_investor_order |
| `FeeTransferComp` | Compensation: return fee | create_investor_order |
| `UnlockStash` | Unlock stash (stash N → stash 0) | unlock_order_stash |
| `UnlockStashComp` | Compensation: re-lock stash | unlock_order_stash |
| `FundTransfer` | Vault-to-vault transfer | fund_account_with_cash_tokens |
| `FundMint` | Mint tokens to clearing | fund_account_with_cash_tokens |
| `FundApprove` | Approve treasury for deposit | fund_account_with_cash_tokens |
| `FundDeposit` | Deposit to treasury vault | fund_account_with_cash_tokens |
| `AuthorizedInstrTransfer` | Vault-to-vault transfer | fund_account_with_authorized_instrument |
| `AuthorizedInstrMint` | Mint authorized instrument tokens | fund_account_with_authorized_instrument |
| `AuthorizedInstrApprove` | Approve treasury for deposit | fund_account_with_authorized_instrument |
| `AuthorizedInstrDeposit` | Deposit to treasury vault | fund_account_with_authorized_instrument |
| `WithdrawTransfer` | Vault-to-vault transfer | withdraw_cash_tokens_from_account |
| `WithdrawFromVault` | Withdraw from treasury vault | withdraw_cash_tokens_from_account |
| `WithdrawBurn` | Burn withdrawn tokens | withdraw_cash_tokens_from_account |
| `Erc20Transfer` | ERC20 facet transfer | transfer_authorized_instrument (laseragent) |
| `Erc20TransferComp` | Compensation: reverse transfer | transfer_authorized_instrument (laseragent) |

## LASER Mutation Request Fields

Every LASER mutation for treasury ops now carries both keys:

```json
{
  "mutate_id": "mut_cio_lock_order_volume_{sagaIdempKey}",
  "saga_idempotency_key": "{sagaIdempKey}",
  "treasury_op_idempotency_key": "{treasuryOpIdempKey}",
  "from_slot_address": "...",
  "to_slot_address": "...",
  "call_data": { ... }
}
```

- `mutate_id`: Unique identifier for the LASER mutation, derived from saga key.
- `saga_idempotency_key`: Tracks which saga step triggered this mutation (for logging/audit).
- `treasury_op_idempotency_key`: The actual on-chain idempotency key passed to the smart contract's `IdempotencyKey` argument. This is what prevents double execution at the contract level.

## What Happens on Retry

### Saga step retried (same sagaIdempKey)

The TRAX coordinator redelivers the same step. The executor:
1. Extracts the same `treasury_ops_base_idempkey` from input (deterministic).
2. Derives the same `treasuryOpIdempKey` via the builder (deterministic).
3. Submits the same on-chain call — the contract recognizes the `IdempotencyKey` and returns the cached result without re-executing.

### Compensation after forward execution

The compensation step uses a different suffix (e.g., `LockValueComp` vs `LockValue`), producing a distinct `treasuryOpIdempKey`. The contract treats it as a new operation and executes the reversal.

### Multiple on-chain ops in one saga step

Each operation uses a different suffix (e.g., `FundMint`, `FundApprove`, `FundDeposit`), so each gets its own unique `treasuryOpIdempKey`. No collisions possible because suffixes are type-safe constants — not hand-crafted strings.

## Scope

This scheme applies to **treasury vault value operations** only:
- Vault transfers (TransferFromVault, TransferVaultBalance)
- Deposits (DepositToVault)
- Withdrawals (WithdrawFromVault)
- Mints and burns
- ERC20 facet transfers

It does **not** apply to:
- Contract deployment sagas (deploy_lattice_facets, deploy_*_legal_mechanisms)
- Permission grants (grant_*_perm)
- Configuration operations (initialize_*, configure_*)
- Orderbook operations (create_direct_order, cancel_direct_order)

These are one-time infrastructure operations where saga-level idempotency is sufficient.

## Adding New Treasury Operations

When adding a new treasury on-chain call:

1. Add a new `OpSuffix` constant to `pkg/treasury/idempkey/builder.go`.
2. Add it to the `TestBuilder_UniqueSuffixes` test to verify no collisions.
3. In the executor, call `idempkey.RequireFromInput(input, "step_name")` to get the base key.
4. Derive the treasury key: `idempkey.New(base).For(idempkey.YourNewSuffix)`.
5. Pass both `sagaIdempKey` and `treasuryOpIdempKey` to the LASER mutation helper.
6. If the operation has a compensation path, add a `*Comp` suffix variant.
7. Ensure the saga submitter includes `treasury_ops_base_idempkey` in the saga input.
