# DevOps Sign-off: `cubrox` -> `masterkey` Rename Plan v4 (GCP pivot)

**Reviewer:** DevOps Engineer persona
**Date:** 2026-06-30
**Plan under review:** `reports/refactor/01-architecture-plan.md` (v4 — 2026-06-30)
**Prior sign-off:** `reports/refactor/02b-devops-signoff.md` (v3 / v2 — ALIGNED)
**Anchor for pivot:** Issue #237 (locked operator decisions)

---

## Verdict

**NEEDS_REVISION**

v4's overall direction is correct and the architectural simplification is sound. R19 (billing) and R20 (orphaned legacy URL) are characterized well. The Phase 4 collapse from 8 steps to 3 is genuinely safe — there is no "var-flip race" left to engineer around once #237 sets the vars at provisioning time.

However, three concrete gaps need fixing before #237 fires, all order-of-operations issues the operator can actually trip over:

1. **#237's body literally says "no dual-write needed" and lists #200 as superseded** (CLOSE), while v4 plan §6 keeps #200 as REWORK and the Phase 2 step 16 text reinstates the dual-write. The architect's intent and the operator's just-confirmed lock are aligned (dual-write IS happening), but #237's body is now stale and contradicts that. Whoever runs #237 will read its body, see "no dual-write needed," skip #200, and the next CI run after `gh repo rename` fails with `iam.serviceAccounts.getAccessToken denied` — exact same R3 failure mode as v3, just on the renamed repo path.
2. **`scripts/provision-gcp-project.sh` expects `GITHUB_OWNER` AND `GITHUB_REPO` as two separate env vars.** #237's happy-path step 4 writes `GITHUB_REPO=cubrox/cubrox`, which the script will treat as `WIF_REPO_NAME=cubrox/cubrox` (literally including the slash) AND `WIF_OWNER=` (empty, because `GITHUB_OWNER` is unset). With `WIF_OWNER` empty, line 478's `[skip] WIF setup not requested` fires and the entire WIF block is silently skipped. The deployer SA never gets bound to the GitHub repo principalSet. The first preview-deploy after #237 still gets `iam.serviceAccounts.getAccessToken denied`. This is a "you read the wrong env var name" footgun and it's in the locked ticket body, so the architect's plan inherits it.
3. **The v4 Phase 2 step 16 verification mechanism is the wrong workflow.** The plan suggests `workflow_dispatch` on `rollback-production.yml` with `revision=<currentRevision>` as the WIF auth probe. That workflow doesn't have a safe dry-run mode — it actually re-routes traffic to the supplied revision (lines 100-108), then smoke-tests it (lines 127-146). On a brand-new `masterkey` service that has exactly one revision, supplying that revision is a no-op but it's not zero-impact: the workflow will run `gcloud run services update-traffic` and the smoke test against the production URL. `synthetic-monitor.yml` is the cleaner probe (its `workflow_dispatch` only describes the service URL and runs the auth flow) but it's disabled per Phase 1 step 13 during the cutover window.

None of these break the v4 architecture. They break the executability of #237 and Phase 2 step 16 as currently written.

---

## What I re-verified

- `reports/refactor/01-architecture-plan.md` v4 changelog (lines 12-47) — read in full, including the seven "what survives" / "what's invalidated" bullets
- `01-architecture-plan.md` §3 Phase 0 (v4 STATUS: MOSTLY OBSOLETE, lines 330-344), Phase 2 step 16 (rewritten, lines 372-391), Phase 3 (replaced by verification checklist, lines 401-446), Phase 4 (collapsed, lines 447-477), Phase 5 (~50% eliminated, lines 479-508) — read end-to-end
- `01-architecture-plan.md` §4 risk register: R3 status downgrade (lines 540-553), R19 new (lines 694-703), R20 new (lines 705-717)
- `01-architecture-plan.md` §6 reconciliation table (lines 750-798) and §6.1 dependency graph (lines 810-871) — row-by-row
- Issue #237 body — read in full via `gh issue view 237`
- `scripts/provision-gcp-project.sh` lines 60 (default `ARTIFACT_REPO=agile-flow`), 351-368 (5 project-level IAM roles), 402-479 (WIF block — pool, provider, BOTH bindings via for-loop), 800 (`SERVICE_NAME` default `agile-flow-app`), 862-906 (Step 7 GitHub secret push), 1011 (next-steps echo)
- `.github/workflows/deploy.yml` lines 22-26 (env defaults), 60-71 (WIF auth), 131-225 (deploy step + env_vars + secrets)
- `.github/workflows/preview-deploy.yml` lines 24-28 (same env defaults pattern)
- `.github/workflows/rollback-production.yml` end-to-end — confirmed there's no auth-only mode
- `.github/workflows/synthetic-monitor.yml` lines 19-46 (workflow_dispatch present; would be a cleaner WIF probe)
- Repo state today: `gh variable list` confirms NO `vars.CLOUD_RUN_SERVICE` / `vars.ARTIFACT_REPO` set today; the defaults `agile-flow-app` / `agile-flow` are firing in all workflows. Confirms v4's premise that #237 must set these.

---

## Blocking concerns

### BC1 — #237's body and v4 §6 contradict each other on WIF dual-write

**Where:** #237's "Blocks / supersedes" list says `#200 (E3-T1 WIF dual-write) — superseded; this ticket creates the binding fresh, no dual-write needed`. v4 plan §6 row #200: `REWORK | What changes: now executed against the NEW GCP project (provisioned by #237) rather than the legacy project.` v4 Phase 2 step 16 (line 372): describes the dual-write in detail.

**Why it breaks things:** Whoever executes #237 reads the ticket body as the authoritative spec — they don't necessarily re-read the architecture plan. They will mark #200 as superseded and skip it. After #201 (repo rename) fires, the WIF binding still pins to `cubrox/cubrox` while GitHub's OIDC token presents `cubrox/masterkey`. Every workflow that authenticates to GCP starts failing with `iam.serviceAccounts.getAccessToken denied` — production deploys, preview deploys, synthetic monitor, rollback. Same R3 failure mode v3 was engineered to prevent; v4 reintroduces it by leaving #237's body unedited.

**Fix:** Edit #237's body. Strike "superseded" on #200; replace with: "**#200 remains REQUIRED:** dual-write a second WIF binding for `cubrox/masterkey` on the new project's deployer SA BEFORE running `gh repo rename`. Operator confirmed this approach 2026-06-30." Also strike the implication elsewhere in #237's body that the rename plan "Epics 3-5 collapse significantly" — that's still true for Phases 3/4/5, but Phase 2's WIF re-bind step is NOT collapsed.

### BC2 — #237 happy-path step 4 sets the wrong env-var name; WIF setup silently no-ops

**Where:** #237 step 4: `GCP_PROJECT_ID=<NEW> GITHUB_REPO=cubrox/cubrox bash scripts/provision-gcp-project.sh`. Script line 404: `WIF_OWNER="${GITHUB_OWNER:-${GITHUB_USERNAME:-}}"`. Script line 407: `if [[ -n "$WIF_OWNER" ]]; then` — guards the entire WIF block. Script line 478: `[skip] WIF setup not requested (GITHUB_OWNER and GITHUB_USERNAME unset)`.

**Why it breaks things:** `GITHUB_REPO=cubrox/cubrox` does not satisfy `WIF_OWNER`. `WIF_OWNER` reads only from `GITHUB_OWNER` or `GITHUB_USERNAME`. Without one of those set, the entire `if [[ -n "$WIF_OWNER" ]]` block (pool create, provider create, SA bindings) is skipped. The script completes "successfully," prints the next-steps block, but the WIF provider does not exist and the deployer SA has no GitHub principalSet binding. The next preview-deploy auth step fails with `Permission denied on resource (or it may not exist)` from the WIF provider lookup. Worse, the script then proceeds to Step 7 (line 862) and may try to push `GCP_WORKLOAD_IDENTITY_PROVIDER` to GitHub secrets — but `WIF_PROVIDER_RESOURCE` (set on line 476) is also unset, so the secret push (line 882: `if [[ -n "${WIF_PROVIDER_RESOURCE:-}" ]]`) is also skipped silently. The operator gets a "complete" provisioning with WIF broken end-to-end.

Additionally, the literal `GITHUB_REPO=cubrox/cubrox` would (if WIF_OWNER were also set correctly) produce a malformed `WIF_MEMBER` URI: `principalSet://.../attribute.repository/<owner>/cubrox/cubrox` — three path segments after `attribute.repository/` instead of two — which doesn't match what GitHub's OIDC token presents.

**Fix:** Edit #237 step 4 to `GCP_PROJECT_ID=<NEW> GITHUB_OWNER=cubrox GITHUB_REPO=cubrox bash scripts/provision-gcp-project.sh` (the repo NAME within the owner is just `cubrox`, since the GitHub slug is `cubrox/cubrox`). Also add to #237's Definition of Done a one-line post-provisioning check: `gcloud iam service-accounts get-iam-policy $SA_EMAIL --project=$NEW_GCP_PROJECT_ID --format=json | grep -c principalSet` MUST return ≥ 2 (one for each of the two WIF roles). If it returns 0, WIF wasn't set up; re-run with the correct env vars.

### BC3 — Phase 2 step 16's WIF verification workflow has side effects

**Where:** v4 plan line 389: `Verify: trigger workflow_dispatch on rollback-production.yml with revision=<currentRevision> and reason='WIF binding verification'. This auths to GCP but only acts on user-confirmed input — safe to dry-run.`

**Why it breaks things:** `rollback-production.yml` does NOT have a dry-run mode (verified by reading lines 100-146). On dispatch with a `revision=<currentRevision>` input, it will execute `gcloud run services update-traffic masterkey --to-revisions=<currentRevision>=100` — which, when the supplied revision is already at 100%, is operationally a no-op, BUT the workflow also runs a smoke test against the live production URL (lines 127-146) and writes a "Rollback complete" log entry. On a freshly-provisioned `masterkey` service with exactly one revision, this works without traffic disruption — but if there are multiple revisions or if the supplied revision-name is wrong (typo'd, copy-paste error), the workflow will actively reroute traffic to whatever was supplied. Calling this "safe to dry-run" is misleading.

A cleaner WIF probe is `synthetic-monitor.yml` (`workflow_dispatch` with optional `base_url` input) — but Phase 1 step 13 explicitly disables its `schedule:` block. The `workflow_dispatch` trigger should still work even with `schedule:` commented out, so this is actually a viable WIF probe — but the v4 plan doesn't mention it.

**Fix:** Replace the "use rollback-production.yml" instruction in Phase 2 step 16 with one of:
- **Option A (preferred):** Use `synthetic-monitor.yml workflow_dispatch` against the new service. It auths via WIF (lines 59-61 mirror deploy.yml), describes the service URL, and runs the smoke auth. Side-effect: it'll send a magic-link email to the smoke-test address — fine.
- **Option B:** Add a tiny ephemeral workflow (or a `workflow_dispatch` job in deploy.yml gated behind a `dry_run` input) that authenticates via WIF and does `gcloud auth print-access-token` then exits. Pure auth-only probe, zero side effects. This is the kind of fix #237 should ship as a follow-up.
- **Option C (acceptable):** Note in the plan that `rollback-production.yml` IS being used as the probe and explicitly acknowledge the side effect (a benign traffic-shift call against a single-revision service). Document the precondition: "only safe when `masterkey` has exactly one ready revision."

---

## Non-blocking suggestions

### NS1 — Update #237's Definition of Done with billing-budget verification

R19's mitigation says "#237's Definition of Done includes a billing-account verification step (confirm billing is enabled and a budget alert is set at ≥ $50/month threshold)." #237's actual DoD (read in full) doesn't include this. Either edit #237's DoD to add it, or accept that R19's mitigation is aspirational and the operator must remember to set the budget manually. Recommend the former.

### NS2 — §2.3 inventory table still has v3 language

Lines 138-147 of the plan describe Cloud Run / AR / WIF transitions as if executing in-place against an existing project ("Today: agile-flow-app"). v4 changes the meaning of "Today" — there is no `agile-flow-app` we can see in OUR project. The table is technically still descriptive of the inventory of identifiers but a reviewer reading top-to-bottom might miss that lines 138-150 describe the v3 framing. Add a v4 banner to §2.3 ("§2.3 below describes the resource-shape inventory; in v4 only resources in the new project exist; resources in the old project are inferred from this repo's history but cannot be touched") OR strike the "Today" column and replace with "Identifier."

### NS3 — Phase 5 step 1 (WIF binding cleanup) should explicitly verify before removing

The v4 Phase 5 step 1 `remove-iam-policy-binding` for the `cubrox/cubrox` principalSet. Before running it, confirm the `cubrox/masterkey` binding exists AND a recent successful workflow run used it. The `gcloud iam service-accounts get-iam-policy` output should show both bindings; the audit log should show a recent successful `getAccessToken` against the new principalSet. v3 Phase 5 step 38 had similar prudence; v4's compressed version drops the explicit "verify the new binding has been exercised first" guard. Add it.

### NS4 — §6 reconciliation row for #200 should explicitly cite the v4 dual-write requirement

Row #200 reads "REWORK | What changes: now executed against the NEW GCP project." This is correct but doesn't loudly counter #237's claim that #200 is superseded. Add: "**NOT superseded by #237** — #237 provisions ONE binding (`cubrox/cubrox`); #200 adds the SECOND binding (`cubrox/masterkey`) before the repo rename. Both are required."

### NS5 — Add a one-line "what to do if WIF check fails post-#237" to the runbook

The simplification of Phase 3 to "verification only" assumes #237 set everything up correctly. If WIF wasn't set up (BC2), Phase 3 step 6's dry-run preview-deploy will reveal the breakage. The plan should explicitly say: "if WIF verification fails post-#237, re-run `scripts/provision-gcp-project.sh` with `GITHUB_OWNER=cubrox GITHUB_REPO=cubrox` set; the script's idempotency lines (414, 427) skip the pool/provider but the SA binding loop on line 466 will add the missing principalSet bindings." This gives the operator a recovery path that doesn't require manual `gcloud iam` surgery.

---

## Additional risks beyond R19/R20

### R21 — `provision-gcp-project.sh` defaults `ARTIFACT_REPO=agile-flow` (line 60), not `masterkey`

If the operator runs #237's happy-path step 4 without explicitly setting `ARTIFACT_REPO=masterkey`, the script will create an Artifact Registry repo named `agile-flow` in the new project. Subsequent deploys (with `vars.ARTIFACT_REPO=masterkey` per #237 step 7) will then try to push to a `masterkey` repo that doesn't exist. The script's idempotency-via-`describe` (line 308) means a re-run with the corrected env var will create the second repo cleanly, but the operator now has TWO AR repos in the new project — one of which is dead weight. **Mitigation:** edit #237 step 4 to `GCP_PROJECT_ID=<NEW> ARTIFACT_REPO=masterkey GITHUB_OWNER=cubrox GITHUB_REPO=cubrox bash scripts/provision-gcp-project.sh`. Note: this overlaps with B4-listed ticket #196 (rename script defaults), but #196 lands in the Phase 1 PR AFTER #237 runs, so the rename doesn't help #237.

### R22 — `provision-gcp-project.sh:800` Step 5.8 creates a Cloud Run service with `--image=us-docker.pkg.dev/cloudrun/container/hello`

The placeholder revision uses the public hello image; first real deploy overwrites it. This is fine in steady state, but the placeholder is created with `--allow-unauthenticated` and `--port=8080` — no `--set-env-vars` for `DATABASE_URL` or `ANTHROPIC_API_KEY`. **R13 (env-var type stickiness) re-applies:** when `deploy.yml` first deploys, it does `--update-env-vars` (set/replace semantics, per the deploy.yml comment on lines 192-196). The hello placeholder has NO env vars set, so all of `deploy.yml`'s env vars are created fresh as literals — this is actually fine and matches `deploy.yml`'s intent. But if anyone manually `gcloud run deploy`s with `--set-secrets DATABASE_URL=...` between #237 finishing and the first `deploy.yml` run, they'd brick the service per R13. Phase 3 verification step 3 (line 409 in the plan) is the right place to catch this; recommend explicitly checking `gcloud run services describe masterkey --format='value(spec.template.spec.containers[0].env)'` returns empty (or contains only the literal vars from deploy.yml's first run) and NOT any `valueSource: secretKeyRef:` entries on DATABASE_URL / ANTHROPIC_API_KEY.

### R23 — Cloud Logging / Cloud Build / IAM credentials APIs may not all be auto-enabled

`provision-gcp-project.sh:297-304` enables six APIs: `run`, `artifactregistry`, `secretmanager`, `iam`, `iamcredentials`, `billingbudgets`. #237 step 3 enables a different five-API set: `run`, `artifactregistry`, `iamcredentials`, `cloudbuild`, `secretmanager`. Notably #237 lists `cloudbuild` (not in the script) and OMITS `iam` and `billingbudgets`. `deploy.yml` does NOT use Cloud Build (it does a local `docker build` then pushes); so `cloudbuild.googleapis.com` is unnecessary. `iam.googleapis.com` IS needed (for the `get-iam-policy` calls in the script) — but it's usually enabled by default on new projects. `billingbudgets.googleapis.com` is needed if R19's budget alert is set up. **Mitigation:** unify the API list in #237 step 3 with the script's enable call at line 297 (use the script's six-API list, plus add `logging.googleapis.com` if R20's enumeration work needs it later, which it probably doesn't since the new project starts empty).

### R24 — Supabase Auth allowlist may have org/project scoping affected by GCP project change

The Supabase Auth dashboard's redirect-URL allowlist is keyed against the Supabase project (`gnswmcgaztcxslirulwm`), not the GCP project. R4/R12 are still correctly characterized. However, the Supabase GitHub App's allowlist (R10) tracks the GitHub repo, and the per-PR branching plumbing reads from GitHub Actions secrets that include `SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_URL`. **R24 (low risk):** confirm that switching GCP projects doesn't affect Supabase's `webhook` callback URLs registered against the GitHub App — these point at supabase.com endpoints, not our Cloud Run service, so should be unaffected. Read-only verification only; no action.

### R25 — The legacy Cloud Run URL `agile-flow-app-heo5ry7rua-uc.a.run.app` may continue billing in the old project despite "inaccessible"

"Operator lost access" likely means lost IAM access to the project, not loss of the billing relationship. The orphaned runtime may continue accruing Cloud Run charges (min-instances=1 per deploy.yml:168) AND Cloud Logging charges (logs retention) AND Artifact Registry storage charges until the billing org owner manually shuts it down. **The cost is bounded but not zero.** Recommend the operator at least file a billing-org case to either (a) regain access enough to set `--min-instances=0` and stop logging ingestion, or (b) accept the cost until Google reclaims the project for non-payment of some other invoice. R19's mitigation focuses on the NEW project's billing; R25 highlights that the OLD project's billing is still happening and the operator may have legal/financial recourse to stop it that isn't IAM-access dependent.

---

## WIF dual-write specific check

**Operator's locked decision:** dual-write the new project's deployer SA with bindings for BOTH `cubrox/cubrox` AND `cubrox/masterkey` principalSets BEFORE the repo rename; prune the `cubrox/cubrox` binding in Phase 5.

**v4 plan ordering check (Phase 2 step 16 → step 17):**

- v4 Phase 2 step 16 (line 372): "WIF re-bind after repo rename (v4 REPLACES v3's dual-write). ... **Architect's chosen approach: dual-write the new binding BEFORE running the repo rename, then prune the old one in Phase 5** — same shape as v3's plan, just executed in the new project instead of the old one."
- v4 Phase 2 step 17 (line 392): "Repo rename: `gh repo rename masterkey --repo cubrox/cubrox` ..."

The plan text says "BEFORE the rename" in step 16. The numerical ordering 16-then-17 reinforces this. **Order is correct: the `cubrox/masterkey` binding lands before `gh repo rename` fires.**

**Mechanism check:** the v4 plan's bash snippet (lines 379-388) adds the new binding via two `gcloud iam service-accounts add-iam-policy-binding` calls (one per role) against the NEW project's deployer SA, with member `principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github/attribute.repository/cubrox/masterkey`. The old `cubrox/cubrox` binding stays untouched. This is correct shape and matches what `provision-gcp-project.sh:465-474` did originally for the `cubrox/cubrox` binding.

**Why this matters (R3 failure mode prevention):** with both bindings in place at the moment `gh repo rename` fires, GitHub's OIDC token presents `repository = cubrox/cubrox` for any in-flight workflow run AND `repository = cubrox/masterkey` for any newly-triggered run after the rename — both match a `principalSet` binding on the deployer SA. No `iam.serviceAccounts.getAccessToken denied`. After Phase 5's stability window, the `cubrox/cubrox` binding is pruned.

**Confirmed:** the v4 plan's order-of-operations puts the `cubrox/masterkey` binding in place before the rename. The mechanism matches the operator's locked decision exactly.

**Caveat:** this is contingent on #237 NOT being interpreted to mean "#200 superseded, skip it" (BC1). If #200 is skipped, the dual-write never happens, and the rename triggers R3. The architectural intent is right; the ticket-state hygiene needs the BC1 fix.

---

## `provision-gcp-project.sh` audit

#237's happy path assumes the script, run with `GCP_PROJECT_ID=<NEW> GITHUB_REPO=cubrox/cubrox`, does the following:
1. Enable APIs
2. Create AR repo named `masterkey`
3. Create deployer SA
4. Bind 4 project-level IAM roles
5. Create WIF pool + provider, bind 2 SA-level roles to the GitHub repo principalSet
6. Create Cloud Run service named `masterkey` with a placeholder image
7. Push GitHub Actions secrets (`GCP_PROJECT_ID`, `GCP_SERVICE_ACCOUNT`, `GCP_WORKLOAD_IDENTITY_PROVIDER`)

What the script ACTUALLY does on a fresh project with `GCP_PROJECT_ID=<NEW> GITHUB_REPO=cubrox/cubrox` (and nothing else set):

| # | Step | Status |
|---|------|--------|
| 1 | Enable 6 APIs (lines 296-304: `run`, `artifactregistry`, `secretmanager`, `iam`, `iamcredentials`, `billingbudgets`) | OK. Note #237 lists 5 different APIs — see R23. |
| 2 | Create AR repo (line 313) | **WRONG NAME** — defaults to `agile-flow` (line 60), not `masterkey`. Need `ARTIFACT_REPO=masterkey` env var. See R21. |
| 3 | Create deployer SA `deployer@<project>.iam.gserviceaccount.com` (line 331) | OK. |
| 4 | Bind 4 project-level IAM roles (lines 360-368: `run.admin`, `artifactregistry.writer`, `serviceAccountUser`, `secretmanager.secretAccessor`) | OK. |
| 5 | Create WIF pool + provider + bind 2 SA-level roles | **SILENTLY SKIPPED** — `WIF_OWNER` is empty because `GITHUB_OWNER` and `GITHUB_USERNAME` are unset (lines 404, 407). The entire block including the SA binding is skipped (line 478 prints `[skip] WIF setup not requested`). See BC2. |
| 6 | Create Cloud Run service (line 809) | **WRONG NAME** — defaults to `agile-flow-app` (line 800), not `masterkey`. Need `CLOUD_RUN_SERVICE=masterkey` env var. |
| 7 | Push GitHub Actions secrets (line 862-906) | **SILENTLY SKIPPED** — gated on `GITHUB_REPOSITORY` env var being set (line 862). #237 doesn't set this. Falls back to printing values. Even if `GITHUB_REPOSITORY` were set, `GCP_WORKLOAD_IDENTITY_PROVIDER` push (line 882) is gated on `WIF_PROVIDER_RESOURCE` being set, which it isn't from step 5. |

**Net effect of #237 as currently written:** a new GCP project with the wrong AR repo name (`agile-flow`), the wrong Cloud Run service name (`agile-flow-app`), no WIF, and no secrets auto-pushed. The operator would then manually create the `masterkey` AR repo, manually create the `masterkey` Cloud Run service, manually set up WIF, and manually push secrets — essentially re-doing 80% of the script's work by hand. The first `deploy.yml` run would still fail because WIF auth isn't plumbed.

**Idempotency check (fresh project tolerance):** the script IS designed to be idempotent. Each step's `describe`-then-create pattern (lines 207-235, 308-319, 325-349, 414-441) tolerates pre-existing state. Re-running with the correct env vars after a partial first run will create only the missing resources without errors. The retry helper (lines 86-142) absorbs eventual-consistency lag from fresh-project IAM propagation. So a recovery path exists: fix the env vars and re-run; the script picks up where the broken run left off.

**Conclusion:** `provision-gcp-project.sh` is well-built for the workflow #237 intends, but #237's invocation contract (env vars set) is mis-specified. The script will silently do the wrong thing because the env vars don't drive the code paths #237 assumes. Fix is environmental (BC2, R21), not in the script itself.

**Required env-var invocation for #237 to actually do what its happy-path says:**

```bash
GCP_PROJECT_ID=<NEW> \
ARTIFACT_REPO=masterkey \
CLOUD_RUN_SERVICE=masterkey \
GITHUB_OWNER=cubrox \
GITHUB_REPO=cubrox \
GITHUB_REPOSITORY=cubrox/cubrox \
bash scripts/provision-gcp-project.sh
```

(With `GITHUB_REPOSITORY=cubrox/cubrox` set, Step 7 will auto-push the secrets and #237 step 6 becomes a no-op verification.)

---

## Summary table

| # | Status | Item |
|---|--------|------|
| BC1 | BLOCKING | #237 body contradicts v4 §6 on WIF dual-write necessity; edit #237 to clarify #200 is still required |
| BC2 | BLOCKING | #237 step 4 env vars wrong; WIF silently no-ops; fix to `GITHUB_OWNER=cubrox GITHUB_REPO=cubrox` |
| BC3 | BLOCKING | Phase 2 step 16 verification via `rollback-production.yml` has side effects; use `synthetic-monitor.yml workflow_dispatch` or add an auth-only probe |
| NS1 | suggestion | Add billing-budget check to #237 DoD per R19 |
| NS2 | suggestion | §2.3 still has v3 framing; add v4 banner |
| NS3 | suggestion | Phase 5 WIF prune should verify new binding has been exercised first |
| NS4 | suggestion | §6 row #200 should loudly counter #237's "superseded" claim |
| NS5 | suggestion | Add WIF-recovery one-liner to Phase 3 |
| R21 | new risk | `ARTIFACT_REPO` defaults to `agile-flow`; #237 must set it |
| R22 | new risk | Placeholder Cloud Run service has no env vars; first `deploy.yml` populates them but watch for manual interference per R13 |
| R23 | new risk | API-enable list in #237 differs from script's; reconcile |
| R24 | new risk (low) | Supabase webhook URLs unaffected by GCP project change — read-only check only |
| R25 | new risk | Old GCP project may still be accruing charges despite IAM access loss; recommend billing-org escalation |

---

**Result:** Plan needs three blocker fixes before #237 fires; v4 architecture is otherwise sound.
Blocking concerns raised: 3 (BC1-BC3)
Non-blocking suggestions: 5 (NS1-NS5)
Additional risks identified: 5 (R21-R25)
WIF dual-write order: confirmed correct (binding lands before rename per Phase 2 step 16 → step 17)
`provision-gcp-project.sh` happy-path audit: script is sound; #237's env-var contract is wrong
