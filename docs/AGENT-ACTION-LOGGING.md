# Agent Action Logging and Audit Trail

## Overview

This document describes the agent action logging and audit trail system implemented to track agent behavior, detect restricted action attempts, and maintain compliance with agent safety protocols.

## Purpose

The logging system serves three primary purposes:

1. **Observability**: Track all agent actions across GitHub and deployment workflows
2. **Safety**: Detect when agents attempt restricted actions (merge PRs, push to main, deploy to production)
3. **Compliance**: Maintain an audit trail for security reviews and incident investigation

## Architecture

### Components

1. **Log Analyzer Script** (`scripts/analyze-agent-actions.sh`)
   - Analyzes git history, PR activity, and workflow runs
   - Detects restricted action attempts
   - Generates human-readable and JSON reports

2. **Weekly Audit Workflow** (`.github/workflows/agent-audit-report.yml`)
   - Runs automatically every Monday at 9:00 AM UTC
   - Can be triggered manually via workflow_dispatch
   - Creates GitHub issues when restricted actions are detected

3. **Log Format Specification**
   - Structured JSON format for machine parsing
   - Human-readable format for manual review

## Log Format Specification

### JSON Format

Each agent action is logged in JSON Lines format (one JSON object per line):

```json
{
  "timestamp": "2025-11-28T08:10:00.000Z",
  "agent": "github-actions",
  "session_id": "workflow-run-12345",
  "action": "gh pr review",
  "context": {
    "pr_number": 123,
    "repo": "your-org/your-repo",
    "review_event": "COMMENT"
  },
  "status": "success",
  "duration_ms": 450,
  "restricted_action_attempted": false,
  "error": null
}
```

### Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | ISO 8601 datetime | When the action occurred |
| `agent` | string | Agent identity (e.g., "github-actions", "{org}-worker") |
| `session_id` | string | Workflow run ID or session identifier |
| `action` | string | Action type (see Action Types below) |
| `context` | object | Action-specific context data |
| `status` | string | "success", "failure", or "pending" |
| `duration_ms` | number | Action duration in milliseconds |
| `restricted_action_attempted` | boolean | Whether action is restricted by protocol |
| `error` | string/null | Error message if action failed |

### Action Types

#### Allowed Actions

- `commit` - Regular git commit
- `pr_created` - Pull request created
- `pr_review` - Pull request reviewed
- `deploy_staging` - Deployment to staging environment
- `run_tests` - Test execution
- `build` - Build process

#### Restricted Actions (flagged with `restricted_action_attempted: true`)

- `merge_pull_request` - Merging a PR (requires human approval)
- `push_to_main` - Direct push to main branch (blocked by branch protection)
- `deploy_production` - Production deployment (requires manual approval)
- `move_to_done` - Moving issue to Done column (human-only)
- `close_issue` - Closing an issue (human-only)

## Using the Log Analyzer

### Basic Usage

Run the analyzer for the last 7 days (default):

```bash
./scripts/analyze-agent-actions.sh
```

### Analyze Specific Date Range

```bash
./scripts/analyze-agent-actions.sh --since 2025-11-01
```

### Output to File

```bash
./scripts/analyze-agent-actions.sh --output audit-report.txt
```

### JSON Output

```bash
./scripts/analyze-agent-actions.sh --json
```

### Verbose Mode

```bash
./scripts/analyze-agent-actions.sh --verbose
```

### Combined Options

```bash
./scripts/analyze-agent-actions.sh --since 2025-11-15 --json --output audit.json
```

## Sample Reports

### Human-Readable Report

```
====================================================================
           Agent Action Audit Report
====================================================================

Report Date: 2025-11-29
Analysis Period: 2025-11-22 to 2025-11-29

SUMMARY
--------------------------------------------------------------------
Total Actions Logged:           45
Restricted Actions Attempted:   0

RESTRICTED ACTION BREAKDOWN
--------------------------------------------------------------------
Pull Request Merges:            0
Direct Pushes to Main:          0
Production Deployments:         3
Move to Done Column:            0

No restricted actions attempted

RECENT AGENT ACTIVITY:
--------------------------------------------------------------------
2025-11-28T14:32:00Z | github-actions | deploy_staging
2025-11-28T12:15:00Z | github-actions | pr_review
2025-11-27T16:45:00Z | github-actions | commit

RECOMMENDATIONS
--------------------------------------------------------------------
* All agent actions within protocol - no issues detected

====================================================================
```

### JSON Report

```json
{
  "report_date": "2025-11-29",
  "analysis_period": {
    "since": "2025-11-22",
    "until": "2025-11-29"
  },
  "summary": {
    "total_actions": 45,
    "restricted_actions_attempted": 0,
    "merge_attempts": 0,
    "push_to_main_attempts": 0,
    "deploy_prod_attempts": 3,
    "move_to_done_attempts": 0
  },
  "actions": [
    {
      "timestamp": "2025-11-28T14:32:00Z",
      "agent": "github-actions",
      "action": "deploy_staging",
      "context": {"workflow": "Deploy to Staging", "conclusion": "success"},
      "restricted_action_attempted": false
    }
  ]
}
```

## Weekly Audit Workflow

The weekly audit workflow runs automatically every Monday and:

1. **Fetches Repository Data**: Pulls git history, PRs, and workflow runs
2. **Runs Analysis**: Executes `analyze-agent-actions.sh`
3. **Generates Report**: Creates audit report artifact
4. **Checks for Issues**: Scans for restricted action attempts
5. **Creates Alert Issue**: If restricted actions found, creates GitHub issue with details

### Manual Trigger

You can manually trigger the audit workflow from GitHub Actions:

1. Go to Actions tab
2. Select "Agent Activity Audit Report" workflow
3. Click "Run workflow"
4. Optionally specify:
   - `since_date`: Custom start date (YYYY-MM-DD)
   - `output_format`: "human" or "json"

### Report Artifacts

Weekly reports are stored as GitHub Actions artifacts for 90 days:

- Location: Workflow run artifacts
- Naming: `agent-audit-report-{run_number}`
- Retention: 90 days
- Format: Plain text or JSON

## Restricted Action Detection

### Detection Methods

1. **Git History Analysis**
   - Scans commits for bot/automation authors
   - Checks commit branch context for main branch pushes
   - Flags direct commits to main from automated sources

2. **Pull Request Analysis**
   - Tracks PR creation by bots
   - Detects bot-initiated merges via GitHub API
   - Cross-references merge actor with bot accounts

3. **Workflow Analysis**
   - Monitors production deployment triggers
   - Verifies manual approval gates were used
   - Flags automatic production deployments

4. **Issue Activity** (Future Enhancement)
   - Track project board movements
   - Detect automated "Move to Done" actions
   - Monitor issue closures

### What Gets Flagged

An action is flagged as restricted when:

- **Merge Attempt**: Bot user appears as PR merger
- **Push to Main**: Bot commit appears directly on main branch
- **Production Deploy**: Production deployment without manual approval gate
- **Move to Done**: Project board automation moves issue to Done
- **Close Issue**: Bot closes an issue without human trigger

## Incident Response

When restricted actions are detected:

1. **Automatic Alert**: GitHub issue created with full context
2. **Investigation Required**: Review the specific actions flagged
3. **Verify Impact**: Check if unauthorized code reached production
4. **Update Policies**: Adjust agent policies if needed
5. **Strengthen Controls**: Add additional safeguards if vulnerability found

### Investigation Checklist

- [ ] Review full audit report in workflow artifacts
- [ ] Check git history for flagged commits
- [ ] Verify branch protection rules are enabled
- [ ] Confirm agent PAT has minimal permissions
- [ ] Review recent PR merges for human approval
- [ ] Check production deployments for manual approval
- [ ] Verify no unauthorized code deployed
- [ ] Update agent policies if instruction conflicts found
- [ ] Run verification tests (`scripts/verify-agent-restrictions.sh`)

## Log Retention

| Log Type | Retention Period | Storage Location |
|----------|------------------|------------------|
| Workflow Reports | 90 days | GitHub Actions artifacts |
| Git History | Permanent | Git repository |
| GitHub API Data | N/A (queried on-demand) | GitHub API |

## Advanced Analysis

### Query Specific Actions

Extract all merge attempts:

```bash
./scripts/analyze-agent-actions.sh --json | jq '.actions[] | select(.action == "merge_pull_request")'
```

### Find Restricted Actions

```bash
./scripts/analyze-agent-actions.sh --json | jq '.actions[] | select(.restricted_action_attempted == true)'
```

### Count Actions by Agent

```bash
./scripts/analyze-agent-actions.sh --json | jq '.actions | group_by(.agent) | map({agent: .[0].agent, count: length})'
```

### Export for External Analysis

```bash
./scripts/analyze-agent-actions.sh --since 2025-01-01 --json > full-year-audit.json
```

## Integration with Other Systems

### Alerting

The audit system can be extended to send alerts via:

- Slack webhook (add to workflow)
- Email notifications (GitHub Actions email action)
- PagerDuty (for critical security events)
- Custom webhook endpoint

### Metrics Dashboard

Log data can be exported to:

- Grafana (visualization)
- Prometheus (time-series metrics)
- DataDog (observability platform)
- Custom analytics tools

## Troubleshooting

### Script Fails with "gh: command not found"

Install GitHub CLI:

```bash
# macOS
brew install gh

# Linux
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install gh
```

### Script Fails with "Permission denied"

Make script executable:

```bash
chmod +x scripts/analyze-agent-actions.sh
```

### No Actions Found

- Verify you're in the repository root
- Check the `--since` date isn't too recent
- Ensure GitHub CLI is authenticated: `gh auth status`

### Workflow Fails to Create Issue

- Check workflow has `issues: write` permission
- Verify repository settings allow issue creation
- Check for GitHub API rate limits

## References

- [NON-NEGOTIABLE PROTOCOL](./.claude/agents/github-ticket-worker.md)
- [PR Reviewer Agent](./.claude/agents/pr-reviewer.md)
- [GitHub CLI Documentation](https://cli.github.com/manual/)
- [GitHub Actions Security Best Practices](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)
