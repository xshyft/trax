# TODO — `treasury_asset_balance_transfer` saga; reuse for Withdraw + Lock + Unlock end-to-end

> **Status**: PHASE 1 LANDED IN CODE 2026-05-11 — deploy-time saga_templates row update + Phase 2 (prtagent proto) + Phase 3 UnlockCash + Phase 4 (mini-broker) + Phase 5 (e2e/docs sweep) still ahead.
> **Created**: 2026-05-11
> **Short ID**: `TABT`
> **Authoring rules**: per `feedback_phased_todo_authoring.md` (established header + phase shape; bake in "ask `kam` liberally") and `feedback_pre_production_no_backcompat.md` (no shims, atomic per-surface flips)
> **Driving feedback**: kam — "withdraw saga can be reused for lock unlock, but just it operates on the same vault, diff stashes, it can be renamed to something else that represents this transfer-between-stashes nature other than withdrawal or anything else"
> **Companion to**:
> - `TODO_TREASURY_STASH_OPERATIONS.md` (STASHOPS) — defines `stash.DeriveIndex` algorithm + the broader stash semantics. **Phase 1 LANDED 2026-05-17** (keccak256[:8] → top-63-bits → int63; rejects on the ~2^-63 LIQUID-collision case). TABT now serves arbitrary non-LIQUID, non-numeric seeds end-to-end.
> - `TODO_EXECUTION_IDEMPOTENCY_SEED.md` (EXIDS) — defines the wire fields `execution_idempotency_seed` + `treasury_stash_derivation_seed`. TABT consumes both verbatim.
> **Surfaces touched** (estimate):
> - RENAME saga template `withdraw_cash_tokens_from_account` → `treasury_asset_balance_transfer` (`pkg/daemons/treassvc/trax/executors/` + `pkg/daemons/accmgr/trax/executors/`).
> - GENERALIZE saga inputs to accept source/destination `(account_iid, stash_seed)`, the new `finalize_to_erc20` flag, and a deterministic vault-lock acquired BEFORE the transfer.
> - SPLIT `accmgr` REST: new `/cash-tokens/{currency}/asset-balance-transfer` POST; replace the existing `/withdraw` POST (no back-compat shim).
> - ADD `LockCash` + `UnlockCash` to prtagent v1 proto + handler; ADD `amount` field to `UnlockCashRequest` in brktrdapi proto too.
> - REPLACE `LockCash` + `UnlockCash` stubs in brktrdsvc.
> - EXTEND `stash.DeriveIndex` to short-circuit numeric seeds in `[0, 2^64−1]` directly (no hashing) — applies BEFORE the existing `LIQUID` short-circuit doesn't (LIQUID literal stays a separate fast-path).
> - ADD `pkg/cache.KeyedLockStore` + `PgsqlKeyedLockStore` — generic Postgres-backed distributed lock primitive (TTL + steal-on-expire). Table `shared.distributed_locks`. TABT is the first consumer; future callers compose their own keys. See O11 for the design.
> - PORT EXIDS + stash widgets to mini-broker (separate submodule).
> - WIRE Lock/Unlock buttons into mini-broker portfolio + thread EXIDS + stash through every mutating mini-broker flow.
> - E2E + docs sweep per `feedback_saga_proto_changes_full_sweep.md`.
> **Pre-deps**:
> - STASHOPS Phase 1 — LANDED 2026-05-17. `stash.DeriveIndex` is real (keccak256-based, int63 output). Non-LIQUID, non-numeric seeds resolve end-to-end at `tabt_acquire_vault_lock`.
> - Burn-bypass story (BURNER_ROLE or allowance) — only needed if any caller flips `burn_after_withdraw=true`. Off by default after commit `6f5c0fc19`; not blocking TABT itself.

---

## ⚠ Notes for the executing agent

**Phase 0 is CLOSED** — every O1–O12 question ratified by kam on 2026-05-11. See "Phase 0 — Decisions" below for the authoritative answers. Honor them verbatim; if you find yourself reaching for a different design call, stop and re-confirm with kam BEFORE deviating.

**Ask `kam` liberally** beyond Phase 0 too:
- Whenever a step name or saga input key looks ambiguous — name it once, ratify it with kam, and use it everywhere.
- Whenever a brktrdsvc / prtagent handler differs from its peer — these handlers MUST stay in lockstep (same validators, same DispatchRegistry posture, same saga inputs).
- Whenever the mini-broker port deviates from the common_ui widget — mini-broker has its own Flutter env (use whatever is normal there); the port mirrors the trade_bench behavior but uses mini-broker's idioms.

**Pre-production project — no back-compat shims** (memory `feedback_pre_production_no_backcompat.md`). When `withdraw_cash_tokens_from_account` is renamed → all callers update in the same commit. No alias template. No fallback path. Per kam (O6): "just deploy over the previous one — we are not in production." No drain step required.

**One saga template, three flows** — kam's explicit design call. Withdraw, Lock, and Unlock all converge on `treasury_asset_balance_transfer` via gateway pre-filling inputs differently. Deposit currently stays on `fund_account_with_cash_tokens` (different shape: mint → approve → deposit-to-vault). Do NOT collapse Deposit into TABT without a separate kam-blessed design — out of scope here.

**Stash safety via locks, not skips** (kam, 2026-05-11) — every step in the saga ALWAYS runs. Parallel-transfer safety comes from a deterministic lock acquired at the start of the saga, keyed on `(account_iid, treasury_deploy_id, exec_runtime_name, vault_address, source_stash_number, destination_stash_number)`. No other transfer can hold a lock that overlaps with this set while this saga is mid-flight.

---

## Overview

### Today (state at 2026-05-11)

**`WithdrawCash`** (both prtagent v1 and brktrdsvc) — submits saga `withdraw_cash_tokens_from_account` via the same accmgr REST. After commits `f83412f9b` + `6f5c0fc19`:
- Signer = broker's clearing slot (not investor's).
- Movement step uses `TrezorErc20IdempTransferVaultBalance` (TVB) — RAC-gated, works across vaults.
- Optional `burn_after_withdraw` flag (default `false`) gates the `wcfa_withdraw_and_burn` finalization sub-step.
- Source stash = `LIQUID` always. Destination = clearing's `LIQUID`.

**`LockCash` / `UnlockCash`** — brktrdsvc returns `Unimplemented`; prtagent v1 doesn't expose the RPC at all. `UnlockCashRequest` has no `amount` field today.

**Frontend**:
- `broker_trading_pages` (trade_bench consumer): EXIDS field + stash field exist; cash-flow modal handles all 4 modes; Lock/Unlock buttons surface in the portfolio toolbar; Lock/Unlock currently bubble the `Unimplemented` error verbatim via `ASuiteDialog.error`.
- `mini-broker`: no EXIDS / stash widgets; ad-hoc seed strings; no Lock/Unlock buttons.

**Stash seed resolution** (post-STASHOPS Phase 1, landed 2026-05-17):
1. `seed == "LIQUID"` → `0` (existing fast-path).
2. `seed` parses as an integer in `[0, 2^64−1]` → use the number directly (NEW per kam, 2026-05-11).
3. Otherwise → `DeriveIndex(seed)` (STASHOPS Phase 1 algorithm).

### Target (after TABT lands)

ONE saga template `treasury_asset_balance_transfer` with the inputs below. Three gateway-side dispatchers (`WithdrawCash`, `LockCash`, `UnlockCash`) pre-fill those inputs differently and submit. The saga doesn't know the operation's name — only the source/destination `(vault, stash)` pair, the amount, the EXIDS seed, and whether to finalize to ERC20.

```
┌──────────────────┐         ┌──────────────────┐         ┌──────────────────┐
│ WithdrawCash RPC │         │   LockCash RPC   │         │  UnlockCash RPC  │
│  (prtagent +     │         │  (prtagent +     │         │  (prtagent +     │
│   brktrdsvc)     │         │   brktrdsvc)     │         │   brktrdsvc)     │
└────────┬─────────┘         └────────┬─────────┘         └────────┬─────────┘
         │                            │                            │
   client supplies                client supplies              client supplies
     source_stash                  destination_stash             source_stash + amount
     amount                        amount                        (amount optional?
   gateway defaults                gateway defaults              see O9-amended)
     dst_acct = clearing             dst_acct = source             dst_acct = source
     dst_stash = LIQUID              src_stash = LIQUID            dst_stash = LIQUID
     finalize_to_erc20 = false       finalize_to_erc20 = false     finalize_to_erc20 = false
     (was true pre-2026-05-17 —
      flipped per O13 below;
      gateway is pure
      vault→vault now)
         │                            │                            │
         └────────────────────────────┴────────────────────────────┘
                                      │
                              ┌───────▼────────┐
                              │  treasury_     │
                              │  asset_balance │
                              │  _transfer saga│
                              │   (TRAX)       │
                              └────────────────┘
```

---

## Phase 0 — Decisions (some ratified; remaining open)

### ✅ O1. Final saga template name — RATIFIED 2026-05-11

**Decision**: `treasury_asset_balance_transfer`. Short ID `TABT`.

### ✅ O2. Step name prefix — RATIFIED 2026-05-11

**Decision**: `tabt_`. Concrete step names (still subject to kam's eye on individual names):
- `tabt_query_source_balance` (was `wcfa_query_account_balance`)
- `tabt_acquire_vault_lock` (NEW per kam — locking guard before any movement)
- `tabt_transfer_between_stashes` (was `wcfa_transfer_to_clearing`; ALWAYS runs)
- `tabt_finalize_to_erc20` (was `wcfa_withdraw_and_burn`; ALWAYS runs, behaviour gated by `finalize_to_erc20` input — see O5-amended)
- `tabt_verify_balances` (was `wcfa_verify_post_transfer_balances`; ALWAYS runs; also performs the stash-index derivation per kam, see O5-amended)
- `tabt_release_vault_lock` (NEW per kam — release at the end whether the saga commits or compensates)

### ✅ O3. Source vs destination stash seed input — RATIFIED 2026-05-11

**Decision**: Saga has BOTH `source_stash_derivation_seed` AND `destination_stash_derivation_seed` as inputs. The gRPC handler decides what the broker sends on the wire and fills in defaults for the other side.

Per-RPC defaults:
- `WithdrawCash`: broker supplies `source_stash_derivation_seed` (default `LIQUID`); gateway sets `destination_stash_derivation_seed = "LIQUID"`.
- `LockCash`: broker supplies `destination_stash_derivation_seed` (REJECTS `LIQUID` per D14.4); gateway sets `source_stash_derivation_seed = "LIQUID"`.
- `UnlockCash`: broker supplies `source_stash_derivation_seed` (REJECTS `LIQUID`); gateway sets `destination_stash_derivation_seed = "LIQUID"`.

### ✅ O4. `destination_account_iid` — RATIFIED 2026-05-11

**Decision**: Saga keeps `destination_account_iid` flexible (required input, but the gRPC handler decides what to populate by default).

Per-RPC defaults:
- `WithdrawCash`: gateway resolves `destination_account_iid` to the legal-structure's clearing account.
- `LockCash` / `UnlockCash`: gateway sets `destination_account_iid = source_account_iid`.

### ✅ O5. Step skip vs always-run + vault locking — RATIFIED 2026-05-11 (with kam-mandated changes)

**Decisions per kam**:

1. **Every step ALWAYS runs.** Removing the "skip when `finalize_to_erc20=false`" semantic from the prior draft.
2. **Stash-index derivation happens in `tabt_verify_balances`.** That step resolves both source and destination stash numbers from their seed strings and then verifies the on-chain balances.
3. **`tabt_finalize_to_erc20` always runs but is GATED by input.** When `finalize_to_erc20=false`, the step still executes its idempotent body but does NO on-chain ERC20 call (it records the `false` decision in result_data). When `finalize_to_erc20=true`, it performs the existing withdraw-and-burn flow (with `burn_after_withdraw` still gating the actual burn per commit `6f5c0fc19`).
4. **Parallel-transfer safety via vault locks.** A new `tabt_acquire_vault_lock` step at the head of the saga acquires a deterministic lock keyed on:
   ```
   (account_iid, treasury_deploy_id, exec_runtime_name, vault_address,
    source_stash_number, destination_stash_number)
   ```
   No other TABT saga can hold a lock with overlapping coordinates while this one is mid-flight. **Open**: lock mechanism (see ❓O11 below).

### ✅ O6. TRAX migration strategy — RATIFIED 2026-05-11

**Decision per kam**: "just deploy over the previous one — we are not in production." No drain step. Single commit that renames + ships. No alias template.

### ✅ O7. Mini-broker widget strategy — RATIFIED 2026-05-11

**Decision per kam**: "mini-broker has its own flutter env. use whatever is normal there." Concretely: clone-and-adapt — copy the widget shape into mini-broker, swap riverpod calls for mini-broker's existing state idioms (likely `provider`). Acknowledged divergence; common_ui remains the source-of-truth for trade_bench.

### ✅ O9. UnlockCash amount semantics — RATIFIED 2026-05-11 (proto change)

**Decision per kam**: "add amount field as may want to unlock less than the actual stash balance." Proto change: add `amount` to `UnlockCashRequest` in brktrdapi (and the new prtagent v1 proto added in Phase 2). When omitted by the broker, gateway defaults `amount` to the source-stash balance (saga-internal pre-query in `tabt_query_source_balance`).

### ✅ NEW — Numeric stash-seed bypass — RATIFIED 2026-05-11

**Decision per kam**: "if the seed is a numeric string between 0 and 2^64-1, we use the number form, no derivation is needed."

`stash.DeriveIndex` resolution order (post-TABT):
1. `seed == "LIQUID"` (case-sensitive, exactly 6 ASCII bytes) → `0`.
2. `seed` parses as an integer with `strconv.ParseUint(seed, 10, 64)` → use that value directly.
3. Otherwise → fall through to the STASHOPS Phase 1 hashing algorithm.

Implications:
- Brokers that want explicit stash control can pass any numeric string `"1"`, `"42"`, `"18446744073709551615"`. Skips hashing.
- The LIQUID-rejection rule on Lock/Unlock (D14.4) becomes: reject literal `"LIQUID"` only — passing `"0"` numerically still resolves to stash 0 (which is the same as LIQUID by index). **Open**: should `"0"` ALSO be rejected on Lock/Unlock paths (since it's semantically equivalent to LIQUID)? See ❓O12.

### ✅ O8. Mini-broker EXIDS history store — RATIFIED 2026-05-11

**Decision per kam**: **Local SQLite.** Mini-broker persists per-`(rpc, investor)` seed history in a local SQLite DB. Durable across app restarts; survives reinstall only if the OS preserves the app's documents directory. Same FTS-style filter behavior the trade_bench picker has.

### ✅ O10. Dashboard / runbook ownership — RATIFIED 2026-05-11

**Decision per kam**: **Same PR sweep.** Helm values, Grafana JSON, and any internal runbook update happens inside the TABT PR. No deferred cleanup. Matches the no-back-compat / atomic-deploy rule.

### ✅ O11. Vault-lock mechanism — RATIFIED 2026-05-11 (amended same day)

**Decision per kam**: **Postgres-backed distributed keyed lock with TTL.** Originally drafted as a TABT-specific `treassvc.vault_locks` table; refined the same day to a **generic** keyed-lock store in `pkg/cache`, mirroring how `pkg/cache.AcquireMultiLock` (Redis) is exposed today. TABT is the first consumer; future callers compose their own keys.

**Final shape**:

```go
// pkg/cache/pgsql_keyed_lock.go
type KeyedLockStore interface {
    Acquire(ctx, key, holderID string, ttl time.Duration) error          // ErrKeyedLockHeld on live conflict
    Release(ctx, holderID string) (int, error)                            // idempotent; deletes by holder
    Refresh(ctx, holderID string, ttl time.Duration) (int, error)         // extend expires_at
    IsHeldBy(ctx, holderID string) (bool, error)                          // diagnostic
    ReapExpired(ctx) (int, error)                                          // hygiene; optional
}

// PgsqlKeyedLockStore implements KeyedLockStore against
// shared.distributed_locks. Schema DDL owned by EnsureSchema; the
// `shared` schema namespace is created by init_shared_pgsql.sql.
const DefaultKeyedLockTTL = 5 * time.Minute
```

**Schema** (created by `PgsqlKeyedLockStore.EnsureSchema`):

```sql
CREATE TABLE IF NOT EXISTS shared.distributed_locks (
    lock_key    TEXT        NOT NULL PRIMARY KEY,
    holder_id   TEXT        NOT NULL,
    acquired_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS distributed_locks_holder_id_idx
    ON shared.distributed_locks (holder_id);
CREATE INDEX IF NOT EXISTS distributed_locks_expires_at_idx
    ON shared.distributed_locks (expires_at);
```

**Why generic + `shared`**: the lock primitive isn't TABT-specific. Any future saga / handler that needs a Postgres-backed distributed lock (because Redis isn't durable enough, or to keep saga state in one store) reuses it by composing its own `lock_key` string. Lives in `shared` next to `shared.exids_payload_registry` — same scope, same lifecycle.

**Acquire semantics — INSERT … ON CONFLICT DO UPDATE gated by expiry**:

```sql
INSERT INTO shared.distributed_locks (lock_key, holder_id, acquired_at, expires_at)
VALUES ($1, $2, NOW(), NOW() + ($3 || ' milliseconds')::INTERVAL)
ON CONFLICT (lock_key)
DO UPDATE SET holder_id = EXCLUDED.holder_id,
              acquired_at = EXCLUDED.acquired_at,
              expires_at  = EXCLUDED.expires_at
 WHERE shared.distributed_locks.expires_at <= NOW();
```

Three outcomes:
- No existing row → INSERT, lock acquired.
- Existing row, expired → DO UPDATE overwrites, lock STOLEN from the orphaned holder.
- Existing row, still live → ON CONFLICT trips, WHERE filters DO UPDATE out, RowsAffected = 0 → `Acquire` returns `ErrKeyedLockHeld`.

**TABT key composition** (callsite, `tabt_acquire_vault_lock`):

```go
lockKey := fmt.Sprintf("tabt:%s:%s:%s:%s:%d:%d",
    accountIid, treasuryDeployID, execRuntimeName, vaultAddress,
    sourceStashNumber, destinationStashNumber)
holderID := sagaInstanceID
ttl := cache.DefaultKeyedLockTTL // 5min, kam can override per-callsite
```

#### TTL ownership — who applies it (load-bearing — read carefully)

The TTL is a CALLER decision, not a store-wide default. There is no daemon-side "default for all locks". The store ships with `cache.DefaultKeyedLockTTL = 5 minutes` purely as a recommended starting point.

- **Initial TTL — applied at Acquire by the saga step that takes the lock.**
  - `tabt_acquire_vault_lock` passes `cache.DefaultKeyedLockTTL` (5 min) today. That bounds the worst-case remaining saga runtime: one TVB transfer (~30s) + 3 short query/verify steps + slack for network blips. If a later TABT change adds slow steps, the step's author bumps the TTL passed at this call.
  - Other future callers pick a TTL appropriate to THEIR operation. The package is generic; no global tuning knob.

- **Extension — applied at Refresh by any long-running step.**
  - If a step holds the lock and is taking longer than the original TTL allows, it MAY call `store.Refresh(ctx, sagaInstanceID, ttl)` mid-body to push `expires_at` forward. TABT today does NOT need Refresh; the doc string captures the pattern for whoever lands a slow step later.
  - Refresh is idempotent — calling on an already-released or stolen lock is a no-op (zero rows affected). Steps don't need to check IsHeldBy first.

- **Release — applied at Release on commit AND compensation.**
  - `tabt_release_vault_lock` calls `store.Release(ctx, sagaInstanceID)` in BOTH the `ExecuteSync` (commit) and `CompensateSync` (compensation) bodies. Single holder_id per saga → single DELETE call cleans up every key the saga held.
  - Zero rows deleted is fine (idempotent). The compensation path runs even if the saga errored before reaching Acquire — Release-on-no-rows is a no-op.

- **Reaping — applied at ReapExpired by any long-lived daemon.**
  - Optional. The steal-on-acquire path already reclaims expired rows for correctness. ReapExpired is hygiene: keeps the table small over time so SELECTs stay fast.
  - Recommendation: wire from `treassvc` (or `traxctrl`, since lock lifecycle aligns with saga lifecycle) with a 1-minute ticker. ReapExpired holds no lock itself; safe to run concurrently with Acquire/Release.

- **What if Acquire's DB write succeeds but the network reply is lost?**
  - The row is in the table. Treat the operation as Acquired — retries will hit DO UPDATE on the (now-present) row, but the WHERE-clause keeps the existing holder live until `expires_at <= NOW()`. Effectively: the second Acquire call returns ErrKeyedLockHeld until the first holder's TTL expires. To make a same-saga retry idempotent, the saga step uses TRAX's existing per-step idempotency (the step runs at most once successfully; on retry GetIdempotentKeyExecutionStatus returns Completed and the step body doesn't re-run Acquire).

- **What if Release's DB write fails?**
  - The row stays. TTL kicks in: `expires_at` passes, the next Acquire on the same key steals it. No operator intervention needed in the common case. Operators CAN run ReapExpired manually for immediate cleanup if they want.

- **What if the holding pod crashes between Acquire and Release?**
  - Same as Release failure — row stays until TTL expires. Same steal-on-acquire mitigation. Pick a TTL that bounds your worst-case scheduled downtime + retry window.

Tests cover: Acquire on empty table, Acquire returning ErrKeyedLockHeld on live conflict, Acquire stealing an expired row, Release-idempotency on no-row, Refresh extending `expires_at`, ReapExpired count.

### ✅ O12. Numeric `"0"` rejection — RATIFIED 2026-05-11

**Decision per kam**: **Reject both `"LIQUID"` AND numeric `"0"` anywhere the liquid spendable stash cannot be specified.** Broader than just Lock/Unlock — the validator checks the *resolved stash index*. If the rule "LIQUID disallowed" applies at any callsite, numeric `"0"` is disallowed too.

Implementation: `exids.MustValidateStashSeedOrStatusErr(seed, allowLiquid=false)` resolves the seed via the same numeric-bypass / LIQUID-short-circuit / DeriveIndex pipeline that the saga uses, then rejects if the resolved index is 0. The validator currently rejects the literal `"LIQUID"` only — extend it to also reject any numeric form that resolves to 0.

### ✅ O13. Gateway WithdrawCash semantics — RATIFIED 2026-05-17

**Driving directive (kam, 2026-05-17)**:

> Withdraw cash (clearing, target, from_stash, amount): It checks the TV[from_stash] balance, if enough, it transfers "amount" from TV[from_stash] to clearing TV[0]. NO TRANSFER TO ACCOUNT OR BURN. IF THEY EXIST, MAKE THEM OPTIONAL USING FLAGS. WHEN CALLED FROM grpc impls, THEY DO AS IT IS MENTIONED HERE.

**Decision**: Gateway-driven `WithdrawCash` (prtagent v1 + brktrdsvc) is a **pure vault→vault transfer** — TV[from_stash] → clearing TV[0]. No on-chain withdraw-to-ERC20-account, no burn. The TABT saga keeps both `finalize_to_erc20` and `burn_after_withdraw` as optional inputs for admin / manual callers that still need the full ERC20 cleanup; the gateway helpers always submit them as `false`.

**Conceptual model (post-O13)**:

| RPC          | Source                  | Destination              | Notes                                  |
|--------------|-------------------------|--------------------------|----------------------------------------|
| DepositCash  | clearing ACCOUNT (mint→approve→deposit if clearing TV[0] insufficient) → clearing TV[0] | target TV[0]            | Saga = `fund_account_with_cash_tokens` |
| WithdrawCash | target TV[from_stash]   | clearing TV[0]           | Saga = `treasury_asset_balance_transfer`, `finalize_to_erc20=false` |
| LockCash     | target TV[0] (LIQUID)   | target TV[to_stash]      | Saga = `treasury_asset_balance_transfer`, `finalize_to_erc20=false` |
| UnlockCash   | target TV[from_stash]   | target TV[0] (LIQUID)    | Saga = `treasury_asset_balance_transfer`, `finalize_to_erc20=false` |

**Implementation footprint** (landed in the same change):

1. `pkg/daemons/prtagent/impl/v1/grpc/investor.go` — `withdrawCashTokensFromAccount` helper sends `finalize_to_erc20: false` (was `true`). Comment block above the request body updated.
2. `pkg/daemons/brktrdsvc/impl/v1/grpc/cash.go` — `WithdrawCash` handler calls `withdrawCashTokensFromAccount(..., false /*finalizeToErc20*/)` (was `true`). Comment block above the call site updated.
3. Unit tests covering the gateway's saga-submission shape:
   - `pkg/daemons/prtagent/impl/v1/grpc/investor_test.go` — `TestWithdrawCash_SagaSubmissionSkipsBurnAndAccountWithdraw`.
   - `pkg/daemons/brktrdsvc/impl/v1/grpc/cash_test.go` — `TestBrk_WithdrawCashHelper_PassesFinalizeAndBurnAsFalse`.
4. cat37 e2e header (`tests/e2e/laser/prtagent_cash_flow_validation_e2e_test.go`) documents the new gateway invariant + points at the unit tests for the saga-shape assertion.
5. CLAUDE.md brktrdsvc + prtagent daemon blurbs updated to drop "WithdrawCash burns" wording.

**Saga capability NOT removed**: the `tabt_finalize_to_erc20` step body still honors the input flag. Direct accmgr REST callers (admin tooling) can still submit `finalize_to_erc20=true` if they need the on-chain ERC20 cleanup. No saga code deleted, no proto changed.

**What this does NOT cover**: a funded gateway-driven WithdrawCash happy-path e2e test asserting on-chain "vault TV[seed] decreased, clearing TV[0] increased, clearing ERC20 ACCOUNT balance UNCHANGED, no burn." Tracked as a deferred follow-up — needs a fresh test that wires up a funded investor through the CIO infrastructure. The unit tests cover the saga-input shape; cat11 / cat40 cover the on-chain side of TABT in saga-direct mode.

---

## Phase 1 — Backend rename + generalize

**Pre-deps**: All Phase 0 questions closed (O8, O10, O11, O12 still open). STASHOPS Phase 1 (`DeriveIndex` real impl) merged 2026-05-17 — arbitrary string seeds work end-to-end.

**Files touched**:

1. Saga executor package:
   - `pkg/daemons/treassvc/trax/executors/withdraw_cash_tokens_from_account/` → directory rename to `treasury_asset_balance_transfer/`.
   - Inside: rename `wcfa_*` step files + IDs to `tabt_*`.
   - Rename `sagaTemplateId` literal in `saga.go` to `"treasury_asset_balance_transfer"`.
   - Generalize each step's input extraction (per O3, O4, O5).
   - Add new steps: `tabt_acquire_vault_lock` (first) + `tabt_release_vault_lock` (last).

2. Accmgr saga template registration:
   - `pkg/daemons/accmgr/trax/executors/withdraw_cash_tokens_from_account/` → rename + update saga-template literal.
   - `run.go` import path renames.

3. Accmgr REST handler:
   - `pkg/daemons/accmgr/api/v1/accounts_post_withdraw_cash_tokens.go` → replace with `accounts_post_treasury_asset_balance_transfer.go`. Generic POST taking the full saga input shape. Delete the old file.
   - Update the router registration.

4. Saga input shape (post-rename):
   ```
   {
     "treasury_ops_base_idempotency_key": "exids:v1:<RpcName>:..." (caller-supplied),
     "currency_code": "EUR",
     "legal_structure_iid": "legstr_…",
     "exec_runtime_name": "primary",

     "source_account_iid": "<account_iid>",
     "source_stash_derivation_seed": "LIQUID" | "<numeric or arbitrary string>",

     "destination_account_iid": "<account_iid>",
     "destination_stash_derivation_seed": "LIQUID" | "<numeric or arbitrary string>",

     "amount": "<raw cents string>",
     "finalize_to_erc20": "true" | "false" (default "false"),
     "burn_after_withdraw": "true" | "false" (default "false"; ignored if finalize_to_erc20=false)
   }
   ```

5. Step-by-step internals (post-rename, per O5 always-run + lock semantics):

   - **tabt_acquire_vault_lock**: derive stash numbers from both seeds (numeric bypass, LIQUID short-circuit, or DeriveIndex). Compute the lock key tuple. Acquire the lock (mechanism per O11). Store stash numbers in step result_data for downstream steps.
   - **tabt_query_source_balance**: query `source_account_iid` vault at the resolved source-stash number. Stash the balance for downstream verification.
   - **tabt_transfer_between_stashes**: TVB call. `FromVault` = source vault, `FromStash` = source stash number. `ToVault` = destination vault, `ToStash` = destination stash number. `Caller` + `from_slot_address` = broker's clearing slot (same as commit `6f5c0fc19`).
   - **tabt_finalize_to_erc20**: ALWAYS runs. Reads `finalize_to_erc20` input. When `true`: execute `idempWithdrawFromVault` + optional `burn` (existing flow from `wcfa_withdraw_and_burn`). When `false`: no-op body, record `{finalize_to_erc20: false, on_chain_finalize: false}` in result_data.
   - **tabt_verify_balances**: re-query source + destination vaults. Assert source decreased by `amount`, destination increased by `amount`. (Stash-index derivation is in `tabt_acquire_vault_lock` per the lock-key requirement; verify only confirms the resolved numbers post-transfer.)
   - **tabt_release_vault_lock**: release the lock acquired in step 1. Runs on both the commit path and the compensation path (so a compensated saga doesn't leak the lock).

6. Step-template IDs and saga-template ID literals:
   - `pkg/treasury/idempkey/builder.go` — `StepWcfa*` constants → `StepTabt*`.

7. `pkg/treasury/stash/derive.go`:
   - Numeric-seed bypass + STASHOPS Phase 1 hash path both landed. `DeriveIndex` is fully implemented (keccak256-based, int63 output; rejects on the ~2^-63 LIQUID collision).

**Acceptance**: existing `make laser-e2e-ethbc-cat?` tests for withdraw (renamed alongside in Phase 5) pass against the new saga template.

## Phase 2 — prtagent v1 proto + handler parity

**Files touched**:

1. `data/api/grpc/prtagentapi/v1/*.proto` (locate the investor service def):
   - Add `LockCash` + `UnlockCash` RPCs mirroring brktrdapi's `LockCashRequest` / `UnlockCashRequest` shape.
   - Field tags + field-200 EXIDS contract.

2. `data/api/grpc/brktrdapi/v1/service.proto`:
   - Add `amount` field to `UnlockCashRequest` per O9 ratified.

3. `make gen-proto` (docker required; memory `feedback_docker_ask_kam.md` — ask kam before running if daemon down).

4. `pkg/daemons/prtagent/impl/v1/grpc/investor.go`:
   - New `LockCash` handler — EXIDS validator + stash validator (`allowLiquid=false`), DispatchRegistry, submit TABT saga with `finalize_to_erc20=false`, gateway-defaults per O3 + O4.
   - New `UnlockCash` handler — same shape; gateway optionally defaults `amount` to source-stash balance when broker omits it (per O9 amended).

5. `pkg/daemons/prtagent/impl/v1/grpc/exids_validation_test.go`:
   - `TestLockCash_RejectsEmptySeed`, `TestLockCash_RejectsLIQUIDStashSeed`, `TestLockCash_RejectsNumericZeroStashSeed` (per O12 outcome), `TestUnlockCash_*` mirror.

6. Regenerate Flutter bindings in any prtagent-facing consumer.

## Phase 3 — brktrdsvc real LockCash / UnlockCash

**Files touched**:

1. `pkg/daemons/brktrdsvc/impl/v1/grpc/cash.go`:
   - Replace lines `:344-381` stub bodies with real saga submissions through the TABT saga (same shape prtagent v1 just got, same DispatchRegistry usage, same EXIDS posture).
   - Wire the O9-amended `amount`-default behavior.

2. `pkg/daemons/brktrdsvc/impl/v1/grpc/exids_validation_test.go` (if it exists; create if not) — mirror prtagent's validator tests.

3. CLAUDE.md surface line (under brktrdsvc) — drop "LockCash/UnlockCash" from the stub count (currently lists "6 stubs"; should drop to "4 stubs": ReplaceOrder, StreamLiveQuote, StreamLiveOhlc, RegisterInvestorAtDepositories).

## Phase 4 — Mini-broker port

Mini-broker is a separate submodule with its own Flutter env. Strategy per O7: use mini-broker's idiomatic state mgmt (likely `provider`); clone-and-adapt the widget shape from common_ui.

**Files touched** (estimate):

1. EXIDS + stash widgets cloned into `apps/apps/legacy/mini-broker/lib/widgets/exids/` (or wherever mini-broker keeps widgets). Replace riverpod with provider/manual callbacks.

2. `apps/apps/legacy/mini-broker/lib/services/grpc_helper.dart`:
   - Add `lockCash` / `unlockCash` methods alongside existing `depositCash` / `withdrawCash` / `createOrderAsync` / `cancelOrderAsync` / `replaceOrderAsync`.
   - Record seeds in mini-broker's local history (per O8 outcome).

3. `apps/apps/legacy/mini-broker/lib/screens/portfolio_page.dart`:
   - Add Lock Cash + Unlock Cash buttons next to Deposit / Withdraw.
   - Thread stash + EXIDS values through the modal.

4. Wire EXIDS + stash widgets into:
   - Create order screen (currently uses ad-hoc `_exidsSeed`).
   - Cancel order modal.
   - Replace order modal.
   - Deposit cash modal.
   - Withdraw cash modal.
   - NEW Lock cash modal.
   - NEW Unlock cash modal.

5. Submodule commit (`apps/apps/legacy/mini-broker`) + parent pointer bump in the same kam-approved batch.

## Phase 5 — E2E + docs sweep

Per memory `feedback_saga_proto_changes_full_sweep.md`.

**Files touched**:

1. `tests/e2e/laser/withdraw_cash_test.go` → rename + extend:
   - `TestTabt_Withdraw_LIQUID` (current withdraw behavior).
   - `TestTabt_Lock_NumericStashIndex` (numeric bypass).
   - `TestTabt_Unlock_NumericStashIndex` (with partial-amount per O9).
   - `TestTabt_LockThenUnlock_RoundTrip` (per EXIDS D14.6.1).
   - `TestTabt_RejectsLIQUIDOnLock` (LIQUID literal).
   - `TestTabt_RejectsNumericZeroOnLock` (per O12 outcome).
   - `TestTabt_VaultLockPreventsParallelTransfer` (concurrency).

2. New e2e category OR fold into existing (O10 calls; per CLAUDE.md `docs/E2E_TEST_CATALOG.md` MUST be updated when adding tests). Makefile `E2E_CAT*_PATTERN` updates accordingly.

3. `docs/E2E_TEST_CATALOG.md` — category + test descriptions.

4. `docs/TODO_TREASURY_STASH_OPERATIONS.md` (STASHOPS) — mark Phase 2 (LockCash) + Phase 3 (UnlockCash) as DONE; link back to TABT for the saga implementation; note the numeric-bypass amendment.

5. `docs/TODO_EXECUTION_IDEMPOTENCY_SEED.md` (EXIDS) — LockCash + UnlockCash now real (drop from stub list); note the `amount` addition to UnlockCashRequest.

6. `CLAUDE.md` — update brktrdsvc surface description line (currently mentions 8 stubs; should drop to 4 after Phase 3).

7. Helm / dashboards / runbook updates per O10 outcome.

---

## What's DONE on this branch

Pre-TABT prep (commits leading up to this TODO):
- `f83412f9b` — withdraw signs with broker's clearing slot, not investor's.
- `6f5c0fc19` — withdraw uses TVB (RAC-gated) instead of TFV; burn becomes optional via `burn_after_withdraw` input flag; deployer slot only required when burn is on.
- `e571b5960` — ethbc burn handler accepts both `ArgNameEnum_BurnFrom` and `ArgNameEnum_From` (fixes `E20:INBAL`); trade_bench portfolio gets Lock/Unlock UI buttons + 4-mode cash-flow modal; `ASuiteDialog.error` with red Close button.

Phase 0 — design decisions ratified by kam (`232b13274`).

Phase 1 — code (this branch):
- `b410dd14a` — Numeric stash-seed bypass (`stash.ResolveStashIndex`) + validator rejects literal "LIQUID" AND numeric "0" when allowLiquid=false.
- `e80bd22bd` — Mechanical rename `withdraw_cash_tokens_from_account` → `treasury_asset_balance_transfer`; step prefix `wcfa_*` → `tabt_*`.
- `1a4ff5901` — Lock primitive moved to `pkg/cache` as a generic `KeyedLockStore` + `PgsqlKeyedLockStore` (`shared.distributed_locks`, TTL + steal-on-expire). TABT's previous `cache.AcquireMultiLock` calls stripped.
- `6a0c0005e` — New `tabt_acquire_vault_lock` + `tabt_release_vault_lock` step bodies; treassvc wired to Postgres with `EnsureSchema` at startup.
- `7f6c9820e` — accmgr REST + prtagent v1 + brktrdsvc thread the generalized TABT inputs (source/destination account + stash seeds + finalize_to_erc20 flag).
- `d814fa071` — Step bodies (`tabt_query_source_balance`, `tabt_transfer_between_stashes`, `tabt_finalize_to_erc20`, `tabt_verify_balances`) consume the source/destination split; `verify_inputs` produces the destination + treasury_deploy_id keys downstream steps need.
- This commit — brktrdsvc real LockCash; UnlockCash kept as stub pending proto Amount field; CLAUDE.md surface line updated.
- 2026-05-17 — O13: gateway WithdrawCash flipped to `finalize_to_erc20=false` in both prtagent v1 and brktrdsvc; gateway flow is now pure vault→vault (no withdraw-to-ERC20-account, no burn). Saga keeps the flags for admin/manual callers. Unit tests added for both gateways' saga-submission shape; cat37 e2e header + CLAUDE.md daemon blurbs updated to match.
- 2026-05-17 — STASHOPS Phase 1 LANDED (driven by kam's `"test1test1"` failure earlier the same day). `pkg/treasury/stash/DeriveIndex` is no longer a stub — keccak256(seed)[:8] → top-63-bits → int63; ~2^-63 LIQUID-collision case surfaces `ErrSeedHashesToLiquid`. Four green-path e2e tests added at `tests/e2e/laser/cash_flow_happy_path_e2e_test.go` (DepositCash, WithdrawCash LIQUID, LockCash arbitrary seed, UnlockCash arbitrary seed) that drive prtagent gRPC → TABT saga → on-chain delta assertions. cat37 Makefile pattern + E2E_TEST_CATALOG.md entries updated. Coverage gap that silently let `"test1test1"` hit production is closed: any future regression of the stub would fail the Lock/Unlock happy-path tests on the next cat37 run.

Phase 2 NOT done — prtagent v1 proto extension for LockCash / UnlockCash (needs `make gen-proto` / docker).

Phase 3 partial — brktrdsvc LockCash real, UnlockCash blocked on Phase 2 proto Amount field.

Phase 4 NOT done — mini-broker EXIDS + stash widget port + Lock/Unlock UI.

Phase 5 NOT done — e2e tests + STASHOPS / EXIDS doc cross-reference updates.

Deploy-time NOT done — `trax.saga_templates` + `trax.saga_step_templates` row updates for the renamed template id + 2 new step ids (`tabt_acquire_vault_lock`, `tabt_release_vault_lock`). Per O6, kam ratified the no-drain / single-rename strategy for pre-production clusters; the operator updates these rows when the new image is deployed.
