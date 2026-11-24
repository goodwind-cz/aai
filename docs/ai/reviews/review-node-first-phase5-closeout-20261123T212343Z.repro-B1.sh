#!/usr/bin/env bash
# Repro for review finding B1 (node-first-phase5-closeout, review-node-first-phase5-closeout-20261123T212343Z.md).
# TEST-4036 pins the literal heading "## [unreleased] — Node-first phase 5 closeout". A release cut rolls every
# "## [unreleased] — " heading into "## [vYYYY.MM.DD] — " (see tests/skills/test-aai-hook-installer-docs.sh and
# test-aai-merge-policy.sh, which accept both forms for exactly this reason), so the first release after merge turns
# TEST-4036 red. The repro works on a scratch clone only and prints the control and the rolled result.
# Usage: bash <this file> <path to the branch checkout>   (expect: control PASS, rolled FAIL; exit 0 when it bites)
set -euo pipefail
SRC="${1:?usage: repro-B1.sh <checkout>}"
case "$SRC" in /*) ;; *) echo "need an absolute checkout path" >&2; exit 2 ;; esac
D="$(mktemp -d "${TMPDIR:-/tmp}/aai-review-b1.XXXXXX")"
trap 'rm -rf -- "$D"' EXIT
git clone -q --no-hardlinks "$SRC" "$D/clone"
cd "$D/clone"
rc=0; env -u AAI_ROLE -u AAI_GIT_WRITE bash tests/skills/test-aai-phase5-closeout.sh test_4036_docs_and_wiring >"$D/control.out" 2>&1 || rc=$?
echo "control rc=$rc: $(tail -n 1 "$D/control.out")"
[[ "$rc" -eq 0 ]] || { echo "control did not pass; repro inconclusive" >&2; exit 3; }
# what the release roll does to the heading
sed 's/^## \[unreleased\] — Node-first phase 5 closeout$/## [v2026.11.24] — Node-first phase 5 closeout/' CHANGELOG.md > "$D/CHANGELOG.rolled"
cp "$D/CHANGELOG.rolled" CHANGELOG.md
rc=0; env -u AAI_ROLE -u AAI_GIT_WRITE bash tests/skills/test-aai-phase5-closeout.sh test_4036_docs_and_wiring >"$D/rolled.out" 2>&1 || rc=$?
echo "rolled rc=$rc: $(tail -n 1 "$D/rolled.out")"
[[ "$rc" -ne 0 ]] && { echo "BITES: TEST-4036 fails once the release rolls the heading"; exit 0; }
echo "does not bite"; exit 1
