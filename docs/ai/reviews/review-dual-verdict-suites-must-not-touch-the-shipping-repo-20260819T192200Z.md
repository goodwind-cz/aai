# Code Review — suites-must-not-touch-the-shipping-repo (round 3, narrow re-review)

```yaml
review:
  scope: "git diff main -- tests/skills/test-framework.sh .aai/scripts/lib/repo-tripwire.sh tests/skills/test-aai-repo-tripwire.sh .aai/scripts/aai-run-tests.sh tests/skills/suite-map.yaml .aai/system/PROFILES.yaml docs/specs/SPEC-0137-spec-suites-must-not-touch-the-shipping-repo.md docs/issues/CHANGE-0151-suites-must-not-touch-the-shipping-repo.md (base main @ 4fb5c60, working tree)"
  spec: docs/specs/SPEC-0137-spec-suites-must-not-touch-the-shipping-repo.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-001/TEST-002 green in the 12-arm run; re-proved inside the ratchet fixture by TEST-008(c) and by TEST-011's unlisted third writer. Mutation m2 (allowlist lookup disabled) turns TEST-008+TEST-011 red." }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-007 green; .aai/scripts/aai-run-tests.sh:270-292 unchanged by this remediation." }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-006 green against the real checkout in this session's 12-arm run." }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-003/009/010 green. Tri-state attestation still gated: mutation m5 (`local tw_attested=true`) turns TEST-003, TEST-008 and TEST-011 red together." }
      - { ac: Spec-AC-05, call: compliant,
          citation: "TEST-004 green, measured 6 status calls over 3 suites — the deletion removed no snapshot and added none." }
      - { ac: Spec-AC-06, call: compliant,
          citation: "TEST-008/011/012 green; mutations m1 (path-subset check dropped) -> TEST-008 red, m3 (aai_tripwire_hash_changed neutralised) and m4 (clean->dirty escalation disabled) -> TEST-011 red alone. BLOCKING-3 reproduction now prints 0 STALE lines." }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 516,
          issue: "The line `content changed (git status class unmoved, caught by the ratchet-path hash): <path>` is printed for EVERY path in `tw_hash_paths`, whether or not the status class moved. `tw_hash_paths` is only a content verdict; it says nothing about the class. On a clean checkout — the CI case — the same path is therefore printed twice in one block, once as `changed: <path>` (which can only come from the status comparison) and once under an assertion that the status comparison saw nothing. Same defect at :569 in the ALLOWED block. This is the same honesty class as the deleted stale-drain (a line asserting evidence the run did not gather), one rank lower because no operator action attaches to it and no verdict moves.",
          failure_scenario: "Clean checkout, real shipped suite. `bash tests/skills/test-framework.sh --skill aai-metrics` on a freshly-committed byte copy of this repository prints, in one ALLOWED block: `changed: docs/ai/overview-data.json`, `changed: docs/ai/overview.html`, then `content changed (git status class unmoved, caught by the ratchet-path hash): docs/ai/overview.html` and the same for overview-data.json. Both files were clean at suite start, so the class moved and the parenthetical is false. Fires on all four ratchet entries on every clean CI run. Fix: emit the line only for paths absent from `aai_tripwire_changed_paths` output (the framework already computes both lists at :393-394)." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-repo-tripwire.sh, line: 426,
          issue: "The deletion took with it the ONLY assertion that constrained framework output for a ratchet entry whose suite did not fire, and the Test Plan row for TEST-008 (spec:546) still claims that control is run: 'The fifth suite is an allowlisted one that writes nothing, kept as the in-run control that an unused entry produces no line at all'. The arm asserts nothing about lines naming aai-hitl-propagation; the row overclaims what the arm gates.",
          failure_scenario: "Mutation m6: reintroduce the deleted drain in its most dangerous form — an unconditional loop in generate_summary printing `STALE ratchet entry '<suite>' — it changed nothing in this run; close the item and delete the entry` for every table entry. TEST-003, TEST-008 and TEST-011 all stay GREEN. The exact defect this ride removed can return without any arm going red. Remedy (either): one negative assertion in TEST-008 (`grep -q 'STALE' <<<\"$out\"` must not match), or delete the 'produces no line at all' clause from the Test Plan row so it stops claiming a gate that does not exist." }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 374,
          issue: "The clean->dirty escalation lifts only `clean`. When `tw_state == unavailable` the content-hash evidence is computed and then discarded, so a positive detection is silently dropped. This is the answer to 'who else reads tw_state': removing the drain left no other reader wrong, but this reader has a pre-existing asymmetry. Same shape in the `lost` branch at :502-505, which prints no paths even when `tw_hash_paths` is non-empty.",
          failure_scenario: "Framework run in a checkout that is not a git repository (the TEST-010 degrade, and the ordinary state of a downstream vendoring `.aai/` + `tests/skills/` without git). Fixture: one suite, not on the ratchet, appends to `docs/INDEX.md`. Observed: `aai-zz-evil PASS (0.0s) [tripwire NOT ARMED — no usable git snapshot of <root>]`, framework exit 0, the write landed, and the hash snapshot had detected it. Nothing in the run names the detection — a degrade without a NOTE (AGENTS.md convention). Fix: escalate on `-n \"$tw_hash_paths\"` regardless of tw_state, or at minimum name the hash-detected paths on the NOT ARMED / lost lines." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/repo-tripwire.sh, line: 20,
          issue: "The vendored library's CONTRACT block lists seven functions and omits `aai_tripwire_hash_usable` — which the framework calls at test-framework.sh:172 and which is the only way a caller can tell 'the paths were digested' from 'there is no hasher on this machine' — and `aai_tripwire_hasher`. It also states no hash-side limit: with only `cksum` present the 'content verdict' is a 32-bit CRC, and a path that is UNREADABLE in both snapshots compares equal and reads unchanged. Validation round 3 raised the omission; I find no follow-up id covering it.",
          failure_scenario: "A downstream vendor reads only the header (the stated purpose of that block), hashes a named path set, and reads an empty `aai_tripwire_hash_changed` as proof the files did not move — on a machine with no digest tool, where every snapshot is `HASHER UNAVAILABLE` and every comparison is trivially empty. The guard exists (`aai_tripwire_hash_usable`) but the contract does not mention it." }
  cannot_verify:
    - { claim: "The reported full-suite figure '80/80 observed, exit 0, four ALLOWED, zero STALE'.",
        closes_with: "An uninterrupted `AAI_TEST_TIMEOUT=1800 bash tests/skills/test-framework.sh`. Mine reached 24/80 in ~50 minutes (aai-delta-stage3 alone took 368s) and was stopped to stay inside the review budget; through 24/80 it showed zero STALE and zero ALLOWED — the four ratchet suites all sort after `aai-feedback-*` and had not run. I closed the gap differently: each of the four ratchet suites was then run as its own framework run via --skill, all four printing PASS [tripwire ALLOWED ...] with the WARNING block, the registry item and 0/1 attested; and the BLOCKING-3 case was reproduced directly. Validation holds the clean full-run evidence." }
    - { claim: "Behaviour of the ratchet on Windows/PowerShell CI and on a machine with no digest tool.",
        closes_with: "A run on each. The no-hasher degrade path is exercised only by inspection here; `fu-tripwire-degrade-not-on-suite-line` already tracks its honesty gap." }
  overall: pass
```

## 1. Is BLOCKING-3 gone, and gone by removal rather than by hiding?

Gone, by removal. The code is absent: no `TRIPWIRE_CLEAN_SUITES`, no feeder in
`run_test`, no drain block in `generate_summary`, and no other reference anywhere in
the repo (`/usr/bin/grep -rn 'TRIPWIRE_CLEAN'` over the tree: zero hits outside the
prior review reports). The ratchet header at test-framework.sh:59-63 states why the
drain was deleted rather than conditioned, and D8 (spec:302-318) records the same with
the measurement.

Reproduced my own case rather than reading theirs — fixture `fxD`, byte copy of the
shipped framework and library in a throwaway git repo, five suites: `aai-state` exits
42, `aai-metrics` exits 3, `aai-hitl-propagation` clean at exit 0, `aai-token-capture`
writes both its listed paths, one unrelated clean suite. Output:

```
[ 1/ 5] aai-hitl-propagation PASS (1.0s)
[ 2/ 5] aai-metrics          FAIL (0.0s) [tripwire NOT ATTESTED — suite exited 3 before completing]
[ 3/ 5] aai-state            SKIP (0.0s) [tripwire NOT ATTESTED — suite skipped (exit 42), it never ran]
[ 4/ 5] aai-t-clean          PASS (0.0s)
[ 5/ 5] aai-token-capture    PASS (0.0s) [tripwire ALLOWED — known offender fu-token-capture-writes-overview, inside its listed path(s)]
...
Tripwire: 1 known-offender suite(s) changed the shipping repository inside their allowlisted paths
Tripwire: 2/5 suite(s) attested clean; 3 not attested
```

STALE lines: 0. Both live entries whose suites did not run are untouched and unmentioned;
no operator instruction to close a registry item. The rest of the verdict is unchanged —
the skipped suite is still SKIP, the crashed one still FAIL with its own reason, the
allowlisted one still ALLOWED, the attestation arithmetic still tri-state.

The `follow_up_status` closing `fu-tripwire-stale-line-blind-to-d7` cites the same
reproduction and is honest about it.

## 2. Did the deletion take anything load-bearing?

No — verified by mutation, not by reading. One reused copy of the repository under the
scratchpad, re-baselined by commit, arms trimmed to TEST-003/008/011, pristine files
restored by `cp` between runs (no git restore anywhere, in the live tree or the copy).
Unmutated control: all three green.

| Mutation | Result |
|---|---|
| m1 — drop the path-subset check (an entry becomes blanket permission) | TEST-008 red, alone |
| m2 — disable the allowlist lookup entirely | TEST-008 + TEST-011 red |
| m3 — neutralise `aai_tripwire_hash_changed` in the library | TEST-011 red, alone |
| m4 — disable the clean->dirty escalation in the framework | TEST-011 red, alone |
| m5 — `local tw_attested=true` (collapse the tri-state) | TEST-003 + TEST-008 + TEST-011 red |
| m6 — reintroduce an unconditional STALE drain | **all three still GREEN** |

So: the listed-then-unlisted-same-path case still fails (m1, m3, m4 and TEST-011's own
`aai-zz-evil` assertion), allowlisted suites inside their paths still read ALLOWED and do
not fail (m2 proves the arms depend on it), and the attestation counting is still
tri-state (m5). The two edited arms still gate what their Test Plan rows claim, with one
exception: TEST-008's row claims an in-run control ("an unused entry produces no line at
all") that the arm does not assert, and m6 shows the consequence — see NON-BLOCKING-2.
That is the honest answer to "did the deletion take anything": it took the only assertion
that would notice the defect coming back.

I also checked m2 against the spec's own evidence cell for Spec-AC-06, which says the
allowlist-ignoring mutation turns "TEST-008 red alone". Measured, it turns TEST-008 and
TEST-011 red — TEST-011 reads the same ALLOWED label. The cell was written before
TEST-011 existed. INFO below; the Spec-AC-04 cell handles its own pair correctly and this
one should read the same way.

## 3. Is the NB-1 documentation honest and in the right place?

Yes, with one gap that is not about NB-1 itself.

The library header (repo-tripwire.sh:83-99) states the bound in LIBRARY terms first —
"this library reports the paths that MOVED, and a path that was ALREADY dirty when the
observed command started does not move… a caller comparing `aai_tripwire_changed_paths`
against an allowlist cannot see an out-of-list write to a path that was dirty
beforehand" — then names the framework instance, quotes the exact line an operator would
see (`tripwire ALLOWED … inside its listed path(s)` at exit 0), says the write lands, says
ratchet paths are exempt because they are content-hashed, says why it is stated rather
than enforced, says what a caller who needs it closed must do (diff against its own
before-snapshot), and names the tracked id. A downstream vendor reading only that header
is correctly warned: the warning is generic, it is not buried in a framework-specific
example, and it does not overstate the exemption. D8 (spec:320-334) and the CHANGE doc
(:66-70) carry the same, and `fu-tripwire-allowed-ignores-pre-dirty` is open at P2.

The gap is elsewhere in the same header: the CONTRACT block a vendor reads first lists
seven functions and omits `aai_tripwire_hash_usable`, which is precisely the guard that
stops an empty hash comparison from being read as "unchanged". NON-BLOCKING-4.

## 4. The interaction

Readers of `tw_state` after the deletion: the escalation (:374), the ratchet block
(:387), the note/attestation case (:424), and the metrics record (:578). Readers of
`tw_attested`: the not-attested counter (:458), the progress line (:476), the metrics
record (:578). Removing the drain left none of them with a stale assumption — the drain
was a pure consumer, it fed nothing, and `TRIPWIRE_CLEAN_SUITES` has no surviving
reference.

The interaction that IS wrong is one the deletion did not create and did not fix: the
escalation at :374 is conditioned on `tw_state == clean`, so the hash verdict — which
needs no git at all — is thrown away whenever git is the thing that is missing.
Reproduced: NON-BLOCKING-3. Two mechanisms named separately (D8 hashing, D9
unavailable), and their interaction discards positive evidence and prints a green PASS.

## Was deleting the drain the right call?

Yes, and I would make the same call. A correct drain needs three conditions at once —
the suite ran to completion, the tripwire was armed, and the content verdict was actually
gathered (not the no-hasher degrade) — and its output is an instruction to delete a
guard entry and close a P2. That is a large correctness surface for a convenience, added
to a mechanism whose own spec says it is transitional. Conditioning it would have made a
fourth reader of `tw_state`/`tw_attested`/`TRIPWIRE_HASH_DEGRADED` on a mechanism
scheduled for deletion. The one thing the deletion should have kept is a one-line
negative assertion, which is NON-BLOCKING-2.

## Findings

**BLOCKING: none.**

- **NON-BLOCKING-1** — false "git status class unmoved" claim on every ALLOWED and
  content-violation block whose path's class DID move; fires on all four ratchet entries
  on a clean CI checkout. `tests/skills/test-framework.sh:516` and `:569`. Recommended
  disposition: **remediate in-tree** (one condition, and the framework already has both
  lists in hand at :393-394). Cheap, and it is operator-facing output of the same honesty
  class as the finding this round removed.
- **NON-BLOCKING-2** — the deleted drain is now ungated (m6 green) and the TEST-008 Test
  Plan row still claims the control. `tests/skills/test-aai-repo-tripwire.sh:426`,
  spec:546. Recommended disposition: **remediate in-tree** — either one `grep -q 'STALE'`
  negative assertion in TEST-008, or strike the clause from the row. Do not leave both as
  they are.
- **NON-BLOCKING-3** — hash evidence discarded when `tw_state == unavailable`
  (`test-framework.sh:374`, and no paths named in the `lost` block at :502-505).
  Recommended disposition: **promote to a follow-up ref** (new `fu-` id, P3) — it cannot
  bite a git-repo CI run, and the disposable-worktree successor moots it.
- **NON-BLOCKING-4** — the vendored library's CONTRACT block omits
  `aai_tripwire_hash_usable` / `aai_tripwire_hasher` and states no hash-side limit
  (`cksum` fallback is a 32-bit CRC; UNREADABLE-in-both compares equal).
  `.aai/scripts/lib/repo-tripwire.sh:20-47`. Recommended disposition: **remediate
  in-tree** (three lines in a comment block that is the vendor-facing contract), or a new
  P3 follow-up if the ride is closing.

## INFO (never gate)

- Spec-AC-06 evidence cell (spec:592): "ignoring the list so a known offender fails again"
  turns TEST-008 **and TEST-011** red, not "TEST-008 red alone". Measured this session.
- `.aai/scripts/lib/repo-tripwire.sh:55` still cites "(D4)" for the clean-is-not-verified
  rule; that is D3. Flagged in the previous two passes, still there.
- The spec's Implementation plan (spec:638) still says the new suite has "the seven arms
  above"; it has twelve. `tests/skills/test-aai-repo-tripwire.sh:6` still says "Covers
  TEST-001..TEST-007".
- `tests/skills/test-aai-repo-tripwire.sh:415` still says "aai-metrics runs first in the
  discovery order"; discovery is alphabetical and `aai-hitl-propagation` sorts first. The
  reasoning the comment carries is still correct.
- The 20260819T153900Z review report still ends with two stray `</content>` / `</invoke>`
  lines; it is untracked and will be staged with this scope.
- `fu-suite-map-tripwire-row-incomplete` (P3) is still open and the suite-map row is
  unchanged — it omits `tests/skills/test-aai-spec-lint.sh` and `.aai/system/PROFILES.yaml`,
  both of which this scope changed.
- The ALLOWED block prints each hash-detected path twice (once under `changed:` from the
  union, once under `content changed`). Merged into NON-BLOCKING-1; on its own it is
  cosmetic.

## Evidence

- `bash tests/skills/test-aai-repo-tripwire.sh` — 12/12 PASS, exit 0 (zsh, non-interactive
  `bash` invocation; all greps in my own measurements were `/usr/bin/grep` by absolute
  path).
- BLOCKING-3 reproduction: `scratchpad/repro-blocking3.sh` — fixture fxD, 0 STALE lines,
  verdict unchanged.
- NOT-ARMED interaction reproduction: `scratchpad/repro-unarmed.sh` — exit 0, write landed,
  no mention.
- Mutations m1-m6 in one reused re-baselined copy (`scratchpad/mutcopy`), runner
  `scratchpad/mutate.sh`; table above.
- Clean-copy real-suite run confirming NON-BLOCKING-1:
  `test-framework.sh --skill aai-metrics` in `scratchpad/mutcopy` (git status clean at
  start).
- Live tree, four ratchet suites via `--skill`: all four PASS [tripwire ALLOWED ...], each
  naming its registry item, each 0/1 attested clean.
- `node .aai/scripts/spec-lint.mjs` — 137 specs, 0 findings.
- `node .aai/scripts/check-test-registration.mjs` — exit 0, no output.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` — Verdict: CLEAN, exit 0.
- Full framework run: started, reached 24/80 in ~50 min, stopped to stay in budget (see
  cannot_verify).

## Anti-gaming note

The dispatch stated it had not ranked anything and then framed four judgements, which the
contract requires me to record. It named the deletion, the two edited arms, the NB-1
documentation and "the interaction" as the places to look. Of the four findings here, one
(NON-BLOCKING-2) is inside a place it named but is the opposite of what it asked — it
asked whether the deletion took anything load-bearing out of the *guard*, and what it took
was the *test*; one (NON-BLOCKING-1) is in a place it did not name at all and is the
finding I would fix first; one (NON-BLOCKING-3) is the interaction it asked about, though
not the one it implied (no reader was left wrong by the deletion; a pre-existing reader is
wrong on its own); and one (NON-BLOCKING-4) came out of the NB-1 question but is not about
NB-1. No severity coaching was attempted. The note that the ratchet is transitional
entered exactly one judgement — whether deleting the drain beat conditioning it — where it
is a legitimate input, and no other.

The dispatch also set a 45-minute target. I exceeded it: the full framework run consumed
~50 minutes and produced 24/80. I stopped it rather than trim the mutation work, because
the mutation table is what answers the question I was asked and the full run is Validation's
evidence, not mine. That trade is recorded here rather than hidden in a green line.
