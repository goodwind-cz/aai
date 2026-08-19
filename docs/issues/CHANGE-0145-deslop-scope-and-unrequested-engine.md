---
id: deslop-scope-and-unrequested-engine
number: 145
type: change
status: done
user_visible: true
ceremony_level: 2
capability: aai-deslop
links:
  pr:
    - 260
  commits:
    - c824367
---

# Change — deslop: scope becomes a parameter, and class 4 gets an engine

## Summary
- `/aai-deslop` is hardcoded to the current diff and its class-4 row
  ("Unrequested features: behavior, flags, or config no AC asked for") is a
  table entry that no code checks. Make scope an explicit parameter
  (`--diff`, `--all`, ask when unspecified — no default; fails closed) and
  give class 4 a mechanical detector that feeds both scopes from one engine.
- The wide scope IS RESEARCH-0001 F3 (`unrequested` is the one detection
  direction we lack). Folding it here means F3 needs no second home.

## Motivation / Business Value
- Verified in this tree on 2026-08-14: nothing dispatches deslop. The only
  reference outside its own prompt is one line in `.aai/AGENTS.md` marking it
  OPTIONAL. It runs when a human asks for it, which is precisely why a wide
  scope is safe here: the prompt's "never a repo-wide cleanup crusade" rule
  was written to stop an implementation agent from wandering mid-ride, not to
  cap a deliberately invoked pass. Owner call 2026-08-14: "je to skill co se
  spousti na vyzadani, cili by mohl mit siroky zaber nebo se zeptat."
- Every check we own asks "is the requirement covered?" — `spec-lint.mjs` does
  it bidirectionally (`ac-without-test`, `test-ac-unknown`) but only for
  in-flight specs at the freeze boundary. Nothing asks the reverse question
  about accumulated surface: does this code answer to any requirement? With
  most code here shipped autonomously, that is the specific exposure.
- Class 4 today depends on the agent noticing. A mechanical list turns a
  judgment call into a reviewable artifact.

## Scope
- In scope: scope parameter and its resolution (including the empty-diff
  branch); a new detection engine shared by both scopes; the scope-aware
  rewrite of the "Diff-scoped only" rule; the skill description; governance
  obligations for touching a vendored prompt (see Constraints).
- Out of scope: making deslop blocking or gating in any form; auto-deletion
  under `--all`; dispatching deslop from any workflow phase; acting on the
  first `--all` report (triage is a separate decision once the number is
  known).

## Affected Area
- `.aai/SKILL_DESLOP.prompt.md` (scope parameter, rules rewrite, output shape)
- `.claude/skills/aai-deslop/SKILL.md` (description says "current diff only")
- New: the class-4 detection engine under `.aai/scripts/`
- New: a test suite for the engine, plus a suite-map row
- `.aai/system/PROFILES.yaml`, prompt-diet ledger, TEST-012 pin

## Desired Behavior (To-Be)
- `/aai-deslop` with no scope argument ASKS which scope to use rather than
  assuming; an empty diff offers the wide scope instead of today's terminal
  "nothing to deslop".
- `--diff` reproduces today's behavior exactly for the five slop classes.
- `--all` walks accumulated surface and reports class-4 candidates only: the
  other four classes stay diff-only, because they are judgments about lines a
  change introduced and have no meaning against settled code.
- Both scopes run the SAME engine; the only difference is its input set.
- Output is report-only in both scopes: the engine never edits, and `--all`
  never edits at all. Exit code is always 0 — advisory means advisory.

## Acceptance Criteria
- AC-001: invoked with no scope argument, the skill asks for the scope and
  performs no scan until answered.
- AC-002: `--diff` on a fixture change reports the same class-4 candidates a
  correct manual pass would, and the other four classes behave as today.
- AC-003: with an empty diff, the skill offers the wide scope rather than
  stopping at "nothing to deslop".
- AC-004: `--all` on a fixture tree lists every exported symbol, flag and
  config key that no AC text mentions, and lists nothing that is mentioned.
- AC-005: the engine writes no file and changes no byte under either scope;
  proven by a byte-identity assertion over the fixture tree before and after.
- AC-006: exit code is 0 for a clean run, a run with findings, and a run over
  an empty input set.
- AC-007: the "Diff-scoped only" rule in the prompt no longer reads as
  absolute and states which scope it binds.
- AC-008: the skill description no longer claims the pass is diff-only.

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-deslop.sh`
  (the LEARNED rule: never invoke the runner directly)
- `node <engine> --all --json` over the repo, recording the raw candidate
  count as the triage baseline
- `bash tests/skills/test-aai-prompt-diet.sh` for the TEST-012 pin
- `node .aai/scripts/docs-audit.mjs` clean

## Constraints / Risks
- Node stdlib only, zero dependencies (docs/TECHNOLOGY.md). Symbol extraction
  is therefore pattern-based, not a real parser — the engine must state that
  limit in its own output rather than implying completeness.
- Editing a vendored `.aai` prompt carries the prompt-corpus governance
  checklist: prompt-diet ledger entry, TEST-012 pin bump, PROFILES
  classification for any new file. Missing one of these fails CI, not review.
- The first `--all` run over roughly 8.6k lines of scripts will almost
  certainly surface legitimate code. That is expected and is why the output is
  report-only: a detector whose first run is noisy is still useful, a gate
  whose first run is noisy is a blocker. Triage happens after the number
  exists.
- False negatives are the quieter risk: an AC that mentions a symbol only in
  prose will suppress a real finding. Accepted for the first cut and named in
  the output.
- No secret is referenced by this scope.

## Adjudication Summary — relocated (2026-08-18)

The Adjudication Summary this section used to hold (its preamble, its NB-3
coupling note, the 10-row indefensible-candidate table and its closing
pointer) moved verbatim to
`docs/analysis/deslop-candidate-adjudication-20260815.md` by
`spec-deslop-corpus-honesty`. The coupling that section's own NB-3 recorded
in advance is why: that spec widens the `--all` requirement corpus to
include `docs/issues/**`, and this document — `type: change`, under
`docs/issues/` — would otherwise re-enter its own suppression corpus and
silently drop the 10 rows a second time. The table's new home is outside the
corpus on two grounds (directory, and `type: research`), not one. The
underlying untracked full walk is unchanged at
`docs/ai/reports/deslop-candidate-adjudication-20260815.md`.

## Notes
- Explicit assumptions, recorded instead of asking (ship autopilot default 3):
  - A1 — requirement text for `--diff` is the in-flight scope's spec resolved
    from STATE focus; for `--all` it is the union of AC text across frozen and
    done specs. Planning may narrow this.
  - A2 — the surface scanned is exported symbols in `.mjs`, function names and
    flags in `.sh`/`.ps1`, and config keys in `.aai/system/*.yaml`.
  - A3 — the engine reports; a human or agent still decides every deletion.
  - A4 — `--all` is read-only by construction, not by convention.
- `ceremony_level: 2` is a suggestion from intake (new behavioral surface plus
  a vendored prompt edit); Planning declares the binding value at freeze.
- Source: RESEARCH-0001 F3, and F1 for why spec-lint is the wrong host (it is
  scoped to in-flight specs at the freeze boundary).
- Owner deferred two larger items on 2026-08-14 before choosing this one: the
  shell-twin parity tax (P1) and the F5 update-manifest scope.
