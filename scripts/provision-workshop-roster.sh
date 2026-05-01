#!/usr/bin/env bash
#
# provision-workshop-roster.sh — multi-project provisioning from a CSV roster.
#
# Wraps scripts/provision-gcp-project.sh for workshop facilitators who need
# to provision N participant projects in one command.
#
# Usage:
#   BILLING_ACCOUNT_ID=XXX-XXXX-XXXX ./scripts/provision-workshop-roster.sh roster.csv
#   BILLING_ACCOUNT_ID=XXX ./scripts/provision-workshop-roster.sh roster.csv --force-shared-parent
#
# Required environment variables:
#   BILLING_ACCOUNT_ID   The GCP billing account to attach each project to
#
# Optional flags:
#   --force-shared-parent    Pass NEON_FORCE_SHARED_PARENT=true to the inner
#                            script. By default, an existing Neon branch with
#                            a roster handle's name causes the inner script
#                            to fail with an actionable error (#90 — prevents
#                            silent cross-contamination). Set this flag to
#                            opt back into the previous silent-reuse behavior
#                            for paired collaboration or re-running an existing
#                            cohort against a still-populated Neon project.
#
# Optional environment variables:
#   GCP_REGION           (default: us-central1) — passed through to inner script
#   ARTIFACT_REPO        (default: agile-flow)  — passed through to inner script
#   PROVISION_SCRIPT     (default: scripts/provision-gcp-project.sh) — for tests
#   NEON_API_KEY         optional; forwarded to inner script for branch creation
#   NEON_PROJECT_ID      optional; forwarded to inner script for branch creation
#   NEON_FORCE_SHARED_PARENT  same effect as --force-shared-parent above; the
#                            flag sets this env var on the inner script
#   BUDGET_CAP_USD       optional; forwarded to inner script for Step 5.6
#                        (per-project billing budget). Default for workshop
#                        usage is 25.
#
# CSV format (header required, accepts 4, 5, or 6 columns):
#   handle,github_user,email,cohort
#   alice,alice-gh,alice@example.com,2026-05
#   bob,bob-gh,bob@example.com,2026-05
#
#   handle,github_user,email,cohort,neon_branch        (5-column variant)
#   alice,alice-gh,alice@example.com,2026-05,alice
#   bob,bob-gh,bob@example.com,2026-05,bob_personal    (explicit branch override)
#
#   handle,github_user,email,cohort,neon_branch,github_full_repo   (6-column)
#   alice,alice-gh,alice@acme.com,2026-05,alice,acme/agile-flow-alice
#   bob,bob-gh,bob@acme.com,2026-05,bob,acme/widget-shop
#   carol,carol-gh,carol@example.com,2026-05,carol,                (defaults)
#
# When the optional `neon_branch` column is empty or absent, NEON_BRANCH_NAME
# defaults to the row's `handle`. Use the override when the same person needs
# a stable Neon branch across cohorts (different `cohort` value, same branch).
#
# When the optional `github_full_repo` column is empty or absent,
# defaults to `<github_user>/agile-flow-gcp`. Use the override when
# attendees fork into an org and rename the repo to fit their product.
# The wrapper splits the value at the slash and exports GITHUB_OWNER and
# GITHUB_REPO to the inner script.
#
# Project IDs follow the pattern  af-{handle}-{cohort}  and are globally
# unique. This is non-negotiable: the runbook, day-1 doc, and dry-run
# checklist all assume this shape.
#
# Side effects per row:
#   1. Calls provision-gcp-project.sh --create-project (idempotent)
#   2. Grants roles/editor on the new project to the participant's email
#   3. Appends a row to roster-output.csv with status + project ID
#
# This script is fail-fast: the loop stops on the first row that errors,
# so a half-provisioned classroom does not silently happen.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVISION_SCRIPT="${PROVISION_SCRIPT:-$REPO_ROOT/scripts/provision-gcp-project.sh}"
OUTPUT_CSV="${OUTPUT_CSV:-roster-output.csv}"

# ── Argument parsing ─────────────────────────────────────────────────────

ROSTER_CSV=""
FORCE_SHARED_PARENT="${NEON_FORCE_SHARED_PARENT:-false}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-shared-parent)
      FORCE_SHARED_PARENT=true
      shift
      ;;
    -h|--help)
      sed -n '1,60p' "$0"
      exit 0
      ;;
    --*)
      echo "ERROR: unknown flag: $1" >&2
      exit 2
      ;;
    *)
      if [[ -n "$ROSTER_CSV" ]]; then
        echo "ERROR: multiple positional arguments; expected exactly one (the roster CSV)" >&2
        exit 2
      fi
      ROSTER_CSV="$1"
      shift
      ;;
  esac
done

if [[ -z "$ROSTER_CSV" ]]; then
  cat >&2 <<EOF
Usage: BILLING_ACCOUNT_ID=XXX ./scripts/provision-workshop-roster.sh <roster.csv> [--force-shared-parent]

See header of $0 for full documentation.
EOF
  exit 2
fi

if [[ ! -f "$ROSTER_CSV" ]]; then
  echo "ERROR: roster file not found: $ROSTER_CSV" >&2
  exit 2
fi

if [[ -z "${BILLING_ACCOUNT_ID:-}" ]]; then
  echo "ERROR: BILLING_ACCOUNT_ID is required" >&2
  exit 2
fi

if [[ ! -x "$PROVISION_SCRIPT" ]]; then
  echo "ERROR: inner provision script not executable: $PROVISION_SCRIPT" >&2
  exit 2
fi

# ── CSV header validation ────────────────────────────────────────────────
#
# The roster format accepts two header shapes:
#   1. handle,github_user,email,cohort               (4 columns, original)
#   2. handle,github_user,email,cohort,neon_branch   (5 columns, with Neon
#                                                     branch override)
#
# When the 5th column is present and non-empty for a row, NEON_BRANCH_NAME
# takes that value. Otherwise it defaults to the row's `handle` — which
# matches the GCP project ID's handle component, so attendee branches are
# named alice / bob / etc. by default.

EXPECTED_HEADER_4="handle,github_user,email,cohort"
EXPECTED_HEADER_5="handle,github_user,email,cohort,neon_branch"
EXPECTED_HEADER_6="handle,github_user,email,cohort,neon_branch,github_full_repo"
ACTUAL_HEADER="$(head -n 1 "$ROSTER_CSV" | tr -d '\r')"

if [[ "$ACTUAL_HEADER" != "$EXPECTED_HEADER_4" \
   && "$ACTUAL_HEADER" != "$EXPECTED_HEADER_5" \
   && "$ACTUAL_HEADER" != "$EXPECTED_HEADER_6" ]]; then
  echo "ERROR: roster CSV header must be one of:" >&2
  echo "       $EXPECTED_HEADER_4" >&2
  echo "       $EXPECTED_HEADER_5" >&2
  echo "       $EXPECTED_HEADER_6" >&2
  echo "       got: $ACTUAL_HEADER" >&2
  exit 2
fi

# ── Output CSV setup ─────────────────────────────────────────────────────

if [[ ! -f "$OUTPUT_CSV" ]]; then
  echo "handle,project_id,status,wif_provider,timestamp" > "$OUTPUT_CSV"
fi

# ── Counters ─────────────────────────────────────────────────────────────

total=0
created=0
skipped=0

# ── Loop ─────────────────────────────────────────────────────────────────

# tail -n +2 skips header. Process substitution avoids subshell so counters
# survive into the summary block.
#
# We read 6 fields. 4- and 5-column rows leave the trailing fields empty;
# the default-fallback logic below covers them.
while IFS=',' read -r handle github_user email cohort neon_branch github_full_repo; do
  # Strip whitespace and CR (Windows line endings)
  handle="$(echo "$handle" | tr -d '[:space:]\r')"
  github_user="$(echo "$github_user" | tr -d '[:space:]\r')"
  email="$(echo "$email" | tr -d '[:space:]\r')"
  cohort="$(echo "$cohort" | tr -d '[:space:]\r')"
  neon_branch="$(echo "${neon_branch:-}" | tr -d '[:space:]\r')"
  github_full_repo="$(echo "${github_full_repo:-}" | tr -d '[:space:]\r')"

  if [[ -z "$handle" || -z "$cohort" ]]; then
    continue
  fi

  # Default neon_branch to handle when not explicitly set per row.
  if [[ -z "$neon_branch" ]]; then
    neon_branch="$handle"
  fi

  # Validate Neon branch name: 1-63 chars, alphanumeric + hyphen + underscore.
  # Reject anything else fail-fast on this row, since the inner script's
  # Neon API call would error mid-loop with a less-clear message.
  if ! [[ "$neon_branch" =~ ^[A-Za-z0-9_-]{1,63}$ ]]; then
    echo "ERROR: invalid neon_branch '$neon_branch' for handle '$handle'" >&2
    echo "       must be 1-63 chars, alphanumeric + hyphen + underscore only" >&2
    exit 2
  fi

  # Default github_full_repo to "<github_user>/agile-flow-gcp" when not set.
  # That preserves today's behavior for personal-fork participants.
  if [[ -z "$github_full_repo" ]]; then
    github_full_repo="${github_user}/agile-flow-gcp"
  fi

  # Validate <owner>/<repo> shape. GitHub owner: alphanumeric + hyphens
  # (1-39 chars). Repo: alphanumeric + dot + hyphen + underscore (1-100).
  # Strict check rejects empty fragments, double slashes, leading/trailing
  # whitespace (already stripped above), etc.
  if ! [[ "$github_full_repo" =~ ^[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$ ]]; then
    echo "ERROR: invalid github_full_repo '$github_full_repo' for handle '$handle'" >&2
    echo "       must be <owner>/<repo> with allowed chars only" >&2
    exit 2
  fi

  # Split into owner and repo for env-var passthrough.
  github_owner="${github_full_repo%%/*}"
  github_repo="${github_full_repo##*/}"

  total=$((total + 1))
  project_id="af-${handle}-${cohort}"
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  echo ""
  echo "──────────────────────────────────────────────────"
  echo "  [$total] $handle  ->  $project_id"
  echo "──────────────────────────────────────────────────"

  # Detect whether the project already exists, so we can label the output
  # row honestly. The inner script is idempotent either way, so this is
  # purely for the summary CSV.
  if gcloud projects describe "$project_id" >/dev/null 2>&1; then
    status="skipped"
    skipped=$((skipped + 1))
  else
    status="created"
    created=$((created + 1))
  fi

  # Run the inner provisioner. It handles "already exists" internally;
  # we just pass through the env it needs.
  #
  # GITHUB_OWNER + GITHUB_REPO together enable WIF setup (Step 5.5).
  # Together they identify the GitHub repo whose Actions runs are
  # trusted to impersonate the deployer SA. Empty owner skips the step.
  # GITHUB_USERNAME is also exported as a legacy alias of GITHUB_OWNER
  # for any external caller still relying on that env-var name.
  #
  # NEON_BRANCH_NAME enables the Neon-branch-per-attendee step (5.7).
  # NEON_API_KEY and NEON_PROJECT_ID are forwarded only if set in the
  # facilitator's environment; the inner script skips that step when
  # either is missing.
  GCP_PROJECT_ID="$project_id" \
  BILLING_ACCOUNT_ID="$BILLING_ACCOUNT_ID" \
  GCP_REGION="${GCP_REGION:-us-central1}" \
  ARTIFACT_REPO="${ARTIFACT_REPO:-agile-flow}" \
  GITHUB_OWNER="$github_owner" \
  GITHUB_REPO="$github_repo" \
  GITHUB_USERNAME="$github_user" \
  GITHUB_REPOSITORY="$github_full_repo" \
  NEON_BRANCH_NAME="$neon_branch" \
  NEON_API_KEY="${NEON_API_KEY:-}" \
  NEON_PROJECT_ID="${NEON_PROJECT_ID:-}" \
  NEON_FORCE_SHARED_PARENT="$FORCE_SHARED_PARENT" \
  BUDGET_CAP_USD="${BUDGET_CAP_USD:-}" \
    "$PROVISION_SCRIPT" --create-project

  # Grant the participant editor on their own project. Idempotent.
  echo ""
  echo "[bind] roles/editor -> user:$email"
  gcloud projects add-iam-policy-binding "$project_id" \
    --member="user:$email" \
    --role="roles/editor" \
    --condition=None \
    --quiet >/dev/null

  # WIF provider resource path. The inner script's Step 5.5 created the
  # pool + provider when GITHUB_USERNAME was non-empty; record the canonical
  # resource string for the summary CSV so the facilitator can paste it
  # straight into participant fork secrets.
  wif_provider=""
  if [[ -n "$github_user" ]]; then
    project_number="$(gcloud projects describe "$project_id" --format='value(projectNumber)' 2>/dev/null || true)"
    if [[ -n "$project_number" ]]; then
      wif_provider="projects/${project_number}/locations/global/workloadIdentityPools/github/providers/github"
    fi
  fi

  echo "$handle,$project_id,$status,$wif_provider,$timestamp" >> "$OUTPUT_CSV"
done < <(tail -n +2 "$ROSTER_CSV")

# ── Summary ──────────────────────────────────────────────────────────────

echo ""
echo "=================================="
echo "  Workshop provisioning summary"
echo "=================================="
echo "  Total rows processed:   $total"
echo "  Newly created:          $created"
echo "  Already existed:        $skipped"
echo "  Failed:                 0   (script is fail-fast — see above for any error)"
echo ""
echo "  Output: $OUTPUT_CSV"
echo "  Next:   set up WIF (manually or via #5) and send each participant"
echo "          their setup email per docs/PLATFORM-GUIDE.md."
