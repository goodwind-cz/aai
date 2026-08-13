# Code Review — CHANGE-0140 reporting/docs true-up (dual verdict)

```yaml
review:
  scope: eecc340..HEAD (a69bd52) — commits 598bcec, f681cb2, bc056cd, a69bd52; inline path list per spec
  spec: docs/specs/SPEC-DRAFT-spec-reporting-docs-true-up.md (frozen at eecc340, ceremony_level 1)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "docs/USER_GUIDE.md diff (5 hunks, all in-scope); TEST-009 green; rollup re-run in scratch clone: ZERO DIFF (byte-stable, re-verified by this review)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/test-aai-userguide-drift.sh (suite exit 0); RED logs docs/ai/tdd/red-20260813T175818Z-*-userguide-drift.log (RED_CLASS: product_red line 1); in-test exceptions verified at lines 65/125" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/generate-dashboard.mjs:8 import + :23-30 D3 precedence; independent reviewer recompute over 492 runs = 37,098,869 == generator == committed AC evidence; test_120 green" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "generate-dashboard.mjs:411-419 panel substitution; TEST-003/004 green; reviewer probes: partial-data fixture renders ALL canvases (no false no-data), usage_total_tokens=0 counts as signal (recorded-zero, not absence)" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/SKILL_DASHBOARD.prompt.md caveat rewrite; bytes re-measured 4157 -> 4755 = +598 exact; ledger entry prompt-diet-ledger.sh:160; pin -6642+598 = -6044; TEST-006 + prompt-diet suite green" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "docs/product/aai-dashboard.md (read in full — accurate vs code, incl. exit codes 0/1/2 and template contract); TEST-011 green; INDEX row present" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills (repo-wide), line: 0,
          issue: "No class-level CHANGELOG released-region integrity pin — third glued/deleted-heading incident; catches so far are scope-specific luck",
          failure_scenario: "A future edit glues/deletes a released heading OLDER than the newest scope-pinned one (e.g. v2026.08.13 or earlier): no suite fires; the corruption ships and the next aai-release re-rolls released bullets" }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-dashboard.mjs, line: 403,
          issue: "Payload escaping order un-escapes backticks (backtick->\\` then \\ -> \\\\ doubling re-exposes the backtick) and never escapes ${ or String.replace $-patterns — pre-existing, spec-declared residual risk, but reviewer probe PROVED page death",
          failure_scenario: "A ledger run recorded with role 'Impl `loop`' or worktree 'wt-${env}': rendered dashboard.html template literal throws SyntaxError/ReferenceError at load, every chart blank (reproduced: hostile fixture -> new Function() FAILS; real-data HTML parses OK)" }
  cannot_verify:
    - { claim: "Pre-merge full-suite CI proof (selector mode=selected for this diff)",
        closes_with: "PR opened WITH the ci-full label already applied (validation lane statement / CHANGE-0139 F-6 precedent)" }
    - { claim: "Browser-rendered Chart.js visuals (axes, legends, Total series appearance)",
        closes_with: "Opening docs/ai/dashboard.html in a browser; this review syntax-checked all embedded scripts against real data (parse OK) but did not pixel-render" }
    - { claim: "Close-ceremony effects (docs-audit false-open F2 self-resolving, status flip, close events)",
        closes_with: "close-work-item.mjs run at the PR step; audits re-run CLEAN after" }
    - { claim: "Staging decision for the uncommitted regenerated docs/ai artifacts (dashboard.html/-data.json at HEAD still carry zero-token content)",
        closes_with: "Deliberate PR-step decision per validation F3; committed artifacts are stale but outside the spec's inline review scope" }
  overall: pass
```

## Scope and preflight

- Scope: `git diff eecc340..HEAD` — 13 files, 904 insertions / 53 deletions, matching the
  spec's inline review scope exactly (plus docs/INDEX.md, a generated index whose two row
  changes are mechanical consequences of the scope). Branch feat/reporting-docs-true-up;
  `git status` shows only pre-existing uncommitted docs/ai regeneration outputs
  (validation F3 territory) — nothing of this review's doing, nothing in scope dirty.
- Anti-gaming note: the dispatch named focus areas and one fix to verify (F1) but did not
  pre-rate severities or scope-exclude anything; full scope reviewed regardless.

## Focus 1 — F1 fix verification (a69bd52): VERIFIED, byte-verbatim

- `a69bd52` touches ONLY CHANGELOG.md (3 insertions, 1 deletion): the glued line 50 was
  split — bullet terminated at `…suite-map rows for both new suites.`, blank line, and the
  full `## [v2026.08.13.2] — …(CHANGE-0139) [L1]` heading restored as its own line.
- Whole-region check, not just the heading: `tail -n +52 CHANGELOG.md` (from the restored
  heading to EOF) vs `tail -n +14 $(git show 9dc5d10:CHANGELOG.md)` — **cmp reports
  byte-identical**. Preamble lines 1–13 (incl. the bare `## [unreleased]` scaffold) also
  identical to 9dc5d10. The CHANGE-0140 entry sits intact at lines 14–51, one
  `## [unreleased] — <title>` heading per convention.
- `test-aai-win-fallback.sh` (TEST-026) exit 0; `test-aai-release.sh` exit 0.

### Incident-class assessment (0135 / 0138-era / 0140): a gap REMAINS

What actually caught this glue: TEST-026's pin
`grep -qE '^## \[(unreleased|v[0-9][^]]*)\].*CHANGE-0139'` — the glue moved the CHANGE-0139
heading text mid-line, so the `^##` BOL anchor stopped matching. Two contingencies made
that a catch: (a) the damaged heading happened to be the **immediately previous scope's**,
and (b) that scope's suite pins its own heading with a BOL anchor. (The `[L1]` suffix was
not the catching mechanism; the BOL anchor + the `CHANGE-0139` literal were.)

Repo-wide survey of CHANGELOG pins (this review, grep over tests/skills): every existing
pin is **scope-specific** — win-fallback test_023 (CHANGE-0136), TEST-026 (CHANGE-0139),
doctor TEST-032 (doctor scope), update 0137-TEST-010, orchestration-mode TEST-017
(RFC-0005). test-aai-release.sh validates the roll transform **on fixtures only**, never
the real repo file. Therefore:

- Heading DELETION or GLUE of a heading belonging to one of the ~4 recently-pinned scopes:
  caught. The same damage to ANY OLDER released heading: **caught by nothing**. The next
  release cut would silently re-roll or orphan released bullets.
- Recommendation (NB-1): a class-level pin is owed — released-region append-only
  invariant. Cheapest robust form: a test that locates the first `## [v` heading in
  CHANGELOG.md and byte-compares that region against the same region of
  `git show <latest release tag>:CHANGELOG.md` (release history is immutable by
  definition; the F1 verification in this review is exactly this check done by hand).
  Fires on glue, deletion, retitle, and reorder of any released section, at any age,
  without per-scope pins. Disposition: promote-to-follow-up ref (reviewer is read-only;
  orchestrator records it).

## Focus 2 — dashboard code (D3 precedence, Number(null), Total series, no-data)

- **D3 precedence** (`generate-dashboard.mjs:23-30`): explicit-finite wins
  (`tokensIn !== null || tokensOut !== null` → sum with `?? 0`, marker ignored — no double
  count), else `extractUsageTotal(note)` (imported, line 8), else `{total: 0, hasSignal:
  false}`. Marker lands only in `tokensTotal`/`total` — grep confirms no path splits it
  into in/out. Matches the spec's D3 text exactly.
- **Number(null) trap**: `finiteNum()` (lines 14-16) requires `typeof v === 'number' &&
  Number.isFinite(v)` — JSON null no longer coerces to a recorded 0 that would shadow the
  marker. Both normalizers (ledger line 157-158, flat line 132-133) use it. Side note
  (INFO, no failure scenario in the real ledger): numeric STRINGS (`"100"`) were coerced
  by the old `Number()` path and are now rejected into the marker/no-signal path — the
  ledger writer never emits strings, and rejecting them is the more honest reading.
- **Independent recompute** (this review's own script over the real ledger): 492 runs →
  `{total: 37098869, marker: 270, explicit: 0, none: 222}` — equals the generator output,
  the committed AC evidence and the validation recompute to the digit. Per-day sums over
  the generated data: input 0, output 0, total 37,098,869 — no fabricated split anywhere.
- **Total series** (template lines ~482-506): `totalData` falls back to `input+output`
  when `total` is null (legacy data objects) — correct. With all-zero input/output and
  marker-only data the chart draws the real Total line plus two flat-zero Input/Output
  lines: honest, though visually the two zero-lines are noise (INFO, not a defect — they
  correctly represent "no decomposed data recorded").
- **No-data substitution — PARTIAL data cannot go wrong**: `hasTokenSignal` is
  `operations.some(...)`; tdd/worktree/publish stats return null only when the WHOLE
  filtered dataset lacks the source. Reviewer probe: a fixture where only 1 run of 4 has
  a tdd role/worktree/marker/publish name rendered **all four canvases and zero no-data
  divs**. `usage_total_tokens=0` probe: `hasSignal true, total 0` → canvas kept
  (recorded-zero ≠ absence, per D4). Real-ledger run into scratch: exactly
  tdd/worktree/publish no-data divs + tokenChart canvas — matches the ledger's shape.
- Panel `.replace()` ordering is safe: the four `{{PANEL_*}}` placeholders precede the
  `{{METRICS_DATA}}` embed point in document order and the substituted markup contains no
  `$` patterns.
- **NB-2 (pre-existing, now proven)**: the payload escape chain (lines 403-406) replaces
  backslashes LAST, which re-exposes the backslash added by the backtick escape: a
  backtick inside any payload STRING (skill/role name, worktree name, filter value —
  notes never enter the payload) yields `` \\` `` in the template literal = escaped
  backslash + LIVE backtick → literal terminates early → SyntaxError, page dead.
  Reproduced: hostile fixture role ``Impl `weird` </script> ${boom}`` → embedded script
  FAILS `new Function()`; real-data HTML parses OK. `${…}` in a name additionally
  interpolates (ReferenceError, or expression evaluation). `<` survives only by luck of
  JSON `<` semantics. The spec declared this exact area residual risk with
  "fix-at-cause in scope for the payload line only IF a fixture exposes corruption" — the
  shipped fixtures (realistic text) did not; this review's adversarial probe did. Because
  the reachable-input surface is unchanged by this diff (skillStats/worktreeStats names
  pre-date the scope) and no real ledger value contains a backtick or `${`, this is
  NON-BLOCKING. Fix shape for the follow-up: escape backslash FIRST, then `` ` ``, `<`,
  and `$` (or embed via `<script type="application/json">` + JSON.parse), and pass a
  function as the `.replace('{{METRICS_DATA}}', …)` replacement to disarm `$&`-pattern
  semantics. Disposition: promote-to-follow-up ref.

## Focus 3 — drift suite (extractor, self-check, exceptions, reverse completeness)

- **Anchor regex** (`MENTION_RE`, line 60): `(^|[[:space:]]|\`|\(|\|)/aai-[a-z0-9]+(-[a-z0-9]+)*`
  — exactly the D2 set (BOL/whitespace/backtick/paren/pipe). Script paths
  (`.aai/scripts/aai-sync.sh`: `/` preceded by `s`) and URLs (`//aai-…`: preceded by `/`)
  are structurally excluded; verified in the probe file AND by the committed self-check.
- **Self-check non-vacuity** (lines 87-102): runs on EVERY invocation of test_007 against
  a throwaway probe file with one positive control (`` `/aai-probe-positive` `` must
  extract) and two negative controls (script path, pages.dev URL must NOT). A regressed
  extractor fails the positive control before ever touching the guide — the vacuity trap
  (extractor matches nothing → forward trivially passes) is additionally closed by line
  106 (`no anchored mention found at all` → FAIL).
- **Exceptions in-test**: `ALLOWED_GENERATED="aai-test-unit aai-test-e2e aai-build"`
  (line 65) and `REVERSE_EXCEPTIONS=""` (line 125) — both declared IN the test, reverse
  empty as the spec demands (aai-factory-report fixed, not excepted).
- **Reverse completeness**: iterates `"$SKILLS_DIR"/aai-*/` **dynamically** (line 128) —
  nothing hardcoded, all 37 current vendored skills covered, `count -gt 0` guards layout
  drift, and the per-skill grep uses a name boundary `([^a-z0-9-]|$)` so `/aai-test`
  never satisfies `aai-test-unit`.
- INFO (no failure scenario worth a finding): the anchor set omits `[`, so a mention
  written in markdown-link form `[/aai-bogus](…)` would evade the FORWARD check (false
  negative only; the reverse direction and the D1c convention make this cosmetically
  unlikely). Not required by D2; noted for completeness.

## Focus 4 — USER_GUIDE surgery

- Diff re-read hunk by hunk: (1) command-table row, (2) `#### /aai-factory-report`
  section with the vs-dashboard comparison, (3) quick-reference entry, (4)+(5) the two
  dead alias comments removed with surrounding feedback prose untouched, (6) the
  "Workflow metrics dashboard" block inside the generated rollup — the mechanical result
  of the rollup picking up the new product doc, not a hand edit. **Nothing unrelated
  touched.**
- Rollup byte-stability re-proven by this review (not taken from the validation report):
  fresh `git clone` of the repo into scratch, checkout feat/reporting-docs-true-up, run
  `generate-userguide-rollup.mjs` → **git diff empty (ZERO DIFF)**.
- Factory-report section accuracy: four KPI families / per-ISO-week trend / refresh-at-
  close / METRICS+EVENTS sources match `generate-factory-report.mjs` behavior and the
  aai-factory-report skill description; the vs-dashboard split (trends vs per-run
  drill-down) matches both tools' actual outputs.

## Focus 5 — governance

- Diet: `wc -c .aai/SKILL_DASHBOARD.prompt.md` = 4755; at eecc340 = 4157 → **+598
  measured**, ledger entry credits exactly 598 (prompt-diet-ledger.sh:160), headroom
  claim consistent (1622 unchanged); TEST-012 pin −6642 → **−6044** equals the
  independent re-sum (suite green, and −6044 = −6642 + 598 arithmetically).
- Suite-map: `aai-dashboard` row (generator, template, prompt, all three skill dirs,
  product doc, committed outputs) and `aai-userguide-drift` row (USER_GUIDE,
  `.claude/skills/**`, rollup generator) — generous per spec; hygiene-pack green pins
  registration.
- Product doc: read in full — real content, accurate against the code (CLI exit codes
  0/1/2 match parseArgs/generateDashboard; template placeholder contract matches;
  limits honest). Capability `aai-dashboard`, predicate-checked by TEST-011.
- Ceremony 1: declared in intake AND spec with a written justification including the
  recorded judgement that the surface count sits at the top of level 1 — proper form.
- Intake correction (feedback `.mjs` engines all exist) recorded in the spec, not
  silently re-planned — and TEST-009 pins the scripts' documentation surviving.

## Test evidence (this review's own runs, all via aai-run-tests.sh)

| Command | Exit |
|---|---|
| test-aai-dashboard.sh | 0 |
| test-aai-userguide-drift.sh | 0 |
| test-aai-win-fallback.sh (TEST-026 incl.) | 0 |
| test-aai-release.sh | 0 |
| test-aai-metrics.sh (test_120 incl.) | 0 |
| test-aai-userguide-rollup.sh | 0 |
| test-aai-prompt-diet.sh (TEST-012 −6044) | 0 |
| test-aai-hygiene-pack.sh (suite-map rows) | 0 |
| spec-lint --path SPEC-DRAFT-spec-reporting-docs-true-up.md | 0 |
| generate-dashboard.mjs --metrics real ledger --output scratch | 0, Total tokens 37098869 |
| independent D3 recompute (own script, 492 runs) | 37098869 exact |
| scratch-clone rollup re-run | ZERO DIFF |
| CHANGELOG released region vs 9dc5d10 (cmp) | byte-identical |
| hostile-payload probe (backtick/`${}` role name) | embedded script SyntaxError (NB-2 proven); real-data HTML parses OK |
| partial-data / zero-marker panel probes | correct (no false no-data; 0-marker = signal) |

## Warning dispositions (H6)

- NB-1 (CHANGELOG class-level released-region pin missing): **promote-to-follow-up ref**
  — suggested shape: released-region byte-compare against the latest release tag's
  CHANGELOG. Third incident of the class; scope-specific pins provably do not cover
  headings older than the recently-pinned scopes.
- NB-2 (payload escape order / `${}` interpolation in generate-dashboard.mjs:403-406 +
  `$`-pattern replace semantics): **promote-to-follow-up ref** — pre-existing,
  spec-acknowledged residual risk, now with a concrete reproduction; fix is a
  four-line ordering/escaping change plus a function-replacement for the embed.

The orchestrator records both (read-only reviewer files no refs).

## Merge-gate statement

Both verdicts PASS. No BLOCKING findings. spec_compliance: all six Spec-ACs compliant
with independently re-verified evidence; F1 remediation confirmed byte-verbatim across
the whole released region. code_quality: PASS conditional on the two NON-BLOCKING
warnings being recorded per H6 (decision or follow-up ref) before closeout. Merge
readiness additionally requires the validation lane's standing hand-off: open the PR
**with the ci-full label already applied**, and make the deliberate F3 staging decision
for the regenerated docs/ai dashboard artifacts (committed copies at HEAD still show
zero tokens). Merge itself remains an operator action.
