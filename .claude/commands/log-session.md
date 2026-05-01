---
description: Log a session journal capturing tickets delivered, challenges, mitigations, and insights
---

Write a session journal for today's development session and save it to `reports/session-journals/YYYY-MM-DD.md`.

If a journal already exists for today's date, append a session number suffix (e.g., `2026-02-15-2.md`).

## What to Capture

### 1. Session Summary (2-3 sentences)
High-level narrative of what the session accomplished and its strategic significance.

### 2. Tickets Delivered
For each ticket completed (merged to main) during this session:

| Field | Description |
|-------|-------------|
| Ticket # and title | Issue number and short description |
| PR # | Pull request number |
| What changed | 1-2 sentence summary of the implementation |
| Files touched | Key files modified (not exhaustive) |
| Tests added | Count and nature of new tests |

### 3. Tickets In Review
Same format as above, but for PRs that are created and reviewed but not yet merged.

### 4. Challenges and Mitigations
Document every significant obstacle encountered and how it was resolved:

| Field | Description |
|-------|-------------|
| Challenge | What went wrong or blocked progress |
| Root cause | Why it happened |
| Mitigation | How it was resolved |
| Prevention | What would prevent this in the future (if applicable) |

Examples: merge conflicts, CI failures, migration errors, test failures, architectural decisions that needed revision.

### 5. Insights and Learnings
Capture knowledge that will help in future sessions:
- **Technical insights** — patterns discovered, gotchas identified, architecture decisions
- **Process insights** — workflow improvements, efficiency gains, bottlenecks identified
- **Domain insights** — business logic clarifications, product understanding

These should be concrete and actionable, not generic observations.

### 6. Tickets Created
New tickets created during the session with brief context on why they were created.

### 7. Metrics
Quick quantitative summary:
- PRs created / merged / reviewed
- Tickets completed / created
- Tests added
- Board state changes

### 8. Next Up
Prioritized list of what should be tackled next, with context on dependencies and blockers.

## Format

Use the template structure from existing journals in `reports/session-journals/`. Keep the tone factual and concise — this is a working document for project continuity, not a blog post.

## After Writing

1. Read the journal back to verify completeness
2. Cross-reference against the git log and board state to catch anything missed
3. **Validate memory writes** — check that completed tickets have corresponding
   `CompletedTicket` entities in Memory MCP:
   - For each ticket listed in "Tickets Delivered", query Memory MCP:
     `mcp__memory__search_nodes({ "query": "CompletedTicket-{issue-number}" })`
   - If Memory MCP is not configured, skip validation:
     `→ Memory validation skipped — Memory MCP server not available`
   - Report results using standard vocabulary:
     `→ Memory OK: CompletedTicket-{issue} exists for #{issue}`
     `✗ Missing memory: CompletedTicket-{issue} — no entity found for #{issue}`
     `→ Run /validate-memory to create missing entities`
   - Summary: `→ Memory validation: {found}/{total} completed tickets have CompletedTicket entities`
4. Present a brief summary to the user
5. **Consolidate session knowledge** — extract insights missed during the
   session and propose Memory MCP entities. Skip this step with an info
   message if Memory MCP is not configured.

   **Step 5a: Gather signals**
   - Read PR diffs and commit messages for PRs merged this session
   - Review the "Challenges and Mitigations" and "Insights and Learnings"
     sections from the journal you just wrote

   **Step 5b: Structured reflection**
   Prompt yourself with these questions, using the gathered signals:
   - What was the root cause of any bugs or CI failures encountered?
   - What patterns were discovered, reused, or established?
   - What would you do differently next time?
   - Were there gotchas that would trip up a future agent on similar work?

   **Step 5c: Check for duplicates**
   For each potential insight, query Memory MCP (`search_nodes`) to verify
   no existing entity already captures it. Skip duplicates.

   **Step 5d: Propose entities**
   Based on reflection, propose up to 5 new Memory MCP entities:
   - `LessonLearned` — gotchas, workarounds, root cause discoveries
   - `PatternDiscovered` — reusable patterns established or confirmed

   Present each proposed entity to the user with a preview:
   ```
   Proposed: Lesson-{short-name}
   Type: LessonLearned
   Observations:
     - {observation 1}
     - {observation 2}
   Create? [present to user for confirmation]
   ```

   **Step 5e: Write confirmed entities**
   Create only the entities the user confirms. Report:
   `→ Created {N} memory entities from session consolidation`

   If no insights worth recording, report:
   `→ No new memory entities proposed — session knowledge already captured`

## Related Commands

- `/validate-memory` — Standalone memory validation and entity creation
- `/sprint-status` — Current board health overview
- `/groom-backlog` — Prioritize and populate Ready column
- `/work-ticket` — Pick up next ticket
