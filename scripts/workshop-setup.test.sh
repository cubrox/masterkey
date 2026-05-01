#!/usr/bin/env bash
#
# Tests for workshop-setup.sh — pre-flight check behavior.
#
# Stubs gcloud + the inner provision-workshop-roster.sh via PATH
# injection and ROSTER_WRAPPER override. Each test asserts a specific
# pre-flight failure path or the happy-path delegation.
#
# Run: ./scripts/workshop-setup.test.sh

# Pre-flight tests deliberately exercise failure paths; -e gets in the way.
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/workshop-setup.sh"

new_tmp() { mktemp -d -t aflowsetup-XXXX; }

# Stub gcloud + roster wrapper. $1: behavior — "ok" | "no-auth" | "billing-closed"
make_stubs() {
  local tmp="$1"
  local behavior="$2"
  mkdir -p "$tmp/bin"

  cat > "$tmp/bin/gcloud" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "auth list")
    if [[ "$behavior" == "no-auth" ]]; then
      exit 0  # no output → no @ matched → fail
    fi
    echo "active@example.com"
    exit 0
    ;;
  "billing accounts")
    # billing accounts list --filter ... --format='value(open)'
    if [[ "$behavior" == "billing-closed" ]]; then
      echo "False"
    else
      echo "True"
    fi
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF

  cat > "$tmp/bin/roster-wrapper.sh" <<EOF
#!/usr/bin/env bash
echo "ROSTER WRAPPER CALLED with: \$*" > "$tmp/wrapper.log"
exit 0
EOF

  chmod +x "$tmp/bin/gcloud" "$tmp/bin/roster-wrapper.sh"
}

write_roster() {
  cat > "$1" <<'EOF'
handle,github_user,email,cohort
alice,alice-gh,alice@example.com,2026-05
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

# ── Test 1: Happy path — pre-flight passes, hands off to wrapper ────────

echo ""
echo "Test 1: pre-flight passes and execs the roster wrapper"

T1=$(new_tmp)
make_stubs "$T1" "ok"
write_roster "$T1/roster.csv"

PATH="$T1/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  ROSTER_WRAPPER="$T1/bin/roster-wrapper.sh" \
  "$SCRIPT" "$T1/roster.csv" > "$T1/stdout.log" 2>&1
ec=$?

assert_eq "0" "$ec" "exit 0"
assert_contains "ok.*gcloud authed" "$T1/stdout.log" "logs gcloud auth ok"
assert_contains "ok.*billing account" "$T1/stdout.log" "logs billing ok"
assert_contains "ok.*roster header is valid" "$T1/stdout.log" "logs header ok"
assert_contains "ok.*roster has 1 data row" "$T1/stdout.log" "logs row count"
if [[ -f "$T1/wrapper.log" ]] && grep -q "ROSTER WRAPPER CALLED" "$T1/wrapper.log"; then
  echo -e "  ${GREEN}✓${NC} roster wrapper was invoked"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} roster wrapper was NOT invoked"
  FAIL=$((FAIL + 1))
fi

# ── Test 2: No active gcloud auth → exit 2, no wrapper call ────────────

echo ""
echo "Test 2: missing gcloud auth fails pre-flight"

T2=$(new_tmp)
make_stubs "$T2" "no-auth"
write_roster "$T2/roster.csv"

PATH="$T2/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  ROSTER_WRAPPER="$T2/bin/roster-wrapper.sh" \
  "$SCRIPT" "$T2/roster.csv" > "$T2/stdout.log" 2>&1
ec=$?

assert_eq "2" "$ec" "exit 2 on missing auth"
assert_contains "fail.*no active gcloud account" "$T2/stdout.log" "logs auth failure"
if [[ ! -f "$T2/wrapper.log" ]]; then
  echo -e "  ${GREEN}✓${NC} roster wrapper NOT invoked"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} roster wrapper was invoked despite pre-flight failure"
  FAIL=$((FAIL + 1))
fi

# ── Test 3: Missing BILLING_ACCOUNT_ID → exit 2 ────────────────────────

echo ""
echo "Test 3: missing BILLING_ACCOUNT_ID fails pre-flight"

T3=$(new_tmp)
make_stubs "$T3" "ok"
write_roster "$T3/roster.csv"

PATH="$T3/bin:$PATH" \
  ROSTER_WRAPPER="$T3/bin/roster-wrapper.sh" \
  "$SCRIPT" "$T3/roster.csv" > "$T3/stdout.log" 2>&1
ec=$?

assert_eq "2" "$ec" "exit 2 on missing BILLING_ACCOUNT_ID"
assert_contains "fail.*BILLING_ACCOUNT_ID is not set" "$T3/stdout.log" "logs missing env"

# ── Test 4: Billing account closed → exit 2 ────────────────────────────

echo ""
echo "Test 4: closed billing account fails pre-flight"

T4=$(new_tmp)
make_stubs "$T4" "billing-closed"
write_roster "$T4/roster.csv"

PATH="$T4/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  ROSTER_WRAPPER="$T4/bin/roster-wrapper.sh" \
  "$SCRIPT" "$T4/roster.csv" > "$T4/stdout.log" 2>&1
ec=$?

assert_eq "2" "$ec" "exit 2 on closed billing account"
assert_contains "fail.*not found or not OPEN" "$T4/stdout.log" "logs billing failure"

# ── Test 5: Bad roster header → exit 2 ─────────────────────────────────

echo ""
echo "Test 5: bad roster header fails pre-flight"

T5=$(new_tmp)
make_stubs "$T5" "ok"
cat > "$T5/roster.csv" <<EOF
name,email
alice,alice@example.com
EOF

PATH="$T5/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  ROSTER_WRAPPER="$T5/bin/roster-wrapper.sh" \
  "$SCRIPT" "$T5/roster.csv" > "$T5/stdout.log" 2>&1
ec=$?

assert_eq "2" "$ec" "exit 2 on bad header"
assert_contains "fail.*roster header must be" "$T5/stdout.log" "logs header failure"

# ── Test 6: Empty roster (header only) → exit 2 ────────────────────────

echo ""
echo "Test 6: empty roster (header only) fails pre-flight"

T6=$(new_tmp)
make_stubs "$T6" "ok"
echo "handle,github_user,email,cohort" > "$T6/roster.csv"

PATH="$T6/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  ROSTER_WRAPPER="$T6/bin/roster-wrapper.sh" \
  "$SCRIPT" "$T6/roster.csv" > "$T6/stdout.log" 2>&1
ec=$?

assert_eq "2" "$ec" "exit 2 on empty roster"
assert_contains "fail.*roster has no data rows" "$T6/stdout.log" "logs empty-roster failure"

# ── Test 7: 5-column header is accepted by pre-flight ───────────────────

echo ""
echo "Test 7: 5-column roster header passes pre-flight"

T7=$(new_tmp)
make_stubs "$T7" "ok"
cat > "$T7/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch
alice,alice-gh,alice@example.com,2026-05,
EOF

PATH="$T7/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  ROSTER_WRAPPER="$T7/bin/roster-wrapper.sh" \
  "$SCRIPT" "$T7/roster.csv" > "$T7/stdout.log" 2>&1
ec=$?

assert_eq "0" "$ec" "exit 0 with 5-column header"
assert_contains "ok.*roster header is valid" "$T7/stdout.log" "logs header ok"

# ── Test 8: 6-column header is accepted by pre-flight ───────────────────

echo ""
echo "Test 8: 6-column roster header passes pre-flight"

T8=$(new_tmp)
make_stubs "$T8" "ok"
cat > "$T8/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch,github_full_repo
alice,alice-gh,alice@acme.com,2026-05,alice,acme/agile-flow-alice
EOF

PATH="$T8/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  ROSTER_WRAPPER="$T8/bin/roster-wrapper.sh" \
  "$SCRIPT" "$T8/roster.csv" > "$T8/stdout.log" 2>&1
ec=$?

assert_eq "0" "$ec" "exit 0 with 6-column header"
assert_contains "ok.*roster header is valid" "$T8/stdout.log" "logs header ok"

# ── Summary ─────────────────────────────────────────────────────────────

echo ""
echo "─────────────────────────────────"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "─────────────────────────────────"

(( FAIL > 0 )) && exit 1
exit 0
