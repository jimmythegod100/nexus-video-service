import os

import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch

os.environ.setdefault("REDIS_URL", "redis://localhost:6379/0")
os.environ.setdefault("CELERY_BROKER_URL", "redis://localhost:6379/1")
os.environ.setdefault("CELERY_RESULT_BACKEND", "redis://localhost:6379/2")

from src.main import app


@pytest.fixture
def client():
    with patch("src.main.enqueue_video_job", return_value="test-job-id"):
        with TestClient(app) as test_client:
            yield test_client


def test_health_check(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["service"] == "nexus-video-service"


def test_generate_video(client):
    payload = {
        "prompt": "A cinematic drone shot over mountains",
        "duration": 30,
        "style": "cinematic",
        "format": "mp4",
    }
    response = client.post("/v1/video/generate", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["job_id"] == "test-job-id"
    assert data["status"] == "pending"


def test_get_job_status(client):
    client.post(
        "/v1/video/generate",
        json={
            "prompt": "A cinematic drone shot over mountains",
            "duration": 30,
            "style": "cinematic",
            "format": "mp4",
        },
    )
    response = client.get("/v1/video/test-job-id/status")
    assert response.status_code == 200
    assert response.json()["job_id"] == "test-job-id"


def test_invalid_request(client):
    response = client.post(
        "/v1/video/generate",
        json={"prompt": "short", "duration": 1, "style": "cinematic", "format": "mp4"},
    )
    assert response.status_code == 422
