# Maintenance Guide

Operational procedures for maintaining agent safety, auditing, and security.

## Weekly Audit Schedule

Automated workflows run weekly to verify agent safety controls and detect policy violations.

| Workflow | Schedule | Purpose |
|----------|----------|---------|
| Agent Audit Report | Monday 9:00 AM UTC | Analyze agent actions for restricted attempts |
| Agent Restriction Verification | Sunday 00:00 UTC | Verify safety controls remain effective |

### Agent Audit Report

**Schedule**: Every Monday at 9:00 AM UTC

**What it checks**:

- Commits and PRs by bot accounts (worker, reviewer)
- Merge actions (who merged what)
- Deployment triggers
- Attempts at restricted actions

**On violation detected**:

- Creates GitHub issue with label `safety`, `security`, `audit`
- Includes full audit report
- Links to workflow run for artifacts

**Manual trigger**:

```bash
# Trigger manually
gh workflow run agent-audit-report.yml

# With custom date range
gh workflow run agent-audit-report.yml -f since_date=2024-01-01

# With JSON output
gh workflow run agent-audit-report.yml -f output_format=json
```

### Agent Restriction Verification

**Schedule**: Every Sunday at 00:00 UTC

**What it checks**:

- NON-NEGOTIABLE PROTOCOL blocks exist in workflow agents
- NEVER merge statements present
- Branch protection rulesets configured
- Agent policy files have deny rules in settings
- Bot accounts documented in settings template

**On failure**:

- Creates GitHub issue with label `safety`, `security`, `audit`
- Includes verification results
- Links to workflow run for details

**Manual trigger**:

```bash
# Run all tests
gh workflow run verify-agent-restrictions.yml

# Run specific category
gh workflow run verify-agent-restrictions.yml -f test_category=protocol

# Verbose output
gh workflow run verify-agent-restrictions.yml -f verbose=true
```

## Token Rotation Schedule (Team Setups)

> This section applies if you use dedicated bot accounts (e.g.,
> `{org}-worker`, `{org}-reviewer`). Solo developers using a single
> GitHub account can skip this.

Bot account tokens should be rotated regularly for security.

### Rotation Reminders

Set calendar reminders for these rotation events:

| Token | Rotation Period | Reminder Date |
|-------|-----------------|---------------|
| worker-bot PAT | 90 days | [Set from creation date] |
| reviewer-bot PAT | 90 days | [Set from creation date] |
| Platform API key | 90 days | [If applicable] |

### Rotation Procedure

1. **Generate new token** in GitHub Settings > Developer Settings > Personal Access Tokens

2. **Update repository secrets**:
   ```bash
   gh secret set WORKER_PAT --body "new_token_here"
   gh secret set REVIEWER_PAT --body "new_token_here"
   ```

3. **Verify token works**:
   ```bash
   # Switch to bot account
   gh auth switch --user your-org-worker

   # Verify authentication
   gh auth status
   ```

4. **Revoke old token** after verification

5. **Update rotation reminder** for next 90 days

## Monitoring Audit Results

### Check Workflow Status

```bash
# Recent audit runs
gh run list --workflow=agent-audit-report.yml --limit=5

# Recent verification runs
gh run list --workflow=verify-agent-restrictions.yml --limit=5

# View specific run
gh run view <run-id>
```

### Download Audit Artifacts

```bash
# List artifacts from a run
gh run view <run-id> --json artifacts

# Download artifact
gh run download <run-id> -n agent-audit-report-<run-number>
```

### Review Audit Issues

```bash
# List safety/audit issues
gh issue list --label=safety --label=audit

# View specific issue
gh issue view <issue-number>
```

## Responding to Audit Alerts

When an audit alert issue is created:

### 1. Assess Severity

- **Critical**: Unauthorized merge, production deployment, main branch push
- **High**: Restricted action attempted but blocked
- **Medium**: Policy drift detected, missing protocol blocks
- **Low**: Warnings about documentation, consistency issues

### 2. Investigation Steps

```bash
# Run local analysis
./scripts/analyze-agent-actions.sh --since 2024-01-01 --verbose

# Run verification tests
./scripts/verify-agent-restrictions.sh --verbose

# Run policy linter
./scripts/lint-agent-policies.sh --verbose
```

### 3. Common Remediation

| Issue | Remediation |
|-------|-------------|
| Missing NON-NEGOTIABLE PROTOCOL | Add block to agent file |
| Missing "NEVER merge" statement | Add explicit prohibition |
| Prohibited instruction found | Remove or negate the instruction |
| Branch protection bypassed | Review ruleset settings |
| Unauthorized merge | Revoke token, audit access, update policies |

### 4. Post-Incident

- Document incident in issue
- Update policies to prevent recurrence
- Close audit issue with resolution notes
- Consider additional automated checks

## CI/CD Integration

### Agent Policy Linting

Every PR runs the agent policy linter to prevent instruction drift:

```yaml
# In .github/workflows/ci.yml
- name: Validate agent policies
  run: ./tests/validate-agent-policies.sh

- name: Lint agent policies for prohibited instructions
  run: ./scripts/lint-agent-policies.sh
```

### Linter Checks

1. PR reviewer prohibited terms (merge, move to Done, close issue)
2. Ticket worker prohibited terms (push to main, move to Done)
3. NON-NEGOTIABLE PROTOCOL blocks present
4. NEVER merge statements exist
5. Human context in approval workflow
6. Bot account identity instructions
7. Three-stage workflow consistency

## Local Verification

### Run All Checks

```bash
# Full audit
./scripts/analyze-agent-actions.sh --since 30days

# Restriction verification
./scripts/verify-agent-restrictions.sh

# Policy linting
./scripts/lint-agent-policies.sh --verbose
```

### Scheduled Local Checks

Consider adding to your workflow:

```bash
# Weekly Monday check (add to crontab or task scheduler)
0 9 * * 1 cd /path/to/project && ./scripts/analyze-agent-actions.sh --since 7days
```

## Documentation References

- [Agent Action Logging](AGENT-ACTION-LOGGING.md) - Audit script details
- [Agent Restriction Tests](testing/agent-restriction-tests.md) - Verification test details
- [Agent Linter README](../scripts/README-agent-linter.md) - Linter documentation
- [Bot Account Setup](../.claude/README.md) - Bot configuration

## Maintenance Checklist

### Weekly

- [ ] Review any audit alert issues
- [ ] Check workflow run status
- [ ] Verify no failed verification tests
- [ ] Run `/prune-memory` to review stale knowledge graph entities

### Monthly

- [ ] Review accumulated audit reports
- [ ] Check token expiration dates
- [ ] Verify branch protection rules unchanged
- [ ] Review any policy warnings

### Quarterly

- [ ] Rotate bot account tokens
- [ ] Review agent policies for drift
- [ ] Update documentation as needed
- [ ] Review and update audit thresholds
