# NEXUS Video Service

FastAPI orchestrator for the NEXUS video generation pipeline.

## Quick Start

```bash
poetry install
cp .env.example .env
# Requires Redis + control plane running
poetry run nexus-video-service
```

Service runs on http://localhost:8080

## Endpoints

- POST /v1/video/generate — enqueue a video generation job
- GET /v1/video/{job_id}/status — poll job status
- GET /health — health check

## Background Processing

Uses Celery with Redis broker for async video processing tasks.

```bash
celery -A src.tasks.celery_app worker --loglevel=info
```
