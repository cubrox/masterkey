# Agentic Development Controls

This document describes the layered control structure that governs how AI agents
operate within this repository. Each control mitigates a specific class of risk
introduced by agentic development, where autonomous AI agents write code, create
pull requests, post reviews, and manage project boards.

---

## Why Controls Matter

When agents operate autonomously, the failure modes are different from human
development. An agent does not get tired, but it also does not pause to question
whether an instruction makes sense. It will merge a PR if told to. It will push
directly to main if the path is open. It will commit `.env` files if nothing
stops it.

The controls below are organized from the **outermost boundary** (platform-level
enforcement) to the **innermost** (runtime application guardrails), forming a
defense-in-depth architecture where no single control is sufficient on its own,
but together they create overlapping safety zones.

---

## Layer 1: Platform Enforcement

These controls are enforced by GitHub and cannot be bypassed by agents or code.

### Branch Protection on `main`

**What it does**: Requires pull request reviews and passing status checks before
any code can be merged to `main`. Direct pushes are blocked.

**Why it matters**: This is the single most important control. Everything else
can be worked around if an agent can push directly to the production branch.
Branch protection is the hard boundary that forces all changes through the
review pipeline.

**Configuration**: GitHub repository settings, cannot be modified by agents.

### Account Separation

| Account | Role | Permissions |
|---------|------|-------------|
| Human operator | Full org admin, merge authority | Admin |
| Worker bot | Commits, PRs, board ops | Scoped PAT |
| Reviewer bot | PR reviews only, no board scopes | Scoped PAT |

**Why it matters**: Separation of duties. The worker cannot review its own PRs.
The reviewer cannot merge. Neither bot can perform admin operations. If one
token is compromised, the blast radius is limited to that account's permissions.

**How it works**: Each account has its own GitHub PAT with scoped permissions.
The `gh auth switch` command selects the active account. A pre-tool-use hook
(`.claude/hooks/ensure-github-account.sh`) automatically switches to the
correct account before PR operations.

---

## Layer 2: Claude Code Permission Boundaries

Claude Code enforces tool-level access control through
`.claude/settings.template.json`.

### Explicit Deny Rules

```json
"deny": [
  "Read(.env)",
  "Read(.env.*)",
  "Read(*.key)",
  "Read(*credentials*)",
  "Read(*secret*)",
  "Write(.env)",
  "Write(.env.*)",
  "Bash(gh pr merge:*)"
]
```

**What each rule prevents**:

- **Secret file access**: Agents cannot read or write `.env`, credential files,
  or key files. This prevents accidental exposure of API keys, database URLs,
  and other secrets in commits, PR descriptions, or log output.

- **Merge prohibition**: The `Bash(gh pr merge:*)` pattern is denied at the
  framework level. Even if an agent's instructions say "merge", the platform
  will block the `gh pr merge` command. This is the hard enforcement behind
  the "only humans merge" rule.

**Why deny rules beat allow rules**: An allow-list can have gaps. A deny rule
on merge is explicit and survives any future changes to the allow list.

### Scoped Allow Rules

The allow list explicitly enumerates which bash commands, web domains, and MCP
tools agents may use. Commands not on the list require human approval. This
prevents agents from running arbitrary shell commands or accessing unauthorized
services.

---

## Layer 3: Agent Policy Controls

These controls are embedded in agent definition files (`.claude/agents/*.md`)
and enforce behavioral rules through system prompts.

### NON-NEGOTIABLE PROTOCOL Blocks

Both critical workflow agents (`github-ticket-worker` and `pr-reviewer`) contain
a `NON-NEGOTIABLE PROTOCOL` section that defines absolute restrictions:

**github-ticket-worker**:

1. NEVER merge pull requests
1. NEVER move tickets to "Done" column
1. NEVER push directly to main branch
1. ONLY work on tickets in "Ready" or "In Progress" columns
1. If asked to violate, MUST refuse and remind user

**pr-reviewer**:

1. NEVER merge pull requests or click "Merge" button
1. NEVER click GitHub "Approve" button (written GO/NO-GO only)
1. NEVER move tickets to "Done" column
1. NEVER deploy to production or trigger production workflows
1. Human reviewer ALWAYS performs final GitHub approval and merge
1. If forced to choose between protocol and speed, ALWAYS choose protocol

**Why this matters**: Prompt-level restrictions are softer than platform
enforcement, but they handle nuanced cases that deny rules cannot. For example,
the "if forced to choose between protocol and speed" instruction addresses the
specific failure mode where a user pressures the agent to skip steps.

### Three-Stage Workflow Enforcement

The development workflow is partitioned across three actors with non-overlapping
authority:

```text
Worker (bot)          Reviewer (bot)         Human
     |                      |                    |
  Implement            Review code          Final review
  Create PR            GO / NO-GO           Approve
  Move to In Review    Request changes       Merge
     |                      |                    |
     X cannot review        X cannot merge       X doesn't write code
     X cannot merge         X cannot move board
     X cannot mark Done     X cannot deploy
```

No single actor can take a change from inception to production. This is the
agentic equivalent of the two-person rule in security-critical systems.

---

## Layer 4: CI/CD Verification Pipeline

These controls run automatically on every pull request and block merging when
they fail.

### CI Workflow (`.github/workflows/ci.yml`)

Every PR must pass these checks:

| Check | What It Validates |
|-------|-------------------|
| Markdown lint | Documentation quality and formatting |
| JSON validation | Configuration file integrity |
| Shell script validation | Shellcheck on all `.sh` files |
| Command file validation | Slash command structure and required fields |
| Agent file validation | Agent definition structure |
| Agent policy lint | Safety protocol presence and correctness |

### Agent Policy Linter (`scripts/lint-agent-policies.sh`)

This CI check specifically guards against **instruction drift** — the gradual
erosion of safety rules through incremental edits. It scans agent definition
files for:

**Error conditions (block merge)**:

- "and merge" instructions in `pr-reviewer` (unless in "human...and merge"
  context)
- "move to Done" instructions without negation ("NEVER", "cannot", "do not")
- "close the issue" instructions without negation
- "push to main" instructions without negation
- Missing `NON-NEGOTIABLE PROTOCOL` blocks
- Missing "NEVER merge" statements

**Warning conditions (flag but allow merge)**:

- Missing "human" context in merge/approval discussions
- Missing bot account identity instructions
- Incomplete three-stage workflow descriptions

**Why this is critical**: Without this linter, a well-intentioned edit to
simplify an agent file could accidentally remove a safety instruction. The
linter ensures that the removal of any safety-critical phrase is a CI-failing
event that requires conscious override.

---

## Layer 5: Pre-Push Local Verification

Before code even reaches GitHub, the local pre-push hook
(`scripts/hooks/pre-push`) runs lint and test checks appropriate to the
detected language stack (Python, Node.js, or Go).

**Why local enforcement matters**: CI runs cost time and compute. A failing push
wastes minutes of CI and creates noise in PR check status. The pre-push hook
catches failures locally before they waste shared resources.

The hook is enabled via `git config core.hooksPath scripts/hooks`. The
`--no-verify` bypass is explicitly forbidden in CLAUDE.md.

---

## Layer 6: Automated Auditing

These controls don't prevent actions — they detect and alert when something
goes wrong.

### Weekly Restriction Verification

**Schedule**: Every Sunday at 00:00 UTC
**Workflow**: `.github/workflows/verify-agent-restrictions.yml`
**Script**: `scripts/verify-agent-restrictions.sh`

Runs 10 tests across 3 categories:

**Protocol Compliance (5 tests)**:

- NON-NEGOTIABLE PROTOCOL blocks present in workflow agents
- PR reviewer has "NEVER merge" statement
- Review command documents merge prohibition
- Ticket worker prohibits Done column moves
- Ticket worker prohibits main branch pushes

**Permission Enforcement (2 tests)**:

- Branch protection is active on `main`
- Settings template has merge deny rule

**Documentation (3 tests)**:

- Bot account documentation exists
- Workflow documentation exists
- Test scenario documentation exists

**On failure**: Automatically creates a GitHub issue with `[ALERT]` prefix
and `safety`, `security`, `audit` labels. Reports are retained for 90 days
as workflow artifacts.

### Weekly Action Audit

**Schedule**: Every Monday at 09:00 UTC
**Workflow**: `.github/workflows/agent-audit-report.yml`
**Script**: `scripts/analyze-agent-actions.sh`

Analyzes the previous 7 days of activity for restricted action attempts:

| Restricted Action | Detection Method |
|-------------------|------------------|
| Bot merging a PR | `mergedBy` field in PR data matches bot account |
| Direct push to `main` | Git log shows bot commit on main branch |
| Production deployment | Workflow run matches deploy-production pattern |
| Move to Done column | Project board event analysis |

**On violation**: Automatically creates a GitHub issue with investigation
steps. Reports are retained for 90 days.

**Why audit matters even with prevention**: Prevention controls can have bugs.
Branch protection can be temporarily disabled by an admin. A new MCP tool
might not be covered by deny rules. The audit layer provides a safety net
that detects what the prevention layer misses.

---

## Layer 7: Runtime Application Guardrails

These controls operate at the application level, protecting interactions with
end users. They are application-specific and should be implemented as the
product matures.

Examples of runtime guardrails:

- **Input guards**: Validate inbound messages for prompt injection, PII,
  spam, inappropriate content, and off-topic requests.
- **Output guards**: Validate AI-generated responses for brand voice
  compliance, factual accuracy, length limits, and secret exposure.
- **Conversation evaluators**: Score conversations across quality dimensions
  and alert on degradation.

The starter app does not include runtime guardrails out of the box. Implement
them as your application's requirements become clear.

---

## Layer 8: Observability and Incident Response

### Sentry Integration

The starter app includes Sentry SDK integration for error tracking. When
configured with the Sentry GitHub integration, exceptions automatically create
GitHub issues, closing the loop between runtime errors and the project board.

### Alerting (Application-Specific)

As the application matures, implement alerting for:

- High error rates
- High latency (p95)
- Service downtime during business hours
- Queue backlogs

### Incident Runbooks

Pre-written response procedures for common failure scenarios reduce
mean-time-to-recovery. Create runbooks in `docs/runbooks/` as the application's
operational surface grows.

---

## How the Layers Interact

The controls are designed so that each layer compensates for the weaknesses
of the others:

```text
Layer 1 (Platform)     Hard boundary. Cannot be bypassed by agents.
                       Weakness: Only covers merge and push operations.
    |
Layer 2 (Deny Rules)   Extends platform controls to secrets and specific commands.
                       Weakness: Only covers enumerated patterns.
    |
Layer 3 (Agent Policy) Covers nuanced behavioral rules and edge cases.
                       Weakness: Soft enforcement (prompt-based).
    |
Layer 4 (CI/CD)        Verifies agent policies haven't drifted.
                       Weakness: Only runs on PR creation.
    |
Layer 5 (Pre-Push)     Catches failures before they reach CI.
                       Weakness: Can be bypassed with --no-verify.
    |
Layer 6 (Audit)        Detects violations that prevention missed.
                       Weakness: Retrospective, not preventive.
    |
Layer 7 (Runtime)      Protects end-user interactions.
                       Weakness: AI-based detection is probabilistic.
    |
Layer 8 (Observability) Detects system-level degradation.
                       Weakness: Alerting requires monitoring infra to be healthy.
```

The key insight is that **Layer 3 (agent policies) would be dangerously
insufficient alone**. An agent following prompt instructions is only as
reliable as its attention to those instructions under adversarial or
confusing conditions. The surrounding layers ensure that even if the agent
ignores or misinterprets a policy, the platform, CI, and audit systems
catch the violation.

Similarly, **Layer 1 (platform enforcement) alone is too coarse**. Branch
protection prevents direct pushes and unreviewed merges, but it cannot
enforce code quality, brand voice compliance, or proper ticket workflow.
The inner layers handle what the platform cannot.

---

## Summary

| Layer | Controls | Enforcement | Timing |
|-------|----------|-------------|--------|
| 1. Platform | Branch protection, account separation | Hard (GitHub) | Always |
| 2. Deny Rules | Secret access block, merge block | Hard (framework) | Tool invocation |
| 3. Agent Policy | NON-NEGOTIABLE PROTOCOL, three-stage workflow | Soft (prompt) | Agent execution |
| 4. CI/CD | Policy linter, tests, coverage | Hard (blocks merge) | Every PR |
| 5. Pre-Push | Lint, tests (language auto-detected) | Hard (blocks push) | Every push |
| 6. Audit | Restriction verification, action audit | Detective (alerts) | Weekly |
| 7. Runtime | Input/output guards, evaluator | Automated (per-message) | Per interaction |
| 8. Observability | Sentry, metrics, alerts, runbooks | Detective (alerts) | Continuous |
