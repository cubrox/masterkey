#!/bin/bash

# Validate agent configuration files have required sections
# Each agent must define: Role description, what they own, what they cannot do

set -e

AGENTS_DIR=".claude/agents"
ERRORS=0

echo "Validating agent files..."
echo ""

for file in "$AGENTS_DIR"/*.md; do
    if [ ! -f "$file" ]; then
        continue
    fi

    filename=$(basename "$file")
    file_errors=0

    # Check for Role section (# Role, ## Role, or role description at start)
    if ! grep -qiE "^#+ *(Role|Agent Role|Overview)" "$file"; then
        # Check if file starts with a role-like description
        if ! head -20 "$file" | grep -qiE "(agent|role|responsible for)"; then
            echo "WARN: $filename - No clear Role section found"
        fi
    fi

    # Check for Owns/Responsibilities section
    # Accept various patterns: explicit sections, inline mentions, or capability descriptions
    if ! grep -qiE "^#+ *(Owns|Responsibilities|What .* Owns|Core Capabilities|Primary)" "$file"; then
        if ! grep -qiE "(owns|responsible for|in charge of|will do|should do|handles|manages)" "$file"; then
            echo "WARN: $filename - No clear ownership/responsibilities definition"
        fi
    fi

    # Check for Cannot Do/Limitations section
    # Accept various patterns: explicit sections, inline limitations, or boundary mentions
    if ! grep -qiE "^#+ *(Cannot|Limitations|Restrictions|Boundaries|Important)" "$file"; then
        if ! grep -qiE "(cannot|must not|should not|forbidden|prohibited|do not|don't|never|only human)" "$file"; then
            echo "WARN: $filename - No clear limitations/boundaries definition"
        fi
    fi

    # Check file is not empty
    if [ ! -s "$file" ]; then
        echo "FAIL: $filename - File is empty"
        file_errors=$((file_errors + 1))
    fi

    # Check minimum content length (at least 500 chars for a proper agent def)
    char_count=$(wc -c < "$file" | tr -d ' ')
    if [ "$char_count" -lt 500 ]; then
        echo "FAIL: $filename - Agent definition too short ($char_count chars, minimum 500)"
        file_errors=$((file_errors + 1))
    fi

    if [ $file_errors -eq 0 ]; then
        echo "PASS: $filename"
    else
        ERRORS=$((ERRORS + file_errors))
    fi
done

echo ""
if [ $ERRORS -gt 0 ]; then
    echo "FAILED: $ERRORS issue(s) found in agent files"
    exit 1
else
    echo "SUCCESS: All agent files valid"
    exit 0
fi
