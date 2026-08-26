```yaml
review:
  scope: "main...2ec19db102c35686e43f236b1a1ccdbc718b3b1c plus working-tree docs/ai/EVENTS.jsonl; exact 102-path set in STATE code_review.scope"
  spec: docs/specs/SPEC-0154-spec-harness-surfaces-drift-unguarded.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-001 / tests/skills/test-aai-hygiene-pack.sh:1745-1789; fresh aai-hygiene-pack PASS, 39 skills" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-002, TEST-003 / tests/skills/test-aai-hygiene-pack.sh:1792-1816; sync-harness-skills.mjs --check exit 0" }
      - { ac: Spec-AC-03, call: compliant, citation: "TEST-004 / tests/skills/test-aai-hygiene-pack.sh:1819-1847; .aai/scripts/sync-harness-skills.mjs:120-137" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-006 / tests/skills/test-aai-hygiene-pack.sh:2011-2054; check-test-registration.mjs exit 0" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-007 / tests/skills/test-aai-hygiene-pack.sh:1872-1948; fresh control and three bite proofs PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-005 / tests/skills/test-aai-hygiene-pack.sh:1745-1789,1819-1869; manifest exclusions empty at .aai/system/HARNESS_SKILLS.yaml:60" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-008 / tests/skills/test-aai-hygiene-pack.sh:1951-1979; .cursor/rules/aai.mdc:1-32; current official Cursor Rules and Agent Skills docs" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-009 / tests/skills/test-aai-hygiene-pack.sh:1982-2008; AGENTS.md:1; .aai/system/HARNESS_SKILLS.yaml:35-53" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-010 / tests/skills/test-aai-suite-select.sh:361-388; tests/skills/suite-map.yaml:362-375" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-011..014; final-HEAD run test-20260825-215029 is 81/81; prompt corpus 315049; scoped suites fresh PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/sync-harness-skills.mjs, line: 256, issue: "A trailing --manifest or --root with no value is accepted and silently replaced by the default live-repository path, contradicting the documented usage-error exit-2 contract.", failure_scenario: "Run `node .aai/scripts/sync-harness-skills.mjs --check --root` or the same command ending in `--manifest`; both exit 0 after checking the live repository, so a mistyped fixture command can report OK for the wrong tree." }
      - { rank: NON-BLOCKING, file: .aai/scripts/sync-harness-skills.mjs, line: 350, issue: "--write follows a mirror skill-directory symlink without checking that the resolved target remains under the mirror tree.", failure_scenario: "If .gemini/skills/<expected-skill> is a symlink to another writable directory, --write treats the skill as missing and writes SKILL.md through the symlink outside the repository." }
  cannot_verify:
    - { claim: "Actual discovery, deduplication, and precedence behavior in installed Cursor, Codex, and Gemini clients", closes_with: "An end-to-end smoke in each supported client showing all 39 skills and, for Cursor, which duplicate path wins" }
  overall: pass
```

# Final Code Review — harness-surfaces-drift-unguarded

This is the final **Code Review** pass at `2ec19db102c35686e43f236b1a1ccdbc718b3b1c`. Both independent verdicts pass. The result is conditional on dispositioning the two NON-BLOCKING warnings before closeout under H6.

## Scope preflight

- Branch: `fix/harness-surface-parity`; merge base: `17caf5d26e861a9e2d546c39076fab4bf19b29f8`.
- Reviewed scope: `git diff main...2ec19db102c35686e43f236b1a1ccdbc718b3b1c` plus the one declared working-tree append in `docs/ai/EVENTS.jsonl`.
- `git status --porcelain` before the report contained only `M docs/ai/EVENTS.jsonl`.
- The union of committed and working-tree paths is 102 paths; it equals the 102 paths in `STATE.code_review.scope`, with no missing or extra path.
- `main` is a byte-exact prefix of `docs/ai/EVENTS.jsonl`, `docs/ai/decisions.jsonl`, and `docs/ai/tests/test-runs.jsonl`. The local event is one append-only `validation_verdict`; no ledger byte was reordered or removed.
- The dispatch contained no expected finding, severity coaching, or scope exclusion. The entire declared scope was reviewed.

## Verdict 1 — spec_compliance: PASS

| AC | Call | Evidence |
|---|---|---|
| Spec-AC-01 | compliant | `test_110` proves exact set equality across all four trees; the fresh suite reports 39 skills. |
| Spec-AC-02 | compliant | Generator `--check` exits 0; `test_111` proves a following `--write` changes no mirror bytes and both generated indexes list 39 skills. |
| Spec-AC-03 | compliant | `test_112(a)` removes the `.codex/skills` manifest row and observes exit 2 naming it. Current validation also rejects manifest rows outside the hardcoded mirror set. |
| Spec-AC-04 | compliant | `test_110` through `test_115` are called by `main()`; the fresh hygiene suite and independent registration checker both exit 0. |
| Spec-AC-05 | compliant | `test_113` creates a disposable detached worktree, runs a green control, and proves add-source/delete-Codex/edit-description mutations independently redden with named offenders. |
| Spec-AC-06 | compliant | `test_110` proves one-pair exclusion scope; `test_112` rejects empty-reason and stale exclusions. The shipped manifest has zero exclusions. |
| Spec-AC-07 | compliant | The 32-line rule passes all five TEST-008 observables. Current official Cursor documentation confirms `.mdc` rules use `description`, `globs`, and `alwaysApply`, and skills load from `.agents/skills`, `.cursor/skills`, plus Claude/Codex compatibility directories. |
| Spec-AC-08 | compliant | Root `AGENTS.md` begins `# Agent Instructions (Shim)`; manifest lines 35-53 record D2 and D3. |
| Spec-AC-09 | compliant | `test_020` individually maps all five named surfaces to `aai-hygiene-pack` with no `FULL_RUN reason=unmapped`. |
| Spec-AC-10 | compliant | Commit `2ec19db` records final-HEAD run `test-20260825-215029` at 81/81. Fresh scoped suites all pass; corpus is 315049 bytes; profile and close-work-item pins pass; no protected path is in the diff. |

Every TEST-001..014 exists. TEST-001..010 are implemented by `test_110`..`test_115` and `test_020`; TEST-011..014 are covered by the profile, prompt-diet, full-framework, and doc-numbering suites. The AC/Test status cells remain `planned`/`pending`; this is close-ceremony metadata under the current workflow, not missing implementation evidence. The close step must substitute the cited evidence and terminal statuses rather than claiming they were already flipped.

The previous round's in-tree findings are closed at this HEAD: undeclared manifest rows are refused, unreadable mirror files are named, an absent live mirror tree fails the bash arm, the pinned grep binary is used, and final-HEAD 81/81 evidence is committed.

## Verdict 2 — code_quality: PASS

No BLOCKING finding was found. There are two NON-BLOCKING findings.

### NB-1 — missing option values silently select the live repository

At `.aai/scripts/sync-harness-skills.mjs:256-257`, `argv[++i]` is not checked. At lines 268-271, the resulting `undefined` value activates the default root or manifest. Concrete reproduction at this HEAD:

```text
$ node .aai/scripts/sync-harness-skills.mjs --check --root
OK: .agents/skills, .codex/skills, .gemini/skills match the declared transform
exit 0

$ node .aai/scripts/sync-harness-skills.mjs --check --manifest
OK: .agents/skills, .codex/skills, .gemini/skills match the declared transform
exit 0
```

That is a false-green usage path: a fixture or automation typo checks the live repository instead of the intended target. It does not affect correctly formed invocations and therefore does not block the current normalization.

Disposition: **remediate-in-tree before closeout** by rejecting a missing/option-shaped value for both flags with exit 2, plus a regression arm in `test_112`.

### NB-2 — write containment does not reject mirror-directory symlinks

At `.aai/scripts/sync-harness-skills.mjs:329-351`, a missing expected target leads to `mkdirSync(path.dirname(targetPath), {recursive:true})` and `writeFileSync(targetPath, ...)`. A symlink at the expected skill directory is not included by `Dirent.isDirectory()`, but the subsequent write follows it. Thus a malformed or accidentally symlinked mirror can make `--write` create or overwrite a `SKILL.md` outside the repository. The threat is bounded because running modified repository tooling is already trusted-code execution, and `--check` performs no write.

Disposition: **promote-to-follow-up-ref `fu-harness-sync-symlink-containment` (P3)** before closeout. The follow-up should add an `lstat`/realpath containment refusal and a scratch-fixture regression. This warning is not eligible for an accepted-residual-only disposition because the write-through scenario has a concrete bite.

The two `git checkout --` calls in `test_113` are noted but not ranked as defects: they operate only in a freshly created absolute disposable worktree, each is followed immediately by a clean control, and the EXIT trap removes that exact worktree. Replacing them with byte copies would align more literally with HAZ-RESTORE, but the present sequence has no shipping-tree failure scenario.

## Cannot verify

- Actual client discovery/dedup/precedence behavior was not exercised in installed Cursor, Codex, and Gemini clients. Current official documentation and repository parity substantiate the declared filesystem contracts, but only end-to-end client smokes can close this external-runtime gap.

## Verification performed

| Command or check | Exit | Relevant result |
|---|---:|---|
| `node .aai/scripts/sync-harness-skills.mjs --check` | 0 | all three mirrors match the declared transform |
| canonical wrapper + `test-aai-hygiene-pack.sh` | 0 | all tests pass, including `test_110`..`test_115` |
| canonical wrapper + `test-aai-suite-select.sh` | 0 | all tests pass, including `test_020` |
| canonical wrapper + `test-aai-layer-profiles.sh` | 0 | 225/225 `.aai` files classified; all tests pass |
| canonical wrapper + `test-aai-prompt-diet.sh` | 0 | all tests pass; corpus contract remains green |
| canonical wrapper + `test-aai-doc-numbering.sh` | 0 | all tests pass; close-work-item pin holds |
| `node .aai/scripts/check-test-registration.mjs tests/skills` | 0 | no orphan test functions |
| `node .aai/scripts/docs-audit.mjs --check --strict --no-event` | 0 | CLEAN |
| `git diff --check main...HEAD` and working event diff | 0 | no whitespace errors |
| scope set comparison | 0 | declared 102 = reviewed 102; no missing/extra paths |
| ledger prefix comparisons | 0 | all three append-only ledgers preserve `main` byte-for-byte |
| `/bin/bash -c 'cat .aai/*.prompt.md \| wc -c'` | 0 | `315049` |
| committed final full sweep | 0 | run `test-20260825-215029`: 81 passed, 0 failed, 0 skipped |

## Next steps

Post-review dispositions recorded by the orchestrator:

1. NB-1 was remediated in tree at the parser boundary. Missing or option-shaped
   values for both `--root` and `--manifest` now exit 2 with a flag-specific
   message; the regression arm reached RED, then GREEN, and the full
   `aai-hygiene-pack` suite passed.
2. NB-2 was promoted to the open P3 follow-up
   `fu-harness-sync-symlink-containment` in `docs/ai/decisions.jsonl`.
3. Close ceremony must update AC/Test statuses and evidence cells, preserving
   the evidence above.

Overall review verdict: **PASS**. The orchestrator dispositions above satisfy
the two H6 conditions; post-review code changes still require fresh validation
and review before closeout.
