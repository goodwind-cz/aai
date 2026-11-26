#!/usr/bin/env bash
# Review repro (test-infra-p2-fixes, code review round 2, finding B-2).
#
# Claim: TEST-4130's pw_xdg and pw_home arms do not unset an inherited
# PLAYWRIGHT_BROWSERS_PATH. On a Linux host, the canonical invocation
# `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-run-tests.sh`
# has the OUTER wrapper export PLAYWRIGHT_BROWSERS_PATH (the b3c245b7
# pass-through), the nested wrapper keeps it as a caller value, and both arms
# fail deterministically. macOS (where the validation sweep ran) never exports
# it, so the sweep stayed green.
#
# The Linux host is simulated with the wrapper's own AAI_UNAME override on the
# outer wrapper; the second run sets PLAYWRIGHT_BROWSERS_PATH directly (a Linux
# user who exported it in their shell).
#
# Usage: bash docs/ai/reviews/repro-test-infra-p2-fixes-pw-inherited.sh [repo]
# Exit 1 = defect present (TEST-4130 red under an inherited value).
# Exit 0 = TEST-4130 is green in both runs (the finding is closed).
# Exit 2 = setup failure.
#
# Safety: one mktemp root with fake HOME, XDG_CACHE_HOME and TMPDIR, friction
# capture off, removed on exit; the repo is read, never written.
set -euo pipefail
src="${1:-$PWD}"
root="$(mktemp -d "${TMPDIR:-/tmp}/aai-review-b2.XXXXXX")" || exit 2
[[ -n "$root" && "$root" == /* && -d "$root" ]] || exit 2
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/home" "$root/xdg" "$root/tmp"
cd "$src" || exit 2

run() {
  local label="$1"; shift
  local rc=0
  env -u AAI_ROLE -u PLAYWRIGHT_BROWSERS_PATH "$@" HOME="$root/home" XDG_CACHE_HOME="$root/xdg" \
    TMPDIR="$root/tmp" AAI_FRICTION_CAPTURE=0 \
    bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-run-tests.sh 4130_private_xdg_cache \
    > "$root/$label.out" 2>&1 || rc=$?
  echo "$label: TEST-4130 rc=$rc"
  grep -m1 '^FAIL' "$root/$label.out" || true
  return "$rc"
}

bad=0
run linux-outer-wrapper AAI_UNAME=Linux || bad=1
run user-exported-value PLAYWRIGHT_BROWSERS_PATH=/home/u/.cache/ms-playwright || bad=1

if [[ "$bad" -eq 1 ]]; then
  echo "DEFECT: TEST-4130 is red when PLAYWRIGHT_BROWSERS_PATH is inherited (any Linux run through the wrapper)"
  exit 1
fi
echo "closed: TEST-4130 is green with an inherited PLAYWRIGHT_BROWSERS_PATH"
exit 0
