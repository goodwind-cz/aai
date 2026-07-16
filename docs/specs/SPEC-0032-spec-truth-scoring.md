---
id: spec-truth-scoring
type: spec
number: 32
status: draft
ceremony_level: 1
links:
  change: truth-scoring
  research: RES-0001
  rfc: null
  pr: []
  commits: []
---

# SPEC — Truth-Scoring on the Metrics Ledger (reliability facts at flush)

SPEC-FROZEN: true

Ceremony justification: S-sized additive extension of one functional surface —
the metrics pipeline (.aai/scripts/metrics-flush.mjs + metrics-report.mjs) and
its golden suite tests/skills/test-aai-metrics.sh. New fields are appended to
flushed ledger entries and one new report section is appended; no schema
migration, old ledger lines stay valid and render n/a. No `protected_paths_l3`
surface is touched (docs/ai/docs-audit.yaml checked at freeze: state engine,
allocator, guards, workflow canon, constitution — none in scope).

- Change: truth-scoring (docs/issues/CHANGE-0021-truth-scoring.md)
- Research: RES-0001 P3 (claude-flow truth-scoring concept minus the theater)
- Strategy: tdd — golden-tested byte-deterministic scripts; every AC lands
  RED-first in tests/skills/test-aai-metrics.sh.
- Worktree: recommended; user decision worktree
  (/Users/ales/Projects/aai-p3-truth, branch feat/truth-scoring, base main).
- Code review: required (L1 single dual-verdict pass). Scope: the four files
  in the AC table plus this spec, the CHANGE doc, and docs/INDEX.md.

## Constitution deviations

None. (Art. 1: every AC is golden/test-evidenced RED->GREEN. Art. 2: additive
counts over facts already recorded, no speculative scoring/routing. Art. 3:
plain JSONL/markdown. Art. 4: old lines and absent fields degrade to explicit
`n/a`, corrupt input still fails loud. Art. 5: strictly additive entry fields
and report section; old ledger lines never rewritten. Art. 6: STATE writes
unchanged — metrics-flush remains the sanctioned CHANGE-0009 standalone
multi-file transaction on the shared line engine; this change only ADDS
derived fields to the ledger entry it builds, it does not add STATE writes.
Art. 7: no merge performed.)

## Acceptance criteria

| Spec-AC | Requirement (measurable) | TEST |
|---------|--------------------------|------|
| Spec-AC-01 | `metrics-flush.mjs` writes on EVERY newly flushed ledger entry, after `totals` and before `verdict`: `"strategy": <string\|null>` and `"reliability": {"validation_fails": N, "review_fails": N, "remediation_runs": N, "first_pass_clean": bool}` derived ONLY from facts recorded in STATE per rules R1–R6 below — never estimated, never read from events. Golden line byte-exact. | TEST-006 (updated golden: clean run -> `strategy":"tdd"`, all counts 0, `first_pass_clean:true`), TEST-017 (derivation matrix: FAIL-noted validation + review runs, suffixed remediation roles, PASS-noted re-review NOT counted, null-note runs NOT counted as fails; `undecided` strategy -> null) |
| Spec-AC-02 | `metrics-report.mjs` appends a `### Per-Strategy Reliability` section: one row per strategy group (lexicographic; entries without a string `strategy` group under `n/a`), columns `strategy \| items \| first-pass clean \| avg validation fails \| avg review fails \| avg remediations`; ledger lines without a `reliability` object contribute `n/a` stats; output stays byte-deterministic (two runs byte-identical). | TEST-014 (existing golden extended with the all-`n/a` row — old lines unbroken), TEST-018 (mixed old+new golden section byte-exact + run-twice cmp) |
| Spec-AC-03 | `bash tests/skills/test-aai-metrics.sh` exits 0; full tests/skills sweep green (pre-existing environmental failures only, named); `node .aai/scripts/docs-audit.mjs --check --strict` CLEAN exit 0; `node .aai/scripts/check-state.mjs docs/ai/STATE.yaml` OK; flush idempotence probe: second flush run on an already-flushed fixture appends NO second ledger line. | metrics suite + sweep + audit + probe transcripts (docs/ai/tdd/truth-scoring-*.log) |

## Derivation rules (normative, part of Spec-AC-01)

Facts available to flush are exactly what it already reads: the per-ref
`metrics.work_items.<ref>.agent_runs` list (role, note, timing, tokens) and
the STATE singletons (`implementation_strategy`, verdict blocks). Flush does
NOT read docs/ai/EVENTS.jsonl (it only appends events best-effort), and
reset-block/flush provenance notes in the verdict blocks are overwritten by
later cycles — neither is a derivation source.

- R1 `remediation_runs`: count of runs whose `role`, lowercased, contains
  `remediation` (covers the recorded `Remediation (…)` suffix variants).
- R2 `validation_fails`: count of runs whose `role`, lowercased, contains
  `validation` AND whose recorded `note` matches `/\bVERDICT:\s*FAIL\b/i`
  (the recorded verdict-marker convention; folded `>-` notes are joined
  before matching).
- R3 `review_fails`: same marker test as R2, role contains `review`.
- R4 `first_pass_clean`: `true` iff R1 = R2 = R3 = 0.
- R5 `strategy`: `implementation_strategy.selected` read off STATE when it is
  a non-null string other than `undecided`; else `null`. Stamped on every
  entry flushed in that pass (the block is a singleton scoped to the
  validated refs of the pass).
- R6 honest limitations (documented, not worked around): a FAIL cycle whose
  run note is null or lacks the verdict marker is INVISIBLE to R2/R3 —
  `remediation_runs` remains the structural witness (a Remediation run is
  only ever dispatched after a recorded FAIL), which is why R4 requires all
  three counts to be zero rather than trusting R2/R3 alone. Counts are facts
  about what was RECORDED, never a reconstruction of what happened.
