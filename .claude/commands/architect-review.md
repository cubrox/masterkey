---
description: Get architectural guidance or review for a design decision
---

Launch the system-architect agent to provide architectural guidance, review a design, or evaluate technology choices.

**Usage**: `/architect-review <topic-or-question>`

**Examples**:
- `/architect-review "How should we structure the authentication service?"`
- `/architect-review "Evaluate Redis vs Memcached for our caching layer"`
- `/architect-review "Review the proposed API design for payments"`

## What This Command Does

### 1. Understand Context
- Clarify the problem being solved
- Identify constraints (time, budget, skills, technology)
- Understand non-functional requirements (performance, scalability, security)

### 2. Analyze Options
- Present 2-4 viable architectural approaches
- Document pros and cons of each
- Identify risks and trade-offs

### 3. Make Recommendation
- Provide clear recommendation with rationale
- Explain key trade-offs being accepted
- Offer implementation guidance

### 4. Document Decision (if accepted)
- Create Architecture Decision Record (ADR)
- Capture context, decision, and consequences

## Output Format

```markdown
## Architectural Review: [Topic]

### Context
[What problem are we solving? Why now?]

### Constraints
- [Constraint 1]
- [Constraint 2]

### Options Evaluated

#### Option 1: [Name]
- **Description**: [How it works]
- **Pros**: [Benefits]
- **Cons**: [Drawbacks]
- **Best for**: [Use cases]

#### Option 2: [Name]
...

### Recommendation: [Option Name]

**Rationale**: [Why this option]

**Trade-offs Accepted**:
- [Trade-off 1]
- [Trade-off 2]

### Implementation Guidance
1. [Step 1]
2. [Step 2]
3. [Step 3]

### Risks & Mitigations
| Risk | Mitigation |
|------|------------|
| [Risk 1] | [How to handle] |

### ADR (if decision is accepted)
# ADR-XXX: [Title]

## Status
Proposed

## Context
[Issue being addressed]

## Decision
[What we're doing]

## Consequences
**Positive**: [Benefits]
**Negative**: [Trade-offs]
```

## When to Use

- Designing new features or systems
- Evaluating technology choices
- Refactoring or re-architecting existing code
- Resolving technical disagreements
- Establishing patterns and standards

## Types of Reviews

**Design Review**: Evaluate a proposed architecture
```
/architect-review "Review the microservices design for order processing"
```

**Technology Evaluation**: Compare options
```
/architect-review "PostgreSQL vs MongoDB for our data model"
```

**Pattern Guidance**: Get recommendations
```
/architect-review "Best approach for real-time notifications"
```

**Scalability Assessment**: Plan for growth
```
/architect-review "How to scale the search service to 10x traffic"
```

### Output Format

End your output with a Result Block:

```
---

**Result:** Architecture review complete
Topic: Authentication service design
Recommendation: OAuth2 with PKCE flow
Options evaluated: 3
Risks: 1 (token refresh complexity)
```
