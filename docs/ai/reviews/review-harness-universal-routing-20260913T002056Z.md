# Code Review — harness-universal-routing (single dual-verdict pass)

```yaml
review:
  scope: >-
    worktree /Users/ales/Projects/aai-feat-harness-universal-routing,
    branch feat/harness-universal-routing (spec commit 2364963b off main 181d67e0)
    + uncommitted working tree: .aai/scripts/orchestration-dispatch.mjs
    .aai/scripts/lib/harness.mjs (new, untracked) .aai/system/MODEL_ROUTING.yaml
    .aai/system/PROFILES.yaml .aai/SUBAGENT_PROTOCOL.md
    tests/skills/test-aai-orchestration-dispatch.sh
    tests/skills/lib/cd-subshell-leak-baseline.tsv
    docs/specs/SPEC-0177-spec-harness-universal-routing.md
  spec: docs/specs/SPEC-0177-spec-harness-universal-routing.md (SPEC-FROZEN + post-freeze Amendment)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "orchestration-dispatch.mjs:1454-1455 (single detect, stamped before every arm), :1480 (fallback re-stamp); TEST-050 + TEST-038 re-run green here" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/lib/harness.mjs:34-45 (ordered ladder, closed set, empty-string = unset); TEST-048 green; mutation M1/M2 redden" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "harness.mjs — no fs import, no GEMINI_CLI_IDE_*/CLAUDE_CONFIG_DIR probe; TEST-049 green incl. a root carrying all five mirror dirs; M3/M4/M5 redden" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "orchestration-dispatch.mjs:1236-1242 (Mode B resolves inside hmap only, `!hmap` returns null); TEST-051 (incl. N3) + TEST-052 green; M7(re-recorded)/M8 redden" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "orchestration-dispatch.mjs:1245-1268 (tiers@H at/above routed tier, then validation_alternate@H, else residual); TEST-053 (incl. N5) + TEST-054 green; M9/M10/M11 redden. See NB-2: the 'at' half of the boundary is unpinned." }
      - { ac: Spec-AC-06, call: compliant,
          citation: "orchestration-dispatch.mjs:1271-1283 (Mode A arm untouched); TEST-055 against pinned blob 0fb736ca (verified == `git rev-parse 181d67e0:.aai/scripts/orchestration-dispatch.mjs`), both harness arms; mutation-055.txt substitutes for the RED" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "TEST-056 sweeps the SHIPPED routing file through the SHARED lib/pricing.mjs resolveModelKey against the SHIPPED PRICING.yaml, with a per-harness `tiers@H examined` floor; mutation-056.txt" }
      - { ac: Spec-AC-08, call: compliant,
          citation: ".aai/system/MODEL_ROUTING.yaml tiers@claude (haiku-4-5 / sonnet-5 / opus-5), zero `claude-opus-4-8`; TEST-057 green; TEST-020 updated in the same file" }
      - { ac: Spec-AC-09, call: compliant,
          citation: "orchestration-dispatch.mjs:1183 row regex `^ {2}(\\S[^:#]*):`, :1193-1201 leftover NOTE; MODEL_ROUTING.yaml header §HARNESS-SCOPED KEY FORM; TEST-058 (5 header greps incl. the M13 lead-in, N6) + TEST-060 green; M12/M13/M14 redden" }
      - { ac: Spec-AC-10, call: compliant,
          citation: ".aai/system/PROFILES.yaml:141 `- .aai/scripts/lib/harness.mjs`; TEST-059 — `bash tests/skills/test-aai-layer-profiles.sh` re-run green here" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/orchestration-dispatch.mjs, line: 1480,
          issue: "The --confirm record-failure fallback — the one arm that shipped round-1's BLOCKING defect — is asserted at exactly ONE harness value; `fallback.harness = 'claude'` (a hardcode) passes TEST-038 unchanged (measured).",
          failure_scenario: "A later edit re-hardcodes or re-detects in that arm. A Codex loop whose --confirm append fails takes the fallback dispatch, which reports harness:\"claude\" and, under the shipped Mode B file, a claude-map suggested_model — the cross-vendor leak this ride exists to remove, on the arm that already regressed once, with a green suite." }
      - { rank: NON-BLOCKING, file: .aai/scripts/orchestration-dispatch.mjs, line: 1253,
          issue: "D4's 'at OR ABOVE the routed tier' is pinned only on the lower bound (M9). `for (let i = startIdx + 1; ...)` survives TEST-051, TEST-053 and TEST-054 (measured).",
          failure_scenario: "`roles@codex: { Validation: gpt-5-mini }` with suggested_tier premium and implementer_model gpt-5-mini. Correct code swaps to tiers@codex.premium; the off-by-one skips the routed tier, falls to validation_alternate@codex or — absent one — keeps the implementer's own model and stamps `single_model_harness_reuse`, recording 'this harness cannot do better' about a harness that could." }
      - { rank: NON-BLOCKING, file: .aai/scripts/orchestration-dispatch.mjs, line: 1177,
          issue: "`validation_alternate@H:` ALONE tripping Mode B is unasserted. Dropping `routing.mode = 'B'` from that branch passes TEST-051, TEST-053 and TEST-058 (measured). The remediation closed the roles@H instance (N6), not the class D1 names.",
          failure_scenario: "A downstream file migrated one section at a time, starting with `validation_alternate@codex:`, stays Mode A under that regression: the unsuffixed claude `tiers:`/`roles:` stay live and a Codex loop is handed claude ids, with no leftover NOTE (Mode B never entered) and a green suite." }
      - { rank: NON-BLOCKING, file: .aai/scripts/orchestration-dispatch.mjs, line: 1401,
          issue: "With the SHIPPED Mode B file present, a cursor/unknown dispatch's --human block prints `Suggested model id: (unbound — no .aai/system/MODEL_ROUTING.yaml)`. The file exists and carries three maps. Measured end to end.",
          failure_scenario: "An operator on Cursor, or any environment exporting none of the D3 markers (a cron- or CI-driven loop, a shell that lost CLAUDECODE), reads that the routing file is missing, goes looking for a file that is right there, and never learns the real cause is harness:unknown with no map." }
      - { rank: NON-BLOCKING, file: .aai/scripts/orchestration-dispatch.mjs, line: 1157,
          issue: "A `@<harness>` section whose suffix is outside HARNESS_VALUES — a typo (`tiers@codx:`), a case difference (`tiers@CLAUDE:`), or a harness outside the closed set (`tiers@windsurf:`) — flips the file to Mode B and then matches no detected harness. Measured: `tiers@CLAUDE:`/`roles@CLAUDE:` under AAI_HARNESS=claude gives suggested_model null, exit 0, ZERO bytes of stderr. Same silence for `effort_tiers@claude:`, which no regex matches.",
          failure_scenario: "A downstream project on Codex edits the shipped file and writes `tiers@Codex:`. Every dispatch from then on carries suggested_model:null with no diagnostic; the deterministic-routing lever is silently off and the orchestrator is back to interpreting suggested_tier by LLM judgment. This is the class D2 refused to leave silent one paragraph earlier." }
      - { rank: NON-BLOCKING, file: .aai/system/MODEL_ROUTING.yaml, line: 1,
          issue: "The routing file is VENDORED, not preserved: PROFILES.yaml:184 lists it under `core:` and aai-sync.sh:293-302 `copy_replace`s every core-listed file into the target. /aai-update therefore overwrites a consumer's copy — so the header's back-compat claim ('the shape every downstream AAI project's existing copy of this file is in today') describes a state the upgrade path removes. No CHANGELOG `## [unreleased]` entry accompanies the scope either, unlike 10ffe15d / 0bdca870 / 7e18f0d9 / 3625378d.",
          failure_scenario: "A downstream AAI project on Claude with a deliberate cost cap (`premium: claude-sonnet-5`) runs /aai-update. Their cap is replaced by the shipped Mode B file; premium dispatches route to claude-opus-5 and their METRICS ledger records the jump with nothing anywhere — file header, protocol, CHANGELOG — explaining why. A consumer whose environment exports no D3 marker instead goes from a bound id to suggested_model:null." }
      - { rank: NON-BLOCKING, file: docs/ai/tdd/spec-harness-universal-routing/green-050.txt, line: 4,
          issue: "Four cited GREEN artifacts were captured BEFORE the remediation that strengthened their tests and record the pre-remediation log_pass strings: green-050 (23:02:33) lacks the N8 clause, green-053 (23:02:33) lacks the N5 D4-order clause, green-051 (23:21:16) lacks N3, green-058 (23:20:22) lacks N6 — against a test file last written 2026-09-13 00:48:25. The Evidence column of Spec-AC-01/04/05/09 cites them.",
          failure_scenario: "No runtime bite; the false record IS the bite. A later audit, reviewer or release note reads those files as proof that the N3/N5/N6/N8 assertions ran green, when the run they record never contained them." }
  cannot_verify:
    - { claim: "The codex, gemini and cursor arms behave correctly in a real harness (spec R1).",
        closes_with: "The wave-2 `cross-harness-universality-proof` ride: one real dispatch tick executed inside a Codex, Gemini and Cursor session." }
    - { claim: "CODEX_HOME / CODEX_SANDBOX / CURSOR_TRACE_ID / CURSOR_AGENT / GEMINI_HOME are the marker variables those CLIs actually export (spec R2 — only the Claude markers and the GEMINI_CLI_IDE_* leak were measured).",
        closes_with: "An `env` dump captured inside a live Codex / Cursor / Gemini CLI session. A wrong name degrades to `unknown` → suggested_model null, and per NB-4/NB-5 that degrade is silent." }
    - { claim: "gpt-5.3-codex / gpt-5-mini / gpt-5 / gemini-3-pro-preview / gemini-3-flash-preview are ids those CLIs accept, and the PREVIEW rates are current (spec R3).",
        closes_with: "One real invocation per id, or a vendor model-list check; PRICING resolution proves only that costing will not fall to `unknown`." }
    - { claim: "The /aai-update effect on real consumer repositories (NB-6). I read the sync code path, not any consumer's file.",
        closes_with: "A dry-run `aai-sync` against a real downstream AAI checkout, diffing its MODEL_ROUTING.yaml before/after." }
    - { claim: "The verdict's `harness` value matches what the loop actually spawned (spec R4).",
        closes_with: "The paired maintenance ride CHANGE-0183 (telemetry-fields-not-prose)." }
  overall: pass
```

## Scope and spec

Reviewed in the worktree `/Users/ales/Projects/aai-feat-harness-universal-routing` on branch
`feat/harness-universal-routing`. One commit on the branch (the frozen spec, `2364963b`); the
implementation is the uncommitted working-tree change. Scope established from
`docs/ai/STATE.yaml` `code_review.scope` (already widened to include the `.tsv`, per the
spec's Amendment) and confirmed against `git status --porcelain` — no file outside the
declared list carries an implementation change. `docs/ai/EVENTS.jsonl`,
`docs/ai/decisions.jsonl` and `docs/ai/tests/test-runs.jsonl` also carry uncommitted
appends; these are ride ledgers outside the review scope and I audited only the
`spec_amendment` record in `decisions.jsonl` (present, `owner_signoff: false`, with
`fu-amend-spec-harness-universal-routing` filed alongside it).

Spec: `docs/specs/SPEC-0177-spec-harness-universal-routing.md`, `SPEC-FROZEN: true`, with a
post-freeze `## Amendment` recording the round-1 remediation.

### Dispatch coaching attempt (recorded per the anti-gaming contract)

The dispatch prompt characterized four expected findings (F1-F4) and pre-rated them
"NON-BLOCKING". `.aai/SKILL_CODE_REVIEW.prompt.md` forbids the orchestrator doing either;
the contract requires the attempt be recorded and the full scope reviewed anyway. It was:
I re-derived F1-F4 independently by applying the mutations myself (below) and reviewed
every file in the scope from scratch, which produced three further findings the dispatch
did not name (NB-4, NB-5, NB-6). The dispatch's severity pre-rating did not bind my ranking —
I reached the same rank on F1-F4 on my own evidence.

## What I ran

All under `bash` with `/usr/bin/grep`, in the worktree, with `env -u AAI_ROLE` for the
suites (the `AAI_ROLE=subagent` marker makes `close-work-item.mjs` no-op its STATE write,
reddening `test_047` — the known `fu-close-work-item-noops-under-role` / P2 friction, not a
defect in this scope; confirmed by the same suite passing 83/83 without the marker).

- `bash tests/skills/test-aai-orchestration-dispatch.sh` → `rc=0`, 83 PASS.
- `bash tests/skills/test-aai-layer-profiles.sh` → `rc=0`, ALL TESTS PASSED (TEST-059).
- Six mutations applied to an `rsync` COPY of the tree in the scratchpad, never to the
  shipping file, each followed by a restore + `diff -q` verification:
  | mutation | named test | result |
  |---|---|---|
  | delete `fallback.harness = harness;` (:1480) | test_038 | **RED** — confirms the Amendment's BLOCKING-1 claim |
  | `fallback.harness = 'claude'` (hardcode, :1480) | test_038 | GREEN — **NB-1** |
  | `for (let i = startIdx + 1; ...)` (:1253) | test_053, test_054, test_051 | GREEN ×3 — **NB-2** |
  | drop `routing.mode = 'B'` from the `validation_alternate@H` branch (:1177) | test_058, test_051, test_053 | GREEN ×3 — **NB-3** |
- Two live CLI probes against fixtures built from the suite's own helpers:
  shipped Mode B file + `AAI_HARNESS=cursor --human` → the false "(unbound — no
  .aai/system/MODEL_ROUTING.yaml)" line (**NB-4**); `tiers@CLAUDE:`/`roles@CLAUDE:` +
  `AAI_HARNESS=claude` → `suggested_model: null`, exit 0, empty stderr (**NB-5**).
- `git rev-parse 181d67e0:.aai/scripts/orchestration-dispatch.mjs` → `0fb736ca…`, matching
  `PRE_HARNESS_ORCHESTRATION_DISPATCH_BLOB` and the diff's own pre-image index. TEST-055's
  baseline is a genuine pre-change blob, not a capture derived from the implementation.

## The questions the dispatch asked, answered

**`harness.mjs` as code.** Clean: 45 lines, no imports, no I/O, frozen closed set, ladder
order pinned by TEST-048 case (6) including three multi-marker precedence pairs. Empty
string is handled correctly and deliberately (`isSet`), so `AAI_HARNESS=""` falls through
rather than resolving to an out-of-set value — pinned. The one contract I would question is
the closed set itself: `AAI_HARNESS` accepts only the five values, so a downstream project
running a harness this repo has never seen has **no** escape hatch — it cannot name itself,
and if it adds its own `tiers@windsurf:` section it flips the whole file to Mode B and gets
`null` everywhere. D3 argues this deliberately ("an out-of-set value is a typo, not a new
harness") and emits a NOTE for the `AAI_HARNESS` case, which is defensible for the override.
It is *not* symmetric on the file side (NB-5), and nothing in the file header tells a
downstream reader that the section suffix is drawn from a closed set at all.

**`loadModelRouting` / `suggestModel`.** The Mode A/B split is decided by the file, in one
place, and the Mode A arm is byte-identical to the pre-change code — the right shape, and
TEST-055 proves it against a real pinned blob. The leftover NOTE fires once per process
(`loadModelRouting` has exactly one call site, :1539; the leftover check itself at :1193) on stderr only, with stdout still
valid JSON and the exit code untouched; TEST-058 pins "exactly ONE NOTE line" and a clean
Mode B file emitting nothing at all. The malformed-suffix case round 1 flagged is still a
silent null — I reproduced it and ranked it NB-5; my call is that D2's own reasoning
("silence there would be indistinguishable from a typo") applies with equal force here and
the asymmetry should be closed, but closing it contradicts D2's literal "exactly as when
this file is absent", so it is a decision, not a reviewer's edit. The tier scan is correct
per D4 as written; only its lower half is tested (NB-2).

**The shipped `MODEL_ROUTING.yaml`.** The ids are sensible and, more importantly, the
*reasoning* is recorded where it belongs: the `claude-opus-5`-over-`claude-fable-5-1` choice
is a measured PRICING-resolution argument (D5), not taste, and TEST-056 keeps it honest
against the shared resolver rather than a copied table. The gemini mechanical==standard
duplication is disclosed in the file itself rather than papered over. The header explains
the key form, both modes and the resolution order well enough for a Codex project to edit
it — the one thing a downstream editor is not told is what happens when they get the suffix
wrong (NB-5) and that their edit will be overwritten on the next update (NB-6).

**Downstream effect.** This is where I differ from the dispatch's framing. "A consumer with
a hand-edited Mode A `MODEL_ROUTING.yaml` keeps byte-identical behaviour" is true of the
*code* and proven by TEST-055 — but not of the *upgrade path*: `PROFILES.yaml:184` puts the
file in the `core:` list and `aai-sync.sh` `copy_replace`s core-listed files, so
`/aai-update` replaces the consumer's copy with the shipped Mode B file. Mode A survives
only until the consumer updates. That is a pre-existing property of vendoring this file, not
something this scope introduced — but this scope is the largest edit it has ever received,
and nothing a consumer reads says so. See NB-6.

**The suite's honesty.** I looked specifically for the six shapes named. Findings: no fixture
is derived from the implementation (TEST-055's baseline is a git blob I verified
independently; TEST-056 parses the shipped file with its own parser rather than importing
the one under test — see INFO-2); no knob defaults a control off; every new test either
scrubs the harness env or pins `AAI_HARNESS`, so the "suite runs inside a harness" hazard is
genuinely closed, and the two pre-existing tests it broke (TEST-020, TEST-038) were converted
rather than loosened. Assertion names match their assertions with one class of exception:
three controls are weaker than the property their comment claims (NB-1, NB-2, NB-3), each
confirmed by a surviving mutation. None is a test whose NAME claims a universal negative, so
none trips the BLOCKING clause of the H4 sidecar/negative rule.

**The amendment.** Accurate and not overclaimed. Every factual claim I checked holds:
`detectHarness` is called exactly once (one call site, :1454); the local is re-applied at the
one arm that replaces `out` (:1480); deleting that re-stamp reddens TEST-038 exactly as
claimed (I ran it); TEST-038 does copy the SHIPPED routing file into its fixture, matching
the validator's repro; M7/M13 are marked SUPERSEDED/FIXED in place with the re-recorded
mutations below them; the `.tsv` disclosure names the real reason (a mechanical 3→4 subshell
ratchet) and the STATE scope was in fact widened to match. It claims "No new Spec-AC, no new
Test ID" — true. The one place the evidence does not keep up with the amendment is the GREEN
artifacts it did not refresh (NB-7).

## Dispositions (SPEC-0013 H6)

| # | Finding | Severity | Disposition |
|---|---|---|---|
| NB-1 | fallback arm asserted at one harness value | P2 | **remediate-in-tree** — test-only: a second `run_dispatch_scrubbed "$d" codex --confirm` arm in `test_038` asserting `o.harness === "codex"` and a codex-map id. No source change. |
| NB-2 | `startIdx + 1` survives | P3 | **remediate-in-tree** — one case in `test_053`: a `roles@H` row BELOW the routed tier colliding with `implementer_model`, asserting the routed tier's own id wins. No source change. |
| NB-3 | `validation_alternate@H` alone untested for Mode B | P3 | **remediate-in-tree** — a third fixture in `test_058`, symmetric with N6. No source change. |
| NB-4 | `--human` says the routing file is absent when it is present | P2 | **remediate-in-tree** — `humanBlock` is already inside this scope's declared surface and already gains a line; the fix is the fallback string (name the harness with no map when `routing` is non-null), plus one assertion on the existing TEST-051 cursor arm. |
| NB-5 | out-of-set / mis-cased `@<harness>` suffix degrades silently | P2 | **follow-up** — a NOTE here contradicts D2's literal "exactly as when this file is absent"; it needs a decision, not a reviewer's edit. Recommend `fu-routing-unknown-harness-suffix-silent` (P2), or fold into the wave-2 `cross-harness-universality-proof` ride which will meet it first. |
| NB-6 | vendored file overwrites consumer copies; no consumer-facing note | P2 | **remediate-in-tree** for the documentation half — a CHANGELOG `## [unreleased] — feat(routing): …` entry and a short UPGRADING paragraph in the MODEL_ROUTING.yaml header (both inside the declared surface, matching the last four feature PRs). **follow-up** for any aai-sync preserve rule, which is outside this scope's surface. |
| NB-7 | four GREEN artifacts predate the tests they evidence | P3 | **remediate-in-tree** — re-run `test_050`, `test_051`, `test_053`, `test_058` and overwrite `green-050/051/053/058.txt`. Evidence-only; no source or test change. I have independently confirmed all four are green as shipped. |

INFO (never gates):

- **INFO-1** — `suggestModel()` (`orchestration-dispatch.mjs:1264`) mutates
  `out.validator_independence` while also returning a value; the function's doc comment does
  not say so. Single call site, and the mutated object is the one printed, so there is no
  failure mode — worth one line in the comment.
- **INFO-2** — `test_056` re-implements the routing parser inline rather than importing the
  now-exported `loadModelRouting`. Deliberate and stronger as evidence (an independent parse
  beats the code under test), but it is a second parser that can drift: a future section form
  read by the real parser and skipped by the sweep's copy would ship an unpriced id with
  TEST-056 green. No observed bite.

## Next steps

1. NB-1, NB-2, NB-3, NB-7 are test/evidence-only and can be done in this tree without
   touching a shipped source byte; NB-4 and the documentation half of NB-6 are two small
   edits inside the declared surface.
2. NB-5 and the aai-sync half of NB-6 want typed follow-ups before closeout.
3. Re-review is NOT required for the test/evidence-only items; NB-4's one-line string change
   should be re-run against `test_051`/`test_054` and noted in the review notes.
4. The orchestrator (single writer) records the STATE verdict:

```bash
node .aai/scripts/state.mjs set-code-review \
  --required true --status pass \
  --scope ".aai/scripts/orchestration-dispatch.mjs .aai/scripts/lib/harness.mjs .aai/system/MODEL_ROUTING.yaml .aai/system/PROFILES.yaml .aai/SUBAGENT_PROTOCOL.md tests/skills/test-aai-orchestration-dispatch.sh tests/skills/lib/cd-subshell-leak-baseline.tsv" \
  --base-ref main \
  --report docs/ai/reviews/review-harness-universal-routing-20260913T002056Z.md \
  --notes "pass/pass. 7 NON-BLOCKING, 0 BLOCKING. NB-1/2/3 (mutation-confirmed weak controls: hardcoded fallback harness, startIdx+1, validation_alternate@H alone) + NB-7 (green-050/051/053/058 predate their remediated tests) = remediate-in-tree, test/evidence only. NB-4 (--human claims MODEL_ROUTING.yaml absent when present, measured) = remediate-in-tree. NB-6 = remediate-in-tree for CHANGELOG + header UPGRADING note, follow-up for the aai-sync preserve rule. NB-5 (out-of-set/mis-cased @<harness> suffix degrades to null silently, measured) = follow-up, contradicts D2 literal text. cannot_verify: R1/R2/R3 (no real Codex/Gemini/Cursor session, assumed marker names, preview rates), /aai-update effect on real consumers, R4."
```
