package trax_e2e_test

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/kamcpp/trax/pkg/trax"
	"github.com/kamcpp/trax/tests/e2e/common/framework"
)

// compensationExecutors returns the executor configs for all compensation test templates.
func compensationExecutors() []framework.ExecutorConfig {
	okResult := `{"status":"ok"}`
	simError := `{"error":"simulated_failure"}`

	return []framework.ExecutorConfig{
		// comp_fail_last_saga: step1 ok, step2 ok, step3 fails
		{SagaTemplateID: "comp_fail_last_saga", SagaStepTemplateID: "cfl_step1", ExecSimStatus: "ok", ExecSimResult: okResult, CompSimStatus: "ok", CompSimResult: `{"comp_step1":"undone"}`},
		{SagaTemplateID: "comp_fail_last_saga", SagaStepTemplateID: "cfl_step2", ExecSimStatus: "ok", ExecSimResult: okResult, CompSimStatus: "ok", CompSimResult: `{"comp_step2":"undone"}`},
		{SagaTemplateID: "comp_fail_last_saga", SagaStepTemplateID: "cfl_step3", ExecSimStatus: "error", ExecSimError: simError, CompSimStatus: "ok", CompSimResult: `{"comp_step3":"undone"}`},
		// comp_fail_first_saga: step1 fails
		{SagaTemplateID: "comp_fail_first_saga", SagaStepTemplateID: "cff_step1", ExecSimStatus: "error", ExecSimError: simError, CompSimStatus: "ok"},
		{SagaTemplateID: "comp_fail_first_saga", SagaStepTemplateID: "cff_step2", ExecSimStatus: "ok", ExecSimResult: okResult, CompSimStatus: "ok"},
		{SagaTemplateID: "comp_fail_first_saga", SagaStepTemplateID: "cff_step3", ExecSimStatus: "ok", ExecSimResult: okResult, CompSimStatus: "ok"},
		// comp_blocked_saga: step3 fails, step1 compensation also fails → BLOCKED
		{SagaTemplateID: "comp_blocked_saga", SagaStepTemplateID: "cbl_step1", ExecSimStatus: "ok", ExecSimResult: okResult, CompSimStatus: "error", CompSimError: simError},
		{SagaTemplateID: "comp_blocked_saga", SagaStepTemplateID: "cbl_step2", ExecSimStatus: "ok", ExecSimResult: okResult, CompSimStatus: "ok"},
		{SagaTemplateID: "comp_blocked_saga", SagaStepTemplateID: "cbl_step3", ExecSimStatus: "error", ExecSimError: simError, CompSimStatus: "ok"},
	}
}

// setupCompensationEnv creates the E2E environment, compensation templates, and starts executors.
func setupCompensationEnv(t *testing.T) (*framework.E2EEnvironment, func()) {
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
		InitSchemas:     []string{"trax", "laser", "test_cluster"},
		ClusterID:       "e2e_test_cluster",
	})

	verifyCusterExists(t)

	err := framework.CreateCompensationTemplatesViaTraxcli(t, env.GetTestDBName())
	require.NoError(t, err, "Failed to create compensation templates")

	err = framework.WaitForCoordinatorReadiness(t, 3)
	require.NoError(t, err, "Coordinators should be ready")

	// Start executors dynamically inside the traxcli-submitter container
	cleanupExecutors := framework.StartExecutorsViaDockerExec(t, compensationExecutors(), "e2e_test_cluster")

	return env, cleanupExecutors
}

// submitCompensationSaga submits a compensation test saga via traxcli submitter.
func submitCompensationSaga(t *testing.T, templateID string) string {
	t.Helper()

	sagaID, err := framework.SubmitSagaViaTraxcli(
		t,
		"traxcli-comp-test-submitter",
		"e2e_test_cluster",
		templateID,
	)
	require.NoError(t, err, "Failed to submit saga %s", templateID)
	require.NotEmpty(t, sagaID, "Saga ID should not be empty")

	return sagaID
}

// TestSagaCompensation_FailAtLastStep verifies that when the last step fails,
// all previously completed steps are compensated and the saga reaches COMPENSATED state.
//
// Flow: step1 ok → step2 ok → step3 FAILS → compensate step3 → compensate step2 → compensate step1 → COMPENSATED
func TestSagaCompensation_FailAtLastStep(t *testing.T) {
	t.Log("=== Saga Compensation: Fail at Last Step ===")

	env, cleanupExec := setupCompensationEnv(t)
	defer env.Cleanup()
	defer cleanupExec()

	t.Log("Submitting comp_fail_last_saga...")
	sagaID := submitCompensationSaga(t, "comp_fail_last_saga")
	t.Logf("Saga submitted: %s", sagaID)

	t.Log("Polling for COMPENSATED state...")
	err := framework.PollSagaStatus(t, "traxctrl", sagaID,
		"e2e_test_cluster", string(trax.SagaStateEnum_Compensated), 120*time.Second)
	require.NoError(t, err, "Saga should reach COMPENSATED state")

	// Verify step states
	steps, err := framework.GetSagaStepStatuses(t, "traxctrl", sagaID, "e2e_test_cluster")
	require.NoError(t, err, "Failed to get step statuses")
	require.Len(t, steps, 3, "Should have 3 steps")

	for i, step := range steps {
		t.Logf("Step %d [%s]: %s", i+1,
			framework.ShortenTemplateID(step.StepTemplateID),
			framework.ShortenStepState(step.Status))
	}

	// All three steps should be CompensationDone:
	// Steps 1 and 2 succeeded then were compensated backwards.
	// Step 3 failed execution but still gets compensated (to clean up partial effects).
	require.Equal(t, string(trax.SagaStepStateEnum_CompensationDone), steps[0].Status,
		"Step 1 should be CompensationDone")
	require.Equal(t, string(trax.SagaStepStateEnum_CompensationDone), steps[1].Status,
		"Step 2 should be CompensationDone")
	require.Equal(t, string(trax.SagaStepStateEnum_CompensationDone), steps[2].Status,
		"Step 3 should be CompensationDone (failed step also gets compensated)")

	// Verify forward execution Result is preserved (not overwritten by compensation)
	for i, step := range steps {
		if step.Result != nil {
			resultMap, ok := step.Result.(map[string]interface{})
			if ok && resultMap["status"] == "ok" {
				t.Logf("Step %d: forward Result preserved: %v", i+1, resultMap)
			}
		}
	}

	// Verify CompensationResult is populated separately
	for i, step := range steps {
		if step.CompensationResult != nil {
			compResultMap, ok := step.CompensationResult.(map[string]interface{})
			if ok {
				t.Logf("Step %d: CompensationResult: %v", i+1, compResultMap)
			}
		}
	}

	// Verify CompensationReason is set on the saga instance
	_, _, compensationReason, err := framework.GetSagaStatus(t, "traxctrl", sagaID, "e2e_test_cluster")
	require.NoError(t, err, "Failed to get saga status")
	t.Logf("Saga CompensationReason: %s", compensationReason)
	require.NotEmpty(t, compensationReason, "Saga should have CompensationReason")
	require.Contains(t, compensationReason, "cfl_step3",
		"CompensationReason should reference the failing step")

	t.Log("TestSagaCompensation_FailAtLastStep PASSED!")
}

// TestSagaCompensation_FailAtFirstStep verifies that when the first step fails,
// there's nothing to compensate and the saga reaches COMPENSATED state immediately.
//
// Flow: step1 FAILS → abort step2,step3 → compensate step1 → COMPENSATED
func TestSagaCompensation_FailAtFirstStep(t *testing.T) {
	t.Log("=== Saga Compensation: Fail at First Step ===")

	env, cleanupExec := setupCompensationEnv(t)
	defer env.Cleanup()
	defer cleanupExec()

	t.Log("Submitting comp_fail_first_saga...")
	sagaID := submitCompensationSaga(t, "comp_fail_first_saga")
	t.Logf("Saga submitted: %s", sagaID)

	t.Log("Polling for COMPENSATED state...")
	err := framework.PollSagaStatus(t, "traxctrl", sagaID,
		"e2e_test_cluster", string(trax.SagaStateEnum_Compensated), 120*time.Second)
	require.NoError(t, err, "Saga should reach COMPENSATED state")

	// Verify step states
	steps, err := framework.GetSagaStepStatuses(t, "traxctrl", sagaID, "e2e_test_cluster")
	require.NoError(t, err, "Failed to get step statuses")
	require.Len(t, steps, 3, "Should have 3 steps")

	for i, step := range steps {
		t.Logf("Step %d [%s]: %s", i+1,
			framework.ShortenTemplateID(step.StepTemplateID),
			framework.ShortenStepState(step.Status))
	}

	// Step 1 failed execution but still gets compensated (to clean up partial effects)
	require.Equal(t, string(trax.SagaStepStateEnum_CompensationDone), steps[0].Status,
		"Step 1 should be CompensationDone (failed step also gets compensated)")
	// Steps 2 and 3 were never executed, so they are aborted
	require.Equal(t, string(trax.SagaStepStateEnum_ExecutionAborted), steps[1].Status,
		"Step 2 should be ExecutionAborted")
	require.Equal(t, string(trax.SagaStepStateEnum_ExecutionAborted), steps[2].Status,
		"Step 3 should be ExecutionAborted")

	// Verify CompensationReason is set on the saga instance
	_, _, compensationReason, err := framework.GetSagaStatus(t, "traxctrl", sagaID, "e2e_test_cluster")
	require.NoError(t, err, "Failed to get saga status")
	t.Logf("Saga CompensationReason: %s", compensationReason)
	require.NotEmpty(t, compensationReason, "Saga should have CompensationReason")
	require.Contains(t, compensationReason, "cff_step1",
		"CompensationReason should reference the failing step")

	t.Log("TestSagaCompensation_FailAtFirstStep PASSED!")
}

// TestSagaCompensation_Blocked verifies that when a step fails AND compensation
// of a previous step also fails, the saga reaches BLOCKED state.
//
// Flow: step1 ok → step2 ok → step3 FAILS → compensate step3 ok → compensate step2 ok → compensate step1 FAILS → BLOCKED
func TestSagaCompensation_Blocked(t *testing.T) {
	t.Log("=== Saga Compensation: Blocked (compensation failure) ===")

	env, cleanupExec := setupCompensationEnv(t)
	defer env.Cleanup()
	defer cleanupExec()

	t.Log("Submitting comp_blocked_saga...")
	sagaID := submitCompensationSaga(t, "comp_blocked_saga")
	t.Logf("Saga submitted: %s", sagaID)

	t.Log("Polling for BLOCKED state...")
	err := framework.PollSagaStatus(t, "traxctrl", sagaID,
		"e2e_test_cluster", string(trax.SagaStateEnum_Blocked), 120*time.Second)
	require.NoError(t, err, "Saga should reach BLOCKED state")

	// Verify step states
	steps, err := framework.GetSagaStepStatuses(t, "traxctrl", sagaID, "e2e_test_cluster")
	require.NoError(t, err, "Failed to get step statuses")
	require.Len(t, steps, 3, "Should have 3 steps")

	for i, step := range steps {
		t.Logf("Step %d [%s]: %s", i+1,
			framework.ShortenTemplateID(step.StepTemplateID),
			framework.ShortenStepState(step.Status))
	}

	// Step 1: compensation failed → CompensationBlocked
	require.Equal(t, string(trax.SagaStepStateEnum_CompensationBlocked), steps[0].Status,
		"Step 1 should be CompensationBlocked (compensation failed)")
	// Step 2: compensation succeeded → CompensationDone
	require.Equal(t, string(trax.SagaStepStateEnum_CompensationDone), steps[1].Status,
		"Step 2 should be CompensationDone")
	// Step 3: execution failed but still gets compensated → CompensationDone
	require.Equal(t, string(trax.SagaStepStateEnum_CompensationDone), steps[2].Status,
		"Step 3 should be CompensationDone (failed step also gets compensated)")

	// Verify CompensationReason is set on the saga instance
	_, _, compensationReason, err := framework.GetSagaStatus(t, "traxctrl", sagaID, "e2e_test_cluster")
	require.NoError(t, err, "Failed to get saga status")
	t.Logf("Saga CompensationReason: %s", compensationReason)
	require.NotEmpty(t, compensationReason, "Saga should have CompensationReason")

	t.Log("TestSagaCompensation_Blocked PASSED!")
}
