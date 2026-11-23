---
id: spec-node-first-phase5-closeout
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: c23635d4c79b15c939d3d67304e0d0065ae53ec7a5df51f1bf70315bc4afa365
ceremony_level: 3
links:
  requirement: node-first-phase5-closeout
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Close RFC-0017 phase 5: every shipped script is a launcher or kept native on purpose

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-DRAFT-node-first-phase5-closeout.md
  (owner brief 2026-11-23, decisions 1 to 4 in its Summary).
- Umbrella RFC: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  (phase 5 row; table "Kept native scripts").
- Plan: docs/analysis/node-first-remaining-plan.md (section 1 method,
  section 5 done criteria, section 6 re-measure after ride 12).
- Prior scopes whose tests this scope edits (closed, their spec documents
  are not edited; see D-AMEND): docs/specs/SPEC-0310-spec-sync-on-node.md
  (TEST-4021, TEST-4022), docs/specs/SPEC-0282-spec-release-publish-on-node.md
  (TEST-3529), docs/specs/SPEC-0063-spec-aai-release-skill.md (TEST-019),
  docs/specs/SPEC-0284-spec-install-path-parity-harness.md (TEST-3565,
  TEST-3566, TEST-3568, TEST-3570 and the allowlist).
- Technology contract: docs/TECHNOLOGY.md (bash 3.2 suites through
  `.aai/scripts/aai-run-tests.sh`, Node 22 floor, Node stdlib only, `.ps1`
  parses under Windows PowerShell 5.1 and pwsh 7).

## Implementation strategy

- Strategy: tdd
- Rationale: the owner requires the three follow-ups to close test-first,
  and every other change here is a guard or a launcher contract whose test
  can be written first and observed failing on the unchanged tree (the
  strict check reds on six logic files today, the release grammar refuses
  `-DryRun` under `--launcher ps1` today, the share probe prints 19 of 20
  token characters today). The Windows arms red on the hosted runner (the
  control arm of D-HOSTCHECK reds on the frozen bash twin in every run).
  Not chosen at intake (the intake's Notes say Planning decides); Planning
  chose it from the owner's test-first requirement.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: L3 ride (owner directive), the main checkout carries
  other sessions' uncommitted files, and the scope edits the parity harness
  and release launcher that other rides read.
- User decision: worktree (owner directive in the 2026-11-23 brief)
- Base ref: main at 0ff18d63
- Worktree branch/path: chore/node-first-phase5-closeout at
  /Users/ales/Projects/aai-worktrees/node-first-phase5-closeout
- Review required: true
- Review scope (explicit paths): .aai/scripts/aai-release.ps1;
  .aai/scripts/aai-release.mjs; .aai/scripts/cloudflare-share.mjs;
  tests/fixtures/aai-release-reference/aai-release.ps1;
  tests/skills/lib/release-reference.mjs; tests/skills/lib/script-classes.mjs;
  tests/skills/lib/install-parity.mjs;
  tests/skills/lib/install-parity-allowlist.tsv;
  tests/skills/lib/install-parity.test.mjs;
  tests/skills/install-parity.Tests.ps1; tests/skills/release-cut.Tests.ps1;
  tests/skills/lib/aai-release.test.mjs;
  tests/skills/lib/cloudflare-share.test.mjs;
  tests/skills/test-aai-release-cut.sh; tests/skills/test-aai-release.sh;
  tests/skills/test-aai-cloudflare-share.sh;
  tests/skills/test-aai-install-parity.sh; tests/skills/test-aai-sync-docs.sh;
  tests/skills/test-aai-hygiene-pack.sh;
  tests/skills/test-aai-phase5-closeout.sh; tests/skills/suite-map.yaml;
  tests/skills/suite-weights.tsv; .github/workflows/ps1-quality.yml;
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md;
  docs/analysis/node-first-remaining-plan.md; CHANGELOG.md;
  docs/product/node-first-phase5-closeout.md;
  docs/issues/CHANGE-DRAFT-node-first-phase5-closeout.md; this spec; plus
  every shipped file the D-ODD root-cause fix changes (the review scope is
  re-recorded with those paths when the fix lands).

## Decisions

### D-KEPT: five new kept-native rows

The table "Kept native scripts" of RFC-0017 keeps its four rows byte for
byte and gains five, in this order, each reason non-empty:

| Script | Reason |
|---|---|
| `.aai/scripts/claude-hook-gate.sh` | the bash pre-filter of the Claude hook gate: it starts no Node process for a command that cannot concern a gate, so an ordinary agent shell command pays no Node start; an L3 protected surface (owner decision 2026-11-23) |
| `.aai/scripts/lib/test-residue.sh` | sourced by aai-run-tests.sh, which stays bash: removes the residue one test run provably created, inside the supervising shell (owner decision 2026-11-23) |
| `.aai/scripts/lib/repo-tripwire.sh` | sourced by aai-run-tests.sh, which stays bash: the shipping-repository write tripwire around each suite (owner decision 2026-11-23) |
| `.aai/scripts/lib/append-lock.sh` | sourced by the bash suite framework tests/skills/test-framework.sh: serialised appends to the append-only run ledger; the Node callers use lib/append-lock.mjs (owner decision 2026-11-23) |
| `.aai/scripts/lib/git-bash-path.sh` | sourced by aai-run-tests.sh, which stays bash: in-process Windows to Git Bash path translation (owner decision 2026-11-23) |

### D-CLASS: one classifier, two checks

`tests/skills/lib/script-classes.mjs` (test-only, Node stdlib) is the single
reading of the plan's section 1 method and of the kept-native table:

- `countCodeLines(text)`: lines that are not blank and whose first non-space
  character is not `#` (the section 1 grep count).
- `LAUNCHER_MAX_CODE_LINES = 20`; `POLICY_TOKENS`: the four expressions of
  today's TEST-4022 (the word git, `.gitignore`, `PROFILES`, the profile
  flag in either spelling), matched against code lines only.
- `KEPT_NATIVE_HEADING = '### Kept native scripts'`; `parseKeptNative(rfcText)`
  returns every table row under that heading (header and rule excluded) as
  `{ file, reason, line }`, a row with an empty reason included (today's
  regex silently drops it).
- `classify({ file, text, kept })`: `deprecation launcher` (a `# RETIRED`
  comment in the first three lines), `kept native` (a row with a non-empty
  reason), `launcher` (at most 20 code lines, no policy token) or `logic`.
- `strictProblems({ files, read, kept })`: one problem string per violation:
  a `logic` file; a `deprecation launcher` over 20 code lines or naming a
  policy token; a row with an empty reason; a row naming a file outside
  `files`; a file named by two rows.
- CLI: `node tests/skills/lib/script-classes.mjs strict --root <dir>
  [--files-from <list>]` prints each problem on its own line, exits 1 when
  there is one and 0 otherwise; without `--files-from` the list is
  `git -C <dir> ls-files -z -- .aai/scripts` filtered to `.sh` and `.ps1`
  (lib and any subdirectory included). `--files-from` lets the bite proof
  run on a scratch directory that is not a git repository.

Consumers: the strict check TEST-4025 (a whole-checkout case of the
hygiene corpus half, which is core, so it runs on every pull request), and
the tolerant record check TEST-4022, which now imports the classifier and
the table parser instead of its inline copies.

### D-RELEASE: the PowerShell release launcher

Launcher (`.aai/scripts/aai-release.ps1`), at most 20 code lines, ASCII, no
`param(` block, no policy token, following `aai-sync.ps1`:

1. dot-source guard: `if ($MyInvocation.InvocationName -eq '.') { return }`
   (dot-sourcing starts nothing, as before);
2. the module is `Join-Path $PSScriptRoot 'aai-release.mjs'`; without `node`
   on PATH or without the module it writes the old refusal line byte for
   byte (`REFUSED: missing-node ` + `[char]0x2014` + ` Node.js 22 or later is
   required for /aai-release (https://nodejs.org/); nothing was changed.`)
   to stderr and exits 20;
3. the raw `$args` are normalized exactly as `aai-sync.ps1` does (a `[bool]`
   element after a `-Name:` token drops the token when false; an array
   element is joined with commas; a trailing colon is cut);
4. `& node $Module --launcher ps1 --launcher-path $PSCommandPath @argv`, no
   stderr redirect, then `exit $LASTEXITCODE`; no `ErrorActionPreference`
   or `PSNativeCommandUseErrorActionPreference` assignment (the old file
   set neither).

Module grammar (`aai-release.mjs` `parseArgs`, argument intake only):
under `--launcher ps1` it accepts every form it accepts today plus a
`PS1_FLAGS` table keyed by the lower-cased name (`'-version'`,
`'-dryrun': '--dry-run'`, `'-confirm'`, `'-yes'`, `'-noremote'`), any letter
case, `-Version <v>` and `-Version:<v>`, and a switch with a `:$true`,
`:$false`, `:true` or `:false` suffix (any case) read as on or off. Under
`--launcher sh` or none, a PowerShell form is still `Unknown argument`,
exit 1 (the sh launcher's grammar is unchanged).

Frozen reference: `tests/fixtures/aai-release-reference/aai-release.ps1`
is a byte copy of `.aai/scripts/aai-release.ps1` at 0ff18d63 (blob
1c910b53, sha256
453d2ffba770460eb5a9cc231968521d19a5b55725fb50962b73d53ff9c4dfdb), kept
outside `.aai/` so it is never vendored; `tests/skills/lib/release-reference.mjs`
verifies the hash before materializing it (the update-reference pattern).

D-RELEASE-MATRIX (TEST-4027; each under `pwsh -NoProfile -File` and in
session through `& $launcher @a`, in a scratch git repository with a
CHANGELOG scaffold, both launchers next to the same module copy): M01 `-h`;
M02 `--help`; M03 `-Version v9 -DryRun`; M04 `-Version:v9 -DryRun`; M05
`-version v9 -dryrun`; M06 `--version v9 --dry-run`; M07 `-DryRun -NoRemote`;
M08 `-Confirm -NoRemote -Version v9` (a local cut in the scratch repository);
M09 `-Yes -NoRemote -Version v9`; M10 `-DryRun:$false -NoRemote -Version v9`;
M11 `-Bogus`; M12 run outside a git repository (exit 10); M13 a repository
without CHANGELOG.md (exit 11); M14 `-DryRun` with `AAI_RELEASE_DATE` and
`AAI_RELEASE_NO_REMOTE=1`; M15 `-DryRun extra`; M16 PATH without node
(exit 20); M17 to M20 are the DR forms below. The remote finish
(`-Confirm` without `-NoRemote`) is never run: it would reach a hosting
platform. Stdout, stderr and the exit code must be identical for M01 to M16
after the launcher directory is normalized to one token; M17 to M20 must
show the new column below.

| DR | Form | Old (frozen launcher) | New | Why |
|---|---|---|---|---|
| DR-R1 | an abbreviated name such as `-Ver v9` or `-Dry` | bound by PowerShell | `Unknown argument`, exit 1 | one grammar with aai-release.sh and aai-sync.ps1 (SPEC-0310 DR-3); no reimplemented PowerShell binder |
| DR-R2 | a common parameter such as `-Verbose` or `-ErrorAction Stop` | accepted, no effect | `Unknown argument`, exit 1 | the documented usage names none |
| DR-R3 | a bare first word such as `v9` | bound to Version by position | `Unknown argument: v9`, exit 1 | the sh launcher has no positional version |
| DR-R4 | `-Version` with no value | a PowerShell binding error, exit 1 | `REFUSED: --version needs a value.`, exit 1 | the module's one refusal for it |

The matrix is the arbiter: a difference outside DR-R1 to DR-R4 fails the
test. When the matrix measures an old behaviour other than the Old column
says (for example under one engine), Implementation records the measured
value with `spec-amend.mjs add --class measurement` before changing the
row; the New column is the contract.

### D-REDACT: the share failure echo

In `.aai/scripts/cloudflare-share.mjs`, the failure echo becomes: (1)
redact every whole secret value of 8 or more characters on the raw text;
(2) strip escapes with an expression that covers CSI, OSC (ended by BEL or
ST), nF (ESC, one or more bytes 0x20 to 0x2F, a final byte 0x30 to 0x7E),
Fp (ESC 0x30 to 0x3F, such as `ESC 7` and `ESC 8`), Fe (ESC 0x40 to 0x5F)
and Fs (ESC 0x60 to 0x7E, such as `ESC c`); (3) remove every ESC byte left;
(4) replace every run of the text that contains a window of
`MIN_SECRET_WINDOW = 8` consecutive characters of a secret with
`[REDACTED]`. Property (TEST-4029): for the follow-up's probe
(`ESC [Upper-to ESC [0m ken-CCCC3333` around the token
`Upper-token-CCCC3333`, written without spaces) and for each secret of the
fixture (a 40-character CLOUDFLARE_API_TOKEN and a 37-character
CLOUDFLARE_API_KEY), each escape of the list (unterminated CSI `ESC [`,
`ESC [0m`, `ESC [1;31m`, OSC with BEL, OSC with ST, `ESC ( B`, `ESC 7`,
`ESC 8`, `ESC c`, a lone ESC) inserted at every position 0 to length, and
an unterminated CSI before the value combined with a complete CSI at every
split point, the stderr lines `run` writes after a failed stub deploy hold
no window of 8 consecutive secret characters and no ESC byte. The case
runs through `run` with an injected deploy (the seam the follow-up names
as the TEST-3421 stub lines), not through `redact` alone.

### D-TWIN: a launcher twin in the parity driver

`tests/skills/lib/install-parity.mjs` registers a fourth twin
`{ name: 'launcher', ops: ['sync', 'update'], peers: { sync: ['node'],
update: ['node'] } }` after `node`: sync runs `ctx.bash
<fwd(ctx.src)>/.aai/scripts/aai-sync.sh <fwd(target)> [--profile p]`, update
runs `ctx.bash <fwd(ctx.src)>/.aai/scripts/aai-update.sh --repo <src> --ref
main`, both with cwd the target, so the SHIPPED launchers of the scratch
source run under the same bash as the frozen twins (Git for Windows' bash
on Windows, never the WSL shim). `node.peers` gains `launcher` for update;
pairs are emitted in registry order, so the new pair is `node:launcher`.
The allowlist parser's twin list and TEST-3570's list become
`sh, ps1, node, launcher`. TEST-3565 and TEST-3566 change only where they
enumerate twins. Expected: no `node:launcher` divergence on any host (both
sides run the same module from the same scratch source); a divergence that
appears is fixed at cause or gets a reviewed row with a follow-up, never a
normalization.

### D-HOSTCHECK: named host checks in the driver report

The driver report gains `host_checks`: entries `{ id, scenario, twin,
status, checked, detail }` with status `pass`, `fail`, `not-applicable` or
`bites`; each entry also goes to `notes` as one line
`AAI-HOST-CHECK <id> <scenario> <twin> <status> checked=<n>`; any `fail`
makes the verdict FAIL and the exit non-zero.

- `no-odd-root` (every host): after each sync and update step of the node
  and launcher twins, a root entry of the target whose name matches
  `ODD_NAME = /[^\x20-\x7e]/` and that did not exist before the step is a
  `fail` naming it with its code points; `checked` is the number of root
  entries read.
- `source-path-windows` (win32 only, `process.platform` read by the driver
  itself): every `- Source path:` line of `.aai/system/AAI_PIN.md` and every
  `- Source:` line of a `docs/ai/reports/sync-conflicts-*.md` the step wrote,
  for the node and launcher twins, must match `WIN_ABS_RE` (a drive letter,
  a colon, a backslash); `checked` counts the lines; SY-01 with fewer than
  two checked lines is a `fail` (vacuous). On POSIX the entry is
  `not-applicable` with detail `POSIX host`.
- `source-path-windows-control` (win32 only): the same predicate run on the
  frozen sh twin's SY-01 pin must FAIL (it records `/c/...`); then the
  status is `bites`, else `fail` (the check would not catch the old bug).

`tests/skills/install-parity.Tests.ps1` asserts on win32: exactly one
`source-path-windows` entry per SY-01 twin launcher and node with status
`pass` and checked at least 2, one control entry with status `bites`, and
`no-odd-root` entries for UP-01 twin launcher with status `pass` and checked
at least 1; on POSIX it asserts the two Windows entries read
`not-applicable`. It writes every `AAI-HOST-CHECK` line to the host log, so
the windows-parity job's log shows that the Windows arms ran under each
engine.

### D-ODD: finding the cause of the odd root directories

1. The first hosted run with D-TWIN and D-HOSTCHECK decides the branch: the
   launcher twin's `no-odd-root` fails (the shipped path is affected; that
   log is the RED evidence) or passes while the frozen sh twin still shows
   the entries (only the frozen path is affected).
2. In either branch, a test-only diagnostic (`AAI_PARITY_ODD_DIAG=1`, off by
   default, in the driver) re-runs, in a fresh copy of the post-step target
   and under the same bash-derived environment, one candidate at a time
   with a root snapshot before and after each, and prints
   `AAI-ODD-DIAG <candidate> born=<n>`: the doctor field report helper; the
   doctor itself with `--json`; the three ref-guard hook runs as the doctor
   launches them (control, refuse, permit inputs); `aai-win-selftest.ps1`
   through the engine the doctor resolves; the agent CLI probes. The first
   candidate that births an entry, narrowed to its child process and
   argument list, is the named root cause.
3. Shipped path affected: fix at the cause in the shipped file (L3 rules
   apply if that file is `lib/guard-config.mjs`), the check goes green on
   both engines; when the fix also cures the frozen twin, the allowlist row
   is stale and is removed (the driver already fails a stale row).
4. Frozen path only: the row is re-justified per D-ALLOW.
5. The cause is recorded as one line of plan section 7:
   `- Root cause of fu-parity-win-odd-root-dirs: <child process and
   arguments>, shown by ps1-quality run <id>`.
6. Stop rule: three hosted diagnostic runs without a named candidate end
   the ride as BLOCKED with numbered options for the owner (keep the row and
   the follow-up open, or widen the diagnostic).

### D-ALLOW: allowlist rows after the closes

- `win-source-path-pin`, `win-source-path-report` (pairs sh:ps1, the frozen
  twins only): tracker `accepted`; reason states that the frozen bash
  reference records the Git Bash spelling and the shipped launcher records
  the Windows path, proven by TEST-4032 and the `source-path-windows` host
  check.
- `win-sh-odd-root-dirs`: removed when stale (step 3 of D-ODD); otherwise
  tracker `accepted`, the reason names the root cause and that only the
  frozen reference that no longer ships shows it, and the match field takes
  the form the driver allows for an `accepted` row (`?` requires a `fu-`
  tracker today).

### D-REMEASURE: the record of this ride

`docs/analysis/node-first-remaining-plan.md` gains
`## 7. Re-measure after the phase 5 closeout (YYYY-MM-DD)` (section 6 stays
as written, a dated record): the method sentence of section 6, a file table
of every non-launcher file with code lines, class and reason (expected: the
nine kept-native rows and the seven deprecation launchers, no `logic`
row), `- Twin duplication: 0 code lines ...`, the open P1 and P2 follow-ups
of the plan's refs (expected: one row `none`), a line naming the open P2
items whose subject sounds related but whose ref lies outside the plan's
refs (today `fu-hook-gate-skips-renamed-doc`, `fu-release-pwsh-identity-crash`,
`fu-release-preflight-scrubbed-env`) with why each is outside, the D-ODD
root-cause line, and the hosted line
`- Parity harness and Pester (H1 to H3): <status>`, where status is either
`passed on <full sha> (ps1-quality run <id>)` or `pending: <what remains>`.

TEST-4022 is generalized: it reads the latest `## N. Re-measure after ...
(YYYY-MM-DD)` section instead of the literal section 6 heading, and the
RFC phase 5 row must name that section (`section 7`) while in progress.

RFC-0017 phase 5 row: one new sentence for this slice (the eighteenth),
linking the intake; status `done` only when section 7's hosted line reads
`passed on ...` and every section 5 criterion holds on the section 7
measurement; otherwise `in progress` and the row names section 7 and what
remains.

### D-HOSTED: hosted evidence and the order of the record

1. Implementation reaches local GREEN at head H1 with the hosted line
   `pending: ...` and the phase 5 status `in progress`.
2. The orchestrator pushes H1 and runs
   `gh workflow run ps1-quality.yml --ref chore/node-first-phase5-closeout`
   and `gh workflow run skill-suite.yml --ref chore/node-first-phase5-closeout`
   (or reads the draft pull request's runs). The windows-5_1,
   windows-parity, windows-wsl1, gate and skill-suite runs for H1 are read
   with `gh run view <id> --json
   headSha,conclusion,jobs` and `gh run view <id> --log`; the summary and the
   `AAI-HOST-CHECK` and `AAI-ODD-DIAG` lines are saved under
   `docs/ai/tdd/node-first-phase5-closeout/hosted/`.
3. Red on H1: remediation, new head, repeat.
4. Green on H1: one record commit H2 that touches only the plan, the RFC,
   the product doc and the follow-up ledger: the hosted line reads
   `passed on <H1> (ps1-quality run <id>)`, the phase 5 status `done` when
   the rest of section 5 holds, the two Windows follow-ups close. TEST-4033
   checks, when the H1 object exists locally, that `git diff --name-only
   <H1> HEAD` names only those paths (on a checkout without that object it
   logs that it could not check and does not fail).
5. Validation runs on H2. The pull request's own ps1-quality run on its
   final head must be green before the owner merges; if it is red, a new
   commit sets the status back to `in progress` (never a history rewrite).

### D-FU: the three closes

- `fu-cfshare-redact-escape-robust`: `follow-ups.mjs close --resolved-by
  node-first-phase5-closeout --source "tests/skills/lib/cloudflare-share.test.mjs
  TEST-4029"` after TEST-4029 is green.
- `fu-parity-win-odd-root-dirs`: `--source "tests/skills/lib/install-parity.test.mjs
  TEST-4031; ps1-quality run <id> on <H1>; cause: <D-ODD line>"`, only at
  step 4 of D-HOSTED.
- `fu-parity-win-source-path`: `--source "tests/skills/lib/install-parity.test.mjs
  TEST-4032; ps1-quality run <id> on <H1>"`, only at step 4 of D-HOSTED.

TEST-4021 accepts `fu-parity-win-source-path` either open or closed with
resolved_by `node-first-phase5-closeout`, a source naming a test file and a
TEST id it holds followed by a colon, and a `ps1-quality run <digits>`.

### D-AMEND: closed specs whose tests change

One `spec-amend.mjs add --class contract --signoff none --ref
node-first-phase5-closeout` record per closed spec whose test body this
scope edits, written after the edit is verified by grep or diff (never from
a report): SPEC-0310 (TEST-4021 accepts the close; TEST-4022 reads the
latest re-measure section and uses the shared classifier), SPEC-0282
(TEST-3529 pins the D-RELEASE launcher shape instead of the param block),
SPEC-0063 (TEST-019 checks the four flags by behaviour instead of by
`$Name` text), SPEC-0284 (the launcher twin in TEST-3565, TEST-3566,
TEST-3570, the win32 host-check assertions in TEST-3568, the D-ALLOW rows).
The owner's merge signs them (L3, the owner merges).

### D-WIRE

- New suite `tests/skills/test-aai-phase5-closeout.sh` (TEST-4024, TEST-4033
  to TEST-4036; own scratch prefix and ownership marker; bash 3.2): a
  `suite-map.yaml` entry selected by the RFC, the plan, CHANGELOG.md, the
  product doc, `tests/skills/lib/script-classes.mjs`, `.aai/scripts/*.sh`,
  `.aai/scripts/*.ps1`, `.aai/scripts/lib/*.sh`, the follow-up suite and the
  suite itself; a `suite-weights.tsv` row with the fallback-unsampled
  comment line.
- TEST-4025 is listed in `HYGIENE_CORPUS_CASES` and defined in
  `tests/skills/test-aai-hygiene-pack.sh`.
- `.github/workflows/ps1-quality.yml`: `tests/fixtures/aai-release-reference/**`
  and `tests/skills/lib/release-reference.mjs` on both path lists; any
  shipped file the D-ODD fix changes that PowerShell or the Windows jobs
  read, as the win-fallback derivation pins require.
- `suite-map.yaml`: the release-cut suite also selected by the frozen
  reference and its helper; the install-parity suite unchanged (its globs
  already cover the driver, the allowlist and the Pester file).
- Companion obligations: a new `.aai/**` file (only if the D-ODD fix adds
  one) gets a PROFILES.yaml classification; no prompt-corpus bytes are
  planned (if a prompt changes, the diet-ledger entry and TEST-012 bump
  join the scope).
- CHANGELOG.md: one `## [unreleased] — Node-first phase 5 closeout` heading
  (a per-entry heading, not bullets under a scaffold), naming each
  consumer-visible change of this diff to a shipped file: the share
  redaction, the release launcher and its DR-R1 to DR-R4, the Windows update
  change if a shipped file changed for D-ODD, and the Windows sync source
  path as proven (no claim of a fix the diff does not make).
- Product doc: new `docs/product/node-first-phase5-closeout.md` (capability
  `node-first-phase5-closeout`, the intake's capability), written by the
  ship step after LOOP COMPLETE; TEST-4036 checks it once it exists.
- `docs/INDEX.md` is regenerated by the pre-commit hook.

## Acceptance Criteria Mapping

- AC-001 maps to Spec-AC-01 (TEST-4024).
- AC-002 maps to Spec-AC-02 (TEST-4025).
- AC-003 maps to Spec-AC-03, Spec-AC-04, Spec-AC-05 (TEST-4026 to TEST-4028,
  hosted H1).
- AC-004 maps to Spec-AC-06 (TEST-4029).
- AC-005 maps to Spec-AC-07 and Spec-AC-08 (TEST-4030, TEST-4031, hosted H2).
- AC-006 maps to Spec-AC-07 and Spec-AC-09 (TEST-4030, TEST-4032, hosted H2).
- AC-007 maps to Spec-AC-10 to Spec-AC-13 (TEST-4033 to TEST-4036, the
  updated TEST-4021 and TEST-4022, hosted H1 to H3).

## Constitution deviations

None. (Article 5: the four release-launcher forms of DR-R1 to DR-R4 change
at a public boundary; they are explicit, tested and named in the CHANGELOG
entry, which the article requires of a breaking change.)

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | The Kept native scripts table of RFC-0017 SHALL hold exactly nine rows: the four existing rows unchanged and, in D-KEPT order, .aai/scripts/claude-hook-gate.sh, lib/test-residue.sh, lib/repo-tripwire.sh, lib/append-lock.sh and lib/git-bash-path.sh, each with a non-empty reason; TEST-4024 reads the table through parseKeptNative of tests/skills/lib/script-classes.mjs and exits 0. | done | docs/ai/tdd/node-first-phase5-closeout/green/TEST-4024.log; docs/ai/tdd/spec-node-first-phase5-closeout/mutation-TEST-4024.txt | — | D-KEPT; RED docs/ai/tdd/node-first-phase5-closeout/red/TEST-4024.log |
| Spec-AC-02 | WHEN TEST-4025 runs, the strict check over every tracked .sh and .ps1 under .aai/scripts (lib included) SHALL print no problem and exit 0; on a scratch copy seeded with a 21-code-line script without a row, a 3-code-line script naming git, a 21-code-line RETIRED script, a row with an empty reason and a row naming a file outside the list it SHALL exit 1 and name each seeded file or row; the classifier's code-line count SHALL equal the section 1 grep count for every live file. | planned | — | — | D-CLASS |
| Spec-AC-03 | WHEN aai-release.mjs runs with --launcher ps1 it SHALL accept in any letter case -Version v, -Version:v, -DryRun, -Confirm, -Yes and -NoRemote, a switch with a colon true or false suffix as on or off, and every form it accepts today, with the same parsed options as the matching double-dash form; WHEN it runs with --launcher sh or none a PowerShell form SHALL still exit 1 with Unknown argument; TEST-4026 exits 0. | planned | — | — | D-RELEASE grammar |
| Spec-AC-04 | .aai/scripts/aai-release.ps1 SHALL have at most 20 code lines by the section 1 method, no param block, only ASCII bytes, no policy token, the dot-source guard, the old refusal line and exit 20; WHEN TEST-4027 runs D-RELEASE-MATRIX through the frozen launcher and the new one under pwsh 7, by -File and in session, M01 to M16 SHALL give identical stdout, stderr and exit code after the launcher directory is normalized, and M17 to M20 SHALL give the New column of DR-R1 to DR-R4. | planned | — | — | D-RELEASE matrix |
| Spec-AC-05 | tests/skills/release-cut.Tests.ps1 SHALL hold TEST-4028 cases for each flag form by -File and in session, a switch given false by colon, the refusal line and exit 20 without node, a module exit code passed through and a dot-source that starts no node; they SHALL pass with 0 failed and 0 skipped under pwsh 7 (TEST-4028) and under Windows PowerShell 5.1 and pwsh 7 in the hosted windows-5_1 job with the skip count still AAI_EXPECTED_WIN_SKIP_COUNT (H1). | planned | — | — | D-RELEASE; hosted H1 |
| Spec-AC-06 | WHEN a share deploy fails, the stderr lines run writes SHALL hold no window of 8 consecutive characters of CLOUDFLARE_API_TOKEN or CLOUDFLARE_API_KEY and no ESC byte, for the follow-up probe and every D-REDACT layout; TEST-4029 exits 0 and was observed failing on the pre-change module. | planned | — | — | D-REDACT; closes fu-cfshare-redact-escape-robust |
| Spec-AC-07 | install-parity.mjs SHALL register the D-TWIN launcher twin running the scratch source's shipped aai-sync.sh and aai-update.sh through the driver's bash, paired only with node; WHEN the driver runs SY-01 and UP-01 with twins node and launcher on this host it SHALL exit 0 with verdict PASS and the pair node:launcher in both; the allowlist SHALL parse with the four twins and pass TEST-3570; TEST-4030 exits 0. | planned | — | — | D-TWIN |
| Spec-AC-08 | The driver SHALL run the no-odd-root host check after every sync and update step of the node and launcher twins and fail when a root entry with a name outside printable ASCII is born (a fake twin that makes one fails it in TEST-4031); in the hosted windows-parity job under both engines the check SHALL read pass for UP-01 twin launcher with checked at least 1 and its AAI-HOST-CHECK line SHALL be in the log (H2); plan section 7 SHALL name the root cause with the run id; win-sh-odd-root-dirs SHALL be removed or re-justified per D-ALLOW. | planned | — | — | D-HOSTCHECK, D-ODD, D-ALLOW; closes fu-parity-win-odd-root-dirs |
| Spec-AC-09 | On win32 the driver SHALL require every Source path line of AAI_PIN.md and every Source line of a sync-conflicts report written by the node and launcher twins to start with a drive letter, a colon and a backslash, with at least two lines checked in SY-01, and the control on the frozen sh twin's SY-01 pin SHALL read bites; on POSIX the check SHALL read not-applicable; install-parity.Tests.ps1 SHALL fail on win32 when the check or the control is absent, not passing or checked 0; TEST-4032 exits 0 and H2 shows the pass and bites lines under both engines. | planned | — | — | D-HOSTCHECK; closes fu-parity-win-source-path |
| Spec-AC-10 | The plan SHALL hold section 7 per D-REMEASURE whose file table equals the shared-classifier measurement of the tree with no logic row, twin duplication 0, the follow-up table, the outside-ref line, the root-cause line and the hosted line; the RFC-0017 phase 5 row SHALL read done only when the hosted line reads passed on a full sha with a run id and every section 5 criterion holds, else in progress naming section 7 and what remains; TEST-4022 and TEST-4033 exit 0. | done | docs/ai/tdd/node-first-phase5-closeout/green/TEST-4033.log; docs/ai/tdd/spec-node-first-phase5-closeout/mutation-TEST-4033.txt | — | D-REMEASURE, D-HOSTED; local record with the hosted line pending; the done flip of the RFC row waits for the record commit H2 |
| Spec-AC-11 | follow-ups list --status all SHALL show `fu-cfshare-redact-escape-robust`, fu-parity-win-odd-root-dirs and fu-parity-win-source-path closed with resolved_by node-first-phase5-closeout and a source naming a test file and a TEST id that occurs in it followed by a colon, the two Windows items also naming a ps1-quality run id; TEST-4034 and the updated TEST-4021 exit 0. | planned | — | — | D-FU |
| Spec-AC-12 | WHEN aai-sync.mjs installs the extended profile into a scratch target, every launcher and deprecation launcher of the shared classifier that the install holds SHALL run from it with its recorded arguments (sh under bash, ps1 under pwsh 7), exit with its recorded code and print neither the node-missing refusal nor a shell error, and a shipped launcher without a recorded row SHALL fail the test; TEST-4035 exits 0 (pwsh required on CI). | planned | — | — | plan section 5 criterion 3 |
| Spec-AC-13 | CHANGELOG.md SHALL hold one heading of the D-WIRE title whose entry names each consumer-visible change of this diff to a shipped file; the new suite SHALL be in suite-map.yaml and suite-weights.tsv; the frozen release reference and its helper SHALL be on both ps1-quality.yml path lists; a new .aai file SHALL have a PROFILES.yaml entry; the product doc, once written, SHALL pass the product-doc check; spec-amend list --strict SHALL exit 0 holding the D-AMEND records; TEST-4036 exits 0. | done | docs/ai/tdd/node-first-phase5-closeout/green/TEST-4036.log; docs/ai/tdd/spec-node-first-phase5-closeout/mutation-TEST-4036.txt | — | D-WIRE, D-AMEND; RED docs/ai/tdd/node-first-phase5-closeout/red/TEST-4036.log; the helper is not on the ps1-quality path lists, see the disclosed spec_amendment |

## Implementation plan

Order (each step RED first, evidence under
`docs/ai/tdd/node-first-phase5-closeout/red/` and `.../green/`):

1. D-CLASS lib and TEST-4025 (RED: six logic files), D-KEPT rows and
   TEST-4024 (RED: five rows missing), TEST-4022 refactor onto the lib.
2. D-RELEASE: frozen reference and helper, TEST-4026 (RED: `-DryRun`
   refused under ps1), module grammar, TEST-4027 (RED: 25 code lines and
   the param block), new launcher, TEST-4028 Pester cases, the TEST-3529 and
   TEST-019 updates.
3. D-REDACT: TEST-4029 (RED: the probe prints 19 of 20 characters, `ESC ( B`
   leaves an ESC byte), then the fix.
4. D-TWIN and D-HOSTCHECK: TEST-4030, TEST-4031, TEST-4032 (RED: no
   launcher twin, no host checks), the driver changes, the Pester
   assertions, the TEST-3565, TEST-3566, TEST-3568 and TEST-3570 updates;
   measure the smoke matrix time on this host and state it.
5. TEST-4035 (every launcher from a scratch install).
6. New suite and wiring, TEST-4033, TEST-4034, TEST-4036 (RED: no section 7,
   no closes, no entry), plan section 7 with `pending`, the RFC sentence
   with `in progress`, CHANGELOG entry, D-AMEND records.
7. D-HOSTED steps 2 to 4 with D-ODD inside them (the orchestrator pushes and
   reads the hosted runs; Implementation or Remediation makes the fix).

Seams crossed (principle 2):

- S1 classifier and the plan's grep method: TEST-4025 compares the lib's
  count with the section 1 grep count for every live file.
- S2 the RFC table and its two readers: TEST-4024, TEST-4025 and TEST-4022
  all read it through `parseKeptNative`; TEST-4025 seeds the empty-reason
  row the old regex dropped.
- S3 PowerShell launcher and module grammar: TEST-4027 end to end (old and
  new launcher, same module), TEST-4028 under real engines (H1 for 5.1).
- S4 share deploy output and the failure echo: TEST-4029 goes through
  `run` with an injected deploy.
- S5 shipped launchers, module and Git Bash environment: TEST-4030 on POSIX,
  H2 on Windows (the only place the Git Bash conversion exists).
- S6 doctor field report and the target root: TEST-4031 (fake twin) and H2.
- S7 follow-up ledger, plan section 7 and TEST-4022: TEST-4033, TEST-4034.
- S8 classifier classes and the installed launchers: TEST-4035.
- S9 the record and the hosted run: D-HOSTED; no test reads GitHub, so the
  binding of "passed on H1" to a real run is Validation's reading of `gh`
  output (residual risk below).

Hard safety rules for every test and diagnostic: scratch directories only,
created with an own prefix and ownership marker and removed by a trap on
failure; never a sync, update, hook install or release into this
repository or any real one; `GIT_CONFIG_*` scrubbed and scratch git
identities set per fixture; no container tool; no tag, release, push or
remote finish; delete only what the run provably created.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-4024 | Spec-AC-01 | inspection | tests/skills/test-aai-phase5-closeout.sh | test_4024_kept_native_rows parses the RFC-0017 table with parseKeptNative and requires the nine D-KEPT files in order, each with a non-empty reason, the four old rows byte-identical to base | `sed:s/ the bash pre-filter of the Claude hook gate[^\x7c]*/  /` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |
| TEST-4025 | Spec-AC-02 | integration | tests/skills/test-aai-hygiene-corpus.sh | test_4025_kept_native_gate_and_bite runs the strict CLI on the tree (exit 0), compares the lib count with the section 1 grep count per file, then runs it on a scratch copy with the five D-CLASS seeds via --files-from and requires exit 1 naming each seed | `sed:s/LAUNCHER_MAX_CODE_LINES = 20/LAUNCHER_MAX_CODE_LINES = 2000/` on tests/skills/lib/script-classes.mjs | red |
| TEST-4026 | Spec-AC-03 | unit | tests/skills/test-aai-release-cut.sh | test_4026_ps1_grammar runs run_node_tests TEST-4026 of tests/skills/lib/aai-release.test.mjs: each PS1_FLAGS form in three letter cases, the colon value and colon boolean forms, the double-dash forms under ps1 give the options of the double-dash form; under sh each PowerShell form is Unknown argument exit 1 | `sed:s/'-dryrun': '--dry-run'/'-dryrunx': '--dry-run'/` on .aai/scripts/aai-release.mjs | pending |
| TEST-4027 | Spec-AC-04 | integration | tests/skills/test-aai-release-cut.sh | test_4027_ps1_launcher_differential checks the D-RELEASE launcher shape (code lines, no param block, ASCII, no policy token, guard, refusal, exit 20) and runs D-RELEASE-MATRIX through the hash-verified frozen launcher and the new one under pwsh 7 (required on CI) | `sed:s/--launcher ps1/--launcher sh/` on .aai/scripts/aai-release.ps1 | pending |
| TEST-4028 | Spec-AC-05 | integration | tests/skills/test-aai-release-cut.sh | test_4028_ps1_pester runs Invoke-Pester on release-cut.Tests.ps1 filtered to the TEST-4028 cases under pwsh 7 and requires at least 6 passed, 0 failed, 0 skipped; the same cases run in the hosted windows-5_1 job under 5.1 and 7 (H1) | `sed:s/exit 20/exit 21/` on .aai/scripts/aai-release.ps1 | pending |
| TEST-4029 | Spec-AC-06 | unit | tests/skills/test-aai-cloudflare-share.sh | test_4029_redaction_layouts runs run_node_tests TEST-4029 of tests/skills/lib/cloudflare-share.test.mjs: the probe and every D-REDACT layout through run with an injected failing deploy; no 8-character secret window and no ESC byte in stderr | `sed:s/MIN_SECRET_WINDOW = 8/MIN_SECRET_WINDOW = 80/` on .aai/scripts/cloudflare-share.mjs | pending |
| TEST-4030 | Spec-AC-07 | integration | tests/skills/test-aai-install-parity.sh | test_4030_launcher_twin runs run_node_tests TEST-4030 of tests/skills/lib/install-parity.test.mjs: the registry entry, ops and peers, pair order node:launcher, the allowlist parse with four twins, and a real SY-01 and UP-01 run with twins node and launcher into scratch targets with verdict PASS | `sed:s/name: 'launcher'/name: 'launcherx'/` on tests/skills/lib/install-parity.mjs | pending |
| TEST-4031 | Spec-AC-08 | unit | tests/skills/test-aai-install-parity.sh | test_4031_no_odd_root runs run_node_tests TEST-4031: a fake launcher twin that creates a root directory with a non-ASCII name fails the no-odd-root check (status fail, verdict FAIL, exit not 0), a clean fake passes with checked above 0, an odd entry present before the step is not reported as born; the Windows arm is hosted H2 | `sed:s/ODD_NAME\.test\(name\)/false/g` on tests/skills/lib/install-parity.mjs | pending |
| TEST-4032 | Spec-AC-09 | unit | tests/skills/test-aai-install-parity.sh | test_4032_source_path_windows runs run_node_tests TEST-4032: the source-path predicate passes a drive-letter backslash path and fails a /c/ path, fewer than two checked lines in SY-01 fail, the control reads bites only when the frozen pin fails, the POSIX entry reads not-applicable; and the Pester file holds the win32 assertions of D-HOSTCHECK; the Windows arm is hosted H2 | `sed:s/const WIN_ABS_RE = .*;/const WIN_ABS_RE = \/^\/;/` on tests/skills/lib/install-parity.mjs | pending |
| TEST-4033 | Spec-AC-10 | inspection | tests/skills/test-aai-phase5-closeout.sh | test_4033_remeasure_record requires section 7 as the latest re-measure section, its file table equal to the classifier measurement with no logic row, twin duplication 0, the follow-up table equal to the ledger, the outside-ref line, the root-cause line, the hosted line in one of its two forms, the RFC row status rule, and the D-HOSTED diff check when the cited sha exists | `sed:s/## 7\. Re-measure after the phase 5 closeout/## 7. Remeasure after the phase 5 closeout/` on docs/analysis/node-first-remaining-plan.md | green |
| TEST-4034 | Spec-AC-11 | inspection | tests/skills/test-aai-phase5-closeout.sh | test_4034_follow_ups reads follow-ups list --status all --json and the close records and requires the three D-FU closes with their sources, each cited test file holding the cited TEST id followed by a colon, and a ps1-quality run id on the two Windows items | `sed:s/"resolved_by":"node-first-phase5-closeout"/"resolved_by":"node-first-phase5-closeoutx"/g` on docs/ai/decisions.jsonl | green |
| TEST-4035 | Spec-AC-12 | integration | tests/skills/test-aai-phase5-closeout.sh | test_4035_every_launcher_runs installs the extended profile with aai-sync.mjs into a scratch target and runs each launcher of the classifier from it with its recorded arguments and exit code, sh under bash and ps1 under pwsh 7, and fails on a launcher without a row | `sed:s/exec node/exec nodex/` on .aai/scripts/triage.sh | green |
| TEST-4036 | Spec-AC-13 | inspection | tests/skills/test-aai-phase5-closeout.sh | test_4036_docs_and_wiring requires the CHANGELOG heading and its named changes, the suite-map and weight rows, the ps1-quality path entries, PROFILES entries for any new .aai file, the product-doc check when the doc exists, and spec-amend list --strict exit 0 with the D-AMEND records | `sed:s/## \[unreleased\] — Node-first phase 5 closeout/## [unreleased] — Node-first phase five closeout/` on CHANGELOG.md | green |

Test counts by type: unit 4 (TEST-4026, TEST-4029, TEST-4031, TEST-4032),
integration 5 (TEST-4025, TEST-4027, TEST-4028, TEST-4030, TEST-4035),
inspection 4 (TEST-4024, TEST-4033, TEST-4034, TEST-4036); 13 rows.
TEST ids were taken from the highest id in use across every local and
remote branch's `docs/specs` and `tests` (TEST-4023 on origin/main at
0ff18d63), counted up from TEST-4024; no id of SPEC-0309 or SPEC-0310 is
reused.

Existing tests this scope edits (not Test Plan rows of this spec; D-AMEND
records them): TEST-4021 and TEST-4022 (test-aai-sync-docs.sh), TEST-3529
(test-aai-release-cut.sh), TEST-019 (test-aai-release.sh), TEST-3565,
TEST-3566, TEST-3568 and TEST-3570 (test-aai-install-parity.sh and its node
and Pester files).

Hosted checks (CI, read by Validation from the runs of D-HOSTED):

- H1: the windows-5_1 job's full Pester steps under Windows PowerShell 5.1
  and pwsh 7 pass with release-cut.Tests.ps1 and its TEST-4028 cases, no
  failed container, the skip count still AAI_EXPECTED_WIN_SKIP_COUNT; the
  gate job's Linux pwsh 7 Pester passes.
- H2: the windows-parity job's two steps (5.1 and 7) pass with the smoke
  matrix including twins node and launcher, and the log holds the
  `AAI-HOST-CHECK` lines `source-path-windows ... pass`,
  `source-path-windows-control ... bites` and `no-odd-root UP-01 launcher
  pass`.
- H3: the whole ps1-quality run (including windows-wsl1 and the Linux gate)
  and the skill-suite run (Linux) conclude success on the same head sha;
  macOS is the local Validation run of test-aai-install-parity.sh and the
  selected suites on this host (plan section 5 names Linux, macOS, 5.1 and
  7).

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash
  <suite>` exits 0 for tests/skills/test-aai-phase5-closeout.sh,
  test-aai-hygiene-corpus.sh, test-aai-hygiene-pack.sh,
  test-aai-release-cut.sh, test-aai-release.sh,
  test-aai-cloudflare-share.sh, test-aai-install-parity.sh,
  test-aai-sync-docs.sh, test-aai-follow-ups.sh, test-ps1-quality.sh,
  test-aai-win-fallback.sh, test-aai-suite-select.sh and every suite
  `select-suites.mjs` selects for the diff (plus the core set), each round;
  one full sweep before close with `AAI_TEST_TIMEOUT=3000`.
- `env -u AAI_ROLE node --test tests/skills/lib/aai-release.test.mjs
  tests/skills/lib/cloudflare-share.test.mjs
  tests/skills/lib/install-parity.test.mjs` exits 0 (also under Node 22).
- `node .aai/scripts/spec-lint.mjs --path <this spec>`,
  `node .aai/scripts/mutation-gate.mjs` for this spec,
  `node .aai/scripts/spec-amend.mjs list --strict` and
  `node .aai/scripts/follow-ups.mjs verify-closures --path <this spec>
  --strict` pass.
- Hosted checks H1 to H3 per D-HOSTED.
- PASS criteria: all TEST rows green with stored RED and GREEN logs and
  mutation records, every Spec-AC done with evidence, H1 to H3 read on the
  head that the record cites.

## Evidence contract

For each artifact: ref_id `node-first-phase5-closeout`, the Spec-AC and
TEST id, the command or review scope, the exit code or verdict, the
evidence path and the commit or diff range. RED and GREEN logs:
`docs/ai/tdd/node-first-phase5-closeout/{red,green}/TEST-xxxx.log`;
mutation records: `docs/ai/tdd/spec-node-first-phase5-closeout/mutation-TEST-xxxx.txt`;
hosted summaries and log excerpts:
`docs/ai/tdd/node-first-phase5-closeout/hosted/<run id>.txt`.

### Evidence by strategy

| Strategy | Evidence this spec may demand |
|---|---|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix |
| loop | per-TEST-xxx green runs; RED-proof observed, storage optional |
| direct | targeted regression tests green (exit codes) plus the scoped diff |
| untested | the recorded strategy rationale plus the scoped diff |

This spec is tdd: the first row applies; a hosted-only arm stores its RED
or control-bites excerpt under `hosted/`.

## Residual risks

- The Windows proofs exist only on the hosted runner; a local macOS run
  cannot exercise Git Bash path conversion or the odd directories. The
  closes of AC-005 and AC-006 depend on the hosted run (D-HOSTED).
- The odd-root cause may need several hosted iterations; the D-ODD stop
  rule bounds it at three diagnostic runs, then BLOCKED with options.
- The record cites a green run on H1 while the pull request head is H2;
  the docs-only delta is machine-checked only where the H1 object exists,
  and the binding of a run id to a real green run is read from `gh`, not
  tested.
- "No policy" is a token heuristic (git, `.gitignore`, PROFILES, the
  profile flag); a launcher that encodes policy in other words is
  classified a launcher. The plan's section 1 method defines it so.
- Three open P2 items with release or hook-gate names lie outside the
  plan's refs; section 7 names them and why, and the done rule does not
  count them (the rule TEST-4022 measures since SPEC-0310).
- DR-R1 to DR-R4 drop undocumented PowerShell binding forms of the release
  launcher; a caller using an abbreviation, a common parameter or a
  positional version now gets exit 1 with a named argument.
- The launcher twin lengthens the smoke matrix on every host (about one
  update run per engine on Windows); TEST-3569's bound applies only on the
  reference host and is re-measured in step 4.
- TEST-4035 runs the `.ps1` launchers under pwsh 7 on POSIX only; Windows
  PowerShell 5.1 coverage of each launcher stays with its own Pester file.

Registry items closed by this scope: fu-cfshare-redact-escape-robust.

Registry items closed by the record commit H2 after the hosted run (D-HOSTED step 4; they are not claimed above because verify-closures reads a claim of an item that is still open as a miss): fu-parity-win-odd-root-dirs and fu-parity-win-source-path.

Open items on the same subjects that this scope does not close, and why:
fu-cfshare-ps1-help-args and fu-cfshare-url-regex-osc8 (the share
launcher's binding and the URL extraction, not the redaction the owner
named); fu-update-ps1-colon-switch-args (aai-update.ps1, which this scope
does not change); fu-hook-gate-herestring-tmpfile (the hook-gate
pre-filter is listed as kept native, not changed);
fu-tripwire-attributes-concurrent-writes, fu-tree-lsof-unbounded,
fu-tree-mount-check-gaps and fu-tree-mount-walk-unbounded (the kept-native
bash libraries are listed, not changed); fu-delete-retired-legacy-migrations,
fu-delete-retired-shell-loop-runner and fu-delete-retired-pre-commit-checks-ps1
(deletion is the next release, owner decision 2 of the plan).
