---
id: spec-friction-channel-sweep
type: spec
status: implementing
mutation_gate: v1
frozen_sha256: bb13008a90c4f3b8bfb44c856c596873aaac487947b242f3dc290a7326ab1b10
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0190-friction-channel-sweep.md
  rfc: null
  pr: []
  commits: []
---

# Spec — the channel the owner reads says what happened, and says when it is not being read

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0190-friction-channel-sweep.md
- Paired maintenance half: docs/issues/CHANGE-0172-hand-authored-friction-is-second-class.md
- Second intake this scope settles: docs/issues/CHANGE-0179-friction-issues-arrive-without-a-description.md
- Mandate: docs/project-sessions/2026-09-13-wave-3-subsystem-sweeps.md (sweep 6)
- Sweep 5 (merged, the model for this one): docs/specs/SPEC-0184-spec-update-installs-ref-guard-undisclosed.md
- Mutation gate: docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md
- Owner decisions this scope implements, both `hitl_decision`, both
  `owner_signoff: true`, both 2026-09-05 in docs/ai/decisions.jsonl:
  `friction-triage-scoring-rewards-recurrence` and
  `friction-issue-body-is-prose-free`
- Protocol: .aai/system/FRICTION_PROTOCOL.md
- Technology contract: docs/TECHNOLOGY.md
- Ceremony table: .aai/workflow/WORKFLOW.md "Ceremony levels"
- Upstream report: GitHub `goodwind-cz/aai#361`

## Implementation strategy
- Strategy: tdd
- Rationale: every criterion here is either a REFUSAL (prose that must not
  reach a public issue, a recurrence that must not manufacture a candidate, an
  automatic path that must not admit a summary) or a DISCLOSURE (a NOTE naming
  a drop, a refusal naming its true exit status, a status line naming a stale
  report). Both shapes pass trivially when the code that implements them is
  absent: a capture that silently drops a summary satisfies "the record still
  persists", and a triage that promotes everything satisfies "the candidate is
  listed". A green run of such a control proves nothing, so every Test Plan row
  carries the mutation that must redden it and the RED is recorded first. The
  highest-hazard path in this repository — free text reaching a PUBLIC issue —
  is inside this scope, and its only honest gate is a test that has been seen
  to fail without the fix.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: the capture CLI writes the repository's own untracked
  spool at `docs/ai/friction/observations.jsonl`, and this scope's suites drive
  that CLI. A half-applied edit in the shared checkout does not fail a test; it
  corrupts the live evidence base three other sessions are appending to.
- User decision: worktree (already recorded in STATE)
- Base ref: main (e48c0bef)
- Worktree branch/path: feat/friction-channel-sweep at
  /Users/ales/Projects/aai-feat-friction-sweep
- Inline review scope: not applicable (worktree)
- Code review: required. Scope is the branch diff against main e48c0bef.

## Ceremony level

Level 2. Verified, not assumed: `protected_paths_l3` in docs/ai/docs-audit.yaml
lists `state.mjs`, `lib/state-engine.mjs`, `lib/state-core.mjs`,
`allocate-doc-number.mjs`, `pre-commit-checks.sh`, `pre-commit-checks.ps1`,
`.aai/workflow/WORKFLOW.md` and `docs/CONSTITUTION.md`. Not one file this scope
edits is on that list. The merge is covered by the standing internal merge
authorization of 2026-09-12 under the wave-3 mandate: nothing here changes a
consumer's git behaviour. It does change what the channel may transmit to a
PUBLIC repository, which is why Spec-AC-04 exists, not why the level is higher.

## What is established before this scope starts

Measured on 2026-09-25 against the tree at e48c0bef and against the LIVE spool
of the shared checkout (`/Users/ales/Projects/aai/docs/ai/friction/`, read
only, never written). Each fact is re-measurable by the command named with it.

1. **The live spool is 824 observations and 819 of them are one machine
   record.** `aai-run-tests.sh` lines 184-205 append one schema-v2 observation
   for every non-zero exit of a wrapped command, hard-coded to
   `skill_id: aai-run-tests`, `skill_phase: test-execution`,
   `failure_class: deterministic_script_failure`, `confidence: low`, and NO
   `impact`. Measured distribution: 819 of that exact shape, 2
   `close-work-item/close`, and 3 hook/hand-authored records carrying real
   signal. Every TDD RED run that goes through the wrapper adds one.
2. **The recurrence cap the owner decided no longer delivers what he decided.**
   The `hitl_decision` of 2026-09-05 reads: "RECURRENCE_CAP drops to 3 so
   recurrence can only PROMOTE a record that already carries signal, never
   create a candidate on its own." Its measured basis was a 65-record spool in
   which 56 records carried "neither impact nor confidence", i.e. signal 0.
   That premise is gone: today every record carries `confidence`, so the
   wrapper's clusters have signal 1, not 0. Re-measured over the 824-record
   spool with `score = maxSignal + min(recurrence-1, CAP)` and threshold 4:
   CAP 5 yields 56 review candidates, CAP 3 yields 56 — identical, because
   `1 + 3 = 4` is the threshold. The cap alone cannot hold the line the owner
   drew. Adding a signal FLOOR (recurrence contributes only to a cluster whose
   max signal is at least 2) yields 3 candidates, and those three are exactly
   the three high-signal records: `SKILL_VALIDATION/validation` (signal 8),
   `SKILL_FEEDBACK_UPSERT/remediation` (7), `SKILL_INTAKE/metrics` (6).
3. **The chain ends in a write nobody reads, and the numbers say so.** The
   committed discovery surface is `aai-feedback-status.mjs`, wired into
   `.aai/SKILL_WRAP_UP.prompt.md` step 6 and pinned by
   `tests/skills/test-aai-friction-wiring.sh` TEST-015. Nothing else in the
   factory invokes it: no tick, no close ceremony, no CI step. Measured on the
   shared checkout: the spool holds 824 observations, the committed
   `triage-report.json` reports `total_observations: 65` and was last written
   2026-09-05, the seven files in `pending-issues/` were prepared from that
   65-record snapshot, and `upsert-ledger.jsonl` holds exactly two
   `issue_created` records, both 2026-09-05. So 759 observations have never
   been triaged and nothing has been filed from this repository in 20 days.
   The status surface would nevertheless print "824 observation(s) captured ·
   7 draft(s) pending your --confirm" and point at a publish over drafts built
   from a stale report.
4. **The channel does work, from downstream.** `goodwind-cz/aai` currently
   carries open issues #390, #391 and #392, all filed 2026-09-24 from a
   Windows/node-24 downstream project, all `high impact`, all labelled
   `aai-friction`, all prose-free, and all carrying exactly one hand-written
   analysis comment added afterwards. The channel's automatic half still files
   telemetry; a human still supplies every sentence.
5. **`fu-friction-label-missing-in-destination` is resolved in the world, not
   in the code.** `gh label list --repo goodwind-cz/aai` shows `aai-friction`
   ("AAI-layer friction reported via the /aai-feedback channel"), and #369,
   #370, #390, #391 and #392 carry it. The permanent unlabelled degrade the
   item describes no longer happens.
6. **`harness` already reaches both downstream stages.** `aai-friction.mjs`
   derives it, `aai-feedback-triage.mjs` carries it through `ALLOWED_KEYS` and
   renders it per cluster, and `aai-feedback-upsert.mjs` renders it on the
   facts line through `safeHarness`. Pinned by `test-aai-feedback-triage.sh`
   TEST-014 and `test-aai-feedback-upsert.sh` TEST-064. Measured on the spool:
   817 records carry `harness: claude`.
7. **Prose is structurally impossible today, on every path.** Measured on the
   824-record spool: 0 records carry `summary` and all 824 carry
   `redaction_status: none`. `.aai/feedback.yaml` has
   `capture.summary_enabled: false`, and `aai-friction.mjs` `record()` consults
   ONLY that flag — there is no path by which a human who wrote and read a
   sentence can attach it. The downstream plumbing for prose already exists:
   `summary` is in the triage `ALLOWED_KEYS` and `buildPayload` already renders
   a certified summary as a blockquote. Only the capture gate is missing.
8. **`record` never names a dropped summary.** `record()` writes exactly
   `recorded <fingerprint>` on stdout and nothing else. A summary rejected by
   the redactor sets `redaction_status: capture_dropped_fields` in the file and
   says nothing to the caller; a summary supplied while the gate is off is
   dropped with `redaction_status: none`, which is byte-indistinguishable from
   "no summary was supplied". `redactSummary` already returns a `reason`
   (`over_length`, `control_char`, `unsafe_char`, `empty`, or a detector class)
   and the caller discards it. This is GitHub `#361`.
9. **Two of the three `gh` call sites in the upsert diagnose their failures;
   one does not, and one reports a success-shaped exit code on a refusal.**
   `existingLabels` (line 385, `catch` at 397) discards `runGh`'s result
   entirely, so its caller at line 659 prints "could not read the label set"
   with no exit status and no certified stderr, while the dedup and create
   sites both route through `ghRefusalLine`. Separately, `dedupSearch`'s
   JSON parse failure (line 376) returns the SUCCESSFUL process result, so the
   refusal at line 639 prints `(exit 0)` beside a message that is refusing.
10. **`learned-append.mjs` writes a house style the house does not use.**
    Line 159 returns one unwrapped line ending in a lowercase `(source: …)`.
    Measured on `docs/knowledge/LEARNED.md` at e48c0bef: 21 entries use
    `(Source: `, 15 use `(source: `, and 9 lines already exceed 200
    characters. The drift predates any single ride.
11. **LEARNED's own header admits an untriaged region.** 30 bullets live under
    the six `## Session …` headings; 10 carry a date and 4 carry a
    `[local]`/`[guard → id]` marker. The header says so explicitly and names
    `fu-triage-undated-learned-log` as the tracker.
12. **The append-only ledger merge is prose.** `docs/knowledge/LEARNED.md:283`
    carries `[guard → fu-learned-ledger-merge-procedure]` on a rule that
    describes the procedure (base side stays a byte-exact prefix, both
    branches' new lines appended after it, never accept an auto-merge without
    diffing the prefix) and names no command that performs it. Nothing in
    `.aai/scripts/` merges a JSONL ledger.
13. **The subsystem has one twin, and it is empty.** `aai-run-tests.ps1`
    contains no friction capture at all, so no Windows run has ever appended an
    observation. Every other file in scope (`aai-friction.mjs`,
    `aai-feedback-triage.mjs`, `aai-feedback-upsert.mjs`,
    `aai-feedback-status.mjs`, `learned-append.mjs`) is Node-only with no twin.
14. **Prompt-diet headroom is 1942 of a 2048 cap**, with
    `JUSTIFIED_GROWTH_BYTES == 35820` (measured:
    `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`,
    TEST-010 and TEST-012). The three corpus files this scope may touch are
    `.aai/SKILL_FEEDBACK_UPSERT.prompt.md` (2827 B),
    `.aai/SKILL_WRAP_UP.prompt.md` (8452 B) and
    `.aai/SKILL_FEEDBACK_TRIAGE.prompt.md` (1658 B).
15. **The live TEST id band ends at TEST-648** across docs/specs and
    tests/skills, excluding the synthetic TEST-900 and TEST-9xxx bands. This
    scope allocates from TEST-649.

## Decisions

**D1 — The owner's sentence is the decision; the cap was the mechanism he was
shown, and it no longer delivers it.** The signed decision reads "recurrence
can only PROMOTE a record that already carries signal, never create a candidate
on its own". Fact 2 measures that `RECURRENCE_CAP = 3` alone leaves 56 of 56
candidates standing, because the premise it rested on — 56 of 65 records
carrying neither scoring field — was retired by a capture point that now
supplies `confidence` on every machine record. This scope therefore delivers
BOTH: the constant drops to 3 exactly as decided and is pinned so a future edit
is a visible choice, AND a `SIGNAL_FLOOR` of 2 gates the recurrence bonus, so
the sentence is true independently of the threshold a project configures.
Additive with disclosure: nothing the owner decided is reversed, and the
deviation from the literal mechanism is stated here and reported with the
before/after list CHANGE-0172's Verification section demands. A floor of 2 is
the smallest value that admits the owner's own second arm — "a low/low record
(signal 2) with recurrence 3+ still is a candidate" — while refusing a record
carrying one lone field.

**D2 — Prose enters by a human act, never by a default.** `capture.summary_enabled`
stays `false` and the automatic path stays prose-free, exactly as the
2026-09-05 decision says. The promotion is an explicit CLI flag,
`record --promote`, readable only from argv: an input JSON key named `promote`
is dropped by the same D6 allowlist that drops every other unlisted key, so no
hook, no prompt and no wrapper can turn prose on by writing a field. The flag
admits a `summary` for certification; it does not exempt it from anything.

**D3 — A human author is not an exemption from redaction, and the test must
prove the write happened.** A promoted summary passes the capture-time redactor
and, independently, the transmit-time redactor, exactly as an automatic one
would. What is new is the standard of proof: each redaction arm carries a
POSITIVE CONTROL asserting that the record was actually appended (spool line
count grew by exactly one) or that the mutating call actually ran (creates
equals 1), because this repository has already shipped a vacuous green on this
exact surface — LEARNED's `[guard → fu-learned-positive-control-for-absence]`
entry records a mutation that would have sent a live credential to a public
issue under a fully green suite.

**D4 — The channel files the analysis comment when, and only when, the record
carries prose it has certified.** CHANGE-0179's AC-001 asks for one of two
outcomes: refuse to file a prose-free observation, or file a body a maintainer
can act on. Refusing is rejected on measurement: 824 of 824 live records are
prose-free (fact 7) and #390-#392 show the downstream channel filing prose-free
issues that a human then comments on by hand (fact 4). A refusal would close the
channel outright. So the flow does the work the human is doing: on a confirmed
publish whose record carries a CERTIFIED summary, it posts that prose as the
analysis comment itself, as a second mutating call under the same `--confirm`.
A prose-free record keeps today's behaviour exactly — one issue, and the
`gh issue comment` command PRINTED, never run. The comment is attempted only
when `parseIssueUrl` CERTIFIED the URL, because an uncertified number is not a
number this tool may write to.

**D5 — The comment failing must never unsay the issue.** The issue exists the
moment `gh issue create` returns. A failed comment is reported through the same
`ghRefusalLine` sanitizer with its real exit status, the ledger append still
happens, and the process exits non-zero naming what is owed — the same
discipline the ledger-append failure path already uses. Nothing rolls back.

**D6 — One sanitizer, all three call sites.** `existingLabels` returns its
`runGh` result like `dedupSearch` does, and its caller prints through
`ghRefusalLine`. A parse failure is a DIFFERENT failure from a process failure
and gets its own status rendering — `ghRefusalLine` never prints `exit 0`
beside a refusal, because a search that exited 0 and returned unreadable output
is refused for the parse, not for the exit.

**D7 — `fu-friction-label-missing-in-destination` is closed by evidence, and
label auto-creation is REJECTED.** The label exists (fact 5). The intake's
proposal — create it on first use, disclosed — would give the channel a
repository-administration mutation it deliberately does not hold: the whole
design is that the only write is one issue, behind one human `--confirm`. The
existing degrade (name every dropped label, file anyway) is already the right
behaviour and is already tested. Creating the label was an owner action and it
has been taken.

**D8 — The wrapper's automatic capture is NOT extended to the PowerShell
twin, and the reason is measured.** Fact 13 names the divergence; fact 1
measures what the POSIX side produces: 819 records that, after D1, generate
zero review candidates. Mirroring that into `aai-run-tests.ps1` would double a
volume this scope has just proved carries no signal. The honest fix is to
recalibrate what the wrapper records, which is the wrapper's own scope, not the
channel's. Filed as a follow-up with the measurement rather than built here.

**D9 — The discovery surface must state the backlog, not the inbox.** Fact 3
is the answer to "does anything verify that a filed observation reaches the
owner": nothing does, and the one surface that could is telling him to publish
drafts built from a 20-day-old, 65-observation snapshot while 759 newer
observations sit untriaged. Closing the whole loop — making something RUN the
surface on a schedule — is NOT this ride's job: it needs a decision about where
the owner is reached (a routine, the close ceremony, a PR comment) and that is
a product decision with an owner menu behind it. What IS this ride's job is
that the surface stop lying when it is run: report the review-candidate count,
name the report as STALE by comparing its own `total_observations` against the
live spool line count (a deterministic comparison, no wall clock), and make
`next` name triage rather than a publish over stale drafts. The scheduling half
is filed as a named follow-up, not left implied.

**D10 — Scope boundary.** The three `fu-amend-*` items whose subject matches
this subsystem (`fu-amend-friction-upsert-channel-ba7701`,
`fu-amend-friction-publish-hides-r-b86049`,
`fu-amend-lessons-that-must-hold-d-13bccc`) are owner sign-off obligations on
earlier specs, not defects in this subsystem. They are named in "Registry items
closed by this scope" as out of scope so they are not read as dropped, and they
are never placed in a sweep's bin. The GitHub API surface beyond issues,
comments and labels stays out, as the intake says.

## Constitution deviations

None.

## Acceptance Criteria Mapping

- Spec-AC-01: WHEN the triage engine scores a cluster, recurrence SHALL
  contribute only to a cluster whose maximum per-observation signal is at least
  `SIGNAL_FLOOR` (2), and `RECURRENCE_CAP` SHALL equal 3; a cluster of six
  zero-signal observations SHALL NOT be a review candidate, a cluster whose
  observations carry `confidence` alone SHALL NOT become one at any recurrence,
  a low/low cluster at recurrence 3 SHALL be one, and a single high/high
  observation SHALL be one. The already-delivered `harness` rendering in triage
  and in the issue payload SHALL close on its existing pins proven to redden
  under a named mutation rather than on a reading of the source.
  Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-feedback-triage.sh`
  over four synthetic fixture spools asserting the `decision` field of each
  cluster, plus `node .aai/scripts/mutation-run.mjs --replay --spec <this spec>`
  for the two harness rows, plus a re-run over a COPY of the live spool
  reporting the candidate list before and after (expected 56 to 3).

- Spec-AC-02: A hand-authored schema-v2 observation carrying `impact` and
  `confidence` SHALL persist both fields and SHALL be scored from them, while a
  schema-v1 record's persisted line SHALL stay byte-identical to the pre-v2
  tool's output.
  Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-friction.sh`
  comparing the appended JSONL line byte-for-byte against the expected object
  in each arm.

- Spec-AC-03: `node .aai/scripts/aai-friction.mjs record --promote` SHALL admit
  a `summary` for certification even while `.aai/feedback.yaml`
  `capture.summary_enabled` is `false`; the same input WITHOUT `--promote`
  SHALL persist no `summary`; an input JSON key named `promote` SHALL NOT
  enable it; and the automatic capture point in `.aai/scripts/aai-run-tests.sh`
  SHALL pass neither `--promote` nor any `summary`.
  Verification: three `record` runs asserting the presence and ABSENCE of the
  `summary` key in the appended line, plus a grep of the wrapper's record
  invocation for both tokens.

- Spec-AC-04: A promoted `summary` SHALL be persisted only when the
  capture-time redactor certifies it and SHALL be transmitted only when the
  transmit-time redactor certifies it independently; an uncertifiable summary
  SHALL be dropped in both passes exactly as an automatic one is, with the
  outcome recorded in `redaction_status`; and EACH arm SHALL carry a positive
  control that the append or the mutating call actually happened.
  Verification: two capture arms asserting the spool line count grew by exactly
  one and that the clean arm's text is present while the unsafe arm's is
  absent, plus two upsert arms asserting `creates == 1` and the exact bytes of
  the `--body` argument the `gh` stub received.

- Spec-AC-05: WHEN `record` drops a supplied `summary`, it SHALL write one NOTE
  line to stderr naming the reason — the capture gate when
  `capture.summary_enabled` is false and `--promote` was not given, or the
  redactor's own reason (`over_length`, `control_char`, `unsafe_char`, `empty`,
  or a detector class) when certification failed — and SHALL leave its stdout
  (`recorded <fingerprint>`) and its exit code unchanged.
  Verification: two `record` runs capturing stdout, stderr and the exit code
  separately, plus a wrapper run through `aai-run-tests.sh` proving the
  wrapper's own exit code is unchanged.

- Spec-AC-06: WHEN a confirmed publish files an issue for a record carrying a
  summary the transmit redactor certified AND `parseIssueUrl` certified the
  returned URL, the engine SHALL issue exactly one additional mutating
  `gh issue comment` call against the parsed number and the CONFIGURED
  destination, carrying that certified prose; WHEN the record carries no
  certified prose, or the URL was not certified, it SHALL issue no second
  mutating call and SHALL keep printing today's command; and WHEN the comment
  call fails, the issue SHALL remain filed, the ledger entry SHALL still be
  written, the failure SHALL be named with its real exit status through
  `ghRefusalLine`, and the process SHALL exit non-zero.
  Verification: a deny-by-default `gh` stub pinning the exact flag skeleton and
  the VALUES of every mutating call, asserting the call count and the argv of
  each in all four arms.

- Spec-AC-07: `existingLabels` SHALL return its `runGh` result and its caller
  SHALL render the refusal through `ghRefusalLine`, naming the exit status and
  the certified stderr detail; and a dedup search whose process exited 0 but
  whose output could not be parsed SHALL be refused as a PARSE failure, so no
  refusal line ever prints `exit 0`.
  Verification: a `gh` stub failing `label list` with a known exit code and
  stderr, and a second returning exit 0 with unparseable stdout; grep of each
  refusal line for the status token and for the absence of `(exit 0)`.

- Spec-AC-08: `learned-append.mjs` SHALL emit the house bullet — wrapped at no
  more than 76 characters per line with a two-space continuation indent and a
  capitalised `(Source: …)` — and the result SHALL still satisfy the script's
  own `isPureAppend` gate byte-exactly.
  Verification: an append into a fixture target, asserting every emitted line
  length, the continuation indent, the `(Source: ` literal, and that the
  resulting file equals the original plus the appended bytes.

- Spec-AC-09: A new `.aai/scripts/ledger-merge.mjs` SHALL merge two versions of
  an append-only JSONL ledger by keeping the base side as a byte-exact PREFIX
  and appending both sides' new lines after it, SHALL refuse with a non-zero
  exit and write nothing when the result would not carry the base as a prefix,
  SHALL report the line count contributed by each side, and SHALL be classified
  exactly once in `.aai/system/PROFILES.yaml` with a `tests/skills/suite-map.yaml`
  row for its suite.
  Verification: four fixture merges (disjoint additions, one side empty,
  identical sides, a base whose bytes were rewritten) asserting the exit code
  and a byte comparison of the result against the expected file, plus
  `grep -c` of the PROFILES entry and the suite-map row.

- Spec-AC-10: Every bullet under a `## Session …` heading in
  `docs/knowledge/LEARNED.md` SHALL carry exactly one `[local]` or
  `[guard → <id>]` marker, the header paragraph declaring that region
  untriaged SHALL be replaced by what is now true, and a lint rule SHALL refuse
  a Session bullet that carries no marker.
  Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh`
  with the new `learned-guard-lints.mjs` rule reporting zero findings on the
  live corpus and a non-zero count on a fixture with one unmarked bullet.

- Spec-AC-11: `aai-feedback-status.mjs` SHALL report the review-candidate count
  read from the triage report (0 when absent), SHALL name the report as STALE
  whenever its `total_observations` differs from the live spool's line count,
  naming both numbers, SHALL make `next` name the triage command rather than a
  publish whenever the report is absent or stale even while drafts exist, and
  `--json` SHALL carry `candidates`, `report_observations` and `report_stale`.
  Verification: four fixture friction directories (no report, a report matching
  the spool, a report behind the spool with drafts present, an empty spool)
  asserting the printed line, the `next` line and the `--json` fields; the
  stale arm's fixture reproduces the measured 65-against-824 shape.

- Spec-AC-12: The close ceremony SHALL surface the friction backlog, so what the
  factory learns about itself reaches the owner by default rather than when he
  remembers to ask. `close-work-item.mjs` — the script that actually runs, not a
  prompt step that describes one — SHALL print one line naming the untriaged
  count and the candidates that clear the signal floor, and a failure of that
  step SHALL degrade to a NOTE rather than block a close.
  Verification: a close over a spool with untriaged records prints the line and
  its counts; a close whose backlog step is made to fail still closes, with the
  NOTE; the line names candidates by the same scoring Spec-AC-01 defines, not a
  second one.

## Acceptance Criteria Status

| Spec-AC    | Description                                                         | Status  | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Recurrence promotes a scored cluster and never creates one          | planned | —        | —         | run 1 |
| Spec-AC-02 | A hand-authored observation carries its own signal                  | planned | —        | —         | run 1 |
| Spec-AC-03 | Prose enters by an explicit human act, never by a default           | planned | —        | —         | run 2 |
| Spec-AC-04 | Promoted prose is redacted twice and the write is positively proved | planned | —        | —         | run 2 |
| Spec-AC-05 | A dropped summary is named to the caller                            | planned | —        | —         | run 2 |
| Spec-AC-06 | The channel files the analysis comment it can certify               | planned | —        | —         | run 3 |
| Spec-AC-07 | Every gh refusal names its true cause and its true exit status      | planned | —        | —         | run 3 |
| Spec-AC-08 | The append gate writes the style the house reads                    | planned | —        | —         | run 4 |
| Spec-AC-09 | The append-only ledger merge is a command, not a memory             | planned | —        | —         | run 4 |
| Spec-AC-10 | Every Session lesson declares where its enforcement lives           | planned | —        | —         | run 4 |
| Spec-AC-11 | The discovery surface reports the backlog, not the inbox            | planned | —        | —         | run 4 |
| Spec-AC-12 | The close ceremony surfaces the backlog, so it reaches the owner by default | planned | —        | —         | —     |

## Implementation plan

Components affected:
- `.aai/scripts/aai-feedback-triage.mjs` — `RECURRENCE_CAP` drops to 3, a
  `SIGNAL_FLOOR` constant is added, and the cluster's `recurrenceBonus` is
  gated on `maxSignal >= SIGNAL_FLOOR`.
- `.aai/scripts/aai-friction.mjs` — a `--promote` flag on `record` parsed from
  argv only; the summary branch consults `promote OR loadSummaryEnabled()`; a
  NOTE is written to stderr for every drop, naming the gate or the redactor's
  `reason`; stdout and the exit contract are untouched.
- `.aai/scripts/aai-feedback-upsert.mjs` — `existingLabels` returns its
  `runGh` result; `dedupSearch`'s parse failure is distinguished from a process
  failure; the confirmed publish path gains one certified-prose analysis
  comment behind the URL certification, with its own refusal rendering.
- `.aai/scripts/aai-feedback-status.mjs` — the triage report is read for
  `total_observations` and the candidate count; staleness is the comparison of
  that number with the spool's line count; `next` and the `--json` object gain
  the new fields.
- `.aai/scripts/learned-append.mjs` — `formatRule` wraps and capitalises.
- `.aai/scripts/ledger-merge.mjs` — NEW.
- `.aai/system/PROFILES.yaml` — one classification entry for the new script
  (companion obligation, closed list).
- `tests/skills/suite-map.yaml` — a row for the new suite, and the friction
  suites' globs gain `.aai/scripts/ledger-merge.mjs` and
  `.aai/scripts/aai-feedback-status.mjs` where they are now asserted.
- `tests/skills/lib/learned-guard-lints.mjs` — one new rule, `session-marker`.
- `docs/knowledge/LEARNED.md` — the Session bullets gain their markers and the
  header paragraph is corrected.
- `.aai/system/FRICTION_PROTOCOL.md` — the promote path and the NOTE contract
  (not in the prompt-diet corpus glob).
- `.aai/SKILL_FEEDBACK_UPSERT.prompt.md`, `.aai/SKILL_WRAP_UP.prompt.md`,
  `.aai/SKILL_FEEDBACK_TRIAGE.prompt.md` — the three corpus files whose text
  describes behaviour this scope changes.

Companion obligations, both entries of the closed list apply:
- Prompt corpus bytes are added, so a `JUSTIFIED_ADDITIONS` entry is folded
  into `tests/skills/lib/prompt-diet-ledger.sh` with the MEASURED `wc -c` delta
  against e48c0bef, and TEST-012's `want_growth` is bumped from 35820 by
  exactly that number. Planned delta: about +900 B across the three files
  (roughly +450 B for the upsert prompt's comment contract, +250 B for the
  wrap-up prompt's corrected status line, +200 B for the triage prompt's signal
  floor). Headroom is 1942 B of a 2048 B cap, so the plan fits with room; if
  the MEASURED total exceeds 1942 B the ride stops and re-plans rather than
  raising the cap.
- A NEW `.aai/**` file is added (`ledger-merge.mjs`), so a classification entry
  is folded into `.aai/system/PROFILES.yaml` and asserted exactly once.

Edge cases the implementation must hold:
- A shell function invoked on the left of `||` runs with `set -e` SUSPENDED for
  its whole body. Any new shell helper in this scope is invoked so that its
  failure is seen, and its success line is gated on the work having succeeded —
  not printed unconditionally after it.
- The three readers of `.aai/feedback.yaml` (`aai-friction.mjs`,
  `aai-feedback-triage.mjs`, `aai-feedback-upsert.mjs`) each carry their own
  indentation and comment handling. This scope adds no key to that file; if a
  reader is touched at all, the same fixture set is fed to every reader that
  reads the same block, so they cannot hold three definitions of whitespace.
- No test may match production code by its literal spelling: an assertion that
  greps a source line breaks on any correct edit to that line. Where a `.ps1`
  or source-text assertion is unavoidable, it anchors on the construct's own
  site and is paired with a behavioural arm.
- The NOTE of Spec-AC-05 goes to stderr and must never reach stdout: the
  wrapper at `aai-run-tests.sh` redirects both to `/dev/null` and swallows the
  result, and the capture contract says a capture failure never changes the
  caller's outcome.
- `redaction_status` keeps its existing closed set; a promoted clean summary
  records `capture_clean` like any other certified one. No new persisted key is
  introduced, so the triage `ALLOWED_KEYS` gate is untouched and no existing
  spool line becomes `unsanitized_key`.
- The second mutating `gh` call must be counted by the deny-by-default stub as
  its own skeleton; a stub that matches by subcommand prefix would accept
  `issue comment` as `issue create`.

TDD slicing — four runs, grouped by the surface they share:
- Run 1: Spec-AC-01, Spec-AC-02 (the triage scoring engine and the capture
  schema it scores). One fixture builder serves both, and the two harness
  replay rows belong to the same engine.
- Run 2: Spec-AC-03, Spec-AC-04, Spec-AC-05 (everything `record` does with a
  summary). The promote flag, the double redaction and the NOTE are one code
  region and one contract; splitting them would leave a half-open prose path
  between runs, which is the one thing this subsystem must never ship.
- Run 3: Spec-AC-06, Spec-AC-07 (the upsert's `gh` boundary). All three call
  sites and the new fourth one share `runGh`, `ghRefusalLine` and one stub.
- Run 4: Spec-AC-08, Spec-AC-09, Spec-AC-10, Spec-AC-11 (the four surfaces that
  touch neither capture nor upsert), then the prompt-diet true-up, the full
  sweep and the close ceremony.

## Test Plan

Ids continue the live band; the highest real id in the corpus at planning is
TEST-648, so this scope allocates from TEST-649. Every row names its own suite
and selector; the mutation evidence for each is
`docs/ai/tdd/spec-friction-channel-sweep/mutation-<TEST-id>.txt`, produced by
`node .aai/scripts/mutation-run.mjs`.

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Mutation | Status |
|----------|------------|------|----------------------|-------------|----------|--------|
| TEST-649 | Spec-AC-01 | integration | tests/skills/test-aai-feedback-triage.sh | test_649_recurrence_only_promotes — four fixture spools: six zero-signal observations of one fingerprint decide `retain`; twenty confidence-only observations of one fingerprint decide `retain`; three low/low observations decide `review_candidate`; one high/high observation decides `review_candidate`. | Remove the signal gate on the recurrence bonus with sed:s/maxSignal >= SIGNAL_FLOOR/true/ so recurrence manufactures a candidate again. | pending |
| TEST-650 | Spec-AC-01 | unit | tests/skills/test-aai-feedback-triage.sh | test_650_recurrence_cap_pinned — the source declares RECURRENCE_CAP as 3 and a fixture of twelve low/low observations of one fingerprint scores exactly 5, proving the cap binds at 3 rather than at the member count. | sed:s/RECURRENCE_CAP = 3/RECURRENCE_CAP = 9/ so the twelve-member cluster scores 2 plus 9. | pending |
| TEST-651 | Spec-AC-01 | integration | tests/skills/test-aai-feedback-triage.sh | test_651_harness_pin_still_bites — the existing harness pin (TEST-014) is replayed under mutation, proving the delivered harness rendering in triage is closed by a test that reddens rather than by a reading of the source. | Make the closed-set sanitizer pass its input through with sed:s/HARNESS_VALUES.includes(v) ? v : 'unknown'/v/ so an out-of-set value is no longer normalized. | pending |
| TEST-652 | Spec-AC-01 | integration | tests/skills/test-aai-feedback-upsert.sh | test_652_harness_payload_pin_still_bites — the existing payload pin (TEST-064) is replayed under mutation, proving the harness field on the issue facts line is closed by a test that reddens. | Drop the harness clause from the facts line with sed:s/  harness: \$\{safeHarness\(rep.harness\)\}// so the rendered body omits it. | pending |
| TEST-653 | Spec-AC-02 | integration | tests/skills/test-aai-friction.sh | test_653_hand_authored_is_scoreable — a schema-v2 record carrying impact high and confidence high persists both keys and triages to signal 6; a schema-v1 record's appended line is byte-identical to the expected nine-key object. | Drop the impact copy from the v2 branch with sed:s/if \(v2.impact !== undefined\) persisted.impact = v2.impact;// so a hand-authored impact is silently lost. | pending |
| TEST-654 | Spec-AC-03 | integration | tests/skills/test-aai-friction.sh | test_654_promote_admits_prose — with capture.summary_enabled false, `record --promote` persists a clean summary, the same input without the flag persists no summary key at all, and an input JSON carrying a `promote` key persists no summary either. | Default the flag on with sed:s/let promote = false;/let promote = true;/ so the automatic path admits prose. | pending |
| TEST-655 | Spec-AC-03 | integration | tests/skills/test-aai-friction-capture-points.sh | test_655_wrapper_never_promotes — the wrapper's record invocation in aai-run-tests.sh contains neither a promote token nor a summary field, asserted by driving a real failing command through the wrapper against a fixture spool dir and reading the appended line. | Add the promote flag to the wrapper's record invocation so the automatic capture point becomes a prose path. | pending |
| TEST-656 | Spec-AC-04 | integration | tests/skills/test-aai-friction.sh | test_656_capture_redaction_both_ways — a promoted summary carrying a credential-shaped token is dropped with redaction_status capture_dropped_fields and its text is absent from the spool; a clean one persists with capture_clean and its exact text present; POSITIVE CONTROL — the spool line count grows by exactly one in each arm. | Certify unconditionally with sed:s/if \(r.ok\) \{/if (true) \{/ in the capture summary branch so an uncertified summary is persisted. | pending |
| TEST-657 | Spec-AC-04 | integration | tests/skills/test-aai-feedback-upsert.sh | test_657_transmit_redaction_independent — a spool line whose summary carries a credential-shaped token never reaches the gh argv while the issue is still filed with transmit_dropped; a certified one appears as the blockquote; POSITIVE CONTROL — the stub records creates equal to 1 in both arms. | Certify unconditionally in buildPayload's summary branch so the transmit pass stops being a second independent gate. | pending |
| TEST-658 | Spec-AC-05 | integration | tests/skills/test-aai-friction.sh | test_658_dropped_summary_is_named — with the gate off and no promote flag, stderr names the capture gate as the reason; with promote and a 201-character summary, stderr names over_length; in both arms stdout is exactly the recorded line and the exit code is 0. | Delete the NOTE write so the drop is silent again; the record still persists and the run still exits 0. | pending |
| TEST-659 | Spec-AC-05 | integration | tests/skills/test-aai-friction-capture-points.sh | test_659_note_never_masks_the_caller — a failing command driven through aai-run-tests.sh while the capture path emits a NOTE still exits with the wrapped command's own status, and the wrapper's stdout carries no NOTE text. | Make the NOTE path exit 3 instead of continuing so a capture diagnosis becomes a capture failure. | pending |
| TEST-660 | Spec-AC-06 | integration | tests/skills/test-aai-feedback-upsert.sh | test_660_certified_prose_is_commented — a confirmed publish of a record whose summary the transmit pass certified issues exactly two mutating calls, `issue create` then `issue comment <n> --repo <destination> --body <prose>`, where n is the number parsed from the certified URL; the deny-by-default stub pins the flag skeleton and the values of both. | Skip the comment call so the flow returns to printing the command it could have run. | pending |
| TEST-661 | Spec-AC-06 | integration | tests/skills/test-aai-feedback-upsert.sh | test_661_prose_free_and_failed_comment — a prose-free record files one issue and only PRINTS the comment command; a comment call that exits non-zero leaves the issue filed, still appends the ledger entry, names the failure with its exit status, and exits non-zero. | Make the prose-free branch also call comment, so a metadata-only record produces an empty second write. | pending |
| TEST-662 | Spec-AC-06 | integration | tests/skills/test-aai-feedback-upsert.sh | test_662_uncertified_url_never_commented — a gh create returning a foreign-host URL and one returning garbled stdout each produce the existing manual NOTE and exactly one mutating call. | Use the regex-parsed number without consulting the certification result so an uncertified URL is written to. | pending |
| TEST-663 | Spec-AC-07 | integration | tests/skills/test-aai-feedback-upsert.sh | test_663_label_refusal_names_status — a gh whose `label list` exits 4 with a known stderr line makes the filing print a refusal naming exit 4 and the certified detail, and the issue is still filed unlabelled. | Revert existingLabels to discard its runGh result so the caller has no status to name. | pending |
| TEST-664 | Spec-AC-07 | integration | tests/skills/test-aai-feedback-upsert.sh | test_664_parse_failure_is_not_exit_zero — a dedup search exiting 0 with unparseable stdout refuses naming the parse failure, and the refusal line contains no exit 0 token; a dedup search exiting 4 still names exit 4. | Return the successful process result from the parse-failure branch so the refusal reports exit 0 again. | pending |
| TEST-665 | Spec-AC-08 | integration | tests/skills/test-aai-learned-append.sh | test_665_house_style_bullet — an appended rule emits no line longer than 76 characters, every continuation line begins with exactly two spaces, the attribution reads `(Source: `, and the resulting file equals the original bytes plus the appended bytes. | Revert the formatter to a single unwrapped line with a lowercase source attribution. | pending |
| TEST-666 | Spec-AC-09 | integration | tests/skills/test-aai-ledger-merge.sh | test_666_merge_keeps_base_prefix — four fixture merges (disjoint additions, one side empty, identical sides, a base whose bytes were rewritten) each produce the expected bytes or the expected non-zero refusal, and the per-side line counts are reported. | Concatenate the two sides without the base-prefix check so a rewritten base merges silently. | pending |
| TEST-667 | Spec-AC-09 | unit | tests/skills/test-aai-ledger-merge.sh | test_667_new_script_is_classified — PROFILES.yaml classifies .aai/scripts/ledger-merge.mjs exactly once and suite-map.yaml carries a row for this suite naming that script. | Delete the PROFILES entry so the new file ships unclassified. | pending |
| TEST-668 | Spec-AC-10 | integration | tests/skills/test-aai-hygiene-pack.sh | test_668_session_bullets_carry_a_marker — the new learned-guard-lints rule reports zero findings over the live docs/knowledge/LEARNED.md and a non-zero count over a fixture whose Session section holds one unmarked bullet; the header no longer claims the region is untriaged. | Widen the rule's marker pattern to match any bracketed token so an unmarked bullet passes. | pending |
| TEST-669 | Spec-AC-11 | integration | tests/skills/test-aai-feedback-status.sh | test_669_status_reports_the_backlog — four fixture friction directories (no report, a report matching the spool, a report reporting 65 against a 824-line spool with drafts present, an empty spool) produce the expected printed line, the expected next command, and the expected candidates / report_observations / report_stale values under --json. | Compare the report against itself rather than the spool with sed:s/report.total_observations !== spoolLines/false/ so a stale report reads as current. | pending |
| TEST-670 | Spec-AC-11 | integration | tests/skills/test-aai-feedback-status.sh | test_670_stale_report_never_advertises_publish — with drafts present and a stale report, the next line names the triage command and not a publish; with drafts present and a current report it names the publish; the empty-spool arm stays silent on stdout while --json still emits the object. | Restore the draft-first ordering so a stale report still advertises a publish over its drafts. | pending |
| TEST-671 | Spec-AC-12 | integration | tests/skills/test-aai-close-work-item.sh | test_671_close_surfaces_the_backlog — a close prints the friction backlog line naming the untriaged count and the candidates worth the owner's attention, and a failure of that step degrades to a NOTE rather than blocking the close. | Neuter the backlog call so the close prints nothing and the operator learns nothing. | pending |
| TEST-672 | Spec-AC-06 | integration | tests/skills/test-aai-feedback-upsert.sh | test_672_comment_body_is_the_certified_blockquote — a comment call fires exactly when the filed body carries a certified blockquote, and its body is byte-identical to that blockquote rather than a second read of the same field. | Replace the certified summary with the raw one at both the gate and the body, which is the substitution that sent a token and a key path to a public repository while the suite stayed green. | pending |
| TEST-673 | Spec-AC-12 | integration | tests/skills/test-aai-close-work-item.sh | test_673_backlog_step_cannot_hang_a_close — a genuinely hung backlog child is bounded and degrades to a NOTE, so the close finishes instead of waiting on the network. | Remove the timeout from the backlog spawn so a hung child holds the close open. | pending |

## Seams

- S1 — capture writes the line triage reads and upsert transmits. Crossed by
  TEST-656 and TEST-657, which drive a REAL `record` run and then feed the
  resulting spool file to the upsert, rather than hand-building a spool line on
  either side.
- S2 — `aai-run-tests.sh` is a SHELL caller of the Node capture CLI, and its
  own exit code is a pinned contract. Crossed by TEST-655 and TEST-659, which
  run a failing command through the wrapper and read both the appended spool
  line and the wrapper's status.
- S3 — the triage report is written by one script and read by two others
  (`aai-feedback-upsert.mjs` and, newly, `aai-feedback-status.mjs`). Crossed by
  TEST-669, whose fixtures are reports a real triage run produced, never
  hand-authored JSON.
- S4 — the upsert's `gh` boundary is one seam with four call sites after this
  scope. Crossed by TEST-660 through TEST-664 against one deny-by-default stub
  that counts and pins every call, so a new call site cannot hide inside an
  existing skeleton.
- S5 — `learned-append.mjs` writes the file `learned-guard-lints.mjs` lints.
  Crossed by TEST-665 and TEST-668 read together: the appended bullet must
  satisfy the lint the same corpus is checked with.
- S6 — the prompt corpus and the diet ledger. Crossed by the TEST-012 re-sum in
  `tests/skills/test-aai-prompt-diet.sh`, run at the end of run 4.
- S7 — a seam NO automated test crosses, recorded rather than omitted: whether
  a filed issue is ever READ by a maintainer. Nothing in this repository can
  assert that, and this scope does not claim to.

## Residual risks

- The loop still closes on a human. After this scope the discovery surface
  tells the truth when it is run, but nothing RUNS it except
  `/aai-wrap-up`. Measured at planning: 824 observations, a triage report 759
  observations behind, two issues filed in twenty days. D9 states why
  scheduling is not decided here; the follow-up named below carries it.
- Prose reaching a PUBLIC repository is the highest-hazard path in this
  repository and this scope widens it by one deliberate command. The
  mitigations are two independent redaction passes, a flag readable only from
  argv, and a positive control on every redaction arm — the same three that
  were in place when a vacuous green shipped on this surface before. A fourth
  adversarial reading at validation is the residual.
- The automatic capture at `aai-run-tests.sh` keeps appending 100-plus records
  a week that, after Spec-AC-01, can never become candidates. The spool grows
  without bound and the signal-to-noise ratio of the file a human might read is
  unchanged. Recalibrating the wrapper's capture is the wrapper's scope; filed.
- `aai-run-tests.ps1` still captures nothing, so a Windows-only defect is still
  invisible to this channel. D8 records why extending it now would be the wrong
  direction; filed.
- The Session-section triage of Spec-AC-10 is a judgement applied to twenty
  bullets by one reader. The lint pins that a marker EXISTS; nothing pins that
  the marker is the RIGHT one.

## Verification

- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-feedback-triage.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-friction.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-friction-capture-points.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-feedback-upsert.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-feedback-status.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-learned-append.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-ledger-merge.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
- `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-DRAFT-spec-friction-channel-sweep.md`
- `AAI_TEST_TIMEOUT=3000 bash .aai/scripts/aai-run-tests.sh` (full sweep, once,
  before close)
- The before/after candidate report CHANGE-0172's Verification demands, run
  over a COPY of the live spool, never against the shared checkout's own
  files. Expected at planning: 56 candidates before, 3 after.
- PASS criteria: every TEST-xxx green, every mutation record RED on replay,
  every Spec-AC in a terminal status.

## Evidence contract

- ref_id: `friction-channel-sweep`
- Per TDD run: the RED log at `docs/ai/tdd/spec-friction-channel-sweep/` and
  the mutation record `mutation-<TEST-id>.txt` in the same directory, both
  cited in the AC Status Evidence cell.
- Per suite run: the command, its exit code and its output path.
- Code review: the branch diff against main e48c0bef, dual verdict.
- Strategy is `tdd`, so a stored RED artifact per AC-gating test is demanded
  and the mutation record is not optional.

## Registry items closed by this scope

Re-derived at planning from `node .aai/scripts/follow-ups.mjs list --status open`
(101 open) by subject, and each measured against the tree at e48c0bef and
against the live spool rather than taken from the intake's list.

FIXED BY THIS SCOPE, each by the named Spec-AC, each with a test a named
mutation reddens:

- `fu-existinglabels-discards-status` (P2) — Spec-AC-07, TEST-663
- `fu-upsert-refusal-prints-exit-zero` (P3) — Spec-AC-07, TEST-664
- `fu-learned-append-style-drift` (P3) — Spec-AC-08, TEST-665
- `fu-learned-ledger-merge-procedure` (P3) — Spec-AC-09, TEST-666, TEST-667
- `fu-triage-undated-learned-log` (P3) — Spec-AC-10, TEST-668

ALREADY FIXED IN THE TREE, closed on evidence plus a mutation that reddens the
existing pin, with no production-code change:

- The `harness` field reaching triage and upsert — Spec-AC-01, TEST-651 and
  TEST-652. Delivered by sweep 1 (`telemetry-fields-not-prose`) and already
  pinned by `test-aai-feedback-triage.sh` TEST-014 and
  `test-aai-feedback-upsert.sh` TEST-064; the intake listed it as work for this
  ride and it is not. Measured: 817 of 824 live records carry
  `harness: claude`.
- CHANGE-0172 AC-002, a hand-authored observation carrying `impact` and
  `confidence` — Spec-AC-02, TEST-653. Schema v2 has accepted both since
  RFC-0013; five live records carry them. What was missing was never the field,
  it was the scoring (Spec-AC-01) and the prose (Spec-AC-03).

CLOSED ON EXTERNAL EVIDENCE, no code and no test possible:

- `fu-friction-label-missing-in-destination` (P3) — the `aai-friction` label now
  exists in `goodwind-cz/aai` and issues #369, #370, #390, #391 and #392 carry
  it (`gh label list --repo goodwind-cz/aai`). The item named an owner action
  or a config removal as its two exits; the owner took the action. No test can
  pin a remote repository's label set, and this spec does not pretend
  otherwise.

NOT CLOSED — REJECTED BY THIS SCOPE, with the measured reason:

- The intake's proposal that the label be "created on first use, disclosed" —
  rejected per D7. The label exists, so the work has no subject; and giving the
  channel a repository-administration write would break the property the whole
  design rests on, that its only mutation is one issue behind one human
  `--confirm`.

NOT CLOSED — OUT OF SCOPE, named so they are not read as dropped:

- `fu-amend-friction-upsert-channel-ba7701` (P2),
  `fu-amend-friction-publish-hides-r-b86049` (P2) and
  `fu-amend-lessons-that-must-hold-d-13bccc` (P2) — owner sign-off obligations
  on three earlier frozen specs. They match this subsystem by subject and are
  not defects in it; a sweep never places an `fu-amend-*` item in its bin
  (D10).
- `fu-seed-partial-verdict-unasserted`, `fu-seeded-copies-lesson-no-guard`
  (both `tracked_by: test-framework-sweep`) and `fu-ledger-shrink-arm-unpinned`
  (`tracked_by: dispatch-state-sweep`) matched a keyword scan of this bucket
  and belong to those rides.

NOT CLOSED — FILED BY THIS SCOPE (new follow-ups, each with its measurement):

- `fu-friction-loop-has-no-scheduler` (P2) — nothing in the factory runs
  `aai-feedback-status.mjs` or the triage engine except `/aai-wrap-up`;
  measured 824 observations against a report 759 behind and two issues filed in
  twenty days (D9).
- `fu-runtests-capture-is-unscored-noise` (P2) — the wrapper's automatic
  capture supplies `confidence: low` and no `impact` on every non-zero exit,
  including every deliberate TDD RED run; 819 of 824 live records are that one
  shape and none of them can be a candidate after Spec-AC-01.
- `fu-runtests-ps1-captures-no-friction` (P3) — `aai-run-tests.ps1` has no
  capture point at all, so a Windows-only failure never reaches the channel
  (D8).

## GitHub issues

- Issue `goodwind-cz/aai#361` (`missing_or_invalid_artifact`,
  `aai-feedback-triage / friction-record`, medium impact, high confidence,
  `workaround: manual`, macOS, pin v2026.09.06) — FIXED by Spec-AC-05,
  TEST-658. The reporter's own sentence is in the body: "A summary over the
  length cap is dropped fail closed, but record still prints only success, so
  the caller learns nothing and can file an empty issue believing it carries
  prose." Both halves are delivered: the over-length drop is named with the
  redactor's `over_length` reason, and the gate-off drop — which the reporter
  did not name and which is the DEFAULT posture today — is named too. Closed at
  this ride's PR citing the criterion and its test.
- Issues `#338` and `#339`, which CHANGE-0179's AC-005 asks this scope to
  disposition: both are metadata-only bodies that cannot be reconstructed after
  the fact, because the prose was never captured (the spool holds no more than
  the issue does). They are LEFT OPEN as the evidence that produced D4, and the
  ride's PR comments on each naming the criterion that stops the next one
  arriving that way. Closing them would delete the measurement.

## Amendment 1 (post-freeze, 2026-09-25 — the owner routes the backlog into the close ceremony; ADDITIVE)

Planning measured that this factory's friction channel has been silent for
twenty days: 824 observations spooled, the last triage on 2026-09-05 seeing 65
of them, 759 never triaged, nothing filed from this repository since — while
the one surface that reports any of it would still have printed "824 captured,
7 drafts pending your --confirm" over drafts cut from that September snapshot.
The cause is that `aai-feedback-status.mjs` has exactly ONE caller in the whole
factory, `/aai-wrap-up` step 6, so it runs only when the owner asks. Planning
recorded that closing the loop needed a product decision about where the owner
is actually reached, and raised it as a menu (D9).

The owner answered **A on 2026-09-25**: fold it into the close ceremony, so
every merged ride ends with the backlog line. This section is the scope change
that answer makes, recorded with his sign-off because the canon assigns a
post-freeze scope change to the owner.

Added additively as **Spec-AC-12** with **TEST-671**; no existing Spec-AC, test
id, selector, file path or Mutation cell changes, and Spec-AC-11 still stands on
its own — the surface must stop lying whether or not anything calls it.

Two things the implementation must honour, both learned the hard way this month.
It goes in `close-work-item.mjs`, the script that runs, NOT in a prompt step
that describes one: this ride's whole subsystem exists because a chain ended in
a write nobody read, and four sweeps in a row found a control whose enforcement
was prose. And it must be best-effort: a backlog step that can block a close
would make every ride hostage to the reporting channel, which is the opposite of
the property being bought. That file is hash-pinned by four suites, so this work
belongs with the ride's single re-pin, written last.

Sign-off: owner.

## Amendment 2 (post-freeze, 2026-09-25 — validation round 1's four blocking findings)

**The call site this ride added had nothing guarding what it sends.** Replacing
the certified summary with the raw one, at the comment gate and at its body,
left the ENTIRE upsert suite green — including the arm written to catch exactly
that, because it greps only the `issue create` line and never looks at the
`issue comment` line or asserts that no comment was made. Under that
substitution a confirmed publish sent a token-shaped string and an SSH key path
to a public repository's issue comment, reproduced end to end. This spec's own
D3 names vacuous greens as the reason its positive controls exist, and the ride
reproduced one on the site it introduced. TEST-672 now pins the structural
property — a comment fires exactly when the filed body carries a certified
blockquote, and carries byte-identically that blockquote rather than a second
read — and TEST-657's arm inspects the whole recorded call set instead of one
line.

**The shipped contract said the opposite of the code.** `.aai/SKILL_FEEDBACK_UPSERT.prompt.md`
still told its reader that the comment command "only PRINTS that command, it
never runs it", and its safety model still named one mutating call, while
Spec-AC-06 had added a second. The Implementation plan named that file and it
was never touched; the delivery commit disclosed the diet accounting but not the
dropped plan item. Corrected, measured at +1022 B, credited 1:1 with the
TEST-012 pin moved by exactly that amount; headroom stays 1942 of 2048.

**The Registry section made twelve closure claims where it meant six.** Its
subsections used prose headings instead of the vocabulary the closure reader
understands, so bullets under REJECTED, OUT OF SCOPE and FILED read as claims
that those items were closed. `verify-closures --strict` went from rc=0 on main
to rc=1 here, and TEST-029's allowlist is drain-only, so this would have stayed
red in main AFTER the merge rather than clearing at the close. The three
sections now carry the `NOT CLOSED` label and the six genuinely resolved items
are closed for real; the checker is rc=0 repo-wide.

**Spec-AC-12 put an unbounded network call in the close path.** The owner's
amendment forbade a backlog step that could block a close, and the first
implementation could: `close-work-item.mjs` spawned a status tool that spawns
`gh`, with no timeout on either, where before this ride that file made no
network calls at all. With a hung stub the step was still running after ten
seconds. Both spawns are now bounded, the outer one overridable by environment,
and TEST-673 pins that a genuinely hung child degrades to a NOTE. The hang was
reproduced under an external watchdog rather than through the mutation runner,
because the runner has no suite timeout and cannot safely drive an unbounded
mutant — the evidence file is named outside the replay glob for that reason.

**One wording note carried rather than edited.** The residual-risk and D3 prose
calls the record-time and transmit-time redactions "independent". They are the
same function re-derived at two points in time, which is what the code and the
prompt say; nothing claims two algorithms. Read strictly the word could suggest
otherwise, and it is recorded here rather than rewritten, because an amendment
corrects and does not rewrite.

Sign-off: none (tracked).

