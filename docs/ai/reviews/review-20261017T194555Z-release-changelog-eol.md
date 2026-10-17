# Code Review — release-changelog-eol

```yaml
review:
  scope: "git diff f404ef88..068c77c1 (branch fix/release-changelog-eol): .aai/scripts/release-finish.mjs tests/skills/test-aai-release.sh docs/product/release-command-finish.md CHANGELOG.md docs/specs/SPEC-0235-spec-release-changelog-eol.md docs/issues/ISSUE-0102-release-changelog-eol.md (+ ledger/index companions docs/INDEX.md docs/ai/EVENTS.jsonl docs/ai/decisions.jsonl)"
  spec: docs/specs/SPEC-0235-spec-release-changelog-eol.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "release-finish.mjs:52 blob(), :110 split without CRLF replace, :402 base read; TEST-067 PASS (selector + full run), mutation-TEST-067 RED" }
      - { ac: Spec-AC-02, call: compliant, citation: "release-finish.mjs:110 newline/pop; BOM survives (no trim); TEST-068 PASS, mutation-TEST-068 RED" }
      - { ac: Spec-AC-03, call: compliant, citation: "release-finish.mjs:112 cr from first heading, :125 scaffold+cr; TEST-069 PASS incl. zero bare LF loop, mutation-TEST-069 RED" }
      - { ac: Spec-AC-04, call: compliant, citation: "release-finish.mjs:415 blob(head)!==record.content; TEST-070 PASS (two variants refuse once, zero creates; exact control exits 0, 1 PR, 1 merge), mutation-TEST-070 RED" }
      - { ac: Spec-AC-05, call: compliant, citation: "release-finish.mjs:396 re-derivation before unchangedBase/worktree/commit/push; TEST-071 PASS, mutation-TEST-071 RED" }
      - { ac: Spec-AC-06, call: compliant, citation: "test-aai-release.sh test_716 runs real released_region_verdict on both base shapes -> PASS v0; TEST-072 PASS, mutation-TEST-072 RED (EOF state differs)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 111,
          issue: "A UTF-8 BOM is now kept on the first line, so a CHANGELOG whose first byte sequence is BOM + '## [unreleased] — ...' (no title line) no longer matches /^## \\[/; that first entry is treated as preamble and not rolled. Pre-fix, trim() stripped the BOM and the entry rolled (BOM lost).",
          failure_scenario: "base = '\\uFEFF## [unreleased] — feat: a (#1)\\n\\n- a\\n\\n## [unreleased] — fix: b (#2)\\n...\\n## [v0] — old\\n' -> content keeps '\\uFEFF## [unreleased] — feat: a' stuck above the new '## [unreleased]' scaffold, notes contain only fix: b (reproduced in a scratch copy of rollup()). Fails closed via audit missing-notes when #1 shipped files; slips through when #1 is a no-notes/unshipped PR, and stays stuck on every later cut. Single-entry variant refuses empty-notes." }
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 415,
          issue: "Exact-byte adoption assumes `git add` stores record.content verbatim. A repo whose attributes normalize CHANGELOG.md (explicit `text`/`eol=lf`, e.g. '*.md text eol=lf') with a CRLF base blob gets an LF blob at :432, so blob(head)!==record.content.",
          failure_scenario: "downstream with '*.md text eol=lf' and a historically CRLF CHANGELOG blob; process dies after the commit at :432 but before atomicSave -> every resume refuses identity 'Unbound prepared release branch' (verified in scratch: core.autocrlf=true alone preserves CRLF when the index already has CRLF; an explicit eol=lf attribute normalizes to LF). Normal (uncrashed) path is unaffected; AAI's own .gitattributes has no rule for root CHANGELOG.md." }
  cannot_verify:
    - { claim: "Live GitHub release workflow publishes from the byte-exact rolled file and CI TEST-025 passes on the next real release PR", closes_with: "first /aai-release --confirm after merge (spec Seams residual risk)" }
    - { claim: "Windows behavior of the finish engine (git autocrlf/attributes on blob vs worktree bytes)", closes_with: "a Windows-runner run of the finish fixture; Pester aai-release.Tests.ps1 does not exercise release-finish.mjs; TEST-033 parity ran under macOS pwsh only. Reasoned: cat-file blob is raw (no smudge), default autocrlf=true keeps LF blobs LF and CRLF-indexed blobs CRLF, so only the attribute case in NB-2 diverges" }
  overall: pass
```

## Scope and preflight

- Worktree /Users/ales/Projects/aai-fix-release-changelog-eol, branch `fix/release-changelog-eol`, HEAD 068c77c1 verified; working tree clean; base f404ef88. Commits: 06e733b7 (intake + frozen spec), 068c77c1 (fix).
- Coaching check: the dispatch listed focus areas and the incident context but did not pre-rate severity or exclude any area; full scope reviewed.

## Evidence run by the reviewer

- Six selectors (`test_711`..`test_716`) via `aai-run-tests.sh`: each `SELECTED TEST PASSED`.
- Full suite `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh`: `ALL TESTS PASSED`, rc=0, 91 PASS lines; TEST-067..072 each appear exactly once (the `ownSelector` exclusion keeps them out of the `all` node pass); TEST-011, TEST-021 (SIGKILL resume), TEST-025 (live released region vs v2026.10.17), TEST-033 (pwsh parity) PASS.
- `tests/skills/test-aai-learned-routing.sh` (copies the engine): ALL TESTS PASSED.
- `mutation-gate.mjs --spec ...`: GATE PASS 6 rows; all six mutation records verdict RED with selector honoured.
- `spec-lint.mjs --path <spec>`: LINT PASS.
- RED log docs/ai/tdd/release-changelog-eol-red.log shows TEST-067 failing at offset 130 on the pre-fix engine.

## Focus-area analysis

- Byte-exactness: `blob()` uses `cat-file blob` with utf8 decoding; Node's Buffer utf8 decode keeps U+FEFF, so BOM round-trips (TEST-068 asserts EF BB BF). Per-line CR is kept by splitting on `\n` only; heading regexes tolerate trailing CR (`\s*$`, `\S`, `l.trim()`). Final-newline state preserved by `newline`/`pop`/re-append. Scaffold CR follows the first `## [` heading (spec decision); mixed files keep each line's own ending (probe confirmed). Content is written with `fs.writeFileSync(string)` = UTF-8, so bytes equal the blob for UTF-8 input.
- Normalization still where intended: `record.notes` strips `\r$` per line before join/trim (:123), so notes stay LF-only; release-body comparison (:474) still uses `trim()` both sides; audit heading match (`addedRolledNotes` `norm`) trims each line, so CR in patch lines is harmless. No SPEC-0233 regression observed (TEST-011/021/010/012 pass).
- No-PR journal re-derivation (:396): keyed on the journal's fixed `baseHead`, so a moved remote base cannot false-refuse (base movement is still caught later by `unchangedBase()`); runs after the identity-field check and before any worktree write/commit/push/PR. Residual false-refuse paths: base object pruned locally (refuses `git-command`, not `identity`), or a later engine version changing `rollup()` output mid-ride (intended conservatism). A journal whose PR was created but not yet saved (crash between create and save) with defective content also refuses — consistent with the spec's out-of-scope operator recovery.
- PS1 frontend: `.aai/scripts/aai-release.ps1:131` only forwards to the engine; no change needed.

## Findings and dispositions (H6)

- NB-1 (P3, release-finish.mjs:111, BOM directly before first entry heading) — recommended disposition: remediate-in-tree (peel a leading U+FEFF before splitting and re-prefix it; one fixture case), else promote to follow-up `fu-release-rollup-bom-heading`.
- NB-2 (P3, release-finish.mjs:415/:432, attribute-normalized CHANGELOG vs exact adoption) — recommended disposition: (d) accepted residual: only bites on a crash between commit and journal save in a repo that both normalizes CHANGELOG.md by attribute and carries a CRLF blob; no observed bite, no false record (the refusal is fail-closed).

INFO (non-gating):
- CRLF base without final newline whose last section is an out-of-order `[unreleased]` entry rolls to a bare LF mid-file and a trailing lone CR (probe); this is the spec's declared edge case on an abnormal layout.
- The re-derivation `identity` refusal prints the generic Resume hint; re-running cannot succeed — the operator must remove the journal (same as other identity refusals; product doc does not spell out recovery).
- test_716 captures node stdout with `out="$(...)"` under `set -e`; on a node failure the `FAIL: TEST-072` stdout line is swallowed (stderr assertion still shows).

## Next steps

Orchestrator records NB-1/NB-2 dispositions; proceed to Validation.
