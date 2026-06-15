package framework

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/kamcpp/trax/tests/e2e/common/testresults"
)

// setupTestResultsCapture initializes test results tracking for a test
// This is called automatically by NewE2EEnvironment if CaptureResults is true
// Returns nil if results capture is disabled or fails to initialize
func setupTestResultsCapture(t *testing.T, services []string) *testresults.TestResultsTracker {
	t.Helper()

	// Check if results capture is enabled
	baseDir := os.Getenv("TEST_RESULTS_BASE_DIR")
	if baseDir == "" {
		t.Log("TEST_RESULTS_BASE_DIR not set, skipping results capture")
		return nil
	}

	// Get suite name from environment or extract from test path
	suiteName := os.Getenv("TEST_SUITE_NAME")
	if suiteName == "" {
		// Try to extract from working directory
		// e.g., /path/to/tests/e2e/laser -> "laser"
		cwd, _ := os.Getwd()
		suiteName = filepath.Base(cwd)
	}

	// Create tracker
	tracker, err := testresults.NewTestResultsTracker(suiteName, t.Name())
	if err != nil {
		t.Logf("Warning: failed to create test results tracker: %v", err)
		return nil
	}

	// Set compose file info
	composeFile := filepath.Join(".", "docker-compose.yaml")
	composeDir, _ := os.Getwd()
	tracker.SetComposeInfo(composeFile, composeDir)

	// Track all services
	// Include common infrastructure services
	commonServices := []string{"postgres", "redis", "rabbitmq", "init-db", "test-runner"}
	allServices := append(commonServices, services...)
	for _, svc := range allServices {
		tracker.TrackService(svc)
	}

	// Set database connection info
	dbInfo := &testresults.DBConnectionInfo{
		PostgresHost:     os.Getenv("PGSQL_HOST"),
		PostgresPort:     os.Getenv("PGSQL_PORT"),
		PostgresUser:     os.Getenv("PGSQL_USER"),
		PostgresPassword: os.Getenv("PGSQL_PASSWORD"),
		PostgresDB:       os.Getenv("PGSQL_DATABASE"),
		RedisHost:        "redis",
		RedisPort:        "6379",
	}
	tracker.SetDatabaseInfo(dbInfo)

	// Auto-detect and track init scripts
	if err := testresults.AutoDetectInitScripts(tracker); err != nil {
		t.Logf("Warning: failed to auto-detect init scripts: %v", err)
	}

	// Register cleanup to capture results
	t.Cleanup(func() {
		t.Logf("Capturing test results to: %s", tracker.ResultsDir)

		// Determine test result
		result := "passed"
		var testErr error
		if t.Failed() {
			result = "failed"
			testErr = fmt.Errorf("test failed")
		} else if t.Skipped() {
			result = "skipped"
		}

		// Capture all results
		if err := testresults.CaptureAll(tracker); err != nil {
			t.Logf("Warning: test results capture failed: %v", err)
		}

		// Save test info
		if err := testresults.SaveTestInfo(tracker, result, testErr); err != nil {
			t.Logf("Warning: failed to save test info: %v", err)
		}

		// Generate HTML viewer (must be after SaveTestInfo to read test-info.json)
		if err := testresults.GenerateHTMLViewer(tracker); err != nil {
			t.Logf("Warning: HTML viewer generation failed: %v", err)
		}

		// Capture environment
		if err := testresults.CaptureEnvironment(tracker); err != nil {
			t.Logf("Warning: failed to capture environment: %v", err)
		}

		// Capture network info
		if err := testresults.CaptureNetworkInfo(tracker); err != nil {
			t.Logf("Warning: failed to capture network info: %v", err)
		}

		t.Logf("Test results captured successfully")
	})

	return tracker
}

// captureFinalTestState captures final test state and generates reports
// This is called automatically by E2EEnvironment.Cleanup()
func captureFinalTestState(t *testing.T, tracker *testresults.TestResultsTracker) {
	t.Helper()

	if tracker == nil {
		return
	}

	// Note: All capture work is already registered in t.Cleanup() by setupTestResultsCapture
	// This function is a no-op but kept for consistency with the API
	t.Log("Test results capture registered in cleanup hooks")
}
