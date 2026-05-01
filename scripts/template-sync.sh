#!/usr/bin/env bash
# template-sync.sh -- Sync framework files from vibeacademy/agile-flow releases.
# Called by .github/workflows/template-sync.yml (workflow_dispatch only).
# Guardrails:
#   - Only syncs directories/files listed in syncDirectories (.agile-flow-version)
#   - Does NOT auto-merge; PR requires human review
#   - Uses unauthenticated GitHub API to fetch release metadata

set -euo pipefail

UPSTREAM_REPO="vibeacademy/agile-flow"
VERSION_FILE=".agile-flow-version"

###############################################################################
# 1. Read local version and syncDirectories
###############################################################################
if [ ! -f "$VERSION_FILE" ]; then
  echo "ERROR: $VERSION_FILE not found."
  exit 1
fi

LOCAL_VERSION=$(python3 -c "import json,sys; print(json.load(open('$VERSION_FILE'))['version'])")
SYNC_DIRS=$(python3 -c "
import json, sys
dirs = json.load(open('$VERSION_FILE')).get('syncDirectories', [])
print('\n'.join(dirs))
")

echo "Local version : $LOCAL_VERSION"
echo "Sync targets  : $SYNC_DIRS"

###############################################################################
# 2. Fetch latest release from GitHub (unauthenticated)
###############################################################################
RELEASE_JSON=$(curl -sf "https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest") || {
  echo "ERROR: Could not fetch latest release from ${UPSTREAM_REPO}."
  exit 1
}

LATEST_VERSION=$(echo "$RELEASE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'].lstrip('v'))")
RELEASE_URL=$(echo "$RELEASE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['html_url'])")
TARBALL_URL=$(echo "$RELEASE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['tarball_url'])")

echo "Latest version: $LATEST_VERSION"

###############################################################################
# 3. Compare versions
###############################################################################
if [ "$LOCAL_VERSION" = "$LATEST_VERSION" ]; then
  echo "No updates available. Local version ($LOCAL_VERSION) matches latest release."
  exit 0
fi

echo "Update available: $LOCAL_VERSION -> $LATEST_VERSION"

###############################################################################
# 4. Download and extract release tarball
###############################################################################
WORK_DIR=$(mktemp -d)
TARBALL="$WORK_DIR/release.tar.gz"

echo "Downloading release tarball..."
curl -sfL "$TARBALL_URL" -o "$TARBALL"
tar -xzf "$TARBALL" -C "$WORK_DIR"

# GitHub tarballs extract into a directory like owner-repo-hash/
EXTRACTED_DIR=$(find "$WORK_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)

if [ -z "$EXTRACTED_DIR" ]; then
  echo "ERROR: Could not find extracted release directory."
  rm -rf "$WORK_DIR"
  exit 1
fi

###############################################################################
# 5. Sync each directory/file from syncDirectories
###############################################################################
FILES_CHANGED=()

while IFS= read -r sync_path; do
  [ -z "$sync_path" ] && continue

  upstream_path="$EXTRACTED_DIR/$sync_path"

  if [ ! -e "$upstream_path" ]; then
    echo "SKIP: $sync_path not found in upstream release."
    continue
  fi

  if [ -d "$upstream_path" ]; then
    # Directory sync: iterate over each file in the upstream directory
    while IFS= read -r file; do
      rel_file="${file#"$upstream_path"/}"
      local_file="$sync_path/$rel_file"
      upstream_file="$file"

      # Create parent directory if needed
      mkdir -p "$(dirname "$local_file")"

      if [ -f "$local_file" ]; then
        if ! diff -q "$upstream_file" "$local_file" >/dev/null 2>&1; then
          cp "$upstream_file" "$local_file"
          git add "$local_file"
          FILES_CHANGED+=("$local_file")
          echo "UPDATED: $local_file"
        fi
      else
        cp "$upstream_file" "$local_file"
        git add "$local_file"
        FILES_CHANGED+=("$local_file")
        echo "ADDED: $local_file"
      fi
    done < <(find "$upstream_path" -type f)
  else
    # Single file sync
    if [ -f "$sync_path" ]; then
      if ! diff -q "$upstream_path" "$sync_path" >/dev/null 2>&1; then
        cp "$upstream_path" "$sync_path"
        git add "$sync_path"
        FILES_CHANGED+=("$sync_path")
        echo "UPDATED: $sync_path"
      fi
    else
      mkdir -p "$(dirname "$sync_path")"
      cp "$upstream_path" "$sync_path"
      git add "$sync_path"
      FILES_CHANGED+=("$sync_path")
      echo "ADDED: $sync_path"
    fi
  fi
done <<< "$SYNC_DIRS"

###############################################################################
# 6. Clean up
###############################################################################
rm -rf "$WORK_DIR"

###############################################################################
# 7. If no files changed, exit
###############################################################################
if [ ${#FILES_CHANGED[@]} -eq 0 ]; then
  echo "Already up to date. All synced files match the latest release."
  exit 0
fi

###############################################################################
# 8. Create branch, commit, and open PR
###############################################################################
SYNC_BRANCH="agile-flow-sync/v${LATEST_VERSION}"

# Check if a branch or PR already exists for this version
if git ls-remote --heads origin "$SYNC_BRANCH" | grep -q "$SYNC_BRANCH"; then
  echo "Branch $SYNC_BRANCH already exists on remote. Skipping PR creation."
  exit 0
fi

git checkout -b "$SYNC_BRANCH"

# Update .agile-flow-version with the new version
python3 -c "
import json
with open('$VERSION_FILE', 'r') as f:
    data = json.load(f)
data['version'] = '$LATEST_VERSION'
with open('$VERSION_FILE', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
git add "$VERSION_FILE"

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

COMMIT_MSG="chore(sync): update Agile Flow framework to v${LATEST_VERSION}"
git commit -m "$COMMIT_MSG"
git push origin "$SYNC_BRANCH"

# Build file list for PR body
FILE_LIST=""
for f in "${FILES_CHANGED[@]}"; do
  FILE_LIST="${FILE_LIST}- \`${f}\`
"
done

PR_BODY="## Agile Flow Framework Update

Updates framework files from \`v${LOCAL_VERSION}\` to \`v${LATEST_VERSION}\`.

### Updated files

${FILE_LIST}
### Release notes

See the full release notes: ${RELEASE_URL}

---
> This PR was created automatically by the template-sync workflow.
> **Please review the changes before merging.**"

gh pr create \
  --title "chore(sync): update Agile Flow framework to v${LATEST_VERSION}" \
  --body "$PR_BODY" \
  --base main \
  --head "$SYNC_BRANCH"

echo "PR created successfully for v${LATEST_VERSION}."
