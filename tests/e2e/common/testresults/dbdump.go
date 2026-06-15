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

	fullOutput, err := fullCmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("pg_dump full failed: %w (output: %s)", err, string(fullOutput))
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

	schemaOutput, err := schemaCmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("pg_dump schema failed: %w (output: %s)", err, string(schemaOutput))
	}

	if err := os.WriteFile(schemaDumpPath, schemaOutput, 0644); err != nil {
		return fmt.Errorf("failed to write schema dump: %w", err)
	}

	return nil
}

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

	if output, err := saveCmd.CombinedOutput(); err != nil {
		return fmt.Errorf("redis SAVE command failed: %w (output: %s)", err, string(output))
	}

	// Try to get Redis data directory info
	dumpInfoPath := filepath.Join(dataDir, "redis_dump.info")

	// Get Redis config info
	configCmd := exec.Command("redis-cli",
		"-h", db.RedisHost,
		"-p", db.RedisPort,
		"CONFIG", "GET", "dir",
	)

	configOutput, err := configCmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to get redis data dir: %w", err)
	}

	// Create info file
	note := fmt.Sprintf("Redis SAVE command executed successfully.\n\nRedis config output:\n%s\n", string(configOutput))
	if err := os.WriteFile(dumpInfoPath, []byte(note), 0644); err != nil {
		return fmt.Errorf("failed to write redis info: %w", err)
	}

	return nil
}
