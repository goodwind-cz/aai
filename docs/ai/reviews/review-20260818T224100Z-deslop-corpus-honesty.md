# Code Review — deslop-corpus-honesty

```yaml
review:
  scope: >-
    working tree vs main (83c3899), paths from STATE code_review.scope:
    .aai/scripts/deslop-unrequested.mjs,.aai/SKILL_DESLOP.prompt.md,
    tests/skills/test-aai-deslop.sh,tests/skills/lib/prompt-diet-ledger.sh,
    tests/skills/test-aai-prompt-diet.sh,
    docs/analysis/deslop-candidate-adjudication-20260815.md,
    docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md,
    docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md,
    docs/product/aai-deslop.md,docs/specs/SPEC-0136-spec-deslop-corpus-honesty.md,
    docs/issues/CHANGE-0150-deslop-corpus-honesty.md,docs/ai/decisions.jsonl,
    docs/INDEX.md,CHANGELOG.md
  spec: docs/specs/SPEC-0136-spec-deslop-corpus-honesty.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-022 green; independent probe: requirement_corpus.documents = 331, 0 paths outside dirs, dirs/types/statuses emitted as data (deslop-unrequested.mjs:1058, :1094-1097)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-023 green; independently verified --worktree-guard/--worktree-baseline/--pr-config absent from candidates and each named in CHANGE-0125 / CHANGE-0096. Evidence caveat: NB-1 below" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-024 green; docs/analysis/deslop-candidate-adjudication-20260815.md carries 10 rows + coupling note; 0 corpus documents under docs/analysis; SKILL_DESLOP.prompt.md:22-27 states the convention" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-025 green; reproduced the --diff-worded note verbatim on an independent fixture (dangling symlink), exit 0" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "TEST-026 green; measured on this repo examined 334 == count 331 + sum(excluded) 3. Scope caveat: NB-2 below covers the --diff scope, which the AC does not require to balance" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "TEST-005 + TEST-006 green; withdrawal of the additivity clause verified honest — see the Guard Withdrawal section. NB-3/NB-4/NB-5 below" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "TEST-028 green; independently verified the released [v2026.08.16] CHANGELOG section byte-identical to main (4142 B both sides); SPEC-0132 diff is additive-only (2 lines re-emitted with appended SUPERSEDED text, all historical measurements intact); product-doc counts 9/65 = 14% and CHANGELOG counts 65->56 / 408->417 / 135->331 / examined 334 all match the live measurement" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "test-aai-prompt-diet.sh green (pin -2918 -> -2564, ledger entry 354 B, wc -c = 4759 confirms 4405+354); check-test-registration.mjs rc 0; follow-ups list --status open names none of the four" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-deslop.sh, line: 1247,
          issue: "TEST-023's real-tree half searches for each of the three symbols in ANY corpus document and breaks on the first hit. This ride's own spec (docs/specs/SPEC-0136-spec-deslop-corpus-honesty.md, type: spec, status: implementing) is a corpus member under BOTH the old and the new rule, names all three symbols in its Summary, and sorts first in the documents list — so the loop is satisfied by the ride's own document and never reaches CHANGE-0125/CHANGE-0096. Combined with the spec's own V-2 note (the candidates half is not failing-first either), the entire real-tree half of Spec-AC-02 passes identically under the pre-change engine.",
          failure_scenario: "Revert D1 (narrow the corpus back to docs/specs + type:spec) and re-run test_023: the three symbols are still absent (this spec suppresses them) and each is still 'named in a corpus document' (this spec). The arm stays green on the defect it was written to catch." }
      - { rank: NON-BLOCKING, file: .aai/scripts/deslop-unrequested.mjs, line: 1088,
          issue: "In the --diff scope renderJson synthesises examined = documents.length + unreadable.length while pairing it with a hardcoded all-zero excluded block (including excluded.unreadable: 0). The balance invariant this ride ships as its D4 headline — examined == count + sum(excluded) — therefore does NOT hold under --diff whenever a STATE-named requirement document is unreadable. Reproduced: count 1, examined 2, sum(excluded) 0, excluded.unreadable 0, while notes correctly names one unreadable document. New in this diff (--diff emitted no examined before).",
          failure_scenario: "A consumer applies the documented invariant to any --diff run whose STATE spec_path or primary_path is stale/unreadable and reads a false 'accounting broken' signal. The zero unreadable bucket also contradicts the note printed in the same payload. Fix is ~3 lines: either count the diff scope's unreadable into excluded.unreadable, or omit examined for --diff." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0136-spec-deslop-corpus-honesty.md, line: 460,
          issue: "The WITHDRAWN entry asserts 'Suite additivity survives as a project convention and a code-review duty.' No such convention or duty is written anywhere: .aai/SKILL_CODE_REVIEW.prompt.md contains no additivity check, and the only governance hit is CONSTITUTION.md:22 article 5, which scopes 'additive first' to public boundaries (APIs, prompts, schemas, step numbering), not test suites. This is the one place the withdrawal narrative claims a replacement protection that does not exist.",
          failure_scenario: "A future reviewer reads the AC, assumes the duty is part of their contract, does not perform the check, and an arm is silently deleted with nothing — mechanical or contractual — objecting." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0136-spec-deslop-corpus-honesty.md, line: 446,
          issue: "Spec-AC-06's correction says 'cmp appears nowhere in the suite'. Literally false: the token appears twice, in pre-existing comments at tests/skills/test-aai-deslop.sh:391 and :444 ('cmp-proven'), inherited from SPEC-0132's own wording. The substantive claim (no cmp invocation; manifests compared as shell strings) is correct and I verified it.",
          failure_scenario: "A reader greps for cmp to confirm the correction, finds two hits, and cannot tell whether the correction or the suite is wrong. Two-word fix: 'no cmp call exists in the suite (two stale cmp-proven comments at :391/:444 remain, describing a string compare).'" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-deslop.sh, line: 505,
          issue: "TEST-005 never asserts the engine's exit code; the suite runs under `set -uo pipefail` (no -e), so an engine that dies before doing any work leaves the fixture manifest and file list unchanged and the arm passes vacuously. Already filed as fu-test005-no-exit-assert (P3).",
          failure_scenario: "A startup-time throw in the engine (bad import, syntax error on a Node version bump) makes TEST-005 report the no-write property as proven when nothing ran. TEST-006 catches the exit contract on its own fixtures, so the pair still holds AC-06, but TEST-005 alone proves nothing." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md, line: 709,
          issue: "The ride adds four [SUPERSEDED] pointers to SPEC-0132 and corrects the cmp phrasing in its own new AC-06, but leaves SPEC-0132's Spec-AC-05 row ('proven by a sha256 manifest compared with cmp') — the origin of the false claim — untouched, alongside four other cmp assertions at :519, :604, :614, :620, :756, :833.",
          failure_scenario: "The correction is applied to the new document and not to the document that is actually wrong, so a reader of SPEC-0132 still learns the false mechanism. A fifth [SUPERSEDED]/[CORRECTED] marker at that row costs one line and matches the pattern the ride already established." }
  cannot_verify:
    - { claim: "TEST-028's base_ref() behaviour on a GitHub pull_request checkout (detached HEAD, only origin/main fetched) and its fail-closed branch when neither ref resolves",
        closes_with: "a CI run of the suite on an actual pull_request checkout, or a local detached-HEAD mutation harness; locally origin/main == main == HEAD == 83c3899, so only one of three paths was exercised" }
    - { claim: "That the 5 reds in tests/skills/test-framework.sh are exactly the known ride-caused ones and clear after commit + close",
        closes_with: "a post-commit, post-close full framework sweep; the dispatch instructed me not to run it and I did not" }
    - { claim: "That the relocated table in docs/analysis/ matches the untracked full walk at docs/ai/reports/deslop-candidate-adjudication-20260815.md",
        closes_with: "a diff of the two; the reports file is gitignored and outside the review diff, so only its existence and the tracked 10-row table were checked" }
    - { claim: "R4 — the directory allowlist stays exact as the repo grows",
        closes_with: "nothing available today; I independently confirmed it is exact NOW (0 requirement-typed documents under docs/** outside the three directories, and all three are flat), but the property is a snapshot, not an invariant" }
  overall: pass
```

## Preflight

- Base `main` = HEAD `83c3899`; `git status --porcelain=v1 -uno` = 17 at start and 17 at end. No restoring git command was run; every experiment ran in the session scratchpad.
- All figures below were produced under `bash -c` with `/usr/bin/grep` by absolute path, per the ugrep/zsh-history-modifier hazard named in the dispatch. The interactive `zsh` alias was never used for measurement.
- STATE `worktree.inline_review_scope` is stale — it still names the `ci-test-impact-selection` file list. `code_review.scope` is explicit and current, so I reviewed that. Four modified paths are outside it (`docs/ai/EVENTS.jsonl`, `factory-report*`, `overview*`, `tests/test-runs.jsonl`); all four are generated runtime ledgers, not scope work. Noted, not blocking.

## Dispatch coaching check

The dispatch declared its own anti-gaming posture and largely honoured it: it did not pre-rank findings and explicitly invited disagreement. Two soft framings are recorded for the record rather than as violations — it characterised two items as "non-blocking ... for your disposition" before I formed a view (both turned out non-blocking on my own reading), and it supplied a full narrative of the guard withdrawal before I had read it. I reviewed the whole scope independently and the two findings I rank highest (NB-1, NB-2) are ones the dispatch did not mention.

## Guard withdrawal — the judgement asked for

**Verdict: the withdrawal is honest, and dropping the guard was the right call. One sentence overstates.**

I discharged the manual check the spec explicitly hands to review ("Read this number, and the removal of TEST-027 itself, by hand at review time"), rather than accepting the withdrawal narrative:

| check | result |
|---|---|
| base arm definitions (`git show main:...`) | 21 |
| current arm definitions | 28 (21 base + 7 new: 022-026, 028, 030) |
| base arms missing from current | **0** |
| per-arm assertion-site count regressions (`ok=0` markers, per arm, base vs current) | **0 of 21** — every base arm identical; totals 114 -> 174 |
| deleted lines vs main (`git diff --numstat`) | 666 added, **22 deleted** |
| what the 22 deletions are | 1 documented in-place re-baseline (fixture corpus count 3 -> 4, with an inline comment naming this ride) + 21 old dispatch lines, replaced by a `"$@"`-aware dispatch that still lists all 28 arms |

So the withdrawal costs nothing measurable in this diff, and the base never had the protection. More to the point: each of the four mechanizations reported **PASS while a gutted arm sat in the suite**. A green in-file guard is worse than no guard, because it converts an unchecked property into a falsely-checked one — which is precisely the failure mode this ride exists to correct. Withdrawing it is consistent with the ride's own thesis, not an exception to it.

**Is the loss stated where a future reader hits it?** Yes, in three places of descending obscurity, and the first is not the history block: the AC Status table's Notes column for Spec-AC-06 (the table a reader and the close gate both walk), the WITHDRAWN sub-bullet in the AC body, and the Verification command list, which downgrades `git diff --numstat` to "informational only" and says outright that nothing mechanically gates additivity any more. The GUARD HISTORY block is additional, not the sole carrier. I grepped every scope document, the suite, the engine, the prompt, the product doc and the CHANGELOG for `TEST-027` / `test_027` / `additiv`: **no surviving promise of the protection anywhere.** The CHANGELOG's silence is correct — nothing shipped and nothing regressed.

**Where it overstates:** NB-3 above. "Suite additivity survives as a project convention and a code-review duty" names a duty that exists in no document. `.aai/SKILL_CODE_REVIEW.prompt.md` has no such clause; `docs/CONSTITUTION.md:22` article 5 scopes "additive first" to public boundaries, not suites. The claim happens to have been true this once because the spec's Verification section asked review to do it by hand and I did — but that is a per-ride instruction, not a standing duty. Recommend softening the sentence to what is actually true ("this ride's Verification section asks review to check it by hand; it is not written into the code-review contract") and letting `fu-deslop-suite-additivity-guard` carry the gap. I do not recommend editing the code-review prompt inside this capped ride — that pulls in the prompt-diet ledger, TEST-012 and PROFILES obligations for a governance change that deserves its own scope.

I do not find the dispatch's account of the withdrawal self-serving. It understated nothing I could find, and the four defeats are recorded in more detail than the withdrawal needs.

## Independent verification performed

| command / probe | result |
|---|---|
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-deslop.sh` | 28 PASS, 0 FAIL, "All tests passed!" |
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh` | all PASS |
| `node .aai/scripts/spec-lint.mjs` | LINT PASS, 0 findings, rc 0 |
| `node .aai/scripts/check-test-registration.mjs` | rc 0 |
| `node .aai/scripts/docs-audit.mjs --gate spec-deslop-corpus-honesty` | GATE PASS |
| `node .aai/scripts/deslop-unrequested.mjs --all --json` | corpus 331, examined 334, candidates 56, suppressed 417, excluded {draft 1, not_requirement_type 2, rest 0}; **balances** |
| corpus membership properties | 0 documents outside the three dirs; 0 under `docs/analysis`; three named symbols absent from candidates |
| which corpus docs name the three symbols | `CHANGE-0125` (guard, baseline), `CHANGE-0096` (pr-config) — and, first in list order, this ride's own SPEC-DRAFT (see NB-1) |
| allowlist exactness (own enumeration of `docs/**`) | 0 requirement-typed documents outside the three dirs; all three flat |
| released CHANGELOG `[v2026.08.16]` vs `main` | byte-identical, 4142 B both sides |
| `--diff` accounting probe (dangling-symlink fixture) | count 1 / examined 2 / sum(excluded) 0 — **does not balance** (NB-2) |
| `follow-ups.mjs list --status open` | the four target items absent; 4 items open against this ride (2x P2, 2x P3) |

## Warning dispositions (H6)

| # | finding | recommended disposition |
|---|---|---|
| NB-1 | TEST-023 real-tree half is satisfied by the ride's own spec | **remediate-in-tree** — ~5 lines: exclude this scope's own documents from the search loop (or require a `docs/issues/**` match specifically), and correct the V-2 note's "for the right, cited reason" sentence. Cheap and squarely on the ride's theme. If the owner holds the cap: promote-to-follow-up. |
| NB-2 | `--diff` `examined` breaks the D4 balance invariant | **remediate-in-tree** — ~3 lines in `renderJson`, plus one clause in Spec-AC-05 scoping the equation. Alternatively a new follow-up ref; it is newly-shipped output, so I lean remediate. |
| NB-3 | "code-review duty" names a duty that does not exist | **remediate-in-tree** (one sentence in the spec). The underlying gap is already carried by `fu-deslop-suite-additivity-guard` (P3). |
| NB-4 | "cmp appears nowhere in the suite" | **remediate-in-tree** (two words) — or accept as-is and record the acceptance; the substantive claim is correct. |
| NB-5 | TEST-005 vacuous-pass window | already **promoted** — `fu-test005-no-exit-assert` (P3). Enough. Does not block: TEST-006 owns the exit contract and AC-06's evidence is the pair. |
| NB-6 | SPEC-0132's own cmp rows uncorrected | **promote-to-follow-up-ref** — a frozen-spec text correction with six sites; not this ride's job to absorb under a cap. |

## Disposition of the two items validation handed over

- **cmp phrasing (NB-4):** the phrasing must change, but it is a two-word edit, not a gate. The current sentence is falsifiable by a one-command grep, in a ride whose entire subject is documents that assert checkable things. Leaving it is a small self-inflicted wound. Non-blocking.
- **TEST-005 exit assertion (NB-5):** the P3 follow-up is enough. It does not block. TEST-006 asserts exit 0/2 against the same engine and AC-06 cites the pair, so the AC's evidence chain holds; what is lost is only TEST-005's standalone strength, and no claim in the spec depends on it standing alone.

## Next steps

1. Owner decides NB-1 and NB-2: remediate in tree (~8 lines total, both with a clear failing-first observation available) or promote to refs. Both are on the ride's own honesty theme, which argues for remediation.
2. NB-3 and NB-4 are one-sentence spec edits; take them with whichever pass runs next.
3. NB-6 as a new follow-up ref against SPEC-0132.
4. Nothing here blocks the PR. Both verdicts pass.
