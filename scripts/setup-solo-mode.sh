#!/bin/bash
#
# Agile Flow — Solo Mode Setup
#
# One-shot bootstrap for solo mode: one personal GitHub account plays
# all roles (worker, reviewer, human merger). Recommended for workshops,
# tutorials, individual learners, and anyone evaluating the framework
# without provisioning bot accounts.
#
# What this script does (and does not):
#
#   ✓ Persists `AGILE_FLOW_SOLO_MODE=true` to your shell profile.
#   ✓ Audits stale `GITHUB_PERSONAL_ACCESS_TOKEN*` env vars (which
#     silently override `gh auth switch` and break agent workflows).
#   ✓ Verifies your active gh account has the required scopes
#     (repo, project, workflow, read:project) and refreshes if not.
#   ✓ Activates the in-repo pre-push hook (`core.hooksPath`).
#   ✓ Verifies you have admin access on the current fork.
#
#   ✗ Does NOT cache tokens to disk. Tokens stay in gh's keyring.
#   ✗ Does NOT auto-modify your shell rc to remove tokens — surfaces
#     them and tells you the exact removal command.
#   ✗ Does NOT touch multi-bot env vars (AGILE_FLOW_WORKER_ACCOUNT /
#     AGILE_FLOW_REVIEWER_ACCOUNT) without explicit confirmation —
#     preserves multi-bot setups that may have a fallback pattern.
#
# Usage:
#   bash scripts/setup-solo-mode.sh
#
# Prerequisites:
#   - gh CLI installed and authenticated (`gh auth login`)
#   - Run from the repo root (where `.git/` and `scripts/hooks/` live)
#
# After this script completes, RESTART Claude Code so the agent
# subprocesses pick up the new env var. The hook checks
# `AGILE_FLOW_SOLO_MODE` from its own env, which is a snapshot from
# the agent session start — without a restart, the hook keeps reading
# the old (unset) value.
#
# Exit codes:
#   0 — solo mode is configured (or already configured)
#   1 — a check failed (gh missing, no admin access, etc.)
#   2 — user declined a required prompt
#
# See also: docs/PLATFORM-GUIDE.md "Solo mode" section, #83.

set -uo pipefail

# Ensure bash even if invoked as `zsh scripts/setup-solo-mode.sh`
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

# ───────────────────────────────────────────────────────────────────
#  Colors + print helpers (copied from setup-accounts.sh shape)
# ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}! $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}→ $1${NC}"; }

# ───────────────────────────────────────────────────────────────────
#  Detect the user's shell profile file
# ───────────────────────────────────────────────────────────────────
detect_shell_profile() {
    if [ -n "${ZSH_VERSION:-}" ] || [ "${SHELL:-}" = "/bin/zsh" ] || [ "${SHELL:-}" = "/usr/bin/zsh" ] || [ "${SHELL:-}" = "/opt/homebrew/bin/zsh" ]; then
        echo "$HOME/.zshrc"
    elif [[ "${SHELL:-}" == */fish ]]; then
        echo "$HOME/.config/fish/config.fish"
    elif [ -n "${BASH_VERSION:-}" ] || [ "${SHELL:-}" = "/bin/bash" ] || [ "${SHELL:-}" = "/usr/bin/bash" ]; then
        if [ -f "$HOME/.bash_profile" ]; then
            echo "$HOME/.bash_profile"
        else
            echo "$HOME/.bashrc"
        fi
    else
        if [ -f "$HOME/.zshrc" ]; then
            echo "$HOME/.zshrc"
        elif [ -f "$HOME/.bashrc" ]; then
            echo "$HOME/.bashrc"
        else
            echo "$HOME/.profile"
        fi
    fi
}

# ───────────────────────────────────────────────────────────────────
#  Persist an env var to shell profile (idempotent)
#  Handles bash/zsh `export` and fish `set -Ux`.
# ───────────────────────────────────────────────────────────────────
persist_env_var() {
    local var_name=$1
    local var_value=$2
    local profile
    profile=$(detect_shell_profile)

    export "$var_name=$var_value"

    if [[ "$profile" == */fish/* ]]; then
        # fish: `set -Ux NAME value` (universal, exported)
        if grep -q "^set -Ux ${var_name} " "$profile" 2>/dev/null; then
            if [[ "$OSTYPE" == darwin* ]]; then
                sed -i '' "s|^set -Ux ${var_name} .*|set -Ux ${var_name} ${var_value}|" "$profile"
            else
                sed -i "s|^set -Ux ${var_name} .*|set -Ux ${var_name} ${var_value}|" "$profile"
            fi
            print_info "Updated ${var_name} in ${profile}"
        else
            mkdir -p "$(dirname "$profile")"
            {
                echo ""
                echo "# Added by Agile Flow setup-solo-mode"
                echo "set -Ux ${var_name} ${var_value}"
            } >> "$profile"
            print_info "Added ${var_name} to ${profile}"
        fi
    else
        # bash/zsh: `export NAME=value`
        if grep -q "^export ${var_name}=" "$profile" 2>/dev/null; then
            if [[ "$OSTYPE" == darwin* ]]; then
                sed -i '' "s|^export ${var_name}=.*|export ${var_name}=\"${var_value}\"|" "$profile"
            else
                sed -i "s|^export ${var_name}=.*|export ${var_name}=\"${var_value}\"|" "$profile"
            fi
            print_info "Updated ${var_name} in ${profile}"
        else
            {
                echo ""
                echo "# Added by Agile Flow setup-solo-mode"
                echo "export ${var_name}=\"${var_value}\""
            } >> "$profile"
            print_info "Added ${var_name} to ${profile}"
        fi
    fi
}

# ───────────────────────────────────────────────────────────────────
#  Pre-flight: gh present + repo root + already authed
# ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}=== Agile Flow — Solo Mode Setup ===${NC}"
echo ""

if ! command -v gh >/dev/null 2>&1; then
    print_error "gh CLI not found on PATH"
    print_info "Install: https://cli.github.com/"
    exit 1
fi

if [ ! -d ".git" ]; then
    print_error "Not in a git repo (no .git/ here)"
    print_info "cd to the repo root, then re-run this script"
    exit 1
fi

# Note: `gh auth status` (without --active) exits non-zero if ANY account
# in the keyring has an invalid token, even when valid accounts exist.
# Use --active to check that there's at least one working active account.
if ! gh auth status --active >/dev/null 2>&1; then
    print_error "No active gh account (or all accounts have invalid tokens)"
    print_info "Run: gh auth login"
    exit 1
fi

# Detect interactive vs non-interactive run. Codespace `postCreateCommand`
# (and any other piped/redirected invocation) lacks a TTY on stdin, which
# means `gh auth refresh` would hang waiting for browser OAuth, and a
# fail-fast on missing admin would break Codespace creation. In those
# contexts we WARN and continue instead. See #97.
IS_INTERACTIVE=true
if [ ! -t 0 ]; then
    IS_INTERACTIVE=false
    print_warning "Non-interactive context detected (no TTY on stdin)"
    print_info "Some steps will WARN+continue instead of running interactive prompts."
    echo ""
fi

# ───────────────────────────────────────────────────────────────────
#  Step 1/8: Detect shell + show current state
# ───────────────────────────────────────────────────────────────────
echo -e "${CYAN}--- Step 1/8: Detect shell ---${NC}"
echo ""

profile=$(detect_shell_profile)
print_success "Detected shell profile: ${profile}"

active_account=$(gh auth status --active 2>&1 | grep "Logged in to" | sed 's/.*account \([^ ]*\).*/\1/' | head -1)
print_info "Active gh account: ${active_account:-(none detected)}"
echo ""

# ───────────────────────────────────────────────────────────────────
#  Step 2/8: Persist AGILE_FLOW_SOLO_MODE
# ───────────────────────────────────────────────────────────────────
echo -e "${CYAN}--- Step 2/8: Persist AGILE_FLOW_SOLO_MODE=true ---${NC}"
echo ""

if [ "${AGILE_FLOW_SOLO_MODE:-}" = "true" ] && grep -qE "(^export AGILE_FLOW_SOLO_MODE=|^set -Ux AGILE_FLOW_SOLO_MODE )" "$profile" 2>/dev/null; then
    print_success "AGILE_FLOW_SOLO_MODE=true already set in ${profile}"
else
    persist_env_var "AGILE_FLOW_SOLO_MODE" "true"
fi
echo ""

# ───────────────────────────────────────────────────────────────────
#  Step 3/8: Audit GITHUB_PERSONAL_ACCESS_TOKEN* env vars
# ───────────────────────────────────────────────────────────────────
echo -e "${CYAN}--- Step 3/8: Audit GITHUB_PERSONAL_ACCESS_TOKEN env vars ---${NC}"
echo ""

# In solo mode, ANY of these env vars override `gh auth switch` silently.
# Detection is from the current shell environment (what gh sees right now)
# AND from the shell rc file (so the user knows what to remove permanently).
token_env_vars=()
while IFS= read -r line; do
    [ -n "$line" ] && token_env_vars+=("$line")
done < <(env | grep -E "^(GITHUB_PERSONAL_ACCESS_TOKEN|GH_TOKEN)" | cut -d= -f1 || true)

token_rc_lines=()
if [ -f "$profile" ]; then
    while IFS= read -r line; do
        [ -n "$line" ] && token_rc_lines+=("$line")
    done < <(grep -nE "^(export\s+)?GITHUB_PERSONAL_ACCESS_TOKEN|^(export\s+)?GH_TOKEN|^set -Ux\s+GITHUB_PERSONAL_ACCESS_TOKEN|^set -Ux\s+GH_TOKEN" "$profile" 2>/dev/null || true)
fi

env_count=${#token_env_vars[@]}
rc_count=${#token_rc_lines[@]}
if [ "$env_count" -eq 0 ] && [ "$rc_count" -eq 0 ]; then
    print_success "No token env vars detected (gh keyring is the source of truth)"
else
    print_warning "Found token env vars that override gh auth switch:"
    echo ""
    if [ "$env_count" -gt 0 ]; then
        for v in "${token_env_vars[@]}"; do
            echo "    in current shell: ${v}"
        done
    fi
    if [ "$rc_count" -gt 0 ]; then
        for line in "${token_rc_lines[@]}"; do
            echo "    in ${profile}: ${line}"
        done
    fi
    echo ""
    print_warning "These vars cause gh to authenticate with the env-var token instead of the keyring."
    print_warning "In solo mode, that breaks agent workflows because gh auth switch silently has no effect."
    echo ""
    print_info "Recommended manual cleanup:"
    print_info "  1. Edit ${profile} and remove the lines above"
    print_info "  2. Rotate the affected tokens at https://github.com/settings/tokens"
    print_info "  3. Restart your shell (or open a new terminal)"
    echo ""
    print_warning "Continuing without removing — the rest of this script may surface inconsistencies."
fi
echo ""

# ───────────────────────────────────────────────────────────────────
#  Step 4/8: Verify scopes
# ───────────────────────────────────────────────────────────────────
echo -e "${CYAN}--- Step 4/8: Verify gh token scopes ---${NC}"
echo ""

required_scopes=(repo project workflow read:project)
auth_status_output=$(gh auth status 2>&1 || true)
token_scopes=$(echo "$auth_status_output" | grep -E "Token scopes:" | head -1 | sed -E "s/.*Token scopes: //; s/['\"]//g; s/, /,/g")

missing_scopes=()
for s in "${required_scopes[@]}"; do
    if ! echo ",${token_scopes}," | grep -q ",${s},"; then
        missing_scopes+=("$s")
    fi
done

if [ ${#missing_scopes[@]} -eq 0 ]; then
    print_success "All required scopes present (${required_scopes[*]})"
elif [ "$IS_INTERACTIVE" != "true" ]; then
    # Non-interactive (Codespace postCreateCommand, CI, piped invocation):
    # `gh auth refresh` would hang waiting for browser OAuth. WARN and
    # surface the manual command for the user to run from their first
    # interactive terminal. See #97.
    print_warning "Missing scopes: ${missing_scopes[*]}"
    print_warning "Skipping refresh (non-interactive context — would block on browser OAuth)"
    print_info "Run manually after this script finishes:"
    print_info "  gh auth refresh -h github.com -s $(IFS=,; echo "${missing_scopes[*]}")"
else
    print_warning "Missing scopes: ${missing_scopes[*]}"
    print_info "Running: gh auth refresh -h github.com -s ${missing_scopes[*]}"
    echo ""
    if gh auth refresh -h github.com -s "$(IFS=,; echo "${missing_scopes[*]}")"; then
        # Verify active account did not flip during refresh (known gh quirk).
        new_active=$(gh auth status --active 2>&1 | grep "Logged in to" | sed 's/.*account \([^ ]*\).*/\1/' | head -1)
        if [ "$new_active" != "$active_account" ]; then
            print_warning "gh auth refresh flipped active account from '$active_account' to '$new_active'"
            print_info "Restoring active account..."
            if gh auth switch --user "$active_account" >/dev/null 2>&1; then
                print_success "Restored active account to '$active_account'"
            else
                print_error "Could not restore active account; please run: gh auth switch --user $active_account"
                exit 1
            fi
        fi
        print_success "Scope refresh complete"
    else
        print_error "gh auth refresh failed"
        exit 1
    fi
fi
echo ""

# ───────────────────────────────────────────────────────────────────
#  Step 5/8: Activate pre-push hook
# ───────────────────────────────────────────────────────────────────
echo -e "${CYAN}--- Step 5/8: Activate pre-push hook ---${NC}"
echo ""

if [ -f "scripts/hooks/pre-push" ]; then
    current_hooks_path=$(git config --local --get core.hooksPath 2>/dev/null || true)
    if [ "$current_hooks_path" = "scripts/hooks" ]; then
        print_success "core.hooksPath already set to scripts/hooks"
    else
        git config --local core.hooksPath scripts/hooks
        print_success "Activated pre-push hook (lint + tests will run before every push)"
    fi
else
    print_warning "scripts/hooks/pre-push not found; skipping hook activation"
fi
echo ""

# ───────────────────────────────────────────────────────────────────
#  Step 6/8: Verify admin access on this fork
# ───────────────────────────────────────────────────────────────────
echo -e "${CYAN}--- Step 6/8: Verify admin access on this fork ---${NC}"
echo ""

remote_url=$(git config --get remote.origin.url 2>/dev/null || true)
if [ -z "$remote_url" ]; then
    print_warning "No 'origin' remote configured; skipping admin check"
    print_info "(If this is a fresh clone, the remote should be set automatically)"
else
    # Convert SSH or HTTPS URL to owner/repo
    repo=$(echo "$remote_url" | sed -E 's|^git@github\.com:|/|; s|^https://github\.com/||; s|\.git$||; s|^/||')
    if [ -z "$repo" ]; then
        print_warning "Could not parse owner/repo from remote URL: $remote_url"
    else
        admin=$(gh api "repos/${repo}" --jq '.permissions.admin // false' 2>/dev/null || echo "false")
        if [ "$admin" = "true" ]; then
            print_success "${active_account} has admin access on ${repo}"
        else
            # Downgrade: this used to exit 1, but admin is a *signal*, not a
            # gatekeeper. The bootstrap's other outputs (env var, hook
            # activation) are still valuable; downstream scripts (gh secret
            # set, branch protection setup) will surface their own clear
            # errors when admin is actually needed. See #97.
            print_warning "${active_account} does NOT have admin access on ${repo}"
            print_info "Solo mode normally requires admin (write secrets, manage branches, project boards)."
            print_info "Either: (a) you are not the fork owner — fork the repo first, OR"
            print_info "        (b) you opened a Codespace from the upstream repo — fork it"
            print_info "            and create a Codespace from your fork, OR"
            print_info "        (c) you are operating in a multi-bot setup — solo mode does not apply"
        fi
    fi
fi
echo ""

# ───────────────────────────────────────────────────────────────────
#  Step 7/8: Multi-bot env-var sanity check
# ───────────────────────────────────────────────────────────────────
echo -e "${CYAN}--- Step 7/8: Multi-bot env-var sanity check ---${NC}"
echo ""

if [ -n "${AGILE_FLOW_WORKER_ACCOUNT:-}" ] || [ -n "${AGILE_FLOW_REVIEWER_ACCOUNT:-}" ]; then
    print_warning "Multi-bot env vars detected:"
    [ -n "${AGILE_FLOW_WORKER_ACCOUNT:-}" ]   && echo "    AGILE_FLOW_WORKER_ACCOUNT=${AGILE_FLOW_WORKER_ACCOUNT}"
    [ -n "${AGILE_FLOW_REVIEWER_ACCOUNT:-}" ] && echo "    AGILE_FLOW_REVIEWER_ACCOUNT=${AGILE_FLOW_REVIEWER_ACCOUNT}"
    echo ""
    print_info "These are harmless in solo mode (the hook short-circuits on AGILE_FLOW_SOLO_MODE=true)"
    print_info "but they may confuse readers of doctor.sh output. Consider unsetting them."
else
    print_success "No multi-bot env vars set"
fi
echo ""

# ───────────────────────────────────────────────────────────────────
#  Step 8/8: Done — restart prompt
# ───────────────────────────────────────────────────────────────────
echo -e "${CYAN}--- Step 8/8: Done ---${NC}"
echo ""

print_success "Solo mode is configured."
echo ""
print_info "Next steps:"
print_info "  1. Restart Claude Code (or open a new shell)"
print_info "     so agent subprocesses pick up AGILE_FLOW_SOLO_MODE."
print_info "  2. Run scripts/doctor.sh to verify the full setup."
print_info "  3. Open a ticket and run /work-ticket — agents now operate"
print_info "     as ${active_account} without bot-account switching."
echo ""
exit 0
