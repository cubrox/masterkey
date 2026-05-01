# Agent Context Optimizations

This document describes the context engineering strategy behind this
project's agent configuration. It covers why these optimizations exist,
the failure modes they address, and the principles that guided the work.
For how these principles apply to agent memory and persistence, see
[MEMORY-ARCHITECTURE.md](MEMORY-ARCHITECTURE.md).

---

## Why Context Engineering Matters

"Vibe coding" — giving an LLM a loose prompt and iterating on the output —
works well for small, self-contained tasks. Write a function. Fix a bug.
Generate a test. The model has enough context to understand the task, and
the output is short enough that the human can verify it by reading.

Agentic development is different. The agent operates autonomously across
multi-step workflows: reading tickets, creating branches, writing code,
running tests, creating PRs, managing project boards. The context window
must hold not just the current task, but the rules governing how the agent
operates, the project conventions it must follow, the safety constraints
it cannot violate, and the accumulated knowledge from previous sessions.

This is where vibe coding breaks down. The context window is finite.
Everything you put into it competes for the model's attention. And the
model's attention is not uniform — it has well-documented failure modes
that produce hallucinations, rule violations, and quality degradation
when context is poorly managed.

---

## The Lost-in-the-Middle Problem

The most important concept in context engineering is **positional attention
bias**. Research on long-context LLMs (Liu et al., "Lost in the Middle,"
2023) demonstrated that models attend most strongly to information at the
**beginning** and **end** of their context window. Information in the
middle receives significantly less attention, even when it is explicitly
relevant to the task.

This has direct consequences for agentic development:

**Safety rules get buried.** A CLAUDE.md file that starts with project
description, then covers tech stack, then lists dependencies, and finally
mentions "never push to main" in section 7 — that rule is in the attention
dead zone. The agent will sometimes follow it, sometimes not.

**Duplicated content dilutes attention.** If the same conventional commit
format is described in CLAUDE.md, in the commit skill file, and in the
agent policy, the model must attend to three copies. This triples the
token cost and pushes other content further into the middle. (For why
conventional commits matter in the first place, see
[CONVENTIONAL-COMMITS.md](./CONVENTIONAL-COMMITS.md).)

**Long documents push instructions apart.** A 700+ line CLAUDE.md means
that the first instruction and the last instruction are separated by
thousands of tokens. Rules at the boundary get attention. Rules in the
interior get probabilistic attention.

---

## Why Vibe Coding Produces Hallucinations

Hallucinations in agentic systems follow predictable patterns:

### Missing Ground Truth

When an agent generates a response that requires factual data, it needs
that data in its context. If the data is absent or was pushed out by
lower-priority content, the model generates plausible-sounding text that
may be wrong.

### Instruction Interference

A system prompt with contradictory or overlapping instructions creates
ambiguity. The model resolves ambiguity by picking the interpretation that
best fits its training distribution — which may not be what you intended.
Clean, non-overlapping instructions produce deterministic behavior. Messy,
overlapping instructions produce probabilistic behavior.

### Context Window Exhaustion

Every agentic system has a hard limit on context window size. A bloated
system prompt directly reduces the working memory available for the actual
task — conversation history, tool results, and reasoning traces.

### Attention Competition

Even when all necessary information is present, each token competes for
attention. Reference material irrelevant to the current task still
consumes attention — the model must read it to determine it's irrelevant.

---

## Design Principles

### Principle 1: Minimize Base Context

Every token loaded into every session must earn its place. If content is
only relevant to a specific agent or command, it belongs in that agent's
file — not in CLAUDE.md.

### Principle 2: Front-Load Critical Information

The most important rules go in the first 15-20 lines, where positional
attention is strongest. Rules are numbered and visually distinct.

### Principle 3: One Canonical Location Per Fact

Every piece of information exists in exactly one place. Duplication wastes
tokens and creates drift when one copy is updated and the other isn't.

### Principle 4: Automate What Agents Forget

If an agent must remember an operational step (switch accounts, run tests),
that step should be automated via hooks. Every step the agent must remember
is a step it will sometimes forget.

### Principle 5: Treat Context Like a Budget

Context has a carrying cost (tokens), an attention cost (dilution), and a
maintenance cost (keeping content accurate). The question is not "could this
be useful?" but "is this worth the attention it will consume?"

---

## Optimizations Applied

### 1. CLAUDE.md Compaction

Reduce CLAUDE.md to a routing document. It contains only rules that apply
universally. Everything else lives in specialized files loaded on demand.

### 2. Critical Rules Front-Loading

Add a numbered critical rules section in the first 15 lines of CLAUDE.md.
These are the rules agents violate most frequently. Visual markers help the
model latch onto them.

### 3. TL;DR Blockquotes

Add one-line TL;DR summaries at the start of major sections. An agent can
read the TL;DR, decide relevance, and skip the details if not needed.

### 4. Reference Material Pattern

Split command files into tiers: critical rules (top), workflow steps
(middle), reference material (below separator). The agent encounters
critical rules first and consults reference material only when needed.

### 5. Skills as Context Isolation

Move reusable knowledge (commit formatting, test patterns) into
`.claude/skills/` files. Skills are loaded only when invoked, keeping
the base context lean.

### 6. PreToolUse Hook for Account Switching

Automate GitHub account switching via hook instead of relying on agent
memory. Frees context that would be spent on "did I switch accounts?"
reasoning traces.

### 7. Pre-Push Quality Gate

Run lint and tests locally before push. Prevents CI failure round trips
that waste agent context on error-fix loops.

### 8. Agent Policy Linting in CI

Scan agent policy files for safety instruction drift. Every PR that
touches agent files must pass the policy linter. Safety-critical phrases
cannot be removed without failing CI.

### 9. NON-NEGOTIABLE Protocol Positioning

Place NON-NEGOTIABLE PROTOCOL blocks at the very top of agent definitions
(immediately after metadata). Critical constraints must be in the
strongest attention zone — never buried in the middle or end.

### 10. Agent Deduplication

Remove content from agent definitions that duplicates CLAUDE.md. Agents
reference CLAUDE.md for shared rules instead of repeating them. Each
agent file contains only what is unique to that agent's role.

### 11. Clear Section Hierarchy

Organize agent definitions with a consistent structure: identity,
constraints, responsibilities, workflow, reference. The model can
navigate this structure predictably across all agents.

---

## Impact

| Default/Vibe Coding | This Framework |
|---------------------|----------------|
| CLAUDE.md is a knowledge dump | CLAUDE.md is a routing document |
| Rules scattered in prose | Critical rules in first 15 lines |
| Agent reads everything every time | TL;DR enables selective reading |
| Reference material in working context | Reference material below fold |
| Agent remembers to switch accounts | Hook switches automatically |
| Push then fix CI failures | Fail fast locally |
| Agent policies drift silently | CI linter catches policy drift |
| Same content in 3 files | One canonical location per fact |
