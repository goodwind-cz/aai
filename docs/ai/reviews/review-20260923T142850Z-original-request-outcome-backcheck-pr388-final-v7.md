# Final independent incremental review — PR388 V7

```yaml
review:
  scope: "cb7ee71705b274c6bdf95414edb3d5024bd5c0c8 to current worktree: four input paths; final product/overview pointer update inspected before handoff"
  spec: docs/specs/SPEC-0183-spec-original-request-outcome-backcheck.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-001 in fresh full outcome suite" }
      - { ac: Spec-AC-02, call: compliant, citation: "Prior full V6 review; unchanged TEST-002 candidates" }
      - { ac: Spec-AC-03, call: compliant, citation: "Checker resolveLocal and TEST-003; independent all-internal-aliases/consumed-only-escape" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-004 in fresh outcome suite" }
      - { ac: Spec-AC-05, call: compliant, citation: "Checker:77\u2013115; TEST-005 RED/GREEN; independent directory-symlink-escape" }
      - { ac: Spec-AC-06, call: compliant, citation: "Fresh full role-output suite; independent CLI/import and V7 report check" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-008 in fresh outcome suite; unchanged TEST-009 prior review" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-010 and fresh full role-output suite" }
      - { ac: Spec-AC-09, call: compliant, citation: "Prior TEST-011/core/profile evidence; inspected incremental diff" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Native Windows realpath/junction/case behavior and final committed remote CI", closes_with: "Actual Windows/platform CI for the final committed bytes." }
    - { claim: "Concurrent hostile filesystem replacement and arbitrary semantic truth", closes_with: "A specified race-resistant boundary or independent task-specific semantic observation if claimed." }
  overall: pass
```

## Scope and evidence

Read current STATE, canonical Code Review/subagent/technology/learned instructions, frozen SPEC-0183 and the actual incremental diff. STATE names this base with review not_run; the explicit base/path dispatch establishes scope despite worktree.user_decision being undecided. Read-only git operations were explicitly confirmed by the parent; no git mutation, source/STATE/ledger write or external message was performed. All reviewer experiments ran in the existing single scratch root /tmp/aai-outcome-independent-review2. Only this review and the requested result artifact are reviewer writes. Parent must stage the review with delivery.

The four input paths and final hashes are:

```
.aai/scripts/validation-outcome-check.mjs  d3bc3997c073799fa5830a7b00ed584d7e89baa40d30aa5b25ef12e79b940ea3
docs/ai/tests/test-runs.jsonl  6883629493cd8baeb4f6c5677334d20e2ba10fcedaf626601f86033ae306aad8
docs/product/original-request-outcome-backcheck.md  ffd70cbc390e9d490619bd8eca101e9e8bd6d66c4f20b5b3ec9488678834b2a9
tests/skills/test-aai-outcome-backcheck.sh  d6dece11fa5e9f7af5813c96c5714103f0a0063c9a570e4ab7239b922b3ccafc
```

This is an incremental review of the post-CI remediation, carrying forward the full nine-AC review at docs/ai/reviews/review-20260923T134749Z-original-request-outcome-backcheck-pr388-final-v6.md for unchanged behavior. The dispatch proposed external-finding classifications; under the anti-gaming rule I treated them as directional claims, fetched all three comments independently and assessed the actual source/contract rather than accepting an expected verdict.

## All nine acceptance criteria

| AC | Call | Evidence and reasoning |
|---|---|---|
| Spec-AC-01 | compliant | Declared gaps and unknown outcomes still refuse; aligned control passes. Citation: TEST-001 in fresh full outcome suite. |
| Spec-AC-02 | compliant | Six semantic scenarios retain their original 6/6 evidence; no fresh semantic-run claim. Citation: Prior full V6 review; unchanged TEST-002 candidates. |
| Spec-AC-03 | compliant | Actual canonical saved identity remains admissible; outside-root consumed bytes refuse. Citation: Checker resolveLocal and TEST-003; independent all-internal-aliases/consumed-only-escape. |
| Spec-AC-04 | compliant | Immutable byte matching and dynamic horizons remain unchanged. Citation: TEST-004 in fresh outcome suite. |
| Spec-AC-05 | compliant | Actual filesystem containment now rejects symlink escapes for sources, evidence and local targets with outcome-specific diagnostics. Citation: Checker:77–115; TEST-005 RED/GREEN; independent directory-symlink-escape. |
| Spec-AC-06 | compliant | Imported handoff and standalone CLI retain the same gate and distinct refusal/usage exits. Citation: Fresh full role-output suite; independent CLI/import and V7 report check. |
| Spec-AC-07 | compliant | Resume and fixture independence remain intact; V7 changes no state or loop contract. Citation: TEST-008 in fresh outcome suite; unchanged TEST-009 prior review. |
| Spec-AC-08 | compliant | Code-only, other-role and non-PASS compatibility controls remain green. Citation: TEST-010 and fresh full role-output suite. |
| Spec-AC-09 | compliant | Node stdlib only; no prompt growth, dependency or suite-selection change. Citation: Prior TEST-011/core/profile evidence; inspected incremental diff. |

## Findings and dispositions

No open BLOCKING or NON-BLOCKING finding remains; no warning disposition is outstanding.

- **4083359831 — real, remediated in tree.** Previously a repository-relative evidence/source/consumed path could traverse an outside-root symlink and still pass. resolveLocal now canonicalizes root and existing target with fs.realpathSync.native, then compares an exact root or separator-bounded descendant. Every source/evidence/expected/observed/consumed local path uses that helper. This implements the frozen D1 repository-relative and canonical-local-identity contract; it does not constrain the separate D2 report locator. Actual internal aliases compare by the same resolved filesystem path.
- **4083337921 — real product-documentation finding; 4083359840 is its duplicate.** The committed product page pointed readers at an absent gitignored validation artifact. It now names a tracked independent review and labels the generated report as uncommitted runtime evidence in inline code. The prior tracked review exists in the index; the final candidate pointer is inspected after parent regeneration.
- Older report-locator, changelog and literal-quote findings retain their disputed dispositions from the independently assessed prior reports. V7 changes none of those contracts. In particular, an absolute external report locator still succeeds in the fresh reviewer control.
- Historical B3 remains explicitly withdrawn: column-zero list/heading blocks take precedence over surrounding inline backticks and are genuine declarations. V7 does not alter that corrected V6 parser behavior.

The new helper keeps ENOENT/ENOTDIR on the existing downstream unreadable-file diagnostic path; other resolution failures refuse. Missing/broken files therefore never become admissible through this fallback. The separator check rejects sibling-prefix escapes. path.resolve/path.sep and native realpath use the host platform conventions, with no POSIX slash added to Windows paths. Native Windows execution is a named gap, not an inferred pass. CLI main-module detection and report loading are unchanged. The existing lexical-root boundary and non-atomic filesystem reads are not represented as a hostile-filesystem security sandbox.

## Executable verification

Independent reviewer runs used the canonical wrapper from the already copied repository root with AAI_ROLE=subagent. AAI_TEST_ISOLATION=0 names that scratch repository, never the delivery tree. Raw commands/stdout/stderr/exits are retained under /tmp/aai-outcome-independent-review2/final-v7/. Both executed source files are byte-identical to production.

| Check | Observed result |
|---|---|
| Current TEST-005 against exact base checker | RED exit 1: expected evidence refusal (1), got 0; qualifying assertion, not infrastructure failure |
| Same TEST-005 against current checker | GREEN exit 0 |
| Internal source/spec/evidence symlinks, saved target aliases, symlinked root together | exit 0 |
| Outside parent-directory evidence symlink | exit 1, resolves outside --root |
| Consumed-only outside symlink with valid expected/observed target | exit 1, consumed target outside root |
| Missing evidence / broken symlink | exit 1, original unreadable ENOENT diagnostic |
| Separate absolute external report locator | exit 0 |
| Symlink CLI help / invalid usage / import only | exits 0 / 2 / 0; help and IMPORT_OK observed |
| Current V7 validation report against current production root | exit 0 |

Independently read VALIDATION-20260923T142145Z-original-request-outcome-backcheck-pr388-final-v7.md and its raw archive. Both complete affected suites pass, with suite tripwire/isolation/seeding 2/2 and reaped 0. The outer wrapper also reports the test-runs ledger append; this is disclosed rather than called a clean wrapper tripwire. Reviewer byte comparison proves the ledger retains all 101,471 base bytes and appends exactly 282 bytes. No old ledger bytes were changed. All nine validation source/evidence identities were independently rehashed and match. Prior semantic/corpus evidence retains its original dates; no fresh V7 repetition is claimed.

Read-only git diff --check passed. There is no new dependency, prompt, protected state logic or unrelated source change. This PASS is not final remote CI or merge authorization. Actual model identity/token usage are unavailable and are not self-reported.

## Final metadata check

Independently inspected the parent update generated at 2026-09-23T14:29:10.828Z: product changes only its review reference, preserving the runtime report as inline code; overview JSON/HTML change only generation timestamps and this same review pointer. The referenced review exists at the exact relative target and is intended for staging with delivery. Rehashing confirms implementation, tests and ledger are unchanged since this review preflight. Final companion hashes:

```
docs/ai/overview-data.json  c449ea763145102274a17896a7ef6810e385fb69dbcfc6e6d3f639c5c4528fa4
docs/ai/overview.html  ece82e66d275b6f4adfd0eea957222533ea306515edfc980ea4d323f958e489c
```


## Timed canonical result

```yaml
subagent_result:
  scope: original-request-outcome-backcheck
  role: Code Review
  status: PASS
  started_utc: 2026-09-23T14:24:25Z
  ended_utc: 2026-09-23T14:30:14Z
  duration_seconds: 349
  evidence:
    - command: "Independent incremental diff/source review and fresh GitHub comment fetch"
      exit_code: 0
      output_snippet: "All 9 ACs compliant; real containment/product findings remediated; duplicate product thread classified; no open findings."
    - command: "Canonical wrapped TEST-005 against exact base then current checker in scratch"
      exit_code: 0
      output_snippet: "Qualifying old-checker assertion RED 1; current checker GREEN 0; raw commands/stdout/stderr/exits preserved."
    - command: "Canonical wrapped independent V7 controls and report check"
      exit_code: 0
      output_snippet: "Internal aliases/root and external report locator pass; outside directory/consumed paths refuse; ENOENT stable; symlink help 0, usage 2, import 0."
    - command: "Read final V7 validation raw evidence; independent hash and ledger-prefix checks"
      exit_code: 0
      output_snippet: "Affected suites 2/2; wrapper ledger warning disclosed; 9 report identities match; 101471 base bytes exact, 282 bytes appended."
    - command: "Inspect final product/overview metadata diff and git diff --check"
      exit_code: 0
      output_snippet: "Only requested pointers/timestamps changed; implementation/tests/ledger unchanged; runtime report inline code; whitespace clean."
  files_changed:
    - docs/ai/reviews/review-20260923T142850Z-original-request-outcome-backcheck-pr388-final-v7.md
    - docs/ai/archive/longhorizon-ship/pr388-final-v7-review/review-result.md
  blockers: []
  state_update_commands:
    - "node .aai/scripts/state.mjs set-code-review --required true --status pass --scope \"cb7ee71705b274c6bdf95414edb3d5024bd5c0c8 to current worktree: checker, outcome suite, product, test-runs ledger plus final overview metadata\" --base-ref cb7ee71705b274c6bdf95414edb3d5024bd5c0c8 --report docs/ai/reviews/review-20260923T142850Z-original-request-outcome-backcheck-pr388-final-v7.md --notes \"Spec compliance PASS all 9 ACs with prior unchanged evidence; code quality PASS; no open warnings. Realpath containment and duplicate product-link findings remediated; independent qualifying RED 1 to GREEN 0; internal aliases/external report locator/CLI/import controls pass; V7 report identities and ledger prefix verified. Final product/overview pointers inspected. Native Windows and final remote CI unverified; no merge authorization.\""
```
