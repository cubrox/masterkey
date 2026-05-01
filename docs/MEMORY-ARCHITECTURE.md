# Memory Architecture — Agent Institutional Knowledge

How agile-flow agents persist, retrieve, and share knowledge across sessions.
For context engineering principles behind these choices, see
[CONTEXT-OPTIMIZATIONS.md](CONTEXT-OPTIMIZATIONS.md).

---

## 1. The Mental Model

Think of an agentic system as an operating system:

| OS Concept | Agile-Flow Equivalent | Example |
|------------|-----------------------|---------|
| **CPU** | LLM (Claude) | Processes instructions, generates output |
| **RAM** | Context window | Conversation history, tool results, system prompt |
| **DISK** | External persistence | GitHub board, Memory MCP, session journals, git history, docs/ |
| **Memory Controller** | Slash commands + agent protocols | `/log-session`, `/work-ticket`, `/validate-memory`, `/prune-memory`, post-merge recording |

**RAM is fast but volatile.** Everything in the context window disappears
when the session ends. If knowledge must survive a session boundary, it must
be written to DISK before the session closes.

**RAM is finite.** The context window has a hard token limit. Every token
loaded competes for attention (see
[CONTEXT-OPTIMIZATIONS.md](CONTEXT-OPTIMIZATIONS.md) for why this matters).
Memory architecture must be selective — store what cannot be rederived, not
everything that was observed.

**The Memory Controller decides what moves between RAM and DISK.** Slash
commands and agent protocols define when and how knowledge is persisted.
Without explicit write instructions, knowledge stays in RAM and is lost.

---

## 2. Four Memory Types

Agile-flow's persistence mechanisms map to four cognitive memory types.

### Working Memory (RAM — context window)

| Attribute | Value |
|-----------|-------|
| **What it stores** | Current task context: ticket body, file contents, tool results, conversation history |
| **Where it lives** | LLM context window |
| **Who reads/writes** | Every agent, every session — automatic |
| **Lifespan** | Single session only |

Working memory is managed by Claude Code's context system. Agents do not
need to explicitly manage it, but should be aware that it is finite and
volatile. The context engineering principles in CONTEXT-OPTIMIZATIONS.md
exist to maximize the useful capacity of working memory.

### Episodic Memory (what happened)

| Attribute | Value |
|-----------|-------|
| **What it stores** | Session-specific events: tickets delivered, challenges encountered, decisions made |
| **Where it lives** | `reports/session-journals/YYYY-MM-DD.md` (git-tracked) |
| **Who reads/writes** | Written by `/log-session`; read by any agent or human reviewing history |
| **Lifespan** | Permanent (committed to git) |

Episodic memory captures the narrative of each work session. It answers
"what happened on this date?" — which tickets moved, what broke, what
workarounds were applied.

**Write path:** The `/log-session` command captures tickets delivered,
challenges and mitigations, insights and learnings, and metrics. It writes
a structured journal to `reports/session-journals/`.

**Read path:** Agents or humans read journals via git. Useful for
understanding the history behind a decision or debugging a recurring issue.

### Semantic Memory (what we know)

| Attribute | Value |
|-----------|-------|
| **What it stores** | Facts, patterns, and relationships: completed tickets, review observations, feature dependencies, strategic decisions |
| **Where it lives** | Memory MCP server (graph database) |
| **Who reads/writes** | All four agents read and write via MCP tools |
| **Lifespan** | Persistent across sessions until explicitly deleted |

Semantic memory is the agent team's shared knowledge graph. It stores
structured facts that any agent can query.

**Entity types and naming conventions:**

All agents must follow these conventions when creating Memory MCP entities.
Consistent naming is critical because Memory MCP uses keyword search, not
embeddings — retrieval quality depends entirely on predictable entity names.

| Entity Type | Convention | Example | Created By |
|-------------|-----------|---------|------------|
| CompletedTicket | `CompletedTicket-{issue-number}` | `CompletedTicket-142` | Ticket Worker |
| ReviewObservation | `Review-PR-{pr-number}` | `Review-PR-150` | PR Reviewer |
| PatternDiscovered | `Pattern-{domain}-{short-name}` | `Pattern-auth-jwt-refresh` | Ticket Worker |
| LessonLearned | `Lesson-{domain}-{short-name}` | `Lesson-db-n-plus-one-fix` | Ticket Worker |
| FeatureDecision | `Decision-{feature-name}` | `Decision-social-login` | Product Manager |
| PrioritizationLogic | `Prioritization-{epic-name}` | `Prioritization-onboarding-flow` | Backlog Prioritizer |
| QualityTrend | `Trend-{topic}` | `Trend-test-coverage-gaps` | PR Reviewer |

**The `{domain}` field** should match the ticket's epic label or primary
domain area (e.g., `auth`, `db`, `ui`, `api`, `infra`, `ci`, `docs`).
Use lowercase, hyphen-separated words. Keep names short — they are search
keys, not descriptions. Put descriptive detail in observations instead.

**Relation types:**

Agents use `create_relations` to link entities. Common relations include
dependency chains (`Feature X` depends on `Feature Y`), justification links
(`Decision A` justifies `Ticket B`), and pattern associations
(`PatternDiscovered` relates to `CompletedTicket`).

**MCP tools available:**

| Tool | Purpose | Used By |
|------|---------|---------|
| `create_entities` | Store new knowledge | All agents |
| `add_observations` | Append facts to existing entities | All agents |
| `create_relations` | Link entities together | Backlog Prioritizer, Product Manager |
| `search_nodes` | Query by keyword | All agents |
| `open_nodes` | Retrieve specific entities | All agents |

**Agent-specific usage:**

- **Ticket Worker** — records CompletedTicket, PatternDiscovered, and
  LessonLearned entities after PR merge
- **PR Reviewer** — records ReviewObservation and QualityTrend entities
  after posting reviews
- **Backlog Prioritizer** — stores prioritization decisions, feature
  dependencies, and sequencing logic; uses relations to model dependency
  chains
- **Product Manager** — stores market research, feature decision rationale,
  success metrics, and strategic context

### Procedural Memory (how we work)

| Attribute | Value |
|-----------|-------|
| **What it stores** | Workflows, conventions, safety rules, formatting standards |
| **Where it lives** | `CLAUDE.md`, `.claude/agents/*.md`, `.claude/commands/*.md`, `.claude/skills/*.md`, `docs/` |
| **Who reads/writes** | Written by humans (code review + merge); read by all agents every session |
| **Lifespan** | Permanent (committed to git, loaded into context on demand) |

Procedural memory is the most heavily used memory type. It defines how
agents behave — their protocols, constraints, and workflows. Unlike the
other memory types, procedural memory is loaded directly into working
memory (RAM) at session start.

**Hierarchy:**

```
CLAUDE.md                          (loaded every session — universal rules)
  |
  +-- .claude/agents/*.md          (loaded when agent is invoked)
  |
  +-- .claude/commands/*.md        (loaded when command is invoked)
  |
  +-- .claude/skills/*.md          (loaded when skill is referenced)
  |
  +-- docs/                        (loaded on demand via tool reads)
```

**Key design principle:** Procedural memory follows the "one canonical
location per fact" rule. A convention defined in CLAUDE.md is not repeated
in agent files. Agent files reference CLAUDE.md for shared rules and
contain only what is unique to that agent's role.

---

## 3. Data Flow — A Ticket's Lifecycle Through Memory

This walkthrough traces a single ticket through the memory system from
session start to the next session.

### Session Start

```
DISK -> RAM
  |
  +-- CLAUDE.md loaded (procedural memory)
  +-- Agent policy loaded (procedural memory)
  +-- Command file loaded (procedural memory)
  +-- /work-ticket step 3: context paging (semantic memory -> RAM)
      +-- search_nodes for Pattern-* matching ticket keywords (cap: 3)
      +-- search_nodes for Lesson-* matching ticket keywords (cap: 3)
      +-- search_nodes for CompletedTicket-* in same epic (cap: 4)
```

The agent begins with procedural memory in context. When `/work-ticket`
runs, step 3 ("Load Context from Past Sessions") automatically queries
semantic memory for relevant patterns, lessons, and prior completed tickets
related to the current ticket's domain. Results are capped at 10 entities
to avoid context pollution. This step is silently skipped if Memory MCP
is not configured or returns no results.

### During Session

```
RAM (working memory active)
  |
  +-- Reads ticket from GitHub board
  +-- Creates branch, writes code
  +-- Runs tests, creates PR
  +-- Tool results accumulate in context
```

All work happens in working memory. The context window fills with ticket
content, code diffs, test output, and conversation history. No persistence
has occurred yet.

### Session End (Post-Merge)

```
RAM -> DISK
  |
  +-- create_entities: CompletedTicket-{issue} (semantic memory)
  +-- create_entities: Pattern-{domain}-{name} (semantic memory, if applicable)
  +-- create_entities: Lesson-{domain}-{name} (semantic memory, if applicable)
  +-- /log-session writes journal (episodic memory)
  |     +-- Step 3: validates CompletedTicket entities exist
  |     +-- Step 5: consolidation — proposes LessonLearned/PatternDiscovered
  |           entities from PR diffs and structured reflection (user confirms)
  +-- git commit preserves code changes (procedural memory, if conventions changed)
  +-- Board state updated: ticket -> Done
```

This is the critical persistence step. `/log-session` now includes two
safety nets: step 3 validates that CompletedTicket entities were recorded
(flagging any that were missed), and step 5 extracts additional insights
via structured reflection on PR diffs and challenges. Both steps require
user confirmation before writing. Without these explicit writes, everything
learned during the session is lost.

For on-demand validation outside of `/log-session`, run `/validate-memory`
to check for missing entities and interactively create them.

### Next Session

```
DISK -> RAM
  |
  +-- search_nodes("CompletedTicket-{issue}") retrieves prior work
  +-- Session journals available via git for historical context
  +-- Updated procedural memory reflects any convention changes
```

The next agent session can retrieve what was learned. The knowledge graph
provides structured facts; session journals provide narrative context;
git history provides code-level detail.

---

## 4. Retrieval and Write Mechanics

### Keyword Search via Memory MCP

The `search_nodes` tool performs keyword matching against entity names and
observations. Effective retrieval depends on consistent naming conventions:

- Entity names use the format `{Type}-{identifier}` (e.g.,
  `CompletedTicket-141`, `Pattern-repository-pattern`)
- Observations should include searchable terms: issue numbers, file paths,
  technology names, pattern names
- Relations enable graph traversal: "find all tickets that depend on
  Feature X"

**Search example:**

```json
{
  "tool": "mcp__memory__search_nodes",
  "input": { "query": "authentication" }
}
```

Returns all entities with "authentication" in their name or observations.

### Explicit vs. Automatic Writes

| Write Type | Trigger | Example |
|------------|---------|---------|
| **Protocol-driven** | Agent policy mandates the write | Ticket Worker records CompletedTicket after merge |
| **Command-driven** | Slash command includes write step | `/log-session` creates a session journal |
| **Consolidation-driven** | `/log-session` step 5 proposes entities from PR diffs and reflection | LessonLearned or PatternDiscovered entities proposed after structured reflection |
| **Validation-driven** | `/validate-memory` or `/log-session` step 3 detects missing entities | Missing CompletedTicket entities created interactively |
| **Judgment-driven** | Agent decides knowledge is worth preserving | Ticket Worker records a PatternDiscovered when a reusable pattern emerges |

Protocol-driven and command-driven writes are reliable — they happen every
time. Consolidation-driven and validation-driven writes act as safety nets,
catching knowledge that would otherwise be lost. Judgment-driven writes
depend on the agent recognizing that something is worth recording. The
Memory Schema tables in agent policies provide guidance on what qualifies.

---

## 5. Known Gaps and Mitigations

| Gap | Status | Mitigation |
|-----|--------|------------|
| **Memory pruning** | Resolved | `/prune-memory` command with time-decay scoring: episodic entities >60d archived, semantic >90d flagged for review, <30d protected. User confirms before deletion. |
| **Post-session validation** | Resolved | `/log-session` step 3 validates CompletedTicket entities exist. `/validate-memory` available for on-demand checking and interactive entity creation. |
| **Keyword search only** | Open | Memory MCP uses exact keyword matching. Mitigated by consistent naming conventions (Section 2) and domain-prefixed entity names. Semantic search depends on future MCP server capabilities. |
| **Entity naming enforcement** | Resolved | Canonical naming convention table in Section 2 covers all 7 entity types. Agent policy files reference the table. Enforcement is advisory, not automated. |
| **Cross-session context paging** | Resolved | `/work-ticket` step 3 ("Load Context from Past Sessions") automatically queries for patterns, lessons, and completed tickets matching the current ticket's domain. Capped at 10 entities. |
| **Backward-move audit trail** | Resolved | PR reviewer posts `**Review result: NO-GO** (PR #N)` summary on the issue (not just PR). Ticket worker checks linked PR review comments before starting implementation on previously-reviewed tickets. |
| **Insight extraction** | Resolved | `/log-session` step 5 consolidation: reads PR diffs, applies structured reflection questions, proposes up to 5 LessonLearned/PatternDiscovered entities with user confirmation before writing. |

---

## 6. Extending the Memory System

For teams outgrowing the defaults:

**Add new entity types.** Define the entity type, naming convention, and
creation trigger in the relevant agent policy file. Follow the existing
Memory Schema table format.

**Add new relations.** Use `create_relations` to model domain-specific
connections. Document the relation types in agent policies so all agents
use consistent vocabulary.

**Increase retrieval quality.** Write observations with searchable
keywords. Use consistent naming conventions (see Section 2). Prune stale
entities periodically with `/prune-memory`.

**Monitor memory health.** Run `/prune-memory` weekly (included in the
`docs/MAINTENANCE.md` checklist) to review stale entities. Run
`/validate-memory` after sessions to verify CompletedTicket coverage.
Look for orphaned entities, inconsistent naming, and excessive observation
counts that may indicate redundant recording.

**Keep procedural memory lean.** The context engineering principles in
[CONTEXT-OPTIMIZATIONS.md](CONTEXT-OPTIMIZATIONS.md) apply to memory
architecture too. Every entity loaded into working memory competes for
attention. Store what cannot be rederived; reference what can.

---

## See Also

- [CONTEXT-OPTIMIZATIONS.md](CONTEXT-OPTIMIZATIONS.md) — Context
  engineering principles that inform memory design
- [AGENT-WORKFLOW-SUMMARY.md](AGENT-WORKFLOW-SUMMARY.md) — Complete agent
  workflow documentation
- [ARTIFACT-FLOW.md](ARTIFACT-FLOW.md) — How artifacts flow through the
  system
