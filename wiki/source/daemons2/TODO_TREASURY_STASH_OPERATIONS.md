# TODO: Treasury Stash Operations — `LockCash`, `UnlockCash`, `WithdrawCash` from a chosen stash

> **Status**: SUPERSEDED IN PART by **docs/TODO_CASH_STASH_TRANSFER_SAGA.md (TABT)** as of 2026-05-11. TABT generalizes the withdraw saga into a single `treasury_asset_balance_transfer` saga that Withdraw / Lock / Unlock all reuse — the `lock_cash` / `unlock_cash` template designs sketched in this doc are NOT the target anymore. Phase 1 of TABT landed in code; LockCash on brktrdsvc is real, UnlockCash is stubbed pending a proto Amount field. What remains under STASHOPS strictly: the `stash.DeriveIndex` hashing algorithm past the LIQUID + numeric-form fast-paths (Phase 1 here).
>
> **Phase 1 LANDED 2026-05-17** — `stash.DeriveIndex` is no longer a stub. Algorithm: keccak256(seed) → first 8 bytes big-endian → top bit cleared → int63. Collision on LiquidStashIndex (probability ~2^-63) surfaces `ErrSeedHashesToLiquid`; broker picks another seed. No retry path (keeps derivation deterministic). Driving incident: kam's WithdrawCash with seed `"test1test1"` (2026-05-17) failed at `tabt_acquire_vault_lock` with `ErrNotImplemented`. See "Phase 1 — LANDED" section below for ratifications of O1 / O2 / O3 and the full implementation footprint.
>
> See TABT for the saga design + state.
> **Created**: 2026-05-10
> **Short ID**: `STASHOPS`
> **Authoring rules**: per `feedback_phased_todo_authoring.md` (established header + phase shape; bake in "ask `kam` liberally") and `feedback_pre_production_no_backcompat.md` (no shims, atomic per-surface flips)
> **Companion to**: `TODO_EXECUTION_IDEMPOTENCY_SEED.md` (EXIDS) — the EXIDS TODO defines the *wire field* `treasury_stash_derivation_seed` (validator, proto field, Flutter widget, history persistence). THIS TODO defines the *behaviour* on the server: the derivation algorithm, the sagas, the on-chain operations.
> **Surfaces touched**:
> - NEW package `pkg/treasury/stash/` (algorithm + `LIQUID` constant + Go-side types)
> - NEW sagas `lock_cash` and `unlock_cash` under `pkg/daemons/.../trax/executors/` (or possibly under treassvc — see O3)
> - EXTENDED saga `withdraw_cash_tokens_from_account` to accept a source stash ≠ 0
> - REPLACE stub handlers `pkg/daemons/brktrdsvc/impl/v1/grpc/cash.go:269` (`LockCash`) and `:278` (`UnlockCash`)
> - EXTEND handlers `pkg/daemons/brktrdsvc/impl/v1/grpc/cash.go:113` (`WithdrawCash`) and `pkg/daemons/prtagent/impl/v1/grpc/investor.go:1085` (`WithdrawCash`) — pending O9 in EXIDS
> - NEW REST endpoints on accmgr to receive the new saga submissions (mirror `accounts_post_withdraw_cash_tokens.go` shape)
> - E2E tests covering the lock-then-withdraw round-trip described in EXIDS D14.6.1
> **Related Docs**:
> - `TODO_EXECUTION_IDEMPOTENCY_SEED.md` — wire field contract (D13/D14)
> - `TODO_IDEMPOTENT_TREASURY_VAULT_OPERATIONS.md` — on-chain `Erc20VaultIdempFacet` (COMPLETE; this TODO consumes it)
> - `TODO_BRKTRDAPI_AND_BRKADMAPI.md` — D8 / Phase 2 references where Lock/Unlock cash sagas were originally parked
> - `TODO_FUND_ACCOUNT_WITH_CASH_TOKENS.md` — the existing fund saga (deposit) which is the closest existing precedent for a "broker-driven cash mutation" saga
> - `TODO_FIX_DIVISIBILITY_CORRECT_STASH_UNLOCK.md` — recent work on `unlock_order_stash` semantics; relevant prior art

---

## ⚠ Notes for the executing agent

**This file is a skeleton.** Many decisions have not been made; they are flagged as open questions (O1–O10+ below). DO NOT begin coding any phase before Phase 0 closes the questions relevant to that phase with `kam`.

**Ask `kam` liberally.** Stop and ask before guessing whenever:

- The derivation algorithm needs a numeric parameter (max stash index, hash function, collision-handling rule).
- A saga design choice could go two ways (new saga vs extending an existing one — see O3, O4).
- The authorization / signer story for a Lock/Unlock differs from any existing precedent (the `lock_order_volume` saga uses the clearing-account-vault-as-signer pattern — new sagas may or may not follow that).
- An on-chain operation looks like it should be idempotent but the existing facet doesn't expose it that way.
- Anything in this doc conflicts with what you observe in the code today — assume the doc is stale and ask.

**Pre-production project — no back-compat.** When `withdraw_cash_tokens_from_account` gains a source-stash parameter, every caller in the same commit gets it. No fallback path.

**Single-most-important contract from EXIDS** (re-stated for this TODO's reader):

The client sends ONE string `treasury_stash_derivation_seed`. The server-side `deriveStashIndex` (defined in Phase 1 of THIS TODO) maps it to an integer stash index. The reserved literal `"LIQUID"` short-circuits to stash `0`; everything else goes through the algorithm.

---

## Overview

### Today (state at 2026-05-10)

**`LockCash` / `UnlockCash`** — brktrdsvc handlers at `cash.go:269` and `:278` return `Unimplemented`. No saga exists. The contract surface (proto field carrying broker-supplied entropy under the old name `broker_input`) was reserved by `TODO_BRKTRDAPI_AND_BRKADMAPI.md` D8 / Phase 2 but never built.

**`WithdrawCash`** — both brktrdsvc (`cash.go:113`) and prtagent (`investor.go:1085`) handlers work and submit the `withdraw_cash_tokens_from_account` saga. The saga unconditionally sources from stash `0` (liquid). The body posted to accmgr's `/withdraw` endpoint at `cash.go:230-233` includes only `account_iid` and `amount` — no source stash.

**Existing per-numbered-stash precedent** — the FIX-driven order flow:
- `lock_order_volume` saga (`pkg/daemons/treassvc/trax/executors/create_investor_order/lock_order_volume.go:144`): transfers from vault stash `0` to vault stash `order_stash_index` via `executeTransferVaultBalance`. Stash index is supplied as a small integer by `marketmgr` when it creates the order request (stored in `marketmgr.order_requests.order_stash_index` column — `pkg/daemons/marketmgr/order_request_store_psql.go:39, 176, 329`).
- `unlock_order_stash` saga (`pkg/daemons/treassvc/trax/executors/unlock_order_stash/transfer_stash.go`): transfers back from stash `N` to stash `0`. Reads `source_stash_index` and `destination_stash_index` from input map. Has been hardened recently (see `TODO_FIX_DIVISIBILITY_CORRECT_STASH_UNLOCK.md`) to use the on-chain balance of the source stash as the transfer amount, ignoring caller-supplied `amount` if it disagrees.
- The on-chain `Erc20VaultIdempFacet` has no concept of "stash creation" — every stash index is an addressable slot whose balance starts at `0`. Lock-into-stash-N is a transfer; the slot is materialised lazily when first written.

So the on-chain mechanics for what we need ALREADY EXIST. What's missing is:
1. A way to map a STRING seed to a numeric stash index (today numbers come from marketmgr's auto-incrementing column, not from a hash).
2. Saga templates for the broker-driven LockCash / UnlockCash flows (today's per-numbered-stash sagas are FIX/order-driven).
3. An extended Withdraw saga that can read from a non-zero stash.

### After this TODO

- A new `pkg/treasury/stash/` package owns: the `LIQUID` constant, the `deriveStashIndex(seed string) (int64, error)` function, the `IsLiquid(seed string) bool` predicate, and any related helpers.
- Two new sagas `lock_cash` and `unlock_cash` mirror the shape of `lock_order_volume` / `unlock_order_stash` but are broker-driven (entry point: brktrdsvc handler, not actusvc/FIX).
- The existing `withdraw_cash_tokens_from_account` saga gains an optional `source_stash_index` input. When the source is `0` (the EXIDS-app-default for `LIQUID`), behaviour is unchanged. When non-zero, the saga drains the chosen stash before going through the usual transfer-to-clearing → withdraw-and-burn pipeline.
- The brktrdsvc Lock/Unlock handlers become real and submit the new sagas.
- The brktrdsvc and prtagent (per EXIDS O9) Withdraw handlers read the stash seed, call `deriveStashIndex`, and pass the index into the saga input.
- The EXIDS TODO's D14.6.1 example — broker locks 200 EUR with seed `transfer-156`, later withdraws with the same seed and sources from the same stash — works end-to-end.

---

## Decisions locked

### D1 — `pkg/treasury/stash/` package shape

Tentative API (Phase 1 confirms):

```go
package stash

import "fmt"

// LiquidSeed is the reserved literal that resolves to stash index 0.
// Mirrors EXIDS D14.1.
const LiquidSeed = "LIQUID"

// LiquidStashIndex is the on-chain stash slot for liquid (spendable) balance.
const LiquidStashIndex int64 = 0

// IsLiquid returns true iff the seed is exactly the literal "LIQUID"
// (case-sensitive, no surrounding whitespace).
func IsLiquid(seed string) bool {
    return seed == LiquidSeed
}

// DeriveIndex maps a non-LIQUID stash-derivation seed to a deterministic
// stash index in the range [1, MaxStashIndex].
//
// "LIQUID" is rejected here — callers must check IsLiquid first and
// return LiquidStashIndex without going through this function.
//
// Algorithm: TBD per O1/O2.
func DeriveIndex(seed string) (int64, error) {
    if seed == LiquidSeed {
        return 0, fmt.Errorf("DeriveIndex called with LIQUID; use LiquidStashIndex constant directly")
    }
    // ... see O1/O2 for algorithm choice
    panic("unimplemented")
}

// MaxStashIndex bounds the derivation output. TBD per O1.
const MaxStashIndex int64 = 0 // placeholder
```

The package lives under `pkg/treasury/` next to `pkg/treasury/idempkey/` (sibling). Name `stash` (not `stashes`, not `stashderiv`) to keep imports tight: `stash.LiquidSeed`, `stash.IsLiquid(...)`, `stash.DeriveIndex(...)`.

### D2 — Saga inventory: NEW sagas, not extensions of existing ones

Rationale (subject to O3 confirmation):

- `lock_order_volume` is wired as **step 4 of `create_investor_order`**. It expects the parent saga to have computed the order_stash_index, set up vault slot addresses, the clearing account vault slot, etc. Reusing it for a broker-driven LockCash would mean threading a synthetic order context through it — fragile.
- `unlock_order_stash` is similarly entangled with the FIX/order context (called from `handle_*_fix_exec_report` sagas via the `unlock_stash_helper`).

Cleaner: NEW dedicated sagas `lock_cash` and `unlock_cash` that do ONLY the cash-stash-mutation work, calling the same on-chain primitives. The treassvc executors `lock_order_volume` and `unlock_order_stash` may share helper functions (e.g. `executeTransferVaultBalance`, `confirmVaultBalance`) — extract those if not already.

| Saga | Spawning RPC | Source → Dest | Notes |
|---|---|---|---|
| `lock_cash` (NEW) | `LockCash` (brktrdapi) | stash `0` → `deriveStashIndex(seed)` | Mirrors `lock_order_volume` shape but broker-driven |
| `unlock_cash` (NEW) | `UnlockCash` (brktrdapi) | `deriveStashIndex(seed)` → stash `0` | Mirrors `unlock_order_stash` shape but broker-driven |
| `withdraw_cash_tokens_from_account` (EXTENDED) | `WithdrawCash` (brktrdapi + prtagent) | `source_stash_index` → ... → burn | Today always sources from `0`; gains an optional input parameter |

### D3 — Saga input contract

Every Lock/Unlock/Withdraw saga must receive at minimum:

| Key | Type | Source | Notes |
|---|---|---|---|
| `treasury_ops_base_idempotency_key` | string | EXIDS field 200 (verbatim) | Mandatory — fed via TOBIK chain (EXIDS D7) |
| `stash_derivation_seed` | string | EXIDS new field 5 (aligned across brktrdapi + prtagent) | Mandatory — verbatim from gateway |
| `participant_iid` | string | auth context | as today |
| `external_investor_id` | string | request | as today |
| `currency_code` | string | request | as today |
| `amount` | string | request | as today (Lock/Withdraw); for Unlock: optional, real amount comes from on-chain stash balance per `unlock_order_stash` precedent |
| `source_stash_index` | string-int | derived | Lock: `"0"`. Unlock: `deriveStashIndex(seed)`. Withdraw: same as Unlock if seed != LIQUID, else `"0"`. |
| `destination_stash_index` | string-int | derived | Lock: `deriveStashIndex(seed)`. Unlock: `"0"`. Withdraw: not applicable (downstream pipeline) |

The saga itself does NOT call `deriveStashIndex` — the GATEWAY does, then writes the resolved index into `source_stash_index` / `destination_stash_index`. Keeps the algorithm in one place (the gateway handler). Sagas remain index-only consumers, mirroring today's `lock_order_volume` which receives `order_stash_index` as a pre-computed integer.

(Alternative: have the saga call `deriveStashIndex` instead of the gateway. Pros: single source of truth at saga level; gateway is dumber. Cons: every saga executor needs to import `pkg/treasury/stash`. Decide in O3.)

### D4 — `LIQUID` short-circuit at the gateway

Per EXIDS D14.6.3 / D14.6.6:

```go
// in brktrdsvc / prtagent gateway handlers
seed := req.GetTreasuryStashDerivationSeed()
// ... validator already ran (per EXIDS D14.5)
var stashIdx int64
if stash.IsLiquid(seed) {
    stashIdx = stash.LiquidStashIndex // = 0
} else {
    stashIdx, err = stash.DeriveIndex(seed)
    if err != nil { return nil, status.Errorf(codes.Internal, ...) }
}
// stashIdx now ready for the saga input
```

For Lock/Unlock the EXIDS validator already rejected `LIQUID`, so `stash.IsLiquid` is only true on the Withdraw path (where it short-circuits to liquid-source).

### D5 — On-chain idempotency stays via TOBIK / `idempkey.StepBuilder`

This TODO does not introduce new on-chain idempotency mechanisms. The new `lock_cash` / `unlock_cash` sagas use `idempkey.StepBuilder` (per EXIDS D11) with new step-template-id constants:

```go
// add to pkg/treasury/idempkey/builder.go
StepLockCashTransferVault   StepTemplateID = "lock_cash_transfer_vault"
StepLockCashVerifyBalance   StepTemplateID = "lock_cash_verify_balance"
StepUnlockCashTransferVault StepTemplateID = "unlock_cash_transfer_vault"
StepUnlockCashVerifyBalance StepTemplateID = "unlock_cash_verify_balance"
StepWithdrawCashSourceDrain StepTemplateID = "withdraw_cash_source_drain" // for non-liquid source
```

The OpSuffix table (LockValue, LockValueComp, UnlockStash, UnlockStashComp, WithdrawTransfer, WithdrawFromVault, WithdrawBurn) is reused as-is — no new OpSuffix constants needed.

### D6 — Authorization / signer (UNDECIDED — see O5)

Today's precedent in `lock_order_volume`: the **clearing-account-vault** is the signer (it holds the admin facet authorisation). Worth checking whether a broker-driven LockCash should use the same signer, or whether the broker's own signer must be involved.

Placeholder: the new sagas use the SAME clearing-account-vault-as-signer pattern as `lock_order_volume` until O5 says otherwise.

### D7 — Compensation behaviour (UNDECIDED — see O8)

`lock_order_volume` has a compensation path that reverses the lock (returns volume to stash 0). `unlock_order_stash` likewise. The new `lock_cash` / `unlock_cash` should mirror this behaviour for any saga-orchestration failure between gateway-accept and on-chain-confirm.

Placeholder: mirror existing patterns. Phase 0 confirms no surprises.

---

## Open questions (BLOCKING — must be resolved with `kam` before relevant phase starts)

These are intentionally numerous. This TODO is a skeleton; many algorithmic and saga-design decisions need explicit confirmation.

### O1 — Stash index space and derivation algorithm

What is the value space of a stash index, and what algorithm maps `seed` → index?

- **Value space**: Solidity `uint256` is the on-chain native, but we don't want to operate on 256-bit indices in the gateway. Practical options:
  - `int64` mapped to `uint256` on-chain (range up to `2^63-1` — fits in our existing `marketmgr.order_requests.order_stash_index` `bigint` column).
  - `uint32` (~4 billion stashes per vault) — much smaller domain, easier collision analysis, still way more than any broker realistically uses.
  - `uint16` (65k stashes per vault) — too small? Collision chance becomes meaningful.

- **Algorithm**: candidates ranked roughly:
  - `int64(binary.BigEndian.Uint64(keccak256(seed)[:8]))` and ensure positive (mask out top bit) → wide-open `int64` range, vanishingly small collision odds for any realistic usage.
  - `int64(binary.BigEndian.Uint32(keccak256(seed)[:4]))` → uint32-range, more compact but ~50% collision odds at 100k stashes per vault (birthday paradox).
  - `int64(crc32(seed))` — fast but weaker; not recommended.
  - Hash with BAN-LIST: derive, reject if index `0` (collision with LIQUID) or `1` (reserved?), else accept.

- **Collision behaviour**: if two different seeds derive the same index by chance, the second `LockCash` would lock INTO the same stash that the first one already locked into. The on-chain idempotency facet wouldn't catch this (the per-step keys differ). Practically: balances would commingle in one stash, and an `UnlockCash` with either seed would unlock the combined balance — a quiet correctness bug.

  Mitigation candidates:
  - Wide enough hash output that collisions are astronomically rare (`int64` wide hash → ~1 collision per ~3 billion seeds).
  - Track stash → seed mapping in postgres; reject derive if collision detected; client must pick a different seed.
  - Track seed → stash mapping in postgres; on second `LockCash` with same seed, treat as "lock more into the same stash" (additive). EXIDS payload-hash guard catches retries; this is for genuinely-different second-locks against the same seed-derived stash.

  **Recommendation**: int64 with top-bit-clear (giving 63-bit range, ~9.2 × 10^18 stashes). Collision probability ≈ 0 for any realistic broker. No tracking table. If the algorithm ever needs to change, the seed prefix carries an algorithm-version namespace (similar to EXIDS D4's `:v1:` prefix idea — applied here as `seed = "stashv1:" + user_input` perhaps; OR keep the seed un-prefixed and version the algorithm at the package level).

- **Decision needed**: pick value-space + algorithm + collision behaviour.

### O2 — Algorithm versioning

Once O1 is decided, can the algorithm ever be changed? If yes, how do we version it?

Two options:
- **Embed version in the saga input**: gateway computes `stash_index = derive(seed, algorithm_version)` and writes `algorithm_version` into the saga input. Sagas read it back. New seeds use the latest version; old sagas use the version they were minted with.
- **Embed version in the seed prefix**: `derive(seed)` returns a value that's a function of the prefix (`"v1:..."` uses algorithm 1). Old seeds keep working forever; new seeds opt into the new algorithm.

**Recommendation**: don't pre-design for versioning. Pin the algorithm at v1, document it, change it only via a new dedicated TODO (and accept that any seeds in flight at the time of change need broker re-keying). Keeps Phase 1 simple.

### O3 — `deriveStashIndex` location: gateway vs saga

Should `deriveStashIndex` be called by the gateway (per D3 placeholder) or by the saga executor?

- **Gateway**: keeps sagas dumb (they consume integers, not strings). Aligns with today's `lock_order_volume` precedent. Single derivation site.
- **Saga**: keeps the seed → index mapping closer to the on-chain operation. Eases debugging from saga logs. Multiple call sites if multiple sagas need it.

**Recommendation**: gateway. But confirm.

### O4 — Reuse `unlock_order_stash` saga for `UnlockCash`?

`unlock_order_stash` is FIX-driven today, but its core executors (`transfer_stash.go`, `verify_balance.go`) are saga-template-agnostic — they read `source_stash_index` / `destination_stash_index` from the input map and act accordingly. Could `UnlockCash` submit `unlock_order_stash` directly?

- **Reuse**: zero new saga code. Just provide the right input map. Risk: any FIX-driven assumptions baked into the saga (e.g. expectation of `order_request_iid`, `order_stash_index` field present) would need to be relaxed.
- **New saga `unlock_cash`**: clean separation. New executor files. More code.

**Recommendation**: investigate during Phase 0. If `unlock_order_stash` is genuinely FIX-agnostic at the saga-template level, reuse it. If it has order-context coupling, build new `unlock_cash`. Same investigation for `lock_order_volume` vs new `lock_cash`.

### O5 — Authorization model

Today `lock_order_volume` uses the clearing-account-vault as signer (line 322: `clearingAccountVaultLaserSlotAddress, // signer: clearing account (authorized for admin facet)`). Does broker-driven `LockCash` use the same?

- The broker is the actor on behalf of the investor. The investor's vault gets the balance moved IN. The clearing-account-vault is the participant's (broker's) own account.
- For an order, the participant is authorising that the order ops can manipulate the investor's vault on their behalf. Same model probably applies for raw cash locks.

**Decision**: confirm with `kam` whether the same clearing-account-vault-as-signer pattern is correct for broker-driven cash mutations, or whether a different authorisation flow is needed.

### O6 — MQ event fan-out

Today `CreateOrderAsync` flows fire MQ events into the per-investor exchange. Should `LockCash`/`UnlockCash`/`WithdrawCash` fire equivalent events?

- Mini-broker investor side already subscribes via `SubscribeToEvents` to its per-investor exchange (CLAUDE.md: "ports prtagent's logic verbatim"). If LockCash fires no events, the investor screen has no reactive update — they'd need to poll.
- Event payload schemas need design — at minimum: `lock_cash_submitted`, `lock_cash_confirmed`, `lock_cash_failed`, similar for Unlock and the new Withdraw-from-stash variant.

**Decision**: define which events fire and their payload shape during Phase 7 (currently unsequenced; insert before Phase 8 e2e tests).

### O7 — Per-currency vs cross-currency stash scope

A vault is per-(investor, currency) per existing precedent. Therefore stash indices are scoped within a vault — i.e. seed `transfer-156` could legitimately derive index `47` in BOTH the EUR vault AND the USD vault, and they'd be entirely separate stashes.

**Question**: is this OK from the broker's mental model? Or does the broker think of a stash-derivation seed as identifying a global "deal" that should target the same stash regardless of currency?

If "same stash regardless of currency": the seed → index function must NOT be currency-aware (which is the default — the seed is the only input). ✓
If "currency-scoped": same default. ✓
The semantic question is whether two `LockCash` calls with the same seed but different currencies map to "the same logical stash" or "two unrelated stashes". On-chain they're two unrelated stashes (different vaults). UI should make this clear.

**Decision**: confirm this matches the broker's mental model. Document in the EXIDS D14 + this D-section accordingly.

### O8 — Compensation paths

What does a failed Lock saga compensate to? Same answer for Unlock and Withdraw-from-stash.

- Lock saga: chain transaction succeeds but post-step verify fails → compensation reverses the transfer (mirrors `lock_order_volume.go:258-388`).
- Lock saga: chain transaction submission fails → no compensation needed; nothing happened.
- Unlock saga: same shape.
- Withdraw-from-stash: drain succeeds, transfer-to-clearing fails → compensation re-locks the drained amount back into the source stash. Possible, but adds complexity.

**Decision**: in Phase 0, walk each failure mode and decide compensation behaviour with `kam`. Document in D7.

### O9 — Auto-lock if stash already has a balance

If the broker calls `LockCash` with seed `"transfer-156"` twice (different `execution_idempotency_seed` so the EXIDS dedup doesn't catch), should the second call:
- Add to the existing stash balance (cumulative)?
- Reject because "stash 47 already has a balance"?
- Replace (drain old, lock new)?

EXIDS payload-hash dedup catches the *same-EXIDS-seed* case. This question is about the *different-EXIDS-seed-but-same-stash-seed* case — which is a legitimate "I want to add more to this stash" scenario.

**Recommendation**: additive (cumulative). Matches the on-chain semantic — stash balance is just a number; transferring into it adds, transferring out subtracts. Simplest.

**Decision**: confirm.

### O10 — Unlock with zero balance / unknown stash

`UnlockCash` with seed `"never-locked"` derives some index `K` whose on-chain balance is `0`. What happens?

- The `unlock_order_stash` saga today reads the on-chain balance and uses it as the transfer amount (per `transfer_stash.go:84-117`). A zero balance → transfer of zero → ... arguably succeeds with zero effect, arguably fails with a "nothing to unlock" error.
- If we want to fail loudly: read balance first; if zero, return `FailedPrecondition` from the gateway BEFORE submitting the saga.

**Recommendation**: gateway pre-check. Read the on-chain balance via lasersvc; reject with a clear error if zero. Avoids spawning empty-effect sagas.

**Decision**: confirm.

### O11 — Saga template registration / serializer registration

Per `TODO_MISSING_LASER_SERIALIZER_REGISTRATIONS.md`, every new saga template needs registration in trax serializers. Confirm the registration sites and add the new sagas there.

### O12 — Postgres schema additions

Do the new sagas need new accmgr tables? Possible additions:
- `accmgr.cash_locks` — tracks every `lock_cash` saga, one row per (investor, currency, derived_stash_index, ...). Useful for "list my locked balances" UIs.
- `accmgr.cash_lock_history` — append-only log.

OR rely entirely on on-chain queries + saga history in TRAX. **Decision**: confirm whether postgres mirroring is needed for UX or whether on-chain reads suffice.

---

## Phase 0 — Spec freeze and stakeholder sign-off

Goal: lock D1–D7 with `kam`. Resolve every O-question.

- [ ] 0.1 Resolve O1 (algorithm, value space, collision). Update D1 and D3.
- [ ] 0.2 Resolve O2 (versioning). Probably "no versioning at v1"; document.
- [ ] 0.3 Resolve O3 (gateway vs saga `deriveStashIndex` location).
- [ ] 0.4 Resolve O4 (reuse `unlock_order_stash` and `lock_order_volume` vs new sagas). Read the existing saga executors end-to-end before deciding.
- [ ] 0.5 Resolve O5 (authorization model).
- [ ] 0.6 Resolve O6 (MQ event fan-out). Sketch event payload shapes.
- [ ] 0.7 Resolve O7 (per-currency scope semantic alignment). Update EXIDS D14 if any wording needs sharpening.
- [ ] 0.8 Resolve O8 (compensation paths). Walk each failure mode.
- [ ] 0.9 Resolve O9 (additive vs reject vs replace on second lock).
- [ ] 0.10 Resolve O10 (unlock-empty-stash behaviour).
- [ ] 0.11 Resolve O11 (saga template registration sites).
- [ ] 0.12 Resolve O12 (postgres mirroring needs).
- [ ] 0.13 Confirm EXIDS D14.6.1 lock-then-withdraw example matches what we're actually building.

---

## Phase 1 — `pkg/treasury/stash/` package — **LANDED 2026-05-17**

Goal: implement the algorithm + helpers locked in Phase 0.

**Ratifications (by kam, 2026-05-17 after WithdrawCash failed with seed `"test1test1"`)**:

- **O1 — Algorithm**: `int64(binary.BigEndian.Uint64(keccak256(seed)[:8]) & 0x7fffffffffffffff)`. Wide 63-bit output, ~2^-63 collision probability per pair of distinct seeds. No tracking table. If the hash lands on `LiquidStashIndex` (0), `DeriveIndex` returns `ErrSeedHashesToLiquid` — broker picks a different seed. No retry path (keeps the algorithm deterministic and the test vector trivially reproducible).
- **O2 — Versioning**: NONE. Algorithm pinned at v1 (implicit). Any future change requires a new dedicated TODO and forces broker re-keying — kam explicitly chose not to pre-design for versioning. The lock-in is preserved by `TestDeriveIndex_KnownVector` in `derive_test.go`.
- **O3 — Derivation site**: SAGA, not gateway. `DeriveIndex` is called inside `tabt_acquire_vault_lock` (the TABT saga's first step). Matches the existing placement and keeps gateway helpers focused on shuttling strings rather than computing on-chain indices. Gateway validators (`exids.MustValidateStashSeedOrStatusErr`) still call `ResolvesToLiquid` to enforce D14.4 ("LIQUID disallowed" on Lock/Unlock) but DO NOT trigger DeriveIndex themselves.

**Implementation footprint**:

- [x] 1.1 `pkg/treasury/stash/derive.go` — replaced the `ErrNotImplemented` stub with the real algorithm; added `ErrSeedHashesToLiquid` + `ErrEmptySeed`. Updated package doc + `ResolveStashIndex` error list.
- [x] 1.2 `pkg/treasury/stash/derive_test.go` — `TestDeriveIndex_Deterministic`, `TestDeriveIndex_KnownVector` (locks `"test1test1"` → `0x246ff97eb38f04c2`), `TestDeriveIndex_NeverNegative` (1000-iteration sanity over int63 range), `TestDeriveIndex_DistinctSeedsGiveDistinctIndexes` (10k seeds, zero collisions expected), `TestDeriveIndex_RejectsEmptySeed`. `TestResolveStashIndex_NonNumericFallsToDerive` rewritten to assert pipeline-consistency rather than expecting `ErrNotImplemented`.
- [x] 1.3 No separate README — algorithm doc lives in `derive.go`'s package comment (single source of truth, alongside the code).

**Driving incident**: kam tried `WithdrawCash` with stash seed `"test1test1"` on 2026-05-17. The saga failed at `tabt_acquire_vault_lock` with `stash.DeriveIndex: hashing algorithm not implemented yet`. The cat37 e2e suite passed at the time because every test that submitted a non-LIQUID, non-numeric seed was a validator-rejection test — none ever reached `DeriveIndex`. Coverage closed in the same change: see `tests/e2e/laser/cash_flow_happy_path_e2e_test.go` (`TestCashFlow_LockCash_HappyPath_ArbitrarySeed` + `TestCashFlow_UnlockCash_HappyPath_ArbitrarySeed`).

---

## Phase 2 — `lock_cash` saga

Goal: build the new saga (or extend `lock_order_volume` per O4).

- [ ] 2.1 Decide saga template id (`lock_cash`) and create the saga template file.
- [ ] 2.2 Define saga steps. Suggested mirror of `lock_order_volume`:
  - `lc_validate_inputs` — parse + validate the input map.
  - `lc_resolve_vault_addresses` — same lookup as `lock_order_volume` does at the start.
  - `lc_transfer_vault` — `executeTransferVaultBalance` from stash 0 to derived stash.
  - `lc_verify_balance` — confirm both source and destination balances changed by exactly `amount`.
- [ ] 2.3 Implement each step under `pkg/daemons/treassvc/trax/executors/lock_cash/`. Reuse `executeTransferVaultBalance`, `confirmVaultBalance`, `queryVaultBalance` helpers from `lock_order_volume` — extract them to a shared helper package if not already.
- [ ] 2.4 Use `idempkey.StepBuilder` per EXIDS D11 with new step-template constants (`StepLockCashTransferVault`, `StepLockCashVerifyBalance`).
- [ ] 2.5 Add accmgr REST endpoint `POST /participant/{p}/legal/structure/{ls}/mechanisms/{exec_runtime}/cash-tokens/{ccy}/lock` that submits the saga. Mirror `accounts_post_fund_with_cash_tokens.go` and `accounts_post_withdraw_cash_tokens.go` shapes.
- [ ] 2.6 Add brktrdsvc helper `lockCashIntoStash(...)` mirroring `fundAccountWithCashTokens` — POSTs to the new accmgr endpoint with TOBIK + stash index + investor account IID.
- [ ] 2.7 Per O11: register the saga in trax serializers.

---

## Phase 3 — `unlock_cash` saga

Goal: build the new saga (or extend `unlock_order_stash` per O4).

- [ ] 3.1 Decide saga template id (`unlock_cash`).
- [ ] 3.2 Define saga steps (mirror `unlock_order_stash`).
- [ ] 3.3 Implement under `pkg/daemons/treassvc/trax/executors/unlock_cash/` (or extend `unlock_order_stash` per O4).
- [ ] 3.4 Use `idempkey.StepBuilder` with new constants (`StepUnlockCashTransferVault`, `StepUnlockCashVerifyBalance`).
- [ ] 3.5 Add accmgr REST endpoint for unlock.
- [ ] 3.6 Add brktrdsvc helper `unlockCashFromStash(...)`.
- [ ] 3.7 If O10 = "gateway pre-check": add the on-chain balance lookup at the gateway BEFORE submitting the saga; reject with `FailedPrecondition` on zero balance.
- [ ] 3.8 Saga registration.

---

## Phase 4 — Extend `withdraw_cash_tokens_from_account` for non-zero source stash

Goal: source-stash parameterisation. Per `feedback_pre_production_no_backcompat.md`: atomic — no flag-guarded transition, every caller updated in the same commit.

- [ ] 4.1 Add `source_stash_index` to the saga input contract. Default behaviour preserved when value is `"0"` (i.e. liquid).
- [ ] 4.2 Update accmgr REST `accounts_post_withdraw_cash_tokens.go` to accept `source_stash_index` in the request body. Mandatory (no default — gateway always supplies it).
- [ ] 4.3 Update treassvc executor `withdraw_cash_tokens_from_account/transfer_from_account_to_clearing.go:104+`: when `source_stash_index != "0"`, transfer from that stash into the clearing flow instead of from liquid. Use the `WithdrawTransfer` OpSuffix per existing convention.
- [ ] 4.4 Update treassvc executor `withdraw_cash_tokens_from_account/withdraw_and_burn_tokens.go:103+` if it has any source-stash assumptions.
- [ ] 4.5 New step-template constants if needed (`StepWithdrawCashSourceDrain`).
- [ ] 4.6 If the source stash has insufficient balance for `amount`: fail at the gateway pre-check (similar to O10), or fail loudly inside the saga with a clear error. Decide in Phase 0 alongside O10.

---

## Phase 5 — `WithdrawCash` handler extension (brktrdsvc + prtagent)

Goal: gateway plumbing for the source-stash parameter.

- [ ] 5.1 In `pkg/daemons/brktrdsvc/impl/v1/grpc/cash.go` `WithdrawCash` (line 113):
  - After EXIDS validators (per EXIDS Phase 5.6), call `stash.IsLiquid(req.GetTreasuryStashDerivationSeed())` and `stash.DeriveIndex(...)` per D4.
  - Pass `sourceStashIndex` into the helper `withdrawCashTokensFromAccount(...)` — this requires extending its signature.
  - Update the helper at `cash.go:219+`: add `sourceStashIndex int64` parameter, include in the request body.
- [ ] 5.2 In `pkg/daemons/prtagent/impl/v1/grpc/investor.go` `WithdrawCash` (line 1085) — pending EXIDS O9: same change. Mirror brktrdsvc.
- [ ] 5.3 Update the helper at `pkg/daemons/prtagent/impl/v1/grpc/investor.go:266+` `withdrawCashTokensFromAccount`: same signature extension.

---

## Phase 6 — `LockCash` and `UnlockCash` handler implementation (brktrdsvc)

Goal: replace stubs at `cash.go:269` and `:278` with real handlers.

- [ ] 6.1 `LockCash` handler:
  - EXIDS validators (per EXIDS Phase 5.6).
  - Resolve investor + legal-structure (mirror DepositCash / WithdrawCash boilerplate at lines 53-94 / 148-168).
  - Compute `destStashIdx = stash.DeriveIndex(seed)` (gateway-side per D4).
  - Submit saga via the new helper `lockCashIntoStash(participantIid, legalStructureIid, "primary", currencyCode, investorAccountIid, amountStr, destStashIdx, exidsSeed)`.
  - Return `ExecutionAsyncResponse` with the saga instance id.
- [ ] 6.2 `UnlockCash` handler:
  - EXIDS validators.
  - Resolve investor + legal-structure.
  - Compute `srcStashIdx = stash.DeriveIndex(seed)`.
  - If O10 = gateway pre-check: query the on-chain balance and reject if zero.
  - Submit saga via new helper `unlockCashFromStash(...)`.
- [ ] 6.3 Verify handler-level tests (gateway-level rejection of malformed inputs already covered by EXIDS Phase 5.9 — this phase adds the happy-path saga-submission tests).

---

## Phase 7 — MQ event fan-out

Goal: per O6.

- [ ] 7.1 Define event payload schemas.
- [ ] 7.2 Implement event publication at the saga lifecycle hooks (mirror `mqprtagent.PublishStepFromInput` calls in `lock_order_volume.go`).
- [ ] 7.3 Update mini-broker (and broker_admin / trade_bench when applicable) event handlers to react.

---

## Phase 8 — E2E tests

Goal: cover the workflow end-to-end. Per saved memory `feedback_saga_proto_changes_full_sweep.md`: changes ripple across categories.

- [ ] 8.1 New e2e file `tests/e2e/laser/lock_cash_test.go` covering:
  - Single LockCash submission → on-chain stash N has the locked amount.
  - Repeat with same EXIDS seed → idempotent (one stash, one balance increment).
  - Repeat with same stash-derivation seed but different EXIDS seed → cumulative (per O9 if confirmed) OR reject (per O9 if "reject").
- [ ] 8.2 New e2e `unlock_cash_test.go`:
  - Lock then unlock → balance returns to liquid; stash is empty.
  - Unlock with seed that was never locked → `FailedPrecondition` per O10.
- [ ] 8.3 New e2e `lock_then_withdraw_test.go` — the EXIDS D14.6.1 canonical workflow:
  - Lock 200 EUR with stash seed `transfer-156` (and a fresh EXIDS seed).
  - Verify on-chain stash N has 200 EUR.
  - Withdraw 200 EUR with the SAME stash seed `transfer-156` (and a different EXIDS seed).
  - Verify on-chain stash N is empty AND the investor's external bank account received the burned tokens' fiat equivalent (or whatever the existing withdraw assertion looks like).
- [ ] 8.4 New e2e `withdraw_from_liquid_test.go` — the LIQUID default path:
  - Withdraw with stash seed = `"LIQUID"` → sources from stash 0 (existing behaviour preserved).
- [ ] 8.5 New e2e `stash_derivation_collision_test.go` — exercise the algorithm with adversarially-similar seeds (`"a"`, `"aa"`, `"ab"`, etc. — assuming O1's char rules permit them; otherwise use the actual allowed charset). Assert all derived indices are distinct.
- [ ] 8.6 Update `Makefile` `E2E_CAT*_PATTERN`. Likely a NEW category (e.g. Cat 44 — Treasury Stash Operations) since these don't fit existing categories. Co-ordinate with `docs/E2E_TEST_CATALOG.md`.
- [ ] 8.7 Update `docs/E2E_TEST_CATALOG.md` with the new tests + category.

---

## Phase 9 — Docs sweep

- [ ] 9.1 Update CLAUDE.md: brktrdsvc daemon line in "Core Daemons" gets "+LockCash/UnlockCash live; WithdrawCash supports source stash" or similar.
- [ ] 9.2 Update `TODO_BRKTRDAPI_AND_BRKADMAPI.md` D8 / Phase 2 references to point here as the source of truth.
- [ ] 9.3 Update `TODO_EXECUTION_IDEMPOTENCY_SEED.md` D14.8: change the "(forthcoming)" marker on this file's reference to a normal cross-reference (no more "forthcoming"); confirm the EXIDS Phase 5.0 prerequisite is satisfied.
- [ ] 9.4 Add a one-line summary of STASHOPS to `MEMORY.md` if `kam` confirms this is durable enough to remember across conversations.

---

## Files this TODO is expected to touch (per phase)

| Phase | File / Dir | Action |
|---|---|---|
| 1 | `pkg/treasury/stash/derive.go` | NEW |
| 1 | `pkg/treasury/stash/derive_test.go` | NEW |
| 1 | `pkg/treasury/stash/README.md` | NEW |
| 2 | `pkg/daemons/treassvc/trax/executors/lock_cash/*.go` | NEW |
| 2 | `pkg/daemons/accmgr/api/v1/accounts_post_lock_cash.go` | NEW |
| 2 | `pkg/daemons/brktrdsvc/impl/v1/grpc/cash.go` (`lockCashIntoStash` helper) | EDIT |
| 2 | trax serializer registration (location TBD per O11) | EDIT |
| 3 | `pkg/daemons/treassvc/trax/executors/unlock_cash/*.go` | NEW |
| 3 | `pkg/daemons/accmgr/api/v1/accounts_post_unlock_cash.go` | NEW |
| 3 | `pkg/daemons/brktrdsvc/impl/v1/grpc/cash.go` (`unlockCashFromStash` helper) | EDIT |
| 3 | trax serializer registration | EDIT |
| 4 | `pkg/daemons/treassvc/trax/executors/withdraw_cash_tokens_from_account/transfer_from_account_to_clearing.go` | EDIT (source-stash parameterisation) |
| 4 | `pkg/daemons/treassvc/trax/executors/withdraw_cash_tokens_from_account/withdraw_and_burn_tokens.go` | EDIT (if needed) |
| 4 | `pkg/daemons/accmgr/api/v1/accounts_post_withdraw_cash_tokens.go` | EDIT (accept `source_stash_index`) |
| 5 | `pkg/daemons/brktrdsvc/impl/v1/grpc/cash.go` `WithdrawCash` (line 113) | EDIT |
| 5 | `pkg/daemons/brktrdsvc/impl/v1/grpc/cash.go` `withdrawCashTokensFromAccount` (line 219) | EDIT (signature) |
| 5 | `pkg/daemons/prtagent/impl/v1/grpc/investor.go` `WithdrawCash` (line 1085) | EDIT (per EXIDS O9) |
| 5 | `pkg/daemons/prtagent/impl/v1/grpc/investor.go` `withdrawCashTokensFromAccount` (line 266) | EDIT (signature) |
| 6 | `pkg/daemons/brktrdsvc/impl/v1/grpc/cash.go` `LockCash` (line 269) | EDIT (replace stub) |
| 6 | `pkg/daemons/brktrdsvc/impl/v1/grpc/cash.go` `UnlockCash` (line 278) | EDIT (replace stub) |
| 6 | `pkg/treasury/idempkey/builder.go` (new StepTemplateID constants) | EDIT |
| 7 | `pkg/daemons/.../mq*.go` (event publication) | EDIT |
| 7 | `apps/apps/legacy/mini-broker/lib/services/event_subscription_service.dart` (consume new events) | EDIT |
| 8 | `tests/e2e/laser/lock_cash_test.go` | NEW |
| 8 | `tests/e2e/laser/unlock_cash_test.go` | NEW |
| 8 | `tests/e2e/laser/lock_then_withdraw_test.go` | NEW |
| 8 | `tests/e2e/laser/withdraw_from_liquid_test.go` | NEW |
| 8 | `tests/e2e/laser/stash_derivation_collision_test.go` | NEW |
| 8 | `Makefile` `E2E_CAT*_PATTERN` | EDIT |
| 8 | `docs/E2E_TEST_CATALOG.md` | EDIT |
| 9 | `CLAUDE.md` | EDIT |
| 9 | `TODO_BRKTRDAPI_AND_BRKADMAPI.md` | EDIT |
| 9 | `TODO_EXECUTION_IDEMPOTENCY_SEED.md` (update D14.8 cross-reference) | EDIT |
| All | this file | EDIT continuously |

---

## Done criteria

- [ ] `LockCash` and `UnlockCash` handlers in brktrdsvc are no longer `Unimplemented`.
- [ ] `WithdrawCash` (brktrdsvc and prtagent per EXIDS O9) supports a non-zero source stash, defaulting to LIQUID (= 0) when the seed is `"LIQUID"`.
- [ ] The EXIDS D14.6.1 example workflow passes end-to-end (`lock_then_withdraw_test.go`).
- [ ] Two LockCash calls with the same `treasury_stash_derivation_seed` produce balances in the same on-chain stash (per O9 outcome).
- [ ] Algorithm for `deriveStashIndex` is deterministic, documented, and tested for collision behaviour.
- [ ] All new sagas use `idempkey.StepBuilder` with their own step-template-id constants.
- [ ] All affected e2e categories are green.
- [ ] CLAUDE.md daemon notes are updated.
