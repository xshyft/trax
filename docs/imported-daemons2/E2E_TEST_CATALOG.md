# E2E Test Catalog

This document provides a comprehensive catalog of all End-to-End (E2E) tests in the Agora daemons codebase, organized by functional groups and sorted by complexity/importance (most complex at top, simplest at bottom).

**Total Tests: ~395 test functions across 60+ test files**

**Location**: `tests/e2e/`

---

## Table of Contents

1. [TRAX Saga Orchestration Tests](#group-1-trax-saga-orchestration-tests) - ⭐⭐⭐⭐⭐ HIGHEST
2. [Transfer & Authorization TRAX Tests](#group-2-transfer--authorization-trax-tests) - ⭐⭐⭐⭐⭐ HIGHEST
3. [Individual Saga Step Tests (IndTrxSS)](#group-3-individual-saga-step-tests-indtrxss) - ⭐⭐⭐⭐ HIGH
4. [Legal Mechanism Deployment Tests](#group-4-legal-mechanism-deployment-tests) - ⭐⭐⭐⭐ HIGH
5. [Diamond & Authorization Tests](#group-5-diamond--authorization-tests) - ⭐⭐⭐⭐ HIGH
6. [ERC20 Token Operations Tests](#group-6-erc20-token-operations-tests) - ⭐⭐⭐⭐ HIGH
7. [Cash Token Deployment Tests](#group-7-cash-token-deployment-tests) - ⭐⭐⭐⭐ HIGH
8. [Participant CLI (PaCli) Tests](#group-8-participant-cli-pacli-tests) - ⭐⭐⭐⭐ HIGH to ⭐⭐ MEDIUM
9. [Legal Participant & Structure Tests](#group-9-legal-participant--structure-tests) - ⭐⭐⭐⭐ HIGH to ⭐⭐⭐ MEDIUM
10. [Task Manager & Multi-Signer Tests](#group-10-task-manager--multi-signer-tests) - ⭐⭐⭐⭐ HIGH to ⭐⭐⭐ MEDIUM
11. [Deposit & Treasury Tests](#group-11-deposit--treasury-tests) - ⭐⭐⭐⭐ HIGH to ⭐⭐⭐ MEDIUM
12. [Signer & Key Management Tests](#group-12-signer--key-management-tests) - ⭐⭐⭐ MEDIUM
13. [Slot & Seeding Tests](#group-13-slot--seeding-tests) - ⭐⭐⭐ MEDIUM
14. [External Call & Relay Tests](#group-14-external-call--relay-tests) - ⭐⭐⭐ MEDIUM
15. [Deploy Facets TRAX Tests](#group-15-deploy-facets-trax-tests) - ⭐⭐⭐ MEDIUM
16. [Instrument Manager Tests](#group-16-instrument-manager-tests) - ⭐⭐⭐ MEDIUM to HIGH
17. [LASER Cross-Instance Tests](#group-17-laser-cross-instance-tests) - ⭐⭐⭐ MEDIUM
18. [Import & Data Migration Tests](#group-18-import--data-migration-tests) - ⭐⭐⭐ MEDIUM
19. [ERC20 Facet Routing Tests](#group-19-erc20-facet-routing-tests) - ⭐⭐ MEDIUM to LOW
20. [Executor CRUD Tests](#group-20-executor-crud-tests) - ⭐⭐ LOW
21. [Router CRUD Tests](#group-21-router-crud-tests) - ⭐⭐ LOW
22. [Execution Runtime CRUD Tests](#group-22-execution-runtime-crud-tests) - ⭐⭐ LOW
23. [CSD Message Gateway REST API Tests](#group-23-csd-message-gateway-rest-api-tests) - ⭐⭐ LOW
24. [Smoke Tests (Health Checks)](#group-24-smoke-tests-health-checks) - ⭐ LOWEST
25. [Config & Test Infrastructure Tests](#group-25-config--test-infrastructure-tests) - ⭐ LOWEST
26. [Listing Manager CRUD Tests](#group-26-listing-manager-crud-tests) - ⭐⭐ LOW
27. [Security Listing Deployment Tests](#group-27-security-listing-deployment-tests) - ⭐⭐⭐⭐ HIGH
28. [Market Manager CRUD Tests](#group-28-market-manager-crud-tests) - ⭐⭐ LOW
29. [FIX SecurityDefinition Tests](#group-29-fix-securitydefinition-tests) - ⭐⭐ LOW
32. [FIX NewOrderSingle → Saga Integration Tests](#group-32-fix-newordersingle--saga-integration-tests) - ⭐⭐⭐⭐ HIGH
33. [FIX Client NOS Sending Tests](#group-33-fix-client-nos-sending-tests) - ⭐⭐⭐⭐ HIGH
35. [Fund Account Command Tests](#group-35-fund-account-command-tests) - ⭐⭐⭐⭐ HIGH
36. [Trade Indexer Tests](#group-36-trade-indexer-tests) - ⭐⭐⭐⭐ HIGH
37. [Create Investor Order Saga Tests](#group-37-create-investor-order-saga-tests) - ⭐⭐⭐⭐ HIGH
38. [FIX Sender Report Delivery Tests](#group-38-fix-sender-report-delivery-tests) - ⭐⭐⭐⭐ HIGH
39. [Treasury Indexer Tests](#group-39-treasury-indexer-tests) - ⭐⭐⭐⭐ HIGH
43. [FIX Session Reliability Tests](#category-43-fix-session-reliability) - ⭐⭐⭐⭐⭐ HIGHEST

---

## Complexity Legend

| Symbol | Level | Characteristics |
|--------|-------|-----------------|
| ⭐⭐⭐⭐⭐ | HIGHEST | Multi-service coordination, parallel saga execution, stress testing, full blockchain workflows |
| ⭐⭐⭐⭐ | HIGH | Full saga flows, diamond deployments, complex multi-step workflows |
| ⭐⭐⭐ | MEDIUM | Individual saga steps, single blockchain operations, multi-step CRUD |
| ⭐⭐ | LOW | Basic CRUD operations, validation tests, simple queries |
| ⭐ | LOWEST | Health checks, smoke tests, schema verification |

---

## Group 1a: TRAX Saga Orchestration Tests

**Complexity**: ⭐⭐⭐⭐⭐ HIGHEST

**Makefile Target**: `make trax-e2e-cat1`

**Files**:
- `tests/e2e/trax/seven_step_saga_test.go`
- `tests/e2e/trax/topology_test.go`
- `tests/e2e/trax/compensation_test.go`
- `tests/e2e/trax/deep_sub_saga_test.go`

**Description**: Core TRAX saga orchestration framework tests. These test the fundamental saga execution engine including parallel execution, reliability under load, RabbitMQ topic exchange topology verification, saga compensation (forward recovery failure handling), and deep sub-saga hierarchy spawning with cascading compensation.

**NOTE**: These tests are in the `tests/e2e/trax/` directory and use the simpler TRAX E2E docker-compose environment (no Account Manager needed).

**Dependencies**: traxctrl, 3x traxcoord, multiple executors, idempotency backend

### Test Functions

| Test Function | Complexity | Description | Key Operations |
|--------------|------------|-------------|----------------|
| `TestTenParallelSagasRandomized` | ⭐⭐⭐⭐⭐ | Stress test with 10 parallel sagas | Randomized submission intervals (100-500ms), concurrent goroutines, MVCC row-locking validation |
| `TestSevenStepSagaReliability` | ⭐⭐⭐⭐⭐ | Reliability test with 20 sequential sagas | 180s timeout per saga for re-executions, idempotency backend stability |
| `TestTwoParallelSagasWithDelay` | ⭐⭐⭐⭐ | Concurrent saga execution test | 2 sagas with 3-second delay, MVCC row-locking verification |
| `TestSevenStepSaga` | ⭐⭐⭐⭐ | Basic 7-step saga workflow | Create saga template, submit saga, poll for completion, verify all steps |
| `TestTopicExchangeTopology` | ⭐⭐⭐ | RabbitMQ topic exchange topology verification | Verify topic exchange exists, executor inbox queues, coordinator results queues, correct bindings, no old fanout exchanges |
| `TestQueueCountReduction` | ⭐⭐⭐ | Queue count reduction verification | Verify ~10 queues (7 executor + 3 results) instead of ~42+ with old fanout architecture |
| `TestMessageDeliveryWithTopicExchange` | ⭐⭐⭐⭐ | Message delivery via topic exchange | Run 5 sagas, verify all complete, verify zero residual queue depth |
| `TestSagaCompensation_FailAtLastStep` | ⭐⭐⭐⭐ | Compensation: last step fails | 3-step saga, step3 fails → step1,2 compensated → COMPENSATED state. Verifies forward `Result` preserved, `CompensationResult` populated separately, 3-layer compensation input enrichment, and `CompensationReason` propagated from the failed step. |
| `TestSagaCompensation_FailAtFirstStep` | ⭐⭐⭐ | Compensation: first step fails | 3-step saga, step1 fails → nothing to compensate → COMPENSATED state |
| `TestSagaCompensation_Blocked` | ⭐⭐⭐⭐ | Compensation: blocked state | 3-step saga, step3 fails → step1 compensation fails → BLOCKED state |
| `TestDeepSubSaga_3Level_AllCommitted` | ⭐⭐⭐⭐⭐ | 3-level sub-saga hierarchy success | L1→L2→L3 all committed, verifies parent-child, saga_depth, root_saga_instance_id, tree |
| `TestDeepSubSaga_4Level_DeepFailureCompensation` | ⭐⭐⭐⭐⭐ | 4-level sub-saga cascading compensation | L1→L2→L3→L4, L4 step2 fails → cascading compensation through all levels |

---

## Group 1b: FundAccount Saga Tests (EthBC Required)

**Complexity**: ⭐⭐⭐⭐⭐ HIGHEST

**Makefile Target**: `make laser-e2e-ethbc-cat1`

**Files**:
- `tests/e2e/laser/fund_account_saga_test.go`

**Description**: Complete fund account saga workflows via TRAX. These tests verify the entire saga executes correctly with all services (accmgr, treassvc, traxcoord, etc.) running together.

**NOTE**: These tests require the full LASER E2E stack with EthBC mode (Anvil blockchain).

**Dependencies**: traxctrl, 3x traxcoord, accmgr, treassvc, lasersvc, Anvil blockchain

### Test Functions

| Test Function | Complexity | Description | Key Operations |
|--------------|------------|-------------|----------------|
| `TestFundAccountWithCashTokens_FullFlow_MintPath` | ⭐⭐⭐⭐⭐ | Complete fund account saga with minting | Verify inputs → Query vault balances → Mint tokens → Transfer, ERC20 minting, on-chain treasury verification |
| `TestFundAccountWithCashTokens_FullFlow_ExistingBalancePath` | ⭐⭐⭐⭐⭐ | Alternative path using existing balance | Tests conditional saga logic paths, same complexity as MintPath |
| `TestFundAccountWithCashTokens_MultipleFundings` | ⭐⭐⭐⭐⭐ | Sequential funding operations | Tests idempotency and state management across multiple sagas, cumulative balance tracking |
| `TestFundAccountWithCashTokens_SagaFailure_InsufficientBalance` | ⭐⭐⭐ | Error path: insufficient balance | Error handling, compensation logic, saga rollback mechanisms |
| `TestFundAccountWithCashTokens_SagaFailure_MissingDestinationAccount` | ⭐⭐⭐ | Error path: missing destination | Input validation, error response handling |
| `TestFundCsdAccounts_SingleAccount` | ⭐⭐⭐⭐⭐ | Batch fund single account via fund_csd_accounts saga | REST batch endpoint, sub-saga spawning, fund_account_with_cash_tokens |
| `TestFundCsdAccounts_MultipleAccounts` | ⭐⭐⭐⭐⭐ | Batch fund 3 accounts sequentially | Sequential sub-saga spawning, multi-account batch funding |
| `TestFundCsdAccounts_MismatchedLengths` | ⭐⭐ | Mismatched accounts/amounts arrays | REST validation, 400 error |
| `TestFundCsdAccounts_EmptyAccounts` | ⭐⭐ | Empty accounts array | REST validation, 400 error |
| `TestFundCsdAccounts_InvalidFundType` | ⭐⭐ | Invalid fund_type | REST validation, 400 error |
| `TestFundCsdAccounts_NegativeAmount` | ⭐⭐ | Negative amount | REST validation, 400 error |
| `TestFundCsdAccounts_MissingCurrencyCode` | ⭐⭐ | cash_token without currency_code | REST validation, 400 error |
| `TestFundCsdAccounts_NonExistentAccount` | ⭐⭐⭐ | Non-existent account causes saga compensation | Saga compensation, error propagation |

**Prerequisites**:
- Legal structure must exist
- Execution runtime configured
- Multiple mechanisms deployed (TREASURY, CASH_TOKEN, RAC)

---

## Group 2: Transfer & Authorization TRAX Tests

**Complexity**: ⭐⭐⭐⭐⭐ HIGHEST

**Files**:
- `tests/e2e/laser/transfer_trax_test.go`
- `tests/e2e/laser/authorization_trax_test.go`
- `tests/e2e/laser/distribution_trax_test.go`
- `tests/e2e/laser/validation_trax_test.go`

**Description**: High-complexity tests for instrument authorization, transfers, and distribution via TRAX saga orchestration. These involve multi-account operations, treasury tracking, and blockchain verification.

**Dependencies**: TRAX coordinators, LASER service, accmgr, instrmgr, blockchain

### Test Functions

| Test Function | Complexity | Description | Key Operations |
|--------------|------------|-------------|----------------|
| `TestTRAXSimpleTransferWithTreasuryTracking` | ⭐⭐⭐⭐⭐ | Complete transfer with treasury tracking | Authorize instrument, treasury tracking, multi-account transfers, on-chain balance verification |
| `TestTRAXSecurityHoldersConfirmation` | ⭐⭐⭐⭐⭐ | Security holder confirmation workflow | Multiple participants, complex saga coordination |
| `TestTRAXInstrumentMultiAccountTransfers` | ⭐⭐⭐⭐⭐ | Multi-account transfer operations | Transfers across multiple accounts, treasury balance tracking |
| `TestTRAXInstrumentTransferWithSaga` | ⭐⭐⭐⭐⭐ | Transfer via TRAX saga | Transfer execution via TRAX, compensation workflows, blockchain verification |
| `TestTRAXTransferCompensationParallel` | ⭐⭐⭐⭐⭐ | Parallel compensation scenarios | Concurrent saga handling, compensation logic |
| `TestTRAXTransferCompensationSequential` | ⭐⭐⭐⭐⭐ | Sequential compensation logic | Compensation for failed transfers, sequential execution verification |
| `TestTRAXTransferLinkManagement` | ⭐⭐⭐⭐ | Slot link lifecycle management | Slot link creation and management, link lifecycle verification |
| `TestTRAXTransferZeroBalanceLinkCleanup` | ⭐⭐⭐⭐ | Link cleanup on zero balance | State management, link cleanup when balance reaches zero |
| `TestBasicInstrumentAuthorizationViaTRAX` | ⭐⭐⭐⭐⭐ | Basic instrument authorization | Diamond deployment, ERC20 initialization |
| `TestTRAXAuthorizationWithHoldingsVerification` | ⭐⭐⭐⭐⭐ | Authorization with holder verification | Treasury holdings tracking, multiple service coordination |
| `TestTRAXInstrumentAuthorizationWithDistribution` | ⭐⭐⭐⭐⭐ | Authorization with distribution | Distribution mechanism, multi-holder scenarios |
| `TestTRAXInstrumentAuthorizationWithDistributionParametrized` | ⭐⭐⭐⭐⭐ | Parametrized distribution | Multiple distribution variants |
| `TestTRAXInstrumentEdgeCases` | ⭐⭐⭐ | Edge cases in instrument handling | Edge case validation |
| `TestTRAXInstrumentAuthorizationFailurePaths` | ⭐⭐⭐ | Error scenarios and recovery | Error handling, recovery paths |
| `TestAuthorizeSecurity_FullFlow` | ⭐⭐⭐⭐⭐ | PaCli 3-step authorization (asset+instrument+authorize) | Full security authorization via instrmgr APIs, treasury deposit verification |
| `TestAuthorizeSecurity_CustomDecimals` | ⭐⭐⭐⭐⭐ | Authorization with custom ERC20 decimals | ERC20 decimals=2, treasury deposit verification |
| `TestAuthorizeSecurity_InvalidLegalStructure` | ⭐⭐⭐ | Invalid legal structure rejection | Error handling, saga compensation |
| `TestAuthorizeSecurity_MissingRequiredFields` | ⭐⭐⭐ | Missing required fields rejection | HTTP 400 validation |

---

## Group 3: Individual Saga Step Tests (IndTrxSS)

**Complexity**: ⭐⭐⭐⭐ HIGH

**Files**:
- `tests/e2e/laser/indtrxss_test.go`
- `tests/e2e/laser/indtrxss_saga_treasurymechs_laser_expanded_test.go`
- `tests/e2e/laser/indtrxss_saga_fundaccount_accmgr_test.go`
- `tests/e2e/laser/indtrxss_saga_fundaccount_treassvc_test.go`
- `tests/e2e/laser/indtrxss_saga_treasurymechs_accmgr_test.go`
- `tests/e2e/laser/indtrxss_saga_treasurymechs_laser_test.go`
- `tests/e2e/laser/indtrxss_saga_treasurymechs_test.go`
- `tests/e2e/laser/indtrxss_saga_coremechs_test.go`
- `tests/e2e/laser/indtrxss_saga_coremechs_accmgr_test.go`
- `tests/e2e/laser/indtrxss_saga_coremechs_laser_test.go`
- `tests/e2e/laser/indtrxss_saga_establish_test.go`
- `tests/e2e/laser/individual_step_saga_setup_new_legal_participant_accmgr_s1_create_legal_participant_test.go`
- `tests/e2e/laser/individual_step_saga_setup_new_legal_participant_accmgr_s2_partners_test.go`
- `tests/e2e/laser/individual_step_saga_setup_new_legal_participant_accmgr_s7_apikey_test.go`

**Description**: Comprehensive testing of individual saga steps in isolation. Each step is tested with green path, error variants, compensation verification, and idempotency. Critical for ensuring saga reliability.

**Test Pattern**: Each test requires database setup, prerequisite data creation, IdempotentService instantiation, input building, execution, assertion, and idempotence verification.

### EstablishLegalStructure Saga Steps (S1-S8) - 20 tests

| Step | Test Function | Variants | Description |
|------|--------------|----------|-------------|
| S1 | `TestIndTrxSS_EstablishLegalStructure_S1_VerifyInputs_*` | Green, MissingTargetParticipant, MissingDisplayNames, InvalidType, EmptyPartnersList, MissingEnUSDisplayName, InvalidDisplayNamesJSON, CompensationVerified | Input validation step |
| S2 | `TestIndTrxSS_EstablishLegalStructure_S2_CreateLegalStructureRecord_*` | Green, CompensationVerified | Create legal structure in database |
| S3 | `TestIndTrxSS_EstablishLegalStructure_S3_CreateOwnerAccount_*` | Green, CompensationVerified | Create owner account |
| S4 | `TestIndTrxSS_EstablishLegalStructure_S4_CreateOwnerSlots_*` | Green, Cumulative, CompensationVerified | Create owner blockchain slots |
| S5 | `TestIndTrxSS_EstablishLegalStructure_S5_AttachOwnerEthAddress_*` | Green | Attach ETH address to owner |
| S6 | `TestIndTrxSS_EstablishLegalStructure_S6_CreatePartnerAccounts_*` | CompensationVerified | Create partner accounts |
| S7 | `TestIndTrxSS_EstablishLegalStructure_S7_CreatePartnerSlots_*` | Green | Create partner blockchain slots |
| S8 | `TestIndTrxSS_EstablishLegalStructure_S8_AttachPartnerEthAddresses_*` | Green, Cumulative | Attach ETH addresses to partners |

### DeployCoreLegalMechs Saga Steps (S1-S9) - 14 tests

| Step | Test Function | Variants | Description |
|------|--------------|----------|-------------|
| S1 | `TestIndTrxSS_DeployCoreLegalMechs_S1_VerifyLegalMechanismInputs_*` | Green | Validate mechanism inputs |
| S2 | `TestIndTrxSS_DeployCoreLegalMechs_S2_CreateTaskManagerMechanism_*` | Green, CompensationVerified | Create TaskManager mechanism record |
| S3 | `TestIndTrxSS_DeployCoreLegalMechs_S3_CreateAuthzSourceMechanism_*` | Green, CompensationVerified | Create AuthZ mechanism record |
| S4 | `TestIndTrxSS_DeployCoreLegalMechs_S4_DeployTaskManagerContract_*` | Green, MissingSlotAddress | Deploy TaskManager to blockchain |
| S5 | `TestIndTrxSS_DeployCoreLegalMechs_S5_CreateTaskManagerDeployment_*` | Green, CompensationVerified | Record deployment |
| S6 | `TestIndTrxSS_DeployCoreLegalMechs_S6_DeployAuthzDiamondContract_*` | Green | Deploy AuthZ Diamond |
| S8 | `TestIndTrxSS_DeployCoreLegalMechs_S8_InitializeAuthzDiamond_*` | Green, MissingAdmins | Initialize AuthZ Diamond |
| S9 | `TestIndTrxSS_DeployCoreLegalMechs_S9_AddAuthzFacetToDiamond_*` | Green, MissingFacetSlot | Add AuthZ facet |

### Treasury Mechanism Saga Steps (S4-S17) - 18 tests

| Step | Test Function | Description |
|------|--------------|-------------|
| S4 | `TestIndTrxSS_TreasuryMechs_S4_DeployRacDiamond_*` | Deploy RAC Diamond contract |
| S5 | `TestIndTrxSS_TreasuryMechs_S5_InitializeRacDiamond_*` | Initialize RAC Diamond |
| S6 | `TestIndTrxSS_TreasuryMechs_S6_GrantAddFacetsPermRac_*` | Grant facet permissions |
| S7 | `TestIndTrxSS_TreasuryMechs_S7_AddRacFacet_*` | Add RAC facet |
| S9 | `TestIndTrxSS_TreasuryMechs_S9_DeployTrezorDiamond_*` | Deploy Trezor Diamond |
| S10 | `TestIndTrxSS_TreasuryMechs_S10_InitializeTrezorDiamond_*` | Initialize Trezor |
| S11 | `TestIndTrxSS_TreasuryMechs_S11_GrantAddFacetsPermTrezor_*` | Grant Trezor permissions |
| S12 | `TestIndTrxSS_TreasuryMechs_S12_AddVaultFacets_*` | Add vault facets |
| S13 | `TestIndTrxSS_TreasuryMechs_S13_GrantCreateLedgerPerm_*` | Grant ledger permissions |
| S14 | `TestIndTrxSS_TreasuryMechs_S14_CreateDefaultLedger_*` | Create default ledger |
| S15 | `TestIndTrxSS_TreasuryMechs_S15_GrantSetAddressPerm_*` | Grant address permissions |
| S16 | `TestIndTrxSS_TreasuryMechs_S16_GrantSetIntPerm_*` | Grant int permissions |
| S17 | `TestIndTrxSS_TreasuryMechs_S17_ConfigureRacProperties_*` | Configure RAC properties |

### FundAccount Saga Steps - 17 tests

**AccMgr Steps**:

| Step | Test Function | Variants | Description |
|------|--------------|----------|-------------|
| S1 | `TestIndTrxSS_FundAccountAccMgr_S1_VerifyInputs_*` | Green, MissingStructure, MissingTreasury, MissingCashToken | Validate funding inputs |
| S7 | `TestIndTrxSS_FundAccountAccMgr_S7_CreateFundingRecord_*` | MintPath, TransferPath, Compensation | Create funding record |

**TreasSvc Steps**:

| Step | Test Function | Variants | Description |
|------|--------------|----------|-------------|
| S2 | `TestIndTrxSS_FundAccountTreasSvc_S2_QuerySourceVaultBalance_*` | Green, InsufficientBalance, MissingInputs | Query source vault |
| S3 | `TestIndTrxSS_FundAccountTreasSvc_S3_MintTokensIfNeeded_*` | MintPath, SkipPath, MissingInputs | Mint if needed |
| S4 | `TestIndTrxSS_FundAccountTreasSvc_S4_QueryDestinationVaultBalance_*` | Green, MissingInputs | Query destination |
| S5 | `TestIndTrxSS_FundAccountTreasSvc_S5_TransferFromClearingToDestination_*` | Green, MissingInputs | Execute transfer |
| S6 | `TestIndTrxSS_FundAccountTreasSvc_S6_VerifyPostTransferBalances_*` | Green, MissingInputs | Verify balances |

### SetupNewLegalParticipant Saga Steps - 23 tests

| Step | Test Function | Variants | Description |
|------|--------------|----------|-------------|
| S1 | `TestIndividualStep_SetupNewLegalParticipant_S1_CreateLegalParticipant_*` | Green, GeneratedIid, MissingDisplayNames, EmptyDisplayNames, MissingTypes, EmptyTypes, Idempotency, Compensation | Create legal participant |
| S2 | `TestIndividualStep_SetupNewLegalParticipant_S2_Partners_*` | AllNew, AllExisting, Mixed, EmptyList, DeployerNotInList, ExistingNotFound, Compensation, GeneratedIid | Setup partners |
| S7 | `TestIndividualStep_SetupNewLegalParticipant_S7_ApiKey_*` | Green, DefaultValues, MissingParticipant, Idempotency, KeyFormat | Create API key |

### Full Saga Integration Tests - 4 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestIndTrxSS_Saga_TreasuryMechs_FullFlow` | ⭐⭐⭐⭐⭐ | Complete treasury mechanisms saga |
| `TestIndTrxSS_Saga_CoreMechs_FullFlow` | ⭐⭐⭐⭐⭐ | Complete core mechanisms saga |
| `TestIndTrxSS_Saga_Establish_FullFlow` | ⭐⭐⭐⭐⭐ | Complete establish legal structure saga |
| `TestIndTrxSS_Saga_FundAccount_FullFlow` | ⭐⭐⭐⭐⭐ | Complete fund account saga |

---

## Group 4: Legal Mechanism Deployment Tests

**Complexity**: ⭐⭐⭐⭐ HIGH

**Files**:
- `tests/e2e/laser/legal_mechanism_deployment_test.go`
- `tests/e2e/laser/treasury_mechanism_deployment_test.go`
- `tests/e2e/laser/trading_mechanism_deployment_test.go`

**Description**: Tests for deploying core legal mechanisms (TaskManager, Authorization), treasury mechanisms (RAC, Trezor, Vaults), and trading engine mechanisms (Agora Engine Diamond) via TRAX sagas.

**Dependencies**: TRAX, LASER, accmgr, blockchain

### Core Legal Mechanisms - 14 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestDeployCoreLegalMechanisms_FullFlow` | ⭐⭐⭐⭐⭐ | Complete core mechanisms (TaskMgr + AuthZ) deployment |
| `TestDeployCoreLegalMechanisms_VerifyRoles` | ⭐⭐⭐ | Role assignment verification |
| `TestDeployCoreLegalMechanisms_WithBypassMode` | ⭐⭐⭐ | Bypass mode deployment |
| `TestDeployCoreLegalMechanisms_MissingExecRuntimeName` | ⭐⭐⭐ | Error: missing runtime name |
| `TestDeployCoreLegalMechanisms_MissingLegalStructureIid` | ⭐⭐⭐ | Error: missing structure IID |
| `TestDeployCoreLegalMechanisms_OverlappingAuthzAdmins` | ⭐⭐⭐ | Error: overlapping admins |
| `TestDeployCoreLegalMechanisms_EmptyTaskManagerAdmins` | ⭐⭐⭐ | Error: empty admins |
| `TestDeployCoreLegalMechanisms_MissingAuthzFacetVersion` | ⭐⭐⭐ | Error: missing facet version |
| `TestDeployCoreLegalMechanisms_MissingDeployerAccountIid` | ⭐⭐⭐ | Error: missing deployer account |
| `TestDeployCoreLegalMechanisms_MissingDeployerSlotAddress` | ⭐⭐⭐ | Error: missing deployer slot |
| `TestDeployCoreLegalMechanisms_DuplicateMechanisms` | ⭐⭐⭐ | Error: duplicate mechanisms |
| `TestDeployCoreLegalMechanisms_InvalidLegalStructure` | ⭐⭐⭐ | Error: invalid structure |
| `TestDeployCoreLegalMechanisms_DeployerNotSigner` | ⭐⭐⭐ | Error: deployer not authorized |
| `TestDeployCoreLegalMechanisms_PartnerAccountNotActive` | ⭐⭐⭐ | Error: inactive partner |

### Treasury Mechanisms - 9 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestDeployTreasuryLegalMechanisms_FullFlow` | ⭐⭐⭐⭐⭐ | Complete treasury deployment (RAC + Trezor + Vault + Ledger) |
| `TestDeployTreasuryLegalMechanisms_MissingExecRuntimeName` | ⭐⭐⭐ | Error: missing runtime |
| `TestDeployTreasuryLegalMechanisms_MissingLegalStructureIid` | ⭐⭐⭐ | Error: missing structure |
| `TestDeployTreasuryLegalMechanisms_MissingAdminPartnerSlotAddress` | ⭐⭐⭐ | Error: missing admin slot |
| `TestDeployTreasuryLegalMechanisms_MissingAuthzAdminSlotAddress` | ⭐⭐⭐ | Error: missing authz slot |
| `TestDeployTreasuryLegalMechanisms_MissingRacFacetVersion` | ⭐⭐⭐ | Error: missing facet version |
| `TestDeployTreasuryLegalMechanisms_MissingCoreMechanisms` | ⭐⭐⭐ | Error: missing prerequisites |
| `TestDeployTreasuryLegalMechanisms_DuplicateTreasury` | ⭐⭐⭐ | Error: duplicate treasury |
| `TestDeployTreasuryLegalMechanisms_InvalidLegalStructure` | ⭐⭐⭐ | Error: invalid structure |

### Trading Engine Mechanisms - 11 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestDeployTradingLegalMechanisms_FullFlow` | ⭐⭐⭐⭐⭐ | Complete trading engine deployment (Agora Engine Diamond + 10 facets + algo props) |
| `TestDeployTradingLegalMechanisms_VerifyDiamondFacets` | ⭐⭐⭐⭐ | Verify all 10 facets added, verify algo address props set correctly |
| `TestDeployTradingLegalMechanisms_ViaSetupNewLegalParticipant` | ⭐⭐⭐⭐ | Sub-saga spawner with force_creation_of_trading_mechanism=true |
| `TestDeployTradingLegalMechanisms_MissingCoreMechanisms` | ⭐⭐⭐ | Error: missing prerequisites |
| `TestDeployTradingLegalMechanisms_DuplicateTrading` | ⭐⭐⭐ | Error: duplicate trading engine |
| `TestDeployTradingLegalMechanisms_MissingExecRuntimeName` | ⭐⭐⭐ | Error: missing runtime |
| `TestDeployTradingLegalMechanisms_MissingLegalStructureIid` | ⭐⭐⭐ | Error: missing structure |
| `TestDeployTradingLegalMechanisms_MissingAdminPartnerSlotAddress` | ⭐⭐⭐ | Error: missing admin slot |
| `TestDeployTradingLegalMechanisms_InvalidLegalStructure` | ⭐⭐⭐ | Error: invalid structure |
| `TestDeployTradingLegalMechanisms_InvalidFacetVersion` | ⭐⭐⭐ | Error: invalid facet version |
| `TestDeployTradingLegalMechanisms_SkippedWhenFlagNotSet` | ⭐⭐⭐ | SNLP without trading flag -> skipped |

### Security Listing Deployment - 5 tests (implemented)

**File**: `tests/e2e/laser/security_listing_deployment_test.go`

**Makefile Category**: Cat 27 (`make laser-e2e-ethbc-cat27`)

**Description**: Tests for deploying security listings with on-chain trading pair creation via `createPairV2` on an Agora Engine diamond. Includes csdmsggw deployment config endpoint tests. See [Group 27](#group-27-security-listing-deployment-tests) for full details.

---

## Group 5: Diamond & Authorization Tests

**Complexity**: ⭐⭐⭐⭐ HIGH

**Files**:
- `tests/e2e/laser/authz_diamond_laser_test.go`
- `tests/e2e/laser/diamond_laser_test.go`
- `tests/e2e/laser/deploy_all_facets_test.go`
- `tests/e2e/laser/deploy_facet_test.go`

**Description**: Tests for Diamond pattern smart contract deployment, authorization diamond setup, and facet management via LASER framework.

**Dependencies**: LASER service, blockchain, Lattice contracts

### Authorization Diamond Tests - 5 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestAuthzDiamond_ComprehensiveFunctions` | ⭐⭐⭐⭐⭐ | Comprehensive authorization operations, role management, permission testing |
| `TestAuthzDiamond_DeployWithTaskManagerViaLASER` | ⭐⭐⭐⭐⭐ | Diamond with TaskManager integration, multi-facet deployment |
| `TestAuthzDiamond_DeployViaLASER` | ⭐⭐⭐ | Basic diamond deployment via LASER |
| `TestAuthzDiamond_DeploySimpleAuthzFacetViaLASER` | ⭐⭐⭐ | Simple authorization facet deployment |
| `TestAuthzDiamond_DeployAuthzFacetViaLASER` | ⭐⭐⭐ | Full authorization facet deployment |

### Generic Diamond Tests - 3 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestDiamond_ComprehensiveFunctions` | ⭐⭐⭐⭐⭐ | Full diamond pattern testing |
| `TestDiamond_DeployViaLASER` | ⭐⭐⭐ | Generic diamond deployment |
| `TestDiamond_InitializeWithAuthzSource` | ⭐⭐⭐ | Diamond initialization with AuthZ |

### Deploy All Facets Tests - 6 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestDeployAllLatticeFacets_FullFlow` | ⭐⭐⭐⭐⭐ | Deploy all available Lattice facets |
| `TestDeployLatticeFacets_CoreModule` | ⭐⭐⭐ | Core module facets |
| `TestDeployLatticeFacets_MinimalSet` | ⭐⭐ | Minimal facet set |
| `TestDeployLatticeFacets_VersionUpdate` | ⭐⭐⭐ | Version update testing |
| `TestDeployLatticeFacets_OlderVersionNoUpdate` | ⭐⭐⭐ | Skip older versions |
| `TestDeployLatticeFacets_SelectiveDeployment` | ⭐⭐⭐ | Selective deployment |

### Deploy Single Facet Tests - 3 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestDeployFacet_LocalExecution` | ⭐⭐⭐ | Local facet deployment |
| `TestDeployFacet_InvalidFacetName` | ⭐⭐ | Error: invalid facet name |
| `TestDeployFacet_RDBMSModeRejection` | ⭐⭐ | Error: RDBMS mode rejection |

---

## Group 6: ERC20 Token Operations Tests

**Complexity**: ⭐⭐⭐⭐ HIGH

**Files**:
- `tests/e2e/laser/executor_erc20_operations_test.go`
- `tests/e2e/laser/executor_erc20_approve_test.go`
- `tests/e2e/laser/executor_erc20_direct_test.go`
- `tests/e2e/laser/executor_erc20_errors_test.go`
- `tests/e2e/laser/executor_erc20_decimals_test.go`
- `tests/e2e/laser/executor_erc20_laser_test.go`
- `tests/e2e/laser/executor_erc20_advanced_test.go`
- `tests/e2e/laser/executor_erc20_queries_test.go`

**Description**: Comprehensive ERC20 token operation tests including deploy, transfer, mint, burn, approve, and various edge cases.

**Dependencies**: LASER service, LASER executors, blockchain, ERC20 contracts

### Comprehensive Workflow - 1 test

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestERC20ComprehensiveWorkflow` | ⭐⭐⭐⭐⭐ | Deploy ERC20 with 8 decimals, verify slot links, transfer/mint/burn/approve, mix of async/sync queries |

### Advanced Tests - 2 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestERC20ConcurrentTransfers` | ⭐⭐⭐⭐⭐ | Concurrent multi-account ERC20 transfers in parallel |
| `TestERC20SlotLinkVerification` | ⭐⭐⭐ | Slot link tracking for ERC20 operations |

### Approval Tests - 2 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestERC20ApproveAndTransferFrom` | ⭐⭐⭐ | Approval workflow with TransferFrom |
| `TestERC20TransferFromExceedingAllowance` | ⭐⭐⭐ | Error: exceeding approved amount |

### Direct Operations - 1 test

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestExecutorERC20Direct` | ⭐⭐⭐ | Direct ERC20 operations via executor |

### Error Handling - 4 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestERC20TransferInsufficientBalance` | ⭐⭐⭐ | Error: insufficient balance for transfer |
| `TestERC20MintUnauthorized` | ⭐⭐⭐ | Error: unauthorized mint attempt |
| `TestERC20BurnInsufficientBalance` | ⭐⭐⭐ | Error: insufficient balance for burn |
| `TestERC20BurnFromNonBurnableContract` | ⭐⭐⭐ | Error: non-burnable contract |

### Decimals Tests - 3 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestERC20MultipleDecimalsWorkflow` | ⭐⭐⭐ | Variable decimals testing |
| `TestERC20ZeroDecimalsEdgeCases` | ⭐⭐⭐ | Edge cases with 0 decimals |
| `TestERC20MaxDecimalsLargeAmounts` | ⭐⭐⭐ | Large amounts with max decimals |

### Via LcMgr Tests - 2 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestExecutorERC20ViaLcmgr` | ⭐⭐⭐ | ERC20 operations via LegalCallsManager |
| `TestExecutorERC20MintAndTransferViaLcmgr` | ⭐⭐⭐ | Combined mint + transfer via LcMgr |

### Query Tests - 2 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestERC20AllOperationsSyncAsync` | ⭐⭐⭐ | Mix of sync/async query operations |
| `TestERC20QueryOnNonExistentContract` | ⭐⭐ | Error: query non-existent contract |

---

## Group 7: Cash Token Deployment Tests

**Complexity**: ⭐⭐⭐⭐ HIGH

**Files**:
- `tests/e2e/laser/cash_token_deployment_test.go`

**Description**: Tests for deploying currency-backed cash tokens with treasury integration and ERC20 initialization.

**Dependencies**: TRAX, LASER, treasury service, blockchain

### Test Functions - 14 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestDeployCashToken_FullFlow` | ⭐⭐⭐⭐⭐ | Complete cash token deployment with treasury integration |
| `TestDeployCashToken_WithInitialSupply` | ⭐⭐⭐⭐⭐ | Deployment with initial supply |
| `TestDeployCashToken_AmendVaultLinkMetadata` | ⭐⭐⭐⭐ | Verify crown/links/query returns vault links and GET+PUT amends metadata with authorized_instrument_iid |
| `TestDeployCashToken_AmendVaultLinkMetadata_Idempotent` | ⭐⭐⭐⭐ | Verify amendment is idempotent (second pass is a no-op) |
| `TestDeployCashToken_AmendVaultLinkMetadata_NoLinks` | ⭐⭐⭐ | Verify graceful behavior when no vault links exist (no initial supply) |
| `TestDeployCashToken_CustomDecimals` | ⭐⭐⭐ | Custom decimal configuration |
| `TestDeployCashToken_MissingDecimals` | ⭐⭐⭐ | Error: missing decimals |
| `TestDeployCashToken_InvalidDecimals` | ⭐⭐⭐ | Error: invalid decimals |
| `TestDeployCashToken_MissingCurrencyCode` | ⭐⭐⭐ | Error: missing currency code |
| `TestDeployCashToken_InvalidCurrencyCodeFormat` | ⭐⭐⭐ | Error: invalid currency format |
| `TestDeployCashToken_MissingLegalStructure` | ⭐⭐⭐ | Error: missing legal structure |
| `TestDeployCashToken_NoTreasuryMechanism` | ⭐⭐⭐ | Error: no treasury deployed |
| `TestDeployCashToken_DuplicateCurrency` | ⭐⭐⭐ | Error: duplicate currency |
| `TestDeployCashToken_DeployerNotSigner` | ⭐⭐⭐ | Error: unauthorized deployer |

---

## Group 8: Participant CLI (PaCli) Tests

**Complexity**: ⭐⭐⭐⭐ HIGH to ⭐⭐ MEDIUM

**Files**:
- `tests/e2e/laser/pacli_test.go`

**Description**: Comprehensive testing of the Participant Agent CLI tool covering queries, mutations, saga operations, and full workflows.

**Dependencies**: prtagent service (gRPC), accmgr, TRAX

### Full Workflow Tests (HIGH complexity) - 5 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestPaCli_FullWorkflow_WithDatabaseIsolation_AndSaga` | ⭐⭐⭐⭐⭐ | Complete workflow: participant → account → investor with sagas |
| `TestPaCli_FullParticipantWorkflow` | ⭐⭐⭐⭐⭐ | Full participant lifecycle testing |
| `TestPaCli_SetupLegalParticipant_MinimalRequest` | ⭐⭐⭐⭐ | Legal participant setup via CLI with saga verification |
| `TestPaCli_SetupLegalParticipant_WithCurrencies` | ⭐⭐⭐⭐ | Legal participant with currency support |
| `TestPaCli_CreateInvestor_WithSagaVerification` | ⭐⭐⭐⭐ | Investor creation with saga tracking |

### Create/Mutation Tests (MEDIUM complexity) - 8 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestPaCli_CreateParticipant_WithPersistence` | ⭐⭐⭐ | Create participant with persistence |
| `TestPaCli_CreateAccount_WithPersistence` | ⭐⭐⭐ | Create account with persistence |
| `TestPaCli_CreateP2ARelation_WithPersistence` | ⭐⭐⭐ | Create P2A relation |
| `TestPaCli_CreateParticipant_WithDatabaseIsolation` | ⭐⭐⭐ | Isolated participant creation |
| `TestPaCli_CreateAccount_WithDatabaseIsolation` | ⭐⭐⭐ | Isolated account creation |
| `TestPaCli_CreateP2ARelation_WithDatabaseIsolation` | ⭐⭐⭐ | Isolated relation creation |
| `TestPaCli_SetupLegalParticipant_InvalidRequest` | ⭐⭐⭐ | Error path testing |
| `TestPaCli_SagaStatus_NotFound` | ⭐⭐⭐ | Saga status error handling |

### Query Tests (LOW complexity) - 39 tests

| Test Function Category | Count | Description |
|-----------------------|-------|-------------|
| `TestPaCli_ParticipantsList*` | 3 | List participants with pagination |
| `TestPaCli_AccountsList*` | 2 | List accounts with filters |
| `TestPaCli_SecuritiesList` | 1 | List securities |
| `TestPaCli_CashTokensList` | 1 | List cash tokens |
| `TestPaCli_InvestorsList` | 1 | List investors |
| `TestPaCli_*Get` | 5 | Get individual resources |
| `TestPaCli_*Get_NotFound` | 3 | Not found error paths |
| `TestPaCli_Relations*` | 4 | Relationship queries |
| `TestPaCli_LegalStructures*` | 3 | Legal structure queries |
| `TestPaCli_Ping` | 1 | Connectivity test |
| `TestPaCli_Help` | 1 | Help command |
| `TestPaCli_Connection_NoServer` | 1 | Connection error handling |
| `TestPaCli_UnknownCommand` | 1 | Unknown command error |
| `TestPaCli_InvalidSubcommand` | 1 | Invalid subcommand error |
| `TestPaCli_MissingRequiredArg` | 1 | Missing argument error |
| `TestPaCli_PaginationAllResources` | 1 | Pagination across all resources |

### Deploy Listing Tests (MEDIUM complexity) - 4 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestPaCli_DeployListing_MissingArgs` | ⭐⭐ | Verifies usage instructions when no TTY and no args |
| `TestPaCli_DeployListing_MissingSecurityArg` | ⭐⭐ | Error when only currency is provided |
| `TestPaCli_DeployListing_MissingCurrencyArg` | ⭐⭐ | Error when only security is provided |
| `TestPaCli_DeployListing_NoPrincipalLegalStructure` | ⭐⭐⭐ | Error when no PLS is configured |

---

## Group 9: Legal Participant & Structure Tests

**Complexity**: ⭐⭐⭐⭐ HIGH to ⭐⭐⭐ MEDIUM

**Files**:
- `tests/e2e/laser/setup_new_legal_participant_test.go`
- `tests/e2e/laser/setup_new_custodian_participant_test.go`
- `tests/e2e/laser/legal_structure_trax_test.go`
- `tests/e2e/laser/new_investor_under_participant_trax_test.go`
- `tests/e2e/laser/onboard_new_investor_trax_test.go`
- `tests/e2e/laser/legal_participant_apikey_auth_test.go`
- `tests/e2e/laser/configmgr_pls_test.go`

**Description**: Tests for setting up legal participants (including custodian participants), establishing legal structures (partnerships), creating investors, API key authentication, and Principal Legal Structure (PLS) configuration.

### Setup New Legal Participant - 19 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestSetupNewLegalParticipant_FullFlow` | ⭐⭐⭐⭐⭐ | Complete participant setup flow. Partner-2 declares `account_type=OMNIBUS` + `relations=[CEO, COMPLIANCE_OFFICER]`, exercising the new partner.AccountType passthrough into `create_partner_accounts` and the new step-12 `create_participant_to_legal_structure_relations` row writer. |
| `TestSetupNewLegalParticipant_WithTreasuryName` | ⭐⭐⭐⭐⭐ | Two-phase: deploy treasury, then reuse in new saga |
| `TestSetupNewLegalParticipant_Rule4_ForceCreateTreasury` | ⭐⭐⭐⭐ | Force treasury deployment with no currencies |
| `TestSetupNewLegalParticipant_Steps1And2Only` | ⭐⭐⭐ | Partial flow (steps 1 and 2) |
| `TestSetupNewLegalParticipant_EmptyCurrencies` | ⭐⭐⭐ | Empty currencies variant (no treasury, no cash tokens) |
| `TestSetupNewLegalParticipant_AllExistingPartners` | ⭐⭐⭐ | All partners already exist |
| `TestSetupNewLegalParticipant_GeneratedIids` | ⭐⭐⭐ | Generated IIDs |
| `TestSetupNewLegalParticipant_MissingDisplayNames` | ⭐⭐⭐ | Error: missing display names |
| `TestSetupNewLegalParticipant_NoPartners` | ⭐⭐⭐ | No partners variant |
| `TestSetupNewLegalParticipant_DeployerNotPartner` | ⭐⭐⭐ | Deployer not in partner list |
| `TestSetupNewLegalParticipant_NonExistentPartner` | ⭐⭐⭐ | Error: non-existent partner |
| `TestSetupNewLegalParticipant_DuplicateLegalParticipantIid` | ⭐⭐⭐ | Error: duplicate IID |
| `TestSetupNewLegalParticipant_Rule1_InitialAmountsMismatch` | ⭐⭐ | Rule 1: initial_amounts has key not in currencies |
| `TestSetupNewLegalParticipant_Rule1_DecimalsMismatch` | ⭐⭐ | Rule 1: decimals has key not in currencies |
| `TestSetupNewLegalParticipant_Rule1_AmountsWithoutCurrencies` | ⭐⭐ | Rule 1: initial_amounts non-empty but currencies empty |
| `TestSetupNewLegalParticipant_Rule1_DecimalsWithoutCurrencies` | ⭐⭐ | Rule 1: decimals non-empty but currencies empty |
| `TestSetupNewLegalParticipant_Rule1_MissingAmountForCurrency` | ⭐⭐ | Rule 1: currency missing from initial_amounts |
| `TestSetupNewLegalParticipant_Rule1_MissingDecimalsForCurrency` | ⭐⭐ | Rule 1: currency missing from decimals |

### Legal Structure (Partnership) - 9 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestEstablishPartnershipWithTwoPartners` | ⭐⭐⭐ | Partnership with 2 partners |
| `TestEstablishPartnershipWithOptionalParent` | ⭐⭐⭐ | Partnership with optional parent |
| `TestEstablishPartnershipSinglePartner` | ⭐⭐⭐ | Single partner partnership |
| `TestEstablishPartnership_MissingOwnerParticipant` | ⭐⭐⭐ | Error: missing owner |
| `TestEstablishPartnership_MissingDisplayNames` | ⭐⭐⭐ | Error: missing display names |
| `TestEstablishPartnership_MissingEnUSDisplayName` | ⭐⭐⭐ | Error: missing en-US name |
| `TestEstablishPartnership_InvalidType` | ⭐⭐⭐ | Error: invalid type |
| `TestEstablishPartnership_NonExistentPartner` | ⭐⭐⭐ | Error: non-existent partner |
| `TestEstablishPartnership_EmptyPartnersList` | ⭐⭐⭐ | Error: empty partners |

### New Investor Under Participant - 7 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestNewInvestorUnderParticipant_BasicSuccess` | ⭐⭐⭐ | Basic investor creation |
| `TestNewInvestorUnderParticipant_WithMetadata` | ⭐⭐⭐ | Investor with metadata |
| `TestNewInvestorUnderParticipant_MultipleInvestors` | ⭐⭐⭐ | Multiple investors |
| `TestNewInvestorUnderParticipant_NonExistentParticipant` | ⭐⭐⭐ | Error: non-existent participant |
| `TestNewInvestorUnderParticipant_MissingExternalId` | ⭐⭐⭐ | Error: missing external ID |
| `TestNewInvestorUnderParticipant_DuplicateExternalId` | ⭐⭐⭐ | Error: duplicate external ID |
| `TestNewInvestorUnderParticipant_SameExternalIdDifferentParticipant` | ⭐⭐⭐ | Same ID, different participant |

### Onboard New Investor (Wrapper Saga) - 7 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestOnboardNewInvestor_BasicSuccess` | ⭐⭐⭐⭐ | Full onboarding: create + register at depositories + CSD metadata verification |
| `TestOnboardNewInvestor_WithMetadata` | ⭐⭐⭐ | Metadata passes through to sub-saga; CSD metadata merged alongside user metadata |
| `TestOnboardNewInvestor_MultipleInvestors` | ⭐⭐⭐ | Multiple investors under same participant; both get CSD metadata |
| `TestOnboardNewInvestor_CsdAccountMetadataStored` | ⭐⭐⭐⭐ | Dedicated CSD metadata test: validates JSON structure and IID completeness |
| `TestOnboardNewInvestor_NonExistentParticipant` | ⭐⭐⭐ | Error: step 1 sub-saga compensates |
| `TestOnboardNewInvestor_DuplicateExternalId` | ⭐⭐⭐ | Error: duplicate external ID |
| `TestOnboardNewInvestor_MissingExternalId` | ⭐⭐⭐ | Error: missing external ID |

### CSD Security Holdings - 2 tests (SKELETON — requires gRPC test helper)

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestCsdSecurityHoldings_InvestorWithCsdAccount` | ⭐⭐⭐⭐ | Full flow: onboard → fund CSD → query holdings via prtagent gRPC |
| `TestCsdSecurityHoldings_FallbackToLocalTreassvc` | ⭐⭐⭐ | No CSD metadata → falls back to local treassvc |

### API Key Authentication - 9 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestLegalParticipantApiKey_RESTAuthentication` | ⭐⭐⭐ | REST authentication with API key |
| `TestLegalParticipantApiKey_InvalidKey` | ⭐⭐⭐ | Error: invalid key |
| `TestLegalParticipantApiKey_MissingKey` | ⭐⭐⭐ | Error: missing key |
| `TestLegalParticipantApiKey_DisabledKey` | ⭐⭐⭐ | Error: disabled key |
| `TestLegalParticipantApiKey_RateLimiting` | ⭐⭐⭐ | Rate limiting behavior |
| `TestLegalParticipantApiKey_KeyFormat` | ⭐⭐⭐ | Key format validation |
| `TestLegalParticipantApiKey_HashFormat` | ⭐⭐⭐ | Hash format validation |
| `TestParticipantAPIKey_IsValid` | ⭐⭐⭐ | Validity check |
| `TestParticipantAPIKey_IsOperationAllowed` | ⭐⭐⭐ | Operation permission check |

### Principal Legal Structure (PLS) - 5 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestConfigMgr_PLS_AccmgrEndpoint_NotSet` | ⭐⭐ | accmgr PLS endpoint returns 404 when not configured |
| `TestConfigMgr_PLS_AccmgrEndpoint_Set` | ⭐⭐ | accmgr PLS endpoint returns 200 with manually set PLS |
| `TestConfigMgr_PLS_SetViaSaga` | ⭐⭐⭐⭐ | Setup LP with is_principal=true, verify PLS in configmgr and accmgr |
| `TestConfigMgr_PLS_DuplicateFails` | ⭐⭐⭐⭐ | Second LP with is_principal=true rejected with 409 |
| `TestConfigMgr_PLS_WithoutFlag` | ⭐⭐⭐⭐ | Setup LP without is_principal, verify PLS not set |

### Setup New Custodian Participant - 5 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestSetupNewCustodianParticipant_FullFlow` | ⭐⭐⭐⭐ | Full custodian saga: sub-saga + PLS link. Verifies CUSTODIAN type, client_auth_key, custody account from sub-saga chain. **EthBC** |
| `TestSetupNewCustodianParticipant_WithExistingPartner` | ⭐⭐⭐⭐ | Custodian saga with pre-existing partner (create_new=false). **EthBC** |
| `TestSetupNewCustodianParticipant_MissingDisplayNames` | ⭐⭐ | Error: empty display names returns HTTP 400 |
| `TestSetupNewCustodianParticipant_NoPartners` | ⭐⭐ | Error: empty partners list returns HTTP 400 |
| `TestSetupNewCustodianParticipant_DeployerNotPartner` | ⭐⭐ | Error: deployer_partner_iid not in partners returns HTTP 400 |

### Setup New Issuer Participant - 5 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestSetupNewIssuerParticipant_FullFlow` | ⭐⭐⭐⭐ | Full issuer saga: spawns setup_new_legal_participant sub-saga with type=ISSUER. Verifies ISSUER type, API key, legal structure, custody account. **EthBC** |
| `TestSetupNewIssuerParticipant_WithExistingPartner` | ⭐⭐⭐⭐ | Issuer saga with pre-existing partner (create_new=false). **EthBC** |
| `TestSetupNewIssuerParticipant_MissingDisplayNames` | ⭐⭐ | Error: empty display names returns HTTP 400 |
| `TestSetupNewIssuerParticipant_NoPartners` | ⭐⭐ | Error: empty partners list returns HTTP 400 |
| `TestSetupNewIssuerParticipant_DeployerNotPartner` | ⭐⭐ | Error: deployer_partner_iid not in partners returns HTTP 400 |

---

## Group 10: Task Manager & Multi-Signer Tests

**Complexity**: ⭐⭐⭐⭐ HIGH to ⭐⭐⭐ MEDIUM

**Files**:
- `tests/e2e/laser/taskmanagerv2_laser_test.go`
- `tests/e2e/laser/taskmanagerv2_lcmgr_test.go`
- `tests/e2e/laser/taskmanagerv2_multisigner_test.go`

**Description**: Tests for TaskManager V2 deployment and operations, including multi-signer approval workflows.

### Multi-Signer Tests - 4 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestTaskManagerV2TaskApprovalWorkflow` | ⭐⭐⭐⭐⭐ | Full approval workflow with multiple signers |
| `TestTaskManagerV2MultiExecutorDeployment` | ⭐⭐⭐⭐⭐ | Distributed deployment across executors |
| `TestTaskManagerV2ThreeAdminDeploy` | ⭐⭐⭐ | 3-admin deployment |
| `TestTaskManagerV2MultiSignerSetup` | ⭐⭐⭐ | Multi-signer setup |

### LASER Tests - 4 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestTaskManagerV2LaserMultiRole` | ⭐⭐⭐⭐ | Role-based task management |
| `TestTaskManagerV2LaserSlotSetup` | ⭐⭐⭐ | Slot setup for TaskManager |
| `TestTaskManagerV2LaserDeployAndQuery` | ⭐⭐⭐ | Deploy and query operations |
| `TestTaskManagerV2LaserCreateTask` | ⭐⭐⭐ | Task creation via LASER |

### LcMgr Tests - 3 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestTaskManagerV2LcmgrDeploy` | ⭐⭐⭐ | Deploy via LegalCallsManager |
| `TestTaskManagerV2LcmgrRoleQueries` | ⭐⭐⭐ | Role queries via LcMgr |
| `TestTaskManagerV2LcmgrCreateTask` | ⭐⭐⭐ | Task creation via LcMgr |

---

## Group 11: Deposit & Treasury Tests

**Complexity**: ⭐⭐⭐⭐ HIGH to ⭐⭐⭐ MEDIUM

**Makefile Target**: `make laser-e2e-ethbc-cat11`

**Files**:
- `tests/e2e/laser/deposit_to_treasury_test.go`
- `tests/e2e/laser/chain_verification_fundaccount_test.go`
- `tests/e2e/laser/treasury_vault_withdraw_test.go`

**Description**: Tests for treasury vault operations including deposit, withdrawal, and on-chain verification. Treasury vaults are the core mechanism for holding ERC20 tokens in the Legal Structure architecture. After instrument authorization, tokens are deposited to treasury vaults. These tests verify the complete lifecycle: deposit → query balance → withdraw.

### Chain Verification Fund Account Tests - 10 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestFundAccountWithCashTokens_OnChainVerification_MintPath` | ⭐⭐⭐⭐⭐ | Fund with on-chain vault balance verification (mint path) |
| `TestFundAccountWithCashTokens_OnChainVerification_TransferPath` | ⭐⭐⭐⭐⭐ | Transfer path with verification |
| `TestFundAccountWithCashTokens_OnChainVerification_BalanceToZero` | ⭐⭐⭐⭐⭐ | Edge case: balance to zero |
| `TestChainVerifier_QueryVaultBalance_Integration` | ⭐⭐⭐ | Vault balance query integration |
| `TestChainVerifier_QueryERC20Balance_Integration` | ⭐⭐⭐ | ERC20 balance query integration |
| `TestChainVerifier_PadAddress` | ⭐⭐ | Utility: pad address |
| `TestChainVerifier_PadUint256` | ⭐⭐ | Utility: pad uint256 |
| `TestChainVerifier_HexToDecimalString` | ⭐⭐ | Utility: hex to decimal |
| `TestChainVerifier_AddDecimalStrings` | ⭐⭐ | Utility: add decimals |
| `TestChainVerifier_SubtractDecimalStrings` | ⭐⭐ | Utility: subtract decimals |

### Deposit to Treasury Tests - 7 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestDepositToTreasury_FullFlowWithTreasury` | ⭐⭐⭐⭐ | Complete deposit flow with 4-level balance verification: LASER (direct ERC20, treasury ERC20, vault LIQUID, vault TOTAL) + TREASSVC (direct/treasury holders & holdings via `VerifyCurrentState`) + sole holder/holding assertion |
| `TestDepositToTreasury_BackwardCompatibility` | ⭐⭐⭐ | Legacy deposit format support |
| `TestDepositToTreasury_OnlyLegalStructureIid` | ⭐⭐⭐ | Deposit with only structure IID |
| `TestDepositToTreasury_OnlyExecRuntimeName` | ⭐⭐⭐ | Deposit with only runtime |
| `TestDepositToTreasury_APIRejectWhenMissingCoreMechanismRoles` | ⭐⭐⭐ | API 400: no core mechanism roles |
| `TestDepositToTreasury_APIRejectWhenMissingTreasuryMechanisms` | ⭐⭐⭐ | API 400: no treasury mechanisms |
| `TestDepositToTreasury_APIRejectWhenMissingExecRuntime` | ⭐⭐⭐ | API 400: invalid runtime |

### Treasury Vault Withdraw Tests - 7 tests

These tests verify `withdrawFromErc20VaultTo` functionality on the Trezor (Treasury) contract. After instrument authorization with treasury deposit enabled, tokens are held in the vault. These tests verify correct withdrawal to ERC20 balances.

**Key constraint**: Only the vault owner (msg.sender) can withdraw from their vault.

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestTreasuryVaultWithdraw_FullBalance` | ⭐⭐⭐⭐ | Withdraw entire vault balance to self; verify vault→0, ERC20→full |
| `TestTreasuryVaultWithdraw_PartialBalance` | ⭐⭐⭐⭐ | Withdraw subset; verify correct balance changes |
| `TestTreasuryVaultWithdraw_ToDifferentAccount` | ⭐⭐⭐⭐ | Withdraw to different account; verify recipient receives tokens |
| `TestTreasuryVaultWithdraw_Sequential` | ⭐⭐⭐⭐ | Multiple sequential withdrawals with cumulative verification |
| `TestTreasuryVaultWithdraw_InsufficientBalance` | ⭐⭐⭐ | Red path: attempt to withdraw more than vault balance |
| `TestTreasuryVaultWithdraw_NonOwner` | ⭐⭐⭐ | Red path: non-owner attempts withdrawal (should fail) |
| `TestTreasuryVaultWithdraw_AfterPartialWithdrawal` | ⭐⭐⭐ | Verify withdrawal limits after partial withdrawal |
| `TestTreasuryStashOps_TransferVaultBalance_IntraVault` | ⭐⭐⭐⭐ | Stash-aware intra-vault transfer (stash0 → custom); verify liquid↓, total unchanged, custom stash = amount |
| `TestTreasuryStashOps_TransferVaultBalance_RoundTrip` | ⭐⭐⭐⭐ | Round-trip stash0 → custom → stash0; verify full balance restoration |
| `TestTreasuryStashOps_TracedErc20s` | ⭐⭐⭐ | Query traced ERC20 tokens for vault; verify deposited token appears |
| `TestTreasuryStashOps_TracedStashes` | ⭐⭐⭐ | Query traced stashes after custom stash transfer; verify 0, 1, and custom stash present |
| `TestTreasuryStashOps_SetAndGetStashLabel` | ⭐⭐⭐ | Set and retrieve stash label metadata; verify label_abi round-trips correctly |

---

## Group 12: Signer & Key Management Tests

**Complexity**: ⭐⭐⭐ MEDIUM

**Files**:
- `tests/e2e/laser/signersvc_direct_test.go`
- `tests/e2e/laser/signersvc_laser_test.go`
- `tests/e2e/laser/signersvc_lcmgr_test.go`
- `tests/e2e/laser/signer_tag_test.go`

**Description**: Tests for signer service operations including seed-based slot creation, multi-signer coordination, and various derivation algorithms.

### Direct Signer Tests - 3 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestSignerSvcDirectThreeSignersExchangeSign` | ⭐⭐⭐ | Multi-signer coordination and sign exchange |
| `TestSignerSvcDirectRegisterAndGetAddress` | ⭐⭐⭐ | Register signer with seed and retrieve address |
| `TestSignerSvcDirectStatus` | ⭐⭐ | Signer service status check |

### LASER Signer Tests - 5 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestSignerSvcLaserThreeSignersExchangeSign` | ⭐⭐⭐ | Multi-signer LASER operations |
| `TestSignerSvcLaserMixedAlgorithms` | ⭐⭐⭐ | Multiple address derivation algorithms |
| `TestSignerSvcLaserSlotLinks` | ⭐⭐⭐ | Slot link management for signers |
| `TestSignerSvcLaserSeededSlotCreation` | ⭐⭐⭐ | Create seeded slots |
| `TestSignerSvcLaserServiceWideSlotCreation` | ⭐⭐⭐ | Service-wide slot creation |

### LcMgr Signer Tests - 3 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestSignerSvcLcmgrVerifyOnChainBalances` | ⭐⭐⭐ | Verify on-chain balances |
| `TestSignerSvcLcmgrERC20Deploy` | ⭐⭐⭐ | ERC20 deployment via LcMgr |
| `TestSignerSvcLcmgrERC20Transfer` | ⭐⭐⭐ | ERC20 transfer via LcMgr |

### Signer Tag Tests - 3 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestSignerTag_CreateSeededSlot_WithSignerTag` | ⭐⭐⭐ | Seeded slot with signer tag |
| `TestSignerTag_CreateSeededSlot_WithoutSignerTag` | ⭐⭐⭐ | Seeded slot without tag |
| `TestSignerTag_Helper_CreateSeededSlotWithSignerTag` | ⭐⭐ | Helper function test |

---

## Group 13: Slot & Seeding Tests

**Complexity**: ⭐⭐⭐ MEDIUM

**Files**:
- `tests/e2e/laser/service_seeded_slots_test.go`
- `tests/e2e/laser/executor_seeded_slots_test.go`

**Description**: Tests for slot creation with various address derivation algorithms (ID, SHA256_20, RND_20, RND_64) and service-wide slot management.

### Service-Wide Seeded Slots - 6 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestServiceWideCreateSeededSlots_AllCreated` | ⭐⭐⭐ | Create slots across all executors |
| `TestServiceWideCreateSeededSlots_AllExisting` | ⭐⭐⭐ | Idempotency: all slots exist |
| `TestServiceWideCreateSeededSlots_MixedResults` | ⭐⭐⭐ | Some created, some existing |
| `TestServiceWideCreateSeededSlots_Summary` | ⭐⭐⭐ | Summary report verification |
| `TestServiceWideCreateSeededSlots_DisabledExecutor` | ⭐⭐⭐ | Handle disabled executors |
| `TestServiceWideCreateSeededSlots_VerifySlotLinksCreation` | ⭐⭐⭐ | Link creation verification |

### Executor Seeded Slots - 13 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestExecutorCreateSeededSlot_ID_WithSeed_Created` | ⭐⭐⭐ | ID algorithm with seed (deterministic) |
| `TestExecutorCreateSeededSlot_ID_EmptySeed_Ignored` | ⭐⭐⭐ | ID algorithm ignores empty seed |
| `TestExecutorCreateSeededSlot_SHA256_20_Deterministic` | ⭐⭐⭐ | SHA256 with 20-byte output |
| `TestExecutorCreateSeededSlot_RND_20_WithSeed_Deterministic` | ⭐⭐⭐ | Random with seed (deterministic) |
| `TestExecutorCreateSeededSlot_RND_20_EmptySeed_Created` | ⭐⭐⭐ | Random with empty seed creates new |
| `TestExecutorCreateSeededSlot_RND_64_Deterministic` | ⭐⭐⭐ | Random 64-byte output |
| `TestExecutorDeriveSlotAddr_WithSeed` | ⭐⭐ | Utility: derive with seed |
| `TestExecutorDeriveSlotAddr_WithoutSeed_RND` | ⭐⭐ | Utility: derive without seed |
| `TestExecutorDeriveSlotAddr_AllAlgorithms` | ⭐⭐ | Utility: all algorithms |
| `TestSeededSlot_RefSeed_Immutable` | ⭐⭐⭐ | Ref seed immutability |
| `TestSeededSlot_Metadata_Immutable` | ⭐⭐⭐ | Metadata immutability |
| `TestSeededSlot_Addresses_Populated` | ⭐⭐⭐ | Address population verification |

---

## Group 14: External Call & Relay Tests

**Complexity**: ⭐⭐⭐ MEDIUM

**Files**:
- `tests/e2e/laser/executor_external_call_test.go`
- `tests/e2e/laser/executor_external_call_async_test.go`
- `tests/e2e/laser/executor_relay_finalizer_test.go`

**Description**: Tests for cross-executor communication, external calls, relay operations, and finalizer execution.

### External Call Tests - 3 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestExternalCallDeployContract` | ⭐⭐⭐ | External call to deploy contract |
| `TestExternalCallAsyncDeployContract` | ⭐⭐⭐ | Async external call with deployment |
| `TestExternalCallAsyncQueryWithFuture` | ⭐⭐⭐ | Async external call with future result |

### Relay Finalizer Tests - 2 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestRelayWithSuccessfulFinalizer` | ⭐⭐⭐ | Relay followed by successful finalizer |
| `TestRelayWithFailedFinalizer` | ⭐⭐⭐ | Relay with finalizer error handling |

---

## Group 15: Deploy Facets TRAX Tests

**Complexity**: ⭐⭐⭐ MEDIUM

**Files**:
- `tests/e2e/laser/deploy_facets_trax_test.go`

**Description**: Tests for deploying Lattice facets via TRAX saga orchestration.

### Test Functions - 3 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestDeployDiagFacetViaTRAXSaga` | ⭐⭐⭐ | Deploy diagnostic facet via TRAX |
| `TestDeployMinimalFacetsViaTRAXSaga` | ⭐⭐⭐ | Minimal facet set deployment |
| `TestDeployCoreFacetsViaTRAXSaga` | ⭐⭐⭐ | Core facet deployment |

---

## Group 16: Instrument Manager Tests

**Complexity**: ⭐⭐⭐ MEDIUM to ⭐⭐⭐⭐ HIGH

**Files**:
- `tests/e2e/instrmgr/instrument_authorization_saga_test.go`

**Description**: Tests for instrument authorization via Instrument Manager, including security and cash token authorization.

### Test Functions - 5 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestSecurityAuthorizationEndToEnd` | ⭐⭐⭐⭐⭐ | Complete security authorization workflow |
| `TestCashTokenAuthorizationEndToEnd` | ⭐⭐⭐⭐⭐ | Complete cash token authorization |
| `TestRejectInstrumentWithInvalidType` | ⭐⭐⭐ | Error: invalid instrument type |
| `TestRejectInstrumentWithMissingAccount` | ⭐⭐⭐ | Error: missing account |
| `TestInstrumentAuthorizationIdempotency` | ⭐⭐⭐ | Idempotency testing |

---

## Group 17: LASER Cross-Instance Tests

**Complexity**: ⭐⭐⭐ MEDIUM

**Files**:
- `tests/e2e/laser/laser_cross_instance_test.go`

**Description**: Tests for LASER operations across multiple instances, including proxy deployment and config discovery.

### Test Functions - 4 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestLaserCrossInstance_DeployViaProxy` | ⭐⭐⭐ | Deploy contract via proxy instance |
| `TestLaserCrossInstance_QueryViaProxy` | ⭐⭐⭐ | Query results via proxy |
| `TestLaserCrossInstance_ConfigDiscovery` | ⭐⭐⭐ | Config discovery across instances |
| `TestLaserCrossInstance_SlotCreation` | ⭐⭐⭐ | Cross-instance slot creation |

---

## Group 18: Import & Data Migration Tests

**Complexity**: ⭐⭐⭐ MEDIUM

**Files**:
- `tests/e2e/laser/import_authorized_instrument_test.go`

**Description**: Tests for importing authorized instruments via Security Depository Manager (SDMGR).

### Test Functions - 4 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestImportAuthorizedInstrumentViaSdmgr` | ⭐⭐⭐ | Import security instrument |
| `TestImportCashTokenViaSdmgr` | ⭐⭐⭐ | Import cash token |
| `TestImportAuthorizedInstrumentNonExistentDepository` | ⭐⭐⭐ | Error: invalid depository |
| `TestImportAuthorizedInstrumentDuplicate` | ⭐⭐⭐ | Error: duplicate import |

---

## Group 19: ERC20 Facet Routing Tests

**Complexity**: ⭐⭐ MEDIUM to LOW

**Files**:
- `tests/e2e/laser/erc20_facet_routing_test.go`

**Description**: Tests for ERC20 facet routing and initialization operations.

### Test Functions - 10 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestErc20Facet_InitializeViaLcmgr_GreenPath` | ⭐⭐⭐ | Facet initialization via LcMgr |
| `TestErc20Facet_RoutingDoesNotAffectExecutorERC20` | ⭐⭐⭐ | Routing isolation |
| `TestErc20Facet_Initialize_MissingName_RedPath` | ⭐⭐⭐ | Error: missing name |
| `TestErc20Facet_Initialize_MissingSymbol_RedPath` | ⭐⭐⭐ | Error: missing symbol |
| `TestErc20Facet_Initialize_InvalidDecimals_RedPath` | ⭐⭐⭐ | Error: invalid decimals |
| `TestErc20Facet_UnknownOperation_FallsToDefault` | ⭐⭐⭐ | Default handling |
| `TestErc20FacetRouting_IsErc20FacetOperation_Erc20Initialize` | ⭐⭐ | Unit: ERC20 operation check |
| `TestErc20FacetRouting_IsErc20FacetOperation_NonErc20Operations` | ⭐⭐ | Unit: non-ERC20 operations |
| `TestErc20FacetRouting_OperationPrecedence` | ⭐⭐ | Unit: operation precedence |

---

## Group 20: Executor CRUD Tests

**Complexity**: ⭐⭐ LOW

**Files**:
- `tests/e2e/laser/executor_crud_test.go`

**Description**: Basic CRUD operations for LASER executors via lasercli with database isolation.

### Test Functions - 27 tests

| Test Function | Description |
|--------------|-------------|
| `TestExecutorCRUD_FullWorkflow` | Orchestrated CRUD workflow |
| `TestExecutorCreate_Basic` | Basic executor creation |
| `TestExecutorCreate_WithAllFields` | Creation with all fields |
| `TestExecutorCreate_DuplicateIID` | Error: duplicate IID |
| `TestExecutorCreate_InvalidIID` | Error: invalid IID |
| `TestExecutorGet_Success` | Get executor |
| `TestExecutorGet_NotFound` | Error: not found |
| `TestExecutorList_Empty` | List empty |
| `TestExecutorList_WithPagination` | List with pagination |
| `TestExecutorList_WithSearch` | List with search |
| `TestExecutorUpdate_DisplayName` | Update display name |
| `TestExecutorUpdate_MultipleFields` | Update multiple fields |
| `TestExecutorUpdate_NotFound` | Error: not found |
| `TestExecutorDelete_Success` | Delete executor |
| `TestExecutorDelete_NotFound` | Error: not found |
| `TestExecutorDelete_CancelConfirmation` | Cancel delete |
| `TestExecutorCreate_WithSlotAddressDerivationAlgorithm_ID` | Algorithm: ID |
| `TestExecutorCreate_WithSlotAddressDerivationAlgorithm_SHA256_20` | Algorithm: SHA256_20 |
| `TestExecutorCreate_WithSlotAddressDerivationAlgorithm_RND_20` | Algorithm: RND_20 |
| `TestExecutorCreate_WithSlotAddressDerivationAlgorithm_RND_64` | Algorithm: RND_64 |
| `TestExecutorCreate_DefaultSlotAddressDerivationAlgorithm` | Default algorithm |
| `TestExecutorCreate_WithInvalidSlotAddressDerivationAlgorithm` | Error: invalid algorithm |
| `TestExecutorUpdate_SlotAddressDerivationAlgorithm_ShouldBeImmutable` | Immutability check |
| `TestExecutorUpdate_WithInvalidSlotAddressDerivationAlgorithm_ShouldBeImmutable` | Immutability with invalid |
| `TestExecutorCRUD_SlotAddressDerivationAlgorithm_AllVariants` | All algorithm variants |
| `TestExecutorCreate_SlotAddressDerivationAlgorithm_CaseSensitivity` | Case sensitivity |
| `TestExecutorCreate_SlotAddressDerivationAlgorithm_WithOtherFields` | Algorithm with other fields |

---

## Group 21: Router CRUD Tests

**Complexity**: ⭐⭐ LOW

**Files**:
- `tests/e2e/laser/router_crud_test.go`

**Description**: Basic CRUD operations for LASER routers.

### Test Functions - 18 tests

| Test Function | Description |
|--------------|-------------|
| `TestRouterCreate_WithSingleRoute` | Create with single route |
| `TestRouterCreate_WithMultipleRoutes` | Create with multiple routes |
| `TestRouterCreate_WithRelayAction` | Create with relay action |
| `TestRouterCreate_WithExternalCallAction` | Create with external call |
| `TestRouterCreate_EmptyRoutes` | Error: empty routes |
| `TestRouterCreate_InvalidRoutesJSON` | Error: invalid JSON |
| `TestRouterCreate_DuplicateIID` | Error: duplicate IID |
| `TestRouterGet_Success` | Get router |
| `TestRouterGet_NotFound` | Error: not found |
| `TestRouterList_Empty` | List empty |
| `TestRouterList_WithPagination` | List with pagination |
| `TestRouterUpdate_ReplaceRoutes` | Update: replace routes |
| `TestRouterUpdate_DisplayNameAndLabels` | Update: name and labels |
| `TestRouterUpdate_NotFound` | Error: not found |
| `TestRouterDelete_Success` | Delete router |
| `TestRouterDelete_NotFound` | Error: not found |
| `TestRouterDelete_CancelConfirmation` | Cancel delete |
| `TestRouterCRUD_FullWorkflow` | Full CRUD workflow |

---

## Group 22: Execution Runtime CRUD Tests

**Complexity**: ⭐⭐ LOW

**Files**:
- `tests/e2e/laser/execution_runtime_crud_test.go`

**Description**: Basic CRUD operations for execution runtimes (EVM/RDBMS types).

### Test Functions - 22 tests

| Test Function | Description |
|--------------|-------------|
| `TestExecutionRuntimeCreate_Basic` | Basic creation |
| `TestExecutionRuntimeCreate_WithAllFields` | Creation with all fields |
| `TestExecutionRuntimeCreate_WithRDBMSType` | RDBMS type creation |
| `TestExecutionRuntimeCreate_DuplicateName` | Error: duplicate name |
| `TestExecutionRuntimeCreate_MissingName` | Error: missing name |
| `TestExecutionRuntimeGet_Success` | Get runtime |
| `TestExecutionRuntimeGet_NotFound` | Error: not found |
| `TestExecutionRuntimeGetByName_Success` | Get by name |
| `TestExecutionRuntimeGetByName_NotFound` | Error: name not found |
| `TestExecutionRuntimeList_Empty` | List empty |
| `TestExecutionRuntimeList_WithPagination` | List with pagination |
| `TestExecutionRuntimeUpdate_DisplayName` | Update display name |
| `TestExecutionRuntimeUpdate_MultipleFields` | Update multiple fields |
| `TestExecutionRuntimeUpdate_NotFound` | Error: not found |
| `TestExecutionRuntimeDelete_Success` | Delete runtime |
| `TestExecutionRuntimeDelete_NotFound` | Error: not found |
| `TestExecutionRuntimeDelete_CancelConfirmation` | Cancel delete |
| `TestExecutionRuntimeEndpoints_ListEmpty` | List endpoints |
| `TestExecutionRuntimeCRUD_FullWorkflow` | Full CRUD workflow |
| `TestExecutionRuntimeCreate_TypeEVM` | EVM type |
| `TestExecutionRuntimeCreate_DefaultType` | Default type |
| `TestExecutionRuntimeCreate_AllTypes` | All type variants |

---

## Group 23: CSD Message Gateway and SD App Gateway Tests

**Complexity**: ⭐⭐ LOW

**Files**:
- `tests/e2e/laser/csdmsggw_rest_api_test.go`
- `tests/e2e/laser/sdappgw_custodian_sub_account_test.go`
- `tests/e2e/laser/sdappgw_issue_units_test.go`

**Description**: Gateway tests for CSD Message Gateway REST endpoints, SD App Gateway custodian sub-account creation, and SD App Gateway issue-units issuer resolution.

### Existing Test Functions - 12 tests

| Test Function | Description |
|--------------|-------------|
| `TestCsdMsgGw_ListCashTokens_EmptyResponse` | Empty response |
| `TestCsdMsgGw_ListCashTokens_Pagination` | Pagination |
| `TestCsdMsgGw_ListCashTokens_InvalidLimit` | Error: invalid limit |
| `TestCsdMsgGw_ListCashTokens_InvalidOrderDirection` | Error: invalid order |
| `TestCsdMsgGw_ListCashTokens_MissingApiKey` | Error: missing API key |
| `TestCsdMsgGw_ListCashTokens_InvalidApiKey` | Error: invalid API key |
| `TestCsdMsgGw_ListSecurities_EmptyResponse` | Empty response |
| `TestCsdMsgGw_ListSecurities_Pagination` | Pagination |
| `TestCsdMsgGw_ListSecurities_InvalidLimit` | Error: invalid limit |
| `TestCsdMsgGw_ListSecurities_InvalidOrderDirection` | Error: invalid order |
| `TestCsdMsgGw_ListSecurities_MissingApiKey` | Error: missing API key |
| `TestCsdMsgGw_ListSecurities_InvalidApiKey` | Error: invalid API key |

### Custodian REST API Tests - 29 tests (planned)

**File**: `tests/e2e/laser/csdmsggw_custodian_rest_api_test.go`

**Setup**: Runs `setup_new_custodian_participant` saga to create a custodian with legal structure, custody account, and API key.

#### Green Path Tests - 14 tests

| Test Function | Description |
|--------------|-------------|
| `TestCsdMsgGwCustodian_ListLegalStructures_Success` | List LS for authenticated custodian |
| `TestCsdMsgGwCustodian_CreateSubAccount_SingleLS_Success` | Create sub-account (auto-resolve single LS) |
| `TestCsdMsgGwCustodian_CreateSubAccount_MultipleLS_Success` | Create with explicit LS IID |
| `TestCsdMsgGwCustodian_CreateSubAccount_VerifySagaCompletion` | Wait for saga, verify account ACTIVE with ETH address |
| `TestCsdMsgGwCustodian_ListSubAccounts_Success` | List sub-accounts after creation |
| `TestCsdMsgGwCustodian_ListSubAccounts_WithSearch` | Search filter on sub-accounts |
| `TestCsdMsgGwCustodian_ListSubAccounts_Pagination` | Pagination works correctly |
| `TestCsdMsgGwCustodian_ListSubAccountHoldings_Success` | Query holdings (may be empty/zero) |
| `TestCsdMsgGwCustodian_ListSubAccountHoldings_WithSecurityFilter` | Filter by FinIdentifierString |
| `TestCsdMsgGwCustodian_ListSubAccountHoldings_WithSubAccountFilter` | Filter by sub-account IIDs |
| `TestCsdMsgGwCustodian_GetLegalStructureInfo_Success` | Full LS info with accounts + mechanisms |
| `TestCsdMsgGwCustodian_GetLegalStructureInfo_VerifyMechanismTypes` | Verify AUTHORISATION_SOURCE + VOTING mechanisms present |
| `TestCsdMsgGwCustodian_GetLegalStructureInfo_VerifyAccountRelationTypes` | Verify CUSTODY_ACCOUNT + PARTNER account relations |
| `TestCsdMsgGwCustodian_GetLegalStructureInfo_WithExplicitLSIid` | Same result with explicit LS IID in query param |

#### Red Path Tests - 15 tests

| Test Function | Description |
|--------------|-------------|
| `TestCsdMsgGwCustodian_CreateSubAccount_NoAuth` | Missing API key -> 401 |
| `TestCsdMsgGwCustodian_CreateSubAccount_InvalidApiKey` | Bad key -> 401 |
| `TestCsdMsgGwCustodian_CreateSubAccount_NoLegalStructures` | Participant with 0 LS -> 400 |
| `TestCsdMsgGwCustodian_CreateSubAccount_MultipleLS_MissingLSIid` | >1 LS, no LS provided -> 400 |
| `TestCsdMsgGwCustodian_CreateSubAccount_InvalidLSIid` | LS not owned by participant -> 400 |
| `TestCsdMsgGwCustodian_CreateSubAccount_MissingExternalAccountId` | No external_account_id -> 400 |
| `TestCsdMsgGwCustodian_CreateSubAccount_DuplicateExternalId` | Duplicate (participant, ext_id) -> existing account with `already_exists=true` |
| `TestCsdMsgGwCustodian_ListLegalStructures_NoAuth` | Missing API key -> 401 |
| `TestCsdMsgGwCustodian_ListSubAccounts_NoCustodyAccount` | LS without custody account -> 400 |
| `TestCsdMsgGwCustodian_ListSubAccountHoldings_NoAuth` | Missing API key -> 401 |
| `TestCsdMsgGwCustodian_ListSubAccounts_InvalidLSIid` | LS not owned by participant -> 400 |
| `TestCsdMsgGwCustodian_GetLegalStructureInfo_NoAuth` | Missing API key -> 401 |
| `TestCsdMsgGwCustodian_GetLegalStructureInfo_InvalidApiKey` | Bad key -> 401 |
| `TestCsdMsgGwCustodian_GetLegalStructureInfo_InvalidLSIid` | Non-existent LS in query param -> 400 |
| `TestCsdMsgGwCustodian_GetLegalStructureInfo_MultipleLS_MissingLSIid` | >1 LS, no query param -> 400 |

### SD App Gateway Custodian Sub-account Tests - 7 tests

**File**: `tests/e2e/laser/sdappgw_custodian_sub_account_test.go`

**Setup**: Reuses the custodian E2E setup helper, calls the `sdappgw` gRPC admin gateway, and verifies the existing `create_custodian_sub_account` saga behavior.

| Test Function | Description |
|--------------|-------------|
| `TestSdAppGwCustodianSubAccount_CreateViaAdminGateway` | Create via sdappgw, wait for saga, verify ACTIVE child and `ListAccountSubAccounts` |
| `TestSdAppGwCustodianSubAccount_CreateRelatedAccountViaAdminGateway` | Create via sdappgw with a PARTNER legal-structure relation and verify it appears in `ListLegalStructureAccounts` but not `ListAccountSubAccounts` |
| `TestSdAppGwCustodianSubAccount_CreateUnderRelatedAccountViaAdminGateway` | Create a child under a newly created PARTNER related account and verify it appears in that parent's `ListAccountSubAccounts` |
| `TestSdAppGwCustodianSubAccount_DuplicateExternalIdReturnsExisting` | Duplicate external ID returns existing account without a new saga |
| `TestSdAppGwCustodianSubAccount_RejectsMissingExternalAccountId` | Missing external account ID -> validation error |
| `TestSdAppGwCustodianSubAccount_RejectsInvalidLegalStructure` | Invalid legal structure -> validation error |
| `TestSdAppGwCustodianSubAccount_RejectsUnsupportedLegalStructureRelationType` | Custody/clearing legal-structure account relation types are rejected by this client-account workflow |

### SD App Gateway Issue Units Tests - 1 test

**File**: `tests/e2e/laser/sdappgw_issue_units_test.go`

**Setup**: Reuses the fund-account/security-token infrastructure, marks the issuing legal structure as an issuer, creates a second issuer through the issuer onboarding saga, authorizes a security under the first issuer, and calls `sdappgw` issue-units over gRPC.

| Test Function | Description |
|--------------|-------------|
| `TestSdAppGwIssueUnits_TwoIssuersUsesSelectedSecurityIssuer` | With two issuers visible in sdappgw, rejects a wrong issuer hint and successfully issues units using the selected security's issuer relation |

#### batch-issue-security-units (rework — replaces legacy fund-batch)

**File**: `tests/e2e/laser/csdmsggw_batch_issue_security_units_test.go`

**Background**: Per `docs/TODO_BATCH_ISSUE_SECURITY_UNITS.md`, the legacy
`POST /custodians/accounts/fund-batch` was renamed to
`POST /custodians/accounts/batch-issue-security-units` (securities-only,
PLEGP-only, asynchronous future-list response, external identifiers
only). The poll endpoint
`GET /custodians/accounts/futures/:future_id` and the annex download
endpoint `GET /custodians/accounts/futures/:future_id/annexes/:annex_iid`
ship together.

| Test Function | Description |
|--------------|-------------|
| `TestCsdMsgGw_BatchIssueSecurityUnits_MissingApiKey` | No API key header → 401 |
| `TestCsdMsgGw_BatchIssueSecurityUnits_NonPlegpKey` | API key valid but not principal participant → 403 |
| `TestCsdMsgGw_BatchIssueSecurityUnits_FundTypeFieldRejected` | Strict-bind catches the legacy `fund_type` body field |
| `TestCsdMsgGw_BatchIssueSecurityUnits_StrictBindingRejectsIid` | Strict-bind catches `legal_structure_iid` (skip until PLEGP fixture) |
| `TestCsdMsgGw_LegacyFundBatchRouteIsRemoved` | Legacy `/accounts/fund-batch` route returns 404/405 |
| `TestCsdMsgGw_BatchIssueSecurityUnits_FuturesNoCancel` | DELETE on `/futures/:id` is not routed (no-cancel rule) |
| `TestCsdMsgGw_BatchIssueSecurityUnits_ErrorBodyHasNoIidLeakage` | 401 body must not contain any iid pattern |
| `TestCsdMsgGw_BatchIssueSecurityUnits_HappyPath` | Full saga + poll happy path (skip until PLEGP + listing + initiator fixtures land) |

---

## Group 24: Smoke Tests (Health Checks)

**Complexity**: ⭐ LOWEST

**Files**:
- `tests/e2e/laser/smoke_test.go`
- `tests/e2e/laser/accmgr_smoke_test.go`
- `tests/e2e/laser/instrmgr_smoke_test.go`
- `tests/e2e/laser/trax_smoke_test.go`
- `tests/e2e/laser/native_eth_transfer_smoke_test.go`

**Description**: Basic health checks and smoke tests for service availability.

### LASER Smoke Tests - 7 tests

| Test Function | Description |
|--------------|-------------|
| `TestEnvironmentHealthCheck` | PostgreSQL + service health |
| `TestDatabaseSchemaCreation` | Schema existence verification |
| `TestBasicDatabaseOperations` | CRUD on shared.entities |
| `TestLaserAPIEndpoints` | REST API connectivity |
| `TestLcmgrAPIEndpoints` | LcMgr connectivity |
| `TestLasercliAvailability` | CLI availability |
| `TestAllLASERTablesExist` | All tables exist |

### AccMgr Smoke Tests - 3 tests

| Test Function | Description |
|--------------|-------------|
| `TestEnvironmentAccMgrHealthCheck` | AccMgr health check |
| `TestEnvironmentAccMgrSagaSubmitterReady` | Saga submitter readiness |
| `TestBasicAccMgrCreateAccount` | Basic account creation |

### InstrMgr Smoke Tests - 3 tests

| Test Function | Description |
|--------------|-------------|
| `TestEnvironmentInstrMgrHealthCheck` | InstrMgr health check |
| `TestEnvironmentInstrMgrSagaSubmitterReady` | Saga submitter readiness |
| `TestBasicInstrMgrListInstruments` | List instruments |

### TRAX Smoke Tests - 2 tests

| Test Function | Description |
|--------------|-------------|
| `TestTRAXSmoke` | Basic TRAX check |
| `TestTRAXSmokeWithSubmitter` | TRAX with submitter |

### Native Transfer Smoke Test - 1 test

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestNativeETHTransferSmoke` | ⭐⭐ | Native ETH transfer on blockchain |

---

## Group 25: Config & Test Infrastructure Tests

**Complexity**: ⭐ LOWEST

**Makefile Target**: `make laser-e2e-cat25`

**Files**:
- `tests/e2e/laser/config_test.go`
- `tests/e2e/laser/test_results_capture_test.go`
- `tests/e2e/laser/configmgr_test.go`

**Description**: Configuration and test infrastructure verification, including configmgr daemon CRUD operations.

### Test Functions - 12 tests

| Test Function | Description |
|--------------|-------------|
| `TestConfigGetAndPut` | Config CRUD operations |
| `TestResultsCaptureIntegration` | Results capture integration |
| `TestResultsCaptureFailureScenario` | Failure scenario capture |
| `TestResultsDirectoryStructure` | Directory structure verification |
| `TestConfigMgr_HealthCheck` | ConfigMgr health endpoint |
| `TestConfigMgr_ListValidKeys` | List valid config keys with set_once flags |
| `TestConfigMgr_SetAndGet` | Set and get a config value |
| `TestConfigMgr_SetOnce_RejectsDuplicate` | SetOnce semantics: second PUT returns 409 |
| `TestConfigMgr_ListAll` | List all stored configs |
| `TestConfigMgr_InvalidKey_Rejected` | Unknown key returns 400 |
| `TestConfigMgr_GetUnsetKey` | Valid but unset key returns 404 |
| `TestConfigMgr_DeleteSetOnce_Rejected` | Delete set-once key returns 400 |

---

## Group 26: Listing Manager CRUD Tests

**Complexity**: ⭐⭐ LOW

**Makefile Target**: `make laser-e2e-cat26`

**Files**:
- `tests/e2e/laser/listingmgr_crud_test.go`

**Description**: Basic CRUD operations for the listingmgr daemon's REST API covering SecurityListing, SecurityListingDeployment, and SecurityListingEvent resources.

### Test Functions

| Test Function | Description |
|--------------|-------------|
| `TestListingMgr_SecurityListingCRUD` | Create, read, update, list, delete SecurityListing |
| `TestListingMgr_SecurityListingDeploymentCRUD` | Create, read, list SecurityListingDeployment |
| `TestListingMgr_SecurityListingEventCRUD` | Create, read, list SecurityListingEvent |

---

## Group 27: Security Listing Deployment Tests

**Complexity**: ⭐⭐⭐⭐ HIGH

**Makefile Target**: `make laser-e2e-ethbc-cat27`

**Files**:
- `tests/e2e/laser/security_listing_deployment_test.go`

**Description**: Tests for the `setup_security_listing` TRAX saga (7 steps) that deploys security listings with on-chain trading pair creation via `createPairV2` on an Agora Engine diamond. Includes csdmsggw deployment config endpoint tests.

**Dependencies**: TRAX, LASER, listingmgr, csdmsggw, accmgr, instrmgr, blockchain (Anvil)

### Test Functions - 10 tests

| Test Function | Complexity | Description |
|--------------|------------|-------------|
| `TestSetupSecurityListing_FullFlow` | ⭐⭐⭐⭐⭐ | Complete listing + on-chain pair deployment via 7-step saga; verifies SecurityListing, SecurityListingDeployment, SecurityListingEvent, Calendar |
| `TestSetupSecurityListing_VerifyOnChainPair` | ⭐⭐⭐⭐⭐ | Green path with on-chain pair verification via deployment details (agora_pair_id) |
| `TestSetupSecurityListing_ReuseExistingListing` | ⭐⭐⭐⭐⭐ | Green path: run saga twice with same security/currency but different exec_runtime, verify listing reuse with 2 deployments |
| `TestSetupSecurityListing_DuplicateDeployment` | ⭐⭐⭐ | Error: duplicate deployment for same exec runtime (saga compensated) |
| `TestSetupSecurityListing_InvalidFinIdStr` | ⭐⭐⭐ | Error: malformed FinIdentifierString |
| `TestSetupSecurityListing_MissingTradingMechanism` | ⭐⭐⭐ | Error: non-existent trading mechanism slot address, saga fails at step 3 |
| `TestSetupSecurityListing_MissingCSDConfig` | ⭐⭐⭐ | Error: security not found in instrmgr, saga fails at step 2 |
| `TestCsdMsgGw_DeploymentConfig_MissingParams` | ⭐⭐ | csdmsggw config: missing query params returns 400 |
| `TestCsdMsgGw_DeploymentConfig_SecurityNotFound` | ⭐⭐ | csdmsggw config: non-existent security returns 404/500 |
| `TestCsdMsgGw_DeploymentConfig_Success` | ⭐⭐⭐ | csdmsggw config: happy path with full DB seeding, verifies all response fields (slot addrs, CFI code, CSD identifier, display names) |

**Prerequisites**:
- Legal participant with trading mechanism deployed
- Security and cash tokens issued
- Treasury mechanisms deployed for both issuers

---

## Summary Statistics

| Complexity Level | Test Count | Percentage |
|-----------------|------------|------------|
| ⭐⭐⭐⭐⭐ HIGHEST | ~65 | 16% |
| ⭐⭐⭐⭐ HIGH | ~103 | 26% |
| ⭐⭐⭐ MEDIUM | ~128 | 32% |
| ⭐⭐ LOW | ~87 | 22% |
| ⭐ LOWEST | ~20 | 5% |
| **TOTAL** | **~403** | **100%** |

---

## Test Execution Guidelines

### Running Tests

```bash
# Run all E2E tests (no parallelism)
make e2e

# Run specific test suites
make laser-e2e-full      # Full LASER E2E test suite
make laser-e2e-smoke     # Smoke tests only
make trax-e2e-full       # Full TRAX E2E test suite
make instrmgr-e2e        # Instrument Manager E2E tests
```

### Key Principles

1. **Sequential execution only** - Tests must run with `-p 1` flag (no parallelism)
2. **Use CLI tools exclusively** - Never direct SQL in test logic (exception: setup functions)
3. **Hardcoded IIDs** - Use pattern: `{resource}-{suite}-test-{variant}`
4. **Database isolation** - Each test function must call `setupTestDatabase*` as first operation

### Test Structure Pattern

```go
func TestResource_Operation_Scenario(t *testing.T) {
    setupTestDatabaseFor<Resource>(t)  // First line - always
    iid := "resource-suite-test-variant"  // Hardcoded IID
    // Use lasercli/traxcli for all operations
}
```

---

## Service Dependencies Matrix

| Test Group | Services Required |
|------------|-------------------|
| TRAX Saga Tests | traxctrl, 3x traxcoord, executors, blockchain |
| Individual Saga Steps | Service-specific (accmgr, laser, treassvc) |
| Diamond Tests | LASER, blockchain, Lattice contracts |
| ERC20 Tests | LASER executors, blockchain |
| Participant CLI | prtagent, accmgr, TRAX |
| Smoke Tests | Individual service only |

---

## Blockchain Interaction Categories

| Category | Test Groups | Percentage |
|----------|-------------|------------|
| **No Blockchain** | CRUD, Schema, Config, Smoke | ~30% |
| **Read-Only Blockchain** | Balance queries, Contract verification | ~25% |
| **Write Blockchain** | Deployments, Transfers, Minting | ~45% |

---

## Group 29: FIX SecurityDefinition Tests

**Complexity**: ⭐⭐ LOW

**Makefile Category**: Cat 29 (`make laser-e2e-cat29`)

**Mode**: RDBMS (no blockchain required)

**Description**: Tests the fixreceiver's ability to produce FIX SecurityDefinition (MsgType=d) messages from SecurityListing records fetched from the listingmgr REST API. Uses a real QuickFIX initiator (FIX client) connecting to fixreceiver.

**Services Required**: postgres, redis, rabbitmq, listingmgr, fixreceiver

**Test File**: `tests/e2e/laser/fixreceiver_secdef_test.go`

### Tests

| # | Test Function | Description |
|---|---|---|
| 1 | `TestFIXSecurityDefinition_FromListings_BasicFlow` | Create one SecurityListing, send SecurityDefinitionRequest, verify all FIX fields (Symbol, Currency, SecurityID, SecurityIDSource, SecurityType, SecurityStatus, SecurityExchange, CFICode, PriceType, TotalNumSecurities, SecurityDesc, MinPriceIncrement, TradeDate, Text metadata) |
| 2 | `TestFIXSecurityDefinition_FromListings_MultipleListings` | Create 3 listings with different tickers/currencies, verify 3 SecurityDefinition messages with correct TotalNumSecurities=3 and distinct symbols |
| 3 | `TestFIXSecurityDefinition_FromListings_NoListings` | Empty database, verify 0 SecurityDefinition messages returned (graceful empty response) |
| 4 | `TestFIXSecurityDefinition_FromListings_WithAltID` | Listing with ISIN (primary) + CUSIP (alt) identifiers, verify NoSecurityAltID=1, SecurityAltID, SecurityAltIDSource fields |

---

## Group 31: Create Direct Order Tests

**Complexity**: ⭐⭐⭐⭐ HIGH

**Makefile Category**: Cat 31 (`make laser-e2e-ethbc-cat31`)

**Mode**: EthBC (requires Anvil blockchain)

**Description**: Tests the create_direct_order TRAX saga which submits orders on-chain via the Agora Engine DirectOrderManagerV2 facet, then creates Order and OrderEvent records in the listingmgr database. Builds on setup_security_listing infrastructure — requires a fully deployed SecurityListing with an on-chain trading pair. Also tests REST pre-validation and query endpoints.

**Services Required**: postgres, redis, rabbitmq, anvil, lasersvc, traxcoord, traxctrl, listingmgr, csdmsggw, instrmgr, accmgr

**Test File**: `tests/e2e/laser/create_direct_order_test.go`

### Green Path Tests

| # | Test Function | Description |
|---|---|---|
| 1 | `TestCreateDirectOrder_LimitBid` | Submit LIMIT BID order, verify saga completion, Order record (status=NEW, exchange_oid format, order_hash), and OrderEvent (type=CREATE) |
| 2 | `TestCreateDirectOrder_LimitAsk` | Submit LIMIT ASK order, verify saga completion and Order record with side=ASK |
| 3 | `TestCreateDirectOrder_MarketBid` | Submit MARKET BID order (price=0), verify saga completion and Order record |
| 4 | `TestCreateDirectOrder_VerifyOrderHash` | Create order, verify order_hash is valid SHA-512/384 hex, chain_id/chain_name populated |
| 5 | `TestCreateDirectOrder_RESTQueryEndpoints` | Create 2 orders, verify GET /orders (list), GET /orders/:iid (single), GET /orders?exchange_oid, GET /orders?external_oid, GET /order-events?order_iid |

### Red Path Tests (REST Pre-Validation)

| # | Test Function | Description |
|---|---|---|
| 6 | `TestCreateDirectOrder_MissingRequiredField` | Missing external_oid -> 400 |
| 7 | `TestCreateDirectOrder_InvalidOrderType` | Invalid order_type -> 400 |
| 8 | `TestCreateDirectOrder_InvalidSide` | Invalid side -> 400 |
| 9 | `TestCreateDirectOrder_ExpiredTimestamp` | Past expire_timestamp -> 400 |
| 10 | `TestCreateDirectOrder_ZeroQuantity` | quantity=0 -> 400 |
| 11 | `TestCreateDirectOrder_MarketOrderWithPrice` | MARKET order with price>0 -> 400 |
| 12 | `TestCreateDirectOrder_LimitOrderZeroPrice` | LIMIT order with price=0 -> 400 |
| 13 | `TestCreateDirectOrder_NonExistentListing` | Non-existent security_listing_iid -> 400 |
| 14 | `TestCreateDirectOrder_NoDeleteOrModify` | DELETE/PUT on /orders/:iid -> 404/405 (routes not registered) |

### Funded Green-Path Tests (Accounts Pre-Funded via fund_csd_accounts)

| # | Test Function | Description |
|---|---|---|
| 15 | `TestCreateDirectOrder_FundedLimitBid_GreenPath` | Fund participant with USD, submit LIMIT BID, verify saga COMMITS, verify ALL Order fields (status=NEW, quantity, price, participant_oid, chain_id, order_hash, etc.), verify OrderEvent fields (order_is_bid, order_quantity, order_price, pair_id, tx_hash, etc.), verify GET /orders/:iid |
| 16 | `TestCreateDirectOrder_FundedLimitAsk_GreenPath` | Fund investor, submit LIMIT ASK, verify saga COMMITS, verify ALL Order fields (side=ASK, status=NEW, etc.), verify OrderEvent (order_is_bid=false) |
| 17 | `TestCreateDirectOrder_FundedMarketBid_GreenPath` | Fund participant, submit MARKET BID (price=0), verify saga COMMITS, verify Order fields (order_type=MARKET, price=0), verify OrderEvent |
| 18 | `TestCreateDirectOrder_GetOrderByIid` | Create order, verify GET /orders/:iid returns all fields matching creation, verify 404 for non-existent IID |
| 19 | `TestCreateDirectOrder_CompensationCleanup` | Submit unfunded order, saga COMPENSATES, verify Order/OrderEvent records are cleaned up (no residual DB records) |
| 20 | `TestCreateDirectOrder_IdempotencyKey` | Submit two orders with same idempotency_key, verify first order preserved and no duplicates |
| 21 | `TestCreateDirectOrder_RESTQueryEndpoints_WithData` | Create order, verify GET /orders list contains it, test external_oid/exchange_oid filtering, verify order events, test pagination (`page_size=1`) |
| 22 | `TestCreateDirectOrder_MatchBidAsk_GreenPath` | Place BID + ASK orders on same pair with different investors, verify both orders exist on-chain via getOrders with correct params (quantity, price, bid flag), resolve AgoraEngine ETH address from slot IID via LASER translation, verify off-chain Order records intact |

---

## Group 32: FIX NewOrderSingle → Saga Integration Tests

**Complexity**: ⭐⭐⭐⭐ HIGH

**Makefile Category**: Cat 32 (`make laser-e2e-ethbc-cat32`)

**Mode**: EthBC (requires Anvil blockchain)

**Description**: Tests the FIX NewOrderSingle (MsgType=D) → create_direct_order saga integration. Verifies that FIX message fields are correctly mapped to saga inputs, orders are submitted via listingmgr REST API, and the full saga workflow (validate → on-chain → persist) completes. Tests cover all FIX field mapping edge cases, validation failures, compensation cleanup, and idempotency.

**Services Required**: postgres, redis, rabbitmq, anvil, lasersvc, traxcoord, traxctrl, listingmgr, csdmsggw, instrmgr, accmgr

**Test File**: `tests/e2e/laser/fix_new_order_single_saga_test.go`

### Green Path Tests

| # | Test Function | Description |
|---|---|---|
| 1 | `TestFIXNewOrderSingle_LimitBid_GreenPath` | FIX Limit Buy → saga COMMITS, verify Order+OrderEvent records |
| 2 | `TestFIXNewOrderSingle_LimitAsk_GreenPath` | FIX Limit Sell → saga COMMITS |
| 3 | `TestFIXNewOrderSingle_MarketBid_GreenPath` | FIX Market Buy → saga COMMITS |
| 4 | `TestFIXNewOrderSingle_OrderFieldsMatchFIXInput` | Verify Order record fields match the FIX message fields |
| 5 | `TestFIXNewOrderSingle_TraceIdGeneration` | Verify trace_id starts with "fix-" |

### Red Path Tests

| # | Test Function | Description |
|---|---|---|
| 6 | `TestFIXNewOrderSingle_MissingSymbol` | No Symbol (Tag 55) → error |
| 7 | `TestFIXNewOrderSingle_InvalidSide` | Invalid Side → error |
| 8 | `TestFIXNewOrderSingle_InvalidOrderType` | Invalid OrdType → error |
| 9 | `TestFIXNewOrderSingle_ZeroQuantity` | Quantity ≤ 0 → error |
| 10 | `TestFIXNewOrderSingle_MarketOrderWithPrice` | Market + price > 0 → error |
| 11 | `TestFIXNewOrderSingle_LimitOrderZeroPrice` | Limit + price = 0 → error |
| 12 | `TestFIXNewOrderSingle_ExpiredTimestamp` | ExpireTime in past → error |
| 13 | `TestFIXNewOrderSingle_InvalidTimeInForce` | TimeInForce=IOC → error (only DAY/GTC accepted) |
| 14 | `TestFIXNewOrderSingle_MissingInvestorIid` | No ClientID/PartyID → error |
| 15 | `TestFIXNewOrderSingle_NonExistentSymbol` | Symbol not in listingmgr → error |
| 16 | `TestFIXNewOrderSingle_MissingParticipantIid` | Session without participant_iid → error |

### Compensation Tests

| # | Test Function | Description |
|---|---|---|
| 17 | `TestFIXNewOrderSingle_UnfundedAccount_Compensation` | Unfunded → saga COMPENSATED |
| 18 | `TestFIXNewOrderSingle_CompensationCleanup` | No residual Order records after compensation |

### Idempotency Tests

| # | Test Function | Description |
|---|---|---|
| 19 | `TestFIXNewOrderSingle_IdempotencyKey_NoDuplicates` | Same ClOrdID twice → only one order created |

---

## Group 33: FIX Client NOS Sending Tests

**Complexity**: ⭐⭐⭐⭐ HIGH

**Makefile Category**: Cat 33 (`make laser-e2e-ethbc-cat33`)

**Mode**: EthBC (requires Anvil blockchain for full round-trip)

**Description**: Tests the fixclient daemon's ability to SEND NewOrderSingle (MsgType=D) messages to venue FIX endpoints via its REST API, receive ExecutionReport (MsgType=8) and BusinessMessageReject (MsgType=j) responses, and persist all messages in PostgreSQL. Tests the full round-trip: REST POST → FIX NOS → venue processes → saga execution → ER back → DB persistence → polling endpoint retrieval.

**Architecture**:
```
test → REST POST → fixclient → FIX NOS → fixreceiver → saga → ER → fixclient → DB → REST GET → test
```

**Services Required**: postgres, redis, rabbitmq, anvil, lasersvc, traxcoord, traxctrl, listingmgr, csdmsggw, instrmgr, accmgr, fixreceiver, fixclient, marketmgr

**Test File**: `tests/e2e/laser/fixclient_nos_test.go`

### Green Path Tests

| # | Test Function | Description |
|---|---|---|
| 1 | `TestFIXClientNOS_LimitBid_BasicFlow` | POST limit BUY → 202 → poll → ER with OrdStatus=NEW |
| 2 | `TestFIXClientNOS_LimitAsk_BasicFlow` | POST limit SELL → 202 → poll → ER received |
| 3 | `TestFIXClientNOS_MarketBid_BasicFlow` | POST market BUY → 202 → poll → ER received |
| 4 | `TestFIXClientNOS_SentOrderPersistence` | Verify sent_order fields match request body exactly |
| 5 | `TestFIXClientNOS_ExecutionReportPersistence` | Verify ER fields (order_id, exec_id, exec_type, etc.) and raw_fix_message |
| 6 | `TestFIXClientNOS_StatusProgression` | Verify status: SENT → NEW → FILLED progression |
| 7 | `TestFIXClientNOS_VenueBySymbol` | POST using venue symbol instead of IID → 202 |
| 8 | `TestFIXClientNOS_MultipleOrdersDifferentClOrdID` | Two NOS with different cl_ord_id → unique request_ids, correct correlation |
| 9 | `TestFIXClientNOS_FundedOrder_FullRoundTrip` | Pre-funded order → saga COMMITS → ER reflects outcome |

### Red Path Tests — Validation (400)

| # | Test Function | Description |
|---|---|---|
| 10 | `TestFIXClientNOS_MissingClOrdID` | No cl_ord_id → 400 |
| 11 | `TestFIXClientNOS_MissingSymbol` | No symbol → 400 |
| 12 | `TestFIXClientNOS_MissingCurrency` | No currency → 400 |
| 13 | `TestFIXClientNOS_InvalidSide` | side="HOLD" → 400 |
| 14 | `TestFIXClientNOS_InvalidOrderType` | order_type="STOP" → 400 |
| 15 | `TestFIXClientNOS_ZeroQuantity` | quantity="0" → 400 |
| 16 | `TestFIXClientNOS_NegativeQuantity` | quantity="-10" → 400 |
| 17 | `TestFIXClientNOS_MarketOrderWithPrice` | MARKET + price="10.50" → 400 |
| 18 | `TestFIXClientNOS_LimitOrderZeroPrice` | LIMIT + price="0" → 400 |
| 19 | `TestFIXClientNOS_InvalidTimeInForce` | time_in_force="IOC" → 400 |
| 20 | `TestFIXClientNOS_MissingParticipantIid` | No participant_iid → 400 |
| 21 | `TestFIXClientNOS_MissingInvestorIid` | No investor_iid → 400 |
| 22 | `TestFIXClientNOS_ExpiredExpireTime` | expire_time in past → 400 |
| 23 | `TestFIXClientNOS_InvalidQuantityFormat` | quantity="abc" → 400 |
| 24 | `TestFIXClientNOS_MissingSide` | No side → 400 |

### Red Path Tests — Connection (404/503)

| # | Test Function | Description |
|---|---|---|
| 25 | `TestFIXClientNOS_UnknownVenue` | Non-existent venue → 404 |
| 26 | `TestFIXClientNOS_DisconnectedVenue` | Inactive endpoint → 404/503 |

### Red Path Tests — Polling

| # | Test Function | Description |
|---|---|---|
| 27 | `TestFIXClientNOS_PollNonExistentRequestID` | Fake request_id → 404 |
| 28 | `TestFIXClientNOS_PollEmptyRequestID` | Empty request_id → 404 or 400 |

### Red Path Tests — Venue Rejection

| # | Test Function | Description |
|---|---|---|
| 29 | `TestFIXClientNOS_VenueRejectsOrder` | Invalid symbol at venue → ER with REJECTED |
| 30 | `TestFIXClientNOS_UnfundedOrder_Compensation` | Unfunded order → saga COMPENSATES |

### Edge Cases

| # | Test Function | Description |
|---|---|---|
| 31 | `TestFIXClientNOS_EmptyRequestBody` | Empty body → 400 |
| 32 | `TestFIXClientNOS_MalformedJSON` | Invalid JSON → 400 |
| 33 | `TestFIXClientNOS_GTC_DefaultExpire` | GTC + no expire → accepted |
| 34 | `TestFIXClientNOS_DAY_DefaultExpire` | DAY + no expire → accepted with end-of-day expiry |

---

## Group 34: MarketMgr Order Relay Tests

**Complexity**: ⭐⭐⭐⭐ HIGH

**Makefile Category**: Cat 34 (`make laser-e2e-ethbc-cat34`)

**Mode**: EthBC (requires Anvil blockchain for full round-trip)

**Description**: Tests marketmgr's relay endpoints that forward NewOrderSingle and ExecutionReport polling requests to fixclient. Includes direct relay (caller provides venue_iid), listing-based relay (marketmgr resolves security_listing_iid → venue_iid via Redis), and Redis mapping population during SecurityDefinition proxy queries. Also tests the PrtAgent gRPC integration (CreateOrderAsync, GetOrderExecutionReports).

**Architecture**:
```
test → marketmgr relay → fixclient → FIX NOS → fixreceiver → saga → ER → fixclient → marketmgr relay → test
                │
                │ Redis lookup (listing-based relay)
                │ security_listing_iid → venue_iid + symbol
                ▼
           ┌─────────┐
           │  Redis   │
           └─────────┘
```

**Services Required**: postgres, redis, rabbitmq, anvil, lasersvc, traxcoord, traxctrl, listingmgr, csdmsggw, instrmgr, accmgr, fixreceiver, fixclient, marketmgr

**Test File**: `tests/e2e/laser/marketmgr_order_relay_test.go`

**Related TODO**: `docs/TODO_MARKETMGR_ORDER_RELAY_AND_PRTAGENT_INTEGRATION.md`

### Green Path Tests — Direct Relay (venue_iid)

| # | Test Function | Description |
|---|---|---|
| 1 | `TestMarketMgrRelay_DirectNOS_LimitBid` | POST limit BUY via marketmgr relay → 202 → poll ER via marketmgr → OrdStatus=NEW |
| 2 | `TestMarketMgrRelay_DirectNOS_LimitAsk` | POST limit SELL via marketmgr relay → 202 → ER received |
| 3 | `TestMarketMgrRelay_DirectNOS_MarketBid` | POST market BUY (price=0) via relay → 202 → ER received |
| 4 | `TestMarketMgrRelay_DirectNOS_ERPolling` | Send NOS via marketmgr, poll ER via marketmgr, verify all fields match |

### Green Path Tests — Listing-Based Relay

| # | Test Function | Description |
|---|---|---|
| 5 | `TestMarketMgrRelay_ByListing_BasicFlow` | Trigger SecDef query → populate Redis → POST /orders/by-listing → 202 → poll → ER received |
| 6 | `TestMarketMgrRelay_ByListing_MultipleListings` | 2 SecurityListings on same venue → SecDef query → both resolve correctly |

### Red Path Tests — Direct Relay

| # | Test Function | Description |
|---|---|---|
| 7 | `TestMarketMgrRelay_DirectNOS_MissingVenueIid` | POST to /venues//orders → 404 or 400 |
| 8 | `TestMarketMgrRelay_DirectNOS_UnknownVenue` | Non-existent venue → 404 (from fixclient) |
| 9 | `TestMarketMgrRelay_DirectNOS_EmptyBody` | Empty body → 400 (from fixclient) |
| 10 | `TestMarketMgrRelay_DirectNOS_InvalidSide` | side="HOLD" → 400 (from fixclient) |
| 11 | `TestMarketMgrRelay_DirectNOS_MissingClOrdId` | No cl_ord_id → 400 |
| 12 | `TestMarketMgrRelay_DirectNOS_InvalidQuantity` | quantity="0" → 400 |
| 13 | `TestMarketMgrRelay_DirectNOS_LimitZeroPrice` | LIMIT + price="0" → 400 |
| 14 | `TestMarketMgrRelay_DirectNOS_MarketWithPrice` | MARKET + price="10" → 400 |
| 15 | `TestMarketMgrRelay_DirectNOS_FixClientUnavailable` | fixclient down → 503 or 502 |

### Red Path Tests — Listing-Based Relay

| # | Test Function | Description |
|---|---|---|
| 16 | `TestMarketMgrRelay_ByListing_MissingSecurityListingIid` | No security_listing_iid → 400 |
| 17 | `TestMarketMgrRelay_ByListing_UnknownListing` | Listing not in Redis → 404 |
| 18 | `TestMarketMgrRelay_ByListing_MissingSide` | No side → 400 (from fixclient) |
| 19 | `TestMarketMgrRelay_ByListing_EmptyBody` | Empty body → 400 |

### Red Path Tests — ER Polling Relay

| # | Test Function | Description |
|---|---|---|
| 20 | `TestMarketMgrRelay_PollER_NonExistentRequestId` | Fake request_id → 404 |
| 21 | `TestMarketMgrRelay_PollER_EmptyRequestId` | Empty request_id → 404 or 400 |
| 22 | `TestMarketMgrRelay_PollER_FixClientUnavailable` | fixclient down → 502 |

### Redis Mapping Tests

| # | Test Function | Description |
|---|---|---|
| 23 | `TestMarketMgrRelay_SecDefPopulatesRedisMapping` | SecDef query → Redis mapping created → NOS by-listing succeeds |
| 24 | `TestMarketMgrRelay_SecDefNoMatchingListing` | SecDef symbols don't match any SecurityListing → NOS by-listing fails 404 |
| 25 | `TestMarketMgrRelay_SecDefMultipleVenues` | 2 venues → SecDef queries → each listing routes to correct venue |

### CDO Integration Tests (Full Round-Trip)

| # | Test Function | Description |
|---|---|---|
| 26 | `TestMarketMgrRelay_FundedOrder_FullRoundTrip` | Pre-funded order → relay → saga COMMITS → ER reflects outcome |
| 27 | `TestMarketMgrRelay_UnfundedOrder_Compensation` | Unfunded order → relay → saga COMPENSATES → ER reflects rejection |

---

---

## Group 35: Fund Account Command Tests

**Complexity**: ⭐⭐⭐⭐ HIGH

**Makefile Category**: Cat 35 (`make laser-e2e-ethbc-cat35`)

**Mode**: EthBC (requires Anvil blockchain for fund account sagas)

**Description**: Tests the REST API endpoints used by the pacli `fund cash-tokens` and `fund security-tokens` commands. Validates both the single-fund endpoint (cash tokens) and the batch fund endpoint (security tokens). Tests include green-path funding flows, validation error handling, and invalid amount rejection.

**Services Required**: postgres, redis, rabbitmq, anvil, lasersvc, traxcoord, traxctrl, accmgr, instrmgr, treassvc

**Test File**: `tests/e2e/laser/fund_account_cmd_test.go`

**Infrastructure**: Reuses `setupFundAccountTestInfrastructure` from `fund_account_saga_test.go` (Category 1b). Creates an additional destination account (`facmd-e2e-dest-account-1`) for isolation from Cat 1b tests.

### Cash Token Tests

| # | Test Function | Description |
|---|---|---|
| 1 | `TestFundAccountCmd_CashTokens_SingleFund` | Fund account via single-fund endpoint (same API path as pacli fund cash-tokens) → saga COMMITS |
| 2 | `TestFundAccountCmd_CashTokens_InvalidAmount` | Submit fund with amount "0" → 400 or saga fails |
| 3 | `TestFundAccountCmd_CashTokens_BatchEndpoint` | Fund account via batch endpoint with fund_type=cash_token → saga COMMITS |

### Security Token Tests

| # | Test Function | Description |
|---|---|---|
| 4 | `TestFundAccountCmd_SecurityTokens_BatchEndpoint` | Fund with non-existent authorized instrument → saga COMPENSATES |
| 5 | `TestFundAccountCmd_SecurityTokens_ValidationErrors` | Batch endpoint validation: missing authorized_instrument, mismatched arrays, invalid fund_type, negative amount → 400 |

---

---

## Group 36: Trade Indexer Tests

**Complexity**: ⭐⭐⭐⭐ HIGH

**Makefile Category**: Cat 36 (`make laser-e2e-ethbc-cat36`)

**Mode**: EthBC (requires Anvil blockchain for trading mechanism + orders on chain)

**Description**: Tests for the `tradeidxer` daemon — orderbook indexing (L1/L2/L3/VWAP/Depth), OHLC candle generation, trade tape, smart polling, listingmgr proxy endpoints, and EventStoreFacet-backed FIX Execution Reports (35=8) and Trade Capture Reports (35=AE).

**Services Required**: postgres, redis, rabbitmq, anvil, lasersvc, traxcoord, traxctrl, accmgr, instrmgr, listingmgr, tradeidxer

**Test Files**: `tests/e2e/laser/tradeidxer_test.go`, `tests/e2e/laser/tradeidxer_event_indexer_test.go`

**Infrastructure**: Deployed trading mechanism with SecurityListingDeployment, AgoraEngine pair with orders/trades on chain.

### Tests

| # | Test Function | Description |
|---|---|---|
| 1 | `TestTradeIdxer_Health_ReturnsOk` | Health endpoint returns 200 |
| 2 | `TestTradeIdxer_Status_ShowsActiveDeployments` | Status shows discovered listings |
| 3 | `TestTradeIdxer_Orderbook_L1_AfterOrderCreation` | L1 BBO after orders placed |
| 4 | `TestTradeIdxer_Orderbook_L2_PriceAggregation` | L2 price-level aggregation |
| 5 | `TestTradeIdxer_Orderbook_L3_IndividualOrders` | L3 individual orders |
| 6 | `TestTradeIdxer_Orderbook_L2_LimitParam` | L2 limit param restricts levels |
| 7 | `TestTradeIdxer_Orderbook_L2_SideFilter` | L2 side filter (bids/asks only) |
| 8 | `TestTradeIdxer_Orderbook_VWAP_Calculation` | VWAP calculation correctness |
| 9 | `TestTradeIdxer_Orderbook_Depth_CumulativeQuantity` | Depth chart cumulative quantities |
| 10 | `TestTradeIdxer_Trades_AfterMatch` | Trade tape after order match |
| 11 | `TestTradeIdxer_Trades_TimeRangeFilter` | Trade time range filter |
| 12 | `TestTradeIdxer_Trades_GetById` | Get single trade by ID |
| 13 | `TestTradeIdxer_OHLC_BasicCandles` | Basic OHLC candle generation |
| 14 | `TestTradeIdxer_OHLC_AllIntervals` | All 14 intervals produce candles |
| 15 | `TestTradeIdxer_IncrementalUpdate_NewOrder` | Incremental order update |
| 16 | `TestTradeIdxer_Rebuild_ForceTrigger` | Force rebuild clears and rebuilds |
| 17 | `TestTradeIdxer_SmartPolling_BacksOff` | Smart polling back-off |
| 18 | `TestTradeIdxer_SmartPolling_ResetsOnActivity` | Polling resets on activity |
| 19 | `TestTradeIdxer_OHLC_MissingInterval_Returns400` | Missing interval param |
| 20 | `TestTradeIdxer_OHLC_InvalidInterval_Returns400` | Invalid interval value |
| 21 | `TestTradeIdxer_OHLC_MissingFromTs_Returns400` | Missing from_ts param |
| 22 | `TestTradeIdxer_OHLC_MissingToTs_Returns400` | Missing to_ts param |
| 23 | `TestTradeIdxer_OHLC_FromTsGreaterThanToTs_Returns400` | from_ts > to_ts |
| 24 | `TestTradeIdxer_Orderbook_InvalidDeploymentIid_Returns404` | Unknown deployment IID |
| 25 | `TestTradeIdxer_Orderbook_L2_InvalidSide_Returns400` | Invalid side filter |
| 26 | `TestTradeIdxer_Orderbook_L2_NegativeLimit_Returns400` | Negative limit param |
| 27 | `TestTradeIdxer_Trades_InvalidTradeId_Returns404` | Non-existent trade ID |
| 28 | `TestTradeIdxer_Rebuild_InvalidDeploymentIid_Returns404` | Rebuild unknown deployment |
| 29 | `TestTradeIdxer_ListingMgrProxy_OrderbookL2_ProxiesCorrectly` | ListingMgr proxy L2 |
| 30 | `TestTradeIdxer_ListingMgrProxy_OHLC_ProxiesCorrectly` | ListingMgr proxy OHLC |

### Event Store Tests (tradeidxer_event_indexer_test.go)

| # | Test Function | Description |
|---|---|---|
| 31 | `TestTradeIdxer_EventStore_GreenPath_ExecReport_Create` | Exec report with exec_type=0 (NEW) after order creation |
| 32 | `TestTradeIdxer_EventStore_GreenPath_ExecReport_Fill` | Exec report with exec_type=2 (FILL) after matching BID+ASK |
| 33 | `TestTradeIdxer_EventStore_GreenPath_ExecReport_PartialFill` | Partial fill (exec_type=1) on larger BID, full fill on smaller ASK |
| 34 | `TestTradeIdxer_EventStore_GreenPath_TradeReport_NewTrade` | Trade Capture Report after matching BID+ASK with all FIX fields |
| 35 | `TestTradeIdxer_EventStore_GreenPath_IncrementalProcessing` | Cursor-based incremental event processing |
| 36 | `TestTradeIdxer_EventStore_GreenPath_EventCursor` | Event cursor status in /status endpoint |
| 37 | `TestTradeIdxer_EventStore_GreenPath_FilterByExecType` | Filter exec reports by exec_type |
| 38 | `TestTradeIdxer_EventStore_GreenPath_FilterByParticipantIid` | Filter exec reports by participant_iid |
| 39 | `TestTradeIdxer_EventStore_GreenPath_Pagination` | Pagination with limit/offset on exec reports |
| 40 | `TestTradeIdxer_EventStore_GreenPath_SortOrder` | Sort order (asc/desc) on exec reports |
| 41 | `TestTradeIdxer_EventStore_GreenPath_TradeReportFilterByOrderId` | Filter trade reports by order_id (bid or ask) |
| 42 | `TestTradeIdxer_EventStore_RedPath_InvalidDeploymentIid` | Non-existent deployment returns empty results |
| 43 | `TestTradeIdxer_EventStore_RedPath_InvalidExecId` | Non-existent exec_id returns 404 |
| 44 | `TestTradeIdxer_EventStore_RedPath_InvalidTradeReportId` | Non-existent trade_report_id returns 404 |

---

## Group 37: Create Investor Order Saga Tests

**Complexity**: ⭐⭐⭐⭐ HIGH

**Makefile Category**: Cat 37 (`make laser-e2e-ethbc-cat37`)

**Mode**: EthBC (requires Anvil blockchain for treasury vault operations)

**Description**: Tests the `create_investor_order` TRAX saga that creates investor orders via prtagent with balance verification, cash-token locking in dedicated stash, fee transfer to clearing account, and FIX venue submission. Full compensation path testing included.

**Services Required**: postgres, redis, rabbitmq, anvil, lasersvc, traxcoord, traxctrl, accmgr, instrmgr, treassvc, marketmgr, fixclient, fixreceiver, prtagent

**Test File**: `tests/e2e/laser/create_investor_order_test.go`

**Infrastructure**: Full legal participant (PLEGP) with cash token mechanism, funded investor, security listing with FIX venue connection, Redis listing→venue mapping.

### Green Path Tests

| # | Test Function | Description |
|---|---|---|
| 1 | `TestCreateInvestorOrder_LimitBuy` | Full LIMIT BUY via gRPC with balance verification, volume lock, fee, FIX submission |
| 2 | `TestCreateInvestorOrder_LimitSell` | Full LIMIT SELL order via gRPC |
| 3 | `TestCreateInvestorOrder_MarketBuy` | MARKET BUY order (price=0) via gRPC |
| 4 | `TestCreateInvestorOrder_ZeroFee` | Order with fee_amount=0, step 5 skipped |
| 5 | `TestCreateInvestorOrder_EventLogs` | All 5 event logs present in correct order |
| 6 | `TestCreateInvestorOrder_RESTEndpoints` | List, get by IID, by participant_order, by saga |
| 7 | `TestCreateInvestorOrder_MultipleOrders` | 3 sequential orders, different sides/quantities |

### Red Path Tests

| # | Test Function | Description |
|---|---|---|
| 8 | `TestCreateInvestorOrder_MissingFields` | Missing security_listing_iid rejected at gRPC level |
| 9 | `TestCreateInvestorOrder_InvalidSide` | UNKNOWN side rejected at gRPC level |
| 10 | `TestCreateInvestorOrder_MissingQuantity` | Empty quantity rejected at gRPC level |
| 11 | `TestCreateInvestorOrder_InvalidCurrency` | Currency >3 chars rejected at gRPC level |
| 12 | `TestCreateInvestorOrder_MissingParticipantOrderId` | Empty participant_order_id rejected |
| 13 | `TestCreateInvestorOrder_FullCompensation` | Non-existent listing triggers saga compensation |
| 14 | `TestCreateInvestorOrder_NoAPIKey` | Missing gRPC API key returns Unauthenticated error |

### EXIDS Validation Matrix

Gateway-boundary validation of `execution_idempotency_seed` (D1 / D1.1) — runs through the real prtagent gRPC daemon. Mirrors `pkg/grpc/exids/validator_test.go` end-to-end so any divergence between the in-process validator and the deployed binary surfaces here. See `docs/TODO_EXECUTION_IDEMPOTENCY_SEED.md` Phase 8.9.

**Test File**: `tests/e2e/laser/exids_validation_e2e_test.go`

| # | Test Function | Description |
|---|---|---|
| 28 | `TestEXIDS_E2E_RejectsEmptySeed` | Empty seed → InvalidArgument (`EXIDS_MISSING`) |
| 29 | `TestEXIDS_E2E_RejectsTooShortSeed` | 3-byte seed → `EXIDS_TOO_SHORT` |
| 30 | `TestEXIDS_E2E_AcceptsBoundaryLength_8` | 8-byte seed passes the validator (downstream may reject for other reasons) |
| 31 | `TestEXIDS_E2E_RejectsTooLongSeed` | 257-byte seed → `EXIDS_TOO_LONG` |
| 32 | `TestEXIDS_E2E_RejectsLeadingWhitespace` | Leading space → `EXIDS_LEADING_WHITESPACE` |
| 33 | `TestEXIDS_E2E_RejectsTrailingTab` | Trailing tab → `EXIDS_TRAILING_WHITESPACE` |
| 34 | `TestEXIDS_E2E_RejectsInnerWhitespace` | Mid-string tab → `EXIDS_INNER_WHITESPACE` |
| 35 | `TestEXIDS_E2E_RejectsControlChar` | Embedded NUL → `EXIDS_CONTROL_CHAR` (offset reported) |
| 36 | `TestEXIDS_E2E_RejectsNonASCII` | Embedded é → `EXIDS_NON_ASCII` |
| 37 | `TestEXIDS_E2E_RejectsDisallowedSlash` | `/` → `EXIDS_DISALLOWED_CHAR` |
| 38 | `TestEXIDS_E2E_RejectsDisallowedSemicolon` | `;` → `EXIDS_DISALLOWED_CHAR` |
| 39 | `TestEXIDS_E2E_RejectsDisallowedQuote` | `"` → `EXIDS_DISALLOWED_CHAR` |
| 40 | `TestEXIDS_E2E_SeedPropagatesAsTOBIK` | Successful CreateOrder with known seed → saga commits, seed flows verbatim into TOBIK chain |

### Cash-flow EXIDS + Stash Validation

Gateway-boundary validation of `execution_idempotency_seed` (D5) **and** `treasury_stash_derivation_seed` (D14 / TABT O12) on the four cash-flow RPCs surfaced by the prtagent `InvestorService`. Mirrors the unit tests at `pkg/daemons/prtagent/impl/v1/grpc/exids_validation_test.go` but through the deployed binary. The validator runs **before** any treasury / auth state is touched, so these tests are independent of investor funding — happy-path coverage lives in Cat 11.

**Test File**: `tests/e2e/laser/prtagent_cash_flow_validation_e2e_test.go`

| # | Test Function | Description |
|---|---|---|
| 57 | `TestEXIDS_E2E_DepositCash_RejectsEmptySeed` | DepositCash with empty exids seed → InvalidArgument (`EXIDS_MISSING`) |
| 58 | `TestEXIDS_E2E_DepositCash_RejectsTooShortSeed` | 3-byte seed → `EXIDS_TOO_SHORT` |
| 59 | `TestEXIDS_E2E_WithdrawCash_RejectsEmptySeed` | WithdrawCash with empty exids seed → `execution_idempotency_seed: required field is empty` |
| 60 | `TestEXIDS_E2E_WithdrawCash_RejectsEmptyStashSeed` | Empty `treasury_stash_derivation_seed` → InvalidArgument naming the stash field |
| 61 | `TestEXIDS_E2E_WithdrawCash_AcceptsLIQUIDStashSeed` | `allowLiquid=true` posture — literal `"LIQUID"` must NOT be rejected by the validator |
| 62 | `TestEXIDS_E2E_LockCash_RejectsEmptySeed` | LockCash without exids → `execution_idempotency_seed: required field is empty` |
| 63 | `TestEXIDS_E2E_LockCash_RejectsEmptyStashSeed` | LockCash with empty stash seed → InvalidArgument |
| 64 | `TestEXIDS_E2E_LockCash_RejectsLIQUIDStashSeed` | D14.4 + TABT O12 — Lock REJECTS literal `"LIQUID"` |
| 65 | `TestEXIDS_E2E_UnlockCash_RejectsEmptySeed` | UnlockCash without exids → InvalidArgument |
| 66 | `TestEXIDS_E2E_UnlockCash_RejectsLIQUIDStashSeed` | D14.4 — Unlock REJECTS literal `"LIQUID"` |

### Cash-flow GREEN-PATH (TABT + DeriveIndex end-to-end)

Funded happy-path coverage for the four prtagent `InvestorService` cash-flow RPCs. Reuses the pre-funded EXTINV1 investor from `setupCIOTestInfrastructure` (20,000 EUR + 15,000 USD via the broker treasury at order-infra setup step 4.6). Each test submits the gRPC call, watches the saga to COMMIT via `framework.WatchSaga` against `prtagent-traxctrl` / cluster `PRTAGENT`, and asserts on-chain deltas via `GetInvestorCashHoldings`. Critically the Lock / Unlock tests use non-LIQUID, non-numeric stash seeds — the path that returned `stash.DeriveIndex: hashing algorithm not implemented yet` to brokers before STASHOPS Phase 1 landed 2026-05-17.

**Test File**: `tests/e2e/laser/cash_flow_happy_path_e2e_test.go`

| # | Test Function | Description |
|---|---|---|
| 67 | `TestCashFlow_DepositCash_HappyPath` | DepositCash 1.00 EUR → `fund_account_with_cash_tokens` saga commits → investor total_units grows by 100 |
| 68 | `TestCashFlow_WithdrawCash_HappyPath_LiquidSeed` | WithdrawCash 1.00 EUR from LIQUID → TABT commits with `finalize_to_erc20=false` → investor total_units shrinks by 100 |
| 69 | `TestCashFlow_LockCash_HappyPath_ArbitrarySeed` | LockCash 1.00 USD into stash derived from a unique non-LIQUID seed → TABT commits → total_units unchanged, stash[DeriveIndex(seed)] grows by 100 |
| 70 | `TestCashFlow_UnlockCash_HappyPath_ArbitrarySeed` | Lock 1.00 USD into derived stash then Unlock back → both TABT sagas commit → stash returns to pre-lock value |

brktrdsvc parity (`tests/e2e/laser/cash_flow_happy_path_brktrd_e2e_test.go`) — mirror suite that routes the same four operations through the broker-facing `brktrdsvc` gRPC (`brktrdapiv1.BrokerTradingApiService` on `brktrdsvc:17219`) instead of prtagent's `InvestorService`. The `prtagent-brktrdsvc` service block in `tests/e2e/laser/docker-compose.prtagent.yaml` deploys the daemon alongside the rest of the prtagent namespace. (Note: an earlier attempt to deploy brktrdsvc exposed a pre-existing fixclient lease-lifecycle bug — `Refresh()` didn't release `fix_session_lock` rows before zeroing the connections map, so the next `Acquire` collided with the daemon's own zombie lease. Fixed in `pkg/daemons/fixclient/connection_manager.go::Refresh` + `connectToEndpoint` 2026-05-17.)

| # | Test Function | Description |
|---|---|---|
| 71 | `TestCashFlow_DepositCash_HappyPath_Brktrd` | Same as #67 via brktrdsvc — proves broker-side auth + saga submission |
| 72 | `TestCashFlow_WithdrawCash_HappyPath_LiquidSeed_Brktrd` | Same as #68 via brktrdsvc |
| 73 | `TestCashFlow_LockCash_HappyPath_ArbitrarySeed_Brktrd` | Same as #69 via brktrdsvc — DeriveIndex path through the broker-facing gateway |
| 74 | `TestCashFlow_UnlockCash_HappyPath_ArbitrarySeed_Brktrd` | Same as #70 via brktrdsvc |

### EXIDS Lifecycle (Phase 10)

Covers the Phase 10 hardening surfaces — registry lifecycle states (`pending` / `committed` / `failed`), `IsSeedConsumed`, `MarkCommitted` / `MarkFailed`, `LookupBySagaInstance`, `EvictExpired` exemption rules, plus gateway-observable idempotent-retry / payload-conflict / failed-row-recycle behaviour through the live prtagent gRPC daemon. See `docs/TODO_EXECUTION_IDEMPOTENCY_SEED.md` Phase 10.

The direct-registry tests open `shared.exids_payload_registry` on `prtagent-postgres` and exercise the same `PgsqlPayloadRegistry` code the daemon uses; the gateway tests drive `cioTradingClient.CreateOrderAsync` end-to-end.

**Test File**: `tests/e2e/laser/exids_lifecycle_e2e_test.go`

#### Direct-Registry Lifecycle

| # | Test Function | Description |
|---|---|---|
| 41 | `TestEXIDS_Lifecycle_CheckOrRecord_FreshThenIdempotentRetry` | First call Fresh; second call (same payload) IdempotentRetry returning prior saga id |
| 42 | `TestEXIDS_Lifecycle_CheckOrRecord_PayloadConflict` | Same seed + different payload_hash → PayloadConflict, original row preserved |
| 43 | `TestEXIDS_Lifecycle_CheckOrRecord_RecyclesFailedRow` | `'failed'` row + new CheckOrRecord → recycled in-place to `'pending'`, returns Fresh |
| 44 | `TestEXIDS_Lifecycle_CheckOrRecord_CommittedSameHash_IdempotentRetry` | `'committed'` row + same payload → IdempotentRetry; state stays `'committed'` |
| 45 | `TestEXIDS_Lifecycle_CheckOrRecord_CommittedDifferentHash_PayloadConflict` | `'committed'` row + mutated payload → PayloadConflict; row untouched |
| 46 | `TestEXIDS_Lifecycle_IsSeedConsumed_OnlyCommittedReturnsTrue` | Pending and failed rows are NOT consumed; only committed returns true |
| 47 | `TestEXIDS_Lifecycle_MarkCommitted_AndMarkFailed_Idempotent` | Repeated MarkCommitted / MarkFailed calls converge; missing rows aren't created |
| 48 | `TestEXIDS_Lifecycle_LookupBySagaInstance` | Reverse-map saga_instance_id → (rpc, seed); empty / unknown ids return found=false |
| 49 | `TestEXIDS_Lifecycle_CrossRPCIsolation` | Same seed under two different rpc_name values yields two independent rows |
| 50 | `TestEXIDS_Lifecycle_EvictExpired_ExemptsCommittedAndFailed` | EvictExpired prunes abandoned `'pending'` only; committed + failed + paired-pending survive |

#### Gateway-Observable Lifecycle (via prtagent CreateOrderAsync)

| # | Test Function | Description |
|---|---|---|
| 51 | `TestEXIDS_Lifecycle_Gateway_IdempotentRetry_ReturnsSameSaga` | Two identical CIO submissions return the same saga_instance_id |
| 52 | `TestEXIDS_Lifecycle_Gateway_PayloadConflict_RejectsMutatedPayload` | Same seed + mutated quantity → codes.FailedPrecondition (EXIDS_PAYLOAD_CONFLICT) |
| 53 | `TestEXIDS_Lifecycle_Gateway_RecyclesFailedRow` | Pre-seeded `'failed'` row accepts the next CIO and pairs the new saga id in-place |
| 54 | `TestEXIDS_Lifecycle_Gateway_PreSeededCommittedSameHash_ShortCircuits` | Pre-seeded `'committed'` row + matching payload short-circuits to prior saga id |
| 55 | `TestEXIDS_Lifecycle_Gateway_PreSeededCommittedDifferentHash_PayloadConflict` | Pre-seeded `'committed'` row + mutated payload → FailedPrecondition; row stays committed |
| 56 | `TestEXIDS_Lifecycle_Gateway_RecordsSagaInstanceId` | Successful CIO writes back saga_instance_id; `LookupBySagaInstance` finds the row |

### Investor Event Stream Tests

Tests per-investor RabbitMQ event routing with exclusive auto-delete queues per session.

**Test File**: `tests/e2e/laser/investor_event_stream_test.go`

#### Green Path

| # | Test Function | Description |
|---|---|---|
| 15 | `TestInvestorEventStream_ReceiveSessionEstablished` | Subscribe with investor_account_iid, verify SESSION_ESTABLISHED event with session_iid |
| 16 | `TestInvestorEventStream_SubscribeAndReceiveOrderSubmitted` | Subscribe, call CreateOrderAsync, verify order_submitted event received |
| 17 | `TestInvestorEventStream_MultipleSubscribersSameInvestor` | Two streams for same investor both receive broadcast event |
| 18 | `TestInvestorEventStream_IsolationBetweenInvestors` | Investor A subscribes, order for B submitted, A gets nothing; order for A, A gets it |
| 19 | `TestInvestorEventStream_Heartbeat` | Subscribe, wait >20s, verify heartbeat received |
| 20 | `TestInvestorEventStream_ReceiveSagaStepNotifications` | Subscribe, submit order, wait for saga completion, verify step notifications with step_name and new_status |
| 21 | `TestInvestorEventStream_CancelSubmittedEvent` | Create order, subscribe, cancel order, verify cancel_submitted event with matching external_order_id |
| 22 | `TestInvestorEventStream_SessionIidPropagatedToSaga` | Subscribe, get session_iid, submit order with session_iid in aux_data, verify saga completes and order_submitted received |

#### Red Path

| # | Test Function | Description |
|---|---|---|
| 23 | `TestInvestorEventStream_MissingInvestorAccountIid` | Subscribe without investor_account_iid returns error |
| 24 | `TestInvestorEventStream_EmptyInvestorAccountIid` | Subscribe with empty string returns error |
| 25 | `TestInvestorEventStream_InvalidInvestorAccountIid` | Subscribe with nonexistent IID, subscription works, no events, heartbeats work |
| 26 | `TestInvestorEventStream_DisconnectCleansUpQueue` | Subscribe, disconnect, re-subscribe, verify new session works (old queue cleaned up) |
| 27 | `TestInvestorEventStream_CancelOrderLookupFails` | Cancel non-existent order, verify no cancel_submitted event published (lookup failed before publish) |

---

## Group 38: FIX Sender Report Delivery Tests

**Complexity**: ⭐⭐⭐⭐ HIGH

**Makefile Category**: Cat 38 (`make laser-e2e-ethbc-cat38`)

**Mode**: EthBC (requires Anvil blockchain for on-chain order/trade events)

**Description**: Tests the fixsender background job that polls tradeidxer for Execution Reports (35=8) and Trade Capture Reports (35=AE) and delivers them as FIX messages to connected sessions. Covers cursor persistence, reconnection resumption, own-side trade report filtering, and graceful degradation.

**Services Required**: postgres, redis, rabbitmq, anvil, lasersvc, traxcoord, traxctrl, accmgr, instrmgr, listingmgr, tradeidxer, fixreceiver, fixclient, lcmgr

**Test File**: `tests/e2e/laser/fixsender_test.go`

**Infrastructure**: Full exchange deployment with security listing, two FIX sessions (two participants), tradeidxer event indexing, fixreceiver with fixsender enabled.

### Green Path Tests

| # | Test Function | Description |
|---|---|---|
| 1 | `TestFixSender_ExecutionReport_Delivery` | Place order via FIX NOS, verify ExecutionReport (35=8) delivered to session |
| 2 | `TestFixSender_TradeReport_Delivery` | Two opposing orders match, verify TradeCaptureReport (35=AE) delivered to both sessions |
| 3 | `TestFixSender_CursorPersistence` | Verify cursor in DB matches last delivered report's created_at/iid |
| 4 | `TestFixSender_MultipleReports_InOrder` | Multiple orders, verify all ExecutionReports delivered in chronological order |
| 5 | `TestFixSender_TradeReport_OwnSideOnly` | Two participants trade, each gets only their own-side view |

### Red Path Tests

| # | Test Function | Description |
|---|---|---|
| 6 | `TestFixSender_SessionDrop_StopsJob` | Disconnect session, verify fixsender job stops polling |
| 7 | `TestFixSender_Reconnect_ResumesFromCursor` | Disconnect and reconnect, verify only new reports delivered |
| 8 | `TestFixSender_NoReports_NothingDelivered` | Connect with no orders, verify no FIX messages sent |
| 9 | `TestFixSender_TradeidxerUnavailable_GracefulRetry` | Start fixsender before tradeidxer ready, verify no crash |
| 10 | `TestFixSender_IdempotentRedelivery` | Reset cursor, verify all reports resent (receiver deduplicates) |

---

---

## Group 39: Treasury Indexer Tests

**Complexity**: ⭐⭐⭐⭐ HIGH

**Makefile Target**: `make laser-e2e-ethbc-cat39`

**Mode**: EthBC only (requires Anvil blockchain with deployed Trezor contracts)

**Files**:
- `tests/e2e/laser/treasidxer_test.go`

**Description**: Treasury Indexer daemon E2E tests. Verifies that `treasidxer` correctly discovers treasury mechanisms via AccMgr, polls Trezor ActivityStoreFacet via LASER query API, indexes activities into PostgreSQL, and that LASER result handlers create TREASURY_ERC20_VAULT_HOLDER/HOLDING slot links as a side effect.

**Dependencies**: treasidxer, lasersvc, lcmgr, accmgr, Anvil (Trezor contracts), PostgreSQL

### Test Functions

| # | Test Function | Complexity | Description |
|---|--------------|------------|-------------|
| 1 | `TestTreasIdxer_HealthCheck` | ⭐ | Verify health endpoint returns 200 OK |
| 2 | `TestTreasIdxer_DiscoversTreasuryDeployments` | ⭐⭐⭐ | Verify discovery of treasury mechanisms via AccMgr polling, check /status endpoint |
| 3 | `TestTreasIdxer_IndexesDepositActivity` | ⭐⭐⭐⭐ | Execute fund_account_with_cash_tokens saga, poll activities API until deposit (op=101) appears, verify fields |
| 4 | `TestTreasIdxer_IndexesWithdrawActivity` | ⭐⭐⭐⭐ | Fund account, execute withdrawal saga, verify withdrawal activity (op=102) indexed |
| 5 | `TestTreasIdxer_IndexesTransferVaultBalanceActivity` | ⭐⭐⭐⭐ | Fund account, execute vault transfer, verify transfer activity (op=107) with from/to vault fields |
| 6 | `TestTreasIdxer_ActivityQueryFilters` | ⭐⭐⭐ | Create multiple activities, verify filtering by operation, from_vault, contract_addr, from_ts/to_ts |
| 7 | `TestTreasIdxer_CursorResumption` | ⭐⭐⭐⭐ | Index activities, verify cursor state in DB, create more activities, verify no duplicates |
| 8 | `TestTreasIdxer_CrossDeploymentQuery` | ⭐⭐⭐ | Verify /all/activities returns activities from multiple deployments |
| 9 | `TestTreasIdxer_SlotLinksCreatedOnDeposit` | ⭐⭐⭐⭐ | Execute deposit, verify TREASURY_ERC20_VAULT_HOLDER and HOLDING slot links created via LASER links API |
| 10 | `TestTreasIdxer_SlotLinksIdempotent` | ⭐⭐⭐ | Fund same vault twice, verify only one pair of links exists |
| 11 | `TestTreasIdxer_NoTreasuryDeployment` | ⭐⭐ | Verify graceful behavior (empty jobs, no crash) when no treasury mechanisms exist |
| 12 | `TestTreasIdxer_InvalidDeploymentIid` | ⭐⭐ | Verify 404 for unknown deployment_iid in activities and status endpoints |
| 13 | `TestTreasIdxer_PaginationLimits` | ⭐⭐ | Verify default page size, page_size>500 cap, and page beyond total returns empty |
| 14 | `TestTreasIdxer_MissingRequiredArgs` | ⭐⭐ | Verify 404 for missing deployment_iid (route not found) |

---

---

## Category 40: Idempotent Treasury Vault Operations

**Complexity**: ⭐⭐⭐⭐
**Mode**: EthBC only
**Makefile Target**: `laser-e2e-ethbc-cat40`
**Test File**: `tests/e2e/laser/treasury_vault_idemp_test.go`

| # | Test | Complexity | Description |
|---|------|-----------|-------------|
| 1 | `TestTreasuryVaultIdempDeposit_GreenPath` | ⭐⭐⭐⭐ | Deposit via idempotent operation, verify vault balance |
| 2 | `TestTreasuryVaultIdempDeposit_KeyReuse` | ⭐⭐⭐⭐ | Verify no double-execution on idempotency key reuse |
| 3 | `TestTreasuryVaultIdempWithdraw_GreenPath` | ⭐⭐⭐⭐ | Withdraw via idempotent operation, verify balances |
| 4 | `TestTreasuryVaultIdempTransferFromVault_GreenPath` | ⭐⭐⭐⭐ | Inter-vault transfer via idempotent operation |
| 5 | `TestTreasuryVaultIdempTransferVaultBalance_GreenPath` | ⭐⭐⭐⭐ | Stash-aware transfer via idempotent operation |
| 6 | `TestTreasuryVaultDisabledDeposit_FailsWithError` | ⭐⭐⭐ | Disabled deposit returns DISABLED error |
| 7 | `TestTreasuryVaultDisabledWithdraw_FailsWithError` | ⭐⭐⭐ | Disabled withdraw returns DISABLED error |
| 8 | `TestTreasuryVaultDisabledTransfer_FailsWithError` | ⭐⭐⭐ | Disabled transfer returns DISABLED error |
| 9 | `TestTreasuryVaultDisabledTransferVaultBalance_FailsWithError` | ⭐⭐⭐ | Disabled transferBalance returns DISABLED error |
| 10 | `TestTreasuryVaultIdempDeposit_DifferentKeysAreIndependent` | ⭐⭐⭐⭐ | Different keys execute independently |
| 11 | `TestTreasuryDeployment_IncludesIdempFacet` | ⭐⭐⭐⭐ | Diamond has 8 vault facets including Erc20VaultIdempFacet |

**Prerequisites**: Full treasury infrastructure (E1/E2 executors, Lattice facets, legal structure, treasury mechanisms with Erc20VaultIdempFacet)

---

## Category 41: Expired Orders Flusher

**Complexity**: ⭐⭐⭐⭐
**Mode**: EthBC only
**Makefile Target**: `laser-e2e-ethbc-cat41`
**Test File**: `tests/e2e/laser/expired_orders_flusher_test.go`

| # | Test | Complexity | Description |
|---|------|-----------|-------------|
| 1 | `TestExpiredOrdersFlusher_StatusEndpoint` | ⭐⭐ | Verify flusher status endpoint returns correct shape |
| 2 | `TestExpiredOrdersFlusher_TriggerEndpoint` | ⭐⭐ | Verify trigger causes a flush cycle to complete |
| 3 | `TestExpiredOrdersFlusher_NoExpiredOrders` | ⭐⭐⭐⭐ | Create order with 1h expiry, trigger flusher, verify 0 cancelled |
| 4 | `TestExpiredOrdersFlusher_SingleExpiredOrder` | ⭐⭐⭐⭐ | Create order with 10s expiry, fast-forward Anvil 30s, verify cancellation |
| 5 | `TestExpiredOrdersFlusher_MultipleExpiredOrders` | ⭐⭐⭐⭐ | Create 3 orders with 10s expiry, fast-forward, verify all cancelled |

**Prerequisites**: Full CDO infrastructure (Diamond with AgoraEngine pair, clearing account, funded participants). Uses Anvil `evm_increaseTime` + `evm_mine` for time manipulation.

---

## Category 42: State Actuator Service (actusvc)

**Complexity**: ⭐⭐⭐⭐
**Mode**: EthBC only
**Makefile Target**: `laser-e2e-ethbc-cat42`
**Test Files**:
  - `tests/e2e/laser/actusvc_test.go`
  - `tests/e2e/laser/order_stash_unlock_on_rejection_test.go`

**Description**: Tests the actusvc daemon — post-submission order lifecycle manager that monitors FIX execution reports and triggers settlement actions. Verifies health/status endpoints, ERP polling, settlement saga submission, notification publishing, Redis deduplication, and end-to-end order-stash unlock on REJECTED ERPs.

| # | Test | Complexity | Description |
|---|------|-----------|-------------|
| 1 | `TestActusvc_Health` | ⭐⭐ | Verify health endpoint returns healthy status |
| 2 | `TestActusvc_Status` | ⭐⭐ | Verify status endpoint returns engine state and cycle count |
| 3 | `TestActusvc_Trigger` | ⭐⭐⭐ | Trigger manual poll cycle, verify cycle count increases |
| 4 | `TestActusvc_ERPPolling` | ⭐⭐⭐ | Trigger poll, verify ERP processing without errors |
| 5 | `TestActusvc_Dedup` | ⭐⭐⭐ | Trigger multiple polls, verify Redis dedup prevents reprocessing |
| 6 | `TestOrderStashUnlock_OnRejection_FullChain` | ⭐⭐⭐⭐ | Full chain: place LIMIT BUY, inject REJECTED ERP into `fixclient.execution_reports`, trigger actusvc, assert order flips to REJECTED and `hrer_unlock_order_stash` event log entry appears. Guards the divisibility-correct unlock fix (`docs/TODO_FIX_DIVISIBILITY_CORRECT_STASH_UNLOCK.md`). |
| 7 | `TestBuyFillSettlement_FullFill_StashDrainsToClearing` | ⭐⭐⭐⭐ | Full chain: place LIMIT BUY, assert stash N contains expected raw locked notional, inject FILLED ERP (ord_status='2', exec_type='F'), trigger actusvc, assert order flips to FILLED, `hffer_deposit_fill_proceeds` event log entry appears, stash N drains to `0`, and clearing LIQUID increases by the filled raw notional. Guards `docs/TODO_BUY_FILL_STASH_SETTLEMENT.md` (FIXBUYSET). |

**Prerequisites**: Full CDO infrastructure (Diamond with AgoraEngine pair, clearing account, funded participants, active orders). Requires fixclient with execution reports.

**Deferred** (follow-ups under Cat 42):
- Per-divisor variants (`Divisors_Sec0_Cur4`, `Sec2_Cur2`, `Sec2_Cur4`) — needs `deployCashTokenOnNamespace` to accept a `decimals` parameter. Especially relevant for the BUY-fill settlement variant since the divisibility-correct `fin.ComputeBuyLockAmountRaw` migration replaced the old buggy `computeFillValue` (which only worked when `security_divisor=0`).
- MARKET BUY rejection variant — needs an orderbook-seeding helper so tradeidxer's L1 returns a best-ask before the lock step runs.
- CANCELLED / EXPIRED / DONE_FOR_DAY variants — share the same shared-helper code path, mostly mechanical to add once the rejection variant is stable.
- BUY partial-fill variant (`TestBuyFillSettlement_PartialFill_FillValueToClearing`) — same TABT spawn, asserts only the filled-leg notional moved and the remainder stays in stash N. The state-machine change that routes BUY partial fills to `DEPOSIT_FILL_PROCEEDS` is exercised but not yet under direct assertion.

---

## Category 43: FIX Session Reliability V2 (FIXREL2)

**Complexity**: ⭐⭐⭐⭐
**Mode**: EthBC only
**Makefile Target**: `laser-e2e-ethbc-cat43`
**Test File**: `tests/e2e/laser/fixrel2_test.go`

**Description**: Covers the FIXREL2 hardening: gateway_inbox PossDup dedup (fixclient + fixreceiver), persistent fixsender_cursors upsert + monotonicity, fix_session_lock split-brain protection (Phase 7 lease library), and the dispatcher's retry/dead-letter state machine. Supersedes the spec'd-but-never-shipped V1 Cat 43.

Four scenarios are implemented and exercise the production code paths against the test DB; four are scaffolded with `t.Skip` because they need infrastructure that doesn't yet exist (docker-compose stop/start helper for fixclient/fixreceiver containers, and an in-process QuickFIX peer that can manipulate seqnums + craft Logon(141=Y)).

| # | Test | Complexity | Description |
|---|------|-----------|-------------|
| 1 | `TestFix_RestartFixclientResumesSeqnums` | ⭐⭐⭐⭐⭐ | **SKIPPED** — submit 10 NOS, kill fixclient mid-flow, restart, all 10 land at receiver exactly once. Needs docker-compose stop/start helper. |
| 2 | `TestFix_RestartFixreceiverDeliversBacklog` | ⭐⭐⭐⭐⭐ | **SKIPPED** — kill receiver while broker sends; restart; all NOS land at saga layer exactly once. Needs docker-compose stop/start helper. |
| 3 | `TestFix_PossDupExecutionReportSingleBooking` | ⭐⭐⭐⭐ | Insert ER twice with same `(session_id, msg_type, business_key)`; partial unique index drops the second; original row + flags survive. |
| 4 | `TestFix_ForceGapAndRecover` | ⭐⭐⭐⭐ | **SKIPPED** — manipulate peer's target seqnum, send next msg, assert ResendRequest + gap fill. Needs in-process QuickFIX peer. |
| 5 | `TestFix_FixsenderCursorResumes` | ⭐⭐⭐⭐ | Cursor table upsert semantics + monotonic counters; drop-copy and non-drop-copy variants coexist as separate rows under composite PK. |
| 6 | `TestFix_RejectUnscheduledResetSeqNumFlag` | ⭐⭐⭐ | **SKIPPED** — send Logon(141=Y) outside reset window, assert receiver rejects + Logouts. Needs in-process QuickFIX peer. |
| 7 | `TestFix_DuplicatePodLeaseRejection` | ⭐⭐⭐ | Two `FixSessionLease.Acquire` calls for same session_id; first wins; second errors with "held by"; lock table has exactly one row. |
| 8 | `TestFix_DispatcherFailsBusinessHandlerRetries` | ⭐⭐⭐ | Pending row tracked through 4 failed handler invocations; 5th attempt dead-letters by setting processed_at; partial pending index excludes the dead-lettered row. |

**Prerequisites**: FIXREL2 schemas applied (`init_fixclient_pgsql.sql` + `init_fixreceiver_pgsql.sql`). The implemented tests run against the test DB only — no Diamond / AgoraEngine / running daemons required. The skipped ones will need full CDO infrastructure plus the missing helpers.

**Source of truth**: `docs/TODO_FIX_SESSION_RELIABILITY_V2.md` Phase 9.

---

## Category 44: Cancel Direct Order

**Complexity**: ⭐⭐⭐⭐
**Mode**: EthBC (requires Anvil blockchain)
**Makefile Target**: `laser-e2e-ethbc-cat44`
**Test Pattern**: `TestCancelDirectOrder`

Tests the `cancel_direct_order` TRAX saga that cancels existing on-chain orders via `cancelExternallyIdentifiedDirectOrder`.

### Tests
| Test | Description |
|------|-------------|
| `TestCancelDirectOrder_LimitBid` | Cancel a limit BID order |
| `TestCancelDirectOrder_LimitAsk` | Cancel a limit ASK order |
| `TestCancelDirectOrder_PendingNewOrder` | Cancel order still in PENDING_NEW status |
| `TestCancelDirectOrder_Idempotent` | Same cancel with same idempotency_key is idempotent |
| `TestCancelDirectOrder_NonExistentOrder` | Cancel non-existent order returns 404 |
| `TestCancelDirectOrder_AlreadyCancelled` | Cancel already-cancelled order fails |
| `TestCancelDirectOrder_FilledOrder` | Cancel filled order fails |
| `TestCancelDirectOrder_MissingRequiredFields` | Missing fields return 400 |
| `TestCancelDirectOrder_ExpiredOrder` | Cancel expired order fails |

## Category 45: Cancel Investor Order

**Complexity**: ⭐⭐⭐⭐
**Mode**: EthBC (requires Anvil blockchain)
**Makefile Target**: `laser-e2e-ethbc-cat45`
**Test Pattern**: `TestCancelInvestorOrder`

Tests the `cancel_investor_order` TRAX saga that cancels existing investor orders via FIX OrderCancelRequest through fixclient.

### Tests
| Test | Description |
|------|-------------|
| `TestCancelInvestorOrder_SubmittedOrder` | Cancel a SUBMITTED investor order |
| `TestCancelInvestorOrder_NonExistentOrder` | Cancel non-existent order returns error |
| `TestCancelInvestorOrder_AlreadyCancelled` | Cancel already-cancelled order fails |
| `TestCancelInvestorOrder_MissingFields` | Missing external_order_id returns BAD_REQUEST |
| `TestCancelInvestorOrder_PreSubmittedOrder` | Cancel pre-submission order fails |

---

## Category 46: TRAX Saga Idempotency (EthBC)

**Complexity**: ⭐⭐⭐⭐ HIGH
**Mode**: EthBC (requires Anvil blockchain)
**Makefile Target**: `laser-e2e-ethbc-cat46`
**Test File**: `tests/e2e/laser/trax_idempotency_ethbc_test.go`

**Purpose**: Verify TRAX saga idempotency guarantees in the full LASER+TRAX stack with Anvil blockchain. Ensures no duplicate entities or on-chain operations occur when sagas are submitted with the same parameters or idempotency keys.

| Test | Description |
|------|-------------|
| `TestTraxIdempotency_SetupLegalParticipantDuplicate` | Submit setup_new_legal_participant twice with same participant IID but different idempotency keys. Verifies no duplicate participant is created. Second saga may succeed idempotently or compensate — both are acceptable. |
| `TestTraxIdempotency_SameSagaIdempotencyKey` | Submit same saga template twice with the SAME idempotency key. Verifies deduplication at either API or coordinator level — no duplicate saga execution. |

**Also in TRAX cat1a** (RDBMS mode, `tests/e2e/trax/idempotency_test.go`):

| Test | Description |
|------|-------------|
| `TestSagaSubmissionIdempotency` | Submit two sagas sequentially, verify both complete independently with distinct IDs |
| `TestSagaStepIdempotency` | Verify exactly 7 unique step instances after saga completion (no duplicates) |
| `TestSagaSubmissionIdempotency_ConcurrentSubmissions` | Submit 5 sagas concurrently, verify all 5 execute with unique IDs |
| `TestSagaSubmissionIdempotency_AfterCompensation` | Submit compensation saga, then re-submit same template — verify independent execution |

---

*Document generated: 2026-01-31, updated: 2026-03-23. Groups 26-27 added. Group 27 expanded to 10 tests. Group 29 added. Group 31 added (create_direct_order). Fund batch and funded CDO tests added. CDO tests expanded with comprehensive field verification, compensation cleanup, idempotency, market order, query endpoint, and BID+ASK matching tests. Group 32 added (FIX NewOrderSingle → saga integration). Group 33 added (FIX Client NOS Sending). Group 34 added (MarketMgr Order Relay + PrtAgent Integration). Group 35 added (Fund Account Command tests). Group 36 added (Trade Indexer). Group 37 added (Create Investor Order saga). Group 38 added (FIX Sender Report Delivery). Group 39 added (Treasury Indexer). Group 40 added (Idempotent Treasury Vault Operations). Group 41 added (Expired Orders Flusher). Group 42 added (State Actuator Service). Group 44 added (Cancel Direct Order). Group 37 expanded with Investor Event Stream tests. TRAX Cat1a expanded with 4 saga idempotency tests. Group 46 added (TRAX Idempotency EthBC).*
