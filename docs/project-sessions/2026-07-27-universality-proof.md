# Universality proof — AAI layer on a virgin non-AAI project (2026-07-27)

Claim under test: the factory is universal — any project scale, user only
states needs. Method: hands-on, no simulation. A real 40-line Node CLI
("tempo": BPM/ms/Hz conversions, `node --test` suite, own git history) was
created outside the repo, AAI was bootstrapped onto it via `install.sh
--source-root <aai> --target-root <project>`, and one complete factory
cycle was executed inside the target using only the synced layer.

## What ran unmodified (positives)

1. `install.sh` bootstrap: 70 scripts, system files (MODEL_ROUTING.yaml
   included), TECHNOLOGY.md template, skills — self-hosting assertions
   green on a project that is NOT the fixture.
2. Deterministic dispatch on the target: fail-closed `needs_llm`
   (state_file_missing) on the virgin tree; after STATE init, correct
   rule-5 Planning dispatch with `suggested_model: claude-opus-4-8` (the
   synced MODEL_ROUTING binds) and a live `Prompt hash:` line.
3. Full ride: intake -> frozen L1 spec -> TDD (genuine RED exit 1 ->
   GREEN 5/5) -> validation recorded (maker haiku / checker opus split) ->
   `close-work-item` -> `metrics-flush`.
4. **First live non-null `prompt_hash` in a METRICS ledger** — the
   SPEC-0098 consumer wiring, dogfooded end-to-end on the target: the
   dispatch JSON hash was passed via `append-run --prompt-hash` and
   survived flush byte-unchanged.
5. Product layer: close gate correctly WARNED (report-only default) about
   the missing product doc for a `user_visible` scope; after writing the
   doc per PRODUCT_TEMPLATE, the USER_GUIDE rollup rendered the feature.
   Generated INDEX.md, overview.html, overview-data.json all correct on
   the target.

## Findings (each -> intake)

- F1 (P1, universality): a virgin target cannot mechanically init STATE.
  The canonical schema lives only in the STATE.yaml header comment — a
  file that does not exist yet; `check-state --repair` errors instead of
  creating; `state.mjs` refuses to write; ORCHESTRATION step 4 promises
  "create with canonical schema defaults" that nothing ships. The proof
  hand-copied the schema header from the mothership — exactly what a
  target-project operator cannot do. Intake:
  `state-bootstrap-template` (ship .aai/templates/STATE_TEMPLATE.yaml +
  teach check-state --repair to create from it).
- F2 (minor, honesty): `generate-userguide-rollup.mjs` silently excludes
  a product doc that fails the placeholder predicate — output says
  "0 delivered feature(s)" with no reason line (violates the factory's
  own no-silent-truncation principle). Intake:
  `rollup-exclusion-visibility` (one NOTE line per excluded doc naming
  the missing section).
- F3 (observation, no AAI change): the proof's own first RED/GREEN logs
  were polluted by a broken test invocation (`node --test test/` dir form
  + set -e && pipeline blindness) — caught because exit codes, not output
  lines, are the factory's evidence contract. The discipline the wrapper
  enforces in-repo applied verbatim; logs were re-cut honestly.

## Scaling profile

Written into docs/USER_GUIDE.md ("Scaling profile" section, v1.6):
L0-L1 tiny projects (waived review with rationale, deterministic
validation), L2 team defaults (maker≠checker, dual-verdict, CI impact
selection), L3 regulated (protected paths + operator sign-off).

## Artifacts

Scratch target project (session-local, disposable):
`<scratchpad>/uniproof` — git history: baseline, bootstrap commit,
feature commit, close-artifacts commit. Evidence quoted above lives in
the target's docs/ai/ ledgers; this journal is the durable record.
