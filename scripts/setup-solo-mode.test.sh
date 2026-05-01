#!/usr/bin/env bash
#
# Tests for setup-solo-mode.sh — solo-mode bootstrap.
#
# Stubs `gh` minimally so we can exercise the script's decision logic
# without touching real auth state or the user's shell rc. Each test
# runs in a fresh tempdir with a fake HOME and a fresh git repo +
# scripts/hooks tree.
#
# Run: ./scripts/setup-solo-mode.test.sh

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/setup-solo-mode.sh"

new_sandbox() {
    local tmp
    tmp=$(mktemp -d -t solomode-test-XXXX)
    mkdir -p "$tmp/bin" "$tmp/sandbox-home" "$tmp/repo/scripts/hooks"

    touch "$tmp/sandbox-home/.zshrc"

    (cd "$tmp/repo" && git init -q -b main && git remote add origin https://github.com/test-owner/test-repo.git)
    echo '#!/usr/bin/env bash' > "$tmp/repo/scripts/hooks/pre-push"
    chmod +x "$tmp/repo/scripts/hooks/pre-push"

    # Active-account state is persisted to a file so the stub can mutate
    # it across calls (env-var mutation in the stub doesn't propagate).
    echo "${STUB_INITIAL_ACCOUNT:-}" > "$tmp/active-account"

    echo "$tmp"
}

# gh stub. Reads active account from $STUB_STATE/active-account on each
# call. Writes a log to $STUB_STATE/gh.log. Behavior controlled by
# STUB_TOKEN_SCOPES, STUB_REFRESH_FLIPS_TO, STUB_API_ADMIN.
make_gh_stub() {
    local tmp="$1"
    cat > "$tmp/bin/gh" <<'STUB_EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$STUB_STATE/gh.log"

active=$(cat "$STUB_STATE/active-account" 2>/dev/null)

cmd1="${1:-}"
cmd2="${2:-}"

# Match the first two args verbatim
case "$cmd1 $cmd2" in
    "auth status")
        # --active flag → return success only when active account is set
        for arg in "$@"; do
            if [[ "$arg" == "--active" ]]; then
                if [[ -n "$active" ]]; then
                    echo "github.com"
                    echo "  ✓ Logged in to github.com account ${active} (keyring)"
                    echo "  - Active account: true"
                    echo "  - Token scopes: ${STUB_TOKEN_SCOPES:-'repo, project, workflow, read:project'}"
                    exit 0
                fi
                exit 1
            fi
        done
        # Without --active
        if [[ -n "$active" ]]; then
            echo "github.com"
            echo "  ✓ Logged in to github.com account ${active} (keyring)"
            echo "  - Active account: true"
            echo "  - Token scopes: ${STUB_TOKEN_SCOPES:-'repo, project, workflow, read:project'}"
            exit 0
        fi
        exit 1
        ;;
    "auth refresh")
        if [[ -n "${STUB_REFRESH_FLIPS_TO:-}" ]]; then
            echo "$STUB_REFRESH_FLIPS_TO" > "$STUB_STATE/active-account"
        fi
        exit "${STUB_REFRESH_EXIT:-0}"
        ;;
    "auth switch")
        # argv: --user <name>
        prev=""
        for arg in "$@"; do
            if [[ "$prev" == "--user" ]]; then
                echo "$arg" > "$STUB_STATE/active-account"
                exit 0
            fi
            prev="$arg"
        done
        exit 1
        ;;
esac

# Fall through: match `api repos/<owner>/<repo>` regardless of trailing args
if [[ "$cmd1" == "api" ]] && [[ "$cmd2" == repos/* ]]; then
    echo "${STUB_API_ADMIN:-true}"
    exit 0
fi

# Default: succeed quietly
exit 0
STUB_EOF
    chmod +x "$tmp/bin/gh"
}

# Run script in a clean env (no token vars from parent).
# Pass any STUB_* and required vars explicitly via env.
run_script() {
    local sandbox="$1"
    shift
    # Use env -i to clear, then re-establish only what the script needs.
    env -i \
        HOME="$sandbox/sandbox-home" \
        SHELL=/bin/zsh \
        PATH="$sandbox/bin:/usr/bin:/bin:/usr/local/bin" \
        STUB_STATE="$sandbox" \
        TERM="${TERM:-dumb}" \
        "$@" \
        bash -c "cd '$sandbox/repo' && '$SCRIPT'"
}

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo -e "  ${GREEN}OK${NC} $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $label  (expected: $expected; got: $actual)"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local needle="$1" file="$2" label="$3"
    if grep -qF "$needle" "$file"; then
        echo -e "  ${GREEN}OK${NC} $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $label  (expected to contain: $needle)"
        echo "  --- file content ---"
        sed -e 's/^/  /' "$file"
        echo "  --------------------"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local needle="$1" file="$2" label="$3"
    if ! grep -qF "$needle" "$file"; then
        echo -e "  ${GREEN}OK${NC} $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $label  (should NOT contain: $needle)"
        FAIL=$((FAIL + 1))
    fi
}

# ── Test 1: happy path — no token vars, scopes complete, admin true ───

echo ""
echo "Test 1: happy path"

T1=$(STUB_INITIAL_ACCOUNT=alice new_sandbox)
make_gh_stub "$T1"

set +e
run_script "$T1" \
    STUB_TOKEN_SCOPES="repo, project, workflow, read:project" \
    STUB_API_ADMIN="true" \
    > "$T1/run.log" 2>&1
ec=$?
set -e

assert_eq "0" "$ec" "exit 0 on happy path"
assert_contains "Solo mode is configured" "$T1/run.log" "success message"
assert_contains "AGILE_FLOW_SOLO_MODE" "$T1/sandbox-home/.zshrc" "AGILE_FLOW_SOLO_MODE persisted to .zshrc"
assert_contains "Activated pre-push hook" "$T1/run.log" "hook activated on first run"
assert_not_contains "auth refresh" "$T1/gh.log" "no gh auth refresh on happy path"

# ── Test 2: missing scopes (non-interactive context) → WARN+skip ─────
# Since #97: the script detects non-interactive contexts (no TTY on
# stdin, like Codespace postCreateCommand or this test harness) and
# WARNs about missing scopes instead of calling `gh auth refresh`
# (which would hang on browser OAuth). The test harness's `bash -c`
# invocation IS a non-interactive context, so this test exercises
# that path. The interactive path (call refresh) is verified by
# manual runs from a developer's terminal.

echo ""
echo "Test 2: missing scopes in non-interactive context → WARN+skip refresh"

T2=$(STUB_INITIAL_ACCOUNT=alice new_sandbox)
make_gh_stub "$T2"

set +e
run_script "$T2" \
    STUB_TOKEN_SCOPES="repo, workflow" \
    STUB_API_ADMIN="true" \
    > "$T2/run.log" 2>&1
ec=$?
set -e

assert_eq "0" "$ec" "exit 0"
assert_contains "Non-interactive context detected" "$T2/run.log" "detects no-TTY context"
assert_contains "Missing scopes: project read:project" "$T2/run.log" "names missing scopes"
assert_contains "Skipping refresh" "$T2/run.log" "explicitly skips the interactive call"
assert_contains "Run manually after this script finishes" "$T2/run.log" "tells user how to fix"
# Critical: gh auth refresh must NOT have been called (would hang in real Codespace)
if ! grep -q "auth refresh" "$T2/gh.log"; then
    echo -e "  ${GREEN}OK${NC} did NOT call gh auth refresh in non-interactive context"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} script called gh auth refresh despite non-interactive context (would hang in Codespace!)"
    cat "$T2/gh.log"
    FAIL=$((FAIL + 1))
fi

# ── Test 3: refresh-flip recovery (interactive path, deferred) ───────
# This test previously verified that an interactive `gh auth refresh`
# that flips the active account triggers a restore via `gh auth
# switch`. Since #97, the test harness can't reach that code path
# (it always runs non-interactive). The flip-recovery logic is
# unchanged from #83; manual verification on a developer's terminal
# is the path to exercise it.
#
# In place of the unreachable assertion, we verify that the
# non-interactive context does NOT attempt an auth switch (the flip
# can't happen if refresh wasn't called).

echo ""
echo "Test 3: non-interactive context skips both refresh and switch"

T3=$(STUB_INITIAL_ACCOUNT=alice new_sandbox)
make_gh_stub "$T3"

set +e
run_script "$T3" \
    STUB_TOKEN_SCOPES="repo" \
    STUB_REFRESH_FLIPS_TO="va-worker" \
    STUB_API_ADMIN="true" \
    > "$T3/run.log" 2>&1
ec=$?
set -e

assert_eq "0" "$ec" "exit 0"
if ! grep -q "auth refresh\|auth switch" "$T3/gh.log"; then
    echo -e "  ${GREEN}OK${NC} no gh auth refresh or switch in non-interactive context"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} script attempted refresh/switch despite non-interactive context"
    cat "$T3/gh.log"
    FAIL=$((FAIL + 1))
fi
# The flip-detection logic should not have fired (refresh was skipped)
if ! grep -q "flipped active account" "$T3/run.log"; then
    echo -e "  ${GREEN}OK${NC} flip-detection did NOT fire (refresh was skipped)"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} flip detection fired but refresh should have been skipped"
    FAIL=$((FAIL + 1))
fi

# ── Test 4: token env var present → warning surfaces ─────────────────

echo ""
echo "Test 4: GITHUB_PERSONAL_ACCESS_TOKEN env var → warning"

T4=$(STUB_INITIAL_ACCOUNT=alice new_sandbox)
make_gh_stub "$T4"

set +e
run_script "$T4" \
    STUB_TOKEN_SCOPES="repo, project, workflow, read:project" \
    STUB_API_ADMIN="true" \
    GITHUB_PERSONAL_ACCESS_TOKEN="ghp_fake1234567890" \
    > "$T4/run.log" 2>&1
ec=$?
set -e

assert_eq "0" "$ec" "exit 0 (continues with warning)"
assert_contains "Found token env vars" "$T4/run.log" "surfaces token env var"
assert_contains "GITHUB_PERSONAL_ACCESS_TOKEN" "$T4/run.log" "names the offending var"
assert_contains "Recommended manual cleanup" "$T4/run.log" "tells user how to remove"

# ── Test 5: idempotent re-run ────────────────────────────────────────

echo ""
echo "Test 5: idempotent re-run"

T5=$(STUB_INITIAL_ACCOUNT=alice new_sandbox)
make_gh_stub "$T5"

# First run
set +e
run_script "$T5" \
    STUB_TOKEN_SCOPES="repo, project, workflow, read:project" \
    STUB_API_ADMIN="true" \
    > "$T5/run1.log" 2>&1
set -e

count1=$(grep -c "^export AGILE_FLOW_SOLO_MODE=" "$T5/sandbox-home/.zshrc" || true)

# Second run — must pass AGILE_FLOW_SOLO_MODE=true so the early-skip branch fires
set +e
run_script "$T5" \
    STUB_TOKEN_SCOPES="repo, project, workflow, read:project" \
    STUB_API_ADMIN="true" \
    AGILE_FLOW_SOLO_MODE="true" \
    > "$T5/run2.log" 2>&1
set -e

count2=$(grep -c "^export AGILE_FLOW_SOLO_MODE=" "$T5/sandbox-home/.zshrc" || true)

assert_eq "$count1" "$count2" "AGILE_FLOW_SOLO_MODE export not duplicated on re-run"
assert_contains "AGILE_FLOW_SOLO_MODE=true already set" "$T5/run2.log" "re-run reports already-configured state"
assert_contains "core.hooksPath already set" "$T5/run2.log" "hook activation noted as already set on re-run"

# ── Test 6: not in repo root → fails fast ─────────────────────────────

echo ""
echo "Test 6: not in repo root → fail fast"

T6=$(STUB_INITIAL_ACCOUNT=alice new_sandbox)
make_gh_stub "$T6"

# Override the cwd to NOT be the repo root.
set +e
env -i \
    HOME="$T6/sandbox-home" \
    SHELL=/bin/zsh \
    PATH="$T6/bin:/usr/bin:/bin:/usr/local/bin" \
    STUB_STATE="$T6" \
    TERM="${TERM:-dumb}" \
    bash -c "cd '$T6' && '$SCRIPT'" > "$T6/run.log" 2>&1
ec=$?
set -e

assert_eq "1" "$ec" "exit 1 when not in repo root"
assert_contains "Not in a git repo" "$T6/run.log" "names the issue"

# ── Test 7: no admin access → WARN, continue ────────────────────────
# Since #97: admin-verification was downgraded from `exit 1` to a
# WARN. Admin is a signal, not a gatekeeper — the bootstrap's other
# outputs (env var, hook activation) remain valuable when admin is
# missing, and downstream scripts will surface their own clear errors
# when admin is actually needed. Critically, this also unblocks
# Codespace `postCreateCommand` for users who open a Codespace from
# the upstream repo before forking.

echo ""
echo "Test 7: no admin access on origin remote → WARN+continue (not exit)"

T7=$(STUB_INITIAL_ACCOUNT=alice new_sandbox)
make_gh_stub "$T7"

set +e
run_script "$T7" \
    STUB_TOKEN_SCOPES="repo, project, workflow, read:project" \
    STUB_API_ADMIN="false" \
    > "$T7/run.log" 2>&1
ec=$?
set -e

assert_eq "0" "$ec" "exit 0 — admin missing is a WARN, not a fatal"
assert_contains "does NOT have admin access" "$T7/run.log" "WARN message still emitted"
assert_contains "Solo mode is configured" "$T7/run.log" "script proceeds to completion despite missing admin"

# ── Test 8: no active gh account → fail fast ─────────────────────────

echo ""
echo "Test 8: no active gh account → fail fast"

T8=$(STUB_INITIAL_ACCOUNT="" new_sandbox)
make_gh_stub "$T8"

set +e
run_script "$T8" \
    > "$T8/run.log" 2>&1
ec=$?
set -e

assert_eq "1" "$ec" "exit 1 when no active gh account"
assert_contains "No active gh account" "$T8/run.log" "names the issue"

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "─────────────────────────────────"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "─────────────────────────────────"

(( FAIL > 0 )) && exit 1
exit 0
