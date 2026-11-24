---
id: spec-node-first-leftovers
type: spec
number: 312
status: done
mutation_gate: v1
frozen_sha256: c6ede1fe6650e254335e1359dc56b758b0ce6ed48a71e5d465fc6aa1b48279d4
ceremony_level: 3
links:
  requirement: node-first-leftovers
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Node-first leftovers: the P3 fixes the migration left open

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-0267-node-first-leftovers.md (owner brief
  2026-11-24, second ride).
- Sibling ride: `node-first-cleanup` (P2 items and suite weights). It edits
  other lines of `.aai/templates/git-hooks/pre-commit-index.sh`.
- Closed specs whose pinned text or tests change (see D-AMEND): SPEC-0307
  (update launcher D-LAUNCH text), SPEC-0308 (doubled-key warning wording,
  DR-20 cell), SPEC-0310 (DR-33 line, the Pester count of TEST-4016),
  SPEC-0311 (the share echo rule, Spec-AC-06).
- Technology contract: docs/TECHNOLOGY.md (Node 22 floor, stdlib only;
  `.ps1` parses under Windows PowerShell 5.1 and pwsh 7; bash 3.2 suites).

## Implementation strategy

- Strategy: tdd
- Rationale: the owner's brief asks for TDD. Each fix has a test that fails
  on the unchanged tree: the repro echo, the colon forms reaching Node as
  words, the old DR-33 line, EAGAIN aborting, a BOM hiding a dial, the old
  warning text, and a long TMPDIR breaking the socket case. The 5.1
  quoting case reds only on the hosted Windows PowerShell 5.1 leg.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: L3 ride (guard-config, pre-commit checks, hook body
  templates, hook installer). The main checkout carries another session's
  files.
- User decision: worktree (owner brief 2026-11-24: own worktrees; the
  second pull request needs its own branch)
- Base ref: origin/main at 492f8b26
- Worktree branch/path: chore/node-first-leftovers at
  /Users/ales/Projects/aai-worktrees/node-first-leftovers
- Review required: true
- Review scope: origin/main...HEAD of chore/node-first-leftovers.

## Decisions

### D-ECHO: a gapped secret window

In `.aai/scripts/cloudflare-share.mjs`, `echoText` keeps its current
passes: whole values, then escapes, then contiguous 8-character windows. It
adds one more pass, under a constant `const GAP_SLACK = 2;`. A position
range `[p, p+8)` of the cleaned text is covered when its 8 characters
appear in order, as a subsequence, inside some `8 + GAP_SLACK` consecutive
characters of a secret value. Covered runs print as one `[REDACTED]`, as
today. The frozen SPEC-0311 Spec-AC-06 property still holds, and this
property is added: no 8 consecutive echo characters appear in order inside
any 10 consecutive characters of a secret.

### D-UPDATE-ARGS: the update launcher marshals like the sync launcher

`.aai/scripts/aai-update.ps1` gains the argument loop of `aai-sync.ps1`:

- a `[bool]` false drops the preceding switch;
- a `[bool]` true is dropped;
- an array is joined with `,`;
- a `-Flag:` token loses its trailing colon;
- plus the D-PS51 line.

The loop builds `$argv` and passes `@argv`. The `AAI_UPDATE_SYNC_RUNNER`
handling stays. `aai-update.mjs` `parseArgs` additionally accepts:

- `-Flag:value` as one token for a value flag;
- a switch flag followed by one of the words `true`, `false`, `$true` or
  `$false` (any case): the word is the switch's value and is consumed;
- `-Switch:true` and `-Switch:false` as one token.

This is the grammar of `aai-release.mjs`. The launcher stays at 20 lines
or fewer.

### D-DR33: the refusal says what it guards

The DR-33 line of `aai-sync.mjs` reads
`ERROR: the source <src> lies inside <entry> of the target <target>, which the sync manages; nothing was written.`
The refusal set is unchanged; narrowing it is not this scope. Two new
cases cover `.claude` (source at `<t>/.claude/worktrees/x`) and
`.codex/skills`.

### D-PS51: a trailing backslash under Windows PowerShell

In `aai-sync.ps1` and `aai-update.ps1`, the loop adds one more `\` to an
argument when all three hold:

- it contains whitespace;
- it ends in `\`;
- `$PSVersionTable.PSVersion.Major -lt 6` (legacy native quoting).

Node then receives the value unchanged. A Pester case in
`tests/skills/aai-sync.Tests.ps1` runs a copy of the launcher next to a
stub module that prints its argv as JSON:

- on Windows, through `powershell.exe -NoProfile -File` with
  `-TargetRoot 'C:\My Projects\app\'`;
- elsewhere, through `pwsh -NoProfile -File`.

It requires the stub to receive `C:\My Projects\app\`. The case is never
skipped, so the TEST-4016 count of passed cases moves from 5 to 6 (D-AMEND).

### D-EAGAIN: stdout writes survive a non-blocking pipe

`writeFd` in `aai-sync.mjs` writes the whole string as bytes in a loop.
`fs.writeSync` can return a partial count, and the loop continues from the
offset. On `EAGAIN` it waits 5 ms with `Atomics.wait` on a private
`Int32Array` and retries, giving up after 30 s of no progress with the
original error. The guard is `if (e.code === 'EAGAIN')`.

### D-BOM: one reading of a BOM-prefixed config

`readGuardConfig` in `.aai/scripts/lib/guard-config.mjs` drops one leading
BOM before splitting lines:

```
const text = raw.startsWith(BOM) ? raw.slice(BOM.length) : raw;
```

`out.raw` keeps the bytes as read. Each shell mirror of a dial accepts an
optional leading BOM in its pattern, `^(\xef\xbb\xbf)?<key>:`, written as
a bash `$'...'` string. The mirrors are:

- `pre-commit-checks.sh` (`doc_number_guard`);
- `pre-commit-index.sh` (`close_gate`, `body_lint`);
- `pre-push.sh` (`close_gate`).

The existing grep-versus-reader conformance test gains BOM fixtures.

### D-WARN: the doubled-key warning names the winner

The `install-pre-commit-hook.mjs` warning reads
`WARNING: <cfg> carries <n> ref_guard: lines (lines <a>, <b>); the first one with a value wins (line <w>). Repair: ...`
Here `<w>` is the line `readRefGuardPolicy` takes. The two existing
asserts change with it.

### D-SOCK: a short socket directory

The socket case of TEST-3987 in `tests/skills/lib/install-pre-commit-hook.test.mjs`
creates its socket in a fresh `mkdtemp` under
`const SOCK_BASE = process.platform === 'win32' ? os.tmpdir() : '/tmp';`
and removes it afterwards. The existing ENAMETOOLONG and EINVAL skips stay.

### D-DOCS: two clauses

- The DR-20 cell of SPEC-0308 adds: "except that a `PWD` with a leading
  `//` collapses to `/` in module messages; the hook lands in the same
  place".
- The CHANGELOG entry of this ride adds an erratum to the v2026.11.24
  installer entry: `--hooks` together with `--print` also exits 2 (DR-5).

### D-AMEND

One `spec-amend.mjs add --class contract --signoff none --ref
node-first-leftovers` record per closed spec whose pinned text or test this
scope changes, written after the change is verified by grep or diff:

- SPEC-0307: the D-LAUNCH text of `aai-update.ps1` and the DR-4 grammar;
- SPEC-0308: the doubled-key wording and the DR-20 clause;
- SPEC-0310: the DR-33 line, the D-LAUNCH text of `aai-sync.ps1`, and the
  TEST-4016 count;
- SPEC-0311: the echo rule.

The owner's merge signs them.

### D-DEFER: the design items stay open

`fu-runner-git-env-scrub`, `fu-bootstrap-seed-use-shared-lib`,
`fu-sync-aai-prefix-ignore`, `fu-hook-upgrade-resets-mode` and
`fu-parity-odd-row-tracker-successor` are not changed by this scope. Each
changes a behaviour a frozen spec pins, or tracks an open cause. The ride's
report names the pinning clause for each.

## Acceptance Criteria Mapping

- AC-001 to Spec-AC-01; AC-002 to Spec-AC-02 and Spec-AC-03; AC-003 to
  Spec-AC-04; AC-004 to Spec-AC-05; AC-005 to Spec-AC-06; AC-006 to
  Spec-AC-07 and Spec-AC-08; AC-007 to Spec-AC-09; AC-008 to Spec-AC-10;
  AC-009 to Spec-AC-11.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN echoText receives the fu-cfshare-redact-eaten-chars repro input or any of 200 seeded variants with up to two eaten characters the output SHALL hold no 8 consecutive characters that appear in order inside any 10 consecutive characters of the secret, and no ESC byte. | done | docs/ai/tdd/node-first-leftovers/green/TEST-4049.log; docs/ai/tdd/spec-node-first-leftovers/mutation-TEST-4049.txt | — | D-ECHO |
| Spec-AC-02 | WHEN aai-update.mjs parseArgs reads -DryRun false, -DryRun $true, -DryRun:true, -Repo:X, or -Repo: followed by X it SHALL yield dryRun false, dryRun true, dryRun true, repo X and repo X respectively, with outcome run. | done | docs/ai/tdd/node-first-leftovers/green/TEST-4050.log; docs/ai/tdd/spec-node-first-leftovers/mutation-TEST-4050.txt | — | D-UPDATE-ARGS |
| Spec-AC-03 | WHEN aai-update.ps1 runs under pwsh in session with -DryRun:$false, -DryRun:$true, -Repo:X or an array value the stub module SHALL receive no bare boolean word and no trailing-colon token, and the launcher SHALL stay at 20 lines or fewer. | done | docs/ai/tdd/node-first-leftovers/green/TEST-4051.log; docs/ai/tdd/spec-node-first-leftovers/mutation-TEST-4051.txt | — | D-UPDATE-ARGS |
| Spec-AC-04 | WHEN the sync source lies inside .claude or .codex/skills of the target the run SHALL refuse with the D-DR33 line and write nothing. | done | docs/ai/tdd/node-first-leftovers/green/TEST-4052.log; docs/ai/tdd/spec-node-first-leftovers/mutation-TEST-4052.txt | — | D-DR33 |
| Spec-AC-05 | WHEN aai-sync.ps1 runs with -TargetRoot ending in a backslash and holding a space the stub module SHALL receive that path unchanged, under Windows PowerShell 5.1 on the hosted Windows leg and under pwsh elsewhere. | done | docs/ai/tdd/node-first-leftovers/green/TEST-4053.log; docs/ai/tdd/spec-node-first-leftovers/mutation-TEST-4053.txt | — | D-PS51; hosted 5.1 leg |
| Spec-AC-06 | WHEN fs.writeSync throws EAGAIN once and then writes partially the sync output SHALL be complete and in order and the run SHALL exit 0. | done | docs/ai/tdd/node-first-leftovers/green/TEST-4054.log; docs/ai/tdd/spec-node-first-leftovers/mutation-TEST-4054.txt | — | D-EAGAIN |
| Spec-AC-07 | WHEN docs/ai/docs-audit.yaml starts with a BOM followed by a dial line readGuardConfig SHALL read that dial. | done | docs/ai/tdd/node-first-leftovers/green/TEST-4055.log; docs/ai/tdd/spec-node-first-leftovers/mutation-TEST-4055.txt | — | D-BOM |
| Spec-AC-08 | WHEN docs/ai/docs-audit.yaml starts with a BOM followed by doc_number_guard enforce, close_gate enforce or body_lint enforce each shell mirror SHALL read enforce, agreeing with readGuardConfig on every conformance fixture. | done | docs/ai/tdd/node-first-leftovers/green/TEST-4056.log; docs/ai/tdd/spec-node-first-leftovers/mutation-TEST-4056.txt | — | D-BOM |
| Spec-AC-09 | WHEN the first ref_guard line is valueless and a second carries a value the installer warning SHALL name the second line as the one that wins. | done | docs/ai/tdd/node-first-leftovers/green/TEST-4057.log; docs/ai/tdd/spec-node-first-leftovers/mutation-TEST-4057.txt | — | D-WARN |
| Spec-AC-10 | WHEN TMPDIR is longer than 80 bytes the socket case of TEST-3987 SHALL pass. | done | docs/ai/tdd/node-first-leftovers/green/TEST-4058.log; docs/ai/tdd/spec-node-first-leftovers/mutation-TEST-4058.txt | — | D-SOCK |
| Spec-AC-11 | SPEC-0308's DR-20 cell and CHANGELOG.md SHALL carry the D-DOCS clauses; spec-amend list --strict SHALL exit 0 holding the D-AMEND records. | done | docs/ai/tdd/node-first-leftovers/green/TEST-4059.log; docs/ai/tdd/spec-node-first-leftovers/mutation-TEST-4059.txt | — | D-DOCS, D-AMEND |

## Implementation plan

1. TEST-4049: echo (D-ECHO).
2. TEST-4050, TEST-4051, TEST-4053: update and sync launcher arguments
   (D-UPDATE-ARGS, D-PS51).
3. TEST-4052, TEST-4054: DR-33 and EAGAIN (D-DR33, D-EAGAIN).
4. TEST-4055, TEST-4056: BOM (D-BOM).
5. TEST-4057, TEST-4058: warning and socket (D-WARN, D-SOCK).
6. TEST-4059: docs and amendments (D-DOCS, D-AMEND).

Then the CHANGELOG heading
`## [unreleased] — Node-first leftovers: share echo, launcher arguments, sync output and guard config fixes`.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-4049 | Spec-AC-01 | unit | tests/skills/test-aai-cloudflare-share.sh | test_4049_gapped_window runs the node:test case TEST-4049 in cloudflare-share.test.mjs: the repro input and 200 seeded variants with up to two eaten characters, asserting the gapped-window property and no ESC byte | `sed:s/const GAP_SLACK = 2;/const GAP_SLACK = 0;/` on .aai/scripts/cloudflare-share.mjs | green |
| TEST-4050 | Spec-AC-02 | unit | tests/skills/test-aai-update-node.sh | test_4050_colon_grammar runs the node:test case TEST-4050 in aai-update.test.mjs over the five Spec-AC-02 forms | `sed:s/\$true/$maybe/` on .aai/scripts/aai-update.mjs | green |
| TEST-4051 | Spec-AC-03 | integration | tests/skills/test-aai-update-node.sh | test_4051_ps1_marshalling needs pwsh, copies aai-update.ps1 beside a stub module printing argv as JSON, runs the colon and array forms in session and by -File, and checks the line count | `sed:s/\$s = \$s\.Substring\(0, \$s\.Length - 1\)/$s = $s/` on .aai/scripts/aai-update.ps1 | green |
| TEST-4052 | Spec-AC-04 | integration | tests/skills/test-aai-sync-node.sh | test_4052_dr33_managed runs the node:test case TEST-4052 in aai-sync.test.mjs: sources inside .claude/worktrees/x and .codex/skills/x are refused with the D-DR33 line, target unchanged | `sed:s/which the sync manages/which the sync replaces/` on .aai/scripts/aai-sync.mjs | green |
| TEST-4053 | Spec-AC-05 | integration | tests/skills/test-aai-sync-node.sh | test_4053_ps51_trailing_backslash needs pwsh and runs the D-PS51 Pester case of aai-sync.Tests.ps1 (by name), requiring it passed; the hosted ps1-quality 5.1 leg runs the same case under powershell.exe | `sed:s/-lt 6\)/-lt 99)/` on .aai/scripts/aai-sync.ps1 | green |
| TEST-4054 | Spec-AC-06 | unit | tests/skills/test-aai-sync-node.sh | test_4054_eagain runs the node:test case TEST-4054 in aai-sync.test.mjs: a writeSync stub throwing EAGAIN once then writing partially; full ordered output, exit 0 | `sed:s/if \(e\.code === 'EAGAIN'\)/if (false)/` on .aai/scripts/aai-sync.mjs | green |
| TEST-4055 | Spec-AC-07 | unit | tests/skills/test-aai-pre-commit-checks.sh | test_4055_guard_config_bom reads a BOM-prefixed config with readGuardConfig and requires the first dial read | `sed:s/const text = raw\.startsWith\(BOM\) \? raw\.slice\(BOM\.length\) : raw;/const text = raw;/` on .aai/scripts/lib/guard-config.mjs | green |
| TEST-4056 | Spec-AC-08 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4056_shell_mirrors_bom runs each shell mirror pattern over the conformance fixtures plus BOM fixtures and requires agreement with readGuardConfig | `sed:s/xbb.xbf/xbb_xbf/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4057 | Spec-AC-09 | unit | tests/skills/test-aai-hook-installer-node.sh | test_4057_doubled_key_winner runs the node:test case TEST-4057 in install-pre-commit-hook.test.mjs: a valueless first ref_guard line and a valued second, requiring the warning to name the second line | `sed:s/the first one with a value wins/the first one wins/` on .aai/scripts/install-pre-commit-hook.mjs | green |
| TEST-4058 | Spec-AC-10 | unit | tests/skills/test-aai-hook-installer-node.sh | test_4058_socket_long_tmpdir runs the TEST-3987 node:test case with TMPDIR set to a fresh directory whose path exceeds 80 bytes and requires it to pass with the socket case run, not skipped | `sed:s/: '\/tmp';/: os.tmpdir();/` on tests/skills/lib/install-pre-commit-hook.test.mjs | green |
| TEST-4059 | Spec-AC-11 | inspection | tests/skills/test-aai-hook-installer-docs.sh | test_4059_leftover_docs requires the D-DOCS clauses in SPEC-0308 and CHANGELOG.md and spec-amend list --strict exit 0 with the D-AMEND records | `sed:s/--hooks together with --print/--hooks with --print/` on CHANGELOG.md | green |

## Verification

- Suites through the canonical runner with `env -u AAI_ROLE`, and a fresh
  `XDG_CACHE_HOME` on this host (the operator's PowerShell cache crashes
  pwsh):
  - aai-cloudflare-share;
  - aai-update-node and aai-update-docs;
  - aai-sync-node and aai-sync-docs;
  - aai-pre-commit-checks;
  - aai-hook-installer-node and aai-hook-installer-docs;
  - aai-git-hook-templates (the mirrors);
  - aai-install-parity (the launcher twins).
- One full sweep before the close, with `AAI_TEST_TIMEOUT=3600`.
- mutation-run records for every row; `mutation-gate.mjs` PASS;
  `spec-amend.mjs list --strict` exit 0.
- Hosted: the ps1-quality Windows PowerShell 5.1 and pwsh 7 legs, which
  run the D-PS51 case under powershell.exe, and the skill-suite run on the
  pull request head.

## Evidence contract

- ref_id `node-first-leftovers`. RED and GREEN logs go under
  `docs/ai/tdd/node-first-leftovers/{red,green}/`, and mutation records go
  under `docs/ai/tdd/spec-node-first-leftovers/`.
- The validation report is
  `docs/ai/reports/VALIDATION-<ts>-node-first-leftovers.md`. The review
  report is `docs/ai/reviews/review-node-first-leftovers-<ts>.md`.

### Evidence by strategy

tdd: a stored RED artifact for each AC-gating test plus the verification
above. TEST-4053's Windows PowerShell 5.1 RED and GREEN are read from the
hosted leg.

## Registry items closed by this scope

fu-cfshare-redact-eaten-chars, fu-update-ps1-colon-flag-forms,
fu-update-ps1-colon-switch-args, fu-sync-dr33-overbroad-managed-refusal,
fu-sync-dr33-test-non-aai-entries, fu-sync-ps1-51-native-arg-quoting,
fu-sync-eagain-nonblocking-stdout, fu-guard-dials-ignore-bom,
fu-doubled-key-warning-valueless-first, fu-classify-socket-long-tmpdir,
fu-dr20-note-double-slash-pwd, fu-changelog-dr5-hooks-print.

## Registry items this scope leaves open

The five D-DEFER items listed in that Decision stay open by design.

## Residual risks

- The gapped window can redact an ordinary 8-character run that happens to
  be a subsequence of a token window. The echo is a diagnostic, so
  over-redaction is the safe side.
- D-PS51 is proven under Windows PowerShell 5.1 only on the hosted leg.
  Locally, pwsh 7 on macOS does not use legacy quoting.
- The `aai-release.ps1` launcher has the same 5.1 trailing-backslash
  exposure for a path-valued flag. It is not changed here and is filed as
  a follow-up if confirmed.
