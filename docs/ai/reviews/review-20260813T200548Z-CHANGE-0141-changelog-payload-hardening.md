# Code Review — CHANGE-0141 changelog-payload-hardening

- Date: 2026-08-13T20:05:48Z
- Reviewer: Code Review role (dual-verdict single pass, SKILL_CODE_REVIEW)
- Scope: `git diff 0ff2da1..HEAD` (de580ae, cc52d22, 03484e7, 0f2b3a1) on
  feat/changelog-payload-hardening
- Spec: docs/specs/SPEC-0128-spec-changelog-payload-hardening.md (SPEC-FROZEN @ 0ff2da1,
  ceremony_level 1)
- Validation consulted: docs/ai/validation/validation-20260813T195747Z-CHANGE-0141-changelog-payload-hardening.md (PASS)
- Read-only pass: no product files edited, no branch switch, STATE.yaml untouched.

```yaml
review:
  scope: 0ff2da1..HEAD (tests/skills/test-aai-release.sh, .aai/scripts/generate-dashboard.mjs,
    tests/skills/test-aai-dashboard.sh, tests/skills/test-aai-userguide-drift.sh,
    CHANGELOG.md, docs/INDEX.md, docs/specs/SPEC-0128-spec-changelog-payload-hardening.md)
  spec: docs/specs/SPEC-0128-spec-changelog-payload-hardening.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/test-aai-release.sh:162-249 (released_region_verdict, D1 pipeline-free resolution + D3 awk/cmp) + test_025/test_026; suite rc 0 with 'PASS: TEST-025 released region byte-identical vs v2026.08.13.2'; TEST-002 matrix asserts EXPECTED verdict per arm; RED docs/ai/tdd/red-20260813T193830Z-changelog-payload-hardening-released-region-pin.log" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/generate-dashboard.mjs:412-416 (backslash-first chain) + :430-434 (five function-form substitutions); dashboard suite rc 0 (TEST-012 hostile fixture EMBED-OK, TEST-013 order pin + real-ledger round-trip); reviewer probe: trailing $, string-final backslash, lone ${ at end, $` adjacency, U+2028/29, payload-borne {{PANEL_*}}/{{METRICS_DATA}} all round-trip deep-equal; RED …-hostile-embed.log" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "tests/skills/test-aai-userguide-drift.sh:62 (MENTION_RE + \\[) + :100-107 (link-form positive control); suite rc 0 (TEST-007 forward, TEST-008 reverse 37 skills); RED …-linkform-extractor.log (zero hits pre-change)" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "release/dashboard/userguide-drift/metrics suites all rc 0 via aai-run-tests.sh (reviewer re-run); head -1 of all three RED logs = 'RED_CLASS: product_red'; git diff 0ff2da1..HEAD shows .aai/scripts/aai-release.sh and docs/dashboard-template.html untouched, generate-dashboard.mjs exit paths/flags unchanged; check-test-registration rc 0; spec-lint rc 0" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-dashboard.sh, line: 371,
          issue: "Committed hostile fixture (test_012) omits U+2028/U+2029 line separators and lone-surrogate classes; these were exercised only by the validator's uncommitted probe.",
          failure_scenario: "A future escape-chain edit that normalizes or re-escapes \\u-sequences (e.g. a naive unicode-escape pass) could mangle payload strings containing U+2028/29 or escaped lone surrogates while test_012 stays green — the regression pin never sees those bytes." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-dashboard.mjs, line: 430,
          issue: "METRICS_DATA is substituted FIRST; the four PANEL replaces then scan HTML already containing the untrusted payload. Safe today only because every {{PANEL_*}} placeholder precedes the embed line in docs/dashboard-template.html (367-411 < 423) — first-occurrence semantics find the template's own placeholder.",
          failure_scenario: "A template edit that adds/moves a {{PANEL_*}} placeholder below the script block lets a ledger string containing the literal '{{PANEL_TOKENS}}' hijack that substitution: panel markup is injected inside the JSON payload and the real placeholder stays literal. Free fix: perform the METRICS_DATA replace LAST (or pin the ordering in TEST-013)." }
  cannot_verify:
    - { claim: "CI runners actually have the tags at test time (TEST-025 non-vacuous on CI)",
        closes_with: "one green CI skill-suite log showing 'PASS: TEST-025 … vs v2026.08.13.2'; workflow file already verified: fetch-depth: 0 on all four actions/checkout@v4 steps in .github/workflows/skill-suite.yml (lines 83/124/148/190)" }
    - { claim: "ci-full label on the future PR (validation F2, L1 pre-merge full-suite proof)",
        closes_with: "PR opened with the ci-full label; no PR exists yet" }
    - { claim: "doc-numbering TEST-013 false-open (validation F1) self-resolves at close",
        closes_with: "close-work-item.mjs run at the PR step (precedent CHANGE-0136/0138/0140); rc 0 on main already shown by validation" }
    - { claim: "downstream vendored dashboard-template.html copies inherit the fixed generator",
        closes_with: "next aai-update/aai-bootstrap sync in each downstream repo (spec residual risk, accepted)" }
  overall: pass
```

## Reviewer-run evidence (this pass, not inherited)

| Command | rc | Key line |
|---|---|---|
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh` | 0 | `PASS: TEST-025 released region byte-identical vs v2026.08.13.2 (latest ancestor release tag)`; TEST-022/023/024/026 green in the same run |
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-dashboard.sh` | 0 | TEST-012 hostile embed OK, TEST-013 structural pin + real-ledger round-trip |
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-userguide-drift.sh` | 0 | TEST-007 (link-form control extracted), TEST-008 (37 skills) |
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-metrics.sh` | 0 | whole suite incl. test_120 lib pin |
| `node .aai/scripts/check-test-registration.mjs tests/skills` | 0 | no unregistered suites |
| `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-…` | 0 | LINT PASS, 0 findings |
| `node .aai/scripts/generate-dashboard.mjs --data-only` (real ledger) | 0 | sidecar regenerates cleanly |
| Scratch embed probe (extra-hostile ledger through the REAL generator) | 0 | `PROBE-OK deep-equal; u2028=true trailing$=true endsBackslash=true payloadPlaceholder=true loneDollarBrace=true` |
| Scratch helper probes (extracted `released_region_verdict`) | — | lightweight tag → PASS; `vNEXT`/`v1-beta` in namespace → resolves clean, no crash; CRLF-only divergence → FAIL (honest byte compare); newer non-ancestor tag on side branch → correct older-tag PASS |

## Focus-area answers (dispatch questions, judged against the code)

1. **released_region_verdict correctness.** Tag glob `v[0-9]*` excludes `vNEXT`
   (N not a digit) and admits `v1-beta`-style names; probed — version sort +
   ancestor filter + named skips keep every odd shape safe, and this repo's 21
   tags are all clean CalVer. Annotated vs lightweight both work
   (`merge-base --is-ancestor` peels tag objects; probed both; real
   v2026.08.13.2 is annotated). Ancestor-loop cost: at most one `merge-base`
   call per tag, 21 tags today — negligible. awk region extraction
   (`f { print; next } /^## \[v/ { f = 1; print }`) is inclusive of the first
   heading line with no off-by-one — both sides use the identical extraction,
   and the cmp divergence at "line 1" in the glue replay proves the heading is
   inside the region. CI reality: `.github/workflows/skill-suite.yml` runs
   `actions/checkout@v4` with `fetch-depth: 0` on ALL four checkout steps
   (lines 83/124/148/190) — tags are fetched, so the pin has teeth on every CI
   job of this repo; the tag-naming pass line distinguishes teeth from the
   named skip in any log. Helper emits exactly one verdict line and always
   returns 0; the non-exiting core is what lets test_026 drive negatives
   without tripping `set -euo pipefail`, and the body is pipeline-free (tag
   list into a variable, here-string iteration, direct awk/cmp).
2. **Escape chain.** Order backslash → backtick → `${` → `<` is complete and
   correct: backslash-doubling first means every later inserted `\` is a live
   template-literal escape; `\${` decodes to `${`; `<` decodes to `<`
   keeping `</script>` out of the HTML bytes while JSON.parse sees the raw
   char. A lone `$` before the closing backtick is harmless (only `${` opens
   an interpolation) — probed with a payload string ending in `$` and one
   ending in `${`; both round-trip. Function-form replacement makes `$&`,
   `` $` ``, `$'`, `$n` inert (probed via the committed fixture's
   `Replacement $& $` $1 patterns` role). Repo-wide survey re-run: the
   `.replace('{{…}}', <string>)` embed pattern now exists NOWHERE — the only
   `{{…}}` substitutions in any generator are the five function-form calls at
   generate-dashboard.mjs:430-434; every other string-arg `.replace` in
   `.aai/scripts` is a regex transform with intentional `$n` backreferences on
   generator-owned text, a different class.
3. **Test quality.** test_026 is not vacuous: each arm asserts the EXPECTED
   verdict string (baseline exact `PASS v2026.08.13.2`, glue and retitle
   `FAIL v2026.08.13.2*`, unreleased exact PASS, tagless `SKIP no tag
   matching*`), so a helper that stopped failing would fail the arm. test_012's
   deep-equal recovers the payload from the RENDERED page: it takes the single
   `const rawMetricsData = ` line, evaluates it with `new Function(line +
   "return rawMetricsData;")` (template-literal decode), `JSON.parse`s the
   result and `assert.deepStrictEqual`s it against the sidecar
   dashboard-data.json — plus a whole-script `new Function` parse check and a
   one-script-block assertion that catches `</script>` leakage. TEST-013's
   grep anchors are each unique in the generator file, so the line-order
   assertion cannot be confused by other `.replace` calls. Hostile-fixture gap
   vs validation's extra classes: U+2028/29 and lone surrogates live only in
   the validator's uncommitted probe — NB-1 below recommends committing them
   (my own probe confirms they round-trip today).
4. **Governance.** CHANGELOG adds one `## [unreleased] — …(CHANGE-0141) [L1]`
   per-entry heading with bullets beneath, unreleased zone only —
   TEST-022/023/024/025/026 all green in one run, and TEST-025 itself proves
   the released region byte-identical vs v2026.08.13.2. Ceremony 1 is
   legitimate: no touched path is in `protected_paths_l3`
   (docs/ai/docs-audit.yaml), no exit contract or placeholder moved
   (aai-release.sh and dashboard-template.html have empty diffs). All three
   RED logs carry `RED_CLASS: product_red` as line 1, captured at 0ff2da1.
   Spec AC table and Test Plan are terminal/green with real evidence strings;
   docs/INDEX.md regeneration matches.

## Findings and dispositions (H6)

- **NB-1** (tests/skills/test-aai-dashboard.sh:371): committed hostile fixture
  omits U+2028/U+2029 and lone-surrogate classes; only the validator's
  uncommitted probe covered them. They are harmless on current engines
  (probed), so this is regression-pinning depth, not a live defect.
  Recommended disposition: remediate-in-tree (extend the test_012 fixture
  strings by one role) or promote to a follow-up ref if the tree is frozen.
- **NB-2** (.aai/scripts/generate-dashboard.mjs:430): METRICS_DATA substituted
  before the PANEL substitutions; safety rides on the template keeping all
  `{{PANEL_*}}` placeholders above the script block (true today: lines
  367-411 vs 423; probed un-hijackable). Recommended disposition:
  remediate-in-tree (reorder so METRICS_DATA is replaced last — behavior
  identical today) or promote to a follow-up ref.
- **INFO** (docs/issues/CHANGE-0141-changelog-payload-hardening.md:31): the
  intake's example names the gap as `[text](/aai-x)` — that form was ALREADY
  covered by the pre-change `(` anchor; the real gap (and what the frozen spec
  and implementation correctly address) is the label form `[/aai-x](…)`.
  Documentation imprecision in a draft intake; no action required.
- **INFO**: tag glob `v[0-9]*` admits non-CalVer names like `v1-beta`; probed
  safe (version sort + ancestor filter + named skips). CRLF-only divergence in
  the released region FAILS (byte-compare is honest about line endings). No
  action.

Anti-gaming note: the dispatch suggested "NB recommend adding" for the
U+2028/29 fixture gap; I judged the gap independently (probed the classes
myself) and reached the same NB ranking on its own merits.

## Merge-gate statement

- spec_compliance: **pass** — all four Spec-AC compliant with cited evidence.
- code_quality: **pass** — zero BLOCKING findings; two NON-BLOCKING (NB-1
  fixture depth, NB-2 substitution-order fragility) each carrying a named
  disposition per H6; the orchestrator records the chosen artifact.
- Overall: **pass**. Merge-gate: this scope is merge-ready from the review's
  side ONCE (a) the PR is opened with the `ci-full` label (validation F2 /
  L1 lane rule), and (b) NB-1 and NB-2 dispositions are recorded
  (remediated, decision entry, or follow-up ref) before closeout. Merging
  itself remains an operator action.
