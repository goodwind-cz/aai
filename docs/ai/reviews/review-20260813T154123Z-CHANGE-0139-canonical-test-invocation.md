# Code Review — CHANGE-0139 canonical test-invocation contract

- Reviewer: Code Review role (single dual-verdict pass, .aai/SKILL_CODE_REVIEW.prompt.md)
- Scope: `git diff c2c4f9e..HEAD` (636a743 RED, 9d888f9 GREEN, 7137baf rot-pin fix, d3d7924 reconciliation) on branch feat/canonical-test-invocation @ d3d7924
- Spec: docs/specs/SPEC-0126-spec-canonical-test-invocation.md (frozen a341237, ceremony_level 1)
- Prior evidence: validation PASS round 1, docs/ai/validation/validation-20260813T153218Z-CHANGE-0139-canonical-test-invocation.md (F1, F2 non-blocking)
- Date: 2026-08-13T15:41:23Z

```yaml
review:
  scope: c2c4f9e..d3d7924 (feat/canonical-test-invocation)
  spec: docs/specs/SPEC-0126-spec-canonical-test-invocation.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "grep -F sweep: WIN/POSIX prefix count exactly 1 in each of TECHNOLOGY.md, TECHNOLOGY_TEMPLATE.md, AGENTS.md; repo-root + prohibition sentences verbatim in all three; both wrapper Usage headers carry the canonical prefixes comment-only (diff hunks read line-by-line — every changed line is a comment); all 7 prompt mentions bash-prefixed; test-aai-win-fallback 024/025 green (this run)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "rationale sentence verbatim in docs/TECHNOLOGY.md:92 and docs/USER_GUIDE.md:1920; USER_GUIDE Leak-safe subsection names both prefixes + 'once'; test 026 green (this run)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "aai-doctor.mjs:608-644 probeCanonicalInvocation — 1 readFileSync + 2 includes(), no spawn/network; tri-state true/false/'UNKNOWN' with honest reasons + /aai-update remedy; CAT-16 returned unconditionally PASS; doctor suite 40/40 green incl. test_038/039; real-repo --json carried=true (this run); CRLF+BOM AGENTS.md fixture probed → carried=true" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "independent re-measure: AGENTS.md +472, six prompts +5 each = 502 == the single ledger entry (prompt-diet-ledger.sh:159) == checkpoint delta (-7144 → -6642) == independent re-sum; DYNAMIC_SKILLS +5 correctly uncredited (system/); prompt-diet suite green, headroom 1622/2048" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "check-test-registration exit 0; product doc canonical literal, no 'pwsh -File .aai/scripts/aai-run-tests.ps1' as THE way; CHANGELOG own [unreleased] — heading with [L1]; full win-fallback / ps1-quality (Pester 141/141) / doctor / update suites exit 0 this run; bash -n on .sh OK; Parser::ParseFile on .ps1: 0 errors" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/USER_GUIDE.md, line: 1873,
          issue: "The Leak-safe section's step 1 still instructs the BARE shape `.aai/scripts/aai-run-tests.sh <cmd> [args...]` three paragraphs above the new two-prefix allowlist note",
          failure_scenario: "An operator or agent following step 1 verbatim invokes the bare shape, which the two-prefix allowlist does not match — the exact re-prompt churn this scope exists to kill, contradicted inside the same section" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-bootstrap.sh, line: 110,
          issue: "wrap_test_command() emits generated downstream aai-test-* commands as the bare `.aai/scripts/aai-run-tests.sh <cmd>` shape (validation F1; confirmed at L110-113 + the vitest guidance text L128)",
          failure_scenario: "Every downstream project bootstrapped after this ships allowlist-missing generated shortcuts; each run re-triggers the approval dialog" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-win-fallback.sh, line: 664,
          issue: "test_024's bare-mention detector compares grep -c LINE counts (n_all vs n_bash); a line carrying both a bare and a bash-prefixed mention counts once in each and the bare one hides (probed in scratch: n_all=1 n_bash=1 → pin fooled)",
          failure_scenario: "A future prompt edit that appends a bare fallback on an existing bash-prefixed line ('...or .aai/scripts/aai-run-tests.sh directly') passes TEST-024 while reintroducing a bare invocation instruction" }
      - { rank: NON-BLOCKING, file: .aai/templates/TECHNOLOGY_TEMPLATE.md, line: 45,
          issue: "Template carries literals + root rule + prohibition but NOT the allowlist-rationale sentence, though spec D1.1 says the template gains 'the same block' as TECHNOLOGY.md (grep -F count RAT=0). Compliant with Spec-AC-02 (which scopes the rationale to TECHNOLOGY.md + USER_GUIDE), deviant from the D1 prose",
          failure_scenario: "A downstream project authoring TECHNOLOGY.md from the template carries the WHAT but not the WHY; a downstream operator deciding whether to allowlist gets no rationale on the authoritative surface" }
  cannot_verify:
    - { claim: "Canonical ps1 shape behaves on real Windows 5.1/7 hosts",
        closes_with: "ps1-quality CI lanes (windows-5_1, windows-wsl1) at PR time; locally only POSIX Pester 141/141 + both-engine parse gates" }
    - { claim: "Pre-merge full-suite CI proof",
        closes_with: "the ci-full label present at PR open (validator's lane statement: select-suites yields mode=selected, no FULL_RUN trigger)" }
    - { claim: "'approved once, matches forever' — that every operator harness (Claude Code, Codex, Copilot) allowlists by literal prefix match",
        closes_with: "field observation per harness; RR-4 accepted in the spec as out of scope" }
    - { claim: "Downstream vendoring actually carries the contract to real machines",
        closes_with: "post-ship doctor probe on downstream hosts (the probe's designed purpose; RR-1/RR-2 accepted)" }
  overall: pass
```

## Verdict 1 — spec_compliance: PASS

AC walk above. Supplementary review-focus evidence:

1. **Literal stability (focus 1).** `grep -cF` per surface: the Windows prefix
   and POSIX prefix each appear EXACTLY once and byte-identically in
   docs/TECHNOLOGY.md, TECHNOLOGY_TEMPLATE.md, .aai/AGENTS.md, the respective
   wrapper header, USER_GUIDE, and (Windows) the product doc — zero variation
   in the allowlist-load-bearing prefix. The only variation is the trailing
   placeholder (`<command...>` in guidance vs `<command> [args...]` in wrapper
   headers) — cosmetic, outside the prefix, and the tests pin exactly the part
   that must be stable (INFO). The prohibition is unambiguous (names bash.exe,
   sh, wsl AND the CWD-relative anti-pattern). A downstream agent reading only
   the prompts gets the correct POSIX shape (`bash .aai/scripts/...`); the
   Windows shape lives in AGENTS.md, which is the one file every downstream
   agent reads at session start — the designed placement.
2. **Doctor probe (focus 2).** Reason strings honest; absent/unreadable →
   literal `'UNKNOWN'` with reason, never fabricated false (readText returns
   null on ANY read error, aai-doctor.mjs:70-76). PASS-only preserved
   unconditionally. Cost: one readFileSync of a ~20 KB file + two includes()
   per run — bounded, no spawn, no network (grep of the added hunk confirms;
   test_039 pins the function body). CRLF survival PROVEN empirically: I
   built a CRLF+BOM AGENTS.md fixture in scratch — `carried:true` (the
   literals contain no newline, so includes() is line-ending-agnostic).
   Minor: the carried-false reason asserts "outdated vendored layer" as the
   cause, but a locally edited AGENTS.md produces the same false — the
   /aai-update remedy is still the right first move (INFO, not a defect).
3. **Rot-pin widening (focus 3).** `^## \[(unreleased|v[0-9][^]]*)\]` is
   regex-correct: anchored at line start and heading level 2 (### does not
   match — probed), `[^]]*` is valid POSIX ERE (] first in a negated bracket),
   the alternation admits only `unreleased` or `v`+digit (`[vNEXT]` rejected —
   probed), and a non-heading bullet mentioning the pattern is rejected. Each
   widened pin still requires the CHANGE id ON the heading line, so the entry
   must exist as its own heading. Deletion probes on scratch CHANGELOG copies:
   removing the CHANGE-0139 entry and the rolled CHANGE-0137 entry each flips
   the corresponding regex to no-match — non-vacuous (independently confirms
   the validator's five deletion probes). Hiding a future deletion would
   require the id string to appear on some OTHER version heading — headings
   name only their own scope; risk negligible.
4. **Prompt edits (focus 4).** All six prompt diffs are pure `bash ` prefix
   insertions (+5 bytes each, re-measured via `git show c2c4f9e:<f> | wc -c`
   vs HEAD); zero semantic drift — each sentence's instruction is unchanged.
   Ledger math: 472 + 6×5 = 502 = the single JUSTIFIED_ADDITIONS entry =
   checkpoint delta (−7144 → −6642) = independent re-sum. DYNAMIC_SKILLS.md's
   +5 correctly excluded (system/, not corpus).
5. **Test quality (focus 5).** test_024/025/026 cannot pass with a broken
   contract in any state I could construct except the same-line shadowing
   technicality (NB-3 below). Here-strings (`<<<`) are bash-3.2-safe; the
   touched suites run under `set -uo pipefail` WITHOUT `-e`, so the
   `n=$(grep -c ...)` zero-count/exit-1 assignments cannot kill the suite
   (the LEARNED shell-options trap does not bite here; test-aai-update.sh's
   `-euo` blocks use `grep -qE ... || log_fail`, safe under -e). All added
   wrapper-header lines are pure printable ASCII (LC_ALL=C sweep of the
   added hunks: clean), and test_025 pins ASCII on the literal-carrying ps1
   lines permanently.
6. **Governance (focus 6).** CHANGELOG entry is its own
   `## [unreleased] — <title> (CHANGE-0139) [L1]` heading per convention.
   Ceremony 1 justification holds (guidance + doc pins + one additive
   PASS-only detail field; no protected path). F2 disposition below.

Commands run this pass (all exit 0): full test-aai-win-fallback.sh,
test-aai-doctor.sh (40/40), test-aai-prompt-diet.sh, test-ps1-quality.sh
(Pester 141/141), test-aai-update.sh, check-test-registration.mjs,
spec-lint.mjs on the spec, bash -n on the .sh wrapper, Parser::ParseFile on
the .ps1 (0 errors), aai-doctor.mjs --json on the real repo (CAT-16 PASS,
carried=true), plus scratch probes (CRLF+BOM fixture, regex adversarial set,
CHANGELOG deletion probes, test_024 shadowing probe, diet re-measure).

## Verdict 2 — code_quality: PASS (4 NON-BLOCKING)

No BLOCKING findings. The findings table (yaml above) with recommended
dispositions per the H6 warnings policy:

- **NB-1** (USER_GUIDE.md:1873 bare shape in the SAME section as the new
  allowlist note) — recommended disposition: **remediate-in-tree**. It is a
  5-byte, non-ledgered (USER_GUIDE is not prompt corpus), zero-risk edit and
  leaving it ships a self-contradicting operator section.
- **NB-2** (aai-bootstrap.sh wrap_test_command emits the bare shape —
  validation F1) — recommended disposition: **promote-to-follow-up-ref**
  (new CHANGE intake), as the validator recommended. Out of the frozen
  seven-mention scope; touching generated-command output deserves its own
  RED-first pins.
- **NB-3** (test_024 same-line shadowing technicality) — recommended
  disposition: **promote-to-follow-up-ref**, folded into the NB-2 intake
  (switch n_all to `grep -oF | wc -l` occurrence counting when that file is
  next opened). Not worth its own ride.
- **NB-4** (TECHNOLOGY_TEMPLATE.md lacks the rationale sentence vs D1.1
  prose) — recommended disposition: **decision record or fold into the NB-2
  follow-up** ("downstream contract carriage completeness"). AC-compliant
  as delivered; record whether the template omission is intended.

INFO (never gate): carried-false reason wording assumes vendored-layer
staleness as the only cause; placeholder cosmetics (`<command...>` vs
`<command> [args...]`) across surfaces.

## Verdict 3 — cannot_verify

Listed in the yaml block: real-Windows behavior (closes at PR CI),
pre-merge full-suite proof (ci-full label at PR open), per-harness
prefix-match allowlist semantics (RR-4), downstream vendoring effect
(RR-1/RR-2 — the probe itself is the designed post-ship observer).

## F2 disposition recommendation (RED_CLASS stamps)

Confirmed: none of the five stored RED logs under docs/ai/tdd/
red-20260813T151116Z-* carries a RED_CLASS line; tdd-evidence-check.mjs
reports UNCLASSIFIED. Recommendation: **accept-legacy, like CHANGE-0137** —
the RED-proof substance is satisfied twice over (stored failing logs with
named reasons + the validator's independent five-row RED replay on the
pre-implementation tree), and re-stamping after the fact would be
evidence-theater, not evidence. Pair the acceptance with a governance edge:
promote "TDD-lane RED logs must carry a RED_CLASS line at capture time" to
a LEARNED rule / the NB-2 follow-up so the NEXT scope fails fast instead of
relying on validator replay. This is a process-hygiene acceptance, not a
gap in this scope's proof.

## Merge gate

Both verdicts PASS → review status **pass**, conditional on the H6 duty:
each NB finding above must be remediated or promoted (decision id /
follow-up ref) before closeout. Merge additionally waits on: (1) the PR
carrying the **ci-full label at open** so mode=full runs pre-merge
(validator's lane statement — no FULL_RUN trigger in this diff), (2) green
Windows ps1-quality lanes on that PR, (3) bot review comments read before
any merge-ready claim (LEARNED), and (4) merging itself remains an
operator-only action.
