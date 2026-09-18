---
id: close-ceremony-sweep
type: change
number: 188
status: draft
capability: close-ceremony-sweep
links:
  pr: []
  commits: []
---

# The close ceremony, the docs audit and the generated pages agree with git

## Summary
- Wave 3, sweep 4 (`docs/project-sessions/2026-09-13-wave-3-subsystem-sweeps.md`).
  Paired maintenance half: `roadmap-gate-admits-only-the-next-pair` (CHANGE-0184);
  the original half, CHANGE-0181, rode with the mutation gate (PR #384) after the
  owner's re-order of 2026-09-14.
- The largest bucket: the close ceremony (`close-work-item.mjs`,
  `close-reconcile.mjs`, `close-before-push-guard.mjs`, `nothing-left-behind.mjs`,
  `check-committed-scope.mjs`, `allocate-doc-number.mjs`), the docs audit
  (`docs-audit.mjs`, `docs-audit-core.mjs`, `spec-lint.mjs`, `spec-amend.mjs`,
  `verify-closures`), the intake preflight (`intake-staleness-check.mjs`) and
  the generated pages (`generate-docs-index.mjs`, `generate-overview.mjs`,
  `generate-factory-report.mjs`). This month it shipped three false
  statements, an INDEX that carried an untracked draft into CI twice, a
  committed-scope check that compared nothing and exited 0, an overview that
  published a closed ride as in flight, and a close gate that cannot see two
  of the three escapes it exists to catch.
- GitHub #338 (aai-pr post-open sweep contract violation, high), #339
  (close pre-commit script failure), #370 (docs-audit drift detection
  abstraction leak) and CHANGE-0184 (the roadmap gate admits any capability,
  not the next one) belong here.

## Motivation / Business Value
- The close ceremony is the factory's claim that work is done. When it
  passes on a folded scope, trusts the ref it is given, or hides the list it
  is refusing on, "done" is a word, not a state.
- The generated pages are what the owner reads. They must be derived from
  tracked state only, so a regeneration never bakes in a working-tree
  accident.

## Scope
- In scope, fixed with a test each: `fu-check-committed-scope-folded`,
  `fu-gate-trusts-the-ref-it-is-given`, `fu-gate-ref-id-shape-mismatch`,
  `fu-registry-class-trusts-the-filer-id`, `fu-close-gate-status-trigger-blind`,
  `fu-close-gate-unpaired-draft-intake`, `fu-close-reconcile-pair-id-convention`,
  `fu-ac-flip-must-precede-close`, `fu-ac-flip-guard-lean-table-blind`,
  `fu-rolecommon-ac-row-canon-conflict`, `fu-spec-template-legend-offers-sha`,
  `fu-gate-ac-duplicate-id-pipe-drop`, `fu-lean-ac-heading-two-authorities`,
  `fu-mask-duplicates-docs-audit-core`, `fu-docsaudit-idmention-probe-per-doc`,
  `fu-posix-predicate-exit-conflates-infra`, `fu-index-regen-eats-untracked`,
  `fu-overview-regen-eats-untracked`, `fu-overview-bakes-untracked-state`,
  `fu-factory-report-stale-draft-path`, `fu-openct-unrdbl-report`,
  `fu-main-push-conflicts-open-pr`, `fu-verify-staged-set-after-commit`,
  the `fu-verify-closures-*` and `fu-closure-claim-extractor-greedy` items,
  the `fu-stale-check-*` items, `fu-typemap-missing-research-hotfix`,
  `fu-intake-templates-lack-number-key`, `fu-report-ids-exceed-registry-cap`,
  `fu-registry-has-no-reopen`, `fu-product-doc-id-collides-with-intake`,
  `fu-reconcile-skip-drops-commands`, `fu-closeworkitem-pin-tail-wording`,
  `fu-changelog-unreleased-shape-undoc`, `fu-no-nul-guard`, `fu-rollup-creates-userguide`,
  `fu-contract-ledger-rule-stated-twice`, `fu-pgq-grep-error-reopened`,
  `fu-golden-flow-questions-vs-failures`, CHANGE-0181, CHANGE-0184, ISSUE-0042,
  GitHub #338, #339, #370.
- `close-work-item.mjs` is hash-pinned by four suites: this ride batches
  every change to it into one re-pin, written last (its own decision).
- Owned elsewhere: `fu-sync-hash-compare-fails-open`, `fu-agents-tree-not-synced`,
  `fu-gitignore-crlf-exact-line`, `fu-release-*` (sweep 5); `fu-friction-*`,
  `fu-existinglabels-*`, `fu-upsert-*`, `fu-learned-*` (sweep 6);
  `fu-azure-live-proof-on-adoption` (rejected: needs an Azure adopter).
- Owner sign-off items (`fu-amend-*`, seven of them across the registry) are
  presented to the owner as one menu, not fixed by code.

## Affected Area
- The scripts named in the summary, `.aai/SKILL_PR.prompt.md` steps 3 to 5,
  `.aai/ROLE_COMMON.md`, `.aai/templates/SPEC_TEMPLATE.md`, the intake
  templates, `.github/workflows/close-gate.yml`, and the suites for each.

## Desired Behavior (To-Be)
- Every close-ceremony gate reads the scope from a source that cannot be
  folded, nulled or trusted on a name, and prints the full list it refuses on.
- Generated pages are derived from tracked content only; an untracked file
  never reaches a committed page.
- The close gate on main catches all three documented escape shapes.
- The roadmap gate admits the next unfinished pair, and the `blocks:` path.

## Notes
- Bucket on 2026-09-13: 61 open follow-ups outside the test-framework and
  dispatch buckets, of which about 45 are this subsystem's; the spec freezes
  the list by id.
- Ceremony 2, TDD, mutation checks; sibling worktree (it edits the ceremony
  the PR of this ride runs through).
