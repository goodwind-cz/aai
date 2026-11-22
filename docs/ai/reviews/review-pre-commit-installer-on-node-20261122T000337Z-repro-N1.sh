#!/usr/bin/env bash
# Repro for code review round 2 R2-N1 (review-pre-commit-installer-on-node-20261122T000337Z.md).
#
# The B1 class, in a suite this ride re-homed: tests/skills/test-aai-git-ref-guard.sh's new helpers git_isolated /
# install_module / install_ps1 set GIT_CONFIG_NOSYSTEM=1 and an empty GIT_CONFIG_GLOBAL but pass every other GIT_*
# variable of the caller through and never assert the resolved hooks path under the suite's scratch root. A
# core.hooksPath that arrives through the environment (GIT_CONFIG_COUNT/KEY_n/VALUE_n here; `git -c ...` hands the
# same thing to child processes as GIT_CONFIG_PARAMETERS) therefore lands the module's hooks outside the scratch root.
# The new suite and the node:test file are immune since 58eeff80 (they unset / drop every GIT_ variable).
#
# Safe: the "victim" is an empty directory this script creates with mktemp and removes again; it is not a
# repository. Run from the worktree root:
#   bash docs/ai/reviews/review-pre-commit-installer-on-node-20261122T000337Z-repro-N1.sh
# Exit 1 while the defect is present, 0 once it is gone.
set -u
ROOT="$(git rev-parse --show-toplevel)" || exit 2
[[ -n "$ROOT" && "$ROOT" == /* && -f "$ROOT/tests/skills/test-aai-git-ref-guard.sh" ]] || exit 2
VICTIM="$(mktemp -d "${TMPDIR:-/tmp}/review-r2n1-victim.XXXXXX")" || exit 2
[[ -n "$VICTIM" && "$VICTIM" == /* && -d "$VICTIM" ]] || exit 2

echo "== test-aai-git-ref-guard.sh test_642 (install_module) with core.hooksPath injected through the environment"
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$VICTIM" \
  env -u AAI_ROLE bash "$ROOT/tests/skills/test-aai-git-ref-guard.sh" test_642_ps1_decline_orders_write_before_removal 2>&1 | tail -3
echo "files written outside the suite's scratch root, in $VICTIM:"
ls -1 "$VICTIM"
n="$(ls -1 "$VICTIM" | wc -l | tr -d ' ')"
rm -f -- "$VICTIM/pre-commit" "$VICTIM/reference-transaction" "$VICTIM/pre-push"
rmdir -- "$VICTIM"
echo "RESULT: install_module wrote $n file(s) outside the scratch root"
[[ "$n" == 0 ]] || exit 1
exit 0
