---
description: Compose a design brief and generate a throwaway HTML mockup for a proposed UX change before writing implementation tickets
argument-hint: <slug>
---

<!--
This skill is a DESIGN-REVIEW skill, NOT a bootstrap-chain gate.
Masterkey has already run /bootstrap-architecture; this skill exists so that
future major UX changes get a compose-brief -> generate-mockup step BEFORE
tickets are filed against the change.

This skill does NOT modify bootstrap-architecture. Do not add gate coupling
in future revisions. If a future extension ever ties this skill to
bootstrap-architecture, the gate must check *absence of
docs/TECHNICAL-ARCHITECTURE.md* — NOT absence of a mockup — so re-runs on
already-bootstrapped forks stay idempotent.

Non-goals recorded from the retrofit design review:
- No docs/MOCKUP.yaml sidecar (violates CLAUDE.md rule #7 — one canonical
  location per fact; PRD already carries the source-of-truth content)
- No --approve / --skip / --refine subcommands (re-run for iteration)
- No docs/MOCKUP-APPROVAL.md audit trail (session journal is the audit trail)
- No Path C starter-template hand-authoring (no consumer)
-->

Generate a throwaway HTML mockup grounded in this fork's product docs, for
operator review before implementation tickets are written.

## When to use

Before filing tickets against any **major UX change** — new surface, redesigned
existing surface, added funnel step. The mockup is a *low-cost gate* the
operator reacts to in 15 minutes, ratifying design intent before the team
spends days building against a mis-shaped hypothesis.

**Not for:** small UI tweaks, copy edits, or already-scoped features that
already have tickets. Overhead is not worth it below "major UX change" size.

## Arguments

- `<slug>` — a short kebab-case identifier for the mockup, e.g.
  `reading-pane-v2`, `dashboards`, `subscription-flow`. Becomes the output
  filename.

Invocation:

```text
/mockup reading-pane-v2
```

## Preflight

Verify inputs before composing the brief:

1. **Required (hard):** `docs/PRODUCT-REQUIREMENTS.md` MUST exist. If missing,
   STOP with `→ Missing docs/PRODUCT-REQUIREMENTS.md — run /bootstrap-product
   first (or restore the file from git history)`.
2. **Required (hard):** `docs/TECHNICAL-ARCHITECTURE.md` MUST exist. If
   missing, STOP with `→ Missing docs/TECHNICAL-ARCHITECTURE.md — this fork
   has not been bootstrapped, /mockup is a post-bootstrap design-review
   skill`.
3. **Soft (used if present):** `docs/POSITIONING-ANALYSIS.md`,
   `docs/JOBS-TO-BE-DONE.md`, `docs/MARKET-RESEARCH.md`,
   `docs/PRODUCT-ROADMAP.md`. Do NOT fail if these are absent — masterkey
   may not have all of them. Log which ones are missing so the operator can
   fill the gap by hand if it matters for this mockup.
4. **Slug validation:** the argument must match `^[a-z0-9][a-z0-9-]*[a-z0-9]$`
   (lowercase kebab-case). If invalid, STOP with `→ Invalid slug '<value>' —
   use lowercase kebab-case, e.g. reading-pane-v2`.
5. **Output collision check:** if `docs/mockups/<slug>-<YYYY-MM-DD>.html`
   already exists for today's date, WARN and ask the operator whether to
   overwrite. The mockup file is per-day-per-slug — a same-day re-run means
   the operator is iterating, and overwrite is usually the intent.

## Compose the design brief

Extract these sections from the available docs:

| Section | Source (in preference order) |
|---|---|
| Product summary (1 paragraph) | `PRODUCT-REQUIREMENTS.md` → executive summary or first section |
| Target user + persona | `POSITIONING-ANALYSIS.md` (if present) → ICP + persona; else `PRODUCT-REQUIREMENTS.md` → user profile |
| Core jobs to be done (3-5 statements) | `JOBS-TO-BE-DONE.md` (if present); else derive from PRD's user journey |
| Screens to mock (5-8) | PRD's feature list, filtered to the ones the operator's slug covers |
| Competitive landscape | `MARKET-RESEARCH.md` (if present); else omit — flag as gap in the brief |
| Aesthetic / brand notes | Generic default: consumer-friendly, light theme (Notion / Linear-light). Masterkey has no brand-style doc; do NOT invent a palette |
| Realistic content | Derive from PRD examples, not lorem ipsum. Match the persona and domain |
| Explicit non-goals | Mockup is throwaway. Production stack is Jinja2 + HTMX per ADRs — mockup should NOT try to match that; whatever's cheapest to author is fine (Tailwind CDN is the empirical default) |

The brief must be ~200-500 words, structured, and copy-pasteable directly
into Claude Design or a Claude Artifacts conversation.

Include an explicit instruction to the generator: **the output must be a
single self-contained HTML file** (no build step, no external assets beyond
CDN Tailwind + Google Fonts). Multi-screen mockups use a left-nav rail
(`aside w-60`) that lets the reviewer step through screens in a single
browser tab.

## Path A — Claude Design (primary)

If the operator has access to Claude Design (Pro / Max / Team / Enterprise):

1. Emit the design brief in a fenced code block.
2. Emit these steps for the operator:
   1. Open [Claude Design](https://www.anthropic.com/news/claude-design-anthropic-labs).
   2. Paste the brief. Attach `docs/PRODUCT-REQUIREMENTS.md` and any of the
      soft docs that are present.
   3. Iterate with Claude Design's inline commenting / adjustment knobs
      until the mockup is close enough to react to substantively.
   4. Export as **standalone HTML**.
   5. Save the exported HTML to `docs/mockups/<slug>-<YYYY-MM-DD>.html`.
3. Write a placeholder file at
   `docs/mockups/<slug>-<YYYY-MM-DD>.html` containing:
   - Line 1: `<!-- SPDX-License-Identifier: BUSL-1.1 -->`
   - Line 2: `<!-- MOCKUP PLACEHOLDER — awaiting operator to paste Claude Design export. Slug: <slug>. Generated: YYYY-MM-DD. -->`
   - A minimal `<!doctype html>` skeleton with a `<title>` reflecting the
     slug, so opening the file in a browser confirms the path is correct.
4. Confirm with the operator: `→ Placeholder written to docs/mockups/<slug>-<YYYY-MM-DD>.html. Paste your Claude Design export over it when ready.`

## Path B — Claude Artifacts fallback

If Claude Design is not available (any Claude account still has Artifacts):

1. Emit the design brief in a fenced code block.
2. Emit these steps:
   1. Open a fresh conversation at [claude.ai](https://claude.ai).
   2. Paste the brief. Also paste the contents of
      `docs/PRODUCT-REQUIREMENTS.md` (and any soft docs, if referenced in
      the brief).
   3. Ask Claude to generate a single self-contained HTML mockup with a
      left-nav rail covering the 5-8 screens listed in the brief.
   4. Iterate 1-3 rounds via the Artifacts panel.
   5. Copy the final HTML into `docs/mockups/<slug>-<YYYY-MM-DD>.html`.
3. Write the same placeholder file described in Path A step 3 so the
   destination path exists.
4. Confirm as in Path A.

## SPDX header enforcement

The first line of every emitted `docs/mockups/*.html` MUST be:

```html
<!-- SPDX-License-Identifier: BUSL-1.1 -->
```

Masterkey is BSL 1.1; generated mockup HTML is derivative content and
inherits the license. If the operator's Claude Design export doesn't
include it, prepend the line manually before saving.

## After the operator lands the artifact

Once the real mockup HTML is in place (not the placeholder):

1. Open the file in a browser to confirm it renders.
2. Add a one-line entry to the current session journal
   (`reports/session-journals/YYYY-MM-DD.md`) linking the mockup and
   summarizing what the operator's reaction was. This is the audit
   trail — no `MOCKUP-APPROVAL.md` sidecar is needed.
3. If the mockup surfaces changes worth ticketing, use `/groom-backlog`
   or `/create-ticket` to file them. Reference the mockup file path in
   the ticket's Environment Context section.

## Output format

Report progress with per-step Progress Lines, then end with a Result Block:

```text
→ Preflight OK (hard: PRD + TECHNICAL-ARCHITECTURE; soft: 2/4 present)
→ Slug validated: reading-pane-v2
→ Composed 320-word design brief
→ Emitted Path A instructions (Claude Design)
→ Placeholder written to docs/mockups/reading-pane-v2-2026-07-02.html

---

**Result:** Mockup skill executed
Slug: reading-pane-v2
Placeholder: docs/mockups/reading-pane-v2-2026-07-02.html
Path: A (Claude Design)
Brief length: 320 words
Missing soft inputs: POSITIONING-ANALYSIS.md, MARKET-RESEARCH.md
Next: operator pastes Claude Design export over placeholder
```

If a hard input is missing, the Result Block reflects the halt:

```text
→ Preflight failed: docs/PRODUCT-REQUIREMENTS.md not found

---

**Result:** Preflight halted — /mockup did not run
Missing: docs/PRODUCT-REQUIREMENTS.md
Fix: run /bootstrap-product or restore the file from git history
```

## References

- Upstream prior-art plans (context only, not a runtime dependency):
  - [`vibeacademy/gembaflow-meta:plans/mockup-feature-spec.md`](https://github.com/vibeacademy/gembaflow-meta/blob/main/plans/mockup-feature-spec.md) (2026-06-04, PM product-shape)
  - [`vibeacademy/gembaflow-meta:plans/mockup-implementation-plan.md`](https://github.com/vibeacademy/gembaflow-meta/blob/main/plans/mockup-implementation-plan.md) (2026-06-04, framework-architect)
- Downstream retrofit synthesis (this fork's adoption reasoning):
  `reports/downstream-reports/2026-07-03-mockup-pressure-test.md`
- Reticle's mockup precedent (empirical single-file shape reference):
  `feature-x/reticle:docs/MOCKUP.html`
- Parent epic: #255 — `/mockup design-review skill (retrofit)`
- ADR-008 (when merged): `/mockup` as design-review skill (retrofit reframing)
