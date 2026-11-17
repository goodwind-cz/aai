# Code review — pr-ceremony-friction-fixes (round 1)

- Scope: git diff c1034b24..2ca48983 (15 files), ceremony level 3
- Reviewer: independent subagent, claude-opus-5-5, read-only (no suites run; a full sweep was in flight)
- spec_compliance: PASS — Spec-AC-01..07 compliant (AC walk below); deviation: post-freeze Mutation-cell edits disclosed by two spec_amendment records (contract record unsigned, tracked by fu-amend-spec-pr-ceremony-friction-fixes; signs on merge)
- code_quality: PASS — BLOCKING: none

security_relevant: true

## AC walk
- Spec-AC-01 compliant: name_check=0 for the four folders; TEST-3831 commits through the installed hook; mutation RED.
- Spec-AC-02 compliant: content scan reads git show ":$file"; TEST-3832 in and outside evidence folders; mutation RED.
- Spec-AC-03 compliant: dotenv override; other paths keep the name check; src/docs/ai/tdd/secret.txt still blocked (root-anchored); mutation RED.
- Spec-AC-04 compliant: staged first, exit 9, read-only; mutation RED.
- Spec-AC-05 compliant: 10/0/0/4; missing value 4, --pre-commit-head without --sync-ready 4.
- Spec-AC-06 compliant: SKILL_PR step 4 note, step 5b --sync-ready before merge, VALIDATION sentence; mutation RED.
- Spec-AC-07 compliant: +284/+139 = 423 B; TEST-012 67057->67480; TEST-2936 base; pr-preflight sums; TEST-3454 19 11; TEST-3461 331/247.

## NON-BLOCKING findings and dispositions
1. CHANGELOG overclaimed "removed from the working tree" (a deleted-after-staging file is skipped by the existing [ -f ] check). Disposition: wording fixed in this PR ("rewritten in the working tree"); the deleted-after-staging case filed as follow-up fu-precommit-deleted-staged-skip.
2. Suffix env names (docs/ai/tdd/prod.env) pass in evidence folders by name (content scan still runs); matches D2. Disposition: follow-up fu-precommit-suffix-env-evidence.
3. --pre-commit-head silently ignored with --pin/--verify-pin. Disposition: fixed in this PR (the usage check runs before the pin modes; TEST-3835 asserts --verify-pin --pre-commit-head exits 4).
4. Pre-existing: non-ASCII staged names are quoted by git and skipped by [ -f ]. Disposition: follow-up fu-precommit-quoted-path-skip.

## cannot_verify
- Full suites / sweep (not run by reviewer; orchestrator sweep recorded separately).
- frozen_sha256 vs amendment records (closed by spec-amend list --strict and mutation-run --replay, both green).
- Agent adherence to SKILL_PR prose (spec residual risk 2).

## Delta after the reviewed head (2ca48983)
- f15ace68: NB-3 fix (usage check before the pin modes) asserted by TEST-3835 (mutation replay RED), TEST-3278 prompt-glob pin +423 B, CHANGELOG wording per NB-1. Re-observed by the independent validator (round 1 PASS, docs/ai/reports/VALIDATION-20261116T213657Z-pr-ceremony-friction-fixes.md).
- acc37e75: merge of origin/main (#564); no ride file touched by it; full sweep test-20261116-211411 rc 0 on this head.
