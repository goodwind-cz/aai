# PR434 final CI remediation maker report

Scope pr-capability-preflight; role Remediation. Shipping HEAD stayed 2d215ede5a5611caf7e55f1dc866b255bc010b80. Original final CI synthetic merge d2c2d0179473991a9fa3e465742bf9a82501e7b7 FAILED. This report supplies maker fix verification, not an independent validation/review verdict. Native Windows PowerShell 5.1 reproof and fresh independent Validation/Review remain pending.

## Root causes and corrections

1. CI ride-select TEST-002 passed advisory maintenance prose to gate as a ref. A private related-proposal fixture reproduces exit2. The test consumes next --json, checks proposal menu shape and gates its structured alternative, with distinct file-intake/bind/complete actions. Selection engine and the legitimate open fu-amend-spec-pr-capability-preflight were unchanged.
2. Full companion-suite progress exposed TEST-718 and TEST-1302 comparing the moving shipped roadmap to a 13-pair literal. Current shipped output is exactly 15 pairs and 4 wave-2 items. Both retain exact summary assertions against independently counted section rows. Deterministic fixture counts elsewhere remain unchanged.
3. Native CI TEST-008 inherited successful clone stderr; PS5.1 Stop promoted Git's detached-switch note to RemoteException. The clone boundary captures all stdio explicitly; genuine failing clone still throws with stderr. The portable benign-note control performs a real shallow clone then emits a note; removing captured stdio gives behavioral RED. Its real shallow/baseline-object-absent positive controls still pass. The private detached local checkout produced no real Git note, so its local pass is not a reproduction of PS5.1; authoritative platform RED is preserved in native-ci-red.log, and native GREEN remains pending CI.
4. External P1 discussion_r4211636751 was real on reviewed ac68ccc: selected/null preflight remote could differ from later hardcoded origin. Readiness prose now binds remote_name to origin when it exists and null only when origin is absent, matching platform probes and push. TEST-006 is RED without that instruction; multiple-remotes and null controls exercise alternate success/null bypass versus origin refusal, while existing snapshot preservation and success controls remain. CLI callers outside this ceremony retain explicit remote choice. Prose inspection does not prove arbitrary agents follow the instructions.

## Changes and lifecycle

Source changes are limited to the PR prompt, preflight/ride-select test suites, measured prompt-diet ledger and checkpoint, and the frozen scope spec. The prompt measures 37717 LF bytes against immutable baseline36430: 1287 credited bytes, checkpoint55539, zero padded headroom. Scope adds the companion test path and origin ceremony constraint, disclosed through canonical unsigned contract amendments; the existing owner sign-off follow-up remains open. Maker AC proof cells now cite current docs/ai/tdd logs alongside unchanged historical reports, and both AC gates pass. Frontmatter stays implementing for the independent recheck. No STATE or shipping Git writes were performed by this subagent.

Mutation replay initially yielded seven behavioral RED, one TEST-006 inconclusive because old patch context no longer applied. Historical TEST-006 patch/record bytes are preserved under this remediation directory. The same deletion-of-readiness mutation was reanchored, disclosed as measurement, and freshly remeasured. A mutation-run self-path copy failure was recovered by passing the patch from the single dispatched scratch root; no mutation-run engine change was made. Best-effort named friction was recorded for both the initial contract failures and this recovery.

Final replay exited 0: 8/8 attempted mutations still redden, zero inconclusive, zero re-stamped; mutation-replay-final.log.

## Executed evidence

All paths below are under docs/ai/tdd/pr-capability-preflight-remediation-20261007/. Every test command used the canonical wrapper from the repository root with AAI_ROLE=subagent. Preflight fixture runs also set AAI_PREFLIGHT_SCRATCH=/private/tmp/aai-pr434-remediation-scratch/fixtures.

| Command | Exit | Evidence |
|---|---:|---|
| bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh test_006, before origin prompt correction | 1 | remote-red.log |
| bash .aai/scripts/aai-run-tests.sh bash /private/tmp/aai-pr434-remediation-scratch/ride-red.sh, original text-to-gate boundary | 2 | ride-red.log |
| bash .aai/scripts/aai-run-tests.sh bash /private/tmp/aai-pr434-remediation-scratch/summary-red.sh, original 13-pair equality | 1 | summary-red.log |
| bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh test_008, private captured-stdio-removal mutation | 1 | clone-control-red.log |
| bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh | 0 | preflight-green.log, all eight rows |
| bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-ride-select.sh | 0 | ride-green.log, full suite |
| bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh | 0 | diet-green.log, including TEST012 |
| bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-platform.sh | 0 | platform-green.log |
| node .aai/scripts/docs-audit.mjs --gate spec-pr-capability-preflight; --ac-flip-check spec-pr-capability-preflight | 0 each | ac-gate.log |
| node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0210-spec-pr-capability-preflight.md | 0 | zero structural findings |
| node .aai/scripts/spec-amend.mjs list --strict | 0 | unsigned contract records remain tracked |
| git diff --check | 0 | no whitespace errors |

Source SHA256 values in source-hashes.json bind local source proof. The root must reset only last_validation, preserve code_review.pass, and dispatch independent Validation on its next tick; fresh Review follows the source-changing external finding under the parent workflow. No human decision is blocking the maker handoff.
