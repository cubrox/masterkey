---
description: "Formally lock MVP scope before development begins"
---

## Scope Lock

This command formalizes the transition from planning to execution by verifying and documenting that MVP scope is locked.

## Instructions

Guide the user through a scope lock checklist, then generate the scope lock document.

### Pre-Check

Before proceeding, verify these documents exist:
- `docs/PRODUCT-REQUIREMENTS.md` (from `/bootstrap-product`)
- `docs/TECHNICAL-ARCHITECTURE.md` (from `/bootstrap-architecture`)

If missing, inform the user which bootstrap phases need to be completed first.

---

## Scope Lock Checklist

Ask the user to confirm each criterion ONE AT A TIME:

### Question 1: Feature List
```
Is your MVP feature list finalized?

1. Yes - I can list exactly what's in v1
2. Mostly - A few items still being decided
3. No - Still exploring options

Enter a number (1-3):
```

If not "Yes", ask:
```
What features are still undecided? (List them so we can track as open items)
```

### Question 2: Acceptance Criteria
```
Do all MVP features have acceptance criteria (testable "done" conditions)?

1. Yes - All features have clear acceptance criteria
2. Partial - Some features need criteria defined
3. No - Most features lack clear criteria

Enter a number (1-3):
```

If not "Yes", ask:
```
Which features need acceptance criteria defined?
```

### Question 3: Open Questions
```
Are major technical and product decisions resolved?

1. Yes - No blocking open questions
2. Mostly - A few non-blocking questions remain
3. No - Major decisions still pending

Enter a number (1-3):
```

If not "Yes", ask:
```
What open questions remain? (List them so we can track)
```

### Question 4: Stakeholder Alignment
```
Are all stakeholders aligned on this scope?

1. Yes - Everyone agrees this is what we're building
2. Mostly - Minor disagreements exist
3. No - Significant misalignment

Enter a number (1-3):
```

If not "Yes", ask:
```
What alignment issues exist?
```

### Question 5: Timeline
```
Do you have a target launch date or timeline?

1. Yes - Specific date: [please specify]
2. Roughly - General timeframe (e.g., "Q2", "3 months")
3. No - No timeline established

Enter a number (1-3) and specify if applicable:
```

### Question 6: Change Process
```
How will scope changes be handled after lock?

1. Formal trade-off process (add something = cut something)
2. Review meeting required for any additions
3. No process defined yet

Enter a number (1-3):
```

---

## Lock Decision

Based on responses, determine lock status:

**LOCKED** - All criteria met (all "Yes" responses)
- Proceed to generate SCOPE-LOCK.md
- Trigger GTM Checkpoint 2

**CONDITIONAL LOCK** - Minor gaps (mostly "Yes" with some "Mostly")
- Document open items
- Proceed with lock but flag items to resolve
- Set deadline for resolving open items

**NOT READY** - Significant gaps (any "No" responses)
- List what needs to be resolved
- Do not create lock document
- Recommend next steps

---

## Output: SCOPE-LOCK.md

Generate the following document:

```markdown
# Scope Lock Document

**Lock Date:** [Today's date]
**Lock Status:** [LOCKED / CONDITIONAL]
**Target Launch:** [From Q5]

---

## MVP Scope

### Features In Scope

[Pull from PRODUCT-REQUIREMENTS.md MVP section, formatted as:]

| Feature | Description | Acceptance Criteria | Priority |
|---------|-------------|---------------------|----------|
| [Feature 1] | [Brief description] | [Testable criteria] | P0 |
| [Feature 2] | [Brief description] | [Testable criteria] | P0 |
| [Feature 3] | [Brief description] | [Testable criteria] | P1 |

### Explicitly Out of Scope (v1)

[Pull from PRODUCT-REQUIREMENTS.md out of scope section]

- [Feature A] - Reason: [Why deferred]
- [Feature B] - Reason: [Why deferred]

---

## Open Items

[If CONDITIONAL lock, list items that need resolution]

| Item | Type | Owner | Due Date |
|------|------|-------|----------|
| [Open question 1] | Decision | [Who] | [Date] |
| [Missing criteria] | Definition | [Who] | [Date] |

---

## Change Control Process

[From Q6]

**To add scope after lock:**
1. [Step 1 - e.g., Submit change request]
2. [Step 2 - e.g., Identify trade-off]
3. [Step 3 - e.g., Get stakeholder approval]

**Authorized approvers:**
- [Role/Name]

---

## Stakeholder Sign-Off

| Role | Status | Notes |
|------|--------|-------|
| Product | [Aligned/Pending] | [Any notes] |
| Engineering | [Aligned/Pending] | [Any notes] |
| Design | [Aligned/Pending] | [Any notes] |
| Marketing | [Aligned/Pending] | [Any notes] |

---

## Timeline

**Target Launch:** [Date/Timeframe]

| Milestone | Target Date |
|-----------|-------------|
| Scope Lock | [Today] |
| Dev Midpoint | [Date] |
| Feature Complete | [Date] |
| Launch | [Date] |

---

## What This Lock Means

By locking scope, we commit to:

1. **Building exactly this** - The features listed above, no more, no less
2. **Predictable timeline** - Dates are based on this defined scope
3. **Visible trade-offs** - Any additions require cutting something else
4. **Marketing can plan** - GTM strategy can be built against this target

This document is the contract between Product, Engineering, and Marketing.

---

## Next Steps

- [ ] Run `/sync-gtm` and select Checkpoint 2 (Scope Lock) to brief Marketing
- [ ] Ensure all tickets exist in backlog for MVP features
- [ ] Begin development sprint

---

*This scope lock is valid until explicitly unlocked or launch is complete.*
```

Save to `docs/SCOPE-LOCK.md`.

---

## After Lock

Inform the user:

```
Scope is now locked. Next steps:

1. Run `/sync-gtm` and select Checkpoint 2 (Scope Lock)
   - This briefs Marketing on the locked scope
   - Marketing can now start GTM planning

2. Ensure all MVP features have tickets in the backlog
   - Run `/groom-backlog` if needed

3. Begin development
   - Run `/work-ticket` to pick up the first ticket

Remember: Adding scope now requires a formal trade-off discussion.
```

### Output Format

End your output with a Result Block:

```
---

**Result:** Scope locked
Status: LOCKED
Target launch: Q2 2025
Features in scope: 12
Open items: 0
Document: docs/SCOPE-LOCK.md
```
