#!/usr/bin/env bash
# Shared helpers for TikTok Creator Center Chrome automation via AppleScript + CDP JS.
set -euo pipefail

_LIB_SOURCE="${BASH_SOURCE[0]:-${0}}"
LIB_DIR="$(cd "$(dirname "${_LIB_SOURCE}")" && pwd)"
SCRIPTS_DIR="$(cd "${LIB_DIR}/.." && pwd)"
NEXUS_ROOT="$(cd "${SCRIPTS_DIR}/.." && pwd)"
LOG_DIR="${NEXUS_ROOT}/logs"
PROCESSING_DIR="${NEXUS_ROOT}/processing"

mkdir -p "$LOG_DIR" "$PROCESSING_DIR"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg"
  echo "$msg" >> "${LOG_DIR}/tiktok-cursor-upload.log"
}

log_err() {
  log "ERROR: $*"
  echo "ERROR: $*" >&2
}

ensure_chrome() {
  if ! pgrep -x "Google Chrome" >/dev/null 2>&1; then
    log "Launching Google Chrome..."
    open -a "Google Chrome"
    sleep 2
  fi
}

chrome_js() {
  local js="$1"
  osascript <<APPLESCRIPT
tell application "Google Chrome"
  return execute front window's active tab javascript $(printf '%s' "$js" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
end tell
APPLESCRIPT
}

chrome_activate() {
  osascript <<'APPLESCRIPT'
tell application "Google Chrome" to activate
APPLESCRIPT
  sleep 0.4
}

chrome_front_url() {
  chrome_js 'location.href'
}

is_tiktok_upload_page() {
  local url="${1:-}"
  if [[ -z "$url" ]]; then
    url=$(chrome_front_url 2>/dev/null || echo "")
  fi
  [[ "$url" == *"tiktok.com"* ]] \
    && { [[ "$url" == *"/upload"* ]] || [[ "$url" == *"creator-center/upload"* ]]; }
}

wait_for_js() {
  local js="$1"
  local timeout="${2:-120}"
  local interval="${3:-2}"
  local elapsed=0
  while [[ "$elapsed" -lt "$timeout" ]]; do
    local result
    result=$(chrome_js "$js" 2>/dev/null || true)
    if [[ "$result" == "true" || "$result" == "True" ]]; then
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  return 1
}

wait_for_file_dialog() {
  local timeout="${1:-15}"
  local elapsed=0
  while [[ "$elapsed" -lt "$timeout" ]]; do
    local count
    count=$(osascript <<'APPLESCRIPT' 2>/dev/null || echo "0"
tell application "System Events"
  tell process "Google Chrome"
    if (count of windows) > 0 then
      return count of sheets of window 1
    end if
    return 0
  end tell
end tell
APPLESCRIPT
)
    if [[ "$count" =~ ^[1-9] ]]; then
      return 0
    fi
    sleep 0.3
    elapsed=$((elapsed + 1))
  done
  return 1
}

click_element_screen() {
  local js_find_click="$1"
  local cliclick_bin="${CLICLICK_BIN:-$(command -v cliclick 2>/dev/null || true)}"
  if [[ -z "$cliclick_bin" ]]; then
    log_err "cliclick not found; install with: brew install cliclick"
    return 1
  fi

  chrome_activate
  local coords
  coords=$(chrome_js "$js_find_click" 2>/dev/null || echo "")
  if [[ -z "$coords" || "$coords" == "missing value" ]]; then
    log_err "Could not resolve element screen coordinates"
    return 1
  fi

  local sx sy
  sx=$(printf '%s' "$coords" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["x"])')
  sy=$(printf '%s' "$coords" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["y"])')
  log "Screen click at ${sx},${sy}"
  "$cliclick_bin" "c:${sx},${sy}"
  sleep 0.5
}

json_get() {
  local json="$1"
  local key="$2"
  printf '%s' "$json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$key',''))"
}

json_get_bool() {
  local json="$1"
  local key="$2"
  printf '%s' "$json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$key', False))"
}

export LIB_DIR SCRIPTS_DIR NEXUS_ROOT LOG_DIR PROCESSING_DIR
