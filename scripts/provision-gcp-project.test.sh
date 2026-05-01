#!/usr/bin/env bash
#
# Tests for the retry_eventual_consistency helper in
# scripts/provision-gcp-project.sh.
#
# We source the script's helper section by extracting it (the script's
# main body requires GCP_PROJECT_ID; we don't want to run that in tests).
#
# Run: ./scripts/provision-gcp-project.test.sh

# Tests deliberately exercise failure paths, so `set -e` would short-circuit
# before assertions run. We rely on explicit exit-code captures instead.
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/provision-gcp-project.sh"

# Pull the helper definition into the current shell. The helper block is
# bounded by its leading comment and the `retry_eventual_consistency()`
# closing brace at column 1 (matched by `^}`).
HELPER_SRC="$(awk '
  /^retry_eventual_consistency\(\)/ { capture=1 }
  /^RETRY_MAX_ATTEMPTS=/ || /^RETRY_MAX_SLEEP=/ { print; next }
  capture { print }
  capture && /^}/ { exit }
' "$SCRIPT")"

# Use small delays so the test runs in <1s.
export RETRY_MAX_ATTEMPTS=4
export RETRY_MAX_SLEEP=1

# shellcheck disable=SC1090,SC2086
eval "$HELPER_SRC"

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

# ── Test 1: command succeeds first try → exit 0, no sleep ────────────────

echo ""
echo "Test 1: success on first attempt"

set +e
out=$(retry_eventual_consistency "ok cmd" -- bash -c 'true' 2>&1)
ec=$?
set -e
assert_eq "0" "$ec" "exit 0"
assert_eq "" "$out" "no retry log written"

# ── Test 2: transient 403 → retry → eventual success ────────────────────

echo ""
echo "Test 2: transient 403 then success"

# Stub command that fails twice with the eventual-consistency signature,
# then succeeds. Use a tmpfile counter.
COUNTER=$(mktemp)
echo 0 > "$COUNTER"
FLAKY_CMD=$(mktemp)
cat > "$FLAKY_CMD" <<EOF
#!/usr/bin/env bash
n=\$(<"$COUNTER")
n=\$((n + 1))
echo \$n > "$COUNTER"
if (( n < 3 )); then
  echo "ERROR: PERMISSION_DENIED: foo denied on resource projects/x" >&2
  exit 1
fi
exit 0
EOF
chmod +x "$FLAKY_CMD"

set +e
out=$(retry_eventual_consistency "flaky" -- "$FLAKY_CMD" 2>&1)
ec=$?
set -e
assert_eq "0" "$ec" "exit 0 after retries"
assert_eq "3" "$(cat "$COUNTER")" "command invoked 3 times (2 fail + 1 success)"

if echo "$out" | grep -q "retry 1/4"; then
  echo -e "  ${GREEN}✓${NC} first retry logged"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[retry 1/4]' in stderr; got: $out"
  FAIL=$((FAIL + 1))
fi

rm -f "$FLAKY_CMD" "$COUNTER"

# ── Test 3: permanent error (already-exists) → fail immediately ─────────

echo ""
echo "Test 3: permanent error fails on first attempt without retrying"

COUNTER=$(mktemp); echo 0 > "$COUNTER"
PERM_CMD=$(mktemp)
cat > "$PERM_CMD" <<EOF
#!/usr/bin/env bash
n=\$(<"$COUNTER")
echo \$((n + 1)) > "$COUNTER"
echo "ERROR: already exists: foo" >&2
exit 1
EOF
chmod +x "$PERM_CMD"

set +e
retry_eventual_consistency "perm" -- "$PERM_CMD" >/dev/null 2>&1
ec=$?
set -e
assert_eq "1" "$ec" "exit non-zero on permanent error"
assert_eq "1" "$(cat "$COUNTER")" "command invoked exactly once (no retry)"

rm -f "$PERM_CMD" "$COUNTER"

# ── Test 4: transient error exhausts retries → fail with logged exhaustion

echo ""
echo "Test 4: transient error exhausts retries"

COUNTER=$(mktemp); echo 0 > "$COUNTER"
ALWAYS_FLAKY=$(mktemp)
cat > "$ALWAYS_FLAKY" <<EOF
#!/usr/bin/env bash
n=\$(<"$COUNTER")
echo \$((n + 1)) > "$COUNTER"
echo "ERROR: PERMISSION_DENIED: denied on resource projects/x" >&2
exit 1
EOF
chmod +x "$ALWAYS_FLAKY"

set +e
out=$(retry_eventual_consistency "always-flaky" -- "$ALWAYS_FLAKY" 2>&1)
ec=$?
set -e
assert_eq "1" "$ec" "exit non-zero after exhaustion"
assert_eq "$RETRY_MAX_ATTEMPTS" "$(cat "$COUNTER")" "command invoked RETRY_MAX_ATTEMPTS times"

if echo "$out" | grep -q "exhausted"; then
  echo -e "  ${GREEN}✓${NC} exhaustion logged"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected 'exhausted' in stderr; got: $out"
  FAIL=$((FAIL + 1))
fi

rm -f "$ALWAYS_FLAKY" "$COUNTER"

# ── Test 5: bad invocation (missing -- separator) → exit 2 ─────────────

echo ""
echo "Test 5: bad invocation"

set +e
retry_eventual_consistency "label" "not-a-separator" "true" >/dev/null 2>&1
ec=$?
set -e
assert_eq "2" "$ec" "exit 2 on missing -- separator"

# ── Test 6: SA-not-exist transient (INVALID_ARGUMENT after SA create) ───
# Reproduces the live bug observed 2026-04-27: `gcloud projects
# add-iam-policy-binding` against a just-created SA returns
# INVALID_ARGUMENT: Service account ... does not exist. The retry helper
# must classify this as transient, not permanent.

echo ""
echo "Test 6: SA-not-exist transient is retried"

COUNTER=$(mktemp); echo 0 > "$COUNTER"
SA_FLAKY=$(mktemp)
cat > "$SA_FLAKY" <<EOF
#!/usr/bin/env bash
n=\$(<"$COUNTER")
n=\$((n + 1))
echo \$n > "$COUNTER"
if (( n < 2 )); then
  echo "ERROR: (gcloud.projects.add-iam-policy-binding) INVALID_ARGUMENT: Service account deployer@af-x.iam.gserviceaccount.com does not exist." >&2
  exit 1
fi
exit 0
EOF
chmod +x "$SA_FLAKY"

out=$(retry_eventual_consistency "sa flaky" -- "$SA_FLAKY" 2>&1)
ec=$?
assert_eq "0" "$ec" "exit 0 after SA-not-exist retried"
assert_eq "2" "$(cat "$COUNTER")" "command invoked twice (1 fail + 1 success)"

if echo "$out" | grep -q "retry 1/"; then
  echo -e "  ${GREEN}✓${NC} SA-not-exist classified as transient"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[retry 1/...]' in stderr — was SA-not-exist treated as permanent?"
  FAIL=$((FAIL + 1))
fi

rm -f "$SA_FLAKY" "$COUNTER"

# ── Test 7: project exists but not owned → fail with clear error ─────────
# Reproduces the live bug observed 2026-04-27 where a roster row hit a
# project ID that exists outside the caller's reach (different org, or
# soft-deleted with no perms). describe succeeds, get-iam-policy fails.

echo ""
echo "Test 7: exists-but-not-yours fails fast with clear message"

T7=$(mktemp -d -t aflowtest-XXXX)
mkdir -p "$T7/bin"

# Stub gcloud to: describe succeeds, get-iam-policy fails, all else fail.
cat > "$T7/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$T7/gcloud.log"
case "\$1 \$2" in
  "projects describe") exit 0 ;;
  "projects get-iam-policy")
    echo "ERROR: PERMISSION_DENIED on getIamPolicy" >&2
    exit 1
    ;;
  *)
    echo "FATAL: stub should never be called for: \$*" >&2
    exit 99
    ;;
esac
EOF
chmod +x "$T7/bin/gcloud"

set +e
PATH="$T7/bin:$PATH" \
  GCP_PROJECT_ID="af-collision-2026-05" \
  BILLING_ACCOUNT_ID="FAKE" \
  "$SCRIPT" --create-project > "$T7/stdout.log" 2>&1
ec=$?
set -e

assert_eq "1" "$ec" "exit 1 on exists-but-not-yours"

# Critical assertion: billing-link must NEVER be called when ownership probe fails.
# That was the live bug — billing-link fired and produced a confusing error.
billing_calls=0
if [[ -f "$T7/gcloud.log" ]]; then
  billing_calls="$(grep -c 'billing projects link' "$T7/gcloud.log" || true)"
fi
assert_eq "0" "$billing_calls" "billing-link was NOT called"

if grep -q "globally unique" "$T7/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} error message names the global-uniqueness cause"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected error message to mention 'globally unique'; got:"
  cat "$T7/stdout.log"
  FAIL=$((FAIL + 1))
fi

if grep -qi "'cohort' column" "$T7/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} error message names the workaround"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected error message to suggest changing cohort"
  FAIL=$((FAIL + 1))
fi

# ── Test 8: project exists in own org but is DELETE_REQUESTED → fail ─────

echo ""
echo "Test 8: exists-in-own-org-but-not-ACTIVE fails fast"

T8=$(mktemp -d -t aflowtest-XXXX)
mkdir -p "$T8/bin"

# Stub: describe succeeds, get-iam-policy succeeds, lifecycleState query
# returns DELETE_REQUESTED.
cat > "$T8/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$T8/gcloud.log"
case "\$1 \$2" in
  "projects describe")
    # The script calls describe twice: once to check existence (no flags),
    # once to read lifecycleState. Distinguish by --format presence.
    if echo "\$*" | grep -q -- "--format"; then
      echo "DELETE_REQUESTED"
    fi
    exit 0
    ;;
  "projects get-iam-policy") exit 0 ;;
  *)
    echo "FATAL: stub should never be called for: \$*" >&2
    exit 99
    ;;
esac
EOF
chmod +x "$T8/bin/gcloud"

set +e
PATH="$T8/bin:$PATH" \
  GCP_PROJECT_ID="af-zombie-2026-05" \
  BILLING_ACCOUNT_ID="FAKE" \
  "$SCRIPT" --create-project > "$T8/stdout.log" 2>&1
ec=$?
set -e

assert_eq "1" "$ec" "exit 1 on DELETE_REQUESTED"

billing_calls=0
if [[ -f "$T8/gcloud.log" ]]; then
  billing_calls="$(grep -c 'billing projects link' "$T8/gcloud.log" || true)"
fi
assert_eq "0" "$billing_calls" "billing-link was NOT called"

if grep -q "DELETE_REQUESTED" "$T8/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} error message names the lifecycleState"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected error message to mention DELETE_REQUESTED; got:"
  cat "$T8/stdout.log"
  FAIL=$((FAIL + 1))
fi

# ── Test 8b: Step 1 idempotent billing-link skip ────────────────────────
# Reproduces the live bug observed during the 2026-04-29 dry-run: with 5
# projects already linked to the billing account (the default cap), every
# `billing projects link` call fails with `Cloud billing quota exceeded`
# regardless of whether the project is already linked. Re-running the
# wrapper on an already-provisioned project should detect the existing
# link via `billing projects describe` and skip the link call.

echo ""
echo "Test 8b: Step 1 skips billing link when project already linked"

T8B=$(mktemp -d -t aflowtest-XXXX)
mkdir -p "$T8B/bin"

# Stub: project exists + ACTIVE + own org; billing-describe returns the
# expected billingAccountName so the new logic should take the [skip] path.
# The link sub-command exits non-zero so an unwanted invocation surfaces.
cat > "$T8B/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$T8B/gcloud.log"
case "\$1 \$2" in
  "projects describe")
    if echo "\$*" | grep -q -- "--format"; then
      echo "ACTIVE"
    fi
    exit 0
    ;;
  "projects get-iam-policy") exit 0 ;;
  "billing projects")
    case "\$3" in
      describe)
        # Mimic gcloud --format=value(billingAccountName) output for an
        # already-linked project.
        echo "billingAccounts/FAKE-BILLING-ID"
        exit 0
        ;;
      link)
        echo "FATAL: link should NOT be called when project already linked" >&2
        exit 99
        ;;
    esac
    ;;
  "services enable") exit 1 ;;  # short-circuit past Step 2
  *) exit 0 ;;
esac
EOF
chmod +x "$T8B/bin/gcloud"

set +e
PATH="$T8B/bin:$PATH" \
  GCP_PROJECT_ID="af-already-linked" \
  BILLING_ACCOUNT_ID="FAKE-BILLING-ID" \
  "$SCRIPT" --create-project > "$T8B/stdout.log" 2>&1
set -e

if grep -q "skip.*Billing account FAKE-BILLING-ID already linked" "$T8B/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} skip-link log line"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[skip] Billing account ... already linked' in stdout"
  cat "$T8B/stdout.log"
  FAIL=$((FAIL + 1))
fi

# Critical regression guard: link must NEVER be called when the project
# is already linked to the same account. The fatal-stub on `link` would
# fire if it did, but we also check the gcloud log to be explicit.
if ! grep -q "billing projects link" "$T8B/gcloud.log"; then
  echo -e "  ${GREEN}✓${NC} gcloud billing projects link NOT invoked"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} link should NOT have been called; this is the live-bug regression"
  FAIL=$((FAIL + 1))
fi

# Sanity: describe SHOULD have been called to make the decision.
if grep -q "billing projects describe" "$T8B/gcloud.log"; then
  echo -e "  ${GREEN}✓${NC} gcloud billing projects describe was the probe"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected billing projects describe to probe current link"
  cat "$T8B/gcloud.log"
  FAIL=$((FAIL + 1))
fi

# ── Test 8c: Step 1 still links when project linked to a DIFFERENT account ─
# Edge case: the project exists and has billing enabled, but to a different
# account than what BILLING_ACCOUNT_ID specifies. The script should still
# call link to switch accounts (gcloud handles that case server-side).

echo ""
echo "Test 8c: Step 1 still links when project linked to a different account"

T8C=$(mktemp -d -t aflowtest-XXXX)
mkdir -p "$T8C/bin"

cat > "$T8C/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$T8C/gcloud.log"
case "\$1 \$2" in
  "projects describe")
    if echo "\$*" | grep -q -- "--format"; then
      echo "ACTIVE"
    fi
    exit 0
    ;;
  "projects get-iam-policy") exit 0 ;;
  "billing projects")
    case "\$3" in
      describe)
        # Linked to a DIFFERENT billing account than BILLING_ACCOUNT_ID
        echo "billingAccounts/SOME-OTHER-ACCOUNT"
        exit 0
        ;;
      link) exit 0 ;;
    esac
    ;;
  "services enable") exit 1 ;;  # short-circuit past Step 2
  *) exit 0 ;;
esac
EOF
chmod +x "$T8C/bin/gcloud"

set +e
PATH="$T8C/bin:$PATH" \
  GCP_PROJECT_ID="af-other-billing" \
  BILLING_ACCOUNT_ID="FAKE-BILLING-ID" \
  "$SCRIPT" --create-project > "$T8C/stdout.log" 2>&1
set -e

if grep -q "link.*Billing account FAKE-BILLING-ID" "$T8C/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} [link] log line fired (different account)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[link] Billing account ...' when linked to a different account"
  cat "$T8C/stdout.log"
  FAIL=$((FAIL + 1))
fi

if grep -q "billing projects link af-other-billing" "$T8C/gcloud.log"; then
  echo -e "  ${GREEN}✓${NC} gcloud billing projects link was invoked"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected billing projects link to be called"
  cat "$T8C/gcloud.log"
  FAIL=$((FAIL + 1))
fi

# ── Test 9-11: Step 1.5 domain-restricted-sharing override ──────────────
#
# The script's Step 1.5 has TWO branches now (was three pre-2026-04-28).
# Decision logic: read the project's effective policy via `describe`.
#   - listPolicy.allValues == "ALLOW"  → [skip] (override already in place)
#   - anything else (empty, RESTRICT, error) → [override] applied
#
# Why "always apply when not ALLOW": the prior `org-policies list` probe
# missed org-inherited constraints that don't show up at the project's
# list view — workshop projects in an org with the constraint enforced
# at the org level were silently left without the override, then failed
# at the first external-domain IAM binding (e.g. Gmail user). The
# `set-policy` call is itself idempotent on a project, so applying it
# unconditionally on non-ALLOW is safe.
#
# Each branch is exercised below. Stubs inject controlled `describe`
# output and short-circuit before the real provisioning steps (we exit
# the stub gcloud non-zero on `services enable` so the script aborts
# before Step 2).

run_step1_5_test() {
  local label="$1"
  local describe_state="$2"   # "allow" | "empty" | "error"
  local tmp; tmp=$(mktemp -d -t aflowtest-XXXX)
  mkdir -p "$tmp/bin"

  cat > "$tmp/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$tmp/gcloud.log"
case "\$1 \$2" in
  "projects describe")
    # Existence check returns 1 (project doesn't exist) so the script
    # takes the create path — but we stub create to succeed.
    exit 1
    ;;
  "projects create") exit 0 ;;
  "billing projects") exit 0 ;;
  "resource-manager org-policies")
    case "\$3" in
      describe)
        # describe with --format='value(listPolicy.allValues)' returns:
        #   - "ALLOW" when override is in place
        #   - empty string when policy exists but allValues is unset
        #     (the org-inherited-but-empty-project-stub case from the
        #      2026-04-28 dry-run)
        #   - non-zero exit when no policy at all (which we treat the
        #     same as "not ALLOW" — apply override)
        case "$describe_state" in
          allow) echo "ALLOW"; exit 0 ;;
          empty) echo ""; exit 0 ;;
          error) exit 1 ;;
        esac
        ;;
      set-policy)
        cat >> "$tmp/set-policy-body.log"
        exit 0
        ;;
    esac
    ;;
  "services enable")
    # Short-circuit here so the test doesn't have to mock the rest.
    exit 1
    ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$tmp/bin/gcloud"

  set +e
  PATH="$tmp/bin:$PATH" \
    GCP_PROJECT_ID="af-policy-test" \
    BILLING_ACCOUNT_ID="FAKE" \
    "$SCRIPT" --create-project > "$tmp/stdout.log" 2>&1
  set -e

  echo "$tmp"
}

# Test 9: describe returns ALLOW → [skip], no set-policy call

echo ""
echo "Test 9: Step 1.5 skips when override already in place"

T9=$(run_step1_5_test "already-applied" "allow")

if grep -q "already in place" "$T9/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} skip message logged"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected 'already in place' in stdout"
  cat "$T9/stdout.log"
  FAIL=$((FAIL + 1))
fi

set_policy_calls=0
if [[ -f "$T9/gcloud.log" ]]; then
  set_policy_calls="$(grep -c 'set-policy' "$T9/gcloud.log" || true)"
fi
assert_eq "0" "$set_policy_calls" "set-policy NOT called when already in place"

# Test 10: describe returns empty (org-inherited-but-not-explicit) → override applied
# Reproduces the live bug observed during the 2026-04-28 dry-run.

echo ""
echo "Test 10: Step 1.5 applies override when project policy is empty (org-inherited case)"

T10=$(run_step1_5_test "empty-stub" "empty")

if grep -q "applying domain-restricted-sharing override" "$T10/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} override-applied message logged"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected 'applying domain-restricted-sharing override' in stdout"
  cat "$T10/stdout.log"
  FAIL=$((FAIL + 1))
fi

set_policy_calls=0
if [[ -f "$T10/gcloud.log" ]]; then
  set_policy_calls="$(grep -c 'set-policy' "$T10/gcloud.log" || true)"
fi
assert_eq "1" "$set_policy_calls" "set-policy called exactly once"

if [[ -f "$T10/set-policy-body.log" ]] && grep -q '"allValues":"ALLOW"' "$T10/set-policy-body.log"; then
  echo -e "  ${GREEN}✓${NC} set-policy body has allValues:ALLOW"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} set-policy body did not contain allValues:ALLOW"
  cat "$T10/set-policy-body.log" 2>/dev/null || echo "(body file not written)"
  FAIL=$((FAIL + 1))
fi

# Test 11: describe returns non-zero (no policy at project level) → override applied
# This used to be the "skip" path. Pre-fix, the script left these projects
# without an override and they failed the first Gmail-account IAM binding.

echo ""
echo "Test 11: Step 1.5 applies override when describe errors (no policy at project level)"

T11=$(run_step1_5_test "no-policy" "error")

if grep -q "applying domain-restricted-sharing override" "$T11/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} override-applied message logged (no longer silently skipped)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected 'applying ... override' in stdout — was the bug reintroduced?"
  cat "$T11/stdout.log"
  FAIL=$((FAIL + 1))
fi

set_policy_calls=0
if [[ -f "$T11/gcloud.log" ]]; then
  set_policy_calls="$(grep -c 'set-policy' "$T11/gcloud.log" || true)"
fi
assert_eq "1" "$set_policy_calls" "set-policy called exactly once even when describe errors"

# ── Test 12-14: Step 5.5 WIF setup ──────────────────────────────────────
#
# Step 5.5 has three branches:
#   - GITHUB_USERNAME unset                 → entire block skipped
#   - GITHUB_USERNAME set, WIF artifacts absent → pool + provider + binding created
#   - GITHUB_USERNAME set, WIF artifacts present → all three sub-steps log [skip]
#                                                  (binding still calls add-iam — idempotent)
#
# Stubs gcloud at PATH and short-circuits the script after Step 5.5 by
# exiting non-zero in code paths past the WIF block (Step 6 only runs
# when --with-sa-key is set; we don't pass it). The script naturally
# completes after Step 5.5 + the closing summary.

run_step5_5_test() {
  local wif_state="$1"   # "absent" | "present"
  local tmp; tmp=$(mktemp -d -t aflowtest-XXXX)
  mkdir -p "$tmp/bin"

  cat > "$tmp/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$tmp/gcloud.log"
case "\$1 \$2" in
  "projects describe")
    # Existence check (no --format) returns 1 so we take the create path.
    # Lifecycle check returns ACTIVE.
    # ProjectNumber check returns 12345.
    # Note: bash strips the single quotes around --format='value(...)'
    # before invoking gcloud, so the stub matches without quotes.
    if echo "\$*" | grep -q "projectNumber"; then
      echo "12345"
    elif echo "\$*" | grep -q "lifecycleState"; then
      echo "ACTIVE"
    else
      exit 1
    fi
    exit 0
    ;;
  "projects create"|"projects get-iam-policy"|"projects add-iam-policy-binding") exit 0 ;;
  "billing projects") exit 0 ;;
  "resource-manager org-policies")
    # Step 1.5: pretend constraint not enforced so we skip past quickly
    case "\$3" in
      describe) exit 1 ;;
      list)     exit 0 ;;
    esac
    ;;
  "services enable") exit 0 ;;
  "artifacts repositories")
    case "\$3" in
      describe) exit 1 ;;   # not exists -> create path
      create)   exit 0 ;;
    esac
    ;;
  "iam service-accounts")
    case "\$3" in
      describe) exit 1 ;;   # not exists -> create path
      create)   exit 0 ;;
      add-iam-policy-binding) exit 0 ;;   # used for SA roles + WIF binding
    esac
    ;;
  "iam workload-identity-pools")
    case "\$3" in
      describe)
        case "$wif_state" in
          present) exit 0 ;;
          *)       exit 1 ;;
        esac
        ;;
      create) exit 0 ;;
      providers)
        case "\$4" in
          describe)
            case "$wif_state" in
              present) exit 0 ;;
              *)       exit 1 ;;
            esac
            ;;
          create-oidc) exit 0 ;;
        esac
        ;;
    esac
    ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$tmp/bin/gcloud"

  # Args 2/3/4 are GITHUB_USERNAME / GITHUB_OWNER / GITHUB_REPO. Existing
  # callers pass only GITHUB_USERNAME (legacy alias path); new callers
  # can pass GITHUB_OWNER + GITHUB_REPO directly to test the modern path.
  # Use ${var-default} (no colon) so explicit empty stays empty.
  set +e
  PATH="$tmp/bin:$PATH" \
    GCP_PROJECT_ID="af-wif-test" \
    BILLING_ACCOUNT_ID="FAKE" \
    GITHUB_USERNAME="${2-}" \
    GITHUB_OWNER="${3-}" \
    GITHUB_REPO="${4-}" \
    "$SCRIPT" --create-project > "$tmp/stdout.log" 2>&1
  set -e

  echo "$tmp"
}

# Test 12: GITHUB_USERNAME unset → entire WIF block skipped

echo ""
echo "Test 12: Step 5.5 skipped when GITHUB_USERNAME unset"

T12=$(run_step5_5_test "absent" "")

if grep -q "WIF setup not requested" "$T12/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} skip message logged"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected 'WIF setup not requested' in stdout"
  cat "$T12/stdout.log"
  FAIL=$((FAIL + 1))
fi

wif_pool_calls=0
if [[ -f "$T12/gcloud.log" ]]; then
  wif_pool_calls="$(grep -c 'workload-identity-pools' "$T12/gcloud.log" || true)"
fi
assert_eq "0" "$wif_pool_calls" "no workload-identity-pools calls when GITHUB_USERNAME unset"

# Test 13: GITHUB_USERNAME set, WIF artifacts absent → pool + provider + binding created

echo ""
echo "Test 13: Step 5.5 creates pool + provider + binding when WIF absent"

T13=$(run_step5_5_test "absent" "alice-gh")

if grep -q "create.*WIF pool" "$T13/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} create-pool log line"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[create] WIF pool' in stdout"
  FAIL=$((FAIL + 1))
fi

if grep -q "create.*WIF provider" "$T13/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} create-provider log line"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[create] WIF provider' in stdout"
  FAIL=$((FAIL + 1))
fi

# create-oidc must include --attribute-condition. Google requires it; we
# learned that the hard way when a real-GCP run failed with INVALID_ARGUMENT.
if grep -q "providers create-oidc.*attribute-condition" "$T13/gcloud.log"; then
  echo -e "  ${GREEN}✓${NC} create-oidc invoked with --attribute-condition"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected --attribute-condition on create-oidc call; got:"
  grep "create-oidc" "$T13/gcloud.log" || echo "(no create-oidc call found)"
  FAIL=$((FAIL + 1))
fi

if grep -q "alice-gh/agile-flow-gcp" "$T13/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} binding log names alice-gh/agile-flow-gcp (default WIF_REPO)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected binding log to mention alice-gh/agile-flow-gcp"
  cat "$T13/stdout.log"
  FAIL=$((FAIL + 1))
fi

# Both WIF roles must be bound. workloadIdentityUser alone leaves the deploy
# step unable to mint access tokens for docker push. We learned that the
# hard way during smoke 2026-04-28.
if grep -q "\[bind\] roles/iam.workloadIdentityUser <- alice-gh/agile-flow-gcp" "$T13/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} workloadIdentityUser binding logged"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[bind] roles/iam.workloadIdentityUser <- alice-gh/agile-flow-gcp'"
  FAIL=$((FAIL + 1))
fi
if grep -q "\[bind\] roles/iam.serviceAccountTokenCreator <- alice-gh/agile-flow-gcp" "$T13/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} serviceAccountTokenCreator binding logged"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[bind] roles/iam.serviceAccountTokenCreator <- alice-gh/agile-flow-gcp'"
  FAIL=$((FAIL + 1))
fi

# Final summary line should print the WIF provider resource path with project number 12345
if grep -q "GCP_WORKLOAD_IDENTITY_PROVIDER = projects/12345/locations/global/workloadIdentityPools/github/providers/github" "$T13/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} final summary prints concrete WIF provider resource"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected concrete WIF provider in final summary; got:"
  grep "WORKLOAD_IDENTITY" "$T13/stdout.log" || echo "(no WORKLOAD_IDENTITY line found)"
  FAIL=$((FAIL + 1))
fi

# Test 14: GITHUB_USERNAME set, WIF artifacts present → idempotent skip

echo ""
echo "Test 14: Step 5.5 idempotent when WIF artifacts already present"

T14=$(run_step5_5_test "present" "alice-gh")

if grep -q "skip.*WIF pool" "$T14/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} skip-pool log line"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[skip] WIF pool' in stdout"
  FAIL=$((FAIL + 1))
fi

if grep -q "skip.*WIF provider" "$T14/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} skip-provider log line"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[skip] WIF provider' in stdout"
  FAIL=$((FAIL + 1))
fi

# Binding step is always called (it's idempotent at the gcloud level)
if grep -q "bind.*workloadIdentityUser" "$T14/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} binding step still ran (idempotent)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected binding step to log [bind]"
  FAIL=$((FAIL + 1))
fi

# ── Test 14b: GITHUB_OWNER + GITHUB_REPO (org-fork path) ────────────────
# Verifies the new env-var pair from #40. Owner is acme (an org); repo
# name diverges from `agile-flow-gcp` because the participant renamed it.

echo ""
echo "Test 14b: Step 5.5 honors GITHUB_OWNER + GITHUB_REPO"

# arg order: state, GITHUB_USERNAME, GITHUB_OWNER, GITHUB_REPO
T14B=$(run_step5_5_test "absent" "" "acme" "widget-shop")

if grep -q "bind.*<- acme/widget-shop" "$T14B/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} binding member is acme/widget-shop (not <user>/agile-flow-gcp)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[bind] ... <- acme/widget-shop' in stdout"
  cat "$T14B/stdout.log"
  FAIL=$((FAIL + 1))
fi

# ── Test 14c: WIF skipped when neither GITHUB_OWNER nor GITHUB_USERNAME set ──

echo ""
echo "Test 14c: Step 5.5 skipped when both GITHUB_OWNER and GITHUB_USERNAME unset"

T14C=$(run_step5_5_test "absent" "" "" "")

if grep -q "skip.*WIF setup not requested" "$T14C/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} skip message logged"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[skip] WIF setup not requested' in stdout"
  cat "$T14C/stdout.log"
  FAIL=$((FAIL + 1))
fi

# ── Test 14d: Step 5.5c WIF binding retries SA-IAM propagation lag ──────
# Reproduces the live bug observed during the 2026-04-28 dry-run: a
# freshly-created deployer SA returns IAM_PERMISSION_DENIED on
# `setIamPolicy` for a few seconds while the IAM control plane catches
# up. Without retry wrapping, Step 5.5c fails the wrapper mid-row.
#
# The stub fails the FIRST `service-accounts add-iam-policy-binding`
# with the exact transient signature the retry helper classifies, then
# succeeds on subsequent attempts. We assert that (a) the script exits
# 0, (b) the binding step retries, and (c) the binding ultimately
# succeeds.

echo ""
echo "Test 14d: Step 5.5c retries on SA-IAM propagation lag"

T14D=$(mktemp -d -t aflowtest-XXXX)
mkdir -p "$T14D/bin"
echo 0 > "$T14D/bind_attempts"

cat > "$T14D/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$T14D/gcloud.log"
case "\$1 \$2" in
  "projects describe")
    if echo "\$*" | grep -q "projectNumber"; then
      echo "12345"
    elif echo "\$*" | grep -q "lifecycleState"; then
      echo "ACTIVE"
    else
      exit 1
    fi
    exit 0
    ;;
  "projects create"|"projects get-iam-policy"|"projects add-iam-policy-binding") exit 0 ;;
  "billing projects") exit 0 ;;
  "resource-manager org-policies")
    case "\$3" in
      describe) exit 1 ;;
      list)     exit 0 ;;
    esac
    ;;
  "services enable") exit 0 ;;
  "artifacts repositories")
    case "\$3" in
      describe) exit 1 ;;
      create)   exit 0 ;;
    esac
    ;;
  "iam service-accounts")
    case "\$3" in
      describe) exit 1 ;;
      create)   exit 0 ;;
      add-iam-policy-binding)
        # Distinguish the project-level binding from the SA-level WIF
        # bindings: the WIF ones target the SA email and reference
        # principalSet:// in --member.
        if echo "\$*" | grep -q "principalSet://"; then
          n=\$(<"$T14D/bind_attempts")
          n=\$((n + 1))
          echo \$n > "$T14D/bind_attempts"
          if (( n == 1 )); then
            echo "ERROR: (gcloud.iam.service-accounts.add-iam-policy-binding) PERMISSION_DENIED: Permission 'iam.serviceAccounts.setIamPolicy' denied on resource (or it may not exist)." >&2
            echo "domain: iam.googleapis.com" >&2
            echo "reason: IAM_PERMISSION_DENIED" >&2
            exit 1
          fi
          exit 0
        fi
        exit 0
        ;;
    esac
    ;;
  "iam workload-identity-pools")
    case "\$3" in
      describe) exit 1 ;;        # absent — create path
      create)   exit 0 ;;
      providers)
        case "\$4" in
          describe)    exit 1 ;;
          create-oidc) exit 0 ;;
        esac
        ;;
    esac
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$T14D/bin/gcloud"

# Speed up the retry helper for tests
set +e
PATH="$T14D/bin:$PATH" \
  RETRY_MAX_ATTEMPTS=4 \
  RETRY_MAX_SLEEP=1 \
  GCP_PROJECT_ID="af-wif-retry-test" \
  BILLING_ACCOUNT_ID="FAKE" \
  GITHUB_OWNER="alice-gh" \
  GITHUB_REPO="agile-flow-gcp" \
  "$SCRIPT" --create-project > "$T14D/stdout.log" 2>&1
ec=$?
set -e

assert_eq "0" "$ec" "wrapper succeeds despite first WIF binding failure"

# The retry log should show a transient classification at least once.
if grep -q '\[retry .*wif bind' "$T14D/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} retry log line present for WIF binding"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[retry .../... wif bind ...]' in stdout — was the binding wrapped in retry_eventual_consistency?"
  cat "$T14D/stdout.log"
  FAIL=$((FAIL + 1))
fi

# Bind attempts: exactly 2 (1 fail + 1 success) for the FIRST WIF role.
# The second WIF role hits a fresh counter — but our stub increments
# the same counter for both WIF bindings. Resulting total: at minimum 2.
attempts="$(cat "$T14D/bind_attempts")"
if (( attempts >= 2 )); then
  echo -e "  ${GREEN}✓${NC} binding retried (saw $attempts WIF binding calls; ≥ 2 means retry happened)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected ≥ 2 WIF binding attempts; got $attempts"
  FAIL=$((FAIL + 1))
fi

# ── Test 15-17: Step 5.7 Neon branch + database-url Secret Manager ──────
#
# Step 5.7 has three branches:
#   - NEON_API_KEY/PROJECT_ID/BRANCH_NAME unset → skipped
#   - branch absent in Neon → POST /branches returns 201; secret created
#   - branch already exists → POST returns 409; lookup existing; secret
#     versions-add (when value differs) or no-op (when same)
#
# Stubs both curl (Neon API) and gcloud (Secret Manager) at PATH.

run_step5_7_test() {
  local neon_state="$1"   # "skip" | "absent" | "exists" | "exists-same-value"
  local tmp; tmp=$(mktemp -d -t aflowtest-XXXX)
  mkdir -p "$tmp/bin"

  # Fake Neon API responses keyed by the URL path.
  cat > "$tmp/bin/curl" <<EOF
#!/usr/bin/env bash
# Capture full args (each on its own line for grep'ability)
printf '%s\n' "\$@" >> "$tmp/curl.log"

# Find the URL — last positional arg containing /api/v2.
url=""
for a in "\$@"; do
  case "\$a" in
    *console.neon.tech/api/v2*) url="\$a" ;;
  esac
done

# --output FILE writes the body to FILE; --write-out '%{http_code}' prints
# the HTTP code on stdout. Detect both.
out_file=""
write_out=""
prev=""
for a in "\$@"; do
  case "\$prev" in
    --output)      out_file="\$a" ;;
    --write-out)   write_out="\$a" ;;
  esac
  prev="\$a"
done

# Method: was -X POST passed?
is_post=false
for a in "\$@"; do
  if [[ "\$a" == POST ]]; then is_post=true; fi
done

emit() {
  # If --output present, write body there. Otherwise body to stdout.
  if [[ -n "\$out_file" ]]; then
    printf '%s' "\$1" > "\$out_file"
  else
    printf '%s' "\$1"
  fi
  # If --write-out present, print HTTP code on stdout.
  if [[ -n "\$write_out" ]]; then
    printf '%s' "\$2"
  fi
}

case "\$url" in
  *"/branches?"*|*"/branches "*)
    # GET /branches
    emit '{"branches":[{"id":"br-main","name":"main","default":true}]}' "200"
    exit 0
    ;;
  *"/branches"*)
    if \$is_post; then
      # POST /branches  (create)
      case "$neon_state" in
        absent)
          emit '{"branch":{"id":"br-alice","name":"alice"}}' "201"
          exit 0
          ;;
        exists|exists-same-value)
          emit '{"error":"branch already exists"}' "409"
          exit 0
          ;;
      esac
    else
      # GET /branches (no query, the re-fetch path)
      emit '{"branches":[{"id":"br-main","name":"main","default":true},{"id":"br-alice","name":"alice"}]}' "200"
      exit 0
    fi
    ;;
  *"/connection_uri"*)
    emit '{"uri":"postgresql://user:pass@ep-xxx-pooler.us-east-2.aws.neon.tech/neondb?sslmode=require"}' "200"
    exit 0
    ;;
  *)
    emit '{"error":"unhandled in stub"}' "500"
    exit 1
    ;;
esac
EOF
  chmod +x "$tmp/bin/curl"

  # Fake gcloud — combines the Step 5.5 stub plus secrets handling.
  cat > "$tmp/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$tmp/gcloud.log"
case "\$1 \$2" in
  "projects describe")
    if echo "\$*" | grep -q "projectNumber"; then
      echo "12345"
    elif echo "\$*" | grep -q "lifecycleState"; then
      echo "ACTIVE"
    else
      exit 1
    fi
    exit 0
    ;;
  "projects create"|"projects get-iam-policy"|"projects add-iam-policy-binding") exit 0 ;;
  "billing projects") exit 0 ;;
  "resource-manager org-policies")
    case "\$3" in
      describe) exit 1 ;;
      list)     exit 0 ;;
    esac
    ;;
  "services enable") exit 0 ;;
  "artifacts repositories")
    case "\$3" in
      describe) exit 1 ;;
      create)   exit 0 ;;
    esac
    ;;
  "iam service-accounts")
    case "\$3" in
      describe) exit 1 ;;
      create)   exit 0 ;;
      add-iam-policy-binding) exit 0 ;;
    esac
    ;;
  "iam workload-identity-pools") exit 1 ;;  # skip WIF in 5.7 tests
  "secrets describe")
    case "$neon_state" in
      exists-same-value) exit 0 ;;   # secret exists
      *)                 exit 1 ;;   # secret does not exist
    esac
    ;;
  "secrets versions")
    # versions access latest — return what's currently in the secret
    case "$neon_state" in
      exists-same-value)
        echo "postgresql://user:pass@ep-xxx-pooler.us-east-2.aws.neon.tech/neondb?sslmode=require"
        ;;
    esac
    exit 0
    ;;
  "secrets create"|"secrets add-iam-policy-binding") exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$tmp/bin/gcloud"

  # Use ${var-default} (no colon) so an explicit empty string passed by
  # the caller — like test 15's "" for NEON_API_KEY — stays empty.
  # ${var:-default} would substitute on empty, which we don't want here.
  # 5th arg is NEON_FORCE_SHARED_PARENT (default false; pass "true" for
  # collision-reuse tests in the post-#90 world).
  set +e
  PATH="$tmp/bin:$PATH" \
    GCP_PROJECT_ID="af-step57-test" \
    BILLING_ACCOUNT_ID="FAKE" \
    NEON_API_KEY="${2-fake-api-key}" \
    NEON_PROJECT_ID="${3-fake-project-id}" \
    NEON_BRANCH_NAME="${4-alice}" \
    NEON_FORCE_SHARED_PARENT="${5-false}" \
    "$SCRIPT" --create-project > "$tmp/stdout.log" 2>&1
  set -e

  echo "$tmp"
}

# Test 15: NEON_API_KEY unset → step is skipped

echo ""
echo "Test 15: Step 5.7 skipped when NEON_API_KEY unset"

T15=$(run_step5_7_test "skip" "" "fake-project-id" "alice")

if grep -q "skip.*NEON_API_KEY unset" "$T15/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} skip message logged"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[skip]' message about NEON_API_KEY"
  cat "$T15/stdout.log"
  FAIL=$((FAIL + 1))
fi

# When skipped, no curl calls to the Neon API should have happened
neon_calls=0
if [[ -f "$T15/curl.log" ]]; then
  neon_calls="$(grep -c "console.neon.tech" "$T15/curl.log" || true)"
fi
assert_eq "0" "$neon_calls" "no Neon API calls when skipped"

# Test 16: NEON_*  set, branch absent → branch created, secret created

echo ""
echo "Test 16: Step 5.7 creates branch + database-url secret when absent"

T16=$(run_step5_7_test "absent")

if grep -q "branch created" "$T16/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} branch-created log line"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected 'branch created' in stdout"
  FAIL=$((FAIL + 1))
fi

if grep -q "create.*database-url secret" "$T16/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} secret-create log line"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[create] database-url secret' in stdout"
  FAIL=$((FAIL + 1))
fi

# Verify gcloud secrets create was called (not versions add)
if grep -q "secrets create database-url" "$T16/gcloud.log"; then
  echo -e "  ${GREEN}✓${NC} gcloud secrets create invoked"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected 'gcloud secrets create database-url' in gcloud.log"
  FAIL=$((FAIL + 1))
fi

# IAM binding granted
if grep -q "secrets add-iam-policy-binding database-url" "$T16/gcloud.log"; then
  echo -e "  ${GREEN}✓${NC} per-secret IAM binding granted"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected 'secrets add-iam-policy-binding database-url' in gcloud.log"
  FAIL=$((FAIL + 1))
fi

# Test 17: branch exists, secret exists with SAME value → no-op skip
# Requires NEON_FORCE_SHARED_PARENT=true (since #90) — the realistic
# trigger for this code path is re-running the same cohort against an
# already-populated Neon project, which is the explicit-share case.

echo ""
echo "Test 17: Step 5.7 idempotent when branch + secret already current (with --force-shared-parent)"

T17=$(run_step5_7_test "exists-same-value" "fake-api-key" "fake-project-id" "alice" "true")

if grep -q "branch.*alice.*already exists.*reusing per NEON_FORCE_SHARED_PARENT" "$T17/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} branch-already-exists log line names the force flag"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected 'branch already exists; reusing per NEON_FORCE_SHARED_PARENT' in stdout"
  cat "$T17/stdout.log"
  FAIL=$((FAIL + 1))
fi

if grep -q "skip.*database-url secret already current" "$T17/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} secret-already-current log line"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[skip] database-url secret already current' in stdout"
  FAIL=$((FAIL + 1))
fi

# Verify gcloud secrets create was NOT called (since we used versions access path)
if ! grep -q "secrets create database-url" "$T17/gcloud.log"; then
  echo -e "  ${GREEN}✓${NC} gcloud secrets create NOT called (idempotent)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} secrets create should NOT have been called when secret is current"
  FAIL=$((FAIL + 1))
fi

# ── Test 18-21: Step 5.6 budget cap ─────────────────────────────────────
#
# Step 5.6 has three branches:
#   - BUDGET_CAP_USD unset → silently skipped, no billing calls
#   - BUDGET_CAP_USD set, no existing budget → create called once
#   - BUDGET_CAP_USD set, budget already exists (by display-name) → skip
#
# The harness stubs the full gcloud surface to keep the script running
# through Step 6 without erroring out on unrelated commands.

run_step5_6_test() {
  local budget_state="$1"   # "skip-unset" | "absent" | "exists"
  local budget_amount="${2-25}"
  local tmp; tmp=$(mktemp -d -t aflowtest-XXXX)
  mkdir -p "$tmp/bin"

  cat > "$tmp/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$tmp/gcloud.log"
case "\$1 \$2" in
  "projects describe")
    if echo "\$*" | grep -q "projectNumber"; then
      echo "12345"
    elif echo "\$*" | grep -q "lifecycleState"; then
      echo "ACTIVE"
    else
      exit 1
    fi
    exit 0
    ;;
  "projects create"|"projects get-iam-policy"|"projects add-iam-policy-binding") exit 0 ;;
  "billing projects") exit 0 ;;
  "billing accounts") exit 0 ;;
  "billing budgets")
    case "\$3" in
      list)
        # Emulate display-name filter by branching on the canned state.
        case "$budget_state" in
          exists) echo "billingAccounts/FAKE/budgets/abcdef" ;;
          permission-denied)
            echo "ERROR: (gcloud.billing.budgets.list) [teddy@example.com] does not have permission to access billingAccounts instance [FAKE] (or it may not exist): missing roles/billing.costsManager" >&2
            exit 1
            ;;
          *)      ;;  # absent → empty output
        esac
        exit 0
        ;;
      create) exit 0 ;;
    esac
    ;;
  "resource-manager org-policies")
    case "\$3" in
      describe) exit 1 ;;
      list)     exit 0 ;;
    esac
    ;;
  "services enable") exit 0 ;;
  "artifacts repositories")
    case "\$3" in
      describe) exit 1 ;;
      create)   exit 0 ;;
    esac
    ;;
  "iam service-accounts")
    case "\$3" in
      describe) exit 1 ;;
      create)   exit 0 ;;
      add-iam-policy-binding) exit 0 ;;
    esac
    ;;
  "iam workload-identity-pools") exit 1 ;;  # skip WIF
  "secrets describe") exit 1 ;;             # skip Neon (no NEON_API_KEY anyway)
  *) exit 0 ;;
esac
EOF
  chmod +x "$tmp/bin/gcloud"

  set +e
  PATH="$tmp/bin:$PATH" \
    GCP_PROJECT_ID="af-step56-test" \
    BILLING_ACCOUNT_ID="FAKE" \
    BUDGET_CAP_USD="${budget_amount-}" \
    "$SCRIPT" --create-project > "$tmp/stdout.log" 2>&1
  set -e

  echo "$tmp"
}

# Test 18: BUDGET_CAP_USD unset → step skipped, no billing calls

echo ""
echo "Test 18: Step 5.6 skipped when BUDGET_CAP_USD unset"

T18=$(run_step5_6_test "skip-unset" "")

if grep -q "skip.*budget cap.*BUDGET_CAP_USD unset" "$T18/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} skip message logged"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[skip] budget cap (BUDGET_CAP_USD unset)' in stdout"
  cat "$T18/stdout.log"
  FAIL=$((FAIL + 1))
fi

budget_calls=0
if [[ -f "$T18/gcloud.log" ]]; then
  budget_calls="$(grep -c 'billing budgets' "$T18/gcloud.log" || true)"
fi
assert_eq "0" "$budget_calls" "no billing budgets calls when BUDGET_CAP_USD unset"

# Test 19: BUDGET_CAP_USD=25, no existing budget → create called

echo ""
echo "Test 19: Step 5.6 creates budget when BUDGET_CAP_USD set and absent"

T19=$(run_step5_6_test "absent" "25")

if grep -q "create.*af-workshop-cap-af-step56-test.*\$25 USD" "$T19/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} create log names display-name + amount"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[create] budget af-workshop-cap-... \$25 USD' in stdout"
  cat "$T19/stdout.log"
  FAIL=$((FAIL + 1))
fi

if grep -q "billing budgets create" "$T19/gcloud.log"; then
  echo -e "  ${GREEN}✓${NC} gcloud billing budgets create invoked"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected 'billing budgets create' in gcloud.log"
  FAIL=$((FAIL + 1))
fi

# Critical scoping assertion: budget MUST filter on the project, not the
# whole billing account. Otherwise one participant's spend trips everyone.
if grep -q "filter-projects=projects/12345" "$T19/gcloud.log"; then
  echo -e "  ${GREEN}✓${NC} budget scoped to project (--filter-projects=projects/12345)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected --filter-projects=projects/12345 on budgets create"
  grep "budgets create" "$T19/gcloud.log" || echo "(no create call found)"
  FAIL=$((FAIL + 1))
fi

# All four threshold rules must be present (50, 90, 100 current + 100 forecasted).
# Each gcloud invocation lands on one line in gcloud.log, so grep -c counts
# invocations, not flag occurrences. Use -o to count matches.
threshold_count="$(grep -o 'threshold-rule=percent=' "$T19/gcloud.log" | wc -l | tr -d '[:space:]')"
assert_eq "4" "$threshold_count" "four --threshold-rule flags present (50/90/100/100-forecast)"

# Test 20: BUDGET_CAP_USD=25, budget already exists → skip (no create)

echo ""
echo "Test 20: Step 5.6 idempotent when budget already exists"

T20=$(run_step5_6_test "exists" "25")

if grep -q "skip.*af-workshop-cap-af-step56-test.*already exists" "$T20/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} skip-existing log line"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[skip] budget ... already exists' in stdout"
  cat "$T20/stdout.log"
  FAIL=$((FAIL + 1))
fi

if ! grep -q "billing budgets create" "$T20/gcloud.log"; then
  echo -e "  ${GREEN}✓${NC} gcloud billing budgets create NOT invoked (idempotent)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} budgets create should NOT have run when budget already exists"
  FAIL=$((FAIL + 1))
fi

# Test 20b: budget list fails (permission denied) → surface the error,
# don't swallow it. This is the silent-failure path that bit the dry-run
# on 2026-04-28 — `2>/dev/null | head` plus `set -euo pipefail` killed
# the wrapper mid-row-1 with no diagnostic, leaving the remaining roster
# rows un-provisioned and `roster-output.csv` empty.

echo ""
echo "Test 20b: Step 5.6 surfaces gcloud billing list errors instead of swallowing them"

T20B=$(run_step5_6_test "permission-denied" "25")

if grep -q "gcloud billing budgets list failed" "$T20B/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} explicit error message logged"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected 'gcloud billing budgets list failed' in stderr"
  cat "$T20B/stdout.log"
  FAIL=$((FAIL + 1))
fi

if grep -q "roles/billing.costsManager" "$T20B/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} error names the missing role"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected error to mention roles/billing.costsManager"
  FAIL=$((FAIL + 1))
fi

# The original gcloud stderr must reach the user, not be swallowed.
if grep -q "does not have permission to access billingAccounts" "$T20B/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} underlying gcloud error is visible to the user"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected the underlying gcloud error to be relayed"
  FAIL=$((FAIL + 1))
fi

# Test 21: invalid BUDGET_CAP_USD → exit 1 with clear error

echo ""
echo "Test 21: Step 5.6 rejects non-numeric BUDGET_CAP_USD"

T21=$(run_step5_6_test "absent" "twenty-five")
ec=$?

if grep -q "BUDGET_CAP_USD must be a positive number" "$T21/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} clear error on bad amount"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected error mentioning 'must be a positive number'"
  cat "$T21/stdout.log"
  FAIL=$((FAIL + 1))
fi

# ── Test 22-23: Step 5.8 Cloud Run service pre-create ───────────────────
#
# Step 5.8 has two branches:
#   - service does not exist  → `gcloud run deploy` with hello placeholder
#   - service already exists  → [skip] log line, no deploy call
#
# The harness stubs the full gcloud surface so the script runs through
# Step 6 without erroring out elsewhere.

run_step5_8_test() {
  local service_state="$1"   # "absent" | "present"
  local tmp; tmp=$(mktemp -d -t aflowtest-XXXX)
  mkdir -p "$tmp/bin"

  cat > "$tmp/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$tmp/gcloud.log"
case "\$1 \$2" in
  "projects describe")
    if echo "\$*" | grep -q "projectNumber"; then
      echo "12345"
    elif echo "\$*" | grep -q "lifecycleState"; then
      echo "ACTIVE"
    else
      exit 1
    fi
    exit 0
    ;;
  "projects create"|"projects get-iam-policy"|"projects add-iam-policy-binding") exit 0 ;;
  "billing projects") exit 0 ;;
  "billing accounts") exit 0 ;;
  "resource-manager org-policies")
    case "\$3" in
      describe) exit 1 ;;  # no policy at project level → apply override
      set-policy) exit 0 ;;
    esac
    ;;
  "services enable") exit 0 ;;
  "artifacts repositories")
    case "\$3" in
      describe) exit 1 ;;
      create)   exit 0 ;;
    esac
    ;;
  "iam service-accounts")
    case "\$3" in
      describe) exit 1 ;;
      create)   exit 0 ;;
      add-iam-policy-binding) exit 0 ;;
    esac
    ;;
  "iam workload-identity-pools") exit 1 ;;  # skip WIF
  "secrets describe") exit 1 ;;             # skip Neon (no NEON_API_KEY)
  "run services")
    # describe is what Step 5.8 calls to detect existence
    case "\$3" in
      describe)
        case "$service_state" in
          present) exit 0 ;;   # service exists → skip path
          absent)  exit 1 ;;   # service missing → create path
        esac
        ;;
    esac
    ;;
  "run deploy") exit 0 ;;       # placeholder deploy succeeds
  *) exit 0 ;;
esac
EOF
  chmod +x "$tmp/bin/gcloud"

  set +e
  PATH="$tmp/bin:$PATH" \
    GCP_PROJECT_ID="af-step58-test" \
    BILLING_ACCOUNT_ID="FAKE" \
    "$SCRIPT" --create-project > "$tmp/stdout.log" 2>&1
  set -e

  echo "$tmp"
}

# Test 22: service absent → placeholder deploy invoked

echo ""
echo "Test 22: Step 5.8 pre-creates Cloud Run service when absent"

T22=$(run_step5_8_test "absent")

if grep -q "create.*Cloud Run service.*agile-flow-app.*placeholder" "$T22/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} create log line names service + placeholder"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[create] Cloud Run service ... placeholder' in stdout"
  cat "$T22/stdout.log"
  FAIL=$((FAIL + 1))
fi

if grep -q "run deploy agile-flow-app" "$T22/gcloud.log"; then
  echo -e "  ${GREEN}✓${NC} gcloud run deploy invoked"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected 'run deploy agile-flow-app' in gcloud.log"
  FAIL=$((FAIL + 1))
fi

# Critical: must use Google's hello-world placeholder image, not a real image.
if grep -q "image=us-docker.pkg.dev/cloudrun/container/hello" "$T22/gcloud.log"; then
  echo -e "  ${GREEN}✓${NC} placeholder image is the official Google hello-world"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected --image=us-docker.pkg.dev/cloudrun/container/hello"
  grep "run deploy" "$T22/gcloud.log" || echo "(no run deploy call found)"
  FAIL=$((FAIL + 1))
fi

# Critical: --service-account must pin to deployer SA so first real deploy
# doesn't drift the runtime SA from the placeholder revision.
if grep -q "service-account=deployer@af-step58-test.iam.gserviceaccount.com" "$T22/gcloud.log"; then
  echo -e "  ${GREEN}✓${NC} --service-account pinned to deployer SA"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected --service-account=deployer@... in run deploy call"
  FAIL=$((FAIL + 1))
fi

# Test 23: service present → [skip], no deploy call

echo ""
echo "Test 23: Step 5.8 idempotent when service already exists"

T23=$(run_step5_8_test "present")

if grep -q "skip.*Cloud Run service.*agile-flow-app.*already exists" "$T23/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} skip-existing log line"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[skip] Cloud Run service ... already exists' in stdout"
  cat "$T23/stdout.log"
  FAIL=$((FAIL + 1))
fi

if ! grep -q "run deploy" "$T23/gcloud.log"; then
  echo -e "  ${GREEN}✓${NC} gcloud run deploy NOT invoked (idempotent)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} run deploy should NOT have been called when service exists"
  FAIL=$((FAIL + 1))
fi

# ── Test 24-26: Step 7 GitHub secret push ───────────────────────────────
#
# Step 7 has three branches:
#   - GITHUB_REPOSITORY set + gh on PATH → secrets pushed via `gh secret set`
#   - GITHUB_REPOSITORY unset            → step skipped silently, footer
#                                          falls back to printed instructions
#   - GITHUB_REPOSITORY set, gh missing  → step logs hint, footer falls back
#
# CRITICAL invariant: secret values must NEVER appear in stdout/stderr.
# The test asserts this by checking the captured output for the literal
# WIF provider string after a successful push.

run_step7_test() {
  local mode="$1"   # "gh-present" | "gh-missing" | "no-repo"
  local tmp; tmp=$(mktemp -d -t aflowtest-XXXX)
  mkdir -p "$tmp/bin"

  # Common gcloud stub (same surface as Test 22-23)
  cat > "$tmp/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$tmp/gcloud.log"
case "\$1 \$2" in
  "projects describe")
    if echo "\$*" | grep -q "projectNumber"; then
      echo "12345"
    elif echo "\$*" | grep -q "lifecycleState"; then
      echo "ACTIVE"
    else
      exit 1
    fi
    exit 0
    ;;
  "projects create"|"projects get-iam-policy"|"projects add-iam-policy-binding") exit 0 ;;
  "billing projects") exit 0 ;;
  "billing accounts") exit 0 ;;
  "resource-manager org-policies")
    case "\$3" in
      describe) exit 1 ;;
      set-policy) exit 0 ;;
    esac
    ;;
  "services enable") exit 0 ;;
  "artifacts repositories")
    case "\$3" in
      describe) exit 1 ;;
      create)   exit 0 ;;
    esac
    ;;
  "iam service-accounts")
    case "\$3" in
      describe) exit 1 ;;
      create)   exit 0 ;;
      add-iam-policy-binding) exit 0 ;;
    esac
    ;;
  "iam workload-identity-pools")
    case "\$3" in
      describe)
        # Pool-level describe in 5.5a → make it absent so the create path runs
        exit 1
        ;;
      create) exit 0 ;;
      providers)
        case "\$4" in
          describe)    exit 1 ;;
          create-oidc) exit 0 ;;
        esac
        ;;
    esac
    ;;
  "secrets describe") exit 1 ;;
  "run services") exit 0 ;;     # service exists → skip Step 5.8
  "run deploy") exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$tmp/bin/gcloud"

  # gh stub: only present in "gh-present" mode. Logs the call args
  # (excluding --body's value, which would defeat the no-stdout invariant
  # — we capture name + repo only).
  if [[ "$mode" == "gh-present" ]]; then
    cat > "$tmp/bin/gh" <<EOF
#!/usr/bin/env bash
# Capture argv minus any --body value (the value-after-flag pattern).
# Distinguish secret name (positional) from --body value (flag-value).
out=()
prev=""
for a in "\$@"; do
  if [[ "\$prev" == "--body" ]]; then
    out+=("--body=<redacted>")
  else
    out+=("\$a")
  fi
  prev="\$a"
done
echo "gh \${out[*]}" >> "$tmp/gh.log"
exit 0
EOF
    chmod +x "$tmp/bin/gh"
  fi

  # PATH controls whether gh is "installed". When mode is gh-missing or
  # no-repo, we exclude the gh stub from PATH so `command -v gh` returns
  # the system gh (or nothing). To force "gh missing" we put a sentinel
  # directory at the front of PATH that has *only* the gcloud stub, then
  # prepend a wrapper that hides any system gh by overshadowing it.
  #
  # Real PATH still appended so /usr/bin/env bash, head, grep, etc. work.
  local PATH_TO_USE
  if [[ "$mode" == "gh-present" ]]; then
    PATH_TO_USE="$tmp/bin:$PATH"
  else
    # Build a sub-dir with only gcloud (no gh) so the test gh stub is
    # NOT visible. We can't truly hide a system-installed gh from
    # `command -v`, but the script's branch is gated on
    # `command -v gh >/dev/null` — so we override `command` is too
    # invasive. Instead we drop a `gh` shim that prints to a sentinel
    # log and exits 127, plus we explicitly pre-test that the stub
    # would never run (Test 25/26 assertions check for the FALLBACK
    # log, which only fires when the script took the gh-missing path
    # OR the no-repo path).
    #
    # Simpler: install a `gh` shim that echoes the failure marker, then
    # use the marker to detect if `gh` was found. But the script uses
    # `command -v gh >/dev/null 2>&1` which returns true if any gh is
    # on PATH. To force false, we use a PATH that contains NO gh stub
    # at all — but the system might have gh on the real PATH.
    #
    # Practical approach: skip the test if the harness can't truly
    # hide gh. Detect by `command -v gh` BEFORE running.
    mkdir -p "$tmp/bin-no-gh"
    cp "$tmp/bin/gcloud" "$tmp/bin-no-gh/"
    PATH_TO_USE="$tmp/bin-no-gh:/usr/bin:/bin"
  fi

  local repo_env=""
  if [[ "$mode" != "no-repo" ]]; then
    repo_env="acme/widget-shop"
  fi

  set +e
  PATH="$PATH_TO_USE" \
    GCP_PROJECT_ID="af-step7-test" \
    BILLING_ACCOUNT_ID="FAKE" \
    GITHUB_OWNER="acme" \
    GITHUB_REPO="widget-shop" \
    GITHUB_REPOSITORY="$repo_env" \
    "$SCRIPT" --create-project > "$tmp/stdout.log" 2>&1
  set -e

  echo "$tmp"
}

# Test 24: gh present + GITHUB_REPOSITORY set → secrets pushed

echo ""
echo "Test 24: Step 7 pushes secrets when gh + GITHUB_REPOSITORY are set"

T24=$(run_step7_test "gh-present")

if grep -q "secrets.*Pushing GitHub Actions secrets to acme/widget-shop" "$T24/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} push-banner log line"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[secrets] Pushing GitHub Actions secrets to acme/widget-shop'"
  cat "$T24/stdout.log"
  FAIL=$((FAIL + 1))
fi

# Verify each expected secret was pushed (gh.log captures name + redacted body)
for secret_name in GCP_PROJECT_ID GCP_SERVICE_ACCOUNT GCP_WORKLOAD_IDENTITY_PROVIDER; do
  if grep -q "secret set $secret_name --repo acme/widget-shop" "$T24/gh.log"; then
    echo -e "  ${GREEN}✓${NC} $secret_name pushed via gh secret set"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC} expected gh secret set for $secret_name"
    cat "$T24/gh.log"
    FAIL=$((FAIL + 1))
  fi
done

# When GH_SECRETS_PUSHED=true, the footer should NOT print the manual values.
# Specifically the WIF provider resource path should not appear.
if ! grep -q "projects/12345/locations/global/workloadIdentityPools/github/providers/github" "$T24/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} footer suppresses manual values when secrets pushed"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} footer leaked WIF provider value when it shouldn't have"
  FAIL=$((FAIL + 1))
fi

# Test 25: gh missing → fallback hint, manual values printed

echo ""
echo "Test 25: Step 7 falls back to printed values when gh CLI is missing"

T25=$(run_step7_test "gh-missing")

if grep -q "secrets.*gh CLI not on PATH" "$T25/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} gh-missing hint logged"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[secrets] gh CLI not on PATH; falling back...' in stdout"
  cat "$T25/stdout.log"
  FAIL=$((FAIL + 1))
fi

# Footer should print the manual values for copy-paste
if grep -q "GCP_WORKLOAD_IDENTITY_PROVIDER = projects/12345/" "$T25/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} fallback footer prints WIF provider for manual entry"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected footer to print WIF provider in manual fallback"
  FAIL=$((FAIL + 1))
fi

# Test 26: GITHUB_REPOSITORY unset → step silently skipped, no hint

echo ""
echo "Test 26: Step 7 silently skipped when GITHUB_REPOSITORY unset"

T26=$(run_step7_test "no-repo")

# No "[secrets]" log line at all when GITHUB_REPOSITORY is unset
if ! grep -q "\[secrets\]" "$T26/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} no [secrets] log line when GITHUB_REPOSITORY unset"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} should not log [secrets] without GITHUB_REPOSITORY"
  cat "$T26/stdout.log"
  FAIL=$((FAIL + 1))
fi

# Footer falls back to manual values (same as Test 25's manual fallback)
if grep -q "GCP_WORKLOAD_IDENTITY_PROVIDER = projects/12345/" "$T26/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} footer prints manual values when GITHUB_REPOSITORY unset"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected manual fallback when GITHUB_REPOSITORY unset"
  FAIL=$((FAIL + 1))
fi

# ── Test 27: cohort-shared Neon secret loop in footer ───────────────────
#
# When the wrapper auto-pushes per-attendee secrets (Step 7 succeeded)
# AND the Neon branch was provisioned, the footer should print the
# exact `gh secret set` loop the facilitator runs for the cohort-shared
# secrets (NEON_API_KEY, NEON_PROJECT_ID). These two are intentionally
# NOT auto-pushed by Step 7 because they're the same value across every
# fork in the cohort; coupling per-attendee provisioning to cohort state
# would make rotation harder.
#
# The dry-run on 2026-04-29 surfaced the gap: the wrapper completed
# successfully, the participant fork had GCP_PROJECT_ID etc. set, but
# /api/health worked and `/` returned 500 because NEON_API_KEY was
# never set on the fork — the facilitator hadn't run a manual `gh
# secret set` loop. Making this loop visible at provisioning-completion
# time is the upstream remedy.

echo ""
echo "Test 27: Footer prints cohort-shared Neon secret loop when Step 7 + Neon both ran"

T27=$(mktemp -d -t aflowtest-XXXX)
mkdir -p "$T27/bin"

# Stub gcloud + curl + gh so the inner script reaches the footer with
# both GH_SECRETS_PUSHED=true and NEON_BRANCH_PROVISIONED=true.
cat > "$T27/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$T27/gcloud.log"
case "\$1 \$2" in
  "projects describe")
    if echo "\$*" | grep -q "projectNumber"; then echo "12345"
    elif echo "\$*" | grep -q "lifecycleState"; then echo "ACTIVE"
    else exit 1; fi
    exit 0 ;;
  "projects create"|"projects get-iam-policy"|"projects add-iam-policy-binding") exit 0 ;;
  "billing projects")
    case "\$3" in
      describe) echo "billingAccounts/FAKE"; exit 0 ;;
      link) exit 0 ;;
    esac ;;
  "billing accounts") exit 0 ;;
  "resource-manager org-policies")
    case "\$3" in
      describe) exit 1 ;;
      set-policy) exit 0 ;;
    esac ;;
  "services enable") exit 0 ;;
  "artifacts repositories")
    case "\$3" in
      describe) exit 1 ;;
      create) exit 0 ;;
    esac ;;
  "iam service-accounts")
    case "\$3" in
      describe) exit 1 ;;
      create) exit 0 ;;
      add-iam-policy-binding) exit 0 ;;
    esac ;;
  "iam workload-identity-pools")
    case "\$3" in
      describe) exit 1 ;;
      create) exit 0 ;;
      providers)
        case "\$4" in
          describe) exit 1 ;;
          create-oidc) exit 0 ;;
        esac ;;
    esac ;;
  "secrets describe") exit 1 ;;
  "secrets create"|"secrets versions"|"secrets add-iam-policy-binding") exit 0 ;;
  "run services") exit 0 ;;
  "run deploy") exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$T27/bin/gcloud"

# Curl stub for the Neon API: respond to the 3 endpoints the script calls.
# Distinguish GET (list branches) from POST (create branch) the same way
# the existing 5.7 stub does — by checking for `-X POST` in argv.
cat > "$T27/bin/curl" <<EOF
#!/usr/bin/env bash
url=""
out_file=""
write_out=""
prev=""
is_post=false
for a in "\$@"; do
  case "\$a" in *console.neon.tech/api/v2*) url="\$a" ;; esac
  case "\$prev" in --output) out_file="\$a" ;; --write-out) write_out="\$a" ;; esac
  if [[ "\$a" == "POST" ]]; then is_post=true; fi
  prev="\$a"
done
emit() {
  if [[ -n "\$out_file" ]]; then printf '%s' "\$1" > "\$out_file"
  else printf '%s' "\$1"; fi
  if [[ -n "\$write_out" ]]; then printf '%s' "\$2"; fi
}
case "\$url" in
  *"/connection_uri"*)
    emit '{"uri":"postgresql://u:p@ep-xxx-pooler.us-east-2.aws.neon.tech/neondb?sslmode=require"}' "200"
    exit 0 ;;
  *"/branches"*)
    if \$is_post; then
      emit '{"branch":{"id":"br-tck517","name":"tck517"}}' "201"
      exit 0
    else
      emit '{"branches":[{"id":"br-main","name":"main","default":true}]}' "200"
      exit 0
    fi
    ;;
  *) emit '{"error":"unhandled"}' "500"; exit 1 ;;
esac
EOF
chmod +x "$T27/bin/curl"

# gh stub: same redact-body pattern as Test 24's harness.
cat > "$T27/bin/gh" <<EOF
#!/usr/bin/env bash
out=()
prev=""
for a in "\$@"; do
  if [[ "\$prev" == "--body" ]]; then out+=("--body=<redacted>"); else out+=("\$a"); fi
  prev="\$a"
done
echo "gh \${out[*]}" >> "$T27/gh.log"
exit 0
EOF
chmod +x "$T27/bin/gh"

set +e
PATH="$T27/bin:$PATH" \
  GCP_PROJECT_ID="af-step27-test" \
  BILLING_ACCOUNT_ID="FAKE" \
  GITHUB_OWNER="acme" \
  GITHUB_REPO="widget-shop" \
  GITHUB_REPOSITORY="acme/widget-shop" \
  NEON_API_KEY="fake-key" \
  NEON_PROJECT_ID="fake-proj" \
  NEON_BRANCH_NAME="tck517" \
  "$SCRIPT" --create-project > "$T27/stdout.log" 2>&1
set -e

# Both code paths must have run — sanity check before the new assertions.
if grep -q "Pushing GitHub Actions secrets to acme/widget-shop" "$T27/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} Step 7 push branch was active (sanity)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected Step 7 to push (test prerequisite); harness misconfigured"
  cat "$T27/stdout.log"
  FAIL=$((FAIL + 1))
fi
if grep -q "branch created" "$T27/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} Step 5.7 Neon branch was created (sanity)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected Neon branch creation (test prerequisite); harness misconfigured"
  cat "$T27/stdout.log"
  FAIL=$((FAIL + 1))
fi

# Core regression-guard assertions: the footer must print the exact
# gh-secret-set commands for the two cohort-shared secrets so a
# facilitator can copy-paste from the wrapper output.
if grep -q "gh secret set NEON_API_KEY    --repo acme/widget-shop" "$T27/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} footer prints gh secret set NEON_API_KEY loop"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected NEON_API_KEY gh-secret-set loop in footer"
  cat "$T27/stdout.log"
  FAIL=$((FAIL + 1))
fi

if grep -q "gh secret set NEON_PROJECT_ID --repo acme/widget-shop" "$T27/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} footer prints gh secret set NEON_PROJECT_ID loop"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected NEON_PROJECT_ID gh-secret-set loop in footer"
  FAIL=$((FAIL + 1))
fi

# Per-attendee secret added by #71: PRODUCTION_DATABASE_URL must be
# auto-pushed alongside NEON_PARENT_BRANCH whenever Neon was provisioned.
# Without it, deploy.yml's migration step skips silently and Cloud Run
# starts with DATABASE_URL="" (post-#68 plain env var), which 500s on
# the first DB query — the bug surfaced in the 2026-04-29 dry-run.
if grep -q "gh secret set PRODUCTION_DATABASE_URL --repo acme/widget-shop" "$T27/gh.log"; then
  echo -e "  ${GREEN}✓${NC} PRODUCTION_DATABASE_URL pushed (Neon-provisioned per-attendee secret)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected PRODUCTION_DATABASE_URL push when Neon provisioned"
  cat "$T27/gh.log"
  FAIL=$((FAIL + 1))
fi

# The footer must NOT actually push these — they're cohort-shared, not
# per-attendee. gh.log should only contain the per-attendee secrets.
if ! grep -q "gh secret set NEON_API_KEY" "$T27/gh.log"; then
  echo -e "  ${GREEN}✓${NC} cohort-shared NEON_API_KEY was NOT auto-pushed"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} NEON_API_KEY was pushed automatically; should be cohort-manual"
  cat "$T27/gh.log"
  FAIL=$((FAIL + 1))
fi
if ! grep -q "gh secret set NEON_PROJECT_ID" "$T27/gh.log"; then
  echo -e "  ${GREEN}✓${NC} cohort-shared NEON_PROJECT_ID was NOT auto-pushed"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} NEON_PROJECT_ID was pushed automatically; should be cohort-manual"
  FAIL=$((FAIL + 1))
fi

# ── Test 28: Step 0 activates core.hooksPath when pre-push hook exists ──
#
# Per #77: every fresh fork must leave the pre-push hook active after the
# provisioner runs. core.hooksPath is per-clone and not auto-set by git
# clone, so without this step the working hook is dormant. Run the
# provisioner in a temp dir that simulates a fresh fork (real `.git`,
# placeholder `scripts/hooks/pre-push`), and assert:
#   1. After the run, `git config --local core.hooksPath` returns
#      `scripts/hooks`
#   2. The activation message was logged
#   3. Re-running is a no-op (idempotent — message NOT logged again)
#
# We don't need the script to succeed end-to-end here. Step 0 runs
# before any GCP call; we just need it to fire.

echo ""
echo "Test 28: Step 0 activates core.hooksPath in a fresh fork"

T28=$(mktemp -d -t aflowtest-XXXX)

# Build the simulated fork tree
git init -q -b main "$T28"
mkdir -p "$T28/scripts/hooks"
echo '#!/usr/bin/env bash' > "$T28/scripts/hooks/pre-push"
chmod +x "$T28/scripts/hooks/pre-push"

# Stub gcloud so the script's later steps fail fast — we only care that
# Step 0 ran. A bare `false`-returning gcloud forces an early failure
# inside the project-create path, but Step 0 fires first.
mkdir -p "$T28/bin"
cat > "$T28/bin/gcloud" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$T28/bin/gcloud"

# First invocation
set +e
PATH="$T28/bin:$PATH" GCP_PROJECT_ID="af-step0-test" \
  bash -c "cd '$T28' && '$SCRIPT'" > "$T28/run1.log" 2>&1
set -e

# Assertion 1: hooksPath is now set in the temp repo
hooks_path=$(git -C "$T28" config --local --get core.hooksPath 2>/dev/null || echo "(unset)")
assert_eq "scripts/hooks" "$hooks_path" "core.hooksPath set after Step 0"

# Assertion 2: activation message logged on first run
if grep -q "\[hook\] Activated pre-push hook" "$T28/run1.log"; then
  echo -e "  ${GREEN}✓${NC} activation message logged on first run"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[hook] Activated' message in stdout"
  cat "$T28/run1.log"
  FAIL=$((FAIL + 1))
fi

# Second invocation — should be a no-op (idempotent)
set +e
PATH="$T28/bin:$PATH" GCP_PROJECT_ID="af-step0-test" \
  bash -c "cd '$T28' && '$SCRIPT'" > "$T28/run2.log" 2>&1
set -e

# Assertion 3: no activation message on second run (already configured)
if ! grep -q "\[hook\] Activated pre-push hook" "$T28/run2.log"; then
  echo -e "  ${GREEN}✓${NC} idempotent — no activation message on second run"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} activation re-fired on second run; should be no-op"
  cat "$T28/run2.log"
  FAIL=$((FAIL + 1))
fi

# Assertion 4: when scripts/hooks/pre-push is absent, Step 0 silently skips
T28b=$(mktemp -d -t aflowtest-XXXX)
git init -q -b main "$T28b"
# Note: NO scripts/hooks/pre-push file here

set +e
PATH="$T28/bin:$PATH" GCP_PROJECT_ID="af-step0-test" \
  bash -c "cd '$T28b' && '$SCRIPT'" > "$T28b/run.log" 2>&1
set -e

if ! grep -q "\[hook\]" "$T28b/run.log"; then
  echo -e "  ${GREEN}✓${NC} no [hook] log when pre-push hook is absent"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} should not log [hook] activation when no hook file present"
  cat "$T28b/run.log"
  FAIL=$((FAIL + 1))
fi

# Assertion 5: activation fires even before the GCP_PROJECT_ID required-
# check fails. This is the regression guard for Step 0's placement —
# without it, a future refactor that pushes Step 0 below the input
# validation would silently break the most common day-1 failure path
# (user runs script without setting GCP_PROJECT_ID).
T28c=$(mktemp -d -t aflowtest-XXXX)
git init -q -b main "$T28c"
mkdir -p "$T28c/scripts/hooks"
echo '#!/usr/bin/env bash' > "$T28c/scripts/hooks/pre-push"
chmod +x "$T28c/scripts/hooks/pre-push"

set +e
# Note: NO GCP_PROJECT_ID set — script must exit 1, but Step 0 should
# still have run.
PATH="$T28/bin:$PATH" \
  bash -c "cd '$T28c' && '$SCRIPT'" > "$T28c/run.log" 2>&1
ec=$?
set -e

assert_eq "1" "$ec" "script exits 1 when GCP_PROJECT_ID is unset (precondition for Assertion 5)"

hooks_path=$(git -C "$T28c" config --local --get core.hooksPath 2>/dev/null || echo "(unset)")
assert_eq "scripts/hooks" "$hooks_path" "core.hooksPath set even when GCP_PROJECT_ID is unset (Step 0 fires before input validation)"

if grep -q "\[hook\] Activated pre-push hook" "$T28c/run.log"; then
  echo -e "  ${GREEN}✓${NC} activation message logged before exit (Step 0 ran before GCP_PROJECT_ID check)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected '[hook] Activated' before the GCP_PROJECT_ID error"
  cat "$T28c/run.log"
  FAIL=$((FAIL + 1))
fi

# ── Test 29: Neon 409 with NEON_FORCE_SHARED_PARENT unset → fail fast ──
#
# Per #90: silent reuse on 409 is the cross-contamination footgun. Two
# attendees with the same handle (or a re-run cohort against a populated
# Neon project) should fail fast with an actionable message rather than
# transparently mounting the second attendee's database-url secret to
# the first attendee's branch.

echo ""
echo "Test 29: Step 5.7 fails fast on Neon 409 when NEON_FORCE_SHARED_PARENT unset"

T29=$(run_step5_7_test "exists" "fake-api-key" "fake-project-id" "alice" "false")

# Note: run_step5_7_test wraps the inner call in `set +e`, so the helper
# always returns 0. Verify behavior via stdout content + gcloud.log.

if grep -q "ERROR: Neon branch 'alice' already exists" "$T29/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} fail-fast error message names the branch and project"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected fail-fast error in stdout"
  cat "$T29/stdout.log"
  FAIL=$((FAIL + 1))
fi

if grep -q "set NEON_FORCE_SHARED_PARENT=true" "$T29/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} error message points at the escape hatch"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected error to mention NEON_FORCE_SHARED_PARENT escape hatch"
  FAIL=$((FAIL + 1))
fi

# Should NOT have proceeded to write the database-url secret (cross-contam guard)
if ! grep -q "secrets create database-url\|secrets versions add database-url" "$T29/gcloud.log"; then
  echo -e "  ${GREEN}✓${NC} did NOT write database-url secret after fail-fast"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} script wrote database-url secret despite collision (cross-contam!)"
  cat "$T29/gcloud.log"
  FAIL=$((FAIL + 1))
fi

# ── Test 30: Neon 409 with NEON_FORCE_SHARED_PARENT=true → silent reuse ──
#
# The opt-in path: legitimate re-run of an existing cohort, or paired
# attendees intentionally sharing a parent branch. Same behavior as the
# pre-#90 default: reuse the branch, write the secret, no error.

echo ""
echo "Test 30: Step 5.7 reuses existing branch when NEON_FORCE_SHARED_PARENT=true"

T30=$(run_step5_7_test "exists" "fake-api-key" "fake-project-id" "alice" "true")

if grep -q "reusing per NEON_FORCE_SHARED_PARENT=true" "$T30/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} reuse log line names the force flag"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected 'reusing per NEON_FORCE_SHARED_PARENT' in stdout"
  cat "$T30/stdout.log"
  FAIL=$((FAIL + 1))
fi

if ! grep -q "ERROR: Neon branch" "$T30/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} no fail-fast error when force flag is set"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} script emitted error despite force flag"
  cat "$T30/stdout.log"
  FAIL=$((FAIL + 1))
fi

# Should have proceeded through to secret write (preserves the pre-#90 behavior).
# The script emits its own `[create] database-url secret` /
# `[skip] database-url secret already current` log prefix on stdout;
# the underlying gcloud call lives in gcloud.log.
if grep -qE "\[(create|update|skip)\] database-url secret" "$T30/stdout.log"; then
  echo -e "  ${GREEN}✓${NC} proceeded to database-url secret handling"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} did not reach database-url secret step under force flag"
  cat "$T30/stdout.log"
  FAIL=$((FAIL + 1))
fi

# ── Summary ──────────────────────────────────────────────────────────────

echo ""
echo "─────────────────────────────────"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "─────────────────────────────────"

(( FAIL > 0 )) && exit 1
exit 0
