---
id: spec-scryer-mcp-and-shallow
type: spec
number: 116
status: done
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0129-scryer-mcp-and-shallow.md
  rfc: null
  pr:
    - 239
  commits:
    - 949fed6e7903e77f43f57600742b942575f09706
---

# Spec — Scryer template v2: MCP-aware tool ladder + shallow-clone-honest health

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0129-scryer-mcp-and-shallow.md
- Prior spec (template + emitter this change edits): docs/specs/SPEC-0115-spec-universal-routines.md
- Decision records: docs/ai/decisions.jsonl (`routine_authorization` for
  `aai-morning-scryer`) — unchanged by this scope
- Technology contract: docs/TECHNOLOGY.md

## Summary

Two production runs of the morning scryer (2026-08-08 and 2026-08-09, cloud
trigger `trig_01XpMxioptoJ7j32YKzzaKnR`) hit environment realities the
`.aai/routines/SCRYER.routine.md` contract does not describe:

1. The cloud container has NO `gh` CLI. The 2026-08-09 run improvised the PR
   sweep through GitHub MCP tools (`list_pull_requests` returned 0 open PRs —
   the read path is field-proven). The contract knows only `gh`, so the merge
   path on an MCP-only host is unspecified, and the digest never said which
   path served the run.
2. The cloud checkout is a SHALLOW clone. `docs-audit`'s history-based
   heuristics saw no commits and reported 24 probable-false-done items that
   are CLEAN locally. The digest presented an environment artifact as findings.

Both are contract-text defects in ONE file. Since CHANGE-0128 that file is the
single source of truth for the live prompt, so the fix is a template edit plus
the regeneration of the byte-for-byte pins that guard it. No engine change:
`.aai/scripts/routine-emit.mjs` already has every mechanism this needs (the
`MERGE-GATES` marker pair, the closed four-placeholder set, the post-render
closure check). Re-arming the live cloud routine from the new template is an
out-of-repo operator/orchestrator obligation, recorded as R1 below.

## Implementation strategy
- Strategy: hybrid
- Rationale: the three NEW contract assertions (tool-ladder placement,
  report-only merge-instruction isolation, shallow-honest health) are exactly
  the kind of pin that passes vacuously if written after the prose — a grep
  for text you just typed proves nothing — so they get a tight TDD lane: RED
  observed and stored against the PRE-change template, then GREEN. The rest is
  loop: regenerating the golden fixture and re-running the pin chain, where a
  green run against a byte-for-byte fixture is itself the evidence and a RED
  is produced automatically by the template edit. STATE carries no
  intake-sourced strategy for this scope (the recorded `hybrid` belongs to the
  CHANGE-0128 ride) and the intake records no
  `Implementation mode (user choice):` line, so this is Planning's call — and
  it lands on the same value.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: the scope is one template file, one regenerated fixture
  and one test file; no `protected_paths_l3` surface is touched (state engine,
  allocator, pre-commit guards, `.aai/workflow/WORKFLOW.md`,
  `docs/CONSTITUTION.md` — none appear in the file list). Work is already on
  the dedicated branch `feat/scryer-mcp-and-shallow`, so a worktree buys
  little beyond what the branch already gives.
- User decision: undecided
- Base ref: main
- Worktree branch/path: feat/scryer-mcp-and-shallow (current checkout)
- Inline review scope: .aai/routines/SCRYER.routine.md,
  tests/fixtures/routines/scryer-claude-merge.golden.txt,
  tests/skills/test-aai-routine.sh, CHANGELOG.md,
  docs/specs/SPEC-0116-spec-scryer-mcp-and-shallow.md,
  docs/issues/CHANGE-0129-scryer-mcp-and-shallow.md

## Design decisions

- D1 — The ladder is SPLIT across the merge-gate marker boundary, because the
  two halves have different audiences. The READ ladder (`gh` first, GitHub MCP
  read tools as fallback) lives OUTSIDE
  `<!-- MERGE-GATES:START -->`/`<!-- MERGE-GATES:END -->`: every digest needs
  PR reads, including the report-only variant, which is the default emission
  when no authorization record exists. The MERGE ladder (`gh pr merge` else
  the MCP `merge_pull_request` tool) lives INSIDE the markers, because
  `applyMergeGate` strips ONLY the marker block: any merge instruction written
  outside it would ship in a report-only routine, handing merge wording to an
  instance whose whole point is that it may not merge. This is the single
  highest-consequence detail in the change, so it gets its own AC and its own
  test on the RENDERED report-only output, not on the template text.
- D2 — No new placeholder. The ladder is unconditional prose ("use `gh` when
  the probe passed, otherwise the MCP tools"), evaluated by the agent at run
  time, not a render-time branch. A `{{TOOL_PATH}}`-style placeholder would
  break the closed four-token set that TEST-002 pins and the emitter's
  post-render closure check enforces, and it would need the emitter to know
  something it cannot know at emission time (which tools the *cloud container*
  will have, months later).
- D3 — No `.aai/scripts/routine-emit.mjs` change. Every mechanism this scope
  needs already exists and is tested; touching the emitter would widen the
  blast radius from "prose plus fixture" to "engine". If implementation finds
  itself editing the emitter, that is a signal the design drifted — stop and
  re-plan.
- D4 — The HEALTH step is NEW template text, not an edit. The reconstructed
  template (SPEC-0115 D6) never carried a health/docs-audit step at all —
  CHANGE-0128 AC-001 enumerated six contract elements and health was not among
  them — yet the live 2026-08-08/09 runs plainly ran one. This scope writes
  that step down for the first time, which is why AC-002 reads as "becomes
  shallow-honest": the observable target is the emitted contract, and the
  emitted contract must instruct the honest behavior.
- D5 — Shallow handling is probe → best-effort repair → honest SKIP, in that
  order, and never a crash. `git fetch --unshallow` legitimately fails on a
  host with no network, no remote, or an already-complete clone; the contract
  therefore treats it as best-effort and branches on the RE-PROBED state, not
  on the fetch's exit code. When history is still absent the digest names the
  shallow-clone artifact and SKIPs the history-based classes (`false-done`,
  `false-open`, `stale`) — a skipped class named in **Degradováno** is a
  successful degraded run under the existing resilience contract; 24 phantom
  findings are a false report, which is worse than no report.
- D6 — MCP tool names are pinned as literal text in the contract, with an
  explicit "if a named tool is unavailable, degrade that section — never
  invent a tool" rule. Only `list_pull_requests` is field-proven (2026-08-09);
  the rest are asserted from the same server's tool family. The degrade rule
  is what makes an unverified name safe rather than a crash, and the residual
  exposure is recorded as R2.
- D7 — The golden fixture is REGENERATED from the new template with the exact
  command TEST-003 runs, never hand-edited. The pin's whole value is that the
  fixture and the render come from the same generator; a hand-patched golden
  silently weakens every future run of TEST-003.

## Acceptance Criteria Mapping

- Maps to: CHANGE-0129 AC-001
- Spec-AC-01: `.aai/routines/SCRYER.routine.md` declares the tool ladder
  explicitly. OUTSIDE the `MERGE-GATES` marker pair it names `gh` as the first
  choice and the GitHub MCP read tools as the fallback, pinning the literals
  `list_pull_requests`, `get_pull_request`, `get_pull_request_status` and
  `get_pull_request_comments`, plus the rule that an unavailable named tool
  degrades that digest section rather than being replaced by an invented one.
  INSIDE the marker pair it names the merge ladder with the literals
  `gh pr merge` and `merge_pull_request`. The digest shape gains one section
  that names which tool path served the run. All six CHANGE-0128 contract
  elements remain greppable and the declared placeholder set is still exactly
  `{{REPO}}`, `{{SCHEDULE}}`, `{{MERGE_ALLOWED}}`, `{{MODEL}}`.
  - Verification: `bash tests/skills/test-aai-routine.sh 001 002 035` —
    TEST-035 (ladder literals on the correct side of the markers, digest
    path-naming section), TEST-001 (six elements survive), TEST-002 (closed
    placeholder set survives). Evidence: suite stdout with the three PASS
    lines.

- Maps to: CHANGE-0129 AC-001
- Spec-AC-02: the REPORT-ONLY render carries no merge instruction. Running the
  emitter against a ledger with no matching authorization record produces a
  prompt containing `merge-allowed: false`, and containing NONE of the
  literals `## Merge gates`, `gh pr merge`, `merge_pull_request`; the same
  invocation against the authorized fixture produces a prompt containing
  `merge-allowed: true` and ALL THREE of those literals. Both invocations exit
  0.
  - Verification: `bash tests/skills/test-aai-routine.sh 036 012 011` —
    TEST-036 (the paired presence/absence assertion over both rendered
    variants), plus the pre-existing TEST-011/TEST-012 pair. Evidence: suite
    stdout.

- Maps to: CHANGE-0129 AC-002
- Spec-AC-03: the template carries a HEALTH step that is shallow-honest, and
  it survives into BOTH rendered variants (it sits outside the marker pair).
  It pins, as greppable text: the probe `git rev-parse --is-shallow-repository`;
  the best-effort repair `git fetch --unshallow`; a branch on the RE-PROBED
  state, not the fetch exit code; the rule that when full history is still
  unavailable the digest names the shallow-clone artifact in **Degradováno**
  and SKIPs the history-based classes, naming at least `false-done`; and a
  pointer to the resilience contract making a failed probe or a failed
  `docs-audit` a degraded section, never a crash.
  - Verification: `bash tests/skills/test-aai-routine.sh 037` — TEST-037 greps
    all five pins in the rendered merge-enabled prompt AND in the rendered
    report-only prompt (the real template through the real emitter, both
    branches of `applyMergeGate`). Evidence: suite stdout.

- Maps to: CHANGE-0129 AC-003
- Spec-AC-04: the byte-for-byte pin chain is intact after the template edit
  and no governance surface drifts. `tests/fixtures/routines/scryer-claude-merge.golden.txt`
  is regenerated with the TEST-003 command so the golden diff passes, renders
  stay idempotent and `{{`-free, and the whole `tests/skills/test-aai-routine.sh`
  suite exits 0 with zero FAIL lines. `git diff --name-only main...HEAD`
  contains neither `.aai/system/PROFILES.yaml` nor
  `tests/skills/lib/prompt-diet-ledger.sh` nor
  `tests/skills/test-aai-prompt-diet.sh` (no new `.aai/**` file is added, and
  `.aai/routines/SCRYER.routine.md` is outside the `.aai/*.prompt.md` corpus
  glob, so neither companion obligation fires), and the profiles, prompt-diet
  and hygiene suites all exit 0.
  - Verification: `bash tests/skills/test-aai-routine.sh` (exit 0, no FAIL),
    `bash tests/skills/test-aai-layer-profiles.sh`,
    `bash tests/skills/test-aai-prompt-diet.sh`,
    `bash tests/skills/test-aai-hygiene-pack.sh`, and
    `git diff --name-only main...HEAD` showing none of the three governance
    paths. Evidence: the four suite stdouts and the diff listing.

CHANGE-0129 AC-004 (live re-arm, test-at-creation fire, disposable probe PR
proving the MCP merge path, decisions.jsonl record) maps to NO Spec-AC by
design: nothing in this repository can execute it and no test can observe it.
It is recorded as the out-of-repo obligation R1 under `## Residual risks`, the
way SPEC-0115 recorded R1/R2, and it is the orchestrator's post-merge act.

## Constitution deviations

- Article 7 (Operator-only merge) — DEVIATION, justified, INHERITED and
  NARROWED. This scope extends an already-authorized scheduled-agent merge
  capability (SPEC-0115's recorded deviation, resting on the owner's explicit
  2026-08-06 scoped authorization in `docs/ai/decisions.jsonl` and the
  `merge-authorization-owner-override` precedent) onto a second tool path, the
  GitHub MCP `merge_pull_request` tool. It widens no permission: the three
  merge gates are unchanged, `[L3]` scopes remain operator-only, the
  machine-checked `routine_authorization` guard is untouched and still
  fail-closed, and Spec-AC-02 adds a NEW narrowing this repository did not
  have before — a test that the report-only variant contains no merge
  instruction at all, on either path.
- Articles 1, 2, 3, 4, 5, 6 — no deviation. Note Article 4 (degrade and
  report): the shallow-clone SKIP and the unavailable-MCP-tool rule are both
  explicit-report degradations, and Article 2 (simplicity): D2 and D3 keep the
  change to prose plus a regenerated fixture, adding neither a placeholder nor
  an engine branch.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the template is read THEN the read ladder and its MCP tool literals sit outside the merge markers, the merge ladder literals sit inside them, the digest names the tool path that ran, and the six contract elements plus the four-token placeholder set survive | done | test-aai-routine.sh TEST-035/001/002 PASS 2026-08-09 | — | RED stored docs/ai/tdd/red-TEST-035-20260809T101612Z.log |
| Spec-AC-02 | WHEN the emitter renders without an authorization record THEN the prompt carries merge-allowed false and none of the three merge literals; WHEN it renders with one THEN all three are present | done | test-aai-routine.sh TEST-036/011/012 PASS 2026-08-09 | — | RED stored docs/ai/tdd/red-TEST-036-20260809T101612Z.log; the D1 boundary, asserted on rendered output |
| Spec-AC-03 | WHEN either variant is rendered THEN it carries the shallow probe, the best-effort unshallow, the re-probe branch, the skip-not-report rule naming false-done, and the never-crash pointer | done | test-aai-routine.sh TEST-037 PASS 2026-08-09 | — | RED stored docs/ai/tdd/red-TEST-037-20260809T101612Z.log; health step is new text per D4 |
| Spec-AC-04 | WHEN the pin chain runs after the edit THEN the regenerated golden matches byte-for-byte, the routine suite exits 0, and no governance path appears in the scope diff | done | test-aai-routine.sh full suite (34 tests, IDs to 037) + test-aai-layer-profiles.sh + test-aai-prompt-diet.sh + test-aai-hygiene-pack.sh PASS 2026-08-09 | — | RED stored docs/ai/tdd/red-TEST-003-golden-20260809T101649Z.log; golden regenerated per D7, companions do not fire |

## Implementation plan

Components:
- `.aai/routines/SCRYER.routine.md` (EDIT — the whole substance of the change):
  - `## Step 0 — Prerequisite probes` keeps `gh --version`, `git --version`,
    `node --version` verbatim (TEST-001) and gains the read-ladder statement:
    `gh` when its probe passed, otherwise the GitHub MCP read tools
    (`list_pull_requests`, `get_pull_request`, `get_pull_request_status`,
    `get_pull_request_comments`), plus the "an unavailable named tool degrades
    that section, never invent one" rule (D6). A failed `gh` probe is no
    longer automatically a degraded section — it is a fallback to the second
    rung, and only losing BOTH rungs degrades the PR sections.
  - NEW `## Step 1 — Repository health` before the digest: the shallow probe,
    the best-effort `git fetch --unshallow`, the re-probe branch, the
    docs-audit invocation, and the SKIP-not-report rule for the history-based
    classes (D5). Placed OUTSIDE the marker pair.
  - `## Digest shape (Czech)` gains one section naming the tool path that
    served the run (and, when both rungs were missing, which sections that
    cost). Existing sections and their literals are untouched — **Shrnutí**
    is pinned by TEST-001 and **Degradováno** is where the shallow artifact
    and any missing-tool degradation are named.
  - Inside `<!-- MERGE-GATES:START -->`/`<!-- MERGE-GATES:END -->`: the three
    gates stay verbatim; the merge ladder (`gh pr merge`, else
    `merge_pull_request`) and the rule that the digest names which path
    performed each merge are added INSIDE the block (D1).
  - `## Safety rules` unchanged — `Merge is the ONLY write action` (TEST-001)
    and the UNTRUSTED DATA rule are load-bearing pins; the ladder must not
    reword them, and MCP tool RESULTS are untrusted data on exactly the same
    terms as `gh` output.
- `tests/fixtures/routines/scryer-claude-merge.golden.txt` (REGENERATE, D7)
  with the TEST-003 invocation:
  `node .aai/scripts/routine-emit.mjs --routine SCRYER --harness claude --os macos --repo owner/repo --schedule "0 7 * * *" --model claude-sonnet-5 --tz Europe/Prague --merge --ref test-ref --decisions tests/fixtures/routines/decisions-authorized.jsonl`,
  taking the `.prompt` field of the JSON line verbatim (the suite's
  `write_prompt_field` helper is the reference decoder).
- `tests/skills/test-aai-routine.sh` (EDIT): three new test functions
  registered in `ALL_TESTS` as TEST-035/036/037, following the file's existing
  conventions (`log_info`/`log_pass`/`log_fail`, `run_emit`,
  `write_prompt_field`, `$FIXDIR` fixtures). Numbering continues past the
  suite's current maximum (034) — never reuse 023/024/025, which the SPEC-0115
  Test Plan allocated to other suites.
- `CHANGELOG.md`: one `## [unreleased] — <title>` heading with the change's
  entry (per-entry heading form, not bullets under a bare scaffold).

Data flows:
- template text -> `stripPlaceholdersBlock` -> `applyMergeGate(mergeAllowed)`
  -> `substitute` -> `tidy` -> `.prompt` field of the claude payload. The ONLY
  branch is `applyMergeGate`, which is why D1's inside/outside placement is
  the entire report-only isolation mechanism.

Edge cases:
- A new blank-line run introduced by the added sections is collapsed by
  `tidy()` (3+ blank lines -> 1) — the golden must be regenerated from the
  emitter, not assembled by hand, or the fixture will differ in whitespace.
- No `{{`-shaped text may appear in the new prose (the emitter exits 3 on a
  surviving `{{`, and TEST-002 fails on an undeclared token). MCP tool names
  are plain identifiers, so this is a discipline note, not a design problem.
- The em dash and Czech diacritics already in the file are UTF-8; new text
  must stay UTF-8 or the golden diff will catch it.
- `git fetch --unshallow` on an already-complete clone exits non-zero on some
  git versions — this is exactly why D5 branches on the re-probe.

## Seams

- S1 — template <-> renderer. Produced by the template author, consumed by
  `routine-emit.mjs`. Crossed by TEST-003 (regenerated golden, real template
  through the real emitter) and TEST-005 (zero unresolved placeholders). No
  mock exists on this path.
- S2 — merge-gate marker block <-> the report-only variant. THE seam of this
  change: text added on the wrong side of the marker pair ships merge wording
  to a routine that must not merge, and nothing in the emitter would complain
  (exit 0, valid render). Crossed by TEST-036, which renders BOTH branches of
  `applyMergeGate` from the REAL template and asserts presence on one side and
  absence on the other — a template-text grep alone cannot cross it, because
  the template legitimately contains the merge literals.
- S3 — new health/ladder prose <-> the six-element contract grep. New prose
  displacing or rewording a pinned literal breaks the CHANGE-0128 contract
  silently. Crossed by TEST-001 (six elements) and TEST-002 (placeholder
  closure) re-run against the edited template, and by TEST-011's gate greps on
  the rendered merge-enabled prompt.
- S4 — template <-> the live cloud trigger. Not crossable by any test in this
  repository (no cloud credentials, and the live prompt text is not in the
  repo — SPEC-0115 D6). Recorded as R1, not tested.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-035 | Spec-AC-01 | unit | tests/skills/test-aai-routine.sh | read-ladder literals and the MCP degrade rule appear OUTSIDE the MERGE-GATES marker pair, the merge-ladder literals appear INSIDE it, and the digest shape names the tool path that ran | green |
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-routine.sh | regression: the six CHANGE-0128 contract elements are still greppable in the edited template | green |
| TEST-002 | Spec-AC-01 | unit | tests/skills/test-aai-routine.sh | regression: the placeholder set is still exactly the four declared tokens | green |
| TEST-036 | Spec-AC-02 | int  | tests/skills/test-aai-routine.sh | report-only render has merge-allowed false and none of `## Merge gates` / `gh pr merge` / `merge_pull_request`; authorized render has merge-allowed true and all three; both exit 0 | green |
| TEST-011 | Spec-AC-02 | int  | tests/skills/test-aai-routine.sh | regression: authorized fixture still yields merge-enabled plus the three gates | green |
| TEST-012 | Spec-AC-02 | int  | tests/skills/test-aai-routine.sh | regression: unauthorized fixture still yields report-only plus the loud MERGE DISABLED stderr line | green |
| TEST-037 | Spec-AC-03 | int  | tests/skills/test-aai-routine.sh | both rendered variants carry the shallow probe, the best-effort unshallow, the re-probe branch, the skip-not-report rule naming false-done, and the never-crash pointer | green |
| TEST-003 | Spec-AC-04 | int  | tests/skills/test-aai-routine.sh | regenerated golden equals the render byte-for-byte | green |
| TEST-004 | Spec-AC-04 | int  | tests/skills/test-aai-routine.sh | two identical renders of the edited template are byte-identical | green |
| TEST-005 | Spec-AC-04 | int  | tests/skills/test-aai-routine.sh | edited template renders with zero unresolved placeholder sequences | green |
| TEST-038 | Spec-AC-04 | int  | tests/skills/test-aai-layer-profiles.sh | its TEST-001 union still equals the live .aai tree (no new or unclassified .aai file was added) | green |
| TEST-039 | Spec-AC-04 | int  | tests/skills/test-aai-prompt-diet.sh | its TEST-010 floor and TEST-012 pin are unchanged (the routine template is outside the .aai/*.prompt.md corpus glob) | green |

RED discipline (strategy hybrid): TEST-035, TEST-036 and TEST-037 are the
AC-gating tests for the three new behaviors and MUST be observed FAILING
against the PRE-change template before the template is edited — a contract
grep written after the prose it greps for proves nothing. Store each RED
transcript under `docs/ai/tdd/`. TEST-003 will also go RED the moment the
template changes (golden mismatch); capture that transcript too, since it is
the proof the byte-for-byte pin still bites. The remaining rows are
loop-covered: green runs suffice.

## Verification

Commands:
- `bash tests/skills/test-aai-routine.sh`
- `bash tests/skills/test-aai-layer-profiles.sh`
- `bash tests/skills/test-aai-prompt-diet.sh`
- `bash tests/skills/test-aai-hygiene-pack.sh`
- `git diff --name-only main...HEAD`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0116-spec-scryer-mcp-and-shallow.md`
- `node .aai/scripts/docs-audit.mjs --check --strict`

Evidence artifacts: suite stdout with per-TEST pass lines, the RED transcripts
under `docs/ai/tdd/`, the regenerated golden fixture, the scope diff listing.

PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract

Per artifact record: ref_id, Spec-AC and TEST-xxx links, command or review
scope, exit code or review verdict, evidence path, commit SHA or diff range.

### Evidence by strategy

Strategy is `hybrid`: stored RED artifacts are demanded for TEST-035/036/037
(plus the TEST-003 golden RED), together with the full verification matrix
above.

## Residual risks

- R1 — OUT-OF-REPO OBLIGATION (CHANGE-0129 AC-004, orchestrator-owned,
  post-merge). Nothing in this repository can perform or observe it: update
  the live routine via RemoteTrigger with the template-rendered merge-enabled
  prompt (the `routine_authorization` record already exists), fire an
  immediate test run per the test-at-creation rule, verify the MCP merge path
  end-to-end with a disposable probe PR, and record the outcome — including
  the trigger id — in `docs/ai/decisions.jsonl`. Until that fire happens, the
  only evidence for the new contract is that it renders correctly, not that a
  cloud agent behaves correctly under it. Accepted, not tested, explicitly
  tracked here so it cannot be mistaken for delivered.
- R2 — Only `list_pull_requests` is field-proven against the live GitHub MCP
  server (2026-08-09 run). `get_pull_request`, `get_pull_request_status`,
  `get_pull_request_comments` and `merge_pull_request` are asserted from the
  same server's tool family, not observed. A wrong name yields a missing tool,
  which the D6 degrade rule turns into a named degraded section rather than a
  crash or an invented substitute; the R1 probe run is where a wrong name
  surfaces. Accepted.
- R3 — The shallow-honest branch is contract TEXT: whether a cloud agent
  actually re-probes and skips instead of reporting cannot be asserted by any
  test here (the suite has no shallow cloud checkout and does not execute the
  prompt). Mitigation: the pins make the instruction unambiguous, and the R1
  fire is the field check — the 24-phantom-findings symptom is loud and
  immediately visible in the next digest. Accepted.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
