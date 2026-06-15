-- ============================================================================
-- TRAX Smoke Test Saga Template
-- ============================================================================
-- Purpose: Minimal saga template for E2E smoke testing
-- Usage: Load this file during E2E test database initialization when
--        ENABLE_TESTING_ENDPOINTS=true
--
-- Contains:
--   - smoke_test_template (1 step)
-- ============================================================================

\c agora_db;

-- ============================================================================
-- SAGA TEMPLATE: smoke_test_template
-- ============================================================================
-- Description: Minimal saga template for E2E smoke testing
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
    'smoke_test_template',
    'Smoke Test Template',
    'Minimal saga template for E2E smoke testing',
    '{"short_id": "smoke"}'::jsonb,
    '["test", "smoke", "e2e"]'::jsonb,
    '{"test_type": "smoke"}'::jsonb,
    '["smoke_test_step"]'::jsonb
)
ON CONFLICT (template_id) DO NOTHING;

-- ----------------------------------------------------------------------------
-- Steps for: smoke_test_template
-- ----------------------------------------------------------------------------

-- Step 1: Smoke Test Step
-- Purpose: Minimal step for smoke testing
INSERT INTO trax.saga_step_templates (
    template_id,
    saga_template_id,
    display_name,
    description,
    labels,
    tags,
    metadata
)
VALUES (
    'smoke_test_step',
    'smoke_test_template',
    'Smoke Test Step',
    'Minimal step for smoke testing',
    '{"short_id": "smokestep"}'::jsonb,
    '["test", "smoke", "e2e", "step"]'::jsonb,
    '{"index": "1"}'::jsonb
)
ON CONFLICT (template_id) DO NOTHING;