# Code Review — drain-the-tripwire-known-offender-list

```yaml
review:
  scope: git diff 862e069..3fd0137 (branch feat/drain-the-tripwire-ratchet)
  spec: docs/specs/SPEC-0146-spec-drain-the-tripwire-known-offender-list.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/test-framework.sh:98-99 (table parses to 0 entries); TEST-014 green at head; full-run parity is the implementer's evidence — see cannot_verify" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/test-aai-repo-tripwire.sh:796-877 TEST-013 green; validation M8/M1/M2b bite proofs" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "follow-ups.mjs list --status done: all four ids resolved_by drain-the-tripwire-known-offender-list with a per-suite --source" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "tests/skills/test-aai-repo-tripwire.sh:64,933-1002 TEST-014 green at 0/0; validation M1/M2/M2b" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "repo-tripwire.sh md5 23efde1d46ccf18758dcc39c2a1ff4fc and aai-run-tests.sh md5 d8ba567838b81c81632ab68553506d5b identical on both sides; derived hash set on 862e069 == floor at 3fd0137, same three paths in the same order" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-repo-tripwire.sh, line: 903,
          issue: "TEST-015's floor check is identity-blind: grep -c on the unanchored '^  \"docs/' plus a >=3 threshold, so it counts paths without naming them",
          failure_scenario: "MEASURED (MA6): replace docs/ai/overview.html and docs/ai/overview-data.json in TRIPWIRE_ALWAYS_WATCH with two decoy docs/ lines — the whole suite stays green (TEST-011/013/014/015 all PASS) while a two-suite fixture writing docs/ai/overview.html gives the second writer a bare PASS and 1/2 attested clean, against 0/2 on the unmutated floor. Two of the three floor paths have no coverage of any kind" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-repo-tripwire.sh, line: 915,
          issue: "TEST-015 pins two source lines verbatim, and one of them is exactly what the open P3 fu-always-watch-array-unguarded asks to change",
          failure_scenario: "MEASURED (MB): adding the :- guard to lines 137 and 188 of test-framework.sh is behaviour-preserving — the docs/INDEX.md fixture still reports 0/2 attested clean, TEST-011 stays green — yet TEST-015 fails with 'the hashed set is derived from the exemption table again', a diagnosis of something that did not happen" }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 52,
          issue: "the rewritten comment contradicts itself inside one paragraph: 'at AAI_TEST_ISOLATION=0, aai-state and aai-token-capture still write the shipping tree' (line 53) then 'an exemption that cannot fire protects nothing' (line 58)",
          failure_scenario: "the exemption CAN fire — with isolation degraded it fires and turns a FAIL into an ALLOWED warning. That is precisely the state the drain changes. The load-bearing half of the sentence ('its removal can only make the guard stricter') is true; the first half is the same class of overclaim this commit was written to remove" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-repo-tripwire.sh, line: 885,
          issue: "TW_GREP pins 7 uses while 61 other grep call sites in the same file stay bare, including TEST-014's anchorless control (line 403) which reads the same framework file five lines from a pinned read",
          failure_scenario: "under a shimmed or ugrep-aliased grep, TEST-014's negative control and every TEST-008/011/012/013 assertion resolve to a different binary than TEST-015's reads. A half-pinned file advertises a guarantee it does not hold and gives no way to see where the boundary is" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-repo-tripwire.sh, line: 871,
          issue: "TW_GREP and the whole test_015 function are inserted between TEST-014's header comment block and test_014_shipped_ratchet_length_is_ratcheted (line 933)",
          failure_scenario: "a reader arriving at test_015 (line 895) reads TEST-014's rationale as its documentation; a reader arriving at test_014 finds it undocumented. In a file whose arms are carried by their header comments this is a live maintenance hazard, not a formatting nit" }
  cannot_verify:
    - { claim: "Spec-AC-01's full-run parity — 81/81 before and after with an identical pass set",
        closes_with: "the two disposable-worktree full runs' logs; this round was forbidden from re-running the framework and validation could not read the implementer's scratchpad either" }
    - { claim: "TW_GREP's stated premise, that a census shim replaces grep in non-interactive shells",
        closes_with: "the shim itself; on this host /usr/bin/grep is BSD grep 2.6.0-FreeBSD and the pinned patterns were exercised against it, but the shim was not observed" }
    - { claim: "CI's behaviour on the first PR push while the spec is still status: implementing",
        closes_with: "the PR run — see finding 6 below" }
  overall: pass
```

## Scope and method

Reviewed `862e069..3fd0137` — `tests/skills/test-framework.sh`,
`tests/skills/test-aai-repo-tripwire.sh`, the spec, the CHANGE intake and the
ledger appends. Validation round 1
(`docs/ai/validation/validation-20260822T225652Z-...-round1.md`) was read first
and is not repeated; it was measured against `7c5a09c`, one commit behind head.
Everything below ran in a disposable `git worktree add --detach` at `3fd0137`
under the session scratchpad, removed with a targeted `git worktree remove`.
The shipping tree was never edited.

## The expected red, and its diagnosis

`bash tests/skills/test-aai-repo-tripwire.sh` at head: **14 PASS, 1 FAIL**,
exit 1. The only red is TEST-006, and it fails on its `rc != 0` branch, not on
its dirty-tree branch — the real checkout is left clean, which is what the arm
is actually about.

Chased to the bottom rather than accepted:

- TEST-006 runs `test-aai-doc-numbering.sh`, which exits 1 at its own TEST-013,
  `repo docs-audit CLEAN + index byte-idempotent`.
- `node .aai/scripts/docs-audit.mjs` → `Drifted: 1 | False-open: 1`, verdict
  NEEDS-TRIAGE. The **drift report names exactly one document**:
  `spec-drain-the-tripwire-known-offender-list`, `probable-false-open`, "AC
  Status table fully terminal with evidence". Nothing else is in it. RFC-0012
  appears only in the informational rollout-progress section with the umbrella
  heuristic already suppressed; orphans, stale, duplicates, body lint,
  provenance drift are all 0.
- Proved the diagnosis is the *whole* cause: flipping `status: implementing` to
  `done` in the worktree copy of the spec makes the same audit report
  `Drifted: 0 | False-open: 0 | Verdict: CLEAN`. Flipped back with `sed`, never
  with a restoring git command.

So the stated cause is confirmed and complete, and it self-clears at
`close-work-item.mjs`. One consequence is worth naming (finding 6 below).

## Findings

### 1. NON-BLOCKING (P2, filed) — TEST-015 counts the floor but never names it

`tests/skills/test-aai-repo-tripwire.sh:903`

```
floor_n="$("$TW_GREP" -c '^  "docs/' "$fw" 2>/dev/null || true)"
...
[[ "$floor_n" -ge 3 ]] || { log_fail "... declares $floor_n path(s), want at least 3 ..."; return; }
```

The pattern is not anchored to the array and the threshold is a count, so the
arm asserts *how many* floor paths there are and never *which*.

**Measured, MA6.** Swap `docs/ai/overview.html` and `docs/ai/overview-data.json`
for two decoy `docs/` lines, leave everything else alone:

| | result |
|---|---|
| `test-aai-repo-tripwire.sh` | TEST-008/011/012/013/014/**015 all PASS** — the suite is as green as the unmutated control |
| two-suite fixture writing `docs/ai/overview.html`, isolation off | first writer `FAIL [TRIPWIRE]`, **second writer bare `PASS`, `1/2 attested clean`, write landed** |
| the same fixture on the unmutated floor | both `FAIL [TRIPWIRE]`, `0/2 attested clean` |

That is validation's P2 state returning for two of the three floor paths with
nothing red. Only `docs/INDEX.md` has a behavioural backstop, and it comes from
TEST-011, not from TEST-015.

Filed `fu-test015-floor-identity-blind` (P2), read back from
`follow-ups.mjs list --status open --json`: present, severity P2, ref_id
`drain-the-tripwire-known-offender-list`, status open. Disposition:
promote-to-follow-up-ref (done).

### 2. NON-BLOCKING (P3, filed) — TEST-015 pins a line the open P3 asks to change

`tests/skills/test-aai-repo-tripwire.sh:915` and `:921` grep
`^TRIPWIRE_WATCH_PATHS=("${TRIPWIRE_ALWAYS_WATCH[@]}")` and
`for p in "${TRIPWIRE_ALWAYS_WATCH[@]}"; do` verbatim. The already-filed
`fu-always-watch-array-unguarded` (P3) asks for `:-` on exactly those two
expansions.

**Measured, MB.** With `:-` added to both, the `docs/INDEX.md` fixture still
reports `0/2 attested clean` and TEST-011 stays green — behaviour is unchanged —
and TEST-015 fails with *"TRIPWIRE_WATCH_PATHS no longer starts from the floor,
so the hashed set is derived from the exemption table again"*, which is a
description of something that did not happen. The two open registry items cannot
both be satisfied without editing TEST-015 in the same diff, and the failure
message will misdirect whoever tries.

Filed `fu-test015-blocks-array-guard-fix` (P3), read back: present, P3, open.
Disposition: promote-to-follow-up-ref (done).

### 3. NON-BLOCKING — the rewritten comment still contradicts itself

`tests/skills/test-framework.sh:52-60`. Lines 53-55 correctly say the four
suites still write the shipping tree at `AAI_TEST_ISOLATION=0`. Line 58 then
says "an exemption that cannot fire protects nothing".

It *can* fire. Isolation-off is a supported, counted, NOTE-degraded state, and
in it the drained entry was doing exactly its job: converting a FAIL into an
`ALLOWED` warning with the run still green. So yes, **there is a state where
isolation is off and the drained entry would have mattered** — an operator
running `AAI_TEST_ISOLATION=0 bash tests/skills/test-framework.sh` gets four
suites turning from green-with-warning to red.

The conclusion still holds and the drain is still right, but on the second
clause only: the change can only move the guard toward failing, never toward
passing, and the failure is loud. That is the sentence worth keeping. Coming
three lines after the correction it is the same class of overclaim the commit
set out to remove. Disposition: remediate-in-tree, one comment line.

### 4. NON-BLOCKING — TW_GREP half-pins the file

61 bare `grep` call sites, 7 `TW_GREP` uses (measured with `/usr/bin/grep -c`
under `/bin/bash`). The starkest instance is inside TEST-014 itself: its
anchorless negative control is built with a bare
`grep -v '^TRIPWIRE_KNOWN_OFFENDERS=($'` (line 403) five lines from TEST-015's
pinned reads of the same file.

**Judgement, since the brief asks for one: a half-pinned file is worse than a
consistently unpinned one.** Unpinned, the property "this file's assertions
depend on whatever grep resolves to" is uniform, discoverable in one grep, and
fixable in one pass. Half-pinned, the file now carries a comment asserting a
resolution guarantee that holds for 7 of 68 sites, with no marker on the other
61 and no arm that would notice if a new site picked the wrong one. The comment
is the liability, not the variable. Either finish the pin (one `sed`, then a
one-line arm that greps this file for a bare `grep`) or drop `TW_GREP` and note
the hazard once at the top. Disposition: remediate-in-tree or follow-up ref —
orchestrator's call; not filed, because it overlaps the existing hygiene lane.

### 5. NON-BLOCKING — TW_GREP's fallback degrades silently

`[[ -x "$TW_GREP" ]] || TW_GREP=grep` (line 886) falls back to the very binary
the comment above it says must not be measured against, and says nothing. The
repository's own convention, quoted inside `test-framework.sh` two hundred lines
away, is *degrade with a NOTE, never silently*. One `log_info` closes it.

Also in the same arm, `2>/dev/null` on the `floor_n` grep (line 903) discards the
only diagnostic that count has, and `seeded_n=1` on line 927 followed by
`[[ "$seeded_n" -eq 1 ]]` on line 929 is a tautology — the "vacuity guard did not
run" branch is unreachable dead code. Both INFO.

### 6. NON-BLOCKING — the branch ships a red gating suite until the close ceremony

`test-aai-repo-tripwire.sh` is red at head for the reason established above, and
`SKILL_PR` runs `close-work-item.mjs` *after* `gh pr create`. The PR's first CI
run will therefore see the spec still at `status: implementing` and this suite
red. Self-clearing, deterministic, and a known repository dynamic — but it is a
merge precondition, not a non-event: **do not merge until the close-ceremony
commit has landed and `test-aai-repo-tripwire.sh` is 15/15.** Named here so the
PR step does not read the red as a flake.

Note also that the spec's AC Status table was populated against `7c5a09c` and
still says "all 14 arms green" and that the floor "carries no arm"; head has 15
arms and TEST-015 is the arm. TEST-015 has no Test Plan row and no Spec-AC
mapping. Evidence drift of one commit, not an AC failure — the ACs themselves
hold at head — but the table should name `3fd0137` and TEST-015 before close.

## What I attacked and could not break

- **Deleting the floor.** Replayed validation's M4b (floor block plus dedup seed
  removed, `TRIPWIRE_WATCH_PATHS=()`): TEST-015 goes **red** with the right
  message while TEST-011 stays green. TEST-015 does close the exact gap it was
  written for, and validation's finding that TEST-011 does not cover it is
  confirmed from the other side.
- **Neutralising the floor while keeping every pinned string** (MA1: a second
  `TRIPWIRE_WATCH_PATHS=()` after line 137). TEST-015 passes, as predicted for a
  textual arm — but **TEST-011 catches it**, because the dedup seed makes its own
  injected `docs/INDEX.md` entry redundant and the watch set ends empty. The
  textual/behavioural trade is therefore narrower than it looks: the shipped pair
  of arms covers "the watch set is non-empty" behaviourally and "it comes from
  the floor" textually. The residual is finding 1, and only finding 1.
- **AC-005, independently.** `repo-tripwire.sh` and `aai-run-tests.sh` are md5-
  identical to `862e069`. The set `862e069` derived from its four table entries
  is `{docs/INDEX.md, docs/ai/overview.html, docs/ai/overview-data.json}` in that
  dedup order; `TRIPWIRE_ALWAYS_WATCH` at head is the same three in the same
  order. The hashed set is byte-for-byte the same question.
- **A new `printf | grep -q` occurrence.** `tests/skills/lib/pipe-grep-q-ratchet.sh`
  exit 0; `test-aai-hygiene-pack.sh` exit 0, "3 pinned needle(s) of 4 converted
  sites intact". None added.
- **`rc=$?` after a pipe.** Every `$?` read in the new code follows a
  `var="$(cmd)"` command substitution, not a pipeline, so it reports the
  command. The suite runs `set -uo pipefail` with **no `-e`**, so the deliberate
  non-zero reads in TEST-013/TEST-014 survive to be inspected instead of killing
  the script. Correct as written, and the comment on `count_ratchet_entries`
  ("pure awk, so there is no bash-3.2 empty-array or `$?`-after-a-pipe hazard")
  is accurate.
- **`log_fail` in a subshell.** `inject_ratchet_entries` and
  `count_ratchet_entries` both log nothing and return status, documented as such;
  every caller owns the message. No `log_fail` reached from a command
  substitution.
- **bash 3.2.57, `set -u`.** The whole suite was run under an explicit
  `/bin/bash` (3.2.57(1)-release, arm64-apple-darwin25). TEST-015's locals are
  all initialised. `${#TRIPWIRE_ALWAYS_WATCH[@]}` is never taken. The two
  unguarded `[@]` expansions are the already-filed P3 and fail loudly, not
  silently.
- **`p` reuse in the seeding loop.** `p` is declared `local` at the head of
  `tripwire_ratchet_init`; the seed loop runs to completion before the entry loop
  and nothing reads `p` between them. No clobber — verified by executing lines
  132-234 in isolation with stubbed collaborators.
- **Fixture ids reaching the registry.** `fu-ctl-one`, `fu-ctl-two`,
  `fu-fixture-metrics-overview`, `fu-fixture-state-index`,
  `fu-fixture-hitl-index`: 0 hits each in `docs/ai/decisions.jsonl`. The ledger
  is fed only by `decisions.jsonl`; nothing scans source for `fu-` ids.
- **Seeding proved before concluding.** `inject_ratchet_entries` reads back every
  entry with `grep -qF` and refuses any entry containing a quote or backslash
  before writing shell source. `node .aai/scripts/check-test-registration.mjs
  tests/skills` exit 0.
- **`fu-watch-paths-empty-reopens-d7`'s closure.** Correct *now*. Its `--source`
  is still a description of the edit rather than a measurement, and at the moment
  of closure the fix had no arm (validation's point), but TEST-015 retroactively
  supplies one and I measured that the exact reopening the item describes is
  caught. The arm does not assert the wrong thing — it asserts a true thing about
  one of the three paths and a count about the other two (finding 1).

## Latent, not live

`tripwire_ratchet_init`'s dedup set is a substring test over a space-joined
string, and this change seeds it from the floor. Measured by executing the real
function with a mutated floor:

- floor path `docs/a b.md` + table path `docs/a` → `docs/a` is **silently
  swallowed** and never enters `TRIPWIRE_WATCH_PATHS`.
- floor path `docs/gl*b.md` → accepted with **no warning**, where the identical
  table entry would get the glob-metacharacter `log_warn`; matched literally, so
  it watches nothing.

Both need a future edit to the floor; today's three paths have neither a space
nor a metacharacter. The substring dedup is pre-existing (it already applied to
table paths); this change widens its input. INFO — worth a comment on the array
telling the next author the floor is whitespace- and glob-hostile.

## Judgement calls the brief asked for

**Is TEST-015 a real assertion?** Partly. It is four greps and a vacuity guard,
and it does close the filed gap: the mutation that left the suite 14/14 green now
fails it. But its floor check is a count, not a set, and two of the three paths
it exists to protect can be replaced with the suite fully green (finding 1).
Calling that "the D7 fix is asserted, not just present" in the pass message
overstates what ran.

**Was a behavioural arm available at reasonable cost?** Yes, and cheaply — the
fixture that proves it is about twenty lines and I wrote it in this round: two
fixture suites appending to one floor path, isolation off, assert the second
writer fails and `0/2 attested clean`. Run once per floor path it covers all
three by behaviour and needs no source-text pin at all, which also dissolves
finding 2. That is the arm this scope should have shipped. It is not a blocker,
because the textual arm plus TEST-011 does cover the specific regression that was
filed; it is the reason finding 1 is P2 rather than P3.

**Is the drain still the right call?** Yes. The argument as written is wrong in
its premise — the exemption *could* fire, whenever isolation degrades, and there
it mattered — but right in its conclusion: removing it can only convert a green
ALLOWED warning into a red FAIL, never the reverse. A guard that gets stricter
in the degraded case is the correct direction, the degradation is NOTE-reported,
and the residual is filed as `fu-drained-suites-still-write-unisolated`. Merge
the drain; fix the sentence.

## Coaching-attempt note

The dispatch named nine registry ids as "known, do not refile" and stated in
advance that TEST-006 would be red with its cause. Per the anti-gaming contract
this is recorded rather than obeyed as a scope exclusion: the full diff was
reviewed, the TEST-006 diagnosis was re-derived from the audit rather than
accepted, and the two findings above are new and were filed.

## Verdict

**pass.** No BLOCKING finding: the shipped runtime behaviour is correct, the
floor is load-bearing and measured so in this round, AC-005 holds byte-exactly,
and every Spec-AC is compliant at head. Five NON-BLOCKING findings, two of them
newly filed to the registry; the rest carry named dispositions above.

Merge precondition (not a blocker): the close ceremony must land and
`test-aai-repo-tripwire.sh` must be 15/15 before the PR is merged.
