#!/usr/bin/env bash
#
# Tests for diagnose-cloudrun.sh — the one-shot Cloud Run diagnostic.
#
# The harness stubs `gcloud` so each test fixes a synthetic service
# and revision JSON shape, then asserts that the expected sections
# render and that traps (missing project, placeholder image, stale
# traffic, mismatched latest-ready/latest-created) are surfaced.
#
# Run: ./scripts/diagnose-cloudrun.test.sh

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/diagnose-cloudrun.sh"

new_tmp() { mktemp -d -t diagcrtest-XXXX; }

# Stub builder. Writes a `gcloud` shim that:
#   - For `run services describe`, prints the contents of $tmp/service.json
#   - For `run revisions describe`, prints the contents of $tmp/revision.json
#   - For `logging read`, prints synthetic log lines
#   - Logs every call to $tmp/gcloud.log
make_gcloud_stub() {
  local tmp="$1"
  mkdir -p "$tmp/bin"
  cat > "$tmp/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$tmp/gcloud.log"
case "\$1 \$2" in
  "run services")
    if [[ "\$3" == "describe" ]]; then
      cat "$tmp/service.json"
      exit 0
    fi
    ;;
  "run revisions")
    if [[ "\$3" == "describe" ]]; then
      cat "$tmp/revision.json"
      exit 0
    fi
    ;;
  "logging read")
    cat <<LOGS
2026-04-29T20:14:02Z INFO Uvicorn running on http://0.0.0.0:8080
2026-04-29T20:14:03Z ERROR psycopg.errors.UndefinedTable: relation "todo" does not exist
LOGS
    exit 0
    ;;
esac
exit 1
EOF
  chmod +x "$tmp/bin/gcloud"
}

assert_contains() {
  local needle="$1" haystack_file="$2" label="$3"
  if grep -qF "$needle" "$haystack_file"; then
    echo -e "  ${GREEN}OK${NC} $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $label  (expected to contain: $needle)"
    cat "$haystack_file"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local needle="$1" haystack_file="$2" label="$3"
  if ! grep -qF "$needle" "$haystack_file"; then
    echo -e "  ${GREEN}OK${NC} $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $label  (should NOT contain: $needle)"
    FAIL=$((FAIL + 1))
  fi
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

# ── Test 1: missing project → exit 2 with clear error ───────────────────

echo ""
echo "Test 1: no --project and no GCP_PROJECT_ID env → exit 2"

T1=$(new_tmp)
make_gcloud_stub "$T1"

set +e
PATH="$T1/bin:$PATH" \
  GCP_PROJECT_ID="" \
  bash "$SCRIPT" > "$T1/stdout.log" 2> "$T1/stderr.log"
ec=$?
set -e

assert_eq "2" "$ec" "exit 2 when project unset"
assert_contains "project is required" "$T1/stderr.log" "stderr names the missing input"
assert_contains "Refusing to fall back" "$T1/stderr.log" "explains why no implicit fallback"

# Verify gcloud was never called.
gh_call_count=0
if [[ -f "$T1/gcloud.log" ]]; then
  gh_call_count="$(grep -c '.' "$T1/gcloud.log" 2>/dev/null || true)"
fi
assert_eq "0" "$gh_call_count" "no gcloud calls before pre-flight failure"

# ── Test 2: full happy path → all 5 sections render ─────────────────────

echo ""
echo "Test 2: happy path with synthetic service JSON renders all sections"

T2=$(new_tmp)
make_gcloud_stub "$T2"

cat > "$T2/service.json" <<'JSON'
{
  "metadata": {
    "namespace": "af-test-2026-05x",
    "labels": {"cloud.googleapis.com/location": "us-central1"}
  },
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {"image": "us-central1-docker.pkg.dev/af-test/agile-flow/app:abc1234"}
        ]
      }
    }
  },
  "status": {
    "url": "https://agile-flow-app-xxx-uc.a.run.app",
    "latestReadyRevisionName": "agile-flow-app-00005-abc",
    "latestCreatedRevisionName": "agile-flow-app-00005-abc",
    "traffic": [
      {"percent": 100, "revisionName": "agile-flow-app-00005-abc"}
    ]
  }
}
JSON

cat > "$T2/revision.json" <<'JSON'
{
  "status": {
    "conditions": [
      {"type": "Ready", "status": "True"},
      {"type": "Active", "status": "True"},
      {"type": "ContainerHealthy", "status": "True"}
    ]
  }
}
JSON

set +e
PATH="$T2/bin:$PATH" \
  bash "$SCRIPT" --project=af-test-2026-05x > "$T2/stdout.log" 2> "$T2/stderr.log"
ec=$?
set -e

assert_eq "0" "$ec" "exit 0 on happy path"
assert_contains "=== Cloud Run service: agile-flow-app ===" "$T2/stdout.log" "section 1 header"
assert_contains "=== Traffic split ===" "$T2/stdout.log" "section 2 header"
assert_contains "=== Currently-serving image ===" "$T2/stdout.log" "section 3 header"
assert_contains "=== Latest revision conditions ===" "$T2/stdout.log" "section 4 header"
assert_contains "=== Last 50 log lines ===" "$T2/stdout.log" "section 5 header"
assert_contains "=== End of diagnostic ===" "$T2/stdout.log" "footer marker"

# Section 1 fields
assert_contains "URL:                  https://agile-flow-app-xxx-uc.a.run.app" "$T2/stdout.log" "URL line"
assert_contains "Latest READY:         agile-flow-app-00005-abc" "$T2/stdout.log" "latest-ready line"

# Section 2: 100% traffic, no STALE marker (latest-ready matches)
assert_contains "100% -> agile-flow-app-00005-abc" "$T2/stdout.log" "traffic 100% to current"
assert_not_contains "STALE" "$T2/stdout.log" "no STALE marker when traffic matches latest-ready"

# Section 3: real image, no PLACEHOLDER marker
assert_contains "us-central1-docker.pkg.dev/af-test/agile-flow/app:abc1234" "$T2/stdout.log" "real image rendered"
assert_not_contains "PLACEHOLDER" "$T2/stdout.log" "no PLACEHOLDER marker for real image"

# Section 4: revision conditions
assert_contains "Ready: True" "$T2/stdout.log" "Ready condition"
assert_contains "ContainerHealthy: True" "$T2/stdout.log" "ContainerHealthy condition"

# Section 5: log lines (most-recent-last via `tac`)
assert_contains "Uvicorn running" "$T2/stdout.log" "log line: Uvicorn"
assert_contains "UndefinedTable" "$T2/stdout.log" "log line: error"

# ── Test 3: stale traffic + placeholder image → both markers fire ───────

echo ""
echo "Test 3: stale traffic + placeholder image → STALE and PLACEHOLDER markers"

T3=$(new_tmp)
make_gcloud_stub "$T3"

cat > "$T3/service.json" <<'JSON'
{
  "metadata": {
    "namespace": "af-test-2026-05x",
    "labels": {"cloud.googleapis.com/location": "us-central1"}
  },
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {"image": "us-docker.pkg.dev/cloudrun/container/hello"}
        ]
      }
    }
  },
  "status": {
    "url": "https://agile-flow-app-xxx-uc.a.run.app",
    "latestReadyRevisionName": "agile-flow-app-00005-abc",
    "latestCreatedRevisionName": "agile-flow-app-00005-abc",
    "traffic": [
      {"percent": 100, "revisionName": "agile-flow-app-00001-q7w"}
    ]
  }
}
JSON

cat > "$T3/revision.json" <<'JSON'
{"status": {"conditions": [{"type": "Ready", "status": "True"}]}}
JSON

set +e
PATH="$T3/bin:$PATH" \
  bash "$SCRIPT" --project=af-test-2026-05x > "$T3/stdout.log" 2> "$T3/stderr.log"
ec=$?
set -e

assert_eq "0" "$ec" "exit 0"
assert_contains "STALE" "$T3/stdout.log" "STALE marker on traffic going to non-latest-ready revision"
assert_contains "latest-ready is agile-flow-app-00005-abc" "$T3/stdout.log" "STALE marker names latest-ready"
assert_contains "PLACEHOLDER" "$T3/stdout.log" "PLACEHOLDER marker on cloudrun/container/hello image"

# ── Test 4: latest-created != latest-ready → WARN line fires ────────────

echo ""
echo "Test 4: latest-created != latest-ready → WARN line"

T4=$(new_tmp)
make_gcloud_stub "$T4"

cat > "$T4/service.json" <<'JSON'
{
  "metadata": {"namespace": "p", "labels": {"cloud.googleapis.com/location": "us-central1"}},
  "spec": {"template": {"spec": {"containers": [{"image": "img:tag"}]}}},
  "status": {
    "url": "https://x",
    "latestReadyRevisionName": "rev-00004",
    "latestCreatedRevisionName": "rev-00005",
    "traffic": [{"percent": 100, "revisionName": "rev-00004"}]
  }
}
JSON

cat > "$T4/revision.json" <<'JSON'
{"status": {"conditions": [{"type": "Ready", "status": "True"}]}}
JSON

set +e
PATH="$T4/bin:$PATH" \
  bash "$SCRIPT" --project=p > "$T4/stdout.log" 2> "$T4/stderr.log"
ec=$?
set -e

assert_eq "0" "$ec" "exit 0"
assert_contains "WARN latest-created differs from latest-ready" "$T4/stdout.log" "WARN line on latest-ready/created mismatch"
assert_contains "Latest CREATED:       rev-00005" "$T4/stdout.log" "latest-created shown"
assert_contains "Latest READY:         rev-00004" "$T4/stdout.log" "latest-ready shown"

# ── Test 5: bad arg → exit 2, suggest --help ────────────────────────────

echo ""
echo "Test 5: unknown argument → exit 2"

T5=$(new_tmp)
make_gcloud_stub "$T5"

set +e
PATH="$T5/bin:$PATH" \
  bash "$SCRIPT" --bogus > "$T5/stdout.log" 2> "$T5/stderr.log"
ec=$?
set -e

assert_eq "2" "$ec" "exit 2 on unknown arg"
assert_contains "unknown argument: --bogus" "$T5/stderr.log" "names the bad arg"
# Use grep -F via the helper which already handles `--` poorly; switch to a
# substring grep that tolerates the `--help` literal.
if grep -qE -- "--help" "$T5/stderr.log"; then
  echo -e "  ${GREEN}OK${NC} points at --help"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} points at --help"
  cat "$T5/stderr.log"
  FAIL=$((FAIL + 1))
fi

# ── Test 6: --help exits 0 with usage info ──────────────────────────────

echo ""
echo "Test 6: --help renders usage and exits 0"

T6=$(new_tmp)
make_gcloud_stub "$T6"

set +e
bash "$SCRIPT" --help > "$T6/stdout.log" 2> "$T6/stderr.log"
ec=$?
set -e

assert_eq "0" "$ec" "exit 0 on --help"
assert_contains "Usage:" "$T6/stdout.log" "--help shows Usage"
assert_contains "GCP_PROJECT_ID" "$T6/stdout.log" "--help mentions required env"

# ── Summary ─────────────────────────────────────────────────────────────

echo ""
echo "─────────────────────────────────"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "─────────────────────────────────"

(( FAIL > 0 )) && exit 1
exit 0
