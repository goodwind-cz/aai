# Code Review — suites-must-not-touch-the-shipping-repo (dual verdict)

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
          citation: "TEST-001/TEST-002 green (suite stdout); tests/skills/test-framework.sh:346-372 dirty-overrides-outcome. See BLOCKING-1 — the property is intact in isolation but is defeated by the Spec-AC-06 mechanism." }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-007 green; .aai/scripts/aai-run-tests.sh:104-133 (arm + not-armed NOTE), :276-292 (report on every exit path, exit code untouched)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-006 green; tests/skills/test-aai-doc-numbering.sh:661-692 and tests/skills/test-aai-deslop.sh:935-1007 both generate into a mirror" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-003/TEST-009/TEST-010 green; tests/skills/test-framework.sh:298-341 tri-state attestation. Literal fixtures hold; see BLOCKING-1 for the case the wording does not survive." }
      - { ac: Spec-AC-05, call: compliant,
          citation: "TEST-004 green — measured 6 status calls over 3 suites through a PATH shim; TEST-005 green" }
      - { ac: Spec-AC-06, call: non-compliant,
          citation: "Two clauses reproduced FALSE on a clean tree with the SHIPPED entries — (i) 'A suite that is not on the list still fails, so Spec-AC-01 is unchanged' and (ii) D8's 'a dirty or unobservable suite says nothing about [its entry]'. Evidence: scratchpad/attack16 and the four-suite --skill sequence below." }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-framework.sh, line: 298,
          issue: "The ratchet manufactures the D7 masking precondition on a CLEAN checkout for the three highest-traffic paths in the repo, and the framework then prints its strongest green label — bare PASS plus 'attested clean' — over subsequent real writes to those paths by ANY suite, listed or not. It also prints STALE for entries whose suites are still writing, instructing the operator to delete a live guard entry. The framework holds the before-snapshot and can see the path was already dirty; it never says so.",
          failure_scenario: "Clean checkout, CI's own invocation shape. aai-hitl-propagation runs first and is ALLOWED for docs/INDEX.md. Any later suite that writes docs/INDEX.md — including one on no allowlist at all — leaves porcelain byte-identical, so tw_state=clean, tw_attested=true, the progress line is a bare PASS and the suite is counted in the attested-clean numerator. Reproduced twice: (a) fixture, unlisted suite aai-zz-evil appended to docs/INDEX.md, framework exit 0, '1/2 attested clean'; (b) real suites on a clean copy of this repo — aai-state and aai-token-capture both wrote, both printed PASS + '1/1 attested clean' + 'STALE ratchet entry … it changed nothing in this run'." }
      - { rank: BLOCKING, file: .aai/scripts/lib/repo-tripwire.sh, line: 50,
          issue: "The D7 KNOWN LIMIT paragraph states a bound that the shipped configuration falsifies: 'on a clean checkout — CI, and the normal local case — the FIRST write to any path is always caught.' With the ratchet seeded, the first write to docs/INDEX.md, docs/ai/overview.html and docs/ai/overview-data.json is deliberately allowed on a clean CI tree, so every later write to them is uncaught and unlabelled. The spec repeats the same bound (D7, 'The residue is bounded and its shape is known'). This is the load-bearing honesty statement of the whole feature and it is wrong as shipped.",
          failure_scenario: "A reader (or a downstream project vendoring this library) reads the header, concludes CI runs are fully guarded, and does not add the compensating check. The four-suite sequence above is the counter-example." }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 84,
          issue: "tripwire_path_listed iterates `for listed in $2` unquoted, so an allowlist entry containing a glob is pathname-expanded against the framework's CWD instead of compared literally.",
          failure_scenario: "A future entry written as `docs/*` silently widens to every top-level entry of docs/ when CWD is the repo root (measured: matches docs/INDEX.md), and matches nothing at all when CWD is elsewhere — non-deterministic scope for a security-relevant list. `set -f` around the loop, or a literal `case`, fixes it. Confirms validation's finding and its 'narrow' characterization: one directory level, dormant today." }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 74,
          issue: "tripwire_allowlist_entry returns on the FIRST matching suite, so a second entry for the same suite is silently ignored.",
          failure_scenario: "Someone adds `aai-metrics|fu-new-item|docs/other.md` below the existing aai-metrics row expecting both to apply; only the first is read, so the suite fails on docs/other.md with no hint that its second entry was discarded. Fails CLOSED, which is why this is not blocking; confirms validation's characterization." }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 380,
          issue: "When a suite BOTH genuinely fails and trips the tripwire, `outcome` is forced to `tripwire`, which skips the `*)` branch that prints the tail of the suite log. The tripwire block prints only the numeric exit code.",
          failure_scenario: "A suite crashes at exit 1 with a real assertion message AND leaves an untracked file. CI shows FAIL [TRIPWIRE] + the changed path, and the assertion text that explains the crash is not echoed — the reader must fetch the artifact to debug an ordinary failure." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/repo-tripwire.sh, line: 18,
          issue: "The header's blind spots are stated for the working tree only. Everything under .git/ is invisible: `git config --local`, hook installation, branch/tag/remote creation, `git stash`, reflog. Several suites already run `git config` inside fixtures; one that ever ran it against PROJECT_ROOT would permanently mutate the shipping repo's config and the tripwire would report `clean`.",
          failure_scenario: "A suite adds `git config --local core.hooksPath /tmp/x` to PROJECT_ROOT to work around a pre-commit hook. HEAD is unmoved, porcelain is unchanged, the suite is reported attested clean, and every later commit in that checkout silently skips hooks. Not in the intake's definition, but it belongs beside D3 and D7 in the header a downstream project vendors." }
      - { rank: NON-BLOCKING, file: tests/skills/suite-map.yaml, line: 572,
          issue: "The aai-repo-tripwire suite-map row omits two paths this scope actually changed: tests/skills/test-aai-spec-lint.sh and .aai/system/PROFILES.yaml.",
          failure_scenario: "A later PR that only edits test-aai-spec-lint.sh's mirror logic (the third offender fix, which this scope introduced) does not select aai-repo-tripwire on the CI selected path, so the guard's own suite does not run against a change to a suite it guards. The .aai/scripts/lib/** fail-open rule covers library edits but not this one." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 118,
          issue: "The two mktemp snapshot files are removed only on the normal path; there is no trap, so a signal delivered to the wrapper itself between arming and the report leaks both.",
          failure_scenario: "Operator Ctrl-C's a wrapped long test run: two zero-to-few-KB files stay in TMPDIR per interrupted invocation. Cosmetic; noted for completeness." }
  cannot_verify:
    - { claim: "The full 80-suite framework aggregate on this dirty tree (validation's 80/80, 0 violations).",
        closes_with: "I started it on a clean copy and stopped it at suite 7/80 to stay inside the review budget; the four ratchet suites were then run individually via CI's own `--skill` shape, which is what the findings rest on. A full green run does not bear on the findings either way — see the note on validation below." }
    - { claim: "Behavior of the tripwire on Windows (Git-Bash / WSL) and on the PowerShell dispatcher path.",
        closes_with: "aai-run-tests.ps1 delegates to aai-run-tests.sh (line 694), so the wrapper tripwire is inherited by construction, but no Windows run was observed here. ps1-quality.yml exercises the dispatcher and would surface a regression." }
    - { claim: "Whether the four registry items named in the ratchet exist and are open in the follow-up ledger.",
        closes_with: "`node .aai/scripts/follow-ups.mjs list` against docs/ai/decisions.jsonl. Not run — read-only reviewer, and the ids are consistent between the framework table, the spec and the intake." }
  overall: fail
```

## Scope and method

Diff scope: the eleven paths named in the spec's `Inline review scope`, taken as the
working-tree diff (tracked) plus the two untracked new files, against `main` at
`4fb5c6087ac20b1759a2ebbb8cc00c210a0e5e12`. Two further modified files —
`docs/ai/decisions.jsonl` and `docs/ai/EVENTS.jsonl` — are outside that declared
list; they read as ride telemetry (spec-freeze, decisions) rather than source
edits, and I did not review them as scope. `docs/INDEX.md`, `docs/ai/overview*.*`
and `docs/ai/tests/test-runs.jsonl` are the suite-run dirt the dispatch named.

All measurements below were produced in **zsh** (`/bin/zsh`), with `grep` invoked
as `/usr/bin/grep` by absolute path. Everything destructive ran in one reused
copy under the scratchpad; the shipping repo was touched only by the two
verification commands the dispatch offered.

- Start: `HEAD 4fb5c6087ac20b1759a2ebbb8cc00c210a0e5e12`, `git status --porcelain=v1 -uno | wc -l` = **13**
- End: `HEAD 4fb5c6087ac20b1759a2ebbb8cc00c210a0e5e12` (unmoved),
  `git status --porcelain=v1 -uno | wc -l` = **13** (unchanged). The only new
  untracked path is this report.

## The three judgements

### 1. Is the ratchet honest?

**Yes in construction, no in reporting — and the reporting half is what makes it
a guard that does not guard.**

The construction is genuinely good, and better than the alternatives it rejected.
Every property that makes a curated-exemption list dangerous has a named
counter-measure that I verified in code: the entry is a bash array in the
framework, not a config file, so growing it is a diff a reviewer sees; each entry
carries a registry id, so nothing can be exempted anonymously; each entry is
scoped to paths, so an entry is not blanket permission for its suite; HEAD moves
are never covered; and `TEST-008` names its fixture suites after the *shipped*
entries and dirties the *shipped* paths, so the arm reads the same table CI
reads rather than a test-only injection. That last choice is the single best
decision in this diff — it is the difference between testing the mechanism and
testing the configuration, and most implementations get it wrong.

So: it should have shipped as a ratchet. Shipping it failing would have made CI
red on a clean tree until four out-of-scope production scripts were fixed, and
shipping it report-only at both funnels would have produced a check with no
teeth at the one funnel CI runs. The ratchet is the right shape.

**But the ratchet as shipped is not the ratchet as described.** The description
says four suites are exempted for their own paths. What actually ships is: after
the first allowlisted suite runs, three paths — `docs/INDEX.md`,
`docs/ai/overview.html`, `docs/ai/overview-data.json` — are unguarded **for every
remaining suite in the run, listed or not**, and writes to them are reported as
*attested clean*. Those are not incidental paths; they are the three most
frequently regenerated files in this repository, i.e. precisely the paths a
runaway suite is most likely to write. Nobody connected D8 to D7. See BLOCKING-1.

### 2. Does the guard hold where it matters?

Fifteen attacks were defeated and the two filed holes are as narrow as claimed —
I reproduced both. The glob one widens exactly one directory level and only when
CWD contains the pattern base (measured), and no shipped entry contains a glob;
the duplicate-entry one fails **closed** (the second entry is dropped, so the
suite fails on the path the dropped entry would have covered). Both are correct
NON-BLOCKING calls.

**The sixteenth exists and it is not narrow.** It is BLOCKING-1, reproduced twice.

Reproduction A — synthetic, but using a byte copy of the real framework and the
real shipped table, in a throwaway git repo, from a genuinely clean tree:

```
[ 1/ 2] aai-hitl-propagation PASS (0.0s) [tripwire ALLOWED — known offender fu-hitl-propagation-writes-real-index, inside its listed path(s)]
[ 2/ 2] aai-zz-evil          PASS (0.0s)
[PASS] Passed:  2 (100%)
[INFO] Tripwire: 1/2 suite(s) attested clean; 1 not attested
EXIT=0
--- did evil's write land? ---
1
```

`aai-zz-evil` is on no allowlist. It appended to `docs/INDEX.md`. The run exited
0, the suite printed a bare `PASS`, and it was counted in the **attested-clean**
numerator. Spec-AC-06's clause "a suite that is not on the list still fails, so
Spec-AC-01 is unchanged" is false in the configuration the ratchet itself
creates.

Reproduction B — the **real** four suites, on a clean copy of this repository, run
through CI's own `test-framework.sh --skill <name>` sequence:

```
=========== aai-hitl-propagation (tree dirty before: 0) ===========
PASS (95.0s) [tripwire ALLOWED — known offender fu-hitl-propagation-writes-real-index, inside its listed path(s)]
tree dirty after: 2
=========== aai-metrics (tree dirty before: 2) ===========
PASS (9.0s) [tripwire ALLOWED — known offender fu-metrics-suite-writes-real-overview, inside its listed path(s)]
tree dirty after: 4
=========== aai-state (tree dirty before: 4) ===========
PASS (55.0s)
[INFO] Tripwire: 1/1 suite(s) attested clean; 0 not attested
[WARN] Tripwire: STALE ratchet entry 'aai-state' (fu-state-suite-writes-real-index) — it changed nothing in this run
=========== aai-token-capture (tree dirty before: 4) ===========
PASS (0.0s)
[INFO] Tripwire: 1/1 suite(s) attested clean; 0 not attested
[WARN] Tripwire: STALE ratchet entry 'aai-token-capture' (fu-token-capture-writes-overview) — it changed nothing in this run
```

The first two work exactly as designed. The last two — the two writers D8 says
"had been invisible for exactly the reason D7 records" — are reported PASS,
counted attested clean, and their entries are printed **STALE with an
instruction to close the registry item and delete the entry**. The ratchet, which
"only shrinks", drains itself for the wrong reason. D8's own guarantee — "Only a
suite the tripwire observed as clean can make its entry stale — a dirty or
unobservable suite says nothing about it" — is the exact sentence this falsifies.

### 3. D7: is the limit stated where a reader hits it, and is STALE honest?

**The limit is stated in three places and all three state it wrongly, in the same
direction.** `.aai/scripts/lib/repo-tripwire.sh:50-57`, the spec's D7, and the
spec's Spec-AC-04 notes all bound the residue with "on a clean checkout — CI, and
the normal local case — the FIRST write to any path is always caught." That bound
is what makes D7 acceptable as a stated limit rather than a hole, and the seeded
ratchet invalidates it: on a clean CI tree the first write to each of the three
ratcheted paths is *deliberately allowed*, so the bound no longer holds for them.
Placement is fine — the library header is exactly where a downstream vendor will
read it. The content is wrong. That is BLOCKING-2.

**The STALE line is not honest**, and the framework has the data to make it
honest. `tw_before` is sitting in a variable in the same function; a path that is
already dirty in it is, by definition, unobservable for that suite. The line
hedges with "if that holds on a clean tree", but Reproduction B started on a
clean tree — it is the *preceding suite in the same run* that dirties the path —
so the hedge does not protect the reader it is aimed at. The unhedged half is
worse: "it changed nothing in this run" is a flat assertion that was false in
both reproductions, and the `attested clean` count beside it is unhedged
entirely.

The strongest evidence for this is the ride's own telemetry.
`tests/skills/results/test-20260819-143923/metrics.jsonl`, from a full framework
run today, records:

```
{"skill":"aai-hitl-propagation",...,"tripwire":"clean","tripwire_attested":true,"tripwire_allowed":false}
{"skill":"aai-metrics",...,"tripwire":"clean","tripwire_attested":true,"tripwire_allowed":false}
{"skill":"aai-state",...,"tripwire":"clean","tripwire_attested":true,"tripwire_allowed":false}
{"skill":"aai-token-capture",...,"tripwire":"clean","tripwire_attested":true,"tripwire_allowed":false}
```

All four known offenders, recorded as **attested clean, not allowed**. That is the
whole-tree evidence this ride produced, and it is the reading D3 exists to
forbid.

## Was validation generous?

Yes — not in effort, but in what it accepted as evidence. Validation found the
four writers, wrote the ratchet, tested the ratchet against the shipped table
(good), and then measured the result on a tree where the ratchet's mechanism
could not fire. "80/80, 0 tripwire violations" is not a green light for this
feature; on the tree it was measured on it is the *symptom*. A single run on a
clean tree — which validation already knew how to produce, because that is how it
found the four writers — would have surfaced both BLOCKING findings, because they
appear in the first two lines of output. The 15 attacks were aimed at the
allowlist parser; none was aimed at the interaction between the allowlist and the
limit stated two decisions above it.

## Recommended remedy (small, no redesign)

Either of these clears BLOCKING-1; the first is the honest-degrade version and is
about ten lines:

1. **Name the blind spot.** In `run_test`, compute the set of paths already dirty
   in `tw_before`. If any of them is non-empty, the suite cannot be
   `tw_attested=true` for those paths: print `tripwire PARTIAL — N path(s) were
   already dirty at suite start; writes to them are unobservable (D7): <paths>`,
   keep it out of the attested-clean numerator, and suppress the STALE line for
   any entry whose paths appear in that set. This satisfies AGENTS.md's
   degrade-with-NOTE convention and Constitution Article 4, which the current
   output does not.
2. **Close it for the ratchet's own paths.** Hash the (currently three) distinct
   paths named in `TRIPWIRE_KNOWN_OFFENDERS` before and after each suite. That is
   ~3 file hashes per suite, nowhere near the "content hash of the whole tree"
   cost D7 rejects, and it removes the amplification entirely.

BLOCKING-2 is a text fix in three places: the bound must say "the first write to
any path **not named in the known-offender list** is always caught", and the
library header must state that the framework caller may seed such a list.

Dispositions for the NON-BLOCKING findings (reviewer recommendation; the
orchestrator records them): glob-widening and duplicate-entry —
**remediate-in-tree**, both are one-line and both are in the file being changed.
Lost-log-tail on a combined failure, the `.git/`-internals blind spot, the
suite-map row, and the tmpfile leak — **promote-to-follow-up-ref**.

## Anti-gaming note

The dispatch stated it had deliberately not ranked anything, then supplied a
framing that named the ratchet, the two filed holes and D7 as the three
questions. It did not name the interaction between them, which is where the
BLOCKING findings are; I record the framing here as required by the contract and
note that reviewing the full scope, rather than the three named questions, is
what produced them. No coaching on severity was attempted.

Two smaller notes outside the findings: the comment at
`tests/skills/test-aai-repo-tripwire.sh:412` says "aai-metrics runs first in the
discovery order", but discovery is alphabetical and `aai-hitl-propagation` sorts
first; the reasoning the comment carries is still correct. And the AC Status rows
reading `implementing` rather than `done` is well-evidenced in the spec's own
measured note — I have no objection to it.

## Verification run for this review

- `bash tests/skills/test-aai-repo-tripwire.sh` — **exit 0, all 10 arms PASS**
  (TEST-001..TEST-010, including TEST-004's measured "6 calls over 3 suites").
  The run left the shipping repo byte-identical, which independently corroborates
  Spec-AC-03.
- `node .aai/scripts/spec-lint.mjs` — `LINT PASS: no structural findings` (137 specs scanned).
- `node .aai/scripts/check-test-registration.mjs` — clean (no output).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` — `### Verdict: CLEAN`.
- Full framework: started on a clean scratch copy, stopped at 7/80 to stay in
  budget; the four ratchet suites then run individually via `--skill` (above).
</content>
</invoke>
