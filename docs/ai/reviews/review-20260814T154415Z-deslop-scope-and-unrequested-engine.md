# Code Review — deslop-scope-and-unrequested-engine

```yaml
review:
  scope: >-
    working tree (uncommitted, 25 paths) — .aai/scripts/deslop-unrequested.mjs,
    .aai/SKILL_DESLOP.prompt.md, .aai/AGENTS.md, .aai/system/PROFILES.yaml,
    .claude|.codex|.gemini|.agents/skills/aai-deslop/SKILL.md, SKILLS.md,
    docs/USER_GUIDE.md, docs/SKILL_CATALOG.html, docs/skill-catalog-data.json,
    tests/skills/test-aai-deslop.sh, tests/skills/suite-map.yaml,
    tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh,
    tests/skills/test-aai-spec-lint.sh, CHANGELOG.md, docs/INDEX.md
  spec: docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "deslop-unrequested.mjs:48-72 parseArgs/usageExit; TEST-001, TEST-009" }
      - { ac: Spec-AC-02, call: compliant, citation: "deslop-unrequested.mjs:514-558 scanDiff; TEST-002 (range+dirty caveat = round-3 F17, outside this AC's WHEN)" }
      - { ac: Spec-AC-03, call: compliant, citation: "deslop-unrequested.mjs:240-349 extractors + 475-486 matchAndSplit; TEST-003, TEST-015 (M-1/M-2 mutation-proven r3)" }
      - { ac: Spec-AC-04, call: compliant, citation: "deslop-unrequested.mjs:164-205; TEST-004, TEST-010; live run corpus=132, excluded 0/0/0/0/0" }
      - { ac: Spec-AC-05, call: compliant, citation: "no fs write call exists in the engine (grep: only readFileSync/readdirSync); TEST-005" }
      - { ac: Spec-AC-06, call: compliant, citation: "deslop-unrequested.mjs:50,650 — the only process.exit calls are 2 and 0; TEST-006, TEST-016" }
      - { ac: Spec-AC-07, call: compliant, citation: "deslop-unrequested.mjs:563; TEST-007 — DEVIATION: the note also fires when the diff is non-empty but touches no scanned path (finding B2)" }
      - { ac: Spec-AC-08, call: compliant, citation: "deslop-unrequested.mjs:577-583 buildLimits, emitted by both renderers (607-610, 636); TEST-008" }
      - { ac: Spec-AC-09, call: compliant, citation: "SKILL_DESLOP.prompt.md 79 lines / 4052 B; rule at :70-72 names the scope it binds; TEST-009, TEST-011" }
      - { ac: Spec-AC-10, call: compliant, citation: "all 7 surfaces re-read here; TEST-014 — see NB-4 on the '(default)' wording they all carry" }
      - { ac: Spec-AC-11, call: compliant, citation: "PROFILES.yaml:225; suite-map.yaml:114-122; prompt-diet-ledger.sh:164 G=1140, pin -4122; TEST-012, TEST-013" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/SKILL_DESLOP.prompt.md, line: 46,
          issue: "The suppressed count is called a 'false-negative floor' (a lower bound). It is at most an upper bound on suppression-mechanism false negatives; CHANGELOG.md:33 calls the same number a 'ceiling' and spec D5 calls it an 'upper bound'. Two shipped surfaces of one scope assert opposite bounds on one number.",
          failure_scenario: "Operator runs --all, sees 'Suppressed this run: 750'. The agent relays prompt line 46 verbatim: at least 750 unrequested symbols were missed. The true statement is the inverse — at most 750 suppressions could be prose coincidence, and most are correct suppressions. The operator discards a usable 390-row list as unusable, or files an emergency follow-up against a detector that is working." }
      - { rank: BLOCKING, file: .aai/scripts/deslop-unrequested.mjs, line: 526,
          issue: "emptyDiff is defined as scannedFiles.length === 0 ('the diff touched no path inside .aai/scripts or .aai/system'), but line 563 reports it as the literal 'NOTE: empty diff'. The engine asserts a fact about the diff that it never measured.",
          failure_scenario: "Probe B (reproduced here): fresh repo on main, one commit, then `src/app.mjs` added with `export function brandNew(){}` and staged. `node deslop-unrequested.mjs --diff` prints 'NOTE: empty diff — rerun with --all to scan accumulated surface.' at exit 0. AAI is vendored into projects whose code is not under .aai/, so this is the DEFAULT class-4 result for essentially every downstream scope: the agent is told the diff is empty when it has changed files, and per prompt lines 23-26 it then offers --all, which scans the AAI framework rather than the user's change." }
      - { rank: NON-BLOCKING, file: .aai/scripts/deslop-unrequested.mjs, line: 381,
          issue: "tryGit swallows every git failure (stderr to /dev/null, catch-all) and every caller degrades to 'working tree' with no note. A missing git binary, a non-repository cwd and a genuinely clean tree are indistinguishable in the output. Constitution art. 4.",
          failure_scenario: "Probe A (reproduced here): `--diff` run in a non-git directory prints 'Diff input: working tree' + 'NOTE: empty diff' + 'Candidates: 0' at exit 0. Every git call failed; the report reads as a clean scan." }
      - { rank: NON-BLOCKING, file: .aai/scripts/deslop-unrequested.mjs, line: 311,
          issue: "extractCliFlags matches every /--[a-z][a-z0-9-]*/ token in a file and labels it kind 'cli-flag'. On the real tree 30 of 139 cli-flag candidates are CSS custom properties (--accent, --bg, --fg, --muted, --line, --card-bg in generate-docs-hub.mjs:200-201 and generate-factory-report.mjs:687) and 35 are flags this repo passes TO external tools (--error-unmatch, --exclude-standard, --others, --git-common-dir, --left-right...). ~47% of the kind, ~17% of all 390 candidates, carry a kind label that is factually wrong — these tokens are not CLI surface of this repo at all.",
          failure_scenario: "An operator triaging the --all list per the class-4 action ('Remove; file an intake note if genuinely valuable') deletes `--accent` from generate-docs-hub.mjs's :root block believing it is an unrequested CLI flag, silently breaking the docs-hub dark theme. No LIMITS sentence warns that the cli-flag kind includes non-flags." }
      - { rank: NON-BLOCKING, file: .aai/scripts/deslop-unrequested.mjs, line: 44,
          issue: "NOT_SCANNED_NOTE says 'not scanned: tests/**, docs/**, agent wrapper trees, anything outside .aai/', implying everything INSIDE .aai/ is scanned. collectSurfaceFiles (355-369) covers only .aai/scripts/**.{mjs,sh,ps1} and .aai/system/*.yaml — .aai/*.prompt.md, .aai/workflow/**, .aai/templates/**, .aai/system/*.md and every non-yaml file under .aai/system are silently out of scope.",
          failure_scenario: "An operator reads 'Candidates: 390' plus that note and concludes the .aai/ tree has been swept for unrequested surface. The prompt corpus and workflow surface — the largest part of .aai/ — were never looked at, and nothing in the output says so." }
      - { rank: NON-BLOCKING, file: .aai/SKILL_DESLOP.prompt.md, line: 15,
          issue: "Line 15 labels --diff '(default)'; line 21 says 'never assume --diff by default'. The same contradiction is propagated to all five companion description surfaces (.aai/AGENTS.md:115, SKILLS.md:45, docs/USER_GUIDE.md:707+721, the four wrapper SKILL.md files). The engine itself has NO default — parseArgs:69 exits 2 on a missing scope.",
          failure_scenario: "Spec D4 layer 2 exists so 'ask' cannot decay into 'assume'. An agent invoked as bare `/aai-deslop` reads '(default)' first, runs `--diff`, and never reaches the mechanical exit-2 teeth of layer 1 — which only bite on a flagless engine invocation the agent no longer makes. The ask-and-stop rule is defeated by the file that contains it." }
      - { rank: NON-BLOCKING, file: .aai/scripts/deslop-unrequested.mjs, line: 514,
          issue: "scanDiff({ base, json }) destructures `json` and never uses it; rendering is chosen at the entry point from args.json (line 649). Dead parameter.",
          failure_scenario: "No runtime failure. Recorded because it is a class-3/class-4 hit inside the class-4 detector — the next reader assumes scanDiff varies its behavior by output format and looks for a branch that does not exist." }
  cannot_verify:
    - { claim: "That the 390 --all candidates contain no genuinely unrequested surface worth removing.",
        closes_with: "A human triage pass over the recorded baseline docs/ai/tdd/deslop-real-repo-all-baseline-20260814.json, classifying each row. Out of this scope by the spec's own residual-risk note; I sampled every kind but classified only the cli-flag kind exhaustively." }
    - { claim: "Behavior of the engine on Windows/PowerShell paths (toPosix, the .ps1 extractor, git output line endings).",
        closes_with: "A run of tests/skills/test-aai-deslop.sh on a Windows runner. Every probe here was darwin." }
    - { claim: "That the regenerated docs/SKILL_CATALOG.html and docs/skill-catalog-data.json match what generate-docs-hub.mjs produces on a clean checkout.",
        closes_with: "TEST-014 asserts it and validation round 3 re-ran it; I did not re-run the generator here to avoid touching tracked artifacts mid-review." }
    - { claim: "Round-3 F17 (range-mode/dirty-worktree coordinate mismatch) is still latent rather than active.",
        closes_with: "Re-running F17's two-command repro after the scope is committed to a feature branch. It is latent today only because the scope is uncommitted on main." }
  overall: fail
```

## Scope and spec

Reviewed the uncommitted working tree (`git status --porcelain`, 25 paths) against
the frozen spec `docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md`
(`SPEC-FROZEN: true`, ceremony 2). Diff established with `git diff` (nothing staged).

Per the anti-gaming contract, I did NOT re-run the 79-suite sweep — three validation
rounds own "does it work" and round 3 is a verified PASS. This pass asks the questions
validation does not: is the output honest, is the complexity earned, will it age.

**Coaching attempt recorded (anti-gaming clause):** the dispatch pre-scoped six areas
to "review hardest on" and pre-characterized one expected finding shape ("does any
output line read more confident than the mechanism justifies"). The full scope was
reviewed anyway; two of the seven findings below (NB-5, NB-6) fall outside the
dispatch's six areas, and one dispatch hypothesis was checked and **refuted** (see
"What is sound", item 3).

## What is sound

Stating this first, because most of this scope is good and a finding list read alone
would misrepresent it.

1. **Read-only is by construction, not by convention.** The engine imports `fs` and
   calls only `readFileSync` / `readdirSync`. There is no write path to remove. The
   sha256-manifest proof in TEST-005 is belt-and-braces over a structural property.
2. **The exit contract is genuinely fail-fast where it matters.** `parseArgs` returns
   `null` for no scope, both scopes, an unknown flag, a dangling `--base` value, and
   `--base` without `--diff`; every one lands on `usageExit()` at line 48 before a
   single `fs` or `git` call. There are exactly two `process.exit` sites in the file
   (2 and 0). Verified by reading, not only by TEST-006's grep.
3. **The `--all` justification still holds — checked, not assumed.** Nothing
   auto-invokes deslop. `tests/skills/test-aai-advisory-skills.sh:191-222` pins six
   gate/dispatch surfaces (three ORCHESTRATION prompts, two orchestration scripts,
   WORKFLOW.md) against any reference to the skill, and a repo-wide grep for `deslop`
   outside its own surfaces returns only test files, research docs and this scope's
   own artifacts. `.aai/AGENTS.md:115` is a menu line, not a dispatch. The wide scope
   remains operator-initiated.
4. **Complexity is earned.** Five extractor kinds are D3's closed list and all five
   fire on the real tree. The `matchLine` vs `line` split looks like the kind of
   speculative refinement art. 2 forbids, but it is not: it is the round-2 F11 fix,
   and round 3 mutation-proved it in both directions (M-1 false-negative, M-2
   false-positive). The suppressed counter is the honesty mechanism, not decoration.
   The only unearned line in the file is the dead `json` parameter (NB-5).
5. **The LIMITS block in the engine itself is carefully worded and honest.** Line 580
   scopes its claim to the suppression mechanism ("a symbol named ANYWHERE in a
   requirement document ... is suppressed. Suppressed this run: N") rather than
   claiming a bound on total false negatives, and line 579 separately discloses
   pattern-extraction blindness. The dishonesty in this scope is in the *paraphrases*
   around that block (B1), not in the block.
6. **Governance companions are real and internally consistent.** G=1140 (1119 prompt +
   21 AGENTS.md), pin -5262 -> -4122, PROFILES `extended` entry, suite-map row, full
   `main()` registration of TEST-001..016.

## The honesty question (dispatch focus 1)

The dispatch asked whether the LIMITS block overstates what the suppressed count means.
The engine's own wording does not. **Its paraphrases do, in both directions:**

| Surface | Wording for the same number | Correct? |
|---|---|---|
| `deslop-unrequested.mjs:580` | "a symbol named ANYWHERE ... is suppressed. Suppressed this run: N" | Yes — scoped to the mechanism, asserts no bound |
| `CHANGELOG.md:33` | "the detector's own false-negative **ceiling**" | Only for the suppression mechanism; silently excludes unextracted symbols and the unscanned surface |
| spec D5 (frozen) | "the measured **upper bound** on this run's false negatives" | Overstated for the same reason |
| `SKILL_DESLOP.prompt.md:46` | "a false-negative **floor**" | **No — inverted.** A floor asserts at least N were missed |

The prompt is the artifact an agent loads at run time, so the inverted one is the one
that reaches the operator. That is B1.

The ceiling/upper-bound framing is also wrong-but-in-the-safe-direction: total false
negatives are *not* bounded by the suppressed count, because symbols the extractors
never see (dynamic exports, computed names) and the entire unscanned part of `.aai/`
(NB-3) contribute false negatives outside it. The engine's own line 580 is the honest
formulation; the fix for B1 is to make the prompt say what line 580 says, and the
cheap hardening for CHANGELOG/spec is to say "upper bound on false negatives *from
prose suppression*" rather than a bound on false negatives.

## The 390 / 750 question (dispatch focus 2)

Ran `node .aai/scripts/deslop-unrequested.mjs --all --json`: 390 candidates, 750
suppressed, corpus 132, files 112 — reproducing round 3's independently-derived
figures exactly.

Composition:

| kind | candidates | judgment on a sample |
|---|---|---|
| cli-flag | 139 | **30 are CSS custom properties, 35 are flags passed to git/gh/node.** Not surface of this repo at all (NB-2). Of the remaining 74, most are real AAI flags |
| mjs-export | 128 | Internal helpers (`collisionSuffix`, `numberWidthFromBasename`, `reservationRef`, `maskCredentials`). Every one exists because another module imports it |
| sh-func | 64 | Internal shell helpers (`add_unique`, `has_glob`, `first_glob`, `json_has_package_dep`) |
| ps1-func | 53 | Same (`Resolve-RepoRoot`, `Ensure-Directory`, `Get-ProcessSnapshot`) |
| yaml-key | 6 | The signal kind — 6 candidates out of a much larger extracted set, i.e. suppression actually discriminated |

**Plain answer: as shipped, `--all` is a low-precision inventory, not a triage
goldmine — and the yaml-key row shows why.** The detector's premise ("a symbol no
requirement document names is unrequested") only holds for surface a requirement would
plausibly name: public flags and top-level config keys. Specs in this repo name
behaviors, file paths and CLI contracts; they never enumerate internal helper
functions. So the 245 mjs-export/sh-func/ps1-func rows are not detections, they are a
restatement of "specs do not list private helpers". `yaml-key`, where a requirement
*does* plausibly name the key, produced 6 candidates — that is the kind doing real work.

This is **not** a blocking objection, for three reasons the scope itself already
anticipated: nothing is gated on the list, the spec's residual-risk section explicitly
predicted a noisy first run and deferred triage, and the LIMITS block forbids reading
it as a verdict. But it should be said plainly rather than filed under "triage owns
that call": the operator-visible value of `--all` today is concentrated in one of five
kinds, and the honest expectation to set is hours of triage for a handful of real hits.

NB-2 is separable from that judgment and *is* a defect: a kind label that says
`cli-flag` about a CSS custom property is a false statement, not low precision.

## Deviations from the frozen spec

- **Spec-AC-07 / D4 (B2).** The spec's EMPTY DIFF clause is written for an empty diff.
  The implementation fires the same note whenever the diff touches no *scanned* path.
  Reasonable as an implementation shortcut, wrong as a report. The engine already has
  the right pattern for this elsewhere: `buildNotes` distinguishes `surfaceEmpty` for
  `--all` with a specific diagnostic (line 567-569). `--diff` needs the twin.
- **Spec Summary vs D4 (NB-4).** The frozen spec is itself inconsistent: the Summary
  says "`--diff` default", D4 says the absence of a decision must never be silently
  resolved into one. The prompt inherited both. Remediation should follow D4 (the
  designed behavior, and the one the engine implements) and treat the Summary's
  "default" as the loose one.
- Round-3 **F17** (range-mode coordinate mismatch) and **F18** (suite-map globs) are
  carried, not re-derived. I confirmed both still stand on this tree and take no
  independent position beyond round 3's.

## Warning dispositions (H6)

| # | Finding | Disposition |
|---|---|---|
| B1 | prompt "floor" wording | **remediate-in-tree** — one clause; no test change needed (TEST-009 does not pin it). Consider adding a grep arm so it cannot regress |
| B2 | "empty diff" on a non-empty diff | **remediate-in-tree** — split `emptyDiff` into `diffEmpty` and `noScannedPath`, give the second its own note, and add the missing TEST-007 arm (a diff with changed files, none under the scanned globs) |
| NB-1 | swallowed git failure | **remediate-in-tree** — one `git rev-parse --git-dir` probe and one NOTE; same shape as the existing `surfaceEmpty` degrade |
| NB-2 | cli-flag kind mislabels CSS vars and external-tool flags | **promote-to-follow-up-ref** — `fu-deslop-cliflag-kind-precision`, P2. Fix is a design call (rename the kind vs exclude `--x:` / `var(--x)` contexts) and the spec's NO STOPLIST decision is adjacent |
| NB-3 | NOT_SCANNED_NOTE overstates coverage | **remediate-in-tree** — restate as the positive glob list |
| NB-4 | "(default)" contradicts ask-and-stop across 6 surfaces | **remediate-in-tree** — drop "(default)" from the prompt and the five companion surfaces; the wording change is inside the already-credited ledger delta or shrinks it |
| NB-5 | dead `json` param | **remediate-in-tree** — delete one identifier |

## Next steps

1. Fix B1 and B2 (both small, both in the reporting layer). B2 wants the one TEST-007
   arm that does not exist today: a non-empty diff containing no scanned path.
2. Fix NB-1, NB-3, NB-4, NB-5 in the same pass — together they are under twenty lines.
3. File `fu-deslop-cliflag-kind-precision` (NB-2) and, per round 3's own suggestion,
   `fu-deslop-range-mode-coordinate-mismatch` (F17) and the F18 glob widening.
4. Re-review: same single pass, re-walk the AC table, refresh cannot_verify.

## Declared deviation

`.aai/SUBAGENT_CONTRACT.md` forbids a dispatched subagent from writing
`docs/ai/STATE.yaml`, while this dispatch explicitly instructs the verdict to be
recorded via `state.mjs set-code-review`. `.aai/SKILL_CODE_REVIEW.prompt.md` permits
the STATE write "when the dispatch grants it (single-agent mode or an explicit
instruction)", which it does here. Already tracked as
`fu-subagent-state-write-contradiction` (P2, this ref). Following the dispatch and
declaring it, as validation rounds 1-3 did.
