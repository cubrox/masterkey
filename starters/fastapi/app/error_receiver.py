"""Lightweight error event receiver.

Accepts Sentry-format event envelopes and creates GitHub issues labeled
``bug:auto``. This enables zero-config error telemetry for workshops --
no external Sentry account required.

Rate limiting: one issue per unique error message per hour.
"""

import json
import logging
import os
import time
import urllib.request
from typing import Any

from fastapi import APIRouter, Request, Response

logger = logging.getLogger("error_receiver")

router = APIRouter()

# In-memory rate limit: {error_message: timestamp_of_last_issue}
_recent_issues: dict[str, float] = {}
_RATE_LIMIT_SECONDS = 3600  # 1 hour


def _is_rate_limited(error_message: str) -> bool:
    """Return True if an issue for this error was created within the rate limit window."""
    last_created = _recent_issues.get(error_message)
    if last_created is None:
        return False
    return (time.time() - last_created) < _RATE_LIMIT_SECONDS


def _record_issue(error_message: str) -> None:
    """Record that an issue was created for this error message."""
    _recent_issues[error_message] = time.time()
    # Evict stale entries to prevent unbounded growth
    cutoff = time.time() - _RATE_LIMIT_SECONDS
    stale = [k for k, v in _recent_issues.items() if v < cutoff]
    for k in stale:
        del _recent_issues[k]


def _parse_sentry_envelope(body: bytes) -> dict[str, Any] | None:
    """Extract error details from a Sentry envelope.

    Sentry envelopes are newline-delimited: header, item-header, payload.
    We look for the event payload containing exception data.
    """
    try:
        lines = body.split(b"\n")
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
            # Look for exception data in the payload
            if "exception" in data:
                values = data["exception"].get("values", [])
                if values:
                    exc = values[-1]  # Most recent exception in the chain
                    return {
                        "type": exc.get("type", "UnknownError"),
                        "value": exc.get("value", "No message"),
                        "stacktrace": _format_stacktrace(exc.get("stacktrace")),
                        "timestamp": data.get("timestamp", ""),
                        "environment": data.get("environment", "unknown"),
                        "server_name": data.get("server_name", ""),
                    }
    except Exception:
        logger.exception("Failed to parse Sentry envelope")
    return None


def _format_stacktrace(stacktrace: dict[str, Any] | None) -> str:
    """Format a Sentry stacktrace into a readable string."""
    if not stacktrace:
        return "No stacktrace available"
    frames = stacktrace.get("frames", [])
    if not frames:
        return "No stacktrace available"
    lines = []
    for frame in frames[-10:]:  # Last 10 frames
        filename = frame.get("filename", "?")
        lineno = frame.get("lineno", "?")
        function = frame.get("function", "?")
        lines.append(f'  File "{filename}", line {lineno}, in {function}')
        if "context_line" in frame and frame["context_line"]:
            lines.append(f"    {frame['context_line'].strip()}")
    return "\n".join(lines) if lines else "No stacktrace available"


def _create_github_issue(error_info: dict[str, Any]) -> bool:
    """Create a GitHub issue via the REST API. Returns True on success."""
    token = os.getenv("GITHUB_TOKEN")
    repo = os.getenv("GITHUB_REPOSITORY")  # e.g. "vibeacademy/agile-flow"
    if not token:
        logger.warning("GITHUB_TOKEN not set -- cannot create issue from error event")
        return False
    if not repo:
        logger.warning("GITHUB_REPOSITORY not set -- cannot create issue from error event")
        return False

    title = f"bug: {error_info['type']}: {error_info['value'][:80]}"
    body = f"""## Auto-Detected Error

**Type:** `{error_info["type"]}`
**Message:** {error_info["value"]}
**Environment:** {error_info["environment"]}
**Timestamp:** {error_info["timestamp"]}

### Stack Trace

```
{error_info["stacktrace"]}
```

---
*Auto-created by the error receiver. Run `/work-ticket` to fix this bug.*
"""

    payload = json.dumps(
        {
            "title": title,
            "body": body,
            "labels": ["bug:auto"],
        }
    ).encode()

    req = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/issues",
        data=payload,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status == 201:
                result = json.loads(resp.read())
                logger.info("Created GitHub issue #%s for %s", result.get("number"), error_info["type"])
                return True
            logger.warning("GitHub API returned status %s", resp.status)
            return False
    except Exception:
        logger.exception("Failed to create GitHub issue")
        return False


@router.post("/api/error-events/{project_id}")
@router.post("/api/error-events")
async def receive_error_event(request: Request) -> Response:
    """Receive a Sentry-format event envelope and create a GitHub issue.

    Always returns 200 to prevent the Sentry SDK from retrying.
    """
    try:
        body = await request.body()
        error_info = _parse_sentry_envelope(body)

        if error_info is None:
            return Response(content='{"id":"accepted"}', media_type="application/json", status_code=200)

        if _is_rate_limited(error_info["value"]):
            logger.info("Rate-limited: %s (already reported within the last hour)", error_info["type"])
            return Response(content='{"id":"rate_limited"}', media_type="application/json", status_code=200)

        if _create_github_issue(error_info):
            _record_issue(error_info["value"])

    except Exception:
        logger.exception("Error processing event")

    return Response(content='{"id":"accepted"}', media_type="application/json", status_code=200)
