# Independent validation — PR434 current snapshot

Verdict: **FAIL** on `609832744c202805234da8a09e40c5d3bb171308`, compared with `bdeb425c040ada918dd97e5b878b71e420bad83a`. A reproduced push-destination mismatch violates the ceremony identity contract. Current native WSL and full-suite CI also fail. No historical PASS is substituted for current evidence.

Validation started **2026-10-07T20:57:48Z** from the system clock. Fresh independent context, artifacts only. Requested route gpt-6-astra; actual serving model **unknown** because it is not exposed. No claim of weight/model independence or token usage is made. No implementation, spec, STATE, lifecycle, Git/index or shipping-ledger edits were performed. Only this report, its typed result and scoped evidence were written. Code review status for this current source snapshot: **required_not_run**; STATE's prior pass concerns historical review.

## Original intent and coverage

Read CHANGE-0204, frozen SPEC-0210, RFC-0016's bounded A1 intent, both human decision records, amendments, current STATE, technology contract, canonical Validation/verify/single-writer guidance, full branch path inventory and implementation/test diff. All six original requirements remain aligned in the spec; no later RFC phase, live Azure adoption or timing improvement is included. The private downstream raw artifacts remain unavailable and no historical reproduction is claimed.

| Original requirement | Spec | Implementation and executed evidence | Result |
|---|---|---|---|
| AC-001 explicit identity before provider calls | Spec-AC-01 | identity(), TEST-001; strict invalid-identity zero-call and valid positive controls, symlink parity | aligned; exercised behavior satisfied |
| AC-002 bounded noninteractive Azure reads; create permission unknown | Spec-AC-02 | readiness()/probe(), TEST-002; exact argv/environment, closed stdin, extension record, split UTF8 | aligned; exercised behavior satisfied |
| AC-003 named nonzero refusal and remedy | Spec-AC-03 | failure()/probe(), TEST-003..005; client/extension/auth/network/unknown, 1MiB cap, synthetic secret positive control; local timeout1512ms, child gone/no later probe | aligned; exercised behavior satisfied |
| AC-004 before ceremony writes; correct origin and preservation | Spec-AC-04 | prompt PRECONDITIONS, TEST-006 snapshots pass; independent actual CLI pushurl reproduction below | **aligned; violated** |
| AC-005 GitHub/generic routes | Spec-AC-05 | TEST-007 and complete existing platform suite pass locally, Linux passes; current WSL TEST-007 fails harness bound | aligned; required platform proof **unknown** |
| AC-006 classification/selection/byte accounting | Spec-AC-06 | TEST-008, full profiles/diet/hygiene/ride-select pass locally; +1287 LF bytes, checkpoint55539, zero padded headroom; WSL TEST-008 never reached | aligned; full current evidence **incomplete** |

## Blocking findings

**B1 — P1 functional: readiness follows origin fetch URL, while push can target another repository.** `.aai/scripts/pr-preflight.mjs:165` uses `git remote get-url -- origin` without `--push --all`. The corrected prompt fixes the remote name to origin but `.aai/SKILL_PR.prompt.md:329` still executes `git push -u origin <branch>`, which honors configured push destinations. Origin-name equality does not establish destination equality.

The isolated reproduction used a real Git repository with fetch URL `https://github.com/Org/Repo.git`, pushurl `https://dev.azure.com/Other/Project/_git/Other`, and a strict three-command gh stub. The real shipping CLI exited0 READ_VERIFIED for GitHub. Adding a second pushurl `https://github.com/Another/Repo.git` still exited0 READ_VERIFIED. Only read-only Git queries and stub calls occurred; no push, provider write or real network call was made. Raw result and reproducible script: `pushurl-repro.log` / `pushurl-repro.cjs` in the evidence directory. This independently confirms the current external finding [discussion_r4211969090](https://github.com/goodwind-cz/aai/pull/434#discussion_r4211969090). Bind readiness to actual push destination identity, or refuse divergent/ambiguous push configuration; retain negative and positive controls. The prior selected-remote/null correction alone does not close this seam.

**B2 — required native evidence: WSL TEST-007 fails.** Current ps1-quality run37685852381 job113013349041 checks out synthetic merge `b54ef37424d6edb510c2b04640274daac25db43e` (60983274 into bdeb425c). Scope TEST-001..006 pass, then `RemoteException: FAIL: TEST-007 CLI must finish within harness bound` at Pester line56. Pester151 pass/1 fail/4 named POSIX-only skips. TEST-008 is never reached in that job. This is the fixture's whole-CLI `spawnSync(...timeout:4000)` bound, not an observed product PROBE_TIMEOUT result. The raw log does not identify which TEST-007 invocation stalled or establish that it is harmless/flaky. Successful Linux or historical d223 evidence cannot fill this gap.

**B3 — required full suite: current104 aggregate is97 PASS /6 FAIL /1 SKIP.** Run37685852367's four complete shard logs bind the same synthetic merge:

| Job / shard | Total | Passed | Failed | Skipped | Failure |
|---|---:|---:|---:|---:|---|
| 113013457677 /1 |25|24|1|0|aai-doc-numbering, TEST-013 expects CLEAN|
| 113013457339 /2 |26|25|1|0|aai-delta-stage3, sibling docs-audit failure|
| 113013457588 /3 |26|23|2|1|aai-doc-number-reservation TEST-011 nested doc-numbering; aai-deslop TEST-028 audit not CLEAN|
| 113013457365 /4 |27|25|2|0|aai-docs-audit TEST-1349 expects CLEAN; aai-repo-tripwire TEST-006 sibling doc-numbering/deslop do not complete|

The skip is **aai-state**, exit42, shard3. Its absence is not a pass. All104 suites were isolated/seeded; zero isolation degradation and zero reattributed waves. Independent read-only `docs-audit --check --no-event` exits0 but explicitly says **NEEDS-TRIAGE (1)**: pr-capability-preflight probable-false-open because implementing intake retains delivery commits, ac_evidence/work_item_closed events and a metrics flush. The full-corpus scan covers567 docs; the audit's exit0 is not a CLEAN verdict. This directly supports the audit/dependency failures; the doc-number-reservation job only retains its nested-call boundary, so no absent nested raw output is fabricated. Closeout artifacts/roadmap/overview still reflect the prior close while the intake/spec are reopened; reconcile through the authorized lifecycle process, never erase append-only history or call this aggregate green.

## Executed local evidence

Every suite used `AAI_ROLE=subagent` and canonical `bash .aai/scripts/aai-run-tests.sh`; suites ran serially in seeded isolated checkouts. The batch captured the step-start epoch and ran the reaper after each step; all reapers reported0. The additional isolated pushurl diagnostic used the wrapper and a legacy-fallback reaper (its step-start epoch was not retained across the separate shell calls); it also reaped0.

| Command after canonical wrapper | Exit | Raw evidence |
|---|---:|---|
| bash tests/skills/test-aai-pr-preflight.sh |0|pr-preflight.log;8/8|
| bash tests/skills/test-aai-pr-platform.sh |0|pr-platform.log|
| bash tests/skills/test-aai-layer-profiles.sh |0|layer-profiles.log|
| bash tests/skills/test-aai-prompt-diet.sh |0|prompt-diet.log|
| bash tests/skills/test-aai-ride-select.sh |0|ride-select.log|
| bash tests/skills/test-aai-hygiene-pack.sh |0|hygiene-pack.log|
| node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0210-spec-pr-capability-preflight.md |0|mutation.log;8/8 behavioral RED,0 inconclusive,0 restamped|
| node /private/tmp/aai-pr434-validation-scratch/pushurl-repro.cjs |0|pushurl-repro.log; exit0 means mismatch reproduced, not product PASS|

Original disclosed parseable-no-op RED evidence was read and accepted by `tdd-evidence-check.mjs` as product_red. Current eight mutation patches remain behavioral removal checks; historical TEST-006 patch/record and explicit reanchor amendment are retained. Those eight green tests/mutation bites do not cover B1 and cannot refute the separate reproduction. Historical full100/4 and d223 native successes remain historical failed/resolved evidence, not current aggregate or native attestations.

Current Linux ps1-quality job113013348742 passes full Pester156/0/0, PSScriptAnalyzer, all eight shared scope arms, plus canonical Bash under ordinary uid1001 with scratch override unset. Both origin/refusal and captured successful-clone stderr controls pass there. Complete native Windows5.1/7 sibling result was still pending when this report was assembled; no result is inferred. The WSL failure already prevents native matrix completion.

## Gates, scope, and remaining limits

AC status gate **PASS**; spec lint0 findings. Independent canonical parser scan214 specs/208 opted-in finds2 deferred rows in other scopes, zero overdue rows, zero scope Review-By violations. `ac-corpus.json` retains exact rows. No AC/lifecycle rows were edited. E2E/deployed browser/build testing is not applicable under TECHNOLOGY; CLI/framework integration, shell/platform and corpus tests are applicable and their failures are preserved.

`tree-manifest.json` binds all55 branch paths. EVENTS, METRICS, decisions and test-runs retain byte-exact base prefixes. Shipping status remained clean before report creation. Complete raw downloaded job logs and local evidence are bound by SHA256/bytes in `evidence.json`; relevant execution sections, failures and summaries were inspected. Some CI framework logs contain only failure tails of nested suites; they are complete job logs, not invented complete nested logs.

Friction was captured by the sole-writer root (fingerprint v1:6475f1b6dfc9ff5b27da1d8aa0ebfc9d); this validator's write scope excludes the spool. The existing unsigned contract-amendment follow-up remains open. Snapshot authorization does not waive validation/review/native proof or authorize merge. Live Azure, future create permission, downstream historical reproduction and arbitrary-agent obedience to prose remain explicitly unproved. This finding-bearing round must be handled under the canonical review-round cap/split rule; this validator does not authorize another unsplit remediation loop.

The typed outcome checker is expected to **refuse PASS admissibility** because AC-004 is violated and AC-005/006 remain unknown. The typed subagent result must separately pass check-role-output. Returned STATE commands record FAIL and remediation; no PASS tree snapshot is returned.

```aai-outcome-v1
{
  "version": 1,
  "ref": "pr-capability-preflight",
  "validation_started_utc": "2026-10-07T20:57:48Z",
  "sources": [
    {
      "kind": "intake",
      "path": "docs/issues/CHANGE-0204-pr-capability-preflight.md",
      "sha256": "5103c792b1773650e6122e91fb58cd15ae8760e8ec3c9dc5642423b618a45460"
    },
    {
      "kind": "spec",
      "path": "docs/specs/SPEC-0210-spec-pr-capability-preflight.md",
      "sha256": "75bd28bad2ba6d0047bf82f8d49f41fd6bce51865bfb305127e514947185afbb"
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
      "rationale": "Frozen spec retains the original requirement; implementation/evidence result is assessed separately. TEST-001 identity before providers; local and current Linux/native WSL arms passed",
      "required": true,
      "outcome_ids": [
        "OUT-001"
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
      "rationale": "Frozen spec retains the original requirement; implementation/evidence result is assessed separately. TEST-002 strict Azure argv/env/closed stdin, split UTF8, create permission unknown",
      "required": true,
      "outcome_ids": [
        "OUT-002"
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
      "rationale": "Frozen spec retains the original requirement; implementation/evidence result is assessed separately. TEST-003..005 named refusal, credential controls, output cap, bounded child termination",
      "required": true,
      "outcome_ids": [
        "OUT-003"
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
      "rationale": "Frozen spec retains the original requirement; implementation/evidence result is assessed separately. TEST-006 preservation and origin selection; independent pushurl reproduction proves destination mismatch",
      "required": true,
      "outcome_ids": [
        "OUT-004"
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
      "rationale": "Frozen spec retains the original requirement; implementation/evidence result is assessed separately. TEST-007 local/Linux pass, current WSL whole-CLI harness timeout means required platform proof is incomplete",
      "required": true,
      "outcome_ids": [
        "OUT-005"
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
      "rationale": "Frozen spec retains the original requirement; implementation/evidence result is assessed separately. TEST-008 local/Linux pass; WSL arm unreached, current full framework97PASS6FAIL1SKIP",
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
        "expected_identity": "609832744c202805234da8a09e40c5d3bb171308",
        "observed_identity": "609832744c202805234da8a09e40c5d3bb171308"
      },
      "verification": {
        "operation": "TEST-001 identity before providers; local and current Linux/native WSL arms passed",
        "evidence_path": "docs/ai/tdd/pr-capability-preflight-validation-20261007T205748Z/evidence.json",
        "evidence_sha256": "1e13d5987e8435658840ce69cc51ce7e58f235d1f5684d46b5eec62c6bc2472d",
        "observed_at_utc": "2026-10-07T21:10:44Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only readiness and disposable fixtures; this scope requests no external provider write or persisted external artifact."
      }
    },
    {
      "id": "OUT-002",
      "requirement_ids": [
        "AC-002"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "609832744c202805234da8a09e40c5d3bb171308",
        "observed_identity": "609832744c202805234da8a09e40c5d3bb171308"
      },
      "verification": {
        "operation": "TEST-002 strict Azure argv/env/closed stdin, split UTF8, create permission unknown",
        "evidence_path": "docs/ai/tdd/pr-capability-preflight-validation-20261007T205748Z/evidence.json",
        "evidence_sha256": "1e13d5987e8435658840ce69cc51ce7e58f235d1f5684d46b5eec62c6bc2472d",
        "observed_at_utc": "2026-10-07T21:10:44Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only readiness and disposable fixtures; this scope requests no external provider write or persisted external artifact."
      }
    },
    {
      "id": "OUT-003",
      "requirement_ids": [
        "AC-003"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "609832744c202805234da8a09e40c5d3bb171308",
        "observed_identity": "609832744c202805234da8a09e40c5d3bb171308"
      },
      "verification": {
        "operation": "TEST-003..005 named refusal, credential controls, output cap, bounded child termination",
        "evidence_path": "docs/ai/tdd/pr-capability-preflight-validation-20261007T205748Z/evidence.json",
        "evidence_sha256": "1e13d5987e8435658840ce69cc51ce7e58f235d1f5684d46b5eec62c6bc2472d",
        "observed_at_utc": "2026-10-07T21:10:44Z",
        "result": "satisfied"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only readiness and disposable fixtures; this scope requests no external provider write or persisted external artifact."
      }
    },
    {
      "id": "OUT-004",
      "requirement_ids": [
        "AC-004"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "609832744c202805234da8a09e40c5d3bb171308",
        "observed_identity": "609832744c202805234da8a09e40c5d3bb171308"
      },
      "verification": {
        "operation": "TEST-006 preservation and origin selection; independent pushurl reproduction proves destination mismatch",
        "evidence_path": "docs/ai/tdd/pr-capability-preflight-validation-20261007T205748Z/evidence.json",
        "evidence_sha256": "1e13d5987e8435658840ce69cc51ce7e58f235d1f5684d46b5eec62c6bc2472d",
        "observed_at_utc": "2026-10-07T21:10:44Z",
        "result": "violated"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only readiness and disposable fixtures; this scope requests no external provider write or persisted external artifact."
      }
    },
    {
      "id": "OUT-005",
      "requirement_ids": [
        "AC-005"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "609832744c202805234da8a09e40c5d3bb171308",
        "observed_identity": "609832744c202805234da8a09e40c5d3bb171308"
      },
      "verification": {
        "operation": "TEST-007 local/Linux pass, current WSL whole-CLI harness timeout means required platform proof is incomplete",
        "evidence_path": "docs/ai/tdd/pr-capability-preflight-validation-20261007T205748Z/evidence.json",
        "evidence_sha256": "1e13d5987e8435658840ce69cc51ce7e58f235d1f5684d46b5eec62c6bc2472d",
        "observed_at_utc": "2026-10-07T21:10:44Z",
        "result": "unknown"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only readiness and disposable fixtures; this scope requests no external provider write or persisted external artifact."
      }
    },
    {
      "id": "OUT-006",
      "requirement_ids": [
        "AC-006"
      ],
      "target": {
        "kind": "repository",
        "expected_identity": "609832744c202805234da8a09e40c5d3bb171308",
        "observed_identity": "609832744c202805234da8a09e40c5d3bb171308"
      },
      "verification": {
        "operation": "TEST-008 local/Linux pass; WSL arm unreached, current full framework97PASS6FAIL1SKIP",
        "evidence_path": "docs/ai/tdd/pr-capability-preflight-validation-20261007T205748Z/evidence.json",
        "evidence_sha256": "1e13d5987e8435658840ce69cc51ce7e58f235d1f5684d46b5eec62c6bc2472d",
        "observed_at_utc": "2026-10-07T21:10:44Z",
        "result": "unknown"
      },
      "persistence": {
        "applicable": false,
        "reason": "Read-only readiness and disposable fixtures; this scope requests no external provider write or persisted external artifact."
      }
    }
  ]
}
```
