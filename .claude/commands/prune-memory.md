---
description: Review and prune stale Memory MCP entities with time-decay scoring
---

Analyze the Memory MCP knowledge graph for stale entities and present
candidates for archival or review. No entities are deleted without user
confirmation.

## Pre-Check

Attempt a `mcp__memory__read_graph` or `mcp__memory__search_nodes` call.
If Memory MCP is not configured or unreachable:

```
→ Memory pruning skipped — Memory MCP server not available
```

Stop here.

## Workflow

### Step 1: Read the Knowledge Graph

Use `mcp__memory__read_graph` to retrieve all entities, or iterate with
`mcp__memory__search_nodes` for each entity type:

- `CompletedTicket-*`
- `ReviewObservation-*` / `Review-PR-*`
- `PatternDiscovered-*` / `Pattern-*`
- `LessonLearned-*` / `Lesson-*`
- `QualityTrend-*` / `Trend-*`

For each entity, extract the approximate creation date from observations
(look for date strings, issue numbers that can be cross-referenced, or
the `last_verified` observation if present).

### Step 2: Categorize by Age and Type

Apply these rules:

| Entity Type | Category | Threshold | Action |
|-------------|----------|-----------|--------|
| CompletedTicket, ReviewObservation | Episodic | > 60 days old | Archive candidate |
| PatternDiscovered, LessonLearned, QualityTrend | Semantic | > 90 days old | Review candidate |
| Any type | Protected | < 30 days old | Never flag |

- **Archive candidates**: Episodic entities past their threshold with no
  `last_verified` observation updated within 30 days.
- **Review candidates**: Semantic entities past their threshold. These are
  NOT deletion candidates — they are flagged for human review only.
- **Current**: Everything else.

### Step 3: Present Report

```
Memory Health Report
Total entities: {total}
Current: {current}
Archive candidates (episodic, >60d): {archive_count}
Review candidates (semantic, >90d): {review_count}

Archive candidates:
  {entity-name} (created ~{age}d ago) — {first observation summary}
  ...

Review candidates:
  {entity-name} (created ~{age}d ago) — {first observation summary}
  ...
```

If no candidates found:

```
→ Memory health: all {total} entities are current — no pruning needed
```

### Step 4: Process Archive Candidates

Ask the user:

```
Delete {archive_count} archive candidates? [y/N]
```

If confirmed, use `mcp__memory__delete_entities` for each confirmed
entity. Report:

```
→ Deleted {N} archived entities
```

### Step 5: Flag Review Candidates

For review candidates (semantic entities), do NOT delete. Instead, add
a `needs-review` observation using `mcp__memory__add_observations`:

```json
{
  "observations": [
    {
      "entityName": "{entity-name}",
      "contents": ["needs-review: flagged by /prune-memory on {date}"]
    }
  ]
}
```

Report:

```
→ Flagged {N} semantic entities for review (not deleted)
```

## Output Format

End with a Result Block:

```
---

**Result:** Memory pruning complete
Total entities: {total}
Archived (deleted): {deleted}
Flagged for review: {flagged}
Current (no action): {current}
```

## Related Commands

- `/validate-memory` — Check for missing CompletedTicket entities
- `/log-session` — Session journal with memory validation
