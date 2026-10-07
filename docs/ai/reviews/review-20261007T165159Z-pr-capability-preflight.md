```yaml
review:
  scope: "bdeb425c040ada918dd97e5b878b71e420bad83a...6005f5874dd789dbacd3e61088edf38aa8b35d99 plus all tracked working diffs"
  spec: docs/specs/SPEC-DRAFT-spec-pr-capability-preflight.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:143; TEST-001; final-main.log" }
      - { ac: Spec-AC-02, call: non-compliant, citation: ".aai/scripts/pr-preflight.mjs:101; R2 split UTF-8 reproducer" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:74; TEST-003..005; native inspection manifest" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/SKILL_PR.prompt.md:21,54; TEST-006" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:216; TEST-007; final validation report" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/system/PROFILES.yaml:205; tests/skills/suite-map.yaml:1117; TEST-008" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-pr-preflight.sh, line: 14, issue: "R1: macOS-only scratch default breaks ordinary Linux Bash suite execution", failure_scenario: "AAI_PREFLIGHT_SCRATCH is unset on an Ubuntu user account without a writable /private; recursive mkdir fails before any TEST assertion." }
      - { rank: BLOCKING, file: .aai/scripts/pr-preflight.mjs, line: 101, issue: "R2: decoding each chunk separately corrupts split UTF-8", failure_scenario: "A successful Azure repository response splits the UTF-8 bytes of a Unicode project or repository name between data events; replacement characters cause identity mismatch and refusal." }
  cannot_verify:
    - { claim: "Authenticated live Azure compatibility", closes_with: "Authorized live provider round trip under existing fu-azure-live-proof-on-adoption." }
    - { claim: "Every future agent follows prompt ordering", closes_with: "An executable ceremony boundary; current text checks and fixture execution only prove the declared seam." }
    - { claim: "Full pre-close suite green and native Linux Bash execution", closes_with: "Completed full sweep plus ordinary-user Linux Bash run after R1 remediation." }
  overall: fail
```

# Code review — pr-capability-preflight, round 1

## Scope and independence

Reviewed the complete immutable-base diff and all tracked working changes. HEAD was `6005f5874dd789dbacd3e61088edf38aa8b35d99`; base was `bdeb425c040ada918dd97e5b878b71e420bad83a`. STATE selects worktree mode. `git status --porcelain` showed only EVENTS.jsonl, test-runs.jsonl and test-aai-pr-preflight.sh modified; the first two append records and the suite removes trailing whitespace. Staged diff was empty. No area was excluded, including the umbrella RFC, snapshot authorization, generated index, ledgers and hygiene companion change. The RFC remains a proposal, not claimed delivered scope. No dispatch coaching was observed.

Read canonical role/contract, assembled `canon.mjs build --role 'Code Review' --ref HEAD`, technology and learned rules, intake and amended frozen spec. Model route requested by dispatcher: premium fallback gpt-6-astra because gpt-5.3-codex was unavailable. Actual weights are not observable and are not attested. No source, Git, STATE, staging or decision mutation was made. Only this review artifact was written.

## Acceptance criteria walk

| AC | Call | Evidence and reason |
|---|---|---|
| Spec-AC-01 | compliant | identity() rejects missing, detached, inconsistent and ambiguous local/provider identity before readiness; TEST-001 and independent adverse evidence cover the supported URI shapes. |
| Spec-AC-02 | non-compliant | Azure argv, extension checks and unknown create permission are correct in the exercised matrix. R2 nevertheless rejects a legitimate successful Unicode response depending on stream chunk boundaries, contrary to the successful read contract. |
| Spec-AC-03 | compliant | Named safe errors, no raw provider text output, capped output and timeout termination are implemented and exercised by TEST-003..005 plus both native engines. R2 is a success-path defect, not a disclosure or refusal-class defect. |
| Spec-AC-04 | compliant | Prompt positions readiness before lifecycle/index/commit/push writes and before fresh STATE initialization. TEST-006 checks ordering and actual CLI refusal preservation with success controls. Arbitrary-agent compliance remains an explicit limit. |
| Spec-AC-05 | compliant | GitHub host/repository binding and generic/local fallbacks remain; TEST-007 and existing platform suite passed in cited independent validation. |
| Spec-AC-06 | compliant | Core profile, suite-map, inventory pin and +1200 canonical LF-byte accounting are present; TEST-008 verifies shallow checkout and CRLF behavior. R1 separately breaks running the new Bash suite on an ordinary Linux environment. |

All TEST-001..008 functions exist and are invoked. Independently inspected `docs/ai/tdd/pr-capability-preflight-final-main.log`: eight PASS rows. `pr-capability-preflight-final-mutations.log` records 8/8 behavioral REDs, zero inconclusive/restamped. Checked all hashes in `pr-capability-preflight-final-evidence.json` against actual retained files: all match. Read `docs/ai/reports/VALIDATION-20261007T154607Z-pr-capability-preflight.md` and native inspection manifest. That report truthfully preserves the initial selected aggregate failure and successful affected reruns; no green aggregate is inferred. Native Pester passes do not exercise R1 because Pester sets AAI_PREFLIGHT_SCRATCH explicitly.

The original six intake requirements are retained. Amendments are disclosed in the append-only decision ledger, with owner signoff still owed under `fu-amend-spec-pr-capability-preflight`. No new runtime sidecar was introduced. No test name claiming an unproved universal negative was found. The status table still says native proof pending; the validator explicitly assigns that reconciliation to close rather than falsely claiming the docs were updated.

## Findings

### R1 — BLOCKING / P2: use a portable default scratch directory

`tests/skills/test-aai-pr-preflight.sh:14` selects `/private/tmp/aai-pr-preflight-scratch` for every non-Windows host, then line 15 recursively creates it before the test's try/finally. On a standard Linux checkout run by a non-root user, `/private` is absent and the user cannot create it under `/`. Thus the documented Bash command fails every row with EACCES before testing the CLI. This also applies to the Ubuntu skill-suite CI jobs: neither `.github/workflows/skill-suite.yml` nor `tests/skills/test-framework.sh` sets AAI_PREFLIGHT_SCRATCH or provisions `/private`. The Linux Pester run passes because its BeforeAll supplies an OS temporary path, which masks the Bash default.

Evidence is the actual default expression plus absence of an override in both invocation owners. This is a deterministic environment-path defect identified statically; no native Linux Bash run was fabricated. Use the existing explicit override with an `os.tmpdir()`-based portable default, and prove the canonical Bash invocation under an ordinary Linux user with that override unset. Preserve private per-run fixtures.

### R2 — BLOCKING / P2: preserve UTF-8 across stream chunks

`.aai/scripts/pr-preflight.mjs:101` applies `chunk.toString('utf8')` independently to each Buffer. Pipe data events may split a multibyte character. A repository response containing `Repo 雪`, split after the first UTF-8 byte of 雪, becomes `Repo ���`. JSON still parses, but the equality checks against the intended repository/project then produce PROVIDER_RESULT_INVALID instead of READ_VERIFIED. A split Unicode branch/root output can likewise break local identity. The spec explicitly includes Unicode identities.

A read-only in-memory probe extracted the exact current probe() function, supplied an EventEmitter child and two byte chunks, and observed:

```json
{"expected":"{\"name\":\"Repo 雪\"}","observed":"{\"name\":\"Repo ���\"}","equal":false}
```

No source modification or actual provider invocation was involved. Reproduction: encode `JSON.stringify({name:'Repo 雪'})` into a Buffer; locate `Buffer.from('雪')`, split at its index + 1, emit the two Buffers on stdout, then emit close(0). The current helper returns the corrupted string. Buffer complete bounded output and decode once, or use a streaming UTF-8 decoder while preserving the byte-based cap. Add a real CLI stub that emits a split multibyte successful response and proves READ_VERIFIED, with a corresponding failing-first observation.

## Cannot verify and H6 dispositions

- Live authenticated Azure remains the existing named evidence debt; hermetic argv/native process tests cannot close it.
- Prompt ordering is verified as text plus fixture behavior, not enforcement over arbitrary future agents.
- The concurrent full pre-close sweep was unfinished when this review ended. This review neither waits on it nor claims it passed. Native Linux Bash evidence for the portable default is still needed.
- No NON-BLOCKING warnings were raised, so there are no H6 warning dispositions to file. Both concrete findings require remediation in tree before review PASS. No follow-up was filed by this read-only reviewer.

Next: remediate R1/R2 with focused regression evidence, revalidate impacted behavior, and return for the second allowed review round. Keep the full-sweep and owner amendment-signoff obligations visible.

## Dispatched result

```yaml
subagent_result:
  scope: pr-capability-preflight
  role: Code Review
  status: FAIL
  started_utc: 2026-10-07T16:51:59Z
  ended_utc: 2026-10-07T16:55:38Z
  duration_seconds: 219
  evidence:
    - command: "node .aai/scripts/canon.mjs build --role 'Code Review' --ref HEAD"
      exit_code: 0
      output_snippet: "Canonical contract, review role and learned sections assembled."
    - command: "git diff bdeb425c040ada918dd97e5b878b71e420bad83a...HEAD; git diff; git diff --cached"
      exit_code: 0
      output_snippet: "Full committed scope plus three tracked working changes; staged diff empty."
    - command: "Read-only in-memory extraction and execution of probe() with split UTF-8 buffers"
      exit_code: 0
      output_snippet: "Expected Repo 雪; observed Repo ���; equal=false."
    - command: "SHA-256 verification of final-evidence.json referenced files"
      exit_code: 0
      output_snippet: "Evidence hashes verified: true."
  files_changed:
    - docs/ai/reviews/review-20261007T165159Z-pr-capability-preflight.md
  blockers:
    - "R1 Linux Bash scratch default; R2 split UTF-8 corruption."
  state_update_commands:
    - node .aai/scripts/state.mjs set-code-review --required true --status fail --scope "bdeb425c040ada918dd97e5b878b71e420bad83a...6005f5874dd789dbacd3e61088edf38aa8b35d99 plus all tracked working diffs" --base-ref bdeb425c040ada918dd97e5b878b71e420bad83a --report docs/ai/reviews/review-20261007T165159Z-pr-capability-preflight.md --notes "Round 1 FAIL: R1 portable Linux scratch default and R2 split UTF-8 corruption require in-tree remediation; no NON-BLOCKING warnings."
```
