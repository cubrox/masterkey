---
description: Check progress toward a roadmap milestone
---

Launch the agile-backlog-prioritizer agent to assess progress toward a specific milestone.

**Usage**: `/check-milestone <milestone-name>`

**Example**: `/check-milestone "MVP Release"`

## What This Command Does

### 1. Milestone Overview
- Read milestone definition from `docs/PRODUCT-ROADMAP.md`
- Identify target completion date
- List all epics and tasks associated with the milestone
- Review exit criteria and success metrics

### 2. Progress Analysis
- Query project board for milestone-related issues
- Count issues by status (Done, In Review, In Progress, Ready, Backlog)
- Calculate completion percentage
- Identify completed vs. remaining work

### 3. Blocker & Risk Assessment
- Identify blocked tickets
- Flag tickets with no assignee or stale activity
- Review dependency chains and critical path items
- Assess risk factors (scope creep, technical debt, unclear specs)

### 4. Velocity & Forecasting
- Calculate team velocity (tickets completed per week)
- Estimate remaining effort based on incomplete tickets
- Project completion date based on current velocity
- Compare projected vs. target completion date

### 5. Recommendations
- **If on track**: Continue current pace, monitor risks
- **If behind schedule**:
  - Identify tasks that can be deferred
  - Recommend parallelization opportunities
  - Suggest scope reduction if necessary
  - Flag tickets needing urgent attention
- **If ahead**: Consider pulling in work from next milestone

## Output Format

```markdown
## Milestone: <Name>
**Target Date**: <Date from roadmap>
**Projected Date**: <Based on velocity>
**Status**: On Track | At Risk | Blocked

### Progress Summary
- Completed: X tasks (Y%)
- In Progress: X tasks
- Ready: X tasks
- Backlog: X tasks
- **Total**: X tasks

### Critical Path Items
1. [#123] Item name - Status - Blockers
2. [#124] Item name - Status - Blockers

### Blockers & Risks
- Blocker: Description
- Risk: Description

### Velocity Analysis
- Avg velocity: X tasks/week
- Remaining effort: Y tasks
- Estimated completion: <Date>
- Delta from target: +/- X days

### Recommendations
1. Action item
2. Action item
```

## Configuration

Define milestones in `docs/PRODUCT-ROADMAP.md`:
```markdown
## Milestones

### MVP Release
- **Target Date**: March 15, 2025
- **Exit Criteria**:
  - Core features complete
  - All P0 bugs resolved
  - Documentation complete
```

## Best Practices

- Run weekly to monitor milestone health
- Update PRODUCT-ROADMAP.md if dates need adjustment
- Create new issues if gaps are identified
- Defer scope to next milestone rather than compromise quality

### Output Format

End your output with a Result Block:

```
---

**Result:** Milestone check — On Track
Milestone: MVP Release (target: March 15)
Progress: 12/18 tasks (67%)
Blockers: 1 (#34 — API dependency)
Projected: March 13 (-2 days)
```
