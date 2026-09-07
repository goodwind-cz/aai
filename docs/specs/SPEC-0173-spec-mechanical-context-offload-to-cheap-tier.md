---
id: spec-mechanical-context-offload-to-cheap-tier
type: spec
number: 173
status: implementing
ceremony_level: 2
links:
  requirement: docs/specs/RES-0002-mechanical-context-offload-to-cheap-tier.md
  rfc: null
  pr: []
  commits: []
---

# Spec — offloading mechanical context work to a cheap tier (research spike)

SPEC-FROZEN: true

## Links
- Requirement: `docs/specs/RES-0002-mechanical-context-offload-to-cheap-tier.md` (the research intake; it is also the DELIVERABLE this spec gates)
- Surfaces read, never written: `.aai/system/MODEL_ROUTING.yaml`, `.aai/scripts/orchestration-dispatch.mjs`, `.aai/system/PRICING.yaml`, `docs/ai/METRICS.jsonl`, `docs/ai/EVENTS.jsonl`
- Surface added: `docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs` (a one-off measurement script, deliberately outside `.aai/`)
- Technology contract: `docs/TECHNOLOGY.md` (Node stdlib only, zero dependencies)
- Prior art in this repo: `docs/specs/SPEC-0018-spec-model-tiering-with-teeth.md`, `docs/specs/SPEC-0029-spec-hook-enforced-gates.md`, `docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md`

Registry items closed by this scope: none. `node .aai/scripts/follow-ups.mjs list`
at the base commit returns 141 open items and NONE of them names model routing, a
cheap-tier offload, a pre-tool block, or harness-scoped model resolution. One open
item shares a subject with this spike and is deliberately NOT closed:
`fu-usage-marker-omission-unfixable` (P2) — a run appended without a usage marker
cannot be corrected. That is precisely the data hole this spike measures (227 of 611
recorded runs carry no marker), but closing it requires changing `state.mjs
append-run`, which Spec-AC-08 forbids. The instrumentation proposal this spike owes
under Spec-AC-03 is the input a later CHANGE would use to close it; saying so here is
the "closes it or says why not" obligation discharged.

## The measurement this spec rests on

Taken first-hand at the base commit `8d967f47`, under bash with `/usr/bin/grep`,
over `docs/ai/METRICS.jsonl` (167 lines, 132 work-item records):

```
agent_runs                            611
  carrying usage_total_tokens=N        384   (63%)
  carrying no usage marker at all      227   (37%)
summed tokens over the 384             59,685,340
distinct model_id values                10   incl. claude-opus-4-8[1m] and 26x "unknown"
distinct role strings                   13   of which 7 are one-off free-text variants
tokens_in / tokens_out / cost_usd     null on every one of the 611
```

Three things this measurement establishes that the intake did not:

1. **The role axis needs normalizing too, not just the model axis.** The intake
   named the `model_id` hazard (`unknown`, the `[1m]` suffix). It did not name the
   role hazard: only 6 of the 13 role strings are canonical (`Planning` 110,
   `Implementation` 47, `Validation` 144, `Code Review` 140, `Remediation` 79,
   `TDD Implementation` 84 — 604 runs). The other 7 are singletons written by hand,
   such as `Remediation (E1 over-kill)` and `Code Review (re-review)`. Grouping "by
   role" without a normalization map silently produces 13 buckets, 7 of them n=1.
2. **Cross-vendor runs are already recorded, not hypothetical.** `deepseek-v4-flash`
   (5 runs), `gpt-5.6-sol` (3) and `gpt-5.5` (1) appear in the ledger today. The
   harness-universality question is therefore about a routing contract that has
   already been violated in practice, not about a future that might arrive.
3. **The denominator is 611, not 384.** Any share expressed over the 384
   marker-bearing runs is a share of 63% of the population. Stating a percentage
   without saying which denominator it uses would overstate coverage by a third.

Enforcement surface, measured the same way: `.claude/` exists and contains only
`skills/`. There is no `.claude/settings.json` in this repository, so there is no
`PreToolUse` hook surface today — the thing the spike is assessing would have to be
created, not configured.

## Design decisions

- **D1 — the intake document IS the deliverable; no second findings document is
  created.** The intake says so in its own Success Criteria, and a spike that emits a
  parallel report leaves two documents to keep in sync and a reader with no way to
  know which one is current. Every AC below writes into
  `docs/specs/RES-0002-mechanical-context-offload-to-cheap-tier.md`.

- **D2 — the measurement script is committed, and it lives outside `.aai/`.** Every
  number in the Findings section must be re-derivable by one named command or it is
  an assertion. The script goes to
  `docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs`, next to the
  analysis it serves. Outside `.aai/` on purpose: it is a one-off, it is not vendored
  downstream by `aai-sync`, it incurs no `.aai/system/PROFILES.yaml` classification
  obligation, and `docs-audit` scans only `.md` under `docs/` so it adds no
  doc-lifecycle obligation either. It takes an optional `--path` so it can be run
  against a ledger snapshot from a named commit — without that, the numbers in the
  document become unreproducible the moment this very ride appends its own runs.

- **D3 — both grouping axes are normalized, and the unattributable remainder is
  printed, never dropped.** `model_id` normalization strips the harness suffix
  (`claude-opus-4-8[1m]` folds into `claude-opus-4-8`) and keeps `unknown` as its own
  visible bucket. Role normalization folds a free-text variant onto its canonical
  prefix and keeps a count of what it folded. Both axes print their remainder line.
  A grouping that silently drops rows is the failure mode this decision exists to
  prevent.

- **D4 — the leading hypothesis is adjudicated, never implemented.** The intake's
  `### Leading hypothesis — harness scoping by suffix key` is a candidate to falsify.
  Spec-AC-07 demands a verdict token and an answer to each of the three falsifiers the
  intake itself named. No AC in this spec requires, permits or rewards an edit to
  `.aai/system/MODEL_ROUTING.yaml` or `.aai/scripts/orchestration-dispatch.mjs`, and
  Spec-AC-08 forbids it by diff. A spike that ships the design it was asked to test
  has tested nothing.

- **D5 — the enforcement verdict degrades explicitly or it is not a verdict.** The
  public `shunt` plugin source may be unreachable from the run environment. If it is,
  the document records the attempted URL, the date and the failure, and marks every
  hook-contract claim as article-derived rather than source-verified. Silently basing
  a verdict on the article's prose while the intake's own Method says to read the
  source is the drift the intake's "Source and its standing" section exists to stop
  (Constitution Article 4: degrade and report).

- **D6 — the do-not-delegate list is enumerated from code, not from memory.** Its
  population is the `TIERS` map in `.aai/scripts/orchestration-dispatch.mjs`, which
  holds 10 role keys at the base commit. Enumerating from a named artifact is what
  makes Spec-AC-05 checkable for completeness; a list argued from the prompt corpus
  could omit a role and nothing would notice.

- **D7 — recommendations name a follow-up TYPE, not a registry entry.** The intake
  says every action item leaves as a follow-up intake (RFC or CHANGE). The follow-up
  registry already carries 141 open items and its outflow problem is documented in
  `docs/analysis/registry-growth-diagnosis.md`; adding six more unclosed ids is a cost
  no AC should mandate. Filing is permitted, and anything presented as filed must
  carry an id the registry actually returns (SUBAGENT_CONTRACT follow-up honesty).

- **D8 — no headline number is produced, and the timebox is stated in the document.**
  The intake forbids reproducing a 90%-style figure and forbids repeating the
  circulating adoption numbers. The 2-day timebox is a constraint on the spike, not an
  acceptance criterion; the document records the actual elapsed effort so a reader can
  weigh the findings against what was spent on them.

## Constitution deviations

None.

## Implementation strategy
- Strategy: untested
- Rationale: recorded at intake by the user (`implementation_strategy.source: intake`)
  and kept unchanged — this spike is a docs-only analysis whose deliverable is a
  document plus a one-off measurement script over the ledgers, not production code.
  There is no shipped behavior to drive out: every acceptance criterion below is a
  text-presence fact about the deliverable, an exit code from the measurement script,
  or an arithmetic reconciliation over a ledger snapshot. Those commands ARE the
  verification and their exit codes are the evidence; no stored `docs/ai/tdd/`
  artifact is demanded, and none would prove anything about a document. Planning
  concurs with the recorded choice and records no objection.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: the scope is a document, a measurement script and the regenerated
  docs index — nothing a worktree protects. A worktree is nonetheless already in use
  and is worth keeping: the ride runs alongside other live sessions in this repository,
  and the measurement script must read a pinned ledger snapshot without a dirty
  shipping tree underneath it.
- User decision: worktree (already recorded in STATE by the user; Planning does not
  re-open it)
- Base ref: main (`8d967f47`)
- Worktree branch/path: `feat/mechanical-context-offload-to-cheap-tier` at
  `/Users/ales/Projects/aai-mechanical-context-offload`
- Inline review scope: not used (worktree selected)

Code review is REQUIRED for this scope. Ceremony level 2 requires it, and the scope
commits an executable file (`ledger-token-attribution.mjs`) whose arithmetic is the
sole warrant for every number in the Findings section. STATE currently records
`code_review.required: false`, which predates that decision; the correcting command is
returned with this spec.

## Companion obligations

Neither entry of the closed list applies: this scope adds no bytes to the prompt
corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`) and adds no new `.aai/**` file — the one
new executable lives under `docs/analysis/` by D2, precisely so that it does not.

## Acceptance Criteria Mapping

- Maps to: intake Success Criteria bullet 1
- Spec-AC-01: the `## Findings` and `## Recommendations` sections of
  `docs/specs/RES-0002-mechanical-context-offload-to-cheap-tier.md` carry written
  content, both `Not yet produced` placeholders are gone, and the document still
  passes a strict docs audit.
  - Verification: `/usr/bin/grep -c 'Not yet produced' docs/specs/RES-0002-mechanical-context-offload-to-cheap-tier.md`
    returns 0 (grep exit 1), and
    `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path docs/specs/RES-0002-mechanical-context-offload-to-cheap-tier.md`
    exits 0.

- Maps to: intake Success Criteria bullet 2
- Spec-AC-02: `docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs`
  runs against a named ledger snapshot and prints token totals grouped by normalized
  role and by normalized `model_id`, plus four reconciliation lines (total
  `agent_runs`, runs carrying a `usage_total_tokens=` marker, runs carrying none, and
  the summed token total). The role-row sum and the model-row sum each equal the
  marker-bearing total exactly. Every number quoted in the Findings baseline names the
  commit it was taken at, and re-running the script against that commit's snapshot
  reproduces it.
  - Verification: `git show 8d967f47:docs/ai/METRICS.jsonl > <scratch>/metrics-at-base.jsonl`
    then `node docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs --path <scratch>/metrics-at-base.jsonl`
    exits 0 and prints `agent_runs=611`, `with_usage_marker=384`, `without_usage_marker=227`,
    `tokens_total=59685340`; the two group sums are compared against `tokens_total` and
    are equal; each cell of the Findings baseline table is located verbatim in that
    stdout.

- Maps to: intake Success Criteria bullet 3
- Spec-AC-03: the Findings section states the mechanical share as a RANGE with its
  method and its denominator, or states that it cannot be attributed from current data
  and names the smallest instrumentation change that would make it attributable,
  sized S, M or L.
  - Verification: the Findings section contains exactly one line matching either
    `Estimated mechanical share: <low>% to <high>% of <denominator> runs` with the two
    numbers satisfying low less than or equal to high, or the literal
    `Estimated mechanical share: not attributable from current data`. When the
    not-attributable form is used, a following line matches
    `Instrumentation: <path> - size <S or M or L>` and names a real file that exists
    in the repository. Checked by `/usr/bin/grep -nE` for the two forms plus a
    `test -f` on the named path.

- Maps to: intake Success Criteria bullet 4
- Spec-AC-04: the Findings section carries an enforcement verdict subsection whose
  verdict line reads `Pre-tool block verdict:` followed by one of `available`,
  `available-with-cost` or `unavailable`, and which states the file-existence evidence
  for the enforcement surface, the maintenance surface adding it commits this project
  to, what it breaks, and the provenance of the hook contract it reasons from.
  - Verification: `ls .claude/settings.json` returns not-found at the base commit and
    that absence is quoted in the subsection; `/usr/bin/grep -nE 'Pre-tool block verdict: (available|available-with-cost|unavailable)'`
    over the intake document returns exactly one line; the same subsection is grepped
    for the literal tokens `no mid-session flip`, `prompt cache`, and one of
    `source-verified` or `article-derived`.

- Maps to: intake Success Criteria bullet 5
- Spec-AC-05: the Findings section carries a do-not-delegate table with one row per
  role key of the `TIERS` map in `.aai/scripts/orchestration-dispatch.mjs`, each row
  classified `delegable` or `never` and each carrying a one-sentence argument. No role
  key is missing and no row names a role the map does not hold.
  - Verification: `/usr/bin/grep -cE "^  '[^']+': '(premium|standard|mechanical)',$" .aai/scripts/orchestration-dispatch.mjs`
    returns 10 at the base commit; each of those 10 role names is located in the first
    column of the table, and the table's row count equals that number.

- Maps to: intake Success Criteria bullet 6
- Spec-AC-06: the `## Recommendations` section is a table in which every row carries a
  follow-up type of `RFC` or `CHANGE`, a size of `S`, `M` or `L`, an expected-saving
  statement, an effort statement, and an explicit ordering key; rows appear in
  non-increasing order of that key. Any recommendation presented as filed carries a
  registry id that the follow-up CLI returns.
  - Verification: every row's type token is in the set and every row's size token is in
    the set; the ordering-key column read top to bottom is non-increasing; for each id
    the row labels `filed:`, `node .aai/scripts/follow-ups.mjs list --json` contains
    that id (an id present only as `suggested:` is not checked and must not be
    presented as filed).

- Maps to: intake sub-question 4 and the intake Method section
- Spec-AC-07: the Findings section adjudicates the intake's harness-scoping hypothesis
  with a verdict line reading `Harness-scoping hypothesis:` followed by one of
  `upheld`, `falsified` or `undecided`, answers each of the three falsifiers the intake
  named, and records on evidence gathered in this spike why each of the two rejected
  alternatives loses or wins.
  - Verification: `/usr/bin/grep -nE 'Harness-scoping hypothesis: (upheld|falsified|undecided)'`
    over the intake document returns exactly one line; the subsection is grepped for
    three falsifier headings and for the literal tokens `nested per-harness section`
    and `capability probe`.

- Maps to: intake Scope, "Out of scope" — research only
- Spec-AC-08: the scope's diff changes no routing, dispatch, pricing or harness-config
  surface, adds no hook, and touches nothing outside `docs/`.
  - Verification: `git diff --name-only 8d967f47...HEAD` combined with
    `git status --porcelain` contains no `.aai/system/MODEL_ROUTING.yaml`, no
    `.aai/scripts/orchestration-dispatch.mjs`, no `.aai/system/PRICING.yaml` and no
    path under `.claude/`; and every changed path begins with `docs/`, checked by
    piping the same list through `/usr/bin/grep -vcE '^docs/'` which returns 0
    matches (grep exit 1).

## Acceptance Criteria Status

| Spec-AC    | Description                    | Status      | Evidence       | Review-By   | Notes                          |
|------------|--------------------------------|-------------|----------------|-------------|--------------------------------|
| Spec-AC-01 | The intake document's Findings and Recommendations sections carry written content, both placeholders are gone, and the document passes a strict docs audit | planned | — | — | Implementation ran the AC-01 verification commands this ride (2026-09-07) and both passed; Status stays planned and Evidence stays empty on purpose so this still-open spec (status implementing) does not read as probable-false-open under docs-audit --check --strict - Evidence citation is Validation's, per this spec's own Evidence contract ("Evidence path: the validation report under docs/ai/validation/") |
| Spec-AC-02 | WHEN the committed measurement script is run against a named ledger snapshot THEN it prints token totals grouped by normalized role and by normalized model id plus four reconciliation lines, and the group sums equal the marker-bearing total | planned | — | — | Implementation ran the AC-02 verification command this ride (2026-09-07): agent_runs=611, with_usage_marker=384, without_usage_marker=227, tokens_total=59685340, both group sums equal tokens_total; Status/Evidence deferred to Validation for the same false-open reason as AC-01 |
| Spec-AC-03 | The mechanical share is stated as a low-to-high range with its method and denominator, or stated as not attributable together with a named instrumentation change sized S, M or L | planned | — | — | Implementation wrote the mechanical-share line this ride (2026-09-07): "0% to 21% of 611 runs"; Status/Evidence deferred to Validation for the same false-open reason as AC-01 |
| Spec-AC-04 | The Findings carry one pre-tool-block verdict line from a three-value set, plus the surface evidence, the maintenance cost, what it breaks, and the provenance of the hook contract | planned | — | — | Implementation wrote the enforcement verdict this ride (2026-09-07): "available-with-cost", source-verified against the fetched shunt plugin source; Status/Evidence deferred to Validation for the same false-open reason as AC-01 |
| Spec-AC-05 | The do-not-delegate table carries one row per role key of the TIERS map in orchestration-dispatch.mjs, each classified delegable or never with an argument | planned | — | — | Implementation built the 10-row table this ride (2026-09-07), verified against the live TIERS map; Status/Evidence deferred to Validation for the same false-open reason as AC-01 |
| Spec-AC-06 | Every recommendation row carries a follow-up type, a size, an expected saving, an effort and an ordering key, rows are ordered non-increasing by that key, and any id presented as filed is returned by the follow-up CLI | planned | — | — | Implementation wrote the 5-row Recommendations table this ride (2026-09-07), ordering key 9,7,5,4,3, all ids suggested: (none filed); Status/Evidence deferred to Validation for the same false-open reason as AC-01 |
| Spec-AC-07 | The harness-scoping hypothesis receives one verdict line from a three-value set, an answer to each of the three named falsifiers, and an evidence-based ruling on both rejected alternatives | planned | — | — | Implementation adjudicated the hypothesis this ride (2026-09-07): "upheld", against code read directly from orchestration-dispatch.mjs; Status/Evidence deferred to Validation for the same false-open reason as AC-01. Addendum (Remediation, 2026-09-07): superseded - a later remediation on this ride softened the deliverable's verdict to "undecided" because only one of the three named falsifiers was genuinely tested against live code; the "upheld" statement above is left as originally written and this sentence records the supersession rather than rewriting it. |
| Spec-AC-08 | The scope's diff touches no routing, dispatch, pricing or harness-config surface, adds no hook, and contains no path outside docs | planned | — | — | Implementation ran the AC-08 diff check this ride (2026-09-07): 0 matches outside docs/; Status/Evidence deferred to Validation for the same false-open reason as AC-01 |

## Implementation plan

Components affected:
- `docs/specs/RES-0002-mechanical-context-offload-to-cheap-tier.md` — the Findings and
  Recommendations sections are written; every other section is left as frozen intake.
- `docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs` — new; Node
  stdlib only, no dependencies, reads `docs/ai/METRICS.jsonl` or a `--path` override,
  writes nothing.
- `docs/INDEX.md` — regenerated by `node .aai/scripts/generate-docs-index.mjs`, never
  hand-edited.

Data flow: `METRICS.jsonl` snapshot at a pinned commit -> the script's normalizers ->
grouped totals plus reconciliation lines on stdout -> quoted into the Findings baseline
table -> re-derived by validation from the same snapshot.

Order of work: take the measurement first, then read the routing contract and the
enforcement surface against it, then the external source, then write Findings, then
write Recommendations. Recommendations written before the measurement would be the
intake's hypothesis wearing a finding's clothes.

Edge cases:
- A `note` field carrying more than one `usage_total_tokens=` occurrence: the script
  must define which it takes and print how many records had more than one.
- A record with an `agent_runs` array that is absent or empty: counted in the
  work-item total, contributing zero runs, and reported rather than skipped.
- The `unknown` model bucket (26 runs) and the no-marker bucket (227 runs) are printed
  as their own rows; a report that omits them reads as fuller coverage than exists.
- The external plugin source being unreachable — handled by D5, not by silence.
- `METRICS.jsonl` growing during the ride: handled by pinning `--path` to a snapshot.

## Test Plan

Strategy is `untested`: NO test file is created. This scope ships a document and a
one-off analysis script; a committed test suite for a one-off script is production
tooling the scope was explicitly told not to build. Each row below is a command run
against the shipped tree; its exit code and its stdout are the evidence.

Two of these rows cross a real seam rather than assert a document's own words about
itself. TEST-002 crosses the seam between the script's arithmetic and the numbers the
document quotes, by re-deriving from the pinned ledger snapshot rather than trusting
the table. TEST-005 crosses the seam between the do-not-delegate list and the live
`TIERS` map in `orchestration-dispatch.mjs`, so a role added to the map later makes the
list demonstrably incomplete instead of quietly stale.

| Test ID  | Spec-AC    | Type       | File path (expected)       | Description                  | Status  |
|----------|------------|------------|----------------------------|------------------------------|---------|
| TEST-001 | Spec-AC-01 | check | no new file - command over docs/specs/RES-0002-mechanical-context-offload-to-cheap-tier.md | grep asserts zero remaining Not-yet-produced placeholders and docs-audit --check --strict --no-event on the document exits 0 | pending |
| TEST-002 | Spec-AC-02 | check | no new file - command over docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs and a pinned METRICS snapshot | the script runs against the 8d967f47 snapshot and prints agent_runs 611, with-marker 384, without-marker 227 and tokens_total 59685340; the role-row sum and the model-row sum each equal tokens_total; every cell of the Findings baseline table is found verbatim in that stdout | pending |
| TEST-003 | Spec-AC-03 | check | no new file - command over the Findings section | exactly one mechanical-share line matches one of the two permitted forms, a range satisfies low not greater than high, and the not-attributable form is accompanied by an instrumentation line naming a size token and a path that test -f confirms exists | pending |
| TEST-004 | Spec-AC-04 | check | no new file - command over the Findings section and over .claude | the verdict line matches exactly one of the three permitted values, the absence of .claude/settings.json is quoted as the surface evidence, and the subsection contains the no-mid-session-flip token, the prompt-cache token and a source-verified or article-derived provenance token | pending |
| TEST-005 | Spec-AC-05 | check | no new file - command over .aai/scripts/orchestration-dispatch.mjs and the Findings section | the TIERS role-key count read from the dispatch source equals the do-not-delegate table's row count, and every one of those role names appears in the table's first column | pending |
| TEST-006 | Spec-AC-06 | check | no new file - command over the Recommendations section and the follow-up registry | every row carries a type token from RFC or CHANGE and a size token from S, M or L, the ordering-key column is non-increasing top to bottom, and every id labelled filed is returned by follow-ups.mjs list --json | pending |
| TEST-007 | Spec-AC-07 | check | no new file - command over the Findings section | exactly one harness-scoping verdict line matches the three-value set, three falsifier headings are present, and both rejected-alternative tokens are present | pending |
| TEST-008 | Spec-AC-08 | check | no new file - command over the scope diff | the changed-path list from git diff --name-only against the base plus git status --porcelain contains none of the four forbidden surfaces and every entry begins with docs/ | pending |

## Verification

Commands, in the order validation should run them:

1. `node docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs --path <scratch>/metrics-at-base.jsonl`
2. `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path docs/specs/RES-0002-mechanical-context-offload-to-cheap-tier.md`
3. `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path docs/specs/SPEC-0173-spec-mechanical-context-offload-to-cheap-tier.md`
4. `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0173-spec-mechanical-context-offload-to-cheap-tier.md`
5. `node .aai/scripts/generate-docs-index.mjs` followed by `git diff --stat docs/INDEX.md`
6. the eight TEST rows above, each read for its exit code and its stdout
7. `git diff --name-only 8d967f47...HEAD` and `git status --porcelain` for Spec-AC-08

Evidence artifacts: the measurement script's stdout captured against the pinned
snapshot; the docs-audit and spec-lint exit codes; the changed-path list; and the
commit SHA of the delivered document.

PASS criteria: all eight TEST rows green AND all eight Spec-AC rows in a terminal
status with non-empty Evidence.

## Evidence contract

- ref_id: `mechanical-context-offload-to-cheap-tier`
- Spec-AC and TEST links: as tabulated above, one TEST row per Spec-AC, eight of each
- Command or review scope: the seven verification commands above; review scope is
  `docs/specs/RES-0002-mechanical-context-offload-to-cheap-tier.md`,
  `docs/specs/SPEC-0173-spec-mechanical-context-offload-to-cheap-tier.md`,
  `docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs` and
  `docs/INDEX.md`
- Exit code or verdict: recorded per command
- Evidence path: the validation report under `docs/ai/validation/`
- Commit SHA: the delivering commit on `feat/mechanical-context-offload-to-cheap-tier`

Because the recorded strategy is `untested`, this spec demands the strategy rationale
plus the scoped diff and the exit codes above, and no stored `docs/ai/tdd/` artifact
is required for any row.

## Residual risks

Written down because no test in this plan crosses them:

- **Whether the mechanical-share estimate is TRUE cannot be tested.** The ledger holds
  no per-tool-call attribution, so any share is a modelled estimate over a 63%-covered
  population of 611 runs on one project. Spec-AC-03 therefore tests the SHAPE of the
  claim — a range, a method, a denominator — never its correctness. A reader who takes
  the range as a measurement will be wrong, which is why the denominator is required
  in the same line.
- **The conclusions are directional for this project only.** 132 work items on one
  self-hosting repository is not a sample from which a general rule follows, and the
  document must say so where it recommends.
- **The `shunt` hook contract may reach the document second-hand.** D5 makes that
  visible rather than preventing it; a verdict marked `article-derived` is weaker
  evidence than one marked `source-verified`, and Spec-AC-04 forces the distinction to
  be stated rather than assumed.
- **Recommendations sized S, M or L are estimates by the same agent that wrote the
  findings.** Nothing here independently checks a size. The ordering key is required to
  be printed so a reviewer can disagree with the arithmetic rather than with a feeling.
