# Code review: node-first-cleanup, delta round (dual verdict)

```yaml
review:
  scope: "git diff 1403fba0..42561fe6 (chore/node-first-cleanup): a10e9f34, 303b8ab0, merge 603b6fa7 (origin/main 970c7a1f, #584), 42561fe6"
  spec: docs/specs/SPEC-DRAFT-spec-node-first-cleanup.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "delta does not touch tests/skills/suite-weights.tsv; TEST-4037 PASS (aai-suite-select at 42561fe6)" }
      - { ac: Spec-AC-02, call: compliant, citation: "the pin edits in test-aai-sync-node.sh, test-aai-update-node.sh and test-aai-hook-installer-node.sh survive the auto-merge (git diff origin/main..HEAD shows them intact); TEST-4038 PASS (aai-suite-select)" }
      - { ac: Spec-AC-03, call: compliant, citation: "delta does not touch .github/workflows/skill-suite.yml; TEST-4039 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "delta does not touch release-dry-run.mjs; carried by the prior review at 1403fba0" }
      - { ac: Spec-AC-05, call: compliant, citation: "delta does not touch aai-release.test.mjs; aai-release suite PASS at 42561fe6" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/release-finish.mjs:449-454 env adds GIT_CONFIG_NOSYSTEM=1, GIT_TERMINAL_PROMPT=0; spec D-PREFLIGHT text amended to name both (a10e9f34); TEST-4042 helper assertion (test-aai-release.sh recutCase TEST-4042) PASS in aai-release at 42561fe6" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/templates/git-hooks/pre-commit-index.sh:70,79 (--no-renames) kept through the merge next to #584's BOM dial grep at :61; aai-pre-commit-checks PASS under /bin/bash 3.2.57" }
      - { ac: Spec-AC-08, call: compliant, citation: ".aai/templates/git-hooks/pre-commit-index.sh:140 (--no-renames) kept next to the BOM dial grep at :136" }
      - { ac: Spec-AC-09, call: compliant, citation: "delta does not touch merge-cleanup.mjs; carried by the prior review" }
      - { ac: Spec-AC-10, call: compliant, citation: "delta does not touch merge-cleanup.mjs; carried by the prior review" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-4047 PASS over the merged .aai shell scripts, including #584's edited pre-commit-checks.sh and pre-push.sh (aai-pre-commit-checks at 42561fe6)" }
      - { ac: Spec-AC-12, call: compliant, citation: "CHANGELOG.md:33-41 is the only D-WIRE heading, #584's entry follows it; spec D-WIRE and the TEST-4048 row now name the rolled heading form that tests/skills/test-aai-suite-select.sh:2500-2503 already accepted; spec-amend list --strict rc 0; TEST-4048 PASS" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "the release preflight on Windows with no system git config (Git for Windows keeps core.autocrlf, core.fscache and http settings there; the clone now checks out without them)", closes_with: "a Windows run of the preflight on a CHANGELOG-reading test; already covered by the open fu-release-preflight-env-host-gaps" }
    - { claim: "TEST-4042 catches a dropped GIT_CONFIG_NOSYSTEM on a host with no system credential helper (a Linux runner)", closes_with: "the fixture asserting the two variables are present; already filed as fu-preflight-nosystem-pin-host-indep. On this host the check does catch it: without the variable the system config gives credential.helper osxkeychain, and with it git config --get-regexp '^credential\\.' exits 1" }
    - { claim: "the suites not re-run by the reviewer at 42561fe6 (aai-git-hook-templates, aai-spec-amend, aai-hook-installer-node, aai-hook-installer-docs, aai-sync-node, aai-update-node, aai-hygiene-pack)", closes_with: "the dispatcher's merged-tree runs and a full sweep or CI on the PR head. The reviewer re-ran the hygiene test_031 pattern extraction by hand on the merged template; the BOM line matched" }
  overall: pass
```

security_relevant: true

## Scope and spec

- Scope: `git diff 1403fba0..42561fe6`. The full review at 1403fba0
  (`docs/ai/reviews/review-node-first-cleanup-20261124T234144Z.md`) passed.
  The worktree was clean at the start. The only change afterwards is four
  run-ledger lines that the reviewer's suite runs appended to
  `docs/ai/tests/test-runs.jsonl`. They are append-only: the HEAD blob is still
  a byte-exact prefix. They were not restored (HAZ-LEDGER).
- Spec: `docs/specs/SPEC-DRAFT-spec-node-first-cleanup.md`, ceremony level 3.
  It was restamped twice in the delta, in a10e9f34 (D-PREFLIGHT env text) and
  303b8ab0 (D-WIRE and the TEST-4048 row). Each restamp has a matching
  `spec_amendment` record:
  - 23:44:47Z, class contract, unsigned (a10e9f34);
  - 00:29:24Z, class measurement (303b8ab0).
  42561fe6 adds one more record, at 01:02:40Z, for the TEST-308 re-pin.
  `node .aai/scripts/spec-amend.mjs list --strict` returns rc 0.
- Dispatch coaching check: the dispatch named the areas to check (conflict
  resolutions, the merged hook template, the ledger order). It did not
  pre-rate any finding. The whole delta was reviewed.

## The delta

### a10e9f34 and 303b8ab0 (NB-1 remediation)

- `release-finish.mjs:449-454`: the preflight env now holds
  `GIT_CONFIG_NOSYSTEM=1` and `GIT_TERMINAL_PROMPT=0`. The comment says these
  are the only `GIT_*` keys. That is true, because the allowlist loop copies no
  `GIT_*` name. `release-dry-run.mjs:18` already uses the same pair.
- TEST-4042: the leak loop lets the two keys through only with their exact
  values. The new check runs `git config --get-regexp '^credential\.'` and
  expects no output, so it covers `credential.helper` and URL-scoped
  `credential.<url>.*` keys. When nothing matches, git exits 1, the helper
  throws, the catch leaves `''` and the check passes. That is correct.
  - Host probe with Apple Git 2.54 and an empty HOME: without
    `GIT_CONFIG_NOSYSTEM`, the system file
    `/Library/Developer/CommandLineTools/usr/share/git-core/gitconfig` returns
    `credential.helper osxkeychain`. With it, the command exits 1. So this
    host catches a removal of the variable.
  - A host with no system credential helper does not. That is the open
    follow-up fu-preflight-nosystem-pin-host-indep. It is not a new finding.
- CHANGELOG bullet: the bullet now names the effect: no system git config, no
  OS credential helper, no prompt. That is accurate.
- Spec D-WIRE and the TEST-4048 row now describe what the test already accepted
  at 1403fba0: `[unreleased]` or a rolled `[vYYYY.MM.DD]` heading, with exactly
  one match (`test-aai-suite-select.sh:2500-2503`). The text now matches the
  code. Nothing changed in behaviour.

### 603b6fa7 (merge of origin/main 970c7a1f, #584)

Checked with `git show --cc` and a three-way comparison against merge-base
492f8b26.

- CHANGELOG.md: both per-entry headings sit under the `## [unreleased]`
  scaffold. This ride's entry is first and #584's entry follows it. Neither
  entry lost text, and the heading form matches the per-entry convention.
- docs/ai/roadmap.yaml: `node-first-leftovers: done` (main) is kept, followed
  by `node-first-cleanup: active` (branch). Both entries are there.
- tests/skills/test-aai-pre-commit-checks.sh: TEST-4047 (branch) and
  TEST-4055/4056 (main) are all defined and all wired into `main()`. The suite
  passes.
- tests/skills/test-aai-git-ref-guard.sh: the TEST-308 baseline is re-measured
  to `b8352cc1…`, and the comment block keeps both rides' re-pin notes.
  aai-git-ref-guard passes at 42561fe6, so the pin equals the merged template's
  hash.
- `.aai/templates/git-hooks/pre-commit-index.sh` (auto-merged) carries both
  rides' edits:
  - `--no-renames` on the gated list (:70), the per-file hunk (:79) and the
    linted list (:140);
  - the BOM-tolerant `$'^(\xef\xbb\xbf)?…'` dial greps for `close_gate` (:61)
    and `body_lint` (:136).

  Under bash 3.2:
  - `/bin/bash -n` (3.2.57) is clean for this template, `pre-push.sh` and
    `pre-commit-checks.sh`.
  - A /bin/bash 3.2 probe of the dial grep through a here-string reads
    plain-enforce and BOM-enforce as enforce. It reads report-only,
    BOM+`enforced` and commented-out as report-only. Results are the same under
    `LC_ALL=C` and `en_US.UTF-8`.
  - `bash` on PATH is /bin/bash 3.2, so the suites ran the installed hooks
    under 3.2.
  - The hygiene test_031 extraction (awk, then `printf %b`) still yields the
    BOM pattern from the merged template.
- Other files changed on both sides merged cleanly with nothing lost. In each,
  the branch's edit is intact relative to origin/main:
  - test-aai-hook-installer-docs.sh: TEST-3999 relaxation;
  - test-aai-hook-installer-node.sh, test-aai-sync-node.sh and
    test-aai-update-node.sh: the measured-weight pins;
  - docs/INDEX.md: CHANGE-0267 and SPEC-0312 rows, Done 697.
- TEST id ranges do not overlap. This ride uses TEST-4019, 4027 and 4037-4048.
  SPEC-0312 uses TEST-4016 and 4049-4059.

### Ledgers (HAZ-LEDGER)

Byte comparison of the merge-base, branch-tip (303b8ab0), origin/main
(970c7a1f = origin/main now), merge and HEAD blobs:

| ledger | origin/main is a prefix of merge | merge = main + the branch-only bytes | merge is a prefix of HEAD | duplicate lines |
|---|---|---|---|---|
| EVENTS.jsonl | yes | yes (+557 B) | yes (+0) | 0 |
| decisions.jsonl | yes | yes (+28629 B) | yes (+509 B, the 42561fe6 disclosure) | 0 |
| tests/test-runs.jsonl | yes | yes (+31367 B) | yes (+2930 B) | 0 |
| METRICS.jsonl | yes | yes (+0) | yes (+0) | 0 |

Each ledger holds the base lines first, then the branch-only lines, with
nothing lost or duplicated, and each ends with a newline.

### 42561fe6

This commit adds one `spec_amendment` record (class measurement, no sign-off)
that discloses the TEST-308 re-pin. Ten run-ledger lines are appended after it.
The text matches the change: the re-pin comment and the new baseline are in
`test-aai-git-ref-guard.sh`.

## Findings

No BLOCKING or NON-BLOCKING findings in the delta.

INFO (does not gate):
- The outer `aai-run-tests.sh` tripwire prints `AAI-TRIPWIRE FAIL … M
  docs/ai/tests/test-runs.jsonl` after each run. The cause is the framework's
  own run-ledger append. The wrapper still exits 0, and the inner summary says
  every suite was attested clean. This behaviour existed before this ride. It
  is noise, not a regression.
- `tests/skills/suite-weights.tsv` was measured before the merge, so it has no
  weight for the tests #584 added to five suites. That makes the weights
  slightly stale, which is a cost and not a defect. The next weight measurement
  picks the new tests up.

## Prior-round warnings: dispositions confirmed

- NB-1 (system credential helper): fixed in-tree in a10e9f34 and 303b8ab0. The
  remaining gap on hosts without a system helper is filed as
  fu-preflight-nosystem-pin-host-indep (P3, open).
- NB-2 (pwsh probe needs Pester): filed as fu-dry-run-pwsh-probe-needs-pester
  (P3, open).
- NB-3 (seterr-lint line shapes): filed as fu-seterr-lint-line-shapes (P3,
  open).

## Evidence (reviewer runs at 42561fe6)

| command | rc |
|---|---|
| suite aai-git-ref-guard | 0 (PASS 28 s) |
| suite aai-pre-commit-checks | 0 (PASS 79 s) |
| suite aai-suite-select | 0 (PASS 29 s) |
| suite aai-release | 0 (PASS 435 s) |
| `node .aai/scripts/spec-amend.mjs list --strict` | 0 |
| `/bin/bash -n` on the three hook/check scripts | 0 |
| ledger prefix/union comparison (node, scratch blobs) | all true |

Each suite was run with `XDG_CACHE_HOME=<scratch> AAI_TEST_TIMEOUT=1800 env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill <suite>`.

## Next steps

The review passes. Merge readiness depends on the cannot_verify items above
(CI on the PR head) and on the open owner sign-offs (`fu-amend-*`).
