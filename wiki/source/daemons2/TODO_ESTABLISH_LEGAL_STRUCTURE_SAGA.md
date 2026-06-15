# COMPLETED: Establish New Legal Structure for Participant - TRAX Saga Implementation

> **Status**: IMPLEMENTED (2025-12-30)
>
> **Recent changes (2026-04-26):** the saga grew from 11 to **12 steps**.
> Step 12 `create_participant_to_legal_structure_relations` writes typed
> participant↔LS roles (CEO, BOARD_MEMBER, COMPLIANCE_OFFICER, …) into
> a new table `accmgr.participant_to_legal_structure_relations`. The
> step is a no-op when no partner declared a `relations` list, so it
> doesn't disturb existing flows. Step 6 `create_accounts_for_legal_structure_partners`
> now reads the optional `partners` JSON input (when forwarded by the
> parent saga's `spawn_establish_legal_struct`) to drive per-partner
> `account_type` (falls back to `CUSTODY`) and stash `partner.prefix`
> in `account.labels.partner_naming_prefix`. Existing fin enum / struct
> renamed participant-first: `LegalStructureToParticipantRelation*` →
> `ParticipantToLegalStructureRelation*` (token prefix
> `PARTICIPANT_TO_LEGAL_STRUCTURE_RELATION_TYPE_ENUM_`).

## Overview

TRAX saga template `establish_new_legal_structure_for_participant` that orchestrates the creation of a legal structure (PARTNERSHIP type only) with an owner participant, partners list, and activated accounts with appropriate LASER slots.

---

## Saga Specification

### Inputs
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| target_participant_iid | string | Yes | IID of the owner participant (TP) |
| parent_participant_iid | string | No | IID of the optional parent participant (PP) |
| display_names | map[string]string (JSON) | Yes | Must contain at least "en-US" key |
| type | string | Yes | Must be "LEGAL_STRUCTURE_TYPE_ENUM_PARTNERSHIP" |
| descriptions | map[string]string (JSON) | No | Optional descriptions by locale |
| partner_participant_iids | []string (JSON) | Yes | List of partner participant IIDs (PL) |

### Steps and Service Ownership (Decomposed)

| Step | Name | Service | Description |
|------|------|---------|-------------|
| 1 | `verify_new_legal_structure_inputs` | **accmgr** | Validate inputs, verify participants exist and are enabled |
| 2 | `create_legal_structure_record` | **accmgr** | Create LegalStructure and ParticipantList records |
| 3 | `create_account_for_legal_structure_owner` | **accmgr** | Create account and participant-to-account relation for TP |
| 4 | `create_laser_slots_for_legal_structure_owner` | **lasersvc** | Create non-SIGNER LASER slots for owner account |
| 5 | `attach_eth_address_to_legal_structure_owner_account` | **accmgr** | Attach ETH address to owner account, set ACTIVE |
| 6 | `create_accounts_for_legal_structure_partners` | **accmgr** | Create accounts and relations for all partners (batch) |
| 7 | `create_laser_slots_for_legal_structure_partners` | **lasersvc** | Create SIGNER-tagged LASER slots for all partner accounts |
| 8 | `attach_eth_addresses_to_legal_structure_partner_accounts` | **accmgr** | Attach ETH addresses to partner accounts, set ACTIVE |

**Service Distribution**:
- **accmgr**: Steps 1, 2, 3, 5, 6, 8 (participant/account domain)
- **lasersvc**: Steps 4, 7 (LASER slot creation)

---

## Phase 1: Domain Model Updates

### 1.1 Update LegalStructure Type
**File**: `pkg/fin/legal_struture.go`

- [x] 1.1.1 Add `OwnerParticipantIid` field (required, string)
- [x] 1.1.2 Add `ParentParticipantIid` field (optional, *string with omitempty)

```go
type LegalStructure struct {
    Iid         string          `json:"iid"`
    Identifiers []FinIdentifier `json:"identifiers"`
    Type        LegalStructureTypeEnum `json:"type"`

    // NEW FIELDS:
    OwnerParticipantIid  string  `json:"owner_participant_iid"`
    ParentParticipantIid *string `json:"parent_participant_iid,omitempty"`

    ParticipantListIids []string          `json:"participant_list_iids"`
    DisplayNames        map[string]string `json:"display_names"`
    Descriptions        map[string]string `json:"descriptions"`
    Labels              map[string]string `json:"labels"`
    Tags                []string          `json:"tags"`
    Metadata            map[string]string `json:"metadata"`
}
```

### 1.2 Update ParticipantListTypeEnum
**File**: `pkg/fin/participant_list.go`

- [x] 1.2.1 Add `PARTICIPANT_LIST_TYPE_ENUM_PARTNERS` constant

```go
// Legal Structure Related
ParticipantListTypeEnum_Partners ParticipantListTypeEnum = "PARTICIPANT_LIST_TYPE_ENUM_PARTNERS"
```

---

## Phase 2: Database Schema Updates

**File**: `deploy/k8s/init/init_accmgr_pgsql.sql`

### 2.1 Create legal_structures Table

- [x] 2.1.1 Add `accmgr.legal_structures` table with all fields from `fin.LegalStructure`
- [x] 2.1.2 Add foreign key to `shared.entities(iid)`
- [x] 2.1.3 Add foreign key to `accmgr.participants(iid)` for owner_participant_iid
- [x] 2.1.4 Add optional foreign key for parent_participant_iid
- [x] 2.1.5 Create indexes on owner_participant_iid, parent_participant_iid, type

```sql
CREATE TABLE IF NOT EXISTS accmgr.legal_structures (
    iid VARCHAR PRIMARY KEY,
    identifiers JSONB NOT NULL DEFAULT '[]',
    type VARCHAR NOT NULL,
    owner_participant_iid VARCHAR NOT NULL,
    parent_participant_iid VARCHAR,
    participant_list_iids JSONB NOT NULL DEFAULT '[]',
    display_names JSONB NOT NULL DEFAULT '{}',
    descriptions JSONB NOT NULL DEFAULT '{}',
    labels JSONB NOT NULL DEFAULT '{}',
    tags JSONB NOT NULL DEFAULT '[]',
    metadata JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_legal_structures_entity FOREIGN KEY (iid) REFERENCES shared.entities(iid) ON DELETE CASCADE,
    CONSTRAINT fk_legal_structures_owner FOREIGN KEY (owner_participant_iid) REFERENCES accmgr.participants(iid),
    CONSTRAINT fk_legal_structures_parent FOREIGN KEY (parent_participant_iid) REFERENCES accmgr.participants(iid)
);
CREATE INDEX IF NOT EXISTS idx_legal_structures_owner ON accmgr.legal_structures(owner_participant_iid);
CREATE INDEX IF NOT EXISTS idx_legal_structures_parent ON accmgr.legal_structures(parent_participant_iid);
CREATE INDEX IF NOT EXISTS idx_legal_structures_type ON accmgr.legal_structures(type);
```

### 2.2 Create participant_lists Table

- [x] 2.2.1 Add `accmgr.participant_lists` table with all fields from `fin.ParticipantList`
- [x] 2.2.2 Add foreign key to `shared.entities(iid)`
- [x] 2.2.3 Create GIN index on types for JSONB array containment queries

```sql
CREATE TABLE IF NOT EXISTS accmgr.participant_lists (
    iid VARCHAR PRIMARY KEY,
    types JSONB NOT NULL DEFAULT '[]',
    participant_iids JSONB NOT NULL DEFAULT '[]',
    display_names JSONB NOT NULL DEFAULT '{}',
    descriptions JSONB NOT NULL DEFAULT '{}',
    labels JSONB NOT NULL DEFAULT '{}',
    tags JSONB NOT NULL DEFAULT '[]',
    metadata JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_participant_lists_entity FOREIGN KEY (iid) REFERENCES shared.entities(iid) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_participant_lists_types ON accmgr.participant_lists USING GIN (types);
```

---

## Phase 3: Store Interface & Implementation

### 3.1 Update AccountStore Interface
**File**: `pkg/daemons/accmgr/account_store.go`

- [x] 3.1.1 Add LegalStructure CRUD methods:
  - `CreateLegalStructure(ctx, ls *fin.LegalStructure) error`
  - `GetLegalStructureByIid(ctx, iid string) (*fin.LegalStructure, error)`
  - `QueryLegalStructures(ctx, options *common.QueryOptions) ([]*fin.LegalStructure, *common.QueryResponse, error)`
  - `QueryLegalStructuresByOwner(ctx, ownerIid string, options *common.QueryOptions) ([]*fin.LegalStructure, *common.QueryResponse, error)`
  - `UpdateLegalStructure(ctx, ls *fin.LegalStructure) error`
  - `DeleteLegalStructure(ctx, iid string) error`

- [x] 3.1.2 Add ParticipantList CRUD methods:
  - `CreateParticipantList(ctx, pl *fin.ParticipantList) error`
  - `GetParticipantListByIid(ctx, iid string) (*fin.ParticipantList, error)`
  - `QueryParticipantLists(ctx, options *common.QueryOptions) ([]*fin.ParticipantList, *common.QueryResponse, error)`
  - `UpdateParticipantList(ctx, pl *fin.ParticipantList) error`
  - `DeleteParticipantList(ctx, iid string) error`

### 3.2 Implement PostgreSQL Store Methods
**File**: `pkg/daemons/accmgr/account_store_pgsql.go`

- [x] 3.2.1 Implement all LegalStructure methods (follow CreateParticipant pattern)
- [x] 3.2.2 Implement all ParticipantList methods (follow CreateParticipant pattern)
- [x] 3.2.3 Add transaction helper methods: `createLegalStructureInTx`, `createParticipantListInTx`

### 3.3 Implement In-Memory Store Methods (for testing)
**File**: `pkg/daemons/accmgr/account_store_inmem.go`

- [x] 3.3.1 Add `legalStructures map[string]*fin.LegalStructure` field
- [x] 3.3.2 Add `participantLists map[string]*fin.ParticipantList` field
- [x] 3.3.3 Implement all interface methods

---

## Phase 4: TRAX Saga Template

### 4.1 Create Saga Template File
**File**: `pkg/trax/templates/agora/csd/establish_new_legal_structure_for_participant.go` (NEW)

- [x] 4.1.1 Define `SagaTemplate` with TemplateId: `establish_new_legal_structure_for_participant`
- [x] 4.1.2 Define 8 `SagaStepTemplate` records:
  - `verify_new_legal_structure_inputs` (index: 1)
  - `create_legal_structure_record` (index: 2)
  - `create_account_for_legal_structure_owner` (index: 3)
  - `create_laser_slots_for_legal_structure_owner` (index: 4)
  - `attach_eth_address_to_legal_structure_owner_account` (index: 5)
  - `create_accounts_for_legal_structure_partners` (index: 6)
  - `create_laser_slots_for_legal_structure_partners` (index: 7)
  - `attach_eth_addresses_to_legal_structure_partner_accounts` (index: 8)
- [x] 4.1.3 Create `CreateEstablishNewLegalStructureForParticipantSagaTemplates()` function

### 4.2 Register Saga Template
**File**: `pkg/trax/templates/agora/csd/index.go`

- [x] 4.2.1 Add call to `CreateEstablishNewLegalStructureForParticipantSagaTemplates()` in `CreateSagaTemplates()`

---

## Phase 5: Saga Step Executors

Executors are split between **accmgr** and **lasersvc** services.

### 5.1 ACCMGR Executors Directory
**Directory**: `pkg/daemons/accmgr/trax/executors/establish_new_legal_structure_for_participant/` (NEW)

### 5.2 Step 1: verify_new_legal_structure_inputs (accmgr)
**File**: `pkg/daemons/accmgr/trax/executors/establish_new_legal_structure_for_participant/verify_inputs.go` (NEW)

- [x] 5.2.1 Create IdempotentService struct with accountStore dependency
- [x] 5.2.2 Implement `ExecuteSync` (COMMIT):
  - Validate required inputs exist
  - Validate `display_names` contains "en-US"
  - Validate `type` == "LEGAL_STRUCTURE_TYPE_ENUM_PARTNERSHIP"
  - Validate `partner_participant_iids` is non-empty
  - Verify TP exists via `accountStore.GetParticipantByIid()`
  - Verify all partners exist
  - Verify all participants are enabled
  - If PP provided, verify it exists and is enabled
- [x] 5.2.3 Implement `CompensateSync` (COMP): No-op

### 5.3 Step 2: create_legal_structure_record (accmgr)
**File**: `pkg/daemons/accmgr/trax/executors/establish_new_legal_structure_for_participant/create_legal_structure_record.go` (NEW)

- [x] 5.3.1 Create IdempotentService struct with accountStore dependency
- [x] 5.3.2 Implement `ExecuteSync` (COMMIT):
  - Generate IID for ParticipantList
  - Create shared.entities record for ParticipantList
  - Create ParticipantList with Types=[PARTNERS], ParticipantIids=input partners
  - Generate IID for LegalStructure
  - Create shared.entities record for LegalStructure
  - Create LegalStructure with OwnerParticipantIid, optional ParentParticipantIid, Type=PARTNERSHIP
  - Link ParticipantList to LegalStructure.ParticipantListIids
  - Return `legal_structure_iid`, `participant_list_iid` in result
- [x] 5.3.3 Implement `CompensateSync` (COMP):
  - Delete LegalStructure record
  - Delete ParticipantList record
  - Delete shared.entities records

### 5.4 Step 3: create_account_for_legal_structure_owner (accmgr)
**File**: `pkg/daemons/accmgr/trax/executors/establish_new_legal_structure_for_participant/create_owner_account.go` (NEW)

- [x] 5.4.1 Create IdempotentService struct with accountStore dependency
- [x] 5.4.2 Implement `ExecuteSync` (COMMIT):
  - Generate account IID (auto-generated UUID-based)
  - Create shared.entities record
  - Create Account (Status=PENDING, store LS IID in metadata)
  - Create ParticipantToAccountRelation (type=OWNER)
  - Return `owner_account_iid` in result
- [x] 5.4.3 Implement `CompensateSync` (COMP):
  - Delete ParticipantToAccountRelation
  - Delete Account
  - Delete shared.entities record

### 5.5 LASERSVC Executors Directory
**Directory**: `pkg/daemons/lasersvc/trax/executors/establish_new_legal_structure_for_participant/` (NEW)

### 5.6 Step 4: create_laser_slots_for_legal_structure_owner (lasersvc)
**File**: `pkg/daemons/lasersvc/trax/executors/establish_new_legal_structure_for_participant/create_owner_slots.go` (NEW)

- [x] 5.6.1 Create IdempotentService struct with laserStore, executorRegistry dependencies
- [x] 5.6.2 Implement `ExecuteSync` (COMMIT):
  - Get `owner_account_iid` from input (passed from step 3)
  - Call `CreateSeededSlotsForAllExecutorsWithTransaction(ctx, owner_account_iid, nil, ...)` (nil = no SIGNER)
  - Extract ETH address from slot creation result
  - Return `owner_account_eth_addr` in result
- [x] 5.6.3 Implement `CompensateSync` (COMP):
  - Delete slot_links via laserStore
  - Delete slots via laserStore

### 5.7 Step 5: attach_eth_address_to_legal_structure_owner_account (accmgr)
**File**: `pkg/daemons/accmgr/trax/executors/establish_new_legal_structure_for_participant/attach_owner_eth_address.go` (NEW)

- [x] 5.7.1 Create IdempotentService struct with accountStore dependency
- [x] 5.7.2 Implement `ExecuteSync` (COMMIT):
  - Get `owner_account_iid` and `owner_account_eth_addr` from input
  - Update account metadata with ETH address
  - Set account status to ACTIVE
  - Update LegalStructure metadata with owner account info
- [x] 5.7.3 Implement `CompensateSync` (COMP):
  - Remove ETH address from account metadata
  - Set account status back to PENDING

### 5.8 Step 6: create_accounts_for_legal_structure_partners (accmgr)
**File**: `pkg/daemons/accmgr/trax/executors/establish_new_legal_structure_for_participant/create_partner_accounts.go` (NEW)

- [x] 5.8.1 Create IdempotentService struct with accountStore dependency
- [x] 5.8.2 Implement `ExecuteSync` (COMMIT):
  - Parse `partner_participant_iids` from original saga input
  - For each partner:
    - Generate account IID
    - Create shared.entities record
    - Create Account (Status=PENDING)
    - Create ParticipantToAccountRelation (type=AUTHORIZED)
  - Return `partner_account_iids` as JSON array in result
- [x] 5.8.3 Implement `CompensateSync` (COMP):
  - Parse created accounts from execution result
  - For each account (REVERSE order):
    - Delete ParticipantToAccountRelation
    - Delete Account
    - Delete shared.entities record

### 5.9 Step 7: create_laser_slots_for_legal_structure_partners (lasersvc)
**File**: `pkg/daemons/lasersvc/trax/executors/establish_new_legal_structure_for_participant/create_partner_slots.go` (NEW)

- [x] 5.9.1 Create IdempotentService struct with laserStore, executorRegistry dependencies
- [x] 5.9.2 Implement `ExecuteSync` (COMMIT):
  - Parse `partner_account_iids` from input (from step 6)
  - For each partner account:
    - Call `CreateSeededSlotsForAllExecutorsWithTransaction(ctx, account_iid, []string{"SLOT_LINK_TAG_ENUM_SIGNER"}, ...)`
    - Extract ETH address
  - Return `partner_account_eth_addrs` as JSON array in result
- [x] 5.9.3 Implement `CompensateSync` (COMP):
  - For each partner account (REVERSE order):
    - Delete slot_links
    - Delete slots

### 5.10 Step 8: attach_eth_addresses_to_legal_structure_partner_accounts (accmgr)
**File**: `pkg/daemons/accmgr/trax/executors/establish_new_legal_structure_for_participant/attach_partner_eth_addresses.go` (NEW)

- [x] 5.10.1 Create IdempotentService struct with accountStore dependency
- [x] 5.10.2 Implement `ExecuteSync` (COMMIT):
  - Parse `partner_account_iids` and `partner_account_eth_addrs` from input
  - For each partner account:
    - Update account metadata with ETH address
    - Set account status to ACTIVE
  - Update LegalStructure metadata with partner account info
- [x] 5.10.3 Implement `CompensateSync` (COMP):
  - For each partner account:
    - Remove ETH address from account metadata
    - Set account status back to PENDING

### 5.11 Executor Registration (accmgr)
**File**: `pkg/daemons/accmgr/trax/executors/establish_new_legal_structure_for_participant/saga.go` (NEW)

- [x] 5.11.1 Create `RunExecutorsAsync()` function that registers steps 1, 2, 3, 5, 6, 8

**File**: `pkg/daemons/accmgr/trax/executors/run.go`

- [x] 5.11.2 Add call to new saga's `RunExecutorsAsync()`

### 5.12 Executor Registration (lasersvc)
**File**: `pkg/daemons/lasersvc/trax/executors/establish_new_legal_structure_for_participant/saga.go` (NEW)

- [x] 5.12.1 Create `RunExecutorsAsync()` function that registers steps 4, 7

**File**: `pkg/daemons/lasersvc/trax/executors/run.go`

- [x] 5.12.2 Add call to new saga's `RunExecutorsAsync()`

---

## Phase 6: E2E Tests

**File**: `tests/e2e/laser/legal_structure_trax_test.go` (NEW)

### 6.1 Test Setup

- [x] 6.1.1 Create `setupTestDatabaseForLegalStructure(t)` function
- [x] 6.1.2 Create helper to create test participants

### 6.2 Green Path Tests

- [x] 6.2.1 `TestEstablishPartnershipWithTwoPartners`
  - Create TP, P1, P2 participants
  - Submit saga with valid inputs
  - Verify saga completes successfully
  - Verify LegalStructure created with correct fields
  - Verify ParticipantList created with PARTNERS type
  - Verify owner account created with non-SIGNER slot_links
  - Verify partner accounts created with SIGNER slot_links

- [x] 6.2.2 `TestEstablishPartnershipWithOptionalParent`
  - Same as above but include parent_participant_iid
  - Verify LegalStructure.ParentParticipantIid is set

- [x] 6.2.3 `TestEstablishPartnershipSinglePartner`
  - Minimum valid case with one partner
  - Verify saga completes

### 6.3 Red Path Tests

- [x] 6.3.1 `TestEstablishPartnership_MissingOwnerParticipant`
  - Submit saga with non-existent target_participant_iid
  - Verify saga fails at step 1

- [x] 6.3.2 `TestEstablishPartnership_MissingDisplayNames`
  - Submit saga without display_names or without en-US
  - Verify saga fails at step 1

- [x] 6.3.3 `TestEstablishPartnership_InvalidType`
  - Submit saga with type != PARTNERSHIP
  - Verify saga fails at step 1

- [x] 6.3.4 `TestEstablishPartnership_NonExistentPartner`
  - Submit saga with one non-existent partner IID
  - Verify saga fails at step 1

- [x] 6.3.5 `TestEstablishPartnership_EmptyPartnersList`
  - Submit saga with empty partner_participant_iids
  - Verify saga fails at step 1

- [x] 6.3.6 `TestEstablishPartnership_CompensationOnStep3Failure`
  - Simulate failure at step 3 (e.g., LASER service unavailable)
  - Verify step 2 compensation runs (LS and PL deleted)

- [x] 6.3.7 `TestEstablishPartnership_CompensationOnStep4Failure`
  - Simulate failure during step 4 (after partial partner accounts created)
  - Verify all created accounts are cleaned up
  - Verify step 3 compensation runs
  - Verify step 2 compensation runs

---

## Phase 7: Documentation Updates

### 7.1 Update SUMMARY-FOR-AGENT.md
**File**: `docs/SUMMARY-FOR-AGENT.md`

- [x] 7.1.1 Add section on Legal Structure saga workflow
- [x] 7.1.2 Document saga inputs/outputs
- [x] 7.1.3 Document SIGNER vs non-SIGNER account distinction

---

## Files Summary

### New Files

**Saga Template:**
| File | Description |
|------|-------------|
| `pkg/trax/templates/agora/csd/establish_new_legal_structure_for_participant.go` | Saga template definition (8 steps) |

**ACCMGR Executors (Steps 1, 2, 3, 5, 6, 8):**
| File | Description |
|------|-------------|
| `pkg/daemons/accmgr/trax/executors/establish_new_legal_structure_for_participant/verify_inputs.go` | Step 1: Validate inputs |
| `pkg/daemons/accmgr/trax/executors/establish_new_legal_structure_for_participant/create_legal_structure_record.go` | Step 2: Create LS and PL |
| `pkg/daemons/accmgr/trax/executors/establish_new_legal_structure_for_participant/create_owner_account.go` | Step 3: Create owner account |
| `pkg/daemons/accmgr/trax/executors/establish_new_legal_structure_for_participant/attach_owner_eth_address.go` | Step 5: Attach owner ETH addr |
| `pkg/daemons/accmgr/trax/executors/establish_new_legal_structure_for_participant/create_partner_accounts.go` | Step 6: Create partner accounts |
| `pkg/daemons/accmgr/trax/executors/establish_new_legal_structure_for_participant/attach_partner_eth_addresses.go` | Step 8: Attach partner ETH addrs |
| `pkg/daemons/accmgr/trax/executors/establish_new_legal_structure_for_participant/saga.go` | ACCMGR executor registration |

**LASERSVC Executors (Steps 4, 7):**
| File | Description |
|------|-------------|
| `pkg/daemons/lasersvc/trax/executors/establish_new_legal_structure_for_participant/create_owner_slots.go` | Step 4: Create owner slots (non-SIGNER) |
| `pkg/daemons/lasersvc/trax/executors/establish_new_legal_structure_for_participant/create_partner_slots.go` | Step 7: Create partner slots (SIGNER) |
| `pkg/daemons/lasersvc/trax/executors/establish_new_legal_structure_for_participant/saga.go` | LASERSVC executor registration |

**Tests:**
| File | Description |
|------|-------------|
| `tests/e2e/laser/legal_structure_trax_test.go` | E2E tests |

### Modified Files
| File | Changes |
|------|---------|
| `pkg/fin/legal_struture.go` | Add OwnerParticipantIid, ParentParticipantIid fields |
| `pkg/fin/participant_list.go` | Add PARTNERS enum value |
| `deploy/k8s/init/init_accmgr_pgsql.sql` | Add legal_structures and participant_lists tables |
| `pkg/daemons/accmgr/account_store.go` | Add LegalStructure and ParticipantList interface methods |
| `pkg/daemons/accmgr/account_store_pgsql.go` | Implement PostgreSQL store methods |
| `pkg/daemons/accmgr/account_store_inmem.go` | Implement in-memory store methods |
| `pkg/trax/templates/agora/csd/index.go` | Register new saga template |
| `pkg/daemons/accmgr/trax/executors/run.go` | Register ACCMGR executors |
| `pkg/daemons/lasersvc/trax/executors/run.go` | Register LASERSVC executors |
| `docs/SUMMARY-FOR-AGENT.md` | Document new saga workflow |

---

## Data Flow Diagram

```
[Saga Submit: establish_new_legal_structure_for_participant]
    |
    v
[Step 1: verify_new_legal_structure_inputs] (ACCMGR)
    |-- COMMIT: Validate TP, PP, partners exist and enabled
    |-- COMP: No-op
    v
[Step 2: create_legal_structure_record] (ACCMGR)
    |-- COMMIT: Create ParticipantList (PARTNERS), Create LegalStructure
    |-- COMP: Delete LegalStructure, Delete ParticipantList
    |-- OUTPUT: legal_structure_iid, participant_list_iid
    v
[Step 3: create_account_for_legal_structure_owner] (ACCMGR)
    |-- COMMIT: Create Account (PENDING), Create Relation (OWNER)
    |-- COMP: Delete relation, Delete account
    |-- OUTPUT: owner_account_iid
    v
[Step 4: create_laser_slots_for_legal_structure_owner] (LASERSVC)
    |-- COMMIT: Create slots (no SIGNER tag) for owner_account_iid
    |-- COMP: Delete slot_links, Delete slots
    |-- OUTPUT: owner_account_eth_addr
    v
[Step 5: attach_eth_address_to_legal_structure_owner_account] (ACCMGR)
    |-- COMMIT: Update account metadata, Set status=ACTIVE
    |-- COMP: Remove ETH addr, Set status=PENDING
    v
[Step 6: create_accounts_for_legal_structure_partners] (ACCMGR)
    |-- COMMIT: For each partner: Create Account (PENDING), Create Relation (AUTHORIZED)
    |-- COMP: Reverse order: Delete relations, Delete accounts
    |-- OUTPUT: partner_account_iids (JSON array)
    v
[Step 7: create_laser_slots_for_legal_structure_partners] (LASERSVC)
    |-- COMMIT: For each partner: Create slots (SIGNER tag)
    |-- COMP: Reverse order: Delete slot_links, Delete slots
    |-- OUTPUT: partner_account_eth_addrs (JSON array)
    v
[Step 8: attach_eth_addresses_to_legal_structure_partner_accounts] (ACCMGR)
    |-- COMMIT: For each partner: Update account metadata, Set status=ACTIVE
    |-- COMP: For each partner: Remove ETH addr, Set status=PENDING
    v
[SAGA COMMITTED]
```

### Service Execution Summary

```
ACCMGR (6 steps):    1 -> 2 -> 3 -----> 5 -> 6 -----> 8
                                 \         \
LASERSVC (2 steps):               4         7
```

---

## Success Criteria

- [x] All domain model changes compile without errors
- [x] Database schema creates tables successfully
- [x] Store methods pass unit tests
- [x] Saga template registered correctly (verify via traxcli)
- [x] All 8 step executors start without errors (6 in accmgr, 2 in lasersvc)
- [x] Green path E2E tests pass
- [x] Red path E2E tests pass (compensation works correctly across services)
- [x] Owner account has non-SIGNER slot_links
- [x] Partner accounts have SIGNER-tagged slot_links
- [x] Documentation updated

---

## Implementation Order

1. Phase 1: Domain Model (no dependencies)
2. Phase 2: Database Schema (depends on domain model)
3. Phase 3: Store Implementation (depends on schema)
4. Phase 4: Saga Template (depends on TRAX framework - no code deps)
5. Phase 5a: ACCMGR Step Executors (steps 1, 2, 3, 5, 6, 8)
6. Phase 5b: LASERSVC Step Executors (steps 4, 7)
7. Phase 6: E2E Tests (depends on all above)
8. Phase 7: Documentation (depends on all above)

---

## Notes

- **PARTNERSHIP only**: Initially, only PARTNERSHIP type is supported. Other types can be added later.
- **Auto-generated IIDs**: Account IIDs are auto-generated UUIDs. References stored in LegalStructure metadata.
- **SIGNER tag**: Partner accounts use SIGNER-tagged slots for blockchain signing. Owner account uses non-SIGNER slots.
- **Service boundary**: Steps alternate between accmgr and lasersvc services. Data passes between services via saga step outputs.
- **Compensation order**: Step 6/7 compensation must process accounts in reverse creation order.
- **Transaction boundaries**: Each step manages its own transaction. Store methods should support transaction context.
- **Executor dependencies**:
  - ACCMGR executors need: `accountStore`
  - LASERSVC executors need: `laserStore`, `executorRegistry`