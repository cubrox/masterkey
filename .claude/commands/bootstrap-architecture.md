---
description: "Phase 2: Define Technical Architecture based on PRD"
---

Launch the system-architect agent to define the technical architecture based on your Product Requirements Document.

## Bootstrap Phase 2: Technical Architecture

**Prerequisite**: Phase 1 (Product Definition) must be complete.

The System Architect will read your PRD and help you define:

1. **Technology Stack** - Languages, frameworks, tools
2. **System Design** - Components, services, boundaries
3. **Data Models** - Entities, relationships, storage
4. **API Contracts** - Interfaces, protocols, patterns
5. **Infrastructure** - Hosting, deployment, scaling
6. **Development Standards** - Coding conventions, testing requirements

## Process

### 0. Platform (Fixed)

This template is hard-configured for **Google Cloud Platform**:

- **Compute**: Cloud Run (serverless containers, scale-to-zero)
- **Container registry**: Artifact Registry
- **Secrets**: Secret Manager
- **Database**: Neon (serverless Postgres with per-PR branching)
- **Auth**: Workload Identity Federation (SA key fallback for workshops)

If you need a different platform, fork the upstream
[vibeacademy/agile-flow](https://github.com/vibeacademy/agile-flow)
repository instead — it ships with Render as the default and supports
Vercel, Cloudflare, Railway, and Fly.io.

Write the platform choice to `.claude/PROJECT.md`:

```markdown
## Platform
- **Hosting**: gcp
- **Compute**: Cloud Run
- **Database**: Neon
- **Selected**: [date]
```

This file is read by the `devops-engineer` and `system-architect` agents
to provide platform-specific guidance.

### Stack (Fixed)

This fork ships with a **FastAPI + Jinja2 + HTMX + SQLModel starter**
(Python 3.12, uv, Alembic for migrations). The stack is hard-configured —
if the user needs a different stack (Next.js, Go, Rails, etc.), point
them at the upstream [vibeacademy/agile-flow](https://github.com/vibeacademy/agile-flow)
repo or another fork that targets their platform.

**What the starter includes:**

- `app/main.py` — FastAPI app with Jinja2 templates and static files mounted
- `app/models/todo.py` — example SQLModel (delete when building your product)
- `app/api/health.py` — health check endpoint used by Cloud Run
- `app/api/todos.py` — HTMX route examples (reference; delete when building)
- `templates/` — base layout + HTMX fragment examples
- `alembic/` — migration runner, preconfigured for Neon
- `tests/` — pytest + httpx test harness with in-memory SQLite fixture
- `pyproject.toml` — uv-managed dependencies

The CI `python` job runs automatically because `pyproject.toml` exists
at the root. The `node` job auto-skips because there's no `package.json`.

**Stack transition is out of scope for this fork.** Users who want to
mix in a React frontend or replace FastAPI entirely should fork the repo
and take ownership of those changes themselves — or use a different
Agile Flow variant.

### Error Handling and Observability

Unlike the upstream Agile Flow, this fork does NOT ship a Sentry
self-receiver or error-to-GitHub-issue pipeline. Attendees who want
observability have three choices:

1. **Google Cloud Logging + Error Reporting** — the most GCP-native
   option. Logs from Cloud Run automatically land in Cloud Logging, and
   Error Reporting auto-groups unhandled exceptions from FastAPI
   tracebacks. Zero setup required; view errors at
   `https://console.cloud.google.com/errors`.
2. **Sentry SaaS or self-hosted GlitchTip** — set `SENTRY_DSN` as an
   environment variable and initialize `sentry-sdk[fastapi]` in
   `app/main.py`. See Sentry's FastAPI docs for the one-liner.
3. **Nothing** — acceptable for a workshop demo where the scope is
   "get it working," not "production-grade observability."

For self-referential URL construction (email links, redirects), use
pattern #4 in `docs/PATTERN-LIBRARY.md` — read `X-Forwarded-Host` from
the request, or set `APP_URL` as a runtime env var via
`gcloud run services update --set-env-vars`.

### 1. PRD Analysis
The architect first analyzes your Product Requirements:
- What features need to be built?
- What scale do we need to support?
- What are the technical constraints?
- What integrations are required?

### 2. Technology Selection
For each layer of the stack:
- Present 2-3 options with trade-offs
- Recommend based on requirements
- Document the decision rationale

### 3. System Design
Define the high-level architecture:
- Component boundaries
- Data flow
- Integration points
- Security boundaries

### 4. Standards Definition
Establish development standards:
- Coding conventions
- Testing requirements
- Documentation standards
- Review criteria

## Output

This phase creates:

### docs/TECHNICAL-ARCHITECTURE.md
```markdown
# Technical Architecture

## Overview
[High-level system description]

## Technology Stack

### Frontend
- Framework: Server-rendered Jinja2 templates + HTMX (no build step)
- Styling: Pico.css via CDN (class-less; replace if you outgrow it)
- Interactivity: HTMX 2.x for AJAX, form handling, and fragment swaps
- Testing: [e.g., Vitest + Testing Library]

### Backend
- Runtime: Python 3.12
- Framework: FastAPI + Uvicorn
- Database layer: SQLModel + Alembic
- Testing: pytest + httpx (with in-memory SQLite fixture)
- Package manager: uv

### Database
- Primary: [e.g., Supabase (PostgreSQL) — supports branching for ephemeral PR databases]
- Cache: [e.g., Redis]
- Search: [e.g., Elasticsearch] (if needed)

### Infrastructure
- Hosting: GCP Cloud Run (Artifact Registry, Secret Manager, Neon)
- CI/CD: [e.g., GitHub Actions]
- Monitoring: [e.g., DataDog]

## System Design

### Component Diagram
[ASCII or description of components]

### Data Flow
[How data moves through the system]

### API Design
[REST/GraphQL/gRPC patterns]

## Data Models

### Core Entities
[Entity definitions and relationships]

### Database Schema
[Key tables/collections]

## Development Standards

### Code Style
- [Linting rules]
- [Formatting rules]
- [Naming conventions]

### Testing Requirements
- Unit test coverage: [e.g., 80%]
- Integration tests: [requirements]
- E2E tests: [requirements]

### Documentation
- [What needs documentation]
- [Documentation format]

### Code Review
- [Review checklist]
- [Approval requirements]

## Security

### Authentication
[Auth approach]

### Authorization
[Permissions model]

### Data Protection
[Encryption, PII handling]

## Scalability

### Current Targets
[Expected load]

### Scaling Strategy
[How we'll scale]

## Architecture Decision Records

### ADR-001: [First Decision]
- Status: Accepted
- Context: [Why this decision]
- Decision: [What we decided]
- Consequences: [Impact]
```

## CLAUDE.md Updates

This phase also updates CLAUDE.md with project-specific configuration:
- Technology stack details
- Code standards
- Build and test commands
- Definition of Ready/Done refinements

## What Gets Unlocked

After Phase 2 is complete:
- **Ticket Worker** knows the tech stack and coding standards
- **PR Reviewer** knows what to check for
- **Quality Engineer** knows testing requirements
- **All agents** can give project-specific guidance

## Architecture Patterns

The architect will recommend patterns based on your needs:

| Pattern | Best For |
|---------|----------|
| Monolith | Small team, early stage, simple domain |
| Modular Monolith | Growing team, need boundaries |
| Microservices | Large scale, independent deployment |
| Serverless | Event-driven, variable load |
| JAMstack | Content sites, static-first |

## Tips for Success

1. **Start simple** - You can always add complexity later
2. **Optimize for change** - Requirements will evolve
3. **Document decisions** - Future you will thank present you
4. **Consider the team** - Pick tech your team can maintain
5. **Plan for testing** - Testability is an architecture concern

## Running This Command

1. Ensure Phase 1 is complete (PRD exists)
2. Type `/bootstrap-architecture`
3. Answer the architect's questions about constraints and preferences
4. Review the proposed architecture
5. Iterate until satisfied

When complete, run `bash bootstrap.sh` to continue to Phase 3.

## FastAPI Testing Guidance

HTTP tests use `fastapi.testclient.TestClient` with an overridden
`get_session` dependency that yields sessions bound to an in-memory
SQLite database. Each test gets a fresh database so tests are
independent and fast.

```python
# tests/conftest.py
from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, SQLModel, create_engine
from sqlmodel.pool import StaticPool

from app.db import get_session
from app.main import app


@pytest.fixture(name="session")
def session_fixture() -> Generator[Session, None, None]:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


@pytest.fixture(name="client")
def client_fixture(session: Session) -> Generator[TestClient, None, None]:
    def get_session_override() -> Generator[Session, None, None]:
        yield session

    app.dependency_overrides[get_session] = get_session_override
    with TestClient(app) as client:
        yield client
    app.dependency_overrides.clear()
```

For HTMX routes specifically, assert on HTML substrings in the response
body. Verify that fragment responses do NOT include the full page chrome
(`assert "<html" not in response.text`) — this catches the common mistake
of accidentally returning a full page template from an HTMX endpoint.

### Output Format

Report each phase with a Progress Line, then end with a Result Block:

```
→ Read PRODUCT-REQUIREMENTS.md
→ Selected platform: GCP Cloud Run (fixed)
→ Defined tech stack and data models
→ Generated TECHNICAL-ARCHITECTURE.md

---

**Result:** Architecture definition complete
Document: docs/TECHNICAL-ARCHITECTURE.md
Platform: GCP Cloud Run
Stack: FastAPI, SQLModel, Jinja2, HTMX, Python 3.12
Next: /bootstrap-agents
```
