---
id: configurable-merge-policy-lanes
type: product
capability: configurable-merge-policy-lanes
status: current
delivered_by:
  - configurable-merge-policy-lanes
  - delegated-requester-approval
spec: docs/specs/SPEC-0207-spec-configurable-merge-policy-lanes.md
updated: 2026-11-16
---

# Owner-defined merge lanes

## What it does

By default an AAI agent never merges a pull request; merging is the
operator's job. A repository owner can now write down, in one project-owned
file, which kinds of pull requests the agent may merge on its own, for
example "a change that only touches content or design files, with green CI,
a recorded bot sweep and the requester's GitHub approval". Each such rule is
a lane, and each lane must point at a decision the owner signed. Anything
outside every lane, and anything touching architecture (containers,
dependencies, migrations, CI, credentials) as the owner defines it, still
goes to the operator. With no policy file, nothing changes.

## How to use it

1. Record the owner's decision in `docs/ai/decisions.jsonl` as a
   `hitl_decision` with `owner_signoff: true`, the owner's login as `actor`,
   and a sentence the lane will quote.
2. Write `docs/ai/merge-policy.yaml` (see Data model). Print the exact
   accepted spelling with `node .aai/scripts/merge-policy.mjs --canonical`
   and check it with `node .aai/scripts/merge-policy.mjs --validate`
   (`aai-doctor` category CAT-19 runs the same check).
3. Merge the policy file yourself. The evaluator reads the policy and the
   decisions only from the merge target branch, and a pull request that
   edits the policy or the merge machinery is never lane-eligible.
4. For a pull request, the agent runs
   `node .aai/scripts/merge-policy.mjs --check --pr <n>`. On an `allowed`
   line it merges with that lane's own marker:
   `<MARKER>=1 gh pr merge <n> --squash --match-head-commit <headRefOid>`,
   and cites the lane's `decision_ref` in its merge report.

Example lane for a site whose merges only rebuild a preview:

```yaml
version: 1
deploy:
  preview: public
  production_on_merge: false
architecture:
  - id: containers
    globs: [Dockerfile, "**/docker-compose*.yml"]
kinds:
  - id: content
    globs: ["src/content/**", "**/*.md"]
lanes:
  - id: requester-content
    decision_ref: site-content@2026-10-01T10:00:00Z
    decision_match: "MERGE LANE requester-content"
    signed_by: owner_login
    kinds: [content]
    merge_reaches: preview
    allow_public_side_effect: true
    marker: AAI_CONTENT_LANE_MERGE
    requester_logins: [requester_login]
```

## Data model

- `docs/ai/merge-policy.yaml` (project-owned, never touched by sync):
  `version`, `deploy` (`preview`: none/private/public,
  `production_on_merge`), `architecture` (id + globs; any match sends the PR
  to the operator), `kinds` (id + globs; closed world, an unmatched path
  denies), `lanes` (id, `decision_ref`, `decision_match`, `signed_by`,
  `kinds`, `merge_reaches`, opt-ins `allow_public_side_effect` and
  `max_ceremony`, a unique `AAI_*_MERGE` marker, `requester_logins`, the
  optional `delegated_approvers` (a subset of `requester_logins`, written
  right after it), and optional `requires` conditions). The file is valid
  only when, after comments and whitespace are stripped, it equals its
  canonical text.
- `docs/ai/decisions.jsonl`: each lane binds to exactly one owner-signed
  `hitl_decision` record.
- This repository's own policy carries one lane, `internal-standing`, which
  replaces the former prose standing merge authorization of 2026-09-12.

## Requesters without GitHub (relayed approval)

A requester who has no GitHub account can still be the human at the merge.
The supported pattern is a chat gateway that holds a dedicated GitHub App or
bot credential:

1. The gateway shows the requester a preview of one exact head (the PR's
   `headRefOid`) in chat.
2. When the requester answers OK in chat, the gateway submits an APPROVED
   review as the bot at that `headRefOid`. The review body carries one
   relay line (below).
3. The owner lists the bot in the lane's `requester_logins` and also in
   `delegated_approvers`.

```yaml
    requester_logins: [alice, content-gateway]
    delegated_approvers: [content-gateway]
```

A delegated login satisfies the requester step only when its latest
deciding review is APPROVED at `headRefOid` and its body carries exactly one
line of this form:

```
AAI-RELAY chat=<platform>:<message-id> requester=<platform>:<user-id>
```

- `<platform>` is `[a-z][a-z0-9-]{0,31}` (for example `telegram`) and is the
  same in both fields.
- `<message-id>` and `<user-id>` are 1 to 128 characters from
  `[A-Za-z0-9_.:/-]`.
- The line is matched whole: single spaces, fixed field order, no other
  tokens, no leading or trailing whitespace; the capital `AAI-RELAY` prefix
  is required. CRLF line ends are fine.
- Every body line whose trimmed text starts with `aai-relay`, in any letter
  case, counts as a relay line; any other line is ignored. Keep gateway
  footers and prose from starting with that word: a second such line makes
  the review malformed.
- A review that is APPROVED at head but has no line is denied
  `relay_reference_missing`; one with a line that is near-miss, doubled or
  otherwise not the exact form is denied `relay_reference_malformed`. Both
  lane lines end in `login=<login>`. Any other failure (a stale commit, a
  later CHANGES_REQUESTED) stays `requester_approval_missing`. A human
  login in the same lane is unaffected and needs no line.
- `--validate` refuses a `delegated_approvers` list that is written empty
  (`delegated_empty`), repeats a login (`delegated_duplicate`) or names a
  login missing from `requester_logins` (`delegated_not_requester`).

Trust assumption: the approving identity's credential must be
unreachable from agent tools (never in the agent's environment, profile
config or any file the agent can read). On a single host where the agent
runs as the same OS user this is a guardrail, not a security boundary; server-side branch
protection remains the real boundary. The relay line tells a relayed
Approve from one pressed by hand with the bot's credential only as long as
whoever presses it by hand does not type the line: it is a guardrail
against habit, not proof of origin. The evaluator does not check the
requester id in the line against any list.

## Interfaces and contracts

- `merge-policy.mjs --check --pr <n>`: first line `MERGE-POLICY allowed ...`
  (exit 0), `MERGE-POLICY denied ...` plus one line per lane (exit 3), or
  `MERGE-POLICY no_policy` (exit 4); usage error exit 2. Printed paths are
  escaped so every verdict stays one physical line.
- A lane denied for a delegated approver's relay line prints
  `lane=<id> reason=relay_reference_missing login=<login>` or
  `lane=<id> reason=relay_reference_malformed login=<login>`; the allowed
  line is unchanged.
- `merge-policy.mjs --validate`: `VALID lanes=<n>` (exit 0) or
  `INVALID lane=<id> code=<code>` lines (exit 1); exit 4 with no file.
- `merge-policy.mjs --canonical` and `--classify`: print the canonical
  policy text and the per-path classification.
- Claude hook gate: with a lane marker set, a `gh pr merge` is allowed only
  in the exact shape above and only when the evaluator allows that lane;
  with no lane marker the gate behaves byte-for-byte as before.
- Constitution article 7 (v2): a lane merge the evaluator allows under an
  owner-signed policy is the sole exception to operator-only merging.
- Breaking: a project relying on a prose standing authorization in
  `decisions.jsonl` without a policy file falls back to operator-only
  merges until it writes a lane; `aai-doctor` warns about it.

## Limits and non-goals

- Path globs classify paths, not content: a content file that adds a new
  external script is still content. A content tripwire is a follow-up.
- Ride inputs (ceremony, intake, validation and review status) come from the
  checkout's STATE focus and are not yet bound to the PR being judged
  (follow-up `fu-merge-policy-ride-pr-binding`).
- `?` in a glob matches one UTF-16 unit, not one character
  (follow-up `fu-merge-policy-glob-unicode-question`); decision timestamps
  must be whole seconds (follow-up `fu-merge-policy-decision-ref-frac-ts`).
- A delegated approver's review body is read as GitHub returns it on each
  `--check`; editing a review body changes the verdict, and an edit does
  not move the review's commit.
- Only Claude Code sessions are mechanically guarded by the hook; other
  harnesses must call `--check` themselves. Markers are a guardrail, not a
  security boundary; server-side branch protection remains the real one.

## Links

- Request: docs/rfc/RFC-0015-configurable-merge-policy-lanes.md (goodwind-cz/aai#429)
- Spec: docs/specs/SPEC-0207-spec-configurable-merge-policy-lanes.md
- Relayed approval (goodwind-cz/aai#474):
  docs/specs/SPEC-0299-spec-delegated-requester-approval.md
- Validation evidence: docs/ai/reports/VALIDATION-20261005T0412Z-configurable-merge-policy-lanes.md
