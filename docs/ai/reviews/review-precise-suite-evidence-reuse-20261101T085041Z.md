# Code Review: precise-suite-evidence-reuse (round 4)

```yaml
review:
  scope: main...HEAD (feat/precise-suite-evidence-reuse, head c639df81, base main 89a63814; 29 files, +3464/-30)
  spec: docs/specs/SPEC-DRAFT-spec-precise-suite-evidence-reuse.md (amended; latest contract amendment 2026-11-01T04:45:55Z; owner HITL 2026-11-01T02:43:43Z option 1; amendments owner_signoff false, tracked by fu-amend-precise-suite-evidence-reuse)
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "test-framework.sh main() reuse split + reuse_report; TEST-3165 PASS (validation r7 full sweep at c1a494d2)" }
      - { ac: Spec-AC-02, call: non-compliant, citation: "suite-reuse.mjs:191 with :122/:180: a $SCRIPT_DIR/<literal> or $(dirname ...)/<literal> reference whose literal starts lib/ is handed to LIB_RE, which captures one segment only and runs only in tests/skills/ files. $SCRIPT_DIR/lib/sub/data.json, $SCRIPT_DIR/lib/../fixtures/x.txt and, in a tests/ file outside tests/skills/, $SCRIPT_DIR/lib/data.txt add no file (or an absent directory path) and are not unresolved; D4 (d) lists $SCRIPT_DIR/<literal> resolved against the own directory as a recognized form (finding B1). The addPath forms of r3 B1 and validation r7 B1-residual are fixed (:157-165; reviewer probe). TEST-3166/3167/3192 PASS for the forms they cover" }
      - { ac: Spec-AC-03, call: compliant, citation: "suite-reuse.mjs computeIdentity env/args/runtime/policy/history; TEST-3168..3172 PASS (r7)" }
      - { ac: Spec-AC-04, call: compliant, citation: "suite-reuse.mjs loadManifest/checkSuites reasons; TEST-3173, TEST-3174 PASS (r7)" }
      - { ac: Spec-AC-05, call: compliant, citation: "suite-reuse.mjs recordSuite refusals, test-framework.sh reuse_settle; TEST-3175, TEST-3176 PASS (r7)" }
      - { ac: Spec-AC-06, call: compliant, citation: "suite-reuse.mjs OFF modes, suite_execute AAI_SUITE_REUSE=0, release-dry-run.mjs:219; TEST-3177..3179 PASS (r7)" }
      - { ac: Spec-AC-07, call: compliant, citation: "reuse_report, generate_summary Reused, test-runs.jsonl reused; TEST-3180, TEST-3181 PASS (r7)" }
      - { ac: Spec-AC-08, call: compliant, citation: "suite-reuse.mjs:380-393 lintManifest now also reports gate-row-missing (:386) and not-gate-selected (:390); reviewer ran lint on a scratch clone of c639df81: rc 0; TEST-3182 (two new cases), TEST-3193, TEST-3194 PASS (r7 for c1a494d2 cases)" }
      - { ac: Spec-AC-09, call: compliant, citation: "select-suites.mjs isMain guard + export; TEST-3183, TEST-3190 PASS (r7)" }
      - { ac: Spec-AC-10, call: compliant, citation: "suite-reuse.Tests.ps1, ps1-quality.yml both lists; TEST-3184, TEST-3185 PASS (local pwsh; native Windows is post-PR H1)" }
      - { ac: Spec-AC-11, call: compliant, citation: "SKILL_VERIFY.prompt.md Reuse exception paragraph, VALIDATION.prompt.md step 5 c2, prompt-diet ledger; TEST-3186, TEST-3187 PASS (r7)" }
      - { ac: Spec-AC-12, call: compliant, citation: "suite-reuse.mjs 496 lines, imports node: + select-suites + lib/tree-hash + lib/runtime-file, IDENTITY_COMPONENTS at :31; TEST-3188 PASS (r7)" }
      - { ac: Spec-AC-13, call: compliant, citation: "docs/analysis/precise-suite-evidence-reuse.md; TEST-3189 PASS (r7)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 191,
          issue: "relative() returns early for any non-dynamic $SCRIPT_DIR/ or $(dirname ...)/ literal starting lib/, on the assumption that LIB_RE (:122, applied at :180) covers it. LIB_RE captures exactly one segment of [A-Za-z0-9_.-] and runs only for tests/skills/ files, and its result never goes through addPath, so it is neither normalized nor widened. Three shapes of a D4 (d) recognized form are lost: (1) a deeper lib path, $SCRIPT_DIR/lib/sub/data.json, records tests/skills/lib/sub (a directory, hashed absent forever); (2) a dot segment, $SCRIPT_DIR/lib/../fixtures/x.txt, records tests/skills/lib/.. (absent); (3) any $SCRIPT_DIR/lib/<file> in a closure file under tests/ but outside tests/skills/ adds nothing at all. None is pushed to unresolved, so the suite stays reusable. Same class as r3 B1 (normalization) on the path addPath does not see.",
          failure_scenario: "Reviewer probe with the shipped loadContext/computeIdentity in scratch repos (scratchpad/r4/probe2.mjs, probe3.mjs): 'SD lib subdir file', 'SD lib dotdot dir', 'dirname lib dotdot', 'tests/other SCRIPT_DIR/lib file' each give detects-change false, unresolved 0, after editing or adding the target; controls $SCRIPT_DIR/fixtures/x.txt and $SCRIPT_DIR/lib/data.json give true. A manifest suite (or a helper it sources from tests/<other>/) reads cat \"$SCRIPT_DIR/lib/fixtures/data.json\" 2>/dev/null || echo '{}': record a pass, edit data.json, check returns REUSE over the changed input. The minimal-tree gate refuses only a read whose absence fails the suite; this tolerant read passes there. No live manifest suite has this shape today (repo-wide grep for $SCRIPT_DIR|dirname)/lib/<x>/ or /lib/..: 0 hits; tests/skills/lib has no subdirectories)." }
  cannot_verify:
    - { claim: "Suite results at c639df81 (the two TEST-3167 trailing-dot cases and the TEST-3182 gate-row-missing case added after validation r7)", closes_with: "the validator's full sweep now running in the worktree; the reviewer ran no suites (dispatch)" }
    - { claim: "Native Windows parity (Pester under windows-5_1 / windows-wsl1, skip count unchanged)", closes_with: "post-PR H1: ps1-quality run on the PR head" }
    - { claim: "CI prints 'Evidence reuse: off (ci)' in every framework job and never reuses", closes_with: "post-PR H2: skill-suite run log on the PR head" }
    - { claim: "The five manifest notes are true for reads the minimal-tree gate cannot see (optional reads, absolute or $HOME paths, inherited env)", closes_with: "syscall-level trace (fs_usage/strace) of each manifest suite or a recorded line review per suite" }
    - { claim: "Role conduct: consumers read the cited log and never treat REUSED as the close-time sweep (R3)", closes_with: "observed behaviour over future rides; TEST-3186 checks text only" }
    - { claim: "Measured wall times and check seconds in the analysis note", closes_with: "re-running D11 on the reviewed head; not re-measured" }
    - { claim: "SKILL_VERIFY.prompt.md links docs/product/precise-suite-evidence-reuse.md, which does not exist at this head", closes_with: "the product doc landing before the PR (ship: product docs after LOOP COMPLETE)" }
  overall: fail
```

security_relevant: false

## Scope and method

- Scope: `git diff main...HEAD` in worktree `/Users/ales/Projects/aai-worktrees/precise-suite-evidence-reuse` (worktree mode, base main 89a63814, head c639df81). Working-tree changes outside the reviewed diff: `docs/ai/EVENTS.jsonl`, `docs/ai/tests/test-runs.jsonl` (telemetry from the running sweep).
- Contract: the frozen spec as amended, against the owner HITL decision (option 1): D4 (d) claims only the forms it lists as recognized or unresolvable; every other variable-built, derived or indirect form is R1 and the minimal-tree gate is the admission safety. A miss on a form D4 (d) lists is judged blocking, a miss on an unlisted form R1.
- Coaching note (anti-gaming contract): the dispatch stated the r3 findings, the commits since r3 and the severity rule for tokenizer misses (owner HITL contract). That is scope and contract context; no area was excluded and nothing was pre-rated. The whole branch was reviewed.
- Reviewer evidence: read the helper at head (closure, addPath, relative, lint), the delta `56d7f8d1..c639df81`, the new TEST-3167/TEST-3182 cases and validation r7. Probes in `/private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/r4/` (`probe.mjs`, `probe2.mjs`, `probe3.mjs`) import the helper from a `git clone --local` of c639df81 and compare computed identities before and after a change. `lint` run on that clone: rc 0. No suites run; nothing written in the worktree except this report.

## Round-3 findings and validation r7: resolution

| id | status | evidence |
|---|---|---|
| r3 B1 dot-segment literals | resolved for every token that reaches addPath | `suite-reuse.mjs:157-165`: punctuation trim no longer eats a whole `.`/`..` segment, then `path.posix.normalize`, escape or root collapse is unresolvable, trailing slash kept. Probe: `docs/specs/..` widens to `docs`, `docs/specs/.` to `docs/specs`, `docs/specs/../${f}` to `docs/`, `docs//specs/a.md` to the file; all detect the change. New TEST-3167 case covers these plus five unresolvable forms. The same class remains on the `lib/` path that bypasses addPath (B1 below) |
| validation r7 B1-residual (trailing `/..` cut) | resolved | c639df81 `:158-159`; TEST-3167 cases `trailing dotdot widens to the parent`, `... under tests widens to tests`, `trailing dotdot collapses to the root` |
| r3 N1 gate glob sync | resolved | `lintManifest` `not-gate-selected` (:390) and `gate-row-missing` (:386); two TEST-3182 cases; live lint rc 0 |
| r3 INFO `fu-reuse-comma-colon-literal` uncommitted | resolved | committed in c1a494d2 |
| r3 report staging | resolved | r3 report committed in c1a494d2 |

## Spec-AC walk

See `ac_walk`. Deviations from the amended spec:

1. D4 (d) recognizes `$SCRIPT_DIR/<literal>` and `$(dirname ...)/<literal>` resolved against the file's own directory, and `lib/<name>` in a `tests/skills/` file. A `$SCRIPT_DIR/lib/...` literal is the first form, but the code routes it to the second, which handles only one segment in `tests/skills/` files (B1). These are not among the forms the HITL narrowing moved to R1 (variable-built, derived, indirect, other base spellings).
2. All amendments unsigned, tracked by fu-amend-precise-suite-evidence-reuse: documented additive-with-disclosure path, not a finding.

## BLOCKING findings

- **B1 `.aai/scripts/suite-reuse.mjs:191`** (with :122, :180): the `lib/` early return in `relative()`. Suggested fix: return early only when LIB_RE really covers the reference, i.e. `rel.startsWith('tests/skills/') && /^lib\/[A-Za-z0-9_-][A-Za-z0-9_.-]*$/.test(restRaw) && !/^lib\/\.{1,2}$/.test(restRaw)`; otherwise fall through to the normal join plus `addPath`. Also make LIB_RE skip a `.` or `..` name (and optionally route its match through `addPath` so `lib/<a>/<b>` widens), or push such a match to unresolved. RED first in TEST-3167: `$SCRIPT_DIR/lib/sub/data.json`, `$SCRIPT_DIR/lib/../fixtures/x.txt`, `$(dirname "${BASH_SOURCE[0]}")/lib/../fixtures/x.txt`, and a sourced `tests/other/h.sh` reading `$SCRIPT_DIR/lib/data.txt`; each must give RUN reason=inputs after the target changes. Small change; no spec text change needed. Probe scripts above reproduce.

## NON-BLOCKING findings and recommended dispositions (H6)

None new this round.

accepted residual (carried from round 1): N5 - the args component is the helper's constant default, not passed by the framework; today's vector is constant and equals the default, no bite observed and no false record (P3).

INFO (does not gate): `docs/product/precise-suite-evidence-reuse.md`, linked from SKILL_VERIFY, still does not exist (listed under cannot_verify until the product doc lands before the PR).

## cannot_verify

See the YAML block: suite results at c639df81 (validator sweep running), post-PR H1/H2, reads the gate cannot see, role conduct (R3), measured timings, and the product-doc link.

## Next steps

1. Remediation: B1 with RED-first TEST-3167 cases; selected suites plus CORE for the round; the validator's close-time full sweep must then cover the fixed head.
2. Orchestrator: commit this report with the remediation commit; quote the N5 accepted residual in `code_review.notes`. Round-cap handling (this is the third consecutive normalization/closure finding on the tokenizer) is the orchestrator's and owner's call.
3. Re-review after remediation: same single pass.
