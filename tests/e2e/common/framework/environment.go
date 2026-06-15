package framework

import (
	"testing"
	"time"

	"github.com/kamcpp/trax/tests/e2e/common/testresults"
)

// E2EEnvironment manages test lifecycle automatically
// Handles: test results capture, DB setup, service switching, cleanup
type E2EEnvironment struct {
	t            *testing.T
	config       Config
	testDBName   string
	tracker      *testresults.TestResultsTracker
	dbConnection interface{} // Stores DB connection if needed
}

// Config defines the configuration for an E2E test environment
type Config struct {
	// Services to manage (e.g., "traxctrl", "traxcoord1", "lasersvc")
	// These services will be health-checked and switched to the test database
	Services []string

	// LogOnlyServices are services that only need log capture
	// (e.g., "executor-step1", "traxcli-submitter")
	// These services will NOT be health-checked or switched to the test database
	LogOnlyServices []string

	// Test database name (will be created automatically)
	// If empty, a random name will be generated
	TestDBName string

	// AutoSwitchDB automatically switches all services to the test database
	// Default: true
	AutoSwitchDB bool

	// CaptureResults automatically captures test results (logs, DB dumps, etc.)
	// Default: true
	CaptureResults bool

	// InitSchemas is a list of schema initialization functions to run
	// Examples: "laser", "trax", "accmgr", "instrmgr", "lcmgr"
	InitSchemas []string

	// AdditionalSetup is an optional function to run additional setup
	// Called after DB is created and schemas are initialized, but before service switching
	AdditionalSetup func(*testing.T, interface{}) error

	// SkipServiceHealthCheck skips waiting for services to be healthy
	// Default: false (health checks are performed)
	SkipServiceHealthCheck bool

	// ClusterID is the TRAX cluster ID used for saga metrics capture
	// Must be set when CaptureResults is true
	ClusterID string
}

// NewE2EEnvironment creates a new E2E test environment with automatic setup
// This function:
// 1. Sets up test results capture (if enabled)
// 2. Creates and initializes test database
// 3. Initializes requested schemas
// 4. Waits for services to be healthy
// 5. Switches all services to test database (if enabled)
func NewE2EEnvironment(t *testing.T, cfg Config) *E2EEnvironment {
	t.Helper()

	// Apply defaults
	if cfg.AutoSwitchDB && len(cfg.Services) == 0 {
		t.Fatal("AutoSwitchDB is true but no services specified in config")
	}

	env := &E2EEnvironment{
		t:      t,
		config: cfg,
	}

	// Step 1: Setup test results capture (AUTOMATIC)
	if cfg.CaptureResults {
		t.Log("Framework: Setting up test results capture...")
		env.setupTestResultsCapture()
	}

	// Step 2: Create and initialize test database (AUTOMATIC)
	t.Log("Framework: Setting up test database...")
	env.setupTestDatabase()
	t.Logf("Framework: ✓ Test database ready: %s", env.testDBName)

	// Step 3: Wait for services to be healthy (AUTOMATIC)
	if !cfg.SkipServiceHealthCheck {
		t.Log("Framework: Waiting for services to be healthy...")
		env.waitForServices()
		t.Log("Framework: ✓ All services healthy")
	}

	// Step 4: Switch all services to test database (AUTOMATIC)
	if cfg.AutoSwitchDB {
		t.Log("Framework: Switching services to test database...")
		env.switchServicesToTestDB()
		t.Logf("Framework: ✓ All services switched to database: %s", env.testDBName)
	}

	t.Log("Framework: ✓ Environment setup complete")

	return env
}

// setupTestResultsCapture initializes test results tracking
func (e *E2EEnvironment) setupTestResultsCapture() {
	// Combine Services and LogOnlyServices for log capture
	allServices := append([]string{}, e.config.Services...)
	allServices = append(allServices, e.config.LogOnlyServices...)

	tracker := setupTestResultsCapture(e.t, allServices)
	if tracker != nil {
		if e.config.ClusterID != "" {
			tracker.SetTraxInfo("traxctrl", e.config.ClusterID)
		}
		e.tracker = tracker
	}
}

// setupTestDatabase creates and initializes the test database
func (e *E2EEnvironment) setupTestDatabase() {
	db, dbName := SetupTestDatabase(e.t, e.config.TestDBName)
	e.testDBName = dbName
	e.dbConnection = db

	// Initialize requested schemas
	for _, schema := range e.config.InitSchemas {
		e.t.Logf("Framework: Initializing %s schema...", schema)
		if err := InitializeSchema(e.t, db, schema); err != nil {
			e.t.Fatalf("Framework: Failed to initialize %s schema: %v", schema, err)
		}
	}

	// Run additional setup if provided
	if e.config.AdditionalSetup != nil {
		e.t.Log("Framework: Running additional setup...")
		if err := e.config.AdditionalSetup(e.t, db); err != nil {
			e.t.Fatalf("Framework: Additional setup failed: %v", err)
		}
	}

	// Close DB connection (services will reconnect)
	db.Close()
}

// waitForServices waits for all configured services to be healthy
func (e *E2EEnvironment) waitForServices() {
	for _, service := range e.config.Services {
		e.t.Logf("Framework: Waiting for service: %s", service)
		if err := WaitForServiceHealth(service, 30*time.Second); err != nil {
			e.t.Fatalf("Framework: Service %s not healthy: %v", service, err)
		}
	}
}

// switchServicesToTestDB switches all configured services to the test database
func (e *E2EEnvironment) switchServicesToTestDB() {
	for _, service := range e.config.Services {
		e.t.Logf("Framework: Switching %s to test database...", service)
		if err := SetServiceDatabase(e.t, service, e.testDBName); err != nil {
			e.t.Fatalf("Framework: Failed to switch %s to test database: %v", service, err)
		}
	}

	// Wait a moment for all services to stabilize after DB switch
	time.Sleep(500 * time.Millisecond)
}

// Cleanup performs automatic cleanup and test results capture
// This should be called in a defer statement: defer env.Cleanup()
func (e *E2EEnvironment) Cleanup() {
	e.t.Helper()
	e.t.Log("Framework: Performing cleanup and capturing test results...")

	if e.tracker != nil {
		captureFinalTestState(e.t, e.tracker)
	}

	e.t.Log("Framework: ✓ Cleanup complete")
}

// GetTestDBName returns the test database name
func (e *E2EEnvironment) GetTestDBName() string {
	return e.testDBName
}

// GetTracker returns the test results tracker (may be nil)
func (e *E2EEnvironment) GetTracker() *testresults.TestResultsTracker {
	return e.tracker
}
