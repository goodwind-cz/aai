# Final parent Validation recheck — PR434

Verdict: **PASS** for current reviewed source plus recovered historical evidence. Code review gate: **pass** (retained independent assembly dual PASS). AC status gate: **pass**. This is a new validation outcome, not a rewrite of the genuine earlier FAIL. Final metadata-commit CI and the external review sweep remain the root orchestrator's delivery work.

## Scope and independence

System-clock start: 2026-10-08T13:49:48Z. Fresh independent Validation context; no implementation conversation used. Requested validator gpt-6-astra and requested maker gpt-6-luna differ, but actual serving weights are unknown. No claim of weight-level independence. Original intake CHANGE-0204, frozen SPEC-0210, owner split decision, technology contract, source, relevant test/prose boundaries and recorded artifacts were independently read. This validation uses the explicit final-delivery override, not the default rule6 Planning dispatch for already-done documents. STATE was active, human_input.required=false and strategy=tdd. No STATE, lifecycle, Git/index, external or old evidence writes were made. No delegation: the requirements share the identity/provider/ceremony boundary and are not independent groups.

Complete scope: bdeb425c040ada918dd97e5b878b71e420bad83a..9d90d1e4dad24ff56f69a938f87c97510d61b740 plus restored original RED bytes. Source SHA256 e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf and suite SHA256 239206e806eff008083c8c1b081587760aa0ec9f4094fe7336a7404dc169df7c match the supplied boundary. All 2614 tracked files match HEAD. The .aai/tests diff from reviewed 8701da75 to HEAD is empty. The prior full-scope inspection covers 1002 changed paths; its 46 sealed report/evidence files were hash-and-size verified unchanged. Prior findings and observations are reused explicitly, not described as new executions.

## Requirement coverage

| Requirement | Spec | Implementation and executable evidence |
|---|---|---|
| AC-001 explicit unambiguous repository/remote/source/base | Spec-AC-01 | CLI identity/raw URL checks; fresh TEST001 plus malformed port, dot-path, password and endpoint mismatch probes |
| AC-002 bounded noninteractive Azure read; create unknown | Spec-AC-02 | probe/readiness/launcher; fresh TEST002 exact argv, closed stdin, inherited environment controls and split UTF8; prior exact-head native matrix |
| AC-003 named safe failures and bounded cleanup | Spec-AC-03 | Refusal, byte/time caps; fresh TEST003–005; 1495ms timeout, child_alive=false, later_probes=0; reached secret emitter |
| AC-004 preflight before writes, preserve local state | Spec-AC-04 | SKILL_PR preconditions and CLI; fresh TEST006 origin/alternate/null and STATE/index/HEAD/reservation preservation; source/prose ordering read |
| AC-005 GitHub and generic contracts retained | Spec-AC-05 | identity ASCII folding and literal endpoint equality; fresh TEST007, public/enterprise combined-case, Unicode distinction, generic numeric-port redaction/null controls |
| AC-006 classification, selection and measured prompt bytes | Spec-AC-06 | profiles/map/diet and fixture companions; fresh TEST008 LF/CRLF, shallow clone, captured stderr and delayed/hung replay controls; exact-head full CI |
| RED before implementation | Test Plan / Evidence by strategy | Original maker test exit1 and checker0 at 2026-10-07T12:26:40.910Z; authentic full read at 14:02:46.776Z; independent extraction and current checker0; fresh 8+2+2 mutation RED |
| No auto-install/credential disclosure; preserve unrelated work | Provider/ceremony seams | Read-only source, strict argv allowlists, reached secret control, fresh boundary pins and tracked-byte equality |
| Native platform proof | Verification | Captured Windows5.1/pwsh7/WSL1/Linux execution on exactly current HEAD; fresh identity/log read-back |
| Historical evidence preservation | Evidence contract | 46 sealed files unchanged, current tracked bytes unchanged; prior six-alias/five-transitive-alias/605-file transport audit retained with original timestamps |

No intake requirement was omitted or weakened. The complete source-quoted requirement inventory is in the machine-readable block below. Its observations of old material are new **read-back inspections**, never claims of rerunning old CI or original RED.

## Recovered RED evidence

Independent comparison against both original preserved session files matches complete call/output records, including their ordinals, timestamps and call IDs. The historical cat command names four artifacts in order: original RED, mutation replay, native Windows status, Pester baseline. Extraction starts at RED_CLASS and ends immediately before the next lower-case `command: node .aai/scripts/mutation-run.mjs --replay --spec` marker. It contains exactly TEST001..008 FAIL rows, Unicode 雪, the original header and terminal newline. All 1740 UTF8 bytes match both recovery original-red.log and restored docs/ai/tdd/pr-capability-preflight-red.log. SHA256 dfe1829c14b3bb4fe9f2c28f3cb89be248777381553b8e108fc870df4bf85fab is a **current recovery hash**; no historical original hash exists or is claimed.

The preserved maker tool call actually ran a disclosed parseable no-op baseline through the wrapper, captured exit1, wrote the evidence header plus raw stdout, and obtained checker acceptance (exit0). The baseline retained in docs/ai/tdd/spec-pr-capability-preflight/baseline.mjs matches that disclosed no-op. Original prompt/distribution failures are explicitly named for TEST006/008. This is authentic historical product RED, not a newly simulated run. Recovery closes earlier B1; the old report and its unknown outcome/checker refusal remain unchanged.

## Commands and outcomes

Evidence is under docs/ai/reports/pr434-final-recheck-20261008T134948Z/. Fresh tests ran in the ONE authorized standalone copy /private/tmp/aai-pr434-final-recheck-scratch. Wrapper, fixture TMPDIR and all mutation experiments stayed there. The wrapper's AAI_TEST_ISOLATION=0 wording calls its cwd shipping; that cwd was the copy. Step epochs and post-step reapers were used by run-validation.sh and run-adversarial.sh, with zero survivors.

| Command | Exit | Evidence |
|---|---:|---|
| wrapper + bash tests/skills/test-aai-pr-preflight.sh | 0 | preflight.log: 8 named PASS |
| wrapper + node .aai/scripts/mutation-run.mjs --replay --spec SPEC-0210 path | 0 | parent-replay.log: 8/8 RED, 0 inconclusive, 0 restamped |
| same replay, SPEC-0211 path | 0 | generic-replay.log: 2/2 RED, 0 inconclusive, 0 restamped |
| same replay, SPEC-0212 path | 0 | case-replay.log: 2/2 RED, 0 inconclusive, 0 restamped |
| wrapper + sealed prior adversarial.cjs, scratch root, 007 | 0 | adversarial-reaped.log: 11 positive/negative seam probes |
| node .aai/scripts/tdd-evidence-check.mjs --red docs/ai/tdd/pr-capability-preflight-red.log | 0 | red-check.log: ACCEPTED product_red |
| node .aai/scripts/docs-audit.mjs --gate SPEC-0210 | 0 | ac-gate.log: all rows terminal/evidenced, Review-By valid |
| node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0210-spec-pr-capability-preflight.md | 0 | spec-lint.log: no structural findings |
| node .aai/scripts/docs-audit.mjs --no-event | 0 | docs-audit.log: CLEAN, 8 report-only unreadable tables and 2 report-only missing-close-telemetry observations |
| independent extraction/seal/boundary/corpus checks | passed assertions | recovery-inspection.json, prior-seals.json, boundary-corpus.json, final-boundary.json |
| python3 inspect-ci.py | 0 | ci-inspection.json: exact-head 3 runs and 11 logs |

This is the final delivery recheck after the prior final FAIL, not a new broad implementation round. Discovery finds 104 framework suites, plus test-framework.sh and test-ps1-quality.sh drivers (106 test-*.sh files), and five Pester files. No browser/e2e config, deployed surface, package build or separate application test runner exists. The explicitly authorized prior **full** exact-head CI supplies the broad sweep; it was not redundantly rerun locally. CI runs 37778220504 (skills), 37778220619 (PowerShell), 37778220735 (docs) are completed/success at 9d90d1e4dad24ff56f69a938f87c97510d61b740. Full shards total 103 PASS, 0 FAIL, 1 named aai-state SKIP; no skip is counted as PASS. Native Windows5.1/pwsh7/WSL1 each show 153/0/4 documented POSIX-only skips; Linux Pester 157/0/0. Every native preflight arm ran. Docs success has API job/step proof; missing raw docs logs are not claimed read. All original CI timestamps remain in the raw captured artifacts. No CI claim is made about a future metadata commit.

## Gates, failure categories and residual limits

AC gate PASS: six parent rows terminal/evidenced. Repo-wide scan: 216 specs, 210 opted tables, zero overdue deferred/blocked rows. The two deferred rows are in other specs, due 2026-10-17 and 2026-10-20; the per-validated-spec 14-day rule has no applicable parent rows. No lifecycle/AC rows/events were edited under the dispatch's freeze.

Product failures: none in this recheck. Evidence completeness: original missing RED now independently verified; earlier FAIL is retained. Validator infrastructure: the first inspection helper incorrectly stripped the source record ordinal, then a later stage used headSha instead of raw REST head_sha; corrected comparisons and the independent CI helper pass. These helper errors are not product RED. The first successful adversarial execution did not preserve its epoch for a separate post-step reaper; it was repeated with the fully recorded wrapper/reaper script, also exit0 and zero survivors. Mutation logs retain named nested-scratch EISDIR exclusions; all 12 records still redden, none inconclusive/restamped. The unsupported checker --help probe exited1 with usage; it is not a validation result.

Carried residuals: live authenticated Azure adoption/downstream reproduction and future create permission remain unverified; prose ordering cannot attest arbitrary future agent obedience. Actual model-weight independence remains unknown. Filed P3 fu-review-log-attribution (N1) remains open, as do the three unsigned-amendment follow-ups for parent/generic/case specs; no signatures or repairs are fabricated. Historical 621-file narrative versus available 605 Git804 report/review inventory remains disclosed. Full CI's aai-state skip remains a skip. The new recovery depends on preserved local harness output rather than an unavailable original historical hash; this provenance and extraction were directly checked.

Verification-before-claim was applied by identifying the scope, rerunning its matrix/replays, reading outputs and comparing identities/hashes before the outcome checker. Root owns STATE merge commands, metadata commit, resulting-head CI, external sweep and owner-directed merge. This report author stops at the checked handoff.

## Outcome binding

```aai-outcome-v1
{
  "version": 1,
  "ref": "pr-capability-preflight",
  "validation_started_utc": "2026-10-08T13:49:48Z",
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
      "rationale": "Independently matched authentic historical tool records, four-artifact cat order and 1740-byte UTF8 extraction, eight product failures, original maker exit1/checker0 and current checker0; current recovery hash is not a historical pin.",
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
      "rationale": "Fresh read-back verifies three successful captured CI runs and 11 raw logs at exact current HEAD; execution timestamps remain historical, not restamped.",
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
      "rationale": "Freshly verified 46 sealed prior files and all 2614 tracked files against unchanged HEAD; reuse prior exact-head six-alias/five-transitive-alias/605-file audit with its original observation times.",
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
        "evidence_path": "docs/ai/reports/pr434-final-recheck-20261008T134948Z/preflight.log",
        "evidence_sha256": "db491b73608748c513cb00d79a3ecfd583ee45c429bf94c20fff9f8d01150b90",
        "observed_at_utc": "2026-10-08T13:56:53.749745+00:00",
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
        "evidence_path": "docs/ai/reports/pr434-final-recheck-20261008T134948Z/preflight.log",
        "evidence_sha256": "db491b73608748c513cb00d79a3ecfd583ee45c429bf94c20fff9f8d01150b90",
        "observed_at_utc": "2026-10-08T13:56:53.749745+00:00",
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
        "evidence_path": "docs/ai/reports/pr434-final-recheck-20261008T134948Z/preflight.log",
        "evidence_sha256": "db491b73608748c513cb00d79a3ecfd583ee45c429bf94c20fff9f8d01150b90",
        "observed_at_utc": "2026-10-08T13:56:53.749745+00:00",
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
        "evidence_path": "docs/ai/reports/pr434-final-recheck-20261008T134948Z/preflight.log",
        "evidence_sha256": "db491b73608748c513cb00d79a3ecfd583ee45c429bf94c20fff9f8d01150b90",
        "observed_at_utc": "2026-10-08T13:56:53.749745+00:00",
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
        "evidence_path": "docs/ai/reports/pr434-final-recheck-20261008T134948Z/preflight.log",
        "evidence_sha256": "db491b73608748c513cb00d79a3ecfd583ee45c429bf94c20fff9f8d01150b90",
        "observed_at_utc": "2026-10-08T13:56:53.749745+00:00",
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
        "evidence_path": "docs/ai/reports/pr434-final-recheck-20261008T134948Z/preflight.log",
        "evidence_sha256": "db491b73608748c513cb00d79a3ecfd583ee45c429bf94c20fff9f8d01150b90",
        "observed_at_utc": "2026-10-08T13:56:53.749745+00:00",
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
        "operation": "Independently matched authentic historical tool records, four-artifact cat order and 1740-byte UTF8 extraction, eight product failures, original maker exit1/checker0 and current checker0; current recovery hash is not a historical pin.",
        "evidence_path": "docs/ai/reports/pr434-final-recheck-20261008T134948Z/recovery-inspection.json",
        "evidence_sha256": "7fa1da1929c75b2cf20e3edff012f2cd4e2cecd84d305a35ea040a9490c07f58",
        "observed_at_utc": "2026-10-08T13:56:53.749745+00:00",
        "result": "satisfied"
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
        "evidence_path": "docs/ai/reports/pr434-final-recheck-20261008T134948Z/preflight.log",
        "evidence_sha256": "db491b73608748c513cb00d79a3ecfd583ee45c429bf94c20fff9f8d01150b90",
        "observed_at_utc": "2026-10-08T13:56:53.749745+00:00",
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
        "evidence_path": "docs/ai/reports/pr434-final-recheck-20261008T134948Z/final-boundary.json",
        "evidence_sha256": "336d200500a06848677aa6881b92aeba13a5339847a6c9c220070845017c1514",
        "observed_at_utc": "2026-10-08T13:56:53.749745+00:00",
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
        "operation": "Fresh read-back verifies three successful captured CI runs and 11 raw logs at exact current HEAD; execution timestamps remain historical, not restamped.",
        "evidence_path": "docs/ai/reports/pr434-final-recheck-20261008T134948Z/ci-inspection.json",
        "evidence_sha256": "1a091e2f49d7495dfacb2b381c98af01b5cbbcbd6c6912a1a7fcb92ed51701be",
        "observed_at_utc": "2026-10-08T13:56:53.749745+00:00",
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
        "operation": "Freshly verified 46 sealed prior files and all 2614 tracked files against unchanged HEAD; reuse prior exact-head six-alias/five-transitive-alias/605-file audit with its original observation times.",
        "evidence_path": "docs/ai/reports/pr434-final-recheck-20261008T134948Z/prior-seals.json",
        "evidence_sha256": "e4c1c3c94d7c223036298d0967a2780d5ed79856f5c52397e6055e409409e580",
        "observed_at_utc": "2026-10-08T13:56:53.749745+00:00",
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
