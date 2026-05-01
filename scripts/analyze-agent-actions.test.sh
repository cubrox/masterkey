#!/bin/bash
# Tests for analyze-agent-actions.sh script
# Run this script to verify the analyzer works correctly
#
# Usage: ./scripts/analyze-agent-actions.test.sh

set -e

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Helper function to run a test
run_test() {
  local test_name=$1
  local test_command=$2
  local expected_exit_code=${3:-0}

  echo -n "Testing: $test_name ... "

  set +e
  eval "$test_command" > /tmp/test_output.txt 2>&1
  actual_exit_code=$?
  set -e

  if [ $actual_exit_code -eq $expected_exit_code ]; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${RED}FAIL${NC}"
    echo "  Expected exit code: $expected_exit_code"
    echo "  Actual exit code: $actual_exit_code"
    echo "  Output:"
    cat /tmp/test_output.txt | head -n 20
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# Helper function to check output contains expected text
check_output() {
  local test_name=$1
  local test_command=$2
  local expected_text=$3

  echo -n "Testing: $test_name ... "

  set +e
  output=$(eval "$test_command" 2>&1)
  set -e

  if echo "$output" | grep -q "$expected_text"; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${RED}FAIL${NC}"
    echo "  Expected text: $expected_text"
    echo "  Output:"
    echo "$output" | head -n 20
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

echo "Running tests for analyze-agent-actions.sh"
echo "============================================"
echo ""

# Change to repo root for tests
cd "$REPO_ROOT"

# Test 1: Script exists and is executable
run_test "Script exists and is executable" "test -x ./scripts/analyze-agent-actions.sh"

# Test 2: Help flag works
check_output "Help flag displays usage" "./scripts/analyze-agent-actions.sh --help" "Usage:"

# Test 3: Default execution (7 days)
run_test "Default execution completes" "./scripts/analyze-agent-actions.sh > /dev/null 2>&1"

# Test 4: Custom date range
run_test "Custom date range works" "./scripts/analyze-agent-actions.sh --since 2025-11-01 > /dev/null 2>&1"

# Test 5: JSON output format
check_output "JSON output format" "./scripts/analyze-agent-actions.sh --json --since 2025-11-01" "report_date"

# Test 6: JSON output is valid JSON
run_test "JSON output is valid" "./scripts/analyze-agent-actions.sh --json --since 2025-11-01 | jq . > /dev/null 2>&1"

# Test 7: Output to file
run_test "Output to file works" "rm -f /tmp/test-report.txt && ./scripts/analyze-agent-actions.sh --since 2025-11-01 --output /tmp/test-report.txt && test -f /tmp/test-report.txt"

# Test 8: Human-readable output contains expected sections
check_output "Human output has summary section" "./scripts/analyze-agent-actions.sh --since 2025-11-01" "SUMMARY"

# Test 9: Human-readable output contains recommendations
check_output "Human output has recommendations" "./scripts/analyze-agent-actions.sh --since 2025-11-01" "RECOMMENDATIONS"

# Test 10: JSON output has correct structure
check_output "JSON has analysis_period" "./scripts/analyze-agent-actions.sh --json --since 2025-11-01" "analysis_period"
check_output "JSON has summary" "./scripts/analyze-agent-actions.sh --json --since 2025-11-01" "summary"
check_output "JSON has actions array" "./scripts/analyze-agent-actions.sh --json --since 2025-11-01" "actions"

# Test 11: Unknown option shows error
check_output "Unknown option shows error" "./scripts/analyze-agent-actions.sh --unknown-option 2>&1" "Unknown option"

# Test 12: Verbose flag works
run_test "Verbose flag works" "./scripts/analyze-agent-actions.sh --verbose --since 2025-11-01 > /dev/null 2>&1"

# Summary
echo ""
echo "============================================"
echo "Test Results:"
echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
  echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
  exit 1
else
  echo -e "  ${GREEN}All tests passed!${NC}"
  exit 0
fi
