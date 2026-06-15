# TODO: Deploy Core Legal Mechanisms for Legal Structure - TRAX Saga Implementation

> **Status**: COMPLETED
> **Created**: 2026-01-02
> **Completed**: 2026-01-02

## Overview

TRAX saga template `deploy_core_legal_mechanisms_for_legal_structure` that deploys governance mechanisms (TaskManagerV2 and AuthzDiamond) for an existing legal structure (PARTNERSHIP). This saga is EthBC-only and requires LASER for all contract operations.

---

## Saga Specification

### Inputs

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| exec_runtime_name | string | Yes | Execution runtime for deployments (e.g., "primary") |
| locale | string | Yes | Locale for display names (e.g., "en-US") |
| prefix | string | Yes | Prefix for mechanism names (e.g., "ACME" -> "ACME-TaskManager") |
| legal_structure_iid | string | Yes | IID of the parent legal structure |
| task_manager_admins | []string (JSON) | Yes | Partner account IIDs for TM admin role |
| task_manager_approvers | []string (JSON) | Yes | Partner account IIDs for TM approver role |
| task_manager_executors | []string (JSON) | Yes | Partner account IIDs for TM executor role |
| bypass_mode | bool | No | TaskManager bypass mode (default: false) |
| authz_source_diamond_admins | []string (JSON) | Yes | 2 partner account IIDs for AuthzDiamond admin role |
| authz_admins | []string (JSON) | Yes | 2 DIFFERENT partner account IIDs for Authz admin role |
| authz_facet_version | string | Yes | AuthzFacet version from lattice archive (e.g., "v3.1.0") |
| deployer_account_iid | string | Yes | Account IID with SIGNER slot for deployments |
| deployer_slot_address | string | Yes | LASER slot address for contract deployments |

### Validation Rules
- `authz_source_diamond_admins` and `authz_admins` must have NO overlap (4 different partners)
- `deployer_account_iid` must have an active SIGNER-tagged slot
- `legal_structure_iid` must reference an existing PARTNERSHIP legal structure
- All partner account IIDs must be ACTIVE with SIGNER-tagged slots

### Steps and Service Ownership

| Step | Name | Service | Description |
|------|------|---------|-------------|
| 1 | `verify_legal_mechanism_inputs` | **accmgr** | Validate inputs, verify legal structure exists, verify all accounts have SIGNER slots |
| 2 | `create_task_manager_legal_mechanism` | **accmgr** | Create LegalMechanism record (type=VOTING) with slot address PREFIX-TaskManager |
| 3 | `create_authz_source_legal_mechanism` | **accmgr** | Create LegalMechanism record (type=AUTHORISATION_SOURCE) with slot address PREFIX-AuthzSource |
| 4 | `deploy_task_manager_contract` | **lasersvc** | Deploy TaskManagerV2 via LASER using deployer signer |
| 5 | `create_task_manager_deployment_record` | **accmgr** | Create LegalMechanismDeployment for TaskManager with contract address |
| 6 | `deploy_authz_diamond_contract` | **lasersvc** | Deploy AuthzDiamond via LASER using deployer signer |
| 7 | `initialize_authz_diamond` | **lasersvc** | Initialize AuthzDiamond with TaskManager ref and admin groups |
| 8 | `create_authz_source_deployment_record` | **accmgr** | Create LegalMechanismDeployment for AuthzDiamond |
| 9 | `deploy_authz_facet` | **lasersvc** | Deploy AuthzFacet contract using deployer signer |
| 10 | `add_authz_facet_to_diamond` | **lasersvc** | Add facet to diamond using first AuthzDiamond admin as signer |

**Service Distribution**:
- **accmgr**: Steps 1, 2, 3, 5, 8 (legal mechanism domain records)
- **lasersvc**: Steps 4, 6, 7, 9, 10 (LASER contract operations)

---

## Phase 1: Domain Model Updates

### 1.1 Update LegalMechanism Type
**File**: `pkg/fin/legal_mechanism.go`

- [x] 1.1.1 Add `LegalStructureIid` field (required, string)

```go
type LegalMechanism struct {
    Iid         string          `json:"iid"`
    Identifiers []FinIdentifier `json:"identifiers"`

    Type LegalMechanismTypeEnum `json:"type"`

    // NEW FIELD: Link to parent legal structure
    LegalStructureIid string `json:"legal_structure_iid"`

    DisplayNames map[string]string `json:"display_names"`
    Descriptions map[string]string `json:"descriptions"`
    Labels       map[string]string `json:"labels"`
    Tags         []string          `json:"tags"`
    Metadata     map[string]string `json:"metadata"`
}
```

### 1.2 Update LegalMechanismDeployment Type
**File**: `pkg/fin/legal_mechanism_deployment.go`

- [x] 1.2.1 Add `LegalMechanismIid` field (required, string)

```go
type LegalMechanismDeployment struct {
    Iid         string          `json:"iid"`
    Identifiers []FinIdentifier `json:"identifiers"`

    Type LegalMechanismDeploymentTypeEnum `json:"type"`

    // NEW FIELD: Link to parent legal mechanism
    LegalMechanismIid string `json:"legal_mechanism_iid"`

    DeploymentDetails any `json:"deployment_details"`

    DisplayNames map[string]string `json:"display_names"`
    Descriptions map[string]string `json:"descriptions"`
    Labels       map[string]string `json:"labels"`
    Tags         []string          `json:"tags"`
    Metadata     map[string]string `json:"metadata"`
}
```

### 1.3 LaserLegalMechanismDeploymentDetails
**File**: `pkg/fin/legal_mechanism_deployment.go`

- [x] 1.3.1 No changes needed - SlotAddress already exists for contract address

---

## Phase 2: Database Schema Updates

**File**: `deploy/k8s/init/init_accmgr_pgsql.sql`

### 2.1 Create legal_mechanisms Table

- [x] 2.1.1 Add `accmgr.legal_mechanisms` table

```sql
CREATE TABLE IF NOT EXISTS accmgr.legal_mechanisms (
    iid VARCHAR PRIMARY KEY,
    identifiers JSONB NOT NULL DEFAULT '[]',
    type VARCHAR NOT NULL,
    legal_structure_iid VARCHAR NOT NULL,
    display_names JSONB NOT NULL DEFAULT '{}',
    descriptions JSONB NOT NULL DEFAULT '{}',
    labels JSONB NOT NULL DEFAULT '{}',
    tags JSONB NOT NULL DEFAULT '[]',
    metadata JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_legal_mechanisms_entity FOREIGN KEY (iid) REFERENCES shared.entities(iid) ON DELETE CASCADE,
    CONSTRAINT fk_legal_mechanisms_legal_structure FOREIGN KEY (legal_structure_iid) REFERENCES accmgr.legal_structures(iid)
);
CREATE INDEX IF NOT EXISTS idx_legal_mechanisms_legal_structure ON accmgr.legal_mechanisms(legal_structure_iid);
CREATE INDEX IF NOT EXISTS idx_legal_mechanisms_type ON accmgr.legal_mechanisms(type);
```

### 2.2 Create legal_mechanism_deployments Table

- [x] 2.2.1 Add `accmgr.legal_mechanism_deployments` table

```sql
CREATE TABLE IF NOT EXISTS accmgr.legal_mechanism_deployments (
    iid VARCHAR PRIMARY KEY,
    identifiers JSONB NOT NULL DEFAULT '[]',
    type VARCHAR NOT NULL,
    legal_mechanism_iid VARCHAR NOT NULL,
    deployment_details JSONB NOT NULL DEFAULT '{}',
    display_names JSONB NOT NULL DEFAULT '{}',
    descriptions JSONB NOT NULL DEFAULT '{}',
    labels JSONB NOT NULL DEFAULT '{}',
    tags JSONB NOT NULL DEFAULT '[]',
    metadata JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_legal_mechanism_deployments_entity FOREIGN KEY (iid) REFERENCES shared.entities(iid) ON DELETE CASCADE,
    CONSTRAINT fk_legal_mechanism_deployments_mechanism FOREIGN KEY (legal_mechanism_iid) REFERENCES accmgr.legal_mechanisms(iid)
);
CREATE INDEX IF NOT EXISTS idx_legal_mechanism_deployments_mechanism ON accmgr.legal_mechanism_deployments(legal_mechanism_iid);
CREATE INDEX IF NOT EXISTS idx_legal_mechanism_deployments_type ON accmgr.legal_mechanism_deployments(type);
```

---

## Phase 3: Store Interface & Implementation

### 3.1 Update AccountStore Interface
**File**: `pkg/daemons/accmgr/account_store.go`

- [x] 3.1.1 Add LegalMechanism CRUD methods:
  - `CreateLegalMechanism(ctx, lm *fin.LegalMechanism) error`
  - `GetLegalMechanismByIid(ctx, iid string) (*fin.LegalMechanism, error)`
  - `QueryLegalMechanisms(ctx, options *common.QueryOptions) ([]*fin.LegalMechanism, *common.QueryResponse, error)`
  - `QueryLegalMechanismsByLegalStructure(ctx, lsIid string, options *common.QueryOptions) ([]*fin.LegalMechanism, *common.QueryResponse, error)`
  - `UpdateLegalMechanism(ctx, lm *fin.LegalMechanism) error`
  - `DeleteLegalMechanism(ctx, iid string) error`

- [x] 3.1.2 Add LegalMechanismDeployment CRUD methods:
  - `CreateLegalMechanismDeployment(ctx, lmd *fin.LegalMechanismDeployment) error`
  - `GetLegalMechanismDeploymentByIid(ctx, iid string) (*fin.LegalMechanismDeployment, error)`
  - `QueryLegalMechanismDeployments(ctx, options *common.QueryOptions) ([]*fin.LegalMechanismDeployment, *common.QueryResponse, error)`
  - `QueryLegalMechanismDeploymentsByMechanism(ctx, lmIid string, options *common.QueryOptions) ([]*fin.LegalMechanismDeployment, *common.QueryResponse, error)`
  - `UpdateLegalMechanismDeployment(ctx, lmd *fin.LegalMechanismDeployment) error`
  - `DeleteLegalMechanismDeployment(ctx, iid string) error`

### 3.2 Implement PostgreSQL Store Methods
**File**: `pkg/daemons/accmgr/account_store_pgsql.go`

- [x] 3.2.1 Implement all LegalMechanism methods (follow CreateLegalStructure pattern)
- [x] 3.2.2 Implement all LegalMechanismDeployment methods
- [x] 3.2.3 Add transaction helper methods

### 3.3 Implement In-Memory Store Methods
**File**: `pkg/daemons/accmgr/account_store_inmem.go`

- [x] 3.3.1 Add `legalMechanisms map[string]*fin.LegalMechanism` field
- [x] 3.3.2 Add `legalMechanismDeployments map[string]*fin.LegalMechanismDeployment` field
- [x] 3.3.3 Implement all interface methods

---

## Phase 4: TRAX Saga Template

### 4.1 Create Saga Template File
**File**: `pkg/trax/templates/agora/csd/deploy_core_legal_mechanisms_for_legal_structure.go` (NEW)

- [x] 4.1.1 Define `SagaTemplate` with TemplateId: `deploy_core_legal_mechanisms_for_legal_structure`
- [x] 4.1.2 Define 10 `SagaStepTemplate` records with proper ordering and service labels
- [x] 4.1.3 Create `CreateDeployCoreLegalMechanismsForLegalStructureSagaTemplates()` function

### 4.2 Register Saga Template
**File**: `pkg/trax/templates/agora/csd/index.go`

- [x] 4.2.1 Add call to new template creation function

---

## Phase 5: API Endpoints

### 5.1 Create REST Endpoint for Saga Submission
**File**: `pkg/daemons/accmgr/api/v1/legal_mechanisms_post_deploy.go` (NEW)

- [x] 5.1.1 Create `deployCoreLegalMechanismsRequest` struct with all saga inputs
- [x] 5.1.2 Create `deployCoreLegalMechanismsResponse` struct
- [x] 5.1.3 Implement `postDeployCoreLegalMechanisms(c *gin.Context)` handler
- [x] 5.1.4 Validate required fields (exec_runtime_name, locale, prefix, legal_structure_iid, etc.)
- [x] 5.1.5 Validate authz_source_diamond_admins and authz_admins have no overlap
- [x] 5.1.6 Marshal arrays to JSON strings for saga input
- [x] 5.1.7 Submit saga via `traxSagaSubmitter.SubmitSaga()`
- [x] 5.1.8 Return saga_instance_id on success

```go
type deployCoreLegalMechanismsRequest struct {
    ExecRuntimeName      string   `json:"exec_runtime_name"`
    Locale               string   `json:"locale"`
    Prefix               string   `json:"prefix"`
    LegalStructureIid    string   `json:"legal_structure_iid"`
    TaskManagerAdmins    []string `json:"task_manager_admins"`
    TaskManagerApprovers []string `json:"task_manager_approvers"`
    TaskManagerExecutors []string `json:"task_manager_executors"`
    BypassMode           bool     `json:"bypass_mode,omitempty"`
    AuthzDiamondAdmins   []string `json:"authz_source_diamond_admins"`
    AuthzAdmins          []string `json:"authz_admins"`
    AuthzFacetVersion    string   `json:"authz_facet_version"`
    DeployerAccountIid   string   `json:"deployer_account_iid"`
    DeployerSlotAddress  string   `json:"deployer_slot_address"` // LASER slot address for contract deployments
}
```

### 5.2 Register Endpoint
**File**: `pkg/daemons/accmgr/api/v1/api.go`

- [x] 5.2.1 Add route: `POST /legal-mechanisms/deploy-core` -> `postDeployCoreLegalMechanisms`

---

## Phase 6: Saga Step Executors

> **Note**: The authz_source_diamond_admins and authz_admins are provided as saga inputs (account IIDs).
> E2E tests must use first 2 partners as authz_source_diamond_admins and next 2 partners as authz_admins.

### ACCMGR Executors
**Directory**: `pkg/daemons/accmgr/trax/executors/deploy_core_legal_mechanisms_for_legal_structure/` (NEW)

#### 6.1 Step 1: verify_legal_mechanism_inputs
**File**: `verify_inputs.go`

- [x] 6.1.1 Validate all required inputs exist
- [x] 6.1.2 Verify legal_structure_iid exists and is PARTNERSHIP type
- [x] 6.1.3 Verify deployer_account_iid has SIGNER slot
- [x] 6.1.4 Verify all partner account IIDs have SIGNER slots
- [x] 6.1.5 Verify authz_source_diamond_admins and authz_admins have no overlap
- [x] 6.1.6 COMP: No-op

#### 6.2 Step 2: create_task_manager_legal_mechanism
**File**: `create_task_manager_mechanism.go`

- [x] 6.2.1 Generate IID for LegalMechanism
- [x] 6.2.2 Create shared.entities record
- [x] 6.2.3 Create LegalMechanism with Type=VOTING, LegalStructureIid, DisplayNames using prefix+locale
- [x] 6.2.4 Store slot_address = "{prefix}-TaskManager" in metadata
- [x] 6.2.5 Return `task_manager_mechanism_iid`, `task_manager_contract_slot_address`
- [x] 6.2.6 COMP: Delete LegalMechanism and entity records

#### 6.3 Step 3: create_authz_source_legal_mechanism
**File**: `create_authz_source_mechanism.go`

- [x] 6.3.1 Generate IID for LegalMechanism
- [x] 6.3.2 Create shared.entities record
- [x] 6.3.3 Create LegalMechanism with Type=AUTHORISATION_SOURCE, LegalStructureIid, DisplayNames
- [x] 6.3.4 Store slot_address = "{prefix}-AuthzSource" in metadata
- [x] 6.3.5 Return `authz_source_mechanism_iid`, `authz_source_diamond_slot_address`
- [x] 6.3.6 COMP: Delete LegalMechanism and entity records

#### 6.4 Step 5: create_task_manager_deployment_record
**File**: `create_task_manager_deployment.go`

- [x] 6.4.1 Get `task_manager_contract_address` from step 4
- [x] 6.4.2 Generate IID for LegalMechanismDeployment
- [x] 6.4.3 Create shared.entities record
- [x] 6.4.4 Create LegalMechanismDeployment with Type=LASER, details including slot_address
- [x] 6.4.5 Return `task_manager_deployment_iid`
- [x] 6.4.6 COMP: Delete deployment and entity records

#### 6.5 Step 8: create_authz_source_deployment_record
**File**: `create_authz_source_deployment.go`

- [x] 6.5.1 Get `authz_diamond_contract_address` from step 6
- [x] 6.5.2 Generate IID for LegalMechanismDeployment
- [x] 6.5.3 Create shared.entities record
- [x] 6.5.4 Create LegalMechanismDeployment with Type=LASER, details including slot_address
- [x] 6.5.5 Return `authz_source_deployment_iid`
- [x] 6.5.6 COMP: Delete deployment and entity records

#### 6.6 Executor Registration (accmgr)
**File**: `saga.go`

- [x] 6.6.1 Create `RunExecutorsAsync()` function for steps 1, 2, 3, 5, 8

**File**: `pkg/daemons/accmgr/trax/executors/run.go`

- [x] 6.6.2 Add call to new saga's `RunExecutorsAsync()`

---

### LASERSVC Executors
**Directory**: `pkg/daemons/lasersvc/trax/executors/deploy_core_legal_mechanisms_for_legal_structure/` (NEW)

#### 6.7 Step 4: deploy_task_manager_contract
**File**: `deploy_task_manager.go`

- [x] 6.7.1 Get deployer slot address from deployer_account_iid
- [x] 6.7.2 Get all partner account ETH addresses for roles
- [x] 6.7.3 Execute LASER mutation DEPLOY_TASKMANAGERV2 with:
  - admins = all partner addresses
  - creators = all partner addresses
  - approvers = all partner addresses
  - executors = all partner addresses
  - enableBypassMode = bypass_mode input
  - contract_name = task_manager_contract_slot_address
- [x] 6.7.4 Return `task_manager_contract_address`, `task_manager_deploy_tx_hash`
- [x] 6.7.5 COMP: No on-chain compensation (contracts are immutable)

#### 6.8 Step 6: deploy_authz_diamond_contract
**File**: `deploy_authz_diamond.go`

- [x] 6.8.1 Get deployer slot address
- [x] 6.8.2 Execute LASER mutation DEPLOY_AUTHZ_DIAMOND with contract_name = authz_source_diamond_slot_address
- [x] 6.8.3 Return `authz_diamond_contract_address`, `authz_diamond_deploy_tx_hash`
- [x] 6.8.4 COMP: No on-chain compensation

#### 6.9 Step 7: initialize_authz_diamond
**File**: `initialize_authz_diamond.go`

- [x] 6.9.1 Get authz_diamond_contract_address from step 6
- [x] 6.9.2 Get task_manager_contract_address from step 4
- [x] 6.9.3 Get authz_source_diamond_admins addresses from saga input (account IIDs -> ETH addresses)
- [x] 6.9.4 Get authz_admins addresses from saga input (account IIDs -> ETH addresses)
- [x] 6.9.5 Execute LASER mutation INITIALIZE_AUTHZ_DIAMOND with:
  - name = authz_source_diamond_slot_address
  - taskManager = task_manager_contract_address
  - authzAdmins = authz_admins addresses
  - authzDiamondAdmins = authz_source_diamond_admins addresses
- [x] 6.9.6 Return `authz_diamond_init_tx_hash`
- [x] 6.9.7 COMP: No on-chain compensation

#### 6.10 Step 9: deploy_authz_facet
**File**: `deploy_authz_facet.go`

- [x] 6.10.1 Get deployer slot address
- [x] 6.10.2 Execute LASER mutation DEPLOY_FACET with:
  - facet_name = "AuthzFacet"
  - facet_version = authz_facet_version input
- [x] 6.10.3 Return `authz_facet_contract_address`, `authz_facet_deploy_tx_hash`
- [x] 6.10.4 COMP: No on-chain compensation

#### 6.11 Step 10: add_authz_facet_to_diamond
**File**: `add_authz_facet.go`

- [x] 6.11.1 Get first authz_diamond_admin account's slot address (the signer for this tx)
- [x] 6.11.2 Get authz_diamond_contract_address from step 6
- [x] 6.11.3 Get authz_facet_contract_address from step 9
- [x] 6.11.4 Execute LASER mutation AUTHZ_DIAMOND_ADD_FACETS with:
  - signer = first authz_diamond_admin slot address
  - diamond = authz_diamond_contract_address
  - facets = [authz_facet_contract_address]
- [x] 6.11.5 Return `add_facet_tx_hash`
- [x] 6.11.6 COMP: No on-chain compensation

#### 6.12 Executor Registration (lasersvc)
**File**: `saga.go`

- [x] 6.12.1 Create `RunExecutorsAsync()` function for steps 4, 6, 7, 9, 10

**File**: `pkg/daemons/lasersvc/trax/executors/run.go`

- [x] 6.12.2 Add call to new saga's `RunExecutorsAsync()`

---

## Phase 7: E2E Tests

**File**: `tests/e2e/laser/legal_mechanism_deployment_test.go` (NEW)

### 7.1 Test Setup Functions

- [x] 7.1.1 `setupTestDatabaseForLegalMechanisms(t)` - Initialize test database
- [x] 7.1.2 `createDeployerSignerSlot(t)` - Create SIGNER slot for deployer
- [x] 7.1.3 `createPartnerParticipantsAndAccounts(t, count int)` - Create partner participants with SIGNER accounts
- [x] 7.1.4 `createInstitutionWithNonSignerAccount(t)` - Create institution with non-SIGNER account
- [x] 7.1.5 `createPartnershipLegalStructure(t, partners []string)` - Create legal structure via existing saga
- [x] 7.1.6 `deployAuthzFacetPrereq(t, version string)` - Deploy AuthzFacet via LASER

### 7.2 Green Path Tests (EthBC-only)

- [x] 7.2.1 `TestDeployCoreLegalMechanisms_FullFlow`
  - Setup: Create deployer, 5 partners, 1 institution, legal structure, deploy authz facet
  - Submit saga with all valid inputs
  - Verify saga completes successfully
  - Verify LegalMechanism records created (VOTING and AUTHORISATION_SOURCE)
  - Verify LegalMechanismDeployment records created with correct slot_address
  - Verify contract addresses are valid ETH addresses
  - **Final RPC verification**: Query TaskManager and AuthzDiamond contracts directly

- [x] 7.2.2 `TestDeployCoreLegalMechanisms_WithBypassMode`
  - Same as above but bypass_mode=true
  - Verify TaskManager deployed with bypass enabled

- [x] 7.2.3 `TestDeployCoreLegalMechanisms_VerifyRoles`
  - Deploy mechanisms using:
    - authz_source_diamond_admins = [partner1_account, partner2_account]
    - authz_admins = [partner3_account, partner4_account]
  - Use LASER queries to verify:
    - All 5 partners are TaskManager admins
    - All 5 partners are TaskManager approvers
    - All 5 partners are TaskManager executors
    - Partners 1-2 are AuthzDiamond admins (from saga input)
    - Partners 3-4 are Authz admins (from saga input)

### 7.3 Red Path Tests (EthBC-only)

- [x] 7.3.1 `TestDeployCoreLegalMechanisms_MissingExecRuntime`
  - Submit saga without exec_runtime_name
  - Verify saga fails at step 1

- [x] 7.3.2 `TestDeployCoreLegalMechanisms_InvalidLegalStructure`
  - Submit saga with non-existent legal_structure_iid
  - Verify saga fails at step 1

- [x] 7.3.3 `TestDeployCoreLegalMechanisms_DeployerNotSigner`
  - Create deployer with non-SIGNER slot
  - Submit saga
  - Verify saga fails at step 1

- [x] 7.3.4 `TestDeployCoreLegalMechanisms_OverlappingAuthzAdmins`
  - Submit saga with overlapping authz_source_diamond_admins and authz_admins
  - Verify saga fails at step 1

- [x] 7.3.5 `TestDeployCoreLegalMechanisms_InvalidFacetVersion`
  - Submit saga with non-existent authz_facet_version
  - Verify saga fails at step 9

- [x] 7.3.6 `TestDeployCoreLegalMechanisms_PartnerAccountNotActive`
  - Create partner with PENDING account status
  - Submit saga
  - Verify saga fails at step 1

---

## Phase 8: Documentation Updates

### 8.1 Update SUMMARY-FOR-AGENT.md
**File**: `docs/SUMMARY-FOR-AGENT.md`

- [x] 8.1.1 Add section on Legal Mechanism deployment saga
- [x] 8.1.2 Document saga inputs/outputs
- [x] 8.1.3 Document relationship: LegalStructure -> LegalMechanism -> LegalMechanismDeployment
- [x] 8.1.4 Document EthBC-only constraint

---

## Data Flow Diagram

```
[Saga Submit: deploy_core_legal_mechanisms_for_legal_structure]
    |
    v
[Step 1: verify_legal_mechanism_inputs] (ACCMGR)
    |-- COMMIT: Validate LS exists, deployer/partners have SIGNER slots, no overlap in authz admins
    |-- COMP: No-op
    v
[Step 2: create_task_manager_legal_mechanism] (ACCMGR)
    |-- COMMIT: Create LegalMechanism (VOTING), DisplayNames={locale: "PREFIX-TaskManager"}
    |-- COMP: Delete LegalMechanism
    |-- OUTPUT: task_manager_mechanism_iid, task_manager_contract_slot_address
    v
[Step 3: create_authz_source_legal_mechanism] (ACCMGR)
    |-- COMMIT: Create LegalMechanism (AUTHORISATION_SOURCE)
    |-- COMP: Delete LegalMechanism
    |-- OUTPUT: authz_source_mechanism_iid, authz_source_diamond_slot_address
    v
[Step 4: deploy_task_manager_contract] (LASERSVC)
    |-- COMMIT: LASER DEPLOY_TASKMANAGERV2 (deployer signs, all partners as roles)
    |-- COMP: No-op (immutable)
    |-- OUTPUT: task_manager_contract_address, task_manager_deploy_tx_hash
    v
[Step 5: create_task_manager_deployment_record] (ACCMGR)
    |-- COMMIT: Create LegalMechanismDeployment (LASER) with contract address
    |-- COMP: Delete deployment record
    |-- OUTPUT: task_manager_deployment_iid
    v
[Step 6: deploy_authz_diamond_contract] (LASERSVC)
    |-- COMMIT: LASER DEPLOY_AUTHZ_DIAMOND (deployer signs)
    |-- COMP: No-op (immutable)
    |-- OUTPUT: authz_diamond_contract_address, authz_diamond_deploy_tx_hash
    v
[Step 7: initialize_authz_diamond] (LASERSVC)
    |-- COMMIT: LASER INITIALIZE_AUTHZ_DIAMOND (deployer signs)
    |   - taskManager = task_manager_contract_address
    |   - authzAdmins = authz_admins input (E2E: partners 3-4)
    |   - authzDiamondAdmins = authz_source_diamond_admins input (E2E: partners 1-2)
    |-- COMP: No-op (immutable)
    |-- OUTPUT: authz_diamond_init_tx_hash
    v
[Step 8: create_authz_source_deployment_record] (ACCMGR)
    |-- COMMIT: Create LegalMechanismDeployment (LASER) with contract address
    |-- COMP: Delete deployment record
    |-- OUTPUT: authz_source_deployment_iid
    v
[Step 9: deploy_authz_facet] (LASERSVC)
    |-- COMMIT: LASER DEPLOY_FACET (deployer signs)
    |-- COMP: No-op (immutable)
    |-- OUTPUT: authz_facet_contract_address, authz_facet_deploy_tx_hash
    v
[Step 10: add_authz_facet_to_diamond] (LASERSVC)
    |-- COMMIT: LASER AUTHZ_DIAMOND_ADD_FACETS (first authz_diamond_admin signs)
    |-- COMP: No-op (immutable)
    |-- OUTPUT: add_facet_tx_hash
    v
[SAGA COMMITTED]
```

### Service Execution Summary

```
ACCMGR (5 steps):    1 -> 2 -> 3 --------> 5 --------> 8
                                  \           \           \
LASERSVC (5 steps):                4           6 -> 7       9 -> 10
```

---

## Files Summary

### New Files

**API Endpoint:**
| File | Description |
|------|-------------|
| `pkg/daemons/accmgr/api/v1/legal_mechanisms_post_deploy.go` | REST endpoint for saga submission |

**Saga Template:**
| File | Description |
|------|-------------|
| `pkg/trax/templates/agora/csd/deploy_core_legal_mechanisms_for_legal_structure.go` | Saga template (10 steps) |

**ACCMGR Executors (Steps 1, 2, 3, 5, 8):**
| File | Description |
|------|-------------|
| `pkg/daemons/accmgr/trax/executors/deploy_core_legal_mechanisms_for_legal_structure/saga.go` | Executor registration |
| `pkg/daemons/accmgr/trax/executors/deploy_core_legal_mechanisms_for_legal_structure/verify_inputs.go` | Step 1 |
| `pkg/daemons/accmgr/trax/executors/deploy_core_legal_mechanisms_for_legal_structure/create_task_manager_mechanism.go` | Step 2 |
| `pkg/daemons/accmgr/trax/executors/deploy_core_legal_mechanisms_for_legal_structure/create_authz_source_mechanism.go` | Step 3 |
| `pkg/daemons/accmgr/trax/executors/deploy_core_legal_mechanisms_for_legal_structure/create_task_manager_deployment.go` | Step 5 |
| `pkg/daemons/accmgr/trax/executors/deploy_core_legal_mechanisms_for_legal_structure/create_authz_source_deployment.go` | Step 8 |

**LASERSVC Executors (Steps 4, 6, 7, 9, 10):**
| File | Description |
|------|-------------|
| `pkg/daemons/lasersvc/trax/executors/deploy_core_legal_mechanisms_for_legal_structure/saga.go` | Executor registration |
| `pkg/daemons/lasersvc/trax/executors/deploy_core_legal_mechanisms_for_legal_structure/deploy_task_manager.go` | Step 4 |
| `pkg/daemons/lasersvc/trax/executors/deploy_core_legal_mechanisms_for_legal_structure/deploy_authz_diamond.go` | Step 6 |
| `pkg/daemons/lasersvc/trax/executors/deploy_core_legal_mechanisms_for_legal_structure/initialize_authz_diamond.go` | Step 7 |
| `pkg/daemons/lasersvc/trax/executors/deploy_core_legal_mechanisms_for_legal_structure/deploy_authz_facet.go` | Step 9 |
| `pkg/daemons/lasersvc/trax/executors/deploy_core_legal_mechanisms_for_legal_structure/add_authz_facet.go` | Step 10 |

**Tests:**
| File | Description |
|------|-------------|
| `tests/e2e/laser/legal_mechanism_deployment_test.go` | E2E tests (EthBC-only) |

### Modified Files

| File | Changes |
|------|---------|
| `pkg/fin/legal_mechanism.go` | Add LegalStructureIid field |
| `pkg/fin/legal_mechanism_deployment.go` | Add LegalMechanismIid field |
| `deploy/k8s/init/init_accmgr_pgsql.sql` | Add legal_mechanisms and legal_mechanism_deployments tables |
| `pkg/daemons/accmgr/account_store.go` | Add LegalMechanism and LegalMechanismDeployment interface methods |
| `pkg/daemons/accmgr/account_store_pgsql.go` | Implement PostgreSQL store methods |
| `pkg/daemons/accmgr/account_store_inmem.go` | Implement in-memory store methods |
| `pkg/trax/templates/agora/csd/index.go` | Register new saga template |
| `pkg/daemons/accmgr/api/v1/api.go` | Add route for POST /legal-mechanisms/deploy-core |
| `pkg/daemons/accmgr/trax/executors/run.go` | Register ACCMGR executors |
| `pkg/daemons/lasersvc/trax/executors/run.go` | Register LASERSVC executors |
| `docs/SUMMARY-FOR-AGENT.md` | Document legal mechanism deployment |

---

## Success Criteria

- [x] Domain model changes compile without errors
- [x] Database schema creates tables successfully
- [x] Store methods pass unit tests
- [x] Saga template registered correctly (verify via traxcli)
- [x] All 10 step executors start without errors
- [x] Green path E2E tests pass (EthBC mode)
- [x] Red path E2E tests pass (validation failures)
- [x] TaskManagerV2 deployed with all partners as all roles
- [x] AuthzDiamond initialized with 4 different partners (2+2)
- [x] AuthzFacet added to diamond by first AuthzDiamond admin
- [x] Direct RPC verification passes at end of tests
- [x] Documentation updated

---

## Implementation Order

1. Phase 1: Domain Model Updates (no dependencies)
2. Phase 2: Database Schema (depends on domain model)
3. Phase 3: Store Implementation (depends on schema)
4. Phase 4: Saga Template (depends on TRAX framework)
5. Phase 5: API Endpoint (depends on saga template)
6. Phase 6a: ACCMGR Step Executors (steps 1, 2, 3, 5, 8)
7. Phase 6b: LASERSVC Step Executors (steps 4, 6, 7, 9, 10)
8. Phase 7: E2E Tests (depends on all above)
9. Phase 8: Documentation

---

## Notes

- **EthBC-only**: This saga only works with real Ethereum blockchain, not RDBMS mode
- **Immutable contracts**: LASER contract deployments cannot be compensated (on-chain immutability)
- **Partner roles**: All 5 partners get ALL TaskManager roles (admin, approver, executor)
- **Authz split from inputs**: authz_source_diamond_admins and authz_admins are saga inputs (account IIDs), must not overlap
  - E2E tests use: partners 1-2 as AuthzDiamond admins, partners 3-4 as Authz admins
- **Facet signing**: First account in authz_source_diamond_admins input signs the facet addition (step 10)
- **Deployer**: Separate 7th account with SIGNER slot, not a partner
- **API endpoint**: REST endpoint at POST /legal-mechanisms/deploy-core submits the saga
- **Slot addresses**: Follow PREFIX-TYPE pattern (e.g., "ACME-TaskManager", "ACME-AuthzSource")
- **Verification**: LASER queries for main logic, direct RPC only at end of tests