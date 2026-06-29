#!/usr/bin/env python3
"""Analyze media files and generate TikTok upload metadata as JSON.

Usage:
  tiktok-media-analyze.py /path/to/video.mp4 --account "@myhandle"
  tiktok-media-analyze.py /path/to/video.mp4 --title-hint "drone flight" --pretty

Outputs JSON with media analysis + caption, hashtags, privacy, upload_path.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

VIDEO_EXT = {".mp4", ".mov", ".m4v", ".webm", ".mkv", ".avi"}
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".gif"}


def run_cmd(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


def ffprobe_json(path: Path) -> dict:
    proc = run_cmd([
        "ffprobe", "-v", "quiet", "-print_format", "json",
        "-show_format", "-show_streams", str(path),
    ])
    if proc.returncode != 0:
        return {}
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {}


def analyze_video(path: Path) -> dict:
    data = ffprobe_json(path)
    duration = 0.0
    width = height = 0

    fmt = data.get("format", {})
    if fmt.get("duration"):
        duration = float(fmt["duration"])

    for stream in data.get("streams", []):
        if stream.get("codec_type") == "video" and not width:
            width = int(stream.get("width") or 0)
            height = int(stream.get("height") or 0)

    is_vertical = height > width if width and height else True
    return {
        "media_kind": "video",
        "duration": duration,
        "width": width,
        "height": height,
        "is_vertical": is_vertical,
        "upload_type": "video",
    }


def analyze_image(path: Path) -> dict:
    return {
        "media_kind": "image",
        "duration": 0.0,
        "width": 0,
        "height": 0,
        "is_vertical": True,
        "upload_type": "photo",
    }


def build_caption(title_hint: str, account: str, media_info: dict) -> str:
    base = title_hint.strip() or Path(media_info.get("source_name", "clip")).stem.replace("_", " ").title()
    if account and not account.startswith("@"):
        account = f"@{account}"
    suffix = f" {account}" if account else ""
    return f"{base}{suffix}".strip()


def build_hashtags(title_hint: str, media_info: dict) -> list[str]:
    tags = ["#fyp", "#foryou", "#viral"]
    words = [w for w in title_hint.lower().split() if len(w) > 2][:3]
    tags.extend(f"#{w}" for w in words)
    if media_info.get("is_vertical"):
        tags.append("#vertical")
    return list(dict.fromkeys(tags))[:10]


def analyze_media(path: Path, account: str, title_hint: str, privacy: str) -> dict:
    ext = path.suffix.lower()
    if ext in VIDEO_EXT:
        media_info = analyze_video(path)
    elif ext in IMAGE_EXT:
        media_info = analyze_image(path)
    else:
        raise SystemExit(f"Unsupported media type: {ext}")

    media_info["source_name"] = path.name
    caption = build_caption(title_hint, account, media_info)
    hashtags = build_hashtags(title_hint or path.stem, media_info)

    return {
        "platform": "tiktok",
        "account": account,
        "title": caption[:150],
        "caption": caption,
        "hashtags": hashtags,
        "privacy_default": privacy,
        "upload_path": str(path.resolve()),
        "upload_type": media_info["upload_type"],
        "media": media_info,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate TikTok upload metadata JSON")
    parser.add_argument("media", type=Path, help="Path to video or image")
    parser.add_argument("--account", default="", help="TikTok handle (e.g. @myhandle)")
    parser.add_argument("--title-hint", default="", help="Optional caption/title hint")
    parser.add_argument("--privacy", default="private", choices=["public", "friends", "private"])
    parser.add_argument("--pretty", action="store_true", help="Pretty-print JSON")
    args = parser.parse_args()

    if not args.media.exists():
        raise SystemExit(f"Media not found: {args.media}")

    result = analyze_media(args.media.resolve(), args.account, args.title_hint, args.privacy)
    indent = 2 if args.pretty else None
    print(json.dumps(result, indent=indent))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
