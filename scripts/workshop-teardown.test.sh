#!/usr/bin/env bash
#
# Tests for workshop-teardown.sh — deletion loop, idempotency,
# confirmation handling, and CSV-derived ID guard.
#
# Run: ./scripts/workshop-teardown.test.sh

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/workshop-teardown.sh"

new_tmp() { mktemp -d -t aflowdown-XXXX; }

# Stub gcloud. $1: behavior — "all-active" | "all-deleted" | "fail-delete"
make_stubs() {
  local tmp="$1"
  local behavior="$2"
  mkdir -p "$tmp/bin"

  cat > "$tmp/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$tmp/gcloud.log"
case "\$1 \$2" in
  "projects describe")
    case "$behavior" in
      all-active|fail-delete) echo "ACTIVE" ;;
      all-deleted)            echo "DELETE_REQUESTED" ;;
      *)                      echo "ACTIVE" ;;
    esac
    exit 0
    ;;
  "projects delete")
    if [[ "$behavior" == "fail-delete" ]]; then
      exit 1
    fi
    exit 0
    ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$tmp/bin/gcloud"
}

write_roster() {
  cat > "$1" <<'EOF'
handle,github_user,email,cohort
alice,alice-gh,alice@example.com,2026-05
bob,bob-gh,bob@example.com,2026-05
EOF
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo -e "  ${GREEN}✓${NC} $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC} $label  (expected: $expected; got: $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local needle="$1" file="$2" label="$3"
  if grep -q "$needle" "$file"; then
    echo -e "  ${GREEN}✓${NC} $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC} $label  (looking for: $needle in $file)"
    FAIL=$((FAIL + 1))
  fi
}

# ── Test 1: Happy path with --yes → both projects deleted ───────────────

echo ""
echo "Test 1: --yes deletes both ACTIVE projects"

T1=$(new_tmp)
make_stubs "$T1" "all-active"
write_roster "$T1/roster.csv"
# Pre-create an output csv so we can verify cleanup
echo "stale" > "$T1/roster-output.csv"

PATH="$T1/bin:$PATH" \
  OUTPUT_CSV="$T1/roster-output.csv" \
  "$SCRIPT" "$T1/roster.csv" --yes > "$T1/stdout.log" 2>&1
ec=$?

assert_eq "0" "$ec" "exit 0"
assert_eq "2" "$(grep -c 'projects delete' "$T1/gcloud.log")" "gcloud projects delete called twice"
assert_contains "Deleted:  2" "$T1/stdout.log" "summary shows 2 deleted"
if [[ ! -f "$T1/roster-output.csv" ]]; then
  echo -e "  ${GREEN}✓${NC} roster-output.csv removed"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} roster-output.csv was NOT removed"
  FAIL=$((FAIL + 1))
fi
if [[ -f "$T1/roster.csv" ]]; then
  echo -e "  ${GREEN}✓${NC} roster.csv (input) preserved"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} roster.csv (input) was deleted — should not be"
  FAIL=$((FAIL + 1))
fi

# ── Test 2: Idempotent re-run (already DELETE_REQUESTED) ───────────────

echo ""
echo "Test 2: idempotent re-run on already-deleted projects"

T2=$(new_tmp)
make_stubs "$T2" "all-deleted"
write_roster "$T2/roster.csv"

PATH="$T2/bin:$PATH" \
  OUTPUT_CSV="$T2/roster-output.csv" \
  "$SCRIPT" "$T2/roster.csv" --yes > "$T2/stdout.log" 2>&1
ec=$?

assert_eq "0" "$ec" "exit 0 on idempotent re-run"
assert_eq "0" "$(grep -c 'projects delete' "$T2/gcloud.log")" "gcloud projects delete NOT called"
assert_contains "Skipped:  2" "$T2/stdout.log" "summary shows 2 skipped"

# ── Test 3: --yes flag actually skips the prompt ────────────────────────
# Without --yes, the script reads from stdin; with --yes it should not block.

echo ""
echo "Test 3: --yes does not block on stdin"

T3=$(new_tmp)
make_stubs "$T3" "all-active"
write_roster "$T3/roster.csv"

# Run with stdin closed; if the prompt triggered, the read would fail and
# the script would abort. With --yes, it should sail through.
PATH="$T3/bin:$PATH" \
  OUTPUT_CSV="$T3/roster-output.csv" \
  "$SCRIPT" "$T3/roster.csv" --yes < /dev/null > "$T3/stdout.log" 2>&1
ec=$?

assert_eq "0" "$ec" "exit 0 with --yes and closed stdin"

# ── Test 4: Bad CSV header rejected ────────────────────────────────────

echo ""
echo "Test 4: bad CSV header fails fast"

T4=$(new_tmp)
make_stubs "$T4" "all-active"
cat > "$T4/roster.csv" <<EOF
name,email
alice,alice@example.com
EOF

PATH="$T4/bin:$PATH" \
  OUTPUT_CSV="$T4/roster-output.csv" \
  "$SCRIPT" "$T4/roster.csv" --yes > "$T4/stdout.log" 2>&1
ec=$?

assert_eq "2" "$ec" "exit 2 on bad header"
assert_eq "0" "$(grep -c 'projects delete' "$T4/gcloud.log" 2>/dev/null || echo 0)" "no gcloud deletes were attempted"

# ── Test 5: Project IDs derive from roster (no arbitrary IDs) ──────────
# Verifies the scope guard: the gcloud invocations only target IDs that
# match the af-{handle}-{cohort} pattern from the CSV.

echo ""
echo "Test 5: only roster-derived project IDs are touched"

T5=$(new_tmp)
make_stubs "$T5" "all-active"
write_roster "$T5/roster.csv"

PATH="$T5/bin:$PATH" \
  OUTPUT_CSV="$T5/roster-output.csv" \
  "$SCRIPT" "$T5/roster.csv" --yes > "$T5/stdout.log" 2>&1

# Whitelist check: every "projects describe" line must end with one of the
# two expected IDs. Filter out the expected lines, see if anything remains.
unexpected="$(grep 'projects describe' "$T5/gcloud.log" \
  | grep -v 'projects describe af-alice-2026-05 ' \
  | grep -v 'projects describe af-bob-2026-05 ' || true)"

if grep -q 'projects describe af-alice-2026-05' "$T5/gcloud.log" && \
   grep -q 'projects describe af-bob-2026-05' "$T5/gcloud.log" && \
   [[ -z "$unexpected" ]]; then
  echo -e "  ${GREEN}✓${NC} only af-alice-2026-05 and af-bob-2026-05 were inspected"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} unexpected project IDs in gcloud.log:"
  echo "$unexpected"
  FAIL=$((FAIL + 1))
fi

# ── Test 6: Failed delete reported in summary ──────────────────────────

echo ""
echo "Test 6: failed gcloud delete is reflected in summary"

T6=$(new_tmp)
make_stubs "$T6" "fail-delete"
write_roster "$T6/roster.csv"

PATH="$T6/bin:$PATH" \
  OUTPUT_CSV="$T6/roster-output.csv" \
  "$SCRIPT" "$T6/roster.csv" --yes > "$T6/stdout.log" 2>&1
ec=$?

assert_eq "1" "$ec" "exit 1 when any delete fails"
assert_contains "Failed:   2" "$T6/stdout.log" "summary shows failures"

# ── Test 7: 5-column roster is accepted ─────────────────────────────────
# Teardown only reads handle + cohort, so the 5th column is ignored — but
# the header validation must accept the wider shape.

echo ""
echo "Test 7: 5-column roster header is accepted"

T7=$(new_tmp)
make_stubs "$T7" "all-active"
cat > "$T7/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch
alice,alice-gh,alice@example.com,2026-05,
bob,bob-gh,bob@example.com,2026-05,bob_personal
EOF

PATH="$T7/bin:$PATH" \
  OUTPUT_CSV="$T7/roster-output.csv" \
  "$SCRIPT" "$T7/roster.csv" --yes > "$T7/stdout.log" 2>&1
ec=$?

assert_eq "0" "$ec" "exit 0 with 5-column header"
assert_eq "2" "$(grep -c 'projects delete' "$T7/gcloud.log")" "both rows still attempted (5th column ignored)"

# ── Test 8: 6-column roster is accepted ─────────────────────────────────

echo ""
echo "Test 8: 6-column roster header is accepted"

T8=$(new_tmp)
make_stubs "$T8" "all-active"
cat > "$T8/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch,github_full_repo
alice,alice-gh,alice@acme.com,2026-05,alice,acme/agile-flow-alice
bob,bob-gh,bob@acme.com,2026-05,bob,acme/widget-shop
EOF

PATH="$T8/bin:$PATH" \
  OUTPUT_CSV="$T8/roster-output.csv" \
  "$SCRIPT" "$T8/roster.csv" --yes > "$T8/stdout.log" 2>&1
ec=$?

assert_eq "0" "$ec" "exit 0 with 6-column header"
assert_eq "2" "$(grep -c 'projects delete' "$T8/gcloud.log")" "both rows still attempted (6th column ignored)"

# ── Summary ─────────────────────────────────────────────────────────────

echo ""
echo "─────────────────────────────────"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "─────────────────────────────────"

(( FAIL > 0 )) && exit 1
exit 0
