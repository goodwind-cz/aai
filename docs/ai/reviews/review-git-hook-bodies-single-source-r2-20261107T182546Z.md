```yaml
review:
  scope: "git diff main...HEAD (refactor/git-hook-bodies-single-source@595d3af1, base main 244ef0bf), the code_review.scope path list (27 paths); remediation delta 5f2991fb..595d3af1 read in full"
  spec: docs/specs/SPEC-DRAFT-spec-git-hook-bodies-single-source.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/templates/git-hooks/*.sh; TEST-3432 PASS (reviewer r2 suite run)" }
      - { ac: Spec-AC-02, call: compliant, citation: "install-pre-commit-hook.sh:196 (CDPATH= cd --), :720; TEST-3433, TEST-3445 PASS (three CDPATH shapes, spaced repo, relative path)" }
      - { ac: Spec-AC-03, call: compliant, citation: "install-pre-commit-hook.ps1:735-745; TEST-3434 PASS (pwsh 7)" }
      - { ac: Spec-AC-04, call: compliant, citation: "tests/skills/install-pre-commit-hook.Tests.ps1; TEST-3435 PASS Total=7 Failed=0 Skipped=0 (pwsh 7); 5.1 = hosted H1" }
      - { ac: Spec-AC-05, call: compliant, citation: "pre-commit-index.sh; TEST-3436 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-3437 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "sh:213-226,582,929; ps1:191-209,513,608; TEST-3438, TEST-3446, TEST-3447 PASS" }
      - { ac: Spec-AC-08, call: compliant, citation: "emit_template tr -d CR (sh:208-210), Get-TemplateBytes (ps1:181-186); TEST-3439 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "reference-transaction.sh; TEST-3440 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: "PROFILES.yaml core rows; TEST-3441 PASS" }
      - { ac: Spec-AC-11, call: compliant, citation: "vendor-hook-installer.sh:9; test-aai-git-hook-templates.sh:494-501 widened matcher + directory positive control; TEST-3442 PASS (matcher still line-start only, see NB2)" }
      - { ac: Spec-AC-12, call: compliant, citation: "suite-map.yaml, suite-weights.tsv, ps1-quality.yml, .gitattributes, cd-subshell-leak-baseline.tsv; TEST-3443 PASS" }
      - { ac: Spec-AC-13, call: compliant, citation: "sh 1017/547, ps1 819/557, templates 317 (TEST-3444 PASS); RFC-0017 phase 5 row" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/install-pre-commit-hook.ps1, line: 739,
          issue: "The malformed-template check refuses only a template with no second line. An index template whose final LF is missing passes the check; the sh composition (awk NR>1, sh:720) re-adds a trailing LF and the ps1 byte slice does not, so the twins write different pre-commit bytes and the ps1 hook ends without LF.",
          failure_scenario: "Truncate the vendored pre-commit-index.sh by its last byte, then run each installer in a fresh repo: both exit 0, cmp reports EOF on the ps1-written hook (reviewer probe, scratch). Shipped templates are pinned to one final LF by TEST-3432, so only a hand-edited downstream copy reaches this; the hook still runs under sh." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-git-hook-templates.sh, line: 499,
          issue: "bare_cp_sites now matches an installer named anywhere on a cp line, but only a cp that starts the line. The log_pass text still says 'no suite copies an installer by hand'.",
          failure_scenario: "A future fixture writes mkdir -p \"$d/.aai/scripts\" && cp \"$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.sh\" \"$d/.aai/scripts/\": TEST-3442 stays green and the fixture's installer refuses with a missing template. No current suite has such a line (reviewer grep over tests/skills/*.sh and lib/*.sh)." }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 39,
          issue: "The entry's line counts predate the remediation (sh 544/1014, ps1 550/812; tree is 547/1017 and 557/819), and the entry does not mention the new malformed-template refusal.",
          failure_scenario: "Cut the release as is: the published notes state counts that TEST-3444 itself contradicts and omit a user-visible exit-1 refusal with its own error line." }
  cannot_verify:
    - { claim: "Windows PowerShell 5.1 behaviour of the ps1 write path (Get-TemplateBytes, the new malformed check, Write-BytesViaTemp) and of the Pester file under powershell.exe",
        closes_with: "Hosted H1: ps1-quality Windows 5.1 and pwsh 7 jobs green on the PR with install-pre-commit-hook.Tests.ps1 7 passed, 0 skipped" }
    - { claim: "The Pester twin case on native Windows (Git Bash discovery, forward-slash installer path, 8.3 TestDrive names)",
        closes_with: "The same hosted Windows job log" }
    - { claim: "A real downstream aai-update delivers templates together with installers on a consumer repository with history",
        closes_with: "One real downstream aai-update run followed by bash .aai/scripts/install-pre-commit-hook.sh --force" }
    - { claim: "Owner acceptance of Amendment 2 (contract class, unsigned, tracked by fu-amend-git-hook-bodies-single-source)",
        closes_with: "Owner sign-off or reversal before merge" }
  overall: pass
```

# Code review: git-hook-bodies-single-source (round 2)

security_relevant: true

- Scope: `git diff main...HEAD` on `refactor/git-hook-bodies-single-source@595d3af1` (base `main` `244ef0bf`), over the 27-path `code_review.scope` list in STATE. I read the remediation delta `5f2991fb..595d3af1` in full and re-walked the whole scope. Two uncommitted files (`docs/ai/EVENTS.jsonl`, `docs/ai/tests/test-runs.jsonl`) are telemetry outside the scope and were not touched.
- Spec: `docs/specs/SPEC-DRAFT-spec-git-hook-bodies-single-source.md`, frozen, Amendments 1 and 2.
- Reviewer: one fresh dual-verdict pass, verdict formed from the code. Own runs on 595d3af1:
  - `bash tests/skills/test-aai-git-hook-templates.sh` (env -u AAI_ROLE -u AAI_GIT_WRITE): rc 0, 16 of 16 PASS, no SKIP-CASE, Pester 7/7/0/0 (55 s).
  - `spec-lint --path <spec>`: LINT PASS. `mutation-gate --spec <spec>`: GATE PASS, 16 rows. `spec-amend list --strict`: rc 0.
  - A scratch probe of an index template without its final LF (NB1).
  - No full sweep.
- `security_relevant: true` carries over from r1 (B1 disabled secrets-guard installation).
- Dispatch prompt: no coaching. It named no focus areas or expected findings.

## Verdict 1: spec_compliance = pass

All 13 Spec-AC rows are compliant (YAML above). TEST-3445..3447 exist, are called from `main`, and pass. They are recorded in the Test Plan with mutation strings, and the mutation gate accepts all 16 rows.

Deviations from the frozen text:

1. Amendment 2 widens Spec-AC-02 and Spec-AC-07 and adds the D-MISSING malformed paragraph. It is a contract-class amendment with no owner sign-off, tracked by `fu-amend-git-hook-bodies-single-source` (open). It tightens behaviour and weakens nothing.
2. The sh installer's `--print index` now also refuses a malformed index template (`require_templates` runs on the print path, sh:236). The ps1 has no print. Amendment 2 says "before any write"; refusing a write-free print is stricter than the text. Info only.
3. A malformed index template also refuses the guard-block upgrade path, which does not compose from the index template. This follows "refuse before any write" literally and is the same in both installers. Info only.
4. Carried over from r1, unchanged: the sh reference-transaction write (sh:408) redirects straight into the slot, not via a temp sibling; the ps1 rename replaces a symlinked slot under `-Force`; two em dashes became `--`.

## Verdict 2: code_quality = pass

### r1 findings, re-checked against the code

- **B1 (fixed).** sh:196 is now `CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")"`. It is the only `cd` in the installer. The helper (`vendor-hook-installer.sh:9`) and the suite header use the same form. TEST-3445 drives the relative-path install under `.`, `.:$HOME` and `:$HOME` from a spaced repo. The cd-subshell-leak ratchet passes inside TEST-3443.
- **NB1 r1 (fixed for the specified shape).** sh:220 counts lines after CR removal, and ps1:199-206 checks for an LF with something after it. Both give the same result for no-LF, one-line, CRLF-one-line and empty files, and both refuse before `ensure_hooks_dir`. A residual remains (NB1 below).
- **NB2 r1 (partially fixed).** The matcher now looks for the installer name anywhere on a cp line and has a directory-destination positive control. It is still limited to a cp at the start of a line (NB2 below).
- **NB3 r1 (fixed).** TEST-3447 pins arming with a missing template for both installers: exit 1, the D-MISSING line, and no hook and no config written.

### BLOCKING

None.

### NON-BLOCKING (recommended disposition; the orchestrator records it)

**NB1: `.aai/scripts/install-pre-commit-hook.ps1:739` (vs `.sh:720`). A missing final LF passes the malformed check and breaks twin parity.**
- Reviewer probe: vendor each installer into a fresh scratch repo, drop the last byte of `pre-commit-index.sh`, and install. Both installers exit 0. `cmp` reports EOF on the ps1-written pre-commit, and its last bytes are `md"` with no LF.
- The validator's r2 NB1 found the same thing independently.
- Severity: P3. Only a hand-edited template reaches it (TEST-3432 pins the shipped bytes), the hook still runs, and no record is false.
- Recommended disposition: (a) in tree. Extend both malformed checks to require a final LF (sh: `tail -c1` of `emit_template index` must be a newline; ps1: `$tb[-1] -eq 10`), and add one shape to TEST-3446. Otherwise (d) accepted residual.

**NB2: `tests/skills/test-aai-git-hook-templates.sh:499` (`bare_cp_sites`). Only a cp at the start of a line is matched.**
- It misses `... && cp <installer> ...`, `( cp ... )`, and a `cp -R .aai/scripts` without the templates.
- No current violator exists. The whole-tree `cp -R .aai/scripts/.` sites (docs-audit:8992, ride-select:1266/1299) copy into git clones that already hold the tracked templates, and they do not run the installer standalone.
- The test name (`test_3442_fixtures_use_helper`) does not claim the universal negative, but its `log_pass` text does.
- Recommended disposition: (b) `fu-` P3 follow-up (match `cp` after `^|&&|;|\(`, add a positive control), or (a) narrow the `log_pass` wording to "no line-leading cp".

**NB3: `CHANGELOG.md:39`. Stale counts and an undisclosed refusal.**
- The entry says sh 544/1014 and ps1 550/812. The tree has 547/1017 and 557/819, which TEST-3444 prints.
- The new `ERROR: AAI hook template malformed ...` exit-1 refusal is not mentioned.
- This is a product-doc fix, due after LOOP COMPLETE per the ship convention.
- Recommended disposition: (a) in tree, at the product-doc step before the PR.

### Checked and clean

- **Pipefail in the new check.** sh:220 pipes `tr` into `awk 'END{...}'`, and awk reads to EOF. The check sits in an `elif` condition, so `set -e` does not fire on it.
- **ps1 5.1 syntax of the new check.** It uses `[Array]::IndexOf` with a `[byte]` and positional `Get-TemplateBytes`. There is no 7-only syntax. Empty-file handling: `-ne 13` on an empty array gives an empty `byte[]`, and `IndexOf` returns -1, so the file is refused.
- **Test hygiene.**
  - New cases use absolute-path `cd` in subshells, so CDPATH is never consulted.
  - Fixtures live in mktemp dirs with spaced names.
  - `malformed_round` pre-seeds pre-push and asserts it is unchanged, which proves no partial write.
  - The `/usr/bin/grep -qxF` asserts read a file, not a pipe.
- **TEST-3447 RED status.** It is a coverage pin for code that was already correct. Its RED proof is the mutation record (`require_templates ref-guard` mutated to `: ref-guard`), and the gate accepts it. The validator's NB5 (no stored red logs for 3445..3447; evidence cells name only r1 logs) is a close-flip reconciliation item, not a code defect.

## cannot_verify

1. Windows PowerShell 5.1 runtime behaviour of the ps1 path, including the new malformed check, and of the Pester file. Closes with hosted H1 green on the PR.
2. The Pester twin case on native Windows. Closes with the same hosted log.
3. A real downstream aai-update that delivers templates with installers. Closes with one real downstream run.
4. Owner acceptance of Amendment 2, the unsigned contract amendment. Closes with sign-off or reversal before merge.

## Warning dispositions (H6), recommended

| Finding | Recommended | Notes |
|---|---|---|
| NB1 | (a) in tree, else (d) | P3, hand-edited template only, no false record |
| NB2 | (b) fu P3, or (a) narrow the log_pass wording | assurance gap in a negative guard |
| NB3 | (a) at the product-doc step | user-facing notes must match the tree |

accepted residual: (only if the orchestrator picks (d) for NB1) P3 maintenance edge: a hand-truncated index template without a final LF yields a ps1 hook one byte shorter than the sh twin. It still runs, and nothing records it as identical.

## Next steps

1. The orchestrator records the dispositions for NB1 through NB3. If NB1 or NB3 go in tree, a small delta re-check follows.
2. Run the close-ceremony full sweep (owed per validation r2) before close.
3. On the PR: confirm H1, and get the owner's decision on Amendment 2 at merge.
