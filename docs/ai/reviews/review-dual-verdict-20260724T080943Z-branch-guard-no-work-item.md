```yaml
review:
  scope: "git diff (working tree, uncommitted); files: .aai/scripts/branch-guard.mjs, tests/skills/test-aai-branch-guard.sh, docs/INDEX.md, docs/ai/tests/test-runs.jsonl, docs/issues/ISSUE-DRAFT-branch-guard-no-work-item.md (new), docs/specs/SPEC-DRAFT-spec-branch-guard-no-work-item.md (new)"
  spec: docs/specs/SPEC-DRAFT-spec-branch-guard-no-work-item.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/branch-guard.mjs:249-257 (item 5 allowlist check, fires for both set-and-unrelated and cleared ref_id); TEST-009/TEST-010 in tests/skills/test-aai-branch-guard.sh:293-336, observed PASS in local run + docs/ai/tdd/green-20260724T074153Z.log" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/branch-guard.mjs:234-247 (item 4, base check precedes item 5 allowlist at line 253); TEST-012 (chore/legacy-main base-collision) + TEST-002, both observed exit 1 locally and re-verified with an independent fixture (base==chore/legacy-main, ref_id cleared -> exit 4, not 0)" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/branch-guard.mjs:267-274 (item 7, unchanged); TEST-004 (feat/unrelated-name) observed exit 3 locally" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/branch-guard.mjs:226-232 (item 3, Tier A, unconditional, before any branch-name inspection); TEST-011 observed exit 4 locally" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/branch-guard.mjs:207-221 (items 1-2, unchanged, precede STATE read); TEST-003 observed exit 2 locally (both readable-STATE and STATE-absent sub-cases)" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/branch-guard.mjs:267-278 (item 8, unchanged pass path); TEST-001 (real state.mjs writer seam) observed exit 0 locally" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "SKILL_PR actually invokes branch-guard.mjs as a live pre-push gate in a real operator session (vs. TEST-007's static grep-based assertion that the prompt text exists and precedes the PUSH step)", closes_with: "an end-to-end SKILL_PR dry run or operator-observed session log; out of scope for this diff (SKILL_PR.prompt.md is unmodified in this scope)" }
    - { claim: "CI (Linux) green — the spec/PASS-criteria cite 'green on macOS + Linux CI'", closes_with: "the CI run log for this branch/PR; only local macOS execution was performed during this review" }
  overall: pass
```

# Code Review — branch-guard-no-work-item (GitHub #135)

**Role**: Code Review (L1 lightweight lane, single independent pass)
**Scope**: uncommitted working-tree diff — `.aai/scripts/branch-guard.mjs`,
`tests/skills/test-aai-branch-guard.sh`, plus bookkeeping
(`docs/INDEX.md`, `docs/ai/tests/test-runs.jsonl`) and two new draft docs
(`docs/issues/ISSUE-DRAFT-branch-guard-no-work-item.md`,
`docs/specs/SPEC-DRAFT-spec-branch-guard-no-work-item.md`).
**Spec**: `docs/specs/SPEC-DRAFT-spec-branch-guard-no-work-item.md`
(SPEC-FROZEN: true, ceremony_level: 1)
**Base**: `main` == `HEAD` (this branch's commits are already on `main`
via a prior merge boundary; the reviewable content is the uncommitted
working tree, confirmed empty `git diff main...HEAD`).

## Spec-AC table walk

| Spec-AC | Call | Evidence |
|---|---|---|
| Spec-AC-01 | compliant | Allowlist check (item 5, `branch-guard.mjs:249-257`) fires for both set-but-unrelated and cleared `ref_id`. Ran `bash tests/skills/test-aai-branch-guard.sh 009 010` locally — both PASS. RED log (`docs/ai/tdd/red-20260724T074153Z.log`) shows the same two cases failing (exit 3 / exit 4) against the unmodified guard — genuine RED-to-GREEN pair, not fabricated. |
| Spec-AC-02 | compliant | Item 4 (base check, lines 234-247) is checked and can return before item 5 (allowlist, line 253) is ever reached. Verified with the spec's own TEST-012 fixture (branch AND `--base` both `chore/legacy-main`) -> exit 1. Also built an independent fixture not in the test suite: same base-collision but with `ref_id` CLEARED -> exit 4 (item 4a), confirming the allowlist never rescues even the Tier-B sub-case of a chore-named base branch. |
| Spec-AC-03 | compliant | `feat/unrelated-name` with a non-matching `ref_id` still exits 3 (TEST-004, unmodified, PASS). |
| Spec-AC-04 | compliant | TEST-011 (`chore/tenant-cleanup`, STATE.yaml absent) -> exit 4. Tier A check (line 228, `!focus.fileReadable`) is unconditional and runs before `matchAllowlistPrefix` is ever called. |
| Spec-AC-05 | compliant | TEST-003 (detached HEAD, including the detached+STATE-absent sub-case) -> exit 2, both sub-cases PASS; items 1-2 precede the STATE read entirely and are unmodified by this diff. |
| Spec-AC-06 | compliant | TEST-001 (real `state.mjs set-focus` writer -> guard reads it back on `fix/<ref>`) -> exit 0, PASS; item 8 pass path is unmodified. |

All six Spec-AC rows are `done` in the Acceptance Criteria Status table
with non-empty evidence citations pointing at real, existing log files
(`docs/ai/tdd/red-20260724T074153Z.log`, `green-20260724T074153Z.log` —
both present on disk and their content matches the actual local test
run reproduced during this review, byte-for-byte on the PASS/FAIL
lines).

## Code quality — findings

None. Specific hunted-for defect classes, each checked directly:

**1. Prefix matching is path-segment, not substring.** `ALLOWLIST_PREFIXES
= ['chore/', 'release/', 'docs/']` (branch-guard.mjs:72) bakes the
trailing slash into the constant, and `matchAllowlistPrefix` uses
`branch.startsWith(p)` (line 76) — never `.includes()`. Built three
throwaway-repo fixtures not present in the shipped test suite and ran
the guard directly:
- `documentation-foo` -> exit 3 (does NOT match `docs/`)
- `choreography/x` -> exit 3 (does NOT match `chore/`)
- `release-notes` -> exit 3 (does NOT match `release/`)

All three fail closed exactly as the spec's edge-case note claims — no
leak.

**2. Decision order correctness.** Traced the 8-item order against the
code line-by-line: item 1 (not-git, line 208) -> 4; item 2 (detached,
line 215) -> 2; item 3 (Tier A, line 228) -> 4 unconditional; item 4
(base==branch, line 238) -> 4a (line 239, Tier B) -> 4 / 4b (line 244)
-> 1; item 5 (allowlist, line 253) -> 0; item 6 (Tier B non-allowlisted,
line 261) -> 4; item 7 (mismatch, line 270) -> 3; item 8 (pass, line
277) -> 0. Matches the spec's numbered order exactly, including the
"allowlist runs after base and before ref_id checks" requirement, and
"cleared ref_id on a non-allowlisted branch still fails closed"
(verified via TEST-005 case A regression, unmodified, and by construction
of the code path — item 6 is unconditionally reached when item 5's
`matchAllowlistPrefix` returns null).

**3. Tier A vs Tier B split.** `readFocus()` (lines 135-149) returns two
independently-checkable fields: `fileReadable` (false only on a caught
`readFileSync` exception — Tier A) and `ok` (false whenever `refId` is
null/empty even though the file opened fine — Tier B). The guard checks
`!focus.fileReadable` at item 3 (line 228, unconditional) separately
from `!focus.ok` at item 6 (line 261, only reached for non-allowlisted
branches). This is a real split, not a conflation — confirmed by
TEST-011 (Tier A, STATE absent, allowlisted branch) still exiting 4
while TEST-010 (Tier B, STATE readable but ref_id null, allowlisted
branch) exits 0.

**4. Read-only / fail-closed / no throw.** No write calls anywhere in
the diff (grep for `writeFileSync`/`fs.write` in branch-guard.mjs:
none). `git()` wraps `execFileSync` and every caller of a git-invoking
helper (`isInsideWorkTree`, `resolveStatePath`) is wrapped in try/catch
degrading to `false`/`null` rather than throwing. `readFocus` catches
the `readFileSync` failure explicitly. No uncaught-throw path found.

**5. Allowlist message distinctness.** Allowlist pass message (line
255): `"branch-guard: OK — ... is a recognized non-work-item branch
(prefix "..."; no work item claimed)."` with NO remediation line —
confirmed by TEST-009's explicit negative assertion (line 314) that the
output must NOT contain `"matches current_focus.ref_id"` (the exit-8
pass message) and by direct inspection: the allowlist branch (lines
254-257) never calls `remediation()`, while every other exit path does.
Distinct from the exit-3 mismatch message (line 271) as well.

**6. Header/usage comments.** Top-of-file doc block (lines 26-56)
documents the new exit-0 allowlist path, `ALLOWLIST_PREFIXES`, and the
Tier A/Tier B distinction, matching the spec's requirement that no
prompt-corpus file carries this documentation.

## Test quality

- TEST-009..012 build throwaway git repos via the existing
  `make_repo`/`write_state`/`run_guard` helpers (full `mktemp`
  templates, `git init -b main`, POSIX-safe — LEARNED 2026-07-19
  discipline preserved).
- TEST-009/TEST-010 are genuinely RED-discriminating: the spec's own RED
  log (captured before the fix, against the unmodified guard, sha256
  pinned) shows exit 3 / exit 4 respectively, vs. exit 0 post-fix —
  reproduced locally.
- TEST-011/TEST-012 are explicitly and honestly labeled
  "NON-DISCRIMINATING BY DESIGN" in both the spec and the test file's
  own comments (lines 338-340, 354-356) rather than claiming a fake RED
  — this is the correct disposition per the spec's own RED-proof
  exemption rule, not a gap.
- TEST-001..008 are present, unmodified (diffed against git history —
  only new lines appended, no existing test body edited), and all still
  pass.
- Full suite run locally (`bash tests/skills/test-aai-branch-guard.sh`)
  and via the CI-matching wrapper
  (`.aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-branch-guard.sh`):
  both exit 0, all 12 cases PASS.

## Spec compliance — bookkeeping checks

- `protected_paths_l3` (docs/ai/docs-audit.yaml): `.aai/scripts/state.mjs`,
  `lib/state-engine.mjs`, `lib/state-core.mjs`,
  `allocate-doc-number.mjs`, `pre-commit-checks.sh/.ps1`,
  `.aai/workflow/WORKFLOW.md`, `docs/CONSTITUTION.md` — none touched by
  this diff (confirmed by grep of the diffed file list against the L3
  list).
- No `.aai/*.prompt.md` / `.aai/AGENTS.md` edit in this diff (confirmed
  — diffed file list contains no `.aai/**` prompt file).
- No new `.aai/**` file (only `.aai/scripts/branch-guard.mjs`, already
  existing since PR #129, is modified).
- Companion obligations: spec's own section states both obligations
  (prompt-corpus bytes, new `.aai/**` file) are N/A — confirmed true by
  direct diff inspection, not merely asserted.
- Acceptance Criteria Status table: all 6 rows `done` (terminal), each
  with a non-empty, file-verified evidence path.
- Pipe-count safety: every data row in both the Test Plan and
  Acceptance Criteria Status tables has exactly 8 `|`-delimited fields
  (7 columns), confirmed via `awk -F'|'`; no literal `|` character
  appears inside any cell (the spec's own self-check note at lines
  352-355 is accurate).
- `state.mjs` diff against `main`: empty — no STATE.yaml schema change,
  consistent with the spec's "read-only, no schema change" claim.

## Warnings disposition (H6)

No NON-BLOCKING findings raised — nothing to disposition.

## Next steps

None required for merge readiness on this scope. The two `cannot_verify`
items (live SKILL_PR invocation end-to-end, and CI-Linux green) are
standard for a diff-scoped review and do not block — TEST-007's static
grep assertion adequately covers the wiring claim within this scope's
review boundary, and the spec's PASS criteria already require the full
suite green locally, which was reproduced.
