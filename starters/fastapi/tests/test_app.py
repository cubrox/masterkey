import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_returns_200():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_index_returns_html():
    response = client.get("/")
    assert response.status_code == 200
    assert "Agile Flow Starter" in response.text


def test_error_raises_runtime_error():
    with pytest.raises(RuntimeError, match="Deliberate error"):
        client.get("/error")
