#!/bin/bash

# Validate command files have required frontmatter
# Each command file must have YAML frontmatter with a description

set -e

COMMANDS_DIR=".claude/commands"
ERRORS=0

echo "Validating command files..."
echo ""

for file in "$COMMANDS_DIR"/*.md; do
    if [ ! -f "$file" ]; then
        continue
    fi

    filename=$(basename "$file")

    # Check for YAML frontmatter
    if ! head -1 "$file" | grep -q "^---$"; then
        echo "FAIL: $filename - Missing YAML frontmatter (must start with ---)"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # Extract frontmatter and check for description
    # Use awk for cross-platform compatibility (macOS head -n -1 not supported)
    frontmatter=$(awk '/^---$/{if(++c==2)exit}c==1' "$file")

    if ! echo "$frontmatter" | grep -q "^description:"; then
        echo "FAIL: $filename - Missing 'description' in frontmatter"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # Check description is not empty
    description=$(echo "$frontmatter" | grep "^description:" | sed 's/^description:[[:space:]]*//')
    if [ -z "$description" ]; then
        echo "FAIL: $filename - Empty description"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    echo "PASS: $filename"
done

echo ""
if [ $ERRORS -gt 0 ]; then
    echo "FAILED: $ERRORS command file(s) have issues"
    exit 1
else
    echo "SUCCESS: All command files valid"
    exit 0
fi
