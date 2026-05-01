# Artifact Flow

How documents, tickets, and code flow through the Agile Flow system — who
produces each artifact, what it contains, and who consumes it.

---

## System Overview

```mermaid
graph TB
    subgraph Bootstrap ["Phase 0-4: Bootstrap (one-time setup)"]
        direction TB
        Human["Human (founder)"]
        Research["Research Phase<br/><i>/research, /jtbd, /positioning</i>"]
        PM["Product Manager Agent"]
        SA["System Architect Agent"]
        BA["Bootstrap Agents Skill"]

        Human -->|answers questions| Research
        Research -->|produces| MR["MARKET-RESEARCH.md<br/><i>Competitors, audience,<br/>opportunity gaps</i>"]
        Research -->|produces| JTBD["JOBS-TO-BE-DONE.md<br/><i>User jobs, pain points,<br/>underserved needs</i>"]
        Research -->|produces| Pos["POSITIONING-ANALYSIS.md<br/><i>Differentiators, category,<br/>value proposition</i>"]

        Human -->|answers questions| PM
        MR -->|enriches| PM
        JTBD -->|enriches| PM
        Pos -->|enriches| PM
        PM -->|produces| PRD["PRODUCT-REQUIREMENTS.md<br/><i>Vision, audience, features,<br/>success metrics, constraints</i>"]
        PM -->|produces| Roadmap["PRODUCT-ROADMAP.md<br/><i>Phases, milestones,<br/>success criteria</i>"]

        Human -->|answers questions| SA
        SA -->|reads| PRD
        SA -->|produces| Arch["TECHNICAL-ARCHITECTURE.md<br/><i>Stack, components, data models,<br/>API contracts, infrastructure</i>"]

        BA -->|reads| PRD
        BA -->|reads| Arch
        BA -->|produces| AgentConfig["Agent Definitions<br/><i>.claude/agents/*.md<br/>Project-specific context</i>"]
        BA -->|produces| ProjectMD["PROJECT.md<br/><i>Platform, org, board URL</i>"]
    end

    subgraph Operate ["Ongoing: Development Cycle"]
        direction TB

        subgraph Groom ["Stage 1: Ticket Authoring"]
            direction TB
            Groomer["Backlog Prioritizer Agent<br/><i>(Product Owner role)</i>"]

            Groomer -->|reads| PRD2["PRD"]
            Groomer -->|reads| Arch2["Architecture"]
            Groomer -->|reads| Controls["AGENTIC-CONTROLS.md"]

            Groomer -->|"produces (Agentic PRD Lite)"| Ticket["GitHub Issue<br/><i>Problem + 4 Power Sections</i>"]
        end

        subgraph Implement ["Stage 2: Implementation"]
            direction TB
            Worker["Ticket Worker Agent<br/><i>(va-worker account)</i>"]

            Worker -->|"reads + validates"| Ticket2["Ticket"]
            Worker -->|reads| Arch3["Architecture"]
            Worker -->|produces| Branch["Feature Branch<br/><i>Code + tests</i>"]
            Worker -->|produces| PR["Pull Request<br/><i>Description, linked issue,<br/>CI checks</i>"]
        end

        subgraph Review ["Stage 3: Quality Gate"]
            direction TB
            Reviewer["PR Reviewer Agent<br/><i>(va-reviewer account)</i>"]

            Reviewer -->|reads| PR2["Pull Request"]
            Reviewer -->|reads| Ticket3["Ticket"]
            Reviewer -->|produces| ReviewComment["Review Comment<br/><i>GO / NO-GO<br/>recommendation</i>"]
        end

        subgraph Merge ["Stage 4: Human Decision"]
            direction TB
            HumanMerge["Human (founder)"]

            HumanMerge -->|reads| ReviewComment2["Review Comment"]
            HumanMerge -->|tests| Preview["Preview Environment<br/><i>Render / Vercel / etc.</i>"]
            HumanMerge -->|decides| MergeAction["Merge to main"]
            MergeAction -->|triggers| Deploy["Production Deploy"]
            MergeAction -->|triggers| Done["Ticket → Done"]
        end

        Groom --> Implement --> Review --> Merge
    end

    Bootstrap --> Operate

    style MR fill:#e8eaf6
    style JTBD fill:#e8eaf6
    style Pos fill:#e8eaf6
    style PRD fill:#e1f5fe
    style Roadmap fill:#e1f5fe
    style Arch fill:#e1f5fe
    style AgentConfig fill:#f3e5f5
    style ProjectMD fill:#f3e5f5
    style Ticket fill:#fff3e0
    style Branch fill:#e8f5e9
    style PR fill:#e8f5e9
    style ReviewComment fill:#fce4ec
    style MergeAction fill:#f5f5f5
    style Deploy fill:#f5f5f5
```

---

## Artifact Detail: The Ticket (Agentic PRD Lite)

The ticket is the critical handoff artifact between the groomer and the
worker. It must be dense enough that the worker agent can implement without
hallucinating missing constraints.

```mermaid
graph LR
    subgraph Sources ["Source Documents"]
        PRD["PRD<br/><i>Features, acceptance criteria</i>"]
        Arch["Architecture<br/><i>Stack, patterns, files</i>"]
        Controls["Agentic Controls<br/><i>Safety constraints</i>"]
        Roadmap["Roadmap<br/><i>Phase, milestone</i>"]
    end

    Groomer["Backlog Prioritizer"]

    PRD --> Groomer
    Arch --> Groomer
    Controls --> Groomer
    Roadmap --> Groomer

    subgraph TicketFormat ["Agentic PRD Lite Ticket"]
        Problem["Problem Statement<br/><i>What and why</i>"]
        SectionA["A. Environment Context<br/><i>Stack, integrations,<br/>files to reference</i>"]
        SectionB["B. Guardrails<br/><i>Security, performance,<br/>what NOT to do</i>"]
        SectionC["C. Happy Path<br/><i>Input → Logic → Output<br/>step-by-step flow</i>"]
        SectionD["D. Definition of Done<br/><i>Concrete tests and<br/>assertions to prove success</i>"]
        Meta["Metadata<br/><i>Epic link, effort, priority</i>"]
    end

    Groomer --> Problem
    Groomer --> SectionA
    Groomer --> SectionB
    Groomer --> SectionC
    Groomer --> SectionD
    Groomer --> Meta

    style SectionA fill:#e1f5fe
    style SectionB fill:#fce4ec
    style SectionC fill:#e8f5e9
    style SectionD fill:#fff3e0
```

### Where Each Section Comes From

| Section | Primary Source | What the Groomer Extracts |
|---------|--------------|--------------------------|
| Problem | PRD feature list | Why this matters, who benefits |
| A. Environment Context | TECHNICAL-ARCHITECTURE.md | Stack, framework, existing patterns, files to modify |
| B. Guardrails | AGENTIC-CONTROLS.md + PRD constraints | Security rules, performance targets, explicit prohibitions |
| C. Happy Path | PRD acceptance criteria + architecture | Step-by-step Input → Logic → Output for this feature |
| D. Definition of Done | PRD success metrics + test patterns | Specific tests, endpoints, assertions that prove completion |
| Metadata | PRODUCT-ROADMAP.md | Epic link, phase alignment, effort estimate, priority |

---

## Separation of Duties

No single actor can take a change from idea to production alone.

```mermaid
graph LR
    subgraph Actors
        PM["Product Manager"]
        PO["Backlog Prioritizer<br/><i>(Product Owner)</i>"]
        Worker["Ticket Worker<br/><i>(va-worker)</i>"]
        Reviewer["PR Reviewer<br/><i>(va-reviewer)</i>"]
        Human["Human"]
    end

    PM -->|"evaluates features<br/>go/no-go decisions"| Strategy["Strategy<br/>Artifacts"]
    PO -->|"authors tickets<br/>prioritizes backlog"| Tickets["Tickets"]
    Worker -->|"writes code<br/>creates PRs"| Code["Code +<br/>Pull Requests"]
    Reviewer -->|"reviews code<br/>GO / NO-GO"| Reviews["Review<br/>Comments"]
    Human -->|"approves + merges<br/>moves to Done"| Production["Production<br/>Deploy"]

    Strategy --> Tickets --> Code --> Reviews --> Production

    style PM fill:#e1f5fe
    style PO fill:#fff3e0
    style Worker fill:#e8f5e9
    style Reviewer fill:#fce4ec
    style Human fill:#f5f5f5
```

### Authority Matrix

| Actor | Creates | Reads | Cannot Do |
|-------|---------|-------|-----------|
| Product Manager | PRD, Roadmap, feature evaluations | All docs | Write code, manage backlog |
| Backlog Prioritizer | Tickets, priorities, epics | PRD, Roadmap, Architecture, Controls | Write code, review PRs, merge |
| Ticket Worker (bot) | Branches, code, tests, PRs | Tickets, Architecture, CLAUDE.md | Merge PRs, move to Done, push to main |
| PR Reviewer (bot) | Review comments, GO/NO-GO | PRs, tickets, code diffs | Merge PRs, move to Done, write code |
| Human | Merge decisions, Done status | Everything | N/A (full authority) |

---

## Artifact Lifecycle

```mermaid
stateDiagram-v2
    [*] --> MarketResearch: /research (optional)
    MarketResearch --> JTBDAnalysis: /jtbd (optional)
    JTBDAnalysis --> Positioning: /positioning (optional)
    Positioning --> PRD: /bootstrap-product
    [*] --> PRD: /bootstrap-product (without research)
    PRD --> Architecture: /bootstrap-architecture
    Architecture --> AgentConfig: /bootstrap-agents
    AgentConfig --> Board: /bootstrap-workflow

    Board --> Ticket: /groom-backlog or /create-ticket

    state Ticket {
        [*] --> Backlog
        Backlog --> Ready: Groomer promotes<br/>(meets Definition of Ready +<br/>4 Power Sections)
        Ready --> InProgress: Worker picks up
        InProgress --> InReview: PR created, CI green
        InReview --> Done: Human merges
    }

    Done --> Ticket: Next ticket
    Done --> [*]: All tickets complete
```

---

## Quick Reference: Commands and Artifacts

| Command | Actor | Reads | Produces |
|---------|-------|-------|----------|
| `/research` | Product Manager | Human answers, web search | MARKET-RESEARCH.md |
| `/jtbd` | Product Manager | Human answers, MARKET-RESEARCH.md (optional) | JOBS-TO-BE-DONE.md |
| `/positioning` | Product Manager | Human answers, MARKET-RESEARCH.md + JOBS-TO-BE-DONE.md (optional) | POSITIONING-ANALYSIS.md |
| `/bootstrap-product` | Product Manager | Human answers, research artifacts (optional) | PRD, Roadmap |
| `/bootstrap-architecture` | System Architect | PRD | Architecture doc |
| `/bootstrap-agents` | Bootstrap skill | PRD, Architecture | Agent configs |
| `/bootstrap-workflow` | Workflow skill | CLAUDE.md | Board, branch protection, initial backlog |
| `/groom-backlog` | Backlog Prioritizer | PRD, Roadmap, Architecture, Controls | Refined tickets in Ready column |
| `/create-ticket` | Backlog Prioritizer | PRD, Architecture, Controls | Single ticket in Backlog |
| `/work-ticket` | Ticket Worker | Ticket, Architecture | Branch, code, tests, PR |
| `/review-pr` | PR Reviewer | PR, ticket, code diff | Review comment (GO/NO-GO) |
| `/sprint-status` | Any agent | Board state | Status report |
| `/evaluate-feature` | Product Manager | PRD, Roadmap | BUILD/DEFER/DECLINE decision |
| `/release-decision` | Product Manager | Board, PRD, metrics | GO/NO-GO release decision |

---

## See Also

- [TICKET-FORMAT.md](TICKET-FORMAT.md) — Canonical Agentic PRD Lite template
- [AGENT-WORKFLOW-SUMMARY.md](AGENT-WORKFLOW-SUMMARY.md) — Detailed workflow documentation
- [AGENTIC-CONTROLS.md](AGENTIC-CONTROLS.md) — 8-layer defense-in-depth controls
