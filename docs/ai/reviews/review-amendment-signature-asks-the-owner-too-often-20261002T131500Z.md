---
review:
  scope: "git diff 0db79662..5c831dfd on change/amendment-signature-asks-the-owner-too-often (PR #422) — the round-4 remediation only. .aai/scripts/spec-amend.mjs, docs/specs/SPEC-0205-spec-amendment-signature-asks-the-owner-too-often.md, tests/skills/test-aai-spec-amend.sh, docs/ai/decisions.jsonl, docs/INDEX.md, docs/ai/EVENTS.jsonl, and the new docs/ai/reviews/review-amendment-signature-asks-the-owner-too-often-20261002T123435Z.md. Round 1-3 are OUT OF SCOPE by dispatch: three validation reports and two review reports already cover them independently."
  spec: docs/specs/SPEC-0205-spec-amendment-signature-asks-the-owner-too-often.md
  round: 4 (Codex P2 shell-quoting finding, Copilot Test-Plan-summary finding x2, Codex P1 missing-review-report finding)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01..21, call: "out of scope for this round", citation: "already walked by the round-3 review (docs/ai/reviews/review-amendment-signature-asks-the-owner-too-often-20261002T123435Z.md, itself a round-4-written transcription — see finding 1 below) and independently re-derived by VALIDATION-amendment-signature-asks-the-owner-too-often-20261002T124000Z.md; not re-walked here per explicit dispatch scope" }
      - { ac: Spec-AC-22, call: compliant, citation: ".aai/scripts/spec-amend.mjs:726-728 (shq helper) and :1476,:1690,:1736 (all three printed-command interpolation sites use it, confirmed by grep — no site missed); TEST-1378 PASS in a full suite run (env -u AAI_ROLE bash tests/skills/test-aai-spec-amend.sh, this session); mutation RED confirmed at docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1378.txt (rc=1, 'unknown flag \"with\"')" }
      - { ac: Spec-AC-23, call: compliant, citation: "the TEST-1379 parser in tests/skills/test-aai-spec-amend.sh (lines ~453-507) reads both tables and compares AC count, row count and the multi-row AC list against the sentence, exactly as worded; TEST-1379 PASS in the same full suite run; mutation RED confirmed at docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1379.txt (rc=1, 'sentence says 27, the Test Plan holds 26')" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: "docs/ai/reviews/review-amendment-signature-asks-the-owner-too-often-20261002T123435Z.md",
          line: "frontmatter does_not_cover (lines ~97-99) vs the body's 'Disposition of the NON-BLOCKING findings' section (lines ~211-226)",
          issue: "The report's frontmatter states plainly that it does NOT cover round 4 ('the round-4 changes ... Those are UNREVIEWED and need a fresh independent round'), but its own body then analyzes a round-4 test (TEST-1378 arm 2) and renders a disposition verdict on it: 'it inherits the same limit, which is recorded here so the follow-up is read as covering both guards.' That claim is also not backed anywhere in the durable, tracked artifact the WARNINGS POLICY designates for a disposition — I grepped docs/ai/decisions.jsonl for every record touching fu-flagspecs-guard-line-scoped and found exactly one, timestamped 2026-10-02T12:34:35Z (round 3), naming only 'TEST-1376's FLAG_SPECS guard' verbatim. It textually cannot mention TEST-1378, which did not exist until 12:50:58Z. The linkage lives only inside a document that disclaims reviewing the code it is linking to.",
          failure_scenario: "A later agent or operator picks up fu-flagspecs-guard-line-scoped to close it, reads the ledger record (the canonical source per the WARNINGS POLICY), sees it names only TEST-1376, and patches only that guard's line-scoping. TEST-1378 arm 2's identical limitation (verified below) ships unfixed and untracked, because the only place that connects the two lives in a document whose own frontmatter says 'not reviewed.' A skim-reader of the frontmatter would also reasonably conclude the body contains nothing about round 4, and be surprised to find it does." }
    non_blocking_disposition_recommendation: "Extend fu-flagspecs-guard-line-scoped with a short follow-up note (node .aai/scripts/follow-ups.mjs or a decisions.jsonl amendment note) that explicitly names TEST-1378/Spec-AC-22 alongside TEST-1376/Spec-AC-20, so the tracked ledger — not a disclaiming review report — is self-sufficient. P3, no observed bite yet (both guards are source-complete today; the gap is only in what a future partial fix might miss), so 'accepted residual' naming this explicitly in a NEW review report is also acceptable if the operator prefers not to touch the ledger again."
  verified_clean:
    - { area: "shq() escaping", result: "Correct. Verified against 11 adversarial values (space, single quote, double quotes, $(...) command substitution, backticks, $VAR, trailing backslash, empty string, repeated quotes, ';|&><', glob chars, embedded newline) round-tripped through a REAL `bash` eval via a disposable argv-printing script — every value arrived as exactly one intact argument. Standard POSIX single-quote-wrap-with-escaped-quote technique, textbook-correct." }
    - { area: "JSON.stringify -> shq at the other two sites", result: "No regression found. Grepped the repo for any consumer expecting the old double-quoted format (tests, docs, other scripts); none exists — TEST-013/015/016 extract-and-eval the printed line rather than pattern-match its quote style. TEST-015 and TEST-016 were correctly updated to be quote-style-agnostic rather than hardcoding the new quote character." }
    - { area: "TEST-1378 arm 2 narrowing ('command token onward')", result: "Confirmed to share the exact single-physical-line scope as TEST-1376 arm 2 (same code shape: match the subcommand/command-token position on line i, scan only lines[i].slice(from-there)). Checked for a LIVE blind spot: the one multi-physical-line printed-command block in the file (the USAGE text, spec-amend.mjs:617-640) contains zero actual `${...}` interpolations — only literal `<placeholder>` prose — so today the narrowing misses nothing real. The shared limitation is latent (a future multi-line console.log split across physical lines would evade both guards identically), not currently exploited." }
    - { area: "TEST-015 / TEST-016 re-pin strength", result: "Not loosened. Built a disposable detached git worktree at 5c831dfd (outside the reviewed tree, removed after use), patched shq() to a no-op passthrough, and ran the suite: TEST-015 failed immediately against the regression; in isolation TEST-016 NB-E and TEST-1378 arm 1 also failed, each against the exact defect class they exist to catch (bare values splitting into stray argv tokens / a double quote breaking eval). All three are genuine regression guards." }
    - { area: "TEST-1379 self-referential anchor", result: "The agent's account is accurate and is independently confirmed. mutation-run.mjs's applySedExpr (lib/mutation-record.mjs + mutation-run.mjs:372-377) applies the --sed pattern with String.replace and NO 'g' flag unless declared — i.e. only the FIRST match in the whole file. The two STAYED-GREEN mutation-record artifacts under docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/ show the literal anchor 's/26 rows; counted from the table/27 .../' hit the Test Plan row's own Mutation-column cell (which quotes that exact phrase and sits earlier in the file than the real sentence) instead of the sentence. I regex-searched the current spec for the shipped lookahead anchor '26 rows(?=; counted)' and found exactly ONE match in the whole file — the real sentence — because both self-referential mentions in the explanatory prose/cell are followed by '(' or a line break, never literally '; counted'. Today's fix is mechanically verified, not merely asserted." }
  cannot_verify:
    - { claim: "That no future edit to SPEC-0205's Test Plan preamble/Mutation-cell prose can ever again collide with TEST-1379's anchor the same way.",
        reason: "The fix is correct for the CURRENT text by construction, not by a standing uniqueness guard; the spec's own prose names the hazard ('Prose in this section must likewise never spell that phrase out') but nothing mechanical enforces it on every future edit.",
        closes_with: "node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-0205-... re-run after any future edit touching this section, before merge — confirmed wired into the close-work-item gate (tests/skills/test-aai-close-work-item.sh, test-aai-mutation-gate.sh), so a collision would surface at close time, not necessarily at edit time." }
    - { claim: "Whether the owner, when eventually clearing fu-amend-amendment-signature-asks-cf289a, will read the three new round-4 decisions.jsonl entries (one contract, two measurement) as distinctly and adequately disclosed.",
        reason: "This is a human sign-off judgment outside what the diff alone can settle.",
        closes_with: "the owner's actual sign-off event on fu-amend-amendment-signature-asks-cf289a." }
  overall: pass
---

# Code Review (round 4) — amendment-signature-asks-the-owner-too-often

## Scope

`git diff 0db79662..5c831dfd` on `change/amendment-signature-asks-the-owner-too-often`
(PR #422), run from `/Users/ales/Projects/aai-amend` at HEAD `5c831dfd`. Per
explicit dispatch, rounds 1-3 are not re-walked — they carry their own
validation and review evidence already. This review covers exactly what
round 4 changed: `shq()` and its three call sites in
`.aai/scripts/spec-amend.mjs`; Spec-AC-22/Spec-AC-23 and TEST-1378/TEST-1379
in the spec and suite; the re-pinned TEST-015/TEST-016 assertions; and the
new backfilled round-3 review report.

## Spec compliance

Spec-AC-22 and Spec-AC-23 (the only rows this round added) are both
**compliant**, cited above. Full suite run in this session (`env -u AAI_ROLE
bash tests/skills/test-aai-spec-amend.sh`) passed TEST-1354 through TEST-1379
inclusive, 0 failures. `node .aai/scripts/mutation-gate.mjs --spec
docs/specs/SPEC-0205-...` reports `GATE PASS: 26 row(s) satisfied degraded=0
unstamped=0 uncomparable=0`, matching the Test Plan's final row count.

## Code quality

One NON-BLOCKING finding (detailed in the frontmatter block above): the new
backfilled review report `review-amendment-signature-asks-the-owner-too-often-
20261002T123435Z.md` explicitly disclaims reviewing round 4, then makes a
load-bearing claim about a round-4 test's follow-up coverage inside its own
body — a claim that is not reflected anywhere in the actual tracked
follow-up record (`docs/ai/decisions.jsonl`, `fu-flagspecs-guard-line-
scoped`, which still names only TEST-1376/Spec-AC-20 verbatim, predating
TEST-1378's existence). This is a documentation/process-integrity gap, not a
functional defect — the code itself is correct and the guard really is
source-complete today (see "verified clean" below) — so it does not fail
this verdict, but it should be disposed per the WARNINGS POLICY rather than
left resting on one document's prose. No BLOCKING findings.

Six items were explicitly checked and found clean — see `verified_clean` in
the frontmatter for the evidence on each: `shq()`'s escaping correctness
(tested against 11 adversarial values through a real `bash eval`), the
safety of swapping `JSON.stringify` for `shq` at the other two printed-
command sites, whether TEST-1378 arm 2's narrower scan creates a live blind
spot (it does not — the one multi-line printed-command block has no real
interpolations), whether TEST-015/TEST-016's re-pin was loosened to pass
(verified NOT loosened via a disposable mutation-worktree check), and
whether TEST-1379's self-referential lookahead anchor is actually unique in
the current file (mechanically confirmed: exactly one match).

## Cannot verify

Two items, both forward-looking and outside what this diff can settle on its
own — see the frontmatter `cannot_verify` block: (1) whether a future,
unrelated edit to this spec's Test Plan prose could reintroduce the same
self-reference collision TEST-1379 just fixed (the fix is correct for today,
not guarded going forward beyond a prose warning and the close-time mutation
gate), and (2) the owner's eventual sign-off judgment on the open
`fu-amend-amendment-signature-asks-cf289a` tracker.

## Overall

**pass.** No BLOCKING findings. One NON-BLOCKING finding needs a disposition
recorded in the tracked ledger (recommendation given above) before closeout
per the WARNINGS POLICY's teeth.
