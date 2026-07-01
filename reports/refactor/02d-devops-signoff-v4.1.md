# DevOps Sign-off: `cubrox` -> `masterkey` Rename Plan v4.1 (round-2 focused revision)

**Reviewer:** DevOps Engineer persona
**Date:** 2026-06-30
**Plan under review:** `reports/refactor/01-architecture-plan.md` (v4.1 — 2026-06-30)
**Prior sign-off:** `reports/refactor/02c-devops-signoff-v4.md` (v4 — NEEDS_REVISION with BC1/BC2/BC3 + R21-R25)

---

## Verdict

**ALIGNED**

v4.1 fully resolves all three blockers from v4 and folds R21-R25 into the risk register with workable mitigations. The architect did not gold-plate — they made surgical edits in the exact places the v4 review called out, preserved everything that was already accepted, and the resulting plan is internally consistent. Most importantly, the #237 body-edit callout in §6 is precise, paste-correct, and matches the script's actual env-var contract on every name. The Phase 2 step 16 switch from `rollback-production.yml` to `synthetic-monitor.yml` is the right call for the right reason — `synthetic-monitor.yml workflow_dispatch` exercises the same `google-github-actions/auth@v3` step shape as `deploy.yml` (verified line-by-line) without any traffic-shift side effect.

No new blockers. One observation worth surfacing as a non-blocking suggestion (NS-V41-1 below) about the smoke-auth probe failing past the WIF step against the hello placeholder service — operator should know to read the run log for the auth-step pass/fail rather than just the overall workflow status. Not blocking because the recovery path is correct interpretation, not re-execution.

Cleared to fire #237 with the corrected body.

---

## Blocker resolution table

| ID | Resolved? | Where in v4.1 | Notes |
|----|-----------|---------------|-------|
| BC1 | Yes | §6 row #200 (line 835) + §6 row #237 (line 862) + §6 callout "Correction 1" (lines 868-872) + §3 Phase 2 step 16 preamble (lines 382, 384) | #200 explicitly REWORK not CLOSE; #237 row tagged "REWORK BODY"; callout dictates the exact replacement text including "operator confirmed 2026-06-30" provenance; the implied "Epics 3-5 collapse applies to Phase 2's WIF step" misreading is explicitly called out and forbidden. Cross-reference to step 16's preamble closes the loop between the §6 callout and the operational steps. |
| BC2 | Yes | §6 callout "Correction 2" (lines 874-897) + DoD check 1 (line 901) + DoD check 6 (line 906) + R21 (line 731) + R23 (line 751) | All six env vars listed correctly: `GCP_PROJECT_ID`, `ARTIFACT_REPO=masterkey`, `CLOUD_RUN_SERVICE=masterkey`, `GITHUB_OWNER=cubrox`, `GITHUB_REPO=cubrox` (bare repo name, not slug), `GITHUB_REPOSITORY=cubrox/cubrox`. Each name verified against script reality (see #237 body delta sanity check below). Each silent-skip failure mode (line 478 WIF skip, line 60 `ARTIFACT_REPO` default, line 800 `SERVICE_NAME` default, line 862 secret-push gate) is documented with the script line number that fires it. DoD checks 1, 2, 3, 6 each catch a specific BC2-flagged failure mode with a one-line `gcloud` or `gh` invocation. |
| BC3 | Yes | §3 Phase 2 step 16 verification block (line 401) + R3 mitigation (line 563) | Verification switched from `rollback-production.yml workflow_dispatch` to `synthetic-monitor.yml workflow_dispatch`. Plan explicitly explains why `rollback-production.yml` was rejected (mutates traffic via `gcloud run services update-traffic`, no dry-run mode), why `synthetic-monitor.yml`'s `schedule:` block being commented out per Phase 1 step 13 doesn't disable `workflow_dispatch` (the two triggers are independent), and provides an NS5 recovery path (re-run provision script with corrected env vars). R3 mitigation paragraph mirrors the rationale. |

All three blockers resolved with the right shape and the right level of explicitness.

---

## Risk register check (R21-R25)

| ID | Present? | Severity / Likelihood | Mitigation | Notes |
|----|----------|----------------------|------------|-------|
| R21 | Yes (lines 731-739) | Certain / High impact (dead AR repo + push failure) | #237 body sets `ARTIFACT_REPO=masterkey`; DoD check 2 verifies it; #196 doesn't help since it lands later | Correctly flags overlap with #196 timing. Mitigation is environmental at #237 invocation. Workable. |
| R22 | Yes (lines 741-749) | Low steady-state / Medium if manual `gcloud run deploy` interferes | Phase 3 verification step 3 + #237 DoD check 4 verify env-var types; operational convention "don't manually deploy between #237 finish and Phase 1 PR merge" | Honest about the residual: WIF auth itself isn't the issue; the issue is human discipline between two events. Mitigation is documentation + a single grep that catches the failure mode. Reasonable. |
| R23 | Yes (lines 751-760) | Certain mismatch / Low impact | #237 body reconciled to script's 6-API list (`run`, `artifactregistry`, `secretmanager`, `iam`, `iamcredentials`, `billingbudgets`); script's idempotent re-enable acts as defense-in-depth | Drops `cloudbuild` correctly (deploy.yml does local `docker build`, not Cloud Build). Right reconciliation direction. |
| R24 | Yes (lines 762-767) | N/A / Informational | None needed; documented as read-only check | Correctly downgraded from "risk" to "clarification so future reviewers don't re-investigate." Right call. |
| R25 | Yes (lines 769-781) | High / Tens of $$/month, bounded | Billing-org escalation: either regain access to set `min-instances=0`, or initiate project shutdown via billing console (works even without project-level IAM since `roles/billing.admin` operates on billing account); accept indefinite cost if both unavailable | Operationally sound. The "project shutdown via billing console works without project-level IAM" detail is correct and gives the operator a real recovery path. |

All five risks present. No new risks I'd flag that aren't already in the register. R25's mitigation is the most actionable single recovery the operator should do regardless — this is the highest-leverage item in the entire v4.1 risk register and the plan correctly identifies it as a one-email task.

---

## #237 body delta sanity check (paste-into-terminal correctness)

The v4.1 callout proposes #237's step 4 invocation be:

```bash
GCP_PROJECT_ID=<new-project-id> \
ARTIFACT_REPO=masterkey \
CLOUD_RUN_SERVICE=masterkey \
GITHUB_OWNER=cubrox \
GITHUB_REPO=cubrox \
GITHUB_REPOSITORY=cubrox/cubrox \
bash scripts/provision-gcp-project.sh
```

Cross-checked against `scripts/provision-gcp-project.sh` line-by-line:

| Env var | Script line | Behavior | Plan's choice | Verdict |
|---------|-------------|----------|---------------|---------|
| `GCP_PROJECT_ID` | (used throughout, no default) | Required; script errors if unset | `<new-project-id>` placeholder | Correct |
| `ARTIFACT_REPO` | 60 (`ARTIFACT_REPO="${ARTIFACT_REPO:-agile-flow}"`) | Defaults to `agile-flow` | `masterkey` | Correct — overrides the default |
| `CLOUD_RUN_SERVICE` | 800 (`SERVICE_NAME="${CLOUD_RUN_SERVICE:-agile-flow-app}"`) | Defaults to `agile-flow-app` | `masterkey` | Correct — overrides the default |
| `GITHUB_OWNER` | 404 (`WIF_OWNER="${GITHUB_OWNER:-${GITHUB_USERNAME:-}}"`) | Drives the WIF block gate (line 407) | `cubrox` | Correct — non-empty value enables WIF |
| `GITHUB_REPO` | 405 (`WIF_REPO_NAME="${GITHUB_REPO:-agile-flow-gcp}"`) | BARE repo name, not slug; defaults to `agile-flow-gcp` | `cubrox` | Correct — bare name. Line 465 then assembles `principalSet://.../attribute.repository/cubrox/cubrox`. |
| `GITHUB_REPOSITORY` | 862 (`if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then`) | Gates the `gh secret set` push (Step 7) | `cubrox/cubrox` | Correct — owner/repo slug, enables auto-push of GCP_PROJECT_ID, GCP_SERVICE_ACCOUNT, GCP_WORKLOAD_IDENTITY_PROVIDER |

**WIF_MEMBER assembly check.** Script line 465: `WIF_MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL}/attribute.repository/${WIF_OWNER}/${WIF_REPO_NAME}"`. With `WIF_OWNER=cubrox` and `WIF_REPO_NAME=cubrox`, the URI assembles to `...attribute.repository/cubrox/cubrox` — exactly two path segments after `attribute.repository/`, matching what GitHub's OIDC token presents for `cubrox/cubrox`. Correct.

**Step 7 secret-push behavior under this invocation.** With `GITHUB_REPOSITORY=cubrox/cubrox` set AND `WIF_PROVIDER_RESOURCE` populated (line 476 sets it because the WIF block executed), all three secrets (`GCP_PROJECT_ID`, `GCP_SERVICE_ACCOUNT`, `GCP_WORKLOAD_IDENTITY_PROVIDER`) get pushed via `gh secret set --repo cubrox/cubrox`. #237's step 6 (verify secrets) then becomes a no-op confirmation. Correct.

**One-shot paste correctness:** the block as written above pastes cleanly into a bash terminal (line continuations are proper `\`-then-newline, no trailing whitespace risk that I can spot in the plan's markdown rendering). After pasting, the operator must replace `<new-project-id>` with the actual project ID — this is clearly templated and standard.

**Conclusion:** the invocation as documented in v4.1's §6 callout is correct on every env-var name, every value, and every interaction with the script's internal logic. Paste-and-run will produce the intended provisioning state.

---

## Phase 2 step 16 WIF verification sanity check (synthetic-monitor.yml)

**Question:** is `synthetic-monitor.yml workflow_dispatch` actually a safe (read-only) WIF probe?

**Verified against `.github/workflows/synthetic-monitor.yml`:**

- **Triggers (lines 19-28):** both `schedule:` and `workflow_dispatch:` are declared. Commenting out `schedule:` (per Phase 1 step 13) does NOT disable `workflow_dispatch` — GitHub Actions treats trigger keys independently. Correctly handled in the plan.
- **WIF auth step (lines 75-80):** uses `google-github-actions/auth@v3` with `workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}` and `service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}` — line-for-line identical shape to `deploy.yml:60-65`. If WIF passes here, it passes for `deploy.yml`, `preview-deploy.yml`, and `rollback-production.yml` (which all use the same `google-github-actions/auth@v3` invocation).
- **Read-only operations:**
  - `gcloud run services describe ${SERVICE_NAME} --region=${GCP_REGION} --format='value(status.url)'` (line 104-106) — read-only.
  - `gcloud secrets versions access latest --secret=supabase-url|supabase-anon-key|supabase-service-key` (lines 118-123) — read-only.
- **Side effects in the post-auth steps:**
  - `scripts/smoke_auth.py` (line 142) — drives a sign-in/logout flow against the live service URL via the Supabase service-key (mints a throwaway session). NOT a traffic-shift, NOT a service mutation. Side effect: creates a temporary Supabase auth user on `gnswmcgaztcxslirulwm` (the existing Supabase project, unaffected by GCP pivot).
  - `actions/github-script@v7` (lines 148-204) — opens or comments on an alert issue ONLY on `failure()`. If the probe fails (e.g., because the hello-placeholder service can't actually sign anyone in — see NS-V41-1 below), this WILL create a `[ALERT] Synthetic auth monitor failed - 2026-06-30` issue in `cubrox/cubrox`. Benign, easy to close.

**Comparison vs. `rollback-production.yml`:** `rollback-production.yml` runs `gcloud run services update-traffic` (re-routing traffic) followed by a smoke test against the production URL with the resupplied revision. On a freshly-provisioned single-revision `masterkey` service that's an operational no-op, BUT it WOULD write a "Rollback complete" log entry, mutate the service's traffic spec (even if to the same revision), and is brittle to typo'd revision names. `synthetic-monitor.yml` has none of that.

**Conclusion:** `synthetic-monitor.yml workflow_dispatch` is the correct probe choice. The WIF auth step is the single test we care about — if it succeeds, the dual-write binding is plumbed correctly and the BC3 fix is validated.

---

## New blockers

**None.**

v4.1 made the three surgical edits I asked for and didn't introduce new operational risks. The plan is internally consistent, the #237 body callout is precise enough that the orchestrator can copy-paste it into the issue edit, and the risk register additions are honest about likelihood and impact.

---

## Non-blocking suggestions (v4.1-specific)

### NS-V41-1 — Phase 2 step 16 synthetic-monitor probe will likely fail at the smoke_auth step (not at WIF auth)

**Where:** §3 Phase 2 step 16 verification (line 401).

**Why this surfaces now:** at Phase 2 step 16 execution time, #237 has provisioned the placeholder Cloud Run service using `--image=us-docker.pkg.dev/cloudrun/container/hello` (per R22 / script line 800-825). That hello image responds to HTTP probes but does NOT run the FastAPI app, does NOT have `/auth/callback`, does NOT integrate with Supabase. `scripts/smoke_auth.py` (line 142 of synthetic-monitor.yml) will fail because the live URL isn't actually serving the application — it's serving "Hello World" from a placeholder.

**Net effect:** the overall workflow run will be RED, BUT the WIF auth step (lines 75-80) will have already turned green by that point. The BC3 verification mechanism still works — the operator just needs to read the run log for the "Authenticate to Google Cloud (Workload Identity Federation)" step specifically, not just look at the overall ✗.

**Mitigation:** add one line to Phase 2 step 16's verification text: "**Expected:** WIF auth step (line 75-80 of synthetic-monitor.yml) shows green; subsequent smoke_auth step likely RED because the masterkey service is still the hello placeholder at this phase. Read the per-step status, not just the overall workflow ✗. Close any auto-filed `[ALERT] Synthetic auth monitor failed` issue that gets opened — it's expected, not a real outage."

**Why non-blocking:** the operator gets the right signal (WIF works) from reading the per-step status. Misinterpretation produces only confusion, not damage. A doc clarification would help; a re-revision is not warranted.

### NS-V41-2 — DoD check 6's `gh variable list` won't show `vars` set on the renamed repo

**Where:** §6 callout DoD check 6 (line 906): `gh variable list --repo cubrox/cubrox | grep -E 'CLOUD_RUN_SERVICE|ARTIFACT_REPO'`.

**Observation:** at #237 execution time, the repo is still `cubrox/cubrox`, so the command works. But the Step 7 secret push in `provision-gcp-project.sh` does NOT actually push GitHub Actions `vars` — only `secrets` (per lines 880-893). `CLOUD_RUN_SERVICE` and `ARTIFACT_REPO` are GitHub Actions **VARIABLES**, not secrets, and the script does NOT call `gh variable set`. So this DoD check, as worded, will return empty even after a fully-successful #237 run.

**What the operator needs:** the operator (or #237's step 7) must `gh variable set CLOUD_RUN_SERVICE --body masterkey --repo cubrox/cubrox` and `gh variable set ARTIFACT_REPO --body masterkey --repo cubrox/cubrox` MANUALLY. These are not auto-pushed by the script.

**Mitigation:** edit DoD check 6 to explicitly say "after manually running `gh variable set CLOUD_RUN_SERVICE --body masterkey` and `gh variable set ARTIFACT_REPO --body masterkey`, this check confirms both vars are set." OR add a separate Step 7.5 to #237's body: "Manually push GitHub Actions vars: `gh variable set CLOUD_RUN_SERVICE --body masterkey && gh variable set ARTIFACT_REPO --body masterkey`."

**Why non-blocking:** today's repo (`gh variable list --repo cubrox/cubrox`) confirms neither variable is set today — so the operator will see they're missing post-#237 if they run the check, and remember to set them. Recovery is two `gh variable set` commands, trivially executable. Plan is correct in intent (the vars must be set); just unclear on the mechanism. Worth a small edit to either the DoD check or #237's body, but not block-worthy.

---

## What survives unchanged from v4 (DevOps-accepted in v4 sign-off — should not be re-litigated)

- Phase -1 (framework alignment) is DONE — closed via PR #232. (line 42)
- Phase 1 (codebase rename) shape unchanged. (line 43)
- Phase 4 collapse to 3 steps (merge → verify → restore monitor) preserved. (lines 463-469)
- Phase 5 ~50% elimination preserved. (lines 491-509)
- R19 (billing) and R20 (orphaned URL) framings preserved. (lines 706-729)
- Dependency graph (8-ticket critical chain) preserved. (line 979)
- v4 §6 reconciliation table preserved with only #200 + #237 row edits and a new callout subsection appended.

Nothing in v4.1 destabilizes anything I previously accepted.

---

## Sign-off statement

I sign off on `reports/refactor/01-architecture-plan.md` v4.1 as **ALIGNED**.

The three blockers from `reports/refactor/02c-devops-signoff-v4.md` (BC1, BC2, BC3) are fully resolved. R21-R25 are documented in the risk register with severity, likelihood, and workable mitigations. The #237 body-edit callout is precise and paste-correct against `scripts/provision-gcp-project.sh`'s actual env-var contract. The Phase 2 step 16 verification mechanism (`synthetic-monitor.yml workflow_dispatch`) is genuinely read-only at the WIF auth layer and is the right choice over `rollback-production.yml`.

Two non-blocking suggestions documented (NS-V41-1 and NS-V41-2) for the operator to be aware of when executing #237 and Phase 2. Neither warrants a re-revision.

**Cleared to proceed:** the orchestrator should edit #237's body per the v4.1 §6 callout, then fire #237. Phase 2 step 16's WIF dual-write and `synthetic-monitor.yml workflow_dispatch` verification follow as documented.

---

**Result:** v4.1 plan aligned; v4 blockers resolved; #237 can be re-bodied and fired.
Blocking concerns raised: 0
Non-blocking suggestions: 2 (NS-V41-1, NS-V41-2)
Risk register additions verified: 5 (R21-R25 — all present with workable mitigation)
#237 invocation paste-check: correct on all 6 env vars
Phase 2 step 16 verification mechanism: `synthetic-monitor.yml workflow_dispatch` confirmed read-only at WIF layer

SIGNOFF_SAVED: reports/refactor/02d-devops-signoff-v4.1.md
VERDICT: ALIGNED
ONE_LINE: v4.1 resolves BC1/BC2/BC3 cleanly; R21-R25 logged; #237 body delta is paste-correct against the script's env-var contract.
