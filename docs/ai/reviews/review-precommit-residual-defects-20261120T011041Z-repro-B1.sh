#!/usr/bin/env bash
# Repro for review finding B1 (review-precommit-residual-defects-20261120T011041Z.md).
# TEST-3920 is named test_3920_no_builtin_redirection_text (a universal negative over the script text) but
# asserts only two textual forms: no `<<` and every `command -v` in `( command -v x )`. This copies the suite
# and .aai/scripts into a private scratch tree, puts one builtin redirection (`hash node >/dev/null 2>&1`, the
# exact class D4 removes) into the COPY of pre-commit-checks.sh before CHECK 9, and runs the TEST-3920
# selector there. Nothing in the shipping tree is modified.
# Exit 1 = gap reproduced (TEST-3920 passes on a script that holds a builtin redirection); 0 = TEST-3920 caught it.
# Run from the repository root: bash docs/ai/reviews/review-precommit-residual-defects-20261120T011041Z-repro-B1.sh
set -u
ROOT="$(pwd -P)"
[ -f "$ROOT/.aai/scripts/pre-commit-checks.sh" ] || { echo "run from the repository root"; exit 2; }
T="$(mktemp -d "${TMPDIR:-/tmp}/aai-review-b1.XXXXXX")" || exit 2
case "$T" in /*) ;; *) echo "scratch path not absolute"; exit 2 ;; esac
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tests/skills" "$T/.aai"
cp -R "$ROOT/.aai/scripts" "$T/.aai/scripts"
cp "$ROOT/tests/skills/test-aai-pre-commit-checks.sh" "$T/tests/skills/"
cp -R "$ROOT/tests/skills/lib" "$T/tests/skills/lib"
M="$T/.aai/scripts/pre-commit-checks.sh"
awk '/^TRACKED_IGNORED_SCRIPT=/ { print "hash node >/dev/null 2>&1 || true" } { print }' "$M" > "$M.new" && mv "$M.new" "$M"
grep -n '^hash node >/dev/null 2>&1' "$M" || { echo "mutation not applied"; exit 2; }
echo "--- TEST-3920 on the mutant:"
env -u AAI_ROLE -u AAI_GIT_WRITE bash "$T/tests/skills/test-aai-pre-commit-checks.sh" test_3920_no_builtin_redirection_text
rc=$?
echo "--- TEST-3920 exit: $rc"
if [ "$rc" -eq 0 ]; then
  echo "GAP REPRODUCED: TEST-3920 (named no_builtin_redirection) passes on a script holding a builtin redirection"
  exit 1
fi
echo "TEST-3920 caught the builtin redirection"
exit 0
