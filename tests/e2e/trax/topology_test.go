package trax_e2e_test

import (
	"regexp"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/xshyft/trax/pkg/trax"
	"github.com/xshyft/trax/tests/e2e/common/framework"
)

// TestTopicExchangeTopology verifies that the TRAX topic exchange is correctly
// configured after coordinator and executor startup.
// It checks:
// - The per-cluster topic exchange exists with type "topic"
// - Executor inbox queues exist with correct bindings
// - Coordinator results queues exist with correct bindings
// - Old per-step fanout exchanges do NOT exist
func TestTopicExchangeTopology(t *testing.T) {
	t.Log("=== Topic Exchange Topology Verification Test ===")

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
		InitSchemas:    []string{"trax", "test_cluster"},
		ClusterID:      "e2e_test_cluster",
	})
	defer env.Cleanup()

	t.Log("Step 1: Verifying cluster exists...")
	verifyCusterExists(t)

	t.Log("Step 2: Creating seven step saga template...")
	err := framework.CreateSevenStepTemplateViaTraxcli(t, env.GetTestDBName())
	require.NoError(t, err, "Failed to create saga template")

	t.Log("Step 3: Waiting for coordinators to be ready...")
	err = framework.WaitForCoordinatorReadiness(t, 3)
	require.NoError(t, err, "Coordinators should be ready")

	// Give coordinators time to complete template reload and queue initialization
	t.Log("Step 4: Waiting for template reload to complete...")
	time.Sleep(15 * time.Second)

	rmq := framework.NewRabbitMQManagementClient(t)

	// Verify topic exchange exists
	t.Log("Step 5: Verifying topic exchange exists...")
	exchangeName := "x_e2e_test_cluster_trax_saga_steps"
	exchange := rmq.GetExchangeByName(t, exchangeName)
	require.NotNil(t, exchange, "Topic exchange '%s' should exist", exchangeName)
	assert.Equal(t, "topic", exchange.Type, "Exchange should be of type 'topic'")
	assert.True(t, exchange.Durable, "Exchange should be durable")
	t.Logf("  ✓ Topic exchange '%s' exists (type=%s, durable=%v)", exchange.Name, exchange.Type, exchange.Durable)

	// Verify executor inbox queues exist (7 steps = 7 queues)
	t.Log("Step 6: Verifying executor inbox queues...")
	executorQueues := rmq.GetQueuesMatching(t, `^q_e2e_test_cluster_trax_executor_.*_inbox$`)
	assert.GreaterOrEqual(t, len(executorQueues), 7, "Should have at least 7 executor inbox queues (one per step)")
	for _, q := range executorQueues {
		t.Logf("  ✓ Executor inbox queue: %s (consumers=%d)", q.Name, q.Consumers)
	}

	// Verify coordinator results queues exist (3 affinities = 3 queues)
	t.Log("Step 7: Verifying coordinator results queues...")
	resultsQueues := rmq.GetQueuesMatching(t, `^q_e2e_test_cluster_trax_coordinator_\d+_results$`)
	assert.Equal(t, 3, len(resultsQueues), "Should have exactly 3 coordinator results queues (one per affinity)")
	for _, q := range resultsQueues {
		t.Logf("  ✓ Coordinator results queue: %s (consumers=%d)", q.Name, q.Consumers)
		assert.GreaterOrEqual(t, q.Consumers, 1, "Results queue '%s' should have at least 1 consumer", q.Name)
	}

	// Verify bindings on the topic exchange
	t.Log("Step 8: Verifying topic exchange bindings...")
	bindings := rmq.ListBindingsForExchange(t, exchangeName)
	t.Logf("  Found %d bindings on exchange '%s'", len(bindings), exchangeName)

	// Count request bindings (executor inbox) and response bindings (coordinator results)
	requestBindings := 0
	responseBindings := 0
	for _, b := range bindings {
		if len(b.RoutingKey) > 8 && b.RoutingKey[len(b.RoutingKey)-8:] == ".request" {
			requestBindings++
			t.Logf("  ✓ Request binding: %s -> %s (key=%s)", b.Source, b.Destination, b.RoutingKey)
		} else if len(b.RoutingKey) > 9 && b.RoutingKey[len(b.RoutingKey)-9:] == ".response" {
			responseBindings++
			t.Logf("  ✓ Response binding: %s -> %s (key=%s)", b.Source, b.Destination, b.RoutingKey)
		}
	}
	assert.GreaterOrEqual(t, requestBindings, 7, "Should have at least 7 request bindings (one per step)")
	assert.Equal(t, 3, responseBindings, "Should have exactly 3 response bindings (one per coordinator affinity)")

	// Verify old-style per-step fanout exchanges do NOT exist
	t.Log("Step 9: Verifying no old-style per-step fanout exchanges...")
	oldExchangeCount := 0
	oldPattern := regexp.MustCompile(`trax_coordinator_\d+_saga_.*_step_.*_(inbox|outbox)`)
	exchanges := rmq.ListExchanges(t)
	for _, ex := range exchanges {
		// Old naming pattern: e2e_test_cluster_trax_coordinator_{affinity}_saga_{sagaTemplate}_step_{stepTemplate}_{inbox|outbox}
		if oldPattern.MatchString(ex.Name) {
			oldExchangeCount++
			t.Logf("  WARNING: Old-style exchange still exists: %s", ex.Name)
		}
	}
	assert.Equal(t, 0, oldExchangeCount, "No old-style per-step fanout exchanges should exist")
	t.Log("  ✓ No old-style per-step fanout exchanges found")

	t.Log("✓ Topic Exchange Topology Verification Test PASSED!")
}

// TestQueueCountReduction verifies that the total number of TRAX-related queues
// is dramatically reduced compared to the old architecture.
// Old: ~42+ queues (7 steps × 3 affinities × 2 directions)
// New: ~10 queues (7 executor inbox + 3 coordinator results)
func TestQueueCountReduction(t *testing.T) {
	t.Log("=== Queue Count Reduction Verification Test ===")

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
		InitSchemas:    []string{"trax", "test_cluster"},
		ClusterID:      "e2e_test_cluster",
	})
	defer env.Cleanup()

	t.Log("Step 1: Verifying cluster exists...")
	verifyCusterExists(t)

	t.Log("Step 2: Creating seven step saga template...")
	err := framework.CreateSevenStepTemplateViaTraxcli(t, env.GetTestDBName())
	require.NoError(t, err, "Failed to create saga template")

	t.Log("Step 3: Waiting for coordinators to be ready...")
	err = framework.WaitForCoordinatorReadiness(t, 3)
	require.NoError(t, err, "Coordinators should be ready")

	// Wait for template reload
	time.Sleep(15 * time.Second)

	rmq := framework.NewRabbitMQManagementClient(t)

	t.Log("Step 4: Counting TRAX-related queues for seven_step_sleep_saga...")

	// Count executor inbox queues specifically for the seven_step_sleep_saga template
	// Other saga templates (compensation, deep sub-saga) also create executor queues
	// so we must filter to only count queues for our template under test
	executorCount := rmq.CountQueuesMatching(t, `^q_e2e_test_cluster_trax_executor_seven_step_sleep_saga_`)
	t.Logf("  Executor inbox queues (seven_step_sleep_saga): %d", executorCount)

	// Count coordinator results queues (shared across all saga templates per affinity)
	coordinatorResultsCount := rmq.CountQueuesMatching(t, `^q_e2e_test_cluster_trax_coordinator_\d+_results$`)
	t.Logf("  Coordinator results queues: %d", coordinatorResultsCount)

	// Total step-related queues for our template (executor + coordinator results)
	totalStepQueues := executorCount + coordinatorResultsCount
	t.Logf("  Total step-related queues: %d", totalStepQueues)

	// With 7 steps and 3 affinities, old architecture would create:
	// 7 steps × 3 affinities × 2 (inbox+outbox) = 42 queues for this template alone
	// New architecture: 7 executor inbox + 3 results = 10 queues
	assert.LessOrEqual(t, totalStepQueues, 15,
		"Total step-related queues should be ≤15 (expected ~10: 7 executor + 3 results), not 42+ as in old architecture")
	assert.Equal(t, 7, executorCount, "Should have exactly 7 executor inbox queues for seven_step_sleep_saga")
	assert.Equal(t, 3, coordinatorResultsCount, "Should have exactly 3 coordinator results queues")

	t.Logf("✓ Queue count verified: %d total (was ~42+ with old architecture)", totalStepQueues)
	t.Log("✓ Queue Count Reduction Verification Test PASSED!")
}

// TestMessageDeliveryWithTopicExchange runs a full saga to verify that the
// topic exchange correctly routes messages between coordinators and executors.
// After the saga completes, it verifies zero queue depth (no stuck messages).
func TestMessageDeliveryWithTopicExchange(t *testing.T) {
	t.Log("=== Message Delivery with Topic Exchange Test ===")

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
		InitSchemas:    []string{"trax", "test_cluster"},
		ClusterID:      "e2e_test_cluster",
	})
	defer env.Cleanup()

	t.Log("Step 1: Verifying cluster exists...")
	verifyCusterExists(t)

	t.Log("Step 2: Creating seven step saga template...")
	err := framework.CreateSevenStepTemplateViaTraxcli(t, env.GetTestDBName())
	require.NoError(t, err, "Failed to create saga template")

	t.Log("Step 3: Waiting for coordinators to be ready...")
	err = framework.WaitForCoordinatorReadiness(t, 3)
	require.NoError(t, err, "Coordinators should be ready")

	rmq := framework.NewRabbitMQManagementClient(t)

	// Run 5 sagas sequentially to exercise the topic exchange
	const numSagas = 5
	t.Logf("Step 4: Running %d sagas to exercise topic exchange routing...", numSagas)

	for i := 1; i <= numSagas; i++ {
		sagaID := submitSevenStepSaga(t)
		t.Logf("  Saga %d submitted: %s", i, framework.ShortenID(sagaID))

		err = framework.PollSagaStatus(t, "traxctrl", sagaID, "e2e_test_cluster", string(trax.SagaStateEnum_Committed), 180*time.Second)
		require.NoError(t, err, "Saga %d should complete successfully", i)

		verifyAllStepsCompleted(t, sagaID)
		t.Logf("  ✓ Saga %d completed and verified", i)

		if i < numSagas {
			time.Sleep(1 * time.Second)
		}
	}

	// Verify zero queue depth after all sagas complete
	// Use polling with timeout since residual messages from the coordinator's
	// processSagaSteps polling loop may take a moment to be consumed by executors
	t.Log("Step 5: Verifying zero queue depth (no stuck messages)...")
	var executorDepth, resultsDepth int
	deadline := time.Now().Add(30 * time.Second)
	for time.Now().Before(deadline) {
		time.Sleep(3 * time.Second)
		executorDepth = rmq.GetTotalQueueDepth(t, `^q_e2e_test_cluster_trax_executor_`)
		resultsDepth = rmq.GetTotalQueueDepth(t, `^q_e2e_test_cluster_trax_coordinator_\d+_results$`)
		if executorDepth == 0 && resultsDepth == 0 {
			break
		}
		t.Logf("  Queue depth not yet zero (executor=%d, results=%d), waiting...", executorDepth, resultsDepth)
	}

	t.Logf("  Executor inbox queue depth: %d", executorDepth)
	t.Logf("  Coordinator results queue depth: %d", resultsDepth)

	assert.Equal(t, 0, executorDepth, "Executor inbox queues should be empty after all sagas complete")
	assert.Equal(t, 0, resultsDepth, "Coordinator results queues should be empty after all sagas complete")

	t.Logf("✓ All %d sagas completed with zero residual messages", numSagas)
	t.Log("✓ Message Delivery with Topic Exchange Test PASSED!")
}
