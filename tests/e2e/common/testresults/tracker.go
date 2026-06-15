package testresults

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// TestResultsTracker maintains state of what needs to be captured during test execution
type TestResultsTracker struct {
	mu         sync.Mutex
	TestName   string
	SuiteName  string
	RunID      string
	ResultsDir string
	StartTime  time.Time
	EndTime    time.Time

	// Tracking information
	ComposeFile  string
	ComposeDir   string
	Services     []string
	InitScripts  []string
	ConfigFiles  map[string]string // service name -> config file path
	DatabaseInfo *DBConnectionInfo

	// Saga metrics tracking
	SagaInstanceIDs []string // Saga instance IDs to collect metrics for
	SagaMetricsJSON []byte   // Cached saga metrics JSON for HTML viewer
	TraxctrlService string   // TRAX controller service name for metrics collection
	ClusterID       string   // TRAX cluster ID

	// Capture status
	CaptureErrors []error
}

// DBConnectionInfo holds database connection details for dumps
type DBConnectionInfo struct {
	PostgresHost     string
	PostgresPort     string
	PostgresUser     string
	PostgresPassword string
	PostgresDB       string
	RedisHost        string
	RedisPort        string
}

// NewTestResultsTracker creates a new tracker for the given test
func NewTestResultsTracker(suiteName, testName string) (*TestResultsTracker, error) {
	runID := GenerateTestRunID(testName)

	baseDir := os.Getenv("TEST_RESULTS_BASE_DIR")
	if baseDir == "" {
		return nil, fmt.Errorf("TEST_RESULTS_BASE_DIR environment variable not set")
	}

	// Get or create session ID for grouping tests from same test run
	sessionID := os.Getenv("TEST_SESSION_ID")
	if sessionID == "" {
		// If no session ID, use the old structure (backwards compatible)
		sessionID = suiteName
	}

	resultsDir := filepath.Join(
		baseDir,
		sessionID,
		runID,
	)

	tracker := &TestResultsTracker{
		TestName:    testName,
		SuiteName:   suiteName,
		RunID:       runID,
		ResultsDir:  resultsDir,
		StartTime:   time.Now(),
		Services:    []string{},
		InitScripts: []string{},
		ConfigFiles: make(map[string]string),
	}

	return tracker, nil
}

// TrackInitScript registers an initialization script for capture
func (t *TestResultsTracker) TrackInitScript(scriptPath string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.InitScripts = append(t.InitScripts, scriptPath)
}

// TrackService registers a docker-compose service for log capture
func (t *TestResultsTracker) TrackService(serviceName string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.Services = append(t.Services, serviceName)
}

// TrackConfigFile registers a service config file for capture
func (t *TestResultsTracker) TrackConfigFile(service, path string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.ConfigFiles[service] = path
}

// SetDatabaseInfo sets the database connection information
func (t *TestResultsTracker) SetDatabaseInfo(dbInfo *DBConnectionInfo) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.DatabaseInfo = dbInfo
}

// SetComposeInfo sets the docker-compose file location
func (t *TestResultsTracker) SetComposeInfo(composeFile, composeDir string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.ComposeFile = composeFile
	t.ComposeDir = composeDir
}

// RecordError records an error that occurred during capture
func (t *TestResultsTracker) RecordError(err error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.CaptureErrors = append(t.CaptureErrors, err)
}

// Complete marks the test as completed
func (t *TestResultsTracker) Complete() {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.EndTime = time.Now()
}

// TrackSagaInstance registers a saga instance ID for metrics collection
func (t *TestResultsTracker) TrackSagaInstance(sagaInstanceID string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.SagaInstanceIDs = append(t.SagaInstanceIDs, sagaInstanceID)
}

// SetTraxInfo sets TRAX controller and cluster information for metrics collection
func (t *TestResultsTracker) SetTraxInfo(traxctrlService, clusterID string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.TraxctrlService = traxctrlService
	t.ClusterID = clusterID
}

// SetSagaMetricsJSON sets the collected saga metrics JSON
func (t *TestResultsTracker) SetSagaMetricsJSON(metricsJSON []byte) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.SagaMetricsJSON = metricsJSON
}

// GetSagaInstanceIDs returns the tracked saga instance IDs
func (t *TestResultsTracker) GetSagaInstanceIDs() []string {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.SagaInstanceIDs
}

// HasSagaMetrics returns true if saga metrics have been collected
func (t *TestResultsTracker) HasSagaMetrics() bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	return len(t.SagaMetricsJSON) > 0
}
