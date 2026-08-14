# Code Review — CHANGE-0143 / spec-close-regenerate-order (CEREMONY 3)

```yaml
review:
  scope: "git diff main...HEAD on feat/close-regenerate-order @ ae829e9 (21 paths)"
  spec: docs/specs/SPEC-0131-spec-close-regenerate-order.md (SPEC-FROZEN: true, ceremony_level: 3)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/allocate-doc-number.mjs:1162-1164 (regen immediately after regenerateIndex, inside runAllocate only); dry-run early return :1114-1124; main() dispatch :1221-1224; TEST-020/021 green (my run, exit 0); mutation probe M1 (allocator reverted to main) makes TEST-020 FAIL" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/allocate-doc-number.mjs:821-824 (exactly two entries, overview then rollup); tests/skills/test-aai-doc-numbering.sh:1234-1262 exact two-line order equality with five stubbed candidates; TEST-023 survey pin; mutation probe M4" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "tests/fixtures/close-regenerate-order/{pr255,pr256}: I re-derived all five files from git history — `git show <sha>:<path> | grep -F SPEC-DRAFT-<slug>` is BYTE-EXACT against each fixture, and the real hit counts are 3 (00bdd03) and 2 (ff8208e); TEST-024/025 green" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "tests/skills/test-aai-doc-numbering.sh:1039-1098 (closed list has no docs/ai/STATE.yaml; exact-slug regex anchor at :1085); TEST-026 (a)(a2)(b)(c)(d)(e) green. Behaviour is correct — I probed the suffix-collision case the suite omits and the shipped predicate does NOT flag it — but the anchor that makes it correct is untested (mutation probe M3, finding NB-5)" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/scripts/allocate-doc-number.mjs:834-847 mirrors close-work-item.mjs regenerateFactoryReportBestEffort; TEST-027 (absent silent / each failing generator exactly one named INFO) + TEST-028 (exit 2/3/4) green" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "`git diff main -- .aai/scripts/close-work-item.mjs` = 0 bytes (my run); test-aai-close-work-item.sh exit 0 (my run); in-suite pin tests/skills/test-aai-doc-numbering.sh:1487-1508; mutation probe M2 (planted byte) makes TEST-029 FAIL" }
      - { ac: Spec-AC-07, call: compliant,
          citation: ".aai/SKILL_PR.prompt.md step 1b both lines; allocator header :33-46; completion line :1164; suite-map row +11 entries; all 7 RED logs carry RED_CLASS on line 1; measured prompt delta 21333 -> 21492 = 159 B == ledger entry == TEST-012 pin move -5421 -> -5262; `git diff main --stat -- .aai/*.prompt.md` names only SKILL_PR.prompt.md" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/allocate-doc-number.mjs, line: 1163,
          issue: "the completion line hardcodes docs/INDEX.md into the regenerated list, violating the honesty contract stated 330 lines above it",
          failure_scenario: "core-only sync (generate-docs-index.mjs absent) or a throwing index generator: regenerateIndex() returns/swallows with zero output, yet stdout still says `regenerated docs/INDEX.md — stage every page listed here`. Harm is bounded to a no-op `git add` unless docs/INDEX.md carries unrelated working-tree edits, which scope-only staging would then sweep into the allocation commit." }
      - { rank: NON-BLOCKING, file: .aai/scripts/allocate-doc-number.mjs, line: 823,
          issue: "the spec's edge case says the rollup generator no-ops when docs/USER_GUIDE.md is absent; it does not — it CREATES the file (generate-userguide-rollup.mjs:167-176, empty `existing` -> spliceMarkedRegion appends the block -> writeFileSync)",
          failure_scenario: "a consumer repo synced at the extended profile with docs/ but no docs/USER_GUIDE.md: the first allocation creates docs/USER_GUIDE.md containing only the generated rollup block, and the completion line then instructs the agent to STAGE it — a new tracked doc the scope never intended. Mitigated (not removed) by close-work-item.mjs already running the same generator at close, so the file would appear one ceremony step later anyway." }
      - { rank: NON-BLOCKING, file: .aai/scripts/allocate-doc-number.mjs, line: 841,
          issue: "pages are credited only on whole-generator success, so a generator that fails PART-WAY leaves a modified page that the stage-me list never names",
          failure_scenario: "generate-overview.mjs writes docs/ai/overview-data.json (:465) BEFORE docs/ai/overview.html (:468). If renderHtml() throws between them, execFileSync reports non-zero, the catch fires, and NEITHER page enters `regenerated` — overview-data.json is modified on disk, unnamed on stdout, unstaged under scope-only staging, and rides into the PR as an unmentioned dirty file. Under-claiming is the safe direction and the detection check is the compensating control, hence non-blocking." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-doc-numbering.sh, line: 1497,
          issue: "TEST-029's unreachable-base-ref arm emits log_pass — a green PASS line for an assertion that never executed",
          failure_scenario: "a future scope edits .aai/scripts/close-work-item.mjs and runs on a checkout where neither origin/main nor main resolves (shallow PR fetch, renamed default branch, detached archive). The D5 byte-unchanged guarantee prints PASS, the suite exits 0, and the edit ships unpinned. The F4 remediation removed the most common instance of this class but left the skip arm reporting success." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-doc-numbering.sh, line: 1085,
          issue: "the exact-slug regex anchor is load-bearing but UNTESTED — mutation probe M3 deletes the line and the entire doc-numbering suite stays green (rc=0)",
          failure_scenario: "the only precision case the suite tests (SPEC-DRAFT-foo vs SPEC-0001-foobar.md, TEST-026(b)) is already excluded by the glob `$prefix-[0-9]*-$slug.md`, which requires the literal `-foo.md` suffix. The case the regex actually defends is the SUFFIX collision: I built the tree (a page carrying SPEC-DRAFT-foo, an in-flight docs/specs/SPEC-DRAFT-foo.md, and an unrelated docs/specs/SPEC-0001-bar-foo.md) and confirmed the shipped predicate returns rc=0 while the anchor-less mutant reports `VIOLATION: ... SPEC-DRAFT-foo while docs/specs/SPEC-0001-bar-foo.md exists`. So a later refactor can silently delete the anchor, the suite will not notice, and the compensating control then FALSE-POSITIVES on a legitimately in-flight draft — reddening the suite for unrelated rides, the opposite of the D3 precision guarantee." }
  cannot_verify:
    - { claim: "the full 78-suite framework sweep is green on this branch",
        closes_with: "the PR's own CI run — I confirmed `node .aai/scripts/select-suites.mjs --base-ref main` emits `FULL_RUN reason=protected-l3 path=.aai/scripts/allocate-doc-number.mjs`, so mode=full fires without a ci-full label. I ran 10 named suites/commands, not the framework." }
    - { claim: "D2's measured cost figures (+0.12 s regen on a 9.13 s allocation; generate-userguide-rollup.mjs is byte-idempotent)",
        closes_with: "a timed re-run; I did not re-measure either number." }
    - { claim: "neither new generator can hang the allocator (execFileSync carries no timeout)",
        closes_with: "an adversarial input corpus. By inspection neither generator opens a socket, reads stdin, or shells out (grep for execFileSync/execSync/spawnSync/fetch/https/createInterface/process.stdin over both files: zero hits), and stdio:'ignore' hands the child /dev/null on fd 0 — but absence of a hang primitive is not proof of termination." }
    - { claim: "Windows/PowerShell parity for the new bash predicate",
        closes_with: "a run of the PS mirror; the new detection code is bash-only inside a .sh suite and was not exercised on Windows." }
  overall: pass
```

---

## Scope, spec, and preflight

- Branch `feat/close-regenerate-order` @ `ae829e9`, 10 commits ahead of `main`, **0 behind**.
- Working tree at review time: only `docs/ai/EVENTS.jsonl` modified (telemetry appends; one of them produced by my own `docs-audit --check --strict` run — **not restored**, per the repo's learned rule that restoring EVENTS wipes close telemetry).
- Frozen spec read in full before the diff. Review scope = the spec's inline list, which post-freeze includes `tests/skills/test-aai-spec-lint.sh` (recorded IMPLEMENTATION ADJUSTMENT).
- `git diff main --stat` names **three paths outside the declared inline scope**: `docs/INDEX.md` (regenerated companion — legitimate), `docs/ai/decisions.jsonl` (two append-only follow_up lines), `docs/ai/EVENTS.jsonl`. I verified the EVENTS churn is **not** a loss: sorting both sides, `comm -23 main head` = **0 lines**, i.e. the branch ledger is a strict superset of main's (1706 -> 1709); the 35 apparent deletions are pure line reordering from the `03e31f5` up-to-main merge.

### Anti-gaming: coaching attempt recorded

Per the review contract's anti-gaming clause, the dispatch prompt did characterize expected findings: it named validation's F1 in advance ("F1 says no for INDEX"), listed the four remediated findings, and summarized what prior evidence proved. It also instructed me to judge severity myself and to verify rather than trust. I record the characterization here as required, and I reviewed the **full** diff independently — including re-deriving the fixtures from git history, re-measuring the prompt byte delta, re-running the close-pin diff, and running four of my own mutation probes rather than accepting the stored RED logs.

---

## Evidence I produced (not inherited)

### Commands run (all exit 0)

| command | exit |
|---|---|
| `aai-run-tests.sh bash tests/skills/test-aai-doc-numbering.sh` | 0 |
| `aai-run-tests.sh bash tests/skills/test-aai-close-work-item.sh` | 0 |
| `aai-run-tests.sh bash tests/skills/test-aai-overview.sh` | 0 |
| `aai-run-tests.sh bash tests/skills/test-aai-userguide-rollup.sh` | 0 |
| `aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh` | 0 |
| `aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh` | 0 |
| `aai-run-tests.sh bash tests/skills/test-aai-doc-number-reservation.sh` | 0 |
| `aai-run-tests.sh bash tests/skills/test-aai-spec-lint.sh` | 0 |
| `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0131-spec-close-regenerate-order.md` | 0 (LINT PASS, 0 findings) |
| `node .aai/scripts/check-test-registration.mjs` | 0 |
| `node .aai/scripts/docs-audit.mjs --check --strict` | 0 (Verdict: CLEAN) |
| `git diff main -- .aai/scripts/close-work-item.mjs` | 0 bytes |
| `node .aai/scripts/select-suites.mjs --base-ref main` | `FULL_RUN reason=protected-l3` |

### Mutation probes (my own, in a local clone under the scratchpad — the source tree was never written)

| probe | mutation | expected | observed |
|---|---|---|---|
| M0 | none (baseline clone) | suite green | **green** |
| M1 | `.aai/scripts/allocate-doc-number.mjs` reverted to `origin/main` | TEST-020 fails | **FAIL: Did not expect 'SPEC-DRAFT-widget-projection' in .../iso-t020/docs/USER_GUIDE.md** |
| M2 | planted byte appended to `close-work-item.mjs` | TEST-029 fails | **FAIL: close-work-item.mjs must be byte-unchanged against origin/main** |
| M3 | exact-slug anchor removed from the detection predicate (`:1085`) | TEST-026(b) fails | **SURVIVED — rc=0, whole suite green.** See NB-5. |
| M4 | generator order reversed in `SPEC_PAGE_GENERATORS` | TEST-022 fails | **FAIL: generator order must be overview then userguide-rollup** |

M1 is the important one: it proves the prevention arm is not self-satisfying. `docs/USER_GUIDE.md` and `docs/ai/overview.*` are **not** in `REWRITE_TREES` (the markdown pass walks `docs/{rfc,specs,issues,requirements,releases,product,ai/reviews,project-sessions,knowledge}` plus `README.md`/`CHANGELOG.md`), so no amount of reference rewriting can clear those pages — only a real regeneration can, and TEST-020 goes red the moment the regeneration is removed.

### Fixture provenance re-derived

| fixture | vs `git show <sha>:<path> \| grep -F SPEC-DRAFT-<slug>` |
|---|---|
| `pr255/docs/USER_GUIDE.md` | BYTE-EXACT |
| `pr255/docs/ai/overview.html` | BYTE-EXACT |
| `pr255/docs/ai/overview-data.json` | BYTE-EXACT |
| `pr256/docs/ai/overview.html` | BYTE-EXACT |
| `pr256/docs/ai/overview-data.json` | BYTE-EXACT |

Real hit counts at `00bdd03`: USER_GUIDE 1, overview.html 1, overview-data.json 1 (= the fixture's 3 violations). At `ff8208e`: overview.html 1, overview-data.json 1, USER_GUIDE **0** (= the fixture's 2 violations, and the USER_GUIDE absence in `pr256/` is itself correct).

---

## The L3 surface: every hunk of `.aai/scripts/allocate-doc-number.mjs`

Three hunks, nothing else in the file moved (verified against the full diff, not the stat):

1. **`@@ -30,6 +30,21` — header comment.** 15 lines of contract text inserted into the existing block-comment run, above `// Usage:`. No code. The stated ordering (INDEX -> overview -> rollup) matches the code. Accurate.
2. **`@@ -795,6 +810,42` — the new constant + function**, inserted *between* `regenerateIndex()` (:805-811) and `moveFile()` (:849). `regenerateIndex`'s body is untouched, as the spec promised.
3. **`@@ -1109,7 +1160,8` — the call site.** One line added, one line replaced, inside `runAllocate` only.

`REWRITE_TREES`, `EXCLUDED_TREES`, `EXCLUDED_CODE_PATHS`, `rewriteReferences`, `moveFile`, `parseArgs`, every `die()` code, the reservation path and `runGuard`/`runBackfill`/`runReserveCompletion` are all byte-identical. The edit is minimal.

### Can it throw past its catch?

No. Inside the `try`: `path.join` on two strings, `fs.existsSync` (documented never to throw), `execFileSync` (throws only into the catch), `Array.prototype.push`. Outside the `try`: an array literal and a `for…of` over a module constant. The only expression outside a guard is the `process.stderr.write` **inside** the catch — I probed the pathological case (`node -e 'process.stderr.write(...)' 2>&-`) and the process **survived with rc=0**, so a closed stderr does not convert a best-effort skip into a failed allocation on this platform. Precedent is identical anyway: the existing provisional-allocation `console.error` at :1147 carries the same exposure on main.

### Can it hang?

`execFileSync` carries no `timeout`, which is a new instance of an exposure `regenerateIndex` already has with a 9.13 s generator. I looked for a hang primitive in both new children and found none: zero `execFileSync|execSync|spawnSync|fetch(|http(s)://|createInterface|process.stdin` hits across `generate-overview.mjs` and `generate-userguide-rollup.mjs`, and `stdio: 'ignore'` gives the child `/dev/null` on fd 0 so it cannot block on input. `stdio: 'ignore'` also removes the `maxBuffer`/ENOBUFS class entirely — a chatty generator cannot kill the allocator. Listed under `cannot_verify`, not as a finding: I could not construct a failure scenario.

### Can it run in a mode it must not?

No, on four independent counts:

- `main()` (:1221-1224) dispatches `--guard`, `--reserve` and `--backfill` to their own functions and **returns**; none of them can reach `runAllocate`.
- `--dry-run` returns at :1123, 39 lines before the call site.
- `--all` with zero drafts returns at :1049, also before the call site.
- I read `runBackfill` (:992-1017) specifically to check the design premise: it only re-stamps frontmatter on filenames that are **already numbered** and never renames anything, so it cannot invalidate a projection. Excluding it is correct, not merely convenient.

TEST-021 confirms all four empirically with a sha256 before/after over the three pages.

### Partial writes and non-zero exits

- **Generator exits non-zero** -> `execFileSync` throws -> one named INFO line -> its pages are NOT credited -> allocator exit code unchanged. Proven by TEST-027(b) for each generator independently.
- **Generator throws before writing** -> same path, no page touched.
- **Generator writes garbage** -> the allocator cannot tell, and does not try. The compensating control is the detection check over the eight closed-list pages, which reads content, not exit codes. This is the honest boundary of a best-effort design and the spec says so.
- **Generator fails between its two writes** -> NB-3 above.
- **`die()` mid-batch** (:1141 reservation exhausted, :1152/:1155 stamp failures) exits before *both* regen calls, leaving already-renamed drafts' projections stale. This is pre-existing behaviour for `docs/INDEX.md` on main; the new function inherits it without widening it. INFO, not a finding.

### Blast radius

Nothing in the new code can affect document *identity*: it runs strictly after the last `moveFile`/`rewriteReferences`/`console.log` of the plan loop, writes no doc, touches no ref, computes no number, and returns a value used only to format one stdout line. The worst reachable outcome of a total failure of both generators is two stale projections plus two INFO lines — exactly the status quo the change is fixing.

---

## Detection predicate — precision

Read at `tests/skills/test-aai-doc-numbering.sh:1063-1098`.

**Precision on the closed list.** The eight paths match the intake's AC-002 set exactly; `docs/ai/STATE.yaml` is absent and TEST-026(c) pins that absence twice (behaviourally and by asserting the constant). Skips for absent and untracked members are both named. `set -euo pipefail` discipline holds: every loop is fed by a here-string, `grep -c` runs over a here-string with the no-match exit absorbed, and every rc is captured as `cmd || rc=$?`. The `[0-9]*` glob is safe without `nullglob` because the unexpanded pattern fails the `[[ -f ]]` test.

**Can it fire on a legitimately in-flight draft?** Only via slug reuse. The predicate keys purely on the existence of a numbered counterpart and never checks whether the DRAFT file still exists — which is exactly what D3's operative sentence specifies, so implementation matches spec. The residual shape is: a slug is numbered and shipped, then a NEW `SPEC-DRAFT-<same-slug>.md` is opened and a generated page links it. That would false-positive. Doc-id slugs are meant to be durable and unique, so this is a governance violation before it is a detection bug. INFO.

**The exact-slug anchor (`:1085`) is correct and untested — NB-5.** TEST-026(b)'s prefix-collision case is already handled by the glob, so the anchor's real job is the *suffix* collision. I built that tree by hand: page carries `SPEC-DRAFT-foo`, `docs/specs/SPEC-DRAFT-foo.md` is legitimately in flight, and an unrelated `docs/specs/SPEC-0001-bar-foo.md` exists. Shipped predicate: **rc=0, no violation** (correct). Anchor-less mutant: `VIOLATION: docs/ai/overview.html carries SPEC-DRAFT-foo while docs/specs/SPEC-0001-bar-foo.md exists` (a false positive on an in-flight draft — precisely what D3 promises never happens). The full suite does not distinguish the two.

**Two residual precision notes (INFO, both unreachable today):**
- The token regex `[A-Z]+-DRAFT-[a-z0-9]+(-[a-z0-9]+)*` silently truncates a slug containing an uppercase letter or an underscore, producing a **false negative** (the truncated slug then fails the anchored basename regex). The repo's slug convention is lowercase-hyphen, so unreachable.
- The live-tree arm TEST-026(e) is thin right now: across all eight pages there is exactly **one** DRAFT token on this branch (`docs/INDEX.md` -> `SPEC-0131-spec-close-regenerate-order`, no counterpart). Non-vacuous, but only just.

**One undocumented coupling (INFO).** `scan_stale_draft_refs` filters on `git -C "$root" ls-files`, and the replay fixtures are not their own repos — the filter passes only because `tests/fixtures/close-regenerate-order/**` is tracked in the *parent* repo and git resolves the relative path against the enclosing worktree. This works, and a regression fails loudly (TEST-024 asserts rc==1, so a wholesale skip would fail, not silently pass), but the helper's comment does not say so.

---

## Could the new tests pass against a broken implementation?

Largely no, and I verified the two arms that matter by mutation rather than by reading:

- **Prevention (TEST-020)** — M1 proves it. It asserts on the projection side after producing on the source side, and no rewrite path can reach those pages.
- **Order pin (TEST-022)** — exact string equality against a two-line expectation, with all five candidate generators stubbed, so an extra run, a missing run, a reorder or a double-run all fail. M4.
- **Close pin (TEST-029)** — M2 proves the planted byte fires it. Its **skip arm is the one real false-pass path** in the new suite: see NB-4.
- **Detection (TEST-024/025/026)** — the static replay is byte-exact against real history (I re-derived it), and TEST-026(a2) is a genuine negative-control-with-teeth: it plants the numbered counterpart into the same tree and requires exactly one violation. **But one line of the predicate is unprotected: M3 shows the exact-slug anchor can be deleted with the suite still green (NB-5).** The behaviour is right today; the test does not keep it right.
- **TEST-023** (`grep -cF 'docs/specs'` over two generators) is the weakest arm: a generator could build a spec path by concatenation (`'docs/' + dir`) and slip the pin. It is what the spec specified and it is a survey-staleness canary rather than a correctness proof. INFO.
- **TEST-030/031** are grep pins; they pin the presence of the strings, not their truth. Adequate for their AC.

---

## Governance

| item | claim | verified |
|---|---|---|
| SKILL_PR delta | +159 B | `wc -c`: 21333 -> 21492 = **159**. Ledger entry says 159. |
| `.aai/*.prompt.md` scope | only SKILL_PR | `git diff main --stat -- '.aai/*.prompt.md'` names one file. |
| TEST-012 pin | -5262 | pin moved -5421 -> -5262 (= -5421 + 159); suite green; the test also re-sums `JUSTIFIED_ADDITIONS` independently and both match. |
| Headroom | 1622 / 2048 | credited 1:1, unchanged. |
| suite-map row | widened | 11 entries added: both generators, all eight closed-list pages, the fixture glob. `**` is used 79 times elsewhere in the file, so the glob form is conventional. |
| RED_CLASS | line 1, at capture | all **7** RED logs: line 1 is `RED_CLASS: product_red` (6) / `RED_CLASS: infra_fail` (1). |
| CHANGELOG | per-entry `## [unreleased] — <title>` heading | correct form, `[L3]` tagged. |
| registration | every suite has a row | `check-test-registration.mjs` exit 0; hygiene-pack exit 0. |
| docs-audit | CLEAN | `--check --strict` verdict CLEAN, 0 orphans / drifted / stale / false_open. |

---

## Deviations from the frozen spec

1. **Scope widened post-freeze** by `tests/skills/test-aai-spec-lint.sh` — recorded in the spec as an IMPLEMENTATION ADJUSTMENT with the root cause filed as `fu-test011-branch-diff-allowlist-tax`. I read the edit: it adds a commented case arm listing this scope's two `.aai/` paths, does not weaken the pin's other semantics, and explicitly re-states what the zero-added-ceremony claim now covers. Correct call.
2. **The implementation improves on D2's sketch** by returning the regenerated page list; the sketch returns nothing. Required by D4 point 2, so this is the spec's other half, not drift.
3. **D2's edge-case line is factually wrong** — "the rollup generator no-ops" when `docs/USER_GUIDE.md` is absent. It creates the file. The AC's observable (allocator still exits 0) still holds. See NB-2.
4. **Intake AC-005 vs spec D4** — the intake asks for "the close-ceremony product doc and any guidance that currently implies the human does this by hand" to be updated; D4 declines `docs/product/`. I verified the justification rather than accepting it: **zero** files under `docs/product/` mention `allocate-doc-number` or `SPEC-DRAFT`, so there is no such product doc to correct. The frozen spec is the contract and its reasoning is sound.

---

## Findings and dispositions (H6)

| # | rank | disposition recommended to the orchestrator |
|---|---|---|
| NB-1 | NON-BLOCKING | **already promoted** — `fu-completion-line-hardcodes-index`, P3, decisions.jsonl 2026-08-14T06:42:44Z. I independently concur with P3, and I recommend *against* remediating in-tree: the fix (a boolean return from `regenerateIndex`) re-opens the `protected_paths_l3` surface for a cosmetic gain, and the pre-change line made the same claim unconditionally, so this is not a regression. |
| NB-2 | NON-BLOCKING | **promote-to-follow-up-ref**, and correct the spec's edge-case sentence in the same ref. No in-tree code change (it would mean touching the L3 surface or the generator). |
| NB-3 | NON-BLOCKING | **promote-to-follow-up-ref**. Fixing it properly means per-page `mtime`/hash accounting inside the best-effort function — more machinery than the defect warrants while the detection check compensates. |
| NB-4 | NON-BLOCKING | **promote-to-follow-up-ref**. The skip arm should not print `log_pass`; either surface it as a distinct SKIP in the suite summary or fail closed when `CI=true`. This is the same "pin goes inert while reporting PASS" class the F4 remediation targeted, one level up. |
| NB-5 | NON-BLOCKING | **remediate-in-tree** — the only finding whose fix costs nothing on the protected surface. Add a suffix-collision case to TEST-026(b): a page carrying `SPEC-DRAFT-foo`, an in-flight `docs/specs/SPEC-DRAFT-foo.md`, and `docs/specs/SPEC-0001-bar-foo.md`, asserting rc=0. Four lines in a non-protected test file, and it converts a surviving mutant into a killed one. If the orchestrator prefers not to reopen an L3 ride for a test addition, promote-to-follow-up-ref is acceptable — the shipped behaviour is proven correct. |

No BLOCKING findings. INFO notes (never gate): no `timeout` on `execFileSync`; `die()` mid-batch skips both regen calls; token-regex slug charset; slug-reuse false positive; thin live-tree arm; `git ls-files` parent-repo coupling in the fixture replays; TEST-023's substring survey pin.

### Reviewer side effects, declared

Running the suites dirtied two product files. Both are pre-existing suite behaviour, not defects of this scope, but I record them because an L3 PR is staged path-by-path:

- `docs/INDEX.md` — `tests/skills/test-aai-doc-numbering.sh:660-663` (TEST-013, pre-existing) runs `generate-docs-index.mjs` against the **live** `PROJECT_ROOT` twice, restamping the `Generated:` line. My run left a timestamp-only diff; I **restored it** to `ae829e9` so the tree matches how I found it. Worth knowing: this scope's `protected-l3` FULL_RUN selection makes that suite run more often, so allocation commits may pick up index timestamp churn from the test run itself.
- `docs/ai/EVENTS.jsonl` — my `docs-audit --check --strict` appended a `docs_audit` telemetry event. **Not restored**, per the repo's learned rule that restoring EVENTS wipes close telemetry.

Per the report-staging rule (SPEC-0013 H4), this report should be staged with the scope's commit; I did not stage or commit anything myself.

---

## Merge gate

**PASS on both verdicts — merge-ready subject to the two standing gates that are outside a local reviewer's reach:** (1) the PR's own `mode=full` CI run, which the selector confirms will fire on `protected-l3` without a `ci-full` label, and (2) the five NON-BLOCKING findings each carrying a recorded disposition before closeout (NB-1 already has one; NB-5 is the one I recommend fixing rather than filing).

Nothing in this review blocks the merge. The protected-surface edit is minimal, correctly gated to the one mode that renames, and incapable of touching document identity; its failure modes all degrade to the pre-change status quo plus a named line.

## Evidence contract

- ref_id: `close-regenerate-order`
- Spec-AC / TEST links: as cited per row above
- Review scope: `git diff main...HEAD` on `feat/close-regenerate-order` @ `ae829e9`
- Verdict: spec_compliance **pass**, code_quality **pass**, overall **pass**
- Evidence path: this file; suite logs and mutation-probe logs under the session scratchpad (`logs/*.log`, `logs/mut-M{0..4}.log`)
- Diff range: `main..ae829e9`

## Appendix — mutation probe transcript

Clone `ae829e9` of `feat/close-regenerate-order`, local origin, no network, source tree never written.

```
clone HEAD: ae829e9 branch=feat/close-regenerate-order
=== M0 baseline (unmutated clone) ===                       M0 rc=0
=== M1: revert the allocator to main's version ===          M1 rc=1
  FAIL: Did not expect 'SPEC-DRAFT-widget-projection' in .../iso-t020/docs/USER_GUIDE.md
=== M2: plant a byte in close-work-item.mjs ===             M2 rc=1
  FAIL: close-work-item.mjs must be byte-unchanged against origin/main (Spec-AC-06)
=== M3: drop the exact-slug anchoring ===                   M3 rc=0   <-- MUTANT SURVIVED
=== M4: reorder the generators ===                          M4 rc=1
  FAIL: generator order must be overview then userguide-rollup, and nothing else
```

Follow-up probe isolating what M3's survival means (hand-built tree, shipped predicate vs anchor-less mutant):

```
--- WITH the exact-slug anchor (shipped code) ---
rc=0
--- WITHOUT the anchor (M3 mutant) ---
VIOLATION: docs/ai/overview.html carries SPEC-DRAFT-foo while docs/specs/SPEC-0001-bar-foo.md exists
rc=1
```

3 of 4 mutants killed. The survivor is a test-coverage gap (NB-5), not a live defect.
