# TODO: Setup New Legal Participant - TRAX Saga Implementation

> **Status**: COMPLETED
> **Created**: 2026-01-16
> **Last Updated**: 2026-04-25
>
> **Note (2026-04-25)**: The api-key step (Step 7,
> `create_legal_participant_api_key`) was deleted and replaced by the
> generalised `create_api_keys` step. Saga inputs lost the three
> `api_key_display_name` / `api_key_rate_limit` /
> `api_key_allowed_operations` scalars; they were replaced by a single
> `api_keys` JSON-encoded list of `{participant_iid, display_name,
> rate_limit, allowed_operations}` entries — one per participant
> (legal participant or partner) that should receive a key. Empty
> `participant_iid` resolves to the legal participant being created.
> See the sdappgw / exchappgw `Create*` request messages and
> `pkg/daemons/accmgr/trax/executors/setup_new_legal_participant/create_api_keys.go`
> for the canonical shape.
>
> The saga also picked up additional optional inputs for legal-structure
> widening: `legal_structure_type`, `legal_structure_parent_participant_iid`,
> `legal_structure_identifiers / labels / tags / metadata /
> descriptions`, plus participant-side `legal_participant_labels /
> tags / metadata`. The historical hardcode of `type=PARTNERSHIP` is
> lifted; absent input still defaults to `PARTNERSHIP` for back-compat.
> **Dependencies**:
> - `establish_new_legal_structure_for_participant` saga (EXISTS)
> - `deploy_core_legal_mechanisms_for_legal_structure` saga (EXISTS)
> - `deploy_treasury_legal_mechanisms_for_legal_structure` saga (EXISTS)
> - `deploy_cash_token_legal_mechanism_for_legal_structure` saga (EXISTS - see TODO_DEPLOY_CASH_TOKEN_LEGAL_MECHANISM_SAGA.md)

---

## Overview

TRAX saga template `setup_new_legal_participant` that creates a complete Legal Participant with full infrastructure:
1. Legal Participant record
2. Board partner participant records (create new OR reference existing)
3. Legal Structure with owner/partner/clearing accounts (via sub-saga)
4. Core Legal Mechanisms - TaskManagerV2 + AuthzDiamond (via sub-saga)
5. Treasury Legal Mechanisms - RAC + Trezor Diamonds (via sub-saga)
6. Cash Token Legal Mechanisms - one per currency (via sub-saga loop)
7. API Key for Legal Participant REST authentication

**Key Concepts**:
- **Legal Participant**: The primary entity being set up
- **Legal Structure**: PARTNERSHIP type, owned by Legal Participant
- **Core Legal Mechanisms**: TaskManagerV2 (voting) + AuthzDiamond (authorization)
- **Treasury Legal Mechanisms**: RAC + Trezor Diamonds
- **Cash Token**: ERC20 per currency issued to Legal Structure Clearing Account
- **Sub-Saga**: First implementation of nested saga spawning with polling

**Architecture**: Hybrid approach - direct DB calls for participant creation, spawn existing sagas for mechanism deployments.

---

## Prerequisites

1. **Execution Runtime** configured in LASER (no validation - LASER handles it)
2. **All dependent sagas implemented**:
   - `establish_new_legal_structure_for_participant`
   - `deploy_core_legal_mechanisms_for_legal_structure`
   - `deploy_treasury_legal_mechanisms_for_legal_structure`
   - `deploy_cash_token_legal_mechanism_for_legal_structure`

---

## Saga Specification

### Inputs

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| legal_participant_iid | string | No | Optional IID; generated if missing |
| legal_participant_display_names | map[string]string | Yes | At least one entry required |
| legal_participant_descriptions | map[string]string | No | Optional descriptions |
| legal_participant_types | []string | Yes | Participant types (must not be empty) |
| legal_participant_identifiers | []FinIdentifier | No | SYMBOL, LEI, TEXT, etc. |
| partners | []PartnerSpec | Yes | At least one partner required |
| deployer_partner_iid | string | Yes | Must be one of the partners |
| legal_structure_display_names | map[string]string | No | Uses Legal Participant names if empty |
| prefix | string | No | Contract naming prefix; derived if empty |
| exec_runtime_name | string | Yes | e.g., "primary" |
| locale | string | Yes | e.g., "en-US" |
| currencies | []string | No | Empty = no cash tokens issued |
| initial_amounts | map[string]string | No | Amounts per currency (in cents) |
| api_key_display_name | string | No | Default: "Legal Participant API Key" |
| api_key_rate_limit | int | No | Default: 60/min |
| api_key_allowed_operations | []string | No | Empty = all allowed |
| treasury_name | string | No | Existing treasury diamond slot address to reuse |
| force_creation_of_treasury_mechanism | bool | No | Deploy treasury even with no currencies |
| decimals | map[string]int | Cond. | Required for each currency when currencies non-empty |

### Treasury/Currency Rules

The following rules govern when treasury mechanisms and cash tokens are deployed:

| currencies | treasury_name | force_creation | Behavior |
|---|---|---|---|
| > 0 | provided | ignored | Use existing treasury, deploy cash tokens |
| > 0 | empty | ignored | Deploy new treasury, then deploy cash tokens |
| 0 | -- | true | Deploy new treasury, no cash tokens |
| 0 | -- | false/absent | No treasury, no cash tokens |

**Rule 1 (API-level validation):**
- If `currencies` is non-empty: every currency must have an entry in both `initial_amounts` AND `decimals` (no defaults)
- Keys in `initial_amounts` or `decimals` that are not in `currencies` are rejected (400)
- If `currencies` is empty: `initial_amounts` and `decimals` must also be empty (400 otherwise)

**Rule 2 (executor-level, treasury_name provided):**
- Step 5 (spawn_deploy_treasury) skips sub-saga deployment
- Returns `trezor_diamond_slot_address = treasury_name` with `treasury_reused: "true"`

**Rule 3 (executor-level, currencies > 0, no treasury_name):**
- Step 5 deploys new treasury mechanisms via sub-saga (existing behavior)
- Step 6 deploys cash tokens for each currency

**Rule 4 (executor-level, no currencies, force_creation=true):**
- Step 5 deploys new treasury mechanisms via sub-saga
- Step 6 skips (no currencies)

**PartnerSpec Structure (widened 2026-04-26)**:
```go
type PartnerSpec struct {
    Iid          string            `json:"iid"`                      // Required (provided or generated)
    DisplayNames map[string]string `json:"display_names"`            // Required if CreateNew
    Descriptions map[string]string `json:"descriptions,omitempty"`   // Caller-supplied descriptions land on the participant record
    Prefix       string            `json:"prefix,omitempty"`         // Stashed in account.labels.partner_naming_prefix by create_partner_accounts
    Types        []string          `json:"types"`                    // Required if CreateNew (INDIVIDUAL, CORPORATE, etc.)
    Identifiers  []FinIdentifier   `json:"identifiers,omitempty"`
    CreateNew    bool              `json:"create_new"`               // true=create, false=reference existing
    AccountType  string            `json:"account_type,omitempty"`   // AccountTypeEnum name; empty falls back to CUSTODY
    Relations    []string          `json:"relations,omitempty"`      // ParticipantToLegalStructureRelationTypeEnum tokens (CEO, BOARD_MEMBER, …)
}
```

> **Note (2026-04-26)**: The full `partners` JSON list is forwarded to
> the LS sub-saga (`establish_new_legal_structure_for_participant`) via
> `spawn_establish_legal_struct`'s `partners` input. The sub-saga's
> step 6 (`create_accounts_for_legal_structure_partners`) consumes
> `partner.account_type` + `partner.prefix`, and a new step 12
> (`create_participant_to_legal_structure_relations`) consumes
> `partner.relations` to write rows into
> `accmgr.participant_to_legal_structure_relations`. Issuer + custodian
> wrapper sagas now forward `legal_participant_identifiers` instead of
> hardcoding `[]`.

### Saga Steps (7 steps)

| Step | Name | Service | Description |
|------|------|---------|-------------|
| 1 | `create_legal_participant_record` | **accmgr** | Create Legal Participant with provided/generated IID |
| 2 | `create_or_validate_partner_participants` | **accmgr** | Create new OR validate existing partner participants |
| 3 | `spawn_establish_legal_structure_saga` | **accmgr** | Submit Legal Structure establishment sub-saga, wait for completion |
| 4 | `spawn_deploy_core_mechanisms_saga` | **accmgr** | Submit Core Legal Mechanisms deployment sub-saga, wait for completion |
| 5 | `spawn_deploy_treasury_mechanisms_saga` | **accmgr** | Submit Treasury Legal Mechanisms deployment sub-saga, wait for completion |
| 6 | `spawn_deploy_cash_tokens_saga` | **accmgr** | Submit Cash Token sub-sagas (one per currency), wait for all |
| 7 | `create_legal_participant_api_key` | **accmgr** | Create ParticipantAPIKey for Legal Participant REST auth |

**Service Distribution**: All steps owned by **accmgr** (sub-sagas delegate to lasersvc/instrmgr internally)

---

## Implementation Phases

### Phase 1: Sub-Saga Executor Infrastructure (NEW)

**File**: `pkg/trax/sub_saga_executor.go` (NEW)

- [ ] 1.1.1 Create `SubSagaExecutor` struct with polling configuration
- [ ] 1.1.2 Implement `SpawnAndWait(ctx, clusterId, templateId, input, idempotentKey)` method
- [ ] 1.1.3 Implement `pollForCompletion(ctx, clusterId, sagaInstanceId)` method
- [ ] 1.1.4 Implement `getSagaInstance(ctx, clusterId, sagaInstanceId)` via traxctrl API
- [ ] 1.1.5 Implement `extractOutputsFromSteps(ctx, clusterId, sagaInstanceId)` method
- [ ] 1.1.6 Define `SubSagaResult` struct with outputs and error

**Key Design**:
```go
type SubSagaExecutor struct {
    sagaSubmitter SagaSubmitter
    traxCtrlURL   string
    pollInterval  time.Duration  // Default: 2s
    maxWaitTime   time.Duration  // Default: 10min
}

func (e *SubSagaExecutor) SpawnAndWait(
    ctx context.Context,
    clusterId string,
    sagaTemplateId string,
    sagaInput map[string]string,
    originIdempotentKey string,
) (*SubSagaResult, error)
```

---

### Phase 2: Saga Template

**File**: `pkg/trax/templates/agora/csd/setup_new_legal_participant.go` (NEW)

- [ ] 2.1.1 Define `SagaTemplate` with TemplateId: `setup_new_legal_participant`
- [ ] 2.1.2 Define 7 `SagaStepTemplate` records with service=accmgr
- [ ] 2.1.3 Create `CreateSetupNewLegalParticipantSagaTemplates()` function

**File**: `pkg/trax/templates/agora/csd/index.go`

- [ ] 2.2.1 Add call to new template creation function

---

### Phase 3: API Endpoint

**File**: `pkg/daemons/accmgr/api/v1/participants_post_setup_legal.go` (NEW)

- [ ] 3.1.1 Create `setupLegalParticipantRequest` struct
- [ ] 3.1.2 Create `setupLegalParticipantResponse` struct
- [ ] 3.1.3 Implement `postSetupLegalParticipant(c *gin.Context)` handler
- [ ] 3.1.4 Validate required fields
- [ ] 3.1.5 Submit saga via `traxSagaSubmitter.SubmitSaga()`

**File**: `pkg/daemons/accmgr/api/v1/api.go`

- [ ] 3.2.1 Add route: `POST /participants/setup-legal` -> `postSetupLegalParticipant`

---

### Phase 4: ACCMGR Executors

**Directory**: `pkg/daemons/accmgr/trax/executors/setup_new_legal_participant/` (NEW)

#### Step 1: create_legal_participant_record
**File**: `create_legal_participant.go`

- [ ] 4.1.1 Parse legal_participant_iid; generate if missing using `common.SecureRandomString(32)`
- [ ] 4.1.2 Validate legal_participant_display_names not empty
- [ ] 4.1.3 Validate legal_participant_types not empty
- [ ] 4.1.4 Create Participant record with LEGAL_ENTITY + provided types
- [ ] 4.1.5 Return `legal_participant_iid`
- [ ] 4.1.6 COMP: Delete participant record

#### Step 2: create_or_validate_partner_participants
**File**: `create_or_validate_partners.go`

- [ ] 4.2.1 Parse partners JSON array
- [ ] 4.2.2 For each partner with `create_new: true`:
  - Generate IID if missing
  - Validate display_names and types not empty
  - Create Participant record
  - Track as "created" for compensation
- [ ] 4.2.3 For each partner with `create_new: false`:
  - Validate participant exists
  - Validate participant is enabled
- [ ] 4.2.4 Validate deployer_partner_iid is in partners list
- [ ] 4.2.5 Return `partner_participant_iids`, `deployer_participant_iid`, `created_partner_iids` (for compensation)
- [ ] 4.2.6 COMP: Delete only newly created partners (not existing ones)

#### Step 3: spawn_establish_legal_structure_saga
**File**: `spawn_establish_legal_struct.go`

- [ ] 4.3.1 Build sub-saga input from parent input:
  ```
  target_participant_iid = legal_participant_iid
  partner_participant_iids = partner_participant_iids
  display_names = legal_structure_display_names (or legal_participant_display_names)
  type = PARTNERSHIP
  ```
- [ ] 4.3.2 Create SubSagaExecutor with traxctrl URL
- [ ] 4.3.3 Call SpawnAndWait for `establish_new_legal_structure_for_participant`
- [ ] 4.3.4 Extract outputs: `legal_structure_iid`, `owner_account_iid`, `partner_account_iids`, `partner_eth_addresses`, `clearing_account_iid`, `clearing_eth_address`
- [ ] 4.3.5 Identify deployer's account IID and eth address from partner list
- [ ] 4.3.6 Return all extracted outputs + `sub_saga_instance_id`
- [ ] 4.3.7 COMP: Sub-saga handles its own compensation

#### Step 4: spawn_deploy_core_mechanisms_saga
**File**: `spawn_deploy_core.go`

- [ ] 4.4.1 Build sub-saga input:
  ```
  legal_structure_iid = from step 3
  deployer_account_iid = deployer's account from step 3
  deployer_slot_address = deployer's eth address from step 3
  partner_slot_addresses = all partner eth addresses
  prefix = from input or derive from Legal Participant display name
  locale = from input
  exec_runtime_name = from input
  ```
- [ ] 4.4.2 SpawnAndWait for `deploy_core_legal_mechanisms_for_legal_structure`
- [ ] 4.4.3 Extract outputs: `task_manager_mechanism_iid`, `task_manager_slot_address`, `authz_source_mechanism_iid`, `authz_diamond_slot_address`
- [ ] 4.4.4 Return outputs + `sub_saga_instance_id`
- [ ] 4.4.5 COMP: Sub-saga handles its own compensation

#### Step 5: spawn_deploy_treasury_mechanisms_saga
**File**: `spawn_deploy_treasury.go`

- [ ] 4.5.1 Build sub-saga input:
  ```
  legal_structure_iid = from step 3
  deployer_account_iid, deployer_slot_address = from step 3
  admin_partner_slot_address = deployer eth address
  authz_admin_slot_address = deployer eth address (same partner)
  exec_runtime_name, locale = from input
  (facet versions from lattice defaults or input)
  ```
- [ ] 4.5.2 SpawnAndWait for `deploy_treasury_legal_mechanisms_for_legal_structure`
- [ ] 4.5.3 Extract outputs: `rac_mechanism_iid`, `rac_diamond_slot_address`, `treasury_mechanism_iid`, `trezor_diamond_slot_address`
- [ ] 4.5.4 Return outputs + `sub_saga_instance_id`
- [ ] 4.5.5 COMP: Sub-saga handles its own compensation

#### Step 6: spawn_deploy_cash_tokens_saga
**File**: `spawn_deploy_cash_tokens.go`

- [ ] 4.6.1 Parse currencies array from input
- [ ] 4.6.2 If currencies empty: return success immediately (no tokens)
- [ ] 4.6.3 For each currency:
  - Build sub-saga input:
    ```
    currency_code = currency
    legal_structure_iid = from step 3
    initial_amount = from initial_amounts map (default "0")
    exec_runtime_name = from input
    deployer_account_iid, deployer_slot_address = from step 3
    admin_partner_slot_address = deployer eth address
    authz_admin_slot_address = deployer eth address
    clearing_account_slot_address = from step 3
    ```
  - SpawnAndWait for `deploy_cash_token_legal_mechanism_for_legal_structure`
  - Collect outputs
- [ ] 4.6.4 Return aggregated outputs: `cash_token_mechanism_iids`, `cash_token_contract_addresses`, `cash_token_iids` (all as JSON maps)
- [ ] 4.6.5 COMP: Sub-sagas handle their own compensation

#### Step 7: create_legal_participant_api_key
**File**: `create_legal_participant_api_key.go`

- [ ] 4.7.1 Generate 32-char random ID
- [ ] 4.7.2 Generate 32-byte secure random key, format as `agora_live_{base64}`
- [ ] 4.7.3 Hash key with SHA-256 for storage
- [ ] 4.7.4 Create ParticipantAPIKey record via apiKeyStore.Create()
- [ ] 4.7.5 Return `api_key_id`, `api_key_plain` (ONE-TIME in saga output)
- [ ] 4.7.6 COMP: Delete API key record via apiKeyStore.Disable()

#### Executor Registration
**File**: `saga.go`

- [ ] 4.8.1 Create `RunExecutorsAsync()` function for all 7 steps
- [ ] 4.8.2 Create `UpdateStores()` for test injection

**File**: `pkg/daemons/accmgr/trax/executors/run.go`

- [ ] 4.8.3 Add call to new saga's `RunExecutorsAsync()`

---

### Phase 5: IndTrxSS Tests (Individual Step Tests)

**File**: `tests/e2e/laser/indtrxss_saga_snlp_common_test.go` (NEW)

- [ ] 5.1.1 Create `SetupNewLegalParticipantSagaInput` test struct
- [ ] 5.1.2 Create `defaultSNLPSagaInput()` helper
- [ ] 5.1.3 Create step execution helpers

**File**: `tests/e2e/laser/indtrxss_saga_snlp_accmgr_s1_create_legal_participant_test.go` (NEW)

- [ ] 5.2.1 `TestIndTrxSS_SNLP_S1_CreateLegalParticipant_Green` - valid input
- [ ] 5.2.2 `TestIndTrxSS_SNLP_S1_CreateLegalParticipant_GeneratedIid` - IID auto-generated
- [ ] 5.2.3 `TestIndTrxSS_SNLP_S1_CreateLegalParticipant_MissingDisplayNames` - red path
- [ ] 5.2.4 `TestIndTrxSS_SNLP_S1_CreateLegalParticipant_MissingTypes` - red path
- [ ] 5.2.5 `TestIndTrxSS_SNLP_S1_CreateLegalParticipant_DuplicateIid` - red path

**File**: `tests/e2e/laser/indtrxss_saga_snlp_accmgr_s2_partners_test.go` (NEW)

- [ ] 5.3.1 `TestIndTrxSS_SNLP_S2_Partners_AllNew` - create all partners
- [ ] 5.3.2 `TestIndTrxSS_SNLP_S2_Partners_AllExisting` - reference existing
- [ ] 5.3.3 `TestIndTrxSS_SNLP_S2_Partners_Mixed` - some new, some existing
- [ ] 5.3.4 `TestIndTrxSS_SNLP_S2_Partners_DeployerValidation` - deployer in list
- [ ] 5.3.5 `TestIndTrxSS_SNLP_S2_Partners_EmptyList` - red path
- [ ] 5.3.6 `TestIndTrxSS_SNLP_S2_Partners_ExistingNotFound` - red path
- [ ] 5.3.7 `TestIndTrxSS_SNLP_S2_Partners_DeployerNotInList` - red path

**File**: `tests/e2e/laser/indtrxss_saga_snlp_accmgr_s3_spawn_legal_struct_test.go` (NEW)

- [ ] 5.4.1 `TestIndTrxSS_SNLP_S3_SpawnLegalStruct_Green` - sub-saga completes
- [ ] 5.4.2 `TestIndTrxSS_SNLP_S3_SpawnLegalStruct_OutputExtraction` - verify all outputs
- [ ] 5.4.3 `TestIndTrxSS_SNLP_S3_SpawnLegalStruct_SubSagaFails` - red path (mock failure)

**Files for Steps 4-6**: Similar pattern for core/treasury/cash token spawns

**File**: `tests/e2e/laser/indtrxss_saga_snlp_accmgr_s7_apikey_test.go` (NEW)

- [ ] 5.7.1 `TestIndTrxSS_SNLP_S7_ApiKey_Green` - key created
- [ ] 5.7.2 `TestIndTrxSS_SNLP_S7_ApiKey_CustomRateLimit` - rate limit set
- [ ] 5.7.3 `TestIndTrxSS_SNLP_S7_ApiKey_InvalidParticipant` - red path

---

### Phase 6: Full Saga E2E Tests

**File**: `tests/e2e/laser/setup_new_legal_participant_test.go` (NEW)

#### Green Path Tests

- [ ] 6.1.1 `TestSetupNewLegalParticipant_FullFlow`
  - Submit saga with 2 partners (1 new, 1 existing), 2 currencies
  - Verify Legal Participant created
  - Verify partners created/validated
  - Verify Legal Structure established
  - Verify Core mechanisms deployed
  - Verify Treasury mechanisms deployed
  - Verify USD and EUR cash tokens deployed
  - Verify API key created and usable

- [ ] 6.1.2 `TestSetupNewLegalParticipant_EmptyCurrencies`
  - Submit saga with no currencies
  - Verify saga completes successfully
  - Verify no cash tokens created

- [ ] 6.1.3 `TestSetupNewLegalParticipant_AllExistingPartners`
  - Pre-create partner participants
  - Submit saga referencing existing partners
  - Verify partners not duplicated

- [ ] 6.1.4 `TestSetupNewLegalParticipant_GeneratedIids`
  - Submit saga without legal_participant_iid and partner iids
  - Verify IIDs generated correctly

#### Red Path Tests

- [ ] 6.2.1 `TestSetupNewLegalParticipant_DuplicateLegalParticipantIid` - fails at step 1
- [ ] 6.2.2 `TestSetupNewLegalParticipant_NoPartners` - fails at step 2
- [ ] 6.2.3 `TestSetupNewLegalParticipant_DeployerNotPartner` - fails at step 2
- [ ] 6.2.4 `TestSetupNewLegalParticipant_NonExistentPartner` - fails at step 2

---

### Phase 7: API Key Authentication Tests

**File**: `tests/e2e/laser/legal_participant_apikey_auth_test.go` (NEW)

- [ ] 7.1.1 `TestLegalParticipantApiKey_RESTAuthentication` - use key for REST call
- [ ] 7.1.2 `TestLegalParticipantApiKey_InvalidKey` - 401 Unauthorized
- [ ] 7.1.3 `TestLegalParticipantApiKey_RateLimiting` - rate limited after threshold
- [ ] 7.1.4 `TestLegalParticipantApiKey_DisabledKey` - disabled key rejected

---

### Phase 8: Documentation

**File**: `docs/SUMMARY-FOR-AGENT.md`

- [ ] 8.1.1 Add section on setup_new_legal_participant saga
- [ ] 8.1.2 Document sub-saga spawning pattern
- [ ] 8.1.3 Document saga hierarchy: SNLP -> LS -> CLM -> TLM -> CASHTK

---

## Data Flow Diagram

```
[Saga Submit: setup_new_legal_participant]
    |
    v
[Step 1: create_legal_participant_record] (ACCMGR)
    |-- CREATE: Participant (types=LEGAL_ENTITY + input types)
    |-- OUTPUT: legal_participant_iid
    v
[Step 2: create_or_validate_partner_participants] (ACCMGR)
    |-- CREATE or VALIDATE: Partner participants
    |-- OUTPUT: partner_participant_iids, deployer_participant_iid
    v
[Step 3: spawn_establish_legal_structure_saga] (ACCMGR)
    |-- SUBMIT: establish_new_legal_structure_for_participant
    |-- POLL: Wait for COMMITTED (up to 10 min)
    |-- OUTPUT: legal_structure_iid, accounts, eth_addresses
    v
[Step 4: spawn_deploy_core_mechanisms_saga] (ACCMGR)
    |-- SUBMIT: deploy_core_legal_mechanisms_for_legal_structure
    |-- POLL: Wait for COMMITTED
    |-- OUTPUT: task_manager_*, authz_diamond_*
    v
[Step 5: spawn_deploy_treasury_mechanisms_saga] (ACCMGR)
    |-- SUBMIT: deploy_treasury_legal_mechanisms_for_legal_structure
    |-- POLL: Wait for COMMITTED
    |-- OUTPUT: rac_*, trezor_*
    v
[Step 6: spawn_deploy_cash_tokens_saga] (ACCMGR)
    |-- IF currencies empty: SUCCESS (no tokens)
    |-- FOR EACH currency:
    |     |-- SUBMIT: deploy_cash_token_legal_mechanism_for_legal_structure
    |     |-- POLL: Wait for COMMITTED
    |-- OUTPUT: cash_token_mechanism_iids, cash_token_contract_addresses
    v
[Step 7: create_legal_participant_api_key] (ACCMGR)
    |-- GENERATE: Secure random key (agora_live_{base64})
    |-- CREATE: ParticipantAPIKey (hash stored)
    |-- OUTPUT: api_key_id, api_key_plain (ONE-TIME)
    v
[SAGA COMMITTED]
```

---

## Files Summary

### New Files

| File | Description |
|------|-------------|
| `pkg/trax/sub_saga_executor.go` | Reusable sub-saga spawning infrastructure |
| `pkg/trax/templates/agora/csd/setup_new_legal_participant.go` | Saga template (7 steps) |
| `pkg/daemons/accmgr/api/v1/participants_post_setup_legal.go` | REST endpoint |
| `pkg/daemons/accmgr/trax/executors/setup_new_legal_participant/saga.go` | Executor registration |
| `pkg/daemons/accmgr/trax/executors/setup_new_legal_participant/create_legal_participant.go` | Step 1 |
| `pkg/daemons/accmgr/trax/executors/setup_new_legal_participant/create_or_validate_partners.go` | Step 2 |
| `pkg/daemons/accmgr/trax/executors/setup_new_legal_participant/spawn_establish_legal_struct.go` | Step 3 |
| `pkg/daemons/accmgr/trax/executors/setup_new_legal_participant/spawn_deploy_core.go` | Step 4 |
| `pkg/daemons/accmgr/trax/executors/setup_new_legal_participant/spawn_deploy_treasury.go` | Step 5 |
| `pkg/daemons/accmgr/trax/executors/setup_new_legal_participant/spawn_deploy_cash_tokens.go` | Step 6 |
| `pkg/daemons/accmgr/trax/executors/setup_new_legal_participant/create_legal_participant_api_key.go` | Step 7 |
| `tests/e2e/laser/indtrxss_saga_snlp_common_test.go` | IndTrxSS test infrastructure |
| `tests/e2e/laser/indtrxss_saga_snlp_accmgr_s1_create_legal_participant_test.go` | Step 1 tests |
| `tests/e2e/laser/indtrxss_saga_snlp_accmgr_s2_partners_test.go` | Step 2 tests |
| `tests/e2e/laser/indtrxss_saga_snlp_accmgr_s3_spawn_legal_struct_test.go` | Step 3 tests |
| `tests/e2e/laser/indtrxss_saga_snlp_accmgr_s4_spawn_core_test.go` | Step 4 tests |
| `tests/e2e/laser/indtrxss_saga_snlp_accmgr_s5_spawn_treasury_test.go` | Step 5 tests |
| `tests/e2e/laser/indtrxss_saga_snlp_accmgr_s6_spawn_cashtokens_test.go` | Step 6 tests |
| `tests/e2e/laser/indtrxss_saga_snlp_accmgr_s7_apikey_test.go` | Step 7 tests |
| `tests/e2e/laser/setup_new_legal_participant_test.go` | Full saga E2E tests |
| `tests/e2e/laser/legal_participant_apikey_auth_test.go` | API key auth tests |

### Modified Files

| File | Changes |
|------|---------|
| `pkg/trax/templates/agora/csd/index.go` | Register new saga template |
| `pkg/daemons/accmgr/trax/executors/run.go` | Register ACCMGR executors |
| `pkg/daemons/accmgr/api/v1/api.go` | Add route for POST /participants/setup-legal |
| `docs/SUMMARY-FOR-AGENT.md` | Document saga and sub-saga pattern |

---

## Critical Reference Files

| File | Reason |
|------|--------|
| `pkg/trax/templates/agora/csd/establish_new_legal_structure_for_participant.go` | Saga template structure pattern |
| `pkg/trax/submitter.go` | SagaSubmitter interface for sub-saga spawning |
| `pkg/daemons/accmgr/trax/executors/establish_new_legal_structure_for_participant/verify_inputs.go` | IdempotentService pattern |
| `pkg/auth/types.go` | ParticipantAPIKey structure |
| `pkg/daemons/accmgr/api/v1/apikeys_post_create.go` | API key generation pattern |
| `tests/e2e/laser/indtrxss_common_test.go` | IndTrxSS test infrastructure |

---

## Implementation Order

1. **Phase 1**: Sub-Saga Executor Infrastructure (foundation for steps 3-6)
2. **Phase 2**: Saga Template (7 steps)
3. **Phase 3**: API Endpoint
4. **Phase 4**: ACCMGR Step Executors (steps 1-7)
5. **Phase 5**: IndTrxSS Tests (one per step)
6. **Phase 6**: Full Saga E2E Tests
7. **Phase 7**: API Key Authentication Tests
8. **Phase 8**: Documentation

---

## Success Criteria

- [ ] Sub-saga executor infrastructure works (spawn + poll + extract outputs)
- [ ] Saga template registered correctly (verify via traxcli)
- [ ] All 7 step executors start without errors
- [ ] IndTrxSS tests pass for each step (green + red paths)
- [ ] Full saga E2E tests pass (EthBC mode)
- [ ] Empty currencies flow completes successfully (no tokens)
- [ ] Partner creation AND validation modes work
- [ ] API key created and usable for REST authentication
- [ ] Compensation works correctly (rollback on failure)
- [ ] Documentation updated

---

## Notes

- **First Sub-Saga Implementation**: This saga introduces nested saga spawning - the SubSagaExecutor pattern should be reusable for future sagas
- **EthBC-only**: Mechanism deployments only work with real Ethereum blockchain
- **Hybrid Architecture**: Direct DB for participants, sub-sagas for complex mechanisms
- **Idempotency**: Sub-saga submission uses composite key `parent_key:sub_saga_type` for retry safety
- **Compensation Cascade**: Parent saga compensates in reverse; each sub-saga handles its own internal compensation
- **API Key Security**: Plaintext key only returned once in saga output - hash stored in DB
- **Partner Flexibility**: Supports creating new OR referencing existing participants with any type