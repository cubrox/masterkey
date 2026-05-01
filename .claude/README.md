# Claude Code Configuration

This directory contains agent policies, slash commands, and settings for Claude Code projects using the Agile Flow template.

## Directory Structure

```
.claude/
├── agents/                    # Agent policy definitions
│   ├── github-ticket-worker.md
│   ├── pr-reviewer.md
│   ├── agile-backlog-prioritizer.md
│   └── ...
├── commands/                  # Slash command definitions
│   ├── work-ticket.md
│   ├── review-pr.md
│   ├── groom-backlog.md
│   └── ...
├── settings.local.json        # Local permissions (gitignored)
├── settings.template.json     # Template for permissions setup
└── README.md                  # This file
```

## Settings Configuration

The `settings.local.json` file controls what tools and permissions agents have access to. This file should be gitignored to allow for local customization.

### Creating Your Local Settings

If you don't have a `settings.local.json` file, copy the template:

```bash
cp .claude/settings.template.json .claude/settings.local.json
```

### IMPORTANT: Security Restrictions

The template intentionally **DENIES** `Bash(gh pr merge:*)`. This enforces the trunk-based development workflow where:

- Agents can **create** PRs via `gh pr create` (github-ticket-worker)
- Agents can **review** PRs via `gh pr review` (pr-reviewer)
- Only **humans** can **merge** PRs

This separation ensures quality control and prevents accidental merges.

### Allowed Agent Capabilities

Agents CAN:
- Create and update issues
- Move issues between project board columns
- Create pull requests
- Review pull requests (comment and provide recommendations)
- Run tests and builds
- Read repository files
- Use git for branching and committing

Agents CANNOT:
- Merge pull requests (human-only)
- Push directly to main branch (protected)
- Move tickets to Done column (human-only)
- Read secret files (.env, *.key, etc.)

## Bot Accounts (Optional — for Teams)

Dedicated bot accounts provide separation of concerns and a clear audit
trail. Solo developers can use their personal GitHub account for all
operations and skip this section.

### Recommended Setup

Create two bot accounts for your organization:

#### Worker Bot (e.g., `{org}-worker`)

**Purpose:** Creates code changes, branches, and pull requests

**Recommended Permissions (Classic PAT):**
- `repo` — full repository access (branches, PRs, issues)
- `project` — project board access (moving tickets between columns)

**Recommended Permissions (Fine-Grained PAT):**
- Contents: Read and write (for branches)
- Issues: Read and write
- Pull requests: Read and write
- Metadata: Read-only
- Projects: Read and write

**What the worker bot CAN do:**
- Create feature branches
- Push commits to feature branches
- Create pull requests
- Create and update issues
- Move issues to In Progress and In Review

**What the worker bot CANNOT do:**
- Push directly to main branch (blocked by branch protection)
- Merge pull requests (blocked by branch protection)
- Move issues to Done column (agent policy restriction)

#### Reviewer Bot (e.g., `{org}-reviewer`)

**Purpose:** Reviews pull requests and provides GO/NO-GO recommendations

**Recommended Permissions (Classic PAT):**
- `repo` — full repository access (PR reviews, approvals)
- `project` — project board access (reading ticket status)

**Recommended Permissions (Fine-Grained PAT):**
- Contents: Read-only
- Issues: Read and write
- Pull requests: Read and write
- Metadata: Read-only
- Projects: Read and write (required for approvals to count)

**What the reviewer bot CAN do:**
- Review pull requests
- Approve or request changes on PRs
- Comment on PRs and issues
- Read repository code

**What the reviewer bot CANNOT do:**
- Merge pull requests (agent policy restriction)
- Push to any branch
- Move issues to Done column (agent policy restriction)

### Human Workflow

The complete three-stage workflow:

```
1. Worker Bot creates feature branch and PR
         │
         ▼
2. Reviewer Bot reviews PR and provides GO/NO-GO recommendation
         │
         ▼
3. Human makes final approval decision and merges
```

This ensures:
- Bots can propose and review changes
- Humans maintain final control over merges
- Branch protection requirements are satisfied
- Clear audit trail of who did what

### PAT Storage

Bot PATs should be stored securely:

**Local Development:**
```bash
# Configure gh CLI with multiple accounts
gh auth login  # Login with your personal account
gh auth login  # Login with worker bot account
gh auth login  # Login with reviewer bot account

# Switch between accounts
gh auth switch --user {bot-username}

# Verify current account
gh auth status
```

**IMPORTANT Security Notes:**
- NEVER commit PATs to git
- NEVER log PATs in console output
- Set PAT expiration and rotate regularly
- If compromised, revoke immediately at https://github.com/settings/tokens

## Agent Policies

### github-ticket-worker

Implements tickets from the Ready column. Creates feature branches and PRs.

**Key Restrictions:**
- Can only work on tickets in Ready column
- Must create feature branches (no direct main commits)
- Cannot merge PRs
- Cannot move tickets to Done

### pr-reviewer

Reviews PRs and provides decision support for human reviewers.

**Key Restrictions:**
- Cannot review its own code
- Cannot merge PRs (provides recommendations only)
- Cannot move tickets to Done

### agile-backlog-prioritizer

Manages the product backlog and populates the Ready column.

**Key Restrictions:**
- Cannot implement tickets (only prioritizes)
- Cannot merge PRs

## Troubleshooting

**Q: Why can't agents merge PRs?**
A: This is intentional. The workflow requires human review and approval before code reaches the main branch. This is a safety feature, not a bug.

**Q: My settings.local.json is missing**
A: Copy from template: `cp .claude/settings.template.json .claude/settings.local.json`

**Q: Agent says it can't access the repository**
A: Verify the bot account is properly configured:
```bash
gh auth status
gh auth switch --user {bot-username}
gh repo view {owner}/{repo}
```

**Q: PRs aren't being attributed to the bot account**
A: Make sure to switch accounts before agent operations:
```bash
gh auth switch --user {bot-username}
```

**Q: Branch protection is blocking bot pushes**
A: Ensure the bot account has Write access to the repository and branch protection allows the bot to push to feature branches (not main).

## Related Documentation

- Main project configuration: `../CLAUDE.md`
- Getting started guide: `../docs/GETTING-STARTED.md`
