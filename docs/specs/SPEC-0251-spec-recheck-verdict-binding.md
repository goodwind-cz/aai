---
id: spec-recheck-verdict-binding
type: spec
number: 251
status: done
mutation_gate: v1
frozen_sha256: ffc60a59b98b04324fc956ea1f5d9e526857e000d0cbe3a33031e1e7dfe1569a
ceremony_level: 3
links:
  requirement: recheck-verdict-binding
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Bind each judged re-check verdict to STATE, then make delta the default

SPEC-FROZEN: true

## Links

- Requirement: [Recheck verdict binding](../issues/CHANGE-0226-recheck-verdict-binding.md)
  (intake commit `9981130b`).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  phase 4 row (second slice).
- Prior art: [SPEC-0250](SPEC-0250-spec-cheap-transitions-slice.md) (PR #498,
  the delta re-check mode, its D1 conditions, the D4 stamps and their general
  residual, Spec-AC-16 and TEST-2742). Ledger-pin pattern: SPEC-0250 TEST-2723.
- Owner decision 2026-10-24, menu answer "Zapnout po ověření": build the
  binding first; delta becomes the default only when Validation proves that
  every shape listed in D5 gives `full`; `AAI_RECHECK_MODE=full` stays a
  per-run opt-out; the owner confirms the flip at the merge menu.

## Implementation strategy

- Strategy: hybrid
- Rationale: the binding writer, the eligibility reader, the flush and handoff
  behavior, the escalation flag and the default switch are behavior with
  refusal paths, so each row that gates them is TDD with a stored RED and a
  mutation record. The prompt, protocol, workflow, CHANGELOG, RFC, profile,
  suite-map and diet-ledger edits are mechanical (loop mode), each pinned by a
  mutation-gated inspection row.

## Isolation and review

- Worktree recommendation: required (ceremony level 3).
- Worktree rationale: the scope edits `.aai/workflow/WORKFLOW.md`, a
  `protected_paths_l3` surface, and changes how every downstream install
  dispatches re-check rounds; the ride already runs in its own linked worktree.
- User decision: worktree (recorded before Planning).
- Base ref: 59ee0ff2 (main); intake commit 9981130b.
- Worktree branch/path: change/recheck-verdict-binding at /private/tmp/aai-recheck-binding
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/lib/check-binding.mjs .aai/scripts/lib/recheck.mjs
  .aai/scripts/state.mjs .aai/scripts/orchestration-dispatch.mjs
  .aai/scripts/metrics-flush.mjs .aai/scripts/check-role-output.mjs
  .aai/ORCHESTRATION.prompt.md .aai/ORCHESTRATION_PARALLEL.prompt.md
  .aai/SUBAGENT_PROTOCOL.md .aai/workflow/WORKFLOW.md .aai/system/PROFILES.yaml
  tests/skills/test-aai-recheck.sh tests/skills/lib/recheck.test.mjs
  tests/skills/suite-map.yaml tests/skills/lib/prompt-diet-ledger.sh
  tests/skills/test-aai-prompt-diet.sh
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md CHANGELOG.md
  docs/ai/decisions.jsonl docs/issues/CHANGE-0226-recheck-verdict-binding.md
  docs/specs/SPEC-0251-spec-recheck-verdict-binding.md
  docs/specs/SPEC-0250-spec-cheap-transitions-slice.md
  (an existing suite outside this list is edited only when one of its pins
  names a literal this scope changes, for example the state.mjs subcommand
  list in `test-aai-state.sh`; each such edit is disclosed in the hand-off).
- Code review required: true, on the most capable tier (L3), with the
  operator checkpoint before merge.

## Problem, measured

SPEC-0250 ships delta re-check opt-in because `recheckMode` decides a judged
round from `check_verdict` stamps in the tracked `docs/ai/EVENTS.jsonl`. The
#498 reviews and validations found eight ways to change what those stamps say
without `ledger_rewritten` or `merge_in_range` seeing it (code review r4 B-10,
r5 B-11, r6 B-12; validation r3 B9 F1/F2/F7, r4 F7i; the merge probe of
TEST-2743), and one way to stamp a verdict no dispatched checker wrote
(validation r2 probe D2, `fu-recheck-verdict-not-bound-to-check`). TEST-2742
pins three of them as giving `delta` under `AAI_RECHECK_MODE=delta` today.
Every one of them edits a git-tracked file or git history. None of them can
edit `docs/ai/STATE.yaml`, which `.gitignore` excludes, so no commit, amend,
rebase, squash, merge or replace object carries it.

## Scope and design

### D1. The store: a `check_binding` block in STATE, written only by `state.mjs bind-check`

The binding lives in a new optional top-level block `check_binding:` of
`docs/ai/STATE.yaml`. Only one command writes it:

    node .aai/scripts/state.mjs bind-check --on <dispatch|verdict> --role <validation|code_review> --ref <R> [--state <path>]

`bind-check` takes no head, report, digest or marker from its caller. It reads
every value it records from STATE, from the report files STATE names and from
`git` run in the repository that holds the STATE file. It is refused (exit 3,
nothing read or written) when `AAI_ROLE` is set to any non-empty value,
whitespace included, for any `--state` path (the TEST-2744 posture; the rest
of `state.mjs` keeps its `AAI_ROLE=subagent` rule and its path predicate), and refused (exit 2, nothing written) when `--ref`
is not `current_focus.ref_id`. `check-role-output.mjs` already refuses any
returned `state_update_commands` entry outside its allowlist; `bind-check` is
not added to it, so a role cannot return it (E-STATE-UPDATE-COMMAND). The
STATE template is unchanged: an absent block means no binding.

Why STATE and not another file: `state.mjs` is the one sanctioned STATE writer
with an atomic write, a duplicate-key check and the single-writer refusal; a
second gitignored sidecar would need all three again. STATE is per checkout,
which D6 turns into an explicit comparison.

Fields (the line engine's `  key: value` form; lists in the block-list form
`state.mjs` already writes; one block, one ref at a time):

| Field | Written by | Value |
|---|---|---|
| `ref_id` | both | the ref; a `bind-check` for another ref replaces the whole block |
| `checkout` | both | `realpath` of `git rev-parse --show-toplevel` at write time |
| `spec_path` | dispatch | the focus spec path STATE names (the work item `spec_path`, else `current_focus.spec_path`), recorded once while the block holds none and kept for the life of the block (D13) |
| `security_sticky` | both | `true` once any bound marker of either role was `true`; not lowered by a write that keeps the block; a replacement block is seeded from the per-ref `check_sticky` record (D15) |
| `<role>_pending_heads` | dispatch | the 40-hex `git rev-parse HEAD` of each dispatch of the role since its last bound verdict, in order |
| `<role>_pending_reports` | dispatch | the report paths STATE named for the role at the FIRST pending dispatch (Validation: the `.md` entries of `last_validation.evidence_paths` when its `ref_id` names the ref; Code Review: `code_review.report_paths` when `scope_ref_id` is null or names the ref) |
| `<role>_head` | verdict | the bound head (D2), 40 hex, or `AMBIGUOUS_HEAD` (forty zeros) |
| `<role>_status` | verdict | `pass` or `fail` |
| `<role>_reports` | verdict | the report paths STATE names for the role at bind time |
| `<role>_digests` | verdict | the sha256 hex of each of those files, same order |
| `<role>_security` | verdict | the marker of D3: `true`, `false` or `null` |
| `<role>_bound_at_utc` | verdict | ISO 8601 UTC of the write |

`<role>` is `validation` or `code_review`.

### D2. When `bind-check` writes

`--on dispatch` (a `--confirm` tick that dispatches Validation or Code Review,
full or delta alike): appends the current HEAD to `<role>_pending_heads`,
and, when the list was empty, records `<role>_pending_reports`. It writes
nothing when the last pending head equals HEAD and the role's report set equals
`<role>_pending_reports` (a repeated tick).

`--on verdict` (every `--confirm` tick, for each role, before the dispatch
decision): writes the role's verdict fields only when all of these hold, and
otherwise writes nothing:

1. `<role>_pending_heads` is non-empty;
2. STATE holds a `pass` or `fail` verdict of the role for the ref;
3. the role's current report set holds at least one path that is not in
   `<role>_pending_reports` (a new report since the first pending dispatch).

The bound head is the FIRST pending head. When a later pending head does not
descend from it, or git cannot say, the bound head is `AMBIGUOUS_HEAD`. The
write then clears `<role>_pending_heads` and `<role>_pending_reports` and sets
`security_sticky` to `true` when the new marker is `true` (it never lowers it).
Condition 3 is what tells a dispatched check's verdict from a re-record of an
older report after a crashed check (validation r2 probe D2): a re-record names
no new report, so nothing is bound and the pending head stays (D4,
`binding_pending`).

The EVENTS stamps of SPEC-0250 D4 (`check_dispatched`, `check_verdict`) are
still appended by the same ticks, unchanged, as telemetry. No eligibility
decision reads them (D4).

### D3. The marker the binding records

At `--on verdict`, the role's marker is read from each bound report with the
existing `markerOfText`: `true` when any report says `true`, `false` when there
is at least one report and every one carries exactly one
`security_relevant: false` line, `null` otherwise. The full Code Review and
Validation prompts are unchanged (SPEC-0250 D5 still defines the line).

### D4. Eligibility reads the binding

`recheckMode` keeps every SPEC-0250 D1 condition that does not read a stamp
(role, switch, delta non-empty, D2 allowlist, D3 protected paths, ceremony,
prior reports read from the base blob or live, `ledger_rewritten`,
`merge_in_range`, `git_error`). It no longer parses any `check_*` line of
`docs/ai/EVENTS.jsonl`. The stamp conditions are replaced by these, read from
`check_binding` through `.aai/scripts/lib/check-binding.mjs`:

| Comparison | Reason when it fails |
|---|---|
| a block exists, its `ref_id` equals the ref and the role's `<role>_status` is `pass` or `fail` | `first_round` |
| every field present parses as the D1 table says (head 40 hex, status pass or fail, security true, false or null, reports and digests of equal length, digests 64 hex, STATE free of duplicate top-level keys) | `binding_ambiguous` |
| `checkout` equals the `realpath` of `git rev-parse --show-toplevel` of the root being decided | `binding_other_checkout` |
| `<role>_pending_heads` is empty (D14: `canon.mjs` passes `ownDispatch`) | `binding_pending:<role>` |
| `<role>_head` is an ancestor of HEAD (`AMBIGUOUS_HEAD` never is) | `base_not_ancestor` |
| the sha256 of each `<role>_reports` file read now equals its `<role>_digests` entry | `binding_report_changed:<path>` (also when the file is unreadable) |
| `spec_path` is recorded and equals the focus spec path STATE names now (D13) | `spec_path_unbound:binding` when no path is recorded, `spec_path_changed:binding` when it differs |
| `security_sticky` is not `true` and neither role's `<role>_security` is `true` | `security_relevant:binding` |
| the `check_sticky` block parses and holds an entry for the ref (D15) | `sticky_record_ambiguous` when it does not parse, `sticky_record_absent:binding` when it holds no entry for the ref |
| that entry's `security` is not `true` (D15) | `security_relevant:sticky` |
| the role's `<role>_security` is `false` | `security_marker_absent:binding:<role>` |
| `git for-each-ref --count=1 refs/replace/` prints nothing and `<git common dir>/info/grafts` does not exist | `replace_refs_present` |

The base of the delta is `<role>_head`. Every `git` call made by
`recheckMode` and by `bind-check` runs with each `GIT_*` variable of the
inherited environment removed and `GIT_NO_REPLACE_OBJECTS=1` set
(`gitEnv()` in `check-binding.mjs`), so a replace ref under any
`GIT_REPLACE_REF_BASE` is not applied to the reads.

### D5. The tamper shapes and what each one meets

Each shape below is a test (Spec-AC-04) on a fixture with two judged
Validation rounds bound through the real `bind-check`: round 1 bound with
marker `true`, round 2 bound with marker `false`, so `security_sticky` is
`true`, and a non-production delta after round 2. Each test runs under
`AAI_RECHECK_MODE=delta` (so the switch is not the reason) and under the
default environment, and records which comparison of D4 returns `full`.
On the base commit `59ee0ff2` the same fixture built with the EVENTS stamps
returns `delta` for shapes 1 to 8 and 10 (the stored RED); shapes 9
(`merge_in_range`) and 11 (the stamped marker) already give `full` there.

| # | Shape (source) | Comparison that gives full |
|---|---|---|
| 1 | an uncommitted in-place rewrite of a `true` stamp (r4 F7i, TEST-2742) | `security_sticky` |
| 2 | `commit --amend` folding the rewrite into the stamp's commit (r5 B-11, TEST-2742) | `security_sticky` |
| 3 | a rebase that drops the stamp's commit (r5 B-11) | `security_sticky` |
| 4 | a squash merge resolved to ours that drops the stamp (r5 B-11) | `security_sticky` |
| 5 | a rewrite committed before the base, true appended then flipped (r6 B-12) | `security_sticky` |
| 6 | `git replace` in each form: an object replace of the base commit whose tree hides a production change, `replace --graft`, the same under `GIT_REPLACE_REF_BASE=refs/other/`, and an `info/grafts` file (r5 B-11) | `replace_refs_present`, and with `GIT_REPLACE_REF_BASE` also `production_path` for the hidden file |
| 7 | a hand-appended `check_verdict` with a forged head after a production commit, with a bound earlier round (r3 B9 F1/F2) | `production_path` (the base stays the bound head) |
| 8 | a hand-appended `check_verdict` with no binding at all (r3 B9 F1) | `first_round` |
| 9 | `merge -s ours` dropping a side-branch commit that holds a `true` stamp (TEST-2743 probe) | `security_sticky` and `merge_in_range` |
| 10 | a re-record of the old report after a crashed check (r2 probe D2) | `binding_pending:<role>` |
| 11 | a bound report flipped from true to false after the bind, committed (Q8) or gitignored in place (Q9) | `binding_report_changed:<path>` |

### D6. Where the binding goes when STATE moves

- `ride-handoff.mjs out` copies only the ride partition it names
  (focus, work item, metrics entry, strategy, code_review, last_validation,
  tdd_cycle, worktree fields); `check_binding` is not in it, and this scope
  does not add it. The worktree's STATE has no block, so its first re-check
  round gives `first_round`. The `check_sticky` entry of the ride is copied
  into the worktree STATE (D15). A STATE copied into another checkout by hand
  keeps the block, and `checkout` then differs: `binding_other_checkout`.
- `metrics-flush.mjs` partial reset of a flushed ref that `check_binding`
  names clears both roles' verdict and pending fields and keeps `ref_id`,
  `checkout` and `security_sticky` (`clearCheckBinding`); the next round
  gives `first_round`. The full reset removes the block (`removeCheckBinding`).
  Neither function opens the `check_sticky` block (D15).
- `reset-block` does not touch the block (the round after a remediation reads
  it; that is the normal path).
- `merge-cleanup.mjs` archives runtime files and never restores one into
  `docs/ai/STATE.yaml`; `recheckMode` reads only `<root>/docs/ai/STATE.yaml`,
  so an archived block is never read.

In each case delta degrades to `full` until a round is bound again in the
checkout that runs it.

### D7. The default switch (separable final step)

After the binding is proven (Spec-AC-01 to Spec-AC-06, Spec-AC-14 and
Spec-AC-16 green with mutation records, and Validation's replay of D5 all
`full`), one final commit changes `deltaEnabled(env)`:
`AAI_RECHECK_MODE` trimmed and lower-cased; unset, empty or `delta` enable
the mode (`const DEFAULT_ON = true;`); `full` and every other value give
`recheck_disabled`. A misspelt value keeps the round full. The same commit
updates the wording in `.aai/SUBAGENT_PROTOCOL.md`, `.aai/workflow/WORKFLOW.md`,
`.aai/ORCHESTRATION.prompt.md`, `.aai/ORCHESTRATION_PARALLEL.prompt.md` and
`CHANGELOG.md`, rewrites SPEC-0250's TEST-2731 and TEST-2738 node cases to the
new default, and amends SPEC-0250 D1 and Spec-AC-17.

If Validation finds a D5 shape that gives `delta`, or the owner declines the
flip at the merge menu, Spec-AC-11 is moved to `deferred` (Review-By at least 14
days ahead, Notes naming the failing shape or the owner answer) by a
`spec-amend` record, and the owner is told. Everything else ships without it.

The revert is NOT `git revert f79fa2dc` (the commit message of the flip says to
revert it alone; that is no longer true). Commits after the flip rewrote the
wording the flip also touched, and a revert of it on the tip conflicts in nine files
(CHANGELOG.md, docs/INDEX.md, docs/ai/decisions.jsonl, the two overview files,
SPEC-0250, this spec, recheck.test.mjs and test-aai-recheck.sh); resolving
`decisions.jsonl` toward the revert would delete append-only ledger lines (HAZ-LEDGER).
History is not rewritten. The revert is ONE forward commit:

1. Code: `.aai/scripts/lib/recheck.mjs` `const DEFAULT_ON = true;` (line 76) becomes
   `false`, and the comment at lines 71 to 75 and the header at lines 7 and 8 go
   back to opt-in wording, as do the comments in `canon.mjs` (the `f79fa2dc`
   hunk) and `orchestration-dispatch.mjs` (around line 1716). This one toggle gives
   the pre-flip `deltaEnabled` exactly (unset, empty or blank: false; trimmed,
   lower-cased `delta`: true; anything else: false).
2. Tests: the TEST-2731 and TEST-2738 bodies come back from
   `git show f79fa2dc^:tests/skills/lib/recheck.test.mjs`; TEST-2820 is inverted
   (default off) and TEST-2821 is inverted (the docs state opt-in with
   `AAI_RECHECK_MODE=delta`, including the RFC, #498, SPEC-0250,
   `append-event.mjs` and CHANGELOG-heading checks added since); the SELF-HOSTING
   header of `recheck.test.mjs` (lines 8 to 12) is restored; in
   `test-aai-recheck.sh` `test_2738_default_is_delta` is renamed back to `_is_full`
   and the TEST-2820, TEST-2821 and TEST-2742 pass lines and the header are
   restored.
3. Docs: `.aai/SUBAGENT_PROTOCOL.md` (the ON-by-default sentence and the
   escalation clause that says the unset default is delta), `.aai/workflow/WORKFLOW.md`
   line 68, `.aai/ORCHESTRATION_PARALLEL.prompt.md` line 149 (back to opt-in;
   this prompt byte change needs its `prompt-diet-ledger.sh` entry, the `want_growth`
   in `test-aai-prompt-diet.sh` and the `test-aai-pr-preflight.sh` pin recomputed to the
   measured value, as the flip did with +2 B), the CHANGELOG bullets and
   headings, SPEC-0250 (D1, Spec-AC-17, the TEST-2738 row, the Article 5, Risks
   and Rollback lines), RFC-0017 line 307, and this spec (D7 and Spec-AC-11
   marked as reversed by the owner at the merge).
   `.aai/ORCHESTRATION.prompt.md` step 2 (the flip changed its parenthesis to "default on; AAI_RECHECK_MODE=full opts out"; restore "opt-in, off unless AAI_RECHECK_MODE=delta", a prompt byte change that joins the diet recompute above).
4. Ledger, append only: one `spec_amendment` record per spec (contract, D7
   reversed by the owner), the `frozen_sha256` re-pin, and a TEST-2820 mutation
   re-anchor (its cell `DEFAULT_ON = true` to `false` is a no-op after the toggle).
5. Gate: `test-aai-recheck.sh`, `test-aai-prompt-diet.sh`,
   `test-aai-pr-preflight.sh`, `spec-amend list --strict` (rc 0) and a mutation
   replay of TEST-2820, TEST-2821, TEST-2731 and TEST-2738.

Step 1 alone leaves the docs saying the default is on, and TEST-2821 would still
pass; steps 2 to 4 make the state consistent. check_binding and check_sticky stay.

### D8. Folded follow-ups

- `fu-recheck-escalation-mode-blind`: `check-role-output.mjs` takes
  `--recheck-mode <delta|full>` (any other value: exit 2). It prints
  `RECHECK-ESCALATION: needs_full_recheck` only with `--recheck-mode delta`
  (`if (recheckModeArg === 'delta')`); with `full` or without the flag a
  `needs_full_recheck` BLOCKED is an ordinary BLOCKED. `.aai/SUBAGENT_PROTOCOL.md`
  merge step 1 passes the dispatch JSON's `recheck.mode` (`full` when
  `recheck` is null).
- `fu-recheck-escalation-merge-mismatch`: `.aai/ORCHESTRATION.prompt.md`,
  `.aai/ORCHESTRATION_PARALLEL.prompt.md` and `.aai/SUBAGENT_PROTOCOL.md` each
  say, with the literal phrase `run none of its state_update_commands`, that
  an escalated round merges nothing. ORCHESTRATION stays at or under 45 lines
  (it is at 45: the edits extend existing lines).
- `fu-recheck-comments-overclaim-scope`: the `eventsAppendOnly` comment in
  `recheck.mjs` states its comparison (the phrase `compares only` followed by
  the live file, the blobs at the base and at HEAD, and the commits of
  `base..HEAD`) and drops the claim that committed lines are protected and the
  dropped follow-up id.
- `fu-recheck-verdict-not-bound-to-check`: closed by D1 to D5.

### D9. Wording rule (the #498 lesson)

Every text this scope writes about the binding (this spec, the protocol
section, the WORKFLOW sentence, the CHANGELOG entry, code comments in
`check-binding.mjs` and `recheck.mjs`) names the comparison a check makes and
never what it guarantees. None of them uses `tamper-proof`, `guarantee`,
`closes every` or `cannot be forged`. The residual is one sentence, starting
`Residual:`:

Residual: the comparisons read `docs/ai/STATE.yaml` and the bound report files
as they are on disk, so an edit to either made outside `state.mjs` before the
tick that binds or reads it, and a verdict the orchestrator itself records for
the dispatched role with a new report, are taken as written; no shape outside
the D5 table is claimed.

Two statements about `check_sticky` are not made in any text of this scope: that one
command alone writes it, and that it can only go up. The texts name the writers
(`state.mjs bind-check` and `ride-handoff.mjs out`, both through `putStickyRaise`),
the commands that contain no code that opens it (the block replacement of D1,
`clearCheckBinding`, `removeCheckBinding`, `reset-block`, `check-state`), and what
`recheckMode` compares: the entry for the ref in the STATE file of the tree being
decided exists, parses and holds `security` other than `true`, and the ceremony level of
every spec path it holds. The record is per STATE file (D15); that is stated for each
file, not as a guarantee.

### D10. Wiring and governance

- `.aai/scripts/lib/check-binding.mjs` (new, Node stdlib plus the repo's line
  engine) owns reading and planning the block, `gitEnv()` and the D4
  comparisons; `state.mjs` writes through the existing engine and atomic
  write; `recheck.mjs` calls the reader. `orchestration-dispatch.mjs` runs
  `state.mjs bind-check` as a child process (`bindCheck(...)`), the way it
  runs `append-event.mjs`, and swallows a failure (a missing binding keeps the
  round full). Its header sentence "The script NEVER mutates STATE" is amended
  to name this one `--confirm` write.
- `.aai/system/PROFILES.yaml`: `.aai/scripts/lib/check-binding.mjs` in core.
- `tests/skills/suite-map.yaml`: the `aai-recheck` row lists
  `check-binding.mjs`, `state.mjs`, `metrics-flush.mjs` and
  `check-role-output.mjs`.
- Prompt diet: the `.aai/*.prompt.md` glob measures 370992 bytes at
  `59ee0ff2` and TEST-010 headroom is 0 there. If the delivered glob is larger,
  one `JUSTIFIED_ADDITIONS` entry naming `recheck-verdict-binding` credits
  exactly the growth (TEST-010 headroom stays 0) and the TEST-012 checkpoint
  moves by the same amount. `SUBAGENT_PROTOCOL.md` and `WORKFLOW.md` are not in
  the measured glob and are not credited.
- RFC-0017 phase 4 row: names this slice with a link ending
  `recheck-verdict-binding.md`, status stays `in progress`.
- `CHANGELOG.md`: one `## [unreleased] — <type>: <title>` entry.
- SPEC-0250 amendment (one `spec-amend` contract record, `owner_signoff`
  false, tracked by a NEW open follow-up id, never the closed
  `fu-amend-spec-cheap-transitions-slice`): D1, D4 and D5 residual paragraphs,
  the Spec-AC-16 parenthetical and the TEST-2742 row point at this spec; the
  TEST-2742 node case asserts `full` for its shapes; every SPEC-0250 Test Plan
  mutation cell whose target text this scope removes is re-anchored to the
  comparison that replaced it and re-run with `mutation-run.mjs --spec` SPEC-0250 for
  that row only (the #498 mutation records are gitignored and not in this
  worktree, so `mutation-gate.mjs --spec` SPEC-0250 is not a gate here). The flip part
  (D1 switch paragraph, Spec-AC-17, TEST-2731, TEST-2738) is in the D7 commit.

### D11. CI lessons carried from #498

- Any JSON larger than a few KB reaches a child process on stdin or as a file,
  never in argv (the Linux 128 KiB argv cap).
- CI has no harness environment: every test that reads dispatch routing
  fields pins `AAI_HARNESS=claude` (as `recheck.test.mjs` `HARNESS_ENV` does).
- A CI-like clean clone runs the changed suites before the PR (Verification).

### D12. How this ride is validated (self-hosting)

1. This spec is ceremony level 3, so `recheckMode` returns `ceremony_l3` for
   every round of this ride (TEST-2827 runs it on the live spec).
2. Every remediation of this ride touches `.aai/**`, which is production.
3. The orchestrator exports `AAI_RECHECK_MODE=full` for every Validation and
   Code Review round of this ride and builds the full canon payload; the
   hand-off and each report say so.
4. The validator's model differs from the implementer's, Code Review runs on
   the most capable tier, and Validation replays the D5 table in a scratch
   clone of the delivered tree with the delivered code, not the mechanism's
   own verdict.
5. Once Implementation lands, this ride's own `--confirm` ticks write a
   `check_binding` block into the worktree STATE. Points 1 and 3 keep every
   round full regardless.

### D13. Two more fail-open fixes folded (owner decision 2026-10-24, menu answer "Zahrnout ty dvě nebezpečné")

The default flip puts every install behind two P3 findings of #498 that each
turn a full round into a delta round, so both are fixed in this scope.

- `fu-recheck-fenced-false-marker`: `markerOfText` (now in `check-binding.mjs`,
  re-exported by `recheck.mjs`) counts a `security_relevant:` line only when it
  starts at column 0 outside every fenced code block. A fence opens on a line
  with at most three leading spaces and then three or more backticks or tildes,
  and closes on a line of the same character, at least as many of them and
  nothing else; an unclosed fence runs to the end of the text. Lines inside a
  fence are not read. The result is `true` when a column-0 line outside a
  fence says `true`; otherwise `null` when a fence is still open at the end of
  the text; otherwise `false` only when exactly one marker line exists outside
  the fences and it says `false`; otherwise `null`. Every ambiguous shape is
  `null`, which `recheckMode` reads as absent and answers `full`
  (`security_marker_absent:binding:<role>` for a bound report,
  `security_marker_absent:<path>` for a prior report).
- `fu-recheck-specpath-repoint-gives-delta`: the ceremony level was read from
  the spec path STATE names, so re-pointing the gitignored STATE (the work item
  `spec_path` or `current_focus.spec_path`) at a lower-level spec made a level 3
  ride read as level 2. The binding now records `spec_path` (D1 row) at the
  first `bind-check --on dispatch` of the block, while it holds none, from the
  same STATE reading `recheckMode` uses. `recheckMode` reads the level of the
  recorded path and of the path STATE names now, each live and at the base
  commit, and takes the stricter; any level 3 gives `ceremony_l3`, any level
  that cannot be read gives `ceremony_unknown`. A STATE path that differs from
  the recorded one gives `spec_path_changed:binding` (a spec renamed by the
  allocator after the judged round therefore runs full once), and a block with
  no recorded path gives `spec_path_unbound:binding`. Residual of this row: a
  re-point made before the first dispatch tick that records the path is taken
  as written (the D9 residual).
- Wording rule D9 applies to the code comments and docs of both rows.

### D14. The payload build after the tick that dispatched the round (found by the TEST-2816 seam)

The `--confirm` tick writes `bind-check --on dispatch` after its own decision, so the pending head
of the round it dispatched is already in STATE when the orchestrator then runs
`canon.mjs build --recheck delta` for that same round. Without a rule the build would read its own
dispatch as `binding_pending` and refuse every delta round. `canon.mjs` therefore calls
`recheckMode` with `ownDispatch: true`: a pending list of exactly one head, equal to the current
HEAD, is the dispatch record of the round being built and gives no `binding_pending`. A direct
`recheckMode` call, the tick's own decision and a pending list of any other shape keep the reason
(D5 shape 10 and the TEST-2805 case are unchanged). This is an additive refinement of the D4
`binding_pending` row, disclosed by a second contract amendment record.

At a crashed-check head (D5 shape 10 with the one pending head equal to the current HEAD) the tick's
own decision gives `full` with `binding_pending`, while `canon.mjs build --recheck delta` builds a
delta payload for that round: the base it lists is the last bound verdict head, so the payload lists
everything changed since the last judged verdict, and the build binds no verdict. Validation r1 (N2)
found no way to use this to skip a pending check; the sentence records what the two readers compare.

### D15. The per-ref `check_sticky` record (code review r1 B-1 and validation r1 B1, 2026-10-24)

Review and validation found that replacing the `check_binding` block starts a block with
`security_sticky` false and re-reads `spec_path`: a focus switch to another ref and back using only
`state.mjs` commands (probe A3), `git worktree move` (probe WM, `checkout` differs) and a block that
does not parse each left a bound `security_relevant: true` and the recorded L3 spec path unremembered,
and the next bound round with a test-only delta gave `delta`. The sticky flag and the recorded spec
paths therefore live in a second optional top-level block of STATE, `check_sticky:`, one list item per
ref, each a single-quoted JSON object with exactly the keys `ref_id` (string), `security` (boolean) and
`spec_paths` (list of strings).

- Writers. `state.mjs bind-check` (both `--on` values) and `ride-handoff.mjs out` call one function
  (`putStickyRaise` in `check-binding.mjs`). It sets `security` to the OR of the recorded value and
  the value given, and `spec_paths` to the union of the recorded paths and the given ones. The
  given value of a bind is `security_sticky` of the block it carries, the flag and `spec_path` of a
  replaced block that parsed and named the same ref, and the `spec_path` of the new block. A record that
  has a problem is rebuilt, not repaired: a line that does not parse (and an inline header) is kept
  byte for byte, so the reader stays ambiguous and gives `full` for every ref it might name; items that
  repeat a ref merge to the highest flag and the union of their paths; the entry for the ref being
  written gets `security` true. A prior `check_binding` block that does not parse gives `security`
  true as well. Remediation round 2 (code review r2 NB-1) replaced the earlier rebuild, which dropped
  unparsable items and kept the first of two duplicates.
  After the write `check_binding.security_sticky` equals the entry's `security`.
- Not editing. The block replacement of D1, `clearCheckBinding`, `removeCheckBinding` and
  `reset-block` contain no code that opens the block, so a partial flush, a full flush and a reset
  leave the entries as they are. Entries are not removed (a ref reused after its flush keeps the
  flag, which gives more `full`).
- Handoff. `ride-handoff.mjs out` copies the entry of its ref into the worktree STATE. An origin
  `check_sticky` block that does not parse, or an origin `check_binding` block that names the ref
  or does not parse with no entry for the ref, is carried as an entry with `security` true. The
  worktree still starts without a `check_binding` block (`first_round`, D6).
- Reading. `recheckMode` adds the two D4 rows above and reads the ceremony level of every spec path
  the entry holds, each live and at the base, together with the recorded and the named path (D13);
  a path that cannot be read gives `ceremony_unknown`.
- Residual, per STATE file. The record lives in one STATE file, so a STATE file that holds no raised
  entry for the ref starts unraised, and its first bind writes an entry with `security` false because
  nothing is recorded there to compare. The condition is not how the file was made (TEST-2835 makes the
  worktree STATE with `check-state.mjs --repair` and still carries the entry); it is whether
  `ride-handoff.mjs out` or a `bind-check` run against that file wrote the entry. It holds for a
  worktree STATE that `ride-handoff.mjs out` did not write, for a STATE deleted and recreated in the
  same checkout (probe FRESH), and for the origin STATE after a worktree raised the flag, because
  nothing carries an entry from a worktree back to the origin (probe BACK; follow-up
  `fu-sticky-no-reverse-carry`). An edit of the record made outside `state.mjs` is the D9 residual.

This is a contract amendment of D1, D4, D6 and Spec-AC-05, disclosed by a record in the amendment ledger.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01 (dispatch record), Spec-AC-02 (verdict
  binding), Spec-AC-03 (eligibility reads the binding), Spec-AC-05 (where the
  binding goes) and Spec-AC-06 (the end-to-end seam).
- Intake AC-002 maps to Spec-AC-04 (every D5 shape gives full) and
  Spec-AC-16 (TEST-2742 flipped, SPEC-0250 amended).
- Intake AC-003 maps to Spec-AC-10 (the docs say what the code compares) and
  Spec-AC-11 (the default switch and its docs; separable, D7).
- Intake AC-004 maps to Spec-AC-07 (escalation flag and merge wording),
  Spec-AC-08 (the comment) and Spec-AC-02 and Spec-AC-04
  (`fu-recheck-verdict-not-bound-to-check`).
- Intake AC-005 maps to Spec-AC-13.
- Intake AC-006 maps to Spec-AC-14. The 15 sign-off records were appended by
  the intake commit `9981130b`; the row pins them.
- Owner decision 2026-10-24 (D13): Spec-AC-17 (fenced marker) and Spec-AC-18
  (spec path re-point) fold `fu-recheck-fenced-false-marker` and
  `fu-recheck-specpath-repoint-gives-delta`; both serve Intake AC-002.
- Code review r1 B-1 and validation r1 B1 (D15): Spec-AC-19 (the per-ref record) serves Intake AC-002.
- Spec-AC-09 (runtime safety of the switch-independent pieces: one store, one
  writer, subagent refusal) and Spec-AC-12 (governance) and Spec-AC-15
  (self-hosting) serve all of them.

## Constitution deviations

None. Article 1: no round is skipped; a bound round only selects the payload.
Article 2: one block, one subcommand, one library; no new workflow. Article 4:
every unknown resolves to `full` with a named reason. Article 5: the block is
optional and additive, the EVENTS stamps keep their schema. Article 6: STATE
has one writer, `state.mjs`; the dispatch runs it as a child process as it
runs `append-event.mjs`, and a subagent is refused.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN state.mjs bind-check --on dispatch runs for a role and the focus ref the system SHALL write check_binding with ref_id, checkout equal to the realpath of the git toplevel and the role pending head equal to git rev-parse HEAD (computed by state.mjs, no head flag exists), record the role report set on the first pending dispatch, append a newer head on a later dispatch, write nothing on a repeat with the same head and report set, replace a block of another ref, and refuse a ref that is not current_focus.ref_id with exit 2 and no write; with AAI_ROLE set to any non-empty value, whitespace included, it SHALL exit 3 and write nothing, and check-role-output.mjs SHALL refuse a returned state.mjs bind-check command with E-STATE-UPDATE-COMMAND. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2801.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2802.log | — | TEST-2801, TEST-2802 |
| Spec-AC-02 | WHEN state.mjs bind-check --on verdict runs and the role has a pending head, a pass or fail verdict of the role for the ref and at least one report path not in the pending report set, the system SHALL write the role head (the first pending head, or forty zeros when a later pending head does not descend from it), status, reports, their sha256 digests and the D3 marker, set security_sticky when the marker is true and never lower it, and clear the role pending fields; with no pending head, no pass or fail verdict, a verdict of another ref, no new report path (a re-record of the old report) or a repeat it SHALL write nothing. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2803.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2804.log | — | TEST-2803, TEST-2804 |
| Spec-AC-03 | WHEN recheckMode decides a Validation or Code Review round the system SHALL take the base from the bound role head and SHALL return full with the D4 reason for each failing comparison (first_round, binding_ambiguous, binding_other_checkout, binding_pending, base_not_ancestor, binding_report_changed, security_relevant:binding, security_marker_absent:binding, replace_refs_present), and SHALL NOT read any check_ line of EVENTS.jsonl: appending forged check_verdict or check_dispatched lines to a bound eligible fixture leaves the result deep-equal, and forged lines with no binding give first_round. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2805.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2806.log | — | TEST-2805, TEST-2806 |
| Spec-AC-04 | WHEN each shape of the D5 table is applied to a fixture with two bound Validation rounds (true then false) and a non-production delta, recheckMode SHALL return full with the comparison the table names, under AAI_RECHECK_MODE=delta and under the default environment, for all eleven shapes. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2807.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2808.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2809.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2810.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2811.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2812.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2813.log | — | TEST-2807, TEST-2808, TEST-2809, TEST-2810, TEST-2811, TEST-2812, TEST-2813 |
| Spec-AC-05 | WHEN ride-handoff.mjs out hands a ride whose STATE holds check_binding to a worktree, the worktree STATE SHALL hold no check_binding and recheckMode there SHALL give first_round; a STATE copied by hand into another checkout SHALL give binding_other_checkout; a metrics-flush partial reset of the bound ref SHALL clear both roles verdict and pending fields and keep ref_id, checkout and security_sticky; a full reset SHALL remove the block; reset-block SHALL leave the block byte-identical; a STATE file under docs/ai/archive SHALL never be read; check-state.mjs SHALL exit 0 on a STATE holding the block. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2814.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2815.log | — | TEST-2814, TEST-2815 |
| Spec-AC-06 | WHEN a fixture runs real orchestration-dispatch.mjs --confirm ticks, real state.mjs verdict writes and reset-block through a Validation round and a Code Review round, each fail, a test-only remediation commit and the next dispatch, the next dispatch SHALL carry recheck mode delta with base equal to the head of the first dispatch of that role read from check_binding, canon build --recheck delta SHALL exit 0 with the tick's own dispatch record pending (D14); after a production commit the dispatch SHALL be full with production_path; role, rule, suggested_tier, suggested_model, suggested_effort, validator_independence and lane SHALL equal the same snapshot under AAI_RECHECK_MODE=full with AAI_HARNESS=claude. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2816.log | — | TEST-2816 |
| Spec-AC-07 | check-role-output.mjs SHALL print RECHECK-ESCALATION for a BLOCKED block whose only blocker is needs_full_recheck only with --recheck-mode delta, print nothing extra with --recheck-mode full or without the flag, and exit 2 on any other value; ORCHESTRATION.prompt.md (at most 45 lines), ORCHESTRATION_PARALLEL.prompt.md and SUBAGENT_PROTOCOL.md SHALL each contain --recheck-mode and the phrase run none of its state_update_commands. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2817.log | — | TEST-2817 |
| Spec-AC-08 | The eventsAppendOnly comment in recheck.mjs SHALL contain compares only and SHALL NOT contain fu-recheck-uncommitted-stamp-rewrite or the sentence that committed lines are protected; recheck.mjs and check-binding.mjs SHALL contain none of tamper-proof, guarantee, closes every, cannot be forged. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2818.log | — | TEST-2818 |
| Spec-AC-09 | WHEN a dispatched subagent environment (AAI_ROLE=subagent) runs orchestration-dispatch.mjs --confirm on an eligible fixture the system SHALL write no check_binding change (bind-check refused, failure swallowed, dispatch exit code unchanged), and the next orchestrator tick SHALL still decide from the unchanged block. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2802.log | — | TEST-2802 |
| Spec-AC-10 | The Delta re-check section of SUBAGENT_PROTOCOL.md, the WORKFLOW.md delta re-check sentence and the CHANGELOG entry of this scope SHALL name check_binding and bind-check, carry exactly one line starting Residual:, and contain none of tamper-proof, guarantee, closes every, cannot be forged (case-insensitive). | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2819.log | — | TEST-2819 |
| Spec-AC-11 | (Separable, D7.) WHEN AAI_RECHECK_MODE is unset, empty, blank or delta in any case or padding the mode SHALL be enabled, and WHEN it is full in any case or padding, or any other value, the round SHALL be full with recheck_disabled, through recheckMode, the dispatch recheck field and canon build --recheck delta; SUBAGENT_PROTOCOL.md, WORKFLOW.md, ORCHESTRATION.prompt.md, ORCHESTRATION_PARALLEL.prompt.md and the CHANGELOG entry SHALL state the default as on with AAI_RECHECK_MODE=full as the opt-out and SHALL NOT call the mode opt-in or off by default. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2820.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2821.log | — | TEST-2820, TEST-2821 |
| Spec-AC-12 | PROFILES.yaml SHALL list .aai/scripts/lib/check-binding.mjs exactly once, in core; select-suites.mjs SHALL print FULL_RUN reason=shared-lib for it while the suite-map aai-recheck row lists it, state.mjs, metrics-flush.mjs and check-role-output.mjs; WHEN the .aai/*.prompt.md glob grew past 370992 bytes the diet ledger SHALL hold one entry naming recheck-verdict-binding whose byte count equals the growth and TEST-010 SHALL report headroom 0. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2822.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2823.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2824.log | — | TEST-2822, TEST-2823, TEST-2824 |
| Spec-AC-13 | The RFC-0017 phase 4 row SHALL have status cell in progress or done and a link target ending recheck-verdict-binding.md beside the cheap-transitions-slice.md link; the frontmatter keeps status implementing and umbrella true; rows 0 and 2 stay in progress, rows 1 and 3 done, row 5 not started. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2825.log | — | TEST-2825 |
| Spec-AC-14 | spec-amend list over the repository ledger SHALL show every spec_amendment record of ref cheap-transitions-slice with ts before 2026-10-24T18:30:00Z in bucket signed or measurement, at least eleven of them signed, and the records at 2026-10-24T12:53:10Z of ref roadmap-serves-downstream-projects, at 2026-10-24T12:53:11Z of refs ride-state-handoff-to-worktree and canon-is-a-build-artifact and at 2026-10-24T13:42:28Z of ref node-first-third-slice signed; follow-ups list --status all SHALL show fu-amend-spec-cheap-transitions-slice, fu-amend-roadmap-serves-downstrea-fb0e2b, fu-amend-canon-is-a-build-artifac-d789f0 and fu-amend-node-first-third-slice-2-6a231a as done. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2826.log | — | TEST-2826 |
| Spec-AC-15 | WHEN recheckMode runs on a scratch copy of the live tree with focus recheck-verdict-binding and this spec as the spec path, for Validation and Code Review, the system SHALL return full with ceremony_l3 among the reasons. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2827.log | — | TEST-2827 |
| Spec-AC-16 | The SPEC-0250 TEST-2742 node case SHALL assert mode full for each of its shapes, the SPEC-0250 TEST-2742 row and D4 SHALL name spec-recheck-verdict-binding and SHALL NOT say the residual is pinned, docs/ai/decisions.jsonl SHALL hold a spec_amendment record of ref cheap-transitions-slice after 2026-10-24T18:30:00Z whose tracked_by is not fu-amend-spec-cheap-transitions-slice, and spec-amend list --strict SHALL exit 0. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2828.log | — | TEST-2828 |
| Spec-AC-17 | WHEN a report is read for its security_relevant marker (markerOfText, used by bind-check at verdict and by recheckMode for prior reports) the system SHALL count a marker line only when it starts at column 0 outside every fenced code block (a fence of three or more backticks or tildes, opened with at most three leading spaces and closed by a line of the same character and at least that length); a false line inside a fence SHALL NOT make a report marked, a true line at column 0 outside a fence SHALL give true, a report with an unclosed fence and no true marker outside it SHALL give null, a report with a fence and one real false line outside it SHALL give false, and through bind-check and recheckMode a report whose only false marker sits inside a fence SHALL give full with security_marker_absent:binding:validation. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2829.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2830.log | — | TEST-2829, TEST-2830 |
| Spec-AC-18 | WHEN recheckMode decides a bound round the system SHALL take the ceremony level from the stricter of the spec the binding records (spec_path, recorded once by bind-check dispatch from STATE) and the spec STATE names now, each read live and at the base, SHALL return full with spec_path_changed:binding when STATE names another path and with spec_path_unbound:binding when the block records none, and WHEN the work item spec_path or the focus spec_path is re-pointed at a lower-level spec after the bind of a level 3 spec it SHALL give ceremony_l3. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2831.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2832.log | — | TEST-2831, TEST-2832 |
| Spec-AC-19 | WHEN the check_binding block is replaced (a focus switch to another ref and back through state.mjs commands, git worktree move, a block that does not parse), the system SHALL keep the check_sticky entry of the ref, so that after an earlier bound security_relevant true a later bound false round with a test-only delta gives full with security_relevant:sticky or security_relevant:binding under AAI_RECHECK_MODE=delta and under the default environment, in the alternation r1 to r2 to r1 repeated twice; WHEN a spec path is re-pointed at a lower-level spec after a focus switch the entry SHALL hold both paths and recheckMode SHALL give ceremony_l3; ride-handoff.mjs out SHALL copy the entry of its ref into the worktree STATE (flag raised when the origin record does not parse or a block of the ref has no entry) and the worktree rounds SHALL give full; a partial flush, a full flush and reset-block SHALL leave the check_sticky block byte-identical; a bound block with no entry SHALL give sticky_record_absent:binding and an entry that does not parse SHALL give sticky_record_ambiguous; each control without an earlier true gives delta; WHEN a bind rebuilds a record that has a line that does not parse or two items for one ref, the system SHALL keep the unparsable line byte for byte and merge the repeated items to the highest flag, so that the damaged ref stays full after a bind for another ref; a STATE file with no raised entry for the ref (a worktree STATE not written by ride-handoff.mjs out, a STATE recreated in the same checkout, the origin STATE after a worktree raised the flag) is stated as the per-STATE-file gap and is not claimed. | done | docs/ai/tdd/recheck-verdict-binding/green/TEST-2833.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2834.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2835.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2836.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2837.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2838.log, docs/ai/tdd/recheck-verdict-binding/green/TEST-2839.log | — | TEST-2833, TEST-2834, TEST-2835, TEST-2836, TEST-2837, TEST-2838, TEST-2839 |

## Implementation plan

1. RED: add the TEST-2801 to TEST-2828 node cases to
   `tests/skills/lib/recheck.test.mjs`, their functions to
   `tests/skills/test-aai-recheck.sh` and TEST-2824 to
   `tests/skills/test-aai-prompt-diet.sh`; run each function alone on the
   unchanged tree and store the output under
   `docs/ai/tdd/recheck-verdict-binding/red/`. The D5 tamper rows build their
   fixture twice: once with the EVENTS stamps the base code reads (stored RED:
   `delta` on `59ee0ff2` for shapes 1 to 8 and 10) and once through
   `bind-check`.
2. `lib/check-binding.mjs` and `state.mjs bind-check` (D1 to D3); TEST-2801
   to TEST-2804 green.
3. `recheckMode` reads the binding (D4), `gitEnv()`, `replace_refs_present`;
   TEST-2805, TEST-2806, TEST-2810 green; existing SPEC-0250 node cases move
   their judged-round fixtures from hand-written stamps to `bind-check`.
4. Dispatch wiring (`bindCheck` on `--confirm`), flush (`clearCheckBinding`,
   `removeCheckBinding`); TEST-2802 (Spec-AC-09 half), TEST-2814 to TEST-2816
   and the remaining D5 rows green.
5. Escalation flag and wording, the comment, the binding docs (D8, D9, D10);
   TEST-2817 to TEST-2819 green. SPEC-0250 amendment (binding part) and the
   TEST-2742 flip; TEST-2828 green. Rows of SPEC-0250 are edited BEFORE its
   amendment record is appended.
6. Governance and RFC (D10); TEST-2822 to TEST-2827 green.
7. Run the Verification list, record one mutation per row with
   `mutation-run.mjs`, run `mutation-gate.mjs` for this spec, and re-run
   `mutation-run.mjs` for each re-anchored or rewritten SPEC-0250 row.
8. The flip, as ONE separate commit (D7); TEST-2820 and TEST-2821 green, the
   SPEC-0250 TEST-2731 and TEST-2738 cases rewritten, and the flip part of the
   SPEC-0250 amendment. Its RED is stored before the commit.
9. Remediation round 1 (code review r1 and validation r1 findings, 2026-10-24): D15 and Spec-AC-19, the TEST-2833 to
   TEST-2837 cases, the wording corrections of the flip, the rename of the TEST-2831 title and the TEST-2738
   function. It lands on top of the D7 commit because the corrected wording describes the default as on; the flip
   is therefore no longer the tip, and reverting it alone needs the wording lines of this round reverted with it.
10. Remediation round 2 (code review r2 and validation r2, 2026-10-24): the per-STATE-file wording of D9, D15 and
    Spec-AC-19 in the spec, the protocol, the CHANGELOG and the code comments; the rebuild of a damaged
    record (TEST-2838, TEST-2839); the four present-tense off or opt-in texts and the TEST-2821 extension; the
    forward-commit revert recipe in D7. The amendment records are appended last.

Seams crossed (each with a test that produces on one side and reads the real
result on the other):

- `state.mjs bind-check` writes STATE, `recheckMode` reads it: TEST-2805 and
  every D5 row use the real CLI, never a hand-written block.
- Dispatch tick to `bind-check` to the next tick's decision: TEST-2816.
- Dispatch under `AAI_ROLE=subagent` to the refused write: TEST-2802.
- `ride-handoff.mjs` to the worktree STATE to `recheckMode`: TEST-2814.
- `ride-handoff.mjs out` to the worktree STATE entry to `recheckMode` after two worktree rounds: TEST-2835.
- `metrics-flush.mjs` to the block to `recheckMode`; `check-state.mjs` over
  the block: TEST-2815.
- The returned `state_update_commands` to `check-role-output.mjs`
  (`bind-check` refused) and the `--recheck-mode` flag to the escalation line:
  TEST-2802, TEST-2817.
- Not crossed by a test: a live ride's delta round after the flip (no ride in
  this slice runs one, D12); named under Risks.

### Mutation anchors

The Test Plan mutation cells name these code forms; Implementation writes
them as named. A cell whose form the code cannot keep is re-anchored with a
`spec-amend` restamp that keeps the same comparison disabled.

- `check-binding.mjs`: `export const BINDING_BLOCK = 'check_binding';`,
  `if (samePending) return null;`, `if (fresh.length === 0) return null;`,
  `digests: reports.map((p) => sha256OfFile(root, p)),`,
  `const sticky = prior.securitySticky === true ? true : marker === true;`,
  `return readBindingBlock(lines);`,
  `if (sha256OfFile(root, p) !== bound.digests[i])`,
  `binding.checkout !== checkoutOf(root)`,
  `binding.securitySticky === true`,
  `if (replaceRefsPresent(root)) reasons`,
  `GIT_NO_REPLACE_OBJECTS: '1'`.
- `recheck.mjs`: `if (!bound) reasons.push('first_round');`,
  `const DEFAULT_ON = true;`, `if (bound.specPath !== specPath)`,
  `new Set([bound.specPath, specPath])`.
- D13 (`check-binding.mjs`): `fence = { ch: open[1][0], len: open[1].length };`,
  `if (fence !== null) return null;`,
  `specPath: prior.specPath ?? stateSpecPath(lines, ref),`.
- D15 (`check-binding.mjs`, `recheck.mjs`, `ride-handoff.mjs`): `security: (had ? had.security : false) || security === true`,
  `else if (entry.security === true) reasons.push('security_relevant:sticky');`,
  `for (const rp of recorded) if (!levelPaths.includes(rp)) levelPaths.push(rp);`,
  `carrySticky(lines, originLines, ref);`.
- `state.mjs`: `const BIND_ROLE_GUARD = true;`.
- `orchestration-dispatch.mjs`: `bindCheck(root, statePath, stampRef, t, 'verdict');`.
- `metrics-flush.mjs`: `clearCheckBinding(lines, flushedRefs);`.
- `check-role-output.mjs`: `if (recheckModeArg === 'delta')`.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-2801 | Spec-AC-01 | unit | tests/skills/test-aai-recheck.sh | test_2801_bind_on_dispatch runs node --test --test-name-pattern TEST-2801: in a fixture repo state.mjs bind-check --on dispatch writes ref_id, checkout (realpath of the toplevel), the pending head equal to git rev-parse HEAD and the pending report set; a repeat appends nothing (STATE byte-identical); a commit then a second dispatch appends the newer head and keeps the first report set; a dispatch for another focus ref replaces the block; a ref other than current_focus.ref_id exits 2 with STATE byte-identical; the subcommand rejects a --head flag as unknown | `sed:s/if \(samePending\) return null;//` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2802 | Spec-AC-01, Spec-AC-09 | integration | tests/skills/test-aai-recheck.sh | test_2802_bind_refused_for_subagent runs bind-check with AAI_ROLE=subagent, a space and a tab: exit 3, STATE byte-identical; unset writes; check-role-output.mjs on a Validation PASS block whose state_update_commands holds a state.mjs bind-check line reports E-STATE-UPDATE-COMMAND; orchestration-dispatch.mjs --confirm under AAI_ROLE=subagent on an eligible fixture leaves check_binding byte-identical and exits as without the guard | `sed:s/const BIND_ROLE_GUARD = true;/const BIND_ROLE_GUARD = false;/` on .aai/scripts/state.mjs | green |
| TEST-2803 | Spec-AC-02 | unit | tests/skills/test-aai-recheck.sh | test_2803_bind_on_verdict: after a dispatch and set-validation fail with a new report, bind-check --on verdict writes the first pending head, status fail, the report paths, digests equal to an independent sha256 of each file, security false, and clears the pending fields; a report saying true sets security true and security_sticky true; a later bound round with false keeps security_sticky true; a report without the marker line gives security null; the same for code_review with report_paths | `sed:s/digests: reports\.map\(\(p\) => sha256OfFile\(root, p\)\),/digests: reports.map(() => '0'.repeat(64)),/` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2804 | Spec-AC-02 | unit | tests/skills/test-aai-recheck.sh | test_2804_bind_refusals: nothing is written for no pending head, a not_run verdict, a verdict whose ref_id is another ref, a re-record naming only the report set recorded at dispatch (probe D2), and a repeat after the bind; two pending heads on one line of history bind the first; a pending head on a sibling branch binds forty zeros | `sed:s/if \(fresh\.length === 0\) return null;//` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2805 | Spec-AC-03 | unit | tests/skills/test-aai-recheck.sh | test_2805_eligibility_reads_binding: a fixture bound through bind-check with a test-only delta gives delta with base equal to the bound head; then one comparison at a time gives full with exactly its reason: no block (first_round), a block of another ref (first_round), a duplicate top-level check_binding key and a digest list shorter than the report list (binding_ambiguous), a different checkout value written by a second checkout of the repo (binding_other_checkout), a newer dispatch without a verdict (binding_pending:validation), a forty-zero head (base_not_ancestor), an edited and a deleted bound report (binding_report_changed), a true marker of the other role (security_relevant:binding), a null marker (security_marker_absent:binding:validation) | `sed:s/binding\.checkout !== checkoutOf\(root\)/false/` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2806 | Spec-AC-03 | unit | tests/skills/test-aai-recheck.sh | test_2806_stamps_not_read: on the bound eligible fixture, appending check_verdict lines with security_relevant true, with a later head and for the other role, and check_dispatched lines, leaves recheckMode deep-equal (delta, same base); a fixture with forged check_verdict lines and no check_binding gives full with exactly first_round among the stamp reasons | `sed:s/return readBindingBlock\(lines\);/return null;/` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2807 | Spec-AC-04 | unit | tests/skills/test-aai-recheck.sh | test_2807_uncommitted_and_amend (D5 shapes 1 and 2) on the two-round fixture: an uncommitted in-place flip of the true stamp, and the flip folded in with commit --amend, each give full with security_relevant:binding under AAI_RECHECK_MODE=delta and full under the default env; the stored RED shows delta for both on 59ee0ff2 | `sed:s/binding\.securitySticky === true/false/` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2808 | Spec-AC-04 | unit | tests/skills/test-aai-recheck.sh | test_2808_rebase_and_squash (D5 shapes 3 and 4): a rebase that drops the commit holding the true stamp, and a squash merge of a side branch resolved to ours that drops it, each give full with security_relevant:binding under both envs | `sed:s/next\.securitySticky = rec\.security;/next.securitySticky = false;/` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2809 | Spec-AC-04 | unit | tests/skills/test-aai-recheck.sh | test_2809_rewrite_before_base (D5 shape 5, r6 B-12): a commit appending a true stamp and a later commit flipping it, both before the bound base of round 2, give full with security_relevant:binding under both envs | `sed:s/binding\.securitySticky === true/binding.securitySticky === 7/` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2810 | Spec-AC-04 | unit | tests/skills/test-aai-recheck.sh | test_2810_git_replace (D5 shape 6) on a fixture with markers false: git replace of the base commit by a commit whose tree already holds a production change, git replace --graft, an info/grafts file, each give full with replace_refs_present; a replace ref under refs/other/ with GIT_REPLACE_REF_BASE=refs/other/ exported gives full with production_path naming the hidden file; the control without any replace gives production_path too and the same fixture without the production change gives delta | `sed:s/if \(replaceRefsPresent\(root\)\) reasons/if (false) reasons/` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2811 | Spec-AC-04 | unit | tests/skills/test-aai-recheck.sh | test_2811_forged_append (D5 shapes 7 and 8): with a bound false round, a production commit and a hand-appended check_verdict at the new head with security_relevant false give full with production_path and base equal to the bound head; with no binding a hand-appended check_verdict gives first_round | `sed:s/if \(!bound\) reasons\.push\('first_round'\);/if (false) reasons.push('first_round');/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2812 | Spec-AC-04 | unit | tests/skills/test-aai-recheck.sh | test_2812_merge_ours_and_rerecord (D5 shapes 9 and 10): merge -s ours dropping a side-branch commit with a true stamp gives full with security_relevant:binding and merge_in_range; a crashed check followed by set-validation re-recording the old report gives full with binding_pending:validation | `sed:s/binding\.securitySticky === true/binding.securitySticky === 'x'/` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2813 | Spec-AC-04 | unit | tests/skills/test-aai-recheck.sh | test_2813_bound_report_flip (D5 shape 11, Q8 and Q9): a bound Code Review report flipped from true to false and committed, and a bound gitignored Validation report flipped in place (git status empty), each give full with binding_report_changed naming the path | `sed:s/!== bound\.digests\[i\]/=== 'never'/` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2814 | Spec-AC-05 | integration | tests/skills/test-aai-recheck.sh | test_2814_handoff_and_copy: ride-handoff.mjs out on a fixture whose STATE holds check_binding leaves no check_binding in the worktree STATE and recheckMode there gives first_round; the origin STATE copied by cp into a second worktree of the same repo gives binding_other_checkout; a STATE copy under docs/ai/archive/merge-cleanup/ with the live block removed gives first_round | `sed:s/binding\.checkout !== checkoutOf\(root\)/binding.checkout === 'x'/` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2815 | Spec-AC-05 | integration | tests/skills/test-aai-recheck.sh | test_2815_flush_reset_and_check_state: metrics-flush.mjs partial reset of the bound ref clears both roles verdict and pending fields and keeps ref_id, checkout and security_sticky, then recheckMode gives first_round; the full reset removes the block; reset-block last_validation leaves the block byte-identical; check-state.mjs exits 0 on the STATE with the block | `sed:s/clearCheckBinding\(lines, flushedRefs\);//` on .aai/scripts/metrics-flush.mjs | green |
| TEST-2816 | Spec-AC-06 | e2e | tests/skills/test-aai-recheck.sh | test_2816_end_to_end_binding with AAI_HARNESS=claude: real --confirm ticks dispatch Validation (H1), set-validation fail with a new report, a tick binds it, Remediation dispatch, a test-only commit, reset-block, a tick dispatches Validation with recheck mode delta and base H1 read from check_binding, canon build --recheck delta exits 0 although the tick left its own dispatch pending (D14, ownDispatch); the same for Code Review; after a commit to .aai/scripts/fixture.mjs the dispatch is full with production_path; the independence fields equal the AAI_RECHECK_MODE=full run | `sed:s/bindCheck\(root, statePath, stampRef, t, 'verdict'\);/void 0;/` on .aai/scripts/orchestration-dispatch.mjs | green |
| TEST-2817 | Spec-AC-07 | integration | tests/skills/test-aai-recheck.sh | test_2817_escalation_knows_mode runs check-role-output.mjs on a BLOCKED block with the single blocker needs_full_recheck: with --recheck-mode delta it prints RECHECK-ESCALATION; with --recheck-mode full and without the flag it prints no RECHECK-ESCALATION and exits 0; --recheck-mode bogus exits 2; ORCHESTRATION.prompt.md has at most 45 lines and it, ORCHESTRATION_PARALLEL.prompt.md and SUBAGENT_PROTOCOL.md each contain --recheck-mode and run none of its state_update_commands | `sed:s/if \(recheckModeArg === 'delta'\)/if (true)/` on .aai/scripts/check-role-output.mjs | green |
| TEST-2818 | Spec-AC-08 | inspection | tests/skills/test-aai-recheck.sh | test_2818_comments_state_comparison extracts the comment block above eventsAppendOnly in recheck.mjs: it contains compares only and neither fu-recheck-uncommitted-stamp-rewrite nor only lines already present in a committed blob are protected; recheck.mjs and check-binding.mjs contain none of the four banned phrases (case-insensitive) | `sed:s/compares only/compares/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2819 | Spec-AC-10 | inspection | tests/skills/test-aai-recheck.sh | test_2819_docs_state_comparison checks the Delta re-check section of SUBAGENT_PROTOCOL.md, the WORKFLOW.md line containing delta re-check and the CHANGELOG entry naming recheck-verdict-binding: each names check_binding and bind-check, the protocol section has exactly one line starting Residual:, and none contains tamper-proof, guarantee, closes every or cannot be forged (case-insensitive) | `sed:s/Residual:/Note:/` on .aai/SUBAGENT_PROTOCOL.md | green |
| TEST-2820 | Spec-AC-11 | unit | tests/skills/test-aai-recheck.sh | test_2820_default_on: deltaEnabled is true for unset, empty, blank, delta, DELTA and padded delta, false for full, FULL, padded full, off, 0, false and a misspelling; on an eligible bound fixture with AAI_RECHECK_MODE unset recheckMode gives delta, the dispatch recheck field gives delta with the delta system_prompt and canon build --recheck delta exits 0; with full each gives recheck_disabled and canon exits 11 | `sed:s/const DEFAULT_ON = true;/const DEFAULT_ON = false;/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2821 | Spec-AC-11 | inspection | tests/skills/test-aai-recheck.sh | test_2821_default_on_docs: SUBAGENT_PROTOCOL.md Delta re-check section, the WORKFLOW.md delta re-check line, ORCHESTRATION.prompt.md, ORCHESTRATION_PARALLEL.prompt.md and the CHANGELOG entry naming recheck-verdict-binding each contain AAI_RECHECK_MODE=full, and none of their recheck sentences contains opt-in, OPT-IN or off by default; SPEC-0250 Spec-AC-17 names spec-recheck-verdict-binding; the RECHECK-ESCALATION lines of the protocol section name AAI_RECHECK_MODE=full and never full-or-unset, the RFC-0017 lines naming this slice do not say the mode stays opt-in, the #498 CHANGELOG entry says that a later entry changes the default, and SPEC-0250 holds none of the five old-default phrases; remediation round 2 adds that SPEC-0250 does not say the mode is off unless exported, that the recheck-verdict-binding CHANGELOG heading does not call the mode opt-in or off by default (the #498 heading keeps its merged text, since aai-release TEST-024 forbids rewriting an unreleased heading present at the merge-base; its body says the later entry changed the default), and that append-event.mjs does not say recheck reads the stamps or an opt-in default and says they are telemetry | `sed:s/not read them; it compares/not read them; it reads them back to decide whether the next round may run; it compares/` on .aai/scripts/append-event.mjs | green |
| TEST-2822 | Spec-AC-12 | inspection | tests/skills/test-aai-recheck.sh | test_2822_profiles_classified asserts .aai/scripts/lib/check-binding.mjs appears exactly once in PROFILES.yaml, inside the core list | `sed:s/lib\/check-binding\.mjs/lib\/check-binding-gone.mjs/g` on .aai/system/PROFILES.yaml | green |
| TEST-2823 | Spec-AC-12 | integration | tests/skills/test-aai-recheck.sh | test_2823_suite_map_selects feeds .aai/scripts/lib/check-binding.mjs to select-suites.mjs --files-from - and requires FULL_RUN reason=shared-lib, and requires the suite-map aai-recheck row to list check-binding.mjs, state.mjs, metrics-flush.mjs and check-role-output.mjs; feeding state.mjs selects aai-recheck | `sed:s/lib\/check-binding\.mjs/lib\/check-binding-gone.mjs/g` on tests/skills/suite-map.yaml | green |
| TEST-2824 | Spec-AC-12 | inspection | tests/skills/test-aai-prompt-diet.sh | test_2824_diet_entry_for_binding computes the .aai/*.prompt.md glob bytes minus 370992: when positive it requires exactly one JUSTIFIED_ADDITIONS entry naming recheck-verdict-binding whose leading byte count equals that growth; when zero or negative it requires no such entry; in both cases the TEST-010 headroom computed by compute_reduction_headroom is 0 | `sed:s/recheck-verdict-binding/recheck-binding-gone/g` on tests/skills/lib/prompt-diet-ledger.sh | green |
| TEST-2825 | Spec-AC-13 | inspection | tests/skills/test-aai-recheck.sh | test_2825_rfc_phase4_row parses the RFC-0017 Rollout Status table: phase 4 status cell in progress or done, one link target ending recheck-verdict-binding.md and one ending cheap-transitions-slice.md; frontmatter status implementing and umbrella true; rows 0 and 2 in progress, rows 1 and 3 done, row 5 not started | `sed:s/recheck-verdict-binding\.md/recheck-gone.md/g` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |
| TEST-2826 | Spec-AC-14 | inspection | tests/skills/test-aai-recheck.sh | test_2826_498_amendments_signed runs node .aai/scripts/spec-amend.mjs list --json (stdout read into node, not argv) and requires every cheap-transitions-slice record with ts before 2026-10-24T18:30:00Z in signed or measurement with at least eleven signed, and the four cross-spec records at 12:53:10Z, 12:53:11Z (two refs) and 13:42:28Z signed; then follow-ups.mjs list --status all --json requires the four named trackers done (fu-amend-ride-state-handoff-to-worktree is not required: its open record dates from 2026-10-22) | `sed:s/"classifies_ts":"2026-10-24T13:42:28Z","classifies_ref":"node-first-third-slice","owner_signoff":true/"classifies_ts":"2026-10-24T13:42:28Z","classifies_ref":"node-first-third-slice","owner_signoff":false/` on docs/ai/decisions.jsonl | green |
| TEST-2827 | Spec-AC-15 | integration | tests/skills/test-aai-recheck.sh | test_2827_ride_stays_full runs recheckMode on a scratch copy of the live tree with STATE focus recheck-verdict-binding and this spec as spec path, role Validation and role Code Review, under AAI_RECHECK_MODE unset and delta: mode full and ceremony_l3 in the reasons for all four runs | `sed:s/const PROTECTED_LEVEL = 3;/const PROTECTED_LEVEL = 9;/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2828 | Spec-AC-16 | inspection | tests/skills/test-aai-recheck.sh | test_2828_spec0250_superseded runs the TEST-2742 node cases (green, asserting full) and checks the SPEC-0250 TEST-2742 row and D4 name spec-recheck-verdict-binding and do not contain pins the KNOWN general residual; reads decisions.jsonl for a spec_amendment of ref cheap-transitions-slice after 2026-10-24T18:30:00Z whose tracked_by differs from fu-amend-spec-cheap-transitions-slice; spec-amend list --strict exits 0 (rc read without a pipe) | `sed:s/spec-recheck-verdict-binding/spec-gone/g` on docs/specs/SPEC-0250-spec-cheap-transitions-slice.md | green |
| TEST-2829 | Spec-AC-17 | unit | tests/skills/test-aai-recheck.sh | test_2829_fenced_marker runs node --test --test-name-pattern TEST-2829: markerOfText gives false for a column-0 false line outside a fence, null for a false line only inside a backtick fence, only inside a tilde fence and only inside a fence opened with three leading spaces, null for a false line indented four spaces, true for a true line at column 0 outside a fence, null for an unclosed fence with no true marker, false for a fence followed by one real false line, null for a fence followed by two real marker lines, and a shorter closing line does not close a longer fence; the stored RED is the same text on 59ee0ff2 giving false for the fenced-only report | `sed:s/fence = \{ ch: open\[1\]\[0\], len: open\[1\]\.length \};/fence = null;/` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2830 | Spec-AC-17 | integration | tests/skills/test-aai-recheck.sh | test_2830_fenced_marker_seam: a two-round fixture bound through bind-check whose Validation report holds its only false marker inside a fence gives full with security_marker_absent:binding:validation and a prior-report security_marker_absent reason; the same fixture with one real false line outside the fence gives delta; a report with an unclosed fence gives null in the binding | `sed:s/if \(fence !== null\) return null;//` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2831 | Spec-AC-18 | unit | tests/skills/test-aai-recheck.sh | test_2831_specpath_repoint: a ride bound on a level 3 spec whose STATE work item spec_path is re-pointed at a level 2 spec, and one whose current_focus spec_path is re-pointed, each give full with spec_path_changed:binding and ceremony_l3; a block with no recorded spec_path gives spec_path_unbound:binding; the unchanged level 2 control gives delta; the stored RED is the stamp-built twin on 59ee0ff2 giving delta after the re-point | `sed:s/new Set\(\[bound\.specPath, specPath\]\)([\s\S]*?)for \(const rp of recorded\) if \(!levelPaths\.includes\(rp\)\) levelPaths\.push\(rp\);/new Set([specPath])$1/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2832 | Spec-AC-18 | unit | tests/skills/test-aai-recheck.sh | test_2832_specpath_recorded: bind-check --on dispatch records spec_path from STATE once, a later dispatch after STATE was re-pointed keeps the first path, a verdict write keeps it, a dispatch for another ref replaces the block with that ref spec path, and the flush partial reset keeps it | `sed:s/specPath: prior\.specPath \?\? stateSpecPath\(lines, ref\),/specPath: null,/` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2833 | Spec-AC-19 | integration | tests/skills/test-aai-recheck.sh | test_2833_focus_alternation_sticky (probe A3, slug refs): round 1 of ride-one bound true through bind-check, set-focus to hotfix-two and a dispatch bind for it replace the block (the record of ride-one still says security true), set-focus back, a dispatch, set-validation fail with a new report marked false and a verdict bind; a test-only change then gives full with security_relevant:binding or security_relevant:sticky under the delta env and the default env; the alternation repeated once more leaves only the record carrying the flag and gives full with security_relevant:sticky; the control that never bound true gives delta after the same alternation | `sed:s/security: \(had \? had\.security : false\)/security: (false)/` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2834 | Spec-AC-19 | integration | tests/skills/test-aai-recheck.sh | test_2834_worktree_move_sticky (probe WM): in a linked worktree round 1 is bound true and round 2 false, git worktree move changes the checkout (binding_other_checkout), a dispatch bind and a full round marked false replace the block, and a test-only change then gives full with security_relevant:binding or security_relevant:sticky under both envs; the control move without an earlier true gives delta | `sed:s/(const had = )cur\.entries\.get\(ref\);([\s\S]*?const goneSecurity = )gone !== null/$1undefined;$2false/` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2835 | Spec-AC-19 | integration | tests/skills/test-aai-recheck.sh | test_2835_handoff_sticky: ride-handoff.mjs out on a fixture whose STATE holds a true entry writes an equal entry into the worktree STATE and no check_binding, the worktree gives first_round, two worktree rounds marked false keep the entry true and a test-only change gives full; an origin check_sticky block that does not parse, and an origin check_binding block with no entry, are each carried as an entry with security true | `sed:s/carrySticky\(lines, originLines, ref\);//` on .aai/scripts/ride-handoff.mjs | green |
| TEST-2836 | Spec-AC-19 | integration | tests/skills/test-aai-recheck.sh | test_2836_specpath_record: an L3 spec is bound, set-focus switches away and back with STATE spec_path naming an L2 spec, a full round binds the L2 path; the entry holds both paths and a test-only change gives full with ceremony_l3 under both envs; the control with two L2 specs gives delta | `sed:s/for \(const rp of recorded\) if \(!levelPaths\.includes\(rp\)\) levelPaths\.push\(rp\);//` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2837 | Spec-AC-19 | integration | tests/skills/test-aai-recheck.sh | test_2837_record_kept_by_flush_and_reset: a partial flush and reset-block leave the check_sticky block byte-identical, a full flush removes check_binding and leaves the entry, a later bind with a false marker keeps security true; a bound block with the entry removed gives full with sticky_record_absent:binding, an entry that does not parse gives sticky_record_ambiguous, and a bind over it rewrites the entry with security true; the control with the entry present gives delta | `sed:s/if \(entry === undefined\) reasons\.push\('sticky_record_absent:binding'\);/if (entry === 5) reasons.push('sticky_record_absent:binding');/` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2838 | Spec-AC-19 | integration | tests/skills/test-aai-recheck.sh | test_2838_unparsable_item_kept: a bound true ride whose check_sticky item has security turned into a string gives full with sticky_record_ambiguous; a dispatch bind for another ref keeps that line byte for byte and raises the entry of the other ref; after a false verdict round of the damaged ref and a test-only change the mode is full with sticky_record_ambiguous under the delta env and the default env; the control with an undamaged record of a false ride gives delta after the same alternation | `sed:s/out\.push\(\.\.\.keptLines\);//` on .aai/scripts/lib/check-binding.mjs | green |
| TEST-2839 | Spec-AC-19 | integration | tests/skills/test-aai-recheck.sh | test_2839_duplicate_items_merged: a record holding a false and a true item for one ref (both orders) gives full; after a dispatch bind for another ref and a false verdict round of the ref, a test-only change gives full under the delta env and the default env, one item remains for the ref and it holds security true | `sed:s/first\.security \S+ o\.security/first.security && o.security/` on .aai/scripts/lib/check-binding.mjs | green |

### RED observations and positive controls

- TEST-2801 to TEST-2806 and TEST-2814 to TEST-2817: RED on the base because
  `bind-check`, `check-binding.mjs`, the `--recheck-mode` flag and the flush
  helpers do not exist. The node wrapper's zero-passing-tests guard makes a
  missing case RED, not vacuously green.
- TEST-2807 to TEST-2813: the stored RED is the stamp-built twin of each
  fixture on `59ee0ff2`, which returns `delta` for D5 shapes 1 to 8 and 10
  (TEST-2742 already pins shapes 1 and 2 as delta there). Shapes 9 and 11
  already give full on the base (`merge_in_range`, the stamped marker); their
  RED is the mutation record. If a stamp-built twin does not return `delta`
  on the base, the hand-off says so and the row keeps only its mutation
  record as RED.
- TEST-2818, TEST-2819, TEST-2821 to TEST-2825, TEST-2828: RED on the base
  (literals, rows and entries absent; the comment still holds the dropped id).
- TEST-2820: RED on the base (`deltaEnabled` is false when unset); it is
  stored before the D7 commit.
- TEST-2826 and TEST-2827: pass on the base (signed by `9981130b`; the spec is
  L3); their RED is the mutation record.
- TEST-2833 to TEST-2837 (remediation round 1): RED on `f79fa2dc`, where the block replacement forgets the flag and the
  recorded path and `ride-handoff.mjs out` copies nothing of it; the stored RED is the output of the five cases on that
  commit (probe A3 and probe WM of the reports are their first two fixtures).
- TEST-2838 and TEST-2839 (remediation round 2): RED on `5b70bca8`, where the rebuild dropped the unparsable item and kept the
  first of two items (probes HOSTILE and DUP of code review r2); their RED is the mutation record.
- Positive controls inside fixtures: TEST-2805 and TEST-2810 assert `delta`
  for the unmodified eligible fixture before each refusal; TEST-2807 to
  TEST-2813 assert that the true stamp is present in EVENTS before the shape
  is applied and absent or lowered after it; TEST-2814 asserts the origin
  block exists before the handoff.

## Verification

- New and changed suite: `env -u AAI_ROLE AAI_RECHECK_MODE=full bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-recheck.sh` exits 0.
- Direct Node tests: `node --test tests/skills/lib/recheck.test.mjs` exits 0.
- State, flush, handoff, role output, dispatch, canon: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>` exits 0 for test-aai-state.sh, test-aai-metrics-flush.sh, test-aai-ride-handoff.sh (or the suite that owns ride-handoff), test-aai-role-output.sh, test-aai-orchestration-dispatch.sh, test-aai-canon.sh, test-aai-r-guard.sh, test-aai-check-state.sh.
- Prompt diet: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh` exits 0.
- Governance pins: test-aai-hygiene-pack.sh, test-aai-layer-profiles.sh, test-aai-ceremony-levels.sh, test-aai-lightweight-lane.sh and test-aai-suite-select.sh each exit 0 through the wrapper.
- Selection over the scope: `git diff --name-only 59ee0ff2 | node .aai/scripts/select-suites.mjs --files-from -`; every selected suite exits 0 through the wrapper; one full sweep with `AAI_TEST_TIMEOUT=3000` before close.
- CI-like clean clone: `git clone --no-local /private/tmp/aai-recheck-binding <scratch>/clone`, then in that clone `env -i PATH="$PATH" HOME="$HOME" bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-recheck.sh` and the same for test-aai-state.sh and test-aai-prompt-diet.sh (no STATE, no `AAI_*`, no harness variables), each exit 0; when Docker is available, the recheck suite also in a `node:24` Linux container; otherwise the PR's CI run is the Linux evidence.
- Replay: Validation rebuilds each D5 shape in a scratch clone of the delivered tree and records the `recheckMode` output (all `full`), and replays the #498 probes the reports name (B9 F1/F2/F7, F7i, B-10, B-11, B-12, Q8, Q9, D2, the merge probe).
- Canon claims: `node .aai/scripts/canon.mjs claims` exits 0.
- Amendment ledger: `node .aai/scripts/spec-amend.mjs list --strict` exits 0, rc read directly.
- Registration: `node .aai/scripts/check-test-registration.mjs tests/skills` exits 0.
- Mutation records: `node .aai/scripts/mutation-run.mjs --spec <this spec> --test-id <id> --suite <suite> --selector <function> --target <file> --sed '<expr>'` per row; `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exits 0; each re-anchored or rewritten SPEC-0250 row has a fresh killed record from `mutation-run.mjs --spec docs/specs/SPEC-0250-spec-cheap-transitions-slice.md`.
- Spec lint: `node .aai/scripts/spec-lint.mjs --path <this spec>` reports no error.
- Docs audit: `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path <file>` for this spec, SPEC-0250 and the RFC reports no finding this scope introduced.
- Self-hosting: the hand-off states that every Validation and Code Review round of this ride ran with `AAI_RECHECK_MODE=full` and the full canon payload.

## Evidence contract

Per TEST and Spec-AC: command, exit code, output path under
`docs/ai/tdd/recheck-verdict-binding/`, and the mutation record from
`mutation-run.mjs`. Each AC Evidence cell cites a `docs/ai/tdd/` artifact at
hand-off. Strategy hybrid: stored RED per AC-gating test (the D5 rows store
the base-commit `delta` output of the stamp-built twin) plus the verification
list above. Planning's measurements (370992 glob bytes, headroom 0, 45 lines)
are inputs, not attestations of the implementation.

## Risks and rollback

- The D9 residual sentence is the whole residual of the binding.
- SPEC-0250's own residual stays: the security marker is a classification by
  the checker; a checker that marks a security finding false lets a later
  test-only delta run in delta mode. With the default on, that reaches every
  install with eligible rounds. The delta round is still an independent model
  review of the delta, and a production change still gives full.
- Open P3 items this scope does not fold, whose reach grows with the default
  on: `fu-recheck-duplicate-level-keys`, `fu-recheck-suite-symlink-is-test-code`
  and `fu-recheck-glob-matcher-limits`. The owner folded
  `fu-recheck-fenced-false-marker` and `fu-recheck-specpath-repoint-gives-delta`
  on 2026-10-24 (D13).
- `ledger_rewritten` stays and may refuse delta on a checkout whose line
  endings rewrite the ledger (Windows `core.autocrlf=true`, a carried
  cannot_verify of #498); that gives full, not delta.
- A single-ref block: two scopes that alternate in one STATE replace each
  other's binding, so the round after a switch runs full (`first_round`); the flag and the recorded spec
  paths of each ref stay in the `check_sticky` record (D15), so a later bound round of that ref with an
  earlier true still gives full.
- Two P3 items filed by remediation round 1: `fu-bind-check-role-posture-mismatch` (an orchestrator with
  `AAI_ROLE` set to a non-subagent value never binds, so every round is full) and
  `fu-recheck-state-tracked-premise` (nothing checks that a downstream install gitignores STATE).
- No ride in this slice runs a delta round (D12). The first ride after the
  flip is the observation; `AAI_RECHECK_MODE=full` turns it off per run.
- Editing `.aai/workflow/WORKFLOW.md` makes this L3: operator checkpoint
  before merge. Consumer-visible (the default changes): merge needs the
  owner's menu, which also confirms or declines the D7 flip.
- TEST-2826 pins ledger facts; a legitimate later rewrite of those records
  would redden it and must amend or retire the row.
- Rollback: export `AAI_RECHECK_MODE=full`, or apply the forward-commit recipe of D7
  (delta back to opt-in with the binding kept; `git revert` of the flip commit no longer applies), or revert the scope; an orphan
  `check_binding` block is ignored by every reader but `recheckMode`.

## Registry disposition

Registry items closed by this scope: `fu-recheck-verdict-not-bound-to-check`
(D1 to D5), `fu-recheck-escalation-mode-blind` and
`fu-recheck-escalation-merge-mismatch` (D8), `fu-recheck-comments-overclaim-scope`
(D8), `fu-recheck-fenced-false-marker` and
`fu-recheck-specpath-repoint-gives-delta` (D13, owner decision 2026-10-24).

Related open items, left open: `fu-recheck-duplicate-level-keys`, `fu-recheck-glob-matcher-limits` and
`fu-recheck-suite-symlink-is-test-code` (classification of reports, specs,
protected entries and paths; not stamp tampering; owner decision on folding),
`fu-amend-ride-state-handoff-to-worktree` (its open record
is from the 2026-10-22 ride, not #498).
