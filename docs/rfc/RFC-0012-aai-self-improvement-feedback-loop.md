---
id: aai-self-improvement-feedback-loop
type: rfc
number: 12
status: accepted
links:
  spec: null
  pr: []
  commits: []
---

# RFC (Decision Proposal)

## Context

- Problem or opportunity:
  - AAI skills can discover defects in their own prompts, wrappers, scripts, or
    workflow contracts while running in AAI or a downstream project.
  - Manual reporting loses evidence. Directly creating a GitHub issue for every
    error would create noise, duplicates, and privacy risks.
  - AAI needs a portable feedback loop that distinguishes AAI-owned defects
    from project failures, aggregates repeated evidence, and promotes only
    actionable findings to the upstream repository.
- Drivers/constraints:
  - Preserve the zero-runtime-dependency and cross-platform contracts.
  - Work in vendored downstream installations, including private projects.
  - Be local-first and explicit about external writes.
  - Never upload raw conversations, logs, source code, credentials, usernames,
    absolute paths, or repository identities by default.
  - Keep the existing rule that agents may open PRs but only an operator merges.
  - Treat GitHub issue content as untrusted data, not agent instructions.

### External patterns reviewed

- Aider provides an explicit `/report` command that opens a GitHub issue. It is
  a useful escape hatch, but depends on the user recognizing report-worthy
  failures and does not aggregate runs
  ([Aider commands](https://aider.chat/docs/usage/commands.html)).
- GitHub Issue Forms provide structured fields, validation, labels, and an
  explicit duplicate-search acknowledgement
  ([GitHub Issue Forms](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms)).
- Sentry groups similar events by fingerprints and recommends filtering
  unactionable events before escalation. The transferable principle is to keep
  observations separate from issues
  ([Sentry developer guide](https://docs.sentry.io/pdfs/developer-quick-reference-guide.pdf)).
- Renovate aggregates many candidates into one Dependency Dashboard issue and
  supports approval before work proceeds
  ([Renovate Dependency Dashboard](https://docs.renovatebot.com/key-concepts/dashboard/)).
- LangSmith routes selected error or low-score traces into rubric-based
  annotation queues and turns reviewed failures into durable evaluation
  examples
  ([LangSmith annotation queues](https://docs.langchain.com/langsmith/annotation-queues),
  [LangSmith assertions](https://docs.langchain.com/langsmith/assertions)).
- GitHub recommends least-privilege workflow tokens; issue collection and code
  remediation should use separate identities
  ([GitHub secure use](https://docs.github.com/en/actions/reference/security/secure-use),
  [GITHUB_TOKEN guidance](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token)).

## Proposal

- Recommended option:
  - Introduce an **AAI Friction Feedback Loop** with four separated stages:
    local capture, intelligent triage/upsert, upstream processing, and verified
    improvement delivery.

### 1. Local capture shared by every skill

- Define one canonical `AAI_FRICTION_PROTOCOL` referenced by every universal
  skill prompt. Enforce this seam in the skill test suite; thin platform
  wrappers must reference it rather than duplicate it.
- Record a candidate only for evidence of an AAI-owned failure:
  - contradictory, ambiguous, or impossible AAI instructions;
  - missing or invalid AAI-owned files, commands, templates, or transitions;
  - deterministic failure of an AAI script or workflow contract;
  - repeated recovery work caused by an AAI abstraction leak;
  - a human correction identifying an AAI prompt or skill defect;
  - a documented downstream or cross-platform contract violation.
- Exclude expected test failures, normal target-project bugs, invalid user
  input, HITL pauses, transient provider/network failures, unavailable optional
  tools, and cosmetic preferences unless recurrence shows a systemic problem.
- Capture through a dependency-free Node CLI such as:
  `node .aai/scripts/aai-friction.mjs record --input <sanitized-json>`.
  It writes atomically to an untracked project-local spool. Capture has no
  GitHub token and performs no network I/O.
- Each observation contains schema version, timestamp, AAI pin, skill and phase,
  failure class, expected/observed behavior, minimal reproduction, workaround,
  impact, confidence, recurrence evidence, safe evidence references, redaction
  status, and a deterministic fingerprint.
- Capture failure must never replace or mask the skill's original result.

### 2. Intelligent triage and GitHub upsert

- Add portable `/aai-feedback-triage`. It can run explicitly, from
  `/aai-wrap-up`, after a failed AAI skill, or at another safe session boundary.
  Do not require a resident background daemon.
- Triage applies:
  1. hard gates for AAI ownership, actionability, sanitization, and either
     reproducibility or meaningful recurrence;
  2. a documented score for impact, confidence, recurrence, and workaround
     cost;
  3. fingerprint clustering and upstream open/closed issue search;
  4. a reporting budget and cooldown.
- Suggested decisions:
  - below threshold: retain locally for aggregation, then expire;
  - at threshold: prepare a review candidate;
  - security or data-loss risk: alert the operator, never auto-publish details;
  - open matching fingerprint: add only materially new evidence;
  - fixed in a newer AAI release: recommend updating first;
  - recurring on/after the fixed release: report a linked regression.
- Put a stable marker such as
  `<!-- aai-friction:v1:<fingerprint> -->` in each upstream issue. Do not rely
  on title similarity for deduplication.
- Configure `.aai/feedback.yaml` with:
  - `local` (default): capture and summarize only;
  - `review`: prepare the exact issue and require approval for the write;
  - `auto`: opt-in upsert only for sanitized, high-confidence, non-security
    findings that pass every gate.
- Pin the destination repository explicitly. The AAI template can suggest
  `goodwind-cz/aai`; forks and other frameworks can set their own destination,
  taxonomy, thresholds, and labels.
- Start with a budget of at most three new issues per installation per seven
  days. Suppress updates unless they add a version, platform, reproduction, or
  impact level.

### 3. Upstream issue-processing skill

- Add `/aai-feedback-maintainer` for the upstream framework repository. Process
  only issues carrying the machine marker and maintainer-recognized
  `aai-feedback` label.
- Use the visible lifecycle:
  `needs-triage -> needs-info | accepted | duplicate | rejected`, then
  `reproduced -> fix-ready -> pr-open`.
- The processor:
  - validates schema and sanitization;
  - deduplicates again by marker;
  - reproduces in a disposable fixture/worktree against the reported AAI pin;
  - classifies prompt, wrapper, script, documentation-contract, or project bug;
  - sends accepted work through normal AAI intake/orchestration;
  - requires a regression test or executable prompt-contract test;
  - opens a linked PR through `/aai-pr`;
  - never merges, releases, claims a fix, or executes issue-provided commands
    without maintainer-controlled validation.
- Collection receives only issue read/write permission. Remediation uses a
  separate identity and explicit permissions.

### 4. Verified learning and distribution

- A report counts as learned only when it links to:
  1. a reproduced failing fixture;
  2. accepted intake/spec where required;
  3. a regression test;
  4. a reviewed, operator-merged PR;
  5. the first release containing the fix.
- `/aai-update` can match local fingerprints against fixes in the new pin. A
  recurrence after the fixed version becomes a regression candidate.
- Measure maintainer acceptance, duplicate suppression, time to accepted issue,
  post-release recurrence, issue volume, false AAI-ownership classifications,
  and privacy incidents. Privacy incidents must remain zero.

- Rationale:
  - The strongest shared industry pattern is: collect many events, group and
    filter them, route a small actionable set to review, and turn accepted
    examples into regression checks.
  - Local capture is cheap enough for every skill; network reporting remains
    separately configurable and auditable.
  - Fingerprints, version awareness, aggregation, and budgets prevent reporting
    every triviality.
  - Configuration makes the protocol reusable by other projects.
  - Human acceptance and merge prevent recursive self-validation.

## Alternatives Considered

- Option A: Every skill calls `gh issue create`.
  - Pros: simplest and fastest.
  - Cons: noisy, unsafe, nondeterministic, hard to deduplicate, and requires
    credentials everywhere. Rejected.
- Option B: Manual `/aai-report` only, similar to Aider.
  - Pros: explicit consent and low privacy risk.
  - Cons: loses unattended and repeated signals. Keep as an escape hatch.
- Option C: Local spool, triage/upsert, and separate maintainer processor.
  - Pros: portable, permission-separated, deduplicated, measurable.
  - Cons: more components and delayed reporting. Recommended.
- Option D: Central hosted telemetry for every trace.
  - Pros: strongest fleet-wide analytics.
  - Cons: infrastructure, cost, consent, and data-residency concerns. Defer.
- Option E: One permanent feedback dashboard issue per downstream project.
  - Pros: low issue count and convenient approval.
  - Cons: mixes lifecycles and can expose private project identity. Optional
    presentation mode only.

## Consequences

- Technical impact:
  - New protocol, schema, capture CLI, untracked spool, configuration, triage
    skill, maintainer skill, issue form, labels, fixtures, and skill-suite tests.
  - Fingerprint normalization becomes a versioned compatibility contract.
- Operational impact:
  - Maintainers receive fewer, richer issues but must tune thresholds.
  - Operators select local, review, or bounded auto mode.
  - Safe-boundary invocation is the baseline; scheduling is optional.
- Migration/compatibility notes:
  - Phase 0: define taxonomy, schema, privacy policy, and fixtures.
  - Phase 1: local shadow mode for at least two weeks.
  - Phase 2: review mode in AAI and threshold calibration.
  - Phase 3: review mode in selected downstream projects.
  - Phase 4: explicit auto opt-in for proven categories.
  - Phase 5: consider automatic fix PR preparation; retain human merge forever.
  - Missing config or `gh` must degrade to local-only, not fail a skill.

## Risks

- Sensitive public disclosure: collect summaries, redact twice, block uncertain
  cases, and require review for security reports.
- Issue spam: ownership gates, fingerprints, recurrence, version checks,
  budgets, and local default.
- False AAI attribution: require evidence tied to an AAI-owned surface and
  reproduce upstream.
- Prompt injection: parse only the versioned schema; prose and attachments are
  untrusted evidence.
- Self-reinforcing fixes: require regression evidence, validation, review, and
  operator merge.
- Surprising downstream behavior: default to no network and show an inspectable
  local queue.
- Bad fingerprint grouping: version the algorithm and support maintainer
  split/merge aliases.
- Private-project fingerprinting: omit identity metadata by default.
- Over-privileged credentials: separate issue collection from remediation.

## Decisions (resolved 2026-07-25, project owner)

The eight open questions were resolved by the owner via interrogation. Each is now
a binding decision for implementation:

- **D1 (destination):** `goodwind-cz/aai` is the DEFAULT destination. Downstream
  forks/other frameworks may override it in `.aai/feedback.yaml`.
- **D2 (release modes):** the first release offers `local` (default), `review`,
  AND `auto` (opt-in). `auto` is gated by D8.
- **D3 (shadow retention/threshold):** local observations expire after **14 days**;
  the reporting threshold starts LOWER/more sensitive and is calibrated during
  shadow mode.
- **D4 (auto-update):** an automatic reporter may NOT update an existing issue
  without approval. In every mode, UPDATES to an existing issue require review;
  `auto` may only OPEN a new-fingerprint issue that passes all gates.
- **D5 (private downstream routing):** private installations report to
  `goodwind-cz/aai` too, but under HARD (double) redaction with all identity
  fields omitted (see D6). They are NOT carved out to a separate destination by
  default.
- **D6 (safe fields):** a MINIMAL allowlist only — OS family
  (linux/macos/windows), AAI pin/version, Node major version, skill id + phase,
  failure class, and the deterministic fingerprint. Never: hostnames, absolute
  paths, repository names/remotes, usernames, or project identifiers.
- **D7 (maintainer processing):** EXPLICIT invocation only in the first release;
  optional scheduling may be added later and only AFTER a human applies the triage
  label — never fully autonomous.
- **D8 (auto gate):** `auto` upserts unlock only after maintainer acceptance
  **>= 70% over >= 20 reviewed reports AND zero privacy incidents**.

### Privacy reconciliation (explicit consequence of D1 + D5)

D1 (default destination = upstream) and D5 (private installs also report upstream,
redacted) move this design AWAY from the RFC's original "opt-in destination /
never upload by default" stance. The privacy guarantee therefore rests, by owner
decision, on FOUR other pillars that implementation MUST make strong and testable:

1. the MODE default is `local` (D2) — NO external write occurs until an operator
   explicitly selects `review` or `auto`;
2. the minimal field allowlist (D6) — identity fields are structurally excluded,
   not merely redacted;
3. hard/double redaction for private installs (D5), with uncertain cases blocked;
4. the auto gate (D8) plus the reporting budget/cooldown.

Implementers MUST treat "mode=local emits nothing over the network" and "no
identity field ever leaves the machine" as skill-suite-enforced invariants, since
they now carry the privacy contract that an opt-in destination would otherwise
have carried. The zero-privacy-incidents metric (D8) is the standing check.

## Approvals

- Required approvers (roles/names):
  - AAI maintainer/owner for taxonomy, thresholds, and lifecycle.
  - Security/privacy reviewer for redaction, retention, and public reporting.
  - Workflow maintainer for intake, orchestration, `/aai-pr`, `/aai-update`, and
    the operator-only merge boundary.

- **Decision 2026-07-25: ACCEPTED (Option C — local spool + triage/upsert +
  separate maintainer processor) by project owner (ales@holubec.net).** The eight
  open questions are resolved as D1-D8 above. Status advanced draft -> accepted;
  implementation is DEFERRED to future phased specs (Phase 0 first). This RFC is
  frozen: the decisions are binding inputs to those specs. The security/privacy
  and workflow-maintainer approvals named above are still required at
  implementation time (Phase 0 gate), not waived by this acceptance.

## Notes

- Intake assumptions:
  - The canonical upstream is currently `goodwind-cz/aai`.
  - Other projects can replace destination and taxonomy without changing the
    capture protocol.
  - Background processing may prepare issues and PRs, but external-write and
    merge authority remain governed by explicit configuration and AAI gates.
