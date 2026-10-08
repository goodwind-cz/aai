# Validation: pr-github-case-identity

- Verdict: PASS for child scope; parent final assembly, native CI, code review and external sweep remain owed.
- Context isolation: fresh validation context and artifact-only reading; requested maker/validator model identities were not observable.
- Branch/base: fix/pr-github-case-identity / 8dd7a88a59a43ed094088b17361ca08cd13c855a.
- Current source SHA-256: e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf. Current suite SHA-256: 239206e806eff008083c8c1b081587760aa0ec9f4094fe7336a7404dc169df7c.
- Lane: lightweight (ceremony_level 1), declared TEST-001/007 plus adversarial seam probes. This is an intermediate round; parent full framework sweep is owed at close.
- Pre-merge full-suite route: existing PR #434 carried `ci-full` label in retained prior review snapshot; root must confirm the current head and run full CI after integration.
- AC status gate: PASS (`docs-audit --gate SPEC-0212`, exit 0); global scan 216 specs, zero deferred/blocked dated rows.
- Code review gate: required_not_run.
- Lifecycle handoff: spec frontmatter is implementing while maker already set both AC rows done/evidenced. This validator did not edit them or emit ac_evidence. Root must reconcile close-time state under step 8a before close.

## Coverage

| Requirement | Spec | Evidence |
|---|---|---|
| R1 | Spec-AC-01 | docs/ai/reports/pr-github-case-identity-validation-20261008T113526Z/test007.log |
| R2 | Spec-AC-01 | docs/ai/reports/pr-github-case-identity-validation-20261008T113526Z/adversarial007.log |
| R3 | Spec-AC-02 | docs/ai/reports/pr-github-case-identity-validation-20261008T113526Z/test001.log |
| R4 | Spec-AC-02 | docs/ai/reports/pr-github-case-identity-validation-20261008T113526Z/test001.log |
| R5 | Spec-AC-01 | docs/ai/reports/pr-github-case-identity-validation-20261008T113526Z/replay.log |
| R6 | Spec-AC-02 | docs/ai/reports/pr-github-case-identity-validation-20261008T113526Z/test007.log |

## Executable evidence

| Command | Exit | Result |
|---|---:|---|
| wrapper TEST-001 | 0 | PASS; docs/ai/reports/pr-github-case-identity-validation-20261008T113526Z/test001.log |
| wrapper TEST-007 | 0 | PASS; docs/ai/reports/pr-github-case-identity-validation-20261008T113526Z/test007.log |
| wrapper scratch adversarial TEST-007 | 0 | seven refusal controls and PASS; docs/ai/reports/pr-github-case-identity-validation-20261008T113526Z/adversarial007.log |
| wrapper mutation-run --replay --spec docs/specs/SPEC-0212-spec-pr-github-case-identity.md | 0 | 2/2 RED, 0 inconclusive; docs/ai/reports/pr-github-case-identity-validation-20261008T113526Z/replay.log |
| tdd-evidence-check --red docs/ai/tdd/pr-github-case-identity-red.log | 0 | product_red |
| spec-lint --path docs/specs/SPEC-0212-spec-pr-github-case-identity.md | 0 | zero findings |
| docs-audit --gate SPEC-0212 | 0 | gate pass |
| docs-audit --no-event | 0 | clean; unrelated legacy table notes report-only |

## Failures and limits

- Behavioral failures: none in the child scope.
- Infrastructure failures: none; the heartbeat hook degraded with EPERM and does not gate validation.
- Process handoff: root must handle already-terminal AC rows in the open spec, source-bound native/full CI, parent mutation remeasurement, final parent review and close.
- Identity risk: the platform did not expose actual maker/validator model serving identities; context separation is fresh but model difference cannot be independently proved.

```aai-outcome-v1
{
  "version": 1,
  "ref": "pr-github-case-identity",
  "validation_started_utc": "2026-10-08T11:35:26Z",
  "sources": [
    {
      "kind": "intake",
      "path": "docs/issues/ISSUE-0095-pr-github-case-identity.md",
      "sha256": "a8e13b3336790d2e752f66014cdad7720abb78dc05ddaf60584c155a3f73cfae"
    },
    {
      "kind": "spec",
      "path": "docs/specs/SPEC-0212-spec-pr-github-case-identity.md",
      "sha256": "5d79d342483399c5b8c06cc3db31f529312014d1dad53032b825792bc7cbe81a"
    }
  ],
  "requirements": [
    {
      "id": "R1",
      "source": {
        "path": "docs/issues/ISSUE-0095-pr-github-case-identity.md",
        "quote": "Owner/repository spelling differing only by ASCII case is the same GitHub identity for input/remote and provider-result comparison."
      },
      "constraint": "Real CLI reaches READ_VERIFIED with separately varied nameWithOwner and URL path casing",
      "spec_ac_ids": [
        "Spec-AC-01"
      ],
      "assessment": "aligned",
      "rationale": "Read the child intake and frozen spec independently, inspected the current diff, and executed the linked integration evidence.",
      "required": true,
      "outcome_ids": [
        "O1"
      ]
    },
    {
      "id": "R2",
      "source": {
        "path": "docs/issues/ISSUE-0095-pr-github-case-identity.md",
        "quote": "Different owner or repository, host, protocol, userinfo, query and fragment remain refused."
      },
      "constraint": "Real CLI refuses different identities and seven hostile provider fields after three allowlisted reads",
      "spec_ac_ids": [
        "Spec-AC-01"
      ],
      "assessment": "aligned",
      "rationale": "Read the child intake and frozen spec independently, inspected the current diff, and executed the linked integration evidence.",
      "required": true,
      "outcome_ids": [
        "O2"
      ]
    },
    {
      "id": "R3",
      "source": {
        "path": "docs/issues/ISSUE-0095-pr-github-case-identity.md",
        "quote": "Effective fetch/push strings remain exactly equal."
      },
      "constraint": "Real Git effective endpoint divergence refuses before provider reads",
      "spec_ac_ids": [
        "Spec-AC-02"
      ],
      "assessment": "aligned",
      "rationale": "Read the child intake and frozen spec independently, inspected the current diff, and executed the linked integration evidence.",
      "required": true,
      "outcome_ids": [
        "O3"
      ]
    },
    {
      "id": "R4",
      "source": {
        "path": "docs/issues/ISSUE-0095-pr-github-case-identity.md",
        "quote": "Input differing only by casing from the origin is also refused."
      },
      "constraint": "Repaired input case equivalent succeeds; genuinely different owner and repository refuse",
      "spec_ac_ids": [
        "Spec-AC-02"
      ],
      "assessment": "aligned",
      "rationale": "Read the child intake and frozen spec independently, inspected the current diff, and executed the linked integration evidence.",
      "required": true,
      "outcome_ids": [
        "O4"
      ]
    },
    {
      "id": "R5",
      "source": {
        "path": "docs/specs/SPEC-0212-spec-pr-github-case-identity.md",
        "quote": "Stored behavioral RED per both gating rows plus focused GREEN and checked mutation replay are required by tdd."
      },
      "constraint": "Both RED records classified product_red and both mutation patches still redden",
      "spec_ac_ids": [
        "Spec-AC-01"
      ],
      "assessment": "aligned",
      "rationale": "Read the child intake and frozen spec independently, inspected the current diff, and executed the linked integration evidence.",
      "required": true,
      "outcome_ids": [
        "O5"
      ]
    },
    {
      "id": "R6",
      "source": {
        "path": "docs/issues/ISSUE-0095-pr-github-case-identity.md",
        "quote": "No provider writes, secrets acquisition, new dependencies, new vendored files or prompt growth."
      },
      "constraint": "Diff limited to source, existing suite, child spec; strict fixture permits only read probes",
      "spec_ac_ids": [
        "Spec-AC-02"
      ],
      "assessment": "aligned",
      "rationale": "Read the child intake and frozen spec independently, inspected the current diff, and executed the linked integration evidence.",
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
        "expected_identity": "fix/pr-github-case-identity@8dd7a88a59a43ed094088b17361ca08cd13c855a:source-sha256:e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf;test-sha256:239206e806eff008083c8c1b081587760aa0ec9f4094fe7336a7404dc169df7c",
        "observed_identity": "fix/pr-github-case-identity@8dd7a88a59a43ed094088b17361ca08cd13c855a:source-sha256:e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf;test-sha256:239206e806eff008083c8c1b081587760aa0ec9f4094fe7336a7404dc169df7c"
      },
      "verification": {
        "operation": "Real CLI reaches READ_VERIFIED with separately varied nameWithOwner and URL path casing",
        "evidence_path": "docs/ai/reports/pr-github-case-identity-validation-20261008T113526Z/test007.log",
        "evidence_sha256": "e192076cfcd4e396e5ebef914768822254970d6f71998627771fc4b806e29f6c",
        "observed_at_utc": "2026-10-08T11:36:36.204Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Invocation-time CLI behavior; persisted evidence is hashed and read back."
      }
    },
    {
      "id": "O2",
      "requirement_ids": [
        "R2"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-github-case-identity@8dd7a88a59a43ed094088b17361ca08cd13c855a:source-sha256:e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf;test-sha256:239206e806eff008083c8c1b081587760aa0ec9f4094fe7336a7404dc169df7c",
        "observed_identity": "fix/pr-github-case-identity@8dd7a88a59a43ed094088b17361ca08cd13c855a:source-sha256:e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf;test-sha256:239206e806eff008083c8c1b081587760aa0ec9f4094fe7336a7404dc169df7c"
      },
      "verification": {
        "operation": "Real CLI refuses different identities and seven hostile provider fields after three allowlisted reads",
        "evidence_path": "docs/ai/reports/pr-github-case-identity-validation-20261008T113526Z/adversarial007.log",
        "evidence_sha256": "1928d7a905275f98cd945d25778cbd9bf087267fd447c7f7ffc6db17364584e0",
        "observed_at_utc": "2026-10-08T11:38:20.752Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Invocation-time CLI behavior; persisted evidence is hashed and read back."
      }
    },
    {
      "id": "O3",
      "requirement_ids": [
        "R3"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-github-case-identity@8dd7a88a59a43ed094088b17361ca08cd13c855a:source-sha256:e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf;test-sha256:239206e806eff008083c8c1b081587760aa0ec9f4094fe7336a7404dc169df7c",
        "observed_identity": "fix/pr-github-case-identity@8dd7a88a59a43ed094088b17361ca08cd13c855a:source-sha256:e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf;test-sha256:239206e806eff008083c8c1b081587760aa0ec9f4094fe7336a7404dc169df7c"
      },
      "verification": {
        "operation": "Real Git effective endpoint divergence refuses before provider reads",
        "evidence_path": "docs/ai/reports/pr-github-case-identity-validation-20261008T113526Z/test001.log",
        "evidence_sha256": "3a84b09c8a93655498f81bdfef11062c5a2834936ff778010022272f245136be",
        "observed_at_utc": "2026-10-08T11:36:12.834Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Invocation-time CLI behavior; persisted evidence is hashed and read back."
      }
    },
    {
      "id": "O4",
      "requirement_ids": [
        "R4"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-github-case-identity@8dd7a88a59a43ed094088b17361ca08cd13c855a:source-sha256:e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf;test-sha256:239206e806eff008083c8c1b081587760aa0ec9f4094fe7336a7404dc169df7c",
        "observed_identity": "fix/pr-github-case-identity@8dd7a88a59a43ed094088b17361ca08cd13c855a:source-sha256:e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf;test-sha256:239206e806eff008083c8c1b081587760aa0ec9f4094fe7336a7404dc169df7c"
      },
      "verification": {
        "operation": "Repaired input case equivalent succeeds; genuinely different owner and repository refuse",
        "evidence_path": "docs/ai/reports/pr-github-case-identity-validation-20261008T113526Z/test001.log",
        "evidence_sha256": "3a84b09c8a93655498f81bdfef11062c5a2834936ff778010022272f245136be",
        "observed_at_utc": "2026-10-08T11:36:12.834Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Invocation-time CLI behavior; persisted evidence is hashed and read back."
      }
    },
    {
      "id": "O5",
      "requirement_ids": [
        "R5"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-github-case-identity@8dd7a88a59a43ed094088b17361ca08cd13c855a:source-sha256:e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf;test-sha256:239206e806eff008083c8c1b081587760aa0ec9f4094fe7336a7404dc169df7c",
        "observed_identity": "fix/pr-github-case-identity@8dd7a88a59a43ed094088b17361ca08cd13c855a:source-sha256:e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf;test-sha256:239206e806eff008083c8c1b081587760aa0ec9f4094fe7336a7404dc169df7c"
      },
      "verification": {
        "operation": "Both RED records classified product_red and both mutation patches still redden",
        "evidence_path": "docs/ai/reports/pr-github-case-identity-validation-20261008T113526Z/replay.log",
        "evidence_sha256": "477cef02155810cf11aa30b438cbcd9268d92c025dbe50b887456756f55f107c",
        "observed_at_utc": "2026-10-08T11:37:01.421Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Invocation-time CLI behavior; persisted evidence is hashed and read back."
      }
    },
    {
      "id": "O6",
      "requirement_ids": [
        "R6"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-github-case-identity@8dd7a88a59a43ed094088b17361ca08cd13c855a:source-sha256:e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf;test-sha256:239206e806eff008083c8c1b081587760aa0ec9f4094fe7336a7404dc169df7c",
        "observed_identity": "fix/pr-github-case-identity@8dd7a88a59a43ed094088b17361ca08cd13c855a:source-sha256:e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf;test-sha256:239206e806eff008083c8c1b081587760aa0ec9f4094fe7336a7404dc169df7c"
      },
      "verification": {
        "operation": "Diff limited to source, existing suite, child spec; strict fixture permits only read probes",
        "evidence_path": "docs/ai/reports/pr-github-case-identity-validation-20261008T113526Z/test007.log",
        "evidence_sha256": "e192076cfcd4e396e5ebef914768822254970d6f71998627771fc4b806e29f6c",
        "observed_at_utc": "2026-10-08T11:36:36.204Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Invocation-time CLI behavior; persisted evidence is hashed and read back."
      }
    }
  ]
}
```
