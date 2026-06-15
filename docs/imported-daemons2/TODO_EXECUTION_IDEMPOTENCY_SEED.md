# TODO: Client-Supplied `execution_idempotency_seed` for Treasury-Affecting RPCs

> **Status**: PLANNED (no work started — only this TODO exists)
> **Created**: 2026-05-10
> **Short ID**: `EXIDS`
> **Authoring rules**: per `feedback_phased_todo_authoring.md` (use established header + phase shape; bake in "ask `kam` liberally") and `feedback_pre_production_no_backcompat.md` (no shims, no deprecation flags, atomic per-surface flips)
> **Surfaces touched (this TODO)**:
> - `data/api/grpc/prtagent/v1/{trading,investor}.proto` (8 RPCs, 5 mutating)
> - `data/api/grpc/brktrdapi/v1/service.proto` (7 RPCs, all mutating)
> - `data/api/grpc/brkadmapi/v1/service.proto` (guard comment only — no current write RPCs)
> - `pkg/daemons/prtagent/impl/v1/grpc/{trading,investor}.go` (gateway handlers)
> - `pkg/daemons/brktrdsvc/impl/v1/grpc/{trading,cash}.go` (gateway handlers)
> - `pkg/treasury/idempkey/builder.go` (NO API changes — this is the validation contract; see D7)
> - `apps/apps/legacy/mini-broker/lib/screens/{trading_page,portfolio_page}.dart` and broker pages
> - `apps/apps/trade_bench/lib/features/...` (note: trading screens not yet built — see Phase 7)
> - `apps/packages/common_ui/lib/...` (NEW shared widget — both apps consume)
> - `tests/e2e/laser/{create_investor_order,create_direct_order,fund_account_*,chain_verification_fundaccount,order_test_infra}_test.go`
> - `Makefile` (E2E_CAT*_PATTERN), `docs/E2E_TEST_CATALOG.md`
> **Future surfaces (Phase 9, separate TODOs)**: every other gRPC API in the repo (sdappv1, exchappv1, prtagentappv1, csdmsggw, sdappgw, exchappgw, prtagentappgw) and every admin app under `apps/apps/` (security_depository_admin, exchange_admin, prtagent_admin, broker_admin, …)
> **Related Docs**:
> - `TODO_TREASURY_STASH_OPERATIONS.md` *(forthcoming — to be created before Phase 5 of this TODO begins; tracks the `LockCash`/`UnlockCash`/`WithdrawCash` saga implementation + `deriveStashIndex` algorithm. THIS TODO adds only the `treasury_stash_derivation_seed` wire field, validator, and Flutter widget — see D14.8 for the scope split.)*
> - `TODO_IDEMPOTENT_TREASURY_VAULT_OPERATIONS.md` (the on-chain `Erc20VaultIdempFacet` whose `SagaIdempotencyKey` per-step keys are derived from TOBIK — that work is COMPLETE)
> - `TODO_BRKTRDAPI_AND_BRKADMAPI.md` (where brktrd/brkadm RPC shapes were defined)
> - `TODO_INTENTSVC_FOR_FUND_CSD_ACCOUNTS.md` (TOBIK = `treas:<intent_id>` is the already-locked recipe for intentsvc-driven funds; this TODO replaces "intent_id" with "client-supplied seed" for the gRPC paths)
> - `TODO_CREATE_INVESTOR_ORDER_SAGA.md`, `TODO_CREATE_DIRECT_ORDER_SAGA.md`, `TODO_CANCEL_INVESTOR_ORDER_SAGA.md`, `TODO_CANCEL_DIRECT_ORDER_SAGA.md`
> - `TODO_FUND_ACCOUNT_WITH_CASH_TOKENS.md`
> - `TODO_STATE_ACTUATOR_SERVICE.md` (actusvc → accmgr propagation that carries TOBIK into `handle_*_fix_exec_report`)

---

## ⚠ Notes for the executing agent

This file is the **single source of truth**. Update it as you execute — it is not a one-shot spec. The companion implementation thread will consume this verbatim.

**Ask `kam` liberally.** Stop and ask before guessing whenever any of these come up:

- A request shape that *looks* like a write but you can't tell if it actually mutates a treasury balance (e.g. `RegisterInvestorAtDepositories`, `OnboardInvestor` — see open questions O1, O2).
- A saga step where the seed-to-derived-key recipe is ambiguous (e.g. multi-leg orders that touch >1 vault — see O4 + Phase 1 saga audit).
- A consumer outside the two named clients (mini-broker, trade_bench) that already calls one of the in-scope RPCs — DO NOT silently break it. List it, ask whether it's in scope for this TODO or parked for Phase 9.
- Anything in this doc that conflicts with what you observe in the code today — assume the doc is stale and ask. Use the file/line anchors throughout to verify each claim before acting on it.
- Compensation steps that today log `compensation_status: skipped_missing_treasury_ops_base_idempotency_key` (see Phase 4) — this WAS forgiving on purpose; tightening it to fail-loud is a behaviour change. Confirm before flipping each one.

**Pre-production project — no back-compat.** Per `feedback_pre_production_no_backcompat.md`: when the proto field flips to mandatory, every caller in the same commit gets the field. No fallback path, no `optional` modifier as a soft launch, no "during the migration window". If a caller can't be updated in the same commit, the proto change waits.

**TOBIK is the established term.** Per saved memory `project_intentsvc_design_locked.md`: TOBIK = Treasury Ops Base Idempotency Key = the saga-input field whose canonical key name is `treasury_ops_base_idempotency_key` (defined as `idempkey.InputKey` at `pkg/treasury/idempkey/builder.go:38`). All references in this document use TOBIK as the abbreviation.

---

## ☝ Single most important contract (read this before anything else)

**The client sends exactly ONE string: `execution_idempotency_seed`.**

It does NOT send per-step keys. It does NOT know the OpSuffix table. It does NOT pre-derive `cio_lock_order_volume` or `wcfa_withdraw_and_burn` or `facwct_mint_tokens_if_needed` or anything like that.

The server takes that one string, places it verbatim into `sagaInput["treasury_ops_base_idempotency_key"]`, and the **already-built** machinery in `pkg/treasury/idempkey/builder.go` mints every per-step idempotency key from it via:

```go
treasuryOpsBaseIdempotencyKey, _ := idempkey.RequireFromInput(input, "<step>")
perStepKey := idempkey.New(treasuryOpsBaseIdempotencyKey).For(idempkey.<OpSuffix>)
```

The 19 typed `OpSuffix` constants at `pkg/treasury/idempkey/builder.go:15-35` (`LockValue`, `LockValueComp`, `FeeTransfer`, `UnlockStash`, `FundMint`, `FundDeposit`, `WithdrawBurn`, `Erc20Transfer`, …) are **server-side implementation detail**. The client is blissfully unaware of them. If a new OpSuffix is added tomorrow, no client changes; the existing seed automatically mints the new step's key too.

Because `Builder.For(s) = base + "-" + string(s)` (builder.go:52-54), determinism is automatic: same seed in → same per-step keys out, every time, on every server, in every retry.

**This is the entire idea.** Everything below is plumbing. Don't lose this in the noise.

---

## Overview

### Today (the part you don't change)

The treasury-side idempotency machinery is COMPLETE. The end-to-end chain works as follows:

```
   client gRPC ────►   gateway (prtagent / brktrdsvc)
                      │
                      │  derives TOBIK from request fields
                      │  e.g. "cio:<participant>:<order_id>:<listing>:<qty>"
                      │       at trading.go:584
                      ▼
                  saga submission via TRAX
                      │  sagaInput["treasury_ops_base_idempotency_key"] = TOBIK
                      ▼
                  treassvc / accmgr saga executors
                      │  treasuryOpsBaseIdempotencyKey, _ := idempkey.RequireFromInput(input, "<step>")
                      │  perStepKey := idempkey.New(base).For(idempkey.<OpSuffix>)
                      ▼
                  lcmgr / Erc20VaultIdempFacet on-chain
                      │  uses bytes32(perStepKey) — see ITVOP TODO
                      ▼
                  on-chain idemp facet rejects duplicate
```

For **post-trade flows triggered by FIX**, TOBIK is propagated:

```
   marketmgr orderbook  ◄── tradeidxer indexes the order with TOBIK
                       │   (TOBIK was stored in the order_request row at submit time)
                       │
   actusvc reads exec report ◄── fixreceiver writes execution_reports
                       │
                       ▼  POST /accounts/.../handle-fix-exec-report
                       │   body includes treasury_ops_base_idempotency_key
                       │   actusvc/actions.go:187, 234
                       ▼
   accmgr handle_*_fix_exec_report sagas
                       │   inject TOBIK into the spawned child sagas:
                       │   - unlock_order_stash
                       │   - return_fee
                       │   - deposit_fill_proceeds
                       ▼
   treassvc per-step executors (lock-value, fee-transfer, unlock-stash, …)
```

The 19 step suffixes are enumerated in `pkg/treasury/idempkey/builder.go:15-35` (LockValue, LockValueComp, FeeTransfer, FeeTransferComp, UnlockStash, UnlockStashComp, FundTransfer, FundMint, FundApprove, FundDeposit, AuthorizedInstr{Transfer,Mint,Approve,Deposit}, WithdrawTransfer, WithdrawFromVault, WithdrawBurn, Erc20Transfer, Erc20TransferComp).

### What this TODO changes

The last remaining gap: **the gateway derives TOBIK itself**, so the client has no idempotency control.

After this TODO:
- The client supplies `execution_idempotency_seed` on every treasury-affecting RPC.
- The gateway uses it **verbatim** as TOBIK — it stops generating TOBIK from request fields.
- The same logical operation submitted twice (network retry, app restart, user double-tap) produces identical TOBIKs, identical per-step keys via `idempkey.Builder`, and the on-chain `Erc20VaultIdempFacet` makes the second call a no-op.
- The compensation paths that currently degrade gracefully (`OptionalFromInput`, `compensation_status: skipped_missing_treasury_ops_base_idempotency_key`) become fail-loud, because the field is now mandatory at the boundary.

### What this TODO does NOT change

- The `idempkey` package API. `Builder.For(OpSuffix)`, `RequireFromInput`, `OptionalFromInput`, `InputKey` constant — all stay as-is.
- The on-chain `Erc20VaultIdempFacet` and the `SagaIdempotencyKey` per-vault-call mechanism. That work is COMPLETE under `TODO_IDEMPOTENT_TREASURY_VAULT_OPERATIONS.md`.
- The 19 OpSuffix constants. Adding new step suffixes is out of scope unless Phase 1's audit uncovers a missing case.
- The actusvc → accmgr REST shape. Already carries TOBIK; nothing to change there.
- The intentsvc TOBIK contract (`treas:<intent_id>`) per `project_intentsvc_design_locked.md`. The intentsvc path is orthogonal to gRPC; both will end up writing TOBIK into the same saga input slot.

### Two responsibilities, two layers

| Layer | Responsibility | Owner |
|---|---|---|
| Client | Generate a seed that is **deterministic from the operation inputs** (no time, no random, no UUID). Re-submission with identical inputs yields an identical seed. | Client app code (mini-broker, trade_bench, future suite apps) |
| Server | Validate (non-empty, length, no whitespace) at the gateway boundary. Pass verbatim into `sagaInput["treasury_ops_base_idempotency_key"]`. From there `idempkey.Builder` does the rest. Reject if missing. | Gateway handlers (prtagent, brktrdsvc, …) |

---

## Decisions locked

### D1 — Field name and shape

- Wire field: `string execution_idempotency_seed`.
- **Mandatory.** Empty / whitespace-only → gateway returns `codes.InvalidArgument` immediately, before any saga is started, before any cache lookup, before any other validation. First check after auth.
- Opaque UTF-8 string. **Server does not interpret it** beyond using it as TOBIK.
- **Strict character set**: regex **`^[A-Za-z0-9:_.-]{8,256}$`**. ASCII byte length, NOT character count (Go `len(s)`, Dart `utf8.encode(s).length`).
  - Allowed: ASCII letters `A-Z`, `a-z`, digits `0-9`, and the four punctuation characters `:` (prefix delimiter, `cio:v1:`), `_`, `-` (base64url-safe), `.` (version dots).
  - **Disallowed and rejected with a specific error** (see error-code table below):
    - Whitespace of any kind: space, tab, newline, CR, vertical tab, form feed, NBSP, every Unicode whitespace.
    - Control characters: `0x00-0x1F`, `0x7F`.
    - Quote / escape footguns: `"`, `'`, `` ` ``, `\`.
    - HTML/XML hazards: `<`, `>`, `&`.
    - URL-path delimiters: `/`, `?`, `#`.
    - SQL hazards beyond what's listed: `;`, `%`.
    - Base64 standard-variant chars not in the safe subset: `+`, `=`, `/`.
    - Brackets / parens: `(`, `)`, `[`, `]`, `{`, `}`.
    - Math/misc: `*`, `,`, `^`, `~`, `|`, `!`, `@`, `$`.
    - All non-ASCII bytes (`> 0x7F`): rules out emoji, smart quotes, accented characters, NFC/NFKC normalisation drift. If the client even *thinks* about typing `é` we'd rather hard-fail than silently normalise.
  - Case-sensitive. Recipes produce lowercase hex by convention (sha256 hex output is lowercase); manual values are accepted in any case but are NOT normalised — `Cio:V1:abc` and `cio:v1:abc` are different seeds.
  - Length: **min 8 bytes, max 256 bytes**. Min 8 forbids degenerate values like `a:b` that carry no entropy. Max 256 leaves headroom for the per-step suffixing chain (`<seed>-<step_template>-<op_suffix>` ≤ ~340 bytes total; well within Postgres `text` column limits and on-chain `bytes32(keccak256(...))` collapse).
  - **Reject before trim.** Do NOT silently trim leading/trailing whitespace — that hides client bugs that produce non-deterministic seeds.
  - Validation MUST run BEFORE any other check (auth excepted) so the error is fast and unambiguous.
- No `optional` modifier. proto3 default-empty is treated as missing.
- **Field number: `200` on every Request message across every affected proto.** Verified unused via `grep "= 200" data/api/grpc/{prtagent,brktrdapi,brkadmapi}/v1/*.proto` (zero hits as of 2026-05-10). One number, zero exceptions, zero per-message variation. If 200 is ever taken in a future surface added to EXIDS, the new surface picks a free number AND we update this D1 to record the exception explicitly.

#### D1.1 — Validation error-code table (gateway → client)

The gateway returns `codes.InvalidArgument` with a `message` of the form `execution_idempotency_seed: <reason>` and a structured `error_details` field carrying the machine-readable reason code:

| Reason code | Trigger | Example client message |
|---|---|---|
| `EXIDS_MISSING` | field absent / zero-length | `execution_idempotency_seed: required field is empty` |
| `EXIDS_TOO_SHORT` | `len < 8` | `execution_idempotency_seed: must be at least 8 bytes (got 3)` |
| `EXIDS_TOO_LONG` | `len > 256` | `execution_idempotency_seed: must be at most 256 bytes (got 412)` |
| `EXIDS_LEADING_WHITESPACE` | starts with `[ \t\n\r]` or any `unicode.IsSpace` rune | `execution_idempotency_seed: must not start with whitespace` |
| `EXIDS_TRAILING_WHITESPACE` | ends with same | `execution_idempotency_seed: must not end with whitespace` |
| `EXIDS_INNER_WHITESPACE` | contains any whitespace anywhere (covers tabs, NBSP, etc.) | `execution_idempotency_seed: must not contain whitespace` |
| `EXIDS_CONTROL_CHAR` | contains `0x00-0x1F` or `0x7F` | `execution_idempotency_seed: must not contain control characters (byte 0x09 at offset 12)` |
| `EXIDS_NON_ASCII` | contains any byte > `0x7F` | `execution_idempotency_seed: must be ASCII-only (byte 0xC3 at offset 8)` |
| `EXIDS_DISALLOWED_CHAR` | contains an ASCII char outside `[A-Za-z0-9:_.-]` | `execution_idempotency_seed: character '/' at offset 14 is not allowed (allowed: [A-Za-z0-9:_.-])` |

Errors are checked in the order listed above so the most specific reason wins. The validator MUST report the **byte offset** of the first violation when applicable — debugging non-deterministic seeds is much easier when the client sees "the rogue tab is at offset 12" instead of just "invalid".

#### D1.2 — Single canonical regex shipped server-side AND client-side

The regex is stored in exactly one place per language and consumed by every handler:

- **Go** (`pkg/grpc/exids/validator.go`, NEW per Phase 5.4): `var SeedRegex = regexp.MustCompile(`^[A-Za-z0-9:_.-]{8,256}$`)` — but the validator does NOT use `regexp.MatchString` for the failing path; it iterates byte-by-byte to produce the offset-pointing error messages above. The regex is the spec; the validator is the implementation.
- **Dart** (`apps/packages/common_ui/lib/services/exids_validator.dart`, NEW per Phase 6): identical regex literal. Same byte-offset error reporting.
- **Doc**: this D1 section is the single source of truth. If the regex ever changes (Phase 9 expansion may need it), update D1 and propagate to both implementations in the same commit.

### D2 — Orthogonal to `proposed_execution_id`

Both fields stay on every RPC. The two serve different purposes:

| Field | Purpose | Owner | Identity across retries |
|---|---|---|---|
| `proposed_execution_id` | Per-call execution / trace ID. Identifies *this RPC invocation* for log correlation. Used as `RefExecutionId` on the `ExecutionAsyncResponse`. | Client suggestion → gateway canonicalises | **New** on every retry |
| `execution_idempotency_seed` | Logical-operation identity. Same value across N retries means "same logical operation". Drives TOBIK. | Client only. Gateway uses verbatim. | **Stable** across retries |

A retrying client sends a **new** `proposed_execution_id` and the **same** `execution_idempotency_seed`. The gateway can both (a) trace this specific call and (b) recognise the operation is logically identical to the prior one.

### D3 — Scope of "treasury-affecting RPC" for this TODO

The Phase 2/5 surfaces:

#### `prtagent/v1` — `TradingService` (file: `data/api/grpc/prtagent/v1/trading.proto`)

| RPC | Request message | Status today | This TODO |
|---|---|---|---|
| `CreateOrderAsync` | `CreateOrderAsyncRequest` (line 136) | Gateway derives TOBIK at trading.go:584 | Add field; gateway uses verbatim |
| `ReplaceOrderAsync` | `ReplaceOrderAsyncRequest` (line 163) | Stub today (handler at trading.go:831 — verify) | Add field; wire when handler lands |
| `CancelOrderAsync` | `CancelOrderAsyncRequest` (line 179) | Real handler at trading.go:835; cancel saga unlocks the order stash → mutates treasury | Add field |

#### `prtagent/v1` — `InvestorService` (file: `data/api/grpc/prtagent/v1/investor.proto`)

| RPC | Request message | Status today | This TODO |
|---|---|---|---|
| `DepositCash` | `DepositCashRequest` (line 206) | Handler at investor.go:1004; gateway derives TOBIK at investor.go:328 (`facwct:%s:%s:%s:%s`) | Add field; gateway uses verbatim |
| `WithdrawCash` | `WithdrawCashRequest` (line 221) | Handler at investor.go:1085; gateway derives TOBIK at investor.go:279 (`wcfa:%s:%s:%s:%s`) | Add field |
| ~~`WithdrawSecurity`~~ | ~~`WithdrawSecurityRequest` (line 236)~~ | Handler at investor.go:1166 returns `Unimplemented` today | **REMOVED entirely** — per O1 resolution + `TODO_BRKTRDAPI_AND_BRKADMAPI.md` D6 ("DepositSecurity / WithdrawSecurity. Removed by D6 — investors don't move securities, was a design flaw, resolved"). Same removal extended to prtagent v1: delete RPC from service block, delete `WithdrawSecurityRequest` and `WithdrawSecurityResponse` messages from investor.proto, delete handler at investor.go:1166. See Phase 2.x. |

#### `brktrdapi/v1` — `BrokerTradingApiService` (file: `data/api/grpc/brktrdapi/v1/service.proto`)

| RPC | Request message | Status today | This TODO |
|---|---|---|---|
| `CreateOrder` | `CreateOrderRequest` (line 279) | Handler at brktrdsvc/.../trading.go:44; derives TOBIK at line 195 | Add field; gateway uses verbatim |
| `ReplaceOrder` | `ReplaceOrderRequest` (line 297) | Stub at brktrdsvc/.../trading.go:265 | Add field; wire when handler lands |
| `CancelOrder` | `CancelOrderRequest` (line 307) | Real at brktrdsvc/.../trading.go:285 | Add field |
| `DepositCash` | `DepositCashRequest` (line 241) | Handler at brktrdsvc/.../cash.go:40 | Add field |
| `WithdrawCash` | `WithdrawCashRequest` (line 249) | Handler at brktrdsvc/.../cash.go:113; derives TOBIK at cash.go:210 | Add field |
| `LockCash` | `LockCashRequest` (line 258) | **REAL handler as of 2026-05-11** (commit `135ad0277`) — submits TABT (`treasury_asset_balance_transfer`) saga via `cashStashTransfer`. EXIDS + stash validators run eagerly. See `docs/TODO_CASH_STASH_TRANSFER_SAGA.md`. | **Adds TWO mandatory fields:** `execution_idempotency_seed = 200` (new, per D1) AND `treasury_stash_derivation_seed = 5` (rename of existing `broker_input` per D13/O5; `LIQUID` AND numeric "0" REJECTED per D14 + TABT O12). |
| `UnlockCash` | `UnlockCashRequest` (line 267) | Stub at cash.go pending TABT O9 proto Amount field. Validators run eagerly; saga + accmgr REST support unlock end-to-end. | TWO mandatory fields, `LIQUID` + numeric "0" REJECTED. TABT O9 also adds `amount` field for partial unlocks (Phase 2 proto extension). |

#### `brktrdapi/v1` — onboarding RPCs (mandatory field, downstream consumer pending)

| RPC | Request message | Status today | This TODO |
|---|---|---|---|
| `OnboardInvestor` | `OnboardInvestorRequest` (line 221) | Handler exists | **Per O2: add field, validate at gateway, pass into saga input — but document that downstream broker-side onboarding logic does not currently consume it.** Mandatory at boundary for future use cases (when onboarding gains treasury write side-effects). |
| `RegisterInvestorAtDepositories` | `RegisterInvestorAtDepositoriesRequest` (line 230) | Stub today | **Per O2: same as OnboardInvestor — mandatory at boundary, passed into the CSD function, downstream CSD logic does not currently consume it.** When the CSD-side handler is implemented, the seed is already in the saga input slot ready for use. |

For O2-scoped RPCs, add a comment in the proto next to the field:

```proto
// REQUIRED. Mandatory at the gateway boundary. The downstream onboarding /
// CSD logic does not currently read this field — it is reserved for future
// use cases that introduce treasury writes at this saga step. See D-O2 in
// docs/TODO_EXECUTION_IDEMPOTENCY_SEED.md.
string execution_idempotency_seed = 200;
```

#### `brkadmapi/v1` — guard comment only

All current RPCs are read-only oversight: `Ping`, `PollExecution`, `WaitForExecution`, `GetParticipant`, `ListParticipantHoldings`, `ListParticipantOrders`, `GetBrokerCsdInfo`, `ListInvestors`, `ListMarkets`, `ListVenues`, `GetOrderbook`, `ListSecurityListings`, `ListCashTokens`, `ListExecutionReports`, `ListTradeReports`, `ListTreasuryActivities`, `ListAgoraEvents`, `ListSagas`, `GetSaga`, `GetSagaTree`, `WatchSaga`, `ListAccounts`, `ListLegalStructures`, `ListLegalMechanisms`, `ListApiKeys`, `ResolveDisplayNamesByIid`. No `Create*`/`Submit*`/`Lock*`/`Unlock*`/`Deposit*`/`Withdraw*` exists today.

Add a guard block in `data/api/grpc/brkadmapi/v1/service.proto`, just above the `service BrokerAdminApiService { ... }` opening brace:

```proto
// EXIDS contract (docs/TODO_EXECUTION_IDEMPOTENCY_SEED.md):
// Any RPC added below that mutates a treasury balance (deposit / withdraw /
// lock / unlock / transfer / mint / burn on cash or security vaults) MUST
// include `string execution_idempotency_seed` as a mandatory field
// (validated at the gateway boundary, used verbatim as the saga's
// `treasury_ops_base_idempotency_key`). See D3 of that TODO.
```

### D4 — Auto-generation rules (client-defined recipe, doc spells out invariants)

> **Per O3 resolution**: every recipe MUST have a per-RPC namespace prefix (e.g. `cio:v1:`, `dep:v1:`, `lck:v1:`). This guarantees that two seeds for two different RPCs can never collide even if their hashed payloads happen to match. The gateway's same-seed-different-payload guard (Phase 3) leans on this: collision detection is scoped per-RPC, and the prefix makes that trivially safe.


Clients pick their own canonical-input → seed recipe **as long as** the recipe satisfies:

1. **Deterministic.** Given identical inputs the seed is identical. NO time component (`Date.now`, `DateTime.now()`, `Stopwatch`, `clock`), NO random source (`Random`, `crypto.getRandomValues`), NO UUID, NO monotonic counter, NO IP address, NO session token, NO request id.
2. **Stable across re-renders.** Closing and re-opening the form, navigating away and back, restarting the app, switching theme, changing locale — none of these may change the seed if the inputs are unchanged.
3. **Sensitive to every functionally-distinct input.** Two requests that would produce different on-chain effects MUST produce different seeds.
4. **Insensitive to cosmetic input.** Apply BEFORE hashing:
   - Trim leading/trailing whitespace on every string field.
   - Normalise decimal strings (`"1.0"` → `"1"` → `"1.000000"`? — pick one canonical form per field type and document next to the recipe).
   - Lowercase hex IIDs only if the surrounding code already does (be conservative — over-canonicalisation is itself non-determinism).
   - Sort map/list keys when the input is conceptually unordered.
5. **Length-bounded ≤ 256 bytes** (D1). Recommended recipe: `"<rpc>:v1:" + hex(sha256(canonical_input_blob))` — total ≈ 75 bytes.
6. **Sensitive to recipe version.** The `:v1:` prefix lets you bump the recipe later without colliding with old seeds. If the recipe ever changes, increment to `:v2:` and document the migration in this file.
7. **Self-describing prefix encouraged** for human readability in audit logs; server treats the entire string as opaque.

The TODO does NOT mandate a specific tuple per RPC. The implementing agent for the client side picks the tuple, documents it in the client codebase next to the helper, and writes a unit test asserting (a) determinism (5000 calls produce identical output), (b) sensitivity (mutating any input field changes the seed), (c) insensitivity to cosmetic noise.

#### Suggested per-RPC canonical input tuples (advisory — confirm with `kam` per RPC)

These mirror the existing server-side recipes verbatim where possible, so the seed produced by an auto-generated client matches the TOBIK that the gateway *used* to derive — preserving determinism continuity:

| RPC | Existing server recipe | Suggested client recipe |
|---|---|---|
| `CreateOrderAsync` (prtagent) | `cio:%s:%s:%s:%s` (participant, investor_order_id, listing, qty) at trading.go:584 | `cio:v1:` + sha256(`participant_iid|external_investor_id|security_listing_iid|side|order_type|quantity|price|currency|fee_amount|investor_order_id|fee_payer_account_iid`) |
| `ReplaceOrderAsync` (prtagent) | none today | `rio:v1:` + sha256(`old_participant_order_id|new_participant_order_id|new_quantity|new_price|new_expire_time`) |
| `CancelOrderAsync` (prtagent) | none today | `xio:v1:` + sha256(`participant_iid|external_order_id|reason`) |
| `DepositCash` (prtagent) | `facwct:%s:%s:%s:%s` (legal_struct, account, ccy, amount) at investor.go:328 | `dep:v1:` + sha256(`participant_iid|external_investor_id|currency_code|amount`) |
| `WithdrawCash` (prtagent) | `wcfa:%s:%s:%s:%s` at investor.go:279 | `wdr:v1:` + sha256(`participant_iid|external_investor_id|currency_code|amount`) |
| `CreateOrder` (brktrdapi) | `cio:%s:%s:%s:%s` at brktrdsvc/trading.go:195 | mirror prtagent CreateOrderAsync recipe (fields slightly different — `venue_iid` is REQUIRED in brktrd CreateOrder, include it) |
| `DepositCash` (brktrdapi) | (per cash.go:210) | mirror prtagent DepositCash recipe |
| `WithdrawCash` (brktrdapi) | (per cash.go:210) | `wdr:v1:` + sha256(`participant_iid|external_investor_id|currency_code|amount|treasury_stash_derivation_seed`) — stash seed is part of the tuple so a withdraw from `LIQUID` and a withdraw from `transfer-156` produce different idempotency seeds |
| `LockCash` (brktrdapi) | n/a (stub) | `lck:v1:` + sha256(`participant_iid|external_investor_id|currency_code|amount|treasury_stash_derivation_seed`) — stash seed REQUIRED + non-LIQUID here per D14, so always present and contributes to the hash |
| `UnlockCash` (brktrdapi) | n/a (stub) | `ulk:v1:` + sha256(`participant_iid|external_investor_id|currency_code|treasury_stash_derivation_seed`) |
| `WithdrawCash` (prtagent, pending O9) | (no stash field today) | `wdr:v1:` + sha256(`participant_iid|external_investor_id|currency_code|amount|treasury_stash_derivation_seed`) — same as brktrdapi |
| `CancelOrder` (brktrdapi) | mirror prtagent CancelOrderAsync | same |
| `ReplaceOrder` (brktrdapi) | mirror prtagent ReplaceOrderAsync | same |

Open question O7 (Phase 1 audit): once the recipe is locked, do we ALSO change the gateway to *fall back* to the server recipe when seed is empty during a transition window? **Per `feedback_pre_production_no_backcompat.md`: NO. Atomic flip per surface.** Gateway rejects empty seed in the same commit that adds the field.

### D5 — UI shape (mini-broker + trade_bench, single shared widget in `common_ui`)

A reusable Flutter widget sits at the bottom of every form that calls one of the in-scope RPCs:

```
┌──────────────────────────────────────────────────────────────────┐
│ ☑ Auto-generate execution idempotency seed                       │
│                                                                  │
│ Execution idempotency seed                                       │
│ ┌────────────────────────────────────────────────────────────┐ ▾ │
│ │ cio:v1:7f3a8c34a9d21e6b8c4d5e2f1a0b9c8d7e6f5a4b3c2d1e0f… │   │  ← read-only when checked
│ └────────────────────────────────────────────────────────────┘   │
│                                                                  │
│ ⓘ Auto-derived from the order inputs above.                      │
└──────────────────────────────────────────────────────────────────┘
```

When the user unchecks the box:

```
┌──────────────────────────────────────────────────────────────────┐
│ ☐ Auto-generate execution idempotency seed                       │
│                                                                  │
│ Execution idempotency seed                                       │
│ ┌────────────────────────────────────────────────────────────┐ ▾ │
│ │ my-custom-seed-abc                                         │   │  ← editable
│ ├────────────────────────────────────────────────────────────┤   │
│ │ cio:v1:7f3a8c…  (today 14:02 — BUY 100 BETA @ 12.50)      │   │  ← dropdown shows
│ │ cio:v1:9b2e1d…  (today 11:45 — BUY 50 BETA @ 12.45)       │   │     local history
│ │ cio:v1:2a8c4f…  (yesterday 16:33 — SELL 200 BETA @ 12.60) │   │     for this RPC + investor
│ │ + 47 more …                                                │   │
│ └────────────────────────────────────────────────────────────┘   │
│                                                                  │
│ ⚠ Seed differs from auto-derived value.                          │
└──────────────────────────────────────────────────────────────────┘
```

**Behaviour rules:**

- **Default state: checkbox CHECKED.** Field is read-only and shows the current auto-derived seed.
- The widget subscribes to a `Stream<Map<String, dynamic>>` of the form's currently-bound input map (or equivalent — `ChangeNotifier`, `ValueListenable`, `Riverpod` provider, whatever the host page uses). Re-derives on every emission. No polling, no timers.
- **Uncheck → field becomes editable AND the trailing chevron reveals a search-and-edit combobox** over the locally-persisted history of recent seeds for `(rpc, investor)` (see D6). The user can:
  - Type a free-form value (validated: non-empty, ≤256 bytes, no leading/trailing whitespace, ASCII printable subset).
  - Pick an old seed from the dropdown (clicking it copies it into the text field, where it can be further edited).
  - Type to filter the dropdown by substring match against the seed value AND the human-readable annotation ("BUY 100 BETA").
- **Re-check** → the field is overwritten with a freshly-recomputed auto-seed. Show a `SnackBar` / toast: "Reverted to auto-derived seed. Your custom value `<truncated>` was discarded." This is intentionally noisy — silent overwrite would be a footgun.
- **Manual value equals auto-recipe output** → silently treat as auto. Don't penalise the user for hand-typing a value that happens to match.
- The hint icon (ⓘ) shows a tooltip explaining what the seed does and why retries with the same seed are safe.
- The warning icon (⚠) appears only when (a) checkbox is unchecked AND (b) value differs from current auto-derived value. Helps the user notice when the form has changed since they overrode the seed.

**Validation gates** (block submit until satisfied):
- Non-empty after trim.
- Length ≤ 256 bytes (UTF-8 byte length, not character count — Dart `utf8.encode(s).length`).
- No leading/trailing whitespace (do not auto-trim).
- ASCII printable subset `[0x20-0x7E]` only — control chars and emoji are rejected (rationale: keep audit logs greppable; if `kam` wants to relax this, change the recipe rule, not the widget).

**Accessibility:**
- Checkbox label is a single line, screen-reader friendly.
- Field has its own `Semantics` label "Execution idempotency seed".
- Dropdown items have a structured semantic label (seed value + annotation read separately).
- Keyboard: Tab moves checkbox → field; Down-arrow opens dropdown when field is focused.

#### D5.1 — Copy + full-screen modal viewer for long seeds

Seeds at the upper end of D1 (256 bytes) don't fit comfortably in a single-line text field. The widget MUST expose two affordances for inspecting a full seed:

- **Copy button** — a small icon button (`Icons.copy_outlined` or `Icons.content_copy`) sits inside the field's `suffixIcon` row, to the left of the dropdown chevron. Tap copies the current seed value to the system clipboard via `Clipboard.setData(ClipboardData(text: seed))`. Show a brief `SnackBar`: "Seed copied (74 chars)" with the live length so the user knows what they got.
- **Expand-to-modal button** — a second icon button (`Icons.open_in_full` or `Icons.zoom_out_map`) opens a full-screen modal that:
  - Displays the seed in a large monospaced text area (read-only when the parent checkbox is checked, editable otherwise).
  - Wraps long text across multiple lines so every byte is visible without horizontal scrolling.
  - Shows live byte length and character class breakdown (e.g. "74 bytes — letters: 60, digits: 13, separators: 1").
  - Has its own copy button at the top-right.
  - Has a "Close" button (Esc on desktop) that dismisses without saving.
  - When editable: a "Save" button validates the value (D1 character set + length rules with byte-offset error) and pops back. Validation errors render inline inside the modal — same error-code table as the gateway (D1.1).

ASCII layout of the inline field with both icons:

```
Execution idempotency seed
┌──────────────────────────────────────────────┐ ⧉ ⤢ ▾
│ cio:v1:7f3a8c34a9d21e6b8c4d5e2f1a0b9c8d7e…   │
└──────────────────────────────────────────────┘
                                          copy↑ ↑expand  ↑history
```

The expand-modal also serves the **history list** — when invoked from the dropdown's "view all" entry, it renders every history row with the same readability properties + a per-row copy button + a per-row "use this" button that fills it back into the parent field.

**Why a modal**: a 256-byte seed is unreadable in a 280-pixel-wide text field on mobile and uncomfortably truncated even on desktop. The modal is the only safe way to confirm "is this the value I think it is" before submitting an irreversible operation. Required for the read-only auto-derived case too (the user must be able to *audit* the auto seed, not just trust it).

**Tooltip placement**: hover/long-press on the copy or expand icon shows "Copy seed to clipboard" / "Open full-screen view".

**Keyboard shortcut on desktop**: when the field has focus, `Ctrl/Cmd+C` copies; `Ctrl/Cmd+Shift+E` opens the expand modal. (Mobile has only the tap affordances.)

**Implementation note for the executing agent**: the two icons + the modal live in the same `ExecutionIdempotencySeedField` widget under `apps/packages/common_ui/lib/widgets/`. Don't fork into per-app variants. The modal itself is its own widget `ExecutionIdempotencySeedViewerDialog` — exposable for any other place in the suite that wants to render a long seed (Phase 9 admin apps will reuse it).

### D6 — Local seed history persistence (mini-broker + trade_bench)

Per Q4 in the planning round: **local-only, per installation.** No server roaming yet.

| Property | Value |
|---|---|
| Storage backend | `SharedPreferences` (Flutter) for both apps |
| Upgrade path | If queries get expensive (>50ms on warm cache), switch to `sqflite` — but DO NOT add `sqflite` until measured. Avoid `Hive` (extra build artifacts). |
| Key schema | `exids.history.<rpc_name>.<external_investor_id>` |
| Value schema | JSON-serialised `List<Map<String, dynamic>>`, each entry: `{seed: string, ts_local_iso: string (UTC ISO-8601 — see `feedback_dates_utc_in_json_local_in_ui.md`), input_summary: string (human-readable e.g. "BUY 100 BETA @ 12.50 EUR"), input_hash: string (sha256 of canonical inputs)}` |
| Cap | **50 most recent entries per (rpc, investor)** |
| Eviction | Drop oldest on overflow |
| Size budget | ~75 bytes seed + ~50 bytes annotation + ~30 bytes timestamp = ~155 bytes/entry × 50 entries × ~10 (rpc, investor) pairs = **~75 KB** worst-case per installation. Well within `SharedPreferences` limits. |
| Write trigger | On a successful gateway submission (`PollExecution` returns `OK` for the submitted execution at least once — even before the saga COMPLETES). DO NOT write on local form changes; the field re-recomputes constantly while typing and that would flood storage. |
| Read trigger | On opening the combobox dropdown when checkbox is unchecked. Lazy: don't load on every form open. |
| Privacy | `input_summary` MUST NOT contain PII or secrets. Use only fields the user already sees on screen. |
| Cleanup on logout | Delete entries for that investor's external ID — privacy hygiene. Implement in the auth-service logout hook of each app. |

**Phase 9 (out of scope here)**: a server-side `ListExecutionIdempotencySeeds` RPC that lets the user roam between devices. Track in `TODO_EXIDS_EXPANSION_TO_ADMIN_APIS.md` when it materialises.

### D7 — Server contract: seed → TOBIK → per-step keys (no new code)

**Restating the single-most-important-contract from the top callout:** the client sends ONE string. The server's existing `idempkey` package mints every per-step key from it. The client never sees, names, or derives any per-step key.

The gateway:

1. Validates `execution_idempotency_seed` per D1 (non-empty, ≤256 bytes, no whitespace, ASCII printable, before any other check).
2. Sets `sagaInput["treasury_ops_base_idempotency_key"] = req.GetExecutionIdempotencySeed()` **verbatim**. No hashing, no namespacing, no concatenation, no `cio:` / `facwct:` / `wcfa:` prefix injection. The client decides what those prefixes mean (D4); the server treats the whole string as opaque.
3. Removes the existing server-side derivation lines (file:line catalogue in Phase 2/5 below).

Downstream (already built — DO NOT TOUCH):

- Every saga executor that needs a per-step key calls `idempkey.RequireFromInput(input, "<step>")` to fetch TOBIK and `idempkey.New(base).For(idempkey.<OpSuffix>)` to mint the per-step key. The OpSuffix is selected by the executor for its specific operation (e.g. `lock_order_volume.go` uses `LockValue` for the forward step and `LockValueComp` for the compensation). The client has no involvement.
- The 19 OpSuffix constants at `builder.go:15-35` are the **server-side enumeration of every distinct treasury operation**. Adding a new OpSuffix requires only a server change; no client coordination needed because the client only sends the seed.
- New OpSuffix constants are added **only** if Phase 1 audit reveals a treasury vault mutation that today reuses an existing suffix incorrectly. (Verify in Phase 1.) When added, every existing client seed automatically mints the new key — zero migration cost.
- Postgres dedup at `lcmgr.trz_erc20_idempotency_keys` (see `pkg/daemons/lcmgr/contract_store_pgsql.go:1738-1753`) needs no schema change — it's already keyed on `(chain_id, trezor_contract_address, idempotency_key)` where `idempotency_key` is the per-step key derived from TOBIK.

**Why this design:** the per-step OpSuffix table is a server-side implementation concern (it changes when sagas are refactored, when new on-chain operations are added, when compensation paths gain new steps). Forcing the client to know that table would couple every UI release to every backend saga refactor. By contrast, the seed contract is **frozen forever**: one string, deterministic from inputs, that's it.

### D8 — Tighten the soft "skipped_missing_treasury_ops_base_idempotency_key" branches

Today, several compensation paths gracefully skip when TOBIK is missing:

- `pkg/daemons/treassvc/trax/executors/create_investor_order/lock_order_volume.go:275`
- `pkg/daemons/treassvc/trax/executors/create_investor_order/transfer_fee.go:300`
- `pkg/daemons/treassvc/trax/executors/unlock_order_stash/transfer_stash.go:236`

The accmgr REST handlers also currently log a WARN rather than rejecting when TOBIK is absent:

- `pkg/daemons/accmgr/api/v1/accounts_post_handle_fix_exec_report.go:149-150`
- (search for `TreasuryOpsBaseIdempotencyKey == ""` to find others)

The `idempkey.OptionalFromInput` helper at `pkg/treasury/idempkey/builder.go:76-84` exists specifically to support those soft branches.

**After Phase 4** (which removes the gateway-side derivation): every saga-creation path is required to supply TOBIK, so soft-fall-back paths become dead code. Phase 4 deletes:

- All `OptionalFromInput` callsites (verify each before deletion — some may be reading from non-gateway-originated saga inputs).
- All `compensation_status: skipped_missing_*` branches.
- The WARN-on-missing branches in accmgr REST → upgrade to `400 Bad Request`.

The `OptionalFromInput` function itself stays in the package (cheap, future-proof) unless every callsite is gone — in which case delete it.

### D9 — `intent_id` continuity (intentsvc and EXIDS coexistence)

Per `project_intentsvc_design_locked.md`: intentsvc derives TOBIK as `treas:<intent_id>`. That path is orthogonal to gRPC: an intent submitted via intentsvc carries its own intent_id; an order placed via gRPC carries the EXIDS seed; both end up in the same `treasury_ops_base_idempotency_key` saga input slot.

This TODO does NOT touch intentsvc. The implementer should:

- Verify in Phase 1 that no intentsvc-driven path also receives the EXIDS seed.
- Verify in Phase 8 that an e2e test crossing intentsvc + gRPC for the same logical fund operation produces a *different* TOBIK (different namespacing) and is correctly distinguished by the gateway / dedup layer (see Phase 3, O3).

### D10 — `csdmsggw.SdOpsBaseIdempotencyKey` and other "*OpsBaseIdempotencyKey" fields

`pkg/daemons/csdmsggw/api/v1/batch_issue_security_units_handler.go:620` writes `req.SdOpsBaseIdempotencyKey` into the saga input slot `treasury_ops_base_idempotency_key`. So csdmsggw already has a "client-supplied base idempotency key" field, just under a different (sd-prefixed) name. That gateway is **out of scope for this TODO** but in scope for Phase 9 — track in `TODO_EXIDS_EXPANSION_TO_ADMIN_APIS.md`. When that TODO lands, decide whether to rename `SdOpsBaseIdempotencyKey` → `ExecutionIdempotencySeed` for naming uniformity.

### D11 — Per-saga-step namespacing via `idempkey.StepBuilder` (resolves O4)

**Problem to prevent**: today, two different sagas could both reference `idempkey.LockValue`. Given the same TOBIK they would mint identical per-step keys, and the on-chain `Erc20VaultIdempFacet` (which sees only `bytes32(keccak256(key))`) would no-op the second call when it shouldn't.

**Solution**: introduce a `StepBuilder` type in the `idempkey` package that wraps `Builder` and stamps a saga-step-template ID into the per-step key. Each saga step constructs a `StepBuilder` from its OWN template ID and uses *that* — never `Builder.For` directly.

**API sketch** (final shape decided in Phase 1):

```go
// pkg/treasury/idempkey/builder.go (additions; existing Builder + OpSuffix unchanged)

// StepTemplateID identifies a unique saga step in the system. Used to
// namespace per-step idempotency keys so that two sagas reusing the same
// OpSuffix produce distinct on-chain keys.
type StepTemplateID string

const (
    // create_investor_order saga steps
    StepCioLockOrderVolume   StepTemplateID = "cio_lock_order_volume"
    StepCioTransferFee       StepTemplateID = "cio_transfer_fee"
    // unlock_order_stash saga steps
    StepUosTransferStash     StepTemplateID = "uos_transfer_stash"
    // fund_account_with_cash_tokens saga steps
    StepFacwctTransferToDest StepTemplateID = "facwct_transfer_to_destination"
    StepFacwctMintIfNeeded   StepTemplateID = "facwct_mint_tokens_if_needed"
    // withdraw_cash_tokens_from_account saga steps
    StepWcfaTransferToClearing StepTemplateID = "wcfa_transfer_to_clearing"
    StepWcfaWithdrawAndBurn  StepTemplateID = "wcfa_withdraw_and_burn"
    // ... one constant per row in Phase 1 deliverable table
)

// StepBuilder mints per-step idempotency keys scoped to a single saga step.
// Constructed via Builder.ForStep(stepID).
type StepBuilder struct {
    base   string
    stepID StepTemplateID
}

// ForStep returns a StepBuilder scoped to the given step template ID.
// Per-step keys minted from this StepBuilder include the stepID, so two
// sagas using the same OpSuffix produce distinct keys.
func (b Builder) ForStep(stepID StepTemplateID) StepBuilder {
    return StepBuilder{base: b.base, stepID: stepID}
}

// For returns the per-step idempotency key:
//   <base>-<step_template_id>-<op_suffix>
//
// e.g. base="cio:v1:7f3a..." + stepID="cio_lock_order_volume" + LockValue
//   →  "cio:v1:7f3a...-cio_lock_order_volume-lock-value"
//
// Cross-saga collisions become structurally impossible: even if two sagas
// both use the LockValue suffix, the step_template_id portion differs.
func (sb StepBuilder) For(s OpSuffix) string {
    return sb.base + "-" + string(sb.stepID) + "-" + string(s)
}
```

**Migration path** (Phase 4 work, separate from Phase 1 audit):

- Each existing executor that today calls `idempkey.New(base).For(LockValue)` becomes `idempkey.New(base).ForStep(idempkey.StepCioLockOrderVolume).For(LockValue)`.
- The string used at the `RequireFromInput(input, "<step>")` callsite — currently a free-form string like `"cio_lock_order_volume"` — becomes the constant `string(idempkey.StepCioLockOrderVolume)`. One fact, one location.
- Postgres rows in `lcmgr.trz_erc20_idempotency_keys` written under the OLD scheme (no step namespace) coexist with NEW rows. Pre-production, no migration needed: every existing row is operationally a no-op (test data) and will be wiped or naturally aged out. Confirm with `kam` before assuming this.
- The 19 OpSuffix constants stay exactly as they are. Only the per-step *use* changes.

**What does NOT change in D11**:

- The client still sends only `execution_idempotency_seed` (the seed). It does NOT see step template IDs — those are server-side enumeration. The "single most important contract" callout at the top stays true.
- `Builder.For` (without a step) remains in the API for non-saga callers (if any exist after Phase 1 audit). If no non-saga callers exist, deprecate `Builder.For` and force everyone through `StepBuilder.For`. Decision deferred to Phase 1.

### D12 — `originIdempotencyKey` derivation: prefix + seed (resolves O6 with option C)

Today `pkg/daemons/prtagent/impl/v1/grpc/trading.go:609` does:

```go
originIdempotencyKey := fmt.Sprintf("cio_%s_%s", participantIid, req.InvestorOrderId)
```

After EXIDS, every gateway handler that calls `traxSubmitter.SubmitSaga` switches to:

```go
originIdempotencyKey := "<saga_template_id>_" + req.GetExecutionIdempotencySeed()
// e.g. "create_investor_order_cio:v1:7f3a..."
//      "fund_account_with_cash_tokens_dep:v1:9b2e..."
```

**Why option C (prefix + seed) and not bare seed**:

- The saga-template prefix keeps TRAX's audit logs greppable by saga type, exactly as today. `grep '^create_investor_order_'` still works.
- TRAX's existing dedup (which keys on `originIdempotencyKey`) becomes the EXIDS dedup mechanism for free. No new gateway-side registry needed for the *same-seed-same-payload* case (Phase 3 still needs work for the *same-seed-different-payload* case).
- One mechanism per layer. The seed drives BOTH on-chain idempotency (via TOBIK + StepBuilder) AND TRAX submission idempotency. Consistent end-to-end.

**Implementation note**: every `SubmitSaga` callsite changes. Phase 2.5 + Phase 5.5 must catalogue every callsite and flip it. Search: `grep -rn "originIdempotencyKey" pkg/daemons/`.

**Open follow-up (Phase 3)**: the same-seed-*different*-payload case still needs the per-RPC payload-hash registry from O3 — TRAX's dedup alone won't catch a malicious or buggy client that reuses a seed with a different payload (TRAX would correctly say "I already have a saga for that origin" and return the prior saga, but the *new* payload would be silently dropped). Phase 3 adds payload-hash comparison on top of the TRAX-layer dedup.

### D13 — `broker_input` rename to `treasury_stash_derivation_seed` (CORRECTED — resolves O5)

> **Earlier drafts of this section conflated `broker_input` with `execution_idempotency_seed`. That was wrong.** The two are orthogonal; there are now TWO distinct mandatory seed fields on Lock/Unlock/Withdraw cash. This section covers the stash-derivation seed only; D14 documents the LIQUID reserved value and the per-RPC default/reject rules.

The brktrdapi `broker_input` field is **renamed to `treasury_stash_derivation_seed`** (NOT to `execution_idempotency_seed`). It stays as its own field and keeps its functional role: deterministically picking which numbered stash inside a vault the operation targets.

| RPC | Today | After EXIDS |
|---|---|---|
| `LockCashRequest` (brktrdapi) | `string broker_input = 5; // REQUIRED` (line 263) | `string treasury_stash_derivation_seed = 5; // REQUIRED. May NOT be the literal "LIQUID".` |
| `UnlockCashRequest` (brktrdapi) | `string broker_input = 5; // REQUIRED` (line 271) | `string treasury_stash_derivation_seed = 5; // REQUIRED. May NOT be the literal "LIQUID".` |
| `WithdrawCashRequest` (brktrdapi) | `string broker_input = 5; // OPTIONAL` (line 254) | `string treasury_stash_derivation_seed = 5; // REQUIRED. App sends "LIQUID" when the user doesn't override.` |
| `WithdrawCashRequest` (prtagent) | (no equivalent field today) | `string treasury_stash_derivation_seed = 5; // REQUIRED. App sends "LIQUID" when the user doesn't override.` *(added per O9 — aligned to brktrdapi's field 5)* |

**Field numbers**:
- brktrdapi keeps the existing `5` slot (renamed from `broker_input`).
- prtagent's `treasury_stash_derivation_seed` lives at field `5` on all three RPCs (Lock/Unlock/Withdraw) so the wire layout matches brktrdapi across the suite. Earlier draft used `201`; aligned to `5` 2026-05-16.
- `execution_idempotency_seed` continues to live at field 200 across every in-scope RPC per D1/O7. **Two distinct fields, two distinct purposes.**

**Two-field surface, two distinct purposes:**

| | `execution_idempotency_seed` (200) | `treasury_stash_derivation_seed` (5 across brktrdapi + prtagent) |
|---|---|---|
| **Purpose** | Logical operation identity → drives TOBIK → drives on-chain idemp facet keys | Functional input → picks which numbered stash inside a vault the op targets |
| **Determinism** | Required per D4 (no time, no rand) | Required (same value → same stash) |
| **Mandatory** | Yes, everywhere | Yes on Lock/Unlock/Withdraw cash |
| **Reserved values** | None | `"LIQUID"` → stash index 0 (the liquid spendable stash) |
| **Per-RPC reject rules** | None beyond D1 charset | Lock/Unlock REJECT `"LIQUID"`; Withdraw accepts it |
| **Default fill by app** | Auto-recipe (D4) | Withdraw modal: defaults to `"LIQUID"`. Lock/Unlock modals: no default — user must enter |
| **History persisted in app** | Yes, per `(rpc, investor)` (D6) | Yes, per `(rpc, investor)`, separate store key |
| **Same widget shape** | `ExecutionIdempotencySeedField` (D5) | Same widget *type*, different label / validator (D5.2) |

**How they interact**:
- Two `LockCash` calls with the same `execution_idempotency_seed` but different `treasury_stash_derivation_seed` → Phase 3's payload-hash registry (O3 option c) catches this as "same seed, different payload" and rejects the second.
- Two `LockCash` calls with the same `execution_idempotency_seed` and same `treasury_stash_derivation_seed` (full payload identical) → Phase 3 registry says "same logical op", returns the original saga, idempotent end-to-end.
- The auto-recipe for `execution_idempotency_seed` on Lock/Unlock/Withdraw cash MUST include `treasury_stash_derivation_seed` in its hashed inputs — otherwise two locks targeting different stashes would auto-derive the same idempotency seed, causing one to be silently treated as a retry of the other. **This is the recipe rule; see updated D4 table.**

**Schema/wire impact**:
- brktrdapi proto: rename field 5 from `broker_input` to `treasury_stash_derivation_seed` on `LockCashRequest`, `UnlockCashRequest`, `WithdrawCashRequest`. Per `feedback_pre_production_no_backcompat.md`: atomic rename, no aliasing.
- prtagent proto: add `string treasury_stash_derivation_seed = 5;` to `WithdrawCashRequest` (new feature — landed per O9; field number aligned to brktrdapi 2026-05-16).
- Update `pkg/daemons/brktrdsvc/impl/v1/grpc/cash.go`: every `req.BrokerInput` → `req.TreasuryStashDerivationSeed`. Validator (per D14) runs at the top of each handler.
- Update `pkg/daemons/prtagent/impl/v1/grpc/investor.go` `WithdrawCash`: read the new field, plumb through to `withdrawCashTokensFromAccount`.

### D14 — `treasury_stash_derivation_seed` semantics

This field is a SECOND mandatory seed on Lock/Unlock/Withdraw cash. It is fully orthogonal to `execution_idempotency_seed`.

#### D14.1 — Reserved value `"LIQUID"` → stash index 0

The literal ASCII string `"LIQUID"` (uppercase, exactly 6 bytes, no surrounding whitespace) is RESERVED. It deterministically maps to stash index `0` — the liquid, spendable stash present in every vault at the treasury layer. The reservation is part of the wire contract:

- `treasury_stash_derivation_seed = "LIQUID"` ⇒ on-chain operations target stash `0`.
- `treasury_stash_derivation_seed = "<anything else satisfying D14.2>"` ⇒ on-chain operations target a non-zero stash whose index is deterministically derived from the seed by the existing stash-derivation logic in cash.go (today's `broker_input` → stash math; verify exact algorithm in Phase 5).

`"LIQUID"` is case-sensitive. `"liquid"`, `"Liquid"`, `"LIQUID "` (trailing space) are all rejected — they fall through to the regular charset validator (D14.2) and either pass as opaque seeds (mapping to non-zero stashes) or fail validation. We treat `"LIQUID"` as a single magic constant, not a fuzzy alias.

`"LIQUID"` is the only reserved value. No future expansion to other reserved strings without explicit `kam` sign-off (track in this section if added).

#### D14.2 — Per-RPC accept rules

The validator on `treasury_stash_derivation_seed` accepts EITHER:

- The exact literal `"LIQUID"`, OR
- A value matching the same regex as `execution_idempotency_seed`: `^[A-Za-z0-9:_.-]{8,256}$` (D1).

That is: `"LIQUID"` is the one short value; everything else must satisfy the standard 8–256-byte charset rule.

| RPC | `"LIQUID"` accepted? | Empty / missing accepted? |
|---|---|---|
| `LockCashRequest` (brktrdapi) | **REJECTED** with reason `STASH_LIQUID_NOT_ALLOWED` | REJECTED with reason `STASH_MISSING` |
| `UnlockCashRequest` (brktrdapi) | **REJECTED** with reason `STASH_LIQUID_NOT_ALLOWED` | REJECTED with reason `STASH_MISSING` |
| `WithdrawCashRequest` (brktrdapi) | Accepted (resolves to stash 0) | REJECTED with reason `STASH_MISSING` (app fills `"LIQUID"` by default — see D14.3) |
| `WithdrawCashRequest` (prtagent) | Accepted (resolves to stash 0) | REJECTED with reason `STASH_MISSING` (app fills `"LIQUID"` by default) |

Rationale for the Lock/Unlock reject:
- "Locking" is the act of moving liquid balance INTO a non-liquid stash. Locking into stash 0 is a no-op (the source stash IS stash 0).
- "Unlocking" is the act of releasing balance FROM a non-liquid stash BACK to liquid. Unlocking stash 0 is meaningless.

The reject is enforced at the gateway boundary (before saga submission) so the user gets immediate feedback in the UI.

#### D14.3 — App-side defaulting for Withdraw

The withdraw flow MUST present a stash-selection field in the modal. The default state shows `"LIQUID"` already filled. The user can override by typing or selecting from the locally-persisted history (same UX pattern as `execution_idempotency_seed`, see D5.2).

If the user clears the field entirely, the app re-fills `"LIQUID"` on submit-attempt. The user CANNOT submit a withdraw with an empty `treasury_stash_derivation_seed` — the gateway would reject it (`STASH_MISSING`) and the modal must catch that locally first to avoid a round trip.

#### D14.4 — App-side defaulting for Lock and Unlock

Lock and Unlock modals do NOT pre-fill anything. The user must enter or select a stash-derivation seed. The modal's submit button is disabled until the field is non-empty AND not equal to `"LIQUID"`.

#### D14.5 — Validator error-code table (gateway → client)

Mirrors D1.1 in shape. The gateway returns `codes.InvalidArgument` with reason code in `error_details`:

| Reason code | Trigger | Example client message |
|---|---|---|
| `STASH_MISSING` | field absent / zero-length | `treasury_stash_derivation_seed: required field is empty` |
| `STASH_LIQUID_NOT_ALLOWED` | value == `"LIQUID"` AND RPC ∈ {Lock, Unlock} | `treasury_stash_derivation_seed: "LIQUID" is not a valid target for LockCash; lock requires a non-liquid stash` |
| `STASH_TOO_SHORT` | non-LIQUID value with `len < 8` | `treasury_stash_derivation_seed: must be "LIQUID" or at least 8 bytes (got 3)` |
| `STASH_TOO_LONG` | `len > 256` | `treasury_stash_derivation_seed: must be at most 256 bytes (got 412)` |
| `STASH_LEADING_WHITESPACE` | starts with whitespace | `treasury_stash_derivation_seed: must not start with whitespace` |
| `STASH_TRAILING_WHITESPACE` | ends with whitespace | as above |
| `STASH_INNER_WHITESPACE` | contains any whitespace | as above |
| `STASH_CONTROL_CHAR` | `0x00-0x1F` or `0x7F` byte | as above (with offset) |
| `STASH_NON_ASCII` | byte > `0x7F` | as above (with offset) |
| `STASH_DISALLOWED_CHAR` | ASCII char outside `[A-Za-z0-9:_.-]` | as above (with offset) |

(Note: `"LIQUID"` is exempt from the 8-byte minimum but NOT from the charset rule — `"LIQUID"` is itself within `[A-Za-z]+` so it satisfies the charset.)

#### D14.6 — Server-side mapping `"LIQUID"` → stash 0

The gateway, after validation, transforms the value before submitting the saga:

```go
sagaInput["stash_derivation_seed"] = req.GetTreasuryStashDerivationSeed()
// no transformation here — the saga / executor downstream interprets "LIQUID"

// inside the executor (or cash.go's stash-derivation helper):
func deriveStashIndex(stashDerivationSeed string) int64 {
    if stashDerivationSeed == "LIQUID" {
        return 0
    }
    // existing broker_input → stash math (Phase 5 audit confirms the algorithm)
    return derive(stashDerivationSeed)
}
```

The seed flows verbatim into the saga input slot (suggest naming: `stash_derivation_seed` to match `treasury_ops_base_idempotency_key`'s pattern). Downstream executors call `deriveStashIndex` to resolve to the actual numeric stash. Phase 5 confirms whether to put `deriveStashIndex` in a new helper package (e.g. `pkg/treasury/stash/derive.go`) or inline at each callsite.

#### D14.6.1 — Symmetric derivation across RPCs (canonical workflow)

`deriveStashIndex` is a pure deterministic function. Given the same `treasury_stash_derivation_seed`, it returns the same stash index regardless of which RPC called it. This is the load-bearing property that makes the broker-investor workflow work.

**Canonical example:**

```
1. Broker submits LockCash:
     external_investor_id          = "kam-060"
     currency_code                 = "EUR"
     amount                        = "200"
     treasury_stash_derivation_seed = "transfer-156"
     execution_idempotency_seed    = "lck:v1:<sha256(...)>"

   → deriveStashIndex("transfer-156") = e.g. 47
   → 200 EUR moves from stash 0 (liquid) into stash 47 of investor's vault.

2. Later, the same broker submits WithdrawCash for the locked balance:
     external_investor_id          = "kam-060"
     currency_code                 = "EUR"
     amount                        = "200"
     treasury_stash_derivation_seed = "transfer-156"   ← SAME seed
     execution_idempotency_seed    = "wdr:v1:<sha256(...)>"   ← DIFFERENT (it's a different op)

   → deriveStashIndex("transfer-156") = 47 (same function, same input → same output)
   → Withdraw is sourced from stash 47 directly, not from liquid.
```

The broker never has to remember the numeric stash index. They only remember `"transfer-156"`. The system finds the stash by re-deriving.

**Implication for app history**: a single `treasury_stash_derivation_seed` value typically gets used multiple times across the lifecycle of a logical "deal" (lock, possibly partial-unlock, withdraw, etc.). The `(rpc, investor)` history scoping in D6 is therefore the WRONG scoping for the stash-seed history — it should be just `investor` so the same seed shows up in the dropdown for Lock and for Withdraw both. **Update**: stash-seed history key is `exids.stash_history.<external_investor_id>` (no rpc namespace). The exec-idempotency-seed history keeps the per-rpc scoping (since each RPC has its own auto-recipe and re-using a CreateOrder seed in DepositCash is meaningless).

**Implication for `UnlockCash`**: same seed → same stash → unlocks the right stash. UnlockCash with a seed that has never been Locked → the on-chain stash is empty / non-existent → the saga rejects with "nothing to unlock". This is the natural error semantics; no special handling needed.

#### D14.7 — UI/UX shared pattern with `ExecutionIdempotencySeedField`

The widget `TreasuryStashDerivationSeedField` reuses the EXACT same pattern as `ExecutionIdempotencySeedField` (D5):

- Auto-generate checkbox (default checked for Withdraw — value `"LIQUID"`; default UNCHECKED for Lock/Unlock — no auto value).
- Editable when unchecked; combo-box history dropdown with locally-persisted entries.
- Copy + expand-to-modal buttons (D5.1).
- Same SharedPreferences scheme, separate key namespace: `exids.stash_history.<rpc_name>.<external_investor_id>` (D6).
- Same validator (D14.5 reason codes) on both client and server.

Implementation: refactor the underlying widget into a shared base `_SeedFieldBase` parameterised by:
- field label (`"Execution idempotency seed"` vs `"Treasury stash"`)
- validator function (D1.1 reason codes vs D14.5 reason codes)
- auto-recipe function (returns the auto-derived value OR a constant like `"LIQUID"` for the Withdraw-stash case)
- history store key namespace
- `allowLiquid` flag (false for Lock/Unlock, true for Withdraw — gates the default-checkbox behaviour and the validator's `STASH_LIQUID_NOT_ALLOWED` rule)

The two public widgets (`ExecutionIdempotencySeedField`, `TreasuryStashDerivationSeedField`) are thin wrappers that pass the right parameters to the shared base. This avoids forking the widget twice and ensures D5.1's copy/modal viewer applies to both seed fields without duplication.

#### D14.8 — Scope split: this TODO adds the WIRE FIELD ONLY; saga implementation is a separate TODO

**In scope for THIS TODO (`TODO_EXECUTION_IDEMPOTENCY_SEED.md`):**

- Add the `treasury_stash_derivation_seed` field to the affected proto Request messages (rename in brktrdapi at field 5; add new in prtagent `WithdrawCashRequest` at field 5 — landed per O9, aligned to brktrdapi).
- Gateway-boundary validator implementing D14.5 reason codes (charset + `LIQUID` accept/reject rules + length).
- Plumb the value into the saga input map (suggested key: `stash_derivation_seed` next to `treasury_ops_base_idempotency_key`).
- Flutter widget `TreasuryStashDerivationSeedField` (D14.7) wired into mini-broker's Lock/Unlock/Withdraw modals (and trade_bench's once those screens land).
- Local SharedPreferences history per D14.6.1 (scoped per investor, NOT per rpc).
- Gateway-level e2e tests for the validator (Phase 8 catalogue extended).

**Out of scope for this TODO — moves to a separate TODO file:**

- The actual `deriveStashIndex(seed string) int64` algorithm. (Today's `broker_input` → stash math lives in `pkg/daemons/brktrdsvc/...`; the helper extraction, the `LIQUID` short-circuit, and any algorithmic change all happen in the new TODO.)
- Full Lock/Unlock/Withdraw saga implementation (today's brktrdsvc handlers at cash.go:269/278 are stubs returning `Unimplemented`).
- The on-chain stash mutation paths and their per-step idempotency (which use the EXIDS seed via the standard TOBIK chain — orthogonal to stash derivation).
- E2E coverage of the lock-then-withdraw symmetry workflow (D14.6.1 example) — belongs with the saga implementation tests.

**Forthcoming TODO file**: `TODO_TREASURY_STASH_OPERATIONS.md` (short ID `STASHOPS` or `LUWS` — pick during creation). Will define:

- Phase 1: stash-derivation algorithm spec + `pkg/treasury/stash/derive.go` package.
- Phase 2: `LockCash` saga in `treassvc` + brktrdsvc handler wiring.
- Phase 3: `UnlockCash` saga + handler wiring.
- Phase 4: `WithdrawCash` extension to read from a non-zero stash when seed != `"LIQUID"`.
- Phase 5: prtagent `WithdrawCash` extension (mirrors brktrdapi; same algorithm helper).
- Phase 6: end-to-end workflow tests (lock → withdraw round-trip per D14.6.1).
- Etc.

The new TODO references THIS one for the wire-field contract; this one references the new one for the algorithm. Two TODOs, two PR streams, one coherent feature. **The new TODO file MUST be created before Phase 5 of this TODO begins**, because Phase 5's gateway plumbing needs to call `deriveStashIndex` (or stub it) and the function has to exist somewhere.

---

---

## Resolved questions log

All eight resolved on 2026-05-10 with `kam`. Summarised here for audit; full resolutions live in the corresponding D-section.

| # | Question (one-line) | Resolution | D-section |
|---|---|---|---|
| O1 | `WithdrawSecurity` in/out of EXIDS scope? | **Removed entirely from prtagent v1** — proto + handler + tests. Mirrors `TODO_BRKTRDAPI_AND_BRKADMAPI.md` D6 ("investors don't move securities, was a design flaw, resolved"). | D3 (prtagent InvestorService row, struck through) + Phase 2.x |
| O2 | `OnboardInvestor` / `RegisterInvestorAtDepositories` (brktrdapi) — in scope? | **Yes — mandatory at gateway, validated, passed into saga input. Downstream consumer is intentionally absent today; reserved for future use.** Proto comment at the field documents this clearly. | D3 (brktrdapi onboarding RPCs section) |
| O3 | Same-seed-different-payload behaviour? | **Option (c): gateway compares payload hash, accepts if equal, rejects if different.** Per-RPC namespace prefix on the recipe makes cross-RPC collision structurally impossible. | D4 callout + Phase 3 |
| O4 | Suffix-collision risk across sagas? | **Solved structurally via `idempkey.StepBuilder`** — wraps `Builder` with a step-template-id namespace so two sagas using the same `OpSuffix` produce distinct on-chain keys. Per-step constants (`StepCioLockOrderVolume`, etc.) live in the same package. | D11 |
| O5 | `LockCash`/`UnlockCash`/`WithdrawCash` `broker_input` field — keep both? | **Rename `broker_input` → `execution_idempotency_seed`.** Single field, double duty: idempotency contract AND stash-derivation entropy. Field 5 deleted; field 200 carries the seed. | D13 |
| O6 | Gateway-side dedup registry — separate, or fold into TRAX `originIdempotencyKey`? | **Option C: `originIdempotencyKey = "<saga_template>_" + seed`.** Saga-template prefix keeps TRAX logs greppable; TRAX's existing dedup absorbs same-seed-same-payload retries for free. Same-seed-different-payload still needs Phase 3 payload-hash registry. | D12 |
| O7 | Field number choice? | **`200` everywhere, no exceptions.** Verified unused across prtagent/brktrdapi/brkadmapi protos as of 2026-05-10. | D1 |
| O8 | Dart test infra — exists? | **No Dart tests exist today; Phase 6 introduces `test` + `flutter_test` in `common_ui`.** Lower priority than e2e laser tests. Phase 8 is expanded to thoroughly cover messy-input cases (tabs, NBSP, control chars, non-ASCII, oversize, etc.). | D1.1 + Phase 6.6 + Phase 8.9 |
| O9 | Add `treasury_stash_derivation_seed` to prtagent `WithdrawCashRequest` too (not just brktrdapi)? | **RESOLVED 2026-05-16** — yes, landed across all four cash-flow RPCs on prtagent (Deposit/Withdraw/Lock/Unlock) with stash on field 5 to match brktrdapi byte-for-byte. mini-broker now drives EXIDS + stash from the UI; gateway validators enforce `allowLiquid=true` (Withdraw) / `false` (Lock/Unlock). | resolved |

---

## Phase 0 — Spec freeze and stakeholder sign-off

Goal: lock D1–D10 with `kam` before any code is touched. Resolve every O-question.

- [ ] 0.1 Resolve open questions O1–O8 with `kam`. Update D-section in this file with the answers; do NOT proceed to Phase 1 with any O-question still open.
- [ ] 0.2 Walk D3's RPC list past `kam`. Confirm each row, edit any addition/removal directly into D3.
- [ ] 0.3 Confirm the recipe-invariants in D4 are sufficient. The implementing agent for the *client* side will derive the actual tuples per RPC; this phase only confirms the rules and the suggested tuples.
- [ ] 0.4 Confirm UI shape in D5 with `kam`. ASCII mock above is fine; if `kam` wants a different layout, note it in D5 directly.
- [ ] 0.5 Confirm local-only persistence model in D6 and the 50-entry cap.
- [ ] 0.6 Confirm "tighten the soft branches" plan (D8) — walk each compensation branch line by line with `kam`.

---

## Phase 1 — Saga-by-saga audit (read-only — produces a table, no code change)

Goal: catalogue every saga / executor that mutates a treasury vault, the OpSuffix it uses, and the path TOBIK takes from boundary to vault. The output is a table inside this TODO under "Phase 1 deliverable" below. NO CODE CHANGE in this phase.

- [ ] 1.1 List every executor file under `pkg/daemons/treassvc/trax/executors/` and `pkg/daemons/accmgr/trax/executors/` that calls `idempkey.RequireFromInput` or `idempkey.OptionalFromInput`. Use `grep -rn "idempkey\.(Require|Optional)FromInput"`.
- [ ] 1.2 For each, record `{file, line, saga_name, step_label, OpSuffix used, mutation type (lock/unlock/transfer/mint/burn/deposit/withdraw), comp_branch (Y/N), comp soft-skip (Y/N)}`.
- [ ] 1.3 Identify the *spawning* path for each saga: which RPC handler (or which actusvc action) submitted the parent saga, and which intermediate sagas chain into it. Trace from `handle_*_fix_exec_report` back through actusvc to the original `CreateOrderAsync`.
- [ ] 1.4 Identify any saga that today receives TOBIK from a *non-gateway* source (e.g. intentsvc, csdmsggw `SdOpsBaseIdempotencyKey`) — flag those in the table; they are not affected by this TODO.
- [ ] 1.5 Check that the OpSuffix space (`builder.go:15-35`) covers every actual mutation step. If a step uses `LockValue` for both lock and a separate transfer, that's a bug — flag and ask `kam`.
- [ ] 1.6 Update `Phase 1 deliverable` below with the table.

### Phase 1 deliverable: TOBIK consumer catalogue

> **Completed 2026-05-10.** Full grep results below. **Cross-saga OpSuffix audit: CLEAN** — every OpSuffix is used by exactly one saga (the rightmost column groups by saga). D11 `StepBuilder` is still the right design (defense-in-depth + future-proofing) but no immediate cross-saga collision exists today.

#### `RequireFromInput` callsites (12 total, 7 sagas, all EXIDS-mandatory after Phase 2/5)

| Saga | Step file:line | OpSuffix used | Comp? | Comp soft-skip line | Spawn chain |
|---|---|---|---|---|---|
| `create_investor_order` | `treassvc/.../lock_order_volume.go:46` (forward) + `:272` (comp) | `LockValue` (line 146), `LockValueComp` (line 314) | Y | `:275` | gRPC `CreateOrderAsync` (prtagent, brktrdapi) |
| `create_investor_order` | `treassvc/.../transfer_fee.go:44` (forward) + `:297` (comp) | `FeeTransfer` (line 137), `FeeTransferComp` (line 309) | Y | `:300` | gRPC `CreateOrderAsync` |
| `unlock_order_stash` | `treassvc/.../transfer_stash.go:63` (forward) + `:233` (comp) | `UnlockStash` (line 145), `UnlockStashComp` (line 249) | Y | `:236` | actusvc on FIX exec report (handle_done_for_day, handle_fill, handle_partial_fill, handle_cancel) → accmgr handle_*_fix_exec_report → unlock_order_stash |
| `fund_account_with_cash_tokens` | `treassvc/.../transfer_from_clearing_to_destination.go:109` | `FundTransfer` (line 115) | N | — | gRPC `DepositCash` (prtagent + brktrdapi) |
| `fund_account_with_cash_tokens` | `treassvc/.../mint_tokens_if_needed.go:124` | `FundMint` (line 136), `FundApprove` (line 163), `FundDeposit` (line 186) | N | — | gRPC `DepositCash` |
| `withdraw_cash_tokens_from_account` | `treassvc/.../transfer_from_account_to_clearing.go:104` | `WithdrawTransfer` (line 110) | N | — | gRPC `WithdrawCash` (prtagent + brktrdapi) |
| `withdraw_cash_tokens_from_account` | `treassvc/.../withdraw_and_burn_tokens.go:103` | `WithdrawFromVault` (line 115), `WithdrawBurn` (line 138) | N | — | gRPC `WithdrawCash` |
| `fund_account_with_authorized_instrument` | `treassvc/.../mint_if_needed.go:118` | `AuthorizedInstrMint` (line 126), `AuthorizedInstrApprove` (line 142), `AuthorizedInstrDeposit` (line 155) | N | — | NOT EXIDS-scope (no gRPC client today — internal saga spawn only) |
| `fund_account_with_authorized_instrument` | `treassvc/.../transfer_to_dest.go:99` | `AuthorizedInstrTransfer` (line 104) | N | — | NOT EXIDS-scope |

#### `OptionalFromInput` callsites (2 total, both NON-EXIDS)

| Saga | Step file:line | OpSuffix | Spawn chain | Phase 4 action |
|---|---|---|---|---|
| `transfer_authorized_instrument` | `laseragent/.../transfer_tokens.go:298` (forward), `:760` (comp) | `Erc20Transfer` (line 299), `Erc20TransferComp` (line 761) | Internal LASER call from sagas spawning transfers; no direct gRPC EXIDS path | LEAVE ALONE per Phase 4.4 — non-EXIDS spawn chain. Document with comment: "// Internal-only — gRPC paths must use RequireFromInput per EXIDS Phase 4". |

#### Cross-saga OpSuffix audit (D11 verification)

| OpSuffix | Used by saga(s) | Cross-saga collision? |
|---|---|---|
| `LockValue` / `LockValueComp` | `create_investor_order` only | ✅ none |
| `FeeTransfer` / `FeeTransferComp` | `create_investor_order` only | ✅ none |
| `UnlockStash` / `UnlockStashComp` | `unlock_order_stash` only | ✅ none |
| `FundMint`, `FundApprove`, `FundDeposit`, `FundTransfer` | `fund_account_with_cash_tokens` only | ✅ none |
| `AuthorizedInstrMint/Approve/Deposit/Transfer` | `fund_account_with_authorized_instrument` only | ✅ none |
| `WithdrawTransfer`, `WithdrawFromVault`, `WithdrawBurn` | `withdraw_cash_tokens_from_account` only | ✅ none |
| `Erc20Transfer` / `Erc20TransferComp` | `transfer_authorized_instrument` (laseragent) only | ✅ none |

**Result**: zero cross-saga OpSuffix collisions today. D11 `StepBuilder` is implemented as defense-in-depth so future saga authors can't introduce a collision by accident. Migration of existing executors to `StepBuilder.For` happens in Phase 4.

#### Step-template constants required by D11 (one per `RequireFromInput` step name)

```go
// add to pkg/treasury/idempkey/builder.go
StepCioLockOrderVolume               StepTemplateID = "cio_lock_order_volume"
StepCioLockOrderVolumeComp           StepTemplateID = "cio_lock_order_volume_compensation"
StepCioTransferFee                   StepTemplateID = "cio_transfer_fee"
StepCioTransferFeeComp               StepTemplateID = "cio_transfer_fee_compensation"
StepUosTransferStash                 StepTemplateID = "uos_transfer_stash"
StepUosTransferStashComp             StepTemplateID = "uos_transfer_stash_compensation"
StepFacwctTransferToDestination      StepTemplateID = "facwct_transfer_to_destination"
StepFacwctMintTokensIfNeeded         StepTemplateID = "facwct_mint_tokens_if_needed"
StepWcfaTransferToClearing           StepTemplateID = "wcfa_transfer_to_clearing"
StepWcfaWithdrawAndBurn              StepTemplateID = "wcfa_withdraw_and_burn"
StepFawaiMintIfNeeded                StepTemplateID = "fawai_mint_if_needed"
StepFawaiTransferToDestination       StepTemplateID = "fawai_transfer_to_destination"
```

---

## Phase 2 — Proto + gateway changes for `prtagent/v1`

Goal: add the mandatory field to every RPC in D3's prtagent slice. Coordinated atomic commit per `feedback_pre_production_no_backcompat.md`.

- [ ] 2.1 Edit `data/api/grpc/prtagent/v1/trading.proto`:
  - Add `string execution_idempotency_seed = 103;` (or O7 number) to `CreateOrderAsyncRequest` (line 136), `ReplaceOrderAsyncRequest` (line 163), `CancelOrderAsyncRequest` (line 179).
  - Add `// REQUIRED: Client-controlled seed used verbatim as treasury_ops_base_idempotency_key. See docs/TODO_EXECUTION_IDEMPOTENCY_SEED.md.` comment.
- [ ] 2.2 Edit `data/api/grpc/prtagent/v1/investor.proto`:
  - Add the field to `DepositCashRequest` (line 206), `WithdrawCashRequest` (line 221), `WithdrawSecurityRequest` (line 236) — last subject to O1.
- [ ] 2.3 Run `make gen-proto`. Verify generated Go matches expectations. Verify no other proto file references the affected messages in a way that breaks.
- [ ] 2.4 In `pkg/daemons/prtagent/impl/v1/grpc/`: add a single shared validator `validateExecutionIdempotencySeed(seed string) error` (returns `codes.InvalidArgument` on empty/oversize/whitespace/non-printable). Pick a home — likely `api.go` next to existing helpers, or a new `validators.go`. Call it at the **top** of every affected handler, before any other check.
- [ ] 2.5 In `trading.go` `CreateOrderAsync`:
  - **DELETE** line 584: `"treasury_ops_base_idempotency_key": fmt.Sprintf("cio:%s:%s:%s:%s", participantIid, req.InvestorOrderId, req.SecurityListingIid, req.Quantity),`
  - **REPLACE WITH**: `"treasury_ops_base_idempotency_key": req.GetExecutionIdempotencySeed(),`
  - Verify `req.GetExecutionIdempotencySeed()` is referenced after Phase 2.4's validator has run (so guaranteed non-empty).
  - Consider whether `originIdempotencyKey` (line 609) should also switch — it is TRAX's own dedup mechanism, not TOBIK. Likely keep separate; ask `kam` per O6.
- [ ] 2.6 In `trading.go` `CancelOrderAsync` and `ReplaceOrderAsync`: add validator call. Wire seed into saga input when these handlers are eventually implemented.
- [ ] 2.7 In `investor.go`:
  - In `DepositCash` (line 1004): pipe seed through to `s.fundAccountWithCashTokens(...)` — change the helper signature to accept TOBIK as a parameter instead of deriving it.
  - In `WithdrawCash` (line 1085): same for `s.withdrawCashTokensFromAccount(...)`.
  - In `fundAccountWithCashTokens` (line 318): **DELETE** line 328 `treasuryOpsBaseIdempotencyKey := fmt.Sprintf("facwct:...")` and **REPLACE** the body field at line 333 with the parameter.
  - In `withdrawCashTokensFromAccount` (line 266): **DELETE** line 279 derivation and use the parameter at line 283.
  - In `WithdrawSecurity` (line 1166): when the handler is implemented, follow the same pattern.
- [ ] 2.8 Update prtagent gateway swagger / OpenAPI generation; verify `make docs` succeeds. Inspect `gen-pkg/.../prtagent/v1/*.swagger.json` for the new field.
- [x] 2.9 **Audit every consumer of `prtagentapi.v1`** — completed 2026-05-10. Findings:

  **Real Go consumers (in scope for in-same-commit update):**
  - `tests/e2e/laser/order_test_infra_test.go` — already TOBIK-aware at lines 1701, 1817; needs seed plumbing for the gRPC-routed test variants.
  - `tests/e2e/laser/{create,cancel}_investor_order_test.go`, `investor_event_stream_test.go`, `order_stash_unlock_on_rejection_test.go`.

  **Real Flutter consumers (in scope for Phase 6 in-same-commit update):**
  - `apps/apps/legacy/mini-broker/lib/services/{grpc_helper,real_grpc_client,event_subscription_service}.dart`
  - `apps/apps/legacy/mini-broker/lib/screens/{portfolio_page,trading_page}.dart`

  **Generated bindings to sync (not authored):**
  - `apps/packages/common_data/lib/src/generated/prtagent/v1/{investor,trading}.{pb,pbgrpc,pbjson}.dart` — regenerated by Dart proto build.
  - `apps/packages/common_data/proto/qomet/agora/daemons/api/grpc/prtagent/v1/{investor,trading}.proto` — **separate copy from the canonical `data/api/grpc/prtagent/v1/`** (already drifted: still has `WithdrawSecurity`, missing `fin/account.proto` import). `kam`: confirm whether to sync from canonical or whether common_data is intentionally lagging. Either way, mini-broker's regenerated Dart bindings need to gain `executionIdempotencySeed` field on the affected requests.

  **Out of scope (don't migrate via this TODO):**
  - `apps/apps/security_depository_admin/` — uses sdappgw/v1, not prtagent (Phase 9).
  - `apps/packages/broker_trading_pages/` — uses brktrdapi/v1 (covered by Phase 5/6, not Phase 2).

- [x] 2.10 **Decision**: Phase 2 ships **paired with** Phase 6 (mini-broker integration) and the e2e test updates from Phase 8. Per `feedback_pre_production_no_backcompat.md`, no transition window — atomic flip across:
  - canonical proto files (Phase 2.1-2.2)
  - common_data proto copy + regenerated Dart bindings (Phase 6 prereq)
  - mini-broker form code (Phase 6)
  - e2e fixtures (Phase 8)
- [ ] 2.11 Update `pkg/daemons/prtagent/impl/v1/grpc/trading_test.go` and `investor_test.go`: every test that calls a now-mandatory-seed RPC must construct a seed.
- [ ] 2.12 Add gateway-level tests: `TestCreateOrderAsync_RejectsEmptySeed`, `TestCreateOrderAsync_RejectsOversizeSeed`, `TestCreateOrderAsync_RejectsWhitespaceSeed`, `TestCreateOrderAsync_AcceptsValidSeed_PassesVerbatimToSagaInput`. Mirror for Deposit, Withdraw, Cancel.

---

## Phase 3 — Same-seed dedup at the gateway (resolves O3, O6)

Goal: implement the gateway-level dedup behaviour selected in O3.

**Status (2026-05-10):** Phase 3 is **DONE — Postgres-backed**.

Implementation summary:
- `pkg/grpc/exids/registry.go` defines a `Registry` interface with two implementations: `InMemoryPayloadRegistry` (per-process, useful for tests / single-pod) and `PgsqlPayloadRegistry` (durable, cross-pod, table `shared.exids_payload_registry`).
- Schema lives in `deploy/k8s/init/init_shared_pgsql.sql` (auto-created at deploy time) AND can be ensured at runtime via `PgsqlPayloadRegistry.EnsureSchema(ctx)` (idempotent).
- prtagent daemon (`pkg/daemons/prtagent.go`) now constructs a `PgsqlPayloadRegistry` from `POSTGRESQL_CONN_STRING`, ensures schema, runs a 10-min background eviction goroutine, and passes the registry into `TradingServer` via `NewTradingServerWithRegistry`.
- 9 in-memory unit tests + 5 Postgres integration tests (auto-skip when `PGSQL_HOST` env unset). Compile-time interface assertion ensures both backends stay in sync.

Cross-pod consistency: same-seed retries on different prtagent pods now hit the same `shared.exids_payload_registry` row, so `IdempotentRetry` and `PayloadConflict` are detected uniformly across the fleet. The TRAX `OriginIdempotencyKey` dedup (D12) and on-chain `Erc20VaultIdempFacet` remain as defense in depth.

Remaining Phase 3 work (lower-priority follow-ups):

 Investigated during Phase 2/5 implementation:

- D12 already lands (`originIdempotencyKey = "<saga_template>_" + seed`).
- TRAX's `defaultSagaSubmitter.SubmitSaga` (`pkg/trax/submitter.go:380`) is fire-and-forget MQ publish — it generates a fresh `sagaInstanceId` on every call and just attaches the originIdempotencyKey to the message. It does NOT proactively dedup at submission time; that behaviour lives in the coordinator's downstream message handling (search `pkg/trax/coordinator.go` for `OriginIdempotencyKey` handling — needs investigation).
- The on-chain `Erc20VaultIdempFacet` is the ultimate safeguard: even if two TRAX sagas with the same TOBIK both run to the per-step on-chain mutation, the second's bytes32 key collides with the first's row in `lcmgr.trz_erc20_idempotency_keys` and the second on-chain call is a no-op. So **worst case today is option (b) of O3** — two server-side records but one on-chain effect — which is acceptable as a fallback even though (c) is the goal.

The remaining Phase 3 work is to **add a gateway-side payload-hash registry** so the gateway can REJECT (not just silently dedup) the same-seed-different-payload case before submitting. This needs a kam decision on storage:

- [ ] 3.1 Resolve with `kam`: storage backend for the registry — Postgres (per-namespace, durable, cross-pod), Redis (fast, cross-pod, eviction-aware), or in-memory (per-pod only, simpler to ship). Mini-broker / single-pod test environments only need in-memory.
- [ ] 3.2 Investigate TRAX coordinator's actual `OriginIdempotencyKey` semantics — does the coordinator already reject duplicate origin keys, or does it accept them silently? `grep OriginIdempotencyKey pkg/trax/coordinator.go` is the entry point; lines 1160 / 1322 / 1364 / 2246 / 2858 need a walk-through.
- [ ] 3.3 Implement the chosen registry per 3.1. Mirror the existing in-flight saga registry storage layer if present.
- [ ] 3.4 Property tests asserting:
  - Same seed + same payload → same saga returned, response idempotent (no second saga submission).
  - Same seed + different payload → `FailedPrecondition` per O3 option (c).
  - Different seed + same payload → two separate sagas.
- [ ] 3.5 Add Prometheus metrics:
  - `exids_seed_collision_total{outcome="same_payload_idempotent"}` — counter for retry caught successfully.
  - `exids_seed_collision_total{outcome="different_payload_rejected"}` — counter for client bug or replay.
  - `exids_seed_validation_failed_total{reason="empty|oversize|whitespace|non_printable"}` — visibility into client misuse. (The `pkg/grpc/exids` validator emits typed `ReasonCode` already; metric just needs to count by code.) `prometheus/client_golang` is in `go.sum` but the codebase has no `promauto` callsites yet — first use also needs a /metrics endpoint decision per daemon.
- [ ] 3.6 Document the metric names in the daemon's README.

---

## Phase 4 — Tighten the soft fallbacks (D8)

Goal: every saga executor and REST handler that currently softens TOBIK absence becomes fail-loud.

- [ ] 4.1 In `pkg/daemons/treassvc/trax/executors/create_investor_order/lock_order_volume.go`:
  - Line 272-280 already uses `RequireFromInput` and falls into a soft branch — confirm the `compensationResults[sagaIdempotencyKey] = result` short-circuit at line 278 is still needed for the (now impossible) "missing TOBIK" case. If not, delete the branch entirely.
  - Same for `transfer_fee.go:297-300` and `unlock_order_stash/transfer_stash.go:233-236`.
- [ ] 4.2 In `pkg/daemons/accmgr/api/v1/accounts_post_handle_fix_exec_report.go:149-150`: upgrade WARN to `400 Bad Request`. Same for any `accounts_post_*.go` that accepts an optional `TreasuryOpsBaseIdempotencyKey` JSON field — flip to required.
- [ ] 4.3 In `pkg/daemons/accmgr/api/v1/accounts_post_fund_batch.go:177-179`: the inline comment references "Critical: temporary TOBIK datetime suffix" tracked in `docs/TODO.md`. Verify this still applies; if EXIDS supersedes it, update the comment to reference this TODO and either delete the temporary suffix or schedule its removal in this phase.
- [ ] 4.4 Search the repo for `OptionalFromInput` callsites: `grep -rn "idempkey.OptionalFromInput"`. For each, decide:
  - If the caller is downstream of an EXIDS-now-mandatory RPC: convert to `RequireFromInput`.
  - If the caller is downstream of a non-EXIDS path (intentsvc, internal saga spawn): leave alone.
- [ ] 4.5 If every `OptionalFromInput` callsite is converted, delete `OptionalFromInput` from `pkg/treasury/idempkey/builder.go:73-84`. Otherwise leave it but mark it `// Internal-only — gRPC paths must use RequireFromInput`.
- [ ] 4.6 Re-run e2e categories listed in Phase 8 to confirm no caller path slipped through.

---

## Phase 5 — `brktrdapi/v1` proto + gateway changes

Goal: same as Phase 2 but for brktrdapi. Plus the brkadmapi guard comment.

- [ ] 5.0 **Prerequisite**: create `TODO_TREASURY_STASH_OPERATIONS.md` (per D14.8) and lock its Phase 1 (algorithm spec + `pkg/treasury/stash/derive.go` package + `LIQUID` short-circuit) before any code in this Phase 5 starts. The gateway code below references `deriveStashIndex` which has to exist — even if only as a stub returning `0` for `LIQUID` and erroring otherwise during this TODO's window.
- [ ] 5.1 Edit `data/api/grpc/brktrdapi/v1/service.proto`. Two atomic changes in this single edit:
  - **(a) `execution_idempotency_seed` additions (per D1/O7 — field 200):** add `string execution_idempotency_seed = 200;` to:
    - `CreateOrderRequest` (line 279)
    - `ReplaceOrderRequest` (line 297)
    - `CancelOrderRequest` (line 307)
    - `DepositCashRequest` (line 241)
    - `WithdrawCashRequest` (line 249)
    - `LockCashRequest` (line 258)
    - `UnlockCashRequest` (line 267)
    - `OnboardInvestorRequest` (line 221) — pending O2
    - `RegisterInvestorAtDepositoriesRequest` (line 230) — pending O2
  - **(b) `broker_input` rename (per D13/O5 — keep field 5):** on `LockCashRequest`, `UnlockCashRequest`, `WithdrawCashRequest`, rename field 5 from `broker_input` to `treasury_stash_derivation_seed`. Update inline comments to reference D14's `LIQUID` reservation and the per-RPC accept rules. Per `feedback_pre_production_no_backcompat.md`: atomic rename, no aliasing.
- [ ] 5.1.1 Edit `data/api/grpc/prtagent/v1/investor.proto` (per O9 — pending kam confirmation): add `string treasury_stash_derivation_seed = 201;` to `WithdrawCashRequest`. Verify `201` unused before applying. If O9 resolves "no", skip this step and the corresponding handler change in 5.6.1.
- [ ] 5.2 Edit `data/api/grpc/brkadmapi/v1/service.proto`: add the EXIDS guard comment block (D3 quoted block) just above `service BrokerAdminApiService {`. NO field additions.
- [ ] 5.3 Run `make gen-proto`. Verify generated Go (Request structs gain `ExecutionIdempotencySeed` and `TreasuryStashDerivationSeed` fields; `BrokerInput` field is gone).
- [ ] 5.4 Update brktrdsvc handler validators (mirror Phase 2.4) — share validators across daemons via `pkg/grpc/exids/validator.go` and `pkg/grpc/exids/stash_validator.go`. Stash validator implements D14.5 (charset + LIQUID rules + per-RPC `allowLiquid` flag).
- [ ] 5.5 In `pkg/daemons/brktrdsvc/impl/v1/grpc/trading.go`:
  - **DELETE** line 195 `"treasury_ops_base_idempotency_key": fmt.Sprintf("cio:%s:%s:%s:%s", ...)` and replace with `req.GetExecutionIdempotencySeed()`.
  - Add EXIDS validator call at top of `CreateOrder` (line 44).
  - Wire seed into the cancel saga submission in `CancelOrder` (line 285) — per CLAUDE.md, brktrdsvc' `CancelOrder` mirrors prtagent's `CancelOrderAsync` end-to-end (submits `cancel_investor_order` saga + fires `cancel_submitted` MQ event). The seed must flow into the saga input the same way.
  - Stub handlers (`ReplaceOrder` line 265): add validator now so future implementation inherits it.
- [ ] 5.6 In `pkg/daemons/brktrdsvc/impl/v1/grpc/cash.go`:
  - **DELETE** line 210's TOBIK derivation; replace with `req.GetExecutionIdempotencySeed()`.
  - Add EXIDS validator at top of `DepositCash` (line 40), `WithdrawCash` (line 113), `LockCash` (line 269), `UnlockCash` (line 278).
  - **For Lock/Unlock/Withdraw cash**: also add the stash-seed validator. Lock/Unlock pass `allowLiquid=false`, Withdraw passes `allowLiquid=true`. Every `req.BrokerInput` reference becomes `req.TreasuryStashDerivationSeed`.
  - Plumb `req.TreasuryStashDerivationSeed` into the saga input map under key `stash_derivation_seed`. Downstream `deriveStashIndex` (per D14.6) maps it to a numeric stash. (Implementation of `deriveStashIndex` lives in the new `TODO_TREASURY_STASH_OPERATIONS.md` per D14.8 — a stub that returns `0` for `LIQUID` is sufficient during this TODO's window.)
- [ ] 5.6.1 In `pkg/daemons/prtagent/impl/v1/grpc/investor.go` `WithdrawCash` (line 1085) — per O9: add the stash-seed validator (`allowLiquid=true`); plumb `req.TreasuryStashDerivationSeed` into the saga input map under key `stash_derivation_seed`. Existing call to `withdrawCashTokensFromAccount` (line 1154) must accept the stash seed as a parameter and forward it.
- [ ] 5.7 Update `BrokerTradingApiService` swagger; rebuild docs. Verify both new fields appear with correct annotations.
- [ ] 5.8 Audit consumers of brktrdapi: today the only known consumer is the planned `broker_admin` Flutter suite app + the workspace package `apps/packages/broker_trading_pages/`. Walk each and gate on Phase 6/7 sign-off (broker_trading_pages is shared and may already be wired into `broker_admin` — confirm). For consumers that submit Lock/Unlock/Withdraw: they MUST also be updated to send `treasury_stash_derivation_seed` in the same commit.
- [ ] 5.9 Add gateway-level tests mirroring Phase 2.12 for brktrdsvc — split into two test files: `cash_exids_test.go` (EXIDS validation per D1.1) and `cash_stash_test.go` (stash-seed validation per D14.5, including `LIQUID` accept-or-reject per RPC).

---

## Phase 6 — `mini-broker` UI integration (legacy app)

Location: `apps/apps/legacy/mini-broker/`.

- [x] 6.0 **Mini-broker rich-widget verdict (2026-05-10): DEFERRED-WONTFIX.** Mini-broker is the "legacy" app (per `apps/apps/legacy/` location). It does NOT depend on `common_ui` / `common_theme` / `common_core`, uses `provider` (not `flutter_riverpod`), and has no `AppSettings` infrastructure. Wiring the rich widget would mean: pull in 3 new packages, wrap MaterialApp with `buildAppTheme()` for `AppTokens`, add a riverpod ProviderScope, supply an `AppSettings` instance for `SeedHistoryStore`. That's a multi-day refactor of a deprecated app that already works against the EXIDS gateway via inline `_exidsSeed()` in `lib/services/grpc_helper.dart`. The rich widget's natural home is `apps/packages/broker_trading_pages/` (which IS riverpod-based, already imports `common_ui`, and is the "real" investor-side UI per CLAUDE.md). When broker_trading_pages wires the widget, mini-broker stays on inline derivation until it's retired.
- [x] 6.1 **Widget home decided**: `apps/packages/common_ui/lib/src/widgets/exids/`. Built and exported.
- [ ] 6.2 Create `apps/packages/common_ui/lib/widgets/execution_idempotency_seed_field.dart`. API:

```dart
class ExecutionIdempotencySeedField extends StatefulWidget {
  /// Stream of the form's currently-bound input map (or anything the
  /// recipe needs to compute a deterministic seed). Re-derive on every
  /// emission while checkbox is checked.
  final Stream<Map<String, dynamic>> inputStream;

  /// Pure function — given the latest input map, return the canonical
  /// seed string. MUST satisfy D4 invariants (no time, no rand).
  final String Function(Map<String, dynamic>) recipe;

  /// Identifies the (rpc, investor) pair for history scoping.
  /// Format: '<rpc_name>:<external_investor_id>'.
  final String historyKey;

  /// Human-readable annotation derived from the same input map.
  /// Stored alongside the seed in history (D6). MUST NOT contain PII.
  final String Function(Map<String, dynamic>) annotation;

  /// Called when the seed value changes. Form should bind this to its
  /// submit-payload builder.
  final ValueChanged<String> onSeedChanged;

  /// Optional: pre-filled value when the form is opened in "edit existing
  /// draft" mode. When non-null, checkbox starts UNCHECKED.
  final String? initialSeed;

  // ... constructor
}
```

- [ ] 6.2.1 Create `apps/packages/common_ui/lib/widgets/execution_idempotency_seed_viewer_dialog.dart` (per D5.1). Full-screen modal that:
  - Displays the seed in a wrapped monospace text area.
  - Shows live byte length and char-class breakdown.
  - Has a copy button (top-right) that calls `Clipboard.setData` and shows a snackbar with the byte count.
  - Has read-only and editable modes; editable validates with the same byte-offset error reporting as the gateway (D1.1).
  - Has Esc / Close to dismiss; Save (editable mode only) to commit.
  - Exported as a reusable widget so Phase 9 admin apps can render long seeds in any context (audit logs, saga inspector, etc.).
- [ ] 6.2.2 In `ExecutionIdempotencySeedField` (6.2): wire the inline copy button (`Clipboard.setData` + snackbar with live byte length) and the expand button (opens the viewer dialog). Plumb the editable/read-only state through so the dialog respects the parent checkbox.
- [ ] 6.2.3 Add a "view all" entry at the bottom of the history dropdown that opens the viewer dialog in list mode — every history row, each with its own copy + use-this buttons.
- [ ] 6.3 Create `apps/packages/common_ui/lib/services/seed_history_store.dart`. Implements D6: SharedPreferences-backed, per-(rpc, investor) ring buffer of 50.

```dart
class SeedHistoryStore {
  static const int maxEntriesPerKey = 50;

  Future<void> add(String historyKey, SeedHistoryEntry entry);
  Future<List<SeedHistoryEntry>> list(String historyKey);
  Future<void> clearForInvestor(String externalInvestorId); // logout hook
}

class SeedHistoryEntry {
  final String seed;
  final DateTime tsUtc; // stored UTC, displayed local-locale (memory: feedback_dates_utc_in_json_local_in_ui.md)
  final String inputSummary;
  final String inputHash; // sha256 of canonical inputs — for "differs from auto" warning
}
```

- [ ] 6.4 Wire the widget into every form that submits an in-scope RPC. Mini-broker calls `prtagent/v1` today (per `TODO_BRKTRDAPI_AND_BRKADMAPI.md` D-section); do NOT migrate it to brktrdapi here. Targets:
  - `lib/screens/trading_page.dart` — order form (Create/Replace/Cancel).
  - `lib/screens/portfolio_page.dart` — deposit / withdraw forms (verify location; may live in a dialog).
  - `lib/screens/broker/orders_page.dart` — broker-side Cancel order modal (if any).
  - Confirm the full list with `kam` after grepping for `CreateOrderAsync`, `DepositCash`, `WithdrawCash`, `CancelOrderAsync` in `lib/services/`.
- [ ] 6.5 Implement per-RPC recipes (D4 invariants). One file per RPC under `lib/services/idemp_seeds/` for findability. E.g. `create_order_async_seed_recipe.dart`. Each file exports:

```dart
String createOrderAsyncSeedRecipe(Map<String, dynamic> input) {
  // canonical normalisation
  final parts = [
    (input['participant_iid'] as String).trim(),
    (input['external_investor_id'] as String).trim(),
    (input['security_listing_iid'] as String).trim(),
    (input['side'] as String).trim().toUpperCase(),
    (input['order_type'] as String).trim().toUpperCase(),
    _normalizeDecimal(input['quantity']),
    _normalizeDecimal(input['price']),
    (input['currency'] as String).trim().toUpperCase(),
    _normalizeDecimal(input['fee_amount']),
    (input['investor_order_id'] as String).trim(),
    (input['fee_payer_account_iid'] as String? ?? '').trim(),
  ];
  final blob = parts.join('|');
  return 'cio:v1:${sha256.convert(utf8.encode(blob)).toString()}';
}
```

- [ ] 6.6 Unit tests for each recipe asserting: (a) determinism — 5000 calls produce identical output; (b) sensitivity — mutating each input field individually changes the seed; (c) insensitivity to whitespace, decimal-format-noise, case (where canonicalised); (d) length ≤ 256 bytes; (e) empty-input vs zero-input distinction (`""` vs `"0"` produce different seeds).
- [ ] 6.7 Wire `SeedHistoryStore.add()` into the post-submit success path: in each form's submit handler, on `PollExecution` returning `OK`, call `await store.add(historyKey, SeedHistoryEntry(...))`.
- [ ] 6.8 Wire `SeedHistoryStore.clearForInvestor()` into the auth logout hook.
- [ ] 6.9 Confirm theme compliance per CLAUDE.md UI Development Guidelines: NO hardcoded Tailwind/CSS colours; reuse the existing theme system. (mini-broker is Flutter, so this is theme widget colors — verify how the existing forms colorize input fields and follow suit.)
- [ ] 6.10 Manual UX walk: open each form, observe auto-seed re-derives on every input edit; uncheck the box, edit the value, re-check, observe overwrite + toast. Confirm that two consecutive submits of the same form produce identical seeds and that the second submit is idempotent end-to-end (verify in postgres / chain trace).
- [ ] 6.11 Confirm with `kam` UX is right before merging.

---

## Phase 7 — `trade_bench` UI integration

Location: `apps/apps/trade_bench/`.

> **NOTE**: trade_bench currently has only `settings`, `home`, `config`, `shell`, `about`, `event_messages`, `login` features under `lib/features/`. There is **no trading or portfolio screen yet**. Either (a) the trading screens land before EXIDS Phase 7 starts, in which case wire EXIDS into them at construction time; or (b) Phase 7 is reduced to "ensure `common_ui` widget is consumed by trade_bench when its trading screens land". Confirm scope with `kam` at Phase 0.6.

- [x] 7.1 Confirmed 2026-05-10: trade_bench has no trading/portfolio screens yet — only `settings`, `home`, `config`, `shell`, `about`, `event_messages`, `login` features. The only file mentioning a mutating RPC is `trade_bench_event_subscription.dart`, and only in a comment.
- [x] 7.2 trade_bench's pubspec already declares `common_ui:` as a workspace dep. No additional wiring needed today — `package:common_ui/common_ui.dart` exports `ExecutionIdempotencySeedField`, `TreasuryStashDerivationSeedField`, `ExecutionIdempotencySeedViewerDialog`, `validateExidsSeed`, `validateStashSeed`, and `SeedHistoryStore`. When trade_bench gains trading screens, the integration is a 1-line import + form-binding step.
- [x] 7.3 No-op (no mutating-RPC callsites today). `flutter analyze` on trade_bench is green after the brktrdapi proto changes propagated.
- [N/A] 7.4 / 7.5 / 7.6 / 7.7 — moved to "future" status; revisit when trading screens land.

---

## Phase 8 — E2E test sweep

Per saved memory `feedback_saga_proto_changes_full_sweep.md`: changes to sagas/proto/gateway surfaces ripple across multiple e2e categories. Touch them all in the same PR.

Categories that almost certainly need updates (cross-check `docs/E2E_TEST_CATALOG.md` while doing this — categories may have shifted):

- [ ] 8.1 **Cat 1b** (`laser-e2e-ethbc-cat1`) — FundAccount Saga. Tests already pass `treasury_ops_base_idempotency_key`:
  - `tests/e2e/laser/fund_account_saga_test.go:624` — already wired
  - `tests/e2e/laser/fund_account_cmd_test.go:83` — already wired (`facmd-cash-single-fund-001`)
  - `tests/e2e/laser/chain_verification_fundaccount_test.go:321` — already wired
  - **Action**: ensure these tests now route through the gRPC gateway with `execution_idempotency_seed = "<the-string-above>"` instead of submitting saga input directly. Add a parallel test variant for each that verifies gateway-level rejection on missing seed.
- [ ] 8.2 **Cat 31** — Create Direct Order. Add seed-supplied test variant + same-seed-twice retry test.
- [ ] 8.3 **Cat 32** — FIX→Saga NewOrderSingle. The FIX adapter does NOT have an EXIDS field (FIX is a separate protocol). Decide: (a) FIX path stays on a deterministic server-derived TOBIK (special-case in fixreceiver); (b) FIX path is out of EXIDS scope entirely. Recommended: (a) — the FIX adapter generates a TOBIK from the inbound `ClOrdID` (which is the FIX equivalent of "client-controlled idempotency"), document in this TODO under D11 once decided.
- [ ] 8.4 **Cat 35** — Fund Account Command. Already TOBIK-aware (`fund_account_cmd_test.go:83`). Add gateway-routed variant.
- [ ] 8.5 **Cat 37** — Create Investor Order. Most-exercised path; add the most thorough retry-determinism test here:
  - Submit `CreateOrderAsync` with seed `S`; observe saga `A` and on-chain tx `T`.
  - Re-submit `CreateOrderAsync` with same seed `S`, same payload; observe response references saga `A` (no new saga); on-chain state unchanged.
  - Submit `CreateOrderAsync` with same seed `S`, *different* payload (e.g. quantity changed); observe O3-defined behaviour (recommended: rejected).
  - Submit `CreateOrderAsync` with different seed, same payload; observe new saga `B` and new on-chain tx `T'`.
- [ ] 8.6 **Cat 40** — Idempotent Treasury Vault. The on-chain assertion pivot: same seed + retry → second on-chain call is a no-op at the vault. This is where the Erc20VaultIdempFacet (`TODO_IDEMPOTENT_TREASURY_VAULT_OPERATIONS.md`) earns its keep. Verify by inspecting `lcmgr.trz_erc20_idempotency_keys` rows.
- [ ] 8.7 **Cat 38** — FIX Sender Report Delivery. Verify `handle_*_fix_exec_report` sagas still receive TOBIK end-to-end after Phase 4's tightening.
- [ ] 8.8 **Cat 42** — State Actuator Service. actusvc carries TOBIK from event index to accmgr REST; verify the path is unbroken.
- [ ] 8.9 Add a new test file `tests/e2e/laser/exids_validation_test.go` per RPC in D3. **This is the primary EXIDS test surface — be thorough.** Cover every reason code in D1.1's table:

  **Length and emptiness:**
  - empty / unset seed → `InvalidArgument` with reason `EXIDS_MISSING`
  - 1-byte seed → `EXIDS_TOO_SHORT`
  - 7-byte seed → `EXIDS_TOO_SHORT`
  - 8-byte seed (boundary) → accepted
  - 256-byte seed (boundary) → accepted
  - 257-byte seed → `EXIDS_TOO_LONG`
  - 1MB seed → `EXIDS_TOO_LONG`

  **Whitespace (the "messy input" cases per O8):**
  - leading space `" cio:v1:abc12345"` → `EXIDS_LEADING_WHITESPACE`
  - trailing space `"cio:v1:abc12345 "` → `EXIDS_TRAILING_WHITESPACE`
  - leading tab `"\tcio:v1:abc12345"` → `EXIDS_LEADING_WHITESPACE`
  - trailing tab → `EXIDS_TRAILING_WHITESPACE`
  - leading newline `"\ncio:v1:abc12345"` → `EXIDS_LEADING_WHITESPACE`
  - trailing CR `"cio:v1:abc12345\r"` → `EXIDS_TRAILING_WHITESPACE`
  - inner space `"cio:v1: abc12345"` → `EXIDS_INNER_WHITESPACE`
  - inner tab `"cio:v1:\tabc12345"` → `EXIDS_INNER_WHITESPACE`
  - inner newline → `EXIDS_INNER_WHITESPACE`
  - NBSP (` `) anywhere → either `EXIDS_NON_ASCII` (caught at byte level first) — assert which order matches the validator
  - whitespace-only `"        "` → `EXIDS_LEADING_WHITESPACE` (first failing rule wins)

  **Control characters:**
  - `"cio:v1:\x00abcde"` (NUL) → `EXIDS_CONTROL_CHAR`
  - `"cio:v1:\x07abcde"` (BEL) → `EXIDS_CONTROL_CHAR`
  - `"cio:v1:\x1Babcde"` (ESC) → `EXIDS_CONTROL_CHAR`
  - `"cio:v1:\x7Fabcde"` (DEL) → `EXIDS_CONTROL_CHAR`
  - error message includes the byte offset of the first violation

  **Non-ASCII:**
  - smart-quotes `"cio:v1:“abc"` → `EXIDS_NON_ASCII`
  - emoji `"cio:v1:🔑abcde"` → `EXIDS_NON_ASCII`
  - accented `"cio:v1:café123"` → `EXIDS_NON_ASCII`
  - cyrillic `"cio:v1:абв12345"` → `EXIDS_NON_ASCII`
  - lookalike attack `"cio:v1:аbcde"` (with Cyrillic 'а' substituted for Latin 'a') → `EXIDS_NON_ASCII`

  **Disallowed ASCII printable chars:**
  - `"cio:v1:abc/de"` (URL path) → `EXIDS_DISALLOWED_CHAR`
  - `"cio:v1:abc?de"` → `EXIDS_DISALLOWED_CHAR`
  - `"cio:v1:abc#de"` → `EXIDS_DISALLOWED_CHAR`
  - `"cio:v1:abc&de"` → `EXIDS_DISALLOWED_CHAR`
  - `"cio:v1:abc=de"` (base64 std) → `EXIDS_DISALLOWED_CHAR`
  - `"cio:v1:abc+de"` (base64 std) → `EXIDS_DISALLOWED_CHAR`
  - `"cio:v1:abc;de"` (SQL) → `EXIDS_DISALLOWED_CHAR`
  - `"cio:v1:abc'de"` (quote) → `EXIDS_DISALLOWED_CHAR`
  - `"cio:v1:abc\"de"` (double quote) → `EXIDS_DISALLOWED_CHAR`
  - `"cio:v1:abc\\de"` (backslash) → `EXIDS_DISALLOWED_CHAR`
  - `"cio:v1:abc<de"` / `"cio:v1:abc>de"` → `EXIDS_DISALLOWED_CHAR`
  - `"cio:v1:abc(de"` / `"cio:v1:abc)de"` / `[`, `]`, `{`, `}` → `EXIDS_DISALLOWED_CHAR`
  - `"cio:v1:abc*de"` / `,`, `^`, `~`, `|`, `!`, `@`, `$`, `%` → `EXIDS_DISALLOWED_CHAR`
  - error message names the disallowed char and its offset

  **Allowed-charset boundary (must accept):**
  - `"abcdefgh"` (8-char min, all letters) → accepted
  - `"01234567"` (all digits) → accepted
  - `"a:b.c-d_e"` (every allowed punctuation) → accepted
  - `"AbCdEfGhIjKl"` (mixed case) → accepted
  - `"cio:v1:" + sha256-hex` (canonical recipe output) → accepted
  - 256-char seed of pure `[A-Za-z0-9:_.-]` → accepted

  **End-to-end propagation** (the "real" tests, not just validation):
  - same seed + identical payload twice → exactly one ledger movement (verified by `lcmgr.trz_erc20_idempotency_keys` row count = 1)
  - same seed + different payload → behaviour matches O3 (option c — payload-hash mismatch detected, second call rejected)
  - seed propagates verbatim from gateway request → `sagaInput["treasury_ops_base_idempotency_key"]` → `handle_*_fix_exec_report` child saga → treassvc executor's `idempkey.RequireFromInput` → `StepBuilder.For` mints the per-step on-chain key
  - per-step key derivation matches D11: minted key for `lock_order_volume` step = `<seed>-cio_lock_order_volume-lock-value` (verifiable in `lcmgr.trz_erc20_idempotency_keys.idempotency_key` column)
  - `originIdempotencyKey` recorded in TRAX = `"create_investor_order_" + seed` per D12

  **Hash determinism with messy inputs** (per O8 emphasis on "complex input structures that may carry tabs, spaces, etc."):
  - construct two payloads that differ ONLY in tab vs space inside a free-text field (e.g. order `aux_data["note"] = "hello world"` vs `"hello\tworld"`); send same seed twice; assert payloads are detected as different and second is rejected
  - same payload submitted with `quantity = "100"` vs `"100.0"` vs `"100.00"`; depending on the gateway's payload-canonicalisation rule (decided in Phase 3), assert the gateway either treats them as identical or distinct — and document which
  - same payload with field-key ordering swapped in JSON (where applicable) → must be canonicalised by the validator before hashing
  - inputs containing the exact char set EXIDS rejects in the seed itself (a human-typed `aux_data["memo"] = "with / slash and ; semi"`) → must NOT cause seed validation to fail (seed validation is on the seed only, not on the payload)

  **Cross-RPC isolation** (per O3 namespace prefix rule):
  - submit `CreateOrderAsync` with seed `S`; submit `DepositCash` with the same seed `S`; assert no cross-collision (two distinct sagas, two distinct on-chain key sets)
- [ ] 8.10 Update `tests/e2e/laser/order_test_infra_test.go` (already TOBIK-aware at lines 1701, 1817): add helper `submitOrderViaGatewayWithSeed(t, seed)` that mirrors the existing `submitOrderViaSagaSubmitter` but routes through gRPC.
- [ ] 8.11 Update Makefile patterns (`E2E_CATn_PATTERN`) to include any new test names. Run `make e2e-cat-help` to verify each new test is picked up by the right category.
- [ ] 8.12 Update `docs/E2E_TEST_CATALOG.md` with the new tests' descriptions.

---

## Phase 9 — Forward expansion (out of scope here, parked for sequencing)

Per the user's parking-lot statement: after this TODO ships, expand `execution_idempotency_seed` to every other gRPC interface and every admin app under `apps/apps/`. Each expansion is its own follow-up TODO. **Lock the rule here** so future API additions get the field for free:

- Future TODO: `TODO_EXIDS_EXPANSION_TO_ADMIN_APIS.md` — covers `sdappv1`, `exchappv1`, `prtagentappv1`, `csdmsggw` (rename `SdOpsBaseIdempotencyKey` → `ExecutionIdempotencySeed`?), `sdappgw`, `exchappgw`, `prtagentappgw`. Plus the eventual server-side `ListExecutionIdempotencySeeds` RPC if D6's local-only persistence proves limiting.
- Future TODO: `TODO_EXIDS_EXPANSION_TO_ADMIN_APPS.md` — covers `security_depository_admin`, `exchange_admin`, `prtagent_admin`, `broker_admin`, plus any remaining suite app under `apps/apps/`. May reuse the `common_ui` widget verbatim.
- The brkadmapi guard comment added in Phase 5.2 is the cross-reference anchor: any new write RPC in any gateway must follow the EXIDS contract.

---

## Files this TODO is expected to touch (full traceability table)

| Phase | File / Dir | Action | Anchor |
|---|---|---|---|
| 1 | `pkg/treasury/idempkey/builder.go` | NO CHANGE (audit only) | builder.go:38 (InputKey), :47 (New), :63 (RequireFromInput) |
| 1 | `pkg/daemons/treassvc/trax/executors/**/*.go` | NO CHANGE (audit only) | per-file table in Phase 1 deliverable |
| 1 | `pkg/daemons/accmgr/trax/executors/**/*.go` | NO CHANGE (audit only) | per-file table in Phase 1 deliverable |
| 2 | `data/api/grpc/prtagent/v1/trading.proto` | EDIT: add field on 3 RPCs | line 136 (Create), 163 (Replace), 179 (Cancel) |
| 2 | `data/api/grpc/prtagent/v1/investor.proto` | EDIT: add field on 3 RPCs | line 206 (Deposit), 221 (Withdraw), 236 (WithdrawSecurity) |
| 2 | `pkg/daemons/prtagent/impl/v1/grpc/trading.go` | EDIT: validator, delete derivation, wire seed | line 584 (DELETE derivation), 385/831/835 (validator at top of CreateOrderAsync/Replace/Cancel) |
| 2 | `pkg/daemons/prtagent/impl/v1/grpc/investor.go` | EDIT: validator + helper signature change | line 279 (DELETE derivation in withdraw), 328 (DELETE in fund), 1004/1085/1166 (validator at top of DepositCash/WithdrawCash/WithdrawSecurity) |
| 2 | `pkg/daemons/prtagent/impl/v1/grpc/api.go` (or new validators.go) | NEW: `validateExecutionIdempotencySeed` | n/a |
| 2 | `pkg/daemons/prtagent/impl/v1/grpc/trading_test.go` | EDIT + NEW tests (Phase 2.12) | n/a |
| 2 | `pkg/daemons/prtagent/impl/v1/grpc/investor_test.go` | EDIT + NEW tests | n/a |
| 3 | `pkg/daemons/prtagent/impl/v1/grpc/...` (registry) | NEW: same-seed dedup | search `originIdempotencyKey` |
| 4 | `pkg/daemons/treassvc/trax/executors/create_investor_order/lock_order_volume.go` | EDIT: tighten compensation | line 272-280 |
| 4 | `pkg/daemons/treassvc/trax/executors/create_investor_order/transfer_fee.go` | EDIT: tighten compensation | line 297-300 |
| 4 | `pkg/daemons/treassvc/trax/executors/unlock_order_stash/transfer_stash.go` | EDIT: tighten compensation | line 233-236 |
| 4 | `pkg/daemons/accmgr/api/v1/accounts_post_handle_fix_exec_report.go` | EDIT: WARN→ERROR | line 149-150 |
| 4 | `pkg/daemons/accmgr/api/v1/accounts_post_fund_batch.go` | EDIT: review temporary TOBIK suffix comment | line 177-179 |
| 4 | `pkg/treasury/idempkey/builder.go` | EDIT: maybe delete OptionalFromInput | line 73-84 |
| 5 | `data/api/grpc/brktrdapi/v1/service.proto` | EDIT: add field on 7 (or 9 with O2) RPCs | line 221, 230, 241, 249, 258, 267, 279, 297, 307 |
| 5 | `data/api/grpc/brkadmapi/v1/service.proto` | EDIT: add guard comment only | top of service block |
| 5 | `pkg/daemons/brktrdsvc/impl/v1/grpc/trading.go` | EDIT: validator + delete derivation + wire seed | line 195 (DELETE), 44/265/285 (validator) |
| 5 | `pkg/daemons/brktrdsvc/impl/v1/grpc/cash.go` | EDIT: validator + delete derivation + wire seed | line 210 (DELETE), 40/113/269/278 (validator) |
| 5 | `pkg/grpc/exids/validator.go` | NEW: shared validator package (or inline copy) | n/a |
| 6 | `apps/packages/common_ui/lib/widgets/execution_idempotency_seed_field.dart` | NEW | n/a |
| 6 | `apps/packages/common_ui/lib/widgets/execution_idempotency_seed_viewer_dialog.dart` | NEW (per D5.1: copy + full-screen modal) | n/a |
| 6 | `apps/packages/common_ui/lib/services/exids_validator.dart` | NEW (Dart mirror of Go validator, D1.2) | n/a |
| 6 | `apps/packages/common_ui/lib/services/seed_history_store.dart` | NEW | n/a |
| 6 | `apps/packages/common_ui/lib/services/idemp_seeds/*.dart` | NEW (one per RPC) | n/a |
| 6 | `apps/packages/common_ui/test/...` | NEW (recipe + history tests) | n/a |
| 6 | `apps/apps/legacy/mini-broker/lib/screens/trading_page.dart` | EDIT: wire widget | n/a |
| 6 | `apps/apps/legacy/mini-broker/lib/screens/portfolio_page.dart` | EDIT: wire widget | n/a |
| 6 | `apps/apps/legacy/mini-broker/lib/screens/broker/orders_page.dart` | EDIT: wire widget if applicable | n/a |
| 6 | `apps/apps/legacy/mini-broker/lib/services/auth_service.dart` | EDIT: clear seed history on logout | n/a |
| 7 | `apps/apps/trade_bench/lib/features/.../*.dart` | EDIT (or defer per Phase 7 note) | n/a |
| 7 | `apps/apps/trade_bench/lib/services/...` | EDIT: clear on logout | n/a |
| 8 | `tests/e2e/laser/exids_validation_test.go` | NEW | n/a |
| 8 | `tests/e2e/laser/create_investor_order_test.go` | EDIT: gateway-routed retry test | n/a |
| 8 | `tests/e2e/laser/create_direct_order_test.go` | EDIT: same | n/a |
| 8 | `tests/e2e/laser/fund_account_cmd_test.go` | EDIT: gateway-routed variant | line 83 |
| 8 | `tests/e2e/laser/fund_account_saga_test.go` | EDIT: gateway-routed variant | line 624 |
| 8 | `tests/e2e/laser/chain_verification_fundaccount_test.go` | EDIT: gateway-routed variant | line 321 |
| 8 | `tests/e2e/laser/order_test_infra_test.go` | EDIT: add `submitOrderViaGatewayWithSeed` helper | line 1701, 1817 |
| 8 | `Makefile` (`E2E_CAT*_PATTERN`) | EDIT | n/a |
| 8 | `docs/E2E_TEST_CATALOG.md` | EDIT | n/a |
| All | this file (`docs/TODO_EXECUTION_IDEMPOTENCY_SEED.md`) | EDIT continuously (open questions, Phase 1 deliverable, decisions as they evolve) | this file |
| All | `CLAUDE.md` daemon notes for prtagent / brktrdsvc | EDIT once full surface lands | per-daemon line in "Core Daemons" section |

---

## Phase 10 — Post-ship hardening (2026-05-11)

A series of issues surfaced on **vp-agora-plgr1** during real Withdraw /
Deposit testing forced a second pass over the EXIDS plumbing.
Documented here so subsequent work and reviewers can trace the WHY of
each diff and don't redo the same investigations.

### P10.1 — Probe moved off `lcmgr.trz_erc20_idempotency_keys` onto `shared.exids_payload_registry`

The original consumed-seed probe (commits `488c4de16`, `c61a6d7a2`)
SELECT-ed against `lcmgr.trz_erc20_idempotency_keys`. That schema
lives in a different daemon's database than `brktrdsvc` /
`prtagent` connect to on plgr1, so the probe got `relation does not
exist` and my fail-closed posture turned every cash-flow RPC into
`UNAVAILABLE`.

Per kam: "we have a table for it" — meaning `shared.exids_payload_registry`
already exists in the prtagent-ns DB and is the right place. The
probe now uses it via `exids.Registry.IsSeedConsumed` (commit
`5e774b124`), no cross-namespace dependency. `pkg/treasury/idempkey/probe.go`
+ tests deleted.

### P10.2 — Probe runs BEFORE `CheckOrRecord`, not after

The probe was sitting AFTER `exids.DispatchRegistry`, so a registry
`IdempotentRetry` short-circuit could hand the UI a prior
`saga_instance_id` whose traxctrl row was long gone — UI's
`WaitForExecution` then surfaced `code=5 NOT_FOUND`. Moved the probe
ahead of the registry dispatch in all six cash-flow handlers (commit
`c61a6d7a2`). On-chain key consumption is the source of truth; the
registry is a TTL'd cache.

### P10.3 — Explicit lifecycle column on the registry

`shared.exids_payload_registry` gains a `state TEXT` column with
three values:

- `'pending'` — reservation taken, saga in-flight or not yet observed.
- `'committed'` — observer (`WaitForExecution` / `PollExecution`) saw
  the saga reach `COMPLETED`. Seed is consumed.
- `'failed'` — observer saw a non-success terminal status. Row stays
  as audit trail; `CheckOrRecord` recycles it back to `'pending'` so
  the next retry gets a Fresh attempt.

Per kam (2026-05-11) — "when an operation fails, the exids must not
be stored" — failed seeds are recyclable. Shipped in commit
`7f502b811`. `IsSeedConsumed` filters by `state='committed'` only.
`EvictExpired` only touches abandoned `'pending'` rows; committed +
failed rows survive forever.

New `Registry` interface methods (Pgsql + InMemory):
- `MarkCommitted(ctx, rpc, seed)`
- `MarkFailed(ctx, rpc, seed)`
- `LookupBySagaInstance(ctx, sagaInstanceID) (rpc, seed, found, err)`

### P10.4 — Orphan saga cleanup

When `WaitForExecution` / `PollExecution` exits on `codes.NotFound`
past the 15s `sagaInsertGracePeriod`, the saga is an orphan
(accmgr's MQ publish succeeded but traxcoord never persisted —
e.g. coord restart that lost the message, or the saga template
wasn't registered). The gateway now reverse-looks-up the registry
by saga_instance_id and `MarkFailed` the row so the user's next
retry with the same seed is Fresh. Without this the seed stuck on
the dead saga id forever. Commit `e0577b090`.

### P10.5 — Per-RPC scope confirmed; on-chain alignment deferred

Registry PK is `(rpc_name, seed)` — same seed under different RPCs
is allowed (kam ratified 2026-05-11). The probe and lifecycle
methods are all per-RPC scoped.

**Known gap — flagged for future work.** The on-chain idempotency
key derives from `<seed>-<op_suffix>` where the suffix is
per-saga-step, NOT per-RPC. Within TABT, WithdrawCash / LockCash /
UnlockCash all share the `withdraw-transfer` suffix (see
`pkg/treasury/idempkey/builder.go::WithdrawTransfer`). So a seed
reused across two different RPCs that submit the same saga template
collides on-chain even though the registry treats them as
unrelated. Decision (kam, 2026-05-11): keep the off-chain per-RPC
scope; address on-chain alignment later (likely by prefixing the
on-chain key with `rpc_name` in `idempkey.Builder` so different
RPCs minting the same suffix get distinct on-chain keys).

### P10.6 — `MarkCommitted` must fire when on-chain effect is produced, NOT only on saga COMPLETED

This is the **fix kam pressed for**: a saga can fail at a late step
(e.g. `tabt_verify_balances`) but still have produced on-chain
effects in earlier steps (`tabt_transfer_between_stashes` /
`tabt_finalize_to_erc20`). The on-chain idempotency key is burned
permanently by those earlier steps — no retry with the same seed
can ever re-execute it.

Today's `reconcileExidsRegistry` collapsed this case into
`MarkFailed`, which made `CheckOrRecord` recycle the row to
Fresh — a second submission with the same seed then passed the
probe, hit the burned on-chain key, got a silent no-op, and the
verify step caught the discrepancy as a "balance after doesn't
match expected" error. The user got stuck in a loop with no clean
recovery (the on-chain layer doesn't surface the `idempotency_key_reused`
flag in EthBC mode — see P10.7).

**Decision (kam, 2026-05-11):** the saga that touches treasury is
the **primary owner** of the registry state transition once the
on-chain effect is produced. The gateway acts as a **safety net**.

#### P10.6.A — Saga-side primary path

`exids_rpc_name` is added to saga input by the gateway on
submission (WithdrawCash / LockCash / UnlockCash / DepositCash from
brktrdsvc + prtagent). accmgr's `verify_inputs` propagates it. The
treassvc saga step body, on a successful on-chain idempotent
mutation, calls `registry.MarkCommitted(rpc, seed)` against
`shared.exids_payload_registry` (treassvc shares the prtagent-ns
Postgres, no cross-namespace dependency). MarkCommitted errors are
logged + swallowed — the saga still progresses; the gateway safety
net catches a missed Mark.

Step bodies that perform on-chain idempotent mutations:
- TABT `tabt_transfer_between_stashes` (TVB)
- TABT `tabt_finalize_to_erc20` (withdraw + optional burn)
- `fund_account_with_cash_tokens` `facwct_mint_tokens_if_needed`
  (mint + approve + deposit)
- `fund_account_with_cash_tokens` `facwct_transfer_to_destination`
  (TVB-like transfer)

#### P10.6.B — Gateway safety net

In `reconcileExidsRegistry`, when a saga reaches a non-success
terminal status, fetch its step results and inspect each step's
`result_data` for tx-hash markers (`tx_hash`, `transfer_tx_hash`,
`withdraw_tx_hash`, `mint_tx_hash`, `deposit_tx_hash`,
`burn_tx_hash`). If any step left an on-chain trace →
`MarkCommitted` (seed irrevocably burned). Only when NO step has
any on-chain marker → `MarkFailed` (truly recyclable).

This collapses two prior-existing concerns into one rule:
"on-chain effect produced ≡ seed committed".

### P10.7 — EthBC mode doesn't surface `idempotency_key_reused`

`pkg/daemons/lcmgr/trezor_erc20_contract.go` sets
`metadata["idempotency_key_reused"]="true"` on the four
`mutationIdemp*` paths, but those only fire in the RDBMS-simulation
backend. EthBC mode (real Ethereum / Anvil) goes through the
on-chain idemp facet directly; the saga step sees a successful
return + the prior tx hash, has no way to tell it was a no-op.

This is the underlying mechanic that turned a seed-reuse into a
verify-step failure on plgr1. P10.6 mitigates the user-facing
impact (the registry now correctly stays committed across the
saga's compensation cycle). The deeper fix — surfacing the reuse
signal from EthBC up to the saga step — is parked as future work.

### P10.8 — Other fixes in the same window

- **WithdrawCash `destination_account_iid` was blank** (both
  brktrdsvc + prtagent). accmgr's default for blank destination is
  to use source, which collapsed the TABT TVB into a same-vault-
  same-stash call that reverted on-chain with `E20I:TSS`. Gateway
  now resolves the clearing account IID via
  `prtagentcommon.ResolveCachedParticipantCsdAccountIidAndLegalStructureIidAndClearingAccountVaultSlot`
  (its 3rd return value) and passes it as `destination_account_iid`.
  Commit `ea279a614`.
- **`tabt_verify_balances` destination-balance check** was
  asserting `destination_after >= amount` for ALL TABT flows. For
  Withdraw with `finalize_to_erc20=true` the destination stash is
  credited then debited within the same saga, net-zero change —
  the check spuriously failed whenever the clearing vault carried a
  pre-saga balance below `amount`. Now gated on `finalize_to_erc20
  = false` (Lock/Unlock only). Source-decreased-by-amount check is
  the meaningful invariant for Withdraw and was tightened from Warn
  to Error. Commit `2896bd5e1`.
- **TABT saga template registration**. `deploy/k8s/init/prtagent/min/trax.sql`
  still seeded the older `withdraw_cash_tokens_from_account`
  template + 6 `wcfa_*` steps. Replaced with `treasury_asset_balance_transfer`
  template + 8 `tabt_*` steps matching the executors registered in
  pkg/daemons/{accmgr,treassvc}/trax/executors/treasury_asset_balance_transfer/.
  Applied to vp-agora-plgr1 via `kubectl exec ... psql -f`. Commit
  `228b5b974`.
- **EXIDS in NewInvestor + signup UX**. prtagent's `NewInvestor`
  gains `execution_idempotency_seed = 200`. trade_bench + mini-broker
  signup pages render an `ExecutionIdempotencySeedField` (mini-broker
  has an inline equivalent — no `common_ui` dep). Commits
  `20204b341`, `1e4cc36` (mini-broker submodule).
- **brktrdsvc helm chart** gains `TREASURY_INDEXER_BASE_URL` (needed
  by the treasidxer-backed `ListInvestorTransactions` shipped in
  `533d2813b`). Commit `808e66fc5`.

### P10.9 — Phase 10 done-criteria

- [x] Probe runs before registry CheckOrRecord (P10.2).
- [x] Probe reads `shared.exids_payload_registry`, not lcmgr (P10.1).
- [x] Three-state lifecycle on the registry row (P10.3).
- [x] Orphan saga auto-cleanup on NOT_FOUND past grace (P10.4).
- [ ] Saga-side primary `MarkCommitted` on on-chain effect (P10.6.A) — in progress.
- [ ] Gateway safety net scan for tx-hash markers (P10.6.B) — in progress.
- [ ] On-chain `idempotency_key_reused` signal surfaced in EthBC mode (P10.7) — parked.
- [ ] On-chain key derivation prefixed with `rpc_name` (P10.5) — parked.

---

## Done criteria

- [ ] Every in-scope RPC rejects requests missing `execution_idempotency_seed` with `codes.InvalidArgument` before any saga is started.
- [ ] No gateway handler still derives TOBIK from request fields (verify by `grep -rn "treasury_ops_base_idempotency_key\":" pkg/daemons/{prtagent,brktrdsvc}` — every match should be `req.GetExecutionIdempotencySeed()`).
- [ ] Every saga step that mutates a treasury vault calls `idempkey.RequireFromInput` (no `OptionalFromInput` callsite remains downstream of an EXIDS-mandatory RPC).
- [ ] Every soft-fall-back compensation branch (`compensation_status: skipped_missing_treasury_ops_base_idempotency_key`) is deleted from the EXIDS-served code paths.
- [ ] Re-submitting the identical (seed, payload) pair through the gateway results in **exactly one** on-chain vault state change, observable via Cat 40 e2e and a single row in `lcmgr.trz_erc20_idempotency_keys`.
- [ ] mini-broker shows the auto-generate widget on every in-scope form, default-checked, with editable history when unchecked.
- [ ] trade_bench either has the widget on its trading screens, OR depends on `common_ui`'s widget and is ready to consume when those screens land (Phase 7 outcome).
- [ ] The `exids_seed_collision_total` and `exids_seed_validation_failed_total` Prometheus metrics are emitted by the gateway.
- [ ] `MEMORY.md` (auto-memory index) gains an entry pointing to this TODO under "EXIDS — execution idempotency seed contract".
- [ ] All affected e2e categories are green.
- [ ] All affected docs are updated (saga TODOs, gateway TODO, E2E catalog, this file's Phase 1 deliverable).
- [ ] CLAUDE.md gains a one-line note under prtagent and brktrdsvc daemon descriptions referencing EXIDS as the client-controlled idempotency contract.
