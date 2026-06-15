# TODO: Deploy Treasury Legal Mechanisms for Legal Structure - TRAX Saga Implementation

> **Status**: COMPLETE
> **Created**: 2026-01-02
> **Parent Reference**: `deploy_core_legal_mechanisms_for_legal_structure` saga

## Overview

TRAX saga template `deploy_treasury_legal_mechanisms_for_legal_structure` that deploys Treasury governance mechanisms (RAC Diamond and Trezor Diamond) for an existing legal structure that already has Core Legal Mechanisms deployed. This saga is EthBC-only and requires LASER for all contract operations.

**Key Concepts**:
- **RAC Diamond**: Resource Access Controller - manages access control for treasury operations
- **Trezor Diamond**: Treasury vault - holds vault facets (erc20-vault, eth-vault, etc.) and ledger functionality

---

## Prerequisites (MUST be validated in Step 1)

1. **Legal Structure exists** - must be PARTNERSHIP type
2. **Core Legal Mechanisms are deployed** on the specified Execution Runtime:
   - TaskManagerV2 contract deployed and initialized
   - AuthzDiamond contract deployed, initialized, and has AuthzFacet added
3. **No prior Treasury Legal Mechanisms** have been deployed to the specified Exec Runtime
4. **Required facets available in lattice archive** (latest versions):
   - `rac` - Resource Access Controller facet
   - `erc20-vault-admin` - ERC20 vault administration facet
   - `erc20-vault` - ERC20 vault operations facet
   - `ledger-lister` - Ledger listing/query facet
   - `rbac` - Role-Based Access Control facet
   - `props` - Properties/configuration facet
   - `activity-store` - Activity audit log facet
   - `eth-vault` - Native ETH vault facet
   - `erc20-vault-idemp` - Idempotent ERC20 vault operations facet
5. **admin_partner** must be:
   - One of the partners of the Legal Structure
   - One of the TaskManager admins
6. **authz_admin** must be one of the AuthzDiamond's admins (from Core deployment)

---

## Saga Specification

### Inputs

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| exec_runtime_name | string | Yes | Execution runtime for deployments (e.g., "primary") |
| locale | string | Yes | Locale for display names (e.g., "en-US") |
| legal_structure_iid | string | Yes | IID of the parent legal structure |
| admin_partner_slot_address | string | Yes | LASER slot address of admin partner (must be partner + TM admin) |
| authz_admin_slot_address | string | Yes | LASER slot address of AuthzDiamond admin (from Core deployment) |
| deployer_account_iid | string | Yes | Account IID with SIGNER slot for deployments |
| deployer_slot_address | string | Yes | LASER slot address for contract deployments |
| rac_facet_version | string | Yes | Version of RAC facet from lattice (e.g., "v1.0.0") |
| erc20_vault_admin_facet_version | string | Yes | Version of erc20-vault-admin facet |
| erc20_vault_facet_version | string | Yes | Version of erc20-vault facet |
| ledger_lister_facet_version | string | Yes | Version of ledger-lister facet |
| rbac_facet_version | string | Yes | Version of rbac facet |
| props_facet_version | string | Yes | Version of props facet |
| activity_store_facet_version | string | Yes | Version of activity-store facet |
| eth_vault_facet_version | string | Yes | Version of eth-vault facet |
| erc20_vault_idemp_facet_version | string | Yes | Version of erc20-vault-idemp facet |

**Note**: The `prefix` for slot/contract names is derived from the existing Core Legal Mechanisms deployment (same prefix used).

### Validation Rules (Step 1)

1. `legal_structure_iid` must reference an existing PARTNERSHIP legal structure
2. Core Legal Mechanisms must exist for this Legal Structure (query LegalMechanism records with types VOTING and AUTHORISATION_SOURCE)
3. No Treasury mechanisms (types RAC, TREASURY) exist for this Legal Structure
4. `admin_partner_slot_address` must:
   - Belong to a partner in the Legal Structure's participant list
   - Be one of the TaskManager admins (from Core deployment)
5. `authz_admin_slot_address` must be one of the AuthzDiamond admins (from Core deployment)
6. `deployer_account_iid` must have an active SIGNER-tagged slot

### Saga Steps (18 steps)

| Step | Name | Service | Description |
|------|------|---------|-------------|
| 1 | `verify_treasury_mechanism_inputs` | **accmgr** | Validate inputs, verify Core exists, verify no Treasury exists |
| 2 | `create_rac_legal_mechanism` | **accmgr** | Create LegalMechanism record (type=RAC) |
| 3 | `create_treasury_legal_mechanism` | **accmgr** | Create LegalMechanism record (type=TREASURY) |
| 4 | `deploy_rac_diamond_contract` | **lasersvc** | Deploy RAC Diamond via LASER using deployer |
| 5 | `initialize_rac_diamond` | **lasersvc** | Initialize RAC Diamond (admin-partner) |
| 6 | `grant_add_facets_permission_to_admin_rac` | **lasersvc** | authz-admin grants addFacets permission to admin-partner on RAC |
| 7 | `add_rac_facet_to_rac_diamond` | **lasersvc** | admin-partner adds RAC facet to RAC diamond |
| 8 | `create_rac_deployment_record` | **accmgr** | Create LegalMechanismDeployment for RAC |
| 9 | `deploy_trezor_diamond_contract` | **lasersvc** | Deploy Trezor Diamond via LASER using deployer |
| 10 | `initialize_trezor_diamond` | **lasersvc** | Initialize Trezor Diamond (admin-partner) |
| 11 | `grant_add_facets_permission_to_admin_trezor` | **lasersvc** | authz-admin grants addFacets permission to admin-partner on Trezor |
| 12 | `add_vault_facets_to_trezor_diamond` | **lasersvc** | admin-partner adds all vault facets (a-h, 8 total) to Trezor diamond |
| 13 | `grant_create_ledger_permission` | **lasersvc** | authz-admin grants createLedger permission to admin-partner |
| 14 | `create_default_ledger` | **lasersvc** | admin-partner creates DEFAULT ledger (id=1) |
| 15 | `grant_set_address_permission` | **lasersvc** | authz-admin grants setAddress permission to admin-partner |
| 16 | `grant_set_int_permission` | **lasersvc** | authz-admin grants setInt permission to admin-partner |
| 17 | `configure_rac_properties` | **lasersvc** | admin-partner calls setInt("rac.domain.id", 999) and setAddress("rac.address", RAC_addr) |
| 18 | `create_treasury_deployment_record` | **accmgr** | Create LegalMechanismDeployment for Trezor |

**Service Distribution**:
- **accmgr**: Steps 1, 2, 3, 8, 18 (legal mechanism domain records)
- **lasersvc**: Steps 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15, 16, 17 (LASER contract operations)

---

## Implementation Phases

### Phase 1: Domain Model Updates

**File**: `pkg/fin/legal_mechanism.go`

- [x] 1.1.1 `LegalMechanismTypeEnum_ResourceAccessController` already exists (RAC)
- [x] 1.1.2 `LegalMechanismTypeEnum_Treasury` already exists

**No domain model changes required** - both types are already defined.

---

### Phase 2: Saga Template

**File**: `pkg/trax/templates/agora/csd/deploy_treasury_legal_mechanisms_for_legal_structure.go` (NEW)

- [x] 2.1.1 Define `SagaTemplate` with TemplateId: `deploy_treasury_legal_mechanisms_for_legal_structure`
- [x] 2.1.2 Define 18 `SagaStepTemplate` records with proper ordering and service labels
- [x] 2.1.3 Create `CreateDeployTreasuryLegalMechanismsForLegalStructureSagaTemplates()` function

**File**: `pkg/trax/templates/agora/csd/index.go`

- [x] 2.2.1 Add call to new template creation function

---

### Phase 3: API Endpoint

**File**: `pkg/daemons/accmgr/api/v1/legal_mechanisms_post_deploy_treasury.go` (NEW)

- [x] 3.1.1 Create `deployTreasuryLegalMechanismsRequest` struct
- [x] 3.1.2 Create `deployTreasuryLegalMechanismsResponse` struct
- [x] 3.1.3 Implement `postDeployTreasuryLegalMechanisms(c *gin.Context)` handler
- [x] 3.1.4 Validate required fields
- [x] 3.1.5 Submit saga via `traxSagaSubmitter.SubmitSaga()`

**File**: `pkg/daemons/accmgr/api/v1/api.go`

- [x] 3.2.1 Add route: `POST /legal-mechanisms/deploy-treasury` -> `postDeployTreasuryLegalMechanisms`

---

### Phase 4: ACCMGR Executors

**Directory**: `pkg/daemons/accmgr/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/` (NEW)

#### Step 1: verify_treasury_mechanism_inputs
**File**: `verify_inputs.go`

- [x] 4.1.1 Validate all required inputs exist
- [x] 4.1.2 Verify legal_structure_iid exists and is PARTNERSHIP type
- [x] 4.1.3 Query existing LegalMechanisms for this Legal Structure
- [x] 4.1.4 Verify Core mechanisms exist (VOTING + AUTHORISATION_SOURCE types)
- [x] 4.1.5 Verify no Treasury mechanisms exist (RAC + TREASURY types)
- [x] 4.1.6 Retrieve Core mechanism deployment details (contract addresses, prefix)
- [x] 4.1.7 Verify admin_partner_slot_address is a Legal Structure partner
- [x] 4.1.8 Verify admin_partner_slot_address is a TaskManager admin
- [x] 4.1.9 Verify authz_admin_slot_address is an AuthzDiamond admin
- [x] 4.1.10 Verify deployer_account_iid has SIGNER slot
- [x] 4.1.11 Return: `prefix`, `authz_diamond_contract_address`, `task_manager_contract_address`
- [x] 4.1.12 COMP: No-op

#### Step 2: create_rac_legal_mechanism
**File**: `create_rac_mechanism.go`

- [x] 4.2.1 Generate IID for LegalMechanism
- [x] 4.2.2 Create LegalMechanism with Type=RAC, LegalStructureIid
- [x] 4.2.3 Store slot_address = "{prefix}-RAC" in metadata
- [x] 4.2.4 Return `rac_mechanism_iid`, `rac_diamond_slot_address`
- [x] 4.2.5 COMP: Delete LegalMechanism record

#### Step 3: create_treasury_legal_mechanism
**File**: `create_treasury_mechanism.go`

- [x] 4.3.1 Generate IID for LegalMechanism
- [x] 4.3.2 Create LegalMechanism with Type=TREASURY, LegalStructureIid
- [x] 4.3.3 Store slot_address = "{prefix}-Trezor" in metadata
- [x] 4.3.4 Return `treasury_mechanism_iid`, `treasury_diamond_slot_address`
- [x] 4.3.5 COMP: Delete LegalMechanism record

#### Step 8: create_rac_deployment_record
**File**: `create_rac_deployment.go`

- [x] 4.4.1 Get `rac_diamond_contract_address` from step 4
- [x] 4.4.2 Create LegalMechanismDeployment with Type=LASER
- [x] 4.4.3 Return `rac_deployment_iid`
- [x] 4.4.4 COMP: Delete deployment record

#### Step 18: create_treasury_deployment_record
**File**: `create_treasury_deployment.go`

- [x] 4.5.1 Get `trezor_diamond_contract_address` from step 9
- [x] 4.5.2 Create LegalMechanismDeployment with Type=LASER
- [x] 4.5.3 Return `treasury_deployment_iid`
- [x] 4.5.4 COMP: Delete deployment record

#### Executor Registration
**File**: `saga.go`

- [x] 4.6.1 Create `RunExecutorsAsync()` function for steps 1, 2, 3, 8, 18

**File**: `pkg/daemons/accmgr/trax/executors/run.go`

- [x] 4.6.2 Add call to new saga's `RunExecutorsAsync()`

---

### Phase 5: LASERSVC Executors

**Directory**: `pkg/daemons/lasersvc/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/` (NEW)

#### Step 4: deploy_rac_diamond_contract
**File**: `deploy_rac_diamond.go`

- [x] 5.1.1 Execute LASER mutation DEPLOY_DIAMOND (generic diamond)
- [x] 5.1.2 Contract name = `{prefix}-RAC`
- [x] 5.1.3 Return `rac_diamond_contract_address`, `rac_deploy_tx_hash`
- [x] 5.1.4 COMP: No-op (immutable)

#### Step 5: initialize_rac_diamond
**File**: `initialize_rac_diamond.go`

- [x] 5.2.1 Execute LASER mutation INITIALIZE_DIAMOND
- [x] 5.2.2 Admin = admin_partner_slot_address
- [x] 5.2.3 Return `rac_init_tx_hash`
- [x] 5.2.4 COMP: No-op

#### Step 6: grant_add_facets_permission_to_admin_rac
**File**: `grant_add_facets_perm_rac.go`

- [x] 5.3.1 Signer = authz_admin_slot_address
- [x] 5.3.2 Execute LASER mutation to grant permission on RAC diamond
- [x] 5.3.3 Permission: addFacets(address[]) to admin_partner_slot_address
- [x] 5.3.4 Return `grant_add_facets_rac_tx_hash`
- [x] 5.3.5 COMP: No-op

#### Step 7: add_rac_facet_to_rac_diamond
**File**: `add_rac_facet.go`

- [x] 5.4.1 Signer = admin_partner_slot_address
- [x] 5.4.2 Get RAC facet address from lattice (using rac_facet_version)
- [x] 5.4.3 Execute LASER mutation DIAMOND_ADD_FACETS
- [x] 5.4.4 Return `add_rac_facet_tx_hash`
- [x] 5.4.5 COMP: No-op

#### Step 9: deploy_trezor_diamond_contract
**File**: `deploy_trezor_diamond.go`

- [x] 5.5.1 Execute LASER mutation DEPLOY_DIAMOND
- [x] 5.5.2 Contract name = `{prefix}-Trezor`
- [x] 5.5.3 Return `trezor_diamond_contract_address`, `trezor_deploy_tx_hash`
- [x] 5.5.4 COMP: No-op

#### Step 10: initialize_trezor_diamond
**File**: `initialize_trezor_diamond.go`

- [x] 5.6.1 Execute LASER mutation INITIALIZE_DIAMOND
- [x] 5.6.2 Admin = admin_partner_slot_address
- [x] 5.6.3 Return `trezor_init_tx_hash`
- [x] 5.6.4 COMP: No-op

#### Step 11: grant_add_facets_permission_to_admin_trezor
**File**: `grant_add_facets_perm_trezor.go`

- [x] 5.7.1 Signer = authz_admin_slot_address
- [x] 5.7.2 Execute LASER mutation to grant permission on Trezor diamond
- [x] 5.7.3 Permission: addFacets(address[]) to admin_partner_slot_address
- [x] 5.7.4 Return `grant_add_facets_trezor_tx_hash`
- [x] 5.7.5 COMP: No-op

#### Step 12: add_vault_facets_to_trezor_diamond
**File**: `add_vault_facets.go`

- [x] 5.8.1 Signer = admin_partner_slot_address
- [x] 5.8.2 Get all facet addresses from lattice:
  - erc20-vault-admin (version input)
  - erc20-vault (version input)
  - ledger-lister (version input)
  - rbac (version input)
  - props (version input)
  - activity-store (version input)
  - eth-vault (version input)
- [x] 5.8.3 Execute LASER mutation DIAMOND_ADD_FACETS with all 7 facets
- [x] 5.8.4 Return `add_vault_facets_tx_hash`
- [x] 5.8.5 COMP: No-op

#### Step 13: grant_create_ledger_permission
**File**: `grant_create_ledger_perm.go`

- [x] 5.9.1 Signer = authz_admin_slot_address
- [x] 5.9.2 Execute LASER mutation to grant createLedger permission to admin-partner
- [x] 5.9.3 Return `grant_create_ledger_tx_hash`
- [x] 5.9.4 COMP: No-op

#### Step 14: create_default_ledger
**File**: `create_default_ledger.go`

- [x] 5.10.1 Signer = admin_partner_slot_address
- [x] 5.10.2 Execute LASER mutation to call createLedger("DEFAULT") on Trezor
- [x] 5.10.3 Ledger is non-slave, gets id=1
- [x] 5.10.4 Return `create_ledger_tx_hash`, `default_ledger_id` (should be "1")
- [x] 5.10.5 COMP: No-op

#### Step 15: grant_set_address_permission
**File**: `grant_set_address_perm.go`

- [x] 5.11.1 Signer = authz_admin_slot_address
- [x] 5.11.2 Execute LASER mutation to grant setAddress permission to admin-partner
- [x] 5.11.3 Return `grant_set_address_tx_hash`
- [x] 5.11.4 COMP: No-op

#### Step 16: grant_set_int_permission
**File**: `grant_set_int_perm.go`

- [x] 5.12.1 Signer = authz_admin_slot_address
- [x] 5.12.2 Execute LASER mutation to grant setInt permission to admin-partner
- [x] 5.12.3 Return `grant_set_int_tx_hash`
- [x] 5.12.4 COMP: No-op

#### Step 17: configure_rac_properties
**File**: `configure_rac_properties.go`

- [x] 5.13.1 Signer = admin_partner_slot_address
- [x] 5.13.2 Execute LASER mutation to call setInt("rac.domain.id", 999)
- [x] 5.13.3 Execute LASER mutation to call setAddress("rac.address", rac_diamond_contract_address)
- [x] 5.13.4 Return `configure_rac_tx_hash`
- [x] 5.13.5 COMP: No-op

#### Executor Registration
**File**: `saga.go`

- [x] 5.14.1 Create `RunExecutorsAsync()` function for steps 4-7, 9-17

**File**: `pkg/daemons/lasersvc/trax/executors/run.go`

- [x] 5.14.2 Add call to new saga's `RunExecutorsAsync()`

---

### Phase 6: E2E Tests

**File**: `tests/e2e/laser/treasury_mechanism_deployment_test.go` (NEW)

#### Test Setup Functions

- [x] 6.1.1 `setupTestDatabaseForTreasuryMechanisms(t)` - reuse Diamond test setup
- [x] 6.1.2 `deployCoreLegalMechanismsPrereq(t, legalStructureIid)` - deploy Core mechanisms first

#### Green Path Tests

- [x] 6.2.1 `TestDeployTreasuryLegalMechanisms_FullFlow`
  - Setup: Create deployer, 5 partners, legal structure
  - Deploy Core Legal Mechanisms first
  - Submit Treasury saga with all valid inputs
  - Verify saga completes successfully
  - Verify LegalMechanism records created (RAC and TREASURY)
  - Verify LegalMechanismDeployment records with correct addresses
  - Verify contract addresses are valid ETH addresses

- [ ] 6.2.2 `TestDeployTreasuryLegalMechanisms_VerifyContracts` *(NOT IMPLEMENTED - optional enhancement)*
  - Deploy full flow
  - Use LASER queries to verify:
    - RAC diamond has RAC facet
    - Trezor diamond has all 7 vault facets
    - DEFAULT ledger exists with id=1
    - rac.domain.id = 999
    - rac.address = RAC contract address

#### Red Path Tests

- [x] 6.3.1 `TestDeployTreasuryLegalMechanisms_MissingCoreMechanisms`
  - Create legal structure WITHOUT deploying Core
  - Submit Treasury saga
  - Verify saga fails at step 1 (Core mechanisms not found)

- [x] 6.3.2 `TestDeployTreasuryLegalMechanisms_DuplicateTreasury`
  - Deploy Treasury successfully
  - Attempt second Treasury deployment
  - Verify saga fails at step 1 (Treasury already exists)

- [ ] 6.3.3 `TestDeployTreasuryLegalMechanisms_InvalidAdminPartner` *(NOT IMPLEMENTED - optional enhancement)*
  - Use admin_partner_slot_address that is NOT a Legal Structure partner
  - Verify saga fails at step 1

- [ ] 6.3.4 `TestDeployTreasuryLegalMechanisms_AdminNotTaskManagerAdmin` *(NOT IMPLEMENTED - optional enhancement)*
  - Use admin_partner_slot_address that is partner but NOT TaskManager admin
  - Verify saga fails at step 1

- [ ] 6.3.5 `TestDeployTreasuryLegalMechanisms_InvalidAuthzAdmin` *(NOT IMPLEMENTED - optional enhancement)*
  - Use authz_admin_slot_address that is NOT an AuthzDiamond admin
  - Verify saga fails at step 1

- [ ] 6.3.6 `TestDeployTreasuryLegalMechanisms_InvalidFacetVersion` *(NOT IMPLEMENTED - optional enhancement)*
  - Use non-existent facet version
  - Verify saga fails at facet addition step

#### Additional Tests Implemented (not in original TODO)

- [x] `TestDeployTreasuryLegalMechanisms_MissingExecRuntimeName` - Validation error test
- [x] `TestDeployTreasuryLegalMechanisms_MissingLegalStructureIid` - Validation error test
- [x] `TestDeployTreasuryLegalMechanisms_MissingAdminPartnerSlotAddress` - Validation error test
- [x] `TestDeployTreasuryLegalMechanisms_MissingAuthzAdminSlotAddress` - Validation error test
- [x] `TestDeployTreasuryLegalMechanisms_MissingRacFacetVersion` - Validation error test
- [x] `TestDeployTreasuryLegalMechanisms_InvalidLegalStructure` - Non-existent legal structure test

---

### Phase 7: Documentation

**File**: `docs/SUMMARY-FOR-AGENT.md`

- [x] 7.1.1 Add section on Treasury Legal Mechanism deployment saga
- [x] 7.1.2 Document saga inputs/outputs
- [x] 7.1.3 Document relationship: Core mechanisms -> Treasury mechanisms
- [x] 7.1.4 Document two-diamond architecture (RAC + Trezor)

---

## Data Flow Diagram

```
[Prerequisites: Core Legal Mechanisms Deployed]
    |
    v
[Saga Submit: deploy_treasury_legal_mechanisms_for_legal_structure]
    |
    v
[Step 1: verify_treasury_mechanism_inputs] (ACCMGR)
    |-- VALIDATE: Core mechanisms exist, no Treasury exists
    |-- VALIDATE: admin_partner is partner + TM admin
    |-- VALIDATE: authz_admin is AuthzDiamond admin
    |-- OUTPUT: prefix, authz_diamond_address, task_manager_address
    v
[Step 2: create_rac_legal_mechanism] (ACCMGR)
    |-- CREATE: LegalMechanism (RAC), slot_address = {prefix}-RAC
    v
[Step 3: create_treasury_legal_mechanism] (ACCMGR)
    |-- CREATE: LegalMechanism (TREASURY), slot_address = {prefix}-Trezor
    v
[Step 4: deploy_rac_diamond_contract] (LASERSVC)
    |-- LASER: DEPLOY_DIAMOND (deployer signs)
    |-- OUTPUT: rac_diamond_contract_address
    v
[Step 5: initialize_rac_diamond] (LASERSVC)
    |-- LASER: INITIALIZE_DIAMOND (admin-partner as admin)
    v
[Step 6: grant_add_facets_permission_to_admin_rac] (LASERSVC)
    |-- LASER: authz-admin grants addFacets to admin-partner on RAC
    v
[Step 7: add_rac_facet_to_rac_diamond] (LASERSVC)
    |-- LASER: admin-partner adds RAC facet
    v
[Step 8: create_rac_deployment_record] (ACCMGR)
    |-- CREATE: LegalMechanismDeployment (LASER) with RAC address
    v
[Step 9: deploy_trezor_diamond_contract] (LASERSVC)
    |-- LASER: DEPLOY_DIAMOND (deployer signs)
    |-- OUTPUT: trezor_diamond_contract_address
    v
[Step 10: initialize_trezor_diamond] (LASERSVC)
    |-- LASER: INITIALIZE_DIAMOND (admin-partner as admin)
    v
[Step 11: grant_add_facets_permission_to_admin_trezor] (LASERSVC)
    |-- LASER: authz-admin grants addFacets to admin-partner on Trezor
    v
[Step 12: add_vault_facets_to_trezor_diamond] (LASERSVC)
    |-- LASER: admin-partner adds 7 vault facets (b-h)
    v
[Step 13: grant_create_ledger_permission] (LASERSVC)
    |-- LASER: authz-admin grants createLedger to admin-partner
    v
[Step 14: create_default_ledger] (LASERSVC)
    |-- LASER: admin-partner creates "DEFAULT" ledger (id=1)
    v
[Step 15: grant_set_address_permission] (LASERSVC)
    |-- LASER: authz-admin grants setAddress to admin-partner
    v
[Step 16: grant_set_int_permission] (LASERSVC)
    |-- LASER: authz-admin grants setInt to admin-partner
    v
[Step 17: configure_rac_properties] (LASERSVC)
    |-- LASER: admin-partner calls setInt("rac.domain.id", 999)
    |-- LASER: admin-partner calls setAddress("rac.address", RAC_addr)
    v
[Step 18: create_treasury_deployment_record] (ACCMGR)
    |-- CREATE: LegalMechanismDeployment (LASER) with Trezor address
    v
[SAGA COMMITTED]
```

---

## Service Execution Summary

```
ACCMGR (5 steps):    1 -> 2 -> 3 -----------------> 8 ----------------------> 18
                                  \                   \                          \
LASERSVC (13 steps):               4 -> 5 -> 6 -> 7    9 -> 10 -> 11 -> 12 -> 13 -> 14 -> 15 -> 16 -> 17
```

---

## Files Summary

### New Files

| File | Description |
|------|-------------|
| `pkg/trax/templates/agora/csd/deploy_treasury_legal_mechanisms_for_legal_structure.go` | Saga template (18 steps) |
| `pkg/daemons/accmgr/api/v1/legal_mechanisms_post_deploy_treasury.go` | REST endpoint |
| `pkg/daemons/accmgr/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/saga.go` | ACCMGR executor registration |
| `pkg/daemons/accmgr/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/verify_inputs.go` | Step 1 |
| `pkg/daemons/accmgr/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/create_rac_mechanism.go` | Step 2 |
| `pkg/daemons/accmgr/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/create_treasury_mechanism.go` | Step 3 |
| `pkg/daemons/accmgr/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/create_rac_deployment.go` | Step 8 |
| `pkg/daemons/accmgr/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/create_treasury_deployment.go` | Step 18 |
| `pkg/daemons/lasersvc/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/saga.go` | LASERSVC executor registration |
| `pkg/daemons/lasersvc/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/deploy_rac_diamond.go` | Step 4 |
| `pkg/daemons/lasersvc/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/initialize_rac_diamond.go` | Step 5 |
| `pkg/daemons/lasersvc/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/grant_add_facets_perm_rac.go` | Step 6 |
| `pkg/daemons/lasersvc/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/add_rac_facet.go` | Step 7 |
| `pkg/daemons/lasersvc/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/deploy_trezor_diamond.go` | Step 9 |
| `pkg/daemons/lasersvc/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/initialize_trezor_diamond.go` | Step 10 |
| `pkg/daemons/lasersvc/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/grant_add_facets_perm_trezor.go` | Step 11 |
| `pkg/daemons/lasersvc/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/add_vault_facets.go` | Step 12 |
| `pkg/daemons/lasersvc/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/grant_create_ledger_perm.go` | Step 13 |
| `pkg/daemons/lasersvc/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/create_default_ledger.go` | Step 14 |
| `pkg/daemons/lasersvc/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/grant_set_address_perm.go` | Step 15 |
| `pkg/daemons/lasersvc/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/grant_set_int_perm.go` | Step 16 |
| `pkg/daemons/lasersvc/trax/executors/deploy_treasury_legal_mechanisms_for_legal_structure/configure_rac_properties.go` | Step 17 |
| `tests/e2e/laser/treasury_mechanism_deployment_test.go` | E2E tests |

### Modified Files

| File | Changes |
|------|---------|
| `pkg/trax/templates/agora/csd/index.go` | Register new saga template |
| `pkg/daemons/accmgr/api/v1/api.go` | Add route for POST /legal-mechanisms/deploy-treasury |
| `pkg/daemons/accmgr/trax/executors/run.go` | Register ACCMGR executors |
| `pkg/daemons/lasersvc/trax/executors/run.go` | Register LASERSVC executors |
| `docs/SUMMARY-FOR-AGENT.md` | Document Treasury legal mechanism deployment |

---

## Success Criteria

- [ ] Domain model has RAC type enum
- [ ] Saga template registered correctly (verify via traxcli)
- [ ] All 18 step executors start without errors
- [ ] Green path E2E tests pass (EthBC mode)
- [ ] Red path E2E tests pass (validation failures)
- [ ] RAC diamond deployed with RAC facet
- [ ] Trezor diamond deployed with all 7 vault facets
- [ ] DEFAULT ledger created with id=1
- [ ] RAC properties configured (rac.domain.id=999, rac.address=RAC_addr)
- [ ] Deployment records created with correct contract addresses
- [ ] Documentation updated

---

## Implementation Order

1. Phase 1: Domain Model Updates (add RAC type)
2. Phase 2: Saga Template (18 steps)
3. Phase 3: API Endpoint
4. Phase 4: ACCMGR Step Executors (steps 1, 2, 3, 8, 18)
5. Phase 5: LASERSVC Step Executors (steps 4-7, 9-17)
6. Phase 6: E2E Tests
7. Phase 7: Documentation

---

## Notes

- **EthBC-only**: This saga only works with real Ethereum blockchain, not RDBMS mode
- **Immutable contracts**: LASER contract deployments cannot be compensated (on-chain immutability)
- **Two-diamond architecture**: RAC (access control) and Trezor (vault/ledger) are separate diamonds
- **Permission flow**: authz-admin grants permissions, admin-partner executes operations
- **Core dependency**: This saga REQUIRES Core Legal Mechanisms to be deployed first
- **Prefix reuse**: Uses same prefix as Core deployment (retrieved from existing records)
- **RAC integration**: RAC diamond uses AuthzDiamond from Core for permission checks
- **Facets from lattice**: All 8 facets are pre-deployed in lattice archive, referenced by version
- **Ledger naming**: DEFAULT ledger always gets id=1 as the first non-slave ledger

---

## CRITICAL: Trezor-to-RAC Cross-Diamond Authorization

### Background

When the Trezor Diamond (Treasury) executes vault operations like `depositToErc20Vault`, `withdrawFromErc20VaultTo`, or `transferFromErc20Vault`, it internally calls the **RAC Diamond's protected functions** (e.g., `updateResourceQuota`).

### The Problem

The RAC Diamond uses the same AuthzSource (AuthzDiamond with SimpleAuthzFacet) as other diamonds. When Trezor calls RAC:
1. The `msg.sender` is the **Trezor Diamond's contract address**
2. RAC Diamond checks if this caller is authorized via SimpleAuthzFacet
3. If Trezor is NOT in the whitelist → `DMND:NAUTH` error

### Evidence from Contracts

**RACFacet.sol** - `updateResourceQuota` is PROTECTED:
```solidity
function getFacetProtectedPI() external pure override returns (string[] memory) {
    pi[12] = "updateResourceQuota(address[],bytes32,bytes32,bytes32,uint256,uint256)";
}
```

**Erc20VaultInternal.sol** - Trezor calls RAC:
```solidity
function _depositToErc20Vault(...) internal {
    IRAC rac = IRAC(PropsLib._getAddress("rac.address", true));
    rac.updateResourceQuota(...);  // CROSS-DIAMOND CALL TO PROTECTED FUNCTION!
}
```

### Required Fix: Grant Trezor Access to RAC's AuthzSource

**This saga MUST include a step to add Trezor Diamond to the AuthzSource whitelist.**

#### Proposed New Step (after Step 17, before Step 18)

| Step | Name | Service | Description |
|------|------|---------|-------------|
| 17b | `grant_treasury_rac_access` | **lasersvc** | authz-admin adds Trezor Diamond to AuthzSource whitelist |

#### Implementation

```go
// Step 17b: Grant Trezor access to call RAC's protected functions
// Signer: authz_admin_slot_address
// Target: authz_source_diamond_slot_address
// Account to add: trezor_diamond_contract_address

funcDecl := ats.Func(string(model.OperationNameEnum_SimpleAuthzAddAccount)).
    Arguments(
        ats.String(string(ats.ArgNameEnum_LedgerContractSlotAddress)).Build(),
        ats.String(string(ats.ArgNameEnum_Account)).Build(),
    ).Build()

arguments := ats.NewBoundTuple().
    AddVar(ats.String(string(ats.ArgNameEnum_LedgerContractSlotAddress)).Build(), authzSourceDiamondSlotAddress).
    AddVar(ats.String(string(ats.ArgNameEnum_Account)).Build(), trezorDiamondContractAddress).
    Build()
```

### Why This Wasn't Caught Earlier

- The issue only manifests when **Fund Account saga** tries to deposit tokens to Treasury
- Deploy Treasury saga completes successfully (no deposits during deployment)
- The error appears as `DMND:NAUTH` in Fund Account step 3 or step 5

### See Also

- `docs/TODO_DEPLOY_CASH_TOKEN_LEGAL_MECHANISM_SAGA.md` - Contains detailed analysis
- `docs/PROTECTED_FUCTION_PROXY_CALL_FLOW_IN_LATTICE.md` - Authorization flow documentation
- `docs/DIAMOND_OVERVIEW.md` - Diamond architecture and DMND:NAUTH error

---

## Solidity Contracts Reference

> **Repository**: `/Users/kam/repos/NEW2/qomet/contracts`

### Diamond Core Architecture

| Contract | Path | Description |
|----------|------|-------------|
| Diamond.sol | `contracts/diamond/Diamond.sol` | Main proxy contract using Diamond Pattern. Key functions: `initialize()`, `addFacets()`, `setAuthzSource()` |
| FacetManager.sol | `contracts/diamond/FacetManager.sol` | Library managing facet lifecycle: `_addFacet()`, `_addFacets()`, `_deleteFacets()` |
| DiamondFactory.sol | `contracts/diamond/DiamondFactory.sol` | Factory for creating new Diamond instances |
| IDiamondFacet.sol | `contracts/diamond/IDiamondFacet.sol` | Interface all facets must implement: `getFacetName()`, `getFacetVersion()`, `getFacetPI()` |

### RAC (Resource Access Controller) Facet

| Contract | Path | Version | Description |
|----------|------|---------|-------------|
| IRAC.sol | `contracts/facets/rac/IRAC.sol` | - | Central access control interface |
| RACFacet.sol | `contracts/facets/rac/RACFacet.sol` | 2.4.0 | Implements IRAC with 26 public functions |
| RACInternal.sol | `contracts/facets/rac/RACInternal.sol` | - | Internal implementation (global/domain/zone/resource quotas) |

**RAC Constants**:
```solidity
RAC_ZONE_ID = keccak256(bytes("RAC"))
RAC_OK = 0
RAC_ERROR_LOCKED = 1001
RAC_ERROR_ACCESS_CAP_EXCEEDED = 1002
RAC_ERROR_TOTAL_CAP_EXCEEDED = 1003
RAC_ERROR_BLACKLISTED_ACCOUNT = 1004
RAC_ERROR_NOT_IN_WHITELIST = 1005
```

### Props (Properties/Configuration) Facet

| Contract | Path | Version | Description |
|----------|------|---------|-------------|
| PropsFacet.sol | `contracts/facets/props/PropsFacet.sol` | 1.2.0 | Key-value configuration storage |
| PropsInternal.sol | `contracts/facets/props/PropsInternal.sol` | - | Internal implementation |

**Key Functions**:
```solidity
// Integer properties
getInt(string key, bool revertIfMissing) -> uint256
setInt(string[] keyArr, uint256[] valueArr)

// Address properties
getAddress(string key, bool revertIfMissing) -> address
setAddress(string[] keyArr, address[] valueArr)
```

**Configuration Keys Used**:
- `"rac.address"` - Address of RAC contract
- `"rac.domain.id"` - RAC domain identifier (uint256, e.g., 999)

### ERC20 Vault Facets

| Contract | Path | Version | Description |
|----------|------|---------|-------------|
| Erc20VaultFacet.sol | `contracts/facets/_trezor/erc20-vault/Erc20VaultFacet.sol` | 2.5.0 | ERC20 vault operations |
| Erc20VaultAdminFacet.sol | `contracts/facets/_trezor/erc20-vault/Erc20VaultAdminFacet.sol` | 2.5.0 | Admin functions (BALANCE_MANAGER_ROLE) |
| Erc20VaultInternal.sol | `contracts/facets/_trezor/erc20-vault/Erc20VaultInternal.sol` | - | Internal implementation |

**Key Functions**:
```solidity
getErc20VaultBalance(uint256 ledgerId, address erc20, address vault, uint256 stash)
depositToErc20Vault(uint256, address, address, address, address, uint256, bytes)
withdrawFromErc20VaultTo(uint256, address, address, address, uint256, bytes)
transferFromErc20Vault(uint256, address, address, address, address, uint256, bytes)
```

### ETH Vault Facet

| Contract | Path | Version | Description |
|----------|------|---------|-------------|
| EthVaultFacet.sol | `contracts/facets/_trezor/eth-vault/EthVaultFacet.sol` | 2.3.0 | Native ETH vault operations |
| EthVaultAdminFacet.sol | `contracts/facets/_trezor/eth-vault/EthVaultAdminFacet.sol` | 2.3.0 | Admin functions |

**Key Functions**:
```solidity
getEthVaultBalance(uint256 ledgerId, address vault, uint256 stash)
depositToEthVault(uint256, address, address, bytes) payable
withdrawFromEthVaultTo(uint256, address, address, address, uint256, bytes)
```

### Ledger-Lister Facet

| Contract | Path | Version | Description |
|----------|------|---------|-------------|
| LedgerListerFacet.sol | `contracts/facets/_trezor/ledger-lister/LedgerListerFacet.sol` | 1.0.1 | Ledger management |
| LedgerListerInternal.sol | `contracts/facets/_trezor/ledger-lister/LedgerListerInternal.sol` | - | Internal implementation |

**Key Functions**:
```solidity
getNrOfLedgers() -> uint256
getLedgerInfo(uint256 ledgerId) -> (string name, bool slave, string[] tags)
createLedger(string name, bool slave, string[] tags)  // Returns ledger ID (starts at 1)
setLedgerName(uint256 ledgerId, string name)
setLedgerTags(uint256 ledgerId, string[] tags)
```

**Ledger Storage**:
```solidity
struct Ledger {
    uint256 id;
    string name;
    bool slave;       // slave ledgers track on-chain balances only
    string[] tags;
}
```

### Activity Store Facet

| Contract | Path | Version | Description |
|----------|------|---------|-------------|
| ActivityStoreFacet.sol | `contracts/facets/_trezor/activity-store/ActivityStoreFacet.sol` | 1.2.1 | Activity audit log |
| ActivityStoreInternal.sol | `contracts/facets/_trezor/activity-store/ActivityStoreInternal.sol` | - | Internal implementation |

**Key Functions**:
```solidity
getNrOfActivities() -> uint256
getActivities(uint256 afterId) -> Activity[]
getActivitiesByHash(bytes32[] hashArr) -> Activity[]
```

### RBAC Facet

| Contract | Path | Version | Description |
|----------|------|---------|-------------|
| RBACFacet.sol | `contracts/facets/rbac/RBACFacet.sol` | 1.0.1 | Role-Based Access Control |

**Key Functions**:
```solidity
hasRole(address account, uint256 role) -> bool
grantRole(uint256 taskId, string taskManagerKey, address account, uint256 role)
revokeRole(uint256 taskId, string taskManagerKey, address account, uint256 role)
```

### Trezor Constants

**File**: `contracts/facets/_trezor/Constants.sol`

```solidity
// Operations
DEPOSIT_OP = 100
WITHDRAW_OP = 200
ANY_OP = 1000

// Roles
BALANCE_MANAGER_ROLE = uint256(0x046f87342...)

// Stashes
DEFAULT_LIQUID_STASH = 0
TOTAL_BALANCE_STASH = 1
```

### Typical Diamond Initialization Flow

```solidity
1. Create Diamond via DiamondFactory.createDiamond()
2. Call Diamond.initialize() with:
   - Default facets array
   - Protected function signatures
   - Authz configuration
3. Set Props via PropsFacet.setAddress(["rac.address"], [racAddress])
4. Set Props via PropsFacet.setInt(["rac.domain.id"], [domainId])
5. Create Ledger via LedgerListerFacet.createLedger("DEFAULT", false, [])
6. Add additional Facets via Diamond.addFacets(address[])
```

### Multi-Level Access Control Architecture

```
Global Level
  ├─ Domain Level (rac.domain.id)
  │   ├─ Zone Level
  │   │   ├─ Resource Level (operations: DEPOSIT, WITHDRAW, ANY)
```