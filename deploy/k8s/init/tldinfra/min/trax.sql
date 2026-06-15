-- ============================================================================
-- TLDINFRA TRAX Saga Templates
-- ============================================================================
-- Purpose: TRAX cluster and saga templates for tldinfra namespace
-- Contains: deploy_lattice_facets saga (74 facet deployment steps)
-- Usage: ./deploy data min-records --cluster-id <cluster> --ns tldinfra
-- ============================================================================

\c agora_db;

-- ============================================================================
-- TRAX CLUSTER
-- ============================================================================

-- TLDINFRA - Infrastructure cluster for Lattice Framework facet deployments
INSERT INTO trax.clusters (
    id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'TLDINFRA',
    'TLD Infrastructure Cluster',
    'TRAX cluster for tldinfra namespace - manages Lattice Framework facet deployments',
    '{"env": "local", "namespace": "tldinfra"}'::jsonb,
    '["tldinfra", "lattice", "facets", "infrastructure"]'::jsonb,
    '{"created_by": "tldinfra_min_init"}'::jsonb
)
ON CONFLICT (id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

\echo 'TRAX cluster TLDINFRA created';

-- ============================================================================
-- SAGA TEMPLATE: deploy_lattice_facets
-- ============================================================================
-- Description: Deploy Lattice Framework facets (EIP-2535 Diamond pattern)
-- Steps: 73 facet deployment steps organized by module
-- Modules: core, erc20, trezor, prizma, agora, korridor, elysium, frenzy, utr
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
    'deploy_lattice_facets',
    'Deploy Lattice Framework Facets',
    'TRAX saga for deploying Lattice Framework facets (EIP-2535 Diamond pattern). Creates versioned slots and :latest alias slots. EthBC-only.',
    '{"short_id": "dlf"}'::jsonb,
    '["agora", "csd", "saga", "workflow", "lattice", "facet", "diamond", "eip2535", "laser", "ethereum", "deploy", "infrastructure", "trax-flow"]'::jsonb,
    '{"facet_count": "74"}'::jsonb,
    '["deploy_app_registry_facet", "deploy_authz_facet", "deploy_simple_authz_facet", "deploy_rbac_facet", "deploy_rac_facet", "deploy_hasher_facet", "deploy_diag_facet", "deploy_props_facet", "deploy_hash_annotator_facet", "deploy_task_executor_facet", "deploy_erc20_facet", "deploy_laser_erc20_facet", "deploy_eth_reserve_facet", "deploy_eth_reserve_admin_facet", "deploy_eth_reserve_transfer_facet", "deploy_eth_vault_facet", "deploy_eth_vault_admin_facet", "deploy_eth_vault_transfer_facet", "deploy_erc20_reserve_facet", "deploy_erc20_reserve_admin_facet", "deploy_erc20_reserve_transfer_facet", "deploy_erc20_vault_facet", "deploy_erc20_vault_admin_facet", "deploy_erc20_vault_transfer_facet", "deploy_erc20_vault_idemp_facet", "deploy_erc721_reserve_facet", "deploy_erc721_reserve_admin_facet", "deploy_erc721_reserve_transfer_facet", "deploy_erc721_vault_facet", "deploy_erc721_vault_admin_facet", "deploy_erc721_vault_transfer_facet", "deploy_activity_store_facet", "deploy_reserve_lister_facet", "deploy_ledger_lister_facet", "deploy_registry_facet", "deploy_registrar_facet", "deploy_registrar_factory_facet", "deploy_catalog_facet", "deploy_council_facet", "deploy_council_admin_facet", "deploy_council_pm_facet", "deploy_board_facet", "deploy_grant_token_facet", "deploy_agora_engine_facet", "deploy_agora_engine_direct_order_manager_facet", "deploy_agora_engine_offer_manager_facet", "deploy_agora_engine_matcher_facet", "deploy_agora_engine_matcher_algo_facet", "deploy_agora_engine_settler_algo_facet", "deploy_agora_engine_trade_manager_facet", "deploy_agora_engine_pair_manager_facet", "deploy_agora_engine_order_stats_facet", "deploy_agora_engine_direct_order_manager_v2_facet", "deploy_agora_engine_direct_order_manager_v2_query_facet", "deploy_agora_engine_event_store_facet", "deploy_access_point_facet", "deploy_access_point_send_manager_facet", "deploy_access_point_delivery_manager_facet", "deploy_access_point_v2_facet", "deploy_access_point_v3_facet", "deploy_elysium_facet", "deploy_elysium_admin_facet", "deploy_elysium_plan_manager_facet", "deploy_minter_facet", "deploy_token_store_facet", "deploy_royalty_manager_facet", "deploy_reserve_manager_facet", "deploy_payment_method_manager_facet", "deploy_whitelist_manager_facet", "deploy_payment_handler_facet", "deploy_erc721_facet", "deploy_crossmint_facet", "deploy_utr_facet", "deploy_utr_v2_facet"]'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata,
    saga_step_template_ids = EXCLUDED.saga_step_template_ids;

\echo 'Saga template deploy_lattice_facets created';

-- ============================================================================
-- SAGA STEP TEMPLATES: Core/Foundation Module (1-10)
-- ============================================================================

-- Step 1: Deploy AppRegistryFacet
-- Service: lasersvc
-- Purpose: Deploy AppRegistryFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_app_registry_facet',
    'deploy_lattice_facets',
    'Deploy AppRegistryFacet',
    'Deploy AppRegistryFacet via LASER DEPLOY_FACET',
    '{"short_id": "darf", "service": "lasersvc", "module": "core", "facet_name": "AppRegistryFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "core", "workflow"]'::jsonb,
    '{"index": "1", "facet_name": "AppRegistryFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 2: Deploy AuthzFacet
-- Service: lasersvc
-- Purpose: Deploy AuthzFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_authz_facet',
    'deploy_lattice_facets',
    'Deploy AuthzFacet',
    'Deploy AuthzFacet via LASER DEPLOY_FACET',
    '{"short_id": "dazf", "service": "lasersvc", "module": "core", "facet_name": "AuthzFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "core", "workflow"]'::jsonb,
    '{"index": "2", "facet_name": "AuthzFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 3: Deploy SimpleAuthzFacet
-- Service: lasersvc
-- Purpose: Deploy SimpleAuthzFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_simple_authz_facet',
    'deploy_lattice_facets',
    'Deploy SimpleAuthzFacet',
    'Deploy SimpleAuthzFacet via LASER DEPLOY_FACET',
    '{"short_id": "dsaf", "service": "lasersvc", "module": "core", "facet_name": "SimpleAuthzFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "core", "workflow"]'::jsonb,
    '{"index": "3", "facet_name": "SimpleAuthzFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 4: Deploy RBACFacet
-- Service: lasersvc
-- Purpose: Deploy RBACFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_rbac_facet',
    'deploy_lattice_facets',
    'Deploy RBACFacet',
    'Deploy RBACFacet via LASER DEPLOY_FACET',
    '{"short_id": "drbf", "service": "lasersvc", "module": "core", "facet_name": "RBACFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "core", "workflow"]'::jsonb,
    '{"index": "4", "facet_name": "RBACFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 5: Deploy RACFacet
-- Service: lasersvc
-- Purpose: Deploy RACFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_rac_facet',
    'deploy_lattice_facets',
    'Deploy RACFacet',
    'Deploy RACFacet via LASER DEPLOY_FACET',
    '{"short_id": "drcf", "service": "lasersvc", "module": "core", "facet_name": "RACFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "core", "workflow"]'::jsonb,
    '{"index": "5", "facet_name": "RACFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 6: Deploy HasherFacet
-- Service: lasersvc
-- Purpose: Deploy HasherFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_hasher_facet',
    'deploy_lattice_facets',
    'Deploy HasherFacet',
    'Deploy HasherFacet via LASER DEPLOY_FACET',
    '{"short_id": "dhsf", "service": "lasersvc", "module": "core", "facet_name": "HasherFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "core", "workflow"]'::jsonb,
    '{"index": "6", "facet_name": "HasherFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 7: Deploy DiagFacet
-- Service: lasersvc
-- Purpose: Deploy DiagFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_diag_facet',
    'deploy_lattice_facets',
    'Deploy DiagFacet',
    'Deploy DiagFacet via LASER DEPLOY_FACET',
    '{"short_id": "ddgf", "service": "lasersvc", "module": "core", "facet_name": "DiagFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "core", "workflow"]'::jsonb,
    '{"index": "7", "facet_name": "DiagFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 8: Deploy PropsFacet
-- Service: lasersvc
-- Purpose: Deploy PropsFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_props_facet',
    'deploy_lattice_facets',
    'Deploy PropsFacet',
    'Deploy PropsFacet via LASER DEPLOY_FACET',
    '{"short_id": "dprf", "service": "lasersvc", "module": "core", "facet_name": "PropsFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "core", "workflow"]'::jsonb,
    '{"index": "8", "facet_name": "PropsFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 9: Deploy HashAnnotatorFacet
-- Service: lasersvc
-- Purpose: Deploy HashAnnotatorFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_hash_annotator_facet',
    'deploy_lattice_facets',
    'Deploy HashAnnotatorFacet',
    'Deploy HashAnnotatorFacet via LASER DEPLOY_FACET',
    '{"short_id": "dhaf", "service": "lasersvc", "module": "core", "facet_name": "HashAnnotatorFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "core", "workflow"]'::jsonb,
    '{"index": "9", "facet_name": "HashAnnotatorFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 10: Deploy TaskExecutorFacet
-- Service: lasersvc
-- Purpose: Deploy TaskExecutorFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_task_executor_facet',
    'deploy_lattice_facets',
    'Deploy TaskExecutorFacet',
    'Deploy TaskExecutorFacet via LASER DEPLOY_FACET',
    '{"short_id": "dtef", "service": "lasersvc", "module": "core", "facet_name": "TaskExecutorFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "core", "workflow"]'::jsonb,
    '{"index": "10", "facet_name": "TaskExecutorFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- ============================================================================
-- SAGA STEP TEMPLATES: ERC20 Module (11-12)
-- ============================================================================

-- Step 11: Deploy Erc20Facet
-- Service: lasersvc
-- Purpose: Deploy Erc20Facet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_erc20_facet',
    'deploy_lattice_facets',
    'Deploy Erc20Facet',
    'Deploy Erc20Facet via LASER DEPLOY_FACET',
    '{"short_id": "de2f", "service": "lasersvc", "module": "erc20", "facet_name": "Erc20Facet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "erc20", "workflow"]'::jsonb,
    '{"index": "11", "facet_name": "Erc20Facet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 12: Deploy LASERErc20Facet
-- Service: lasersvc
-- Purpose: Deploy LASERErc20Facet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_laser_erc20_facet',
    'deploy_lattice_facets',
    'Deploy LASERErc20Facet',
    'Deploy LASERErc20Facet via LASER DEPLOY_FACET',
    '{"short_id": "dlef", "service": "lasersvc", "module": "erc20", "facet_name": "LASERErc20Facet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "erc20", "workflow"]'::jsonb,
    '{"index": "12", "facet_name": "LASERErc20Facet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- ============================================================================
-- SAGA STEP TEMPLATES: Trezor/Treasury Module (13-34)
-- ============================================================================

-- Step 13: Deploy EthReserveFacet
-- Service: lasersvc
-- Purpose: Deploy EthReserveFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_eth_reserve_facet',
    'deploy_lattice_facets',
    'Deploy EthReserveFacet',
    'Deploy EthReserveFacet via LASER DEPLOY_FACET',
    '{"short_id": "derf", "service": "lasersvc", "module": "trezor", "facet_name": "EthReserveFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "13", "facet_name": "EthReserveFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 14: Deploy EthReserveAdminFacet
-- Service: lasersvc
-- Purpose: Deploy EthReserveAdminFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_eth_reserve_admin_facet',
    'deploy_lattice_facets',
    'Deploy EthReserveAdminFacet',
    'Deploy EthReserveAdminFacet via LASER DEPLOY_FACET',
    '{"short_id": "dera", "service": "lasersvc", "module": "trezor", "facet_name": "EthReserveAdminFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "14", "facet_name": "EthReserveAdminFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 15: Deploy EthReserveTransferFacet
-- Service: lasersvc
-- Purpose: Deploy EthReserveTransferFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_eth_reserve_transfer_facet',
    'deploy_lattice_facets',
    'Deploy EthReserveTransferFacet',
    'Deploy EthReserveTransferFacet via LASER DEPLOY_FACET',
    '{"short_id": "dert", "service": "lasersvc", "module": "trezor", "facet_name": "EthReserveTransferFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "15", "facet_name": "EthReserveTransferFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 16: Deploy EthVaultFacet
-- Service: lasersvc
-- Purpose: Deploy EthVaultFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_eth_vault_facet',
    'deploy_lattice_facets',
    'Deploy EthVaultFacet',
    'Deploy EthVaultFacet via LASER DEPLOY_FACET',
    '{"short_id": "devf", "service": "lasersvc", "module": "trezor", "facet_name": "EthVaultFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "16", "facet_name": "EthVaultFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 17: Deploy EthVaultAdminFacet
-- Service: lasersvc
-- Purpose: Deploy EthVaultAdminFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_eth_vault_admin_facet',
    'deploy_lattice_facets',
    'Deploy EthVaultAdminFacet',
    'Deploy EthVaultAdminFacet via LASER DEPLOY_FACET',
    '{"short_id": "deva", "service": "lasersvc", "module": "trezor", "facet_name": "EthVaultAdminFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "17", "facet_name": "EthVaultAdminFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 18: Deploy EthVaultTransferFacet
-- Service: lasersvc
-- Purpose: Deploy EthVaultTransferFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_eth_vault_transfer_facet',
    'deploy_lattice_facets',
    'Deploy EthVaultTransferFacet',
    'Deploy EthVaultTransferFacet via LASER DEPLOY_FACET',
    '{"short_id": "devt", "service": "lasersvc", "module": "trezor", "facet_name": "EthVaultTransferFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "18", "facet_name": "EthVaultTransferFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 19: Deploy Erc20ReserveFacet
-- Service: lasersvc
-- Purpose: Deploy Erc20ReserveFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_erc20_reserve_facet',
    'deploy_lattice_facets',
    'Deploy Erc20ReserveFacet',
    'Deploy Erc20ReserveFacet via LASER DEPLOY_FACET',
    '{"short_id": "d2rf", "service": "lasersvc", "module": "trezor", "facet_name": "Erc20ReserveFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "19", "facet_name": "Erc20ReserveFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 20: Deploy Erc20ReserveAdminFacet
-- Service: lasersvc
-- Purpose: Deploy Erc20ReserveAdminFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_erc20_reserve_admin_facet',
    'deploy_lattice_facets',
    'Deploy Erc20ReserveAdminFacet',
    'Deploy Erc20ReserveAdminFacet via LASER DEPLOY_FACET',
    '{"short_id": "d2ra", "service": "lasersvc", "module": "trezor", "facet_name": "Erc20ReserveAdminFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "20", "facet_name": "Erc20ReserveAdminFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 21: Deploy Erc20ReserveTransferFacet
-- Service: lasersvc
-- Purpose: Deploy Erc20ReserveTransferFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_erc20_reserve_transfer_facet',
    'deploy_lattice_facets',
    'Deploy Erc20ReserveTransferFacet',
    'Deploy Erc20ReserveTransferFacet via LASER DEPLOY_FACET',
    '{"short_id": "d2rt", "service": "lasersvc", "module": "trezor", "facet_name": "Erc20ReserveTransferFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "21", "facet_name": "Erc20ReserveTransferFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 22: Deploy Erc20VaultFacet
-- Service: lasersvc
-- Purpose: Deploy Erc20VaultFacet via LASER DEPLOY_FACET (query functions only; non-idempotent mutations disabled at LASER level)
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_erc20_vault_facet',
    'deploy_lattice_facets',
    'Deploy Erc20VaultFacet',
    'Deploy Erc20VaultFacet via LASER DEPLOY_FACET (provides query functions, non-idempotent mutations disabled at LASER level)',
    '{"short_id": "d2vf", "service": "lasersvc", "module": "trezor", "facet_name": "Erc20VaultFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "22", "facet_name": "Erc20VaultFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 23: Deploy Erc20VaultAdminFacet
-- Service: lasersvc
-- Purpose: Deploy Erc20VaultAdminFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_erc20_vault_admin_facet',
    'deploy_lattice_facets',
    'Deploy Erc20VaultAdminFacet',
    'Deploy Erc20VaultAdminFacet via LASER DEPLOY_FACET',
    '{"short_id": "d2va", "service": "lasersvc", "module": "trezor", "facet_name": "Erc20VaultAdminFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "23", "facet_name": "Erc20VaultAdminFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 24: Deploy Erc20VaultTransferFacet
-- Service: lasersvc
-- Purpose: Deploy Erc20VaultTransferFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_erc20_vault_transfer_facet',
    'deploy_lattice_facets',
    'Deploy Erc20VaultTransferFacet',
    'Deploy Erc20VaultTransferFacet via LASER DEPLOY_FACET',
    '{"short_id": "d2vt", "service": "lasersvc", "module": "trezor", "facet_name": "Erc20VaultTransferFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "24", "facet_name": "Erc20VaultTransferFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 25: Deploy Erc20VaultIdempFacet
-- Service: lasersvc
-- Purpose: Deploy Erc20VaultIdempFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_erc20_vault_idemp_facet',
    'deploy_lattice_facets',
    'Deploy Erc20VaultIdempFacet',
    'Deploy Erc20VaultIdempFacet via LASER DEPLOY_FACET',
    '{"short_id": "d2vi", "service": "lasersvc", "module": "trezor", "facet_name": "Erc20VaultIdempFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "25", "facet_name": "Erc20VaultIdempFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 26: Deploy Erc721ReserveFacet
-- Service: lasersvc
-- Purpose: Deploy Erc721ReserveFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_erc721_reserve_facet',
    'deploy_lattice_facets',
    'Deploy Erc721ReserveFacet',
    'Deploy Erc721ReserveFacet via LASER DEPLOY_FACET',
    '{"short_id": "d7rf", "service": "lasersvc", "module": "trezor", "facet_name": "Erc721ReserveFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "26", "facet_name": "Erc721ReserveFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 27: Deploy Erc721ReserveAdminFacet
-- Service: lasersvc
-- Purpose: Deploy Erc721ReserveAdminFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_erc721_reserve_admin_facet',
    'deploy_lattice_facets',
    'Deploy Erc721ReserveAdminFacet',
    'Deploy Erc721ReserveAdminFacet via LASER DEPLOY_FACET',
    '{"short_id": "d7ra", "service": "lasersvc", "module": "trezor", "facet_name": "Erc721ReserveAdminFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "27", "facet_name": "Erc721ReserveAdminFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 28: Deploy Erc721ReserveTransferFacet
-- Service: lasersvc
-- Purpose: Deploy Erc721ReserveTransferFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_erc721_reserve_transfer_facet',
    'deploy_lattice_facets',
    'Deploy Erc721ReserveTransferFacet',
    'Deploy Erc721ReserveTransferFacet via LASER DEPLOY_FACET',
    '{"short_id": "d7rt", "service": "lasersvc", "module": "trezor", "facet_name": "Erc721ReserveTransferFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "28", "facet_name": "Erc721ReserveTransferFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 29: Deploy Erc721VaultFacet
-- Service: lasersvc
-- Purpose: Deploy Erc721VaultFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_erc721_vault_facet',
    'deploy_lattice_facets',
    'Deploy Erc721VaultFacet',
    'Deploy Erc721VaultFacet via LASER DEPLOY_FACET',
    '{"short_id": "d7vf", "service": "lasersvc", "module": "trezor", "facet_name": "Erc721VaultFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "29", "facet_name": "Erc721VaultFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 30: Deploy Erc721VaultAdminFacet
-- Service: lasersvc
-- Purpose: Deploy Erc721VaultAdminFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_erc721_vault_admin_facet',
    'deploy_lattice_facets',
    'Deploy Erc721VaultAdminFacet',
    'Deploy Erc721VaultAdminFacet via LASER DEPLOY_FACET',
    '{"short_id": "d7va", "service": "lasersvc", "module": "trezor", "facet_name": "Erc721VaultAdminFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "30", "facet_name": "Erc721VaultAdminFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 31: Deploy Erc721VaultTransferFacet
-- Service: lasersvc
-- Purpose: Deploy Erc721VaultTransferFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_erc721_vault_transfer_facet',
    'deploy_lattice_facets',
    'Deploy Erc721VaultTransferFacet',
    'Deploy Erc721VaultTransferFacet via LASER DEPLOY_FACET',
    '{"short_id": "d7vt", "service": "lasersvc", "module": "trezor", "facet_name": "Erc721VaultTransferFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "31", "facet_name": "Erc721VaultTransferFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 32: Deploy ActivityStoreFacet
-- Service: lasersvc
-- Purpose: Deploy ActivityStoreFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_activity_store_facet',
    'deploy_lattice_facets',
    'Deploy ActivityStoreFacet',
    'Deploy ActivityStoreFacet via LASER DEPLOY_FACET',
    '{"short_id": "dasf", "service": "lasersvc", "module": "trezor", "facet_name": "ActivityStoreFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "32", "facet_name": "ActivityStoreFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 33: Deploy ReserveListerFacet
-- Service: lasersvc
-- Purpose: Deploy ReserveListerFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_reserve_lister_facet',
    'deploy_lattice_facets',
    'Deploy ReserveListerFacet',
    'Deploy ReserveListerFacet via LASER DEPLOY_FACET',
    '{"short_id": "drlf", "service": "lasersvc", "module": "trezor", "facet_name": "ReserveListerFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "33", "facet_name": "ReserveListerFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 34: Deploy LedgerListerFacet
-- Service: lasersvc
-- Purpose: Deploy LedgerListerFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_ledger_lister_facet',
    'deploy_lattice_facets',
    'Deploy LedgerListerFacet',
    'Deploy LedgerListerFacet via LASER DEPLOY_FACET',
    '{"short_id": "dllf", "service": "lasersvc", "module": "trezor", "facet_name": "LedgerListerFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "trezor", "workflow"]'::jsonb,
    '{"index": "34", "facet_name": "LedgerListerFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- ============================================================================
-- SAGA STEP TEMPLATES: Prizma/Governance Module (35-43)
-- ============================================================================

-- Step 35: Deploy RegistryFacet
-- Service: lasersvc
-- Purpose: Deploy RegistryFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_registry_facet',
    'deploy_lattice_facets',
    'Deploy RegistryFacet',
    'Deploy RegistryFacet via LASER DEPLOY_FACET',
    '{"short_id": "drgf", "service": "lasersvc", "module": "prizma", "facet_name": "RegistryFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "prizma", "workflow"]'::jsonb,
    '{"index": "35", "facet_name": "RegistryFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 36: Deploy RegistrarFacet
-- Service: lasersvc
-- Purpose: Deploy RegistrarFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_registrar_facet',
    'deploy_lattice_facets',
    'Deploy RegistrarFacet',
    'Deploy RegistrarFacet via LASER DEPLOY_FACET',
    '{"short_id": "drrf", "service": "lasersvc", "module": "prizma", "facet_name": "RegistrarFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "prizma", "workflow"]'::jsonb,
    '{"index": "36", "facet_name": "RegistrarFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 37: Deploy RegistrarFactoryFacet
-- Service: lasersvc
-- Purpose: Deploy RegistrarFactoryFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_registrar_factory_facet',
    'deploy_lattice_facets',
    'Deploy RegistrarFactoryFacet',
    'Deploy RegistrarFactoryFacet via LASER DEPLOY_FACET',
    '{"short_id": "drff", "service": "lasersvc", "module": "prizma", "facet_name": "RegistrarFactoryFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "prizma", "workflow"]'::jsonb,
    '{"index": "37", "facet_name": "RegistrarFactoryFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 38: Deploy CatalogFacet
-- Service: lasersvc
-- Purpose: Deploy CatalogFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_catalog_facet',
    'deploy_lattice_facets',
    'Deploy CatalogFacet',
    'Deploy CatalogFacet via LASER DEPLOY_FACET',
    '{"short_id": "dctf", "service": "lasersvc", "module": "prizma", "facet_name": "CatalogFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "prizma", "workflow"]'::jsonb,
    '{"index": "38", "facet_name": "CatalogFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 39: Deploy CouncilFacet
-- Service: lasersvc
-- Purpose: Deploy CouncilFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_council_facet',
    'deploy_lattice_facets',
    'Deploy CouncilFacet',
    'Deploy CouncilFacet via LASER DEPLOY_FACET',
    '{"short_id": "dcnf", "service": "lasersvc", "module": "prizma", "facet_name": "CouncilFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "prizma", "workflow"]'::jsonb,
    '{"index": "39", "facet_name": "CouncilFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 40: Deploy CouncilAdminFacet
-- Service: lasersvc
-- Purpose: Deploy CouncilAdminFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_council_admin_facet',
    'deploy_lattice_facets',
    'Deploy CouncilAdminFacet',
    'Deploy CouncilAdminFacet via LASER DEPLOY_FACET',
    '{"short_id": "dcaf", "service": "lasersvc", "module": "prizma", "facet_name": "CouncilAdminFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "prizma", "workflow"]'::jsonb,
    '{"index": "40", "facet_name": "CouncilAdminFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 41: Deploy CouncilPMFacet
-- Service: lasersvc
-- Purpose: Deploy CouncilPMFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_council_pm_facet',
    'deploy_lattice_facets',
    'Deploy CouncilPMFacet',
    'Deploy CouncilPMFacet via LASER DEPLOY_FACET',
    '{"short_id": "dcpf", "service": "lasersvc", "module": "prizma", "facet_name": "CouncilPMFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "prizma", "workflow"]'::jsonb,
    '{"index": "41", "facet_name": "CouncilPMFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 42: Deploy BoardFacet
-- Service: lasersvc
-- Purpose: Deploy BoardFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_board_facet',
    'deploy_lattice_facets',
    'Deploy BoardFacet',
    'Deploy BoardFacet via LASER DEPLOY_FACET',
    '{"short_id": "dbdf", "service": "lasersvc", "module": "prizma", "facet_name": "BoardFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "prizma", "workflow"]'::jsonb,
    '{"index": "42", "facet_name": "BoardFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 43: Deploy GrantTokenFacet
-- Service: lasersvc
-- Purpose: Deploy GrantTokenFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_grant_token_facet',
    'deploy_lattice_facets',
    'Deploy GrantTokenFacet',
    'Deploy GrantTokenFacet via LASER DEPLOY_FACET',
    '{"short_id": "dgtf", "service": "lasersvc", "module": "prizma", "facet_name": "GrantTokenFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "prizma", "workflow"]'::jsonb,
    '{"index": "43", "facet_name": "GrantTokenFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- ============================================================================
-- SAGA STEP TEMPLATES: Agora/Trading Module (44-55)
-- ============================================================================

-- Step 44: Deploy AgoraEngineFacet
-- Service: lasersvc
-- Purpose: Deploy AgoraEngineFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_agora_engine_facet',
    'deploy_lattice_facets',
    'Deploy AgoraEngineFacet',
    'Deploy AgoraEngineFacet via LASER DEPLOY_FACET',
    '{"short_id": "daef", "service": "lasersvc", "module": "agora", "facet_name": "AgoraEngineFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "agora", "workflow"]'::jsonb,
    '{"index": "44", "facet_name": "AgoraEngineFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 45: Deploy AgoraEngineDirectOrderManagerFacet
-- Service: lasersvc
-- Purpose: Deploy AgoraEngineDirectOrderManagerFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_agora_engine_direct_order_manager_facet',
    'deploy_lattice_facets',
    'Deploy AgoraEngineDirectOrderManagerFacet',
    'Deploy AgoraEngineDirectOrderManagerFacet via LASER DEPLOY_FACET',
    '{"short_id": "dado", "service": "lasersvc", "module": "agora", "facet_name": "AgoraEngineDirectOrderManagerFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "agora", "workflow"]'::jsonb,
    '{"index": "45", "facet_name": "AgoraEngineDirectOrderManagerFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 46: Deploy AgoraEngineOfferManagerFacet
-- Service: lasersvc
-- Purpose: Deploy AgoraEngineOfferManagerFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_agora_engine_offer_manager_facet',
    'deploy_lattice_facets',
    'Deploy AgoraEngineOfferManagerFacet',
    'Deploy AgoraEngineOfferManagerFacet via LASER DEPLOY_FACET',
    '{"short_id": "daom", "service": "lasersvc", "module": "agora", "facet_name": "AgoraEngineOfferManagerFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "agora", "workflow"]'::jsonb,
    '{"index": "46", "facet_name": "AgoraEngineOfferManagerFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 47: Deploy AgoraEngineMatcherFacet
-- Service: lasersvc
-- Purpose: Deploy AgoraEngineMatcherFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_agora_engine_matcher_facet',
    'deploy_lattice_facets',
    'Deploy AgoraEngineMatcherFacet',
    'Deploy AgoraEngineMatcherFacet via LASER DEPLOY_FACET',
    '{"short_id": "damf", "service": "lasersvc", "module": "agora", "facet_name": "AgoraEngineMatcherFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "agora", "workflow"]'::jsonb,
    '{"index": "47", "facet_name": "AgoraEngineMatcherFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 48: Deploy AgoraEngineMatcherAlgoFacet
-- Service: lasersvc
-- Purpose: Deploy AgoraEngineMatcherAlgoFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_agora_engine_matcher_algo_facet',
    'deploy_lattice_facets',
    'Deploy AgoraEngineMatcherAlgoFacet',
    'Deploy AgoraEngineMatcherAlgoFacet via LASER DEPLOY_FACET',
    '{"short_id": "dama", "service": "lasersvc", "module": "agora", "facet_name": "AgoraEngineMatcherAlgoFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "agora", "workflow"]'::jsonb,
    '{"index": "48", "facet_name": "AgoraEngineMatcherAlgoFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 49: Deploy AgoraEngineSettlerAlgoFacet
-- Service: lasersvc
-- Purpose: Deploy AgoraEngineSettlerAlgoFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_agora_engine_settler_algo_facet',
    'deploy_lattice_facets',
    'Deploy AgoraEngineSettlerAlgoFacet',
    'Deploy AgoraEngineSettlerAlgoFacet via LASER DEPLOY_FACET',
    '{"short_id": "dasa", "service": "lasersvc", "module": "agora", "facet_name": "AgoraEngineSettlerAlgoFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "agora", "workflow"]'::jsonb,
    '{"index": "49", "facet_name": "AgoraEngineSettlerAlgoFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 50: Deploy AgoraEngineTradeManagerFacet
-- Service: lasersvc
-- Purpose: Deploy AgoraEngineTradeManagerFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_agora_engine_trade_manager_facet',
    'deploy_lattice_facets',
    'Deploy AgoraEngineTradeManagerFacet',
    'Deploy AgoraEngineTradeManagerFacet via LASER DEPLOY_FACET',
    '{"short_id": "datm", "service": "lasersvc", "module": "agora", "facet_name": "AgoraEngineTradeManagerFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "agora", "workflow"]'::jsonb,
    '{"index": "50", "facet_name": "AgoraEngineTradeManagerFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 51: Deploy AgoraEnginePairManagerFacet
-- Service: lasersvc
-- Purpose: Deploy AgoraEnginePairManagerFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_agora_engine_pair_manager_facet',
    'deploy_lattice_facets',
    'Deploy AgoraEnginePairManagerFacet',
    'Deploy AgoraEnginePairManagerFacet via LASER DEPLOY_FACET',
    '{"short_id": "dapm", "service": "lasersvc", "module": "agora", "facet_name": "AgoraEnginePairManagerFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "agora", "workflow"]'::jsonb,
    '{"index": "51", "facet_name": "AgoraEnginePairManagerFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 52: Deploy AgoraEngineOrderStatsFacet
-- Service: lasersvc
-- Purpose: Deploy AgoraEngineOrderStatsFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_agora_engine_order_stats_facet',
    'deploy_lattice_facets',
    'Deploy AgoraEngineOrderStatsFacet',
    'Deploy AgoraEngineOrderStatsFacet via LASER DEPLOY_FACET',
    '{"short_id": "daos", "service": "lasersvc", "module": "agora", "facet_name": "AgoraEngineOrderStatsFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "agora", "workflow"]'::jsonb,
    '{"index": "52", "facet_name": "AgoraEngineOrderStatsFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;


-- Step 53: Deploy AgoraEngineDirectOrderManagerV2Facet
-- Service: lasersvc
-- Purpose: Deploy AgoraEngineDirectOrderManagerV2Facet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_agora_engine_direct_order_manager_v2_facet',
    'deploy_lattice_facets',
    'Deploy AgoraEngineDirectOrderManagerV2Facet',
    'Deploy AgoraEngineDirectOrderManagerV2Facet via LASER DEPLOY_FACET',
    '{"short_id": "dav2", "service": "lasersvc", "module": "agora", "facet_name": "AgoraEngineDirectOrderManagerV2Facet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "agora", "workflow"]'::jsonb,
    '{"index": "53", "facet_name": "AgoraEngineDirectOrderManagerV2Facet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 54: Deploy AgoraEngineDirectOrderManagerV2QueryFacet
-- Service: lasersvc
-- Purpose: Deploy AgoraEngineDirectOrderManagerV2QueryFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_agora_engine_direct_order_manager_v2_query_facet',
    'deploy_lattice_facets',
    'Deploy AgoraEngineDirectOrderManagerV2QueryFacet',
    'Deploy AgoraEngineDirectOrderManagerV2QueryFacet via LASER DEPLOY_FACET',
    '{"short_id": "dv2q", "service": "lasersvc", "module": "agora", "facet_name": "AgoraEngineDirectOrderManagerV2QueryFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "agora", "workflow"]'::jsonb,
    '{"index": "54", "facet_name": "AgoraEngineDirectOrderManagerV2QueryFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 55: Deploy AgoraEngineEventStoreFacet
-- Service: lasersvc
-- Purpose: Deploy AgoraEngineEventStoreFacet via LASER DEPLOY_FACET (rev-21: current default revision)
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_agora_engine_event_store_facet',
    'deploy_lattice_facets',
    'Deploy AgoraEngineEventStoreFacet',
    'Deploy AgoraEngineEventStoreFacet via LASER DEPLOY_FACET',
    '{"short_id": "daes", "service": "lasersvc", "module": "agora", "facet_name": "AgoraEngineEventStoreFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "agora", "workflow"]'::jsonb,
    '{"index": "55", "facet_name": "AgoraEngineEventStoreFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- ============================================================================
-- SAGA STEP TEMPLATES: Korridor/Access Module (56-60)
-- ============================================================================

-- Step 56: Deploy AccessPointFacet
-- Service: lasersvc
-- Purpose: Deploy AccessPointFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_access_point_facet',
    'deploy_lattice_facets',
    'Deploy AccessPointFacet',
    'Deploy AccessPointFacet via LASER DEPLOY_FACET',
    '{"short_id": "dapf", "service": "lasersvc", "module": "korridor", "facet_name": "AccessPointFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "korridor", "workflow"]'::jsonb,
    '{"index": "56", "facet_name": "AccessPointFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 57: Deploy AccessPointSendManagerFacet
-- Service: lasersvc
-- Purpose: Deploy AccessPointSendManagerFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_access_point_send_manager_facet',
    'deploy_lattice_facets',
    'Deploy AccessPointSendManagerFacet',
    'Deploy AccessPointSendManagerFacet via LASER DEPLOY_FACET',
    '{"short_id": "daps", "service": "lasersvc", "module": "korridor", "facet_name": "AccessPointSendManagerFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "korridor", "workflow"]'::jsonb,
    '{"index": "57", "facet_name": "AccessPointSendManagerFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 58: Deploy AccessPointDeliveryManagerFacet
-- Service: lasersvc
-- Purpose: Deploy AccessPointDeliveryManagerFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_access_point_delivery_manager_facet',
    'deploy_lattice_facets',
    'Deploy AccessPointDeliveryManagerFacet',
    'Deploy AccessPointDeliveryManagerFacet via LASER DEPLOY_FACET',
    '{"short_id": "dapd", "service": "lasersvc", "module": "korridor", "facet_name": "AccessPointDeliveryManagerFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "korridor", "workflow"]'::jsonb,
    '{"index": "58", "facet_name": "AccessPointDeliveryManagerFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 59: Deploy AccessPointV2Facet
-- Service: lasersvc
-- Purpose: Deploy AccessPointV2Facet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_access_point_v2_facet',
    'deploy_lattice_facets',
    'Deploy AccessPointV2Facet',
    'Deploy AccessPointV2Facet via LASER DEPLOY_FACET',
    '{"short_id": "dap2", "service": "lasersvc", "module": "korridor", "facet_name": "AccessPointV2Facet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "korridor", "workflow"]'::jsonb,
    '{"index": "59", "facet_name": "AccessPointV2Facet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 60: Deploy AccessPointV3Facet
-- Service: lasersvc
-- Purpose: Deploy AccessPointV3Facet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_access_point_v3_facet',
    'deploy_lattice_facets',
    'Deploy AccessPointV3Facet',
    'Deploy AccessPointV3Facet via LASER DEPLOY_FACET',
    '{"short_id": "dap3", "service": "lasersvc", "module": "korridor", "facet_name": "AccessPointV3Facet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "korridor", "workflow"]'::jsonb,
    '{"index": "60", "facet_name": "AccessPointV3Facet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- ============================================================================
-- SAGA STEP TEMPLATES: Elysium Module (61-63)
-- ============================================================================

-- Step 61: Deploy ElysiumFacet
-- Service: lasersvc
-- Purpose: Deploy ElysiumFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_elysium_facet',
    'deploy_lattice_facets',
    'Deploy ElysiumFacet',
    'Deploy ElysiumFacet via LASER DEPLOY_FACET',
    '{"short_id": "delf", "service": "lasersvc", "module": "elysium", "facet_name": "ElysiumFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "elysium", "workflow"]'::jsonb,
    '{"index": "61", "facet_name": "ElysiumFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 62: Deploy ElysiumAdminFacet
-- Service: lasersvc
-- Purpose: Deploy ElysiumAdminFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_elysium_admin_facet',
    'deploy_lattice_facets',
    'Deploy ElysiumAdminFacet',
    'Deploy ElysiumAdminFacet via LASER DEPLOY_FACET',
    '{"short_id": "dela", "service": "lasersvc", "module": "elysium", "facet_name": "ElysiumAdminFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "elysium", "workflow"]'::jsonb,
    '{"index": "62", "facet_name": "ElysiumAdminFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 63: Deploy ElysiumPlanManagerFacet
-- Service: lasersvc
-- Purpose: Deploy ElysiumPlanManagerFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_elysium_plan_manager_facet',
    'deploy_lattice_facets',
    'Deploy ElysiumPlanManagerFacet',
    'Deploy ElysiumPlanManagerFacet via LASER DEPLOY_FACET',
    '{"short_id": "delp", "service": "lasersvc", "module": "elysium", "facet_name": "ElysiumPlanManagerFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "elysium", "workflow"]'::jsonb,
    '{"index": "63", "facet_name": "ElysiumPlanManagerFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- ============================================================================
-- SAGA STEP TEMPLATES: Frenzy/NFT Module (64-72)
-- ============================================================================

-- Step 64: Deploy MinterFacet
-- Service: lasersvc
-- Purpose: Deploy MinterFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_minter_facet',
    'deploy_lattice_facets',
    'Deploy MinterFacet',
    'Deploy MinterFacet via LASER DEPLOY_FACET',
    '{"short_id": "dmtf", "service": "lasersvc", "module": "frenzy", "facet_name": "MinterFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "frenzy", "workflow"]'::jsonb,
    '{"index": "64", "facet_name": "MinterFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 65: Deploy TokenStoreFacet
-- Service: lasersvc
-- Purpose: Deploy TokenStoreFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_token_store_facet',
    'deploy_lattice_facets',
    'Deploy TokenStoreFacet',
    'Deploy TokenStoreFacet via LASER DEPLOY_FACET',
    '{"short_id": "dtsf", "service": "lasersvc", "module": "frenzy", "facet_name": "TokenStoreFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "frenzy", "workflow"]'::jsonb,
    '{"index": "65", "facet_name": "TokenStoreFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 66: Deploy RoyaltyManagerFacet
-- Service: lasersvc
-- Purpose: Deploy RoyaltyManagerFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_royalty_manager_facet',
    'deploy_lattice_facets',
    'Deploy RoyaltyManagerFacet',
    'Deploy RoyaltyManagerFacet via LASER DEPLOY_FACET',
    '{"short_id": "drmf", "service": "lasersvc", "module": "frenzy", "facet_name": "RoyaltyManagerFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "frenzy", "workflow"]'::jsonb,
    '{"index": "66", "facet_name": "RoyaltyManagerFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 67: Deploy ReserveManagerFacet
-- Service: lasersvc
-- Purpose: Deploy ReserveManagerFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_reserve_manager_facet',
    'deploy_lattice_facets',
    'Deploy ReserveManagerFacet',
    'Deploy ReserveManagerFacet via LASER DEPLOY_FACET',
    '{"short_id": "drsm", "service": "lasersvc", "module": "frenzy", "facet_name": "ReserveManagerFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "frenzy", "workflow"]'::jsonb,
    '{"index": "67", "facet_name": "ReserveManagerFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 68: Deploy PaymentMethodManagerFacet
-- Service: lasersvc
-- Purpose: Deploy PaymentMethodManagerFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_payment_method_manager_facet',
    'deploy_lattice_facets',
    'Deploy PaymentMethodManagerFacet',
    'Deploy PaymentMethodManagerFacet via LASER DEPLOY_FACET',
    '{"short_id": "dpmm", "service": "lasersvc", "module": "frenzy", "facet_name": "PaymentMethodManagerFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "frenzy", "workflow"]'::jsonb,
    '{"index": "68", "facet_name": "PaymentMethodManagerFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 69: Deploy WhitelistManagerFacet
-- Service: lasersvc
-- Purpose: Deploy WhitelistManagerFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_whitelist_manager_facet',
    'deploy_lattice_facets',
    'Deploy WhitelistManagerFacet',
    'Deploy WhitelistManagerFacet via LASER DEPLOY_FACET',
    '{"short_id": "dwmf", "service": "lasersvc", "module": "frenzy", "facet_name": "WhitelistManagerFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "frenzy", "workflow"]'::jsonb,
    '{"index": "69", "facet_name": "WhitelistManagerFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 70: Deploy PaymentHandlerFacet
-- Service: lasersvc
-- Purpose: Deploy PaymentHandlerFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_payment_handler_facet',
    'deploy_lattice_facets',
    'Deploy PaymentHandlerFacet',
    'Deploy PaymentHandlerFacet via LASER DEPLOY_FACET',
    '{"short_id": "dphf", "service": "lasersvc", "module": "frenzy", "facet_name": "PaymentHandlerFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "frenzy", "workflow"]'::jsonb,
    '{"index": "70", "facet_name": "PaymentHandlerFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 71: Deploy ERC721Facet
-- Service: lasersvc
-- Purpose: Deploy ERC721Facet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_erc721_facet',
    'deploy_lattice_facets',
    'Deploy ERC721Facet',
    'Deploy ERC721Facet via LASER DEPLOY_FACET',
    '{"short_id": "d721", "service": "lasersvc", "module": "frenzy", "facet_name": "ERC721Facet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "frenzy", "workflow"]'::jsonb,
    '{"index": "71", "facet_name": "ERC721Facet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 72: Deploy CrossmintFacet
-- Service: lasersvc
-- Purpose: Deploy CrossmintFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_crossmint_facet',
    'deploy_lattice_facets',
    'Deploy CrossmintFacet',
    'Deploy CrossmintFacet via LASER DEPLOY_FACET',
    '{"short_id": "dcmf", "service": "lasersvc", "module": "frenzy", "facet_name": "CrossmintFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "frenzy", "workflow"]'::jsonb,
    '{"index": "72", "facet_name": "CrossmintFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- ============================================================================
-- SAGA STEP TEMPLATES: UTR Module (73-74)
-- ============================================================================

-- Step 73: Deploy UTRFacet
-- Service: lasersvc
-- Purpose: Deploy UTRFacet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_utr_facet',
    'deploy_lattice_facets',
    'Deploy UTRFacet',
    'Deploy UTRFacet via LASER DEPLOY_FACET',
    '{"short_id": "dutf", "service": "lasersvc", "module": "utr", "facet_name": "UTRFacet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "utr", "workflow"]'::jsonb,
    '{"index": "73", "facet_name": "UTRFacet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

-- Step 74: Deploy UTRV2Facet
-- Service: lasersvc
-- Purpose: Deploy UTRV2Facet via LASER DEPLOY_FACET
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'deploy_utr_v2_facet',
    'deploy_lattice_facets',
    'Deploy UTRV2Facet',
    'Deploy UTRV2Facet via LASER DEPLOY_FACET',
    '{"short_id": "dut2", "service": "lasersvc", "module": "utr", "facet_name": "UTRV2Facet"}'::jsonb,
    '["agora", "csd", "saga", "step", "lattice", "facet", "deploy", "laser", "ethereum", "utr", "workflow"]'::jsonb,
    '{"index": "74", "facet_name": "UTRV2Facet"}'::jsonb
)
ON CONFLICT (template_id) DO UPDATE SET
    saga_template_id = EXCLUDED.saga_template_id,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    labels = EXCLUDED.labels,
    tags = EXCLUDED.tags,
    metadata = EXCLUDED.metadata;

\echo 'Saga step templates (74 facets) created';

-- ============================================================================
-- SUMMARY
-- ============================================================================

\echo '';
\echo '============================================================';
\echo 'TLDINFRA TRAX Templates Complete!';
\echo '============================================================';
\echo '';
\echo 'Created:';
\echo '  - TRAX cluster: TLDINFRA';
\echo '  - Saga template: deploy_lattice_facets (73 steps)';
\echo '';