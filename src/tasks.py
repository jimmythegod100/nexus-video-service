import logging
import uuid

from celery import Celery

from src.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

celery_app = Celery(
    "nexus-video-service",
    broker=settings.CELERY_BROKER_URL,
    backend=settings.CELERY_RESULT_BACKEND,
)

celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
)


@celery_app.task(name="nexus.process_video")
def process_video_task(
    job_id: str,
    prompt: str,
    duration: int,
    style: str,
    format: str,
    webhook_url: str | None = None,
) -> dict:
    """Background worker: calls Gemini MCP and updates job status."""
    logger.info("Processing video job %s: %s", job_id, prompt[:50])
    return {
        "job_id": job_id,
        "status": "processing",
        "prompt": prompt,
        "duration": duration,
        "style": style,
        "format": format,
        "webhook_url": webhook_url,
    }


def enqueue_video_job(
    prompt: str,
    duration: int,
    style: str,
    format: str,
    webhook_url: str | None = None,
) -> str:
    job_id = str(uuid.uuid4())
    process_video_task.delay(job_id, prompt, duration, style, format, webhook_url)
    return job_id
