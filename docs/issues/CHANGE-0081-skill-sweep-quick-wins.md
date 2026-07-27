---
id: skill-sweep-quick-wins
number: 81
type: change
status: draft
user_visible: false
links:
  pr: []
  commits: []
---

# Change — skill-sweep batch: three verified quick-win fixes + six findings intakes

## Summary
- Batch delivery of the skill-sweep audit (three parallel hands-on
  auditors over ~20 previously untouched skills; journal section in
  docs/project-sessions/2026-07-26-independent-audit-autonomy-pack.md):
  (1) aai-canonicalize.sh: 5 empty-array expansions crash under macOS
  default bash 3.2 with set -u — fixed with the empty-safe
  ${arr[@]+"${arr[@]}"} idiom (the naive "${arr[@]-}" form regressed the
  default texts and was rejected in review), verified with /bin/bash;
  (2) test-canon.mjs: --help/any unknown flag silently fell through to a
  LIVE phase-1 run that writes docs/ai/test-canon.proposal.json (fired
  during the audit itself) — usage branch added, exit 0/2, TEST-020 pin;
  bonus review-window fix: pre-existing $ROOT$ROOT path doubling at line 85
  silently skipped the YAML->JSONL migration branch — corrected;
  (3) generate-dashboard.mjs: positional-arg parser compared against
  default STRINGS, mis-routing the 2nd positional into metricsPath and
  silently overwriting docs/ai/dashboard.html — explicit consumed-slot
  booleans, reproduced and verified both orders.
- Six findings filed as intakes: doctor-determinize, dashboard-refit,
  docs-hub-generator, session-journal-contract, validate-report-contract,
  decapod-prune.

## Acceptance Criteria
- AC-001: /bin/bash aai-canonicalize.sh . --dry-run emits zero unbound
  errors AND empty detection categories still render their default text
  ("Not detected" / "Unknown...") — the review-caught regression of the
  first fix idiom (single-empty-arg expansion) is covered (verified live
  on an empty fixture repo).
- AC-002: test-canon --help exit 0, unknown flag exit 2, no proposal
  write either way (TEST-020, suite 20/20).
- AC-003: dashboard positional and flag invocations both write only the
  requested output path; repo dashboard untouched (verified live).

## Verification
- bash tests/skills/test-aai-test-canon.sh (20/20)
- /bin/bash .aai/scripts/aai-canonicalize.sh . --dry-run
- node .aai/scripts/generate-dashboard.mjs <positional and flag forms>

## Constraints / Risks
- Ceremony L2 (three tooling scripts, no protected L3 surface, no prompt
  corpus bytes); review: single dual-verdict pass on the script diffs.
