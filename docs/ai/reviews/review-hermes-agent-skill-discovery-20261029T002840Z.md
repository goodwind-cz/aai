```yaml
review:
  scope: "main..eb69da5201357a7436bb9cc39c80239cf54f4efc plus local source-integrity remediation and untracked helper"
  spec: docs/specs/SPEC-0259-spec-hermes-agent-skill-discovery.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/lib/hermes-skills-smoke.py:81; TEST-001/002 GREEN" }
      - { ac: Spec-AC-02, call: compliant, citation: "tests/skills/lib/hermes-skills-smoke.py:135; TEST-003 GREEN" }
      - { ac: Spec-AC-03, call: compliant, citation: "tests/skills/lib/hermes-skills-smoke.py:162; TEST-004 GREEN" }
      - { ac: Spec-AC-04, call: compliant, citation: "tests/skills/lib/hermes-skills-smoke.py:156; TEST-005 GREEN" }
      - { ac: Spec-AC-05, call: compliant, citation: "docs/USER_GUIDE.md:165; TEST-006 native and offline GREEN" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Ignored Hermes files and concurrent mutation after source preflight", closes_with: "Immutable complete source snapshot if such stronger attestation is required; current diagnostic expressly excludes it" }
    - { claim: "Other Hermes revisions, Windows-native Hermes and downstream model/UI execution", closes_with: "Separate native platform/revision and live execution evidence" }
    - { claim: "Original freeze-anchor drift cause and owner acceptance", closes_with: "Existing fu-amend-hermes-agent-skill-discovery disposition" }
  overall: pass
```

security_relevant: false

# Full-scope review after source-attestation remediation

Compliance PASS; code quality PASS. No open blocking or non-blocking findings. Actual model identity unavailable; no usage estimate asserted. The new preflight is evidence provenance checking, not an untrusted-code security boundary.

## Scope

Reviewed the complete current diff against main `3778b2c83d5f6a685a5e3f1036224ebaa86eb7e1`, with committed head `eb69da5201357a7436bb9cc39c80239cf54f4efc`, three modified tracked files and the untracked `tests/skills/lib/hermes-source-integrity.py`. Total delivery scope is 22 tracked changed paths plus that helper. It includes all docs, numbered intake/spec, generated closeout companions, append-only events/decisions, first two review reports, tests and suite registration/provenance previously enumerated in `review-hermes-agent-skill-discovery-20261029T002000Z.md`. Compared committed changes since that review as well as the new local diff; prior substantive conclusions remain applicable. STATE inline mode plus explicit dispatch establishes the expanded scope. No coaching or hidden scope exclusion was received.

## Acceptance criteria

| AC | Call | Evidence |
|---|---|---|
| Spec-AC-01 | compliant | Native TEST-001/002: source-derived exact catalog/descriptions, untrusted/revoked trust, deleted wrapper and nested cwd. |
| Spec-AC-02 | compliant | Native TEST-003: current-project canonical pointer and fixture prompt bytes; bad-pointer control fails. |
| Spec-AC-03 | compliant | Native TEST-004: repeated real sync, updated metadata and native reload; missing sync fails. |
| Spec-AC-04 | compliant | Native TEST-005: unrelated project/profile byte preservation and existing mirror parity; mutation fails. |
| Spec-AC-05 | compliant | Native TEST-006 plus offline guide routing and tracked product evidence checks; exact revision/profile/cwd/reload/support limits documented. |

The spec is unchanged; all six declared tests exist and freshly passed. No functional spec deviation found. Existing freeze-restamp owner follow-up is still disclosed, not silently waived.

## Executable evidence and external finding

PR comment 4407477853 was real and is remediated at `tests/skills/lib/hermes-skills-smoke.py:12`: Git status is checked before any Hermes imports, nonzero Git commands fail closed, tracked worktree/index and nonignored untracked changes are refused, and the checked HEAD is reused in evidence. Normal ignores are intentionally honored and that limit appears in the diagnostic. No frozen-snapshot or hostile-source claim is made.

`tests/skills/lib/hermes-source-integrity.py:28` tests the pre-import boundary using poison imports in a disposable Git fixture. Worktree, index and untracked mutations each fail before import; the clean source-check-only path succeeds. Git writes are scoped to the fixture; the installed Hermes checkout is untouched. Shell registration invokes these regressions before native execution; suite-map covers the helper. The earlier guide selection, tracked evidence link and weight provenance fixes remain present.

Fresh reviewer command, exit 0: `AAI_ROLE=subagent AAI_HERMES_SOURCE=/Users/ales/.hermes/hermes-agent AAI_HERMES_PYTHON=/Users/ales/.hermes/installs/de9aef5118c0fdd8/environments/3138bc2b34a540d8b91fc3df21e4db8d/venv/bin/python bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hermes-skills.sh`.

`/tmp/hermes-review-native-3.log` contains both offline GREEN results, four source-integrity GREEN results, clean Git-visible source revision `bf0203a794a07aac3ff764972ab9087baa4e4f4e`, and native `6/6 GREEN; native execution; no skipped evidence; no credentials or LLM calls`. Native mutation controls ran. `git diff --check` and `node .aai/scripts/sync-harness-skills.mjs --check` also exit 0.

Read failing-first poison-import evidence in `docs/ai/tdd/hermes-source-integrity-red.log`, repaired evidence in `docs/ai/tdd/hermes-source-integrity-green.log`, and independent `docs/ai/reports/VALIDATION-hermes-independent-4.md`. No implementation or STATE edits performed by reviewer.

## Disposition

No new WARNINGs. Named cannot-verify limits remain visible above. Stage this report with the remediation, apply the returned review command, reply to the external finding with its fixing SHA, and require hosted checks on that SHA before merge. No additional finding-bearing review round is requested.
