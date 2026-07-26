---
id: pr-post-open-review-sweep
number: 60
type: change
status: done
links:
  pr:
    - 160
  commits:
    - 899712c074347e65520ca496ba2fb9e6729675c3
---

# Change — SKILL_PR step 5d: post-open bot-review sweep before merge-readiness

## Summary
- Codify the post-open review sweep as SKILL_PR step 5d: after `gh pr create`,
  external reviewer bots (Copilot, Codex) post inline comments that do NOT
  appear in `gh pr checks`; the ceremony must read them after CI completes,
  fix legitimate findings on the same branch as a review-response commit,
  rebut false positives in a PR comment, and wait for the CI re-run before
  any merge-readiness claim.

## Motivation / Business Value
- The sweep currently lives only in session discipline and operator memory
  (memory note check-pr-bot-review-comments, 2026-07); PRs #158 (7 findings)
  and #159 (3 findings + 1 fix-of-fix) prove the bots catch real defects
  (unbounded marker regex, weak grep anchoring) that the in-pipeline review
  missed. Uncodified, any other agent/operator merges past them.
- Operator direction 2026-07-26: "zapracuj to do SKILL_PR jako 5d".

## Scope
- In scope: .aai/SKILL_PR.prompt.md new step 5d (~12 lines) between 5c and 6;
  prompt-diet ledger itemized entry + TEST-012 pinned-total bump; any suite
  stanza pinning SKILL_PR structure.
- Out of scope: automation of the sweep (a future script could diff comment
  timestamps vs last push); merge boundary semantics (unchanged).

## Affected Area
- .aai/SKILL_PR.prompt.md, tests/skills/lib/prompt-diet-ledger.sh,
  tests/skills/test-aai-prompt-diet.sh (pin bump), CHANGELOG.md.

## Desired Behavior (To-Be)
- SKILL_PR contains step 5d with: post-CI comment poll (gh api pulls/<n>/
  comments + gh pr view --json reviews), triage duty (fix on-branch OR rebut
  in a PR comment, never silent), review-response commit + summary comment,
  CI re-run wait, unchanged never-merge boundary.

## Acceptance Criteria
- AC-001: SKILL_PR step 5d exists between 5c and 6 with the four duties
  (poll, triage fix-or-rebut, response commit + summary comment, re-run
  wait) — grep-verified tokens.
- AC-002: prompt-diet ledger carries the measured positive entry; TEST-012
  re-sum matches; headroom stays in [0, 2048]; suite green.
- AC-003: no other SKILL_PR step renumbered; merge-boundary section 6
  byte-identical.

## Verification
- bash tests/skills/test-aai-prompt-diet.sh
- bash tests/skills/test-aai-hygiene-pack.sh (SKILL_PR structural pins)
- grep contracts per AC-001/003; PR CI full framework.

## Constraints / Risks
- No secrets referenced (secrets preflight skipped).
- Ceremony level 1 (single-surface prompt addition, operator-directed).
  Ceremony justification: single-file prompt step addition with mechanical
  companions; measurable ACs; no protected surface.
- Local-run policy: targeted suites only; CI is the binding full run.

## Notes
- Evidence base: PR #158 review response commit 0159096 (7 findings);
  PR #159 review response commits 73d1ed4 + 4d75d71 (3 findings + quoted
  pointer form). Promotes memory-note discipline to canon.
- Autopilot intake (/aai-ship): metrics question skipped, human_time_minutes
  intake recorded as null.
