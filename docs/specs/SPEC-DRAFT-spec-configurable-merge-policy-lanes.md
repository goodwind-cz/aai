---
id: spec-configurable-merge-policy-lanes
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 25b384b9e308157d5664b4f2d1560336491ca2aa19f32acb86b8575acd2c303c
ceremony_level: 3
links:
  requirement: null
  rfc: docs/rfc/RFC-DRAFT-configurable-merge-policy-lanes.md
  intake: docs/rfc/RFC-DRAFT-configurable-merge-policy-lanes.md
  pr: []
  commits: []
---

# Spec — An owner-signed merge policy decides which pull requests the agent may merge

SPEC-FROZEN: true

## Links
- Requirement: RFC `configurable-merge-policy-lanes` (accepted), docs/rfc/RFC-DRAFT-configurable-merge-policy-lanes.md
- Source issue: GitHub goodwind-cz/aai#429
- Owner decisions: the RFC's "Decisions (owner, 2026-10-03)" D1 to D4, and the
  `hitl_decision` with `ref_id: configurable-merge-policy-lanes` at
  `2026-10-03T15:30:00Z` in docs/ai/decisions.jsonl
- Prior art: RFC-0010 (hook-enforced gates), RFC-0014 D1 (scope, cost and
  irreversibility stay with a human; self-declared severity rejected),
  the 2026-09-12 standing merge authorization (`ref_id: wave-2-roadmap`)
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, bash-3.2 suites,
  no YAML library: every config is a closed-shape line-level parse)

## Problem

`.aai/SKILL_PR.prompt.md` step 6 forbids `gh pr merge` outright. Its one
exception, STANDING AUTHORIZATION, is prose that points at one owner record
and excludes, by name, every public side effect and every ceremony-3 ride.
A downstream owner who has decided "content and design pull requests merge
when CI is green and the requester approved them" cannot say so: `.aai/` is
vendored and rewritten by every sync, and the hook overlay that enforces the
boundary guards Claude Code sessions only. Other harnesses read prose, and the
most absolute prose layer wins.

This scope replaces the prose exception with one project-owned, declarative
file (`docs/ai/merge-policy.yaml`) and one deterministic evaluator
(`.aai/scripts/merge-policy.mjs`). Every harness, the hook and `SKILL_PR`
consult the same evaluator. No file means today's behaviour exactly.

## Scope

In scope:
- New `.aai/scripts/merge-policy.mjs` with three modes: `--check --pr <n>`,
  `--validate`, and `--classify` (an authoring aid that prints how each path
  classifies).
- The policy schema, closed-shape and parsed line by line.
- The merge gate in `.aai/scripts/claude-hook-gate.sh` gains a lane path.
- `SKILL_PR` step 6, the `AGENTS.md` closeout line and the `SKILL_SHIP` merge
  checkpoint defer to the evaluator. The STANDING AUTHORIZATION prose is removed.
- This repository's own `docs/ai/merge-policy.yaml`, carrying the 2026-09-12
  standing authorization as one lane.
- `aai-doctor` category CAT-19 (Merge Policy).
- Constitution article 7 amended to v2.
- Companion obligations: PROFILES classification, `DOCS_AI_CANON.list` entry,
  prompt-diet ledger true-up with the TEST-012 pin, suite-map entries and a
  CHANGELOG entry.

Out of scope:
- A diff-content tripwire, for example a new `<script src>` in a content file.
  Owner decision D3 makes it a follow-up.
- Labels or agent-written records as requester approval. D1 rejects both.
- Wiring the evaluator into non-Claude harnesses. AAI ships the single source
  of truth, and each harness calls it.
- Changing how `AAI_OPERATOR_MERGE` is detected (see Residual risks R5).

Size judgement: 23 Spec-ACs is large, but one ride can carry it. The
migration (Spec-AC-18/19) cannot be split from the evaluator. Removing the
prose exception before the lane exists would remove this repository's
standing authorization for the interval between the two merges, and keeping
both would ship the two-path state the RFC exists to remove. If the owner
still wants a split, cut it after Spec-AC-17: Phase A = evaluator, validate,
hook and doctor (Spec-AC-01..17, 20, 22), with the prose and constitution left
untouched. Phase B = migration, prose removal and constitution v2 (Spec-AC-18,
19, 21, 23).

## Design decisions

### P1 — Schema (closed shape, line-level, two-space indentation)

```yaml
# docs/ai/merge-policy.yaml — absent file = operator-only merge, unchanged.
version: 1
deploy:
  preview: none                # none, private or public
  production_on_merge: false   # true when a merge to the base branch deploys production
architecture:                  # closed list; any match makes the PR operator-only
  - id: containers
    globs: ["Dockerfile", "**/Dockerfile", "**/docker-compose*.yml"]
kinds:                         # closed world; a path matching no kind denies
  - id: content
    globs: ["src/content/**", "**/*.md"]
lanes:
  - id: requester-content
    decision_ref: some-ref@2026-10-01T10:00:00Z
    decision_match: "MERGE LANE requester-content"
    signed_by: owner_login
    kinds: [content]
    merge_reaches: preview     # nothing, preview or production
    allow_public_side_effect: true
    max_ceremony: 3            # optional; absent means 2
    marker: AAI_CONTENT_LANE_MERGE
    requester_logins: [requester-login]
    requires:                  # optional ride conditions; every key optional
      intake_types: [change, issue]
      exclude_roadmap_capability: true
      validation_pass: true
      review_pass: true
      pr_body_contains: "Residual"
```

Any key outside this shape is `unknown_key` and makes the policy invalid.
That includes any key that would switch off CI or the sweep check. Those two
checks are not configurable.
Lists may be written in flow style (`[a, b]`). Scalars may be quoted.

### P2 — Decision binding

`decision_ref` is `<ref_id>@<ts>`. A lane binds to exactly one record in the
base branch's `docs/ai/decisions.jsonl`. That record must satisfy all of:
- `type` is `hitl_decision`
- `owner_signoff` is `true`
- `ref_id` and `ts` match
- `actor` equals `signed_by`
- the `decision` text contains `decision_match`

Zero matching records or more than one is invalid. `wave-2-roadmap` has three
records sharing one `ts`, so `decision_match` is required, not optional.

### P3 — Everything the check reads comes from the base branch or the platform

`--check` makes one `gh pr view <n> --json
number,state,isDraft,baseRefName,baseRefOid,headRefOid,reviews,statusCheckRollup,body`
call. It then reads `docs/ai/merge-policy.yaml`, `docs/ai/decisions.jsonl` and
`docs/ai/roadmap.yaml` with `git show <baseRefOid>:<path>`. It never reads the
working tree or the PR head for these three files. The changed-file list is
`git diff --name-only --no-renames <baseRefOid>...<headRefOid>`, so a rename
shows up as a delete plus an add. If either object is missing locally, the
result is `base_unavailable`. The evaluator never fetches.

### P4 — Guard paths

`GUARD_PATHS` is a constant in the evaluator. It holds
`docs/ai/merge-policy.yaml`, `.aai/scripts/merge-policy.mjs`,
`.aai/scripts/claude-hook-gate.sh`, `.aai/scripts/lane-gate.mjs` and every
`.aai/scripts/lib/*.mjs` that the evaluator or lane-gate imports. A PR that
touches any of these paths is denied with `policy_touched`, whatever the
lanes say.

For this repository this is a tightening relative to the 2026-09-12 prose.
An internal ride that edits the merge machinery now goes to the operator.
It is disclosed as HITL-2 below.

### P5 — Classification (owner decision D3)

Globs are anchored to the full repo-relative path:
- `*` matches within one segment and never matches `/`.
- `**` matches zero or more whole segments.
- `?` matches one character other than `/`.
- A pattern has no implicit basename matching.

Each changed path is classified in this order:
1. It matches `GUARD_PATHS`: denied `policy_touched`.
2. It matches any architecture glob: denied `architecture`. This holds even
   when the path also matches a kind glob.
3. It matches no kind glob: denied `unclassified`.

A lane covers a path when at least one kind the path matches is listed in the
lane's `kinds`.

### P6 — Requester approval (owner decision D1)

Only reviews whose state is APPROVED, CHANGES_REQUESTED or DISMISSED decide
anything. COMMENTED never overrides. For each login in `requester_logins`,
take that login's latest deciding review by `submittedAt`.

The lane is satisfied when at least one listed login has a latest deciding
review that is APPROVED and whose `commit.oid` equals `headRefOid`. Labels and
records in any file count for nothing.

A lane whose `merge_reaches` is not `nothing` must list at least one
requester. Under RFC-0014 D1 that requester is the human at the merge.

### P7 — Deploy consistency and opt-ins (owner decision D2)

`merge_reaches` must equal what `deploy` implies:
- `production` when `production_on_merge` is true
- otherwise `preview` when `deploy.preview` is not `none`
- otherwise `nothing`

Opt-ins:
- `production` requires `allow_public_side_effect: true`.
- `preview` with `deploy.preview: public` requires
  `allow_public_side_effect: true`.
- Ceremony 3 is covered only when `max_ceremony: 3` is written explicitly.

### P8 — Ceremony and ride inputs

The ceremony level, the intake type and the STATE validation/review status
come from the same inputs `lane-gate.mjs --sweep-check` already uses:
- the flags `--spec`, `--intake` and `--state`
- the environment variables `AAI_SWEEP_SPEC`, `AAI_SWEEP_INTAKE` and
  `AAI_SWEEP_STATE`
- defaulting to STATE `current_focus`

The ceremony level follows canon: an absent field is level 2. A ride whose
spec and intake cannot be resolved counts as ceremony 3.

`exclude_roadmap_capability` denies when the ride's `ref_id` is a
`- capability:` entry in the base branch's roadmap.

### P9 — Hook lane path (byte-identical by construction)

The new path runs only when no `AAI_OPERATOR_MERGE=1` is present AND the
command is a `gh pr merge` AND a lane marker is present. A lane marker means:
- a variable whose name matches `^AAI_[A-Z0-9_]+_MERGE$` and is not
  `AAI_OPERATOR_MERGE`
- with the value `1`
- present either in the hook's environment or as a leading `NAME=1` assignment
  in the merge command segment

When no lane marker is present, the gate runs today's code, so it produces
today's bytes, whether or not a policy exists. When a lane marker is present,
the hook:
1. Resolves the PR exactly as gate 2b already does.
2. Runs `merge-policy.mjs --check`.
3. Allows the merge only when the result is `allowed` AND the allowed lane's
   own marker is among the markers that are set. The existing sweep check
   (gate 2b) still runs after that.

Any other outcome produces today's article-7 deny text plus one line,
`merge-policy: <verdict line>`, and exit 2. A missing node or a missing
evaluator also falls back to today's deny. The lane path can only ever add an
allow; it never turns today's deny into an allow on error.

### P10 — Output and exit contract

| outcome | stdout first line | exit |
|---|---|---|
| allowed | `MERGE-POLICY allowed pr=<n> lane=<id> marker=<NAME> decision_ref=<ref> merge_reaches=<v>` | 0 |
| denied | `MERGE-POLICY denied pr=<n> reason=<code>` then one `lane=<id> reason=<code>` line per lane evaluated | 3 |
| no policy at base | `MERGE-POLICY no_policy pr=<n>` | 4 |
| usage error | message on stderr | 2 |

The first lane in file order whose conditions all hold wins.
`--validate` prints `VALID lanes=<n>` and exits 0. On errors it prints one
`INVALID lane=<id or -> code=<code>` line per error and exits 1. An absent
file exits 4.

PR-level deny codes: `api_unavailable`, `pr_not_open`, `base_unavailable`,
`policy_invalid`, `policy_touched`, `architecture`, `unclassified`,
`ci_not_green`, `sweep_check_failed`, `no_lane_matched`.

Lane-level deny codes: `kind_not_in_lane`, `intake_type`,
`roadmap_capability`, `ceremony_exceeds`, `requester_approval_missing`,
`validation_not_pass`, `review_not_pass`, `pr_body_missing`.

Validate codes: `parse_error`, `unknown_key`, `missing_key`,
`duplicate_lane`, `undefined_kind`, `empty_globs`, `bad_marker`,
`duplicate_marker`, `decision_missing`, `decision_unsigned`,
`decision_ambiguous`, `signer_mismatch`, `reaches_inconsistent`,
`public_effect_not_opted_in`, `requester_missing`, `bad_ceremony`.

### P11 — Constitution article 7 (how the amendment is handled)

The amendment is a Spec-AC: Spec-AC-21 edits the text to v2. The constitution
says it is ratified "by merging the introducing PR", and this is a capability
ride at ceremony 3, so the owner merges it in any case under today's rule.
The owner's merge is therefore the ratification the constitution names. The
PR body must ask for that ratification explicitly (HITL-1). The spec does not
treat the amendment as a constitution deviation, because the constitution's
own amendment path is used.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: the scope changes the merge boundary (a guard), edits
  `docs/CONSTITUTION.md` (a protected L3 surface) and prompt corpus every
  session reads. `/Users/ales/Projects/aai` is shared by several live sessions,
  so the work must not run inline. The worktree must carry the live
  uncommitted inputs of this ride: the untracked RFC, the 2026-10-03 append to
  `docs/ai/decisions.jsonl` and the `docs/ai/roadmap.yaml` admission. They are
  not on `main` yet. Copy live STATE as well (LEARNED / memory
  "worktree-carry-live-state").
- User decision: undecided
- Base ref: main at 64f2595f
- Worktree branch/path: suggested `change/configurable-merge-policy-lanes` at `/Users/ales/Projects/aai-merge-policy`
- Inline review scope: .aai/scripts/merge-policy.mjs, .aai/scripts/claude-hook-gate.sh, .aai/scripts/aai-doctor.mjs, .aai/SKILL_PR.prompt.md, .aai/SKILL_SHIP.prompt.md, .aai/AGENTS.md, .aai/SKILL_DOCTOR.prompt.md, .aai/system/PROFILES.yaml, .aai/system/DOCS_AI_CANON.list, docs/CONSTITUTION.md, docs/ai/merge-policy.yaml, tests/skills/test-aai-merge-policy.sh, tests/skills/test-aai-hooks-overlay.sh, tests/skills/test-aai-doctor.sh, tests/skills/test-aai-constitution.sh, tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh, tests/skills/suite-map.yaml, CHANGELOG.md, docs/specs/SPEC-DRAFT-spec-configurable-merge-policy-lanes.md

## Implementation strategy
- Strategy: tdd
- Rationale: the owner chose full TDD at intake (D4; STATE
  `implementation_strategy.source: intake`). The scope is also a guard whose
  whole value lies in its denials. Every deny code and every validate code
  must be seen FAILING before its predicate exists. A guard that was never
  seen red on a forged approval, a head-branch policy or an architecture path
  proves nothing. Fixtures are real git repositories with a base and a head
  commit, plus a stub `gh` on PATH. There is never a network call.

## Implementation plan

The mutation column names these identifiers, so implementation must create
them under these names. If a name changes, the mutation cell is re-derived
and the change is disclosed.

`.aai/scripts/merge-policy.mjs` (new, Node stdlib only, core profile):
- `const POLICY_PATH = 'docs/ai/merge-policy.yaml'`
- `export const GUARD_PATHS = [...]` (P4)
- `const MARKER_RE = /^AAI_[A-Z0-9_]+_MERGE$/`
- `const DEFAULT_MAX_CEREMONY = 2`
- `const EXIT_ALLOWED = 0`, `const EXIT_DENIED = 3`, `const EXIT_NO_POLICY = 4`
- `function parsePolicy(text)`: closed shape, returns `{ policy }` or `{ errors }`
- `function validatePolicy(policy, decisionsText)`: P2 and P7, returns the validate codes
- `function readAtBase(root, oid, relPath)`: `git show <oid>:<relPath>`;
  returns `null` when the path is absent at that commit
- `function globToRegExp(glob)` (P5)
- `function classifyFiles(files, policy)`: guard paths first, then
  architecture, then kinds
- `function requesterApproved(reviews, logins, headOid)` (P6)
- `function ciGreen(rollup)`: rollup must not be empty. A CheckRun counts
  only when it is COMPLETED with conclusion SUCCESS, NEUTRAL or SKIPPED. A
  StatusContext counts only when its state is SUCCESS.
- `function runSweepCheck(root, pr, rideOpts)`: spawns
  `lane-gate.mjs --sweep-check`. Exit 5 maps to `sweep_check_failed`.
- `function evaluateLane(lane, ctx)`: lane-level codes, checked in the order
  listed in P10
- `--debug-inputs` (with `--check`): also prints the resolved ride inputs
  (`ceremony=<n> intake_type=<t> ref=<r>`), for the S2 seam test

Mandated source lines. The Test Plan mutations target these lines byte for
byte. If one is restructured, its mutation cell is re-derived and the change
is disclosed:
- `if (GUARD_PATHS.includes(f))` in `classifyFiles`
- `for (const a of policy.architecture)` in `classifyFiles`
- `globToRegExp` emits the literal `'[^/]*'` for a single star
- `execFileSync('git', ['show', oid + ':' + relPath]` in `readAtBase`
- `readAtBase(root, base, POLICY_PATH)` and
  `readAtBase(root, base, 'docs/ai/decisions.jsonl')` in the check path
- `r.commit && r.commit.oid === headOid` in `requesterApproved`
- `if (!Array.isArray(rollup)) return false;` then
  `if (rollup.length === 0) return false;` in `ciGreen`
- `if (rc === 5) return 'sweep_check_failed'` in `runSweepCheck`
- `if (lane.merge_reaches !== impliedReach)` and
  `lane.allow_public_side_effect !== true` in `validatePolicy`
- `if (hits.length > 1)` in the decision binder
- `errors.push({ lane: id, code: 'requester_missing' })` in `validatePolicy`
- `return 2; // canon: absent ceremony_level is implicit 2` in `readRideCeremony`
- `if (req.pr_body_contains && !body.includes(req.pr_body_contains))` in `evaluateLane`
- `if (pr.isDraft === true)` in the PR-state check
- `['pr', 'view', String(pr)` as the start of the single `gh` argv
- `for (const lane of policy.lanes)` in the lane loop
- `merge-policy.mjs" --check` in the hook's lane path

`.aai/scripts/claude-hook-gate.sh`: inside the `merge)` case, before the
existing `AAI_OPERATOR_MERGE` test, add `lane_markers_set` (environment scan
plus command-prefix scan). It runs only when the operator marker is not `1`.
The existing deny block is kept byte for byte and reused as the fallback.

`.aai/scripts/aai-doctor.mjs`: CAT-19 Merge Policy.
- Absent policy with no orphaned authorization: not reported.
- Absent policy with an orphaned authorization: WARN naming the orphaned
  record and the remedy (author a lane).
- Valid policy: PASS `lanes=<n>`.
- Invalid policy: WARN listing the codes.

The doctor reads the working-tree file, because doctor is an authoring
health check. `--check` alone is the merge-time authority.

Data flow at merge:
1. `gh pr view`
2. base reads
3. policy validity
4. PR state
5. classification
6. CI
7. sweep check
8. lanes in order
9. verdict

Edge cases: a PR touching zero files gets `unclassified` with path `-`. A
review whose `commit` is null is not at head. A flow list containing an empty
string gives `empty_globs`. A CRLF policy file is normalised before the parse.

## Acceptance Criteria Mapping
- Maps to: RFC Proposal items 1 to 5, the RFC's added design points, Risks, and owner decisions D1 to D4.
- Spec-AC-01..23 below. Each is verified by the TEST rows in the Test Plan.
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-policy.sh`, plus the named suites per row.

## Constitution deviations

- Article 7 (operator-only merge): AMENDED by this scope to v2, not deviated
  from. The amendment follows the constitution's own path: the version bumps
  and the owner re-ratifies by merging the introducing PR (P11, Spec-AC-21,
  HITL-1). Justification: owner decisions of 2026-10-03 and the RFC Approvals
  section, which names article 7.
- Article 5 (additive first): one explicit, documented breaking change. After
  sync, a downstream project that relied on the prose STANDING AUTHORIZATION
  and has no `docs/ai/merge-policy.yaml` loses that exception. Justification:
  the RFC requires one path, not two. The break is declared in CHANGELOG
  (Spec-AC-23), and doctor CAT-19 detects the orphaned authorization record
  by name and prints the remedy (Spec-AC-20).

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN the base commit carries no docs/ai/merge-policy.yaml THEN `merge-policy.mjs --check --pr N` prints `MERGE-POLICY no_policy pr=N` and exits 4, and `merge-policy.mjs --validate --path <absent file>` exits 4 | planned | — | — | default off |
| Spec-AC-02 | WHEN no lane marker is present THEN for the 8-payload merge matrix (git merge, gh pr merge with and without a number, each with and without AAI_OPERATOR_MERGE=1) the merge gate's stderr bytes and exit code equal those of the base-commit adapter, both with and without a policy file in the fixture | planned | — | — | byte-identical by construction (P9) |
| Spec-AC-03 | WHEN the policy or the decision record differs between the base commit and the head or working tree THEN `--check` decides from the base commit only: base absent plus permissive head gives no_policy; restrictive base plus permissive head gives denied; a decision record present only in head gives denied reason=policy_invalid with validate code decision_missing | planned | — | — | P3 self-grant defence |
| Spec-AC-04 | WHEN the PR diff adds, modifies or deletes any GUARD_PATHS entry THEN `--check` exits 3 with reason=policy_touched naming that path, even when every other condition holds; and GUARD_PATHS contains docs/ai/merge-policy.yaml, the evaluator, claude-hook-gate.sh, lane-gate.mjs and every lib module either script imports | planned | — | — | P4 |
| Spec-AC-05 | WHEN a changed path matches an architecture glob THEN `--check` exits 3 with reason=architecture even if a kind glob also matches; WHEN a path matches no kind glob THEN reason=unclassified; WHEN a kind file is renamed onto an architecture path THEN reason=architecture | planned | — | — | P5 closed world, D3 |
| Spec-AC-06 | `merge-policy.mjs --classify --path <policy> --files-from <list>` prints one `<path> <class>` line per input path and matches the P5 glob semantics on a 10-case fixture table: star stops at slash, double star spans zero or more segments, question mark is one non-slash character, no implicit basename match | planned | — | — | authoring aid and glob proof |
| Spec-AC-07 | WHEN a lane lists requester_logins THEN `--check` allows only when a listed login's latest deciding review is APPROVED at headRefOid; an unlisted approver, an approval on an older commit, an approval followed by CHANGES_REQUESTED or DISMISSED, and a label named approved with no review each give lane reason=requester_approval_missing; a later COMMENTED review does not revoke an approval | planned | — | — | D1 |
| Spec-AC-08 | WHEN statusCheckRollup is empty, or any entry is pending, failed or cancelled THEN `--check` exits 3 with reason=ci_not_green; WHEN every entry is SUCCESS, NEUTRAL or SKIPPED THEN CI does not block | planned | — | — | CI mandatory |
| Spec-AC-09 | WHEN `lane-gate.mjs --sweep-check` exits 5 for the PR THEN `--check` exits 3 with reason=sweep_check_failed; WHEN a policy carries a key that would disable CI or the sweep check THEN `--validate` exits 1 with code unknown_key | planned | — | — | sweep check mandatory, not configurable |
| Spec-AC-10 | WHEN a lane has merge_reaches production, or preview on a deploy.preview public repo, without allow_public_side_effect true THEN `--validate` exits 1 with code public_effect_not_opted_in and `--check` denies with reason=policy_invalid | planned | — | — | D2 opt-in |
| Spec-AC-11 | WHEN the ride's ceremony is 3 THEN a lane without max_ceremony gives lane reason=ceremony_exceeds and a lane with max_ceremony 3 passes; WHEN no spec or intake resolves THEN the ride counts as ceremony 3; on 4 fixture specs the level the evaluator reads equals the ceremony_level line lane-gate.mjs prints | planned | — | — | ceremony opt-in plus seam with lane-gate |
| Spec-AC-12 | WHEN a lane's merge_reaches disagrees with deploy (preview with deploy.preview none, nothing with production_on_merge true, production with production_on_merge false), or decision_ref resolves to zero, two, unsigned or other-actor records THEN `--validate` exits 1 printing reaches_inconsistent, decision_missing, decision_ambiguous, decision_unsigned or signer_mismatch respectively; a valid policy prints `VALID lanes=N` and exits 0 | planned | — | — | unsatisfiable lanes fail loudly |
| Spec-AC-13 | WHEN a lane marker fails MARKER_RE, equals AAI_OPERATOR_MERGE, or repeats another lane's marker THEN `--validate` exits 1 with bad_marker or duplicate_marker; an allowed verdict names the lane's own marker | planned | — | — | distinct marker per lane |
| Spec-AC-14 | WHEN the hook receives `gh pr merge N` with lane X's marker set (environment or leading NAME=1 assignment) and the evaluator allows lane X with a valid sweep record THEN exit 0; with no marker, with lane Y's marker, with an evaluator denial, or for `git merge` THEN exit 2 and stderr carries the article-7 text plus a merge-policy line naming the verdict | planned | — | — | P9, real evaluator and real lane-gate in fixture |
| Spec-AC-15 | WHEN a lane declares requires intake_types, exclude_roadmap_capability, validation_pass, review_pass or pr_body_contains THEN each unmet condition yields its own lane reason (intake_type, roadmap_capability, validation_not_pass, review_not_pass, pr_body_missing), and the fixture meeting all of them is allowed | planned | — | — | expresses the 2026-09-12 conditions |
| Spec-AC-16 | WHEN the PR is not OPEN or is a draft THEN reason=pr_not_open; WHEN gh is absent or exits non-zero THEN reason=api_unavailable with exit 3; WHEN baseRefOid or headRefOid is not a local object THEN reason=base_unavailable; across the whole suite the stub gh argv log contains only `pr view` invocations | planned | — | — | fail closed, no network |
| Spec-AC-17 | WHEN two lanes both hold THEN the allowed line names the first in file order; WHEN no lane holds THEN the first line is `MERGE-POLICY denied pr=N reason=no_lane_matched` followed by exactly one `lane=<id> reason=<code>` line per lane | planned | — | — | P10 output contract |
| Spec-AC-18 | This repository's docs/ai/merge-policy.yaml passes `--validate` with exit 0 and holds exactly one lane, id internal-standing, bound to wave-2-roadmap@2026-09-12T19:56:52Z with decision_match STANDING MERGE AUTHORIZATION, merge_reaches nothing, no max_ceremony, requires validation_pass, review_pass, pr_body_contains Residual, intake_types change issue techdebt hotfix, exclude_roadmap_capability true; in a fixture whose base carries that file, a conforming internal ride is allowed and a capability ride, a ceremony-3 ride, a validation fail, a body without Residual and a hooks path are each denied | planned | — | — | migration with identical conditions; mapping in Notes |
| Spec-AC-19 | `.aai/SKILL_PR.prompt.md` step 6 no longer contains the STANDING AUTHORIZATION paragraph or the string ref wave-2-roadmap, and instructs `node .aai/scripts/merge-policy.mjs --check --pr` with the lane marker and decision_ref citation; the TEST-012 literals (NEVER merge, AAI_OPERATOR_MERGE, guardrail, not a security boundary) survive; `.aai/AGENTS.md` closeout and `.aai/SKILL_SHIP.prompt.md` step 6 name merge-policy.mjs instead of standing authorization | planned | — | — | one path |
| Spec-AC-20 | `aai-doctor.mjs` reports CAT-19 Merge Policy: absent policy with no orphaned authorization is not reported; a valid policy is PASS with lanes=N; an invalid one is WARN naming its codes; an absent policy plus an owner-signed hitl_decision containing STANDING MERGE AUTHORIZATION is WARN naming the record and the remedy; `--json` carries CAT-19 | planned | — | — | discoverability and Article 5 mitigation |
| Spec-AC-21 | docs/CONSTITUTION.md article 7 names lane merges allowed by .aai/scripts/merge-policy.mjs under an owner-signed docs/ai/merge-policy.yaml as the sole sanctioned exception, still contains operator-only, and the ratification line reads v2, 2026-10-03; tests/skills/test-aai-constitution.sh exits 0 | planned | — | — | P11, HITL-1 |
| Spec-AC-22 | .aai/system/PROFILES.yaml lists .aai/scripts/merge-policy.mjs under core; .aai/system/DOCS_AI_CANON.list lists merge-policy.yaml; tests/skills/suite-map.yaml maps the evaluator and the new suite so select-suites.mjs prints no FULL_RUN for that path; the prompt-diet ledger carries an entry for this ref and TEST-012 is re-pinned; test-aai-layer-profiles.sh and test-aai-prompt-diet.sh exit 0 | planned | — | — | companion obligations |
| Spec-AC-23 | CHANGELOG.md carries a `## [unreleased] — ` heading for this capability whose body names docs/ai/merge-policy.yaml, merge-policy.mjs --validate, and the breaking removal of the prose standing authorization with its migration step | planned | — | — | Article 5 disclosure |

## Test Plan

TEST ids start at 1501. The gap after TEST-1440 is deliberate: another
planning session is open in parallel and may take the next ids.

All fixtures are scratch git repositories. They set their own `user.email` and
`user.name`, and the base commit is reachable as a real object. `gh` is a stub
on PATH that serves JSON from a fixture file and appends its argv to a log.
Suites run under `env -u AAI_ROLE`. Mutation cells are JS-regex `sed`
substitutions against the identifiers that the Implementation plan mandates.

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-1501 | Spec-AC-01 | integration | tests/skills/test-aai-merge-policy.sh | fixture base without policy: --check prints no_policy and exits 4; --validate on an absent path exits 4 | sed:s/const EXIT_NO_POLICY = 4/const EXIT_NO_POLICY = 3/ | green |
| TEST-1502 | Spec-AC-02 | integration | tests/skills/test-aai-hooks-overlay.sh | 8-payload matrix, stderr and rc captured from the adapter at the base commit (git show into scratch) and from the live adapter, with and without a policy file: byte-equal | sed:s/Merge denied: constitution article 7/Merge denied: article 7/ | pending |
| TEST-1503 | Spec-AC-03 | integration | tests/skills/test-aai-merge-policy.sh | base has no policy, head commit and working tree carry an allow-all policy: verdict no_policy | sed:s/readAtBase\(root, base, POLICY_PATH\)/readFileSync(join(root, POLICY_PATH), 'utf8')/ | green |
| TEST-1504 | Spec-AC-03 | integration | tests/skills/test-aai-merge-policy.sh | base policy has no lane covering docs, head widens it: verdict denied reason=no_lane_matched | sed:s/\['show', oid \+ ':' \+ relPath\]/['show', 'HEAD:' + relPath]/ | green |
| TEST-1505 | Spec-AC-03 | integration | tests/skills/test-aai-merge-policy.sh | decision record appended only in the head commit: denied reason=policy_invalid and stdout names decision_missing | sed:s/readAtBase\(root, base, 'docs\/ai\/decisions\.jsonl'\)/readFileSync(join(root, 'docs\/ai\/decisions.jsonl'), 'utf8')/ | green |
| TEST-1506 | Spec-AC-04 | integration | tests/skills/test-aai-merge-policy.sh | three PRs (add, modify, delete docs/ai/merge-policy.yaml) and one touching .aai/scripts/merge-policy.mjs, all else passing: each exits 3 with reason=policy_touched and the path | sed:s/if \(GUARD_PATHS\.includes\(f\)\)/if (false)/ | green |
| TEST-1507 | Spec-AC-04 | unit | tests/skills/test-aai-merge-policy.sh | GUARD_PATHS (read via node import) is a superset of the relative import closure of merge-policy.mjs and lane-gate.mjs plus claude-hook-gate.sh and the policy path | sed:s/'\.aai\/scripts\/lane-gate\.mjs',// | green |
| TEST-1508 | Spec-AC-05 | integration | tests/skills/test-aai-merge-policy.sh | Dockerfile matching both architecture and kind: architecture; src/x.bin matching nothing: unclassified; git mv of content file to Dockerfile: architecture | sed:s/for \(const a of policy\.architecture\)/for (const a of [])/ | pending |
| TEST-1509 | Spec-AC-06 | unit | tests/skills/test-aai-merge-policy.sh | 10-row glob table through --classify (a/b.md vs *.md, **/*.md at depth 0 and 3, src/** vs src, ? vs slash, literal dot) equals golden output | sed:s/\[\^\/\]\*/.*/ | pending |
| TEST-1510 | Spec-AC-07 | integration | tests/skills/test-aai-merge-policy.sh | six review fixtures: listed APPROVED at head allowed; unlisted, stale-commit, approve-then-changes-requested, approve-then-dismissed, label-only denied requester_approval_missing; approve-then-commented allowed | sed:s/r\.commit && r\.commit\.oid === headOid/true/ | pending |
| TEST-1511 | Spec-AC-08 | integration | tests/skills/test-aai-merge-policy.sh | rollup fixtures: empty, IN_PROGRESS, FAILURE, StatusContext PENDING each ci_not_green; SUCCESS plus NEUTRAL plus SKIPPED passes | sed:s/if \(rollup\.length === 0\) return false/if (rollup.length < 0) return false/ | pending |
| TEST-1512 | Spec-AC-09 | integration | tests/skills/test-aai-merge-policy.sh | no pr_sweep record in fixture EVENTS: sweep_check_failed; policy with requires ci false or sweep_check false: validate exit 1 unknown_key | sed:s/if \(rc === 5\) return 'sweep_check_failed'/if (rc === 5) return null/ | pending |
| TEST-1513 | Spec-AC-10 | integration | tests/skills/test-aai-merge-policy.sh | production lane without opt-in and public-preview lane without opt-in: validate exit 1 public_effect_not_opted_in; check denies policy_invalid; with opt-in both validate | sed:s/lane\.allow_public_side_effect !== true/false/ | pending |
| TEST-1514 | Spec-AC-11 | integration | tests/skills/test-aai-merge-policy.sh | ceremony-3 spec: lane without max_ceremony denied ceremony_exceeds, with max_ceremony 3 allowed; no spec and no intake resolvable: denied ceremony_exceeds | sed:s/const DEFAULT_MAX_CEREMONY = 2/const DEFAULT_MAX_CEREMONY = 3/ | pending |
| TEST-1515 | Spec-AC-11 | integration | tests/skills/test-aai-merge-policy.sh | four specs (levels 0, 2, 3, field absent): the level in merge-policy --check --debug-inputs equals the ceremony_level value printed by lane-gate.mjs for the same spec | sed:s/return 2; \/\/ canon: absent ceremony_level is implicit 2/return 3;/ | pending |
| TEST-1516 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | three deploy-inconsistent lanes each give reaches_inconsistent; a consistent policy prints VALID lanes=1 exit 0 | sed:s/if \(lane\.merge_reaches !== impliedReach\)/if (false)/ | pending |
| TEST-1517 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | decisions fixture: no match, two matches on shared ref and ts, owner_signoff false, other actor give decision_missing, decision_ambiguous, decision_unsigned, signer_mismatch | sed:s/if \(hits\.length > 1\)/if (hits.length > 99)/ | pending |
| TEST-1518 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | unknown key, duplicate lane id, undefined kind, empty globs, reaches preview without requester_logins: each its code, one INVALID line per error | sed:s/errors\.push\(\{ lane: id, code: 'requester_missing' \}\)/void 0/ | pending |
| TEST-1519 | Spec-AC-13 | unit | tests/skills/test-aai-merge-policy.sh | markers AAI_X_MERGE (valid), aai_x_merge, AAI_OPERATOR_MERGE, two lanes sharing one marker: bad_marker, bad_marker, duplicate_marker; allowed line names the lane marker | sed:s/const MARKER_RE = \/\^AAI_\[A-Z0-9_\]\+_MERGE\$\//const MARKER_RE = \/.\/ | pending |
| TEST-1520 | Spec-AC-14 | integration | tests/skills/test-aai-hooks-overlay.sh | fixture with base policy lane X, stub gh, valid pr_sweep: env marker X and prefix marker X allowed rc 0; no marker, marker Y, evaluator denial, git merge with marker X each rc 2 with article-7 text and a merge-policy line | sed:s/merge-policy\.mjs" --check/merge-policy.mjs" --chek/ | pending |
| TEST-1521 | Spec-AC-15 | integration | tests/skills/test-aai-merge-policy.sh | one fixture per requires key unmet (intake type rfc, ref listed as base roadmap capability, STATE last_validation fail, code_review fail, body lacking literal) gives its reason; all met is allowed | sed:s/if \(req\.pr_body_contains && !body\.includes\(req\.pr_body_contains\)\)/if (false)/ | pending |
| TEST-1522 | Spec-AC-16 | integration | tests/skills/test-aai-merge-policy.sh | state CLOSED, isDraft true, gh stub exit 1, gh absent from PATH, baseRefOid unknown object: pr_not_open, pr_not_open, api_unavailable, api_unavailable, base_unavailable, all exit 3 | sed:s/if \(pr\.isDraft === true\)/if (false)/ | pending |
| TEST-1523 | Spec-AC-16 | integration | tests/skills/test-aai-merge-policy.sh | after the whole suite, every argv line in the stub gh log starts with pr view | sed:s/\['pr', 'view', String\(pr\)/['api', 'repos', String(pr)/ | pending |
| TEST-1524 | Spec-AC-17 | integration | tests/skills/test-aai-merge-policy.sh | two satisfiable lanes: allowed names the first; reorder the file: names the other; three failing lanes: no_lane_matched plus exactly three lane lines | sed:s/for \(const lane of policy\.lanes\)/for (const lane of [...policy.lanes].reverse())/ | pending |
| TEST-1525 | Spec-AC-18 | integration | tests/skills/test-aai-merge-policy.sh | live docs/ai/merge-policy.yaml validates against the live decisions ledger (exit 0) and its single lane carries every field value Spec-AC-18 names | sed:s/decision_match: "STANDING MERGE AUTHORIZATION"/decision_match: "STANDING DECISION"/ | pending |
| TEST-1526 | Spec-AC-18 | integration | tests/skills/test-aai-merge-policy.sh | fixture base carries the live policy file plus the live wave-2 records: conforming internal ride allowed; capability ride, ceremony 3, validation fail, body without Residual, hooks path each denied with their reason | sed:s/exclude_roadmap_capability: true/exclude_roadmap_capability: false/ | pending |
| TEST-1527 | Spec-AC-19 | integration | tests/skills/test-aai-merge-policy.sh | grep -c ref wave-2-roadmap and STANDING AUTHORIZATION in SKILL_PR equal 0; SKILL_PR, AGENTS.md and SKILL_SHIP each name merge-policy.mjs; hooks TEST-012 literals present | sed:s/merge-policy\.mjs --check --pr/merge-policy.mjs --pr/ | pending |
| TEST-1528 | Spec-AC-20 | integration | tests/skills/test-aai-doctor.sh | fixtures: absent clean (no CAT-19 line), valid (PASS lanes=1), invalid (WARN with code), absent plus orphaned STANDING MERGE AUTHORIZATION record (WARN naming it); --json has id CAT-19 | sed:s/STANDING MERGE AUTHORIZATION/STANDING MERGE AUTH0RIZATION/ | pending |
| TEST-1529 | Spec-AC-21 | integration | tests/skills/test-aai-constitution.sh | article 7 line contains merge-policy.mjs and operator-only; ratification line contains v2, 2026-10-03; existing TEST-001..TEST-005 still pass | sed:s/v2, 2026-10-03/v1, 2026-07-16/ | pending |
| TEST-1530 | Spec-AC-22 | integration | tests/skills/test-aai-merge-policy.sh | PROFILES core list line, DOCS_AI_CANON.list line, suite-map maps the evaluator (select-suites on that one path prints no FULL_RUN and selects aai-merge-policy); layer-profiles suite exits 0 | sed:s/  - \.aai\/scripts\/merge-policy\.mjs/  - .aai\/scripts\/merge-policy-x.mjs/ | pending |
| TEST-1531 | Spec-AC-22 | integration | tests/skills/test-aai-prompt-diet.sh | JUSTIFIED_ADDITIONS carries an entry naming configurable-merge-policy-lanes and TEST-012 pin equals the new sum; suite exits 0 | sed:s/configurable-merge-policy-lanes/configurable-merge-policy-lanez/ | pending |
| TEST-1532 | Spec-AC-23 | unit | tests/skills/test-aai-merge-policy.sh | CHANGELOG has a line starting with the unreleased heading prefix whose entry body names merge-policy.yaml, --validate and the standing authorization removal | sed:s/merge-policy\.mjs --validate/merge-policy.mjs --check/ | pending |

RED observation plan: each row is first seen failing on the pre-change tree,
where the evaluator does not exist or the text is not yet written. The RED log
goes to `docs/ai/tdd/configurable-merge-policy-lanes-red-<TEST>.log`. GREEN is
then recorded after the change, and `mutation-run.mjs` records the mutation
under `docs/ai/tdd/spec-configurable-merge-policy-lanes/`.

TEST-1502 is RED-able because the pre-change adapter is the golden reference.
Its RED is observed by applying the mutation in a scratch copy. That test is a
regression guard, and its mutation is the evidence that it bites.

## Verification

Commands, in order (all from the worktree root):
1. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-policy.sh`: exit 0
2. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hooks-overlay.sh`: exit 0, and every pre-existing TEST passes unchanged
3. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-doctor.sh`: exit 0
4. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-constitution.sh`: exit 0
5. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh` and `test-aai-layer-profiles.sh`: exit 0
6. `node .aai/scripts/merge-policy.mjs --validate`: `VALID lanes=1`, exit 0
7. `node .aai/scripts/spec-lint.mjs --path <this spec>`: no errors
8. `node .aai/scripts/mutation-gate.mjs --spec <this spec>`: GATE PASS
9. `node .aai/scripts/docs-audit.mjs --check --strict`: clean, with no `docs_ai_noncanon` for merge-policy.yaml
10. Full framework sweep before close, with `AAI_TEST_TIMEOUT=3000`

PASS criteria: all TEST-xxx green AND all Spec-AC terminal.

## Evidence contract

The strategy is `tdd`. Each AC-gating test owes a stored RED artifact under
`docs/ai/tdd/` plus the full verification matrix. Each artifact records:
- ref_id `configurable-merge-policy-lanes`
- the Spec-AC and the TEST-xxx
- the command
- the exit code
- the evidence path
- the commit SHA or diff range

Spec-AC-18 is a claim about the live ledger and the live policy file.
TEST-1525 runs against the live files, not a copy. Spec-AC-02's golden is
regenerated from the base commit on every run and never committed, so it
cannot drift from the code it pins.

## Seams this change crosses

| Seam | What it touches | Reader that must not break | Test |
|---|---|---|---|
| S1 | evaluator calls lane-gate.mjs --sweep-check | the existing sweep record predicate and its exit 5 | TEST-1512, TEST-1520 |
| S2 | ceremony level read for a ride | lane-gate.mjs readCeremonyLevel; both must agree | TEST-1515 |
| S3 | hook merge gate gains a lane path | every existing hooks-overlay TEST and the golden bytes | TEST-1502, TEST-1520 |
| S4 | base-branch reads of decisions.jsonl and roadmap.yaml | the same ledgers routine-emit and ride-select read; read-only here | TEST-1505, TEST-1521 |
| S5 | SKILL_PR step 6 text | hooks TEST-012 literals; SKILL_SHIP and AGENTS pointers | TEST-1527 |
| S6 | docs/ai/ inventory | docs-audit docs_ai_noncanon class | TEST-1530, Verification step 9 |
| S7 | prompt corpus bytes | prompt-diet TEST-010 and TEST-012 | TEST-1531 |
| S8 | the live policy and the live 2026-09-12 record | this repository's own merges after delivery | TEST-1525, TEST-1526 |

No automated test crosses the GitHub server itself. The real `gh pr view`
JSON shape (field names `reviews[].commit.oid`, `statusCheckRollup[].conclusion`)
is pinned by fixtures only. See R1.

## Registry items closed by this scope

none. `follow-ups.mjs list` was scanned for merge, lane, hook, operator,
marker, authorization and constitution. The only item on a touched subject
is `fu-lanegate-readstate-duplicate` (collapse two STATE readers in
lane-gate.mjs). This scope does not edit lane-gate.mjs; it only spawns it.
That item stays open with its own owner.

## Residual risks

- R1: the `gh pr view --json` field shapes are pinned by fixtures, not by a
  live call. A GitHub CLI change to `reviews[].commit` fails closed
  (approval missing, deny), never open.
- R2: globs classify paths, not semantics (owner decision D3). A restyle
  that adds a script tag calling a new external service passes as design.
  The content tripwire is a suggested follow-up.
- R3: the evaluator runs from the checked-out tree. A PR that rewrites the
  evaluator is denied by GUARD_PATHS only if the evaluator that runs is the
  honest one. Markers and the evaluator are guardrails against habit, not a
  security boundary. Server-side branch protection remains the only boundary.
- R4: `intake_types`, the validation/review status in STATE, and the sweep
  record are agent-written inputs. This is the same trust the 2026-09-12
  prose exception already placed in them, so it is not a regression. The
  requester approval in public lanes is the one input the agent cannot write
  (D1).
- R5: today's operator marker `AAI_OPERATOR_MERGE` is read only from the hook
  process environment. A `NAME=1` prefix on the Bash command never reaches a
  hook process. Lane markers accept both forms (P9). The operator marker is
  left unchanged so the no-policy bytes stay identical.
  suggested: `fu-operator-marker-invisible-to-hook`.
- R6: the local `baseRefOid` object may be older than the server's base tip
  between fetches. The evaluator reads the policy at the oid the API names
  and denies `base_unavailable` when that object is missing. It never reads a
  stale branch name.
- R7: the migrated lane expresses "internal ride" as intake type plus
  "not a roadmap capability". In this repository, roadmap rule 4 puts every
  capability on the roadmap. A `change`-type capability that bypassed the
  roadmap would not be caught by the lane. The 2026-09-12 judgement "no
  behaviour visible to downstream consumers" has no path form beyond the
  architecture globs (HITL-2).

## HITL items for the owner (answered at the merge checkpoint, not blocking planning)

- HITL-1: ratify constitution article 7 v2 by merging this PR. The PR body
  must say so in one line.
- HITL-2: confirm that the migrated lane `internal-standing` matches the
  2026-09-12 authorization. The mapping is in Notes. Two differences need
  confirmation. First, an intentional tightening: a ride that edits
  GUARD_PATHS now goes to the operator. Second, the "behaviour visible to
  downstream consumers" judgement is reduced to architecture globs: `hooks/**`,
  `install.sh`, `install.ps1`, `.aai/scripts/install-pre-commit-hook.*`,
  `.aai/scripts/aai-sync.*`, `.github/**`.

## Notes

Mapping of the 2026-09-12 prose conditions to lane `internal-standing`:

| prose condition | lane field |
|---|---|
| internal ride: fix, chore, guard, harness, test | requires.intake_types [change, issue, techdebt, hotfix] plus exclude_roadmap_capability true |
| ceremony 2 or below; ceremony 3 never | max_ceremony absent (2) |
| validation and code review recorded pass | requires.validation_pass, requires.review_pass |
| CI fully green on the final head | mandatory, not configurable |
| every bot thread answered and resolved | mandatory sweep check (threads_unresolved must be 0 on a swept record) |
| residuals disclosed in the PR body | requires.pr_body_contains "Residual" |
| capability ride never | exclude_roadmap_capability true |
| public or external side effect never; the ref-guard ride excluded | merge_reaches nothing, allow_public_side_effect false, consumer-facing architecture globs |
| release never | intake_types excludes release |

Kinds for this repository: one kind, `repo`, with globs `["**"]`. The
architecture list and GUARD_PATHS are what bound the lane.

Suggested follow-ups (not filed):
- `suggested: fu-merge-policy-content-tripwire`: owner decision D3 deferral
- `suggested: fu-operator-marker-invisible-to-hook`: R5
