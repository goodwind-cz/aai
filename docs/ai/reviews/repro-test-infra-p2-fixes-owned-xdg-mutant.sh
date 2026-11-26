#!/usr/bin/env bash
# Review repro (test-infra-p2-fixes, code review round 1, finding B-1).
#
# Claim: TEST-4130 never exercises the OWNED branch of the D1 private
# XDG_CACHE_HOME block in .aai/scripts/aai-run-tests.sh (the branch every
# outermost invocation takes). A mutant whose owned branch hands the caller's
# XDG_CACHE_HOME to the wrapped command keeps TEST-4130 green.
#
# Usage: bash docs/ai/reviews/repro-test-infra-p2-fixes-owned-xdg-mutant.sh [repo]
#   repo defaults to the current directory (a checkout of the ride's HEAD).
# Exit 1 = defect present (the mutant leaks AND TEST-4130 passes on it).
# Exit 0 = TEST-4130 catches the mutant (the finding is closed).
# Exit 2 = setup failure.
#
# Safety: everything runs in a `git clone --local --no-hardlinks` under one
# mktemp root, with a fake HOME, a fake XDG_CACHE_HOME and a fake TMPDIR inside
# that root, friction capture off. The root is removed on exit. Nothing outside
# the root is written; the owner's real cache is never read or touched.
set -euo pipefail
src="${1:-$PWD}"
root="$(mktemp -d "${TMPDIR:-/tmp}/aai-review-b1.XXXXXX")" || exit 2
[[ -n "$root" && "$root" == /* && -d "$root" ]] || exit 2
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/home" "$root/xdg" "$root/tmp"
git clone -q --local --no-hardlinks "$src" "$root/clone" || exit 2
cd "$root/clone"
perl -0pi -e 's|  AAI_XDG_CACHE_DIR="\$AAI_TREE_ROOT/xdg-cache"\n  mkdir -- "\$AAI_XDG_CACHE_DIR"|  AAI_XDG_CACHE_DIR="\${XDG_CACHE_HOME:-\$AAI_TREE_ROOT/xdg-cache}"\n  mkdir -p -- "\$AAI_XDG_CACHE_DIR"|' .aai/scripts/aai-run-tests.sh
if git diff --quiet -- .aai/scripts/aai-run-tests.sh; then
  echo "setup: the mutation did not apply (owned-branch text changed?)" >&2
  exit 2
fi

# 1. The mutant, invoked as the owner invokes it (outermost wrapper, owned run).
seen="$(env -u AAI_ROLE -u AAI_TEST_OWNER -u AAI_RESIDUE_IN_TEST -u AAI_TEST_RUN_ID \
  HOME="$root/home" XDG_CACHE_HOME="$root/xdg" TMPDIR="$root/tmp" AAI_FRICTION_CAPTURE=0 \
  bash .aai/scripts/aai-run-tests.sh sh -c 'printf "%s\n" "$XDG_CACHE_HOME"' 2>/dev/null)"
leak=0
[[ "$seen" == "$root/xdg" ]] && leak=1
echo "mutant owned run: wrapped command saw XDG_CACHE_HOME=$seen (caller's fake: $root/xdg) leak=$leak"

# 2. TEST-4130 against the same mutant, through the canonical runner.
rc=0
env -u AAI_ROLE HOME="$root/home" XDG_CACHE_HOME="$root/xdg" TMPDIR="$root/tmp" AAI_FRICTION_CAPTURE=0 \
  bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-run-tests.sh 4130_private_xdg_cache \
  > "$root/t4130.out" 2>&1 || rc=$?
echo "TEST-4130 on the mutant: rc=$rc"
tail -n 3 "$root/t4130.out"

if [[ "$leak" -eq 1 && "$rc" -eq 0 ]]; then
  echo "DEFECT: the owned-branch mutant leaks the caller's XDG_CACHE_HOME and TEST-4130 stays green"
  exit 1
fi
echo "closed: TEST-4130 catches the owned-branch mutant (or the mutant does not leak)"
exit 0
