---
id: deslop-scope-and-unrequested-engine
number: 145
type: change
status: draft
user_visible: true
ceremony_level: 2
capability: aai-deslop
links:
  pr: []
  commits: []
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

## Adjudication Summary (moved from spec, point-in-time 2026-08-15 remediation)

Moved here from `docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md`
D3 by the 2026-08-15 REMEDIATION dispatch (round-6 validation V6 disposition
item 1, the PREFERRED option validation itself recommended): this document is
`type: change`, `status: draft`, under `docs/issues/`, so it sits outside the
deslop engine's `--all` requirement corpus (spec D2: `docs/specs/**`,
`type: spec` only) on three independent grounds, at zero engine change —
restoring the 10 rows below to `--all` candidate output. It was originally
folded into the spec as tracked content because `.gitignore:21` excludes
`docs/ai/reports/**`, making the full per-candidate walk below untracked and
machine-local; this summary remains its durable, reviewable home, now here
instead of the spec. The original untracked walk is unchanged at
`docs/ai/reports/deslop-candidate-adjudication-20260815.md`.

COUPLING (round-6 code review, NB-3): this table's exclusion from `--all`
candidate output works only because the `--all` corpus is `docs/specs/**`
only (fu-deslop-all-corpus-specs-only, P2, tracks widening it). If that
corpus is ever widened to include `docs/issues/**`, this table would become
part of its own suppression corpus again and all 10 rows below would
silently disappear from the live output a second time — move this table to
a non-corpus home before making that change.

This is a POINT-IN-TIME measurement: 60 of the underlying 70 real-tree
candidates were defensible and 10 indefensible as measured on 2026-08-15
against the round-5-remediation baseline
(`docs/ai/tdd/deslop-real-repo-all-baseline-20260815-round5-remediation.json`,
70/398). The tree moves with every merge; see the spec's D3 for the
reconciliation between that baseline and the current live count.

Of the 70 real-tree candidates, 60 (85.7%) are defensible — a genuine flag or
config key this repo's OWN code parses (a literal `tok === '--x'` / `args.x`
check, or a real, executable — not commented-out — usage string; for the two
YAML files, a real top-level key read by this repo's own loader), grouped by
file in the full report since the defense is identical within a file. 10
(14.3%) are indefensible: flag-shaped TEXT a syntactic, non-per-flag rule
cannot exclude without either a stoplist (forbidden by the spec's D3) or
string-content/intent analysis this pattern-based detector does not attempt
(this is exactly the residual class the engine's LIMITS block discloses —
spec D5). Each of the 10, with why it cannot be classified:

| # | symbol | site | why indefensible |
|---|---|---|---|
| 1 | `--git` | `.aai/scripts/deslop-unrequested.mjs:740` | a `line.startsWith('diff --git ')` string comparison — git's own diff-header literal, never a flag this code accepts. |
| 2 | `--grep` | `.aai/scripts/docs-audit.mjs:256` | a template-literal ADVISORY string suggesting a `git log --grep=...` triage command to the human reader; never invoked by this code. |
| 3 | `--no-renames` | `.aai/scripts/select-suites.mjs:212` | a SECOND, separate mention inside a `catch` block's error-message template literal describing the failed command (the real invocation, elsewhere in the same file, is correctly excluded). |
| 4 | `--all-features` | `.aai/scripts/aai-bootstrap.sh:524` | inside a `printf`'d SUGGESTED `cargo` command line; cargo is never actually invoked on this line. |
| 5 | `--all-targets` | `.aai/scripts/aai-bootstrap.sh:524` | same line, same reasoning as row 4. |
| 6 | `--hard` | `.aai/scripts/expert-fetch.ps1:207` | git's own flag embedded in a PowerShell regex PATTERN string used to detect dangerous prompt content; never invoked. |
| 7 | `--no-verify` | `.aai/scripts/expert-fetch.ps1:207` | same line, same reasoning as row 6. |
| 8 | `--prompt-file` | `.aai/scripts/autonomous-loop.sh:47` | belongs to whichever AGENT CLI a `%s` placeholder resolves to (a configured external agent's own headless-prompt flag), not to this script, which only builds the invocation string. |
| 9 | `--prompt-file` | `.aai/scripts/autonomous-loop.ps1:46` | PowerShell counterpart of row 8, same reasoning. |
| 10 | `--prompt-file` | `.aai/scripts/routine-emit.mjs:526` | site line 526 is dedupe's first-occurrence line, and IS Gemini's own real `--prompt-file` flag (a separately configured external agent CLI's surface, same category as rows 8-9) — NOT a generic placeholder. The actual generic placeholder example string is one line below at :527, whose surrounding comment (line 515) states the real Codex CLI has no such flag. (V6-3 correction, round-6 validation, 2026-08-15 remediation: the original row cited line 526 for the "generic placeholder" reason; the verdict and category were already correct, only the cited line was wrong.) |

The full per-candidate walk (all 70, not a sample — including the 60
defensible rows' file-grouped defenses) lives in the gitignored evidence
tree: `docs/ai/reports/deslop-candidate-adjudication-20260815.md`. This table
is that artifact's tracked summary, not a replacement for it; the original is
not deleted or moved.

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
