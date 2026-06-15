# TODO: Legal Structure Sagas Diamond+Facet Refactoring

> **Status**: COMPLETE (Go code, SQL, and E2E test updates done - pending E2E test verification)
> **Created**: 2026-01-27
> **Updated**: 2026-01-27
> **Priority**: HIGH
> **Branch**: `impl-prtagent-grpc-iface-with-trax-integ`

---

## Overview

Refactor legal-structure sagas to use the proper Diamond+Facet pattern instead of the removed `DeployErc20`/`Erc20Mint`/`Erc20Transfer` operations.

**Problem**: The previous commit renamed ERC20 operations to distinguish between:
- **ExecutorERC20** operations (standalone contracts, NOT for legal-structure sagas)
- **LaserErc20Facet** operations (Diamond+Facet pattern, FOR legal-structure sagas)

The code does NOT compile because saga files still reference the removed operations.

---

## Naming Convention

- Step names: Use `deploy_erc20_diamond`, `add_laser_erc20_facet`, `initialize_laser_erc20`
- Facet slot address format: `LASERErc20Facet:{version}` (LASER translates to ETH address)
- Operation names: `LaserErc20FacetMint`, `LaserErc20FacetTransfer`, `LaserErc20FacetInitialize`

---

## Reference Implementation

Follow the pattern from **Treasury saga** (`deploy_treasury_legal_mechanisms_for_legal_structure`):
- `deploy_trezor_diamond.go` - DeployDiamond pattern
- `initialize_trezor_diamond.go` - InitializeDiamond pattern
- `grant_add_facets_perm_trezor.go` - SimpleAuthzAddAccount pattern
- `add_vault_facets.go` - DiamondAddFacets pattern

---

## Phase 0: SQL Saga Template Updates (MUST BE DONE FIRST!)

> **CRITICAL**: The saga step templates must be loaded into the database BEFORE the Go executors can run. The database defines which steps exist and their order.

### SQL Files to Update

| File | Saga |
|------|------|
| `deploy/k8s/init/csd/min/trax.sql` | `deploy_cash_token_legal_mechanism_for_legal_structure`, `process_new_instrument_authorization` |
| `deploy/k8s/init/prtagent/min/trax.sql` | Same sagas (if present) |

### CashToken Saga SQL Changes

**Current** (5 steps):
```sql
'["dctlm_verify_cash_token_inputs", "dctlm_create_cash_token_legal_mechanism", "dctlm_deploy_cash_token_erc20_contract", "dctlm_issue_initial_supply_to_clearing", "dctlm_create_cash_token_record"]'
```

**New** (9 steps):
```sql
'["dctlm_verify_cash_token_inputs", "dctlm_create_cash_token_legal_mechanism", "dctlm_deploy_erc20_diamond", "dctlm_initialize_erc20_diamond", "dctlm_grant_add_laser_erc20_facet_permission", "dctlm_add_laser_erc20_facet", "dctlm_grant_initialize_laser_erc20_permission", "dctlm_initialize_laser_erc20", "dctlm_issue_initial_supply_to_clearing", "dctlm_create_cash_token_record"]'
```

### Tasks

- [x] 0.1 UPDATE `deploy/k8s/init/csd/min/trax.sql`: ✅ DONE
  - [x] Update `deploy_cash_token_legal_mechanism_for_legal_structure` saga_step_template_ids
  - [x] DELETE old step template: `dctlm_deploy_cash_token_erc20_contract`
  - [x] ADD new step templates:
    - `dctlm_deploy_erc20_diamond`
    - `dctlm_initialize_erc20_diamond`
    - `dctlm_grant_add_laser_erc20_facet_permission`
    - `dctlm_add_laser_erc20_facet`
    - `dctlm_grant_initialize_laser_erc20_permission`
    - `dctlm_initialize_laser_erc20`
  - [x] UPDATE step index numbers for `dctlm_issue_initial_supply_to_clearing` and `dctlm_create_cash_token_record`

- [x] 0.2 UPDATE `deploy/k8s/init/csd/min/trax.sql`: ✅ DONE
  - [x] Update `process_new_instrument_authorization` saga_step_template_ids (now 8 steps with Diamond+Facet pattern)
  - [x] ADD new `pnia_*` Diamond+Facet steps

- [x] 0.3 UPDATE `deploy/k8s/init/prtagent/min/trax.sql` ✅ DONE (already has Diamond+Facet pattern)

- [ ] 0.4 Re-deploy database with updated SQL:
  ```bash
  # After SQL updates, re-initialize the database
  ./deploy data min-records --cluster-id <cluster> --ns csd
  ```

---

## Phase 1: CashToken Saga Refactoring

**Saga**: `deploy_cash_token_legal_mechanism_for_legal_structure`
**Directory**: `pkg/daemons/laseragent/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/`

### Current LASERSVC Steps (BROKEN)

| Step | File | Operation | Status |
|------|------|-----------|--------|
| `dctlm_deploy_cash_token_erc20_contract` | `deploy_cash_token_erc20_contract.go` | `DeployErc20` | ❌ BROKEN |
| `dctlm_issue_initial_supply_to_clearing` | `issue_initial_supply_to_clearing.go` | `Erc20Mint` | ❌ BROKEN |

### New LASERSVC Steps

| # | Step ID | File Name | Operation | Status |
|---|---------|-----------|-----------|--------|
| 1 | `dctlm_deploy_erc20_diamond` | `deploy_erc20_diamond.go` | `DeployDiamond` | ⬜ TODO |
| 2 | `dctlm_initialize_erc20_diamond` | `initialize_erc20_diamond.go` | `InitializeDiamond` | ⬜ TODO |
| 3 | `dctlm_grant_add_laser_erc20_facet_permission` | `grant_add_laser_erc20_facet_permission.go` | `SimpleAuthzAddAccount` | ⬜ TODO |
| 4 | `dctlm_add_laser_erc20_facet` | `add_laser_erc20_facet.go` | `DiamondAddFacets` | ⬜ TODO |
| 5 | `dctlm_grant_initialize_laser_erc20_permission` | `grant_initialize_laser_erc20_permission.go` | `SimpleAuthzAddAccount` | ⬜ TODO |
| 6 | `dctlm_initialize_laser_erc20` | `initialize_laser_erc20.go` | `LaserErc20FacetInitialize` | ⬜ TODO |
| 7 | `dctlm_issue_initial_supply_to_clearing` | `issue_initial_supply_to_clearing.go` | `LaserErc20FacetMint` | ⬜ TODO |

### Tasks

- [x] 1.1 DELETE `deploy_cash_token_erc20_contract.go` ✅ DONE
- [x] 1.2 CREATE `dctlm_deploy_erc20_diamond.go` ✅ DONE
- [x] 1.3 CREATE `dctlm_initialize_erc20_diamond.go` ✅ DONE
- [x] 1.4 CREATE `dctlm_grant_add_laser_erc20_facet_permission.go` ✅ DONE
- [x] 1.5 CREATE `dctlm_add_laser_erc20_facet.go` ✅ DONE
- [x] 1.6 CREATE `dctlm_grant_initialize_laser_erc20_permission.go` ✅ DONE
- [x] 1.7 CREATE `dctlm_initialize_laser_erc20.go` ✅ DONE
- [x] 1.8 MODIFY `issue_initial_supply_to_clearing.go`: Change `Erc20Mint` → `LaserErc20FacetMint` ✅ DONE
- [x] 1.9 MODIFY `saga.go`: Update to run new executor goroutines ✅ DONE

---

## Phase 2: AuthorizedInstrument Saga Refactoring

**Saga**: `process_new_instrument_authorization`
**Directory**: `pkg/daemons/laseragent/trax/executors/process_new_instrument_authorization/`

### Current Steps (BROKEN)

| Step | File | Operation | Status |
|------|------|-----------|--------|
| `deploy_diamond_contract_for_authorized_instrument` | `deploy_diamond_contract_for_authorized_instrument.go` | `DeployErc20` | ❌ BROKEN |

### New Steps

| # | Step ID | File Name | Operation | Status |
|---|---------|-----------|-----------|--------|
| 1 | `pnia_deploy_erc20_diamond` | `deploy_erc20_diamond.go` | `DeployDiamond` | ⬜ TODO |
| 2 | `pnia_initialize_erc20_diamond` | `initialize_erc20_diamond.go` | `InitializeDiamond` | ⬜ TODO |
| 3 | `pnia_grant_add_laser_erc20_facet_permission` | `grant_add_laser_erc20_facet_permission.go` | `SimpleAuthzAddAccount` | ⬜ TODO |
| 4 | `pnia_add_laser_erc20_facet` | `add_laser_erc20_facet.go` | `DiamondAddFacets` | ⬜ TODO |
| 5 | `pnia_grant_initialize_laser_erc20_permission` | `grant_initialize_laser_erc20_permission.go` | `SimpleAuthzAddAccount` | ⬜ TODO |
| 6 | `pnia_initialize_laser_erc20` | `initialize_laser_erc20.go` | `LaserErc20FacetInitialize` | ⬜ TODO |

### Tasks

- [x] 2.1 DELETE `deploy_diamond_contract_for_authorized_instrument.go` and related old files ✅ DONE
- [x] 2.2 CREATE `pnia_deploy_erc20_diamond.go` ✅ DONE
- [x] 2.3 CREATE `pnia_initialize_erc20_diamond.go` ✅ DONE
- [x] 2.4 CREATE `pnia_grant_add_laser_erc20_facet_permission.go` ✅ DONE
- [x] 2.5 CREATE `pnia_add_laser_erc20_facet.go` ✅ DONE
- [x] 2.6 CREATE `pnia_grant_initialize_laser_erc20_permission.go` ✅ DONE
- [x] 2.7 CREATE `pnia_initialize_laser_erc20.go` ✅ DONE
- [x] 2.8 MODIFY `deposit_initial_supply_to_treasury.go`: Update step ID to `pnia_deposit_initial_supply_to_treasury` ✅ DONE
- [x] 2.9 MODIFY `saga.go`: Update executor registrations ✅ DONE

---

## Phase 3: Simple Operation Updates

### Transfer Tokens (`transfer_authorized_instrument`)

**File**: `pkg/daemons/laseragent/trax/executors/transfer_authorized_instrument/transfer_tokens.go`

- [x] 3.1 Change `Erc20Transfer` → `LaserErc20FacetTransfer` ✅ DONE
- [x] 3.2 Update ATS function declaration to use `LaserErc20FacetTransfer` ✅ DONE

### Mint Tokens (`fund_account_with_cash_tokens`)

**File**: `pkg/daemons/treassvc/trax/executors/fund_account_with_cash_tokens/mint_tokens_if_needed.go`

- [x] 3.3 Change `Erc20Mint` → `LaserErc20FacetMint` ✅ DONE
- [x] 3.4 Update ATS function declaration to use `LaserErc20FacetMint` ✅ DONE

---

## Implementation Details

### Step: `deploy_erc20_diamond`

```go
funcDecl := ats.Func(string(model.OperationNameEnum_DeployDiamond)).
    Arguments(
        ats.String(string(ats.ArgNameEnum_Deployer)).Build(),
        ats.String(string(ats.ArgNameEnum_SmartContractName)).Build(),
    ).
    Returns(
        ats.String("contract_address").Build(),
        ats.String("tx_hash").Build(),
    ).Build()

// Input: deployer_slot_address, cash_token_slot_address (Diamond name)
// Output: cash_token_diamond_contract_address, cash_token_deploy_tx_hash
```

### Step: `initialize_erc20_diamond`

```go
funcDecl := ats.Func(string(model.OperationNameEnum_InitializeDiamond)).
    Arguments(
        ats.String(string(ats.ArgNameEnum_LedgerContractSlotAddress)).Build(),
        ats.String(string(ats.ArgNameEnum_DiamondName)).Build(),
        ats.String(string(ats.ArgNameEnum_TaskManager)).Build(),
        ats.String(string(ats.ArgNameEnum_AuthzSource)).Build(),
        ats.String(string(ats.ArgNameEnum_AuthzDomain)).Build(),
    ).
    Returns(
        ats.String("tx_hash").Build(),
    ).Build()

// Input: cash_token_slot_address, task_manager_contract_slot_address,
//        authz_source_diamond_slot_address, prefix
// Diamond name: "{prefix}-CashToken-{currency}"
// Authz domain: "CashToken"
```

### Step: `add_laser_erc20_facet`

```go
funcDecl := ats.Func(string(model.OperationNameEnum_DiamondAddFacets)).
    Arguments(
        ats.String(string(ats.ArgNameEnum_Deployer)).Build(),
        ats.String(string(ats.ArgNameEnum_LedgerContractSlotAddress)).Build(),
        ats.Array(string(ats.ArgNameEnum_FacetAddresses), ats.String("").Build()).Build(),
    ).
    Returns(
        ats.String("tx_hash").Build(),
    ).Build()

// Facet slot address - LASER translates to ETH address
facetSlotAddresses := []string{
    fmt.Sprintf("LASERErc20Facet:%s", laserErc20FacetVersion),
}
```

### Step: `initialize_laser_erc20`

```go
funcDecl := ats.Func(string(model.OperationNameEnum_LaserErc20FacetInitialize)).
    Arguments(
        ats.String(string(ats.ArgNameEnum_SmartContractName)).Build(),
        ats.String(string(ats.ArgNameEnum_Name)).Build(),
        ats.String(string(ats.ArgNameEnum_Symbol)).Build(),
        ats.UInt8(string(ats.ArgNameEnum_Decimals)).Build(),
    ).
    Returns(
        ats.String("tx_hash").Build(),
    ).Build()

// Input: cash_token_slot_address (Diamond), token_name, token_symbol, decimals
```

### Step: `issue_initial_supply_to_clearing` (Updated)

```go
funcDecl := ats.Func(string(model.OperationNameEnum_LaserErc20FacetMint)).
    Arguments(
        ats.String(string(ats.ArgNameEnum_SmartContractName)).Build(),
        ats.String(string(ats.ArgNameEnum_MintTo)).Build(),
        ats.UInt256(string(ats.ArgNameEnum_Amount)).Build(),
    ).
    Returns(
        ats.String("tx_hash").Build(),
    ).Build()

// to_slot_address: cash_token_slot_address (Diamond proxy)
```

---

## Required Saga Input Parameters

These come from the legal structure/core mechanisms:

| Parameter | Source | Description |
|-----------|--------|-------------|
| `task_manager_contract_slot_address` | Legal Structure | TaskManagerV2 contract |
| `authz_source_diamond_slot_address` | Legal Structure | RAC AuthzDiamond |
| `authz_admin_slot_address` | Legal Structure | Admin for authz operations |
| `admin_partner_slot_address` | Legal Structure | Partner admin |
| `laser_erc20_facet_version` | Config | Version of LASERErc20Facet (e.g., "1.0.0") |
| `prefix` | Legal Structure | For diamond naming |

---

## Saga Flow Diagram

```
ACCMGR:
  dctlm_verify_cash_token_inputs
  dctlm_create_cash_token_legal_mechanism
       ↓
LASERSVC (7 steps):
  dctlm_deploy_erc20_diamond
       ↓
  dctlm_initialize_erc20_diamond
       ↓
  dctlm_grant_add_laser_erc20_facet_permission
       ↓
  dctlm_add_laser_erc20_facet
       ↓
  dctlm_grant_initialize_laser_erc20_permission
       ↓
  dctlm_initialize_laser_erc20
       ↓
  dctlm_issue_initial_supply_to_clearing
       ↓
INSTRMGR:
  dctlm_create_cash_token_record
```

---

## Phase 4: Update E2E Tests

> **Status**: DONE

E2E tests need to be updated to work with the new Diamond+Facet pattern.

### Analysis Summary

The E2E tests primarily use **standalone ERC20 operations** (`DeployErc20`, `Erc20Transfer`, `Erc20Mint`) for testing LASER infrastructure. These are **ExecutorERC20** operations and are separate from the legal-structure sagas which now use **LaserErc20Facet** operations.

**Key Distinction**:
- **ExecutorERC20** (`DeployErc20`, `Erc20Mint`, `Erc20Transfer`) - Used by E2E test helpers for standalone ERC20 contracts
- **LaserErc20Facet** (`LaserErc20FacetMint`, `LaserErc20FacetTransfer`) - Used by legal-structure sagas via Diamond proxy

Most E2E test files use ExecutorERC20 for test setup and don't need changes. The saga-specific tests need updates.

### Files Requiring Updates

#### 4.1 Saga Documentation Comments (Low Priority)

| File | Line | Issue |
|------|------|-------|
| `tests/e2e/laser/cash_token_deployment_test.go` | 30-34 | Documentation references old step `dctlm_deploy_cash_token_erc20_contract` |
| `tests/e2e/laser/cash_token_deployment_test.go` | 649-658 | `extractCashTokenSagaResults` references old step ID |

#### 4.2 Saga Executor Routes (Medium Priority)

These tests configure LASER executor routes matching on operation names. If the tests are for standalone ERC20 (not legal-structure sagas), they should continue using `DeployErc20`/`Erc20Transfer`. If testing legal-structure flows, they need updates:

| File | Lines | Operation | Update Needed |
|------|-------|-----------|---------------|
| `tests/e2e/instrmgr/instrument_authorization_saga_test.go` | 525 | `DeployErc20` | **YES** - for PNIA saga |
| `tests/e2e/laser/indtrxss_common_test.go` | 606, 622 | `Erc20Transfer`, `Erc20Mint` | **YES** - for TII/FACWCT sagas |

#### 4.3 Test Helper Functions (No Change Needed)

These use standalone ERC20 for test setup infrastructure (NOT legal-structure sagas):

| File | Function | Operations | Update Needed |
|------|----------|------------|---------------|
| `tests/e2e/laser/erc20_helpers_test.go` | `deployERC20WithExecutorSlot` | `DeployErc20` | NO - standalone ERC20 |
| `tests/e2e/laser/erc20_helpers_test.go` | `transferERC20WithExecutorSlot` | `Erc20Transfer` | NO - standalone ERC20 |
| `tests/e2e/laser/erc20_helpers_test.go` | `mintERC20WithExecutorSlot` | `Erc20Mint` | NO - standalone ERC20 |
| `tests/e2e/laser/executor_external_call_test.go` | Multiple | Various | NO - LASER infrastructure tests |
| `tests/e2e/laser/executor_erc20_laser_test.go` | Multiple | Various | NO - LASER ERC20 tests |
| `tests/e2e/laser/diamond_laser_test.go` | Multiple | Various | NO - Diamond infrastructure |
| `tests/e2e/laser/laser_cross_instance_test.go` | Multiple | Various | NO - Cross-instance tests |

### Tasks

- [x] 4.1 Review existing E2E tests for CashToken saga ✅ DONE (Analysis)
- [x] 4.2 Review existing E2E tests for AuthorizedInstrument saga ✅ DONE (Analysis)
- [x] 4.3 Update `cash_token_deployment_test.go`: ✅ DONE
  - [x] Update saga step documentation comments (lines 30-34)
  - [x] Update `extractCashTokenSagaResults()` step IDs (line 649-658)
  - [ ] Update `executeCashTokenDeploymentSteps()` to use Diamond+Facet pattern (SKIPPED - uses workaround)
- [x] 4.4 Update `instrument_authorization_saga_test.go`: ✅ DONE
  - [x] Update executor routes to match new Diamond+Facet operations
  - [x] Added routes for DeployDiamond, InitializeDiamond, DiamondAddFacets, SimpleAuthzAddAccount, LaserErc20FacetInitialize, LaserErc20FacetMint
- [x] 4.5 Update `indtrxss_common_test.go`: ✅ DONE
  - [x] Added route for `LaserErc20FacetTransfer`
  - [x] Added route for `LaserErc20FacetMint`
- [ ] 4.6 Run E2E tests to verify:
  ```bash
  make laser-e2e-smoke
  make instrmgr-e2e
  ```

### Important Note

**DO NOT** update the standalone ERC20 helper functions (`deployERC20WithExecutorSlot`, etc.) as they test the ExecutorERC20 contract which is a separate flow from legal-structure sagas. The ExecutorERC20 operations are still valid for:
- Direct ERC20 deployment/testing
- LASER infrastructure E2E tests
- Non-saga ERC20 operations

---

## Verification

- [x] `make build` - Code compiles without errors ✅ DONE
- [ ] `make test` - Unit tests pass
- [ ] `make laser-e2e-smoke` - Basic functionality works
- [ ] Test CashToken saga end-to-end
- [ ] Test AuthorizedInstrument saga end-to-end
- [ ] Verify Diamond+Facet structure is correct

---

## Files Summary

### CashToken Saga Files

| Action | File Path | Status |
|--------|-----------|--------|
| DELETE | `pkg/daemons/laseragent/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/deploy_cash_token_erc20_contract.go` | ✅ |
| CREATE | `pkg/daemons/laseragent/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/dctlm_deploy_erc20_diamond.go` | ✅ |
| CREATE | `pkg/daemons/laseragent/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/dctlm_initialize_erc20_diamond.go` | ✅ |
| CREATE | `pkg/daemons/laseragent/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/dctlm_grant_add_laser_erc20_facet_permission.go` | ✅ |
| CREATE | `pkg/daemons/laseragent/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/dctlm_add_laser_erc20_facet.go` | ✅ |
| CREATE | `pkg/daemons/laseragent/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/dctlm_grant_initialize_laser_erc20_permission.go` | ✅ |
| CREATE | `pkg/daemons/laseragent/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/dctlm_initialize_laser_erc20.go` | ✅ |
| MODIFY | `pkg/daemons/laseragent/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/issue_initial_supply_to_clearing.go` | ✅ |
| MODIFY | `pkg/daemons/laseragent/trax/executors/deploy_cash_token_legal_mechanism_for_legal_structure/saga.go` | ✅ |

### AuthorizedInstrument Saga Files

| Action | File Path | Status |
|--------|-----------|--------|
| DELETE | `pkg/daemons/laseragent/trax/executors/process_new_instrument_authorization/deploy_diamond_contract_for_authorized_instrument.go` (and old related files) | ✅ |
| CREATE | `pkg/daemons/laseragent/trax/executors/process_new_instrument_authorization/pnia_deploy_erc20_diamond.go` | ✅ |
| CREATE | `pkg/daemons/laseragent/trax/executors/process_new_instrument_authorization/pnia_initialize_erc20_diamond.go` | ✅ |
| CREATE | `pkg/daemons/laseragent/trax/executors/process_new_instrument_authorization/pnia_grant_add_laser_erc20_facet_permission.go` | ✅ |
| CREATE | `pkg/daemons/laseragent/trax/executors/process_new_instrument_authorization/pnia_add_laser_erc20_facet.go` | ✅ |
| CREATE | `pkg/daemons/laseragent/trax/executors/process_new_instrument_authorization/pnia_grant_initialize_laser_erc20_permission.go` | ✅ |
| CREATE | `pkg/daemons/laseragent/trax/executors/process_new_instrument_authorization/pnia_initialize_laser_erc20.go` | ✅ |
| MODIFY | `pkg/daemons/laseragent/trax/executors/process_new_instrument_authorization/deposit_initial_supply_to_treasury.go` | ✅ |
| MODIFY | `pkg/daemons/laseragent/trax/executors/process_new_instrument_authorization/saga.go` | ✅ |

### Simple Update Files

| Action | File Path | Status |
|--------|-----------|--------|
| MODIFY | `pkg/daemons/laseragent/trax/executors/transfer_authorized_instrument/transfer_tokens.go` | ✅ |
| MODIFY | `pkg/daemons/treassvc/trax/executors/fund_account_with_cash_tokens/mint_tokens_if_needed.go` | ✅ |

---

## Related Documents

- `docs/TODO_DEPLOY_CASH_TOKEN_LEGAL_MECHANISM_SAGA.md` - Original CashToken saga spec
- `docs/DIAMOND_LASER_LCMGR_SUPPORT_TODO.md` - Diamond implementation reference
- Treasury saga: `pkg/daemons/laseragent/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/`