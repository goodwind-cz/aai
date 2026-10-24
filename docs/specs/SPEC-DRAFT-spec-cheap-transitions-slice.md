---
id: spec-cheap-transitions-slice
type: spec
number: null
status: implementing
frozen_sha256: 62f70e1b3d5f3b4e472f10ebf552aba6c8e08aeaee3fbd983e2c3231168acd14
mutation_gate: v1
ceremony_level: 3
links:
  requirement: cheap-transitions-slice
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Delta re-check: a routine re-review or re-validation gets a slim payload

SPEC-FROZEN: true

## Links

- Requirement: [Cheap transitions slice](../issues/CHANGE-DRAFT-cheap-transitions-slice.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  Proposal section 4 (reduce agent context; extend the existing L0/L1 paths;
  protected state, security and public contracts keep independent checks),
  the phase 4 row, and owner decisions 1.1 and 1.5.
- Prior art for canon composition:
  [SPEC-0243](SPEC-0243-spec-slim-standing-role-context.md) (standing lessons
  only in every role payload, #491). Pattern for the ledger pin:
  [SPEC-0249](SPEC-0249-spec-node-first-third-slice.md) TEST-2626.

## Implementation strategy

- Strategy: hybrid
- Rationale: the eligibility library, the canon delta build, the dispatch
  field and the two verdict events are new behavior with refusal paths that
  must be observed RED before they exist, so every row that gates them is TDD
  with a stored RED and a mutation record. The prompt, protocol, workflow,
  profile, suite-map, diet-ledger and RFC edits are mechanical (loop mode) but
  each one is pinned by a mutation-gated inspection row.

## Isolation and review

- Worktree recommendation: required (ceremony level 3).
- Worktree rationale: the scope edits `.aai/workflow/WORKFLOW.md`, a
  `protected_paths_l3` surface, and changes how every downstream install
  dispatches re-check rounds; the ride already runs in its own linked worktree.
- User decision: worktree (recorded before Planning).
- Base ref: ba552b89 (main); intake commit d4738f91.
- Worktree branch/path: change/cheap-transitions-slice at /private/tmp/aai-cheap-transitions
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/lib/recheck.mjs .aai/scripts/canon.mjs .aai/system/CANON.yaml
  .aai/scripts/orchestration-dispatch.mjs .aai/scripts/append-event.mjs
  .aai/RECHECK_DELTA.prompt.md .aai/ORCHESTRATION.prompt.md
  .aai/ORCHESTRATION_PARALLEL.prompt.md .aai/SKILL_CODE_REVIEW.prompt.md
  .aai/VALIDATION.prompt.md .aai/SUBAGENT_PROTOCOL.md
  .aai/workflow/WORKFLOW.md .aai/system/PROFILES.yaml
  tests/skills/test-aai-recheck.sh tests/skills/lib/recheck.test.mjs
  tests/skills/lib/recheck-measure.mjs tests/skills/suite-map.yaml
  tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-prompt-diet.sh
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md CHANGELOG.md
  docs/ai/decisions.jsonl docs/issues/CHANGE-DRAFT-cheap-transitions-slice.md
  docs/specs/SPEC-DRAFT-spec-cheap-transitions-slice.md
  (tests/skills/suite-weights.tsv only if the selector asks for a row; an
  existing suite is edited only when one of its pins names a changed literal,
  and each such edit is disclosed in the hand-off).
- Code review required: true, on the most capable tier (L3), with the
  operator checkpoint before merge.

## Measured baseline (intake AC-001)

Source: the last `docs/ai/METRICS.jsonl` row of each ride, `agent_runs` in
order. A re-check round is a Code Review or Validation run that is not the
first run of that role in the ride. Tokens are `tokens_total` as the harness
reported it; a null counts as 0, so the columns are known tokens. Durations
are the sum of `duration_seconds`.

| Ride | PR | Runs | CR runs | V runs | Rem runs | Ride tokens | Ride s | Re-check rounds | Re-check tokens | Re-check s |
|---|---|---|---|---|---|---|---|---|---|---|
| slim-standing-role-context | 491 | 7 | 1 | 3 | 1 | 1057954 | 6610 | 2 | 209638 | 2953 |
| ride-state-handoff-to-worktree | 492 | 6 | 1 | 2 | 1 | 1204708 | 8036 | 1 | 129332 | 831 |
| docs-audit-suite-speed | 493 | 19 | 5 | 6 | 6 | 2042010 | 14119 | 9 | 960092 | 5148 |
| ci-node-24-baseline | 494 | 5 | 1 | 2 | 0 | 0 | 2906 | 1 | 0 | 217 |
| node-first-sync-hook-slice | 495 | 9 | 2 | 3 | 2 | 647341 | 22518 | 3 | 353734 | 16611 |
| node-first-second-slice | 496 | 7 | 2 | 2 | 1 | 1182015 | 11100 | 2 | 301862 | 4778 |
| node-first-third-slice | 497 | 15 | 5 | 4 | 4 | 2256013 | 16647 | 7 | 870643 | 8791 |

Across the seven rides: 68 runs, 8390041 known tokens, 81936 s. Re-check
rounds: 25, holding 2825301 tokens (33.7%) and 39329 s (48.0%).

What the late rounds re-checked. For each re-check round, Planning diffed the
ride's PR branch commits (`gh pr view <N> --json commits`, then
`git diff --name-only <head when the previous run of that role ended> <head
when this run started>`) and classified the paths with the D2 allowlist
below. The method needs the PR branch commits, which a CI clone does not
fetch, so these two columns are a Planning measurement, not a pinned test:

| Ride | Re-check rounds | Non-production deltas | Their tokens | Verdicts on those rounds |
|---|---|---|---|---|
| slim-standing-role-context | 2 | 1 (V) | 138253 | V pass |
| ride-state-handoff-to-worktree | 1 | 0 | 0 | none |
| docs-audit-suite-speed | 9 | 7 (5 V, 2 CR) | 742812 | 5 V pass; CR r2 and r3 FAIL with BLOCKING findings in test-only deltas |
| ci-node-24-baseline | 1 | 1 (V) | unknown | V pass |
| node-first-sync-hook-slice | 3 | 0 | 0 | none |
| node-first-second-slice | 2 | 2 (V, CR) | 301862 | both pass |
| node-first-third-slice | 7 | 4 (2 V, 2 CR) | 480758 | all pass; CR r4 still found a P2 surviving mutant in a test-only delta |

Totals: 15 of 25 re-check rounds judged a delta that touched no production
path (tests, spec, RFC and ledger lines only), holding 1663685 tokens (19.8%
of all known tokens). By role: 10 Validation rounds, 1199429 tokens, 10 of 10
pass; 5 Code Review rounds, 464256 tokens, 2 FAIL, and one pass whose report
carried a P2 that was remediated in tree. In node-first-third-slice the round 1
report names a security drift (the expert prompt fetcher has two security
filters); under D2 its reviewer would mark the ride security-relevant, which
takes its 4 rounds (480758 tokens) out of delta mode, leaving 11 rounds and
1182927 tokens (14.1%).

Size of a re-check round. Median tokens of the non-production rounds: Code
Review 91463, Validation 124934. Median of the first rounds: Code Review
153021, Validation 212297. Late rounds are already about 40% smaller than first
rounds, because the orchestrator narrowed them in dispatch prose (the reports
are titled "r3 (delta)", "r4 (delta)"), but each still starts a fresh context
of the full role size.

Prompt bytes today. `node .aai/scripts/canon.mjs build --role <R> --ref x |
wc -c` at the intake commit: Planning 32273, Implementation 31006, TDD
Implementation 38862, Validation 45467, Remediation 25891, Code Review 32720.
The sections: `.aai/SUBAGENT_CONTRACT.md` 7232, `docs/knowledge/LEARNED.md`
13344, `.aai/VALIDATION.prompt.md` 24568, `.aai/SKILL_CODE_REVIEW.prompt.md`
11821.

## Mechanism choice

Chosen: a delta re-check mode (intake candidate 1), with a minimal structured
marker from candidate 3. The numbers against the alternatives:

- Delta re-check (chosen). It applies to the 15 rounds above (11 with the
  security marker applied) and removes none of them: every round keeps an
  independent model in a fresh context. Per dispatch it removes the full role
  prompt and `LEARNED.md` from the payload, an expected cut of at least 60% of
  the prompt bytes (Validation 45467 to about 12500, Code Review 32720 to about
  12500). In tokens the payload alone is small next to a round: about 8000
  fewer input tokens for a Validation round (about 6% of the 124934 median),
  about 5000 for a Code Review round. The rest of the expected gain comes from
  the narrowed walk the delta prompt prescribes; that part is not measurable
  until a ride uses the mode. This slice does not claim the RFC's 30% token
  target.
- Deterministic finding triage (a text-only or test-only fix goes to the
  remediator and an automated check instead of a new review round). Upper
  bound: the same 15 rounds removed outright, 1663685 tokens. It would have
  shipped real defects: 2 of the 5 non-production Code Review rounds returned
  FAIL with BLOCKING findings in test-only deltas (docs-audit-suite-speed r2
  and r3), and node-first-third-slice r4 found a P2 surviving mutant behind a
  measured bypass in a test and spec delta. Rejected, because it weakens an
  independent check, which the intake puts out of scope.
- Structured verdict and finding format read by dispatch. Rules 10 to 13
  already decide transitions in code from the STATE verdict fields that
  `set-validation` and `set-code-review` write. What stays prose is the
  orchestrator's reading of reports, and the orchestrator's own context is not
  in METRICS (`agent_runs` records subagents only), so the gain is 0 in the
  current telemetry. Only the one machine-readable line this mechanism needs
  (`security_relevant:`, D5) is adopted.
- Larger, but not built here (owner decision candidate). The Validation half of
  the triage idea is the largest single saving in the data: all 10
  non-production Validation re-checks passed. Replacing them with a scripted
  re-run while Code Review stays independent would save about 1199429 tokens
  (14.3%), but it turns an independent model check into an automated one.
  Recommendation: keep it out until a ride has measured delta mode;
  `suggested: fu-scripted-revalidation-nonprod-delta` for the owner to decide
  on that evidence.

The evidence is not evenly split and the chosen option weakens no check, so no
owner decision blocks this spec.

## Scope and design

### D1. When the mode applies and when it must not

The library `.aai/scripts/lib/recheck.mjs` (new, Node stdlib only) exports
`recheckMode({ root, ref, role, env })` and the constants named below. It
returns `{ mode, reasons, base, head, spec_path, changed_paths, prior_reports }`, where
`mode` is `delta` only when every condition holds, and otherwise `full` with
every failing condition named in `reasons` (closed vocabulary, collected, not
first-match):

| Condition for delta | Reason token when it fails |
|---|---|
| role is Validation or Code Review (`RECHECK_ROLES`; looked up as an own key, so `__proto__` and kin are unknown roles) | `role_not_rechecked` |
| `AAI_RECHECK_MODE`, trimmed and lower-cased, is unset, empty or `delta` (`FORCE_ENV`; the rollback switch: `full` and every other value force full) | `forced_full` |
| a `check_verdict` event exists for this ref and role (D4) | `first_round` |
| its `head` is an ancestor of HEAD | `base_not_ancestor` |
| the delta is non-empty | `no_delta` |
| every changed path matches `NON_PRODUCTION_PATTERNS` (D2) | `production_path:<path>` per path |
| no changed path matches `protected_paths_l3` read live (D3) | `protected_path:<path>` per path, or `protected_config_unreadable` |
| the focus spec's `ceremony_level` parses as 0, 1 or 2 in BOTH the live file and the blob at the base, and neither says 3 (the delta may edit the spec, so the stricter of the two decides) | `ceremony_l3` when either reads 3 (`PROTECTED_LEVEL`), `ceremony_unknown` when either is absent, unparseable or unreadable, or the spec is missing at either end |
| every prior report of the ref carries exactly one `security_relevant: false` line and none says true (D5), read from the blob at the base when the report existed there, and none of those was changed inside the delta | `security_relevant:<path>`, `security_marker_absent:<path>`, `prior_report_unreadable:<path>`, `prior_report_changed:<path>`, or `security_marker_absent:<role>` when the re-checked role has no prior report |
| every git call succeeds | `git_error` |

The delta is the union of `git diff --name-only --no-renames <base>` (committed and
uncommitted tracked changes against the base; `--no-renames` so that both ends of a
rename and every deletion are listed) and
`git ls-files --others --exclude-standard` (untracked, not ignored), sorted and
de-duplicated. The library reads STATE (focus ref, spec path,
`code_review.report_paths`, `last_validation.evidence_paths`) and
`docs/ai/EVENTS.jsonl` read-only and never writes either. Any unexpected
condition resolves to `full`; the mode is opt-in by proof, never by default.

### D2. Non-production paths

`NON_PRODUCTION_PATTERNS` is an explicit allowlist: test code under `tests/`
(`tests/skills/test-aai-*.sh`, `tests/skills/*.Tests.ps1` and
`tests/skills/lib/*.test.mjs`; every other file under `tests/` is production,
because production scripts read gate inputs there: `suite-map.yaml` and
`suite-weights.tsv` choose which suites CI runs, the `*-baseline.tsv`,
`*-ratchet.sh` and `prompt-diet-ledger.sh` files set ratchets, and
`merge-policy.mjs` lists `suite-map.yaml` among its `GUARD_PATHS`; TEST-2730
derives the files the scripts name and holds the allowlist to them),
`docs/specs/**`, `docs/issues/**`, `docs/rfc/**`, `docs/analysis/**`,
`docs/product/**`, `docs/ai/reviews/**`, `docs/ai/tdd/**`,
`docs/ai/reports/**`, `CHANGELOG.md`, and every member of
`TREE_HASH_EXCLUDE_PATHS` (the append-only ledgers and the generated pages).
Everything else is production, including `.aai/**`, `.github/**`,
`.claude/**`, `docs/knowledge/**` (LEARNED is part of every payload),
`docs/ai/*.yaml`, `docs/TECHNOLOGY.md`, `docs/CONSTITUTION.md` and every root
file except `CHANGELOG.md`. `orchestration-dispatch.mjs` exports
`TREE_HASH_EXCLUDE_PATHS` (additive) so a test can prove the two lists do not
drift.

### D3. Protected paths

`protected_paths_l3` is read live from `docs/ai/docs-audit.yaml` through the
existing docs-audit config parser, never copied. Every default entry is already
production under D2; the arm exists for a project that protects a path under
`tests/` or `docs/`. A config that cannot be read refuses delta.

### D4. Verdict stamps (two new EVENTS types)

`append-event.mjs` accepts two new types, both requiring `--role`
(`validation` or `code_review`) and `--head` (40 lowercase hex,
`HEAD_SHA_RE`):

- `check_dispatched` with `--seen <marker>`: written by
  `orchestration-dispatch.mjs` on a `--confirm` tick that dispatches
  Validation or Code Review (rules 11, 11s, 13), full or delta alike. `head`
  is `git rev-parse HEAD` at that tick. A repeated tick whose head and seen
  marker equal the latest `check_dispatched` of that ref and role, with no
  `check_verdict` since, appends nothing; a repeated tick at a newer head appends
  a further `check_dispatched`. `seen` records the verdict identity at
  dispatch time: `run_at:<last_validation.run_at_utc>` for Validation,
  `reports:<count of code_review.report_paths>` for Code Review.
- `check_verdict` with `--status <pass or fail>` and an optional
  `--security-relevant <true or false>` (refused for any other value): written by the first
  `--confirm` tick that sees, for the focus ref, a verdict of that role whose
  identity differs from the marker of the EARLIEST unjudged `check_dispatched`
  (a newer `run_at_utc`, compared as instants, or more review reports), where
  the unjudged dispatches of a role are its `check_dispatched` events after the
  last `check_verdict` of that role. `head` is copied from that earliest
  unjudged `check_dispatched`: the base is what the checker was actually handed,
  never the head of a re-tick that landed while the check was in flight (a
  production commit made in between would otherwise be absorbed into the base
  and never re-checked). Fail closed: when another unjudged head does not
  descend from the earliest one, or git cannot say, the base is ambiguous and
  the stamp carries `AMBIGUOUS_HEAD` (forty zeros, never a commit), so the next
  round is `base_not_ancestor` and runs full.
  The stamp also records the security marker of the verdict (D5): `true` when
  any report STATE names for that role at that moment says `true`, `false`
  only when there is at least one report and every one carries exactly one
  `security_relevant: false` line, and no field at all otherwise.

No `check_dispatched`, no stamp; no stamp, `first_round`. A crashed check
leaves no new verdict identity, so it is never stamped by the check itself.
Known limit (filed as `fu-recheck-verdict-not-bound-to-check`, P2): the stamp
cannot tell the dispatched checker's STATE write from a later `set-validation`
of another source, because STATE carries no head or tree for a verdict; the
verdict identity is only "newer than the dispatched marker". Without `--confirm`
nothing is written. Both writes go through `append-event.mjs` (one EVENTS
writer) and are swallowed on failure, like `recordValidationVerdict`.

### D5. The security marker

The full Code Review and Validation prompts each gain one instruction: the
report carries exactly one line `security_relevant: true` or
`security_relevant: false` at column 0; it is `true` when any finding of the
round, open or fixed, touches a security guard, a secret, authentication,
authorization, input sanitization or a sandbox boundary, and once any report
of the ref says `true`, every later report of the ref says `true`. The
classification is made by the independent checker, not by code; code only
reads it, and a missing or ambiguous line refuses delta.

The judged round's own report is written after the base, and a Validation
report is gitignored, so reading it live at the next round would let a later
edit flip it unseen. The marker is therefore recorded in the `check_verdict`
stamp when the verdict is first seen (D4), and eligibility trusts the stamp:
the latest stamp of the dispatched role SHALL say `false` (a stamp without the
field counts as absent and gives `security_marker_absent:stamp:<role>`), and
any stamp of either role for the ref that says `true` gives
`security_relevant:stamp:<role>`, for every later round (sticky). A report that
existed at the base is still read from the base blob and refuses when the delta
touched it; a live read that says `true` still refuses, but no live read can
lower a stamped `true`.

### D6. The dispatch field

For a dispatch of Validation or Code Review, `orchestration-dispatch.mjs` adds
`recheck: { mode, reasons, base, head, spec_path, changed_paths, prior_reports, fallback }`
from the same `recheckMode` call; every other verdict carries `recheck: null`
(additive; the D3 key set test still holds). On `mode: delta` the
`system_prompt` is `.aai/RECHECK_DELTA.prompt.md` (`RECHECK_PROMPT` in the
library) and `prompt_hash` is computed over it by the existing function, and
`recheck.fallback` is `{ system_prompt, prompt_hash }` of the FULL role payload
(the stock role prompt and its hash); on `mode: full` `fallback` is `null`.
The fallback is what the orchestrator records when canon refuses the delta
build after the dispatch: only a delta payload that was actually sent is
recorded with the delta identity or the `recheck=delta` note.
`role`, `rule`, `suggested_tier`, `suggested_model`, `suggested_effort`,
`validator_independence` and `lane` are identical to what the same snapshot
yields with `AAI_RECHECK_MODE=full`. No rule predicate, rule order or verdict
changes.

### D7. The canon delta build

`canon.mjs build --role <R> --ref <r> --recheck delta` calls `recheckMode`
with the live root. When it returns `full`, canon prints
`canon-recheck-refused: <reasons joined by space>` on stderr, nothing on
stdout, and exits 11. When it returns `delta`, canon assembles the sections
declared under a new top-level `delta_sections:` key in `.aai/system/CANON.yaml`,
in order `contract` (file `.aai/SUBAGENT_CONTRACT.md`), `recheck` (file
`.aai/RECHECK_DELTA.prompt.md`) and `scope` (new type `recheck_scope`). The
`recheck_scope` text names the role, the ref, the spec path (`spec:`), the base,
the head, every changed path and every prior report path, one per line. Every existing build check
applies unchanged: the five standing hazards, the duplicate-rule scan and the
byte ceiling. `--recheck full` and no flag build exactly what the base commit's `canon.mjs` builds from the same inputs (the full Code Review and Validation payloads still grow by the D5 marker line).
`--print-hash --recheck delta` prints the digest of the delta stack (the
`recheck` section file in the role position, then the contract and LEARNED, the
same order and framing `prompt-hash.mjs` uses) without computing eligibility,
so it equals the dispatch `prompt_hash` of a delta dispatch.

### D8. The delta prompt

`.aai/RECHECK_DELTA.prompt.md` (new, at most 4096 bytes, no withdrawn-claim
phrase that `canon.mjs claims` scans for) tells the re-checker: you are the
same independent role as the full check, in a fresh context; read the prior
reports and the diff `git diff <base>` plus the untracked paths; for each prior
finding say fixed or still open with evidence; review the delta for new
defects, including weakened assertions, deleted cases and mutation cells that
no longer bite; re-run the spec's Test Plan commands the delta touches and the
ones the prior findings name. A Validation re-check still writes the single
`aai-outcome-v1` block that `validation-outcome-check.mjs` checks, with every
outcome re-observed in this round. The prompt also carries the output
contracts a checker needs, as short statements that name the full prompt's
sections instead of copying them: the report path (`docs/ai/reviews/review-<timestamp>.md`,
never `docs/validation/`, and the Validation report path), the H6 disposition of
every NON-BLOCKING finding, the `set-code-review` and `set-validation` shapes,
the `aai-outcome-v1` schema pointer, `validation-outcome-check.mjs` run before
any PASS, and `state_update_commands` for a dispatched role. Every report
carries the D5 marker. If the
delta cannot be judged without the full context, return status BLOCKED with
the literal reason `needs_full_recheck`; the orchestrator then dispatches the
full role with `AAI_RECHECK_MODE=full`.

### D9. Wiring and documentation

- `.aai/ORCHESTRATION.prompt.md` step 2: build the prefix with
  `canon.mjs build --role <R> --ref <ref_id>` where `<ref_id>` is the dispatch
  JSON's `ref_id` field, never `HEAD` (canon keys the stamps and STATE on the
  ref, so `HEAD` always refuses); when the JSON has `recheck.mode` delta add
  `--recheck delta`; if canon exits 11, build without it and take
  `system_prompt` and `prompt_hash` from `recheck.fallback`, and record no
  `recheck=delta` note. The file stays at or under 45 lines. TEST-2725 runs the
  documented command with the dispatch `ref_id`.
- `.aai/ORCHESTRATION_PARALLEL.prompt.md`: the Context bullet points at
  `canon.mjs build` (with the same `--recheck delta` rule) instead of "a copy
  of .aai/SUBAGENT_CONTRACT.md" (closes `fu-orchestration-parallel-still-pastes`).
- `.aai/SUBAGENT_PROTOCOL.md`: the INPUT row names `canon.mjs build` as the
  payload builder (closes `fu-subagent-protocol-input-row-stale`), and a new
  "Delta re-check" subsection states D1, the `needs_full_recheck` escalation,
  `AAI_RECHECK_MODE=full` as the switch, and that the `append-run` of a round
  whose delta payload was actually sent carries the note
  `recheck=delta base=<sha>` so its tokens can be compared later (a round that
  fell back to the full payload carries neither the note nor the delta
  `prompt_hash`).
- `.aai/workflow/WORKFLOW.md`, below the ceremony table: a re-check round
  (rules 11, 11s, 13 after a judged round) may run in delta mode at L0 to L2
  per `.aai/SUBAGENT_PROTOCOL.md`; never at L3, never for a production,
  protected or security-relevant delta; the independent model and the
  validator-differs rule are unchanged.
- `.aai/system/PROFILES.yaml`: `.aai/scripts/lib/recheck.mjs` and
  `.aai/RECHECK_DELTA.prompt.md` in core (canon and dispatch are core).
- `tests/skills/suite-map.yaml`: a row `aai-recheck` for the new library,
  prompt, measure script and the canon, dispatch, append-event and CANON
  sources.
- Prompt diet: one `JUSTIFIED_ADDITIONS` entry naming
  `cheap-transitions-slice`, credited at the measured growth of the prompt
  corpus, and the TEST-012 checkpoint moved to match.
- `CHANGELOG.md`: one `## [unreleased] — <title>` entry; downstream installs
  dispatch re-check rounds differently.

### D10. How this ride is validated (self-hosting)

The mechanism never judges its own delivery:

1. This spec is ceremony level 3, so `recheckMode` returns `ceremony_l3` for
   every round of this ride (TEST-2717 runs it on the live spec).
2. Every remediation of this ride touches `.aai/**`, which is production.
3. The orchestrator runs every Validation and Code Review round of this ride
   with `AAI_RECHECK_MODE=full` and the full canon payload, and the hand-off
   records it.
4. The validator's model differs from the implementer's, and Code Review runs
   on the most capable tier, as L3 requires.

### D11. Before and after (intake AC-003)

The recorded command is `node tests/skills/lib/recheck-measure.mjs`. It builds a
fixture git repository under the OS temp directory from the live canon inputs
(never the shipping tree), commits a base, adds a four-path non-production
delta shaped like node-first-third-slice round 4 (a suite, a node:test file,
the spec and one ledger line), seeds STATE, two prior reports with
`security_relevant: false`, an L2 spec and a `check_verdict` per role at the
base, then prints one JSON line per role with `full_bytes`, `delta_bytes` and
`ratio`. Before (measured at the intake commit): Code Review 32720 bytes,
Validation 45467 bytes per dispatch. After (delivered, output of this
command, re-measured after remediation round 1 added the output contracts to the
delta prompt and the `spec:` line to the scope): Code Review `full_bytes` 33082
(the D5 marker line grew the full prompt) and `delta_bytes` 11363, ratio 0.343;
Validation `full_bytes` 45843 and `delta_bytes` 11362, ratio 0.248. Against the
intake-commit bytes that is 32720 to 11363 and 45467 to 11362. At delivery the
numbers were 10238 (ratio 0.309) and 10237 (ratio 0.223); round 1 spent about
1.1 KB per delta dispatch on the contracts a checker needs. `delta_bytes` stays
at most 40% of `full_bytes` for both roles.
Tokens: the harness exposes `tokens_total` per run, but this ride has no delta
round by design (D10). The first ride that runs a delta round records its
`tokens_total` against the medians above (Code Review 91463, Validation
124934), identified by the `recheck=delta` run note.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01 (the measured baseline above, recomputed
  from METRICS by TEST-2701) and the Mechanism choice section.
- Intake AC-002 maps to Spec-AC-02 (applies), Spec-AC-03 (must not apply:
  production, protected, security, first round, L3 and the rest), Spec-AC-04
  (dispatch), Spec-AC-05 (stamps), Spec-AC-06 (canon), Spec-AC-07 (the
  end-to-end seam) and Spec-AC-11 and Spec-AC-12 (wiring and governance).
- Intake AC-003 maps to Spec-AC-08.
- Intake AC-004 maps to Spec-AC-03, Spec-AC-04 (independence fields
  unchanged) and Spec-AC-10 (this ride stays full).
- Intake AC-005 maps to Spec-AC-09.
- Remediation round 1 (code review r1 and validation r1, both FAIL) adds
  Spec-AC-14 to Spec-AC-18: the ref wiring and the full-identity fallback
  (B-1), the verdict base (B-2), the eligibility inputs a delta could edit
  (NB-1 to NB-3), the fail-closed switch and role lookup (N1, N5) and the
  payload contracts (NB-4).
- Intake AC-006 maps to Spec-AC-13. The six sign-off records were appended by
  the intake commit `d4738f91`; the row pins them.

## Constitution deviations

None. Article 1: no round is skipped, and every delta round still produces
executable evidence (the Validation outcome contract is unchanged). Article 2:
one library, one CANON key, two event types; no new workflow. Article 4: every
unknown resolves to the full payload with a named reason, and canon refuses
with an empty stdout. Article 5: the dispatch field and the CANON key are
additive, the default build is byte-identical, and `AAI_RECHECK_MODE=full`
restores today's behavior. Article 6: the library reads STATE and never writes
it.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | For each of the seven rides in the Measured baseline table, the Runs, CR runs, V runs, Rem runs, Ride tokens, Re-check rounds and Re-check tokens cells equal the values recomputed from the last docs/ai/METRICS.jsonl row of that ref (null tokens counted as 0). | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2701.log | tdd | TEST-2701 |
| Spec-AC-02 | WHEN recheckMode runs in a fixture repository whose focus spec is ceremony 2, with a check_verdict for the role at a base that is an ancestor of HEAD, a delta of only allowlisted paths (tracked and untracked), no protected match and prior reports each holding one security_relevant: false line, the system SHALL return mode delta with that base, the current head, the sorted changed paths and the prior report paths; every TREE_HASH_EXCLUDE_PATHS member SHALL classify as non-production. | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2702.log | tdd | TEST-2702 |
| Spec-AC-03 | WHEN any single D1 condition fails the system SHALL return mode full with its named reason: a tracked or untracked path outside the allowlist (production_path), an allowlisted path listed in a fixture protected_paths_l3 (protected_path), a prior report saying security_relevant: true, a report without the line or with it twice, an unreadable report, no prior report for the role, no check_verdict (first_round), ceremony 3 (ceremony_l3), an absent level (ceremony_unknown), a base that is not an ancestor, an empty delta, AAI_RECHECK_MODE=full (forced_full) and a failing git call (git_error); two failing conditions SHALL both be named. | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2703.log, docs/ai/tdd/cheap-transitions-slice/green/TEST-2704.log, docs/ai/tdd/cheap-transitions-slice/green/TEST-2705.log, docs/ai/tdd/cheap-transitions-slice/green/TEST-2706.log | tdd | TEST-2703, TEST-2704, TEST-2705, TEST-2706 |
| Spec-AC-04 | WHEN orchestration-dispatch.mjs dispatches Validation or Code Review the JSON SHALL carry a recheck object equal to recheckMode on the same tree plus a fallback key (null in mode full; on delta the full role prompt path and its prompt_hash), and every other verdict SHALL carry recheck null; on delta the system_prompt SHALL be .aai/RECHECK_DELTA.prompt.md and prompt_hash SHALL equal canon.mjs build --print-hash --recheck delta for that role; role, rule, suggested_tier, suggested_model, suggested_effort, validator_independence and lane SHALL equal the output for the same snapshot under AAI_RECHECK_MODE=full. | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2707.log, docs/ai/tdd/cheap-transitions-slice/green/TEST-2708.log, docs/ai/tdd/cheap-transitions-slice/green/TEST-2709.log | tdd | TEST-2707, TEST-2708, TEST-2709 |
| Spec-AC-05 | append-event.mjs SHALL accept check_dispatched and check_verdict with the D4 fields and refuse a missing role, an unknown role, a head that is not 40 lowercase hex and a check_verdict without status; WHEN a --confirm tick dispatches Validation or Code Review it SHALL append one check_dispatched with the HEAD and the seen marker, and WHEN a later --confirm tick sees a new verdict identity it SHALL append one check_verdict whose head equals the head of the earliest check_dispatched of that role after its last check_verdict (a re-tick at a newer head appends a further check_dispatched but never moves the base, and divergent unjudged heads stamp forty zeros); a repeated tick with the same head and seen marker and no verdict since, a repeated tick after the stamp, a tick without --confirm and a verdict with no prior check_dispatched SHALL append nothing. | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2710.log, docs/ai/tdd/cheap-transitions-slice/green/TEST-2711.log | tdd | TEST-2710, TEST-2711 |
| Spec-AC-06 | WHEN canon.mjs build runs with --recheck delta on an eligible tree the payload SHALL hold the section sequence contract, recheck, scope, exactly five HAZ lines, the role, base, head, each changed path and each prior report in the scope section, and no line unique to LEARNED.md or to the full role prompt; WHEN the tree is not eligible canon SHALL exit 11 with canon-recheck-refused and the reasons on stderr and an empty stdout; a build with --recheck full or without the flag SHALL be byte-identical to what the base commit's canon.mjs (ba552b89) builds from the same current inputs. | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2712.log, docs/ai/tdd/cheap-transitions-slice/green/TEST-2713.log | tdd | TEST-2712, TEST-2713 |
| Spec-AC-07 | WHEN a fixture repository runs real dispatch ticks with --confirm and real state.mjs writes through Validation dispatch, a fail verdict, Remediation, a test-only commit and reset-block, the next Validation dispatch SHALL carry recheck mode delta whose base equals the HEAD of the first dispatch and canon build --recheck delta SHALL succeed with the same changed paths; after a further commit to an .aai/scripts path the next dispatch SHALL carry mode full with production_path and canon SHALL refuse with exit 11. | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2714.log | tdd | TEST-2714 |
| Spec-AC-08 | node tests/skills/lib/recheck-measure.mjs SHALL exit 0 and print one JSON line for Code Review and one for Validation with integer full_bytes and delta_bytes, delta_bytes at most 0.40 times full_bytes for both, without writing to the repository it runs from; the D11 section of this spec and the RFC phase 4 row record the delivered numbers. | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2715.log | tdd | TEST-2715 |
| Spec-AC-09 | The RFC-0017 phase 4 row has status cell in progress, links a target ending in cheap-transitions-slice.md, and holds at least two N to M bytes pairs with M at most 0.40 times N; the frontmatter keeps status implementing and umbrella true; rows 0 and 2 stay in progress, rows 1 and 3 stay done and row 5 stays not started. | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2716.log | tdd | TEST-2716 |
| Spec-AC-10 | WHEN recheckMode runs on the live repository for ref cheap-transitions-slice with this spec as the focus spec, the system SHALL return mode full with ceremony_l3 among the reasons. | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2717.log | tdd | TEST-2717 |
| Spec-AC-11 | .aai/RECHECK_DELTA.prompt.md is at most 4096 bytes and contains aai-outcome-v1, validation-outcome-check, security_relevant, needs_full_recheck and independent; ORCHESTRATION.prompt.md contains --recheck delta and has at most 45 lines; ORCHESTRATION_PARALLEL.prompt.md contains canon.mjs build and no longer the phrase a copy of .aai/SUBAGENT_CONTRACT.md; SKILL_CODE_REVIEW.prompt.md and VALIDATION.prompt.md each contain security_relevant; SUBAGENT_PROTOCOL.md names canon.mjs in the INPUT row and contains recheck=delta, AAI_RECHECK_MODE and needs_full_recheck; WORKFLOW.md contains a delta re-check sentence that names L3. | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2718.log, docs/ai/tdd/cheap-transitions-slice/green/TEST-2719.log | tdd | TEST-2718, TEST-2719 |
| Spec-AC-12 | PROFILES.yaml lists .aai/scripts/lib/recheck.mjs and .aai/RECHECK_DELTA.prompt.md exactly once each, in core; select-suites.mjs selects aai-recheck for each new file other than the shared library with no FULL_RUN line, and for .aai/scripts/lib/recheck.mjs it prints FULL_RUN reason=shared-lib (a shared-library file triggers a full run by design, which includes aai-recheck) while the suite-map aai-recheck row still lists that file; the prompt-diet ledger holds an entry naming cheap-transitions-slice and the prompt-diet suite passes. | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2720.log, docs/ai/tdd/cheap-transitions-slice/green/TEST-2721.log, docs/ai/tdd/cheap-transitions-slice/green/TEST-2722.log | tdd | TEST-2720, TEST-2721, TEST-2722 |
| Spec-AC-13 | spec-amend list over the repository ledger shows at least six spec_amendment records of ref node-first-third-slice in bucket signed and none in any other bucket except measurement, and follow-ups list with status all shows fu-amend-spec-node-first-third-slice as done. | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2723.log | tdd | TEST-2723 |
| Spec-AC-14 | The documented canon command in ORCHESTRATION.prompt.md and ORCHESTRATION_PARALLEL.prompt.md SHALL pass the dispatch JSON ref_id (the placeholder ref_id, never HEAD); WHEN that command is run in an eligible fixture with the dispatch ref_id and --recheck delta it SHALL exit 0 and with HEAD as the ref it SHALL exit 11; a delta dispatch SHALL carry recheck.fallback holding the full role prompt path and a prompt_hash equal to canon.mjs build --print-hash for that role and to the prompt_hash of the same dispatch under AAI_RECHECK_MODE=full, and a full dispatch SHALL carry recheck.fallback null; every append-run capture site of the dispatch prompt_hash (SUBAGENT_PROTOCOL.md twice, SKILL_LOOP.prompt.md once) SHALL name the recheck.fallback hash for a refused delta. | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2725.log, docs/ai/tdd/cheap-transitions-slice/green/TEST-2737.log | tdd | TEST-2725, TEST-2737 |
| Spec-AC-15 | WHEN a --confirm re-tick appends a check_dispatched at a newer head while the check has no verdict, the check_verdict SHALL carry the earliest unjudged head, so that after a test-only fix and reset-block the next dispatch SHALL be mode full with the production commit made in between named in production_path and the old head as the base; WHEN the unjudged heads do not lie on one line of history the stamp SHALL carry AMBIGUOUS_HEAD and the next round SHALL name base_not_ancestor. | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2724.log | tdd | TEST-2724 |
| Spec-AC-16 | The delta SHALL NOT decide its own eligibility: a staged rename out of a production path and a deleted production file SHALL give production_path for the production end; an L3 focus spec rewritten to a lower level, a level raised, a level removed, a spec deleted and a spec absent at the base SHALL give ceremony_l3 or ceremony_unknown; a prior report that existed at the base and was edited or deleted in the delta SHALL give prior_report_changed and its marker SHALL be read from the base blob while a report written after the base is read live and can only raise, never lower, the stamped marker of its verdict: the marker of the judged round's own report SHALL be taken from the check_verdict stamp written when its verdict was first seen (a committed Code Review report flipped from true to false inside the delta, and a gitignored Validation report flipped in place, SHALL both give full), a stamp without the marker SHALL count as absent, and once any stamped verdict of either role says true every later round SHALL be full; every file under tests/ other than test code (suite, Pester file, node:test file) SHALL be production, including every tests/ path merge-policy GUARD_PATHS names and every tests/ file a production script names by literal path. | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2726.log, docs/ai/tdd/cheap-transitions-slice/green/TEST-2727.log, docs/ai/tdd/cheap-transitions-slice/green/TEST-2728.log, docs/ai/tdd/cheap-transitions-slice/green/TEST-2729.log, docs/ai/tdd/cheap-transitions-slice/green/TEST-2730.log | tdd | TEST-2726, TEST-2727, TEST-2728, TEST-2729, TEST-2730, TEST-2734, TEST-2735, TEST-2736 |
| Spec-AC-17 | AAI_RECHECK_MODE SHALL be trimmed and lower-cased and any value other than unset, empty or delta SHALL force full with forced_full; a role name that is an inherited property (__proto__, constructor, toString) SHALL be an unknown role with role_not_rechecked and SHALL NOT throw in recheckMode or planCheckStamps. | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2731.log, docs/ai/tdd/cheap-transitions-slice/green/TEST-2732.log | tdd | TEST-2731, TEST-2732 |
| Spec-AC-18 | RECHECK_DELTA.prompt.md (at most 4096 bytes) SHALL carry the report path docs/ai/reviews/review- with the never docs/validation rule, the H6 disposition duty with accepted residual, the set-code-review and set-validation shapes, aai-outcome-v1, validation-outcome-check.mjs with Before any PASS, outcome_report and state_update_commands, each pointing at a section that exists in the full prompt; the delta scope section SHALL name the spec path. | done | docs/ai/tdd/cheap-transitions-slice/green/TEST-2733.log | tdd | TEST-2733 |
| TEST-2734 | Spec-AC-16 | unit | tests/skills/test-aai-recheck.sh | test_2734_stamped_security_marker builds a judged round by planCheckStamps and appends its check_verdict: a Code Review report that said true at verdict time and is flipped to false in a commit inside the delta (probe Q8), and a gitignored Validation report flipped in place (probe Q9, git status shows nothing), both give full with security_relevant:stamp:<role>; the same flow with a false report gives a false stamp and delta for each role | `sed:s/e\.payload\.security_relevant === true\)\) reasons/e.payload.security_relevant === 7)) reasons/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2735 | Spec-AC-16 | unit | tests/skills/test-aai-recheck.sh | test_2735_stamp_without_marker_and_sticky: a report without a marker line plans a stamp without the field and the next round gives security_marker_absent:stamp:validation; a hand-written stamp without the field is absent too; an earlier true stamp followed by a false one stays full; a true stamp of the other role keeps the role full | `sed:s/priorVerdict\.payload\.security_relevant !== false/priorVerdict.payload.security_relevant === 5/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2736 | Spec-AC-16 | integration | tests/skills/test-aai-recheck.sh | test_2736_tick_records_marker runs real --confirm ticks: the check_verdict the tick appends carries security_relevant false read from the report STATE names; append-event accepts --security-relevant true and refuses any other value without appending | `sed:s/if \(marker !== null\) stamp\.security_relevant = marker;/if (marker !== null) stamp.security_relevant = undefined;/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2737 | Spec-AC-14 | inspection | tests/skills/test-aai-recheck.sh | test_2737_capture_sites_fallback checks that SUBAGENT_PROTOCOL.md names recheck.fallback in the delta section and at both prompt_hash capture sites, and that the SKILL_LOOP.prompt.md append-run capture step names it | `sed:s/recheck\.fallback\.prompt_hash/the fallback hash/` on .aai/SKILL_LOOP.prompt.md | green |

## Implementation plan

1. RED: write `tests/skills/lib/recheck.test.mjs`, `tests/skills/lib/recheck-measure.mjs`
   and `tests/skills/test-aai-recheck.sh` (plus the TEST-2722 function in
   `test-aai-prompt-diet.sh`); run each row's function alone on the unchanged
   tree and store the output under `docs/ai/tdd/cheap-transitions-slice/red/`.
2. Write `lib/recheck.mjs` (D1 to D3, D5 reading); TEST-2702 to TEST-2706 and
   TEST-2717 go green.
3. Add the two event types and the tick stamps (D4); TEST-2710 and TEST-2711.
4. Add the dispatch field (D6) and the `TREE_HASH_EXCLUDE_PATHS` export;
   TEST-2707 to TEST-2709.
5. Add the CANON key, the `recheck_scope` section type, the `--recheck` flag and
   the delta prompt (D7, D8); TEST-2712 to TEST-2715.
6. Wiring and docs (D9), the RFC row with the measured numbers, the D11 numbers
   in this spec (the one post-freeze edit expected, made with `spec-amend`);
   TEST-2716 and TEST-2718 to TEST-2722 go green.
7. Run the suites in Verification through the wrapper and record one mutation
   per row.

Seams crossed (each with a test that produces on one side and reads the real
result on the other):

- Dispatch tick to EVENTS to library: TEST-2711 and TEST-2714 let the real
  dispatch write the stamps and the real library read them.
- Library to dispatch and to canon: TEST-2707 and TEST-2714 compare the
  dispatch `recheck` object with what canon accepts or refuses on the same tree.
- Dispatch `prompt_hash` to canon `--print-hash`: TEST-2709 (the TEST-682 and
  TEST-683 pattern).
- STATE written by `state.mjs` to the library's read: TEST-2714 uses real
  `set-validation` and `reset-block` calls, not hand-written STATE.
- `docs/ai/docs-audit.yaml` to the protected arm: TEST-2704 plants the entry in
  a fixture config the library reads through the real parser.
- A delta Validation report to `validation-outcome-check.mjs`: not crossed by a
  test in this slice (no ride runs a delta round here); the prompt pins the
  contract (TEST-2718), and the residual is listed under Risks.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-2701 | Spec-AC-01 | inspection | tests/skills/test-aai-recheck.sh | test_2701_baseline_table_matches_metrics parses the first table of the Measured baseline section of this spec and, for each ride, recomputes Runs, CR runs, V runs, Rem runs, Ride tokens, Re-check rounds and Re-check tokens from the last METRICS.jsonl row of that ref; every cell must match and at least three rides must be present | `sed:s/"tokens_total":256979,/"tokens_total":256978,/` on docs/ai/METRICS.jsonl | green |
| TEST-2702 | Spec-AC-02 | unit | tests/skills/test-aai-recheck.sh | test_2702_delta_applies runs node --test --test-name-pattern TEST-2702 on tests/skills/lib/recheck.test.mjs: a fixture repo with an L2 spec, a check_verdict at the base, a tracked change under tests/, an untracked file under docs/specs/, a decisions.jsonl line and two reports with security_relevant: false returns mode delta, the base, the head, the three sorted paths and both reports; every TREE_HASH_EXCLUDE_PATHS member is non-production | `sed:s/mode: 'delta',/mode: 'full',/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2703 | Spec-AC-03 | unit | tests/skills/test-aai-recheck.sh | test_2703_production_refused runs the TEST-2703 node cases: a tracked change to .aai/scripts/x.mjs, an untracked .aai/new.mjs, a change to docs/knowledge/LEARNED.md and one to docs/ai/docs-audit.yaml each give full with production_path naming that path; a production path plus a test path names only the production one | `sed:s/const NON_PRODUCTION_PATTERNS = \[/const NON_PRODUCTION_PATTERNS = [\/.\/, /` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2704 | Spec-AC-03 | unit | tests/skills/test-aai-recheck.sh | test_2704_protected_refused runs the TEST-2704 node cases: a fixture docs-audit.yaml whose protected_paths_l3 lists tests/skills/guarded.sh turns a change to that test file into full with protected_path; the same change without the entry gives delta; an unreadable config gives protected_config_unreadable | `sed:s/protected_paths_l3/protected_paths_l3_gone/g` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2705 | Spec-AC-03 | unit | tests/skills/test-aai-recheck.sh | test_2705_security_refused runs the TEST-2705 node cases: one report with security_relevant: true gives security_relevant naming it; a report without the line, a report with the line twice and a missing report file give security_marker_absent or prior_report_unreadable; no report for the role gives security_marker_absent with the role | `sed:s/security_relevant: true/security_relevant: never/g` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2706 | Spec-AC-03 | unit | tests/skills/test-aai-recheck.sh | test_2706_other_refusals runs the TEST-2706 node cases: no check_verdict gives first_round; ceremony 3 gives ceremony_l3; an absent level gives ceremony_unknown; a base on a sibling branch gives base_not_ancestor; HEAD equal to the base with a clean tree gives no_delta; AAI_RECHECK_MODE=full gives forced_full; a root that is not a git repository gives git_error; first round plus a production path names both | `sed:s/if \(!priorVerdict\)/if (false)/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2707 | Spec-AC-04 | integration | tests/skills/test-aai-recheck.sh | test_2707_dispatch_field runs orchestration-dispatch.mjs in an eligible fixture at rule 11 and rule 13: recheck.mode is delta and deep-equals recheckMode on the same root, system_prompt is .aai/RECHECK_DELTA.prompt.md; a Remediation dispatch and a no_action verdict carry recheck null | `sed:s/const RECHECK_ROLES = new Set\(\['Validation', 'Code Review'\]\);/const RECHECK_ROLES = new Set([]);/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2708 | Spec-AC-04 | integration | tests/skills/test-aai-recheck.sh | test_2708_independence_unchanged runs the rule 11 fixture twice, once eligible and once with AAI_RECHECK_MODE=full, with an implementer model recorded: role, rule, suggested_tier, suggested_model, suggested_effort, validator_independence (must_differ true, the implementer model) and lane are deep-equal, and suggested_model differs from the implementer model | `sed:s/must_differ: true/must_differ: false/` on .aai/scripts/orchestration-dispatch.mjs | green |
| TEST-2709 | Spec-AC-04 | integration | tests/skills/test-aai-recheck.sh | test_2709_prompt_hash_seam compares the prompt_hash of the delta Validation dispatch with canon.mjs build --role Validation --print-hash --recheck delta in the same root, and the Code Review pair the same way; both pairs are equal and differ from the full-mode hash | `sed:s/path: .aai\/RECHECK_DELTA.prompt.md/path: .aai\/REMEDIATION.prompt.md/` on .aai/system/CANON.yaml | green |
| TEST-2710 | Spec-AC-05 | unit | tests/skills/test-aai-recheck.sh | test_2710_event_schema runs append-event.mjs in a fixture: check_dispatched with role, head and seen and check_verdict with role, head and status append one line each with the payload fields; a missing role, role reviewer, a 39-character head, an upper-case head and a check_verdict without status each exit non-zero and append nothing | `sed:s/const HEAD_SHA_RE = \/\^\[0-9a-f\]\{40\}\$\/;/const HEAD_SHA_RE = \/.\/;/` on .aai/scripts/append-event.mjs | green |
| TEST-2711 | Spec-AC-05 | integration | tests/skills/test-aai-recheck.sh | test_2711_tick_stamps runs dispatch ticks in a fixture: a --confirm rule 11 tick appends one check_dispatched with the HEAD; the same tick again appends no second check_dispatched and no check_verdict; after set-validation fail a --confirm tick appends one check_verdict with status fail and the dispatched head, and a repeat appends nothing; a tick without --confirm appends nothing; a verdict with no check_dispatched is never stamped | `sed:s/'check_verdict'/'check_verdict_gone'/g` on .aai/scripts/orchestration-dispatch.mjs | green |
| TEST-2712 | Spec-AC-06 | integration | tests/skills/test-aai-recheck.sh | test_2712_canon_delta_payload runs canon.mjs build --role Code Review --ref r --recheck delta in an eligible fixture: the section ids are contract recheck scope, five lines start with - HAZ-, the scope names the role, base, head, each changed path and each report, and a line unique to LEARNED.md and one unique to SKILL_CODE_REVIEW.prompt.md are absent | `sed:s/delta_sections:/delta_sections_gone:/g` on .aai/system/CANON.yaml | green |
| TEST-2713 | Spec-AC-06 | integration | tests/skills/test-aai-recheck.sh | test_2713_canon_refusal_and_identity runs --recheck delta in a first-round fixture and in a production-delta fixture: exit 11, stdout empty, stderr canon-recheck-refused with first_round and production_path; then for all six roles the build with --recheck full and without the flag is byte-identical to what the ba552b89 canon.mjs, copied into a scratch copy of the current tree, builds from the same current inputs | `sed:s/if \(rc.mode !== 'delta'\)/if (false)/` on .aai/scripts/canon.mjs | green |
| TEST-2714 | Spec-AC-07 | e2e | tests/skills/test-aai-recheck.sh | test_2714_end_to_end runs the D4 sequence in a fixture repo with the real dispatch, state.mjs and append-event: tick 1 dispatches Validation, set-validation fail, tick 2 dispatches Remediation, a test-only commit, reset-block last_validation, tick 3 dispatches Validation with recheck mode delta and base equal to the tick 1 HEAD, canon build --recheck delta exits 0 and its scope lists the same paths; a commit to .aai/scripts/fixture.mjs, then tick 4 gives full with production_path and canon exits 11 | `sed:s/'check_verdict'/'check_verdict_x'/g` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2715 | Spec-AC-08 | integration | tests/skills/test-aai-recheck.sh | test_2715_measure_ratio runs node tests/skills/lib/recheck-measure.mjs, requires exit 0, two JSON lines for Code Review and Validation with integer full_bytes and delta_bytes and delta_bytes at most 0.40 times full_bytes, and git status --porcelain of the project root unchanged before and after | `sed:s/path: .aai\/RECHECK_DELTA.prompt.md/path: .aai\/VALIDATION.prompt.md/` on .aai/system/CANON.yaml | green |
| TEST-2716 | Spec-AC-09 | inspection | tests/skills/test-aai-recheck.sh | test_2716_rfc_phase4_row parses the RFC-0017 Rollout Status table: phase 4 status cell is in progress, a link target ends in cheap-transitions-slice.md, at least two matches of N to M bytes each with M at most 0.40 times N; frontmatter status implementing and umbrella true; rows 0 and 2 in progress, rows 1 and 3 done, row 5 not started | `sed:s/cheap-transitions-slice.md/cheap-transitions-gone.md/g` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |
| TEST-2717 | Spec-AC-10 | integration | tests/skills/test-aai-recheck.sh | test_2717_ride_stays_full runs recheckMode on a scratch copy of the live tree with STATE focus cheap-transitions-slice and this spec as spec path, role Validation and role Code Review: mode full and ceremony_l3 in the reasons for both | `sed:s/const PROTECTED_LEVEL = 3;/const PROTECTED_LEVEL = 9;/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2718 | Spec-AC-11 | inspection | tests/skills/test-aai-recheck.sh | test_2718_prompts checks RECHECK_DELTA.prompt.md (size at most 4096 bytes, the five literals), ORCHESTRATION.prompt.md (--recheck delta, at most 45 lines), ORCHESTRATION_PARALLEL.prompt.md (canon.mjs build present, the old copy phrase absent), and security_relevant in SKILL_CODE_REVIEW.prompt.md and VALIDATION.prompt.md | `sed:s/security_relevant/security_flag/g` on .aai/SKILL_CODE_REVIEW.prompt.md | green |
| TEST-2719 | Spec-AC-11 | inspection | tests/skills/test-aai-recheck.sh | test_2719_protocol_and_workflow checks that the SUBAGENT_PROTOCOL.md INPUT row names canon.mjs, that the file contains recheck=delta, AAI_RECHECK_MODE and needs_full_recheck, and that WORKFLOW.md has a line containing delta re-check and L3 | `sed:s/recheck=delta/recheck-delta/g` on .aai/SUBAGENT_PROTOCOL.md | green |
| TEST-2720 | Spec-AC-12 | inspection | tests/skills/test-aai-recheck.sh | test_2720_profiles_classified asserts .aai/scripts/lib/recheck.mjs and .aai/RECHECK_DELTA.prompt.md each appear exactly once in PROFILES.yaml, inside the core list | `sed:s/lib\/recheck.mjs/lib\/recheck-gone.mjs/g` on .aai/system/PROFILES.yaml | green |
| TEST-2721 | Spec-AC-12 | integration | tests/skills/test-aai-recheck.sh | test_2721_suite_map_selects feeds each new file path to node .aai/scripts/select-suites.mjs --files-from - and requires a SELECTED aai-recheck line and no FULL_RUN line for every new file except .aai/scripts/lib/recheck.mjs, for which it requires FULL_RUN reason=shared-lib and the suite-map aai-recheck row listing the file | `sed:s/lib\/recheck.mjs/lib\/recheck-gone.mjs/g` on tests/skills/suite-map.yaml | green |
| TEST-2722 | Spec-AC-12 | inspection | tests/skills/test-aai-prompt-diet.sh | test_2722_diet_entry_for_slice requires one JUSTIFIED_ADDITIONS entry whose text names cheap-transitions-slice and starts with a positive byte count; the suite's TEST-012 sum check covers the total | `sed:s/cheap-transitions-slice/cheap-transitions-gone/g` on tests/skills/lib/prompt-diet-ledger.sh | green |
| TEST-2723 | Spec-AC-13 | inspection | tests/skills/test-aai-recheck.sh | test_2723_497_amendments_signed runs node .aai/scripts/spec-amend.mjs list --json and requires at least six records of ref node-first-third-slice in bucket signed and none outside signed and measurement; then node .aai/scripts/follow-ups.mjs list --status all --json and requires fu-amend-spec-node-first-third-slice with status done | `sed:s/"classifies_ref":"node-first-third-slice","owner_signoff":true/"classifies_ref":"node-first-third-slice","owner_signoff":false/` on docs/ai/decisions.jsonl | green |
| TEST-2724 | Spec-AC-15 | integration | tests/skills/test-aai-recheck.sh | test_2724_earliest_unjudged_head runs the probe sequence with real ticks: dispatch H1, a production commit, a --confirm re-tick at H2, set-validation fail, a tick; the check_verdict head is H1; after a test-only fix and reset-block the dispatch is full with production_path naming the in-flight file and base H1; planCheckStamps over divergent unjudged heads stamps AMBIGUOUS_HEAD and the next recheckMode names base_not_ancestor; two dispatches on one line of history stamp the earlier one | `sed:s/const first = dispatches\[0\]\.payload\.head;/const first = dispatches[dispatches.length - 1].payload.head;/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2725 | Spec-AC-14 | integration | tests/skills/test-aai-recheck.sh | test_2725_orchestration_ref_wiring extracts the canon build command from ORCHESTRATION.prompt.md and runs it with the dispatch ref_id in an eligible fixture (exit 0, recheck section present), with HEAD as the ref (exit 11), and after a production commit (exit 11); the delta dispatch recheck.fallback equals the full role prompt path and canon --print-hash and the prompt_hash of the same dispatch under AAI_RECHECK_MODE=full; the protocol states that the delta note is recorded only for a sent payload | `sed:s/--ref <ref_id>/--ref HEAD/` on .aai/ORCHESTRATION.prompt.md | green |
| TEST-2726 | Spec-AC-16 | unit | tests/skills/test-aai-recheck.sh | test_2726_rename_refused stages git mv from .aai/scripts/x.mjs into tests/skills/test-aai-moved.sh: mode full with production_path for the old path and both ends listed; a rename inside tests/ is delta | `sed:s/'--no-renames', //` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2727 | Spec-AC-16 | unit | tests/skills/test-aai-recheck.sh | test_2727_delete_refused deletes a production file by git rm and another by rm, each beside a test edit: full with production_path naming it; deleting a test file is delta | `sed:s/'--no-renames'/'--diff-filter=d'/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2728 | Spec-AC-16 | unit | tests/skills/test-aai-recheck.sh | test_2728_delta_cannot_lower_level rewrites an L3 spec to level 2 inside the delta (ceremony_l3), raises a level, removes a level, deletes the spec and adds a spec absent at the base (ceremony_unknown); a body edit that leaves the level alone stays delta and reports spec_path | `sed:s/if \(base && !gitFailed\) levels\.push/if (false) levels.push/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2729 | Spec-AC-16 | unit | tests/skills/test-aai-recheck.sh | test_2729_prior_reports_from_base edits a true report to false inside the delta (prior_report_changed and security_relevant from the base blob), deletes one, appends to one; reports written after the base are read live and give delta, a new report that says true refuses | `sed:s/if \(atBase && changed\.includes\(p\)\) reasons/if (false) reasons/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2730 | Spec-AC-16 | integration | tests/skills/test-aai-recheck.sh | test_2730_tests_gate_inputs_production classifies suites, Pester files and node:test files as non-production and suite-map.yaml, suite-weights.tsv, the baselines, the ratchet, the diet ledger and test-framework.sh as production; every tests/ path in merge-policy GUARD_PATHS and every tests/ file a production script names by literal path is production unless it is test code; a changed suite-map.yaml gives production_path | `sed:s/export const NON_PRODUCTION_PATTERNS = \[/export const NON_PRODUCTION_PATTERNS = [\/.\/, /` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2731 | Spec-AC-17 | unit | tests/skills/test-aai-recheck.sh | test_2731_mode_switch_fails_closed requires forcedFull true for full in any case or padding, off, 0, false and a misspelling, false for unset, empty, whitespace and delta in any case; recheckMode and the dispatch give forced_full for a padded upper-case full | `sed:s/return v !== '' && v !== 'delta';/return v === 'full';/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2732 | Spec-AC-17 | unit | tests/skills/test-aai-recheck.sh | test_2732_inherited_role_names runs recheckMode and planCheckStamps with __proto__, constructor, toString, hasOwnProperty and valueOf: no throw, full with role_not_rechecked; canon refuses the role without a stack trace | `sed:s/Object\.hasOwn\(ROLE_TOKENS, role\) \? ROLE_TOKENS\[role\] : null/ROLE_TOKENS[role] ?? null/` on .aai/scripts/lib/recheck.mjs | green |
| TEST-2733 | Spec-AC-18 | inspection | tests/skills/test-aai-recheck.sh | test_2733_delta_payload_contracts checks the delta prompt size and the contract literals, that the full prompts hold the sections it names, and that the delta scope section of canon --recheck delta holds the line spec followed by the spec path | `sed:s/set-code-review/set-review/g` on .aai/RECHECK_DELTA.prompt.md | green |

### RED observations and positive controls

- TEST-2702 to TEST-2717: RED on the baseline because the library, the event
  types, the dispatch field, the CANON key, the canon flag and the measure
  script do not exist (import or flag fails). The node wrapper's
  zero-passing-tests guard makes a missing test name RED, not vacuously green.
- TEST-2701: RED on the baseline because `test-aai-recheck.sh` does not exist;
  its own positive control is the mutation record.
- TEST-2718 to TEST-2722: RED on the baseline (files, literals, rows and the
  ledger entry absent; the parallel prompt still holds the copy phrase).
- TEST-2723: passes on the baseline (signed by `d4738f91`); its RED is the
  mutation record.
- Positive controls inside the fixtures: TEST-2704 asserts delta for the same
  change without the protected entry before asserting the refusal; TEST-2715
  asserts the fixture's full build equals the live full build for each role;
  TEST-2706 asserts the sibling-branch base exists before asserting
  base_not_ancestor.

## Verification

- New suite: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-recheck.sh` exits 0.
- Direct Node tests: `node --test tests/skills/lib/recheck.test.mjs` exits 0 under local Node 22.
- Canon: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-canon.sh` exits 0 (TEST-682, TEST-683 and TEST-684 among them).
- Dispatch: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-orchestration-dispatch.sh` exits 0.
- Prompt diet: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh` exits 0.
- Governance pins: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh`, `... test-aai-r-guard.sh`, `... test-aai-layer-profiles.sh`, `... test-aai-ceremony-levels.sh`, `... test-aai-lightweight-lane.sh`, `... test-aai-role-output.sh` and `... test-aai-suite-select.sh` each exit 0.
- Selection over the scope: `git diff --name-only ba552b89 | node .aai/scripts/select-suites.mjs --files-from -`, every selected suite exits 0 through the wrapper; one full sweep with `AAI_TEST_TIMEOUT=3000` before close.
- Measurement: `node tests/skills/lib/recheck-measure.mjs` output recorded verbatim in D11 and the RFC row.
- Canon claims: `node .aai/scripts/canon.mjs claims` exits 0.
- Amendment ledger: `node .aai/scripts/spec-amend.mjs list --strict` exits 0.
- Registration: `node .aai/scripts/check-test-registration.mjs tests/skills` exits 0.
- Mutation records: `node .aai/scripts/mutation-run.mjs --spec <this spec> --test-id <id> --suite <suite> --selector <function> --target <file> --sed '<expr>'` per row; `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exits 0.
- Spec lint: `node .aai/scripts/spec-lint.mjs --path <this spec>` reports no error.
- Docs audit on the RFC and this spec: `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path <file>` reports no finding this scope introduced.
- Self-hosting: the hand-off states that every Validation and Code Review round
  of this ride ran with `AAI_RECHECK_MODE=full` and the full canon payload.

## Evidence contract

Per TEST and Spec-AC: command, exit code, output path under
`docs/ai/tdd/cheap-transitions-slice/`, and the mutation record from
`mutation-run.mjs`. Each AC Evidence cell cites a `docs/ai/tdd/` artifact at
hand-off. Strategy hybrid: stored RED per AC-gating test plus the verification
list above. Planning's measurements are inputs, not attestations of the
implementation.

## Risks and rollback

- The security marker is a classification by the checker. A checker that
  marks a security finding false would let a later test-only delta run in
  delta mode. The delta round is still an independent model review of the
  delta, a production change still refuses, and the marker is sticky by
  instruction; the residual is accepted and named here.
- No ride in this slice runs a delta round (D10), so the seam from a delta
  Validation report to `validation-outcome-check.mjs` is pinned only by the
  prompt text, and the token effect is unmeasured. The first ride with a delta
  round is the observation; `AAI_RECHECK_MODE=full` turns the mode off without
  a code change.
- The prompt hash of a delta dispatch includes `LEARNED.md`, which the delta
  payload does not send (the existing hash function's fixed inputs). The hash
  over-reacts to a LEARNED edit; it never misses a change of the delta stack.
- `check_dispatched` and `check_verdict` add lines to `docs/ai/EVENTS.jsonl` on
  every check round. The file is append-only and excluded from the tree hash;
  merges keep the base as a byte-exact prefix (HAZ-LEDGER).
- Editing `.aai/workflow/WORKFLOW.md` makes this L3: operator checkpoint before
  merge. Consumer-visible: merge needs the owner's menu (intake constraint).
- The RFC row stays `in progress` on an open umbrella RFC; at close, a
  docs-audit false-open is handled with a fresh `doc_lifecycle` event, as the
  earlier phase children did.
- TEST-2701 and TEST-2723 pin ledger facts; a legitimate later rewrite of those
  records would redden them and must amend or retire the rows.
- Rollback: set `AAI_RECHECK_MODE=full`, or revert the scope's files; the two
  event types stay readable as unknown history.

## Registry disposition

Registry items closed by this scope: `fu-orchestration-parallel-still-pastes`
and `fu-subagent-protocol-input-row-stale` (both edit the dispatch payload
wording this scope changes, D9). `fu-amend-spec-node-first-third-slice` was
closed by the intake commit `d4738f91`; TEST-2723 pins it.

Related open items, left open: `fu-claims-report-drops-root-annotation`
(canon claims reporting, not touched), `fu-learned-standing-annotation-anchor`
and `fu-amend-spec-slim-standing-role-context` (the standing-lessons slice,
not touched), `fu-mutation-rows-share-selectors` (TEST-2709 and TEST-2715 share
one sed target with different replacements; each row names its own test id).
