# Code Review — git-platform-detected-at-bootstrap, round 1

```yaml
review:
  scope: "git diff feca6e0b..HEAD (HEAD 19b2f100, branch change/git-platform-detected-at-bootstrap), limited to STATE code_review.scope"
  spec: docs/specs/SPEC-DRAFT-spec-git-platform-detected-at-bootstrap.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "platform.mjs:94-128, platform-adapter.mjs:22-44; TEST-062 PASS" }
      - { ac: Spec-AC-02, call: compliant, citation: "platform.mjs:105-128 (mismatch && !opts.force, rewritePlatformLine:77-86); TEST-063 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "platform-adapter.mjs:81-102; TEST-064 PASS (win32 cli_missing gap NB-7)" }
      - { ac: Spec-AC-04, call: compliant, citation: "aai-bootstrap.sh record_git_platform + print_summary; SKILL_BOOTSTRAP Git platform section; TEST-065 PASS incl. pwsh arm (validation r1)" }
      - { ac: Spec-AC-05, call: compliant, citation: "platform-adapter.mjs:151-276; TEST-066 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "platform-adapter.mjs:279-290, merge-cleanup.mjs:162-166; TEST-067, TEST-068 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "platform-adapter.mjs:73-79; TEST-069 PASS; reviewer probe azSpawnSpec(win32)" }
      - { ac: Spec-AC-08, call: compliant, citation: "merge-cleanup.mjs:1249-1300, platform-adapter.mjs:273; TEST-070 PASS; validation #468 probe" }
      - { ac: Spec-AC-09, call: compliant, citation: "platform.mjs:168-200; TEST-071 PASS (anchor spelling deviation, see Deviations)" }
      - { ac: Spec-AC-10, call: compliant, citation: "merge-cleanup.mjs:1005-1006 via adapter.listDependents; TEST-072 PASS" }
      - { ac: Spec-AC-11, call: compliant, citation: "merge-cleanup.mjs:149-160, platform.mjs:174-176; TEST-073, TEST-071 mismatch arm PASS (deviation: platform.mjs text lacks record --force, NB-4)" }
      - { ac: Spec-AC-12, call: compliant, citation: "merge-cleanup.mjs:150-157 legacy notice; TEST-074 PASS; suite + Pester twin rc=0 (validation r1)" }
      - { ac: Spec-AC-13, call: compliant, citation: "tests/skills/lib/platform-direct-calls.mjs; reviewer run: PLATFORM-CALLS clean 1 files; TEST-075 PASS" }
      - { ac: Spec-AC-14, call: compliant, citation: "SKILL_MERGE.prompt.md:15-16, prompt-diet-ledger.sh (687 B), PROFILES.yaml, pr-config.yaml; TEST-076 PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/SKILL_MERGE.prompt.md, line: 15,
          issue: "Canon names the Azure merge line but not its outcomes: exit 4 completion_pending, exit 5 head_race_lost, and exit 3 refusals printed as `platform: <reason>` (no REFUSE line) are not covered; the header's exit-code legend (4 = stopped, re-run resumes) belongs to the engine, not to platform.mjs.",
          failure_scenario: "Azure /aai-merge: platform.mjs merge exits 5 (a push landed between the A1 read and az's own read, R1). The agent has no instruction to relay and stop, so it proceeds to step 2 cleanup with AAI_DIRECTION set 'because step 1 merged it', signing the owner's direction against a head the owner never named; or on exit 4 it applies the legend 're-run resumes' and re-runs the merge line." }
      - { rank: NON-BLOCKING, file: .aai/scripts/platform.mjs, line: 115,
          issue: "record writes `platform: unknown` for any host the classifier cannot name, including GitHub Enterprise hosts, which D5 keeps on the legacy GitHub path only while unrecorded.",
          failure_scenario: "Reviewer probe: origin git@github.acme.corp:team/repo.git -> `RECORDED platform=unknown (new file)`; resolvePlatform then returns platform unknown (generic). A GHE project whose /aai-merge works today re-runs /aai-bootstrap and the next /aai-merge refuses platform_generic; no output tells the owner that `platform: github` is the fix. Spec-mandated by Spec-AC-01 (gitlab->unknown), so this is a design gap, not non-compliance." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/platform-adapter.mjs, line: 78,
          issue: "The win32 route `cmd.exe /d /s /c az ...` lets cmd.exe resolve `az` itself, and cmd searches the CURRENT DIRECTORY before PATH (unless NoDefaultCurrentDirectoryInExePath is set). The cwd is the ride checkout (preflight --origin, platform.mjs repoRoot). The argument allow-list itself is sound (no space, quote, &, |, <, >, ^, %, !, (, ), comma or semicolon can pass; an empty arg is refused).",
          failure_scenario: "On Windows, a PR branch that adds `az.cmd` or `az.bat` at the repository root: the owner's /aai-merge preflight (cwd = ride checkout) runs that script instead of the Azure CLI, with the owner's credentials in the environment. Pre-existing analogue for gh needs a binary gh.exe (libuv only probes .com/.exe); the cmd route widens it to a text script. Fix: pass env { ...process.env, NoDefaultCurrentDirectoryInExePath: '1' } on the win32 spec, or spawn an absolute az path resolved from PATH." }
      - { rank: NON-BLOCKING, file: .aai/scripts/platform.mjs, line: 175,
          issue: "Validation N2 confirmed: the merge-path platform_mismatch refusal prints `platform: platform_mismatch recorded=<a> detected=<b>` on stderr, without the `re-record: node .aai/scripts/platform.mjs record --force` command and not as a `REFUSE` line; Spec-AC-11 says platform.mjs merge 'SHALL refuse the same way'.",
          failure_scenario: "Origin changed between preflight and the merge line (or the line is run from another checkout): the operator gets the reason without the fix command, and SKILL_MERGE's 'relay the REFUSE line' instruction has no REFUSE line to match." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 150,
          issue: "Validation N3 confirmed: resolvePlatform({ repoRoot: cwd }) reads <cwd>/docs/ai/pr-config.yaml; preflight's cwd is `opts.origin ?? process.cwd()`, not the git toplevel.",
          failure_scenario: "preflight run from a subdirectory without --origin: the record is not found, so a recorded `unknown`/`none` opt-in and a recorded-vs-origin mismatch are both silently skipped and the detected platform is used. SKILL_MERGE passes --origin \"$(pwd)\" from the checkout root, so it does not bite today." }
      - { rank: NON-BLOCKING, file: .aai/scripts/platform.mjs, line: 186,
          issue: "Any A5 failure, including a spawn timeout (ETIMEDOUT after 120 s), is reported as merge_rejected under the header's 'exit 3 = refused (no merge happened)', without the re-read that steps 4 already does.",
          failure_scenario: "az completes the PR server-side but the process exceeds 120 s (slow network / policy evaluation); the owner is told merge_rejected / no merge happened while the PR is completed. Recoverable (next preflight says already_merged), and D9 step 3 prescribes this mapping." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/platform-adapter.mjs, line: 88,
          issue: "On win32 the az auth probe spawns cmd.exe, which always exists; a missing Azure CLI makes cmd exit 9009, reported as `unauthenticated`, not `cli_missing` as Spec-AC-03 describes.",
          failure_scenario: "Windows bootstrap on an Azure origin without azure-cli installed prints `AUTH azure unauthenticated`; the owner runs `az login`, which does not exist. Report-only, exit code and file unaffected." }
  cannot_verify:
    - { claim: "Live Azure response shapes: lastMergeSourceCommit/lastMergeCommit semantics for a completed squash PR, repository.webUrl/url/project.id presence, thread status values, A4 --api-version 7.1 acceptance (R2)",
        closes_with: "owner-run /aai-merge on the #468 Azure repository (fu-azure-live-proof-on-adoption)" }
    - { claim: "Whether the Azure server itself refuses a completion whose lastMergeSourceCommit is stale, i.e. whether the head race R1 is only detected or also prevented",
        closes_with: "live measurement (fu-azure-server-pinned-completion)" }
    - { claim: "The win32 cmd.exe /d /s /c az route actually executes az.cmd with the argv intact, and the current-directory lookup behaviour named in NB-3",
        closes_with: "one run on a real Windows host with azure-cli installed (R4), plus a planted az.cmd probe" }
    - { claim: "Pester twin and TEST-065 pwsh arm pass", closes_with: "validation r1 ran them (pwsh present); this reviewer did not re-run them" }
  overall: pass
```

## Scope and spec

- Scope: `git diff feca6e0b..HEAD` on change/git-platform-detected-at-bootstrap (HEAD 19b2f100), the paths of STATE `code_review.scope`. Worktree decision `worktree`; working tree clean apart from the two append-only ledgers the test wrapper writes (docs/ai/EVENTS.jsonl, docs/ai/tests/test-runs.jsonl).
- Spec: docs/specs/SPEC-DRAFT-spec-git-platform-detected-at-bootstrap.md (frozen, 14 Spec-ACs, two measurement amendments in decisions.jsonl).
- Validation r1 (docs/ai/reports/VALIDATION-20261016T164947Z-git-platform-detected-at-bootstrap-r1.md) was read, not redone. Reviewer re-ran: `node tests/skills/lib/platform-direct-calls.mjs .aai/scripts/merge-cleanup.mjs` (exit 0, clean), `aai-run-tests.sh bash tests/skills/test-aai-platform-adapter.sh` (all PASS), a block-comment blind-spot probe of the checker over merge-cleanup.mjs (0 lines skipped), a GHE-origin record probe (NB-2) and an azSpawnSpec(win32) probe.
- Dispatch note (anti-gaming contract): the dispatch named focus areas and relayed validator notes N1-N3. It did not pre-rate severity or exclude scope; recorded here, and the full scope was reviewed.

## AC table walk

All 14 Spec-ACs compliant; citations in the YAML block. Every TEST-062..076 exists, and the suites pass (validation r1; platform-adapter suite re-run here).

Deviations from the frozen spec (each listed, none fails the verdict):
- Spec-AC-11 / D9: platform.mjs merge's mismatch refusal is not the same text as merge-cleanup's (no `record --force`, no `REFUSE`). Exit code, reason name and zero A5 match. Reported as NB-4.
- Anchor `if (after.headRefOid !== expectHead)` is spelled inverted (`if (after.headRefOid === expectHead)`, platform.mjs:191). Equivalent logic; no mutation row depends on it (TEST-071 mutates the `before` guard, which is present at :184).
- The AC Status table still reads `planned` on every row (the close ceremony flips it; validation's 8a carve covers it).
- Validation N1 (RED logs without `RED_CLASS:`) is an evidence finding for Validation/TDD, not a code defect; validation's pre-change runs plus mutation replay substitute for it. Not re-ranked here.

## Focus areas checked

- win32 spawn allow-list: `^[A-Za-z0-9._\/:=@-]+$` excludes every cmd.exe metacharacter (`& | < > ^ % ! ( ) " , ;`, space, tab) and the empty arg; `=` and `:` are harmless under az.cmd's `%*`. libuv does not quote these args, so `/s` quote-stripping does not apply. Injection through arguments: none found. The executable lookup is the gap (NB-3).
- Azure head match and exit codes: 3 for every refusal before A5 (operator env, 40-hex, mismatch, platform, read failure, not_open, draft, head_changed), A5 run once, 0 MERGED only when the re-read is completed at the expected sha, 5 head_race_lost on a different merged head, 4 completion_pending when still active or when the re-read fails, 3 merge_rejected for A5 failure or abandoned after completion. Correct against D9. NB-6 covers the A5-timeout wording.
- Refusal before write: openPlatform runs first in preflight (before the PR read) and inside readAndGate, which runApplyOrPlan calls before classifyDrafts, the journal or any handler; TEST-073 asserts empty logs and an unchanged world digest.
- Legacy fallback: an unrecorded `unknown` resolves to github only when no record exists. A real Azure/GitHub mix-up needs a record and a classifiable origin, and that is caught as a mismatch. Masking is possible only when origin is unclassifiable (GHE, on-prem Azure DevOps Server), which is D5/R5 by design. The new risk runs the other way: record turns those hosts into generic mode (NB-2).
- REFUSE-string compatibility: gh_read_failed/gh_read_invalid details are byte-identical (`gh pr view <n>`, `gh pr view printed no JSON`, `gh api review-threads <n>`, `gh api review-threads printed no JSON`), repo_mismatch detail unchanged, dependents failure still retains remote_unknown. GitHub consumers see no change except the one new stderr legacy line (Spec-AC-12).
- Dead code / slop (INFO, no failure mode): `const r = …; return r;` at platform-adapter.mjs:157-158 and :235-236; duplicate `after = detected` at platform.mjs:108; `dependentNumbers` reduced to a one-line wrapper and `const repoSlug = githubRepoSlug` alias in merge-cleanup.mjs:180 (still used at :235 and :1087); genericAdapter.mergeCommand returns a skip object where callers expect a string (unreachable, prView refuses first). The Azure merge line quotes engineDir in double quotes, so a `$` or backtick in an install path would expand in a POSIX shell (spec-literal form; INFO).

## Warning dispositions (H6, recommended; the orchestrator records them)

| Finding | Severity | Recommended disposition |
|---|---|---|
| NB-1 SKILL_MERGE exit 4/5 and refusal relay | P2 | remediate-in-tree (about 150 B, inside the 900 B cap: 687 used) |
| NB-2 record writes unknown for GHE hosts | P2 | promote to follow-up `fu-platform-record-ghe-unknown` (record or bootstrap must not silently move a working legacy-github install to generic; for example, print the `platform: github` hint for an unknown host, or skip writing unknown when `gh auth status --hostname <host>` succeeds) |
| NB-3 cmd.exe current-directory lookup of az | P2 | remediate-in-tree (set NoDefaultCurrentDirectoryInExePath=1 in the win32 spawn env, plus a unit assertion on the spec) |
| NB-4 platform.mjs mismatch text (validation N2) | P3 | remediate-in-tree (one line, closes the Spec-AC-11 "same way" deviation) |
| NB-5 record read relative to cwd (validation N3) | P3 | remediate-in-tree (resolve the git toplevel of cwd) or accepted residual: SKILL_MERGE always passes --origin from the checkout root |
| NB-6 A5 timeout reported as merge_rejected | P3 | accepted residual: D9 prescribes the mapping, and the next preflight reports already_merged, so the failure is loud and recoverable |
| NB-7 win32 missing az reported unauthenticated | P3 | accepted residual: report-only line, Windows-only, the exit code and file are unaffected |

accepted residual: NB-6 — spec-prescribed mapping; a mis-reported completion is corrected by the next preflight (already_merged).
accepted residual: NB-7 — report-only AUTH token on Windows; no gate reads it.

## Next steps

Both verdicts pass, so the review status is pass with open WARNINGs. Before closeout: remediate NB-1, NB-3 and NB-4 (and NB-5 if cheap) in one round with RED-first tests, file the NB-2 follow-up, and record the dispositions above in code_review.notes.
