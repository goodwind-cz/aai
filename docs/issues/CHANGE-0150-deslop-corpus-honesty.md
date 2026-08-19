---
id: deslop-corpus-honesty
number: 150
type: change
status: done
user_visible: false
ceremony_level: 1
capability: aai-deslop
links:
  pr:
    - 265
  commits:
    - 6160a86dd12bcc3fee2b7513205776867279300f
---

# Change — three defects in one corpus resolver

## Summary
- `resolveAllCorpus` in `.aai/scripts/deslop-unrequested.mjs` carries three
  separately-filed registry items. All three were reproduced against the
  current tree on 2026-08-18 before this intake was written.
- Cluster ride number two. The registry stands at 54 and one-item-per-scope
  cannot drain it, so items are batched by the function they live in.

## Motivation / Business Value
- The detector's whole claim is "this code answers to no requirement". Today it
  reads only `docs/specs/**`, so a flag someone explicitly asked for in a CHANGE
  or RFC document is reported as unrequested. Measured now:
  `--worktree-guard`, `--worktree-baseline` and `--pr-config` are all live
  candidates and all three were requested in committed CHANGE docs.
- A tool that calls requested work unrequested erodes trust in every other row
  it prints.

## Scope
- In scope: the corpus definition, the silent skip of an unreadable spec, and
  the missing accounting in the header, all in `resolveAllCorpus`.
- Out of scope: the `--diff` corpus (a different resolver with its own rules);
  any change to what surface is scanned; the extractor kinds.

## Affected Area
- `.aai/scripts/deslop-unrequested.mjs` (`resolveAllCorpus` and its header)
- `tests/skills/test-aai-deslop.sh`
- `docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md` (D2 states
  the corpus rule and would become false)

## Desired Behavior (To-Be)
- D1 — the requirement corpus includes the document types where requirements
  are actually written, not only `docs/specs/**`. Which types, and on what
  status filter, is Planning's call — see the coupling in Constraints.
- D2 — a spec file that cannot be read is named, the way the `--diff` resolver
  already names it. Today `--all` skips it silently while `--diff` reports it,
  and that asymmetry is the finding.
- D3 — the header's document accounting balances: every file the resolver saw
  lands in a named bucket, and a count that does not add up says so.

## Acceptance Criteria
- AC-001: a flag or config key named in a committed CHANGE or RFC document is
  not reported as a candidate, demonstrated on the three real symbols above.
- AC-002: the corpus rule stated in the header output matches the rule the code
  applies, for whatever corpus Planning settles on.
- AC-003: an unreadable requirement document produces a named note under
  `--all`, matching the wording contract the `--diff` path already satisfies.
- AC-004: the included count plus every excluded bucket equals the number of
  documents the resolver examined, and a residue is reported rather than
  dropped.
- AC-005: SPEC-0132's D2 corpus sentence is corrected in the same change, so no
  shipped document describes the old rule.
- AC-006: the engine stays report-only — no gate, no exit-code change.

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-deslop.sh`
- run whatever `node .aai/scripts/select-suites.mjs --files-from <changed
  files>` returns, and additionally `tests/skills/test-aai-layer-profiles.sh`
  and `tests/skills/test-aai-feedback-upsert.sh` — the previous ride proved the
  selector's list is not a superset of what CI runs
- `node .aai/scripts/deslop-unrequested.mjs --all` over this repo, and check the
  three named symbols are gone from the candidate list

## Constraints / Risks
- **The coupling that decides this scope.** `fu-deslop-adjudication-self-suppression`
  records that a symbol named anywhere in a corpus document is suppressed.
  CHANGE-0145 moved its adjudication table out of the spec and into
  `docs/issues/CHANGE-0145-...` precisely to get those ten rows back. Widening
  the corpus to `docs/issues/**` re-suppresses all ten. Planning must decide
  this deliberately and say so — either accept the loss with a reason, or find
  a corpus rule that admits requirements without admitting findings-about-the-tool.
  Do not widen the corpus without addressing it.
- Widening the corpus lowers the candidate count. That is the point, but it
  also means the numbers published in SPEC-0132, the CHANGELOG and the product
  doc go stale — re-baseline every figure the change moves, measured not
  predicted.
- Node stdlib only, zero dependencies. Report-only throughout.
- No secret is referenced by this scope.

## Notes
- Registry items closed by this scope: `fu-deslop-all-corpus-specs-only`,
  `fu-deslop-allcorpus-unreadable-silent`,
  `fu-deslop-corpus-header-other-bucket`.
- Reproductions run before writing this doc: the corpus filter is
  `walk('docs/specs')` with `fm.type !== 'spec'`; a live `--all` run lists all
  three requested flags among 65 candidates; the header prints five status
  buckets with no residue accounting.
- Strategy suggestion: direct with targeted tests. Planning declares the
  binding ceremony level.
