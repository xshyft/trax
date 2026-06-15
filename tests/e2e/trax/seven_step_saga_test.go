package trax_e2e_test

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/kamcpp/trax/pkg/trax"
	"github.com/kamcpp/trax/tests/e2e/common/framework"
)

// TestSevenStepSaga tests a complete 7-step saga workflow
// Each step sleeps for 1000ms and returns success
func TestSevenStepSaga(t *testing.T) {
	t.Log("=== Seven Step Saga E2E Test ===")

	// Framework handles EVERYTHING automatically:
	// - Test results capture
	// - DB creation/initialization
	// - Service health checks
	// - Database switching for all services
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
		TestDBName:      "", // Generate random name
		AutoSwitchDB:    true,
		CaptureResults:  true,
		InitSchemas:     []string{"trax", "laser", "test_cluster"}, // Initialize schemas
		ClusterID:       "e2e_test_cluster",
		AdditionalSetup: nil, // No additional setup needed
	})
	defer env.Cleanup() // Automatic: capture logs, DB dumps, generate HTML

	t.Log("Step 1: Verifying e2e_test_cluster exists...")
	verifyCusterExists(t)
	t.Log("✓ Cluster verified")

	t.Log("Step 2: Creating seven step saga template...")
	err := framework.CreateSevenStepTemplateViaTraxcli(t, env.GetTestDBName())
	require.NoError(t, err, "Failed to create saga template")
	t.Log("✓ Saga template created")

	t.Log("Step 3: Waiting for coordinators to be ready...")
	err = framework.WaitForCoordinatorReadiness(t, 3)
	require.NoError(t, err, "Coordinators should be ready")
	t.Log("✓ Coordinators ready")

	t.Log("Step 4: Submitting saga instance...")
	sagaID := submitSevenStepSaga(t)
	t.Logf("✓ Saga submitted: %s", sagaID)

	t.Log("Step 5: Polling for saga completion...")
	err = framework.PollSagaStatus(t, "traxctrl", sagaID, "e2e_test_cluster", string(trax.SagaStateEnum_Committed), 180*time.Second)
	require.NoError(t, err, "Saga should complete successfully")
	t.Log("✓ Saga completed")

	t.Log("Step 6: Verifying all 7 steps completed...")
	verifyAllStepsCompleted(t, sagaID)
	t.Log("✓ All steps verified")

	t.Log("✓ Seven Step Saga E2E Test PASSED!")
}

// verifyCusterExists verifies the e2e_test_cluster exists
func verifyCusterExists(t *testing.T) {
	t.Helper()

	clusters, err := framework.ListClusters(t, "traxctrl")
	require.NoError(t, err, "Failed to list clusters")
	require.Contains(t, clusters, "e2e_test_cluster", "e2e_test_cluster should exist")
}

// submitSevenStepSaga submits the saga instance via traxcli submitter
func submitSevenStepSaga(t *testing.T) string {
	t.Helper()

	sagaID, err := framework.SubmitSagaViaTraxcli(
		t,
		"traxcli-e2e-test-submitter",
		"e2e_test_cluster",
		"seven_step_sleep_saga",
	)
	require.NoError(t, err, "Failed to submit saga")
	require.NotEmpty(t, sagaID, "Saga ID should not be empty")

	return sagaID
}

// verifyAllStepsCompleted verifies that all 7 steps completed successfully
func verifyAllStepsCompleted(t *testing.T, sagaID string) {
	t.Helper()

	steps, err := framework.GetSagaStepStatuses(t, "traxctrl", sagaID, "e2e_test_cluster")
	require.NoError(t, err, "Failed to get saga step statuses")
	require.Len(t, steps, 7, "Should have exactly 7 steps")

	// Verify each step is committed
	for i, step := range steps {
		t.Logf("Step %d [%s]: [%s] %s", i+1, framework.ShortenID(step.StepInstanceID), framework.ShortenTemplateID(step.StepTemplateID), framework.ShortenStepState(step.Status))
		require.Equal(t, string(trax.SagaStepStateEnum_ExecutionDone), step.Status,
			"Step %d (%s) should be committed", i+1, step.StepTemplateID)
	}

	t.Log("✓ All 7 steps completed successfully")
}

// TestSevenStepSagaReliability tests reliability by running 20 sagas sequentially
// Each saga waits 2 seconds after completion before starting the next one
// This ensures the entire flow is stable and can be trusted
func TestSevenStepSagaReliability(t *testing.T) {
	t.Log("=== Seven Step Saga Reliability Test (20 iterations) ===")

	// Framework handles EVERYTHING automatically
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
		TestDBName:      "", // Generate random name
		AutoSwitchDB:    true,
		CaptureResults:  true,
		InitSchemas:     []string{"trax", "laser", "test_cluster"},
		ClusterID:       "e2e_test_cluster",
		AdditionalSetup: nil,
	})
	defer env.Cleanup()

	t.Log("Step 1: Verifying e2e_test_cluster exists...")
	verifyCusterExists(t)
	t.Log("✓ Cluster verified")

	t.Log("Step 2: Creating seven step saga template...")
	err := framework.CreateSevenStepTemplateViaTraxcli(t, env.GetTestDBName())
	require.NoError(t, err, "Failed to create saga template")
	t.Log("✓ Saga template created")

	t.Log("Step 3: Waiting for coordinators to be ready...")
	err = framework.WaitForCoordinatorReadiness(t, 3)
	require.NoError(t, err, "Coordinators should be ready")
	t.Log("✓ Coordinators ready")

	// Run 20 sagas sequentially
	const numIterations = 20
	t.Logf("Step 4: Running %d sagas sequentially...", numIterations)

	for i := 1; i <= numIterations; i++ {
		t.Logf("--- Iteration %d/%d ---", i, numIterations)

		// Submit saga
		sagaID := submitSevenStepSaga(t)
		t.Logf("  ✓ Saga %d submitted: %s", i, sagaID)

		// Poll for completion (180s timeout to accommodate potential step re-executions under load)
		err = framework.PollSagaStatus(t, "traxctrl", sagaID, "e2e_test_cluster", string(trax.SagaStateEnum_Committed), 180*time.Second)
		require.NoError(t, err, "Saga %d should complete successfully", i)
		t.Logf("  ✓ Saga %d completed", i)

		// Verify all steps completed
		verifyAllStepsCompleted(t, sagaID)
		t.Logf("  ✓ Saga %d: all 7 steps verified", i)

		// Wait 2 seconds before next iteration
		if i < numIterations {
			t.Logf("  Waiting 2 seconds before next saga...")
			time.Sleep(2 * time.Second)
		}
	}

	t.Logf("✓ All %d sagas completed successfully!", numIterations)
	t.Log("✓ Seven Step Saga Reliability Test PASSED!")
}

// TestTwoParallelSagasWithDelay tests that 2 sagas started a few seconds apart can run in parallel
// This verifies that the MVCC row-locking fix correctly handles concurrent saga execution
func TestTwoParallelSagasWithDelay(t *testing.T) {
	t.Log("=== Two Parallel Sagas with Delay Test ===")

	// Framework handles EVERYTHING automatically
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
		TestDBName:      "", // Generate random name
		AutoSwitchDB:    true,
		CaptureResults:  true,
		InitSchemas:     []string{"trax", "laser", "test_cluster"},
		ClusterID:       "e2e_test_cluster",
		AdditionalSetup: nil,
	})
	defer env.Cleanup()

	t.Log("Step 1: Verifying e2e_test_cluster exists...")
	verifyCusterExists(t)
	t.Log("✓ Cluster verified")

	t.Log("Step 2: Creating seven step saga template...")
	err := framework.CreateSevenStepTemplateViaTraxcli(t, env.GetTestDBName())
	require.NoError(t, err, "Failed to create saga template")
	t.Log("✓ Saga template created")

	t.Log("Step 3: Waiting for coordinators to be ready...")
	err = framework.WaitForCoordinatorReadiness(t, 3)
	require.NoError(t, err, "Coordinators should be ready")
	t.Log("✓ Coordinators ready")

	t.Log("Step 4: Submitting first saga...")
	saga1ID := submitSevenStepSaga(t)
	t.Logf("✓ First saga submitted: %s", saga1ID)

	t.Log("Step 5: Waiting 3 seconds before submitting second saga...")
	time.Sleep(3 * time.Second)

	t.Log("Step 6: Submitting second saga...")
	saga2ID := submitSevenStepSaga(t)
	t.Logf("✓ Second saga submitted: %s", saga2ID)

	t.Log("Step 7: Waiting for both sagas to complete in parallel...")

	// Use channels to wait for both sagas concurrently
	type sagaResult struct {
		id  string
		err error
	}
	resultsChan := make(chan sagaResult, 2)

	// Poll first saga (180s timeout - idempotency backend must be enabled to handle re-deliveries)
	go func() {
		err := framework.PollSagaStatus(t, "traxctrl", saga1ID, "e2e_test_cluster", string(trax.SagaStateEnum_Committed), 180*time.Second)
		resultsChan <- sagaResult{id: saga1ID, err: err}
	}()

	// Poll second saga (180s timeout - idempotency backend must be enabled to handle re-deliveries)
	go func() {
		err := framework.PollSagaStatus(t, "traxctrl", saga2ID, "e2e_test_cluster", string(trax.SagaStateEnum_Committed), 180*time.Second)
		resultsChan <- sagaResult{id: saga2ID, err: err}
	}()

	// Collect results
	for i := 0; i < 2; i++ {
		result := <-resultsChan
		require.NoError(t, result.err, "Saga %s should complete successfully", result.id)
		t.Logf("  ✓ Saga [%s] completed", framework.ShortenID(result.id))
	}

	t.Log("Step 8: Verifying all steps for both sagas...")
	verifyAllStepsCompleted(t, saga1ID)
	t.Logf("  ✓ First saga [%s]: all 7 steps verified", framework.ShortenID(saga1ID))
	verifyAllStepsCompleted(t, saga2ID)
	t.Logf("  ✓ Second saga [%s]: all 7 steps verified", framework.ShortenID(saga2ID))

	t.Log("✓ Two Parallel Sagas with Delay Test PASSED!")
}

// TestTenParallelSagasRandomized tests 10 parallel sagas with randomized submission intervals
// This is a stress test to verify MVCC row-locking handles high concurrency correctly
func TestTenParallelSagasRandomized(t *testing.T) {
	t.Log("=== Ten Parallel Sagas with Randomized Intervals Test ===")

	// Framework handles EVERYTHING automatically
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
		TestDBName:      "", // Generate random name
		AutoSwitchDB:    true,
		CaptureResults:  true,
		InitSchemas:     []string{"trax", "laser", "test_cluster"},
		ClusterID:       "e2e_test_cluster",
		AdditionalSetup: nil,
	})
	defer env.Cleanup()

	t.Log("Step 1: Verifying e2e_test_cluster exists...")
	verifyCusterExists(t)
	t.Log("✓ Cluster verified")

	t.Log("Step 2: Creating seven step saga template...")
	err := framework.CreateSevenStepTemplateViaTraxcli(t, env.GetTestDBName())
	require.NoError(t, err, "Failed to create saga template")
	t.Log("✓ Saga template created")

	t.Log("Step 3: Waiting for coordinators to be ready...")
	err = framework.WaitForCoordinatorReadiness(t, 3)
	require.NoError(t, err, "Coordinators should be ready")
	t.Log("✓ Coordinators ready")

	const numSagas = 10
	t.Logf("Step 4: Submitting %d sagas with randomized intervals (100-500ms)...", numSagas)

	// Channel to collect saga IDs
	sagaIDsChan := make(chan string, numSagas)

	// Submit all sagas in goroutines with randomized delays
	for i := 0; i < numSagas; i++ {
		sagaNum := i + 1
		go func(num int) {
			// Random delay between 100-500ms before submission
			randomDelay := time.Duration(100+num*40) * time.Millisecond
			time.Sleep(randomDelay)

			sagaID := submitSevenStepSaga(t)
			t.Logf("  ✓ Saga %d submitted: %s (after %v delay)", num, sagaID, randomDelay)
			sagaIDsChan <- sagaID
		}(sagaNum)
	}

	// Collect all saga IDs
	sagaIDs := make([]string, 0, numSagas)
	for i := 0; i < numSagas; i++ {
		sagaID := <-sagaIDsChan
		sagaIDs = append(sagaIDs, sagaID)
	}
	t.Logf("✓ All %d sagas submitted", numSagas)

	t.Log("Step 5: Waiting for all sagas to complete in parallel...")

	// Use channels to wait for all sagas concurrently
	type sagaResult struct {
		id  string
		err error
	}
	resultsChan := make(chan sagaResult, numSagas)

	// Poll each saga in parallel
	for _, sagaID := range sagaIDs {
		go func(id string) {
			err := framework.PollSagaStatus(t, "traxctrl", id, "e2e_test_cluster", string(trax.SagaStateEnum_Committed), 180*time.Second)
			resultsChan <- sagaResult{id: id, err: err}
		}(sagaID)
	}

	// Collect results
	completedCount := 0
	for i := 0; i < numSagas; i++ {
		result := <-resultsChan
		require.NoError(t, result.err, "Saga %s should complete successfully", result.id)
		completedCount++
		t.Logf("  ✓ Saga [%s] completed (%d/%d)", framework.ShortenID(result.id), completedCount, numSagas)
	}

	t.Logf("Step 6: Verifying all steps for %d sagas...", numSagas)
	for i, sagaID := range sagaIDs {
		verifyAllStepsCompleted(t, sagaID)
		t.Logf("  ✓ Saga %d [%s]: all 7 steps verified", i+1, framework.ShortenID(sagaID))
	}

	t.Logf("✓ All %d parallel sagas completed successfully!", numSagas)
	t.Log("✓ Ten Parallel Sagas with Randomized Intervals Test PASSED!")
}
