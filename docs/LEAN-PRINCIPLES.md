# Lean Principles in Agile Flow

Agile Flow is a waste elimination system. Every agent, command, hook, and
workflow constraint exists to close a specific leak in the software delivery
pipeline. The leaks are not new — they are the seven wastes identified by
Toyota's lean manufacturing system, translated for software delivery by
Mary and Tom Poppendieck.

Writing code is not the same thing as shipping product. When agents write
code, the distinction sharpens: code generation throughput is irrelevant.
What matters is throughput of **value to the customer**. Every waste below
is a way that code generation decouples from value delivery.

## The Seven Wastes

| Manufacturing Waste | Software Waste | Agile Flow Countermeasure |
|---------------------|----------------|--------------------------|
| Inventory | Partially Done Work | Pull system, WIP limits, one-ticket-at-a-time |
| Overproduction | Extra Features | PM/PO gate, scope lock, feature evaluation |
| Extra Processing | Relearning | Memory MCP, 4 Power Sections, session journals |
| Transportation | Handoffs | Structured interfaces, review templates, account hooks |
| Waiting | Delays | Pull-based Ready column, CI auto-fix, bot accounts |
| Motion | Task Switching | Single-piece flow, focused agent sessions |
| Defects | Defects | Shift-left testing, red flags, CI gates, pre-push hooks |

## Detailed Mapping

### 1. Inventory → Partially Done Work

**The waste:** Unfinished code, features, or documentation sitting idle.
Work-in-progress that is not yet deployable ties up resources and risks
obsolescence before delivery.

**How it amplifies with agents:** An unsupervised agent can churn out
half-finished PRs faster than humans can review them. Without constraints,
you accumulate inventory at machine speed.

**Agile Flow countermeasures:**

| Practice | How it helps |
|----------|-------------|
| Ready column cap (2-5 items) | Limits work entering the system |
| One ticket at a time | Worker agent completes before starting new work |
| Worker → Reviewer → Human pipeline | Work flows through stages; it does not accumulate |
| `/sprint-status` stale item detection | Surfaces idle work-in-progress |
| Short-lived feature branches | Forces completion — branches do not linger |

**Lean principle:** This is a **pull system**. Work is pulled into each
stage only when capacity exists. The Ready column is the kanban signal.

---

### 2. Overproduction → Extra Features

**The waste:** Building functionality that users do not need. "Gold-plating"
increases complexity and maintenance costs without delivering value.

**How it amplifies with agents:** Agents are eager to please. Ask an agent
to build a login page and it will add OAuth, magic links, biometric auth,
and a password strength meter — none of which were requested. Overproduction
is the default mode for generative AI.

**Agile Flow countermeasures:**

| Practice | How it helps |
|----------|-------------|
| Product Manager gates what gets built | BUILD / DEFER / DECLINE evaluation |
| Product Owner gates what is ready to build | Definition of Ready enforces scope |
| `/lock-scope` | Formalizes the MVP boundary |
| `/evaluate-feature` | Forces a business case before code exists |
| Acceptance criteria in tickets | Agent implements *what is specified*, not what it imagines |
| PR Reviewer red flags | Catches scope creep during review |

**Lean principle:** **Build only what is pulled by the customer.** The PM
represents the customer. The PO translates demand into executable work.
Nothing enters the system without passing both gates.

---

### 3. Extra Processing → Relearning

**The waste:** Rediscovering knowledge that was previously known but poorly
documented. Performing unnecessary steps that do not contribute to the end
product.

**How it amplifies with agents:** Every agent session starts with an empty
context window. Without institutional memory, the agent re-reads the same
files, re-discovers the same patterns, and makes the same mistakes —
every single time. Relearning waste becomes *catastrophic* at agent speed
because the agent does not know what it does not know.

**Agile Flow countermeasures:**

| Practice | How it helps |
|----------|-------------|
| Memory MCP entities | `CompletedTicket`, `PatternDiscovered`, `LessonLearned` persist across sessions |
| 4 Power Sections in tickets | Front-loads context so the agent does not rediscover it |
| `/log-session` | Captures institutional knowledge after each work session |
| Progressive refinement (bootstrap phases) | Builds cumulative context that compounds |
| CLAUDE.md and agent configs | Persistent project context loaded every session |
| Conventional commits | Scannable history — no need to re-read code to understand what changed |

**Lean principle:** **Preserve knowledge.** If you learn something, write
it down where the next worker (human or agent) will find it. The cost of
documentation is paid once. The cost of relearning is paid every session.

---

### 4. Transportation → Handoffs

**The waste:** Passing work between teams or individuals. Each handoff
introduces delay, miscommunication, and context loss.

**How it amplifies with agents:** Agent-to-agent handoffs are fragile.
Context windows do not transfer. If the worker agent's implementation
intent is not captured in the PR description, the reviewer agent
reviews blind.

**Agile Flow countermeasures:**

| Practice | How it helps |
|----------|-------------|
| Structured PR template | Standardized interface between worker and reviewer |
| GO/NO-GO review format | Standardized interface between reviewer and human |
| Ticket format (4 Power Sections) | Standardized interface between PO and worker |
| `ensure-github-account.sh` hook | Automates identity switching at handoff boundaries |
| Issue-to-PR linking | Traceability from requirement to implementation |
| Board column transitions | Visible handoff state (Ready → In Progress → In Review) |

**Lean principle:** **Standardize handoff interfaces.** You cannot
eliminate handoffs in a review-gated workflow, but you can make each
handoff lossless by defining the contract. The three-stage workflow
(worker → reviewer → human) has *more* handoffs than "just push to main,"
but each handoff is structured to preserve context. Unstructured handoffs
are far more wasteful.

---

### 5. Waiting → Delays

**The waste:** Time lost waiting for approvals, feedback, dependencies,
or resources.

**How it amplifies with agents:** Agents work fast but block on human
decisions. A PR that sits unreviewed for two days wasted the agent's
speed advantage entirely. The bottleneck shifts from code production to
human review bandwidth.

**Agile Flow countermeasures:**

| Practice | How it helps |
|----------|-------------|
| Ready column always stocked (2-5 items) | Worker never waits for work to be defined |
| CI auto-fix protocol (up to 3 retries) | Agent does not wait for human to fix lint errors |
| Bot accounts | No waiting for human to switch contexts to do routine GitHub operations |
| PR reviewer agent | Review starts immediately, not when a human has time |
| `/sprint-status` wait detection | Surfaces items stuck in review too long |
| Branch protection with automated checks | CI runs without human initiation |

**Lean principle:** **Eliminate waiting by making the next step available
immediately.** The pull system ensures work is always ready. The reviewer
agent reduces the review wait. The human's role is scoped to the final
merge decision — the highest-value, lowest-frequency step.

---

### 6. Motion → Task Switching

**The waste:** Frequent context switching between tasks. Mental overhead
of ramping up on different work items reduces focus and productivity.

**How it amplifies with agents:** Context windows are finite. Switching
tasks means losing context, which means relearning (waste #3). An agent
that juggles three tickets simultaneously will do all three poorly.

**Agile Flow countermeasures:**

| Practice | How it helps |
|----------|-------------|
| One ticket at a time | Single-piece flow — complete before starting new work |
| Agent role specialization | Each agent does one type of work (build, review, prioritize) |
| Focused slash commands | `/work-ticket` does exactly one thing |
| Ticket scoping heuristics | Tickets scoped to single-PR, single-session work |
| "No parallel work" rule | Explicit policy in worker agent |

**Lean principle:** **Single-piece flow.** One unit of work moves through
the entire value stream before the next unit begins. This minimizes
work-in-progress (waste #1) and context switching (waste #6)
simultaneously.

---

### 7. Defects → Defects

**The waste:** Bugs that require rework, testing, and fixes after the
fact.

**How it amplifies with agents:** Agents produce plausible-looking code
that may be subtly wrong. They do not feel uncertainty — they generate
with equal confidence whether the code is correct or hallucinated.
Defect generation can outpace defect detection unless the system is
designed to prevent it.

**Agile Flow countermeasures:**

| Practice | How it helps |
|----------|-------------|
| Quality engineer agent | BDD test plans catch defects before they are built |
| PR reviewer red flags | Automatic NO-GO for security vulnerabilities, failing tests, missing coverage |
| Pre-push hooks | Defects caught before code leaves the developer's machine |
| CI gates | Automated verification before human review |
| "Never merge with failing tests" rule | Hard gate — no exceptions |
| `/test-feature` command | Shift-left testing with Given-When-Then scenarios |
| Conventional commits | Atomic changes make defect isolation easier |
| Error receiver (auto bug filing) | Production defects create tickets automatically |

**Lean principle:** **Build quality in.** Do not inspect quality after the
fact — prevent defects at the source. Every gate in the pipeline exists to
catch defects closer to where they were introduced, when the cost of
fixing them is lowest.

---

## The System View

Individual practices are not the point. The *system* is the point.

```
    ┌─────────────────── PULL SYSTEM ─────────────────────┐
    │                                                     │
    │  Backlog → Ready → In Progress → In Review → Done   │
    │           (2-5)    (1 at a time)  (structured)      │
    │             ↑           ↑             ↑             │
    │          PO gate    Worker agent  Reviewer agent    │
    │          (scope)    (single-piece) (quality)        │
    │             ↑                                       │
    │          PM gate                                    │
    │          (value)                                    │
    └─────────────────────────────────────────────────────┘
```

Each waste is addressed not by a single practice but by the interaction
of multiple practices:

- **Scope lock** (overproduction) + **Definition of Ready** (relearning) +
  **one ticket at a time** (motion) = only well-defined, valuable work
  enters the system, one piece at a time.

- **Structured PR template** (handoffs) + **CI gates** (defects) +
  **reviewer agent** (waiting) = handoffs are fast, lossless, and
  quality-verified.

- **Memory MCP** (relearning) + **session journals** (relearning) +
  **progressive refinement** (relearning) = institutional knowledge
  compounds instead of evaporating.

## Why This Matters for Agentic Development

Vibe coding optimizes for code generation throughput — how fast can I
produce code. Lean says throughput of code is irrelevant; what matters
is throughput of value to the customer.

Agents amplify everything. They amplify productivity, but they also
amplify waste. An agent that builds extra features builds them faster.
An agent that produces defects produces them faster. An agent that
creates partially done work creates it faster.

Without a waste elimination system, agents are a force multiplier on
your existing dysfunction. With one, they are a force multiplier on
your delivery capability.

The seven wastes do not change because agents are writing code. In
most cases, the risk from waste *increases*. Lean software delivery
is not a nice-to-have for agentic development — it is a prerequisite.

## References

- Poppendieck, Mary and Tom. *Lean Software Development: An Agile Toolkit.* Addison-Wesley, 2003.
- Ohno, Taiichi. *Toyota Production System: Beyond Large-Scale Production.* Productivity Press, 1988.
- Womack, James P. and Daniel T. Jones. *Lean Thinking.* Free Press, 2003.
- Anderson, David J. *Kanban: Successful Evolutionary Change for Your Technology Business.* Blue Hole Press, 2010.
