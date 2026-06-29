#!/usr/bin/env bash
# Fill TikTok upload caption and hashtags in Chrome via CDP JavaScript.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/chrome-tiktok-common.sh
source "${SCRIPT_DIR}/chrome-tiktok-common.sh"

read_page_context() {
  chrome_js '
(function() {
  const captionEl = document.querySelector("[contenteditable=\"true\"], textarea, [data-e2e=\"caption-input\"]");
  const text = document.body.innerText || "";
  const filenameMatch = text.match(/([\\w.-]+\\.(mp4|mov|webm))/i);
  const uploading = /uploading|processing/i.test(text);
  const ready = /post|publish|save draft/i.test(text);
  return JSON.stringify({
    url: location.href,
    captionField: captionEl ? (captionEl.innerText || captionEl.value || "").trim().slice(0, 120) : "",
    filename: filenameMatch ? filenameMatch[1] : "",
    uploading,
    ready,
    isTikTok: location.href.includes("tiktok.com")
  });
})();'
}

set_caption() {
  local text="$1"
  local text_json
  text_json=$(printf '%s' "$text" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
  chrome_js "
(function() {
  const el = document.querySelector('[contenteditable=\"true\"], textarea, [data-e2e=\"caption-input\"]');
  if (!el) return JSON.stringify({ok:false, error:'caption field not found'});
  el.focus();
  if ('value' in el) {
    el.value = ${text_json};
    el.dispatchEvent(new Event('input', {bubbles:true}));
    el.dispatchEvent(new Event('change', {bubbles:true}));
  } else {
    el.innerText = ${text_json};
    el.dispatchEvent(new InputEvent('input', {bubbles:true}));
  }
  return JSON.stringify({ok:true, text: (el.innerText || el.value || '').slice(0,120)});
})();"
}

set_privacy_option() {
  local privacy="$1"
  local label=""
  case "$privacy" in
    public) label="Everyone" ;;
    friends) label="Friends" ;;
    private) label="Only me" ;;
    *) label="Only me" ;;
  esac
  local label_json
  label_json=$(printf '%s' "$label" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
  chrome_js "
(function() {
  const want = ${label_json};
  const options = Array.from(document.querySelectorAll('button, div[role=\"button\"], label, span'));
  const match = options.find(el => (el.innerText || el.getAttribute('aria-label') || '').includes(want));
  if (match) { match.click(); return JSON.stringify({ok:true, privacy: want}); }
  return JSON.stringify({ok:false, error:'privacy option not found', want});
})();"
}

fill_tiktok_metadata() {
  local meta_json="$1"
  local privacy="${2:-private}"
  local dry_run="${3:-0}"

  local caption hashtags_json
  caption=$(printf '%s' "$meta_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); tags=" ".join(d.get("hashtags",[])); print(f"{d.get(\"caption\",\"\")} {tags}".strip())')
  hashtags_json=$(printf '%s' "$meta_json" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get("hashtags",[])))')

  if [[ "$dry_run" -eq 1 ]]; then
    log "DRY-RUN fill — current page context:"
    read_page_context | python3 -m json.tool
    return 0
  fi

  log "Filling TikTok caption..."
  set_caption "$caption" >/dev/null || true

  log "Setting privacy: $privacy"
  set_privacy_option "$privacy" >/dev/null || true

  log "TikTok metadata fill complete (hashtags: $hashtags_json)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ "${1:-}" == "--dry-run" ]]; then
    ensure_chrome
    read_page_context | python3 -m json.tool
    exit 0
  fi
  echo "Usage: $(basename "$0") --dry-run   # read current upload form" >&2
  echo "       source and call fill_tiktok_metadata JSON [privacy]" >&2
  exit 1
fi
