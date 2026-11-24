#!/usr/bin/env bash
# Repro for review finding B2 (node-first-phase5-closeout, review-node-first-phase5-closeout-20261123T212343Z.md).
# TEST-4033 and TEST-4034 require follow-up items of OTHER, future work to stay open forever: the P3 successor
# fu-parity-win-odd-root-cause must be "an open P3", and the three outside-ref P2 items named in plan section 7 must stay
# "open P2". Resolving any of them (the intended next step for each) turns this suite red on an unrelated pull request.
# The repro works on a scratch clone only: it closes each item there with the shipped CLI and runs the two cases.
# Usage: bash <this file> <path to the branch checkout>   (expect: control PASS, each close FAIL; exit 0 when it bites)
set -euo pipefail
SRC="${1:?usage: repro-B2.sh <checkout>}"
case "$SRC" in /*) ;; *) echo "need an absolute checkout path" >&2; exit 2 ;; esac
D="$(mktemp -d "${TMPDIR:-/tmp}/aai-review-b2.XXXXXX")"
trap 'rm -rf -- "$D"' EXIT
git clone -q --no-hardlinks "$SRC" "$D/clone"
cd "$D/clone"
cp docs/ai/decisions.jsonl "$D/ledger.base"
run_case() { local rc=0; env -u AAI_ROLE -u AAI_GIT_WRITE bash tests/skills/test-aai-phase5-closeout.sh "$1" >"$D/out" 2>&1 || rc=$?; echo "$rc $(tail -n 1 "$D/out" | cut -c1-240)"; }
echo "control 4033: $(run_case test_4033_remeasure_record)"
echo "control 4034: $(run_case test_4034_follow_ups)"
bites=0
for id in fu-parity-win-odd-root-cause fu-release-pwsh-identity-crash; do
  cp "$D/ledger.base" docs/ai/decisions.jsonl
  env -u AAI_ROLE -u AAI_GIT_WRITE node .aai/scripts/follow-ups.mjs close --id "$id" --resolved-by some-later-ride \
    --source "review repro" --ledger "$D/clone/docs/ai/decisions.jsonl" >/dev/null
  r33="$(run_case test_4033_remeasure_record)"; echo "after closing $id, 4033: $r33"
  [[ "${r33%% *}" == 0 ]] || bites=1
  if [[ "$id" == fu-parity-win-odd-root-cause ]]; then
    r34="$(run_case test_4034_follow_ups)"; echo "after closing $id, 4034: $r34"
    [[ "${r34%% *}" == 0 ]] || bites=1
  fi
done
[[ "$bites" -eq 1 ]] && { echo "BITES: resolving a later follow-up fails the closeout record checks"; exit 0; }
echo "does not bite"; exit 1
