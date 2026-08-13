---
id: doctor-honesty-batch
number: 138
type: change
status: draft
user_visible: true
ceremony_level: 1
capability: aai-doctor
---

# Change — doctor/config honesty batch: six recorded follow-ups, one scope

## Summary
- Owner approved 2026-08-13 ("ano" to the post-release backlog): close the
  six recorded follow-ups that all live in the doctor + update-config
  surface, as ONE ride instead of six micro-rides. Sources: decisions.jsonl
  dispositions of 2026-08-13 (CHANGE-0135 NB batch 01:26, CHANGE-0137
  batches 10:50 and 11:22).

## Acceptance Criteria
- AC-001 (N2, CAT-16): probeCodexExecSubcommand parses the `codex --help`
  output anchored to its `Commands:` block instead of the current
  indentation heuristic — the two false-positive prose fixtures (A/G) and
  the two false-negative command-list fixtures (C/D) from the 0135 rescope
  validation flip to correct verdicts; the 7-fixture battery becomes an
  11-fixture battery covering tab and single-space separators.
- AC-002 (F5): resolveCliVersion stops overloading ABSENT — an executable
  that resolves but yields an empty/failed --version reports
  `present: true, version: null` with a named reason, and a stderr
  diagnostic is never presented as the version string.
- AC-003 (F6): the CAT-16 one-line reason distinguishes absent from
  unknown — a timed-out/unreadable probe shows in the count line (e.g.
  `2/3 present, 1 unknown`), never folded into absence.
- AC-004 (BOM parity): a UTF-8 BOM no longer hides a first-line key from
  the column-0 config parsers — fixed in update-doctor-report.mjs AND
  update-check.mjs TOGETHER (parity invariant, SEAM-3 of SPEC-0124);
  one shared or twin-identical strip, pinned by tests on both parsers.
- AC-005 (config/retention honesty): update-config exists-but-unreadable
  yields a named degrade line (not silent default-on); retention prune
  failures emit one stderr diagnostic naming the undeletable file while
  stdout keeps its exactly-one-line contract.
- AC-006: tests per conventions, RED-first where a contract changes;
  docs (product docs for doctor + update) updated truthfully; no change
  to any exit-code contract; zero network/LLM preserved.
