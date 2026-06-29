#!/usr/bin/env bash
# Open TikTok Creator Center upload page in Google Chrome.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/chrome-tiktok-common.sh
source "${SCRIPT_DIR}/chrome-tiktok-common.sh"

TIKTOK_UPLOAD_URL="${TIKTOK_UPLOAD_URL:-https://www.tiktok.com/creator-center/upload?from=upload}"

open_tiktok_upload() {
  ensure_chrome
  local current_url
  current_url=$(chrome_front_url 2>/dev/null || echo "")

  if is_tiktok_upload_page "$current_url"; then
    log "TikTok upload already open: $current_url"
    chrome_activate
    return 0
  fi

  log "Opening TikTok upload: $TIKTOK_UPLOAD_URL"
  osascript <<APPLESCRIPT
tell application "Google Chrome"
  if (count of windows) = 0 then make new window
  set URL of active tab of front window to "$TIKTOK_UPLOAD_URL"
  activate
end tell
APPLESCRIPT

  sleep 3

  if ! wait_for_js 'location.href.includes("tiktok.com") && (location.href.includes("/upload") || location.href.includes("creator-center/upload"))' 45 1; then
    log_err "Failed to reach TikTok upload page"
    return 1
  fi

  log "TikTok upload page ready"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  open_tiktok_upload
fi
