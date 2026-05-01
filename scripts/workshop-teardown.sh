#!/usr/bin/env bash
#
# workshop-teardown.sh — delete participant projects from a CSV roster.
#
# Reverse of workshop-setup.sh. Reads the same roster, computes the
# project IDs from af-{handle}-{cohort}, prompts for confirmation,
# and calls `gcloud projects delete` per row.
#
# Usage:
#   ./scripts/workshop-teardown.sh roster.csv          # interactive
#   ./scripts/workshop-teardown.sh roster.csv --yes    # skip prompt
#
# Idempotent: re-running on already-torn-down projects logs [skip]
# rows and exits 0. Will NOT touch projects whose IDs do not derive
# from this roster — protects against malformed CSVs taking down
# unrelated production projects.
#
# Side effect: removes roster-output.csv after the loop, since it's
# stale once projects are gone. Does NOT remove roster.csv (input).

set -euo pipefail

OUTPUT_CSV="${OUTPUT_CSV:-roster-output.csv}"
ASSUME_YES=false

# ── Argument parsing ─────────────────────────────────────────────────────

if [[ $# -lt 1 || $# -gt 2 ]]; then
  cat >&2 <<EOF
Usage: ./scripts/workshop-teardown.sh <roster.csv> [--yes]

See header of $0 for full documentation.
EOF
  exit 2
fi

ROSTER_CSV="$1"

if [[ "${2:-}" == "--yes" ]]; then
  ASSUME_YES=true
elif [[ -n "${2:-}" ]]; then
  echo "ERROR: unknown flag: $2" >&2
  exit 2
fi

if [[ ! -f "$ROSTER_CSV" ]]; then
  echo "ERROR: roster file not found: $ROSTER_CSV" >&2
  exit 2
fi

# ── CSV header validation ───────────────────────────────────────────────
# Accept both 4-column and 5-column shapes. Teardown only reads handle and
# cohort to compute project IDs; the 5th column is ignored here.

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

# ── Build project ID list from roster ────────────────────────────────────

declare -a project_ids=()
# Reads up to 6 fields. 4- and 5-column rows leave the trailing fields
# empty (we don't use them for teardown — only handle + cohort are
# needed to compute project IDs). 6-column rows have github_full_repo
# captured and ignored. Without these names, a 6-column row would leak
# its trailing values into cohort.
# shellcheck disable=SC2034  # github_user, email, neon_branch, github_full_repo unused; required per roster format
while IFS=',' read -r handle github_user email cohort neon_branch github_full_repo; do
  handle="$(echo "$handle" | tr -d '[:space:]\r')"
  cohort="$(echo "$cohort" | tr -d '[:space:]\r')"
  if [[ -z "$handle" || -z "$cohort" ]]; then
    continue
  fi
  project_ids+=("af-${handle}-${cohort}")
done < <(tail -n +2 "$ROSTER_CSV")

if (( ${#project_ids[@]} == 0 )); then
  echo "ERROR: roster has no data rows" >&2
  exit 2
fi

# ── Confirmation prompt ─────────────────────────────────────────────────

echo "──────────────────────────────────────────────────"
echo "  Workshop teardown — projects targeted"
echo "──────────────────────────────────────────────────"
for pid in "${project_ids[@]}"; do
  echo "  • $pid"
done
echo ""
echo "  GCP holds project IDs for ~30 days after deletion."
echo "  Re-creating with the same ID is blocked during that window."
echo ""

if [[ "$ASSUME_YES" != "true" ]]; then
  read -r -p "Delete ${#project_ids[@]} project(s)? [y/N] " reply
  if [[ "$reply" != "y" && "$reply" != "Y" ]]; then
    echo "Aborted by user."
    exit 0
  fi
fi

# ── Deletion loop ───────────────────────────────────────────────────────

deleted=0
skipped=0
failed=0

for pid in "${project_ids[@]}"; do
  echo ""
  echo "──────────────────────────────────────────────────"
  echo "  $pid"
  echo "──────────────────────────────────────────────────"

  state="$(gcloud projects describe "$pid" --format='value(lifecycleState)' 2>/dev/null || echo "NOT_FOUND")"

  case "$state" in
    ACTIVE)
      echo "[delete] $pid (was ACTIVE)"
      if gcloud projects delete "$pid" --quiet; then
        deleted=$((deleted + 1))
      else
        echo "[fail] gcloud projects delete returned non-zero for $pid" >&2
        failed=$((failed + 1))
      fi
      ;;
    DELETE_REQUESTED)
      echo "[skip] $pid is already DELETE_REQUESTED"
      skipped=$((skipped + 1))
      ;;
    NOT_FOUND)
      echo "[skip] $pid not found (already gone or never created)"
      skipped=$((skipped + 1))
      ;;
    *)
      echo "[skip] $pid is in unexpected state: $state"
      skipped=$((skipped + 1))
      ;;
  esac
done

# ── Cleanup output CSV ──────────────────────────────────────────────────

if [[ -f "$OUTPUT_CSV" ]]; then
  rm -f "$OUTPUT_CSV"
  echo ""
  echo "[clean] removed $OUTPUT_CSV"
fi

# ── Summary ─────────────────────────────────────────────────────────────

echo ""
echo "=================================="
echo "  Teardown summary"
echo "=================================="
echo "  Targeted: ${#project_ids[@]}"
echo "  Deleted:  $deleted"
echo "  Skipped:  $skipped"
echo "  Failed:   $failed"
echo ""

if (( failed != 0 )); then
  exit 1
fi
exit 0
