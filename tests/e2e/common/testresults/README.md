# E2E Test Results Capture Package

This package provides comprehensive test results capture for E2E tests, creating unique timestamped directories containing logs, database dumps, system info, configs, init scripts, and metadata from each test run.

## Features

- **Unique Test Run IDs**: Format `{testName}_{timestamp}` (test name first)
- **Complete Artifact Capture**: Logs, DB dumps, init scripts, configs
- **System & Docker Info**: OS, kernel, Docker version, runtime details
- **Database Dumps**: Full + schema-only PostgreSQL, Redis info
- **Init Scripts**: Auto-detection and copying
- **Service Configs**: Docker-compose config extraction
- **Git Metadata**: Branch, commit, diff, author
- **Capture Manifest**: JSON with file list, sizes, SHA256 checksums
- **Interactive HTML Viewer**: Self-contained viewer with syntax highlighting, file tree navigation, and search
- **No Auto-Cleanup**: Results accumulate indefinitely
- **Failure Resilient**: Uses `t.Cleanup()` to capture even on failure
- **Parallel Capture**: Optimized concurrent operations

## Directory Structure

### With Session Grouping (Recommended)

When `TEST_SESSION_ID` is set, all tests from a single test run are grouped together:

```
${HOST_PWD}/.test-results/e2e/
└── {session-id}/                       # e.g., "20250109_2025:01:09-15:04:23.456-CET_laser-smoke"
    ├── {timestamp}_{testName}/         # e.g., "20250109_2025:01:09-15:04:25.789-CET_TestEnvironmentHealthCheck"
            ├── index.html        # Interactive HTML viewer (double-click to open)
            ├── logs/             # All docker-compose service logs
            │   ├── postgres.log
            │   ├── redis.log
            │   ├── rabbitmq.log
            │   ├── lcmgr.log
            │   ├── lasersvc.log
            │   └── ...
            ├── data/
            │   ├── postgres_dump.sql        # Full database dump
            │   ├── postgres_schema.sql      # Schema-only dump
            │   ├── redis_dump.info
            │   └── scripts/init/            # All init SQL scripts
            │       ├── init_laser_pgsql.sql
            │       ├── init_trax_pgsql.sql
            │       └── ...
            ├── config/
            │   ├── docker-compose.yaml      # Copy of compose file
            │   ├── docker-version.json
            │   ├── docker-info.json
            │   ├── system-info.txt
            │   ├── network-info.txt
            │   └── service-configs/         # Per-service env vars
            │       ├── postgres.env
            │       ├── lasersvc.env
            │       └── ...
            ├── metadata/
            │   ├── git-info.txt             # Branch, commit, author
            │   ├── git-diff.patch           # Uncommitted changes
            │   ├── test-info.json           # Test metadata
            │   ├── environment.txt          # Env variables
            │   └── capture-manifest.json    # Complete file manifest
            └── test-output.log              # Test stdout/stderr
    ├── {timestamp2}_{testName2}/       # e.g., "20250109_2025:01:09-15:04:26.123-CET_TestDatabaseSchemaCreation"
    └── ...
```

### Without Session Grouping (Legacy)

When `TEST_SESSION_ID` is not set, tests are organized by suite name:

```
${HOST_PWD}/.test-results/e2e/
└── {testSuiteName}/                    # e.g., "laser"
    └── {testName}/                     # e.g., "TestEnvironmentHealthCheck"
        └── {timestamp}_{testName}/     # e.g., "20250109_2025:01:09-15:04:23.456-CET_TestEnvironmentHealthCheck"
            ├── index.html
            ├── logs/
            ├── data/
            ├── config/
            └── metadata/
```

## Usage

### In E2E Tests

Add the following to the beginning of your test function:

```go
func TestMyFeature(t *testing.T) {
    // Setup test results capture
    tracker := setupTestResultsCapture(t)

    // Your test code here...
}
```

The `setupTestResultsCapture()` function:
1. Creates a new `TestResultsTracker` with a unique run ID
2. Registers all docker-compose services for log capture
3. Sets database connection info for dumps
4. Auto-detects init scripts
5. Registers a `t.Cleanup()` handler that captures everything
6. Generates an interactive HTML viewer (`index.html`) automatically

### Viewing Test Results

After a test run completes, you can view the results by:

1. **Opening the HTML Viewer**: Navigate to the test results directory and double-click `index.html`
   - No web server required - it's a self-contained HTML file
   - Works in any modern browser (Chrome, Firefox, Safari, Edge)
   - Dark GitHub theme for comfortable viewing

2. **Features**:
   - **File Tree Navigation**: Browse logs, data, config, and metadata files
   - **Syntax Highlighting**: Automatic highlighting for JSON, SQL, YAML, bash, and logs
   - **Log Viewer**: Special error/warning highlighting for log files
   - **Manifest Overview**: Quick statistics and file checksums
   - **Search**: Filter files in the tree view
   - **Relative Paths**: Easy navigation between sections

Example locations:
```
# With session grouping (recommended):
.test-results/e2e/20250109_2025:01:09-15:04:23.456-CET_laser-smoke/20250109_2025:01:09-15:04:25.789-CET_TestEnvironmentHealthCheck/index.html

# Without session grouping (legacy):
.test-results/e2e/laser/TestEnvironmentHealthCheck/20250109_2025:01:09-15:04:25.789-CET_TestEnvironmentHealthCheck/index.html
```

### Environment Variables

Required:
- `TEST_RESULTS_BASE_DIR` - Base directory for test results (e.g., `/test-results/e2e`)

Optional:
- `TEST_SESSION_ID` - Session ID for grouping tests from same run (e.g., `20250109_2025:01:09-15:04:23.456-CET_laser-smoke`)
  - When set: All tests go into `${BASE_DIR}/${SESSION_ID}/{YYYYMMDD}_{datetime}-{TZ}_{testName}/`
  - When not set: Tests go into `${BASE_DIR}/${SUITE_NAME}/{testName}/{YYYYMMDD}_{datetime}-{TZ}_{testName}/` (legacy)
- `TEST_SUITE_NAME` - Suite name (defaults to directory name, e.g., "laser")

### Manual Capture

You can also use the capture functions directly:

```go
// Create tracker
tracker, err := testresults.NewTestResultsTracker("my-suite", "TestName")
if err != nil {
    log.Fatal(err)
}

// Configure tracker
tracker.SetComposeInfo("./docker-compose.yaml", "./")
tracker.TrackService("postgres")
tracker.SetDatabaseInfo(&testresults.DBConnectionInfo{
    PostgresHost: "localhost",
    PostgresPort: "5432",
    // ...
})

// Capture everything
if err := testresults.CaptureAll(tracker); err != nil {
    log.Printf("Capture failed: %v", err)
}
```

## API Reference

### TestResultsTracker

The main state management object that tracks what needs to be captured.

**Methods:**
- `TrackService(serviceName string)` - Register a docker-compose service for log capture
- `TrackInitScript(scriptPath string)` - Register an init script for copying
- `TrackConfigFile(service, path string)` - Register a service config file
- `SetDatabaseInfo(dbInfo *DBConnectionInfo)` - Set database connection details
- `SetComposeInfo(composeFile, composeDir string)` - Set docker-compose file location
- `RecordError(err error)` - Record a capture error
- `Complete()` - Mark test as completed

### Core Functions

- `GenerateTestRunID(testName string) string` - Generate unique run ID
- `CreateTestResultsDir(tracker *TestResultsTracker) error` - Create directory structure
- `CaptureAll(tracker *TestResultsTracker) error` - Orchestrate all captures
- `AutoDetectInitScripts(tracker *TestResultsTracker) error` - Find init scripts

### Capture Functions

- `CaptureLogs(tracker *TestResultsTracker) error` - Extract service logs
- `CaptureSystemInfo(tracker *TestResultsTracker) error` - Capture OS/system info
- `CaptureDockerInfo(tracker *TestResultsTracker) error` - Capture Docker info
- `CaptureNetworkInfo(tracker *TestResultsTracker) error` - Capture network info
- `CaptureDatabaseDumps(tracker *TestResultsTracker) error` - Dump databases
- `CaptureInitScripts(tracker *TestResultsTracker) error` - Copy init scripts
- `CaptureServiceConfigs(tracker *TestResultsTracker) error` - Extract configs
- `CaptureGitMetadata(tracker *TestResultsTracker) error` - Capture git info
- `CaptureEnvironment(tracker *TestResultsTracker) error` - Capture env vars
- `GenerateCaptureManifest(tracker *TestResultsTracker) error` - Generate manifest
- `SaveTestInfo(tracker *TestResultsTracker, result string, testError error) error` - Save test metadata

## Helper Scripts

Standalone scripts for manual use:

### extract-logs.sh
```bash
./tests/e2e/common/scripts/extract-logs.sh <compose-file> <output-dir>
```

Extracts logs from all services in a docker-compose file.

### dump-databases.sh
```bash
./tests/e2e/common/scripts/dump-databases.sh <output-dir> <host> <port> <db> <user> <password>
```

Creates PostgreSQL dumps (full + schema-only) and triggers Redis save.

### capture-docker-info.sh
```bash
./tests/e2e/common/scripts/capture-docker-info.sh <output-dir>
```

Captures Docker version, info, and compose version.

## Implementation Details

### Parallel Capture

The `CaptureAll()` function runs independent capture operations in parallel:
- System info
- Docker info
- Git metadata
- Logs extraction

Sequential operations (database dumps, init scripts, configs) run after parallel operations complete.

### Error Handling

Errors during capture are recorded but don't fail the test. All errors are:
1. Recorded in `tracker.CaptureErrors`
2. Included in the capture manifest
3. Logged for debugging

### Database Dumps

PostgreSQL dumps use `pg_dump` with:
- Full dump: Plain text format (`-F p`)
- Schema dump: `--schema-only` flag
- No password prompts: `--no-password` with `PGPASSWORD` env var

Redis dumps trigger `SAVE` command and record info about the dump location.

### Init Scripts Auto-Detection

Searches common locations for standard init scripts:
- `../../../deploy/k8s/init/` (relative to compose file)
- `./init/` (relative to compose file)
- Compose file directory

Looks for patterns like:
- `init_shared_pgsql.sql`
- `init_laser_pgsql.sql`
- `init_trax_pgsql.sql`
- etc.

## Makefile Targets

```bash
# View test results information
make laser-e2e-results-info

# Run tests (capture happens automatically)
make laser-e2e-full
make laser-e2e-smoke
```

## Troubleshooting

### No Results Captured

Check:
1. `TEST_RESULTS_BASE_DIR` environment variable is set
2. Directory has write permissions
3. Check test logs for capture errors

### Missing Logs

Verify:
1. Docker-compose services are tracked
2. Services have actually run and produced logs
3. Docker-compose file path is correct

### Database Dumps Failed

Ensure:
1. `pg_dump` is available in test container
2. Database connection info is correct
3. Database is accessible from test runner

### Large Result Directories

Results are never auto-cleaned. To manage disk space:
1. Manually delete old test runs
2. Archive results to long-term storage
3. Implement custom retention policy

## Related Documentation

- [E2E_TEST_RESULTS_CAPTURE_TODO.md](../../../../docs/E2E_TEST_RESULTS_CAPTURE_TODO.md) - Complete implementation plan
- [LASER_E2E_TESTS_TODO.md](../../../../docs/LASER_E2E_TESTS_TODO.md) - LASER E2E test plan
