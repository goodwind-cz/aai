---
id: spec-implied-signing-without-links-pr
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 0e00e631ff0eccc0a93ef2de9b2dd0d1363fe361232c1fb71428fdd91fbf924f
ceremony_level: 2
links:
  requirement: implied-signing-without-links-pr
  rfc: null
  pr: []
  commits: []
---

# A merged ride's amendments read as signed when its PR number sits only in the squash commit subject

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-DRAFT-implied-signing-without-links-pr.md
- Predecessor: docs/specs/SPEC-0226-spec-amendment-signoff-implied-by-merge.md (the implied signature this scope extends)
- Engine: .aai/scripts/spec-amend.mjs (`getBaseDocIndex`, `checkRideMerged`)
- Consumer across the seam: .aai/scripts/follow-ups.mjs (`foldAmendments(...).followUps`)
- Canon: .aai/system/AUTONOMOUS_LOOP.md (section 6a, the SPEC-0226 sentence)
- Test Suite: tests/skills/test-aai-spec-amend.sh
- Ledger: docs/ai/decisions.jsonl
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Implementation strategy
- Strategy: tdd
- Rationale: the change sits on a signature gate, where a false positive (a signature implied for a ride that never merged) is worse than a missing one. Each refusal arm (status not done, subject not in the strict format, commit not on the first-parent line, PR number read from the checkout instead of the base) must be seen RED against its own mutation before it counts. The orchestrator recorded tdd for this ride.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to a signature gate plus append-only ledger writes; the ride already runs in its own worktree.
- User decision: worktree
- Base ref: main (origin/main 72a8c2ea at planning)
- Worktree branch/path: change/implied-signing-without-links-pr at /private/tmp/aai-implied-sign
- Inline review scope: .aai/scripts/spec-amend.mjs tests/skills/test-aai-spec-amend.sh .aai/system/AUTONOMOUS_LOOP.md docs/ai/decisions.jsonl docs/specs/SPEC-DRAFT-spec-implied-signing-without-links-pr.md

## Measurements (planning, 2026-10-25, base origin/main 72a8c2ea)

- 585 docs under `docs/` carry `status: done` and an `id`; 87 of them have an empty `links.pr` (read with `parseFrontmatter` from `.aai/scripts/lib/docs-model.mjs`, the parser `getBaseDocIndex` uses).
- For those 87, the newest first-parent commit of origin/main that touched the doc has a subject ending in ` (#<n>)` for 61 docs; 26 do not (older `Merge pull request #N from ...` merge commits, direct pushes such as `fix(docs-audit): ... (CHANGE-0001)`, and two subjects of the form `... (#480) (#483)` that still end in the suffix).
- origin/main first-parent history: 620 commits, 314 subjects ending in ` (#<n>)`, 148 subjects starting `Merge pull request #`. The repo's directed merge runs `gh pr merge <n> --squash` (`.aai/SKILL_MERGE.prompt.md`, `.aai/scripts/merge-policy.mjs`), so every merge since the switch to squash produces the suffix.
- Every ride closed through the canonical `/aai-pr` flow since CHANGE-0198 has an empty `links.pr`: `close-work-item.mjs` runs before `gh pr create` and nothing writes the number later.
- How PR #501 was signed: one `hitl_decision` (decisions.jsonl line 2451, answer "Mergni #501 (Recommended)") and six hand-written `spec_amendment_classification` overlays (lines 2452 to 2457, record keys 98ec877de848, 949419e17d08, f4fc1fe9a179, f6993ac19a97, d2d5f37e6ed6, 083edab1cd4f). Four records carry ref_id `merge-cleanup-resolves-framework-friction` (the CHANGE-0227 doc id), two carry `spec-merge-cleanup-resolves-framework-friction` (the SPEC-0252 doc id).
- PR #502 left four unsigned contract records on `provider-adapter-registry-slice` (record keys 04a6a38c2bd8, 86aff82b4b9d, 21f05c8acd17, db41b41061fe), tracked by `fu-amend-provider-adapter-registry-slice`.
- Prototype of the chosen seam (a scratch copy of `.aai/scripts/`, never the shipping tree), run against the ledger blob at 72a8c2ea with the six #501 overlays removed and `--base-ref 72a8c2ea`: today's code reads 390 signed, 142 measurement, 12 unsigned-tracked; the prototype reads 400 signed, 142 measurement, 2 unsigned-tracked. Exactly 10 records change bucket, the six #501 and the four #502 records, all to `signed` with tracker `done`. The 2 that stay unsigned belong to `routing-tables-have-an-owner-and-a-seam`, whose doc CHANGE-0192 is `status: draft` although its newest commit subject ends in `(#389)`.

## Seam decision

Three seams were on the table (intake Scope). Chosen: the implied-signature check reads the PR number from the base branch's commit subject.

- `merge-cleanup.mjs apply` recording `links.pr` after the merge was rejected: it writes into the main checkout after the merge, the exact dirty-checkout state SPEC-0226 removed, and protected `main` refuses the push.
- `close-work-item.mjs` backfilling was rejected: it runs before the PR exists, and changing when it runs is out of scope.
- The read-time check has the fewest moving parts: no writer, no new ledger record, one `git log` call per done ride that lacks `links.pr`, cached per index entry.

### D1. What the check compares

When `checkRideMerged` finds the ride doc for a ref_id in the base ref's tree with `status: done` and an empty `links.pr`, it runs

`git log -1 --first-parent --format=%s <baseRef> -- <path of that doc on the base ref>`

and reads the ride as merged when that one subject line matches the regular expression ` \(#([1-9][0-9]*)\)$` (a space, `(#`, a positive decimal integer with no leading zero, `)`, end of line). Nothing else in the subject is read. A doc with a non-empty `links.pr` keeps today's rule unchanged. Every other case reads unmerged: no doc for the ref_id, a doc that is not `done`, a base ref that does not resolve, a `git log` that exits non-zero or prints nothing, a subject in any other shape.

Caveat stated once: a commit subject is text, and anyone who can push to the base branch can write that suffix by hand; the check trusts the base branch's protection, as the existing `links.pr` rule trusts whoever wrote the frontmatter.

### D2. Code shape (mutation anchors depend on it)

- `getBaseDocIndex` adds the doc's base-tree path to each index entry: `const info = { id: String(fm.id), status: fm.status, prs, isDone, rel: rels[n] };`.
- A module constant `const SQUASH_PR_SUFFIX = / \(#([1-9][0-9]*)\)$/;` and a function `squashPrFromBase(cwd, baseRef, rel)` that spawns `['log', '-1', '--first-parent', '--format=%s', baseRef, '--', rel]` with `encoding: 'utf8'`, returns `null` when the exit status is not 0, strips one trailing newline, and returns the captured integer or `null`.
- `checkRideMerged` keeps its two early returns, then reads, on separate lines, `if (!info) return false;`, `if (info.status !== 'done') return false;`, `if (info.prs.length > 0) return true;`, caches `info.squashPr` on first use, and ends with `return info.squashPr !== null;`.
- The comment above the implied-signature fold in `foldAmendments` and the cache comment above `BASE_DOCS_CACHE` say what is compared, in the words of D1, and nothing more.

### D3. Canon sentence

`.aai/system/AUTONOMOUS_LOOP.md` section 6a currently reads "merged into the base branch with a PR number in `links.pr` (SPEC-0226)". It becomes: merged into the base branch with a PR number in `links.pr`, or, when `links.pr` is empty, with the newest first-parent commit of the base branch that touched the ride doc carrying a subject ending in ` (#<n>)` (SPEC-0226, this spec). The two literals the test reads are `newest first-parent commit` and `(#<n>)`. The file sits outside the `.aai/*.prompt.md` glob and TEST-010 extra-file accounting, so no prompt-diet ledger entry is owed; it is an existing file, so no PROFILES.yaml entry is owed.

### D4. The #502 signatures (ledger action, AC-004)

The implementer, before writing, greps each of the four record keys in `node .aai/scripts/spec-amend.mjs list --json` output and confirms ref_id `provider-adapter-registry-slice`, class `contract`, `owner_signoff: false`. Then, in this order:

1. one `hitl_decision` line appended to `docs/ai/decisions.jsonl` (raw append, the #501 shape at line 2451): ref_id `provider-adapter-registry-slice`, `by: human`, `answer` exactly `Mergni #502 (Recommended)`, `owner_signoff: true`, decision text naming PR #502, merge commit 72a8c2ea and head 8ce9e708 and the four record keys;
2. `node .aai/scripts/spec-amend.mjs classify --record <key> --signoff owner --why "<...>" --source "owner merge of PR #502 via menu answer 'Mergni #502 (Recommended)', 2026-10-25; hitl_decision <its ts>"` once per key (04a6a38c2bd8, 86aff82b4b9d, 21f05c8acd17, db41b41061fe);
3. `node .aai/scripts/follow-ups.mjs close --id fu-amend-provider-adapter-registry-slice --resolved-by implied-signing-without-links-pr --source <hitl ts>`.

Each step is verified by reading the ledger back before the next (memory: a ledger record is written only after the text it describes is verified). These writes go last among ledger writes of the ride that precede the PR sweep.

## Acceptance Criteria Mapping

- Spec-AC-01 maps to AC-001. Verify: in a fixture repo whose base `main` holds a `status: done` ride doc with `links:\n  pr: []`, committed with subject `feat: ride (#77)`, `spec-amend.mjs list --base-ref main --json` reports the ride's unsigned contract record with `bucket: signed`, `owner_signoff: true`, `tracked_status: done`, and `list --strict` exits 0. Across the seam, `follow-ups.mjs list --status all --json` on the same ledger reports the `fu-amend-*` tracker as `done`.
- Spec-AC-02 maps to AC-002. Verify: in fixture repos, each of these reads `unsigned-tracked` with `owner_signoff: false`: a `draft` doc whose newest base commit subject ends in `(#5)`; a done doc with empty `links.pr` whose newest base subject is each of `chore: no suffix`, `fix: x (#12) trailing`, `fix: x (#0)`, `fix: x (#12a)`, `Merge pull request #12 from o/b`; a done doc whose newest suffixed commit is on a side branch joined to `main` by a `--no-ff` merge commit with subject `merge side`; a done doc whose base subject has no suffix while the checked-out branch adds a later commit touching it with subject `feat: y (#9)`; a `--base-ref` that does not resolve.
- Spec-AC-03 maps to AC-003. Verify: with cwd at the project root, the ledger blob `git show 72a8c2ea:docs/ai/decisions.jsonl` minus the six #501 overlay lines (classifies_record 98ec877de848, 949419e17d08, f4fc1fe9a179, f6993ac19a97, d2d5f37e6ed6, 083edab1cd4f) read by `spec-amend.mjs list --base-ref 72a8c2ea --json` reports those six records and the four #502 records (04a6a38c2bd8, 86aff82b4b9d, 21f05c8acd17, db41b41061fe) as `signed`, the bucket totals as 400 signed, 142 measurement, 2 unsigned-tracked, 0 unsigned-untracked, 0 unclassified.
- Spec-AC-04 maps to AC-004. Verify: `docs/ai/decisions.jsonl` holds exactly one `hitl_decision` with ref_id `provider-adapter-registry-slice` and answer `Mergni #502 (Recommended)`; exactly one `spec_amendment_classification` with `owner_signoff: true` per key 04a6a38c2bd8, 86aff82b4b9d, 21f05c8acd17, db41b41061fe, each written after that hitl line; a `follow_up_status` `done` for `fu-amend-provider-adapter-registry-slice`; `node .aai/scripts/spec-amend.mjs list --strict` exits 0.
- Spec-AC-05 maps to AC-001 (the description says exactly what the seam compares). Verify: the section 6a paragraph of `.aai/system/AUTONOMOUS_LOOP.md` that names `links.pr` also contains the literals `newest first-parent commit` and `(#<n>)`, and the fragment "with a PR number in `links.pr` (SPEC-0226)" no longer appears.

## Acceptance Criteria Status

| Spec-AC    | Description | Status  | Evidence | Review-By | Notes |
|------------|-------------|---------|----------|-----------|-------|
| Spec-AC-01 | WHEN a contract amendment's ride doc on the base ref is status done with an empty links.pr AND the newest first-parent base commit touching that doc has a subject ending in a space then (#n) with n a positive integer, spec-amend list SHALL read the amendment as signed with its tracker done, and follow-ups list SHALL read the tracker done | done | docs/ai/tdd/implied-signing-without-links-pr/red/red-TEST-3017.log; docs/ai/tdd/implied-signing-without-links-pr/green/green-TEST-3017.log; docs/ai/tdd/spec-implied-signing-without-links-pr/mutation-TEST-3017.txt; docs/ai/tdd/implied-signing-without-links-pr/red/red-TEST-3023.log; docs/ai/tdd/implied-signing-without-links-pr/green/green-TEST-3023.log; docs/ai/tdd/spec-implied-signing-without-links-pr/mutation-TEST-3023.txt | — | seam: spec-amend fold to follow-ups.mjs |
| Spec-AC-02 | WHEN the ride doc is not done on the base ref, OR the subject is in any other shape, OR the suffixed commit is not on the base ref's first-parent line, OR the suffix exists only on the checked-out branch, OR the base ref does not resolve, spec-amend list SHALL read the amendment as unsigned | done | docs/ai/tdd/implied-signing-without-links-pr/green/green-TEST-3018.log; docs/ai/tdd/spec-implied-signing-without-links-pr/mutation-TEST-3018.txt; docs/ai/tdd/implied-signing-without-links-pr/red/red-TEST-3019.log; docs/ai/tdd/implied-signing-without-links-pr/green/green-TEST-3019.log; docs/ai/tdd/spec-implied-signing-without-links-pr/mutation-TEST-3019.txt; docs/ai/tdd/implied-signing-without-links-pr/green/green-TEST-3020.log; docs/ai/tdd/spec-implied-signing-without-links-pr/mutation-TEST-3020.txt; docs/ai/tdd/implied-signing-without-links-pr/green/green-TEST-3021.log; docs/ai/tdd/spec-implied-signing-without-links-pr/mutation-TEST-3021.txt | — | fail closed |
| Spec-AC-03 | WHEN the real ledger at 72a8c2ea without the six PR 501 overlays is read against base 72a8c2ea, the six PR 501 and four PR 502 contract records SHALL read signed and the totals SHALL be 400 signed, 142 measurement, 2 unsigned-tracked | done | docs/ai/tdd/implied-signing-without-links-pr/red/red-TEST-3022.log; docs/ai/tdd/implied-signing-without-links-pr/green/green-TEST-3022.log; docs/ai/tdd/spec-implied-signing-without-links-pr/mutation-TEST-3022.txt | — | real-history replay |
| Spec-AC-04 | The four SPEC-0253 contract records are signed by one hitl_decision carrying Mergni #502 (Recommended) and one owner classification per record, the tracker reads done, and list --strict exits 0 | done | docs/ai/tdd/implied-signing-without-links-pr/red/red-TEST-3024.log; docs/ai/tdd/implied-signing-without-links-pr/green/green-TEST-3024.log; docs/ai/tdd/spec-implied-signing-without-links-pr/mutation-TEST-3024.txt | — | ledger action |
| Spec-AC-05 | AUTONOMOUS_LOOP.md section 6a states the squash-subject comparison next to the links.pr rule | done | docs/ai/tdd/implied-signing-without-links-pr/red/red-TEST-3025.log; docs/ai/tdd/implied-signing-without-links-pr/green/green-TEST-3025.log; docs/ai/tdd/spec-implied-signing-without-links-pr/mutation-TEST-3025.txt | — | canon sentence |

## Implementation plan

- `.aai/scripts/spec-amend.mjs`: D2. No other caller changes; `checkRideMerged` stays exported with the same signature.
- `tests/skills/test-aai-spec-amend.sh`: TEST-3017 to TEST-3024 below, registered in `main()` after `test_519_existing_overlays_continue_to_fold_signed`. Fixture repos follow TEST-517: `git init -q -b main`, local `user.email`/`user.name`, every setup command's exit code checked.
- `.aai/system/AUTONOMOUS_LOOP.md`: D3.
- `docs/ai/decisions.jsonl`: D4, append-only.
- Edge cases: two subjects like `(#480) (#483)` read #483 (only the end is anchored); the same doc reachable through several index keys shares one cached entry object, so one `git log` per doc; a spawn failure reads unmerged, never throws.

## Seams crossed

| Seam | Producer side | Consumer side | Test |
|------|---------------|---------------|------|
| implied signature to tracker projection | spec-amend.mjs foldAmendments followUps | follow-ups.mjs list status | TEST-3023 |
| real squash history to the fold | GitHub squash subjects on origin/main | spec-amend.mjs list | TEST-3022 |
| canonical merge flow to the check | close-work-item.mjs leaves links.pr empty | checkRideMerged | TEST-3017, TEST-3022 |

Residual risks (no automated test crosses them):
- A merge done outside the squash convention (a merge commit, a rebase merge, a platform whose squash title differs, such as Azure DevOps "Merged PR <n>: ...") reads unsigned; the hand overlay path stays available. Fail closed.
- A later direct push to the base branch that touches a ride doc makes the ride read unsigned from then on (the newest touching commit decides). Fail closed.
- A later PR that touches an older done ride doc makes that ride read merged through the later PR's number; the doc was already done on the base, so the reading is about a merged ride either way.
- SPEC-0226 does not tell a directed merge from a lane or standing merge, and neither does this scope (out of scope per intake).
- TEST-3022 needs commit 72a8c2ea in the checkout; CI checks out with `fetch-depth: 0` (`.github/workflows/skill-suite.yml`). A shallow clone fails the test with a message naming the missing commit.

## Test Plan

| Test ID   | Spec-AC    | Type        | File path (expected)               | Description | Mutation | Status  |
|-----------|------------|-------------|------------------------------------|-------------|----------|---------|
| TEST-3017 | Spec-AC-01 | integration | tests/skills/test-aai-spec-amend.sh | test_3017_squash_subject_signs_empty_links_pr: fixture repo, done doc with links pr [], committed as feat: ride (#77); list --base-ref main --json shows bucket signed, owner_signoff true, tracked_status done; list --strict exits 0. RED on the pre-change tree: bucket unsigned-tracked | `sed:s/return info\.squashPr !== null;/return false;/` on .aai/scripts/spec-amend.mjs | green |
| TEST-3018 | Spec-AC-02 | integration | tests/skills/test-aai-spec-amend.sh | test_3018_not_done_doc_stays_unsigned: draft doc with links pr [], newest base subject ends in (#5); reads unsigned-tracked, owner_signoff false | `sed:s/if \(info\.status !== 'done'\) return false;/if (false) return false;/` on .aai/scripts/spec-amend.mjs | green |
| TEST-3019 | Spec-AC-02 | integration | tests/skills/test-aai-spec-amend.sh | test_3019_subject_shape_is_strict: five fixture repos, done doc with links pr [], newest base subjects chore: no suffix, fix: x (#12) trailing, fix: x (#0), fix: x (#12a), Merge pull request #12 from o/b; each reads unsigned-tracked; plus one repo where --base-ref names a missing ref reads unsigned-tracked | `sed:s/\[1-9\]\[0-9\]\*/[0-9]*/` on .aai/scripts/spec-amend.mjs | green |
| TEST-3020 | Spec-AC-02 | integration | tests/skills/test-aai-spec-amend.sh | test_3020_first_parent_only: the done doc lands on a side branch in a commit with subject feat: side (#7), joined to main by git merge --no-ff -m merge side; list --base-ref main reads unsigned-tracked | `sed:s/'-1', '--first-parent', /'-1', /` on .aai/scripts/spec-amend.mjs | green |
| TEST-3021 | Spec-AC-02 | integration | tests/skills/test-aai-spec-amend.sh | test_3021_pr_number_read_from_base_not_checkout: main holds the done doc with links pr [] under subject chore: no suffix; a checked-out branch adds a commit touching that doc with subject feat: y (#9); list --base-ref main from that branch reads unsigned-tracked | `sed:s/'--format=%s', baseRef, '--'/'--format=%s', 'HEAD', '--'/` on .aai/scripts/spec-amend.mjs | green |
| TEST-3022 | Spec-AC-03 | integration | tests/skills/test-aai-spec-amend.sh | test_3022_real_history_replay_501_502: git show 72a8c2ea:docs/ai/decisions.jsonl into a scratch file, drop the six PR 501 overlay lines by classifies_record, run list --base-ref 72a8c2ea --json from PROJECT_ROOT; the ten named record keys read signed and the bucket totals are 400 signed, 142 measurement, 2 unsigned-tracked; a missing 72a8c2ea fails naming the commit. RED on the pre-change tree: 390 signed, 12 unsigned-tracked | `sed:s/, isDone, rel: rels\[n\] \}/, isDone }/` on .aai/scripts/spec-amend.mjs | green |
| TEST-3023 | Spec-AC-01 | integration | tests/skills/test-aai-spec-amend.sh | test_3023_follow_ups_reads_tracker_done: the TEST-3017 fixture read by the real follow-ups.mjs list --status all --json; the fu-amend tracker reads done | `sed:s/if \(st && st\.s > 0 && st\.u === 0\) \{/if (false) {/` on .aai/scripts/spec-amend.mjs | green |
| TEST-3024 | Spec-AC-04 | contract    | tests/skills/test-aai-spec-amend.sh | test_3024_pr_502_signatures_on_ledger: the project ledger holds exactly one hitl_decision on provider-adapter-registry-slice with answer Mergni #502 (Recommended), one owner classification per key 04a6a38c2bd8 86aff82b4b9d 21f05c8acd17 db41b41061fe each after that line, a follow_up_status done for fu-amend-provider-adapter-registry-slice; spec-amend list --strict exits 0 | `sed:s/Mergni #502 \(Recommended\)/Mergni #502/` on docs/ai/decisions.jsonl | green |
| TEST-3025 | Spec-AC-05 | contract    | tests/skills/test-aai-spec-amend.sh | test_3025_canon_states_squash_comparison: the AUTONOMOUS_LOOP.md paragraph naming links.pr contains newest first-parent commit and (#<n>), and the old fragment with a PR number in links.pr (SPEC-0226) is gone | `sed:s/newest first-parent commit/newest commit/` on .aai/system/AUTONOMOUS_LOOP.md | green |

RED plan: TEST-3017, TEST-3022 and TEST-3023 are observed failing on the pre-change tree (the measurement above already shows the 3022 numbers); TEST-3018 to TEST-3021 pass on the pre-change tree (today's code refuses everything with an empty `links.pr`), so their RED is the mutation run of each row after GREEN; TEST-3024 and TEST-3025 are RED before the ledger action and the canon edit. RED and GREEN runs are logged under `docs/ai/tdd/`.

## Verification

- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-spec-amend.sh` exits 0 (run with `env -u AAI_ROLE`).
- `node .aai/scripts/mutation-run.mjs` for each Test Plan row; each row reddens its test.
- `node .aai/scripts/spec-amend.mjs list --strict` exits 0 on the ride branch after D4.
- `node .aai/scripts/follow-ups.mjs list --status all --json` shows `fu-amend-provider-adapter-registry-slice` as `done`.
- Regression: `tests/skills/test-aai-follow-ups.sh` and `tests/skills/test-aai-merge-cleanup.sh` exit 0 (both consume the fold or its fixtures).
- PASS criteria: all TEST-xxx green, all Spec-AC terminal.

## Evidence contract

Per artifact: ref_id `implied-signing-without-links-pr`, Spec-AC and TEST ids, command, exit code, evidence path under `docs/ai/tdd/` or `docs/ai/reports/`, commit SHA.

### Evidence by strategy

| Strategy     | Evidence this spec may demand                                   |
|--------------|-----------------------------------------------------------------|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix — unchanged |
| loop         | per-TEST-xxx green runs; RED-proof observed, storage optional    |
| direct       | targeted regression tests green (exit codes) plus the scoped diff — NO stored RED artifact, NO matrix beyond the declared versions |
| untested     | the recorded strategy rationale plus the scoped diff — no test suites demanded for the scope itself |

## Constitution deviations

None.

## Registry

Registry items closed by this scope: `fu-amend-provider-adapter-registry-slice` (CLOSED FULLY by D4).

Not closed, subject adjacent: `fu-amend-list-shows-unsigned-signed` (a record-key overlay collision reads a record signed; a different cause in the overlay match, untouched here); `fu-amend-update-installs-ref-guar-f8caa1` (its ride doc CHANGE-0192 is `draft`, so no merge implies a signature); `fu-platform-azure-links-pr-url` (merge-cleanup's links.pr URL parsing, a different reader); `fu-product-doc-names-removed-sign-merged` (product doc prose, untouched).
