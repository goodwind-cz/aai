# Validation — pr-generic-url-validity

- Verdict: **PASS for this child validation scope**.
- Round: intermediate, lightweight lane (ceremony level 1).
- Started UTC: 2026-10-08T10:13:36Z.
- Independence: fresh validator context, repository artifacts only. Requested gpt-6-sol differs from maker request gpt-6-luna; actual serving identities unavailable.
- Branch/base: fix/pr-generic-url-validity / 1691558c034e13258a31b8288df5642f6263a8cb.
- Current source/test SHA-256: a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958 / 7de8c1cb5460254a314e8df2232296e18e007e5b109da42e5ef78ec35326331c.

## Coverage

| Requirement | Spec | Evidence | Result |
|---|---|---|---|
| R1 malformed scheme refusal | Spec-AC-01 / TEST-001 | test001.log, stored product RED | pass |
| R2 lawful generic/local routes | Spec-AC-02 / TEST-007 | test007.log, stored product RED | pass |
| R3 exact destination/provider controls | Spec-AC-01,02 | full8.log, eight passes | pass |
| R4 TDD anti-tautology | Spec Test Plan | two accepted RED logs; prior independent mutation replay 2/2; proof.json binds unchanged source/test hashes | pass; replay historical |
| R5 scoped preservation | Intake constraints / Spec Scope | proof.json; prior scope diff | pass for child paths |
| R6 frozen spec amendment | Spec amendment rule | amend.log, spec-amend suite, measurement record at 10:04:58Z | pass; unsigned contract debt open |

## Metadata and limits

Parent intake remains implementing with umbrella: true, the owner split decision, and two child refs. Strict docs audit is CLEAN and names the parent as deliberately open. Parent Review FAIL remains. Existing PR434 carries ci-full per the root-observed GitHub response, which triggers full mode on a future source push; assembled-source CI is still owed.

Global opted-in AC review scan found two deferred rows due 2026-10-17 and 2026-10-20; neither is overdue on 2026-10-08. SPEC-0211 has no deferred/blocked row. Its done rows predate this validator and were not changed here. The AC gate and flip guard both pass.

## Evidence log

| Command | Exit | Observation |
|---|---:|---|
| wrapper: bash tests/skills/test-aai-pr-preflight.sh test_001 | 0 | malformed refusal; lawful three-provider control |
| wrapper: bash tests/skills/test-aai-pr-preflight.sh test_007 | 0 | generic/local positives and malformed refusal |
| wrapper: bash tests/skills/test-aai-pr-preflight.sh | 0 | eight of eight rows pass |
| wrapper: bash tests/skills/test-aai-spec-amend.sh | 0 | suite pass |
| wrapper: bash tests/skills/test-aai-docs-audit.sh | 0 | suite pass including real corpus |
| node .aai/scripts/spec-amend.mjs --strict | 0 | 299 records, zero unsigned-untracked |
| node .aai/scripts/docs-audit.mjs --no-event --strict | 0 | CLEAN; 571 docs, 2 umbrellas |
| node .aai/scripts/docs-audit.mjs --gate SPEC-0211 | 0 | AC table complete |
| node .aai/scripts/docs-audit.mjs --ac-flip-check SPEC-0211 | 0 | no delivery citation ahead of close |
| tdd-evidence-check.mjs --red each stored RED log | 0,0 | product_red |
| git diff --check; node --check pr-preflight.mjs | 0,0 | clean |

No new failure. The prior framework aggregate ended 130 and is not represented as green; completed results and bounded hygiene rerun stay in the prior report. Native Windows, full assembled-source CI, parent review/validation, and external sweep remain owed. Code review gate: **required_not_run**. AC status gate: **pass**.

```aai-outcome-v1
{
  "version": 1,
  "ref": "pr-generic-url-validity",
  "validation_started_utc": "2026-10-08T10:13:36Z",
  "sources": [
    {
      "kind": "intake",
      "path": "docs/issues/ISSUE-0094-pr-generic-url-validity.md",
      "sha256": "f33a3b26a7696a89abfcc2a211a3f2ce9fbfd56c2b5e11dabcdf602646daf77d"
    },
    {
      "kind": "spec",
      "path": "docs/specs/SPEC-0211-spec-pr-generic-url-validity.md",
      "sha256": "c601aa55033616636b10f306a1b897e5e9c46bc232e94939db341f9db2646018"
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
      "rationale": "Measurement amendment explains changed evidence summary and strict gate passes; unsigned contract debt remains open.",
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
        "evidence_path": "docs/ai/reports/validation-20261008T101336Z-pr-generic-url-validity/test001.log",
        "evidence_sha256": "7300560ffac10505b9cd31a6a54ba71cd5cf7d9c7f96dd01fdb3e3235e7f3bb9",
        "observed_at_utc": "2026-10-08T10:14:34.392Z",
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
        "evidence_path": "docs/ai/reports/validation-20261008T101336Z-pr-generic-url-validity/test007.log",
        "evidence_sha256": "f8407301131097ba7007c9f9e27a033cf151398d6ed9bca520e1b95707e80559",
        "observed_at_utc": "2026-10-08T10:14:57.243Z",
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
        "evidence_path": "docs/ai/reports/validation-20261008T101336Z-pr-generic-url-validity/full8.log",
        "evidence_sha256": "453d2da4d502456cb485346e444ac7e3a9fe5f65a783ee7248c9aa871581be13",
        "observed_at_utc": "2026-10-08T10:19:16.293Z",
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
        "operation": "Verify unchanged source/test hashes and stored product RED plus prior mutation replay; replay not repeated this round",
        "evidence_path": "docs/ai/reports/validation-20261008T101336Z-pr-generic-url-validity/proof.json",
        "evidence_sha256": "f18240eee12e5592a920e3964d01309d78d7313c6933ce77fa25106ad48839e4",
        "observed_at_utc": "2026-10-08T10:20:01.197Z",
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
        "operation": "Verify scoped current source/test hashes and parent metadata",
        "evidence_path": "docs/ai/reports/validation-20261008T101336Z-pr-generic-url-validity/proof.json",
        "evidence_sha256": "f18240eee12e5592a920e3964d01309d78d7313c6933ce77fa25106ad48839e4",
        "observed_at_utc": "2026-10-08T10:20:01.197Z",
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
        "operation": "Run strict spec amendment gate after measurement record",
        "evidence_path": "docs/ai/reports/validation-20261008T101336Z-pr-generic-url-validity/amend.log",
        "evidence_sha256": "5285c77df645dae0ad57f0dd2c8b37a609765b688ad844069653611a9be0b74f",
        "observed_at_utc": "2026-10-08T10:19:27.173Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Invocation-time CLI or repository gate behavior; hashed evidence records the observation."
      }
    }
  ]
}
```
