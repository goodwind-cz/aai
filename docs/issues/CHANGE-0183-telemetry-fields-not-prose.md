---
id: telemetry-fields-not-prose
type: change
number: 183
status: draft
links:
  pr: []
  commits: []
---

# Run telemetry is recorded as fields, so cost and reliability stop depending on prose

## Summary
- Roadmap wave 2, pair 1, maintenance half, paired with
  `harness-universal-routing`.
- `state.mjs append-run` stores harness usage in the free-text `note`:
  `usage_total_tokens=...`, `requested_model=... actual_model=...`, and a
  verdict marker `VERDICT: FAIL`. `metrics-flush.mjs` then parses those
  markers back out to derive cost, model and reliability.
- Measured on 2026-09-12: `total_cost_usd` is null on all 137 ledger
  entries; `model_id` is unknown on 27 of 620 runs; `validation_fails` sums to
  1 across the ledger while `remediation_runs` sums to 67, because a note that
  reads `VERDICT FAIL` (no colon) counts as no failure. RES-0002 had to
  hand-parse the same markers to measure where tokens go. Friction
  observations record `os_family` and `node_major` but not the harness.
- The factory report's 76% first-pass-clean rate is built on those fields and
  cannot be trusted.

## Motivation / Business Value
- Every planning decision about models, tiers and harnesses is judged on this
  ledger. When the ledger's cost, model and verdict columns are derived from
  substrings of prose, the numbers are whatever the last note-writer typed.
- The ledger is append-only by canon (HAZ-LEDGER), so a wrong number can never
  be corrected in place. The only defence is to make it right at append time.
- Pair 1's capability half routes per harness; without a `harness` field on
  runs and observations, nothing can later say whether that routing did
  anything.

## Scope
- In scope: structured fields on `append-run` (`--harness`, `--tokens-total`,
  `--verdict`, `--requested-model`, `--actual-model`), written into
  `agent_runs` entries; flush derives cost, model and reliability from fields
  first and from note markers only as a labelled fallback; refusal of a
  Validation or Code Review run appended without a verdict; `harness` on
  friction observations and in the upsert payload's structured list; the
  factory and metrics reports show which basis each number came from.
- Out of scope: rewriting existing ledger lines (append-only); changing what
  `close-work-item.mjs` writes into `work_item_closed` (protected,
  hash-pinned; SPEC-0175 R6 names the hardcoded `validation: pass`); per-token
  input/output split when the harness does not expose it.

## Affected Area
- `.aai/scripts/state.mjs` (`append-run`), `.aai/scripts/metrics-flush.mjs`
  (reliability and cost derivation), `.aai/scripts/lib/usage-note.mjs`,
  `.aai/scripts/aai-friction.mjs` and `.aai/scripts/aai-feedback-upsert.mjs`
  (observation schema and payload), `.aai/scripts/generate-factory-report.mjs`
  and `metrics-report.mjs`, the STATE schema header, `.aai/SUBAGENT_PROTOCOL.md`
  where it tells the orchestrator what to record, and the suites for each.

## Desired Behavior (To-Be)
- `append-run` accepts `--harness`, `--tokens-total`, `--verdict pass|fail|none`,
  `--requested-model` and `--actual-model` and writes them as fields on the run.
  Existing note markers remain accepted for back-compatibility.
- A run whose role is Validation or Code Review is refused at append time when
  `--verdict` is absent, with a message naming the flag; a run of any other role
  defaults to `none`.
- Flush derives `validation_fails` and `review_fails` from the verdict field;
  when a run has no field it falls back to the note marker and prints a NOTE
  naming the run and the basis. `cost_usd` is computed from `--tokens-total`
  at a blended rate from PRICING when the input/output split is unknown,
  labelled `cost_basis: total-blended`; it is null only when no token figure
  exists at all, with a NOTE.
- Friction observations carry `harness`; the upsert payload lists it beside
  `os_family` and `node_major`.
- The factory report and metrics report show, per entry, the verdict source
  (field or marker) and the cost basis, so a reader can tell measured numbers
  from reconstructed ones.

## Acceptance Criteria
- AC-001: `append-run` with the five new flags writes five fields on the run and
  a subsequent `check-state` passes; the same call without them still succeeds
  for a non-verdict role.
- AC-002: `append-run --role Validation` without `--verdict` exits 2 naming the
  flag; with `--verdict fail` it writes `verdict: fail`.
- AC-003: a fixture STATE with two Validation runs carrying `verdict: fail` and
  no note marker flushes to `validation_fails: 2`; the same fixture with the
  fields removed and notes reading `VERDICT FAIL` (no colon) flushes to 0 with
  a NOTE naming both runs as marker-derived.
- AC-004: a run with `tokens-total` and a model that resolves in PRICING flushes
  to a non-null `cost_usd` with `cost_basis: total-blended`; a run with no token
  figure flushes to null with a NOTE.
- AC-005: `aai-friction.mjs` records `harness` on a new observation and the
  prepared upsert draft lists it; an observation without it (legacy) still
  triages.
- AC-006: the factory report renders a verdict-source and cost-basis column and
  distinguishes legacy entries from field-derived ones.
- AC-007: no existing ledger line is modified; the ledger before and after the
  scope's own flush differ only by appended lines.

## Verification
- Unit fixtures for `append-run` and `metrics-flush` covering AC-001 to
  AC-004, including a mutation that deletes the field-first branch and must
  redden the fixture of AC-003.
- `bash tests/skills/test-aai-friction.sh` and the upsert suite for AC-005.
- `generate-factory-report.mjs` on a fixture ledger mixing legacy and
  field-derived entries for AC-006.
- `cmp` of the ledger prefix for AC-007.

## Constraints / Risks
- HAZ-LEDGER: `docs/ai/METRICS.jsonl` and `docs/ai/decisions.jsonl` are
  append-only; nothing in this scope edits an existing line.
- The harness may expose only a total token count; the blended-rate cost is
  an estimate and must be labelled as one, never presented as measured.
- `close-work-item.mjs` is protected; its hardcoded `validation: pass` in
  `work_item_closed` stays a named residual, not a change here.
- No secret is referenced by this scope; secrets preflight skipped.

## Notes
- Source evidence: Codex P2 on PR #374 (`METRICS.jsonl:169` records
  `validation_fails: 0` for a ride with two `VERDICT FAIL` runs), the ledger
  aggregates measured during the wave 2 assessment, and RES-0002's own
  marker-parsing script. Filed follow-up: `fu-reliability-marker-is-freetext`.
- Implementation mode (user choice): tdd — every AC is a derivation that can
  silently produce a flattering number, and the day's evidence is that such
  numbers were produced.
