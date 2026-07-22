---
review:
  scope: "inline working-tree diff (uncommitted): .aai/scripts/branch-guard.mjs (NEW), tests/skills/test-aai-branch-guard.sh (NEW), .aai/SKILL_PR.prompt.md (additive), .aai/AGENTS.md (additive note); docs/specs/SPEC-DRAFT-spec-branch-per-work-item-hygiene.md + docs/issues/ISSUE-DRAFT-branch-per-work-item-hygiene.md bookkeeping"
  spec: docs/specs/SPEC-DRAFT-spec-branch-per-work-item-hygiene.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/test-aai-branch-guard.sh test_001 -> guard exit 0; .aai/scripts/branch-guard.mjs:210-212; suite green (bash tests/skills/test-aai-branch-guard.sh, exit 0)" }
      - { ac: Spec-AC-02, call: compliant, citation: "test_002/003/004 -> guard exit 1/2/3 + exact remediation; branch-guard.mjs:196-208; independent probe (see report) confirms a wrong branch never returns 0" }
      - { ac: Spec-AC-03, call: compliant, citation: "test_005 (5 sub-cases incl. base+broken-STATE->4 and detached+broken-STATE->2 precedence) -> branch-guard.mjs:171-194 order matches spec Design item 2 before item 3" }
      - { ac: Spec-AC-04, call: compliant, citation: "test_006 (all 10 current_focus.type rows) -> branch-guard.mjs:156-169, TYPE_TOKENS closed map + '?? chore' default" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/SKILL_PR.prompt.md:14-20 '0. BRANCH HYGIENE' precedes PROCESS step 1 (DERIVE SCOPE, line 30) and step 5 (PUSH + PR, line 127); test_007 green" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/AGENTS.md:170-174 'One branch per work item' note names branch-guard.mjs; test_008 green" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Guard behaves identically in CI (Linux) as verified here (macOS)", closes_with: "a green CI run of tests/skills/test-aai-branch-guard.sh on the project's Linux runner; the diff itself only proves POSIX-portable construction (full mktemp templates, git init -b main, no stat -f, honors shebang)" }
    - { claim: "No other in-flight AAI skill/prompt path bypasses SKILL_PR and pushes directly, which would make the new precondition unreachable in practice", closes_with: "a repo-wide grep for other `git push` call sites outside SKILL_PR.prompt.md; out of this diff's scope" }
  overall: pass
---

# Code Review — branch-per-work-item-hygiene (L1 lightweight lane)

## Scope

Reviewed as an inline (non-worktree) diff: HEAD and `main` are the same commit
(`2efc65d`); the entire scope is uncommitted working-tree state, matching
`docs/ai/STATE.yaml` `worktree.user_decision: inline`. Verified via
`git status --porcelain` and `git diff --stat`:

```
 M .aai/AGENTS.md          | 6 ++
 M .aai/SKILL_PR.prompt.md | 7 ++
?? .aai/scripts/branch-guard.mjs
?? docs/issues/ISSUE-DRAFT-branch-per-work-item-hygiene.md
?? docs/specs/SPEC-DRAFT-spec-branch-per-work-item-hygiene.md
?? tests/skills/test-aai-branch-guard.sh
```

No unrelated dirty files. `protected_paths_l3` (`state.mjs`,
`lib/state-engine.mjs`, `lib/state-core.mjs`, `allocate-doc-number.mjs`,
`pre-commit-checks.{sh,ps1}`, `WORKFLOW.md`, `CONSTITUTION.md`) — none
touched, confirmed by `git status --porcelain` above.

## Spec-AC table walk

See the structured `ac_walk` block above; all six Spec-AC rows compliant with
citations. `docs/specs/...` "Acceptance Criteria Status" table rows are all
`done` with non-empty evidence (TEST-xxx + `docs/ai/tdd/green-branch-guard-20260722T214726Z.log`,
which exists and was inspected). RED evidence
(`docs/ai/tdd/red-branch-guard-20260722T214622Z.log`, `RED_CLASS:
product_red`) also exists and was inspected — shows the pre-fix suite failing
with `MODULE_NOT_FOUND` (guard absent) and `grep -c` = 0 for both prompt/doc
RED-proofs, matching the spec's claims.

## Code quality — evidence

**Read-only STATE contract.** `branch-guard.mjs` imports only `splitLines`
from `lib/state-core.mjs` and `readScalar`/`unquoteScalar` from
`lib/state-engine.mjs` — the same read-only subset `orchestration-dispatch.mjs`
already imports (confirmed: `grep -n "import" .aai/scripts/orchestration-dispatch.mjs`
shows the identical pattern). Grepped the whole file for `writeFileSync`,
`renameSync`, `appendFileSync`: none present. The only `fs` call is
`fs.readFileSync` inside `readFocus()`. No write path to `docs/ai/STATE.yaml`
exists anywhere in the diff.

**Fail-closed correctness / check order.** The implementation's numbered
comments (`branch-guard.mjs:171-212`, "Order item 1..6") match the spec's
Design section check order exactly: work-tree check -> detached -> STATE
read -> base-branch -> containment -> pass. Verified precedence empirically
via `test_003`'s and `test_005`'s cross-precedence sub-cases (detached+broken
STATE -> 2, not 4; base+broken STATE -> 4, not 1) — both green. Independently
probed the highest-severity risk class (a wrong branch silently exiting 0):
built a throwaway repo with `current_focus.ref_id: my-feature` and checked
out `totally-wrong-branch-name`; the guard printed the mismatch message and
exited 3, never 0. Also confirmed the RED-proof is genuine: pointing
`AAI_BRANCH_GUARD` at a nonexistent path makes `test_001` (and all
behavioral tests) fail, not spuriously pass — `test_002`'s exit-code
assertion alone would coincidentally match Node's ENOENT exit code (both are
1), but its companion stderr-content assertion (exact remediation string)
correctly fails against a stack trace, so the test still discriminates in
practice; verified by direct execution.

**ref_id-\>branch mapping.** `branch.includes(focus.refId)` is a literal
substring test (not regex), so no ref_id triggers ReDoS or a false regex
match. The base-branch check runs strictly before the containment check
(order item 4 before item 5), so a base branch that coincidentally contains
the ref_id substring is still reported as exit 1, not a false exit 0 — this
exact adversarial case is covered by `test_002`'s negative control
(`release-$ref` as base) and passed. `--suggest`'s type-token map
(`TYPE_TOKENS`) is a closed object with `?? 'chore'` fallback — confirmed it
never throws on an unmapped or `null` type.

**Portability.** No `stat -f`; `mktemp` calls all use full templates
(`mktemp -d "$TMP_ROOT/${1}.XXXXXX"`, `mktemp "$TMP_ROOT/err.XXXXXX"`); the
suite's own `#!/usr/bin/env bash` shebang is honored (verified via
`.aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-branch-guard.sh`
-> exit 0, matching the CI invocation shape); `git init -b main` used in
every fixture (never assumes a default local `main`). `branch-guard.mjs`
itself is plain Node stdlib (`fs`, `path`, `child_process`, `url`) with no
platform-specific syscalls.

**Remediation string correctness.** `remediation(type, refId, base)` builds
`git checkout -b <type-token>/<ref-id> origin/<base>` using the STATE-derived
type/ref_id and the resolved `--base`; every non-zero-exit stderr path
(base/detached/mismatch) was asserted verbatim by the matching test
(`test_002`/`test_003`/`test_004`) and independently reproduced during this
review with matching output.

**Findings:** none BLOCKING or NON-BLOCKING. One area was investigated and
found to be a non-issue after concrete reproduction attempts: `currentBranch()`
(`branch-guard.mjs:92-94`, called unguarded at line 178) is not wrapped in a
try/catch, so a `git rev-parse --abbrev-ref HEAD` failure after the
work-tree check passes would surface as an uncaught Node exception (exit
code 1, colliding with the documented "on base branch" exit code) rather
than the documented exit-4 config-error path. I attempted to construct a
concrete repro (corrupting `.git/HEAD` after work-tree validation) — in
practice `git rev-parse --is-inside-work-tree` itself fails first under that
corruption and the guard correctly falls through to the existing exit-4
path (`isInsideWorkTree()`'s try/catch), so no working false-open or
mislabeled-exit scenario was reproducible from this diff. Recorded here as
an honest gap rather than a finding, since the review skill requires a
concrete failure scenario to gate, and none was found in the time
available — see `cannot_verify` disposition below (a defense-in-depth
try/catch would remove the theoretical residual risk cheaply, but nothing
observed here demonstrates it firing).

## Test quality

All 8 tests run in throwaway `mktemp`-rooted repos under a single
`TMP_ROOT`, cleaned by an EXIT trap (`rm -rf "$TMP_ROOT"`); no `git clean`
used; no interference with the reviewer's own working tree confirmed by
`git status --porcelain` before/after the run. `test_001` crosses the STATE
seam for real (`state.mjs set-focus` as producer, `branch-guard.mjs` as
consumer) rather than hand-writing a STATE fixture for the happy path.
`test_002`/`test_005` each include an explicit negative/precedence control
(coincidental base-branch containment; base-vs-STATE and detached-vs-STATE
precedence) that specifically targets the false-open class the dispatch
flagged as highest severity — all green, and independently reproduced
outside the suite (see above). No test asserts a tautology (each assertion
pairs an exit code with a specific stderr/stdout content check).

## Verification run log

- `bash tests/skills/test-aai-branch-guard.sh` -> exit 0, all 8 PASS.
- `.aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-branch-guard.sh` -> exit 0.
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-branch-per-work-item-hygiene.md` -> `LINT PASS: no structural findings.`
- `node .aai/scripts/branch-guard.mjs --suggest` on this branch -> `fix/branch-per-work-item-hygiene`, matching `current_focus.ref_id`.
- `node .aai/scripts/branch-guard.mjs --base main` on this branch -> exit 0, `OK — branch "fix/branch-per-work-item-hygiene" matches current_focus.ref_id "branch-per-work-item-hygiene"`.
- Independent false-open probe (fresh throwaway repo, `ref_id: my-feature`, branch `totally-wrong-branch-name`) -> exit 3, never 0.
- `AAI_BRANCH_GUARD=/nonexistent/path bash tests/skills/test-aai-branch-guard.sh 002` -> FAIL as expected (RED-proof holds via the stderr-content assertion).

## Warnings disposition (H6)

No open WARNINGs (NON-BLOCKING findings) from this pass — nothing to
promote to `decisions.jsonl` or a follow-up ref.

## Next steps

None blocking. Scope is ready for `code_review.status: pass` and SKILL_PR.
