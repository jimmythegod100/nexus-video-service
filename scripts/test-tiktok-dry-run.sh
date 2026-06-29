#!/usr/bin/env bash
# Automated dry-run matrix for tiktok-cursor-upload.sh (no Chrome / no publish).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD_SH="${SCRIPT_DIR}/tiktok-cursor-upload.sh"
NEXUS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_FILE="${NEXUS_ROOT}/logs/tiktok-cursor-upload.log"

SAMPLE_MP4="${SAMPLE_MP4:-}"

find_default_media() {
  if [[ -z "$SAMPLE_MP4" ]]; then
    SAMPLE_MP4=$(find "$NEXUS_ROOT/processing" "$HOME/Downloads" -type f -name '*.mp4' 2>/dev/null | head -1)
  fi
}

pass=0
fail=0
results=()

record() {
  local name="$1" status="$2" detail="$3"
  results+=("$name|$status|$detail")
  if [[ "$status" == PASS ]]; then pass=$((pass+1)); else fail=$((fail+1)); fi
}

run_expect_ok() {
  local name="$1"; shift
  local out rc=0
  out=$("$@" 2>&1) || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    record "$name" PASS "exit 0"
  else
    record "$name" FAIL "expected exit 0, got $rc"
    echo "$out" >&2
  fi
}

run_expect_fail() {
  local name="$1" expect_rc="$2"; shift 2
  local out rc=0
  out=$("$@" 2>&1) || rc=$?
  if [[ "$rc" -eq "$expect_rc" ]]; then
    record "$name" PASS "exit $expect_rc"
  else
    record "$name" FAIL "expected exit $expect_rc, got $rc"
    echo "$out" >&2
  fi
}

echo "=== TikTok upload dry-run matrix ==="
find_default_media

[[ -n "$SAMPLE_MP4" ]] && run_expect_ok "sample-video" "$UPLOAD_SH" --dry-run "$SAMPLE_MP4" || record "sample-video" SKIP "no sample MP4 found"

run_expect_fail "missing-file" 1 "$UPLOAD_SH" --dry-run "/nonexistent/video-$(date +%s).mp4"
run_expect_fail "invalid-extension" 2 "$UPLOAD_SH" --dry-run "/etc/hosts"

if [[ -n "$SAMPLE_MP4" ]]; then
  plan=$("$UPLOAD_SH" --dry-run --no-publish "$SAMPLE_MP4" 2>&1) || true
  if echo "$plan" | grep -q 'STOP before Post (--no-publish)'; then
    record "no-publish-plan" PASS "plan mentions --no-publish stop"
  else
    record "no-publish-plan" FAIL "plan missing no-publish marker"
  fi
else
  record "no-publish-plan" SKIP "no sample media"
fi

if [[ -x "$SCRIPT_DIR/tiktok-upload.py" ]]; then
  record "python-driver" PASS "tiktok-upload.py present"
else
  record "python-driver" FAIL "tiktok-upload.py missing"
fi

if [[ -f "$SCRIPT_DIR/tiktok-upload.scpt" ]]; then
  record "applescript-target" PASS "tiktok-upload.scpt present"
else
  record "applescript-target" FAIL "tiktok-upload.scpt missing"
fi

echo
printf "%-22s %-6s %s\n" "TEST" "STATUS" "DETAIL"
printf "%-22s %-6s %s\n" "----" "------" "------"
for row in "${results[@]}"; do
  IFS='|' read -r n s d <<< "$row"
  printf "%-22s %-6s %s\n" "$n" "$s" "$d"
done
echo
echo "PASS/SKIP/FAIL summary: $pass passed, $fail failed"

exit "$fail"
