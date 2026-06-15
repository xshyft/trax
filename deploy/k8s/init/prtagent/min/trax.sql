-- ============================================================================
-- PRTAGENT TRAX Saga Templates
-- ============================================================================
-- Purpose: TRAX saga templates for PRTAGENT (Participant Agent) namespace
-- Usage: ./deploy data min-records --cluster-id <cluster> --ns prtagent
--
-- Contains:
--   PRTAGENT-specific templates:
--     - new_account_under_participant (2 steps)
--     - enable_market_for_account (1 step)
--     - deposit_cash_into_account (3 steps)
--     - withdraw_cash_from_account (3 steps)
--     - new_investor_under_participant (7 steps)
--     - register_investor_at_depositories (2 steps)
--     - onboard_new_investor (3 steps, sub-saga wrapper)
--
--   FIX Execution Report handling sagas (actusvc → accmgr, 1 step each):
--     - handle_pending_new_fix_exec_report (OrdStatus A)
--     - handle_new_fix_exec_report (OrdStatus 0)
--     - handle_partial_fill_fix_exec_report (OrdStatus 1)
--     - handle_fill_fix_exec_report (OrdStatus 2)
--     - handle_done_for_day_fix_exec_report (OrdStatus 3)
--     - handle_cancel_fix_exec_report (OrdStatus 4)
--     - handle_rejected_fix_exec_report (OrdStatus 8)
--     - handle_expired_fix_exec_report (OrdStatus C)
--
--     - unlock_order_stash (1 step — unlocks stashed tokens on cancel/expire/reject)
--
--   Plus ALL CSD templates:
--     - process_new_instrument_authorization (6 steps)
--     - activate_laser_slots_for_fin_object (2 steps)
--     - transfer_authorized_instrument (2 steps)
--     - establish_new_legal_structure_for_participant (12 steps)
--     - deploy_core_legal_mechanisms_for_legal_structure (10 steps)
--     - deploy_treasury_legal_mechanisms_for_legal_structure (19 steps)
--     - deploy_trading_legal_mechanisms_for_legal_structure (9 steps)
--     - setup_new_legal_participant (8 steps)
--     - create_custodian_sub_account (5 steps)
--     - setup_security_listing (11 steps)
-- ============================================================================

\c agora_db;

-- ============================================================================
-- TRAX CLUSTER
-- ============================================================================

-- PRTAGENT Cluster - Participant Agent operations
INSERT INTO trax.clusters (id, display_name, description, labels, tags, metadata)
VALUES (
    'PRTAGENT',
    'PRTAGENT Cluster',
    'TRAX cluster for Participant Agent operations including broker operations and CSD functionality',
    '{"env": "local", "namespace": "prtagent"}'::jsonb,
    '["agora", "prtagent", "trax", "cluster", "broker"]'::jsonb,
    '{"created_by": "prtagent_min_init"}'::jsonb
)
ON CONFLICT (id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ############################################################################
-- ############################################################################
-- ##                                                                        ##
-- ##                    PRTAGENT-SPECIFIC SAGA TEMPLATES                    ##
-- ##                                                                        ##
-- ############################################################################
-- ############################################################################


-- ============================================================================
-- SAGA TEMPLATE: new_account_under_participant
-- ============================================================================
-- Description: Saga for creating a new account under one participant
-- Steps: 2
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'new_account_under_participant',
    'New Account Under Participant',
    'Saga for creating a new account under one participant',
    '{"short_id": "naup"}'::jsonb,
    '["agora", "prtagent", "broker", "saga", "participant", "account"]'::jsonb,
    '{}'::jsonb,
    '["create_new_record_for_account_in_store", "create_cash_entry_in_treasury"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: new_account_under_participant
-- ----------------------------------------------------------------------------

-- Step 1: Create New Record For Account In Store
-- Purpose: Create a new record for the account in the store
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_new_record_for_account_in_store',
    'new_account_under_participant',
    'Create New Record For Account In Store',
    'Step for creating a new record for the account in the store',
    '{"short_id": "cnrfis"}'::jsonb,
    '["agora", "broker", "step", "saga", "participant", "account"]'::jsonb,
    '{"index": "1", "generate_eth_account_address": "true"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Create Cash Entry In Treasury
-- Purpose: Create a cash entry in the treasury
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_cash_entry_in_treasury',
    'new_account_under_participant',
    'Create Cash Entry In Treasury',
    'Step for creating a cash entry in the treasury',
    '{"short_id": "cciet"}'::jsonb,
    '["agora", "prtagent", "broker", "step", "saga", "participant", "account", "treasury"]'::jsonb,
    '{"index": "2", "initial_balance": "0"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: enable_market_for_account
-- ============================================================================
-- Description: Saga for enabling market for a specific account
-- Steps: 1
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'enable_market_for_account',
    'Enable Market For Account',
    'Saga for enabling market for a specific account',
    '{"short_id": "emfa"}'::jsonb,
    '["agora", "prtagent", "broker", "saga", "market", "account"]'::jsonb,
    '{}'::jsonb,
    '["update_market_manager_to_include_account_for_market"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: enable_market_for_account
-- ----------------------------------------------------------------------------

-- Step 1: Update Market Manager To Include Account For Market
-- Purpose: Update the market manager to include the account for the market
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'update_market_manager_to_include_account_for_market',
    'enable_market_for_account',
    'Update Market Manager To Include Account For Market',
    'Step for updating the market manager to include the account for the market. The chosen market must exist already.',
    '{"short_id": "ummticam"}'::jsonb,
    '["agora", "prtagent", "broker", "step", "saga", "market", "account"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: deposit_cash_into_account
-- ============================================================================
-- Description: Saga for depositing cash into a specific account
-- Steps: 3
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'deposit_cash_into_account',
    'Deposit Cash Into Account',
    'Saga for depositing cash into a specific account',
    '{"short_id": "dcica"}'::jsonb,
    '["agora", "prtagent", "broker", "saga", "account", "deposit", "cash", "asset"]'::jsonb,
    '{}'::jsonb,
    '["mint_cash_tokens_in_treasury", "transfer_minted_cash_to_account", "update_ledger_with_the_deposited_amount"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: deposit_cash_into_account
-- ----------------------------------------------------------------------------

-- Step 1: Mint Cash Tokens In Treasury
-- Purpose: Mint cash tokens in the treasury
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'mint_cash_tokens_in_treasury',
    'deposit_cash_into_account',
    'Mint Cash Tokens In Treasury',
    'Step for minting cash tokens in the treasury',
    '{"short_id": "mctit"}'::jsonb,
    '["agora", "broker", "step", "saga", "asset", "cash", "account"]'::jsonb,
    '{"index": "1", "currency": "USD"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Transfer Minted Cash To Account
-- Purpose: Transfer minted cash to a specific account
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'transfer_minted_cash_to_account',
    'deposit_cash_into_account',
    'Transfer Minted Cash To Account',
    'Step for transferring minted cash to a specific account',
    '{"short_id": "tmcta"}'::jsonb,
    '["agora", "prtagent", "broker", "step", "saga", "participant", "account", "treasury"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Update Ledger With The Deposited Amount
-- Purpose: Update the ledger with the deposited amount
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'update_ledger_with_the_deposited_amount',
    'deposit_cash_into_account',
    'Update Ledger With The Deposited Amount',
    'Step for updating the ledger with the deposited amount',
    '{"short_id": "ulwdta"}'::jsonb,
    '["agora", "prtagent", "broker", "step", "saga", "participant", "account", "treasury", "ledger", "cash", "asset"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: withdraw_cash_from_account
-- ============================================================================
-- Description: Saga for withdrawing cash from a specific account
-- Steps: 3
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'withdraw_cash_from_account',
    'Withdraw Cash From Account',
    'Saga for withdrawing cash from a specific account',
    '{"short_id": "wcfa"}'::jsonb,
    '["agora", "prtagent", "broker", "saga", "account", "cash", "asset", "withdraw"]'::jsonb,
    '{}'::jsonb,
    '["transfer_cash_from_account", "burn_cash_tokens_and_remove_from_treasury", "withdraw_update_ledger_with_amount"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: withdraw_cash_from_account
-- ----------------------------------------------------------------------------

-- Step 1: Transfer Cash From Account
-- Purpose: Transfer cash from a specific account
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'transfer_cash_from_account',
    'withdraw_cash_from_account',
    'Transfer Cash From Account',
    'Step for transferring cash from a specific account',
    '{"short_id": "tcfa"}'::jsonb,
    '["agora", "prtagent", "broker", "step", "saga", "participant", "account", "treasury"]'::jsonb,
    '{"index": "1", "currency": "USD"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Burn Cash Tokens And Remove From Treasury
-- Purpose: Burn cash tokens and remove from the treasury
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'burn_cash_tokens_and_remove_from_treasury',
    'withdraw_cash_from_account',
    'Burn Cash Tokens And Remove From Treasury',
    'Step for burning cash tokens and removing from the treasury',
    '{"short_id": "bctft"}'::jsonb,
    '["agora", "broker", "step", "saga", "asset", "cash", "account"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Update Ledger With The Withdrawn Amount
-- Note: Using different template_id than deposit to avoid conflict
-- Purpose: Update the ledger with the withdrawn amount
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'withdraw_update_ledger_with_amount',
    'withdraw_cash_from_account',
    'Update Ledger With The Withdrawn Amount',
    'Step for updating the ledger with the withdrawn amount',
    '{"short_id": "wulwa"}'::jsonb,
    '["agora", "prtagent", "broker", "step", "saga", "participant", "account", "treasury", "ledger", "cash", "asset"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: new_investor_under_participant
-- ============================================================================
-- Description: TRAX saga for creating a new investor under a participant
--              (broker), including investor record, relations, account with
--              LASER slots, and ETH address attachment
-- Steps: 7
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'new_investor_under_participant',
    'New Investor Under Participant',
    'TRAX saga for creating a new investor under a participant (broker), including investor record, relations, account with LASER slots, and ETH address attachment',
    '{"short_id": "niup"}'::jsonb,
    '["agora", "prtagent", "saga", "workflow", "investor", "participant", "account", "laser", "eth-address", "trax-flow"]'::jsonb,
    '{}'::jsonb,
    '["niup_verify_new_investor_inputs", "niup_create_investor_record", "niup_create_participant_to_investor_relation", "niup_create_account_for_investor", "niup_create_laser_slots_for_investor_account", "niup_attach_eth_address_to_investor_account", "niup_create_investor_to_account_relation"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: new_investor_under_participant
-- ----------------------------------------------------------------------------

-- Step 1: Verify New Investor Inputs
-- Service: accmgr
-- Purpose: Validate that participant exists, external_investor_id is unique for
--          this participant, and all required fields are provided.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'niup_verify_new_investor_inputs',
    'new_investor_under_participant',
    'Verify New Investor Inputs',
    'Validate that participant exists, external_investor_id is unique for this participant, and all required fields are provided.',
    '{"short_id": "niup_s1", "service": "accmgr"}'::jsonb,
    '["agora", "prtagent", "saga", "step", "investor", "validation", "participant", "workflow"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Create Investor Record
-- Service: accmgr
-- Purpose: Create the Investor entity in accmgr with provided or auto-generated
--          IID, external_investor_id, types, status, and metadata.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'niup_create_investor_record',
    'new_investor_under_participant',
    'Create Investor Record',
    'Create the Investor entity in accmgr with provided or auto-generated IID, external_investor_id, types, status, and metadata.',
    '{"short_id": "niup_s2", "service": "accmgr"}'::jsonb,
    '["agora", "prtagent", "saga", "step", "investor", "create", "entity", "workflow"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Create Participant-to-Investor Relation
-- Service: accmgr
-- Purpose: Create ParticipantToInvestorRelation linking the owner participant
--          to the newly created investor with MEMBER_INVESTOR relation type.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'niup_create_participant_to_investor_relation',
    'new_investor_under_participant',
    'Create Participant-to-Investor Relation',
    'Create ParticipantToInvestorRelation linking the owner participant to the newly created investor with MEMBER_INVESTOR relation type.',
    '{"short_id": "niup_s3", "service": "accmgr"}'::jsonb,
    '["agora", "prtagent", "saga", "step", "investor", "relation", "participant", "workflow"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 4: Create Account for Investor
-- Service: accmgr
-- Purpose: Create Account with types [CLIENT, INVESTOR_HOLDING], external_account_id
--          derived from investor IID, and PENDING status.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'niup_create_account_for_investor',
    'new_investor_under_participant',
    'Create Account for Investor',
    'Create Account with types [CLIENT, INVESTOR_HOLDING], external_account_id derived from investor IID, and PENDING status.',
    '{"short_id": "niup_s4", "service": "accmgr"}'::jsonb,
    '["agora", "prtagent", "saga", "step", "investor", "account", "create", "workflow"]'::jsonb,
    '{"index": "4"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 5: Create LASER Slots for Investor Account
-- Service: lasersvc
-- Purpose: Create LASER slots for the investor account. Slots are created with
--          nil tags (non-SIGNER) as accounts don't sign transactions.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'niup_create_laser_slots_for_investor_account',
    'new_investor_under_participant',
    'Create LASER Slots for Investor Account',
    'Create LASER slots for the investor account. Slots are created with nil tags (non-SIGNER) as accounts don''t sign transactions.',
    '{"short_id": "niup_s5", "service": "lasersvc"}'::jsonb,
    '["agora", "prtagent", "saga", "step", "investor", "laser", "slots", "workflow"]'::jsonb,
    '{"index": "5"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 6: Attach ETH Address to Investor Account
-- Service: accmgr
-- Purpose: Attach the LASER-generated ETH address to the account as an identifier
--          and set account status to ACTIVE.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'niup_attach_eth_address_to_investor_account',
    'new_investor_under_participant',
    'Attach ETH Address to Investor Account',
    'Attach the LASER-generated ETH address to the account as an identifier and set account status to ACTIVE.',
    '{"short_id": "niup_s6", "service": "accmgr"}'::jsonb,
    '["agora", "prtagent", "saga", "step", "investor", "account", "eth-address", "identifier", "workflow"]'::jsonb,
    '{"index": "6"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 7: Create Investor-to-Account Relation
-- Service: accmgr
-- Purpose: Create InvestorToAccountRelation linking the investor to their account
--          with OWNER relation type.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'niup_create_investor_to_account_relation',
    'new_investor_under_participant',
    'Create Investor-to-Account Relation',
    'Create InvestorToAccountRelation linking the investor to their account with OWNER relation type.',
    '{"short_id": "niup_s7", "service": "accmgr"}'::jsonb,
    '["agora", "prtagent", "saga", "step", "investor", "account", "relation", "ownership", "workflow"]'::jsonb,
    '{"index": "7"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: handle_pending_new_fix_exec_report
-- ============================================================================
-- Description: Handle FIX execution report with OrdStatus A (PENDING_NEW)
-- Steps: 1 (finalize)
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
) VALUES (
    'handle_pending_new_fix_exec_report',
    'Handle PENDING_NEW FIX Exec Report',
    'Processes a PENDING_NEW (OrdStatus A) execution report: appends event log, keeps SUBMITTED status',
    '{"short_id": "hpner"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "pending-new"]'::jsonb,
    '{}'::jsonb,
    '["hpner_finalize"]'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name, description = EXCLUDED.description,
    labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'hpner_finalize', 'handle_pending_new_fix_exec_report',
    'Finalize PENDING_NEW Exec Report',
    'Update order request status, append event log, mark exec report done',
    '{"short_id": "hpner_fin"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "finalize"]'::jsonb,
    '{"index": "1"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: handle_new_fix_exec_report
-- ============================================================================
-- Description: Handle FIX execution report with OrdStatus 0 (NEW)
-- Steps: 1 (finalize)
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
) VALUES (
    'handle_new_fix_exec_report',
    'Handle NEW FIX Exec Report',
    'Processes a NEW (OrdStatus 0) execution report: transitions order to ACCEPTED, appends event log',
    '{"short_id": "hner"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "new"]'::jsonb,
    '{}'::jsonb,
    '["hner_finalize"]'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name, description = EXCLUDED.description,
    labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'hner_finalize', 'handle_new_fix_exec_report',
    'Finalize NEW Exec Report',
    'Update order request status to ACCEPTED, append event log, mark exec report done',
    '{"short_id": "hner_fin"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "finalize"]'::jsonb,
    '{"index": "1"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: handle_partial_fill_fix_exec_report
-- ============================================================================
-- Description: Handle FIX execution report with OrdStatus 1 (PARTIALLY_FILLED)
-- Steps: 2 (deposit_fill_proceeds for SELL, finalize)
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
) VALUES (
    'handle_partial_fill_fix_exec_report',
    'Handle PARTIAL_FILL FIX Exec Report',
    'Processes a PARTIALLY_FILLED (OrdStatus 1) execution report: deposits fill proceeds (SELL), transitions to PARTIALLY_FILLED',
    '{"short_id": "hpfer"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "partial-fill"]'::jsonb,
    '{}'::jsonb,
    '["hpfer_deposit_fill_proceeds", "hpfer_finalize"]'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name, description = EXCLUDED.description,
    labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'hpfer_deposit_fill_proceeds', 'handle_partial_fill_fix_exec_report',
    'Deposit Fill Proceeds',
    'Deposit cash proceeds to seller investor account (SELL side only, skipped for BUY). Amount = last_qty * last_px',
    '{"short_id": "hpfer_dfp"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "settlement", "deposit"]'::jsonb,
    '{"index": "1"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'hpfer_finalize', 'handle_partial_fill_fix_exec_report',
    'Finalize PARTIAL_FILL Exec Report',
    'Update order request status to PARTIALLY_FILLED, persist cum_qty, append event log, mark exec report done',
    '{"short_id": "hpfer_fin"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "finalize"]'::jsonb,
    '{"index": "2"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: handle_fill_fix_exec_report
-- ============================================================================
-- Description: Handle FIX execution report with OrdStatus 2 (FILLED)
-- Steps: 3 (deposit_fill_proceeds, unlock_order_stash, finalize)
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
) VALUES (
    'handle_fill_fix_exec_report',
    'Handle FILL FIX Exec Report',
    'Processes a FILLED (OrdStatus 2) execution report: deposits fill proceeds (SELL), unlocks order stash, transitions to COMPLETED',
    '{"short_id": "hffer"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "fill"]'::jsonb,
    '{}'::jsonb,
    '["hffer_deposit_fill_proceeds", "hffer_unlock_order_stash", "hffer_finalize"]'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name, description = EXCLUDED.description,
    labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'hffer_deposit_fill_proceeds', 'handle_fill_fix_exec_report',
    'Deposit Fill Proceeds',
    'Deposit final fill cash proceeds to seller investor account (SELL side). Amount = last_qty * last_px',
    '{"short_id": "hffer_dfp"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "settlement", "deposit"]'::jsonb,
    '{"index": "1"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'hffer_unlock_order_stash', 'handle_fill_fix_exec_report',
    'Unlock Order Stash',
    'Unlock remaining locked tokens from order stash N to stash 0',
    '{"short_id": "hffer_uos"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "settlement", "unlock"]'::jsonb,
    '{"index": "2"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'hffer_finalize', 'handle_fill_fix_exec_report',
    'Finalize FILL Exec Report',
    'Update order request status to COMPLETED, persist final cum_qty, append event log, mark exec report done',
    '{"short_id": "hffer_fin"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "finalize"]'::jsonb,
    '{"index": "3"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: handle_done_for_day_fix_exec_report
-- ============================================================================
-- Description: Handle FIX execution report with OrdStatus 3 (DONE_FOR_DAY)
-- Steps: 3 (unlock_order_stash, return_fee, finalize)
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
) VALUES (
    'handle_done_for_day_fix_exec_report',
    'Handle DONE_FOR_DAY FIX Exec Report',
    'Processes a DONE_FOR_DAY (OrdStatus 3) execution report: unlocks order stash, returns fee, transitions to COMPENSATED',
    '{"short_id": "hdfer"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "done-for-day"]'::jsonb,
    '{}'::jsonb,
    '["hdfer_unlock_order_stash", "hdfer_return_fee", "hdfer_finalize"]'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name, description = EXCLUDED.description,
    labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'hdfer_unlock_order_stash', 'handle_done_for_day_fix_exec_report',
    'Unlock Order Stash',
    'Unlock remaining locked tokens from order stash N to stash 0',
    '{"short_id": "hdfer_uos"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "settlement", "unlock"]'::jsonb,
    '{"index": "1"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'hdfer_return_fee', 'handle_done_for_day_fix_exec_report',
    'Return Fee',
    'Return fee from clearing account to investor account via fund_account_with_cash_tokens',
    '{"short_id": "hdfer_rf"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "settlement", "fee-return"]'::jsonb,
    '{"index": "2"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'hdfer_finalize', 'handle_done_for_day_fix_exec_report',
    'Finalize DONE_FOR_DAY Exec Report',
    'Update order request status to COMPENSATED, append event log, mark exec report done',
    '{"short_id": "hdfer_fin"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "finalize"]'::jsonb,
    '{"index": "3"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: handle_cancel_fix_exec_report
-- ============================================================================
-- Description: Handle FIX execution report with OrdStatus 4 (CANCELLED)
-- Steps: 3 (unlock_order_stash, return_fee, finalize)
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
) VALUES (
    'handle_cancel_fix_exec_report',
    'Handle CANCEL FIX Exec Report',
    'Processes a CANCELLED (OrdStatus 4) execution report: unlocks order stash, returns fee, transitions to COMPENSATED',
    '{"short_id": "hcer"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "cancel"]'::jsonb,
    '{}'::jsonb,
    '["hcer_unlock_order_stash", "hcer_return_fee", "hcer_finalize"]'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name, description = EXCLUDED.description,
    labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'hcer_unlock_order_stash', 'handle_cancel_fix_exec_report',
    'Unlock Order Stash',
    'Unlock remaining locked tokens from order stash N to stash 0',
    '{"short_id": "hcer_uos"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "settlement", "unlock"]'::jsonb,
    '{"index": "1"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'hcer_return_fee', 'handle_cancel_fix_exec_report',
    'Return Fee',
    'Return fee from clearing account to investor account via fund_account_with_cash_tokens',
    '{"short_id": "hcer_rf"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "settlement", "fee-return"]'::jsonb,
    '{"index": "2"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'hcer_finalize', 'handle_cancel_fix_exec_report',
    'Finalize CANCEL Exec Report',
    'Update order request status to COMPENSATED, append event log, mark exec report done',
    '{"short_id": "hcer_fin"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "finalize"]'::jsonb,
    '{"index": "3"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: handle_cancel_rejected_fix_exec_report
-- ============================================================================
-- Description: Handle CANCEL_REJECTED FIX execution report (OrdStatus 8 with orig_cl_ord_id)
-- Steps: 1 (finalize only — no unlock/return-fee since original order is still active)
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
) VALUES (
    'handle_cancel_rejected_fix_exec_report',
    'Handle Cancel Rejected FIX Exec Report',
    'Processes a cancel rejection (OrdStatus 8 with orig_cl_ord_id): transitions order to CancelRejected (retryable)',
    '{"short_id": "hcrr"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "cancel-rejected"]'::jsonb,
    '{}'::jsonb,
    '["hcrr_finalize"]'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name, description = EXCLUDED.description,
    labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'hcrr_finalize', 'handle_cancel_rejected_fix_exec_report',
    'Finalize Cancel Rejected Exec Report',
    'Update order request status to CancelRejected, append event log, mark exec report done',
    '{"short_id": "hcrr_fin"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "cancel-rejected", "finalize"]'::jsonb,
    '{"index": "1"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: handle_rejected_fix_exec_report
-- ============================================================================
-- Description: Handle FIX execution report with OrdStatus 8 (REJECTED)
-- Steps: 3 (unlock_order_stash, return_fee, finalize)
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
) VALUES (
    'handle_rejected_fix_exec_report',
    'Handle REJECTED FIX Exec Report',
    'Processes a REJECTED (OrdStatus 8) execution report: unlocks order stash, returns fee, transitions to REJECTED',
    '{"short_id": "hrer"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "rejected"]'::jsonb,
    '{}'::jsonb,
    '["hrer_unlock_order_stash", "hrer_return_fee", "hrer_finalize"]'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name, description = EXCLUDED.description,
    labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'hrer_unlock_order_stash', 'handle_rejected_fix_exec_report',
    'Unlock Order Stash',
    'Unlock remaining locked tokens from order stash N to stash 0',
    '{"short_id": "hrer_uos"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "settlement", "unlock"]'::jsonb,
    '{"index": "1"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'hrer_return_fee', 'handle_rejected_fix_exec_report',
    'Return Fee',
    'Return fee from clearing account to investor account via fund_account_with_cash_tokens',
    '{"short_id": "hrer_rf"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "settlement", "fee-return"]'::jsonb,
    '{"index": "2"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'hrer_finalize', 'handle_rejected_fix_exec_report',
    'Finalize REJECTED Exec Report',
    'Update order request status to REJECTED, append event log, mark exec report done',
    '{"short_id": "hrer_fin"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "finalize"]'::jsonb,
    '{"index": "3"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: handle_expired_fix_exec_report
-- ============================================================================
-- Description: Handle FIX execution report with OrdStatus C (EXPIRED)
-- Steps: 3 (unlock_order_stash, return_fee, finalize)
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
) VALUES (
    'handle_expired_fix_exec_report',
    'Handle EXPIRED FIX Exec Report',
    'Processes an EXPIRED (OrdStatus C) execution report: unlocks order stash, returns fee, transitions to COMPENSATED',
    '{"short_id": "heer"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "expired"]'::jsonb,
    '{}'::jsonb,
    '["heer_unlock_order_stash", "heer_return_fee", "heer_finalize"]'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name, description = EXCLUDED.description,
    labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'heer_unlock_order_stash', 'handle_expired_fix_exec_report',
    'Unlock Order Stash',
    'Unlock remaining locked tokens from order stash N to stash 0',
    '{"short_id": "heer_uos"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "settlement", "unlock"]'::jsonb,
    '{"index": "1"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'heer_return_fee', 'handle_expired_fix_exec_report',
    'Return Fee',
    'Return fee from clearing account to investor account via fund_account_with_cash_tokens',
    '{"short_id": "heer_rf"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "settlement", "fee-return"]'::jsonb,
    '{"index": "2"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
) VALUES (
    'heer_finalize', 'handle_expired_fix_exec_report',
    'Finalize EXPIRED Exec Report',
    'Update order request status to COMPENSATED, append event log, mark exec report done',
    '{"short_id": "heer_fin"}'::jsonb,
    '["agora", "actusvc", "fix", "exec-report", "finalize"]'::jsonb,
    '{"index": "3"}'::jsonb
) ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name,
    description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ############################################################################
-- ############################################################################
-- ##                                                                        ##
-- ##                          CSD SAGA TEMPLATES                            ##
-- ##                (Included for prtagent namespace)                       ##
-- ##                                                                        ##
-- ############################################################################
-- ############################################################################


-- ============================================================================
-- SAGA TEMPLATE: process_new_instrument_authorization
-- ============================================================================
-- Description: TRAX flow for processing new instrument authorization using
--              Diamond+Facet pattern. Deploys Diamond, adds LaserErc20Facet,
--              initializes token, deposits to treasury, and creates record.
-- Steps: 8
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'process_new_instrument_authorization',
    'Process New Instrument Authorization',
    'TRAX flow for processing new instrument authorization using Diamond+Facet pattern',
    '{"short_id": "pnia"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "instrument", "authorize", "trax-flow", "diamond", "facet"]'::jsonb,
    '{}'::jsonb,
    '["pnia_deploy_erc20_diamond", "pnia_initialize_erc20_diamond", "pnia_grant_add_laser_erc20_facet_permission", "pnia_add_laser_erc20_facet", "pnia_grant_initialize_laser_erc20_permission", "pnia_initialize_laser_erc20", "pnia_approve_treasury_for_deposit", "pnia_deposit_initial_supply_to_treasury", "pnia_create_authorized_instrument_record", "pnia_amend_vault_link_metadata", "pnia_claim_authz_instr_erc20_diamond_via_metadata"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: process_new_instrument_authorization
-- ----------------------------------------------------------------------------

-- Step 1: Deploy ERC20 Diamond
-- Service: lasersvc
-- Purpose: Deploy Diamond contract for authorized instrument via LASER.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'pnia_deploy_erc20_diamond',
    'process_new_instrument_authorization',
    'Deploy ERC20 Diamond',
    'Deploy Diamond contract for authorized instrument via LASER using deployer signer. Contract name = {prefix}-Instrument-{isin}. Returns instrument_diamond_contract_address.',
    '{"short_id": "pnia_s1", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "step", "instrument", "diamond", "deploy", "laser"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Initialize ERC20 Diamond
-- Service: lasersvc
-- Purpose: Initialize Diamond with TaskManager, AuthzSource references.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'pnia_initialize_erc20_diamond',
    'process_new_instrument_authorization',
    'Initialize ERC20 Diamond',
    'Initialize Diamond with TaskManager reference, AuthzSource, and AuthzDomain="Instrument". Uses deployer as signer.',
    '{"short_id": "pnia_s2", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "initialize", "instrument", "diamond", "laser"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Grant Add LaserErc20Facet Permission
-- Service: lasersvc
-- Purpose: authz_admin grants addFacets permission to admin_partner on Instrument Diamond.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'pnia_grant_add_laser_erc20_facet_permission',
    'process_new_instrument_authorization',
    'Grant Add LaserErc20Facet Permission',
    'authz_admin grants addFacets(address[]) permission to admin_partner on Instrument Diamond via SimpleAuthzAddAccount.',
    '{"short_id": "pnia_s3", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "step", "instrument", "permission", "grant", "add-facets", "laser"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 4: Add LaserErc20Facet to Diamond
-- Service: lasersvc
-- Purpose: admin_partner adds LaserErc20Facet to Instrument Diamond.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'pnia_add_laser_erc20_facet',
    'process_new_instrument_authorization',
    'Add LaserErc20Facet to Diamond',
    'admin_partner adds LaserErc20Facet (from lattice using laser_erc20_facet_version) to Instrument Diamond via DiamondAddFacets.',
    '{"short_id": "pnia_s4", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "step", "instrument", "facet", "add", "diamond", "laser", "erc20"]'::jsonb,
    '{"index": "4"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 5: Grant Initialize LaserErc20 Permission
-- Service: lasersvc
-- Purpose: authz_admin grants initialize permission to admin_partner on Instrument Diamond.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'pnia_grant_initialize_laser_erc20_permission',
    'process_new_instrument_authorization',
    'Grant Initialize LaserErc20 Permission',
    'authz_admin grants initialize permission to admin_partner on Instrument Diamond via SimpleAuthzAddAccount.',
    '{"short_id": "pnia_s5", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "step", "instrument", "permission", "grant", "initialize", "laser"]'::jsonb,
    '{"index": "5"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 6: Initialize LaserErc20
-- Service: lasersvc
-- Purpose: Initialize ERC20 token with instrument name, symbol, and decimals.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'pnia_initialize_laser_erc20',
    'process_new_instrument_authorization',
    'Initialize LaserErc20',
    'Initialize ERC20 token with name={instrument_name}, symbol={isin}, decimals=0 (for securities) via LaserErc20FacetInitialize.',
    '{"short_id": "pnia_s6", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "step", "instrument", "erc20", "initialize", "laser"]'::jsonb,
    '{"index": "6"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 7: Approve Treasury for Deposit
-- Service: laseragent
-- Purpose: Clearing account approves treasury vault to spend tokens.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'pnia_approve_treasury_for_deposit',
    'process_new_instrument_authorization',
    'Approve Treasury for Deposit',
    'Clearing account approves treasury vault to spend authz_initial_units of ERC20 tokens via ExecutorErc20Approve.',
    '{"short_id": "pnia_s7", "service": "laseragent"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "step", "erc20", "approve", "treasury", "clearing", "laser"]'::jsonb,
    '{"index": "7"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 8: Deposit Initial Supply to Treasury
-- Service: laseragent
-- Purpose: Deposit initial supply to treasury via TrezorErc20DepositToVault.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'pnia_deposit_initial_supply_to_treasury',
    'process_new_instrument_authorization',
    'Deposit Initial Supply to Treasury',
    'Deposit authz_initial_units tokens from clearing account to treasury vault via TrezorErc20DepositToVault.',
    '{"short_id": "pnia_s8", "service": "laseragent"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "step", "treasury", "deposit", "initial", "supply", "laser"]'::jsonb,
    '{"index": "8"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 9: Create Authorized Instrument Record
-- Service: instrmgr
-- Purpose: Create AuthorizedInstrument record in instrmgr.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'pnia_create_authorized_instrument_record',
    'process_new_instrument_authorization',
    'Create Authorized Instrument Record',
    'Create AuthorizedInstrument record in instrmgr with isin, contract_address, legal_structure_iid.',
    '{"short_id": "pnia_s9", "service": "instrmgr"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "step", "authorization", "instrument", "record", "instrmgr"]'::jsonb,
    '{"index": "9"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 10: Amend Vault Link Metadata
-- Service: laseragent
-- Purpose: Amend treasury vault link metadata with authorized_instrument_iid from previous step.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'pnia_amend_vault_link_metadata',
    'process_new_instrument_authorization',
    'Amend Vault Link Metadata',
    'Amend treasury vault link metadata with authorized_instrument_iid after create_authorized_instrument_record completes.',
    '{"short_id": "pnia_s10", "service": "laseragent"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "step", "vault", "link", "metadata", "amend", "laser"]'::jsonb,
    '{"index": "10"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 11: Claim AuthzInstr ERC20 Diamond via Metadata
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'pnia_claim_authz_instr_erc20_diamond_via_metadata',
    'process_new_instrument_authorization',
    'Claim AuthzInstr ERC20 Diamond via Metadata',
    'Stamp the authorized_instrument_iid into the authz-instr''s own ERC20 Diamond inner slot metadata so the treasury indexer can resolve activities emitted by the authz-instr''s contract back to the authz-instr iid. Per-authz-instr slot — no shared-claim conflict. ref_seed is left untouched (immutable in lasersvc).',
    '{"short_id": "pnia_s11", "service": "laseragent"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "step", "treasury", "diamond", "metadata", "claim", "laser"]'::jsonb,
    '{"index": "11"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: activate_laser_slots_for_fin_object
-- ============================================================================
-- Description: Workflow for activating the LASER slots for a financial object
-- Steps: 2
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'activate_laser_slots_for_fin_object',
    'Activate LASER Slots for Financial Object',
    'Workflow for activating the LASER slots for a financial object',
    '{"short_id": "alfsfo"}'::jsonb,
    '["agora", "csd", "saga", "laser", "slot", "ethereum", "workflow", "public", "address", "financial", "object", "activation"]'::jsonb,
    '{}'::jsonb,
    '["create_laser_slots_for_fin_object", "attach_eth_address_to_fin_object_metadata"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: activate_laser_slots_for_fin_object
-- ----------------------------------------------------------------------------

-- Step 1: Create LASER Slots
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_laser_slots_for_fin_object',
    'activate_laser_slots_for_fin_object',
    'Create LASER Slots',
    'Step for creating LASER Slots.',
    '{"short_id": "clsffo"}'::jsonb,
    '["agora", "csd", "saga", "step", "laser", "slot", "public", "address", "allocate", "ethereum", "financial", "object", "workflow"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Attach Ethereum Address to Financial Object Metadata
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'attach_eth_address_to_fin_object_metadata',
    'activate_laser_slots_for_fin_object',
    'Attach Ethereum Address to Financial Object Metadata',
    'Step for attaching the Ethereum address to the financial object''s metadata.',
    '{"short_id": "aeafom"}'::jsonb,
    '["agora", "csd", "saga", "step", "laser", "slot", "public", "address", "update", "financial", "object", "ethereum", "authorize", "workflow"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: transfer_authorized_instrument
-- ============================================================================
-- Description: TRAX flow for transferring authorized instruments between accounts
-- Steps: 2
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'transfer_authorized_instrument',
    'Transfer Authorized Instrument',
    'TRAX flow for transferring authorized instruments between accounts',
    '{"short_id": "tai"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "instrument", "transfer", "trax-flow"]'::jsonb,
    '{}'::jsonb,
    '["transfer_tokens", "validate_balances_after_transfer"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: transfer_authorized_instrument
-- ----------------------------------------------------------------------------

-- Step 1: Transfer Tokens
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'transfer_tokens',
    'transfer_authorized_instrument',
    'Transfer Tokens',
    'Step for transferring tokens from one account to another.',
    '{"short_id": "tt"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "step", "instrument", "transfer", "tokens"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Validate Balances After Transfer
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'validate_balances_after_transfer',
    'transfer_authorized_instrument',
    'Validate Balances After Transfer',
    'Step for validating account balances after the transfer is complete.',
    '{"short_id": "vbat"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "step", "validate", "balance", "transfer"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: establish_new_legal_structure_for_participant
-- ============================================================================
-- Description: TRAX flow for establishing a new legal structure (PARTNERSHIP)
--              for a participant with owner account, partner accounts, and
--              clearing account
-- Steps: 11
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'establish_new_legal_structure_for_participant',
    'Establish New Legal Structure for Participant',
    'TRAX flow for establishing a new legal structure (PARTNERSHIP) for a participant with custody account, partner accounts, and clearing account',
    '{"short_id": "enlsfp"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "legal-structure", "partnership", "participant", "account", "laser", "trax-flow", "clearing-account"]'::jsonb,
    '{}'::jsonb,
    '["verify_new_legal_structure_inputs", "create_legal_structure_record", "create_custody_account_for_legal_structure", "create_laser_slots_for_legal_structure_custody", "attach_eth_address_to_legal_structure_custody_account", "create_accounts_for_legal_structure_partners", "create_laser_slots_for_legal_structure_partners", "attach_eth_addresses_to_legal_structure_partner_accounts", "create_clearing_account_for_legal_structure", "create_laser_slots_for_clearing_account", "attach_eth_address_to_clearing_account", "create_participant_to_legal_structure_relations"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: establish_new_legal_structure_for_participant
-- ----------------------------------------------------------------------------

-- Step 1: Verify New Legal Structure Inputs
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'verify_new_legal_structure_inputs',
    'establish_new_legal_structure_for_participant',
    'Verify New Legal Structure Inputs',
    'Validate inputs, verify participants exist and are enabled.',
    '{"short_id": "vnlsi", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-structure", "verify", "validate", "participant", "workflow"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Create Legal Structure Record
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_legal_structure_record',
    'establish_new_legal_structure_for_participant',
    'Create Legal Structure Record',
    'Create LegalStructure and ParticipantList records.',
    '{"short_id": "clsr", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-structure", "create", "participant-list", "record", "workflow"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Create Custody Account for Legal Structure
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_custody_account_for_legal_structure',
    'establish_new_legal_structure_for_participant',
    'Create Custody Account for Legal Structure',
    'Create custody account and legal-structure-to-account relation.',
    '{"short_id": "ccafls", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-structure", "account", "custody", "create", "relation", "workflow"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 4: Create LASER Slots for Legal Structure Custody Account
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_laser_slots_for_legal_structure_custody',
    'establish_new_legal_structure_for_participant',
    'Create LASER Slots for Legal Structure Custody Account',
    'Create non-SIGNER LASER slots for custody account.',
    '{"short_id": "clsflsc", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-structure", "laser", "slot", "custody", "ethereum", "workflow"]'::jsonb,
    '{"index": "4"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 5: Attach ETH Address to Legal Structure Custody Account
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'attach_eth_address_to_legal_structure_custody_account',
    'establish_new_legal_structure_for_participant',
    'Attach ETH Address to Legal Structure Custody Account',
    'Attach ETH address to custody account and set status to ACTIVE.',
    '{"short_id": "aeatca", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-structure", "attach", "ethereum", "address", "custody", "activate", "workflow"]'::jsonb,
    '{"index": "5"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 6: Create Accounts for Legal Structure Partners
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_accounts_for_legal_structure_partners',
    'establish_new_legal_structure_for_participant',
    'Create Accounts for Legal Structure Partners',
    'Create accounts and relations for all partner participants.',
    '{"short_id": "caflsp", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-structure", "account", "partner", "create", "batch", "relation", "workflow"]'::jsonb,
    '{"index": "6"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 7: Create LASER Slots for Legal Structure Partners
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_laser_slots_for_legal_structure_partners',
    'establish_new_legal_structure_for_participant',
    'Create LASER Slots for Legal Structure Partners',
    'Create SIGNER-tagged LASER slots for all partner accounts.',
    '{"short_id": "clsflsp", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-structure", "laser", "slot", "partner", "signer", "ethereum", "workflow"]'::jsonb,
    '{"index": "7"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 8: Attach ETH Addresses to Legal Structure Partner Accounts
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'attach_eth_addresses_to_legal_structure_partner_accounts',
    'establish_new_legal_structure_for_participant',
    'Attach ETH Addresses to Legal Structure Partner Accounts',
    'Attach ETH addresses to partner accounts and set status to ACTIVE.',
    '{"short_id": "aeatpa", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-structure", "attach", "ethereum", "address", "partner", "activate", "batch", "workflow"]'::jsonb,
    '{"index": "8"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 9: Create Clearing Account for Legal Structure
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_clearing_account_for_legal_structure',
    'establish_new_legal_structure_for_participant',
    'Create Clearing Account for Legal Structure',
    'Create clearing account and LegalStructureToAccountRelation for the legal structure itself.',
    '{"short_id": "ccafls", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-structure", "account", "clearing", "create", "relation", "workflow"]'::jsonb,
    '{"index": "9"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 10: Create LASER Slots for Clearing Account
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_laser_slots_for_clearing_account',
    'establish_new_legal_structure_for_participant',
    'Create LASER Slots for Clearing Account',
    'Create SIGNER-tagged LASER slots for clearing account.',
    '{"short_id": "clsfca", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-structure", "laser", "slot", "clearing", "ethereum", "workflow"]'::jsonb,
    '{"index": "10"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 11: Attach ETH Address to Clearing Account
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'attach_eth_address_to_clearing_account',
    'establish_new_legal_structure_for_participant',
    'Attach ETH Address to Clearing Account',
    'Attach ETH address to clearing account and set status to ACTIVE.',
    '{"short_id": "aeatca", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-structure", "attach", "ethereum", "address", "clearing", "activate", "workflow"]'::jsonb,
    '{"index": "11"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 12: Create Participant-to-Legal-Structure Relations
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('create_participant_to_legal_structure_relations', 'establish_new_legal_structure_for_participant', 'Create Participant-to-Legal-Structure Relations', 'Persist typed participant↔legal-structure roles (CEO, BOARD_MEMBER, COMPLIANCE_OFFICER, …) declared on each partner. No-op when no partner declared a relation.', '{"short_id": "cptlsr", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-structure", "participant", "relation", "role", "workflow"]'::jsonb, '{"index": "12"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: deploy_core_legal_mechanisms_for_legal_structure
-- ============================================================================
-- Description: TRAX flow for deploying governance mechanisms (TaskManagerV2
--              and AuthzDiamond) for an existing legal structure (PARTNERSHIP).
--              EthBC-only.
-- Steps: 10
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'deploy_core_legal_mechanisms_for_legal_structure',
    'Deploy Core Legal Mechanisms for Legal Structure',
    'TRAX flow for deploying governance mechanisms (TaskManagerV2 and AuthzDiamond) for an existing legal structure (PARTNERSHIP). EthBC-only.',
    '{"short_id": "dclmfls"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "legal-mechanism", "legal-structure", "task-manager", "authz-diamond", "laser", "governance", "ethereum", "trax-flow"]'::jsonb,
    '{}'::jsonb,
    '["verify_legal_mechanism_inputs", "create_task_manager_legal_mechanism", "create_authz_source_legal_mechanism", "deploy_task_manager_contract", "create_task_manager_deployment_record", "deploy_authz_diamond_contract", "create_authz_source_deployment_record", "initialize_authz_diamond", "add_authz_facet_to_diamond", "assign_partner_roles"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: deploy_core_legal_mechanisms_for_legal_structure
-- ----------------------------------------------------------------------------

-- Step 1: Verify Legal Mechanism Inputs
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'verify_legal_mechanism_inputs',
    'deploy_core_legal_mechanisms_for_legal_structure',
    'Verify Legal Mechanism Inputs',
    'Validate inputs, verify legal structure exists and is PARTNERSHIP type, verify deployer and all partner accounts have SIGNER slots, verify authz_source_diamond_admins and authz_admins have no overlap.',
    '{"short_id": "vlmi", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "verify", "validate", "signer", "partnership", "workflow"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Create TaskManager Legal Mechanism
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_task_manager_legal_mechanism',
    'deploy_core_legal_mechanisms_for_legal_structure',
    'Create TaskManager Legal Mechanism',
    'Create LegalMechanism record with type=VOTING, LegalStructureIid, and DisplayNames using prefix+locale. Store slot_address = {prefix}-TaskManager in metadata.',
    '{"short_id": "ctmlm", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "task-manager", "voting", "create", "record", "workflow"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Create AuthzSource Legal Mechanism
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_authz_source_legal_mechanism',
    'deploy_core_legal_mechanisms_for_legal_structure',
    'Create AuthzSource Legal Mechanism',
    'Create LegalMechanism record with type=AUTHORISATION_SOURCE, LegalStructureIid. Store slot_address = {prefix}-AuthzSource in metadata.',
    '{"short_id": "caslm", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "authz-source", "authorisation", "create", "record", "workflow"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 4: Deploy TaskManager Contract
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_task_manager_contract',
    'deploy_core_legal_mechanisms_for_legal_structure',
    'Deploy TaskManager Contract',
    'Deploy TaskManagerV2 via LASER using deployer signer. All partners are admins, approvers, and executors. Returns task_manager_contract_address.',
    '{"short_id": "dtmc", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "task-manager", "deploy", "laser", "ethereum", "contract", "workflow"]'::jsonb,
    '{"index": "4"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 5: Create TaskManager Deployment Record
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_task_manager_deployment_record',
    'deploy_core_legal_mechanisms_for_legal_structure',
    'Create TaskManager Deployment Record',
    'Create LegalMechanismDeployment with type=LASER, linking to TaskManager mechanism, with contract address from step 4.',
    '{"short_id": "ctmdr", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "task-manager", "deployment", "record", "laser", "workflow"]'::jsonb,
    '{"index": "5"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 6: Deploy AuthzDiamond Contract
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_authz_diamond_contract',
    'deploy_core_legal_mechanisms_for_legal_structure',
    'Deploy AuthzDiamond Contract',
    'Deploy AuthzDiamond via LASER using deployer signer. Returns authz_diamond_contract_address.',
    '{"short_id": "dadc", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "authz-diamond", "deploy", "laser", "ethereum", "contract", "workflow"]'::jsonb,
    '{"index": "6"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 7: Create AuthzSource Deployment Record
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_authz_source_deployment_record',
    'deploy_core_legal_mechanisms_for_legal_structure',
    'Create AuthzSource Deployment Record',
    'Create LegalMechanismDeployment with type=LASER, linking to AuthzSource mechanism, with contract address from step 6.',
    '{"short_id": "casdr", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "authz-source", "deployment", "record", "laser", "workflow"]'::jsonb,
    '{"index": "7"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 8: Initialize AuthzDiamond
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'initialize_authz_diamond',
    'deploy_core_legal_mechanisms_for_legal_structure',
    'Initialize AuthzDiamond',
    'Initialize AuthzDiamond with TaskManager reference, authz_source_diamond_admins, and authz_admins. Uses deployer as signer.',
    '{"short_id": "iad", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "authz-diamond", "initialize", "laser", "ethereum", "workflow"]'::jsonb,
    '{"index": "8"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 9: Add AuthzFacet to Diamond
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'add_authz_facet_to_diamond',
    'deploy_core_legal_mechanisms_for_legal_structure',
    'Add AuthzFacet to Diamond',
    'Add AuthzFacet to AuthzDiamond using first authz_source_diamond_admin as signer. Returns add_facet_tx_hash.',
    '{"short_id": "aaftd", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "authz-facet", "diamond", "add", "laser", "ethereum", "workflow"]'::jsonb,
    '{"index": "9"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 10: Assign Partner Roles
-- Service: accmgr
-- Purpose: Assign roles (TaskManagerAdmin, AuthzAdmin, Deployer, etc.) to partner
--          LegalStructureToAccountRelation records based on role arrays from saga input.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'assign_partner_roles',
    'deploy_core_legal_mechanisms_for_legal_structure',
    'Assign Partner Roles',
    'Assign roles (TaskManagerAdmin, AuthzAdmin, Deployer, etc.) to partner LegalStructureToAccountRelation records. Maps role arrays to matching partner relations and updates their metadata.',
    '{"short_id": "apr", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "partner", "roles", "assign", "workflow"]'::jsonb,
    '{"index": "10"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: deploy_treasury_legal_mechanisms_for_legal_structure
-- ============================================================================
-- Description: TRAX flow for deploying Treasury governance mechanisms
--              (RAC Diamond and Trezor Diamond) for an existing legal structure
--              that already has Core Legal Mechanisms deployed. EthBC-only.
-- Steps: 19
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Deploy Treasury Legal Mechanisms for Legal Structure',
    'TRAX flow for deploying Treasury governance mechanisms (RAC Diamond and Trezor Diamond) for an existing legal structure that already has Core Legal Mechanisms deployed. EthBC-only.',
    '{"short_id": "dtlmfls"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "legal-mechanism", "legal-structure", "rac", "trezor", "treasury", "laser", "governance", "ethereum", "trax-flow", "diamond"]'::jsonb,
    '{}'::jsonb,
    '["verify_treasury_mechanism_inputs", "create_rac_legal_mechanism", "create_treasury_legal_mechanism", "deploy_rac_diamond_contract", "initialize_rac_diamond", "grant_add_facets_permission_to_admin_rac", "add_rac_facet_to_rac_diamond", "create_rac_deployment_record", "deploy_trezor_diamond_contract", "initialize_trezor_diamond", "grant_add_facets_permission_to_admin_trezor", "add_vault_facets_to_trezor_diamond", "grant_create_ledger_permission", "create_default_ledger", "grant_set_address_permission", "grant_set_int_permission", "configure_rac_properties", "grant_treasury_rac_access", "create_treasury_deployment_record"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: deploy_treasury_legal_mechanisms_for_legal_structure
-- ----------------------------------------------------------------------------

-- Step 1: Verify Treasury Mechanism Inputs
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'verify_treasury_mechanism_inputs',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Verify Treasury Mechanism Inputs',
    'Validate inputs, verify Core Legal Mechanisms exist, verify no Treasury mechanisms exist, verify admin_partner is partner + TM admin, verify authz_admin is AuthzDiamond admin, verify deployer has SIGNER slot.',
    '{"short_id": "vtmi", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "verify", "validate", "treasury", "rac", "trezor", "workflow"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Create RAC Legal Mechanism
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_rac_legal_mechanism',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Create RAC Legal Mechanism',
    'Create LegalMechanism record with type=RESOURCE_ACCESS_CONTROLLER, LegalStructureIid. Store slot_address = {prefix}-RAC in metadata.',
    '{"short_id": "crlm", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "rac", "resource-access-controller", "create", "record", "workflow"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Create Treasury Legal Mechanism
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_treasury_legal_mechanism',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Create Treasury Legal Mechanism',
    'Create LegalMechanism record with type=TREASURY, LegalStructureIid. Store slot_address = {prefix}-Trezor in metadata.',
    '{"short_id": "ctlm", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "treasury", "trezor", "create", "record", "workflow"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 4: Deploy RAC Diamond Contract
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_rac_diamond_contract',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Deploy RAC Diamond Contract',
    'Deploy RAC Diamond via LASER using deployer signer. Contract name = {prefix}-RAC. Returns rac_diamond_contract_address.',
    '{"short_id": "drdc", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "rac", "diamond", "deploy", "laser", "ethereum", "contract", "workflow"]'::jsonb,
    '{"index": "4"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 5: Initialize RAC Diamond
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'initialize_rac_diamond',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Initialize RAC Diamond',
    'Initialize RAC Diamond with admin_partner_slot_address as admin. Uses deployer as signer.',
    '{"short_id": "ird", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "rac", "diamond", "initialize", "laser", "ethereum", "workflow"]'::jsonb,
    '{"index": "5"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 6: Grant AddFacets Permission to Admin on RAC
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'grant_add_facets_permission_to_admin_rac',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Grant AddFacets Permission to Admin on RAC',
    'authz_admin grants addFacets(address[]) permission to admin_partner on RAC Diamond.',
    '{"short_id": "gafpar", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "rac", "permission", "grant", "add-facets", "laser", "workflow"]'::jsonb,
    '{"index": "6"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 7: Add RAC Facet to RAC Diamond
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'add_rac_facet_to_rac_diamond',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Add RAC Facet to RAC Diamond',
    'admin_partner adds RAC facet (from lattice using rac_facet_version) to RAC Diamond.',
    '{"short_id": "arftrd", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "rac", "facet", "add", "diamond", "laser", "workflow"]'::jsonb,
    '{"index": "7"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 8: Create RAC Deployment Record
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_rac_deployment_record',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Create RAC Deployment Record',
    'Create LegalMechanismDeployment with type=LASER, linking to RAC mechanism, with contract address from step 4.',
    '{"short_id": "crdr", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "rac", "deployment", "record", "laser", "workflow"]'::jsonb,
    '{"index": "8"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 9: Deploy Trezor Diamond Contract
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_trezor_diamond_contract',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Deploy Trezor Diamond Contract',
    'Deploy Trezor Diamond via LASER using deployer signer. Contract name = {prefix}-Trezor. Returns trezor_diamond_contract_address.',
    '{"short_id": "dtdc", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "diamond", "deploy", "laser", "ethereum", "contract", "workflow"]'::jsonb,
    '{"index": "9"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 10: Initialize Trezor Diamond
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'initialize_trezor_diamond',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Initialize Trezor Diamond',
    'Initialize Trezor Diamond with admin_partner_slot_address as admin. Uses deployer as signer.',
    '{"short_id": "itd", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "diamond", "initialize", "laser", "ethereum", "workflow"]'::jsonb,
    '{"index": "10"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 11: Grant AddFacets Permission to Admin on Trezor
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'grant_add_facets_permission_to_admin_trezor',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Grant AddFacets Permission to Admin on Trezor',
    'authz_admin grants addFacets(address[]) permission to admin_partner on Trezor Diamond.',
    '{"short_id": "gafpat", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "permission", "grant", "add-facets", "laser", "workflow"]'::jsonb,
    '{"index": "11"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 12: Add Vault Facets to Trezor Diamond
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'add_vault_facets_to_trezor_diamond',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Add Vault Facets to Trezor Diamond',
    'admin_partner adds 7 vault facets to Trezor Diamond: erc20-vault-admin, erc20-vault, ledger-lister, rbac, props, activity-store, eth-vault.',
    '{"short_id": "avfttd", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "vault", "facets", "add", "diamond", "laser", "workflow"]'::jsonb,
    '{"index": "12"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 13: Grant CreateLedger Permission
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'grant_create_ledger_permission',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Grant CreateLedger Permission',
    'authz_admin grants createLedger permission to admin_partner on Trezor Diamond.',
    '{"short_id": "gclp", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "permission", "grant", "create-ledger", "laser", "workflow"]'::jsonb,
    '{"index": "13"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 14: Create Default Ledger
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_default_ledger',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Create Default Ledger',
    'admin_partner creates DEFAULT ledger (non-slave, id=1) on Trezor Diamond via createLedger function.',
    '{"short_id": "cdl", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "ledger", "create", "default", "laser", "workflow"]'::jsonb,
    '{"index": "14"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 15: Grant SetAddress Permission
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'grant_set_address_permission',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Grant SetAddress Permission',
    'authz_admin grants setAddress permission to admin_partner on Trezor Diamond.',
    '{"short_id": "gsap", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "permission", "grant", "set-address", "props", "laser", "workflow"]'::jsonb,
    '{"index": "15"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 16: Grant SetInt Permission
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'grant_set_int_permission',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Grant SetInt Permission',
    'authz_admin grants setInt permission to admin_partner on Trezor Diamond.',
    '{"short_id": "gsip", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "permission", "grant", "set-int", "props", "laser", "workflow"]'::jsonb,
    '{"index": "16"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 17: Configure RAC Properties
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'configure_rac_properties',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Configure RAC Properties',
    'admin_partner configures Trezor Diamond: setInt(''rac.domain.id'', 999) and setAddress(''rac.address'', rac_diamond_contract_address).',
    '{"short_id": "crp", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "rac", "props", "configure", "laser", "workflow"]'::jsonb,
    '{"index": "17"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 18: Grant Treasury RAC Access
-- CRITICAL: Grant Trezor Diamond access to call protected functions on RAC Diamond.
--           Without this step, Fund Account saga will fail with DMND:NAUTH when Trezor
--           calls rac.updateResourceQuota() during vault operations.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'grant_treasury_rac_access',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Grant Treasury RAC Access',
    'CRITICAL: Grant Trezor Diamond access to RAC Diamond via SimpleAuthzAddAccount. Required for vault operations (depositToErc20Vault) that call rac.updateResourceQuota().',
    '{"short_id": "gtra", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "rac", "authz", "permission", "laser", "workflow", "critical"]'::jsonb,
    '{"index": "18"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 19: Create Treasury Deployment Record
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'create_treasury_deployment_record',
    'deploy_treasury_legal_mechanisms_for_legal_structure',
    'Create Treasury Deployment Record',
    'Create LegalMechanismDeployment with type=LASER, linking to Treasury mechanism, with Trezor contract address from step 9.',
    '{"short_id": "ctdr", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "treasury", "trezor", "deployment", "record", "laser", "workflow"]'::jsonb,
    '{"index": "19"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: deploy_trading_legal_mechanisms_for_legal_structure
-- ============================================================================
-- Description: TRAX flow for deploying Trading governance mechanisms
--              (Agora Engine Diamond) for an existing legal structure
--              that already has Core Legal Mechanisms deployed. EthBC-only.
-- Steps: 9
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'deploy_trading_legal_mechanisms_for_legal_structure',
    'Deploy Trading Legal Mechanisms for Legal Structure',
    'TRAX flow for deploying Trading governance mechanisms (Agora Engine Diamond) for an existing legal structure that already has Core Legal Mechanisms deployed. EthBC-only.',
    '{"short_id": "dtrlmfls"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "legal-mechanism", "legal-structure", "trading", "agora-engine", "laser", "governance", "ethereum", "trax-flow", "diamond"]'::jsonb,
    '{}'::jsonb,
    '["dtlm_verify_trading_mechanism_inputs", "dtlm_create_trading_engine_legal_mechanism", "dtlm_deploy_trading_engine_diamond_contract", "dtlm_initialize_trading_engine_diamond", "dtlm_grant_add_facets_perm_trading_engine", "dtlm_add_trading_engine_facets", "dtlm_grant_set_address_perm_trading_engine", "dtlm_configure_algo_address_properties", "dtlm_create_trading_engine_deployment_record"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: deploy_trading_legal_mechanisms_for_legal_structure
-- ----------------------------------------------------------------------------

-- Step 1: Verify Trading Mechanism Inputs
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'dtlm_verify_trading_mechanism_inputs',
    'deploy_trading_legal_mechanisms_for_legal_structure',
    'Verify Trading Mechanism Inputs',
    'Validate inputs, verify Core Legal Mechanisms exist, verify no Trading mechanisms exist, verify admin_partner is partner + TM admin, verify authz_admin is AuthzDiamond admin, verify deployer has SIGNER slot, verify all facet versions provided.',
    '{"short_id": "dtlm_vtmi", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "verify", "inputs", "workflow"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Create Trading Engine Legal Mechanism
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'dtlm_create_trading_engine_legal_mechanism',
    'deploy_trading_legal_mechanisms_for_legal_structure',
    'Create Trading Engine Legal Mechanism',
    'Create LegalMechanism record with type=TRADING and slot_address = {prefix}-AgoraEngine.',
    '{"short_id": "dtlm_ctelm", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "create", "mechanism", "workflow"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Deploy Trading Engine Diamond Contract
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'dtlm_deploy_trading_engine_diamond_contract',
    'deploy_trading_legal_mechanisms_for_legal_structure',
    'Deploy Trading Engine Diamond Contract',
    'Deploy Agora Engine Diamond via LASER using deployer. Contract name = {prefix}-AgoraEngine.',
    '{"short_id": "dtlm_dtedc", "service": "laseragent"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "deploy", "diamond", "laser", "workflow"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 4: Initialize Trading Engine Diamond
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'dtlm_initialize_trading_engine_diamond',
    'deploy_trading_legal_mechanisms_for_legal_structure',
    'Initialize Trading Engine Diamond',
    'Initialize Agora Engine Diamond with admin_partner as admin, AuthzSource from Core, TaskManager from Core, authzDomain=AGORA_ENGINE.',
    '{"short_id": "dtlm_ited", "service": "laseragent"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "initialize", "diamond", "laser", "workflow"]'::jsonb,
    '{"index": "4"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 5: Grant Add Facets Permission to Admin (Trading Engine)
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'dtlm_grant_add_facets_perm_trading_engine',
    'deploy_trading_legal_mechanisms_for_legal_structure',
    'Grant Add Facets Permission to Admin (Trading Engine)',
    'authz_admin grants addFacets permission to admin_partner on Agora Engine diamond via SimpleAuthzAddAccount.',
    '{"short_id": "dtlm_gafpte", "service": "laseragent"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "grant", "permission", "facets", "authz", "workflow"]'::jsonb,
    '{"index": "5"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 6: Add Trading Engine Facets
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'dtlm_add_trading_engine_facets',
    'deploy_trading_legal_mechanisms_for_legal_structure',
    'Add Trading Engine Facets',
    'admin_partner adds 10 facets to Agora Engine diamond: RBAC, Props, AgoraEngine, TradeManager, PairManager, OfferManager, Matcher, OrderStats, DirectOrderManager, DirectOrderV2+V2Query.',
    '{"short_id": "dtlm_atef", "service": "laseragent"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "add", "facets", "diamond", "laser", "workflow"]'::jsonb,
    '{"index": "6"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 7: Grant Set Address Permission (Trading Engine)
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'dtlm_grant_set_address_perm_trading_engine',
    'deploy_trading_legal_mechanisms_for_legal_structure',
    'Grant Set Address Permission (Trading Engine)',
    'authz_admin grants setAddress permission to admin_partner on Agora Engine diamond via SimpleAuthzAddAccount.',
    '{"short_id": "dtlm_gsapte", "service": "laseragent"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "grant", "permission", "setAddress", "authz", "workflow"]'::jsonb,
    '{"index": "7"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 8: Configure Algo Address Properties
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'dtlm_configure_algo_address_properties',
    'deploy_trading_legal_mechanisms_for_legal_structure',
    'Configure Algo Address Properties',
    'admin_partner sets MatcherAlgo and SettlerAlgo facet addresses as properties on Agora Engine diamond via DIAMOND_PROPS_SET_ADDRESS (PropsFacet.setAddress). Keys: agora.engine.global.matching.matcher.algo.facet, agora.engine.global.matching.settler.algo.facet.',
    '{"short_id": "dtlm_caap", "service": "laseragent"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "configure", "props", "address", "algo", "matcher", "settler", "workflow"]'::jsonb,
    '{"index": "8"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 9: Create Trading Engine Deployment Record
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'dtlm_create_trading_engine_deployment_record',
    'deploy_trading_legal_mechanisms_for_legal_structure',
    'Create Trading Engine Deployment Record',
    'Create LegalMechanismDeployment with type=LASER, linking to Trading Engine mechanism, with Agora Engine contract address from step 3.',
    '{"short_id": "dtlm_ctedr", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "deployment", "record", "laser", "workflow"]'::jsonb,
    '{"index": "9"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: setup_new_legal_participant
-- ============================================================================
-- Description: TRAX saga for setting up a Legal Participant in prtagent namespace
--              with partners, legal structure, core mechanisms, and API key.
--              NOTE: Treasury mechanisms, trading mechanisms, and cash tokens are
--              NOT deployed in prtagent - those are CSD-only concerns.
-- Steps: 6
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'setup_new_legal_participant',
    'Setup New Legal Participant',
    'TRAX saga for setting up a complete Legal Participant with partners, legal structure, core mechanisms, treasury mechanisms, trading engine mechanisms, cash tokens, and API key',
    '{"short_id": "snlp"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "legal-participant", "participant", "legal-structure", "partnership", "mechanisms", "treasury", "trading", "agora-engine", "cash-token", "api-key", "trax-flow"]'::jsonb,
    '{}'::jsonb,
    '["snlp_create_legal_participant_record", "snlp_create_or_validate_partner_participants", "snlp_spawn_establish_legal_structure_saga", "snlp_set_principal_legal_structure", "snlp_spawn_deploy_core_mechanisms_saga", "snlp_spawn_deploy_treasury_mechanisms_saga", "snlp_spawn_deploy_trading_engine_mechanisms_saga", "snlp_spawn_deploy_cash_tokens_saga", "snlp_create_api_keys"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: setup_new_legal_participant
-- ----------------------------------------------------------------------------

-- Step 1: Create Legal Participant Record
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'snlp_create_legal_participant_record',
    'setup_new_legal_participant',
    'Create Legal Participant Record',
    'Create participant record for the Legal Participant with provided or auto-generated IID, display names, descriptions, types, and identifiers.',
    '{"short_id": "snlp_s1", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-participant", "participant", "create", "legal-participant", "workflow"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Create or Validate Partner Participants
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'snlp_create_or_validate_partner_participants',
    'setup_new_legal_participant',
    'Create or Validate Partner Participants',
    'Create new partner participant records (if create_new=true) or validate existing participants (if create_new=false). Verify deployer is in partners list.',
    '{"short_id": "snlp_s2", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-participant", "participant", "partner", "create", "validate", "workflow"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Spawn Establish Legal Structure Saga
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'snlp_spawn_establish_legal_structure_saga',
    'setup_new_legal_participant',
    'Spawn Establish Legal Structure Saga',
    'Submit establish_new_legal_structure_for_participant sub-saga and wait for completion. Creates PARTNERSHIP legal structure with owner, partner, and clearing accounts.',
    '{"short_id": "snlp_s3", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-participant", "sub-saga", "legal-structure", "partnership", "spawn", "workflow"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 4: Set Principal Legal Structure
-- Service: accmgr (calls configmgr)
-- Purpose: If is_principal flag is set, register the legal structure as the
--          Principal Legal Structure (PLS) in configmgr. Skips if flag not set.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'snlp_set_principal_legal_structure',
    'setup_new_legal_participant',
    'Set Principal Legal Structure',
    'If is_principal flag is set, register the legal structure as the Principal Legal Structure (PLS) in configmgr. Uses set-once semantics: fails with 409 if PLS already configured.',
    '{"short_id": "snlp_s4", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-participant", "principal", "pls", "configmgr", "workflow"]'::jsonb,
    '{"index": "4"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 5: Spawn Deploy Core Mechanisms Saga
-- Service: accmgr
-- Purpose: Submit deploy_core_legal_mechanisms_for_legal_structure sub-saga and wait for completion.
--          Deploys TaskManagerV2 and AuthzDiamond contracts.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'snlp_spawn_deploy_core_mechanisms_saga',
    'setup_new_legal_participant',
    'Spawn Deploy Core Mechanisms Saga',
    'Submit deploy_core_legal_mechanisms_for_legal_structure sub-saga and wait for completion. Deploys TaskManagerV2 and AuthzDiamond contracts.',
    '{"short_id": "snlp_s5", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-participant", "sub-saga", "core-mechanisms", "task-manager", "authz", "spawn", "workflow"]'::jsonb,
    '{"index": "5"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 6: Spawn Deploy Treasury Mechanisms Saga
-- Service: accmgr
-- Purpose: Submit deploy_treasury_legal_mechanisms_for_legal_structure sub-saga and wait for completion.
--          Deploys RAC and Trezor Diamonds.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'snlp_spawn_deploy_treasury_mechanisms_saga',
    'setup_new_legal_participant',
    'Spawn Deploy Treasury Mechanisms Saga',
    'Submit deploy_treasury_legal_mechanisms_for_legal_structure sub-saga and wait for completion. Deploys RAC and Trezor Diamonds.',
    '{"short_id": "snlp_s6", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-participant", "sub-saga", "treasury-mechanisms", "rac", "trezor", "spawn", "workflow"]'::jsonb,
    '{"index": "6"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 7: Spawn Deploy Trading Engine Mechanisms Saga
-- Service: accmgr
-- Purpose: Submit deploy_trading_legal_mechanisms_for_legal_structure sub-saga and wait for completion.
--          Deploys Agora Engine Diamond. Controlled by force_creation_of_trading_mechanism flag.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'snlp_spawn_deploy_trading_engine_mechanisms_saga',
    'setup_new_legal_participant',
    'Spawn Deploy Trading Engine Mechanisms Saga',
    'Submit deploy_trading_legal_mechanisms_for_legal_structure sub-saga and wait for completion. Deploys Agora Engine Diamond. Controlled by force_creation_of_trading_mechanism flag.',
    '{"short_id": "snlp_s7", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-participant", "sub-saga", "trading-mechanisms", "agora-engine", "spawn", "workflow"]'::jsonb,
    '{"index": "7"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 8: Spawn Deploy Cash Tokens Saga
-- Service: accmgr
-- Purpose: Submit deploy_cash_token_legal_mechanism_for_legal_structure sub-sagas
--          (one per currency) and wait for completion. Issues ERC20 tokens to LS Clearing Account.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'snlp_spawn_deploy_cash_tokens_saga',
    'setup_new_legal_participant',
    'Spawn Deploy Cash Tokens Saga',
    'Submit deploy_cash_token_legal_mechanism_for_legal_structure sub-sagas (one per currency) and wait for completion. Issues ERC20 tokens to LS Clearing Account.',
    '{"short_id": "snlp_s8", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-participant", "sub-saga", "cash-token", "erc20", "currency", "spawn", "workflow"]'::jsonb,
    '{"index": "8"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 9: Create API Keys
-- Service: accmgr
-- Purpose: Mint ParticipantAPIKeys for each entry in the api_keys input list.
--          Empty list = no keys minted. Plaintext keys returned only once in
--          saga output, then disabled on compensation.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'snlp_create_api_keys',
    'setup_new_legal_participant',
    'Create API Keys',
    'Mint ParticipantAPIKeys for each entry in the api_keys input list. Empty list = no keys minted. Plaintext keys returned only once in saga output, then disabled on compensation.',
    '{"short_id": "snlp_s9", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-participant", "api-key", "authentication", "rest", "create", "workflow"]'::jsonb,
    '{"index": "9"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: setup_new_issuer_participant
-- ============================================================================
-- Description: TRAX saga for setting up an Issuer Participant. Spawns
--              setup_new_legal_participant as sub-saga with issuer-specific
--              defaults (optional treasury/cash tokens, no trading, not principal).
-- Steps: 1
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'setup_new_issuer_participant',
    'Setup New Issuer Participant',
    'TRAX saga for setting up an Issuer Participant. Spawns setup_new_legal_participant as sub-saga with issuer-specific defaults (optional treasury/cash tokens, no trading, not principal).',
    '{"short_id": "snip"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "issuer", "participant", "legal-structure", "trax-flow"]'::jsonb,
    '{}'::jsonb,
    '["snip_spawn_setup_legal_participant_saga"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: setup_new_issuer_participant
-- ----------------------------------------------------------------------------

-- Step 1: Spawn Setup Legal Participant Saga
-- Service: accmgr
-- Purpose: Submit setup_new_legal_participant sub-saga and wait for completion.
--          Creates issuer participant with partners, legal structure, core
--          mechanisms, optional treasury/cash tokens, and API key.
--          No trading engine, not principal.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'snip_spawn_setup_legal_participant_saga',
    'setup_new_issuer_participant',
    'Spawn Setup Legal Participant Saga',
    'Submit setup_new_legal_participant sub-saga and wait for completion. Creates issuer participant with partners, legal structure, core mechanisms, optional treasury/cash tokens, and API key. No trading engine, not principal.',
    '{"short_id": "snip_s1", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "issuer", "sub-saga", "legal-participant", "spawn", "workflow"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: create_custodian_sub_account
-- ============================================================================
-- Description: Creates a sub-account under a custodian's custody account.
--              Creates Account (Client type), PARENT_CHILD AccountToAccountRelation
--              linking custody account to sub-account, non-signer LASER slots,
--              and attaches ETH address to activate the account.
-- Steps: 5
-- Triggered by: csdmsggw REST API (PUT /api/v1/custodians/legal-structures/sub-accounts/create)
-- Similar to: new_investor_under_participant (same non-signer slot pattern)
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'create_custodian_sub_account',
    'Create Custodian Sub-Account',
    'Creates a sub-account under a custodian custody account with PARENT_CHILD relation, non-signer LASER slots, and ETH address attachment. Triggered by csdmsggw REST API.',
    '{"short_id": "ccsa"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "custodian", "sub-account", "parent-child", "laser", "trax-flow"]'::jsonb,
    '{}'::jsonb,
    '["ccsa_verify_inputs", "ccsa_create_sub_account", "ccsa_create_parent_child_relation", "ccsa_create_laser_slots", "ccsa_attach_eth_address_and_activate"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: create_custodian_sub_account
-- ----------------------------------------------------------------------------

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'ccsa_verify_inputs',
    'create_custodian_sub_account',
    'Verify Sub-Account Inputs',
    'Validate legal structure ownership, custody account existence, and uniqueness of (participant_iid, external_account_id) combination.',
    '{"short_id": "ccsa_s1", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "custodian", "sub-account", "verify", "validation", "workflow"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'ccsa_create_sub_account',
    'create_custodian_sub_account',
    'Create Sub-Account',
    'Create Account (type=Client, status=PENDING) with external_account_id and participant_iid_for_external_account.',
    '{"short_id": "ccsa_s2", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "custodian", "sub-account", "create", "account", "workflow"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'ccsa_create_parent_child_relation',
    'create_custodian_sub_account',
    'Create Parent-Child Relation',
    'Create AccountToAccountRelation (PARENT_CHILD) linking custody account (parent/from) to new sub-account (child/to).',
    '{"short_id": "ccsa_s3", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "custodian", "sub-account", "parent-child", "relation", "workflow"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'ccsa_create_laser_slots',
    'create_custodian_sub_account',
    'Create Sub-Account LASER Slots',
    'Create non-signer LASER slots for the sub-account using account_iid as seed (tags=nil, no SIGNER capability). Outputs the derived eth_address for the next step.',
    '{"short_id": "ccsa_s4", "service": "laseragent"}'::jsonb,
    '["agora", "csd", "saga", "step", "custodian", "sub-account", "laser", "slots", "non-signer", "workflow"]'::jsonb,
    '{"index": "4"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'ccsa_attach_eth_address_and_activate',
    'create_custodian_sub_account',
    'Attach ETH Address and Activate Sub-Account',
    'Attach Ethereum address from LASER slot creation as FinIdentifier (scheme=ethereum, standard=EIP-55) and set account status to ACTIVE.',
    '{"short_id": "ccsa_s5", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "custodian", "sub-account", "ethereum", "address", "activate", "workflow"]'::jsonb,
    '{"index": "5"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: deploy_cash_token_legal_mechanism_for_legal_structure
-- ============================================================================
-- Description: TRAX flow for deploying a Cash Token (ERC20) Legal Mechanism
--              for an existing legal structure using Diamond+Facet pattern.
--              Deploys Diamond, adds LaserErc20Facet, initializes token,
--              issues initial supply to clearing account, and records the cash token.
-- Steps: 10
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'deploy_cash_token_legal_mechanism_for_legal_structure',
    'Deploy Cash Token Legal Mechanism for Legal Structure',
    'TRAX flow for deploying a Cash Token (ERC20) Legal Mechanism for an existing legal structure using Diamond+Facet pattern. Deploys Diamond, adds LaserErc20Facet, initializes token, issues initial supply to clearing account, and records the cash token.',
    '{"short_id": "dctlmfls"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "legal-mechanism", "legal-structure", "cash-token", "erc20", "laser", "ethereum", "trax-flow", "currency", "diamond", "facet"]'::jsonb,
    '{}'::jsonb,
    '["dctlm_verify_cash_token_inputs", "dctlm_create_cash_token_legal_mechanism", "dctlm_deploy_erc20_diamond", "dctlm_update_mechanism_contract_address", "dctlm_initialize_erc20_diamond", "dctlm_grant_add_laser_erc20_facet_permission", "dctlm_add_laser_erc20_facet", "dctlm_grant_initialize_laser_erc20_permission", "dctlm_initialize_laser_erc20", "dctlm_grant_mint_permission", "dctlm_grant_clearing_deposit_permission", "dctlm_issue_initial_supply_to_clearing", "dctlm_deposit_initial_supply_to_treasury", "dctlm_create_cash_token_record", "dctlm_amend_vault_link_metadata", "dctlm_claim_authz_instr_erc20_diamond_via_metadata"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: deploy_cash_token_legal_mechanism_for_legal_structure
-- ----------------------------------------------------------------------------

-- Step 1: Verify Cash Token Inputs
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'dctlm_verify_cash_token_inputs',
    'deploy_cash_token_legal_mechanism_for_legal_structure',
    'Verify Cash Token Inputs',
    'Validate inputs: verify legal structure exists, Treasury mechanism is deployed, currency_code is valid ISO 4217, deployer has SIGNER slot, clearing account exists.',
    '{"short_id": "dctlm_s1", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "verify", "validate", "currency", "workflow"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Create Cash Token Legal Mechanism
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'dctlm_create_cash_token_legal_mechanism',
    'deploy_cash_token_legal_mechanism_for_legal_structure',
    'Create Cash Token Legal Mechanism',
    'Create LegalMechanism record with type=CASH_TOKEN, LegalStructureIid, currency_code in metadata. Store slot_address = {prefix}-CashToken-{currency} in metadata.',
    '{"short_id": "dctlm_s2", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "create", "record", "currency", "workflow"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Deploy ERC20 Diamond
-- Service: lasersvc
-- Purpose: Deploy Diamond contract for ERC20 token via LASER using deployer signer.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'dctlm_deploy_erc20_diamond',
    'deploy_cash_token_legal_mechanism_for_legal_structure',
    'Deploy ERC20 Diamond',
    'Deploy Diamond contract for ERC20 token via LASER using deployer signer. Contract name = {prefix}-CashToken-{currency}. Returns cash_token_diamond_contract_address.',
    '{"short_id": "dctlm_s3", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "diamond", "deploy", "laser", "ethereum", "contract", "workflow"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 4: Update Mechanism with Contract Address
-- Service: accmgr
-- Purpose: Update the CashToken LegalMechanism metadata with the deployed contract_address (ETH address).
--          This is required for fund_account_with_cash_tokens saga to find the ERC20 contract address.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'dctlm_update_mechanism_contract_address',
    'deploy_cash_token_legal_mechanism_for_legal_structure',
    'Update Mechanism with Contract Address',
    'Update the CashToken LegalMechanism metadata with contract_address from the deployed Diamond. Required for fund_account_with_cash_tokens saga.',
    '{"short_id": "dctlm_s4", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "update", "contract-address", "accmgr", "workflow"]'::jsonb,
    '{"index": "4"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 5: Initialize ERC20 Diamond
-- Service: lasersvc
-- Purpose: Initialize Diamond with TaskManager, AuthzSource references.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'dctlm_initialize_erc20_diamond',
    'deploy_cash_token_legal_mechanism_for_legal_structure',
    'Initialize ERC20 Diamond',
    'Initialize Diamond with TaskManager reference, AuthzSource, and AuthzDomain="CashToken". Uses deployer as signer.',
    '{"short_id": "dctlm_s5", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "diamond", "initialize", "laser", "ethereum", "workflow"]'::jsonb,
    '{"index": "5"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 6: Grant Add LaserErc20Facet Permission
-- Service: lasersvc
-- Purpose: authz_admin grants addFacets permission to admin_partner on CashToken Diamond.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'dctlm_grant_add_laser_erc20_facet_permission',
    'deploy_cash_token_legal_mechanism_for_legal_structure',
    'Grant Add LaserErc20Facet Permission',
    'authz_admin grants addFacets(address[]) permission to admin_partner on CashToken Diamond via SimpleAuthzAddAccount.',
    '{"short_id": "dctlm_s6", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "permission", "grant", "add-facets", "laser", "workflow"]'::jsonb,
    '{"index": "6"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 7: Add LaserErc20Facet to Diamond
-- Service: lasersvc
-- Purpose: admin_partner adds LaserErc20Facet to CashToken Diamond.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'dctlm_add_laser_erc20_facet',
    'deploy_cash_token_legal_mechanism_for_legal_structure',
    'Add LaserErc20Facet to Diamond',
    'admin_partner adds LaserErc20Facet (from lattice using laser_erc20_facet_version) to CashToken Diamond via DiamondAddFacets.',
    '{"short_id": "dctlm_s7", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "facet", "add", "diamond", "laser", "erc20", "workflow"]'::jsonb,
    '{"index": "7"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 8: Grant Initialize LaserErc20 Permission
-- Service: lasersvc
-- Purpose: authz_admin grants initialize permission to admin_partner on CashToken Diamond.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'dctlm_grant_initialize_laser_erc20_permission',
    'deploy_cash_token_legal_mechanism_for_legal_structure',
    'Grant Initialize LaserErc20 Permission',
    'authz_admin grants initialize permission to admin_partner on CashToken Diamond via SimpleAuthzAddAccount.',
    '{"short_id": "dctlm_s8", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "permission", "grant", "initialize", "laser", "workflow"]'::jsonb,
    '{"index": "8"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 9: Initialize LaserErc20
-- Service: lasersvc
-- Purpose: Initialize ERC20 token with name, symbol, and decimals via LaserErc20FacetInitialize.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'dctlm_initialize_laser_erc20',
    'deploy_cash_token_legal_mechanism_for_legal_structure',
    'Initialize LaserErc20',
    'Initialize ERC20 token with name={currency_code} Cash Token, symbol={currency_code}, decimals=18 via LaserErc20FacetInitialize.',
    '{"short_id": "dctlm_s9", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "erc20", "initialize", "laser", "ethereum", "workflow"]'::jsonb,
    '{"index": "9"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 10: Grant Mint Permission
-- Service: lasersvc
-- Purpose: Grant mint permission to deployer on AuthzDiamond. Required for FundAccountWithCashTokens saga to mint tokens.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'dctlm_grant_mint_permission',
    'deploy_cash_token_legal_mechanism_for_legal_structure',
    'Grant Mint Permission',
    'authz_admin grants mint permission to deployer on AuthzDiamond via SimpleAuthzAddAccount. Required for FundAccountWithCashTokens saga to mint tokens.',
    '{"short_id": "dctlm_s10", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "permission", "grant", "mint", "laser", "workflow"]'::jsonb,
    '{"index": "10"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 11: Grant Clearing Account Deposit Permission
-- Service: lasersvc
-- Purpose: Grant clearing account permission on AuthzSource to call depositToErc20Vault on Trezor Diamond.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'dctlm_grant_clearing_deposit_permission',
    'deploy_cash_token_legal_mechanism_for_legal_structure',
    'Grant Clearing Deposit Permission',
    'authz_admin grants clearing account permission on AuthzDiamond via SimpleAuthzAddAccount. Required for clearing account to call depositToErc20Vault on Trezor Diamond.',
    '{"short_id": "dctlm_s11", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "permission", "grant", "clearing", "deposit", "treasury", "laser", "workflow"]'::jsonb,
    '{"index": "11"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 12: Issue Initial Supply to Clearing Account
-- Service: lasersvc
-- Purpose: Mint initial tokens to clearing account via LaserErc20FacetMint.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'dctlm_issue_initial_supply_to_clearing',
    'deploy_cash_token_legal_mechanism_for_legal_structure',
    'Issue Initial Supply to Clearing Account',
    'Mint initial_amount tokens to clearing_account_slot_address via LaserErc20FacetMint. Skip if initial_amount is 0.',
    '{"short_id": "dctlm_s12", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "erc20", "mint", "initial-supply", "clearing", "laser", "workflow"]'::jsonb,
    '{"index": "12"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 13: Deposit Initial Supply to Treasury
-- Service: lasersvc
-- Purpose: Deposit minted tokens from clearing account into Treasury vault for vault accounting.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'dctlm_deposit_initial_supply_to_treasury',
    'deploy_cash_token_legal_mechanism_for_legal_structure',
    'Deposit Initial Supply to Treasury',
    'Deposit minted tokens from clearing account into Treasury vault via TrezorErc20DepositToVault. Required for fund_account_with_cash_tokens vault-to-vault transfers.',
    '{"short_id": "dctlm_s13", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "erc20", "deposit", "treasury", "vault", "laser", "workflow"]'::jsonb,
    '{"index": "13"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 14: Create Cash Token Record
-- Service: instrmgr
-- Purpose: Create CashToken record and LegalMechanismDeployment.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'dctlm_create_cash_token_record',
    'deploy_cash_token_legal_mechanism_for_legal_structure',
    'Create Cash Token Record',
    'Create CashToken record in instrmgr with currency_code, contract_address, legal_structure_iid, and mechanism_iid. Create LegalMechanismDeployment record.',
    '{"short_id": "dctlm_s14", "service": "instrmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "record", "create", "instrmgr", "deployment", "workflow"]'::jsonb,
    '{"index": "14"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 15: Amend Vault Link Metadata
-- Service: lasersvc (laseragent executor)
-- Purpose: Amend treasury vault link metadata with authorized_instrument_iid after the cash token record is created.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'dctlm_amend_vault_link_metadata',
    'deploy_cash_token_legal_mechanism_for_legal_structure',
    'Amend Vault Link Metadata',
    'Amend treasury vault link metadata with authorized_instrument_iid. Links created during deposit (step 13) do not have authorized_instrument_iid since the instrmgr record is created in step 14. This step amends the link metadata after the record exists.',
    '{"short_id": "dctlm_s15", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "vault-link", "metadata", "amend", "lasersvc", "workflow"]'::jsonb,
    '{"index": "15"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'dctlm_claim_authz_instr_erc20_diamond_via_metadata',
    'deploy_cash_token_legal_mechanism_for_legal_structure',
    'Claim AuthzInstr ERC20 Diamond via Metadata',
    'Stamp the authorized_instrument_iid into the cash-token''s own ERC20 Diamond inner slot metadata so the treasury indexer can resolve activities emitted by the cash-token''s contract back to the authz-instr iid. Per-cash-token slot — no shared-claim conflict. ref_seed is left untouched (immutable in lasersvc).',
    '{"short_id": "dctlm_s16", "service": "lasersvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "diamond", "metadata", "claim", "lasersvc", "workflow"]'::jsonb,
    '{"index": "16"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: fund_account_with_cash_tokens
-- ============================================================================
-- Description: Saga for funding an account with cash tokens via Treasury
-- Steps: 7
-- Services: accmgr (steps 1,7), treassvc (steps 2-6)
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'fund_account_with_cash_tokens',
    'Fund Account With Cash Tokens',
    'Saga for funding an account with cash tokens by minting or using existing clearing balance',
    '{"short_id": "facwct"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "account", "cash", "token", "treasury", "funding"]'::jsonb,
    '{}'::jsonb,
    '["facwct_verify_inputs", "facwct_query_source_balance", "facwct_mint_tokens_if_needed", "facwct_query_destination_balance", "facwct_transfer_to_destination", "facwct_verify_balances", "facwct_amend_vault_link_metadata", "facwct_create_funding_record"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: fund_account_with_cash_tokens
-- ----------------------------------------------------------------------------

-- Step 1: Verify Fund Account Inputs
-- Service: accmgr
-- Purpose: Validate all inputs and gather contract addresses for funding operation
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'facwct_verify_inputs',
    'fund_account_with_cash_tokens',
    'Verify Fund Account Inputs',
    'Validate all inputs and gather contract addresses for funding operation. Verify legal structure, mechanisms (TREASURY, CASH_TOKEN, RAC), clearing account, and destination account exist.',
    '{"short_id": "facwct_s1", "service": "accmgr"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "validation", "inputs", "account", "funding"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Query Source Vault Balance
-- Service: treassvc
-- Purpose: Query clearing account vault balance before operations
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'facwct_query_source_balance',
    'fund_account_with_cash_tokens',
    'Query Source Vault Balance',
    'Query clearing account vault LIQUID balance before operations via TrezorErc20GetVaultBalance. Validate balance if use_clearing_balance=true.',
    '{"short_id": "facwct_s2", "service": "treassvc"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "query", "treasury", "vault", "balance"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Mint Tokens If Needed
-- Service: treassvc
-- Purpose: Conditionally mint new tokens to clearing account if use_clearing_balance=false
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'facwct_mint_tokens_if_needed',
    'fund_account_with_cash_tokens',
    'Mint Tokens If Needed',
    'Conditionally mint new tokens to clearing account if use_clearing_balance=false. Execute Erc20MintTo followed by TrezorErc20DepositToVault.',
    '{"short_id": "facwct_s3", "service": "treassvc"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "mint", "erc20", "treasury", "conditional"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 4: Query Destination Vault Balance
-- Service: treassvc
-- Purpose: Query destination account vault balance before transfer
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'facwct_query_destination_balance',
    'fund_account_with_cash_tokens',
    'Query Destination Vault Balance',
    'Query destination account vault LIQUID balance before transfer via TrezorErc20GetVaultBalance.',
    '{"short_id": "facwct_s4", "service": "treassvc"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "query", "treasury", "vault", "balance", "destination"]'::jsonb,
    '{"index": "4"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 5: Transfer From Clearing To Destination
-- Service: treassvc
-- Purpose: Execute TrezorErc20TransferFromVault from clearing vault to destination vault
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'facwct_transfer_to_destination',
    'fund_account_with_cash_tokens',
    'Transfer From Clearing To Destination',
    'Execute TrezorErc20TransferFromVault from clearing vault to destination vault. Amount is transferred from LIQUID stash.',
    '{"short_id": "facwct_s5", "service": "treassvc"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "transfer", "treasury", "vault", "laser"]'::jsonb,
    '{"index": "5"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 6: Verify Post Transfer Balances
-- Service: treassvc
-- Purpose: Verify vault balances after transfer via on-chain queries
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'facwct_verify_balances',
    'fund_account_with_cash_tokens',
    'Verify Post Transfer Balances',
    'Verify vault balances after transfer via TrezorErc20GetVaultBalance queries. Source decreased by amount, destination increased by amount.',
    '{"short_id": "facwct_s6", "service": "treassvc"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "verification", "treasury", "vault", "balance"]'::jsonb,
    '{"index": "6"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 7: Amend Vault Link Metadata
-- Service: treassvc
-- Purpose: Amend treasury vault link metadata with authorized_instrument_iid
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'facwct_amend_vault_link_metadata',
    'fund_account_with_cash_tokens',
    'Amend Vault Link Metadata',
    'Amend treasury vault link metadata with authorized_instrument_iid. New links created during transfer (step 5) may lack authorized_instrument_iid. This step copies it from existing links set during deployment.',
    '{"short_id": "facwct_s7", "service": "treassvc"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "vault-link", "metadata", "amend", "treassvc"]'::jsonb,
    '{"index": "7"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 8: Create Funding Record
-- Service: accmgr
-- Purpose: Create AccountFunding record for audit trail
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'facwct_create_funding_record',
    'fund_account_with_cash_tokens',
    'Create Funding Record',
    'Create AccountFunding record for audit trail with source_account, destination_account, amount, currency, and transaction hash.',
    '{"short_id": "facwct_s8", "service": "accmgr"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "record", "funding", "account", "audit"]'::jsonb,
    '{"index": "8"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: unlock_order_stash
-- ============================================================================
-- Description: Saga for unlocking stashed tokens from an order's reserved stash
--              back to the investor's liquid (stash 0) balance.
-- Steps: 1 (accmgr validates inputs, treassvc transfer steps TBD)
-- Services: accmgr (step 1)
-- Spawned by: heer_unlock_order_stash, hcer_unlock_order_stash,
--             hrer_unlock_order_stash, hdfer_unlock_order_stash,
--             hffer_unlock_order_stash
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'unlock_order_stash',
    'Unlock Order Stash',
    'Unlock stashed tokens from order reserve (stash N) back to liquid balance (stash 0). Used when orders are cancelled, expired, rejected, or done-for-day.',
    '{"short_id": "uos"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "order", "stash", "unlock", "settlement"]'::jsonb,
    '{}'::jsonb,
    '["uos_validate_inputs", "uos_transfer_stash", "uos_verify_balance"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- Step 1: Validate Unlock Inputs
-- Service: accmgr
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'uos_validate_inputs',
    'unlock_order_stash',
    'Validate Unlock Order Stash Inputs',
    'Validate order request IID, investor vault address, order stash index, amount, and currency. Outputs source_stash_index (order stash) and destination_stash_index (0 = liquid).',
    '{"short_id": "uos_s1", "service": "accmgr"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "validation", "inputs", "order", "stash", "unlock"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Transfer Stash (stash N → stash 0)
-- Service: treassvc
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'uos_transfer_stash',
    'unlock_order_stash',
    'Transfer From Order Stash',
    'Transfer locked tokens from order stash N to liquid stash 0 via TrezorErc20 vault transfer.',
    '{"short_id": "uos_s2", "service": "treassvc"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "transfer", "stash", "unlock"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Verify Balance
-- Service: treassvc
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'uos_verify_balance',
    'unlock_order_stash',
    'Verify Post-Transfer Balance',
    'Verify that the destination stash balance increased by the expected amount after transfer.',
    '{"short_id": "uos_s3", "service": "treassvc"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "verify", "balance", "stash", "unlock"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: treasury_asset_balance_transfer
-- ============================================================================
-- TABT — generalized cash-token movement saga. Serves the
-- brktrdsvc/prtagent WithdrawCash / LockCash / UnlockCash flows: the
-- caller picks which by setting source_stash_derivation_seed,
-- destination_stash_derivation_seed, and finalize_to_erc20 in saga
-- input. Replaces the older `withdraw_cash_tokens_from_account`
-- saga; see e80bd22bd / 87f1e53f3 / d814fa071 / 6a0c0005e for the
-- rename + step-shape evolution.
-- Steps: 8
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'treasury_asset_balance_transfer',
    'Treasury Asset Balance Transfer',
    'Generalized TABT saga: shuffles cash-token balances between vault stashes (LIQUID and numbered) and optionally finalizes back to the ERC20 supply. Drives Withdraw / Lock / Unlock by setting source / destination stash seeds and finalize_to_erc20 in saga input.',
    '{"short_id": "tabt"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "account", "cash", "token", "treasury", "tabt"]'::jsonb,
    '{}'::jsonb,
    '["tabt_verify_inputs", "tabt_acquire_vault_lock", "tabt_query_source_balance", "tabt_transfer_between_stashes", "tabt_finalize_to_erc20", "tabt_verify_balances", "tabt_release_vault_lock", "tabt_create_funding_record"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: treasury_asset_balance_transfer
-- ----------------------------------------------------------------------------

-- Step 1: Verify Inputs
-- Service: accmgr
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'tabt_verify_inputs',
    'treasury_asset_balance_transfer',
    'Verify TABT Inputs',
    'Validate generalized TABT inputs: legal_structure, mechanisms (TREASURY, CASH_TOKEN), source / destination account IIDs, source / destination stash derivation seeds, finalize_to_erc20, burn_after_withdraw. Resolves treasury_deploy_id used by the vault-lock key.',
    '{"short_id": "tabt_s1", "service": "accmgr"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "verify", "tabt", "accmgr"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Acquire Vault Lock
-- Service: treassvc
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'tabt_acquire_vault_lock',
    'treasury_asset_balance_transfer',
    'Acquire Vault Lock',
    'Compose the per-stash-pair lock key (treasury_deploy_id + source/destination stash) and INSERT a row into shared.distributed_locks tagged with the saga instance id. Fails fast on a live lock for the same key. Release runs on commit AND compensation.',
    '{"short_id": "tabt_s2", "service": "treassvc"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "lock", "tabt", "treassvc"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Query Source Vault Balance
-- Service: treassvc
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'tabt_query_source_balance',
    'treasury_asset_balance_transfer',
    'Query Source Vault Balance',
    'Query the source vault balance at the resolved source_stash_number via TrezorErc20GetVaultBalance. Validate sufficient balance for the transfer amount and snapshot for downstream verification.',
    '{"short_id": "tabt_s3", "service": "treassvc"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "query", "balance", "vault", "tabt", "treassvc"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 4: Transfer Between Stashes
-- Service: treassvc
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'tabt_transfer_between_stashes',
    'treasury_asset_balance_transfer',
    'Transfer Between Stashes',
    'Execute the cross-stash vault transfer (TrezorErc20IdempTransferFromVault or TVB depending on source / destination shape). Source / destination accounts + stash numbers come from the saga input.',
    '{"short_id": "tabt_s4", "service": "treassvc"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "transfer", "vault", "tabt", "treassvc"]'::jsonb,
    '{"index": "4"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 5: Finalize To ERC20
-- Service: treassvc
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'tabt_finalize_to_erc20',
    'treasury_asset_balance_transfer',
    'Finalize To ERC20',
    'Optional tail (gated on finalize_to_erc20=true, runs for Withdraw, skipped for Lock / Unlock). Withdraw tokens from the clearing vault to the ERC20 balance via TrezorErc20WithdrawFromVault, optionally burn via LaserErc20FacetBurn under the deployer BURNER_ROLE if burn_after_withdraw=true.',
    '{"short_id": "tabt_s5", "service": "treassvc"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "withdraw", "burn", "vault", "erc20", "tabt", "treassvc"]'::jsonb,
    '{"index": "5"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 6: Verify Post Transfer Balances
-- Service: treassvc
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'tabt_verify_balances',
    'treasury_asset_balance_transfer',
    'Verify Post Transfer Balances',
    'Re-query the source / destination vaults via TrezorErc20GetVaultBalance and compare against the pre-transfer snapshots. Source decreased by amount, destination increased by amount.',
    '{"short_id": "tabt_s6", "service": "treassvc"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "verify", "balance", "vault", "tabt", "treassvc"]'::jsonb,
    '{"index": "6"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 7: Release Vault Lock
-- Service: treassvc
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'tabt_release_vault_lock',
    'treasury_asset_balance_transfer',
    'Release Vault Lock',
    'DELETE every row tagged with this saga instance id from shared.distributed_locks. Runs on commit and compensation so an aborted TABT does not park a lock.',
    '{"short_id": "tabt_s7", "service": "treassvc"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "lock", "tabt", "treassvc"]'::jsonb,
    '{"index": "7"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 8: Create Funding Record
-- Service: accmgr
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'tabt_create_funding_record',
    'treasury_asset_balance_transfer',
    'Create TABT Funding Record',
    'Insert an AccountFunding row (WITHDRAWAL / LOCK / UNLOCK depending on saga inputs) for audit trail with source / destination accounts, amount, currency, transfer + (optional) erc20-finalize tx hashes.',
    '{"short_id": "tabt_s8", "service": "accmgr"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "record", "tabt", "account", "audit"]'::jsonb,
    '{"index": "8"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: setup_security_listing
-- ============================================================================
-- Description: Creates a SecurityListing record (or reuses existing), resolves
--              deployment configuration from CSD message gateway and accmgr,
--              sets up cross-diamond authorization grants, creates a trading
--              pair on-chain via createPairV2, and records the deployment and
--              event in listingmgr stores.
-- Steps: 11
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'setup_security_listing',
    'Setup Security Listing',
    'Creates security listing record and deploys trading pair on-chain via createPairV2',
    '{"short_id": "ssl"}'::jsonb,
    '["agora", "csd", "saga", "security-listing", "pair", "createPairV2", "listingmgr", "trax-flow"]'::jsonb,
    '{}'::jsonb,
    '["ssl_validate_inputs", "ssl_query_deployment_config", "ssl_resolve_fee_collector", "ssl_resolve_issuer_admin", "ssl_authorize_admin_on_trading_engine", "ssl_authorize_engine_on_security_treasury", "ssl_authorize_engine_on_cash_treasury", "ssl_create_or_reuse_security_listing", "ssl_create_calendar", "ssl_create_pair_on_chain", "ssl_create_deployment_and_event_records"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: setup_security_listing
-- ----------------------------------------------------------------------------

-- Step 1: Validate Inputs
-- Service: listingmgr
-- Purpose: Validate all required saga inputs and check for existing listings/deployments
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'ssl_validate_inputs',
    'setup_security_listing',
    'Validate Inputs',
    'Validate required inputs (fin_id_strs, execution_runtime, slot addresses) and check for existing SecurityListing or deployment conflicts.',
    '{"short_id": "ssl_s1", "service": "listingmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "security-listing", "validation"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Query Deployment Config
-- Service: listingmgr
-- Purpose: Query csdmsggw for security listing deployment configuration
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'ssl_query_deployment_config',
    'setup_security_listing',
    'Query Deployment Config',
    'Query csdmsggw for deployment configuration including LASER slot addresses, trezor addresses, CFI code, and issuer information.',
    '{"short_id": "ssl_s2", "service": "listingmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "security-listing", "config", "csdmsggw"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Resolve Fee Collector
-- Service: listingmgr
-- Purpose: Resolve the fee collector slot address from the trading mechanism's legal structure
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'ssl_resolve_fee_collector',
    'setup_security_listing',
    'Resolve Fee Collector',
    'Query accmgr to find the legal structure owning the trading mechanism, then resolve the clearing account slot address as fee collector.',
    '{"short_id": "ssl_s3", "service": "listingmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "security-listing", "fee-collector", "accmgr", "clearing-account"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 4: Resolve Issuer Admin
-- Service: listingmgr
-- Purpose: Resolve the issuer's admin partner slot address from the issuer's legal structure
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'ssl_resolve_issuer_admin',
    'setup_security_listing',
    'Resolve Issuer Admin',
    'Query accmgr for the security issuer legal structure and extract the admin partner (partner 0) slot address from metadata.',
    '{"short_id": "ssl_s4", "service": "listingmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "security-listing", "issuer", "admin", "accmgr"]'::jsonb,
    '{"index": "4"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 5: Authorize Admin on Trading Engine
-- Service: listingmgr
-- Purpose: Add exchange's admin partner to trading engine's AuthzDiamond whitelist
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'ssl_authorize_admin_on_trading_engine',
    'setup_security_listing',
    'Authorize Admin on Trading Engine',
    'SimpleAuthzAddAccount: add exchange admin partner to trading engine AuthzDiamond so they can call createPairV2.',
    '{"short_id": "ssl_s5", "service": "listingmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "security-listing", "authz", "trading-engine", "laser", "on-chain"]'::jsonb,
    '{"index": "5"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 6: Authorize Engine on Security Treasury
-- Service: listingmgr
-- Purpose: Add trading engine to security treasury's AuthzDiamond whitelist
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'ssl_authorize_engine_on_security_treasury',
    'setup_security_listing',
    'Authorize Engine on Security Treasury',
    'SimpleAuthzAddAccount: add trading engine diamond to security treasury AuthzDiamond for transferVaultBalance access.',
    '{"short_id": "ssl_s6", "service": "listingmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "security-listing", "authz", "treasury", "security", "laser", "on-chain"]'::jsonb,
    '{"index": "6"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 7: Authorize Engine on Cash Treasury
-- Service: listingmgr
-- Purpose: Add trading engine to cash token treasury's AuthzDiamond whitelist
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'ssl_authorize_engine_on_cash_treasury',
    'setup_security_listing',
    'Authorize Engine on Cash Treasury',
    'SimpleAuthzAddAccount: add trading engine diamond to cash token treasury AuthzDiamond for transferVaultBalance access.',
    '{"short_id": "ssl_s7", "service": "listingmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "security-listing", "authz", "treasury", "cash-token", "laser", "on-chain"]'::jsonb,
    '{"index": "7"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 8: Create or Reuse Security Listing
-- Service: listingmgr
-- Purpose: Create a new SecurityListing record or reuse an existing one
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'ssl_create_or_reuse_security_listing',
    'setup_security_listing',
    'Create or Reuse Security Listing',
    'If a SecurityListing already exists for the security+currency pair, reuse it. Otherwise create a new one with Pending status.',
    '{"short_id": "ssl_s8", "service": "listingmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "security-listing", "create", "reuse"]'::jsonb,
    '{"index": "8"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 9: Create Calendar
-- Service: listingmgr
-- Purpose: Create a trading calendar for the security listing
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'ssl_create_calendar',
    'setup_security_listing',
    'Create Calendar',
    'Create an empty trading calendar and link it to the SecurityListing.',
    '{"short_id": "ssl_s9", "service": "listingmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "security-listing", "calendar", "trading"]'::jsonb,
    '{"index": "9"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 10: Create Pair On-Chain
-- Service: listingmgr
-- Purpose: Deploy trading pair on-chain via createPairV2 through LASER
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'ssl_create_pair_on_chain',
    'setup_security_listing',
    'Create Pair On-Chain',
    'Build ATS BoundFunc for createPairV2, submit async mutation to LASER, poll for completion, and extract agora_pair_id from PairCreate event.',
    '{"short_id": "ssl_s10", "service": "listingmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "security-listing", "pair", "createPairV2", "laser", "on-chain", "agora-engine"]'::jsonb,
    '{"index": "10"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 11: Create Deployment and Event Records
-- Service: listingmgr
-- Purpose: Create SecurityListingDeployment and SecurityListingEvent records
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'ssl_create_deployment_and_event_records',
    'setup_security_listing',
    'Create Deployment and Event Records',
    'Create SecurityListingDeployment (LASER_AND_AGORA type with agora_pair_id), SecurityListingEvent (LISTING_DEPLOYMENT type), and activate the SecurityListing.',
    '{"short_id": "ssl_s11", "service": "listingmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "security-listing", "deployment", "event", "record"]'::jsonb,
    '{"index": "11"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: register_investor_at_depositories
-- ============================================================================
-- Description: TRAX saga for registering an investor at all security
--              depositories by calling the create-sub-account endpoint
--              on each depository's REST endpoint.
-- Steps: 2
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'register_investor_at_depositories',
    'Register Investor at Depositories',
    'TRAX saga for registering an investor at all security depositories managed by sdmgr. Queries sdmgr for all depositories, then calls the create-sub-account endpoint on each depository''s REST endpoint with external_account_id = investor_iid. The endpoint is idempotent.',
    '{"short_id": "riad"}'::jsonb,
    '["agora", "prtagent", "saga", "workflow", "investor", "depository", "sub-account", "registration", "trax-flow"]'::jsonb,
    '{}'::jsonb,
    '["riad_verify_inputs", "riad_register_at_all_depositories"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: register_investor_at_depositories
-- ----------------------------------------------------------------------------

-- Step 1: Verify Inputs
-- Service: accmgr
-- Purpose: Validate that investor_iid exists in accmgr and belongs to the
--          authenticated participant.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'riad_verify_inputs',
    'register_investor_at_depositories',
    'Verify Investor Inputs',
    'Validate that investor_iid exists and belongs to the authenticated participant. Outputs participant_iid and external_investor_id for downstream steps.',
    '{"short_id": "riad_s1", "service": "accmgr"}'::jsonb,
    '["agora", "prtagent", "saga", "step", "investor", "validation", "workflow"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Register at All Depositories
-- Service: accmgr
-- Purpose: Query sdmgr for all security depositories, then for each depository's
--          active REST endpoint, call PUT /custodians/legal-structures/sub-accounts/create
--          with external_account_id = investor_iid. Uses per-endpoint auth config.
--          Accepts 201 (created) and 200/409 (already exists) as success.
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'riad_register_at_all_depositories',
    'register_investor_at_depositories',
    'Register at All Depositories',
    'Query sdmgr for all security depositories, call create-sub-account endpoint on each active REST endpoint. Uses per-endpoint auth config. Idempotent: 201=created, 200/409=already exists. Parses response to extract account_iid and ls_iid. After processing all depositories, stores CSD account IIDs in investor.Metadata["csd_accounts"] as a JSON object keyed by depository IID.',
    '{"short_id": "riad_s2", "service": "accmgr"}'::jsonb,
    '["agora", "prtagent", "saga", "step", "depository", "sub-account", "registration", "rest-call", "workflow"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: onboard_new_investor
-- ============================================================================
-- Description: Wrapper saga that creates a new investor under a participant,
--              registers them at all security depositories, and activates
--              LASER slots for the investor account. Spawns three sub-sagas:
--                1. new_investor_under_participant (creates investor, account, relations)
--                2. register_investor_at_depositories (registers at all sec depositories)
--                3. activate_laser_slots_for_fin_object (seeds LASER slots, writes ETH addr to account metadata)
--              Outputs from step 1 (investor_iid, account_iid) are merged into
--              subsequent steps via TRAX step-output-merge mechanism.
-- Steps: 3
-- Triggered by: prtagent gRPC NewInvestor(), accmgr REST POST /participant/{pid}/investor/new
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id,
    display_name,
    description,
    labels,
    tags,
    metadata,
    saga_step_template_ids
)
VALUES (
    'onboard_new_investor',
    'Onboard New Investor',
    'Wrapper saga that creates a new investor under a participant, registers them at all security depositories, and activates LASER slots for the investor account. Step 1 spawns new_investor_under_participant, step 2 spawns register_investor_at_depositories, step 3 spawns activate_laser_slots_for_fin_object. Outputs from step 1 are automatically merged into subsequent steps.',
    '{"short_id": "oni"}'::jsonb,
    '["agora", "prtagent", "saga", "workflow", "investor", "onboarding", "sub-saga", "trax-flow"]'::jsonb,
    '{}'::jsonb,
    '["oni_spawn_new_investor_saga", "oni_spawn_register_at_depositories_saga", "oni_spawn_activate_laser_slots_saga"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: onboard_new_investor
-- ----------------------------------------------------------------------------

-- Step 1: Spawn new_investor_under_participant sub-saga
-- Purpose: Create investor record, relations, account with LASER slots, and ETH address
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'oni_spawn_new_investor_saga',
    'onboard_new_investor',
    'Spawn New Investor Sub-Saga',
    'Spawns new_investor_under_participant as a sub-saga. Creates investor record, participant-to-investor relation, account with LASER slots, attaches ETH address, and creates investor-to-account relation. Outputs investor_iid for the next step.',
    '{"short_id": "oni_s1", "service": "accmgr"}'::jsonb,
    '["agora", "prtagent", "saga", "step", "investor", "sub-saga", "spawn", "creation"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Spawn register_investor_at_depositories sub-saga
-- Purpose: Register investor at all security depositories managed by sdmgr
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'oni_spawn_register_at_depositories_saga',
    'onboard_new_investor',
    'Spawn Register at Depositories Sub-Saga',
    'Spawns register_investor_at_depositories as a sub-saga. Receives investor_iid from step 1 output (merged by coordinator). Queries sdmgr for all depositories and registers the investor at each.',
    '{"short_id": "oni_s2", "service": "accmgr"}'::jsonb,
    '["agora", "prtagent", "saga", "step", "investor", "sub-saga", "spawn", "depository", "registration"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Spawn activate_laser_slots_for_fin_object sub-saga
-- Purpose: Activate LASER slots for the investor account, writing slot_address to account metadata
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'oni_spawn_activate_laser_slots_saga',
    'onboard_new_investor',
    'Spawn Activate LASER Slots Sub-Saga',
    'Spawns activate_laser_slots_for_fin_object as a sub-saga. Receives account_iid from step 1 output (merged by coordinator). Creates LASER slots for the investor account and writes the ETH address to account metadata.',
    '{"short_id": "oni_s3", "service": "accmgr"}'::jsonb,
    '["agora", "prtagent", "saga", "step", "investor", "sub-saga", "spawn", "laser", "slot", "activation"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- ============================================================================
-- SAGA TEMPLATE: create_direct_order
-- ============================================================================
-- Description: Submits a new trading order to an Agora Engine trading pair via
--              createExternallyIdentifiedBatchDirectOrderV2. Validates inputs,
--              resolves PLEGP, checks calendar, submits on-chain, and records
--              the order in listingmgr.
-- Steps: 3
-- ============================================================================

INSERT INTO trax.saga_templates (template_id, display_name, description, labels, tags, metadata, saga_step_template_ids)
VALUES (
    'create_direct_order',
    'Create Direct Order',
    'Submits a new direct trading order via createExternallyIdentifiedBatchDirectOrderV2 on Agora Engine',
    '{"short_id": "cdo"}'::jsonb,
    '["agora", "csd", "saga", "order", "direct-order", "trading", "listingmgr", "trax-flow"]'::jsonb,
    '{}'::jsonb,
    '["cdo_validate_and_resolve", "cdo_submit_order_on_chain", "cdo_create_order_record"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('cdo_validate_and_resolve', 'create_direct_order', 'Validate and Resolve', 'Validate order inputs, resolve SecurityListingDeployment for pair_id and trading mechanism, query PLEGP from accmgr, check calendar operating hours, resolve token decimals from instrmgr, and resolve PLEGP admin/authz slot addresses.', '{"short_id": "cdo_s1", "service": "listingmgr"}'::jsonb, '["agora", "csd", "saga", "step", "order", "validation", "resolve", "plegp", "calendar"]'::jsonb, '{"index": "1"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('cdo_submit_order_on_chain', 'create_direct_order', 'Submit Order On-Chain', 'Build ATS arguments from resolved data, submit LASER mutation for createExternallyIdentifiedBatchDirectOrderV2, parse DirectOrderCreate2 event to extract on-chain order_id and pair_id.', '{"short_id": "cdo_s2", "service": "listingmgr"}'::jsonb, '["agora", "csd", "saga", "step", "order", "laser", "on-chain", "agora-engine", "direct-order"]'::jsonb, '{"index": "2"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('cdo_create_order_record', 'create_direct_order', 'Create Order Record', 'Create Order record in listingmgr.orders with computed order_hash, denormalized token/chain info, and create initial OrderEvent (type=CREATE) in listingmgr.order_events.', '{"short_id": "cdo_s3", "service": "listingmgr"}'::jsonb, '["agora", "csd", "saga", "step", "order", "record", "order-event", "listingmgr"]'::jsonb, '{"index": "3"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;

-- ============================================================================
-- SAGA TEMPLATE: create_investor_order
-- ============================================================================
-- Description: Saga for creating an investor order via prtagent gRPC.
--              Validates inputs, creates order request record, verifies balance,
--              locks volume in order stash, transfers fee, submits to FIX venue.
-- Steps: 6
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
)
VALUES (
    'create_investor_order',
    'Create Investor Order',
    'Saga for creating an investor order: validate inputs, create order request, verify balance, lock volume, transfer fee, submit to FIX venue',
    '{"short_id": "cio"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "order", "investor", "fix", "trading"]'::jsonb,
    '{}'::jsonb,
    '["cio_validate_inputs", "cio_create_order_request", "cio_verify_balance", "cio_lock_order_volume", "cio_transfer_fee", "cio_submit_to_fix"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- Step 1: Validate Inputs
-- Service: prtagent
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'cio_validate_inputs',
    'create_investor_order',
    'Validate Investor Order Inputs',
    'Validate all gRPC request fields, resolve investor and participant CSD accounts, resolve vault addresses and cash token contract from legal structure, generate random order stash index.',
    '{"short_id": "cio_s1", "service": "prtagent"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "validation", "inputs", "order", "investor"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Create Order Request Record
-- Service: marketmgr
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'cio_create_order_request',
    'create_investor_order',
    'Create Order Request Record',
    'Insert order request record into marketmgr.order_requests with PENDING status. Append ORDER_REQUEST_CREATED event log. Compensation appends compensation events and sets status to COMPENSATED.',
    '{"short_id": "cio_s2", "service": "marketmgr"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "record", "order", "request", "marketmgr"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Verify Balance
-- Service: treassvc
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'cio_verify_balance',
    'create_investor_order',
    'Verify Investor Balance',
    'Query investor vault stash 0 (LIQUID) balance via LASER. Verify balance >= order volume + fee. Verify order stash has zero balance. Uses distributed lock on investor vault.',
    '{"short_id": "cio_s3", "service": "treassvc"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "balance", "verify", "treasury", "vault"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 4: Lock Order Volume
-- Service: treassvc
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'cio_lock_order_volume',
    'create_investor_order',
    'Lock Order Volume in Stash',
    'Transfer order volume from investor vault stash 0 to order stash via TrezorErc20TransferVaultBalance (admin facet, signed by clearing account). Compensation reverses the transfer.',
    '{"short_id": "cio_s4", "service": "treassvc"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "lock", "volume", "stash", "transfer", "treasury"]'::jsonb,
    '{"index": "4"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 5: Transfer Fee
-- Service: treassvc
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'cio_transfer_fee',
    'create_investor_order',
    'Transfer Fee to Clearing Account',
    'Transfer fee from investor vault stash 0 to clearing account vault stash 0 via TrezorErc20TransferVaultBalance (admin facet, signed by clearing account). Compensation reverses the transfer.',
    '{"short_id": "cio_s5", "service": "treassvc"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "fee", "transfer", "clearing", "treasury"]'::jsonb,
    '{"index": "5"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 6: Submit to FIX Venue
-- Service: marketmgr
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
)
VALUES (
    'cio_submit_to_fix',
    'create_investor_order',
    'Submit Order to FIX Venue',
    'Resolve venue from Redis cache, POST NewOrderSingle to fixclient REST API, update order request with FIX details. Compensation logs failure and sets status to REJECTED.',
    '{"short_id": "cio_s6", "service": "marketmgr"}'::jsonb,
    '["agora", "prtagent", "csd", "saga", "step", "fix", "venue", "submit", "order", "marketmgr"]'::jsonb,
    '{"index": "6"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- SAGA TEMPLATE: cancel_investor_order
-- ============================================================================
-- Description: Cancels an existing investor order by sending FIX
--              OrderCancelRequest to the venue via fixclient.
-- Steps: 3
-- ============================================================================

INSERT INTO trax.saga_templates (template_id, display_name, description, labels, tags, metadata, saga_step_template_ids)
VALUES (
    'cancel_investor_order',
    'Cancel Investor Order',
    'Cancels an existing investor order by sending FIX OrderCancelRequest to the venue via fixclient.',
    '{"short_id": "cioc"}'::jsonb,
    '["agora", "csd", "saga", "order", "cancel-investor-order", "trading", "prtagent", "marketmgr", "trax-flow"]'::jsonb,
    '{}'::jsonb,
    '["cioc_validate_and_resolve", "cioc_update_order_request", "cioc_submit_cancel_to_fix"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- Step 1: Validate and Resolve
-- Service: prtagent
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('cioc_validate_and_resolve', 'cancel_investor_order', 'Validate and Resolve',
    'Validate external_order_id, query marketmgr for order_request, check cancellable status.',
    '{"short_id": "cioc_s1", "service": "prtagent"}'::jsonb,
    '["agora", "csd", "saga", "step", "order", "cancel", "validation"]'::jsonb,
    '{"index": "1"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;

-- Step 2: Update Order Request
-- Service: marketmgr
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('cioc_update_order_request', 'cancel_investor_order', 'Update Order Request',
    'Update order_request status to CANCEL_SUBMISSION_PENDING.',
    '{"short_id": "cioc_s2", "service": "marketmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "order", "cancel", "update"]'::jsonb,
    '{"index": "2"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;

-- Step 3: Submit Cancel to FIX
-- Service: marketmgr
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('cioc_submit_cancel_to_fix', 'cancel_investor_order', 'Submit Cancel to FIX',
    'Generate cancel_cl_ord_id, POST to fixclient, update status to CANCEL_SUBMITTED.',
    '{"short_id": "cioc_s3", "service": "marketmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "order", "cancel", "fix", "submit"]'::jsonb,
    '{"index": "3"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;