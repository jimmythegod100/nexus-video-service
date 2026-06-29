import logging
import time
from contextlib import asynccontextmanager
from datetime import datetime

from fastapi import FastAPI, HTTPException

from src.config import get_settings, setup_logging
from src.models import HealthCheckResponse, JobStatusResponse, VideoGenerateRequest, VideoGenerateResponse
from src.tasks import enqueue_video_job

logger = logging.getLogger(__name__)
setup_logging()

start_time = time.time()
job_store: dict[str, dict] = {}


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("nexus-video-service started")
    yield
    logger.info("nexus-video-service shutdown")


app = FastAPI(title="NEXUS Video Service", version="0.1.0", lifespan=lifespan)


@app.post("/v1/video/generate", response_model=VideoGenerateResponse)
async def generate_video(req: VideoGenerateRequest):
    try:
        job_id = enqueue_video_job(
            prompt=req.prompt,
            duration=req.duration,
            style=req.style.value,
            format=req.format.value,
            webhook_url=req.webhook_url,
        )
        now = datetime.now()
        job_store[job_id] = {
            "status": "pending",
            "progress": 0,
            "created_at": now,
            "updated_at": now,
        }
        return VideoGenerateResponse(
            job_id=job_id,
            status="pending",
            status_url=f"/v1/video/{job_id}/status",
            webhook_url=req.webhook_url,
        )
    except Exception as e:
        logger.error("generate_video failed: %s", e)
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.get("/v1/video/{job_id}/status", response_model=JobStatusResponse)
async def get_job_status(job_id: str):
    job = job_store.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")
    return JobStatusResponse(
        job_id=job_id,
        status=job["status"],
        progress=job.get("progress", 0),
        video_url=job.get("video_url"),
        error_message=job.get("error_message"),
        created_at=job["created_at"],
        updated_at=job["updated_at"],
    )


@app.get("/health", response_model=HealthCheckResponse)
async def health_check():
    return HealthCheckResponse(
        status="healthy",
        service="nexus-video-service",
        uptime_seconds=int(time.time() - start_time),
        celery_configured=True,
    )


@app.get("/")
async def root():
    return {
        "service": "nexus-video-service",
        "version": "0.1.0",
        "status": "running",
        "endpoints": {
            "health": "/health",
            "generate": "/v1/video/generate",
            "status": "/v1/video/{job_id}/status",
        },
    }


def run() -> None:
    import uvicorn

    settings = get_settings()
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=settings.SERVICE_PORT,
        log_level=settings.LOG_LEVEL.lower(),
    )


if __name__ == "__main__":
    run()
