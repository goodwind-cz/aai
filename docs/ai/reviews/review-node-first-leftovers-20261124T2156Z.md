# Code review: node-first-leftovers (single dual-verdict pass)

```yaml
review:
  scope: origin/main...HEAD of chore/node-first-leftovers (head 06ceb099, base 492f8b26)
  spec: docs/specs/SPEC-DRAFT-spec-node-first-leftovers.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/cloudflare-share.mjs:20,54-69 (GAP_SLACK = 2, gapped pass); TEST-4049 in tests/skills/lib/cloudflare-share.test.mjs:555; reviewer fuzz probe-echo.mjs 2000 variants, 0 leaks" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/aai-update.mjs:66-127 (BOOL_WORDS, colon split and join); TEST-4050 in tests/skills/lib/aai-update.test.mjs:595" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/aai-update.ps1:1-19 (19 lines, the aai-sync.ps1 loop); TEST-4051 in tests/skills/test-aai-update-node.sh:426" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/aai-sync.mjs:281 (which the sync manages); TEST-4052 in tests/skills/lib/aai-sync.test.mjs:873" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/scripts/aai-sync.ps1:12 and aai-update.ps1:12; Pester case tests/skills/aai-sync.Tests.ps1:94; TEST-4053 green on pwsh 7 locally, 5.1 green on hosted run 45477504577 per the validation report (5.1 RED not observed, see cannot_verify)" }
      - { ac: Spec-AC-06, call: compliant,
          citation: ".aai/scripts/aai-sync.mjs:63-84 (byte loop, EAGAIN 5 ms retry, 30 s stall bound); TEST-4054 in tests/skills/lib/aai-sync.test.mjs:891" }
      - { ac: Spec-AC-07, call: compliant,
          citation: ".aai/scripts/lib/guard-config.mjs:90 (one leading BOM dropped, out.raw keeps bytes); TEST-4055 in tests/skills/test-aai-pre-commit-checks.sh:1384" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "pre-commit-checks.sh:417, templates/git-hooks/pre-commit-index.sh:61,135, templates/git-hooks/pre-push.sh:51; TEST-4056 tests/skills/test-aai-pre-commit-checks.sh:1399; hygiene test_031 BOM variants" }
      - { ac: Spec-AC-09, call: compliant,
          citation: ".aai/scripts/lib/guard-config.mjs:299-300 (winnerLine), install-pre-commit-hook.mjs:653-663; TEST-4057 tests/skills/lib/install-pre-commit-hook.test.mjs:1365" }
      - { ac: Spec-AC-10, call: compliant,
          citation: "tests/skills/lib/install-pre-commit-hook.test.mjs:1878-1891 (SOCK_BASE, mkdtemp, rmSync); TEST-4058 tests/skills/test-aai-hook-installer-node.sh:301" }
      - { ac: Spec-AC-11, call: compliant,
          citation: "SPEC-0308 DR-20 cell line 569; CHANGELOG.md:33-45; four contract spec_amendment records in docs/ai/decisions.jsonl; spec-amend list --strict exit 0 (run by reviewer); TEST-4059" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-update.mjs, line: 74,
          issue: "isOption does not know the colon spellings the parser now accepts, so a colon-form flag after a value flag is taken as that flag's value",
          failure_scenario: "aai-update.ps1 -Ref -DryRun:true (value forgotten) reaches Node as -Ref, -DryRun:true; parseArgs yields ref '-DryRun:true', dryRun false, outcome run instead of the 'value' refusal; likewise -Repo -DryRun:true and the 5.1 split form -Repo: -DryRun:true. aai-release.mjs refuses to join any -[A-Za-z] token. Repro: reviewer probe probe-parse.mjs (session scratch, see Probes)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/guard-config.mjs, line: 300,
          issue: "winnerLine falls back to keyLines[0] when no key line has a value, so the warning names a valueless line as 'the first one with a value'",
          failure_scenario: "docs-audit.yaml 'ref_guard:\\nb: 1\\nref_guard:\\n' -> plain installer run warns '(lines 1, 3); the first one with a value wins (line 1)' while readRefGuardPolicy takes no line and falls back to armed (same as validation NB-8)" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-pre-commit-checks.sh, line: 239,
          issue: "TEST-3454 pin moved to '243 40' but the log_pass text still claims 'exactly 242 added and 39 removed lines' and the provenance comment chain has no +1 -1 entry for this ride",
          failure_scenario: "every green run of the suite prints a false pin value into the test log; the next re-pin author reconciling the comment chain cannot account for the +1 -1" }
      - { rank: NON-BLOCKING, file: tests/skills/lib/install-pre-commit-hook.test.mjs, line: 1880,
          issue: "mkdtempSync under a hard-coded /tmp runs before the try, outside the ENAMETOOLONG/EINVAL skip",
          failure_scenario: "a POSIX host without a writable /tmp (Termux, some sandboxes) now fails the whole TEST-3987 classify case with EACCES/ENOENT, where it used to pass under TMPDIR" }
  cannot_verify:
    - { claim: "Spec-AC-05 under Windows PowerShell 5.1: the unfixed launcher actually breaks the trailing backslash (the RED)",
        closes_with: "one hosted ps1-quality workflow_dispatch on a branch with the D-PS51 line removed, showing the Pester case red (validation NB-5)" }
    - { claim: "the D-PS51 line in aai-update.ps1 behaves like the tested aai-sync.ps1 copy under 5.1",
        closes_with: "a Pester or TEST-4051 case driving aai-update.ps1 through powershell.exe on the hosted leg (validation NB-4)" }
    - { claim: "the BOM-tolerant greps behave the same under GNU grep (Ubuntu CI, Git for Windows) as under BSD grep here",
        closes_with: "the skill-suite run on the pull request head (TEST-4056, hygiene test_031)" }
    - { claim: "the full sweep the spec's Verification requires before close",
        closes_with: "one full sweep recorded as a full_sweep event on the final head (validation NB-6)" }
  overall: pass
```

security_relevant: true

## Scope and inputs

- Scope: `git diff origin/main...HEAD` in /Users/ales/Projects/aai-worktrees/node-first-leftovers, head 06ceb099, 32 files.
- Spec: docs/specs/SPEC-DRAFT-spec-node-first-leftovers.md (frozen, ceremony_level 3).
- Read, not relied on: docs/ai/reports/VALIDATION-20261124T2046Z-node-first-leftovers.md (PASS).
- Dispatch note (anti-gaming rule): the dispatch told the reviewer that a conflict with the sibling ride on the `git diff --cached` lines of pre-commit-index.sh and on the TEST-308 hash pin is "expected, not a finding", and named the validation NBs already filed. That is a scope exclusion. It is recorded here. The re-pin was reviewed anyway: the TEST-308 baseline comment names the D-BOM lines as the cause, and the two BOM greps are the only changes to that template in this diff. A merge order with the sibling needs one more re-pin on whichever lands second. That is a sequencing fact, not a defect in this diff.

## AC table walk

All eleven rows are compliant (see the YAML block). Deviations from the frozen spec:

- One measurement amendment for TEST-4053's mutation (`-lt 99` instead of `-lt 0`), recorded in decisions.jsonl with a reason. It is disclosed, not hidden.
- One extra contract amendment for SPEC-0310 (the writeFd anchor of D-MODULE), which D-AMEND did not list. It is additive and recorded.
- The D-DEFER ids moved to a "left open" section by a recorded measurement amendment.

## Probes run by the reviewer

| Probe | Result |
|---|---|
| `node probe-echo.mjs`: 2000 random tokens (40 and 37 characters), up to two eaten characters via CSI, both secrets set, an independent subsequence checker | 0 leaks, 0 ESC. Ordinary error text not over-redacted. Time: 10 KB 27 ms, 100 KB 273 ms, 1 MB 1.9 s |
| `node probe-parse.mjs`: colon forms after a value flag | `-Repo -DryRun:true` gives repo `-DryRun:true`, outcome run (NB-A) |
| winnerLine dry-run on two valueless lines | winnerLine 1, the reader takes no line (NB-B) |
| BOM grep, /usr/bin/grep under bash 3.2, LC_ALL C, en_US.UTF-8, C.UTF-8 | a first-line BOM matches, plain matches, a doubled BOM does not, a line-2 BOM matches (the filed fu-bom-mirror-anchors-every-line) |
| `node -e 'Atomics.wait(...)'` on the main thread (LEARNED newly-called-API rule) | `timed-out` after 6 ms on v22.23.1: the API exists and works |
| `node .aai/scripts/spec-amend.mjs list --strict` | exit 0 |
| aai-run-tests.sh test-framework.sh --skill X for aai-update-node, aai-pre-commit-checks and aai-hook-installer-docs (fresh XDG_CACHE_HOME, env -u AAI_ROLE) | PASS each. aai-update-node took two runs: the suite exited 0 on the first run, but the tripwire flagged this review report, which the reviewer was writing at the time. The clean re-run (test-runs.jsonl) passed in 183 s |

The probe scripts live in the reviewer's session scratch directory /private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/cr-b (probe-echo.mjs, probe-parse.mjs, wl/). They are not added to the tree, and none of them backs a BLOCKING finding.

## Findings

No BLOCKING finding.

NON-BLOCKING, each with a recommended disposition:

- NB-A (P3) `.aai/scripts/aai-update.mjs:74`, `isOption`. It recognizes `-DryRun` but not `-DryRun:true`, `-DryRun:$true` or `-Force:false`, which `parseArgs` now accepts. A missing value before a colon-form switch is read as the value, and the switch is lost: `-Ref -DryRun:true` gives ref `-DryRun:true`, dryRun false, outcome run. The same happens when the 5.1 split form `-Repo:` is followed by a colon-form switch. The isOption comment says "after a value flag it is a missing value, never the value (--repo --dry-run must not drop the dry-run)", so the new forms break a stated invariant. The likely end is a clone failure on a ref or repo that does not exist, not a write, so this is P3. `aai-release.mjs` avoids it by refusing to join any `-[A-Za-z]` token. Disposition: promote to follow-up (suggested id `fu-update-isoption-colon-forms`), or remediate in tree by stripping a `:...` suffix in isOption.
- NB-B (P3) `.aai/scripts/lib/guard-config.mjs:300`. The warning names line 1 as "the first one with a value" when no key line has a value. This is the validation's NB-8, which is not yet filed. Disposition: promote to follow-up (suggested `fu-doubled-key-warning-no-valued-line`), or record it as accepted residual. It is a misleading line number in a rare file shape, and it leaves no false record in the tree.
- NB-C (P4) `tests/skills/test-aai-pre-commit-checks.sh:239`. The pass message still says 242 and 39, and the comment chain lacks this ride's +1 -1. Disposition: remediate in tree (two text lines, no behaviour change). Until then each green run prints a false pin value.
- NB-D (P4) `tests/skills/lib/install-pre-commit-hook.test.mjs:1880`. `mkdtempSync` on a hard-coded `/tmp` sits outside the try. Disposition: accepted residual: the spec froze `/tmp` for SOCK_BASE, and every supported dev host and CI runner has a writable /tmp. No bite has been observed and no record is left false.

INFO (not gating):

- TEST-4054's name claims the whole output arrives in order. It asserts the help text's first line, a `Usage` substring and the final newline, not byte equality with the help text. Every offset mutation I considered breaks the prefix, so it catches them in practice. A byte-equal compare against `HELP_TEXT` would match the claim.
- The gapped pass costs about 2 s per MB of failure echo. The echo is wrangler's failure output, normally a few KB.
- Validation NB-4 (the aai-update.ps1 D-PS51 line has no test), NB-5 (no observed 5.1 RED), NB-6 (full sweep owed) and NB-7 (the docs-audit-core loadConfig BOM) are not in the three filed follow-ups. The orchestrator still owes them a disposition.

## Warning dispositions (H6)

| Finding | Recommended disposition |
|---|---|
| NB-A | follow-up `fu-update-isoption-colon-forms` (P3), or remediate in tree |
| NB-B | follow-up `fu-doubled-key-warning-no-valued-line` (P3), or accepted residual |
| NB-C | remediate in tree |
| NB-D | accepted residual: the spec froze /tmp; all supported hosts have a writable /tmp; no observed bite and no false record |

## Next steps

1. Orchestrator: record the NB-A..NB-C dispositions and the open validation NB-4..NB-7. File the ids through `follow-ups.mjs add` (the reviewer files none).
2. Run the full sweep that the spec's Verification requires before close (validation NB-6).
3. The owner merges (L3). The sibling PR that lands second re-pins TEST-308.
