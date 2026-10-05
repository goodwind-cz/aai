---
id: spec-configurable-merge-policy-lanes
type: spec
number: 207
status: done
mutation_gate: v1
frozen_sha256: 88a29053f1339bf4bdabed642f29e0861f064f2d380420514b6d640fed3e6076
ceremony_level: 3
links:
  requirement: null
  rfc: docs/rfc/RFC-0015-configurable-merge-policy-lanes.md
  intake: docs/rfc/RFC-0015-configurable-merge-policy-lanes.md
  pr:
    - TBD
  commits:
    - bcdc1077e45683416b097945ab6e11cd1fd557f0
---

# Spec — An owner-signed merge policy decides which pull requests the agent may merge

SPEC-FROZEN: true

## Links
- Requirement: RFC `configurable-merge-policy-lanes` (accepted), docs/rfc/RFC-0015-configurable-merge-policy-lanes.md
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
    globs: [Dockerfile, "**/Dockerfile", "**/docker-compose*.yml"]
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
      pr_body_contains: Residual
```

Any key outside this shape is `unknown_key` and makes the policy invalid.
That includes any key that would switch off CI or the sweep check. Those two
checks are not configurable.
Every list is written in flow style (`[a, b]`). Quoting follows the one
canonical rule below.
A list-typed key (`kinds`, `requester_logins`, `requires.intake_types`, a
kind's or architecture entry's `globs`) accepts ONLY a well-formed `[...]`
flow list: a bare scalar, an unclosed list, or a quoted string that merely
looks like one (`"[a]"` is the STRING `[a]`, not a list) is `parse_error`,
never silently read as a one-element list or dropped so the condition it
names is skipped (validation-round2 R2-B2). An explicitly empty `[]` list
parses; it is not itself an error (it fails closed at evaluation instead —
an empty `requires.intake_types` matches no ride). `requires.pr_body_contains`
is a scalar and must be a non-empty string; an empty needle is `parse_error`
too (`"".includes("")` is true for every body, so an empty needle would
never deny).

A block-introducing key (`deploy`, `architecture`, `kinds`, `lanes`, a
lane's `requires`) carries its content ONLY on the indented lines that
follow it; nothing after its own colon is ever read, so any text there is
`parse_error` (validation-round3 R3-B1, made explicit in remediation round
5) — except an explicit empty collection (`[]` or `{}`), which parses as
zero entries and must then have NO indented children: `lanes: []` or
`kinds: []` followed by entries is `parse_error` (validation-round4
R4-B1b). A SCALAR-typed key (`version`, an `id`, `deploy.preview`,
`decision_ref`, `decision_match`, `signed_by`, `marker`, `max_ceremony`,
`merge_reaches`, `requires.pr_body_contains`) whose value starts with `[` or
`{` is `parse_error`, never read as a list (validation-round4 R4-B1a:
`marker: [X]` dodged `duplicate_marker`). Every architecture or kind entry
is `id` plus `globs`; an entry with no `globs` line at all is
`missing_key`. A flow list's own comma split never crosses a quote
boundary: a trailing bracket pair (`[a] [b]`) or a literal comma inside
quotes (`["a,b"]`) is `parse_error` (validation-round3 NB-3).

**Textual canonical form (owner decision 2026-10-04, remediation round 5).**
These per-shape rules are defense in depth. The structural rule is
textual: the policy is valid only if

    textualNormalize(raw) === canonicalText(parsePolicy(raw))

line by line, in order. `textualNormalize` works on the RAW file text only,
never on a parsed value: it strips one leading BOM, turns CRLF into LF,
drops full-line comments (first non-space/tab character `#`), drops a
trailing comment only where `#` is outside quotes AND preceded by an ASCII
space or tab (never another Unicode space — validation-round4 NB-1), strips
trailing ASCII spaces/tabs, and drops blank lines. Nothing else: no
re-quoting, no reflowing, no indentation change. `canonicalText` is one
deterministic emitter from the parsed policy object, driven by each key's
schema type (a list-typed key always emits a list, a scalar-typed key always
a scalar):
- fixed key order: version, deploy, architecture, kinds, lanes; deploy
  preview, production_on_merge; an entry `- id:` then `globs:`; a lane
  `- id:` then decision_ref, decision_match, signed_by, kinds, merge_reaches,
  allow_public_side_effect, max_ceremony, marker, requester_logins, requires;
  requires intake_types, exclude_roadmap_capability, validation_pass,
  review_pass, pr_body_contains;
- two-space indentation, `key: value` with one space after the colon, a
  block header as the bare `key:`;
- an optional key only when written; an EMPTY block is spelled by omitting
  it (`lanes:` with no entries, `lanes: []`, `deploy: {}`, an empty
  `requires:` are all noncanonical);
- booleans bare `true`/`false`; integers bare decimal;
- strings, the ONE quoting rule: bare when the string matches
  `^[A-Za-z_][A-Za-z0-9_./@:+-]*$`, does not end in `:`, and is not a YAML
  reserved word (true, false, yes, no, on, off, y, n, null, any case);
  otherwise wrapped in double quotes, verbatim. Single quotes are never
  canonical. A string containing `"`, `\` or a control character has no
  canonical spelling and is `parse_error`;
- every list in flow style on one line, `[a, b]` — items by the string rule,
  separated by `, `; the empty list is `[]`;
- no comments.

Any difference is `noncanonical line=<n>`, `n` being the first differing
line of the raw file (one past its last line when the canonical text is
longer); `--check` then denies `policy_invalid`. This makes every
misreading visible by construction: if the parser reads `marker: [X]` as
`X`, it emits `marker: X`, which is not the file's `marker: [X]`. Comments
and blank lines stay free. `merge-policy.mjs --canonical [--path <file>]`
prints the canonical text of any policy the parser can read (exit 0; exit 1
on a parse-time error; 4 when the file is absent) so an owner can copy it;
a noncanonical `--validate`/`--check` names that command on stderr, and
doctor CAT-19 names it in its WARN.

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
lane's `kinds`. A lane is eligible only when it covers EVERY changed path —
coverage is judged per path, never over the PR's union of matched kinds, so
one qualifying file can never drag an otherwise-uncovered path through a
narrow lane. `evaluateLane` denies on the first changed path (diff order) a
lane does not cover, reason `kind_not_in_lane`, naming that path (P10).
(code review B1, round 7 remediation, disclosed via spec-amend.mjs — the
per-path rule above was already written; this closes the gap that had no
Spec-AC row pinning it as a PR-level consequence.)

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
1. Checks the `gh pr merge` segment itself against a fixed ALLOW-LIST
   (validation-round2 R2-B1: a deny-list keyed on flag spelling is bypassed
   by quoting a flag, or by gh's own `--flag=value` parsing of
   `--admin`/`--auto` as real boolean flags — neither spelling ever matched
   a deny regex looking for the bare word). Any quote character, backslash,
   or `=` inside a token refuses outright. Past `gh pr merge`, the ONLY
   tokens permitted are: one bare PR number, one of
   `--squash`/`--merge`/`--rebase`, an optional `--delete-branch`, and
   exactly one `--match-head-commit <value>` — each at most once. Every
   other token (`--auto`, `--admin`, `-R`/`--repo`, a URL, a second
   `--match-head-commit`, or any future flag not on this list) refuses. This
   is the one and only gate for `--auto`/`--admin` (validation-round1 NB-1)
   and for an other-repository `-R`/`--repo` target or URL — one allow-list,
   not a deny-list per bypass shape found.
2. Resolves the PR exactly as gate 2b already does, then resolves that PR's
   current head (`gh pr view <n> --json headRefOid`) and requires the command
   to carry `--match-head-commit <that head>` — so the merge can only ever
   land the exact head this invocation is about to judge, never a later push.
3. Runs `merge-policy.mjs --check`.
4. Allows the merge only when the result is `allowed` AND the allowed lane's
   own marker is among the markers that are set. The existing sweep check
   (gate 2b) still runs after that.

Any other outcome produces today's article-7 deny text plus one line,
`merge-policy: <verdict line>`, and exit 2. A missing node, gh or a missing
evaluator also falls back to today's deny. The lane path can only ever add an
allow; it never turns today's deny into an allow on error.

### P10 — Output and exit contract

| outcome | stdout first line | exit |
|---|---|---|
| allowed | `MERGE-POLICY allowed pr=<n> lane=<id> marker=<NAME> decision_ref=<ref> merge_reaches=<v>` | 0 |
| denied | `MERGE-POLICY denied pr=<n> reason=<code>` then one `lane=<id> reason=<code>` line per lane evaluated (a `kind_not_in_lane` line carries ` path=<p>`, the first changed path that lane does not cover) | 3 |
| no policy at base | `MERGE-POLICY no_policy pr=<n>` | 4 |
| usage error | message on stderr | 2 |

The first lane in file order whose conditions all hold wins.
`--validate` prints `VALID lanes=<n>` and exits 0. On errors it prints one
`INVALID lane=<id or -> code=<code>` line per error and exits 1 (a
`noncanonical` one carries ` line=<n>`). An absent file exits 4.
`--canonical` prints the P1 canonical text and exits 0, or the INVALID
lines and exits 1 on a parse-time error.

PR-level deny codes: `api_unavailable`, `pr_not_open`, `base_unavailable`,
`policy_invalid`, `policy_touched`, `architecture`, `unclassified`,
`ci_not_green`, `sweep_check_failed`, `no_lane_matched`.

Lane-level deny codes: `kind_not_in_lane`, `intake_type`,
`roadmap_unreadable`, `roadmap_capability`, `ceremony_exceeds`,
`requester_approval_missing`, `validation_not_pass`, `review_not_pass`,
`pr_body_missing`. (`roadmap_unreadable` added by the round-7 remediation
amendment below — code review N2 had already implemented it at
`evaluateLane`'s `exclude_roadmap_capability` check; this closes the P10
listing gap, a disclosed doc fix with no behavior change.)

Validate codes: `parse_error`, `unknown_key`, `missing_key`, `duplicate_key`,
`duplicate_lane`, `undefined_kind`, `empty_globs`, `bad_marker`,
`duplicate_marker`, `decision_missing`, `decision_unsigned`,
`decision_ambiguous`, `signer_mismatch`, `reaches_inconsistent`,
`public_effect_not_opted_in`, `requester_missing`, `bad_ceremony`,
`noncanonical` (P1 textual canonical form).
`duplicate_key` is a repeated top-level key, a repeated `deploy`/`requires`
sub-key, or a repeated lane key (including a second `requires:` block) —
validation-round1 B2, disclosed via `spec-amend.mjs`.

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
- Inline review scope: .aai/scripts/merge-policy.mjs, .aai/scripts/claude-hook-gate.sh, .aai/scripts/aai-doctor.mjs, .aai/SKILL_PR.prompt.md, .aai/SKILL_SHIP.prompt.md, .aai/AGENTS.md, .aai/SKILL_DOCTOR.prompt.md, .aai/system/PROFILES.yaml, .aai/system/DOCS_AI_CANON.list, docs/CONSTITUTION.md, docs/ai/merge-policy.yaml, tests/skills/test-aai-merge-policy.sh, tests/skills/test-aai-hooks-overlay.sh, tests/skills/test-aai-doctor.sh, tests/skills/test-aai-constitution.sh, tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh, tests/skills/suite-map.yaml, CHANGELOG.md, docs/specs/SPEC-0207-spec-configurable-merge-policy-lanes.md

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
| Spec-AC-01 | WHEN the base commit carries no docs/ai/merge-policy.yaml THEN `merge-policy.mjs --check --pr N` prints `MERGE-POLICY no_policy pr=N` and exits 4, and `merge-policy.mjs --validate --path <absent file>` exits 4 | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1501.log TEST-1501 mutation-gate PASS | — | default off |
| Spec-AC-02 | WHEN no lane marker is present THEN for the 8-payload merge matrix (git merge, gh pr merge with and without a number, each with and without AAI_OPERATOR_MERGE=1) the merge gate's stderr bytes and exit code equal those of the base-commit adapter, both with and without a policy file in the fixture | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1502.log TEST-1502 mutation-gate PASS | — | byte-identical by construction (P9) |
| Spec-AC-03 | WHEN the policy or the decision record differs between the base commit and the head or working tree THEN `--check` decides from the base commit only: base absent plus permissive head gives no_policy; restrictive base plus permissive head gives denied; a decision record present only in head gives denied reason=policy_invalid with validate code decision_missing | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1503.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1504.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1505.log TEST-1503 TEST-1504 TEST-1505 mutation-gate PASS | — | P3 self-grant defence |
| Spec-AC-04 | WHEN the PR diff adds, modifies or deletes any GUARD_PATHS entry THEN `--check` exits 3 with reason=policy_touched naming that path, even when every other condition holds; and GUARD_PATHS contains docs/ai/merge-policy.yaml, the evaluator, claude-hook-gate.sh, lane-gate.mjs and every lib module either script imports | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1506.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1507.log TEST-1506 TEST-1507 mutation-gate PASS | — | P4 |
| Spec-AC-05 | WHEN a changed path matches an architecture glob THEN `--check` exits 3 with reason=architecture even if a kind glob also matches; WHEN a path matches no kind glob THEN reason=unclassified; WHEN a kind file is renamed onto an architecture path THEN reason=architecture; a lane is eligible only when it covers EVERY changed path (P5 amendment, round 7); getChangedFiles reads git's real path bytes via `-z`, never a C-quoted/escaped form | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1508.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1569-1571.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1572-1573.log docs/ai/tdd/configurable-merge-policy-lanes-red-TEST-1569.log docs/ai/tdd/configurable-merge-policy-lanes-red-TEST-1570.log docs/ai/tdd/configurable-merge-policy-lanes-red-TEST-1572.log docs/ai/tdd/configurable-merge-policy-lanes-red-TEST-1573.log TEST-1508 TEST-1569 TEST-1570 TEST-1572 TEST-1573 mutation-gate PASS | — | P5 closed world, D3; round 7 B1/B2 remediation closes the per-path-coverage and real-bytes gaps; validation round 8 V8-B1 remediation adds globToRegExp's dotAll flag (TEST-1572) and escapes a printed path's line terminators so a denial stays one line (TEST-1573) |
| Spec-AC-06 | `merge-policy.mjs --classify --path <policy> --files-from <list>` prints one `<path> <class>` line per input path and matches the P5 glob semantics on a 10-case fixture table: star stops at slash, double star spans zero or more segments, question mark is one non-slash character, no implicit basename match | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1509.log TEST-1509 mutation-gate PASS | — | authoring aid and glob proof |
| Spec-AC-07 | WHEN a lane lists requester_logins THEN `--check` allows only when a listed login's latest deciding review is APPROVED at headRefOid; an unlisted approver, an approval on an older commit, an approval followed by CHANGES_REQUESTED or DISMISSED, and a label named approved with no review each give lane reason=requester_approval_missing; a later COMMENTED review does not revoke an approval | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1510.log TEST-1510 mutation-gate PASS | — | D1 |
| Spec-AC-08 | WHEN statusCheckRollup is empty, or any entry is pending, failed or cancelled THEN `--check` exits 3 with reason=ci_not_green; WHEN every entry is SUCCESS, NEUTRAL or SKIPPED THEN CI does not block | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1511.log TEST-1511 mutation-gate PASS | — | CI mandatory |
| Spec-AC-09 | WHEN `lane-gate.mjs --sweep-check` exits 5 for the PR THEN `--check` exits 3 with reason=sweep_check_failed; WHEN a policy carries a key that would disable CI or the sweep check THEN `--validate` exits 1 with code unknown_key | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1512.log TEST-1512 mutation-gate PASS | — | sweep check mandatory, not configurable |
| Spec-AC-10 | WHEN a lane has merge_reaches production, or preview on a deploy.preview public repo, without allow_public_side_effect true THEN `--validate` exits 1 with code public_effect_not_opted_in and `--check` denies with reason=policy_invalid | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1513-20261003T224513Z.log TEST-1513 mutation-gate PASS | — | D2 opt-in |
| Spec-AC-11 | WHEN the ride's ceremony is 3 THEN a lane without max_ceremony gives lane reason=ceremony_exceeds and a lane with max_ceremony 3 passes; WHEN no spec or intake resolves THEN the ride counts as ceremony 3; on 4 fixture specs the level the evaluator reads equals the ceremony_level line lane-gate.mjs prints | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1514.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1515.log TEST-1514 TEST-1515 mutation-gate PASS | — | ceremony opt-in plus seam with lane-gate |
| Spec-AC-12 | WHEN a lane's merge_reaches disagrees with deploy (preview with deploy.preview none, nothing with production_on_merge true, production with production_on_merge false), or decision_ref resolves to zero, two, unsigned or other-actor records THEN `--validate` exits 1 printing reaches_inconsistent, decision_missing, decision_ambiguous, decision_unsigned or signer_mismatch respectively; a valid policy prints `VALID lanes=N` and exits 0; an inline flow value on a block header (deploy, architecture, kinds, lanes) is parse_error, never a silently-empty block; an empty-collection header (`[]`/`{}`) with indented children is parse_error (validation-round4 R4-B1b); a `[`/`{` value on a scalar-typed key is parse_error (R4-B1a); and the policy is valid only when its textually normalized text equals the canonical text emitted from the parsed values, line by line in order, else noncanonical line=N -- an equivalent respelling (quoted vs bare, empty block) is noncanonical; `--canonical` prints the canonical text (P1 textual canonical form, remediation round 5) | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1516-20261003T224514Z.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1517-20261003T224514Z.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1518-20261003T224514Z.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1545-1546-1547-1548.log docs/ai/tdd/configurable-merge-policy-lanes-red-TEST-1545-1546-1548.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1550-1558.log docs/ai/tdd/configurable-merge-policy-lanes-red-TEST-1550-1557.log TEST-1516 TEST-1517 TEST-1518 TEST-1534 TEST-1545 TEST-1547 TEST-1548 TEST-1552 TEST-1553 TEST-1555 TEST-1556 TEST-1557 mutation-gate PASS | — | unsatisfiable lanes fail loudly; round 5 replaces the round-4 round-trip with the textual canonical form (owner decision 2026-10-04) |
| Spec-AC-13 | WHEN a lane marker fails MARKER_RE, equals AAI_OPERATOR_MERGE, or repeats another lane's marker THEN `--validate` exits 1 with bad_marker or duplicate_marker; a marker spelled as a list (`marker: [X]`) is parse_error, never a value that dodges duplicate_marker (validation-round4 R4-B1a); an allowed verdict names the lane's own marker | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1519-20261003T224514Z.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1550-1558.log docs/ai/tdd/configurable-merge-policy-lanes-red-TEST-1550-1557.log TEST-1519 TEST-1550 mutation-gate PASS | — | distinct marker per lane; R4-B1a list-spelled marker |
| Spec-AC-14 | WHEN the hook receives `gh pr merge N` with lane X's marker set (environment or leading NAME=1 assignment) and the evaluator allows lane X with a valid sweep record THEN exit 0; with lane Y's marker, with an evaluator denial, or for `git merge` with a lane marker THEN exit 2 and stderr carries the article-7 text plus a merge-policy line naming the verdict; with no marker THEN exit 2 with the article-7 text and no merge-policy line (byte-identical per Spec-AC-02); the merge segment's own tokens are allow-listed, so no --flag=value or quoted spelling of a refused flag ever reaches gh; the segment must also carry an explicit PR number -- the branch-implicit form (no number) is refused (validation-round3 NB-1) | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1520.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1542.log docs/ai/tdd/configurable-merge-policy-lanes-red-TEST-1542.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1549.log docs/ai/tdd/configurable-merge-policy-lanes-red-TEST-1549.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1550-1558.log docs/ai/tdd/configurable-merge-policy-lanes-red-TEST-1551.log TEST-1520 TEST-1542 TEST-1549 TEST-1551 mutation-gate PASS | — | P9, real evaluator and real lane-gate in fixture; R2-B1 allow-list; NB-1 explicit PR number; R4-B1a hook denies a list-spelled-marker policy |
| Spec-AC-15 | WHEN a lane declares requires intake_types, exclude_roadmap_capability, validation_pass, review_pass or pr_body_contains THEN each unmet condition yields its own lane reason (intake_type, roadmap_capability, validation_not_pass, review_not_pass, pr_body_missing), and the fixture meeting all of them is allowed; a list-typed requires key (intake_types) or lane key (kinds, requester_logins) that is a scalar, unclosed or quoted-pseudo-list is parse_error, never silently dropped; a lane's `requires: {...}` written inline on its own header is parse_error for the same reason; a `#` preceded by a non-ASCII space (U+FEFF, NBSP) never starts a comment (validation-round4 NB-1); an architecture/kind entry with no `globs` line is missing_key; a flow list's own malformed item (a trailing bracket pair, a literal comma inside quotes) is parse_error, never silently narrowed (validation-round3 R3-B1/NB-3) | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1521.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1543-1544.log docs/ai/tdd/configurable-merge-policy-lanes-red-TEST-1543-1544.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1545-1546-1547-1548.log docs/ai/tdd/configurable-merge-policy-lanes-red-TEST-1545-1546-1548.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1550-1558.log docs/ai/tdd/configurable-merge-policy-lanes-red-TEST-1550-1557.log TEST-1521 TEST-1543 TEST-1544 TEST-1545 TEST-1546 TEST-1554 mutation-gate PASS | — | expresses the 2026-09-12 conditions; R2-B2 closed-shape list parsing; R3-B1/NB-3 tokenizer folds; R4 NB-1 ASCII-only comment start |
| Spec-AC-16 | WHEN the PR is not OPEN or is a draft THEN reason=pr_not_open; WHEN gh is absent or exits non-zero THEN reason=api_unavailable with exit 3; WHEN baseRefOid or headRefOid is not a local object THEN reason=base_unavailable; across the whole suite the stub gh argv log contains only `pr view` invocations | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1522.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1523.log TEST-1522 TEST-1523 mutation-gate PASS | — | fail closed, no network |
| Spec-AC-17 | WHEN two lanes both hold THEN the allowed line names the first in file order; WHEN no lane holds THEN the first line is `MERGE-POLICY denied pr=N reason=no_lane_matched` followed by exactly one `lane=<id> reason=<code>` line per lane | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1524.log TEST-1524 mutation-gate PASS | — | P10 output contract |
| Spec-AC-18 | This repository's docs/ai/merge-policy.yaml passes `--validate` with exit 0 and holds exactly one lane, id internal-standing, bound to wave-2-roadmap@2026-09-12T19:56:52Z with decision_match STANDING MERGE AUTHORIZATION, merge_reaches nothing, no max_ceremony, requires validation_pass, review_pass, pr_body_contains Residual, intake_types change issue techdebt hotfix, exclude_roadmap_capability true; in a fixture whose base carries that file, a conforming internal ride is allowed and a capability ride, a ceremony-3 ride, a validation fail, a body without Residual and a hooks path are each denied | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1525-1526-1527.log TEST-1525 TEST-1526 mutation-gate PASS | — | migration with identical conditions; mapping in Notes |
| Spec-AC-19 | `.aai/SKILL_PR.prompt.md` step 6 no longer contains the STANDING AUTHORIZATION paragraph or the string ref wave-2-roadmap, and instructs `node .aai/scripts/merge-policy.mjs --check --pr` with the lane marker and decision_ref citation; the TEST-012 literals (NEVER merge, AAI_OPERATOR_MERGE, guardrail, not a security boundary) survive; `.aai/AGENTS.md` closeout and `.aai/SKILL_SHIP.prompt.md` step 6 name merge-policy.mjs instead of standing authorization; the documented `gh pr merge <n> --squash --match-head-commit <headRefOid>` command carries the PR number the hook's allow-list requires (N7 remediation, round 7) | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1525-1526-1527.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1569-1571.log docs/ai/tdd/configurable-merge-policy-lanes-red-TEST-1571.log TEST-1527 TEST-1571 mutation-gate PASS | — | one path; N7 closed by naming the PR number the hook already required |
| Spec-AC-20 | `aai-doctor.mjs` reports CAT-19 Merge Policy: absent policy with no orphaned authorization is not reported; a valid policy is PASS with lanes=N; an invalid one is WARN naming its codes, and a noncanonical one also names `merge-policy.mjs --canonical`; an absent policy plus an owner-signed hitl_decision containing STANDING MERGE AUTHORIZATION is WARN naming the record and the remedy; `--json` carries CAT-19 | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1528.log docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1550-1558.log docs/ai/tdd/configurable-merge-policy-lanes-red-TEST-1558.log TEST-1528 TEST-1558 mutation-gate PASS | — | discoverability and Article 5 mitigation |
| Spec-AC-21 | docs/CONSTITUTION.md article 7 names lane merges allowed by .aai/scripts/merge-policy.mjs under an owner-signed docs/ai/merge-policy.yaml as the sole sanctioned exception, still contains operator-only, and the ratification line reads v2, 2026-10-03; tests/skills/test-aai-constitution.sh exits 0 | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1529.log TEST-1529 mutation-gate PASS | — | P11, HITL-1: the PR body must ask the owner to ratify by merging |
| Spec-AC-22 | .aai/system/PROFILES.yaml lists .aai/scripts/merge-policy.mjs under core; .aai/system/DOCS_AI_CANON.list lists merge-policy.yaml; tests/skills/suite-map.yaml maps the evaluator and the new suite so select-suites.mjs prints no FULL_RUN for that path; the prompt-diet ledger carries an entry for this ref and TEST-012 is re-pinned; test-aai-layer-profiles.sh and test-aai-prompt-diet.sh exit 0 | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1530.log, docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1531.log TEST-1530/1531 mutation-gate PASS | — | companion obligations; PROFILES/DOCS_AI_CANON/suite-map rows were already in place from batches 1-7, TEST-1530 verifies them as a regression guard |
| Spec-AC-23 | CHANGELOG.md carries a `## [unreleased] — ` heading for this capability whose body names docs/ai/merge-policy.yaml, merge-policy.mjs --validate, and the breaking removal of the prose standing authorization with its migration step | done | docs/ai/tdd/configurable-merge-policy-lanes-green-TEST-1532.log TEST-1532 mutation-gate PASS | — | Article 5 disclosure |

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
| TEST-1502 | Spec-AC-02 | integration | tests/skills/test-aai-hooks-overlay.sh | 8-payload matrix, stderr and rc captured from the adapter at the base commit (git show into scratch) and from the live adapter, with and without a policy file: byte-equal | sed:s/Merge denied: constitution article 7/Merge denied: article 7/ | green |
| TEST-1503 | Spec-AC-03 | integration | tests/skills/test-aai-merge-policy.sh | base has no policy, head commit and working tree carry an allow-all policy: verdict no_policy | sed:s/readAtBase\(root, base, POLICY_PATH\)/readFileSync(join(root, POLICY_PATH), 'utf8')/ | green |
| TEST-1504 | Spec-AC-03 | integration | tests/skills/test-aai-merge-policy.sh | base policy has no lane covering docs, head widens it: verdict denied reason=no_lane_matched | sed:s/\['show', oid \+ ':' \+ relPath\]/['show', 'HEAD:' + relPath]/ | green |
| TEST-1505 | Spec-AC-03 | integration | tests/skills/test-aai-merge-policy.sh | decision record appended only in the head commit: denied reason=policy_invalid and stdout names decision_missing | sed:s/readAtBase\(root, base, 'docs\/ai\/decisions\.jsonl'\)/readFileSync(join(root, 'docs\/ai\/decisions.jsonl'), 'utf8')/ | green |
| TEST-1506 | Spec-AC-04 | integration | tests/skills/test-aai-merge-policy.sh | three PRs (add, modify, delete docs/ai/merge-policy.yaml) and one touching .aai/scripts/merge-policy.mjs, all else passing: each exits 3 with reason=policy_touched and the path | sed:s/if \(GUARD_PATHS\.includes\(f\)\)/if (false)/ | green |
| TEST-1507 | Spec-AC-04 | unit | tests/skills/test-aai-merge-policy.sh | GUARD_PATHS (read via node import) is a superset of the relative import closure of merge-policy.mjs and lane-gate.mjs plus claude-hook-gate.sh and the policy path | sed:s/'\.aai\/scripts\/lane-gate\.mjs',// | green |
| TEST-1508 | Spec-AC-05 | integration | tests/skills/test-aai-merge-policy.sh | Dockerfile matching both architecture and kind: architecture; src/x.bin matching nothing: unclassified; git mv of content file to Dockerfile: architecture | sed:s/for \(const a of policy\.architecture\)/for (const a of [])/ | green |
| TEST-1509 | Spec-AC-06 | unit | tests/skills/test-aai-merge-policy.sh | 10-row glob table through --classify (a/b.md vs *.md, **/*.md at depth 0 and 3, src/** vs src, ? vs slash, literal dot) equals golden output | sed:s/\[\^\/\]\*/.*/ | green |
| TEST-1510 | Spec-AC-07 | integration | tests/skills/test-aai-merge-policy.sh | six review fixtures: listed APPROVED at head allowed; unlisted, stale-commit, approve-then-changes-requested, approve-then-dismissed, label-only denied requester_approval_missing; approve-then-commented allowed | sed:s/r\.commit && r\.commit\.oid === headOid/true/ | green |
| TEST-1511 | Spec-AC-08 | integration | tests/skills/test-aai-merge-policy.sh | rollup fixtures: empty, IN_PROGRESS, FAILURE, StatusContext PENDING each ci_not_green; SUCCESS plus NEUTRAL plus SKIPPED passes | sed:s/if \(rollup\.length === 0\) return false/if (rollup.length < 0) return false/ | green |
| TEST-1512 | Spec-AC-09 | integration | tests/skills/test-aai-merge-policy.sh | no pr_sweep record in fixture EVENTS: sweep_check_failed; policy with requires ci false or sweep_check false: validate exit 1 unknown_key (remediation round, B1: mutation re-recorded against runSweepCheck's sweepCheckAllowed-based rewrite) | sed:s/return sweepCheckAllowed\(rc, stdout, pr\) \? null : 'sweep_check_failed';/return sweepCheckAllowed(rc, stdout, pr) ? 'sweep_check_failed' : null;/ | green |
| TEST-1513 | Spec-AC-10 | integration | tests/skills/test-aai-merge-policy.sh | production lane without opt-in and public-preview lane without opt-in: validate exit 1 public_effect_not_opted_in; check denies policy_invalid; with opt-in both validate | sed:s/lane\.allow_public_side_effect !== true/false/ | green |
| TEST-1514 | Spec-AC-11 | integration | tests/skills/test-aai-merge-policy.sh | ceremony-3 spec: lane without max_ceremony denied ceremony_exceeds, with max_ceremony 3 allowed; no spec and no intake resolvable: denied ceremony_exceeds | sed:s/const DEFAULT_MAX_CEREMONY = 2/const DEFAULT_MAX_CEREMONY = 3/ | green |
| TEST-1515 | Spec-AC-11 | integration | tests/skills/test-aai-merge-policy.sh | four specs (levels 0, 2, 3, field absent): the level in merge-policy --check --debug-inputs equals the ceremony_level value printed by lane-gate.mjs for the same spec | sed:s/return 2; \/\/ canon: absent ceremony_level is implicit 2/return 3;/ | green |
| TEST-1516 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | three deploy-inconsistent lanes each give reaches_inconsistent; a consistent policy prints VALID lanes=1 exit 0 | sed:s/if \(lane\.merge_reaches !== impliedReach\)/if (false)/ | green |
| TEST-1517 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | decisions fixture: no match, two matches on shared ref and ts, owner_signoff false, other actor give decision_missing, decision_ambiguous, decision_unsigned, signer_mismatch | sed:s/if \(hits\.length > 1\)/if (hits.length > 99)/ | green |
| TEST-1518 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | unknown key, duplicate lane id, undefined kind, empty globs, reaches preview without requester_logins: each its code, one INVALID line per error | sed:s/errors\.push\(\{ lane: id, code: 'requester_missing' \}\)/void 0/ | green |
| TEST-1519 | Spec-AC-13 | unit | tests/skills/test-aai-merge-policy.sh | markers AAI_X_MERGE (valid), aai_x_merge, AAI_OPERATOR_MERGE, two lanes sharing one marker: bad_marker, bad_marker, duplicate_marker; allowed line names the lane marker | sed:s/const MARKER_RE = \/\^AAI_\[A-Z0-9_\]\+_MERGE\$\//const MARKER_RE = \/.\// | green |
| TEST-1520 | Spec-AC-14 | integration | tests/skills/test-aai-hooks-overlay.sh | fixture with base policy lane X, stub gh, valid pr_sweep: env marker X and prefix marker X allowed rc 0; marker Y, evaluator denial, git merge with marker X each rc 2 with article-7 text and a merge-policy line; no marker rc 2 with article-7 text and no merge-policy line | sed:s/merge-policy\.mjs" --check/merge-policy.mjs" --chek/ | green |
| TEST-1521 | Spec-AC-15 | integration | tests/skills/test-aai-merge-policy.sh | one fixture per requires key unmet (intake type rfc, ref listed as base roadmap capability, STATE last_validation fail, code_review fail, body lacking literal) gives its reason; all met is allowed | sed:s/if \(req\.pr_body_contains && !body\.includes\(req\.pr_body_contains\)\)/if (false)/ | green |
| TEST-1522 | Spec-AC-16 | integration | tests/skills/test-aai-merge-policy.sh | state CLOSED, isDraft true, gh stub exit 1, gh absent from PATH, baseRefOid unknown object: pr_not_open, pr_not_open, api_unavailable, api_unavailable, base_unavailable, all exit 3 | sed:s/prJson\.isDraft === true/false/ | green |
| TEST-1523 | Spec-AC-16 | integration | tests/skills/test-aai-merge-policy.sh | after the whole suite, every argv line in the stub gh log starts with pr view | sed:s/\['pr', 'view', String\(pr\)/['api', 'repos', String(pr)/ | green |
| TEST-1524 | Spec-AC-17 | integration | tests/skills/test-aai-merge-policy.sh | two satisfiable lanes: allowed names the first; reorder the file: names the other; three failing lanes: no_lane_matched plus exactly three lane lines | sed:s/for \(const lane of policy\.lanes\)/for (const lane of [...policy.lanes].reverse())/ | green |
| TEST-1525 | Spec-AC-18 | integration | tests/skills/test-aai-merge-policy.sh | live docs/ai/merge-policy.yaml validates against the live decisions ledger (exit 0) and its single lane carries every field value Spec-AC-18 names | sed:s/decision_match: "STANDING MERGE AUTHORIZATION"/decision_match: "STANDING DECISION"/ | green |
| TEST-1526 | Spec-AC-18 | integration | tests/skills/test-aai-merge-policy.sh | fixture base carries the live policy file plus the live wave-2 records: conforming internal ride allowed; capability ride, ceremony 3, validation fail, body without Residual, hooks path each denied with their reason | sed:s/exclude_roadmap_capability: true/exclude_roadmap_capability: false/ | green |
| TEST-1527 | Spec-AC-19 | integration | tests/skills/test-aai-merge-policy.sh | grep -c ref wave-2-roadmap and STANDING AUTHORIZATION in SKILL_PR equal 0; SKILL_PR, AGENTS.md and SKILL_SHIP each name merge-policy.mjs; hooks TEST-012 literals present | sed:s/merge-policy\.mjs --check --pr/merge-policy.mjs --pr/ | green |
| TEST-1528 | Spec-AC-20 | integration | tests/skills/test-aai-doctor.sh | fixtures: absent clean (no CAT-19 line), valid (PASS lanes=1), invalid (WARN with code), absent plus orphaned STANDING MERGE AUTHORIZATION record (WARN naming it); --json has id CAT-19 | sed:s/STANDING MERGE AUTHORIZATION/STANDING MERGE AUTH0RIZATION/ | green |
| TEST-1529 | Spec-AC-21 | integration | tests/skills/test-aai-constitution.sh | article 7 line contains merge-policy.mjs and operator-only; ratification line contains v2, 2026-10-03; existing TEST-001..TEST-005 still pass | sed:s/v2, 2026-10-03/v1, 2026-07-16/ | green |
| TEST-1530 | Spec-AC-22 | integration | tests/skills/test-aai-merge-policy.sh | PROFILES core list line, DOCS_AI_CANON.list line, suite-map maps the evaluator (select-suites on that one path prints no FULL_RUN and selects aai-merge-policy); layer-profiles suite exits 0 | sed:s/  - \.aai\/scripts\/merge-policy\.mjs/  - .aai\/scripts\/merge-policy-x.mjs/ | green |
| TEST-1531 | Spec-AC-22 | integration | tests/skills/test-aai-prompt-diet.sh | JUSTIFIED_ADDITIONS carries an entry naming configurable-merge-policy-lanes and TEST-012 pin equals the new sum; suite exits 0 | sed:s/configurable-merge-policy-lanes/configurable-merge-policy-lanez/ | green |
| TEST-1532 | Spec-AC-23 | unit | tests/skills/test-aai-merge-policy.sh | CHANGELOG has a line starting with the unreleased heading prefix whose entry body names merge-policy.yaml, --validate and the standing authorization removal | sed:s/merge-policy\.mjs --validate/merge-policy.mjs --check/ | green |
| TEST-1533 | Spec-AC-11 | integration | tests/skills/test-aai-merge-policy.sh | validation-round1 B1: `--check --pr <n>` with NO --spec/--intake/--state resolves ceremony/intake_type/ref from STATE current_focus (spec_path/primary_path) and allows a qualifying internal-standing ride | sed:s/function resolveCurrentFocusPaths/function resolveCurrentFocusPathsX/ | green |
| TEST-1534 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | validation-round1 B2: a boolean-typed scalar (production_on_merge) reads only true/false; True/yes is parse_error, never a silent false reroute; remediation round 5: a quoted "true"/"false" is noncanonical (one spelling per type), bare true/false stay VALID | sed:s/function parseBooleanScalar/function parseBooleanScalarX/ | green |
| TEST-1535 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | validation-round1 B2: deploy.preview and merge_reaches reject out-of-set values (PUBLIC, publik, Nothing) as parse_error | sed:s/if \(!DEPLOY_PREVIEW_ENUM\.has\(v\)\) return/if (false) return/ | green |
| TEST-1536 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | validation-round1 B2: a repeated requires: block or a repeated lane scalar key is duplicate_key, not last-writer-wins | sed:s/seenLaneKeys\.has\('requires'\)/false \&\& seenLaneKeys.has('requires')/ | green |
| TEST-1537 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | validation-round1 B2: a lane missing a required field (marker) is missing_key | sed:s/for \(const rk of REQUIRED_LANE_KEYS\)/for (const rk of [])/ | green |
| TEST-1538 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | validation-round1 B2: an explicitly-written max_ceremony outside 0-3 is bad_ceremony | sed:s/lane\.max_ceremony <= 3/lane.max_ceremony <= 30/ | green |
| TEST-1539 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | validation-round1 NB-7: an absent version is missing_key; a version other than 1 is parse_error | sed:s/policy\.version !== 1/policy.version !== 2/ | green |
| TEST-1540 | Spec-AC-11 | integration | tests/skills/test-aai-merge-policy.sh | validation-round1 NB-2: readRideCeremony fails closed to 3 on a quoted/non-canonical ceremony_level, and an explicit --spec that does not exist never falls back to --intake | sed:s/if \(!\['0', '1', '2', '3'\]\.includes\(cl\[1\]\)\) return 3/if (false) return 3/ | green |
| TEST-1541 | Spec-AC-14 | integration | tests/skills/test-aai-hooks-overlay.sh | validation-round1 B1/NB-1: the hook lane path, with no AAI_SWEEP_* vars in a normal session, resolves intake_types from STATE current_focus and allows a qualifying ride naming --match-head-commit; --auto/--admin and a missing/mismatched --match-head-commit are refused | sed:s/LANE_MATCH_HEAD_ERE='--match-head-commit\[\[:space:\]\]\+\(\[0-9a-fA-F\]\+\)'/LANE_MATCH_HEAD_ERE='nomatch'/ | green |
| TEST-1542 | Spec-AC-14 | integration | tests/skills/test-aai-hooks-overlay.sh | validation-round2 R2-B1: the lane path's merge-segment allow-list refuses gh's own --flag=value spelling (--admin=true, --auto=1), a quoted --admin/--auto/--repo/-R, and a repeated --match-head-commit; the canonical allowed shape (plus optional --delete-branch) still allows | sed:s/lane_check_merge_shape \|\| return/true/ (pipe-free replacement: a literal `\|\|` in a replacement cell would land a literal backslash in the mutated source) | green |
| TEST-1543 | Spec-AC-15 | unit | tests/skills/test-aai-merge-policy.sh | validation-round2 R2-B2: a scalar, unclosed or quoted-pseudo-list value for a list-typed key (kinds, requester_logins, requires.intake_types) is parse_error; an empty requires.pr_body_contains is parse_error; an explicit intake_types: [] and a well-formed requester_logins: [alice] stay VALID (controls) | sed:s/kv4\.key === 'intake_types'/kv4.key === 'intake_types_x'/ | green |
| TEST-1544 | Spec-AC-15 | integration | tests/skills/test-aai-merge-policy.sh | validation-round2 R2-B2: --check denies reason=policy_invalid code=parse_error for a scalar requires.intake_types, end to end, rather than evaluateLane silently skipping the condition (Array.isArray was false) and allowing a non-matching (feature) intake through a change-only lane | sed:s/kv4\.key === 'intake_types'/kv4.key === 'intake_types_x'/ | green |
| TEST-1545 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | validation-round3 R3-B1: an inline flow value on a block header (requires, deploy, architecture) is parse_error (remediation round 5; round 4 reported it as noncanonical), never a silently-empty block; an architecture entry with no globs at all is missing_key | sed:s/if \(rest !== '\[\]' && rest !== '\{\}'\) return 'parse_error';/void 0;/ | green |
| TEST-1546 | Spec-AC-15 | unit | tests/skills/test-aai-merge-policy.sh | validation-round3 NB-3: a trailing bracket pair after a flow list, or a literal comma written as data inside quotes, is parse_error, never a silently narrowed list -- remediation round 5: a list item with no canonical spelling (a quote, backslash or control character inside) is refused alongside, since it is what would let the canonical emitter echo a misread list back in the file's own shape | sed:s/if \(\[badQuote, noSpelling\]\.some\(Boolean\)\) return null;/void 0;/ | green |
| TEST-1547 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | P1 textual canonical form: a canonical policy dressed in a BOM, CRLF, full-line, indented and trailing comments (after a space or a tab), trailing spaces/tabs and blank lines stays VALID; every equivalent respelling (quoted or single-quoted string, quoted boolean, quoted list item, empty deploy/architecture/requires block, extra space, key order) is noncanonical -- remediation round 5 deliberately changes round 4's VALID expectation for respellings | sed:s/const text = stripTrailingComment\(line\)/const text = (line)/ | green |
| TEST-1548 | Spec-AC-12 | integration | tests/skills/test-aai-merge-policy.sh | structural fuzz: a dozen single-line perturbations of the LIVE merge-policy.yaml (found by pattern, not line number), each one the parser would not otherwise consume, are all invalid with the specific code each gets | sed:s/function headerRest\(rest, lines, i, childIndent\) \{/function headerRest() { return 'ok';/ | green |
| TEST-1549 | Spec-AC-14 | integration | tests/skills/test-aai-hooks-overlay.sh | validation-round3 NB-1: the lane path requires an explicit PR number in the gh pr merge segment; the branch-implicit form (no number) is refused, the canonical numbered shape still allows | sed:s/if \[ "\$have_pr" -eq 0 \]; then/if [ "\$have_pr" -eq 99 ]; then/ | green |
| TEST-1550 | Spec-AC-13 | integration | tests/skills/test-aai-merge-policy.sh | validation-round4 R4-B1a: the live policy plus a second unconditioned lane spelling its marker [AAI_INTERNAL_STANDING_MERGE] is parse_error at --validate and denied policy_invalid at --check (round 4: allowed lane=loose); decision_ref: [ref@ts] is parse_error; controls: the scalar duplicate stays duplicate_marker, a distinct marker stays VALID lanes=2 | sed:s/if \(\/\^\[\[\{\]\/\.test\(s\)\) return PARSE_FAIL;/void 0;/ | green |
| TEST-1551 | Spec-AC-14 | integration | tests/skills/test-aai-hooks-overlay.sh | validation-round4 R4-B1a end to end: the real hook adapter denies (rc 2, merge-policy line naming policy_invalid) a policy whose second unconditioned lane spells the marker as a list, for a ride the conditioned lane denies (round 4: rc 0); control: the conditioned lane alone allows a qualifying ride | sed:s/if \(parsed\.errors\) return parsed;/if (false) return parsed;/ | green |
| TEST-1552 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | validation-round4 R4-B1a defense in depth: a [ or { value on every scalar-typed key (version, a kind id, a lane id, deploy.preview, decision_ref, decision_match, signed_by, merge_reaches, marker, max_ceremony, pr_body_contains) is parse_error, not merely noncanonical | sed:s/if \(\/\^\[\[\{\]\/\.test\(s\)\) return PARSE_FAIL;/void 0;/ | green |
| TEST-1553 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | validation-round4 R4-B1b: lanes: [], kinds: [], architecture: [], deploy: {}, requires: {} and lanes: {} each followed by indented children are parse_error (round 4: children read anyway, VALID); an empty block with no children is noncanonical line=2; an omitted block (version only) is VALID lanes=0 | sed:s/if \(i < lines\.length && lines\[i\]\.indent >= childIndent\) return 'parse_error';/void 0;/ | green |
| TEST-1554 | Spec-AC-15 | unit | tests/skills/test-aai-merge-policy.sh | validation-round4 NB-1: U+FEFF or NBSP before # inside pr_body_contains is not a comment start, the needle keeps it and the file is noncanonical (round 4: needle silently read as Residual, VALID); a # after an ASCII space or a tab stays a comment, VALID | sed:s/raw\[k\]\.text !== canon\[k\]/false/ | green |
| TEST-1555 | Spec-AC-12 | integration | tests/skills/test-aai-merge-policy.sh | every blocking parser shape from validation rounds 1-3 (quoted booleans, True/yes, PUBLIC/publik, repeated requires, quoted max_ceremony, scalar/unclosed/pseudo-list intake_types, unclosed requester_logins, empty pr_body_contains, inline requires/deploy/architecture, missing globs, trailing bracket, quoted comma, duplicated globs), applied to the live policy, is INVALID with its own code | sed:s/raw\[k\]\.text !== canon\[k\]/false/ | green |
| TEST-1556 | Spec-AC-12 | integration | tests/skills/test-aai-merge-policy.sh | property test over the live policy: at least 20 single-token perturbations (wrap a scalar in [], quote/unquote, single quotes, leading zero, indent +2/-2, append a token, append {}, list separator, spacing around the colon, duplicate a line, move a line out of order, into another block, into another lane) are each INVALID; comment/whitespace-only perturbations (trailing comments after a space or a tab, full-line and indented comments, blank and whitespace-only lines, trailing spaces/tabs, CRLF plus BOM) each stay VALID | sed:s/raw\[k\]\.text !== canon\[k\]/false/ | green |
| TEST-1557 | Spec-AC-12 | integration | tests/skills/test-aai-merge-policy.sh | merge-policy.mjs --canonical: the live policy's canonical output fed back through --validate is VALID and equals the live file's body; a respelled live policy (quoted, single-quoted, reordered, spaced) is noncanonical, its --validate names --canonical, and its --canonical output equals the live canonical text and validates; a parse_error makes --canonical exit 1 | sed:s/if \(opts\.mode === 'canonical'\) return runCanonical\(opts\);/void 0;/ | green |
| TEST-1558 | Spec-AC-20 | integration | tests/skills/test-aai-doctor.sh | CAT-19: a noncanonical policy is WARN naming code=noncanonical line=8 and merge-policy.mjs --canonical; its canonical spelling is PASS | sed:s/l\.includes\('code=noncanonical'\)/false/ | green |
| TEST-1559 | Spec-AC-09 | integration | tests/skills/test-aai-merge-policy.sh | code review B1: runSweepCheck/sweepCheckAllowed counts the sweep as passed ONLY when lane-gate.mjs --sweep-check exits 0 AND stdout's first line is the allowed verdict for THIS pr; an unreadable EVENTS.jsonl (lane-gate's own onError handler, rc 0, "LANE heavy reason=internal-error") denies sweep_check_failed, never allowed; a real pr_sweep record still allows | sed:s/return sweepCheckAllowed\(rc, stdout, pr\) \? null : 'sweep_check_failed';/if (rc === 5) return 'sweep_check_failed'; return null;/ | green |
| TEST-1560 | Spec-AC-15 | integration | tests/skills/test-aai-merge-policy.sh | code review N2: exclude_roadmap_capability fails CLOSED (roadmap_unreadable) when the base roadmap is absent or structurally broken, or the ride's intake carries no id: -- never silently skipped; a resolvable roadmap that genuinely excludes nothing still allows | sed:s/if \(!ctx\.roadmapCapabilities \|\| !ctx\.rideRef\) \{/if (false) {/ | green |
| TEST-1561 | Spec-AC-05 | integration | tests/skills/test-aai-merge-policy.sh | code review N3: a zero-file PR (getChangedFiles's '-' sentinel for an empty diff) classifies as unclassified path=- before any glob match, never matched through this repo's own catch-all ** kind | sed:s/if \(files\.length === 1 && files\[0\] === '-'\) return/if (false) return/ | green |
| TEST-1562 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | code review N4: an empty decision_match is parse_error, mirroring the existing empty pr_body_contains rule -- a non-empty decision_match stays VALID (control); round-6 NB-4 widened the live check to whitespace-only (TEST-1566), so this row's mutation now disables the whole condition | sed:s/if \(typeof scalar !== 'string' \|\| scalar\.trim\(\) === ''\) return fail\(lane\.id, 'parse_error'\);/if (false) return fail(lane.id, 'parse_error');/ | green |
| TEST-1563 | Spec-AC-13 | unit | tests/skills/test-aai-merge-policy.sh | validation-round5 NB-1 (part 1): a lane id carrying a space or an = is parse_error -- the root cause of claude-hook-gate.sh's LANE_ALLOWED_ERE being spoofable by a lane id embedding its own " marker=<other>" text; a hyphenated or numeric id (existing live shapes) stays VALID (controls) | sed:s/if \(typeof laneId === 'string' && \/\[\\s=\]\/\.test\(laneId\)\) return fail\('-', 'parse_error'\);/if (false) return fail('-', 'parse_error');/ | green |
| TEST-1564 | Spec-AC-14 | integration | tests/skills/test-aai-hooks-overlay.sh | validation-round6 NB-1 remediation: round 5's greedy `lane=.*` LANE_ALLOWED_ERE always preferred the LAST " marker=...decision_ref=" occurrence, which opened a NEW vector -- a spoofed evaluator line whose decision_ref VALUE embeds its own fake " marker=<other> decision_ref=..." text (sitting AFTER the real marker field) is read as that fake marker. The hook's ERE is now FULL-LINE anchored and FIELD-EXACT (every field whitespace- and =-free, in the evaluator's fixed order); such a line fails the shape entirely and the hook denies outright regardless of which marker env var is set; the real evaluator's own marker still governs on a well-formed line | sed:s/decision_ref=\(\[\^\[:space:\]=\]\+\)/decision_ref=(.*)/ | green |
| TEST-1565 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | validation-round6 NB-1: decision_ref is parse-rejected unless it matches `<ref_id>@<ISO8601Z>` with a SAFE_BARE ref_id (DECISION_REF_RE) -- a space (including the exact round-6 hook-spoof payload), a missing/second @, a bad timestamp or an = is parse_error; the live shape with a matching decision stays VALID (control) | sed:s/if \(typeof scalar !== 'string' \|\| !DECISION_REF_RE\.test\(scalar\)\) return fail\(lane\.id, 'parse_error'\);/void 0;/ | green |
| TEST-1566 | Spec-AC-12 | unit | tests/skills/test-aai-merge-policy.sh | validation-round6 NB-4: decision_match consisting only of whitespace is parse_error, mirroring the N4 empty-string rule (TEST-1562) -- a whitespace needle matches almost every real decision text, proving nothing | sed:s/scalar\.trim\(\) === ''/scalar === ''/ | green |
| TEST-1567 | Spec-AC-15 | unit | tests/skills/test-aai-merge-policy.sh | validation-round6 NB-4: requires.pr_body_contains consisting only of whitespace is parse_error, mirroring TEST-1543's empty-string rule | sed:s/v\.trim\(\) === ''/v === ''/ | green |
| TEST-1568 | Spec-AC-09 | unit | tests/skills/test-aai-merge-policy.sh | validation-round6 NB-4: sweepCheckAllowed binds pr= to a WHOLE numeric token -- the old `(?:[^0-9]\|$)` tail let pr=7x count for PR 7 (x satisfies "not a digit" without reaching a token boundary); pr=70 and pr=7 (end of string or followed by whitespace) are controls | sed:s/\(\?:\\s/(?:[^0-9]/ (pipe-free replacement: a literal \| in a replacement cell would land a literal backslash in the mutated source) | green |
| TEST-1569 | Spec-AC-05 | integration | tests/skills/test-aai-merge-policy.sh | code review round 7 B1: lane coverage is judged per changed path, never over the PR's union of matched kinds -- a content-only lane denies a mixed content+code PR naming the uncovered path; the same lane allows an all-content PR; a path matching two kinds (content declared first, special declared second and more specific) allows via its SECOND matched kind, proving classifyFiles records every match, not just the first; the live catch-all internal-standing policy still allows a two-file ride | sed:s/if \(!covered\) return \{ ok: false, reason: 'kind_not_in_lane', path \};/if (false) return { ok: false, reason: 'kind_not_in_lane', path };/ | green |
| TEST-1570 | Spec-AC-05 | integration | tests/skills/test-aai-merge-policy.sh | code review round 7 B2: getChangedFiles reads git's real path bytes via `-z`, never the default C-quoted/escaped form -- a non-ASCII and a quote-bearing path under an architecture glob still deny architecture (the pre-fix form let both bypass the deny); a space- and a backslash-bearing path still classify and allow normally; a GUARD_PATHS path still denies policy_touched with a non-ASCII sibling present in the same diff | sed:s/'diff', '-z', '--name-only'/'diff', '--name-only'/ | green |
| TEST-1571 | Spec-AC-19 | integration | tests/skills/test-aai-merge-policy.sh | code review round 7 N7: SKILL_PR.prompt.md step 6's documented lane-merge command, with `<n>`/`<headRefOid>` substituted, is parsed out of the prompt text and run through claude-hook-gate.sh's own lane_check_merge_shape allow-list (TEST-1549) -- the pre-fix command (no PR number) was refused by the hook it documents | sed:s/gh pr merge <n> --squash --match-head-commit <headRefOid>` \(the PR\n     number is required — the hook's lane allow-list refuses the\n     branch-implicit form with no number\) with that/gh pr merge --squash --match-head-commit <headRefOid>` with that/ | green |
| TEST-1572 | Spec-AC-05 | integration | tests/skills/test-aai-merge-policy.sh | validation round 8 V8-B1: globToRegExp's compiled RegExp needed the `s` (dotAll) flag -- without it, a changed path's LF, CR, U+2028 or U+2029 failed to match an architecture glob reached through `**` while a kind glob written with `*` still matched the same bytes, letting the PR bypass the P5 architecture deny; reproduced for all four line-terminator bytes under `.github/**`+`**/*.yml` and for the RFC's own `migrations/**`+content example | sed:s/, 's'\);/);/ | green |
| TEST-1573 | Spec-AC-05 | integration | tests/skills/test-aai-merge-policy.sh | validation round 8 V8-B1 INFO: a denied path is echoed verbatim in its verdict/reason line (round 7 B2) -- escaping a line terminator or other control byte before printing it keeps P10's one-line-per-lane contract even when the path carries a forged `MERGE-POLICY allowed`/`lane=...` payload; the denial still prints exactly the expected number of physical lines | sed:s/path=\${escapeForLine\(verdict\.path\)}/path=\${verdict.path}/ | green |

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
