# Code review — a-branch-diff-pin-taxes-every-later-scope (adversarial, ceremony 1)

- Role: Code Review (single dual-verdict pass, .aai/SKILL_CODE_REVIEW.prompt.md)
- Branch: fix/allocator-reports-its-own-degrade, head 0672ab5, base e29adb9 (current main)
- Spec: docs/specs/SPEC-DRAFT-spec-a-branch-diff-pin-taxes-every-later-scope.md (Spec-AC-01..05, ceremony_level 1)
- Validation round 1: docs/ai/validation/validation-20260824T105621Z-a-branch-diff-pin-taxes-every-later-scope-round1.md (PASS — bite proofs, ledger prefixes, allocator diff minimality all re-derived there; NOT repeated here)
- Reviewer note (anti-gaming): the dispatch named attack surfaces and asked for a
  judgment on an already-filed P2 with its severity pre-stated. Recorded per the
  coaching rule; the full diff was read and reviewed regardless, and the pgq
  ratchet, merge drop-analysis, and two containment probes below are this
  review's own measurements, not the dispatch's.

```yaml
review:
  scope: "e29adb9..0672ab5 (5b838e4 allocator reporting tail; eda5e3f containment arm; 0672ab5 merge of main, OURS on the suite)"
  spec: docs/specs/SPEC-DRAFT-spec-a-branch-diff-pin-taxes-every-later-scope.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "pin loop tests/skills/test-aai-spec-lint.sh:1648-1662 byte-unchanged vs e29adb9; validation TEST-101/103 mutation+control proofs. Deviation named: the exit-contract half's literal SHALL-FAIL claim has a filed false-PASS path (fu-exit-contract-pin-comment-dup, P2) — judged below, not a blocker" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "arm has no branch-diff logic to trip (tests/skills/test-aai-spec-lint.sh:1685-1690 compares only vocabulary carriers); validation unrelated-file probe PASS" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "no git diff / origin/main / base_ref inside the arm (whole-file grep hits only line 1498, a different test's comment); manifest at :1681-1684; fourth-carrier probe FAIL per validation, gutted-everywhere and deleted-path probes FAIL loud per this review" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "pass line count is $n from the counting loop :1692-1695; arm comments :1657-1678 carry no path/group count (the only digits in the function are the four pinned exit-code literals)" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "allowlist and its case groups gone (140-line diff removes all 13 groups); decisions.jsonl append at offset 397433: fu-test011-branch-diff-allowlist-tax status done, resolved_by this scope" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-spec-lint.sh, line: 1685,
          issue: "carriers set is measured by grep -rl over the LIVE .aai/ tree, so gitignored runtime files (.aai/cache/) are in scope of the measurement",
          failure_scenario: "a future runtime cache file under .aai/ that embeds doc text containing NEEDS-CLARIFICATION makes TEST-011 FAIL on that developer tree only (CI checkouts have no cache). Fails LOUD and the diagnostic names the extra file, so no false green and no false record — this is a spurious-noise risk, not a vacuous-pass risk. Disposition: accepted residual (see below)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/allocate-doc-number.mjs, line: 814,
          issue: "comment claims the shape is 'copied verbatim from regenerateSpecPagesBestEffort' but the sibling is SILENT on an absent generator (existsSync -> continue, no INFO) while regenerateIndex reports absence",
          failure_scenario: "a reader trusting the comment infers the sibling also reports absence and skips adding the missing-generator INFO there; the behavioral delta (regenerateIndex is stricter, which is the better behavior) is undocumented. Comment-accuracy only, no runtime defect. Disposition: accepted residual (see below)" }
  cannot_verify:
    - { claim: "CI (Linux, GNU grep, bash 5.x) runs the containment arm with the same result as this Mac (BSD grep, bash 3.2.57)",
        closes_with: "the pre-merge full-suite CI run the FULL_RUN protected-l3 trip already forces on this PR (per validation section 'Suite execution'); grep -rlE / sort / herestring usage is portable on inspection, so the residual risk is CI-run-shaped, not code-shaped" }
    - { claim: "no consumer outside this repo parses the allocator completion line expecting docs/INDEX.md to always be present",
        closes_with: "in-repo sweep found only tests/skills/test-aai-doc-numbering.sh:1575 pinning 'allocate complete:' (list-agnostic; suite green per validation); out-of-repo consumers are unobservable from this diff" }
  overall: pass
```

## Attack 1 — the new arm as shell code (with this repo's scars)

- **Suite options are `set -uo pipefail`, no `-e`** (tests/skills/test-aai-spec-lint.sh:20),
  so the one construct that looked abort-prone — `carriers="$(cd ... && grep -rlE ... | sort)"`
  returning grep's 1 under pipefail when nothing matches — cannot kill the run.
  Proved empirically, not just read: probe B (vocabulary gutted from all three
  manifest files in a disposable worktree) produced
  `measured: <empty>` + `FAIL TEST-011(clarify)` + suite exit 1 with the full
  remainder of the suite still executing. Fail-loud, never abort, never vacuous.
- **pgq ratchet (printf|grep -q over 64 KiB)**: live `pgq_scan tests/skills`
  total 389, `test-aai-spec-lint.sh` = 61, byte-equal to the baseline row at
  both e29adb9 and head; `pgq_compare` emits zero RISE/NEW/SHRINK/GONE lines.
  The new arm's pipes are `printf|sort` and `printf|tr` (not quiet-grep) and the
  pre-existing pins grep FROM FILES. No new unsafe occurrence.
- **log_fail in a subshell**: none — `log_pass`/`log_fail`/`ok=0` all execute in
  the function's own shell; the only subshells are `$(printf ...| tr ...)` string
  builders inside log_info arguments. `FAILED=1` propagation intact (proved by
  both probes' suite exit 1).
- **bare `rc=$?` after a pipe**: none in the added code (no `$?` at all).
- **Quoting**: every expansion in the new arm is quoted (`"$carriers"`,
  `"$manifest"`, `"$p"`, `<<<"$carriers"`); manifest and carriers both pass
  through `LC_ALL=C sort`, so comparison order is locale-independent.
- **bash 3.2.57**: whole suite run under `/bin/bash` (3.2.57 arm64) via the
  leak-safe wrapper — exit 0, `PASS TEST-011(clarify) ... contained to the 3
  .aai/ files of the scope's manifest`.

## Attack 2 — the manifest as data

The manifest is a `printf` literal INSIDE the arm (:1681-1684) — it and its
reader are the same lines of the same file, so storage-vs-reader drift is
impossible by construction; it matches the spec's three named paths exactly.
Deletion probe (this review, disposable worktree, PLANNING.prompt.md removed):
`FAIL TEST-011(clarify)` with `measured: .aai/scripts/spec-freeze.mjs
.aai/scripts/spec-lint.mjs` — fail loud, names the shrunken set. Gutted-everywhere
probe: fail loud with the empty set printed (above). The one data-shaped residual
is the live-tree/gitignored-files exposure (NON-BLOCKING finding 1), whose
failure direction is spurious-FAIL, never vacuous-PASS.

## Attack 3 — judgment on fu-exit-contract-pin-comment-dup (P2)

**Judgment: filing was the correct disposition; this is NOT a merge blocker.**
The mechanism is real and re-confirmed by reading: spec-freeze.mjs duplicates
the four phrases in a header comment (lines 54-61) above the runtime strings
(101-106), and the whole-file `grep -qF` (suite :1660) is satisfied by the
comment alone, so runtime-only drift stays falsely green. Why file-not-fix, in
this ride specifically:

1. **The gap pre-exists on main in bytes this ride did not touch.** The pin loop
   is outside the diff (context-identical to e29adb9) and spec-freeze.mjs is not
   in the branch diff at all. Blocking this merge would hold an allocator fix and
   a tax repayment hostage to a latent weakness both older than the branch.
2. **Every candidate fix breaches this ride's frozen boundary.** The spec's
   ceremony justification pins "the durable half of the same arm is held
   byte-identical"; the alternative surface, spec-freeze.mjs, is a file this
   ride's whole evidence story verifies as untouched. Editing either is scope
   widening past a frozen L1 spec.
3. **No candidate fix is trivially correct.** Anchoring the grep on JS source
   formatting (`+ '  0 frozen...`) pins formatting; requiring >=2 occurrences
   false-FAILs the day the comment is legitimately de-duplicated; de-duplicating
   the comment changes a protected-adjacent file. Choosing between these IS the
   follow-up's work.
4. **Precedent and policy line up**: the same-class, weaker
   fu-usage-pin-misses-appended-flag (P3) was filed, not fixed, in this very
   ride; the comment-dup variant is graded stronger (P2) because it misses ANY
   runtime-only rewording, which is the honest severity. P2 correctly took
   disposition (b) (typed follow-up), not accepted-residual — per the WARNINGS
   policy, (d) is P3-only.

Caveat kept visible: until that follow-up lands, a runtime-only exit-contract
drift would print a green TEST-011 pass line — the false-green is recorded in
the ledger (the follow-up entry), so the repo record is qualified, not false.

## Attack 4 — the merge commit (OURS on the suite)

`git diff f65ae56 e29adb9 -- tests/skills/test-aai-spec-lint.sh` (everything
main did to the suite since the fork) is exactly: the eleventh allowlist payment
(the `.aai/SKILL_CODE_REVIEW.prompt.md|.aai/SKILL_WRAP_UP.prompt.md` case group
plus its comment) and the pass-line recount "36 paths across 13 case groups" —
all of it inside the region eda5e3f replaced. The OURS resolution therefore
dropped only the payment the repair makes moot; nothing else of main's was
lost. Cross-file check: `git diff e29adb9 0672ab5 --stat` lists exactly the 7
branch-owned surfaces, so every other file main touched (including
.aai/PLANNING.prompt.md +6, SKILL_CODE_REVIEW, SKILL_WRAP_UP, SPEC-0149,
CHANGE-0161, registry-growth-diagnosis, LEARNED) is byte-identical to main in
the merge result. Ledger appends in the range are exactly 4 decisions (3
closures + 1 new P3) and 1 doc_lifecycle event after main's byte-exact prefix
(prefix cmp re-derived by validation; append content read here and consistent).
docs/INDEX.md is a clean regeneration reflecting the two new draft docs.

## Attack 5 — registry-policy compliance (second ride under accepted residual)

Validation's two accepted residuals (line-split evasion, case-variation evasion
of the carrier regex) are honest disposition-(d) uses: both are
assurance-strength limits requiring deliberate adversarial input, neither has an
observed bite, and neither leaves a false record (the green line claims
containment of the exact vocabulary, which stays true). The one finding that DID
bite under mutation (comment-dup) was correctly escalated to a filed P2 instead
of being laundered as a residual. Policy applied as written.

## Warning dispositions (H6)

- Finding 1 (live-tree grep includes gitignored .aai/ files) —
  **accepted residual: P3 assurance/robustness; failure direction is a loud,
  self-naming spurious FAIL on a developer tree only, no false green, no false
  record; confining to `git ls-files` would add its own empty-xargs failure
  modes for a hazard with no current instance (.aai/cache/ holds one JSON with
  no vocabulary).**
- Finding 2 (allocator comment overstates "verbatim") —
  **accepted residual: P3 comment-accuracy; behavior is correct and stricter
  than the sibling; no false record outside one adjective in a comment.**

## Verdict

**PASS** — spec_compliance pass, code_quality pass (no BLOCKING findings),
cannot_verify list above. The filed P2 stays a follow-up, judged correctly
disposed; both review warnings are recorded accepted residuals per H6(d).
