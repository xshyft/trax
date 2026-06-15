# E2E Test Results Capture System - Implementation Checklist

This document provides a step-by-step implementation guide for creating a comprehensive test results capture system for E2E tests. The system captures logs, database dumps, system information, configurations, initialization scripts, and metadata from each test run.

**Test Results Approach:**
- Each test run gets unique directory: `{testName}_{timestamp}` format
- Test runner tracks what needs to be captured during test execution
- Full capture happens at test completion (even on failure) via `t.Cleanup()`
- Results are NEVER automatically cleaned - they accumulate for debugging
- All docker-compose services logged in raw format
- Complete database dumps (PostgreSQL full + schema, Redis if applicable)
- System and Docker information captured
- All initialization scripts and configs preserved
- Git metadata and capture manifest included

**Directory Structure:**
```
${HOST_PWD}/.test-results/e2e/
└── {testSuiteName}/              # e.g., "laser"
    └── {testName}/               # e.g., "TestTRAXInstrumentIssuance"
        └── {testName}_{timestamp}/   # e.g., "TestTRAXInstrumentIssuance_20250109_150423"
            ├── logs/             # All docker-compose service logs
            ├── data/             # Database dumps and init scripts
            ├── config/           # Docker, system info, service configs
            ├── metadata/         # Git info, test results, manifest
            └── test-output.log   # Test stdout/stderr
```

**Important Notes:**
- Test name comes FIRST in run ID format (not timestamp first)
- Database dumps include both full data and schema-only exports
- Init scripts are copied to `data/scripts/init/`
- System info includes Docker version, runtime, OS details
- Tracker maintains state of what to capture during execution
- All capture operations are failure-resilient

---

## Phase 1: Core Test Results Infrastructure

### 1.1 Create Test Results Tracker

Create file `tests/e2e/common/testresults/tracker.go`:

- [ ] 1.1.1 Define `TestResultsTracker` struct:
  ```go
  package testresults

  import (
      "sync"
      "time"
  )

  // TestResultsTracker maintains state of what needs to be captured during test execution
  type TestResultsTracker struct {
      mu                 sync.Mutex
      TestName           string
      SuiteName          string
      RunID              string
      ResultsDir         string
      StartTime          time.Time
      EndTime            time.Time

      // Tracking information
      ComposeFile        string
      ComposeDir         string
      Services           []string
      InitScripts        []string
      ConfigFiles        map[string]string // service name -> config file path
      DatabaseInfo       *DBConnectionInfo

      // Capture status
      CaptureErrors      []error
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
  ```

- [ ] 1.1.2 Implement `NewTestResultsTracker()` function:
  ```go
  // NewTestResultsTracker creates a new tracker for the given test
  func NewTestResultsTracker(suiteName, testName string) (*TestResultsTracker, error) {
      runID := GenerateTestRunID(testName)
      resultsDir := filepath.Join(
          os.Getenv("TEST_RESULTS_BASE_DIR"),
          suiteName,
          testName,
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
  ```

- [ ] 1.1.3 Implement tracking methods:
  ```go
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
  ```

- [ ] 1.1.4 Verify tracker compiles: `go build ./tests/e2e/common/testresults/`

### 1.2 Create Core Capture Orchestration

Create file `tests/e2e/common/testresults/capture.go`:

- [ ] 1.2.1 Implement `GenerateTestRunID()`:
  ```go
  package testresults

  import (
      "fmt"
      "os"
      "path/filepath"
      "strings"
      "time"
  )

  // GenerateTestRunID creates a unique run ID in format: {testName}_{timestamp}
  func GenerateTestRunID(testName string) string {
      // Clean test name (remove special characters, replace spaces)
      cleanName := strings.ReplaceAll(testName, "/", "_")
      cleanName = strings.ReplaceAll(cleanName, " ", "_")

      timestamp := time.Now().Format("20060102_150405")
      return fmt.Sprintf("%s_%s", cleanName, timestamp)
  }
  ```

- [ ] 1.2.2 Implement `CreateTestResultsDir()`:
  ```go
  // CreateTestResultsDir creates the full directory structure for test results
  func CreateTestResultsDir(tracker *TestResultsTracker) error {
      // Create main results directory
      if err := os.MkdirAll(tracker.ResultsDir, 0755); err != nil {
          return fmt.Errorf("failed to create results dir: %w", err)
      }

      // Create subdirectories
      subdirs := []string{
          "logs",
          "data",
          "data/scripts",
          "data/scripts/init",
          "config",
          "config/service-configs",
          "metadata",
      }

      for _, subdir := range subdirs {
          dirPath := filepath.Join(tracker.ResultsDir, subdir)
          if err := os.MkdirAll(dirPath, 0755); err != nil {
              return fmt.Errorf("failed to create subdir %s: %w", subdir, err)
          }
      }

      return nil
  }
  ```

- [ ] 1.2.3 Implement `CaptureAll()` orchestration function:
  ```go
  // CaptureAll performs all capture operations for a completed test
  func CaptureAll(tracker *TestResultsTracker) error {
      tracker.Complete()

      // Create directory structure
      if err := CreateTestResultsDir(tracker); err != nil {
          return fmt.Errorf("failed to create directories: %w", err)
      }

      // Capture in parallel where possible, but collect all errors
      var wg sync.WaitGroup

      // Capture logs
      wg.Add(1)
      go func() {
          defer wg.Done()
          if err := CaptureLogs(tracker); err != nil {
              tracker.RecordError(fmt.Errorf("log capture failed: %w", err))
          }
      }()

      // Capture system info
      wg.Add(1)
      go func() {
          defer wg.Done()
          if err := CaptureSystemInfo(tracker); err != nil {
              tracker.RecordError(fmt.Errorf("system info capture failed: %w", err))
          }
      }()

      // Capture Docker info
      wg.Add(1)
      go func() {
          defer wg.Done()
          if err := CaptureDockerInfo(tracker); err != nil {
              tracker.RecordError(fmt.Errorf("docker info capture failed: %w", err))
          }
      }()

      // Capture git metadata
      wg.Add(1)
      go func() {
          defer wg.Done()
          if err := CaptureGitMetadata(tracker); err != nil {
              tracker.RecordError(fmt.Errorf("git metadata capture failed: %w", err))
          }
      }()

      wg.Wait()

      // Sequential operations (may depend on above)
      if err := CaptureDatabaseDumps(tracker); err != nil {
          tracker.RecordError(fmt.Errorf("database dump failed: %w", err))
      }

      if err := CaptureInitScripts(tracker); err != nil {
          tracker.RecordError(fmt.Errorf("init scripts capture failed: %w", err))
      }

      if err := CaptureServiceConfigs(tracker); err != nil {
          tracker.RecordError(fmt.Errorf("config capture failed: %w", err))
      }

      // Generate manifest (should be last)
      if err := GenerateCaptureManifest(tracker); err != nil {
          tracker.RecordError(fmt.Errorf("manifest generation failed: %w", err))
      }

      // Return error if any captures failed
      if len(tracker.CaptureErrors) > 0 {
          return fmt.Errorf("capture completed with %d errors", len(tracker.CaptureErrors))
      }

      return nil
  }
  ```

- [ ] 1.2.4 Verify capture orchestration compiles

---

## Phase 2: System and Docker Information Capture

### 2.1 Create System Info Capture

Create file `tests/e2e/common/testresults/sysinfo.go`:

- [ ] 2.1.1 Implement `CaptureSystemInfo()`:
  ```go
  package testresults

  import (
      "fmt"
      "os"
      "os/exec"
      "path/filepath"
      "runtime"
  )

  // CaptureSystemInfo captures OS, kernel, CPU, memory information
  func CaptureSystemInfo(tracker *TestResultsTracker) error {
      outputPath := filepath.Join(tracker.ResultsDir, "config", "system-info.txt")
      f, err := os.Create(outputPath)
      if err != nil {
          return fmt.Errorf("failed to create system-info.txt: %w", err)
      }
      defer f.Close()

      fmt.Fprintf(f, "System Information\n")
      fmt.Fprintf(f, "==================\n\n")

      // Go runtime info
      fmt.Fprintf(f, "Go Version: %s\n", runtime.Version())
      fmt.Fprintf(f, "GOOS: %s\n", runtime.GOOS)
      fmt.Fprintf(f, "GOARCH: %s\n", runtime.GOARCH)
      fmt.Fprintf(f, "NumCPU: %d\n\n", runtime.NumCPU())

      // OS information (using uname)
      if out, err := exec.Command("uname", "-a").Output(); err == nil {
          fmt.Fprintf(f, "uname -a: %s\n", string(out))
      }

      // Kernel version
      if out, err := exec.Command("uname", "-r").Output(); err == nil {
          fmt.Fprintf(f, "Kernel: %s\n", string(out))
      }

      // CPU info (Linux)
      if runtime.GOOS == "linux" {
          if out, err := os.ReadFile("/proc/cpuinfo"); err == nil {
              fmt.Fprintf(f, "\nCPU Info:\n%s\n", string(out))
          }

          // Memory info
          if out, err := os.ReadFile("/proc/meminfo"); err == nil {
              fmt.Fprintf(f, "\nMemory Info:\n%s\n", string(out))
          }
      }

      // macOS specific info
      if runtime.GOOS == "darwin" {
          if out, err := exec.Command("sysctl", "-n", "machdep.cpu.brand_string").Output(); err == nil {
              fmt.Fprintf(f, "CPU: %s\n", string(out))
          }
          if out, err := exec.Command("sysctl", "-n", "hw.memsize").Output(); err == nil {
              fmt.Fprintf(f, "Memory: %s bytes\n", string(out))
          }
      }

      // Disk space
      if out, err := exec.Command("df", "-h").Output(); err == nil {
          fmt.Fprintf(f, "\nDisk Space:\n%s\n", string(out))
      }

      return nil
  }
  ```

- [ ] 2.1.2 Test system info capture manually
- [ ] 2.1.3 Verify output file format is readable

### 2.2 Create Docker Info Capture

Continue in `tests/e2e/common/testresults/sysinfo.go`:

- [ ] 2.2.1 Implement `CaptureDockerInfo()`:
  ```go
  // CaptureDockerInfo captures Docker version, runtime, and environment info
  func CaptureDockerInfo(tracker *TestResultsTracker) error {
      configDir := filepath.Join(tracker.ResultsDir, "config")

      // Docker version (JSON format)
      versionPath := filepath.Join(configDir, "docker-version.json")
      if out, err := exec.Command("docker", "version", "--format", "json").Output(); err == nil {
          if err := os.WriteFile(versionPath, out, 0644); err != nil {
              return fmt.Errorf("failed to write docker-version.json: %w", err)
          }
      } else {
          // Fallback to plain text
          versionPath = filepath.Join(configDir, "docker-version.txt")
          if out, err := exec.Command("docker", "version").Output(); err == nil {
              if err := os.WriteFile(versionPath, out, 0644); err != nil {
                  return fmt.Errorf("failed to write docker-version.txt: %w", err)
              }
          }
      }

      // Docker info (JSON format)
      infoPath := filepath.Join(configDir, "docker-info.json")
      if out, err := exec.Command("docker", "info", "--format", "json").Output(); err == nil {
          if err := os.WriteFile(infoPath, out, 0644); err != nil {
              return fmt.Errorf("failed to write docker-info.json: %w", err)
          }
      } else {
          // Fallback to plain text
          infoPath = filepath.Join(configDir, "docker-info.txt")
          if out, err := exec.Command("docker", "info").Output(); err == nil {
              if err := os.WriteFile(infoPath, out, 0644); err != nil {
                  return fmt.Errorf("failed to write docker-info.txt: %w", err)
              }
          }
      }

      // Docker compose version
      composePath := filepath.Join(configDir, "docker-compose-version.txt")
      if out, err := exec.Command("docker-compose", "version").Output(); err == nil {
          if err := os.WriteFile(composePath, out, 0644); err != nil {
              return fmt.Errorf("failed to write docker-compose-version.txt: %w", err)
          }
      }

      return nil
  }
  ```

- [ ] 2.2.2 Implement `CaptureNetworkInfo()`:
  ```go
  // CaptureNetworkInfo captures Docker network information for the test environment
  func CaptureNetworkInfo(tracker *TestResultsTracker) error {
      if tracker.ComposeFile == "" {
          return nil // Skip if no compose file tracked
      }

      outputPath := filepath.Join(tracker.ResultsDir, "config", "network-info.txt")
      f, err := os.Create(outputPath)
      if err != nil {
          return fmt.Errorf("failed to create network-info.txt: %w", err)
      }
      defer f.Close()

      fmt.Fprintf(f, "Docker Network Information\n")
      fmt.Fprintf(f, "==========================\n\n")

      // List networks
      if out, err := exec.Command("docker", "network", "ls").Output(); err == nil {
          fmt.Fprintf(f, "Networks:\n%s\n\n", string(out))
      }

      // Inspect compose project networks
      // Extract project name from compose file directory
      if tracker.ComposeDir != "" {
          projectName := filepath.Base(tracker.ComposeDir)

          // List containers for this project
          cmd := exec.Command("docker-compose", "-f", tracker.ComposeFile, "ps")
          cmd.Dir = tracker.ComposeDir
          if out, err := cmd.Output(); err == nil {
              fmt.Fprintf(f, "Compose Services Status:\n%s\n\n", string(out))
          }
      }

      return nil
  }
  ```

- [ ] 2.2.3 Test Docker info capture
- [ ] 2.2.4 Verify JSON and text output formats

---

## Phase 3: Database Dumps

### 3.1 Create Database Dump Functions

Create file `tests/e2e/common/testresults/dbdump.go`:

- [ ] 3.1.1 Implement `CaptureDatabaseDumps()`:
  ```go
  package testresults

  import (
      "fmt"
      "os"
      "os/exec"
      "path/filepath"
  )

  // CaptureDatabaseDumps orchestrates all database dumps
  func CaptureDatabaseDumps(tracker *TestResultsTracker) error {
      if tracker.DatabaseInfo == nil {
          return nil // Skip if no database info
      }

      // PostgreSQL dumps
      if tracker.DatabaseInfo.PostgresHost != "" {
          if err := DumpPostgreSQL(tracker); err != nil {
              return fmt.Errorf("postgresql dump failed: %w", err)
          }
      }

      // Redis dumps
      if tracker.DatabaseInfo.RedisHost != "" {
          if err := DumpRedis(tracker); err != nil {
              // Redis dump is best-effort, log but don't fail
              tracker.RecordError(fmt.Errorf("redis dump failed: %w", err))
          }
      }

      return nil
  }
  ```

- [ ] 3.1.2 Implement `DumpPostgreSQL()`:
  ```go
  // DumpPostgreSQL creates full and schema-only PostgreSQL dumps
  func DumpPostgreSQL(tracker *TestResultsTracker) error {
      db := tracker.DatabaseInfo
      dataDir := filepath.Join(tracker.ResultsDir, "data")

      // Set PGPASSWORD environment variable for pg_dump
      env := append(os.Environ(), fmt.Sprintf("PGPASSWORD=%s", db.PostgresPassword))

      // Full dump
      fullDumpPath := filepath.Join(dataDir, "postgres_dump.sql")
      fullCmd := exec.Command("pg_dump",
          "-h", db.PostgresHost,
          "-p", db.PostgresPort,
          "-U", db.PostgresUser,
          "-d", db.PostgresDB,
          "--no-password",
          "-F", "p", // Plain text format
      )
      fullCmd.Env = env

      fullOutput, err := fullCmd.Output()
      if err != nil {
          return fmt.Errorf("pg_dump full failed: %w (stderr: %s)", err, fullCmd.Stderr)
      }

      if err := os.WriteFile(fullDumpPath, fullOutput, 0644); err != nil {
          return fmt.Errorf("failed to write full dump: %w", err)
      }

      // Schema-only dump
      schemaDumpPath := filepath.Join(dataDir, "postgres_schema.sql")
      schemaCmd := exec.Command("pg_dump",
          "-h", db.PostgresHost,
          "-p", db.PostgresPort,
          "-U", db.PostgresUser,
          "-d", db.PostgresDB,
          "--no-password",
          "-F", "p",
          "--schema-only",
      )
      schemaCmd.Env = env

      schemaOutput, err := schemaCmd.Output()
      if err != nil {
          return fmt.Errorf("pg_dump schema failed: %w", err)
      }

      if err := os.WriteFile(schemaDumpPath, schemaOutput, 0644); err != nil {
          return fmt.Errorf("failed to write schema dump: %w", err)
      }

      return nil
  }
  ```

- [ ] 3.1.3 Implement `DumpRedis()`:
  ```go
  // DumpRedis attempts to capture Redis data
  func DumpRedis(tracker *TestResultsTracker) error {
      db := tracker.DatabaseInfo
      dataDir := filepath.Join(tracker.ResultsDir, "data")

      // Trigger Redis SAVE command
      saveCmd := exec.Command("redis-cli",
          "-h", db.RedisHost,
          "-p", db.RedisPort,
          "SAVE",
      )

      if _, err := saveCmd.Output(); err != nil {
          return fmt.Errorf("redis SAVE command failed: %w", err)
      }

      // Try to copy dump.rdb if accessible
      // Note: This may not work in all environments, so we make it best-effort
      dumpPath := filepath.Join(dataDir, "redis_dump.rdb")

      // Get Redis data directory
      configCmd := exec.Command("redis-cli",
          "-h", db.RedisHost,
          "-p", db.RedisPort,
          "CONFIG", "GET", "dir",
      )

      configOutput, err := configCmd.Output()
      if err != nil {
          return fmt.Errorf("failed to get redis data dir: %w", err)
      }

      // Parse output (returns: dir\n/path/to/dir\n)
      // For simplicity, we'll just note that dump was triggered
      note := fmt.Sprintf("Redis SAVE command executed successfully.\nRedis config output:\n%s\n", string(configOutput))
      if err := os.WriteFile(dumpPath+".info", []byte(note), 0644); err != nil {
          return fmt.Errorf("failed to write redis info: %w", err)
      }

      return nil
  }
  ```

- [ ] 3.1.4 Test PostgreSQL dump with test database
- [ ] 3.1.5 Verify dump files are valid SQL
- [ ] 3.1.6 Test Redis dump (best-effort)

---

## Phase 4: Initialization Scripts and Config Capture

### 4.1 Create Init Scripts Capture

Create file `tests/e2e/common/testresults/scripts.go`:

- [ ] 4.1.1 Implement `CaptureInitScripts()`:
  ```go
  package testresults

  import (
      "fmt"
      "io"
      "os"
      "path/filepath"
  )

  // CaptureInitScripts copies all tracked initialization scripts
  func CaptureInitScripts(tracker *TestResultsTracker) error {
      if len(tracker.InitScripts) == 0 {
          return nil // No scripts to capture
      }

      scriptsDir := filepath.Join(tracker.ResultsDir, "data", "scripts", "init")

      for _, scriptPath := range tracker.InitScripts {
          if err := copyFile(scriptPath, scriptsDir); err != nil {
              return fmt.Errorf("failed to copy script %s: %w", scriptPath, err)
          }
      }

      return nil
  }

  // copyFile copies a file to destination directory, preserving filename
  func copyFile(srcPath, destDir string) error {
      src, err := os.Open(srcPath)
      if err != nil {
          return fmt.Errorf("failed to open source: %w", err)
      }
      defer src.Close()

      filename := filepath.Base(srcPath)
      destPath := filepath.Join(destDir, filename)

      dest, err := os.Create(destPath)
      if err != nil {
          return fmt.Errorf("failed to create destination: %w", err)
      }
      defer dest.Close()

      if _, err := io.Copy(dest, src); err != nil {
          return fmt.Errorf("failed to copy file: %w", err)
      }

      return nil
  }
  ```

- [ ] 4.1.2 Implement `AutoDetectInitScripts()` to scan docker-compose:
  ```go
  // AutoDetectInitScripts scans docker-compose file for init scripts
  func AutoDetectInitScripts(tracker *TestResultsTracker) error {
      if tracker.ComposeFile == "" {
          return nil
      }

      // Read docker-compose file
      content, err := os.ReadFile(tracker.ComposeFile)
      if err != nil {
          return fmt.Errorf("failed to read compose file: %w", err)
      }

      // Simple heuristic: look for .sql or .cql files in volume mounts
      // This is a basic implementation - could be enhanced with proper YAML parsing
      contentStr := string(content)

      // Common patterns for init scripts
      patterns := []string{
          "init_shared_pgsql.sql",
          "init_trax_pgsql.sql",
          "init_laser_pgsql.sql",
          "init_lcmgr_pgsql.sql",
          "init_accmgr_pgsql.sql",
          "init_instrmgr_pgsql.sql",
          "init_test_cluster.sql",
      }

      // Search for these patterns in the project
      baseDir := tracker.ComposeDir
      if baseDir == "" {
          baseDir = filepath.Dir(tracker.ComposeFile)
      }

      for _, pattern := range patterns {
          // Look in common locations
          searchDirs := []string{
              filepath.Join(baseDir, "..", "..", "..", "deploy", "k8s", "init"),
              filepath.Join(baseDir, "init"),
              filepath.Join(baseDir),
          }

          for _, searchDir := range searchDirs {
              scriptPath := filepath.Join(searchDir, pattern)
              if _, err := os.Stat(scriptPath); err == nil {
                  tracker.TrackInitScript(scriptPath)
              }
          }
      }

      return nil
  }
  ```

- [ ] 4.1.3 Test init scripts capture with sample files
- [ ] 4.1.4 Verify copied files are identical to originals

### 4.2 Create Service Config Capture

Create file `tests/e2e/common/testresults/config.go`:

- [ ] 4.2.1 Implement `CaptureServiceConfigs()`:
  ```go
  package testresults

  import (
      "fmt"
      "os"
      "os/exec"
      "path/filepath"
      "strings"
  )

  // CaptureServiceConfigs captures service configurations and environment variables
  func CaptureServiceConfigs(tracker *TestResultsTracker) error {
      configDir := filepath.Join(tracker.ResultsDir, "config", "service-configs")

      // Copy docker-compose file
      if tracker.ComposeFile != "" {
          destPath := filepath.Join(tracker.ResultsDir, "config", "docker-compose.yaml")
          if err := copyFileTo(tracker.ComposeFile, destPath); err != nil {
              return fmt.Errorf("failed to copy docker-compose: %w", err)
          }
      }

      // Extract environment variables for each service
      if len(tracker.Services) > 0 && tracker.ComposeFile != "" {
          for _, service := range tracker.Services {
              if err := captureServiceEnv(tracker, service, configDir); err != nil {
                  tracker.RecordError(fmt.Errorf("failed to capture %s env: %w", service, err))
              }
          }
      }

      // Capture tracked config files
      for service, configPath := range tracker.ConfigFiles {
          destName := fmt.Sprintf("%s.conf", service)
          destPath := filepath.Join(configDir, destName)
          if err := copyFileTo(configPath, destPath); err != nil {
              tracker.RecordError(fmt.Errorf("failed to copy %s config: %w", service, err))
          }
      }

      return nil
  }

  // copyFileTo copies a file to a specific destination path
  func copyFileTo(srcPath, destPath string) error {
      src, err := os.Open(srcPath)
      if err != nil {
          return fmt.Errorf("failed to open source: %w", err)
      }
      defer src.Close()

      dest, err := os.Create(destPath)
      if err != nil {
          return fmt.Errorf("failed to create destination: %w", err)
      }
      defer dest.Close()

      if _, err := io.Copy(dest, src); err != nil {
          return fmt.Errorf("failed to copy: %w", err)
      }

      return nil
  }

  // captureServiceEnv extracts environment variables for a service
  func captureServiceEnv(tracker *TestResultsTracker, service, configDir string) error {
      // Use docker-compose config to get rendered service config
      cmd := exec.Command("docker-compose", "-f", tracker.ComposeFile, "config")
      cmd.Dir = tracker.ComposeDir

      output, err := cmd.Output()
      if err != nil {
          return fmt.Errorf("docker-compose config failed: %w", err)
      }

      // Parse output to extract environment variables for this service
      // This is a simplified version - full implementation would parse YAML properly
      outputStr := string(output)

      envFile := filepath.Join(configDir, fmt.Sprintf("%s.env", service))
      f, err := os.Create(envFile)
      if err != nil {
          return fmt.Errorf("failed to create env file: %w", err)
      }
      defer f.Close()

      fmt.Fprintf(f, "# Environment variables for service: %s\n", service)
      fmt.Fprintf(f, "# Extracted from docker-compose config\n\n")

      // Extract environment section for this service (simplified)
      // In production, use proper YAML parsing
      serviceSection := extractServiceSection(outputStr, service)
      fmt.Fprintf(f, "%s\n", serviceSection)

      return nil
  }

  // extractServiceSection extracts the service section from compose config (simplified)
  func extractServiceSection(configYaml, service string) string {
      // This is a placeholder - implement proper YAML parsing
      lines := strings.Split(configYaml, "\n")
      inService := false
      result := []string{}

      for _, line := range lines {
          if strings.Contains(line, service+":") {
              inService = true
          }
          if inService {
              result = append(result, line)
              // Stop at next service (basic heuristic)
              if strings.HasPrefix(line, "  ") && strings.HasSuffix(line, ":") && !strings.Contains(line, "environment") {
                  if len(result) > 5 { // Ensure we captured something
                      break
                  }
              }
          }
      }

      return strings.Join(result, "\n")
  }
  ```

- [ ] 4.2.2 Test service config capture
- [ ] 4.2.3 Verify environment variables are captured correctly

---

## Phase 5: Git Metadata and Manifest Generation

### 5.1 Create Git Metadata Capture

Create file `tests/e2e/common/testresults/git.go`:

- [ ] 5.1.1 Implement `CaptureGitMetadata()`:
  ```go
  package testresults

  import (
      "fmt"
      "os"
      "os/exec"
      "path/filepath"
  )

  // CaptureGitMetadata captures git branch, commit, diff, and status
  func CaptureGitMetadata(tracker *TestResultsTracker) error {
      metadataDir := filepath.Join(tracker.ResultsDir, "metadata")

      // Git info file
      gitInfoPath := filepath.Join(metadataDir, "git-info.txt")
      f, err := os.Create(gitInfoPath)
      if err != nil {
          return fmt.Errorf("failed to create git-info.txt: %w", err)
      }
      defer f.Close()

      fmt.Fprintf(f, "Git Information\n")
      fmt.Fprintf(f, "===============\n\n")

      // Current branch
      if out, err := exec.Command("git", "branch", "--show-current").Output(); err == nil {
          fmt.Fprintf(f, "Branch: %s\n", string(out))
      }

      // Commit hash
      if out, err := exec.Command("git", "rev-parse", "HEAD").Output(); err == nil {
          fmt.Fprintf(f, "Commit: %s\n", string(out))
      }

      // Short commit hash
      if out, err := exec.Command("git", "rev-parse", "--short", "HEAD").Output(); err == nil {
          fmt.Fprintf(f, "Short Commit: %s\n", string(out))
      }

      // Commit author and date
      if out, err := exec.Command("git", "log", "-1", "--format=%an <%ae>").Output(); err == nil {
          fmt.Fprintf(f, "Author: %s\n", string(out))
      }

      if out, err := exec.Command("git", "log", "-1", "--format=%ad").Output(); err == nil {
          fmt.Fprintf(f, "Date: %s\n", string(out))
      }

      // Commit message
      if out, err := exec.Command("git", "log", "-1", "--format=%B").Output(); err == nil {
          fmt.Fprintf(f, "\nCommit Message:\n%s\n", string(out))
      }

      // Remote info
      fmt.Fprintf(f, "\nRemote Info:\n")
      if out, err := exec.Command("git", "remote", "-v").Output(); err == nil {
          fmt.Fprintf(f, "%s\n", string(out))
      }

      // Git status
      fmt.Fprintf(f, "\nGit Status:\n")
      if out, err := exec.Command("git", "status").Output(); err == nil {
          fmt.Fprintf(f, "%s\n", string(out))
      }

      // Git diff (uncommitted changes)
      diffPath := filepath.Join(metadataDir, "git-diff.patch")
      if out, err := exec.Command("git", "diff").Output(); err == nil {
          if err := os.WriteFile(diffPath, out, 0644); err != nil {
              return fmt.Errorf("failed to write git-diff.patch: %w", err)
          }
      }

      return nil
  }
  ```

- [ ] 5.1.2 Implement `CaptureEnvironment()`:
  ```go
  // CaptureEnvironment captures environment variables at test time
  func CaptureEnvironment(tracker *TestResultsTracker) error {
      envPath := filepath.Join(tracker.ResultsDir, "metadata", "environment.txt")
      f, err := os.Create(envPath)
      if err != nil {
          return fmt.Errorf("failed to create environment.txt: %w", err)
      }
      defer f.Close()

      fmt.Fprintf(f, "Environment Variables\n")
      fmt.Fprintf(f, "=====================\n\n")

      for _, env := range os.Environ() {
          fmt.Fprintf(f, "%s\n", env)
      }

      return nil
  }
  ```

- [ ] 5.1.3 Test git metadata capture
- [ ] 5.1.4 Verify git diff is valid patch format

### 5.2 Create Manifest Generation

Create file `tests/e2e/common/testresults/manifest.go`:

- [ ] 5.2.1 Define manifest structures:
  ```go
  package testresults

  import (
      "crypto/sha256"
      "encoding/hex"
      "encoding/json"
      "fmt"
      "io"
      "os"
      "path/filepath"
      "time"
  )

  // CaptureManifest represents the complete capture manifest
  type CaptureManifest struct {
      TestName       string                `json:"test_name"`
      SuiteName      string                `json:"suite_name"`
      RunID          string                `json:"run_id"`
      StartTime      time.Time             `json:"start_time"`
      EndTime        time.Time             `json:"end_time"`
      Duration       float64               `json:"duration_seconds"`
      ResultsDir     string                `json:"results_dir"`

      CapturedFiles  []CapturedFile        `json:"captured_files"`
      Services       []string              `json:"services"`
      InitScripts    []string              `json:"init_scripts"`

      Errors         []string              `json:"errors,omitempty"`
      GeneratedAt    time.Time             `json:"generated_at"`
  }

  // CapturedFile represents a captured file with metadata
  type CapturedFile struct {
      Path         string    `json:"path"`
      RelativePath string    `json:"relative_path"`
      Size         int64     `json:"size_bytes"`
      Checksum     string    `json:"sha256"`
      CapturedAt   time.Time `json:"captured_at"`
  }
  ```

- [ ] 5.2.2 Implement `GenerateCaptureManifest()`:
  ```go
  // GenerateCaptureManifest creates a JSON manifest of all captured artifacts
  func GenerateCaptureManifest(tracker *TestResultsTracker) error {
      manifest := &CaptureManifest{
          TestName:    tracker.TestName,
          SuiteName:   tracker.SuiteName,
          RunID:       tracker.RunID,
          StartTime:   tracker.StartTime,
          EndTime:     tracker.EndTime,
          Duration:    tracker.EndTime.Sub(tracker.StartTime).Seconds(),
          ResultsDir:  tracker.ResultsDir,
          Services:    tracker.Services,
          InitScripts: tracker.InitScripts,
          GeneratedAt: time.Now(),
      }

      // Convert errors to strings
      for _, err := range tracker.CaptureErrors {
          manifest.Errors = append(manifest.Errors, err.Error())
      }

      // Walk results directory and collect all files
      err := filepath.Walk(tracker.ResultsDir, func(path string, info os.FileInfo, err error) error {
          if err != nil {
              return err
          }

          if info.IsDir() {
              return nil
          }

          // Skip the manifest file itself
          if filepath.Base(path) == "capture-manifest.json" {
              return nil
          }

          relPath, err := filepath.Rel(tracker.ResultsDir, path)
          if err != nil {
              relPath = path
          }

          checksum, err := calculateSHA256(path)
          if err != nil {
              checksum = "error-calculating"
          }

          capturedFile := CapturedFile{
              Path:         path,
              RelativePath: relPath,
              Size:         info.Size(),
              Checksum:     checksum,
              CapturedAt:   info.ModTime(),
          }

          manifest.CapturedFiles = append(manifest.CapturedFiles, capturedFile)
          return nil
      })

      if err != nil {
          return fmt.Errorf("failed to walk results directory: %w", err)
      }

      // Write manifest
      manifestPath := filepath.Join(tracker.ResultsDir, "metadata", "capture-manifest.json")
      manifestData, err := json.MarshalIndent(manifest, "", "  ")
      if err != nil {
          return fmt.Errorf("failed to marshal manifest: %w", err)
      }

      if err := os.WriteFile(manifestPath, manifestData, 0644); err != nil {
          return fmt.Errorf("failed to write manifest: %w", err)
      }

      return nil
  }

  // calculateSHA256 computes SHA256 checksum of a file
  func calculateSHA256(filePath string) (string, error) {
      f, err := os.Open(filePath)
      if err != nil {
          return "", err
      }
      defer f.Close()

      hasher := sha256.New()
      if _, err := io.Copy(hasher, f); err != nil {
          return "", err
      }

      return hex.EncodeToString(hasher.Sum(nil)), nil
  }
  ```

- [ ] 5.2.3 Test manifest generation
- [ ] 5.2.4 Verify manifest JSON is valid and contains expected fields
- [ ] 5.2.5 Verify checksums are calculated correctly

### 5.3 Create Test Metadata Capture

Add to `tests/e2e/common/testresults/manifest.go`:

- [ ] 5.3.1 Define test info structure:
  ```go
  // TestInfo represents metadata about the test execution
  type TestInfo struct {
      Name         string    `json:"name"`
      SuiteName    string    `json:"suite_name"`
      StartTime    time.Time `json:"start_time"`
      EndTime      time.Time `json:"end_time"`
      Duration     float64   `json:"duration_seconds"`
      Result       string    `json:"result"` // "passed", "failed", "skipped"
      Error        string    `json:"error,omitempty"`
      FailureMsg   string    `json:"failure_message,omitempty"`
  }
  ```

- [ ] 5.3.2 Implement `SaveTestInfo()`:
  ```go
  // SaveTestInfo saves test execution metadata
  func SaveTestInfo(tracker *TestResultsTracker, result string, testError error) error {
      info := &TestInfo{
          Name:      tracker.TestName,
          SuiteName: tracker.SuiteName,
          StartTime: tracker.StartTime,
          EndTime:   tracker.EndTime,
          Duration:  tracker.EndTime.Sub(tracker.StartTime).Seconds(),
          Result:    result,
      }

      if testError != nil {
          info.Error = testError.Error()
      }

      infoPath := filepath.Join(tracker.ResultsDir, "metadata", "test-info.json")
      infoData, err := json.MarshalIndent(info, "", "  ")
      if err != nil {
          return fmt.Errorf("failed to marshal test info: %w", err)
      }

      if err := os.WriteFile(infoPath, infoData, 0644); err != nil {
          return fmt.Errorf("failed to write test info: %w", err)
      }

      return nil
  }
  ```

- [ ] 5.3.3 Test test info capture

---

## Phase 6: Logs Capture

### 6.1 Create Logs Capture Function

Create file `tests/e2e/common/testresults/logs.go`:

- [ ] 6.1.1 Implement `CaptureLogs()`:
  ```go
  package testresults

  import (
      "fmt"
      "os"
      "os/exec"
      "path/filepath"
  )

  // CaptureLogs extracts logs from all docker-compose services
  func CaptureLogs(tracker *TestResultsTracker) error {
      if tracker.ComposeFile == "" || len(tracker.Services) == 0 {
          return nil // No services to capture
      }

      logsDir := filepath.Join(tracker.ResultsDir, "logs")

      for _, service := range tracker.Services {
          if err := captureServiceLog(tracker, service, logsDir); err != nil {
              tracker.RecordError(fmt.Errorf("failed to capture %s logs: %w", service, err))
          }
      }

      return nil
  }

  // captureServiceLog captures logs for a single service
  func captureServiceLog(tracker *TestResultsTracker, service, logsDir string) error {
      logFile := filepath.Join(logsDir, fmt.Sprintf("%s.log", service))

      cmd := exec.Command("docker-compose",
          "-f", tracker.ComposeFile,
          "logs",
          "--no-color",
          "--timestamps",
          service,
      )
      cmd.Dir = tracker.ComposeDir

      output, err := cmd.Output()
      if err != nil {
          return fmt.Errorf("docker-compose logs failed: %w", err)
      }

      if err := os.WriteFile(logFile, output, 0644); err != nil {
          return fmt.Errorf("failed to write log file: %w", err)
      }

      return nil
  }
  ```

- [ ] 6.1.2 Implement `CaptureTestOutput()`:
  ```go
  // CaptureTestOutput captures the test's stdout/stderr
  func CaptureTestOutput(tracker *TestResultsTracker, testOutput []byte) error {
      outputPath := filepath.Join(tracker.ResultsDir, "test-output.log")

      if err := os.WriteFile(outputPath, testOutput, 0644); err != nil {
          return fmt.Errorf("failed to write test output: %w", err)
      }

      return nil
  }
  ```

- [ ] 6.1.3 Test logs capture from running docker-compose environment
- [ ] 6.1.4 Verify log files contain timestamps and full output

---

## Phase 7: Integration with Test Framework

### 7.1 Modify E2E Helper Functions

Edit file `tests/e2e/laser/e2e_helpers_test.go`:

- [ ] 7.1.1 Add import for test results package:
  ```go
  import (
      "qomet.tech/agora/daemons/tests/e2e/common/testresults"
  )
  ```

- [ ] 7.1.2 Add `setupTestResultsCapture()` function:
  ```go
  // setupTestResultsCapture initializes test results tracking for a test
  func setupTestResultsCapture(t *testing.T) *testresults.TestResultsTracker {
      // Check if results capture is enabled
      baseDir := os.Getenv("TEST_RESULTS_BASE_DIR")
      if baseDir == "" {
          t.Log("TEST_RESULTS_BASE_DIR not set, skipping results capture")
          return nil
      }

      // Get suite name from environment or default to "laser"
      suiteName := os.Getenv("TEST_SUITE_NAME")
      if suiteName == "" {
          suiteName = "laser"
      }

      // Create tracker
      tracker, err := testresults.NewTestResultsTracker(suiteName, t.Name())
      if err != nil {
          t.Logf("Warning: failed to create test results tracker: %v", err)
          return nil
      }

      // Set compose file info
      composeFile := filepath.Join(".", "docker-compose.yaml")
      composeDir := filepath.Join(".", "tests", "e2e", "laser")
      tracker.SetComposeInfo(composeFile, composeDir)

      // Track all services from docker-compose
      services := []string{
          "postgres", "redis", "rabbitmq", "init-db",
          "lcmgr", "traxctrl",
          "traxcoord1", "traxcoord2", "traxcoord3",
          "lasersvc", "accmgr", "instrmgr",
          "test-runner",
      }
      for _, svc := range services {
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
          if t.Failed() {
              result = "failed"
          } else if t.Skipped() {
              result = "skipped"
          }

          // Capture all results
          if err := testresults.CaptureAll(tracker); err != nil {
              t.Logf("Warning: test results capture failed: %v", err)
          }

          // Save test info
          var testErr error
          if t.Failed() {
              testErr = fmt.Errorf("test failed")
          }
          if err := testresults.SaveTestInfo(tracker, result, testErr); err != nil {
              t.Logf("Warning: failed to save test info: %v", err)
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
  ```

- [ ] 7.1.3 Update existing test helper functions to use tracker:
  ```go
  // Modify setupTestDatabase to track test database
  func setupTestDatabase(t *testing.T) (*sql.DB, string) {
      tracker := t.Context().Value("testResultsTracker").(*testresults.TestResultsTracker)
      // ... existing code ...

      // Track that we're using a test database
      if tracker != nil {
          tracker.SetDatabaseInfo(&testresults.DBConnectionInfo{
              PostgresHost:     host,
              PostgresPort:     port,
              PostgresUser:     user,
              PostgresPassword: password,
              PostgresDB:       dbName,
              RedisHost:        "redis",
              RedisPort:        "6379",
          })
      }

      // ... rest of existing code ...
  }
  ```

- [ ] 7.1.4 Update test functions to call setupTestResultsCapture:
  ```go
  // Example: Update TestEnvironmentHealthCheck
  func TestEnvironmentHealthCheck(t *testing.T) {
      tracker := setupTestResultsCapture(t)

      t.Log("Starting environment health check...")
      // ... rest of test ...
  }
  ```

- [ ] 7.1.5 Test integration with a simple smoke test
- [ ] 7.1.6 Verify results are captured in correct directory structure

### 7.2 Modify test.sh Script

Edit file `test.sh`:

- [ ] 7.2.1 Add environment variable setup at top:
  ```bash
  # Test results capture (always enabled)
  export TEST_RESULTS_ENABLED=true
  export TEST_RESULTS_BASE_DIR=${TEST_RESULTS_BASE_DIR:-"/test-results/e2e"}

  # Create results directory
  mkdir -p "$TEST_RESULTS_BASE_DIR"
  ```

- [ ] 7.2.2 Add logging of results location:
  ```bash
  echo "=========================================="
  echo "Test Results Configuration"
  echo "=========================================="
  echo "Results Directory: $TEST_RESULTS_BASE_DIR"
  echo "Results Capture: ENABLED (never auto-cleaned)"
  echo ""
  ```

- [ ] 7.2.3 Update test summary to mention results:
  ```bash
  # At end of script
  echo ""
  echo "Test results have been saved to: $TEST_RESULTS_BASE_DIR"
  echo "Results are preserved and will NOT be automatically cleaned"
  echo ""
  ```

- [ ] 7.2.4 Test modified test.sh script
- [ ] 7.2.5 Verify environment variables are set correctly

---

## Phase 8: Docker Compose and Makefile Updates

### 8.1 Modify docker-compose.yaml

Edit file `tests/e2e/laser/docker-compose.yaml`:

- [ ] 8.1.1 Add volume mount for test results:
  ```yaml
  services:
    test-runner:
      volumes:
        - ../../../:/workspace
        - ../../../.gobuild:/workspace/.gobuild
        - ../../../.gopkg:/go/pkg/mod
        - ../../../.tests-bin:/workspace/.tests-bin
        - ../../../.test-results:/test-results:rw  # NEW: Test results capture
  ```

- [ ] 8.1.2 Add environment variables to test-runner:
  ```yaml
    test-runner:
      environment:
        # ... existing env vars ...
        TEST_RESULTS_BASE_DIR: /test-results/e2e
        TEST_SUITE_NAME: laser
  ```

- [ ] 8.1.3 Ensure test-runner has required tools (if not already present):
  ```yaml
    test-runner:
      # Note: qomet/golang-builder:1.23.latest should already have these
      # but document what's needed:
      # - postgresql-client (for pg_dump)
      # - docker-cli (for docker commands)
      # - git (for git metadata)
  ```

- [ ] 8.1.4 Test updated docker-compose configuration
- [ ] 8.1.5 Verify volume mount permissions allow writing

### 8.2 Update Makefile Targets

Edit file `Makefile`:

- [ ] 8.2.1 Update `laser-e2e-full` target:
  ```makefile
  .PHONY: laser-e2e-full
  laser-e2e-full: laser-e2e-clean
  	@echo "🧪 Running FULL LASER E2E test suite..."
  	@echo "Tests: All tests including comprehensive CRUD, edge cases, workflows"
  	@mkdir -p ${PWD}/.test-results
  	@cd tests/e2e/laser && \
  		export BRANCH_TAG=$${BRANCH_TAG:-$$(git -C ../../.. branch --show-current)} && \
  		export TEST_RUN_PATTERN=$${TEST_RUN_PATTERN:-} && \
  		export TEST_RESULTS_BASE_DIR=${PWD}/.test-results/e2e && \
  		docker-compose up --exit-code-from test-runner --abort-on-container-exit test-runner
  	@echo "✅ Full LASER E2E test suite completed"
  	@echo "📁 Test results saved to: ${PWD}/.test-results/e2e/laser/"
  ```

- [ ] 8.2.2 Update `laser-e2e-smoke` target similarly:
  ```makefile
  .PHONY: laser-e2e-smoke
  laser-e2e-smoke:
  	@echo "🧪 Running LASER E2E smoke tests..."
  	@echo "Tests: Environment health, Schema creation, Basic CRUD ops, API endpoints, lasercli, Tables"
  	@echo "Pattern: ^Test(Environment|Database|Basic|Laser|Ethscmgr|Lasercli|AllLASER)"
  	@mkdir -p ${PWD}/.test-results
  	@cd tests/e2e/laser && \
  		export BRANCH_TAG=$${BRANCH_TAG:-$$(git -C ../../.. branch --show-current)} && \
  		export TEST_RUN_PATTERN='^Test(Environment|Database|Basic|Laser|Ethscmgr|Lasercli|AllLASER)' && \
  		export TEST_RESULTS_BASE_DIR=${PWD}/.test-results/e2e && \
  		docker-compose up --exit-code-from test-runner --abort-on-container-exit test-runner
  	@echo "✅ LASER E2E smoke tests completed"
  	@echo "📁 Test results saved to: ${PWD}/.test-results/e2e/laser/"
  ```

- [ ] 8.2.3 Add new informational target:
  ```makefile
  .PHONY: laser-e2e-results-info
  laser-e2e-results-info:
  	@echo "LASER E2E Test Results Information"
  	@echo "===================================="
  	@echo "Results Directory: ${PWD}/.test-results/e2e/laser/"
  	@echo ""
  	@if [ -d "${PWD}/.test-results/e2e/laser" ]; then \
  		echo "Recent Test Runs:"; \
  		find ${PWD}/.test-results/e2e/laser -maxdepth 2 -type d -name "*_*" | sort -r | head -10; \
  		echo ""; \
  		echo "Disk Usage:"; \
  		du -sh ${PWD}/.test-results/e2e/laser; \
  		echo ""; \
  		echo "Total Test Runs:"; \
  		find ${PWD}/.test-results/e2e/laser -maxdepth 2 -type d -name "*_*" | wc -l; \
  	else \
  		echo "No test results found yet."; \
  	fi
  	@echo ""
  	@echo "Note: Test results are NEVER automatically cleaned"
  ```

- [ ] 8.2.4 Update `laser-e2e-help` target to mention results:
  ```makefile
  .PHONY: laser-e2e-help
  laser-e2e-help:
  	@echo "LASER E2E Test Targets:"
  	@echo "  make laser-e2e-smoke         - Run smoke tests only (fast, basic functionality)"
  	@echo "  make laser-e2e-full          - Run full test suite (all tests including CRUD)"
  	@echo "  make laser-e2e-up            - Start E2E environment (all services)"
  	@echo "  make laser-e2e-down          - Stop E2E environment"
  	@echo "  make laser-e2e-clean         - Clean up E2E environment (remove volumes)"
  	@echo "  make laser-e2e-logs          - View E2E service logs"
  	@echo "  make laser-e2e-shell         - Open shell in test-runner container"
  	@echo "  make laser-e2e-results-info  - Show test results information"
  	@echo ""
  	@echo "Test Results:"
  	@echo "  Location:     ${PWD}/.test-results/e2e/laser/"
  	@echo "  Auto-Cleanup: DISABLED - results preserved indefinitely"
  	@echo "  Format:       {testName}_{timestamp}/"
  	@echo ""
  	@echo "Environment variables:"
  	@echo "  BRANCH_TAG - Docker image tag (default: current branch)"
  	@echo ""
  	@echo "Example: BRANCH_TAG=main make laser-e2e-test"
  ```

- [ ] 8.2.5 Test Makefile targets
- [ ] 8.2.6 Verify `laser-e2e-results-info` displays correct information

---

## Phase 9: Helper Scripts

### 9.1 Create Log Extraction Script

Create file `tests/e2e/common/scripts/extract-logs.sh`:

- [ ] 9.1.1 Implement script:
  ```bash
  #!/bin/bash
  # Extract logs from all docker-compose services
  # Usage: extract-logs.sh <compose-file> <output-dir>

  set -e

  if [ $# -ne 2 ]; then
      echo "Usage: $0 <compose-file> <output-dir>"
      exit 1
  fi

  COMPOSE_FILE="$1"
  OUTPUT_DIR="$2"

  # Create output directory
  mkdir -p "$OUTPUT_DIR"

  # Get list of services
  SERVICES=$(docker-compose -f "$COMPOSE_FILE" config --services)

  echo "Extracting logs from docker-compose services..."

  for service in $SERVICES; do
      echo "  - $service"
      docker-compose -f "$COMPOSE_FILE" logs --no-color --timestamps "$service" \
          > "$OUTPUT_DIR/${service}.log" 2>&1 || true
  done

  echo "Logs extracted to: $OUTPUT_DIR"
  ```

- [ ] 9.1.2 Make script executable: `chmod +x tests/e2e/common/scripts/extract-logs.sh`
- [ ] 9.1.3 Test script with running docker-compose environment

### 9.2 Create Database Dump Script

Create file `tests/e2e/common/scripts/dump-databases.sh`:

- [ ] 9.2.1 Implement script:
  ```bash
  #!/bin/bash
  # Dump PostgreSQL and Redis databases
  # Usage: dump-databases.sh <output-dir> <postgres-host> <postgres-port> <db-name> <user> <password>

  set -e

  if [ $# -ne 6 ]; then
      echo "Usage: $0 <output-dir> <postgres-host> <postgres-port> <db-name> <user> <password>"
      exit 1
  fi

  OUTPUT_DIR="$1"
  POSTGRES_HOST="$2"
  POSTGRES_PORT="$3"
  DB_NAME="$4"
  DB_USER="$5"
  DB_PASSWORD="$6"

  # Create output directory
  mkdir -p "$OUTPUT_DIR"

  echo "Dumping PostgreSQL database..."

  # Set password for pg_dump
  export PGPASSWORD="$DB_PASSWORD"

  # Full dump
  echo "  - Full dump: postgres_dump.sql"
  pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$DB_USER" -d "$DB_NAME" \
      --no-password -F p > "$OUTPUT_DIR/postgres_dump.sql"

  # Schema-only dump
  echo "  - Schema dump: postgres_schema.sql"
  pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$DB_USER" -d "$DB_NAME" \
      --no-password -F p --schema-only > "$OUTPUT_DIR/postgres_schema.sql"

  echo "PostgreSQL dumps completed"

  # Redis dump (best effort)
  echo "Triggering Redis dump..."
  redis-cli -h redis -p 6379 SAVE || echo "  Warning: Redis SAVE failed"

  echo "Database dumps completed in: $OUTPUT_DIR"
  ```

- [ ] 9.2.2 Make script executable: `chmod +x tests/e2e/common/scripts/dump-databases.sh`
- [ ] 9.2.3 Test script with test database

### 9.3 Create Docker Info Script

Create file `tests/e2e/common/scripts/capture-docker-info.sh`:

- [ ] 9.3.1 Implement script:
  ```bash
  #!/bin/bash
  # Capture Docker version, runtime, and network information
  # Usage: capture-docker-info.sh <output-dir>

  set -e

  if [ $# -ne 1 ]; then
      echo "Usage: $0 <output-dir>"
      exit 1
  fi

  OUTPUT_DIR="$1"

  # Create output directory
  mkdir -p "$OUTPUT_DIR"

  echo "Capturing Docker information..."

  # Docker version
  echo "  - Docker version"
  docker version --format json > "$OUTPUT_DIR/docker-version.json" 2>/dev/null || \
      docker version > "$OUTPUT_DIR/docker-version.txt"

  # Docker info
  echo "  - Docker info"
  docker info --format json > "$OUTPUT_DIR/docker-info.json" 2>/dev/null || \
      docker info > "$OUTPUT_DIR/docker-info.txt"

  # Docker compose version
  echo "  - Docker compose version"
  docker-compose version > "$OUTPUT_DIR/docker-compose-version.txt" 2>&1 || true

  echo "Docker information captured to: $OUTPUT_DIR"
  ```

- [ ] 9.3.2 Make script executable: `chmod +x tests/e2e/common/scripts/capture-docker-info.sh`
- [ ] 9.3.3 Test script

---

## Phase 10: Testing and Validation

### 10.1 Unit Tests for Capture Functions

Create file `tests/e2e/common/testresults/capture_test.go`:

- [ ] 10.1.1 Test `GenerateTestRunID()`:
  ```go
  func TestGenerateTestRunID(t *testing.T) {
      runID := GenerateTestRunID("TestSampleTest")

      // Verify format: TestSampleTest_{timestamp}
      if !strings.HasPrefix(runID, "TestSampleTest_") {
          t.Errorf("runID should start with test name: %s", runID)
      }

      // Verify timestamp format (20060102_150405)
      parts := strings.Split(runID, "_")
      if len(parts) < 3 {
          t.Errorf("runID should have timestamp: %s", runID)
      }
  }
  ```

- [ ] 10.1.2 Test `CreateTestResultsDir()`:
  ```go
  func TestCreateTestResultsDir(t *testing.T) {
      tmpDir := t.TempDir()
      os.Setenv("TEST_RESULTS_BASE_DIR", tmpDir)

      tracker, err := NewTestResultsTracker("test-suite", "TestSample")
      if err != nil {
          t.Fatalf("failed to create tracker: %v", err)
      }

      if err := CreateTestResultsDir(tracker); err != nil {
          t.Fatalf("failed to create directories: %v", err)
      }

      // Verify all subdirectories exist
      subdirs := []string{
          "logs", "data", "data/scripts", "data/scripts/init",
          "config", "config/service-configs", "metadata",
      }

      for _, subdir := range subdirs {
          path := filepath.Join(tracker.ResultsDir, subdir)
          if _, err := os.Stat(path); os.IsNotExist(err) {
              t.Errorf("directory should exist: %s", path)
          }
      }
  }
  ```

- [ ] 10.1.3 Test tracker methods
- [ ] 10.1.4 Run unit tests: `go test ./tests/e2e/common/testresults/`

### 10.2 Integration Test

Create file `tests/e2e/laser/test_results_capture_test.go`:

- [ ] 10.2.1 Create simple integration test:
  ```go
  package laser_e2e_test

  import (
      "testing"
      "time"
  )

  // TestResultsCaptureIntegration verifies the test results capture system works end-to-end
  func TestResultsCaptureIntegration(t *testing.T) {
      tracker := setupTestResultsCapture(t)
      if tracker == nil {
          t.Skip("Test results capture not enabled")
      }

      t.Log("Test results tracker initialized successfully")
      t.Logf("Results will be saved to: %s", tracker.ResultsDir)

      // Simulate some test work
      time.Sleep(100 * time.Millisecond)

      // Track a dummy init script (if exists)
      initScript := "../../../deploy/k8s/init/init_laser_pgsql.sql"
      if _, err := os.Stat(initScript); err == nil {
          tracker.TrackInitScript(initScript)
          t.Log("Tracked init script")
      }

      t.Log("Test completed, cleanup will capture results")
  }
  ```

- [ ] 10.2.2 Run integration test
- [ ] 10.2.3 Verify results directory is created
- [ ] 10.2.4 Verify all expected files are present
- [ ] 10.2.5 Verify manifest.json is valid

### 10.3 Full E2E Test with Capture

- [ ] 10.3.1 Run `make laser-e2e-smoke` with capture enabled
- [ ] 10.3.2 Verify results directory structure for each test:
  ```
  .test-results/e2e/laser/
  ├── TestEnvironmentHealthCheck/
  │   └── TestEnvironmentHealthCheck_20250109_150423/
  │       ├── logs/ (with all service logs)
  │       ├── data/ (with database dumps and init scripts)
  │       ├── config/ (with docker and system info)
  │       ├── metadata/ (with git info and manifest)
  │       └── test-output.log
  └── TestDatabaseSchemaCreation/
      └── TestDatabaseSchemaCreation_20250109_150430/
          └── ... (same structure)
  ```

- [ ] 10.3.3 Verify logs directory contains all service logs
- [ ] 10.3.4 Verify data directory contains PostgreSQL dumps
- [ ] 10.3.5 Verify data/scripts/init contains all SQL init files
- [ ] 10.3.6 Verify config directory contains Docker and system info
- [ ] 10.3.7 Verify metadata directory contains git info and manifest
- [ ] 10.3.8 Verify manifest.json lists all captured files
- [ ] 10.3.9 Verify test-info.json contains test metadata

### 10.4 Test Failure Scenario

- [ ] 10.4.1 Create a test that intentionally fails:
  ```go
  func TestIntentionalFailure(t *testing.T) {
      tracker := setupTestResultsCapture(t)
      if tracker == nil {
          t.Skip("Test results capture not enabled")
      }

      // Simulate test work
      time.Sleep(50 * time.Millisecond)

      // Force failure
      t.Fatal("Intentional test failure to verify capture on error")
  }
  ```

- [ ] 10.4.2 Run failing test
- [ ] 10.4.3 Verify results are still captured despite failure
- [ ] 10.4.4 Verify test-info.json shows result: "failed"
- [ ] 10.4.5 Verify error message is captured

### 10.5 Verify No Auto-Cleanup

- [ ] 10.5.1 Run multiple test runs
- [ ] 10.5.2 Verify all test results are preserved
- [ ] 10.5.3 Run `make laser-e2e-results-info`
- [ ] 10.5.4 Verify it lists all test runs
- [ ] 10.5.5 Verify disk usage is reported

---

## Phase 11: Documentation and Final Steps

### 11.1 Update Project README

- [ ] 11.1.1 Add section about E2E test results capture
- [ ] 11.1.2 Document directory structure
- [ ] 11.1.3 Document environment variables
- [ ] 11.1.4 Explain no auto-cleanup policy

### 11.2 Create Results Viewer (Optional Enhancement)

- [ ] 11.2.1 Create simple HTML viewer for results
- [ ] 11.2.2 Generate index.html in results directory
- [ ] 11.2.3 Link to all captured artifacts

### 11.3 Performance Optimization

- [ ] 11.3.1 Measure capture overhead time
- [ ] 11.3.2 Optimize parallel capture operations
- [ ] 11.3.3 Add compression option for large dumps (optional)

### 11.4 Completion Verification

- [ ] 11.4.1 Run full E2E test suite with capture
- [ ] 11.4.2 Verify all tests produce complete results
- [ ] 11.4.3 Review disk usage and consider retention policies (manual)
- [ ] 11.4.4 Document any known limitations

---

## Summary

This implementation provides a comprehensive test results capture system that:

1. **Tracks During Execution**: Uses `TestResultsTracker` to record what needs to be captured as tests run
2. **Unique Test Run IDs**: Format `{testName}_{timestamp}` with test name FIRST
3. **Complete Artifact Capture**: Logs, database dumps, init scripts, configs, system info, git metadata
4. **Failure Resilient**: Capture happens via `t.Cleanup()` even when tests fail
5. **No Auto-Cleanup**: Results accumulate indefinitely for debugging and forensics
6. **Parallel Capture**: Optimized to capture multiple artifacts concurrently
7. **Comprehensive Manifest**: JSON manifest documents all captured files with checksums
8. **Integrated**: Works seamlessly with existing E2E test infrastructure

Future agents can continue implementation by following this checklist step-by-step, with each checkbox representing a specific, testable unit of work.