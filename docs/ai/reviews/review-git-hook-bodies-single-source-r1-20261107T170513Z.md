```yaml
review:
  scope: "git diff main...HEAD (refactor/git-hook-bodies-single-source@5f2991fb, base main 244ef0bf), the code_review.scope path list"
  spec: docs/specs/SPEC-0278-spec-git-hook-bodies-single-source.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/templates/git-hooks/*.sh (mode 100644, ASCII, one final LF, checked); TEST-3432 PASS r1-suite log" }
      - { ac: Spec-AC-02, call: compliant, citation: "install-pre-commit-hook.sh:196-235,717; TEST-3433 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "install-pre-commit-hook.ps1:181-220,729-734,772-795; TEST-3434 PASS (pwsh 7)" }
      - { ac: Spec-AC-04, call: compliant, citation: "tests/skills/install-pre-commit-hook.Tests.ps1 (7 cases); TEST-3435 PASS Total=7 Failed=0 Skipped=0 under pwsh 7; 5.1 = hosted H1" }
      - { ac: Spec-AC-05, call: compliant, citation: "pre-commit-index.sh:12-13,58,70-71,81-82,124; TEST-3436 PASS; validator baseline RED reproduced" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-3437 PASS; reviewer scan of the templates finds no pipe into grep -q/head/quiet reader" }
      - { ac: Spec-AC-07, call: compliant, citation: "install-pre-commit-hook.sh:213-224,579,919-927; .ps1:190-201,506,597-601; TEST-3438 PASS; reviewer probe of --arm-ref-guard/-ArmRefGuard with a missing template in a spaced path: rc 1, D-MISSING line, no hook, no config" }
      - { ac: Spec-AC-08, call: compliant, citation: "emit_template tr -d CR (sh:208-210), Get-TemplateBytes -ne 13 (ps1:184-188); TEST-3439 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "reference-transaction.sh:31-39; TEST-3440 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: "PROFILES.yaml core rows; TEST-3441 PASS" }
      - { ac: Spec-AC-11, call: compliant, citation: "tests/skills/lib/vendor-hook-installer.sh; TEST-3442 PASS (guard weaker than stated, see NB2)" }
      - { ac: Spec-AC-12, call: compliant, citation: "suite-map.yaml, suite-weights.tsv, ps1-quality.yml x2, .gitattributes:7; TEST-3443 PASS" }
      - { ac: Spec-AC-13, call: compliant, citation: "sh 1014/544, ps1 812/550, templates 317; RFC-0017 phase 5 row; TEST-3444 PASS" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/install-pre-commit-hook.sh, line: 196,
          issue: "SCRIPT_DIR is resolved with a bare cd, so an exported CDPATH makes cd print the directory into the command substitution. TEMPLATE_DIR then points at a non-existent path and every install refuses. The repo convention is CDPATH= cd -- (triage.sh, aai-live.sh, validate-skills.sh and two more launchers).",
          failure_scenario: "export CDPATH=.:$HOME; then, at a repo root, run bash .aai/scripts/install-pre-commit-hook.sh, the canonical SKILL_UPDATE step-4 command. It prints ERROR: AAI hook template missing: <root>/.aai/scripts\\n<root>/.aai/templates/git-hooks/... and exits 1, and no hook is installed (the secrets guard included). Reproduced by the reviewer with --print ref-guard. main 244ef0bf has no SCRIPT_DIR and installs normally: this is a regression." }
      - { rank: NON-BLOCKING, file: .aai/scripts/install-pre-commit-hook.ps1, line: 731,
          issue: "The composition assumes the index template has an LF after line 1 and a second line. The .sh (awk NR==1) yields a different shape on the same input, so twin parity also breaks there.",
          failure_scenario: "A hand-edited downstream pre-commit-index.sh without an LF: IndexOf gives -1, and 0..-1 takes byte 0 plus the last byte. The ps1 writes '#N' + guard block + the whole template into the slot, then exits 1 at the post-condition. A broken hook is left in place. Shipped templates are pinned by TEST-3432, so only a malformed copy reaches this." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-git-hook-templates.sh, line: 496,
          issue: "bare_cp_sites matches only a cp line that ENDS in the installer file name (the destination). The spec's guard is about the copied path (the source). A cp into a directory destination, which is the helper's own shape (vendor-hook-installer.sh:12,15), is not detected.",
          failure_scenario: "A future fixture adds cp \"$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.sh\" \"$d/.aai/scripts/\" without the templates. TEST-3442 stays green, and the fixture's installer refuses with a missing template. log_pass still claims 'no suite copies an installer by hand'." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-git-hook-templates.sh, line: 389,
          issue: "TEST-3438 covers only the default --hooks all selection. D-MISSING also names --arm-ref-guard/-ArmRefGuard, and that path has its own check (sh:579, ps1:506) with no test.",
          failure_scenario: "A refactor that drops require_templates from arm_ref_guard would truncate the slot (emit_template ref-guard > \"$REFTX_PATH\" with a missing file) and record ref_guard: armed. No test reddens. The reviewer's manual probe shows the current code correct." }
  cannot_verify:
    - { claim: "Windows PowerShell 5.1 behaviour of the new write path (Get-TemplateBytes, Write-BytesViaTemp on fresh slots, Move-Item -Force over an existing file) and of the Pester file under powershell.exe",
        closes_with: "Hosted H1: the ps1-quality Windows 5.1 and pwsh 7 jobs green on the PR with install-pre-commit-hook.Tests.ps1 discovered, 7 passed, 0 skipped" }
    - { claim: "The Pester twin case on native Windows (Git Bash located from git.exe, a C:/ forward-slash installer path, TestDrive 8.3 short names matching the D-MISSING path in -BeLike)",
        closes_with: "The same hosted Windows job log" }
    - { claim: "Downstream installs that refresh through aai-update/aai-sync on a real consumer repository (not a scratch target) receive the templates together with the installers",
        closes_with: "One real downstream aai-update run followed by bash .aai/scripts/install-pre-commit-hook.sh --force" }
  overall: fail
```

# Code review: git-hook-bodies-single-source (round 1)

security_relevant: true

- Scope: `git diff main...HEAD` on `refactor/git-hook-bodies-single-source@5f2991fb` (base `main` `244ef0bf`), over the `code_review.scope` path list in STATE (27 paths). The worktree has two uncommitted modified files, `docs/ai/EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl`. Both are validation telemetry, outside the review content, and were left untouched.
- Spec: `docs/specs/SPEC-0278-spec-git-hook-bodies-single-source.md`, frozen, with Amendment 1.
- Reviewer: one fresh dual-verdict pass. I read the code directly and ran my own scratch probes in the session scratchpad. I did not run a full sweep. The suite evidence I cite is the validation r1 log `docs/ai/validation/git-hook-bodies-single-source/r1-suite-git-hook-templates.log`: 13 of 13 PASS, 0 SKIP-CASE, Pester 7 of 7.
- Why `security_relevant: true`: the BLOCKING finding stops the AAI:GUARD-CHECKS secrets guard and the ref guard from being installed at all.
- Coaching attempt recorded (anti-gaming contract): the dispatch prompt named focus areas and pointed at the validator's NB1 with "judge severity". I reviewed the full scope regardless. NB1 is ranked independently below, and the BLOCKING finding lies outside the named focus list.

## Verdict 1: spec_compliance = pass

All 13 Spec-AC rows are compliant; the per-row citations are in the YAML block above. All claimed TEST-3432..3444 exist in `tests/skills/test-aai-git-hook-templates.sh`, are called from `main`, and pass in the validation log.

Deviations from the frozen text (listed per contract; none fails a row):

1. D-COMPOSE says that both installers "write through a temp sibling and rename". The `.sh` reference-transaction write (`install-pre-commit-hook.sh:405`) still redirects straight into the slot. This is unchanged from the baseline, and the spec's parenthetical names only pre-commit and pre-push for the `.sh`. No AC row covers it.
2. The PowerShell installer now writes fresh slots through `Write-BytesViaTemp`. With `-Force`, that rename replaces a symlinked slot instead of writing through it, as `Set-Content` did at the baseline. This is safer, since the baseline wrote outside the repository, but it is a behaviour change that neither D-TPL nor the CHANGELOG lists. Info only.
3. Validator NB3 (the em dash becomes `--` in two stderr messages) is confirmed. It follows D-TPL's explicit dash rule.

## Verdict 2: code_quality = fail

### BLOCKING

**B1: `install-pre-commit-hook.sh:196`. A bare `cd` in `SCRIPT_DIR` breaks every install under an exported CDPATH.**

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

- When the installer is run by a relative path, the documented command `bash .aai/scripts/install-pre-commit-hook.sh` (SKILL_UPDATE step 4), the `cd .aai/scripts` consults CDPATH.
- With `export CDPATH=.:$HOME`, bash prints the matched directory to stdout. That output lands inside the substitution, so `SCRIPT_DIR` holds two lines.
- `TEMPLATE_DIR` is then a non-existent path, and every selection refuses with `ERROR: AAI hook template missing: …` and exit 1. No hook is installed, including the secrets guard block.
- Reproduced in a scratch target whose path contains a space:
  - with CDPATH exported: rc 1, and the message shows a two-line path;
  - with CDPATH unset: works.
- The baseline installer had no `SCRIPT_DIR`, so this is a regression. It fails closed and loudly, but it disables guard installation on every sync on such a machine.
- The repo already knows this hazard. Five launchers use `CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")"`, for example `.aai/scripts/triage.sh:4`.
- Fix: `SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"`, plus a RED-first case in TEST-3433 or TEST-3441 that runs the target's installer by its relative path with `CDPATH=.` exported. The `cd-subshell-leak-baseline.tsv` row for the installer may need re-recording if the ratchet counts change.

### NON-BLOCKING (each with a recommended disposition; the orchestrator records it)

**NB1: `install-pre-commit-hook.ps1:731-732`. The composition assumes the index template holds an LF and a second line.** (This is the validator's NB1, re-ranked independently.)

- Probe: with an index template that has no LF, the ps1 wrote `#N` + guard block + the whole template, and the `.sh` wrote line 1 + LF + guard block.
- Both then exit 1 at the post-condition, and both leave the malformed hook in the slot.
- Only a hand-edited or truncated template reaches this. Shipped templates are pinned by TEST-3432 and arrive byte-identical through aai-sync (TEST-3441).
- Severity P3: there is no false record, and the refusal is loud (exit 1).
- Recommended disposition: (a) remediate in tree if B1's round is open anyway. Guard `$firstNl -lt 0 -or $firstNl -ge $idxBytes.Length - 1` with a named refusal before any write, and in the `.sh` require at least two lines. Otherwise (d) accepted residual.

**NB2: `tests/skills/test-aai-git-hook-templates.sh:496` (`bare_cp_sites`). The guard tests the destination, not the copied path.**

- It matches only a `cp` line that ends in the installer file name.
- `cp "$X/install-pre-commit-hook.sh" "$d/.aai/scripts/"` is the helper's own shape, and it is not detected.
- The positive control uses only the shape the matcher was built for.
- No current violator exists: the reviewer grepped every `tests/skills/*.sh` and `lib/*.sh`.
- Recommended disposition: (a) remediate in the same round. Match any `cp` line that names `install-pre-commit-hook.(sh|ps1)` anywhere outside the helper, and add a directory-destination positive control. If not, (b) a follow-up `fu-` P3 entry.

**NB3: `tests/skills/test-aai-git-hook-templates.sh:389` (TEST-3438). `--arm-ref-guard` / `-ArmRefGuard` with a missing template is not covered.**

- D-MISSING names both flags. The code is correct: the reviewer probed both installers, which returned rc 1, the D-MISSING line, no hook and no `docs/ai/docs-audit.yaml` written.
- No test pins this.
- Recommended disposition: (a) add one arm round to `missing_round` in B1's round, or (d) accepted residual: P3, an unexercised edge with no observed bite.

### Checked and clean (no finding)

- **Early-closing readers.** The templates hold no pipe into `grep -q`, `grep -Eq`, `head`, `sed q` or a quiet reader. The remaining pipes go into `grep -E`, `grep -Ev` or `grep -oE`, which read to EOF. In `install-pre-commit-hook.sh:717` and `:818`, the producers pipe into `awk` with no `exit`, which reads to EOF.
- **Paths with spaces.** Every template path is quoted in the `.sh`. The `.ps1` uses `Test-Path -LiteralPath`, and `Join-Path` adds no wildcard resolution. A missing template in a spaced downstream path refuses with the absolute path (probed).
- **PowerShell 5.1 syntax.**
  - Only nested two-argument `Join-Path` is used (no `-AdditionalChildPath`).
  - `[UTF8Encoding]::new` is 5.0+. There is no `??`, ternary or `-Parallel`.
  - `$IsLinux`/`$IsMacOS` evaluate to `$null` on 5.1 because no StrictMode is set.
  - `WriteAllBytes` writes no BOM.
  - `Write-BytesViaTemp` already existed at the baseline (upgrade path). The Pester upgrade case runs it over an existing file on 5.1 in H1.
- **D-MISSING ordering.** Both installers check the templates before `ensure_hooks_dir` / `Confirm-HooksDir`, before any hook write and before the arm config write. `--uninstall` and decline need no template (TEST-3438, Pester case 7).
- **Existing installs.** A plain re-run keeps the bytes. The interior compare in `Update-PreCommitHook` / `upgrade_precommit_hook` reads the shipped block from the template, and the block is byte-identical to the baseline. TEST-3439 runs each installer over the other's hooks.
- **Test quality.**
  - Each integration row compares against bytes composed independently in the test (`sed`/`cat` in bash).
  - The Pester twin case uses the sh installer as an independent oracle, so the mirrored `Get-Composed` logic is not the only one.
  - Negatives carry positive controls (TEST-3432 on the baseline installers, TEST-3437 against the baseline `hookBody`, TEST-3442 against a scratch suite).
  - Both installers are covered in TEST-3434/3436/3438/3439/3440/3441.
- **Wiring.** suite-map (129 rows), weights, the ps1-quality push and pull_request lists, `.gitattributes`, PROFILES core, and the comment-only `guard-config.mjs` edit. No prompt or L3 file changed.

## cannot_verify

1. Windows PowerShell 5.1 runtime behaviour of the new ps1 write path and of the Pester file. Closes with hosted H1 green on the PR.
2. The Pester twin case on native Windows (Git Bash discovery, forward-slash path, matching short-name TestDrive paths). Closes with the same hosted job log.
3. A real downstream aai-update that delivers templates together with installers. The scratch `aai-sync` covers the mechanism, but not a consumer repository with history. Closes with one real downstream run.

## Warning dispositions (H6), recommended

| Finding | Recommended | Notes |
|---|---|---|
| NB1 | (a) in B1's remediation round, else (d) | P3, refused loudly |
| NB2 | (a) in B1's round, else (b) fu P3 | assurance gap in a negative guard |
| NB3 | (a) in B1's round, else (d) | P3, current code probed correct |

accepted residual: (only if the orchestrator picks (d) for NB1/NB3) P3 maintenance edges with no observed bite and no false record.

## Next steps

1. Remediation: fix B1 RED-first: a fixture with `export CDPATH=.` that runs the target installer by its relative path. Then optionally fold NB1–NB3.
2. Fresh re-review (rule 13) on the remediation delta.
3. On the PR: confirm H1 (Windows 5.1 and pwsh 7 Pester) before the owner merges.
