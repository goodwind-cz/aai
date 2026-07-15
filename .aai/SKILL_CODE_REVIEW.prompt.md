# Code Review Skill — Single Dual-Verdict Reviewer

ONE review pass, TWO independent verdicts, plus an honest-gaps list.
This replaces the former two-stage flow (RFC single-dual-verdict-review,
RES-0001 F4: measured equal quality at ~50% tokens / ~2x speed). The
evidence ceremony around findings is kept; the duplicated pass structure
is gone. A measurement gate (spec-single-dual-verdict-review Spec-AC-05)
compares the next 5 reviewed scopes against the two-stage history in
docs/ai/METRICS.jsonl; the revert path is restoring the prior prompt from
git history.

## ANTI-GAMING CONTRACT (binding — .aai/SUBAGENT_PROTOCOL.md "Review dispatch anti-gaming rules")

- The reviewer context is read-only on implementation files: read code,
  specs, tests, and STATE freely; write ONLY the review report under
  docs/ai/reviews/ and the STATE `code_review` block via the CLI below —
  and the STATE write only when the dispatch grants it (single-agent mode or
  an explicit instruction); in K>=2 parallel mode the orchestrator merges
  verdicts per SUBAGENT_PROTOCOL's single-writer rule (review dogfood NB-2).
- NON-BLOCKING findings: the reviewer NAMES the recommended disposition
  (remediate-in-tree vs promote-to-follow-up-ref) in the report; the
  ORCHESTRATOR records it (decisions.jsonl / new ref) — a read-only reviewer
  never files refs itself (review dogfood friction 3).
- The dispatching orchestrator MUST NOT characterize expected findings,
  pre-rate severity, or scope-exclude areas for the reviewer. If the
  dispatch prompt does any of these, record the coaching attempt in the
  report and review the full scope anyway.
- Diff handoff is by ref/path list (base/head refs, PR number, or explicit
  paths) — never pasted inline into the dispatch prompt. Run the git/gh
  commands yourself against the named refs.

## DIFF SCOPE PREFLIGHT (MANDATORY — before any verdict)

Code review does not require a git worktree. It requires a clean, explicit
diff scope.

Accepted review scopes:
- Worktree or feature branch: `git diff <base>...HEAD`
- Pull request: `gh pr diff <number>`
- Staged changes: `git diff --staged`
- Local inline changes: `git diff` plus `git diff --staged`
- Explicit paths: `git diff -- <path...>` and/or `git diff --staged -- <path...>`
- Commit/range: `git show <sha>` or `git diff <from>..<to>`

Before reviewing:
1. Read `docs/ai/STATE.yaml`.
2. Determine `worktree.user_decision` and `worktree.inline_review_scope`.
3. Run `git status --porcelain`.
4. Establish exactly one review scope.
5. If inline mode is selected and unrelated changes exist outside the scope,
   STOP and ask for exact paths or a diff range.
6. If no clean scope can be established, set `human_input.required: true`
   with a blocking reason and STOP.

Worktree policy:
- If `worktree.user_decision == worktree`, prefer `git diff <base>...HEAD`.
- If `worktree.user_decision == inline`, use `worktree.inline_review_scope`.
- If no worktree metadata exists, review can still proceed using an explicit
  caller-provided diff, PR number, staged diff, or path list.

## THE REVIEW PASS

Read the frozen spec for the scope (`docs/specs/SPEC-<id>.md` /
`SPEC-DRAFT-<slug>.md`, if one exists), then read the full diff once.
Produce BOTH verdicts from that single pass. Each verdict cites its own
evidence section — quality impressions never soften compliance findings,
and compliance gaps never inflate quality findings.

### Verdict 1 — spec_compliance: pass | fail
Evidence is the AC table walk: for EVERY Spec-AC row in the spec's
Acceptance Criteria Status table, one line with the AC id, a per-row call
(compliant / non-compliant / cannot-verify), and a per-AC citation — the
diff hunk (file:line), the TEST-xxx evidence, or the named gap. Also check
TEST-xxx entries: do the claimed tests exist and pass? List every deviation
from the frozen spec, even reasonable ones. If no spec exists, review
against the stated intake requirement/scope and say so explicitly in the
report. A well-written implementation of the wrong thing still fails this
verdict.

### Verdict 2 — code_quality: pass | fail
Real defects only (security, correctness, data loss, performance,
concurrency, error handling), ranked:
- BLOCKING — must fix before merge. Any BLOCKING finding fails this verdict.
- NON-BLOCKING — should fix; these are the WARNINGs of the H6 policy below
  and carry its disposition duty.
Every finding cites file:line AND a concrete failure scenario — the input,
sequence, or state that makes the defect bite. No failure scenario, no
finding: style preferences without a failure mode are INFO at most and
never gate.

### Verdict 3 — cannot_verify: [...] — MANDATORY section, empty list allowed
Claims the diff alone cannot substantiate: runtime behavior no test covers,
external-service contracts, performance assertions, migrations against real
data, cross-repo effects. Name each claim and the evidence that would close
it. An empty list is an explicit statement ("everything claimed was
verifiable from the diff and cited evidence"), never an omitted section.
This converts silent gaps into named ones — write "cannot-verify" instead
of guessing a pass.

Overall review status: pass ONLY when both verdicts pass. `cannot_verify`
entries do not block by themselves, but each must be visible in the report
and considered when judging merge readiness.

## REPORT

Save to `docs/ai/reviews/review-<timestamp>.md` (optionally a `.json`
sibling). NEVER write review or validation evidence to `docs/validation/`
— that directory is scanned by the docs audit, and a frontmatter-less
report there flips the repo audit to NEEDS-TRIAGE (SPEC-0015 review
lesson). `docs/ai/reviews/` is audit-excluded by construction.

Structured dual-verdict block (top of the report):

```yaml
review:
  scope: <diff range | PR number | path list>
  spec: <spec path or none>
  spec_compliance:
    verdict: pass | fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant | non-compliant | cannot-verify,
          citation: "<file:line | TEST-xxx | named gap>" }
  code_quality:
    verdict: pass | fail
    findings:
      - { rank: BLOCKING | NON-BLOCKING, file: <path>, line: <n>,
          issue: "<what is wrong>",
          failure_scenario: "<the input/sequence that makes it bite>" }
  cannot_verify:
    - { claim: "<what the diff cannot substantiate>",
        closes_with: "<evidence that would close it>" }
  overall: pass | fail
```

Markdown body: scope + spec named, the AC table walk, findings with
file:line + failure scenario, the cannot_verify list, warning dispositions
(H6 below), and next steps.

## STATE CONTRACT

PRIMARY PATH (transactional CLI, SPEC-0012):

```bash
node .aai/scripts/state.mjs set-code-review \
  --required <true|false> --status <pass|fail|waived> \
  --scope "<diff-range-or-paths-reviewed>" --base-ref <base-or-null> \
  --report docs/ai/reviews/review-<timestamp>.md \
  --notes "<short summary incl. per-WARNING dispositions>"
```

FALLBACK — if .aai/scripts/state.mjs is absent:
read .aai/STATE_FALLBACK.md and follow it (code_review block hand-edit).

Status rules:
- `pass`: both verdicts pass (no spec non-compliance, no BLOCKING finding).
- `fail`: any Spec-AC non-compliance, missing required TEST-xxx evidence,
  or any BLOCKING finding.
- `waived`: only when the user explicitly waives review or accepts the
  remaining findings. Record the waiver in `docs/ai/decisions.jsonl`.

Report staging (SPEC-0013 H4): after writing
`docs/ai/reviews/review-<timestamp>.{md,json}`, stage the report files
together with the scope's commit (or with the review-response commit) so
review reports never orphan as untracked files across sessions. The wrap-up
skill flags any untracked `docs/ai/reviews/*` as orphaned review reports;
SKILL_PR treats scope-cited reports as expected companions.

## WARNINGS POLICY WITH TEETH (SPEC-0013 H6)

- BLOCKING findings block merge/PR readiness.
- A PASS verdict with open WARNINGs (NON-BLOCKING findings) is conditional
  — before closeout, EACH WARNING must be either
  (a) remediated, or
  (b) promoted to a `docs/ai/decisions.jsonl` entry (decision id +
      rationale), or
  (c) promoted to a tracked follow-up ref (an ISSUE/CHANGE id named in the
      review notes).
  The review report AND STATE.yaml `code_review.notes` must name the chosen
  artifact per WARNING (decision id or follow-up ref). Unrecorded WARNINGs
  are surfaced at closeout by SKILL_WRAP_UP (advisory) and by VALIDATION
  step 8b (enforcement backstop).
- INFO notes never block.

## External Review Response

Codified flow for responding to EXTERNAL review findings on an open PR
(SPEC-0013 H3; codifies the PR #27/#29 practice). Run it whenever a PR
carries unresolved review threads from a human or a review bot.

1. **Fetch the review threads:**
   ```bash
   gh api repos/{owner}/{repo}/pulls/{number}/comments   # inline review threads
   gh pr view {number} --json reviews                     # top-level review verdicts
   ```
2. **Triage every finding** as real / stale / duplicate / disputed, and
   record a one-line disposition per thread:
   - real: the defect exists in the current head — remediate.
   - stale: already fixed by a later commit — cite the fixing commit.
   - duplicate: same root cause as another thread — cite the primary thread.
   - disputed: you believe the finding is wrong — state why, with evidence;
     leave the resolution to the reviewer.
3. **Remediate each real finding with a RED-proofed regression test:** write
   the test first, observe it FAIL against the pre-fix code (cite the red
   log under docs/ai/tdd/), then fix and observe GREEN. A fix without a
   failing-first test is not a remediation.
4. **Reply inline per thread**, citing the fixing commit SHA and TEST id
   (e.g. "Fixed in `abc1234`, regression covered by TEST-017"). For
   stale/duplicate/disputed, reply with the disposition instead.
   Never resolve a thread without a reply.
5. **Push** the remediation commits (with the updated review report staged
   per the report-staging rule above) and re-request review if the platform
   requires it.

## RE-REVIEW AFTER REMEDIATION

The same single pass, automatically — no special casing. Re-establish the
scope (preflight), walk the AC table again, re-rank the findings, refresh
the cannot_verify list, write a new report, update STATE.

BEGIN NOW.
