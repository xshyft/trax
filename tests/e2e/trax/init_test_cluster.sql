-- Insert e2e_test_cluster for TRAX E2E tests
-- This must exist before instrmgr announces itself as a saga submitter
-- Note: cluster ID must use underscores, not hyphens, as it's used in table names

INSERT INTO trax.clusters (id, display_name, description, tags, created_at, updated_at)
VALUES (
    'e2e_test_cluster',
    'E2E Test Cluster',
    'TRAX cluster for E2E testing',
    '["e2e", "test"]'::jsonb,
    NOW(),
    NOW()
)
ON CONFLICT (id) DO NOTHING;