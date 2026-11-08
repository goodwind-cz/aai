---
id: spec-hook-gate-on-node
type: spec
number: null
status: implementing
frozen_sha256: 7c5671b03cb9b1598ca82619928540570f15843b0936d6feb05ab9da36d48a07
mutation_gate: v1
ceremony_level: 3
links:
  requirement: hook-gate-on-node
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Move the Claude hook gate's decisions to one Node module behind a bash pre-filter, and gate the Azure merge command

SPEC-FROZEN: true

## Links

- Requirement: [Move the Claude hook gate's decisions to one Node module behind a bash pre-filter, and gate the Azure merge command](../issues/CHANGE-DRAFT-hook-gate-on-node.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  phase 5, and the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  ride 7 (owner sign-off: yes, on the plan, 2026-11-05; plan section 4 item 3
  makes the hook gate L3 in this ride).
- Pattern precedents: ride 3 [SPEC-0276](SPEC-0276-spec-cloudflare-share-on-node.md)
  and ride 6a [SPEC-0281](SPEC-0281-spec-release-on-node.md) (one Node
  module, injected process seam, one `node:test` case per drift, the suite
  helpers `run_node_tests` and `need_tool`, wiring named up front), ride 5
  [SPEC-0279](SPEC-0279-spec-pre-commit-checks-ps1-retire.md) (an L3 guard
  ride, parity against `git show <base>:<script>`).
- The behaviour the gate mirrors is owned elsewhere and is not changed:
  `.aai/scripts/pre-commit-checks.sh` (commit), `.aai/scripts/merge-policy.mjs`
  `--check` (lane path), `.aai/scripts/lane-gate.mjs` `--sweep-check` (gate 2b),
  constitution articles 6 and 7.
- Technology contract: docs/TECHNOLOGY.md (bash, Node stdlib, `node:test`,
  bash suites).
- Baseline: main `c88cf708`.

## Implementation strategy

- Strategy: tdd
- Rationale: the owner asked for TDD in runs of about three Spec-ACs (rides 1
  to 6). The gate is an L3 guard that runs on every tool call of a
  consumer project with the hooks overlay; every drift decision is a
  behaviour that must be seen failing first on the baseline, and the
  differential parity row is RED on the baseline because the module does
  not exist. Inspection rows (wiring, L3 lists, budget) are RED on the
  baseline too. Every row carries a mutation.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: the scope edits L3 protected surfaces
  (`.aai/workflow/WORKFLOW.md`, `docs/ai/docs-audit.yaml`, and the two gate
  files it adds to the lists), so WORKFLOW.md gives the worktree gate
  REQUIRED semantics (an explicit recorded decision); the main checkout is
  shared and holds unrelated uncommitted files (docs/INDEX.md,
  docs/ai/EVENTS.jsonl, docs/ai/dashboard*, docs/ai/tests/test-runs.jsonl).
- User decision: worktree (owner decision 2026-11-08, recorded in STATE with
  rationale "owner decision 2026-11-08: own worktree for L3 ride, parallel
  with ride 6b"; not an autopilot default)
- Base ref: main
- Worktree branch/path: refactor/hook-gate-on-node at /Users/ales/Projects/aai-worktrees/hook-gate-on-node
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/hook-gate.mjs .aai/scripts/claude-hook-gate.sh
  .aai/scripts/merge-policy.mjs .aai/workflow/WORKFLOW.md
  docs/ai/docs-audit.yaml .aai/templates/docs-audit.template.yaml
  .aai/system/PROFILES.yaml
  tests/skills/test-aai-hook-gate.sh tests/skills/lib/hook-gate.test.mjs
  tests/skills/lib/hook-gate-latency.mjs
  tests/skills/test-aai-hooks-overlay.sh tests/skills/test-aai-merge-policy.sh
  tests/skills/test-aai-hitl-propagation.sh
  tests/skills/suite-map.yaml tests/skills/suite-weights.tsv
  tests/skills/test-aai-hygiene-pack.sh
  tests/skills/lib/cd-subshell-leak-baseline.tsv
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md CHANGELOG.md
  docs/ai/decisions.jsonl
  docs/issues/CHANGE-DRAFT-hook-gate-on-node.md
  docs/specs/SPEC-DRAFT-spec-hook-gate-on-node.md docs/INDEX.md
  (decisions.jsonl only for the follow-up close record; the allocator
  renames the two DRAFT files at merge).
- Code review required: true, on the most capable tier (L3: mandatory; a
  waiver is flagged to the operator, never auto-accepted).

## Ceremony

- Level 3: the scope touches `.aai/workflow/WORKFLOW.md` and
  `docs/ai/docs-audit.yaml`, and adds `.aai/scripts/claude-hook-gate.sh` and
  `.aai/scripts/hook-gate.mjs` to `protected_paths_l3` (owner decision
  2026-11-05).
- What L3 adds here, per the WORKFLOW.md table: the recorded worktree
  decision (done, the owner's); full independent validation, never a delta
  re-check; mandatory code review on the most capable tier; an operator
  checkpoint before merge with an explicit final-diff sign-off (the owner
  merges). No other owner token is needed to edit the surfaces:
  `test-aai-hitl-propagation.sh` TEST-014 accepts an L3 touch authorized by
  a frozen `ceremony_level: 3` spec in the same diff, which this spec is.
- Suite selection: `select-suites.mjs` answers `FULL_RUN reason=protected-l3`
  for WORKFLOW.md and docs-audit.yaml, so Validation runs the full sweep
  (`AAI_TEST_TIMEOUT=3600`).

## Measurements behind the decisions

Measured on the planning tree (macOS arm64 Apple M4 Max, bash 3.2.57, BSD
`/usr/bin/grep`, Node 22.23.1, `LANG=C.UTF-8`) on 2026-11-08 at `c88cf708`,
by running the real script against a scratch git fixture with payloads
written to a file (no live pipe into the script).

### Lines (the plan's method, section 1)

Code lines are non-blank, non-comment lines
(`grep -cvE '^[[:space:]]*(#|$)'` under bash with `/usr/bin/grep`).

| Script | Total lines | Code lines | Git mode |
|---|---|---|---|
| claude-hook-gate.sh | 632 | 341 | 100755 |

`gh` appears on 19 code lines (60 tokens counting comments); the follow-up's
"30 gh sites" is not reproducible on this tree.

### Latency today (n=60 per case, `spawnSync('bash', [gate, name])`, payload on stdin)

| Gate | Command in the payload | Exit | p50 | p95 |
|---|---|---|---|---|
| commit | `ls -la docs/specs` | 0 | 30.8 ms | 36.1 ms |
| merge | `ls -la docs/specs` | 0 | 29.8 ms | 35.0 ms |
| state-dump | `ls -la docs/specs` | 0 | 29.6 ms | 37.1 ms |
| commit | `git status --short` | 0 | 29.5 ms | 34.0 ms |
| merge | `git log --oneline -5` | 0 | 30.2 ms | 35.2 ms |
| merge | `git merge feature-x` | 2 | 38.7 ms | 44.6 ms |
| stop-nudge | (Stop payload, this repo's STATE) | 0 | 33.4 ms | 35.8 ms |

Reference floors on the same host: `node -e 0` 19.9 ms p50, 23.1 ms p95; a
bash script that reads stdin and matches it with `case` without starting
Node 3.3 ms p50, 4.2 ms p95. The hooks overlay runs the three PreToolUse
gates on every Bash tool call, so an ordinary command costs three bash and
three Node start-ups today.

### Early-closing pipe sites

By the pipe-safe ratchet's `PGQ_PATTERN` (comment lines dropped, bash,
`/usr/bin/grep`): 9 sites, 7 `printf` piped into `grep -q`/`grep -Eq`
(lines 112, 122, 137, 472, 490, 599, 600) and 2 piped into `head` (110,
492). The script sets `set -u` only, never `pipefail`, so the ratchet's
shipping arm skips it (it counts only files that set `pipefail`). The plan
row said "7 sites under pipefail": the 7 is the `grep -q` subset, and the
script does not run under `pipefail` unless the caller exports it.

### Reproduction (scratch fixture, bash, 3 of 3 runs each unless noted)

- Azure merge forms allowed: `node .aai/scripts/platform.mjs merge --pr 7
  --expect-head abc --operator-merge` and `az repos pr update --id 7
  --status completed` exit 0 without `AAI_OPERATOR_MERGE`; `gh pr merge 42
  --squash` exits 2 (one run each; deterministic).
- Inherited `pipefail`: with `SHELLOPTS=braceexpand:hashall:interactive-comments:pipefail`
  exported, `gh pr merge 42 --squash`, `git merge feat` and
  `python3 -c 'yaml.dump(open("docs/ai/STATE.yaml"))'`, each followed by
  8000 filler lines, exit 0 (allowed); without `SHELLOPTS` the merge case
  exits 2. A 300000-byte single-line command does not misfire (`grep`
  reads the whole line first).
- Text that only names a merge command is denied: `git commit -m "explain
  git merge handling"` and `echo gh pr merge 5` exit 2 from the merge gate.
- The operator marker as a command prefix,
  `AAI_OPERATOR_MERGE=1 gh pr merge 42 --squash`, exits 2 (the hooks-overlay
  suite pins this as TEST-1520 "operator marker as prefix is not a lane
  marker").
- Locale: `gh<U+00A0>pr merge 5` exits 2 under `LANG=C.UTF-8` and 0 under
  `LC_ALL=C` (BSD grep's `[[:space:]]` follows the locale).
- The hooks overlay is not installed in this repository or in the owner's
  user settings (`.github/workflows/docs-numbering.yml` says so too), so no
  live session depends on the script while the ride runs.

### Who reads the script today (tracked files; history, reviews, reports and test results excluded)

- `.aai/templates/hooks/settings-hooks.json`: the four hook commands run
  `bash "$G" <gate>`. Unchanged.
- `.aai/scripts/merge-policy.mjs` `GUARD_PATHS` names the script; a lane
  merge of a PR touching a guard path is refused (`policy_touched`).
- `.aai/system/PROFILES.yaml`: `core`; the comment at line 171 already calls
  it "itself L3-protected".
- `tests/skills/test-aai-hooks-overlay.sh`: behavioural cases run the script
  (TEST-004 to 020, 1502, 1520, 1541, 1542, 1549, 1551, 1564); source reads:
  TEST-003 (names `pre-commit-checks.sh` and `state.mjs`), TEST-009 (awk of
  the `stop-nudge)` branch has no `exit 2`), TEST-574 (names `lane-gate.mjs`
  and `--sweep-check`). TEST-1502 compares the live script with
  `git show 64f2595f:<script>` byte for byte on stderr and exit code.
- `tests/skills/test-aai-merge-policy.sh`: TEST-1507 adds the script to the
  `GUARD_PATHS` closure; TEST-1571 awk-extracts `lane_check_merge_shape()`
  from the script.
- `tests/skills/lib/cd-subshell-leak-baseline.tsv`: 8 rows' worth of `cd`
  inside a substitution in the script.
- `tests/skills/suite-map.yaml`: the `aai-hooks-overlay` and
  `aai-merge-policy` rows glob the script.
- No `.aai/*.prompt.md`, no `.aai/AGENTS.md` and no fixture `cp` names the
  script.

### Coordination

- Ride 6 slice (b) (`release-publish-on-node`, worktree
  /Users/ales/Projects/aai-worktrees/release-publish-on-node) runs in
  parallel; it has an intake only at planning time. Expected overlaps,
  resolved by whichever branch merges second: the suite-map row-count pin
  in `test-aai-hygiene-pack.sh` test_090 (131 today; 132 after this ride;
  133 if both add a suite), `tests/skills/suite-weights.tsv` (appended
  rows), the RFC-0017 phase 5 sentence list, CHANGELOG `[unreleased]`
  headings, and TEST ids (this spec starts at TEST-3500 to leave room
  after TEST-3478). This ride edits no release file.
- PR #535 and the SPEC-0257 worktrees are read only for this ride.

## Decisions

### D-DRIFT. Every behaviour difference found

Each row with a behaviour is decided here and pinned by exactly one
`node:test` case in `tests/skills/lib/hook-gate.test.mjs` whose name begins
with the DG id. "Kept" means the module decides exactly as the script at
`c88cf708` and the case pins it.

| DG | Behaviour | Script at c88cf708 | Decision |
|---|---|---|---|
| DG-01 | Azure merge forms: a `node` call of `platform.mjs merge`, and `az repos pr update` carrying `--status completed` | allowed (exit 0) | merge commands: the article 7 deny (same bytes as for `gh pr merge`) unless `AAI_OPERATOR_MERGE=1` is in the hook environment; with it, gate 2b runs `lane-gate.mjs --sweep-check` with the number of `--pr` (platform.mjs) or `--id` (az) and denies on rc 5 with the gate 2b text; no number on the command denies with the D-OUT unidentified-PR text when node and lane-gate.mjs exist, else allows; a lane marker never unlocks an Azure form (the lane path keeps refusing anything but `gh pr merge`) |
| DG-02 | a merge, commit or state-dump command followed by thousands of lines while `pipefail` is inherited through an exported `SHELLOPTS` | merge and state-dump allowed (early-closing reader under pipefail) | decided on the whole command text in Node, no pipe: merge and state-dump deny, commit runs the checks, under every shell option |
| DG-03 | text that only names a merge command (`git commit -m "explain git merge handling"`, `echo gh pr merge 5`) | denied (exit 2) | kept: denied. A quote-aware parse would also let `bash -c 'gh pr merge 5'` through; a false deny costs a rephrase, a false allow costs article 7 |
| DG-04 | operator marker as a command prefix (`AAI_OPERATOR_MERGE=1 gh pr merge 42 --squash`) | denied | kept: only the hook environment's marker counts (TEST-1520). `fu-merge-gh-line-powershell` stays open; accepting a prefix is a policy decision for the owner |
| DG-05 | payload whose command is JSON-escaped (`"gh pr merge 5"`) | denied (node decodes the JSON) | kept: the pre-filter forwards every payload containing a backslash-u escape, so the module decodes and denies |
| DG-06 | non-ASCII whitespace between command words (`gh<U+00A0>pr merge 5`) | locale-dependent: denied under a UTF-8 locale, allowed under `LC_ALL=C` | denied under every locale: the module's whitespace class is explicit, ASCII white space plus U+00A0, U+1680, U+2000-U+200A, U+2028, U+2029, U+202F, U+205F and U+3000 (what a UTF-8 `[[:space:]]` matched), never JavaScript `\s`. Under `LC_ALL=C` bash does not split on these, so a command that never runs as a merge is denied (a false positive); with `AAI_OPERATOR_MERGE=1` a PR target such as `5<U+00A0>` is also split at the character, so gate 2b then checks the sweep record of PR 5 where the old gate under `LC_ALL=C` denied it as unresolvable (a new allow, bounded: the number is still sweep-checked and `gh` itself rejects the argument). Under a UTF-8 locale the decision equals the old one |
| DG-07 | Node absent; module file absent or empty | every gate allows, except a merge-shaped payload with a lane marker set in the environment (the no-node lane guard: article 7 deny plus `merge-policy: evaluator unavailable: node not found (the command could not be read)`) | kept for Node absent (the launcher keeps the guard, same bytes); a missing or empty module allows, except the same lane guard (the launcher tests the module with `-s`, so an empty file counts as missing) |
| DG-08 | `stop-nudge` | prints the nudge when an indented `status: in_progress` line exists and LOOP_TICKS.jsonl is absent or not newer than STATE.yaml; never exit 2 | kept, byte for byte |
| DG-09 | multi-line command text | `grep` matches line by line (`^` at each line start) | kept: every regex the module ports from a `grep` call runs with the `m` flag, and `MERGE_SEG` is the first match on any line, as `grep -o` and `head -1` gave |
| DG-10 | U+FEFF between command words (`gh<U+FEFF>pr merge 5`) | allowed (bash does not split on it) | kept: allowed under every locale, and the operator-marker path keeps its deny. The module's whitespace class leaves U+FEFF out (JavaScript `\s` would count it), so U+FEFF is never a separator, as in bash: `gh<U+FEFF>pr merge 5` is no merge command; with `AAI_OPERATOR_MERGE=1` the target `5<U+FEFF>` stays whole, `gh` cannot resolve it and the gate 2b text names it, byte for byte as the old gate did. Pinned by DG-10 and by untagged corpus rows |
| DG-11 | a no-break-space indent before `status: in_progress` in STATE.yaml | nudge under a UTF-8 locale, none under `LC_ALL=C` | nudge under every locale (the explicit whitespace class of DG-06); a reminder only, never a block |
| DG-12 | LOOP_TICKS.jsonl written in the same second as STATE.yaml, a fraction later | decided by the shell `-nt` test of the host bash (whole seconds on bash 3.2, nanoseconds on bash 4 and later) | compared at whole-second granularity, as bash 3.2 does: ticks in the same second as STATE.yaml do not count as newer, so the nudge stays; on a host with bash 4 or later the old script was silent there |

Count drifts with no behaviour (no test row): the follow-up's "30 gh sites"
(19 code lines measured) and the plan's "7 sites under pipefail" (9 sites,
no `pipefail` in the script); both are corrected in the intake.

### D-MOD. The module

`.aai/scripts/hook-gate.mjs`, Node stdlib only, no relative import (so the
`GUARD_PATHS` closure is the one file), no side effect on import (the CLI
runs only when the file is the entry point, through the realpath main guard
the other `.aai/scripts/*.mjs` CLIs use). It holds these literal constants,
which the mutations below target:

- `const GATES = ['commit', 'merge', 'state-dump', 'stop-nudge'];`
- `const ASCII_SPACE_ONLY = false;` (DG-06): every ported `[[:space:]]`
  becomes the explicit class of DG-06 (ASCII white space plus the non-ASCII
  members a UTF-8 `[[:space:]]` matches, never JavaScript `\s`), or
  `[ \t\n\v\f\r]` when this flag is true
- `const AZURE_COMPLETED = 'completed';`
- `const PLATFORM_SCRIPT = 'platform.mjs';`
- `const SWEEP_DENY_RC = 5;`
- `const TAIL_COMMIT = 25;` and `const TAIL_SWEEP = 5;` (the `tail -25` and
  `tail -5` of the script)
- the deny and nudge texts of D-OUT as string constants, byte for byte.

Exports:

- `parsePayload(text)`: `{ command, cwd }`, both strings, empty on any parse
  failure.
- `isMergeCommand(command)`: true for the script's `git ... merge` and
  `gh pr merge` regex and the DG-01 Azure forms.
- `mergeSegment(command)`: the first `gh pr merge` segment as the script's
  `grep -oE ... | head -1` gave it, or `''`.
- `checkMergeShape(segment)`: `{ ok: true }` or `{ ok: false, verdict }`, the
  port of `lane_check_merge_shape` (same verdict strings).
- `decide(gate, input, deps)`: `{ code, stderr }` with code 0 or 2.
  `input` is `{ payload, env, root }`; `deps` is `{ which(name),
  exists(path), readFile(path), mtimeMs(path), run(cmd, args, opts) }`, where
  `run` returns `{ status, stdout, stderr }`. The CLI wires `which` to a PATH
  scan, `run` to `spawnSync` with the working directories the script used
  (`cd "$ROOT"` becomes `cwd: root`), and the rest to `node:fs`.

CLI: `node hook-gate.mjs <gate>` reads the payload from stdin, takes the
root from `CLAUDE_PROJECT_DIR` (fallback `.`), writes the decision's stderr
and exits with its code. Any thrown error or unknown gate exits 0 with
nothing written (fail-open, as the script's header promises). Nothing is
ever written to stdout except the stop-nudge line (DG-08 keeps it on stdout,
byte for byte), which `decide` returns as an extra `stdout` field; the
module also exports `main` for the CLI seam case.

### D-OUT. Output contract

Every deny text, the `merge-policy: <verdict>` line, the lane verdict
strings, the gate 2b texts (`Merge denied: no valid post-open review sweep
record for PR <N> ...`, the two unresolvable-PR texts), the commit-gate
block text with the last 25 lines of the checks' output, the state-dump text
and the stop-nudge line are the script's bytes at `c88cf708`. The DG-01 deny
without a number reuses the script's "could not determine which PR this
merge command targets" text with the `Command:` line; no new deny text is
introduced.

### D-LAUNCH. The launcher

`.aai/scripts/claude-hook-gate.sh` keeps its name, mode, usage comment and
the four gate names. It:

1. reads the payload once (`PAYLOAD="$(cat 2>/dev/null || true)"`);
2. pre-filters with `case` on the raw payload, starting no process: `commit`
   continues only when the payload contains `commit`; `merge` only when it
   contains `merge` or `completed` (in any letter case, because `az` takes
   `--status Completed`); `state-dump` only when it contains
   `dump`; `stop-nudge` only when `$ROOT/docs/ai/STATE.yaml` exists; every
   gate also continues when the payload contains a backslash-u escape
   (DG-05); an unknown gate exits 0. Otherwise it exits 0.
3. when `node` is not on PATH: for `merge`, the no-node lane guard of the
   script (environment markers by `compgen -e`, the payload containing
   `merge`, the article 7 text plus the `merge-policy:` line, exit 2);
   otherwise exit 0;
4. when the module next to the launcher (`${BASH_SOURCE[0]%/*}/hook-gate.mjs`)
   is missing: the same lane guard for `merge`, otherwise exit 0;
5. otherwise runs `node "<dir>/hook-gate.mjs" "$GATE" <<<"$PAYLOAD"`, then
   `rc=$?`, the literal line `[ "$rc" -eq 2 ] && exit 2`, and `exit 0`.

`set -u` stays and `-e`/`pipefail` stay off. The launcher has no pipeline
(no `|` other than `||`), no `grep`, `sed`, `awk`, `head`, `tail` or `tr`,
and no `cd` inside a command substitution. Budget (the plan's method): at
most 70 code lines (an upper bound, not a pin).

### D-L3. Protected surfaces

- `docs/ai/docs-audit.yaml` and `.aai/templates/docs-audit.template.yaml`:
  `  - .aai/scripts/claude-hook-gate.sh` and `  - .aai/scripts/hook-gate.mjs`
  inserted after `  - .aai/scripts/pre-commit-checks.ps1`, in both files
  identically (`test-aai-sync-seed.sh` TEST-006 keeps them in lockstep).
- `.aai/workflow/WORKFLOW.md` "Protected surfaces": the guards bullet keeps its
  original line (the pre-commit-checks tests anchor it with `$`); a `hook gate:`
  bullet right after it names both files.
- `tests/skills/test-aai-hitl-propagation.sh` TEST-014 reads the first 8
  `  - ` lines of docs-audit.yaml (`qhead -8`); with 10 entries the window
  would drop `WORKFLOW.md` and `CONSTITUTION.md`. It reads the whole
  `protected_paths_l3` block instead.
- `.aai/scripts/merge-policy.mjs` `GUARD_PATHS` gains
  `.aai/scripts/hook-gate.mjs` next to the script; `test-aai-merge-policy.sh`
  TEST-1507 adds it to the closure.

### D-WIRE. Wiring, named up front

- `tests/skills/suite-map.yaml`: new row `aai-hook-gate` with globs
  `.aai/scripts/hook-gate.mjs`, `.aai/scripts/claude-hook-gate.sh`,
  `.aai/templates/hooks/**`, `.aai/scripts/merge-policy.mjs`,
  `.aai/scripts/lane-gate.mjs`, `.aai/workflow/WORKFLOW.md`,
  `docs/ai/docs-audit.yaml`, `.aai/templates/docs-audit.template.yaml`,
  `.aai/system/PROFILES.yaml`,
  `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`,
  `tests/skills/test-aai-hook-gate.sh`, `tests/skills/lib/hook-gate.test.mjs`,
  `tests/skills/lib/hook-gate-latency.mjs`,
  `tests/skills/lib/nested-suite-lint.mjs`,
  `tests/skills/lib/nested-suite-allowlist.tsv`, `tests/skills/suite-map.yaml`,
  `tests/skills/suite-weights.tsv`, and every other `tests/skills/lib/*` file
  the suite sources or reads. The `aai-hooks-overlay` and `aai-merge-policy`
  rows gain `.aai/scripts/hook-gate.mjs`.
- `tests/skills/suite-weights.tsv`:
  `# sample aai-hook-gate fallback unsampled (new suite of hook-gate-on-node; no successful observation)`
  and `aai-hook-gate<TAB>196` (the documented maximum).
- `test-aai-hygiene-pack.sh` `test_090_suite_map_pin`: the one literal
  row-count pin moves 131 to 132 (verified at planning: the only
  `-eq 131` in tests/skills). Ride 6b may add a suite too; the branch that
  merges second moves it again.
- Nested-suite lint: no new allowlist row; cross-suite calls in the new
  suite are selector form (`test-aai-hooks-overlay.sh test_1502_no_marker_bytes_equal_base`,
  `test-aai-merge-policy.sh test_1507_guard_paths_superset_of_import_closure`,
  `test-aai-merge-policy.sh test_1571_skill_pr_merge_command_passes_hook_shape`,
  `test-aai-sync-seed.sh test_audit_template_single_source` (TEST-006),
  `test-aai-hitl-propagation.sh test_014_no_protected_path_touched`,
  `test-aai-hygiene-pack.sh test_090_suite_map_pin`,
  `test-aai-hygiene-pack.sh test_129_mutation_gate_suite_registration`,
  `test-aai-layer-profiles.sh test_manifest_conformance`,
  `test-aai-expert-fetch.sh test_2624_inventory_matches_tree`).
- `tests/skills/lib/cd-subshell-leak-baseline.tsv`: re-recorded with
  `node .aai/scripts/check-cd-subshell-leak.mjs --record`; the
  `claude-hook-gate.sh` row (8) disappears, nothing else changes.
- `check-test-registration.mjs`: every `test_*` function is called.
- `.aai/system/PROFILES.yaml`: `  - .aai/scripts/hook-gate.mjs` under `core:`,
  right after `  - .aai/scripts/claude-hook-gate.sh`.
- `check-vendored-script-deps.mjs` exits 0 (no fixture copies the script or
  the module today; a new fixture that copies the launcher copies the
  module too).
- `.github/workflows/ps1-quality.yml`: unchanged (no `.ps1` in scope; the
  hook runs under bash on every platform, Git Bash on Windows).
- Prompt corpus: no `.aai/*.prompt.md` and no `.aai/AGENTS.md` change, so no
  prompt-diet ledger entry, no TEST-012 move, and no companion pin move in
  `test-aai-pr-preflight.sh`, `test-aai-legacy-migrations.sh` or
  `test-aai-retired-loop-runner.sh`. A Validation diff that shows a prompt
  change is a scope breach.
- Hooks overlay template `.aai/templates/hooks/settings-hooks.json`:
  unchanged byte for byte (consumer settings do not move).

### D-RFC. RFC-0017 and CHANGELOG

- Phase 5 row: one sentence after the tenth-slice sentence and before the
  remaining-scripts-plan sentence:
  `The eleventh slice [moved the Claude hook gate's decisions to Node](../issues/CHANGE-DRAFT-hook-gate-on-node.md): one module decides the four gates behind a bash pre-filter that starts no Node process for a command that cannot concern a gate, the Azure merge command is gated like gh pr merge, and the gate is an L3 protected surface.`
  Status stays `in progress`; frontmatter untouched. The allocator rewrites
  the link at merge; checks match only the suffix `hook-gate-on-node.md`.
  The inventory table is unchanged (the script has no twin and no row).
- After LOOP COMPLETE (ship convention, in the review scope, not a TEST
  row): CHANGELOG `## [unreleased] — refactor(hooks): the Claude hook gate decides in one Node module behind a bash pre-filter, and gates the Azure merge command`
  naming DG-01, DG-02, DG-06, the pre-filter, the L3 listing and the before
  and after code lines.

### D-FU. Follow-ups

- Closed at ride close (after the last ledger-touching commit, before the
  final sweep): `fu-platform-adapter-hook-gate`, resolved by
  `hook-gate-on-node` (DG-01).
- Left open, with reasons: `fu-merge-gh-line-powershell` (DG-04, an owner
  policy decision), `fu-platform-adapter-merge-policy` and
  `fu-platform-adapter-lane-gate` (the evaluators the gate calls still use
  `gh`; this ride changes neither), `fu-hooks-merge-group-level-keys` (the
  bootstrap overlay merge, not the gate), `fu-constitution-art7-directed-merge`
  (constitution wording).
- None filed by planning.

### D-SUITE

One new suite `aai-hook-gate` (`tests/skills/test-aai-hook-gate.sh`) holds
every row, with `run_node_tests` (a pattern that matches no passing case
fails) and `need_tool` (an absent tool fails on CI, a named SKIP-CASE
locally). Every fixture is a fresh temp git repository with a local
identity; payloads are written to a file and redirected in (no live pipe,
the TEST-004 lesson). Cases that need `gh` put a stub first on PATH that
answers the `pr view` shapes the fixture needs and logs its argv; no case
calls a real `gh`, `az` or network. The baseline script is read with
`git show c88cf708:.aai/scripts/claude-hook-gate.sh` (full history, as
TEST-1502 already requires). Node spawns are counted with a `node` wrapper
first on PATH that appends one line to a log and execs the real Node. The
suite and the `node:test` file each finish in under 90 seconds locally.

### D-MEASURE. Latency cases

`tests/skills/lib/hook-gate-latency.mjs` runs both scripts with
`spawnSync('bash', [script, gate])`, the payload on stdin, in one fixture
with this repository's layer copied in, alternating new and baseline runs
per iteration. Pre-filtered cases: `commit`, `merge` and `state-dump` with
`ls -la docs/specs`, `commit` with `git status --short`, `merge` with
`git log --oneline -5`. Delegated cases: `merge` with `git merge feature-x`
(deny, no external tool), `state-dump` with a STATE.yaml `yaml.dump`
command, `stop-nudge` with an in-progress STATE and no tick log. The
reference-host bounds (p95 at most 10 ms pre-filtered, 50 ms delegated) are
asserted only when `AAI_HOOK_GATE_REFERENCE_HOST=1` is set (Validation sets
it on the planning host and records the output); the ratio assertions run
everywhere.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01, Spec-AC-02 and Spec-AC-09.
- Intake AC-002 maps to Spec-AC-03.
- Intake AC-003 maps to Spec-AC-04, Spec-AC-05 and Spec-AC-06.
- Intake AC-004 maps to Spec-AC-07 and Spec-AC-08.
- Intake AC-005 maps to Spec-AC-12.
- Intake AC-006 maps to Spec-AC-10, Spec-AC-11, Spec-AC-13 and Spec-AC-14.

## Constitution deviations

None. Article 7 (operator-only merge): the gate denies one more merge form
(DG-01) and allows nothing it denied before; DG-04 keeps the marker rule.
Article 6 (single-writer STATE): the state-dump gate is unchanged in what it
denies and decides on the whole text (DG-02). Article 4 (degrade and
report): the gate stays fail-open on its own errors, as its header states,
with the lane-path denials kept. Article 2 (simplicity): one module, no new
dependency, no new flag, and the overlay template is untouched.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | Importing .aai/scripts/hook-gate.mjs in a child node with a temp cwd writes nothing to stdout, stderr or the cwd and exports parsePayload, isMergeCommand, mergeSegment, checkMergeShape and decide; the CLI given an unknown gate, malformed JSON, or a deps.run that throws exits 0 with empty stdout and stderr; no CLI run writes stdout except the stop-nudge line. | done | docs/ai/tdd/hook-gate-on-node/green/run1-green.log; docs/ai/tdd/spec-hook-gate-on-node/mutation-TEST-3500.txt | — | — |
| Spec-AC-02 | WHEN the launcher and the c88cf708 script each run every corpus row (at least 60 rows over the four gates: allow, deny, lane path with a stub gh and the real merge-policy.mjs, gate 2b with and without a sweep record, commit with a passing and a failing checks script, multi-line commands, stop-nudge fixtures), the system SHALL give the same exit code and the same stderr bytes on every row not tagged with a DG id whose decision changes it. | done | docs/ai/tdd/hook-gate-on-node/green/run1-green.log; docs/ai/tdd/spec-hook-gate-on-node/mutation-TEST-3501.txt | — | — |
| Spec-AC-03 | DG-01: each Azure form exits 2 with the article 7 text without AAI_OPERATOR_MERGE; with the marker and no sweep record it exits 2 with the gate 2b text naming the --pr or --id number; with a valid record it exits 0; with no number it exits 2 with the unidentified-PR text, and 0 when lane-gate.mjs is absent; with only a lane marker it exits 2 with a merge-policy line. | done | docs/ai/tdd/hook-gate-on-node/green/run2-green.log; docs/ai/tdd/spec-hook-gate-on-node/mutation-TEST-3503.txt | — | — |
| Spec-AC-04 | DG-02: with SHELLOPTS carrying pipefail exported, the launcher run on a merge command and a STATE.yaml yaml.dump command each followed by 8000 lines exits 2, and a commit command followed by 8000 lines runs a failing checks script and exits 2; the c88cf708 script exits 0 on the merge and state-dump cases (the RED). | done | docs/ai/tdd/hook-gate-on-node/green/run2-green.log; docs/ai/tdd/spec-hook-gate-on-node/mutation-TEST-3504.txt | — | — |
| Spec-AC-05 | The node:test cases DG-03, DG-05, DG-06, DG-07, DG-08 and DG-09 pass, each asserting its D-DRIFT decision as exit code and exact stderr through decide, and DG-07 also through the launcher with a PATH holding no node and with the module renamed away. | done | docs/ai/tdd/hook-gate-on-node/green/run2-green.log; docs/ai/tdd/spec-hook-gate-on-node/mutation-TEST-3505.txt | — | — |
| Spec-AC-06 | Every DG id with a behaviour in the D-DRIFT table begins exactly one node:test case name in tests/skills/lib/hook-gate.test.mjs, and the test file names no DG id the table lacks; DG-04 is pinned by a case asserting exit 2 for the prefix form. | done | docs/ai/tdd/hook-gate-on-node/green/run1-green.log; docs/ai/tdd/spec-hook-gate-on-node/mutation-TEST-3502.txt | — | — |
| Spec-AC-07 | WHEN the launcher runs a payload that lacks its gate's trigger substring and any backslash-u escape, the system SHALL exit 0 with no node spawn in the counting wrapper's log; a delegated payload decided without an external tool spawns node exactly once; for every corpus row the pre-filter skips, decide on the same input returns code 0. | done | docs/ai/tdd/hook-gate-on-node/green/run3-green.log; docs/ai/tdd/spec-hook-gate-on-node/mutation-TEST-3506.txt | — | — |
| Spec-AC-08 | The latency script measures the launcher and the c88cf708 script interleaved in one run (n at least 40 per case) on the D-MEASURE cases and prints p50 and p95 per case; the suite asserts each pre-filtered case p50 is at most 0.35 times the baseline p50 and each delegated case p50 is at most 1.15 times the baseline p50 plus 3 ms; on the reference host the recorded p95 is at most 10 ms pre-filtered and at most 50 ms delegated. | done | docs/ai/tdd/hook-gate-on-node/green/run3-green.log; docs/ai/tdd/spec-hook-gate-on-node/mutation-TEST-3507.txt | — | — |
| Spec-AC-09 | claude-hook-gate.sh has at most 70 code lines by the plan's method, keeps set -u without -e or pipefail, holds no pipe other than the OR operator, no grep, sed, awk, head, tail or tr call and no cd inside a command substitution, names hook-gate.mjs, and maps module exit 2 to 2 and every other exit to 0, except that a module exit other than 0 and 2 with a lane marker set and a merge-shaped payload runs the lane guard (exit 2, the no-node bytes). | done | docs/ai/tdd/hook-gate-on-node/green/run3-green.log; docs/ai/tdd/spec-hook-gate-on-node/mutation-TEST-3508.txt | — | — |
| Spec-AC-10 | The existing callers keep working: test-aai-hooks-overlay.sh and test-aai-merge-policy.sh exit 0 with TEST-1502 unchanged; TEST-003, TEST-009 and TEST-574 read the module where they read the script; TEST-1571 checks the SKILL_PR command with checkMergeShape of the module; test-aai-lightweight-lane.sh exits 0. | done | docs/ai/tdd/hook-gate-on-node/green/run4-green.log; docs/ai/tdd/spec-hook-gate-on-node/mutation-TEST-3509.txt | — | — |
| Spec-AC-11 | GUARD_PATHS of merge-policy.mjs names hook-gate.mjs; TEST-1507 includes it in the closure and passes; classifyFiles over a file list holding only hook-gate.mjs returns denyReason policy_touched. | done | docs/ai/tdd/hook-gate-on-node/green/run4-green.log; docs/ai/tdd/spec-hook-gate-on-node/mutation-TEST-3510.txt | — | — |
| Spec-AC-12 | Both gate files are listed after pre-commit-checks.ps1 in docs-audit.yaml and its template and in a WORKFLOW.md hook gate bullet right after the guards bullet, which stays byte-identical to its c88cf708 text; sync-seed TEST-006 and the pre-commit-checks TEST-3456 pass; hitl-propagation TEST-014 reads every protected entry with no first-8 window and passes; select-suites answers FULL_RUN reason=protected-l3 for each gate file. | done | docs/ai/tdd/hook-gate-on-node/green/run4-green.log; docs/ai/tdd/spec-hook-gate-on-node/mutation-TEST-3511.txt | — | — |
| Spec-AC-13 | Wiring per D-WIRE: select-suites selects aai-hook-gate for the module and the launcher (read in a scratch root whose docs-audit.yaml lists neither, because the real tree answers FULL_RUN protected-l3 for L3 files) and for the three test files, and aai-hooks-overlay and aai-merge-policy for the module; the weights row is 196 with its fallback line; hygiene test_090 pins 132 and test_129 pass; nested-suite lint, check-cd-subshell-leak, check-test-registration and check-vendored-script-deps exit 0; PROFILES lists the module once under core and layer-profiles test_manifest_conformance passes. | done | docs/ai/tdd/hook-gate-on-node/green/run5-green.log; docs/ai/tdd/spec-hook-gate-on-node/mutation-TEST-3512.txt | — | — |
| Spec-AC-14 | WHEN aai-sync.sh --profile core installs into a scratch git target whose path holds a space, the target SHALL hold the launcher and the module, its launcher SHALL deny gh pr merge 5 with exit 2 and allow ls with exit 0 and no node spawn; the suite prints before 341, the launcher's after code lines, the removed lines and the module's code lines; the RFC-0017 phase 5 row holds the D-RFC sentence once and expert-fetch test_2624 passes. | done | docs/ai/tdd/hook-gate-on-node/green/run5-green.log; docs/ai/tdd/spec-hook-gate-on-node/mutation-TEST-3513.txt; docs/ai/tdd/spec-hook-gate-on-node/mutation-TEST-3514.txt | — | — |

## Implementation plan

TDD in five runs of about three Spec-ACs; each run stores RED under
`docs/ai/tdd/hook-gate-on-node/red/` before its change, GREEN under
`green/`, and one mutation record per row (`node .aai/scripts/mutation-run.mjs`)
before the run's hand-off.

1. Run 1, Spec-AC-01, 02, 06: the suite skeleton, the `node:test` file with
   the seam case and all DG case names, the corpus and the differential
   harness, then the module (D-MOD, D-OUT) and the launcher's delegation.
2. Run 2, Spec-AC-03, 04, 05: DG-01 (Azure), DG-02 (inherited pipefail),
   the kept-decision cases.
3. Run 3, Spec-AC-07, 08, 09: the pre-filter (D-LAUNCH), the spawn
   counter, the latency script, the launcher budget.
4. Run 4, Spec-AC-10, 11, 12: the hooks-overlay and merge-policy source
   reads, GUARD_PATHS, the L3 lists and TEST-014.
5. Run 5, Spec-AC-13, 14: D-WIRE, the scratch install, the measurement,
   D-RFC; then the CHANGELOG entry after LOOP COMPLETE.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3500 | Spec-AC-01 | unit | tests/skills/test-aai-hook-gate.sh | test_3500_seam runs run_node_tests TEST-3500 on tests/skills/lib/hook-gate.test.mjs: an import in a child node with a temp cwd writes nothing and exposes the five exports; the CLI on an unknown gate, on malformed JSON and with a run fake that throws exits 0 with empty stdout and stderr | `sed:s/const GATES = \['commit', 'merge', 'state-dump', 'stop-nudge'\];/const GATES = ['commit', 'merge', 'state-dump', 'stop-nudge', 'bogus'];/` on .aai/scripts/hook-gate.mjs | green |
| TEST-3501 | Spec-AC-02 | integration | tests/skills/test-aai-hook-gate.sh | test_3501_parity builds the D-SUITE fixture, reads the c88cf708 script with git show, runs it and the launcher on every corpus row with identical env, cwd and payload files, and compares exit codes and stderr bytes; rows tagged with a changing DG id are skipped by name, and the case fails when fewer than 60 rows were compared; the corpus holds NUL-inside-the-command rows for the merge, commit and state-dump gates, compared untagged | `sed:s/the agent never merges;/the agent never merges./` on .aai/scripts/hook-gate.mjs | green |
| TEST-3502 | Spec-AC-06 | inspection | tests/skills/test-aai-hook-gate.sh | test_3502_drift_coverage reads the DG ids of the D-DRIFT table of this spec (found by its id spec-hook-gate-on-node under docs/specs) and the test names of tests/skills/lib/hook-gate.test.mjs; each behaviour id begins exactly one test name and no test name begins with an id the table lacks; positive control: a scratch copy with DG-06 renamed is reported | `sed:s/'DG-06 /'DG-60 /` on tests/skills/lib/hook-gate.test.mjs | green |
| TEST-3503 | Spec-AC-03 | integration | tests/skills/test-aai-hook-gate.sh | test_3503_azure_forms runs run_node_tests TEST-3503 and the launcher on the platform.mjs merge and az repos pr update forms: no marker gives 2 and the article 7 text; marker and no pr_sweep record gives 2 and the gate 2b text naming 7; a valid record gives 0; no number gives 2 and the unidentified text, 0 with lane-gate.mjs renamed away; a lane marker alone gives 2 with a merge-policy line; the c88cf708 script gives 0 on the no-marker rows (RED) | `sed:s/const AZURE_COMPLETED = 'completed';/const AZURE_COMPLETED = 'complete';/` on .aai/scripts/hook-gate.mjs | green |
| TEST-3504 | Spec-AC-04 | integration | tests/skills/test-aai-hook-gate.sh | test_3504_inherited_pipefail exports SHELLOPTS with pipefail and runs the launcher on the three 8001-line commands (merge 2, state-dump 2, commit with a failing checks script 2) and the c88cf708 script on the merge and state-dump ones (0, recorded as the baseline observation) | `patch:docs/ai/tdd/spec-hook-gate-on-node/mutation-TEST-3504.patch` on .aai/scripts/hook-gate.mjs | green |
| TEST-3505 | Spec-AC-05 | unit | tests/skills/test-aai-hook-gate.sh | test_3505_kept_decisions runs run_node_tests TEST-3505: DG-03 (two text-only commands deny), DG-05 (escaped JSON denies), DG-06 (U+00A0 between words denies), DG-07 (decide is not reached: the launcher with no node on PATH and with the module renamed allows ls and a merge, and denies a merge with a lane marker in the env with the no-node text), DG-08 (nudge line byte for byte, never 2), DG-09 (a merge on the third line is found and MERGE_SEG is that line's segment), DG-10 (U+FEFF between words denies), DG-11 (no-break-space indent nudges under LC_ALL=C), DG-12 (ticks in the same second as STATE do not silence the nudge) | `sed:s/const ASCII_SPACE_ONLY = false;/const ASCII_SPACE_ONLY = true;/` on .aai/scripts/hook-gate.mjs | green |
| TEST-3506 | Spec-AC-07 | integration | tests/skills/test-aai-hook-gate.sh | test_3506_prefilter puts the counting node wrapper first on PATH; ls, git status and git log payloads on commit, merge and state-dump leave the log empty with exit 0; git merge feature-x on merge adds exactly one line; then runs run_node_tests TEST-3506, which checks for every corpus row the pre-filter would skip that decide returns code 0 | `sed:s/\*merge\*/*mergx*/` on .aai/scripts/claude-hook-gate.sh | green |
| TEST-3507 | Spec-AC-08 | integration | tests/skills/test-aai-hook-gate.sh | test_3507_latency runs node tests/skills/lib/hook-gate-latency.mjs with the c88cf708 script and the launcher, n=40, prints the D-MEASURE table and fails when a ratio bound of Spec-AC-08 is exceeded on two measurements in a row (a failing ratio is measured once more); with AAI_HOOK_GATE_REFERENCE_HOST=1 also checks the absolute p95 bounds | `patch:docs/ai/tdd/spec-hook-gate-on-node/mutation-TEST-3507.patch` on .aai/scripts/claude-hook-gate.sh | green |
| TEST-3508 | Spec-AC-09 | inspection | tests/skills/test-aai-hook-gate.sh | test_3508_launcher_shape counts code lines with grep -cvE on the hash comment and blank pattern under bash with /usr/bin/grep when present (at most 70), requires set -u, no set -e and no pipefail, no single pipe after removing the OR operator, none of the seven tools as a command word, zero lines from check-cd-subshell-leak for the file, the module name, and runs the launcher with a fake module that exits 2, 1 and 3 (2, 0, 0), and with exit 1, exit 3, a syntax error and an unreadable module under a lane marker (merge-shaped payload 2 with the lane guard text, other payload 0, no marker 0) | `sed:s/\[ "\$rc" -eq 2 \] \&\& exit 2/[ "$rc" -ne 0 ] \&\& exit 2/` on .aai/scripts/claude-hook-gate.sh | green |
| TEST-3509 | Spec-AC-10 | integration | tests/skills/test-aai-hook-gate.sh | test_3509_callers runs the hooks-overlay selectors test_003_script_conformance, test_009_stop_nudge, test_016_merge_gate_sweep_check and test_1502_no_marker_bytes_equal_base, and the merge-policy test_1571_skill_pr_merge_command_passes_hook_shape selector (exit 0 each); requires TEST-003, TEST-009 and TEST-574 to name hook-gate.mjs and TEST-1571 to import checkMergeShape instead of awk-extracting the script. The full hooks-overlay, merge-policy and lightweight-lane runs are Verification steps | `sed:s/export function checkMergeShape/function checkMergeShape/` on .aai/scripts/hook-gate.mjs | green |
| TEST-3510 | Spec-AC-11 | integration | tests/skills/test-aai-hook-gate.sh | test_3510_guard_paths imports GUARD_PATHS from merge-policy.mjs and requires .aai/scripts/hook-gate.mjs; runs the merge-policy TEST-1507 selector (exit 0); calls the exported classifyFiles of merge-policy.mjs with a file list holding only .aai/scripts/hook-gate.mjs and requires denyReason policy_touched | `sed:s/  '.aai\/scripts\/hook-gate.mjs',//` on .aai/scripts/merge-policy.mjs | green |
| TEST-3511 | Spec-AC-12 | inspection | tests/skills/test-aai-hook-gate.sh | test_3511_protected_lists requires both files right after pre-commit-checks.ps1 in the protected_paths_l3 block of docs-audit.yaml and of the template, and in the WORKFLOW.md hook gate bullet right after the guards bullet; runs the sync-seed test_audit_template_single_source and hitl-propagation test_014_no_protected_path_touched selectors (exit 0); requires no qhead -8 in TEST-014; pipes each gate file to select-suites.mjs --files-from - and requires FULL_RUN reason=protected-l3 | `sed:s/  - .aai\/scripts\/hook-gate.mjs//` on docs/ai/docs-audit.yaml | green |
| TEST-3512 | Spec-AC-13 | inspection | tests/skills/test-aai-hook-gate.sh | test_3512_wiring pipes the module and the launcher (in a scratch root whose docs-audit.yaml lists neither, since the real tree answers FULL_RUN protected-l3) and the three test files to select-suites.mjs --files-from - and requires aai-hook-gate, and the module also aai-hooks-overlay and aai-merge-policy; requires one weights row at 196 with its fallback line; runs hygiene-pack test_090 and test_129 selectors; runs nested-suite-lint with its allowlist, check-cd-subshell-leak, check-test-registration and check-vendored-script-deps (exit 0); requires the module once under core in PROFILES and runs layer-profiles test_manifest_conformance | `sed:s/      - .aai\/scripts\/hook-gate.mjs/      - .aai\/scripts\/hook-gate-gone.mjs/` on tests/skills/suite-map.yaml | green |
| TEST-3513 | Spec-AC-14 | e2e | tests/skills/test-aai-hook-gate.sh | test_3513_downstream_install runs aai-sync.sh --profile core into a scratch git target named with a space, requires the launcher and the module there, runs the target's own launcher with CLAUDE_PROJECT_DIR set to the target on a gh pr merge 5 payload (2, article 7 text) and an ls payload (0, counting wrapper log empty) | `sed:s/  - \.aai\/scripts\/hook-gate\.mjs/  - .aai\/scripts\/hook-gate-gone.mjs/` on .aai/system/PROFILES.yaml | green |
| TEST-3514 | Spec-AC-14 | inspection | tests/skills/test-aai-hook-gate.sh | test_3514_lines_and_rfc prints before 341, the launcher's code lines, the removed lines and the module's code lines (the module counted with the double-slash comment pattern); runs expert-fetch test_2624_inventory_matches_tree (exit 0); requires the phase 5 row to keep status in progress and hold the D-RFC sentence exactly once with a link ending hook-gate-on-node.md | `sed:s/The eleventh slice \[moved the Claude hook gate's decisions to Node\]/The eleventh slice [moved the Claude hook gate]/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |

Test counts by type: unit 2, integration 7, inspection 4, e2e 1 (15 rows;
the DG cases are `node:test` cases inside TEST-3503 to TEST-3506).

Seams crossed (Principle 2): the module against the script it replaces
(TEST-3501 compares exit codes and stderr bytes with the base script on one
corpus, TEST-1502 keeps its own older base); the module and the real
`merge-policy.mjs --check` and `lane-gate.mjs --sweep-check` it spawns
(TEST-3501 lane and gate 2b rows, TEST-3503); the commit gate and a real
checks script (TEST-3501, TEST-3504); the launcher under an inherited shell
option (TEST-3504); the launcher and the Node process boundary (TEST-3506,
TEST-3507); `GUARD_PATHS` read by the lane check (TEST-3510); the protected
lists read by select-suites, sync-seed and TEST-014 (TEST-3511);
select-suites, the hygiene pins, the nested-suite lint, the cd ratchet and
the registration check reading the new suite (TEST-3512); aai-sync's core
profile copy to a target's own launcher (TEST-3513); the RFC inventory read
by SPEC-0249's check (TEST-3514). The hooks overlay JSON calling the
launcher is crossed by hooks-overlay TEST-004 (unchanged, Verification).

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hook-gate.sh`
  exits 0 (15 rows), plus the touched and selected suites, each run the
  same way: test-aai-hooks-overlay.sh, test-aai-merge-policy.sh,
  test-aai-lightweight-lane.sh, test-aai-hitl-propagation.sh,
  test-aai-sync-seed.sh, test-aai-hygiene-pack.sh, test-aai-layer-profiles.sh,
  test-aai-expert-fetch.sh, test-aai-suite-select.sh. L3: Validation runs
  the full sweep with `AAI_TEST_TIMEOUT=3600`.
- `env -u AAI_ROLE node --test tests/skills/lib/hook-gate.test.mjs` exits 0
  with at least 12 passing cases (one per DG behaviour row plus the seam
  and pre-filter cases).
- `AAI_HOOK_GATE_REFERENCE_HOST=1 node tests/skills/lib/hook-gate-latency.mjs ...`
  on the planning host: the p50/p95 table recorded in the validation report
  with the before (c88cf708) and after values.
- No prompt change: `git diff --stat main -- '.aai/*.prompt.md' .aai/AGENTS.md`
  prints nothing; the overlay template is unchanged:
  `git diff --stat main -- .aai/templates/hooks/settings-hooks.json` prints
  nothing (both recorded in the validation report, not pinned by a test).
- Not edited (coordination): `git diff --stat main -- .aai/scripts/aai-release.sh .aai/scripts/aai-release.ps1 .aai/scripts/release-cut.mjs .aai/scripts/release-finish.mjs`
  prints nothing.
- `node .aai/scripts/spec-lint.mjs --path <this spec>` and
  `node .aai/scripts/mutation-gate.mjs` for this spec pass.

## Evidence contract

ref_id `hook-gate-on-node`; RED, GREEN and mutation evidence under
`docs/ai/tdd/hook-gate-on-node/` and `docs/ai/tdd/spec-hook-gate-on-node/`
(gitignored); each AC row's Evidence names its green log and mutation
record; the validation report and review verdict under `docs/ai/reports/`
and `docs/ai/reviews/`.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Residual risks

- The latency ratios depend on the host's load; the runs are interleaved
  so load hits both scripts alike, and the absolute bounds are asserted only
  on the reference host. A loaded CI runner can still flake TEST-3507; a
  rerun, not a code change, is the first response.
- The differential corpus covers the shapes the existing suites and this
  spec name; a command shape outside it can still differ. The `m`-flag and
  whitespace rules (DG-06, DG-09) close the two systematic differences
  found between `grep` and JavaScript regexes.
- DG-06 makes the gate deny a command it allowed under `LC_ALL=C`, and with
  `AAI_OPERATOR_MERGE=1` lets a PR target carrying a non-ASCII separator reach
  the sweep check of the number before it (a bounded new allow under
  `LC_ALL=C` only; the number is still checked and `gh` rejects the argument).
  DG-10 keeps the old decisions, U+FEFF included. DG-11 and DG-12 can only add a reminder.
- The gate guards Claude Code sessions only where the overlay is installed;
  Codex and Gemini sessions are not gated (unchanged; the `.aai` scripts
  remain the cross-platform floor).
- DG-04 leaves `/aai-merge`'s printed `AAI_OPERATOR_MERGE=1 gh pr merge`
  line denied under the overlay unless the marker is in the session
  environment (unchanged; `fu-merge-gh-line-powershell`).
- The umbrella RFC-0017 stays open across this child-phase delivery; the
  close may trip the docs-audit false-open on the parent, suppressed with a
  fresh doc_lifecycle event as in earlier slices.

Registry items closed by this scope:
- fu-platform-adapter-hook-gate (DG-01)

Items this scope leaves open, with reasons: fu-merge-gh-line-powershell
(DG-04, owner policy), fu-platform-adapter-merge-policy and
fu-platform-adapter-lane-gate (the evaluators keep calling gh),
fu-hooks-merge-group-level-keys (overlay merge, not the gate),
fu-constitution-art7-directed-merge (constitution wording),
fu-azure-live-proof-on-adoption (a live Azure round trip is not possible
here).
