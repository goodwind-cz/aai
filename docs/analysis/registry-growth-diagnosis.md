# Why the follow-up registry grows — diagnosis and triage (2026-08-24)

Scope: `docs/ai/decisions.jsonl` follow-up registry, measured on `main` at
`f65ae56` (release v2026.08.23). Companion change:
`docs/issues/CHANGE-0161-the-registry-has-no-outflow.md`. All numbers below
were measured from the ledger itself on 2026-08-24; the measurement commands
are one-liners over the JSONL and are reproducible from this document's
tables.

## 1. The measured shape

The registry is 13 days old. The first follow_up line is stamped
2026-08-11; there is no older stock. Totals on the base commit: 247 opened,
84 closed or dropped, 163 open (160 P-graded: 4 P1, 73+? P2, 80 P3, plus one
malformed early line the CLI folds under a synthesized id).

Daily flow (opened / closed / net):

| day | opened | closed | net |
|-----|--------|--------|-----|
| 08-11 | 1 | 0 | +1 |
| 08-13 | 17 | 4 | +13 |
| 08-14 | 28 | 1 | +27 |
| 08-15 | 9 | 1 | +8 |
| 08-16 | 9 | 1 | +8 |
| 08-17 | 3 | 8 | -5 |
| 08-18 | 13 | 10 | +3 |
| 08-19 | 41 | 26 | +15 |
| 08-20 | 22 | 4 | +18 |
| 08-21 | 45 | 6 | +39 |
| 08-22 | 24 | 10 | +14 |
| 08-23 | 35 | 13 | +22 |

Where filings come from (all 248 openings, classified by their `source`
and `decision` fields): review bots and code review 116 (47%), measurement
during proof work 58 (23%), validation rounds 28 (11%), spec/planning 21,
close/session 8, other 17.

Per-ride filing rate over time: the first product rides (CHANGE-0128..0144,
Aug 13-14) filed 1-6 items each. The apparatus rides that followed filed an
order more: deslop-scope 18, deslop-corpus-honesty 19,
suites-must-not-touch-the-shipping-repo 28, suites-run-in-a-disposable-
worktree 15, the-subagent-contract-omits-the-hazards 22. The five worst
net-growth rides are all rides ON the test/guard apparatus.

Closure dynamics: median lifespan of a closed item is 1.4 days — items are
closed almost exclusively by the ride that immediately follows on the same
subject (57 of 87 closures came from a different ride than the one that
filed, i.e. the next ride whose scope overlapped). An item that survives its
neighbourhood has no other route out: median age of the open stock is 3.2
days only because the stock is young; nothing older ever left except by
owner fiat.

The natural experiment: on 2026-08-19 an owner-approved triage dropped 22
items at once, with the recorded reason "Registry had reached 67 open items,
which made the ten that matter unreadable. Dropping is not disproof." Five
days later the registry stood at 163. The refill rate exceeded the largest
cleanup the project had ever done within a week.

## 2. The mechanism

Three structural facts, each verified in the repo, jointly force growth:

**(a) A mandatory intake valve.** `.aai/SKILL_CODE_REVIEW.prompt.md`
("WARNINGS POLICY WITH TEETH", SPEC-0013 H6) requires EVERY non-blocking
review finding to be either remediated in the ride or recorded as a registry
row / tracked ref; VALIDATION step 8 enforces the same at closeout. There is
no disposition for "true, recorded, not worth tracking". Under ride
discipline ("file it, don't fix it" — 30 filings say this explicitly in
their decision field), filing is the cheapest legal disposition, so every
observation becomes a permanent row. The pipeline runs two external bots
plus an internal dual-verdict review plus up to nine validation rounds per
ride; their finding count scales with diff size and scrutiny and is never
zero.

**(b) No outflow.** Nothing in the pipeline reads the registry.
`grep -rl follow-ups.mjs .aai/` returns the CLI itself, the code-review
prompt (writer), and the factory report (a counter). Planning, intake and
orchestration never consult it; there is no expiry, no cap, no owner, no
triage step. The only exits are (1) a next-door ride happening to overlap,
and (2) ad-hoc owner fiat.

**(c) A self-exciting subject.** ~45% of the stock is about the test/guard
apparatus. Fixing those items is done by apparatus rides, which add MORE
guard surface (tripwires, ratchets, arms, byte-pins), which the same
adversarial scrutiny then measures, yielding more findings per ride, not
fewer. Filing rate per ride grew from 1-6 to 11-28 as the subject shifted
from product to apparatus. The incumbent ride of 2026-08-24 documents the
same loop from the inside: a pin on one scope's diff billed six later
scopes ("a-branch-diff-pin-taxes-every-later-scope").

Steady state under these rules: open count grows by roughly
(findings per ride) - (same-neighbourhood closures) = +5 per ride, without
bound. Exactly what was observed across sixteen rides.

## 3. Hypotheses adjudicated

**"Growth is honest measurement of newly built tools' limits, and stops
when the road is fixed" (the incumbent's working theory).** Half right,
and wrong where it matters. Right: the findings are honest — sampled
evidence fields cite real mutations, real line numbers, real measured
behavior; this diagnosis found no fabricated finding. Wrong: the prediction.
The three heaviest road-fixing days (Aug 21-23) are the three highest-growth
days (+39, +14, +22), the worst net producers are precisely the road-fixing
rides, and the 08-19 triage regrew in five days. Fixing the road grows the
measured surface; by induction growth does not stop, it compounds. The last
three days did not build a machine that produces work for itself out of
nothing — the findings are real — but they did build a machine that
converts every unit of assurance work into more than one unit of recorded
assurance debt, which is the same terminal behavior.

**"The ceremony manufactures findings because each gate must produce
output."** Not confirmed as stated — gates do not fabricate; no evidence of
padded or invented findings. But the disposition mandate (a) converts every
gate output into a permanent row, which has the same arithmetic effect. The
manufacturing step is the filing requirement, not the finding.

**"P3 has no cost, so nothing is refused."** Confirmed in structure:
filing is cheaper than remediating and cheaper than arguing, and there is no
disposition that records without tracking. (Close rates per severity are
similar — P1 60%, P2 36%, P3 33% — because closure is neighbourhood luck,
not priority.)

**"No expiry, no owner, no triage."** Confirmed (see 2b). Also visible in
the stock: items that are decisions ("decide whether the shell twin is a
standing cost" — a P1 that is a QUESTION), items that are lessons
("a claim sweep needs reading, not regex"), and five verifiable duplicate
pairs filed from different rides because nothing dedups against the open
set.

**"File it, don't fix it converts every observation into a permanent
row."** Confirmed as the composition of (a) and (b).

## 4. The correction

The registry must become a queue of intended work with the review reports
as the durable archive of observations. Three moves, deliberately adding NO
new guard surface (per 2c, new surface is the fuel):

1. **A disposition that records without tracking** (edit to
   `.aai/SKILL_CODE_REVIEW.prompt.md`): a P3 finding that names an
   assurance-strength or maintenance limit — a guard weaker than ideal, an
   unexercised edge, a cost — with no observed bite and no false record left
   anywhere may be recorded as `accepted residual: <reason>` in the review
   report and NOT filed. P1/P2, anything that bit, and anything that leaves
   a false record (a green that lies, a wrong number in telemetry) still
   must be remediated or filed.

2. **A consumer** (edit to `.aai/PLANNING.prompt.md`): the spec's "Registry
   items closed by this scope" line must be derived from a live
   `follow-ups.mjs list` pass over the scope's subjects, so neighbourhood
   closure — the only closure that empirically happens — becomes systematic
   instead of accidental.

3. **Triage of the existing stock** (section 5): every open item gets a
   written disposition here; the ledger receives append-only closures only
   for dispositions that survive checking. Nothing is deleted: every closed
   row keeps its original finding line and its evidence citation in the
   tracked review/validation reports.

What this correction does NOT claim: that the 95 items kept open will now
shrink on their own. They shrink if rides consult the registry at planning
(move 2) and if the P1/P2 stock is scheduled deliberately. The honest test
of this correction is the same registry read four weeks from now: if open
count is again above 150, the diagnosis was wrong somewhere and the next
lever is refusing P2 filings without a named owner-ride.

## 5. Triage of the 163 open items

Rules applied: severity as filed is respected (no P1/P2 is dropped as
residual); a "done" needs a deliverable that exists; a "dropped" needs a
reason that survives checking and never claims the finding was false.
Owner sign-off for every appended closure = the merge of the PR that
carries them; striking any line before merge reopens nothing (the drop is
simply not appended).

### 5a. Duplicates — dropped, primary named (6)

- `fu-telemetry-completeness-20260811T0520` = `fu-usage-marker-omission-unfixable`
  (both: a run whose usage marker was omitted has no per-run correction).
- `fu-state-focus-specpath-stale` = `fu-setfocus-keeps-stale-spec-path`
  (both: set-focus leaves the previous ride's spec_path in current_focus).
- `fu-ceremony-guard-reds-on-dirty-core` = `fu-ceremony-test016-blanket-byte-pin`
  (both: ceremony-levels TEST-016 byte-pins docs-audit-core.mjs).
- `fu-framework-appends-tracked-testruns` = `fu-test-runs-jsonl-tracked-ignored`
  (both: test-framework.sh dirties tracked docs/ai/tests/test-runs.jsonl).
- `fu-pr-number-prediction-races` = `fu-close-requires-pr-before-it-exists`
  (one root cause: close-work-item needs --pr before the PR exists).
- `fu-run-id-second-resolution-collides` = `fu-framework-rundir-same-second`
  (one root cause: RUN_ID has one-second resolution).

### 5b. Lessons — done, resolved by a LEARNED.md rule shipped in this ride (3)

- `fu-claim-sweep-needs-reading-not-regex` -> rule: corpus-wide claim
  corrections are completed by reading the enumerated files, never by regex.
- `fu-append-only-merge-needs-prefix-order` -> rule: merge an append-only
  ledger by keeping the base a byte-exact prefix.
- `fu-escape-literals-self-inflict` -> rule: after writing about a control
  character, scan the file for the literal.

These rows asked for knowledge to be institutionalized, not for code; the
rule is the deliverable and is cited by each closure.

### 5c. Unfixable-historical / environmental — dropped with the reason (3)

- `fu-round7-report-never-written`: writing the report now would be a
  reconstruction presented as evidence; the verdict survives in the
  subagent record the row cites.
- `fu-decisions-appended-out-of-ts-order`: append-only history is
  permanent; consumers fold by id, not physical order.
- `fu-layer-profiles-sync-idempotence-flake`: known CI-load flake class
  (green on bare re-run of the same commit); reopen if it reproduces
  locally.

### 5d. Accepted residuals — dropped, reopen on first bite (56, all P3)

Assurance-strength and maintenance limits with no observed bite and no
false record: arms that could be evaded by a route nobody takes, pins not
mutation-proofed, untested-platform gaps, dead code, duplication and cost
observations. The finding line and its evidence citation remain in the
ledger and in the tracked review/validation reports; dropping is not
disproof, and the first observed bite reopens the subject as a fresh filed
row with the old id cited.

`fu-mask-pipe-clause-unpinned`, `fu-reserve-success-path-uncovered`,
`fu-test020-corpus-regex-thin`, `fu-g4-corpus-regex-polarity`,
`fu-deslop-suite-additivity-guard`, `fu-test005-no-exit-assert`,
`fu-spec0132-cmp-wording`, `fu-deslop-ac02-single-citation`,
`fu-mutation-rig-copies-whole-tree`, `fu-deslop-t026-draft-flag-unpinned`,
`fu-deslop-symlink-fixtures-windows`, `fu-deslop-diff-balance-clause-shadowed`,
`fu-deslop-unanchored-report-line-greps`, `fu-deslop-surface-walk-dir-silent`,
`fu-tripwire-porcelain-class-not-content`, `fu-tripwire-evadable-by-index-flags`,
`fu-tripwire-ratchet-path-glob-widens`, `fu-tripwire-ratchet-duplicate-entry`,
`fu-tripwire-git-internals-unnamed`, `fu-suite-map-tripwire-row-incomplete`,
`fu-wrapper-tripwire-snapshot-leak`, `fu-tripwire-unavailable-discards-hash`,
`fu-tripwire-contract-omits-hash-side`, `fu-isolation-seeding-duplicated`,
`fu-nested-isolation-per-suite-cost`, `fu-iso-kill-arms-double-covered`,
`fu-iso-wroot-string-compare-dead`, `fu-iso-exec-script-basename-only`,
`fu-followups-dead-return-usageerror`, `fu-pipeguard-nonepipe-arm-unproven`,
`fu-pipe-exit-contract-windows-untested`, `fu-prefix-restatement-needs-hyphen`,
`fu-test012-sigpipe-rationale-overstated`, `fu-spec0010-t001-utc-date-bomb`,
`fu-test004-missing-mask-vacuity-guard`, `fu-index-row-metadata-unasserted`,
`fu-stale-arm-reads-worktree-index`, `fu-strip-dated-runaway-section-mask`,
`fu-histmap-merge-pathspec-divergence`, `fu-pipe-into-head-sigpipe-class`,
`fu-pgq-scan-evadable-shapes`, `fu-payload-needle-unbounded-in-message`,
`fu-pgq-baseline-duplicate-row-masks-rise`, `fu-pgq-scan-silent-on-grep-error`,
`fu-isolation-degrade-not-on-pass-line`, `fu-wrapper-no-repo-root-branch-dead`,
`fu-seeding-skipped-token-collides`, `fu-ratchet-counter-line-undercount`,
`fu-always-watch-array-unguarded`, `fu-test014-anchorless-control-mismatch`,
`fu-test015-blocks-array-guard-fix`, `fu-tripwire-suite-grep-half-pinned`,
`fu-haz-arm-cardinality-not-uniqueness`, `fu-haz-arm-omits-placement-pin`,
`fu-contract-cap-counts-lines-not-bytes`, `fu-decisions-supersede-unenforced`

Deliberately NOT in this batch despite being P3, because they leave a false
record or a silent-false-good, the shape this project treats as its worst
defect class: `fu-tripwire-degrade-not-on-suite-line` (tripwire_attested:
true recorded under degrade), `fu-seed-step2-enumeration-silent`,
`fu-marker-append-failure-discarded` (both report "seeded" over an
incomplete seed).

### 5e. Kept open (95: 4 P1, 73 P2, 18 P3)

Disposition: real defects and decisions someone should schedule; the four
P1s first (`fu-shell-twin-parity-tax` is a QUESTION for the owner, not a
defect — it should become a HITL decision, not sit in this queue;
`fu-subagent-probe-hits-real-repo`, `fu-isolated-suite-reaches-shipping-repo`,
`fu-release-guards-forbid-release-by-pr` are the isolation and release-path
holes). The stale-prose P3 cluster
(`fu-tripwire-suite-comment-transitional`, `fu-isolation-suite-presumes-deletion`,
`fu-drain-spec-says-d7-filed-not-fixed`, `fu-spec-d6-enumeration-stale`,
`fu-ledger-no-backtick-claim-is-absolute`, `fu-contract-ledger-rule-stated-twice`)
is one cheap sweep ride. Full list with severities:

- P1 `fu-isolated-suite-reaches-shipping-repo` (retire-the-tripwire-behind-its-replacement)
- P1 `fu-release-guards-forbid-release-by-pr` (release-v2026-08-23)
- P1 `fu-shell-twin-parity-tax` (RESEARCH-0001)
- P1 `fu-subagent-probe-hits-real-repo` (deslop-scope-and-unrequested-engine)
- P2 `fu-ac-table-flip-trips-false-open` (the-subagent-contract-omits-the-hazards)
- P2 `fu-acgate-vs-falseopen-catch22` (suites-must-not-touch-the-shipping-repo)
- P2 `fu-adhoc-probes-unisolated-report-only` (registry-audit-20260820)
- P2 `fu-allowlist-count-is-prose-not-asserted` (the-subagent-contract-omits-the-hazards)
- P2 `fu-bare-main-baseref-sweep` (deslop-corpus-honesty)
- P2 `fu-ceremony-levels-nearest-miss-30kb` (assertions-must-not-die-on-their-own-payload)
- P2 `fu-ceremony-test016-blanket-byte-pin` (spec-intake-numbers-some-doc-types-immediately)
- P2 `fu-cli-exit-truncates-pipe-sweep` (cli-output-survives-a-pipe)
- P2 `fu-close-before-push-ordering` (deslop-corpus-honesty)
- P2 `fu-close-requires-pr-before-it-exists` (deslop-corpus-honesty)
- P2 `fu-contract-prefix-order-unenforced` (the-subagent-contract-omits-the-hazards)
- P2 `fu-dispatch-prompt-coaching-bias` (role-verification-guards)
- P2 `fu-dispatch-targets-closed-scope` (deslop-scope-and-unrequested-engine)
- P2 `fu-docnumbering-logfail-aborts-suite` (deslop-corpus-honesty)
- P2 `fu-docsaudit-idmention-probe-per-doc` (spec-docs-history-is-one-git-call-per-doc)
- P2 `fu-drain-pipe-grep-q-ratchet` (assertions-must-not-die-on-their-own-payload)
- P2 `fu-drained-suites-still-write-unisolated` (drain-the-tripwire-known-offender-list)
- P2 `fu-empty-path-cd-stays-in-shipping-repo` (the-subagent-contract-omits-the-hazards)
- P2 `fu-filed-list-trusted-again` (suites-run-in-a-disposable-worktree)
- P2 `fu-fixture-arg-exceeds-linux-argstrlen` (assertions-must-not-die-on-their-own-payload)
- P2 `fu-followups-json-truncated-on-pipe` (suites-must-not-touch-the-shipping-repo)
- P2 `fu-framework-rundir-same-second` (suites-must-not-touch-the-shipping-repo)
- P2 `fu-intake-common-fallback-numbers-doc` (intake-numbers-some-doc-types-immediately)
- P2 `fu-intake-dir-pin-is-set-not-opening` (intake-numbers-some-doc-types-immediately)
- P2 `fu-intake-dir-unanchored-research-hotfix` (intake-numbers-some-doc-types-immediately)
- P2 `fu-intake-table-parser-asymmetry` (intake-numbers-some-doc-types-immediately)
- P2 `fu-ismain-symlink-realpath` (suites-run-in-a-disposable-worktree)
- P2 `fu-iso-bases-reset-discards-entries` (suites-run-in-a-disposable-worktree)
- P2 `fu-iso-wrapper-traps-dont-reap-group` (suites-run-in-a-disposable-worktree)
- P2 `fu-isolation-suite-not-hermetic` (a-run-must-say-whether-isolation-armed)
- P2 `fu-ledger-backticks-ran-as-command` (intake-numbers-some-doc-types-immediately)
- P2 `fu-main-push-conflicts-open-pr` (cli-output-survives-a-pipe)
- P2 `fu-mask-duplicates-docs-audit-core` (CHANGE-0144)
- P2 `fu-no-nul-guard` (docs-model-nul-escape)
- P2 `fu-openct-unrdbl-report` (followups-cli-hardening)
- P2 `fu-orchestrator-does-not-watch-ci` (ride-cost-readout)
- P2 `fu-orchestrator-git-add-scope-bleed` (CHANGE-0142)
- P2 `fu-orchestrator-monitor-uses-gnu-find` (suites-run-in-a-disposable-worktree)
- P2 `fu-orchestrator-mutated-real-file` (cli-output-survives-a-pipe)
- P2 `fu-overview-shows-closed-ride-inflight` (the-tripwire-is-permanent-not-transitional)
- P2 `fu-parallel-roles-dirty-the-tree` (suites-must-not-touch-the-shipping-repo)
- P2 `fu-posix-arm-reddens-on-prose-backslash` (index-arm-diffs-whole-file-for-a-path-claim)
- P2 `fu-posix-predicate-exit-conflates-infra` (index-arm-diffs-whole-file-for-a-path-claim)
- P2 `fu-ratchet-not-selected-on-rise` (assertions-must-not-die-on-their-own-payload)
- P2 `fu-report-ids-exceed-registry-cap` (intake-numbers-some-doc-types-immediately)
- P2 `fu-seed-loss-turns-an-arm-into-a-skip` (a-half-seeded-checkout-says-it-is-isolated)
- P2 `fu-setfocus-keeps-stale-spec-path` (deslop-scope-and-unrequested-engine)
- P2 `fu-sigpipe-code-differs-by-platform` (assertions-must-not-die-on-their-own-payload)
- P2 `fu-spec-closes-claim-unverified` (registry-audit-20260820)
- P2 `fu-staleness-source-line-self-certifies` (index-arm-diffs-whole-file-for-a-path-claim)
- P2 `fu-subagent-state-write-contradiction` (deslop-scope-and-unrequested-engine)
- P2 `fu-suggested-ids-read-as-filed` (suites-must-not-touch-the-shipping-repo)
- P2 `fu-sweep-regex-misses-present-tense` (the-tripwire-is-permanent-not-transitional)
- P2 `fu-sweep-scope-excludes-repo-root` (the-tripwire-is-permanent-not-transitional)
- P2 `fu-sync-hash-compare-fails-open` (followups-cli-hardening)
- P2 `fu-tdd-skips-full-sweep` (deslop-scope-and-unrequested-engine)
- P2 `fu-test-runs-jsonl-tracked-ignored` (suites-must-not-touch-the-shipping-repo)
- P2 `fu-test011-branch-diff-allowlist-tax` (CHANGE-0144)
- P2 `fu-test013-uncovered-on-legal-max-raise` (drain-the-tripwire-known-offender-list)
- P2 `fu-test021c-precondition-unasserted` (cli-output-survives-a-pipe)
- P2 `fu-test028-exitcode-not-clean` (deslop-corpus-honesty)
- P2 `fu-tripwire-allowed-ignores-pre-dirty` (suites-must-not-touch-the-shipping-repo)
- P2 `fu-tripwire-always-watch-floor-uncovered` (drain-the-tripwire-known-offender-list)
- P2 `fu-tripwire-fail-hides-suite-log-tail` (suites-must-not-touch-the-shipping-repo)
- P2 `fu-ts-precision-unify-source` (role-verification-guards)
- P2 `fu-typemap-missing-research-hotfix` (spec-intake-numbers-some-doc-types-immediately)
- P2 `fu-usage-marker-omission-unfixable` (the-subagent-contract-omits-the-hazards)
- P2 `fu-validation-ignores-suite-selector` (ride-cost-readout)
- P2 `fu-validation-staleness-undetected` (deslop-scope-and-unrequested-engine)
- P2 `fu-verify-staged-set-after-commit` (CHANGE-0142)
- P2 `fu-worktree-hook-disarms-later-suites` (suites-run-in-a-disposable-worktree)
- P2 `fu-worktree-shares-git-admin-surface` (suites-run-in-a-disposable-worktree)
- P2 `fu-wrapper-hidden-suite-run-unreported` (retire-the-tripwire-behind-its-replacement)
- P3 `fu-ac-flip-must-precede-close` (suites-run-in-a-disposable-worktree)
- P3 `fu-completion-line-hardcodes-index` (CHANGE-0143)
- P3 `fu-contract-ledger-rule-stated-twice` (the-subagent-contract-omits-the-hazards)
- P3 `fu-docsaudit-t003-red-on-new-doc` (suites-run-in-a-disposable-worktree)
- P3 `fu-drain-spec-says-d7-filed-not-fixed` (drain-the-tripwire-known-offender-list)
- P3 `fu-index-regen-silent-degrade` (close-regenerate-order)
- P3 `fu-intake-templates-lack-number-key` (intake-numbers-some-doc-types-immediately)
- P3 `fu-isolation-suite-presumes-deletion` (the-tripwire-is-permanent-not-transitional)
- P3 `fu-ledger-no-backtick-claim-is-absolute` (intake-numbers-some-doc-types-immediately)
- P3 `fu-marker-append-failure-discarded` (a-half-seeded-checkout-says-it-is-isolated)
- P3 `fu-metrics-flush-advises-git-restore` (the-subagent-contract-omits-the-hazards)
- P3 `fu-rollup-creates-userguide` (CHANGE-0143)
- P3 `fu-seed-step2-enumeration-silent` (spec-a-half-seeded-checkout-says-it-is-isolated)
- P3 `fu-spec-d6-enumeration-stale` (the-tripwire-is-permanent-not-transitional)
- P3 `fu-tripwire-degrade-not-on-suite-line` (suites-must-not-touch-the-shipping-repo)
- P3 `fu-tripwire-fixture-dirs-leak` (suites-must-not-touch-the-shipping-repo)
- P3 `fu-tripwire-suite-comment-transitional` (the-tripwire-is-permanent-not-transitional)
- P3 `fu-vague-term-line-attribution` (CHANGE-0144)

## 6. What was not verified

- Each filed finding's truth was NOT re-derived; severities are trusted as
  filed. The triage never claims a finding was wrong — only that tracking
  it as open work is not justified by its own text.
- The duplicate pairs were verified by reading both finding texts and
  confirming one fix resolves both, not by testing the fixes.
- The flake disposition for `fu-layer-profiles-sync-idempotence-flake`
  relies on the row's own evidence (CI-only, green on re-run); the flake
  was not reproduced here.
- The prediction in section 4 (open count under 150 in four weeks) is a
  falsifiable commitment, not a result.
