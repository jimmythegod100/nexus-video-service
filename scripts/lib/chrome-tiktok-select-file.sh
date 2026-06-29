#!/usr/bin/env bash
# Select a local media file in TikTok upload via macOS file picker (CDP + AppleScript).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/chrome-tiktok-common.sh
source "${SCRIPT_DIR}/chrome-tiktok-common.sh"

_SELECT_FILES_JS='
(function() {
  const btn = Array.from(document.querySelectorAll("button, div[role=\"button\"], input[type=file], label"))
    .find(el => /select video|select file|upload video|choose file|drag and drop/i.test(el.innerText || el.textContent || el.getAttribute("aria-label") || ""));
  const input = document.querySelector("input[type=file]");
  const target = btn || input;
  if (!target) return "";
  const r = target.getBoundingClientRect();
  const chromeX = window.outerWidth - window.innerWidth;
  const chromeY = window.outerHeight - window.innerHeight;
  return JSON.stringify({
    x: Math.round(window.screenX + chromeX + r.x + r.width / 2),
    y: Math.round(window.screenY + chromeY + r.y + r.height / 2),
    via: btn ? "button" : "input"
  });
})();'

trigger_file_picker() {
  log "Triggering TikTok file picker (real screen click)..."
  if ! click_element_screen "$_SELECT_FILES_JS"; then
    log "cliclick failed; falling back to JS click..."
    chrome_js '
(function() {
  const btn = Array.from(document.querySelectorAll("button, div[role=\"button\"], input[type=file]"))
    .find(el => /select video|select file|upload video|choose file/i.test(el.innerText || el.textContent || el.getAttribute("aria-label") || ""));
  if (btn) { btn.click(); return "button"; }
  const input = document.querySelector("input[type=file]");
  if (input) { input.click(); return "input"; }
  return "";
})();' || true
  fi
}

select_file_via_dialog() {
  local file_path="$1"
  local dir_path
  dir_path="$(cd "$(dirname "$file_path")" && pwd)"
  local file_name
  file_name="$(basename "$file_path")"

  log "File picker: navigating to $dir_path / $file_name"

  osascript <<APPLESCRIPT
set targetDir to "$dir_path"
set targetFile to "$file_name"

tell application "Google Chrome" to activate
delay 0.4

tell application "System Events"
  tell process "Google Chrome"
    set frontmost to true
    delay 0.3

    try
      click text field 1 of splitter group 1 of sheet 1 of window 1
    on error
      try
        click splitter group 1 of sheet 1 of window 1
      end try
    end try
    delay 0.3

    keystroke "g" using {command down, shift down}
    delay 0.7
    keystroke targetDir
    delay 0.2
    key code 36
    delay 1.0

    keystroke targetFile
    delay 0.5
    key code 36
    delay 0.4

    if (count of sheets of window 1) > 0 then
      try
        click button "Open" of splitter group 1 of sheet 1 of window 1
      on error
        key code 36
      end try
    end if
  end tell
end tell
APPLESCRIPT
}

select_tiktok_upload_file() {
  local file_path="$1"

  if [[ ! -f "$file_path" ]]; then
    log_err "File not found: $file_path"
    return 1
  fi

  file_path="$(cd "$(dirname "$file_path")" && pwd)/$(basename "$file_path")"
  ensure_chrome
  chrome_activate

  local attempt
  for attempt in 1 2 3; do
    trigger_file_picker

    if wait_for_file_dialog 12; then
      log "File dialog open (attempt $attempt)"
      if select_file_via_dialog "$file_path"; then
        log "File selected; waiting for upload form..."
        sleep 2
        if wait_for_js '
(function() {
  const caption = document.querySelector("[contenteditable=\"true\"], textarea, [data-e2e=\"caption-input\"]");
  const progress = /uploading|processing|100%|edit video|post/i.test(document.body.innerText || "");
  return !!(caption || progress);
})();' 90 2; then
          log "TikTok upload form visible"
          return 0
        fi
        log "Upload form not yet visible after file selection"
      fi
    else
      log "File dialog did not appear (attempt $attempt)"
    fi

    sleep 1.5
  done

  log_err "Failed to select file after 3 attempts"
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -lt 1 ]]; then
    echo "Usage: $(basename "$0") /absolute/path/to/media" >&2
    exit 1
  fi
  select_tiktok_upload_file "$1"
fi
