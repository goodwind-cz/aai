---
id: spec-role-verification-guards
type: spec
number: 133
status: done
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0146-role-verification-guards.md
  rfc: null
  pr:
    - 261
  commits:
    - 797c742
---

# Spec — four report-only guards where one role takes another's word

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0146-role-verification-guards.md
- Evidence ride for all four gaps: CHANGE-0145 (PR 259 / PR 260)
- Engines edited: `.aai/scripts/close-work-item.mjs` (G1),
  `.aai/scripts/append-event.mjs` and `.aai/scripts/orchestration-dispatch.mjs` (G2)
- Prompts edited: `.aai/SKILL_TDD.prompt.md` (G3),
  `.aai/SKILL_TEST_SKILLS.prompt.md` (G4)
- Precedent this scope copies wholesale: CHANGE-0120 rule 9x — a content hash
  recorded as an EVENTS line and compared at the next dispatch, chosen there for
  exactly this scope's reason (see the comment at
  `.aai/scripts/orchestration-dispatch.mjs` line 694: "the confirm arm needs no
  new STATE field ... state.mjs is a protected L3 surface this change
  deliberately does not touch")
- Suites that already own these surfaces: tests/skills/test-aai-close-work-item.sh,
  tests/skills/test-aai-orchestration-dispatch.sh, tests/skills/test-aai-tdd.sh,
  tests/skills/test-aai-prompt-diet.sh
- Routing already correct in tests/skills/suite-map.yaml (verified): the
  `aai-orchestration-dispatch` row already globs BOTH `orchestration-dispatch.mjs`
  and `append-event.mjs`; `aai-close-work-item` globs `close-work-item.mjs`;
  `aai-prompt-diet` globs `.aai/*.prompt.md`; `aai-tdd` globs `SKILL_TDD.prompt.md`
- Prompt-corpus ledger: tests/skills/lib/prompt-diet-ledger.sh (TEST-012 pin -3747)
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, zero dependencies,
  canonical invocation `bash .aai/scripts/aai-run-tests.sh <command...>`)

## Ceremony level — 2, declared, with the reasoning

Level 2 is the DEFAULT and it is the honest level here. Level 1 is defined in
`.aai/workflow/WORKFLOW.md` as "S fix, single surface"; this scope moves five
files across four independent mechanisms, one of which is the deterministic
dispatch engine that decides every role hop in the factory. Level 3 is
MANDATORY only when the scope touches `protected_paths_l3` in
docs/ai/docs-audit.yaml — and the whole point of D2 below is that it does not.
The intake's `ceremony_level: 1` was explicitly conditional (assumption A1:
"Planning declares the binding value"); this is that declaration, and it is one
level heavier than the intake guessed, not lighter.

Recorded consequence: L2 means full pipeline (independent validation, mandatory
code review). No operator sign-off and no mandatory FULL_RUN are owed, because
no protected surface is entered.

## Summary

Four places where a role accepts another role's word. Each answer is ONE
warning on a surface that already exists. No new script, no new gate, no new
dependency, no exit-code change anywhere.

Corrected at remediation (validation-20260816T131500Z N4): G1's edit to
`close-work-item.mjs` collides with TWO other frozen specs' byte-diff-empty
pins on that same file (SPEC-0131/CHANGE-0143 D5, SPEC-0129/CHANGE-0142 D5).
A pure byte-diff pin cannot survive a third spec legitimately touching the
file, so ONE new test-support file,
`tests/skills/lib/close-work-item-pin.sh`, unifies both pins into one shared
content-hash allowlist (see Spec-AC-09 and the Implementation plan). This is
the one exception to "no new file" above, and it is a test library, not a
production script — the SPEC-0060 precedent (`prompt-diet-ledger.sh`) is the
same shape.

The budget is the finding, not modesty. CHANGE-0145 ran roughly 30 hours
because its core was a new engine. A guard that costs more than the defect
class it prevents is a net loss, and two of the four decisions below (D2's
storage choice, D3's conditionality) are made on that basis with numbers
attached.

## Design decisions recorded at planning time (do not re-derive)

### D1 — G1 detects post-merge closes with GIT, not with the PR API

The intake reasoned that `close-work-item.mjs` "already receives `--pr N`, so
it can read that PR's state". It can, and it should not. Three measured
reasons, all checked against the tree:

1. `close-work-item.mjs` shells out today ONLY to `node` (append-event, the
   four regenerators, metrics record) and to `git worktree list` (line 807).
   It makes no network call and every one of its 35 existing arms is hermetic.
   `gh pr view` would put a network round-trip and an external CLI inside the
   close ceremony and force a PATH-shimmed fake `gh` into every arm.
2. It would be GitHub-only. `.aai/scripts/pr-platform.mjs` exists precisely
   because this repo committed to platform portability (SPEC-0103), and it is
   a remote-URL classifier — it has no PR-state reader to extend, verified by
   reading it. Adding a GitHub-shaped state read regresses that contract.
3. The PR's API state is a WEAKER signal than the local one. The question the
   warning must answer is "will the commits this close produces be part of the
   PR and its CI?" — and the direct local evidence is that the DELIVERY COMMIT
   IS ALREADY UPSTREAM.

The predicate, therefore:

```
git merge-base --is-ancestor <args.commit> <upstream default ref>
```

exit 0 means the delivery commit already sits on the default branch, so the
close is running after the merge and anything it writes lands outside the PR
and outside its CI. In the documented order (PR 259) the delivery commit lives
only on the feature branch, the predicate is false, and nothing is printed.

Upstream default ref resolution, in order, first hit wins:
`git symbolic-ref --quiet refs/remotes/origin/HEAD`, then the literal
`origin/main`, then `origin/master`. Every git failure — no remote, no such
ref, not a repository, non-zero exit — resolves to NO WARNING. Fail-open is
correct for a report-only guard: a false silence costs nothing, a false alarm
in the close ceremony trains people to ignore the line.

The line goes to STDERR (where the product-doc, usage-capture and
evidence-path warnings already go), is emitted ONCE PER INVOCATION rather than
once per ref (the pair-close arm, test_005, closes two refs in one run), and
carries the greppable token `post-merge-close`:

```
close-work-item: WARN post-merge-close - delivery commit <sha> is already an
  ancestor of <ref>; commits produced by this close will be in neither PR
  #<N> nor its CI
```

Stdout is untouched, so the byte-identity contract of test_009's canon grep
and the existing completion line both hold.

### D2 — G2 stores the judged hash in EVENTS, not in `last_validation`. THE L3 TRAP IS REAL AND THIS AVOIDS IT HONESTLY

The intake flagged the trap and it is exactly as described: `last_validation`
is written by `.aai/scripts/state.mjs`, which is line 1 of `protected_paths_l3`
in docs/ai/docs-audit.yaml. Touching it forces `ceremony_level: 3` on the
WHOLE scope — operator sign-off plus a mandatory FULL_RUN — for four warnings.

Both cheaper-route claims were verified against the code before relying on
them, and both are true:

- `orchestration-dispatch.mjs` DOES compute a content hash and put it in its
  state summary: `spec.content_hash = specContentHash(body)` (line 651), inside
  `buildSnapshot`, printed as part of `state_summary`.
- `docs/ai/EVENTS.jsonl` IS an append-only audit log written through
  `.aai/scripts/append-event.mjs`, and neither file appears in
  `protected_paths_l3`.

More than that: the exact mechanism this scope needs ALREADY SHIPPED as
CHANGE-0120's rule 9x. A `phase_confirmed` event carries a `hash` payload; the
next tick reads the LAST such event for the focus ref out of the same EVENTS
scan that rule 4b already performs, and compares. The in-code justification for
that storage choice is quoted in the Links section above and is verbatim this
scope's reasoning. G2 is therefore not a new design; it is a second instance of
a pattern this repo already adopted, tested and shipped.

**Ruling: events-based. `ceremony_level` stays 2. No protected surface is
touched.** If a future scope wants the hash inside `last_validation` for STATE
consumers, that is a separate L3 ride with its own sign-off.

Three sub-decisions inside that ruling:

**What is hashed.** AC-003 says "the content hash of the TREE state it judged",
not the spec's contract hash — so `specContentHash` is the wrong function here.
On CHANGE-0145 the thing that moved under the verdict was the engine, the
suite, the prompt and eight description surfaces: tracked files, some committed
and some dirty. The hash is therefore a sha256 (`node:crypto`, stdlib) over the
concatenation of `git rev-parse HEAD`, `git status --porcelain=v1 -uno` MINUS
any status line naming a path in `TREE_HASH_EXCLUDE_PATHS`, AND `git diff
HEAD` for tracked changes MINUS any per-file block naming a
`TREE_HASH_EXCLUDE_PATHS` entry (the diff fold-in is the B4 fix, below). That
captures new commits, uncommitted tracked edits AND content moving inside an
already-dirty tracked file, and deliberately ignores untracked files — `-uno`
and plain `git diff HEAD` both skip them identically — because the untracked
set on any live ride is the in-flight intake draft, the spec and the
gitignored `docs/ai/tdd/*.log` churn, and hashing those would make the warning
fire on every tick and be ignored within a day. Any git failure yields `null`,
and a null on either side of the comparison means NO ADVISORY (fail-open, same
rationale as D1).

Corrected at remediation (validation-20260816T131500Z B1): the exclusion list
was added because the ORIGINAL hash (no exclusions) was self-invalidating in
THIS repository. `docs/ai/EVENTS.jsonl` is TRACKED here (unlike every G2
fixture, which committed before the file existed), so the `--confirm` stamp's
own append moved the hash it had just recorded, and because the stamp is
first-observation-only (below), the staleness advisory latched ON
permanently with nothing else changed — proven by `probe_g2b` in the
validation report. `docs/ai/decisions.jsonl`, the regenerated
`docs/INDEX.md`, `docs/ai/overview.html` and `docs/ai/tests/test-runs.jsonl`
are also TRACKED and move within minutes of ordinary ride activity that has
nothing to do with the judged verdict, compounding it without any self-write
at all. `TREE_HASH_EXCLUDE_PATHS` (in `orchestration-dispatch.mjs`, beside
`computeTreeHash`) names exactly these append-only/generated ledgers, so
appending an audit line — or a scheduled regen touching only a `Generated:`
stamp — is not treated as a change to the tree a validator judged. Two
alternatives were weighed and rejected: refreshing the stamp on every
`--confirm` (the ACTUAL `phase_confirmed` precedent, corrected below) does
not clear the false advisory on the tick that observes the drift, because
`decide()` reads the snapshot built BEFORE that tick's own write — it only
prevents the NEXT tick's advisory, one tick too late; and scoping the hash to
the spec's own review-scope file list (RR-2's named follow-up) is strictly
more precise but is machinery this remediation was not asked to build. The
chosen fix removes the self-invalidation at its source and is provably
sufficient for the "stamp, then dispatch again with nothing else changed"
case (TEST-011).

Corrected at remediation (validation-20260816T143000Z B4): the status-only
hash was blind to a CONTENT edit inside a tracked file that was ALREADY
dirty at stamp time — `git status --porcelain` carries only a path and an
XY status letter, never bytes, so editing an already-`M`-marked file left
the hash byte-identical. Measured on this repository's own file set (20
modified tracked files as a matter of routine): this was the DOMINANT shape
on a live ride, not an edge case, and it is precisely the scenario G2 exists
to catch — validation records `pass`, then someone edits the scope's own
code before the next role hop. Every G2 fixture that existed before this fix
mutated a file that was CLEAN at stamp time (status-letter flip, which the
hash already saw), so no arm exercised it — the same fixture-realism gap B1
closed on the opposite polarity (self-invalidation on NOTHING changing).
Fixed by folding `git diff HEAD`'s filtered patch text into the hash
alongside the porcelain status (`filterExcludedDiff`, beside
`computeTreeHash`), using the SAME `TREE_HASH_EXCLUDE_PATHS` set matched
against each file's `diff --git a/<path> b/<path>` header, so the B1
exclusion behavior holds on the new content-diff input exactly as it already
did on the status-line input — proven by TEST-013's negative arm (an
already-dirty `docs/ai/EVENTS.jsonl` edited further stays silent). Measured
cost: `git diff HEAD` runs in roughly 20ms on this repository, next to the
~10ms `git status` call already paid every tick — immaterial next to the
rest of a dispatch tick's file I/O, so no alternative (e.g. hashing only a
narrower diff, or skipping already-tracked-dirty files) was needed to keep
the guard cheap.

**Who writes it, and the honest limit that follows.** The stamp is written by
`orchestration-dispatch.mjs` under the EXISTING `--confirm` opt-in, through the
existing `recordConfirm`-shaped delegation to `append-event.mjs`, on the first
tick that observes `last_validation.status == pass` for the focus ref with no
matching `validation_verdict` event yet. It is NOT written by the validator.

Corrected at remediation (role-verification-guards remediation, B-1): the
ORIGINAL rule stopped there — "no matching event yet" — which made the stamp
per-REF-forever rather than per-VERDICT. A re-validation that later records a
fresh pass on the current tree (the modal shape of an L2 ride: FAIL, remediate,
PASS again) could never move the reference point, so `withStaleAdvisory`
compared the current tree against a reference that was one or more
remediations old and the advisory latched permanently ON the moment ANY
tracked file moved after the first stamp — losing all discriminating power on
exactly the ride shape G2 was written for. The stamp condition now ALSO fires
when `last_validation.run_at_utc` (state.mjs's self-stamped verdict timestamp)
is strictly newer than the last stamped event's own `ts` (append-event.mjs's
auto-filled timestamp) — i.e. whenever a validation round has completed since
the reference point was last set — proven by TEST-004's extended arm (stamp,
mutate, observe the advisory, record a newer verdict, prove the second stamp
and the cleared advisory).

Corrected at remediation (BLOCKING-1, validation-20260816T203700Z): "strictly
newer" was implemented as a lexicographic string `>` on the two ISO-8601
timestamps, which is not a newer-than comparison across them — the two
producers emit at DIFFERENT precision by design (`append-event.mjs`'s `ts`
keeps milliseconds; `state.mjs`'s `run_at_utc` truncates to the second via
`state-engine.mjs`'s `nowIso()`), so a verdict recorded in the SAME
wall-clock second as its own stamp compared as strictly newer than that
stamp (string index 19: a truncated-second string's `Z` sorts above a
millisecond string's `.`). Since the comparison target is the last stamp's
`ts`, not the live clock, this stayed true on every later tick until a
genuinely new verdict landed — a spurious re-stamp that adopted whatever tree
was current on the tick that triggered it as the new reference, silently
healing a real staleness advisory one tick after it correctly fired. Fixed by
comparing `Date.parse` instants on both sides (`Number.isFinite`-guarded,
same fail-closed polarity as every other missing-data guard here); a
same-second verdict now compares as NOT newer, the correct fail-closed
reading — a verdict whose recorded second matches the stamp's cannot be
*proven* newer. Proven at the exact boundary by TEST-004's second extended
arm: `run_at_utc` set to the truncated second of the last stamp's own `ts`
(never a hand-picked date), asserting no re-stamp and a persistent advisory
across repeated `--confirm` ticks.

That is a deliberate trade and it has a cost, stated plainly: the recorded hash
is the tree as of the first dispatch tick that OBSERVED each verdict, not the
tree as of the instant the validator finished. A tracked change landing in
that window is invisible to the guard, and the window re-opens on every fresh
verdict, not just the first one. What it buys is large — one writer, no new
file, no prompt-corpus growth, no second definition of the hash function that
could drift from the comparison side, and `--confirm` remains the single opt-in
exception to dispatch's read-only contract rather than becoming two. The window
is seconds on a normal tick; the CHANGE-0145 defect opened hours later.

**How it stays report-only.** Detection lives in `decide()`, which
`test_018_purity_and_docstring_guard` pins as a pure, non-mutating function of
its snapshot — so the two inputs (`tree_hash`, `last_validation_verdict`) are
computed in `buildSnapshot` and `decide()` only compares them. When
`validation.status == pass`, both hashes are non-null, and they differ,
`decide()` sets an ADDITIVE `advisories` key containing
`validation_verdict_stale`. It does not touch `rule`, `verdict`, `role`,
`reasons`, or the exit code. The `advisories` key is present ONLY in the
stale case (Spec-AC-05's first clause). Corrected at remediation
(validation-20260816T131500Z B3, and this paragraph brought into agreement
with that fix at validation-20260816T143000Z N2b): the NON-stale case is
NOT byte-identical to the pre-change tree — `buildSnapshot` always adds
`tree_hash` and `last_validation_verdict` to `state_summary` regardless of
staleness, so pure byte-identity was never achievable once D2 made that
design choice. The real guarantee, and the one `test_042`'s `cmp` clause
(TEST-007) verifies against a pinned pre-change blob, is additive-only
modulo exactly those two named keys — see Spec-AC-05's Verification for the
precise mechanics. `test_033_stable_segment_byte_identity` pins a DIFFERENT,
narrower thing (`prompt_hash`/`inherits` stability across two ticks, not
stdout bytes) and is not evidence for this paragraph's claim; the citation
above is removed rather than repeated. `main()` prints one stderr line when
the `advisories` key is present, with or without `--human`. A snapshot
lacking the new fields entirely (undefined — exactly what test_018 passes)
produces no advisory.

Corrected at remediation (N-4, validation-20260816T203700Z): the staleness
condition checked the stamped EVENT's own `payload.status`, never STATE's
current `last_validation.status`. The event payload is a snapshot frozen at
stamp time — it never updates after the fact. If STATE's own
`last_validation.status` later moves off `pass` (a fresh fail/not_run
verdict, or an operator's `reset-block`), the old event still says
`status: "pass"` forever, and a live tick kept asserting "the recorded pass
verdict's tree hash no longer matches" about a pass verdict STATE no longer
holds. `withStaleAdvisory` now ALSO requires `snapshot.validation.status ===
'pass'`, so the advisory fires only while STATE and the last stamp AGREE a
pass verdict is standing.

New event type `validation_verdict` is appended to `append-event.mjs`'s closed
`EVENT_TYPES` set, requiring `--status` and `--hash`. Verified safe: every
consumer in `.aai/scripts/lib/docs-audit-core.mjs` filters by explicit
`e.event === '<known>'` equality, so an unrecognized type is inert there.

### D3 — G3's sweep is TIED TO CEREMONY LEVEL, not applied flat

The measured inputs, taken from this repo rather than from preference:

- Cost of the sweep: ~35 min, on every ride it applies to.
- Observed benefit, one data point: on CHANGE-0145 (an L2 ride) it would have
  caught two blockers — a branch-diff allowlist entry and a CHANGELOG scaffold
  — two roles earlier, saving ~2.5 h (~150 min).
- Ride mix, counted over `docs/specs/*.md` frontmatter at planning time:
  30 specs at level 1, 65 at level 2, 8 at level 3 (103 leveled, 134 total).

Applied FLAT: 103 x 35 min = ~60 h of sweep. Tied to L2/L3: 73 x 35 min =
~43 h, i.e. ~17.5 h of L0/L1 sweeps not paid.

Whether the L2/L3 half pays for itself depends on how often a cross-suite
defect actually surfaces. At the CHANGE-0145 saving of 150 min, true
break-even on 73 L2/L3 rides is 2555 / 150 = 17.0 hits, i.e. roughly **1 hit
in every 4.3 rides** (corrected at remediation — the original sentence here
computed 73/5 x 150 min = ~36 h against a ~43 h cost and presented that as
"break-even," which is a 15% net LOSS at that ratio, not a break-even; 1-in-5
was never the break-even point on these numbers) — plausible but not proven,
and honestly not provable from one observation. The cost side also omits a
duplicate worth naming: `.aai/VALIDATION.prompt.md`'s LEAK-SAFE EXECUTION
section already mandates the SAME full 79-suite sweep at exactly the L2/L3
population one role later (`When lane.selected == "full" ... run the full
discovery/execution sweep exactly as today`), so G3's marginal benefit is
"catch it one role earlier, where the same role can still fix it in place,"
not "catch it for the first time" — smaller than the 150 min figure above
credits it with, since the counterfactual already ends at Validation rather
than running loose indefinitely. Note what is NOT in doubt: the L0/L1 half is
a clear loss. A level-1 ride is single-surface by definition, and this repo's
L1 implementations routinely finish in less time than the 35-minute sweep
would add. Making a 20-minute ride 55 minutes to guard against a cross-suite
interaction that a single-surface change can barely produce is precisely the
guard-costs-more-than-the-defect shape the scope was told to avoid.

**Ruling, corrected at remediation: the sweep is RECOMMENDED — not a REQUIRED
standing rule — before a done claim at ceremony_level 2 and 3, and not
recommended at 0 and 1 (the role must SAY so either way).** The original
ruling required it at L2/L3 on a break-even claim that does not hold on its
own numbers, and on a cost model that missed a full sweep Validation already
runs at the identical population one role later. Demoting REQUIRED to
RECOMMENDED costs almost nothing in practice: the escape hatch the intake
already allowed ("or it states plainly that it did not run and why") already
made an un-run sweep permitted at every level provided it is named, so the
observable behavior a role follows is nearly unchanged — what changes is that
the spec stops asserting a trade it has not established. At L0/L1 the
sanctioned reason is the level itself, which converts a silent omission into a
named, auditable one; at L2/L3 an un-run sweep is still permitted but must
carry a real reason, because a guard that cannot be overridden becomes a gate,
and a gate is out of scope regardless of REQUIRED/RECOMMENDED wording.

Fail-closed on ambiguity: the prompt instructs the role to treat an absent or
unreadable ceremony level as 2 (sweep recommended), matching every other
consumer's fail-closed default in this repo.

### D4 — G4 IS PROSE-ONLY. Nothing in the repo arms a waiter in code

Checked before specifying, per the intake's assumption A2. A case-insensitive
sweep of `.aai/**/*.md` for `background`, `run_in_background`, `wait for`,
`waiting for` and `summary.txt`, plus a sweep of `.aai/scripts/` for
output-stream polling, returns ELEVEN hits and not one is a background-run
waiter:

- `SKILL_HITL.prompt.md:23,34,56` and `SKILL_WORKTREE.prompt.md:66` — waiting on
  a HUMAN, not on a process.
- `SKILL_PR.prompt.md:260,261,271,275,302` — polling a PR API within a bounded
  window, which is already the correct shape (a remote resource, not a stream).
- `SKILL_DOCS_AUDIT.prompt.md`, `SKILL_WRAP_UP.prompt.md`,
  `SKILL_INTAKE.prompt.md` — operator approval gates.
- `AGENTS.md:228`, `system/AUTONOMOUS_LOOP.md:46` — status vocabulary.

**Ruling: G4 is documentation only. No code is invented to change.** AC-007
splits accordingly into a positive half that has a real RED (the teaching does
not exist yet) and a regression pin whose subject is already true today —
stated as such rather than dressed up as a fix.

The positive teaching goes in `.aai/SKILL_TEST_SKILLS.prompt.md`, the one
prompt that tells a role to run the long sweep. And it must name the right
predicate, because the obvious one is broken: `test-framework.sh` writes
`$RUN_DIR/summary.txt` TWICE — line 101 at setup ("Test run started at ...")
and line 249 at the end. **Polling for the EXISTENCE of `summary.txt` returns
true immediately and is exactly as wrong as matching a colour-coded pattern in
the output stream.** The completion-distinguishing token is the literal header
`AAI Skills Test Summary`, written only by the final heredoc. The teaching
names that string, and names why existence is insufficient.

### D5 — everything locally provable, and what these guards do NOT do

Every verification below is a local command: the two engine suites through
`bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>.sh`, `grep`
contracts over two prompt files, `git` predicates inside mktemp fixture repos
built with `git init -b main`, and `wc -c` for the prompt-byte delta. No
network, no service, no `gh`.

Limits, recorded because the failure mode of a warning is that people believe
it means more than it does:

1. G1 detects "the delivery commit is already upstream", which is a PROXY for
   "the PR is merged". A legitimate close from a second clone after a merge
   trips it — by design, per the intake ("exit code unchanged; closing from
   another clone after a merge is legitimate"). It is a notice, not an
   accusation.
2. G2's hash is stamped at first observation of a verdict, not at verdict
   time (D2), and — since the B-1 remediation fix — this now applies to EVERY
   observed verdict, not only the ride's first one: each fresh pass re-opens
   the same few-second validator-to-first-tick window. That window is
   unguarded on every occurrence, not just once per ride.
3. G2 detects that the TRACKED tree moved, not that the move was RELEVANT to
   the verdict. Any commit in the window trips it. Scoping the hash to the
   spec's review-scope file list would be more precise and is more machinery
   than this scope may spend; it is a legitimate follow-up.
4. G2 is blind to untracked changes (`-uno`, D2) and blind to a tree that moved
   and moved back to byte-identical content. It is NOT blind to a content edit
   inside an already-dirty tracked file — that was a genuine gap (B4) until
   the diff fold-in above closed it; recorded here as fixed, not as a residual,
   since RR-2 already carries what remains.
5. `computeTreeHash`'s `git diff HEAD` call carries a 64 MB `maxBuffer`
   (remediation N-C; raised from an original 16 MB): an overflow throws,
   `computeTreeHash` returns `null`, and G2 disarms with no signal — no stamp
   is written under `--confirm` and no advisory is ever printed, the same
   silent-fail-open every other git call in this file already has.
   `TREE_HASH_EXCLUDE_PATHS` does NOT reduce what crosses this buffer:
   `filterExcludedDiff` runs on the string AFTER `execFileSync` returns, so a
   large regenerated EXCLUDED ledger counts against the limit in full before
   it is filtered out. The two sibling git calls (`rev-parse HEAD`,
   `status --porcelain=v1 -uno`) still carry Node's 1 MB default, unraised —
   three thresholds on three calls, not one uniform limit.
6. G3's floor is prompt compliance. Nothing mechanically verifies that a TDD
   role which claims a green sweep actually ran one; the guard removes the
   silent omission, not the dishonest claim. As of this remediation the
   requirement itself is a RECOMMENDATION, not a standing rule (see D3) —
   the floor is one layer softer than "required but unverified."
7. G4 changes nothing executable. Its whole mechanism is one prompt teaching
   plus a regression pin.
8. No guard here can fail a ride. That is the scope, and any of these turning
   into a gate is a scope violation, not an improvement.

## Implementation strategy
- Strategy: hybrid
- Rationale: G1 and G2 each have a cheap deterministic RED against a real
  program on the pre-change tree — a merged-order fixture prints nothing today,
  and a mutated tree under a recorded pass produces no advisory today — so they
  ride the TDD lane with a stored RED artifact per AC-gating test, `RED_CLASS:`
  written as line 1 at capture. G3 and G4 are prompt teachings whose RED is a
  zero-hit grep against the pre-change corpus and whose GREEN is a grep
  contract, plus the ledger true-up that the existing TEST-012 pin makes red
  mechanically the moment the bytes land: loop lane, RED observed and recorded,
  storage optional. STATE carries no intake-sourced strategy choice for this
  scope (the intake's `## Notes` has no `Implementation mode (user choice):`
  line), so this is Planning's call.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: no protected surface and no parallel scope touches these
  five files, so isolation is not needed for safety; it is worth offering only
  because `orchestration-dispatch.mjs` is the engine every role hop reads and a
  broken working tree there stalls the factory rather than one scope. A
  dedicated branch is required regardless by the one-branch-per-work-item rule
  that `branch-guard.mjs` enforces at PR.
- User decision: undecided
- Base ref: main
- Worktree branch/path: feat/role-verification-guards
- Inline review scope: .aai/scripts/close-work-item.mjs,
  .aai/scripts/append-event.mjs, .aai/scripts/orchestration-dispatch.mjs,
  .aai/SKILL_TDD.prompt.md, .aai/SKILL_TEST_SKILLS.prompt.md,
  tests/skills/test-aai-close-work-item.sh,
  tests/skills/test-aai-orchestration-dispatch.sh, tests/skills/test-aai-tdd.sh,
  tests/skills/test-aai-prompt-diet.sh, tests/skills/lib/prompt-diet-ledger.sh,
  docs/specs/SPEC-0133-spec-role-verification-guards.md,
  docs/issues/CHANGE-0146-role-verification-guards.md, CHANGELOG.md,
  tests/skills/lib/close-work-item-pin.sh (new — Spec-AC-09, N4),
  tests/skills/test-aai-follow-ups.sh (TEST-008 switched to the shared pin
  plus OK-status assertion, new arm test_010 — N1/N4),
  tests/skills/test-aai-doc-numbering.sh (TEST-029 switched to the shared
  pin plus OK-status assertion — N1/N4),
  tests/skills/test-aai-spec-lint.sh (the `.aai/` no-new-ceremony branch-diff
  allowlist gains this scope's five `.aai/` paths — a companion obligation of
  G1-G4, same shape as D3's own CHANGE-0145 example),
  tests/skills/suite-map.yaml (both owning suites gain globs for
  close-work-item.mjs and the shared pin library — NB-7; restored to scope at
  PR staging after round 5 ruled that deleting a genuinely-changed path to
  force set-equality leaves it in no scope at all)

Declared at remediation, validation-20260816T131500Z N3: the four entries
above were changed by the original implementation but omitted from this
list. No `spec_scope_edited` event accompanies this correction —
`spec-scope-edit.mjs` refuses by design to move a path the ride's own diff
touched (that is exactly this situation, a content omission, not out-of-band
bookkeeping), so the fix is this direct edit to the frozen spec's scope
bullet, made in the same remediation pass as B1-B3.

History, corrected at remediation (external review, PR #261 F3 — Copilot and
Codex both independently found this; the round-4 version of this paragraph
below is superseded and left visible for the record, not deleted):
`tests/skills/suite-map.yaml` was added to the scope list above at the
round-3 remediation pass (per the code review's NB-7 disposition "remediate
in tree"), then at round 4 (validation-20260816T203700Z N-3) it was REMOVED
from this list on the reasoning that the matching path had never been added
to `docs/ai/STATE.yaml`'s `code_review.scope` (17 in STATE vs 18 here) and
removing it here would restore set-equality. That reasoning was wrong:
validation round 5 ruled that deleting a path the ride's own diff genuinely
touched, purely to force set-equality, leaves that path in NO declared scope
at all — worse than the mismatch it was meant to fix. Round 5 restored
`tests/skills/suite-map.yaml` to BOTH lists instead: it is back in the
inline scope bullet above (see the NB-7 entry), and `docs/ai/STATE.yaml`'s
`code_review.scope` was updated to carry all 18 paths including it —
verified set-equal by the round-2 code review
(`docs/ai/reviews/review-20260816T214153Z-role-verification-guards.md`:
"the scope list ... now DOES include suite-map.yaml, and STATE's
code_review.scope now carries all 18 paths including it (verified)").

Code review required: true (code, test and prompt changes); scope = the
explicit path list above as a diff against main.

## Companion obligations check (closed list)
- Prompt corpus bytes move: YES. `.aai/SKILL_TDD.prompt.md` (G3) and
  `.aai/SKILL_TEST_SKILLS.prompt.md` (G4) are both inside TEST-010's live
  `.aai/*.prompt.md` glob. Fold in ONE `JUSTIFIED_ADDITIONS` entry in
  tests/skills/lib/prompt-diet-ledger.sh credited 1:1 at the MEASURED combined
  growth G, and bump the TEST-012 pin in tests/skills/test-aai-prompt-diet.sh
  from -3747 to -3747 + G. Budget ceiling for this scope: 900 B combined. No
  other prompt and no `.aai/AGENTS.md` byte moves. Neither file is one of the
  three thin wrappers, so `WRAPPER_LINE_CEILING` (45) does not apply to either.
- New `.aai/**` file: NO. All five files named at planning time are edited in
  place, so no `.aai/system/PROFILES.yaml` classification entry is owed. ONE
  new file exists outside `.aai/**` — `tests/skills/lib/close-work-item-pin.sh`
  (test-support, not production; declared at remediation, N4; see Spec-AC-09)
  — so this specific obligation (which only fires on a new `.aai/**` path)
  is genuinely unaffected.
- Not a companion obligation, fixed at remediation anyway (NB-7, supersedes
  the N5 follow-up `fu-pin-lib-suite-map-route`, now closed):
  tests/skills/suite-map.yaml globbed `tests/skills/lib/**` only via the
  unrelated `aai-win-fallback` row; neither `aai-doc-numbering` nor
  `aai-follow-ups` globbed the new library or `.aai/scripts/close-work-item.mjs`
  directly (both suites were still selected on THIS PR's own diff via their
  OTHER globbed paths — `append-event.mjs`, `decisions.jsonl`,
  `test-aai-follow-ups.sh` itself — so the gap was real but not yet load-
  bearing here). N5 originally filed this as a follow-up rather than fixing
  it in tree; the code review that found the gap independently ranked it
  "fix here, a routing gap on the guard's own file is the same self-
  referential hole as everything else on this ride," so both suite-map rows
  now glob `.aai/scripts/close-work-item.mjs` and
  `tests/skills/lib/close-work-item-pin.sh` directly. Every OTHER touched
  path is already globbed by the suite that owns it.

## Acceptance Criteria Mapping

- Maps to: CHANGE-0146-role-verification-guards AC-001
- Spec-AC-01: WHEN `close-work-item.mjs` runs with a `--commit` sha that is
  already an ancestor of the resolved upstream default ref THEN stderr carries
  EXACTLY ONE line containing the token `post-merge-close`, naming the sha, the
  ref and the PR number, even when the invocation closes a pair of refs; WHEN
  the sha is not an ancestor THEN zero such lines appear; WHEN any git step
  fails or no upstream ref resolves THEN zero such lines appear; WHEN
  `--dry-run` is passed THEN zero such lines appear regardless of ancestry
  (intentional — confirmed at remediation, validation-20260816T131500Z N7:
  `--dry-run` already reports everything informationally in its own JSON, and
  this line is suppressed there to match the three pre-existing gates beside
  it, per the code comment at `close-work-item.mjs` `main()`).
- Verification: two mktemp fixture repos built with `git init -b main` (merged order and open-PR order) plus a no-remote fixture; `node .aai/scripts/close-work-item.mjs --ref <slug> --pr <N> --commit <sha>` capturing stderr; `grep -c post-merge-close` equals 1, 0 and 0 respectively; the pair-close fixture also equals 1; the merged-order fixture re-run with `--dry-run` added equals 0.

- Maps to: CHANGE-0146-role-verification-guards AC-002
- Spec-AC-02: WHEN the post-merge warning is emitted THEN the process exit code
  and the whole of stdout are byte-identical to the same fixture run against
  the pre-change tree, and the same holds on the non-warning path.
- Verification: capture exit code and stdout for all three fixtures on the pre-change tree and again after; `cmp` the stdout captures; assert the exit codes match pairwise. "The pre-change tree" is a git blob sha PINNED once, by hand, at the moment G1 landed — never `git archive HEAD` or any other HEAD-relative resolution (corrected at remediation, validation-20260816T131500Z B2: HEAD IS the post-change tree from the delivery commit onward, so a HEAD-relative "pre-change" extraction self-destructs the instant this scope is committed).

- Maps to: CHANGE-0146-role-verification-guards AC-003
- Spec-AC-03: WHEN `orchestration-dispatch.mjs` runs with `--confirm` against a
  STATE whose `last_validation.status` is pass for the focus ref and no
  `validation_verdict` event exists for that ref THEN docs/ai/EVENTS.jsonl gains
  exactly one `validation_verdict` line whose `payload.hash` equals the
  `tree_hash` reported in that run's `state_summary` and whose `payload.status`
  is pass; WHEN the same tick repeats with the tree unchanged THEN no second
  line is appended; WHEN `--confirm` is absent THEN nothing is written.
- Verification: fixture repo plus fixture STATE; run `node .aai/scripts/orchestration-dispatch.mjs --confirm`; `wc -l` on EVENTS before and after equals plus one; parse the appended line and assert `payload.hash` equals `state_summary.tree_hash`; re-run and assert `wc -l` unchanged; run without `--confirm` on a clean EVENTS and assert `wc -l` unchanged. Added at remediation — validation-20260816T203700Z BLOCKING-1: the "same tick repeats" clause above is exercised at the exact boundary where it was refuted — set `last_validation.run_at_utc` to the truncated second of the last stamped event's own `ts` (never a hand-picked date; this is what `state.mjs` would have written had the validator recorded the verdict in the same wall-clock second as the stamp) and assert a further `--confirm` tick still appends no new line; then, with a genuine tracked mutation present, assert the stale advisory keeps firing on EVERY subsequent `--confirm` tick rather than self-clearing after one.

- Spec-AC-03's idempotency clause holds only when both timestamps compared for freshness are parsed as INSTANTS (`Date.parse`, both sides `Number.isFinite`-guarded), never compared as strings — the two producers (`append-event.mjs`'s millisecond `ts`, `state.mjs`'s second-truncated `run_at_utc`) disagree at exactly the second boundary, and a same-second verdict must compare as NOT newer than its own stamp.

- Maps to: CHANGE-0146-role-verification-guards AC-004
- Spec-AC-04: WHEN a `validation_verdict` event exists for the focus ref, the
  recorded verdict is still pass IN BOTH the event's own payload AND
  `last_validation.status` (corrected at remediation, N-4,
  validation-20260816T203700Z — the event payload alone is a snapshot frozen
  at stamp time and never updates, so a later fail/not_run verdict or an
  operator `reset-block` must silence the advisory even though the OLD event
  still says pass), and the tracked tree has since changed OUTSIDE
  `TREE_HASH_EXCLUDE_PATHS` (D2, corrected at remediation —
  validation-20260816T131500Z B1) THEN the dispatch prints one stderr line
  containing `validation_verdict_stale` and names the focus ref, with no
  agent input and with or without `--human`; WHEN the tree is unchanged THEN
  zero such lines appear; WHEN the only tracked change since the stamp is an
  append to a `TREE_HASH_EXCLUDE_PATHS` entry — INCLUDING the `--confirm`
  stamp's own write to `docs/ai/EVENTS.jsonl` — THEN zero such lines appear
  on that tick or any later tick with nothing else changed; WHEN either hash
  is null, the snapshot carries neither new field, or `last_validation.status`
  is no longer pass THEN zero such lines appear.
- Verification: from the AC-003 fixture, mutate one TRACKED file, re-run the dispatch without `--confirm`, `grep -c validation_verdict_stale` on stderr equals 1 and the ref appears on the same line; the unmutated control equals 0; a snapshot built without the new fields, passed directly to the exported `decide()`, yields no `advisories` key; from a fixture whose `docs/ai/EVENTS.jsonl` is TRACKED before the first `--confirm` tick (mirroring this repo), stamp then re-dispatch twice more with nothing else changed — `grep -c validation_verdict_stale` on stderr equals 0 on both later ticks (TEST-011). Added at remediation — validation-20260816T143000Z B4: a tracked file dirtied BEFORE the stamp (git status letter " M" set once and never changed again in the arm), stamped while already dirty, then edited a SECOND time (same status letter, different bytes) — `grep -c validation_verdict_stale` on stderr equals 1, proving the hash is now sensitive to content moving inside an already-dirty file, not just to the status-letter/path set changing; the same shape inside a `TREE_HASH_EXCLUDE_PATHS` entry (`docs/ai/EVENTS.jsonl`) stays at 0, proving the B1 exclusion still holds on the new content-diff input (TEST-013). Added at remediation — validation-20260816T203700Z: (BLOCKING-1) a validation round recorded in the SAME wall-clock second as the last stamp must NOT produce a re-stamp, and a genuine tracked mutation at that same boundary must keep producing the advisory on every subsequent `--confirm` tick rather than self-clearing after one (extends TEST-004); (N-4) a pure `decide()` call with `snapshot.validation.status: 'not_run'` but a stale event payload still claiming `status: 'pass'` and a mismatched hash yields no `advisories` key (extends TEST-006).

- Maps to: CHANGE-0146-role-verification-guards AC-005
- Spec-AC-05: WHEN the stale condition holds THEN the run's `rule`, `verdict`,
  `role`, `reasons` and process exit code are identical to the same snapshot
  without the stale condition, and the stdout JSON differs from it ONLY by the
  added `advisories` key; WHEN the stale condition does not hold THEN the
  stdout JSON is ADDITIVE-ONLY relative to the pre-change tree's output for
  the same snapshot: byte-identical once the two known-additive
  `state_summary` keys (`tree_hash`, `last_validation_verdict`) are removed
  from both captures. (Corrected at remediation — validation-20260816T131500Z
  B3: pure byte-identity was never achievable once `buildSnapshot` always
  adds those two keys to `state_summary`, which D2 deliberately chose; the
  original clause claimed a stronger guarantee than the implementation gives
  and TEST-007's evidence did not run the `cmp` this AC's own Verification
  named.)
- Verification: run the stale and non-stale fixtures, diff the two stdout JSON objects after deleting `advisories` and `state_summary` and assert equality; assert both exit codes equal; run the SAME fixture through the pinned pre-change `orchestration-dispatch.mjs` (a recorded blob sha, never a moving `HEAD` — see B2's Verification below for why) and the current script, delete `tree_hash`/`last_validation_verdict` from the current run's `state_summary`, and compare the two non-stale stdout captures via `JSON.stringify` equality on the parsed objects (TEST-007). Corrected at remediation — validation-20260816T143000Z N2: `JSON.stringify` equality is key-order-sensitive but NOT byte-sensitive the way `cmp` is — a whole-output reformat (e.g. `JSON.stringify(out, null, 2)`) parses to the identical object and would pass this check while failing a real `cmp` on the raw bytes. That gap is out of this AC's scope (no clause here promises byte-level output-format stability; the dispatch CLI's stdout format is unpinned repo-wide, a pre-existing condition). What this Verification's comparison DOES catch — an added, removed or changed `state_summary` key beyond the two named ones — is exactly Spec-AC-05's substance, independently confirmed at the byte level in the validation report via a surgical string-level key deletion on the raw stdout captures.

- Maps to: CHANGE-0146-role-verification-guards AC-006
- Spec-AC-06: WHEN `.aai/SKILL_TDD.prompt.md` Phase 4 is read THEN it names,
  before any done or complete claim, either a recorded full framework sweep
  result or an explicit named statement that the sweep did not run together
  with the reason; it states that the sweep is RECOMMENDED at ceremony_level 2
  and 3 and NOT recommended at 0 and 1 (corrected at remediation, Q4: the
  original wording REQUIRED it at 2 and 3 as a standing rule — see D3 for why
  that overstated the case); it names the level itself as the sanctioned
  reason at 0 and 1; and it instructs that an absent or unreadable level is
  treated as 2.
- Verification: grep contracts over `.aai/SKILL_TDD.prompt.md` for the sweep-recommendation sentence, the literal levels 2 and 3, the literal levels 0 and 1, the did-not-run statement form, and the fail-closed-to-2 instruction; each token present exactly once in the Phase 4 region.

- Maps to: CHANGE-0146-role-verification-guards AC-007
- Spec-AC-07: WHEN `.aai/SKILL_TEST_SKILLS.prompt.md` is read THEN it teaches
  waiting on the DISK ARTIFACT, naming `summary.txt`, naming the
  completion-distinguishing literal `AAI Skills Test Summary`, and stating
  explicitly that the mere EXISTENCE of `summary.txt` is not completion because
  the framework creates it at setup; AND no `.aai/**` file matches the
  output-stream-wait regex `OUTPUT_STREAM_WAIT_RE` (corrected at remediation,
  N-A: the original clause claimed a corpus-wide absence of ANY guidance
  instructing a wait on an output-stream pattern — a universal negative the
  arm does not establish. The regex is polarity-blind (it has no notion of
  prohibition, so a line correctly TEACHING "never wait on a pattern in the
  output stream" would report as a hit) and narrow (three of four realistic
  offending phrasings evade it, `fu-test020-corpus-regex-thin`). What the arm
  actually proves — a real property, just a narrower one — is that this ONE
  pattern finds zero matches today and DOES find a match against a synthetic
  fixture carrying it, so the pin is not vacuous).
- Verification: grep contracts over `.aai/SKILL_TEST_SKILLS.prompt.md` for the three tokens and the not-existence sentence; a corpus scan over `.aai/**` for the `OUTPUT_STREAM_WAIT_RE` pattern returning zero hits; a synthetic fixture carrying the forbidden phrasing must make the same scan return non-zero, proving the pin can bite. Widening the pattern's recall (so a wider set of offending phrasings, and no correctly-worded prohibition, trips it) is a named follow-up (`fu-test020-corpus-regex-thin`), not part of this AC's claim.

- Maps to: CHANGE-0146-role-verification-guards AC-008
- Spec-AC-08: WHEN the scope is complete THEN the combined measured growth of
  the two edited prompts is at most 900 bytes, ONE `JUSTIFIED_ADDITIONS` entry
  credits it 1:1 naming both files and their measured deltas, the TEST-012 pin
  equals -3747 plus that growth and equals an independent re-sum of the array,
  and no prompt exceeds any line cap that applies to it.
- Verification: `wc -c` deltas on both prompts summing to at most 900; `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh` exits 0 with the bumped pin; assert neither edited file is in the `WRAPPER_LINE_CEILING` list.

- Maps to: (no separate intake AC — declared at remediation, validation-20260816T131500Z N4. An implementation-detail pin protecting Spec-AC-02's frozen-file mechanism where G1 legitimately touches a file two OTHER frozen specs already pin byte-unchanged: SPEC-0131/CHANGE-0143 D5 and SPEC-0129/CHANGE-0142 D5, both cited in the Links section.)
- Spec-AC-09: WHEN `close-work-item.mjs`'s sha256 content hash is not one of
  the entries in `tests/skills/lib/close-work-item-pin.sh`'s
  `CLOSE_WORK_ITEM_ALLOWED_HASHES` THEN both consuming suites
  (`tests/skills/test-aai-follow-ups.sh` TEST-008,
  `tests/skills/test-aai-doc-numbering.sh` TEST-029) fail closed naming the
  mismatched hash; WHEN the file is absent THEN both fail closed as ABSENT;
  WHEN the check returns anything other than the three closed statuses
  (OK/ABSENT/MISMATCH) THEN the callers fail closed too — never silently
  treat an unrecognized status as success. Corrected at remediation (N-B):
  the OK-vs-ABSENT/MISMATCH/unrecognized assertion is hoisted into ONE
  function, `close_work_item_pin_assert` (same library), that BOTH callers
  delegate to in a single line, rather than each caller carrying its own
  copy of the if/elif chain — the ORIGINAL per-caller copy was proven to
  survive its own deletion once N1's static pin (a grep for the literal
  `!= "OK"` in the caller's extracted source) had nothing behavioural left
  to check but a comment mentioning that literal.
- Verification: edit `close-work-item.mjs` by one byte in an isolated copy and re-run both consuming suites — MISMATCH naming the new hash, both fail; delete the file — ABSENT, both fail; add a junk hash beside the valid entries — OK, unaffected; a stubbed `close_work_item_pin_check` returning empty output with exit 0 (the gutted-function shape), shadowed over the real one, makes the REAL `close_work_item_pin_assert` return 1, not 0 (`tests/skills/test-aai-follow-ups.sh` test_010) — a behavioural pin on the single shared guard, not a textual grep on caller source.

## Constitution deviations

None. (Checked against docs/CONSTITUTION.md v1 articles 1-7. Article 1: every
AC above names one command and one observable, and both TDD-lane guards have a
stored RED before their GREEN. Article 2: no new script, no new file, no new
abstraction — G2 reuses the CHANGE-0120 event pattern rather than inventing a
second one, and G1 reuses the git shelling already present in the file.
Article 3: every artifact is a plain git-diffable file or an mktemp fixture.
Article 4: all three git-dependent paths degrade to silence with an explicit
fail-open rationale, and the dispatch advisory fail-opens on undefined
snapshot fields. Article 5: additive at every boundary — no exit code, no CLI
flag, no output-format change on any non-stale path, and the new event type is
inert to every existing consumer. Article 6: this planning pass does not write
docs/ai/STATE.yaml; the orchestrator records phase and strategy through
state.mjs. Article 7: no merge is performed.)

## Acceptance Criteria Status

| Spec-AC    | Description                                                                 | Status  | Evidence | Review-By | Notes |
|------------|-----------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | G1 post-merge close warning fires exactly once per invocation on the merged-order fixture, zero times on open-PR order, zero times when git cannot resolve an upstream ref, and zero times under --dry-run | done | tests/skills/test-aai-close-work-item.sh TEST-001/002 (test_047/048, dry-run control added at remediation N7); docs/ai/tdd/red-20260816T072740Z-g1-post-merge-close.log; docs/ai/tdd/green-20260816T074304Z-test-aai-close-work-item-suite.log | —         | token `post-merge-close`; git predicate, never the PR API (D1) |
| Spec-AC-02 | G1 changes neither exit code nor stdout on either path                       | done | tests/skills/test-aai-close-work-item.sh TEST-003 (test_049, pre-change baseline now a PINNED blob sha, not `git archive HEAD` — B2 fix), pre/post-change stdout+exit cmp; docs/ai/tdd/green-20260816T074304Z-test-aai-close-work-item-suite.log | —         | warning goes to stderr beside the existing gate warnings; test_049 no longer self-destructs on the delivery commit (B2) |
| Spec-AC-03 | G2 records one `validation_verdict` event under `--confirm` whose hash equals the reported tree_hash, idempotently, and writes nothing without the flag; re-stamps on a NEWER recorded verdict rather than latching to the first observation forever (corrected at remediation, B-1); a same-second verdict compares as NOT newer (corrected at remediation, BLOCKING-1) | done | tests/skills/test-aai-orchestration-dispatch.sh TEST-004 (test_039, extended at remediation B-1 with the re-stamp arm, extended again at remediation BLOCKING-1 with the same-second boundary arm); docs/ai/tdd/red-20260816T072959Z-g2-validation-verdict-stale.log; docs/ai/tdd/green-20260816T074746Z-test-aai-orchestration-dispatch-suite.log; docs/ai/tdd/red-20260816T193521Z-b1-stamp-refresh.log; docs/ai/tdd/green-20260816T193521Z-b1-stamp-refresh.log; docs/ai/tdd/red-20260816T205033Z-blocking1-same-second-boundary.log; docs/ai/tdd/green-20260816T205033Z-blocking1-same-second-boundary.log | —         | EVENTS storage, not `last_validation` (D2); no protected surface; stamp condition compares `last_validation.run_at_utc` against the stamped event's `ts` as `Date.parse` instants, not existence and not lexicographic string order (B-1, BLOCKING-1) |
| Spec-AC-04 | G2 reports a stale verdict mechanically when the tracked tree moved under a recorded pass (outside TREE_HASH_EXCLUDE_PATHS) that STATE's `last_validation.status` ALSO still calls pass for the SAME ref (corrected at remediation, N-4; ref corroboration added at remediation, external review PR #261 F2), and stays silent otherwise or on any null; a re-stamped verdict clears a latched advisory on the following tick (corrected at remediation, B-1); a genuinely stale advisory keeps firing on every tick rather than self-clearing (corrected at remediation, BLOCKING-1); the tree-hash diff input no longer loses a quoted-path file's content to a leaked exclusion-skip flag (corrected at remediation, external review PR #261 F1) | done | tests/skills/test-aai-orchestration-dispatch.sh TEST-005/006 (test_040/041, TEST-006 extended at remediation N-4 with the STATE-no-longer-pass control, extended again at remediation PR #261 F2 with the mismatched-ref control) + TEST-011 (test_043, added at remediation B1: a TRACKED-EVENTS.jsonl fixture proves the --confirm stamp no longer self-invalidates) + TEST-013 (test_044, added at remediation B4: a content-only edit inside an already-dirty tracked file now trips the advisory, the same shape inside an excluded ledger stays silent) + TEST-014 (test_045, added at remediation PR #261 F1: a git-quoted path sorting after an excluded ledger no longer loses its content-only edit) + TEST-004 (test_039, extended at remediation B-1: the advisory clears one tick after a re-stamp; extended again at remediation BLOCKING-1: the advisory keeps firing at the same-second boundary rather than self-clearing); docs/ai/tdd/red-20260816T072959Z-g2-validation-verdict-stale.log; docs/ai/tdd/green-20260816T074746Z-test-aai-orchestration-dispatch-suite.log; docs/ai/tdd/red-20260816T181554Z-test013-b4-suite.log; docs/ai/tdd/green-20260816T181554Z-test013-b4-suite.log; docs/ai/tdd/red-20260816T181554Z-test011-b1-exclusion-retroactive.log (N3 retroactive RED for the B1-round TEST-011 assertion); docs/ai/tdd/red-20260816T193521Z-b1-stamp-refresh.log; docs/ai/tdd/green-20260816T193521Z-b1-stamp-refresh.log (code-review B-1: the stale advisory that latched permanently ON after the first remediation now clears); docs/ai/tdd/red-20260816T205033Z-blocking1-same-second-boundary.log; docs/ai/tdd/green-20260816T205033Z-blocking1-same-second-boundary.log; docs/ai/tdd/red-20260816T205033Z-n4-advisory-state-corroboration.log; docs/ai/tdd/green-20260816T205033Z-n4-advisory-state-corroboration.log; docs/ai/tdd/red-20260817T074735Z-f1-filterdiff-quotedpath.log; docs/ai/tdd/green-20260817T074735Z-f1-filterdiff-quotedpath.log (PR #261 F1, captured against a disposable rsync copy per SUBAGENT_CONTRACT isolation, never against this repository); docs/ai/tdd/red-20260817T074736Z-f2-stale-advisory-ref-corroboration.log; docs/ai/tdd/green-20260817T074736Z-f2-stale-advisory-ref-corroboration.log (PR #261 F2, same isolation); docs/ai/tdd/green-20260817T075046Z-orchestration-dispatch-full-suite.log (full 45-arm suite green in-repo post-fix, non-regression) | —         | token `validation_verdict_stale`; detection is pure inside decide(); the exclusion list lives beside computeTreeHash AND now also filters the `git diff HEAD` content input (B4); maxBuffer raised 16 -> 64 MB (N-C); advisory now requires STATE and the last stamp to AGREE a pass verdict is standing for the SAME ref (N-4, PR #261 F2); filterExcludedDiff resets its skip flag on every diff header including unparseable ones (PR #261 F1) |
| Spec-AC-05 | G2 is report-only — rule, verdict, role, reasons and exit code unchanged, JSON additive-only in the stale case, and additive-only (modulo tree_hash/last_validation_verdict) in the non-stale case | done | tests/skills/test-aai-orchestration-dispatch.sh TEST-007 (test_042, extended at remediation B3 with the real pre-change-vs-post-change cmp the spec names, against a pinned blob sha); docs/ai/tdd/green-20260816T074746Z-test-aai-orchestration-dispatch-suite.log; docs/ai/tdd/red-20260816T181554Z-test007-b3-cmp-retroactive.log and docs/ai/tdd/green-20260816T181554Z-test007-b3-cmp-retroactive.log (N3 retroactive RED/GREEN for the B3-round cmp extension) | —         | non-stale stdout additive-only relative to the pre-change tree (AC reworded, B3); the JSON.stringify-equality overclaim removed and D2's report-only paragraph brought into agreement (N2/N2b); code-review NB-1: the comment repeating the retracted byte-identity claim + `test_033` citation corrected to cite test_042/Spec-AC-05 instead; B-1's `validationRunAtUtc` is returned as a sibling of `snapshot`, deliberately kept OFF `state_summary` so this AC's two-key modulo stays exactly two |
| Spec-AC-06 | G3 sweep RECOMMENDED (not a standing REQUIRED rule — corrected at remediation, Q4) present in SKILL_TDD Phase 4, tied to ceremony level 2 and 3, with the named did-not-run statement and fail-closed-to-2 | done | tests/skills/test-aai-tdd.sh TEST-008 (test_g3_sweep_gate_prompt_contract, grep contract updated at remediation Q4 from REQUIRED/NOT required to RECOMMENDED/NOT recommended); docs/ai/tdd/red-20260816T073650Z-g3-g4-prompt-tokens.log; docs/ai/tdd/green-20260816T073653Z-test-aai-tdd-suite.log; docs/ai/tdd/green-20260816T193521Z-q4-g3-recommendation.log (Q4 re-wording GREEN) | —         | conditionality ruled in D3 on the counted ride mix; demoted REQUIRED -> RECOMMENDED at remediation because D3's break-even arithmetic was self-refuting and its cost model omitted that VALIDATION.prompt.md already mandates the identical full sweep one role later at the same L2/L3 population |
| Spec-AC-07 | G4 teaches the disk-artifact poll naming the completion token, states that existence is not completion, and no `.aai/**` file matches `OUTPUT_STREAM_WAIT_RE` (narrowed at remediation, N-A, from an unsubstantiated universal-negative claim) | done | tests/skills/test-aai-prompt-diet.sh TEST-009 (test_020); docs/ai/tdd/red-20260816T073650Z-g3-g4-prompt-tokens.log; docs/ai/tdd/green-20260816T073851Z-test-aai-prompt-diet-suite.log | —         | prose-only outcome, ruled in D4 after checking the corpus; regex is polarity-blind and narrow (three of four realistic offender phrasings evade it, plus a correct prohibition would false-positive) — widening tracked under `fu-test020-corpus-regex-thin`, not claimed by this AC |
| Spec-AC-08 | Prompt-corpus governance true-up — combined growth at most 900 B, ledger entry credited 1:1, TEST-012 pin at -3747 plus growth | done | tests/skills/test-aai-prompt-diet.sh TEST-010/012 (test_012_growth_sum_matches_ledger); pin -2918 (corrected at remediation, N-2, validation-20260816T203700Z — was cited -2919); docs/ai/tdd/green-20260816T073851Z-test-aai-prompt-diet-suite.log | —         | no line cap applies to either edited prompt |
| Spec-AC-09 | Shared close-work-item.mjs content-hash pin fails closed on mismatch/absence in both consuming suites, tolerates an inert extra entry, and its callers assert the positive OK status via one shared, hoisted guard (corrected at remediation, N-B) | done | tests/skills/test-aai-follow-ups.sh TEST-008 (test_008_close_path, now one line delegating to close_work_item_pin_assert) + TEST-010 (test_010_pin_ok_assertion_catches_gutted_check, re-written at remediation N-B to shadow close_work_item_pin_check and drive the REAL close_work_item_pin_assert, superseding N1's literal-grep static pin); tests/skills/test-aai-doc-numbering.sh TEST-029 (test_029_close_work_item_byte_unchanged, also one line); docs/ai/tdd/green-20260816T140003Z-spec-ac09-pin-mechanism.log; docs/ai/tdd/red-20260816T181554Z-n1-pin-caller-source.log and docs/ai/tdd/green-20260816T181554Z-n1-pin-caller-source.log (N1 RED/GREEN, mutation M9 against the real caller — the round this remediation's N-B hoist supersedes); declared at remediation, N4 | —         | tests/skills/lib/close-work-item-pin.sh — the one new file this scope adds (test-support, mirrors SPEC-0060's prompt-diet-ledger.sh); close_work_item_pin_assert() is the single hoisted guard both real callers delegate to (N-B, code-review finding) |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:

- `.aai/scripts/close-work-item.mjs` — one resolver for the upstream default
  ref and one ancestor predicate, both fully try-wrapped to silence, called
  ONCE in `main()` before the pre-write phase; one `console.error` line. No
  change to argument parsing, to the mutation path, to the self-verify or to
  any exit code.
- `.aai/scripts/append-event.mjs` — `'validation_verdict'` added to the
  `EVENT_TYPES` set and one `case` requiring `--status` and `--hash`,
  mirroring the `phase_confirmed` case beside it. Header comment updated.
- `.aai/scripts/orchestration-dispatch.mjs` — `buildSnapshot` gains
  `tree_hash` (sha256 over `git rev-parse HEAD` plus
  `git status --porcelain=v1 -uno`, null on any failure) and
  `last_validation_verdict`, the latter collected inside the EXISTING EVENTS
  loop at line ~700 that already harvests `work_item_closed` and
  `phase_confirmed`, so no extra file read. `decide()` gains the pure
  comparison setting the additive `advisories` key. `main()` gains the stderr
  line and, under `--confirm`, the stamp through a `recordConfirm`-shaped
  delegation. The `usage()` text's read-only sentence is widened to name both
  writes the flag now permits. `computeTreeHash` also gains
  `TREE_HASH_EXCLUDE_PATHS`, an itemized denylist of tracked, append-only
  telemetry/generated ledgers stripped from the `git status` output before
  hashing (declared at remediation, B1 — see D2 and Spec-AC-04).
- `tests/skills/lib/close-work-item-pin.sh` (NEW — declared at remediation,
  N4; see Spec-AC-09) — a pure, sourceable test-support library unifying two
  independently frozen byte-diff-empty pins on `close-work-item.mjs`
  (SPEC-0131/CHANGE-0143 D5, SPEC-0129/CHANGE-0142 D5) into one shared
  content-hash allowlist, consumed by both
  `tests/skills/test-aai-follow-ups.sh` and
  `tests/skills/test-aai-doc-numbering.sh`. Mode 644, no `set -u`, no `cd`,
  bash-3.2 safe — same discipline as `tests/skills/lib/prompt-diet-ledger.sh`
  (SPEC-0060).
- `.aai/SKILL_TDD.prompt.md` — Phase 4 gains the sweep requirement with its
  ceremony-level condition and the named did-not-run form.
- `.aai/SKILL_TEST_SKILLS.prompt.md` — the disk-artifact poll teaching with the
  completion token and the existence-is-not-completion sentence.
- `tests/skills/test-aai-close-work-item.sh`,
  `tests/skills/test-aai-orchestration-dispatch.sh`,
  `tests/skills/test-aai-tdd.sh`, `tests/skills/test-aai-prompt-diet.sh` — new
  arms only, appended after each suite's current last arm and wired into
  `main()` (hygiene test_093 fails an unwired function).
- `tests/skills/test-aai-follow-ups.sh`, `tests/skills/test-aai-doc-numbering.sh`
  (declared at remediation, N3/N4) — TEST-008 / TEST-029 switched from their
  own independent pin logic to `close_work_item_pin_check` against the new
  shared library, and each gains an OK-status assertion (N1); the follow-ups
  suite also gains ONE new arm, test_010, regression-pinning that assertion.
- `tests/skills/lib/prompt-diet-ledger.sh` — one `JUSTIFIED_ADDITIONS` entry.
- `CHANGELOG.md` — one `## [unreleased] — <title>` heading, per-entry heading
  form, never bullets under the scaffold.

Data flows and seams (each crossed by a named test):

- SEAM-1 `append-event.mjs` event vocabulary to `orchestration-dispatch.mjs`'s
  reader: the writer and the reader agree on the string `validation_verdict`
  and on the payload key `hash` across a process boundary. A rename on one side
  silently disarms the whole guard while unit tests on either side stay green.
  Crossed by TEST-004, which drives the real dispatch CLI to WRITE the event
  and then a second real dispatch run to READ it — never a hand-written fixture
  line.
- SEAM-2 the hash producer to the hash comparator: both sides must be the same
  function, or the advisory fires forever. Crossed by TEST-004's equality
  assertion between the appended `payload.hash` and the run's reported
  `tree_hash`, and by TEST-006's unmutated control which must stay silent.
- SEAM-3 the new `validation_verdict` line to every existing EVENTS consumer:
  `docs-audit-core.mjs`, the close ceremony's self-verify and rule 4b all read
  the same log. Crossed by TEST-007, which runs
  `node .aai/scripts/docs-audit.mjs --check --strict --no-event` over a repo
  whose EVENTS carries the new line and asserts the verdict is unchanged.
- SEAM-4 the edited prompts to the diet ledger's byte floor: the added bytes
  are inside TEST-010's live glob and will make main red the moment they land.
  Crossed by TEST-010.
- SEAM-5 `close-work-item.mjs`'s new git calls to its existing hermetic
  fixtures: the suite's fixture repos must gain a remote and an `origin/main`
  ref, or every new arm silently takes the fail-open path and proves nothing.
  Crossed by TEST-001's non-vacuity assertion that the merged-order fixture
  actually produces the warning.

Edge cases:

- Pair close (two refs, one invocation): one warning, not two (TEST-001).
- Fixture repo with no remote at all: silence, exit code unchanged (TEST-001).
- `origin/HEAD` unset but `origin/main` present: resolver falls through to the
  literal, warning still fires.
- A repo whose default branch is `master`: third resolver arm.
- Dispatch run outside a git repository: `tree_hash` is null, no stamp is
  written under `--confirm` and no advisory is emitted.
- EVENTS carrying a malformed `validation_verdict` line: the existing
  try/catch in the scan loop skips it, leaving the guard inert rather than
  crashing the tick.
- Two `validation_verdict` events for one ref: last wins, matching the
  `phase_confirmed` precedent in the same loop.
- A ride whose ceremony level is absent from the spec: G3's prompt instructs
  fail-closed to 2, so the sweep is required.

Residual risks (written down, not silently accepted):

- RR-1: G2's stamp window (D2) leaves tracked changes between the validator
  finishing and the next tick invisible. Bounded to seconds on a normal tick,
  and — corrected at remediation, B-1 — that bound now holds on EVERY
  validation round, not only the first: the stamp is per-verdict (compares
  `last_validation.run_at_utc` against the last stamped event's `ts`), so a
  re-validation after remediation re-opens a fresh few-second window instead
  of leaving the guard pinned to a remediation-old reference indefinitely.
  Closing the window entirely means a validator-side write, which means a
  prompt change and a second definition of the hash — deliberately not paid
  here.
- RR-2: G2 warns on ANY tracked movement outside `TREE_HASH_EXCLUDE_PATHS`
  (D2, B1 fix), not on RELEVANT movement (D5.3). Over-firing is the realistic
  failure mode and the reason the guard is stderr-only and never a gate.
  Scoping the hash to the spec's review-scope list is the named follow-up if
  the noise proves real. Also residual after B1: `TREE_HASH_EXCLUDE_PATHS`
  filters the `git status --porcelain` LINES and (after B4) the `git diff
  HEAD` per-file blocks, so an uncommitted append to an excluded ledger is
  invisible to the hash on BOTH inputs, but a COMMIT whose tree includes one
  of those paths still moves `git rev-parse HEAD` and therefore `tree_hash`
  — e.g. a commit that mixes a real code change with a
  `docs/ai/EVENTS.jsonl` update still correctly trips the guard (the code
  change is real movement), but a hypothetical commit touching ONLY an
  excluded ledger would too. Not fixed here: excluding committed history
  needs a tree-object comparison ignoring named paths, which is materially
  more machinery than the porcelain-line/diff-block filter above and was not
  needed to make B1's specific proof ("stamp, then dispatch again with
  nothing else changed") hold, since the stamp itself never commits. Also
  residual after B4: a tracked file edited and then reverted to
  byte-identical content between ticks still yields the SAME hash both
  sides of the round trip (`git diff HEAD` output is a function of current
  content vs `HEAD`, not of history), so a "moved and moved back" tree stays
  invisible exactly as D5.4 already recorded.
- RR-3: G3's benefit is one data point (D3). The corrected 1-in-4.3 break-even
  is an estimate, not a measurement, and the recommendation should be
  re-examined once several L2 rides have run under it — including whether it
  should ever become a standing rule, given Validation already runs the same
  sweep one role later. The L0/L1 exemption does not depend on that estimate.
- RR-4: G3 and G4 are carried entirely by prompt compliance. A role that
  ignores the prompt defeats both, and no test in this scope can detect that.
- RR-5: G1's ancestor predicate needs a fetched upstream ref. A stale
  `origin/main` in a long-lived clone can miss a merge that happened remotely,
  producing a false silence. Fail-open by design; refreshing the ref would mean
  a network call, which D1 rules out.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                             | Description                                                                 | Status  |
|----------|------------|-------------|--------------------------------------------------|-----------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-close-work-item.sh         | merged-order fixture where the delivery commit is already an ancestor of origin/main produces exactly one `post-merge-close` stderr line naming the sha, the ref and the PR number, and the pair-close variant still produces exactly one | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-close-work-item.sh         | negative controls: open-PR-order fixture with the commit only on the feature branch produces zero lines, a fixture with no remote at all also produces zero lines rather than an error, and a merged-order fixture re-run with `--dry-run` also produces zero lines (N7 dry-run carve-out) | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-close-work-item.sh         | exit code and full stdout captured on all three fixtures are identical to captures taken on the pre-change tree, proving the warning is stderr-only and exit-code-neutral on both paths | green |
| TEST-004 | Spec-AC-03, Spec-AC-04 | integration | tests/skills/test-aai-orchestration-dispatch.sh  | real dispatch CLI with `--confirm` on a pass verdict appends exactly one `validation_verdict` line whose `payload.hash` equals the same run's reported `tree_hash` and whose `payload.status` is pass; a second identical tick appends nothing; a run without `--confirm` appends nothing; added at remediation (B-1): mutate a tracked file and confirm the stale advisory fires, then record a validation round NEWER than the last stamp (a later `last_validation.run_at_utc`) and prove a SECOND `--confirm` tick appends a second `validation_verdict` line and the advisory clears on the following tick — the stamp is per-verdict, not per-ref-forever; added at remediation (BLOCKING-1): set `last_validation.run_at_utc` to the truncated second of the last stamp's own `ts` (never a hand-picked date) and prove a further `--confirm` tick appends nothing, and that a genuine tracked mutation at this boundary keeps producing the stale advisory on EVERY subsequent `--confirm` tick rather than self-clearing after one | green |
| TEST-005 | Spec-AC-04 | integration | tests/skills/test-aai-orchestration-dispatch.sh  | after mutating one TRACKED file, a second real dispatch run prints exactly one stderr `validation_verdict_stale` line naming the focus ref, both with and without `--human`, with no agent input | green |
| TEST-006 | Spec-AC-04 | unit        | tests/skills/test-aai-orchestration-dispatch.sh  | silence controls: unmutated tree yields zero stale lines; a snapshot passed to the exported `decide()` with the two new fields absent yields no `advisories` key; a null `tree_hash` yields none either; added at remediation (N-4): a snapshot whose `validation.status` is `not_run` but whose stale stamped event still says `status: pass` with a mismatched hash yields no `advisories` key either; added at remediation (external review, PR #261 F2): a snapshot whose `validation.status` is `pass` but whose `validation.ref_id` names a DIFFERENT ref than `focus.ref_id` yields no `advisories` key either, even with mismatched hashes -- `withStaleAdvisory` must corroborate the ref, not only the status | green |
| TEST-007 | Spec-AC-05 | integration | tests/skills/test-aai-orchestration-dispatch.sh  | report-only proof: stale and non-stale runs agree on rule, verdict, role, reasons and exit code, their stdout differs only by `advisories`; separately, the SAME fixture run through the pinned pre-change `orchestration-dispatch.mjs` blob and the current script produce byte-identical stdout once `tree_hash`/`last_validation_verdict` are deleted from the current run's `state_summary` (the real `cmp` Spec-AC-05 names, added at remediation — B3); `docs-audit.mjs --check --strict --no-event` over the repo carrying the new event type returns its unchanged verdict | green |
| TEST-008 | Spec-AC-06 | unit        | tests/skills/test-aai-tdd.sh                     | grep contracts over `.aai/SKILL_TDD.prompt.md` Phase 4: the sweep recommendation, the literal ceremony levels 2 and 3 as RECOMMENDED, 0 and 1 as exempt (reworded at remediation, Q4, from REQUIRED/NOT required), the named did-not-run statement form, and the absent-level-is-2 instruction each present exactly once | green |
| TEST-009 | Spec-AC-07 | unit        | tests/skills/test-aai-prompt-diet.sh             | `.aai/SKILL_TEST_SKILLS.prompt.md` names `summary.txt`, the completion literal `AAI Skills Test Summary` and the existence-is-not-completion sentence; a corpus scan of `.aai/**` for the `OUTPUT_STREAM_WAIT_RE` pattern returns zero hits, and the same scan over a synthetic fixture carrying that phrasing returns non-zero, proving the pin bites (AC narrowed to this one pattern at remediation, N-A — not a proven universal negative over all possible phrasings) | green |
| TEST-010 | Spec-AC-08 | unit        | tests/skills/test-aai-prompt-diet.sh             | combined measured growth of the two prompts is at most 900 B, the new `JUSTIFIED_ADDITIONS` entry names both files with their measured deltas, and the TEST-012 pin equals -3747 plus that growth and equals an independent re-sum of the array | green |
| TEST-011 | Spec-AC-04 | integration | tests/skills/test-aai-orchestration-dispatch.sh  | added at remediation (B1): on a fixture whose `docs/ai/EVENTS.jsonl` is TRACKED before the first `--confirm` tick (mirroring this repo, unlike every other G2 fixture), stamp once then re-dispatch twice more with nothing else changed — zero `validation_verdict_stale` lines on either later tick, and a later `--confirm` tick still appends no second `validation_verdict` line | green |
| TEST-012 | Spec-AC-09 | unit        | tests/skills/lib/close-work-item-pin.sh | declared at remediation (N4): the shared content-hash allowlist fails closed (MISMATCH naming the hash, or ABSENT) in both consuming suites (test-aai-follow-ups.sh test_008_close_path, test-aai-doc-numbering.sh test_029_close_work_item_byte_unchanged) when close-work-item.mjs is edited or deleted, tolerates an inert extra allowlist entry, and (test-aai-follow-ups.sh test_010) the single hoisted guard, close_work_item_pin_assert, asserts the POSITIVE OK status rather than denylisting the two known failures, so a gutted check function returning empty status with exit 0 is rejected too — driven directly by shadowing close_work_item_pin_check and calling the REAL close_work_item_pin_assert (N-B, corrected at remediation from N1's literal-grep static pin on caller source, superseded because a comment could satisfy that grep after the real guard's deletion) | green |
| TEST-013 | Spec-AC-04 | integration | tests/skills/test-aai-orchestration-dispatch.sh  | added at remediation (B4, validation-20260816T143000Z): a tracked file dirtied ONCE before the stamp (status letter " M" fixed for the whole arm), stamped while already dirty, then edited a SECOND time with the SAME status letter but different bytes -- exactly one `validation_verdict_stale` line naming the focus ref, proving the hash now moves on content alone; the same shape inside a `TREE_HASH_EXCLUDE_PATHS` entry (`docs/ai/EVENTS.jsonl`) stays at zero, proving the B1 exclusion still holds on the new diff-content input | green |
| TEST-014 | Spec-AC-04 | integration | tests/skills/test-aai-orchestration-dispatch.sh  | added at remediation (external review, PR #261 F1): a tracked, git-QUOTED path (non-ASCII byte, core.quotepath default on) sorting immediately after an excluded ledger (`docs/ai/EVENTS.jsonl`) in diff order is dirtied once, stamped while dirty, then edited a SECOND time with the SAME status letter but different bytes -- exactly one `validation_verdict_stale` line naming the focus ref, proving `filterExcludedDiff` no longer leaks the excluded ledger's skip state across the unparseable quoted header into the quoted file's own (non-excluded) diff block | green |

RED plan (hybrid; every RED observed BEFORE its GREEN work, and STORED with
`RED_CLASS:` written as line 1 AT CAPTURE for the TDD-lane arms — `product_red`
when the planted input reaches the assertion, `infra_fail` otherwise, per
`.aai/SKILL_TDD.prompt.md`):

- TEST-001/002/003 RED (TDD lane, stored): run the pre-change
  `close-work-item.mjs` against the merged-order fixture. Observed result is a
  clean close with an EMPTY stderr where the warning belongs — the silence IS
  the defect, captured verbatim together with the exit code and stdout that
  TEST-003 later pins.
- TEST-004/005/006/007 RED (TDD lane, stored): run the pre-change dispatch with
  `--confirm` on the pass fixture. Observed result is no `validation_verdict`
  line in EVENTS; then mutate a tracked file and re-run — observed result is no
  advisory and no stderr line. Both captured.
- TEST-008 RED (loop lane): `grep -c` for the sweep tokens in the pre-change
  `.aai/SKILL_TDD.prompt.md` returns 0.
- TEST-009 RED (loop lane): `grep -c` for the literal `AAI Skills Test Summary`
  and for `summary.txt` in the pre-change
  `.aai/SKILL_TEST_SKILLS.prompt.md` returns 0. Stated honestly: the corpus-scan
  HALF of this arm is already green on the pre-change tree (D4 measured zero
  offending hits), so it is a REGRESSION PIN with no RED of its own — the
  synthetic-fixture bite check is what proves it is not vacuous.
- TEST-010 RED (loop lane): arises mechanically — the pin is -3747 before the
  prompt bytes land and the suite fails on the measured growth until the ledger
  entry is added.
- TEST-013 RED (TDD lane, stored — added at remediation, B4): run the
  pre-B4-fix `computeTreeHash` (status-only, no `git diff HEAD` fold-in)
  against the fixture in D2's B4 correction — a tracked file dirtied once,
  stamped, then edited again with the SAME status letter. Observed result is
  zero `validation_verdict_stale` lines where the arm expects one — the
  silence IS the defect. Captured, together with the GREEN capture after the
  fix, under `docs/ai/tdd/`.
- N3 (validation-20260816T143000Z): the three assertions the PRIOR
  remediation round added had no stored RED artifact of their own — TEST-011
  (`test_043`, the B1 exclusion filter), TEST-010 (`test_010`'s OK-status
  guard, N1's own subject before this round's fix), and TEST-007's real
  pre/post-change `cmp` extension (B3). All three are now captured
  retroactively by re-applying the ORIGINAL reverting mutations named in the
  round-2 validation report (M1, M9, M12) against a disposable copy and
  storing the resulting RED/GREEN pairs under `docs/ai/tdd/`.

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-close-work-item.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-orchestration-dispatch.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-tdd.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh`
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
- `node .aai/scripts/spec-lint.mjs`
- Full framework sweep once before reporting done — this scope's own G3 rule
  applied to itself, and at ceremony_level 2 the rule recommends it
  (corrected at remediation, Q4: RECOMMENDED, not REQUIRED — see D3):
  `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh`
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
For each implementation, validation, TDD and code review artifact, record:
- ref_id: role-verification-guards
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (docs/ai/tdd/ for the stored RED artifacts of TEST-001..007 per
  the hybrid strategy; `RED_CLASS:` stamped as line 1 at capture)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
