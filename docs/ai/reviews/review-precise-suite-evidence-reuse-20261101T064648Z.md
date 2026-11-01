# Code Review: precise-suite-evidence-reuse (round 3)

```yaml
review:
  scope: main...HEAD (feat/precise-suite-evidence-reuse, head 56d7f8d1, base main 89a63814; 28 files, +3305/-30)
  spec: docs/specs/SPEC-DRAFT-spec-precise-suite-evidence-reuse.md (amended; latest contract amendment 2026-11-01T04:45:55Z; owner HITL 2026-11-01T02:43:43Z option 1; amendments owner_signoff false, tracked by fu-amend-precise-suite-evidence-reuse)
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "test-framework.sh main() reuse split + reuse_report; TEST-3165 PASS (validation r6 full sweep test-20261101-060255)" }
      - { ac: Spec-AC-02, call: non-compliant, citation: "suite-reuse.mjs:157-161: a token holding a . or .. segment (tests/../docs/specs/, docs/./specs/) is matched by TOKEN_RE (dots are path characters) but never normalized, so underDir() finds 0 files and the directory or partly built path contributes nothing, and is not unresolved; D4 (d) says such a literal names a directory and adds every file under it (finding B1). The r2 B1 dot-ending form is fixed (:157). TEST-3166/3167/3192 PASS for the forms they cover" }
      - { ac: Spec-AC-03, call: compliant, citation: "suite-reuse.mjs:228-254; TEST-3168..3172 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "suite-reuse.mjs:62-76,311-316; TEST-3173, TEST-3174 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "suite-reuse.mjs:336-370, test-framework.sh reuse_settle; TEST-3175, TEST-3176 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "suite-reuse.mjs:283-289, suite_execute AAI_SUITE_REUSE=0, release-dry-run.mjs:219; TEST-3177..3179 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "reuse_report, generate_summary Reused lines, test-runs.jsonl reused field; suite-reuse.mjs:323-326; TEST-3180, TEST-3181 PASS" }
      - { ac: Spec-AC-08, call: compliant, citation: "suite-reuse.mjs:373-423; Evidence cell now cites green-TEST-3194.log (r2 N3 fixed); TEST-3182/3193/3194 PASS; r6-validator-minimal-tree-live.log 5/5" }
      - { ac: Spec-AC-09, call: compliant, citation: "select-suites.mjs isMain guard + export; TEST-3183, TEST-3190 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: "suite-reuse.Tests.ps1, ps1-quality.yml both lists; TEST-3184, TEST-3185 PASS (local pwsh; native Windows is post-PR H1)" }
      - { ac: Spec-AC-11, call: compliant, citation: "SKILL_VERIFY.prompt.md:19-23, VALIDATION.prompt.md step 5 c2, prompt-diet ledger +543; TEST-3186, TEST-3187 PASS" }
      - { ac: Spec-AC-12, call: compliant, citation: "suite-reuse.mjs 487 lines, node: + select-suites + lib/tree-hash + lib/runtime-file imports, IDENTITY_COMPONENTS at :31; TEST-3188 PASS" }
      - { ac: Spec-AC-13, call: compliant, citation: "docs/analysis/precise-suite-evidence-reuse.md; TEST-3189 PASS" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 157,
          issue: "addPath never normalizes the token. A token with a . or .. segment is a recognized D4 (d) form (path characters include .), but underDir() compares string prefixes against normalized listTreeFiles paths, so tests/../docs/specs/ or docs/./specs/ matches 0 files. The dir is logged '(0 files)', nothing is added, nothing is unresolved, and the suite stays reusable. A dot-segment literal without a trailing slash that names a directory falls to add(p); fileHash on a directory throws EISDIR and is recorded 'absent', which never changes.",
          failure_scenario: "A manifest suite reads cat \"$ROOT/tests/../docs/specs/${f}\" or loops for f in \"$ROOT/docs/./specs/\"*.md. Reviewer probe with the shipped loadContext/computeIdentity in scratch repos: 'dotdot dir then var', 'dotdot dir literal' and 'dot segment dir then var' all give target-in-inputs false, dirs '(0 files)', unresolved 0; the control docs/specs/${f} gives target-in-inputs true. Record a pass, edit docs/specs/a.md, check matches the recorded identity: false REUSE. The minimal-tree gate refuses only a mandatory read; a glob loop over the directory that matches nothing in the minimal tree passes the gate. No live manifest suite has this shape today (explain on all 5: 0 dot-segment tokens; repo-wide 4 hits, all fixture strings in non-manifest suites)." }
      - { rank: NON-BLOCKING, file: tests/skills/suite-map.yaml, line: 1416,
          issue: "The r2 N2 fix hand-lists the five manifest suite files in the aai-suite-reuse globs; nothing (lint, TEST-3182/3194, hygiene-pack) checks that each manifest suite's file stays in that list",
          failure_scenario: "A sixth suite is admitted to tests/skills/suite-reuse.json without adding tests/skills/test-<it>.sh to the aai-suite-reuse row. A later edit to that suite's file adds an undeclared read, selects only its own row plus CORE, the admission gate does not run, and intermediate rounds can reuse the suite over the undeclared input (the r2 N2 path returns for that suite)." }
  cannot_verify:
    - { claim: "Native Windows parity (Pester under windows-5_1 / windows-wsl1, skip count unchanged)", closes_with: "post-PR H1: ps1-quality run on the PR head" }
    - { claim: "CI prints 'Evidence reuse: off (ci)' in every framework job and never reuses", closes_with: "post-PR H2: skill-suite run log on the PR head" }
    - { claim: "The five manifest notes are true for reads the minimal-tree gate cannot see (optional reads, absolute or $HOME paths, inherited env)", closes_with: "syscall-level trace (fs_usage/strace) of each manifest suite or a recorded line review per suite" }
    - { claim: "Role conduct: consumers read the cited log and never treat REUSED as the close-time sweep (R3)", closes_with: "observed behaviour over future rides; TEST-3186 checks text only" }
    - { claim: "Measured wall times and check seconds in the analysis note", closes_with: "re-running D11 on the reviewed head; not re-measured" }
    - { claim: "Suite results at 56d7f8d1 (full sweep 120/0/1, TEST-3167 5 node cases)", closes_with: "cited from VALIDATION-precise-suite-evidence-reuse-r6.md; the reviewer did not re-run suites (dispatch: no full sweep)" }
    - { claim: "SKILL_VERIFY.prompt.md:21 links docs/product/precise-suite-evidence-reuse.md, which does not exist at this head", closes_with: "the product doc landing before the PR (ship: product docs after LOOP COMPLETE)" }
  overall: fail
```

security_relevant: false

## Scope and method

- Scope: `git diff main...HEAD` in worktree `/Users/ales/Projects/aai-worktrees/precise-suite-evidence-reuse` (STATE focus `precise-suite-evidence-reuse`, worktree mode, base main 89a63814, head 56d7f8d1). Working-tree changes outside the reviewed diff: `docs/ai/EVENTS.jsonl`, `docs/ai/tests/test-runs.jsonl` (telemetry) and `docs/ai/decisions.jsonl` (the uncommitted `fu-reuse-comma-colon-literal` follow-up line).
- Contract: the frozen spec as amended, against the owner HITL decision (option 1): D4 (d) claims only the forms the tokenizer recognizes; every variable-built, derived or indirect form is R1 and the minimal-tree gate is the admission safety.
- Coaching note (anti-gaming contract): the dispatch named the HITL contract and that validation r6 NB-1 is filed under R1. That is scope context, not a pre-rated finding; nothing was excluded. The full branch was reviewed, not only the delta.
- Reviewer evidence: read the whole helper at head, the framework, select-suites, release-dry-run, prompt and CI diffs, the remediation commit and validation r6. Probe script in scratch (`/private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/r3/probe.mjs`) builds scratch git repos and calls the shipped `loadContext`/`computeIdentity`. `explain` on the 5 live manifest suites: only dir-literals `docs/a/`, `docs/b/` (orchestration-mode fixtures), no dot segments. No suites re-run.

## Round-2 findings: resolution

| r2 id | status | evidence |
|---|---|---|
| B1 dot-ending literal before an expansion | resolved | `suite-reuse.mjs:157`: a dynamic literal now always slices to its last `/`; trim applies only to non-dynamic literals. Three TEST-3167 cases (`.${ext}`, `.*`, `.{sh,ps1}`); RED red-run4-b1-dot-literal.log; validator r6 probe: 9 false REUSE at 846955f0, RUN inputs at head; non-dynamic precision kept |
| N1 D3/R1 gate limits | resolved | spec D3 :231 and R1 sentence; amendment 04:45:55Z |
| N2 gate not run on suite-file edits | resolved for the five suites (suite-map.yaml:1416-1422; validator select check); drift risk is new N1 below |
| N3 AC-08 evidence cell | resolved | cell cites green-TEST-3194.log |
| r1 N3/N6 dispositions | resolved | `fu-reuse-history-marker-scope`, `fu-reuse-record-max-age` filed (decisions.jsonl 04:44:24Z/25Z) |
| report staging | resolved | both earlier review reports committed in 56d7f8d1 |

## Spec-AC walk

See `ac_walk`. Deviations from the amended spec:

1. D4 (d) directory literal with a `.` or `..` segment: a recognized token form (it starts with `tests`/`docs`/`.aai` and is made of path characters) that names a directory but adds no file and is not unresolved (B1). The forms D4 (d) moves to R1 are variable-built, derived or indirect; a dot-segment literal is none of these, so the narrowing does not cover it. Same class as r2 B1: the contract claims a form and the implementation misses it.
2. Validation r6 NB-1 (`,`/`:` before an expansion) is outside the token character set and correctly sits under R1 (follow-up `fu-reuse-comma-colon-literal`, not yet committed).
3. All amendments unsigned, tracked by fu-amend-precise-suite-evidence-reuse: documented additive-with-disclosure path, not a finding.

## BLOCKING findings

- **B1 `.aai/scripts/suite-reuse.mjs:157-161`**: normalize before deciding. Suggested fix: after computing `p`, `p = path.posix.normalize(p)` (it keeps a trailing slash: `tests/../docs/specs/` gives `docs/specs/`); if the result is `.`, `./`, `..` or starts with `../`, push to `unresolved` (fail closed, and it also covers `docs/../../etc/passwd`). `relative()` at :190 already normalizes, so this aligns the token path with it. Add `tests/../docs/specs/${f}`, `docs/./specs/` (dir literal) and `tests/skills/../../docs` (no trailing slash) to TEST-3167, RED first. Small change; no spec text change needed.

## NON-BLOCKING findings and recommended dispositions (H6)

| id | finding | recommended disposition |
|---|---|---|
| N1 | manifest suite files hand-listed in the aai-suite-reuse globs; no check keeps them in sync with the manifest | remediate in tree (P3): `lint` emits `not-gate-selected` for a manifest suite whose file does not match the aai-suite-reuse row globs, one TEST-3182 case; else promote to follow-up `fu-reuse-gate-glob-sync` |

INFO (does not gate): SKILL_VERIFY.prompt.md:21 links `docs/product/precise-suite-evidence-reuse.md`, which does not exist yet; listed under cannot_verify until the product doc lands before the PR. The `fu-reuse-comma-colon-literal` follow-up line is in the working tree only; commit it with the next remediation commit.

accepted residual (carried from round 1): N5 - the args component is the helper's constant default, not passed by the framework; today's vector is constant and equals the default, no bite observed and no false record (P3).

## cannot_verify

See the YAML block: post-PR H1/H2, reads the gate cannot see, role conduct (R3), measured timings, suite results cited from validation r6, and the product-doc link.

## Next steps

1. Remediation: B1 with RED-first TEST-3167 cases; N1 in tree or as a follow-up. Selected suites plus CORE for the round. The r6 full sweep predates the fix, so the close-time sweep must be re-run by the validator after this remediation.
2. Orchestrator: commit the `fu-reuse-comma-colon-literal` line and this report with the remediation commit; quote the N5 accepted residual in `code_review.notes`.
3. Re-review after remediation: same single pass.
