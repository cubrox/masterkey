# Branching Strategy

This document explains why the Agile Flow template requires trunk-based
development and how the branching model keeps your project safe. It is
written for founders and builders who may be new to Git workflows.

---

## The Assembly Line vs. The Garage

Imagine you are building a car. You would not bolt a new carburetor
directly into the engine to see if it works. You would test the part on
a bench first — check that it fits, that fuel flows correctly, that
nothing leaks. Only after the part passes inspection do you install it
into the car.

Software works the same way:

| Car Factory | Software (Agile Flow) |
|-------------|----------------------|
| Test bench | **Feature branch** — an isolated workspace where you build and test one change |
| Component inspection | **CI checks** — automated tests that verify the change before it goes anywhere |
| Install verified part | **Merge to main** — the tested change becomes part of the official codebase |
| Car leaves the factory | **Production deploy** — the updated app goes live for users |

The key idea: **never install an untested part**. Every change is built
in isolation, verified automatically, reviewed by a person, and only
then added to the product.

---

## What Is Trunk-Based Development?

**Trunk-based development** is a way of organizing code changes around
one primary **branch** (a branch is a private copy of the codebase where
you can make changes without affecting anyone else).

The rules are simple:

1. There is one main branch called `main`. It always represents the
   latest verified version of your product.
2. When you (or an agent) want to make a change, you create a short-lived
   **feature branch** — a temporary workspace that branches off from
   `main`.
3. You make your changes on that feature branch, get them reviewed, and
   **merge** (combine) them back into `main` quickly — ideally the same
   day.
4. The feature branch is then deleted. It served its purpose.

```
main  ──●──────────●──────────●──────────●──  (always deployable)
         \        /  \        /
          ●──●──●      ●──●──●
          feature/     feature/
          add-login    fix-header
          (hours)      (hours)
```

The branches are short-lived — hours, not weeks. Each one adds a small,
focused change to `main`.

---

## Why Not Long-Lived Branches?

Some teams use a different approach: long-lived branches that run for
weeks or months before merging. This causes real problems:

### Merge conflicts

The longer a branch lives, the more it **diverges** (drifts apart) from
`main`. Other changes land on `main` while your branch is still going.
When you finally try to merge, the two versions may contradict each
other. Resolving these conflicts is time-consuming and error-prone.

### Integration risk

Two features that work perfectly in isolation may break when combined.
With long-lived branches, you do not find out until "merge day" — by
which point fixing the interaction is expensive.

### Stale reviews

A **pull request** (a proposal to merge your changes) with 2,000 changed
lines is nearly impossible to review meaningfully. Reviewers skim or
rubber-stamp it. Small PRs get careful attention.

### Delayed feedback

Bugs hide longer on a long-lived branch. The sooner code reaches `main`,
the sooner it gets tested in a real environment and seen by real users.
Fast feedback means faster fixes.

---

## Why It Matters Even More with AI Agents

Agentic coding — where AI agents write code on your behalf — amplifies
every problem with long-lived branches:

**Agents produce work fast.** An agent can open multiple pull requests
per day. If those PRs sat on long-lived branches, you would have an
unmanageable merge queue within a week.

**Agents do not carry memory across sessions.** Each time an agent picks
up a ticket, it reads the current state of `main` to understand the
project. A short-lived branch that merges the same day means `main`
always reflects reality. A long-lived branch means the agent is working
against a stale picture.

**Small PRs are reviewable; large ones are not.** The human-in-the-loop
review step is your primary safety gate. It only works if each PR is
small enough for you to actually read and understand. A 50-line PR takes
minutes to review. A 2,000-line PR? You will skip it — and that defeats
the purpose.

**Parallel work compounds conflicts.** If two agents work on long-lived
branches simultaneously, their changes diverge from each other *and* from
`main`. The merge conflicts multiply. Short-lived branches that merge
quickly avoid this entirely.

---

## How It Works in This Template

Here is the concrete flow when a ticket is worked in Agile Flow:

```
1. Agent picks up a ticket from the Ready column
   |
2. Agent creates a feature branch (feature/issue-12-add-login)
   |
3. Agent writes code and tests on that branch
   |
4. Agent pushes the branch --> CI runs automatically
   |                           (lint, tests, policy checks)
   |
5. Preview environment spins up (a live copy of the app with your change)
   |
6. Agent opens a pull request
   |
7. Reviewer agent posts GO / NO-GO recommendation
   |
8. Human reviews the PR (small, focused, understandable)
   |
9. Human merges --> code goes to production
   |
10. Branch is deleted. Ticket moves to Done.
```

The entire cycle — from ticket to production — happens in hours, not
weeks. The branch exists only as long as it needs to.

---

## The Safety Model

Each stage of the flow above is a **quality gate** — a checkpoint that
must pass before the change moves forward. Think of the carburetor
analogy: each gate is an inspection point before the part gets installed.

| Layer | What It Isolates | Analogy |
|-------|-----------------|---------|
| Feature branch | Code changes from the live product | The test bench |
| Pre-push hook | Catches errors before code leaves your machine | Checking the part before sending it to inspection |
| CI checks | Automated quality verification | The inspection station |
| Preview environment | User-facing testing in an isolated copy | Test-driving the car before shipping |
| Branch protection | Prevents untested code from reaching `main` | The locked gate to the assembly line |
| Human merge | The final decision to ship | The factory manager's sign-off |

No single layer is the whole story. Together, they ensure that every
change is built in isolation, tested automatically, reviewed by a human,
and only then added to the product. If any gate fails, the change does
not move forward — and `main` stays safe.

For the full technical breakdown of all eight control layers, see
[AGENTIC-CONTROLS.md](./AGENTIC-CONTROLS.md).

---

## Related Documentation

| Document | What It Covers |
|----------|---------------|
| [FAQ.md](./FAQ.md) | "Why can't I push to main?" and other common questions |
| [CONVENTIONAL-COMMITS.md](./CONVENTIONAL-COMMITS.md) | Why structured commit messages matter for agents and humans |
| [CI-CD-GUIDE.md](./CI-CD-GUIDE.md) | How CI workflows run, what they check, and how to fix failures |
| [EPHEMERAL-PR-ENVIRONMENTS.md](./EPHEMERAL-PR-ENVIRONMENTS.md) | How preview environments are created and destroyed per PR |
| [AGENTIC-CONTROLS.md](./AGENTIC-CONTROLS.md) | The eight layers of safety that govern agent behavior |
