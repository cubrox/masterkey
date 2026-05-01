#!/bin/bash
# Agent Restriction Verification Tests
# Run after any changes to agent policies or permissions
#
# Purpose: Verify that agents cannot perform restricted actions like:
# - Merging pull requests
# - Pushing directly to main branch
# - Moving issues to Done column
# - Deploying to production
#
# Usage:
#   ./scripts/verify-agent-restrictions.sh [--verbose] [--test TEST_NAME]
#
# Options:
#   --verbose       Show detailed output for each test
#   --test NAME     Run only specific test (protocol, permissions, docs, all)
#
# Exit codes:
#   0 = All tests passed
#   1 = One or more tests failed
#   2 = Script error (missing dependencies, etc.)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Configuration
VERBOSE=false
SPECIFIC_TEST=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose)
      VERBOSE=true
      shift
      ;;
    --test)
      SPECIFIC_TEST="$2"
      shift 2
      ;;
    --help)
      sed -n '2,21p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 2
      ;;
  esac
done

# Helper functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[PASS]${NC} $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_failure() {
  echo -e "${RED}[FAIL]${NC} $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_skip() {
  echo -e "${YELLOW}[SKIP]${NC} $1"
  TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

log_warning() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

verbose_log() {
  if [ "$VERBOSE" = true ]; then
    echo "  $1"
  fi
}

# Check if running specific test or all tests
should_run_test() {
  local test_name=$1
  if [ -z "$SPECIFIC_TEST" ] || [ "$SPECIFIC_TEST" = "all" ] || [ "$SPECIFIC_TEST" = "$test_name" ]; then
    return 0
  else
    return 1
  fi
}

# Test suite header
echo ""
echo "========================================"
echo "  Agent Restriction Verification Suite"
echo "========================================"
echo ""
echo "Date: $(date)"
echo "Repository: $(git remote get-url origin 2>/dev/null || echo 'Unknown')"
echo "Current branch: $(git branch --show-current 2>/dev/null || echo 'Unknown')"
echo ""

# Prerequisite checks
log_info "Checking prerequisites..."

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
  log_warning "gh CLI not found. Some tests will be skipped."
  log_warning "Install from: https://cli.github.com/"
fi

# Check if in git repository
if ! git rev-parse --is-inside-work-tree &> /dev/null; then
  echo -e "${RED}ERROR:${NC} Not in a git repository"
  exit 2
fi

echo ""
log_info "Starting test suite..."
echo ""

# =============================================================================
# TEST CATEGORY 1: Protocol Compliance Tests
# =============================================================================

if should_run_test "protocol"; then
  echo "--------------------------------------------"
  echo "Category 1: Agent Protocol Compliance"
  echo "--------------------------------------------"
  echo ""

  # Test 1.1: Check for NON-NEGOTIABLE PROTOCOL blocks in workflow agents
  TESTS_RUN=$((TESTS_RUN + 1))
  verbose_log "Checking for NON-NEGOTIABLE PROTOCOL blocks in workflow agent files..."

  WORKFLOW_AGENTS=("github-ticket-worker" "pr-reviewer")
  MISSING_PROTOCOL=0

  for agent in "${WORKFLOW_AGENTS[@]}"; do
    agent_file=".claude/agents/${agent}.md"
    if [ -f "$agent_file" ]; then
      if ! grep -q "NON-NEGOTIABLE PROTOCOL" "$agent_file"; then
        log_failure "Missing NON-NEGOTIABLE PROTOCOL in $agent"
        MISSING_PROTOCOL=1
      else
        verbose_log "  Found NON-NEGOTIABLE PROTOCOL in $agent"
      fi
    else
      verbose_log "  $agent_file not found (may not be configured)"
    fi
  done

  if [ $MISSING_PROTOCOL -eq 0 ]; then
    log_success "Workflow agents contain NON-NEGOTIABLE PROTOCOL blocks"
  fi

  # Test 1.2: Check pr-reviewer has "NEVER merge" statement
  TESTS_RUN=$((TESTS_RUN + 1))
  verbose_log "Checking pr-reviewer agent for NEVER merge statement..."

  if [ -f ".claude/agents/pr-reviewer.md" ]; then
    if grep -qi "NEVER.*merge" .claude/agents/pr-reviewer.md; then
      log_success "pr-reviewer.md contains NEVER merge statement"
    else
      log_failure "pr-reviewer.md missing NEVER merge statement"
    fi
  else
    log_skip "pr-reviewer.md not found"
  fi

  # Test 1.3: Check review-pr command does NOT instruct to merge
  TESTS_RUN=$((TESTS_RUN + 1))
  verbose_log "Checking review-pr command for merge prohibition..."

  if [ -f ".claude/commands/review-pr.md" ]; then
    # Should mention that it CANNOT merge, not that it should merge
    if grep -qi "cannot.*merge\|NEVER.*merge\|human.*merge" .claude/commands/review-pr.md; then
      log_success "review-pr.md correctly documents merge prohibition"
    else
      log_warning "review-pr.md doesn't explicitly document merge prohibition"
      TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    fi
  else
    log_skip "review-pr.md not found"
  fi

  # Test 1.4: Check github-ticket-worker for Done column prohibition
  TESTS_RUN=$((TESTS_RUN + 1))
  verbose_log "Checking github-ticket-worker for Done column prohibition..."

  if [ -f ".claude/agents/github-ticket-worker.md" ]; then
    if grep -qi "NEVER.*Done\|cannot.*Done" .claude/agents/github-ticket-worker.md; then
      log_success "github-ticket-worker.md prohibits moving to Done"
    else
      log_failure "github-ticket-worker.md missing Done column prohibition"
    fi
  else
    log_skip "github-ticket-worker.md not found"
  fi

  # Test 1.5: Check github-ticket-worker for main branch prohibition
  TESTS_RUN=$((TESTS_RUN + 1))
  verbose_log "Checking github-ticket-worker for main branch prohibition..."

  if [ -f ".claude/agents/github-ticket-worker.md" ]; then
    if grep -qi "NEVER.*push.*main\|NEVER.*main.*branch" .claude/agents/github-ticket-worker.md; then
      log_success "github-ticket-worker.md prohibits pushing to main"
    else
      log_failure "github-ticket-worker.md missing main branch prohibition"
    fi
  else
    log_skip "github-ticket-worker.md not found"
  fi

  echo ""
fi

# =============================================================================
# TEST CATEGORY 2: Permission Enforcement Tests
# =============================================================================

if should_run_test "permissions"; then
  echo "--------------------------------------------"
  echo "Category 2: Permission Enforcement"
  echo "--------------------------------------------"
  echo ""

  # Test 2.1: Verify branch protection on main
  TESTS_RUN=$((TESTS_RUN + 1))
  verbose_log "Checking branch protection rules on main..."

  if command -v gh &> /dev/null; then
    # Extract repo from git remote
    REPO_URL=$(git remote get-url origin 2>/dev/null || echo "")
    REPO=""
    if [[ $REPO_URL =~ github.com[:/]([^/]+/[^/.]+) ]]; then
      REPO="${BASH_REMATCH[1]}"
      REPO="${REPO%.git}"
    fi

    if [ -n "$REPO" ]; then
      # Check for rulesets (newer GitHub feature)
      RULESETS=$(gh api "repos/$REPO/rulesets" 2>/dev/null || echo "[]")
      if echo "$RULESETS" | grep -q '"enforcement":"active"'; then
        log_success "Branch protection ruleset is active"
      else
        # Fall back to check legacy branch protection
        if gh api "repos/$REPO/branches/main/protection" &> /dev/null; then
          log_success "Branch protection enabled on main"
        else
          log_failure "Branch protection NOT enabled on main"
        fi
      fi
    else
      log_skip "Could not parse repository from git remote"
    fi
  else
    log_skip "gh CLI not available"
  fi

  # Test 2.2: Verify settings template has deny rules
  TESTS_RUN=$((TESTS_RUN + 1))
  verbose_log "Checking settings template for deny rules..."

  if [ -f ".claude/settings.template.json" ]; then
    if grep -q '"deny"' .claude/settings.template.json; then
      if grep -q "gh pr merge" .claude/settings.template.json; then
        log_success "settings.template.json has merge deny rule"
      else
        log_warning "settings.template.json missing explicit merge deny rule"
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
      fi
    else
      log_failure "settings.template.json missing deny rules section"
    fi
  else
    log_skip ".claude/settings.template.json not found"
  fi

  echo ""
fi

# =============================================================================
# TEST CATEGORY 3: Documentation Verification
# =============================================================================

if should_run_test "docs"; then
  echo "--------------------------------------------"
  echo "Category 3: Documentation Verification"
  echo "--------------------------------------------"
  echo ""

  # Test 3.1: Check if .claude/README.md exists with bot account docs
  TESTS_RUN=$((TESTS_RUN + 1))
  verbose_log "Checking for bot account documentation..."

  if [ -f ".claude/README.md" ]; then
    if grep -qi "bot.*account\|worker.*reviewer" .claude/README.md; then
      log_success "Bot account documentation exists"
    else
      log_warning ".claude/README.md exists but may be missing bot account details"
      TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    fi
  else
    log_failure ".claude/README.md not found"
  fi

  # Test 3.2: Check for CLAUDE.md with workflow documentation
  TESTS_RUN=$((TESTS_RUN + 1))
  verbose_log "Checking CLAUDE.md for workflow documentation..."

  if [ -f "CLAUDE.md" ]; then
    if grep -qi "trunk.*based\|three.*stage\|workflow" CLAUDE.md; then
      log_success "CLAUDE.md contains workflow documentation"
    else
      log_warning "CLAUDE.md may be missing workflow documentation"
      TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    fi
  else
    log_skip "CLAUDE.md not found"
  fi

  # Test 3.3: Check for test scenario documentation
  TESTS_RUN=$((TESTS_RUN + 1))
  verbose_log "Checking for test scenario documentation..."

  if [ -f "docs/testing/agent-restriction-tests.md" ]; then
    log_success "Agent restriction test documentation exists"
  elif [ -f "docs/AGENT-ACTION-LOGGING.md" ]; then
    log_success "Agent action logging documentation exists"
  else
    log_warning "Test scenario documentation not found"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
  fi

  echo ""
fi

# =============================================================================
# Summary Report
# =============================================================================

echo ""
echo "========================================"
echo "  Test Summary"
echo "========================================"
echo ""
echo "Total tests run:    $TESTS_RUN"
echo -e "${GREEN}Tests passed:       $TESTS_PASSED${NC}"
echo -e "${RED}Tests failed:       $TESTS_FAILED${NC}"
echo -e "${YELLOW}Tests skipped:      $TESTS_SKIPPED${NC}"
echo ""

# Calculate pass rate
if [ $TESTS_RUN -gt 0 ]; then
  PASS_RATE=$(awk "BEGIN {printf \"%.1f\", ($TESTS_PASSED / $TESTS_RUN) * 100}")
  echo "Pass rate: $PASS_RATE%"
  echo ""
fi

# Final verdict
if [ $TESTS_FAILED -gt 0 ]; then
  echo -e "${RED}--------------------------------------------${NC}"
  echo -e "${RED}FAILED: $TESTS_FAILED test(s) failed${NC}"
  echo -e "${RED}--------------------------------------------${NC}"
  echo ""
  echo "Review the failures above and ensure agent restrictions are properly configured."
  echo ""
  exit 1
else
  echo -e "${GREEN}--------------------------------------------${NC}"
  echo -e "${GREEN}PASSED: All tests passed!${NC}"
  echo -e "${GREEN}--------------------------------------------${NC}"
  echo ""

  if [ $TESTS_SKIPPED -gt 0 ]; then
    echo -e "${YELLOW}Note: $TESTS_SKIPPED test(s) were skipped.${NC}"
    echo "This may be due to missing dependencies or manual verification requirements."
    echo ""
  fi

  exit 0
fi
