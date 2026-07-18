---
id: spec-deterministic-close-ceremony
type: spec
number: 53
status: done
ceremony_level: 2
links:
  change: deterministic-close-ceremony
  rfc: null
  pr:
    - 105
  commits:
    - 4bb6d81
---

# SPEC — Deterministic close-ceremony mechanism (`close-work-item.mjs`)

SPEC-FROZEN: true

## Links
- Change: deterministic-close-ceremony
  (docs/issues/CHANGE-0037-deterministic-close-ceremony.md)
- Canonical close prose being mechanized: `.aai/VALIDATION.prompt.md` steps
  8a/8b (done-flip + `work_item_closed`/`ac_evidence` emission) and
  `.aai/SKILL_PR.prompt.md` (links.pr stamping).
- Audit heuristics this must satisfy: `.aai/scripts/lib/docs-audit-core.mjs`
  (`falseOpenEvidence`, the `status === 'done'` false-done branch,
  `missing-close-telemetry`).
- Event emitter reused verbatim: `.aai/scripts/append-event.mjs`.
- Precedent helper-script shape (closed exit contract, stdlib-only, bash test
  suite): SPEC-0045 (`.aai/scripts/secrets-preflight.mjs`).
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation (SPEC-FROZEN: true), work not started
- implementing: work in flight
- done: all Spec-AC terminal; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Ceremony level
`ceremony_level: 2` — full pipeline. Honestly considered L1 (the dispatch
invitation) and rejected:
1. NOT single-surface: the scope adds one NEW governance-critical executable
   (`.aai/scripts/close-work-item.mjs`), edits TWO canonical workflow prompts
   (`.aai/VALIDATION.prompt.md`, `.aai/SKILL_PR.prompt.md`), and adds one NEW
   bash test suite — three distinct surface classes, beyond the WORKFLOW.md L1
   "small single-surface fix" definition.
2. Governance-integrity class: the script MUTATES committed doc frontmatter
   (status flips), APPENDS to the shared committed audit log
   (docs/ai/EVENTS.jsonl), and its correctness property (emit the ref form the
   audit matches) is exactly the failure class the change exists to remove. A
   mis-close silently misrepresents project state. That warrants L2's full
   independent validation and mandatory review, not the L1 declared-scope lane.
It touches NO `protected_paths_l3` entry — verified against
docs/ai/docs-audit.yaml (the list is state.mjs, state-engine, state-core,
allocate-doc-number, pre-commit-checks.sh/.ps1, WORKFLOW.md, CONSTITUTION.md;
the NEW close script is not on it and only CALLS append-event.mjs /
docs-audit.mjs / generate-docs-index.mjs, none of which are protected). So L3
is not forced.

## Problem statement (verified facts)
1. The close ceremony is 100% agent-improvised (verified 2026-07-18: no
   `.aai/scripts/close-work-item.mjs` exists; the ceremony lives as prose in
   `.aai/VALIDATION.prompt.md` step 8a/8b and `.aai/SKILL_PR.prompt.md`).
2. THE CRUX — ref form. The audit computes a doc's identity as
   `id = fm.id ?? ids.primary` (docs-audit-core.mjs, scan loop). Every doc in
   this repo carries a frontmatter slug `id` (e.g. `intake-secrets-preflight`),
   so the audit matches close events on the SLUG, never on the numbered
   filename id (`CHANGE-0034`). The heuristics that consume it:
   - `missing-close-telemetry` (done doc): fires unless a `work_item_closed`
     event has `ref === fm.id` (slug) or `ref.startsWith(fm.id + '/')`.
   - false-done, no-gate non-spec doc (change/issue/debt): fires unless a
     commit mentions the slug OR an `ac_evidence` event has `ref === fm.id`
     (slug) / rolls up to it. A change doc's own commits reference the NUMBERED
     id, not the slug, so the bare-slug `ac_evidence` event is what clears it.
   - `probable-false-open` (still-open doc): `work_item_closed` matching EITHER
     the slug OR the numbered fileId trips it (Arm C, unconditional). Therefore
     the status MUST be flipped to `done` BEFORE any close event is emitted —
     emitting `work_item_closed` against a still-open doc self-flags it. This is
     the exact tension VALIDATION.prompt.md line 149 documents.
3. GOLDEN REFERENCE (the CHANGE-0034 + SPEC-0045 pair that audits CLEAN today,
   docs/ai/EVENTS.jsonl lines 612–617; audit `--list` shows both `tracked-done`
   / `aligned`). The close event set that produced CLEAN:
   - change doc (slug `intake-secrets-preflight`):
     `doc_lifecycle implementing→done` (ref = slug),
     `work_item_closed` (ref = slug, validation pass, code_review pass),
     `ac_evidence` (ref = slug — BARE, commit `cea19d7`).
   - spec doc (slug `spec-intake-secrets-preflight`):
     `doc_lifecycle draft→done` (ref = slug),
     `work_item_closed` (ref = slug, validation pass, code_review pass).
   The pair ALSO shows the improvisation defect this change removes: TWO
   conflicting `doc_lifecycle` for the change (line 612 `implementing→done` and
   line 614 `draft→done`) — the agent guessed the `from` status twice because
   nothing read the ACTUAL current status.
4. Recurring failure modes (CHANGE-0037 Motivation), all silent-until-audit:
   - status-flip miss — flipping `draft→done` on an actually-`implementing`
     doc is a no-op; the doc stays open, trips `probable-false-open`
     (SPEC-0046).
   - ref-form mismatch — numbered `work_item_closed`/`ac_evidence` leaves the
     audit unable to match, flags `probable-false-done` (CHANGE-0027/0035).
   - incomplete event set — forgetting the spec's events while doing the
     change's.
5. docs/TECHNOLOGY.md: Node stdlib only, plain `node` invocation, no YAML
   library in-repo. The script is stdlib-only and deterministic.
6. No docs/canonical/ layer exists → no `## Deltas` section applies (this spec
   changes no canonical REQ; it mechanizes workflow prose).

## Design decisions

- D1 (CLI grammar): NEW `.aai/scripts/close-work-item.mjs` (Node stdlib only,
  plain `node`). Closed grammar:
  `node .aai/scripts/close-work-item.mjs --ref <slug> --pr <N> --commit <sha>
  [--spec <spec-slug>] [--review <pass|waived|none>] [--dry-run]`
  - `--ref <slug>` — the primary work-item doc's frontmatter slug `id`
    (change/issue/debt/spec). Required.
  - `--pr <N>` — PR number stamped into `links.pr` (integer; required).
  - `--commit <sha>` — delivery commit stamped into `links.commits` AND used as
    the `ac_evidence` commit (required).
  - `--spec <spec-slug>` — optional second doc (the spec) closed in the SAME
    transaction as the primary doc.
  - `--review <pass|waived|none>` — the `code_review` token for
    `work_item_closed`; optional, default `none` (validation is always `pass` —
    the close ceremony only runs after a PASS).
  - `--dry-run` — print the planned mutations + event set as JSON, write
    nothing, exit 0.

- D2 (doc resolution — reuse, no fork): resolve each `--ref`/`--spec` slug to
  exactly one scanned doc via the SAME two-pass resolver the audit exposes —
  `gateDoc`-style (docs-audit-core `scanAuditDocs` + frontmatter `id` match,
  then filename-id fallback). More than one match, or zero matches, is a fatal
  usage error (exit 2) naming the candidates — fail-closed, never guess (mirrors
  gateDoc's ambiguity guard). The resolved `fm.id` (the slug) is the ref used
  for EVERY emitted event (D5). This is the crux correctness property.

- D3 (read ACTUAL status; transition from it): read each doc's CURRENT
  `fm.status`. Transition rule (fixes AC-001 / SPEC-0046 status-flip miss):
  - `draft | implementing | accepted` → rewrite frontmatter `status: done` and
    emit `doc_lifecycle --from <ACTUAL> --to done`.
  - already `done` → NO status rewrite, NO `doc_lifecycle` (idempotent).
  - any other status (`deferred|rejected|superseded`) → fatal usage error
    (exit 2): the close ceremony does not silently reopen/repurpose a terminal
    non-done doc.
  The `from` is ALWAYS the value read off disk — never assumed.

- D4 (stamp links — append + dedupe): in the SAME frontmatter edit, ensure
  `links.pr` contains `<N>` and `links.commits` contains `<sha>` (append if
  absent, no duplicate). Line-surgical edit of the YAML frontmatter block only
  (the doc body is byte-untouched). If `links` / `links.pr` / `links.commits`
  keys are absent, they are created in the frontmatter.

- D5 (the FROZEN event set + ref form — reuse append-event.mjs, no forked
  schema). For EACH closed doc, using the doc's resolved SLUG `id` as `--ref`
  (bare, never the numbered fileId), emit via `append-event.mjs`, best-effort
  ordering AFTER the status flip:
  1. `doc_lifecycle --ref <slug> --from <ACTUAL> --to done` — ONLY when a real
     transition happened (skipped if already done).
  2. `work_item_closed --ref <slug> --validation pass --code-review <token>` —
     clears `missing-close-telemetry`; skipped if an existing `work_item_closed`
     event already has `ref === slug` (dedupe).
  3. `ac_evidence --ref <slug> --commit <sha>` — clears the no-gate false-done
     branch for the primary (change/issue/debt) doc; emitted for the spec too
     for symmetry (harmless — the spec's false-done is AC-table-based). Skipped
     if an existing `ac_evidence` event already has `ref === slug` AND
     `payload.commit === sha` (dedupe).
  RATIONALE for bare-slug (not `slug/Spec-AC-NN`): the primary-doc false-done
  guard matches `ref === id` OR `ref.startsWith(id + '/')`; the bare slug
  satisfies both the guard and `missing-close-telemetry`. Per-Spec-AC
  numbered `ac_evidence` (`SPEC-NNNN/Spec-AC-NN`) remain VALIDATION's job
  (step 8a) — the close script does NOT emit or touch those.

- D6 (ORDERING is status-flip-FIRST, then events, then self-verify; fail-closed
  by total rollback). The close is a single synchronous transaction:
  1. SNAPSHOT: record the byte-length of docs/ai/EVENTS.jsonl and the full
     original content of each doc file to be mutated.
  2. Idempotency short-circuit: if every planned mutation is already present
     (status already `done`, `links.pr`/`links.commits` already carry the
     values, and the `work_item_closed`/`ac_evidence` events already exist for
     each ref) → emit NOTHING, write NOTHING, regenerate INDEX, run the audit,
     assert CLEAN, exit 0.
  3. APPLY: rewrite frontmatter (status flip + links stamp) for each doc; then
     append the D5 event set for each doc.
  4. SELF-VERIFY: regenerate the INDEX
     (`node .aai/scripts/generate-docs-index.mjs`), then run the FULL audit
     (`runAudit(root, {})` / `docs-audit.mjs --check`). Assert CLEAN for the
     closed refs: each closed ref classifies `tracked-done` with verdict
     `aligned` (NO `probable-false-done` / `probable-false-open` /
     `probable-partial`), and no `missing-close-telemetry` entry names it.
  5. FAIL-CLOSED: if the assert fails, RESTORE every mutated doc file to its
     snapshot content, TRUNCATE docs/ai/EVENTS.jsonl back to the snapshot
     byte-length, regenerate the INDEX again (revert), print the audit
     reason(s) for the offending ref, and exit non-zero. No half-closed doc is
     ever left on disk (AC-004). The REAL audit engine is the oracle — the
     script does not re-implement the heuristics (no divergence risk).
  6. `--dry-run` stops after step 2's plan computation and prints the plan JSON.

- D7 (pair atomicity — AC-003): with `--spec`, BOTH docs are resolved up front;
  if EITHER cannot be resolved/transitioned the script exits 2 before any write.
  The self-verify (D6.4) covers BOTH refs; a failure rolls BOTH back. The pair
  is never half-closed.

- D8 (idempotent + non-blocking exit contract — AC-004):
  - exit 0 = closed successfully OR nothing to do (already fully closed).
  - exit 1 = self-verify failed (audit not CLEAN after close) — rolled back,
    finding printed. Also unexpected internal error (top-level try/catch).
  - exit 2 = usage error (missing/invalid flag, unresolvable/ambiguous ref,
    non-done terminal status) — nothing written.

- D9 (wiring the ceremony — AC-005). The prose STOPS instructing hand-editing
  frontmatter / hand-emitting close events:
  - `.aai/SKILL_PR.prompt.md`: add an explicit close step AFTER the PR is
    opened (PR number + head commit now known): `node
    .aai/scripts/close-work-item.mjs --ref <slug> --pr <N> --commit <sha>
    [--spec <spec-slug>] --review <pass|waived|none>`. Merge boundary
    unchanged (the agent still never merges).
  - `.aai/VALIDATION.prompt.md` step 8b: the manual "write `status: done` into
    frontmatter" + manual `append-event --event work_item_closed`/`ac_evidence`
    lines are REPLACED by a pointer that the deterministic close (frontmatter
    flip + close event set) is performed by `close-work-item.mjs` at the
    PR/close step. The CLOSE GATE (`docs-audit.mjs --gate`) and AC-STATUS-GATE
    pre-checks STAY in validation (they gate the PASS verdict); the done-flip
    itself moves to the script. Byte-lean edits (no new prose beyond the
    pointer + the invocation line).

- D10 (single-writer assumption, recorded): the fail-closed rollback truncates
  EVENTS.jsonl to a snapshot length, which is safe only because the close step
  runs at a serialized point (post-PR, one work item) with no concurrent
  EVENTS writer. Recorded as R1; the AAI close flow is single-writer by
  construction (the loop dispatches one close at a time).

## Implementation strategy
- Strategy: hybrid
- Rationale: the script is governance-integrity new behavior with hard
  correctness properties (ref form, status-flip-from-actual, idempotency,
  fail-closed rollback) — TEST-001..007 get per-test RED-GREEN discipline, the
  fail-closed and status-flip-miss tests written and observed RED first
  (they encode the exact incident classes). The prose wiring (D9,
  VALIDATION/SKILL_PR edits) is mechanical line-editing where loop
  implementation suffices; its grep-wired test (TEST-008) satisfies the
  RED-proof obligation by being observed failing against the unedited prompts.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: additive scope — one new script, one new test suite, lean
  edits to two workflow prompts; no protected_paths_l3 paths, no migrations, no
  cross-cutting refactor. The operator has ALREADY recorded `user_decision:
  inline` for this workflow-hardening wave ("operator-approved
  workflow-hardening wave: inline on feat/deterministic-close-ceremony" in
  STATE); Planning does not override that recorded decision.
- User decision: inline (pre-recorded by operator)
- Base ref: main
- Inline review scope: see Code review scope below.
- Code review required: true (NEW governance-critical executable that mutates
  committed doc frontmatter + appends to the shared committed EVENTS log +
  workflow-prompt changes + a new test suite).
- Code review scope (explicit paths):
  `.aai/scripts/close-work-item.mjs`, `.aai/VALIDATION.prompt.md`,
  `.aai/SKILL_PR.prompt.md`, `tests/skills/test-aai-close-work-item.sh`,
  `docs/specs/SPEC-0053-spec-deterministic-close-ceremony.md`,
  `docs/issues/CHANGE-0037-deterministic-close-ceremony.md`, `docs/INDEX.md`

## Acceptance Criteria Mapping
- Maps to: CHANGE-0037 AC-001 (status flip from ACTUAL value)
  - Spec-AC-01: `close-work-item.mjs` reads each target doc's ACTUAL current
    `fm.status` and transitions `draft|implementing|accepted → done`, emitting
    `doc_lifecycle --from <ACTUAL> --to done`; an already-`implementing` doc is
    closed correctly (the SPEC-0046 flip-miss cannot recur) and a
    non-done-terminal status (`deferred|rejected|superseded`) is a usage error
    (exit 2), never a silent reopen.
  - Verification: TEST-001 (draft-close), TEST-002 (implementing-close =
    SPEC-0046 regression), TEST-003 (non-done-terminal → exit 2).
- Maps to: CHANGE-0037 AC-002 (slug ref form; audit CLEAN)
  - Spec-AC-02: EVERY emitted close event uses the doc's bare SLUG `id` as
    `--ref` (never the numbered fileId); after a close a FULL `docs-audit` is
    CLEAN for the closed ref(s) — no `probable-false-done` / `probable-false-open`
    / `missing-close-telemetry` (the CHANGE-0027/0035 ref-mismatch cannot
    recur). The event set matches the golden reference: `doc_lifecycle`,
    `work_item_closed`, bare-slug `ac_evidence`.
  - Verification: TEST-004 (event-ref assertion + real audit CLEAN over the
    closed ref — the seam test).
- Maps to: CHANGE-0037 AC-003 (change+spec pair, never half-closed)
  - Spec-AC-03: with `--spec`, BOTH docs flip to done and BOTH receive the
    complete slug-reffed event set in one transaction; if either doc cannot be
    resolved/closed the script writes nothing and exits 2; a self-verify failure
    rolls BOTH back.
  - Verification: TEST-005 (pair close: both done + both event sets + audit
    CLEAN), TEST-006 (pair pre-write abort: unresolvable spec → exit 2, primary
    doc untouched).
- Maps to: CHANGE-0037 AC-004 (idempotent + fail-closed)
  - Spec-AC-04: re-running on an already-closed item appends ZERO new
    events, adds ZERO duplicate links, and exits 0; when the post-close audit is
    NOT CLEAN the script exits non-zero, NAMES the finding, and leaves every
    target doc byte-identical to its pre-run content (status not flipped, no
    events appended — EVENTS.jsonl byte-length unchanged).
  - Verification: TEST-007 (idempotent re-run: 0 new events/links, exit 0),
    TEST-008 (fail-closed: a spec rigged with a non-terminal AC row → exit 1,
    doc + EVENTS.jsonl byte-identical to pre-run).
- Maps to: CHANGE-0037 AC-005 (canonical flow references the script)
  - Spec-AC-05: `.aai/SKILL_PR.prompt.md` carries the
    `node .aai/scripts/close-work-item.mjs ...` close step, and
    `.aai/VALIDATION.prompt.md` step 8b no longer instructs hand-editing
    frontmatter to `done` nor hand-emitting `work_item_closed`/close
    `ac_evidence` (it points to the script); repo-wide
    `node .aai/scripts/docs-audit.mjs --check --strict --no-event` stays exit 0.
  - Verification: TEST-009 (canon grep contract: SKILL_PR names the script;
    VALIDATION 8b no longer carries the hand-flip/hand-emit lines; strict audit
    exit 0).

## Constitution deviations

None.

(Checked at freeze against docs/CONSTITUTION.md: art. 1 — every AC verified by
executable bash fixtures that run the REAL script + REAL audit; art. 2 — scope
is exactly the close mechanism, no speculative flush/merge coupling (both
explicitly out of scope); art. 3 — plain stdlib-only script, git-diffable
prompt lines; art. 4 — unresolvable/ambiguous refs and non-done statuses fail
fast with named reasons, a not-CLEAN self-verify degrades to a reported
rollback rather than a silent half-close; art. 5 — additive at the prompt
boundary (a pointer replaces hand-steps; existing closed docs stay valid,
never re-processed); art. 6 — the script writes doc frontmatter + EVENTS only,
never STATE (STATE stays the state.mjs surface); art. 7 — merge boundary
untouched, the script never merges.)

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Status flip from ACTUAL value (draft/implementing/accepted→done); non-done-terminal → exit 2 | done | docs/ai/tdd/green-20260718T025153Z-close-work-item-test001-009.log (TEST-001/002/003); docs/ai/tdd/green-20260718T033346Z-close-work-item-test001-012.log (TEST-012) | — | fixes SPEC-0046 flip-miss; TEST-012 (code-review B3) adds the null-fmId pre-write usage-error guard |
| Spec-AC-02 | Every close event uses bare slug ref; post-close full audit CLEAN for the ref | done | docs/ai/tdd/green-20260718T025153Z-close-work-item-test001-009.log (TEST-004) | — | fixes CHANGE-0027/0035 ref mismatch |
| Spec-AC-03 | change+spec pair both close with complete event sets; never half-closed | done | docs/ai/tdd/green-20260718T025153Z-close-work-item-test001-009.log (TEST-005/006) | — | pair atomicity |
| Spec-AC-04 | Idempotent (0 new events/links, exit 0) + fail-closed (exit 1, doc+EVENTS byte-identical on rollback) | done | docs/ai/tdd/green-20260718T025153Z-close-work-item-test001-009.log (TEST-007/008); docs/ai/tdd/green-20260718T033346Z-close-work-item-test001-012.log (TEST-010) | — | hard requirement; TEST-010 (code-review B1, RED-proofed docs/ai/tdd/red-20260718T033229Z-close-work-item-b1-regen-failure-test010.log) closes the post-apply-INDEX-regen-failure rollback-bypass hole (regenerateIndex() now throws instead of process.exit(1), so the existing catch(err)@:491 rollback owner always runs) |
| Spec-AC-05 | SKILL_PR names the script; VALIDATION 8b drops hand-flip/hand-emit; strict audit exit 0 | done | docs/ai/tdd/green-20260718T025153Z-close-work-item-test001-009.log (TEST-009) | — | wiring |

## Implementation plan
Edit points:
1. `.aai/scripts/close-work-item.mjs` — NEW (~200 lines). argv parse per D1
   closed grammar; import `scanAuditDocs`/`runAudit` (or shell out to
   `docs-audit.mjs`) + reuse the `gateDoc` two-pass resolver from
   docs-audit-core.mjs for slug resolution (D2); read `fm.status` via the
   shared `parseFrontmatter` (docs-model.mjs) — NO new parser; frontmatter
   line-surgical edit for status + links (D3/D4); event emission by spawning
   `append-event.mjs` with bare-slug refs (D5); snapshot/apply/self-verify/
   rollback transaction (D6); pair atomicity (D7); exit contract (D8). Header
   comment carries the full contract (grammar, event set + ref form, ordering,
   fail-closed rollback) — SPEC-0045 precedent.
2. `.aai/SKILL_PR.prompt.md` — add the close-step invocation after step 5
   (PR opened), before the merge-boundary section (D9).
3. `.aai/VALIDATION.prompt.md` — edit step 8b: replace the hand-flip +
   hand-emit lines with the script pointer; keep the CLOSE GATE / AC-STATUS
   pre-checks (D9).
4. `tests/skills/test-aai-close-work-item.sh` — NEW bash-3.2-compatible suite
   (pattern: tests/skills/test-aai-secrets-preflight.sh; scratch fixture repo
   under a mktemp dir with docs/ + docs/ai/EVENTS.jsonl + docs/ai/docs-audit.yaml
   + a git init so the audit's git probes run; cleaned on EXIT; runnable via
   `.aai/scripts/aai-run-tests.sh` per the LEARNED wrapper rule).
Edge cases pinned: doc already `done` → no doc_lifecycle, no dup links, no dup
events, exit 0; `links.pr`/`links.commits` absent in frontmatter → created;
`--commit` sha already in links.commits → not duplicated; `--spec` omitted →
single-doc close; a non-done-terminal status → exit 2 with named reason; a
self-verify failure → total rollback (doc content + EVENTS byte-length
restored, INDEX regenerated).

## Seam analysis
- SEAM 1 (the crux): the close script's EMITTED event ref form ↔ the
  docs-audit heuristics that MATCH on `fm.id`. This is a produce-on-one-side /
  read-on-the-other seam. Crossed END-TO-END by TEST-004 and TEST-005: run the
  REAL `close-work-item.mjs`, then run the REAL `docs-audit.mjs`/`runAudit` and
  assert the closed ref classifies `tracked-done`/`aligned` with no false-done/
  false-open/missing-close-telemetry — NOT a mock of the audit. A ref-form
  regression (numbered instead of slug) makes the real audit flag drift and
  fails the test.
- SEAM 2: the script's frontmatter status write ↔ the audit's
  `probable-false-open` (which fires on a still-open doc carrying a
  `work_item_closed`). Crossed by TEST-002/TEST-004: the ORDER (flip-first) is
  asserted by verifying the closed doc is `tracked-done` (never
  `probable-false-open`) after a real close of an `implementing` doc.
- SEAM 3: the script's close event set ↔ VALIDATION's per-Spec-AC numbered
  `ac_evidence` (both write the shared EVENTS log). The division of labor
  (numbered per-AC = validation; bare-slug close set = script) is pinned by
  TEST-009 (VALIDATION 8b no longer emits the close set) and TEST-004 (the
  script emits exactly the bare-slug set).
- Residual seam risk (R2): whether the LIVE PR agent actually invokes the
  script (vs hand-improvising) is LLM behavior — the canon text (SKILL_PR)
  pins the duty and TEST-009 pins the text, but adherence is not mechanically
  forced (same accepted class as SPEC-0043/0044/0045 R1).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                          | Description                                                                                                   | Status  |
|----------|------------|-------------|-----------------------------------------------|---------------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-close-work-item.sh      | Draft-close: a `draft` change-doc fixture → close → frontmatter `status: done`, `doc_lifecycle from=draft to=done` (bare slug ref), exit 0 | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-close-work-item.sh      | Implementing-close (SPEC-0046 regression): an `implementing` fixture → close → `status: done`, `doc_lifecycle from=implementing to=done`; a later real audit shows `tracked-done`, NOT `probable-false-open` | green |
| TEST-003 | Spec-AC-01 | integration | tests/skills/test-aai-close-work-item.sh      | Non-done-terminal guard: a `deferred` (and a `superseded`) fixture → exit 2 with a named reason; doc untouched, no events appended | green |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-close-work-item.sh      | Ref-form + real-audit CLEAN (SEAM 1/2): close a no-gate change doc; assert the emitted `doc_lifecycle`/`work_item_closed`/`ac_evidence` all carry the bare slug ref, then run the REAL `docs-audit.mjs --list` and assert the ref is `tracked-done`/`aligned` with zero false-done/false-open/missing-close-telemetry | green |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-close-work-item.sh      | Pair close: `--ref <change> --spec <spec>` → BOTH docs `status: done`, BOTH carry `doc_lifecycle`+`work_item_closed`(+`ac_evidence` for change), real audit CLEAN for both refs | green |
| TEST-006 | Spec-AC-03 | integration | tests/skills/test-aai-close-work-item.sh      | Pair pre-write abort: `--spec` naming an unresolvable slug → exit 2; the primary change doc is byte-identical (no partial close), EVENTS.jsonl byte-length unchanged | green |
| TEST-007 | Spec-AC-04 | integration | tests/skills/test-aai-close-work-item.sh      | Idempotent re-run: run close twice; second run appends ZERO new EVENTS lines, adds no duplicate `links.pr`/`links.commits`, exits 0 | green |
| TEST-008 | Spec-AC-04 | integration | tests/skills/test-aai-close-work-item.sh      | Fail-closed: a spec fixture rigged with a non-terminal AC row so the post-close audit is NOT CLEAN → exit non-zero, finding named; the doc frontmatter and EVENTS.jsonl are byte-identical to their pre-run snapshots (total rollback) | green |
| TEST-009 | Spec-AC-05 | unit        | tests/skills/test-aai-close-work-item.sh      | Canon grep contract: `.aai/SKILL_PR.prompt.md` names `close-work-item.mjs`; `.aai/VALIDATION.prompt.md` step 8b no longer carries a hand `status: done` flip nor a hand `append-event --event work_item_closed` line; `docs-audit.mjs --check --strict --no-event` exits 0 — REDs on the unedited canon | green |
| TEST-010 | Spec-AC-04 | integration | tests/skills/test-aai-close-work-item.sh      | Code-review B1 regression: rig `docs/INDEX.md` so `generate-docs-index.mjs`'s own marker guard fails, making the POST-APPLY self-verify's INDEX regeneration fail → assert exit non-zero AND the doc frontmatter AND `EVENTS.jsonl` are byte-identical to their pre-run snapshot (the uncatchable `process.exit(1)` inside `regenerateIndex()` no longer bypasses `rollback()`) | green |
| TEST-011 | Spec-AC-04 | integration | tests/skills/test-aai-close-work-item.sh      | Code-review B2 regression: a doc whose `links.pr` is already an INLINE non-empty list (`pr: [42]`) is closed with a new `--pr 99` → the inline line is normalized to block form (no malformed mixed inline+block YAML), both values present, and a second (idempotent) close of the normalized doc round-trips without further mutation | green |
| TEST-012 | Spec-AC-01 | integration | tests/skills/test-aai-close-work-item.sh      | Code-review B3 regression: a doc resolved only via the display-id fallback (no frontmatter `id:` key, `fmId` null) is rejected with a clean, named, PRE-WRITE exit 2 — doc and `EVENTS.jsonl` byte-identical, no wasted apply/rollback cycle | green |

RED-proof: TEST-001..008 MUST be observed failing before the script exists (the
invocation fails with no such file). TEST-002 (SPEC-0046 flip-miss) and TEST-008
(fail-closed rollback) are written FIRST — they encode the exact incident
classes and must be RED against a naive draft→done / no-rollback implementation,
not merely against the missing file. TEST-009 MUST be observed failing against
the unedited SKILL_PR / VALIDATION prompts. TEST-010 (code-review B1) was
observed RED against the UNFIXED `process.exit(1)` code path
(`docs/ai/tdd/red-20260718T033229Z-close-work-item-b1-regen-failure-test010.log`,
`RED_CLASS: product_red`, `tdd-evidence-check.mjs` ACCEPTED) before the
`regenerateIndex()` throw-instead-of-exit fix landed.

## Verification
- `bash tests/skills/test-aai-close-work-item.sh` → exit 0 (TEST-001..012), run
  via `.aai/scripts/aai-run-tests.sh` per the LEARNED wrapper rule.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0
  (repo-wide regression; AC-005).
- Manual end-to-end dry run: `node .aai/scripts/close-work-item.mjs
  --ref <slug> --pr <N> --commit <sha> --spec <spec-slug> --dry-run` prints the
  planned mutation + event JSON without writing.
- `test-aai-prompt-diet.sh` TEST-010: `test-aai-prompt-diet.sh` TEST-010 PASSES
  on clean main (net reduction 29694 B, headroom 1022/2048) — it is NOT a
  pre-existing failure. The AC-005-mandated wiring prose this scope adds to
  `.aai/SKILL_PR.prompt.md` step 5c (+1144 B) and `.aai/VALIDATION.prompt.md`
  step 8b (+165 B) — a measured +1309 B corpus delta (325653 → 326962 B) —
  IS justified canon-mandated growth (Spec-AC-05 requires this prose), so it
  was trued up in the `JUSTIFIED_GROWTH_BYTES` ledger (DEBT-0002/SPEC-0048
  Spec-AC-01/02 contract) rather than absorbed as a gate exception: the ledger
  constant moved 6144 → 7453 (+1309, itemized ledger comment names this
  scope), restoring headroom to the same 1022 B baseline. `test-aai-worktree.sh`
  scratch-git fixture remains a known pre-existing failure (NOT a gate for
  this scope; unrelated to the changed paths).
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal with Evidence.

## Residual risks
- R1: the fail-closed rollback (EVENTS.jsonl truncation to a snapshot length)
  assumes a single EVENTS writer during the close (D10). The AAI close flow is
  single-writer by construction (one serialized close per work item); a
  concurrent external appender is out of the AAI model and out of scope.
- R2: whether the LIVE PR agent invokes the script (vs hand-improvising the
  close) is LLM behavior — pinned by SKILL_PR text (TEST-009) but not
  mechanically forced (accepted class, SPEC-0043/0044/0045 R1).
- R3: metrics-flush.mjs ALSO emits `doc_lifecycle`/`work_item_closed` (its
  `emitEvents`, hardcoded `implementing→done`, keyed on the STATE ref_id which
  may be the NUMBERED id). This is a SEPARATE, pre-existing surface (flush is
  explicitly out of scope, CHANGE-0037). Its numbered events are audit-inert
  once the doc is already `done` (false-open only fires on open docs; the close
  script flips first). Flagged as a follow-up to reconcile flush's event
  emission with the slug-ref contract — NOT fixed here to keep this scope
  single-surface.
- R4: the script shells out to `generate-docs-index.mjs` and `docs-audit.mjs`
  for self-verify; if a downstream repo lacks them (older vendored layer) the
  close cannot self-verify — the script must detect their absence and refuse
  (exit 1 with a clear message) rather than close blind (fail-closed posture).
  CLOSED by the code-review B1 remediation: `regenerateIndex()` now throws
  (instead of calling the uncatchable `process.exit(1)` directly) whenever
  `generate-docs-index.mjs` is absent OR errors, so a POST-APPLY self-verify
  failure on this exact R4 path always reaches the existing rollback owner
  (`catch(err)` in `main()`) before the process exits non-zero — TEST-010
  RED-proofs and covers it.

## Code-review remediation record (CHANGE-0037 / SPEC-0053, review-20260718T032459Z)
- B1 (BLOCKING, fail-closed hole): `regenerateIndex()` called the uncatchable
  `process.exit(1)` directly; when it ran from inside the post-apply
  `selfVerify()` (inside the try block whose `catch(err)` owns `rollback()`),
  the process terminated before `rollback()` ever ran, leaving a half-closed
  doc (status:done + stamped links + close events) on disk with exit 1.
  Fix-at-cause: `regenerateIndex()` now THROWS on both failure modes (missing
  generator, generator error) instead of exiting; the post-apply call site's
  throw now propagates to the existing `catch(err)`, which rolls back BEFORE
  exiting non-zero; the pre-write idempotency-short-circuit call site (nothing
  written that run) lets the throw reach the top-level try/catch, which
  already exits non-zero on any internal error — same D8 exit-1 contract via
  `throw` instead of a direct exit. Remediated in-tree; TEST-010 RED-proofed
  against the unfixed `process.exit(1)` path
  (`docs/ai/tdd/red-20260718T033229Z-close-work-item-b1-regen-failure-test010.log`)
  and GREEN after the fix
  (`docs/ai/tdd/green-20260718T033346Z-close-work-item-test001-012.log`).
- B2 (NON-BLOCKING, disposition: remediate-in-tree): `stampLink` appending a
  block list item after an INLINE non-empty list (`pr: [42]` then a spliced
  `    - 99`) produced malformed mixed inline+block YAML. Fix-at-cause:
  `locateLinksField` now reports `inlineNonEmpty`; `stampLink` normalizes the
  inline line to block form (carrying its already-parsed items) in the SAME
  splice that appends the new value, instead of leaving the inline line in
  place. Covered by TEST-011 (append + idempotent-re-run round-trip through
  the script's own reader).
- B3 (NON-BLOCKING, disposition: remediate-in-tree): a doc resolved by
  display-id with a null `fm.id` reached `applyDocMutation`/`emitEvent` before
  failing (fail-closed via rollback, but a wasted apply/rollback cycle and a
  generic "internal error" instead of a clean usage error). Fix-at-cause: a
  PRE-WRITE guard in `main()`'s resolution loop rejects a resolved doc with no
  usable `fmId` with a named exit-2 message before any write. Covered by
  TEST-012.

## Evidence contract
For each implementation, validation, TDD, and code review artifact record:
ref_id `deterministic-close-ceremony` (spec `spec-deterministic-close-ceremony`),
Spec-AC + TEST-xxx links, command or review scope, exit code or verdict,
evidence path, commit SHA / diff range.
