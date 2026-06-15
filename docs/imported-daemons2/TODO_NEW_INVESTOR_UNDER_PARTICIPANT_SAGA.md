# TODO: New Investor Under Participant - TRAX Saga Implementation

> **Status**: ✅ COMPLETE (All Phases Done)
> **Created**: 2026-01-05
> **Updated**: 2026-01-22

## Overview

TRAX saga template `new_investor_under_participant` that creates a new investor record for an authenticated participant, establishes the participant-to-investor relationship, creates a non-signer account for the investor, activates LASER slots, and creates the investor-to-account ownership relation.

This TODO also includes migrating investor functionality from `invmgr` to `accmgr` and removing the `invmgr` daemon.

**Key Design Decisions:**
- Phase 0 (invmgr → accmgr migration) MUST be completed first before saga implementation
- Expose investor creation via **accmgr** REST API (not prtagent as originally planned)
  - REST API endpoint: `POST /participant/{participant_iid}/investor/new`
- Create new `AccountTypeEnum_InvestorHolding` type for investor accounts
- Investor accounts get BOTH `Client` AND `InvestorHolding` account types
- Use `owner_participant_iid` (not `broker_participant_iid`) consistently everywhere
- Use `external_investor_id` (not `external_investor_ref`) consistently everywhere
- Investor must be queryable by: 1) `investor_iid`, OR 2) `owner_participant_iid` + `external_investor_id`

**Implementation Notes (Deviations from Original Plan):**
- REST API is in **accmgr** (not prtagent) at `pkg/daemons/accmgr/api/v1/investors_post_new.go`
- Step 5 executor is in **laseragent** (not lasersvc) at `pkg/daemons/laseragent/trax/executors/new_investor_under_participant/`
- E2E test file is named `new_investor_under_participant_trax_test.go` (not `new_investor_under_participant_test.go`)

---

## Saga Specification

### Inputs

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| participant_iid | string | Yes | IID of the authenticated participant (from auth context) |
| external_investor_id | string | Yes | External investor ID, unique per participant |
| aux_data | map[string]string | No | Additional metadata to append to investor record |

### Validation Rules

- `external_investor_id` must be unique for the given `participant_iid` (owner)
- `participant_iid` must be extracted from authenticated context (AUTH header)
- Participant must exist and be enabled

### Steps and Service Ownership

| Step | Name | Service | Description |
|------|------|---------|-------------|
| 1 | `verify_new_investor_inputs` | **accmgr** | Validate inputs, verify participant exists and is enabled, check external_investor_id uniqueness |
| 2 | `create_investor_record` | **accmgr** | Create Investor record with external_investor_id and aux_data as metadata |
| 3 | `create_participant_to_investor_relation` | **accmgr** | Create ParticipantToInvestorRelation with type MEMBER_INVESTOR |
| 4 | `create_account_for_investor` | **accmgr** | Create non-signer Account with types [Client, InvestorHolding] and status PENDING |
| 5 | `create_laser_slots_for_investor_account` | **laseragent** | Create non-SIGNER LASER slots for the investor account (tags = nil) |
| 6 | `attach_eth_address_to_investor_account` | **accmgr** | Attach ETH address to account metadata, set status to ACTIVE |
| 7 | `create_investor_to_account_relation` | **accmgr** | Create InvestorToAccountRelation with type ACCOUNT_OWNER |

**Service Distribution**:
- **accmgr**: Steps 1, 2, 3, 4, 6, 7 (investor/account/relation domain)
- **laseragent**: Step 5 (LASER slot creation with `nil` tags for non-SIGNER slots)

---

## Phase 0: Prerequisites - Migrate invmgr to accmgr ✅ COMPLETE

> **Note**: Phase 0 was completed on 2026-01-17. The `invmgr` daemon has been fully removed and all investor functionality is now part of `accmgr`.

### 0.1 Move Investor Domain to accmgr ✅

**Goal**: Move all investor-related code from `pkg/daemons/invmgr/` to `pkg/daemons/accmgr/`

- [x] 0.1.1 Move `InvestorStore` interface methods to `AccountStore` interface
  - `pkg/daemons/accmgr/account_store.go`
- [x] 0.1.2 Move PostgreSQL implementation methods
  - To: `pkg/daemons/accmgr/account_store_pgsql.go`
- [x] 0.1.3 Move in-memory implementation methods
  - To: `pkg/daemons/accmgr/account_store_inmem.go`
- [x] 0.1.4 Move REST API endpoints
  - To: `pkg/daemons/accmgr/api/v1/*.go`
- [x] 0.1.5 Update import paths across codebase

### 0.2 Update Database Schema ✅

- [x] 0.2.1 Investor tables are now in `accmgr` schema
  - `accmgr.investors`
  - `accmgr.investor_to_account_relations`
- [x] 0.2.2 Updated `deploy/k8s/init/init_accmgr_pgsql.sql`
- [x] 0.2.3 Removed `deploy/k8s/init/init_invmgr_pgsql.sql`

### 0.3 Remove invmgr Daemon ✅

- [x] 0.3.1 Removed `pkg/daemons/invmgr.go`
- [x] 0.3.2 Removed `pkg/daemons/invmgr/` directory
- [x] 0.3.3 Removed `cmd/agora/daemons/invmgr/` directory
- [x] 0.3.4 Removed `deploy/k8s/charts/invmgr/` directory (K8s Helm chart)
- [x] 0.3.5 Updated `Makefile` to remove invmgr targets
- [x] 0.3.6 Updated docker-compose and K8s deployment configs
- [x] 0.3.7 Updated references in documentation and admui

---

## Phase 1: Domain Model Updates

### 1.1 Add AccountTypeEnum_InvestorHolding
**File**: `pkg/fin/account.go`

- [x] 1.1.1 Add new account type constant:
```go
AccountTypeEnum_InvestorHolding AccountTypeEnum = "ACCOUNT_TYPE_ENUM_INVESTOR_HOLDING"
```

### 1.2 Update admui enums.ts ✅
**File**: `pkg/clis/admui/webapp/src/types/enums.ts`

- [x] 1.2.1 Add `InvestorHolding` to `AccountTypeEnum`:
```typescript
InvestorHolding: 'ACCOUNT_TYPE_ENUM_INVESTOR_HOLDING',
```

### 1.3 Create ParticipantToInvestorRelation Type ✅
**File**: `pkg/fin/participant_to_investor_relation.go`

- [x] 1.3.1 Define `ParticipantToInvestorRelationTypeEnum` with values:
  - `PARTICIPANT_TO_INVESTOR_RELATION_TYPE_ENUM_MEMBER_INVESTOR`
  - `PARTICIPANT_TO_INVESTOR_RELATION_TYPE_ENUM_OTHER`

- [x] 1.3.2 Define `ParticipantToInvestorRelation` struct:

```go
type ParticipantToInvestorRelation struct {
    Iid string `json:"iid"`

    ParticipantIid string `json:"participant_iid"`
    InvestorIid    string `json:"investor_iid"`

    Relations []ParticipantToInvestorRelationTypeEnum `json:"relations"`

    EffectiveFromTs *string `json:"effective_from_ts,omitempty"`
    EffectiveToTs   *string `json:"effective_to_ts,omitempty"`

    DisplayNames map[string]string `json:"display_names"`
    Descriptions map[string]string `json:"descriptions"`
    Labels       map[string]string `json:"labels"`
    Tags         []string          `json:"tags"`
    Metadata     map[string]string `json:"metadata"`
}
```

### 1.4 Update Investor Type ✅
**File**: `pkg/fin/investor.go`

- [x] 1.4.1 Rename `BrokerParticipantIid` to `OwnerParticipantIid` in `Investor` struct:
```go
// Before:
BrokerParticipantIid string `json:"broker_participant_iid"`

// After:
OwnerParticipantIid string `json:"owner_participant_iid"`
```
- [x] 1.4.2 Update ALL code references from `BrokerParticipantIid` to `OwnerParticipantIid`
- [x] 1.4.3 Update ALL code references from `broker_participant_iid` to `owner_participant_iid`

---

## Phase 2: Database Schema Updates ✅ COMPLETE

**File**: `deploy/k8s/init/init_accmgr_pgsql.sql`

### 2.1 Add investors Table to accmgr Schema ✅

- [x] 2.1.1 Create investors table (migrate from invmgr schema):

```sql
-- Create investors table in accmgr schema (aligned with fin.Investor)
CREATE TABLE IF NOT EXISTS accmgr.investors (
    iid VARCHAR PRIMARY KEY,

    -- Core fields aligned with fin.Investor
    identifiers JSONB NOT NULL DEFAULT '[]',       -- []FinIdentifier as JSON array
    types JSONB NOT NULL DEFAULT '[]',             -- []InvestorTypeEnum as JSON array

    display_names JSONB NOT NULL DEFAULT '{}',     -- map[string]string with locales like "en-US"
    descriptions JSONB NOT NULL DEFAULT '{}',      -- map[string]string with locales like "en-US"
    labels JSONB NOT NULL DEFAULT '{}',            -- map[string]string
    tags JSONB NOT NULL DEFAULT '[]',              -- []string
    metadata JSONB NOT NULL DEFAULT '{}',          -- map[string]string

    external_investor_id VARCHAR NOT NULL,
    owner_participant_iid VARCHAR NOT NULL,        -- REQUIRED: Owner participant IID (denormalized for uniqueness)
    status VARCHAR NOT NULL,                       -- InvestorStatus enum values

    -- Timestamps
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Foreign key to ensure IID uniqueness across all entities
    CONSTRAINT fk_investors_entity
    FOREIGN KEY (iid) REFERENCES shared.entities(iid) ON DELETE CASCADE,

    -- Foreign key to ensure participant exists
    CONSTRAINT fk_investors_owner_participant
    FOREIGN KEY (owner_participant_iid) REFERENCES accmgr.participants(iid) ON DELETE CASCADE
);

-- Uniqueness constraint: external_investor_id must be unique per owner participant
CREATE UNIQUE INDEX IF NOT EXISTS idx_investor_ext_id_per_owner
    ON accmgr.investors(owner_participant_iid, external_investor_id);

-- Index for querying by owner participant
CREATE INDEX IF NOT EXISTS idx_investors_owner_participant ON accmgr.investors(owner_participant_iid);
CREATE INDEX IF NOT EXISTS idx_investors_identifiers ON accmgr.investors USING GIN (identifiers);
```

### 2.2 Add investor_to_account_relations Table to accmgr Schema ✅

- [x] 2.2.1 Create investor_to_account_relations table (migrate from invmgr schema):

```sql
-- Create investor-to-account relations table (aligned with fin.InvestorToAccountRelation)
CREATE TABLE IF NOT EXISTS accmgr.investor_to_account_relations (
    iid VARCHAR PRIMARY KEY,

    investor_iid VARCHAR NOT NULL,
    account_iid VARCHAR NOT NULL,

    relations JSONB NOT NULL DEFAULT '[]', -- []InvestorToAccountRelationType as JSON array

    effective_from_ts VARCHAR,              -- ISO timestamp string
    effective_to_ts VARCHAR,                -- ISO timestamp string

    display_names JSONB NOT NULL DEFAULT '{}',
    descriptions JSONB NOT NULL DEFAULT '{}',
    labels JSONB NOT NULL DEFAULT '{}',
    tags JSONB NOT NULL DEFAULT '[]',
    metadata JSONB NOT NULL DEFAULT '{}',

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (investor_iid) REFERENCES accmgr.investors(iid) ON DELETE CASCADE,
    FOREIGN KEY (account_iid) REFERENCES accmgr.accounts(iid) ON DELETE CASCADE,
    UNIQUE(investor_iid, account_iid)
);

CREATE INDEX IF NOT EXISTS idx_inv_acc_rel_investor ON accmgr.investor_to_account_relations(investor_iid);
CREATE INDEX IF NOT EXISTS idx_inv_acc_rel_account ON accmgr.investor_to_account_relations(account_iid);
```

### 2.3 Create participant_to_investor_relations Table ✅

- [x] 2.3.1 Create table with foreign keys and indexes:

```sql
CREATE TABLE IF NOT EXISTS accmgr.participant_to_investor_relations (
    iid VARCHAR PRIMARY KEY,
    participant_iid VARCHAR NOT NULL,
    investor_iid VARCHAR NOT NULL,
    relations JSONB NOT NULL DEFAULT '[]',
    effective_from_ts VARCHAR,
    effective_to_ts VARCHAR,
    display_names JSONB NOT NULL DEFAULT '{}',
    descriptions JSONB NOT NULL DEFAULT '{}',
    labels JSONB NOT NULL DEFAULT '{}',
    tags JSONB NOT NULL DEFAULT '[]',
    metadata JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pti_rel_entity FOREIGN KEY (iid) REFERENCES shared.entities(iid) ON DELETE CASCADE,
    CONSTRAINT fk_pti_rel_participant FOREIGN KEY (participant_iid) REFERENCES accmgr.participants(iid),
    CONSTRAINT fk_pti_rel_investor FOREIGN KEY (investor_iid) REFERENCES accmgr.investors(iid),
    CONSTRAINT uq_participant_investor UNIQUE (participant_iid, investor_iid)
);
CREATE INDEX IF NOT EXISTS idx_pti_rel_participant ON accmgr.participant_to_investor_relations(participant_iid);
CREATE INDEX IF NOT EXISTS idx_pti_rel_investor ON accmgr.participant_to_investor_relations(investor_iid);
```

---

## Phase 3: Store Interface & Implementation ✅ COMPLETE

### 3.1 Update AccountStore Interface ✅
**File**: `pkg/daemons/accmgr/account_store.go`

- [x] 3.1.1 Add Investor CRUD methods (migrate from InvestorStore):
  - `CreateInvestor(ctx, investor *fin.Investor) error`
  - `GetInvestorByIid(ctx, iid string) (*fin.Investor, error)`
  - `GetInvestorByOwnerParticipantAndExternalId(ctx, ownerParticipantIid, externalInvestorId string) (*fin.Investor, error)` ← **Key lookup method**
  - `QueryInvestors(ctx, options *common.QueryOptions) ([]*fin.Investor, *common.QueryResponse, error)`
  - `QueryInvestorsByOwnerParticipantIid(ctx, ownerParticipantIid string, options *common.QueryOptions) ([]*fin.Investor, *common.QueryResponse, error)`
  - `UpdateInvestor(ctx, investor *fin.Investor) error`
  - `DeleteInvestor(ctx, iid string) error`

- [x] 3.1.2 Add ParticipantToInvestorRelation CRUD methods:
  - `CreateParticipantToInvestorRelation(ctx, rel *fin.ParticipantToInvestorRelation) error`
  - `GetParticipantToInvestorRelationByIid(ctx, iid string) (*fin.ParticipantToInvestorRelation, error)`
  - `QueryParticipantToInvestorRelations(ctx, options *common.QueryOptions) ([]*fin.ParticipantToInvestorRelation, *common.QueryResponse, error)`
  - `QueryParticipantToInvestorRelationsByParticipant(ctx, participantIid string, options *common.QueryOptions) ([]*fin.ParticipantToInvestorRelation, *common.QueryResponse, error)`
  - `QueryParticipantToInvestorRelationsByInvestor(ctx, investorIid string, options *common.QueryOptions) ([]*fin.ParticipantToInvestorRelation, *common.QueryResponse, error)`
  - `UpdateParticipantToInvestorRelation(ctx, rel *fin.ParticipantToInvestorRelation) error`
  - `DeleteParticipantToInvestorRelation(ctx, iid string) error`

- [x] 3.1.3 Add InvestorToAccountRelation CRUD methods (migrate from InvestorStore):
  - `CreateInvestorToAccountRelationFull(ctx, rel *fin.InvestorToAccountRelation) error`
  - `GetInvestorToAccountRelationByIid(ctx, iid string) (*fin.InvestorToAccountRelation, error)`
  - `QueryInvestorToAccountRelationsByInvestor(ctx, investorIid string, options *common.QueryOptions) ([]*fin.InvestorToAccountRelation, *common.QueryResponse, error)`
  - `QueryInvestorToAccountRelationsByAccount(ctx, accountIid string, options *common.QueryOptions) ([]*fin.InvestorToAccountRelation, *common.QueryResponse, error)`
  - `UpdateInvestorToAccountRelation(ctx, rel *fin.InvestorToAccountRelation) error`
  - `DeleteInvestorToAccountRelationByIid(ctx, iid string) error`

### 3.2 Implement PostgreSQL Store Methods ✅
**File**: `pkg/daemons/accmgr/account_store_pgsql.go`

- [x] 3.2.1 Implement all Investor methods
- [x] 3.2.2 Implement all ParticipantToInvestorRelation methods
- [x] 3.2.3 Implement all InvestorToAccountRelation methods

### 3.3 Implement In-Memory Store Methods ✅
**File**: `pkg/daemons/accmgr/account_store_inmem.go`

- [x] 3.3.1 Add `investors map[string]*fin.Investor` field
- [x] 3.3.2 Add `participantToInvestorRelations map[string]*fin.ParticipantToInvestorRelation` field
- [x] 3.3.3 Add `investorToAccountRelations map[string]*fin.InvestorToAccountRelation` field
- [x] 3.3.4 Implement all interface methods

---

## Phase 4: REST API Setup ✅ COMPLETE

> **Note**: REST API was implemented in **accmgr** instead of prtagent as originally planned.

### 4.1 Create REST API in accmgr ✅
**File**: `pkg/daemons/accmgr/api/v1/investors_post_new.go`

- [x] 4.1.1 Implemented `POST /participant/{participant_iid}/investor/new` endpoint
  - Validates `external_investor_id` is required
  - Passes metadata with prefix `"metadata_*"` to saga input
  - Submits `new_investor_under_participant` saga
  - Returns saga instance ID for async tracking

**Request Structure:**
```go
type NewInvestorRequest struct {
    ExternalInvestorID string            `json:"external_investor_id" binding:"required"`
    Metadata           map[string]string `json:"metadata,omitempty"`
}
```

**Response Structure:**
```go
type NewInvestorResponse struct {
    SagaInstanceID string `json:"saga_instance_id"`
    Message        string `json:"message"`
}
```

---

## Phase 5: TRAX Saga Template ✅ COMPLETE

> **Note**: Saga templates in this codebase are executor-registered (not file-based templates).

### 5.1 Saga Template Registered via Executors ✅

- [x] 5.1.1 Saga template ID: `new_investor_under_participant`
- [x] 5.1.2 7 steps registered via executor packages:
  - `verify_new_investor_inputs` (index: 1, service: accmgr)
  - `create_investor_record` (index: 2, service: accmgr)
  - `create_participant_to_investor_relation` (index: 3, service: accmgr)
  - `create_account_for_investor` (index: 4, service: accmgr)
  - `create_laser_slots_for_investor_account` (index: 5, service: laseragent)
  - `attach_eth_address_to_investor_account` (index: 6, service: accmgr)
  - `create_investor_to_account_relation` (index: 7, service: accmgr)

---

## Phase 6: Saga Step Executors ✅ COMPLETE

### ACCMGR Executors ✅
**Directory**: `pkg/daemons/accmgr/trax/executors/new_investor_under_participant/`

#### 6.1 Step 1: verify_new_investor_inputs ✅
**File**: `verify_inputs.go`

- [x] 6.1.1 Validate required inputs exist (`participant_iid`, `external_investor_id`)
- [x] 6.1.2 Verify participant exists and is enabled
- [x] 6.1.3 Check `external_investor_id` uniqueness for the owner participant
- [x] 6.1.4 COMP: No-op

#### 6.2 Step 2: create_investor_record ✅
**File**: `create_investor_record.go`

- [x] 6.2.1 Generate IID for Investor
- [x] 6.2.2 Create shared.entities record
- [x] 6.2.3 Create Investor with ExternalInvestorId, aux_data as Metadata
- [x] 6.2.4 Set `owner_participant_iid` for uniqueness constraint
- [x] 6.2.5 Return `investor_iid` in result
- [x] 6.2.6 COMP: Delete Investor and entity records

#### 6.3 Step 3: create_participant_to_investor_relation ✅
**File**: `create_participant_to_investor_relation.go`

- [x] 6.3.1 Generate IID for ParticipantToInvestorRelation
- [x] 6.3.2 Create shared.entities record
- [x] 6.3.3 Create relation with type MEMBER_INVESTOR
- [x] 6.3.4 Return `participant_to_investor_relation_iid` in result
- [x] 6.3.5 COMP: Delete relation and entity records

#### 6.4 Step 4: create_account_for_investor ✅
**File**: `create_account_for_investor.go`

- [x] 6.4.1 Generate IID for Account
- [x] 6.4.2 Create shared.entities record
- [x] 6.4.3 Create Account with:
  - `Types`: `[AccountTypeEnum_Client, AccountTypeEnum_InvestorHolding]`
  - `Status`: `PENDING`
  - Store `investor_iid` in Labels
- [x] 6.4.4 Return `investor_account_iid` in result
- [x] 6.4.5 COMP: Delete Account and entity records

#### 6.5 Step 6: attach_eth_address_to_investor_account ✅
**File**: `attach_eth_address.go`

- [x] 6.5.1 Get `investor_account_iid` and ETH address from step 5
- [x] 6.5.2 Update account Metadata with ETH address
- [x] 6.5.3 Set account Status to ACTIVE
- [x] 6.5.4 COMP: Remove ETH address, set Status back to PENDING

#### 6.6 Step 7: create_investor_to_account_relation ✅
**File**: `create_investor_to_account_relation.go`

- [x] 6.6.1 Generate IID for InvestorToAccountRelation
- [x] 6.6.2 Create shared.entities record
- [x] 6.6.3 Create relation with type ACCOUNT_OWNER
- [x] 6.6.4 Return `investor_to_account_relation_iid` in result
- [x] 6.6.5 COMP: Delete relation and entity records

#### 6.7 Executor Registration (accmgr) ✅
**File**: `saga.go`

- [x] 6.7.1 Create `RunExecutorsAsync()` function for steps 1, 2, 3, 4, 6, 7
- [x] 6.7.2 Registered in `pkg/daemons/accmgr/trax/executors/run.go`

### LASERAGENT Executors ✅
**Directory**: `pkg/daemons/laseragent/trax/executors/new_investor_under_participant/`

> **Note**: Step 5 is in **laseragent** (not lasersvc as originally planned)

#### 6.8 Step 5: create_laser_slots_for_investor_account ✅
**File**: `create_laser_slots_for_investor_account.go`

- [x] 6.8.1 Get `investor_account_iid` from step 4
- [x] 6.8.2 Call slot creation with `nil` tags (non-SIGNER)
- [x] 6.8.3 Extract ETH address from slot creation result
- [x] 6.8.4 Return `investor_account_eth_addr` in result
- [x] 6.8.5 COMP: Delete slot_links and slots

#### 6.9 Executor Registration (laseragent) ✅
**File**: `saga.go`

- [x] 6.9.1 Create `RunExecutorsAsync()` function for step 5
- [x] 6.9.2 Registered in laseragent executor run

---

## Phase 7: API Implementation ✅ COMPLETE

> **Note**: REST API was implemented in **accmgr** instead of prtagent as originally planned.

### 7.1 accmgr REST API Handler ✅
**File**: `pkg/daemons/accmgr/api/v1/investors_post_new.go`

- [x] 7.1.1 Implemented `POST /participant/{participant_iid}/investor/new`
  - Validates external_investor_id required
  - Submits `new_investor_under_participant` saga with inputs
  - Returns saga instance ID for async tracking
- [x] 7.1.2 Proper async response handling via saga instance ID
- [x] 7.1.3 Uses `external_investor_id` (not `external_investor_ref`)
- [x] 7.1.4 Uses `owner_participant_iid` (not `broker_participant_iid`)

---

## Phase 8: E2E Tests ✅ COMPLETE

**File**: `tests/e2e/laser/new_investor_under_participant_trax_test.go`

### 8.1 Test Setup Functions ✅

- [x] 8.1.1 `setupTestDatabaseForNewInvestor(t)` - Initialize test database with E1/E2 executors
- [x] 8.1.2 `createTestParticipantForInvestor(t, iid string)` - Create broker participant
- [x] 8.1.3 `submitNewInvestorSaga(t, input, idempotentKey)` - Submit saga via accmgr REST API
- [x] 8.1.4 `waitForNewInvestorSagaCompletion(t, sagaInstanceId, timeoutSeconds)` - Wait for terminal state

### 8.2 Green Path Tests (EthBC mode) ✅

- [x] 8.2.1 `TestNewInvestorUnderParticipant_BasicSuccess` - Basic saga flow
- [x] 8.2.2 `TestNewInvestorUnderParticipant_WithMetadata` - Metadata handling
- [x] 8.2.3 `TestNewInvestorUnderParticipant_MultipleInvestors` - Multiple investors under same participant

### 8.3 Red Path Tests ✅

- [x] 8.3.1 `TestNewInvestorUnderParticipant_DuplicateExternalId` - Uniqueness constraint
- [x] 8.3.2 `TestNewInvestorUnderParticipant_SameExternalIdDifferentParticipant` - Cross-participant isolation
- [x] 8.3.3 `TestNewInvestorUnderParticipant_MissingExternalId` - Validation error
- [x] 8.3.4 `TestNewInvestorUnderParticipant_NonExistentParticipant` - Failure handling

### 8.4 Test Utilities ✅

- [x] `getInvestorIidFromSaga()` - Query investor by external ID
- [x] `getAccountIidFromSaga()` - Query investor's account
- [x] `verifyInvestorCreated()` - Verify investor properties
- [x] `verifyInvestorAccountCreated()` - Verify account with INVESTOR_HOLDING type
- [x] `verifyParticipantToInvestorRelation()` - Verify participant-investor link
- [x] `verifyInvestorToAccountRelation()` - Verify investor-account link with OWNER type

---

## Phase 9: Documentation Updates ✅ COMPLETE

### 9.1 Update SUMMARY-FOR-AGENT.md ✅
**File**: `docs/SUMMARY-FOR-AGENT.md`

- [x] 9.1.1 Add section on new_investor_under_participant saga
- [x] 9.1.2 Document investor domain migration to accmgr
- [x] 9.1.3 Document ParticipantToInvestorRelation model

### 9.2 Create TODO Document ✅
**File**: `docs/TODO_NEW_INVESTOR_UNDER_PARTICIPANT_SAGA.md`

- [x] 9.2.1 This TODO document with final implementation status

---

## Data Flow Diagram

```
[prtagent gRPC: NewInvestor()] OR [prtagent REST: POST /api/v1/investors]
    |
    v
[Saga Submit: new_investor_under_participant]
    |
    v
[Step 1: verify_new_investor_inputs] (ACCMGR)
    |-- COMMIT: Validate participant, check external_investor_id uniqueness per owner
    |-- COMP: No-op
    v
[Step 2: create_investor_record] (ACCMGR)
    |-- COMMIT: Create Investor with ExternalInvestorId, OwnerParticipantIid, aux_data as Metadata
    |-- COMP: Delete Investor
    |-- OUTPUT: investor_iid
    v
[Step 3: create_participant_to_investor_relation] (ACCMGR)
    |-- COMMIT: Create ParticipantToInvestorRelation (MEMBER_INVESTOR)
    |-- COMP: Delete relation
    |-- OUTPUT: participant_to_investor_relation_iid
    v
[Step 4: create_account_for_investor] (ACCMGR)
    |-- COMMIT: Create Account (Types: [Client, InvestorHolding], Status: PENDING)
    |-- COMP: Delete Account
    |-- OUTPUT: investor_account_iid
    v
[Step 5: create_laser_slots_for_investor_account] (LASERAGENT)
    |-- COMMIT: Create non-SIGNER slots (tags=nil) for investor_account_iid
    |-- COMP: Delete slots
    |-- OUTPUT: investor_account_eth_addr
    v
[Step 6: attach_eth_address_to_investor_account] (ACCMGR)
    |-- COMMIT: Update account metadata, set status=ACTIVE
    |-- COMP: Remove ETH addr, set status=PENDING
    v
[Step 7: create_investor_to_account_relation] (ACCMGR)
    |-- COMMIT: Create InvestorToAccountRelation (ACCOUNT_OWNER)
    |-- COMP: Delete relation
    |-- OUTPUT: investor_to_account_relation_iid
    v
[SAGA COMMITTED]

Investor Queryable By:
  1. investor_iid (direct lookup)
  2. owner_participant_iid + external_investor_id (composite key)
```

### Service Execution Summary

```
ACCMGR (6 steps):      1 -> 2 -> 3 -> 4 -----> 6 -> 7
                                         \
LASERAGENT (1 step):                      5
```

---

## Files Summary

### New Files

**Domain Model:**
| File | Description |
|------|-------------|
| `pkg/fin/participant_to_investor_relation.go` | ParticipantToInvestorRelation type |

**Saga Template:**
| File | Description |
|------|-------------|
| `pkg/trax/templates/agora/prtagent/new_investor_under_participant.go` | Saga template (7 steps) |
| `pkg/trax/templates/agora/prtagent/index.go` | prtagent saga index |

**ACCMGR Executors (Steps 1, 2, 3, 4, 6, 7):**
| File | Description |
|------|-------------|
| `pkg/daemons/accmgr/trax/executors/new_investor_under_participant/saga.go` | Executor registration |
| `pkg/daemons/accmgr/trax/executors/new_investor_under_participant/verify_inputs.go` | Step 1 |
| `pkg/daemons/accmgr/trax/executors/new_investor_under_participant/create_investor_record.go` | Step 2 |
| `pkg/daemons/accmgr/trax/executors/new_investor_under_participant/create_participant_to_investor_relation.go` | Step 3 |
| `pkg/daemons/accmgr/trax/executors/new_investor_under_participant/create_account_for_investor.go` | Step 4 |
| `pkg/daemons/accmgr/trax/executors/new_investor_under_participant/attach_eth_address.go` | Step 6 |
| `pkg/daemons/accmgr/trax/executors/new_investor_under_participant/create_investor_to_account_relation.go` | Step 7 |

**LASERAGENT Executors (Step 5):**
| File | Description |
|------|-------------|
| `pkg/daemons/laseragent/trax/executors/new_investor_under_participant/saga.go` | Executor registration |
| `pkg/daemons/laseragent/trax/executors/new_investor_under_participant/create_laser_slots_for_investor_account.go` | Step 5 |

**accmgr REST API:**
| File | Description |
|------|-------------|
| `pkg/daemons/accmgr/api/v1/investors_post_new.go` | POST /participant/{participant_iid}/investor/new |

**Tests:**
| File | Description |
|------|-------------|
| `tests/e2e/laser/new_investor_under_participant_trax_test.go` | E2E full saga tests (EthBC mode) |

### Modified Files

| File | Changes |
|------|---------|
| `pkg/fin/account.go` | Add AccountTypeEnum_InvestorHolding |
| `pkg/fin/investor.go` | Rename BrokerParticipantIid to OwnerParticipantIid |
| `pkg/clis/admui/webapp/src/types/enums.ts` | Add InvestorHolding to AccountTypeEnum |
| `deploy/k8s/init/init_accmgr_pgsql.sql` | Add investors, relations tables |
| `pkg/daemons/accmgr/account_store.go` | Add Investor, Relation methods |
| `pkg/daemons/accmgr/account_store_pgsql.go` | Implement PostgreSQL methods |
| `pkg/daemons/accmgr/account_store_inmem.go` | Implement in-memory methods |
| `pkg/daemons/accmgr/trax/executors/run.go` | Register ACCMGR executors |
| `pkg/daemons/laseragent/trax/executors/run.go` | Register LASERAGENT executors |
| `docs/SUMMARY-FOR-AGENT.md` | Document investor saga |

### Removed Files

| File | Description |
|------|-------------|
| `pkg/daemons/invmgr.go` | invmgr daemon entry |
| `pkg/daemons/invmgr/` | Entire invmgr directory |
| `cmd/agora/daemons/invmgr/` | invmgr CLI entry |
| `deploy/k8s/charts/invmgr/` | K8s Helm chart for invmgr |

---

## Success Criteria ✅ ALL COMPLETE

- [x] invmgr daemon completely removed
- [x] All investor functionality migrated to accmgr
- [x] `AccountTypeEnum_InvestorHolding` added to Go and TypeScript
- [x] `BrokerParticipantIid` renamed to `OwnerParticipantIid` everywhere
- [x] `external_investor_ref` renamed to `external_investor_id` everywhere
- [x] Domain model changes compile without errors
- [x] Database schema creates tables successfully with unique constraint on (owner_participant_iid, external_investor_id)
- [x] Store methods pass unit tests
- [x] Investor queryable by IID
- [x] Investor queryable by owner_participant_iid + external_investor_id
- [x] Saga template registered correctly (executor-based registration)
- [x] All 7 step executors implemented (6 in accmgr, 1 in laseragent)
- [x] Green path E2E tests implemented
- [x] Red path E2E tests implemented
- [x] Query test utilities implemented
- [x] accmgr REST API implemented for investor creation
- [x] Documentation updated

---

## Implementation Order

1. **Phase 0**: Prerequisites - Migrate invmgr to accmgr (CRITICAL FIRST)
2. **Phase 1**: Domain Model Updates
3. **Phase 2**: Database Schema
4. **Phase 3**: Store Implementation
5. **Phase 4**: REST API Endpoints
6. **Phase 5**: Saga Template
7. **Phase 6a**: ACCMGR Step Executors
8. **Phase 6b**: LASERSVC Step Executors
9. **Phase 7**: prtagent NewInvestor Update
10. **Phase 8**: E2E Tests
11. **Phase 9**: Documentation

---

## Notes

- **External ID Uniqueness**: `external_investor_id` is unique per `owner_participant_iid`, not globally
- **Investor Query Methods**: Must support lookup by: 1) `investor_iid`, OR 2) `owner_participant_iid` + `external_investor_id`
- **Account Types**: Investor accounts get BOTH `AccountTypeEnum_Client` AND `AccountTypeEnum_InvestorHolding`
- **Non-SIGNER Slots**: Use `nil` tags when calling `CreateSeededSlotsForAllExecutorsWithTransaction()` (vs `[]string{"SIGNER"}` for signer slots)
- **Auth Header**: `X-Agora-Participant-Api-Key` for REST, `x-agora-participant-api-key` for gRPC
- **invmgr Removal**: Complete removal of invmgr daemon - all investor ops move to accmgr (Phase 0)
- **Field Naming**: Use `owner_participant_iid` (not `broker_participant_iid`) everywhere
- **MEMBER_INVESTOR Type**: New relation type for participant-to-investor relationship
- **EthBC Mode**: E2E tests use LASER system, follow pattern from `setup_new_legal_participant_test.go`
- **accmgr Endpoint**: Investor creation exposed via accmgr REST API
  - REST: `POST /participant/{participant_iid}/investor/new`
- **Step 5 Service**: Implemented in **laseragent** (not lasersvc as originally planned)