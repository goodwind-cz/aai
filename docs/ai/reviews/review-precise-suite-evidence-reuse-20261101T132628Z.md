# Code Review: precise-suite-evidence-reuse (round 5)

```yaml
review:
  scope: main...HEAD (feat/precise-suite-evidence-reuse, head 17f42f7d, base main 89a63814); delta since round 4 c639df81..17f42f7d (9fb6d60b, 17f42f7d)
  spec: docs/specs/SPEC-0266-spec-precise-suite-evidence-reuse.md (amended; contract amendments 2026-11-01T12:15:07Z and 13:07:52Z, restamp record 13:08:58Z; all owner_signoff false, tracked by fu-amend-precise-suite-evidence-reuse)
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "test-framework.sh reuse split + reuse_report; TEST-3165 PASS (validation r9 full sweep at 9fb6d60b; no framework change since)" }
      - { ac: Spec-AC-02, call: non-compliant, citation: "suite-reuse.mjs:177 applies QUOTE_CLOSED_RE to TOKEN_RE tokens only; the LIB_RE loop (:184-192), relative() (:201-215, fed by :217-218) never check a quote closing the literal before more text, so \"$SCRIPT_DIR/lib/fix\"$n.json, \"$SCRIPT_DIR/fixtures/fix\"$n.json, \"lib/fix\"$n.json, \"$(dirname \"$0\")/lib/fix\"_a.json give false REUSE (B1). suite-reuse.mjs:184 limits the lib/ check to tests/skills/ files, so a bare lib/<name> in a tests/ file outside tests/skills/ is neither resolved nor unresolvable; the amended D4 (d) says it is unresolvable (B2). r9 B1/B2/NB-2/NB-3 forms are fixed (TEST-3167 two new cases, 28/28 node cases pass)" }
      - { ac: Spec-AC-03, call: compliant, citation: "computeIdentity env/args/runtime/policy/history unchanged in delta; TEST-3168..3172 PASS (r9)" }
      - { ac: Spec-AC-04, call: compliant, citation: "loadManifest/checkSuites unchanged; TEST-3173, TEST-3174 PASS (r9)" }
      - { ac: Spec-AC-05, call: compliant, citation: "recordSuite refusals, reuse_settle unchanged; TEST-3175, TEST-3176 PASS (r9)" }
      - { ac: Spec-AC-06, call: compliant, citation: "OFF modes unchanged; TEST-3177..3179 PASS (r9)" }
      - { ac: Spec-AC-07, call: compliant, citation: "reporting unchanged; TEST-3180, TEST-3181 PASS (r9)" }
      - { ac: Spec-AC-08, call: compliant, citation: "reviewer: suite-reuse lint rc 0 on a clone of 17f42f7d; the 5 manifest suites have 0 unresolved entries at 17f42f7d (scratchpad/r5/manifest.mjs); spec lint paragraph names all four reasons" }
      - { ac: Spec-AC-09, call: compliant, citation: "select-suites.mjs unchanged; TEST-3183, TEST-3190 PASS (r9)" }
      - { ac: Spec-AC-10, call: compliant, citation: "no ps1 path in delta; TEST-3184, TEST-3185 PASS (earlier rounds; native Windows is post-PR H1)" }
      - { ac: Spec-AC-11, call: compliant, citation: "prompts unchanged in delta; TEST-3186, TEST-3187 PASS (r9)" }
      - { ac: Spec-AC-12, call: compliant, citation: "imports unchanged; TEST-3188 PASS (r9)" }
      - { ac: Spec-AC-13, call: compliant, citation: "analysis note unchanged; TEST-3189 PASS (r9)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 177,
          issue: "The 'path literal closed by a quote before more text' rule, which D4 (d) lists among the unresolvable forms, is enforced only for TOKEN_RE tokens (:177, QUOTE_CLOSED_RE :138). The other two recognized forms never get it: LIB_RE (:184-192) and relative() (:203-215, called from the SCRIPT_DIR_RE and DIRNAME_RE loops at :217-218) accept a closing quote as a plain terminator (LIB_END_RE :124 even whitelists \" and ') and then hash the literal before the quote, a file that does not exist, while the file really read is not hashed and nothing is pushed to unresolved.",
          failure_scenario: "Reviewer probe (scratchpad/r5/probe.mjs, probe2.mjs; shipped helper from a clone of 17f42f7d; identity before vs after editing the target). In tests/skills/test-fk.sh with a BASH_SOURCE-derived SCRIPT_DIR: cat \"$SCRIPT_DIR/lib/fix\"$n.json (tests/skills/lib/fix1.json edited), cat \"$SCRIPT_DIR/fixtures/fix\"$n.json, cat \"$SCRIPT_DIR/fixtures/fix\"_a.json, cat \"lib/fix\"$n.json, cat \"lib/fix\"_a.json, cat 'lib/fix'_a.json, cat \"lib/fix\"-a.json, cat \"$(dirname \"$0\")/lib/fix\"_a.json: each FALSE REUSE with 0 unresolved. Control: cat \"$ROOT/docs/pro\"$S gives unresolvable. The quote-then-expansion shape is exactly the spec's own example (\"$ROOT/docs/pro\"$S); a manifest suite reading such a file optionally (2>/dev/null || default) passes the minimal-tree gate and then reuses over the edit. Latent: no live tests/ file has the shape (grep), the 5 manifest suites resolve cleanly. Not new in round 5 (same results on c639df81), but the new allowlist explicitly trusts the quote." }
      - { rank: BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 184,
          issue: "The lib/ check runs only for files under tests/skills/ (if (rel.startsWith('tests/skills/'))). The amended D4 (d) says every lib/ reference other than the allowlisted one, 'whether a bare token ... in any directory (a file below or outside tests/skills/ ...)', is unresolvable. A bare lib/<name> in a closure file under tests/ outside tests/skills/ (shell or .mjs) is ignored: neither resolved nor unresolvable.",
          failure_scenario: "Probe: the suite sources tests/other/h.sh, which runs cat lib/x (or tests/other/a.mjs reads readFileSync('lib/x')); editing lib/x leaves the identity unchanged, 0 unresolved: FALSE REUSE. Bites when the suite runs from a directory that holds lib/ (repo root of a downstream project with a root lib/). The spec also lists 'a plain relative name with no base' as R1, but the lib/-specific amendment of 13:07:52Z is explicit and newer. Fix is one condition: drop the tests/skills/ gate (the dirname check at :189 already refuses every non-tests/skills directory). Reviewer check: with the gate removed the 5 manifest suites still have 0 unresolved and the repo corpus stays at 98/122 unresolvable." }
      - { rank: NON-BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 138,
          issue: "QUOTE_CLOSED_RE accepts only $, backtick, word, /, quotes after the closing quote; a '.' or '-' is not 'more text' to it.",
          failure_scenario: "cat \"$ROOT/docs/pro\".md hashes docs/pro (absent) and misses docs/pro.md: FALSE REUSE (probe). Spec is ambiguous here: R1 discloses 'a literal closed by a quote before ... concatenation in JS or shell', the unresolvable list says 'closed by a quote before more text'. Recommended disposition: remediate in tree together with B1 (make the after-quote check 'anything but a terminator')." }
  cannot_verify:
    - { claim: "Full-sweep results at 17f42f7d (validation r9 swept 9fb6d60b)", closes_with: "the validator's sweep on the fixed head; reviewer ran only node --test tests/skills/lib/suite-reuse.test.mjs (28/28 pass)" }
    - { claim: "Native Windows parity (Pester under windows-5_1 / windows-wsl1)", closes_with: "post-PR H1: ps1-quality run on the PR head" }
    - { claim: "CI prints 'Evidence reuse: off (ci)' and never reuses", closes_with: "post-PR H2: skill-suite run log on the PR head" }
    - { claim: "The five manifest notes are true for reads the minimal-tree gate cannot see (optional reads, absolute or $HOME paths, inherited env)", closes_with: "syscall-level trace of each manifest suite or a recorded line review per suite" }
    - { claim: "Role conduct: consumers read the cited log and never treat REUSED as the close-time sweep (R3)", closes_with: "observed behaviour over future rides; TEST-3186 checks text only" }
    - { claim: "Measured wall times in the analysis note", closes_with: "re-running D11 on the reviewed head" }
    - { claim: "SKILL_VERIFY links docs/product/precise-suite-evidence-reuse.md, absent at this head", closes_with: "product doc landing before the PR" }
    - { claim: "Cause of the 13:08:58Z 'restamp of an UNVERIFIED cause' record (from d235..., while 9fb6d60b stamped 762c...)", closes_with: "orchestrator note tying the intermediate stamp to the 13:07:52Z text amendment; spec-amend list --strict rc 0 either way" }
  overall: fail
```

security_relevant: false

## Scope and method

- Scope: `git diff main...HEAD` in worktree `/Users/ales/Projects/aai-worktrees/precise-suite-evidence-reuse` (worktree mode, base main 89a63814, head 17f42f7d), focused on `c639df81..17f42f7d`. Working-tree changes outside the reviewed diff: `docs/ai/EVENTS.jsonl`, `docs/ai/tests/test-runs.jsonl` (telemetry).
- Contract: the frozen spec as amended (D4 (d) strict `lib/` allowlist plus the listed unresolvable forms; everything else R1). A false REUSE on a form D4 (d) lists as recognized or unresolvable is blocking; a disclosed R1 form is not.
- Coaching note (anti-gaming contract): the dispatch named the commits and asked to hunt tokenizer false REUSE and check the manifest suites. That is scope, not a pre-rating; the whole branch diff was in scope.
- Reviewer evidence: read the helper closure code at head, the delta, the two new TEST-3167 cases, the amendments and validation r9. Probes in `/private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/r5/` (`probe.mjs`, `probe2.mjs`, `manifest.mjs`, `corpus.mjs`) import the helper from a `git clone --local` at 17f42f7d and compare identities before and after editing the target file. `node --test tests/skills/lib/suite-reuse.test.mjs`: 28/28 pass. `spec-amend list --strict`: rc 0 (three unsigned-tracked records for this ref). `suite-reuse lint` on the clone: rc 0. No suites or sweep run; nothing written in the worktree except this report.

## Validation r9 and round-4 findings: resolution

| id | status | evidence |
|---|---|---|
| review r4 B1 / validation r8 B2 (`lib/` early return) | resolved | `:203-207` refuses any `lib/` form not on the allowlist; probe rows nested, `.`, `..`, out-of-tree all unresolvable |
| validation r9 B1 (own-dir `lib/` below tests/skills) | resolved | `:189` and `:205` require own directory exactly `tests/skills`; new TEST-3167 rows (fixtures/h.sh, lib/helper.sh, dirname) |
| validation r9 B2 (`lib/<name>` before expansion/glob) | resolved | `LIB_END_RE` (:124) refuses `$ * ? [ {`; TEST-3167 rows |
| validation r9 NB-2 (`@`, `+`) | resolved | same terminator check; TEST-3167 rows `@`, `+`, `:` |
| validation r9 NB-3 (look-back) | resolved | `:187` skips only a `lib/` strictly inside a real TOKEN_RE token; `xtests/skills/lib/sub/y` row |
| validation r8 NB-1 (lint reasons in spec) | resolved | lint paragraph lists all four reasons |

Manifest suites: at 17f42f7d all five (aai-feedback-status, aai-pricing, aai-redact, aai-orchestration-mode, aai-runtime-file) have 0 unresolved entries and keep their closures; the allowlist did not break their reuse. The positive TEST-3167 rows (each terminator, token-interior `.aai/scripts/lib/m.mjs`) confirm tracked plain reads stay reusable and invalidating.

## Spec-AC walk

See `ac_walk`. Deviations from the amended spec:

1. Quote-closed literals in the `lib/<name>`, `$SCRIPT_DIR/<literal>` and `$(dirname ...)/<literal>` forms are resolved instead of unresolvable (B1).
2. Bare `lib/` references outside `tests/skills/` are ignored instead of unresolvable (B2).
3. All amendments unsigned, tracked by fu-amend-precise-suite-evidence-reuse: documented additive-with-disclosure path, not a finding.

## BLOCKING findings

- **B1 `.aai/scripts/suite-reuse.mjs:177`** (with :124, :138, :184-192, :203-215, :217-218): the quote-closed check covers tokens only. Suggested fix: one shared after-literal check used by all three forms: if the character after the literal is `"` or `'`, the literal is unresolvable unless the character after that quote is end of text, whitespace, `)`, `;`, `|`, `&`, `<` or `>`. RED first in TEST-3167 with `"$SCRIPT_DIR/lib/fix"$n.json`, `"$SCRIPT_DIR/fixtures/fix"$n.json`, `"lib/fix"_a.json` and `"$(dirname "$0")/lib/fix"_a.json`, each RUN reason=inputs-unresolvable.
- **B2 `.aai/scripts/suite-reuse.mjs:184`**: drop the `rel.startsWith('tests/skills/')` gate on the `lib/` loop so every closure file under `tests/` is checked (the own-directory test at :189 then refuses them). RED first with a sourced `tests/other/h.sh` running `cat lib/x` and a `tests/other/a.mjs` reading `'lib/x'`.

Both are latent (no live file has the shape) and predate round 5, but they are false REUSE on forms the amended D4 (d) names as unresolvable. The fixes are small and need no spec change.

## NON-BLOCKING findings and recommended dispositions (H6)

- N1 `.aai/scripts/suite-reuse.mjs:138` `"$ROOT/docs/pro".md` (`.` or `-` after the quote) not treated as more text. Recommended: remediate in tree with B1.

accepted residual (carried from round 1): N5 - the args component is the helper's constant default, not passed by the framework; today's vector is constant and equals the default, no bite observed and no false record (P3).

INFO (does not gate): a `SCRIPT_DIR` reassigned in a sourced helper changes what a later `$SCRIPT_DIR/lib/x` in the caller reads (probe: false REUSE); cross-file variable flow is a derived form under R1. Prose like `lib/docs-model.mjs's` in tests/skills/test-aai-doc-numbering.sh is trusted through the `'` terminator and hashes an absent path; harmless today, but the B1 fix will make such prose (quote followed by `s`) unresolvable, so the remediation should re-run the corpus resolvability count and confirm the 5 manifest suites stay at 0 unresolved.

## cannot_verify

See the YAML block.

## Next steps

1. Remediation: B1, B2 (and N1) with RED-first TEST-3167 rows; selected suites plus CORE; then the validator's close-time full sweep on the fixed head.
2. Orchestrator: quote the N5 accepted residual in `code_review.notes`; record N1's disposition. This is the fourth consecutive tokenizer round; round-cap handling is the orchestrator's and owner's call.
3. Re-review after remediation: same single pass.
