#!/usr/bin/env bash
# Repro for review r2 finding B1 (review-precommit-residual-defects-r2-20261120T015441Z.md).
# TEST-3920 (test_3920_no_builtin_redirection_text, scan builtin_redir_scan) still misses two shapes:
#   M1  a builtin or function redirected inside a case arm on the pattern's line (`pat) cmd >&2 ;;`), the
#       script's most common one-line idiom: the first word of the segment is `pat)`, not the command;
#   M2  a builtin redirected after an unquoted command substitution (`echo $(date) >/dev/null`): the split at
#       `$(` leaves `date) >/dev/null`, which the subshell rule then skips.
# Each mutant is a COPY of pre-commit-checks.sh in a private mktemp tree (suite + .aai/scripts copied there);
# the TEST-3920 selector runs against it. Nothing in the shipping tree is modified.
# Exit 1 = at least one shape passes TEST-3920 (gap reproduced); 0 = both caught.
# Run from the repository root.
set -u
ROOT="$(pwd -P)"
[ -f "$ROOT/.aai/scripts/pre-commit-checks.sh" ] || { echo "run from the repository root"; exit 2; }
T="$(mktemp -d "${TMPDIR:-/tmp}/aai-review-r2b1.XXXXXX")" || exit 2
case "$T" in /*) ;; *) echo "scratch path not absolute"; exit 2 ;; esac
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tests/skills" "$T/.aai"
cp -R "$ROOT/.aai/scripts" "$T/.aai/scripts"
cp "$ROOT/tests/skills/test-aai-pre-commit-checks.sh" "$T/tests/skills/"
cp -R "$ROOT/tests/skills/lib" "$T/tests/skills/lib"
M="$T/.aai/scripts/pre-commit-checks.sh"
cp "$M" "$T/orig.sh"
gap=0
try() {  # try <label> <awk program applied to the original script>
  awk "$2" "$T/orig.sh" > "$M"
  if cmp -s "$M" "$T/orig.sh"; then echo "$1: mutation not applied"; exit 2; fi
  echo "--- $1:"; diff "$T/orig.sh" "$M" | sed -n '2,4p'
  if env -u AAI_ROLE -u AAI_GIT_WRITE bash "$T/tests/skills/test-aai-pre-commit-checks.sh" test_3920_no_builtin_redirection_text > "$T/out" 2>&1; then
    echo "$1: TEST-3920 PASSES on the mutant (gap)"; gap=1
  else
    echo "$1: TEST-3920 caught it"; tail -1 "$T/out"
  fi
}
# M1: the parse's `case "$meta" in :*) ;; *) staged_read_fail ... ;; esac` gets a stderr redirection on the
# function call inside the case arm.
try M1 '{ if (!done && index($0, "*) staged_read_fail \"malformed staged list\" ;; esac")) { sub(/staged_read_fail "malformed staged list" ;;/, "staged_read_fail \"malformed staged list\" >\\&2 ;;"); done=1 } print }'
# M2: one builtin echo redirected after an unquoted command substitution, before CHECK 9.
try M2 '/^TRACKED_IGNORED_SCRIPT=/ { print "echo $(date) >/dev/null" } { print }'
[ "$gap" -eq 1 ] && { echo "GAP REPRODUCED"; exit 1; }
echo "both shapes caught"
exit 0
