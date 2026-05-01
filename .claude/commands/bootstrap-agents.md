---
description: "Phase 3: Specialize agents with project-specific context"
---

Update all agent configurations with project-specific context from your PRD and Technical Architecture.

## Bootstrap Phase 3: Agent Specialization

**Prerequisites**:
- Phase 1 (Product Definition) complete
- Phase 2 (Technical Architecture) complete

This phase reads your product and architecture documents and injects project-specific context into each agent's configuration.

## Why This Matters

Generic agents give generic advice. Specialized agents give project-specific guidance.

**Before specialization:**
> "Use appropriate testing frameworks for your stack"

**After specialization:**
> "Write tests using Vitest with React Testing Library. Coverage must be >80%. Run `npm test` before creating PRs."

## What Gets Updated

### 1. Quality Engineer (.claude/agents/quality-engineer.md)

The `Project-Specific Context` section is populated with:
- Your testing stack (from architecture)
- Key test areas based on your features
- Critical quality concerns for your domain
- Coverage thresholds and testing commands

### 2. GitHub Ticket Worker (.claude/agents/github-ticket-worker.md)

The `Project Context` section is populated with:
- Your technology stack
- Coding standards and conventions
- Testing requirements
- Build and verification commands

### 3. PR Reviewer (.claude/agents/pr-reviewer.md)

The `Project Context` section is populated with:
- What to check during code review
- Architecture compliance criteria
- Technology-specific review points
- Quality thresholds

### 4. System Architect (.claude/agents/system-architect.md)

The `Project-Specific Domain Analysis` section is populated with:
- Your bounded contexts (if applicable)
- Domain entities and relationships
- Architecture patterns in use
- Key technical decisions

### 5. Product Manager & Product Owner

These agents reference the PRD and roadmap directly, so they're already specialized. This phase ensures cross-references are correct.

## Process

The specialization agent will:

1. **Read Source Documents**
   - docs/PRODUCT-REQUIREMENTS.md
   - docs/PRODUCT-ROADMAP.md
   - docs/TECHNICAL-ARCHITECTURE.md
   - CLAUDE.md

2. **Extract Key Context**
   - Technology stack
   - Coding standards
   - Testing requirements
   - Domain concepts
   - Quality thresholds

3. **Update Agent Configs**
   - Replace template placeholders
   - Add project-specific sections
   - Ensure consistency across agents

4. **Update CLAUDE.md**
   - Fill in project-specific sections
   - Add build/test commands
   - Refine Definition of Ready/Done

## Verification

After this phase, verify agents are specialized:

```bash
# Check that template placeholders are replaced
grep -r "TEMPLATE:" .claude/agents/

# Should return no results if fully specialized
```

## Example Transformation

**Before (template):**
```markdown
## Project-Specific Context

<!--
TEMPLATE: Fill in project-specific testing context here.
- **Architecture**: [Description]
- **Testing Stack**: [Frameworks]
-->
```

**After (specialized):**
```markdown
## Project-Specific Context

- **Architecture**: React 18+ SPA with Node.js API backend
- **Testing Stack**: Vitest + React Testing Library for frontend, Jest for backend
- **Key Test Areas**:
  - User authentication flows
  - Payment processing
  - Real-time notifications
- **Critical Quality Concerns**:
  - PCI compliance for payment data
  - Sub-200ms API response times
  - WCAG AA accessibility
```

## What Gets Unlocked

After Phase 3:
- Agents give **project-specific** advice
- Code reviews check **your** standards
- Tests validate **your** requirements
- Architecture guidance follows **your** patterns

## Manual Refinement

After automated specialization, you may want to further refine:

1. **Add team conventions** not in documents
2. **Specify common pitfalls** for your stack
3. **Add domain-specific terminology**
4. **Include links to internal resources**

Edit the agent files directly in `.claude/agents/`.

## Running This Command

1. Ensure Phases 1 and 2 are complete
2. Type `/bootstrap-agents`
3. Review the proposed updates
4. Confirm to apply changes
5. Optionally refine manually

When complete, run `./bootstrap.sh` to continue to Phase 4.

## Rollback

If you need to reset agents to template state:

```bash
# Re-copy from template (loses customizations)
git checkout -- .claude/agents/
```

### Output Format

Report each phase with a Progress Line, then end with a Result Block:

```
→ Read PRD and architecture docs
→ Updated quality-engineer with project context
→ Updated system-architect with platform details
→ Updated 4 remaining agents

---

**Result:** Agent specialization complete
Agents updated: 6
Source: docs/PRODUCT-REQUIREMENTS.md, docs/TECHNICAL-ARCHITECTURE.md
Next: /bootstrap-workflow
```
