#!/bin/bash

# Validate shell scripts
# Runs shellcheck and syntax validation

set -e

ERRORS=0

echo "Validating shell scripts..."
echo ""

# Find all .sh files using process substitution to avoid SC2044
while IFS= read -r -d '' file; do
    filename=$(basename "$file")
    file_errors=0

    # Check bash syntax
    if ! bash -n "$file" 2>/dev/null; then
        echo "FAIL: $filename - Bash syntax error"
        file_errors=$((file_errors + 1))
    fi

    # Run shellcheck if available
    if command -v shellcheck &> /dev/null; then
        # Excluded warnings:
        # SC1091: Don't follow sourced files (they may not exist in CI)
        # SC2001: Use ${variable//search/replace} instead of sed (style preference)
        # SC2002: Useless cat (style preference, often more readable with cat)
        # SC2034: Allow unused variables (may be used by sourcing scripts)
        # SC2064: Use single quotes for trap (we intentionally want early expansion)
        # SC2086: Double quote to prevent globbing (often intentional)
        # SC2155: Declare and assign separately (acceptable for simple cases)
        # SC2162: read without -r (acceptable for simple scripts)
        # SC2317: Unreachable code (often trap handlers)
        if ! shellcheck -e SC1091 -e SC2001 -e SC2002 -e SC2034 -e SC2064 -e SC2086 -e SC2155 -e SC2162 -e SC2317 "$file" 2>/dev/null; then
            echo "FAIL: $filename - Shellcheck issues found"
            shellcheck -e SC1091 -e SC2001 -e SC2002 -e SC2034 -e SC2064 -e SC2086 -e SC2155 -e SC2162 -e SC2317 "$file" 2>&1 | head -20
            file_errors=$((file_errors + 1))
        fi
    fi

    # Check for executable permission (warn only)
    if [ ! -x "$file" ]; then
        echo "WARN: $filename - Not executable (consider chmod +x)"
    fi

    if [ $file_errors -eq 0 ]; then
        echo "PASS: $filename"
    else
        ERRORS=$((ERRORS + file_errors))
    fi
done < <(find . -name "*.sh" -type f ! -path "./.git/*" ! -path "./node_modules/*" -print0)

echo ""
if [ $ERRORS -gt 0 ]; then
    echo "FAILED: $ERRORS script(s) have issues"
    exit 1
else
    echo "SUCCESS: All shell scripts valid"
    exit 0
fi
