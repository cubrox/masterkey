# Platform Guide: GCP Cloud Run + Neon

This template is configured for **Google Cloud Platform**. The app deploys
to Cloud Run as a container, using Artifact Registry for image storage,
Secret Manager for runtime secrets, and Neon for Postgres with per-PR
branching.

If you need to adapt the template to a different platform, the upstream
`vibeacademy/agile-flow` repo supports Render, Vercel, Cloudflare, and
others. This fork is GCP-only by design.

---

## The Stack

| Layer | Service |
|-------|---------|
| Compute | Cloud Run |
| Image registry | Artifact Registry |
| Secrets | Secret Manager |
| Database | Neon (serverless Postgres, per-PR branching) |
| CI/CD | GitHub Actions |
| Auth (GCP side) | Workload Identity Federation (preferred) or service account key (fallback) |

See `docs/PATTERN-LIBRARY.md` for known pitfalls on this stack.

---

## First-Time Setup

Follow these steps in order. Most of them are one-time and can be
automated (see `scripts/provision-gcp-project.sh`).

### Step 1: Create a GCP Project

```bash
gcloud projects create YOUR_PROJECT_ID --name="Your Project Name"
gcloud config set project YOUR_PROJECT_ID
```

Link it to a billing account:

```bash
gcloud billing projects link YOUR_PROJECT_ID \
  --billing-account=YOUR_BILLING_ACCOUNT_ID
```

Without billing, most GCP APIs will return a 403 with no useful error.

### Step 2: Enable Required APIs

```bash
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  --project=YOUR_PROJECT_ID
```

API enablement is lazy — the first call to each service can take 30-60
seconds to warm up. If you see "API has not been used" errors immediately
after enabling, wait a minute and retry.

### Step 3: Create an Artifact Registry Repository

```bash
gcloud artifacts repositories create agile-flow \
  --repository-format=docker \
  --location=us-central1 \
  --project=YOUR_PROJECT_ID
```

Container images will live at:
`us-central1-docker.pkg.dev/YOUR_PROJECT_ID/agile-flow/agile-flow-app:TAG`

**Do not use `gcr.io` paths.** Container Registry is deprecated and new
projects cannot write to it.

### Step 4: Create a Deployer Service Account

```bash
gcloud iam service-accounts create deployer \
  --display-name="GitHub Actions deployer" \
  --project=YOUR_PROJECT_ID

# Grant permissions to deploy Cloud Run services
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/run.admin"

# Grant permission to push images to Artifact Registry
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

# Grant permission to impersonate the runtime service account
# (Cloud Run needs to run as some identity; default is the Compute SA)
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

# Grant access to read Secret Manager secrets at runtime
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

### How a participant fork "links" to a GCP project

There is no automatic link between a GitHub fork and a GCP project. The
"link" is just **four GitHub Actions secrets** that point the fork's
deploy workflow at the right project. When a participant pushes to
`main` on their fork, `deploy.yml` runs, reads these secrets, and uses
them to authenticate to GCP and deploy to that specific project.

| Secret | Example | Source |
|---|---|---|
| `GCP_PROJECT_ID` | `af-bob-2026-05` | provisioner output |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/123456789/locations/global/workloadIdentityPools/github/providers/github` | provisioner output (after Step 5 below) |
| `GCP_SERVICE_ACCOUNT` | `deployer@af-bob-2026-05.iam.gserviceaccount.com` | provisioner output |
| `NEON_API_KEY` | the workshop's shared Neon API key | facilitator |
| `NEON_PROJECT_ID` | the workshop's shared Neon project ID | facilitator |
| `NEON_PARENT_BRANCH` | the attendee's Neon branch name (e.g. `bob`) | provisioner output |

The first three plus `NEON_PARENT_BRANCH` are *per-participant*; the
two `NEON_*` values that aren't `NEON_PARENT_BRANCH` are shared across
the cohort. Without `NEON_PARENT_BRANCH`, per-PR previews would branch
from `main` (empty schema) instead of from the attendee's branch
(where their migrations live). The participant pastes them into their fork's
`Settings > Secrets and variables > Actions` panel, and that's the
entire handoff. No shared identity, no project metadata stored in
either system — just secret values.

**End-to-end for one participant (`bob`):**

1. Facilitator's roster has bob's row with `github_full_repo=acme/widget-shop` (or empty, defaulting to `bob-gh/agile-flow-gcp` for personal forks).
2. Facilitator runs `provision-workshop-roster.sh` → `af-bob-2026-05` exists with the deployer SA, and Step 5.5 binds the WIF trust to whatever GitHub repo bob's row specified.
3. Facilitator emails bob the four secret values. (Template in `agile-flow-meta/docs/workshops/gcp-facilitator-runbook.md` §7.)
4. Bob forks `vibeacademy/agile-flow-gcp` (to his account or his org), pastes the four secrets, pushes a trivial change to `main`. The deploy workflow uses WIF to assume the deployer SA and ships the container to bob's project.

**The most common participant footgun:** if the GitHub fork's owner/repo
doesn't match what the roster said, WIF auth fails because the trust
binding names a specific `<owner>/<repo>` exactly. Coordinate with
participants before provisioning: where will they fork (personal vs
org), and will they rename the repo? The `github_full_repo` column in
the roster captures the answer.

As of #5/#40, WIF setup is automatic per-project — the four secrets
above fall out of `provision-gcp-project.sh` Step 5.5 when
`GITHUB_OWNER` (or its legacy alias `GITHUB_USERNAME`) is set. The
workshop wrapper exports both `GITHUB_OWNER` and `GITHUB_REPO` per
CSV row. See Step 5 below for details.

---

### Step 5: Set Up Workload Identity Federation (Recommended)

Workload Identity Federation lets GitHub Actions authenticate to GCP
without storing a long-lived service account key. This is the best
practice and should be your default.

**As of `provision-gcp-project.sh` Step 5.5, this is automatic per
project.** Set `GITHUB_OWNER` and `GITHUB_REPO` and the script creates
the pool, the OIDC provider, and the IAM binding scoped to
`<owner>/<repo>`. `GITHUB_USERNAME` continues to work as a legacy alias
for `GITHUB_OWNER` so older callers don't need to change.

```bash
# Personal fork
GCP_PROJECT_ID=af-alice-2026-05 \
BILLING_ACCOUNT_ID=XXX-XXXX-XXXX \
GITHUB_OWNER=alice-gh \
GITHUB_REPO=agile-flow-gcp \
  ./scripts/provision-gcp-project.sh --create-project

# Org fork with renamed repo
GCP_PROJECT_ID=af-alice-2026-05 \
BILLING_ACCOUNT_ID=XXX-XXXX-XXXX \
GITHUB_OWNER=acme \
GITHUB_REPO=widget-shop \
  ./scripts/provision-gcp-project.sh --create-project
```

The script's "Next steps" output prints the exact `GCP_WORKLOAD_IDENTITY_PROVIDER`
and `GCP_SERVICE_ACCOUNT` values to paste into the participant's fork
secrets — no copying from this doc, no project-number arithmetic.

The workshop wrapper (`provision-workshop-roster.sh`) splits the
`github_full_repo` CSV column at the slash and exports `GITHUB_OWNER`
and `GITHUB_REPO` automatically, so a facilitator running the canonical
workshop flow never needs to think about WIF setup at all. The wrapper
also records the WIF provider resource string in `roster-output.csv`
per row.

> **The fork's owner/repo must match the roster.** The IAM binding is
> pinned to `<github_owner>/<github_repo>` exactly. If a participant's
> actual fork lives at a different path than the roster's
> `github_full_repo` says, WIF auth fails on first deploy. Confirm
> with each participant before provisioning: which GitHub
> account/org will they fork into, and what will the repo be named?

#### Manual fallback (rarely needed)

If you need to set WIF up by hand — for an out-of-band project, a
non-default repo name without using the `WIF_REPO` env override, or
debugging — the original sequence:

```bash
# Create the pool
gcloud iam workload-identity-pools create github \
  --location="global" \
  --display-name="GitHub Actions" \
  --project=YOUR_PROJECT_ID

# Create the provider (trusts GitHub's OIDC tokens)
gcloud iam workload-identity-pools providers create-oidc github \
  --workload-identity-pool=github \
  --location=global \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.actor=assertion.actor" \
  --attribute-condition="assertion.repository != ''" \
  --project=YOUR_PROJECT_ID

# Get the project number (different from project ID)
PROJECT_NUMBER=$(gcloud projects describe YOUR_PROJECT_ID --format='value(projectNumber)')

# Allow the GitHub repo to impersonate the deployer service account.
# Two roles are required: workloadIdentityUser to authenticate as the SA,
# and serviceAccountTokenCreator to mint access tokens (gcloud, docker push).
for role in roles/iam.workloadIdentityUser roles/iam.serviceAccountTokenCreator; do
  gcloud iam service-accounts add-iam-policy-binding \
    "deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
    --role="$role" \
    --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github/attribute.repository/GITHUB_USER/REPO_NAME" \
    --project=YOUR_PROJECT_ID
done
```

The WIF provider resource name to paste into GitHub secrets is:

```
projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github/providers/github
```

### Step 5 (Alternative): Service Account Key (Workshop Shortcut)

If WIF feels like too much setup for your timeline (e.g., for a workshop),
you can use a service account JSON key instead. This is **not recommended
for production** — the key is a long-lived credential that can be leaked.

```bash
gcloud iam service-accounts keys create deployer-key.json \
  --iam-account="deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --project=YOUR_PROJECT_ID
```

Paste the contents of `deployer-key.json` into the GitHub secret
`GCP_SA_KEY`. Delete the local file immediately after.

### Step 6: Create a Neon Account and Project

Sign up at <https://neon.tech>. On the free tier you get one project, 10
branches, 0.5 GB storage, and ~192 compute hours per month — enough for
development and small workshops.

Create a Neon project in the same region as your Cloud Run service (e.g.,
`us-central1` → `us-east-2` is the closest Neon region at the time of
writing; pick the Neon region closest to your Cloud Run region).

From the Neon Console, grab:

- **Project ID** — for the `NEON_PROJECT_ID` secret
- **API key** — Settings → API Keys → create one — for the `NEON_API_KEY` secret
- **Connection string (pooled)** — Dashboard → Connection Details → select
  "Pooled connection" — this is your `DATABASE_URL` for production

### Step 7: Create a Secret Manager Secret for the Database URL

**As of `provision-gcp-project.sh` Step 5.7, this is automatic per
project.** Set three env vars before running the provisioner:

```bash
NEON_API_KEY=neon_api_key_... \
NEON_PROJECT_ID=dawn-mountain-12345 \
NEON_BRANCH_NAME=alice \
GCP_PROJECT_ID=af-alice-2026-05 \
BILLING_ACCOUNT_ID=XXX-XXXX-XXXX \
  ./scripts/provision-gcp-project.sh --create-project
```

Step 5.7 will:

1. Create a Neon branch named `$NEON_BRANCH_NAME` (parented from the
   project's `main` branch). If the branch already exists, reuse it.
2. Fetch the branch's pooled connection URI via the Neon API.
3. Create the `database-url` Secret Manager secret with that URI as
   the value. If the secret already exists with a different value, add
   a new version.
4. Grant the deployer service account `roles/secretmanager.secretAccessor`
   on the secret.

The workshop wrapper (`provision-workshop-roster.sh`) reads
`neon_branch` from each `roster.csv` row (defaulting to the row's
`handle`) and exports `NEON_BRANCH_NAME` automatically. Facilitators
running the canonical workshop flow don't need to manage this secret
per project.

#### Manual fallback (rarely needed)

If you're running the inner script standalone or the env vars aren't
set, the script's "Next steps" footer prints the manual command:

```bash
echo -n "postgresql://user:pass@pooled-host/db" | \
  gcloud secrets create database-url \
    --data-file=- \
    --project=YOUR_PROJECT_ID
```

Use the **pooled** Neon connection string (the host should contain
`-pooler.`). Cloud Run exhausts direct connections fast because every
revision instance opens its own pool. See pattern #9 in
`docs/PATTERN-LIBRARY.md`.

### Step 8: Configure GitHub Secrets and Variables

In your GitHub repo settings (Settings → Secrets and variables → Actions):

**Secrets (encrypted, not visible after save):**

| Name | Value |
|------|-------|
| `GCP_PROJECT_ID` | `YOUR_PROJECT_ID` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | The full WIF provider path from Step 5 |
| `GCP_SERVICE_ACCOUNT` | `deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com` |
| `GCP_SA_KEY` | (Only if not using WIF — contents of `deployer-key.json`) |
| `NEON_API_KEY` | From Neon Console |
| `NEON_PROJECT_ID` | From Neon Console |
| `NEON_PARENT_BRANCH` | (Optional) Neon branch name for per-PR previews to inherit from. Defaults to `main` when unset. Workshop forks set this to the attendee's branch (e.g. `alice`). |

**Variables (plain text, visible):**

| Name | Default | Purpose |
|------|---------|---------|
| `GCP_REGION` | `us-central1` | Cloud Run + Artifact Registry region |
| `ARTIFACT_REPO` | `agile-flow` | Artifact Registry repo name |
| `CLOUD_RUN_SERVICE` | `agile-flow-app` | Cloud Run service name |
| `APP_URL` | (your production URL) | Passed to the container at runtime for self-referential URL construction |
| `NEON_DB_USER` | `neondb_owner` | Neon database role |

### Step 9: First Deploy

Push to `main` (or trigger the `Deploy to Production` workflow manually
via `gh workflow run deploy.yml`). Watch the workflow logs. First deploys
often reveal missing IAM grants — fix and retry.

If the workflow succeeds but the container fails its health check with
"starting but not ready," the most likely cause is a missing
`--host 0.0.0.0` on the uvicorn command in the Dockerfile. See pattern #1 in `docs/PATTERN-LIBRARY.md`.

---

## Account Model

This template supports two modes for the GitHub identities that
operate the agentic workflow. **Solo mode is the default** for new
forks; multi-bot mode is the production opt-in.

### Solo mode (default)

One personal GitHub account plays all roles — worker (creates PRs),
reviewer (posts review comments), human merger. Recommended for:

- Workshops and tutorials (one attendee, one fork, one identity)
- Individual learners and framework evaluators
- Anyone whose org doesn't have provisioned bot accounts

**Bootstrap:**

```bash
bash scripts/setup-solo-mode.sh
```

The script persists `AGILE_FLOW_SOLO_MODE=true` to your shell rc,
audits stale `GITHUB_PERSONAL_ACCESS_TOKEN*` env vars (which
silently override `gh auth switch`), verifies your gh token has
`repo + project + workflow + read:project` scopes, activates the
pre-push hook (`core.hooksPath`), and verifies you have admin
access on the fork. See `docs/GETTING-STARTED.md` Path B for the
walkthrough.

In Codespaces, `AGILE_FLOW_SOLO_MODE=true` is set automatically via
`.devcontainer/devcontainer.json`'s `containerEnv` and the bootstrap
script runs as `postCreateCommand`. Codespaces is the recommended
setup path for first-time users; see GETTING-STARTED Path A.

**Agent identity:** the worker and reviewer agents read
`gh auth status` to verify the active account before any GitHub
mutation. Neither agent runs `gh auth switch` (that mutates global
gh state across the user's terminals; #82). The hook
(`.claude/hooks/ensure-github-account.sh`) short-circuits on
`AGILE_FLOW_SOLO_MODE=true` and no longer tries to switch accounts.

### Multi-bot mode (production)

Separate worker + reviewer bot accounts plus a human merger.
Provides separation of duties and an audit trail (worker bot's
identity on every PR creation; reviewer bot's identity on every
review). Appropriate for:

- Production teams with provisioned bot accounts
- Organizations that need a clear paper trail on automated activity
- Setups where the framework is operated by multiple humans who want
  to distinguish their actions from agent actions

**Bootstrap:**

```bash
bash scripts/setup-accounts.sh
```

Activated by setting `AGILE_FLOW_WORKER_ACCOUNT` (default:
`va-worker`) and `AGILE_FLOW_REVIEWER_ACCOUNT` (default:
`va-reviewer`) env vars. The hook auto-switches to the right
account before `gh pr create` and `gh pr review`. Other gh
operations (issue create, label create, branch protection) require
the agent to verify the active account and STOP if wrong — never
switch from agent context (#82).

### Choosing between them

Choose based on use case, not phase. Workshop attendees stay in solo
mode for the entire workshop. Production teams adopt multi-bot once
they have provisioned bot accounts AND a documented PAT-rotation
schedule — both are real operational costs that solo mode avoids.

The two modes coexist in the framework: **the same agents, hooks,
and scripts work for both.** Switching modes is an env-var change
and a re-run of the appropriate bootstrap script; no code is
duplicated for solo vs multi-bot.

**Trade-off:** solo mode loses the audit-trail benefit of
bot-account separation — every PR and review is attributed to the
single personal account. For learning environments and small teams,
this is fine. For production at scale, multi-bot's clarity is
worth the setup cost.

---

## Workshop: Lifecycle (Setup and Teardown)

When running a workshop, the facilitator's mental model is two commands:

```bash
# Bring up the classroom
BILLING_ACCOUNT_ID=XXXXXX-XXXXXX-XXXXXX \
  ./scripts/workshop-setup.sh roster.csv

# Tear it down at T+1 day
./scripts/workshop-teardown.sh roster.csv          # interactive prompt
./scripts/workshop-teardown.sh roster.csv --yes    # non-interactive
```

The setup script runs four pre-flight checks (gcloud auth, billing
account is OPEN, roster file exists with the expected header, roster
has data rows) and then hands off to the underlying provisioning logic.
Pre-flight failures exit 2 with actionable messages — far better than
discovering a missing auth token mid-loop.

### Roster format

`roster.csv` accepts three header shapes. The first four columns are
required; the 5th and 6th are optional automation columns.

**Minimal (4 columns):**

```csv
handle,github_user,email,cohort
alice,alice-gh,alice@example.com,2026-05
bob,bob-gh,bob@example.com,2026-05
```

**With Neon branch override (5 columns):**

```csv
handle,github_user,email,cohort,neon_branch
alice,alice-gh,alice@example.com,2026-05,
bob,bob-gh,bob@example.com,2026-05,bob_personal
```

**With Neon + GitHub repo override (6 columns):**

```csv
handle,github_user,email,cohort,neon_branch,github_full_repo
alice,alice-gh,alice@acme.com,2026-05,alice,acme/agile-flow-alice
bob,bob-gh,bob@acme.com,2026-05,bob,acme/widget-shop
carol,carol-gh,carol@example.com,2026-05,carol,
```

Columns:

- `handle` — short, lowercase, stable identifier; appears in the GCP project ID
- `github_user` — the participant's GitHub username; used as the default
  GitHub owner for the WIF binding when `github_full_repo` is empty
- `email` — Google identity granted `roles/editor` on the new project
- `cohort` — `YYYY-MM` of the workshop date; appears in the GCP project ID
- `neon_branch` *(optional)* — Neon branch name for this attendee. When
  empty or absent, defaults to `handle`. Use the override when the same
  person needs a stable branch across cohorts (different `cohort`, same
  `neon_branch`). Must be 1-63 chars, alphanumeric + hyphen + underscore.
- `github_full_repo` *(optional, 6-column shape only)* — `<owner>/<repo>`
  identifying the participant's fork. Use the override when attendees
  fork into their organization's GitHub (e.g., `acme/widget-shop`) and
  rename the repo to fit their product. When empty or absent, defaults
  to `<github_user>/agile-flow-gcp` (the personal-fork pattern).
  Validation: `^[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$`.

Project IDs follow the pattern `af-{handle}-{cohort}`. This shape is
referenced from the facilitator runbook, the participant day-1 doc, and
the dry-run checklist — do not change it. A working example lives at
`scripts/roster.example.csv` (uses the 6-column shape with two org-fork
rows and one personal-fork default).

### Setup behavior

`workshop-setup.sh` is a thin wrapper: after pre-flight passes, it
delegates to `scripts/provision-workshop-roster.sh`. That script:

1. Computes each project ID and checks whether it already exists
2. Calls `provision-gcp-project.sh --create-project` (idempotent)
3. Grants `roles/editor` on the new project to the participant's email
4. Appends a row to `roster-output.csv` with status + project ID

### Idempotency and fail-fast

Re-running setup with the same roster is safe — already-existing
projects are recorded as `skipped` instead of `created`. The wrapper is
fail-fast: if any row fails, the loop stops and exits non-zero. This is
intentional — a half-provisioned classroom is harder to recover from
than a clean stop. Inspect `roster-output.csv`, fix the cause, and
re-run; successful rows are skipped.

### Teardown behavior

`workshop-teardown.sh` reads the same roster, derives the project IDs
(only IDs matching `af-{handle}-{cohort}` from the CSV are touched —
this is a guard against malformed rosters taking down unrelated
projects), and runs `gcloud projects delete` per row.

By default the script prints the list and prompts for confirmation
(`[y/N]`). Pass `--yes` to skip the prompt for non-interactive use.
Idempotent: re-running on already-deleted projects logs `[skip]` rows
and exits 0.

After deletion, `roster-output.csv` is removed (it's stale once
projects are gone). `roster.csv` (input) is preserved.

> **GCP holds project IDs for ~30 days after deletion.** Re-creating
> with the *exact* same project ID during that window will fail with
> `PROJECT_ID_NOT_AVAILABLE`. If you need to reprovision quickly, change
> the `cohort` column in the roster (e.g. `2026-05` → `2026-05a`) so
> new project IDs are generated.

### Budget guardrails

Set `BUDGET_CAP_USD` before running setup to attach a per-project billing
budget to every attendee project. The provisioner's Step 5.6 creates a
budget on the billing account, scoped to the single project via
`--filter-projects=projects/<project_number>`, with thresholds at 50%,
90%, and 100% of current spend plus 100% of forecasted spend.

```bash
BILLING_ACCOUNT_ID=XXXXXX-XXXXXX-XXXXXX \
  BUDGET_CAP_USD=25 \
  ./scripts/workshop-setup.sh roster.csv
```

Notification routing uses the billing account's default IAM recipients —
anyone with `roles/billing.admin` or `roles/billing.user` on the account
gets email at each threshold. No separate Cloud Monitoring notification
channel needed. The facilitator already has Billing Admin to run the
script, so emails route to them automatically.

To create budgets, the facilitator (script runner) needs
`roles/billing.costsManager` on the billing account. This is in addition
to the `roles/billing.user` already required for `gcloud billing
projects link` in Step 1.

The step is idempotent: budgets are looked up by display-name
`af-workshop-cap-<project_id>` before creation, so re-running the
provisioner is a no-op for projects that already have a cap.

When `BUDGET_CAP_USD` is unset (the non-workshop default), Step 5.6 is
skipped silently — `provision-gcp-project.sh` for production deploys
doesn't need a workshop-style cap.

> **This step provides alerts only.** Auto-cutoff (disabling billing on
> threshold breach) is tracked separately at
> [#42](https://github.com/vibeacademy/agile-flow-gcp/issues/42) and is
> intentionally out of scope here. For the May 2026 workshop's blast
> radius (≤8 projects × $25 = ~$200 worst case), facilitator monitoring
> is sufficient.

### Codespace cost estimate

Workshop attendees who use the recommended GitHub Codespace path (see
`README.md` and `docs/GETTING-STARTED.md`) accumulate per-attendee
compute charges separate from the GCP budget above. The
`.devcontainer/devcontainer.json` defaults to the cheapest machine
type (`hostRequirements: cpus: 2, memory: 4gb`) to keep the per-cohort
cost predictable.

Reference numbers (subject to change at GitHub's pricing page —
verify before each cohort):

| Variable | Value (2026-04) |
|---|---|
| 2-core machine rate | ~$0.18/hour |
| Free tier (per personal account) | 120 core-hours/month |
| Cohort size | 8 attendees |
| Workshop duration | 2 days × 4 active hours/day |

For a typical 8-attendee, 2-day workshop with 4 active Codespace hours
per attendee per day, total compute ≈ 8 × 2 × 4 × 2 cores ≈ 128
core-hours, mostly within the per-attendee free tier. Even with all
attendees billing past free tier, worst-case compute is ~$15-25 per
cohort.

Codespaces hibernate after 30 minutes of inactivity by default, so
overnight or long-break costs are zero. To keep a Codespace running
across a longer timeline, see GitHub's "Codespaces lifecycle" docs
for the `keepalive` option.

> **Closed-network attendees.** If your cohort includes participants
> behind corporate firewalls that block `*.github.dev` or VS Code
> Server, those attendees use the local-clone fallback path in
> `docs/GETTING-STARTED.md` Path B. The framework supports both;
> Codespaces is the recommended path, not the only path.

### Auto-pushed GitHub secrets (Step 7)

When `GITHUB_REPOSITORY=<owner>/<repo>` is set and `gh` is on PATH and
authenticated, the provisioner pushes the per-attendee secrets directly
into the participant's fork after provisioning completes:

- `GCP_PROJECT_ID`
- `GCP_SERVICE_ACCOUNT`
- `GCP_WORKLOAD_IDENTITY_PROVIDER` (when WIF was set up in Step 5.5)
- `NEON_PARENT_BRANCH` (when Neon was provisioned in Step 5.7)
- `PRODUCTION_DATABASE_URL` (when Neon was provisioned in Step 5.7) — same
  pooled URI written to the `database-url` Secret Manager secret. Required
  by `deploy.yml` for the Alembic migration step and the Cloud Run runtime
  env var. Without it, production starts with `DATABASE_URL=""` and 500s on
  the first DB query.

This eliminates the most common day-1 failure: facilitators copy SA
emails or WIF provider paths between projects by hand and get them
wrong, surfacing later as opaque `iam.serviceAccountTokenCreator` 404s
or WIF `invalid_target` errors.

The wrapper (`provision-workshop-roster.sh`) automatically forwards each
roster row's `github_full_repo` value as `GITHUB_REPOSITORY`, so for
workshop runs no extra setup is needed.

`GCP_SA_KEY` is intentionally NOT auto-pushed (long-lived credential —
upload deliberately if you used `--with-sa-key`). The cohort-shared
`NEON_API_KEY` and `NEON_PROJECT_ID` are also not auto-pushed; the
facilitator sets those once via a separate `gh secret set` call.

When `GITHUB_REPOSITORY` is unset or `gh` is missing, the script falls
back to printing the values for manual entry (existing behavior).

### Cloud Run service pre-create (Step 5.8)

`preview-deploy.yml` calls `gcloud run deploy --no-traffic --tag=pr-N`
to create per-PR preview revisions. That works after a project's first
deploy, but on a brand-new project gcloud rejects the very first PR
with:

```
ERROR: (gcloud.run.deploy) --no-traffic not supported when creating
a new service.
```

To prevent this, the provisioner pre-creates the Cloud Run service with
a placeholder image (Google's `us-docker.pkg.dev/cloudrun/container/hello`)
during Step 5.8. The first real preview-deploy overwrites the
placeholder revision with the participant's container.

The step is idempotent — if the service already exists (re-runs, or
because `deploy.yml` already shipped from the participant's fork), it
logs `[skip]` and continues. The placeholder revision pins
`--service-account` to the deployer SA and `--allow-unauthenticated` so
the first real deploy doesn't change either property.

Override the service name with `CLOUD_RUN_SERVICE=<name>`; defaults to
`agile-flow-app`.

### What the lifecycle scripts do NOT do

- Workload Identity Federation setup — currently manual per project
  (see "Step 5: Workload Identity Federation" above), or track ticket
  [#5](https://github.com/vibeacademy/agile-flow-gcp/issues/5).
- Budget auto-cutoff (Cloud Function disabling billing on threshold
  breach) — see [#42](https://github.com/vibeacademy/agile-flow-gcp/issues/42).
  Email alerts at 50/90/100% are wired up via Step 5.6 above.
- Org-policy override for `iam.allowedPolicyMemberDomains` — currently
  manual per project (see [`PATTERN-LIBRARY.md` pattern #30](./PATTERN-LIBRARY.md)),
  or track ticket [#19](https://github.com/vibeacademy/agile-flow-gcp/issues/19).
- Notification emails to participants — facilitator runbook in
  `agile-flow-meta` documents the email template.

### Output and gitignore

`roster.csv` (input) and `roster-output.csv` (output) are both
gitignored. They contain participant emails — never commit either.

---

## Neon Branch Model

Neon branches are how the framework gives each attendee an isolated
database without provisioning a separate Neon project per person. This
section documents the framework's branch types, the workshop
multi-tenancy model, and the collision behavior — read it once before
running a cohort, especially if you're reusing a Neon project across
cohorts.

### Branch namespace

Neon branches are unique within a project. Across projects, names can
repeat freely. The framework uses one Neon project per cohort by
default.

### Branch types

The framework creates and consumes three categories of Neon branch:

| Type | Owner | Lifetime | Created by |
|---|---|---|---|
| `main` | Project default | Permanent | Neon (at project creation) |
| `<roster-handle>` | One per roster row | Long-lived | `provision-gcp-project.sh` Step 5.7 |
| `pr-{N}` | One per open PR | Short-lived | `preview-deploy.yml` |

- **`main`** — the project's default branch. The production app's
  pooled connection points here. **Must be named `main` literally.**
  `preview-deploy.yml:80` falls back to the literal string `'main'`
  when `NEON_PARENT_BRANCH` is unset; if your Neon project's default
  branch is named differently (`production`, etc.), set
  `NEON_PARENT_BRANCH` explicitly per fork or expect the parent
  fallback to silently fail.
- **`<roster-handle>`** — long-lived seed branches, one per roster row.
  Branch name defaults to the CSV's `handle` column. Created once
  during onboarding by Step 5.7 of `provision-gcp-project.sh`. Never
  auto-deleted — these survive across cohorts unless a facilitator
  manually removes them.
- **`pr-{N}`** — short-lived. Auto-created by `preview-deploy.yml`
  on PR open, auto-deleted by `preview-cleanup.yml` on PR close. PR
  numbers are unique-per-repo, so cross-fork preview branches do
  not collide.

### What `NEON_PARENT_BRANCH` does

Determines what schema and seed data each PR's preview branch
inherits. The default `main` means "inherit from production schema,
no seed data." Setting it to an attendee's roster handle means
"inherit from my seeded dev data." `provision-gcp-project.sh` Step 7
auto-pushes this as a GitHub Actions secret on the attendee's fork.

### Workshop multi-tenancy model

Facilitators typically provision **one** shared Neon project per
cohort (cost-efficient). Three implications:

1. **All attendees see each other's branches in the Neon console.**
   This is normal; not a privacy issue (branch names are roster
   handles, not anything sensitive).
2. **Branch deletion is project-wide.** If `preview-cleanup.yml`
   deletes `pr-3`, it's gone for the entire project, not just the
   triggering fork. PR-number uniqueness across forks prevents this
   from causing real harm in normal use, but be aware.
3. **What you should expect to see in the console.** Given a roster
   of N attendees, expect: 1× `main` (the default), N× `<handle>`
   (one per row), 0+× `pr-{N}` (one per open PR across all forks).
   Anything else is checkable against `roster.csv` — if a console
   branch isn't in the roster, it's a leftover.

### Collision behavior (since #90)

Two roster rows with the same handle, OR a single row whose handle
matches a branch left over from a prior cohort, results in the
provisioner **failing fast** with an actionable message:

```text
ERROR: Neon branch 'alice' already exists in project 'dark-grass-...'.
  This may mean: another roster row already used this handle,
  OR a prior cohort left a branch with this name.
  Choose a different handle, OR set NEON_FORCE_SHARED_PARENT=true
  if you intentionally want to share the parent branch (paired
  collaboration, or re-running the same cohort).
```

To intentionally share a parent (paired collaboration, or
re-running an existing cohort against the still-populated Neon
project), set `NEON_FORCE_SHARED_PARENT=true` in the environment
when running the provisioner. The wrapper accepts
`--force-shared-parent` and propagates it.

```bash
# Default: fail fast on existing branch
bash scripts/provision-workshop-roster.sh roster.csv

# Intentional shared parent
bash scripts/provision-workshop-roster.sh roster.csv --force-shared-parent
```

The previous behavior (silent reuse on 409) is preserved when the
flag is set, so existing automation with intentional collisions
keeps working — just turn the flag on explicitly.

---

## Daily Operations

### Project board hygiene: enable auto-move-to-Done

If your project board's tickets stay stuck in **In Review** after
their PRs merge, the project's built-in **"Item closed → Status:
Done"** workflow isn't enabled.

The framework's `/bootstrap-workflow` instructs facilitators to
enable this once at project creation (Step 1.5). For existing
projects (cohorts already past bootstrap), enable it manually
via the GitHub Projects UI:

1. Open the project: `https://github.com/orgs/<org>/projects/<N>`
2. Click **⋯** (top-right) → **Workflows**
3. Find **"Item closed"**
4. Set **When** = `Issue is closed`, **Set Status** = `Done`
5. Toggle **Enabled** → **Save and turn on workflow**

Once enabled, the flow becomes: human merges PR → GitHub
auto-closes the linked issue (because the PR body has
`Closes #N`) → built-in workflow bumps the project board's
Status column to Done. **No agent ever moves tickets to Done** —
the framework's "only humans move to Done" rule is preserved
because the human's act of merging triggers the chain.

There is no GraphQL mutation to flip this workflow's `enabled`
state — `projectV2.workflows` is queryable and
`deleteProjectV2Workflow` exists, but no
`createProjectV2Workflow` or `updateProjectV2Workflow` exists in
the public API. The web UI is the only configuration path. See
issue #86 for the API research.

### Viewing Logs

```bash
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="agile-flow-app"' \
  --project=YOUR_PROJECT_ID \
  --limit=50 \
  --format='value(timestamp,textPayload)'
```

### Troubleshooting Cloud Run

When something feels wrong (a deploy looks successful but the app
returns 500s, traffic seems to be on the wrong revision, the
placeholder `hello` image is still serving), use the one-shot
diagnostic instead of composing gcloud queries by hand:

```bash
./scripts/diagnose-cloudrun.sh --project=YOUR_PROJECT_ID
```

The script is read-only and prints five sections in one go: service
summary (URL, latest-ready vs latest-created revision), traffic split
with stale-revision markers, currently-serving image with placeholder
detection, latest revision conditions (Ready / Active /
ContainerHealthy), and the last 50 log lines. Paste the full output
into a help channel and someone else can diagnose without a
back-and-forth.

The script never mutates state — no traffic updates, no deploys, no
deletes. For remediation see `Rolling Back` below or
`docs/PATTERN-LIBRARY.md`.

### Rolling Back

Cloud Run keeps every revision. To roll back:

```bash
# List recent revisions
gcloud run revisions list \
  --service=agile-flow-app \
  --region=us-central1 \
  --limit=10

# Route 100% of traffic to a specific revision
gcloud run services update-traffic agile-flow-app \
  --region=us-central1 \
  --to-revisions=agile-flow-app-00042-xyz=100
```

### Updating Runtime Secrets

Runtime secrets are mounted from Secret Manager at deploy time. To rotate:

```bash
# Add a new secret version
echo -n "new-value" | gcloud secrets versions add database-url --data-file=-

# Redeploy to pick up the new version
# (The :latest reference resolves at deploy time, not runtime.)
gh workflow run deploy.yml
```

If you need true live rotation without a redeploy, mount the secret as a
file instead of an env var. See `docs/PATTERN-LIBRARY.md`.

### Monitoring Cost

Cloud Run billing is per-request with a generous free tier (2M
requests/month, 360k GB-seconds, 180k vCPU-seconds). For a low-traffic
app, monthly cost is typically under $5.

Set a budget alert in Cloud Console → Billing → Budgets. Alert at 50%
and 90% of your chosen cap.

---

## Switching Away From GCP

This fork is GCP-specific. If you want to target another platform, fork
the upstream `vibeacademy/agile-flow` repo instead — it ships with
Render as the default and documents alternatives for Vercel, Cloudflare,
Railway, and Fly.io.

Do not try to run this template on another platform without removing the
GCP-specific workflows and Dockerfile settings. The `--host 0.0.0.0`
binding is correct for Cloud Run but may need
adjustment on other targets.
