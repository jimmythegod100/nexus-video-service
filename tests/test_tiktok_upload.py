"""Tests for TikTok upload integration modules."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path
from unittest.mock import patch

import pytest

from src.tiktok_upload import (
    analyze_media,
    build_dry_run_plan,
    check_script_availability,
    run_dry_run_upload,
    validate_media_path,
)
from src.upload_targets import get_upload_target, list_upload_targets


def test_list_upload_targets_includes_tiktok():
    targets = list_upload_targets()
    assert "tiktok" in targets
    assert "youtube" in targets


def test_get_upload_target_tiktok():
    target = get_upload_target("tiktok")
    assert target.platform == "tiktok"
    assert target.upload_script.name == "tiktok-cursor-upload.sh"


def test_get_upload_target_unknown():
    with pytest.raises(KeyError, match="Unknown upload target"):
        get_upload_target("vimeo")


def test_check_script_availability():
    status = check_script_availability()
    assert "upload_script" in status
    assert "analyze_script" in status
    assert "applescript" in status


def test_validate_media_path_missing(tmp_path: Path):
    with pytest.raises(FileNotFoundError):
        validate_media_path(tmp_path / "missing.mp4")


def test_validate_media_path_bad_extension(tmp_path: Path):
    bad = tmp_path / "clip.txt"
    bad.write_text("not video")
    with pytest.raises(ValueError, match="Unsupported extension"):
        validate_media_path(bad)


def test_build_dry_run_plan(tmp_path: Path):
    media = tmp_path / "clip.mp4"
    media.write_bytes(b"\x00" * 16)
    plan = build_dry_run_plan(media, privacy="public", account="@test", title_hint="drone")
    data = plan.to_dict()
    assert data["platform"] == "tiktok"
    assert data["privacy"] == "public"
    assert any("drone" in step for step in data["steps"])
    assert any("@test" in step for step in data["steps"])


def test_analyze_media(tmp_path: Path):
    media = tmp_path / "clip.mp4"
    media.write_bytes(b"\x00" * 16)
    result = analyze_media(media, account="@nexus", title_hint="test clip", privacy="private")
    assert result["platform"] == "tiktok"
    assert "#fyp" in result["hashtags"]


def test_run_dry_run_upload(tmp_path: Path):
    media = tmp_path / "clip.mp4"
    media.write_bytes(b"\x00" * 16)
    result = run_dry_run_upload(media, privacy="private", title_hint="sample")
    assert result["status"] == "dry_run_ok"
    assert result["plan"]["platform"] == "tiktok"
    assert "DRY-RUN" in result["stdout"] or "planned steps" in result["stdout"]


def test_analyze_media_failure(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    media = tmp_path / "clip.mp4"
    media.write_bytes(b"\x00" * 16)

    def fake_run(*args, **kwargs):
        return subprocess.CompletedProcess(args=args[0], returncode=1, stdout="", stderr="boom")

    monkeypatch.setattr(subprocess, "run", fake_run)
    with pytest.raises(RuntimeError, match="boom"):
        analyze_media(media)


def test_upload_target_paths_are_under_nexus_scripts():
    target = get_upload_target("tiktok")
    assert "scripts" in str(target.upload_script)
    assert target.analyze_script is not None
    assert target.applescript is not None
