# Validation — pr-generic-url-validity

- Verdict: **FAIL**
- Round: intermediate, lightweight lane (ceremony level 1).
- Started UTC: 2026-10-08T09:34:49Z.
- Branch/base: fix/pr-generic-url-validity / 1691558c034e13258a31b8288df5642f6263a8cb; uncommitted manifest delivery.
- Independence: fresh isolated validator context using repository artifacts only. Requested validator model gpt-6-sol and implementer model gpt-6-luna; actual serving identities were not exposed, so distinct serving models cannot be attested.
- Source and test hashes match the maker manifest at handoff.

## Coverage

| Requirement | Spec | Evidence | Result |
|---|---|---|---|
| R1 malformed scheme refusal | Spec-AC-01 / TEST-001 | test-001.log, stored RED | pass |
| R2 lawful generic/local controls | Spec-AC-02 / TEST-007 | test-007.log, stored RED | pass |
| R3 exact destination/provider controls | Spec-AC-01,02 | full8.log, all eight rows pass | pass |
| R4 TDD anti-tautology | Spec Test Plan | both RED logs accepted as product_red; mutation-replay.log 2/2 behavioral RED | pass |
| R5 declared child scope | Spec Scope | scope-diff.log; source/test hashes rechecked; delimiter unchanged | pass for child paths |
| R6 frozen spec amendment | Spec Amendment debt | selected-core.log; strict gate names SPEC-0211 | **fail** |

## Failures by category

- **Child process gate:** `node .aai/scripts/spec-amend.mjs --strict` exits 1: SPEC-0211 current projection differs from `frozen_sha256` without an explaining amendment record. Selected `aai-spec-amend` fails for the same reason. This is the primary FAIL reason. The spec AC rows are already marked done while frontmatter remains implementing; Validation did not alter them.
- **Repository-wide suite drift:** selected `aai-docs-audit` fails TEST-1349 because the live strict audit says NEEDS-TRIAGE, naming previously blocked parent pr-capability-preflight as probable-false-open. This does not refute the child URL behavior but blocks an all-green selected/core sweep.
- **Pre-merge proof pending:** no child PR exists yet. Selector maps changed paths to selected/core and DROPPED 97. The future PR requires `ci-full` for lightweight-lane pre-merge full-suite proof; the label and CI run are unverified. Native Windows extraction and parent assembly remain downstream gates.

## Evidence log

| Command / check | Exit | Observation |
|---|---:|---|
| wrapper: `bash tests/skills/test-aai-pr-preflight.sh test_001` | 0 | malformed schemes refuse, zero providers; lawful GitHub three calls |
| wrapper: `bash tests/skills/test-aai-pr-preflight.sh test_007` | 0 | generic numeric port and local controls; malformed generic refusal |
| wrapper: `bash tests/skills/test-aai-pr-preflight.sh` | 0 | all eight named rows pass |
| selected/core `test-framework.sh` | 130 | interrupted during long hygiene rerun; six completed results: four pass, two fail |
| wrapper: `bash tests/skills/test-aai-hygiene-pack.sh` | 0 | standalone run completes all hygiene checks |
| wrapper: `node .aai/scripts/mutation-run.mjs --replay --spec SPEC-0211` in private copy | 0 | 2/2 records redden; zero inconclusive |
| `node .aai/scripts/tdd-evidence-check.mjs --red <each child RED log>` | 0, 0 | both accepted as product_red |
| `node .aai/scripts/spec-lint.mjs --path SPEC-0211` | 0 | no structural findings |
| `node .aai/scripts/docs-audit.mjs --gate SPEC-0211` | 0 | AC status table gate pass |
| `node .aai/scripts/docs-audit.mjs --ac-flip-check SPEC-0211` | 0 | AC flip check pass |
| global Review-By scan | 0 | 216 specs; 210 opted in; 1,540 rows; no overdue rows |
| `git diff --check`; `node --check .aai/scripts/pr-preflight.mjs` | 0, 0 | no whitespace or parse error |
| `validation-outcome-check.mjs --report ... --ref ... --since ... --root ...` | 1 | checker cannot bind sources from absent `.aai/STATE.yaml`; explicit source flags required |
| same checker with `--intake ISSUE-0094 --spec SPEC-0211` | 1 | outcome O6 correctly refused as violated; PASS inadmissible |

Code review gate: **required_not_run**. AC status gate: **pass**. No child STATE, index, source, spec, intake, parent evidence or lifecycle file was changed by Validation.

```aai-outcome-v1
{
  "version": 1,
  "ref": "pr-generic-url-validity",
  "validation_started_utc": "2026-10-08T09:34:49Z",
  "sources": [
    {
      "kind": "intake",
      "path": "docs/issues/ISSUE-0094-pr-generic-url-validity.md",
      "sha256": "f33a3b26a7696a89abfcc2a211a3f2ce9fbfd56c2b5e11dabcdf602646daf77d"
    },
    {
      "kind": "spec",
      "path": "docs/specs/SPEC-0211-spec-pr-generic-url-validity.md",
      "sha256": "a0a41268b56781c4c59a3d2b316ebf81943a9c50434de39abf41f0e410005eb1"
    }
  ],
  "requirements": [
    {
      "id": "R1",
      "source": {
        "path": "docs/issues/ISSUE-0094-pr-generic-url-validity.md",
        "quote": "Malformed explicit scheme URLs return exit 2 / IDENTITY_INVALID before generic success or provider calls."
      },
      "constraint": "Malformed explicit scheme URLs refuse with exit 2 and zero providers.",
      "spec_ac_ids": [
        "Spec-AC-01"
      ],
      "assessment": "aligned",
      "rationale": "The frozen spec maps this original requirement to the named integration rows or evidence contract.",
      "required": true,
      "outcome_ids": [
        "O1"
      ]
    },
    {
      "id": "R2",
      "source": {
        "path": "docs/issues/ISSUE-0094-pr-generic-url-validity.md",
        "quote": "Lawful unrecognized-host URLs and explicit local mode retain CAPABILITY_NOT_APPLICABLE."
      },
      "constraint": "Valid generic and local routes return exit 0 with zero providers.",
      "spec_ac_ids": [
        "Spec-AC-02"
      ],
      "assessment": "aligned",
      "rationale": "The frozen spec maps this original requirement to the named integration rows or evidence contract.",
      "required": true,
      "outcome_ids": [
        "O2"
      ]
    },
    {
      "id": "R3",
      "source": {
        "path": "docs/issues/ISSUE-0094-pr-generic-url-validity.md",
        "quote": "Exact effective fetch/push equality is invariant."
      },
      "constraint": "Effective fetch and push identities agree before provider calls.",
      "spec_ac_ids": [
        "Spec-AC-01",
        "Spec-AC-02"
      ],
      "assessment": "aligned",
      "rationale": "The frozen spec maps this original requirement to the named integration rows or evidence contract.",
      "required": true,
      "outcome_ids": [
        "O3"
      ]
    },
    {
      "id": "R4",
      "source": {
        "path": "docs/specs/SPEC-0211-spec-pr-generic-url-validity.md",
        "quote": "Stored behavioral RED per both gating rows plus focused GREEN and checked mutation replay are required by tdd."
      },
      "constraint": "Both rows have behavioral RED, fresh GREEN and replayable mutations.",
      "spec_ac_ids": [
        "Spec-AC-01",
        "Spec-AC-02"
      ],
      "assessment": "aligned",
      "rationale": "The frozen spec maps this original requirement to the named integration rows or evidence contract.",
      "required": true,
      "outcome_ids": [
        "O4"
      ]
    },
    {
      "id": "R5",
      "source": {
        "path": "docs/issues/ISSUE-0094-pr-generic-url-validity.md",
        "quote": "Preserve parent evidence and staged dependencies."
      },
      "constraint": "Child source changes stay scoped and preserve parent evidence and matrix delimiters.",
      "spec_ac_ids": [
        "Spec-AC-01",
        "Spec-AC-02"
      ],
      "assessment": "aligned",
      "rationale": "The frozen spec maps this original requirement to the named integration rows or evidence contract.",
      "required": true,
      "outcome_ids": [
        "O5"
      ]
    },
    {
      "id": "R6",
      "source": {
        "path": "docs/specs/SPEC-0211-spec-pr-generic-url-validity.md",
        "quote": "Each child may update only its own planned contract through the canonical amendment mechanism if it grows after freeze."
      },
      "constraint": "Post-freeze child spec content must have a matching amendment record and anchor.",
      "spec_ac_ids": [
        "Spec-AC-01",
        "Spec-AC-02"
      ],
      "assessment": "aligned",
      "rationale": "The frozen spec covers the requirement; R6 implementation violates its amendment rule.",
      "required": true,
      "outcome_ids": [
        "O6"
      ]
    }
  ],
  "outcomes": [
    {
      "id": "O1",
      "requirement_ids": [
        "R1"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-generic-url-validity:.aai/scripts/pr-preflight.mjs@sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958",
        "observed_identity": "fix/pr-generic-url-validity:.aai/scripts/pr-preflight.mjs@sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958"
      },
      "verification": {
        "operation": "Execute TEST-001 malformed URL and provider controls",
        "evidence_path": "docs/ai/reports/VALIDATION-20261008T093449Z-pr-generic-url-validity.evidence/test-001.log",
        "evidence_sha256": "d0d93885f93b753e336ae89b3a201583b31ea23c715331994ed3aac0c80d6cd4",
        "observed_at_utc": "2026-10-08T09:36:07Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Invocation-time CLI or repository gate behavior; hashed evidence records the observation."
      }
    },
    {
      "id": "O2",
      "requirement_ids": [
        "R2"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-generic-url-validity:.aai/scripts/pr-preflight.mjs@sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958",
        "observed_identity": "fix/pr-generic-url-validity:.aai/scripts/pr-preflight.mjs@sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958"
      },
      "verification": {
        "operation": "Execute TEST-007 generic, numeric port, malformed port and local controls",
        "evidence_path": "docs/ai/reports/VALIDATION-20261008T093449Z-pr-generic-url-validity.evidence/test-007.log",
        "evidence_sha256": "2d0d37248234b4ae589b010607f367f115e689f35a5ba59e311879aa99e68f1c",
        "observed_at_utc": "2026-10-08T09:36:35Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Invocation-time CLI or repository gate behavior; hashed evidence records the observation."
      }
    },
    {
      "id": "O3",
      "requirement_ids": [
        "R3"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-generic-url-validity:.aai/scripts/pr-preflight.mjs@sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958",
        "observed_identity": "fix/pr-generic-url-validity:.aai/scripts/pr-preflight.mjs@sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958"
      },
      "verification": {
        "operation": "Execute eight integration rows across Git identity, providers and JSON result",
        "evidence_path": "docs/ai/reports/VALIDATION-20261008T093449Z-pr-generic-url-validity.evidence/full8.log",
        "evidence_sha256": "a1d80e2b4f042662613a09a43e315930e6fa961c380ff98fad6e78d002f19bd3",
        "observed_at_utc": "2026-10-08T09:37:41Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Invocation-time CLI or repository gate behavior; hashed evidence records the observation."
      }
    },
    {
      "id": "O4",
      "requirement_ids": [
        "R4"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-generic-url-validity:.aai/scripts/pr-preflight.mjs@sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958",
        "observed_identity": "fix/pr-generic-url-validity:.aai/scripts/pr-preflight.mjs@sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958"
      },
      "verification": {
        "operation": "Replay two behavioral mutations in a private copy",
        "evidence_path": "docs/ai/reports/VALIDATION-20261008T093449Z-pr-generic-url-validity.evidence/mutation-replay.log",
        "evidence_sha256": "b6701cf32712c05dd0ac97059032b6379a646f05c7618649c6f0f5a9ed0a4d4a",
        "observed_at_utc": "2026-10-08T09:49:27Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Invocation-time CLI or repository gate behavior; hashed evidence records the observation."
      }
    },
    {
      "id": "O5",
      "requirement_ids": [
        "R5"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-generic-url-validity:.aai/scripts/pr-preflight.mjs@sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958",
        "observed_identity": "fix/pr-generic-url-validity:.aai/scripts/pr-preflight.mjs@sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958"
      },
      "verification": {
        "operation": "Read back exact child scope diff",
        "evidence_path": "docs/ai/reports/VALIDATION-20261008T093449Z-pr-generic-url-validity.evidence/scope-diff.log",
        "evidence_sha256": "9da8559e4b96f95cb41bc7701c3df816547cbfb7541b121824e1ea9af8c2b879",
        "observed_at_utc": "2026-10-08T09:56:14Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Invocation-time CLI or repository gate behavior; hashed evidence records the observation."
      }
    },
    {
      "id": "O6",
      "requirement_ids": [
        "R6"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-generic-url-validity:docs/specs/SPEC-0211-spec-pr-generic-url-validity.md",
        "observed_identity": "fix/pr-generic-url-validity:docs/specs/SPEC-0211-spec-pr-generic-url-validity.md"
      },
      "verification": {
        "operation": "Execute strict amendment gate and selected/core suites",
        "evidence_path": "docs/ai/reports/VALIDATION-20261008T093449Z-pr-generic-url-validity.evidence/selected-core.log",
        "evidence_sha256": "4b63875f40b1523e09eeb067190c52c608a4abf6040cdd70dc186cc496f94160",
        "observed_at_utc": "2026-10-08T09:48:16Z",
        "result": "violated"
      },
      "persistence": {
        "applicable": false,
        "reason": "Invocation-time CLI or repository gate behavior; hashed evidence records the observation."
      }
    }
  ]
}
```
