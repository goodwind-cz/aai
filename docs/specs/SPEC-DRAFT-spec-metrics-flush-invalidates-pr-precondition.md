---
id: spec-metrics-flush-invalidates-pr-precondition
type: spec
number: null
status: implementing
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-DRAFT-metrics-flush-invalidates-pr-precondition.md
  rfc: null
  pr: []
  commits: []
---

# Spec — the flush archives the proof, so the PR gate must be able to read it

SPEC-FROZEN: true

## Links
- Requirement: `docs/issues/ISSUE-DRAFT-metrics-flush-invalidates-pr-precondition.md`
- Decision records: `docs/ai/decisions.jsonl` (no open registry item on this subject — see "Registry items closed by this scope")
- Technology contract: `docs/TECHNOLOGY.md` (Node stdlib only, zero runtime deps, bash 3.2 in suites)
- Prior art this design deliberately follows: SPEC-0160 (PR #331) and
  `spec-ac-table-premature-flip-recurs` (PR #333) — two consumers of one signal
  resolved by extracting ONE shared predicate, never a second heuristic.

## Amendment (post-freeze, 2026-09-02 — validation rounds 1-2, B1 + B2 BLOCKING)

This is a FROZEN spec, amended at remediation and disclosed here rather than
rewritten silently. `SPEC-FROZEN: true` is preserved; the mechanism is the
additive-with-disclosure convention `docs/specs/SPEC-0132-...md`,
`docs/specs/SPEC-0153-...md`, `docs/specs/SPEC-0161-...md` and
`docs/specs/SPEC-0162-...md` already established — nothing in
`.aai/workflow/WORKFLOW.md`, `spec-lint.mjs` or `spec-freeze.mjs` defines a
re-freeze path, so the convention IS the mechanism. `.aai/system/AUTONOMOUS_LOOP.md:25`
assigns scope changes to HITL; **no prior owner sign-off was obtained and the
owner may reverse this.** This is the fourth such unsigned amendment this repo
carries, and the owner has an open intake about that gap. Round 2 asked whether
it could be RETIRED; the answer, argued in item 4 below, is no — the narrowing
is load-bearing and the alternative that would have avoided it does not close
the defect.

1. **The trust argument was false wherever the archive record was minted
   without the DEFAULT gate having held** (B1 + B2, BLOCKING). Three places in
   this spec and in `.aai/scripts/validation-waiver.mjs` argued that a
   `verdict: PASS` ledger entry proves the flush gates held — "Why the archive
   record is trustworthy" below, the `fu-metrics-verdict-has-no-staleness`
   paragraph's "can only ever open the gate for a ride whose live status WAS
   `pass` moments earlier", and R4's "forging one requires editing STATE and the
   ledger consistently". All three were false as delivered, on TWO lanes:
   - **B1, the sweep lane.** `metrics-flush --sweep` substitutes a durable
     `work_item_closed` event plus `active_work_items[ref].status == 'done'` for
     the validation PASS, the entry builder hardcodes `verdict: 'PASS'`, and
     `partialRefs` included swept refs.
   - **B2, the resume lane** (found in round 2, after B1 was fixed and
     confirmed closed). `metrics-flush.mjs`'s `if (inLedger.has(ref)) {
     toResume.push(entry); continue; }` short-circuits BEFORE either gate is
     evaluated, and resumed refs flow into `completedRefs` → `partialRefs` →
     `archiveRefs`. A resumed ref can therefore NEVER be in `sweptRefs`, so
     round 1's `partialRefs.filter(r => !sweptRefs.includes(r))` was a no-op for
     exactly this class. Two reproductions, both opening where base blocks:
     `--sweep` then `AAI_FLUSH_INJECT_CRASH=after-ledger` then a plain re-flush
     (which is `tests/skills/test-aai-metrics.sh` TEST-107's own fixture, the
     designed crash-recovery state of SPEC-0068 Spec-AC-06); and a pre-existing
     same-day `verdict: PASS` ledger line for the focus ref followed by a plain
     flush with **no `--sweep` and no crash at all**.

   Either way the same reset zeroed `code_review.required`, so BOTH SKILL_PR
   preconditions read satisfied for a ride that satisfied neither. Reproduced
   end to end on all three shapes: `open: true, reason: validation_archived_pass`
   where base returns `open: false, reason: validation_not_run_no_waiver`.
2. **The fix narrows Spec-AC-01, and Spec-AC-09 is ADDED** rather than
   Spec-AC-01 being rewritten. Spec-AC-01 said "one archive record per reset
   ref"; the delivered behaviour is one record per ARCHIVE-ELIGIBLE reset ref,
   threaded into `applyPartialReset` as a separate `archiveRefs` argument.
   Eligibility is a POSITIVE property carried from the default gate — the loop
   evaluates the default predicate for EVERY selected entry (it is a pure read
   of the un-committed STATE, so hoisting it above the resume short-circuit
   changes nothing about which refs flush, resume or skip) and collects the
   satisfying refs into a `defaultOkRefs` allowlist; the caller then passes
   `partialRefs.filter(r => defaultOkRefs.has(r))`. Round 1's subtraction of
   `sweptRefs` is REPLACED, not supplemented: a subtraction has to enumerate
   every lane that must not archive and it missed one, while the allowlist
   enumerates the single lane that EARNS the claim and is closed under new
   lanes by construction. The RESET itself is byte-unchanged (prose,
   `run_at_utc`, `ref_id`, both blocks); only the record is withheld, so a
   swept or unvalidated-resumed ref reaches the gate with exactly the verdict it
   had before the flush, while a genuinely-validated ref still archives even
   when it is being RESUMED after an interrupted flush. Spec-AC-01 remains true
   for every ref that satisfies the DEFAULT gate, which is every ref
   TEST-001..008 exercise; the carve-out is recorded in its Notes cell and in
   the section text below rather than by editing the frozen sentence.
3. **Two prose-accuracy corrections in `.aai/scripts/validation-waiver.mjs`**
   (non-blocking findings (a) and (b), no behaviour change): the RECENCY
   paragraph claimed the record is "UN-INHERITABLE" more absolutely than the
   code supports (`state.mjs set-validation --clear <field> --notes '<text>'`
   writes arbitrary notes WITHOUT re-stamping `run_at_utc`, so a record can be
   hand-AUTHORED against a live instant — still worthless without a matching
   ledger PASS, and strictly harder to forge than the waiver lane's single
   hand-written record); and the PRECEDENCE paragraph's "surfaced ONLY where the
   generic would print" is a refusal-side statement, while on the OPEN side a
   valid archive returns before the waiver lane runs, so it opens past a
   MALFORMED waiver record that blocks on base. That note is not
   flush-producible (the preservation path only ever carries a waiver that
   already parsed `ok`); reaching it takes a hand-edited
   `last_validation.notes`, and the prose now says so.
4. **Why this amendment is KEPT rather than retired.** Validation round 2 put
   the question directly: an alternative fix — stop hardcoding
   `verdict: 'PASS'` in the entry builder and emit a non-`PASS` verdict for
   sweep-gated entries — would have left the frozen sentence "one archive
   record per reset ref" literally true, made Spec-AC-09 and TEST-009
   unnecessary, and let this whole section be deleted. It was evaluated and
   REJECTED, on the merits and not on effort:
   - **It does not close B2.** Binding 3 corroborates a record against a
     same-day `verdict: PASS` ledger line. Marking SWEPT lines non-`PASS`
     removes the corroboration for a resumed *swept* ref only. It leaves the
     second reproduction wide open: a pre-existing ledger line that IS a
     genuine `PASS` (any earlier same-day default flush wrote one) still
     corroborates a record minted for a ref whose live `last_validation` now
     says `fail` — or `not_run` — because the resume branch never asked. A fix
     that has to be paired with the allowlist anyway cannot be the reason to
     drop the allowlist.
   - **It changes a different feature's ledger semantics.** `verdict` is
     SPEC-0068's field and the factory report's input; re-typing it for sweeps
     is a product-intent change to the sweep lane, made from inside a frozen
     spec that is about the archive lane. Round 1's stated reason for the
     restraint ("it would move METRICS.jsonl bytes for every past sweep") was
     WRONG and is corrected here — past lines are already written, so only
     future sweeps would change — but the correct reason still holds.
   - **With the allowlist in place it adds no protection to this gate.** A
     swept ref never receives a record, so binding 3 is never reached for one.
     Its only remaining value is against a HAND-AUTHORED record (R5), where the
     ledger requirement is already the harder half. That is worth a follow-up
     registry item on `verdict` honesty, not a scope expansion here.

   So Spec-AC-01 genuinely narrows, the narrowing is what closes B1 and B2, and
   the disclosure has to stay. What round 2 did change is the honesty of the
   claim: the amendment no longer says the narrowing was unavoidable in the
   abstract — it says the one alternative that would have avoided it was
   examined and is insufficient.

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Problem, measured

`.aai/scripts/metrics-flush.mjs` `applyPartialReset` (metrics-flush.mjs:539-570)
resets `last_validation` to `status: not_run`, `ref_id: null`,
`run_at_utc: <flush instant>`, `notes: reset after flush of <refs>` and resets
`code_review` to `required: false`, `status: not_run`. That is designed archival
behaviour: the durable record moved to `docs/ai/METRICS.jsonl`.

`.aai/SKILL_PR.prompt.md` PRECONDITIONS then run
`node .aai/scripts/validation-waiver.mjs --state docs/ai/STATE.yaml`, whose
`evaluateGate` reads those same live fields. On `not_run` with no waiver
sentinel in `notes` it returns `validation_not_run_no_waiver` and exits 1. The
operator reads "this ride never validated" while `docs/ai/METRICS.jsonl` holds
that exact `ref_id` with `"verdict":"PASS"` and full per-role evidence.

Honesty about frequency, carried from the intake verbatim in substance:
CONFIRMED ONCE, HAZARD STRUCTURALLY REPEATABLE. One ride
(`intake-staleness-preflight-warning`) actually manifested the block and needed
a manual `state.mjs set-validation` / `set-code-review` restoration. A second
ride (`adhoc-probes-unisolated-report-only`) ran the same tick ordering but its
preconditions happened to read `pass` when SKILL_PR ran. This is not "observed
twice", and the structural claim is not withdrawn either.

Two findings from reading the code that the intake could not have known, both
load-bearing for the design below:

1. THE `code_review` HALF DOES NOT BLOCK. The partial reset sets
   `code_review.required: false`, and SKILL_PR's check is
   `If code_review.required == true: status is pass or waived`. Post-flush that
   conditional is VACUOUS — it neither blocks nor enforces. The only executable
   refusal is the validation gate. (The silent de-enforcement is a separate,
   quieter defect; see "Residual risks".)
2. THIS REPO TAKES THE PARTIAL-RESET BRANCH, not the full one.
   `fullReset = remaining.length === 0 || remaining.every(it => it.status === 'done')`
   (metrics-flush.mjs:1019). `docs/ai/STATE.yaml` currently carries 64
   `in_progress` work items against 44 `done`, so `remaining.every(done)` is
   false. Measured: `grep -o "    status: [a-z_]*" docs/ai/STATE.yaml | sort | uniq -c`
   → `44 done`, `64 in_progress`. The partial branch is also the only branch
   under which SKILL_PR can even reach the validation gate: the full reset nulls
   `current_focus`, and SKILL_PR step 0 `branch-guard.mjs` refuses first. The
   fix therefore targets the partial-reset shape, which is both the real one and
   the only one where the gate is the binding constraint.

## Direction chosen, and why the other was rejected

CHOSEN — intake option 1 (the gate reads the durable proof), implemented as ONE
EXTENDED PREDICATE, not a second heuristic.

REJECTED — intake option 2 (fix SKILL_LOOP's tick ordering so Metrics Flush
never precedes that scope's SKILL_PR). Rejected on evidence, not taste:

- There is no tick ordering in `.aai/SKILL_LOOP.prompt.md` to fix. Ordering is
  the deterministic first-match rule table in
  `.aai/scripts/orchestration-dispatch.mjs`
  (`node .aai/scripts/orchestration-dispatch.mjs --rules`). That table has 14
  rules and NOT ONE of them dispatches SKILL_PR. Rule 14 is
  `validation pass AND focus ref absent from METRICS.jsonl -> dispatch Metrics Flush`.
- SKILL_PR is deliberately outside the loop because its own PRECONDITIONS
  require "explicit user confirmation to commit/push".
  `.aai/SKILL_SHIP.prompt.md` makes the sequence explicit: step 2 runs the loop
  to completion, step 5 is the SHIP CHECKPOINT (a human gate), step 6 runs
  SKILL_PR. The loop must terminate BEFORE the human gate, and terminating is
  what fires rule 14. Flush-before-PR is therefore a CONSEQUENCE of the human
  gate sitting between them, not an ordering accident.
- Closing the window would require the deterministic dispatcher to condition on
  a PR that cannot exist until a human says yes: a new dispatch rule, a new
  STATE field recording "PR opened", and a narrowed rule-14 predicate. A new
  STATE field means `.aai/scripts/state.mjs` — a PROTECTED L3 path requiring
  explicit owner sign-off. Per the dispatch instruction this is flagged, not
  routed around: option 2 is an L3/HITL scope, option 1 is not.
- Option 2 also fixes only the loop lane. An operator who runs `/aai-flush`
  then `/aai-pr` by hand hits the identical block, and no dispatch rule can
  reach them. Option 1 fixes both lanes.

## Why this is not the mistake SPEC-0160 and #333 were written against

Those two rides failed because TWO CONSUMERS each computed the answer to one
question and disagreed. This design adds NO second consumer and NO second
decision site:

- The question "did this ride validate?" is decided in exactly one function,
  `evaluateGate` in `.aai/scripts/validation-waiver.mjs`, which is already the
  single executable authority SKILL_PR calls. Its call site, its flags, and its
  exit-code contract are unchanged.
- What is added inside that one predicate is a second EVIDENCE SOURCE, not a
  second decider — the same shape as `status: pass` and "a waiver record in
  notes" already being two sources feeding one verdict.
- The record's grammar gets ONE writer and ONE parser, in the same file, in the
  same one-writer/one-parser discipline `formatWaiver`/`parseWaiver` already
  establish there (PR #303 F-2 introduced exactly this pattern for the durable
  waiver field, and `metrics-flush.mjs:121` already imports from that file).
  A producer can never emit a shape the reader refuses, because the producer
  renders through the parser and refuses to emit what will not parse back.

## Design

### Writer — `.aai/scripts/metrics-flush.mjs`

`applyPartialReset` already composes the reset note from one `nowIsoStr`, and
stamps that same value into `last_validation.run_at_utc`; the ledger entry's
`date_utc` is `nowIsoStr.slice(0, 10)` (metrics-flush.mjs:890). One instant,
three places, one transaction. The flush APPENDS to the note it already writes,
one record per reset ref:

```
[AAI-VALIDATION-ARCHIVED v1 ref=<REF> at=<YYYY-MM-DDTHH:MM:SSZ>]
```

The existing prose (`reset after flush of <refs>` and the preserved-waiver
clause) is unchanged and stays first, so `test-aai-metrics.sh:772`'s substring
assertion keeps passing. Records are rendered through `formatArchive`, which
returns null rather than emit a record its own parser would refuse.

**AMENDED 2026-09-02 (`## Amendment`, items 1-2) — "one record per reset ref"
is one record per ARCHIVE-ELIGIBLE reset ref.** `applyPartialReset` takes
`archiveRefs` as a separate argument from `flushedRefs`; the caller passes
`partialRefs.filter(r => defaultOkRefs.has(r))`, where `defaultOkRefs` is the
allowlist the gate loop builds by evaluating the DEFAULT predicate for every
selected entry — including the ones the resume short-circuit
(`inLedger.has(ref)`) used to skip asking about. Reset eligibility and archive
eligibility are different questions: the reset covers every ref this flush
completed, whichever lane completed it, while a record CLAIMS a validation PASS
existed and merely moved, and only the DEFAULT gate establishes that. Swept refs
and resumed refs that do not satisfy that predicate reset byte-identically and
archive nothing; a ref that does satisfy it archives even when it is being
resumed after an interrupted flush (Spec-AC-09, TEST-009).

### Reader — `.aai/scripts/validation-waiver.mjs`

New exports `formatArchive` / `parseArchive` mirroring the waiver pair, and a
new ARCHIVE LANE inside `evaluateGate`, reached only when `status === 'not_run'`.
The lane OPENS the gate when ALL of these hold, and otherwise falls through:

1. `notes` carries exactly one well-formed `v1` archive record whose `ref`
   satisfies `refMatchesScope(record.ref, scopeRef)`, with
   `scopeRef = last_validation.ref_id ?? current_focus.ref_id`.
2. RECENCY BINDING: `record.at` is a real instant (`isRealInstant`) AND is
   byte-equal to `last_validation.run_at_utc`. This is what makes the record
   un-inheritable: `state.mjs cmdSetValidation` re-stamps `run_at_utc` on every
   call that carries a `--status` (state.mjs:578) while PRESERVING `notes`, so
   the moment any later ride writes a status the inherited record goes stale and
   the lane refuses. `reset-block` cannot defeat this: it is a documented no-op
   when the status is already `not_run` (state.mjs:861-864), which is exactly the
   post-flush state. **AMENDED 2026-09-02 (`## Amendment`, item 3):** the
   guarantee is exactly "an INHERITED record goes stale", not "un-forgeable" —
   `set-validation --clear <field> --notes '<text>'` writes notes without
   re-stamping `run_at_utc`, so a record can be hand-AUTHORED against the live
   instant. See R5.
3. LEDGER PROOF: `docs/ai/METRICS.jsonl` — resolved as a sibling of the `--state`
   path, overridable with a new `--metrics <path>` flag for fixtures — holds
   EXACTLY ONE entry whose `ref_id` satisfies `refMatchesScope` against
   `scopeRef`, with `verdict === "PASS"` and `date_utc === record.at.slice(0, 10)`.
   Zero matching entries, or two, refuse. Unparseable ledger lines are skipped,
   never fatal — skipping can only make the gate more closed.

Reason tokens (each printed as `VALIDATION-GATE blocked reason=<token>`):
`archive_malformed`, `archive_obsolete_version`, `archive_ambiguous`,
`archive_ref_mismatch`, `archive_stale`, `archive_no_ledger_pass`,
`archive_ledger_ambiguous`, `archive_scope_unknown`. The open verdict is
`VALIDATION-GATE open reason=validation_archived_pass`.

### Precedence — the lane may only ever OPEN

If the archive lane does not open, the waiver lane runs BYTE-FOR-BYTE as it does
today, including every existing refusal token. The archive's own named refusal
is surfaced ONLY in the position where the waiver lane would have printed the
generic `validation_not_run_no_waiver`. Consequence, stated so it can be tested:
no input that opens the gate today can be made to block by this change, and no
input blocks today for a waiver reason that starts opening because of it.

This precedence is not cosmetic. The flush preserves an unflushed waiver into
the same note (metrics-flush.mjs:552-555), and by construction such a waiver
names a ref that was NOT flushed — i.e. a different ref from every archive
record in that note. An archive-decides-terminally rule would have blocked a
scope whose own preserved waiver opens the gate today. That is the regression
this ordering exists to prevent.

### Why the archive record is trustworthy

A METRICS.jsonl entry is not merely a log line. `metrics-flush.mjs` refuses to
build one unless the flush criteria gates held at flush time: a PASS verdict
NAMING the ref (`vStatus === 'pass' && refMatches(vRef, ref)`, metrics-flush.mjs:947)
and `code_review` pass-or-waived when it was required (metrics-flush.mjs:952),
plus at least one recorded agent run and no pre-existing ledger entry for that
ref. The entry's existence is therefore durable proof that BOTH gates were
satisfied — which is why finding 1 above (the vacuous `code_review` check) does
not need a second mechanism here.

**AMENDED 2026-09-02 (see `## Amendment`, item 1) — the paragraph above is true
of the DEFAULT gate and false of every other route into the ledger.** Two exist.
`--sweep` is an additional OR path that substitutes a durable
`work_item_closed` event plus `status: done` for the validation PASS, and the
entry builder hardcodes `verdict: 'PASS'` for it too. The RESUME branch
(`inLedger.has(ref)`) completes an interrupted flush for any ref that merely
already HAS a ledger line — a swept one, or one from any earlier same-day flush
— and it short-circuits before either gate is consulted at all. A ledger line is
therefore NOT on its own proof that the gates held. What carries the trust is
the ARCHIVE RECORD, which is emitted only for a ref that SATISFIES THE DEFAULT
PREDICATE at flush time (`partialRefs.filter(r => defaultOkRefs.has(r))`), an
allowlist evaluated per ref and independent of which lane completed it. Refs
that do not satisfy it are reset byte-identically and archive nothing, so the
entry's existence still corroborates a record, and only a record the default
gate earned can exist to be corroborated.

### Rejected sub-alternative, recorded

Reusing the existing waiver grammar (`flush writes [AAI-VALIDATION-WAIVER v2
by=agent ... reason="archived"]`) would need zero new code and is WRONG. A
waiver asserts "nothing ran and we proceeded anyway". Here validation ran and
PASSED. Recording a pass as a self-waiver would corrupt every waiver count
`scanWaivers` feeds into the factory report and would make every flushed ride
read as self-waived. Rejected on honesty grounds, not effort.

## Implementation strategy
- Strategy: tdd
- Rationale: the whole deliverable is a predicate whose value is opening on ONE
  shape and refusing eight neighbouring ones. Each refusal needs its own RED
  observation before the accepting case exists, because a hand-written guard
  fails precisely on the must-not-fire cases. Three rides this session shipped
  prose that contradicted their own predicate because only the passing shapes
  were tested; RED-per-refusal is the mechanical answer to that.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: the scope edits `tests/skills/lib/prompt-diet-ledger.sh`,
  a shared append-target that concurrent rides also write, and changes a gate
  two other suites drive. It also already exists — Planning ran inside it.
- User decision: worktree
- Base ref: main (5e8cb0a)
- Worktree branch/path: `fix/metrics-flush-invalidates-pr-precondition` at
  `/Users/ales/Projects/aai-fix-metrics-flush`
- Inline review scope: not applicable (worktree)

## Constitution deviations

None.

## Acceptance Criteria Mapping

- Maps to: intake "Expected Behavior" bullet 1 (the durable-record fallback) and
  the "Verification" negative control.
- Spec-AC-01 .. Spec-AC-09 below (Spec-AC-09 ADDED post-freeze; see `## Amendment`).

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                                                                                                                 | Status  | Evidence | Review-By | Notes                                              |
|------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|----------|-----------|----------------------------------------------------|
| Spec-AC-01 | WHEN metrics-flush takes the partial-reset branch the system SHALL append one archive record per reset ref to last_validation.notes whose at equals last_validation.run_at_utc exactly       | planned | —        | —         | writer side; NARROWED post-freeze to reset refs that satisfy the DEFAULT gate, see Spec-AC-09 and `## Amendment` |
| Spec-AC-02 | WHEN a real flush is followed by the real gate on the same STATE the system SHALL exit 0 and print reason=validation_archived_pass                                                            | planned | —        | —         | the end-to-end seam, writer to reader              |
| Spec-AC-03 | WHEN the archive record names a scope that has no PASS entry in METRICS.jsonl the system SHALL exit 1 with reason=archive_no_ledger_pass                                                      | planned | —        | —         | the intake's negative control                      |
| Spec-AC-04 | WHEN a later set-validation re-stamps run_at_utc while inheriting the note the system SHALL exit 1 with reason=archive_stale                                                                  | planned | —        | —         | recency, not ref_id alone                          |
| Spec-AC-05 | WHEN the archive record names a different ref than the scope in hand the system SHALL exit 1 with reason=archive_ref_mismatch                                                                 | planned | —        | —         | ref binding, mirrors waiver v2                     |
| Spec-AC-06 | WHEN the archive sentinel is present but its grammar is not satisfied the system SHALL exit 1 with reason=archive_malformed and never fall through to a silent open                           | planned | —        | —         | fail-closed on a broken record                     |
| Spec-AC-07 | The nine pre-existing arms of tests/skills/test-aai-pr-waiver.sh SHALL pass unchanged, and a preserved-waiver note carrying archive records for other refs SHALL still open on its own waiver | planned | —        | —         | no loosening and no new blocking                   |
| Spec-AC-08 | SKILL_PR SHALL document the archive lane in its VALIDATION precondition bullet and the prompt-diet ledger SHALL be trued up to the MEASURED byte growth                                       | planned | —        | —         | companion obligation, measured not copied          |
| Spec-AC-09 | WHEN a ref reaches METRICS.jsonl by any route other than satisfying the default gate at flush time (the --sweep gate, or the resume branch over a ledger line that already existed) the system SHALL reset it WITHOUT an archive record, so the PR gate returns the same verdict it returned before the flush | planned | —        | —         | ADDED post-freeze, validation rounds 1-2 B1 and B2; a ref that DOES satisfy the default gate still archives in the same reset, resumed or not |

Status values: planned | implementing | done | deferred | blocked | rejected

> Every row above is IMPLEMENTED and its evidence is in the implementation
> hand-off and in `docs/ai/tdd/metrics-flush-invalidates-pr-precondition-red.log`,
> yet each stays `planned` with an empty Evidence cell by the AC-FLIP DEFERRAL
> rule (`.aai/VALIDATION.prompt.md` step 8a): while this doc's frontmatter
> `status` is still `implementing`, a terminal, evidenced table is exactly the
> shape the probable-false-open heuristic flags — and the flag would be right.
> The flip and the Evidence cells belong to the close ceremony
> (`.aai/SKILL_PR.prompt.md` step 4c), in the same transaction as the
> frontmatter `status`. Consequently
> `node .aai/scripts/docs-audit.mjs --gate spec-metrics-flush-invalidates-pr-precondition`
> reports the nine rows as non-terminal at hand-off; that is the EXPECTED
> state under this rule, and it is
> `node .aai/scripts/docs-audit.mjs --ac-flip-check spec-metrics-flush-invalidates-pr-precondition`
> (exit 0, clean) that is the binding pre-handoff self-check here.

## Implementation plan

Components affected:
- `.aai/scripts/validation-waiver.mjs` — `formatArchive`, `parseArchive`,
  `readArchiveLedger`, the archive lane in `evaluateGate`, `--metrics` flag,
  the extra output lines. NOT an L3 path.
- `.aai/scripts/metrics-flush.mjs` — `applyPartialReset` note composition only.
  NOT an L3 path.
- `.aai/SKILL_PR.prompt.md` — one clause on the existing VALIDATION precondition
  bullet, pointing at the script header for the grammar (the file's established
  convention). Keep it to one clause: every byte is owed to the diet ledger.
- `tests/skills/test-aai-pr-waiver.sh` — new arms.
- `tests/skills/test-aai-metrics.sh` — the writer arm, beside the existing
  reset-note assertion at line 772.
- `tests/skills/lib/prompt-diet-ledger.sh` + `tests/skills/test-aai-prompt-diet.sh`
  — the companion true-up.

Data flow (the seam this change creates):
`metrics-flush.mjs applyPartialReset` writes note + `run_at_utc` and appends the
METRICS.jsonl line in ONE transaction, from ONE `nowIsoStr` →
`validation-waiver.mjs evaluateGate` reads all three back and cross-checks them.
Every test that crosses this seam must PRODUCE with the real flush and ASSERT
with the real gate. Two unit tests that hand-build the note would test the mock.

Edge cases the implementation must handle:
- Multi-ref partial reset (`partialRefs` can hold several refs): one record per
  ref, space-separated; the scope in hand selects one; a duplicated ref is
  `archive_ambiguous`.
- `refMatchesScope` already tolerates the `/`-joined multi-ref `scopeRef` STATE
  writes; reuse it, do not re-derive it.
- The note is written by `textFieldLines` as a folded (`>-`) block scalar which
  YAML re-joins with single spaces — the record grammar must stay SINGLE-LINE,
  exactly as the waiver grammar already is, and the reader must fold the same
  way (`readIndentedBlock` already does).
- A `v2` archive record encountered by a `v1` reader is
  `archive_obsolete_version`, never `archive_malformed` — the waiver file's own
  doctrine: "somebody mistyped" and "this predates the binding" are different
  facts and the operator must be told which.
- The `--metrics` default must resolve relative to the `--state` path, not the
  CWD, or every fixture in the suite silently reads the real ledger.

Out of scope, deliberately:
- The FULL-reset branch. It nulls `current_focus`, so `branch-guard.mjs` refuses
  before the validation gate is ever reached; opening the gate there would fix
  nothing. Recorded under "Residual risks".
- The manual `.aai/STATE_FALLBACK.md` reset path (`state.mjs set-validation
  --status not_run --notes "reset after flush of <ref_id>"`, pinned by
  `test-aai-hygiene-pack.sh:144`). It mints no archive record, so it blocks
  exactly as today and the operator's manual restore remains the route. Not
  changing it keeps that suite and the fallback doc untouched.
- Rides flushed BEFORE this change. Their notes carry prose only, no record, so
  they block as today. The fix is forward-looking by design: a second grammar
  for legacy prose would be exactly the second heuristic this spec refuses.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                     | Description                                                                                                       | Status  |
|----------|------------|-------------|------------------------------------------|-------------------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-metrics.sh         | real flush on a fixture; the reset note carries one record per reset ref and its at equals run_at_utc byte for byte | green   |
| TEST-002 | Spec-AC-02 | e2e         | tests/skills/test-aai-pr-waiver.sh       | real flush then real gate on the same STATE and ledger; exit 0 and reason=validation_archived_pass                  | green   |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-pr-waiver.sh       | valid record, ledger with no PASS entry for the ref; exit 1 and reason=archive_no_ledger_pass                       | green   |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-pr-waiver.sh       | post-flush STATE then set-validation not_run for the same ref; exit 1 and reason=archive_stale                       | green   |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-pr-waiver.sh       | record names ride A while the scope is ride B; exit 1 and reason=archive_ref_mismatch                               | green   |
| TEST-006 | Spec-AC-06 | unit        | tests/skills/test-aai-pr-waiver.sh       | sentinel present with a broken grammar and with a v2 token; exit 1, reason archive_malformed then obsolete_version   | green   |
| TEST-007 | Spec-AC-07 | integration | tests/skills/test-aai-pr-waiver.sh       | the nine existing arms rerun green, plus a preserved-waiver note carrying a foreign archive record still opens       | green   |
| TEST-008 | Spec-AC-08 | integration | tests/skills/test-aai-prompt-diet.sh     | JUSTIFIED_GROWTH_BYTES equals the bumped want_growth and the independent re-sum                                      | green   |
| TEST-009 | Spec-AC-09 | e2e         | tests/skills/test-aai-pr-waiver.sh       | five arms on the real flush then the real gate: (a) --sweep, (b) mixed sweep where only the default-flushed sibling is archived, (c) --sweep crashed after the ledger then a plain re-flush, (d) a plain flush over a pre-existing same-day ledger line with no sweep and no crash, (e) a crash-resume of a genuinely-validated ride that must STILL archive | green   |

Test status values: pending -> red -> green

### RED observations — where each is recorded

Strategy is `tdd`, so every arm above needs a stored RED before its GREEN
counts. Record each under `docs/ai/tdd/metrics-flush-invalidates-pr-precondition-red.log`,
one block per TEST id, each block naming the command, the exit code and the
assertion line that failed. TEST-002 through TEST-007 are RED on the pre-change
tree in a specific way worth naming: the gate has no archive lane at all, so
they fail with `validation_not_run_no_waiver` rather than with the expected
token. That IS the bug reproduced — capture that exact output as the RED for
TEST-002.

### Fixture traps this plan is and is not exposed to

- NOT exposed to the `git init --bare` / `init.defaultBranch` trap. No arm here
  clones a bare repo; the gate and flush suites work on temp-dir STATE and
  ledger fixtures only. Stated explicitly so nobody adds a defensive
  `symbolic-ref` call that has nothing to guard.
- EXPOSED to the guard-tested-only-on-accepting-inputs trap, which is why six of
  the eight arms pin a REJECTED input, and why every arm asserts the EXIT CODE
  first and the printed reason token second — the message text is part of the
  contract, not decoration.
- EXPOSED to the suite's own `set -euo pipefail`. Reuse the existing
  `run_gate` helper in `test-aai-pr-waiver.sh` (it already captures a non-zero
  exit without dying); a bare `rc=$?` and a `grep | head` both die under it, and
  they die on CI only.
- Build fixtures with the REAL `state.mjs` and the REAL `metrics-flush.mjs`, as
  the existing suite header insists. A hand-rolled YAML note would never prove
  that the folded block scalar round-trips the grammar.

## Verification

Commands, in order:

1. `bash tests/skills/test-aai-pr-waiver.sh` — expect exit 0, every arm PASS.
2. `bash tests/skills/test-aai-metrics.sh` — expect exit 0.
3. `bash tests/skills/test-aai-prompt-diet.sh` — expect exit 0; TEST-012 must
   report `JUSTIFIED_GROWTH_BYTES` equal to the bumped `want_growth`.
4. `bash tests/skills/test-aai-hygiene-pack.sh` — expect exit 0 (the fallback
   reset note is untouched; this is the proof).
5. `bash tests/skills/test-aai-orchestration-dispatch.sh` — expect exit 0 (the
   rule table is untouched; this is the proof that direction 2 was not
   half-taken).
6. `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-metrics-flush-invalidates-pr-precondition.md`
   — advisory, report findings.
7. Full framework sweep before close: `bash tests/skills/test-framework.sh`.

Evidence artifacts: the suite result directory under `tests/skills/results/`,
the stored RED log at
`docs/ai/tdd/metrics-flush-invalidates-pr-precondition-red.log`, and the scoped
diff.

PASS criteria: all TEST-xxx green AND all Spec-AC terminal.

### Byte-growth measurement (do NOT copy a number from this spec)

The prompt-diet pin on this base is whatever `tests/skills/test-aai-prompt-diet.sh`
says at implementation time — measure it, never transcribe it:

```
/usr/bin/wc -c .aai/SKILL_PR.prompt.md      # before and after the edit
/usr/bin/grep -n want_growth tests/skills/test-aai-prompt-diet.sh
```

Run the measurement under plain `bash` with `/usr/bin/grep`, never the shell's
aliased `grep` or zsh's history expansion — a measured number that came from
`ugrep` has bitten this repo before. The `JUSTIFIED_ADDITIONS` entry must equal
the MEASURED delta and `want_growth` must move by the same amount.

## Evidence contract
- ref_id: `metrics-flush-invalidates-pr-precondition`
- Spec-AC and TEST links: the Test Plan table above, 1:1 in both directions.
- Command or review scope: the seven verification commands above; review scope
  is the six paths in "Implementation plan".
- Exit code or verdict: exit 0 per suite; the gate's own 0/1 per arm.
- Evidence path: `tests/skills/results/<run>`, the RED log, the scoped diff.
- Commit SHA or diff range: `main...HEAD` on
  `fix/metrics-flush-invalidates-pr-precondition`.

### Evidence by strategy

Strategy is `tdd`, so this spec demands the stored RED artifact per AC-gating
test (`docs/ai/tdd/`) plus the full verification matrix above.

## Registry items closed by this scope

`none` — `node .aai/scripts/follow-ups.mjs list` (open=94) carries no item on
this subject. Two open items touch adjacent surfaces and are deliberately NOT
closed:

- `fu-metrics-verdict-has-no-staleness` (P2): the ledger records `verdict: PASS`
  with no notion of whether the verdict covers the final bytes. This scope makes
  a ledger PASS gate-bearing, which touches that subject — but it adds NO new
  staleness exposure, because the live `last_validation.status: pass` the gate
  already honours is equally stale-blind (see also
  `fu-validation-staleness-undetected`). The archive lane can only ever open the
  gate for a ride whose live status WAS `pass` moments earlier. Staleness is a
  property of the verdict, not of where it is stored; the item stays open and
  unchanged in scope.
  **AMENDED 2026-09-02 (`## Amendment`, item 1):** that "WAS `pass` moments
  earlier" sentence was FALSE as first delivered — `--sweep` minted records for
  refs whose live status was `not_run`, and so did the RESUME branch, for any
  ref that already had a ledger line, with no sweep and no crash needed. It is
  true again only because a record is now withheld from every ref that does not
  satisfy the default predicate at flush time (Spec-AC-09); it is a property the
  fix establishes, not one the design had. The strengthened form the allowlist
  earns: a record exists only where `last_validation.status` was `pass` and
  NAMED that ref at the instant of the reset, whichever lane wrote the ledger
  line beside it.
- `fu-cli-exit-truncates-pipe-sweep` (P2) names `metrics-flush.mjs` as one of
  the console.log-then-exit offenders. This scope adds no new print to a piped
  payload path (`validation-waiver.mjs` already routes through
  `lib/cli-pipe-guard.mjs`), so the item is neither closed nor worsened.

## Residual risks (written down, not left out)

- R1. THE VACUOUS `code_review` CHECK. Post-flush `code_review.required` is
  `false`, so SKILL_PR's review precondition stops enforcing rather than
  blocking. This scope does not change it: making it demand evidence post-flush
  would newly BLOCK rides that pass today, which is beyond the intake. The
  compensating fact is real — a METRICS entry can only exist if the review gate
  was satisfied at flush time — but the PR body's "Review status" line and
  `close-work-item.mjs --review` still read the reset block and will understate
  a flushed ride as `none`. Recommend filing this as a follow-up registry item
  at implementation time rather than folding it in here.
- R2. FULL-RESET RIDES are unfixed by design (see "Out of scope"). A ride that
  hits the full branch loses focus, strategy and worktree state too; the
  validation gate is not its binding constraint.
- R3. NO AUTOMATED TEST CROSSES THE SKILL_PR PROSE SEAM. That the PR ceremony
  actually calls the gate is asserted by the prompt text alone; nothing executes
  `.aai/SKILL_PR.prompt.md`. TEST-002 crosses the flush-to-gate seam, which is
  the seam with real state on both sides, but the prompt-to-script seam stays a
  reviewed-not-tested surface — as it is today for the waiver.
- R4. A HAND-EDITED `docs/ai/METRICS.jsonl` could mint a PASS entry. The file is
  per-developer, local and gitignored; the same is already true of every field
  the gate reads. The three-way binding (ref, `run_at_utc` equality, `date_utc`)
  means forging one requires editing STATE and the ledger consistently, which is
  strictly harder than today's single-field edit.
  **AMENDED 2026-09-02 (`## Amendment`, item 1):** as first delivered this risk
  understated the exposure in the direction that matters — `metrics-flush
  --sweep` performed BOTH halves of that "consistent edit" for you, from one
  ordinary command, with no hand-editing at all, and a plain re-flush over an
  existing same-day ledger line did the same through the RESUME branch.
  Withholding the record from every ref that does not satisfy the default
  predicate (Spec-AC-09) is what restores the sentence: forging one again
  requires making `last_validation` say `pass` for the scope AND holding a
  matching ledger entry, which is the "consistent edit" the sentence claims.
  What survives as a genuine residual is narrower and is recorded as R5.
- R5. A RECORD CAN BE HAND-AUTHORED, not merely inherited.
  `state.mjs set-validation --clear <field> --notes '<text>'` writes arbitrary
  notes WITHOUT re-stamping `run_at_utc` (`--status` is optional once `--clear`
  is given), so the recency binding stops an INHERITED record but does not stop
  a deliberately authored one. It still buys nothing alone: binding 3 demands a
  real `verdict: PASS` ledger entry for that scope on that day, so the forgery
  needs the ledger too — strictly more than the single hand-written record the
  waiver lane has always accepted. Recorded, not closed: closing it would mean
  making `run_at_utc` unwritable, which is a `state.mjs` change and `state.mjs`
  is protected L3.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
