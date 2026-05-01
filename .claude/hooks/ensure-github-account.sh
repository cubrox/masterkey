#!/bin/bash
#
# Claude Code PreToolUse Hook: GitHub Account Switcher
#
# Automatically switches to the correct GitHub account before PR creation
# and review operations. Prevents the wrong account from being attributed
# to automated work.
#
# Account model (configure these for your org):
#   - WORKER_ACCOUNT: Used for ticket work, commits, PRs
#   - REVIEWER_ACCOUNT: Used for PR reviews
#
# Configure via environment variables or edit the defaults below.
#
# Two short-circuits before the hook attempts any account switch:
#   1. Env-var fast path — AGILE_FLOW_SOLO_MODE=true exits 0 unconditionally.
#   2. Keyring safety net (#85) — if the active gh account is not one of the
#      configured bots, exit 0. Catches solo-mode setups where the env var
#      didn't propagate to Claude's Bash subprocesses, and post
#      `gh auth refresh` recoveries that flipped the active account to
#      personal. Both are present because env vars and keyring state can
#      diverge in real-world scenarios; the keyring is the reliable signal
#      when they conflict. See UPSTREAM-HANDOFF.md Issue #4 Fix B.
#

set -euo pipefail

# Solo mode: when AGILE_FLOW_SOLO_MODE=true (set via env or shell rc),
# the hook is a no-op. Used for workshops and tutorials where one
# attendee plays both worker and reviewer roles under their own
# GitHub identity. Production teams that want separation-of-duties
# leave this unset and rely on the worker/reviewer bot accounts below.
if [[ "${AGILE_FLOW_SOLO_MODE:-false}" == "true" ]]; then
  exit 0
fi

WORKER_ACCOUNT="${AGILE_FLOW_WORKER_ACCOUNT:-va-worker}"
REVIEWER_ACCOUNT="${AGILE_FLOW_REVIEWER_ACCOUNT:-va-reviewer}"

# Read JSON input from stdin
input=$(cat)

# Extract tool name and command (for Bash tool)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
tool_command=$(echo "$input" | jq -r '.tool_input.command // empty')

# Determine required account based on tool
required_account=""
case "$tool_name" in
  Bash)
    case "$tool_command" in
      *"gh pr create"*)
        required_account="$WORKER_ACCOUNT"
        ;;
      *"gh pr review"*)
        required_account="$REVIEWER_ACCOUNT"
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac

# Get current active account. Fail-open: with `set -o pipefail`, an
# empty/unparsable `gh auth status` would otherwise kill the hook
# with exit 1 and block the tool call. The self-heal block below and
# the existing switch logic both handle empty `current_account`
# gracefully, so we'd rather get an empty value than die here.
current_account=$(gh auth status 2>&1 | grep -B2 "Active account: true" | grep "Logged in to" | sed 's/.*account \([^ ]*\).*/\1/' || true)

# Self-healing safety net (#85). If the active account is not one of
# the configured bots, the user is on a personal account on purpose
# (solo mode without env-var propagation, or post `gh auth refresh`
# recovery). Respect that and exit 0 — don't undo their state.
#
# Two real-world scenarios where this fires:
#   1. User ran scripts/setup-solo-mode.sh AFTER starting Claude Code.
#      AGILE_FLOW_SOLO_MODE is set in their shell rc, but Claude Code's
#      Bash subprocesses see a snapshot from session start. The
#      env-var fast path at the top of this hook misses; the keyring
#      is the more reliable signal.
#   2. `gh auth refresh` flipped the active account to a personal
#      account during scope recovery. Switching back to a bot here
#      would silently undo the user's manual recovery.
#
# Multi-bot mode is unaffected: a user with $WORKER_ACCOUNT active
# falls through to the existing switch-to-reviewer logic below.
# Fail-open if `gh auth status` returned no parsable account — let
# the existing logic surface the gh-state error rather than blocking
# the tool call here.
# See: docs/UPSTREAM-HANDOFF.md Issue #4 Fix B (originating fork's
# 2026-04-30 dry-run).
if [[ -n "$current_account" ]] \
  && [[ "$current_account" != "$WORKER_ACCOUNT" ]] \
  && [[ "$current_account" != "$REVIEWER_ACCOUNT" ]]; then
  echo "[ensure-github-account] Active account '$current_account' is not a configured bot ($WORKER_ACCOUNT/$REVIEWER_ACCOUNT); not switching for $tool_name" >&2
  exit 0
fi

# Switch if needed
if [[ "$current_account" != "$required_account" ]]; then
  echo "Switching GitHub account from '$current_account' to '$required_account' for $tool_name" >&2

  if gh auth switch --user "$required_account" 2>&1; then
    echo "Successfully switched to $required_account" >&2
  else
    echo "ERROR: Failed to switch to $required_account account" >&2
    echo "Please ensure $required_account is authenticated: gh auth login --user $required_account" >&2
    exit 2
  fi
fi

exit 0
