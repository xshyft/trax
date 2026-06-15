package trax_e2e_test

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/kamcpp/trax/pkg/trax"
	"github.com/kamcpp/trax/tests/e2e/common/framework"
)

// TestSagaHierarchyFields verifies that saga instances include parent-child hierarchy fields
// in the API response. For a top-level saga:
//   - root_saga_instance_id should be set to the saga's own instance ID
//   - saga_depth should be 0
//   - parent_saga_instance_id and parent_saga_step_instance_id should be empty
//
// Also verifies the children and tree endpoints return empty results for a top-level saga
// with no children.
func TestSagaHierarchyFields(t *testing.T) {
	t.Log("=== Saga Hierarchy Fields E2E Test ===")

	env := framework.NewE2EEnvironment(t, framework.Config{
		Services: []string{
			"traxctrl",
			"test.traxcoord1",
			"test.traxcoord2",
			"test.traxcoord3",
		},
		LogOnlyServices: []string{
			"traxcli-submitter",
			"executor-step1",
			"executor-step2",
			"executor-step3",
			"executor-step4",
			"executor-step5",
			"executor-step6",
			"executor-step7",
		},
		TestDBName:     "",
		AutoSwitchDB:   true,
		CaptureResults: true,
		InitSchemas:    []string{"trax", "laser", "test_cluster"},
		ClusterID:      "e2e_test_cluster",
	})
	defer env.Cleanup()

	t.Log("Step 1: Creating seven step saga template...")
	err := framework.CreateSevenStepTemplateViaTraxcli(t, env.GetTestDBName())
	require.NoError(t, err, "Failed to create saga template")

	t.Log("Step 2: Waiting for coordinators...")
	err = framework.WaitForCoordinatorReadiness(t, 3)
	require.NoError(t, err, "Coordinators should be ready")

	t.Log("Step 3: Submitting saga instance...")
	sagaID := submitSevenStepSaga(t)
	require.NotEmpty(t, sagaID, "Saga ID should not be empty")
	t.Logf("Saga submitted: %s", sagaID)

	t.Log("Step 4: Polling for saga completion...")
	err = framework.PollSagaStatus(t, "traxctrl", sagaID, "e2e_test_cluster", string(trax.SagaStateEnum_Committed), 180*time.Second)
	require.NoError(t, err, "Saga should complete successfully")

	t.Log("Step 5: Verifying hierarchy fields on saga instance...")
	sagaInstance, err := framework.GetSagaInstanceFull(t, "traxctrl", sagaID, "e2e_test_cluster")
	require.NoError(t, err, "Should be able to get saga instance")

	// Top-level saga should have root = self
	rootID, _ := sagaInstance["root_saga_instance_id"].(string)
	require.Equal(t, sagaID, rootID, "root_saga_instance_id should equal the saga's own ID for top-level sagas")

	// Top-level saga should have depth 0
	sagaDepth, _ := sagaInstance["saga_depth"].(float64) // JSON numbers decode as float64
	require.Equal(t, float64(0), sagaDepth, "saga_depth should be 0 for top-level sagas")

	// Top-level saga should have no parent
	parentID, _ := sagaInstance["parent_saga_instance_id"].(string)
	require.Empty(t, parentID, "parent_saga_instance_id should be empty for top-level sagas")

	parentStepID, _ := sagaInstance["parent_saga_step_instance_id"].(string)
	require.Empty(t, parentStepID, "parent_saga_step_instance_id should be empty for top-level sagas")

	t.Log("Step 6: Verifying children endpoint returns empty for top-level saga...")
	children, err := framework.GetSagaInstanceChildren(t, "traxctrl", sagaID, "e2e_test_cluster")
	require.NoError(t, err, "Should be able to query children")
	require.Empty(t, children, "Top-level saga with no sub-sagas should have no children")

	t.Log("Step 7: Verifying tree endpoint returns only the root saga...")
	tree, err := framework.GetSagaInstanceTree(t, "traxctrl", sagaID, "e2e_test_cluster")
	require.NoError(t, err, "Should be able to query tree")
	// Tree should contain at least the root itself (all sagas with this root_saga_instance_id)
	// For a top-level saga with no children, tree contains just itself
	require.Len(t, tree, 1, "Tree should contain exactly the root saga")
	treeRootID, _ := tree[0]["instance_id"].(string)
	require.Equal(t, sagaID, treeRootID, "Tree root should be the saga itself")

	t.Log("Saga Hierarchy Fields E2E Test PASSED!")
}
