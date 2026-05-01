#!/bin/bash

# Validate agent policies
# Ensures agents have clear boundaries and don't overlap responsibilities

set -e

AGENTS_DIR=".claude/agents"
ERRORS=0

echo "Validating agent policies..."
echo ""

# Track which agents exist
declare -a AGENTS

for file in "$AGENTS_DIR"/*.md; do
    if [ ! -f "$file" ]; then
        continue
    fi

    filename=$(basename "$file" .md)
    AGENTS+=("$filename")
    file_errors=0

    # Check agent has clear "Cannot" boundaries
    cannot_count=$(grep -ciE "(cannot|must not|never|forbidden|prohibited)" "$file" || true)
    cannot_count=${cannot_count:-0}
    if [ "$cannot_count" -lt 2 ]; then
        echo "WARN: $filename - Few boundary constraints found ($cannot_count). Consider adding more 'cannot/must not' rules."
    fi

    # Check for handoff documentation (how this agent interacts with others)
    if ! grep -qiE "(handoff|hands off|passes to|receives from|workflow)" "$file"; then
        echo "WARN: $filename - No handoff/workflow documentation found"
    fi

    # Check for tool/capability documentation
    if ! grep -qiE "(tool|capability|can do|able to|access)" "$file"; then
        echo "WARN: $filename - No tools/capabilities documented"
    fi

    # Verify no agent claims to be able to merge PRs (only humans can)
    # Skip if mentions are about "merged PRs" (past tense, describing state) or explicit denial
    if grep -qiE "merge.*pr|merge.*pull" "$file"; then
        # Check if file explicitly denies merge ability OR only mentions merged (past tense)
        if grep -qiE "(cannot|must not|never|human does).*merge" "$file"; then
            : # OK - explicitly denies merge ability
        elif grep -qiE "merged pr|merged pull|closed/merged|after.*merged" "$file" && ! grep -qiE "will merge|can merge|merge the pr" "$file"; then
            : # OK - only mentions merged PRs (past tense/state)
        else
            echo "FAIL: $filename - Mentions merging PRs but doesn't explicitly forbid it"
            file_errors=$((file_errors + 1))
        fi
    fi

    if [ $file_errors -eq 0 ]; then
        echo "PASS: $filename"
    else
        ERRORS=$((ERRORS + file_errors))
    fi
done

echo ""

# Summary of agents found
echo "Agents found: ${#AGENTS[@]}"
for agent in "${AGENTS[@]}"; do
    echo "  - $agent"
done

echo ""
if [ $ERRORS -gt 0 ]; then
    echo "FAILED: $ERRORS policy issue(s) found"
    exit 1
else
    echo "SUCCESS: All agent policies valid"
    exit 0
fi
