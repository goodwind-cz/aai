---
id: spec-delegated-requester-approval
type: spec
number: 299
status: done
mutation_gate: v1
frozen_sha256: 57bc7119bc9ab5c288e7ffda69cda9d83eacee3dd4457a7d54827cd3202c7d38
ceremony_level: 2
links:
  requirement: delegated-requester-approval
  rfc: null
  pr: []
  commits: []
---

# A lane can require a chat relay line on a delegated approver's review

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-0258-delegated-requester-approval.md
  (GitHub goodwind-cz/aai#474, owner decision: option B, second comment).
- Prior scope this one extends (closed, not edited):
  docs/specs/SPEC-0207-spec-configurable-merge-policy-lanes.md (P1 canonical
  form, P6 requester approval, P10 output contract, R3 "guardrails against
  habit, not a security boundary").
- RFC-0014 D1 (docs/rfc/RFC-0014-unattended-rides-human-gate-at-merge.md):
  the requester is the human at the merge; this scope keeps that human, and
  only changes how her approval reaches GitHub.
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, no YAML
  library, bash 3.2 suites through `.aai/scripts/aai-run-tests.sh`).
- Registry items closed by this scope: none (`follow-ups.mjs list` holds no
  open item about requester approval; the three `fu-merge-policy-*` items
  concern ride binding, glob `?` and decision timestamps, not touched here).

## Implementation strategy

- Strategy: tdd
- Rationale: a behavioural change to the merge evaluator, the one script
  that decides whether the agent may merge. Every new verdict can be seen
  failing on the unchanged tree (the key is `unknown_key` today, so every
  delegated fixture is `policy_invalid`), and the parser's history (four
  validation rounds of misreadings, SPEC-0207) argues for RED first and a
  mutation per row.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: the main checkout is shared with other sessions; the
  ride is PR-bound and the caller placed it in its own worktree.
- User decision: worktree (recorded in STATE, autopilot default)
- Base ref: origin/main at c1034b24
- Worktree branch/path: feat/delegated-requester-approval at
  /Users/ales/Projects/aai-worktrees/delegated-requester-approval
- Review required: true
- Review scope (explicit paths): .aai/scripts/merge-policy.mjs;
  tests/skills/test-aai-merge-policy.sh;
  docs/product/configurable-merge-policy-lanes.md; docs/USER_GUIDE.md;
  CHANGELOG.md; docs/issues/CHANGE-0258-delegated-requester-approval.md;
  docs/specs/SPEC-0299-spec-delegated-requester-approval.md.

## Ceremony

Ceremony level 2. `.aai/scripts/merge-policy.mjs` is not in
`protected_paths_l3` of docs/ai/docs-audit.yaml nor in the WORKFLOW.md
canonical list (state engine, allocator, pre-commit guards, hook gate,
workflow canon), and this scope does not touch `claude-hook-gate.sh` or
`hook-gate.mjs`: the hook reads only the `MERGE-POLICY allowed` line, whose
shape does not change. The evaluator is in merge-policy's own GUARD_PATHS,
so this PR is never lane-eligible and the owner merges it. Not L1: a new
config key, new validation codes and a new check path in a security-relevant
evaluator.

Companion obligations: no `.aai/*.prompt.md` or `.aai/AGENTS.md` byte
changes, no new `.aai/**` file. Neither applies.

## Decisions

### D1. Config shape: one optional per-lane list, `delegated_approvers`

```yaml
lanes:
  - id: requester-content
    ...
    requester_logins: [alice, content-gateway]
    delegated_approvers: [content-gateway]
```

- Optional. Absent means no login of the lane is delegated, and P6 judges
  the lane exactly as SPEC-0207 P6 does today. The parser never defaults it
  in: an absent key stays absent on the parsed lane, so `--canonical` does
  not emit it.
- Canonical position (P1): directly after `requester_logins`, before
  `requires`. Lane key order becomes decision_ref, decision_match,
  signed_by, kinds, merge_reaches, allow_public_side_effect, max_ceremony,
  marker, requester_logins, delegated_approvers, requires. One flow list on
  the key's own line, items by the P1 string rule.
- Parse (closed shape, same reader as `requester_logins`): anything that is
  not a well-formed flow list, or carries an empty item, is `parse_error`.
  A second `delegated_approvers` line in one lane is `duplicate_key`.
- Validation (`validatePolicy`, one INVALID line per error):
  - `delegated_empty`: the key is written as `[]`. An empty list declares
    nothing and is refused rather than read as absent.
  - `delegated_duplicate`: the same login appears twice.
  - `delegated_not_requester`: an entry is not in the lane's
    `requester_logins` (this also covers a lane with no `requester_logins`).
    A delegated approver is a kind of requester; listing it only here would
    let the key be read as a second approval source.

### D2. The relay line: one canonical line, nothing else accepted

A delegated login's review body must contain exactly one line of the form

```
AAI-RELAY chat=<platform>:<message-id> requester=<platform>:<user-id>
```

- `<platform>`: `[a-z][a-z0-9-]{0,31}` (for example `telegram`).
- `<message-id>` and `<user-id>`: 1 to 128 characters from
  `[A-Za-z0-9_.:/-]` (Telegram chat and message ids, including a negative
  chat id or a `<chat-id>/<message-id>` pair).
- Both fields name the same platform.
- The line is matched whole against
  `^AAI-RELAY chat=([a-z][a-z0-9-]{0,31}):([A-Za-z0-9_.:/-]{1,128}) requester=([a-z][a-z0-9-]{0,31}):([A-Za-z0-9_.:/-]{1,128})$`
  after splitting the body on LF and dropping one trailing CR per line.
  Single spaces, fixed field order, no other tokens, no leading or trailing
  whitespace.
- Candidate lines: any line whose text, after trimming whitespace, starts
  with `aai-relay` in any letter case. Exactly zero candidates is
  `relay_reference_missing`. More than one candidate, or one candidate that
  does not match the regex whole or names two different platforms, is
  `relay_reference_malformed`. A near-miss spelling is therefore never read
  as "no line" and never as a valid one.
- The review's own `commit.oid` binds the head (P6 unchanged); the line does
  not repeat the SHA.

### D3. Check behaviour (P6 extended)

For each login in `requester_logins`, in list order, take that login's
latest deciding review by `submittedAt` (APPROVED, CHANGES_REQUESTED,
DISMISSED; COMMENTED never overrides), exactly as today.

- A non-delegated login satisfies the lane when that review is APPROVED at
  `headRefOid` (unchanged).
- A delegated login satisfies the lane when that review is APPROVED at
  `headRefOid` AND its body carries a valid relay line (D2).
- The lane passes the requester step when at least one login satisfies it.
- Otherwise the lane is denied. When at least one delegated login's latest
  deciding review is APPROVED at `headRefOid` but its relay line is missing
  or malformed, the reason is that login's relay reason (the first such
  login in `requester_logins` order), printed as
  `lane=<id> reason=relay_reference_missing login=<login>` or
  `lane=<id> reason=relay_reference_malformed login=<login>` (the login
  escaped like every printed value). In every other case the reason stays
  `requester_approval_missing`.
- `requesterApproved(reviews, logins, headOid)` keeps its signature and
  result for callers that pass no delegated list.

### D4. The trust assumption, stated where the pattern is documented

Option B is documented as a supported pattern in
docs/product/configurable-merge-policy-lanes.md and docs/USER_GUIDE.md:
the gateway holds a dedicated GitHub App or bot credential; it submits an
APPROVED review at the exact `headRefOid` the requester was shown, with the
relay line. The documentation states the assumption verbatim in substance:
the approving identity's credential must be unreachable from agent tools
(never in the agent's environment, profile config or any file the agent can
read). On a single host where the agent runs as the same OS user, this is a
guardrail, not a security boundary, the same wording SPEC-0207 R3 uses for
markers; server-side branch protection remains the only boundary. The relay
line distinguishes a relayed Approve from one pressed by hand with the bot's
credential only as long as whoever presses it by hand does not type the
line; it is a guardrail against habit, not proof of origin.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01.
- Intake AC-002 maps to Spec-AC-02, Spec-AC-05.
- Intake AC-003 maps to Spec-AC-03, Spec-AC-04.
- Intake AC-004 maps to Spec-AC-06.
- Intake AC-005 maps to Spec-AC-07, Spec-AC-08.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a lane carries no delegated_approvers key and its requester_logins lists a bot login whose latest deciding review is APPROVED at headRefOid with an empty body, merge-policy.mjs --check SHALL print the MERGE-POLICY allowed line for that lane and exit 0, and TEST-1510 SHALL stay green with all seven cases | done | docs/ai/tdd/delegated-requester-approval/green-TEST-3850.log; docs/ai/tdd/delegated-requester-approval/green-all.log; docs/ai/tdd/delegated-requester-approval/mutation-TEST-3850.log | — | back-compat: no new key, P6 unchanged |
| Spec-AC-02 | WHEN a lane lists a login in delegated_approvers and that login's latest deciding review is APPROVED at headRefOid and its body carries exactly one valid relay line (D2), alone, among other prose lines, or with CRLF line ends, --check SHALL print the allowed line and exit 0 | done | docs/ai/tdd/delegated-requester-approval/green-TEST-3851.log; docs/ai/tdd/delegated-requester-approval/green-all.log; docs/ai/tdd/delegated-requester-approval/mutation-TEST-3851.log | — | — |
| Spec-AC-03 | WHEN the delegated login's latest deciding review is APPROVED at headRefOid and its body holds no candidate relay line (empty body, or the message id only in prose), --check SHALL exit 3 and print the lane line lane=ID reason=relay_reference_missing login=LOGIN and SHALL NOT print reason=requester_approval_missing for that lane | done | docs/ai/tdd/delegated-requester-approval/green-TEST-3852.log; docs/ai/tdd/delegated-requester-approval/green-all.log; docs/ai/tdd/delegated-requester-approval/mutation-TEST-3852.log | — | — |
| Spec-AC-04 | WHEN the delegated login's latest deciding review is APPROVED at headRefOid and its body holds a lowercase prefix, a leading space, a trailing token, a missing requester field, two different platforms, an id with a space or an out-of-set character, an id longer than 128 characters, or two relay lines, --check SHALL exit 3 and print lane=ID reason=relay_reference_malformed login=LOGIN for each case | done | docs/ai/tdd/delegated-requester-approval/green-TEST-3853.log; docs/ai/tdd/delegated-requester-approval/green-all.log; docs/ai/tdd/delegated-requester-approval/mutation-TEST-3853.log | — | — |
| Spec-AC-05 | WHEN a lane lists a human login and a delegated login, --check SHALL allow on the human's APPROVED review at head even though the delegated login's review lacks a relay line; and SHALL deny with requester_approval_missing, not a relay reason, when the delegated login's relayed approval is at a commit other than headRefOid or is followed by a later CHANGES_REQUESTED review | done | docs/ai/tdd/delegated-requester-approval/green-TEST-3854.log; docs/ai/tdd/delegated-requester-approval/green-all.log; docs/ai/tdd/delegated-requester-approval/mutation-TEST-3854.log | — | — |
| Spec-AC-06 | WHEN merge-policy.mjs --validate reads a lane whose delegated_approvers is a bare scalar or holds an empty item it SHALL print INVALID with code parse_error and exit 1; WHEN it is written as an empty list, repeats a login, or names a login absent from requester_logins it SHALL print INVALID lane=ID code=delegated_empty, delegated_duplicate and delegated_not_requester respectively and exit 1; and --check over such a base policy SHALL deny reason=policy_invalid | done | docs/ai/tdd/delegated-requester-approval/green-TEST-3855.log; docs/ai/tdd/delegated-requester-approval/green-all.log; docs/ai/tdd/delegated-requester-approval/mutation-TEST-3855.log | — | — |
| Spec-AC-07 | WHEN --canonical reads a lane carrying delegated_approvers it SHALL print the key on the line right after requester_logins; a file that writes it before requester_logins SHALL fail --validate with noncanonical; and a lane without the key SHALL emit no delegated_approvers line | done | docs/ai/tdd/delegated-requester-approval/green-TEST-3856.log; docs/ai/tdd/delegated-requester-approval/green-all.log; docs/ai/tdd/delegated-requester-approval/mutation-TEST-3856.log | — | — |
| Spec-AC-08 | docs/product/configurable-merge-policy-lanes.md SHALL name delegated_approvers, the AAI-RELAY line format, relay_reference_missing, relay_reference_malformed, the phrase unreachable from agent tools and the phrase guardrail, not a security boundary; docs/USER_GUIDE.md SHALL name delegated_approvers and AAI-RELAY; CHANGELOG.md SHALL hold one unreleased per-entry heading naming delegated approvers | done | docs/ai/tdd/delegated-requester-approval/green-TEST-3857.log; docs/ai/tdd/delegated-requester-approval/green-all.log; docs/ai/tdd/delegated-requester-approval/mutation-TEST-3857.log | — | — |

## Implementation plan

- `.aai/scripts/merge-policy.mjs`:
  - `LANE_SCALAR_KEYS` gains `delegated_approvers` after
    `requester_logins`; `LIST_KEYS` gains it; the parser branch that reads
    `kinds`/`requester_logins` through `parseRequiredList` reads it too. No
    default is filled in when the key is absent.
  - `validatePolicy` adds the three D1 codes.
  - New exported `relayReference(body)` returning
    `{ ok: true, platform, chat, requester }` or
    `{ ok: false, reason: 'relay_reference_missing' | 'relay_reference_malformed' }`.
  - New exported `requesterVerdict(reviews, logins, headOid, delegated)`
    returning `{ ok: true }` or `{ ok: false, reason, login? }`;
    `requesterApproved` becomes a thin wrapper with an empty delegated list.
  - `evaluateLane` calls `requesterVerdict` with
    `lane.delegated_approvers || []`; `runCheck` appends
    ` login=<escaped>` to a lane line whose verdict carries a login.
  - The header comment's CANONICAL FORM and P6 notes name the key.
- `tests/skills/test-aai-merge-policy.sh`: TEST-3850 to TEST-3857 (below),
  each through the real CLI with the suite's gh stub.
- Docs: product doc section "Requesters without GitHub (relayed approval)",
  data model and interface bullets; USER_GUIDE paragraph; CHANGELOG entry.

Seams crossed:
- `gh pr view --json reviews` payload (`reviews[].body`, `author.login`,
  `commit.oid`) to the evaluator: every check test feeds a full PR JSON
  through the gh stub, never a hand-built in-process review list.
- Evaluator output to the hook gate: the allowed line is unchanged
  (`hook-gate.mjs` LANE_ALLOWED_RE); TEST-3851 asserts the exact allowed
  line, and the hook suite is run as a companion to prove no drift.
- Policy file written by an owner to `--validate`/`--canonical`/`--check`
  (doctor CAT-19 runs `--validate`): TEST-3855 and TEST-3856.

Edge cases: CRLF bodies; a body that is `null` or absent (treated as empty);
a delegated login that also appears twice in reviews (latest deciding wins);
a login with characters that need escaping in the lane line.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3850 | Spec-AC-01 | integration | tests/skills/test-aai-merge-policy.sh | no delegated key, bot login APPROVED at head with empty body: allowed line, exit 0 | `sed:s/const delegated = delegatedList\(lane\);/const delegated = logins;/` | green |
| TEST-3851 | Spec-AC-02 | integration | tests/skills/test-aai-merge-policy.sh | delegated login, valid relay line alone, among prose, with CRLF: allowed line, exit 0 | `sed:s/line.endsWith\('\\r'\)/false/` | green |
| TEST-3852 | Spec-AC-03 | integration | tests/skills/test-aai-merge-policy.sh | delegated login, no relay line: relay_reference_missing login=..., exit 3 | `sed:s/const RELAY_MISSING = 'relay_reference_missing';/const RELAY_MISSING = 'requester_approval_missing';/` | green |
| TEST-3853 | Spec-AC-04 | integration | tests/skills/test-aai-merge-policy.sh | eight malformed shapes and two lines: relay_reference_malformed, exit 3 | `sed:s/if \(candidates.length > 1\)/if (candidates.length > 9)/` | green |
| TEST-3854 | Spec-AC-05 | integration | tests/skills/test-aai-merge-policy.sh | mixed lane: human approval allows; stale or superseded relayed approval denies requester_approval_missing | `sed:s/const atHead = Boolean\(r.commit\) && r.commit.oid === headOid;/const atHead = true;/` | green |
| TEST-3855 | Spec-AC-06 | integration | tests/skills/test-aai-merge-policy.sh | --validate parse_error, delegated_empty, delegated_duplicate, delegated_not_requester; --check policy_invalid | `sed:s/code: 'delegated_not_requester'/code: 'delegated_ok'/` | green |
| TEST-3856 | Spec-AC-07 | integration | tests/skills/test-aai-merge-policy.sh | --canonical position, noncanonical order, no line when absent | `sed:s/'marker', 'requester_logins', 'delegated_approvers',/'marker', 'delegated_approvers', 'requester_logins',/` | green |
| TEST-3857 | Spec-AC-08 | doc | tests/skills/test-aai-merge-policy.sh | product doc, USER_GUIDE and CHANGELOG carry the named strings | `sed:s/unreachable from agent tools/hidden from agent tools/` | green |

RED plan: TEST-3850 is a back-compat pin and is green on the unchanged tree
by design; its RED is the mutation (a lane that treats every requester as
delegated reddens it). TEST-3851 to TEST-3856 are observed failing on the
unchanged tree (`unknown_key` makes every delegated fixture
`policy_invalid`); TEST-3857 fails before the docs are written. RED and
GREEN logs go to docs/ai/tdd/delegated-requester-approval/.

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-policy.sh`
  exits 0 with TEST-1510 and TEST-3850 to TEST-3857 printing PASS.
- Companion: `tests/skills/test-aai-hook-gate.sh` and
  `tests/skills/test-aai-hooks-overlay.sh` exit 0 (allowed-line shape
  unchanged).
- `node .aai/scripts/merge-policy.mjs --validate` on this repo's own policy
  prints `VALID lanes=1`.
- Mutation gate over the Test Plan's Mutation column.

## Residual risks

- R1: the relay line is a convention the gateway writes and the evaluator
  reads. A person holding the bot's credential can type it by hand; the
  check distinguishes habit, not origin (D4).
- R2: the evaluator does not bind the relay line's requester id to a list
  of platform ids in the lane; the gateway decides which chat user may
  approve. A lane-side list (`requester_ids`) is a possible follow-up, not
  in this scope (intake out of scope).
- R3: `gh pr view --json reviews` returns the review body as GitHub stores
  it; an edited review body changes the verdict on the next `--check`. A
  review edit does not change `commit.oid`, so an edited body is judged as
  if it were the original.

## Evidence contract

- ref_id: delegated-requester-approval
- RED/GREEN logs: docs/ai/tdd/delegated-requester-approval/
- Validation report: docs/ai/reports/VALIDATION-<ts>-delegated-requester-approval.md
- Review report: docs/ai/reviews/ (SKILL_CODE_REVIEW)
- Diff range: origin/main...feat/delegated-requester-approval

## Amendments

- 2026-11-16, TEST-3853 Mutation cell: the replacement half no longer
  escapes the parentheses. In a JavaScript replacement string a backslash
  before `(` stays literal, so the frozen cell produced a SyntaxError that
  reddened the whole module instead of exercising the more-than-one-line
  check. The pattern half is unchanged. Disclosed through spec-amend
  (signoff none; the owner's merge direction signs it).
