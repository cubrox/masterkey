# Product Requirements Document

## Product Overview

- **Name**: Cubrox (working name — TBD)
- **Type**: Web application
- **Category**: Content/Media platform
- **Domain**: A website that makes Baha'i writings (WCAG-accessible) easier to read for neurodivergent readers
- **Value Proposition**: An improved reading experience for neurodivergent readers

## Vision and Problem Statement

### Problem

Neurodivergent readers find it harder to focus on and process text. The
primary friction is sustained attention — many readers cannot hold focus on
a passage for more than a couple of minutes, which makes engaging with
longer-form holy writings especially difficult.

### Vision

Every neurodivergent reader can engage deeply with Baha'i writings — and any
other text they choose to bring — through a reading experience tuned to how
they personally focus, process, and comprehend.

### How People Solve This Today

Most don't. Today, readers in this situation simply live with the pain.
Adjacent tools (Beeline Reader, ADHD reading helpers / "bionize"-style
bionic reading, Microsoft Immersive Reader) offer general-purpose reading
support but are not tailored to holy writings or to the specific needs of
neurodivergent readers engaging with sacred text.

## Target Audience

### Primary Users

- **Who**: A neurodivergent person who wants an easier experience reading
  holy texts (specifically Baha'i writings).
- **Pain Point**: Cannot hold attention on a text passage for more than a
  couple of minutes.
- **Current Solution**: None — they push through, give up, or rely on
  general-purpose reading aids that are not designed for sacred text.

### Secondary Users

Anyone who wants an improved reading experience — readers without a formal
neurodivergence diagnosis but who benefit from the same accommodations
(e.g., readers with fatigue, dyslexia, ESL readers, or simply readers who
prefer a calmer reading surface).

## Features

### MVP (Must Have)

- [ ] **Text passage input** — paste or type text passages directly into
      the reader.
- [ ] **Document upload (PDF)** — upload a PDF and read it inside the
      tailored reading experience.
- [ ] **Reading-support toolkit** — choose the type of support applied to a
      passage. v1 includes at minimum:
  - Visual reformatting (font, size, color, spacing, contrast).
  - Comprehension checks (auto-generated questions to confirm
    understanding of what was just read).
- [ ] **Email login** — register and sign in with email.
- [ ] **Saved preferences** — reading-support choices persist per user
      across sessions and devices.

### Out of Scope (v1)

- **Internationalization** — v1 ships English only. No multi-language UI,
  no multi-language source-text support beyond what the user pastes in.

### Core Value Proposition

Make text easier to read and understand — that is the one thing this
product must do exceptionally well.

## Success Metrics

| Metric                                                    | Target (3 months) |
|-----------------------------------------------------------|-------------------|
| Primary: Lines of text read/processed through the product | 100,000           |

## Competitive Analysis

| Competitor                  | Strength                                         | Weakness                                                     | Our Differentiator                          |
|-----------------------------|--------------------------------------------------|--------------------------------------------------------------|---------------------------------------------|
| Beeline Reader              | Color-gradient guides eye across lines           | Generic; not designed for sacred text or comprehension       | Tailored to holy writings + comprehension   |
| ADHD Reading Helper / Bionize | Bionic-reading-style emphasis aids fast scanning | Single technique; doesn't adapt to individual reader profiles | Multiple support modes + per-user prefs     |
| Microsoft Immersive Reader  | Mature accessibility toolkit, broad availability | General-purpose; embedded inside MS products; not faith-aware | Purpose-built for Baha'i writings           |

## Constraints and Requirements

- **Timeline**: Launch in 3–6 months (target window: 2026-08 to 2026-11).
- **Key product constraint**: Readability needs vary significantly between
  individuals — what makes text readable for one neurodivergent person may
  be very different for another. The product must accommodate this with
  configurable, per-user support choices rather than a single "accessible"
  preset.
- **Technical**: Google Cloud (Cloud Run), Neon (serverless Postgres),
  FastAPI. Aligns with this repo's existing stack (FastAPI + Jinja2 + HTMX
  on Python 3.12, SQLModel + Alembic, deployed to Cloud Run).

## Non-Functional Requirements

| Category      | Requirement                                                                 |
|---------------|-----------------------------------------------------------------------------|
| Accessibility | WCAG conformance is a defining product requirement, not a checkbox          |
| Security      | Email-based auth; user preferences stored per account                       |
| Performance   | Reading view must feel instant (perceived latency < 100ms for view changes) |
| Scalability   | Sized to support the 100k-lines-in-3-months target and beyond               |

## Dependencies

- Source corpus of Baha'i writings (licensing / canonical source TBD).
- PDF parsing pipeline for the upload flow.
- LLM or rules-based engine for auto-generated comprehension questions
  (provider TBD during architecture phase).

## Risks and Mitigations

| Risk                                                                                  | Impact | Mitigation                                                                                  |
|---------------------------------------------------------------------------------------|--------|---------------------------------------------------------------------------------------------|
| Readability needs differ across users; a single design won't fit                      | High   | Modular support toolkit; per-user saved preferences; recruit diverse beta testers           |
| Comprehension-question quality is uneven for sacred/poetic text                       | High   | Constrained prompts, source-grounded checks, ability to disable per passage                 |
| PDF ingestion produces messy text that defeats reading aids                           | Medium | Validate parser on representative documents early; surface ingestion errors to user         |
| Scope creep into i18n or non-Baha'i corpora before MVP validates                      | Medium | i18n explicitly out of scope for v1; defer broader corpora until MVP metric proven          |

## Glossary

| Term                         | Definition                                                                                  |
|------------------------------|---------------------------------------------------------------------------------------------|
| Neurodivergent reader        | A reader whose cognition differs from typical norms (ADHD, autism, dyslexia, etc.)          |
| Reading support              | A configurable transformation applied to a passage to aid focus or comprehension            |
| Comprehension check          | Auto-generated question(s) confirming the reader understood a passage                       |
| Holy writings (in this PRD)  | Baha'i sacred texts; v1 corpus scope                                                        |
