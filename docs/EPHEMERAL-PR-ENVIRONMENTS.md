# Ephemeral PR Environments: Cloud Run + Neon

Every pull request in this template gets its own live environment:

- A **Cloud Run revision** tagged with the PR number, reachable at a stable URL
- A **Neon database branch** forked from `main`, with its own connection string
- **Zero production traffic** (the preview revision has `--no-traffic`)
- **Automatic teardown** when the PR closes

This document explains how it works, how to debug it, and how it differs
from the upstream Agile Flow template's Render + Supabase approach.

---

## Architecture

```
PR opened/updated
      |
      v
preview-deploy.yml
      |
      +-- Create Neon branch: pr-{N}
      |       (copy-on-write from main, ~1 sec)
      |
      +-- Run Alembic migrations against the Neon branch database
      |       uv run alembic upgrade head
      |
      +-- Build container image (no build args needed; FastAPI reads env
      |   at runtime)
      |       docker build -t IMAGE .
      |
      +-- Push to Artifact Registry
      |       us-central1-docker.pkg.dev/PROJECT/REPO/app:pr-N-sha
      |
      +-- gcloud run deploy --tag=pr-N --no-traffic
      |       Creates a tagged revision that receives ZERO production traffic
      |       but is reachable at https://pr-N---app-hash.region.run.app
      |
      +-- Override DATABASE_URL with the Neon branch pooled URL
      |       (revision-scoped, doesn't affect production revision)
      |
      +-- Smoke test /api/health
      |
      +-- Post PR comment with preview URL


PR closed/merged
      |
      v
preview-cleanup.yml
      |
      +-- Delete Neon branch pr-{N}
      |       (storage released, no more compute cost)
      |
      +-- Remove Cloud Run revision tag pr-{N}
      |       (revision stays in history, costs nothing on scale-to-zero)
```

---

## Why Revision Tagging, Not Per-PR Services?

A naive approach would create a new Cloud Run service per PR (`app-pr-42`).
This has problems:

- Cloud Run's quota is 1000 services per region. A busy project can hit this.
- Each service needs its own IAM setup, secret mounts, and custom domain config.
- Cleanup requires deleting services, which is slow and lossy (log history is discarded).
- Secret rotation has to happen across every preview service.

**Revision tagging** solves all of these:

- One service, many revisions. All PRs share the service's IAM and secret setup.
- Tags are lightweight — create and delete instantly via `gcloud run services update-traffic`.
- Inactive revisions cost nothing on scale-to-zero, so leaving them around is free.
- Revision history is the audit trail. No data loss when a "preview" is cleaned up.

The tradeoff: revision tagging means all PR previews share the service's
**base configuration** (CPU, memory, scaling limits). You can't give one
PR more memory than another. For this template's use case (FastAPI web
apps that all look similar), this is fine.

---

## Why Neon, Not Cloud SQL?

Cloud SQL does not support fast database branching. Creating a Cloud SQL
clone takes 5-10 minutes per branch and the clone is a separate instance
with its own billing. This is incompatible with "one database per PR."

**Neon** offers copy-on-write branching in ~1 second with zero storage cost
until you write. Its serverless compute model scales to zero between
queries, so an idle PR branch costs nothing. The tradeoff is a 500ms-2s
cold start on the first query after idle — acceptable for preview traffic,
annoying for production.

For production, you have two options:

- **Stay on Neon** with `--min-instances=1` or autosuspend disabled to
  eliminate cold starts. ~$5-10/month per always-on compute.
- **Use Cloud SQL or AlloyDB for production**, Neon for PR previews. More
  complex but gives you Google-native observability for prod.

This template assumes Neon for both. Switch if your scale requires it.

---

## The Preview URL Pattern

Cloud Run generates preview URLs with a literal `---` separator:

```
https://pr-42---my-app-abc123.us-central1.run.app
```

- `pr-42` — the revision tag
- `my-app-abc123` — the base service hostname (stable)
- `us-central1.run.app` — Cloud Run's regional DNS

The URL is stable for the life of the tag — it doesn't change when you
push new commits to the PR (the tag points at the latest revision). You
can bookmark it, share it, and link to it from the PR comment.

---

## Known Limitations

### No Build-Time Env Var Baking Problem

Unlike Next.js, FastAPI reads all env vars at runtime. Preview and
production use the same image; `gcloud run deploy --set-env-vars` passes
per-environment configuration at deploy time. There is no "build-time
vs runtime env var" distinction to trip over.

If your app needs the public URL for self-referential operations (email
links, email templates, signed redirects), use pattern #28 in
`docs/PATTERN-LIBRARY.md` — read `X-Forwarded-Host` from the request or
set `APP_URL` as a runtime env var that differs per deploy.

### Cold Start on First Request

Preview revisions use `--min-instances=0`. The first request after a few
minutes of idle takes 2-5 seconds (Cloud Run container start) plus
500ms-2s (Neon compute wakeup). Smoke tests in `preview-deploy.yml`
retry for 60 seconds to handle this.

### One Neon Free Tier Project Per Account

Neon's free tier allows 10 branches per project. For a team with more
than ~10 concurrent PRs, you'll hit the branch limit. Options:

- Upgrade to the Launch tier ($19/month, 5000 branches).
- Delete stale branches more aggressively (the cleanup workflow only
  handles closed PRs).

### Preview Revisions Don't Auto-Clean on Quota Pressure

Cloud Run accumulates revisions forever until it hits the 1000-per-service
limit. The cleanup workflow removes **tags** but leaves revisions. After
a few months on a busy project, you may want to manually prune old
revisions:

```bash
gcloud run revisions list --service=my-app --region=us-central1 --limit=200 \
  | awk 'NR>1 && !/True/ {print $2}' \
  | xargs -I {} gcloud run revisions delete {} --region=us-central1 --quiet
```

(Only deletes inactive revisions — the active one is protected.)

---

## Debugging a Broken Preview

**Preview URL returns 404 / Service Unavailable:**

1. Check the Cloud Run service has the tag: `gcloud run services describe
   my-app --region=us-central1 --format='value(status.traffic[].tag)'`
2. If the tag exists, check the revision status: `gcloud run revisions
   describe REVISION_NAME --region=us-central1`
3. If the revision failed, check the container logs: `gcloud logging read
   'resource.type="cloud_run_revision" AND resource.labels.revision_name="REVISION_NAME"'`

**Most common cause:** missing `--host 0.0.0.0` on the uvicorn command in the Dockerfile. See
pattern #1 in `docs/PATTERN-LIBRARY.md`.

**Preview URL works but database queries fail:**

1. Check the Neon branch exists: `neonctl branches list`
2. Check the pooled connection string was passed:
   `gcloud run revisions describe REVISION_NAME --region=us-central1 --format=yaml | grep DATABASE_URL`
3. The URL should end in `-pooler.region.aws.neon.tech`. If it doesn't,
   you're using the direct URL and will exhaust connections. See
   pattern #9.

**Preview URL takes 10+ seconds on first load:**

This is the expected cold start behavior. Cloud Run + Neon both scale to
zero. First request warms everything up. Second request is fast.

If you need faster cold starts for a specific PR demo, temporarily bump
`--min-instances=1` on the preview revision:

```bash
gcloud run services update my-app \
  --region=us-central1 \
  --min-instances=1
```

Reset to 0 after the demo.

---

## Cost

For typical workshop / small-team usage:

| Resource | Cost per preview | Cost per month (10 PRs) |
|----------|------------------|------------------------|
| Cloud Run preview revisions | $0 (scale-to-zero) | $0 |
| Artifact Registry storage | ~$0.01 per image | ~$0.10 |
| Neon branch storage | $0 (free tier) | $0 |
| Neon compute hours | $0 (free tier) | $0 |

Expected: **under $1/month** for most projects.

Budget cap recommendation: $25/month on the GCP project, with alerts at
50% and 90%. Covers runaway agent loops without breaking the bank.

---

## Comparison to Upstream Agile Flow (Render + Supabase)

| Feature | Upstream (Render + Supabase) | This fork (GCP + Neon) |
|---------|------------------------------|----------------------|
| Preview compute | Render preview services (one per PR) | Cloud Run tagged revisions (shared service) |
| Preview DB | Supabase branches | Neon branches |
| Preview URL | `https://app-pr-42.onrender.com` | `https://pr-42---app-xyz.run.app` |
| Cold start | 30-60 sec (Render free tier spin-up) | 2-5 sec (Cloud Run) + 0.5-2 sec (Neon) |
| Cleanup | Render auto-deletes on PR close | Cleanup workflow removes tag + Neon branch |
| Service proliferation | One service per PR | One service, many tags |
| Secret management | Render env vars API (silent redeploy required) | Secret Manager (deploy-time mount) |

The GCP version has faster cold starts, cleaner service management, and
avoids Render's notorious env-var-requires-redeploy gotcha. The Render
version has simpler preview URL formatting and zero Dockerfile ownership.

Pick based on what your team already knows. For GCP-native teams, this
fork is the better starting point.
