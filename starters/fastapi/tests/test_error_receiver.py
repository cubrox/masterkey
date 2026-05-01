import json
import time
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.error_receiver import _is_rate_limited, _parse_sentry_envelope, _recent_issues
from app.main import app

client = TestClient(app)


def _make_sentry_envelope(exc_type: str = "RuntimeError", exc_value: str = "test error") -> bytes:
    """Build a minimal Sentry envelope with exception data."""
    header = json.dumps({"event_id": "abc123", "dsn": "https://key@localhost/0"})
    item_header = json.dumps({"type": "event"})
    payload = json.dumps(
        {
            "exception": {
                "values": [
                    {
                        "type": exc_type,
                        "value": exc_value,
                        "stacktrace": {
                            "frames": [
                                {
                                    "filename": "app/main.py",
                                    "lineno": 28,
                                    "function": "error",
                                    "context_line": "raise RuntimeError('test')",
                                }
                            ]
                        },
                    }
                ]
            },
            "timestamp": "2026-02-18T12:00:00Z",
            "environment": "production",
        }
    )
    return f"{header}\n{item_header}\n{payload}".encode()


class TestReceiveEndpoint:
    def test_valid_envelope_returns_200(self):
        envelope = _make_sentry_envelope()
        with patch("app.error_receiver._create_github_issue", return_value=True):
            response = client.post("/api/error-events", content=envelope)
        assert response.status_code == 200
        assert response.json()["id"] == "accepted"

    def test_valid_envelope_with_project_id_returns_200(self):
        envelope = _make_sentry_envelope()
        with patch("app.error_receiver._create_github_issue", return_value=True):
            response = client.post("/api/error-events/0", content=envelope)
        assert response.status_code == 200

    def test_malformed_payload_returns_200(self):
        response = client.post("/api/error-events", content=b"not a valid envelope")
        assert response.status_code == 200
        assert response.json()["id"] == "accepted"

    def test_empty_body_returns_200(self):
        response = client.post("/api/error-events", content=b"")
        assert response.status_code == 200


class TestParsing:
    def test_parse_valid_envelope(self):
        envelope = _make_sentry_envelope("ValueError", "bad input")
        result = _parse_sentry_envelope(envelope)
        assert result is not None
        assert result["type"] == "ValueError"
        assert result["value"] == "bad input"
        assert "app/main.py" in result["stacktrace"]

    def test_parse_envelope_without_exception(self):
        payload = json.dumps({"message": "just a log"}).encode()
        result = _parse_sentry_envelope(payload)
        assert result is None

    def test_parse_garbage_returns_none(self):
        result = _parse_sentry_envelope(b"\x00\x01\x02binary garbage")
        assert result is None


class TestRateLimiting:
    def setup_method(self):
        _recent_issues.clear()

    def test_first_error_not_rate_limited(self):
        assert _is_rate_limited("new error") is False

    def test_repeat_error_is_rate_limited(self):
        _recent_issues["repeat error"] = time.time()
        assert _is_rate_limited("repeat error") is True

    def test_old_error_not_rate_limited(self):
        _recent_issues["old error"] = time.time() - 7200  # 2 hours ago
        assert _is_rate_limited("old error") is False

    def test_rate_limited_envelope_returns_rate_limited(self):
        _recent_issues["test error"] = time.time()
        envelope = _make_sentry_envelope(exc_value="test error")
        response = client.post("/api/error-events", content=envelope)
        assert response.status_code == 200
        assert response.json()["id"] == "rate_limited"


class TestGitHubIssueCreation:
    def test_creates_issue_when_configured(self):
        envelope = _make_sentry_envelope()
        _recent_issues.clear()

        mock_response = MagicMock()
        mock_response.status = 201
        mock_response.read.return_value = json.dumps({"number": 99}).encode()
        mock_response.__enter__ = MagicMock(return_value=mock_response)
        mock_response.__exit__ = MagicMock(return_value=False)

        with (
            patch.dict("os.environ", {"GITHUB_TOKEN": "fake", "GITHUB_REPOSITORY": "org/repo"}),
            patch("urllib.request.urlopen", return_value=mock_response) as mock_urlopen,
        ):
            response = client.post("/api/error-events", content=envelope)

        assert response.status_code == 200
        # Verify urlopen was called with the right URL
        call_args = mock_urlopen.call_args
        req_obj = call_args[0][0]
        assert "org/repo" in req_obj.full_url
        # Verify the issue body contains bug:auto label
        payload = json.loads(req_obj.data)
        assert "bug:auto" in payload["labels"]

    def test_skips_issue_when_no_token(self):
        envelope = _make_sentry_envelope()
        _recent_issues.clear()

        with patch.dict("os.environ", {}, clear=True):
            # Remove GITHUB_TOKEN if present
            import os

            os.environ.pop("GITHUB_TOKEN", None)
            os.environ.pop("GITHUB_REPOSITORY", None)
            response = client.post("/api/error-events", content=envelope)

        assert response.status_code == 200
        assert response.json()["id"] == "accepted"
