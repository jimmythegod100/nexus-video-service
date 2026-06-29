import uuid
from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class VideoStyle(str, Enum):
    CINEMATIC = "cinematic"
    DOCUMENTARY = "documentary"
    ARTISTIC = "artistic"
    EDUCATIONAL = "educational"


class VideoFormat(str, Enum):
    MP4 = "mp4"
    WEBM = "webm"
    MOV = "mov"


class VideoGenerateRequest(BaseModel):
    prompt: str = Field(..., min_length=10, max_length=1000)
    duration: int = Field(..., ge=5, le=300)
    style: VideoStyle = VideoStyle.CINEMATIC
    format: VideoFormat = VideoFormat.MP4
    webhook_url: Optional[str] = None
    agent_id: Optional[str] = "video-generator-agent"


class VideoGenerateResponse(BaseModel):
    job_id: str
    status: str
    status_url: str
    webhook_url: Optional[str] = None


class JobStatusResponse(BaseModel):
    job_id: str
    status: str
    progress: int = 0
    video_url: Optional[str] = None
    error_message: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class HealthCheckResponse(BaseModel):
    status: str
    service: str
    uptime_seconds: int
    celery_configured: bool
