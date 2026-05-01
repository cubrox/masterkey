---
description: Create a test plan and validate a feature against specifications
---

Launch the quality-engineer agent to create a comprehensive test plan and/or execute validation for a feature.

**Usage**: `/test-feature <feature-name-or-ticket>`

**Example**: `/test-feature "user authentication flow"`

## What This Command Does

### 1. Analyze Specifications
- Review ticket requirements and acceptance criteria
- Read relevant BDD specs, user stories, or PRDs
- Understand expected behavior and edge cases

### 2. Create Test Plan
- Design test scenarios in BDD format (Given-When-Then)
- Cover happy path, error handling, and edge cases
- Identify test data requirements
- Define environment setup needs

### 3. Execute Tests (if requested)
- Run automated test suite
- Perform manual testing as needed
- Document results in real-time

### 4. Generate Test Report
- Summarize pass/fail status
- Document any defects found
- Provide coverage metrics
- Recommend next steps

## Output Format

### Test Plan Output
```markdown
# Test Plan: [Feature Name]

## Scope
[What is being tested]

## Test Scenarios

### Scenario 1: [Name]
**Given** [preconditions]
**When** [action]
**Then** [expected outcome]

### Scenario 2: [Name]
...

## Test Data
[Required fixtures and data]

## Environment
[Setup requirements]

## Success Criteria
[What constitutes passing]

## Risks
[Potential issues or blockers]
```

### Test Report Output
```markdown
# Test Report: [Feature Name]

## Executive Summary
- **Status**: PASS/FAIL/BLOCKED
- **Critical Findings**: [Count and description]
- **Recommendation**: [Release decision support]

## Test Results
### [Scenario Name] - PASS/FAIL
[Details, evidence, defects]

## Defects Found
### [DEF-001] [Severity] [Title]
**Impact**: [Business impact]
**Steps to Reproduce**: [Exact steps]
**Expected**: [What should happen]
**Actual**: [What happened]

## Metrics
- Test Coverage: X%
- Pass Rate: X%
- Execution Time: X minutes

## Sign-Off
[Conditions for approval]
```

## Usage Modes

**Create test plan only:**
```
/test-feature "login flow" --plan-only
```

**Execute existing test plan:**
```
/test-feature "login flow" --execute
```

**Full cycle (plan + execute + report):**
```
/test-feature "login flow"
```

## When to Use

- Before implementing a feature (shift-left testing)
- After completing implementation
- Before release to validate critical paths
- When investigating reported bugs

### Output Format

End your output with a Result Block:

```
---

**Result:** Test report — GO
Feature: user authentication flow
Tests: 8 passed, 0 failed
Coverage: 91%
Required changes: 0
```
