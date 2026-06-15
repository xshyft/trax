#!/bin/bash
set -o pipefail

# Set up Go environment
export GO111MODULE=on
export CGO_ENABLED=1
export GOCACHE=${PWD}/.gobuild
export GOPATH=""

# Disable testcontainers Ryuk reaper when running inside Docker (Docker-in-Docker)
# The Ryuk reaper has issues with container cleanup in nested Docker environments
export TESTCONTAINERS_RYUK_DISABLED=true

# Parse command-line arguments
PACKAGES=()
RUN_PATTERN=""
SHORT_TESTS=false
COVERAGE=false
RACE_DETECTION=false
FAIL_FAST=false
TIMEOUT="60s"

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

# Default: run all unit tests (exclude tests/e2e)
if [ ${#PACKAGES[@]} -eq 0 ]; then
  PACKAGES=("github.com/kamcpp/trax/pkg/...")
fi

# Build test flags
# Unit tests can run in parallel
TEST_FLAGS="-v -timeout ${TIMEOUT}"
[ "$SHORT_TESTS" = true ] && TEST_FLAGS="$TEST_FLAGS -short"
[ "$FAIL_FAST" = true ] && TEST_FLAGS="$TEST_FLAGS -failfast"
[ "$RACE_DETECTION" = true ] && TEST_FLAGS="$TEST_FLAGS -race"
[ -n "$RUN_PATTERN" ] && TEST_FLAGS="$TEST_FLAGS -run $RUN_PATTERN"

# Run tests for each package
EXIT_CODE=0
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0
FAILED_TEST_LIST=()
TEST_OUTPUT_FILE="/tmp/test_output_$$.txt"

echo "=========================================="
echo "Running Unit Tests (no clis build)"
echo "=========================================="
echo ""

go fmt ./...

# Check for compilation errors before running tests
echo "Checking for compilation errors..."
echo "  - Checking main packages..."
if ! go build -o /dev/null ./... 2>&1; then
  echo "✗ COMPILATION FAILED in main packages - Cannot proceed with tests"
  echo "=========================================="
  exit 1
fi
echo "  - Checking test packages..."
# Use -run=^$ to compile test packages without running any tests (no test matches empty pattern)
if ! go test -run=^$ ./... 2>&1; then
  echo "✗ COMPILATION FAILED in test packages - Cannot proceed with tests"
  echo "=========================================="
  exit 1
fi
echo "✓ Compilation successful (main packages and test packages)"
echo ""

for PKG in "${PACKAGES[@]}"; do
  echo "=========================================="
  echo "Running tests for: $PKG"
  echo "=========================================="

  if [ "$COVERAGE" = true ]; then
    # Extract package name for coverage file
    PKG_NAME=$(echo "$PKG" | sed 's|/|_|g' | sed 's|\.||g')
    COVERAGE_FILE="${PWD}/.gobuild/coverage_${PKG_NAME}.out"
    go test $TEST_FLAGS -coverprofile="$COVERAGE_FILE" "$PKG" 2>&1 | tee "$TEST_OUTPUT_FILE"
  else
    go test $TEST_FLAGS "$PKG" 2>&1 | tee "$TEST_OUTPUT_FILE"
  fi

  TEST_EXIT=${PIPESTATUS[0]}

  # Parse test output for statistics
  PKG_PASSED=$(grep -c "^--- PASS:" "$TEST_OUTPUT_FILE" 2>/dev/null || echo "0")
  PKG_FAILED=$(grep -c "^--- FAIL:" "$TEST_OUTPUT_FILE" 2>/dev/null || echo "0")
  PKG_SKIPPED=$(grep -c "^--- SKIP:" "$TEST_OUTPUT_FILE" 2>/dev/null || echo "0")

  # Strip whitespace and ensure all values are numeric
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
  while IFS= read -r line; do
    if [[ "$line" =~ ^---\ FAIL:\ (Test[^\ ]+) ]]; then
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
  go tool cover -func=${PWD}/.gobuild/coverage_*.out 2>/dev/null || echo "No coverage files found"
  echo ""
fi

# Print comprehensive test summary
echo ""
echo "=========================================="
echo "UNIT TEST SUMMARY"
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
  echo "✓ All unit tests passed!"
else
  echo "✗ Some tests failed (exit code: $EXIT_CODE)"
  # Ensure we exit with error if tests failed
  [ $EXIT_CODE -eq 0 ] && EXIT_CODE=1
fi
echo "=========================================="

exit $EXIT_CODE
