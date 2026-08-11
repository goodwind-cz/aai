# Code Review — CHANGE-0131 / spec-evidence-path-gate

```yaml
review:
  scope: git diff main...HEAD (branch feat/evidence-path-gate, HEAD 65c6472; 5 commits, 11 files, +1157/-6)
  spec: docs/specs/SPEC-DRAFT-spec-evidence-path-gate.md (SPEC-FROZEN, ceremony_level 1)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/lib/evidence-paths.mjs:76-96 (six rules, in D2 order) + TEST-036 (re-run green at HEAD) + my own edge probe (markdown link, trailing !/?, backslash path, `..` traversal all -> [])" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/lib/evidence-paths.mjs:34,104-117 (parseAcTable + parseLeanAcTable fallback, no local heading regex) + TEST-037 grep contract + table-less/lean behavioral arms" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/lib/guard-config.mjs:40 (GUARD_DIALS), :68 (defaults), :84 (line-parser alternation); docs/ai/docs-audit.yaml:66 + TEST-038; `grep -c '^evidence_path_gate: report-only$' docs/ai/docs-audit.yaml` = 1" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/close-work-item.mjs:1020-1022 (WARNING branch) + TEST-039 (asserts doc, Spec-AC id, absent path named; resolvable path NOT named)" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/scripts/close-work-item.mjs:1015-1019 placed before readEvents:1023 + TEST-040 (exit 5, diff -q on both docs, EVENTS size, docs/INDEX.md absent)" }
      - { ac: Spec-AC-06, call: compliant,
          citation: ".aai/scripts/lib/evidence-paths.mjs:122-126 (fs.existsSync, directory resolvable) + TEST-041 (git check-ignore fixture assertion, then rm -> exit 5)" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "TEST-042 (three prose-only Evidence cells under enforce -> exit 0, `grep -qi 'evidence-path gate'` on stderr empty) + validation's 27-shape probe" }
      - { ac: Spec-AC-08, call: compliant,
          citation: ".aai/scripts/close-work-item.mjs:1057 (evidencePathGate in the dry-run JSON) + TEST-043 (severity refuse, path listed, doc bytes + EVENTS + INDEX untouched)" }
      - { ac: Spec-AC-09, call: compliant,
          citation: ".aai/system/PROFILES.yaml:117 + validation section 1 (five commands exit 0); I re-ran the close suite and spec-lint at HEAD 65c6472 post-F1: ALL TESTS PASSED / Findings: 0" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-close-work-item.sh, line: 1723,
          issue: "D2 rule 5 (no segment is exactly '..') is the only one of the six rules with zero test coverage, while the test's log_pass claims it 'rejects every hostile shape'. Rule 5 is load-bearing, not decoration: I verified statSync(root + '/..').isDirectory() === true, so rule 6 alone ADMITS a traversal token.",
          failure_scenario: "Drop rule 5 in a future refactor and no test fails. An Evidence cell citing e.g. `../shared/docs/ai/tdd/red.log` (a monorepo/worktree-relative citation) is then extracted, does not resolve from ROOT, and under `evidence_path_gate: enforce` refuses a legitimate close with exit 5 — the exact false-positive class the whole grammar exists to avoid. Fix is one `eq('parent traversal', extractEvidencePaths('../../etc/passwd', root), [])` line." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/guard-config.mjs, line: 40,
          issue: "Seam S3 is pinned for THIS dial but not for the dial CLASS. GUARD_DIALS has no production consumer (grep across the repo: the export plus two test files); the reader's actual behavior lives in two other hand-maintained literals — the defaults object (:65-70) and the regex alternation (:84). hygiene-pack test_031 iterates only close_gate and doc_number_guard, so it does not close the class either.",
          failure_scenario: "Dial #7 is added to GUARD_DIALS and the defaults object but not to the alternation, with a unit test that asserts only `GUARD_DIALS.includes('new_dial')` (the shape TEST-035 and TEST-038 both start from). readGuardConfig then returns 'report-only' forever, the operator sets `enforce` in docs-audit.yaml, and the gate silently never fires. Structural fix is small and local: derive both the defaults object and the alternation FROM GUARD_DIALS." }
  cannot_verify:
    - { claim: "Behavior on case-sensitive filesystems (Linux CI) — a wrong-case citation resolves locally on APFS and would not on CI (R4).",
        closes_with: "One CI run of tests/skills/test-aai-close-work-item.sh on ubuntu-latest, plus a case-mismatch fixture arm." }
    - { claim: "The false-positive rate of the grammar on FUTURE rides under `enforce`. The 752/0 and 772/0 numbers are measurements of today's corpus, not a bound on tomorrow's Evidence prose.",
        closes_with: "Accumulated report-only WARNING telemetry across N closes before any flip to enforce — the same evidence pattern usage_capture_gate used (26/26)." }
    - { claim: "Downstream/vendored consumers receive .aai/scripts/lib/evidence-paths.mjs correctly through aai-update.",
        closes_with: "An aai-update dry-run against a downstream target showing the new lib in the add list." }
    - { claim: "Windows behavior. Backslash paths are excluded by charset rule 3 (verified by probe), but no code path was executed on Windows.",
        closes_with: "A Windows run of the close suite, or an explicit statement that close-work-item is POSIX-only." }
  overall: pass
```

## Scope and method

- Branch verified with `git branch --show-current` → `feat/evidence-path-gate`; never switched, never pushed; working tree clean at review start and at review end.
- Read-only on implementation files. Nothing under `.aai/`, `docs/specs/`, `docs/issues/` or `tests/` was written. The only file this review creates is this report.
- Diff read in full: `git diff main...HEAD` over `.aai/scripts/close-work-item.mjs`, `.aai/scripts/lib/evidence-paths.mjs`, `.aai/scripts/lib/guard-config.mjs`, `.aai/system/PROFILES.yaml`, `CHANGELOG.md`, `docs/INDEX.md`, `docs/ai/EVENTS.jsonl`, `docs/ai/docs-audit.yaml`, `docs/issues/CHANGE-0131-evidence-path-gate.md`, `docs/specs/SPEC-DRAFT-spec-evidence-path-gate.md`, `tests/skills/test-aai-close-work-item.sh`.
- Validation report `docs/ai/validation/validation-20260811T225925Z-CHANGE-0131-evidence-path-gate.md` read as settled ground (PASS; F1 fixed post-validation, F2 recorded as spec R6). This review did not re-run validation's matrix; it re-ran only what the post-validation commit put at risk (below) and added its own code-level probes.
- Dispatch-coaching check (anti-gaming contract): the dispatch named review AREAS (grammar readability, wiring quality, S3 maintainability, comment accuracy, CHANGELOG truthfulness, test quality, merge fitness) without pre-rating severity, characterizing expected findings, or excluding any part of the diff. No coaching to record.

## Post-validation delta — the F1 commit (65c6472)

Validation ran at `cbe38f6`. `65c6472` changed the risk-bearing lib and the frozen spec afterwards, so it is unvalidated surface and I verified it directly:

- **Semantics.** The raw NUL at the memo-key join is now the escape `\u0000` inside a template literal (`.aai/scripts/lib/evidence-paths.mjs:60`). In JS a `\u0000` escape in a template literal produces U+0000 — byte-for-byte the same key the raw NUL produced. Confirmed at runtime: the escaped string `===` `'r' + String.fromCharCode(0) + 's'`, length 3, `charCodeAt(1) === 0`.
- **Diffability restored.** `python3` byte scan: 0 NUL bytes; `file` reports `Java source, Unicode text, UTF-8 text` (was `data`); `git diff main...HEAD --stat` now shows `126 ++++...` instead of `Bin 0 -> 5707 bytes`. The remaining non-ASCII bytes are U+2026 (rule 2's `…` literal) and U+2014 (em dashes in comments) — both ordinary UTF-8, both diff-visible. `.gitattributes` `*.mjs text eol=lf` is satisfied.
- **Suite still green at HEAD** (this is the assertion validation could not make): `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-close-work-item.sh` → `=== aai-close-work-item: ALL TESTS PASSED ===`, TEST-036..043 all PASS. TEST-037's `grep -qF` contract, which validation flagged as evaluating against a binary file, now runs against plain text and still discriminates.
- **Spec still lints at HEAD** after R6 was appended: `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-evidence-path-gate.md` → `Findings: 0`.

Verdict on the F1 fix: correct, minimal, and it converts the scope's single most risk-bearing artifact from unreviewable to reviewable. Without it I would have raised the binary lib as BLOCKING (a diff no human and no PR bot can read is not a reviewable diff).

## The grammar as code (`.aai/scripts/lib/evidence-paths.mjs`)

**Rule ordering is right and deliberate.** Cheap string tests run first; the only I/O (rule 6's `statSync`) runs last and behind a module-level memo. The six inline `// rule N` markers line up 1:1 with the header block and with D2, so a reader can check the implementation against the design without leaving the file. This is the rare case where the comment volume (30 header lines for 60 code lines) earns itself: each rule carries the *observed rejection* that motivated it, which is exactly the information a future maintainer needs before deleting one.

**Comment honesty — checked line by line, three minor drifts, no lies:**
- Header: "752 tokens extracted, 0 false positives over 718 cells" is presented as the pre-write measurement and is true as history; the live number is now 772 (validation section 5). It will decay further. INFO only — the sentence says "measured before it was written".
- `isExistingRootDir` (:54-58) says "Memoized per (root, segment)" and then quotes D2's "memoized per call site". The cache is module-global, which is *stronger* than per-call-site; the quote misdescribes the code it sits on. INFO.
- Rule 3's claim that the charset "subsumes globs, brace expansions, line-number suffixes, URLs and backtick-glued joins in one stroke" is accurate — I re-derived each rejection.

**API surface — `extractEvidencePaths` / `evidenceCitations` / `unresolvedCitations` is the right export set.** It is a clean three-layer stack: pure grammar over a string → doc-level rows → existence filter. Only the third has a production consumer; the first two are exported for the hostile unit test (TEST-036) and the corpus tripwire respectively, which is precisely D1's stated reason for the pure-lib split. No fourth export, no options bag, no class. I would not change it.

**Edge behavior I probed directly (all safe-direction):**

| input | result | note |
|---|---|---|
| `../../etc/passwd`, `docs/../../../etc/hosts`, `..` | `[]` | rule 5; without it rule 6 would admit these (see NON-BLOCKING 1) |
| `[docs/ai/tdd/red.log](docs/ai/tdd/red.log)` | `[]` | markdown links are skipped entirely — `]` and `(` survive stripping and fail charset |
| `docs/ai/tdd/red.log!`, `...log?` | `[]` | `!` and `?` are not in `TRAILING_RE`, so charset rule 3 rejects the whole token |
| `docs\ai\tdd\red.log` | `[]` | Windows separators, as the spec's edge-case list says |
| `docs/`, `docs//x` | extracted | trailing slash and double slash both resolve via `existsSync`; harmless |
| this spec's own doc | 21 tokens, 0 unresolved | the scope passes its own gate — the CHANGE-0127 incident is not repeated |

The markdown-link and `!`/`?` cases are false NEGATIVES (under-gating), which is the design's declared bias — "biased to skip rather than to guess". Not findings; worth knowing when someone later asks why a real path was not checked.

`stripEdgePunct`'s repeat-until-stable loop is correct for stacked punctuation and terminates because each iteration that sets `changed` also shortens `s`. Worst case is O(n²) slicing on a pathological all-punctuation token; validation measured 1 ms at 10 010 chars, and Evidence cells are table cells. Not a finding.

`ROOT_DIR_CACHE` is module-global and never invalidated. Correct for the one-shot `close-work-item` process and for the per-case fresh `node` the tests spawn. It would go stale for a hypothetical long-lived consumer that creates a root directory after a negative probe (a watch mode, or the repo-wide audit R2 warns about). INFO, no disposition needed today.

## Wiring quality (`close-work-item.mjs`)

- **Exit contract.** Code 5 is documented in the header block with the same six-line shape as 3 and 4, including the `--dry-run never returns 5` clause. `grep 'process.exit('` confirms 5 is otherwise unused in the file. Clear.
- **Placement.** `evaluateEvidencePathGate(resolved)` sits at :1015, after the usage gate (:1000) and before `readEvents` (:1023) — ahead of the idempotency short-circuit's `regenerateIndex`, which is the S1 hazard. TEST-040 and validation arm B both assert `docs/INDEX.md` was never created on the refusal path.
- **Sibling symmetry is exact**, and that is the main maintainability win here: same `{ severity, dial, ..., reason }` shape, same `readGuardConfig(path.join(ROOT, 'docs/ai'))` call site, same `severity: 'none'` early return that omits `dial` (the usage gate returns `{ severity: 'none', roles: [] }` identically), same two `if (!args.dryRun && ...)` branches, same message prefix grammar. A reader who knows gate 3 or 4 knows this one on sight. The `dial`-omitted-on-none shape means the dry-run JSON's `evidencePathGate` usually carries no `dial` key — consistent with its siblings, so I am not flagging it, but a consumer parsing that JSON must treat `dial` as optional.
- **Operator UX of the messages.** D9 is met and it matters: the reason string names doc + Spec-AC id + token per unresolved citation, with `u.acId ?? '(unknown AC)'` degrading honestly when a lean row has no id. One structural nit: all unresolved citations are joined with `'; '` into a single stderr line, so a doc with a dozen dead citations produces one very long line. Readable at the realistic n=1..3; a `\n  - ` join would be kinder. Not a finding (no failure mode), but the cheapest possible follow-up if anyone touches this block.
- **Scope selection.** The gate iterates `resolved` (primary `--ref` plus `--spec` when given), matching D5, rather than re-globbing — no repo-wide sweep, no second doc resolver.

## Guard-config three-point synchronization

The three touch points all moved together in this diff (`GUARD_DIALS` :40, defaults :68, alternation :84), and TEST-038 pins them *behaviorally* by driving the real `readGuardConfig` over a temp yaml rather than asserting membership — validation's S3 mutation test confirms the pin catches an alternation-only regression in three separate tests.

So for `evidence_path_gate` the hazard is closed. For the *class* it is not: see NON-BLOCKING 2. `GUARD_DIALS` is a declarative list with zero production readers while the behavior lives in two parallel literals, and `test_031_guard_config_conformance` iterates only `close_gate` and `doc_number_guard`. Every new dial therefore depends on its author remembering to write a TEST-038-shaped test. The scope did remember; the next one may not. My recommended disposition is a follow-up ref rather than in-tree remediation — `guard-config.mjs` is shared with the pre-commit hosts and the CI numbering mirror, and refactoring the defaults/alternation to derive from `GUARD_DIALS` is a change to a shared reader that deserves its own declared scope, not a rider on this one.

One thing I checked and can clear: a change touching only `.aai/scripts/lib/evidence-paths.mjs` is NOT missed by CI test-impact selection despite the lib being absent from `suite-map.yaml`'s `aai-close-work-item` globs — `select-suites.mjs` escalates any `.aai/scripts/lib/**` change to `FULL_RUN` via the `shared_lib_globs` trigger. No finding.

## docs-audit.yaml comment block

Accurate on every claim I could test: "Consulted ONLY by close-work-item.mjs" (grep confirms the single consumer), "Default … is report-only, fail-open" (TEST-038's absent-key and invalid-value arms), "existence is checked with fs.existsSync (not git-tracking)" (D4, TEST-041), "Close-only dial … the shell greps deliberately do not mirror it" (no `evidence_path_gate` in `pre-commit-checks.sh`/`.ps1`, and `test_031` covers only the two hook dials — so the statement describes reality rather than aspiration). It follows the house style of the two blocks above it, including the "AAI core ships this key report-only" sentence. The shipped value is `report-only`, exactly one column-0 occurrence.

## CHANGELOG truthfulness

Walked bullet by bullet against the diff; no overclaim. The one number to watch — "752 tokens extracted, zero false positives over 718 cells" — is explicitly attributed to the pre-implementation measurement ("Measured against the live … corpus before it was written"), which is how validation re-measured it (751 excluding this spec's own doc, 772 including). "exit code 5 (documented in the EXIT CONTRACT header, after the existing 0-4)" is true. "the pre-existing TEST-001 through TEST-035 continue registered and green" is true (43 registered functions, 44 PASS lines). The entry uses a per-entry `## [unreleased] — <title>` heading, which is what `aai-release` requires at cut time. The "Fixes the CHANGE-0127 incident" closing bullet is the one rhetorical line; it is accurate in the sense that matters (the mechanism that would have caught it now exists and ships report-only) and the report-only shipping state is stated two bullets above it, so it does not mislead.

## Test quality — do TEST-036..043 assert what their names claim?

Yes, with one gap.

- **TEST-036 `..._extraction_grammar`** — 13 assertions, 1 positive with stacked trailing punctuation, 12 hostile. Covers rules 1, 2, 3, 4, 6. Does **not** cover rule 5 (NON-BLOCKING 1). Two of the twelve (`sha256 digest`, `run id`) contain no `/` and so die on rule 1 — they are near-free assertions rather than grammar pressure, but they are named in Spec-AC-01 so they belong. The `log_pass` wording "rejects every hostile shape" is a universal claim over Spec-AC-01's enumerated list, which it does satisfy; `..` is not on that list, which is why this is a code-quality gap and not a spec non-compliance.
- **TEST-037 `..._shared_parser_contract`** — the grep half is a real S2 contract (both imports present, `docs-model.mjs` named, no `Acceptance Criteria Status` literal in the lib) and the behavioral half exercises both the empty and the lean path. Note the negative grep is phrase-based: a future maintainer who writes the words "Acceptance Criteria Status" into a *comment* in this lib fails the test with a message about a regex they did not add. Mildly false-positive-prone; INFO, and the alternative (a regex-detecting grep) is worse.
- **TEST-038 `..._guard_config_evidence_path_gate_dial`** — four value arms through the real reader plus the shipped-yaml grep. This is the test that makes S3 a real pin rather than a membership assertion. Best test in the set.
- **TEST-039 `..._report_only_warns`** — asserts all four things the name and D9 imply, including the negative (`grep -qF` on the *resolvable* path must find nothing) and the status flip. Strong.
- **TEST-040 `..._enforce_refuses_pre_write`** — exit 5, `diff -q` on both docs against pre-run copies, EVENTS byte length, `docs/INDEX.md` non-existence. "Pre-write" is genuinely proven, not asserted.
- **TEST-041 `..._existence_not_tracking`** — the fixture self-checks with `git check-ignore -v` before relying on the gitignore (good: a broken fixture fails loudly instead of passing vacuously), then flips to exit 5 after deleting only the ignored file. The name's claim is exactly what runs.
- **TEST-042 `..._prose_never_refuses`** — the intake's hard requirement. Three hostile cells under `enforce`, exit 0, and a case-insensitive `grep -qi 'evidence-path gate'` over stderr proving *no* gate line at all. As a negative control it can only ever confirm; validation's 27-shape probe is the stronger evidence and is recorded.
- **TEST-043 `..._dry_run_noop`** — parses the JSON rather than grepping it, asserts `severity === 'refuse'` and the path's presence, plus doc bytes, EVENTS size, INDEX absence. Matches its name.

Fixture hygiene is consistent with the existing 35: `set_evidence_path_gate_dial` mirrors the two sibling dial helpers exactly, and S5 holds (the pre-existing fixtures' Evidence cells carry `commit-abc` or `—`, neither containing `/`).

## Merge fitness

Merge-fit. The change is additive, dialed fail-open, and its worst realistic bug is a spurious stderr WARNING; the refusal arm requires an explicit opt-in that this repo does not ship. The pre-write placement is the one hard constraint and it is proven three ways (TEST-040, validation arm B, the S1 assertion shared with TEST-031). The post-validation commit is verified above. Both NON-BLOCKING findings are about *future* regressions, not present defects.

Before closeout, per the H6 warnings policy, each NON-BLOCKING finding needs a recorded disposition (orchestrator's action, not mine):

| Finding | Recommended disposition |
|---|---|
| NON-BLOCKING 1 — rule 5 untested in TEST-036 | **remediate-in-tree**: one `eq()` line in TEST-036 (`'../../etc/passwd'` → `[]`). One line, in the file already being changed, closing the only untested rule of the grammar that is the whole point of the scope. |
| NON-BLOCKING 2 — GUARD_DIALS is decorative; the dial class is not structurally guarded | **promote-to-follow-up-ref**: a CHANGE deriving the defaults object and the line-parser alternation from `GUARD_DIALS` in `lib/guard-config.mjs`, with a conformance test that iterates the array. Out of this scope's declared surface and touching a reader shared with the pre-commit hosts. |

Also worth carrying into the close notes: R4 (case sensitivity) and the `enforce`-flip decision should be re-read together — the flip is the moment the APFS/Linux split becomes a real CI/local divergence rather than one stderr line.

## Timing note

`started_utc` below is the first system-clock reading captured during this review, not the dispatch moment — the read phase preceded it and was not clocked, so `duration_seconds` is a lower bound. Recorded this way rather than estimated.
