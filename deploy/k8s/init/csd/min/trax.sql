-- ============================================================================
-- CSD TRAX Saga Templates
-- ============================================================================
-- Purpose: TRAX saga templates for CSD (Central Securities Depository) namespace
-- Usage: ./deploy data min-records --cluster-id <cluster> --ns csd
--
-- Contains:
--   - process_new_instrument_authorization (11 steps)
--   - activate_laser_slots_for_fin_object (2 steps)
--   - transfer_authorized_instrument (2 steps)
--   - establish_new_legal_structure_for_participant (12 steps)
--   - deploy_core_legal_mechanisms_for_legal_structure (10 steps)
--   - deploy_treasury_legal_mechanisms_for_legal_structure (18 steps)
--   - setup_new_legal_participant (7 steps)
--   - setup_new_custodian_participant (2 steps)
--   - create_custodian_sub_account (5 steps)
--   - setup_security_listing (11 steps)
-- ============================================================================

\c agora_db;

-- ============================================================================
-- TRAX CLUSTER
-- ============================================================================

-- CSD Cluster - Central Securities Depository operations
INSERT INTO trax.clusters (id, display_name, description, labels, tags, metadata)
VALUES (
    'CSD',
    'CSD Cluster',
    'TRAX cluster for Central Securities Depository operations including instrument authorization, legal structures, and treasury mechanisms',
    '{"env": "local", "namespace": "csd"}'::jsonb,
    '["agora", "csd", "trax", "cluster"]'::jsonb,
    '{"created_by": "csd_min_init"}'::jsonb
)
ON CONFLICT (id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: process_new_instrument_authorization
-- ============================================================================
-- Description: TRAX flow for processing new instrument authorization using
--              Diamond+Facet pattern. Deploys Diamond, adds LaserErc20Facet,
--              initializes token, approves treasury, deposits to treasury, and creates record.
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
-- Purpose: Clearing account approves treasury vault to spend ERC20 tokens for deposit.
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
-- Purpose: Amend treasury vault link metadata with authorized_instrument_iid from step 9.
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
-- Service: laseragent
-- Purpose: Stamp authorized_instrument_iid into the authz-instr's own
-- ERC20 Diamond inner slot metadata so the treasury indexer can
-- resolve activities emitted by the authz-instr's contract back to
-- the authz-instr iid. Per-authz-instr slot — no shared-claim
-- conflict. ref_seed is left untouched (immutable in lasersvc).
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
-- Service: lasersvc
-- Purpose: Create LASER Slots for the financial object
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
-- Service: accmgr
-- Purpose: Attach the ETH address to the financial object's metadata
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
-- Purpose: Transfer tokens from one account to another
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
-- Purpose: Validate account balances after the transfer is complete
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
-- Steps: 12
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
-- Service: accmgr
-- Purpose: Validate inputs, verify participants exist and are enabled
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
-- Service: accmgr
-- Purpose: Create LegalStructure and ParticipantList records
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
-- Service: accmgr
-- Purpose: Create custody account and legal-structure-to-account relation
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
    'Create custody account and legal-structure-to-account relation. Conditional: only runs when force_creation_of_custody_account=true.',
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
-- Service: lasersvc
-- Purpose: Create SIGNER LASER slots for custody account (conditional on force_creation_of_custody_account)
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
    'Create SIGNER LASER slots for custody account. Conditional: only runs when force_creation_of_custody_account=true.',
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
-- Service: accmgr
-- Purpose: Attach ETH address to custody account and set status to ACTIVE (conditional on force_creation_of_custody_account)
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
    'Attach ETH address to custody account and set status to ACTIVE. Conditional: only runs when force_creation_of_custody_account=true.',
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
-- Service: accmgr
-- Purpose: Create accounts and relations for all partner participants
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
-- Service: lasersvc
-- Purpose: Create SIGNER-tagged LASER slots for all partner accounts
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
-- Service: accmgr
-- Purpose: Attach ETH addresses to partner accounts and set status to ACTIVE
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
-- Service: accmgr
-- Purpose: Create clearing account and LegalStructureToAccountRelation for the legal structure itself
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
-- Service: lasersvc
-- Purpose: Create SIGNER-tagged LASER slots for clearing account
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
-- Service: accmgr
-- Purpose: Attach ETH address to clearing account and set status to ACTIVE
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
-- Service: accmgr
-- Purpose: Persist typed participant↔LS roles (CEO, BOARD_MEMBER, …)
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
    'create_participant_to_legal_structure_relations',
    'establish_new_legal_structure_for_participant',
    'Create Participant-to-Legal-Structure Relations',
    'Persist typed participant↔legal-structure roles (CEO, BOARD_MEMBER, COMPLIANCE_OFFICER, …) declared on each partner. No-op when no partner declared a relation.',
    '{"short_id": "cptlsr", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "legal-structure", "participant", "relation", "role", "workflow"]'::jsonb,
    '{"index": "12"}'::jsonb
)
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
-- Service: accmgr
-- Purpose: Validate inputs, verify legal structure exists and is PARTNERSHIP type,
--          verify deployer and all partner accounts have SIGNER slots,
--          verify authz_source_diamond_admins and authz_admins have no overlap
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
-- Service: accmgr
-- Purpose: Create LegalMechanism record with type=VOTING, LegalStructureIid,
--          and DisplayNames using prefix+locale. Store slot_address = {prefix}-TaskManager in metadata.
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
-- Service: accmgr
-- Purpose: Create LegalMechanism record with type=AUTHORISATION_SOURCE, LegalStructureIid.
--          Store slot_address = {prefix}-AuthzSource in metadata.
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
-- Service: lasersvc
-- Purpose: Deploy TaskManagerV2 via LASER using deployer signer.
--          All partners are admins, approvers, and executors. Returns task_manager_contract_address.
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
-- Service: accmgr
-- Purpose: Create LegalMechanismDeployment with type=LASER, linking to TaskManager mechanism,
--          with contract address from step 4.
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
-- Service: lasersvc
-- Purpose: Deploy AuthzDiamond via LASER using deployer signer.
--          Returns authz_diamond_contract_address.
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
-- Service: accmgr
-- Purpose: Create LegalMechanismDeployment with type=LASER, linking to AuthzSource mechanism,
--          with contract address from step 6.
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
-- Service: lasersvc
-- Purpose: Initialize AuthzDiamond with TaskManager reference, authz_source_diamond_admins,
--          and authz_admins. Uses deployer as signer.
-- NOTE: Initialize MUST come before AddAuthzFacet because the diamond needs
--       to be initialized with TaskManager reference before facets can be added.
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
-- Service: lasersvc
-- Purpose: Add AuthzFacet to AuthzDiamond using first authz_source_diamond_admin as signer.
--          Returns add_facet_tx_hash.
-- NOTE: deploy_authz_facet was REMOVED - facets must be pre-deployed as infrastructure.
--       This step uses a well-known facet slot address (e.g., "SimpleAuthzFacet:v1").
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
-- Service: accmgr
-- Purpose: Validate inputs, verify Core Legal Mechanisms exist, verify no Treasury mechanisms exist,
--          verify admin_partner is partner + TM admin, verify authz_admin is AuthzDiamond admin,
--          verify deployer has SIGNER slot.
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
-- Service: accmgr
-- Purpose: Create LegalMechanism record with type=RESOURCE_ACCESS_CONTROLLER, LegalStructureIid.
--          Store slot_address = {prefix}-RAC in metadata.
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
-- Service: accmgr
-- Purpose: Create LegalMechanism record with type=TREASURY, LegalStructureIid.
--          Store slot_address = {prefix}-Trezor in metadata.
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
-- Service: lasersvc
-- Purpose: Deploy RAC Diamond via LASER using deployer signer.
--          Contract name = {prefix}-RAC. Returns rac_diamond_contract_address.
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
-- Service: lasersvc
-- Purpose: Initialize RAC Diamond with admin_partner_slot_address as admin. Uses deployer as signer.
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
-- Service: lasersvc
-- Purpose: authz_admin grants addFacets(address[]) permission to admin_partner on RAC Diamond.
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
-- Service: lasersvc
-- Purpose: admin_partner adds RAC facet (from lattice using rac_facet_version) to RAC Diamond.
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
-- Service: accmgr
-- Purpose: Create LegalMechanismDeployment with type=LASER, linking to RAC mechanism,
--          with contract address from step 4.
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
-- Service: lasersvc
-- Purpose: Deploy Trezor Diamond via LASER using deployer signer.
--          Contract name = {prefix}-Trezor. Returns trezor_diamond_contract_address.
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
-- Service: lasersvc
-- Purpose: Initialize Trezor Diamond with admin_partner_slot_address as admin. Uses deployer as signer.
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
-- Service: lasersvc
-- Purpose: authz_admin grants addFacets(address[]) permission to admin_partner on Trezor Diamond.
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
-- Service: lasersvc
-- Purpose: admin_partner adds 7 vault facets to Trezor Diamond:
--          erc20-vault-admin, erc20-vault, ledger-lister, rbac, props, activity-store, eth-vault.
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
-- Service: lasersvc
-- Purpose: authz_admin grants createLedger permission to admin_partner on Trezor Diamond.
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
-- Service: lasersvc
-- Purpose: admin_partner creates DEFAULT ledger (non-slave, id=1) on Trezor Diamond via createLedger function.
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
-- Service: lasersvc
-- Purpose: authz_admin grants setAddress permission to admin_partner on Trezor Diamond.
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
-- Service: lasersvc
-- Purpose: authz_admin grants setInt permission to admin_partner on Trezor Diamond.
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
-- Service: lasersvc
-- Purpose: admin_partner configures Trezor Diamond: setInt('rac.domain.id', 999)
--          and setAddress('rac.address', rac_diamond_contract_address).
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
-- Service: lasersvc
-- Purpose: CRITICAL: Grant Trezor Diamond access to call protected functions on RAC Diamond.
--          Without this step, Fund Account saga will fail with DMND:NAUTH when Trezor
--          calls rac.updateResourceQuota() during vault operations.
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
-- Service: accmgr
-- Purpose: Create LegalMechanismDeployment with type=LASER, linking to Treasury mechanism,
--          with Trezor contract address from step 9.
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
-- Service: accmgr
-- Purpose: Validate inputs, verify Core Legal Mechanisms exist, verify no Trading mechanisms exist,
--          verify admin_partner is partner + TM admin, verify authz_admin is AuthzDiamond admin,
--          verify deployer has SIGNER slot, verify all facet versions provided.
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
-- Service: accmgr
-- Purpose: Create LegalMechanism record with type=TRADING, slot_address = {prefix}-AgoraEngine.
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
-- Service: laseragent
-- Purpose: Deploy Agora Engine Diamond via LASER using deployer. Contract name = {prefix}-AgoraEngine.
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
-- Service: laseragent
-- Purpose: Initialize Agora Engine Diamond with admin_partner as admin, AuthzSource, TaskManager, authzDomain="AGORA_ENGINE".
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
-- Service: laseragent
-- Purpose: authz_admin grants addFacets permission to admin_partner on Agora Engine diamond via SimpleAuthzAddAccount.
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
-- Service: laseragent
-- Purpose: admin_partner adds 10 facets to Agora Engine diamond: RBAC, Props, AgoraEngine, TradeManager,
--          PairManager, OfferManager, Matcher, OrderStats, DirectOrderManager, DirectOrderV2+V2Query.
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
-- Service: laseragent
-- Purpose: authz_admin grants setAddress permission to admin_partner on Agora Engine diamond via SimpleAuthzAddAccount.
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
-- Service: laseragent
-- Purpose: admin_partner sets MatcherAlgo and SettlerAlgo facet addresses as properties on Agora Engine
--          diamond via DIAMOND_PROPS_SET_ADDRESS (PropsFacet.setAddress).
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
-- Service: accmgr
-- Purpose: Create LegalMechanismDeployment with type=LASER, linking to Trading Engine mechanism,
--          with Agora Engine contract address from step 3.
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
-- Description: TRAX saga for setting up a complete Legal Participant with
--              partners, legal structure, core mechanisms, treasury mechanisms,
--              trading engine mechanisms, cash tokens, and API key
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
-- Service: accmgr
-- Purpose: Create participant record for the Legal Participant with provided or
--          auto-generated IID, display names, descriptions, types, and identifiers.
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
-- Service: accmgr
-- Purpose: Create new partner participant records (if create_new=true) or
--          validate existing participants (if create_new=false).
--          Verify deployer is in partners list.
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
-- Service: accmgr
-- Purpose: Submit establish_new_legal_structure_for_participant sub-saga and wait for completion.
--          Creates PARTNERSHIP legal structure with owner, partner, and clearing accounts.
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
-- SAGA TEMPLATE: setup_new_custodian_participant
-- ============================================================================
-- Description: TRAX saga for setting up a Custodian Participant. Spawns
--              setup_new_legal_participant as sub-saga (no treasury, no cash
--              tokens, no trading), resolves the custody account created by the
--              sub-saga chain, and links the custody account to the PLS.
--              LASER slots and ETH address are handled by the sub-saga chain
--              (establish_new_legal_structure_for_participant).
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
    'setup_new_custodian_participant',
    'Setup New Custodian Participant',
    'TRAX saga for setting up a Custodian Participant. Spawns setup_new_legal_participant as sub-saga (no treasury, no cash tokens, no trading), resolves the custody account from the sub-saga, and links to PLS.',
    '{"short_id": "sncp"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "custodian", "participant", "legal-structure", "custody-account", "trax-flow"]'::jsonb,
    '{}'::jsonb,
    '["sncp_spawn_setup_legal_participant_saga", "sncp_link_custody_to_pls"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: setup_new_custodian_participant
-- ----------------------------------------------------------------------------

-- Step 1: Spawn Setup Legal Participant Saga + Resolve Custody Account
-- Service: accmgr
-- Purpose: Submit setup_new_legal_participant sub-saga and wait for completion.
--          Creates custodian participant with partners, legal structure, core
--          mechanisms, and API key. No treasury, no cash tokens, no trading.
--          After sub-saga completes, resolves the custody account created by the
--          establish_new_legal_structure_for_participant sub-saga via
--          CUSTODY_ACCOUNT relation on the legal structure.
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
    'sncp_spawn_setup_legal_participant_saga',
    'setup_new_custodian_participant',
    'Spawn Setup Legal Participant Saga',
    'Submit setup_new_legal_participant sub-saga and wait for completion. Creates custodian participant with partners, legal structure, core mechanisms, and API key. Resolves custody_account_iid from the legal structure CUSTODY_ACCOUNT relation.',
    '{"short_id": "sncp_s1", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "custodian", "sub-saga", "legal-participant", "spawn", "workflow"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Link Custody Account to PLS
-- Service: accmgr
-- Purpose: Create a PARENT_CHILD account-to-account relation between the PLS's
--          custody account (parent) and the custodian's custody account (child).
--          Queries configmgr for PLS IID and resolves custody account from LS metadata.
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
    'sncp_link_custody_to_pls',
    'setup_new_custodian_participant',
    'Link Custody Account to PLS',
    'Create a PARENT_CHILD account-to-account relation between the PLS custody account (parent) and the custodian custody account (child). Queries configmgr for PLS IID and resolves custody account from legal structure metadata.',
    '{"short_id": "sncp_s2", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "custodian", "custody-account", "parent-child", "relation", "pls", "workflow"]'::jsonb,
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

-- Step 1: Verify Inputs
-- Service: accmgr
-- Purpose: Validate legal structure ownership, custody account existence, and
--          uniqueness of (participant_iid, external_account_id) combination.
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

-- Step 2: Create Sub-Account
-- Service: accmgr
-- Purpose: Create Account (type=Client, status=PENDING) with external_account_id.
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

-- Step 3: Create Parent-Child Relation
-- Service: accmgr
-- Purpose: Create AccountToAccountRelation (PARENT_CHILD) linking the custody
--          account (parent/from) to the new sub-account (child/to).
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

-- Step 4: Create LASER Slots
-- Service: laseragent
-- Purpose: Create non-signer LASER slots for the sub-account (tags=nil).
--          Uses account_iid as slot address seed. Outputs eth_address.
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

-- Step 5: Attach ETH Address and Activate
-- Service: accmgr
-- Purpose: Attach Ethereum address from LASER slot creation as FinIdentifier
--          (scheme=ethereum, EIP-55) and set account status to ACTIVE.
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
--          This is required for both deploy_cash_token (initial deposit) and fund_account_with_cash_tokens saga.
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
-- Purpose: Deposit minted tokens to Treasury vault for clearing account.
--          Uses TrezorErc20DepositToVault to record balance in Treasury's vault accounting.
--          Required for fund_account_with_cash_tokens saga to transfer tokens via vault-to-vault.
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
    'Deposit minted tokens to Treasury vault for clearing account. First approves Treasury to spend tokens, then deposits via TrezorErc20DepositToVault. Skip if initial_amount is 0.',
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

-- Step 16: Claim AuthzInstr ERC20 Diamond via Metadata
-- Service: lasersvc (laseragent executor)
-- Purpose: Stamp the authz-instr iid into the cash-token's own
-- ERC20 Diamond inner slot metadata so the treasury indexer can
-- resolve activities emitted by the cash-token's contract back to
-- the authz-instr iid even when the slot's immutable `ref_seed`
-- was left empty at deploy time.
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
-- SAGA TEMPLATE: withdraw_cash_tokens_from_account
-- ============================================================================
-- Description: Saga for withdrawing cash tokens from an investor account
--              back to the clearing account via Treasury vault operations.
-- Steps: 6
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
)
VALUES (
    'withdraw_cash_tokens_from_account',
    'Withdraw Cash Tokens From Account',
    'Saga for withdrawing cash tokens from an investor account: transfer to clearing, withdraw from vault, burn tokens, verify balances',
    '{"short_id": "wcfa"}'::jsonb,
    '["agora", "csd", "saga", "account", "cash", "token", "treasury", "withdrawal"]'::jsonb,
    '{}'::jsonb,
    '["wcfa_verify_inputs", "wcfa_query_account_balance", "wcfa_transfer_to_clearing", "wcfa_withdraw_and_burn", "wcfa_verify_balances", "wcfa_create_withdrawal_record"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('wcfa_verify_inputs', 'withdraw_cash_tokens_from_account', 'Verify Withdrawal Inputs', 'Validate all inputs and gather contract addresses for withdrawal operation.', '{"short_id": "wcfa_s1", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "verify", "withdrawal", "accmgr"]'::jsonb, '{"index": "1"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('wcfa_query_account_balance', 'withdraw_cash_tokens_from_account', 'Query Account Vault Balance', 'Query investor account vault LIQUID balance before withdrawal. Validate sufficient balance. Acquire distributed lock.', '{"short_id": "wcfa_s2", "service": "treassvc"}'::jsonb, '["agora", "csd", "saga", "step", "query", "balance", "vault", "treassvc"]'::jsonb, '{"index": "2"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('wcfa_transfer_to_clearing', 'withdraw_cash_tokens_from_account', 'Transfer From Account To Clearing', 'Execute TrezorErc20TransferFromVault from investor account vault to clearing vault.', '{"short_id": "wcfa_s3", "service": "treassvc"}'::jsonb, '["agora", "csd", "saga", "step", "transfer", "vault", "treasury", "treassvc"]'::jsonb, '{"index": "3"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('wcfa_withdraw_and_burn', 'withdraw_cash_tokens_from_account', 'Withdraw From Vault And Burn', 'Withdraw tokens from clearing vault to ERC20 balance, then burn them using deployer BURNER_ROLE.', '{"short_id": "wcfa_s4", "service": "treassvc"}'::jsonb, '["agora", "csd", "saga", "step", "withdraw", "burn", "vault", "erc20", "treassvc"]'::jsonb, '{"index": "4"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('wcfa_verify_balances', 'withdraw_cash_tokens_from_account', 'Verify Post Transfer Balances', 'Verify vault balances after withdrawal transfer. Release distributed lock.', '{"short_id": "wcfa_s5", "service": "treassvc"}'::jsonb, '["agora", "csd", "saga", "step", "verify", "balance", "vault", "treassvc"]'::jsonb, '{"index": "5"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('wcfa_create_withdrawal_record', 'withdraw_cash_tokens_from_account', 'Create Withdrawal Record', 'Create AccountFunding record (type=WITHDRAWAL) for audit trail.', '{"short_id": "wcfa_s6", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "record", "withdrawal", "account", "audit"]'::jsonb, '{"index": "6"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;


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
-- SAGA TEMPLATE: create_direct_order
-- ============================================================================
-- Description: Submits a new trading order to an Agora Engine trading pair via
--              createExternallyIdentifiedBatchDirectOrderV2. Validates inputs,
--              resolves PLEGP, checks calendar, submits on-chain, and records
--              the order in listingmgr.
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

-- ----------------------------------------------------------------------------
-- Steps for: create_direct_order
-- ----------------------------------------------------------------------------

-- Step 1: Validate and Resolve
-- Service: listingmgr
-- Purpose: Validate all inputs, resolve SecurityListingDeployment, extract pair_id
--          and trading mechanism, query PLEGP, check calendar, resolve token decimals,
--          resolve PLEGP admin/authz slot addresses.
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
    'cdo_validate_and_resolve',
    'create_direct_order',
    'Validate and Resolve',
    'Validate order inputs, resolve SecurityListingDeployment for pair_id and trading mechanism, query PLEGP from accmgr, check calendar operating hours, resolve token decimals from instrmgr, and resolve PLEGP admin/authz slot addresses.',
    '{"short_id": "cdo_s1", "service": "listingmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "order", "validation", "resolve", "plegp", "calendar"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Submit Order On-Chain
-- Service: listingmgr
-- Purpose: Build ATS arguments, submit LASER mutation for
--          createExternallyIdentifiedBatchDirectOrderV2, parse DirectOrderCreate2 event
--          to extract order_id and pair_id.
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
    'cdo_submit_order_on_chain',
    'create_direct_order',
    'Submit Order On-Chain',
    'Build ATS arguments from resolved data, submit LASER mutation for createExternallyIdentifiedBatchDirectOrderV2, parse DirectOrderCreate2 event to extract on-chain order_id and pair_id.',
    '{"short_id": "cdo_s2", "service": "listingmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "order", "laser", "on-chain", "agora-engine", "direct-order"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Create Order Record
-- Service: listingmgr
-- Purpose: Create Order record in listingmgr.orders, create initial OrderEvent
--          (type=CREATE), compute order_hash, store all denormalized fields.
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
    'cdo_create_order_record',
    'create_direct_order',
    'Create Order Record',
    'Create Order record in listingmgr.orders with computed order_hash, denormalized token/chain info, and create initial OrderEvent (type=CREATE) in listingmgr.order_events.',
    '{"short_id": "cdo_s3", "service": "listingmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "order", "record", "order-event", "listingmgr"]'::jsonb,
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
-- SAGA TEMPLATE: cancel_direct_order
-- ============================================================================
INSERT INTO trax.saga_templates (template_id, display_name, description, labels, tags, metadata, saga_step_template_ids)
VALUES (
    'cancel_direct_order',
    'Cancel Direct Order',
    'Cancels an existing direct order on-chain via cancelExternallyIdentifiedDirectOrder on Agora Engine. Validates order is cancellable, submits LASER mutation, updates order record.',
    '{"short_id": "cdoc"}'::jsonb,
    '["agora", "csd", "saga", "order", "cancel-order", "trading", "listingmgr", "trax-flow"]'::jsonb,
    '{}'::jsonb,
    '["cdoc_validate_and_resolve", "cdoc_submit_cancel_on_chain", "cdoc_update_order_record"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES (
    'cdoc_validate_and_resolve',
    'cancel_direct_order',
    'Validate and Resolve',
    'Look up order by external_oid, validate cancellable status, resolve SecurityListingDeployment, resolve PLEGP exchange clearing account.',
    '{"short_id": "cdoc_s1", "service": "listingmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "order", "cancel", "validation", "resolve", "plegp"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES (
    'cdoc_submit_cancel_on_chain',
    'cancel_direct_order',
    'Submit Cancel On-Chain',
    'Build ATS function call for cancelExternallyIdentifiedDirectOrder, submit LASER async mutation, poll for tx completion.',
    '{"short_id": "cdoc_s2", "service": "listingmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "order", "cancel", "on-chain", "laser", "mutation"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES (
    'cdoc_update_order_record',
    'cancel_direct_order',
    'Update Order Record',
    'Update order status to CANCELED in listingmgr.orders, create Cancel OrderEvent in listingmgr.order_events.',
    '{"short_id": "cdoc_s3", "service": "listingmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "order", "cancel", "record", "event"]'::jsonb,
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
-- SAGA TEMPLATE: fund_account_with_authorized_instrument
-- ============================================================================
-- Description: Generic saga for funding an account with any authorized instrument (ERC20)
-- Steps: 6
-- Services: treassvc (all steps)
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
    'fund_account_with_authorized_instrument',
    'Fund Account With Authorized Instrument',
    'Generic saga for funding an account with any ERC20 authorized instrument. Accepts pre-resolved addresses (clearing, destination, treasury, erc20). Mints if needed, transfers from clearing to destination vault.',
    '{"short_id": "fawai"}'::jsonb,
    '["agora", "csd", "saga", "account", "authorized-instrument", "treasury", "funding", "generic"]'::jsonb,
    '{}'::jsonb,
    '["fawai_query_source_balance", "fawai_mint_tokens_if_needed", "fawai_query_destination_balance", "fawai_transfer_to_destination", "fawai_verify_balances", "fawai_amend_vault_link_metadata"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: fund_account_with_authorized_instrument
-- ----------------------------------------------------------------------------

-- Step 1: Query Source Vault Balance
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
    'fawai_query_source_balance',
    'fund_account_with_authorized_instrument',
    'Query Source Vault Balance',
    'Acquire distributed lock and query clearing account vault LIQUID balance via TrezorErc20GetVaultBalance. Validate balance if use_clearing_balance=true.',
    '{"short_id": "fawai_s1", "service": "treassvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "query", "treasury", "vault", "balance"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Mint Tokens If Needed
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
    'fawai_mint_tokens_if_needed',
    'fund_account_with_authorized_instrument',
    'Mint Tokens If Needed',
    'Conditionally mint new tokens to clearing account if use_clearing_balance=false. Execute Erc20MintTo, Erc20Approve, TrezorErc20DepositToVault.',
    '{"short_id": "fawai_s2", "service": "treassvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "mint", "erc20", "treasury", "deposit"]'::jsonb,
    '{"index": "2"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Query Destination Vault Balance
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
    'fawai_query_destination_balance',
    'fund_account_with_authorized_instrument',
    'Query Destination Vault Balance',
    'Query destination account vault LIQUID balance before transfer via TrezorErc20GetVaultBalance.',
    '{"short_id": "fawai_s3", "service": "treassvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "query", "treasury", "vault", "balance", "destination"]'::jsonb,
    '{"index": "3"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 4: Transfer From Clearing To Destination
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
    'fawai_transfer_to_destination',
    'fund_account_with_authorized_instrument',
    'Transfer From Clearing To Destination',
    'Execute TrezorErc20TransferFromVault from clearing vault to destination vault. Amount is transferred from LIQUID stash.',
    '{"short_id": "fawai_s4", "service": "treassvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "transfer", "treasury", "vault", "erc20"]'::jsonb,
    '{"index": "4"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 5: Verify Post Transfer Balances
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
    'fawai_verify_balances',
    'fund_account_with_authorized_instrument',
    'Verify Post Transfer Balances',
    'Verify vault balances after transfer. Source decreased by amount, destination increased by amount. Releases distributed lock.',
    '{"short_id": "fawai_s5", "service": "treassvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "verify", "treasury", "vault", "balance"]'::jsonb,
    '{"index": "5"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 6: Amend Vault Link Metadata
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
    'fawai_amend_vault_link_metadata',
    'fund_account_with_authorized_instrument',
    'Amend Vault Link Metadata',
    'Amend treasury vault link metadata with authorized_instrument_iid. New links created during transfer may lack authorized_instrument_iid. Copies it from existing links set during deployment.',
    '{"short_id": "fawai_s6", "service": "treassvc"}'::jsonb,
    '["agora", "csd", "saga", "step", "amend", "treasury", "vault", "link", "metadata"]'::jsonb,
    '{"index": "6"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- ============================================================================
-- SAGA TEMPLATE: fund_account_with_security_tokens
-- ============================================================================
-- Description: Wrapper saga for funding an account with security tokens
-- Steps: 2
-- Services: accmgr (all steps)
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
    'fund_account_with_security_tokens',
    'Fund Account With Security Tokens',
    'Wrapper saga that resolves security mechanism addresses from authorized_instrument_iid, then spawns fund_account_with_authorized_instrument sub-saga with pre-resolved addresses.',
    '{"short_id": "fawst"}'::jsonb,
    '["agora", "csd", "saga", "account", "security", "token", "funding", "wrapper"]'::jsonb,
    '{}'::jsonb,
    '["fawst_verify_inputs", "fawst_spawn_fund"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: fund_account_with_security_tokens
-- ----------------------------------------------------------------------------

-- Step 1: Verify Inputs and Resolve Security Mechanism Addresses
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
    'fawst_verify_inputs',
    'fund_account_with_security_tokens',
    'Verify Inputs and Resolve Security Mechanism',
    'Validate inputs, resolve security mechanism addresses by matching authorized_instrument_iid in legal mechanism metadata. Extract treasury, ERC20, deployer, clearing, and destination addresses.',
    '{"short_id": "fawst_s1", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "validation", "inputs", "security", "mechanism", "resolve"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Spawn Fund Account With Authorized Instrument Sub-Saga
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
    'fawst_spawn_fund',
    'fund_account_with_security_tokens',
    'Spawn Fund Account Sub-Saga',
    'Spawn fund_account_with_authorized_instrument sub-saga with pre-resolved addresses from step 1. Blocks until sub-saga commits or compensates.',
    '{"short_id": "fawst_s2", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "spawn", "sub-saga", "fund", "authorized-instrument"]'::jsonb,
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
-- SAGA TEMPLATE: fund_csd_accounts
-- ============================================================================
-- Description: Batch saga for funding multiple CSD accounts
-- Steps: 2
-- Services: accmgr (all steps)
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
    'fund_csd_accounts',
    'Fund CSD Accounts (Batch)',
    'Batch saga that funds multiple accounts sequentially. Receives parallel accounts[] and amounts[] arrays. Spawns fund_account_with_cash_tokens or fund_account_with_security_tokens sub-sagas per account.',
    '{"short_id": "fcsdacc"}'::jsonb,
    '["agora", "csd", "saga", "batch", "account", "funding", "custodian"]'::jsonb,
    '{}'::jsonb,
    '["fcsdacc_verify_and_resolve", "fcsdacc_fund_accounts"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

-- ----------------------------------------------------------------------------
-- Steps for: fund_csd_accounts
-- ----------------------------------------------------------------------------

-- Step 1: Verify and Resolve Batch Inputs
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
    'fcsdacc_verify_and_resolve',
    'fund_csd_accounts',
    'Verify and Resolve Batch Inputs',
    'Parse JSON arrays for accounts[] and amounts[], validate lengths match, verify all accounts exist and are ACTIVE, verify legal structure exists.',
    '{"short_id": "fcsdacc_s1", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "validation", "batch", "accounts", "resolve"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Fund Accounts Sequentially
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
    'fcsdacc_fund_accounts',
    'fund_csd_accounts',
    'Fund Accounts Sequentially',
    'Sequential loop spawning sub-sagas per account. fund_type=cash_token spawns fund_account_with_cash_tokens, fund_type=security_token spawns fund_account_with_security_tokens. Each sub-saga blocks until complete.',
    '{"short_id": "fcsdacc_s2", "service": "accmgr"}'::jsonb,
    '["agora", "csd", "saga", "step", "spawn", "sub-saga", "sequential", "batch", "fund"]'::jsonb,
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
    'Transfer order volume from investor vault stash 0 to order stash via TrezorErc20TransferFromVault. Compensation reverses the transfer.',
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
    'Transfer fee from investor vault stash 0 to clearing account vault stash 0 via TrezorErc20TransferFromVault. Compensation reverses the transfer.',
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