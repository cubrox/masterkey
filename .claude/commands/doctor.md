---
description: "Run a comprehensive health check of the local environment and remote configuration"
---

# /doctor — Agile Flow Health Check

Run a comprehensive diagnostic of the local environment and remote
configuration. Surfaces every issue that could block a workshop participant.

## Instructions

1. Run the local diagnostic script and capture the full output:

   ```bash
   bash scripts/doctor.sh
   ```

1. Parse the machine-readable summary block between `=== DOCTOR_SUMMARY ===`
   and `=== END_SUMMARY ===`. Extract PASS, WARN, FAIL, and SKIP counts.

1. Perform these **remote checks** that the shell script cannot do:

   a. **Branch protection rulesets** — run:

      ```text
      gh api repos/{owner}/{repo}/rulesets
      ```

      - PASS if at least one ruleset exists targeting `main`
      - WARN if no rulesets found

   b. **Repository secrets** — run:

      ```text
      gh secret list
      ```

      Check for presence (not values) of:
      - `GCP_PROJECT_ID` — WARN if missing (required for any deploy)
      - `GCP_WORKLOAD_IDENTITY_PROVIDER` — WARN if missing AND `GCP_SA_KEY` is also missing
      - `GCP_SERVICE_ACCOUNT` — WARN if missing AND `GCP_SA_KEY` is also missing
      - `GCP_SA_KEY` — OK if missing when WIF is configured (workshop fallback only)
      - `NEON_API_KEY` — WARN if missing (required for PR preview branching)
      - `NEON_PROJECT_ID` — WARN if missing (required for PR preview branching)
      - `PRODUCTION_DATABASE_URL` — WARN if missing (required to run
        Alembic migrations against the prod Neon branch during deploy)

   d. **Local gcloud auth** — run:

      ```text
      gcloud auth list --format=json 2>/dev/null
      ```

      - PASS if at least one active account is listed
      - WARN if no active account (user needs `gcloud auth login`)
      - SKIP if `gcloud` is not installed (note: required for local
        container builds and manual deploys, but CI works without it)

   e. **Local gcloud project** — run:

      ```text
      gcloud config get-value project 2>/dev/null
      ```

      - PASS if a project is set
      - WARN if unset (user needs `gcloud config set project ${GCP_PROJECT_ID}`)
      - SKIP if `gcloud` is not installed

   f. **Local uv and Python** — check for `uv` in `$PATH` and
      `pyproject.toml` at repo root:

      ```text
      which uv && uv --version
      test -f pyproject.toml && echo "pyproject.toml present"
      ```

      - PASS if `uv` is installed AND `pyproject.toml` exists
      - WARN if `uv` is missing (needed for local dev; CI installs it
        automatically)
      - WARN if `pyproject.toml` is missing (this is a Python project —
        something is wrong)

   c. **GitHub Project board** — run:

      ```text
      gh project list --owner {owner} --format json
      ```

      - PASS if at least one project exists
      - WARN if no projects found

1. Format a **health report table** combining local + remote results:

   ```text
   ## Agile Flow Health Report

   ### Local Checks (from scripts/doctor.sh)
   PASS: {n}  WARN: {n}  FAIL: {n}  SKIP: {n}

   ### Remote + Environment Checks
   | Check | Status | Details |
   |-------|--------|---------|
   | Branch protection | PASS/WARN | ... |
   | Repo secrets (GCP) | PASS/WARN | ... |
   | Repo secrets (Neon) | PASS/WARN | ... |
   | Project board | PASS/WARN | ... |
   | Local gcloud auth | PASS/WARN/SKIP | ... |
   | Local gcloud project | PASS/WARN/SKIP | ... |
   | Local uv + pyproject | PASS/WARN | ... |

   ### Overall
   Ready for workshop: **YES** / **NO**
   ```

1. If there are any FAILs or WARNs, list **actionable fix instructions**
   for each one at the bottom of the report.

## Important

- This is a **read-only diagnostic**. Do not modify any files or settings.
- Do not launch sub-agents. Run all checks inline.
- Derive `{owner}` and `{repo}` from `git remote get-url origin`.
- **Non-admin users**: `gh api rulesets` and `gh secret list` may return
  404 or 403 for users without admin access. Map these responses to
  WARN or SKIP rather than FAIL — the checks are informational and do
  not indicate a broken setup.

### Output Format

End your output with a Result Block:

```
---

**Result:** Health check complete
Local: 8 pass, 1 warn, 0 fail
Remote: 3 pass, 1 warn, 0 fail
Ready for workshop: YES
```
