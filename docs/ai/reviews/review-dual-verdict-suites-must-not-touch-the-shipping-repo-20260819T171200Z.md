# Code Review (delta re-review) — suites-must-not-touch-the-shipping-repo

```yaml
review:
  scope: >-
    working-tree diff against main (HEAD 4fb5c6087ac20b1759a2ebbb8cc00c210a0e5e12):
    .aai/scripts/lib/repo-tripwire.sh (new, untracked),
    tests/skills/test-aai-repo-tripwire.sh (new, untracked),
    .aai/scripts/aai-run-tests.sh, .aai/system/PROFILES.yaml,
    tests/skills/test-framework.sh, tests/skills/test-aai-doc-numbering.sh,
    tests/skills/test-aai-deslop.sh, tests/skills/test-aai-spec-lint.sh,
    tests/skills/suite-map.yaml, plus the two DRAFT docs
  spec: docs/specs/SPEC-0137-spec-suites-must-not-touch-the-shipping-repo.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-001/TEST-002 green in a full 12-arm control run; independently reproduced — fixture fx, unlisted suite after an ALLOWED writer to the same ratchet path FAILs [TRIPWIRE], framework exit 1. The Spec-AC-06 mechanism no longer defeats it." }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-007 green; .aai/scripts/aai-run-tests.sh:104-133 arm + not-armed NOTE, :276-292 report on every exit path with the exit code untouched. Unchanged since the last pass." }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-006 green; the whole 12-arm suite left the copy's tree at 0 changed paths (git status --porcelain=v1 | wc -l = 0 before and after)." }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-003/TEST-009/TEST-010 green; tests/skills/test-framework.sh:425-465 tri-state attestation. See BLOCKING-3: the attestation itself is right, it is the Spec-AC-06 stale-drain that ignores it." }
      - { ac: Spec-AC-05, call: compliant,
          citation: "TEST-004 green — 6 status calls over 3 suites through the PATH shim, unchanged by the hashing (the hash is a plain read, no git call); TEST-005 green." }
      - { ac: Spec-AC-06, call: non-compliant,
          citation: "The row's own clause 'an entry whose suite RAN and came back clean is printed as stale' is false as shipped: a ratchet suite that exits 42 — reported by the framework on its own line as 'NOT ATTESTED — suite skipped (exit 42), it never ran' — has its entry printed STALE four lines later with 'it changed nothing in this run … close the item and delete the entry'. Measured, fixture fxD. See BLOCKING-3. Everything else in the row now holds: BLOCKING-1 is closed and reproduced closed." }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-framework.sh, line: 621,
          issue: "The stale-drain loop keys on `tw_state == clean` alone and never consults `tw_attested`, which run_test computed for exactly this distinction (D3: clean never means verified). A ratchet suite that SKIPPED (exit 42) or CRASHED touches nothing, is therefore trivially clean, and its live entry is printed STALE with an unconditional assertion — 'it changed nothing in this run' — plus an operator instruction to close the filed registry item and delete the entry. The remediation made this claim STRONGER rather than conditional: the line now adds 'and for the ratchet's own paths that is a CONTENT verdict, not merely an unmoved git status class', which is a claim about evidence the run did not gather. In the no-hasher degrade the same sentence is emitted while TRIPWIRE_HASH_DEGRADED is true and two lines above it the framework has just warned that the ratchet paths were compared by status class only.",
          failure_scenario: "Fixture fxD, byte copy of the shipped framework and library, clean throwaway repo: test-aai-state.sh exits 42, test-aai-metrics.sh exits 3. Output contains, in one run — `aai-state SKIP [tripwire NOT ATTESTED — suite skipped (exit 42), it never ran]` and `STALE ratchet entry 'aai-state' (fu-state-suite-writes-real-index) — it changed nothing in this run … close the item and delete the entry`, likewise for aai-metrics. Reproduced a second time with the REAL suites: on a clean copy of this repository, aai-hitl-propagation and aai-state each failed early (exit 1) and both live entries were printed STALE. Skips are a first-class contract in this framework (exit 42) and are the ordinary CI condition for env-dependent suites, so this fires on green-ish real runs, not only on crashes. Consequence: two P2 registry items get closed as fixed while the defect stands, and two live guard entries are deleted. Fix: gate the loop on `tw_attested`, and gate the CONTENT-verdict clause on TRIPWIRE_HASH_DEGRADED." }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 397,
          issue: "The path-subset test that bounds a ratchet entry ('an entry is not blanket permission for the suite that holds it') is only as good as the status comparison for every path the table does NOT name. The hashing closed D7 for the three ratchet paths; the subset test still reads non-ratchet paths through `aai_tripwire_changed_paths`, which is blind to a path that was already dirty when the suite started. An allowlisted suite that also writes such a path is reported ALLOWED 'inside its listed path(s)' — an affirmative claim that is false — and the run stays green.",
          failure_scenario: "Fixture fxC, clean framework byte copy, tree carrying one pre-existing local edit (`M docs/other.md`, the ordinary state of a dev checkout — this repository's own tree has 13 modified files right now). test-aai-metrics.sh appends to docs/ai/overview.html (listed) AND to docs/other.md (not listed). Result: `PASS [tripwire ALLOWED … inside its listed path(s)]`, framework exit 0, no failure line, and the out-of-entry write landed. On a CLEAN start the residue is bounded — I verified in fixture fxD2 that the only way to pre-dirty a non-ratchet path is an earlier suite that already failed the run, so a clean-start run is already red when this bites — but nothing in D7, D8, Spec-AC-06 or the ALLOWED block states that the entry bound is unenforceable for already-dirty paths. The framework holds tw_before and can name the already-dirty set; the previous review's option (a) is the complement of the hashing, not its rejected alternative." }
      - { rank: NON-BLOCKING, file: tests/skills/suite-map.yaml, line: 572,
          issue: "Carried over unremediated from the previous pass: the aai-repo-tripwire row still omits tests/skills/test-aai-spec-lint.sh and .aai/system/PROFILES.yaml, both changed by this scope.",
          failure_scenario: "A later PR editing only test-aai-spec-lint.sh's mirror logic does not select aai-repo-tripwire, so the guard's own suite never runs against a change to a suite it guards. Already filed as fu-suite-map-tripwire-row-incomplete (P3) — noted as still open, not re-litigated." }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 493,
          issue: "Carried over unremediated: a suite that both fails on its own exit code and trips the tripwire is routed to the `tripwire)` branch, so the failure-lines-plus-tail dump is not printed.",
          failure_scenario: "Filed as fu-tripwire-fail-hides-suite-log-tail (P2). Observed live in my four-suite real run: aai-state FAILed on its own exit 1 and the tail was printed because the tripwire read clean; had it also written, the diagnosis would have been lost. Noted as still open." }
  cannot_verify:
    - { claim: "The full 80-suite framework aggregate on the post-remediation tree (reported 80/80).",
        closes_with: "AAI_TEST_TIMEOUT=1800 bash tests/skills/test-framework.sh on a clean checkout. Not run: a validation round is running in parallel on this tree and a concurrent framework run would corrupt both, and a full run in the copy did not fit the budget. I ran the 12-arm guard suite to completion in a clean copy instead (12/12, tree byte-identical) and the four ratchet suites in one framework run in a clean copy." }
    - { claim: "Whether any suite OUTSIDE the four ratchet entries writes a ratchet path and will newly go red once content hashing is in force.",
        closes_with: "The same clean-tree 80-suite census validation already ran (which commits between suites and is therefore content-equivalent) re-run on the post-remediation tree. It found exactly the four writers, all four ratcheted, so the risk is low but not measured here." }
    - { claim: "Behaviour on Windows (Git-Bash / WSL) and through the PowerShell dispatcher, including whether shasum/sha256sum/cksum resolve there.",
        closes_with: "A Windows run. The hasher probe degrades with a named WARN when none is found (verified by forcing AAI_TRIPWIRE_HASHER to a non-existent command), so the failure mode is a named degrade rather than a silent one — but see BLOCKING-3 for the one line that contradicts that degrade." }
  overall: fail
```

## Scope, method, shell

Diff scope: the eleven paths in the spec's `Inline review scope`, as the working-tree
diff (tracked) plus the two untracked new files, against `main` at `4fb5c60`.
`docs/INDEX.md`, `docs/ai/overview*.*`, `docs/ai/tests/test-runs.jsonl`,
`docs/ai/EVENTS.jsonl` and `docs/ai/decisions.jsonl` were treated as ride telemetry
and suite-run dirt per the dispatch, not as source edits.

All figures below were produced in **zsh** (`/bin/zsh`); `grep` was invoked as
`/usr/bin/grep` by absolute path everywhere. Nothing destructive touched the shipping
repo: every experiment ran in throwaway fixtures and in one committed copy under the
scratchpad, re-baselined by `cp` from a pristine byte copy, never by a git restore.

- Live tree at start: `HEAD 4fb5c60…`, `git status --porcelain=v1 | wc -l` = **18**
- Live tree at end: `HEAD 4fb5c60…` unmoved, **18** (unchanged; this report is the
  only addition). The only commands run against the live tree were `spec-lint.mjs`,
  `check-test-registration.mjs` and `docs-audit.mjs --check --strict --no-event`,
  all three read-only and all three clean.

## Judgement 1 — are BLOCKING-1 and BLOCKING-2 closed?

**Yes. Both. Reproduced, not read.**

### BLOCKING-1 — the decisive experiment

Clean throwaway git repo, byte copy of the shipped `tests/skills/test-framework.sh`
and `.aai/scripts/lib/repo-tripwire.sh`, the SHIPPED ratchet table, two fixture
suites: `test-aai-hitl-propagation.sh` (listed, appends to `docs/INDEX.md`) then
`test-aai-zz-evil.sh` (**on no allowlist**, appends to the same file).

```
[ 1/ 2] aai-hitl-propagation PASS (0.0s) [tripwire ALLOWED — known offender fu-hitl-propagation-writes-real-index, inside its listed path(s)]
[ 2/ 2] aai-zz-evil          FAIL (0.0s) [TRIPWIRE]
--- TRIPWIRE VIOLATION (aai-zz-evil) ---
AAI-TRIPWIRE FAIL: test suite 'aai-zz-evil' (suite exit code 0) changed the shipping repository.
AAI-TRIPWIRE   content changed (git status class unmoved, caught by the ratchet-path hash): docs/INDEX.md
[FAIL] Failed:  1 (50%)
[INFO] Tripwire: 0/2 suite(s) attested clean; 2 not attested
framework EXIT=1
```

This is the exact configuration that previously produced a bare `PASS`, exit 0 and a
place in the attested-clean numerator. It now fails, names the suite, names the path,
and names the mechanism that caught it. `0/2 attested clean` — the allowlisted writer
is not folded in either.

Second half, the STALE inversion: two ALLOWLISTED writers to the same ratchet path in
sequence (fixture fxE) both read `ALLOWED`, neither is reported STALE, and neither is
counted attested. Previously the second one read a bare `PASS` and its live entry was
printed STALE.

### BLOCKING-2 — the header

`.aai/scripts/lib/repo-tripwire.sh:58-81` no longer carries the false bound. It now
states the limit per PATH and per RUN, says in terms that a caller observing a
sequence manufactures its own dirt, and closes with "A caller that treats a clean
checkout as making this limit harmless is wrong whenever it observes more than one
command." It then names the escape hatch and says which caller uses it. That is
correct against everything I measured, it is placed where a downstream vendor reads
it, and it does not overclaim in the other direction — it explicitly says every path
outside a named set keeps the class-only bound.

### The arms bite

Control: `bash tests/skills/test-aai-repo-tripwire.sh` in a clean copy — **12/12 PASS,
exit 0**, and the copy's tree was byte-identical before and after (0 changed paths).
I then reproduced all four claimed mutations plus one of my own, each against a
trimmed driver running arms 004/008/011/012, restoring from a pristine byte copy
between runs:

| Mutation | Result |
|---|---|
| disable the clean→dirty escalation in `run_test` | TEST-011 red alone |
| `aai_tripwire_hash_changed` returns nothing | TEST-011 red alone |
| drop the `set -f` guard in `tripwire_path_listed` | TEST-012 red alone |
| drop the DUPLICATE warning | TEST-012 red alone |
| **mine:** `tripwire_union_paths` drops the hash side | TEST-011 red alone |

Unmutated control green in the same copy before and after every one. The claimed
mutation evidence is real.

## Judgement 2 — did the fix open something new?

**It did not open a new hole. It left one honesty gap in the residue and it made one
pre-existing false claim louder.** The louder one is BLOCKING-3, below; the residue is
NON-BLOCKING-1.

The hashing is correctly scoped and correctly derived: `TRIPWIRE_WATCH_PATHS` comes
from the table itself, so it cannot drift from what the ratchet dirties and it shrinks
with the table; the digest is read from stdin so the tool's filename echo cannot enter
the record; ABSENT and UNREADABLE are explicit markers so a deletion still reads as a
change; `AAI_TRIPWIRE_HASHER` naming a missing command degrades as NO hasher rather
than as a hasher that fails identically on both sides (the failure mode that would
read as "unchanged"); and the status-changed and content-changed sets are unioned
BEFORE the path-subset test, which my mutation M5 confirms is load-bearing. No new
`git` call: TEST-004 still measures 6 status calls over 3 suites.

The residue is real and is not stated where it bites. Hashing bounds D7 for the three
table paths; the ratchet's own bounding rule — "an entry lists the exact PATHS it
covers, so an allowlisted suite that dirties anything else still fails" — is enforced
for every OTHER path by the status comparison, which is blind to a path that was
already dirty at suite start. Measured (fixture fxC): with one pre-existing
`M docs/other.md`, an allowlisted `aai-metrics` writing `docs/ai/overview.html` **and**
`docs/other.md` is reported

```
PASS (0.0s) [tripwire ALLOWED — known offender fu-metrics-suite-writes-real-overview, inside its listed path(s)]
```

at framework exit 0, with the out-of-entry write landed. "inside its listed path(s)"
is an affirmative claim, and it is false there.

I am **not** ranking this BLOCKING, and the reason is a measurement rather than a
preference. I tried to construct the clean-start version and could not, because the
precondition is unreachable without the run already being red: on a clean start, a
non-ratchet path can only be pre-dirtied by an earlier suite, and that suite either was
unlisted (it FAILed — verified in fixture fxD2, `aai-aa-first FAIL [TRIPWIRE]`
naming `docs/other.md`, then `aai-hitl-propagation` reported ALLOWED while writing the
same path) or was listed for that path, in which case the path is a ratchet path and is
hashed. So on CI this degrades a red run's offender list, and it turns a run green only
on a tree that was already dirty — which is the tree-wide class-only bound the spec
explicitly accepts and the library header explicitly states. It is the accepted D7
residue reaching a place the spec did not think to qualify, not the old defect
relocated: the exemption mechanism no longer manufactures its own precondition.

The honest fix is the previous review's option (a), which the remediation treated as an
alternative to (b) and which is in fact its complement: `run_test` already holds
`tw_before`, so it can name the already-dirty subset and qualify the ALLOWED label.
AGENTS.md's degrade-with-NOTE convention and Constitution Article 4 both point the same
way.

## The finding the dispatch did not name — BLOCKING-3

**The stale-drain never asks whether the suite ran, and this remediation made its claim
stronger.** `tests/skills/test-framework.sh:621-631` loops over the table and prints STALE
whenever `tw_state == clean`. `tw_attested` — computed nearly two hundred lines earlier at :425 in the same
function, for exactly this distinction, because D3 exists — is not consulted. A skipped
or crashed suite touches nothing, is trivially clean, and drains its own entry.

Fixture fxD, byte copies, clean repo, `test-aai-state.sh` = `exit 42`,
`test-aai-metrics.sh` = `exit 3`:

```
[ 1/ 2] aai-metrics          FAIL (0.0s) [tripwire NOT ATTESTED — suite exited 3 before completing]
[ 2/ 2] aai-state            SKIP (0.0s) [tripwire NOT ATTESTED — suite skipped (exit 42), it never ran]
[INFO] Tripwire: 0/2 suite(s) attested clean; 2 not attested
[WARN] Tripwire: STALE ratchet entry 'aai-metrics' (fu-metrics-suite-writes-real-overview) — it changed nothing in this run, and for the ratchet's own paths that is a CONTENT verdict … close the item and delete the entry
[WARN] Tripwire: STALE ratchet entry 'aai-state' (fu-state-suite-writes-real-index) — it changed nothing in this run, and for the ratchet's own paths that is a CONTENT verdict … close the item and delete the entry
```

Two lines apart, the same run says a suite "never ran" and that the suite "changed
nothing in this run". Reproduced a second time with the REAL suites on a clean copy of
this repository, where `aai-hitl-propagation` and `aai-state` each aborted early and
both live entries were printed STALE.

The same sentence is also emitted in the no-hasher degrade, where its CONTENT-verdict
clause is false by construction. Forcing `AAI_TRIPWIRE_HASHER` to a non-existent
command in fixture fxE:

```
[WARN] Tripwire: no content hasher … the 3 ratchet path(s) are compared by git status class only …
[ 2/ 2] aai-state            PASS (0.0s)
[INFO] Tripwire: 1/2 suite(s) attested clean; 1 not attested
[WARN] Tripwire: the count above is CLASS-ONLY for the ratchet's paths …
[WARN] Tripwire: STALE ratchet entry 'aai-state' … for the ratchet's own paths that is a CONTENT verdict, not merely an unmoved git status class …
```

The aggregate degrades honestly twice and the STALE line then contradicts both.

Why this is the shape the previous pass found, in a new place. D3 ("clean never means
verified") and D8 (the drain) were designed separately and are correct separately.
Attestation is consulted on the progress line, in the aggregate counters and in
`metrics.jsonl`; it is not consulted in the one output that carries an operator
instruction. BLOCKING-1 was the same omission between D7 and D8; this is the omission
between D3 and D8. The remediation walked past it: it edited this exact line to add the
CONTENT-verdict clause.

Why BLOCKING rather than a filing. It is inside Spec-AC-06, whose text is "an entry
whose suite **ran** and came back clean is printed as stale", and the framework's own
words for a skipping suite are "it never ran". Skips are a first-class contract here
(exit 42) and the ordinary CI condition for env-dependent suites, so this is not an
exotic path. The instruction it emits closes a filed P2 as fixed and deletes a live
guard entry. The counter-reading is available and I record it: D8's second sentence
says only "a dirty or unobservable suite says nothing about it", and a skipped suite is
neither — under that reading the behaviour is permitted and the AC wording is what is
wrong. Either way one of the two must change, and the code change is one condition:

```bash
if [[ "$tw_state" == "clean" ]]; then   →   if [[ "$tw_state" == "clean" && "$tw_attested" == "true" ]]; then
```

plus making the CONTENT-verdict clause conditional on `TRIPWIRE_HASH_DEGRADED`.

Coverage note: `TEST-008(d)`'s third assertion reads "an entry whose suite never ran was
reported stale", which sounds like this case but is not — the entry it checks
(`aai-token-capture`) is simply absent from the five-suite fixture, i.e. never
discovered. No arm covers a discovered suite that skipped or crashed. That is why a
suite with 12 green arms and five reproduced mutations still ships this.

## Judgement 3 — the third location

**The remediation is right and my previous pass was wrong. I state that plainly.**

The pre-remediation spec is still on disk in the previous review's own scratch copies
(`scratchpad/aai-clean` and `scratchpad/aai-copy`, both carrying the old D7 wording at
line 226, "the FIRST write to any path is always caught, and the offender is always
named"). Its `Spec-AC-04` notes cell (line 495 there) is byte-for-byte the cell that is
in the spec today, and it does **not** contain the claim — it is entirely about
attestation, the two closed validation holes, and their mutations. The previous review
named three locations; there were three, but the third was never the AC-04 cell:

1. `.aai/scripts/lib/repo-tripwire.sh` header — corrected.
2. the spec's D7 — corrected, and it names the old wording as false and superseded
   rather than quietly deleting it, which is the better of the two options.
3. `docs/ai/decisions.jsonl:266`, the `fu-tripwire-porcelain-class-not-content`
   `decision` field — verified still present and still carrying "bounded because on a
   clean checkout the FIRST write is always caught". The ledger is append-only, so
   superseding it in the spec is the correct handling; a `follow_up_status` or a fresh
   `follow_up` line restating the bound would make it findable from the ledger side,
   but that is a filing, not a blocker.

## Standing verification run for this review

- `bash tests/skills/test-aai-repo-tripwire.sh` in a clean copy — **12/12 PASS, exit 0**;
  copy's tree 0 changed paths before and after.
- Four mutations claimed by the remediation + one of my own, each turning exactly the
  named arm red against a green control (table above).
- Framework run over the four ratchet suites in one process on a clean copy of this
  repository (the CI shape, not `--skill` one at a time).
- `node .aai/scripts/spec-lint.mjs` — `LINT PASS: no structural findings` (137 specs).
- `node .aai/scripts/check-test-registration.mjs` — clean, rc=0.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` — `### Verdict: CLEAN`,
  0 drift, 0 false-open.
- Live tree unchanged at 18 entries, HEAD unmoved.

## Dispositions (reviewer recommendation; the orchestrator records them)

- **BLOCKING-3** — remediate-in-tree. One condition plus one conditional clause, and an
  arm in TEST-008 or TEST-003 that discovers a ratchet-named suite which exits 42.
- **NON-BLOCKING-1** (out-of-entry write masked by pre-existing dirt) — remediate-in-tree
  if the already-dirty note is cheap; otherwise promote-to-follow-up-ref with the fxC
  reproduction attached, and add one sentence to D8 saying the entry bound is enforced
  by the status comparison for non-ratchet paths.
- **NON-BLOCKING-2** (suite-map row) and **NON-BLOCKING-3** (lost log tail) — already
  filed as `fu-suite-map-tripwire-row-incomplete` and
  `fu-tripwire-fail-hides-suite-log-tail`; no new artifact needed, noted as still open.

## INFO (never gate)

- `.aai/scripts/lib/repo-tripwire.sh:55` cites "(D4)" for the clean-is-not-verified rule;
  that is D3 in the spec. D4 is the offenders-stop-writing decision.
- The spec's Implementation plan still says the new suite has "the seven arms above"; it
  has twelve.
- `tests/skills/test-aai-repo-tripwire.sh:6` still says "Covers TEST-001..TEST-007".
- `tests/skills/test-aai-repo-tripwire.sh:412` still says "aai-metrics runs first in the
  discovery order"; discovery is alphabetical and `aai-hitl-propagation` sorts first. The
  reasoning the comment carries is still correct. Flagged in the previous pass, not fixed.
- In a content-only violation block the advisory line "A suite must run against a fixture"
  is printed BEFORE the `content changed:` line that names the path, because the advisory
  is the tail of `aai_tripwire_report` and the content lines are appended after it. Purely
  ordering; the path is named.
- The previous review report
  (`docs/ai/reviews/review-…-20260819T153900Z.md`) ends with two stray
  `</content>` / `</invoke>` lines. Untracked artifact of that pass; worth deleting before
  it is staged with the scope.

## Anti-gaming note

The dispatch stated it had not ranked anything, and then framed three judgements. It
named the hashing and the class-only residue separately and asked whether their
interaction was honest — which is where NON-BLOCKING-1 is. It did not name D3, and the
blocking finding of this pass is the interaction between D3 and D8. I record the framing
as the contract requires; reviewing the full scope rather than the three questions is
what produced BLOCKING-3. No coaching on severity was attempted, and the note that the
guard is transitional did not enter any severity call: I judged the tree as shipped.

I also record that the dispatch asked me to judge whether my own previous pass was wrong
about the third location. It was, and I have said so above without hedging.
