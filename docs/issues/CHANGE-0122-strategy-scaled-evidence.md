---
id: strategy-scaled-evidence
number: 122
type: change
status: draft
user_visible: true
ceremony_level: 1
links:
  pr: []
  commits: []
---

# Change — evidence requirements scale with the recorded strategy (direct rides stop paying TDD ceremony)

Ceremony justification: L1 — one report-only finding class added to an existing
lint engine, one template section, and a 3-line prompt pointer. No new gate, no
exit-code change, no protected-surface edit; one suite covers it.

## Summary
- Live cost forensics (downstream InfluxDriver, Codex log 2026-08-04): a
  ONE-LINE pandas fix under the `direct` strategy still produced a spec
  demanding a STORED pre-fix RED artifact and a full test matrix. Review
  refused without the RED artifact -> Remediation reproduced the warning
  against base + Re-review = 2 full agent runs for evidence the chosen
  strategy never promised. That is TDD's contract leaking into non-TDD
  rides.
- Fix: PLANNING prompt + spec template derive the EVIDENCE CONTRACT from
  the recorded implementation strategy (CHANGE-0100): `tdd/hybrid` -> RED
  artifact + full matrix (unchanged); `direct` -> targeted regression tests
  green + scoped diff, NO stored RED artifact, NO matrix beyond declared
  versions; `untested` -> rationale + scoped diff only.
- Deterministic enforcement (prose doesn't fire): spec-lint gains a rule —
  a spec whose STATE-recorded strategy is direct/untested but whose AC/
  verification text requires a RED artifact or TDD-cycle evidence is a
  lint FINDING at write time (Planning fixes it before freeze, not Review
  three agents later).

## Acceptance Criteria
- AC-001: spec-lint flags a direct-strategy spec demanding RED artifacts
  (RED-first fixture) and passes the same text under tdd strategy.
  DELIVERED — `strategy-evidence-mismatch` in `.aai/scripts/spec-lint.mjs`;
  TEST-001/003(stratev) RED-proven (docs/ai/tdd/CHANGE-0122-red-spec-lint.txt),
  TEST-002(stratev) holds tdd/hybrid clean on identical text.
- AC-002: SPEC_TEMPLATE + PLANNING document the per-strategy evidence
  table; prompt bytes ledger-credited.
  DELIVERED — SPEC_TEMPLATE `### Evidence by strategy` (4 rows) + the
  direct/untested entries in Allowed strategy values; PLANNING step 7 pointer
  (+216 B, ledger entry `216 CHANGE-0122-…`, TEST-012 pin -11568 -> -11352,
  headroom 1150/2048); pinned by TEST-006(stratev).
- AC-003: tdd rides' requirements byte-unchanged (non-regression pins).
  DELIVERED — the rule reads only direct/untested; TEST-002(stratev) (tdd +
  hybrid clean), TEST-004(stratev) (waiver + strategy-rationale prose),
  TEST-007(stratev) + TEST-009 (real corpus clean).

## Strategy source (decided here)
- spec-lint reads NO state file and stays pure over the document. Precedence:
  `--strategy <v>` (a caller — orchestration/dispatch, VALIDATION — passing
  STATE's `implementation_strategy.selected`, enum-guarded, exit 2 on a bad
  value) > frontmatter `strategy:` if a project records it > the
  `- Strategy: <v>` body line SPEC_TEMPLATE already writes and the existing
  `frozen-without-strategy` check already reads.
- Unknown / `undecided` / unrecognized -> FAIL OPEN, zero findings.

## Verification
- `bash tests/skills/test-aai-spec-lint.sh` (TEST-001..007(stratev) added; RED
  first: 4 FAIL before the change, log in docs/ai/tdd/).
- `bash tests/skills/test-aai-prompt-diet.sh` (TEST-010 headroom 1150/2048,
  TEST-012 pin bumped).
- `bash tests/skills/test-aai-hygiene-pack.sh`, `bash
  tests/skills/test-aai-layer-profiles.sh`, release TEST-022.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` — CLEAN.

## Constraints / Risks
- Ceremony L1. Touches PLANNING prompt (ledger) + spec-lint.mjs + template.
- Boundary honesty: review may still ASK for more evidence as a finding —
  the change removes only the hard REQUIREMENT mismatch.
- Detection is textual: the rule scans only the evidence-bearing sections
  (AC Status, AC Mapping, Test Plan, Verification, Evidence contract), skips
  per-strategy guidance rows, and skips units that waive the artifact. A
  demand phrased without the artifact nouns (`RED log/artifact/proof/
  evidence`, `docs/ai/tdd/`, `tdd-evidence-check`, `TDD cycle evidence`,
  `RED-GREEN-REFACTOR`) is not detected — report-only, so a miss costs
  nothing beyond today's behavior.
