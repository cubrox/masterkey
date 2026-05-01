# Sorting and Batching

Sorting work before executing it is the single highest-leverage improvement you can make to delivery cadence. Everything else in agile-flow — ticket format, branching, backlog grooming — is downstream of this principle.

---

## The Laundry Analogy

Your dryer just finished. The goal is simple: socks in the sock drawer, shirts in the shirt drawer, towels on the shelf.

**The amateur approach:** grab the first item off the pile, fold it, walk it to the right drawer, put it away, walk back. Grab the next item — different type, different folding pattern, different drawer. Repeat. Every single item forces a context switch: new motor pattern, new destination.

**The professional approach:** sort the pile first. All socks together, all shirts together, all towels together. Now fold each batch. Your hands lock into one folding pattern and stay there. You walk to each drawer once, not twenty times.

The professional finishes faster *and* with less mental effort. Not because they fold faster — because they eliminated the switching cost.

---

## Why Sorting Reduces Context-Switching

The same dynamic plays out in software delivery. The focus required for a database migration is fundamentally different from the focus for a UI component, which is different again from a CI pipeline fix. Each type of work has its own mental model, its own tools, its own failure modes.

If you attack tickets in random order, every transition forces a full context reload — different files, different concerns, different risk profiles. This is expensive for humans and even more expensive for agents.

**For human developers:** each switch burns 10–20 minutes of ramp-up time that produces zero output.

**For AI agents:** each switch means the context window fills with irrelevant instructions from the previous task. The agent's attention is split between the current problem and leftover context from something unrelated.

Sort tickets by type or area *before* you start executing. Each batch keeps you — or the agent — in the same headspace. Database work stays with database work. UI stays with UI. The switching cost drops to near zero.

---

## Why Batching Normalizes Complexity

Unsorted work hides risk. When tickets aren't grouped by concern, a single ticket can quietly absorb three different types of work — a schema change, a UI update, and a deploy config tweak — without anyone noticing until it blows up mid-sprint.

Sorting forces you to see the real shape of the work *before* you commit to it. When you group by area, a ticket that crosses boundaries becomes immediately visible: it doesn't fit neatly into any batch. That's your signal to split it.

Properly sorted and batched tickets have predictable size. An XS stays XS and an S stays S because each ticket does one kind of thing. There are no surprise L tickets hiding inside what looked like an S.

This is why effort estimates hold and budgets don't blow up. The variance in ticket size collapses because sorting eliminates the hidden complexity that causes blowups in the first place.

---

## How agile-flow Enforces This

Sorting and batching aren't just advice — they're built into the workflow at multiple points:

- **Backlog grooming** (`/groom-backlog`) is where sorting happens. The Backlog Prioritizer reads the full backlog and groups work by area and type, surfacing tickets that need splitting before they enter a sprint.
- **The agile board** makes batches visible. Columns show what's in-flight, so you can see at a glance whether a sprint's work is coherent or scattered across unrelated concerns.
- **Ticket format** ([TICKET-FORMAT.md](TICKET-FORMAT.md)) constrains scope to one concern per ticket. A ticket that tries to do two kinds of work violates the format by definition.
- **Branching strategy** ([BRANCHING-STRATEGY.md](BRANCHING-STRATEGY.md)) maps one ticket to one branch to one PR. This keeps batches clean all the way through delivery — no branch accumulates unrelated changes.

---

## Related Documentation

- [TICKET-FORMAT.md](TICKET-FORMAT.md) — ticket structure and scope constraints
- [ARTIFACT-FLOW.md](ARTIFACT-FLOW.md) — how documents, tickets, and code move through the system
- [CONTEXT-OPTIMIZATIONS.md](CONTEXT-OPTIMIZATIONS.md) — context engineering strategy for agent workflows
- [BRANCHING-STRATEGY.md](BRANCHING-STRATEGY.md) — trunk-based development and the one-ticket-one-branch rule
