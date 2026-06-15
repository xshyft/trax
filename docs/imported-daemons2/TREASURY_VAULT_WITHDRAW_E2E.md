# Treasury Vault Withdraw E2E Tests

## Overview

This document describes the E2E tests for treasury vault withdrawal operations. These tests verify the `withdrawFromErc20VaultTo` functionality on the Trezor (Treasury) contract.

## Architecture Background

### Token Flow After Instrument Authorization

When a token is authorized via the `process_new_instrument_authorization` saga with treasury enabled:

1. **ERC20 Diamond is deployed** - A new ERC20 token contract
2. **Initial supply is minted** - Tokens minted to the Clearing Account's ETH address
3. **Tokens deposited to Treasury vault** - Via `depositToErc20Vault` on Trezor contract

**Result after authorization:**
- Clearing Account ETH address: ERC20 balance = **0**
- Clearing Account vault entry in Treasury: **N tokens** (where N = minted tokens)

### Withdrawing from Vault

To move tokens from vault back to an ERC20 balance, use `withdrawFromErc20VaultTo`:

```solidity
function withdrawFromErc20VaultTo(
    uint256 ledgerId,        // Ledger ID (default: 1)
    address callerAccount,   // Must match msg.sender (vault owner)
    address erc20,           // ERC20 token contract address
    address toAccount,       // Destination address for tokens
    uint256 amount,          // Amount to withdraw
    bytes memory data        // Optional data (usually empty)
) external;
```

**Key constraint:** The `fromVault` is implicitly `msg.sender`. Only the vault owner can withdraw from their own vault.

### LASER Operation

The LASER operation for this is `TrezorErc20WithdrawFromVault` with these slot arguments (translated from E1 seeds to E2 ETH addresses):
- `caller` - Vault owner (must be msg.sender)
- `erc20_addr` - ERC20 token contract address
- `from_vault` - Source vault address (same as caller for owner withdrawal)
- `to_account` - Destination account for tokens

## Test Categories

These tests belong to **Category 11** (Deposit & Treasury) in the E2E test catalog.

## Test Scenarios

### 1. Withdraw Full Balance from Vault (`TestTreasuryVaultWithdraw_FullBalance`)

**Setup:**
1. Create Legal Structure with Treasury
2. Issue instrument with treasury deposit (N tokens)
3. Verify: Clearing Account vault balance = N, ERC20 balance = 0

**Test:**
1. Execute `withdrawFromErc20VaultTo` for full balance N
2. Verify: Clearing Account vault balance = 0
3. Verify: Clearing Account ERC20 balance = N

### 2. Withdraw Partial Balance from Vault (`TestTreasuryVaultWithdraw_PartialBalance`)

**Setup:**
1. Create Legal Structure with Treasury
2. Issue instrument with treasury deposit (10,000,000 tokens)

**Test:**
1. Execute `withdrawFromErc20VaultTo` for 3,000,000 tokens
2. Verify: Vault balance = 7,000,000
3. Verify: ERC20 balance = 3,000,000
4. Execute second withdrawal for 2,000,000 tokens
5. Verify: Vault balance = 5,000,000
6. Verify: ERC20 balance = 5,000,000

### 3. Withdraw to Self (Vault Owner) (`TestTreasuryVaultWithdraw_ToSelf`)

**Test:**
1. Caller = Clearing Account (vault owner)
2. toAccount = Clearing Account (same as caller)
3. Verify tokens move from vault to own ERC20 balance

### 4. Withdraw to Different Account (`TestTreasuryVaultWithdraw_ToDifferentAccount`)

**Setup:**
1. Create recipient account with LASER slot

**Test:**
1. Caller = Clearing Account (vault owner)
2. toAccount = Recipient Account (different from caller)
3. Verify: Clearing Account vault balance decreases
4. Verify: Recipient Account ERC20 balance increases
5. Verify: Clearing Account ERC20 balance unchanged (was 0, stays 0)

### 5. Withdraw with Insufficient Balance - Should Fail (`TestTreasuryVaultWithdraw_InsufficientBalance`)

**Setup:**
1. Issue instrument with 1,000,000 tokens in vault

**Test:**
1. Attempt to withdraw 2,000,000 tokens (more than vault balance)
2. Verify: Transaction fails/reverts
3. Verify: Vault balance unchanged

### 6. Withdraw by Non-Vault-Owner - Should Fail (`TestTreasuryVaultWithdraw_NonOwner`)

**Setup:**
1. Create Clearing Account with tokens in vault
2. Create separate Attacker Account

**Test:**
1. Attacker attempts `withdrawFromErc20VaultTo` on Clearing Account's vault
2. Verify: Transaction fails (msg.sender != vault owner)
3. Verify: Clearing Account vault balance unchanged

### 7. Multiple Sequential Withdrawals (`TestTreasuryVaultWithdraw_Sequential`)

**Setup:**
1. Issue instrument with 10,000,000 tokens in vault

**Test:**
1. Withdraw 1,000,000 tokens
2. Verify balances
3. Withdraw 2,000,000 tokens
4. Verify balances
5. Withdraw 3,000,000 tokens
6. Verify balances
7. Withdraw remaining 4,000,000 tokens
8. Verify final state: vault = 0, ERC20 = 10,000,000

### 8. Withdraw After Previous Partial Withdrawal (`TestTreasuryVaultWithdraw_AfterPartial`)

**Setup:**
1. Issue instrument with 5,000,000 tokens
2. Withdraw 2,000,000 tokens (partial)

**Test:**
1. Attempt to withdraw 4,000,000 tokens (exceeds remaining 3,000,000)
2. Verify: Transaction fails
3. Withdraw exactly 3,000,000 tokens
4. Verify: Succeeds, vault now empty

## Helper Functions Required

### `withdrawFromTreasury`

```go
// withdrawFromTreasury executes a withdrawFromErc20VaultTo operation via LASER
func withdrawFromTreasury(
    t *testing.T,
    e1Iid string,                    // E1 executor IID
    trezorSlotAddress string,        // Treasury contract slot address (E1)
    callerSlotAddress string,        // Vault owner slot address (E1) - must be msg.sender
    erc20ContractAddress string,     // ERC20 token contract address (0x... or E1 slot)
    toAccountSlotAddress string,     // Destination for withdrawn tokens (E1)
    amount string,                   // Amount to withdraw
) string // Returns tx_hash
```

### `queryVaultBalance`

```go
// queryVaultBalance queries the ERC20 vault balance for an account
func queryVaultBalance(
    t *testing.T,
    e1Iid string,                    // E1 executor IID
    trezorSlotAddress string,        // Treasury contract slot address
    vaultAddress string,             // Vault owner address to query
    erc20Address string,             // ERC20 token contract address
    stash int,                       // Stash index (usually 0)
) string // Returns balance as string
```

## Integration with Distribution Tests

Once these tests pass, the distribution tests should be updated to use the proper treasury flow:

1. **Issue instrument** with treasury deposit enabled
2. **Withdraw from treasury** to holder account
3. **Distribute** from holder to recipients
4. **Verify** balances at each step

This is the standard treasury flow approach.

## Makefile Integration

Add to `E2E_CAT11_PATTERN`:
```makefile
E2E_CAT11_PATTERN := ... |TestTreasuryVaultWithdraw
```

## Related Documentation

- [docs/ERC20_ARCHITECTURE.md](ERC20_ARCHITECTURE.md) - ERC20 token architecture
- [docs/LASER_ARCHITECTURE.md](LASER_ARCHITECTURE.md) - LASER execution framework
- [docs/E2E_TEST_CATALOG.md](E2E_TEST_CATALOG.md) - Full E2E test catalog
- [docs/DIAMOND_OVERVIEW.md](DIAMOND_OVERVIEW.md) - Diamond proxy pattern
