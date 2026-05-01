# Agent Workflow Summary

Comprehensive reference for the Agile Flow agent-powered development workflow.

## Table of Contents

1. [Core Principles](#core-principles)
2. [The Three Agents](#the-three-agents)
3. [The Workflow](#the-workflow)
4. [Project Board Columns](#project-board-columns)
5. [Epic and Sub-Issue Structure](#epic-and-sub-issue-structure)
6. [Quality Gates](#quality-gates)
7. [Key Documents Reference](#key-documents-reference)
8. [MCP Servers](#mcp-servers)
9. [Slash Commands](#slash-commands)
10. [Complete Workflow Example](#complete-workflow-example)
11. [Troubleshooting](#troubleshooting)

---

## Core Principles

### 1. Separation of Duties

Each agent has distinct responsibilities with explicit boundaries:

| Agent | Responsibility | Cannot Do |
|-------|---------------|-----------|
| github-ticket-worker | Implementation | Merge PRs, move to Done |
| pr-reviewer | Code review | Merge PRs, move to Done |
| agile-backlog-prioritizer | Backlog grooming | Implementation, reviews |

This separation ensures no single agent can complete a change end-to-end without human oversight.

### 2. Human-in-the-Loop

Critical actions require human execution:

- **Merging PRs** - Only humans click the merge button
- **Moving to Done** - Only humans mark work complete
- **Production deployment** - Only humans approve releases
- **Token rotation** - Only humans manage credentials

Agents assist and recommend but never execute final decisions.

### 3. Defense in Depth

Multiple layers of protection prevent unauthorized actions:

```
Layer 1: Agent Instructions (NON-NEGOTIABLE PROTOCOL)
    ↓
Layer 2: Claude Code Settings (permission deny rules)
    ↓
Layer 3: GitHub Permissions (bot account restrictions)
    ↓
Layer 4: Branch Protection (ruleset enforcement)
    ↓
Layer 5: Audit Logging (detection and alerting)
```

If any layer fails, others still protect.

### 4. Observability

All agent actions are tracked and auditable:

- Git commits attributed to bot accounts
- PR comments show agent identity
- Weekly audit reports detect anomalies
- Verification tests ensure compliance

### 5. Fail-Safe Defaults

When in doubt, agents:

- Refuse rather than act
- Ask for human guidance
- Reference protocol restrictions
- Log the decision for audit

---

## The Three Agents

### github-ticket-worker

**Role**: Implementation agent that picks up tickets and writes code.

**Triggered by**: `/work-ticket` command

**Bot Account**: `{org}-worker`

**Capabilities**:

- Read tickets from Ready column
- Create feature branches
- Write code and tests
- Create pull requests
- Move tickets to In Progress and In Review

**Restrictions**:

- NEVER merge pull requests
- NEVER push directly to main
- NEVER move tickets to Done
- NEVER deploy to production

**Workflow Position**: Stage 1 of 3

### pr-reviewer

**Role**: Code review agent that evaluates PRs and provides recommendations.

**Triggered by**: `/review-pr` command

**Bot Account**: `{org}-reviewer`

**Capabilities**:

- Read PR content and diffs
- Analyze code quality
- Check test coverage
- Post review comments
- Provide GO/NO-GO recommendation

**Restrictions**:

- NEVER merge pull requests
- NEVER approve PRs (only comment)
- NEVER move tickets to Done
- NEVER close issues

**Workflow Position**: Stage 2 of 3

### agile-backlog-prioritizer

**Role**: Backlog management agent that prioritizes work.

**Triggered by**: `/groom-backlog` command

**Bot Account**: Uses human's account (read-only operations)

**Capabilities**:

- Read product requirements
- Analyze backlog health
- Prioritize using CD3
- Recommend tickets for Ready
- Identify stale or blocked items

**Restrictions**:

- Does not implement code
- Does not review PRs
- Does not merge or close

**Workflow Position**: Pre-work planning

---

## The Workflow

### Overview Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    THE THREE-STAGE WORKFLOW                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐          │
│  │   STAGE 1   │    │   STAGE 2   │    │   STAGE 3   │          │
│  │  Implement  │───>│   Review    │───>│    Merge    │          │
│  │             │    │             │    │             │          │
│  │  [Agent]    │    │  [Agent]    │    │  [Human]    │          │
│  │  worker     │    │  reviewer   │    │  only       │          │
│  └─────────────┘    └─────────────┘    └─────────────┘          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Phase 1: Backlog Grooming

**Command**: `/groom-backlog`

**Steps**:

1. Agent reads product requirements and roadmap
2. Agent analyzes current backlog health
3. Agent applies CD3 prioritization
4. Agent recommends tickets for Ready column
5. Human reviews and approves moves

**Outcome**: Ready column has 2-5 well-defined tickets

### Phase 2: Implementation

**Command**: `/work-ticket`

**Steps**:

1. Agent verifies active gh account (`gh auth status`); does NOT
   switch (#82). In multi-bot mode, the
   `.claude/hooks/ensure-github-account.sh` hook auto-switches to
   the worker account before `gh pr create`. In solo mode, the
   user's personal account is the active account throughout.
2. Agent picks top ticket from Ready column
3. Agent moves ticket to In Progress
4. Agent creates feature branch
5. Agent implements solution
6. Agent writes tests
7. Agent creates pull request
8. Agent moves ticket to In Review

**Outcome**: PR created, ticket in In Review

### Phase 3: Code Review

**Command**: `/review-pr`

**Steps**:

1. Agent verifies active gh account (`gh auth status`); does NOT
   switch (#82). In multi-bot mode, the hook auto-switches to the
   reviewer account before `gh pr review`. In solo mode, the user's
   personal account posts the review.
2. Agent reads PR and diffs
3. Agent analyzes code quality
4. Agent checks tests and coverage
5. Agent posts detailed review comment
6. Agent provides GO/NO-GO recommendation

**Outcome**: Review posted with recommendation

### Phase 4: Human Merge

**Executor**: Human only

**Steps**:

1. Human reviews agent's assessment
2. Human performs final review
3. Human approves PR
4. Human merges PR
5. Project board's "Item closed → Status: Done" workflow auto-moves
   the ticket (#86); in projects without that workflow enabled, the
   human moves the ticket manually

**Outcome**: Code merged, ticket complete

---

## Project Board Columns

### Icebox

**Purpose**: Ideas and features not yet prioritized

**Entry Criteria**:

- Feature request submitted
- Not aligned with current roadmap phase

**Exit Criteria**:

- Prioritized in grooming session
- Moves to Backlog

**WIP Limit**: None

### Backlog

**Purpose**: Prioritized work not yet ready for development

**Entry Criteria**:

- Aligned with product roadmap
- Has basic description

**Exit Criteria**:

- Meets Definition of Ready
- Moves to Ready

**WIP Limit**: None (prioritized order)

### Ready

**Purpose**: Well-defined tickets ready for implementation

**Entry Criteria**:

- Clear, specific title
- Detailed description
- Acceptance criteria defined
- Effort estimated
- No blockers

**Exit Criteria**:

- Picked up by `/work-ticket`
- Moves to In Progress

**WIP Limit**: 2-5 tickets

### In Progress

**Purpose**: Work currently being implemented

**Entry Criteria**:

- Picked up via `/work-ticket`
- Feature branch created

**Exit Criteria**:

- PR created
- Moves to In Review

**WIP Limit**: 1 per developer

### In Review

**Purpose**: PRs awaiting review and merge

**Entry Criteria**:

- PR created
- CI passing

**Exit Criteria**:

- Human merges PR
- Moves to Done

**WIP Limit**: 2-3 PRs

### Done

**Purpose**: Completed work

**Entry Criteria**:

- PR merged
- Ticket closed (by human)

**Exit Criteria**: None (archive after sprint)

**WIP Limit**: None

---

## Epic and Sub-Issue Structure

### Epic Definition

An epic is a large body of work broken into smaller issues:

```markdown
## [Epic] Feature Name

### Epic Overview
High-level description of the feature.

### Strategic Goal
Why this epic matters to the product.

### Sub-Issues
- [ ] #101 - First component
- [ ] #102 - Second component
- [ ] #103 - Integration

### Total Effort
Sum of sub-issue estimates.

### Dependencies
Other epics or external factors.

### Acceptance Criteria
Definition of epic completion.
```

### Sub-Issue Definition

Each sub-issue is independently deliverable:

```markdown
## Description
What needs to be done.

## Parent Epic
Part of Epic #100 - Feature Name

## Implementation
Technical approach and guidance.

## Acceptance Criteria
- [ ] Specific, testable criteria
- [ ] Another criterion

## Dependencies
- #99 (must be complete first)

## Effort Estimate
Time in hours.
```

### Linking Strategy

- Epic references all sub-issues in description
- Sub-issues reference parent epic
- Dependencies explicitly listed
- Closing sub-issues updates epic progress

---

## Quality Gates

### Definition of Ready

A ticket is ready for development when:

| Criterion | Description |
|-----------|-------------|
| Clear title | Specific, actionable title |
| Description | Context and background provided |
| Acceptance criteria | Specific, testable criteria listed |
| Effort estimate | Time estimate in hours |
| Priority label | P0/P1/P2/P3 assigned |
| No blockers | Dependencies resolved |
| Technical guidance | Implementation hints (if needed) |

### Definition of Done

A ticket is done when:

| Criterion | Description |
|-----------|-------------|
| Code complete | All acceptance criteria met |
| Tests written | Unit and integration tests |
| Tests passing | CI green |
| Code reviewed | PR reviewed by agent + human |
| PR merged | Human merged to main |
| Deployed | In target environment (if applicable) |
| Documented | README/docs updated (if needed) |
| Ticket closed | Human moved to Done |

---

## Key Documents Reference

### Project Configuration

| Document | Purpose |
|----------|---------|
| `CLAUDE.md` | Project instructions for Claude Code |
| `.claude/settings.json` | Permission settings and MCP config |

### Agent Policies

| Document | Purpose |
|----------|---------|
| `.claude/agents/github-ticket-worker.md` | Worker agent policy |
| `.claude/agents/pr-reviewer.md` | Reviewer agent policy |
| `.claude/agents/agile-backlog-prioritizer.md` | Prioritizer policy |

### Commands

| Document | Purpose |
|----------|---------|
| `.claude/commands/work-ticket.md` | Work ticket command |
| `.claude/commands/review-pr.md` | Review PR command |
| `.claude/commands/groom-backlog.md` | Groom backlog command |

### Product Documentation

| Document | Purpose |
|----------|---------|
| `docs/PRODUCT-REQUIREMENTS.md` | Product vision and features |
| `docs/PRODUCT-ROADMAP.md` | Phases and milestones |
| `docs/GETTING-STARTED.md` | Setup instructions |

### Operations

| Document | Purpose |
|----------|---------|
| `docs/MAINTENANCE.md` | Maintenance procedures |
| `docs/AGENT-ACTION-LOGGING.md` | Audit logging |
| `docs/testing/agent-restriction-tests.md` | Test documentation |

### Bot Configuration

| Document | Purpose |
|----------|---------|
| `.claude/README.md` | Bot account setup |
| `scripts/verify-bot-permissions.sh` | Permission verification |

---

## MCP Servers

Agents require three MCP servers: `github` (issues, PRs, project board),
`memory` (persistent context), and `sequential-thinking` (structured
reasoning). See [README.md > MCP Servers](../README.md#mcp-servers-required)
for setup instructions and the `.mcp.json` configuration.

---

## Slash Commands

### /work-ticket

**Purpose**: Pick up and implement next ticket from Ready.

**Usage**: `/work-ticket`

**What Happens**:

1. Launches github-ticket-worker agent
2. Agent verifies active gh account (does NOT switch — multi-bot
   switching is delegated to the PreToolUse hook for `gh pr create`)
3. Finds top ticket in Ready column
4. Creates feature branch
5. Implements solution
6. Creates PR
7. Moves ticket to In Review

### /review-pr

**Purpose**: Review PRs in In Review column.

**Usage**: `/review-pr`

**What Happens**:

1. Launches pr-reviewer agent
2. Agent verifies active gh account (does NOT switch — multi-bot
   switching is delegated to the PreToolUse hook for `gh pr review`)
3. Finds PRs awaiting review
4. Analyzes code quality
5. Posts detailed review
6. Provides GO/NO-GO recommendation

### /groom-backlog

**Purpose**: Prioritize backlog and populate Ready.

**Usage**: `/groom-backlog`

**What Happens**:

1. Launches agile-backlog-prioritizer agent
2. Reads product requirements
3. Analyzes backlog health
4. Applies CD3 prioritization
5. Recommends tickets for Ready
6. Reports backlog status

### /sprint-status

**Purpose**: Quick status check of board health.

**Usage**: `/sprint-status`

**What Happens**:

1. Counts tickets per column
2. Identifies stale items
3. Reports WIP violations
4. Suggests next actions

### /check-milestone

**Purpose**: Track progress toward a milestone.

**Usage**: `/check-milestone "MVP"`

**What Happens**:

1. Reads roadmap for milestone
2. Counts completed vs remaining
3. Calculates completion percentage
4. Identifies blockers

### /evaluate-feature

**Purpose**: Evaluate a feature request.

**Usage**: `/evaluate-feature "Dark mode support"`

**What Happens**:

1. Launches product manager agent
2. Evaluates strategic fit
3. Assesses ROI
4. Provides BUILD/DEFER/DECLINE recommendation

### /architect-review

**Purpose**: Get architectural guidance.

**Usage**: `/architect-review "How should we implement caching?"`

**What Happens**:

1. Launches system architect agent
2. Analyzes current architecture
3. Proposes solutions
4. Evaluates tradeoffs

---

## Complete Workflow Example

### Scenario: Implement User Authentication

#### Step 1: Feature Evaluation

```
Human: /evaluate-feature "Add user authentication"

Product Manager Agent:
- Strategic fit: HIGH (core MVP feature)
- User impact: HIGH (enables personalization)
- Technical risk: MEDIUM (well-understood patterns)
- Recommendation: BUILD
```

#### Step 2: Epic Creation

Human creates epic with sub-issues:

- Epic #50: User Authentication
  - #51: Create user model and database schema
  - #52: Implement registration flow
  - #53: Implement login flow
  - #54: Add session management
  - #55: Write integration tests

#### Step 3: Backlog Grooming

```
Human: /groom-backlog

Backlog Prioritizer Agent:
- Ready column: 1 item (low)
- Recommendation: Move #51 to Ready
- #51 meets Definition of Ready
- No blockers identified
```

#### Step 4: Implementation

```
Human: /work-ticket

Worker Agent (as va-worker):
- Picking up #51: Create user model
- Creating branch: feature/issue-51-user-model
- Moving ticket to In Progress
- [implements solution]
- Creating PR #60
- Moving ticket to In Review
```

#### Step 5: Code Review

```
Human: /review-pr

Reviewer Agent (as va-reviewer):
- Reviewing PR #60
- Code quality: GOOD
- Test coverage: 85%
- Security: No issues found
- Recommendation: GO

Review posted on PR #60.
```

#### Step 6: Human Merge

```
Human actions:
1. Reviews agent's assessment
2. Performs final review
3. Clicks "Approve"
4. Clicks "Squash and merge"
5. Moves #51 to Done
```

#### Step 7: Verification

```bash
# Run audit
./scripts/analyze-agent-actions.sh --since 1

# Output shows:
# - va-worker created PR #60
# - va-reviewer posted review
# - tck517 (human) merged PR
# - No restricted actions detected
```

---

## Troubleshooting

### Ready Column is Empty

**Symptom**: No tickets available for `/work-ticket`

**Solution**:

```
/groom-backlog
```

This will prioritize backlog and move tickets to Ready.

### PR Review Not Posted

**Symptom**: `/review-pr` runs but no comment appears

**Causes**:

1. Bot account token expired
2. Bot account lacks repo permissions
3. PR is draft or closed

**Solution**:

```bash
# Verify bot auth
gh auth switch --user {org}-reviewer
gh auth status

# Check token scopes
# Needs: repo, project, workflow, read:org
```

### Agent Uses Wrong Account

**Symptom**: Commits show wrong author

**Causes**:

1. `gh auth switch` not in agent policy
2. Bot account not configured

**Solution**:

1. Verify agent policy has account switch:

```markdown
## GitHub Account Identity

Before any action, switch to the correct bot account:
\`\`\`bash
gh auth switch --user {org}-worker
\`\`\`
```

1. Run permission verification:

```bash
./scripts/verify-bot-permissions.sh
```

### Branch Protection Bypass

**Symptom**: Direct push to main succeeded

**Causes**:

1. Ruleset not active
2. Bot has bypass permission
3. Ruleset misconfigured

**Solution**:

1. Check ruleset status:
   - Repository Settings > Rules > Rulesets
   - Verify "Active" status
   - Verify "main" branch target

2. Run verification:

```bash
./scripts/verify-agent-restrictions.sh
```

### Audit Report Shows Violations

**Symptom**: Weekly audit creates alert issue

**Causes**:

1. Agent policy drift
2. New agent without restrictions
3. Bypass attempt

**Solution**:

1. Review the audit report details
2. Run linter:

```bash
./scripts/lint-agent-policies.sh --verbose
```

1. Fix any violations found
1. Document incident

### Ticket Stuck in Progress

**Symptom**: Ticket hasn't moved for days

**Causes**:

1. Implementation blocked
2. Agent crashed mid-work
3. PR creation failed

**Solution**:

1. Check for open PR linked to ticket
2. Review agent conversation history
3. Manually move ticket if needed
4. Re-run `/work-ticket` if stuck

---

## Summary

The Agile Flow workflow provides:

1. **Automated implementation** via github-ticket-worker
2. **Automated review** via pr-reviewer
3. **Automated prioritization** via agile-backlog-prioritizer
4. **Human control** over merge and completion
5. **Defense in depth** through multiple protection layers
6. **Full observability** via audit logging

The key principle: **Agents assist, humans decide.**

For questions or issues, consult:

- This document for workflow guidance
- `docs/MAINTENANCE.md` for operational procedures
- `docs/testing/agent-restriction-tests.md` for verification
- `.claude/README.md` for bot setup
