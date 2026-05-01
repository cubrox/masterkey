---
description: Get current sprint status and board health overview
---

Launch the agile-backlog-prioritizer agent to provide a quick status overview of the current sprint and project board.

## What This Command Does

### 1. Board Status Snapshot
- Count tickets in each column (Backlog, Ready, In Progress, In Review, Done, Icebox)
- Identify any bottlenecks (e.g., too many items In Review)
- Check if Ready column needs replenishment

### 2. In Progress Work
- List all tickets currently In Progress
- Check for stale items (no activity in X days)
- Identify any blockers

### 3. Pending Reviews
- List all tickets/PRs In Review
- How long have they been waiting?
- Who needs to take action?

### 4. Recent Completions
- Tickets moved to Done this week
- Velocity trend

### 5. Immediate Actions Needed
- Ready column empty? → Need grooming
- Items blocked? → Need unblocking
- PRs waiting too long? → Need review
- Stale In Progress? → Need attention

## Output Format

```markdown
## Sprint Status: [Date]

### Board Overview
| Column | Count | Health |
|--------|-------|--------|
| Backlog | X | - |
| Ready | X | OK/Low/Empty |
| In Progress | X | OK/High |
| In Review | X | OK/Bottleneck |
| Done | X | - |
| Icebox | X | - |

### In Progress (X items)
| Ticket | Assignee | Days | Status |
|--------|----------|------|--------|
| #123 Title | @user | 2 | Active |
| #124 Title | @user | 5 | Stale |

### Awaiting Review (X items)
| PR | Ticket | Days Waiting |
|----|--------|--------------|
| #234 | #123 | 1 |
| #235 | #124 | 3 |

### Completed This Week
- #120: Feature description
- #121: Feature description
- Velocity: X tickets/week

### Action Items
1. [Priority] Action needed
2. [Priority] Action needed

### Blockers
- #125 blocked by: [reason]
```

## Usage

```
/sprint-status
```

## When to Use

- Daily standup preparation
- Quick health check on project progress
- Before starting new work
- When planning capacity

## Related Commands

- `/groom-backlog` - Detailed backlog grooming session
- `/check-milestone` - Progress toward specific milestone
- `/work-ticket` - Pick up next ticket from Ready
- `/review-pr` - Review pending pull requests

### Output Format

End your output with a Result Block:

```
---

**Result:** Sprint status — On Track
Ready: 3 | In Progress: 2 | In Review: 1 | Done: 8
Blockers: 0
Action items: 2
```
