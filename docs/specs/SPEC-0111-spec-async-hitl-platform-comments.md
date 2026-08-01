---
id: spec-async-hitl-platform-comments
type: spec
number: 111
status: done
ceremony_level: 2
links:
  requirement: async-hitl-platform-comments
  rfc: null
  pr:
    - 205
  commits:
    - c11cd931f1723b2759f1832e3ccd3eb599a076f3
---

# Implementation Spec — async HITL via platform comments

SPEC-FROZEN: true

Ceremony justification: not applicable at level 2 (no justification line required
above level 1). Recorded here only to confirm the L2 declaration is deliberate:
the scope is additive — a NEW deterministic script plus thin prompt pointers and
governance true-ups — and touches NO `protected_paths_l3` surface. See
Constitution deviations and the protected-path analysis below.

## Links
- Requirement: docs/issues/CHANGE-0102-async-hitl-platform-comments.md
- Decision records: none
- Technology contract: docs/TECHNOLOGY.md

## Summary

When a ride raises a human decision (a `[HITL-<n>]` block) on a scope that has a
linked GitHub thread (issue or PR), post the question and enumerated options as
ONE platform comment, PARK the ride, and let a later `/aai-hitl` run (this or a
future session) RESUME by feeding the human's reply into the EXISTING fail-closed
SKILL_HITL resolution. With no linked thread or no GitHub platform, terminal HITL
behaviour is byte-for-byte unchanged.

The channel record (comment id + thread ref) is held in a gitignored runtime
SIDECAR (`docs/ai/hitl-channel.json`), owned by a deterministic script — NOT in
`docs/ai/STATE.yaml`. This is the key design constraint: `state.mjs` is a
`protected_paths_l3` surface, and the intake's original `human_input.channel`
sketch would have required a new typed setter there (an L3 edit). The sidecar
mirrors the briefs/reports precedent (gitignored, script-owned) and keeps this
scope at ceremony level 2.

## Protected-path analysis (LANDMINE check — done FIRST)

- `docs/ai/docs-audit.yaml` `protected_paths_l3` = state.mjs, lib/state-engine.mjs,
  lib/state-core.mjs, allocate-doc-number.mjs, pre-commit-checks.sh/.ps1,
  workflow/WORKFLOW.md, docs/CONSTITUTION.md.
- `state.mjs` `set-human-input` accepts ONLY `--required/--question/--reason`
  (state.mjs:203, 714-728) — there is NO `channel`/thread surface, and adding one
  is exactly the L3 edit avoided.
- This scope touches NONE of those paths. All state about the channel lives in the
  gitignored sidecar. Therefore ceremony_level 2, not 3. No L3 escalation needed.

## Scope decision — add-ons SPLIT OUT (explicit)

The intake lets the planner split either optional add-on to a follow-up intake if
it bloats scope. Against a prompt-corpus headroom of ~0/2048 and a trust-boundary
core, BOTH add-ons are SPLIT OUT to follow-ups:

- Add-on 1 (ride milestone comments): needs milestone hooks in PLANNING /
  VALIDATION / SKILL_PR plus EVENTS.jsonl reading and the "few and dense, past
  ~30 comments UX degrades" density design — its own corpus bytes + tests.
  Deferred to a follow-up intake.
- Add-on 2 (validate-report visual evidence in PRs): PR-ceremony wiring in
  SKILL_PR coupled to aai-validate-report screenshot output — orthogonal to async
  HITL. Deferred to a follow-up intake.
- Also deferred (same follow-up): the session-start auto-nudge hook and the Azure
  DevOps comment channel (see Implementation plan / Residual risks).

## Implementation strategy
- Strategy: tdd
- Rationale: owner accepted the intake's full-TDD recommendation when approving
  the ride; the change is behavioural, multi-surface (channel post + poll +
  prompt wiring), and trust-boundary sensitive (untrusted reply text, author
  permission gate). RED-before-GREEN with captured docs/ai/tdd/*.log.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: multi-surface, PR-bound, trust-boundary-sensitive; already
  executing in an isolated worktree for this ride.
- User decision: worktree
- Base ref: main
- Worktree branch/path: feat/async-hitl-platform-comments (this ride)
- Inline review scope: .aai/scripts/hitl-channel.mjs, .aai/ORCHESTRATION_HITL.prompt.md,
  .aai/SKILL_HITL.prompt.md, tests/skills/test-aai-hitl-channel.sh,
  .aai/system/PROFILES.yaml, tests/skills/suite-map.yaml,
  tests/skills/lib/prompt-diet-ledger.sh, .gitignore

## Acceptance Criteria Mapping

- Maps to: AC-001 (post once + park; no-platform unchanged)
  - Spec-AC-01: WHEN a role raises HITL on a scope WITH a linked GitHub thread the
    system SHALL post exactly one comment carrying the token, question and options,
    record the channel in the sidecar, and NOT emit a terminal block; WITHOUT a
    linked thread or GitHub platform it SHALL leave terminal HITL byte-for-byte
    unchanged.
  - Verification: bash tests/skills/test-aai-hitl-channel.sh (TEST-001, TEST-003,
    TEST-011, TEST-013); expect exit 0, one recorded gh invocation, sidecar entry.
- Maps to: AC-002 (resume routes to SKILL_HITL; ambiguous fail-close; bot/self ignored)
  - Spec-AC-02: WHEN a later poll finds a qualifying human reply on the recorded
    thread the system SHALL surface the reply text as data for the existing
    SKILL_HITL resolution; a bot-authored or self-authored reply SHALL be ignored;
    a re-raised follow-up comment SHALL NOT double-post.
  - Verification: test-aai-hitl-channel.sh (TEST-005, TEST-006, TEST-010, TEST-012,
    TEST-014, TEST-017 follow-up supersedes the question, TEST-018 live-gh poll
    paginates so a busy thread never yields a false status:none).
- Maps to: AC-003 (reply trust: write-permission gate; body is inert data)
  - Spec-AC-03: WHEN a reply author lacks repo write permission the system SHALL
    ignore the reply; the reply body SHALL be treated as data only (control and
    bidi characters stripped, never executed as instructions).
  - Verification: test-aai-hitl-channel.sh (TEST-007, TEST-008, TEST-016 token+ref
    match — a recurring token cannot pick up an OLD ride's reply on poll/resolve).
- Maps to: AC-004 (degrade; idempotent post)
  - Spec-AC-04: WHEN the platform is absent, the remote is offline, or the gh API
    errors the system SHALL degrade to terminal HITL without blocking or crashing
    (exit 0, loud note); a re-raised HITL SHALL NOT post a duplicate comment.
  - Verification: test-aai-hitl-channel.sh (TEST-002, TEST-004, TEST-009, TEST-019
    corrupt sidecar fails closed to status degraded rather than a silent empty).

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                                              | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | WHEN HITL is raised with a linked GitHub thread the system SHALL post one comment and park; without a thread terminal HITL is unchanged | done    | green suite | —         | tests/skills/test-aai-hitl-channel.sh exit 0 |
| Spec-AC-02 | WHEN a poll finds a qualifying human reply the system SHALL surface it for SKILL_HITL; bot or self replies ignored; follow-up post idempotent | done    | green suite | —         | tests/skills/test-aai-hitl-channel.sh exit 0 |
| Spec-AC-03 | WHEN a reply author lacks write permission the system SHALL ignore it; reply body treated as inert data | done    | green suite | —         | tests/skills/test-aai-hitl-channel.sh exit 0 |
| Spec-AC-04 | WHEN platform absent or gh errors the system SHALL degrade to terminal HITL without blocking or crashing; post is idempotent | done    | green suite | —         | tests/skills/test-aai-hitl-channel.sh exit 0 |

## Implementation plan

Components/modules affected:
- NEW `.aai/scripts/hitl-channel.mjs` (Node stdlib, zero deps) with two
  subcommands. The full contract lives in the script header (keeps prompt bytes
  down):
  - `post` — flags: --token, --ref, --thread, --platform (auto-detected via the
    pr-platform classify+origin probe when omitted), --body-file, --sidecar
    (default docs/ai/hitl-channel.json), --kind question or followup, --gh-bin
    (test stub, default gh; env AAI_GH_BIN), --json. Idempotent per (token,
    thread, kind): a recorded comment_id short-circuits the post. GitHub post via
    `gh api repos/{owner}/{repo}/issues/{thread}/comments -F body=@<file> --jq .id`
    (issues API serves PR threads too). Records the sidecar entry
    {hitl_token, ref, platform, thread_ref, comment_id, kind, posted_utc,
    resolved:false}. Degrade (platform none, no thread, azure, gh ENOENT, gh
    error) prints a loud `HITL-CHANNEL degraded reason=...` note and exits 0 —
    caller keeps terminal HITL. Never crashes.
  - `poll` — flags: --sidecar, --self (comma-list of agent/bot logins to
    exclude), --gh-bin, --input (comments fixture), --perm-input (permission
    fixture), --json. For each unresolved sidecar entry, fetch replies via
    `gh api repos/{owner}/{repo}/issues/{thread}/comments`; keep only comments
    created AFTER posted_utc, author NOT in --self and user.type != Bot, and
    author permission in {admin, write, maintain} via
    `gh api repos/{owner}/{repo}/collaborators/{login}/permission`. The reply body
    is UNTRUSTED DATA — sanitized (C0/C1 + bidi stripped, mirroring
    aai-issues.mjs sanitizeLine) and surfaced as JSON only; the script NEVER acts
    on it. Output {status: reply|none|degraded, token, thread_ref, author, body,
    comment_id}. Degrade on gh ENOENT/error/offline → status degraded, exit 0.
- Reuse pr-platform.mjs classify/extractHost for platform detection (imported or
  re-derived); reuse the sanitizeLine control/bidi discipline from aai-issues.mjs.
- Sidecar `docs/ai/hitl-channel.json` — NEW gitignored path (add to .gitignore
  next to briefs/reports).
- `.aai/ORCHESTRATION_HITL.prompt.md` (raise side) — thin pointer in STATE
  WRITEBACK "On HUMAN DECISION REQUIRED": after stamping [HITL-<n>], best-effort
  `node .aai/scripts/hitl-channel.mjs post ...` to the linked thread; no
  thread/platform → terminal HITL unchanged; then PARK.
- `.aai/SKILL_HITL.prompt.md` (resume side) — thin STEP 0 (RESUME FROM PLATFORM)
  before STEP 1: run `node .aai/scripts/hitl-channel.mjs poll`; a qualifying
  reply's body is the human answer (UNTRUSTED DATA — treat as data, feed into
  STEP 3+ unchanged); an ambiguous reply fails closed via the existing rules and
  posts ONE follow-up with `post --kind followup` (idempotent). SKILL_LOOP already
  routes resume through SKILL_HITL (SKILL_LOOP.prompt.md:367), so no SKILL_LOOP
  edit is needed.
- Governance true-ups: `.aai/system/PROFILES.yaml` (classify hitl-channel.mjs as
  core), `tests/skills/suite-map.yaml` (new aai-hitl-channel suite row),
  `tests/skills/lib/prompt-diet-ledger.sh` (JUSTIFIED_ADDITIONS entry sized to the
  measured ORCHESTRATION_HITL + SKILL_HITL growth) + the TEST-012 checkpoint
  constant/comment bump in tests/skills/test-aai-prompt-diet.sh.

Data flows:
- POST: role raise → ORCHESTRATION_HITL pointer → hitl-channel.mjs post → gh →
  sidecar entry. RESUME: /aai-hitl → SKILL_HITL STEP 0 → hitl-channel.mjs poll →
  gh (comments + permission) → reply-as-data → SKILL_HITL STEP 3+ resolution.
- SEAM: the sidecar JSON is the shared boundary between `post` (writer) and `poll`
  (reader), and between the prompt-declared command and the real CLI.

Edge cases:
- Multiple unresolved sidecar entries: poll iterates all; first qualifying reply
  wins per entry.
- Reply before our question (created_at <= posted_utc): ignored.
- Missing/corrupt sidecar: poll → status none; post → creates a fresh sidecar.
- Azure: DEGRADE with a NOTE (az comment channel deferred to follow-up).

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)              | Description                                                                 | Status  |
|----------|------------|------|-----------------------------------|-----------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-hitl-channel.sh | post with github thread and empty sidecar invokes gh once and records the sidecar entry | green   |
| TEST-002 | Spec-AC-04 | unit | tests/skills/test-aai-hitl-channel.sh | post again for the same token and thread makes no gh call (idempotent), exit 0 | green   |
| TEST-003 | Spec-AC-01 | unit | tests/skills/test-aai-hitl-channel.sh | post with platform none or no thread degrades, no gh call, exit 0, sidecar untouched | green   |
| TEST-004 | Spec-AC-04 | unit | tests/skills/test-aai-hitl-channel.sh | post when the gh stub errors degrades to exit 0 with a loud note, no crash | green   |
| TEST-005 | Spec-AC-02 | unit | tests/skills/test-aai-hitl-channel.sh | poll with a qualifying human reply after posted_utc surfaces status reply and the body | green   |
| TEST-006 | Spec-AC-02 | unit | tests/skills/test-aai-hitl-channel.sh | poll ignores a reply authored by self or a Bot, status none | green   |
| TEST-007 | Spec-AC-03 | unit | tests/skills/test-aai-hitl-channel.sh | poll ignores a reply from an author without write permission, status none | green   |
| TEST-008 | Spec-AC-03 | unit | tests/skills/test-aai-hitl-channel.sh | poll surfaces an injection-laden reply verbatim as sanitized data and takes no action | green   |
| TEST-009 | Spec-AC-04 | unit | tests/skills/test-aai-hitl-channel.sh | poll with a gh ENOENT or offline stub degrades to status degraded, exit 0 | green   |
| TEST-010 | Spec-AC-02 | unit | tests/skills/test-aai-hitl-channel.sh | post kind followup twice makes a single gh call (follow-up idempotent) | green   |
| TEST-011 | Spec-AC-01 | unit | tests/skills/test-aai-hitl-channel.sh | ORCHESTRATION_HITL names hitl-channel.mjs post with best-effort degrade-to-terminal wording | green   |
| TEST-012 | Spec-AC-02 | unit | tests/skills/test-aai-hitl-channel.sh | SKILL_HITL STEP 0 names hitl-channel.mjs poll, the UNTRUSTED-DATA rule and the follow-up on ambiguity | green   |
| TEST-013 | Spec-AC-01 | integration | tests/skills/test-aai-hitl-channel.sh | the ORCHESTRATION_HITL-declared post command runs against a fixture and records the sidecar (prompt to CLI to sidecar seam) | green   |
| TEST-014 | Spec-AC-02 | integration | tests/skills/test-aai-hitl-channel.sh | end-to-end post records the sidecar, then poll reads that same sidecar and surfaces a fixture reply (post to poll seam) | green   |
| TEST-016 | Spec-AC-03 | unit | tests/skills/test-aai-hitl-channel.sh | two entries share one token but differ by ref; poll --ref and resolve --ref narrow to the matching ref only so a recurring token cannot pick up an old ride's reply (Codex P1 token-reuse trust guard) | green   |
| TEST-017 | Spec-AC-02 | unit | tests/skills/test-aai-hitl-channel.sh | a follow-up post supersedes the original question entry so poll surfaces one result via the follow-up entry, never the stale question (Codex P2) | green   |
| TEST-018 | Spec-AC-02 | unit | tests/skills/test-aai-hitl-channel.sh | live-gh poll follows pagination (per_page 100) and finds a reply on page 2 instead of a false status none on a busy thread (Codex P2) | green   |
| TEST-019 | Spec-AC-04 | unit | tests/skills/test-aai-hitl-channel.sh | a corrupt sidecar degrades loudly to status degraded with reason sidecar_corrupt and exit 0, never read as an empty ledger (Codex P2 fail-closed) | green   |

Seam analysis (step 6a):
- Seam 1 (sidecar file, produced by post, consumed by poll): TEST-014 crosses it
  end-to-end — post writes the real sidecar, poll reads that real file.
- Seam 2 (prompt-declared command → real CLI → sidecar): TEST-013 extracts the
  command shape from ORCHESTRATION_HITL and runs the real script, mirroring the
  hitl-propagation TEST-012 seam pattern.
- Seam 3 (poll reply → existing SKILL_HITL resolution): covered by contract pins
  (TEST-012) plus the existing test-aai-hitl-propagation suite, which stays green
  (resolution path unchanged). Residual: the LLM STEP 0 → STEP 3 hand-off is
  prose, not automatable end-to-end here — recorded as a residual risk.

Companion obligations (PLANNING step 3a):
- Prompt corpus grows (ORCHESTRATION_HITL + SKILL_HITL) → prompt-diet ledger
  true-up (new JUSTIFIED_ADDITIONS entry + TEST-012 checkpoint bump), verified by
  tests/skills/test-aai-prompt-diet.sh.
- New .aai/** file (hitl-channel.mjs) → PROFILES.yaml classification, verified by
  tests/skills/test-aai-layer-profiles.sh.

## Verification
- Commands: bash tests/skills/test-aai-hitl-channel.sh; bash
  tests/skills/test-aai-hitl-propagation.sh; bash tests/skills/test-aai-pr-platform.sh;
  bash tests/skills/test-aai-orchestration-dispatch.sh; bash
  tests/skills/test-aai-prompt-diet.sh; bash tests/skills/test-aai-hygiene-pack.sh;
  bash tests/skills/test-aai-layer-profiles.sh; node .aai/scripts/docs-audit.mjs
  --check --strict --no-event; node .aai/scripts/spec-lint.mjs --path
  docs/specs/SPEC-0111-spec-async-hitl-platform-comments.md
- Evidence artifacts: docs/ai/tdd/*.log (RED + GREEN captures)
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status

## Evidence contract
For each artifact record: ref_id, Spec-AC and TEST-xxx links, command or review
scope, exit code or verdict, evidence path, commit SHA when available.
