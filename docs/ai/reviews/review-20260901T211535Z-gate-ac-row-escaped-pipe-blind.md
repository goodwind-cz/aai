```yaml
review:
  scope: "git diff 7eaeecb..HEAD (branch fix/gate-ac-row-escaped-pipe-blind, commits 2f2f02f, 34ec205) — .aai/scripts/lib/docs-model.mjs, .aai/scripts/lib/docs-audit-core.mjs, tests/skills/test-aai-docs-audit.sh, tests/skills/lib/cd-subshell-leak-baseline.tsv, docs/ai/tests/test-runs.jsonl, CHANGELOG.md, docs/specs/SPEC-0160-spec-gate-ac-row-escaped-pipe-blind.md, docs/issues/ISSUE-0077-gate-ac-row-escaped-pipe-blind.md, docs/INDEX.md"
  spec: docs/specs/SPEC-0160-spec-gate-ac-row-escaped-pipe-blind.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/lib/docs-audit-core.mjs:1678-1697 (reconcileCanonical wired into BOTH canonical branches) + tests/skills/test-aai-docs-audit.sh:4395-4501 (TEST-001) and :4503-4534 (TEST-002); independently re-run green; reviewer's own 434-doc-id pre/post --gate sweep byte-identical; --gate-file probe FAILs correctly" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/lib/docs-audit-core.mjs:1237-1245 + tests/skills/test-aai-docs-audit.sh:4536-4585 (TEST-003); repo-wide `docs-audit.mjs --check --strict --no-event` re-run by reviewer -> exit 0 CLEAN" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/lib/docs-audit-core.mjs:76-86 (single unparseableAcIds) fed by .aai/scripts/lib/docs-model.mjs:622-633 and :662-673 (declaredIds on BOTH parsers); all four call sites (1241, 1269, 1683, 1706) use it; zero `unparseableLeanIds` references remain in code; TEST-004 at tests/skills/test-aai-docs-audit.sh:4587-4621 cross-checks spec-lint vs --gate on the #330 repro" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "reviewer re-ran test-aai-docs-audit.sh, test-aai-ceremony-levels.sh, test-aai-spec-lint.sh, test-aai-close-work-item.sh, test-aai-hygiene-pack.sh -> all PASS; strict repo audit exit 0 CLEAN; generate-docs-index.mjs idempotent (only the Generated: timestamp line differs); check-state.mjs OK; committed sweep ledger 34ec205 records 84/84" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/docs-audit-core.mjs, line: 76,
          issue: "unparseableAcIds reconciles presence-only (Set membership), so a DUPLICATE Spec-AC id where only one copy is pipe-dropped stays invisible to both the gate and the done-drift check — even when the dropped copy is the non-terminal one",
          failure_scenario: "Fixture with rows `| Spec-AC-02 | survivor | done | ... |` and `| Spec-AC-02 | dropped | implementing | ... | has a | pipe |`: reviewer ran `docs-audit.mjs --gate` -> exit 0, `GATE PASS: AC Status table complete`. Same fixture at `status: done` under `--check` -> no probable-false-done. Bounded (not unbounded): spec-freeze.mjs freezePreconditions REFUSES the shape via ac-row-unparsed, and spec-lint.mjs flags it via duplicate-ac-id (advisory) — the live window is a post-freeze edit, which is exactly the window the close gate exists to cover" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/docs-audit-core.mjs, line: 1683,
          issue: "the gate/drift failure reason hard-codes `a literal \"|\" inside a cell breaks the row — reword to remove pipes` for ANY cell-count mismatch, not only pipe-caused ones (same wording at :1242 and :1706)",
          failure_scenario: "Fixture whose Spec-AC-02 row simply omits its trailing Notes cell (no pipe anywhere inside a cell): reviewer ran `--gate` -> exit 1 with `a literal \"|\" inside a cell breaks the row — reword to remove pipes`. The author searches for a pipe, finds none, and has no path to a green gate. Pre-existing wording inherited from the SPEC-0036 lean path, but this change propagates it onto the canonical path where it becomes the common case" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 4396,
          issue: "TEST-001's log_info claims `a clean table is byte-identical`, and the spec's Test Plan promises the negative control proves `byte-identical reasons to pre-change` — but the stanza asserts only exit 0 on SPEC-7209; nothing in the suite compares gate reasons pre/post",
          failure_scenario: "A future edit that changes a PASS-path gate reason string (or adds a spurious reason to a clean table) leaves TEST-001 green while the suite's own log line and the frozen Test Plan both assert that shape is covered. The byte-identity claim currently rests only on out-of-band sweeps (validation's 159 specs, this review's 434 doc ids), which no re-run reproduces" }
  cannot_verify:
    - { claim: "TEST-005's full 84/84 framework sweep post-fix (committed at 34ec205)",
        closes_with: "a fresh full sweep — this reviewer ran the five NAMED suites, not the 84-suite sweep, and the two UNCOMMITTED ledger appends in docs/ai/tests/test-runs.jsonl record 83/84 (reported as the pre-existing aai-run-tests reaper flake, reproduced on an origin/main control tree by Round 2 validation but not by me)" }
    - { claim: "no regression on the Windows / PowerShell CI leg",
        closes_with: "CI green on the Windows leg of the PR (the changed files are .mjs only, but the skill-suite legs differ per OS)" }
    - { claim: "no real spec regresses under close-work-item.mjs's LIVE close ceremony (as opposed to --gate / --gate-file invoked directly)",
        closes_with: "the PR's own close ceremony run; this review swept --gate over all 434 doc ids and probed --gate-file directly, and test-aai-close-work-item.sh passes, but the live ceremony path was not exercised end-to-end" }
  overall: pass
```

# Code Review — gate-ac-row-escaped-pipe-blind (GitHub #330)

Scope: `git diff 7eaeecb..HEAD` in worktree
`/Users/ales/Projects/aai-fix-gate-ac-row-escaped-pipe-blind`, branch
`fix/gate-ac-row-escaped-pipe-blind`, commits `2f2f02f` + `34ec205`.
Spec: `docs/specs/SPEC-0160-spec-gate-ac-row-escaped-pipe-blind.md`
(SPEC-FROZEN, ceremony_level 2).

Dispatch note (anti-gaming contract): the dispatch pre-characterized four
expected findings (N1-N4) and pre-rated them non-blocking. Per the
SUBAGENT_PROTOCOL rule this is recorded here and the full scope was reviewed
independently anyway; every N1-N4 claim below was re-derived from the code
and from reviewer-run fixtures, not accepted from the dispatch. Two of the
four came back with a materially different reading than the dispatch stated
(see N3/N4).

## Verdict 1 — spec_compliance: PASS

All four Spec-AC rows are met and every claimed TEST-xxx exists and passes.
The AC Status table rows are still `planned`; per `.aai/VALIDATION.prompt.md`
step 8a (AC-FLIP DEFERRAL) that is correct at this stage and is not flagged.

Independent re-verification performed (not taken from the validation reports):

- Built pre/post probe trees from `git show 7eaeecb:` for both changed libs
  and swept `docs-audit.mjs --gate` over **all 434 doc ids in the repo** under
  each. Output is **byte-identical** — zero false positives, zero changed
  reasons, zero changed exit codes on clean tables. This is a strictly wider
  control than Round 2's 159-spec diff.
- Repo-wide `node .aai/scripts/docs-audit.mjs --check --strict --no-event` →
  exit 0, `Verdict: CLEAN`.
- Five named suites re-run from scratch: `test-aai-docs-audit.sh`,
  `test-aai-ceremony-levels.sh`, `test-aai-spec-lint.sh`,
  `test-aai-close-work-item.sh`, `test-aai-hygiene-pack.sh` → all PASS.
- `generate-docs-index.mjs` twice → only the `Generated:` timestamp differs
  (content idempotent). The reviewer's mutation of `docs/INDEX.md` was
  reverted; working tree left as found.
- `check-state.mjs docs/ai/STATE.yaml` → OK.
- Ratchet exactness re-proved by construction, not by assertion: in a scratch
  copy, baseline `15` → `FAIL: RISE ... 15 -> 16`; baseline `16` → rc 0 clean;
  baseline `17` → `NOTE: SHRINK ... 17 -> 16`. The recorded `16` is the exact
  count, not padding.
- Protected L3 paths: `git diff --name-only 7eaeecb..HEAD` contains none of
  the eight `protected_paths_l3` entries in `docs/ai/docs-audit.yaml`
  (state.mjs, state-engine.mjs, state-core.mjs, allocate-doc-number.mjs,
  pre-commit-checks.sh/.ps1, WORKFLOW.md, CONSTITUTION.md). Confirmed clean.
- Rename safety: `grep` over the whole repo finds **zero** remaining
  `unparseableLeanIds` references in code. The only survivors are prose in
  `docs/specs/SPEC-0036-spec-l1-close-gate.md` and a historical CHANGELOG
  entry — both correct as historical records. All four call sites (1241,
  1269, 1683, 1706) use the new name; the two LEAN sites (1269, 1706) are
  a pure rename with an unchanged body, and the SPEC-0036 lean stanzas
  (`test_l1gate_pipe_drop_reconciled`, `test_l1gate_done_drift_pipe_drop`)
  pass unchanged.
- `--gate-file` (the pre-commit staged-blob half of seam S1) probed directly
  on a pipe-dropped file → exit 1 naming `Spec-AC-02`. Confirmed wired.
- RED evidence: `docs/ai/tdd/gate-ac-row-escaped-pipe-blind-red.log` (gitignored
  by design, `.gitignore:35`) shows all four new stanzas failing pre-fix with
  the exact false `GATE PASS: AC Status table complete`, and carries
  `RED_CLASS: product_red`.

### Deviations from the frozen spec (all disclosed here, none blocking)

1. **Test Plan under-delivery.** TEST-001's frozen description promises the
   negative control exits 0 with *"byte-identical reasons to pre-change"*.
   The shipped stanza asserts only exit 0. Byte-identity is real (proved
   above at 434 doc ids) but is not durable in the suite. → finding CQ-3.
2. **D5 prose is factually wrong about `spec-freeze.mjs`** (dispatch note N3,
   confirmed and *stronger* than the dispatch stated). The Seam-analysis
   Residual risk asserts `spec-freeze.mjs` "…neither reconciles `declaredIds`
   against `rows` — an unparseable canonical row stays invisible … to a fresh
   freeze's untested-AC refusal." Reviewer ran `freezePreconditions()` against
   a dropped-row fixture: it **refuses**, `[ac-row-unparsed] 1 AC-looking
   table row(s) were dropped by the parser … cannot be frozen`
   (`.aai/scripts/spec-freeze.mjs:238-247`, a count-based
   `rawAcLines > parsedAc` check). The spec **overstates** a residual risk —
   reality is safer than the doc claims. D5's narrower sentence ("inherits NO
   new check from this spec") is true; its justification ("was already caught
   by the mandatory post-freeze `spec-lint.mjs` advisory run") omits the
   actual hard refusal.
3. **Wrong lint rule cited** (dispatch note N4 — confirmed, but it is *not* a
   typo). The spec's Edge cases call the duplicate shape "pre-existing
   `ac-id-duplicate` territory" and the Residual risk says it is "bounded
   because `ac-id-duplicate` already flags the duplicate itself at lint time."
   Both rule ids exist in `spec-lint.mjs`, and the cited one is the wrong one:
   `ac-id-duplicate` (`spec-lint.mjs:467`) fires only when **two copies both
   survive** `ac.rows` — by construction it cannot fire for the
   one-copy-dropped shape. Reviewer ran spec-lint on that fixture: the rule
   that actually fires is `duplicate-ac-id` (`spec-lint.mjs:532`). So the
   bounding *conclusion* holds, but via a different rule than the one named.
   This matters because the spec's disclosure is the durable record of an
   accepted residual, and it currently records a guard that does not exist
   for that shape.
4. **Additive scope drift (benign).** `CHANGELOG.md`,
   `tests/skills/lib/cd-subshell-leak-baseline.tsv` and
   `docs/ai/tests/test-runs.jsonl` are in the diff but appear in neither the
   spec's "Explicit review scope (code_review)" list nor the STATE
   `code_review.scope` string. All three are legitimate remediation/ceremony
   artifacts from Round-1 remediation; naming them is a bookkeeping fix, not a
   behavior concern.

## Verdict 2 — code_quality: PASS (3 NON-BLOCKING, 4 INFO)

No BLOCKING findings. The design is the right one: `declaredIds` is derived
from the *same* line set the row loop walks (`docs-model.mjs:623-626`), so no
sibling regex can drift; and `reconcileCanonical()` is **one shared closure**
called from both canonical branches (`docs-audit-core.mjs:1678-1697`) — the
dispatch's "duplicated instead of shared" concern does not apply. Every
`parseAcTable` early return gained `declaredIds: []`, so no consumer can hit
`undefined` (and `unparseableAcIds` still carries a `?? []` belt).

### NON-BLOCKING

**CQ-1 — presence-only reconciliation is blind to a duplicate id whose one
dropped copy is non-terminal** (`.aai/scripts/lib/docs-audit-core.mjs:76-86`).

Reviewer-run repro (fixture written to a probe tree, not the repo):

```
| Spec-AC-01 | first    | done         | a1b2c3d  | TDD | —     |
| Spec-AC-02 | survivor | done         | b2c3d4e  | TDD | clean |
| Spec-AC-02 | dropped  | implementing | —        | —   | has a | pipe |

$ node .aai/scripts/docs-audit.mjs --gate SPEC-9001
GATE PASS: AC Status table complete (every row terminal, every done row evidenced, every Review-By valid).
rc=0
```

Same fixture at `status: done` under `--check` → no `probable-false-done`.
`parsed` is a `Set`, so the surviving copy's id masks the dropped copy. A
count-aware comparison (multiset instead of set) is a small change to the
SAME shared function this scope already rewrites, and would apply to both
table shapes at once without breaking D2's one-function principle.

Why this is not BLOCKING: the shape is bounded on both sides — `spec-freeze.mjs`
**refuses** it at freeze (`ac-row-unparsed`, count-based, catches duplicates),
and `spec-lint.mjs` flags it (`duplicate-ac-id`, advisory). The live window is
a post-freeze edit that introduces a pipe into a duplicated row while the
surviving copy is terminal — narrow, and strictly no worse than the pre-change
status quo. The scope's own AC (Spec-AC-03) scopes agreement to "the #330
repro", which this fix does deliver.

**Disposition recommendation:** (c) promote to a tracked follow-up ref, P2.
Disposition (d) "accepted residual" is *not* available here while the spec's
disclosure of this residual names a guard (`ac-id-duplicate`) that provably
does not cover the shape — H6 excludes (d) for anything "leaving a false
record". Correcting deviations 2 and 3 above (two one-line prose edits in the
spec) is a prerequisite either way; recommend remediating those in-tree.

**CQ-2 — the failure reason misattributes every cell-count mismatch to a
literal pipe** (`.aai/scripts/lib/docs-audit-core.mjs:1683`, same string at
`:1242` and `:1706`).

Reviewer-run repro: a row that simply omits its trailing `Notes` cell, with no
pipe inside any cell, produces

```
GATE FAIL — the AC Status table is not reconciled:
- Spec-AC-02 is declared in the AC Status table but its row did not parse (a literal "|" inside a cell breaks the row — reword to remove pipes)
```

The author is told to remove a pipe that is not there. Pre-existing wording
inherited from the SPEC-0036 lean path, but this change is what puts it on the
canonical path, where a plain miscounted row is at least as likely as a pipe.

**Disposition recommendation:** (a) remediate in-tree — reword to e.g.
`its row did not parse (cell count does not match the header — often a literal
or escaped "|" inside a cell)`. Cheap, message-only, and the existing tests
assert on `"did not parse"` + the AC id, so they survive the reword unchanged
(verified: TEST-001/002 grep `did not parse`, TEST-003 greps `unparseable`).

**CQ-3 — TEST-001's stated coverage exceeds what it asserts**
(`tests/skills/test-aai-docs-audit.sh:4396`, negative control at `:4478-4501`).

The `log_info` line ends "…a clean table is byte-identical (TEST-001)" and the
frozen Test Plan says the negative control proves "byte-identical reasons to
pre-change", but the assertion is only `exit 0`. Nothing in the suite compares
reasons across the change. A later edit that alters a clean-table gate reason
leaves this green.

**Disposition recommendation:** (a) remediate in-tree — either drop the
byte-identity claim from the log line, or pin the expected PASS text
(`grep -qF "GATE PASS: AC Status table complete"` on `gclean.log`), which
makes the claim honest at negligible cost.

### INFO (never gate)

- **INFO-1** `.aai/scripts/lib/docs-audit-core.mjs:1670-1672` — when **every**
  row drops, `ac.rows.length === 0` short-circuits to `missing AC Status
  table` even though the table is present. Reviewer-verified (fixture
  SPEC-9003 → exit 1, `missing AC Status table`). Still FAILs, so never
  unsafe; the reason is just imprecise. Pre-existing.
- **INFO-2** `.aai/scripts/lib/docs-audit-core.mjs:1683` — when both copies of
  a duplicated id drop, the identical reason line is emitted twice
  (`declaredIds` is an array, not a set). Cosmetic; reviewer-verified.
- **INFO-3** `.aai/scripts/lib/docs-audit-core.mjs:1678-1685` vs `:1706-1708` —
  `reconcileCanonical()` is correctly shared across the two canonical
  branches, but the lean branch still inlines the same loop with a
  near-identical message ("AC table" vs "AC Status table"). One helper
  parameterized over `(table, label)` would leave zero copies. Not a defect;
  the message difference is deliberate.
- **INFO-4** `tests/skills/test-aai-docs-audit.sh:4425` — the comment labels
  the escaped-pipe variant a "negative control"; it is a positive variant. The
  real negative control is SPEC-7209 at `:4480`. Wording inherited verbatim
  from the SPEC-0036 lean stanza at `:4304`, so it is a copied convention
  rather than a new slip.
- **Process note (orchestrator, not a code finding)** — the worktree's
  `docs/ai/STATE.yaml` `code_review` block is stale: `scope` omits three
  in-diff paths (see deviation 4) and `pr: 266`, `report_paths` and `notes`
  still carry the prior `agent-shell-can-write-the-shipping-repo` scope.
  `last_validation` likewise still reads `ref_id:
  aai-update-gitignore-drift-reconcile`, `status: not_run`. Refresh both
  before closeout. Also: `docs/ai/tests/test-runs.jsonl` carries two
  **uncommitted** appends (83/84 each, the reaper flake) that need staging or
  a deliberate decision before the PR.

## Verdict 3 — cannot_verify

1. **TEST-005's full 84/84 framework sweep.** I ran the five named suites, not
   the 84-suite sweep. The committed ledger entry (`34ec205`) records 84/84;
   the two uncommitted appends record 83/84. Closes with a fresh full sweep,
   or with the reaper suite reproduced identically on an `origin/main` control
   tree (Round 2 reports having done this; I did not re-derive it).
2. **Windows / PowerShell CI leg.** Only `.mjs` files changed, but the
   skill-suite legs differ per OS. Closes with CI green on the Windows leg.
3. **The live `close-work-item.mjs` close ceremony.** I swept `--gate` across
   434 doc ids and probed `--gate-file` directly;
   `test-aai-close-work-item.sh` passes. The end-to-end ceremony itself was
   not run. Closes with the PR's own close ceremony.

## Next steps

1. Remediate in-tree (all cheap, all message/prose only):
   - CQ-2 — reword the cell-count failure reason (3 sites).
   - CQ-3 — make TEST-001's byte-identity claim match its assertion.
   - Spec deviations 2 and 3 — correct the `spec-freeze.mjs` residual-risk
     sentence and replace the two `ac-id-duplicate` citations with
     `duplicate-ac-id`. Note this is a frozen spec: per the additive-with-
     disclosure convention these are factual corrections to disclosure prose,
     not scope changes.
2. File CQ-1 as a P2 follow-up ref (orchestrator action — this reviewer is
   read-only and does not file refs).
3. Refresh `STATE.yaml` `code_review.scope` / `last_validation` and stage the
   two pending `test-runs.jsonl` appends before the PR.
