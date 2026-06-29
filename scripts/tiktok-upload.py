#!/usr/bin/env python3
"""TikTok upload driver — invokes Chrome automation scripts or dry-run plan.

Usage:
  tiktok-upload.py --video path/to/file.mp4 --meta path/to/metadata.json
  tiktok-upload.py --video path/to/file.mp4 --dry-run
  tiktok-upload.py --analyze-only path/to/file.mp4 --account @myhandle
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent
UPLOAD_SH = SCRIPTS_DIR / "tiktok-cursor-upload.sh"
ANALYZE_PY = SCRIPTS_DIR / "tiktok-media-analyze.py"


def load_meta(path: Path) -> dict:
    text = path.read_text()
    if path.suffix in {".yaml", ".yml"}:
        try:
            import yaml  # type: ignore
        except ImportError as exc:
            raise SystemExit("Install PyYAML for YAML sidecars: pip install pyyaml") from exc
        return yaml.safe_load(text) or {}
    return json.loads(text)


def run_upload(
    video_path: Path,
    meta: dict | None = None,
    *,
    dry_run: bool = False,
    no_publish: bool = False,
    privacy: str = "private",
    account: str = "",
) -> int:
    cmd = [str(UPLOAD_SH)]
    if dry_run:
        cmd.append("--dry-run")
    if no_publish:
        cmd.append("--no-publish")
    if account:
        cmd.extend(["--account", account])
    if privacy:
        cmd.extend(["--privacy", privacy])
    cmd.append(str(video_path))

    env = os.environ.copy()
    if meta:
        meta_file = video_path.parent / "tiktok-meta-override.json"
        meta_file.write_text(json.dumps(meta, indent=2))
        env["TIKTOK_META_OVERRIDE"] = str(meta_file)

    proc = subprocess.run(cmd, env=env)
    return proc.returncode


def main() -> int:
    parser = argparse.ArgumentParser(description="Upload a video to TikTok via Chrome automation")
    parser.add_argument("--video", type=Path, help="Path to video file")
    parser.add_argument("--meta", type=Path, help="JSON/YAML metadata sidecar")
    parser.add_argument("--analyze-only", type=Path, help="Analyze media and print metadata JSON")
    parser.add_argument("--account", default="", help="TikTok handle")
    parser.add_argument("--privacy", default="private", choices=["public", "friends", "private"])
    parser.add_argument("--dry-run", action="store_true", help="Plan steps without Chrome automation")
    parser.add_argument("--no-publish", action="store_true", help="Fill metadata but skip publish")
    args = parser.parse_args()

    if args.analyze_only:
        cmd = [sys.executable, str(ANALYZE_PY), str(args.analyze_only), "--pretty"]
        if args.account:
            cmd.extend(["--account", args.account])
        cmd.extend(["--privacy", args.privacy])
        return subprocess.call(cmd)

    if not args.video:
        parser.error("--video is required unless --analyze-only")

    meta = load_meta(args.meta) if args.meta else None
    return run_upload(
        args.video,
        meta,
        dry_run=args.dry_run,
        no_publish=args.no_publish,
        privacy=args.privacy,
        account=args.account,
    )


if __name__ == "__main__":
    raise SystemExit(main())
