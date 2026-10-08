```yaml
review:
  scope: bdeb425c040ada918dd97e5b878b71e420bad83a...aa18e55e44f9487f0b8fdb6093b5a587c789960a
  spec: docs/specs/SPEC-0210-spec-pr-capability-preflight.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:146; TEST-001 local/Linux/native-Windows-5.1 PASS" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:219; TEST-002 local/Linux/native-Windows-5.1 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:76; TEST-003..005 local/Linux/native-Windows-5.1 PASS; final both-engine proof remains open" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/SKILL_PR.prompt.md:54; TEST-006 actual refusal snapshots and origin-binding controls PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:232; TEST-007 and independent pr-platform regression PASS" }
      - { ac: Spec-AC-06, call: non-compliant, citation: "tests/skills/test-aai-pr-preflight.sh:180; mandatory TEST-008 fails at exact-head native CI job113068918811" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Underlying cause of native TEST-008 clone failure", closes_with: "Complete nested child stderr/status on the failing Windows runner and a targeted failing-first repair followed by native GREEN" }
    - { claim: "Final both-engine Windows proof, full green CI and final independent Validation", closes_with: "Required successful checks bound to final shipping head; current WSL1 job fails and Windows job was still running" }
    - { claim: "Live authenticated Azure compatibility and original downstream reproduction", closes_with: "Authorized live fixture plus original downstream installed pin/raw logs; fu-azure-live-proof-on-adoption remains open" }
    - { claim: "Arbitrary future agents always obey PR prompt ordering", closes_with: "Executed agent traces or deterministic ceremony enforcement; current prompt/CLI fixtures cover only their stated seam" }
    - { claim: "Serving-model diversity from maker", closes_with: "Harness-observed serving model identities; requested gpt-6-astra high is not an observation" }
  overall: fail
```

# Fresh final code review — PR434

**FAIL: required native TEST-008 is red on the immutable reviewed head.** The independently executed local suites and mutation replay pass, and Linux CI passes, but those observations do not satisfy the mandatory Windows matrix. No new provider implementation defect was established; the code-quality verdict is independent of the failing compliance evidence.

## Scope and authority

Reviewed the full 282-file base-to-head scope, including implementation, tests, prompts, amended spec, intake, RFC, generated metadata, ledgers, reports and evidence packaging. Worktree mode is selected in STATE; the initial tracked/staged/untracked status was clean, and HEAD matches `aa18e55e44f9487f0b8fdb6093b5a587c789960a`. The full path inventory is retained in `review-20261007T232901Z-integrity.json`. No scope area was excluded. The RFC remains an umbrella draft; this change does not deliver its later phases.

Read the complete fresh canonical dispatch, Code Review skill/prompt, project guide, orchestration, playbook, technology contract, learned rules, named spec/intake/STATE/owner decision, maker report and explicit artifact manifest. No dispatch coaching or requested expected verdict was identified. Requested route is gpt-6-astra high; actual serving identity is **unknown**, and no token/cost estimate is made. This checker used a fresh context and wrote only its review artifacts. No source, STATE, index, Git history or lifecycle write was performed.

The owner decision `docs/decisions/DECISION-pr-capability-preflight-final-round.md` permits Review → metadata-only close → final full CI and independent Validation. It does not waive any failing test. This failed review does not satisfy the prerequisite for that closure sequence.

## Acceptance criteria and test evidence

| AC | Call | Evidence and limit |
|---|---|---|
| Spec-AC-01 | compliant | `.aai/scripts/pr-preflight.mjs:146` validates explicit schema, root/current branch and provider identity. Lines169–175 bind a single equal effective fetch/push destination and refuse whitespace, CR/LF and multiple endpoints before providers. TEST-001 passes direct/symlink parity, real Git pushurl/rewrite refusals and ordinary/matching/empty-entry controls locally, on Linux and in the completed Windows5.1 WSL-host job. |
| Spec-AC-02 | compliant | Lines219–231 require installed extension metadata, exact repository read identity, and leave create permission unknown. TEST-002 verifies closed stdin, exact deny-by-default argv/environment and split UTF-8 response success across the observed hosts. |
| Spec-AC-03 | compliant on observed arms | Lines76–109 implement bounded subprocesses and byte caps; lines202–207 classify recognized failures conservatively. TEST-003..005 pass missing client/extension, auth/network/unknown/malformed failures, secret-emitter positive controls, overflow and timeout/child cleanup. Local timeout1484ms; Linux1238/1243ms; Windows5.1 on WSL host2195ms, child_alive=false and no later probe. Final both-engine proof remains open. |
| Spec-AC-04 | compliant | `.aai/SKILL_PR.prompt.md:21,54` places fresh STATE repair and lifecycle/Git writes behind readiness, requires ceremony origin, and releases the session lock on refusal. TEST-006 checks the actual prompt and executes real refusal snapshots with successful provider/STATE-repair controls. It does not prove arbitrary agent obedience. |
| Spec-AC-05 | compliant | `.aai/scripts/pr-preflight.mjs:232` binds GitHub auth and repository read to resolved host; generic/none routes are explicit and sanitized. TEST-007 includes inherited-negative flags, host mismatch, generic credential controls and delayed lawful identity (>4 seconds). Existing platform regression independently passes. |
| Spec-AC-06 | **non-compliant evidence** | Core profile, suite-map row, hygiene104 pin and +1287-byte diet accounting are consistent; local profile/diet/ride-select suites pass. But the required portable benign-note/shallow control fails in TEST-008 at line180 on current native Windows5.1. The spec's TEST-008 green claim does not establish current native green; its prose correctly says reproof is pending. |

All TEST-001..008 exist and are registered in the Bash runner and native shared matrix. Original disclosed parseable no-op baseline RED and real later whitespace/CR regressions were read; product-red classification is distinct from the retained infrastructure deadline failure. No missing-command or syntax-error mutation was accepted. Current independent replay reproduces **8/8 behavioral RED, 0 inconclusive, 0 restamped**, without changing the recorded evidence.

## Blocking compliance finding R1

**Required Windows TEST-008 does not pass.** Location: `tests/skills/test-aai-pr-preflight.sh:180`, invoked by `tests/skills/aai-pr-preflight.Tests.ps1:56`.

Concrete observed scenario: run the shared eight-row Pester matrix on the Windows5.1 host with WSL1 available, checkout `aa18e55e44f9487f0b8fdb6093b5a587c789960a`. TEST-001..007 pass; TEST-008's benign-note clone control throws `FAIL: TEST-008 benign-note clone succeeds: node:child_process:955`. The native Pester aggregate is **151 passed, 1 failed, 4 declared POSIX-only skips**; job113068918811 and its full-Pester step fail. This is evidence from the exact current head, not an old snapshot or a inferred platform result.

Evidence: [native failed job](https://github.com/goodwind-cz/aai/actions/runs/37702465439/job/113068918811), `review-20261007T232901Z-native-jobs.json`, complete lossless `review-20261007T232901Z-wsl.log.b64`, and clearly labeled `review-20261007T232901Z-wsl-excerpt.log`. The raw log is80069 bytes with253 NULs; the base64 artifact preserves every byte without putting NULs into tracked text.

The captured RemoteException exposes only the first nested error line. **The underlying clone failure cause is unverified**; this report does not claim a path-length, quoting, timeout or Git defect without proof. Remedy: expose the complete nested child error on the failing native path, repair the observed cause within authorized scope, then obtain fresh required native success and a fresh review. Do not suppress the assertion, substitute macOS/Linux proof, or relabel the failure as lifecycle-only.

## Code quality, warnings and external threads

Code quality **PASS**, with no independently established new BLOCKING or NON-BLOCKING implementation defect. The native evidence failure above is not inflated into an unsupported claim that provider behavior is wrong. No new persistent runtime sidecar or overpromising universal-negative test name is introduced. Therefore no H6 warning disposition or new follow-up filing is required.

The three external findings are remediated in the pinned code and have actual replies: origin binding4211636751 → fixing60983274/TEST-006; effective push URLs4211969090 → fixing627ee444/TEST-001; URL whitespace4212243831 → fixingaa18e55e/TEST-001. The last reply is4213067277. This reviewer sent no GitHub messages and resolved no thread.

The known current lifecycle discrepancy remains visible: `docs/ai/roadmap.yaml:56` and generated overview delivered entries say done while intake/spec are implementing. The owner-authorized metadata reconciliation was intended to fix that after a successful review. It remains pending, and the failed native TEST-008 cannot be explained away by that discrepancy. Current full CI shards2/4 also fail their docs-audit CLEAN assertions; complete raw logs are retained as review companions. No final green aggregate is claimed.

## Independent checks and preserved evidence

All reviewer test wrappers ran **strictly serially** against the frozen shipping tree and settled before report writing:

| Command after canonical `bash .aai/scripts/aai-run-tests.sh` prefix | Exit | Result / log suffix |
|---|---:|---|
| `bash tests/skills/test-aai-pr-preflight.sh` | 0 | Eight PASS rows; `-preflight.log` |
| `bash tests/skills/test-aai-pr-platform.sh` | 0 | Existing platform routes; `-pr-platform.log` |
| `bash tests/skills/test-aai-layer-profiles.sh` | 0 | Full distribution suite; `-layer-profiles.log` |
| `bash tests/skills/test-aai-prompt-diet.sh` | 0 | Full accounting suite; `-prompt-diet.log` |
| `bash tests/skills/test-aai-ride-select.sh` | 0 | Structured selection and shipped summary companions; `-ride-select.log` |
| `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0210-spec-pr-capability-preflight.md` | 0 | 8/8 RED, no restamp/inconclusive; `-mutation.log` |

Every suffix above uses prefix `docs/ai/reviews/review-20261007T232901Z`. The exact-head Linux job113068919022 succeeds with both eight-row runs and Pester156/0/0; its complete raw log is `-linux.log`. Windows job113068919033 was still running at the retained CI snapshot; no result is presumed. WSL job113068918811 had already failed.

Integrity checks independently confirm263/263 maker-manifest entries,19/19 original transport hashes/lengths,9 unchanged historical report hashes,24 preserved mutation artifacts and byte-exact base prefixes for EVENTS/METRICS/decisions/test-runs ledgers. The complete scoped corpus has no NUL or Windows-invalid filename. Maker logs that contain outer tripwire refusals remain historical failures; later clean logs and current reviewer checks are separately identified. The full base→head `git diff --check` exits2 on275 whitespace-only diagnostics:274 preserved raw-evidence diagnostics and one decision EOF blank. This informational formatting result does not justify rewriting historical proof or a code-quality finding.

All logs/report/typed result and a SHA256 artifact manifest are explicitly listed in the RESULT companion. No outstanding reviewer wrapper remains. Root alone applies the returned FAIL STATE command and chooses the next authorized role. Final metadata closure, full/native CI, independent Validation and owed `fu-amend-spec-pr-capability-preflight` owner signoffs remain unsatisfied; no merge authority is granted.
