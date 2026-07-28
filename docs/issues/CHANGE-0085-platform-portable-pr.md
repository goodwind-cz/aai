---
id: platform-portable-pr
number: 85
type: change
status: done
user_visible: true
links:
  pr:
    - 185
  commits:
    - e411d52865466082f0721160d8bfcfdcba057434
---

# Change — platform-portable PR ceremony: GitHub/Azure detection + internal review fallback when no external reviewers exist

## Summary
- SKILL_PR steps 5/5d are GitHub-bound (gh pr create, gh api pulls/N/comments)
  and assume auto-assigned reviewer bots. On Azure Repos the ceremony fails
  at PR creation, and even with a port the 5d sweep would silently no-op
  (no auto reviewers). Operator direction 2026-07-28: (1) platform-detect
  the remote (github.com vs dev.azure.com) and branch the ceremony
  (gh vs az repos pr); (2) when the platform has NO external reviewers,
  5d MUST dispatch the internal .aai/SKILL_CODE_REVIEW.prompt.md
  (dual-verdict, independent model) on the FINAL PR diff — same pipeline
  position the bots hold on GitHub — and handle its findings through the
  same fix-or-rebut flow; never a silent empty sweep.

## Scope
- In scope:
  - Deterministic platform probe (new .aai/scripts/pr-platform.mjs or a
    guarded inline step): parse `git remote get-url origin` -> github |
    azure | unknown; unknown = fail loud with guidance, never guess.
  - SKILL_PR.prompt.md: platform-branched step 5 (gh vs az repos pr
    create/thread list/reviewer add); 5d gains the no-external-reviewers
    fallback (dispatch SKILL_CODE_REVIEW on the final diff, triage its
    findings via the canonical EXTERNAL-REVIEW RESPONSE flow, record
    "internal review substituted for absent bot layer" in the PR).
  - Az equivalents documented: az repos pr create / thread list /
    reviewer add; branch-policy note (required reviewers + build
    validation = Azure's gate job).
  - Prompt-diet ledger + TEST-012 pin for corpus growth; grep pins for
    the fallback contract.
- Out of scope: GitLab/Bitbucket (recorded as future variants); changing
  the merge boundary (agent still never merges without authorization).

## Acceptance Criteria
- AC-001: platform probe returns github/azure/unknown deterministically
  for representative remote URLs incl. ssh forms (suite-verified).
- AC-002: SKILL_PR names both platform branches and the az command set;
  grep-pinned; unknown platform = documented fail-loud.
- AC-003: 5d fallback contract pinned — when external reviewers are
  absent, SKILL_CODE_REVIEW dispatch is REQUIRED before merge-readiness;
  the empty-sweep shortcut is only legal on platforms WITH bot layers.

## Additional operator requirements (2026-07-28)
- Internal-review findings MUST be published as PR THREADS via the
  platform API (gh api pulls/N/comments on GitHub, az repos pr thread
  create on Azure) so the audit trail on the PR is identical whether the
  reviewer was a bot or the internal role, and human reviewers see the
  findings where they expect them.
- GENERIC MODE for any other git hosting (GitLab/Bitbucket/bare/no
  remote): platform PR mechanics are skipped, internal SKILL_CODE_REVIEW
  is MANDATORY, verdict + findings land in repo artifacts
  (docs/ai/reports/ + spec dispositions), merge stays with the owner's
  process, and the ceremony says loudly: "platform PR API unavailable —
  internal review substituted, merge is yours". Never a silent quality
  skip.

## Verification
- new/extended suite for the probe; prompt-diet; grep pins.

## Constraints / Risks
- Ceremony L2. Az CLI behavior not live-testable here (no Azure remote):
  command forms verified against az CLI docs; live proof deferred with
  Review-By on first Azure adoption.
