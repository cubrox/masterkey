#!/usr/bin/env bash
#
# workshop-setup.sh — pre-flight + delegate to provision-workshop-roster.sh.
#
# Canonical entry point for facilitators bringing up a workshop classroom.
# Runs four pre-flight checks before handing off to the existing
# CSV-driven provisioning script. Fails fast with actionable messages
# rather than letting gcloud's mid-loop errors be the first signal.
#
# Usage:
#   BILLING_ACCOUNT_ID=XXX-XXXX-XXXX ./scripts/workshop-setup.sh roster.csv
#
# Required environment variables:
#   BILLING_ACCOUNT_ID   GCP billing account to attach each project to
#
# Optional (forwarded to provision-workshop-roster.sh):
#   GCP_REGION           default: us-central1
#   ARTIFACT_REPO        default: agile-flow
#   PROVISION_SCRIPT     default: scripts/provision-gcp-project.sh
#
# Pre-flight checks (in order):
#   1. gcloud is installed and has an active account
#   2. BILLING_ACCOUNT_ID is set and the account is OPEN
#   3. Roster file exists and has the expected header
#   4. Roster has at least one data row
#
# This script does NOT duplicate provisioning logic. After pre-flight
# passes, it execs the existing wrapper.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROSTER_WRAPPER="${ROSTER_WRAPPER:-$REPO_ROOT/scripts/provision-workshop-roster.sh}"

# ── Argument parsing ─────────────────────────────────────────────────────

if [[ $# -ne 1 ]]; then
  cat >&2 <<EOF
Usage: BILLING_ACCOUNT_ID=XXX ./scripts/workshop-setup.sh <roster.csv>

See header of $0 for full documentation.
EOF
  exit 2
fi

ROSTER_CSV="$1"

# ── Pre-flight ───────────────────────────────────────────────────────────

echo "──────────────────────────────────────────────────"
echo "  Workshop setup pre-flight"
echo "──────────────────────────────────────────────────"

fail=0

# 1. gcloud auth
if ! command -v gcloud >/dev/null 2>&1; then
  echo "  [fail] gcloud is not installed or not on PATH" >&2
  fail=1
elif ! gcloud auth list --filter='status:ACTIVE' --format='value(account)' 2>/dev/null | grep -q '@'; then
  echo "  [fail] no active gcloud account — run 'gcloud auth login'" >&2
  fail=1
else
  active_acct="$(gcloud auth list --filter='status:ACTIVE' --format='value(account)')"
  echo "  [ok]   gcloud authed as $active_acct"
fi

# 2. BILLING_ACCOUNT_ID
if [[ -z "${BILLING_ACCOUNT_ID:-}" ]]; then
  echo "  [fail] BILLING_ACCOUNT_ID is not set" >&2
  fail=1
else
  # Verify the billing account is OPEN. If gcloud is mocked in tests, this
  # check still works because the stub respects the same flags.
  billing_state="$(gcloud billing accounts list --filter="name~$BILLING_ACCOUNT_ID" --format='value(open)' 2>/dev/null || true)"
  if [[ "$billing_state" == "True" ]]; then
    echo "  [ok]   billing account $BILLING_ACCOUNT_ID is OPEN"
  else
    echo "  [fail] billing account $BILLING_ACCOUNT_ID not found or not OPEN" >&2
    echo "         (got: '$billing_state')" >&2
    fail=1
  fi
fi

# 3. Roster file + header
if [[ ! -f "$ROSTER_CSV" ]]; then
  echo "  [fail] roster file not found: $ROSTER_CSV" >&2
  fail=1
else
  expected_header_4="handle,github_user,email,cohort"
  expected_header_5="handle,github_user,email,cohort,neon_branch"
  expected_header_6="handle,github_user,email,cohort,neon_branch,github_full_repo"
  actual_header="$(head -n 1 "$ROSTER_CSV" | tr -d '\r')"
  if [[ "$actual_header" == "$expected_header_4" \
     || "$actual_header" == "$expected_header_5" \
     || "$actual_header" == "$expected_header_6" ]]; then
    echo "  [ok]   roster header is valid"
  else
    echo "  [fail] roster header must be one of:" >&2
    echo "           $expected_header_4" >&2
    echo "           $expected_header_5" >&2
    echo "           $expected_header_6" >&2
    echo "         got: $actual_header" >&2
    fail=1
  fi

  # 4. Has at least one data row
  data_rows="$(tail -n +2 "$ROSTER_CSV" | grep -cE '^[^,]+,' || true)"
  if (( data_rows >= 1 )); then
    echo "  [ok]   roster has $data_rows data row(s)"
  else
    echo "  [fail] roster has no data rows" >&2
    fail=1
  fi
fi

if (( fail != 0 )); then
  echo ""
  echo "  Pre-flight failed. Fix the issue(s) above and re-run."
  exit 2
fi

# ── Hand off to provisioning ─────────────────────────────────────────────

if [[ ! -x "$ROSTER_WRAPPER" ]]; then
  echo "  [fail] roster wrapper not executable: $ROSTER_WRAPPER" >&2
  exit 2
fi

echo ""
echo "──────────────────────────────────────────────────"
echo "  Pre-flight passed — provisioning starts now"
echo "──────────────────────────────────────────────────"
echo ""

exec "$ROSTER_WRAPPER" "$ROSTER_CSV"
