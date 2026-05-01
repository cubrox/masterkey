# Conventional Commits

This document explains what conventional commits are, why this template
requires them, and how they help both humans and AI agents work more
effectively. It is written for founders and builders who may not have
used structured commit messages before.

---

## What Is a Commit Message?

Every time you (or an agent) save a set of changes to the codebase, Git
records a **commit** — a snapshot of what changed, when, and by whom.
Each commit has a short message describing the change. Think of it like
a label on a shipping box: it tells you what is inside without opening
it.

A vague label is not helpful:

```
fixed stuff
updates
wip
```

You cannot tell what changed, why, or whether it matters. Now imagine
reading 50 of these in a row — that is what an unstructured Git history
looks like.

---

## The Conventional Commits Format

**Conventional commits** are a simple naming convention that makes every
commit message follow the same structure:

```
<type>(<scope>): <subject>
```

| Part | What It Means | Example |
|------|--------------|---------|
| **type** | The *kind* of change | `feat`, `fix`, `docs` |
| **scope** | The *area* of the project affected | `auth`, `api`, `ui` |
| **subject** | A short description of *what* changed | `add login endpoint` |

Put together, a commit message looks like this:

```
feat(auth): add login endpoint
```

You can read this as: "This is a new **feature** in the **auth** area
that **adds a login endpoint**."

---

## Common Types

| Type | What It Means | Everyday Analogy |
|------|--------------|-----------------|
| `feat` | A new feature was added | Adding a new room to a house |
| `fix` | A bug was fixed | Fixing a leaky faucet |
| `docs` | Only documentation changed | Updating the instruction manual |
| `refactor` | Code was reorganized without changing behavior | Rearranging furniture — same room, better layout |
| `test` | Tests were added or updated | Adding a checklist to verify the faucet works |
| `build` | Build system or dependencies changed | Upgrading your tools |
| `ci` | CI/CD workflows changed | Adjusting the factory inspection process |
| `style` | Code formatting changed (no logic) | Fixing typos in the manual |
| `chore` | Maintenance work | Cleaning the garage |

For the full list of types and scopes used in this project, see
`.claude/skills/commit.md`.

---

## Why This Matters

### You can scan the history at a glance

Compare these two Git logs:

**Without conventional commits:**

```
fixed stuff
update login
more changes
tweaks
bugfix
```

**With conventional commits:**

```
feat(auth): add login endpoint
fix(auth): handle expired tokens
test(auth): add token expiration tests
docs(api): update endpoint reference
fix(ui): correct button alignment on mobile
```

The second log tells you exactly what happened. You can see that three
changes touched authentication, one updated documentation, and one fixed
a UI issue — without reading any code.

### Agents get better context

When an AI agent starts a new session, it reads the recent Git history
to understand what has been built and what has changed. Structured
commit messages give the agent a clear summary. Vague messages force
the agent to read the actual code to figure out what happened, which
wastes context window space and slows things down.

### Reviewers know what to expect

The commit type signals intent. A `refactor` should not change behavior
— if the reviewer sees new functionality in a refactor commit, something
is wrong. A `fix` should be small and targeted. A `feat` should come
with tests. The type sets expectations before the reviewer reads a
single line of code.

### Automated changelogs and releases

Tools can generate changelogs automatically from conventional commits.
The Agile Flow template's release workflow (`release.yml`) already uses
`CHANGELOG.md` alongside commit types. Structured commits make it
possible to answer "what shipped in this release?" without manual
work.

### Faster debugging

When something breaks, you need to find which change caused it. Git can
narrow down the culprit to a specific commit. A message like
`fix(api): validate input on /users endpoint` tells you immediately
whether that commit is relevant to your bug. A message like `updates`
tells you nothing.

---

## How It Works in This Template

You do not need to memorize the format. The project handles it for you:

1. **Agents follow it automatically.** The commit skill
   (`.claude/skills/commit.md`) teaches agents the format. When an agent
   commits code, it produces a conventional commit message.

2. **CLAUDE.md enforces it.** Rule 3 in the critical rules section
   requires conventional commits for all changes.

3. **You just need to recognize it.** When reviewing a pull request, the
   commit messages tell you what kind of change each commit represents.

If you are making a commit manually, here is the pattern:

```bash
git commit -m "feat(auth): add login endpoint"
```

Pick the type from the table above, add the scope (the area you
changed), and write a short description. Lowercase, no period at the
end, under 72 characters.

---

## Related Documentation

| Document | What It Covers |
|----------|---------------|
| [BRANCHING-STRATEGY.md](./BRANCHING-STRATEGY.md) | Why we use trunk-based development and short-lived branches |
| [CONTEXT-OPTIMIZATIONS.md](./CONTEXT-OPTIMIZATIONS.md) | How structured information helps agents work more effectively |
| [CI-CD-GUIDE.md](./CI-CD-GUIDE.md) | How CI checks and automated workflows use commit data |
