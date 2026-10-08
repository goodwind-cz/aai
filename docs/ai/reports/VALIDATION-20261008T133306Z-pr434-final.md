# Final parent Validation — PR434

Verdict: **FAIL (evidence completeness)**. No new product behavior failure was reproduced. Current functional, native and mutation checks pass, but the original parent RED artifact required by the spec and this dispatch is unavailable, so original TDD chronology cannot be independently checked. Code review gate: **pass**, retained semantic assembly review. AC status gate: **pass**.

## Scope and independence

Validation started at **2026-10-08T13:33:06Z**, read from the system clock. Scope is the complete `bdeb425c040ada918dd97e5b878b71e420bad83a..9d90d1e4dad24ff56f69a938f87c97510d61b740` assembly (1,002 changed paths), including both child repairs and final aliases. Source SHA256 is `e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf`; shared suite SHA256 is `239206e806eff008083c8c1b081587760aa0ec9f4094fe7336a7404dc169df7c`. Fresh context, artifacts only; requested validator gpt-6-astra differs from requested makers gpt-6-luna/gpt-6-sol, but actual serving identities and weight independence are unknown. No model identity is inferred.

STATE is active, human_input.required=false, parent last_validation=not_run, strategy=tdd. The owner decision `DECISION-pr434-identity-split.md` explicitly orders final independent Validation after Review, actual metadata close and native/full CI. The preserved default snapshot chooses rule6 Planning because the documents are done. This execution uses the explicit final-delivery override; it does not pretend rule11/default dispatch or reopen metadata. No subagents were used: identity, provider and ceremony requirements share the same input/CLI boundary and are not independent validation partitions.

Original intake, frozen spec, technology contract, source, full changed-path inventory, companion diffs, native harness, owner decisions, prior failed/child validation and assembly review artifacts were read independently. Historical raw evidence was inspected selectively and integrity-checked; this is not a claim to manually reread every line of the 125,943 added lines. The entire executable behavior is one read-only Node CLI plus prompt/profile/test integration. No e2e/browser/build surface exists. Discovery finds104 Bash skill suites and5 Pester files. Exact-head full CI supplies the broad sweep; the dispatch explicitly says not to duplicate it locally without a concrete concern.

## Requirement → specification → implementation → evidence

All original six ACs are aligned with the frozen spec; no omitted or weakened behavior found. The separate original-RED process requirement is aligned but **unknown in evidence**, blocking the full chain.

| Requirement | Spec | Implementation | Evidence and finding |
|---|---|---|---|
| AC-001 explicit identity, reject ambiguity | Spec-AC-01 | pr-preflight identity, local Git and raw URL validation | fresh TEST001; extra malformed port, encoded dot/password and exact endpoint probes; satisfied |
| AC-002 bounded noninteractive Azure read, create unknown | Spec-AC-02 | probe/readiness/Azure launcher | TEST002 exact argv/env/stdin, split UTF8; native matrix; satisfied |
| AC-003 named safe refusal | Spec-AC-03 | Refusal, timeout/byte cap, error classifier | TEST003–005; timeout1456ms, child_alive=false, no later probes; satisfied |
| AC-004 preflight before writes, refusal preserves state | Spec-AC-04 | SKILL_PR PRECONDITIONS + read-only CLI | TEST006 origin/alternate/null and STATE/index/HEAD/ref snapshots; prompt order inspected; satisfied within declared prose limitation |
| AC-005 lawful GitHub/generic routes | Spec-AC-05 | provider identity uses ASCII folding after literal endpoint check | TEST007;11 extra probes including public/enterprise combined case, Unicode distinction, generic redaction and Azure positive; satisfied |
| AC-006 classified/selected files and measured prompt bytes | Spec-AC-06 | PROFILES, suite-map, diet ledger/checkpoint and companions | TEST008, exact-head full CI103PASS/0FAIL/1SKIP;1287-byte delta and checkpoint55539; satisfied |
| RED before implementation | Test Plan/Evidence by strategy | original parent TDD artifact | **unknown**: named original log absent; checker exit3. Mutation sensitivity does not reconstruct chronology. |
| No installs/credentials, preservation, bounded scope | Spec provider/ceremony seams | shell:false, strict probes, closed stdin | fresh tests/source inspection, unchanged boundary and tracked bytes; satisfied |
| Native platform evidence | Verification | shared Node matrix + native Pester | Windows5.1/pwsh7/WSL1 and Linux exact-head CI; satisfied |
| Historical byte-preserving packaging | Evidence contract | six aliases + prior transitive aliases/base64 transport | six Git804 blob equalities,41 integration hashes,5 earlier aliases,605 Git804 reports/reviews identical; satisfied for enumerated corpus |

Evidence paths below are relative to `pr434-final-validation-20261008T133306Z/` beside this report.

## Executed evidence and CI inspection

All local test execution used the canonical wrapper in `/private/tmp/aai-pr434-final-validation-scratch`, with `AAI_ROLE=subagent`, `AAI_TEST_ISOLATION=0`, TMPDIR and fixture scratch confined there. Epoch captured before each command; canonical reaper followed each test. Wrapper wording calls its working directory “shipping repository” when isolation=0; the actual cwd was the authorized copy, never the real checkout.

| Command / verification | Exit | Observation |
|---|---:|---|
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh` | 0 |8/8 named PASS; `preflight.log` |
| wrapper + `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0210-spec-pr-capability-preflight.md` |0|8/8 RED,0 inconclusive,0 restamped; `parent-replay.log` |
| same replay for SPEC0211, first attempt |4|1 RED,1 inconclusive: validator created evidence-audit.py in scratch during execution; retained `generic-replay.log` |
| same replay for SPEC0211, stable rerun |0|2/2 RED,0 inconclusive,0 restamped; `generic-replay-stable.log` |
| same replay for SPEC0212 |0|2/2 RED,0 inconclusive,0 restamped; `case-replay.log` |
| wrapper + `node adversarial.cjs /private/tmp/aai-pr434-final-validation-scratch 007` |0|11 positive/negative seam probes; `adversarial.log` |
| `node .aai/scripts/docs-audit.mjs --gate SPEC-0210` |0|all terminal/evidenced, valid Review-By |
| `node .aai/scripts/docs-audit.mjs --no-event` |0|CLEAN;8 unreadable AC tables explicitly report-only |
| `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0210-spec-pr-capability-preflight.md` |0|no structural findings |
| `node .aai/scripts/spec-amend.mjs list --strict` |0|unsigned amendments explicitly tracked, not signed |
| tdd-evidence-check on6 available classified child/remediation RED logs |0 each|product_red accepted; `red-checks.json` |
| `node .aai/scripts/tdd-evidence-check.mjs --red docs/ai/tdd/pr-capability-preflight-red.log` |3|original parent RED missing; blocking |

Replay patches were applied only by the canonical replay engine inside the scratch hierarchy. Its named warnings about nested untracked scratch directories are retained. No replay restamped the real tree. Before checking final claims I read the resulting full local logs and reconciled the attempt exit codes.

Captured API run records independently bind all three completed successful runs to **9d90d1e4dad24ff56f69a938f87c97510d61b740**: skill-suite37778220504, ps1-quality37778220619, docs-numbering37778220735. Full metadata/jobs and11 supplied raw job logs are copied under `ci/`; original timestamps and hashes remain intact. `ci-inspection.json` records fresh inspection, not a fabricated fresh CI execution time. Docs jobs have successful API step metadata; their raw logs were not supplied, so no claim is made to have read those missing raw logs.

Full framework shards:26+25+27+25=103 passed,0 failed,1 explicit **aai-state SKIP** (exit42, not attested). Selected-mode job is correctly skipped because mode=full; final gate reports full=success. Self-hosting smoke and native seeder jobs succeed. Windows5.1 and pwsh7 each153pass/0fail/4 documented POSIX-only skips; WSL1 leg153/0/4; Linux Pester157/0/0. Each native scope matrix includes all8 preflight cases; no scope case is counted from an old1691/804 run. Native capture diagnostic preserves exit7 and Stop preference. The retained assembly review predates alias metadata and is not represented as an alias review.

## Failure categories and limitations

**B1 — missing original evidence.** SPEC0210 explicitly names `docs/ai/tdd/pr-capability-preflight-red.log`. It is absent on disk, absent from supplied recovery commit e3c26ff7, and has no entry in available `git log --all -- <path>`. The historical corrected180720 and205748 Validation reports say they read a disclosed parseable-no-op baseline and the old red-check log says ACCEPTED. Those assertions do not provide the original bytes. Current8+2+2 mutation replays establish behavioral sensitivity; they cannot attest RED-before-implementation chronology or restore the missing original. Recover the authentic original log/baseline provenance from retained original artifacts and bind its bytes; do not manufacture or restamp a replacement as historical evidence. No source repair is indicated by this finding.

**Validator infrastructure, resolved:** initial runner setup pointed to an evidence directory created in the scratch copy instead of the real report destination; redirections failed before tests ran. Creating the authorized new evidence destination resolved it. Initial corpus helper assumed an exact Status column after a loose header match and raised KeyError; corrected exact-column detection produced216-spec/210-table scan. The generic replay's D7 tripwire above was caused by the validator's scratch helper creation; serial stable rerun passed. These attempts are not product RED.

**Carried limitations:** Azure live authenticated adoption/downstream incident and future PR-create permission remain unverified. Prose ordering cannot guarantee arbitrary future agent compliance. Actual serving-model independence cannot be attested. N1 is genuinely filed P3 `fu-review-log-attribution`, not fixed. `fu-amend-spec-pr-capability-preflight`, `fu-amend-spec-pr-generic-url-validity`, and `fu-amend-spec-pr-github-case-identity` remain open; no owner signatures are fabricated. Full CI's named aai-state skip remains a skip, not a pass. The historical alias report describes621 report/review files; the available Git804 enumerates605, all verified unchanged. This validation does not claim to reconstruct an unavailable621-file pre-rename inventory or the absent original RED log.

## AC gate, integrity, handoff

AC gate **pass**: parent rows are all done and evidenced. Global scan216 specs/210 opted tables finds0 overdue rows; the two deferred rows belong to other specs (0046 due2026-10-17,0209 due2026-10-20). Rule4's14-day rule is per validated spec; parent has no deferred/blocked rows. No AC row or lifecycle metadata was changed.

All2614 tracked paths pass Windows component/case-collision checks; longest relative path136 characters. Six final aliases match original Git804 blobs, bytes and declared SHA256. Five earlier aliases resolve the four intermediate missing transport names and source snapshot; three base64 logs recover original hashes.41 integrated proof artifacts match their manifest. Four base ledgers retain byte-exact base prefixes. Source/test/STATE/index boundary hashes match; all tracked bytes match HEAD. `boundary-corpus.json`, `evidence-integrity.json` and `historical-seals.json` retain enumeration, timing and hashes. No shipping Git/index/STATE/lifecycle/ledger/external mutation was performed.

The outcome checker is intentionally expected to refuse the unknown original-RED outcome. FAIL requires no outcome_report PASS field or success dispatcher. Return only fail/phase commands to the sole STATE writer. Root owns final external sweep and any later merge. This report is a new evidence artifact; old reports remain untouched.

## Outcome binding

```aai-outcome-v1
{
  "version": 1,
  "ref": "pr-capability-preflight",
  "validation_started_utc": "2026-10-08T13:33:06Z",
  "sources": [
    {
      "kind": "intake",
      "path": "docs/issues/CHANGE-0204-pr-capability-preflight.md",
      "sha256": "eae80b7c46f868d3cb930ab70f649f16406a54c0da629e3c4d1bd363fa3b472c"
    },
    {
      "kind": "spec",
      "path": "docs/specs/SPEC-0210-spec-pr-capability-preflight.md",
      "sha256": "24376e354503f0258e9b3236bad501ce7681a7ac0714065babdf831677d7c650"
    }
  ],
  "requirements": [
    {
      "id": "AC-001",
      "source": {
        "path": "docs/issues/CHANGE-0204-pr-capability-preflight.md",
        "quote": "AC-001: Missing or ambiguous repository/remote/source/base identity is refused before provider calls."
      },
      "constraint": "AC-001: Missing or ambiguous repository/remote/source/base identity is refused before provider calls.",
      "spec_ac_ids": [
        "Spec-AC-01"
      ],
      "assessment": "aligned",
      "rationale": "TEST-001 and independent adversarial controls execute real Git identity and exact endpoint refusal before providers.",
      "required": true,
      "outcome_ids": [
        "O-AC-001"
      ]
    },
    {
      "id": "AC-002",
      "source": {
        "path": "docs/issues/CHANGE-0204-pr-capability-preflight.md",
        "quote": "AC-002: Azure client, installed azure-devops extension and authenticated repository read probes are bounded and noninteractive; success reports read verification and unknown create permission."
      },
      "constraint": "AC-002: Azure client, installed azure-devops extension and authenticated repository read probes are bounded and noninteractive; success reports read verification and unknown create permission.",
      "spec_ac_ids": [
        "Spec-AC-02"
      ],
      "assessment": "aligned",
      "rationale": "TEST-002 executes strict Azure argv, environment, closed stdin, Unicode response and unknown create permission.",
      "required": true,
      "outcome_ids": [
        "O-AC-002"
      ]
    },
    {
      "id": "AC-003",
      "source": {
        "path": "docs/issues/CHANGE-0204-pr-capability-preflight.md",
        "quote": "AC-003: Missing client/extension, authentication, network, timeout and unclassified access failures produce a named remedy and nonzero refusal."
      },
      "constraint": "AC-003: Missing client/extension, authentication, network, timeout and unclassified access failures produce a named remedy and nonzero refusal.",
      "spec_ac_ids": [
        "Spec-AC-03"
      ],
      "assessment": "aligned",
      "rationale": "TEST-003..005 exercise named errors, 1000ms timeout, child cleanup and reached secret emitter.",
      "required": true,
      "outcome_ids": [
        "O-AC-003"
      ]
    },
    {
      "id": "AC-004",
      "source": {
        "path": "docs/issues/CHANGE-0204-pr-capability-preflight.md",
        "quote": "AC-004: The PR prompt invokes preflight before numbering, staging, feature/close commit or push; refusal preserves STATE, index, HEAD and reservation refs."
      },
      "constraint": "AC-004: The PR prompt invokes preflight before numbering, staging, feature/close commit or push; refusal preserves STATE, index, HEAD and reservation refs.",
      "spec_ac_ids": [
        "Spec-AC-04"
      ],
      "assessment": "aligned",
      "rationale": "TEST-006 executes refusal preservation snapshots and successful STATE initializer control; prompt ordering read separately.",
      "required": true,
      "outcome_ids": [
        "O-AC-004"
      ]
    },
    {
      "id": "AC-005",
      "source": {
        "path": "docs/issues/CHANGE-0204-pr-capability-preflight.md",
        "quote": "AC-005: Existing GitHub and generic routes remain supported under their explicit readiness contracts."
      },
      "constraint": "AC-005: Existing GitHub and generic routes remain supported under their explicit readiness contracts.",
      "spec_ac_ids": [
        "Spec-AC-05"
      ],
      "assessment": "aligned",
      "rationale": "TEST-007 and independent probes execute GitHub ASCII identity, raw URL refusal, SSH443, generic numeric port and null controls.",
      "required": true,
      "outcome_ids": [
        "O-AC-005"
      ]
    },
    {
      "id": "AC-006",
      "source": {
        "path": "docs/issues/CHANGE-0204-pr-capability-preflight.md",
        "quote": "AC-006: New vendored files are classified and added prompt bytes are accounted for in the prompt-diet ledger and checkpoint."
      },
      "constraint": "AC-006: New vendored files are classified and added prompt bytes are accounted for in the prompt-diet ledger and checkpoint.",
      "spec_ac_ids": [
        "Spec-AC-06"
      ],
      "assessment": "aligned",
      "rationale": "TEST-008 checks profile/suite registration, canonical LF prompt delta and shallow clone controls; exact-head full CI covers companion suites.",
      "required": true,
      "outcome_ids": [
        "O-AC-006"
      ]
    },
    {
      "id": "R-RED",
      "source": {
        "path": "docs/issues/CHANGE-0204-pr-capability-preflight.md",
        "quote": "Capture RED evidence before implementation and independent validation after implementation."
      },
      "constraint": "Capture RED evidence before implementation and independent validation after implementation.",
      "spec_ac_ids": [
        "Spec-AC-01",
        "Spec-AC-02",
        "Spec-AC-03",
        "Spec-AC-04",
        "Spec-AC-05",
        "Spec-AC-06"
      ],
      "assessment": "aligned",
      "rationale": "Original parent RED source is absent; checker exits3. Current mutation replay proves current behavioral sensitivity but cannot establish original pre-implementation chronology.",
      "required": true,
      "outcome_ids": [
        "O-R-RED"
      ]
    },
    {
      "id": "R-SAFETY",
      "source": {
        "path": "docs/issues/CHANGE-0204-pr-capability-preflight.md",
        "quote": "Never install prerequisites automatically or print credentials."
      },
      "constraint": "Never install prerequisites automatically or print credentials.",
      "spec_ac_ids": [
        "Spec-AC-02",
        "Spec-AC-03"
      ],
      "assessment": "aligned",
      "rationale": "Read source and execute exact allowlist client probes and positive-control secret refusal; no install/login/write command.",
      "required": true,
      "outcome_ids": [
        "O-R-SAFETY"
      ]
    },
    {
      "id": "R-PRESERVE",
      "source": {
        "path": "docs/issues/CHANGE-0204-pr-capability-preflight.md",
        "quote": "Preserve unrelated drafts and local work."
      },
      "constraint": "Preserve unrelated drafts and local work.",
      "spec_ac_ids": [
        "Spec-AC-04"
      ],
      "assessment": "aligned",
      "rationale": "Read-back STATE, source, suite and index hashes; base ledgers remain exact prefixes; all experiments confined to the named copy.",
      "required": true,
      "outcome_ids": [
        "O-R-PRESERVE"
      ]
    },
    {
      "id": "R-NATIVE",
      "source": {
        "path": "docs/specs/SPEC-0210-spec-pr-capability-preflight.md",
        "quote": "Mac/Linux Node subprocess green is not Windows proof."
      },
      "constraint": "Mac/Linux Node subprocess green is not Windows proof.",
      "spec_ac_ids": [
        "Spec-AC-02",
        "Spec-AC-03",
        "Spec-AC-06"
      ],
      "assessment": "aligned",
      "rationale": "Inspect immutable exact-head CI run/job metadata and native log counts; original observation timestamps remain in raw logs.",
      "required": true,
      "outcome_ids": [
        "O-R-NATIVE"
      ]
    },
    {
      "id": "R-TRANSPORT",
      "source": {
        "path": "docs/specs/SPEC-0210-spec-pr-capability-preflight.md",
        "quote": "Historical reports/manifests retain original hashes and failure claims; the final transport manifest resolves their old named paths to the exact reconstructed bytes."
      },
      "constraint": "Historical reports/manifests retain original hashes and failure claims; the final transport manifest resolves their old named paths to the exact reconstructed bytes.",
      "spec_ac_ids": [
        "Spec-AC-06"
      ],
      "assessment": "aligned",
      "rationale": "Read-back five transitive aliases and 605 Git804 report/review files; six final aliases separately byte-compared with original Git blobs.",
      "required": true,
      "outcome_ids": [
        "O-R-TRANSPORT"
      ]
    }
  ],
  "outcomes": [
    {
      "id": "O-AC-001",
      "requirement_ids": [
        "AC-001"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740",
        "observed_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740"
      },
      "verification": {
        "operation": "TEST-001 and independent adversarial controls execute real Git identity and exact endpoint refusal before providers.",
        "evidence_path": "docs/ai/reports/pr434-final-validation-20261008T133306Z/preflight.log",
        "evidence_sha256": "31213011010ec1872caa407a1fd5c9ce649b37edbb9528fc557a87c870b1e2fd",
        "observed_at_utc": "2026-10-08T13:43:41Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only CLI verification; executable fixtures are disposable. Saved evidence bytes are hashed; no external write or persistent product output is requested."
      }
    },
    {
      "id": "O-AC-002",
      "requirement_ids": [
        "AC-002"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740",
        "observed_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740"
      },
      "verification": {
        "operation": "TEST-002 executes strict Azure argv, environment, closed stdin, Unicode response and unknown create permission.",
        "evidence_path": "docs/ai/reports/pr434-final-validation-20261008T133306Z/preflight.log",
        "evidence_sha256": "31213011010ec1872caa407a1fd5c9ce649b37edbb9528fc557a87c870b1e2fd",
        "observed_at_utc": "2026-10-08T13:43:41Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only CLI verification; executable fixtures are disposable. Saved evidence bytes are hashed; no external write or persistent product output is requested."
      }
    },
    {
      "id": "O-AC-003",
      "requirement_ids": [
        "AC-003"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740",
        "observed_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740"
      },
      "verification": {
        "operation": "TEST-003..005 exercise named errors, 1000ms timeout, child cleanup and reached secret emitter.",
        "evidence_path": "docs/ai/reports/pr434-final-validation-20261008T133306Z/preflight.log",
        "evidence_sha256": "31213011010ec1872caa407a1fd5c9ce649b37edbb9528fc557a87c870b1e2fd",
        "observed_at_utc": "2026-10-08T13:43:41Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only CLI verification; executable fixtures are disposable. Saved evidence bytes are hashed; no external write or persistent product output is requested."
      }
    },
    {
      "id": "O-AC-004",
      "requirement_ids": [
        "AC-004"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740",
        "observed_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740"
      },
      "verification": {
        "operation": "TEST-006 executes refusal preservation snapshots and successful STATE initializer control; prompt ordering read separately.",
        "evidence_path": "docs/ai/reports/pr434-final-validation-20261008T133306Z/preflight.log",
        "evidence_sha256": "31213011010ec1872caa407a1fd5c9ce649b37edbb9528fc557a87c870b1e2fd",
        "observed_at_utc": "2026-10-08T13:43:41Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only CLI verification; executable fixtures are disposable. Saved evidence bytes are hashed; no external write or persistent product output is requested."
      }
    },
    {
      "id": "O-AC-005",
      "requirement_ids": [
        "AC-005"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740",
        "observed_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740"
      },
      "verification": {
        "operation": "TEST-007 and independent probes execute GitHub ASCII identity, raw URL refusal, SSH443, generic numeric port and null controls.",
        "evidence_path": "docs/ai/reports/pr434-final-validation-20261008T133306Z/preflight.log",
        "evidence_sha256": "31213011010ec1872caa407a1fd5c9ce649b37edbb9528fc557a87c870b1e2fd",
        "observed_at_utc": "2026-10-08T13:43:41Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only CLI verification; executable fixtures are disposable. Saved evidence bytes are hashed; no external write or persistent product output is requested."
      }
    },
    {
      "id": "O-AC-006",
      "requirement_ids": [
        "AC-006"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740",
        "observed_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740"
      },
      "verification": {
        "operation": "TEST-008 checks profile/suite registration, canonical LF prompt delta and shallow clone controls; exact-head full CI covers companion suites.",
        "evidence_path": "docs/ai/reports/pr434-final-validation-20261008T133306Z/preflight.log",
        "evidence_sha256": "31213011010ec1872caa407a1fd5c9ce649b37edbb9528fc557a87c870b1e2fd",
        "observed_at_utc": "2026-10-08T13:43:41Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only CLI verification; executable fixtures are disposable. Saved evidence bytes are hashed; no external write or persistent product output is requested."
      }
    },
    {
      "id": "O-R-RED",
      "requirement_ids": [
        "R-RED"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740",
        "observed_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740"
      },
      "verification": {
        "operation": "Original parent RED source is absent; checker exits3. Current mutation replay proves current behavioral sensitivity but cannot establish original pre-implementation chronology.",
        "evidence_path": "docs/ai/reports/pr434-final-validation-20261008T133306Z/red-checks.json",
        "evidence_sha256": "26ec165d27b0d859ebb94f21075a95f04751fdd871a47a91c5329c688bc1e57e",
        "observed_at_utc": "2026-10-08T13:43:41Z",
        "result": "unknown"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only CLI verification; executable fixtures are disposable. Saved evidence bytes are hashed; no external write or persistent product output is requested."
      }
    },
    {
      "id": "O-R-SAFETY",
      "requirement_ids": [
        "R-SAFETY"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740",
        "observed_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740"
      },
      "verification": {
        "operation": "Read source and execute exact allowlist client probes and positive-control secret refusal; no install/login/write command.",
        "evidence_path": "docs/ai/reports/pr434-final-validation-20261008T133306Z/preflight.log",
        "evidence_sha256": "31213011010ec1872caa407a1fd5c9ce649b37edbb9528fc557a87c870b1e2fd",
        "observed_at_utc": "2026-10-08T13:43:41Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only CLI verification; executable fixtures are disposable. Saved evidence bytes are hashed; no external write or persistent product output is requested."
      }
    },
    {
      "id": "O-R-PRESERVE",
      "requirement_ids": [
        "R-PRESERVE"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740",
        "observed_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740"
      },
      "verification": {
        "operation": "Read-back STATE, source, suite and index hashes; base ledgers remain exact prefixes; all experiments confined to the named copy.",
        "evidence_path": "docs/ai/reports/pr434-final-validation-20261008T133306Z/boundary-corpus.json",
        "evidence_sha256": "e5f7b38ce46ce904ee37d1330a5609f7279dc81aeed88f2ef11228698672b6e2",
        "observed_at_utc": "2026-10-08T13:43:41Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only CLI verification; executable fixtures are disposable. Saved evidence bytes are hashed; no external write or persistent product output is requested."
      }
    },
    {
      "id": "O-R-NATIVE",
      "requirement_ids": [
        "R-NATIVE"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740",
        "observed_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740"
      },
      "verification": {
        "operation": "Inspect immutable exact-head CI run/job metadata and native log counts; original observation timestamps remain in raw logs.",
        "evidence_path": "docs/ai/reports/pr434-final-validation-20261008T133306Z/ci-inspection.json",
        "evidence_sha256": "92134ac8e52ecbd55881ce0aed299b539dcd926ac6ec3affcc2e7a9e21e59c2e",
        "observed_at_utc": "2026-10-08T13:43:41Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only CLI verification; executable fixtures are disposable. Saved evidence bytes are hashed; no external write or persistent product output is requested."
      }
    },
    {
      "id": "O-R-TRANSPORT",
      "requirement_ids": [
        "R-TRANSPORT"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740",
        "observed_identity": "/private/tmp/aai-pr-capability-preflight@9d90d1e4dad24ff56f69a938f87c97510d61b740"
      },
      "verification": {
        "operation": "Read-back five transitive aliases and 605 Git804 report/review files; six final aliases separately byte-compared with original Git blobs.",
        "evidence_path": "docs/ai/reports/pr434-final-validation-20261008T133306Z/historical-seals.json",
        "evidence_sha256": "f1c807b761634f3b69d83a4d3d2fa2f3f40d00574541d23c2930c128437dec16",
        "observed_at_utc": "2026-10-08T13:43:41Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only CLI verification; executable fixtures are disposable. Saved evidence bytes are hashed; no external write or persistent product output is requested."
      }
    }
  ]
}
```
