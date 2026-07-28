---
id: spec-platform-portable-pr
type: spec
number: 103
status: done
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0085-platform-portable-pr.md
  rfc: null
  pr:
    - 185
  commits:
    - e411d52865466082f0721160d8bfcfdcba057434
---

# Spec — Platform-portable PR ceremony: GitHub/Azure detection + internal review fallback when no external reviewers exist

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0085-platform-portable-pr.md
- Decision records: none
- Technology contract: docs/TECHNOLOGY.md

## Summary
`.aai/SKILL_PR.prompt.md` steps 5/5d were GitHub-bound (`gh pr create`,
`gh api pulls/N/comments`) and assumed auto-assigned reviewer bots. On any
other git host (Azure Repos first, GitLab/Bitbucket/bare later) the ceremony
either fails outright at PR creation or, if ported naively, the 5d bot sweep
would silently no-op (no auto reviewers exist there). This change adds a
deterministic platform probe (`.aai/scripts/pr-platform.mjs`), branches
SKILL_PR's step 5 on its verdict (github / azure / GENERIC MODE), and makes
step 5d's internal-review fallback a REQUIRED, not optional, substitute for
the bot layer whenever the platform demonstrably has none — with findings
published back to the platform as PR threads exactly like a bot's would be,
per the operator's 2026-07-28 direction.

## Implementation strategy
- Strategy: tdd
- Rationale: the deliverable is a small deterministic classifier with a
  closed output enum (github/azure/unknown/none) — each host pattern is a
  concrete RED-then-GREEN fixture — plus prose wiring in SKILL_PR pinned by
  grep-contract tests. Both are provable by fixture-driven tests without any
  live external service; RED-first evidence proves the suite and the prompt
  pins genuinely discriminate before the fix, and pass after.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: small, clearly scoped new script + prompt-prose edit +
  one new test suite + governance ledger true-up; no protected L3 surface
  (state engine, allocator, guards, workflow canon — see
  `protected_paths_l3` in docs/ai/docs-audit.yaml, which does not name
  `pr-platform.mjs` or `SKILL_PR.prompt.md`) is touched; already on a
  dedicated branch (feat/platform-portable-pr).
- User decision: inline
- Base ref: main
- Worktree branch/path: feat/platform-portable-pr (current checkout)
- Inline review scope: .aai/scripts/pr-platform.mjs, .aai/SKILL_PR.prompt.md,
  .aai/system/PROFILES.yaml, tests/skills/test-aai-pr-platform.sh,
  tests/skills/suite-map.yaml, tests/skills/lib/prompt-diet-ledger.sh,
  tests/skills/test-aai-prompt-diet.sh,
  docs/specs/SPEC-0103-spec-platform-portable-pr.md,
  docs/issues/CHANGE-0085-platform-portable-pr.md

## Acceptance Criteria Mapping
- Maps to: CHANGE-0085-platform-portable-pr AC-001
- Spec-AC-01: `.aai/scripts/pr-platform.mjs` reads `git remote get-url
  origin` (overridable via `--remote-url`, cwd-independent) and
  deterministically classifies it github / azure / unknown — github.com
  (https and ssh, incl. `git@github.com:` and `ssh://git@github.com/`),
  dev.azure.com + ssh.dev.azure.com + legacy `*.visualstudio.com` as azure,
  every other host as unknown (never a guess) — printing `PLATFORM <value>
  remote=<sanitized-url>` and exit 0; no `origin` remote at all prints
  `PLATFORM none` and exit 0; an unknown flag exits 2 and writes nothing to
  stdout; `--json` emits exactly `{platform, remote} (remote always sanitized)`.
  - Verification: `bash tests/skills/test-aai-pr-platform.sh` TEST-001..014;
    live `node .aai/scripts/pr-platform.mjs` on this repo (expect
    `PLATFORM github`).
- Maps to: CHANGE-0085-platform-portable-pr AC-002
- Spec-AC-02: `.aai/SKILL_PR.prompt.md` step 5 runs the probe FIRST (a named
  "PLATFORM GATE") and branches: `github` keeps the existing `gh pr create`
  path; `azure` documents the exact `az repos pr create` / `az repos pr
  reviewer add` / `pullRequestThreads via az devops invoke` command set (step 5d) and notes
  Azure's branch-policy gate job; `unknown`/`none` route to GENERIC MODE
  (Spec-AC-05).
  - Verification: `bash tests/skills/test-aai-pr-platform.sh` TEST-015/016
    (grep-contract pins on the PLATFORM GATE heading, probe invocation, and
    the four `az repos pr ...` command names).
- Maps to: CHANGE-0085-platform-portable-pr AC-003
- Spec-AC-03: SKILL_PR step 5d's reviewer-fallback contract is pinned —
  whenever the platform has no external reviewer bots (Azure default;
  detectable = zero bot-authored threads AND platform != github), dispatching
  `.aai/SKILL_CODE_REVIEW.prompt.md` on the FINAL PR diff is REQUIRED before
  any merge-readiness claim; the empty-sweep shortcut ("no bot findings")
  stays legal only on a platform WITH a bot layer.
  - Verification: `bash tests/skills/test-aai-pr-platform.sh` TEST-017
    (grep-contract pin on the REQUIRED-before-merge-readiness clause and the
    `platform != github` detection condition).
- Maps to: CHANGE-0085-platform-portable-pr Additional operator requirement 1
  (2026-07-28: PR-thread publication of internal findings)
- Spec-AC-04: internal-review findings from the Spec-AC-03 fallback are
  published as PR THREADS via the platform API (`gh api
  repos/<owner>/<repo>/pulls/<n>/comments` on GitHub, `pullRequestThreads via az devops invoke --id <pr-id>` on Azure) with a closing reply citing the fixing
  commit — the same audit trail whether the reviewer was a bot or the
  internal role — and "internal review substituted for absent bot layer" is
  recorded in the PR description.
  - Verification: `bash tests/skills/test-aai-pr-platform.sh` TEST-017
    (same grep pass also asserts the closing-reply clause and the PR
    description marker; the PR-body template in step 5 carries the marker
    too).
- Maps to: CHANGE-0085-platform-portable-pr Additional operator requirement 2
  (GENERIC MODE for any other git hosting)
- Spec-AC-05: for `unknown`/`none` platforms (GitLab, Bitbucket, bare, no
  remote), SKILL_PR skips platform PR mechanics entirely, makes
  `.aai/SKILL_CODE_REVIEW.prompt.md` on the final diff MANDATORY, writes the
  verdict + findings to a `docs/ai/reports/VALIDATION-<ts>-<slug>.md`-style
  report plus spec dispositions, leaves merge to the owner's process, and
  ends the ceremony with the loud line "platform PR API unavailable —
  internal review substituted, merge is yours." The merge boundary (step 6,
  `gh pr merge` / `az repos pr merge` — never invoked) is unchanged.
  - Verification: `bash tests/skills/test-aai-pr-platform.sh` TEST-018
    (grep-contract pin on the verbatim loud line and the report-path
    naming).
- Maps to: CHANGE-0085-platform-portable-pr Constraints/Risks (Az CLI not
  live-testable here)
- Spec-AC-06 (DEFERRED — see Acceptance Criteria Status): the documented
  `az repos pr create` / `az repos pr reviewer add` / `pullRequestThreads via az devops invoke` / `pullRequestThreads via az devops invoke` command forms behave as documented
  against a REAL Azure DevOps remote (argument names, exit codes, thread
  JSON shape). Not provable in this repo — no Azure remote exists to probe
  live, and `az` is not installed in this environment. Command forms were
  verified against the Azure CLI `az repos pr`/the pullRequestThreads REST resource
  reference documentation only.
  - Verification (future): first live Azure adoption — a real `az repos pr
    create` + `pullRequestThreads via az devops invoke`/`thread list` round trip, logged
    under `docs/ai/reports/` and linked back to this AC.

## Constitution deviations

None.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | pr-platform.mjs deterministic classifier | done | docs/ai/tdd/green-20260728T081246Z-pr-platform.log | — | 18/18 TEST-001..018 green |
| Spec-AC-02 | SKILL_PR PLATFORM GATE + az command set | done | docs/ai/tdd/green-20260728T081246Z-pr-platform.log | — | TEST-015/016 grep pins |
| Spec-AC-03 | 5d reviewer-fallback REQUIRED contract | done | docs/ai/tdd/green-20260728T081246Z-pr-platform.log | — | TEST-017 grep pin |
| Spec-AC-04 | Findings published as PR threads + closing reply | done | docs/ai/tdd/green-20260728T081246Z-pr-platform.log | — | TEST-017 grep pin (shared with Spec-AC-03) |
| Spec-AC-05 | GENERIC MODE skip + mandatory internal review + loud line | done | docs/ai/tdd/green-20260728T081246Z-pr-platform.log | — | TEST-018 grep pin |
| Spec-AC-06 | Live Azure CLI command-shape proof | deferred | — | 2026-08-15 | No Azure remote available in this repo/environment; evidence contract = first live Azure adoption round trip logged under docs/ai/reports/ |

## Implementation plan
- `.aai/scripts/pr-platform.mjs` (new): zero-dep CLI. `readOriginUrl()` runs
  `git remote get-url origin` (cwd-independent — git itself walks up from
  cwd); `--remote-url` overrides for tests/dry-runs. `extractHost()` handles
  both scp-like (`[user@]host:path`) and scheme URLs (`new URL()`).
  `classify(host)` is a closed if/else — github.com(.sub)?, {dev,ssh.dev}
  .azure.com, (.sub)?.visualstudio.com, else unknown. `sanitize()` strips
  HTTPS basic-auth userinfo only (SSH `user@host:` identities are not
  secrets). Text and `--json` output modes; unknown flag -> usage() -> exit
  2, nothing printed (the house convention shared with branch-guard.mjs /
  docs-lock.mjs / reconcile-telemetry.mjs).
- `.aai/SKILL_PR.prompt.md`: step 5 retitled "PLATFORM GATE + PUSH + PR",
  runs the probe, branches gh/az/GENERIC MODE inline (no new numbered step,
  keeping the ceremony's step count stable); PR body template gains one
  Azure/no-bot-layer note. Step 5d gains a REVIEWER-FALLBACK CONTRACT bullet
  between the existing bot-sweep bullet and the CI-re-run bullet.
- `.aai/system/PROFILES.yaml`: `pr-platform.mjs` added to `core` (mirrors
  `select-suites.mjs` — a workflow-engine script SKILL_PR's gate depends on
  directly, not a reporting/publishing extra).
- `tests/skills/suite-map.yaml`: new `aai-pr-platform` row (globs:
  `pr-platform.mjs`, `SKILL_PR.prompt.md`; the suite's own test file matches
  implicitly per the selector's documented convention).
- `tests/skills/lib/prompt-diet-ledger.sh` /
  `tests/skills/test-aai-prompt-diet.sh`: one itemized `JUSTIFIED_ADDITIONS`
  entry (+3277 B, the measured SKILL_PR.prompt.md growth) and the TEST-012
  pinned literal bumped -15485 -> -12208, landing headroom back at exactly
  605/2048 — the same steady-state as before this scope (RED-first: with the
  growth present but uncredited, TEST-010 breaches the byte floor; GREEN
  after the ledger entry + pin bump).

## Test Plan
For each Spec-AC, enumerate concrete tests:

| Test ID | Spec-AC | Type | File path (expected) | Description | Status |
|---------|------------|------------|----------------------------|------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-pr-platform.sh | Host classification matrix (github https/ssh/ssh-url, azure https/ssh current + legacy visualstudio.com, gitlab/bitbucket -> unknown), no-remote real fixture -> none, --json shape, exit codes (0 classified / 2 unknown-flag empty-stdout), cwd-independence, credential sanitization | green |
| TEST-002 | Spec-AC-02 | unit | tests/skills/test-aai-pr-platform.sh | Grep-contract: SKILL_PR names a PLATFORM GATE running pr-platform.mjs + the 4 az repos pr command names | green |
| TEST-003 | Spec-AC-03 | unit | tests/skills/test-aai-pr-platform.sh | Grep-contract: 5d REQUIRED-before-merge-readiness clause + platform != github detection | green |
| TEST-004 | Spec-AC-04 | unit | tests/skills/test-aai-pr-platform.sh | Grep-contract: closing-reply-citing-fixing-commit clause + PR-description marker sentence | green |
| TEST-005 | Spec-AC-05 | unit | tests/skills/test-aai-pr-platform.sh | Grep-contract: verbatim GENERIC MODE loud line + docs/ai/reports/VALIDATION- report path | green |
| TEST-006 | Spec-AC-01..05 | unit | tests/skills/test-aai-prompt-diet.sh | Ledger true-up entry + TEST-012 pinned literal keep TEST-010 byte floor/headroom green at 605/2048 | green |
| TEST-007 | Spec-AC-06 | manual | n/a | Live az repos pr create/reviewer add/thread list/thread create round trip against a real Azure DevOps remote | pending |

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- TEST-007 stays `pending` by design — Spec-AC-06 is DEFERRED, not
  implementable without a live Azure remote; it is not a gap in this scope's
  own delivery.

## Verification
- `bash tests/skills/test-aai-pr-platform.sh` (new suite, TEST-001..018 internal).
- `bash tests/skills/test-aai-prompt-diet.sh` (ledger + TEST-012 pin).
- `bash tests/skills/test-aai-layer-profiles.sh` (PROFILES.yaml classification).
- `bash tests/skills/test-aai-hygiene-pack.sh` (suite-map.yaml row pin).
- `bash tests/skills/test-aai-suite-select.sh` (selector still resolves cleanly).
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0103-spec-platform-portable-pr.md`
- `node .aai/scripts/docs-audit.mjs --gate spec-platform-portable-pr --no-event`
- Evidence artifacts: `docs/ai/tdd/red-20260728T081118Z-pr-platform.log`,
  `docs/ai/tdd/green-20260728T081246Z-pr-platform.log`,
  `docs/ai/tdd/red-20260728T081401Z-prompt-diet-ledger-bump.log`,
  `docs/ai/tdd/green-20260728T081414Z-prompt-diet-ledger-bump.log`.
- PASS criteria: TEST-001..006 green, TEST-007 deferred (not a blocker), all
  Spec-AC in a terminal status (done x5, deferred x1 with future Review-By).

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: spec-platform-portable-pr
- Spec-AC and TEST-xxx links: see Acceptance Criteria Status / Test Plan above
- command: `bash tests/skills/test-aai-pr-platform.sh` /
  `bash tests/skills/test-aai-prompt-diet.sh`
- exit code: 0 (both, GREEN)
- evidence path: docs/ai/tdd/{red,green}-*-pr-platform.log,
  docs/ai/tdd/{red,green}-*-prompt-diet-ledger-bump.log
- commit SHA: not yet committed (single-writer TDD/Planning pass; commit is
  the PR ceremony's job)

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
