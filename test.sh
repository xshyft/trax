#!/bin/bash
set -o pipefail

# Set up Go environment
export GO111MODULE=on
export CGO_ENABLED=1
export GOCACHE=${PWD}/.gobuild
export GOPATH=""

# Configure testcontainers to use Docker socket
export DOCKER_HOST=unix:///var/run/docker.sock
export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
export TESTCONTAINERS_RYUK_DISABLED=true
export TESTCONTAINERS_REAPER_SESSION_ID=ignored
export TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal

# Test results capture (always enabled, never auto-cleaned)
export TEST_RESULTS_ENABLED=true
export TEST_RESULTS_BASE_DIR=${TEST_RESULTS_BASE_DIR:-"/test-results/e2e"}

# CRITICAL VALIDATION: TEST_SESSION_ID must be set when running E2E tests
if [ -n "$TEST_RESULTS_BASE_DIR" ] && [ "$TEST_RESULTS_BASE_DIR" != "/test-results/e2e" ]; then
    # Custom TEST_RESULTS_BASE_DIR is set, must have TEST_SESSION_ID
    :  # Continue, this is the default case
fi

# Check if TEST_SESSION_ID is set (required for E2E tests)
if [ -z "$TEST_SESSION_ID" ]; then
    echo "======================================" >&2
    echo "ERROR: TEST_SESSION_ID is not set" >&2
    echo "======================================" >&2
    echo "" >&2
    echo "TEST_SESSION_ID is REQUIRED for running E2E tests." >&2
    echo "This ensures all test results are properly organized and traceable." >&2
    echo "" >&2
    echo "DO NOT run docker-compose or test.sh directly!" >&2
    echo "Use Makefile targets instead:" >&2
    echo "  - make laser-e2e-smoke" >&2
    echo "  - make laser-e2e-full" >&2
    echo "" >&2
    echo "The Makefile automatically generates unique TEST_SESSION_ID values." >&2
    echo "======================================" >&2
    exit 1
fi

# Create results directory
mkdir -p "$TEST_RESULTS_BASE_DIR"

# Parse command-line arguments
PACKAGES=()
RUN_PATTERN=""
SHORT_TESTS=false
COVERAGE=false
RACE_DETECTION=false
FAIL_FAST=false
TIMEOUT="300s"

while [[ $# -gt 0 ]]; do
  case $1 in
    --all)
      PACKAGES=("github.com/kamcpp/trax/pkg/...")
      shift
      ;;
    --run)
      RUN_PATTERN="$2"
      shift 2
      ;;
    --short)
      SHORT_TESTS=true
      shift
      ;;
    --coverage)
      COVERAGE=true
      shift
      ;;
    --race)
      RACE_DETECTION=true
      shift
      ;;
    --failfast)
      FAIL_FAST=true
      shift
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    *)
      PACKAGES+=("$1")
      shift
      ;;
  esac
done

# Default packages: laser and lcmgr
if [ ${#PACKAGES[@]} -eq 0 ]; then
  PACKAGES=(
    "github.com/kamcpp/trax/pkg/laser/..."
    "github.com/kamcpp/trax/pkg/daemons/lcmgr/..."
  )
fi

# Build test flags
# Always run with -p 1 for sequential execution (critical for E2E tests with database isolation)
TEST_FLAGS="-v -p 1 -timeout ${TIMEOUT}"
[ "$SHORT_TESTS" = true ] && TEST_FLAGS="$TEST_FLAGS -short"
[ "$FAIL_FAST" = true ] && TEST_FLAGS="$TEST_FLAGS -failfast"
[ "$RACE_DETECTION" = true ] && TEST_FLAGS="$TEST_FLAGS -race"
[ -n "$RUN_PATTERN" ] && TEST_FLAGS="$TEST_FLAGS -run $RUN_PATTERN"

# Change to workspace directory
cd /workspace

# Test results configuration
echo "=========================================="
echo "Test Results Configuration"
echo "=========================================="
echo "Results Directory: $TEST_RESULTS_BASE_DIR"
echo "Results Capture: ENABLED (never auto-cleaned)"
echo ""

# Build clis binary (with lasercli subcommand) for E2E tests with incremental build support
echo "=========================================="
echo "Building clis (lasercli subcommand) for E2E tests..."
echo "=========================================="

# Use TESTS_BIN_DIR if set (for incremental builds), otherwise use /usr/bin/agora
TESTS_BIN_DIR=${TESTS_BIN_DIR:-/usr/bin/agora}
mkdir -p "$TESTS_BIN_DIR"
CLIS_BIN="$TESTS_BIN_DIR/clis"

# Always build clis binary (incremental build check disabled for now)
echo "Building clis binary..."
go build -o "$CLIS_BIN" ./cmd/agora/clis
if [ $? -eq 0 ]; then
  echo "✓ clis built successfully at $CLIS_BIN"
else
  echo "⚠ Warning: clis build failed (tests may skip lasercli tests)"
fi

# Create symlink for backwards compatibility
if [ "$TESTS_BIN_DIR" != "/usr/bin/agora" ]; then
  mkdir -p /usr/bin/agora
  ln -sf "$CLIS_BIN" /usr/local/bin/traxcli 2>/dev/null || cp "$CLIS_BIN" /usr/local/bin/traxcli
fi

# Verify clis works
if [ -f "$CLIS_BIN" ]; then
  "$CLIS_BIN" lasercli --help > /dev/null 2>&1 && echo "✓ clis lasercli verified working"
fi
echo ""

# Run tests for each package
EXIT_CODE=0
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0
FAILED_TEST_LIST=()
TEST_OUTPUT_FILE="/tmp/test_output_$$.txt"

go fmt ./...

for PKG in "${PACKAGES[@]}"; do
  echo "=========================================="
  echo "Running tests for: $PKG"
  echo "=========================================="

  if [ "$COVERAGE" = true ]; then
    # Extract package name for coverage file
    PKG_NAME=$(echo "$PKG" | sed 's|/|_|g' | sed 's|\.||g')
    COVERAGE_FILE="/workspace/.gobuild/coverage_${PKG_NAME}.out"
    go test $TEST_FLAGS -coverprofile="$COVERAGE_FILE" "$PKG" 2>&1 | while IFS= read -r line; do echo "[$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")] $line"; done | tee "$TEST_OUTPUT_FILE"
  else
    go test $TEST_FLAGS "$PKG" 2>&1 | while IFS= read -r line; do echo "[$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")] $line"; done | tee "$TEST_OUTPUT_FILE"
  fi

  TEST_EXIT=${PIPESTATUS[0]}

  # Parse test output for statistics
  # Go test output format: "=== RUN", "--- PASS:", "--- FAIL:", "--- SKIP:"
  # Note: Lines are prefixed with timestamps like "[2025-11-11T00:43:57.215Z] --- PASS:"
  # Total = sum of all completed tests (PASS + FAIL + SKIP), not RUN lines
  # because RUN includes subtests that may not have their own PASS/FAIL/SKIP
  PKG_PASSED=$(grep -c "\] --- PASS:" "$TEST_OUTPUT_FILE" 2>/dev/null || echo "0")
  PKG_FAILED=$(grep -c "\] --- FAIL:" "$TEST_OUTPUT_FILE" 2>/dev/null || echo "0")
  PKG_SKIPPED=$(grep -c "\] --- SKIP:" "$TEST_OUTPUT_FILE" 2>/dev/null || echo "0")

  # Strip whitespace and ensure all values are numeric (default to 0 if empty or invalid)
  PKG_PASSED=$(echo "${PKG_PASSED}" | tr -d '[:space:]')
  PKG_FAILED=$(echo "${PKG_FAILED}" | tr -d '[:space:]')
  PKG_SKIPPED=$(echo "${PKG_SKIPPED}" | tr -d '[:space:]')

  # Default to 0 if empty
  PKG_PASSED=${PKG_PASSED:-0}
  PKG_FAILED=${PKG_FAILED:-0}
  PKG_SKIPPED=${PKG_SKIPPED:-0}

  # Calculate total from completed tests
  PKG_TOTAL=$((PKG_PASSED + PKG_FAILED + PKG_SKIPPED))

  TOTAL_TESTS=$((TOTAL_TESTS + PKG_TOTAL))
  PASSED_TESTS=$((PASSED_TESTS + PKG_PASSED))
  FAILED_TESTS=$((FAILED_TESTS + PKG_FAILED))
  SKIPPED_TESTS=$((SKIPPED_TESTS + PKG_SKIPPED))

  # Collect failed test names from output
  # Extract test names from lines like: "[2025-11-11T00:43:57.215Z] --- FAIL: TestExecutorCreate_Basic (0.01s)"
  while IFS= read -r line; do
    if [[ "$line" =~ \]\ ---\ FAIL:\ (Test[^\ ]+) ]]; then
      FAILED_TEST_LIST+=("${PKG}: ${BASH_REMATCH[1]}")
    fi
  done < "$TEST_OUTPUT_FILE"

  # Report package status
  if [ $TEST_EXIT -ne 0 ]; then
    EXIT_CODE=$TEST_EXIT
    echo "FAILED: $PKG (exit code: $TEST_EXIT)"

    [ "$FAIL_FAST" = true ] && {
      rm -f "$TEST_OUTPUT_FILE"
      exit $EXIT_CODE
    }
  else
    echo "PASSED: $PKG"
  fi
done

# Clean up temporary file
rm -f "$TEST_OUTPUT_FILE"

# Print coverage summary if enabled
if [ "$COVERAGE" = true ]; then
  echo "=========================================="
  echo "Coverage Summary"
  echo "=========================================="
  go tool cover -func=/workspace/.gobuild/coverage_*.out 2>/dev/null || echo "No coverage files found"
  echo ""
fi

# Print comprehensive test summary
echo ""
echo "=========================================="
echo "TEST SUMMARY"
echo "=========================================="
echo "Total Tests:   $TOTAL_TESTS"
echo "Passed:        $PASSED_TESTS"
echo "Failed:        $FAILED_TESTS"
echo "Skipped:       $SKIPPED_TESTS"
echo ""

if [ ${#FAILED_TEST_LIST[@]} -gt 0 ]; then
  echo "FAILED TESTS:"
  for failed_test in "${FAILED_TEST_LIST[@]}"; do
    echo "  ✗ $failed_test"
  done
  echo ""
fi

# Determine overall status based on both exit code and failed test count
if [ $EXIT_CODE -eq 0 ] && [ $FAILED_TESTS -eq 0 ]; then
  echo "✓ All tests passed!"
  TEST_STATUS="PASSED"
else
  echo "✗ Some tests failed (exit code: $EXIT_CODE)"
  TEST_STATUS="FAILED"
  # Ensure we exit with error if tests failed
  [ $EXIT_CODE -eq 0 ] && EXIT_CODE=1
fi
echo "=========================================="
echo ""
echo "📁 Test results have been saved to: $TEST_RESULTS_BASE_DIR"
echo "   Results are preserved and will NOT be automatically cleaned"
echo ""

# Save test summary to session directory and print aggregated results
if [ -d "$TEST_RESULTS_BASE_DIR" ] && [ -n "$TEST_SESSION_ID" ]; then
  LATEST_SESSION="$TEST_RESULTS_BASE_DIR/$TEST_SESSION_ID"
  if [ -d "$LATEST_SESSION" ]; then
    # Create session summary file
    SESSION_SUMMARY="$LATEST_SESSION/test-session-summary.txt"
    cat > "$SESSION_SUMMARY" <<EOF
========================================
TEST SESSION SUMMARY
========================================
Session ID: $TEST_SESSION_ID
Started: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Status: $TEST_STATUS

========================================
TEST STATISTICS
========================================
Total Tests:   $TOTAL_TESTS
Passed:        $PASSED_TESTS
Failed:        $FAILED_TESTS
Skipped:       $SKIPPED_TESTS

EOF

    if [ ${#FAILED_TEST_LIST[@]} -gt 0 ]; then
      echo "========================================" >> "$SESSION_SUMMARY"
      echo "FAILED TESTS" >> "$SESSION_SUMMARY"
      echo "========================================" >> "$SESSION_SUMMARY"
      for failed_test in "${FAILED_TEST_LIST[@]}"; do
        echo "  ✗ $failed_test" >> "$SESSION_SUMMARY"
      done
      echo "" >> "$SESSION_SUMMARY"
    fi

    # Add test result files
    echo "========================================" >> "$SESSION_SUMMARY"
    echo "TEST RESULT FILES" >> "$SESSION_SUMMARY"
    echo "========================================" >> "$SESSION_SUMMARY"
    find "$LATEST_SESSION" -name "index.html" -type f 2>/dev/null | while read -r html_file; do
      rel_path="${html_file#$LATEST_SESSION/}"
      test_name=$(basename "$(dirname "$html_file")")
      echo "  • $test_name" >> "$SESSION_SUMMARY"
      echo "    $rel_path" >> "$SESSION_SUMMARY"
      echo "" >> "$SESSION_SUMMARY"
    done

    echo "========================================" >> "$SESSION_SUMMARY"
    echo "LOCATION" >> "$SESSION_SUMMARY"
    echo "========================================" >> "$SESSION_SUMMARY"
    echo "Host path: ./.test-results/e2e/$TEST_SESSION_ID/" >> "$SESSION_SUMMARY"
    echo "Container path: $LATEST_SESSION/" >> "$SESSION_SUMMARY"
    echo "" >> "$SESSION_SUMMARY"
    echo "Each test directory contains:" >> "$SESSION_SUMMARY"
    echo "  - index.html: Interactive HTML viewer with file links" >> "$SESSION_SUMMARY"
    echo "  - logs/: All service logs" >> "$SESSION_SUMMARY"
    echo "  - data/: Database dumps and init scripts" >> "$SESSION_SUMMARY"
    echo "  - config/: Docker and system configuration" >> "$SESSION_SUMMARY"
    echo "  - metadata/: Test metadata, manifest, git info" >> "$SESSION_SUMMARY"
    echo "========================================" >> "$SESSION_SUMMARY"

    echo "=========================================="
    echo "📊 AGGREGATED TEST RESULTS"
    echo "=========================================="
    echo "Session ID: $TEST_SESSION_ID"
    echo ""
    echo "🌐 HTML Viewers (double-click to open in browser):"
    echo ""
    # Find all index.html files in the session
    find "$LATEST_SESSION" -name "index.html" -type f 2>/dev/null | while read -r html_file; do
      # Convert container path to host path relative to repo root
      rel_path="${html_file#/workspace/}"
      test_name=$(basename "$(dirname "$html_file")")
      echo "  • $test_name"
      echo "    ./$rel_path"
      echo ""
    done
    echo "📂 Full session directory (on host):"
    echo "    ./.test-results/e2e/$TEST_SESSION_ID/"
    echo ""
    echo "📄 Session summary saved to:"
    echo "    ./.test-results/e2e/$TEST_SESSION_ID/test-session-summary.txt"
    echo ""
    echo "ℹ️  For agents: Test results are located at ./.test-results/e2e/$TEST_SESSION_ID/"
    echo "   - test-session-summary.txt: Complete test run summary with all statistics"
    echo "   - Each test has an index.html viewer with links to all captured files"
    echo "=========================================="
    echo ""
  fi
fi

exit $EXIT_CODE