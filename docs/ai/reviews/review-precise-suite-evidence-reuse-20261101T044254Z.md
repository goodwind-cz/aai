# Code Review: precise-suite-evidence-reuse (round 2)

```yaml
review:
  scope: main...HEAD (feat/precise-suite-evidence-reuse, head 846955f0, base main 89a63814; 26 files, +3075/-29)
  spec: docs/specs/SPEC-0266-spec-precise-suite-evidence-reuse.md (amended; latest contract amendment 2026-11-01T02:47:05Z after owner HITL 2026-11-01T02:43:43Z option 1; all amendments owner_signoff false, tracked by fu-amend-precise-suite-evidence-reuse)
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "test-framework.sh reuse_check/REUSED path; TEST-3165 PASS (validation r5 selected 53/53 and full sweep test-20261101-040202)" }
      - { ac: Spec-AC-02, call: non-compliant, citation: "suite-reuse.mjs:157-159: a literal ending in . , : ; or ) directly followed by an expansion is trimmed and recorded as one absent path instead of widening to its deepest literal directory, contrary to D4 (d) 'A literal followed directly by an expansion ... widens to the deepest fully literal directory'; reviewer reproduced a false REUSE (finding B1). TEST-3166/3167/3192 PASS for the forms they cover" }
      - { ac: Spec-AC-03, call: compliant, citation: "suite-reuse.mjs:233-252; TEST-3168..3172 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "suite-reuse.mjs:62-76,313-317; TEST-3173, TEST-3174 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "suite-reuse.mjs:338-372, test-framework.sh:1072-1086 (forget now runs without REUSE_HELPER_OK, round-1 N1 fixed); TEST-3175, TEST-3176 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "suite-reuse.mjs:285-291, release-dry-run.mjs; TEST-3177..3179 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "suite-reuse.mjs:325-329; TEST-3180, TEST-3181 PASS" }
      - { ac: Spec-AC-08, call: compliant, citation: "suite-reuse.mjs:374-425 lint and lint --minimal-tree; TEST-3182/3193/3194 PASS; r5-validator-minimal-tree-live.log 5/5 PASS, r5-validator-minimal-tree-check-state.log FAIL as required. Evidence cell lacks a TEST-3194 artifact (N3)" }
      - { ac: Spec-AC-09, call: compliant, citation: "select-suites.mjs export + isMain guard; TEST-3183, TEST-3190 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-3184 (Pester 4/0/0 local, r5-validator-pester.log), TEST-3185 PASS; native Windows is post-PR H1" }
      - { ac: Spec-AC-11, call: compliant, citation: "SKILL_VERIFY.prompt.md:19-23 (wording now 'same declared inputs, env, args, runtime, policy and history', round-1 N2 fixed), VALIDATION.prompt.md step 5 c2; TEST-3186, TEST-3187 PASS" }
      - { ac: Spec-AC-12, call: compliant, citation: "suite-reuse.mjs 489 lines, imports node: + select-suites + lib/tree-hash + lib/runtime-file (amended), no shell option, IDENTITY_COMPONENTS at :31; TEST-3188 PASS" }
      - { ac: Spec-AC-13, call: compliant, citation: "docs/analysis/precise-suite-evidence-reuse.md; TEST-3189 PASS" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 157,
          issue: "addPath trims trailing [.,:;)] from the literal and then skips the deepest-literal-directory slice whenever a trim happened (line 159 'dynamic && !trimmed'), so a partly built path whose literal part ends in a dot (the normal shape of name.${ext}) is recorded as one absent path. D4 (d) lists this form as detected and widened.",
          failure_scenario: "A manifest suite reads cat \"$ROOT/docs/specs/SPEC-0001.${ext}\" (ext=md). explain shows input docs/specs/SPEC-0001 (absent), not docs/specs/. Record a pass, append a line to docs/specs/SPEC-0001.md, check prints REUSE. Reviewer reproduced this with the shipped helper in a scratch repo (checkSuites/recordSuite: check1 RUN no-record, record recorded, check2 REUSE after the edit). The admission gate refuses such a suite only when the read is mandatory at admission time; it does not run when a manifest suite's own file is edited later (N2), which is the realistic path: edit test-aai-pricing.sh to add the read, the suite runs fresh and records, and the next intermediate round reuses it over a changed input." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0266-spec-precise-suite-evidence-reuse.md, line: 219,
          issue: "D3 and R1 present the minimal-tree gate as the admission safety but do not say what it does not prove (validation r5 NB-1): it shows a suite passes with only its identity files, not that it re-runs on every change outside them",
          failure_scenario: "A future manifest suite does an exists-check or tolerant read (if [[ -f docs/x ]]), or reads an absolute or $HOME path, or depends on an inherited env var outside the env component. It passes the gate (validator probe zz-optional, zz-abs, zz-home admitted) and a reviewer trusting the D3 wording admits it; a change to that file then gives REUSE." }
      - { rank: NON-BLOCKING, file: tests/skills/suite-map.yaml, line: 0,
          issue: "The aai-suite-reuse row (which runs the gate via TEST-3194) is selected for manifest and helper edits but not for edits to a manifest suite's own file (validation r5 NB-2)",
          failure_scenario: "An edit to tests/skills/test-aai-pricing.sh that adds an undeclared read selects aai-pricing plus CORE only; the gate does not run until the next full sweep or nightly, and intermediate rounds can reuse the suite over the undeclared input (this is also the trigger path for B1)." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0266-spec-precise-suite-evidence-reuse.md, line: 549,
          issue: "Spec-AC-08 is marked done, but its Evidence cell cites only green-TEST-3182/3193 logs; nothing is cited for the minimal-tree clause added by the 2026-11-01 amendment (validation r5 NB-3)",
          failure_scenario: "docs-audit verify or a later reader of the AC table finds no artifact for the TEST-3194 clause and cannot tell it was proven; the evidence exists only in docs/ai/validation/precise-suite-evidence-reuse/r5-validator-minimal-tree-*.log." }
  cannot_verify:
    - { claim: "Native Windows parity (Pester under windows-5_1 / windows-wsl1, skip count unchanged)", closes_with: "post-PR H1: ps1-quality run on the PR head" }
    - { claim: "CI prints 'Evidence reuse: off (ci)' in every framework job and never reuses", closes_with: "post-PR H2: skill-suite run log on the PR head" }
    - { claim: "The five manifest notes are true for reads the minimal-tree gate cannot see (optional reads, absolute or $HOME paths, inherited env)", closes_with: "a syscall-level trace (fs_usage/strace) of each manifest suite, or a line review of each for exists-checks and absolute paths, recorded per suite; validator grep found no $HOME, /Users/ or worktree references" }
    - { claim: "Role conduct: consumers read the cited log and never treat REUSED as the close-time sweep (R3)", closes_with: "observed behaviour over future rides; TEST-3186 checks text only" }
    - { claim: "Measured wall times and check seconds in the analysis note", closes_with: "re-running D11 on the reviewed head; the reviewer did not re-measure" }
    - { claim: "Suite runs at head 846955f0 (selected 53/53, full sweep 120/0/1)", closes_with: "cited from VALIDATION-precise-suite-evidence-reuse-r5.md; the reviewer did not re-run suites this round (no code change since that run)" }
  overall: fail
```

security_relevant: false

## Scope and method

- Scope: `git diff main...HEAD` in worktree `/Users/ales/Projects/aai-worktrees/precise-suite-evidence-reuse` (STATE `worktree.user_decision: worktree`, base main 89a63814, head 846955f0 = merge of origin/main into 614f33dc). Uncommitted working-tree changes (`docs/ai/EVENTS.jsonl`, `docs/ai/tests/test-runs.jsonl` telemetry, untracked round-1 review report) are outside the reviewed diff.
- Contract: the frozen spec as amended, judged against the owner HITL decision (2026-11-01T02:43:43Z, option 1): D4 (d) claims only the forms the tokenizer catches, every other form is R1, the minimal-tree admission gate is the safety mechanism.
- Coaching note (anti-gaming contract): the dispatch named the HITL decision and the amended contract to review against. That is scope context, not a pre-rated finding; nothing was excluded. Full scope reviewed.
- Reviewer evidence: read the whole helper and the round-2 delta (c5896c33..HEAD). Probe in a scratch repo with the shipped helper, select-suites and libs: suite `fx` with `ext=md; cat "$ROOT/docs/specs/SPEC-0001.${ext}"`. `explain` lists `input docs/specs/SPEC-0001` only. Library cycle: `check` RUN no-record, `record` recorded, append to `docs/specs/SPEC-0001.md`, `check` REUSE (B1). Scan of the five live manifest suites' closures: no literal of this shape today (0 hits); repo-wide 4 hits, all in non-manifest suites (e.g. `test-aai-git-ref-guard.sh` `.aai/scripts/install-pre-commit-hook.{sh,ps1}`, which also hits the trim). No suites re-run; validation r5 ran selected+CORE and the full sweep at this exact head.

## Round-1 findings: resolution

| R1 id | status | evidence |
|---|---|---|
| B1 bare top-level dir literal | resolved | TOKEN_RE:121 accepts the bare name after `/ " ' = (`; QUOTE_CLOSED_RE:136 fails closed on `"$ROOT/docs"/x`; TEST-3167 extended; validator form matrix |
| B2 sidecar lifecycle | resolved | store via `loadOrDegrade`/`atomicWrite`/`reapAsides` (:29, :279-281, :368-370), corrupt -> `store-corrupt`; Spec-AC-12 import list amended (22:08:42Z); TEST-3176 concurrent + corrupt cases |
| B3 universal-negative test name | resolved | TEST-3193 renamed "no Node fs read traced by read-trace.cjs ..."; analysis note lists untraced channels |
| N1 forget skipped on helper-failed | resolved | test-framework.sh:1074 guards only on helper presence; REUSE_HELPER_OK gates record only (:1078); TEST-3175 case |
| N2 "complete input identity" | resolved (wording); product-doc link still dead until close-out step 1 lands `docs/product/precise-suite-evidence-reuse.md` before the PR |
| N3 history marker scope | disposition outstanding: STATE notes name `fu-reuse-history-marker-scope`, but no follow_up line exists in docs/ai/decisions.jsonl. Orchestrator must file it (follow-ups.mjs add) |
| N4 partial-prefix fallback | folded into B1 fix as recommended; but see round-2 B1, the fold is incomplete for literals ending in punctuation |
| N5 args not passed | accepted residual (quoted below) |
| N6 record max age | disposition outstanding: `fu-reuse-record-max-age` named in STATE notes, not filed in decisions.jsonl |

Also outstanding: the round-1 report `docs/ai/reviews/review-precise-suite-evidence-reuse-20261031T220105Z.md` is untracked; per report staging (SPEC-0013 H4) it must be committed with the scope together with this report.

## Spec-AC walk

See the `ac_walk` block. Deviations from the amended spec, in full:

1. D4 (d) partly built path: a literal ending in `.`, `,`, `:`, `;` or `)` directly followed by an expansion or glob character is not widened (B1). This is a detected form in the narrowed contract, not an R1 form, so the owner's narrowing does not cover it. Spec-AC-02 is called non-compliant because its "file the suite reads by a path literal" and TEST-3167's "a partly built path (prefix then variable or star) gives RUN" do not hold for this shape.
2. D3/R1 omit what the gate does not prove (N1).
3. Spec-AC-08 evidence cell does not cite TEST-3194 evidence (N3).
4. All amendments are unsigned (`owner_signoff: false`, tracked by fu-amend-precise-suite-evidence-reuse); the HITL record covers the 02:47:05Z narrowing in substance. Documented additive-with-disclosure path, not a finding.

## BLOCKING findings

- **B1 `.aai/scripts/suite-reuse.mjs:157-159`**: when the literal is dynamic, the trailing punctuation is part of the literal prefix, so the directory slice must apply regardless of the trim. Suggested fix: for `dynamic`, take `raw.slice(0, raw.lastIndexOf('/') + 1)` (trim only in the non-dynamic case), empty prefix stays `unresolved`. Add the `name.${ext}` shape (and `name.*`) to TEST-3167 with a RED first. Over-inclusion fails toward a miss, consistent with D4. One-line change, no spec text change needed.

## NON-BLOCKING findings and recommended dispositions (H6)

| id | finding | recommended disposition |
|---|---|---|
| N1 | D3/R1 do not say the gate proves "passes with only its identity", not "re-runs on any outside change" (optional reads, absolute/$HOME paths, inherited env) | remediate in tree: one sentence in D3 and R1 (additive amendment, P3) |
| N2 | gate not triggered by edits to a manifest suite's own file | remediate in tree: add the manifest suites' files to the aai-suite-reuse globs in suite-map.yaml (P2, it is the trigger path for B1-class bites); else promote to follow-up `fu-reuse-gate-on-suite-edit` |
| N3 | Spec-AC-08 evidence cell lacks TEST-3194 artifact | remediate in tree: cite r5-validator-minimal-tree-live.log and -check-state.log (or a green-TEST-3194.log) in the cell (P3) |

accepted residual: N5 (round 1) - the args component is the helper's constant default, not passed by the framework; today's vector is constant and equals the default, no bite observed and no false record (P3).

INFO (does not gate): `docs/analysis/precise-suite-evidence-reuse.md:152-157` still says untraced channels are "covered only by the literal bash review and the manifest note"; since the minimal-tree gate, mandatory reads through those channels are also refused at admission (understates, no false claim). `minimalTreeAdmit` copies `--manifest` fixtures only into the decision context, the scratch tree carries the live manifest; harmless because the gate runs the framework with `AAI_SUITE_REUSE=0`.

## cannot_verify

See the YAML block: post-PR H1/H2, reads the gate cannot see, role conduct (R3), measured timings, and the suite results cited from validation r5 rather than re-run.

## Next steps

1. Remediation: B1 with a RED-first TEST-3167 case; N1-N3 in tree as recommended. Selected suites plus CORE for the round (no full sweep needed for review; the close-time full sweep is the validator's).
2. Orchestrator: file `fu-reuse-history-marker-scope` and `fu-reuse-record-max-age` via follow-ups.mjs (round-1 N3/N6), stage both review reports with the scope commit, quote the N5 accepted residual in `code_review.notes`.
3. Re-review after remediation: same single pass.
