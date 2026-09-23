# Independent forensic triage — PR388 final-head comments

Reviewed HEAD d0eb23c2a2e9bc020be098218f5a0cf62b135487. Independently fetched GitHub comments via `gh api repos/goodwind-cz/aai/pulls/388/comments --paginate`; raw response is ../new-comments.json. Read frozen SPEC-0183 D1–D3, AC table, intake, full checker, actual handoff and test fixtures. Shipping checkout remains unchanged; all shell calls set AAI_ROLE=subagent. No STATE/git writes, outbound review replies or concurrent shipping suites. This is bounded external triage, not another full nine-AC review.

| Comment | Classification | Disposition |
|---|---|---|
| 4080758104 | real, BLOCKING | Repair CLI entrypoint identity and add real/symlink negative controls after a new operator-authorized remediation round. |
| 4080758113 | disputed as a frozen mechanical-contract defect | Quote fabrication is reproduced, but no literal substring/normalization contract exists. Keep semantic verification explicit; a stricter generic citation policy requires a specified extension. |
| 4080758129 | real, BLOCKING | Reject nonexistent Spec-AC links against declared criteria in the hashed spec; add checker and actual handoff regressions after authorization. |

## Executable evidence

One reused scratch root: /tmp/aai-outcome-independent-review2. Its existing external repository copy supplies the canonical wrapper and fixture files. Checker and actual handoff scripts plus five fixture inputs were independently byte-compared to current shipping HEAD before conclusions. Checker SHA-256 is 509364d8b828eb1a577b7f39db735c70a2a5fbf848dd3a445ec50397b93ec2be; check-role-output SHA-256 is b793a2fa549af5b85ee1b63548c5b6843090ee9b5f7d7c0c6c1080938d98bf98. Their old archive origin therefore does not substitute stale implementation for current code.

The command recorded in raw/probe.command ran from the copied repository root through `AAI_TEST_ISOLATION=0 bash .aai/scripts/aai-run-tests.sh node /tmp/aai-outcome-independent-review2/new-final-comments/probe.mjs`. Isolation is already provided by the complete external copy. Each child invocation has its exact argv, stdout, stderr and exit captured under raw/. Wrapper exit is 0: this is an observational probe whose positive/negative exits are listed, not a claim all contract assertions passed.

- valid-direct: exit 0, expected.
- invalid-direct: exit 1, `OUTCOME-CHECK: expected exactly one aai-outcome-v1 block, found 0`.
- invalid-symlink: exit 0, empty stdout/stderr, despite identical malformed report and options.
- invented-quote: exit 0. The exact deliberately fabricated text is absent from hashed intake bytes (`quote-occurs false`).
- invented-ac: exit 0 for Spec-AC-999, absent from hashed spec (`ac-occurs false`).
- handoff-valid / handoff-invented-ac / handoff-invented-quote: each exit 0 through actual check-role-output CLI with otherwise identical valid Validation envelopes.

Initial direct paths used macOS /tmp, itself a symlink to /private/tmp, so even the supposed direct malformed control silently exited 0. That run is retained as raw/tmp-alias-* and explicitly is not the real-path refusal control. Re-running with fs.realpathSync(base) produced the decisive 1-versus-0 pair above. This independently shows directory-alias and explicit script-link variants of the same root cause.

## 4080758104: skipped CLI is a real failure

At `.aai/scripts/validation-outcome-check.mjs:385`, lexical argv resolution is compared to Node's real module path. A user invoking the CLI through a script symlink or absolute symlink-directory path gets success without reading any report. It violates D2's missing/malformed evidence refusal and D3's standalone/loop checker invocation. The imported function used by check-role-output is unaffected by this particular entrypoint skip; this is not a claim that every dispatched handoff is bypassed.

Minimal remedy: identify the invoked module using filesystem-real paths on both sides, preserving import-only behavior. Add actual Node process controls for valid and malformed report through real path, file symlink and directory symlink, plus help/invalid-usage and import-only behavior. Do not catch a main-entry identity error and silently claim success. Maker's separate tentative patch was not used as evidence here.

## 4080758113: truth of quoted prose versus a new exact-match policy

At checker line 247, a quote is only required to be a nonempty string and its path a declared source. The accepted fabricated quote is real behavior; it is not disputed factually. D1 requires source citation/quote but separately assigns original intent and semantic alignment to the independent validator, states that the checker enforces mechanical shape/links/identities/bytes/statuses/timestamps, and explicitly warns a syntactically consistent false claim can fool it. The intake likewise distinguishes natural-language truth from mechanical evidence identity. No exact-substring or allowed normalization rule is frozen. Existing semantic scorer checks original-constraint citation against its oracle at test-aai-outcome-backcheck.sh:433.

Thus acceptance here does not substantiate the bot's implied promise that checker exit 0 certifies quoted prose. A missing, undeclared or malformed citation remains a mechanical refusal; a dishonest nonempty quote remains a semantic validation failure. Exact matching could be useful assurance, but line wraps, Markdown and excerpts require a defined policy and retained-corpus compatibility evaluation. No claim is made that current checker detects fabricated quotes. Dispute with this boundary, rather than pretending the behavior was refuted. No production remedy is required by this triage; any stronger policy should be separately specified and authorized.

## 4080758129: dangling machine link is distinct from alignment semantics

At checker lines 249–256, aligned spec_ac_ids are checked only for array shape, nonemptiness and uniqueness. Spec-AC-999 satisfies those tests while no such criterion exists. The actual Validation handoff also accepts this report. This is a deterministic absent referent, not a judgment about whether a real criterion semantically covers the requirement.

D1 requires corresponding Spec-AC IDs and says dangling links refuse; its closing boundary explicitly says the checker enforces links. AC-05 likewise includes missing/malformed/contradictory required links. The semantic disclaimer does not make an invented machine identifier an existing referent. Although D1's detailed reciprocal links paragraph principally describes requirement/outcome relations, the unqualified checker-links promise plus required corresponding Spec-AC mapping does not support exempting this declared link type. This report records that interpretive distinction explicitly rather than deriving severity from the bot badge.

Minimal bounded remedy: retain the verified spec bytes, extract actually declared AC IDs using the project's canonical AC-table/lean grammar (docs-model exports parseAcTable and parseLeanAcTable), and refuse each nonmember. Preserve supported compact test fixtures deliberately—either migrate their spec inputs to the canonical table form or define their declaration grammar—rather than introducing an undocumented false refusal. Avoid searching every textual mention, which would accept an example-only ID. Keep judging whether an existing AC is semantically adequate with the validator. Regressions need valid mapped control, nonexistent ID negative and actual handoff E-OUTCOME-REPORT; a spec prose/example mention must not create an AC. No production parser/fixture change was made here.

## Authorization and limits

The first finding-bearing extension was consumed under owner standing decision (a), recorded at 2026-09-23T01:10:39Z. That standing decision expressly says a second extension requires asking. The second explicit `pokracuj` approval recorded at 07:07:41Z and DECISION-original-request-outcome-backcheck-round-extension.md is limited to the prepared TEST-008 fixture correction. Its assumptions explicitly authorize no product behavior change. The 08:44 telemetry exception covers precisely 35 model_id fields, not new engine fixes. These new production defects are outside both narrow approvals. Prepare concrete reviewable patches in scratch; obtain new explicit operator authorization before applying another finding-bearing production remediation round. Neither prior PASS nor the general through-PR instruction waives this cap. Shipping these defects as follow-up work would leave the introduced evidence gate inconsistent with its own refusal contract.

No fresh final-head CI result is claimed. Cross-platform symlink execution beyond macOS is unverified; the reproduction is enough to establish the defect on the supported observed platform. Source-quote truth remains independently semantic; this triage does not assert a complete validator audit or universal proof of all link grammars. Native model identity/token usage are unavailable.

```yaml
subagent_result:
  scope: original-request-outcome-backcheck-pr388-final-comments
  role: Code Review
  status: FAIL
  started_utc: 2026-09-23T09:07:29Z
  ended_utc: 2026-09-23T09:11:23Z
  duration_seconds: 234
  evidence:
    - command: "Canonical wrapped scratch probe.mjs with captured child argv/stdout/stderr/exits"
      exit_code: 0
      output_snippet: "real malformed CLI=1; symlink malformed CLI=0; invented AC checker/handoff=0; invented quote checker/handoff=0."
    - command: "Read frozen D1-D3, AC-05, source code and round-extension decisions"
      exit_code: 0
      output_snippet: "Symlink and absent AC referent are real defects; exact quote matching is unspecified semantic hardening; new production round needs explicit authorization."
  files_changed: []
  blockers:
    - "4080758104: malformed report silently accepted through symlink CLI entrypoint."
    - "4080758129: nonexistent Spec-AC-999 accepted through actual Validation handoff."
    - "New production remediation exceeds the consumed standing extension and fixture-only second extension; explicit operator authorization is required."
  state_update_commands: []
```
