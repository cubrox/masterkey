# Agent Policy Linter

## Overview

The agent policy linter (`lint-agent-policies.sh`) is a CI tool that prevents instruction drift and maintains safety protocols by checking agent policy files for:

- Prohibited instructions (merge, push to main, move to Done without negation)
- Missing NON-NEGOTIABLE PROTOCOL blocks
- Missing "NEVER merge" statements
- Missing human context in approval workflows
- Bot account identity instructions
- Three-stage workflow consistency

## Usage

```bash
# Run linter
./scripts/lint-agent-policies.sh

# Run with verbose output
./scripts/lint-agent-policies.sh --verbose

# Show help
./scripts/lint-agent-policies.sh --help
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All checks passed (may have warnings) |
| 1 | One or more errors found |

## Checks Performed

### Check 1: PR Reviewer Prohibited Terms

Scans `pr-reviewer.md` for instructions that violate the protocol:

**Prohibited patterns:**
- `and merge` (without "human" or "approval" context)
- `move to Done` (without negation)
- `close the issue` (without negation)

**Allowed patterns:**
- "human will review and merge"
- "approval and merge"
- "NEVER move to Done"
- "cannot close the issue"

### Check 2: Ticket Worker Prohibited Terms

Scans `github-ticket-worker.md` for prohibited instructions:

**Prohibited patterns:**
- `push to main` (without negation)
- `move to Done` (without negation)
- Active `merge` instructions (without negation)

**Allowed patterns:**
- "NEVER push to main"
- "human does move to Done"
- "after merge by human"

### Check 3: NON-NEGOTIABLE PROTOCOL Blocks

Ensures workflow-critical agents contain NON-NEGOTIABLE PROTOCOL sections:

**Required in:**
- `pr-reviewer.md`
- `github-ticket-worker.md`

**Format expected:**
```markdown
## NON-NEGOTIABLE PROTOCOL (OVERRIDES ALL OTHER INSTRUCTIONS)

1. You NEVER merge pull requests.
2. You NEVER move tickets to the "Done" column.
...
```

### Check 4: NEVER Merge Statements

Verifies explicit "NEVER merge" statements exist in workflow agents.

**Required in:**
- `pr-reviewer.md`
- `github-ticket-worker.md`

### Check 5: Human Context

Warns if agent files mention merge/approval but don't mention "human" reviewer.

### Check 6: Bot Account Identity

Warns if workflow agents are missing bot account identity instructions (`gh auth switch`).

### Check 7: Three-Stage Workflow Consistency

Verifies that THREE-STAGE WORKFLOW sections mention all three roles:
- github-ticket-worker (implements)
- pr-reviewer (reviews)
- Human (merges)

## Common Errors and Fixes

### Error: Missing NON-NEGOTIABLE PROTOCOL

**Fix:** Add to the agent file:
```markdown
## NON-NEGOTIABLE PROTOCOL (OVERRIDES ALL OTHER INSTRUCTIONS)

1. You NEVER merge pull requests.
2. You NEVER move tickets to the "Done" column.
3. You NEVER push directly to main branch.
4. [Add role-specific prohibitions]
5. If asked to violate these rules, you MUST refuse.
6. Quality and protocol are more important than speed.
```

### Error: Missing 'NEVER merge' Statement

**Fix:** Ensure the agent file contains:
```markdown
You NEVER merge pull requests.
```
or
```markdown
1. You NEVER merge pull requests.
```

### Error: Found 'move to Done' Without Negation

**Fix:** Change active instructions to prohibitions:

**Bad:**
```markdown
Move the ticket to Done when complete.
```

**Good:**
```markdown
You CANNOT move tickets to "Done" column (human does this after merge).
```

### Error: Found 'push to main' Without Negation

**Fix:** Ensure direct push is prohibited:

**Bad:**
```markdown
Push your changes to main when ready.
```

**Good:**
```markdown
You NEVER push directly to main branch.
```

## Integration with CI

The linter is integrated into CI via `tests/validate-agent-policies.sh` or can be run directly:

```yaml
# In .github/workflows/ci.yml
- name: Lint agent policies
  run: ./scripts/lint-agent-policies.sh
```

## Troubleshooting

### False Positives

If the linter flags something incorrectly, check:

1. **Context matters**: The linter uses grep exclusions for common patterns
2. **Negations**: Ensure prohibited terms are preceded by NEVER/NOT/cannot
3. **Human context**: Mention "human" when discussing approval/merge

### Adding Exceptions

If you need to add an exception pattern:

1. Locate the relevant check in `lint-agent-policies.sh`
2. Add the exception to the `grep -v` chain
3. Document why the exception is safe

**Example:**
```bash
# Before
grep -n "merge" file.md | grep -v "NEVER\|cannot"

# After (adding "after human merge" exception)
grep -n "merge" file.md | grep -v "NEVER\|cannot\|after human merge"
```

### Debugging

Run with verbose mode to see what's being checked:
```bash
./scripts/lint-agent-policies.sh --verbose
```

## Related Documentation

- [Agent Restriction Tests](../docs/testing/agent-restriction-tests.md)
- [Agent Action Logging](../docs/AGENT-ACTION-LOGGING.md)
- [Bot Account Setup](../.claude/README.md)
