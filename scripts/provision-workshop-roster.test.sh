#!/usr/bin/env bash
#
# Tests for provision-workshop-roster.sh
#
# Stubs `gcloud` and the inner provisioner via PATH injection + env override
# so we can assert behavior without touching real GCP.
#
# Run: ./scripts/provision-workshop-roster.test.sh

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$REPO_ROOT/scripts/provision-workshop-roster.sh"

# Each test runs in a fresh tmpdir to keep output CSVs isolated.
new_tmp() {
  mktemp -d -t aflowtest-XXXX
}

# Build a fake gcloud + provision-gcp-project.sh in $tmp/bin and prepend to PATH.
#   $1: tmpdir
#   $2: behavior — "ok", "skip-first" (project exists for first row), or "fail"
make_stubs() {
  local tmp="$1"
  local behavior="$2"
  mkdir -p "$tmp/bin"

  # Fake gcloud
  cat > "$tmp/bin/gcloud" <<EOF
#!/usr/bin/env bash
# Log every invocation to a file so the test can assert on it.
echo "gcloud \$*" >> "$tmp/gcloud.log"

case "\$1" in
  projects)
    case "\$2" in
      describe)
        # describe <project_id>
        if [[ "$behavior" == "skip-first" && "\$3" == af-alice-* ]]; then
          exit 0  # alice's project "exists"
        fi
        exit 1    # default: project does not exist
        ;;
      add-iam-policy-binding)
        exit 0
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac
EOF

  # Fake inner provisioner
  cat > "$tmp/bin/provision-gcp-project.sh" <<EOF
#!/usr/bin/env bash
# Log every invocation along with the env vars the wrapper is supposed
# to forward. Tests grep this log to verify per-row env passthrough.
echo "provision \$* GCP_PROJECT_ID=\${GCP_PROJECT_ID:-} GITHUB_USERNAME=\${GITHUB_USERNAME:-} GITHUB_OWNER=\${GITHUB_OWNER:-} GITHUB_REPO=\${GITHUB_REPO:-} NEON_BRANCH_NAME=\${NEON_BRANCH_NAME:-}" >> "$tmp/provision.log"

if [[ "$behavior" == "fail" ]]; then
  echo "fake provision failure" >&2
  exit 1
fi
exit 0
EOF

  chmod +x "$tmp/bin/gcloud" "$tmp/bin/provision-gcp-project.sh"
}

write_roster() {
  local path="$1"
  cat > "$path" <<'EOF'
handle,github_user,email,cohort
alice,alice-gh,alice@example.com,2026-05
bob,bob-gh,bob@example.com,2026-05
EOF
}

assert_contains() {
  local needle="$1"
  local haystack_file="$2"
  local label="$3"
  if grep -q "$needle" "$haystack_file"; then
    echo -e "  ${GREEN}✓${NC} $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC} $label  (looking for: $needle in $haystack_file)"
    FAIL=$((FAIL + 1))
  fi
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo -e "  ${GREEN}✓${NC} $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC} $label  (expected: $expected; got: $actual)"
    FAIL=$((FAIL + 1))
  fi
}

# ── Test 1: Happy path — both rows attempted, output CSV correct ─────────

echo ""
echo "Test 1: Happy path with 2-row roster"

T1=$(new_tmp)
make_stubs "$T1" "ok"
write_roster "$T1/roster.csv"

set +e
PATH="$T1/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T1/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T1/roster-output.csv" \
  "$WRAPPER" "$T1/roster.csv" > "$T1/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0"
assert_eq "2" "$(grep -c '^provision' "$T1/provision.log")" "inner provisioner called twice"
assert_contains "alice,af-alice-2026-05,created" "$T1/roster-output.csv" "alice row recorded as created"
assert_contains "bob,af-bob-2026-05,created" "$T1/roster-output.csv" "bob row recorded as created"
assert_contains "Total rows processed:   2" "$T1/stdout.log" "summary shows 2 rows"

# ── Test 2: Idempotent re-run — both rows show "skipped" ─────────────────

echo ""
echo "Test 2: Idempotent re-run (project already exists for both rows)"

T2=$(new_tmp)
# Custom stub: gcloud projects describe always succeeds (project exists)
mkdir -p "$T2/bin"
cat > "$T2/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$T2/gcloud.log"
case "\$1 \$2" in
  "projects describe") exit 0 ;;  # always exists
  "projects add-iam-policy-binding") exit 0 ;;
  *) exit 0 ;;
esac
EOF
cat > "$T2/bin/provision-gcp-project.sh" <<EOF
#!/usr/bin/env bash
echo "provision \$* GCP_PROJECT_ID=\${GCP_PROJECT_ID:-}" >> "$T2/provision.log"
exit 0
EOF
chmod +x "$T2/bin/gcloud" "$T2/bin/provision-gcp-project.sh"

write_roster "$T2/roster.csv"

set +e
PATH="$T2/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T2/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T2/roster-output.csv" \
  "$WRAPPER" "$T2/roster.csv" > "$T2/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 on re-run"
assert_contains "alice,af-alice-2026-05,skipped" "$T2/roster-output.csv" "alice row recorded as skipped"
assert_contains "bob,af-bob-2026-05,skipped" "$T2/roster-output.csv" "bob row recorded as skipped"
assert_contains "Already existed:        2" "$T2/stdout.log" "summary shows 2 skipped"

# ── Test 3: Fail-fast — first row fails, second row never attempted ─────

echo ""
echo "Test 3: Fail-fast on first-row error"

T3=$(new_tmp)
make_stubs "$T3" "fail"
write_roster "$T3/roster.csv"

set +e
PATH="$T3/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T3/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T3/roster-output.csv" \
  "$WRAPPER" "$T3/roster.csv" > "$T3/stdout.log" 2>&1
exit_code=$?
set -e

if [[ "$exit_code" -ne 0 ]]; then
  echo -e "  ${GREEN}✓${NC} wrapper exits non-zero on inner failure (got $exit_code)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} wrapper should fail on inner script failure (got 0)"
  FAIL=$((FAIL + 1))
fi
assert_eq "1" "$(grep -c '^provision' "$T3/provision.log")" "inner provisioner called only once before exit"

# ── Test 4: Bad CSV header rejected ──────────────────────────────────────

echo ""
echo "Test 4: Bad CSV header is rejected"

T4=$(new_tmp)
make_stubs "$T4" "ok"
cat > "$T4/roster.csv" <<EOF
name,email
alice,alice@example.com
EOF

set +e
PATH="$T4/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T4/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T4/roster-output.csv" \
  "$WRAPPER" "$T4/roster.csv" > "$T4/stdout.log" 2>&1
exit_code=$?
set -e

if [[ "$exit_code" -eq 2 ]]; then
  echo -e "  ${GREEN}✓${NC} wrapper exits 2 on bad header"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} wrapper should exit 2 on bad header (got $exit_code)"
  FAIL=$((FAIL + 1))
fi
assert_contains "header must be one of" "$T4/stdout.log" "error message mentions header format"

# ── Test 5: Missing BILLING_ACCOUNT_ID rejected ─────────────────────────

echo ""
echo "Test 5: Missing BILLING_ACCOUNT_ID is rejected"

T5=$(new_tmp)
make_stubs "$T5" "ok"
write_roster "$T5/roster.csv"

set +e
PATH="$T5/bin:$PATH" \
  PROVISION_SCRIPT="$T5/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T5/roster-output.csv" \
  "$WRAPPER" "$T5/roster.csv" > "$T5/stdout.log" 2>&1
exit_code=$?
set -e

if [[ "$exit_code" -eq 2 ]]; then
  echo -e "  ${GREEN}✓${NC} wrapper exits 2 when BILLING_ACCOUNT_ID is unset"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} wrapper should exit 2 when BILLING_ACCOUNT_ID is unset (got $exit_code)"
  FAIL=$((FAIL + 1))
fi

# ── Test 6: 5-column header + neon_branch column passes through ─────────
# Verifies that:
#   - 5-column header is accepted
#   - NEON_BRANCH_NAME is exported per row from the 5th column
#   - When the 5th column is empty for a row, defaults to handle

echo ""
echo "Test 6: 5-column header forwards NEON_BRANCH_NAME"

T6=$(new_tmp)
make_stubs "$T6" "ok"
cat > "$T6/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch
alice,alice-gh,alice@example.com,2026-05,
bob,bob-gh,bob@example.com,2026-05,bob_personal
EOF

set +e
PATH="$T6/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T6/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T6/roster-output.csv" \
  "$WRAPPER" "$T6/roster.csv" > "$T6/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with 5-column header"
# alice row should default neon_branch to handle (empty 5th column → handle)
assert_contains "GCP_PROJECT_ID=af-alice-2026-05.*NEON_BRANCH_NAME=alice" "$T6/provision.log" "alice row defaults NEON_BRANCH_NAME to handle"
# bob row uses the explicit override
assert_contains "GCP_PROJECT_ID=af-bob-2026-05.*NEON_BRANCH_NAME=bob_personal" "$T6/provision.log" "bob row uses explicit neon_branch override"

# ── Test 7: 4-column header still works (NEON_BRANCH_NAME defaults) ─────

echo ""
echo "Test 7: 4-column header still works (defaults NEON_BRANCH_NAME to handle)"

T7=$(new_tmp)
make_stubs "$T7" "ok"
write_roster "$T7/roster.csv"

set +e
PATH="$T7/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T7/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T7/roster-output.csv" \
  "$WRAPPER" "$T7/roster.csv" > "$T7/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with 4-column header"
assert_contains "GCP_PROJECT_ID=af-alice-2026-05.*NEON_BRANCH_NAME=alice" "$T7/provision.log" "alice defaults to handle (4-column)"
assert_contains "GCP_PROJECT_ID=af-bob-2026-05.*NEON_BRANCH_NAME=bob" "$T7/provision.log" "bob defaults to handle (4-column)"

# ── Test 8: invalid neon_branch value fails fast ────────────────────────

echo ""
echo "Test 8: invalid neon_branch fails the row fast"

T8=$(new_tmp)
make_stubs "$T8" "ok"
cat > "$T8/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch
alice,alice-gh,alice@example.com,2026-05,bad branch with spaces
EOF

set +e
PATH="$T8/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T8/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T8/roster-output.csv" \
  "$WRAPPER" "$T8/roster.csv" > "$T8/stdout.log" 2>&1
exit_code=$?
set -e

# Note: 'bad branch with spaces' → after whitespace stripping → 'badbranchwithspaces'
# which actually IS valid alphanumeric. Use a value that's invalid even after stripping.
# Re-write with a value containing $ (definitely invalid).
cat > "$T8/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch
alice,alice-gh,alice@example.com,2026-05,bad\$value
EOF

set +e
PATH="$T8/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T8/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T8/roster-output.csv" \
  "$WRAPPER" "$T8/roster.csv" > "$T8/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "2" "$exit_code" "wrapper exits 2 on invalid neon_branch"
assert_contains "invalid neon_branch" "$T8/stdout.log" "error message names the field"

# ── Test 9: 6-column header + explicit github_full_repo passes through ──
#
# Verifies that:
#   - 6-column header is accepted
#   - github_full_repo splits at slash; owner+repo exported separately
#   - alice's row uses an org owner (acme); bob's row uses a different owner

echo ""
echo "Test 9: 6-column header forwards GITHUB_OWNER + GITHUB_REPO"

T9=$(new_tmp)
make_stubs "$T9" "ok"
cat > "$T9/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch,github_full_repo
alice,alice-gh,alice@acme.com,2026-05,alice,acme/agile-flow-alice
bob,bob-gh,bob@acme.com,2026-05,bob,acme/widget-shop
EOF

set +e
PATH="$T9/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T9/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T9/roster-output.csv" \
  "$WRAPPER" "$T9/roster.csv" > "$T9/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with 6-column header"
assert_contains "GCP_PROJECT_ID=af-alice-2026-05.*GITHUB_OWNER=acme.*GITHUB_REPO=agile-flow-alice" "$T9/provision.log" "alice row exports acme owner + alice repo"
assert_contains "GCP_PROJECT_ID=af-bob-2026-05.*GITHUB_OWNER=acme.*GITHUB_REPO=widget-shop" "$T9/provision.log" "bob row exports acme owner + widget-shop repo"

# ── Test 10: empty github_full_repo defaults to <github_user>/agile-flow-gcp ──

echo ""
echo "Test 10: empty github_full_repo defaults to <github_user>/agile-flow-gcp"

T10=$(new_tmp)
make_stubs "$T10" "ok"
cat > "$T10/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch,github_full_repo
carol,carol-gh,carol@example.com,2026-05,carol,
EOF

set +e
PATH="$T10/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T10/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T10/roster-output.csv" \
  "$WRAPPER" "$T10/roster.csv" > "$T10/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with empty github_full_repo"
assert_contains "GITHUB_OWNER=carol-gh.*GITHUB_REPO=agile-flow-gcp" "$T10/provision.log" "defaults to <github_user>/agile-flow-gcp"

# ── Test 11: invalid github_full_repo fails fast ────────────────────────

echo ""
echo "Test 11: invalid github_full_repo fails the row fast"

T11=$(new_tmp)
make_stubs "$T11" "ok"
# Use a value with double slash, which the regex rejects.
cat > "$T11/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch,github_full_repo
alice,alice-gh,alice@acme.com,2026-05,alice,acme//bad-repo
EOF

set +e
PATH="$T11/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T11/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T11/roster-output.csv" \
  "$WRAPPER" "$T11/roster.csv" > "$T11/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "2" "$exit_code" "wrapper exits 2 on invalid github_full_repo"
assert_contains "invalid github_full_repo" "$T11/stdout.log" "error message names the field"

# ── Test 12: 4-column legacy roster — github_full_repo defaults work ────

echo ""
echo "Test 12: 4-column header still works (defaults github_full_repo)"

T12=$(new_tmp)
make_stubs "$T12" "ok"
write_roster "$T12/roster.csv"  # 4-column

set +e
PATH="$T12/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T12/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T12/roster-output.csv" \
  "$WRAPPER" "$T12/roster.csv" > "$T12/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with 4-column header"
# alice/bob should both default to <user>/agile-flow-gcp
assert_contains "GITHUB_OWNER=alice-gh.*GITHUB_REPO=agile-flow-gcp" "$T12/provision.log" "alice defaults to alice-gh/agile-flow-gcp"
assert_contains "GITHUB_OWNER=bob-gh.*GITHUB_REPO=agile-flow-gcp" "$T12/provision.log" "bob defaults to bob-gh/agile-flow-gcp"

# ── Summary ──────────────────────────────────────────────────────────────

echo ""
echo "─────────────────────────────────"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "─────────────────────────────────"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
