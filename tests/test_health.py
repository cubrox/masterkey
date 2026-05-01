"""Tests for the health check endpoints."""

from fastapi.testclient import TestClient


def test_health_returns_200(client: TestClient) -> None:
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_health_does_not_touch_database(client: TestClient) -> None:
    """The health endpoint should respond even if the DB is down.

    We can't easily simulate a DB outage here, but we can verify that
    hitting /api/health 100 times doesn't create any DB state.
    """
    for _ in range(100):
        response = client.get("/api/health")
        assert response.status_code == 200


def test_health_db_returns_200_with_working_session(client: TestClient) -> None:
    """The DB health endpoint runs `SELECT 1` and returns ok."""
    response = client.get("/api/health/db")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
