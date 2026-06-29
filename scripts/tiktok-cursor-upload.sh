#!/usr/bin/env bash
# End-to-end TikTok upload from Cursor: analyze media → Chrome upload → fill → publish.
#
# Usage:
#   tiktok-cursor-upload.sh /path/to/media.mp4 [--account "@myhandle"] \
#     [--privacy public|friends|private] [--title-hint "..."] \
#     [--dry-run] [--no-publish]
set -euo pipefail

UPLOAD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${UPLOAD_SCRIPT_DIR}/lib"
NEXUS_ROOT="$(cd "${UPLOAD_SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${NEXUS_ROOT}/logs"
PROCESSING_DIR="${NEXUS_ROOT}/processing"

# shellcheck source=lib/chrome-tiktok-common.sh
source "${LIB_DIR}/chrome-tiktok-common.sh"
# shellcheck source=lib/chrome-tiktok-open.sh
source "${LIB_DIR}/chrome-tiktok-open.sh"
# shellcheck source=lib/chrome-tiktok-select-file.sh
source "${LIB_DIR}/chrome-tiktok-select-file.sh"
# shellcheck source=lib/chrome-tiktok-fill.sh
source "${LIB_DIR}/chrome-tiktok-fill.sh"
# shellcheck source=lib/chrome-tiktok-publish.sh
source "${LIB_DIR}/chrome-tiktok-publish.sh"

ANALYZE_PY="${UPLOAD_SCRIPT_DIR}/tiktok-media-analyze.py"

MEDIA_PATH=""
ACCOUNT=""
PRIVACY="private"
TITLE_HINT=""
DRY_RUN=0
NO_PUBLISH=0

SUPPORTED_MEDIA_EXT=(
  .mp4 .mov .m4v .webm .mkv .avi
  .jpg .jpeg .png .webp .heic .gif
)

media_extension() {
  local base ext
  base="$(basename "$1")"
  ext="${base##*.}"
  if [[ "$ext" == "$base" || -z "$ext" ]]; then
    echo ""
  else
    echo ".${ext,,}"
  fi
}

validate_media_path() {
  local path="$1"
  local ext

  if [[ ! -e "$path" ]]; then
    log_err "Media file not found: $path"
    exit 1
  fi
  if [[ ! -f "$path" ]]; then
    log_err "Media path is not a regular file: $path"
    exit 1
  fi
  if [[ ! -r "$path" ]]; then
    log_err "Media file is not readable: $path"
    exit 3
  fi

  ext="$(media_extension "$path")"
  local supported=0
  local e
  for e in "${SUPPORTED_MEDIA_EXT[@]}"; do
    if [[ "$ext" == "$e" ]]; then
      supported=1
      break
    fi
  done
  if [[ "$supported" -eq 0 ]]; then
    log_err "Unsupported media type ($ext): $path"
    exit 2
  fi
}

usage() {
  cat <<EOF
Usage: $(basename "$0") /path/to/media [options]

Options:
  --account HANDLE   TikTok account handle (e.g. @myhandle)
  --privacy LEVEL    public|friends|private (default: private)
  --title-hint TEXT  Optional caption/title hint
  --dry-run          Analyze + log steps; no Chrome automation
  --no-publish       Fill metadata but stop before final Post click
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --account) ACCOUNT="$2"; shift 2 ;;
    --privacy) PRIVACY="$2"; shift 2 ;;
    --title-hint) TITLE_HINT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-publish) NO_PUBLISH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) log_err "Unknown option: $1"; usage; exit 1 ;;
    *)
      if [[ -z "$MEDIA_PATH" ]]; then
        MEDIA_PATH="$1"
      else
        log_err "Unexpected argument: $1"
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$MEDIA_PATH" ]]; then
  usage
  exit 1
fi

validate_media_path "$MEDIA_PATH"

MEDIA_PATH="$(cd "$(dirname "$MEDIA_PATH")" && pwd)/$(basename "$MEDIA_PATH")"
RUN_ID="$(date '+%Y%m%d-%H%M%S')-$(basename "$MEDIA_PATH" | tr ' ' '-' | tr -cd '[:alnum:]._-' | sed 's/[._-]*$//' | cut -c1-40)"
RUN_DIR="${PROCESSING_DIR}/${RUN_ID}"
mkdir -p "$RUN_DIR" "$LOG_DIR"

log "=== TikTok Cursor Upload START ==="
log "Media: $MEDIA_PATH"
log "Account: ${ACCOUNT:-n/a} | Privacy: $PRIVACY | Dry-run: $DRY_RUN | No-publish: $NO_PUBLISH"

PROC_MEDIA="${RUN_DIR}/$(basename "$MEDIA_PATH")"
cp -f "$MEDIA_PATH" "$PROC_MEDIA"
log "Copied to processing: $PROC_MEDIA"

ANALYZE_ARGS=(--privacy "$PRIVACY" --pretty)
[[ -n "$ACCOUNT" ]] && ANALYZE_ARGS+=(--account "$ACCOUNT")
[[ -n "$TITLE_HINT" ]] && ANALYZE_ARGS+=(--title-hint "$TITLE_HINT")

log "Analyzing media and generating metadata..."
if ! META_JSON=$("$ANALYZE_PY" "$PROC_MEDIA" "${ANALYZE_ARGS[@]}"); then
  log_err "Media analysis failed"
  exit 4
fi
META_FILE="${RUN_DIR}/metadata.json"
printf '%s\n' "$META_JSON" > "$META_FILE"
log "Metadata saved: $META_FILE"

UPLOAD_PATH=$(json_get "$META_JSON" "upload_path")
CAPTION=$(json_get "$META_JSON" "caption")
log "Upload path: $UPLOAD_PATH | Caption: $CAPTION"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY-RUN — planned steps:"
  echo "  1. Open TikTok Creator Center upload in Chrome"
  echo "  2. Select file: $UPLOAD_PATH"
  echo "  3. Wait for processing"
  echo "  4. Fill caption from $META_FILE"
  echo "  5. Set visibility: $PRIVACY"
  if [[ "$NO_PUBLISH" -eq 1 ]]; then
    echo "  6. STOP before Post (--no-publish)"
  else
    echo "  6. Click Post"
  fi
  printf '%s\n' "$META_JSON" | python3 -m json.tool
  log "=== DRY-RUN complete ==="
  exit 0
fi

open_tiktok_upload
select_tiktok_upload_file "$UPLOAD_PATH"
wait_for_upload_processing 600
fill_tiktok_metadata "$META_JSON" "$PRIVACY"

VIDEO_URL=""
if [[ "$NO_PUBLISH" -eq 0 ]]; then
  VIDEO_URL=$(publish_tiktok_upload "$PRIVACY" 0 "$META_JSON" || true)
else
  publish_tiktok_upload "$PRIVACY" 1 "$META_JSON" || true
  log "Filled metadata; stopped before publish (--no-publish)"
fi

RESULT_FILE="${RUN_DIR}/result.json"
python3 - <<PY
import json
from pathlib import Path
meta = json.loads(Path("$META_FILE").read_text())
out = {
    "status": "ok",
    "platform": "tiktok",
    "caption": meta.get("caption"),
    "upload_path": meta.get("upload_path"),
    "privacy": "$PRIVACY",
    "video_url": "$VIDEO_URL".strip() or None,
    "metadata_file": "$META_FILE",
    "no_publish": bool($NO_PUBLISH),
}
Path("$RESULT_FILE").write_text(json.dumps(out, indent=2))
print(json.dumps(out, indent=2))
PY

log "=== TikTok Cursor Upload DONE ==="
if [[ -n "$VIDEO_URL" && "$VIDEO_URL" != "missing value" ]]; then
  echo ""
  echo "TikTok URL: $VIDEO_URL"
fi
