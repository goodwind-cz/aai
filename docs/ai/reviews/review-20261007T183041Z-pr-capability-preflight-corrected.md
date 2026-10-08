```yaml
review:
  scope: "bdeb425c040ada918dd97e5b878b71e420bad83a...d223eb064c1873b80178d726c07cb4d082a33418 plus all tracked working diffs"
  spec: docs/specs/SPEC-0210-spec-pr-capability-preflight.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:143; TEST-001; corrected main.log" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:196; TEST-002; native-linux.log and native-windows.log" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:74; TEST-003..005; corrected main.log and native-windows.log" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/SKILL_PR.prompt.md:21,54; TEST-006" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:216; TEST-007" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/system/PROFILES.yaml:205; tests/skills/suite-map.yaml:1117; TEST-008" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Authenticated live Azure compatibility and historical downstream reproduction", closes_with: "Authorized live Azure round trip and the original downstream pin/raw artifacts; existing fu-azure-live-proof-on-adoption remains open." }
    - { claim: "Every future agent follows the prose ceremony order", closes_with: "Executable ceremony enforcement or observed agent traces; current text and real CLI fixtures prove only their stated seam." }
    - { claim: "A completely green 104-suite aggregate on the final tree", closes_with: "A new complete aggregate; historical run remains 100 PASS/4 FAIL, with disclosed successful affected reruns." }
  overall: pass
```

# Corrected code review — pr-capability-preflight, round 2

Reviewed the entire 23-file immutable-base feature delta plus the two tracked working ledger appends. No paths were excluded: the umbrella RFC, roadmap, decisions, generated index, prior failed review and result, tests, implementation and all accompanying prose were read. STATE selects worktree mode; the staged diff is empty. HEAD is d223eb064c1873b80178d726c07cb4d082a33418. The RFC is retained as a draft proposal for later rides, not counted as delivery of A2–E. No dispatch coaching was observed.

The canonical assembled contract, role and learned rules, frozen amended spec, intake, technology contract, independent corrected Validation report and typed result were inspected. Requested model route is gpt-6-astra after unavailable gpt-5.3-codex routing. Actual serving model identity is unknown; no token usage is claimed. This reviewer wrote only these review artifacts, with no STATE, source, Git or lifecycle mutation.

## Acceptance criteria

| AC | Call | Citation and reasoning |
|---|---|---|
| Spec-AC-01 | compliant | `.aai/scripts/pr-preflight.mjs:143` validates explicit schema, checkout/current branch, remote and provider identity before readiness; TEST-001 includes refusal zero-call controls, supported Azure URI forms and direct/symlink parity. |
| Spec-AC-02 | compliant | `.aai/scripts/pr-preflight.mjs:196` binds the Azure organization/project/repository probes, requires the installed extension record and checks returned identity. TEST-002 pins exact argv, child environment and closed stdin; split Unicode success is observed on Linux and both Windows engines. Create permission remains unknown. |
| Spec-AC-03 | compliant | `.aai/scripts/pr-preflight.mjs:74` bounds subprocess time and combined output bytes, closes stdin and terminates the process tree; lines 189–195 classify only recognized signals. TEST-003..005 cover named refusals, output caps, positive credential-emission controls and timeout cleanup. |
| Spec-AC-04 | compliant | `.aai/SKILL_PR.prompt.md:21,54` moves fresh STATE initialization behind readiness and places the actual invocation before PROCESS writes, with refusal STOP and lock release. TEST-006 executes refusal preservation with success controls; arbitrary future agent obedience is not claimed. |
| Spec-AC-05 | compliant | `.aai/scripts/pr-preflight.mjs:216` pins GitHub hostname and returned owner/name/URL; generic/local routes invoke neither provider. TEST-007 exercises enterprise routing, auth refusal and sanitized generic output. Existing pr-platform regression is carried in independent validation. |
| Spec-AC-06 | compliant | `.aai/system/PROFILES.yaml:205`, `tests/skills/suite-map.yaml:1117`, hygiene inventory 104 and diet addition/checkpoint are consistent. TEST-008 checks actual classification/selection, +1200 LF bytes, CRLF parity and shallow history independence. |

All TEST-001..008 are present and wired into the Bash runner and shared native matrix. The corrected independent main log contains eight PASS records; mutation replay contains eight behavioral RED records, zero inconclusive/restamped. I verified all 29 evidence-file SHA-256 values and byte lengths in `docs/ai/tdd/pr-preflight-validation-corrected/evidence.json`. Base bytes remain an exact prefix for EVENTS, decisions and test-runs ledgers. The first read-only prefix probe exceeded Node's default capture buffer on the large decisions ledger; rerunning with an explicit 16 MB cap completed successfully. This was a reviewer probe issue, not a product failure.

The native raw-log observations and retained CI metadata bind run 37664380807 to d223eb064c1873b80178d726c07cb4d082a33418 with success. Linux records an ordinary uid 1001 and scratch override unset, all eight canonical Bash arms passing, and full Pester 156/0/0. Windows records both engines with all eight scope arms, 152 passing Pester cases and four POSIX-only skips per engine. Timeouts are 1730/1891 ms, child_alive=false, later_probes=0. The retained current local timeout is 1474 ms. These are strict provider-shim process proofs, not live authenticated Azure evidence. No redundant suite execution was needed for this read-only review.

## Findings and prior dispositions

No new BLOCKING or NON-BLOCKING code-quality finding was established. No new runtime sidecar or unsupported universal-negative test name is introduced.

- Prior R1 is remediated in tree: `tests/skills/test-aai-pr-preflight.sh:14` now derives the default from os.tmpdir with private per-run directories. The POSIX Pester arm also runs canonical Bash with the override unset, and native Linux evidence confirms that route.
- Prior R2 is remediated in tree: `.aai/scripts/pr-preflight.mjs:99–109` retains bounded Buffers and decodes on close. TEST-002 splits an actual Unicode JSON response within a character and proves READ_VERIFIED. The independent regression RED and current native GREEN are retained.
- The direct/symlink main guard follows the existing neighboring CLI pattern and TEST-001 proves output/exit parity. New runtime API references were checked to exist; no phantom API was found.

No H6 warning disposition is required because there are no NON-BLOCKING findings. No follow-up was filed by this reviewer.

## Evidence limits and remaining closeout work

The completed historical full sweep remains **100 PASS / 4 FAIL, exit 1**. The corrected validator documents doctor 54/54 and affected framework 6/6, plus the live-serve/reaper/sync-seed successful reruns and their provenance limitations. The outer framework tripwire reports its test-runs append; its report-only output was not erased or represented as a clean aggregate. The final-tree full aggregate has not been rerun; the known failures have specific resolved/environmental dispositions and no unexplained introduced failure was established. The two excerpt-only reruns are weaker retained evidence than complete raw logs, as the validator explicitly discloses.

Spec rows 02/03/05 and generated INDEX still say native proof pending; that accurately preserves their earlier lifecycle state but now needs normal closeout reconciliation to the retained native evidence. It is not a remaining functional blocker. The original intake/RFC/roadmap remain open until their applicable close steps. Contract amendments remain unsigned under the existing tracked `fu-amend-spec-pr-capability-preflight`; this review neither signs them nor authorizes merge. No acceptance behavior was waived to reach these verdicts.

The cannot_verify entries above are explicit scope limits. Live Azure adoption and historical downstream reproduction remain unproved; future read readiness may expire and never implies create authorization. The available current behavior and independent evidence support a PASS for this A1 code review. The orchestrator must independently check and apply the returned STATE command, stage the review companions, and complete the existing lifecycle/signoff requirements.

## Dispatched result

```yaml
subagent_result:
  scope: pr-capability-preflight
  role: Code Review
  status: PASS
  started_utc: 2026-10-07T18:30:41Z
  ended_utc: 2026-10-07T18:36:00Z
  duration_seconds: 319
  actual_model: unknown
  requested_model: gpt-6-astra
  evidence:
    - command: "git diff bdeb425c040ada918dd97e5b878b71e420bad83a...HEAD; git diff HEAD; git diff --cached"
      exit_code: 0
      output_snippet: "Full 23-file committed scope plus two ledger appends; staged diff empty. All paths read."
    - command: "Verify corrected evidence manifest SHA-256 and byte lengths"
      exit_code: 0
      output_snippet: "All 29 evidence file hashes and lengths match."
    - command: "Verify base ledger prefixes with explicit 16 MB read buffer"
      exit_code: 0
      output_snippet: "EVENTS, decisions and test-runs preserve exact base prefixes."
    - command: "Inspect local matrix/mutations, native raw-log scope observations and retained CI metadata"
      exit_code: 0
      output_snippet: "Local8/8; mutation8RED; exactd223 native success; Linux unset-scratch uid1001; both Windows engines8/8; no surviving fixture child."
  files_changed:
    - docs/ai/reviews/review-20261007T183041Z-pr-capability-preflight-corrected.md
    - docs/ai/reviews/result-20261007T183041Z-pr-capability-preflight-corrected.md
  blockers: []
  state_update_commands:
    - node .aai/scripts/state.mjs set-code-review --required true --status pass --scope "bdeb425c040ada918dd97e5b878b71e420bad83a...d223eb064c1873b80178d726c07cb4d082a33418 plus all tracked working diffs" --base-ref bdeb425c040ada918dd97e5b878b71e420bad83a --report docs/ai/reviews/review-20261007T183041Z-pr-capability-preflight-corrected.md --notes "Round 2 PASS: six ACs compliant; R1 portable scratch and R2 split UTF8 remediated; no NON-BLOCKING warnings. Live Azure, arbitrary-agent prompt obedience and historical aggregate limitations remain disclosed; amendment signature owed. Actual model unknown."
```
