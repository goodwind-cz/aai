#!/usr/bin/env bash
# Repro for code review B1 (sync-on-node, review-sync-on-node-20261122T175713Z.md):
# the DR-5 refusal (target equal to or inside the source) and the underRoot "not under the source" check compare real
# paths as strings, and fs.realpathSync keeps the case the caller typed. On a case-insensitive file system (the macOS
# and Windows defaults) a target that names the source with different letter case passes both checks, and the first
# copy-replace deletes a source file (dst and src are the same file).
#
# Scratch only: one mktemp directory under TMPDIR with an own prefix, removed on exit; the layer is taken read-only
# with `git archive` from the checkout named as $1 (default: this script's checkout); env -i, so no GIT_ variable of
# the caller reaches git. Nothing outside the scratch directory is written or deleted.
#
# Exit: 0 = fixed (the case-variant target is refused and the source is unchanged); 1 = defect present;
#       42 = cannot run here (the scratch file system is case-sensitive, or git/node missing).
set -euo pipefail
CHECKOUT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
command -v node >/dev/null 2>&1 || { echo "SKIP: node missing"; exit 42; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git missing"; exit 42; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/aai-review-b1.XXXXXX")"
cleanup() { case "$WORK" in "${TMPDIR:-/tmp}"/aai-review-b1.*) rm -rf -- "$WORK" ;; esac; }
trap cleanup EXIT
mkdir "$WORK/Src"
[[ -d "$WORK/SRC" ]] || { echo "SKIP: $WORK is on a case-sensitive file system"; exit 42; }
git -C "$CHECKOUT" archive HEAD .aai AGENTS.md README.md | tar -x -C "$WORK/Src"
before="$(cd "$WORK/Src" && find . -type f | LC_ALL=C sort | wc -l | tr -d ' ')"
rc=0
env -i PATH="$PATH" HOME="$WORK" node "$WORK/Src/.aai/scripts/aai-sync.mjs" "$WORK/SRC" >"$WORK/out" 2>"$WORK/err" || rc=$?
after="$(cd "$WORK/Src" && find . -type f | LC_ALL=C sort | wc -l | tr -d ' ')"
echo "exit=$rc files_before=$before files_after=$after"
sed -n '1,3p' "$WORK/err"
if [[ "$rc" == 1 && "$before" == "$after" ]] && grep -q 'is the source' "$WORK/err"; then
  echo "FIXED: the case-variant target was refused and the source is unchanged"
  exit 0
fi
echo "DEFECT: the case-variant spelling of the source was not refused (source files $before -> $after)"
exit 1
