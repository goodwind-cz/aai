#!/usr/bin/env bash
# Repro for code review B1 (hook-gate-staged-content r1): `--staged` without
# `--gate-file` is not refused when combined with `--gate <ID>` (or
# `--intake-file`); the flag is silently dropped and the working-tree verdict
# is returned. Spec-AC-04 / D2: "--staged without --gate-file SHALL exit 2".
# Usage: bash <this file> [<repo root holding .aai/>]   -- exits 1 when the defect is present.
set -euo pipefail
SRC="${1:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)}"
[[ -n "$SRC" && "$SRC" == /* && -f "$SRC/.aai/scripts/docs-audit.mjs" ]] || { echo "bad source root: $SRC" >&2; exit 2; }
FX="$(mktemp -d "${TMPDIR:-/tmp}/rev-b1.XXXXXX")"
[[ -n "$FX" && "$FX" == /* ]] || exit 2
trap 'rm -rf "$FX"' EXIT
cp -R "$SRC/.aai" "$FX/.aai"
cd "$FX"
git init -q -b main
git config user.email r@example.invalid; git config user.name r; git config commit.gpgsign false
mkdir -p docs/issues docs/specs
printf -- '---\nid: issue-5990\ntype: issue\nstatus: done\nlinks:\n  pr: []\n---\n# Intake\n' > docs/issues/ISSUE-5990-a.md
spec() {
  local st="$1" ev="a1b2c3d"; [[ "$st" == done ]] || ev="—"
  printf -- '---\nid: spec-5990\ntype: spec\nstatus: done\nlinks:\n  requirement: issue-5990\n  pr: []\n---\n# Spec\n\n## Acceptance Criteria Status\n\n| Spec-AC | Description | Status | Evidence | Review-By | Notes |\n|---|---|---|---|---|---|\n| Spec-AC-01 | first | %s | %s | TDD | — |\n' "$st" "$ev" > docs/specs/SPEC-5990-a.md
}
spec implementing
git add docs                      # the INDEX holds the non-terminal spec
spec done                         # the WORKING TREE holds a reconciled spec
rc=0; node .aai/scripts/docs-audit.mjs --gate-file docs/issues/ISSUE-5990-a.md --staged > a.log 2>&1 || rc=$?
echo "--gate-file <f> --staged  -> rc=$rc (index spec non-terminal: expected 1)"
rc_bare=0; node .aai/scripts/docs-audit.mjs --staged > b.log 2>&1 || rc_bare=$?
echo "--staged                  -> rc=$rc_bare (expected 2)"
rc_gate=0; node .aai/scripts/docs-audit.mjs --gate ISSUE-5990 --staged > c.log 2>&1 || rc_gate=$?
echo "--gate ISSUE-5990 --staged -> rc=$rc_gate (spec D2/AC-04: expected 2); output: $(grep -m1 -E 'GATE|USAGE' c.log | cut -c1-60)"
if [[ "$rc_gate" != 2 ]]; then
  echo "DEFECT B1 present: --staged was silently ignored next to --gate; the working-tree verdict was returned"
  exit 1
fi
echo "B1 not reproduced"
