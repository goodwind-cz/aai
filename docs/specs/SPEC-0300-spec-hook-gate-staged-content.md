---
id: spec-hook-gate-staged-content
type: spec
number: 300
status: done
frozen_sha256: 6b176e2c787a41cbcf8ccccd6c9ed332ce71c922d7ca598910ab948ab2d57685
mutation_gate: v1
ceremony_level: 3
links:
  requirement: hook-gate-staged-content
  rfc: null
  pr: []
  commits: []
---

# Commit-time guards judge the staged content of every staged file

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-0122-hook-gate-staged-content.md
  (follow-ups `fu-hook-gate-reads-worktree-spec`,
  `fu-precommit-deleted-staged-skip`, `fu-precommit-suffix-env-evidence`,
  `fu-precommit-quoted-path-skip`; owner choice 2026-11-17).
- Prior scopes this one builds on (closed, not edited):
  docs/specs/SPEC-0297-spec-issue-gate-via-spec.md (an intake doc gates
  through its linked specs; the hook gates `docs/issues/` done-flips);
  docs/specs/SPEC-0298-spec-pr-ceremony-friction-fixes.md (CHECK 2 content
  scan reads the staged blob; evidence folders judged by content).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, bash 3.2 suites
  through `.aai/scripts/aai-run-tests.sh`).

## Implementation strategy

- Strategy: tdd
- Rationale: guard changes on an L3 surface (`pre-commit-checks.sh`) and in
  a gate predicate a project can set to enforce. Every changed behaviour can
  be seen failing on the unchanged tree (the hook gate reads the working-tree
  spec, a staged secret behind an `rm` exits 0, `prod.env` in an evidence
  folder exits 0, a non-ASCII name exits 0), so each AC gets a RED
  observation and a mutation record. The strategy was not chosen at intake
  (autopilot); Planning chose it.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: L3 protected surface (`.aai/scripts/pre-commit-checks.sh`
  is listed in `protected_paths_l3`); the main checkout carries other
  sessions' uncommitted files.
- User decision: worktree (owner directive in the dispatch brief)
- Base ref: origin/main at 65113785
- Worktree branch/path: fix/hook-gate-staged-content at
  /Users/ales/Projects/aai-worktrees/hook-gate-staged-content
- Review required: true
- Review scope (explicit paths): .aai/scripts/lib/docs-audit-core.mjs;
  .aai/scripts/docs-audit.mjs; .aai/templates/git-hooks/pre-commit-index.sh;
  .aai/scripts/pre-commit-checks.sh; tests/skills/test-aai-docs-audit.sh;
  tests/skills/test-aai-pre-commit-checks.sh; CHANGELOG.md;
  docs/product/docs-close-gate.md;
  docs/issues/ISSUE-0122-hook-gate-staged-content.md;
  docs/specs/SPEC-0300-spec-hook-gate-staged-content.md.

## Decisions

- D1 (staged source for the gate's doc set). `gateFile(root, filePath,
  { staged: true })` builds the doc set the linked-spec resolver walks from
  the commit being made instead of the working tree: the candidate paths are
  the union of the index (`git ls-files -z`) and HEAD (`git ls-tree -r -z
  --name-only HEAD`) under `docs/`, admitted by the same rule as
  `scanAuditDocs` (one shared admission predicate, not a copy). Each path's
  content is its index blob (stage 0) when the index holds one, else HEAD's
  committed blob. A path present only in the working tree (untracked) is not
  part of the commit and is not read. A HEAD-only doc whose frontmatter id
  is also carried by a doc in the index (a rename in the commit, such as a
  DRAFT numbered at close) is not read: the index copy is that doc
  (post-freeze amendment after validation r1, NON-BLOCKING 1). In staged
  mode the gate's configuration (`scan_exclude`, `review_by_methods`) is
  read the same way, from the staged `docs/ai/docs-audit.yaml`, else HEAD's,
  else none, never from an unstaged working-tree edit (post-PR bot-finding
  remediation, Codex P1 on PR #569, same amendment). The blobs are read in one batched
  `git cat-file --batch` call. The resolver, the two-pass id match, the
  reverse-link search and the spec gate are the existing functions; only the
  entry source changes. Without the option the working-tree scan is
  unchanged.
- D2 (CLI). `docs-audit.mjs --gate-file <file> --staged` selects D1. The
  file argument is still the gated doc's content (the hook's staged blob
  copy). `--staged` without `--gate-file` is a usage error (exit 2). Outside
  a git work tree, staged mode cannot evaluate and exits 2 with the reason.
  Exit codes are otherwise those of `--gate-file` (1 fail, 0 pass,
  2 unreadable).
- D3 (hook). `.aai/templates/git-hooks/pre-commit-index.sh` passes
  `--staged` on its close-gate call. An older vendored `docs-audit.mjs`
  ignores the unknown flag and keeps the working-tree read (the parser has
  no unknown-flag error), so a hook installed before the script is updated
  degrades to today's behaviour, never to a broken commit.
- D4 (staged file list). `pre-commit-checks.sh` reads the staged list once,
  NUL-separated (`git diff --cached --name-only -z`), into a bash array, so
  a name git would C-quote (non-ASCII, tab, quote) is checked under its real
  path. CHECKs 2, 3 and 4 iterate that array (bash 3.2 safe under `set -u`).
- D5 (index existence and staged content). A staged path is checked when
  the index holds a stage-0 blob for it (`git cat-file -e ":0:<path>"`),
  whatever the working tree holds; a staged deletion has no index blob and
  is skipped as before. CHECK 2's content scan, CHECK 3's debug scan and
  CHECK 4's marker count read that blob (`git show ":0:<path>"`), consumed
  whole (no early-closing reader under pipefail).
- D6 (suffix dotenv). Inside the four evidence folders a basename `.env`,
  `.env.*` or `*.env` is blocked by name; outside them the name check is
  unchanged (`*.env*` already covers the suffix form).
- D7 (`fu-gate-not-called-by-close-item` stays open). Wiring the gate into
  `close-work-item.mjs` changes the behaviour of the one writer of done
  flips (a refusal path inside the close ceremony) and touches a file whose
  bytes are hash-pinned by four suites; that is not the small, safe wiring
  the owner allowed, so this scope does not take it.

## Acceptance Criteria Mapping

- Spec-AC-01, Spec-AC-02, Spec-AC-04 map to `fu-hook-gate-reads-worktree-spec`
  (D1, D2).
- Spec-AC-03 maps to the same follow-up through the real hook (D3).
- Spec-AC-05 maps to `fu-precommit-deleted-staged-skip` (D5).
- Spec-AC-06 maps to `fu-precommit-suffix-env-evidence` (D6).
- Spec-AC-07 maps to `fu-precommit-quoted-path-skip` (D4).
- Spec-AC-08 maps to preservation and the moved pins of the pre-commit
  suite.
- Spec-AC-09 maps to the consumer-visible record (CHANGELOG, product doc).
- Spec-AC-10 maps to validation r1 NON-BLOCKING 1 (a rename in the close
  commit must not be gated on its stale HEAD copy) and D1 as amended.
- Spec-AC-11 maps to Codex P1 on PR #569 (an unstaged scan_exclude edit
  must not hide a staged linked spec) and D1 as amended.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN an intake doc with no AC table is gated with docs-audit.mjs --gate-file on a copy of it plus --staged in a git fixture whose linked spec has a non-terminal row in the index and a reconciled copy in the working tree, the command SHALL exit 1 and name that spec; WHEN the index copy is reconciled and the working-tree copy has a non-terminal row it SHALL exit 0; the same two cases without --staged SHALL keep today's working-tree verdicts (exit 0 then exit 1) | done | TEST-3860 green docs/ai/tdd/hook-gate-staged-content/green-test_3860_staged_gate_reads_index_spec.log, RED docs/ai/tdd/hook-gate-staged-content/red-test_3860_staged_gate_reads_index_spec.log, mutation docs/ai/tdd/spec-hook-gate-staged-content/mutation-TEST-3860.txt; validation docs/ai/validation/VALIDATION-hook-gate-staged-content-r4.md | — | D1, D2 |
| Spec-AC-02 | WHEN the linked spec is committed reconciled in HEAD, removed from the index with git rm --cached and left non-terminal in the working tree, --gate-file --staged SHALL exit 0 through the HEAD blob; WHEN a reconciled linked spec exists only as an untracked working-tree file, --gate-file --staged SHALL exit 1 with the no linked spec reason | done | TEST-3861 green docs/ai/tdd/hook-gate-staged-content/green-test_3861_staged_gate_head_fallback.log, RED docs/ai/tdd/hook-gate-staged-content/red-test_3861_staged_gate_head_fallback.log, mutation docs/ai/tdd/spec-hook-gate-staged-content/mutation-TEST-3861.txt; validation docs/ai/validation/VALIDATION-hook-gate-staged-content-r4.md | — | D1 |
| Spec-AC-03 | WHEN close_gate is enforce and a commit stages an intake done-flip and its linked spec with a non-terminal row while the working-tree spec is reconciled, git commit through the installed hook SHALL exit non-zero naming the intake id; WHEN the staged spec is reconciled and the working-tree spec has an unstaged non-terminal row, git commit SHALL exit 0 and HEAD SHALL move | done | TEST-3863 green docs/ai/tdd/hook-gate-staged-content/green-test_3863_hook_gates_staged_linked_spec.log, RED docs/ai/tdd/hook-gate-staged-content/red-test_3863_hook_gates_staged_linked_spec.log, mutation docs/ai/tdd/spec-hook-gate-staged-content/mutation-TEST-3863.txt; validation docs/ai/validation/VALIDATION-hook-gate-staged-content-r4.md | — | D3 |
| Spec-AC-04 | docs-audit.mjs --staged without --gate-file SHALL exit 2 with a usage error; --gate-file --staged run in a directory that is not a git work tree SHALL exit 2 | done | TEST-3862 green docs/ai/tdd/hook-gate-staged-content/green-test_3862_staged_usage_and_non_git.log, RED docs/ai/tdd/hook-gate-staged-content/red-test_3862_staged_usage_and_non_git.log, mutation docs/ai/tdd/spec-hook-gate-staged-content/mutation-TEST-3862.txt; validation docs/ai/validation/VALIDATION-hook-gate-staged-content-r4.md | — | D2 |
| Spec-AC-05 | WHEN app/config.txt holding an api_key assignment with a quoted 12-character value is staged and then deleted from the working tree, bash .aai/scripts/pre-commit-checks.sh SHALL exit 1 and print Potential secret detected in app/config.txt once; WHEN app.js holding console.log is staged and then deleted from the working tree, the script SHALL print Debug statements in app.js | done | TEST-3864 green docs/ai/tdd/hook-gate-staged-content/green-test_3864_deleted_worktree_copy_still_scanned.log, RED docs/ai/tdd/hook-gate-staged-content/red-test_3864_deleted_worktree_copy_still_scanned.log, mutation docs/ai/tdd/spec-hook-gate-staged-content/mutation-TEST-3864.txt; validation docs/ai/validation/VALIDATION-hook-gate-staged-content-r4.md | — | D5 |
| Spec-AC-06 | WHEN docs/ai/tdd/prod.env, docs/ai/reports/x.env, docs/ai/validation/stage.env or docs/ai/reviews/a.env is staged with harmless content, the script SHALL exit 1 and print Sensitive file staged followed by that path; a docs/ai/tdd/environment-notes.txt holding only variable names SHALL still exit 0 | done | TEST-3865 green docs/ai/tdd/hook-gate-staged-content/green-test_3865_suffix_dotenv_blocked_in_evidence.log, RED docs/ai/tdd/hook-gate-staged-content/red-test_3865_suffix_dotenv_blocked_in_evidence.log, mutation docs/ai/tdd/spec-hook-gate-staged-content/mutation-TEST-3865.txt; validation docs/ai/validation/VALIDATION-hook-gate-staged-content-r4.md | — | D6 |
| Spec-AC-07 | WHEN app/café.txt holding an api_key assignment is staged, the script SHALL exit 1 and print Potential secret detected in app/café.txt with the unquoted name; WHEN secrets/clé.txt is staged with harmless content it SHALL exit 1 and print Sensitive file staged: secrets/clé.txt; both hold with core.quotePath at its default | done | TEST-3866 green docs/ai/tdd/hook-gate-staged-content/green-test_3866_non_ascii_names_checked.log, RED docs/ai/tdd/hook-gate-staged-content/red-test_3866_non_ascii_names_checked.log, mutation docs/ai/tdd/spec-hook-gate-staged-content/mutation-TEST-3866.txt; validation docs/ai/validation/VALIDATION-hook-gate-staged-content-r4.md | — | D4 |
| Spec-AC-08 | The seven TEST-3454 baseline fixtures SHALL give the baseline's stdout, stderr and exit code, the TEST-3454 numstat pin and the TEST-3461 line-count pin SHALL name the new measured values, and the pre-commit and docs-audit suites SHALL exit 0 | done | TEST-3867 green docs/ai/tdd/hook-gate-staged-content/green-test_3454_small_input_parity.log and docs/ai/tdd/hook-gate-staged-content/green-test_3461_line_budget_and_follow_up.log, RED docs/ai/tdd/hook-gate-staged-content/red-TEST-3867-test_3454_small_input_parity.log, mutation docs/ai/tdd/spec-hook-gate-staged-content/mutation-TEST-3867.txt; suites green in docs/ai/validation/VALIDATION-hook-gate-staged-content-r4.md | — | preservation |
| Spec-AC-09 | CHANGELOG.md SHALL hold exactly one per-entry unreleased heading for this fix, and docs/product/docs-close-gate.md SHALL say the hook reads the intake doc and its linked specs from the index with HEAD as the fallback | done | TEST-3868 green docs/ai/tdd/hook-gate-staged-content/green-test_3868_changelog_and_product_doc.log, RED docs/ai/tdd/hook-gate-staged-content/red-test_3868_changelog_and_product_doc.log, mutation docs/ai/tdd/spec-hook-gate-staged-content/mutation-TEST-3868.txt; validation docs/ai/validation/VALIDATION-hook-gate-staged-content-r4.md | — | consumer record |
| Spec-AC-10 | WHEN a linked spec committed in HEAD as docs/specs/SPEC-DRAFT-spec-5865.md with a non-terminal row is renamed with git mv in the index and reconciled there, --gate-file --staged on the intake SHALL exit 0 and SHALL NOT name the old DRAFT path | done | TEST-3869 green docs/ai/tdd/hook-gate-staged-content/green-test_3869_staged_rename_drops_head_copy.log, RED docs/ai/tdd/hook-gate-staged-content/red-test_3869_staged_rename_drops_head_copy.log, mutation docs/ai/tdd/spec-hook-gate-staged-content/mutation-TEST-3869.txt; validation docs/ai/validation/VALIDATION-hook-gate-staged-content-r4.md | — | D1 (amended) |
| Spec-AC-11 | WHEN the staged docs/ai/docs-audit.yaml holds scan_exclude: [] and an unstaged working-tree edit adds a failing linked spec to scan_exclude while a second linked spec passes, --gate-file --staged on the intake SHALL exit 1 naming the failing spec; once that edit is staged it SHALL exit 0 | done | TEST-3870 green docs/ai/tdd/hook-gate-staged-content/green-test_3870_staged_config_from_index.log, RED docs/ai/tdd/hook-gate-staged-content/red-test_3870_staged_config_from_index.log, mutation docs/ai/tdd/spec-hook-gate-staged-content/mutation-TEST-3870.txt | — | D1 (amended, Codex P1 on PR #569) |

## Implementation plan

- `.aai/scripts/lib/docs-audit-core.mjs`: extract the per-path admission
  rule of `scanAuditDocs` into one predicate used by the walker and by a new
  staged scan; `scanGateEntries(root, { staged })` reads entries from the
  index with HEAD fallback through one `git cat-file --batch`; `gateFile`
  takes `{ staged }` (D1).
- `.aai/scripts/docs-audit.mjs`: `--staged` flag, valid only with
  `--gate-file` (D2).
- `.aai/templates/git-hooks/pre-commit-index.sh`: `--staged` on the
  close-gate call (D3).
- `.aai/scripts/pre-commit-checks.sh`: NUL-separated staged list into an
  array; index-existence test and staged-blob reads in CHECKs 2-4; `*.env`
  in the evidence-folder dotenv override (D4-D6).
- Pins: `tests/skills/test-aai-pre-commit-checks.sh` TEST-3454 numstat and
  TEST-3461 line counts.
- `CHANGELOG.md`: one `## [unreleased] — <title>` entry;
  `docs/product/docs-close-gate.md`: the known-limit paragraph about the
  working-tree read becomes the staged-read statement.
- Seams: the installed hook calls `docs-audit.mjs --gate-file --staged` on a
  real `git commit` (TEST-3863 commits through it); the hook's staged blob
  copy and the staged doc set must agree on the doc's identity (the `self`
  lookup reads the same index); `pre-commit-checks.sh` runs from the
  installed hook as well (TEST-3831 already commits through it and stays
  green).
- Edge cases: a staged deletion is skipped (no index blob); a merge-conflict
  path has no stage-0 blob and is skipped (a conflicted index cannot be
  committed); a path holding a newline cannot be named on the
  `git cat-file --batch` line protocol and is read with its own
  `git show`; HEAD absent (first commit) contributes no paths.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3860 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | git fixture: intake with no table, linked spec staged with an implementing row, working-tree spec done; --gate-file copy --staged exits 1 naming the spec; swap index and worktree contents, exits 0; without --staged the verdicts are the working-tree ones | target `.aai/scripts/lib/docs-audit-core.mjs`; `sed:s/scanGateEntries\(root, \{ staged \}\)/scanGateEntries(root, {})/` reads the working tree again and the case must fail | green |
| TEST-3861 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh | git fixture: spec committed done, git rm --cached, worktree copy implementing; --staged exits 0 via HEAD; a done spec only untracked in the worktree gives exit 1 with no linked spec | target `.aai/scripts/lib/docs-audit-core.mjs`; `sed:s/'HEAD:' \+ rel/':0:' + rel/` drops the HEAD fallback and the case must fail | green |
| TEST-3862 | Spec-AC-04 | unit | tests/skills/test-aai-docs-audit.sh | --staged alone exits 2 with USAGE ERROR; --gate-file --staged in a non-git directory exits 2 | target `.aai/scripts/docs-audit.mjs`; `sed:s/if \(args\.staged && !args\.gateFile\)/if (false)/` lets a bare --staged run the full audit and the case must fail | green |
| TEST-3863 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh | installed hook, close_gate enforce: staged intake flip plus staged failing spec with a reconciled worktree spec aborts the commit naming the intake id; staged reconciled spec with an unstaged failing worktree spec commits and HEAD moves | target `.aai/templates/git-hooks/pre-commit-index.sh`; `sed:s/--gate-file "\$STAGED_TMP" --staged/--gate-file "$STAGED_TMP"/` drops the staged mode and the case must fail | green |
| TEST-3864 | Spec-AC-05 | integration | tests/skills/test-aai-pre-commit-checks.sh | stage app/config.txt with an assembled api_key line and app.js with console.log, rm both working copies; exit 1, one Potential secret detected in app/config.txt line, one Debug statements in app.js line | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/cat-file -e ":0:\$file"/cat-file -e "HEAD:$file"/` restores the working-tree skip and the case must fail | green |
| TEST-3865 | Spec-AC-06 | integration | tests/skills/test-aai-pre-commit-checks.sh | one fixture per evidence folder staging a *.env basename with harmless content: exit 1 and Sensitive file staged followed by the path; docs/ai/tdd/environment-notes.txt holding variable names exits 0 | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/\*\.env\) name_check=1/.NOMATCH) name_check=1/` lets a suffix dotenv name through and the case must fail | green |
| TEST-3866 | Spec-AC-07 | integration | tests/skills/test-aai-pre-commit-checks.sh | stage app/café.txt with an assembled api_key line and secrets/clé.txt with harmless content under default core.quotePath: exit 1, one Potential secret detected in app/café.txt line, one Sensitive file staged: secrets/clé.txt line | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/--name-only -z/--name-only/` reads the quoted newline list and the case must fail | green |
| TEST-3867 | Spec-AC-08 | integration | tests/skills/test-aai-pre-commit-checks.sh | TEST-3454 parity over the seven baseline fixtures and its numstat pin, TEST-3461 line-count pin, both suites exit 0 | target `tests/skills/test-aai-pre-commit-checks.sh`; `sed:s/\[\[ "\$numstat" == "/[[ "$numstat" == "9/` breaks the moved numstat pin and the case must fail | green |
| TEST-3868 | Spec-AC-09 | unit | tests/skills/test-aai-pre-commit-checks.sh | grep -c of the CHANGELOG heading equals 1; the product doc names the index and HEAD as the hook's read | target `docs/product/docs-close-gate.md`; `sed:s/from the index/from the working tree/` reverts the product statement and the case must fail | green |
| TEST-3869 | Spec-AC-10 | integration | tests/skills/test-aai-docs-audit.sh | git fixture: intake plus SPEC-DRAFT spec committed implementing; git mv to SPEC-5865 and stage a reconciled copy; --gate-file --staged exits 0 and the log never names the DRAFT path | target `.aai/scripts/lib/docs-audit-core.mjs`; `sed:s/!\(d\.fromHead && indexIds\.has\(d\.fmId\)\)/true/` reads the renamed-away HEAD copy again and the case must fail | green |
| TEST-3870 | Spec-AC-11 | integration | tests/skills/test-aai-docs-audit.sh | git fixture: staged config scan_exclude empty, failing and passing linked specs staged, unstaged config edit excludes the failing one; --gate-file --staged exits 1 naming it; staging the edit gives exit 0 | target `.aai/scripts/lib/docs-audit-core.mjs`; `sed:s/const config = staged \? loadStagedConfig\(root\) : loadConfig\(root\);/const config = loadConfig(root);/` reads the working-tree config again and the case must fail | green |

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pre-commit-checks.sh`
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh`
- `node .aai/scripts/mutation-run.mjs --replay --spec <this spec>`
- One full sweep before close (`tests/skills/test-framework.sh`).
- PASS criteria: all TEST-xxx green and every Spec-AC terminal.

## Evidence contract

Per artifact: ref_id `hook-gate-staged-content`, Spec-AC and TEST-xxx,
command, exit code, evidence path under `docs/ai/tdd/hook-gate-staged-content/`
(RED and GREEN logs) and `docs/ai/tdd/spec-hook-gate-staged-content/`
(mutation records), commit SHA once committed.

Registry items closed by this scope: fu-hook-gate-reads-worktree-spec, fu-precommit-deleted-staged-skip, fu-precommit-suffix-env-evidence, fu-precommit-quoted-path-skip

## Residual risks

- Without `--staged` the gate's configuration is still read from the
  working-tree `docs/ai/docs-audit.yaml`; with it (the hook), the staged
  copy, else HEAD's, decides (amended after Codex P1 on PR #569).
- CHECK 7 (PowerShell parse gate) keeps its own newline list and working-tree
  read; a non-ASCII `.ps1` name skips the parse check there. It is a warning
  path on hosts with pwsh, not the secrets check.
- A linked spec the commit deletes (`git rm`) is still read from HEAD, as
  the owner's rule asks ("not in the index at all falls back to HEAD"); a
  deletion of the spec an intake gates through therefore passes on the
  deleted copy. Recorded as a follow-up for an explicit policy.
- The staged scan reads every governed doc's blob on each gated done-flip
  (one `git cat-file --batch` process); it costs one batched read per
  gated doc in the commit, not per scanned doc.
