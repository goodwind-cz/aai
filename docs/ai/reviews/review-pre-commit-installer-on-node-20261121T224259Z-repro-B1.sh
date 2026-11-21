#!/usr/bin/env bash
# Repro for code review B1 (review-pre-commit-installer-on-node-20261121T224259Z.md).
#
# The node:test file's in-process installer helper (runMod, and the direct run() calls of TEST-3985) builds the
# environment with prepareEnv but never calls assertHooksUnderRoot. prepareEnv strips only AAI_*, GIT_DIR and
# GIT_WORK_TREE, so a core.hooksPath injected through the environment (GIT_CONFIG_COUNT/KEY/VALUE, which
# `git -c` hands to child processes as GIT_CONFIG_PARAMETERS in the same way) reaches the module's git children,
# and the module writes the three hooks OUTSIDE the test's own scratch root. The spawn-based runInstaller, under
# the same environment, refuses (assertHooksUnderRoot throws) and writes nothing: the contrast run below.
#
# Safe: the "victim" is an empty directory this script creates with mktemp and removes again; it is not a
# repository. Run from the worktree root: bash docs/ai/reviews/review-pre-commit-installer-on-node-20261121T224259Z-repro-B1.sh
set -u
ROOT="$(git rev-parse --show-toplevel)" || exit 2
VICTIM="$(mktemp -d "${TMPDIR:-/tmp}/review-b1-victim.XXXXXX")" || exit 2
[[ -n "$VICTIM" && "$VICTIM" == /* && -d "$VICTIM" ]] || exit 2
T="$ROOT/tests/skills/lib/install-pre-commit-hook.test.mjs"

echo "== in-process helper (runMod): TEST-3988 'a hook made non-executable ...'"
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$VICTIM" \
  env -u AAI_ROLE node --test --test-reporter=tap --test-name-pattern 'TEST-3988 a hook made non-executable' "$T" 2>&1 \
  | grep -E '^(not )?ok|^# (pass|fail)'
echo "files written outside the scratch root, in $VICTIM:"
ls -1 "$VICTIM"
n_inproc="$(ls -1 "$VICTIM" | wc -l | tr -d ' ')"
rm -f -- "$VICTIM/pre-commit" "$VICTIM/reference-transaction" "$VICTIM/pre-push"

echo "== spawn helper (runInstaller): TEST-3986 'hooksPath unset, ...' under the same environment"
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$VICTIM" \
  env -u AAI_ROLE node --test --test-reporter=tap --test-name-pattern 'TEST-3986 hooksPath unset' "$T" 2>&1 \
  | grep -E 'not ok|outside the scratch root' | head -2
n_spawn="$(ls -1 "$VICTIM" | wc -l | tr -d ' ')"
echo "files in $VICTIM after the spawn-helper run: $n_spawn"

rmdir -- "$VICTIM"
echo "RESULT: in-process helper wrote $n_inproc file(s) outside the scratch root; spawn helper wrote $n_spawn"
[[ "$n_inproc" == 0 ]] || exit 1
exit 0
