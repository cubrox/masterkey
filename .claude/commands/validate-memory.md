---
description: Validate that completed tickets have corresponding Memory MCP entities
---

Check whether completed tickets from the current session have corresponding
`CompletedTicket` entities in the Memory MCP knowledge graph. Optionally
create missing entities.

## Workflow

### Step 1: Check Memory MCP Availability

Attempt a `mcp__memory__search_nodes` call with a simple query (e.g.,
`"CompletedTicket"`). If the Memory MCP server is not configured or
unreachable:

```
→ Memory validation skipped — Memory MCP server not available
```

Stop here. Do not treat this as an error.

### Step 2: Identify Completed Tickets

Query GitHub for tickets completed during the current session. Use the
project board to find items in "Done" that have linked PRs merged today,
or check recent `git log --merges` on main for PR merge commits.

Collect: issue number, issue title, PR number, key files changed.

### Step 3: Check for Existing Entities

For each completed ticket, query Memory MCP:

```
mcp__memory__search_nodes({ "query": "CompletedTicket-{issue-number}" })
```

### Step 4: Report Results

For each ticket, report one of:

```
→ Memory OK: CompletedTicket-{issue} exists for #{issue} — {title}
✗ Missing memory: CompletedTicket-{issue} — no entity found for #{issue} ({title})
  → Create this entity? Reading PR diff to generate observations...
```

Summary line:

```
→ Memory validation: {found}/{total} completed tickets have CompletedTicket entities
```

### Step 5: Create Missing Entities (Interactive)

For each missing entity, read the PR diff and generate a `CompletedTicket`
entity with observations:

- Issue number and title
- PR number and branch name
- Summary of what was implemented
- Key files changed
- Patterns or conventions established (if any)
- Gotchas encountered (if any)

Use `mcp__memory__create_entities` to create the entity:

```json
{
  "entities": [
    {
      "name": "CompletedTicket-{issue}",
      "entityType": "CompletedTicket",
      "observations": [
        "Issue #{issue}: {title}",
        "PR #{pr} merged to main",
        "{summary of implementation}",
        "Key files: {files}",
        "{patterns or gotchas, if any}"
      ]
    }
  ]
}
```

After creating each entity, confirm:

```
→ Created CompletedTicket-{issue} with {N} observations
```

## Output Format

End with a Result Block:

```
---

**Result:** Memory validation complete
Checked: {total} completed tickets
Found: {found} existing entities
Created: {created} new entities
Missing: {still-missing} (if any were skipped)
```

## Related Commands

- `/log-session` — Session journal (includes memory validation)
- `/work-ticket` — Pick up next ticket
