# Code Review — deslop-scope-and-unrequested-engine (round 2, post-amendment)

```yaml
review:
  scope: >-
    working tree (uncommitted, 27 paths) — .aai/scripts/deslop-unrequested.mjs,
    .aai/SKILL_DESLOP.prompt.md, .aai/AGENTS.md, .aai/system/PROFILES.yaml,
    .claude|.codex|.gemini|.agents/skills/aai-deslop/SKILL.md, SKILLS.md,
    docs/USER_GUIDE.md, docs/SKILL_CATALOG.html, docs/skill-catalog-data.json,
    tests/skills/test-aai-deslop.sh, tests/skills/suite-map.yaml,
    tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh,
    tests/skills/test-aai-spec-lint.sh, CHANGELOG.md, docs/INDEX.md,
    docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md,
    docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md,
    plus generated/append-only ledgers (EVENTS, decisions, overview, test-runs)
  spec: docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "deslop-unrequested.mjs:82-101 parseArgs + 77-80 usageExit (no fs/git call before it); prompt :20-21 ask-and-stop; TEST-001, TEST-009" }
      - { ac: Spec-AC-02, call: compliant, citation: "deslop-unrequested.mjs:810-875 scanDiff, added.has(c.line) at :853; TEST-002" }
      - { ac: Spec-AC-03, call: compliant, citation: "two kinds only at :622-632 extractFileCandidates; one shared matchAndSplit :771-782; TEST-003, TEST-015" }
      - { ac: Spec-AC-04, call: compliant, citation: "resolveAllCorpus :209-234 / resolveDiffCorpus :193-207; live run corpus=132, excluded 0/0/0/0/0; TEST-004, TEST-010" }
      - { ac: Spec-AC-05, call: compliant, citation: "engine calls only readFileSync/readdirSync (no write path exists); TEST-005" }
      - { ac: Spec-AC-06, call: compliant, citation: "only process.exit sites are :79 (2) and :998 (0); TEST-006 source-proof grep" }
      - { ac: Spec-AC-07, call: compliant, citation: "buildNotes :884-888 now separates emptyDiff / noScannedPath / git-unavailable; TEST-007 (3 arms), TEST-017" }
      - { ac: Spec-AC-08, call: compliant, citation: "buildLimits :902-931 emits 4 unconditional limits in both renderers (:955-958, :984); 4th line carries no digit; TEST-008" }
      - { ac: Spec-AC-09, call: compliant, citation: "prompt 79 lines / 4100 B (<=90); scope-bound rule at :70-72; TEST-009, TEST-011" }
      - { ac: Spec-AC-10, call: compliant, citation: "all 7 surfaces name both scopes, none says diff-only; TEST-014 — but see NB-1, they now over-claim in the other direction" }
      - { ac: Spec-AC-11, call: compliant, citation: "PROFILES.yaml:225; suite-map.yaml:114-122; ledger entry G=1210, pin -4052 == independent re-sum; TEST-012, TEST-013" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/SKILL_DESLOP.prompt.md, line: 17,
          issue: "Eight shipped surfaces say --all covers 'the whole .aai/ tree' / 'the whole accumulated .aai/ surface'. The engine's own NOT_SCANNED_NOTE contradicts them: only .aai/scripts/**.{mjs,sh,ps1} and .aai/system/*.yaml are scanned — 112 of 223 files under .aai/. This is round-4 NB-3 fixed in the engine and left standing in every description surface.",
          failure_scenario: "Operator picks the skill from the wrapper description ('runs the class-4 unrequested-surface check across the whole accumulated .aai/ tree'), runs it, gets 68 candidates and reports .aai/ swept for unrequested surface. The entire prompt corpus (.aai/*.prompt.md), .aai/workflow/**, .aai/templates/** and .aai/system/*.md — 101 markdown files — were never looked at. Same wording is in CHANGELOG.md:22, which ships to users who never run the tool at all." }
      - { rank: NON-BLOCKING, file: .aai/scripts/deslop-unrequested.mjs, line: 209,
          issue: "The --all requirement corpus is docs/specs/** with type: spec only. This repo also records flag requirements in docs/issues/** (intakes) and docs/rfc/**, and nothing in the header, notes or LIMITS says those do not count. Measured on the live run: 15 of the 54 distinct cli-flag symbols reported (28%) appear as whole words in docs/issues|rfc|requirements — e.g. --worktree-guard and --worktree-baseline (docs/issues/CHANGE-0125-adopt-v2-planning.md:56) and --pr-config (docs/issues/CHANGE-0096-github-no-bots-hardening.md:38), all three explicitly requested there. D2 argues the intake MUST be in the --diff corpus because 'dropping the intake would manufacture findings for flags a human explicitly requested one document away'; --all does exactly that, at scale, and the reasoning is not applied.",
          failure_scenario: "Operator triages the --all list per the class-4 action ('Remove; file an intake note if genuinely valuable'), reaches --worktree-guard, finds no spec naming it, and removes an opt-in Planning gate that CHANGE-0125 asked for by name. Nothing in the output would have told them to look in docs/issues/." }
      - { rank: NON-BLOCKING, file: docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md, line: 112,
          issue: "The self-suppression fix (moving the adjudication table into the intake) is correct in direction but contingent on exactly the corpus gap NB-2 describes, and nothing records the coupling. Widening the --all corpus to docs/issues/** — the natural fix for NB-2, and the shape D2 already endorses for --diff — silently re-suppresses all 10 rows.",
          failure_scenario: "A later scope widens resolveAllCorpus to include type: change intakes (a one-line change with an obvious rationale). The live count drops from 68 to 58 with no note anywhere, and the 10 adjudicated indefensible rows disappear from the detector output for the second time, for the same reason, undetected." }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 46,
          issue: "The changelog entry cites docs/ai/reports/deslop-candidate-adjudication-20260815.md as the home of the 60/10 adjudication. .gitignore:21 excludes docs/ai/reports/** — the file is machine-local and will not exist for any reader of the released changelog. The tracked summary now lives in docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md and is not cited.",
          failure_scenario: "A user reading the release notes wants the evidence behind '60 defensible, 10 indefensible', follows the only cited path, and finds nothing in the repo. The claim becomes unverifiable to everyone except the machine that produced it." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md, line: 390,
          issue: "D5 justifies the 14% indefensible residual as 'docs/TECHNOLOGY.md binds this engine to Node stdlib with zero dependencies — a structural limit, not a tuning gap'. Zero-dependency is the wrong constraint for most of the 10. Rows 4-10 (a printf'd cargo suggestion, a PowerShell regex pattern, an external agent CLI's own flag behind a %s placeholder) are unclassifiable because intent is not recoverable from text, which no dependency supplies. Only rows 1 and 3 (flag inside a string literal vs. flag as a call argument) are the kind of thing an AST would help with.",
          failure_scenario: "No runtime failure. It matters because it is the sentence that converts a missed acceptance bar (owner asked 100%, shipped 86%) into an unavoidable limit. Attributing it to a dependency ban invites a future reader to conclude the shortfall closes by adding a parser. The engine's own LIMITS wording — 'needs semantics, not syntax' — is the accurate formulation and should be the one in the spec." }
      - { rank: NON-BLOCKING, file: .aai/scripts/deslop-unrequested.mjs, line: 832,
          issue: "Two stale cross-references in engine comments. Line 832 explains behaviour in terms of 'the per-symbol added.has(matchLine) check'; no matchLine identifier exists anywhere in the file (the amendment removed the kinds that needed it — the code reads added.has(c.line) at :853). Line 908 says the adjudication is 'summarized in this spec's Amendment section'; it was in D3, and the 2026-08-15 pass moved it to the intake.",
          failure_scenario: "A maintainer changing the diff-scope line-matching greps for matchLine to find the check the comment describes, gets zero hits, and either concludes the comment describes removed code (and stops trusting the whole comment block) or re-adds a distinction the amendment deliberately deleted." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-deslop.sh, line: 916,
          issue: "TEST-014 runs generate-docs-hub.mjs against the REAL repository and restores docs/SKILL_CATALOG.html and docs/skill-catalog-data.json from mktemp copies at the end of the function, with no trap. Every run genuinely rewrites both tracked files (the json's generatedAt changes on each generation, which is why the comparison strips it).",
          failure_scenario: "The harness's AAI_TEST_TIMEOUT kill, a Ctrl-C, or a `return` added later between the first generator invocation and the two cp restores leaves the operator's working tree with a modified docs/skill-catalog-data.json (and possibly SKILL_CATALOG.html) plus two orphaned mktemp files. On a suite that ends up in a pre-PR sweep, that shows up as unexplained scope pollution." }
  cannot_verify:
    - { claim: "That the 58 rows validation round 6 verified row-for-row are still correct now that the corpus changed (live output is 68/400, not 58/410).",
        closes_with: "Re-running round 6's independent D2+D3 reimplementation against the current corpus. Round 6 did verify the 10 restored rows by counterfactual (its section 1 lists exactly those 10), so the delta is covered by construction, but not by a fresh row-for-row diff." }
    - { claim: "That .aai/scripts/deslop-unrequested.mjs is byte-identical to the file validation round 6 executed.",
        closes_with: "A recorded sha256 of the engine at round 6 compared with the current file. I checked behaviourally instead: the engine's output difference (58 -> 68) is fully explained by the corpus edit, and the file still contains the round-5/round-6 remediation markers. No stored hash exists to compare against." }
    - { claim: "Behaviour of the engine and the suite on Windows/PowerShell (toPosix, the .ps1 arm of maskShellNoise's backtick continuation rule, git line endings).",
        closes_with: "A run of tests/skills/test-aai-deslop.sh on a Windows runner. Every probe in this review was darwin." }
    - { claim: "That the 60 rows the adjudication calls defensible are all genuinely owned flags.",
        closes_with: "A full independent walk. I sampled 9 sites (append-event.mjs:83, check-role-output.mjs:136, docs-audit.mjs:156, loop-digest.mjs:24, orphan-sweep.mjs:50, spec-lint.mjs:101, generate-live-status.mjs:63, expert-fetch.sh:34, install-pre-commit-hook.sh:19) and every one is a real flag this repo's own code parses or prints in a live usage string. The remaining 51 are unchecked." }
  overall: pass
```

## Scope, method, and a recorded coaching attempt

Reviewed the uncommitted working tree (`git status --porcelain`, 27 paths) against the
frozen, owner-amended spec. Diff established with `git diff` (index empty).

Per the anti-gaming contract I did **not** re-run the suite or the 79-suite sweep —
validation owns that and has run six rounds, round 6 green at 79/79. I did run the
engine itself against the real tree (read-only by construction; porcelain count
unchanged before and after) because judging whether the output is worth producing
requires reading it.

**Coaching attempt recorded (anti-gaming clause).** The dispatch enumerated five
changes to judge, named four areas to "review hardest on", and asked me to scrutinise
one specific judgment call. That is characterising the expected findings. I reviewed
the full scope anyway; three of the seven findings below (NB-1, NB-4, NB-7) fall
outside the dispatch's five items, and one dispatch premise was checked and partly
**refuted** (item 5 below — the "structural limit" framing is not fully correct).

## Does the tool now do something worth doing?

**Yes — marginally but genuinely, and the honest description of it is narrower than
what ships.** Sunk cost plays no part in this; the 68-row list is a different artifact
from the 390-row one, not a smaller version of it.

Live run, this tree: **68 candidates, 400 suppressed, corpus 132, surface 112 files.**
I read every row and sampled nine sites in the source.

- **58 of 68 are real CLI flags or YAML keys this repo's own code parses** —
  `--min-age-s`, `--ps-file`, `--self-pgid` in orphan-sweep; `--lock-token`,
  `--target-version` in update-check; `--source-ts`, `--origin` in follow-ups;
  `max_prompt_bytes`, `blocked_categories` in EXPERT_REGISTRY.yaml. Those are exactly
  the contract surfaces the owner's amendment said the premise holds for. A human can
  walk this list in under an hour and every row is a legitimate question
  ("undocumented flag — document it or drop it?").
- **10 of 68 are flag-shaped text**, and all 10 of the adjudicated rows are present in
  the live output (verified row by row), so the fourth LIMITS line describes a class
  with live instances again — the "zero live instances" nuance round 6 flagged is
  resolved by the table move.
- The composition is the inverse of the pre-amendment run. Where the 390 were 63%
  internal helpers that no spec would ever name, this list is 85% contract surface.
  My previous verdict — "a low-precision inventory, not a triage goldmine" — no longer
  applies to what ships. **The amendment fixed the thing that was wrong.**

The caveat that keeps this at "marginally useful" rather than "clearly useful" is
NB-2. What the list actually means is *"a flag not literally spelled in an accepted
`docs/specs/` document"*, and 28% of it is spelled out in a `docs/issues/` intake
instead. That is a real signal-to-noise tax that the output nowhere discloses, and it
is cheap to fix with one sentence.

A second, smaller precision observation, offered as illustration rather than as a
finding: `docs-audit.mjs:154-157` passes `--total`, `--orphans`, `--drifted`, `--stale`
in one argv array to this repo's own `append-event.mjs`. Two are suppressed and two are
reported, purely because a spec's prose happened to spell two of the four. That is the
prose-suppression property working exactly as `limits[1]` documents, and it is a fair
picture of how much a single row means: not much on its own, which is why "read each
candidate before acting" is the right instruction and why nothing should ever gate on
this.

## The five changes since the last review

**1. The amendment — sound, and honestly recorded.** The `hitl_decision` at
`2026-08-15T08:14:24.000Z` exists in `docs/ai/decisions.jsonl` with actor
`ales_holubec.net`, `authority: owner`, an explicit `amends` field naming D3, an
acceptance bar, and an `origin_error` field owning that intake assumption A2 was
never questioned. The spec keeps `SPEC-FROZEN: true` and carries an Amendment section
naming the record, the measured evidence (245 of 390) and the removal-vs-flag choice
with a YAGNI rationale. This is how a frozen document should be amended.

Is the remainder a thin tool in a big tool's scaffolding? No. Two kinds is a defensible
closed set — a flag and a config key are the two things a requirement is expected to
name, and both fire on the real tree (62 cli-flag, 6 yaml-key). The scaffolding that
survives (corpus resolution, diff resolution, the LIMITS block, the suppressed counter)
is shared by both kinds and would exist for one kind alone. The one structure that
*would* have looked speculative — the `matchLine`/`line` split that the removed kinds
needed — is genuinely gone from the code; only its comment survives (NB-6).

**2. The fourth LIMITS line — honest, not a hedge.** It carries zero digits (so it
cannot go stale), it names the four concrete shapes it covers, it says what would be
needed to do better ("semantics, not syntax"), and it ends with an actionable
instruction. Refusing to print a recomputed-but-wrong number is the right call, and
the point-in-time 10-of-70 figure is still available in the spec and the intake for
anyone who wants magnitude. This does not let a known-bad output ship: it lets a known
14%-noisy output ship *with the noise named*, on a report-only surface, which is what
an advisory tool is for.

**3. Self-suppression and the D3 stoplist rule — I agree it is not blocking, and I
agree the move is a fix rather than a disguised stoplist, with one reservation.**

Not a stoplist: no per-symbol exemption entered the engine, the engine did not change
at all, the rows came *back* (58 → 68), and the suppressed total moved by exactly the
same amount in the opposite direction (410 → 400) in the operator's face. A stoplist
removes rows; this restored them.

Not an engine defect: D2 freezes "anywhere in the body text of any document in the
requirement corpus", the spec is `type: spec, status: implementing`, so its membership
is correct and the matcher behaved as specified. Validation's ruling is right.

The reservation is NB-3. Round 6 justified the move on the ground that the intake "sits
outside the `--all` corpus on three independent grounds" — but D2 argues at length that
an intake **is** a requirement document, which is why it is half the `--diff` corpus.
Both cannot be load-bearing. The move works today because of an inconsistency (NB-2),
not because of a principle, and the coupling is written down nowhere. One sentence in
the intake fixes it.

**4. The falsified V6-2 claim — the replacement text is true.** Verified from source,
not from the document: `docs-audit.mjs:152` is a literal `execFileSync('node', [...])`,
so `firstArgCommandWord` resolves `node`, the internal branch fires, and `--total` /
`--orphans` are extracted rather than excluded as external; they are absent from the
live 68, i.e. suppressed by the corpus. `--hash` (orchestration-dispatch.mjs:905) and
`--op` (spec-scope-edit.mjs:458) are the same shape. D3's new sentence claims exactly
that and nothing more. The `'node'` exception it describes is not speculative code —
five files call `execFileSync('node', …)`.

**5. The 86% framing — mostly correct, one clause overstated (NB-5).** The 10
indefensible rows are real and correctly categorised; I re-checked all 10 sites exist in
the live output. "Semantics, not syntax" is the right diagnosis. But D5 pins the
shortfall on `docs/TECHNOLOGY.md`'s zero-dependency rule, and that is not the operative
constraint for 7 of the 10 — no library tells you whether `--prompt-file` inside a
`%s`-templated agent invocation belongs to this repo. Calling it "a structural limit"
is fair; sourcing that limit to a dependency ban is a rationalisation of one clause,
and it misdirects any future attempt to close the gap.

## Complexity earned (Constitution art. 2 / art. 4)

| Structure | Earned? | Basis |
|---|---|---|
| `maskShellNoise` (57 lines) | **Yes** | Replaces the unsound bare-word heuristic V5-1 found; mutation-guarded in both directions (round 6 B/B2) |
| `commentStartIndex` | **Yes** | Mutation-guarded both ways (C/D); D's over-reach collapses the tree to 6 candidates and turns 4 arms red |
| CSS + external-tool exclusions | **Yes** | Measured 30 and 35 of the original 139; both syntactic, neither a per-flag list |
| `findCmdPassthroughWrapperNames` | **Yes** | Fires on aai-doctor.mjs's `run`; round 6 traced 5 flags it correctly excludes |
| One level of array indirection | **Yes** | Added for a specific observed miss (`--body`); the two remaining gaps are tracked (V6-4) |
| Suppressed counter | **Yes** | The honesty mechanism; the whole LIMITS block hangs on it |
| `matchLine` vs `line` | **Gone** | Correctly deleted by the amendment — only the comment survives (NB-6) |

691 code lines and 246 comment lines to produce 68 rows is a high ratio, but the
comments are doing real work (they carry the round-by-round provenance for every
exclusion rule) and none of the code is now unreachable. Nothing here is speculative.

## The advisory invariant — intact

- Prompt: 79 lines (ceiling 100, spec budget 90), `ADVISORY ONLY` at :3-4 verbatim,
  "Never present this pass as a review verdict" at :78-79.
- Engine: only nonzero exit is 2, for a usage error, before any scan. Every degrade is
  a NOTE at exit 0.
- Nothing dispatches it: `grep -rn deslop .aai/workflow/ .aai/ORCHESTRATION.prompt.md
  .aai/scripts/orchestration-dispatch.mjs` returns nothing. `test-aai-advisory-skills.sh`
  TEST-012 pins the six gate/dispatch surfaces as unwired.
- No gate-like behaviour smuggled in: `--all` never edits, and the prompt's class-4
  action still routes deletions through a human.
- `test-aai-spec-lint.sh`'s branch-diff allowlist claim "now 9 paths across 3 scopes"
  is arithmetically true (3 + 2 + 4). Its comment calls all four new paths "surfaces
  that stop claiming the pass is diff-only", which is loose — PROFILES.yaml is a
  governance entry and the engine is new — but the pin itself is correct. INFO only.

## On skipping a seventh validation round

**Your call was right.** The engine did not change; the documentation pass changed the
corpus, and the corpus is data the engine reads, not code. Round 6's counterfactual
(its section 1) already measured the exact post-move state — it lists the 10 rows that
return and reports 68/400 for precisely the tree that now ships — so the shipping
output was measured by validation even though it was not the tree validation was
looking at. The scope's own suite is 36s and green.

Two caveats worth stating rather than waving off: round 6's strongest artifact, the
from-scratch D2+D3 reimplementation that matched row-for-row, was run against the 58-row
output and not re-run against 68 (recorded in `cannot_verify`); and there is no stored
hash of the engine to make "byte-identical" mechanical rather than asserted — which is
exactly what `fu-validation-staleness-undetected` (P2, this ref) already asks for.

## Warning dispositions (H6)

| # | Finding | Disposition |
|---|---|---|
| NB-1 | "whole .aai/ tree" on 8 surfaces | **remediate-in-tree** — replace with ".aai/ scripts and system config" in the prompt, four wrappers, SKILLS.md, USER_GUIDE.md and CHANGELOG.md, then re-run `node .aai/scripts/generate-docs-hub.mjs`. TEST-014 greps only for `diff-scoped`/`current diff only`/`(default)` and for `--all`, so the wording change is safe; the regeneration is required or TEST-014's staleness arm goes red |
| NB-2 | `--all` corpus silently excludes intakes/RFCs | **remediate-in-tree** (disclosure half) — one LIMITS line: "requirement corpus for `--all` is `docs/specs/**` (`type: spec`) only; a requirement recorded in `docs/issues/**` or `docs/rfc/**` does not suppress". TEST-008 pins `limits.length === 4`, so adding a fifth line needs that arm and TEST-002/TEST-010's shape assertions updated. **promote-to-follow-up-ref** for the corpus-widening half (`fu-deslop-all-corpus-excludes-intakes`, P2), because widening it re-triggers NB-3 |
| NB-3 | self-suppression fix contingent on NB-2 | **remediate-in-tree** — one sentence in the intake's Adjudication Summary: if the `--all` corpus is ever widened to `docs/issues/**`, this table must move to a non-corpus home |
| NB-4 | CHANGELOG cites a gitignored path | **remediate-in-tree** — add the tracked pointer (`docs/issues/CHANGE-DRAFT-…`) beside the gitignored one |
| NB-5 | D5's zero-dependency attribution | **remediate-in-tree** — drop the `docs/TECHNOLOGY.md`/zero-dependency clause; the engine's own "semantics, not syntax" wording is already correct |
| NB-6 | stale `matchLine` and spec-section comment references | **remediate-in-tree** — two comment edits. This changes engine bytes, so re-run `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-deslop.sh` (36s) after |
| NB-7 | TEST-014 restores tracked catalog files without a trap | **promote-to-follow-up-ref** (`fu-test014-catalog-restore-no-trap`, P3) — or a two-line `trap … EXIT`/`RETURN` if fixed in tree |

## Next steps

1. NB-1, NB-4, NB-5 and NB-6 are text edits totalling well under thirty lines; do them
   in one pass. NB-1 requires the docs-hub regeneration, NB-6 requires the 36s suite.
2. NB-3 is one sentence and closes the only reservation on the self-suppression ruling.
3. NB-2's disclosure half is worth the TEST-008 arm update; its corpus half is a
   follow-up, not this scope.
4. NB-7 is the only one I would accept as a tracked follow-up without argument.
5. None of the seven blocks. **This is ready for the owner once the text edits land.**

## Declared deviation

`.aai/SUBAGENT_CONTRACT.md` forbids a dispatched subagent from writing
`docs/ai/STATE.yaml`, while this dispatch explicitly instructs the verdict be recorded
via `state.mjs set-code-review`. `.aai/SKILL_CODE_REVIEW.prompt.md` permits the write
"when the dispatch grants it (single-agent mode or an explicit instruction)". Already
tracked as `fu-subagent-state-write-contradiction` (P2, this ref). Following the
dispatch and declaring it, as every prior role on this ride has.

## Clock note

I did not capture the system clock at dispatch, only at 2026-08-15T11:40:01Z, partway
through. The `started_utc` reported in the result block is that first captured reading,
not the true start; the real elapsed time is longer. Recorded rather than estimated.
