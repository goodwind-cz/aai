# Code review: node-first-cleanup (dual verdict)

```yaml
review:
  scope: "git diff origin/main...HEAD (chore/node-first-cleanup, HEAD 1403fba0, base 492f8b26)"
  spec: docs/specs/SPEC-0313-spec-node-first-cleanup.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/suite-weights.tsv; TEST-4037 PASS (aai-suite-select run at 1403fba0); reviewer recomputed all 143 medians (0 mismatches) and matched all 143 run-45459216102 samples against that run's hosted log (143/143)" }
      - { ac: Spec-AC-02, call: compliant, citation: "eight pin edits (test-aai-sync-node.sh:872, release-cut.sh:367, update-node, bootstrap-node, hook-gate.sh:364, hook-installer-node, install-parity, pre-commit-checks.sh:437); TEST-4038 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: ".github/workflows/skill-suite.yml:293 timeout-minutes 15; TEST-4039 PASS (runners=2 w2=533); hosted fit not observed (cannot_verify)" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/release-dry-run.mjs:21-34,444-456; TEST-4040 (release-first.test.mjs:597)" }
      - { ac: Spec-AC-05, call: compliant, citation: "tests/skills/lib/aai-release.test.mjs:760-768,822; TEST-4041 (test-aai-release-cut.sh:651)" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/release-finish.mjs:444-465; TEST-4042 (test-aai-release.sh recutCase TEST-4042)" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/templates/git-hooks/pre-commit-index.sh:70,79; TEST-4043 PASS under /bin/bash 3.2.57 (aai-git-hook-templates run at 1403fba0)" }
      - { ac: Spec-AC-08, call: compliant, citation: ".aai/templates/git-hooks/pre-commit-index.sh:140; TEST-4044 PASS under bash 3.2" }
      - { ac: Spec-AC-09, call: compliant, citation: ".aai/scripts/merge-cleanup.mjs:1384 up-front REFUSE exit 3; TEST-4045" }
      - { ac: Spec-AC-10, call: compliant, citation: ".aai/scripts/merge-cleanup.mjs:550 resumeSync escape check before any write; TEST-4046" }
      - { ac: Spec-AC-11, call: compliant, citation: "tests/skills/lib/seterr-lint.mjs; TEST-4047 (test-aai-pre-commit-checks.sh:1383)" }
      - { ac: Spec-AC-12, call: compliant, citation: "CHANGELOG.md:33-41; spec-amend list --strict rc 0 with the nine D-AMEND records; TEST-4048 PASS at 1403fba0" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 448,
          issue: "the preflight env allowlist removes HOME/GIT_*/GH_* but git still reads its SYSTEM config, which on Apple Git sets credential.helper=osxkeychain (and Git for Windows ships credential.helper=manager)",
          failure_scenario: "a CHANGELOG-reading test that runs git ls-remote/fetch/push against an explicit https://github.com/... URL inside the preflight clone gets the operator's stored GitHub credential from the keychain/GCM; verified on this host: under env -i HOME=<empty> git config --list --show-origin still lists file:/Library/Developer/CommandLineTools/usr/share/git-core/gitconfig credential.helper=osxkeychain" }
      - { rank: NON-BLOCKING, file: .aai/scripts/release-dry-run.mjs, line: 444,
          issue: "the probe treats any non-zero exit as a failed interpreter, but the probe also asks for the Pester version, so a working pwsh without Pester exits 1",
          failure_scenario: "pwsh 7.6.3 present, Pester absent: the probe prints 7.6.3 then 'You cannot call a method on a null-valued expression' and exits 1 (reproduced with a missing module); the report records interpreters.powershell null and interpreterErrors.powershell 'exit 1', where the base recorded the version; CHANGELOG says only a crashed or version-less PowerShell is recorded as null" }
      - { rank: NON-BLOCKING, file: tests/skills/lib/seterr-lint.mjs, line: 25,
          issue: "line-based scan misses backslash-continued calls, one-line function bodies and set -o pipefail -o errexit",
          failure_scenario: "'f \\<newline>  || echo x', 'g() { f || true; }', 'function f { ... }' bodies and a script whose errexit is turned on by 'set -o pipefail -o errexit' each yield zero findings (scratch fixtures); over today's 27 tracked .aai scripts a continuation-joining/one-liner-splitting variant finds no extra site, so Spec-AC-11 holds today, but the guard for future .aai scripts and the 799 count of fu-seterr-test-corpus-lint-sweep undercount these shapes" }
  cannot_verify:
    - { claim: "the selected-sharded legs fit 15 minutes on hosted runners (D-BOUND hosted half), and selections heavier than PR #582's", closes_with: "the PR head's skills-selected-sharded leg durations; the selector bounds w2 only relative to w1 (wall-ratio/runner-budget), never absolutely, so a large selection can still model past 900 s" }
    - { claim: "the release preflight passes the real CHANGELOG-reading tests in its allowlisted env on a rolled tree", closes_with: "a real cut; reviewer simulation (shared clone of 1403fba0, remote removed, env -i allowlist): release-notes-docs 6/6, current-head-ci 19/19, recheck 85/85, release-cut 29/29 pass; aai-release.test.mjs 44 pass and 3 TEST-4027 cases failed with ENOSPC (host disk at 100%, 774 MiB free); re-run of TEST-4027 alone in the same env: 3/3 pass. Simulation, not a real cut" }
    - { claim: "the Windows preflight (USERPROFILE, no process group, Git for Windows system config)", closes_with: "a Windows run of the preflight; already filed as fu-release-preflight-env-host-gaps" }
    - { claim: "the four other D-WEIGHTS runs' samples", closes_with: "the same log cross-check against 45093987222, 45025432502, 45013455954 and 44915915697 (reviewer checked only 45459216102, 143/143)" }
    - { claim: "aai-merge-cleanup, aai-release, aai-release-cut, aai-release-first, aai-pre-commit-checks suites at 1403fba0", closes_with: "not re-run by the reviewer; the full sweep at 4995d888 (144 passed, 1 skipped, 0 failed) and 1403fba0 touching only TEST-4048 carry them" }
  overall: pass
```

security_relevant: true

## Scope and spec

- Scope: `git diff origin/main...HEAD`, 36 files, branch `chore/node-first-cleanup`
  at 1403fba0. The worktree was clean apart from the run ledger line the
  canonical runner appends (`docs/ai/tests/test-runs.jsonl`). That line came
  from the reviewer's two suite runs. It was not restored (HAZ-LEDGER).
- Spec: `docs/specs/SPEC-0313-spec-node-first-cleanup.md`, frozen, ceremony
  level 3. The amendments were read with `node .aai/scripts/spec-amend.mjs list --strict --status all`
  (rc 0).
- Dispatch coaching check: the dispatch listed areas to watch and folded
  findings not to re-report. It did not rate the severity of any expected
  finding. The whole scope was reviewed anyway.

## Spec compliance: AC walk

All twelve Spec-AC rows are compliant (table above). Deviations from the frozen text, all disclosed or additive:

1. D-PWSH-ID: `interpreterErrors.powershell` can also hold `spawn <code>` (a
   missing binary) and `no version`. The spec names only `exit <status>` and
   `signal <name>`. `interpreterVersion` returns `{version, error}`, not a
   string or null. Both are additive and pinned by TEST-4040's second case.
2. D-INSIDE resume: `stop('write_outside_checkout')` resolves through the
   outcome table as `kept('sync-base')`. The run therefore exits 0 with a
   `Kept:` line, not STOPPED (exit 4). This still matches "stops before any
   write", and TEST-4046 pins exit 0 and the untouched outside tree.
3. Edits outside the spec's review-scope list: `.aai/scripts/lib/merge-outcomes.mjs`
   (new table row), `test-aai-round-budget.sh` (TEST-3613),
   `test-aai-hook-installer-docs.sh` (TEST-3999), `test-aai-git-ref-guard.sh`
   (TEST-308 hash re-pin) and the TEST-119 fixture in `test-aai-release.sh`.
   The closed-spec edits have unsigned contract amendments in the ledger, for
   factory-round-cap, release-same-version-recovery and a second
   pre-commit-installer-on-node record.
4. Spec edge-case text: "a symlinked docs/ai that is dangling … mkdirSync would
   then create inside the checkout" is not accurate. A scratch probe shows that
   `mkdirSync({recursive:true})` and `writeFileSync` through a dangling
   directory link both fail with ENOENT, and nothing is created on either side.
   The behaviour is safe and only the sentence is wrong (INFO).

Question from the dispatch: does any other test added by this ride pin `## [unreleased]` exactly? No.
- TEST-4040 matches `## \[(?:unreleased|v2099.01.01)\] — Fixture` inside its own fixture.
- TEST-4042's fixture test accepts `^## \[(?:unreleased|v[^\]]+)\] — feat: alpha`.
- TEST-4048 now accepts `[unreleased]` or `[vYYYY.MM.DD…]`.
- No other test names this ride's heading. Checked with `git grep "Node-first cleanup" -- tests/`.

## Code quality: findings

Focus areas the dispatch named, checked without a finding:

- **suite-weights.tsv.** Every `test-aai-*.sh` has exactly one row: 145 suites,
  145 rows, none missing or extra.
  - All 143 measured rows equal the rounded median of their samples, floor 1.
  - All 143 samples attributed to run 45459216102 match that run's hosted
    `PASS (<n>s)` lines (`gh run view --log`).
  - The two fallback rows (aai-state, aai-hermes-skills) take the maximum, 450.
- **15-minute bound.** The model is w2 533 s for the PR #582 plan. The hosted
  fit is in cannot_verify.
- **release-finish preflight.**
  - The temp root is removed in `finally` on every path. `refuse()` throws,
    so a failed clone, checkout or remote removal also cleans up.
  - Nothing is written to the real repository. The clone's alternates only
    read the source objects, and the clone's own writes stay in its objects
    directory.
  - `git clone --shared` from a linked worktree (the release-from-worktree
    case), followed by a detached checkout of a commit only that worktree
    holds, works. Checked in a scratch probe.
  - The env allowlist matches D-PREFLIGHT except for the system-config gap
    (NB-1).
- **merge-cleanup.** `escapesCheckout` resolves the nearest existing ancestor
  on both sides with realpath, so an origin reached through a symlink is
  consistent. The up-front REFUSE comes after `readAndGate`, whose only write
  is a `git fetch` to refs, and before any working-tree write. It prints
  `REFUSE write_outside_checkout <rel>` and exits 3, which matches SKILL_MERGE's
  "3 refused (`REFUSE <reason>`)". The missing OUTCOME line is already filed
  (fu-merge-refuse-outcome-and-plan).
- **pre-commit-index.sh.** `--no-renames` is a git flag with no bash construct
  added. TEST-4043 and TEST-4044 pass under /bin/bash 3.2.57 with
  `diff.renames` set to true, copies and false.

### NB-1 (NON-BLOCKING, P2, security): the preflight still inherits git's system credential helper

`.aai/scripts/release-finish.mjs:448-452`. The allowlist removes `HOME`,
`GIT_*`, `GH_*`, `GITHUB_*` and `AAI_*`. git still reads its system
gitconfig, and on this host that is Apple Git's
`/Library/Developer/CommandLineTools/usr/share/git-core/gitconfig`, which sets
`credential.helper=osxkeychain`. Reproduced: under `env -i HOME=<empty>`,
`git config --list --show-origin` still lists the setting. Git for Windows
sets `credential.helper=manager` the same way.

Failure scenario: a CHANGELOG-reading test that talks to an explicit
`https://github.com/...` URL inside the preflight clone (ls-remote, fetch,
push) is handed the operator's stored credential. That is exactly the leak
the follow-up meant to close. The repository's own precedent,
`release-dry-run.mjs` `cleanEnvironment`, sets `GIT_CONFIG_NOSYSTEM=1`,
`GIT_CONFIG_GLOBAL=/dev/null` and `GIT_TERMINAL_PROMPT=0`. D-PREFLIGHT's "no
`GIT_*` variable" rules those out, so the fix needs a spec change.

The CHANGELOG line "a developer's remotes, tokens … no longer change a release
verdict" claims more than the allowlist removes. Recommended disposition:
promote to a follow-up ref (P2). Fix: allow `GIT_CONFIG_NOSYSTEM=1` and
`GIT_TERMINAL_PROMPT=0` in the allowlist, and add a TEST-4042 assertion that
`git config --get credential.helper` is empty in the clone.

### NB-2 (NON-BLOCKING, P3): a pwsh without Pester is reported as a failed probe

`.aai/scripts/release-dry-run.mjs:444`. The probe prints the PowerShell
version and the Pester version in one `-Command`. When Pester is absent, the
second expression throws and pwsh exits 1. Reproduced with pwsh 7.6.3 and a
missing module, using scratch HOME and XDG caches: rc 1.

`interpreterVersion` then records `powershell: null` and `exit 1`. The base
recorded `7.6.3`. No consumer gates on the field, but the report now says a
working interpreter failed, which the CHANGELOG's "crashed or version-less"
wording does not cover. Recommended disposition: promote to a follow-up ref
(P3). Fix: probe the version on its own, or treat the Pester line as optional.

### NB-3 (NON-BLOCKING, P3): seterr-lint misses three shell shapes

`tests/skills/lib/seterr-lint.mjs:25-39`. The lint is line-based, so it misses:

- a backslash-continued `fn \` followed by `|| x` on the next line;
- calls inside a one-line function body, `g() { f || true; }`;
- every line of a `function f { … }` one-liner, because the definition line is skipped whole;
- errexit turned on by `set -o pipefail -o errexit`.

Each shape gave zero findings on a scratch fixture. Over today's 27 tracked
`.aai/**/*.sh`, a variant that joins continuations, splits one-liners and
accepts that errexit form finds no extra site, so Spec-AC-11's zero is true
today. The lint is the forward guard, though, and the count in
fu-seterr-test-corpus-lint-sweep (799) leaves these shapes out. Recommended
disposition: fold into fu-seterr-test-corpus-lint-sweep as a note (promote to
follow-up), or `accepted residual: P3 assurance-strength gap, no observed
bite, zero over the shipped corpus under the stricter variant`.

### INFO (no gate)

- `merge-cleanup.mjs` sits at exactly the 1490-line cap (TEST-058, TEST-2923),
  as it did on base. To stay there, this ride folded nine existing two-line
  statement pairs onto single lines. It also wrote the up-front REFUSE as a
  single line of about 300 characters with a trailing comment (lines 550,
  1384). The size budget now measures formatting more than size. This is a
  pre-existing pattern (8 lines over 200 characters on base, 11 now).
- TEST-4037 pins the five run ids exactly. TEST-4039 pins w2 ≤ 600 for the
  fixture under the shipped weights. Any later re-measure must amend both.
  This is intended by Spec-AC-01 and Spec-AC-03.
- `interpreterVersion` has no timeout, the same as the base probe it replaces.

## Warning dispositions (H6)

| Finding | Severity | Recommended disposition |
|---|---|---|
| NB-1 preflight inherits git system credential helper | P2 | promote to follow-up ref (needs a D-PREFLIGHT change) |
| NB-2 pwsh-without-Pester reads as probe failure | P3 | promote to follow-up ref |
| NB-3 seterr-lint shape gaps | P3 | note on fu-seterr-test-corpus-lint-sweep, or accepted residual (quoted above) |

The orchestrator records each disposition. This reviewer files nothing.

## Commands run

- `aai-run-tests.sh … --skill aai-suite-select` at 1403fba0: rc 0, 1/1 suite.
  TEST-4037, TEST-4038, TEST-4039 (w2=533) and TEST-4048 PASS. The runner's
  tripwire printed a notice about the run ledger line it appended itself.
- `aai-run-tests.sh … --skill aai-git-hook-templates` at 1403fba0: rc 0.
  TEST-4043 and TEST-4044 PASS under /bin/bash 3.2.57.
- `node .aai/scripts/spec-amend.mjs list --strict --status all`: rc 0.
- Weights recompute and cross-check against run 45459216102's hosted log: 143/143.
- Scratch probes:
  - a `--shared` clone of a linked worktree;
  - the pwsh missing-module exit code;
  - mkdir and write through a dangling directory link;
  - seterr-lint edge fixtures;
  - git system config under a scrubbed HOME;
  - the preflight env simulation of the five CHANGELOG-reading test files.

## Next steps

- Merge readiness: no BLOCKING finding. The owner merges (L3). Record the
  NB-1..NB-3 dispositions in the code_review notes. Read the hosted
  selected-sharded leg durations on the PR head before merge, if that mode runs.
