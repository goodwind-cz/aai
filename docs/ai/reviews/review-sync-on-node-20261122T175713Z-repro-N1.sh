#!/usr/bin/env bash
# Repro for code review N1 (sync-on-node, review-sync-on-node-20261122T175713Z.md):
# a source checkout inside the target is allowed (D-ROOTS), but underRoot checks only the PARENT of the path it
# guards. When the source lies inside a managed entry of the target (here <target>/.aai/upstream), the extended stale
# clean removes that entry, and with it the running source, and the run still exits 0.
#
# Scratch only: one mktemp directory under TMPDIR with an own prefix, removed on exit; the layer is taken read-only
# with `git archive` from the checkout named as $1 (default: this script's checkout); env -i. Nothing outside the
# scratch directory is written or deleted.
#
# Exit: 0 = fixed (the source survives); 1 = defect present; 42 = node/git missing.
set -euo pipefail
CHECKOUT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
command -v node >/dev/null 2>&1 || { echo "SKIP: node missing"; exit 42; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git missing"; exit 42; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/aai-review-n1.XXXXXX")"
cleanup() { case "$WORK" in "${TMPDIR:-/tmp}"/aai-review-n1.*) rm -rf -- "$WORK" ;; esac; }
trap cleanup EXIT
SRC="$WORK/T/.aai/upstream"
mkdir -p "$SRC"
git -C "$CHECKOUT" archive HEAD .aai AGENTS.md README.md | tar -x -C "$SRC"
rc=0
env -i PATH="$PATH" HOME="$WORK" node "$SRC/.aai/scripts/aai-sync.mjs" "$WORK/T" >"$WORK/out" 2>"$WORK/err" || rc=$?
echo "exit=$rc"
grep 'CLEAN removed stale' "$WORK/out" || true
if [[ -f "$SRC/.aai/scripts/aai-sync.mjs" ]]; then
  echo "FIXED: the source inside the target survived the sync"
  exit 0
fi
echo "DEFECT: the sync deleted its own source at $SRC (exit $rc)"
exit 1
