package framework

import (
	"database/sql"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"testing"
	"time"

	_ "github.com/lib/pq"
	"github.com/stretchr/testify/require"
	"github.com/xshyft/trax/pkg/common"
)

// SetupTestDatabase creates an isolated test database with random name
// If dbName is provided, it will be used; otherwise a random name is generated
// Returns: db connection and database name
func SetupTestDatabase(t *testing.T, dbName string) (*sql.DB, string) {
	t.Helper()

	// Connect to postgres admin database
	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=postgres sslmode=disable",
		os.Getenv("PGSQL_HOST"),
		os.Getenv("PGSQL_PORT"),
		os.Getenv("PGSQL_USER"),
		os.Getenv("PGSQL_PASSWORD"))

	adminDB, err := sql.Open("postgres", connStr)
	require.NoError(t, err, "failed to connect to postgres")
	defer adminDB.Close()

	// Generate database name if not provided
	if dbName == "" {
		dbName = fmt.Sprintf("e2e_test_%d_%d", time.Now().Unix(), rand.Intn(100000))
	}

	// Create test database
	_, err = adminDB.Exec(fmt.Sprintf("CREATE DATABASE %s", dbName))
	require.NoError(t, err, "failed to create test database %s", dbName)

	t.Logf("Created test database: %s", dbName)

	// Connect to new test database
	testConnStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		os.Getenv("PGSQL_HOST"),
		os.Getenv("PGSQL_PORT"),
		os.Getenv("PGSQL_USER"),
		os.Getenv("PGSQL_PASSWORD"),
		dbName)

	testDB, err := sql.Open("postgres", testConnStr)
	require.NoError(t, err, "failed to connect to test database %s", dbName)

	// Verify connection
	err = testDB.Ping()
	require.NoError(t, err, "failed to ping test database %s", dbName)

	return testDB, dbName
}

// InitializeSchema initializes a specific standalone-TRAX schema in the test database.
// Supported schemas: "trax", "test_cluster"
func InitializeSchema(t *testing.T, db *sql.DB, schemaName string) error {
	t.Helper()

	projectRoot := common.FindProjectRoot(t)

	var sqlPath string
	switch schemaName {
	case "trax":
		sqlPath = filepath.Join(projectRoot, "deploy/k8s/init/init_trax_pgsql.sql")
	case "test_cluster":
		// Special case: initialize test cluster for TRAX
		sqlPath = filepath.Join(projectRoot, "tests/e2e/trax/init_test_cluster.sql")
	default:
		return fmt.Errorf("unknown standalone TRAX schema: %s", schemaName)
	}

	common.ExecuteSQLFile(t, db, sqlPath)
	return nil
}

// DropTestDatabase drops a test database
// This is intentionally NOT called automatically to preserve debugging data
func DropTestDatabase(t *testing.T, dbName string) {
	t.Helper()

	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=postgres sslmode=disable",
		os.Getenv("PGSQL_HOST"),
		os.Getenv("PGSQL_PORT"),
		os.Getenv("PGSQL_USER"),
		os.Getenv("PGSQL_PASSWORD"))

	adminDB, err := sql.Open("postgres", connStr)
	if err != nil {
		t.Logf("Warning: failed to connect to postgres for cleanup: %v", err)
		return
	}
	defer adminDB.Close()

	// Terminate any remaining connections to the test database
	terminateQuery := fmt.Sprintf(`
		SELECT pg_terminate_backend(pg_stat_activity.pid)
		FROM pg_stat_activity
		WHERE pg_stat_activity.datname = '%s'
		  AND pid <> pg_backend_pid()`, dbName)
	_, _ = adminDB.Exec(terminateQuery)

	// Drop test database
	_, err = adminDB.Exec(fmt.Sprintf("DROP DATABASE IF EXISTS %s", dbName))
	if err != nil {
		t.Logf("Warning: failed to drop test database %s: %v", dbName, err)
	} else {
		t.Logf("Dropped test database: %s", dbName)
	}
}

// DropAllTestDatabases drops all e2e_test_* databases
// Call this at the START of a test to clean up all old test databases
func DropAllTestDatabases(t *testing.T, pattern string) {
	t.Helper()

	if pattern == "" {
		pattern = "e2e_test_%"
	}

	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=postgres sslmode=disable",
		os.Getenv("PGSQL_HOST"),
		os.Getenv("PGSQL_PORT"),
		os.Getenv("PGSQL_USER"),
		os.Getenv("PGSQL_PASSWORD"))

	adminDB, err := sql.Open("postgres", connStr)
	if err != nil {
		t.Logf("Warning: failed to connect to postgres for cleanup: %v", err)
		return
	}
	defer adminDB.Close()

	// Find all matching databases
	query := fmt.Sprintf("SELECT datname FROM pg_database WHERE datname LIKE '%s'", pattern)
	rows, err := adminDB.Query(query)
	if err != nil {
		t.Logf("Warning: failed to query test databases: %v", err)
		return
	}
	defer rows.Close()

	var databases []string
	for rows.Next() {
		var dbName string
		if err := rows.Scan(&dbName); err != nil {
			continue
		}
		databases = append(databases, dbName)
	}

	if len(databases) == 0 {
		t.Log("No test databases to clean up")
		return
	}

	t.Logf("Found %d test database(s) to clean up: %v", len(databases), databases)

	// Drop each database
	for _, dbName := range databases {
		// Terminate connections
		terminateQuery := fmt.Sprintf(`
			SELECT pg_terminate_backend(pg_stat_activity.pid)
			FROM pg_stat_activity
			WHERE pg_stat_activity.datname = '%s'
			  AND pid <> pg_backend_pid()`, dbName)
		_, _ = adminDB.Exec(terminateQuery)

		// Drop database
		_, err = adminDB.Exec(fmt.Sprintf("DROP DATABASE IF EXISTS %s", dbName))
		if err != nil {
			t.Logf("Warning: failed to drop database %s: %v", dbName, err)
		} else {
			t.Logf("Dropped test database: %s", dbName)
		}
	}
}
