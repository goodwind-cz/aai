# Code review (delta re-check, PR #556 reviewer fallback): flush-drops-reopened-runs

```yaml
review:
  scope: "git diff da0df9ad303b2e3e794e9c94a4359724ec399be0..ddb910a0 (f627d804, ddb910a0); PR #556 final head == origin/fix/flush-drops-reopened-runs"
  spec: docs/specs/SPEC-0291-spec-flush-drops-reopened-runs.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "no executable byte changed since da0df9ad (git diff --name-only da0df9ad HEAD lists docs/ only); prior PASS stands; AC row done, evidence TEST-3720/3721 + VALIDATION-20261114T1839Z; mutation-gate GATE PASS 8 rows" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "unchanged code; AC row done, evidence TEST-3722; mutation-gate PASS" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "unchanged code; AC row done, evidence TEST-3723/3724/013/107; mutation-gate PASS" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "unchanged code; AC row done, evidence pr-waiver TEST-3725 (arm 19); mutation-gate PASS" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "docs/ai/METRICS.jsonl:248 byte-equal to da0df9ad's last line; origin/main (1667981e, 841485 B) and da0df9ad (848813 B) are exact byte prefixes of HEAD; TEST-3726 rc 0 this round" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "docs/product/telemetry.md:168-174 still describes continuation, flush_segment, SKIP; TEST-3727 rc 0 this round; CHANGELOG untouched by the delta" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 2977,
          issue: "the close ceremony's restamp of SPEC-0291 is recorded as an UNVERIFIED-cause contract amendment (owner_signoff false, tracked_by fu-amend-spec-flush-drops-reopened-runs, P2 at :2978), but the drift is purely the allocator rename: reversing BOTH SPEC-0291-spec-flush-drops-reopened-runs -> SPEC-DRAFT-... and ISSUE-0114-flush-drops-reopened-runs -> ISSUE-DRAFT-... on HEAD's spec reproduces the old anchor 7b9a1e1b...d4 byte-for-byte through contractHash. spec-amend's candidate set misses the issue basename because the spec frontmatter names its requirement by slug id (links.requirement: flush-drops-reopened-runs), not by basename",
          failure_scenario: "close ceremony on any spec whose frontmatter links name slug ids and whose body Links cite the intake's DRAFT basename: the allocator rewrites both, spec-amend reverses only the self-reference, and the ledger gains a 'contract' amendment plus a P2 owner-signature follow-up for a mechanical rename (71 such UNVERIFIED restamp lines already in decisions.jsonl)" }
  cannot_verify:
    - { claim: "new suite code survives set -euo pipefail with GNU tools on the Linux CI runner (carried from the full review)",
        closes_with: "green CI skill-suite job on PR #556 head ddb910a0" }
    - { claim: "PR #555 interaction: after both PRs merge, TEST-3726's origin/main prefix claim and order-independent readers still hold (carried)",
        closes_with: "re-run TEST-3726 and test-aai-pr-waiver.sh on main after #555 merges" }
    - { claim: "R6 downstream older-era STATE/ledger pairs (carried)",
        closes_with: "scratch aai-sync install with an older-era ledger line" }
    - { claim: "D8 reconstruction faithful flag-for-flag (carried; the reconstructed line's bytes did not change in this delta)",
        closes_with: "line-by-line diff of the eleven append-run commands against recon-runs.json" }
  overall: pass
```

security_relevant: false

## Scope and spec

- Role: Code Review, delta re-check (RECHECK_DELTA), run as the SKILL_PR step 5d REVIEWER-FALLBACK
  for PR #556. The external bots did not review, so this round covers the final PR diff on top of
  the full review that passed at da0df9ad.
- Base da0df9ad (full Code Review PASS). Head ddb910a0 == origin/fix/flush-drops-reopened-runs
  (verified with `git rev-parse`). Two commits: f627d804 (telemetry.md correction plus review
  report) and ddb910a0 (close ceremony).
- Spec: docs/specs/SPEC-0291-spec-flush-drops-reopened-runs.md (now `status: done`, number 291).
- Prior reports read: docs/ai/reviews/review-flush-drops-reopened-runs-20261114T191328Z.md,
  docs/ai/reports/VALIDATION-20261114T1839Z-flush-drops-reopened-runs.md,
  docs/ai/reports/VALIDATION-20261114T1917Z-flush-drops-reopened-runs.md.

## Prior findings: fixed or still open

| Prior finding | Status | Evidence observed this round |
|---|---|---|
| NB-1 (P3): continuation lines re-record human time; telemetry.md "sums per ref gets the ride total" was false for human time | Doc part fixed. Code part dispositioned (b), not changed in code by design. | docs/product/telemetry.md:170-174 now limits the "ride total" to agent runs, tokens, duration and cost, and says not to sum `human_time_minutes` across a ride's lines. decisions.jsonl holds follow_up `fu-continuation-rerecords-human-time` (P3), and `follow-ups.mjs list` shows it as open. |
| cannot_verify R1 (dispatch rule 14 strands reopened runs) | Tracked | follow_up `fu-dispatch-flushed-probe-ref-keyed` (P3, open). |
| cannot_verify R2 (per-line readers count a continuation as another ride) | Tracked | follow_up `fu-ledger-readers-fold-flush-segments` (P3, open). |
| INFO items (TEST-3722 arm c label; test_3723 runs TEST-013 twice) | Unchanged | No test file changed in the delta. These were INFO and never gated. |

## Delta checks

- **No executable byte changed.** `git diff --name-only da0df9ad HEAD | grep -v '^docs/'` prints
  nothing. All 13 changed paths are under docs/.
- **METRICS.jsonl.**
  - origin/main (1667981e, 841485 B, which is also the merge-base) is an exact byte prefix of
    HEAD. So is da0df9ad's file (848813 B, ending in the reconstructed line).
  - Line 248 (the reconstructed consumer-config-routing-override line, `flush_segment` 2) is
    byte-equal to da0df9ad's last line.
  - Exactly one line was added (line 249, trailing LF). It is an ordinary first flush:
    - ref `flush-drops-reopened-runs`, the only line for that ref
    - keys `date_utc, ref_id, title, human_time_minutes, agent_runs, totals, strategy,
      reliability, verdict_basis, verdict`
    - no `flush_segment`, no `reconstructed`
  - It holds 9 agent runs: Planning, three TDD Implementation runs, Validation fail, Remediation,
    Validation pass, Code Review pass, and the Validation delta re-check. They are in time order
    with no overlap.
  - `totals.agent_duration_seconds` 7509 equals the sum of the run durations. Run
    `tokens_total` sums to 1487532, which matches overview-data.json's new `token_total`.
  - Reliability reads validation_fails 1, remediation_runs 1, first_pass_clean false, verdict PASS.
    This matches the ride history.
  - All 217 JSON lines parse.
- **Spec and issue consistency.**
  - The spec frontmatter reads number 291, status done. The issue frontmatter reads number 114,
    status done. The Links and Scope lines point at the numbered paths.
  - All six AC rows read `done`. Each Evidence cell names TEST ids and a validation report. There
    are no pipes inside cells (`spec-lint --path` returns LINT PASS, 0 findings).
  - `links.pr`/`links.commits` are empty. This matches the sibling closed docs SPEC-0289 and
    ISSUE-0113, so it is the repo convention.
  - The cited validation reports are gitignored local evidence (`.gitignore:21`). That is also the
    convention, and SPEC-0289 cites 13 of them.
- **Close gates.**
  - `docs-audit --gate spec-flush-drops-reopened-runs` gives GATE PASS.
  - `docs-audit --strict --no-event` gives rc 0 and CLEAN: 0 orphans, 0 drifted, 0 stale,
    0 false-open.
  - The issue's own `--gate` fails with "missing AC Status table". The closed ISSUE-0113 fails the
    same way, because issue docs carry no AC table. This is not a defect.
  - EVENTS holds doc_lifecycle and work_item_closed for both refs.
- **Mutation gate.** `mutation-gate.mjs --spec …SPEC-0291…` gives GATE PASS: 8 rows satisfied,
  degraded 0, unstamped 0.
- **Spec anchor.** `spec-amend list --strict` gives rc 0. Finding NB-R1 covers the restamp.
- **Tests (this round, through the wrapper, `env -u AAI_ROLE -u AAI_GIT_WRITE`).**
  - `test_3726_incident_runs_are_reconstructed_in_the_ledger`: rc 0, 2 PASS, 0 FAIL.
  - `test_3727_changelog_and_product_doc_describe_the_continuation`: rc 0, 2 PASS, 0 FAIL.
  - TEST-3726 selects the reconstructed line by ref and by its `reconstructed` key, not by file
    position. So the ride's own flush line after it does not weaken the test.
- **Regenerated pages.**
  - INDEX moves the spec from Active to Done and the issue from Drafts to Done.
  - overview-data adds the delivered row and backfills the review path of the previous ride.
  - The factory-report-data delta is mostly the daily `age_days` tick (666 of the changed keys)
    plus the new ride's rows.
  - No hand edits were seen.
- `git ls-files -ci --exclude-standard` is empty.

## Verdict 1: spec_compliance = pass

| Spec-AC | Call | Evidence |
|---|---|---|
| 01 to 04 | compliant | Code is unchanged since the full review PASS. The rows are flipped to done with TEST and report evidence, and the mutation gate passes. |
| 05 | compliant | The prefix and line-248 byte checks above pass, and TEST-3726 is green this round. Note: the AC text says the ledger "SHALL end with" the reconstructed line. At HEAD, this ride's own close-ceremony flush line follows it. The AC's substance holds: every origin/main byte is unchanged, and exactly one reconstructed line comes right after them. The test pins the line by ref, not by position. INFO only. |
| 06 | compliant | The telemetry.md correction keeps every phrase TEST-3727 asserts, and TEST-3727 is green this round. |

## Verdict 2: code_quality = pass

### NB-R1 (NON-BLOCKING, P3): restamp recorded as an unverified-cause contract amendment, but the cause is mechanical

- **Location.**
  - docs/ai/decisions.jsonl:2977 is the spec_amendment, `amendment_class: contract`,
    `owner_signoff: false`.
  - docs/ai/decisions.jsonl:2978 is follow_up `fu-amend-spec-flush-drops-reopened-runs`, P2.
  - docs/specs/SPEC-0291-spec-flush-drops-reopened-runs.md:7 holds the new anchor, and :22 holds
    the rewritten issue path.
- **What I measured.**
  - HEAD's spec, with both allocator substitutions reversed
    (`SPEC-0291-spec-flush-drops-reopened-runs` → `SPEC-DRAFT-…` and
    `ISSUE-0114-flush-drops-reopened-runs` → `ISSUE-DRAFT-…`), hashes through
    `lib/spec-contract-hash.mjs` `contractHash` to `7b9a1e1b10008c0dd46f53dae3d5c5fe809834847c58da9649164e265d2232d4`.
    That is exactly the anchor the spec held at da0df9ad.
  - After that reversal, the only diff from da0df9ad's spec is frontmatter (number, status,
    frozen_sha256) and the AC Status/Evidence cells. contractHash blanks those cells.
  - So the drift is fully explained by the allocator. The ledger record's "why" says that
    reversing the allocator rewrite "does not reproduce the stored frozen_sha256, so nothing here
    knows what changed". That is true only for spec-amend's narrow candidate set.
  - `allocatorRewriteCandidates` (spec-amend.mjs:1478-1497) looks for numbered basenames in the
    spec's own self-reference and its frontmatter. This spec's frontmatter names the requirement by
    slug (`links.requirement: flush-drops-reopened-runs`), so the issue rename is never tried.
- **Failure scenario.** Any spec whose frontmatter links use slug ids gets an UNVERIFIED contract
  amendment and a P2 owner-signature item at close, for a pure rename. decisions.jsonl already
  holds 71 such restamp lines.
- **Why NON-BLOCKING.**
  - This is a pre-existing tool limitation. No code in this PR caused it, and the delta changed no
    executable byte.
  - The record is conservative (it fails toward asking the owner). It is not a false PASS.
- **Disposition (c), tracked.** The existing open follow-up `fu-restamp-slug-links-unverified` (P3)
  names exactly this class. The owner can sign `fu-amend-spec-flush-drops-reopened-runs` on the
  evidence above: the reversal of both basenames reproduces the old anchor.

### INFO

- An extra `docs_audit` EVENTS line (ts 2026-11-14T19:49:30Z, ref docs-audit/full, payload
  total 734, zero findings) appeared in the worktree's docs/ai/EVENTS.jsonl while this round ran
  `docs-audit --strict --no-event`.
  - The same command in a scratch copy of the worktree appended nothing. With events enabled, it
    appended one line. So its origin is either a concurrent process in this checkout or this run,
    and it cannot be pinned.
  - It is an append-only telemetry line that matches a clean audit. Per the dispatch rules it was
    left in place (never restore EVENTS).
  - The orchestrator decides whether it rides the next commit. It would move the PR head.
- This Code Review run will be appended to STATE after the ride's ledger line already exists. A
  later flush will therefore write it as a `flush_segment` 2 continuation, which is the feature
  this PR ships. NB-1's human-time caveat applies to that line.

## cannot_verify

See the YAML block. Four entries are carried from the full review: CI on Linux, the post-#555 state,
downstream R6, and the D8 per-flag fidelity. The delta did not touch the bytes they concern.

## Warning dispositions (H6)

- NB-1 (prior round): doc part fixed in f627d804 (telemetry.md:170-174). Code part follows up as
  `fu-continuation-rerecords-human-time` (P3, open), disposition (b).
- NB-R1 (this round): (c), tracked by the existing open follow-up `fu-restamp-slug-links-unverified`
  (P3). The owner signature owed on `fu-amend-spec-flush-drops-reopened-runs` can cite this
  report's reversal evidence.

## Next steps

1. The orchestrator records `set-code-review` (below) and publishes NB-R1 as a PR thread.
2. Decide whether to commit the stray 19:49:30Z docs_audit EVENTS line.
3. Confirm CI green on PR #556 head before merge.
