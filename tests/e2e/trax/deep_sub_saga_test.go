package trax_e2e_test

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xshyft/trax/pkg/trax"
	"github.com/xshyft/trax/tests/e2e/common/framework"
)

// subSagaExecutors returns executor configs for all deep sub-saga test templates.
func subSagaExecutors() []framework.ExecutorConfig {
	okResult := `{"status":"ok"}`
	simError := `{"error":"simulated_failure"}`

	return []framework.ExecutorConfig{
		// === 3-level success chain ===
		// L1: d3ok_l1_saga
		{SagaTemplateID: "d3ok_l1_saga", SagaStepTemplateID: "d3ok_l1s1", ExecSimStatus: "ok", ExecSimResult: okResult, CompSimStatus: "ok"},
		{SagaTemplateID: "d3ok_l1_saga", SagaStepTemplateID: "d3ok_l1_spawn", ExecSimStatus: "sub-saga", SubSagaTemplateID: "d3ok_l2_saga"},
		// L2: d3ok_l2_saga
		{SagaTemplateID: "d3ok_l2_saga", SagaStepTemplateID: "d3ok_l2s1", ExecSimStatus: "ok", ExecSimResult: okResult, CompSimStatus: "ok"},
		{SagaTemplateID: "d3ok_l2_saga", SagaStepTemplateID: "d3ok_l2_spawn", ExecSimStatus: "sub-saga", SubSagaTemplateID: "d3ok_l3_saga"},
		// L3: d3ok_l3_saga (leaf)
		{SagaTemplateID: "d3ok_l3_saga", SagaStepTemplateID: "d3ok_l3s1", ExecSimStatus: "ok", ExecSimResult: okResult, CompSimStatus: "ok"},
		{SagaTemplateID: "d3ok_l3_saga", SagaStepTemplateID: "d3ok_l3s2", ExecSimStatus: "ok", ExecSimResult: okResult, CompSimStatus: "ok"},

		// === 4-level failure chain ===
		// L1: d4f_l1_saga
		{SagaTemplateID: "d4f_l1_saga", SagaStepTemplateID: "d4f_l1s1", ExecSimStatus: "ok", ExecSimResult: okResult, CompSimStatus: "ok"},
		{SagaTemplateID: "d4f_l1_saga", SagaStepTemplateID: "d4f_l1_spawn", ExecSimStatus: "sub-saga", SubSagaTemplateID: "d4f_l2_saga"},
		// L2: d4f_l2_saga
		{SagaTemplateID: "d4f_l2_saga", SagaStepTemplateID: "d4f_l2s1", ExecSimStatus: "ok", ExecSimResult: okResult, CompSimStatus: "ok"},
		{SagaTemplateID: "d4f_l2_saga", SagaStepTemplateID: "d4f_l2_spawn", ExecSimStatus: "sub-saga", SubSagaTemplateID: "d4f_l3_saga"},
		// L3: d4f_l3_saga
		{SagaTemplateID: "d4f_l3_saga", SagaStepTemplateID: "d4f_l3s1", ExecSimStatus: "ok", ExecSimResult: okResult, CompSimStatus: "ok"},
		{SagaTemplateID: "d4f_l3_saga", SagaStepTemplateID: "d4f_l3_spawn", ExecSimStatus: "sub-saga", SubSagaTemplateID: "d4f_l4_saga"},
		// L4: d4f_l4_saga (leaf, step2 fails)
		{SagaTemplateID: "d4f_l4_saga", SagaStepTemplateID: "d4f_l4s1", ExecSimStatus: "ok", ExecSimResult: okResult, CompSimStatus: "ok"},
		{SagaTemplateID: "d4f_l4_saga", SagaStepTemplateID: "d4f_l4s2_err", ExecSimStatus: "error", ExecSimError: simError, CompSimStatus: "ok"},
	}
}

// setupSubSagaEnv creates the E2E environment, sub-saga templates, and starts executors.
func setupSubSagaEnv(t *testing.T) (*framework.E2EEnvironment, func()) {
	t.Helper()

	env := framework.NewE2EEnvironment(t, framework.Config{
		Services: []string{
			"traxctrl",
			"test.traxcoord1",
			"test.traxcoord2",
			"test.traxcoord3",
		},
		LogOnlyServices: []string{"traxcli-submitter"},
		TestDBName:      "",
		AutoSwitchDB:    true,
		CaptureResults:  true,
		InitSchemas:     []string{"trax", "test_cluster"},
		ClusterID:       "e2e_test_cluster",
	})

	verifyCusterExists(t)

	err := framework.CreateSubSagaTemplatesViaTraxcli(t, env.GetTestDBName())
	require.NoError(t, err, "Failed to create sub-saga templates")

	err = framework.WaitForCoordinatorReadiness(t, 3)
	require.NoError(t, err, "Coordinators should be ready")

	// Start executors dynamically inside the traxcli-submitter container
	cleanupExecutors := framework.StartExecutorsViaDockerExec(t, subSagaExecutors(), "e2e_test_cluster")

	return env, cleanupExecutors
}

// submitSubSagaSaga submits a sub-saga test saga via traxcli submitter.
func submitSubSagaSaga(t *testing.T, templateID string) string {
	t.Helper()

	sagaID, err := framework.SubmitSagaViaTraxcli(
		t,
		"traxcli-sub-saga-test-submitter",
		"e2e_test_cluster",
		templateID,
	)
	require.NoError(t, err, "Failed to submit saga %s", templateID)
	require.NotEmpty(t, sagaID, "Saga ID should not be empty")

	return sagaID
}

// TestDeepSubSaga_3Level_AllCommitted tests a 3-level deep sub-saga hierarchy
// where all sagas complete successfully.
//
// Hierarchy:
//
//	L1 (d3ok_l1_saga):  step1 ok → spawn L2 → COMMITTED
//	L2 (d3ok_l2_saga):    step1 ok → spawn L3 → COMMITTED
//	L3 (d3ok_l3_saga):      step1 ok → step2 ok → COMMITTED
//
// Verifies: parent-child relationships, saga_depth, root_saga_instance_id, final states
func TestDeepSubSaga_3Level_AllCommitted(t *testing.T) {
	t.Log("=== Deep Sub-Saga: 3-Level All Committed ===")

	env, cleanupExec := setupSubSagaEnv(t)
	defer env.Cleanup()
	defer cleanupExec()

	t.Log("Submitting d3ok_l1_saga (root, level 1)...")
	rootSagaID := submitSubSagaSaga(t, "d3ok_l1_saga")
	t.Logf("Root saga submitted: %s", rootSagaID)

	// Poll for root saga to reach COMMITTED (long timeout for 3-level chain)
	t.Log("Polling for root saga COMMITTED state...")
	err := framework.PollSagaStatus(t, "traxctrl", rootSagaID,
		"e2e_test_cluster", string(trax.SagaStateEnum_Committed), 300*time.Second)
	require.NoError(t, err, "Root saga should reach COMMITTED state")
	t.Log("Root saga COMMITTED")

	// Verify root saga steps
	rootSteps, err := framework.GetSagaStepStatuses(t, "traxctrl", rootSagaID, "e2e_test_cluster")
	require.NoError(t, err)
	require.Len(t, rootSteps, 2, "Root saga should have 2 steps")
	for i, step := range rootSteps {
		t.Logf("L1 Step %d [%s]: %s", i+1,
			framework.ShortenTemplateID(step.StepTemplateID),
			framework.ShortenStepState(step.Status))
		require.Equal(t, string(trax.SagaStepStateEnum_ExecutionDone), step.Status,
			"L1 Step %d should be ExecutionDone", i+1)
	}

	// Verify hierarchy: root saga should have children
	rootFull, err := framework.GetSagaInstanceFull(t, "traxctrl", rootSagaID, "e2e_test_cluster")
	require.NoError(t, err)

	// Check root has depth 0
	sagaDepth, _ := rootFull["saga_depth"].(float64)
	require.Equal(t, float64(0), sagaDepth, "Root saga should have depth 0")

	// Get L2 child
	children, err := framework.GetSagaInstanceChildren(t, "traxctrl", rootSagaID, "e2e_test_cluster")
	require.NoError(t, err)
	require.Len(t, children, 1, "Root saga should have 1 child (L2)")
	l2SagaID, _ := children[0]["instance_id"].(string)
	l2State, _ := children[0]["state"].(string)
	t.Logf("L2 saga: %s, state: %s", framework.ShortenID(l2SagaID), framework.ShortenSagaState(l2State))
	require.Equal(t, string(trax.SagaStateEnum_Committed), l2State, "L2 saga should be COMMITTED")

	// Verify L2 depth
	l2Full, err := framework.GetSagaInstanceFull(t, "traxctrl", l2SagaID, "e2e_test_cluster")
	require.NoError(t, err)
	l2Depth, _ := l2Full["saga_depth"].(float64)
	require.Equal(t, float64(1), l2Depth, "L2 saga should have depth 1")
	l2Root, _ := l2Full["root_saga_instance_id"].(string)
	require.Equal(t, rootSagaID, l2Root, "L2 root should point to L1")

	// Get L3 child
	l2Children, err := framework.GetSagaInstanceChildren(t, "traxctrl", l2SagaID, "e2e_test_cluster")
	require.NoError(t, err)
	require.Len(t, l2Children, 1, "L2 saga should have 1 child (L3)")
	l3SagaID, _ := l2Children[0]["instance_id"].(string)
	l3State, _ := l2Children[0]["state"].(string)
	t.Logf("L3 saga: %s, state: %s", framework.ShortenID(l3SagaID), framework.ShortenSagaState(l3State))
	require.Equal(t, string(trax.SagaStateEnum_Committed), l3State, "L3 saga should be COMMITTED")

	// Verify L3 depth
	l3Full, err := framework.GetSagaInstanceFull(t, "traxctrl", l3SagaID, "e2e_test_cluster")
	require.NoError(t, err)
	l3Depth, _ := l3Full["saga_depth"].(float64)
	require.Equal(t, float64(2), l3Depth, "L3 saga should have depth 2")
	l3Root, _ := l3Full["root_saga_instance_id"].(string)
	require.Equal(t, rootSagaID, l3Root, "L3 root should point to L1")

	// Verify full tree
	tree, err := framework.GetSagaInstanceTree(t, "traxctrl", rootSagaID, "e2e_test_cluster")
	require.NoError(t, err)
	require.Len(t, tree, 3, "Tree should have 3 saga instances (L1 + L2 + L3)")
	t.Logf("Full tree has %d saga instances", len(tree))

	t.Log("TestDeepSubSaga_3Level_AllCommitted PASSED!")
}

// TestDeepSubSaga_4Level_DeepFailureCompensation tests a 4-level deep sub-saga hierarchy
// where the deepest level (L4) fails, triggering cascading compensation through all levels.
//
// Hierarchy:
//
//	L1 (d4f_l1_saga):  step1 ok → spawn L2 → L2 fails → compensate step1 → COMPENSATED
//	L2 (d4f_l2_saga):    step1 ok → spawn L3 → L3 fails → compensate step1 → COMPENSATED
//	L3 (d4f_l3_saga):      step1 ok → spawn L4 → L4 fails → compensate step1 → COMPENSATED
//	L4 (d4f_l4_saga):        step1 ok → step2 FAILS → compensate step1 → COMPENSATED
//
// This verifies that compensation cascades correctly through multiple sub-saga levels.
func TestDeepSubSaga_4Level_DeepFailureCompensation(t *testing.T) {
	t.Log("=== Deep Sub-Saga: 4-Level Deep Failure with Cascading Compensation ===")

	env, cleanupExec := setupSubSagaEnv(t)
	defer env.Cleanup()
	defer cleanupExec()

	t.Log("Submitting d4f_l1_saga (root, level 1)...")
	rootSagaID := submitSubSagaSaga(t, "d4f_l1_saga")
	t.Logf("Root saga submitted: %s", rootSagaID)

	// Poll for root saga to reach COMPENSATED (long timeout for 4-level chain + compensation)
	t.Log("Polling for root saga COMPENSATED state...")
	err := framework.PollSagaStatus(t, "traxctrl", rootSagaID,
		"e2e_test_cluster", string(trax.SagaStateEnum_Compensated), 600*time.Second)
	require.NoError(t, err, "Root saga should reach COMPENSATED state")
	t.Log("Root saga COMPENSATED")

	// Verify root saga steps
	rootSteps, err := framework.GetSagaStepStatuses(t, "traxctrl", rootSagaID, "e2e_test_cluster")
	require.NoError(t, err)
	require.Len(t, rootSteps, 2, "Root saga should have 2 steps")
	for i, step := range rootSteps {
		t.Logf("L1 Step %d [%s]: %s", i+1,
			framework.ShortenTemplateID(step.StepTemplateID),
			framework.ShortenStepState(step.Status))
	}

	// L1 step1 should be CompensationDone (succeeded, then compensated)
	require.Equal(t, string(trax.SagaStepStateEnum_CompensationDone), rootSteps[0].Status,
		"L1 step1 should be CompensationDone")
	// L1 step2 (spawn) should be CompensationDone (failed step also gets compensated)
	require.Equal(t, string(trax.SagaStepStateEnum_CompensationDone), rootSteps[1].Status,
		"L1 step2 (spawn) should be CompensationDone (failed step also gets compensated)")

	// Traverse the hierarchy to verify all levels compensated
	children, err := framework.GetSagaInstanceChildren(t, "traxctrl", rootSagaID, "e2e_test_cluster")
	require.NoError(t, err)
	require.Len(t, children, 1, "L1 should have 1 child (L2)")
	l2SagaID, _ := children[0]["instance_id"].(string)
	l2State, _ := children[0]["state"].(string)
	t.Logf("L2 saga: %s, state: %s", framework.ShortenID(l2SagaID), framework.ShortenSagaState(l2State))
	require.Equal(t, string(trax.SagaStateEnum_Compensated), l2State, "L2 should be COMPENSATED")

	l2Children, err := framework.GetSagaInstanceChildren(t, "traxctrl", l2SagaID, "e2e_test_cluster")
	require.NoError(t, err)
	require.Len(t, l2Children, 1, "L2 should have 1 child (L3)")
	l3SagaID, _ := l2Children[0]["instance_id"].(string)
	l3State, _ := l2Children[0]["state"].(string)
	t.Logf("L3 saga: %s, state: %s", framework.ShortenID(l3SagaID), framework.ShortenSagaState(l3State))
	require.Equal(t, string(trax.SagaStateEnum_Compensated), l3State, "L3 should be COMPENSATED")

	l3Children, err := framework.GetSagaInstanceChildren(t, "traxctrl", l3SagaID, "e2e_test_cluster")
	require.NoError(t, err)
	require.Len(t, l3Children, 1, "L3 should have 1 child (L4)")
	l4SagaID, _ := l3Children[0]["instance_id"].(string)
	l4State, _ := l3Children[0]["state"].(string)
	t.Logf("L4 saga: %s, state: %s", framework.ShortenID(l4SagaID), framework.ShortenSagaState(l4State))
	require.Equal(t, string(trax.SagaStateEnum_Compensated), l4State, "L4 should be COMPENSATED")

	// Verify L4 (leaf) step details
	l4Steps, err := framework.GetSagaStepStatuses(t, "traxctrl", l4SagaID, "e2e_test_cluster")
	require.NoError(t, err)
	require.Len(t, l4Steps, 2, "L4 should have 2 steps")
	for i, step := range l4Steps {
		t.Logf("L4 Step %d [%s]: %s", i+1,
			framework.ShortenTemplateID(step.StepTemplateID),
			framework.ShortenStepState(step.Status))
	}
	// L4 step1 was compensated, step2 failed but also gets compensated
	require.Equal(t, string(trax.SagaStepStateEnum_CompensationDone), l4Steps[0].Status,
		"L4 step1 should be CompensationDone")
	require.Equal(t, string(trax.SagaStepStateEnum_CompensationDone), l4Steps[1].Status,
		"L4 step2 should be CompensationDone (failed step also gets compensated)")

	// Verify hierarchy depths
	l4Full, err := framework.GetSagaInstanceFull(t, "traxctrl", l4SagaID, "e2e_test_cluster")
	require.NoError(t, err)
	l4Depth, _ := l4Full["saga_depth"].(float64)
	require.Equal(t, float64(3), l4Depth, "L4 should have depth 3")
	l4Root, _ := l4Full["root_saga_instance_id"].(string)
	require.Equal(t, rootSagaID, l4Root, "L4 root should point to L1")

	// Verify full tree
	tree, err := framework.GetSagaInstanceTree(t, "traxctrl", rootSagaID, "e2e_test_cluster")
	require.NoError(t, err)
	require.Len(t, tree, 4, "Tree should have 4 saga instances (L1 + L2 + L3 + L4)")
	t.Logf("Full tree has %d saga instances, all compensated through cascading failure", len(tree))

	t.Log("TestDeepSubSaga_4Level_DeepFailureCompensation PASSED!")
}
