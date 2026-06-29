#!/usr/bin/env bash
# Click through TikTok upload flow to publish (or stop before final click).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/chrome-tiktok-common.sh
source "${SCRIPT_DIR}/chrome-tiktok-common.sh"
# shellcheck source=lib/chrome-tiktok-fill.sh
source "${SCRIPT_DIR}/chrome-tiktok-fill.sh"

wait_for_upload_processing() {
  local timeout="${1:-600}"
  log "Waiting for TikTok upload processing (timeout ${timeout}s)..."
  if wait_for_js '
(function() {
  const text = document.body.innerText || "";
  const caption = document.querySelector("[contenteditable=\"true\"], textarea, [data-e2e=\"caption-input\"]");
  if (caption && /post|publish|save draft/i.test(text)) return true;
  if (/100%|upload complete|edit video/i.test(text)) return true;
  return false;
})();' "$timeout" 3; then
    log "TikTok upload ready for metadata/publish"
    return 0
  fi
  log_err "Timed out waiting for TikTok upload processing"
  return 1
}

click_button_matching() {
  local pattern="$1"
  local pattern_json
  pattern_json=$(printf '%s' "$pattern" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
  chrome_js "
(function() {
  const re = new RegExp(${pattern_json}, 'i');
  const candidates = Array.from(document.querySelectorAll('button, div[role=\"button\"], [data-e2e=\"post-button\"]'));
  const btn = candidates.find(el => {
    const t = (el.innerText || el.getAttribute('aria-label') || '').trim();
    return re.test(t) && !el.disabled && el.getAttribute('aria-disabled') !== 'true';
  });
  if (!btn) return JSON.stringify({ok:false, error:'button not found', pattern: ${pattern_json}});
  btn.click();
  return JSON.stringify({ok:true, clicked: (btn.innerText||btn.getAttribute('aria-label')||'').trim()});
})();"
}

get_video_url_from_page() {
  chrome_js '
(function() {
  const links = Array.from(document.querySelectorAll("a[href]"));
  for (const a of links) {
    const h = a.href || "";
    if (h.includes("tiktok.com/@") && h.includes("/video/")) {
      return h.split("?")[0];
    }
  }
  const text = document.body.innerText || "";
  const m = text.match(/https?:\\/\\/(www\\.)?tiktok\\.com\\/@[^\\s]+\\/video\\/\\d+/);
  return m ? m[0] : "";
})();'
}

publish_tiktok_upload() {
  local privacy="${1:-private}"
  local no_publish="${2:-0}"

  fill_tiktok_metadata "${3:-{\"caption\":\"\",\"hashtags\":[]}}" "$privacy" 0 || true

  if [[ "$no_publish" -eq 1 ]]; then
    log "Stopping before publish (--no-publish)"
    return 0
  fi

  log "Clicking TikTok Post/Publish button..."
  local pub_result
  pub_result=$(click_button_matching '^(Post|Publish|Upload)$' || echo '{"ok":false}')
  log "Publish click result: $pub_result"

  sleep 3
  local url
  url=$(get_video_url_from_page 2>/dev/null || echo "")
  if [[ -n "$url" && "$url" != "missing value" ]]; then
    log "TikTok URL: $url"
    echo "$url"
    return 0
  fi

  log "Publish clicked; URL not yet visible (may still be processing)"
  echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  publish_tiktok_upload "${1:-private}" "${2:-0}"
fi
