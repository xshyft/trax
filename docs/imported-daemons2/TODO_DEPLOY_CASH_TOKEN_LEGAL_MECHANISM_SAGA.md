# TODO: Deploy Cash Token Legal Mechanism for Legal Structure - TRAX Saga Implementation

> **Status**: NOT STARTED
> **Created**: 2026-01-05
> **Dependency**: Requires `TODO_CLEARING_ACCOUNT_FOR_LEGAL_STRUCTURE.md` to be implemented first
> **Parent Reference**: `deploy_treasury_legal_mechanisms_for_legal_structure` saga
>
> ## ⚠️ BLOCKING PREREQUISITES (Must be implemented first)
>
> Before this saga can be implemented, the following infrastructure changes are required:
>
> | # | Prerequisite | Status | Description |
> |---|--------------|--------|-------------|
> | 1 | **EthBCErc20FacetContract** | ✅ DONE | New handler for Erc20Facet operations via Diamond in EthBC mode |
> | 2 | **Erc20Initialize LASER operation** | ✅ DONE | Add `OperationNameEnum_Erc20Initialize` and handler |
> | 3 | **ERC20 approve for Diamond+Erc20Facet** | ✅ DONE | Route ERC20 operations via Diamond contract handler in EthBC |
> | 4 | **Clearing Account SIGNER slots** | ✅ DONE | Change clearing account from non-signer to SIGNER, update tests |

---

## Overview

TRAX saga template `deploy_cash_token_legal_mechanism_for_legal_structure` that deploys a Cash Token Legal Mechanism (ERC20 token representing a specific currency) for an existing legal structure that already has Core Legal Mechanisms and Treasury mechanisms deployed.

**Key Concepts**:
- **Cash Token**: ERC20 token representing fiat currency (e.g., USD, EUR) with CFI code `MMCXXX`
- **Clearing Account**: **SIGNER** account owned by the legal structure, used as initial token holder (must sign ERC20 approve)
- **Treasury Integration**: Tokens are deposited to Treasury vault for the Clearing Account

---

## Prerequisites (MUST be validated in Step 1)

1. **Legal Structure exists** - must be PARTNERSHIP type
2. **Core Legal Mechanisms deployed** on the specified Execution Runtime:
   - TaskManagerV2 contract deployed and initialized (VOTING mechanism)
   - AuthzDiamond contract deployed and initialized (AUTHORISATION_SOURCE mechanism)
3. **Treasury mechanism deployed** on the specified Execution Runtime:
   - RAC Diamond deployed (RESOURCE_ACCESS_CONTROLLER mechanism)
   - Trezor Diamond deployed (TREASURY mechanism) with DEFAULT ledger (id=1)
4. **No prior CASH_TOKEN mechanism** for this currency_code on this exec_runtime_name
5. **Clearing Account exists** - LegalStructureToAccountRelation with type CLEARING_ACCOUNT
6. **Clearing Account has SIGNER LASER slots** on the specified exec_runtime (required for ERC20 approve)

---

## Saga Specification

### Inputs

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| currency_code | string | Yes | ISO 4217 currency code, uppercase (e.g., "USD", "EUR") |
| legal_structure_iid | string | Yes | IID of the parent legal structure |
| initial_amount | string | Yes | Initial token supply in cents (2 decimal places as integer, e.g., "100000" for 1000.00) |
| exec_runtime_name | string | Yes | Execution runtime for deployments (e.g., "primary") |
| deployer_account_iid | string | Yes | Account IID with SIGNER slot for contract deployment |
| deployer_slot_address | string | Yes | LASER slot address for contract deployments |
| admin_partner_slot_address | string | Yes | LASER slot address of admin partner (for permission grants) |
| authz_admin_slot_address | string | Yes | LASER slot address of AuthzDiamond admin |
| locale | string | Yes | Locale for display names (e.g., "en-US") |
| erc20_facet_version | string | Yes | Version of ERC20 facet from lattice |

### Validation Rules (Step 1)

1. `currency_code`: Required, uppercase, 3 characters (ISO 4217)
2. `legal_structure_iid`: Must reference existing PARTNERSHIP legal structure
3. `initial_amount`: Must be positive integer (representing cents)
4. Core Legal Mechanisms must exist (VOTING + AUTHORISATION_SOURCE)
5. Treasury mechanism must exist with deployment for exec_runtime_name
6. No existing CASH_TOKEN mechanism for this currency_code + exec_runtime
7. Clearing Account must exist via LegalStructureToAccountRelation
8. `deployer_account_iid` must have active SIGNER-tagged slot

---

## Saga Steps (14 steps)

| Step | Name | Service | Description |
|------|------|---------|-------------|
| 1 | `verify_cash_token_mechanism_inputs` | **accmgr** | Validate all prerequisites |
| 2 | `create_cash_token_legal_mechanism` | **accmgr** | Create LegalMechanism record (type=CASH_TOKEN) |
| 3 | `deploy_cash_token_erc20_contract` | **lasersvc** | Deploy ERC20 Diamond via LASER |
| 4 | `initialize_cash_token_erc20_diamond` | **lasersvc** | Initialize Diamond with admin |
| 5 | `grant_add_facets_permission_for_cash_token` | **lasersvc** | authz-admin grants addFacets to admin-partner |
| 6 | `add_erc20_facet_to_cash_token_diamond` | **lasersvc** | admin-partner adds ERC20 facet |
| 7 | `initialize_erc20_facet_for_cash_token` | **lasersvc** | Initialize ERC20 (name, symbol, decimals, mint to Clearing Account) |
| 8 | `create_cash_token_deployment_record` | **accmgr** | Create LegalMechanismDeployment record |
| 9 | `grant_erc20_approval_to_treasury` | **lasersvc** | Clearing Account approves Treasury for spending |
| 10 | `deposit_cash_token_to_treasury` | **lasersvc** | Deposit tokens to Treasury vault for Clearing Account |
| 11 | `verify_cash_token_balances` | **lasersvc** | Verify balances (4 checks) |
| 12 | `create_instrument_for_cash_token` | **instrmgr** | Create Instrument record (CFI=MMCXXX) |
| 13 | `create_authorized_instrument_for_cash_token` | **instrmgr** | Create AuthorizedInstrument record |
| 14 | `create_cash_token_record` | **instrmgr** | Create CashToken record |

**Service Distribution**:
- **accmgr**: Steps 1, 2, 8 (validation and legal mechanism records)
- **lasersvc**: Steps 3, 4, 5, 6, 7, 9, 10, 11 (LASER contract operations)
- **instrmgr**: Steps 12, 13, 14 (instrument and cash token records)

---

## Implementation Phases

### Phase 1: Domain Model Updates

**File**: `pkg/fin/legal_mechanism.go`

- [ ] 1.1.1 Add new constant:
  ```go
  LegalMechanismTypeEnum_CashToken LegalMechanismTypeEnum = "LEGAL_MECHANISM_TYPE_ENUM_CASH_TOKEN"
  ```

---

### Phase 2: Saga Template

**File**: `pkg/trax/templates/agora/csd/deploy_cash_token_legal_mechanism_for_legal_structure.go` (NEW)

- [ ] 2.1.1 Define `SagaTemplate` with TemplateId: `deploy_cash_token_legal_mechanism_for_legal_structure`
- [ ] 2.1.2 Define 14 `SagaStepTemplate` records with proper ordering and service labels
- [ ] 2.1.3 Create `CreateDeployCashTokenLegalMechanismForLegalStructureSagaTemplates()` function

**File**: `pkg/trax/templates/agora/csd/index.go`

- [ ] 2.2.1 Add call to new template creation function

---

### Phase 3: API Endpoint

**File**: `pkg/daemons/accmgr/api/v1/legal_mechanisms_post_deploy_cash_token.go` (NEW)

- [ ] 3.1.1 Create `deployCashTokenLegalMechanismRequest` struct
- [ ] 3.1.2 Create `deployCashTokenLegalMechanismResponse` struct
- [ ] 3.1.3 Implement `postDeployCashTokenLegalMechanism(c *gin.Context)` handler
- [ ] 3.1.4 Validate required fields
- [ ] 3.1.5 Submit saga via `traxSagaSubmitter.SubmitSaga()`

**File**: `pkg/daemons/accmgr/api/v1/api.go`

- [ ] 3.2.1 Add route: `POST /legal-mechanisms/deploy-cash-token` -> `postDeployCashTokenLegalMechanism`

---

### Phase 4: ACCMGR Executors

**Directory**: `pkg/daemons/accmgr/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/` (NEW)

#### Step 1: verify_cash_token_mechanism_inputs
**File**: `verify_inputs.go`

- [ ] 4.1.1 Validate all required inputs exist
- [ ] 4.1.2 Verify currency_code format (uppercase, 3 chars, ISO 4217)
- [ ] 4.1.3 Verify legal_structure_iid exists and is PARTNERSHIP type
- [ ] 4.1.4 Query existing LegalMechanisms for this Legal Structure
- [ ] 4.1.5 Verify Core mechanisms exist (VOTING + AUTHORISATION_SOURCE types)
- [ ] 4.1.6 Verify Treasury mechanism exists with deployment for exec_runtime_name
- [ ] 4.1.7 Verify no CASH_TOKEN mechanism exists for this currency_code (check metadata)
- [ ] 4.1.8 Query LegalStructureToAccountRelation for CLEARING_ACCOUNT type
- [ ] 4.1.9 Verify Clearing Account has SIGNER-tagged LASER slots on exec_runtime
- [ ] 4.1.10 Verify deployer_account_iid has SIGNER slot
- [ ] 4.1.11 Return: `prefix`, `treasury_diamond_slot_address`, `clearing_account_iid`, `clearing_account_slot_address`
- [ ] 4.1.12 COMP: No-op

#### Step 2: create_cash_token_legal_mechanism
**File**: `create_cash_token_mechanism.go`

- [ ] 4.2.1 Generate IID for LegalMechanism
- [ ] 4.2.2 Build slot_address: `{prefix}-CashToken-{currency_code}`
- [ ] 4.2.3 Create LegalMechanism with Type=CASH_TOKEN, LegalStructureIid
- [ ] 4.2.4 Store in metadata: `currency_code`, `slot_address`, `clearing_account_iid`
- [ ] 4.2.5 Return `cash_token_mechanism_iid`, `cash_token_slot_address`
- [ ] 4.2.6 COMP: Delete LegalMechanism record

#### Step 8: create_cash_token_deployment_record
**File**: `create_cash_token_deployment.go`

- [ ] 4.3.1 Get `erc20_contract_address` from step 3
- [ ] 4.3.2 Create LegalMechanismDeployment with Type=LASER
- [ ] 4.3.3 Set DeploymentDetails with exec_runtime_name, slot_address, contract_address
- [ ] 4.3.4 Return `cash_token_deployment_iid`
- [ ] 4.3.5 COMP: Delete deployment record

#### Executor Registration
**File**: `saga.go`

- [ ] 4.4.1 Create `RunExecutorsAsync()` function for steps 1, 2, 8

**File**: `pkg/daemons/accmgr/trax/executors/run.go`

- [ ] 4.4.2 Add call to new saga's `RunExecutorsAsync()`

---

### Phase 5: LASERSVC Executors

**Directory**: `pkg/daemons/lasersvc/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/` (NEW)

#### Step 3: deploy_cash_token_erc20_contract
**File**: `deploy_erc20_contract.go`

- [ ] 5.1.1 Execute LASER mutation DEPLOY_DIAMOND
- [ ] 5.1.2 Contract name = `{prefix}-CashToken-{currency_code}`
- [ ] 5.1.3 Return `erc20_contract_address`, `deploy_tx_hash`
- [ ] 5.1.4 COMP: No-op (immutable)

#### Step 4: initialize_cash_token_erc20_diamond
**File**: `initialize_diamond.go`

- [ ] 5.2.1 Execute LASER mutation INITIALIZE_DIAMOND
- [ ] 5.2.2 Admin = admin_partner_slot_address
- [ ] 5.2.3 Return `init_tx_hash`
- [ ] 5.2.4 COMP: No-op

#### Step 5: grant_add_facets_permission_for_cash_token
**File**: `grant_add_facets_permission.go`

- [ ] 5.3.1 Signer = authz_admin_slot_address
- [ ] 5.3.2 Grant addFacets(address[]) permission to admin_partner on cash token diamond
- [ ] 5.3.3 Return `grant_add_facets_tx_hash`
- [ ] 5.3.4 COMP: No-op

#### Step 6: add_erc20_facet_to_cash_token_diamond
**File**: `add_erc20_facet.go`

- [ ] 5.4.1 Signer = admin_partner_slot_address
- [ ] 5.4.2 Get ERC20 facet address from lattice (using erc20_facet_version)
- [ ] 5.4.3 Execute DIAMOND_ADD_FACETS with ERC20 facet
- [ ] 5.4.4 Return `add_erc20_facet_tx_hash`
- [ ] 5.4.5 COMP: No-op

#### Step 7: initialize_erc20_facet_for_cash_token
**File**: `initialize_erc20_facet.go`

- [ ] 5.5.1 Execute LASER mutation for ERC20 initialization
- [ ] 5.5.2 Parameters:
  - name: "{currency_code} Cash Token" (e.g., "USD Cash Token")
  - symbol: currency_code (e.g., "USD")
  - decimals: 2 (for cents)
  - initial_supply: initial_amount
  - initial_holder: clearing_account_slot_address
- [ ] 5.5.3 Return `init_erc20_tx_hash`, `total_supply`
- [ ] 5.5.4 COMP: No-op

#### Step 9: grant_erc20_approval_to_treasury
**File**: `grant_erc20_approval.go`

- [ ] 5.6.1 Signer = clearing_account_slot_address (Clearing Account signs)
- [ ] 5.6.2 Execute LASER mutation ERC20_APPROVE
- [ ] 5.6.3 Parameters: spender=treasury_diamond_slot_address, amount=max uint256
- [ ] 5.6.4 Return `approval_tx_hash`
- [ ] 5.6.5 COMP: No-op

#### Step 10: deposit_cash_token_to_treasury
**File**: `deposit_to_treasury.go`

- [ ] 5.7.1 Execute LASER mutation TREZOR_ERC20_DEPOSIT_TO_VAULT
- [ ] 5.7.2 Parameters:
  - ledger_id: 1 (DEFAULT ledger)
  - caller: clearing_account_slot_address
  - erc20_addr: erc20_contract_address
  - from_account: clearing_account_slot_address
  - to_vault: clearing_account_slot_address (Clearing Account's vault)
  - amount: initial_amount
- [ ] 5.7.3 Use async mutation with polling (like existing deposit step)
- [ ] 5.7.4 Return `deposit_tx_hash`, `vault_addr`
- [ ] 5.7.5 COMP: No-op (cannot reverse on-chain deposit)

#### Step 11: verify_cash_token_balances
**File**: `verify_balances.go`

- [ ] 5.8.1 Query ERC20 balance of Clearing Account - verify = 0
- [ ] 5.8.2 Query ERC20 balance of Treasury - verify = initial_amount
- [ ] 5.8.3 Query Vault balance (LIQUID stash 0) - verify = initial_amount
- [ ] 5.8.4 Query Vault balance (TOTAL stash 1) - verify = initial_amount
- [ ] 5.8.5 Return all balances and `verification_status: "success"`
- [ ] 5.8.6 COMP: No-op

#### Executor Registration
**File**: `saga.go`

- [ ] 5.9.1 Create `RunExecutorsAsync()` function for steps 3-7, 9-11

**File**: `pkg/daemons/lasersvc/trax/executors/run.go`

- [ ] 5.9.2 Add call to new saga's `RunExecutorsAsync()`

---

### Phase 6: INSTRMGR Executors

**Directory**: `pkg/daemons/instrmgr/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/` (NEW)

#### Step 12: create_instrument_for_cash_token
**File**: `create_instrument.go`

- [ ] 6.1.1 Generate IID for Instrument
- [ ] 6.1.2 Create Instrument record:
  - CFICode: "MMCXXX" (cash token CFI code)
  - Classes: [DigitalToken]
  - DisplayNames: {locale: "{currency_code} Cash Token"}
  - Labels: {"currency_code": currency_code, "type": "cash_token"}
  - Tags: ["cash-token", currency_code, "erc20"]
  - Metadata: {"legal_structure_iid", "exec_runtime_name"}
- [ ] 6.1.3 Return `instrument_iid`
- [ ] 6.1.4 COMP: Delete Instrument record

#### Step 13: create_authorized_instrument_for_cash_token
**File**: `create_authorized_instrument.go`

- [ ] 6.2.1 Generate IID for AuthorizedInstrument
- [ ] 6.2.2 Create AuthorizedInstrument record:
  - InstrumentIid: instrument_iid
  - AuthzCurrency: currency_code
  - AuthzInitialUnits: initial_amount
  - AuthzDivisibility: "2" (2 decimal places)
  - AuthzUnitsReceiverAccountIid: clearing_account_iid
  - Metadata: {"contract_address", "legal_structure_iid", "legal_mechanism_iid"}
- [ ] 6.2.3 Return `authorized_instrument_iid`
- [ ] 6.2.4 COMP: Delete AuthorizedInstrument record

#### Step 14: create_cash_token_record
**File**: `create_cash_token.go`

- [ ] 6.3.1 Use SAME IID as authorized_instrument_iid (following existing pattern)
- [ ] 6.3.2 Create CashToken record:
  - Iid: authorized_instrument_iid
  - Identifiers: [{FinEntityType: CashToken, Scheme: "TICKER", Ids: [currency_code], IsPrimary: true}]
  - DisplayNames: {locale: "{currency_code} Cash Token"}
  - Labels: {"currency_code", "status": "active"}
  - Metadata: {"legal_mechanism_iid", "contract_address"}
- [ ] 6.3.3 Return `cash_token_iid`
- [ ] 6.3.4 COMP: Delete CashToken record

#### Executor Registration
**File**: `saga.go`

- [ ] 6.4.1 Create `RunExecutorsAsync()` function for steps 12, 13, 14

**File**: `pkg/daemons/instrmgr/trax/executors/run.go`

- [ ] 6.4.2 Add call to new saga's `RunExecutorsAsync()` (may need to create this file if not exists)

---

### Phase 7: E2E Tests

**File**: `tests/e2e/laser/cash_token_mechanism_deployment_test.go` (NEW)

#### Test Setup Functions

- [ ] 7.1.1 `setupTestDatabaseForCashTokenMechanism(t)` - setup with Diamond + Treasury prereqs
- [ ] 7.1.2 `deployPrerequisiteMechanisms(t, legalStructureIid)` - deploy Core + Treasury mechanisms
- [ ] 7.1.3 `verifyClearingAccountExists(t, legalStructureIid)` - verify clearing account setup

#### Green Path Tests

- [ ] 7.2.1 `TestDeployCashTokenLegalMechanism_FullFlow`
  - Setup: Create legal structure with clearing account
  - Deploy Core + Treasury mechanisms first
  - Submit Cash Token saga with valid inputs (currency_code="USD", initial_amount="100000")
  - Verify saga completes successfully
  - Verify LegalMechanism record created (type=CASH_TOKEN)
  - Verify LegalMechanismDeployment record with correct contract address
  - Verify Instrument, AuthorizedInstrument, CashToken records created
  - Verify CFI code = "MMCXXX"

- [ ] 7.2.2 `TestDeployCashTokenLegalMechanism_MultipleCurrencies`
  - Deploy USD cash token first
  - Deploy EUR cash token second
  - Verify both mechanisms exist
  - Verify separate contracts deployed

- [ ] 7.2.3 `TestDeployCashTokenLegalMechanism_VerifyBalances`
  - Deploy cash token
  - Use LASER queries to verify:
    - Clearing Account ERC20 balance = 0
    - Treasury ERC20 balance = initial_amount
    - Vault LIQUID balance = initial_amount
    - Vault TOTAL balance = initial_amount

#### Red Path Tests

- [ ] 7.3.1 `TestDeployCashTokenLegalMechanism_MissingCoreMechanisms`
  - Create legal structure WITHOUT deploying Core mechanisms
  - Submit Cash Token saga
  - Verify saga fails at step 1 (Core mechanisms not found)

- [ ] 7.3.2 `TestDeployCashTokenLegalMechanism_MissingTreasuryMechanism`
  - Deploy Core mechanisms but NOT Treasury
  - Submit Cash Token saga
  - Verify saga fails at step 1 (Treasury not found)

- [ ] 7.3.3 `TestDeployCashTokenLegalMechanism_DuplicateCurrency`
  - Deploy USD cash token successfully
  - Attempt second USD cash token deployment
  - Verify saga fails at step 1 (CASH_TOKEN for USD already exists)

- [ ] 7.3.4 `TestDeployCashTokenLegalMechanism_MissingClearingAccount`
  - Create legal structure WITHOUT clearing account
  - Deploy Core + Treasury mechanisms
  - Submit Cash Token saga
  - Verify saga fails at step 1 (Clearing Account not found)

- [ ] 7.3.5 `TestDeployCashTokenLegalMechanism_InvalidCurrencyCode`
  - Submit with lowercase currency code "usd"
  - Verify saga fails at step 1 (invalid currency format)

- [ ] 7.3.6 `TestDeployCashTokenLegalMechanism_ZeroInitialAmount`
  - Submit with initial_amount = "0"
  - Verify saga fails at step 1 (initial_amount must be positive)

---

### Phase 8: Documentation Updates

**File**: `docs/SUMMARY-FOR-AGENT.md`

- [ ] 8.1.1 Add section on Cash Token Legal Mechanism deployment saga
- [ ] 8.1.2 Document saga inputs/outputs
- [ ] 8.1.3 Document relationship: Core -> Treasury -> Cash Token
- [ ] 8.1.4 Document currency_code uniqueness constraint

---

## Progress Tracking

| Phase | Status | Progress | Notes |
|-------|--------|----------|-------|
| Phase 1: Domain Model | NOT STARTED | 0/1 (0%) | Add CASH_TOKEN enum |
| Phase 2: Saga Template | NOT STARTED | 0/4 (0%) | 14-step template |
| Phase 3: API Endpoint | NOT STARTED | 0/6 (0%) | POST deploy-cash-token |
| Phase 4: ACCMGR Executors | NOT STARTED | 0/16 (0%) | Steps 1, 2, 8 |
| Phase 5: LASERSVC Executors | NOT STARTED | 0/28 (0%) | Steps 3-7, 9-11 |
| Phase 6: INSTRMGR Executors | NOT STARTED | 0/10 (0%) | Steps 12-14 |
| Phase 7: E2E Tests | NOT STARTED | 0/12 (0%) | Green + Red paths |
| Phase 8: Documentation | NOT STARTED | 0/5 (0%) | Update docs |

---

## Data Flow Diagram

```
[Prerequisites: Core + Treasury Legal Mechanisms Deployed + Clearing Account Exists]
    |
    v
[Saga Submit: deploy_cash_token_legal_mechanism_for_legal_structure]
    |
    v
[Step 1: verify_cash_token_mechanism_inputs] (ACCMGR)
    |-- VALIDATE: Core + Treasury mechanisms exist
    |-- VALIDATE: No CASH_TOKEN mechanism for this currency
    |-- VALIDATE: Clearing Account exists with LASER slots
    |-- OUTPUT: prefix, treasury_diamond_slot_address, clearing_account_slot_address
    v
[Step 2: create_cash_token_legal_mechanism] (ACCMGR)
    |-- CREATE: LegalMechanism (CASH_TOKEN), slot_address = {prefix}-CashToken-{currency}
    v
[Step 3: deploy_cash_token_erc20_contract] (LASERSVC)
    |-- LASER: DEPLOY_DIAMOND (deployer signs)
    |-- OUTPUT: erc20_contract_address
    v
[Step 4: initialize_cash_token_erc20_diamond] (LASERSVC)
    |-- LASER: INITIALIZE_DIAMOND (admin-partner)
    v
[Step 5: grant_add_facets_permission_for_cash_token] (LASERSVC)
    |-- LASER: authz-admin grants addFacets to admin-partner
    v
[Step 6: add_erc20_facet_to_cash_token_diamond] (LASERSVC)
    |-- LASER: admin-partner adds ERC20 facet
    v
[Step 7: initialize_erc20_facet_for_cash_token] (LASERSVC)
    |-- LASER: Initialize ERC20 (name, symbol, decimals=2, mint to Clearing Account)
    v
[Step 8: create_cash_token_deployment_record] (ACCMGR)
    |-- CREATE: LegalMechanismDeployment (LASER) with contract address
    v
[Step 9: grant_erc20_approval_to_treasury] (LASERSVC)
    |-- LASER: Clearing Account approves Treasury for unlimited spending
    v
[Step 10: deposit_cash_token_to_treasury] (LASERSVC)
    |-- LASER: Deposit tokens from Clearing Account to Treasury vault
    v
[Step 11: verify_cash_token_balances] (LASERSVC)
    |-- LASER QUERY: Clearing Account ERC20 = 0
    |-- LASER QUERY: Treasury ERC20 = initial_amount
    |-- LASER QUERY: Vault LIQUID/TOTAL = initial_amount
    v
[Step 12: create_instrument_for_cash_token] (INSTRMGR)
    |-- CREATE: Instrument (CFI=MMCXXX)
    v
[Step 13: create_authorized_instrument_for_cash_token] (INSTRMGR)
    |-- CREATE: AuthorizedInstrument
    v
[Step 14: create_cash_token_record] (INSTRMGR)
    |-- CREATE: CashToken (same IID as AuthorizedInstrument)
    v
[SAGA COMMITTED]
```

---

## Service Execution Summary

```
ACCMGR (3 steps):    1 -> 2 -----------------------> 8
                          \                          \
LASERSVC (8 steps):        3 -> 4 -> 5 -> 6 -> 7      9 -> 10 -> 11
                                                               \
INSTRMGR (3 steps):                                             12 -> 13 -> 14
```

---

## Files Summary

### New Files

| File | Description |
|------|-------------|
| `pkg/trax/templates/agora/csd/deploy_cash_token_legal_mechanism_for_legal_structure.go` | Saga template (14 steps) |
| `pkg/daemons/accmgr/api/v1/legal_mechanisms_post_deploy_cash_token.go` | REST endpoint |
| `pkg/daemons/accmgr/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/saga.go` | ACCMGR executor registration |
| `pkg/daemons/accmgr/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/verify_inputs.go` | Step 1 |
| `pkg/daemons/accmgr/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/create_cash_token_mechanism.go` | Step 2 |
| `pkg/daemons/accmgr/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/create_cash_token_deployment.go` | Step 8 |
| `pkg/daemons/lasersvc/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/saga.go` | LASERSVC executor registration |
| `pkg/daemons/lasersvc/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/deploy_erc20_contract.go` | Step 3 |
| `pkg/daemons/lasersvc/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/initialize_diamond.go` | Step 4 |
| `pkg/daemons/lasersvc/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/grant_add_facets_permission.go` | Step 5 |
| `pkg/daemons/lasersvc/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/add_erc20_facet.go` | Step 6 |
| `pkg/daemons/lasersvc/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/initialize_erc20_facet.go` | Step 7 |
| `pkg/daemons/lasersvc/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/grant_erc20_approval.go` | Step 9 |
| `pkg/daemons/lasersvc/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/deposit_to_treasury.go` | Step 10 |
| `pkg/daemons/lasersvc/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/verify_balances.go` | Step 11 |
| `pkg/daemons/instrmgr/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/saga.go` | INSTRMGR executor registration |
| `pkg/daemons/instrmgr/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/create_instrument.go` | Step 12 |
| `pkg/daemons/instrmgr/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/create_authorized_instrument.go` | Step 13 |
| `pkg/daemons/instrmgr/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/create_cash_token.go` | Step 14 |
| `tests/e2e/laser/cash_token_mechanism_deployment_test.go` | E2E tests |

### Modified Files

| File | Changes |
|------|---------|
| `pkg/fin/legal_mechanism.go` | Add CASH_TOKEN type enum |
| `pkg/trax/templates/agora/csd/index.go` | Register new saga template |
| `pkg/daemons/accmgr/api/v1/api.go` | Add route for POST /legal-mechanisms/deploy-cash-token |
| `pkg/daemons/accmgr/trax/executors/run.go` | Register ACCMGR executors |
| `pkg/daemons/lasersvc/trax/executors/run.go` | Register LASERSVC executors |
| `pkg/daemons/instrmgr/trax/executors/run.go` | Register INSTRMGR executors |
| `docs/SUMMARY-FOR-AGENT.md` | Document cash token legal mechanism deployment |

---

## Critical Reference Files

These files should be studied closely for implementation patterns:

| File | Reason |
|------|--------|
| `pkg/trax/templates/agora/csd/deploy_treasury_legal_mechanisms_for_legal_structure.go` | Saga template structure pattern |
| `pkg/daemons/accmgr/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/verify_inputs.go` | Verification step pattern |
| `pkg/daemons/lasersvc/trax/executors/process_new_instrument_authorization/deposit_initial_supply_to_treasury.go` | Treasury deposit pattern |
| `pkg/daemons/instrmgr/trax/executors/process_new_instrument_authorization/create_authorized_instrument_record.go` | AuthorizedInstrument + CashToken creation pattern |
| `docs/TODO_CLEARING_ACCOUNT_FOR_LEGAL_STRUCTURE.md` | Clearing Account implementation (dependency) |

---

## Dependencies

### Runtime Dependencies (per legal structure)
1. **Core Legal Mechanisms saga** - must be deployed first for the legal structure
2. **Treasury Legal Mechanisms saga** - must be deployed first for the legal structure
3. **Clearing Account** - must exist with SIGNER slots

### Infrastructure Dependencies (BLOCKING - implement before this saga)
1. **Clearing Account SIGNER change** - Update `create_clearing_slots.go` to use SIGNER tag
2. **EthBCErc20FacetContract** - New handler for Erc20Facet in EthBC mode
3. **Erc20Initialize operation** - Add to `operation_name.go` and implement handler
4. **ERC20 Diamond routing** - Route ERC20 operations through Diamond+Erc20Facet

---

## Success Criteria

- [ ] CASH_TOKEN type enum added to LegalMechanismTypeEnum
- [ ] Saga template registered correctly (verify via traxcli)
- [ ] All 14 step executors start without errors
- [ ] Green path E2E tests pass (EthBC mode)
- [ ] Red path E2E tests pass (validation failures)
- [ ] ERC20 contract deployed with correct token parameters (name, symbol, decimals=2)
- [ ] Initial supply minted to Clearing Account
- [ ] Tokens deposited to Treasury vault for Clearing Account
- [ ] Balance verification passes (4 checks)
- [ ] Instrument record created with CFI code MMCXXX
- [ ] AuthorizedInstrument and CashToken records created with matching IIDs
- [ ] LegalMechanism and LegalMechanismDeployment records created correctly
- [ ] Multiple currencies supported (USD, EUR, etc. for same legal structure)
- [ ] Duplicate currency detection works (same currency_code + exec_runtime rejected)
- [ ] Documentation updated

---

## Notes

- **EthBC-only**: This saga only works with real Ethereum blockchain, not RDBMS mode
- **Immutable contracts**: LASER contract deployments cannot be compensated (on-chain immutability)
- **Clearing Account**: **SIGNER** account owned by legal structure, receives initial mint, signs ERC20 approve
- **CFI Code**: Cash tokens use fixed CFI code `MMCXXX` (recognized by `IsCashTokenType()`)
- **Decimals**: Fixed at 2 (representing cents for fiat currencies)
- **Vault ownership**: Tokens deposited to Clearing Account's vault in Treasury
- **Currency uniqueness**: Each currency_code can only be deployed once per exec_runtime
- **Prefix reuse**: Uses same prefix as Core/Treasury deployments

---

## CRITICAL: Treasury-to-RAC Authorization Requirement

### The DMND:NAUTH Problem

When the Treasury (Trezor Diamond) performs vault operations like `depositToErc20Vault`, it makes **cross-Diamond calls** to the RAC Diamond's protected functions. This causes `DMND:NAUTH` errors if the Treasury is not authorized on the RAC's AuthzSource.

### Authorization Chain Analysis

1. **Fund Account Saga Step 5**: `TrezorErc20TransferFromVault` is called
2. **Trezor Diamond**: Executes `Erc20VaultInternal._depositToErc20Vault()`
3. **Cross-Diamond Call**: Trezor calls `rac.updateResourceQuota()` on the RAC Diamond
4. **RAC Diamond Authorization Check**:
   - `updateResourceQuota` is a **protected function** (listed in `RACFacet.getFacetProtectedPI()`)
   - RAC Diamond's fallback calls `_authorizeCall(msg.sender, facet, msg.sig, false)`
   - `msg.sender` is the **Trezor Diamond's contract address**
   - RAC Diamond queries its AuthzSource (SimpleAuthzFacet) for authorization
   - If Trezor's identity hash is NOT in the whitelist → **DMND:NAUTH**

### Contract Evidence

From `RACFacet.sol:58-71`:
```solidity
function getFacetProtectedPI() external pure override returns (string[] memory) {
    string[] memory pi = new string[](13);
    // ...
    pi[12] = "updateResourceQuota(address[],bytes32,bytes32,bytes32,uint256,uint256)";  // PROTECTED!
    return pi;
}
```

From `Erc20VaultInternal.sol:99-114`:
```solidity
function _depositToErc20Vault(...) internal {
    IRAC rac = IRAC(PropsLib._getAddress("rac.address", true));
    // ... multiple calls to rac.isResourceAccessible() and rac.updateResourceQuota()
}
```

### Solution: Grant Treasury Access to RAC AuthzSource

A new saga step is required in `deploy_cash_token_legal_mechanism_for_legal_structure` (or `deploy_treasury_legal_mechanisms`) to:

1. **Add Trezor Diamond's address** to the AuthzSource Diamond's SimpleAuthzFacet whitelist
2. Use `SimpleAuthzAddAccount` operation with:
   - `from_slot_address`: authz_admin (who can call addAccount on AuthzSource)
   - `to_slot_address`: authz_source_diamond_slot_address
   - `account`: trezor_diamond_contract_address (the Treasury's on-chain address)

### Saga Step Implementation

```go
// New step: dctlm_grant_treasury_access_to_rac (or dtlm_grant_trezor_rac_access)
// Purpose: Grant Trezor Diamond permission to call RAC Diamond's protected functions

funcDecl := ats.Func(string(model.OperationNameEnum_SimpleAuthzAddAccount)).
    Arguments(
        ats.String(string(ats.ArgNameEnum_LedgerContractSlotAddress)).Build(),
        ats.String(string(ats.ArgNameEnum_Account)).Build(),
    ).
    Returns(ats.String("tx_hash").Build()).
    Build()

arguments := ats.NewBoundTuple().
    AddVar(ats.String(string(ats.ArgNameEnum_LedgerContractSlotAddress)).Build(), authzSourceDiamondSlotAddress).
    AddVar(ats.String(string(ats.ArgNameEnum_Account)).Build(), trezorDiamondContractAddress).  // The Treasury!
    Build()
```

### Where to Add This Step

**Option 1**: In `deploy_treasury_legal_mechanisms_for_legal_structure` saga (RECOMMENDED)
- Add as step 17.5 (new step 18, shifting existing step 18 to 19)
- After RAC properties are configured, before treasury deployment record

**Option 2**: In `deploy_cash_token_legal_mechanism_for_legal_structure` saga
- Add after step 10 (deposit to treasury)
- Problem: This is too late - the deposit fails

**Option 3**: In both sagas (DEFENSIVE)
- Treasury saga: Grant general access
- Cash token saga: Verify/re-grant if needed

### Identity Hash Calculation

The Diamond authorization uses identity hashes computed as:
```solidity
bytes32 identityHash = keccak256(abi.encodePacked(IDENTITY_HASH_SALT, account));
// IDENTITY_HASH_SALT = "Dwt2wb1d976h"
```

SimpleAuthzFacet stores authorized identity hashes, not raw addresses.

---

## Important: ERC20 Contract Types

### ExecutorERC20 vs Erc20Facet - Key Distinction

**ExecutorERC20** (`LedgerContractTypeEnum_ExecutorERC20`):
- A standalone ERC20 contract with executor pattern (not a Lattice facet)
- Uses `approveFor()`, `executorTransfer()`, `transferFromFor()` - executor signs on behalf of accounts
- Currently used for instrument authorization (process_new_instrument_authorization saga)
- **WILL BE DEPRECATED** - this is a legacy contract, not part of the Lattice Framework
- Located in: `pkg/daemons/lcmgr/ethbc_executor_erc20_contract.go`

**Erc20Facet** (`LedgerContractTypeEnum_Facet`):
- A proper Lattice Framework facet that can be added to a Diamond
- Standard ERC20 interface (no executor pattern)
- Part of the Lattice archive (introduced in rev-11, current default: rev-17)
- **USE THIS** for Cash Token deployment via Diamond pattern

**LASERErc20Facet**:
- Extended Erc20Facet with LASER-specific features
- Also part of Lattice Framework

### Implication for This Saga

This saga MUST use **Erc20Facet** (or LASERErc20Facet) added to a Diamond contract, NOT the legacy ExecutorERC20. The steps should:
1. Deploy a new Diamond contract (Step 3)
2. Add Erc20Facet to the Diamond (Step 6)
3. Initialize ERC20 via the facet (Step 7)

The Clearing Account **MUST be a SIGNER** because:
- Step 9 requires Clearing Account to sign an ERC20 `approve()` transaction
- Standard Erc20Facet uses `approve(spender, amount)` where the owner (FromSlot) signs
- This is different from ExecutorERC20's `approveFor()` pattern

---

## Technical Details: Erc20Facet

### Erc20Facet Initialization Function (introduced in Lattice rev-11, current default: rev-17)

The `Erc20Facet` has an `initializeErc20` function with this signature:

```solidity
function initializeErc20(
    string _name,
    string details,           // Details URI
    string _symbol,
    uint8 _decimals,
    address[] initialOwners,  // Array of addresses to receive initial balances
    uint256[] initialBalances // Array of initial balances (matched by index)
) returns()
```

**Key insight**: Minting is PART OF initialization (via `initialOwners`/`initialBalances` arrays), NOT a separate call.

**For Cash Token Step 7**, use:
- `_name`: "{currency_code} Cash Token" (e.g., "USD Cash Token")
- `details`: "" (empty or URI)
- `_symbol`: currency_code (e.g., "USD")
- `_decimals`: 2 (for cents)
- `initialOwners`: [clearing_account_address]
- `initialBalances`: [initial_amount]

### Other Erc20Facet Functions

```solidity
// Standard ERC20
function approve(address spender, uint256 amount) returns(bool)
function transfer(address to, uint256 amount) returns(bool)
function transferFrom(address from, address to, uint256 amount) returns(bool)
function balanceOf(address account) returns(uint256)
function allowance(address owner, address spender) returns(uint256)
function totalSupply() returns(uint256)
function name() returns(string)
function symbol() returns(string)
function decimals() returns(uint8)

// Minting (separate from initialization)
function mint(uint256 amount, bytes) returns()
function mintTo(address account, uint256 amount, bytes) returns()
```

### LASER Operations Status

| Operation | RDBMS Mode | EthBC ExecutorERC20 | EthBC Erc20Facet |
|-----------|------------|---------------------|------------------|
| `Erc20Approve` | ✅ `erc20_contract.go:mutationApprove()` | ✅ `ethbc_executor_erc20_contract.go` (uses `approveFor`) | ✅ `ethbc_erc20_facet_contract.go` |
| `Erc20Transfer` | ✅ Implemented | ✅ Implemented (uses `executorTransfer`) | ✅ `ethbc_erc20_facet_contract.go` |
| `Erc20Initialize` | ❌ Not defined | ❌ N/A | ✅ `ethbc_erc20_facet_contract.go` |
| `Erc20Mint` | ✅ Implemented | ✅ Implemented | ❌ (use `initializeErc20` with balances) |
| `Erc20BalanceOf` | ✅ Implemented | ✅ Implemented | ✅ `ethbc_erc20_facet_contract.go` |

**Required new operation**: `OperationNameEnum_Erc20Initialize` in `pkg/laser/model/operation_name.go`

---

## Technical Details: Diamond vs AuthzDiamond

### Use `Diamond` (NOT AuthzDiamond) for Cash Token

The Cash Token should follow the same pattern as RAC/Trezor Diamonds:

```
[AuthzDiamond] (Central Authority - ONE per legal structure)
      ↑ authz_source
      |
      ├─→ [RAC Diamond]        (domain: "RAC")
      ├─→ [Trezor Diamond]     (domain: "Trezor")
      └─→ [CashToken Diamond]  (domain: "CashToken-{currency}")
             └─ Contains: Erc20Facet
```

**Key differences**:
- **AuthzDiamond**: Built-in RBAC via SimpleAuthzFacet, Lattice v3.0.0
- **Diamond**: External authorization via `authz_source`, Lattice v4.0.0

### Cash Token Diamond Initialization (Step 4)

```go
// Initialize Diamond with:
diamond_name:    "{prefix}-CashToken-{currency_code}"
authz_source:    AuthzDiamond address (same as RAC/Trezor)
authz_domain:    "CashToken-{currency_code}" (unique domain)
task_manager:    TaskManagerV2 contract address
admin:           admin_partner_slot_address
```

### Permission Grant Pattern (Step 5)

Via `SimpleAuthzFacet.addAccount()` on the AuthzDiamond:
```go
// authz_admin calls SimpleAuthzAddAccount on AuthzDiamond
// to authorize admin_partner for the CashToken domain
mutationSimpleAuthzAddAccount(account: admin_partner_address)
```

---

## Technical Details: Prefix Pattern

### How Prefix is Derived

From Treasury mechanisms pattern (`verify_inputs.go` lines 188-199):

```go
prefix := input["prefix"]
if prefix == "" && taskManagerSlotAddress != "" {
    // Derive prefix from TaskManager slot address: {prefix}-TaskManager
    prefix = taskManagerSlotAddress[:len(taskManagerSlotAddress)-len("-TaskManager")]
}
```

### Slot Address Patterns

| Mechanism Type | Slot Address Pattern |
|----------------|---------------------|
| TaskManager (Voting) | `{prefix}-TaskManager` |
| AuthzSource | `{prefix}-AuthzSource` |
| RAC | `{prefix}-RAC` |
| Trezor (Treasury) | `{prefix}-Trezor` |
| **CashToken** | `{prefix}-CashToken-{currency_code}` |

---

## Technical Details: instrmgr Infrastructure

### TRAX Executor Infrastructure EXISTS

Path: `pkg/daemons/instrmgr/trax/executors/process_new_instrument_authorization/`
- `saga.go` - Executor initialization with `RunExecutorsAsync()`
- `create_authorized_instrument_record.go` - Main executor (729 lines)

### CashToken Domain Model EXISTS

Location: `pkg/fin/instrument.go:159-173`

```go
type CashToken struct {
    Iid          string                    // Same as AuthorizedInstrument IID
    Identifiers  []FinIdentifier           // TICKER identifier
    DisplayNames map[string]string         // Localized names
    Descriptions map[string]string         // Localized descriptions
    Labels       map[string]string         // type, deployment_status, ticker, token_symbol
    Tags         []string                  // issued, erc20, cash_token, symbol
    Metadata     map[string]string         // deployment details, contract info
    Instrument   *Instrument               // Expanded field (omitempty)
}
```

### CashToken Store Interface EXISTS

Location: `pkg/daemons/instrmgr/stores/cash_token_store.go`

Methods available:
- `CreateCashToken(ctx, cashToken)` - Validates underlying instrument has CFI=MMCXXX
- `GetCashToken(ctx, iid)`
- `UpdateCashToken(ctx, cashToken)`
- `DeleteCashToken(ctx, iid)`
- `ListCashTokens(ctx, limit, offset)`
- `SearchCashTokens(ctx, query, limit, offset)`
- `QueryCashTokens(ctx, options)`

PostgreSQL implementation: `pkg/daemons/instrmgr/stores/postgres/cash_token_store.go` (544 lines)

---

## Technical Details: Clearing Account Changes ✅ IMPLEMENTED

### Implementation (Updated)

From `create_clearing_slots.go:52-57`:
```go
results, err := service.CreateSeededSlotsForAllExecutorsWithTransaction(
    ctx,
    slotAddressSeed,
    []string{"SIGNER"}, // tags - SIGNER required for ERC20 approve
```

### Files Updated

1. ✅ `pkg/daemons/lasersvc/trax/executors/establish_new_legal_structure_for_participant/create_clearing_slots.go`
   - Changed `nil` to `[]string{"SIGNER"}` for tags parameter

2. Tests automatically use SIGNER slots now (no explicit changes needed):
   - Existing tests create SIGNER slots via the updated code path
   - SIGNER tag slot_link creation is covered by `signer_tag_test.go`

---

## Technical Details: ERC20 Approve Flow

### Standard Erc20Facet Approve (Step 9)

```go
// From erc20_contract.go:252-298
func (c *ERC20Contract) mutationApprove(ctx context.Context, req laser.MutationRequest) {
    ownerAddr := req.FromSlot  // Clearing Account address
    spenderAddr := extractStringArg(req.CallData.Arguments, "spender")  // Treasury address
    amount := extractStringArg(req.CallData.Arguments, "amount")  // max uint256

    c.store.SetAllowance(ctx, contractAddress, ownerAddr, spenderAddr, amount)
}
```

### Key Point
- The **Clearing Account** is the `FromSlot` (owner)
- The **Clearing Account** must **SIGN** this transaction
- For EthBC mode, signersvc must have the Clearing Account's key

---

## Blocking Prerequisites - Implementation Details ✅ ALL COMPLETED

### Prerequisite 1: EthBCErc20FacetContract ✅ DONE

**What**: New contract handler for Erc20Facet operations via Diamond in EthBC mode

**Files created/modified**:
- ✅ NEW: `pkg/daemons/lcmgr/ethbc_erc20_facet_contract.go` - Complete EthContract implementation
- ✅ `pkg/daemons/lcmgr/ledger_execution_service.go` - Added `LedgerContractTypeEnum_Erc20Facet`

**Operations implemented**:
- ✅ `Erc20Approve` - Standard `approve(spender, amount)` where signer is owner
- ✅ `Erc20Transfer` - Standard `transfer(to, amount)`
- ✅ `Erc20TransferFrom` - Standard `transferFrom(from, to, amount)`
- ✅ `Erc20BalanceOf` - Query `balanceOf(account)`
- ✅ `Erc20Initialize` - Initialize ERC20 with `initializeErc20(name, details, symbol, decimals, owners, balances)`

### Prerequisite 2: Erc20Initialize LASER Operation ✅ DONE

**Files modified**:
- ✅ `pkg/laser/model/operation_name.go` - Added `OperationNameEnum_Erc20Initialize`
- ✅ `pkg/daemons/lcmgr/ethbc_erc20_facet_contract.go` - Handler implemented in `mutationInitialize()`

```go
OperationNameEnum_Erc20Initialize OperationNameEnum = "OPERATION_NAME_ENUM_ERC20_INITIALIZE"
```

### Prerequisite 3: ERC20 Approve for Diamond+Erc20Facet ✅ DONE

**Implementation**: Created separate `EthBCErc20FacetContract` (Option 2 - cleaner separation)

The new contract:
- Routes ERC20 operations through Diamond proxy to Erc20Facet
- Signer is the token owner (not delegated `approveFor` pattern)
- Supports standard ERC20 interface via Diamond

**Files modified**:
- ✅ `pkg/daemons/lcmgr/ledger/ethbc/mutator.go` - Added `isErc20FacetOperation()` and routing
- ✅ `pkg/daemons/lcmgr/ledger/ethbc/querier.go` - Added routing for Erc20Facet operations

**Routing logic**:
```go
// In createContractOnTheFly() - routes OPERATION_NAME_ENUM_ERC20_INITIALIZE to EthBCErc20FacetContract
if isErc20FacetOperation(operationName) {
    return lcmgr.NewEthBCErc20FacetContract(address, client, signatureProvider)
}
```

### Prerequisite 4: Clearing Account SIGNER Slots ✅ DONE

**Files modified**:
- ✅ `pkg/daemons/lasersvc/trax/executors/establish_new_legal_structure_for_participant/create_clearing_slots.go`

**Change applied**:
```go
// Changed from:
nil, // tags - nil for non-SIGNER clearing slots

// To:
[]string{"SIGNER"}, // tags - SIGNER required for ERC20 approve
```
