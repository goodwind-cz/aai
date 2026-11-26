#!/usr/bin/env bash
# Repro (review onboarding-tech-contract-and-lint-gaps r1): TEST-4134 pins the WHOLE live prompt corpus
# against 5f02b0e5 without subtracting later ledger entries, so the next ride that grows any prompt and
# credits its own entry 1:1 (the canonical D-GOV path) turns TEST-4134 red, while the sibling TEST-2824,
# which subtracts later entries' credits, stays green.
# Usage: repro-test-4134-next-ride.sh <worktree> <scratch-dir>   (exit 0 = defect reproduced)
set -uo pipefail
WT="$1"; SC="$2"
[[ -n "$WT" && "$WT" == /* && -n "$SC" && "$SC" == /* ]] || { echo "absolute paths required"; exit 2; }
rm -rf "$SC/tree"; mkdir -p "$SC/tree"
git -C "$WT" archive HEAD | tar -x -C "$SC/tree"
cd "$SC/tree" || exit 2
# baseline on the unmodified tree: TEST-4134 must pass
env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh test_4134_onboarding_ledger_entry >"$SC/base.out" 2>&1; base_rc=$?
# simulate a later ride: +10 B to one prompt, its own 1:1 ledger entry, TEST-012 pin bumped
printf '%s\n' 'Later rid' >> .aai/TECH_UPDATE_DIFF.prompt.md
printf '%s\n' 'JUSTIFIED_ADDITIONS+=( "10 later-ride Spec-AC-01 (simulated next scope): +10 B. Credited 1:1." )' > "$SC/entry"
awk -v e="$(cat "$SC/entry")" '/^JUSTIFIED_GROWTH_BYTES=0$/ { print e } { print }' tests/skills/lib/prompt-diet-ledger.sh > "$SC/ledger" && cp "$SC/ledger" tests/skills/lib/prompt-diet-ledger.sh
sed 's/local want_growth=68749/local want_growth=68759/' tests/skills/test-aai-prompt-diet.sh > "$SC/diet" && cp "$SC/diet" tests/skills/test-aai-prompt-diet.sh
env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh test_012_growth_sum_matches_ledger >"$SC/t012.out" 2>&1; t012_rc=$?
env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh test_2824_diet_entry_for_binding >"$SC/t2824.out" 2>&1; t2824_rc=$?
env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh test_4134_onboarding_ledger_entry >"$SC/t4134.out" 2>&1; t4134_rc=$?
echo "baseline TEST-4134 rc=$base_rc; after a later 1:1-credited ride: TEST-012 rc=$t012_rc TEST-2824 rc=$t2824_rc TEST-4134 rc=$t4134_rc"
grep -h 'TEST-4134' "$SC/t4134.out" | head -3
[[ $base_rc -eq 0 && $t012_rc -eq 0 && $t2824_rc -eq 0 && $t4134_rc -ne 0 ]]
