"""TikTok upload integration helpers for nexus-video-service."""
from __future__ import annotations

import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from src.upload_targets import get_upload_target

TIKTOK_TARGET = get_upload_target("tiktok")


@dataclass
class TikTokUploadPlan:
    platform: str
    media_path: str
    upload_script: str
    analyze_script: str | None
    applescript: str | None
    steps: list[str]
    privacy: str

    def to_dict(self) -> dict:
        return {
            "platform": self.platform,
            "media_path": self.media_path,
            "upload_script": self.upload_script,
            "analyze_script": self.analyze_script,
            "applescript": self.applescript,
            "steps": self.steps,
            "privacy": self.privacy,
        }


def validate_media_path(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(f"Media not found: {path}")
    if not path.is_file():
        raise ValueError(f"Media path is not a file: {path}")
    if path.suffix.lower() not in TIKTOK_TARGET.supported_extensions:
        raise ValueError(
            f"Unsupported extension {path.suffix}; supported: {TIKTOK_TARGET.supported_extensions}"
        )


def check_script_availability() -> dict[str, bool]:
    return {
        "upload_script": TIKTOK_TARGET.upload_script.is_file(),
        "analyze_script": bool(
            TIKTOK_TARGET.analyze_script and TIKTOK_TARGET.analyze_script.is_file()
        ),
        "applescript": bool(TIKTOK_TARGET.applescript and TIKTOK_TARGET.applescript.is_file()),
    }


def build_dry_run_plan(
    media_path: Path,
    *,
    privacy: str = "private",
    account: str = "",
    title_hint: str = "",
) -> TikTokUploadPlan:
    validate_media_path(media_path)
    resolved = media_path.resolve()
    steps = [
        "Open TikTok Creator Center upload in Chrome",
        f"Select file: {resolved}",
        "Wait for upload processing",
        "Fill caption and hashtags from metadata",
        f"Set visibility: {privacy}",
        "Click Post (skipped in dry-run)",
    ]
    if account:
        steps.insert(1, f"Account context: {account}")
    if title_hint:
        steps.insert(2, f"Title hint: {title_hint}")

    return TikTokUploadPlan(
        platform="tiktok",
        media_path=str(resolved),
        upload_script=str(TIKTOK_TARGET.upload_script),
        analyze_script=str(TIKTOK_TARGET.analyze_script) if TIKTOK_TARGET.analyze_script else None,
        applescript=str(TIKTOK_TARGET.applescript) if TIKTOK_TARGET.applescript else None,
        steps=steps,
        privacy=privacy,
    )


def analyze_media(
    media_path: Path,
    *,
    account: str = "",
    title_hint: str = "",
    privacy: str = "private",
) -> dict:
    validate_media_path(media_path)
    if not TIKTOK_TARGET.analyze_script or not TIKTOK_TARGET.analyze_script.is_file():
        raise FileNotFoundError(f"Analyze script missing: {TIKTOK_TARGET.analyze_script}")

    cmd = [
        sys.executable,
        str(TIKTOK_TARGET.analyze_script),
        str(media_path.resolve()),
        "--privacy",
        privacy,
    ]
    if account:
        cmd.extend(["--account", account])
    if title_hint:
        cmd.extend(["--title-hint", title_hint])

    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "TikTok media analysis failed")
    return json.loads(proc.stdout)


def run_dry_run_upload(
    media_path: Path,
    *,
    privacy: str = "private",
    account: str = "",
    title_hint: str = "",
) -> dict:
    validate_media_path(media_path)
    if not TIKTOK_TARGET.upload_script.is_file():
        raise FileNotFoundError(f"Upload script missing: {TIKTOK_TARGET.upload_script}")

    cmd = [str(TIKTOK_TARGET.upload_script), "--dry-run", "--privacy", privacy]
    if account:
        cmd.extend(["--account", account])
    if title_hint:
        cmd.extend(["--title-hint", title_hint])
    cmd.append(str(media_path.resolve()))

    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "TikTok dry-run upload failed")

    plan = build_dry_run_plan(
        media_path, privacy=privacy, account=account, title_hint=title_hint
    )
    return {
        "status": "dry_run_ok",
        "plan": plan.to_dict(),
        "stdout": proc.stdout.strip(),
    }
