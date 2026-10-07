# Independent corrected Validation — pr-capability-preflight

Verdict: **PASS** for the bounded phase-A1 implementation at `d223eb064c1873b80178d726c07cb4d082a33418`. Independent current-tree checks and native execution resolve the preceding functional findings. This is not a PR approval or merge instruction; corrected Code Review remains next.

Validation started at **2026-10-07T18:07:20Z**, captured from the system clock. The checked typed result records the actual end and elapsed duration. Immutable comparison base: `bdeb425c040ada918dd97e5b878b71e420bad83a`. Reviewed the complete base-to-HEAD 23-file delta and all working changes, intake, frozen spec, STATE, canonical Validation/role/single-writer rules, technology contract, learned rules and generated canon. No source, spec, STATE, Git/index or lifecycle edits were made by this validator.

Requested route: premium fallback `gpt-6-astra`; requested gpt5 maker/validator routes were unavailable. **actual_model: unknown**: the interface does not expose verifiable serving weights. No model diversity or token count is invented. This was a fresh independent Validation context; prior maker/reviewer reports were evidence, not supplied verdicts.

## Original intent and coverage

All six original intake requirements are independently compared with their frozen Spec-ACs below. No requirement is omitted or weakened. The original scope excludes PR creation/resumption/stamping, reservation transport and later RFC stages; no live Azure adoption or elapsed-time speedup is claimed.

| Original requirement | Spec | Current behavioral verification | Result |
|---|---|---|---|
| AC-001 explicit identity before provider calls | Spec-AC-01 | TEST-001; invalid identity zero-call refusal, valid positive controls; real direct/symlink parity | aligned / satisfied |
| AC-002 bounded noninteractive Azure read, create permission unknown | Spec-AC-02 | TEST-002; exact deny-by-default argv/env/stdin, extension checks, split Unicode response | aligned / satisfied |
| AC-003 named remedy and nonzero refusal | Spec-AC-03 | TEST-003..005; client/extension/auth/network/unknown failures, timeout/child cleanup, output cap and secret markers | aligned / satisfied |
| AC-004 before ceremony writes; refusal preserves local state | Spec-AC-04 | TEST-006; actual prompt order and actual refusal STATE/index/HEAD/reservation snapshots | aligned / satisfied |
| AC-005 preserve explicit GitHub/generic contracts | Spec-AC-05 | TEST-007; exact repository/host, auth refusal, generic/none no probes; historical full platform regression | aligned / satisfied |
| AC-006 classify files and account prompt bytes | Spec-AC-06 | TEST-008; core profile, suite selection, LF/CRLF and shallow-checkout byte checkpoint; CORE hygiene | aligned / satisfied |

`docs/ai/tdd/pr-preflight-validation-corrected/evidence.json` binds 29 raw evidence files with SHA-256 and byte lengths. Its fresh observation is 2026-10-07T18:23:27.371209Z; historic raw evidence retains its own age and failed outcome. The outcome block below binds original intake/spec bytes and this manifest. Actual future agent compliance with a prompt cannot be guaranteed by lexical ordering assertions; the tested CLI refusal preservation is real executable behavior.

## Fresh current-tree verification

- Leak-safe framework command: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-check-state --skill aai-docs-audit --skill aai-spec-lint --skill aai-hygiene-pack --skill aai-pr-preflight --skill aai-doctor`, followed by canonical reaper. Exit **0**, completed **18:15:05Z**: **6/6 PASS, 6 isolated/seeded, 0 skipped/degraded/reattributed**. Complete aggregate: `docs/ai/tdd/pr-preflight-validation-corrected/affected-framework.log`; full per-suite artifacts: `tests/skills/results/test-20261007-180913/`.
- Preflight **8/8** passes, including native CLI split UTF-8 READ_VERIFIED and direct/symlink parity. Timeout observed **1474 ms** against <=3000 ms; child gone and no later probes. Doctor **54/54**, including TEST-439. Complete logs were inspected, not only summaries.
- Mutation replay: `bash .aai/scripts/aai-run-tests.sh node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-DRAFT-spec-pr-capability-preflight.md`, followed by reaper: exit **0**, **8 behavioral RED, 0 inconclusive, 0 restamped**. Original no-op baseline RED is disclosed and accepted by the RED checker; the separate real split-UTF8 failing-first regression log also reproduces expected READ_VERIFIED versus actual PROVIDER_RESULT_INVALID before remediation.
- Spec lint: **0 findings**. Acceptance gate: **PASS**. Global AC scan: **214 spec files, 208 opted in, 0 overdue, 0 scope rows due in <14 days, 0 malformed**. Positive control identifies five deferred/blocked rows, including current 02/03/05 due October 21. `ac-corpus.json` supersedes the invalid AC portion of earlier `corpus.json`, whose first attempt compared normalization objects with strings. Spec lifecycle rows stay untouched for the orchestrator's later close step.
- Actual shipping-checkout explicit local-only CLI route: exit **0 CAPABILITY_NOT_APPLICABLE** at **18:16:20.050Z**, bound to current source/target and d223 HEAD. STATE/index/HEAD/reservation snapshots unchanged. This intentional local-only test conveys no remote-read or create authority.
- E2E, build/deploy and browser checks are not applicable to this CLI/framework surface under the technology contract. No deployed product surface changed.

The outer framework wrapper prints `AAI-TRIPWIRE FAIL` for its own single **282-byte append to `docs/ai/tests/test-runs.jsonl`**. Its documented outer check is report-only; suite-level tripwires are clean for all six isolated suites. The append is retained, not erased. `tree-manifest.json` records the 23-file hash inventory, unchanged d223 HEAD, exact base/HEAD ledger prefixes and only this working delta. EVENTS and decisions receive no validator appends. Do not present the outer output as clean.

## Native evidence and prior findings

Exact-SHA CI [run 37664380807](https://github.com/goodwind-cz/aai/actions/runs/37664380807) completed successfully at **18:22:28Z**, with every job and step successful. Complete run/jobs JSON and raw logs are preserved in the evidence directory.

| Native execution | Actual evidence | Result |
|---|---|---|
| Linux, pwsh7 + canonical Bash | job112939733496; platform=linux, uid=1001, scratch_override=unset; real split Unicode/direct-symlink and canonical Bash scope matrix | 8/8 scope; Pester156 pass,0 fail,0 skip; analyzer pass |
| Windows PowerShell5.1 | job112939733227; real engine path and strict native CLI matrix | 8/8 scope; Pester152 pass,0 fail,4 POSIX-only skips; timeout1730ms |
| Windows pwsh7 | same job, separate real engine step | 8/8 scope; Pester152 pass,0 fail,4 POSIX-only skips; timeout1891ms |
| WSL1 routing/selftests + Windows5.1 | job112939733026; route/marker, timeout124 and spawnfail125 arms; CAT17 real guard | success; scope8/8; Pester152 pass,0 fail,4 POSIX-only skips |

Both Windows engines show split-UTF8 READ_VERIFIED, child_alive=false and zero later probes. The four named POSIX-only Pester cases run on Linux; there are **zero scope skips**. WSL raw NUL bytes are preserved and were read with text-safe decoding. These are native OS/shell proofs using strict provider shims, not live authenticated Azure adoption.

Round-one review R1 (Linux `/private/tmp` scratch default) is resolved by the portable `os.tmpdir` default and current native non-root Linux execution with the override unset. R2 (chunkwise UTF-8 decode) is resolved by bounded byte buffers decoded at close and actual split-character responses on all required native engines. Byte and timeout limits remain enforced. The direct/symlink main guard is exercised independently. No new functional validation finding remains.

## Historical failure retained; bounded remediation disposition

The completed required full sweep remains **100 PASS / 4 FAIL / 0 skip, 104 isolated/seeded, exit1**, completed **17:37:25Z**. Original raw log `docs/ai/tdd/pr-capability-preflight-final-full.log` and last independent FAIL report remain authoritative history. Two parent-created dirty windows were discarded and 16 suites rerun serially; none of this is rewritten as a green aggregate.

| Prior failing suite | Current disposition |
|---|---|
| doctor TEST-439 | independently rerun current suite54/54, framework PASS |
| live-serve sandbox EPERM | parent permitted isolated rerun14/14 exit0; retained `live-serve-excerpt.log` is an excerpt, not full raw output |
| run-tests reaper sandbox | parent permitted isolated rerun27/27 exit0; retained `reaper-excerpt.log` is an excerpt, not full raw output |
| sync-seed TEST-783 PATH assumption | parent full normal `/bin/bash` rerun exit0 through TEST-793, including783 and nested layer/bootstrap/hooks coverage; full captured output retained |

Sync rerun's outer report-only tripwire records the parent's 6005→d223 commit while an already-seeded isolated run was active. This is disclosed; it is not a clean aggregate. Relevant sync source is unchanged across that delta. The historical local full PowerShell155/156 updater failure has an immutable-base reproduction; current exact-SHA native Linux runs the same case successfully and full156/156. No local failure is silently waived.

Full-delta selector output is retained: **FULL_RUN, unmapped `docs/decisions/DECISION-pr-capability-preflight.md`**. Code-delta selector selects preflight plus CORE (check-state/docs-audit/spec-lint/hygiene). The required full104 execution already happened; this corrected round bounds reruns to the changed implementation and affected regressions, adds doctor, and inspects carried documentation and all ledger prefixes. It does not claim that the selector returned a narrowed full-delta result or that all104 now passed. No further broader retest is justified by a new implementation change or unexplained failure.

## Scope and residual obligations

The two original active roadmap rows and original W isolation decision are preserved; generated INDEX covers567 docs with0 overdue/0 broken. Umbrella RFC remains draft/open. Owner authorization for the CI snapshot did not waive final commit gates or authorize a merge. The unsigned contract amendment follow-up `fu-amend-spec-pr-capability-preflight` remains open; the latest measurement amendment freezes the stated contract projection without waiving behavior. No signature is inferred.

Live Azure access remains unverified (`fu-azure-live-proof-on-adoption`); read verification never certifies future create permission. Review must independently assess the corrected complete delta. The orchestrator must apply the proposed checked STATE commands and immediately dispatch; this validator made no STATE or lifecycle mutation.

## Outcome binding

```aai-outcome-v1
{
  "version": 1,
  "ref": "pr-capability-preflight",
  "validation_started_utc": "2026-10-07T18:07:20Z",
  "sources": [
    {
      "kind": "intake",
      "path": "docs/issues/CHANGE-DRAFT-pr-capability-preflight.md",
      "sha256": "39f6aeb49b7c8e3fc061150c617781aaa125e3705c49abeb073f37e56b8df564"
    },
    {
      "kind": "spec",
      "path": "docs/specs/SPEC-DRAFT-spec-pr-capability-preflight.md",
      "sha256": "9910aee7bc0cf395426c9fa6b6488e1367c038b8745d7c1bfd112e707810c711"
    }
  ],
  "requirements": [
    {
      "id": "AC-001",
      "source": {
        "path": "docs/issues/CHANGE-DRAFT-pr-capability-preflight.md",
        "quote": "AC-001: Missing or ambiguous repository/remote/source/base identity is refused before provider calls."
      },
      "constraint": "AC-001: Missing or ambiguous repository/remote/source/base identity is refused before provider calls.",
      "spec_ac_ids": [
        "Spec-AC-01"
      ],
      "assessment": "aligned",
      "rationale": "Original identity refusal is preserved. TEST-001 exercises valid and missing/mismatched/ambiguous identities with positive provider-call controls; direct/symlink CLI parity and spaces/Unicode pass.",
      "required": true,
      "outcome_ids": [
        "OUT-001"
      ]
    },
    {
      "id": "AC-002",
      "source": {
        "path": "docs/issues/CHANGE-DRAFT-pr-capability-preflight.md",
        "quote": "AC-002: Azure client, installed azure-devops extension and authenticated repository read probes are bounded and noninteractive; success reports read verification and unknown create permission."
      },
      "constraint": "AC-002: Azure client, installed azure-devops extension and authenticated repository read probes are bounded and noninteractive; success reports read verification and unknown create permission.",
      "spec_ac_ids": [
        "Spec-AC-02"
      ],
      "assessment": "aligned",
      "rationale": "Original Azure contract is preserved. TEST-002 verifies exact noninteractive bounded argv/environment and closed stdin, installed-extension checks, authenticated repository read via strict native shims, split UTF-8 READ_VERIFIED, and unknown create permission. No live Azure account claim.",
      "required": true,
      "outcome_ids": [
        "OUT-002"
      ]
    },
    {
      "id": "AC-003",
      "source": {
        "path": "docs/issues/CHANGE-DRAFT-pr-capability-preflight.md",
        "quote": "AC-003: Missing client/extension, authentication, network, timeout and unclassified access failures produce a named remedy and nonzero refusal."
      },
      "constraint": "AC-003: Missing client/extension, authentication, network, timeout and unclassified access failures produce a named remedy and nonzero refusal.",
      "spec_ac_ids": [
        "Spec-AC-03"
      ],
      "assessment": "aligned",
      "rationale": "Original distinct refusal, remedy and nonzero contract is preserved. TEST-003 through TEST-005 exercise missing prerequisites, auth/network/unclassified access, malformed outputs, timeout/child termination, and synthetic secret/output-cap controls.",
      "required": true,
      "outcome_ids": [
        "OUT-003"
      ]
    },
    {
      "id": "AC-004",
      "source": {
        "path": "docs/issues/CHANGE-DRAFT-pr-capability-preflight.md",
        "quote": "AC-004: The PR prompt invokes preflight before numbering, staging, feature/close commit or push; refusal preserves STATE, index, HEAD and reservation refs."
      },
      "constraint": "AC-004: The PR prompt invokes preflight before numbering, staging, feature/close commit or push; refusal preserves STATE, index, HEAD and reservation refs.",
      "spec_ac_ids": [
        "Spec-AC-04"
      ],
      "assessment": "aligned",
      "rationale": "Original ordering and preservation contract is preserved. TEST-006 checks actual prompt placement before writes and actual refused CLI fixture snapshots of STATE/index/HEAD/reservation refs; success controls show provider reachability. Future arbitrary agent obedience is not empirically guaranteed.",
      "required": true,
      "outcome_ids": [
        "OUT-004"
      ]
    },
    {
      "id": "AC-005",
      "source": {
        "path": "docs/issues/CHANGE-DRAFT-pr-capability-preflight.md",
        "quote": "AC-005: Existing GitHub and generic routes remain supported under their explicit readiness contracts."
      },
      "constraint": "AC-005: Existing GitHub and generic routes remain supported under their explicit readiness contracts.",
      "spec_ac_ids": [
        "Spec-AC-05"
      ],
      "assessment": "aligned",
      "rationale": "Original explicit GitHub and generic routes are preserved. TEST-007 checks exact host/repository binding, auth refusal, no provider calls for generic/none, and named fallback; existing platform coverage was included in the completed historical full sweep.",
      "required": true,
      "outcome_ids": [
        "OUT-005"
      ]
    },
    {
      "id": "AC-006",
      "source": {
        "path": "docs/issues/CHANGE-DRAFT-pr-capability-preflight.md",
        "quote": "AC-006: New vendored files are classified and added prompt bytes are accounted for in the prompt-diet ledger and checkpoint."
      },
      "constraint": "AC-006: New vendored files are classified and added prompt bytes are accounted for in the prompt-diet ledger and checkpoint.",
      "spec_ac_ids": [
        "Spec-AC-06"
      ],
      "assessment": "aligned",
      "rationale": "Original classification/accounting contract is preserved. TEST-008 checks real core classification, selector mapping, measured prompt addition and checkpoint; LF/CRLF and shallow checkout without historic object pass. CORE hygiene and full-sweep profile/prompt-diet regression evidence support it.",
      "required": true,
      "outcome_ids": [
        "OUT-006"
      ]
    }
  ],
  "outcomes": [
    {
      "id": "OUT-001",
      "requirement_ids": [
        "AC-001"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "d223eb064c1873b80178d726c07cb4d082a33418",
        "observed_identity": "d223eb064c1873b80178d726c07cb4d082a33418"
      },
      "verification": {
        "operation": "TEST-001 current CLI identity and direct/symlink behavioral matrix; independently inspected complete local output and exact-SHA native Linux/Windows 5.1/pwsh7 CI output; manifest binds raw evidence and historical context separately.",
        "evidence_path": "docs/ai/tdd/pr-preflight-validation-corrected/evidence.json",
        "evidence_sha256": "a436c52d766589cb784e04dae22cbc80baf25fe4d096e00ff3f8a88551c2c7f1",
        "observed_at_utc": "2026-10-07T18:23:27.371209Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only readiness CLI and private test fixtures; no external artifact or provider write is requested by this phase."
      }
    },
    {
      "id": "OUT-002",
      "requirement_ids": [
        "AC-002"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "d223eb064c1873b80178d726c07cb4d082a33418",
        "observed_identity": "d223eb064c1873b80178d726c07cb4d082a33418"
      },
      "verification": {
        "operation": "TEST-002 current Azure strict-shim argv/env/read and split UTF-8 matrix; independently inspected complete local output and exact-SHA native Linux/Windows 5.1/pwsh7 CI output; manifest binds raw evidence and historical context separately.",
        "evidence_path": "docs/ai/tdd/pr-preflight-validation-corrected/evidence.json",
        "evidence_sha256": "a436c52d766589cb784e04dae22cbc80baf25fe4d096e00ff3f8a88551c2c7f1",
        "observed_at_utc": "2026-10-07T18:23:27.371209Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only readiness CLI and private test fixtures; no external artifact or provider write is requested by this phase."
      }
    },
    {
      "id": "OUT-003",
      "requirement_ids": [
        "AC-003"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "d223eb064c1873b80178d726c07cb4d082a33418",
        "observed_identity": "d223eb064c1873b80178d726c07cb4d082a33418"
      },
      "verification": {
        "operation": "TEST-003..005 current refusal/remedy/timeout/credential and cap matrix; independently inspected complete local output and exact-SHA native Linux/Windows 5.1/pwsh7 CI output; manifest binds raw evidence and historical context separately.",
        "evidence_path": "docs/ai/tdd/pr-preflight-validation-corrected/evidence.json",
        "evidence_sha256": "a436c52d766589cb784e04dae22cbc80baf25fe4d096e00ff3f8a88551c2c7f1",
        "observed_at_utc": "2026-10-07T18:23:27.371209Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only readiness CLI and private test fixtures; no external artifact or provider write is requested by this phase."
      }
    },
    {
      "id": "OUT-004",
      "requirement_ids": [
        "AC-004"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "d223eb064c1873b80178d726c07cb4d082a33418",
        "observed_identity": "d223eb064c1873b80178d726c07cb4d082a33418"
      },
      "verification": {
        "operation": "TEST-006 current actual refusal preservation snapshots and prompt order assertions; independently inspected complete local output and exact-SHA native Linux/Windows 5.1/pwsh7 CI output; manifest binds raw evidence and historical context separately.",
        "evidence_path": "docs/ai/tdd/pr-preflight-validation-corrected/evidence.json",
        "evidence_sha256": "a436c52d766589cb784e04dae22cbc80baf25fe4d096e00ff3f8a88551c2c7f1",
        "observed_at_utc": "2026-10-07T18:23:27.371209Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only readiness CLI and private test fixtures; no external artifact or provider write is requested by this phase."
      }
    },
    {
      "id": "OUT-005",
      "requirement_ids": [
        "AC-005"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "d223eb064c1873b80178d726c07cb4d082a33418",
        "observed_identity": "d223eb064c1873b80178d726c07cb4d082a33418"
      },
      "verification": {
        "operation": "TEST-007 current GitHub/generic explicit route matrix; independently inspected complete local output and exact-SHA native Linux/Windows 5.1/pwsh7 CI output; manifest binds raw evidence and historical context separately.",
        "evidence_path": "docs/ai/tdd/pr-preflight-validation-corrected/evidence.json",
        "evidence_sha256": "a436c52d766589cb784e04dae22cbc80baf25fe4d096e00ff3f8a88551c2c7f1",
        "observed_at_utc": "2026-10-07T18:23:27.371209Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only readiness CLI and private test fixtures; no external artifact or provider write is requested by this phase."
      }
    },
    {
      "id": "OUT-006",
      "requirement_ids": [
        "AC-006"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "d223eb064c1873b80178d726c07cb4d082a33418",
        "observed_identity": "d223eb064c1873b80178d726c07cb4d082a33418"
      },
      "verification": {
        "operation": "TEST-008 current core/suite-map/prompt-byte accounting matrix and CORE hygiene; independently inspected complete local output and exact-SHA native Linux/Windows 5.1/pwsh7 CI output; manifest binds raw evidence and historical context separately.",
        "evidence_path": "docs/ai/tdd/pr-preflight-validation-corrected/evidence.json",
        "evidence_sha256": "a436c52d766589cb784e04dae22cbc80baf25fe4d096e00ff3f8a88551c2c7f1",
        "observed_at_utc": "2026-10-07T18:23:27.371209Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only readiness CLI and private test fixtures; no external artifact or provider write is requested by this phase."
      }
    }
  ]
}
```
