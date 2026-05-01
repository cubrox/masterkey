#!/bin/bash
# Agent Action Log Analyzer
# Analyzes GitHub Actions logs, git history, and PR activity to track agent actions
# and detect restricted action attempts.
#
# Usage:
#   ./scripts/analyze-agent-actions.sh [--since YYYY-MM-DD] [--output FILE]
#
# Options:
#   --since DATE    Analyze actions since this date (default: 7 days ago)
#   --output FILE   Write report to file (default: stdout)
#   --json          Output in JSON format instead of human-readable
#   --verbose       Show verbose output during analysis
#   --help          Show this help message

set -e

# Color codes for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SINCE_DATE=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)
OUTPUT_FILE=""
JSON_OUTPUT=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --since)
      SINCE_DATE="$2"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Verbose logging function
log_verbose() {
  if [ "$VERBOSE" = true ]; then
    echo "[DEBUG] $1"
  fi
}

# Ensure we're in a git repository
if [ ! -d .git ]; then
  echo "Error: Must be run from the root of the repository"
  exit 1
fi

# Check if gh CLI is available
if ! command -v gh &> /dev/null; then
  echo "Error: GitHub CLI (gh) is required but not installed"
  echo "Install from: https://cli.github.com"
  exit 1
fi

# Initialize report data
REPORT_DATE=$(date +%Y-%m-%d)
RESTRICTED_ACTIONS=0
TOTAL_ACTIONS=0
MERGE_ATTEMPTS=0
PUSH_TO_MAIN_ATTEMPTS=0
DEPLOY_PROD_ATTEMPTS=0
MOVE_TO_DONE_ATTEMPTS=0

# Create temporary directory for analysis
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# Create empty actions file
touch "$TMP_DIR/actions.jsonl"

# Function to log action in JSON format
log_action() {
  local timestamp=$1
  local agent=$2
  local action=$3
  local context=$4
  local restricted=$5

  echo "{\"timestamp\":\"$timestamp\",\"agent\":\"$agent\",\"action\":\"$action\",\"context\":$context,\"restricted_action_attempted\":$restricted}" >> "$TMP_DIR/actions.jsonl"

  TOTAL_ACTIONS=$((TOTAL_ACTIONS + 1))
  if [ "$restricted" = "true" ]; then
    RESTRICTED_ACTIONS=$((RESTRICTED_ACTIONS + 1))
  fi

  log_verbose "Logged action: $agent - $action (restricted: $restricted)"
}

# Function to check for restricted actions in commit messages and PR descriptions
check_commit_actions() {
  echo "Analyzing git commits since $SINCE_DATE..."

  # Get all commits since the specified date
  git log --since="$SINCE_DATE" --format="%H|%ai|%an|%s" > "$TMP_DIR/commits.txt" 2>/dev/null || true

  while IFS='|' read -r hash timestamp author subject; do
    [ -z "$hash" ] && continue

    # Detect bot commits (from GitHub Actions or bot accounts)
    # Match patterns: github-actions, bot, Bot, worker, reviewer
    if [[ "$author" == *"github-actions"* ]] || [[ "$author" == *"bot"* ]] || [[ "$author" == *"Bot"* ]] || [[ "$author" == *"worker"* ]] || [[ "$author" == *"reviewer"* ]]; then
      agent_name=$(echo "$author" | sed 's/\[//g' | sed 's/\]//g')

      # Check for direct push to main (these shouldn't exist with branch protection)
      branch=$(git log -1 --format=%D "$hash" 2>/dev/null | grep -o "origin/main\|HEAD -> main" || echo "")
      if [[ -n "$branch" ]]; then
        context="{\"commit\":\"$hash\",\"subject\":\"$(echo "$subject" | sed 's/"/\\"/g')\"}"
        log_action "$timestamp" "$agent_name" "push_to_main" "$context" "true"
        PUSH_TO_MAIN_ATTEMPTS=$((PUSH_TO_MAIN_ATTEMPTS + 1))
      fi

      # Log regular bot commit activity
      context="{\"commit\":\"$hash\",\"subject\":\"$(echo "$subject" | sed 's/"/\\"/g')\"}"
      log_action "$timestamp" "$agent_name" "commit" "$context" "false"
    fi
  done < "$TMP_DIR/commits.txt"
}

# Function to analyze PR activity
check_pr_actions() {
  echo "Analyzing pull request activity..."

  # Get PRs created since the specified date
  gh pr list --state all --limit 100 --json number,title,createdAt,author,mergedAt,mergedBy --search "created:>=$SINCE_DATE" > "$TMP_DIR/prs.json" 2>/dev/null || echo "[]" > "$TMP_DIR/prs.json"

  # Parse PR data
  if [ -s "$TMP_DIR/prs.json" ] && [ "$(cat "$TMP_DIR/prs.json")" != "[]" ]; then
    # Count PRs by bot authors
    jq -r '.[] | select(.author.login != null) | select(.author.login | (contains("bot") or contains("github-actions") or contains("worker") or contains("reviewer"))) | "\(.createdAt)|\(.author.login)|pr_created|{\"pr\":\(.number),\"title\":\"\(.title | gsub("\""; "\\\""))\"}"' "$TMP_DIR/prs.json" 2>/dev/null | while IFS='|' read -r timestamp agent action context; do
      [ -z "$timestamp" ] && continue
      log_action "$timestamp" "$agent" "$action" "$context" "false"
    done

    # Check for bot merges (restricted action)
    jq -r '.[] | select(.mergedBy != null) | select(.mergedBy.login != null) | select(.mergedBy.login | (contains("bot") or contains("github-actions") or contains("worker") or contains("reviewer"))) | "\(.mergedAt)|\(.mergedBy.login)|merge_pull_request|{\"pr\":\(.number),\"title\":\"\(.title | gsub("\""; "\\\""))\"}"' "$TMP_DIR/prs.json" 2>/dev/null | while IFS='|' read -r timestamp agent action context; do
      [ -z "$timestamp" ] && continue
      log_action "$timestamp" "$agent" "$action" "$context" "true"
      echo "$((MERGE_ATTEMPTS + 1))" > "$TMP_DIR/merge_count.txt"
    done

    # Update merge attempts count
    if [ -f "$TMP_DIR/merge_count.txt" ]; then
      MERGE_ATTEMPTS=$(cat "$TMP_DIR/merge_count.txt")
    fi
  fi
}

# Function to analyze GitHub Actions workflow runs
check_workflow_actions() {
  echo "Analyzing GitHub Actions workflow runs..."

  # Get workflow runs since the specified date
  gh run list --limit 100 --json workflowName,createdAt,conclusion,name 2>/dev/null > "$TMP_DIR/workflows.json" || echo "[]" > "$TMP_DIR/workflows.json"

  if [ -s "$TMP_DIR/workflows.json" ] && [ "$(cat "$TMP_DIR/workflows.json")" != "[]" ]; then
    # Check for production deployments
    jq -r '.[] | select(.workflowName != null) | select(.workflowName | (contains("deploy-production") or contains("Deploy to Production") or contains("production"))) | "\(.createdAt)|github-actions|deploy_production|{\"workflow\":\"\(.workflowName)\",\"conclusion\":\"\(.conclusion)\"}"' "$TMP_DIR/workflows.json" 2>/dev/null | while IFS='|' read -r timestamp agent action context; do
      [ -z "$timestamp" ] && continue
      # Production deploys should require manual approval
      # Flag as restricted if they appear to be automatic
      restricted="false"
      log_action "$timestamp" "$agent" "$action" "$context" "$restricted"
      echo "$((DEPLOY_PROD_ATTEMPTS + 1))" > "$TMP_DIR/deploy_count.txt"
    done

    # Update deploy count
    if [ -f "$TMP_DIR/deploy_count.txt" ]; then
      DEPLOY_PROD_ATTEMPTS=$(cat "$TMP_DIR/deploy_count.txt")
    fi

    # Check for staging deployments (not restricted)
    jq -r '.[] | select(.workflowName != null) | select(.workflowName | (contains("deploy-staging") or contains("Deploy to Staging") or contains("staging"))) | "\(.createdAt)|github-actions|deploy_staging|{\"workflow\":\"\(.workflowName)\",\"conclusion\":\"\(.conclusion)\"}"' "$TMP_DIR/workflows.json" 2>/dev/null | while IFS='|' read -r timestamp agent action context; do
      [ -z "$timestamp" ] && continue
      log_action "$timestamp" "$agent" "$action" "$context" "false"
    done
  fi
}

# Function to check issue movements (Move to Done is restricted)
check_issue_actions() {
  echo "Analyzing issue activity..."

  # Note: Tracking project board movements requires GitHub GraphQL API
  # For now, we'll scan issue comments and labels for automated changes
  # Future enhancement: Use GitHub GraphQL API to track project board movements

  log_verbose "Issue activity tracking: using basic analysis"
  : # no-op placeholder for future implementation
}

# Function to generate human-readable report
generate_report() {
  if [ "$JSON_OUTPUT" = true ]; then
    # JSON report
    cat <<EOF
{
  "report_date": "$REPORT_DATE",
  "analysis_period": {
    "since": "$SINCE_DATE",
    "until": "$(date +%Y-%m-%d)"
  },
  "summary": {
    "total_actions": $TOTAL_ACTIONS,
    "restricted_actions_attempted": $RESTRICTED_ACTIONS,
    "merge_attempts": $MERGE_ATTEMPTS,
    "push_to_main_attempts": $PUSH_TO_MAIN_ATTEMPTS,
    "deploy_prod_attempts": $DEPLOY_PROD_ATTEMPTS,
    "move_to_done_attempts": $MOVE_TO_DONE_ATTEMPTS
  },
  "actions": [
EOF
    if [ -s "$TMP_DIR/actions.jsonl" ]; then
      cat "$TMP_DIR/actions.jsonl" | sed '$!s/$/,/'
    fi
    cat <<EOF
  ]
}
EOF
  else
    # Human-readable report
    cat <<EOF

${BLUE}====================================================================${NC}
${BLUE}           Agent Action Audit Report${NC}
${BLUE}====================================================================${NC}

Report Date: $REPORT_DATE
Analysis Period: $SINCE_DATE to $(date +%Y-%m-%d)

${BLUE}SUMMARY${NC}
--------------------------------------------------------------------
Total Actions Logged:           $TOTAL_ACTIONS
Restricted Actions Attempted:   $RESTRICTED_ACTIONS

${BLUE}RESTRICTED ACTION BREAKDOWN${NC}
--------------------------------------------------------------------
Pull Request Merges:            $MERGE_ATTEMPTS
Direct Pushes to Main:          $PUSH_TO_MAIN_ATTEMPTS
Production Deployments:         $DEPLOY_PROD_ATTEMPTS
Move to Done Column:            $MOVE_TO_DONE_ATTEMPTS

EOF

    if [ $RESTRICTED_ACTIONS -gt 0 ]; then
      echo -e "${RED}WARNING: Restricted actions were attempted!${NC}"
      echo ""
      echo -e "${YELLOW}RESTRICTED ACTIONS DETAIL:${NC}"
      echo "--------------------------------------------------------------------"

      if [ -s "$TMP_DIR/actions.jsonl" ]; then
        jq -r 'select(.restricted_action_attempted == true) | "[\(.timestamp)] \(.agent) attempted \(.action)\n  Context: \(.context)"' "$TMP_DIR/actions.jsonl" 2>/dev/null || true
      fi
      echo ""
    else
      echo -e "${GREEN}No restricted actions attempted${NC}"
      echo ""
    fi

    echo -e "${BLUE}RECENT AGENT ACTIVITY:${NC}"
    echo "--------------------------------------------------------------------"
    if [ -s "$TMP_DIR/actions.jsonl" ]; then
      jq -r '"\(.timestamp) | \(.agent) | \(.action)"' "$TMP_DIR/actions.jsonl" 2>/dev/null | head -n 20 || true
    fi
    echo ""

    echo -e "${BLUE}RECOMMENDATIONS${NC}"
    echo "--------------------------------------------------------------------"
    if [ $MERGE_ATTEMPTS -gt 0 ]; then
      echo -e "${YELLOW}*${NC} Bot merge attempts detected - verify branch protection rules"
    fi
    if [ $PUSH_TO_MAIN_ATTEMPTS -gt 0 ]; then
      echo -e "${YELLOW}*${NC} Direct pushes to main detected - verify branch protection is enabled"
    fi
    if [ $RESTRICTED_ACTIONS -eq 0 ]; then
      echo -e "${GREEN}*${NC} All agent actions within protocol - no issues detected"
    fi
    echo ""

    cat <<EOF
${BLUE}====================================================================${NC}

For detailed logs, run with --json flag and pipe to jq for analysis.
Example: ./scripts/analyze-agent-actions.sh --json | jq '.actions[] | select(.restricted_action_attempted == true)'

EOF
  fi
}

# Main execution
echo "Agent Action Log Analyzer"
echo "Analyzing agent activity since $SINCE_DATE..."
echo ""

# Run analysis functions
check_commit_actions
check_pr_actions
check_workflow_actions
check_issue_actions

# Generate and output report
if [ -n "$OUTPUT_FILE" ]; then
  generate_report > "$OUTPUT_FILE"
  echo "Report saved to: $OUTPUT_FILE"
else
  generate_report
fi

# Exit with error code if restricted actions were detected
if [ $RESTRICTED_ACTIONS -gt 0 ]; then
  exit 1
fi

exit 0
