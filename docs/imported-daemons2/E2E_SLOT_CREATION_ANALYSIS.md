# E2E Test Slot Creation Analysis

> **Generated**: 2026-02-23 (updated 2026-02-24)
> **Purpose**: Identify e2e tests that manually create slots which are also auto-created by sagas, affecting how we verify actual slot creation as part of saga execution.
> **Coverage**: ALL e2e test suites -- `tests/e2e/laser/` (Cat 1b-30), `tests/e2e/trax/` (Cat 1a), `tests/e2e/instrmgr/`, `tests/e2e/lcmgr/`, `tests/e2e/mq/`, `tests/e2e/csdadmui/`, `tests/e2e/common/`

---

## Table of Contents

1. [Sagas That Auto-Create Slots](#sagas-that-auto-create-slots)
2. [Tests With Overlapping Slot Creation](#tests-with-overlapping-slot-creation)
3. [Full Inventory by Category](#full-inventory-by-category)
4. [Helper Functions That Create Slots](#helper-functions-that-create-slots)
5. [Recommendations](#recommendations)

---

## Sagas That Auto-Create Slots

### Category A: Seeded Slot Creation via `CreateSeededSlotsForAll`

These sagas explicitly call `laserClient.CreateSeededSlotsForAll()` which creates seeded slots across **all registered executors** (E1 crown/ID, E2 lcmgr/SIGNERSVC, etc.) plus TRANSLATION slot_links between them.

| # | Saga | Step | Slot Seed Pattern | Tags | Notes |
|---|------|------|-------------------|------|-------|
| A1 | `activate_laser_slots_for_fin_object` | `create_laser_slots_for_fin_object` | `fin_entity_iid` (account IID) | nil | Also spawned by `onboard_new_investor` |
| A2 | `establish_new_legal_structure_for_participant` | `create_laser_slots_for_legal_structure_custody` | `custody_account_iid` | SIGNER | Only if `force_creation_of_custody_account == "true"` |
| A3 | `establish_new_legal_structure_for_participant` | `create_laser_slots_for_legal_structure_partners` | Each `partner_account_iid` | SIGNER | Iterates JSON array of partner account IIDs |
| A4 | `establish_new_legal_structure_for_participant` | `create_laser_slots_for_clearing_account` | `clearing_account_iid` | SIGNER | Clearing account slot for ERC20 approve |
| A5 | `create_custodian_sub_account` | `ccsa_create_laser_slots` | `account_iid` | nil | Sub-account slots (non-signer) |
| A6 | `new_investor_under_participant` | `niup_create_laser_slots_for_investor_account` | `account_iid` | nil | Investor account slots (non-signer) |
| A7 | `onboard_new_investor` | `oni_spawn_activate_laser_slots_saga` | `account_iid` via sub-saga A1 | nil | Spawns `activate_laser_slots_for_fin_object` |

### Category B: Slots Created via LASER Mutation Result Handlers

These sagas create slots **indirectly** by sending LASER mutations (deploy operations). The LASER result handlers (`DeployDiamondLcmgrResultHandler`, `DeployFacetLcmgrResultHandler`, etc.) automatically create slots for deployed contracts.

| # | Saga | Steps | Slot Pattern | Handler |
|---|------|-------|-------------|---------|
| B1 | `deploy_lattice_facets` | Each `deploy_*_facet` step | ETH addr + `FacetName:version` + `FacetName:latest` | `DeployFacetLcmgrResultHandler` |
| B2 | `deploy_core_legal_mechanisms` | `deploy_task_manager_contract`, `deploy_authz_diamond_contract` | ETH addr + symbolic name | `DeployTaskManagerV2LcmgrResultHandler`, `DeployAuthzDiamondLcmgrResultHandler` |
| B3 | `deploy_treasury_legal_mechanisms` | `deploy_trezor_diamond`, `deploy_rac_diamond` | ETH addr + `{prefix}-RAC`, `{prefix}-TreasuryDiamond` | `DeployDiamondLcmgrResultHandler` |
| B4 | `deploy_trading_legal_mechanisms` | `deploy_trading_engine_diamond` | ETH addr + symbolic | `DeployDiamondLcmgrResultHandler` |
| B5 | `deploy_cash_token_legal_mechanism` | `deploy_erc20_diamond` | ETH addr + `{prefix}-CashToken-{currency}` | `DeployErc20LcmgrResultHandler` |

---

## Tests With Overlapping Slot Creation

These are the **critical findings** -- tests that manually create slots which would also be auto-created by a saga run in the same test or related flow.

### HIGH IMPACT: Partner/Custody Slots Pre-Created Before Saga Would Create Them

#### 1. `legal_mechanism_deployment_test.go` -- `ensurePartnerSlotsExist()` [Cat 4]

**Overlap with:** Saga A3 (`establish_new_legal_structure` step `create_laser_slots_for_legal_structure_partners`)

The `ensurePartnerSlotsExist()` helper (line ~237) creates SIGNER slots for partner account IIDs. These same slots are what the `establish_new_legal_structure` saga's step 7 creates. The tests call this helper as a "safety net" after the establish saga runs, meaning the saga's slot creation is masked -- if the saga fails to create partner slots, the test would still pass because `ensurePartnerSlotsExist()` creates them.

**Affected tests (all Cat 4 `laser-e2e-ethbc-cat4`):**
- `TestDeployCoreLegalMechanisms_FullFlow`
- `TestDeployCoreLegalMechanisms_WithBypassMode`
- `TestDeployCoreLegalMechanisms_VerifyRoles`
- `TestDeployCoreLegalMechanisms_DuplicateMechanisms`
- `TestDeployCoreLegalMechanisms_InvalidLegalStructure`
- `TestDeployCoreLegalMechanisms_DeployerNotSigner`
- `TestDeployCoreLegalMechanisms_PartnerAccountNotActive`

**Slots affected:** Each test creates 3-5 partner SIGNER slots + 1 deployer SIGNER slot (seeds = partner account IIDs like `lm-test-partner1-full-1-account`).

#### 2. `deposit_to_treasury_test.go` -- `ensurePartnerSlotsExist()` [Cat 11]

**Overlap with:** Same as above (Saga A3).

**Affected tests (Cat 11 `laser-e2e-ethbc-cat11`):**
- `TestDepositToTreasury_APIRejectWhenMissingTreasuryMechanisms`
- `TestDepositToTreasury_APIRejectWhenMissingExecRuntime`

**Slots affected:** Partner SIGNER slots for partner account IIDs created by the establish saga.

#### 3. `cash_token_deployment_test.go` -- `createPartnerWithSignerAccount()` [Cat 7]

**Overlap with:** Saga A3 (`establish_new_legal_structure` partner slot creation)

The `createLegalStructureWithTreasuryForCashToken()` helper creates partner SIGNER slots via `createPartnerWithSignerAccount()`. If an establish saga was previously run to create the legal structure, these slots would already exist.

**Affected tests (Cat 7 `laser-e2e-ethbc-cat7`):** All `TestDeployCashToken_*` tests (8+ tests).

#### 4. `security_listing_deployment_test.go` -- Partner/deployer slot setup [Cat 27]

**Overlap with:** Saga A3 (partner slots)

`setupSSLGlobalInfra()` creates issuer deployer + exchange deployer SIGNER slots, plus partner slots through the legal structure setup chain.

**Affected tests (Cat 27 `laser-e2e-ethbc-cat27`):** All `TestSetupSecurityListing_*` tests.

#### 5. `indtrxss_common_test.go` -- Clearing account slot (line ~782) [Cat 3]

**Overlap with:** Saga A4 (`establish_new_legal_structure` step `create_laser_slots_for_clearing_account`)

Creates clearing account LASER slots programmatically via `service.CreateSeededSlotsForAllExecutorsWithTransaction()` with SIGNER tag. This is the same slot the establish saga's clearing account step would create.

**Affected tests (Cat 3 `laser-e2e-ethbc-cat3`):** All IndTrxSS tests that call `createClearingAccountForLegalStructure()`.

### MEDIUM IMPACT: Slots That Are Prerequisites But Could Overlap With Future Saga Expansion

#### 6. Fund account tests -- Destination account slots [Cat 1b / Cat 11]

**Overlap with:** Saga A1 (`activate_laser_slots_for_fin_object`)

`fund_account_saga_test.go` (Cat 1b) and `chain_verification_fundaccount_test.go` (Cat 11) create destination account slots via `lasercli slots create-seeded --seed=<accountIid>`. If the `activate_laser_slots_for_fin_object` saga runs for the same account IID before the test's manual creation, the manual creation would be redundant.

**Affected tests:**
- `TestFundAccountWithCashTokens_*` (Cat 1b `laser-e2e-ethbc-cat1`)
- `TestFundAccountWithCashTokens_OnChainVerification_*` (Cat 11 `laser-e2e-ethbc-cat11`)

---

## Full Inventory by Category

### Cat 1b: FundAccount Saga (EthBC) -- `laser-e2e-ethbc-cat1`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `fund_account_saga_test.go` | `TestFundAccountWithCashTokens_*` | Deployer SIGNER slot (`facwct-e2e-deployer-account`), destination account slot (dynamic seed) | **MEDIUM** -- destination slot overlaps A1 |

### Cat 2: Transfer & Issuance TRAX -- `laser-e2e-ethbc-cat2`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `authorization_trax_test.go` | `TestBasicInstrumentAuthorizationViaTRAX` | Deployer SIGNER, holder, 2 other accounts, instrument slot | No -- prerequisites |
| `authorization_trax_test.go` | `TestTRAXAuthorizationWithHoldingsVerification` | Same pattern | No -- prerequisites |
| `transfer_saga_trax_test.go` | `TestTRAXInstrumentTransferWithSaga` | Deployer SIGNER, holder, recipient, instrument slot | No -- prerequisites |
| `transfer_simple_trax_test.go` | `TestTRAXSimpleTransferWithTreasuryTracking` | Deployer SIGNER, holder, recipient, instrument slot | No -- prerequisites |
| `transfer_compensation_trax_test.go` | `TestTRAXTransferCompensationSequential` | Deployer SIGNER, holder, recipient, instrument slot | No -- prerequisites |
| `transfer_compensation_trax_test.go` | `TestTRAXTransferCompensationParallel` | Deployer SIGNER, holder, 3 recipients, instrument slot | No -- prerequisites |
| `transfer_holders_trax_test.go` | `TestTRAXSecurityHoldersConfirmation` | Deployer SIGNER, holder, 5 recipients, instrument slot | No -- prerequisites |
| `transfer_holders_trax_test.go` | `TestTRAXInstrumentMultiAccountTransfers` | Deployer SIGNER, holder, alice/bob/charlie, instrument slot | No -- prerequisites |
| `transfer_links_trax_test.go` | `TestTRAXTransferLinkManagement` | Deployer SIGNER, holder, 3 recipients, instrument slot | No -- prerequisites |
| `transfer_links_trax_test.go` | `TestTRAXTransferZeroBalanceLinkCleanup` | Deployer SIGNER, holder, recipient, instrument slot | No -- prerequisites |
| `distribution_trax_test.go` | `TestTRAXInstrumentIssuanceWithDistribution` | Deployer SIGNER, holder, 10 recipients, instrument slot | No -- prerequisites |
| `distribution_trax_test.go` | `TestTRAXInstrumentIssuanceWithDistributionParametrized` | Deployer SIGNER, holder, 10 recipients per sub-test, instrument slot | No -- prerequisites |
| `validation_trax_test.go` | `TestTRAXInstrumentEdgeCases` | Deployer SIGNER, holder, instrument, recipient slot | No -- prerequisites |
| `csdmsggw_balance_api_test.go` | `TestCsdMsgGw_AccountHoldings_TreasuryMode` | Deployer SIGNER, holder, instrument slot | No -- prerequisites |
| `csdmsggw_balance_api_test.go` | `TestCsdMsgGw_AccountHoldings_DirectMode` | Deployer SIGNER, holder, instrument slot | No -- prerequisites |
| `csdmsggw_balance_api_test.go` | `TestCsdMsgGw_AuthorizedInstrumentHolders_TreasuryMode` | Deployer SIGNER, holder, instrument slot | No -- prerequisites |
| `csdmsggw_balance_api_test.go` | `TestCsdMsgGw_AuthorizedInstrumentHolders_DirectMode` | Deployer SIGNER, holder, instrument slot | No -- prerequisites |
| `csdmsggw_balance_api_test.go` | `TestCsdMsgGw_AccountSubHoldings` | Deployer SIGNER, holder, instrument slot | No -- prerequisites |
| `authorize_security_test.go` | `TestAuthorizeSecurity_FullFlow` | Instrument slot (authorized instrument IID) | No -- prerequisite |
| `authorize_security_test.go` | `TestAuthorizeSecurity_CustomDecimals` | Instrument slot (authorized instrument IID) | No -- prerequisite |
| `authorize_security_test.go` | `TestAuthorizeSecurity_InvalidLegalStructure` | Instrument slot (authorized instrument IID) | No -- prerequisite |

### Cat 3: Individual Saga Steps (IndTrxSS) -- `laser-e2e-ethbc-cat3`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `indtrxss_common_test.go` | `createClearingAccountForLegalStructure()` | Clearing account SIGNER slot (programmatic) | **HIGH** -- overlaps A4 |
| `indtrxss_establish_legalstruct_step4_*` | Step 4 tests | Custody slots via `CreateSeededSlotsForAll` | N/A -- IS the saga step being tested |
| `indtrxss_establish_legalstruct_step7_*` | Step 7 tests | Partner slots via `CreateSeededSlotsForAll` | N/A -- IS the saga step being tested |

### Cat 4: Legal Mechanism Deployment -- `laser-e2e-ethbc-cat4`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `legal_mechanism_deployment_test.go` | `TestDeployCoreLegalMechanisms_FullFlow` | 4 partner SIGNER + 1 deployer SIGNER | **HIGH** -- partner slots overlap A3 |
| `legal_mechanism_deployment_test.go` | `TestDeployCoreLegalMechanisms_WithBypassMode` | 4 partner SIGNER + 1 deployer SIGNER | **HIGH** -- partner slots overlap A3 |
| `legal_mechanism_deployment_test.go` | `TestDeployCoreLegalMechanisms_VerifyRoles` | 5 partner SIGNER + 1 deployer SIGNER | **HIGH** -- partner slots overlap A3 |
| `legal_mechanism_deployment_test.go` | `TestDeployCoreLegalMechanisms_DuplicateMechanisms` | 4 partner SIGNER + 1 deployer SIGNER | **HIGH** -- partner slots overlap A3 |
| `legal_mechanism_deployment_test.go` | `TestDeployCoreLegalMechanisms_InvalidLegalStructure` | 4 partner SIGNER + 1 deployer SIGNER | **HIGH** -- partner slots overlap A3 |
| `legal_mechanism_deployment_test.go` | `TestDeployCoreLegalMechanisms_DeployerNotSigner` | 4 partner SIGNER + 1 deployer SIGNER + 1 non-signer | **HIGH** -- partner slots overlap A3 |
| `legal_mechanism_deployment_test.go` | `TestDeployCoreLegalMechanisms_PartnerAccountNotActive` | 3 partner SIGNER + 1 deployer SIGNER + 1 pending | **HIGH** -- partner slots overlap A3 |
| `legal_mechanism_deployment_test.go` | `TestDeployTreasuryLegalMechanisms_*` | Partner SIGNER + deployer SIGNER (same pattern) | **HIGH** -- partner slots overlap A3 |
| `legal_mechanism_deployment_test.go` | `TestDeployTradingLegalMechanisms_*` | Partner SIGNER + deployer SIGNER (same pattern) | **HIGH** -- partner slots overlap A3 |

### Cat 5: Diamond & Authorization -- `laser-e2e-ethbc-cat5`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `diamond_laser_test.go` | `TestDiamond_DeployViaLASER` | 1 deployer + 5 admin slots (SIGNER in EthBC) | No -- low-level LASER tests |
| `diamond_laser_test.go` | `TestDiamond_InitializeWithAuthzSource` | Same shared setup | No -- low-level LASER tests |
| `diamond_laser_test.go` | `TestDiamond_ComprehensiveFunctions` | Same shared setup | No -- low-level LASER tests |
| `authz_diamond_laser_test.go` | `TestAuthzDiamond_DeployViaLASER` | 1 deployer slot | No -- low-level LASER tests |
| `authz_diamond_laser_test.go` | `TestAuthzDiamond_DeployWithTaskManagerViaLASER` | 1 deployer slot | No -- low-level LASER tests |
| `authz_diamond_laser_test.go` | `TestAuthzDiamond_ComprehensiveFunctions` | 1 deployer slot | No -- low-level LASER tests |
| `deploy_all_facets_test.go` | `TestDeployLatticeFacets_AllFacets` | 1 deployer SIGNER | No -- prerequisite for facet saga |
| `deploy_all_facets_test.go` | `TestDeployLatticeFacets_CoreOnly` | 1 deployer SIGNER | No -- prerequisite for facet saga |
| `deploy_all_facets_test.go` | `TestDeployLatticeFacets_MinimalSet` | 1 deployer SIGNER | No -- prerequisite for facet saga |
| `deploy_all_facets_test.go` | `TestDeployLatticeFacets_VersionedSlots` | 1 deployer SIGNER | No -- prerequisite for facet saga |
| `deploy_all_facets_test.go` | `TestDeployLatticeFacets_OlderVersionNoUpdate` | 1 deployer SIGNER | No -- prerequisite for facet saga |
| `deploy_all_facets_test.go` | `TestDeployLatticeFacets_SelectiveDeployment` | 1 deployer SIGNER | No -- prerequisite for facet saga |

### Cat 6: ERC20 Token Operations -- `laser-e2e-ethbc-cat6`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `executor_erc20_operations_test.go` | `TestERC20ComprehensiveWorkflow` | 1 recipient slot | No -- prerequisite |
| `executor_erc20_errors_test.go` | `TestERC20TransferInsufficientBalance` | 1 recipient slot | No -- prerequisite |
| `executor_erc20_errors_test.go` | `TestERC20MintUnauthorized` | 1 unauthorized minter slot | No -- prerequisite |
| `executor_erc20_errors_test.go` | `TestERC20BurnFromNonBurnableContract` | 1 recipient slot | No -- prerequisite |
| `executor_erc20_queries_test.go` | `TestERC20AllOperationsSyncAsync` | 1 recipient + 1 spender | No -- prerequisites |
| `executor_erc20_approve_test.go` | `TestERC20ApproveAndTransferFrom` | 1 spender + 1 recipient | No -- prerequisites |
| `executor_erc20_approve_test.go` | `TestERC20TransferFromExceedingAllowance` | 1 spender + 1 recipient | No -- prerequisites |
| `executor_erc20_advanced_test.go` | `TestERC20ConcurrentTransfers` | 5 recipient slots | No -- prerequisites |
| `executor_erc20_advanced_test.go` | `TestERC20SlotLinkVerification` | 1 recipient slot | No -- prerequisite |
| `executor_erc20_decimals_test.go` | `TestERC20MultipleDecimalsWorkflow` | 1 recipient per sub-test | No -- prerequisites |

### Cat 7: Cash Token Deployment -- `laser-e2e-ethbc-cat7`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `cash_token_deployment_test.go` | All `TestDeployCashToken_*` (8+ tests) | 4 partner SIGNER + 1 deployer SIGNER per test | **HIGH** -- partner slots overlap A3 |

### Cat 8: PaCli -- `laser-e2e-cat8` / `laser-e2e-ethbc-cat8`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `pacli_test.go` | `deployFacetsForSagaTests` (helper) | 1 bootstrap deployer SIGNER (`pacli-bootstrap-deployer`) | No -- prerequisite for facet deployment |

### Cat 9: Legal Participant & Structure -- `laser-e2e-ethbc-cat9`

No manual slot creation. Slots are created internally by sagas (`setup_new_legal_participant`, `establish_new_legal_structure`, `onboard_new_investor`, `new_investor_under_participant`).

**Files verified (no slot creation):**
- `setup_new_legal_participant_test.go`
- `setup_new_custodian_participant_test.go`
- `setup_new_issuer_participant_test.go`
- `legal_participant_apikey_auth_test.go`
- `onboard_new_investor_trax_test.go`
- `new_investor_under_participant_trax_test.go`
- `configmgr_pls_test.go`

### Cat 10: Task Manager & Multi-Signer -- `laser-e2e-ethbc-cat10`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `taskmanagerv2_laser_test.go` | `TestTaskManagerV2LaserSlotSetup` | 5 role slots (admin, approver, creator, executor, finalizer) | No -- direct LASER tests |
| `taskmanagerv2_laser_test.go` | `TestTaskManagerV2LaserDeployAndQuery` | 1 deployer slot | No -- direct LASER tests |
| `taskmanagerv2_laser_test.go` | `TestTaskManagerV2LaserCreateTask` | 1 deployer slot | No -- direct LASER tests |
| `taskmanagerv2_multisigner_test.go` | `TestTaskManagerV2MultiSignerSetup` | 5 multi-signer slots (3 admin + 2 approver) | No -- direct LASER tests |
| `taskmanagerv2_multisigner_test.go` | `TestTaskManagerV2ThreeAdminDeploy` | 3 admin slots | No -- direct LASER tests |
| `taskmanagerv2_multisigner_test.go` | `TestTaskManagerV2MultiExecutorSetup` | 4 slots (2 per executor) | No -- direct LASER tests |

### Cat 11: Deposit & Treasury -- `laser-e2e-ethbc-cat11`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `chain_verification_fundaccount_test.go` | `TestFundAccountWithCashTokens_OnChainVerification_*` | Partner SIGNER + deployer + destination account slot | **MEDIUM** -- destination overlaps A1, partner slots overlap A3 |
| `deposit_to_treasury_test.go` | `TestDepositToTreasury_APIRejectWhenMissingTreasuryMechanisms` | Deployer + partner SIGNER via `ensurePartnerSlotsExist` | **HIGH** -- partner slots overlap A3 |
| `deposit_to_treasury_test.go` | `TestDepositToTreasury_APIRejectWhenMissingExecRuntime` | Deployer + partner SIGNER via `ensurePartnerSlotsExist` | **HIGH** -- partner slots overlap A3 |
| `treasury_vault_links_test.go` | `TestTreasuryVaultLinks_TransferCreatesAndRemovesLinks` | Holder SIGNER + recipient SIGNER | No -- prerequisites for vault ops |
| `treasury_vault_links_test.go` | `TestTreasuryVaultLinks_NoLinksForZeroDeposit` | 1 test slot (no deposit) | No -- prerequisite |
| `treasury_vault_withdraw_test.go` | `TestTreasuryVaultWithdraw_DifferentRecipient` | Holder SIGNER + 1 recipient | No -- prerequisites |
| `treasury_vault_withdraw_test.go` | `TestTreasuryVaultWithdraw_NonOwner` | Holder SIGNER + 1 attacker SIGNER | No -- prerequisites |

### Cat 12: Signer & Key Management -- `laser-e2e-ethbc-cat12`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `signer_tag_test.go` | `TestSignerTag_CreateSeededSlot_WithSignerTag` | 1 SIGNER slot | No -- unit-level LASER test |
| `signer_tag_test.go` | `TestSignerTag_CreateSeededSlot_WithoutSignerTag` | 1 normal slot | No -- unit-level LASER test |
| `signer_tag_test.go` | `TestSignerTag_Helper_CreateSeededSlotWithSignerTag` | 1 SIGNER slot | No -- unit-level LASER test |
| `signersvc_laser_test.go` | `TestSignerSvcLaserSeededSlots` | 3 slots + 1 idempotency | No -- unit-level LASER test |
| `signersvc_laser_test.go` | `TestSignerSvcLaserThreeSignersFundAndVerify` | 3 slots | No -- unit-level LASER test |
| `signersvc_laser_test.go` | `TestSignerSvcLaserServiceWide` | 1 service-wide slot | No -- unit-level LASER test |
| `signersvc_laser_test.go` | `TestSignerSvcLaserMixedAlgorithms` | 1 service-wide slot across 3 executors | No -- unit-level LASER test |
| `signersvc_laser_test.go` | `TestSignerSvcLaserSlotLinks` | 1 service-wide slot across 3 executors | No -- unit-level LASER test |

### Cat 13: Slot & Seeding -- `laser-e2e-cat13` / `laser-e2e-ethbc-cat13`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `executor_seeded_slots_test.go` | 10 tests (ID, SHA256_20, RND_20, RND_64, derive, immutability) | 1-2 per-executor slots per test | No -- unit-level slot CRUD |
| `service_seeded_slots_test.go` | 6 tests (all-created, idempotent, mixed, summary, disabled, slot-links) | 1 service-wide slot per test | No -- unit-level slot CRUD |

### Cat 14: External Call & Relay -- `laser-e2e-ethbc-cat14`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `executor_external_call_test.go` | Multiple tests | Deployer SIGNER + holder SIGNER per test | No -- prerequisites |
| `executor_relay_finalizer_test.go` | Multiple tests | 1 service-wide slot per test | No -- testing relay/finalizer behavior |

### Cat 15: Deploy Facets via TRAX -- `laser-e2e-ethbc-cat15`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `deploy_facets_trax_test.go` | `TestDeploySingleFacetViaTRAXSaga` | 1 deployer SIGNER | No -- prerequisite for facet saga |
| `deploy_facets_trax_test.go` | `TestDeployMinimalFacetsViaTRAXSaga` | 1 deployer SIGNER | No -- prerequisite for facet saga |
| `deploy_facets_trax_test.go` | `TestDeployCoreFacetsViaTRAXSaga` | 1 deployer SIGNER | No -- prerequisite for facet saga |

### Cat 16: Instrument Manager -- `laser-e2e-cat16`

No slot creation in instrmgr e2e tests.

### Cat 17: LASER Cross-Instance -- `laser-e2e-cat17`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `laser_cross_instance_test.go` | `TestLaserCrossInstance_DeployViaProxy` | 2 proxy slots (deployer + holder) | No -- testing LASER proxy |
| `laser_cross_instance_test.go` | `TestLaserCrossInstance_QueryViaProxy` | 3 proxy slots (deployer + holder + contract) | No -- testing LASER proxy |
| `laser_cross_instance_test.go` | `TestLaserCrossInstance_SlotCreation` | 1 proxy slot | No -- testing LASER proxy |

### Cat 18: Import & Data Migration -- `laser-e2e-ethbc-cat18`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `import_authorized_instrument_test.go` | `TestImportAuthorizedInstrumentViaSdmgr` | 1 instrument slot | No -- prerequisite for ERC20 Diamond |
| `import_authorized_instrument_test.go` | `TestImportCashTokenViaSdmgr` | 1 instrument slot | No -- prerequisite |
| `import_authorized_instrument_test.go` | `TestImportAuthorizedInstrumentDuplicate` | 1 instrument slot | No -- prerequisite |

### Cat 19: ERC20 Facet Routing -- `laser-e2e-cat19`

No slot creation.

### Cat 20: Executor CRUD -- `laser-e2e-cat20`

No slot creation (creates executors with derivation algorithms, not slots).

### Cat 21: Router CRUD -- `laser-e2e-cat21`

No slot creation.

### Cat 22: Execution Runtime CRUD -- `laser-e2e-cat22`

No slot creation.

### Cat 23: CSD Message Gateway REST -- `laser-e2e-cat23`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `csdmsggw_rest_api_test.go` | All tests | No slot creation | -- |
| `csdmsggw_custodian_rest_api_test.go` | All tests | No slot creation | -- |

### Cat 24: Smoke Tests -- `laser-e2e-cat24`

No slot creation.

### Cat 25: Config & Infrastructure -- `laser-e2e-cat25`

No slot creation.

### Cat 26: Listing Manager CRUD -- `laser-e2e-cat26`

No slot creation.

### Cat 27: Security Listing Deployment -- `laser-e2e-ethbc-cat27`

| File | Test | Slots Created | Saga Overlap? |
|------|------|---------------|---------------|
| `security_listing_deployment_test.go` | All `TestSetupSecurityListing_*` | Issuer deployer SIGNER + exchange deployer SIGNER + partner SIGNER via `setupSSLGlobalInfra()` | **HIGH** -- partner slots overlap A3 |

### Cat 28: Market Manager CRUD -- `laser-e2e-cat28`

No slot creation.

### Cat 29: FIX Security Definition -- `laser-e2e-ethbc-cat29`

No slot creation.

### Cat 30: PrtAgent -- `laser-e2e-cat30`

No slot creation.

---

### Non-Laser E2E Test Suites

These e2e test suites live outside `tests/e2e/laser/` and were also fully analysed. **None of them create any LASER slots.**

#### TRAX E2E (`tests/e2e/trax/`) -- `trax-e2e-full` (Cat 1a)

| File | Tests | Slot Creation? |
|------|-------|----------------|
| `compensation_test.go` | TRAX compensation sagas | No |
| `deep_sub_saga_test.go` | Deep sub-saga orchestration | No |
| `saga_hierarchy_test.go` | Saga hierarchy/parent-child | No |
| `seven_step_saga_test.go` | 7-step saga orchestration | No |
| `topology_test.go` | Saga topology tests | No |

These tests focus on TRAX saga orchestration mechanics (step ordering, compensation, hierarchy) and do not involve LASER slot creation at all.

#### Instrument Manager E2E (`tests/e2e/instrmgr/`) -- `instrmgr-e2e`

| File | Tests | Slot Creation? |
|------|-------|----------------|
| `instrument_authorization_saga_test.go` | Instrument authorization saga | No |

Tests instrument management workflows without LASER slot involvement.

#### LCMgr E2E (`tests/e2e/lcmgr/`)

No test files present.

#### MQ E2E (`tests/e2e/mq/`)

No test files present.

#### CSD Admin UI E2E (`tests/e2e/csdadmui/`)

No test files present.

#### Common E2E (`tests/e2e/common/`)

No test files present (shared utilities only).

---

## Helper Functions That Create Slots

| Helper | File | Method | Used By (Categories) |
|--------|------|--------|----------------------|
| `createSeededSlotWithSignerTag(t, seed)` | `erc20_helpers_test.go:769` | `lasercli slots create-seeded --seed=<seed> --tags=SLOT_LINK_TAG_ENUM_SIGNER` | Cat 4, 7, 11, 27 |
| `createSeededSlotWithTags(t, seed, tags)` | `erc20_helpers_test.go:781` | `lasercli slots create-seeded --seed=<seed> --tags=<tags>` | General purpose |
| `createPartnerWithSignerAccount(t, iid, name)` | `legal_mechanism_deployment_test.go:107` | Creates participant + account + calls `createSeededSlotWithSignerTag` | Cat 4, 7, 11, 27 |
| `createDeployerWithSignerAccount(t, iid)` | `legal_mechanism_deployment_test.go:163` | Delegates to `createPartnerWithSignerAccount` | Cat 4, 7, 11, 27 |
| `ensurePartnerSlotsExist(t, accountIids)` | `legal_mechanism_deployment_test.go:237` | Iterates + calls `createSeededSlotWithSignerTag` per account | Cat 4, 11 |
| `createSlotViaLasercli(t, iid, executorIid, addr)` | `e2e_helpers_test.go:862` | `lasercli slots create --iid=<iid> --executor-iid=<executorIid> --address=<addr>` | Rare direct creation |
| `createClearingAccountForLegalStructure(t, ...)` | `indtrxss_common_test.go:~770` | `service.CreateSeededSlotsForAllExecutorsWithTransaction()` (Go API) | Cat 3 |

---

## Recommendations

### Summary of HIGH-IMPACT Overlaps

| Category | Test File | Overlap Source | Saga | Impact |
|----------|-----------|---------------|------|--------|
| **Cat 3** | `indtrxss_common_test.go` | `createClearingAccountForLegalStructure()` | A4 (clearing slots) | Masks saga clearing slot creation |
| **Cat 4** | `legal_mechanism_deployment_test.go` (7+ tests) | `ensurePartnerSlotsExist()` | A3 (partner slots) | Masks saga partner slot creation |
| **Cat 7** | `cash_token_deployment_test.go` (8+ tests) | `createPartnerWithSignerAccount()` | A3 (partner slots) | Masks saga partner slot creation |
| **Cat 11** | `deposit_to_treasury_test.go` (2 tests) | `ensurePartnerSlotsExist()` | A3 (partner slots) | Masks saga partner slot creation |
| **Cat 11** | `chain_verification_fundaccount_test.go` | `createPartnerWithSignerAccount()` + destination slot | A1+A3 | Masks saga slot creation |
| **Cat 27** | `security_listing_deployment_test.go` (all tests) | `setupSSLGlobalInfra()` | A3 (partner slots) | Masks saga partner slot creation |

### MEDIUM-IMPACT Overlaps

| Category | Test File | Overlap Source | Saga | Impact |
|----------|-----------|---------------|------|--------|
| **Cat 1b** | `fund_account_saga_test.go` | Destination account slot | A1 (activate slots) | Possibly redundant if saga runs first |

### Suggested Actions

1. **For `ensurePartnerSlotsExist()` calls (Cat 4, 11)**: Consider removing this safety net and instead verifying that the `establish_new_legal_structure` saga created the partner slots as expected. If the saga fails, the test should fail.

2. **For `createPartnerWithSignerAccount()` in cash_token/security_listing tests (Cat 7, 27)**: These run the full establish saga flow first. The partner slot creation in setup may be redundant if the establish saga already ran. Verify whether the establish saga's step 7 actually executed, and if so, remove the manual creation.

3. **For IndTrxSS clearing account slot (Cat 3)**: This is intentional (testing individual steps in isolation), but be aware that it masks any issues with the saga's clearing account slot creation step.

4. **For fund account destination slots (Cat 1b)**: Verify whether `activate_laser_slots_for_fin_object` runs for the destination account before the manual `slots create-seeded`. If so, the manual creation is redundant.

5. **General principle**: When verifying saga-based slot creation, check that no helper function has already created the slot before the saga runs. Use `lasercli slots get` assertions AFTER the saga completes rather than relying on pre-created slots.
