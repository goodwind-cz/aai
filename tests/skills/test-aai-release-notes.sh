#!/usr/bin/env bash
# Real Git fixtures for spec-release-one-command-no-findings TEST-001..003.
# bash 3.2 compatible. No network; only disposable repositories are mutated.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$ROOT/.aai/scripts/release-notes-gate.mjs"
SCRATCH_ROOT="${AAI_NOTES_SCRATCH_ROOT:-/tmp/aai-release-one-command-scratch/notes}"
case "$SCRATCH_ROOT" in /*) ;; *) echo 'scratch must be absolute' >&2; exit 1;; esac
mkdir -p "$SCRATCH_ROOT"
FIXTURE="$(mktemp -d "$SCRATCH_ROOT/repo.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
git init -q -b main "$FIXTURE"
git -C "$FIXTURE" config user.name notes-fixture
git -C "$FIXTURE" config user.email notes-fixture@example.invalid
git -C "$FIXTURE" config core.hooksPath /dev/null
mkdir -p "$FIXTURE/.aai"
printf 'old\n' > "$FIXTURE/.aai/tool.txt"
printf '# Changelog\n\n## [unreleased]\n\n## [unreleased] — old note\n\n- Existing description.\n' > "$FIXTURE/CHANGELOG.md"
git -C "$FIXTURE" add -- .aai/tool.txt CHANGELOG.md
git -C "$FIXTURE" commit -qm initial
BASE="$(git -C "$FIXTURE" rev-parse HEAD)"
BODY="$FIXTURE/body.txt"
printf '## Summary\n' > "$BODY"
FAILURES=0
expect() {
  local id="$1" wanted="$2" label="$3"
  shift 3
  local rc=0 ok
  (case "$FIXTURE" in /*) cd "$FIXTURE";; *) exit 99;; esac; node "$GATE" "$@") > "$FIXTURE/out" 2>&1 || rc=$?
  # A missing CLI is infrastructure, never evidence of a working refusal.
  if [ "$wanted" = pass ]; then
    [ "$rc" -eq 0 ] && ok=yes || ok=no
  else
    [ "$rc" -ne 0 ] && grep -q '^REFUSED: release-notes ' "$FIXTURE/out" && ok=yes || ok=no
  fi
  if [ "$ok" = yes ]; then
    printf '%s PASS %s (exit=%s)\n' "$id" "$label" "$rc"
  else
    printf '%s FAIL %s (exit=%s)\n' "$id" "$label" "$rc"
    cat "$FIXTURE/out"
    FAILURES=$((FAILURES + 1))
  fi
}
both() {
  local id="$1" wanted="$2" label="$3"
  if [ "$label" != "docs only" ]; then
    printf "%s\n" "$label" >> "$FIXTURE/.aai/tool.txt"
    git -C "$FIXTURE" add -- .aai/tool.txt
  fi
  expect "$id" "$wanted" "staged: $label" --staged --body-file "$BODY"
  git -C "$FIXTURE" commit -qm "fixture $label" --allow-empty
  HEAD_SHA="$(git -C "$FIXTURE" rev-parse HEAD)"
  expect "$id" "$wanted" "CI range: $label" --base "$BASE" --head "$HEAD_SHA" --body-file "$BODY"
}
printf 'changed\n' > "$FIXTURE/.aai/tool.txt"
git -C "$FIXTURE" add -- .aai/tool.txt
both TEST-001 refuse 'shipped without notes; unchanged old entry'
printf '\n## [unreleased]\n\n' >> "$FIXTURE/CHANGELOG.md"
git -C "$FIXTURE" add -- CHANGELOG.md .aai/tool.txt
both TEST-001 refuse 'blank scaffold'
printf '\n## [unreleased] — new feature\n\n- New behavior ships.\n' >> "$FIXTURE/CHANGELOG.md"
git -C "$FIXTURE" add -- CHANGELOG.md
# Stage a shipped change again so staged and commit-range arms both exercise it.
printf 'changed again\n' > "$FIXTURE/.aai/tool.txt"
git -C "$FIXTURE" add -- .aai/tool.txt
both TEST-002 pass 'new nonempty notes'
# Begin a fresh comparison from this commit, with notes already old.
BASE="$(git -C "$FIXTURE" rev-parse HEAD)"
printf 'another change\n' > "$FIXTURE/.aai/tool.txt"
git -C "$FIXTURE" add -- .aai/tool.txt
printf 'no-notes:    \n' > "$BODY"
both TEST-002 refuse 'empty exemption'
printf 'no-notes:\n\nUnrelated paragraph\n' > "$BODY"
both TEST-002 refuse 'blank marker cannot consume later paragraph'
printf 'no-notes: maintenance needs no operator action\n' > "$BODY"
printf 'yet another change\n' > "$FIXTURE/.aai/tool.txt"
git -C "$FIXTURE" add -- .aai/tool.txt
both TEST-002 pass 'explicit reason'
BASE="$(git -C "$FIXTURE" rev-parse HEAD)"
printf 'docs change\n' > "$FIXTURE/README.md"
git -C "$FIXTURE" add -- README.md
printf 'Summary\n' > "$BODY"
both TEST-002 pass 'docs only'
expect TEST-003 refuse 'missing body' --staged --body-file "$FIXTURE/absent-body"
expect TEST-003 refuse 'unreadable body (directory)' --staged --body-file "$FIXTURE"
expect TEST-003 refuse 'missing history' --base deadbeef --head HEAD --body-file "$BODY"
printf 'no-notes: $(touch "%s/executed") `touch "%s/executed"`\n' "$FIXTURE" "$FIXTURE" > "$BODY"
printf 'untrusted-body change\n' > "$FIXTURE/.aai/tool.txt"
git -C "$FIXTURE" add -- .aai/tool.txt
both TEST-003 pass 'body stays data'
if [ -e "$FIXTURE/executed" ]; then echo 'TEST-003 FAIL body executed'; FAILURES=$((FAILURES + 1)); else echo 'TEST-003 PASS no body execution'; fi
# Resolve the executable through a symlink as the installed CLI can be linked.
REAL_GATE="$GATE"
ln -s "$REAL_GATE" "$FIXTURE/notes-gate-link.mjs"
GATE="$FIXTURE/notes-gate-link.mjs"
expect TEST-003 refuse 'symlink invocation executes gate' --staged --body-file "$FIXTURE/absent-body"
GATE="$REAL_GATE"
# Integration contracts: both entrypoints must invoke the same production CLI.
if grep -q 'release-notes-gate.mjs --staged --body-file' "$ROOT/.aai/SKILL_PR.prompt.md" &&
   grep -q 'release-notes-gate.mjs --base' "$ROOT/.github/workflows/skill-suite.yml" &&
   grep -q 'pull-requests: read' "$ROOT/.github/workflows/skill-suite.yml"; then
  echo 'TEST-003 PASS local and CI shared gate invocation'
else
  echo 'TEST-003 FAIL local/CI wiring missing'; FAILURES=$((FAILURES + 1))
fi
GATE_MODULE="$ROOT/.aai/scripts/release-notes-gate.mjs" node --input-type=module -e '
import { pathToFileURL } from "node:url";
const mod = await import(pathToFileURL(process.env.GATE_MODULE).href);
const { isShipped, hasNoNotesReason } = mod;
if (typeof isShipped !== "function" || typeof hasNoNotesReason !== "function") process.exit(1);
if (!isShipped(".aai/x", "") || !isShipped("tool", "100755") || isShipped("README.md", "100644")) process.exit(2);
if (!hasNoNotesReason("no-notes: because\n") || hasNoNotesReason("no-notes:   \n")) process.exit(3);
' && echo 'TEST-004 PASS exports' || { echo 'TEST-004 FAIL exports'; FAILURES=$((FAILURES + 1)); }
if [ -e "$ROOT/.aai/scripts/release-finish.mjs" ]; then
  echo 'TEST-004 FAIL finish module present'; FAILURES=$((FAILURES + 1))
else
  echo 'TEST-004 PASS finish module absent'
fi
if grep -q 'release-notes-gate.mjs' "$ROOT/.aai/system/PROFILES.yaml" && ! grep -q 'release-finish.mjs' "$ROOT/.aai/system/PROFILES.yaml"; then
  echo 'TEST-004 PASS profiles'
else
  echo 'TEST-004 FAIL profiles'; FAILURES=$((FAILURES + 1))
fi
# A later base commit is not part of the pull request. Two-dot diff would
# treat that base-only shipped edit as a reverse change, and a base-deleted
# note as a note the head added.
FORK="$(git -C "$FIXTURE" rev-parse HEAD)"
git -C "$FIXTURE" checkout -q -b diverge-head
printf 'docs only\n' > "$FIXTURE/README.md"
git -C "$FIXTURE" add -- README.md
git -C "$FIXTURE" commit -qm 'docs only head'
git -C "$FIXTURE" checkout -q -b diverge-base "$FORK"
printf 'base only shipped\n' >> "$FIXTURE/.aai/tool.txt"
git -C "$FIXTURE" add -- .aai/tool.txt
git -C "$FIXTURE" commit -qm 'base shipped'
printf 'Summary\n' > "$BODY"
expect TEST-005 pass 'docs-only head ignores a base-only shipped file' --base diverge-base --head diverge-head --body-file "$BODY"
git -C "$FIXTURE" checkout -q -B notes-head "$FORK"
printf 'shipped on head\n' >> "$FIXTURE/.aai/tool.txt"
git -C "$FIXTURE" add -- .aai/tool.txt
git -C "$FIXTURE" commit -qm 'head shipped no notes'
git -C "$FIXTURE" checkout -q -B notes-base "$FORK"
node -e 'const fs=require("fs"); const p=process.argv[1]; const t=fs.readFileSync(p,"utf8"); if(!t.includes("- New behavior ships.")) process.exit(2); fs.writeFileSync(p, t.replace("\n- New behavior ships.\n","\n"));' "$FIXTURE/CHANGELOG.md"
git -C "$FIXTURE" add -- CHANGELOG.md
git -C "$FIXTURE" commit -qm 'base drops an old note'
printf 'Summary\n' > "$BODY"
expect TEST-005 refuse 'a note deleted on the base is not a note the head added' --base notes-base --head notes-head --body-file "$BODY"
printf 'release-notes assertions: failures=%s fixture=%s base=%s head=%s\n' "$FAILURES" "$FIXTURE" "$BASE" "$(git -C "$FIXTURE" rev-parse HEAD)"
[ "$FAILURES" -eq 0 ]
