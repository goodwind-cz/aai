---
id: spec-adhoc-probes-unisolated-report-only
type: spec
number: null
status: implementing
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-0046-adhoc-probes-unisolated-report-only.md
  rfc: null
  pr: []
  commits:
    - 569320db948d0f65c1a6f855aeb6941ab7fe9570
---

# Spec — ad-hoc wrapper runs are named, and a closure claim is checked

SPEC-FROZEN: true

Two P2 registry items filed against `registry-audit-20260820`, both about a
guard that observes without ever saying so loudly enough to act on. They share
no code, so they are specified as two independent halves of one scope and the
Test Plan keeps them apart.

## Links
- Requirement: docs/issues/ISSUE-0046-adhoc-probes-unisolated-report-only.md
- The isolation mechanism this scope deliberately does NOT widen:
  docs/specs/SPEC-0138-spec-suites-run-in-a-disposable-worktree.md
- The report-only tripwire contract this scope preserves for suite runs:
  docs/specs/SPEC-0137-spec-suites-must-not-touch-the-shipping-repo.md,
  docs/specs/SPEC-0148-spec-the-tripwire-is-permanent-not-transitional.md
- The reporting vocabulary this scope extends without changing:
  docs/specs/SPEC-0144-spec-a-run-must-say-whether-isolation-armed.md
- The frozen decision that forbids wiring the registry into the close
  transaction: docs/specs/SPEC-0129-spec-followup-registry.md D5, pinned by
  `tests/skills/lib/close-work-item-pin.sh`
- Decision records: `docs/ai/decisions.jsonl`
  (`fu-adhoc-probes-unisolated-report-only`, `fu-spec-closes-claim-unverified`)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Measured starting state

Everything below was probed on `main` at planning time, through the canonical
wrapper, and is the RED baseline the Test Plan re-observes.

- HALF A. `bash .aai/scripts/aai-run-tests.sh node -e '<print toplevel/pwd/HEAD>'`
  printed `/Users/ales/Projects/aai`, `/Users/ales/Projects/aai` and `main`, and
  emitted **no** `AAI-ISOLATION` line at all: the `not-applicable` branch prints
  nothing by SPEC-0144's own design.
- HALF A. `bash .aai/scripts/aai-run-tests.sh sh -c 'echo probe > <repo>/PROBE-TRIPWIRE-TMP.txt; exit 0'`
  printed the three-line `AAI-TRIPWIRE FAIL` block, left the file on disk, and
  exited **0**. The block's trailing remediation line was the literal
  `A suite must run against a fixture, never against PROJECT_ROOT.` — a
  sentence about a suite, printed for an invocation that is not one.
- HALF B. Parsing every closure claim in `docs/specs/` and `docs/issues/` today
  and folding each id through `follow-ups.mjs list --status all --json` yields
  **three claims that are not true**:
  - `docs/specs/SPEC-0156-spec-agent-shell-can-write-the-shipping-repo.md`
    claims `fu-empty-path-cd-stays-in-shipping-repo` under `CLOSED
    QUALIFIEDLY`; the ledger folds it `open`.
  - `docs/issues/CHANGE-0146-role-verification-guards.md` claims
    `fu-validation-staleness-undetected` and `fu-tdd-skips-full-sweep`; the
    ledger folds both `open`.
  This scope reports those three. It does NOT amend either document and does
  NOT close those three items — they belong to the scopes that wrote them.
- HALF B. `resolved_by` values are heterogeneous by measurement — `ISSUE-0045`,
  `CHANGE-0165`, `cd-inside-command-substitution-hides-cwd`,
  `role-verification-guards` — so attribution cannot be an equality test. D8
  below is written from that measurement.

## Implementation strategy
- Strategy: hybrid
- Rationale: no intake-recorded choice exists for this ref (ISSUE-0046's
  `## Notes` carries no `Implementation mode (user choice):` line; STATE's
  current value is a leftover from the previous scope), so it is decided here.
  Spec-AC-01..05 and Spec-AC-06..11 are behavioural surfaces whose dominant
  failure mode is silence — a wrapper that prints nothing and a verifier that
  finds nothing both pass a badly written assertion vacuously — and the fixture
  harness to drive them RED already exists in both owning suites, so those take
  the TDD lane with a stored RED artifact per AC-gating test. Spec-AC-12 and
  Spec-AC-13 are a config row and a ledger transaction where a RED-first
  ceremony would only re-observe an unwritten line; those take the direct lane.
  `hybrid` is the value that names that split honestly.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: the scope edits `.aai/scripts/aai-run-tests.sh`, the
  canonical funnel every other test invocation in the session runs through. A
  half-applied edit there does not fail one suite, it fails the ability to run
  any suite, including the ones proving the edit. The scope is also PR-bound
  and spans two independent surfaces. Not `required`: no `protected_paths_l3`
  path is touched.
- User decision: undecided
- Base ref: main
- Worktree branch/path: to be chosen at Implementation Preparation
- Inline review scope: .aai/scripts/aai-run-tests.sh .aai/scripts/lib/repo-tripwire.sh .aai/scripts/follow-ups.mjs tests/skills/test-aai-suite-isolation.sh tests/skills/test-aai-follow-ups.sh tests/skills/suite-map.yaml docs/product/aai-decisions.md CHANGELOG.md

## Design decisions

### D1 — Three invocation kinds, one new name, the isolation SET unchanged
The wrapper already distinguishes a suite run, the framework opt-out and
everything else inside `aai_iso_is_suite_run`, but only the first two have
names. A third, `ad-hoc`, is named. Which invocations get a disposable checkout
does not change — the predicate that decides isolation is untouched, and
Spec-AC-03's byte-unchanged clause is what holds that.

### D2 — Isolation is NOT widened to ad-hoc commands, and the reason is recorded
SPEC-0138 scoped isolation to suite runs because a build or generator run in a
throwaway checkout has its artifact thrown away with the checkout. That argument
is unchanged and it is the same argument that forbids making an ad-hoc write
fatal by default: the corpus tells a vendored downstream project to run
`bash .aai/scripts/aai-run-tests.sh <project test command>`, and a project whose
test command builds writes into its own tree legitimately. A default that reds
every such project is a worse defect than the one being fixed. This scope
therefore fixes the two halves that are defects on their own terms — a report
that says the wrong thing, and a guard with no way to be given teeth — and
declines the redesign.

### D3 — The tripwire report becomes kind-correct; the suite report stays byte-identical
`aai_tripwire_report`'s trailing sentence is fixed text about suites. For an
`ad-hoc` invocation it is false, and it sends the reader looking for a fixture
that does not exist. The remediation line becomes a parameter of the report; the
`suite` and `framework` callers pass today's sentence verbatim, so their output
does not move a byte (SPEC-0137 D1/D2, SPEC-0148). The `ad-hoc` caller passes a
line naming the real remedy and the opt-in below.

### D4 — Silence is kept for a CLEAN ad-hoc run
SPEC-0144 decided that `not-applicable` prints nothing because a line on every
build is a line the operator learns to skip. That decision is respected exactly
where it was argued: a clean ad-hoc run stays silent (Spec-AC-02). The new line
appears only in the state SPEC-0144 never considered — the tripwire already
firing — where the invocation's kind is precisely the missing context.

### D5 — Opt-in teeth: `AAI_SHIPPING_WRITE_FATAL=1`, exit 12, failure fidelity kept
Unset, the wrapper's exit contract is byte-identical to today (Spec-AC-04): the
wrapped command's real status, or 124 at the watchdog. Set, and only for an
`ad-hoc` invocation whose tripwire state is `dirty`, a wrapped command that
exited **0** exits **12** instead. A wrapped command that already failed keeps
its own non-zero status — a real failure outranks the guard, and collapsing it
would destroy the information the caller actually needs. A suite run and the
framework are never affected by the flag.

12 is chosen as a code the wrapper does not otherwise produce and that sits
outside the documented band (78 config, 124 watchdog, 125 spawn, 126/127 exec).
It is not collision-proof against a wrapped command that itself exits 12, which
is why the named `AAI-ADHOC` line, not the number, is the observable.

### D6 — The friction spool is NOT a second sink, deliberately
A durable record in `docs/ai/friction` was designed and declined. The banner
plus the opt-in already deliver both visibility and teeth; a second sink for the
same event is unrequested surface (Constitution article 2) and would put a write
on a path this scope exists to keep quiet. Recorded here so the option is
visible as declined rather than unconsidered.

### D7 — The closure-claim gate is a `follow-ups.mjs` subcommand, not a close-ceremony wire
`close-work-item.mjs` is excluded by a frozen decision, not by preference:
SPEC-0129 D5 refuses to extend that script's snapshot/rollback transaction to a
second append-only ledger (its rollback arm truncates), and every entry in
`tests/skills/lib/close-work-item-pin.sh` re-affirms "no `--resolves` flag, no
`follow-ups.mjs` invocation, no `decisions.jsonl` reference added". Wiring the
check there would have to break that pin.

`docs-audit.mjs --check --strict` is excluded by measurement: TEST-028 in
`tests/skills/test-aai-deslop.sh` requires that verdict to be CLEAN, and three
real unverified claims exist on `main` today in documents this scope must not
amend. Putting the check in that verdict would red the repository's own gate on
someone else's frozen docs.

The check therefore lands as a `verify-closures` subcommand on
`follow-ups.mjs`, which already owns the ledger parse and fold, adds no new
`.aai/**` file, and carries no content-hash pin.

### D8 — Two verdict tiers, and only one of them can fail
`MISS` — a claimed id whose folded status is not `done`, an id absent from the
ledger included. This is the defect the item names and the only tier that moves
an exit code, and only under `--strict`.
`ATTRIBUTION` — a claimed id that IS `done` but whose `resolved_by` bears no
textual relation to the claiming document. Report-only, always, because the
measured `resolved_by` corpus mixes doc ids, requirement ids and ride-ref slugs;
a failing equality test over that corpus would be a false-alarm generator, which
is the failure mode this whole scope is written against.

### D9 — The parser's conservative default, derived from the corpus not invented
Measured over all nine documents that carry a closure statement today, four
shapes exist. The rules that read all four correctly:
- Labelled section: ids under `CLOSED FULLY` / `CLOSED QUALIFIEDLY` are claims;
  ids under `NOT CLOSED` are disclaimed.
- Unlabelled section opening with the `none` sentinel: zero claims; every id in
  it is a neighbour being discussed, not claimed.
- Any other unlabelled section: every `fu-` id in it is a claim.
- Inline label `Registry items closed:` / `Registry items closed by this scope:`
  — the claim list is the rest of that statement. The neighbouring
  `Registry items the ratchet holds open:` label is NOT matched, by exact label.

### D10 — The enforcement is a ratchet arm, not a prompt line
Making a role run the check would cost `.aai/*.prompt.md` bytes and would still
depend on the role remembering. A subset ratchet in
`tests/skills/test-aai-follow-ups.sh` runs on every sweep and in CI: a later
close drains the allowlist and still passes; a NEW unverified claim reds. This
scope therefore spends **zero** prompt-corpus bytes, and the prompt-diet
companion obligation does not apply.

## Acceptance Criteria Mapping
- Maps to: ISSUE-0046 `fu-adhoc-probes-unisolated-report-only` (Spec-AC-01..05)
- Maps to: ISSUE-0046 `fu-spec-closes-claim-unverified` (Spec-AC-06..12)
- Maps to: ISSUE-0046 `## Notes` closure discipline (Spec-AC-13)

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the wrapper runs a command whose executed script is neither a suite file under the repository tests tree nor the repository own tests/skills/test-framework.sh AND the tripwire post-run state is dirty THEN the wrapper SHALL print exactly one stderr line beginning `AAI-ADHOC: ` that names the shipping repository path as the command working tree | implementing | — | — | verify in a fixture repo; count of lines matching the prefix is exactly 1 |
| Spec-AC-02 | WHEN an ad-hoc invocation leaves the shipping repository clean THEN the wrapper SHALL print no `AAI-ADHOC` and no `AAI-ISOLATION` line at all | implementing | — | — | D4; SPEC-0144 no-line-per-build decision preserved |
| Spec-AC-03 | WHEN the tripwire reports dirty for an ad-hoc invocation THEN the trailing remediation line SHALL name the ad-hoc remedy and SHALL NOT be the suite sentence about fixtures and PROJECT_ROOT AND for a suite run and for test-framework.sh the whole tripwire block SHALL be byte-identical to the pre-change capture | implementing | — | — | D3; the byte-identical half is the SEAM-1 assertion |
| Spec-AC-04 | WHEN `AAI_SHIPPING_WRITE_FATAL` is unset THEN an ad-hoc invocation that dirties the shipping repository SHALL exit with the wrapped command own status | implementing | — | — | D5; two runs, wrapped status 0 and 7 |
| Spec-AC-05 | WHEN `AAI_SHIPPING_WRITE_FATAL=1` AND the invocation kind is ad-hoc AND the tripwire state is dirty THEN the wrapper SHALL exit 12 if the wrapped command exited 0 and SHALL preserve the wrapped command own non-zero status otherwise AND the flag SHALL NOT change the exit code of a suite run or of test-framework.sh | implementing | — | — | D5; four runs, one per branch |
| Spec-AC-06 | `node .aai/scripts/follow-ups.mjs verify-closures --path <doc>` SHALL parse closure claims from both recognized shapes (the `## Registry items closed by this scope` section and the exact inline labels) and report every claimed fu- id together with its folded ledger status | implementing | — | — | D9; fixture docs of both shapes |
| Spec-AC-07 | WHEN a claim section carries CLOSED FULLY or CLOSED QUALIFIEDLY labels THEN ids under them SHALL be claims AND ids under a NOT CLOSED label SHALL be disclaimed AND an unlabelled section whose first non-blank content begins with the none sentinel SHALL yield zero claims AND any other unlabelled section SHALL treat every fu- id in it as a claim | implementing | — | — | D9; four fixture docs, one per branch, exact set equality |
| Spec-AC-08 | A claimed id whose folded status is not done (an id absent from the ledger included) SHALL be reported as MISS AND a claimed id that is done but whose resolved_by bears no textual relation to the claiming document SHALL be reported as an ATTRIBUTION note that never affects the exit code | implementing | — | — | D8; one fixture carrying one of each |
| Spec-AC-09 | `verify-closures` SHALL exit 0 in report-only mode regardless of how many misses it found, exit 1 under `--strict` when at least one MISS exists, and exit 2 on a usage error or an unreadable ledger or path | implementing | — | — | three runs, one per code |
| Spec-AC-10 | `verify-closures` with no `--path` SHALL walk docs/specs and docs/issues and report the union of claims and misses across both roots, and a document carrying no closure statement SHALL contribute zero claims and no error | implementing | — | — | fixture with one claiming spec, one claiming issue, one silent doc |
| Spec-AC-11 | A suite arm SHALL run corpus mode against the real repository and fail when the MISS set is not a subset of the declared known-unverified allowlist in tests/skills/test-aai-follow-ups.sh AND that allowlist at delivery SHALL contain exactly the three measured entries | implementing | — | — | D10; ratchet, subset not equality, so a later close drains it |
| Spec-AC-12 | The aai-follow-ups row in tests/skills/suite-map.yaml SHALL glob docs/specs and docs/issues so a new document carrying a closure claim selects this suite | implementing | — | — | the seam that keeps the ratchet reachable from a docs-only diff |
| Spec-AC-13 | Both registry items named by ISSUE-0046 SHALL be closed in the ledger with resolved_by naming this scope ref AND the delivery diff SHALL contain no other scope frozen document and SHALL close no other registry item | implementing | — | — | the three measured misses are reported, never amended away |

Status values: planned | implementing | done | deferred | blocked | rejected
- planned: AC defined, no implementation started
- implementing: work in flight; not allowed at PASS claim time
- done: implementation complete; requires non-empty Evidence (commit SHA or RUN_ID)
- deferred: explicitly postponed; requires Review-By in the future (minimum +14 days) + Notes naming target doc or reason
- blocked: implementation cannot proceed; requires Review-By + Notes naming blocker
- rejected: AC will not be implemented; requires Notes with rationale; no Review-By needed (terminal)

## Implementation plan

Components affected:
- `.aai/scripts/aai-run-tests.sh` — a computed invocation kind, the ad-hoc
  banner, the `AAI_SHIPPING_WRITE_FATAL` branch on the existing tripwire
  `dirty` arm. No change to `aai_iso_is_suite_run`'s predicate, to the
  isolation block, or to the default exit paths.
- `.aai/scripts/lib/repo-tripwire.sh` — `aai_tripwire_report` gains a
  remediation-line parameter, defaulted to today's sentence so no caller
  changes behaviour by omission.
- `.aai/scripts/follow-ups.mjs` — a `verify-closures` subcommand: doc walk,
  claim parse (D9), fold against the existing ledger reader, two verdict tiers
  (D8), `--path` / `--strict` / `--json`, exits 0/1/2.
- `tests/skills/test-aai-suite-isolation.sh` — five new arms (Spec-AC-01..05),
  reusing the existing `new_fixture` harness that already runs
  `sh -c 'printf built > ...'` through the copied wrapper.
- `tests/skills/test-aai-follow-ups.sh` — six new arms plus the ratchet
  allowlist (Spec-AC-06..11).
- `tests/skills/suite-map.yaml` — two globs on the `aai-follow-ups` row.
- `docs/product/aai-decisions.md` — one paragraph documenting
  `verify-closures`, alongside the existing documented manual close step.
- `CHANGELOG.md` — one `## [unreleased] — <title>` entry.

Seams this change shares with code it does not own:
- SEAM-1: the kind classification reads the same predicate the isolation gate
  reads. Producing a kind must not move a single invocation out of the isolated
  set. Crossed by TEST-003, which asserts a suite run still prints
  `AAI-ISOLATION: isolated` and its tripwire block is byte-identical.
- SEAM-2: the wrapper's exit code is consumed by `tests/skills/test-framework.sh`,
  `.aai/SKILL_LOOP.prompt.md` and `.aai/VALIDATION.prompt.md`. 12 must be
  unreachable by default. Crossed by TEST-004, which runs the wrapper with the
  flag unset over a dirtying command and asserts the wrapped status survives.
- SEAM-3: `follow-ups.mjs`'s existing `list`/`add`/`close` argv parse and its
  0/1/2 exit contract. A new subcommand must not move them. Crossed by
  TEST-012, which re-runs the pre-existing `list --json` assertions unchanged.
- SEAM-4: the claim parser reads documents that `docs-audit.mjs` and
  `generate-docs-index.mjs` also parse. A document it cannot parse must
  contribute zero claims, never an error. Crossed by TEST-010's silent-doc arm
  and by TEST-011 running corpus mode over the real tree at exit 0.

Edge cases:
- An ad-hoc command that dirties the repo AND is killed by the watchdog: 124
  outranks 12 (the watchdog branch runs first and is unchanged).
- A claim section naming an id that is not in the ledger at all: MISS, with the
  reason `absent` rather than a status word.
- A claim id longer than the registry's 40-character cap: parsed, folded,
  reported `absent` — the parser never rewrites an id to make it fit.
- A document with two claim statements (a section and an inline label): the
  union of both, deduplicated.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-suite-isolation.sh | fixture repo, ad-hoc command writes a stray file, stderr carries exactly one `AAI-ADHOC: ` line naming the fixture root | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-suite-isolation.sh | fixture repo, ad-hoc command writes nothing, stderr carries zero `AAI-ADHOC` and zero `AAI-ISOLATION` lines | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-suite-isolation.sh | ad-hoc dirty run carries zero occurrences of the suite fixture sentence; a dirtying suite run carries exactly one and its whole tripwire block matches the stored pre-change capture byte for byte (SEAM-1) | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-suite-isolation.sh | flag unset, ad-hoc dirty command exiting 0 gives wrapper exit 0 and exiting 7 gives wrapper exit 7 (SEAM-2) | green |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-suite-isolation.sh | flag set, four runs: ad-hoc dirty exit 0 gives 12, ad-hoc dirty exit 7 gives 7, ad-hoc clean exit 0 gives 0, dirtying suite run exit 0 gives 0 | green |
| TEST-006 | Spec-AC-06 | integration | tests/skills/test-aai-follow-ups.sh | fixture ledger plus one doc of each recognized claim shape; `verify-closures --path --json` lists both shapes' ids with their folded statuses | green |
| TEST-007 | Spec-AC-07 | integration | tests/skills/test-aai-follow-ups.sh | four fixture docs, one per parse branch; the claimed and disclaimed sets match the expected sets exactly, not by count | green |
| TEST-008 | Spec-AC-08 | integration | tests/skills/test-aai-follow-ups.sh | fixture with one open-claimed id and one done-but-foreign-resolved_by id gives exactly one MISS, one ATTRIBUTION, exit 0 | green |
| TEST-009 | Spec-AC-09 | integration | tests/skills/test-aai-follow-ups.sh | three runs give 0 report-only with misses present, 1 under `--strict` with a miss, 2 on an unreadable `--path` | green |
| TEST-010 | Spec-AC-10 | integration | tests/skills/test-aai-follow-ups.sh | fixture corpus with one claiming spec, one claiming issue and one doc carrying no claim statement; both claims appear, the silent doc contributes zero claims and no error (SEAM-4) | green |
| TEST-011 | Spec-AC-11 | integration | tests/skills/test-aai-follow-ups.sh | corpus mode over the real repository at exit 0, MISS set is a subset of the declared allowlist; a fixture claim outside the allowlist fails the arm; the allowlist holds exactly the three measured entries | green |
| TEST-012 | Spec-AC-12 | unit | tests/skills/test-aai-follow-ups.sh | `select-suites` over a changed `docs/specs/*.md` selects `aai-follow-ups`; the pre-existing `list --json` assertions are re-run unchanged (SEAM-3) | green |
| TEST-013 | Spec-AC-13 | integration | tests/skills/test-aai-follow-ups.sh | `follow-ups.mjs list --ref registry-audit-20260820 --status all --json` folds both ids done with resolved_by naming this scope; the delivery diff names no other scope frozen document | green |
Test status values: pending → red → green
- pending: test not yet written
- red: test written and verified failing (TDD RED phase)
- green: test passes with implementation

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- Test IDs are stable — do not renumber after freeze.

## Verification

Commands:
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-suite-isolation.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-follow-ups.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-repo-tripwire.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-run-tests.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh` (one full sweep before close)
- `node .aai/scripts/follow-ups.mjs verify-closures --json`
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
- `node .aai/scripts/spec-lint.mjs`

Evidence artifacts: stored RED artifacts under `docs/ai/tdd/` for the
AC-gating tests of Spec-AC-01..11; captured stderr for the wrapper arms; the
`verify-closures --json` corpus output naming the three measured misses.

PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
For each implementation, validation, TDD and code review artifact, record:
- ref_id
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

### Evidence by strategy

| Strategy     | Evidence this spec may demand                                   |
|--------------|-----------------------------------------------------------------|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix — unchanged |
| loop         | per-TEST-xxx green runs; RED-proof observed, storage optional    |
| direct       | targeted regression tests green (exit codes) plus the scoped diff — NO stored RED artifact, NO matrix beyond the declared versions |
| untested     | the recorded strategy rationale plus the scoped diff — no test suites demanded for the scope itself |

This scope is `hybrid`: Spec-AC-01..11 owe a stored RED artifact; Spec-AC-12
and Spec-AC-13 owe the targeted green plus the scoped diff.

## Residual risks

- RR-1 — Windows. `aai-run-tests.ps1` delegates to this `.sh` under WSL, so the
  ad-hoc banner and the fatal opt-in are inherited on that leg and are covered
  by nothing new here. The Git-Bash degraded leg has no POSIX session and is
  field-verified only, exactly as the SPEC-0046 matrix already records. No
  automated test crosses that seam.
- RR-2 — `AAI_SHIPPING_WRITE_FATAL` is off by default (D2's argument forbids
  otherwise), so an operator who never sets it gets the escalated banner and no
  gate. That is a deliberately partial close and Spec-AC-13's wording says so.
- RR-3 — D9's parser is derived from the nine documents that exist today. A
  tenth shape written tomorrow parses as "every id in an unlabelled section is a
  claim", which can produce a false MISS. The ratchet's subset form is what
  keeps that from being a hard stop, and the ATTRIBUTION tier is report-only for
  the same reason.

## Registry items closed by this scope

Read from `node .aai/scripts/follow-ups.mjs list` at planning time (85 open).

CLOSED FULLY:

- `fu-adhoc-probes-unisolated-report-only` (P2) — its words are "aai-run-tests.sh
  isolates suite runs only, by design, so every generator, build, node one-liner
  and probe a role runs through the canonical wrapper executes in the shipping
  tree with a guard that cannot fail the run". Both named halves are answered:
  the run now says which tree it used at the moment that matters (D3, D4), and
  the guard can be given teeth (D5). The isolation half is answered by refusal
  with a recorded reason (D2), which is what the item asks for — it names the
  design, it does not demand its reversal.
- `fu-spec-closes-claim-unverified` (P2) — its words are "a spec's 'Registry
  items closed by this scope' line is never checked against the ledger". It is
  checked now, over both recognized shapes, in a mode that runs on every sweep
  (D10), and the check's first run names three real claims that were never true.

NOT CLOSED, deliberately, with the reason:

- `fu-wrapper-hidden-suite-run-unreported` (P2, ref
  retire-the-tripwire-behind-its-replacement) — the sibling this dispatch
  names. It is about a real SUITE run whose command shape hides the suite path,
  so it is misclassified and runs unisolated while CLEAN. This scope changes
  nothing about the classification predicate (D1, held by Spec-AC-03) and adds
  no line for a clean run (D4), so that item is untouched. It gains one
  mitigation only: if such a run also writes, it now gets the ad-hoc banner
  instead of the suite sentence. Not enough to claim it.
- `fu-probe-redirect-lands-in-shipping-cwd` (P2, ref
  isolation-shares-the-shipping-git) — an ad-hoc probe's relative redirect
  creating a stray file. SPEC-0156 already recorded that PREVENTING it needs a
  filesystem chokepoint that does not exist below the OS, and this scope adds
  none. What changes is DETECTION: that write is exactly the case D3 now names
  correctly and D5 can fail. Detection is not prevention, so the item stays
  open with the mitigation recorded.
- `fu-filed-list-trusted-again` (P2, ref suites-run-in-a-disposable-worktree) —
  a role's `filed:` list trusted as proof an entry EXISTS. Adjacent to
  Spec-AC-06..11 in spirit and opposite in direction: this scope verifies
  CLOSURE claims against the ledger, not FILING claims. Widening the same
  subcommand to cover it is a real follow-on and would break the scope-only
  constraint ISSUE-0046 sets.
- `fu-iso-wrapper-traps-dont-reap-group` (P2) and
  `fu-isolation-suite-not-hermetic` (P2) — both live in files this scope edits
  and neither shares its subject (signal-path group reaping; a suite inheriting
  `AAI_TEST_ISOLATION` instead of stating it). Same files, different defects,
  not claimed.

NOT CLOSED, and not this scope's to close — the three claims the new check
reports on its first run:

- `docs/specs/SPEC-0156-...` claiming `fu-empty-path-cd-stays-in-shipping-repo`,
  and `docs/issues/CHANGE-0146-...` claiming `fu-validation-staleness-undetected`
  and `fu-tdd-skips-full-sweep`. This scope reports them and ratchets them
  (Spec-AC-11). Closing them would mean either fixing three unrelated defects or
  writing a closure that is as untrue as the claim being audited.

No new registry items are filed by this scope.

## Notes
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
