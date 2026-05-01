---
description: Evaluate a feature request for strategic fit, market value, and ROI
---

Launch the agile-product-manager agent to evaluate whether a feature should be built.

**Usage**: `/evaluate-feature <feature-description>`

**Example**: `/evaluate-feature "Add bulk export functionality for enterprise users"`

## What This Command Does

### 1. Validate the Problem
- Is this a real customer problem or internal assumption?
- How many customers/prospects are experiencing this?
- What evidence supports the need? (support tickets, sales feedback, user research)
- What's the cost of NOT solving this?

### 2. Assess Market Fit
- Does this solve a validated customer problem?
- Is this a "must-have" or "nice-to-have"?
- Does this strengthen competitive position?
- What market segment does this serve?

### 3. Evaluate Business Impact
- Revenue potential (new sales, upsells, retention)
- Cost to build vs. expected return
- Impact on margins and unit economics
- Strategic value beyond direct revenue

### 4. Check Strategic Alignment
- Does this support our product vision?
- Does this fit our target customer segment?
- Does this create technical debt or platform risk?
- Does this open new markets or capabilities?

### 5. Make Recommendation
- **BUILD**: Hand off to Product Owner with success criteria
- **DEFER**: Add to future consideration with conditions
- **DECLINE**: Document rationale, suggest response to requestor

## Output Format

```markdown
## Feature Evaluation: <Feature Name>

### Market Signal
- Customer requests: [Count/Evidence]
- Competitive pressure: [Yes/No - Details]
- Market trend: [Growing/Stable/Declining]

### Business Case
- Revenue impact: [High/Medium/Low]
- Cost estimate: [Request from Product Owner]
- Expected ROI: [Calculation if possible]
- Payback period: [Timeframe]

### Strategic Fit
- Vision alignment: [Strong/Moderate/Weak]
- Target segment: [Core/Adjacent/New]
- Platform impact: [Enhances/Neutral/Risk]

### Recommendation: [BUILD / DEFER / DECLINE]

**Rationale**: [Why this decision serves our product strategy]

### If BUILD:
- Success criteria: [Metrics to track]
- Handoff to Product Owner: [Specific guidance]

### If DEFER:
- Conditions for reconsideration: [What would need to change]
- Review date: [When to revisit]

### If DECLINE:
- Suggested response to requestor: [Draft communication]
- Alternative solutions: [If any]
```

## When to Use

- New feature request from sales, support, or customers
- Internal idea that needs strategic validation
- Competitive pressure to add functionality
- Evaluating scope for upcoming releases

## Who Makes the Decision

The **Product Manager** (agile-product-manager) owns this decision.

After evaluation:
- If BUILD: Product Owner (agile-backlog-prioritizer) handles execution planning
- If DEFER/DECLINE: Product Manager communicates decision

### Output Format

End your output with a Result Block:

```
---

**Result:** Feature evaluation — BUILD
Feature: Bulk export for enterprise users
Strategic fit: Strong
Revenue impact: High
Handoff: Product Owner for execution planning
```
