# Refactor Plan: `cubrox` -> `masterkey`

**Author:** System Architect persona
**Date:** 2026-06-29 (v4 revision 2026-06-30)
**Status:** REVISED (v4) — GCP pivot per operator decision 2026-06-30; v3 in-place-rename assumptions invalidated
**Scope locked by:** product owner (see task brief)

---

## Changelog

### v4.1 — 2026-06-30 — DevOps revision pass (addresses BC1/BC2/BC3 from `reports/refactor/02c-devops-signoff-v4.md`)

DevOps returned **NEEDS_REVISION** on v4 with three blockers, all order-of-operations / executability issues (the v4 architecture itself is sound). This revision addresses each in place:

- **BC1 resolved.** §6 reconciliation rows for #200 and #237 made explicit about the WIF dual-write contract. #200 is **REWORK, not CLOSE** — it executes the `cubrox/masterkey` binding as the dual-write step in the NEW project. #237's row gains a "**#237 body MUST include**" callout listing the corrected text the issue body needs to have (operator/orchestrator must edit #237 to match; this plan tells them what to write). Cross-referenced in §3 Phase 2 step 16's preamble.
- **BC2 resolved.** Phase 2 / §6 #237 callout now specifies the full 5-env-var (actually 6 if including `GITHUB_REPOSITORY` for Step 7's secret push) invocation contract for `provision-gcp-project.sh`. Confirmed by reading `scripts/provision-gcp-project.sh` lines 402-478: `WIF_OWNER` is sourced from `GITHUB_OWNER` (or legacy `GITHUB_USERNAME`), NOT from `GITHUB_REPO`. `WIF_REPO_NAME` is the bare repo name within the owner. Defaults `ARTIFACT_REPO=agile-flow` (line 60) and `CLOUD_RUN_SERVICE=agile-flow-app` (line 800) WILL fire if not overridden. Required invocation documented in #237's body spec.
- **BC3 resolved.** Phase 2 step 16's WIF verification mechanism changed from `rollback-production.yml workflow_dispatch` (which mutates traffic — `gcloud run services update-traffic` is not zero-side-effect) to `synthetic-monitor.yml workflow_dispatch` (which auths via WIF and probes the service URL with no traffic-shift). `synthetic-monitor.yml`'s `workflow_dispatch` trigger continues to work even when its `schedule:` block is commented out per Phase 1 step 13. R3 mitigation text updated to match.

**Five new risks added to §4 from DevOps's review:** R21 (AR repo `agile-flow` default), R22 (placeholder Cloud Run service has no env vars; R13 still applies on first real deploy), R23 (API-enable list mismatch between #237 body and the script), R24 (Supabase webhooks unaffected — informational, no action), R25 (legacy GCP project may still be accruing charges despite IAM loss; operator should escalate via billing org).

**Not changed:** every v4 piece DevOps accepted (Phase -1 status, Phase 1 unchanged, Phase 4 collapse to 3 steps, Phase 5 reduction, R19/R20 framing, dependency graph) is preserved unmodified.

### v4 — 2026-06-30 — GCP pivot: legacy production project inaccessible; provision new GCP project as `masterkey` from day 1

**What happened.** The operator lost access to the production GCP project that hosted the `agile-flow-app` Cloud Run service, deployer SA, WIF binding, Artifact Registry repo, and Secret Manager entries. The fork's existing production runtime (`agile-flow-app-heo5ry7rua-uc.a.run.app`) is orphaned — still serving from a no-longer-managed runtime, but we cannot touch it, snapshot it, rename it, or delete it. Operator's locked decisions, captured in #237's body:

1. **Provision a fresh new GCP project as `masterkey` from day 1.** Skip the legacy `agile-flow-app` naming entirely. The Cloud Run service is `masterkey`, the AR repo is `masterkey`, and the GitHub repo `vars` (`CLOUD_RUN_SERVICE=masterkey`, `ARTIFACT_REPO=masterkey`) are set as part of provisioning — not in a separate flip step.
2. **Supabase project `gnswmcgaztcxslirulwm` is unchanged.** Still accessible, still the data plane. No data migration.
3. **Close #189 (WIF binding verification) as not-planned** — already done 2026-06-30 — and file #237 for the new-project provisioning. Both actions completed before this v4 revision.

**What this invalidates from v3.** The v3 plan's core assumption ("rename Cloud Run service `agile-flow-app` → `masterkey` in place, keep GCP project ID") no longer holds:

- **Phase 0 step 2 snapshots** of the old service / revisions / SA IAM / secrets list are unobtainable (no access to the old project). The four `snapshots/*.pre-rename.yaml` files are not gettable; Phase 0's `S2`-mandated artifacts collapse to the GitHub-only inventory work (#187).
- **Phase 2 step 16 (WIF dual-write)** is moot — there's no old `cubrox/cubrox` binding to dual-write from. #237 provisions WIF cleanly in the new project, bound to `cubrox/cubrox` initially (since the repo isn't renamed yet). The remaining decision (folded into Phase 2 below): after `gh repo rename` (step 17 / E3-T2), either add a SECOND WIF binding for `cubrox/masterkey` then prune the old one, or re-run the provision script's WIF setup pointing at the renamed repo.
- **Phase 3 (Cloud Run + AR preparation)** mostly collapses into #237. The "pre-create masterkey AR repo + Cloud Run service in the same project as the old one" sequence becomes "the new project IS the masterkey project, and its first deploy IS the masterkey service" — no pre-create-then-cutover dance needed. Phase 3 becomes a verification-only stage post-#237: confirm the new service is healthy, capture its URL, update Supabase Auth allowlist with the new URLs, and (if desired) run a dry-run preview-deploy.
- **Phase 4 (Cutover)** is dramatically simplified. The v3 var-flip race window (B7) does not exist — there is no old GCP project to flip FROM. `vars.CLOUD_RUN_SERVICE=masterkey` and `vars.ARTIFACT_REPO=masterkey` are set as part of #237's GitHub-secrets / vars rotation; from that point onward, all CI deploys (preview AND production) land on the new `masterkey` service. The Phase 1 PR merge's `deploy.yml` run lands on `masterkey` directly — not on `agile-flow-app` first then re-deployed after a flip.
- **Phase 5 cleanup** loses three of its most destructive steps: we cannot delete the old Cloud Run service (no access), cannot delete the old AR repo (no access), and cannot prune the old WIF binding in the old project (no access). The legacy production URL `agile-flow-app-heo5ry7rua-uc.a.run.app` continues to resolve from the orphaned runtime indefinitely — we have to enumerate external references and either redirect or replace them (new R20).

**What survives unchanged from v3.**

- **Phase -1 (framework alignment to gembaflow v1.5.0)** is DONE — closed via PR #232 (2026-06-30) and follow-up PRs #235 (#234 closed) and #236 (#233 closed). The local fork is at v1.5.0 with `.gembaflow-*` dotfiles.
- **Phase 1 (codebase rename PR)** is entirely unaffected by the GCP pivot. The 8 sub-tickets (#192-#199) cover identifier renames in `app/`, `tests/`, `templates/`, `ci.yml`, the two `.gembaflow-overrides`-listed scripts, agent persona files, `supabase/config.toml`, and the synthetic-monitor schedule disable. The preview-deploy concern from v3 Phase 1 step 15 (preview goes to the old service) is resolved differently: once #237 lands, the preview-deploy lands on `masterkey` from the start.
- **Repo rename (#201 / E3-T2)** is unchanged — still `gh repo rename masterkey`, still triggers cascade local-remote updates, still needs Supabase GitHub App allowlist verification (R10).
- **Project board migration (#202 + #203)** — #202 (create new board) is partially done (board #2 created on the cubrox user account); ticket-content migration of 67 items (#203) is still valid work.
- **Supabase GitHub App allowlist re-verification** (#209 / E4-T6) still valid post-repo-rename.
- **Memory MCP audit (#222), ADR-007 (#223), Cloud Logging filter updates (#221)** — all still valid, mostly cosmetic post-pivot.
- **Synthetic monitor disable/restore (#199 / #215)** still valid — the cron risk during cutover is the same shape regardless of GCP project identity.

**Risk register changes.**

- **R3 (WIF binding correctness)** — RESOLVED. #237 provisions WIF cleanly in the new project from day 1; the dual-write dance is replaced by a single binding that will need adjustment after the repo rename (handled by re-running `scripts/provision-gcp-project.sh` against the new repo name, OR by an explicit add-binding then remove-binding pair).
- **R19 (NEW)** — GCP billing on the new project. Operator's billing org may have quota or cost surprises (default Cloud Run service quotas vs. project, AR storage cost, Cloud Logging cost). Mitigation: enable billing alerts during #237.
- **R20 (NEW)** — DNS / external links pointing at the legacy production URL `agile-flow-app-heo5ry7rua-uc.a.run.app`. Anything linking to it will 404 or serve a stale runtime once the new prod URL is live. Need to enumerate external references (`rg agile-flow-app-heo5ry7rua` across the repo + Slack history + any blog posts) and either redirect or accept-and-document.
- All other risks (R1, R2, R4-R18) that don't depend on the old project survive unchanged.

**Ticket renumbering.** None. v3's E-series IDs are preserved; v4 reuses them with explicit reconciliation actions documented in the new **§6 Backlog reconciliation post-pivot** table below. v3's "Phase 2 step 16" WIF dual-write is removed (now an explicit "DROP" row in §6 against #200); the Phase 4 var-flip steps (E5-T3, E5-T4) become trivial "verify vars already set" rather than actively flipping. Old step numbers 27-40 remain referenced in the §3 phase descriptions but are flagged "OBSOLETE" where the GCP pivot eliminates their substance.

**One-paragraph net effect.** The pivot turns the most operationally fragile parts of v3 (the dual-state Cloud Run window, the var-flip race, the WIF dual-write timing, the destructive Phase 5 deletions) into "non-events" — they collapse into #237's clean from-scratch provisioning. The remaining work is mostly: do Phase 1 (codebase rename) as planned, rename the repo, migrate the board contents, and audit the new production URL. The trade-off is permanent loss of the legacy `agile-flow-app` runtime (we can't snapshot, can't roll back to it, can't gracefully redirect from it) — but since we'd lost ownership anyway, that trade was already made.

### v3 — 2026-06-29 — added Phase -1 (framework alignment) per user request 2026-06-29

- **Phase -1 added** to §3 BEFORE the existing Phase 0. Aligns the local fork with upstream's rebrand (`vibeacademy/agile-flow` → `vibeacademy/gembaflow`) and upgrades v1.3.0 → v1.5.0. Covers metadata-file renames (`.agile-flow-*` → `.gembaflow-*`), local `template-sync.sh` path edits, doc-string updates ("Agile Flow" → "Gemba Flow"), the v1.5.0 release notes' mandated **manual `curl` refresh of runtime-protected scripts**, the actual `/upgrade` run, and reconciliation of the overrides list against any upstream agent-file renames.
- **Reason this lands first:** upstream v1.5.0's `template-sync.sh` contains an early-exit one-time migration block that does `git mv .agile-flow-version .gembaflow-version` (and same for `.agile-flow-meta/`, `.agile-flow-overrides`) before doing the sync. The masterkey rename touches the SAME files (e.g., `E2-T5` edits paths governed by `.agile-flow-overrides`; `E2-T7` edits files listed in `.agile-flow-overrides`). If masterkey Phase 0 lands first, the next `/upgrade` would mid-rename our overrides file or fight the auto-migration, producing dual-state (`.agile-flow-overrides` AND `.gembaflow-overrides` both present until manual cleanup).
- **New rollback point RB-(-1)** documented.
- **Three Phase -1-specific risks added** to §4: R16 (upstream agent-file renames colliding with our overrides), R17 (`.gembaflow-config.example.json` is a new file expecting fork-specific values), R18 (the manual-curl refresh of `template-sync.sh` is itself a bootstrap-of-the-bootstrapper — if the curl fails or the wrong tag is fetched, the sync runs the old logic and leaves dual-state).
- Step renumbering: v2 used steps 1-40. v3 inserts steps numbered **(-1).1 through (-1).7** in the new Phase -1 (single hyphenated namespace, deliberately separate from the 1-40 numbering so no downstream cross-references break). Phase 0 onward unchanged.

### v2 — 2026-06-29 — incorporated DevOps review (`reports/refactor/02-devops-review.md`)

- **B1:** Added `.github/workflows/ci.yml:218,307,315` to §2.4 inventory and Phase 1 step 8. It inlines `CUBROX_TEST_SEED_ENABLED` literally — not a `vars.*` indirection — so a `vars` flip cannot cover it. Edit the file in the Phase 1 PR.
- **B2:** Rewrote R3 mitigation and added a dedicated Phase 2 step 16 (WIF dual-write). WIF is wired with a trivially-true attribute condition at the provider; the per-repo pin lives on the deployer SA's IAM policy as a `principalSet` member with BOTH `roles/iam.workloadIdentityUser` AND `roles/iam.serviceAccountTokenCreator`. The actual fix is to add a second SA IAM binding for `cubrox/masterkey` BEFORE the repo rename (step 17) and remove the old one in Phase 5 step 38. The "edit attribute condition" path I originally proposed is impossible.
- **B3:** Added explicit guard rail to Phase 3 step 23: do NOT use `--set-secrets` for `DATABASE_URL` or `ANTHROPIC_API_KEY` on the new `masterkey` service. Cloud Run's literal-vs-secret env-var type is sticky; switching mid-cutover would brick `deploy.yml`. Added as new risk R13.
- **B4:** `scripts/provision-gcp-project.sh` lines 800 + 1011 and `scripts/diagnose-cloudrun.sh` line 35 are now in scope. Both files are listed in `.agile-flow-overrides` (verified), so editing them does not fight `template-sync.sh`. Updated §2.5; folded into Phase 1 step 9.
- **B5:** Phase 3 step 24 now ends with capturing the new service URL via `gcloud run services describe ... --format='value(status.url)'` and pinning it into `docs/LAUNCH-CHECKLIST.md` line 10 (amend the still-open Phase 1 PR; or follow-up doc PR if Phase 1 has already merged).
- **B6:** R6 reworded to mention the real consequence — `pyproject.toml:name` is referenced by `[tool.*]` config blocks and `uv build` wheel filenames — so a future renamer must audit those. We still are not renaming today.
- **B7:** Re-sequenced Phase 4 to eliminate the var-flip-before-merge race. New order (steps 27-34): (1) merge Phase 1 PR with vars still pointing at the OLD service, which deploys the rename code to `agile-flow-app` and proves the rename is a live no-op; (2) verify health on the old service; (3) flip `vars.CLOUD_RUN_SERVICE` and `vars.ARTIFACT_REPO`; (4) push a trivial commit to `main` to trigger `deploy.yml` against the new service.
- **R10 added:** Supabase GitHub App may track the repo by `owner/name` vs `repository.id`. Verify the App allowlist still contains `cubrox/masterkey` post-rename (Phase 2 step 17).
- **R12 added:** Supabase Auth allowlist almost certainly has a preview-PR pattern (`https://pr-*---agile-flow-app-*.run.app/auth/callback`). Add the new `pr-*---masterkey-*.run.app` pattern in Phase 3 step 26.
- **R13 added:** Cloud Run env-var type stickiness (from B3).
- **R14 added:** Cloud Run services-per-region quota during the dual-service window (FYI; not a real risk, default quota is ~1000/region).
- **R15 added:** Fork-redirect breakage for any external `cubrox/cubrox` forks (probably none; verify via `gh api repos/cubrox/cubrox/forks` in Phase 0 step 6).
- **Q1, Q2, Q3, Q4, Q5, Q6, Q7, Q8, Q9, Q10:** All ten open questions resolved per DevOps's answers; moved from "Open questions" to "Resolved decisions" in §5.
- **S1 deferred** as a separate follow-up; **S5** (`.claude/PROJECT.md` Supabase fix) folded into the Phase 1 PR as a 5-line cosmetic; **S6** folded into the §2.6 `CLAUDE.md` row.
- **S2 applied:** Phase 0 step 2 now captures revisions, SA IAM policy, and secrets list in addition to the service spec.
- **S3, S4 applied:** S3 verification command added under §2.1 and Phase 2 step 17; S4 dry-run PR is now explicit Phase 3 step 25.
- **C11, C12, C13, C14, C15 etc.:** confirmations folded silently — claims I made correctly are kept as-is.

**Step renumbering note:** v1 used steps 1-31 across 5 phases. v2 inserts (a) Phase 0 step 4 (Cloud Logging enumeration), (b) Phase 0 step 6 (forks check), (c) Phase 1 step 11 (.claude/PROJECT.md fix), (d) Phase 1 step 13 (synthetic-monitor disable), (e) Phase 2 step 16 (WIF dual-write), (f) Phase 3 step 25 (dry-run PR), (g) Phase 4 split into steps 27-34, (h) Phase 5 step 38 (WIF prune). v2 uses steps 1-40 sequentially. All §2/§4/§5 cross-references in this revision use the new numbering.

---

## 1. Executive summary

**v4 update (2026-06-30):** the GCP pivot reshapes this summary. Bullets below are kept for v3 context; v4-specific framing is added inline as **v4 notes**.

- **The rename is a codebase / infra identifier change, not a brand change.** The user-facing product is already "Master Key" in `templates/home.html`, `passages_new.html`, `reading.html`, and `tests/test_home.py`. The string "Cubrox" only appears in technical artifacts: repo slug, package metadata, env-var prefixes, browser globals, Supabase project-id (local), test-seed package name, and developer docs. No marketing copy or sign-in flow needs to change. **v4 unchanged.**
- **Two distinct namespaces collapse into one after this work.** Today the repo is `cubrox/cubrox` on GitHub (confirmed via `git remote`), but the project board is still on the legacy `vibeacademy` org (`orgs/vibeacademy/projects/29`). After the rename, both will live under `cubrox/*` — repo at `cubrox/masterkey`, new board at `users/cubrox/projects/<new-id>` (note: cubrox is a user account, not an org — board #2 already created 2026-06-30). All tickets migrated via #203.
- ~~**The Cloud Run service is currently named `agile-flow-app`, not `cubrox`.**~~ **v4 REPLACES:** The legacy Cloud Run service `agile-flow-app` lives in a GCP project the operator lost access to 2026-06-30. It is orphaned and outside our control. #237 provisions a brand-new GCP project, and the Cloud Run service in that project is named `masterkey` from day 1. **There is no destructive Cloud Run service rename in v4** — the new service simply doesn't exist until #237 creates it.
- **Ephemeral preview deploys are the most fragile surface.** They depend on a per-service revision tag (`pr-N`) and a comment on the PR. **v4 update:** the atomic-flip-with-rename concern is dissolved — once #237 sets `vars.CLOUD_RUN_SERVICE=masterkey`, all preview deploys go to the new service from then onward, with no flip event to coordinate.
- **Framework artifacts (Gemba Flow) stay named as-is.** `pyproject.toml`'s `name = "agile-flow-gcp"` is the framework template name, not the product. (Note: v3 said "Agile Flow"; Phase -1's framework upgrade made this "Gemba Flow" at the framework layer.) **However**, two `.gembaflow-overrides`-listed scripts (`provision-gcp-project.sh`, `diagnose-cloudrun.sh`) DO need edits — they hardcode `agile-flow-app` as the default service name (B4). v4 note: `provision-gcp-project.sh` was used to provision the new project via #237, so its rename matters going forward for any future operator re-running it.
- **WIF authentication is no longer the highest-leverage "stuck in the middle" failure mode in v4.** The fresh provisioning in #237 establishes a known-good baseline; Phase 2 step 16's dual-write (now executed against the new project, not the legacy one) handles the residual repo-rename risk. **The new highest-leverage risk in v4 is R19 (GCP billing surprises) and R20 (orphaned legacy URL still serving from the inaccessible project).**

---

## 2. Inventory

### 2.1 GitHub repo + org

| Item | What changes | Notes |
|------|--------------|-------|
| Repo slug | `cubrox/cubrox` -> `cubrox/masterkey` | `gh repo rename masterkey` from a clone on the default branch. Org stays `cubrox`. |
| Local git remote | `git@github.com:cubrox/cubrox.git` -> `git@github.com:cubrox/masterkey.git` | `git remote set-url origin` after the rename. GitHub serves a 30-day HTTP redirect, but git's SSH transport doesn't honor it — relying on the redirect silently breaks `git push` on every developer machine. |
| Working-tree directory | Optional: `/Users/teddykim/projects/cubrox/cubrox` -> `/Users/teddykim/projects/cubrox/masterkey` | Cosmetic only; does NOT affect git. `cd` paths in CLAUDE/agent context will need to be re-read if the dir is moved. |
| GitHub Actions secrets | No rename needed | `GCP_PROJECT_ID`, `GCP_SERVICE_ACCOUNT`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SA_KEY`, `PRODUCTION_DATABASE_URL`, `ANTHROPIC_API_KEY`, `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_URL` are repo-scoped, not name-scoped. They follow the repo through the rename. |
| Workload Identity Federation binding | **Dual-write before rename, prune after** | The WIF provider's attribute condition is trivially true (`assertion.repository != ''`, per `provision-gcp-project.sh:439`). The repo pin lives on the deployer SA's IAM policy as `principalSet://.../attribute.repository/cubrox/cubrox` with BOTH `roles/iam.workloadIdentityUser` AND `roles/iam.serviceAccountTokenCreator` (per `provision-gcp-project.sh:465-474`). Phase 2 step 16 adds a parallel binding for `cubrox/masterkey` BEFORE the rename. The old binding is removed in Phase 5 step 38. |
| GitHub Pages / repo description / topics | Cosmetic | None configured; nothing to change. |
| Branch protection ruleset (id `15886599`) | Auto-preserved by GitHub rename | Uses `~DEFAULT_BRANCH` sentinel (verified). After Phase 2 step 17, re-run `gh api repos/cubrox/masterkey/rulesets` to confirm the ruleset still applies. |
| GitHub Webhook / App installations | Auto-preserved by GitHub rename | The Supabase GitHub App (for per-PR branching) is installed at the org level and watches selected repos — verify `cubrox/masterkey` is still in the repo allowlist after the rename (see R10). |
| Project board (legacy) | `https://github.com/orgs/vibeacademy/projects/29` -> closed after migration | Source-of-truth ticket data. Read all items (open + closed) before tearing down. |
| Project board (new) | Create `https://github.com/orgs/cubrox/projects/<n>` | Mirror columns: Backlog / Ready / In Progress / In Review / Done. Re-add automation for status moves. |
| Ticket migration | All issues + PRs cross-linked to board | Use `gh api graphql` with `addProjectV2ItemById`. Closed tickets count toward the history; do not omit them. |
| External forks (FYI) | Confirm none exist | `gh api repos/cubrox/cubrox/forks --jq '.[].full_name'`. If any, warn the fork owners that their `origin` URL will redirect for 30 days then break. See R15. |

### 2.2 Code / application

| File | Identifier | Change | Justification |
|------|------------|--------|---------------|
| `pyproject.toml` | `name = "agile-flow-gcp"` | **NO change** | This is the framework starter name from the upstream template. Renaming it would diverge from `vibeacademy/agile-flow-gcp` and break `template-sync.sh` (which diffs files against upstream releases). The Python package on disk is `app/`, not `cubrox/`, so the project name string only appears in distribution metadata — and we don't publish to PyPI. **Leave it.** See R6 for the audit-debt note about `[tool.*]` config blocks if a future maintainer ever does rename it. |
| `app/main.py:19` | `FastAPI(title="Agile Flow GCP")` | -> `FastAPI(title="Master Key")` | This title surfaces in `/docs` (OpenAPI) and in error pages. "Master Key" matches the public brand already used in templates. |
| `app/main.py:59-64` | `CUBROX_TEST_SEED_ENABLED` env var | -> `MASTERKEY_TEST_SEED_ENABLED` | Codebase identifier. Coordinated change with `app/api/test_seed.py`, `tests/test_test_seed_guard.py`, `tests/a11y/playwright.config.ts`, **`.github/workflows/ci.yml:218,307,315`** (see §2.4 — B1), and the CI workflow. |
| `app/api/test_seed.py:32,41,66,71` | Same env var | Same | Module-level guard. |
| `app/api/home.py:5` | Docstring "Cubrox landing page" | -> "Master Key landing page" | Doc comment only. |
| `app/services/ingestion/pdf.py:5` | Docstring "...onto Cubrox" | -> "...onto Master Key" | Doc comment only. |
| `app/scripts/metric.py:30` | `prog="cubrox-metric"` | -> `prog="masterkey-metric"` | CLI program name shown in `--help`. |
| `templates/pages/reading.html:49,60,73,79` | `window.cubroxLineCount` | -> `window.masterkeyLineCount` | Browser global. Must be changed in lock-step with `tests/test_passage_close.py:221,228,234`. |
| `tests/test_passage_close.py:221,228,234` | `window.cubroxLineCount` assertions | Same | Test pins the global name. |
| `tests/test_test_seed_guard.py:25,42,53,56` | `CUBROX_TEST_SEED_ENABLED` | -> `MASTERKEY_TEST_SEED_ENABLED` | Test of the env-var guard. |
| `tests/test_seed_route.py:5` | Docstring | Update env-var name | Doc-only. |
| `tests/test_home.py:97` | "'Cubrox' remains the internal codebase identifier" | -> "'Master Key' is both internal and public; 'masterkey' is the codebase identifier" | Doc comment in test (intent has flipped post-rename). |
| `tests/a11y/package.json:2` | `"name": "cubrox-a11y-tests"` | -> `"name": "masterkey-a11y-tests"` | npm package name (local-only; not published). |
| `tests/a11y/package-lock.json:2,7` | Same | Same | Regenerated by `npm install`. |
| `tests/a11y/README.md:1,16,38,40,74` | "Cubrox accessibility tests" + env var | Update doc + env var | Doc + env-var name in run instructions. |
| `tests/a11y/playwright.config.ts:65` | `CUBROX_TEST_SEED_ENABLED: "true"` | -> `MASTERKEY_TEST_SEED_ENABLED: "true"` | Sets the env on the FastAPI subprocess. |
| `tests/a11y/fixtures/seed.ts:16` | Doc comment | Update env-var name | Doc-only. |
| `tests/test_auth_login.py:73,78` | `pr-42---agile-flow-app-xyz.run.app` | -> `pr-42---masterkey-xyz.run.app` | Test fixture; the test asserts that `_external_origin` returns the exact `X-Forwarded-Host` it received — the string itself has no semantic dependency on the service name (per R11). Rename for **coherence** only; it is not a test of the new naming. |

### 2.3 Infrastructure (GCP)

| Resource | Today | After | Strategy |
|----------|-------|-------|----------|
| Cloud Run service | `agile-flow-app` | `masterkey` | **Destructive recreate** — Cloud Run doesn't support in-place rename. See Order of Operations §3.4. |
| Artifact Registry repo | `agile-flow` | `masterkey` | New AR repo (cheap, no data to migrate). Old repo stays for **30 days** post-cutover (per resolved Q4) before cleanup. |
| Container image tags | `us-central1-docker.pkg.dev/$PROJECT/agile-flow/agile-flow-app:<sha>` | `us-central1-docker.pkg.dev/$PROJECT/masterkey/masterkey:<sha>` | First post-rename `deploy.yml` push creates the new tag. |
| GCP project ID | (kept) | (unchanged) | Per locked scope. |
| Supabase project ref | `gnswmcgaztcxslirulwm` | (unchanged) | Per locked scope. No data migration. |
| Service Account | (kept) | (unchanged) | Same SA continues to run the new Cloud Run service. |
| WIF binding on deployer SA | `principalSet://.../cubrox/cubrox` with `workloadIdentityUser` + `serviceAccountTokenCreator` | **Add** `principalSet://.../cubrox/masterkey` with both roles BEFORE rename; **remove** the old binding in Phase 5 | Per-repo binding kept narrow (resolved Q5 — no org-wide widening). |
| Secret Manager secrets | `supabase-url`, `supabase-anon-key`, `supabase-service-key` | (unchanged names) | These names don't contain "cubrox"; they're already generic. Renaming costs a coordinated 4-step dance for zero functional benefit (resolved Q3). **Leave as-is.** |
| Cloud Logging filter / Error Reporting | Filters on `resource.labels.service_name="agile-flow-app"` | Update saved queries to `="masterkey"` | Enumerate via `gcloud logging metrics list`, `gcloud alpha monitoring policies list`, `gcloud monitoring dashboards list` before Phase 4 (resolved Q7). Most likely returns empty per ADR-004 (Sentry deferred, no custom dashboards) — but verify; alerts that don't fire after the rename look like silence. Error Reporting auto-groups by stack trace, unaffected. |
| Cloud Monitoring alerts | (enumerate per Q7) | (update if any exist) | Same source as above. |
| Synthetic monitor URL | Resolves dynamically via `gcloud run services describe` (see `synthetic-monitor.yml:104-107`) | Auto-follows the new service name once `vars.CLOUD_RUN_SERVICE` is updated | No code change needed; the indirection saves us. |

### 2.4 CI/CD (GitHub Actions)

Most workflows read `vars.CLOUD_RUN_SERVICE` and `vars.ARTIFACT_REPO` with framework defaults — for those, **the fix is to set the repo variables, not to edit the workflow files** (avoids `template-sync.sh` conflict). The exception is `ci.yml`, which inlines `CUBROX_TEST_SEED_ENABLED` literally (B1) and must be edited.

| Workflow file | Today | Change |
|---------------|-------|--------|
| `.github/workflows/ci.yml:218,307,315` | Comments + `env: CUBROX_TEST_SEED_ENABLED: 'true'` inline literal | **Edit file directly in Phase 1 PR.** Rename to `MASTERKEY_TEST_SEED_ENABLED`. This is NOT a `vars.*` reference — a `vars` flip cannot reach it. If left unchanged, the a11y job's uvicorn subprocess receives the old env name, the test-seed router never mounts, every Playwright test 404s on `/test/seed`, and Phase 1 CI goes red. (B1) |
| `.github/workflows/deploy.yml:25-26` | `ARTIFACT_REPO: ${{ vars.ARTIFACT_REPO OR 'agile-flow' }}` / `SERVICE_NAME: ${{ vars.CLOUD_RUN_SERVICE OR 'agile-flow-app' }}` (OR = literal `&#124;&#124;`) | **No file edit.** Set GitHub repo `vars.CLOUD_RUN_SERVICE = masterkey` and `vars.ARTIFACT_REPO = masterkey` so the default is bypassed. |
| `.github/workflows/preview-deploy.yml:27-28` | Same pattern | Same — repo `vars` only. |
| `.github/workflows/preview-cleanup.yml:20` | `SERVICE_NAME: ${{ vars.CLOUD_RUN_SERVICE \|\| 'agile-flow-app' }}` | Same — repo `vars` only. |
| `.github/workflows/synthetic-monitor.yml:46` | Same | Same. **Plus** disable schedule for the cutover window per resolved Q9 (comment out `schedule:` block in Phase 1 step 13; restore in Phase 4 step 32 via a small follow-up PR). |
| `.github/workflows/rollback-production.yml:27` | Same | Same. |
| `.github/workflows/*.yml` `if: github.repository != 'vibeacademy/agile-flow-gcp'` guards | Six workflows have this guard | **No change.** The guard prevents deploys on the upstream framework template; our repo is neither `vibeacademy/agile-flow-gcp` nor will it be `cubrox/masterkey`. The guard keeps doing its job. |
| `.github/workflows/baseline-migrations.yml` | One-time workflow | Same upstream-guard pattern; no change needed. |
| `.github/workflows/template-sync.yml` (if present) | Pulls from upstream framework | No change. |

### 2.5 Scripts

| Script | Item | Change |
|--------|------|--------|
| `scripts/smoke_auth.py:52` | Docstring sample URL `cubrox-xxxxx-uc.a.run.app` | -> `masterkey-xxxxx-uc.a.run.app` (doc only) |
| `scripts/smoke_auth.py:86` | `SMOKE_EMAIL_DOMAIN = "smoke.cubrox.test"` | -> `"smoke.masterkey.test"` (used only as a leak-detection tag in Supabase user lists; cosmetic but coherent) |
| `scripts/diagnose-cloudrun.sh:35` (also doc-comment line 23) | `SERVICE="${CLOUD_RUN_SERVICE:-agile-flow-app}"` | -> `SERVICE="${CLOUD_RUN_SERVICE:-masterkey}"` (also update line 23 comment). **In scope per B4** — this script IS listed in `.agile-flow-overrides` (verified), so editing does not fight `template-sync.sh`. New workshop operators running `/diagnose-cloudrun` would otherwise hit the wrong default. |
| `scripts/provision-gcp-project.sh:800` | `SERVICE_NAME="${CLOUD_RUN_SERVICE:-agile-flow-app}"` | -> `SERVICE_NAME="${CLOUD_RUN_SERVICE:-masterkey}"`. **In scope per B4** — file IS in `.agile-flow-overrides` (verified). New GCP project provisioning would otherwise create a service named `agile-flow-app` that doesn't match `vars.CLOUD_RUN_SERVICE=masterkey`, orphaning the first deploy. |
| `scripts/provision-gcp-project.sh:1011` | `echo "   CLOUD_RUN_SERVICE      = agile-flow-app"` | -> `echo "   CLOUD_RUN_SERVICE      = masterkey"`. **In scope per B4.** This is the post-script "next steps" output; an operator following its instructions would otherwise set the wrong var name. |
| `scripts/doctor.sh` | No `cubrox` references found | No change |
| `scripts/template-sync.sh` | Sync from upstream `vibeacademy/gembaflow` | No change — upstream framework reference, not project-specific (R14). |

### 2.6 Docs

| File | Change |
|------|--------|
| `CLAUDE.md:164-166,175,195` | `Project Name: Cubrox` -> `Project Name: Master Key (codebase: masterkey)`. Repo URL -> `https://github.com/cubrox/masterkey`. Project Board URL -> new `cubrox` org board URL. `Organization: vibeacademy` -> `Organization: cubrox`. `docker build -t agile-flow-app .` -> `docker build -t masterkey .`. **Also add the new production Cloud Run URL** here once known (per S6), so `/doctor` and future agent sessions discover it without re-reading old runbooks. |
| `docs/PRODUCT-REQUIREMENTS.md:5` | `Name: Cubrox (working name — TBD)` -> `Name: Master Key (public) / masterkey (codebase)` |
| `docs/PRODUCT-ROADMAP.md:107` | Change-log row attributing initial roadmap to "cubrox" — doc only, leave as historical record OR replace with "masterkey". Historical attribution preferred; keep as `cubrox` (footnote: "former internal codename"). |
| `docs/TECHNICAL-ARCHITECTURE.md:5,518` | "Cubrox is a server-rendered..." -> "Master Key is...". ADR-006 line 518 "cubrox owned and had to maintain" -> "the project owned and had to maintain" (or leave as historical narrative — ADRs are immutable post-acceptance per the doc's own convention; choice: write a tiny **ADR-007 "Rename to Master Key / masterkey"** and leave ADR-006 untouched). |
| `docs/LAUNCH-CHECKLIST.md:10,12,45-46,51` | Production URL `agile-flow-app-heo5ry7rua-uc.a.run.app` -> new `masterkey-*.run.app` URL. **The new hash is unknowable until Phase 3 step 23 actually creates the service** (per B5). Phase 3 step 24 captures it and pins it here. Repo + board URLs updated. |
| `docs/PATTERN-LIBRARY.md:1368` | "Cubrox chose (1)" -> "We chose (1)" or "Master Key chose (1)" — purely narrative. |
| `docs/PATTERN-LIBRARY.md:1098,1105,1171,1187,1213` | Example `agile-flow-app` -> `masterkey` in code snippets. Cosmetic (these are illustrative). |
| `docs/PLATFORM-GUIDE.md:76,349,699,861,897,902,904` | Same — `agile-flow-app` -> `masterkey`. **But this is an upstream-synced doc** — likely fights `template-sync.sh`. Decision: leave the upstream version intact, append a project-specific overrides note OR add `docs/PLATFORM-GUIDE.md` to `.agile-flow-overrides` and edit freely. |
| `docs/CI-CD-GUIDE.md:99` | Same — same decision tree as above. |
| `docs/FAQ.md` | (verify) — likely no rename needed |
| `docs/GETTING-STARTED.md` | (verify) — upstream framework doc; likely no rename |
| `docs/MEMORY-ARCHITECTURE.md` | (verify) |
| `README.md` | (verify; mostly framework boilerplate from `vibeacademy/agile-flow-gcp`) |
| `CHANGELOG.md` | Add entry: "Renamed codebase identifier `cubrox` -> `masterkey`. No user-facing change; public product name remains `Master Key`." Used as the trivial commit that triggers the post-cutover `deploy.yml` run (Phase 4 step 30). |
| `reports/session-journals/2026-05-25..2026-06-05.md` | **No change** — session journals are historical record. |

### 2.7 Agent + framework artifacts (Agile Flow)

| Item | Change |
|------|--------|
| `.agile-flow-version` | `upstream: https://github.com/vibeacademy/agile-flow` — **no change** (correct upstream). |
| `.agile-flow-overrides` | Add `docs/PLATFORM-GUIDE.md`, `docs/CI-CD-GUIDE.md` if we choose to edit those (see §2.6). |
| `.agile-flow-meta/version` | No change. |
| `.claude/PROJECT.md` | This is project-specific (not synced). Lines 7-9 reference Neon, but the project is on Supabase — **already stale**. Per S5, fold the 5-line Supabase fix into the Phase 1 PR alongside the rename — it removes ongoing stale-context confusion for every agent that reads this file. |
| `.claude/agents/github-ticket-worker.md:33` | "Product: Cubrox" -> "Product: Master Key (codebase: masterkey)". Listed in `.agile-flow-overrides` — safe to edit. |
| `.claude/agents/system-architect.md` | Verify (system architect persona is overridden; safe to edit). The product-specific bounded-context section already says "Reading Surface", not "Cubrox" — likely no edit. |
| `.claude/agents/devops-engineer.md:72,307-324` | Examples reference `agile-flow-app`. Listed in `.agile-flow-overrides` — safe to edit to `masterkey`. |
| `.claude/commands/eli5.md:18-19` | `vibeacademy/cubrox` prototype reference — leave as historical attribution (the eli5 command IS from upstream `agile-flow` / `gembaflow`, this is its provenance). |
| Other `.claude/agents/*.md`, `.claude/commands/*.md`, `.claude/skills/*.md` | Spot-check; upstream-synced; do not edit unless project-specific. |

### 2.8 Supabase

| Item | Change |
|------|--------|
| Supabase project (remote, `gnswmcgaztcxslirulwm`) | **No change** to project ref, schema, or data. |
| `supabase/config.toml:9` | `project_id = "cubrox"` -> `project_id = "masterkey"`. This is the **local Supabase CLI workspace identifier** — affects only `supabase start` / local Docker container naming. No impact on the remote. |
| `supabase/config.toml:5` | Comment `Org: vibeacademy` -> `Org: cubrox` (or whatever the Supabase org actually is — verify in dashboard; not necessarily a GitHub-org match). |
| Supabase Auth redirect allowlist (production URL) | **Add** `https://masterkey-<hash>-uc.a.run.app/auth/callback` (Phase 3 step 26) alongside the existing `agile-flow-app-*` URL. Remove the old one in Phase 5 step 37 only after stability is confirmed. |
| Supabase Auth redirect allowlist (preview-PR URL pattern) | **R12.** Almost certainly contains a `https://pr-*---agile-flow-app-*.run.app/auth/callback` wildcard for preview-deploy callbacks. Add `https://pr-*---masterkey-*.run.app/auth/callback` in Phase 3 step 26 alongside the production URL. Verify against the Supabase dashboard before Phase 5 step 37 prunes the old pattern. |
| Supabase GitHub App config | **R10.** Verify the App is installed on `cubrox/masterkey` post-rename. GitHub usually preserves App installs, but the Supabase App's internal repo allowlist may track by `owner/name` (in which case the rename silently breaks per-PR branching) or by `repository.id` (in which case it auto-updates). Visit Supabase dashboard → Project Settings → Integrations → GitHub immediately after Phase 2 step 17 and confirm `cubrox/masterkey` appears. If it doesn't, re-install the App on the new repo name. Also exercise the path: include a `supabase/migrations/<timestamp>_rename_smoke.sql` empty file in the Phase 3 step 25 dry-run PR so branch-creation actually runs. |
| Supabase magic-link email template | No change — already content-neutral re. service name. |

### 2.9 Memory MCP

The Memory MCP graph for the current session was empty when queried (`mcp__memory__search_nodes("cubrox")` returned `{entities: [], relations: []}`). Other agent sessions may have entities keyed on "Cubrox", "Cubrox PRD", etc. **Not in immediate scope** — flag for post-rename audit:
- Run `mcp__memory__search_nodes("cubrox")` across active sessions.
- Rename entity names, or create alias relations from the old name to the new one.

---

## 3. Order of operations

Numbered, with explicit rollback points (RB-N) and "what's safe to interleave" annotations.

### Phase -1: Framework alignment (gembaflow v1.5.0)

**v4 STATUS: COMPLETED (2026-06-30).** Landed via PRs #232, #235, #236. Closed tickets: #224 (epic), #225-#231 (sub-tasks), #233 (json-validate ruleset split), #234 (bot.reviewer alignment). The local fork is at gembaflow v1.5.0 with `.gembaflow-*` metadata. The body of this section is retained as historical record; no further action required.

This phase exists because upstream renamed `vibeacademy/agile-flow` → `vibeacademy/gembaflow` and shipped v1.5.0 while we sat on v1.3.0. The local fork still has `.agile-flow-*` metadata files and CLAUDE.md / UPSTREAM.md / VERSIONING.md still say "Agile Flow". **This phase lands before the existing Phase 0** because the masterkey rename (Phases 0-5 below) touches the same `.agile-flow-overrides` file and the same agent persona files that the v1.5.0 sync auto-migrates. Sequencing matters: do the framework alignment first, get a clean baseline at v1.5.0 with `.gembaflow-*` dotfiles, THEN start the masterkey rename. The reverse order produces dual-state and merge-conflict pain.

#### What changes

1. Metadata file renames (auto-migrated by upstream's `template-sync.sh` v1.5.0 lines 47-58):
   - `.agile-flow-version` → `.gembaflow-version` (JSON; `upstream` field still legitimately points at `vibeacademy/agile-flow` in upstream's own copy, so we leave that field alone — the actual sync URL is hard-coded in `template-sync.sh` line 36 as `vibeacademy/gembaflow` with `FALLBACK_REPO=vibeacademy/agile-flow` per line 41)
   - `.agile-flow-meta/` → `.gembaflow-meta/` (directory containing `version` file)
   - `.agile-flow-overrides` → `.gembaflow-overrides` (text file listing fork-customized paths)
2. New file shipped: `.gembaflow-config.example.json`. Per upstream contents (4 fields: `org`, `board.id`, `bot.worker`, `bot.reviewer`), this is the **example/template** consumed by `scripts/substitute-config-placeholders.sh` to populate `{{org}} / {{board.id}} / {{bot.worker}} / {{bot.reviewer}}` placeholders in `.claude/commands/work-ticket.md` and `.claude/commands/drain.md`. We **leave the `.example.json` in place as shipped** and additionally create `.gembaflow-config.json` with our actual values (`org=cubrox` for now — to be flipped to whatever the post-Phase-2 owner is, `board.id=29` for now, `bot.worker`/`bot.reviewer` per solo-mode = repo owner). The example file is not consumed at runtime; the unsuffixed one is. This avoids triggering the bootstrap-time substitution with placeholder values still in place (which would corrupt the slash-command specs).
3. Local `scripts/template-sync.sh` path edits — strictly pre-sync bridge, lines 35-36 and 422:
   - Line 35: `VERSION_FILE=".agile-flow-version"` → `".gembaflow-version"`
   - Line 36: `OVERRIDES_FILE=".agile-flow-overrides"` → `".gembaflow-overrides"`
   - Line 422: `mkdir -p .agile-flow-meta` → `mkdir -p .gembaflow-meta`
   - Line 423: same — `.agile-flow-meta/version` → `.gembaflow-meta/version`
   - Line 424: same — `git add .agile-flow-meta/version` → `git add .gembaflow-meta/version`
   - Line 2 / 5 / 6: comments — update for honesty
   - Note: line 34 already correctly says `vibeacademy/gembaflow` (the only line that was forward-fixed when somebody started this work earlier).
   - **`scripts/template-sync.sh` is in `syncDirectories` so the upstream v1.5.0 version will overwrite our local edits on the actual sync run.** That's fine — the local edits are bridge-only, intended to let our CURRENT run of the script (with dotfiles still named `.agile-flow-*`) read the correct paths long enough to download the v1.5.0 tarball, after which the post-loop self-heal block (#371 / #486 per release notes) overwrites `template-sync.sh` with the upstream v1.5.0 version. The local edits' lifetime is exactly one `/upgrade` invocation.
4. Doc string updates (these are NOT in `syncDirectories` for most files — local-only):
   - `CLAUDE.md` line 2 (template heading): "Agile Flow - Claude Code Project Template" → "Gemba Flow - Claude Code Project Template"
   - `CLAUDE.md` lines 10, 73, 80, 81 (`AGILE_FLOW_*` env-var names — these env vars MAY have been renamed by upstream v1.4 or v1.5; check the v1.5.0 `bootstrap-workflow.md` and `ensure-github-account.sh` before flipping. If upstream still reads `AGILE_FLOW_*` env names, our doc must continue to call them that even though the project is now "Gemba Flow". This is a deliberate cross-check during step (-1).5 review.)
   - `UPSTREAM.md`: every "Agile Flow" → "Gemba Flow"; every `vibeacademy/agile-flow` URL → `vibeacademy/gembaflow`
   - `VERSIONING.md`: same
5. Version bump: `.gembaflow-version` `version` field flips from `1.3.0` → `1.5.0` (the sync script's normal post-sync logic does this; we don't hand-edit).
6. New `syncDirectories` entries per upstream v1.5.0's own `.gembaflow-version`: `.claude/modes` and `features`. The first sync pulls these as new directories. Verify nothing in the fork would conflict.
7. Per v1.5.0 release notes' "Migration notes" section: branch-protection ruleset must add `json-validate` as a required status check (was split off from `version-parity` in #471). This is a Phase -1 deliverable: update GitHub branch-protection rule on `main` to require both `version-parity` AND `json-validate`. **Note:** this is mechanically the SAME ruleset (id 15886599) the masterkey Phase 2 step 17 verifies — touching it in Phase -1 is harmless; Phase 2's re-verify still succeeds.

#### Order of operations within Phase -1

Order matters because the v1.5.0 release notes describe a chicken-and-egg problem: the new `template-sync.sh` contains the auto-migration AND the post-sync self-heal, but our v1.3.0 fork has neither. The release notes' "Propagation note" is the canonical sequence:

(-1).1 **Snapshot current state.** `cp .agile-flow-version /tmp/.agile-flow-version.pre-rebrand`; same for `.agile-flow-overrides`, `.agile-flow-meta/version`. Capture `git rev-parse HEAD` as the pre-Phase-(-1) SHA for RB-(-1) rollback. Commit any pending working-tree changes to a wip branch.
(-1).2 **Branch:** `feature/framework-align-gembaflow-v1.5.0`.
(-1).3 **Bridge-edit local `scripts/template-sync.sh`** (per "What changes" item 3). This lets the OLD script (which has the OLD VERSION_FILE/OVERRIDES_FILE paths hardcoded as constants but ALSO has the line-34 upstream URL already correct) find the locally-still-`.agile-flow-*`-named files long enough to do the version comparison and download the v1.5.0 tarball. Test: `bash scripts/template-sync.sh --dry-run` (if `--dry-run` flag exists in our v1.3.0; if not, skip — the rename is verified at step (-1).5 after the actual sync runs).
(-1).4 **Manual curl-refresh of runtime-protected scripts** per the v1.5.0 release notes (this is the keystone — our v1.3.0 doesn't have the self-heal so the upgrade pipeline can't deliver itself):
```bash
curl -fsSL "https://raw.githubusercontent.com/vibeacademy/gembaflow/v1.5.0/scripts/template-sync.sh" -o scripts/template-sync.sh
curl -fsSL "https://raw.githubusercontent.com/vibeacademy/gembaflow/v1.5.0/scripts/lib/overrides.sh" -o scripts/lib/overrides.sh
chmod +x scripts/template-sync.sh
grep -c "Self-healing post-sync refresh" scripts/template-sync.sh   # MUST return 1
```
The grep is the v1.5.0 release-notes' own verification gate. If it returns 0, abort and re-curl.
(-1).5 **Run the sync.** Execute `bash scripts/template-sync.sh`. This now-v1.5.0 script:
- Runs the early one-time migration block (lines 47-58): `git mv .agile-flow-version .gembaflow-version`, same for `.agile-flow-meta/`, same for `.agile-flow-overrides`. Local edits done in (-1).3 are now irrelevant; the file paths in the new script point at `.gembaflow-*` natively.
- Reads `.gembaflow-version`, sees `version=1.3.0` and upstream latest is `v1.5.0`, creates branch `gembaflow-sync/v1.5.0`, downloads the tarball, copies syncDirectories.
- Post-sync loop: re-copies `scripts/template-sync.sh` and `scripts/lib/overrides.sh` from the tarball if they differ from upstream AND not in overrides. (Idempotent on this run because we already curl'd the latest in step (-1).4.)
- Updates `.gembaflow-version` `version` field to `1.5.0`.
- The script opens a PR (or stages a branch — depends on environment; check terminal output).
(-1).6 **Reconcile the overrides list.** The auto-migration moves `.agile-flow-overrides` to `.gembaflow-overrides` byte-for-byte (it's `git mv`, not a content-transform). Walk the file: every path still listed must exist post-sync. Specifically:
- The 5 agent/command paths (`.claude/agents/github-ticket-worker.md`, `.claude/agents/devops-engineer.md`, `.claude/agents/system-architect.md`, `.claude/commands/doctor.md`, `.claude/commands/bootstrap-architecture.md`) — verify none were renamed by upstream v1.4/v1.5 (R16). If `.claude/agents/devops-engineer.md` became `.claude/agents/platform-engineer.md` upstream (hypothetical), our overrides line silently no-ops and the new file gets stomped on next sync.
- The 10 GCP/workshop scripts in `scripts/*.sh` — confirm none are now shipped by upstream (which would mean we're overriding an actual upstream file rather than a fork-local addition).
- Append the two new upstream overrides if applicable: `.gembaflow-meta/` and `.claude/commands/work-ticket.md` per upstream v1.5.0's `.gembaflow-overrides` (verified via `gh api`). The first is structural; the second is so that bootstrap-time-substituted placeholders survive the next sync.
- **Create `.gembaflow-config.json`** by copying `.gembaflow-config.example.json` and filling in actual values. Run `bash scripts/substitute-config-placeholders.sh` (new in v1.5.0) to populate placeholders in `.claude/commands/work-ticket.md` and `.claude/commands/drain.md`.
(-1).7 **Doc string updates** (per "What changes" item 4) AND **verification gate:**
- Edit `CLAUDE.md`, `UPSTREAM.md`, `VERSIONING.md` per item 4.
- Add `json-validate` to branch-protection ruleset 15886599.
- `bash scripts/doctor.sh` — must complete without ERROR.
- `uv run pytest` — full suite must pass.
- Manual smoke: `/work-ticket` slash command resolves (loads the now-template-substituted spec), `/sprint-status` runs, `/doctor` runs.
- `grep -r "\.agile-flow-" . --include="*.sh" --include="*.md" --include="*.json"` — expect 0 hits in non-historical files (session journals + ADRs may keep their references as historical record).
- Open PR for `feature/framework-align-gembaflow-v1.5.0`.

#### Why this lands before masterkey Phase 0

Three reasons, in priority order:

1. **Same files, sequence-sensitive.** Existing E2-T5 (#196) edits `scripts/provision-gcp-project.sh` + `scripts/diagnose-cloudrun.sh` defaults; these are listed in `.agile-flow-overrides`. Existing E2-T7 (#198) edits files listed in `.agile-flow-overrides`. If masterkey lands first and the masterkey PR commits change `.agile-flow-overrides`, the v1.5.0 sync's auto-migration `git mv .agile-flow-overrides .gembaflow-overrides` produces a merge conflict against the not-yet-merged masterkey commits — or worse, lands two copies of the file in the working tree. Doing framework alignment first means by the time E2-T5 / E2-T7 run, the file is already `.gembaflow-overrides` and there's nothing to migrate.
2. **Clean baseline at v1.5.0.** v1.5.0 adds `audit-local-customizations.sh` (run by `/upgrade` per #468) which surfaces every framework-controlled file modified locally but NOT in `.gembaflow-overrides`. Running this BEFORE Phase 0 catches drift the masterkey rename would otherwise pile on top of.
3. **`agile-flow-app` Cloud Run service name disambiguation.** Once we say "Gemba Flow" in CLAUDE.md, the Cloud Run service name `agile-flow-app` is unambiguously a project-specific holdover (not a framework default). This makes the masterkey Phase 4 cutover narrative cleaner — we're renaming "the legacy Cubrox Cloud Run service", not "the Agile Flow framework default service".

#### Rollback point RB-(-1)

Pre-Phase-(-1) SHA captured in step (-1).1. Rollback is `git reset --hard <pre-Phase-(-1)-SHA>` on the feature branch BEFORE the sync PR merges. After merge: rollback requires reverting the sync PR (which is a multi-hundred-file revert touching `.claude/`, `scripts/`, etc.) AND `git mv`-reversing the metadata file renames (which the upstream `template-sync.sh` will re-do on the next `/upgrade`).

**Special concern: framework-rollback is itself a framework operation.** `template-sync.sh` is in `syncDirectories` AND in `RUNTIME_PROTECTED_PATHS`, which means the upstream v1.5.0 version replaces our local v1.3.0 version during the sync. The script that ran the sync is no longer the script that lives on disk. If the sync produces a broken state, the recovery script available to us is the NEW v1.5.0 one (or a curl of the old v1.3.0 from `github.com/vibeacademy/agile-flow/raw/v1.3.0/scripts/template-sync.sh` — note: from `vibeacademy/agile-flow` since at v1.3.0 the repo wasn't yet renamed). Capture the v1.3.0 script as `/tmp/template-sync.v1.3.0.sh` in step (-1).1 alongside the metadata snapshot.

#### Specific risks (see also §4 R16-R18)

- **R16:** v1.4.0 or v1.5.0 may have renamed agents whose old names appear in our `.agile-flow-overrides`. If `.claude/agents/devops-engineer.md` is renamed to `.claude/agents/platform-engineer.md` upstream, our override line silently no-ops, the upstream file lands, and our fork-customized contents are lost on next sync. Mitigation: (-1).6 walks the overrides list against the actual on-disk file list post-sync.
- **R17:** `.gembaflow-config.example.json` is a new file shipped in v1.5.0 with 4 placeholder fields (`org`, `board.id`, `bot.worker`, `bot.reviewer`). If we don't create `.gembaflow-config.json` from it and run `substitute-config-placeholders.sh`, the v1.5.0 `.claude/commands/work-ticket.md` and `drain.md` will load with `{{org}}` etc. literally in the spec text — every `/work-ticket` invocation will read placeholder syntax and fail. Mitigation: (-1).6 explicitly creates `.gembaflow-config.json` and runs the substitution script.
- **R18:** The manual curl-refresh of `template-sync.sh` in step (-1).4 is bootstrap-of-the-bootstrapper. If the curl returns HTTP 404 (e.g., tag `v1.5.0` typo'd, or the file moved upstream), the on-disk script stays at v1.3.0 logic, the auto-migration block is absent, and step (-1).5's sync produces dual-state: `.agile-flow-*` files remain AND `.gembaflow-*` may or may not appear depending on whether v1.3.0's logic happens to look for the new names anywhere (it doesn't — it'd just say "VERSION_FILE not found"). Mitigation: the `grep -c "Self-healing post-sync refresh" scripts/template-sync.sh` gate in step (-1).4 fails loud if the refresh didn't take.

**RB-(-1):** Revert to pre-Phase-(-1) SHA on the feature branch before merge; OR if merged, revert the sync PR + restore `.agile-flow-*` filenames via `git mv` reversal (the `/tmp/template-sync.v1.3.0.sh` snapshot can drive the recovery).

---

### Phase 0 — Pre-flight (read-only, no production impact)

**v4 STATUS: MOSTLY OBSOLETE.** Steps 2-4 (GCP snapshots, WIF binding shape verification, Cloud Logging enumeration) require access to the old GCP project, which the operator no longer has. They are unobtainable and dropped — see §6 reconciliation for ticket-level actions. The only steps still valid in v4 are step 1 (GitHub board inventory — #187), step 5 (open-PR check), and step 6 (forks enumeration). v4 Phase 0 collapses to "GitHub-side inventory only."

1. Inventory all open + closed tickets on `orgs/vibeacademy/projects/29`. Export to a local JSON file. (`gh api graphql` with `node(id: $projectId) { items(...) }`.) **STILL VALID.**
2. ~~Snapshot the existing state into `snapshots/`~~ **OBSOLETE — old project inaccessible.** All four snapshot artifacts (`agile-flow-app.pre-rename.yaml`, `revisions.pre-rename.yaml`, `sa-iam.pre-rename.yaml`, `secrets.pre-rename.yaml`) are unobtainable. Rollback artifacts are now only the snapshots of the NEW project that #237 takes after provisioning — which is a different category of artifact (forward-looking baseline, not backward-looking rollback).
   - `gcloud run services describe agile-flow-app --region=us-central1 --format=yaml > snapshots/agile-flow-app.pre-rename.yaml`
   - `gcloud run revisions list --service=agile-flow-app --region=us-central1 --format=yaml > snapshots/revisions.pre-rename.yaml`
   - `gcloud iam service-accounts get-iam-policy $SA_EMAIL --format=yaml > snapshots/sa-iam.pre-rename.yaml`
   - `gcloud secrets list --project=$GCP_PROJECT_ID --format=yaml > snapshots/secrets.pre-rename.yaml`
   These are the rollback artifacts if the new service goes sideways.
3. ~~**Verify WIF wiring.**~~ **OBSOLETE — old project inaccessible.** Closed via #189 (not-planned) 2026-06-30. The new project's WIF wiring is now an output of #237's provisioning, not a pre-flight verification.
4. ~~Enumerate Cloud Logging / Monitoring assets~~ **OBSOLETE — old project inaccessible.** The expected output was empty anyway (per ADR-004); the new project starts empty by construction. Phase 5 step 39 collapses to a one-line confirmation that the new project's logging filters reference `service_name="masterkey"` correctly (which they do by default, since the service was created with that name).
5. Confirm zero open PRs (preview deploys in flight are a hazard for the cutover window). If any exist, ask their authors to rebase after #237 lands and `vars.CLOUD_RUN_SERVICE` is set — don't leave preview deploys pointing at a non-existent old service. **STILL VALID.**
6. Enumerate external forks: `gh api repos/cubrox/cubrox/forks --jq '.[].full_name'` (per R15). If any exist, notify the fork owners. **STILL VALID.**

**RB-0:** Trivial — nothing changed.

### Phase 1 — Code-only changes on a feature branch

**v4 STATUS: STILL VALID, unchanged scope.** The codebase rename PR (E2-T1 through E2-T8 / #192-#199) is GCP-independent. The only v3 detail that changes is Phase 1 step 15's preview-deploy expectation: in v3 the preview was expected to land on `agile-flow-app`; in v4 it lands on `masterkey` from the start (assuming #237 lands before Phase 1 PR is opened). The "live no-op proof" framing changes to "preview deploy validates new-project plumbing simultaneously with code rename."

7. Branch: `feature/refactor-cubrox-to-masterkey`.
8. Apply ALL §2.2 code/test/template renames AND `.github/workflows/ci.yml:218,307,315` rename (B1). Drive via:
   - `app/main.py` title
   - `CUBROX_TEST_SEED_ENABLED` -> `MASTERKEY_TEST_SEED_ENABLED` everywhere (one ripgrep + sed pass, then audit) — including `ci.yml`
   - `window.cubroxLineCount` -> `window.masterkeyLineCount`
   - `app/scripts/metric.py` prog name
   - test fixtures (`pr-42---agile-flow-app-...` -> `pr-42---masterkey-...`)
   - npm package.json + package-lock.json regenerate
9. Apply §2.5 script edits to `scripts/provision-gcp-project.sh` (lines 800, 1011) and `scripts/diagnose-cloudrun.sh` (line 35 + line 23 comment) (B4). Both are in `.agile-flow-overrides`, safe to edit.
10. Apply §2.6 doc renames (carefully; do not edit upstream-synced docs without adding to `.agile-flow-overrides`).
11. Apply §2.7 agent persona edits (only the files in `.agile-flow-overrides`). **Also** fold the `.claude/PROJECT.md` Supabase fix here (per S5).
12. Update `supabase/config.toml` `project_id`.
13. **Disable synthetic monitor schedule for the cutover window** (resolved Q9): comment out the `schedule:` block in `.github/workflows/synthetic-monitor.yml` on this branch. Add a TODO in the PR body to restore it in a small follow-up PR after Phase 4 step 32.
14. Run full local test suite: `uv run pytest`, `uv run ruff check`, `uv run ruff format --check`, `uv run mypy app/`, and `tests/a11y` (locally against `supabase start`).
15. Open PR. **v4 update:** Once #237 is merged (sets `vars.CLOUD_RUN_SERVICE=masterkey` and `vars.ARTIFACT_REPO=masterkey`), the preview deploy on this PR lands on the NEW `masterkey` Cloud Run service in the new GCP project from the start. A green preview validates both the code rename AND the new-project plumbing simultaneously. (v3 narrative: "preview goes to old `agile-flow-app` to prove rename is a no-op, then re-deploy after var flip" — no longer applicable in v4.)

**RB-1:** Close PR, no impact. Nothing has been deployed.

### Phase 2 — GitHub repo + board migration + WIF re-bind for renamed repo (independent of code)

Can run in parallel with Phase 1 (the code-only branch). v4 reshapes step 16: the v3 "dual-write before rename" is replaced by "re-point the freshly-provisioned WIF binding at the renamed repo." Order within this phase still matters — WIF must work for `cubrox/masterkey` before the first CI run on the renamed repo, otherwise every workflow that authenticates to GCP starts failing with `iam.serviceAccounts.getAccessToken denied`.

16. **WIF re-bind after repo rename (v4 REPLACES v3's dual-write).** #237 provisions a single WIF binding on the new deployer SA for `principalSet://.../attribute.repository/cubrox/cubrox` (matching the repo name at provisioning time). Once #201 (repo rename) lands, GitHub's OIDC token will present `repository = cubrox/masterkey`, which won't match. **Architect's chosen approach: dual-write the new binding BEFORE running the repo rename, then prune the old one in Phase 5** — same shape as v3's plan, just executed in the new project instead of the old one. Reasons:
    1. **Symmetry with the rest of the plan.** Every other piece of Phase 2 dual-writes (Supabase Auth allowlist keeps old + new entries, board exists in both places during migration). A WIF dual-write keeps the mental model uniform.
    2. **Recoverability.** If the repo rename half-completes (e.g., GitHub UI hangs after the rename succeeds but before our local remote update), having both bindings live means CI doesn't immediately go red. Single-binding-pointed-at-`cubrox/masterkey` would mean any in-flight workflow run keyed to the old `cubrox/cubrox` reference fails.
    3. **Cheaper than re-running `provision-gcp-project.sh`.** Re-running the provision script would attempt to re-create the SA, re-create the WIF pool, etc. — most steps would no-op idempotently, but it's a heavier hammer than `add-iam-policy-binding`.
    4. **No cost overhead.** IAM bindings are free; the dual-state lasts only until Phase 5.

    Concrete steps (executed against the NEW GCP project provisioned by #237):
    ```bash
    SA_EMAIL=$(gcloud secrets versions access latest --secret=gcp-deployer-sa-email --project=$NEW_GCP_PROJECT_ID 2>/dev/null) \
      || SA_EMAIL="<read from GCP_SERVICE_ACCOUNT secret>"
    PROJECT_NUMBER=$(gcloud projects describe $NEW_GCP_PROJECT_ID --format='value(projectNumber)')
    NEW_MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github/attribute.repository/cubrox/masterkey"
    for role in roles/iam.workloadIdentityUser roles/iam.serviceAccountTokenCreator; do
      gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
        --role="$role" --member="$NEW_MEMBER" --project=$NEW_GCP_PROJECT_ID
    done
    ```
    Old `cubrox/cubrox` binding stays intact in parallel until Phase 5 step 38. **Verify (v4.1 — BC3 fix):** trigger `workflow_dispatch` on `synthetic-monitor.yml` against the new service. It auths via WIF (lines 59-61 mirror `deploy.yml`), resolves the service URL via `gcloud run services describe masterkey`, and runs the auth probe. **Why this and not `rollback-production.yml`:** `rollback-production.yml` does NOT have a dry-run mode — supplying `revision=<currentRevision>` causes `gcloud run services update-traffic` (lines 100-108) followed by a smoke test (lines 127-146). On a fresh single-revision `masterkey` service that's an operational no-op, but it's NOT side-effect-free; on a multi-revision service or with a typo'd revision name, it actively reroutes traffic. `synthetic-monitor.yml workflow_dispatch` is side-effect-free except for sending a magic-link email to the smoke-test address (fine). The fact that Phase 1 step 13 commented out `synthetic-monitor.yml`'s `schedule:` block doesn't disable `workflow_dispatch` — those are independent triggers. If the WIF probe passes, the new binding is plumbed. **Recovery if it fails (per NS5):** re-run `scripts/provision-gcp-project.sh` with `GCP_PROJECT_ID=$NEW_GCP_PROJECT_ID GITHUB_OWNER=cubrox GITHUB_REPO=masterkey ARTIFACT_REPO=masterkey CLOUD_RUN_SERVICE=masterkey GITHUB_REPOSITORY=cubrox/masterkey` set — the script's idempotency (lines 414, 427) skips the pool/provider but the SA binding loop (line 466) adds the missing `cubrox/masterkey` principalSet binding without manual `gcloud iam` surgery.

    **Why this instead of "re-provision in place against the renamed repo":** the operator's `scripts/provision-gcp-project.sh` reads `GITHUB_REPO` once and bakes it into the WIF binding. Re-running with `GITHUB_REPO=cubrox/masterkey` would add the new binding but would not remove the old one (the script is additive). Same net effect as the explicit `add-iam-policy-binding` calls above, but with hundreds of lines of script execution and the side-effect of re-touching the SA, AR repo, and project APIs (most no-op, some emit log noise). Explicit two-line bindings are auditable and minimal.
17. **Repo rename:** `gh repo rename masterkey --repo cubrox/cubrox` (or via GH UI). GitHub auto-redirects git clone URLs for 30 days, but:
    - **Immediately** update local remotes on every developer machine: `git remote set-url origin git@github.com:cubrox/masterkey.git`.
    - Verify branch-protection ruleset (id 15886599) still applies: `gh api repos/cubrox/masterkey/rulesets` (per S3).
    - Verify Supabase GitHub App allowlist still contains the repo (per R10): Supabase dashboard → Project Settings → Integrations → GitHub.
18. **New project board:** create `https://github.com/orgs/cubrox/projects/<new>`. Mirror columns + automation. Migrate items from `orgs/vibeacademy/projects/29` via `gh api graphql` `addProjectV2ItemById` for every issue/PR ID (open AND closed). Verify item count parity.
19. Close the legacy `vibeacademy/projects/29` board (do NOT delete — keep as audit record). Add a README note in its description pointing to the new board.

**RB-2:** Repo rename is reversible via `gh repo rename cubrox`. Board migration is additive; the legacy board still exists as fallback until step 19. WIF dual-write is purely additive — removing the new binding is a one-line `remove-iam-policy-binding`.

### Phase 3 — Cloud Run + Artifact Registry preparation (no traffic yet)

**v4 STATUS: REPLACED BY #237.** Steps 20-23 in v3 (pre-create AR repo, grant runtime SA reader, smoke-push image, pre-create Cloud Run service with sticky env-var types) are all absorbed into #237's provisioning of the new GCP project. There is no parallel "old service serving prod while we pre-create the new" window because there's no old service we can touch. Phase 3 collapses to a verification-only stage that runs **after #237 lands**:

**v4 Phase 3 (replacement) — verification-only checklist:**

1. Confirm `masterkey` AR repo exists in the new project: `gcloud artifacts repositories describe masterkey --location=us-central1 --project=$NEW_GCP_PROJECT_ID`.
2. Confirm `masterkey` Cloud Run service exists and serves: `gcloud run services describe masterkey --region=us-central1 --project=$NEW_GCP_PROJECT_ID --format='value(status.url)'` returns a URL; `curl $URL/api/health` returns 200; `curl $URL/api/health/db` returns 200.
3. **Critically:** verify env-var TYPES on the new service match `deploy.yml`'s shape (R13 still applies — the new project is fresh, but the first deploy still locks in env-var types per name). `gcloud run services describe masterkey --format=yaml | grep -E 'name: (DATABASE_URL|ANTHROPIC_API_KEY)' -A 2` — values must be literals, not `valueFrom: secretKeyRef:`. If #237 set them as secret-refs, the next `deploy.yml` will fail with the sticky-type error and we have to destructively recreate the service (which is much less painful in v4 than v3, but still annoying). **Architect's recommendation:** add an explicit check to #237's Definition of Done so this is caught at provisioning time, not at first-deploy time.
4. Capture the new service URL `$NEW_URL` and pin it into `docs/LAUNCH-CHECKLIST.md` line 10 (and lines 12, 45-46, 51) plus `CLAUDE.md` Project Information block (per S6).
5. Add Supabase Auth redirect allowlist entries for the new URLs (R4 + R12 — still valid):
   - Production: `https://masterkey-<hash>-uc.a.run.app/auth/callback`
   - Preview pattern: `https://pr-*---masterkey-*-uc.a.run.app/auth/callback`
   - Do NOT remove old `agile-flow-app-*` entries — they're harmless (the old service still receives traffic from anyone with a stale link, and removing them only matters once the legacy runtime is decommissioned, which we cannot control).
6. (Optional) Run a dry-run preview-deploy PR (mirrors v3's #208 / E4-T5). With `vars.CLOUD_RUN_SERVICE=masterkey` already set, this exercises preview-deploy + preview-cleanup + Supabase branching end-to-end. Less critical in v4 (no race condition to verify) but useful as a smoke test before Phase 1 PR lands. If skipped, the Phase 1 PR's own preview deploy serves the same role.

The original step numbers (20-26) are OBSOLETE; they referenced operations against the old project that no longer exist. Below are the v3 step descriptions preserved as historical commentary — none should be executed in v4.

~~20. Create new Artifact Registry repo `masterkey` in the same region~~ **OBSOLETE — folded into #237.**
~~21. Grant the runtime SA `roles/artifactregistry.reader`~~ **OBSOLETE — folded into #237.**
~~22. Build + push an image to the new repo manually as a smoke test~~ **OBSOLETE — first preview-deploy or production deploy serves this role.**
~~23. Pre-create the Cloud Run service `masterkey` with a placeholder revision~~ **OBSOLETE — #237's first deploy creates the service; placeholder no longer needed since there's no old service serving prod to coexist with.** (v3's `gcloud run deploy` recipe with `--min-instances=0`, split env-vars/secrets per R13, and `--no-traffic` isolation from `agile-flow-app` is no longer applicable — the new project has no `agile-flow-app` to coexist with.)
24. **v4 NOTE:** still valid as a verification step (folded into the "v4 Phase 3 verification-only checklist" above), but no longer "after pre-creating the service" — runs against the only-and-only `masterkey` service. Curl the new service's URL — `/api/health` (200), `/api/health/db` (200), then `/` (200, sees Master Key landing). **Capture the new URL** for `docs/LAUNCH-CHECKLIST.md` (B5):
    ```bash
    NEW_URL=$(gcloud run services describe masterkey --region=us-central1 --format='value(status.url)')
    echo "$NEW_URL"  # e.g. https://masterkey-aBcDeFgH-uc.a.run.app
    ```
    Amend the still-open Phase 1 PR (or open a small doc PR if Phase 1 has already merged) to pin `$NEW_URL` into `docs/LAUNCH-CHECKLIST.md` line 10, and `CLAUDE.md`'s Project Information block per S6. Update §2.C health-probe instructions (lines 45-46) and §2.D auth-test (line 51) of the launch checklist to reference `$NEW_URL`.
25. **v4 SIMPLIFIED:** Dry-run preview-deploy is now OPTIONAL. The var-flip race window that motivated v3's explicit dry-run does not exist in v4 (vars are at their target `masterkey` values from #237 onward; there's no flip-and-flip-back dance). If executed as a smoke test: open a throwaway PR with a trivial change plus a `supabase/migrations/<timestamp>_rename_smoke.sql` empty file (per R10 — exercises Supabase branching), confirm preview lands on `masterkey`, close PR, confirm cleanup. Skip the "flip var back" step. Label the dry-run PR `phase3-dryrun`. If skipped, Phase 1 PR's own preview deploy serves the same role.
26. **v4 STILL VALID:** Add the new service URL + preview pattern to the Supabase Auth redirect allowlist (per R4 + R12). Patterns to add: `https://masterkey-<hash>-uc.a.run.app/auth/callback` (production) AND `https://pr-*---masterkey-*-uc.a.run.app/auth/callback` (preview). v4 note: old `agile-flow-app-*` entries can stay indefinitely since the legacy runtime is orphaned outside our control — removing them gains nothing operational.

**RB-3 (v4):** Delete the `masterkey` service + Artifact Registry repo in the new project (if needed during early provisioning). No old prod to fall back to — the orphaned legacy runtime is not a rollback target since we cannot manage it. Effective rollback in v4 is "fix forward in the new project."

### Phase 4 — Cutover (v4 dramatically simplified — no var-flip dance, no dual-state race)

**v4 STATUS: COLLAPSED.** v3's B7-mandated re-sequencing (merge PR → verify old service → flip vars → trivial commit → verify new service) existed to eliminate a race window where `vars.CLOUD_RUN_SERVICE=masterkey` could be live while the Phase 1 PR was still unmerged. In v4 there is no flip — the vars are set as part of #237 and stay set. The Phase 1 PR's `deploy.yml` run lands on `masterkey` directly. The cutover collapses to: merge Phase 1 PR → verify new service → restore synthetic monitor.

**v4 Phase 4 (replacement, 3 steps):**

1. **Merge the Phase 1 PR.** Triggers `deploy.yml`, which (with vars already set to `masterkey` from #237) builds the post-rename code into `masterkey/masterkey:<sha>` and deploys to the `masterkey` Cloud Run service in the new GCP project. The first real production deploy.
2. **Verify `masterkey` production health.** `curl $NEW_URL/api/health`, `/api/health/db`, `/`. Run `scripts/smoke_auth.py` against `$NEW_URL`. Confirm Supabase magic-link round-trip succeeds (synthetic monitor is still disabled per E2-T8 — manual smoke is the only signal until step 3 runs).
3. **Re-enable synthetic monitor** (E5-T6 / #215 — still valid). Open small follow-up PR restoring `schedule:` block. Next :17-past-hour run hits `masterkey`-resolved URL automatically.

Steps 4-6 (announce new URL, prune Supabase allowlist 24-48h post-cutover, etc.) are still valid but mostly cosmetic in v4.

**v3 step descriptions preserved as historical commentary — none should be executed in v4 against the original GCP project:**

~~27. Merge the Phase 1 PR (vars STILL point at agile-flow-app)~~ **OBSOLETE — vars already point at masterkey from #237.** Merge still happens; just no longer carries the "live no-op proof against old service" framing.
~~28. Verify production health on the old service URL~~ **OBSOLETE — old service inaccessible.** v4 verifies on `masterkey` only.
29. ~~Flip GitHub vars~~ **OBSOLETE — done by #237.**
    ```bash
    gh variable set CLOUD_RUN_SERVICE --body masterkey
    gh variable set ARTIFACT_REPO --body masterkey
    ```
30. **Push a trivial commit to `main`** (the `CHANGELOG.md` entry from §2.6 is a natural choice) to trigger `deploy.yml`. The workflow now reads `vars.CLOUD_RUN_SERVICE=masterkey`, builds an image into `masterkey/masterkey:<sha>`, and deploys to the `masterkey` Cloud Run service. Watch the run.
31. **Verify new service URL health.** `curl $NEW_URL/api/health`, `/api/health/db`, `/`. Run `scripts/smoke_auth.py` against `$NEW_URL`. Confirm Supabase magic-link round-trip succeeds (the synthetic monitor would normally catch this, but it's disabled per Phase 1 step 13).
32. **Re-enable synthetic monitor.** Open a small follow-up PR restoring the `schedule:` block in `.github/workflows/synthetic-monitor.yml`. On merge, the monitor's next :17-past-the-hour run hits `gcloud run services describe masterkey` → resolves to `$NEW_URL` → probes the new service URL automatically (self-heals per resolved Q9 + C3).
33. **Inform users / update external URL references.** If a custom domain is in play (currently isn't), no action. If we're on `*.run.app`, the user-facing URL has changed — announce the new URL. Update any docs that reference the production URL but were not touched in Phase 3 step 24.
34. **Keep both Supabase Auth allowlist entries** (old + new, production + preview patterns) for 24-48h post-cutover. Phase 5 step 37 prunes the old ones.

**RB-4 (v4 — critical rollback):**
- If Phase 1 PR merge's `deploy.yml` run fails: the new `masterkey` service either has a bad revision (use `gcloud run services update-traffic masterkey --to-revisions=<prev>=100 --region=us-central1`) or never deployed (fix the workflow and re-run). **There is no fallback to the old service** — the legacy `agile-flow-app` runtime in the inaccessible project is not a managed target.
- If the deploy succeeds but real traffic shows breakage: fix-forward in the new project. Roll back the merge via `git revert` PR; the previous `masterkey` revision will be re-deployed.
- If WIF auth fails despite the new binding: confirm the binding actually applied via `gcloud iam service-accounts get-iam-policy $SA_EMAIL --project=$NEW_GCP_PROJECT_ID`. The provider's attribute condition is trivially true (same as v3); the only possible cause is the binding not being present in the new project.

### Phase 5 — Cleanup (v4 substantially simplified — no old project to clean up)

**v4 STATUS: ~50% of v3 work eliminated.** Steps 35, 36, 38 (delete old Cloud Run service, delete old AR repo, prune old WIF binding) all assumed access to the old GCP project. v4 cannot execute them — the project is inaccessible. The legacy runtime continues to serve indefinitely from a no-longer-managed deployment until Google reclaims it for non-payment or quota-eviction (timing unknown — could be months or years).

What's still valid in v4 Phase 5:

1. **WIF binding cleanup (v4-style).** If Phase 2 step 16 dual-wrote a `cubrox/masterkey` binding alongside the original `cubrox/cubrox` binding in the NEW project, prune the old one once stable:
    ```bash
    OLD_MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github/attribute.repository/cubrox/cubrox"
    for role in roles/iam.workloadIdentityUser roles/iam.serviceAccountTokenCreator; do
      gcloud iam service-accounts remove-iam-policy-binding "$SA_EMAIL" \
        --role="$role" --member="$OLD_MEMBER" --project=$NEW_GCP_PROJECT_ID
    done
    ```
2. **Remove old Supabase Auth allowlist entries (optional).** v4 note: this is a judgement call — the `agile-flow-app-*` entries are harmless and removing them gains nothing since the legacy URL is orphaned. Architect's recommendation: leave them for 6+ months, then audit.
3. **Memory MCP audit.** Run `prune-memory` pass to rename "Cubrox" entities (R7). STILL VALID.
4. **ADR-007 "Rename to Master Key / masterkey".** Write the architectural ADR per §2.6. STILL VALID. v4 version of the ADR should explicitly document the GCP pivot (project-lost-then-re-provisioned) as part of the consequences, since it's now a load-bearing fact of the rename history.
5. **Doc / link cleanup.** v4 NEW scope — enumerate external references to `agile-flow-app-heo5ry7rua-uc.a.run.app` (R20) and either redirect them (where we control the surface) or document them as legacy (where we don't). `rg agile-flow-app-heo5ry7rua` across the repo; check team-comms surfaces.
6. **CHANGELOG entry.** Close out the rename with a CHANGELOG note documenting the new production URL + the orphaned legacy URL.

v3 step descriptions preserved as historical commentary — none should be executed in v4:

~~35. Delete the old Cloud Run service `gcloud run services delete agile-flow-app`~~ **N/A — old project inaccessible.**
~~36. Delete the old Artifact Registry repo~~ **N/A — same reason.**
~~37. Remove the old `agile-flow-app-*.run.app` allowlist entries from Supabase~~ **Optional in v4; see step 2 above.**
~~38. Remove the old WIF binding for `cubrox/cubrox` in the old project~~ **N/A — that project is inaccessible.** The v4 analogue is pruning the same-shape binding in the NEW project after the repo rename (step 1 above).
~~39. Update Cloud Logging saved queries in old project~~ **N/A — old project inaccessible.** The new project starts empty by construction; no inherited filters to update.
~~40. Close the `cubrox/cubrox` repo redirect note in CHANGELOG~~ **STILL VALID** — folded into step 6 above.

**RB-5 (v4):** Past this point, rollback means re-provisioning from scratch (re-run #237's provisioning recipe) plus re-applying the Phase 1 code rename. Phase 0 snapshots are unobtainable; the only "snapshot" we have is `scripts/provision-gcp-project.sh` itself plus this plan document. Don't run v4 Phase 5 step 1 (WIF prune) until the new service has been stable for at least 30 days.

---

## 4. Risk register

### R1 — Ephemeral preview deploys break mid-rename

**Likelihood:** High if Phase 4 is staged poorly.
**Impact:** All open PRs lose preview deploys; reviewers can't validate visually.

**Mechanism:** `preview-deploy.yml` builds an image into `${ARTIFACT_REPO}/${SERVICE_NAME}:pr-N-<sha>` and tags a Cloud Run revision on `${SERVICE_NAME}`. If we flip `vars.CLOUD_RUN_SERVICE` while PRs are open, the next preview-deploy run will:
1. Try to push to a new Artifact Registry path (`masterkey/masterkey:pr-N-<sha>`) — succeeds IF Phase 3 step 20 ran (the new AR repo exists).
2. Try to tag a `pr-N` revision on the `masterkey` service — succeeds IF Phase 3 step 23 pre-created the service.
3. Smoke-test the preview URL pattern `https://pr-N---masterkey-<hash>-uc.a.run.app/api/health` — the URL changes shape (different `<hash>` segment), so the **PR comment with the stale `agile-flow-app` URL will be updated in place** by the `actions/github-script` step (line 307: `c.body?.startsWith('## Preview Deployment')`). Verified: the script overwrites by marker, doesn't append.
4. The cleanup workflow (`preview-cleanup.yml`) when the PR closes will run against the NEW `${SERVICE_NAME}` and look for `pr-N` tag — won't find it on `masterkey` if the tag was created against `agile-flow-app` pre-flip. **Result: orphaned `pr-N` tag on `agile-flow-app` until Phase 5 deletes the service.**

**Mitigation:**
- **Phase 3 step 25 dry-run PR** is now the explicit acceptance gate: open a throwaway PR, flip vars, push, verify, close, restore vars.
- Communicate to all PR authors before flip: "rebase your PR onto post-rename main; your preview URL is going to change."
- Plan Phase 4 for a quiet window (no PRs in flight). Phase 0 step 5 confirms zero open PRs.

### R2 — Cloud Run service rename loses traffic history / revision history

**Likelihood:** Certain (this is how Cloud Run works — services aren't renameable in-place; confirmed by `gcloud run services --help`).
**Impact:** Operational forensics. Cannot `gcloud run revisions list agile-flow-app-00042-xyz` after Phase 5 step 35.

**Mitigation:**
- Phase 0 step 2 captures full YAML snapshots (service + revisions + SA IAM + secrets list per S2).
- Phase 5 step 36: archive image manifests before deleting AR repo.
- Cloud Logging retains logs by project + resource label for 30 days minimum (configurable); old service logs are still query-able as long as the project lives.

### R3 — WIF auth fails after repo rename (v4: SUBSTANTIALLY MITIGATED by clean provisioning, residual risk addressed by Phase 2 step 16 dual-write in the new project)

**v4 STATUS:** Substantially resolved. #237 provisions WIF cleanly in the new project from day 1 (bound to `cubrox/cubrox`, the repo name at provisioning time). The residual risk is that the binding doesn't auto-update when the repo is renamed to `cubrox/masterkey` — same mechanism as v3, but now executed against a project we know is correctly wired (since #237 just provisioned it). Phase 2 step 16's dual-write (now performed against the new project) addresses the residual risk identically to v3.

**Likelihood (v4):** Low — the dual-write step is well-understood and the new project's WIF binding has a known-good baseline. Higher only if Phase 2 step 16 is skipped.
**Impact:** Every workflow that authenticates to GCP starts failing with `iam.serviceAccounts.getAccessToken denied`. `deploy.yml`, `preview-deploy.yml`, `synthetic-monitor.yml`, `rollback-production.yml`, `preview-cleanup.yml` are all affected. Production isn't down (last good revision still serves) but no new deploys can ship — including rollback. **This was the single most likely "stuck in the middle" failure mode in v3; in v4 it's downgraded because the dual-write is now a one-time operation against a fresh project rather than a "modify the existing prod environment" operation.**

**Mechanism:** Per `provision-gcp-project.sh:437-439, 465-474`, the WIF provider's attribute-condition is trivially true (`assertion.repository != ''`). The repo pin lives on the **deployer SA's IAM policy** as `principalSet://.../attribute.repository/cubrox/cubrox`, with BOTH `roles/iam.workloadIdentityUser` AND `roles/iam.serviceAccountTokenCreator`. After the repo rename, GitHub's OIDC token presents `repository = cubrox/masterkey`, which doesn't match the bound principalSet, so token-exchange fails. **There is nothing to change at the provider level** — the v1 plan's "edit the attribute condition" path was wrong.

**Mitigation:**
- Phase 2 step 16 dual-writes the new binding BEFORE the rename. The old binding stays alongside until Phase 5 step 38 removes it. Both names resolve for the entire grace window.
- Verification (v4.1 — BC3 fix): `workflow_dispatch` on `synthetic-monitor.yml` after step 16 but before step 17 (the repo rename). The workflow auths via WIF and probes the service URL — no traffic-shift side effect. Previously this called for `rollback-production.yml workflow_dispatch`, but that workflow mutates traffic via `gcloud run services update-traffic` and lacks a dry-run mode; DevOps flagged it as unsafe. `workflow_dispatch` on `synthetic-monitor.yml` works even though Phase 1 step 13 commented out its `schedule:` block — the two triggers are independent.
- The per-repo binding kept narrow (not widened to org-level per resolved Q5) — accidental sibling repos created under `cubrox` never inherit deploy capability.

### R4 — Supabase magic-link sign-in breaks (redirect URL not in allowlist)

**Likelihood:** Certain if Phase 3 step 26 is skipped.
**Impact:** Users click their magic link, GoTrue refuses the redirect, sign-in fails. Production auth outage.

**Mitigation:**
- Phase 3 step 26 (allowlist the new production URL + new preview pattern pre-cutover).
- `synthetic-monitor.yml` (after re-enable in Phase 4 step 32) will catch any remaining gap within an hour of cutover (it drives a real sign-in against the live URL). `synthetic-monitor.yml:104-107` calls `gcloud run services describe ${SERVICE_NAME}` and `SERVICE_NAME` now reads `vars.CLOUD_RUN_SERVICE=masterkey` — self-healing as long as the var flip happens.

### R5 — `template-sync.sh` next run reverts hand-edited files

**Likelihood:** Medium (the next time someone runs `/upgrade` or `template-sync`).
**Impact:** Renames in `.claude/agents/*.md`, `docs/PLATFORM-GUIDE.md`, etc. get reverted to upstream.

**Mitigation:**
- For files in `.claude/agents` that are already in `.agile-flow-overrides`, the override mechanism protects them — no action needed.
- For `scripts/provision-gcp-project.sh` and `scripts/diagnose-cloudrun.sh`: both are already in `.agile-flow-overrides` (verified), so the B4-mandated edits are protected.
- For `docs/PLATFORM-GUIDE.md`, `docs/CI-CD-GUIDE.md`: either (a) add them to `.agile-flow-overrides` if we edited them, or (b) leave the upstream `agile-flow-app` references intact and accept that the docs say "agile-flow-app" while reality says "masterkey" (low-cost — these are framework reference docs, not operational runbooks).
- Strongly recommend (a): add to `.agile-flow-overrides` ONLY the files we actually edited.

### R6 — `pyproject.toml` rename desync (REVISED per B6)

**Likelihood:** Zero (we're not renaming it).
**Impact:** N/A today.

**Audit-debt note for future maintainers:** if any maintainer later renames `pyproject.toml:name` from `agile-flow-gcp`, they must also audit `[tool.*]` config blocks for the old name. The current value flows into:
- `uv build` wheel filenames (`agile_flow_gcp-X.Y.Z-py3-none-any.whl`)
- `uv pip list` display
- Any `[tool.X.agile-flow-gcp]` config block that scopes by project name (none today; verify before any future rename)
- `template-sync.sh`'s diff logic against upstream

None of our internal code imports the package by its `pyproject.toml` name (the code is in `app/`, not `agile_flow_gcp/`), so a future rename would be cosmetic + config-audit only.

### R7 — Memory MCP entities reference stale names

**Likelihood:** Medium.
**Impact:** Agents in long-lived sessions answer questions using "Cubrox" terminology after the rename, confusing operators.

**Mitigation:**
- Post-rename: run a `prune-memory` skill pass searching for `cubrox` / `Cubrox` entities and rename or add alias observations.
- Out of immediate scope per task brief — flagged as follow-up.

### R8 — Documentation links rot

**Likelihood:** Low-medium.
**Impact:** External references (blog posts, internal wiki, Slack messages) that link to `https://github.com/cubrox/cubrox` get a GitHub 30-day redirect, then break. References to `agile-flow-app-heo5ry7rua-uc.a.run.app` break the moment we delete the old service in Phase 5.

**Mitigation:**
- GitHub redirect window covers the urgent path.
- Communicate the URL change before Phase 5.
- If we have a custom domain (we don't; resolved Q6 defers it), this is moot.

### R9 — `tests/a11y` package-lock churn breaks CI cache key

**Likelihood:** Low.
**Impact:** First CI run after the npm rename rebuilds Playwright browsers (slow but not broken).

**Mitigation:** None needed; cache repopulates within one run.

### R10 — Supabase GitHub App allowlist may de-list the repo on rename (NEW per DevOps)

**Likelihood:** Unknown (depends on whether Supabase tracks by `repository.id` or `owner/name`).
**Impact:** Per-PR Supabase branching silently breaks for new PRs. The Phase 4 step 30 deploy could land with `DATABASE_URL` pointing at production even for migration PRs that should have been branched.

**Mitigation:**
- Immediately after Phase 2 step 17 (repo rename), visit Supabase dashboard → Project Settings → Integrations → GitHub. Confirm `cubrox/masterkey` appears in the allowlist. If it doesn't, re-install the App on the new repo name.
- The Phase 3 step 25 dry-run PR includes an empty `supabase/migrations/<timestamp>_rename_smoke.sql` to exercise the branch-creation path — if branching doesn't fire on that PR, the App allowlist hasn't updated.

### R11 — `tests/test_auth_login.py` fixture URL is coherence-only, not semantic (NEW per DevOps)

**Likelihood:** N/A (clarification, not a risk).
**Impact:** N/A.

**Note:** The test asserts that `_external_origin` returns the exact `X-Forwarded-Host` it received as the redirect URL — the string itself has no semantic dependency on the service name. The §2.2 rename of `pr-42---agile-flow-app-xyz.run.app` -> `pr-42---masterkey-xyz.run.app` is for coherence, NOT to verify the new naming. Captured in §2.2's Justification column so a reviewer doesn't misread the change.

### R12 — Supabase Auth allowlist preview-PR pattern (NEW per DevOps)

**Likelihood:** Certain (the preview-deploy redirect pattern almost certainly exists today).
**Impact:** Magic-link sign-in inside preview environments breaks the moment `vars.CLOUD_RUN_SERVICE=masterkey` is active and a PR triggers a preview build. Reviewers can't smoke-test auth changes in PRs.

**Mitigation:**
- Phase 3 step 26 adds `https://pr-*---masterkey-*-uc.a.run.app/auth/callback` alongside the existing `https://pr-*---agile-flow-app-*.run.app/auth/callback` pattern.
- Phase 5 step 37 prunes the old pattern after stability is confirmed.

### R13 — Cloud Run env-var type stickiness (`literal` vs `secret`) (NEW per B3)

**Likelihood:** Medium (a manual `gcloud run deploy` in the dual-service window could brick the new service).
**Impact:** `Cannot update environment variable [DATABASE_URL] to <type> because it has already been set with a different type` — the next `deploy.yml` run fails permanently; the only fix is destructive service recreate (which restarts the entire cutover).

**Mitigation:**
- Phase 3 step 23 sets `DATABASE_URL` and `ANTHROPIC_API_KEY` as plain literals via `--set-env-vars` only, matching `deploy.yml:216-217`'s shape.
- DO NOT use `--set-secrets` for `DATABASE_URL` or `ANTHROPIC_API_KEY` on `masterkey` during the dual-service window. Supabase credentials (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_KEY`) DO use `--set-secrets` and that matches production — leave them as-is.
- If anyone needs to test secret-mount migration during the dual-service window, do it on a fresh throwaway service, not on `masterkey`.

### R14 — Cloud Run services-per-region quota during dual-service window (NEW; FYI only per DevOps)

**Likelihood:** N/A — quota headroom is huge.
**Impact:** None expected.

**Note:** Pre-creating `masterkey` in Phase 3 while `agile-flow-app` still exists means 2 services in the project. Default Cloud Run quota is ~1000 services per region per project. Captured here for completeness; no mitigation needed.

### R15 — External forks of `cubrox/cubrox` may have stale upstream URLs (NEW per DevOps)

**Likelihood:** Probably zero.
**Impact:** Fork owners' `git remote -v` continues to show `cubrox/cubrox` until they manually update; GitHub redirect covers 30 days.

**Mitigation:**
- Phase 0 step 6 enumerates forks via `gh api repos/cubrox/cubrox/forks --jq '.[].full_name'`.
- If any exist, notify the owners with the `git remote set-url` command.

### R16 — Upstream agent-file renames silently no-op our overrides (NEW per Phase -1)

**Likelihood:** Medium. v1.4.0 / v1.5.0 cumulative changes are large (28 PRs across both); at least one agent or command file is plausibly renamed.
**Impact:** Our `.gembaflow-overrides` line points at a path that no longer exists. The upstream file (newly named) lands without override protection, and our fork-customized contents (which were keyed to the old name) are lost on the same sync.

**Mitigation:**
- Phase -1 step (-1).6 walks `.gembaflow-overrides` against the actual on-disk file list post-sync, line by line.
- For any line where the listed file no longer exists post-sync: `git log --diff-filter=R --follow` upstream to find the rename target, update the overrides line, manually re-apply our customizations to the new path, and commit.

### R17 — `.gembaflow-config.json` missing causes slash-command spec corruption (NEW per Phase -1)

**Likelihood:** Certain if step (-1).6 skips creating `.gembaflow-config.json`.
**Impact:** v1.5.0 `.claude/commands/work-ticket.md` and `.claude/commands/drain.md` contain `{{org}}`, `{{board.id}}`, `{{bot.worker}}`, `{{bot.reviewer}}` placeholders that `substitute-config-placeholders.sh` populates at bootstrap. Without `.gembaflow-config.json`, the substitution either errors or leaves the placeholders literal. Every `/work-ticket` invocation reads spec text containing literal `{{org}}` and either fails or misbehaves.

**Mitigation:**
- Phase -1 step (-1).6 explicitly creates `.gembaflow-config.json` (copied from `.gembaflow-config.example.json`, fields populated).
- For Phase -1 only, `org=cubrox` (will be overwritten in masterkey Phase 2; user-account is fine here since the repo lives at `cubrox/cubrox`), `board.id=29` (legacy `vibeacademy/projects/29` is still the active board through Phase 2). Solo-mode means `bot.worker` and `bot.reviewer` both equal the operator's GitHub handle.
- Run `bash scripts/substitute-config-placeholders.sh` and `bash scripts/substitute-config-placeholders.sh --check` to verify substitution completed.
- Add `.gembaflow-config.json` to `.gitignore` (it contains operator-specific bot account names — shouldn't be tracked) OR commit a checked-in default and `.gitignore` only a `.local.json` override. Decide in step (-1).6.

### R18 — Bootstrap-of-bootstrapper: manual curl-refresh of `template-sync.sh` may silently fail (NEW per Phase -1)

**Likelihood:** Low but consequential.
**Impact:** Step (-1).4's two `curl` commands fetch the v1.5.0 `template-sync.sh` and `lib/overrides.sh`. If either curl returns HTTP 404 (typo'd tag, file moved upstream) or returns a partial file (network blip during pipe to `-o`), the on-disk script stays at v1.3.0 logic. Step (-1).5's `bash scripts/template-sync.sh` then runs the OLD code, which has no auto-migration and no self-heal. The result is dual-state: the script tries to read `.agile-flow-version` (which exists, so it succeeds), syncs v1.5.0 syncDirectories on top of our v1.3.0 tree, but never migrates the dotfile names. Next `/upgrade` run finds the upgraded v1.5.0 syncDirectories AND a still-`.agile-flow-*`-named metadata set — confused.

**Mitigation:**
- Step (-1).4 ends with `grep -c "Self-healing post-sync refresh" scripts/template-sync.sh` which MUST return exactly `1`. Loud failure if curl didn't take.
- Step (-1).1 captures the pre-Phase-(-1) SHA AND a copy of v1.3.0 `template-sync.sh` to `/tmp/template-sync.v1.3.0.sh` as the bootstrap-of-bootstrapper rollback path.
- `curl -fsSL` is used (lowercase `f` exits non-zero on HTTP error; `S` shows errors; `L` follows redirects) — explicit choice to fail loud on 404.

### R19 — GCP billing on new project (NEW per v4)

**Likelihood:** Medium. The operator's billing org may have quotas / budgets / limits that differ from the lost project's posture.
**Impact:** First deploy fails with quota exhaustion or billing-not-enabled error; or, more insidiously, succeeds but consumes more budget than expected once preview deploys multiply (each preview is a separate Cloud Run revision drawing min-instance and request-billed CPU/memory).

**Mitigation:**
- #237's Definition of Done includes a billing-account verification step (confirm billing is enabled and a budget alert is set at ≥ $50/month threshold).
- Audit default Cloud Run quotas via `gcloud compute project-info describe --project=$NEW_GCP_PROJECT_ID` post-provisioning; raise if needed before first deploy.
- Verify Artifact Registry storage quota; default is multi-TB so unlikely to bind.
- Enable Cloud Logging exclusion filters for noisy preview-deploy logs if cost ramp surprises (likely a no-op given low traffic).

### R20 — External links pointing at legacy production URL (NEW per v4)

**Likelihood:** Medium. The legacy URL `agile-flow-app-heo5ry7rua-uc.a.run.app` is referenced in `docs/LAUNCH-CHECKLIST.md` (line 10 and others), `CLAUDE.md`, possibly session journals, possibly older PR descriptions, possibly external surfaces (team Slack, blog posts, README badges). The legacy runtime continues to serve for an unknown period from the inaccessible project; eventually Google reclaims it for non-payment, after which the URL 404s.
**Impact:** Two layered failure modes:
1. **Short term (legacy runtime still up, possibly serving stale code):** users / scripts / docs that link to the old URL get a response — but it's from the orphaned runtime, NOT the new `masterkey` deployment. They see stale UI, stale data semantics, stale auth allowlist behavior. Confusing but recoverable.
2. **Long term (legacy URL reclaimed):** anything still linking to it 404s. Less surprising than (1) but more disruptive if it happens during an active user session.

**Mitigation:**
- v4 Phase 5 step 5 enumerates external references via `rg 'agile-flow-app-heo5ry7rua' .` across the repo, plus a manual audit of team comms surfaces.
- Update `docs/LAUNCH-CHECKLIST.md`, `CLAUDE.md`, and any other repo-controlled doc to point at the new `masterkey-*.run.app` URL (this is partially handled by E4-T3 / #206 already).
- For external surfaces (blog, Slack history): add a sticky-pin note explaining the URL change. Cannot redirect at the DNS layer since we don't own a custom domain.
- The session-journal historical record is intentionally NOT updated — it's a log, not a maintained reference (consistent with §6 policy).
- Accept that the legacy URL will eventually 404 silently; this is the cost of losing project ownership and was already absorbed in the operator's pivot decision.

### R21 — `provision-gcp-project.sh` defaults `ARTIFACT_REPO=agile-flow` if env var unset (NEW per v4.1 / DevOps)

**Likelihood:** Certain if #237's happy-path step 4 omits `ARTIFACT_REPO=masterkey` (the current ticket body does omit it).
**Impact:** Script creates an Artifact Registry repo named `agile-flow` in the new project. Subsequent CI deploys (with `vars.ARTIFACT_REPO=masterkey`) try to push to a `masterkey` AR repo that doesn't exist; deploy fails with `repository not found`. Operator now has a dead `agile-flow` AR repo in the new project + must create a `masterkey` repo separately. Re-running the script with the corrected env vars is idempotent (per `provision-gcp-project.sh:308`) but leaves the `agile-flow` repo as dead weight.

**Mitigation:**
- #237's body MUST explicitly set `ARTIFACT_REPO=masterkey` in step 4 (per the v4.1 §6 callout — BC2 correction). Same for `CLOUD_RUN_SERVICE=masterkey`.
- #237's DoD MUST include `gcloud artifacts repositories describe masterkey --location=us-central1 --project=$NEW_GCP_PROJECT_ID` returning success (per the v4.1 §6 DoD check 2).
- Overlap with B4-listed #196 (rename script defaults from `agile-flow*` to `masterkey*`) — but #196 lands in the Phase 1 PR AFTER #237 runs, so the rename doesn't help #237. Operator must override the defaults at invocation time.

### R22 — Placeholder Cloud Run service ships with no env vars; R13 still applies on first real deploy (NEW per v4.1 / DevOps)

**Likelihood:** Low for the steady state; medium if anyone manually `gcloud run deploy`s between #237 finishing and the first `deploy.yml` run.
**Impact:** `provision-gcp-project.sh:800-825` creates the placeholder Cloud Run service with `--image=us-docker.pkg.dev/cloudrun/container/hello`, `--allow-unauthenticated`, `--port=8080`, and **no `--set-env-vars`**. First `deploy.yml` run uses `--update-env-vars` semantics (set/replace per the deploy.yml comment lines 192-196), so it creates all env vars as literals — matches the deploy.yml intent and works cleanly. **The R13 risk re-applies** only if anyone manually `gcloud run deploy`s with `--set-secrets DATABASE_URL=...` between #237 finishing and the first `deploy.yml` run; that would brick the service per Cloud Run's env-var-type stickiness, requiring destructive recreate.

**Mitigation:**
- Phase 3 verification checklist step 3 (already in plan) explicitly verifies env-var types match `deploy.yml`'s shape (literals for `DATABASE_URL` / `ANTHROPIC_API_KEY`, `valueFrom: secretKeyRef:` for Supabase keys).
- #237's DoD check 4 (v4.1) explicitly runs `gcloud run services describe masterkey --format=yaml | grep -E 'name: (DATABASE_URL|ANTHROPIC_API_KEY)' -A 2` and requires empty output (or literal-only) — catches any manual `--set-secrets` interference before the first preview-deploy lands.
- Operational convention: do NOT manually `gcloud run deploy` against `masterkey` between #237 finish and Phase 1 PR merge; let `deploy.yml` be the first thing to populate env vars.

### R23 — API-enable list mismatch between #237 body and `provision-gcp-project.sh` (NEW per v4.1 / DevOps)

**Likelihood:** Certain (the two lists disagree today).
**Impact:** Low. #237's step 3 enables `run`, `artifactregistry`, `iamcredentials`, `cloudbuild`, `secretmanager` (5 APIs). `provision-gcp-project.sh:297-304` enables `run`, `artifactregistry`, `secretmanager`, `iam`, `iamcredentials`, `billingbudgets` (6 APIs). Differences: #237 includes `cloudbuild` (NOT used by `deploy.yml`, which does a local `docker build`); #237 OMITS `iam` (usually enabled by default on new projects, but if not, the script's own IAM-policy-binding calls fail) and `billingbudgets` (needed for R19's budget alert).

If the operator runs #237 step 3 verbatim and skips step 4 (or runs them in either order), the resulting project may be missing `billingbudgets` (R19 mitigation breaks) and have `cloudbuild` enabled gratuitously (no impact, just a wasted enabled API). The script's step 5 (line 297-304) re-enables APIs idempotently, so running the script masks the issue — but only if step 4 runs at all.

**Mitigation:**
- #237's body (per v4.1 §6 callout) reconciles step 3's API list with the script's (use the script's 6-API list; drop `cloudbuild`).
- Defense-in-depth: the script's idempotent re-enable in step 5 means even if #237 step 3 is wrong, running step 4 fixes it.

### R24 — Supabase webhook URLs unaffected by GCP project change (NEW per v4.1 / DevOps — informational, no action)

**Likelihood:** N/A (clarification, not a risk).
**Impact:** N/A — read-only verification confirms no impact.

**Note:** The Supabase GitHub App's per-PR branching webhooks point at supabase.com endpoints, NOT at our Cloud Run service. Switching GCP projects has no effect on those URLs. The Supabase Auth dashboard's redirect-URL allowlist IS scoped to OUR Cloud Run URLs (R4 / R12 still apply) but is keyed against the Supabase project (`gnswmcgaztcxslirulwm`), unaffected by GCP project changes. Logged here for completeness so a future reviewer doesn't re-investigate.

### R25 — Old GCP project may still be accruing charges despite IAM access loss (NEW per v4.1 / DevOps)

**Likelihood:** High. "Operator lost access" likely means lost IAM access to the project, not loss of the billing relationship — billing keeps running until the billing-org owner intervenes.
**Impact:** Orphaned legacy runtime continues to accrue:
- Cloud Run charges (`deploy.yml:168` hardcodes `--min-instances=1`, so the service draws min-instance billing 24/7).
- Cloud Logging ingestion charges (logs retention is per-project; even orphaned services emit logs).
- Artifact Registry storage charges for the historical image manifests.
The cost is bounded (small Cloud Run service, low traffic) but not zero — likely tens of dollars per month, indefinitely, until the billing org owner shuts it down or Google reclaims the project for non-payment of an unrelated invoice.

**Mitigation:**
- Operator should file a billing-org case to either (a) regain access enough to set `--min-instances=0` and stop logging ingestion, or (b) initiate project shutdown via the billing console (Project Settings → Shut down). Project shutdown is available to anyone with `roles/billing.admin` on the billing account regardless of project-level IAM, so this is achievable even without project-level access.
- If (a) and (b) are both unavailable: accept the cost until Google reclaims the project for non-payment of some other invoice. The legacy URL `agile-flow-app-heo5ry7rua-uc.a.run.app` continues to serve from the orphaned runtime until that happens (R20 short-term failure mode).
- Recommend operator at minimum escalate to the billing org owner before accepting indefinite charges. This is a one-email task, not a multi-step recovery.

---

## 5. Resolved decisions (was "open questions" in v1)

All ten v1 open questions have been resolved by DevOps. Folded into the plan as decisions:

| # | Question (v1) | Decision (v2) | Folded into |
|---|---------------|---------------|-------------|
| Q1 | Blue/green via Cloud Load Balancer + custom domain before rename? | **No.** Stick with destructive create-new-then-delete-old. Pre-creating `masterkey` in Phase 3 step 23 gives 99% of the blue/green benefit. CLB requires a week of work + new IAM role + DNS dependency — out of locked scope. | §3 Phase 3, Out of Scope |
| Q2 | What does the WIF condition look like today? | The provider's attribute-condition is `assertion.repository != ''` (trivially true). The repo pin lives on the deployer SA's IAM policy as a `principalSet` member with BOTH `roles/iam.workloadIdentityUser` AND `roles/iam.serviceAccountTokenCreator`. The actual fix is Phase 2 step 16 dual-write. | §2.1, §2.3, §3 Phase 2 step 16, R3 |
| Q3 | Secret Manager secret renames? | **No.** Leave `supabase-url`, `supabase-anon-key`, `supabase-service-key` unchanged. Generic names, no `cubrox` in them, runtime SA already bound. Renaming costs 4-step coordinated dance for zero benefit. | §2.3 |
| Q4 | Artifact Registry cleanup window? | **30 days, not 7.** Storage is $0.10/GB-month (rounding error). The only way to roll back to a specific commit-SHA revision is to re-pull that image. | §2.3, §3 Phase 5 |
| Q5 | Widen WIF to `repository_owner == 'cubrox'`? | **No, keep per-repo binding.** Each rename is a one-time event; widening means any new repo under `cubrox` (workshop fork, accidental create) inherits production-deploy capability. Defense-in-depth > audit convenience. | §3 Phase 2 step 16, R3 |
| Q6 | Custom domain timing? | **Defer entirely.** Requires registered domain, DNS, managed cert (15-30 min provisioning), new Supabase allowlist round, new magic-link testing. Bundle would also delay Phase 5 cleanup. File as separate post-launch epic. | Out of Scope |
| Q7 | Enumerate Cloud Logging / Monitoring assets? | **Phase 0 step 4 enumeration.** Expected to be empty per ADR-004 (Sentry deferred). Update if non-empty in Phase 5 step 39. | §3 Phase 0 step 4, §3 Phase 5 step 39 |
| Q8 | `SUPABASE_DB_URL` secret survives rename? | **Yes** (repo secrets are repo-scoped, not name-scoped). Question struck — over-cautious. | §2.1 |
| Q9 | Synthetic monitor cron during cutover? | **Disable cleanly, do not rely on luck.** Cron in GitHub Actions can fire up to ~15 min late. Comment out `schedule:` block in Phase 1 PR; restore in small follow-up PR in Phase 4 step 32. | §3 Phase 1 step 13, §3 Phase 4 step 32 |
| Q10 | `--min-instances=1` cost during dual-service window? | **Set `--min-instances=0` on the placeholder.** Keeping the smoke image warm risks loud false-alarms if the smoke image has any problem. `deploy.yml:168` hardcodes `--min-instances=1` on the real deploy, so the Phase 4 deploy flips it automatically. | §3 Phase 3 step 23 |

---

## 6. Backlog reconciliation post-pivot (v4 NEW)

Explicit per-ticket actions in light of the GCP pivot. Three action verbs:

- **KEEP** — ticket is unchanged in scope and acceptance criteria; just proceed.
- **REWORK** — ticket's intent is still valid but the description / steps / DoD need editing for the new context. A "what changes" note is provided.
- **CLOSE** — ticket is obsolete (the work no longer exists, or was never doable in the post-pivot reality). Close as not-planned with a comment pointing at this plan §6 row.

This table is the to-do list for whoever does the post-pivot grooming pass. **No tickets are closed automatically by this plan revision; the operator (or PO) executes the reconciliation table.**

| # | Title (abbreviated) | Action | Reason / what changes |
|---|---------------------|--------|------------------------|
| #181 | Epic 1 — Phase 0 (epic) | REWORK | Narrow scope: GCP snapshot work N/A; epic is now GitHub-side inventory only (board items #187, open-PR check, forks). Update epic body to describe v4 narrowed scope. |
| #182 | Epic 2 — Phase 1 (epic) | KEEP | Codebase rename PR is GCP-independent. Sub-tickets #192-#199 unchanged. |
| #183 | Epic 3 — Phase 2 (epic) | KEEP | Repo rename + board migration + WIF re-bind (in new project). Sub-ticket #200's intent shifts (see below) but epic shape is the same. |
| #184 | Epic 4 — Phase 3 (epic) | REWORK | Narrow scope: most pre-create infra work is absorbed by #237. Epic becomes "verification + Supabase allowlist + optional dry-run". |
| #185 | Epic 5 — Phase 4 (epic) | REWORK | Collapse to 3 steps: merge PR, verify masterkey health, restore synthetic monitor. The var-flip dance (#212, #213) and old-service health check (#211) disappear. |
| #186 | Epic 6 — Phase 5 (epic) | REWORK | Half the work is N/A (old project inaccessible). Epic now: WIF prune in new project, Memory MCP audit, ADR-007, doc cleanup including new R20. |
| #187 | Inventory `vibeacademy/projects/29` | KEEP | Still valid; feeds #203 (board migration). |
| #188 | Snapshot Cloud Run + SA IAM + secrets | CLOSE | Obsolete — old project inaccessible; cannot snapshot. |
| #189 | Verify WIF binding shape | ALREADY CLOSED 2026-06-30 | Same reason; closed not-planned. |
| #190 | Enumerate Cloud Logging | CLOSE | Obsolete — old project inaccessible. New project starts empty. |
| #191 | Bundle Phase 0 snapshots into PR | CLOSE | Obsolete — nothing to bundle without #188/#190. |
| #192 | Rename `CUBROX_TEST_SEED_ENABLED` env var | KEEP | Codebase change; GCP-independent. |
| #193 | Rename `window.cubroxLineCount` | KEEP | Same. |
| #194 | Rename app metadata strings | KEEP | Same. |
| #195 | Rename `tests/a11y` package | KEEP | Same. |
| #196 | Rename `provision-gcp-project.sh` + `diagnose-cloudrun.sh` defaults | KEEP | Same. Note: `provision-gcp-project.sh` was recently used by #237, so post-rename it documents the new project's recreation steps. |
| #197 | Update `supabase/config.toml` + `CLAUDE.md` | REWORK | Add line for new GCP project ID. Add line for new production URL (gets a placeholder until #206 captures it). |
| #198 | `.gembaflow-overrides` agent persona renames | KEEP | Same. |
| #199 | Disable synthetic monitor schedule for cutover | KEEP | Same. The cutover window risk shape is identical. |
| #200 | E3-T1 WIF dual-write | REWORK (v4.1 — explicitly NOT superseded by #237; BC1 / NS4) | **NOT superseded by #237.** #237 provisions ONE binding (`cubrox/cubrox`, matching the repo name at provisioning time); #200 adds the SECOND binding (`cubrox/masterkey`) on the same NEW project's deployer SA BEFORE `gh repo rename` fires (#201). Both bindings live in parallel through the rename and are pruned to one (`cubrox/masterkey` only) in Phase 5 via #220. Operator confirmed the dual-write approach 2026-06-30. **What changes vs. v3:** member URI uses `$NEW_GCP_PROJECT_ID`'s project number (not the legacy project's). DoD: verify both bindings exist on the new SA before #201 fires, via `gcloud iam service-accounts get-iam-policy $SA_EMAIL --project=$NEW_GCP_PROJECT_ID --format=json` showing two `principalSet://` entries (one per WIF role × principalSet). Verification dispatch is `synthetic-monitor.yml workflow_dispatch` against the new service (v4.1 BC3 — NOT `rollback-production.yml`, which mutates traffic). |
| #201 | E3-T2 `gh repo rename cubrox/cubrox → cubrox/masterkey` | KEEP | Independent of GCP project identity. Pre-flight checklist still valid (drops the "vars unflipped" check since there's no flip). |
| #202 | E3-T3 Create new project board | ALREADY DONE | Board #2 created on cubrox user account 2026-06-30. Close as done with link to board. |
| #203 | E3-T4 Migrate 67 items from old board | KEEP | Independent of GCP. |
| #204 | E4-T1 Create masterkey AR repo + grant SA reader | CLOSE | Obsolete — folded into #237's provisioning. Add a verification comment to #237 confirming AR repo + IAM binding exist. |
| #205 | E4-T2 Pre-create Cloud Run masterkey service (R13 env-var types) | REWORK | Reframe as a verification-only ticket: confirm the `masterkey` service exists post-#237 with correct env-var types (`DATABASE_URL` + `ANTHROPIC_API_KEY` as literals, Supabase keys as `valueFrom: secretKeyRef:`). If #237 set them wrong, recreate the service before any preview deploy lands. |
| #206 | E4-T3 Capture new service URL + pin to docs | KEEP | Still valid — runs against the post-#237 service. The "new URL" is just the masterkey service URL once #237 finishes. |
| #207 | E4-T4 Add new Supabase Auth allowlist entries | KEEP | Still valid. v4 note: keep old `agile-flow-app-*` entries indefinitely (harmless; legacy URL is orphaned). |
| #208 | E4-T5 Dry-run preview-deploy against masterkey | REWORK | Downgrade priority P0 → P1 (or P2). The race window it was meant to verify does not exist in v4. Useful as a smoke test but optional; Phase 1 PR's own preview serves the same role. |
| #209 | E4-T6 Verify Supabase GitHub App allowlist post-rename | KEEP | Still valid; the rename still triggers the App allowlist re-verification. |
| #210 | E5-T1 Merge Phase 1 PR with vars STILL `agile-flow-app` | REWORK | Drop the "with old vars" framing. Reframe as: "Merge Phase 1 PR; `deploy.yml` deploys to `masterkey` directly (vars are already set by #237)." Remove guardrails that check var values are still `agile-flow-app`. |
| #211 | E5-T2 Verify agile-flow-app health post-merge | CLOSE | Obsolete — old service inaccessible and would not receive the new deploy anyway (vars point at masterkey from day 1 in v4). |
| #212 | E5-T3 Flip GitHub vars to masterkey | CLOSE | Obsolete — done by #237. Optionally: rework to a one-line "verify `gh variable list` shows masterkey already set" check, but that's a 30-second task that doesn't need its own ticket. Close as superseded. |
| #213 | E5-T4 Push trivial CHANGELOG commit to trigger deploy | REWORK | Demote to optional. v4 reframing: Phase 1 PR merge already triggers `deploy.yml`. A separate trivial-commit ticket is needed ONLY if Phase 1 PR is delayed and we want to verify deploy plumbing before then. Otherwise close as duplicate of #210. |
| #214 | E5-T5 Verify masterkey service health after first real deploy | KEEP | Still valid — only verification step in v4 Phase 4. Becomes more important since there's no second-chance "old service serving prod" fallback. |
| #215 | E5-T6 Re-enable synthetic monitor | KEEP | Pairs with #199. |
| #216 | E5-T7 Announce new URL + update external references | KEEP | Still valid; folds in R20 enumeration work. |
| #217 | E6-T1 Delete old Cloud Run service | CLOSE | N/A — old project inaccessible. |
| #218 | E6-T2 Archive image manifests + delete old AR repo | CLOSE | N/A — same reason. |
| #219 | E6-T3 Remove old Supabase Auth allowlist entries | REWORK | Demote to optional (P2 → P3). The old entries are harmless once the legacy runtime is orphaned. Architect's recommendation: leave them for 6+ months. |
| #220 | E6-T4 Remove old WIF binding for cubrox/cubrox | REWORK | What changes: now refers to the binding in the NEW project (added by #237 at provisioning time, before repo rename). After Phase 2 step 16 dual-writes the `cubrox/masterkey` binding, this ticket prunes the `cubrox/cubrox` binding in the SAME new project. |
| #221 | E6-T5 Update Cloud Logging saved queries | REWORK | Most likely closes as no-op (new project starts empty by construction; no inherited filters). Confirm and close. |
| #222 | E6-T6 Memory MCP audit | KEEP | Still valid. |
| #223 | E6-T7 Write ADR-007 + resolve PLATFORM-GUIDE drift | REWORK | Add to ADR-007 scope: document the GCP pivot (project-lost-then-re-provisioned) as a load-bearing fact of the rename history. |
| #224-#231 | Phase -1 epic + sub-tickets | ALREADY CLOSED | Closed via PR #232 and follow-ups. |
| #233 | json-validate ruleset split | ALREADY CLOSED | Closed via PR #236. |
| #234 | bot.reviewer alignment | ALREADY CLOSED | Closed via PR #235. |
| #237 | Provision new GCP project as masterkey from day 1 | REWORK BODY (v4.1 — BC1 + BC2) — KEEP scope, IN FLIGHT | The umbrella ticket that triggers this v4 revision. Must complete before #200 + #201 fire. **Body needs three edits — see `#237 body MUST include` callout below this table.** Scope of WORK is unchanged; only the ticket's body text changes. |

### `#237 body MUST include` callout (v4.1 — BC1 + BC2)

The orchestrator must edit issue #237's body to reflect three corrections that the current body gets wrong. Plan content here is the authoritative spec for what the body should say. This plan does NOT edit the issue itself — that's the orchestrator's job.

**Correction 1 — WIF dual-write IS required (BC1).** #237's current body says, in its "Blocks / supersedes" section, that #200 is "superseded; this ticket creates the binding fresh, no dual-write needed." That statement is WRONG and must be replaced. The correct statement:

> **#200 remains REQUIRED — not superseded.** This ticket (#237) provisions ONE WIF binding on the new project's deployer SA for `principalSet://.../attribute.repository/cubrox/cubrox` (matching the repo name at provisioning time, since the rename has not yet happened). Before `gh repo rename cubrox/cubrox → cubrox/masterkey` fires (#201, Phase 2 step 17), #200 must add a SECOND parallel binding for `principalSet://.../attribute.repository/cubrox/masterkey` to the same SA, on the same new project. Without #200, every workflow that authenticates to GCP after the rename will fail with `iam.serviceAccounts.getAccessToken denied` — same R3 failure mode v3 was engineered to prevent. The dual-write is pruned to a single binding (`cubrox/masterkey`) in Phase 5 via #220. Operator confirmed this approach 2026-06-30.

Any nearby text in #237 implying that "Epics 3-5 collapse" applies to Phase 2's WIF re-bind step is ALSO wrong and must be reworded — Phases 3 / 4 / 5 do collapse substantially per v4, but the Phase 2 WIF re-bind (step 16) is NOT collapsed; the dual-write executes as written above.

**Correction 2 — `provision-gcp-project.sh` env-var contract (BC2).** #237's current happy-path step 4 invokes the provision script with `GCP_PROJECT_ID=<NEW> GITHUB_REPO=cubrox/cubrox bash scripts/provision-gcp-project.sh`. This is WRONG and causes silent skip of the entire WIF setup block. Verified by reading `scripts/provision-gcp-project.sh` lines 402-478:

- Line 404: `WIF_OWNER="${GITHUB_OWNER:-${GITHUB_USERNAME:-}}"` — sources from `GITHUB_OWNER` or `GITHUB_USERNAME`, NOT from `GITHUB_REPO`.
- Line 405: `WIF_REPO_NAME="${GITHUB_REPO:-agile-flow-gcp}"` — `GITHUB_REPO` is the BARE REPO NAME within the owner, not `owner/name`.
- Line 407: `if [[ -n "$WIF_OWNER" ]]; then` — guards the entire WIF block (pool create, provider create, SA bindings).
- Line 478: `[skip] WIF setup not requested (GITHUB_OWNER and GITHUB_USERNAME unset)` — silent skip path.
- Line 60: `ARTIFACT_REPO` defaults to `agile-flow` if unset (R21).
- Line 800: `SERVICE_NAME` defaults to `agile-flow-app` if `CLOUD_RUN_SERVICE` is unset.
- Line 465: `WIF_MEMBER="principalSet://.../attribute.repository/${WIF_OWNER}/${WIF_REPO_NAME}"` — note the slash is inserted by the script, so passing `GITHUB_REPO=cubrox/cubrox` (with the slash already in it) would produce a malformed 3-segment URI even if `WIF_OWNER` were correctly set.
- Line 862: GitHub-secrets push is gated on `GITHUB_REPOSITORY` being set; without it, secrets are printed rather than pushed.

The correct invocation #237's step 4 must read:

```bash
GCP_PROJECT_ID=<new-project-id> \
ARTIFACT_REPO=masterkey \
CLOUD_RUN_SERVICE=masterkey \
GITHUB_OWNER=cubrox \
GITHUB_REPO=cubrox \
GITHUB_REPOSITORY=cubrox/cubrox \
bash scripts/provision-gcp-project.sh
```

Note: `GITHUB_REPO=cubrox` (bare repo name) because the GitHub slug is `cubrox/cubrox` (owner `cubrox`, repo `cubrox`); the `WIF_MEMBER` URI assembled by line 465 then correctly resolves to `.../attribute.repository/cubrox/cubrox`. `GITHUB_REPOSITORY=cubrox/cubrox` enables the Step 7 auto-push of `GCP_PROJECT_ID`, `GCP_SERVICE_ACCOUNT`, and `GCP_WORKLOAD_IDENTITY_PROVIDER` GitHub Actions secrets — without it #237's step 6 ("verify secrets") would be doing work that step 4 should have already done.

**Correction 3 — Post-provisioning DoD checks (BC1 + BC2 + R19 + R22).** #237's Definition of Done must include the following one-line verification commands; each catches a v4.1-flagged failure mode before the next phase starts:

1. `gcloud iam service-accounts get-iam-policy "$SA_EMAIL" --project="$NEW_GCP_PROJECT_ID" --format=json | grep -c 'principalSet'` MUST return ≥ 2 (two WIF roles × one binding for `cubrox/cubrox`). If 0, BC2 happened: WIF was silently skipped — re-run the script with the env vars above. (BC2 verification.)
2. `gcloud artifacts repositories describe masterkey --location=us-central1 --project="$NEW_GCP_PROJECT_ID"` MUST succeed. If the script created `agile-flow` instead, R21 happened — set `ARTIFACT_REPO=masterkey` and re-run. (R21 verification.)
3. `gcloud run services describe masterkey --region=us-central1 --project="$NEW_GCP_PROJECT_ID" --format='value(status.url)'` MUST return a URL. If it returns "service not found" or describes `agile-flow-app` instead, the `CLOUD_RUN_SERVICE` default fired — set the env var and re-run. (BC2 + R21 sibling check.)
4. `gcloud run services describe masterkey --region=us-central1 --project="$NEW_GCP_PROJECT_ID" --format=yaml | grep -E 'name: (DATABASE_URL|ANTHROPIC_API_KEY)' -A 2` — the placeholder service has NO env vars per `provision-gcp-project.sh:800-825` (uses the hello image). First `deploy.yml` run populates them via `--update-env-vars` semantics. **R22 risk:** if anyone manually `gcloud run deploy`s with `--set-secrets DATABASE_URL=...` between #237 finishing and the first `deploy.yml` run, R13 (env-var type stickiness) bricks the service. DoD: confirm output is empty (or only contains literals matching `deploy.yml`'s shape) before the first preview-deploy lands. (R22 verification.)
5. `gcloud billing projects describe "$NEW_GCP_PROJECT_ID" --format='value(billingEnabled)'` MUST return `True` AND `gcloud billing budgets list --billing-account=$BILLING_ACCOUNT --format='value(displayName)' | grep -c "$NEW_GCP_PROJECT_ID"` MUST return ≥ 1 (budget alert exists). If 0, R19 happened — operator must set up the budget alert manually via the billing console. (R19 verification, per NS1.)
6. `gh variable list --repo cubrox/cubrox | grep -E 'CLOUD_RUN_SERVICE|ARTIFACT_REPO'` MUST show both as `masterkey`. If absent, the Step 7 auto-push was skipped because `GITHUB_REPOSITORY` was unset — set it and re-run, or push the vars manually with `gh variable set`. (BC2 sibling check.)

Additionally: the API-enable list in #237's step 3 (`run`, `artifactregistry`, `iamcredentials`, `cloudbuild`, `secretmanager`) does NOT match `provision-gcp-project.sh:297-304` (`run`, `artifactregistry`, `secretmanager`, `iam`, `iamcredentials`, `billingbudgets`). The script's list is more accurate for our shape — `deploy.yml` does NOT use Cloud Build (it runs a local `docker build` then pushes), and `billingbudgets` is needed for R19's mitigation. Reconcile #237's step 3 to use the script's six-API list (`run`, `artifactregistry`, `secretmanager`, `iam`, `iamcredentials`, `billingbudgets`) and drop `cloudbuild`. (R23 reconciliation.)

**Reconciliation summary (47 table rows covering 53 in-scope tickets — one row aggregates the 8 Phase -1 sub-tickets #224-#231; v4.1 updates #237's classification from KEEP to REWORK-BODY):**
- **CLOSE** (obsolete): 8 tickets — #188, #190, #191, #204, #211, #212, #217, #218.
- **REWORK** (intent valid; scope/steps change — includes 4 epic-body refreshes and v4.1's #237 body edit): 15 tickets — #181, #184, #185, #186, #197, #200, #205, #208, #210, #213, #219, #220, #221, #223, #237 (v4.1 — body edit only; scope unchanged).
- **KEEP** (unchanged scope and acceptance criteria): 19 tickets — #182, #183, #187, #192, #193, #194, #195, #196, #198, #199, #201, #203, #206, #207, #209, #214, #215, #216, #222.
- **ALREADY CLOSED / DONE pre-v4** (action: none): 11 tickets — #189 (closed 2026-06-30), #202 (board #2 created 2026-06-30), #224-#231 (Phase -1, PR #232), #233 (PR #236), #234 (PR #235).

Net: of 53 in-scope tickets (#181-#223 + #233, #234, #237), v4.1 closes 8 as obsolete, reworks 15 (one of which is #237's body-only edit), keeps 19 unchanged, and inherits 11 already done. Critical chain shrinks from v3's 12 tickets to v4's 8 (unchanged in v4.1).

---

## 6.1 Updated dependency graph (v4)

The v3 critical chain (`E1-T3 → E3-T1 → E3-T2 → E4-T2 → E4-T3 → E4-T4 → E4-T5 → E5-T1 → E5-T2 → E5-T3 → E5-T4 → E5-T5`) collapses substantially. v4 chain:

```
#237 (provision new GCP project as masterkey)
   │
   │   • new project ID, deployer SA, WIF binding (cubrox/cubrox)
   │   • GitHub repo secrets rotated: GCP_PROJECT_ID, GCP_SERVICE_ACCOUNT,
   │     GCP_WORKLOAD_IDENTITY_PROVIDER
   │   • GitHub repo vars set: CLOUD_RUN_SERVICE=masterkey, ARTIFACT_REPO=masterkey
   │   • first deploy creates `masterkey` Cloud Run service
   ▼
#187 (inventory legacy board)   ──┐
#199 (disable synthetic monitor) ──┤  Parallel-OK with Phase 1
ALL #192-#198 (Phase 1 code) ─────┤  ← single PR (Phase 1 PR)
                                  ▼
                            #200 (WIF dual-write for cubrox/masterkey
                                  in NEW project — Phase 2 step 16)
                                  │
                                  ▼
                            #201 (gh repo rename cubrox/cubrox → cubrox/masterkey)
                                  │
                                  ├──► #202 already done (board #2 created)
                                  ├──► #203 (migrate 67 items)
                                  ├──► #209 (Supabase GitHub App allowlist verify)
                                  ▼
                            #205 (verify masterkey service env-var types)
                                  │
                                  ▼
                            #206 (capture URL → docs)
                                  │
                                  ▼
                            #207 (Supabase Auth allowlist + new URLs)
                                  │
                                  ▼
                            (optional) #208 (dry-run preview-deploy)
                                  │
                                  ▼
                            #210 (merge Phase 1 PR → deploys to masterkey)
                                  │
                                  ▼
                            #214 (verify masterkey health)
                                  │
                                  ▼
                            #215 (re-enable synthetic monitor)
                                  │
                                  ▼
                            #216 (announce new URL, R20 enumeration)
                                  │                30-day timer
                                  ╰─────────────────────────► Phase 5
                                                #220 (prune cubrox/cubrox WIF
                                                       binding in new project)
                                                #221 (Cloud Logging — likely no-op)
                                                #222 (Memory MCP audit)
                                                #223 (ADR-007)
                                                (#219 demoted to optional)
```

**v4 critical chain (8 tickets, was 12):** `#237 → ALL #192-#198 (Phase 1) → #200 → #201 → #205 → #207 → #210 → #214`.

**What blocks the most downstream work in v4:** still #201 (repo rename). It unblocks: #203, #209, #205, #206, #207, #208, #210, #214, #215, #216, #220. Eleven downstream tickets — down from v3's 23, because Phases 3/4/5 are dramatically simpler.

---

## 7. Out of scope

Explicitly NOT part of this refactor:

- **Old GCP project recovery.** Per v4 operator decision 2026-06-30. The legacy project is abandoned; we don't attempt to regain access. (Was implicit in v3; explicit in v4.)
- **Custom domain to mask the legacy URL.** v4 R20 documents the orphaned legacy URL as an accepted cost. A custom domain would cleanly cover it but remains deferred per resolved Q1 + Q6.
- **GCP project ID rename.** Per locked scope. Would require recreating IAM bindings, WIF pool, secrets, the whole project — orders of magnitude more work.
- **Supabase project ref change.** Per locked scope. Would require database migration, RLS re-deploy, JWT signing-key rotation, redirect-URL migration, magic-link template re-deploy, and a downtime window for the cutover. Out of scope.
- **Supabase org rename.** If the Supabase org happens to be named `vibeacademy` in the dashboard, that's a separate change managed in the Supabase UI and not coupled to this refactor.
- **Custom domain introduction.** Per resolved Q1 + Q6 — deferred as a separate post-launch epic.
- **Cloud Load Balancer / blue-green via traffic-splitting.** Per resolved Q1.
- **Widening WIF to org-level.** Per resolved Q5 — defense-in-depth precludes it.
- **Renaming Secret Manager secrets to add a project prefix.** Per resolved Q3.
- **Public brand change.** "Master Key" is already the public name. This refactor does NOT rename the brand to "masterkey-lowercase" or anything like that.
- **`pyproject.toml` rename.** The framework starter name `agile-flow-gcp` is intentionally preserved. See R6 for audit notes if a future maintainer ever does rename it.
- **Framework artifact renames** (`scripts/template-sync.sh`, `.agile-flow-version` upstream URL, `bootstrap.sh`, the bulk of `scripts/*.sh` that are NOT in `.agile-flow-overrides`). These point at the *Agile Flow framework template*, not the *Master Key product*. Editing them would break framework sync. **NOTE:** `scripts/provision-gcp-project.sh` and `scripts/diagnose-cloudrun.sh` ARE in scope (per B4) because they're in `.agile-flow-overrides`.
- **CHANGELOG link rewrites for historical entries.** The historical record stays as written. Only the post-rename entries reflect the new repo URL.
- **Memory MCP entity migration.** Out of immediate scope; flagged as follow-up under R7.
- **Session-journal historical rewrites.** `reports/session-journals/*.md` stay as written — they're a historical log, not a maintained reference.
- **Database table renames, ORM model renames, API path renames.** Nothing in the persistence layer or HTTP API surface contains "cubrox" — verified via `grep`. No data migration needed.
- **Code package rename** (`app/` -> `masterkey/`). The codebase uses `app` as the import root, which is project-neutral. Renaming it would touch every import line for no functional benefit.
- **Adding `workflow_dispatch:` to `deploy.yml`.** Per S1 — useful escape hatch independent of the rename, but defer to a separate follow-up so the rename PR stays single-purpose.

---

**Result:** Refactor plan revised (v4.1) — DevOps revision pass on v4 (2026-06-30) addressing BC1/BC2/BC3 from `reports/refactor/02c-devops-signoff-v4.md`.
Scope (unchanged from v4): `cubrox` codebase + infra identifier rename to `masterkey`, executed against a NEW GCP project provisioned by #237 (legacy project inaccessible).
Recommendation (v4.1): orchestrator edits #237 body per the §6 "**#237 body MUST include**" callout (BC1 + BC2 fixes); then #237 fires; then Phase 1 codebase PR → #200 WIF dual-write (NOT skipped — `cubrox/masterkey` binding lands on new project's SA BEFORE rename) → repo rename → board migration → cutover (single Phase 1 PR merge) → Phase 5 cleanup. v4.1 unchanged from v4 in critical-chain ordering; the changes are in #237's body specification, Phase 2 step 16's verification mechanism, and §6 row clarity.
Phase -1 (framework alignment to gembaflow v1.5.0): DONE 2026-06-30.
Risks (v4.1): 22 identified (R1-R20 from v4 + R21 AR repo default + R22 placeholder env vars + R23 API list mismatch + R24 Supabase webhooks unaffected/informational + R25 legacy project billing). R3 (WIF auth) substantially mitigated by clean from-scratch provisioning + the explicit Phase 2 step 16 dual-write (now verified via `synthetic-monitor.yml workflow_dispatch` per BC3, not `rollback-production.yml`). R20 remains highest-attention residual risk; R25 surfaces an adjacent concern (legacy project still billing).
Reconciliation (§6): 8 tickets CLOSE, 15 REWORK (v4.1 reclassifies #237 from KEEP to REWORK-BODY — scope unchanged, body needs edits), 19 KEEP, 11 already done. Net work-effort reduction vs. v3: roughly half of Phase 3-5 work eliminated.
Out of scope: old GCP project recovery, GCP project ID rename, Supabase project ref, public brand, framework artifacts not in `.gembaflow-overrides`, `pyproject.toml`, custom domain, CLB.

**v4.1 highest-risk uncertainty to flag for operator:** the v4 dual-write decision stands. The v4.1 revision pass focuses on getting #237 to actually execute the dual-write correctly — namely, fixing #237's body so it (a) doesn't say "#200 superseded" (it isn't) and (b) invokes `provision-gcp-project.sh` with the right env vars so WIF setup doesn't silently no-op. The architectural choice ("dual-write in new project, prune old in Phase 5" vs. "re-run provision script after rename") is unchanged from v4 — both work; dual-write is cheaper and is what the operator's lock confirms.
