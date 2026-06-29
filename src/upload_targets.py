"""Upload target registry for NEXUS video publishing pipeline."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

SERVICE_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = SERVICE_ROOT / "scripts"


@dataclass(frozen=True)
class UploadTarget:
    name: str
    platform: str
    upload_script: Path
    analyze_script: Path | None
    applescript: Path | None
    default_privacy: str
    supported_extensions: tuple[str, ...]


UPLOAD_TARGETS: dict[str, UploadTarget] = {
    "tiktok": UploadTarget(
        name="tiktok",
        platform="tiktok",
        upload_script=SCRIPTS_DIR / "tiktok-cursor-upload.sh",
        analyze_script=SCRIPTS_DIR / "tiktok-media-analyze.py",
        applescript=SCRIPTS_DIR / "tiktok-upload.scpt",
        default_privacy="private",
        supported_extensions=(".mp4", ".mov", ".m4v", ".webm", ".mkv", ".avi"),
    ),
    "youtube": UploadTarget(
        name="youtube",
        platform="youtube",
        upload_script=Path("/workspace/scripts/youtube-cursor-upload.sh"),
        analyze_script=Path("/workspace/scripts/youtube-media-analyze.py"),
        applescript=None,
        default_privacy="private",
        supported_extensions=(".mp4", ".mov", ".m4v", ".webm", ".mkv", ".avi", ".jpg", ".jpeg", ".png"),
    ),
}


def get_upload_target(name: str) -> UploadTarget:
    key = name.lower().strip()
    if key not in UPLOAD_TARGETS:
        raise KeyError(f"Unknown upload target: {name}")
    return UPLOAD_TARGETS[key]


def list_upload_targets() -> list[str]:
    return sorted(UPLOAD_TARGETS.keys())
