---
name: commit
description: Create a conventional commit with proper formatting. Use when ready to commit staged changes following the project's commit standards.
---

# Conventional Commit Skill

Create a properly formatted commit following the [Conventional Commits](https://www.conventionalcommits.org/) specification.

## Commit Format

```text
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

## Allowed Types

| Type | When to Use |
|------|-------------|
| `feat` | Adding new functionality |
| `fix` | Fixing a bug |
| `docs` | Documentation changes only |
| `style` | Code formatting (no logic changes) |
| `refactor` | Restructuring code without changing behavior |
| `perf` | Performance improvements |
| `test` | Adding or updating tests |
| `build` | Build system or dependencies |
| `ci` | CI/CD configuration |
| `chore` | Maintenance tasks |
| `revert` | Reverting a previous commit |

## Scopes

| Scope | Description |
|-------|-------------|
| `api` | API endpoints |
| `auth` | Authentication and authorization |
| `db` | Database and migrations |
| `ui` | Frontend and templates |
| `agent` | Agent definitions |
| `skill` | Skills and commands |
| `ci` | CI/CD workflows |
| `safety` | Safety hooks and controls |
| `deps` | Dependencies |
| `config` | Configuration files |

## Rules

1. Subject line must be lowercase
1. No period at end of subject
1. Subject max 72 characters
1. Body lines max 100 characters
1. Reference issues with `Closes #123` or `Refs #123`

## Process

1. Run `git status` to see changes
1. Run `git diff --staged` to review staged changes
1. Determine type based on what changed
1. Determine scope from file paths
1. Write concise subject (what, not how)
1. Add body if changes need explanation
1. Add footer with issue references and co-author

## Example

```bash
git commit -m "$(cat <<'EOF'
feat(api): add health check endpoint

Returns JSON status for load balancer probes.

Closes #12

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

Now analyze the staged changes and create an appropriate conventional commit.
