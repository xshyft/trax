# TODO: Individual TRAX Saga Step (IndTrxSS) E2E Tests

> **Status**: NOT STARTED
> **Created**: 2026-01-08

## Overview

This document specifies e2e laser tests for verifying individual saga steps (IndTrxSS) by **directly instantiating IdempotentService instances** - NOT through TRAX coordinator or saga submission.

### Purpose

For a saga S with steps s[1], s[2], ..., s[K] requiring prerequisites c[1], c[2], ..., c[L]:

To test step s[T]:
1. Run prerequisites c[1]..c[L] to prepare the environment
2. Execute steps s[1]..s[T-1] sequentially (all green paths) by directly calling IdempotentService.ExecuteSync()
3. Execute step s[T] and verify its output
4. Optionally verify cumulative state from all prior steps
5. Use direct JSON-RPC to blockchain (Alvin) to assert contract state

### Test Naming Convention

```
TestIndTrxSS{SagaShortName}_S{N}_{StepName}_{Variant}
```

| Component | Description |
|-----------|-------------|
| `IndTrxSS` | **Ind**ividual **Tr**a**x** **S**aga **S**tep |
| `{SagaShortName}` | Short saga identifier |
| `S{N}` | Step number (1-indexed) |
| `{StepName}` | Step name in CamelCase |
| `{Variant}` | Test variant (Green, Cumulative, error type, CompensationVerified) |

### Variant Suffixes

| Suffix | Meaning |
|--------|---------|
| `_Green` | Happy path - step executes successfully |
| `_Cumulative` | Green + verify all s[1..T-1] state persisted correctly |
| `_{InputError}` | Input validation failure |
| `_{ExecutionError}` | Execution failure (blockchain, service, timeout) |
| `_CompensationVerified` | Verify CompensateSync() undoes step correctly |

---

## Architecture: Direct IdempotentService Testing

### Key Principle

**NO TRAX coordinator. NO saga submission.** We instantiate IdempotentService structs directly and call `ExecuteSync()`.

### Pattern

```go
func TestIndTrxSS{Saga}_S{N}_{Step}_{Variant}(t *testing.T) {
    // 1. Setup test database and stores
    db := setupTestDatabaseForIndTrxSS(t)
    accountStore := createTestAccountStore(t, db)
    laserStore := createTestLaserStore(t, db)

    // 2. Update package-level stores (required by IdempotentService)
    accmgr_executors.UpdateAccountStore(accountStore)
    lasersvc_executors.UpdateLaserStore(laserStore, executorRegistry)

    // 3. Run prerequisites c[1]..c[L]
    setupPrerequisites(t)

    // 4. Execute prior steps s[1]..s[T-1] sequentially
    ctx := context.Background()
    stepOutputs := make(map[int]map[string]string)

    for i := 1; i < T; i++ {
        svc := createIdempotentServiceForStep(i)
        input := buildInputForStep(i, stepOutputs)
        result, err := svc.ExecuteSync(ctx, fmt.Sprintf("test-step-%d", i), input)
        require.NoError(t, err)
        require.Nil(t, result.Error)
        stepOutputs[i] = result.Result
    }

    // 5. Execute target step s[T]
    targetSvc := createIdempotentServiceForStep(T)
    targetInput := buildInputForStep(T, stepOutputs)
    targetResult, err := targetSvc.ExecuteSync(ctx, "test-step-T", targetInput)

    // 6. Assert step output
    require.NoError(t, err)
    require.Nil(t, targetResult.Error)
    assert.NotEmpty(t, targetResult.Result["expected_output_key"])

    // 7. (Optional) Verify cumulative state
    verifyCumulativeState(t, stepOutputs)

    // 8. (For EthBC) JSON-RPC assertions
    verifyOnChainState(t, targetResult.Result)
}
```

### IdempotentService Instantiation

Each step has its own IdempotentService struct. Example:

```go
// For accmgr step
import accmgr_ls "pkg/daemons/accmgr/trax/executors/establish_new_legal_structure_for_participant"

svc := &accmgr_ls.CreateLegalStructureRecord_IdempotentService{
    ExecutionResults:    make(map[string]*trax.IdempotentServiceExecutionResult),
    CompensationResults: make(map[string]*trax.IdempotentServiceExecutionResult),
}

// For lasersvc step
import lasersvc_ls "pkg/daemons/lasersvc/trax/executors/establish_new_legal_structure_for_participant"

svc := &lasersvc_ls.CreateOwnerSlots_IdempotentService{
    ExecutionResults:    make(map[string]*trax.IdempotentServiceExecutionResult),
    CompensationResults: make(map[string]*trax.IdempotentServiceExecutionResult),
}
```

### Store Initialization

Before calling any IdempotentService:

```go
// For accmgr steps - update package-level store
accmgr_establish.UpdateAccountStore(accountStore)
accmgr_core.UpdateAccountStore(accountStore)
accmgr_treasury.UpdateAccountStore(accountStore)

// For lasersvc steps - update package-level store and registry
lasersvc_establish.UpdateLaserStore(laserStore, executorRegistry)
lasersvc_core.UpdateLaserStore(laserStore, executorRegistry)
lasersvc_treasury.UpdateLaserStore(laserStore, executorRegistry)
```

---

## Saga 1: Establish Legal Structure (8 steps)

**Saga ID**: `establish_new_legal_structure_for_participant`
**Short Name**: `EstablishLegalStructure`

### Prerequisites (c[1]..c[4])

| # | Prerequisite | Setup Method |
|---|-------------|--------------|
| c[1] | Target participant exists and is enabled | `createTestParticipant(t, iid)` |
| c[2] | Parent participant exists (optional) | `createTestParticipant(t, iid)` |
| c[3] | All partner participants exist and are enabled | `createTestParticipants(t, iids)` |
| c[4] | LASER executors configured (crown_executor_iid) | `configureTestExecutors(t)` |

### Steps (s[1]..s[8])

| Step | Name | Service | IdempotentService Struct |
|------|------|---------|-------------------------|
| s[1] | verify_new_legal_structure_inputs | accmgr | `VerifyInputs_IdempotentService` |
| s[2] | create_legal_structure_record | accmgr | `CreateLegalStructureRecord_IdempotentService` |
| s[3] | create_account_for_legal_structure_owner | accmgr | `CreateOwnerAccount_IdempotentService` |
| s[4] | create_laser_slots_for_legal_structure_owner | lasersvc | `CreateOwnerSlots_IdempotentService` |
| s[5] | attach_eth_address_to_legal_structure_owner_account | accmgr | `AttachOwnerEthAddress_IdempotentService` |
| s[6] | create_accounts_for_legal_structure_partners | accmgr | `CreatePartnerAccounts_IdempotentService` |
| s[7] | create_laser_slots_for_legal_structure_partners | lasersvc | `CreatePartnerSlots_IdempotentService` |
| s[8] | attach_eth_addresses_to_legal_structure_partner_accounts | accmgr | `AttachPartnerEthAddresses_IdempotentService` |

### Input/Output Flow

```
s[1] Input: target_participant_iid, parent_participant_iid?, display_names, type, partner_participant_iids
s[1] Output: verification_status

s[2] Input: (saga inputs)
s[2] Output: legal_structure_iid, participant_list_iid

s[3] Input: target_participant_iid, legal_structure_iid
s[3] Output: owner_account_iid

s[4] Input: owner_account_iid
s[4] Output: owner_account_eth_addr

s[5] Input: owner_account_iid, owner_account_eth_addr
s[5] Output: (status)

s[6] Input: partner_participant_iids, legal_structure_iid
s[6] Output: partner_account_iids (JSON array)

s[7] Input: partner_account_iids
s[7] Output: partner_account_eth_addrs (JSON array)

s[8] Input: partner_account_iids, partner_account_eth_addrs
s[8] Output: (status)
```

### Test Specifications

#### Phase 1: Green Path Tests

- [ ] 1.1.1 `TestIndTrxSSEstablishLegalStructure_S1_VerifyInputs_Green`
- [ ] 1.1.2 `TestIndTrxSSEstablishLegalStructure_S2_CreateLegalStructureRecord_Green`
- [ ] 1.1.3 `TestIndTrxSSEstablishLegalStructure_S3_CreateOwnerAccount_Green`
- [ ] 1.1.4 `TestIndTrxSSEstablishLegalStructure_S4_CreateOwnerSlots_Green`
- [ ] 1.1.5 `TestIndTrxSSEstablishLegalStructure_S5_AttachOwnerEthAddress_Green`
- [ ] 1.1.6 `TestIndTrxSSEstablishLegalStructure_S6_CreatePartnerAccounts_Green`
- [ ] 1.1.7 `TestIndTrxSSEstablishLegalStructure_S7_CreatePartnerSlots_Green`
- [ ] 1.1.8 `TestIndTrxSSEstablishLegalStructure_S8_AttachPartnerEthAddresses_Green`

#### Phase 2: Cumulative State Tests

- [ ] 1.2.1 `TestIndTrxSSEstablishLegalStructure_S4_CreateOwnerSlots_Cumulative`
  - After s[4], verify: LegalStructure exists, ParticipantList exists, OwnerAccount exists
- [ ] 1.2.2 `TestIndTrxSSEstablishLegalStructure_S8_AttachPartnerEthAddresses_Cumulative`
  - After s[8], verify: All records exist, all accounts ACTIVE, all slots created

#### Phase 3: Input Validation Red Path Tests

- [ ] 1.3.1 `TestIndTrxSSEstablishLegalStructure_S1_VerifyInputs_MissingTargetParticipant`
- [ ] 1.3.2 `TestIndTrxSSEstablishLegalStructure_S1_VerifyInputs_MissingDisplayNames`
- [ ] 1.3.3 `TestIndTrxSSEstablishLegalStructure_S1_VerifyInputs_InvalidType`
- [ ] 1.3.4 `TestIndTrxSSEstablishLegalStructure_S1_VerifyInputs_EmptyPartnersList`
- [ ] 1.3.5 `TestIndTrxSSEstablishLegalStructure_S1_VerifyInputs_NonExistentPartner`
- [ ] 1.3.6 `TestIndTrxSSEstablishLegalStructure_S1_VerifyInputs_DisabledParticipant`

#### Phase 4: Execution Failure Red Path Tests

- [ ] 1.4.1 `TestIndTrxSSEstablishLegalStructure_S4_CreateOwnerSlots_ExecutorUnavailable`
- [ ] 1.4.2 `TestIndTrxSSEstablishLegalStructure_S7_CreatePartnerSlots_SlotCreationFails`

#### Phase 5: Compensation Verification Tests

- [ ] 1.5.1 `TestIndTrxSSEstablishLegalStructure_S2_CreateLegalStructureRecord_CompensationVerified`
  - Execute s[2], then call CompensateSync(), verify LegalStructure deleted
- [ ] 1.5.2 `TestIndTrxSSEstablishLegalStructure_S3_CreateOwnerAccount_CompensationVerified`
  - Execute s[3], then call CompensateSync(), verify Account deleted
- [ ] 1.5.3 `TestIndTrxSSEstablishLegalStructure_S4_CreateOwnerSlots_CompensationVerified`
  - Execute s[4], then call CompensateSync(), verify slots and slot_links deleted
- [ ] 1.5.4 `TestIndTrxSSEstablishLegalStructure_S6_CreatePartnerAccounts_CompensationVerified`
  - Execute s[6], then call CompensateSync(), verify all partner accounts deleted (reverse order)

---

## Saga 2: Deploy Core Legal Mechanisms (10 steps)

**Saga ID**: `deploy_core_legal_mechanisms_for_legal_structure`
**Short Name**: `DeployCoreLegalMechanism`

### Prerequisites (c[1]..c[6])

| # | Prerequisite | Setup Method |
|---|-------------|--------------|
| c[1] | Legal structure exists (PARTNERSHIP type) | Run Saga 1 or `createTestLegalStructure(t)` |
| c[2] | Deployer account with SIGNER slot | `createDeployerWithSignerAccount(t)` |
| c[3] | All partner accounts with SIGNER slots | Created by Saga 1 |
| c[4] | Execution runtime configured | `configureTestExecutionRuntime(t)` |
| c[5] | AuthzFacet available in lattice | Pre-deployed in test environment |
| c[6] | Deployer funded with ETH (EthBC mode) | `fundWithETH(t, address, amount)` |

### Steps (s[1]..s[10])

| Step | Name | Service | IdempotentService Struct |
|------|------|---------|-------------------------|
| s[1] | verify_legal_mechanism_inputs | accmgr | `VerifyInputs_IdempotentService` |
| s[2] | create_task_manager_legal_mechanism | accmgr | `CreateTaskManagerMechanism_IdempotentService` |
| s[3] | create_authz_source_legal_mechanism | accmgr | `CreateAuthzSourceMechanism_IdempotentService` |
| s[4] | deploy_task_manager_contract | lasersvc | `DeployTaskManager_IdempotentService` |
| s[5] | create_task_manager_deployment_record | accmgr | `CreateTaskManagerDeployment_IdempotentService` |
| s[6] | deploy_authz_diamond_contract | lasersvc | `DeployAuthzDiamond_IdempotentService` |
| s[7] | initialize_authz_diamond | lasersvc | `InitializeAuthzDiamond_IdempotentService` |
| s[8] | create_authz_source_deployment_record | accmgr | `CreateAuthzSourceDeployment_IdempotentService` |
| s[9] | deploy_authz_facet | lasersvc | `DeployAuthzFacet_IdempotentService` |
| s[10] | add_authz_facet_to_diamond | lasersvc | `AddAuthzFacet_IdempotentService` |

### Test Specifications

#### Phase 1: Green Path Tests

- [ ] 2.1.1 `TestIndTrxSSDeployCoreLegalMechanism_S1_VerifyInputs_Green`
- [ ] 2.1.2 `TestIndTrxSSDeployCoreLegalMechanism_S2_CreateTaskManagerMechanism_Green`
- [ ] 2.1.3 `TestIndTrxSSDeployCoreLegalMechanism_S3_CreateAuthzSourceMechanism_Green`
- [ ] 2.1.4 `TestIndTrxSSDeployCoreLegalMechanism_S4_DeployTaskManager_Green`
- [ ] 2.1.5 `TestIndTrxSSDeployCoreLegalMechanism_S5_CreateTaskManagerDeployment_Green`
- [ ] 2.1.6 `TestIndTrxSSDeployCoreLegalMechanism_S6_DeployAuthzDiamond_Green`
- [ ] 2.1.7 `TestIndTrxSSDeployCoreLegalMechanism_S7_InitializeAuthzDiamond_Green`
- [ ] 2.1.8 `TestIndTrxSSDeployCoreLegalMechanism_S8_CreateAuthzSourceDeployment_Green`
- [ ] 2.1.9 `TestIndTrxSSDeployCoreLegalMechanism_S9_DeployAuthzFacet_Green`
- [ ] 2.1.10 `TestIndTrxSSDeployCoreLegalMechanism_S10_AddAuthzFacet_Green`

#### Phase 2: Cumulative State Tests

- [ ] 2.2.1 `TestIndTrxSSDeployCoreLegalMechanism_S5_CreateTaskManagerDeployment_Cumulative`
  - Verify: LegalMechanism(VOTING) exists, TaskManager contract deployed
- [ ] 2.2.2 `TestIndTrxSSDeployCoreLegalMechanism_S10_AddAuthzFacet_Cumulative`
  - Verify: All mechanisms, deployments, contracts, AuthzDiamond initialized with facet

#### Phase 3: Input Validation Red Path Tests

- [ ] 2.3.1 `TestIndTrxSSDeployCoreLegalMechanism_S1_VerifyInputs_InvalidLegalStructure`
- [ ] 2.3.2 `TestIndTrxSSDeployCoreLegalMechanism_S1_VerifyInputs_DeployerNotSigner`
- [ ] 2.3.3 `TestIndTrxSSDeployCoreLegalMechanism_S1_VerifyInputs_OverlappingAuthzAdmins`
- [ ] 2.3.4 `TestIndTrxSSDeployCoreLegalMechanism_S1_VerifyInputs_PartnerNotActive`

#### Phase 4: Execution Failure Red Path Tests

- [ ] 2.4.1 `TestIndTrxSSDeployCoreLegalMechanism_S4_DeployTaskManager_InsufficientGas`
- [ ] 2.4.2 `TestIndTrxSSDeployCoreLegalMechanism_S9_DeployAuthzFacet_InvalidVersion`

#### Phase 5: Compensation Verification Tests

- [ ] 2.5.1 `TestIndTrxSSDeployCoreLegalMechanism_S2_CreateTaskManagerMechanism_CompensationVerified`
- [ ] 2.5.2 `TestIndTrxSSDeployCoreLegalMechanism_S5_CreateTaskManagerDeployment_CompensationVerified`

#### Phase 6: On-Chain Assertion Tests (EthBC only)

- [ ] 2.6.1 `TestIndTrxSSDeployCoreLegalMechanism_S4_DeployTaskManager_VerifyContract`
  - JSON-RPC: Verify contract exists at returned address
- [ ] 2.6.2 `TestIndTrxSSDeployCoreLegalMechanism_S7_InitializeAuthzDiamond_VerifyState`
  - JSON-RPC: Verify TaskManager reference set, admins configured
- [ ] 2.6.3 `TestIndTrxSSDeployCoreLegalMechanism_S10_AddAuthzFacet_VerifyFacet`
  - JSON-RPC: Verify AuthzFacet added to diamond

---

## Saga 3: Deploy Treasury Legal Mechanisms (18 steps)

**Saga ID**: `deploy_treasury_legal_mechanisms_for_legal_structure`
**Short Name**: `DeployTreasuryLegalMechanism`

### Prerequisites (c[1]..c[8])

| # | Prerequisite | Setup Method |
|---|-------------|--------------|
| c[1] | Legal structure exists (PARTNERSHIP type) | Saga 1 |
| c[2] | Core Legal Mechanisms deployed | Saga 2 |
| c[3] | Deployer account with SIGNER slot | `createDeployerWithSignerAccount(t)` |
| c[4] | admin_partner is partner AND TaskManager admin | From Saga 2 inputs |
| c[5] | authz_admin is AuthzDiamond admin | From Saga 2 inputs |
| c[6] | All vault facets available in lattice | Pre-deployed |
| c[7] | Execution runtime configured | `configureTestExecutionRuntime(t)` |
| c[8] | Deployer funded with ETH (EthBC mode) | `fundWithETH(t, address, amount)` |

### Steps (s[1]..s[18])

| Step | Name | Service | IdempotentService Struct |
|------|------|---------|-------------------------|
| s[1] | verify_treasury_mechanism_inputs | accmgr | `VerifyInputs_IdempotentService` |
| s[2] | create_rac_legal_mechanism | accmgr | `CreateRacMechanism_IdempotentService` |
| s[3] | create_treasury_legal_mechanism | accmgr | `CreateTreasuryMechanism_IdempotentService` |
| s[4] | deploy_rac_diamond_contract | lasersvc | `DeployRacDiamond_IdempotentService` |
| s[5] | initialize_rac_diamond | lasersvc | `InitializeRacDiamond_IdempotentService` |
| s[6] | grant_add_facets_permission_to_admin_rac | lasersvc | `GrantAddFacetsPermRac_IdempotentService` |
| s[7] | add_rac_facet_to_rac_diamond | lasersvc | `AddRacFacet_IdempotentService` |
| s[8] | create_rac_deployment_record | accmgr | `CreateRacDeployment_IdempotentService` |
| s[9] | deploy_trezor_diamond_contract | lasersvc | `DeployTrezorDiamond_IdempotentService` |
| s[10] | initialize_trezor_diamond | lasersvc | `InitializeTrezorDiamond_IdempotentService` |
| s[11] | grant_add_facets_permission_to_admin_trezor | lasersvc | `GrantAddFacetsPermTrezor_IdempotentService` |
| s[12] | add_vault_facets_to_trezor_diamond | lasersvc | `AddVaultFacets_IdempotentService` |
| s[13] | grant_create_ledger_permission | lasersvc | `GrantCreateLedgerPerm_IdempotentService` |
| s[14] | create_default_ledger | lasersvc | `CreateDefaultLedger_IdempotentService` |
| s[15] | grant_set_address_permission | lasersvc | `GrantSetAddressPerm_IdempotentService` |
| s[16] | grant_set_int_permission | lasersvc | `GrantSetIntPerm_IdempotentService` |
| s[17] | configure_rac_properties | lasersvc | `ConfigureRacProperties_IdempotentService` |
| s[18] | create_treasury_deployment_record | accmgr | `CreateTreasuryDeployment_IdempotentService` |

### Test Specifications

#### Phase 1: Green Path Tests

- [ ] 3.1.1 `TestIndTrxSSDeployTreasuryLegalMechanism_S1_VerifyInputs_Green`
- [ ] 3.1.2 `TestIndTrxSSDeployTreasuryLegalMechanism_S2_CreateRacMechanism_Green`
- [ ] 3.1.3 `TestIndTrxSSDeployTreasuryLegalMechanism_S3_CreateTreasuryMechanism_Green`
- [ ] 3.1.4 `TestIndTrxSSDeployTreasuryLegalMechanism_S4_DeployRacDiamond_Green`
- [ ] 3.1.5 `TestIndTrxSSDeployTreasuryLegalMechanism_S5_InitializeRacDiamond_Green`
- [ ] 3.1.6 `TestIndTrxSSDeployTreasuryLegalMechanism_S6_GrantAddFacetsPermRac_Green`
- [ ] 3.1.7 `TestIndTrxSSDeployTreasuryLegalMechanism_S7_AddRacFacet_Green`
- [ ] 3.1.8 `TestIndTrxSSDeployTreasuryLegalMechanism_S8_CreateRacDeployment_Green`
- [ ] 3.1.9 `TestIndTrxSSDeployTreasuryLegalMechanism_S9_DeployTrezorDiamond_Green`
- [ ] 3.1.10 `TestIndTrxSSDeployTreasuryLegalMechanism_S10_InitializeTrezorDiamond_Green`
- [ ] 3.1.11 `TestIndTrxSSDeployTreasuryLegalMechanism_S11_GrantAddFacetsPermTrezor_Green`
- [ ] 3.1.12 `TestIndTrxSSDeployTreasuryLegalMechanism_S12_AddVaultFacets_Green`
- [ ] 3.1.13 `TestIndTrxSSDeployTreasuryLegalMechanism_S13_GrantCreateLedgerPerm_Green`
- [ ] 3.1.14 `TestIndTrxSSDeployTreasuryLegalMechanism_S14_CreateDefaultLedger_Green`
- [ ] 3.1.15 `TestIndTrxSSDeployTreasuryLegalMechanism_S15_GrantSetAddressPerm_Green`
- [ ] 3.1.16 `TestIndTrxSSDeployTreasuryLegalMechanism_S16_GrantSetIntPerm_Green`
- [ ] 3.1.17 `TestIndTrxSSDeployTreasuryLegalMechanism_S17_ConfigureRacProperties_Green`
- [ ] 3.1.18 `TestIndTrxSSDeployTreasuryLegalMechanism_S18_CreateTreasuryDeployment_Green`

#### Phase 2: Cumulative State Tests

- [ ] 3.2.1 `TestIndTrxSSDeployTreasuryLegalMechanism_S8_CreateRacDeployment_Cumulative`
  - Verify: RAC mechanism, RAC diamond deployed and initialized with facet
- [ ] 3.2.2 `TestIndTrxSSDeployTreasuryLegalMechanism_S14_CreateDefaultLedger_Cumulative`
  - Verify: Trezor diamond with all 7 facets, DEFAULT ledger created
- [ ] 3.2.3 `TestIndTrxSSDeployTreasuryLegalMechanism_S18_CreateTreasuryDeployment_Cumulative`
  - Verify: Full treasury setup, RAC properties configured

#### Phase 3: Input Validation Red Path Tests

- [ ] 3.3.1 `TestIndTrxSSDeployTreasuryLegalMechanism_S1_VerifyInputs_MissingCoreMechanisms`
- [ ] 3.3.2 `TestIndTrxSSDeployTreasuryLegalMechanism_S1_VerifyInputs_TreasuryAlreadyExists`
- [ ] 3.3.3 `TestIndTrxSSDeployTreasuryLegalMechanism_S1_VerifyInputs_AdminNotPartner`
- [ ] 3.3.4 `TestIndTrxSSDeployTreasuryLegalMechanism_S1_VerifyInputs_AdminNotTaskManagerAdmin`
- [ ] 3.3.5 `TestIndTrxSSDeployTreasuryLegalMechanism_S1_VerifyInputs_InvalidAuthzAdmin`

#### Phase 4: Execution Failure Red Path Tests

- [ ] 3.4.1 `TestIndTrxSSDeployTreasuryLegalMechanism_S7_AddRacFacet_InvalidVersion`
- [ ] 3.4.2 `TestIndTrxSSDeployTreasuryLegalMechanism_S12_AddVaultFacets_MissingFacet`
- [ ] 3.4.3 `TestIndTrxSSDeployTreasuryLegalMechanism_S14_CreateDefaultLedger_MissingPermission`

#### Phase 5: Compensation Verification Tests

- [ ] 3.5.1 `TestIndTrxSSDeployTreasuryLegalMechanism_S2_CreateRacMechanism_CompensationVerified`
- [ ] 3.5.2 `TestIndTrxSSDeployTreasuryLegalMechanism_S8_CreateRacDeployment_CompensationVerified`

#### Phase 6: On-Chain Assertion Tests (EthBC only)

- [ ] 3.6.1 `TestIndTrxSSDeployTreasuryLegalMechanism_S7_AddRacFacet_VerifyFacet`
- [ ] 3.6.2 `TestIndTrxSSDeployTreasuryLegalMechanism_S12_AddVaultFacets_VerifyAllFacets`
- [ ] 3.6.3 `TestIndTrxSSDeployTreasuryLegalMechanism_S14_CreateDefaultLedger_VerifyLedger`
  - JSON-RPC: Query getNrOfLedgers() == 1, getLedgerInfo(1) returns "DEFAULT"
- [ ] 3.6.4 `TestIndTrxSSDeployTreasuryLegalMechanism_S17_ConfigureRacProperties_VerifyProps`
  - JSON-RPC: Query getInt("rac.domain.id") == 999, getAddress("rac.address") == RAC_addr

---

## Implementation Phases

### Phase 1: Test Infrastructure

- [ ] 1.1 Create test file: `tests/e2e/laser/indtrxss_test.go`
- [ ] 1.2 Create helper file: `tests/e2e/laser/indtrxss_helpers_test.go`
- [ ] 1.3 Implement `setupTestDatabaseForIndTrxSS(t)` - isolated DB per test
- [ ] 1.4 Implement `createTestAccountStore(t, db)` - PostgreSQL store with test DB
- [ ] 1.5 Implement `createTestLaserStore(t, db)` - LASER store with test DB
- [ ] 1.6 Implement `configureTestExecutors(t)` - E1/E2 executor setup

### Phase 2: IdempotentService Factory Functions

- [ ] 2.1 `createEstablishLegalStructureStep(stepNum int) trax.IdempotentService`
- [ ] 2.2 `createDeployCoreLegalMechanismStep(stepNum int) trax.IdempotentService`
- [ ] 2.3 `createDeployTreasuryLegalMechanismStep(stepNum int) trax.IdempotentService`

### Phase 3: Input Builder Functions

- [ ] 3.1 `buildEstablishLegalStructureInput(stepNum int, priorOutputs map[int]map[string]string) map[string]string`
- [ ] 3.2 `buildDeployCoreLegalMechanismInput(stepNum int, priorOutputs map[int]map[string]string) map[string]string`
- [ ] 3.3 `buildDeployTreasuryLegalMechanismInput(stepNum int, priorOutputs map[int]map[string]string) map[string]string`

### Phase 4: Assertion Helpers

- [ ] 4.1 `assertLegalStructureExists(t, iid string)`
- [ ] 4.2 `assertLegalMechanismExists(t, iid string, mechanismType string)`
- [ ] 4.3 `assertDeploymentRecordExists(t, iid string)`
- [ ] 4.4 `assertAccountActive(t, iid string)`
- [ ] 4.5 `assertSlotExists(t, slotAddress string)`
- [ ] 4.6 `assertSlotHasTag(t, slotAddress string, tag string)`

### Phase 5: On-Chain Assertion Helpers (EthBC)

- [ ] 5.1 `assertContractDeployed(t, address string)` - via eth_getCode
- [ ] 5.2 `assertTaskManagerRoles(t, address string, admins, approvers, executors []string)`
- [ ] 5.3 `assertAuthzDiamondInitialized(t, address string, taskManagerAddr string)`
- [ ] 5.4 `assertDiamondHasFacet(t, diamondAddr string, facetName string)`
- [ ] 5.5 `assertLedgerExists(t, trezorAddr string, ledgerId int, name string)`
- [ ] 5.6 `assertRacPropertyInt(t, trezorAddr string, key string, value int)`
- [ ] 5.7 `assertRacPropertyAddress(t, trezorAddr string, key string, addr string)`

### Phase 6: Saga 1 Tests (EstablishLegalStructure)

- [ ] 6.1 Implement all Phase 1 green path tests (8 tests)
- [ ] 6.2 Implement Phase 2 cumulative tests (2 tests)
- [ ] 6.3 Implement Phase 3 input validation tests (6 tests)
- [ ] 6.4 Implement Phase 4 execution failure tests (2 tests)
- [ ] 6.5 Implement Phase 5 compensation tests (4 tests)

### Phase 7: Saga 2 Tests (DeployCoreLegalMechanism)

- [ ] 7.1 Implement all Phase 1 green path tests (10 tests)
- [ ] 7.2 Implement Phase 2 cumulative tests (2 tests)
- [ ] 7.3 Implement Phase 3 input validation tests (4 tests)
- [ ] 7.4 Implement Phase 4 execution failure tests (2 tests)
- [ ] 7.5 Implement Phase 5 compensation tests (2 tests)
- [ ] 7.6 Implement Phase 6 on-chain assertion tests (3 tests)

### Phase 8: Saga 3 Tests (DeployTreasuryLegalMechanism)

- [ ] 8.1 Implement all Phase 1 green path tests (18 tests)
- [ ] 8.2 Implement Phase 2 cumulative tests (3 tests)
- [ ] 8.3 Implement Phase 3 input validation tests (5 tests)
- [ ] 8.4 Implement Phase 4 execution failure tests (3 tests)
- [ ] 8.5 Implement Phase 5 compensation tests (2 tests)
- [ ] 8.6 Implement Phase 6 on-chain assertion tests (4 tests)

---

## Files Summary

### New Files

| File | Description |
|------|-------------|
| `tests/e2e/laser/indtrxss_test.go` | Main test file with all IndTrxSS tests |
| `tests/e2e/laser/indtrxss_helpers_test.go` | Helper functions for IndTrxSS tests |
| `tests/e2e/laser/indtrxss_onchain_helpers_test.go` | JSON-RPC assertion helpers (EthBC) |

### Modified Files

| File | Changes |
|------|---------|
| `tests/e2e/laser/e2e_helpers_test.go` | Add shared setup functions if needed |

---

## Test Count Summary

| Saga | Green | Cumulative | Input Validation | Execution Failure | Compensation | On-Chain | Total |
|------|-------|------------|------------------|-------------------|--------------|----------|-------|
| EstablishLegalStructure | 8 | 2 | 6 | 2 | 4 | 0 | 22 |
| DeployCoreLegalMechanism | 10 | 2 | 4 | 2 | 2 | 3 | 23 |
| DeployTreasuryLegalMechanism | 18 | 3 | 5 | 3 | 2 | 4 | 35 |
| **Total** | **36** | **7** | **15** | **7** | **8** | **7** | **80** |

---

## Success Criteria

- [ ] All 80 tests pass in EthBC mode
- [ ] All non-EthBC tests pass in RDBMS mode
- [ ] Test execution is deterministic (no flaky tests)
- [ ] Each step's idempotence is verified (second call returns cached result)
- [ ] Compensation logic properly undoes each step's changes
- [ ] On-chain assertions correctly query contract state
- [ ] Tests are isolated (no state leakage between tests)

---

## Notes

- **No TRAX coordinator**: All tests instantiate IdempotentService directly
- **No saga submission**: Steps are executed individually via ExecuteSync()
- **Package-level store updates**: Required before each test to point to test database
- **Idempotent keys**: Each test uses unique keys (e.g., "test-s1-green", "test-s4-compensation")
- **EthBC-only tests**: On-chain assertion tests are skipped in RDBMS mode
- **Test isolation**: Each test gets its own database instance
- **Step chaining**: Prior step outputs are passed to subsequent steps via map
