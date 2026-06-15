-- ============================================================================
-- EXCHANGE TRAX Saga Templates
-- ============================================================================
-- Purpose: TRAX saga templates for EXCHANGE namespace
-- Usage: ./deploy data min-records --cluster-id <cluster> --ns exchange
--
-- Contains ALL CSD/shared templates:
--     - process_new_instrument_authorization (8 steps)
--     - activate_laser_slots_for_fin_object (2 steps)
--     - transfer_authorized_instrument (2 steps)
--     - establish_new_legal_structure_for_participant (12 steps)
--     - deploy_core_legal_mechanisms_for_legal_structure (10 steps)
--     - deploy_treasury_legal_mechanisms_for_legal_structure (19 steps)
--     - deploy_trading_legal_mechanisms_for_legal_structure (9 steps)
--     - setup_new_legal_participant (9 steps)
--     - deploy_cash_token_legal_mechanism_for_legal_structure (15 steps)
--     - fund_account_with_cash_tokens (7 steps)
--     - setup_security_listing (11 steps)
-- ============================================================================

\c agora_db;


-- ############################################################################
-- ############################################################################
-- ##                                                                        ##
-- ##                    CSD / SHARED SAGA TEMPLATES                         ##
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
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
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
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
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
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
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
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
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
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
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
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
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
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
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
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
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
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
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
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
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
    template_id, saga_template_id, display_name, description, labels, tags, metadata
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
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
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

-- Step 1: Create LASER Slots
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
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
    template_id, saga_template_id, display_name, description, labels, tags, metadata
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
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
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

-- Step 1: Transfer Tokens
INSERT INTO trax.saga_step_templates (
    template_id, saga_template_id, display_name, description, labels, tags, metadata
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
    template_id, saga_template_id, display_name, description, labels, tags, metadata
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
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
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

-- Step 1: Verify New Legal Structure Inputs
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('verify_new_legal_structure_inputs', 'establish_new_legal_structure_for_participant', 'Verify New Legal Structure Inputs', 'Validate inputs, verify participants exist and are enabled.', '{"short_id": "vnlsi", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-structure", "verify", "validate", "participant", "workflow"]'::jsonb, '{"index": "1"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Create Legal Structure Record
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('create_legal_structure_record', 'establish_new_legal_structure_for_participant', 'Create Legal Structure Record', 'Create LegalStructure and ParticipantList records.', '{"short_id": "clsr", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-structure", "create", "participant-list", "record", "workflow"]'::jsonb, '{"index": "2"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Create Custody Account for Legal Structure
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('create_custody_account_for_legal_structure', 'establish_new_legal_structure_for_participant', 'Create Custody Account for Legal Structure', 'Create custody account and legal-structure-to-account relation.', '{"short_id": "ccafls", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-structure", "account", "custody", "create", "relation", "workflow"]'::jsonb, '{"index": "3"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 4: Create LASER Slots for Legal Structure Custody Account
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('create_laser_slots_for_legal_structure_custody', 'establish_new_legal_structure_for_participant', 'Create LASER Slots for Legal Structure Custody Account', 'Create non-SIGNER LASER slots for custody account.', '{"short_id": "clsflsc", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-structure", "laser", "slot", "custody", "ethereum", "workflow"]'::jsonb, '{"index": "4"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 5: Attach ETH Address to Legal Structure Custody Account
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('attach_eth_address_to_legal_structure_custody_account', 'establish_new_legal_structure_for_participant', 'Attach ETH Address to Legal Structure Custody Account', 'Attach ETH address to custody account and set status to ACTIVE.', '{"short_id": "aeatca", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-structure", "attach", "ethereum", "address", "custody", "activate", "workflow"]'::jsonb, '{"index": "5"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 6: Create Accounts for Legal Structure Partners
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('create_accounts_for_legal_structure_partners', 'establish_new_legal_structure_for_participant', 'Create Accounts for Legal Structure Partners', 'Create accounts and relations for all partner participants.', '{"short_id": "caflsp", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-structure", "account", "partner", "create", "batch", "relation", "workflow"]'::jsonb, '{"index": "6"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 7: Create LASER Slots for Legal Structure Partners
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('create_laser_slots_for_legal_structure_partners', 'establish_new_legal_structure_for_participant', 'Create LASER Slots for Legal Structure Partners', 'Create SIGNER-tagged LASER slots for all partner accounts.', '{"short_id": "clsflsp", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-structure", "laser", "slot", "partner", "signer", "ethereum", "workflow"]'::jsonb, '{"index": "7"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 8: Attach ETH Addresses to Legal Structure Partner Accounts
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('attach_eth_addresses_to_legal_structure_partner_accounts', 'establish_new_legal_structure_for_participant', 'Attach ETH Addresses to Legal Structure Partner Accounts', 'Attach ETH addresses to partner accounts and set status to ACTIVE.', '{"short_id": "aeatpa", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-structure", "attach", "ethereum", "address", "partner", "activate", "batch", "workflow"]'::jsonb, '{"index": "8"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 9: Create Clearing Account for Legal Structure
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('create_clearing_account_for_legal_structure', 'establish_new_legal_structure_for_participant', 'Create Clearing Account for Legal Structure', 'Create clearing account and LegalStructureToAccountRelation for the legal structure itself.', '{"short_id": "ccafls", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-structure", "account", "clearing", "create", "relation", "workflow"]'::jsonb, '{"index": "9"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 10: Create LASER Slots for Clearing Account
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('create_laser_slots_for_clearing_account', 'establish_new_legal_structure_for_participant', 'Create LASER Slots for Clearing Account', 'Create SIGNER-tagged LASER slots for clearing account.', '{"short_id": "clsfca", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-structure", "laser", "slot", "clearing", "ethereum", "workflow"]'::jsonb, '{"index": "10"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 11: Attach ETH Address to Clearing Account
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('attach_eth_address_to_clearing_account', 'establish_new_legal_structure_for_participant', 'Attach ETH Address to Clearing Account', 'Attach ETH address to clearing account and set status to ACTIVE.', '{"short_id": "aeatca", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-structure", "attach", "ethereum", "address", "clearing", "activate", "workflow"]'::jsonb, '{"index": "11"}'::jsonb)
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
-- Steps: 10
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
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

-- Step 1: Verify Legal Mechanism Inputs
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('verify_legal_mechanism_inputs', 'deploy_core_legal_mechanisms_for_legal_structure', 'Verify Legal Mechanism Inputs', 'Validate inputs, verify legal structure exists and is PARTNERSHIP type, verify deployer and all partner accounts have SIGNER slots, verify authz_source_diamond_admins and authz_admins have no overlap.', '{"short_id": "vlmi", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "verify", "validate", "signer", "partnership", "workflow"]'::jsonb, '{"index": "1"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Create TaskManager Legal Mechanism
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('create_task_manager_legal_mechanism', 'deploy_core_legal_mechanisms_for_legal_structure', 'Create TaskManager Legal Mechanism', 'Create LegalMechanism record with type=VOTING, LegalStructureIid, and DisplayNames using prefix+locale. Store slot_address = {prefix}-TaskManager in metadata.', '{"short_id": "ctmlm", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "task-manager", "voting", "create", "record", "workflow"]'::jsonb, '{"index": "2"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Create AuthzSource Legal Mechanism
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('create_authz_source_legal_mechanism', 'deploy_core_legal_mechanisms_for_legal_structure', 'Create AuthzSource Legal Mechanism', 'Create LegalMechanism record with type=AUTHORISATION_SOURCE, LegalStructureIid. Store slot_address = {prefix}-AuthzSource in metadata.', '{"short_id": "caslm", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "authz-source", "authorisation", "create", "record", "workflow"]'::jsonb, '{"index": "3"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 4: Deploy TaskManager Contract
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('deploy_task_manager_contract', 'deploy_core_legal_mechanisms_for_legal_structure', 'Deploy TaskManager Contract', 'Deploy TaskManagerV2 via LASER using deployer signer. All partners are admins, approvers, and executors. Returns task_manager_contract_address.', '{"short_id": "dtmc", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "task-manager", "deploy", "laser", "ethereum", "contract", "workflow"]'::jsonb, '{"index": "4"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 5: Create TaskManager Deployment Record
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('create_task_manager_deployment_record', 'deploy_core_legal_mechanisms_for_legal_structure', 'Create TaskManager Deployment Record', 'Create LegalMechanismDeployment with type=LASER, linking to TaskManager mechanism, with contract address from step 4.', '{"short_id": "ctmdr", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "task-manager", "deployment", "record", "laser", "workflow"]'::jsonb, '{"index": "5"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 6: Deploy AuthzDiamond Contract
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('deploy_authz_diamond_contract', 'deploy_core_legal_mechanisms_for_legal_structure', 'Deploy AuthzDiamond Contract', 'Deploy AuthzDiamond via LASER using deployer signer. Returns authz_diamond_contract_address.', '{"short_id": "dadc", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "authz-diamond", "deploy", "laser", "ethereum", "contract", "workflow"]'::jsonb, '{"index": "6"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 7: Create AuthzSource Deployment Record
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('create_authz_source_deployment_record', 'deploy_core_legal_mechanisms_for_legal_structure', 'Create AuthzSource Deployment Record', 'Create LegalMechanismDeployment with type=LASER, linking to AuthzSource mechanism, with contract address from step 6.', '{"short_id": "casdr", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "authz-source", "deployment", "record", "laser", "workflow"]'::jsonb, '{"index": "7"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 8: Initialize AuthzDiamond
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('initialize_authz_diamond', 'deploy_core_legal_mechanisms_for_legal_structure', 'Initialize AuthzDiamond', 'Initialize AuthzDiamond with TaskManager reference, authz_source_diamond_admins, and authz_admins. Uses deployer as signer.', '{"short_id": "iad", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "authz-diamond", "initialize", "laser", "ethereum", "workflow"]'::jsonb, '{"index": "8"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 9: Add AuthzFacet to Diamond
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('add_authz_facet_to_diamond', 'deploy_core_legal_mechanisms_for_legal_structure', 'Add AuthzFacet to Diamond', 'Add AuthzFacet to AuthzDiamond using first authz_source_diamond_admin as signer. Returns add_facet_tx_hash.', '{"short_id": "aaftd", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "authz-facet", "diamond", "add", "laser", "ethereum", "workflow"]'::jsonb, '{"index": "9"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 10: Assign Partner Roles
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
VALUES ('assign_partner_roles', 'deploy_core_legal_mechanisms_for_legal_structure', 'Assign Partner Roles', 'Assign roles (TaskManagerAdmin, AuthzAdmin, Deployer, etc.) to partner LegalStructureToAccountRelation records. Maps role arrays to matching partner relations and updates their metadata.', '{"short_id": "apr", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "partner", "roles", "assign", "workflow"]'::jsonb, '{"index": "10"}'::jsonb)
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
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
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

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('verify_treasury_mechanism_inputs', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Verify Treasury Mechanism Inputs', 'Validate inputs, verify Core Legal Mechanisms exist, verify no Treasury mechanisms exist, verify admin_partner is partner + TM admin, verify authz_admin is AuthzDiamond admin, verify deployer has SIGNER slot.', '{"short_id": "vtmi", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "verify", "validate", "treasury", "rac", "trezor", "workflow"]'::jsonb, '{"index": "1"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('create_rac_legal_mechanism', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Create RAC Legal Mechanism', 'Create LegalMechanism record with type=RESOURCE_ACCESS_CONTROLLER, LegalStructureIid. Store slot_address = {prefix}-RAC in metadata.', '{"short_id": "crlm", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "rac", "resource-access-controller", "create", "record", "workflow"]'::jsonb, '{"index": "2"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('create_treasury_legal_mechanism', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Create Treasury Legal Mechanism', 'Create LegalMechanism record with type=TREASURY, LegalStructureIid. Store slot_address = {prefix}-Trezor in metadata.', '{"short_id": "ctlm", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "treasury", "trezor", "create", "record", "workflow"]'::jsonb, '{"index": "3"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('deploy_rac_diamond_contract', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Deploy RAC Diamond Contract', 'Deploy RAC Diamond via LASER using deployer signer. Contract name = {prefix}-RAC. Returns rac_diamond_contract_address.', '{"short_id": "drdc", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "rac", "diamond", "deploy", "laser", "ethereum", "contract", "workflow"]'::jsonb, '{"index": "4"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('initialize_rac_diamond', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Initialize RAC Diamond', 'Initialize RAC Diamond with admin_partner_slot_address as admin. Uses deployer as signer.', '{"short_id": "ird", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "rac", "diamond", "initialize", "laser", "ethereum", "workflow"]'::jsonb, '{"index": "5"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('grant_add_facets_permission_to_admin_rac', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Grant AddFacets Permission to Admin on RAC', 'authz_admin grants addFacets(address[]) permission to admin_partner on RAC Diamond.', '{"short_id": "gafpar", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "rac", "permission", "grant", "add-facets", "laser", "workflow"]'::jsonb, '{"index": "6"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('add_rac_facet_to_rac_diamond', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Add RAC Facet to RAC Diamond', 'admin_partner adds RAC facet (from lattice using rac_facet_version) to RAC Diamond.', '{"short_id": "arftrd", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "rac", "facet", "add", "diamond", "laser", "workflow"]'::jsonb, '{"index": "7"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('create_rac_deployment_record', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Create RAC Deployment Record', 'Create LegalMechanismDeployment with type=LASER, linking to RAC mechanism, with contract address from step 4.', '{"short_id": "crdr", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "rac", "deployment", "record", "laser", "workflow"]'::jsonb, '{"index": "8"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('deploy_trezor_diamond_contract', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Deploy Trezor Diamond Contract', 'Deploy Trezor Diamond via LASER using deployer signer. Contract name = {prefix}-Trezor. Returns trezor_diamond_contract_address.', '{"short_id": "dtdc", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "diamond", "deploy", "laser", "ethereum", "contract", "workflow"]'::jsonb, '{"index": "9"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('initialize_trezor_diamond', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Initialize Trezor Diamond', 'Initialize Trezor Diamond with admin_partner_slot_address as admin. Uses deployer as signer.', '{"short_id": "itd", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "diamond", "initialize", "laser", "ethereum", "workflow"]'::jsonb, '{"index": "10"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('grant_add_facets_permission_to_admin_trezor', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Grant AddFacets Permission to Admin on Trezor', 'authz_admin grants addFacets(address[]) permission to admin_partner on Trezor Diamond.', '{"short_id": "gafpat", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "permission", "grant", "add-facets", "laser", "workflow"]'::jsonb, '{"index": "11"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('add_vault_facets_to_trezor_diamond', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Add Vault Facets to Trezor Diamond', 'admin_partner adds 7 vault facets to Trezor Diamond: erc20-vault-admin, erc20-vault, ledger-lister, rbac, props, activity-store, eth-vault.', '{"short_id": "avfttd", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "vault", "facets", "add", "diamond", "laser", "workflow"]'::jsonb, '{"index": "12"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('grant_create_ledger_permission', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Grant CreateLedger Permission', 'authz_admin grants createLedger permission to admin_partner on Trezor Diamond.', '{"short_id": "gclp", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "permission", "grant", "create-ledger", "laser", "workflow"]'::jsonb, '{"index": "13"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('create_default_ledger', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Create Default Ledger', 'admin_partner creates DEFAULT ledger (non-slave, id=1) on Trezor Diamond via createLedger function.', '{"short_id": "cdl", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "ledger", "create", "default", "laser", "workflow"]'::jsonb, '{"index": "14"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('grant_set_address_permission', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Grant SetAddress Permission', 'authz_admin grants setAddress permission to admin_partner on Trezor Diamond.', '{"short_id": "gsap", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "permission", "grant", "set-address", "props", "laser", "workflow"]'::jsonb, '{"index": "15"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('grant_set_int_permission', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Grant SetInt Permission', 'authz_admin grants setInt permission to admin_partner on Trezor Diamond.', '{"short_id": "gsip", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "permission", "grant", "set-int", "props", "laser", "workflow"]'::jsonb, '{"index": "16"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('configure_rac_properties', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Configure RAC Properties', 'admin_partner configures Trezor Diamond: setInt(''rac.domain.id'', 999) and setAddress(''rac.address'', rac_diamond_contract_address).', '{"short_id": "crp", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "rac", "props", "configure", "laser", "workflow"]'::jsonb, '{"index": "17"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('grant_treasury_rac_access', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Grant Treasury RAC Access', 'CRITICAL: Grant Trezor Diamond access to RAC Diamond via SimpleAuthzAddAccount. Required for vault operations (depositToErc20Vault) that call rac.updateResourceQuota().', '{"short_id": "gtra", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trezor", "treasury", "rac", "authz", "permission", "laser", "workflow", "critical"]'::jsonb, '{"index": "18"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('create_treasury_deployment_record', 'deploy_treasury_legal_mechanisms_for_legal_structure', 'Create Treasury Deployment Record', 'Create LegalMechanismDeployment with type=LASER, linking to Treasury mechanism, with Trezor contract address from step 9.', '{"short_id": "ctdr", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "treasury", "trezor", "deployment", "record", "laser", "workflow"]'::jsonb, '{"index": "19"}'::jsonb)
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
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
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

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dtlm_verify_trading_mechanism_inputs', 'deploy_trading_legal_mechanisms_for_legal_structure', 'Verify Trading Mechanism Inputs', 'Validate inputs, verify Core Legal Mechanisms exist, verify no Trading mechanisms exist, verify admin_partner is partner + TM admin, verify authz_admin is AuthzDiamond admin, verify deployer has SIGNER slot, verify all facet versions provided.', '{"short_id": "dtlm_vtmi", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "verify", "inputs", "workflow"]'::jsonb, '{"index": "1"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dtlm_create_trading_engine_legal_mechanism', 'deploy_trading_legal_mechanisms_for_legal_structure', 'Create Trading Engine Legal Mechanism', 'Create LegalMechanism record with type=TRADING and slot_address = {prefix}-AgoraEngine.', '{"short_id": "dtlm_ctelm", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "create", "mechanism", "workflow"]'::jsonb, '{"index": "2"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dtlm_deploy_trading_engine_diamond_contract', 'deploy_trading_legal_mechanisms_for_legal_structure', 'Deploy Trading Engine Diamond Contract', 'Deploy Agora Engine Diamond via LASER using deployer. Contract name = {prefix}-AgoraEngine.', '{"short_id": "dtlm_dtedc", "service": "laseragent"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "deploy", "diamond", "laser", "workflow"]'::jsonb, '{"index": "3"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dtlm_initialize_trading_engine_diamond', 'deploy_trading_legal_mechanisms_for_legal_structure', 'Initialize Trading Engine Diamond', 'Initialize Agora Engine Diamond with admin_partner as admin, AuthzSource from Core, TaskManager from Core, authzDomain=AGORA_ENGINE.', '{"short_id": "dtlm_ited", "service": "laseragent"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "initialize", "diamond", "laser", "workflow"]'::jsonb, '{"index": "4"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dtlm_grant_add_facets_perm_trading_engine', 'deploy_trading_legal_mechanisms_for_legal_structure', 'Grant Add Facets Permission to Admin (Trading Engine)', 'authz_admin grants addFacets permission to admin_partner on Agora Engine diamond via SimpleAuthzAddAccount.', '{"short_id": "dtlm_gafpte", "service": "laseragent"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "grant", "permission", "facets", "authz", "workflow"]'::jsonb, '{"index": "5"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dtlm_add_trading_engine_facets', 'deploy_trading_legal_mechanisms_for_legal_structure', 'Add Trading Engine Facets', 'admin_partner adds 10 facets to Agora Engine diamond: RBAC, Props, AgoraEngine, TradeManager, PairManager, OfferManager, Matcher, OrderStats, DirectOrderManager, DirectOrderV2+V2Query.', '{"short_id": "dtlm_atef", "service": "laseragent"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "add", "facets", "diamond", "laser", "workflow"]'::jsonb, '{"index": "6"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dtlm_grant_set_address_perm_trading_engine', 'deploy_trading_legal_mechanisms_for_legal_structure', 'Grant Set Address Permission (Trading Engine)', 'authz_admin grants setAddress permission to admin_partner on Agora Engine diamond via SimpleAuthzAddAccount.', '{"short_id": "dtlm_gsapte", "service": "laseragent"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "grant", "permission", "setAddress", "authz", "workflow"]'::jsonb, '{"index": "7"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dtlm_configure_algo_address_properties', 'deploy_trading_legal_mechanisms_for_legal_structure', 'Configure Algo Address Properties', 'admin_partner sets MatcherAlgo and SettlerAlgo facet addresses as properties on Agora Engine diamond via DIAMOND_PROPS_SET_ADDRESS (PropsFacet.setAddress). Keys: agora.engine.global.matching.matcher.algo.facet, agora.engine.global.matching.settler.algo.facet.', '{"short_id": "dtlm_caap", "service": "laseragent"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "configure", "props", "address", "algo", "matcher", "settler", "workflow"]'::jsonb, '{"index": "8"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dtlm_create_trading_engine_deployment_record', 'deploy_trading_legal_mechanisms_for_legal_structure', 'Create Trading Engine Deployment Record', 'Create LegalMechanismDeployment with type=LASER, linking to Trading Engine mechanism, with Agora Engine contract address from step 3.', '{"short_id": "dtlm_ctedr", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "trading", "agora-engine", "deployment", "record", "laser", "workflow"]'::jsonb, '{"index": "9"}'::jsonb)
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

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('snlp_create_legal_participant_record', 'setup_new_legal_participant', 'Create Legal Participant Record', 'Create participant record for the Legal Participant with provided or auto-generated IID, display names, descriptions, types, and identifiers.', '{"short_id": "snlp_s1", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-participant", "participant", "create", "legal-participant", "workflow"]'::jsonb, '{"index": "1"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('snlp_create_or_validate_partner_participants', 'setup_new_legal_participant', 'Create or Validate Partner Participants', 'Create new partner participant records (if create_new=true) or validate existing participants (if create_new=false). Verify deployer is in partners list.', '{"short_id": "snlp_s2", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-participant", "participant", "partner", "create", "validate", "workflow"]'::jsonb, '{"index": "2"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('snlp_spawn_establish_legal_structure_saga', 'setup_new_legal_participant', 'Spawn Establish Legal Structure Saga', 'Submit establish_new_legal_structure_for_participant sub-saga and wait for completion. Creates PARTNERSHIP legal structure with owner, partner, and clearing accounts.', '{"short_id": "snlp_s3", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-participant", "sub-saga", "legal-structure", "partnership", "spawn", "workflow"]'::jsonb, '{"index": "3"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('snlp_set_principal_legal_structure', 'setup_new_legal_participant', 'Set Principal Legal Structure', 'If is_principal flag is set, register the legal structure as the Principal Legal Structure (PLS) in configmgr. Uses set-once semantics: fails with 409 if PLS already configured.', '{"short_id": "snlp_s4", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-participant", "principal", "pls", "configmgr", "workflow"]'::jsonb, '{"index": "4"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('snlp_spawn_deploy_core_mechanisms_saga', 'setup_new_legal_participant', 'Spawn Deploy Core Mechanisms Saga', 'Submit deploy_core_legal_mechanisms_for_legal_structure sub-saga and wait for completion. Deploys TaskManagerV2 and AuthzDiamond contracts.', '{"short_id": "snlp_s5", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-participant", "sub-saga", "core-mechanisms", "task-manager", "authz", "spawn", "workflow"]'::jsonb, '{"index": "5"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('snlp_spawn_deploy_treasury_mechanisms_saga', 'setup_new_legal_participant', 'Spawn Deploy Treasury Mechanisms Saga', 'Submit deploy_treasury_legal_mechanisms_for_legal_structure sub-saga and wait for completion. Deploys RAC and Trezor Diamonds.', '{"short_id": "snlp_s6", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-participant", "sub-saga", "treasury-mechanisms", "rac", "trezor", "spawn", "workflow"]'::jsonb, '{"index": "6"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('snlp_spawn_deploy_trading_engine_mechanisms_saga', 'setup_new_legal_participant', 'Spawn Deploy Trading Engine Mechanisms Saga', 'Submit deploy_trading_legal_mechanisms_for_legal_structure sub-saga and wait for completion. Deploys Agora Engine Diamond. Controlled by force_creation_of_trading_mechanism flag.', '{"short_id": "snlp_s7", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-participant", "sub-saga", "trading-mechanisms", "agora-engine", "spawn", "workflow"]'::jsonb, '{"index": "7"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('snlp_spawn_deploy_cash_tokens_saga', 'setup_new_legal_participant', 'Spawn Deploy Cash Tokens Saga', 'Submit deploy_cash_token_legal_mechanism_for_legal_structure sub-sagas (one per currency) and wait for completion. Issues ERC20 tokens to LS Clearing Account.', '{"short_id": "snlp_s8", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-participant", "sub-saga", "cash-token", "erc20", "currency", "spawn", "workflow"]'::jsonb, '{"index": "8"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('snlp_create_api_keys', 'setup_new_legal_participant', 'Create API Keys', 'Mint ParticipantAPIKeys for each entry in the api_keys input list. Empty list = no keys minted. Plaintext keys returned only once in saga output, then disabled on compensation.', '{"short_id": "snlp_s9", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-participant", "api-key", "authentication", "rest", "create", "workflow"]'::jsonb, '{"index": "9"}'::jsonb)
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
-- Steps: 15
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
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

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dctlm_verify_cash_token_inputs', 'deploy_cash_token_legal_mechanism_for_legal_structure', 'Verify Cash Token Inputs', 'Validate inputs: verify legal structure exists, Treasury mechanism is deployed, currency_code is valid ISO 4217, deployer has SIGNER slot, clearing account exists.', '{"short_id": "dctlm_s1", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "verify", "validate", "currency", "workflow"]'::jsonb, '{"index": "1"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dctlm_create_cash_token_legal_mechanism', 'deploy_cash_token_legal_mechanism_for_legal_structure', 'Create Cash Token Legal Mechanism', 'Create LegalMechanism record with type=CASH_TOKEN, LegalStructureIid, currency_code in metadata. Store slot_address = {prefix}-CashToken-{currency} in metadata.', '{"short_id": "dctlm_s2", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "create", "record", "currency", "workflow"]'::jsonb, '{"index": "2"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dctlm_deploy_erc20_diamond', 'deploy_cash_token_legal_mechanism_for_legal_structure', 'Deploy ERC20 Diamond', 'Deploy Diamond contract for ERC20 token via LASER using deployer signer. Contract name = {prefix}-CashToken-{currency}. Returns cash_token_diamond_contract_address.', '{"short_id": "dctlm_s3", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "diamond", "deploy", "laser", "ethereum", "contract", "workflow"]'::jsonb, '{"index": "3"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dctlm_update_mechanism_contract_address', 'deploy_cash_token_legal_mechanism_for_legal_structure', 'Update Mechanism with Contract Address', 'Update the CashToken LegalMechanism metadata with contract_address from the deployed Diamond. Required for fund_account_with_cash_tokens saga.', '{"short_id": "dctlm_s4", "service": "accmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "update", "contract-address", "accmgr", "workflow"]'::jsonb, '{"index": "4"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dctlm_initialize_erc20_diamond', 'deploy_cash_token_legal_mechanism_for_legal_structure', 'Initialize ERC20 Diamond', 'Initialize Diamond with TaskManager reference, AuthzSource, and AuthzDomain="CashToken". Uses deployer as signer.', '{"short_id": "dctlm_s5", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "diamond", "initialize", "laser", "ethereum", "workflow"]'::jsonb, '{"index": "5"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dctlm_grant_add_laser_erc20_facet_permission', 'deploy_cash_token_legal_mechanism_for_legal_structure', 'Grant Add LaserErc20Facet Permission', 'authz_admin grants addFacets(address[]) permission to admin_partner on CashToken Diamond via SimpleAuthzAddAccount.', '{"short_id": "dctlm_s6", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "permission", "grant", "add-facets", "laser", "workflow"]'::jsonb, '{"index": "6"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dctlm_add_laser_erc20_facet', 'deploy_cash_token_legal_mechanism_for_legal_structure', 'Add LaserErc20Facet to Diamond', 'admin_partner adds LaserErc20Facet (from lattice using laser_erc20_facet_version) to CashToken Diamond via DiamondAddFacets.', '{"short_id": "dctlm_s7", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "facet", "add", "diamond", "laser", "erc20", "workflow"]'::jsonb, '{"index": "7"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dctlm_grant_initialize_laser_erc20_permission', 'deploy_cash_token_legal_mechanism_for_legal_structure', 'Grant Initialize LaserErc20 Permission', 'authz_admin grants initialize permission to admin_partner on CashToken Diamond via SimpleAuthzAddAccount.', '{"short_id": "dctlm_s8", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "permission", "grant", "initialize", "laser", "workflow"]'::jsonb, '{"index": "8"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dctlm_initialize_laser_erc20', 'deploy_cash_token_legal_mechanism_for_legal_structure', 'Initialize LaserErc20', 'Initialize ERC20 token with name={currency_code} Cash Token, symbol={currency_code}, decimals=18 via LaserErc20FacetInitialize.', '{"short_id": "dctlm_s9", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "erc20", "initialize", "laser", "ethereum", "workflow"]'::jsonb, '{"index": "9"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dctlm_grant_mint_permission', 'deploy_cash_token_legal_mechanism_for_legal_structure', 'Grant Mint Permission', 'authz_admin grants mint permission to deployer on AuthzDiamond via SimpleAuthzAddAccount. Required for FundAccountWithCashTokens saga to mint tokens.', '{"short_id": "dctlm_s10", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "permission", "grant", "mint", "laser", "workflow"]'::jsonb, '{"index": "10"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dctlm_grant_clearing_deposit_permission', 'deploy_cash_token_legal_mechanism_for_legal_structure', 'Grant Clearing Deposit Permission', 'authz_admin grants clearing account permission on AuthzDiamond via SimpleAuthzAddAccount. Required for clearing account to call depositToErc20Vault on Trezor Diamond.', '{"short_id": "dctlm_s11", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "permission", "grant", "clearing", "deposit", "treasury", "laser", "workflow"]'::jsonb, '{"index": "11"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dctlm_issue_initial_supply_to_clearing', 'deploy_cash_token_legal_mechanism_for_legal_structure', 'Issue Initial Supply to Clearing Account', 'Mint initial_amount tokens to clearing_account_slot_address via LaserErc20FacetMint. Skip if initial_amount is 0.', '{"short_id": "dctlm_s12", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "erc20", "mint", "initial-supply", "clearing", "laser", "workflow"]'::jsonb, '{"index": "12"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dctlm_deposit_initial_supply_to_treasury', 'deploy_cash_token_legal_mechanism_for_legal_structure', 'Deposit Initial Supply to Treasury', 'Deposit minted tokens from clearing account into Treasury vault via TrezorErc20DepositToVault. Required for fund_account_with_cash_tokens vault-to-vault transfers.', '{"short_id": "dctlm_s13", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "erc20", "deposit", "treasury", "vault", "laser", "workflow"]'::jsonb, '{"index": "13"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dctlm_create_cash_token_record', 'deploy_cash_token_legal_mechanism_for_legal_structure', 'Create Cash Token Record', 'Create CashToken record in instrmgr with currency_code, contract_address, legal_structure_iid, and mechanism_iid. Create LegalMechanismDeployment record.', '{"short_id": "dctlm_s14", "service": "instrmgr"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "record", "create", "instrmgr", "deployment", "workflow"]'::jsonb, '{"index": "14"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dctlm_amend_vault_link_metadata', 'deploy_cash_token_legal_mechanism_for_legal_structure', 'Amend Vault Link Metadata', 'Amend treasury vault link metadata with authorized_instrument_iid. Links created during deposit (step 13) do not have authorized_instrument_iid since the instrmgr record is created in step 14. This step amends the link metadata after the record exists.', '{"short_id": "dctlm_s15", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "vault-link", "metadata", "amend", "lasersvc", "workflow"]'::jsonb, '{"index": "15"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('dctlm_claim_authz_instr_erc20_diamond_via_metadata', 'deploy_cash_token_legal_mechanism_for_legal_structure', 'Claim AuthzInstr ERC20 Diamond via Metadata', 'Stamp the authorized_instrument_iid into the cash-token''s own ERC20 Diamond inner slot metadata so the treasury indexer can resolve activities emitted by the cash-token''s contract back to the authz-instr iid. Per-cash-token slot — no shared-claim conflict. ref_seed is left untouched (immutable in lasersvc).', '{"short_id": "dctlm_s16", "service": "lasersvc"}'::jsonb, '["agora", "csd", "saga", "step", "legal-mechanism", "cash-token", "diamond", "metadata", "claim", "lasersvc", "workflow"]'::jsonb, '{"index": "16"}'::jsonb)
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
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
)
VALUES (
    'fund_account_with_cash_tokens',
    'Fund Account With Cash Tokens',
    'Saga for funding an account with cash tokens by minting or using existing clearing balance',
    '{"short_id": "facwct"}'::jsonb,
    '["agora", "exchange", "csd", "saga", "account", "cash", "token", "treasury", "funding"]'::jsonb,
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

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('facwct_verify_inputs', 'fund_account_with_cash_tokens', 'Verify Fund Account Inputs', 'Validate all inputs and gather contract addresses for funding operation. Verify legal structure, mechanisms (TREASURY, CASH_TOKEN, RAC), clearing account, and destination account exist.', '{"short_id": "facwct_s1", "service": "accmgr"}'::jsonb, '["agora", "exchange", "csd", "saga", "step", "validation", "inputs", "account", "funding"]'::jsonb, '{"index": "1"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('facwct_query_source_balance', 'fund_account_with_cash_tokens', 'Query Source Vault Balance', 'Query clearing account vault LIQUID balance before operations via TrezorErc20GetVaultBalance. Validate balance if use_clearing_balance=true.', '{"short_id": "facwct_s2", "service": "treassvc"}'::jsonb, '["agora", "exchange", "csd", "saga", "step", "query", "treasury", "vault", "balance"]'::jsonb, '{"index": "2"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('facwct_mint_tokens_if_needed', 'fund_account_with_cash_tokens', 'Mint Tokens If Needed', 'Conditionally mint new tokens to clearing account if use_clearing_balance=false. Execute Erc20MintTo followed by TrezorErc20DepositToVault.', '{"short_id": "facwct_s3", "service": "treassvc"}'::jsonb, '["agora", "exchange", "csd", "saga", "step", "mint", "erc20", "treasury", "conditional"]'::jsonb, '{"index": "3"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('facwct_query_destination_balance', 'fund_account_with_cash_tokens', 'Query Destination Vault Balance', 'Query destination account vault LIQUID balance before transfer via TrezorErc20GetVaultBalance.', '{"short_id": "facwct_s4", "service": "treassvc"}'::jsonb, '["agora", "exchange", "csd", "saga", "step", "query", "treasury", "vault", "balance", "destination"]'::jsonb, '{"index": "4"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('facwct_transfer_to_destination', 'fund_account_with_cash_tokens', 'Transfer From Clearing To Destination', 'Execute TrezorErc20TransferFromVault from clearing vault to destination vault. Amount is transferred from LIQUID stash.', '{"short_id": "facwct_s5", "service": "treassvc"}'::jsonb, '["agora", "exchange", "csd", "saga", "step", "transfer", "treasury", "vault", "laser"]'::jsonb, '{"index": "5"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('facwct_verify_balances', 'fund_account_with_cash_tokens', 'Verify Post Transfer Balances', 'Verify vault balances after transfer via TrezorErc20GetVaultBalance queries. Source decreased by amount, destination increased by amount.', '{"short_id": "facwct_s6", "service": "treassvc"}'::jsonb, '["agora", "exchange", "csd", "saga", "step", "verification", "treasury", "vault", "balance"]'::jsonb, '{"index": "6"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('facwct_amend_vault_link_metadata', 'fund_account_with_cash_tokens', 'Amend Vault Link Metadata', 'Amend treasury vault link metadata with authorized_instrument_iid. New links created during transfer (step 5) may lack authorized_instrument_iid. This step copies it from existing links set during deployment.', '{"short_id": "facwct_s7", "service": "treassvc"}'::jsonb, '["agora", "exchange", "csd", "saga", "step", "vault-link", "metadata", "amend", "treassvc"]'::jsonb, '{"index": "7"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('facwct_create_funding_record', 'fund_account_with_cash_tokens', 'Create Funding Record', 'Create AccountFunding record for audit trail with source_account, destination_account, amount, currency, and transaction hash.', '{"short_id": "facwct_s8", "service": "accmgr"}'::jsonb, '["agora", "exchange", "csd", "saga", "step", "record", "funding", "account", "audit"]'::jsonb, '{"index": "8"}'::jsonb)
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
    '["agora", "exchange", "csd", "saga", "account", "cash", "token", "treasury", "withdrawal"]'::jsonb,
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

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('wcfa_verify_inputs', 'withdraw_cash_tokens_from_account', 'Verify Withdrawal Inputs', 'Validate all inputs and gather contract addresses for withdrawal operation.', '{"short_id": "wcfa_s1", "service": "accmgr"}'::jsonb, '["agora", "exchange", "csd", "saga", "step", "verify", "withdrawal", "accmgr"]'::jsonb, '{"index": "1"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('wcfa_query_account_balance', 'withdraw_cash_tokens_from_account', 'Query Account Vault Balance', 'Query investor account vault LIQUID balance before withdrawal. Validate sufficient balance. Acquire distributed lock.', '{"short_id": "wcfa_s2", "service": "treassvc"}'::jsonb, '["agora", "exchange", "csd", "saga", "step", "query", "balance", "vault", "treassvc"]'::jsonb, '{"index": "2"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('wcfa_transfer_to_clearing', 'withdraw_cash_tokens_from_account', 'Transfer From Account To Clearing', 'Execute TrezorErc20TransferFromVault from investor account vault to clearing vault.', '{"short_id": "wcfa_s3", "service": "treassvc"}'::jsonb, '["agora", "exchange", "csd", "saga", "step", "transfer", "vault", "treasury", "treassvc"]'::jsonb, '{"index": "3"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('wcfa_withdraw_and_burn', 'withdraw_cash_tokens_from_account', 'Withdraw From Vault And Burn', 'Withdraw tokens from clearing vault to ERC20 balance, then burn them using deployer BURNER_ROLE.', '{"short_id": "wcfa_s4", "service": "treassvc"}'::jsonb, '["agora", "exchange", "csd", "saga", "step", "withdraw", "burn", "vault", "erc20", "treassvc"]'::jsonb, '{"index": "4"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('wcfa_verify_balances', 'withdraw_cash_tokens_from_account', 'Verify Post Transfer Balances', 'Verify vault balances after withdrawal transfer. Release distributed lock.', '{"short_id": "wcfa_s5", "service": "treassvc"}'::jsonb, '["agora", "exchange", "csd", "saga", "step", "verify", "balance", "vault", "treassvc"]'::jsonb, '{"index": "5"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('wcfa_create_withdrawal_record', 'withdraw_cash_tokens_from_account', 'Create Withdrawal Record', 'Create AccountFunding record (type=WITHDRAWAL) for audit trail.', '{"short_id": "wcfa_s6", "service": "accmgr"}'::jsonb, '["agora", "exchange", "csd", "saga", "step", "record", "withdrawal", "account", "audit"]'::jsonb, '{"index": "6"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET saga_template_id = EXCLUDED.saga_template_id, display_name = EXCLUDED.display_name, description = EXCLUDED.description, labels = EXCLUDED.labels, tags = EXCLUDED.tags, metadata = EXCLUDED.metadata;


-- ============================================================================
-- SAGA TEMPLATE: setup_security_listing
-- ============================================================================
-- Description: Creates a SecurityListing record (or reuses existing), resolves
--              deployment configuration, sets up cross-diamond authorization
--              grants, creates a trading pair on-chain via createPairV2, and
--              records the deployment and event in listingmgr stores.
-- Steps: 11
-- ============================================================================

INSERT INTO trax.saga_templates (
    template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
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

INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('ssl_validate_inputs', 'setup_security_listing', 'Validate Inputs', 'Validate required inputs (fin_id_strs, execution_runtime, slot addresses) and check for existing SecurityListing or deployment conflicts.', '{"short_id": "ssl_s1", "service": "listingmgr"}'::jsonb, '["agora", "csd", "saga", "step", "security-listing", "validation"]'::jsonb, '{"index": "1"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('ssl_query_deployment_config', 'setup_security_listing', 'Query Deployment Config', 'Query csdmsggw for deployment configuration including LASER slot addresses, trezor addresses, CFI code, and issuer information.', '{"short_id": "ssl_s2", "service": "listingmgr"}'::jsonb, '["agora", "csd", "saga", "step", "security-listing", "config", "csdmsggw"]'::jsonb, '{"index": "2"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('ssl_resolve_fee_collector', 'setup_security_listing', 'Resolve Fee Collector', 'Query accmgr to find the legal structure owning the trading mechanism, then resolve the clearing account slot address as fee collector.', '{"short_id": "ssl_s3", "service": "listingmgr"}'::jsonb, '["agora", "csd", "saga", "step", "security-listing", "fee-collector", "accmgr", "clearing-account"]'::jsonb, '{"index": "3"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('ssl_resolve_issuer_admin', 'setup_security_listing', 'Resolve Issuer Admin', 'Query accmgr for the security issuer legal structure and extract the admin partner (partner 0) slot address from metadata.', '{"short_id": "ssl_s4", "service": "listingmgr"}'::jsonb, '["agora", "csd", "saga", "step", "security-listing", "issuer", "admin", "accmgr"]'::jsonb, '{"index": "4"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('ssl_authorize_admin_on_trading_engine', 'setup_security_listing', 'Authorize Admin on Trading Engine', 'SimpleAuthzAddAccount: add exchange admin partner to trading engine AuthzDiamond so they can call createPairV2.', '{"short_id": "ssl_s5", "service": "listingmgr"}'::jsonb, '["agora", "csd", "saga", "step", "security-listing", "authz", "trading-engine", "laser", "on-chain"]'::jsonb, '{"index": "5"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('ssl_authorize_engine_on_security_treasury', 'setup_security_listing', 'Authorize Engine on Security Treasury', 'SimpleAuthzAddAccount: add trading engine diamond to security treasury AuthzDiamond for transferVaultBalance access.', '{"short_id": "ssl_s6", "service": "listingmgr"}'::jsonb, '["agora", "csd", "saga", "step", "security-listing", "authz", "treasury", "security", "laser", "on-chain"]'::jsonb, '{"index": "6"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('ssl_authorize_engine_on_cash_treasury', 'setup_security_listing', 'Authorize Engine on Cash Treasury', 'SimpleAuthzAddAccount: add trading engine diamond to cash token treasury AuthzDiamond for transferVaultBalance access.', '{"short_id": "ssl_s7", "service": "listingmgr"}'::jsonb, '["agora", "csd", "saga", "step", "security-listing", "authz", "treasury", "cash-token", "laser", "on-chain"]'::jsonb, '{"index": "7"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('ssl_create_or_reuse_security_listing', 'setup_security_listing', 'Create or Reuse Security Listing', 'If a SecurityListing already exists for the security+currency pair, reuse it. Otherwise create a new one with Pending status.', '{"short_id": "ssl_s8", "service": "listingmgr"}'::jsonb, '["agora", "csd", "saga", "step", "security-listing", "create", "reuse"]'::jsonb, '{"index": "8"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('ssl_create_calendar', 'setup_security_listing', 'Create Calendar', 'Create an empty trading calendar and link it to the SecurityListing.', '{"short_id": "ssl_s9", "service": "listingmgr"}'::jsonb, '["agora", "csd", "saga", "step", "security-listing", "calendar", "trading"]'::jsonb, '{"index": "9"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('ssl_create_pair_on_chain', 'setup_security_listing', 'Create Pair On-Chain', 'Build ATS BoundFunc for createPairV2, submit async mutation to LASER, poll for completion, and extract agora_pair_id from PairCreate event.', '{"short_id": "ssl_s10", "service": "listingmgr"}'::jsonb, '["agora", "csd", "saga", "step", "security-listing", "pair", "createPairV2", "laser", "on-chain", "agora-engine"]'::jsonb, '{"index": "10"}'::jsonb)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;
INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata) VALUES ('ssl_create_deployment_and_event_records', 'setup_security_listing', 'Create Deployment and Event Records', 'Create SecurityListingDeployment (LASER_AND_AGORA type with agora_pair_id), SecurityListingEvent (LISTING_DEPLOYMENT type), and activate the SecurityListing.', '{"short_id": "ssl_s11", "service": "listingmgr"}'::jsonb, '["agora", "csd", "saga", "step", "security-listing", "deployment", "event", "record"]'::jsonb, '{"index": "11"}'::jsonb)
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
