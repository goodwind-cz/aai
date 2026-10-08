# Validation — child mutation ancestry remediation

Verdict: **PASS for pr-generic-url-validity child proof only**. The canonical mutation close prerequisite is satisfied. This report does not authorize or claim parent/B2 completion, close execution, native/full CI success, or PR434 merge readiness.

Validation started: 2026-10-08T11:10:30Z. Independent fresh tier-3 CLI context, artifacts only; requested gpt-6-astra, actual serving identity unknown. No claimed weight independence. Dispatched Validation, AAI_ROLE=subagent on executed validation commands; root remains sole Git/index/STATE/lifecycle writer. Current STATE is active, human_input.required false, child phase validation. Source/test maker context was not inherited.

## Scope and requirements

Independently read ISSUE-0094, SPEC-0211, DECISION-pr434-identity-split, retained independent Validation/Review reports, N1 disposition and root/maker remediation artifacts. The decision authorizes the two-child repair and retains final assembly obligations. This is one interdependent evidence-repair group, an intermediate lightweight round, not a new source implementation round. No subagent fan-out was needed.

Branch fix/pr-generic-url-validity; HEAD 6d3f616a96337ff1580968467fadfa9756a87a52. Source SHA-256 a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958; suite 7de8c1cb5460254a314e8df2232296e18e007e5b109da42e5ef78ec35326331c. Intake/spec and source/tests are byte-equal to HEAD and the earlier validated pins. The only tracked delta is the two mutation .txt records and two .patch files. The original historical record base is unavailable to shipping Git (merge-base exit 128); each fresh record names current HEAD, independently accepted by merge-base --is-ancestor (exit 0).

| Requirement | Spec | Implementation / evidence | Result |
|---|---|---|---|
| R1 malformed recognized/generic URL refuses before providers | Spec-AC-01 | validateExplicitUrl before classify; fresh test001.log, positive calls=3 | aligned, pass |
| R2 lawful generic/numeric port/local and redaction preservation | Spec-AC-02 | existing identity branches; fresh test007.log | aligned, pass |
| R3 exact effective destination binding | Spec-AC-01/02 | identity equality guard; fresh TEST-001 divergence/rewrite controls | aligned, pass |
| R4 behavioral RED/GREEN and reproducible mutation | Test Plan, both ACs | fresh replay 2/2 RED; tdd checker accepts both stored product_red logs; fresh focused GREEN | aligned, pass |
| R5 original evidence and index preservation | Evidence contract, both ACs | boundary-before/after.json; four archived originals equal Git HEAD blobs | aligned, pass |
| R6 frozen contract/amendment | Amendment debt | unchanged spec; fresh strict amendment gate | aligned, pass |
| R7 minimal scope, native extraction, dependencies and process constraints | Scope / Implementation plan | source/tests unchanged; exact existing TEST-001/007 and matrix delimiter read; four-file evidence delta | aligned, pass |
| R8 applicable same-cause patches and shipping ancestry | Mutation Test Plan | git apply --check and apply in COPY, node --check; ancestor exit 0; mutation-gate.log | aligned, pass |

All fresh evidence paths in this report are under `docs/ai/reports/validation-20261008T111030Z-pr-generic-ancestry/` unless explicitly identified as historical. `runs.json` records exact commands, actual exits and observation timestamps.

## Adversarial evidence and preservation

Both new patches apply with ordinary git apply to the copied committed source, leave it parseable, and produce exactly deletion of `validateExplicitUrl(remote);`. Each archived zero-context patch fails ordinary applicability (exit 1), a reached negative control. Archived original records and patches match their Git6d3f blobs byte-for-byte. Eleven non-STATE maker manifest file pins and the exact `git ls-files -s -z` index hash are verified. Maker-era STATE differs because root explicitly reset validation; the new pre/post role STATE hash is unchanged. No provenance was hand-edited and replay reports zero restamps. Source/tests, history, index, HEAD and STATE remain unchanged after the checks.

Canonical replay executed inside its disposable clones under the named absolute scratch root. Focused suites use the canonical wrapper's isolated/seeding-complete checkouts, 180-second wrapper bounds and step-epoch reapers (all exit 0). Scratch mutations were confined to `/private/tmp/aai-pr434-generic-ancestry-validation-scratch/copy`; no tracked shipping source mutation, restore, lifecycle dry-run or external operation occurred.

Historical evidence remains historical: VALIDATION-20261008T101336Z-pr-generic-url-validity.md and its six linked evidence hashes were read back and matched, including full8.log with all eight PASS rows, spec-amend and docs-audit suite success. The report and original Review/N1 addendum also equal Git HEAD blobs. That full eight-row suite is not a full-framework success: the earlier framework aggregate exit 130 remains recorded. Broad framework/hygiene reruns are excluded by this delta dispatch; no source, test, parser or framework code changed. TECHNOLOGY and test inventory show Bash integration and native Pester, no applicable browser E2E/build/typecheck. Native matrix execution remains the parent final integration obligation. The retained PR434 ci-full label is the pre-merge full-suite mechanism, not evidence that final-source CI has passed; no live query was made.

## Gates and failure categories

AC status gate: **pass**. SPEC-0211 gate and ac-flip-check exit 0. Existing done rows predate this role; no rows or evidence cells were changed. Global scan: 216 spec Markdown files, 210 opted-in tables, 1540 rows, no dropped rows. Two deferred rows are due 2026-10-17 (SPEC-0046/Spec-AC-10) and 2026-10-20 (SPEC-0209/Spec-AC-06), neither overdue on 2026-10-08. SPEC-0211 has no deferred/blocked row, so its 14-day rule is vacuous. Initial scan accidentally compared normalizeAcStatus's object rather than status field; retained as ac-global-initial-invalid.json and explicitly not evidence. Corrected ac-global.json confirms both known deferred rows as positive controls.

Code review gate: **pass**, retained child dual PASS with N1 disposition independently verified in decisions.jsonl as filed P3 fu-review-log-attribution (2026-10-08T10:38:39Z). No new review verdict was written. The catalog misattribution remains queued, not claimed fixed.

Blocking product/proof failures: none. Mutation gate: 2 satisfied, degraded=0, unstamped=0, uncomparable=0. Diagnostic docs audit: 571 docs, CLEAN, 8 legacy report-only near-miss tables and 2 report-only missing-close-telemetry entries. Spec lint: no structural findings. Amendment gate: exit 0, 205 scanned, 177 without freeze anchors explicitly degraded; unsigned tracked debt remains. These unchanged advisories are not silently erased.

Close readiness is limited to the repaired mutation prerequisite and AC gate. Root owns close-work-item.mjs --dry-run and actual lifecycle. Its evidencePathGate report-only warnings resolve against the main checkout; proof is committed in this worktree. No new main-checkout availability, missing committed proof, or completed close is invented. Final child integration, sibling case identity/B2, parent assembly Review/Validation, authorized close/generated reconciliation, source-bound native/full CI and external sweep remain owed.

Diagnostic command errors were non-verdict discovery issues: check-role-output does not accept --help (usage exit 2); guessed follow-up/AC-helper paths and one guessed old docs-audit log path were absent. Canonical files were found/read; none is used as a false PASS. Historical patch refusal and unavailable private base are intentional negative checks.

## Executable command log

| Command | Exit |
|---|---:|
| `node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-0211-spec-pr-generic-url-validity.md --json` | 0 |
| `bash .aai/scripts/aai-run-tests.sh node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0211-spec-pr-generic-url-validity.md` | 0 |
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh test_001` | 0 |
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh test_007` | 0 |
| `node .aai/scripts/docs-audit.mjs --gate SPEC-0211` | 0 |
| `node .aai/scripts/docs-audit.mjs --ac-flip-check SPEC-0211` | 0 |
| `node .aai/scripts/docs-audit.mjs --no-event --strict` | 0 |
| `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0211-spec-pr-generic-url-validity.md` | 0 |
| `node .aai/scripts/tdd-evidence-check.mjs --red docs/ai/tdd/spec-pr-generic-url-validity/red-TEST-001.log` | 0 |
| `node .aai/scripts/tdd-evidence-check.mjs --red docs/ai/tdd/spec-pr-generic-url-validity/red-TEST-007.log` | 0 |
| `git diff --check` | 0 |
| `node --check .aai/scripts/pr-preflight.mjs` | 0 |
| `node .aai/scripts/spec-amend.mjs --strict` | 0 |

Additionally: independent hash/ancestor/applicability/read-back audit exit 0; corrected global AC scan exit 0. The verification-before-completion IDENTIFY → RUN → READ → VERIFY chain was applied to this current evidence delta. Outcome checker and typed role checker receipts are companions; the exact returned set-validation evidence is this report. Root alone executes returned state commands, with dispatcher snapshot immediately following set-validation. No next role is dispatched here.

```aai-outcome-v1
{
  "version": 1,
  "ref": "pr-generic-url-validity",
  "validation_started_utc": "2026-10-08T11:10:30Z",
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
      "constraint": "Malformed explicit URL refusal, including recognized and generic host; zero provider calls.",
      "spec_ac_ids": [
        "Spec-AC-01"
      ],
      "assessment": "aligned",
      "rationale": "Independently read intake/spec and inspected implementation. This evidence-only delta preserves the mapped behavior and repairs its reproducible mutation proof.",
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
      "constraint": "Preserve lawful generic URLs, numeric ports, local mode and credential redaction.",
      "spec_ac_ids": [
        "Spec-AC-02"
      ],
      "assessment": "aligned",
      "rationale": "Independently read intake/spec and inspected implementation. This evidence-only delta preserves the mapped behavior and repairs its reproducible mutation proof.",
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
      "constraint": "Preserve destination equality and reject divergence before provider calls.",
      "spec_ac_ids": [
        "Spec-AC-01",
        "Spec-AC-02"
      ],
      "assessment": "aligned",
      "rationale": "Independently read intake/spec and inspected implementation. This evidence-only delta preserves the mapped behavior and repairs its reproducible mutation proof.",
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
      "constraint": "Two genuine product RED records, fresh GREEN, replayable behavioral mutations.",
      "spec_ac_ids": [
        "Spec-AC-01",
        "Spec-AC-02"
      ],
      "assessment": "aligned",
      "rationale": "Independently read intake/spec and inspected implementation. This evidence-only delta preserves the mapped behavior and repairs its reproducible mutation proof.",
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
      "constraint": "Preserve original history bytes, index, STATE, source/tests and original independent reports.",
      "spec_ac_ids": [
        "Spec-AC-01",
        "Spec-AC-02"
      ],
      "assessment": "aligned",
      "rationale": "Independently read intake/spec and inspected implementation. This evidence-only delta preserves the mapped behavior and repairs its reproducible mutation proof.",
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
      "constraint": "No spec change in this delta; preserve frozen contract and tracked amendment obligations.",
      "spec_ac_ids": [
        "Spec-AC-01",
        "Spec-AC-02"
      ],
      "assessment": "aligned",
      "rationale": "Independently read intake/spec and inspected implementation. This evidence-only delta preserves the mapped behavior and repairs its reproducible mutation proof.",
      "required": true,
      "outcome_ids": [
        "O6"
      ]
    },
    {
      "id": "R7",
      "source": {
        "path": "docs/issues/ISSUE-0094-pr-generic-url-validity.md",
        "quote": "No provider writes, secrets acquisition, new dependencies, new vendored files or prompt growth."
      },
      "constraint": "Minimal scope; existing TEST IDs and native delimiter preserved; sequential private experiments, root owns branch/STATE/ledgers.",
      "spec_ac_ids": [
        "Spec-AC-01",
        "Spec-AC-02"
      ],
      "assessment": "aligned",
      "rationale": "Independently read intake/spec and inspected implementation. This evidence-only delta preserves the mapped behavior and repairs its reproducible mutation proof.",
      "required": true,
      "outcome_ids": [
        "O7"
      ]
    },
    {
      "id": "R8",
      "source": {
        "path": "docs/specs/SPEC-0211-spec-pr-generic-url-validity.md",
        "quote": "Produce exact patches in the disposable copy and use `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0211-spec-pr-generic-url-validity.md`; expect exit 0, two intended behavioral RED records and no inconclusive/syntax-only result."
      },
      "constraint": "Applicable same-cause patches; actual shipping ancestor provenance; pass canonical close mutation prerequisite.",
      "spec_ac_ids": [
        "Spec-AC-01",
        "Spec-AC-02"
      ],
      "assessment": "aligned",
      "rationale": "Independently read intake/spec and inspected implementation. This evidence-only delta preserves the mapped behavior and repairs its reproducible mutation proof.",
      "required": true,
      "outcome_ids": [
        "O8"
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
        "expected_identity": "fix/pr-generic-url-validity@6d3f616a96337ff1580968467fadfa9756a87a52:pr-generic-url-validity;source-sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958",
        "observed_identity": "fix/pr-generic-url-validity@6d3f616a96337ff1580968467fadfa9756a87a52:pr-generic-url-validity;source-sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958"
      },
      "verification": {
        "operation": "Fresh real-Git CLI integration with positive three-call GitHub control",
        "evidence_path": "docs/ai/reports/validation-20261008T111030Z-pr-generic-ancestry/test001.log",
        "evidence_sha256": "e0bd0cf35cad282f90ec95560cdc666a46bb03c4caa5d5f23b0df32723858428",
        "observed_at_utc": "2026-10-08T11:12:42.788163+00:00",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "CLI/gate invocation behavior; persisted evidence is separately hash-bound and read back."
      }
    },
    {
      "id": "O2",
      "requirement_ids": [
        "R2"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-generic-url-validity@6d3f616a96337ff1580968467fadfa9756a87a52:pr-generic-url-validity;source-sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958",
        "observed_identity": "fix/pr-generic-url-validity@6d3f616a96337ff1580968467fadfa9756a87a52:pr-generic-url-validity;source-sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958"
      },
      "verification": {
        "operation": "Fresh real-Git CLI integration for generic, port, local, redaction and SSH controls",
        "evidence_path": "docs/ai/reports/validation-20261008T111030Z-pr-generic-ancestry/test007.log",
        "evidence_sha256": "edc0d6256f7f4402b5361290c229c08d5ffaff3e01ca150459ce68feb7aab7fd",
        "observed_at_utc": "2026-10-08T11:13:00.619321+00:00",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "CLI/gate invocation behavior; persisted evidence is separately hash-bound and read back."
      }
    },
    {
      "id": "O3",
      "requirement_ids": [
        "R3"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-generic-url-validity@6d3f616a96337ff1580968467fadfa9756a87a52:pr-generic-url-validity;source-sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958",
        "observed_identity": "fix/pr-generic-url-validity@6d3f616a96337ff1580968467fadfa9756a87a52:pr-generic-url-validity;source-sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958"
      },
      "verification": {
        "operation": "Fresh effective fetch/push and rewrite integration controls",
        "evidence_path": "docs/ai/reports/validation-20261008T111030Z-pr-generic-ancestry/test001.log",
        "evidence_sha256": "e0bd0cf35cad282f90ec95560cdc666a46bb03c4caa5d5f23b0df32723858428",
        "observed_at_utc": "2026-10-08T11:12:42.788163+00:00",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "CLI/gate invocation behavior; persisted evidence is separately hash-bound and read back."
      }
    },
    {
      "id": "O4",
      "requirement_ids": [
        "R4"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-generic-url-validity@6d3f616a96337ff1580968467fadfa9756a87a52:pr-generic-url-validity;source-sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958",
        "observed_identity": "fix/pr-generic-url-validity@6d3f616a96337ff1580968467fadfa9756a87a52:pr-generic-url-validity;source-sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958"
      },
      "verification": {
        "operation": "Replay both same-cause patches in canonical disposable clones; confirm RED without restamping",
        "evidence_path": "docs/ai/reports/validation-20261008T111030Z-pr-generic-ancestry/replay.log",
        "evidence_sha256": "477cef02155810cf11aa30b438cbcd9268d92c025dbe50b887456756f55f107c",
        "observed_at_utc": "2026-10-08T11:12:24.917105+00:00",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "CLI/gate invocation behavior; persisted evidence is separately hash-bound and read back."
      }
    },
    {
      "id": "O5",
      "requirement_ids": [
        "R5"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-generic-url-validity@6d3f616a96337ff1580968467fadfa9756a87a52:pr-generic-url-validity;source-sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958",
        "observed_identity": "fix/pr-generic-url-validity@6d3f616a96337ff1580968467fadfa9756a87a52:pr-generic-url-validity;source-sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958"
      },
      "verification": {
        "operation": "Read-back preserved files, archived mutation originals versus committed Git blobs, NUL index listing and STATE boundary",
        "evidence_path": "docs/ai/reports/validation-20261008T111030Z-pr-generic-ancestry/boundary-after.json",
        "evidence_sha256": "4203daaefc40b04ed77fa18ef419b637fbcbd52b12b4cbcd0c0af30da874aa85",
        "observed_at_utc": "2026-10-08T11:14:47.140812+00:00",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": true,
        "boundary": "saved"
      }
    },
    {
      "id": "O6",
      "requirement_ids": [
        "R6"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-generic-url-validity@6d3f616a96337ff1580968467fadfa9756a87a52:pr-generic-url-validity;source-sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958",
        "observed_identity": "fix/pr-generic-url-validity@6d3f616a96337ff1580968467fadfa9756a87a52:pr-generic-url-validity;source-sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958"
      },
      "verification": {
        "operation": "Fresh strict amendment corpus check plus spec equality to historical validation and HEAD",
        "evidence_path": "docs/ai/reports/validation-20261008T111030Z-pr-generic-ancestry/spec-amend.log",
        "evidence_sha256": "5285c77df645dae0ad57f0dd2c8b37a609765b688ad844069653611a9be0b74f",
        "observed_at_utc": "2026-10-08T11:14:47.239304+00:00",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "CLI/gate invocation behavior; persisted evidence is separately hash-bound and read back."
      }
    },
    {
      "id": "O7",
      "requirement_ids": [
        "R7"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-generic-url-validity@6d3f616a96337ff1580968467fadfa9756a87a52:pr-generic-url-validity;source-sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958",
        "observed_identity": "fix/pr-generic-url-validity@6d3f616a96337ff1580968467fadfa9756a87a52:pr-generic-url-validity;source-sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958"
      },
      "verification": {
        "operation": "Read-back unchanged source/suite/intake/spec, four-file evidence-only tracked diff, Git/index/STATE boundary",
        "evidence_path": "docs/ai/reports/validation-20261008T111030Z-pr-generic-ancestry/boundary-after.json",
        "evidence_sha256": "4203daaefc40b04ed77fa18ef419b637fbcbd52b12b4cbcd0c0af30da874aa85",
        "observed_at_utc": "2026-10-08T11:14:47.140812+00:00",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": true,
        "boundary": "saved"
      }
    },
    {
      "id": "O8",
      "requirement_ids": [
        "R8"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "fix/pr-generic-url-validity@6d3f616a96337ff1580968467fadfa9756a87a52:pr-generic-url-validity;source-sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958",
        "observed_identity": "fix/pr-generic-url-validity@6d3f616a96337ff1580968467fadfa9756a87a52:pr-generic-url-validity;source-sha256:a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958"
      },
      "verification": {
        "operation": "Evaluate canonical mutation gate after independent applicability, parseability, ancestor and preserved-history checks",
        "evidence_path": "docs/ai/reports/validation-20261008T111030Z-pr-generic-ancestry/mutation-gate.log",
        "evidence_sha256": "0069af90aae6582dc802cef4e5306ff4086c6b0c5e77e5a0c8e63c349b9dd579",
        "observed_at_utc": "2026-10-08T11:11:45.218920+00:00",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "CLI/gate invocation behavior; persisted evidence is separately hash-bound and read back."
      }
    }
  ]
}
```
