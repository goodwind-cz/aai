---
id: spec-install-path-parity-harness
type: spec
number: 284
status: done
mutation_gate: v1
frozen_sha256: bad3a9aab07832c0e0e67300538f12de21f3e55a417ffa8e9f595dcfeb3eb635
ceremony_level: 2
links:
  requirement: install-path-parity-harness
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Run both twins of sync, update and the hook installer into scratch targets and diff what they leave behind

SPEC-FROZEN: true

## Links

- Requirement: [Run both twins of sync, update and the hook installer into scratch targets and diff what they leave behind](../issues/CHANGE-0254-install-path-parity-harness.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  phase 5, and the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  ride 8 (owner sign-off: no). Rides 9 to 12 (bootstrap, update, installer
  and sync on Node) are held to this harness.
- Pattern precedents: [SPEC-0283](SPEC-0283-spec-hook-gate-on-node.md) (the
  suite helpers `run_node_tests` and `need_tool`, a differential corpus, a
  `node:test` file beside a bash suite, wiring named up front) and
  [SPEC-0278](SPEC-0278-spec-git-hook-bodies-single-source.md) (both hook
  installers run in scratch repositories, Pester under 5.1 and 7 as a hosted
  check).
- The twins compared are owned elsewhere and are not changed:
  `.aai/scripts/aai-sync.sh` and `.ps1`, `.aai/scripts/aai-update.sh` and
  `.ps1`, `.aai/scripts/install-pre-commit-hook.sh` and `.ps1`.
- Technology contract: docs/TECHNOLOGY.md (bash 3.2 compatible suites, Node
  stdlib, `node:test`, Pester 5 for PowerShell, Windows PowerShell 5.1 and
  pwsh 7).
- Baseline: main `396c3cbb`.

## Implementation strategy

- Strategy: tdd
- Rationale: the owner asked for TDD in runs of about three Spec-ACs on
  every Node-first ride. The harness is itself a guard that rides 9 to 12
  rely on; a comparison, normalization or allowlist rule that never failed
  proves nothing, so each rule is seen failing on a synthetic tree first,
  and the real matrix run is RED on the baseline because the driver does
  not exist. Every row carries a mutation.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: a new suite plus CI path-filter and wiring edits; the
  main checkout is shared with other sessions and holds unrelated
  uncommitted files (docs/INDEX.md, docs/ai/EVENTS.jsonl, docs/ai/dashboard*,
  docs/ai/tests/test-runs.jsonl).
- User decision: worktree (owner-directed own worktree, recorded in STATE
  with rationale "owner-directed own worktree"; not an autopilot default)
- Base ref: main
- Worktree branch/path: test/install-path-parity-harness at /Users/ales/Projects/aai-worktrees/install-path-parity-harness
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  tests/skills/lib/install-parity.mjs tests/skills/lib/install-parity.test.mjs
  tests/skills/lib/install-parity-allowlist.tsv
  tests/skills/test-aai-install-parity.sh tests/skills/install-parity.Tests.ps1
  tests/skills/suite-map.yaml tests/skills/suite-weights.tsv
  tests/skills/test-aai-hygiene-pack.sh .github/workflows/ps1-quality.yml
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  docs/ai/decisions.jsonl
  docs/issues/CHANGE-0254-install-path-parity-harness.md
  docs/specs/SPEC-0284-spec-install-path-parity-harness.md docs/INDEX.md
  (decisions.jsonl only for the follow-up records of D-FU; the allocator
  renames the two DRAFT files at merge).
- Code review required: true.

## Ceremony

- Level 2: tests, one CI workflow path filter and docs; no protected
  surface (`protected_paths_l3` in docs/ai/docs-audit.yaml names none of the
  files above) and no production code.
- Suite selection: `.github/workflows/ps1-quality.yml` and the wiring files
  select several suites; Validation runs the selected suites plus the full
  sweep once before close (`AAI_TEST_TIMEOUT=3000`).

## Measurements behind the decisions

Measured on the planning tree (macOS arm64, bash 3.2.57, pwsh 7.6.3,
Node 22.23.1) on 2026-11-10 at `396c3cbb`, with a scratch source made from
the tracked tree and fresh `git init` targets in a scratch directory. One
run each; they size the matrix, they are not thresholds.

| Operation | bash twin | PowerShell twin | Files in the target |
|---|---|---|---|
| aai-sync, fresh, extended | 3 s | 4 s | 504 |
| aai-sync, fresh, core | 3 s | 3 s | 424 |
| aai-update, fresh, local source | 5 s | 4 s | 505 |
| hook installer, fresh, then re-run | 1 s | 1 s | 3 hooks |

Divergences seen in those runs (all bash against PowerShell; the seed of
the allowlist, D-ALLOW):

- `.aai/system/AAI_PIN.md`: `- Template version:  v2026.10.29` (two spaces)
  against one space; `- Synced at (UTC):` to the second against seven
  fraction digits.
- `.gitignore`: the AAI blocks come in a different order, and the runtime
  sidecar block has a different header text (`seeded from
  .aai/system/RUNTIME_IGNORE.list` against `seeded by aai-sync.ps1`); the
  PowerShell file has 4 more lines (54 against 50).
- `hooks/session-start.sh`: executable after the bash twin, not after the
  PowerShell twin (extended profile, macOS).
- `docs/ai/reports/sync-conflicts-<stamp>.md`: the bash twin stamps the name
  in UTC, the PowerShell twin in local time (with `TZ=Etc/GMT-3` the names
  were `...-185415.md` and `...-215419.md`, the UTC `Generated at` line of
  the PowerShell report saying `18:54:19.1023490Z`).
- The three hook bodies were byte-identical; both installers exited 0 on
  install and re-run.

Who reads the twins from the source tree: both sync twins read `.aai/`,
`.claude/skills`, `.codex/skills`, `.gemini/skills`, `.agents/skills`,
`hooks/`, `docs/knowledge/`, `docs/ai/AAI_VERSION.md`, `README.md`,
`.github/copilot-instructions.md`, `.cursor/rules/`, `.claude-plugin/`
(found with a grep of `$SRC_ROOT/` reads in the bash twin and the same
names in the PowerShell twin). The hook installers also read
`.aai/scripts/lib/guard-config.mjs`, `.aai/scripts/lib/docs-audit-core.mjs`
and `.aai/templates/git-hooks/`, so hook scenarios run inside a synced
target.

CI budget: `tests/skills/suite-weights.tsv` sums 7460 s over 132 suites in
4 shards (each leg's job timeout 30 minutes); a new suite enters at the
documented fallback weight 196. The suite stays at that weight on purpose: the
weights audit admits a measured row only from five CI run samples, and the
fallback (the maximum) already starts the suite first in the queue; its wall
alone is about 120 s. The sweep scheduler has no serial or heavy slot, so
weights only order the queue and nothing keeps it off other heavy suites. The Windows job of ps1-quality.yml
(`windows-5_1`) runs the whole `tests/skills` Pester discovery under 5.1 and
again under pwsh 7, with a 30-minute job bound against a measured maximum of
20.6 minutes; the `windows-wsl1` job runs it once more under 5.1. The new
Pester file takes about three minutes per engine on a hosted runner, which
put those full-suite steps at 570 to 585 s against their 600 s ceiling, so
it runs in its own `windows-parity` job instead (D-WIRE) and the full-suite
steps exclude it. The
expected Windows skip count is pinned at 4 (`AAI_EXPECTED_WIN_SKIP_COUNT`)
and `test-ps1-quality.sh` fails a POSIX Pester run that skips anything, so
the new Pester file never skips.

## Decisions

### D-DRIVER. One Node driver, two front ends

`tests/skills/lib/install-parity.mjs` (Node stdlib only, ESM) holds the
scenario matrix, the fixture builders, the twin registry, the runner, the
tree snapshot, the normalizations, the comparison and the allowlist. It is
both a CLI and a module the `node:test` file imports (importing it runs
nothing). Front ends: the bash suite on Linux and macOS and the Pester file
on every host. CLI:

- `node install-parity.mjs list --matrix <smoke|default|full> [--json]`
  prints the scenario ids of the tier, one per line (or a JSON array).
- `node install-parity.mjs run --matrix <tier> [--scenario <id>]...
  [--twins <names>] [--twin-module <name>=<path>]... [--allowlist <tsv>]
  [--bash <path>] [--ps <path>] [--json <file>] [--keep]` runs the
  scenarios, prints one line per scenario (id, seconds, verdict) and one line
  per uncovered divergence, stale row or broken scenario, and writes the
  D-REPORT JSON when `--json` is given.
- Defaults: `--twins` every registered twin in registry order (so a twin
  added to `TWINS` runs in both front ends with no edit there), the committed
  allowlist, `--bash bash`, `--ps pwsh`, and for the scratch base
  `AAI_PARITY_SCRATCH`, else `/tmp` on darwin (the PowerShell twin is about ten
  times slower under `$TMPDIR`) and the OS temp directory elsewhere. `--keep` leaves the scratch root and prints its path; without
  it the scratch root is removed on every exit path.
- Exit codes: 0 every compared pair matches or is covered and no row is
  stale; 1 an uncovered divergence, a stale row or a broken scenario; 2 a
  usage error or an allowlist that does not parse (named row and field); 3 a
  missing tool (node, git, the `--bash` or `--ps` executable), named. 4 an infrastructure break: a twin step or a fixture command outlived its bound (below).
- Every child process has a bound of 300 s, or `AAI_PARITY_STEP_TIMEOUT`
  seconds when that variable is a positive number (anything else is a usage
  error, exit 2; the bash suite sets 900 unless the caller names a value); on
  expiry the child and every process of its group are killed (a POSIX process
  group, `taskkill /T` on Windows) and the driver leaves no process behind.
  A twin step that expires is an infrastructure break, not a parity
  divergence: the driver prints `INFRA timeout <scenario> <twin> <step>`,
  makes no divergence or stale judgement for that run, writes no report and
  exits 4. A step that merely exits 124 by itself is an ordinary exit code.
  A fixture command (git, the sh sync that builds a scratch target) is bound by
  the larger of 300 s and that value, so a small value cannot make fixture
  building flake; one that still expires prints `INFRA timeout fixture <command>`
  and exits 4 the same way.

### D-SEAM. The twin registry and the third twin

A twin is `{ name, argv(step, ctx) }` returning `{ file, args, cwd }`;
`step` is twin-neutral (`{ op: 'sync' or 'update' or 'hooks', profile,
flags }`, flags from `force`, `uninstall`, `decline-ref-guard`) and `ctx`
holds `src` (the scratch source root), `target`, `bash` and `ps`. The
registry `TWINS` holds `sh` (the `.sh` twin under `ctx.bash`) and `ps1` (the
`.ps1` twin under `ctx.ps -NoProfile -NonInteractive -ExecutionPolicy
Bypass -File`, `-ExecutionPolicy` only on win32). Twin argv, as each twin's
own usage spells it:

- sync: sh `bash <src>/.aai/scripts/aai-sync.sh <target> [--profile p]`,
  ps1 `-File <src>/.aai/scripts/aai-sync.ps1 -TargetRoot <target> [-Profile p]`, cwd the target.
- update: sh `bash <src>/.aai/scripts/aai-update.sh --repo <src> --ref main`,
  ps1 `-File <src>/.aai/scripts/aai-update.ps1 -Repo <src> -Ref main`, cwd
  the target (the updater targets its cwd).
- hooks: the target's own installer, sh `bash .aai/scripts/install-pre-commit-hook.sh [--force] [--uninstall] [--decline-ref-guard]`,
  ps1 `-File .aai/scripts/install-pre-commit-hook.ps1 [-Force] [-Uninstall] [-DeclineRefGuard]`, cwd the target.

`--twins` names registry twins in order (absent: every registered twin); `--twin-module <name>=<path>`
imports a module whose default export is `{ argv(step, ctx) }` and appends
it under `<name>` (`[a-z0-9-]+`, no clash with a registered name). Every
pair of twins `(i, j)` with `i < j` in that order is compared, so a third
twin is compared against both shell twins. Rides 9 to 12 add their Node
twin as a third `TWINS` entry (for example `node`) and their pairs to the
allowlist; nothing else in the driver or in a front end changes, because the
default `--twins` is the registry. Anchors the mutations rely
on: the pair loop is written `for (let j = i + 1; j < twins.length; j += 1)`
and `const REFERENCE_TWIN = 'sh';`.

### D-MATRIX. Scenarios

Each scenario is an object literal that starts `{ id: '<ID>', tier: '<tier>', op: '<op>'`
in `SCENARIOS`; `smoke` is a subset of `default`, which is a subset of
`full`. Every step declares its expected exit on the reference twin (`0` or
`nonzero`) and every scenario names probe paths that must exist in every
twin's tree afterwards (positive controls, D-BROKEN). Scenarios with two
steps on one twin also compare each twin's tree after step 2 with its own
tree after step 1 (the pair `sh:sh`, `ps1:ps1`): the idempotence check.

| ID | Tier | Op | Setup (built once per twin, identically) | Steps | Expect | Probes |
|---|---|---|---|---|---|---|
| SY-01 | smoke | sync | empty git repository at `SY-01/target with space` | sync core | 0 | .aai/system/AAI_PIN.md, .gitignore |
| SY-02 | default | sync | empty git repository | sync extended; sync with no profile (sticky pin) | 0, 0 | .aai/system/AAI_PIN.md, .codex/skills/README.md |
| SY-03 | default | sync | git repository whose CRLF `.gitignore` holds `node_modules/`, `.env`, `.aai/` and `.aai/cache/` twice | sync core | 0 | .gitignore |
| SY-04 | default | sync | git repository with a `hooks/hooks.json` holding one user hook entry and a project-edited `hooks/session-start.sh` | sync core | 0 | hooks/hooks.json |
| SY-05 | full | sync | empty git repository | sync extended | 0 | .aai/system/AAI_PIN.md |
| SY-06 | full | sync | empty git repository | sync extended; sync core (prune) | 0, 0 | .aai/system/AAI_PIN.md |
| SY-07 | full | sync | OLDER-CORE fixture (F3) | sync core | 0 | .aai/system/AAI_PIN.md |
| UP-01 | smoke | update | OLDER-CORE fixture (F3) | update | 0 | .aai/system/AAI_PIN.md |
| UP-02 | full | update | empty git repository | update | 0 | .aai/system/AAI_PIN.md |
| UP-03 | full | update | OLDER-EXTENDED fixture (F3) | update | 0 | .aai/system/AAI_PIN.md |
| HK-01 | smoke | hooks | INSTALLED-BASE copy (F4) | install | 0 | .git/hooks/pre-commit, .git/hooks/reference-transaction, .git/hooks/pre-push |
| HK-02 | default | hooks | INSTALLED-BASE copy | install; install | 0, 0 | .git/hooks/pre-commit |
| HK-03 | smoke | hooks | INSTALLED-BASE copy with a foreign executable `.git/hooks/pre-commit` | install | nonzero | .git/hooks/pre-commit |
| HK-04 | default | hooks | as HK-03 | install with force | 0 | .git/hooks/pre-commit |
| HK-05 | smoke | hooks | INSTALLED-BASE copy with an AAI pre-commit hook written from `pre-commit-index.sh` alone (no guard block, the pre-guard body) | install | 0 | .git/hooks/pre-commit |
| HK-06 | default | hooks | INSTALLED-BASE copy with `core.hooksPath` set to `.githooks` | install | 0 | .githooks/pre-commit |
| HK-07 | smoke | hooks | INSTALLED-BASE copy whose `docs/ai/docs-audit.yaml` declares `ref_guard: declined` | install | 0 | .git/hooks/pre-commit |
| HK-08 | default | hooks | INSTALLED-BASE copy | install with decline-ref-guard | 0 | docs/ai/docs-audit.yaml |
| HK-09 | default | hooks | INSTALLED-BASE copy | install; install with uninstall | 0, 0 | docs/ai/docs-audit.yaml |
| HK-10 | smoke | hooks | INSTALLED-BASE copy at `HK-10/target with space` | install | 0 | .git/hooks/pre-commit |

Tier sizes: smoke 7, default 15, full 20. Runtime estimate on the planning
host from the measured operation times (fixtures about 12 s once per run):
smoke about 40 s, default about 80 s, full about 130 s; CI Linux about 1.5
times that. The bash suite runs `default` (`AAI_PARITY_MATRIX=full` opts in
to the full matrix, `smoke` is also accepted); the Pester file runs `smoke`
on every host. Windows is not measured at planning (estimate 2 to 4 minutes
per engine for `smoke`); the PR's ps1-quality run records it (Verification
H2).

### D-FIX. Fixtures (built once per run, copied per twin)

- F1 CURRENT SOURCE `<root>/src`: every tracked path of the checkout
  (`git ls-files -z`, working-tree bytes, so an uncommitted twin is what
  runs; a file the index stores with LF that the working tree holds with
  CRLF, as a Windows checkout with `core.autocrlf` does, is written with its
  index LF, and a NOTE line names how many) except `tests/**` and `docs/**` other than `docs/knowledge/**` and
  `docs/ai/AAI_VERSION.md`; a NOTE line names the two excluded trees (the
  degrade-with-NOTE convention). Then `git init`, `git symbolic-ref HEAD
  refs/heads/main`, a repository-local `user.email` and `user.name`, one
  commit. The update scenarios pass F1 as `--repo`, so the updater's
  checkout of `main` happens in the scratch source, never in the checkout.
- F2 OLDER SOURCE: a copy of F1 with `docs/ai/AAI_VERSION.md` set to
  `- Version: v2026.01.01`, one file listed under `core:` in
  `.aai/system/PROFILES.yaml` removed, a line appended to `.aai/AGENTS.md`,
  committed the same way.
- F3 OLDER-CORE and OLDER-EXTENDED installs: an empty git repository synced
  by the `sh` twin from F2 with that profile, then legacy leftovers the sync
  cleans up (one entry of each class the legacy cleanup of aai-sync.sh names:
  an `ai/` file, a moved `scripts/` file, a moved `docs/ai/` file, one retired
  skill wrapper) and a target-only `.aai/scripts/project-local.sh`.
- F4 INSTALLED-BASE: an empty git repository synced by the `sh` twin from F1
  with `--profile core`.
- Every fixture repository has its own `user.email`, `user.name` and
  `commit.gpgsign false`. F3 and F4 are built by the `sh` twin only to give
  every twin the same starting tree; that build is not a parity statement.
- Each twin runs a scenario in the same absolute target path (the tree of
  the first twin is renamed to `out-<twin>` before the next twin's copy is
  laid down), so absolute paths written into files compare equal without
  any path normalization. Between two steps of one twin that write stamped
  files (sync and update), the driver waits for the next wall-clock second.

### D-ENV. The twins' environment

Each twin process gets the caller's environment with these changes, and no
other: every `AAI_*` variable removed; `TZ=Etc/GMT-3` (`const PINNED_TZ =
'Etc/GMT-3';`, a non-UTC zone, so a local-time stamp next to a UTC stamp
shows up on POSIX; Windows ignores `TZ`); `GIT_CONFIG_NOSYSTEM=1` and
`GIT_CONFIG_GLOBAL=<root>/gitconfig` (an empty file), so neither the
caller's system nor global git configuration (a global `core.hooksPath`, an
`init.templateDir`) reaches a twin; `TMPDIR`, `TMP` and `TEMP` set to
`<root>/tmp`; the one addition is `GIT_REDIRECT_STDERR=2>&1` for the `ps1`
twin's update step on a host whose PowerShell is older than 6 (Windows
PowerShell 5.1 ends `aai-update.ps1` at its first git stderr line, so the rest
of the update is compared; a NOTE line names it and `fu-parity-win-update-5-1-stderr`
tracks the defect). On win32 the `sh` twin runs under the bash the caller passes
with `--bash` (the Pester file resolves Git for Windows' bash, D-PESTER).

### D-SNAP. Snapshot and comparison

A snapshot is every path under the target (directories included, so an
empty directory counts), each with its kind (file, dir, symlink and its
target), bytes as sha256, and for files the executable bit. Exclusions
(E-rows) and normalizations (N-rows) apply before comparison. Divergence
kinds (`const KINDS = ['exit', 'missing', 'bytes', 'lines', 'order', 'mode'];`):

- `exit`: a step's exit codes differ (path `step<N>`).
- `missing`: a path exists in one tree only (or with a different kind).
- `order`: a text file holds the same multiset of lines in a different order.
- `lines`: a text file's lines differ as multisets; the divergence carries
  the lines only on side a and only on side b.
- `bytes`: a file differs and is not text (contains NUL or is not UTF-8).
- `mode`: the executable bit differs; compared only when
  `const MODE_MEANINGFUL = process.platform !== 'win32';` is true.

A text file whose lines differ only by line terminator is a `lines`
divergence (no line-ending normalization). Console output is not compared.

### D-NORM. Normalizations and exclusions, the complete list

`NORMALIZATIONS` in the driver holds exactly these ids, each with a reason
string; nothing else rewrites a byte or a name.

| Id | What | Shape matched exactly | Replaced by | Reason |
|---|---|---|---|---|
| N1 | AAI_PIN.md sync time | the line `- Synced at (UTC): YYYY-MM-DDTHH:MM:SSZ` | `- Synced at (UTC): <stamp>` | wall clock |
| N2 | sync-conflicts report time | the line `- Generated at (UTC): YYYY-MM-DDTHH:MM:SSZ` | `- Generated at (UTC): <stamp>` | wall clock |
| N3 | sync-conflicts report name | `docs/ai/reports/sync-conflicts-YYYYMMDD-HHMMSS.md`, whether or not its stamp equals that file's own Generated-at line in UTC to the second | `sync-conflicts-<stamp-k>.md`, k the ordinal by original name (disagreeing names included) | wall clock; a name whose stamp disagrees with the file's own Generated-at line is renamed by the same ordinal (so the two twins' reports pair and their content is compared) and the disagreement is reported on its own, as a `missing` divergence at the path ending `#name`, when only one of the two sides has it (`const NAME_MUST_MATCH_STAMP = true;` keeps a time-zone divergence visible) |
| N4 | doctor report name | `docs/ai/reports/doctor-YYYYMMDDTHHMMSSZ-<host>.md` | `doctor-<stamp-k>.md` | wall clock and host name |
| E1 | git internals | everything under `.git/`, except for hooks scenarios the regular files of `.git/hooks/` not ending `.sample` | excluded | the object store and index are git's output, sample hooks are git's own |
| E2 | doctor report content | the content of a file N4 renamed (its presence stays compared) | excluded | written by the shared `update-doctor-report.mjs`, not by a twin; holds host and clock; the tree it describes is compared already |

A stamp with fraction digits matches neither N1 nor N2 (the PowerShell
twin's seven-digit stamps stay visible as `lines` divergences).

### D-ALLOW. The allowlist

File `tests/skills/lib/install-parity-allowlist.tsv`: `#` comment lines,
blank lines ignored, a CR before LF tolerated, one row per line with
exactly nine TAB-separated fields:

1. `id`: `[a-z0-9-]+`, unique.
2. `pairs`: a comma list of `a:b` twin pairs in registry order (`sh:ps1`),
   or a self pair (`ps1:ps1`) for the idempotence check.
3. `scenario`: `*` or a comma list of scenario ids.
4. `path`: a POSIX path in the normalized tree, `*` within one segment,
   `**` across segments; `step<N>` for kind `exit`.
5. `kind`: one of the six kinds.
6. `host`: `any`, `posix`, `win32`, `utc`, `non-utc`, `bsd-sed` or `ps5`
   (`ps5` holds when the `--ps` engine reports a major version below 6; the
   `bsd-sed` probe runs through the `--bash` the sh twin uses) (the twins'
   zone: POSIX is always `non-utc` through `PINNED_TZ`; win32 is `utc` when
   the host's offset is 0; `bsd-sed` holds when a probe of the host's `sed`
   with the expression aai-sync.sh uses shows BSD behavior, which is macOS
   only: GNU sed on Linux, Git for Windows and WSL strips the space).
7. `tracker`: `accepted` (by design, the reason says why) or a follow-up id
   `fu-...` that `node .aai/scripts/follow-ups.mjs list --status all --json`
   knows.
8. `match`: `-` for every kind but `lines`; for kind `lines` a JavaScript
   regular expression that every differing line on both sides must match (the
   parser refuses `-` there, since it would cover every line of the path). A
   regular expression led by `=` is paired: it needs a capture group, and the
   captured values of the lines it covers must be the same on both sides, so
   the row excuses a difference in the text around a value and never a
   difference in the value. A row of kind `missing` with a `fu-...` tracker
   may instead take `?`: intermittent, it covers a divergence when one is
   present and is never judged stale (the parser refuses `?` for any other
   kind, for an `accepted` tracker, for a path with a wildcard or for host `any`); `win-sh-odd-root-dirs` uses it because
   the sh update leaves no odd root directory on some Windows runs.
9. `reason`: non-empty free text, no TAB.

A divergence is covered when a row matches its pair, scenario, path, kind
and host and, for `lines`, every differing line matches the `match` regular
expression of at least one such row (a file that differs in two unrelated
ways takes one row per way; a row whose regular expression matched any
differing line of a covered divergence counts as having covered it). A `bytes` row never
covers a text file (anti-masking: a text divergence needs `lines` or
`order`). Staleness is judged only on a whole-tier run (no `--scenario`
filter; a filtered run prints `stale check: off (scenario filter)`): a row
is stale, per row and pair, when the run executed a scenario it names (any,
for `*`), on a host it names, for a pair of the row that ran in it, and the
row covered nothing for that pair (a dead pair inside a multi-pair row is
reported, naming the pair); rows for scenarios or pairs that did not run are
not judged. The stale computation is
`function staleRows(` ending `return stale;` (a mutation anchor). The parser refuses
(exit 2) a wrong field count, an empty reason, an unknown kind or host, a
pair naming a twin that is not registered in this run, a duplicate id, a
tracker that is neither `accepted` nor `fu-...`, and a `match` that does not
compile.

Seed rows (the planning measurements; TDD verifies each against the real
run and corrects path, kind or host to what the run shows, recording the
correction in the green log):

| Row id | Kind | Path | Host | Tracker |
|---|---|---|---|---|
| pin-template-version-spacing | lines | .aai/system/AAI_PIN.md | bsd-sed | fu-parity-pin-template-spacing |
| pin-synced-at-precision | lines | .aai/system/AAI_PIN.md | any | fu-parity-ps1-timestamp-precision |
| gitignore-block-order | order | .gitignore | any | fu-parity-gitignore-block-order |
| gitignore-block-headers | lines | .gitignore | any | fu-parity-gitignore-block-order |
| session-start-exec-bit | mode | hooks/session-start.sh | posix | fu-parity-ps1-hook-exec-bit |
| conflict-report-name-local-time | missing | docs/ai/reports/sync-conflicts-*#name | non-utc | fu-parity-ps1-report-name-local-time |
| conflict-report-generated-precision | lines | docs/ai/reports/sync-conflicts-* | any | fu-parity-ps1-timestamp-precision |

Windows rows (from the hosted ps1-quality run, recorded in the remediation
pass): `win-source-path-pin` and `win-source-path-report` (host `win32`; the
sh twin under Git Bash writes the scratch source path as `/c/...` where ps1
writes `C:\...`, `fu-parity-win-source-path`); `win-ps1-pin-newline-bom`,
`win-ps1-report-newline-bom` and `win-ps1-gitignore-newline` (host `win32`,
paired rows that excuse a trailing CR and, for the first two, a leading byte
order mark, `fu-parity-win-ps1-crlf-bom`); `win-sh-odd-root-dirs` (scenario
UP-01, host `win32`, kind `missing`, `fu-parity-win-odd-root-dirs`). A path
whose first segment leaves printable ASCII is reported at `<odd-root-name>`
(plus the rest of the path) with the real name, shown as code points, in the
detail, so one row can name the random wide-character directories the sh
update leaves on Windows; this is a reporting spelling of a divergence, not a
rewrite of a snapshot name, and NORMALIZATIONS is unchanged.

Every further divergence a real run shows (on any host, including the
Windows CI legs) gets one row with a reason and a tracker; a twin bug gets a
follow-up (D-FU), a by-design difference `accepted`. No row is added to make
a mutation pass, and no row uses `**` with kind `bytes`.

### D-BROKEN. Positive controls

A scenario is BROKEN (exit 1, named) when the reference twin's exit on a
step does not meet the step's expectation, or when a probe path is missing
from any twin's tree. The check is written
`if (!expectMet(step.expect, ref.code)) broken.push(` so that two twins
failing the same way never pass as parity.

### D-REPORT. JSON report

`{ verdict, host, tz, matrix, twins, pairs, total_seconds, scenarios: [{ id,
seconds, steps: [{ twin, step, code }], broken, divergences: [{ pair, path,
kind, detail, covered_by }] }], uncovered, stale }`; `verdict` is `PASS` or
`FAIL`.

### D-PESTER. The Pester file

`tests/skills/install-parity.Tests.ps1` (Pester 5, 5.1-compatible syntax):

- Never skips (no `-Skip`, no host-skip guard); a missing node or bash is a
  failure that names the tool.
- `BeforeAll` dot-sources `lib/pester-native-capture.ps1` and runs every
  native call through `Invoke-NativeCaptured` (the repository's helper for
  native probes under `$ErrorActionPreference = 'Stop'` on 5.1; the older
  `Invoke-Quiet` no longer exists in this tree).
- The PowerShell twin's engine is the running one:
  `(Get-Process -Id $PID).Path`, passed as `--ps`.
- bash: on a Windows host, the first existing of
  `$env:ProgramFiles\Git\bin\bash.exe`, `${env:ProgramFiles(x86)}\Git\bin\bash.exe`,
  the `bin\bash.exe` three levels above `git --exec-path`, and a PATH
  `bash.exe` not under `System32` (the WSL shim is never used; the
  `windows-wsl1` leg has WSL installed); elsewhere `bash` from PATH.
- One `It` runs `node tests/skills/lib/install-parity.mjs run --matrix smoke --bash <bash> --ps <engine> --json <file>`
  (its argument array holds the literal pair `'--matrix', 'smoke'`, a
  mutation anchor)
  and requires exit 0 and `verdict` PASS, printing the driver's stdout and
  stderr on failure; one `It` requires the report's scenario ids to equal
  `list --matrix smoke --json`. `AAI_PARITY_PESTER_SCENARIOS` (a comma list
  of smoke scenario ids) narrows both the driver call (one `--scenario` each)
  and the expected list to those ids; unset, the whole smoke matrix runs. The
  bash suite sets it to HK-01 because its default matrix (TEST-3565) has
  already run both twins over every smoke scenario; the `windows-parity`
  job and the Linux ps1 gate leave it unset and run the whole smoke matrix
  through Pester.

### D-SUITE. The bash suite

`tests/skills/test-aai-install-parity.sh`, bash 3.2 compatible,
`set -euo pipefail`, every case a `test_<id>_<name>` function called from
`main`, helpers `need_tool` (an absent tool fails on CI, a named SKIP-CASE
locally) and `run_node_tests` (a pattern that matches no passing case
fails), as in `test-aai-hook-gate.sh`. The matrix comes from
`PARITY_MATRIX="${AAI_PARITY_MATRIX:-default}"` in function
`parity_matrix`, which refuses any value but smoke, default and full. The
real run happens once per suite invocation into `$TEST_DIR/run.json`;
later cases read it. Lessons applied: no `printf | grep -q` or `| head`
under pipefail (read into a variable, then match), an EPIPE exit is
accepted as 0 or 141 wherever a reader may close early, no bare `rc=$?`
after a command `set -e` would kill, every fixture git repository has its
own identity and a bare origin (none is needed here) would get
`symbolic-ref HEAD`, and no ride-scoped exact-diff or line-count pin (no
test counts allowlist rows or matrix-run divergences, and none pins this
branch's diff).

### D-WIRE. Wiring, named up front

- `tests/skills/suite-map.yaml`: new row `aai-install-parity` with globs
  `.aai/scripts/aai-sync.sh`, `.aai/scripts/aai-sync.ps1`,
  `.aai/scripts/aai-update.sh`, `.aai/scripts/aai-update.ps1`,
  `.aai/scripts/install-pre-commit-hook.sh`,
  `.aai/scripts/install-pre-commit-hook.ps1`, `.aai/templates/git-hooks/**`,
  `.aai/scripts/lib/gitignore-block.sh`, `.aai/scripts/lib/merge-hooks-json.mjs`,
  `.aai/scripts/lib/guard-config.mjs`, `.aai/scripts/lib/docs-audit-core.mjs`,
  `.aai/scripts/update-doctor-report.mjs`, `.aai/system/PROFILES.yaml`,
  `.aai/system/RUNTIME_IGNORE.list`, `.aai/system/COPILOT_SHIM_SHIPPED.list`,
  `.aai/templates/update-config.template.yaml`,
  `.aai/templates/docs-audit.template.yaml`, `hooks/**`,
  `docs/ai/AAI_VERSION.md`, `tests/skills/lib/install-parity.mjs`,
  `tests/skills/lib/install-parity.test.mjs`,
  `tests/skills/lib/install-parity-allowlist.tsv`,
  `tests/skills/install-parity.Tests.ps1`,
  `tests/skills/lib/pester-native-capture.ps1`,
  `tests/skills/lib/nested-suite-lint.mjs`,
  `tests/skills/lib/nested-suite-allowlist.tsv`, `tests/skills/suite-map.yaml`,
  `tests/skills/suite-weights.tsv`, `.github/workflows/ps1-quality.yml`, and
  every other `tests/skills/lib/*` file the suite sources or reads.
- `tests/skills/suite-weights.tsv`:
  `# sample aai-install-parity fallback unsampled (new suite of install-path-parity-harness; no successful observation)`
  and `aai-install-parity<TAB>196` (the documented maximum; the scheduler
  offers no serial or heavy mechanism).
- `test-aai-hygiene-pack.sh` `test_090_suite_map_pin`: the one literal
  row-count pin moves 132 to 133 (verified at planning: the only `-eq 132`
  in tests/skills is that line). A parallel ride that adds a suite moves it
  again; the branch that merges second rebases the pin.
- Nested-suite lint: no new allowlist row; the suite calls other suites
  only in selector form (`test-aai-hygiene-pack.sh test_090_suite_map_pin`,
  `test-aai-hygiene-pack.sh test_129_mutation_gate_suite_registration`,
  `test-aai-win-fallback.sh test_034`, `test-aai-expert-fetch.sh test_2624_inventory_matches_tree`).
- `tests/skills/lib/cd-subshell-leak-baseline.tsv`: unchanged; the new suite
  holds no `cd` inside a command substitution, so
  `node .aai/scripts/check-cd-subshell-leak.mjs` passes without a re-record.
- `check-test-registration.mjs`: every `test_*` function is called.
  `check-vendored-script-deps.mjs` exits 0.
- `.github/workflows/ps1-quality.yml`: both `push` and `pull_request` path
  lists (identical) gain `.aai/scripts/aai-sync.sh`,
  `.aai/scripts/aai-update.sh`, `.aai/scripts/install-pre-commit-hook.sh`,
  `.aai/scripts/lib/gitignore-block.sh`,
  `.aai/scripts/lib/merge-hooks-json.mjs`, `hooks/**`,
  `tests/skills/lib/install-parity.mjs` and
  `tests/skills/lib/install-parity-allowlist.tsv`, so the Windows Pester
  legs run when either twin or the harness changes; the derivation pin
  `test-aai-win-fallback.sh` test_034 stays green. One job and one
  exclusion change: a `windows-parity` job (own 20-minute bound, Windows
  PowerShell 5.1 and pwsh 7 steps, each printing `AAI-PARITY-ELAPSED` and
  failing unless the file passes with 0 skipped) runs
  `tests/skills/install-parity.Tests.ps1`, and every full-suite discovery
  step of `windows-5_1` and `windows-wsl1` sets `Run.ExcludePath` to
  `*install-parity.Tests.ps1`; the Linux gate keeps it. The TotalCount floor
  111, the skip reconciliation and the TEST-008 seed checks are unchanged,
  and `AAI_EXPECTED_WIN_SKIP_COUNT` stays 4. TEST-3571 inspects both.
- `.aai/system/PROFILES.yaml`: unchanged (no new `.aai/**` file). Prompt
  corpus: no `.aai/*.prompt.md` or `.aai/AGENTS.md` change, so no
  prompt-diet ledger entry and no TEST-012 move.
- CHANGELOG: none. The scope is internal (tests and a CI path filter);
  `release-notes-gate.mjs` counts `.github/` as shipped, so the PR body
  carries `no-notes: test-only parity harness and a CI path filter; nothing
  a consumer installs or runs changes`.

### D-RFC. RFC-0017

Phase 5 row: one sentence after the twelfth-slice sentence and before the
remaining-scripts-plan sentence:
`The thirteenth slice [ran both twins of the install path into scratch targets](../issues/CHANGE-0254-install-path-parity-harness.md): a test-only harness compares the trees and exit codes of the bash and PowerShell twins of aai-sync, aai-update and the hook installer, with each known divergence on a reviewed list, and takes the Node twins of the later rides as a third twin.`
Status stays `in progress`; frontmatter untouched. The allocator rewrites
the link at merge; checks match only the suffix
`install-path-parity-harness.md`. The inventory table is unchanged.

### D-FU. Follow-ups

Each seed tracker above, and each further twin bug the runs show, is filed
with `node .aai/scripts/follow-ups.mjs add --id <id> --ref install-path-parity-harness --severity P3 --what ... --why ... --source "<scenario> <path>: sh <value> / ps1 <value>"`
(ids at most 40 characters, prefix `fu-parity-`). Fixing a divergence is out
of scope: the twins are untouched by this ride.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01, Spec-AC-02 and Spec-AC-06.
- Intake AC-002 maps to Spec-AC-04 and Spec-AC-05.
- Intake AC-003 maps to Spec-AC-03 and Spec-AC-08.
- Intake AC-004 maps to Spec-AC-07.
- Intake AC-005 maps to Spec-AC-06, Spec-AC-09 and hosted checks H1 and H2
  (the native Windows Pester legs under Windows PowerShell 5.1 and pwsh 7).
- Intake AC-006 maps to Spec-AC-10.
- Intake AC-007 maps to Spec-AC-11, Spec-AC-12 and Spec-AC-13.

## Constitution deviations

None. Article 1 (evidence before claims): every comparison rule is proved
failing on a synthetic tree, and a scenario whose reference twin misses its
expectation fails as broken instead of passing as parity (D-BROKEN). Article
2 (simplicity): one driver, one data file, no dependency, no new flag on any
twin. Article 4 (degrade and report): a missing tool fails on CI and is a
named SKIP-CASE locally in the bash suite; the Pester file fails by name;
excluded source trees are printed as a NOTE. Article 5 (additive first):
no production file changes.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | node tests/skills/lib/install-parity.mjs list --matrix smoke, default and full each print exactly the scenario ids of the D-MATRIX table rows of that tier and of the tiers below it (smoke 7, default 15, full 20), read from this spec by its id; an unknown tier exits 2. | done | docs/ai/tdd/install-path-parity-harness/green/TEST-3560.txt; docs/ai/tdd/install-path-parity-harness/green/suite-partB.txt; docs/ai/tdd/spec-install-path-parity-harness/mutation-TEST-3560.txt | — | — |
| Spec-AC-02 | WHEN compareTrees runs on two synthetic directories, the system SHALL report one divergence of each kind exit, missing, order, lines, bytes and mode (mode only where MODE_MEANINGFUL holds) with its pair, path and detail, count an empty directory and a symlink target as tree content, and report a CRLF-only difference as lines. | done | docs/ai/tdd/install-path-parity-harness/green/TEST-3561.txt; docs/ai/tdd/install-path-parity-harness/green/node-test-all.txt; docs/ai/tdd/spec-install-path-parity-harness/mutation-TEST-3561.txt | — | — |
| Spec-AC-03 | NORMALIZATIONS holds exactly N1, N2, N3, N4, E1 and E2, each with a non-empty reason; N1 and N2 rewrite only the second-precision line and leave a fraction-digit stamp and every other byte unchanged; N3 renames every sync-conflicts report by ordinal and reports a name that disagrees with its own Generated-at line in UTC at the path ending #name; E1 keeps non-sample .git/hooks files for hooks scenarios only. | done | docs/ai/tdd/install-path-parity-harness/green/TEST-3562.txt; docs/ai/tdd/install-path-parity-harness/green/node-test-all.txt; docs/ai/tdd/spec-install-path-parity-harness/mutation-TEST-3562.txt | — | — |
| Spec-AC-04 | The allowlist parser exits 2 naming the row for each D-ALLOW refusal; WHEN a run meets a divergence the system SHALL pass it only when rows match pair, scenario, path, kind and host and, for lines, each differing line matches the regex of one of them, never cover a text file with a bytes row, and exit 1 naming each uncovered divergence and, on a whole-tier run, each stale row. | done | docs/ai/tdd/install-path-parity-harness/green/TEST-3563.txt; docs/ai/tdd/install-path-parity-harness/green/node-test-all.txt; docs/ai/tdd/spec-install-path-parity-harness/mutation-TEST-3563.txt | — | — |
| Spec-AC-05 | WHEN the reference twin's exit misses a step's expectation or a probe path is absent from a twin's tree, the run SHALL exit 1 and name the scenario as broken, also when both twins fail alike. | done | docs/ai/tdd/install-path-parity-harness/green/TEST-3564.txt; docs/ai/tdd/install-path-parity-harness/green/node-test-all.txt; docs/ai/tdd/spec-install-path-parity-harness/mutation-TEST-3564.txt | — | — |
| Spec-AC-06 | The bash suite runs the default matrix with twins sh and ps1 against the committed allowlist on Linux and macOS and the driver exits 0 with verdict PASS, every default scenario compared with each probe present, and the idempotence pairs compared for SY-02, HK-02 and HK-09. | done | docs/ai/tdd/install-path-parity-harness/green/run-default.out; docs/ai/tdd/install-path-parity-harness/green/suite-partB.txt; docs/ai/tdd/install-path-parity-harness/green/suite-full-matrix.txt; docs/ai/tdd/spec-install-path-parity-harness/mutation-TEST-3565.txt | — | — |
| Spec-AC-07 | WHEN a module twin that delegates to the sh twin is added with --twin-module, the run SHALL compare it with sh and ps1 and pass with an allowlist whose sh:ps1 rows also list ps1 and that twin; a module twin that appends one byte to AAI_PIN.md SHALL fail naming the pairs sh and ps1 against it on that path. | done | docs/ai/tdd/install-path-parity-harness/green/TEST-3566.txt; docs/ai/tdd/install-path-parity-harness/green/suite-partB.txt; docs/ai/tdd/spec-install-path-parity-harness/mutation-TEST-3566.txt | — | — |
| Spec-AC-08 | Every twin process sees TZ equal to PINNED_TZ, GIT_CONFIG_NOSYSTEM=1, GIT_CONFIG_GLOBAL naming the scratch file, TMPDIR under the scratch root and no AAI_ variable, shown by an env-recording module twin; HK-01 with a caller GIT_CONFIG_GLOBAL that sets core.hooksPath still installs into .git/hooks for both twins and passes. | done | docs/ai/tdd/install-path-parity-harness/green/TEST-3567.txt; docs/ai/tdd/install-path-parity-harness/green/suite-partB.txt; docs/ai/tdd/spec-install-path-parity-harness/mutation-TEST-3567.txt | — | — |
| Spec-AC-09 | tests/skills/install-parity.Tests.ps1 run with Invoke-Pester under pwsh 7 passes with at least 2 passed tests, 0 skipped and 0 failed; it runs the smoke matrix with the running engine as --ps (only the scenarios of AAI_PARITY_PESTER_SCENARIOS when that is set), resolves bash through the four D-PESTER candidates on Windows without the System32 shim, routes native calls through Invoke-NativeCaptured and holds no -Skip. | done | docs/ai/tdd/install-path-parity-harness/green/pester-pwsh7.txt; docs/ai/tdd/install-path-parity-harness/green/suite-partB.txt; docs/ai/tdd/spec-install-path-parity-harness/mutation-TEST-3568.txt | — | — |
| Spec-AC-10 | The suite takes the matrix from AAI_PARITY_MATRIX (default when unset, smoke and full accepted, anything else a named failure); the report carries per-scenario and total seconds; with AAI_PARITY_REFERENCE_HOST=1 the default matrix finishes in at most 150 s and smoke in at most 75 s, and the measured values are recorded. | done | docs/ai/tdd/install-path-parity-harness/green/suite-partB-refhost-default.txt; docs/ai/tdd/install-path-parity-harness/green/timing-smoke-refhost.txt; docs/ai/tdd/spec-install-path-parity-harness/mutation-TEST-3569.txt | — | — |
| Spec-AC-11 | Every allowlist row has a tracker that is accepted or an id that follows-ups.mjs list --status all --json knows, and every fu tracker's source names the path it was seen on; the seed rows exist with the D-ALLOW ids. | done | docs/ai/tdd/install-path-parity-harness/green/TEST-3570.txt; docs/ai/tdd/install-path-parity-harness/green/suite-partB.txt; docs/ai/tdd/spec-install-path-parity-harness/mutation-TEST-3570.txt | — | — |
| Spec-AC-12 | Wiring per D-WIRE: select-suites selects aai-install-parity for each of the six twin files, the driver, the allowlist and the Pester file; the weights row is 196 with its fallback line; hygiene test_090 pins 133 and test_129 passes; nested-suite lint, check-cd-subshell-leak, check-test-registration and check-vendored-script-deps exit 0; both ps1-quality.yml path lists are identical and hold the D-WIRE entries and win-fallback test_034 passes. | done | docs/ai/tdd/install-path-parity-harness/green/suite-partB.txt; docs/ai/tdd/spec-install-path-parity-harness/mutation-TEST-3571.txt | — | — |
| Spec-AC-13 | The RFC-0017 phase 5 row keeps status in progress and holds the D-RFC sentence exactly once with a link ending install-path-parity-harness.md, and expert-fetch test_2624 passes. | done | docs/ai/tdd/install-path-parity-harness/green/suite-partB.txt; docs/ai/tdd/spec-install-path-parity-harness/mutation-TEST-3572.txt | — | — |

## Implementation plan

TDD in five runs of about three Spec-ACs; each run stores RED under
`docs/ai/tdd/install-path-parity-harness/red/` before its change, GREEN
under `green/`, and one mutation record per row
(`node .aai/scripts/mutation-run.mjs`) before the run's hand-off.

1. Run 1, Spec-AC-02, 03, 04: the `node:test` file and the driver's pure
   parts (snapshot, compare, normalize, allowlist parse and apply) on
   synthetic trees.
2. Run 2, Spec-AC-01, 05, 07, 08: the matrix, fixtures F1 to F4, the runner,
   the twin registry with `--twin-module`, the environment, the positive
   controls.
3. Run 3, Spec-AC-06, 11: the real default run, the allowlist rows it needs
   (seed rows verified, further rows added with reasons), the follow-ups.
4. Run 4, Spec-AC-09, 10: the Pester file, the tier switch, the timing.
5. Run 5, Spec-AC-12, 13: D-WIRE, D-RFC; then a full-matrix run once
   (`AAI_PARITY_MATRIX=full`) with its rows, recorded in the green log.

Edge cases: a twin that hangs is killed at its bound (300 s, or AAI_PARITY_STEP_TIMEOUT) and the run exits 4 with an INFRA timeout line; a
target path with a space (SY-01, HK-10); two runs of one twin within one
second (the driver waits for the next second); a CRLF allowlist on a
Windows checkout; Git for Windows paths passed to bash as `C:/...`.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3560 | Spec-AC-01 | inspection | tests/skills/test-aai-install-parity.sh | test_3560_matrix_tiers reads the D-MATRIX table of the spec with id spec-install-path-parity-harness under docs/specs, runs list --matrix for each tier with --json and requires the ids of that tier and the tiers below it, in table order; list --matrix bogus exits 2 | `sed:s/id: 'SY-02', tier: 'default'/id: 'SY-02', tier: 'full'/` on tests/skills/lib/install-parity.mjs | green |
| TEST-3561 | Spec-AC-02 | unit | tests/skills/test-aai-install-parity.sh | test_3561_compare_kinds runs run_node_tests TEST-3561 on tests/skills/lib/install-parity.test.mjs: synthetic tree pairs give exactly one divergence of each kind with pair, path and detail, an empty directory and a symlink target count, a CRLF-only change is lines, and on POSIX an executable-bit change is mode | `sed:s/const MODE_MEANINGFUL = process.platform !== 'win32';/const MODE_MEANINGFUL = false;/` on tests/skills/lib/install-parity.mjs | green |
| TEST-3562 | Spec-AC-03 | unit | tests/skills/test-aai-install-parity.sh | test_3562_normalizations runs run_node_tests TEST-3562: the NORMALIZATIONS ids and reasons; N1 and N2 on second and fraction stamps; a timestamp-like string elsewhere unchanged; N3 with an agreeing and a disagreeing name; N4 with two doctor reports; E1 for a hooks and a sync scenario; E2 keeps presence | `sed:s/const NAME_MUST_MATCH_STAMP = true;/const NAME_MUST_MATCH_STAMP = false;/` on tests/skills/lib/install-parity.mjs | green |
| TEST-3563 | Spec-AC-04 | unit | tests/skills/test-aai-install-parity.sh | test_3563_allowlist runs run_node_tests TEST-3563: each parser refusal exits 2 naming the row and field; covered and uncovered divergences; a lines row whose regex misses one line; a bytes row on a text file; a stale row on a whole-tier run; rows for a scenario or pair not run, for another host (a bsd-sed row is judged only where the host sed is BSD and is a failure again on a GNU-sed host), the committed pin row on a BSD-sed and a GNU-sed host, and every row of a scenario-filtered run are not stale | `sed:s/return stale;/return [];/` on tests/skills/lib/install-parity.mjs | green |
| TEST-3564 | Spec-AC-05 | unit | tests/skills/test-aai-install-parity.sh | test_3564_broken runs run_node_tests TEST-3564: the F2 core-entry finder on an LF and a CRLF PROFILES.yaml and a CRLF stamp line; runScenario with injected twins where the reference twin exits 3 on a step that expects 0, where both twins exit 3 alike, and where a probe path is absent, each reported broken with verdict FAIL | `sed:s/if \(!expectMet\(step\.expect, ref\.code\)\) broken\.push\(/if (false) broken.push(/` on tests/skills/lib/install-parity.mjs | green |
| TEST-3565 | Spec-AC-06 | integration | tests/skills/test-aai-install-parity.sh | test_3565_default_matrix needs node, git and pwsh, runs the driver with the suite's matrix (default unless AAI_PARITY_MATRIX says otherwise), twins sh,ps1 and the committed allowlist into $TEST_DIR/run.json, and requires exit 0, verdict PASS, every scenario of the tier in the report with no broken entry, and self pairs present for SY-02, HK-02 and HK-09 | `sed:s/pin-template-version-spacing\t[^\n]*\n//` on tests/skills/lib/install-parity-allowlist.tsv | green |
| TEST-3566 | Spec-AC-07 | integration | tests/skills/test-aai-install-parity.sh | test_3566_third_twin writes two module twins into $TEST_DIR (mirror delegates to the sh argv, skew does the same and appends one byte to .aai/system/AAI_PIN.md after the step) and a scratch allowlist whose sh:ps1 rows also list ps1:mirror; --scenario SY-01 with mirror exits 0 with pairs sh:mirror and ps1:mirror in the report; with skew exits 1 naming sh:skew and ps1:skew on .aai/system/AAI_PIN.md | `sed:s/for \(let j = i \+ 1; j < twins\.length; j \+= 1\)/for (let j = i + 1; j < Math.min(twins.length, 2); j += 1)/` on tests/skills/lib/install-parity.mjs | green |
| TEST-3567 | Spec-AC-08 | integration | tests/skills/test-aai-install-parity.sh | test_3567_environment runs an env-recording module twin with AAI_ROLE and AAI_GIT_WRITE set in the caller and requires TZ=Etc/GMT-3, GIT_CONFIG_NOSYSTEM=1, GIT_CONFIG_GLOBAL under the scratch root, TMPDIR under the scratch root and no AAI_ name; then HK-01 with a caller GIT_CONFIG_GLOBAL setting core.hooksPath to an outside directory exits 0 with the three hooks under .git/hooks for both twins and nothing in that directory | `sed:s/const PINNED_TZ = 'Etc\/GMT-3';/const PINNED_TZ = 'UTC';/` on tests/skills/lib/install-parity.mjs | green |
| TEST-3568 | Spec-AC-09 | integration | tests/skills/test-aai-install-parity.sh | test_3568_pester needs pwsh and Pester 5, runs Invoke-Pester on tests/skills/install-parity.Tests.ps1 under env -u AAI_ROLE and requires at least 2 passed, 0 skipped, 0 failed and 0 failed containers; with AAI_PARITY_PESTER_SCENARIOS=HK-01 (the full smoke matrix runs in the Windows and Linux ps1 jobs); then inspects the file for the four bash candidates, the System32 exclusion, Invoke-NativeCaptured on every native call and no -Skip | `sed:s/'--matrix', 'smoke'/'--matrix', 'nonesuch'/` on tests/skills/install-parity.Tests.ps1 | green |
| TEST-3569 | Spec-AC-10 | integration | tests/skills/test-aai-install-parity.sh | test_3569_tiers_and_timing calls parity_matrix with AAI_PARITY_MATRIX unset (default), smoke, full and bogus (named failure); reads per-scenario and total seconds from $TEST_DIR/run.json (running the smoke matrix when the file is absent); with AAI_PARITY_REFERENCE_HOST=1 requires the D-MATRIX bounds, else prints them | `sed:s/AAI_PARITY_MATRIX:-default/AAI_PARITY_MATRIX:-smoke/` on tests/skills/test-aai-install-parity.sh | green |
| TEST-3570 | Spec-AC-11 | inspection | tests/skills/test-aai-install-parity.sh | test_3570_trackers parses the committed allowlist with the driver's parser, requires every tracker to be accepted or an id in follow-ups.mjs list --status all --json whose source names the row's path, and requires the seven D-ALLOW seed ids | `sed:s/\tfu-parity-ps1-hook-exec-bit\t/\tfu-parity-nonesuch\t/` on tests/skills/lib/install-parity-allowlist.tsv | green |
| TEST-3571 | Spec-AC-12 | inspection | tests/skills/test-aai-install-parity.sh | test_3571_wiring pipes the six twin files, the driver, the allowlist and the Pester file to select-suites.mjs --files-from - and requires aai-install-parity each time; requires one weights row at 196 with its fallback line; runs the hygiene-pack test_090 and test_129 selectors and the win-fallback test_034 selector; runs nested-suite-lint with its allowlist, check-cd-subshell-leak, check-test-registration and check-vendored-script-deps (exit 0); requires the push and pull_request path lists of ps1-quality.yml to be identical and to hold every D-WIRE entry | `sed:s/  aai-install-parity:/  aai-install-parity-gone:/` on tests/skills/suite-map.yaml | green |
| TEST-3572 | Spec-AC-13 | inspection | tests/skills/test-aai-install-parity.sh | test_3572_rfc requires the RFC-0017 phase 5 row to keep status in progress and hold the D-RFC sentence exactly once with a link ending install-path-parity-harness.md, and runs expert-fetch test_2624_inventory_matches_tree (exit 0) | `sed:s/The thirteenth slice \[ran both twins/The thirteenth slice [ran one twin/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |

Test counts by type: unit 4, integration 5, inspection 4 (13 rows).

Seams crossed (Principle 2): the driver against the real twins it
compares (TEST-3565 runs both twins of all three tools into the same
fixtures and reads what they wrote); the updater's checkout of a ref in the
scratch source it is given (UP-01 in TEST-3565); the sync twin's install
read by the hook installers (F4, HK scenarios in TEST-3565); the twin
registry and a module twin, the seam rides 9 to 12 plug into (TEST-3566);
the caller's environment against the twins' (TEST-3567); the Pester engine
against the driver and the PowerShell twin it starts (TEST-3568, and
natively on Windows in hosted checks H1 and H2); the follow-up registry read
for trackers (TEST-3570); select-suites, the hygiene pins, the nested-suite
lint, the cd ratchet, the registration check and the ps1 path-filter
derivation reading the new files (TEST-3571); the RFC inventory read by
SPEC-0249's check (TEST-3572).

Hosted checks (CI, not Test Plan rows; recorded in the validation report
from the PR's ps1-quality run):

- H1: the `windows-parity` job's two steps (Windows PowerShell 5.1 and pwsh 7)
  report `install-parity.Tests.ps1` passed, and the full-suite steps of
  `windows-5_1` and `windows-wsl1` exclude it with the expected skip count
  still 4, the TotalCount floor 111 and no failed container.
- H2: the elapsed time of that file under each engine (the
  `AAI-PARITY-ELAPSED` line) and of the full-suite steps (the
  `AAI-PESTER-ELAPSED` line), against their bounds.

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-install-parity.sh`
  exits 0 (13 rows), plus the touched and selected suites run the same way:
  test-aai-hygiene-pack.sh, test-aai-win-fallback.sh, test-aai-suite-select.sh,
  test-aai-expert-fetch.sh, test-aai-git-hook-templates.sh,
  test-aai-update.sh, test-aai-layer-profiles.sh; then the full sweep once
  before close with `AAI_TEST_TIMEOUT=3000`.
- `env -u AAI_ROLE node --test tests/skills/lib/install-parity.test.mjs` exits 0.
- `AAI_PARITY_MATRIX=full` run of the suite once, its report kept as
  evidence; `AAI_PARITY_REFERENCE_HOST=1` run on the planning host with the
  timing table recorded in the validation report.
- `bash tests/skills/test-ps1-quality.sh` on a host with pwsh and Pester
  exits 0 (the new Pester file passes, no POSIX skip).
- Hosted checks H1 and H2 from the PR's ps1-quality run; a divergence that
  appears only on Windows gets an allowlist row and a follow-up in a
  remediation pass, never a normalization.
- No production change: `git diff --stat main -- .aai hooks CHANGELOG.md`
  prints nothing (recorded in the validation report, not pinned by a test).
- `node .aai/scripts/spec-lint.mjs --path <this spec>` and
  `node .aai/scripts/mutation-gate.mjs` for this spec pass.

## Evidence contract

ref_id `install-path-parity-harness`; RED, GREEN and mutation evidence
under `docs/ai/tdd/install-path-parity-harness/` and
`docs/ai/tdd/spec-install-path-parity-harness/` (gitignored); each AC row's
Evidence names its green log and mutation record; the validation report and
review verdict under `docs/ai/reports/` and `docs/ai/reviews/`.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Residual risks

- Windows time: the smoke tier is not measured on Windows at planning; the
  `windows-parity` job runs it twice (5.1 and 7) inside its own 20-minute
  bound (measured at about 200 s per engine), apart from the 600 s full-suite
  ceiling. If a later run puts it near the bound, the remediation moves HK-05
  and HK-10 out of `smoke` (a tier edit, recorded), never the job bound.
- Windows-only divergences (line endings written by `Set-Content` under
  5.1, `fu-ps1-setcontent-rewrites-seed-eol`) are found only by the CI legs;
  each costs a remediation pass with a row and a follow-up.
- The scratch source leaves out `tests/**` and most of `docs/**`; a twin
  that starts reading another `docs/` path fails the same way in both twins
  and the probes catch only what they name. The NOTE line keeps the
  exclusion visible.
- The older install is synthesized from the current tree (D-FIX F2, F3),
  not from a real older release, so a difference that only an older sync
  script's own output would create is not exercised.
- The idempotence pairs compare a twin with itself; a twin that is
  consistently wrong passes them, which is why the twin pairs exist.
- Console output is not compared; a twin that prints a different
  disclosure is not caught here (`fu-ps1-decline-not-disclosed` stays open).
- The umbrella RFC-0017 stays open across this child-phase delivery; the
  close may trip the docs-audit false-open on the parent, suppressed with a
  fresh doc_lifecycle event as in earlier slices.

Registry items closed by this scope: none

Items this scope leaves open, with reasons: fu-ps1-setcontent-rewrites-seed-eol,
fu-three-readers-three-whitespaces, fu-ps1-symlink-config-replaced,
fu-ps1-decline-not-disclosed, fu-ps1-refusal-no-manual-merge,
fu-ps1-writeerror-terminates-before-exit (twin behaviour; this ride compares
and records, it does not fix; a run that reproduces one of them cites it as
the row's tracker instead of filing a duplicate).
