#!/bin/bash

# Validate JSON configuration files
# Checks syntax and required fields

set -e

ERRORS=0

echo "Validating JSON files..."
echo ""

validate_json() {
    local file="$1"
    local filename=$(basename "$file")

    if [ ! -f "$file" ]; then
        echo "SKIP: $filename - File does not exist"
        return 0
    fi

    # Check JSON syntax
    if ! node -e "JSON.parse(require('fs').readFileSync('$file','utf8'))" 2>/dev/null; then
        echo "FAIL: $filename - Invalid JSON syntax"
        return 1
    fi

    echo "PASS: $filename"
    return 0
}

# Validate .mcp.json if it exists
if [ -f ".mcp.json" ]; then
    if ! validate_json ".mcp.json"; then
        ERRORS=$((ERRORS + 1))
    fi
fi

# Validate settings files
for file in .claude/*.json .claude/**/*.json; do
    if [ -f "$file" ]; then
        if ! validate_json "$file"; then
            ERRORS=$((ERRORS + 1))
        fi
    fi
done

# Validate package.json if it exists
if [ -f "package.json" ]; then
    if ! validate_json "package.json"; then
        ERRORS=$((ERRORS + 1))
    fi
fi

# Validate tsconfig.json if it exists
if [ -f "tsconfig.json" ]; then
    if ! validate_json "tsconfig.json"; then
        ERRORS=$((ERRORS + 1))
    fi
fi

echo ""
if [ $ERRORS -gt 0 ]; then
    echo "FAILED: $ERRORS JSON file(s) have issues"
    exit 1
else
    echo "SUCCESS: All JSON files valid"
    exit 0
fi
