---
id: spec-friction-upsert-channel-cannot-file
type: spec
number: 166
status: done
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-0080-friction-upsert-channel-cannot-file.md
  rfc: null
  pr:
    - TBD
  commits:
    - TBD
---

# Spec — the friction upsert channel can actually file, and its argv is pinned

SPEC-FROZEN: true


## Links
- Requirement: `docs/issues/ISSUE-0080-friction-upsert-channel-cannot-file.md`
- Technology contract: `docs/TECHNOLOGY.md` (Node stdlib only, zero deps, bash-3.2 in suites)
- Engine under change: `.aai/scripts/aai-feedback-upsert.mjs`
- Suite under change: `tests/skills/test-aai-feedback-upsert.sh`
- Config: `.aai/feedback.yaml` (`triage.mode`, `upsert.labels`)
- Governing canon: RFC-0012 Phase 2c (D7/D8 approval gate), RFC-0013 (double redaction)

Registry items closed by this scope: none. **Correction (Amendment 4):** this
paragraph originally said the registry "returns two open items". That number came
from a `tail -3` of the listing and was wrong by two orders of magnitude — the
open backlog is **116** items. The claim was re-derived properly with
`follow-ups.mjs list --status open | grep -c '^open'` and a keyword sweep for
`upsert|feedback|friction|gh search|label`: the only open items naming this
scope's subject are the two this ride itself created
(`fu-amend-friction-upsert-channel-ba7701`, `fu-friction-label-missing-in-destination`).
So the conclusion — this scope discharges no pre-existing open item — still holds;
the number supporting it did not.

## THE MEASURED SITUATION

Measured on 2026-09-04 against `goodwind-cz/aai` at `52ddeb5`, with 53 spooled
observations and `triage.mode` set to `review`:

- `node .aai/scripts/aai-feedback-triage.mjs` → 53 kept, 27 clusters, 7 review candidates.
- `node .aai/scripts/aai-feedback-upsert.mjs` → 7 drafts prepared, **all 7**
  reported `blocked_dedup_unavailable`, and each still printed a
  `--publish <fp> --confirm` command.
- `node .aai/scripts/aai-feedback-upsert.mjs --publish <fp> --confirm` →
  `could not verify dedup ... — refusing to create`, exit 1.

Root cause, reproduced by hand:

```
gh search issues --repo goodwind-cz/aai --match body aai-friction:<fp> --state all --json number --limit 1
→ invalid argument "all" for "--state" flag: valid values are {open|closed}   (exit 1)
```

The same call with `--state` omitted returns `[]` with exit 0. `gh search issues`
searches all states by default, so the flag was never needed.

Second, independent blocker: `gh label list --repo goodwind-cz/aai` contains no
`aai-friction`, while `.aai/feedback.yaml` pins `labels: [aai-friction]` and the
create path passes `--label aai-friction`. `gh issue create` rejects an unknown
label, so the write fails even once the search is fixed.

Why the suite is green: `tests/skills/test-aai-feedback-upsert.sh` stubs `gh`
with a shell script that appends its argv to a file and `exit 0`s unconditionally.
It asserts *that* `gh` was called and *how many times*, never that the argv is one
real `gh` would accept. The mock is strictly more permissive than the CLI it
stands for.

## Design decisions

**D1 — fix the call, keep the fail-closed.** The refusal on an unverifiable
dedup is correct and stays byte-for-byte. Only the call it guards changes:
`--state all` is dropped. A dedup that cannot run must still refuse.

**D2 — a missing label degrades, it does not fail the write.** The channel's
purpose is the upstream hop; a cosmetic label must never cost an observation.
Before the create, the engine reads the destination's labels. Labels that exist
are passed; labels that do not are dropped, and every dropped label is named on
stderr. If the label read itself fails, ALL labels are dropped and the create
still proceeds — the opposite of the dedup's fail-closed, and deliberately so:
a duplicate issue is a real harm, an unlabelled issue is not.

**D3 — the mock validates what real `gh` validates.** The stub gains a small
allowlist: for `search issues` it rejects a `--state` value outside
`{open|closed}`, exactly as the CLI does, exiting non-zero. This makes the
pre-fix engine RED against the suite. The stub is not a `gh` reimplementation;
it pins only the argv facts this engine depends on.

**D4 — prepare output tells the truth about what it is offering.** A cluster the
engine could not clear for publishing is not advertised with a command that will
refuse. Blocked entries print the blocking reason and no `--publish` line.

**D5 — `triage.mode: review` ships with this scope.** The channel being switched
on is the operator decision that motivated the ride; leaving it uncommitted would
silently revert to `local` on the next checkout.

## Implementation strategy
- Strategy: tdd
- Rationale: the defect is that a green suite attested a broken call. The only
  credible fix therefore starts by making the suite able to fail: the stub is
  tightened first, the pre-fix engine is observed RED on the dedup case, and the
  engine change is what turns it GREEN. A fix landed before the mock can fail
  would carry exactly the evidence that already proved worthless here.

## Acceptance Criteria Mapping

- Maps to requirement D1 → Spec-AC-01, Spec-AC-02, Spec-AC-03
- Maps to requirement D2 → Spec-AC-04, Spec-AC-05
- Maps to requirement D3 → Spec-AC-03, Spec-AC-06
- Maps to requirement "prepare honesty" → Spec-AC-07
- Companion obligations (closed list) → Spec-AC-08

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | `dedupSearch` invokes `gh search issues` with NO `--state` flag; the recorded argv for a prepare run contains `search issues --repo <dest> --match body aai-friction:<fp> --json number --limit 1` and the token `--state` appears nowhere in it | done | TEST-013, tests/skills/test-aai-feedback-upsert.sh; docs/ai/tdd/friction-upsert-channel-cannot-file-green.log; RED for this AC in docs/ai/tdd/friction-upsert-channel-cannot-file-red.log | tdd:2026-09-05 | D1; argv asserted on the recorded call, never on an exit code |
| Spec-AC-02 | WHEN the dedup search cannot run THEN `--publish <fp> --confirm` still exits non-zero, writes the unchanged refusal naming the fingerprint, and records ZERO `issue create` calls | done | TEST-011/025/026, tests/skills/test-aai-feedback-upsert.sh; docs/ai/tdd/friction-upsert-channel-cannot-file-green.log; the exit-non-zero branch was uncovered until validation round 2 flipped it fail-OPEN and the suite stayed green | tdd:2026-09-05 | both failure modes covered: unparseable output AND a non-zero exit |
| Spec-AC-03 | The suite's `gh` stub exits non-zero for `search issues` with a `--state` value outside `{open,closed}`; against the PRE-FIX engine the suite is RED, and the RED is the dedup case, not a harness error | done | TEST-014, tests/skills/test-aai-feedback-upsert.sh; docs/ai/tdd/friction-upsert-channel-cannot-file-green.log | tdd:2026-09-05 | D3; the mock must be able to fail before its green can attest anything |
| Spec-AC-04 | WHEN a configured label is absent from the destination THEN the recorded `issue create` argv omits that label, the create still happens exactly once, and stderr names each dropped label | done | TEST-016/017/023/027, tests/skills/test-aai-feedback-upsert.sh; docs/ai/tdd/friction-upsert-channel-cannot-file-green.log; RED for this AC in docs/ai/tdd/friction-upsert-channel-cannot-file-red.log | tdd:2026-09-05 | D2; both arms, plus case-insensitivity and the truncation hedge |
| Spec-AC-05 | WHEN the label read itself fails THEN all labels are dropped, exactly one `issue create` is recorded, and stderr says the label set could not be read | done | TEST-018, tests/skills/test-aai-feedback-upsert.sh; docs/ai/tdd/friction-upsert-channel-cannot-file-green.log | tdd:2026-09-05 | the deliberate asymmetry against the dedup fail-closed |
| Spec-AC-06 | Every `gh` invocation the engine can emit is pinned to an exact FLAG SKELETON in the suite stub, which refuses anything else — the auth preflight, the dedup search, the label read, the issue create — and the mutating create's variable values (destination, title, filed body, redaction) are pinned by their own case | done | TEST-019/032, tests/skills/test-aai-feedback-upsert.sh; docs/ai/tdd/friction-upsert-channel-cannot-file-green.log; 19 deny-by-default probes plus the mutating create destination and content | tdd:2026-09-05 | four review rounds escaped an enumerated allowlist; this is the exact-skeleton replacement |
| Spec-AC-07 | A prepare run prints a `--publish` command for a cluster it cleared, and for a blocked cluster prints the blocking reason with NO `--publish` command on that line | done | TEST-020/024, tests/skills/test-aai-feedback-upsert.sh; docs/ai/tdd/friction-upsert-channel-cannot-file-green.log; RED for this AC in docs/ai/tdd/friction-upsert-channel-cannot-file-red.log | tdd:2026-09-05 | D4; both non-offered arms: blocked dedup and update_existing |
| Spec-AC-08 | `.aai/feedback.yaml` carries `triage.mode: review`; `bash tests/skills/test-aai-feedback-upsert.sh` and `bash tests/skills/test-aai-feedback-triage.sh` are green; the full sweep is green | done | TEST-021/028, tests/skills/test-aai-feedback-upsert.sh and tests/skills/test-aai-feedback-triage.sh; docs/ai/tdd/friction-upsert-channel-cannot-file-green.log; full sweep 86/86 | tdd:2026-09-05 | D5; mode AND destination pinned |

## Implementation plan

### Components
- **EDIT** `.aai/scripts/aai-feedback-upsert.mjs`
  - `dedupSearch`: drop `--state all`.
  - NEW `existingLabels(destination)`: `gh label list --repo <dest> --json name`,
    tri-state like `dedupSearch` — `{read:false}` on any failure or unparseable output.
  - confirm path: filter `cfg.labels` through it, name every drop on stderr, proceed.
  - prepare path: emit the `--publish` line only for a cleared cluster.
- **EDIT** `tests/skills/test-aai-feedback-upsert.sh`
  - stub validates `--state` for `search issues`;
  - stub answers `label list` from a controllable fixture;
  - argv assertions for all three call shapes;
  - new cases for the label degrade, the label-read failure, and prepare honesty.
- **EDIT** `.aai/feedback.yaml` — `triage.mode: review`.

### Out of scope
- Creating the `aai-friction` label in the destination. That is a repository
  change, not a code change, and belongs to the owner. D2 makes the channel work
  without it; a follow-up records the cosmetic gap.
- Raising `max_new_issues_per_7d`. The 3/7d budget is a deliberate rate limit;
  with 7 candidates it drains over three weeks by design, which is not a defect.
- Re-scoring or enriching the schema-v1 observations that lack `impact` /
  `confidence` and therefore never reach candidacy. Separate concern, follow-up.

## Constraints / Risks
- HAZ: the confirm path is the only mutating surface in the engine. Every new
  test that exercises it MUST run against the stub; no case may reach real `gh`.
- Tightening the stub may surface further argv drift in the same suite. That is
  the intent; if it widens the change, the widening is reported, not absorbed.
- `gh label list --json name` is itself an argv contract that can drift. It is
  covered by Spec-AC-06 for the same reason the search is.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                          | Description | Status |
|----------|------------|------|-----------------------------------------------|-------------|--------|
| TEST-013 | Spec-AC-01 | int  | tests/skills/test-aai-feedback-upsert.sh | a prepare run records a `search issues` argv containing `--repo`, `--match body`, the `aai-friction:<fp>` marker, `--json number` and `--limit 1`, and containing NO `--state` token | pending |
| TEST-014 | Spec-AC-03 | unit | tests/skills/test-aai-feedback-upsert.sh | the stub itself exits non-zero for `search issues --state all` and zero for `--state open`, proving the mock can distinguish a value real `gh` rejects | pending |
| TEST-015 | Spec-AC-03 | int  | tests/skills/test-aai-feedback-upsert.sh | RED control — with the stub tightened and the pre-fix `--state all` call restored via a fixture engine copy, the dedup case fails and its message names the dedup, not the harness | pending |
| TEST-011 | Spec-AC-02 | int  | tests/skills/test-aai-feedback-upsert.sh | forced search failure — `--publish <fp> --confirm` exits non-zero, stderr carries the unchanged refusal naming the fingerprint, and zero `issue create` lines are recorded | pending |
| TEST-016 | Spec-AC-04 | int  | tests/skills/test-aai-feedback-upsert.sh | label degrade — destination label set lacks `aai-friction`; the recorded `issue create` argv omits `--label aai-friction`, exactly one create is recorded, and stderr names the dropped label | pending |
| TEST-017 | Spec-AC-04 | int  | tests/skills/test-aai-feedback-upsert.sh | label kept — destination label set contains `aai-friction`; the recorded `issue create` argv DOES carry `--label aai-friction`, pinning both arms | pending |
| TEST-018 | Spec-AC-05 | int  | tests/skills/test-aai-feedback-upsert.sh | label read fails — the stub fails `label list`; all labels dropped, exactly one `issue create` recorded, stderr says the label set could not be read | pending |
| TEST-019 | Spec-AC-06 | int  | tests/skills/test-aai-feedback-upsert.sh | argv coverage — every recorded `gh` line across a prepare and a confirm run matches one of the three asserted shapes; an unrecognised `gh` subcommand fails the case | pending |
| TEST-020 | Spec-AC-07 | int  | tests/skills/test-aai-feedback-upsert.sh | prepare honesty — a cleared cluster prints a `--publish` command; a blocked cluster prints its blocking reason and no `--publish` on that line | pending |
| TEST-021 | Spec-AC-08 | int  | tests/skills/test-aai-feedback-triage.sh | `triage.mode: review` in the shipped `.aai/feedback.yaml` leaves the triage suite green and the engine reporting `mode=review` | pending |

## Amendment (unsigned, 2026-09-04)

The Test Plan's ids were renumbered TEST-001..010 -> TEST-011/013..021 because
`tests/skills/test-aai-feedback-upsert.sh` ALREADY owns TEST-001..TEST-012 with
unrelated meanings; the frozen numbering would have made every Evidence cell
ambiguous. Two further corrections to the frozen text, both made because the
plan did not survive contact with the constraint that a suite must never write
to the shipping repository:

- The planned RED control (a fixture copy of the engine with `--state all`
  restored) is replaced by a compositional pair: TEST-014 proves the stub
  REJECTS `--state all` as the CLI does, and TEST-015 proves the engine's source
  carries no `'--state'` token IN THE QUOTED ARGV FORM. TEST-015's predicate is
  `grep -qF -- "'--state'"`, so it constrains the argv literal only: the engine
  does contain the characters `--state` inside an explanatory comment, and a
  double-quoted variant would not be caught. It is a guard against regressing to
  the rejected call shape, not a proof that the string is absent from the file.
  Copying the engine into `.aai/scripts/` to mutate it would have tripped the
  tripwire; copying it elsewhere breaks its relative imports. The executed RED is
  preserved in `docs/ai/tdd/friction-upsert-channel-cannot-file-red.log`.
- TEST-019's argv coverage forced a change the spec did not anticipate: the
  stub recorded `echo "$@"`, so an issue body's newlines spilled into the call
  log and it could not be read back as a list of invocations. The stub now
  records one line per invocation.

This amendment is NOT owner-authorized. It is recorded in `docs/ai/decisions.jsonl`
with `owner_signoff: false` and carries an open tracked item.

## Amendment 2 (unsigned, 2026-09-04) — after validation round 1

Validation round 1 returned FAIL with three blocking findings. Two changed the
frozen design:

- **The argv class was not closed** (B1). The spec's Spec-AC-06 said "every `gh`
  invocation the engine can emit is covered by an argv assertion", and TEST-019
  as first written matched calls by SUBCOMMAND PREFIX only. Validation escaped it:
  an engine emitting `issue create ... --bodyy` and `label list ... --bogus-flag`
  kept the suite fully green while real `gh` rejects both. The mechanism moved
  from the test to the STUB: it now refuses any flag the subcommand does not
  define, and refuses an unpinned subcommand outright. A drifted flag anywhere
  in the engine now fails whichever case exercises that path, so no future call
  can be added without a test noticing. TEST-019 keeps the shape check and gains
  a positive control that the stub rejects each drift and accepts the real shape.
  The escape was re-run after the change and the suite goes RED.

- **The RED evidence was unclassified** (B2) and, when re-captured per case,
  exposed a defect in the tests themselves: cases 017..020 inherited their
  fixture from case 016, so in selected-case mode they failed with
  `mode=local (no destination)` — RED for the wrong reason, worthless as
  evidence. A `seed_single_candidate` helper now gives every case its own
  fixture, and the config with a labels list is built in `setup`.

TEST-021 (pinning the shipped `triage.mode: review`) was in the plan but had not
been written; validation flagged the omission and it is now present.

This amendment is NOT owner-authorized. It is recorded in `docs/ai/decisions.jsonl`
with `owner_signoff: false` and carries an open tracked item.

## Amendment 3 (unsigned, 2026-09-04) — after code review

Code review returned FAIL with two blocking findings and thirteen non-blocking.
Both blocking findings said the same thing in two places: a claim outran its
predicate.

- **The argv class was STILL open** (B1'). Amendment 2 made the stub reject
  UNKNOWN flags, and said it "refuses any flag the subcommand does not define".
  That is true and insufficient: a call also drifts by OMITTING a required flag
  or by carrying a value gh validates. Five mutations shipped a fully green
  suite — `auth status --bogus-flag` (kills every publish at the preflight),
  `issue create` without `--repo` (files into the operator's own repository, on
  the MUTATING path), `label list` without `--repo` (reads the local label set,
  reintroducing D2), `issue create` without `--title`, and `--sort bogus`. The
  stub now enforces three things: no unknown flag, every flag this engine's
  contract requires, and the values gh itself validates. The `auth status`
  preflight is checked like any other call; Spec-AC-06's enumeration omitted it,
  and the engine emits it on both paths.
- **TEST-015 claimed a universal negative** (B4). Amendment 1 had already made
  the SPEC honest about the predicate being quote-shaped, but the test's own
  name, header and pass-line still said "no `--state` in the engine". Correcting
  the spec and leaving the test's message overstated is the same defect this
  ride exists to fix. Renamed to `test_015_no_quoted_state_argv_literal`, with
  the scope stated in all three places.

Four non-blocking findings were also fixed because each was a live hazard rather
than a cosmetic one, and all four are additions beyond the frozen scope:

- A repeat `--publish --confirm` of the same fingerprint filed a DUPLICATE
  (`creates=2`, demonstrated). The remote search is authoritative but GitHub's
  index lags a fresh issue, so two confirmed publishes can both see an empty
  search. A local-ledger gate now precedes the network dedup. It only ever
  refuses, never authorizes. This hazard is newly reachable precisely because
  the channel can now file at all. Covered by TEST-022.
- `--limit 200` on the label read made "label does not exist" a claim the code
  could not support. The limit is now 500 and a full page reports "not among the
  first N" instead of asserting absence.
- Label matching was case-exact while GitHub's is case-insensitive, producing the
  same untrue message. Covered by TEST-023.
- Spec-AC-07 tested only the `blocked_dedup_unavailable` arm; offering a
  `--publish` for an `update_existing` cluster would have shipped green.
  Covered by TEST-024. Spec-AC-02's refusal-text clause is now asserted by
  TEST-025, and TEST-016/017/018 assert the engine's exit code rather than only
  the recorded create count.

Adding the local-ledger gate broke three PRE-EXISTING cases that reused one
fingerprint across publishes — the gate was doing its job. Each now clears the
local ledger explicitly. All 24 cases were re-verified to pass STANDALONE, not
only in suite order.

This amendment is NOT owner-authorized. It is recorded in `docs/ai/decisions.jsonl`
with `owner_signoff: false` and carries an open tracked item.

## Amendment 4 (unsigned, 2026-09-04) — after validation round 2

Validation round 2 returned FAIL with five blocking findings. Three were the same
guard failing to hold in a new place, and two were the evidence and the prose
drifting from the code.

- **The argv class was open for a THIRD time** (B1). The detector matched
  `--[a-z]*`, so every UPPERCASE long flag (`--Force`) and every SHORT flag
  (`-Z`) was invisible, and `--json` field names were unvalidated — `label list
  --json bogus` is the `--state all` defect verbatim, one call over: a
  permanently rejected read hidden behind a degrade. Two of the four escapes were
  on the MUTATING create path. Flag detection is now positional: any token
  starting with `-` is a flag, and values are consumed by position so a value
  beginning with `-` is never misread.
- **`--repo` was checked as a token, not a value** (B2). `--repo <dest> --repo
  attacker/evil` (gh is last-wins) and `--repo ''` (gh falls back to the LOCAL
  repository) both satisfied the required-flag loop that Amendment 3 had added
  specifically to prevent those two harms. Duplicate flags are now refused, the
  `--flag=value` form is refused, a flag left without its argument is refused,
  and `--repo` must be `owner/name`-shaped.
- **The fail-closed branch the real defect traversed was never tested** (B3).
  Every unverifiable-dedup case fed garbage on stdout at exit 0; nothing made the
  search EXIT NON-ZERO, which is what actually happened in production. Flipping
  `dedupSearch`'s `!r.ok` arm to fail-OPEN shipped a fully green suite. TEST-026
  covers it, and the mutation was re-run to confirm it now reddens.
- **The recorded evidence predated the code** (B4). Both logs are regenerated
  after the final change; the RED log had also still named a function that no
  longer exists.
- **The next overstatement** (B5). The spec's Out of scope said "a follow-up
  records the cosmetic gap" for the missing `aai-friction` label. No such
  follow-up existed at any status — a permanent silent degrade was shipping
  untracked while the spec asserted the opposite. Filed as
  `fu-friction-label-missing-in-destination`.

Two further corrections made while fixing the above:

- The Links section's registry claim was itself measured from a truncated
  command; corrected in place above.
- `newIssuesLast7d` crashed with an unhandled EISDIR on an unreadable ledger. It
  now returns the budget as EXHAUSTED rather than 0: an unreadable budget ledger
  must never read as "plenty of room left".

This amendment is NOT owner-authorized. It is recorded in `docs/ai/decisions.jsonl`
with `owner_signoff: false` and carries an open tracked item.

## Amendment 5 (unsigned, 2026-09-04) — after validation round 3

Round 3 found TEN escapes, all through the same enumerated gate, and that is the
finding: the gate was the wrong SHAPE, not missing entries. Each earlier round
added another allowlist entry and each next round found the entry that was
missing — `--match bodyy`, `--sort` (whose valid values differ per subcommand,
so one shared table is wrong in both directions), `--order`, a stray positional
on the mutating path, the `-R` alias.

The stub no longer enumerates anything. It pins the EXACT argv the engine is
permitted to emit — four shapes, positionally — and refuses everything else. A
renamed flag, a bad value, a stray positional, a reordering, a duplicate, an
alias, an `=`-form or an extra argument all fail by construction. Widening what
the engine may call now requires editing that list, which is the point.

**The claim is corrected with it.** "The values gh itself validates" (Amendment 3,
the suite header, the CHANGELOG) was a universal quantifier over a five-entry
table, and Amendment 2's "no future call can be added without a test noticing"
failed the same way. The stub is NOT a gh emulator and does not know gh's flag
universe. What it now guarantees is narrower and true: the engine emits only the
four pinned argvs. Spec-AC-06 is corrected to say so, and its closed list gains
`gh auth status`, which the engine emits on both paths and which the list omitted
even after Amendment 3 fixed the stub.

Four engine defects round 3 found, all fixed and each verified by mutation:

- The unreadable-ledger handling from Amendment 4 was WORSE than the crash it
  replaced: returning the budget as exhausted printed `budget reached (3/7d)` and
  exited **0**, permanently and silently blocking a legitimate publish under a
  reason that was false. Both local gates now share one read that refuses loudly,
  names the path, and exits non-zero (TEST-029).
- The ledger append AFTER a successful create was unguarded. If it throws, the
  issue exists and the duplicate guard is blind to it. It now exits non-zero with
  a message saying the issue was filed and must be recorded by hand.
- The shipped `destination` was unpinned: repointing it at another repository
  kept the suite green. A wrong destination is worse than a dead channel — it
  publishes the operator's friction somewhere else (TEST-028).
- The duplicate gate, the truncation flag, the case-insensitive label match and
  the auth preflight had no coverage that a mutation could redden. TEST-029..031
  and the mutation battery close that; five mutations were run and all five
  reddened.

This amendment is NOT owner-authorized. It is recorded in `docs/ai/decisions.jsonl`
with `owner_signoff: false` and carries an open tracked item.

## Amendment 6 (unsigned, 2026-09-05) — after validation round 4

Four blocking findings, and the first is the worst thing this ride produced.

- **A gate this scope ADDED silently killed a security test** (B1). TEST-010's
  second arm proves that a charset-clean secret token (`ghp_…`, `sk_live_…`,
  `AKIA…`) never reaches a `gh` argument. It reuses one fingerprint, and the
  new local-ledger duplicate gate short-circuited its publish — so the arm
  recorded no call at all and grepped an empty string. A mutation making
  `passesRedactor` return `true`, which would send a live credential verbatim to
  a PUBLIC issue, shipped a fully green suite. The arm now clears the ledger and
  ASSERTS that it filed, so it can never go vacuous unnoticed again. This is the
  general hazard of adding an early-exit gate: it can make an unrelated
  downstream assertion unreachable while every test still passes.
- **The mutating create's destination was pinned nowhere** (B2). The stub
  shape-checks `--repo` but pins no value, and TEST-028 pins the CONFIG FILE, not
  the argv that consumes it. `issue create --repo attacker/evil` shipped green —
  the exact harm Amendments 4 and 5 both claimed to have closed.
- **The filed content was unasserted** (B3). Every content assertion was against
  the DRAFT file; no confirmed publish in the suite ever ran with a `summary`
  present, so the transmit redaction was never exercised on the filed argv. A raw
  un-redacted summary as the title, and a body with the dedup marker stripped,
  both shipped green. TEST-032 pins all four properties on the write path.
- **The overstatement** (B4). "Pins the EXACT argv … a bad value fails by
  construction" is false for the wildcard slots (`--repo`, `--title`, `--body`,
  the marker suffix), and B2 was its executable counter-example. Corrected on all
  five surfaces to: the stub pins the exact FLAG SKELETON and shape-checks values;
  the values that matter are pinned by TEST-032.

Also fixed: a label refused by the config charset gate was dropped BEFORE the
destination was consulted, silently — while D2 promised every drop is named.
GitHub label names may contain spaces, so this discarded legitimate configuration
without a word (TEST-034). And the post-create ledger-append guard from
Amendment 5 had no test (TEST-033).

**Honest status.** Four review rounds have now found 3, 2, 10 and 4 findings; every
round found at least one overstatement, including this one. The defect rate is
falling and the last round's escapes were all in test coverage rather than in
shipped behaviour, but I cannot claim a fifth round would find nothing.

This amendment is NOT owner-authorized. It is recorded in `docs/ai/decisions.jsonl`
with `owner_signoff: false` and carries an open tracked item.
