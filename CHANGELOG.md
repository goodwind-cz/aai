# Changelog

All notable changes to AAI are documented in this file. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). AAI does not yet
follow semantic versioning — entries are grouped by date or release event.

For target projects: run `/aai-update` to pull the latest layer. After
updating, run `/aai-doctor` to surface any migration actions specific to
your project (for example, the STATE-to-local migration introduced in
RFC-0001).

## [unreleased]

## [unreleased] — feat(doctor): Windows self-test, environment and agent-CLI probe (CHANGE-0135) [L1]

- `/aai-doctor` (`.aai/scripts/aai-doctor.mjs`) gains three new categories:
  `CAT-14` Windows Self-Test runs the REAL `.aai/scripts/aai-run-tests.ps1`
  wrapper three times (success / timeout / induced spawn failure) on the
  machine `/aai-doctor` runs on, `CAT-15` Windows Environment reports
  case-colliding env var groups, PowerShell engines, Git Bash candidates and
  the WSL tri-state, and `CAT-16` Agent CLI Probe reports `claude`/`codex`/
  `gemini` presence and verbatim version, with the four
  `SUBAGENT_PROTOCOL` capability fields honestly reported `UNKNOWN` (never
  inferred from an installed CLI's name).
- New `.aai/scripts/aai-win-selftest.ps1` dot-sources the existing
  `.aai/scripts/aai-run-tests.ps1` for its probe functions (the wrapper's
  own header blesses dot-sourcing to define-without-run) — never a second
  implementation of WSL/Git-Bash resolution or the env-collision rule.
  CAT-14's induced spawn-failure arm doctors only a throwaway CHILD
  process's environment (a temp-directory decoy), never the host's real Git
  installation.
- `--strict` flag: exits 1 when any category is WARN or FAIL (0 when every
  category is PASS or SKIP); the pre-existing exit map (0 clean/WARN-only,
  1 on any FAIL) is unchanged without it. Both new categories cap at WARN
  and can never emit FAIL.
- `tests/skills/aai-win-dispatch.Tests.ps1` gains three new Pester contexts
  for the probe script's pure functions; `tests/skills/test-aai-doctor.sh`
  gains ten new cases (SKIP branch, structural REUSE/arm pins, fake-CLI and
  empty-PATH fixtures, output-shape growth, exit matrix, zero-network pin,
  hygiene set, documentation pin). `.aai/system/PROFILES.yaml` classifies
  the new script under `core`; `tests/skills/suite-map.yaml`'s `aai-doctor`
  row widens to cover it.
- New `docs/product/aai-doctor.md`; `docs/USER_GUIDE.md` documents the
  three new categories, `--strict`, and the UNKNOWN capability reporting.
- Spec-AC-01 (the Windows self-test itself) stays `planned` until the named
  `ps1-quality / windows-5_1` job has actually run green on this scope's PR
  with all three arms PASS — recorded honestly, not claimed.

- `.github/workflows/ps1-quality.yml` `windows-5_1` job gains a per-engine
  Pester 5 install-if-missing step (Windows PowerShell 5.1's TLS 1.2 + NuGet
  provider bootstrap, since 5.1 ships Pester 3.4.0 as a system module — a
  bare `Import-Module Pester -MinimumVersion 5.0` now fails loudly below
  major 5 rather than silently binding to it) and two `Invoke-Pester` steps —
  one under `shell: powershell`, one under `shell: pwsh` — discovering the
  `tests/skills` directory (not two hardcoded files), each printing
  `AAI-PESTER-VERSION`/`AAI-PESTER-ELAPSED`, asserting a 600s hard ceiling,
  and carrying `timeout-minutes: 15`. `workflow_dispatch` fast-iteration path
  (`gh workflow run ps1-quality.yml`) documented in the workflow header and
  `docs/product/windows-test-wrapper.md`.
- New `tests/skills/lib/pester-host-skip.ps1`: a shared, discovery-time
  `Test-IsWindowsHostFor` predicate (edition-aware — `$IsWindows` is
  undefined under Windows PowerShell 5.1), dot-sourced at file scope by both
  `.Tests.ps1` files so a `-Skip:` expression can read it during discovery.
  Four genuinely Windows-fragile tests now carry a named `PosixOnly` skip
  reason; CHANGE-0133 TEST-001 (PATH-collision union) is made portable
  instead of skipped ([IO.Path]::PathSeparator fixtures, not a hardcoded
  `:`). `tests/skills/test-ps1-quality.sh`'s POSIX Pester run now fails when
  `SkippedCount` is non-zero — mutation-proofed against a forced-true
  predicate.
- `.aai/scripts/aai-reap-tests.ps1` `Test-WslUsable` replaces its bare
  `wsl.exe -e true` exit-0 existence probe (the same pre-fix defect
  CHANGE-0133 closed in `aai-run-tests.ps1` — vacuously satisfied by a
  distro-less `wsl.exe`) with the identical functional sentinel probe,
  copied file-local (`Start-WslProbeProcess` + `Wait-ProcessWithTimeout`);
  a cross-file Pester pin keeps both dispatchers' sentinel value and probe
  argv from drifting apart again. TDD RED->GREEN (`docs/ai/tdd/`).
- `tests/skills/suite-map.yaml` `aai-win-fallback` entry widened to the
  workflow file, both `.Tests.ps1` files and `tests/skills/lib/**`, so a
  workflow-only or test-only edit still selects the suite that pins it.
- `docs/TECHNOLOGY.md` no longer claims Pester runs on Linux only.
- Spec-AC-01/Spec-AC-02 stay `planned` until the named `windows-5_1` job has
  actually run green on this scope's PR — recorded honestly, not claimed.

## [unreleased] — fix(scripts): aai-run-tests.ps1 canonicalizes Path/PATH before every spawn, never fakes 124 (CHANGE-0133) [L2]

- `.aai/scripts/aai-run-tests.ps1`: new `Get-CanonicalEnvironmentMap` /
  `Set-CanonicalProcessEnvironment` collapse any OrdinalIgnoreCase-duplicate
  environment key (e.g. both `Path` and `PATH`) to one canonical survivor,
  applied once per dispatch before the WSL probe and before either launch
  primitive — closing the field defect where that duplicate crashed
  `Start-Process` and the wrapper silently reported a fake timeout (124) for
  a command that never ran. `Invoke-ViaGitBash` and `Invoke-ViaWsl` now wrap
  every spawn in `try`/`catch`/`finally`: a genuine spawn failure exits the
  new **125** (never 124), writes one `AAI-SPAWN-ERROR: [<branch>] <message>`
  line naming the real exception and the failing branch, and reaps a live
  process object if one exists — a spawn that produced no object never
  reaches `Stop-ProcessTree`. 124 keeps its exact prior meaning (a process
  that RAN and was killed at the deadline).
- `.aai/scripts/aai-run-tests.sh`: header documents the 124-vs-125 contract;
  one root-caused one-line fix in the perl `setsid`-fallback launch path so a
  non-executable file reports the shell's real 126 instead of being
  collapsed into 127 alongside a missing command (found via the new
  characterization guard, `tests/skills/test-aai-run-tests.sh` TEST-024,
  mutation-proofed against a stub that always returns 124).
- `.github/workflows/ps1-quality.yml` `windows-5_1` job gains a real
  end-to-end smoke step under both Windows PowerShell 5.1 and pwsh 7 —
  the first real-Windows execution of this dispatcher.
- New product doc `docs/product/windows-test-wrapper.md`; intake gains
  `capability: windows-test-wrapper`; `docs/TECHNOLOGY.md` and
  `docs/USER_GUIDE.md` document the 124/125/78 exit-code contract.
- Field fix from the first real Windows CI run (PR #247, run 31603532721):
  `Test-WslUsable` is now a REAL functional probe — it spawns `wsl.exe -e sh
  -c 'exit <sentinel>'` via the new mockable `Start-WslProbeProcess` and
  requires that exact sentinel exit code back, closing the hole where
  windows-latest's wsl.exe with zero installed distributions prints "Windows
  Subsystem for Linux has no installed distributions." and exits 0 —
  indistinguishable from real success under the prior bare
  `ExitCode -eq 0` check, which wrongly routed into WSL. Any non-sentinel
  result (no distro, timeout, error) now correctly falls through to Git Bash.
  `.github/workflows/ps1-quality.yml`'s hang fixture (`aai-smoke-hang.sh`)
  changes from `sleep 10` to `sleep 300` so the timeout arm hangs
  unconditionally with a duration that cannot plausibly elapse before the
  arm's `AAI_TEST_TIMEOUT=2` + outer watchdog grace fires.

## [unreleased] — feat(validation): lane-scaled depth + capability-detected validator isolation (CHANGE-0132) [L2]

- `.aai/VALIDATION.prompt.md` CEREMONY LANE block: on the lightweight lane
  (ceremony_level 0/1) the validator now runs the declared test scope plus
  adversarial probes on the seams it touches and does NOT run a blanket
  full-suite re-execution — close-before-CI ordering is named as why the
  full-suite proof still lands on the same commit. L2/L3 depth and the
  fail-closed default are byte-unchanged.
- `.aai/SUBAGENT_PROTOCOL.md` gains a "Capability detection (runtime, never
  a harness table)" contract (`multi_agent_backend`, `spawn_agent_available`,
  `spawn_model_catalog`, `fork_turns_supported`, resolved at runtime,
  re-resolved on a refused spawn, fail-closed on unknown) and rewrites
  "Spawning a validator" as four ordered isolation tiers — native
  `spawn_agent` with a different model and `fork_turns="none"` → retry
  against an available `spawn_model_catalog` model → separate
  role-per-invocation process (`codex exec -m`, hard isolation) →
  in-parent-session execution as last resort with a recorded residual risk
  — replacing the vague "other in-session hosts" bullet, plus a
  verify-the-granted-model clause.
- `.aai/scripts/lib/usage-note.mjs` gains a `requested_model=`/
  `actual_model=` marker grammar (same boundary discipline as
  `USAGE_NOTE_RE`, bracketed context-window suffix tolerant so
  `claude-opus-4-8[1m]` parses) so a silently-dropped model override is
  visible in `METRICS.jsonl` instead of being read as independence that
  never happened; `append-run --model` keeps recording the granted model.
- New product doc `docs/product/validation-cost-calibration.md` and new
  suite `tests/skills/test-aai-validator-isolation.sh`.

## [v2026.08.12] — feat(close): evidence-path gate — cited evidence must resolve from the main tree (CHANGE-0131) [L1]

- New `.aai/scripts/lib/evidence-paths.mjs` (Node stdlib only): a measured
  six-rule extraction grammar (`extractEvidencePaths`) over an AC Status
  Evidence cell — strip surrounding markdown punctuation, require a `/`,
  reject an ellipsis (`...`/`…`), require a clean `[A-Za-z0-9._/-]` charset,
  reject an absolute path, reject a `..` segment, and require the first
  segment to name an existing directory at the repo root. Measured against
  the live `docs/specs/` + `docs/issues/` corpus before it was written: 752
  tokens extracted, zero false positives over 718 cells. `evidenceCitations`
  reads AC rows only through the shared `parseAcTable`/`parseLeanAcTable`
  readers (`lib/docs-model.mjs`) — no fourth table parser.
  `unresolvedCitations` filters to tokens that do not `fs.existsSync` from
  the repo root (existence, not git-tracking — `docs/ai/tdd/**` is
  gitignored by design and is the single most common evidence location).
- `.aai/scripts/lib/guard-config.mjs`: `evidence_path_gate` joins the
  closed `GUARD_DIALS` set, the defaults object, and the line-parser
  alternation (all three, together — a dial added to only one silently
  reads as its default forever).
- `.aai/scripts/close-work-item.mjs`: `evaluateEvidencePathGate(docs)` runs
  immediately after the usage-capture gate and BEFORE `readEvents`/the
  idempotency short-circuit's INDEX regeneration — a refusal never leaves
  `docs/INDEX.md` written. Report-only (shipped default) WARNs on stderr
  naming the doc, the Spec-AC row and the unresolvable path; `enforce`
  REFUSES pre-write with exit code 5 (documented in the EXIT CONTRACT
  header, after the existing 0-4). `--dry-run` reports the verdict under
  `evidencePathGate` in its JSON and never exits 5 or writes.
- `docs/ai/docs-audit.yaml` ships the documented `evidence_path_gate:
  report-only` key (fail-open default; the flip to enforce is a later,
  separately-evidenced KPI decision, same as `usage_capture_gate`).
- `.aai/system/PROFILES.yaml`: the new lib joins the core
  `.aai/scripts/lib/*` classification (layer-profiles UNCLASSIFIED check
  enforces this).
- `tests/skills/test-aai-close-work-item.sh` gains TEST-036 through
  TEST-043 (extraction grammar, shared-parser grep contract, guard-config
  dial, report-only warn, enforce pre-write refusal, existence-not-tracking,
  the prose-never-refuses negative control, and `--dry-run` no-op) plus a
  `set_evidence_path_gate_dial` fixture helper; the pre-existing TEST-001
  through TEST-035 continue registered and green.
- Fixes the CHANGE-0127 incident this scope exists to close: a spec's AC
  Status Evidence citing a `docs/ai/tdd/...` transcript that resolved only
  inside a deleted worktree, caught previously only by a validator's manual
  sweep.

## [v2026.08.12] — feat(factory-report): per-role token consumption + weekly trend (CHANGE-0130) [L1]

- `.aai/scripts/generate-factory-report.mjs` gains one additive block,
  `cost.role_consumption`, built inside the EXISTING ride/agent_run loop (one
  extra accumulation pass, no second read/parse — reuses `normalizeRole`,
  `extractUsageTotal`, `hasUsageSentinel` and `CANONICAL_ROLES` from
  `lib/usage-note.mjs`, and the existing `median()` helper): per role, the
  six canonical roles (plus `Other` only when populated) each carry three
  partitioning run buckets — `runs_marked`, `runs_sentinel`,
  `runs_unmarked` — and `tokens_total` / `median_tokens_per_run` /
  `share_pct`, computed ONLY from marker-carrying runs and `null` (never `0`)
  when a role has no marked run. A run whose note carries both the
  `usage_total_tokens=<N>` marker and the `usage_capture=none` sentinel
  counts as marked.
- `cost.role_consumption.by_week` BORROWS the existing `m.trend[].week`
  array verbatim (never recomputed), so the new per-role weekly-median
  series shares its x-axis exactly with the report's other four charts.
- New `<section id="role-consumption">` in `factory-report.html` — the ONLY
  element in the page carrying an `id` — with a per-role table, a weekly
  median table, and one sparkline SVG per role with at least one marked
  run; `n/a` renders for every null cell; no dollar-amount figure anywhere.
- `tests/skills/test-aai-factory-report.sh` gains TEST-022 through TEST-027:
  bucket partitioning + marker-beats-sentinel + never-marked all-null
  (TEST-022), cross-KPI identities re-summed against `capture_coverage`,
  `cost.tokens_total` and `cost.by_role` on a fixture AND on the real
  `docs/ai` ledgers (TEST-023), weekly-trend borrowing incl. even-count
  median rounding (TEST-024), HTML-versus-JSON rendering (TEST-025), a
  byte-stability backcompat pin against two new goldens
  (`tests/fixtures/factory-report/backcompat-sparse-{data.json,html}`,
  captured from the PRE-change generator and never regenerated) proven by a
  RED mutation pair (TEST-026), and the product-doc pins (TEST-027). All six
  observed RED pre-change (`cost.role_consumption` undefined); full suite:
  28 tests (IDs to 027), all green. Sibling suites over the shared
  `lib/usage-note.mjs` grammar and the close hook — `test-aai-metrics.sh`,
  `test-aai-overview.sh`, `test-aai-close-work-item.sh`,
  `test-aai-layer-profiles.sh` — all green, unchanged.
- `docs/product/factory-performance-report.md`: new "Role consumption"
  section documenting the three buckets, the marker-only rule, the
  never-imputed `n/a` rule, and the sparse-era caveat (usage-marker coverage
  is complete only since 2026-08-02); `delivered_by` gains `CHANGE-0130`.

## [v2026.08.11] — feat(routine): scryer template v2 — MCP-aware merge sweep + shallow-clone-honest health (CHANGE-0129) [L2]

- `.aai/routines/SCRYER.routine.md`: `## Step 0 — Prerequisite probes` gains
  the read-ladder statement — `gh` when its probe passed, otherwise the
  GitHub MCP read tools `list_pull_requests`, `get_pull_request`,
  `get_pull_request_status`, `get_pull_request_comments` — plus the rule
  that an unavailable named tool degrades that digest section, never an
  invented substitute. A failed `gh` probe alone no longer degrades the PR
  sections; only losing both rungs does.
- New `## Step 1 — Repository health`, outside the merge-gate markers: a
  shallow-clone probe (`git rev-parse --is-shallow-repository`), a
  best-effort `git fetch --unshallow` repair, a re-probe that branches on
  the RE-PROBED state (never the fetch's exit code), and — when history is
  still unavailable — the digest names the shallow-clone artifact in
  **Degradováno** and SKIPs the history-based classes (`false-done`,
  `false-open`, `stale`) instead of reporting them as findings. Never a
  crash, per the existing resilience contract.
- Inside `<!-- MERGE-GATES:START -->`/`<!-- MERGE-GATES:END -->`: the merge
  ladder — `gh pr merge` when its probe passed, otherwise the GitHub MCP
  `merge_pull_request` tool. The three merge gates are unchanged; the
  report-only render (no `routine_authorization` record) still carries
  none of `## Merge gates` / `gh pr merge` / `merge_pull_request` — proven
  on the RENDERED output, not just template text, since only
  `applyMergeGate`'s marker-stripping enforces that isolation.
- `## Digest shape (Czech)` gains **Cesta nástrojů**, naming which tool
  path served the run.
- `tests/fixtures/routines/scryer-claude-merge.golden.txt` regenerated
  byte-for-byte from the edited template via the TEST-003 emitter
  invocation (never hand-patched).
- `tests/skills/test-aai-routine.sh` gains TEST-035 (ladder literals pinned
  on the correct side of the MERGE-GATES markers, digest names the tool
  path), TEST-036 (report-only vs authorized merge-instruction isolation,
  asserted on both rendered branches of `applyMergeGate`), and TEST-037
  (shallow-honesty health pins present in both rendered variants) — all
  three observed RED against the pre-change template before the edit,
  stored under `docs/ai/tdd/`. Full suite: 34 tests (IDs to 037), all green.
- No `routine-emit.mjs` change (D3) and no new placeholder (D2): the ladder
  is unconditional prose the agent evaluates at run time, not a
  render-time branch.

## [v2026.08.08] — feat(routine): standing routines become a vendored, on-demand, agent-neutral template (CHANGE-0128) [L2]

- New `.aai/routines/SCRYER.routine.md` — the morning-scryer standing routine
  reconstructed as a git-diffable, agent-neutral contract with a closed
  four-placeholder set (`{{REPO}}`, `{{SCHEDULE}}`, `{{MERGE_ALLOWED}}`,
  `{{MODEL}}`), replacing the previous Anthropic-cloud-only trigger
  (`trig_01XpMxioptoJ7j32YKzzaKnR`) that had no repository evidence beyond a
  merge authorization line.
- New `node .aai/scripts/routine-emit.mjs` — zero-network, Node-stdlib,
  emit-only instantiator: `--harness claude|codex|gemini|generic` and
  `--os macos|linux|windows` print the matching installation payload
  (a `JSON.parse`-able Claude trigger definition, or a crontab line + bash
  runner + PowerShell `Register-ScheduledTask` twin for local schedulers);
  every emission ends with a `TEST AT CREATION` block naming an immediate
  fire command and three things to verify.
- Merge-rights guard (Spec-AC-04): `--merge` emits the merge-enabled variant
  ONLY when `docs/ai/decisions.jsonl` carries a machine-checked
  `routine_authorization` record (`type`, `ref`, `by: "human"`, `grants`
  including `"merge"`); otherwise it degrades to report-only and prints a
  loud `MERGE DISABLED` line on stderr. Fails closed on an absent, unreadable,
  or malformed ledger — never silently skips the check.
- `docs/ai/decisions.jsonl` gains one appended canonical `routine_authorization`
  record for `aai-morning-scryer`, transcribing the prior 2026-08-06 free-text
  authorization with `derived_from` provenance; the pre-existing line is
  byte-unchanged (append-only).
- New `/aai-routine` skill (`.aai/SKILL_ROUTINE.prompt.md` + wrappers in all
  four skill trees) — invocation-only, pinned never to run from bootstrap,
  sync, or any automatic path.
- Governance: `.aai/system/PROFILES.yaml`, `tests/skills/suite-map.yaml`,
  the prompt-diet ledger, and `SKILLS.md` all gained their required entries;
  new suite `tests/skills/test-aai-routine.sh` (TEST-001..022 plus
  input-hardening TEST-026..034, 31 tests, all green).
- Input-hardening batch: every free-text flag now rejects control
  characters (incl. Unicode U+2028/U+2029) at the parsing boundary, a
  markerless template or an unresolved `{{...}}` placeholder after render
  (new exit code `3`) fails closed instead of leaking, and Windows
  `-TaskName`/`-Description` are PowerShell single-quoted literals immune
  to `$(...)` subexpression injection.
- PR #237 bot-sweep remediation (Codex + Copilot, TEST-031..034): the merge
  guard now fails closed over the WHOLE ledger on any malformed non-comment
  line (a valid record no longer survives a corrupt line elsewhere);
  windows emissions install an honestly-recurring `Register-ScheduledTask`
  trigger mapped from the cron shape (daily/weekly/every-N-hours), refusing
  loudly (exit 2) instead of the previous always-`-Once` trigger; the
  codex runner now invokes the real CLI grammar (`codex exec`, prompt fed
  via stdin) instead of the non-existent `--prompt-file` flag; template
  substitution is single-pass so a value can never be re-interpreted as
  another placeholder token; and `isMain` compares realpaths so invoking
  the script through a symlinked path (e.g. macOS's own `/var` ->
  `/private/var` TMPDIR) no longer silently no-ops.

## [v2026.08.08] — feat(live-status): optional zero-token live-status dashboard — per-harness parser registry, statusline/hook tap, watch mode (CHANGE-0127) [L2]

- New, strictly OPTIONAL `node .aai/scripts/generate-live-status.mjs` answers
  what the existing three generators (dashboard, factory-report, overview)
  cannot: what is running NOW, what it has cost TODAY, and official
  plan-quota headroom — zero LLM tokens, zero network, node stdlib only,
  never coupled to ride ceremony (grepped: zero references in
  close-work-item.mjs, autonomous-loop.sh, session-start.sh, .github/workflows).
- A per-harness parser registry (`.aai/scripts/live-parsers/{registry,
  claude-code,codex,gemini-cli}.mjs`) normalizes Claude Code, Codex and
  Gemini CLI session transcripts into one model. The honesty-critical core
  is TDD'd: Claude Code dedups on `message.id`+`requestId`
  (`event_sum_dedup`) so a duplicated on-disk line counts once; Codex takes
  the LAST `token_count` event's cumulative total per session
  (`session_cumulative_last`) so summing never multiplies real spend;
  Gemini CLI carries no usage field and renders the literal `N/A`, never a
  fabricated zero. A malformed registry entry is refused with a named error
  instead of silently producing partial totals.
- An incremental cache (`.aai/cache/live-status-index.json`, keyed on
  path+mtime+size) means a re-run over an unchanged corpus re-reads zero
  session files; verified live against the owner's real ~755-file corpus
  (cold ~1.3s, warm ~0.1s with 754/755 files skipped).
- Official quotas render from an opt-in statusline-tap spool
  (`five_hour`/`seven_day` used% + `resets_at`) or a harness's own
  in-session server-authoritative rate limits (Codex), else a named `SKIP`
  with an install hint — never an estimated limit. Liveness renders
  `finished`/`waiting-on-approval` from an opt-in hooks spool
  (Stop/Notification), else an mtime-window heuristic labelled with the
  literal word `heuristic`. Both spools are written by
  `.aai/scripts/live-spool.sh` (+ `.ps1` twin), which projects a WHITELIST
  of fields only and always exits 0.
- One-shot and `--watch` invocation modes (matching meta-refresh interval,
  clean exit 0 on SIGINT, no leftover child process); convenience launcher
  `aai-live.sh` / `aai-live.ps1` generates and opens the page via the
  platform opener, refusing with a named error instead of hanging when none
  is found. The opt-in hook overlay
  (`.aai/templates/hooks/live-status-hooks.json`) and the product doc
  (`docs/product/live-status-dashboard.md`) document install and uninstall
  for both spools.
- Outputs (`docs/ai/live-status.html`, `live-status-data.json`) and the
  spool directory (`docs/ai/live/`) are pure runtime sidecars — unlike
  dashboard/factory-report/overview they are never regenerated-and-committed
  at close, so `.gitignore` and `RUNTIME_IGNORE.list` gitignore them and
  `DOCS_AI_CANON.list` classifies them (never leaking into git status or the
  docs-audit non-canonical class). New `.aai` files classified in
  `PROFILES.yaml` (extended); new suite `aai-live-status` gets its
  `suite-map.yaml` row.
- Two re-review findings closed: `aai-live.sh`'s bare `--watch` (no other
  flags) died with an unbound-variable error on bash < 4.4 (bash 3.2.57,
  stock macOS) because an empty `WARMUP_ARGS` array expansion is fatal under
  `set -u` on those versions — fixed with the
  `${WARMUP_ARGS[@]+"${WARMUP_ARGS[@]}"}` idiom, which is correct for both
  the empty and non-empty case (unlike `"${ARR[@]:-}"`, which still passes
  one stray empty-string argument through). The spend-rows table cell was
  the last unescaped foreign-data interpolation in `renderHtml()` (`na()`
  instead of `naEsc()`), and `claude-code.mjs`/`codex.mjs`'s `usageTotal()`
  summed harness token fields with no `Number()` coercion, so a non-numeric
  field turned `+` into string concatenation and a hostile value could reach
  the page as a live `<script>` tag — both layers fixed together.
- PR bot-sweep follow-ups: the one-shot (non-`--watch`) launcher branch of
  `aai-live.sh`/`aai-live.ps1` now resolves the opener target from the
  invocation's own `--output`, mirroring the `--watch` branch's existing
  `resolve_output_path`/`Resolve-OutputPath` logic, instead of always
  opening the hardcoded default `docs/ai/live-status.html`. The dead,
  non-escaping `na()` helper is removed (`naEsc()` is the only escaping path
  now, closing the maintainability footgun of a look-alike non-escaping
  twin). When an available harness's records ALL fail usage coercion,
  `usage_today`/`usage_7d` now report `null` (never a fabricated `0`) with a
  named `notes[]` entry; when only a subset is unknown, the real numeric sum
  from the known records is kept and the exclusion is still named. Stale
  `SPEC-DRAFT-spec-live-status-dashboard` references (pre-dating the
  allocator's rename to `SPEC-0114-spec-live-status-dashboard`) fixed in
  `.gitignore` and the hooks overlay's install comment.

## [v2026.08.07] — feat(planning): CHANGE-0113's D2 gate closes with five behavioral probes, and the altitude PLANNING prompt is adopted (CHANGE-0125-adopt-v2-planning) [L2]

- The altitude experiment's pre-registered decision rule had three of four
  conditions satisfied on 2026-08-05 (D1 quality non-regression: V2 beat the
  shipped prompt 6-2-1 on paired sign test, median Q 13 vs 11; D3 noise; D4
  cost, -32% bytes) and one **unmet by construction**: D2 asked whether
  compliance survives deletion, and the five prose rules the rewrite deletes had
  **no detector at all**. This ride builds the five detectors first, then adopts
  the prompt.
- **spec-lint** gains `ac-without-test` — the reverse of the existing
  TEST-to-AC check: a Spec-AC that no Test Plan row claims. Both AC-table shapes
  (canonical gate and L0/L1 lean) feed it. Scoped to in-flight specs
  (draft/proposed/accepted/implementing) because a `done` spec's Test Plan is
  history: twelve corpus specs are in that shape and flagging them would produce
  noise, not action. This is the exact hole the replay's worst task fell into —
  well-formed acceptance criteria whose test commands did not run.
- **spec-freeze** gains PRECONDITIONS. It checked frontmatter parse and status
  transition only; a spec with untested ACs or an undecided strategy froze
  happily while the prompt said it must not. It now refuses (exit 3, named
  reason, nothing written, `--dry-run` and `--json` included) when the
  would-be-frozen document carries `ac-without-test` or
  `frozen-without-strategy`. Both are read off spec-lint's own rules applied to
  the transform's RESULT, so the freeze and the lint cannot disagree about what
  a violation is — there is no second parser. AC MEASURABILITY is deliberately
  not claimed: no parser can decide it, and the header and `--help` say so
  instead of implying a complete gate.
- **check-role-output** gains `E-PLANNING-VERDICT` plus two opt-in Planning
  gates. The disposition's "do not claim PASS" is unimplementable as written —
  `status: PASS` is the CONTRACT's role-run outcome and every real Planning
  block uses it — so the checkable rule is the one the prose was written
  against: Planning may not record a VALIDATION verdict field. Separately,
  `--base-ref` catches a Planning run writing outside docs/specs/**,
  docs/ai/** and docs/INDEX.md (untracked files included) and
  `--worktree-baseline` / `--worktree-guard` catch a worktree created during
  one. Merge-protocol step 1 does not pass those two flags (it holds neither a
  base ref nor a pre-dispatch worktree capture), so the new
  `tests/skills/test-aai-planning-probes.sh` suite is what proves they bite —
  scripted fake-Planning runs that commit each violation on purpose. That
  wiring gap is written into `.aai/SUBAGENT_PROTOCOL.md` rather than assumed
  away.
- **`.aai/PLANNING.prompt.md` becomes the V2 altitude text**: four principles,
  one worked example and a "what already decides what" authority table, in place
  of twelve numbered steps restating what the scripts and templates already
  enforce. Steps 10-12 survive as the mechanical tail — six suites pin
  `^11) Emit the work-item brief`, `^12) Update docs/ai/STATE.yaml` and the
  freeze/brief/STATE line ORDER, and turning an adoption into a pin migration
  would destroy the very "nothing broke" oracle the experiment rests on. Every
  PLANNING pin suite is green with **zero assertion edits**. Measured 11526 ->
  10227 B; the 1299 B (not 3685 B) shrink and its reason are recorded in the
  diet ledger, TEST-012 pin -9957 -> -11256, headroom back at 1150/2048.
- Four lean/minimal test fixtures gained a Test Plan row or a strategy line.
  That is the probe working, not collateral: each had frozen a spec whose ACs
  had no tests. Not gated, and on the watchlist: the replay's recorded overreach
  regression (median 2 vs 1), and the fact that a Test Plan row naming an AC
  still does not prove its command runs.

## [v2026.08.07] — fix(tests): the state-suite "byte-identical write" flake was a second-boundary race, not CI load (CHANGE-0124-state-flake-rootcause) [L1]

- `test_063_rguard_marker_absent_bytewise` compared the files written by two
  separate `state.mjs` invocations with a raw `cmp` — including the
  `updated_at_utc` field every mutator self-stamps from the wall clock at
  one-second resolution. When the pair straddled a second boundary the arm
  failed on exactly one byte (the seconds digit; captured:
  `...T09:18:47Z` vs `...T09:18:48Z`, `cmp -l` offset 2671). Measured at
  1/30 locally with NO load, so the "CI-load-only, just re-run it" filing
  was wrong — load only widens the window between the two `node` starts.
  The arm now normalizes exactly that one field and compares every other
  byte verbatim, and separately asserts both writes carry exactly one
  well-formed ISO-8601 stamp bumped off the frozen fixture value — so the
  normalization cannot mask a suppressed bump. `state.mjs` and
  `state-engine.mjs` are untouched: two writes at two instants are supposed
  to stamp two times. 30x under saturating CPU load and 30x without: green
  (pre-fix 2/30 and 1/30 failures). The reaper arms in
  `test-aai-run-tests.sh` are a different mechanism (process liveness across
  an etime-derived epoch guard, no byte comparison anywhere in that suite)
  and are left alone.

## [v2026.08.07] — fix(quality): tests that lie get caught — registration guard, corpus-sweep rule, honest names (CHANGE-0123) [L1]

- From the CHANGE-0120 retrospective: three shapes of misleading-but-green
  tests now have deterministic teeth — hygiene test_093 catches
  defined-but-never-invoked test functions (check-test-registration.mjs,
  RED-proven; the exact #229 class), VALIDATION gains the corpus-sweep rule
  (parsers must sweep all real instances, not fixtures), and review treats
  universal-negative test names as BLOCKING unless proven. LEARNED.md
  records the correlated-blind-spots lesson.

## [v2026.08.05] — feat(orchestration): mechanical ticks stop respawning agents — confirm-by-script, scope edits without a re-plan, atomic freeze (CHANGE-0120) [L2]

- Live cost forensics on a one-line downstream fix found ~4 of 11 agent runs
  were process self-repair that needed no model judgment. Three deterministic
  fixes remove that class:
- CONFIRM-BY-SCRIPT (`orchestration-dispatch.mjs` rule 9x): when a re-plan
  bounces a scope back to the implementation phases but changes NOTHING in the
  frozen spec's AC/test contract, the tick confirms the phase and dispatches
  NO agent. The comparison is content-addressed over the FROZEN SPEC itself —
  parsed AC ids + statuses and Test Plan ids + AC mapping — so re-wording and
  whitespace are invisible while any real contract move still dispatches
  normally. Fail-closed throughout: a non-green AC table, a hash delta, or no
  proof of prior green all fall through to the unchanged 9a/9b/9c dispatch.
  The comparison snapshot is stored in the append-only `docs/ai/EVENTS.jsonl`
  ledger as a new `phase_confirmed` event (written only under the new opt-in
  `--confirm` flag, idempotently) — no new STATE field, and `state.mjs` is not
  touched.
- SCOPE EDITS ARE NOT A PLANNING DISPATCH (`.aai/scripts/spec-scope-edit.mjs`,
  new): includes/excludes ONE path in a frozen spec's review-scope list and
  REFUSES (exit 3) any path in the ride's own diff — committed, staged,
  unstaged or untracked — because moving a path the ride actually changed is a
  content decision, not bookkeeping. Edits only the review-scope bullet,
  appends a `spec_scope_edited` audit line, and is idempotent down to the
  ledger. A failed diff probe refuses rather than falling open.
- ATOMIC FREEZE (`.aai/scripts/spec-freeze.mjs`, new): writes `SPEC-FROZEN:
  true` AND frontmatter `status: implementing` in one write+rename, or writes
  nothing — the half-frozen paperwork state that bounced a live ride back to
  Planning now has no producer. spec-lint gains the matching `half-frozen`
  rule for half-states arriving by hand; PLANNING step 10 routes freeze
  through the tool.
- Also fixes a false-green in the CHANGE-0122 suite: `test-aai-spec-lint.sh`
  called `$SPEC_LINT`, an undefined name, so under `set -u` the lint never ran
  and the template-self-flag assertion was vacuously true.
- CORPUS-SHAPE HARDENING (independent validation, pre-merge): both editors were
  written against the SPEC_TEMPLATE shape and met a corpus that does not match
  it. `spec-freeze` corrupted every spec with no `# ` H1 — the marker was
  spliced INSIDE the frontmatter at a stale offset and truncated adjacent
  content, reporting success. It now re-derives the insertion point from the
  rewritten document and, before writing anything, re-parses its own OUTPUT and
  refuses (exit 1, nothing written) unless the result is provably frozen.
  `spec-scope-edit` read only the flat comma list, so the 30 nested and 24
  backticked corpus specs parsed as EMPTY — `--exclude` reported "already out
  of scope" without editing or auditing, `--include` wrote onto the label line.
  Nested child lists, backticked entries, `(annotation)` suffixes and wrapped
  child lines are now first-class, original spelling is preserved on rewrite,
  and a scope bullet that yields no parsable path REFUSES (exit 4) instead of
  reporting a no-op success. Path spellings (`./x`, `a/../x`, `.//x`, absolute,
  symlinked repo prefixes) now normalize to one key, closing a hole where a
  laundered spelling walked a ride-touched path past the exit-3 refusal.
- FAIL-CLOSED CONFIRM: when `--confirm` is requested and the `phase_confirmed`
  event cannot be recorded, the tick falls back to a real dispatch with a
  stderr note instead of reporting a clean no-action — an unrecorded
  confirmation is invisible to the next tick and would repeat forever.

## [v2026.08.05] — feat(spec-lint): evidence requirements scale with the recorded strategy — direct rides stop paying TDD ceremony (CHANGE-0122) [L1]

- A one-line downstream fix taken under the `direct` strategy still shipped a
  spec demanding a STORED pre-fix RED artifact; review refused without it and
  the ride paid two extra agent runs for evidence its own strategy never
  promised. spec-lint now emits `strategy-evidence-mismatch` when a
  direct/untested spec's evidence-bearing sections (AC Status, AC Mapping,
  Test Plan, Verification, Evidence contract) demand a stored RED artifact or
  TDD-cycle evidence. tdd/hybrid are byte-unchanged, per-strategy guidance
  rows and explicit waivers never fire, and an unknown or `undecided`
  strategy fails OPEN. The strategy is read from the document itself (the
  `- Strategy:` line SPEC_TEMPLATE writes) or supplied by a caller that knows
  STATE's value via the new enum-guarded `--strategy <v>` flag.
- SPEC_TEMPLATE gains an `### Evidence by strategy` table (tdd/hybrid: RED
  artifact + full matrix; loop: green runs, storage optional; direct:
  targeted regression green + scoped diff, no stored RED, no matrix beyond
  declared versions; untested: rationale + scoped diff) and lists
  direct/untested among the allowed strategy values; PLANNING step 7 points
  at it in three lines.

## [v2026.08.05] — fix(install): the fast lane stops being structurally dead downstream — the guard config is seeded (CHANGE-0121) [L1]

- Live cost forensics found the lightweight lane's exact target ride (1-line
  fix, direct strategy) computing `LANE heavy` downstream for one reason:
  `docs/ai/docs-audit.yaml` does not exist in target projects, so lane-gate
  fails closed on `protected_config_missing`. No downstream project could
  ever ride fast until someone hand-wrote the config.
- aai-sync (.sh + .ps1) now seeds a minimal `docs/ai/docs-audit.yaml` from a
  new vendored `.aai/templates/docs-audit.template.yaml` when — and only
  when — the file is missing, alongside the existing update-config and
  TECHNOLOGY seeds. An existing file is never overwritten (byte-identical
  across a re-sync) and the seed prints one operator-facing note.
- The seeded `protected_paths_l3` is the canonical vendored set, not a hand
  copy: test-aai-sync-seed TEST-006 pins the template's list to the AAI
  repo's own docs-audit.yaml, so editing one without the other turns the
  suite RED. Dials ship report-only (adoption never starts blocking commits
  or closes) and `docs_ai_canon_extra: []`. Fail-closed semantics are
  untouched — the config simply exists now.

## [v2026.08.04] — feat(docs-audit): docs/ai gets a canon registry — invented dirs are detected, not found by hand (CHANGE-0119) [L1]

- Downstream agents invented two ad-hoc dirs under docs/ai/ in two days
  (validation/, since canonicalized; hitl/, which is not canonical — HITL
  decisions belong in docs/decisions/). Both leaked as untracked noise and
  were found only by the operator, by hand. A vendored inventory
  .aai/system/DOCS_AI_CANON.list now names the allowed direct children of
  docs/ai/, projects extend it via docs_ai_canon_extra: in docs-audit.yaml,
  and docs-audit enumerates the real directory against both — naming every
  stray with a shape-derived remediation hint (hitl -> docs/decisions;
  run-output dir -> tdd/validation/reports). Report-only WARN: the summary
  line and detail section appear only when N > 0 (clean repos stay
  byte-identical), the verdict and exit codes are untouched, and --quick
  detects it too (pure fs).

## [v2026.08.04] — fix(install): docs/ai/validation joins the runtime-ignore class (CHANGE-0118) [L1]

- Downstream Validation runs leaked logs as untracked noise via a
  self-invented docs/ai/validation/ (no canonical ignored home existed).
  The dir is now canonicalized-and-ignored like tdd/**, across AAI
  .gitignore, the bootstrap seed and the ps1 migrate parity. Verdicts stay
  committed (EVENTS/AC tables); curated reviews stay committed (H4); raw
  run output never does.

## [v2026.08.03.2] — fix(release): downstream pins stop saying UNKNOWN — releases stamp AAI_VERSION.md (CHANGE-0117) [L1]

- aai-sync reads docs/ai/AAI_VERSION.md from the source, but the file never
  existed and no cut wrote it — every downstream AAI_PIN said Template
  version: UNKNOWN (operator-found). Both release engines now stamp it in
  the release commit; the file is seeded at v2026.08.03; sync falls back to
  the newest release tag for older checkouts.

## [v2026.08.03.2] — fix(release): the roll consumes the pre-existing scaffold — duplicate-heading class fixed at its root (CHANGE-0116) [L1]

- 4th occurrence traced to the engine itself: every cut copied the old bare
  scaffold into the versioned region while inserting a fresh one. The roll
  now consumes pre-existing scaffolds (TEST-023, RED-proven: pre-fix engine
  leaves 2); the fixture gap (no scaffold+entries kind) is closed; the live
  duplicate from the v2026.08.03 cut is cleaned in the same diff.

## [v2026.08.03] — fix(install): bootstrap seeds runtime-sidecar gitignore block into target projects (CHANGE-0115) [L1]

- Operator-found pre-deployment gap: target projects got no ignore entries
  for AAI runtime sidecars — a git add -A could commit docs/ai/STATE.yaml
  and break the per-dev single-writer model. ensure_gitignore now seeds the
  full runtime block (idempotent, marker-commented, user entries respected);
  dashboards/reports stay tracked by design.

## [v2026.08.03] — chore(diet): the role prompts stop shipping a git tutorial and 26 rows of self-argument (CHANGE-0114) [L1]

- Executed the zero-pin "safe immediate wins" of the Phase 0 unhobbling audit
  (docs/analysis/unhobbling-audit.md, CHANGE-0113): -12,873 B measured across
  SKILL_WORKTREE (-6019), VALIDATION (-2098), SKILL_TDD (-1860), PLANNING
  (-1699) and SKILL_LOOP (-1197). Deleted content was derivable from a script
  or `git --help`, a verbatim second copy of a rule that lives elsewhere, or a
  checklist restating the numbered steps above it — including the drifted
  inline STATE.yaml heredoc (now seeded from STATE_TEMPLATE.yaml) and the
  VALIDATION/PLANNING rationalization tables, 19 rows of pre-emptive rebuttals
  a current-gen model does not need. Every `needs-gate-first` rule and every
  pinned sentence survives verbatim; the ledger retires the freed credit
  (TEST-012 pin 1305 -> -11568), headroom unchanged at 1530/2048.

## [v2026.08.03] — feat(pr): fast lane opens to spec-less rides — intake frontmatter as the ceremony source (CHANGE-0112) [L1]

- Measured 2026-08-02: 8 rides, 0 fast — the lane's exact target class
  (small test+docs rides on an intake with no spec) could never qualify,
  because ceremony_level was read only from spec frontmatter. lane-gate
  --intake now reads the intake doc as a fail-closed fallback (source
  labeled; a present spec always wins — no downgrade shopping). SKILL_PR
  documents the flag; +189 B ledger-credited.

## [v2026.08.03] — chore(quality): CHANGELOG scaffold invariants get a PR-time guard (CHANGE-0111) [L1]

- 3rd recurrence of the duplicate-bare-scaffold class this week (bot-caught on
  #211, rolled into the released section, cleaned by #214): aai-release
  TEST-022 now asserts on the live file — exactly one bare scaffold, above all
  versioned sections — at PR time, not just at release-cut time.

## [v2026.08.02] — chore(diet): buy back prompt-budget headroom so the corpus stops running a zero-headroom treadmill (CHANGE-0110) [L1]

- The prompt-diet floor (`tests/skills/test-aai-prompt-diet.sh` TEST-010) had
  been pinned at `headroom 0/2048` since CHANGE-0090. At zero headroom every
  prompt byte any ride adds breaches the floor on the spot and forces a ledger
  true-up in the same commit — six of them in the week of 2026-07-27 (196, 238,
  551, 262, 349 and 73 B entries), none of which were about whether the growth
  was justified.
- Trimmed 1530 B of genuinely dead weight out of the three largest corpus
  prompts, moving headroom 0 -> 1530: `.aai/SKILL_LOOP.prompt.md` -1297 (six
  full-width U+2500 box-drawing rules in the CHECKPOINT GATE templates replaced
  by the `---` separator the same file already uses for its HITL block — `─` is
  3 bytes each; plus the `LOOP PARAMETERS` `stop_conditions:` list, a verbatim
  second copy of step 2 a-f, collapsed to a pointer at that single definition),
  `.aai/VALIDATION.prompt.md` -209 (the AC STATUS GATE paragraph and the
  `Detection:` bullets stated the same `Review-By` opt-in rule twice — merged),
  `.aai/SKILL_PR.prompt.md` -24 (step 5 re-invoked `pr-platform.mjs` a second
  time after the PLATFORM GATE had already run it).
- Zero semantic rule loss and no credit change: `JUSTIFIED_GROWTH_BYTES` stays
  1116 (TEST-012 pin untouched) because the ledger only lowers credit when a
  shrink would push headroom ABOVE the 2048 cap. 23 grep-pin suites covering the
  three files — every suite `grep -l` finds for them — plus layer-profiles and
  a strict docs audit are green.

## [v2026.08.02] — feat(r-guard): runtime single-writer guard + flush-time forensic backstop (SPEC-0113) [L3]

- Closes the highest-blast-radius gap between "the prompt says so" and "the
  machine ensures so": the single-writer rule (a subagent MUST NOT write
  `docs/ai/STATE.yaml`; the orchestrator is the sole writer — Constitution
  Art. 6) was prose pinned only by grep. Stage 1 adds ONE additive guard clause
  to the protected `.aai/scripts/state.mjs` (L3): when `AAI_ROLE=subagent` is
  set, every STATE-mutating subcommand (the nine mutators plus `reset-block`)
  refuses with a NEW dedicated exit code 3 and writes NOTHING — the file is
  never opened. `log-tick` (LOOP_TICKS) and the separate `append-event.mjs`
  (EVENTS.jsonl) stay allowed. Purely additive: byte-for-byte identical when the
  marker is absent (the full existing state suite passes unchanged).
- Orchestrator wiring: `.aai/SUBAGENT_PROTOCOL.md` (dispatch call contract ENV
  row + updated R-GUARD residual note) and `.aai/ORCHESTRATION_PARALLEL.prompt.md`
  instruct exporting `AAI_ROLE=subagent` for each spawned subagent and keeping it
  UNSET for the orchestrator's own writes.
- Stage 2/3 (WARN-only, `.aai/scripts/metrics-flush.mjs`, not protected): a
  flush-time forensic backstop for the case Stage 1 cannot stop (an agent that
  unset the marker). It flags a flushed ride whose `implementation_strategy.source`
  is neither `intake` nor a spec-path (Stage 2 provenance), escalates a
  rigor-downgrade lane (`untested`/`direct`) with a non-sanctioned source
  (Stage 3, SPEC-0109 RR-3), and flags a `docs/ai/EVENTS.jsonl` that shrank vs
  `git show HEAD:` (Stage 3 append-only predicate). Never blocks.
- HONESTY (rides the code + spec, never softened): Stage 1 is a guardrail against
  the honest/accidental subagent write, NOT a security boundary — an agent that
  unsets the marker defeats it. STATE is gitignored, so the intake's original
  git-timeline cross-check is NOT implementable; Stage 2 is a provenance
  heuristic, not proof. R-GUARD raises the floor from "prose only" to "prose + a
  guardrail that stops the honest mistake + a forensic detector for the dishonest
  one." It does not make a rogue subagent STATE write impossible.
- Tests: `tests/skills/test-aai-state.sh` (Stage 1 refusal, byte-identity,
  allowed paths, exit-code ordering), `tests/skills/test-aai-metrics.sh`
  (Stage 2/3 WARNs), new pin suite `tests/skills/test-aai-r-guard.sh` (wiring +
  live seam) with its `suite-map.yaml` row; prompt-diet ledger trued up (+238 B
  in-glob, credited 1:1, headroom 0/2048; TEST-012 pin trued to the merge-base sum (+238)).

## [v2026.08.02] — feat(runtime): shared runtime-sidecar lifecycle lib + convention pin (CHANGE-0106) [L2]

- Consolidates the hand-rolled lifecycle logic that every recent feature
  re-derived for its own gitignored runtime SIDECAR — the re-derivation that
  shipped ~23 lifecycle defects across four sidecar families in ~2 weeks (~74%
  first caught by external review bots). New zero-dep `.aai/scripts/lib/`
  `runtime-file.mjs` exposes the five proven primitives, each annotated with the
  historical bug CLASS it kills: `loadOrDegrade` (absent vs corrupt vs ok — a
  damaged ledger is never read as empty, class B), `atomicWrite` (temp+rename,
  the rename the sole commit point — no torn write, class E), `claimExclusive`
  (per-pid temp + linkSync with an O_EXCL `wx` fallback, returning
  claimed/held/error so a genuine failure is loud — class A), `isStale`
  (symmetric `|now-ts|>window` with an injectable clock; future-dated / NaN ->
  stale, never wedges — classes C+F), and `reapAsides` (bounded GC of aged
  orphan/aside files, missing-dir is a no-op — class D).
- New negative-control suite `tests/skills/test-aai-runtime-file.sh`
  (TEST-001..016) drives the exact failure input each bespoke sidecar got wrong
  (corrupt / absent / true-parallel race / future-dated / torn-write /
  orphan-reap + determinism x2 + zero-dep) — moving that discovery LEFT, once,
  instead of re-paying it per sidecar per target project.
- Migrates ONE sidecar as a byte-identical proof: `hitl-channel.mjs`
  `loadSidecar` -> `loadOrDegrade` and `saveSidecar` -> `atomicWrite`. The
  serialized bytes are unchanged, so the 19-test hitl-channel suite stays green
  UNCHANGED; the migration ADDS the previously-missing crash-safety guarantee.
  A CONVENTION is pinned (`runtime-file.mjs` header + a
  `.aai/SKILL_CODE_REVIEW.prompt.md` Verdict-2 BLOCKING-finding line): any NEW
  gitignored runtime sidecar MUST use the lib. The hardened `update-check.mjs`
  lock and the SPEC-0004 `docs-lock.mjs` lease are deliberately left frozen.

## [v2026.08.02] — feat(telemetry): close-time usage-capture gate + run-level coverage KPI (CHANGE-0105) [L2]

- Closes the *ongoing* usage-marker leak the factory-performance report exposed:
  53.8% of agent runs carried no `usage_total_tokens` marker because the marker
  was guarded only by prose ("MANDATORY") with no runtime teeth. Adds a
  deterministic close-time gate (`close-work-item.mjs`) — the per-ride
  transition that already reads STATE `agent_runs` and already owns a fail-open
  guard-config dial — that scans the closing ride's runs and, for any
  harness-dispatched-role run (Planning, Implementation, TDD Implementation,
  Validation, Code Review, Remediation) missing BOTH a valid marker AND
  decomposed `tokens_in/out`, WARNs (report-only, shipped default) or REFUSEs
  before any write (exit 4, `usage_capture_gate: enforce` opt-in). Meta-roles
  (Orchestration, Metrics Flush) and unrecognized roles are never gated.
- Honest-gap escape hatch: a run whose harness genuinely exposed no usage
  records the sentinel note `usage_capture=none`, which counts as captured and
  passes even under `enforce` — enforce never punishes an honest absence. The
  new dial (`docs/ai/docs-audit.yaml`, `lib/guard-config.mjs GUARD_DIALS`)
  mirrors `product_doc_gate`: values `enforce | report-only`, absent/invalid →
  report-only fail-open with a stderr notice. AAI core ships it report-only.
- Promotes the factory-report's no-marker footnote to a first-class run-level
  `cost.capture_coverage` KPI (`runs_with_marker / total_runs`, overall + a
  per-ISO-week series, rendered as a KPI tile + weekly bar). Honest nulls
  preserved: an empty ledger reports `pct: null` (never a fabricated zero), a
  real all-unmarked ledger reports an honest `0%`.
- Single-source, no drift: the marker grammar, the `usage_capture=none` sentinel
  grammar, and the canonical harness-role vocabulary all live in
  `lib/usage-note.mjs`; both the close gate and the report import them (the
  report's local `CANONICAL_ROLES`/`normalizeRole` were folded into the lib).
  Non-goals honored mechanically: no historical backfill, `tokens_in/out` fields
  retained, `metrics-flush` stays warn-never-block. Tests extend
  `test-aai-close-work-item.sh` (TEST-030..035) and `test-aai-factory-report.sh`
  (TEST-020..021). Script-only: zero prompt-corpus bytes, no new `.aai/**` file.

## [v2026.08.02] — feat(pr): deterministic PR fast-lane for small, safe rides (CHANGE lightweight-e2e-lane / SPEC spec-lightweight-e2e-lane) [L2]

- Cuts the flat ~42-min ceremony floor for provably-small rides without
  weakening the heavy lane. A new deterministic gate
  (`.aai/scripts/lane-gate.mjs`) prints `LANE fast` ONLY when all four
  machine-read predicates hold: ceremony_level in {0,1}, implementation
  strategy in {direct,untested,loop}, `select-suites.mjs` returns no FULL_RUN
  (protected-l3 / `.aai/scripts/lib/**` / unmapped), and changed-files < 5 with
  diff classes ⊆ {docs, prose, single test, single non-core script}. ANY other
  input — including every mis-declaration — resolves to the byte-for-byte
  unchanged HEAVY lane (fail-closed, anti-gaming; no agent judgment anywhere).
- On `LANE fast`, SKILL_PR: the external bot sweep (step 5d) becomes
  optional-on-demand while the MANDATORY internal dual-verdict code review stays
  the compensating control (re-armable by any reviewer/bot; a review may
  reclassify upward); the close-ceremony commit's docs-only diff routes to the
  CORE suites via SPEC-0097 (one narrowed feature round + one CORE-only close
  round instead of two full-framework rounds — the post-merge/nightly FULL run
  stays the backstop). The chosen lane + its predicate values are recorded in a
  PR body `## Lane` section (auditable — never a hidden decision).
- No protected surface changed: `close-work-item.mjs`, `allocate-doc-number.mjs`,
  the state engine, pre-commit guards, and `WORKFLOW.md` are untouched. A literal
  single-commit ride is not attempted — `close-work-item.mjs` mandates `--pr N`
  — so the second CI round is narrowed, not eliminated, exactly per the intake's
  Option A. New table-driven suite `tests/skills/test-aai-lightweight-lane.sh`
  (TEST-001..018) pins the predicate matrix, the fail-closed negatives, and the
  docs-only-close-diff routing.

## [v2026.08.02] — fix(ops): orphan-sweep — leaked runaway shells die at the next session start (CHANGE-0108) [L1]

- Incident-driven (37 orphaned busy-loops, ~15 cores, ~4 days, found by the
  operator): session-start hook now runs a bounded, best-effort orphan sweep
  killing launchd-adopted agent-shell wrappers that are old (>=2 h) AND hot
  (>=20 % CPU), by process group. Own-PGID + mixed-group + fail-safe guards;
  silent no-op contract; one-line kill report rides the hook context.
  Real-kill test + 7 fixture tests.

## [v2026.08.02] — chore(quality): phantom-API pin — nonexistent-but-plausible runtime APIs stop surviving review (CHANGE-0109) [L1]

- hygiene-pack test_092 pins known-phantom Node APIs (process.getpgrp cousins,
  callback fs.exists, ESM require.main) across .aai scripts; LEARNED.md adds
  the 10-second existence-probe rule. Driven by the live CHANGE-0108 case: a
  phantom API survived author + internal review, caught only by a PR bot.

## [v2026.08.01] — feat(hitl): async HITL via platform comments — park a ride, answer from anywhere (CHANGE-0102 / SPEC-0111) [L2]

- A ride that needs a human decision no longer has to block the terminal: when
  the scope has a linked GitHub issue/PR, the blocking `[HITL-<n>]` question +
  enumerated options are posted as ONE platform comment (idempotent per
  token+thread+kind), the ride parks, and a later session resumes by feeding
  the reply into the existing fail-closed SKILL_HITL resolution. New
  `.aai/scripts/hitl-channel.mjs` (post / poll / resolve; Node stdlib; sidecar
  `docs/ai/hitl-channel.json`, gitignored) — state.mjs untouched (L2, no
  protected path). Trust boundary: a reply resolves a decision only from an
  author with repo write permission (permission-API error fails CLOSED), bots
  and self filtered, only comments after our post count; the body is untrusted
  data (C0/C1/bidi stripped, never executed or shell-interpolated); ambiguous
  replies fail closed with ONE idempotent follow-up; applied answers are
  consumed (`resolve`) so they never re-surface and a stale reply for a
  different token is ignored. No platform / API error degrades to terminal
  HITL byte-for-byte. Suite `tests/skills/test-aai-hitl-channel.sh` (15 tests,
  zero real network); adversarial validation PASS (permission/bot/injection
  probes fail-closed, both test-quality mutants bit); its HIGH residual
  (missing resolve lifecycle) fixed in-ride. Split to follow-ups: milestone
  comments, PR visual evidence, session-start nudge, Azure comment channel.

## [v2026.08.01] — feat(dispatch): token-economics cache-friendly dispatch ordering audit + advisory effort routing (CHANGE-0101 / SPEC-0110) [L2]

- Prompt caching bills a repeated stable prefix at ~10% of base rate, but only
  while that prefix is byte-identical across calls and the effort/model cache key
  is unchanged. The factory dispatches large role prompts thousands of times, so a
  regression in stable-first/variable-last ordering, or a mid-session effort/model
  flip, silently forfeits the discount on every dispatch. This ride audits the
  ordering, adds an advisory per-role effort hint, and pins the invariants.
- CACHE-ORDERING AUDIT (AC-001): every dispatch-assembled prompt surface
  (orchestration-dispatch.mjs JSON + --human block, SUBAGENT_PROTOCOL dispatch
  contract, SKILL_LOOP step 4 + CACHING DISCIPLINE, ORCHESTRATION_PARALLEL SUBAGENT
  EXECUTION, BRIEF_TEMPLATE, ROLE_COMMON) was classified stable vs variable and its
  order recorded in the spec. Finding: ZERO reorders needed — every real
  prompt-assembly surface already leads with the stable role prompt/canon and
  places variable scope/STATE last, and SKILL_LOOP already pins it. AC-002 locks
  the invariant: a suite check asserts the stable prefix (role prompt +
  SUBAGENT_CONTRACT + LEARNED, via the SPEC-0096 prompt-hash machinery) is
  byte-identical across two consecutive same-role dispatches.
- ADVISORY EFFORT ROUTING (AC-003): `.aai/system/MODEL_ROUTING.yaml` gains optional
  `effort_tiers:`/`effort_roles:` sections; `orchestration-dispatch.mjs` surfaces
  `suggested_effort` on every dispatch (JSON + --human) resolved as
  effort_roles[role] ?? effort_tiers[tier] ?? null, mirroring `suggested_model`.
  Shipped map: mechanical roles low, Planning/Implementation default, Validation +
  Code Review high. Advisory only (the harness owns real API params); an absent
  file or absent field degrades `suggested_effort` to null (back-compat).
- NO-MID-SESSION-FLIP PIN (AC-004): a grep-pinned rule in the MODEL_ROUTING.yaml
  header forbids flipping a role's effort/model inside one running session (the key
  is part of the cache key) — separate dispatches per tier, the factory's existing
  shape. Documentation-only; no behavioral surface changed.
- Zero prompt-corpus growth (AC-005): all changes land in scripts/system/tests
  (no ledger cost); prompt-diet headroom stays 0/2048 and TEST-012 unchanged.
  Tests: test-aai-orchestration-dispatch.sh TEST-030..034.

## [v2026.08.01] — feat(intake): user-facing implementation-mode choice (TDD / direct+tests / no-tests) (CHANGE-0100 / SPEC-0109) [L3]

- After a full intake AAI silently routed small changes through the full TDD loop
  (~3-5% of a weekly token limit for a comparable small change), forcing the owner
  to manually steer to direct implementation each time, and it wrote tests even for
  tuning/run scripts unless explicitly told not to. This ride surfaces the
  implementation mode to the user at the END of intake as an explicit 3-way choice
  WITH a recommendation, and honors the chosen lane end to end.
- STRATEGY ENUM (`.aai/scripts/state.mjs`, protected L3): `direct` (implement +
  targeted regression tests, no RED/GREEN ceremony) and `untested` (implement only,
  NO tests) join `loop`/`tdd`/`hybrid`/`undecided` (back-compat). `set-strategy`
  REJECTS `untested` without a non-empty `--rationale` (exit 2, nothing written) so
  the no-tests lane is always a deliberate, audited choice. The enum is mirrored in
  `orchestration-dispatch.mjs` so a recorded lane is never rejected by the dispatcher.
- INTAKE SURFACES THE CHOICE: single-sourced "IMPLEMENTATION MODE CHOICE" block in
  `.aai/INTAKE_COMMON.md`, applied at end of flow from `.aai/SKILL_INTAKE.prompt.md`
  (STEP 3.5). The recommendation is derived from deterministic signals
  (script/tuning-only -> no-tests; small single-surface -> direct+tests;
  behavioral/multi-surface/L2-L3 -> full TDD). No choice -> unchanged (Planning
  decides).
- DOWNSTREAM HONOR: PLANNING respects a pre-recorded intake choice (never silently
  overrides); IMPLEMENTATION/SKILL_TDD run the `direct`/`untested` lanes; VALIDATION
  makes the RED-proof / TDD-evidence demand strategy-conditional (`direct` ->
  targeted-test exit codes, `untested` -> declared verification + rationale) and
  NEVER weakens the tdd/hybrid lanes, independence, or the AC STATUS GATE.
- Governance: prompt-diet ledger true-up (+4774 B, headroom 0/2048) + TEST-012 pin;
  new grep-contract suite `tests/skills/test-aai-implementation-mode.sh` + suite-map
  row; frozen ceremony_level:3 spec authorizes the state.mjs touch (TEST-014).

## [v2026.07.30] — feat(feedback): deterministic friction capture points (CHANGE-0099) [L2]

- RFC-0012 Phase 2 was stalled on ZERO data — `docs/ai/friction/observations.jsonl`
  never got written because the only capture path was recall-dependent PROSE in
  role prompts (the ROLE_COMMON FRICTION HOOK / FRICTION_PROTOCOL.md shadow-capture
  seam), which demonstrably never fired during real work. This ride wires two
  DETERMINISTIC capture points into the scripts where friction provably flows (same
  philosophy as deterministic dispatch: prompt prose does not fire, scripts always
  do). Raw observation only — no LLM ownership judgment at write time
  (`confidence: low`), triage stays review-mode.
- CAPTURE POINT 1 — `.aai/scripts/aai-run-tests.sh`: on a non-zero wrapped-command
  exit it appends ONE schema-v2 observation via the existing `aai-friction.mjs
  record` CLI (a 124 timeout -> `stalled_progress`, any other non-zero ->
  `deterministic_script_failure`; `skill_id: aai-run-tests`). Best-effort and
  never-mask-the-caller: any capture failure is swallowed and the wrapper's real
  exit code is never changed.
- CAPTURE POINT 2 — `.aai/scripts/close-work-item.mjs`: at a successful close it
  reads `docs/ai/STATE.yaml` and, when the closing ride carried `role: Remediation`
  agent_runs, appends ONE observation summarizing the recovery work
  (`skill_id: close-work-item`, `failure_class: abstraction_leak_recovery`). Same
  strictly-last, best-effort discipline as the report/docs-hub regen hooks — never
  reaches rollback, never changes the close exit code.
- ISOLATION (deterministic, pinned): capture fires only when
  `AAI_FRICTION_CAPTURE` is not `0` AND the resolved `docs/ai/friction` spool DIR
  already exists, so fixture repos never pollute the real spool; the wrapper's own
  regression suite sets `AAI_FRICTION_CAPTURE=0`. No schema change (the frozen v2
  `record` contract is reused verbatim — identity fields stay excluded by
  construction). No `.aai` prompt bytes and no new `.aai` file added; the only
  companion obligation is the new `suite-map.yaml` row.
- Covered by `tests/skills/test-aai-friction-capture-points.sh` (TEST-001..009,
  incl. never-mask negative controls with an unwritable spool and fixture-isolation
  pins). RFC-0012 phase-table row 2 updated.

## [v2026.07.30] — feat(reporting): factory performance report — continuous efficiency overview (CHANGE-0098 / SPEC-0108) [L2]

- New deterministic generator `.aai/scripts/generate-factory-report.mjs` reads
  the existing `docs/ai/METRICS.jsonl` + `docs/ai/EVENTS.jsonl` (+ release-doc
  `links.members`) and renders a self-contained `docs/ai/factory-report.html`
  (+ `factory-report-data.json`) answering the owner ask "how efficiently is
  the factory running — what does it deliver, how fast, at what token cost, at
  what quality — over time". Four dimensions, each with an overall value AND a
  per-ISO-week trend series: THROUGHPUT (work_item_closed per week / per
  release, lead time = close minus earliest agent-run start), SPEED (per-ride
  agent busy-seconds, per-canonical-role split with role-variant
  normalization), COST (undecomposed tokens via the shared
  `lib/usage-note.mjs` grammar — tokens only, never a fabricated USD figure),
  QUALITY (first-pass-clean rate, remediation distribution, verdict mix from
  the recorded `reliability` block only). Node stdlib, zero network. Honesty
  rules are load-bearing: values not mechanically derivable render `n/a`, never
  imputed; malformed JSONL lines are skipped and named (degrade-with-NOTE).
- Auto-regenerates best-effort at every successful close (additive, strictly-
  last hook in `close-work-item.mjs` after the docs-hub regen — a generator
  failure never reaches rollback and never changes the close exit code,
  negative-control tested).
- Exposed via the thin `/aai-factory-report` skill wrapper (mirrors
  `aai-overview` — no new `.aai` prompt-corpus file). Classified in PROFILES
  `extended` and mapped in `tests/skills/suite-map.yaml`. Covered by
  `tests/skills/test-aai-factory-report.sh` (TEST-001..014, incl. two cross-
  generator SEAM tests against metrics-report.mjs and generate-overview.mjs,
  and a real-close-entrypoint negative control).
- Bot-sweep hardening (TEST-017..019): the project label now derives from the
  origin remote `owner/repo` slug (basename fallback) so committed artifacts no
  longer embed a throwaway worktree directory name; a ref closed more than once
  counts once and buckets at its LATEST close with an honesty note;
  `counts.active_weeks` is the union of delivery and ride weeks (matching the
  rendered trend); and the remediation table sorts numeric buckets ascending
  with `n/a` last deterministically.

## [v2026.07.30] — feat(auto-update): allocator rewrites DRAFT refs in script/test trees (CHANGE-0097-allocator-header-rewrite) [L3]

- Closes the last dangling-DRAFT-reference class after CHANGE-0064. The
  merge-time doc-number allocator (`allocate-doc-number.mjs`) already rewrote
  `TYPE-DRAFT-<slug>` -> `TYPE-NNNN-<slug>` across committed-class MARKDOWN
  trees; it now applies the SAME verbatim substitution to SCRIPT/TEST sources
  (`tests/**/*.{sh,ps1,mjs}` and `.aai/scripts/**/*.{mjs,sh,ps1}`) via new
  `REWRITE_CODE_TREES` / `REWRITE_CODE_EXTS` constants, so a numbered doc
  leaves no stale DRAFT slug in a header comment or fixture path constant —
  retiring the manual per-ride sed sweep. An `EXCLUDED_CODE_PATHS` list mirrors
  `EXCLUDED_TREES` to hold byte-identical the meta-test suites that TEACH the
  DRAFT convention (doc-numbering, reservation, spec-lint, docs-audit, state),
  the shared `tests/fixtures` tree, the allocator's own source, and the frozen
  prompt-diet byte-accounting ledger. The pass stays idempotent (write only on
  change) and byte-safe (source extensions only). A one-time backfill cleaned
  the DRAFT refs already in-tree so the pointer invariant starts clean.

## [v2026.07.30] — feat(pr): reviewer_bots knob so the GitHub PR sweep never waits for absent bots (CHANGE-0096-github-no-bots-hardening) [L2]

- Closes the GITHUB-WITHOUT-BOTS residual from CHANGE-0085/SPEC-0103. The PR
  ceremony's 5d bot-review sweep polls Copilot/Codex inline comments after CI.
  On a GitHub repo where NO reviewer bots are installed, GitHub is still
  detected, so the bot path was taken and could wait for comments that will
  never arrive, while the empty-sweep shortcut silently skipped review.
- `pr-platform.mjs` now reads a repo-local `reviewer_bots` knob
  (`docs/ai/pr-config.yaml`, column-0 line scan) and prints
  `reviewer_bots=<expected|none|unknown>` in both text and `--json`. Absent
  file/key == `none` (assume-none, the safest default); an invalid value ==
  `unknown` with a stderr warning (fail-open).
- `SKILL_PR` step 5d gates the "no bot findings" empty-sweep shortcut on
  `reviewer_bots == expected`; a GitHub repo with `reviewer_bots`
  none/unknown/absent now takes the internal `SKILL_CODE_REVIEW` fallback
  exactly like Azure. A BOUNDED-WAIT rule (default 10 minutes after CI green)
  guarantees the sweep never waits forever.
- This repo declares `reviewer_bots: expected` (it has Copilot + Codex),
  preserving its existing bot-sweep behavior. Prompt-diet ledger true-up
  (+1147 B credited 1:1, TEST-012 pin -11435 -> -10288); new tests
  TEST-019..022 plus an updated TEST-011 in test-aai-pr-platform.sh.

## [v2026.07.30] — chore(prompts): SUBAGENT_CONTRACT headroom — trim to 53 lines under the 60-line cap (CHANGE-0095-contract-headroom) [L1]

- `.aai/SUBAGENT_CONTRACT.md` sat at exactly 60/60 lines against SPEC-0094's
  hard `<=60`-line cap (enforced by test-aai-role-output.sh TEST-010 and
  test-aai-hygiene-pack.sh TEST-001), so the next clause addition would silently
  breach it. Compressed only prose (intro pointer, timing bullets, usage-note,
  single-writer rationale) from 60 to 53 lines — no pinned or load-bearing
  clause lost. The frozen `subagent_result:` YAML skeleton stays byte-identical
  to `.aai/templates/BRIEF_TEMPLATE.md` (hygiene-pack TEST-002), and every
  spot-grepped token (STATE single-writer rule, `duration_seconds` match,
  `docs/ai/tdd/`, `append-event.mjs`, `check-role-output.mjs`, EXPECT pointer,
  rationalization table) survives verbatim. Added TEST-020 headroom guard
  (`<=54` lines, `>=6` below the cap) alongside the untouched `<=60` cap tests.

## [v2026.07.30] — fix(install): seed docs/ai/update-config.yaml when missing (CHANGE-0094) [L2]

- Completes the auto-update feature's discoverability. The auto-update ride
  shipped `.aai/scripts/update-check.mjs` and the SessionStart hook, but the
  LOCAL policy file `docs/ai/update-config.yaml` was never installed by
  `aai-sync` — `docs/ai/` was only PRESERVED, so the `auto` opt-in knob stayed
  hidden. Both sync engines (`aai-sync.sh` and `aai-sync.ps1`) now SEED
  `docs/ai/update-config.yaml` from the new
  `.aai/templates/update-config.template.yaml` (documented default:
  `mode: notify`, `throttle_hours: 24`, with the full key comments) ONLY when
  the target's copy is MISSING — an operator's edited policy is preserved
  byte-for-byte, mirroring the `docs/TECHNOLOGY.md` seed-when-missing pattern.
  The template is classified in PROFILES core (layer-profiles union intact),
  and the ps1-quality Windows PowerShell 5.1 functional smoke asserts the seed
  lands on a fresh target.

## [v2026.07.29] — fix(auto-update): atomic O_EXCL sync-lock + stale-reclaim closes RR-1/RR-2 (CHANGE-0093) [L2]

- Fast-follow to the auto-update ride
  that CLOSES the two cross-process TOCTOU races accepted as documented
  residuals in `docs/ai/decisions.jsonl` (2026-07-29): RR-1 — the
  `running`-marker concurrent-sync guard had no OS-level lock, so N truly-
  simultaneous same-repo session starts each spawned a detached `aai-update`
  sync (empirically 5 parallel -> up to 5 syncs); RR-2 — once-only outcome
  surfacing could print the "applied" line more than once under the same
  window. RR-1 is fixed with a genuinely atomic claim: before spawning, the
  auto path creates `.aai/cache/update-sync.lock` (a SEPARATE file from the
  pre-existing outcome log) by writing a per-pid temp with the full owner token
  then `fs.linkSync`ing it into place — O_EXCL-equivalent (EEXIST if the target
  exists) with full content the instant it appears (no torn window); on a
  filesystem that disallows hard links it FALLS BACK to
  `fs.openSync(..., 'wx')` (O_CREAT|O_EXCL) so the claim still works. Exactly
  one caller creates the lock and spawns; the losers get EEXIST and back off to
  the existing "in progress" path (no duplicate spawn). A GENUINE claim error
  (e.g. EACCES) is surfaced as a loud, non-fatal skip — never a silent no-op
  masquerading as "in progress". The detached child releases the lock by OWNER
  TOKEN, so a sync that outlived the stale window never deletes a reclaimer's
  fresh lock. RR-1 is closed for BOTH
  cold start AND concurrent STALE-lock RECLAIM: reclaim (which must remove the
  existing lock before re-claiming, so a lone O_EXCL create cannot arbitrate it)
  is serialized behind a short-lived exclusive reclaim lock whose holder
  re-checks staleness after gaining exclusivity, so N racers reclaiming one
  stale lock spawn exactly one sync; and locks are created with FULL content
  atomically (a per-pid temp written then `linkSync`ed into place) instead of
  `openSync('wx')`+`writeSync`, eliminating the torn (created-but-empty) window
  in which a concurrent reader would mis-age a live lock. The detached child
  removes the lock when the sync finishes (success or failure); a crashed sync
  leaves a stale lock that the SAME >30min `SYNC_STALE_MS` window reclaims
  (future-dated / clock-skewed locks reclaim too, via a symmetric staleness
  window that never falsely reclaims a live racer), so auto mode NEVER wedges.
  RR-2 is fixed with an atomic rename claim around outcome
  surfacing so simultaneous sessions surface a finished outcome at most once;
  sequential behavior is unchanged. All prior semantics intact (detached-to-
  completion, report-next-session, source agreement, notify default, canonical
  refuse, offline degrade, throttle + self-heal, future-date guards). The lock
  lives in gitignored, PROFILES-excluded `.aai/cache/`. Suite:
  `tests/skills/test-aai-update-check.sh` (+8 tests, now 31; true-parallel
  single-invocation, lock-reclaim, concurrent-surfacing, an amplified
  CONCURRENT stale-lock reclaim case, a surface-restore-on-read-failure unit
  check, plus a bot-sweep fix set: linkSync-unsupported wx fallback with a
  genuine-error loud-skip, owner-scoped lock release, and stale orphaned-claim
  recovery; deterministic, zero real network).

## [v2026.07.29] — feat(auto-update): config-driven new-release notify + opt-in detached auto-sync (CHANGE-0091 / SPEC-0106) [L2]

- A target project
  now learns a newer AAI release exists as a SIDE EFFECT OF NORMAL USE: the
  existing SessionStart hook runs a best-effort, provably non-blocking check.
  Governed by a committed local config `docs/ai/update-config.yaml` (absent ==
  notify default, back-compat): `mode: notify` (default, safe) surfaces a
  "newer AAI release available" line and changes nothing; `mode: auto`
  (opt-in) applies the `aai-update` sync DETACHED so it NEVER blocks session
  start and NEVER loses the outcome — the sync runs in its own session/process
  group and its result (applied / failed / refused) is REPORTED ON THE NEXT
  session start ("auto-update applied … — review the diff"), recorded in a
  persistent outcome log under gitignored `.aai/cache/`; a synchronous
  `running` marker guards against a duplicate concurrent sync. Detection and
  sync are REUSED verbatim — `layer-drift.mjs` for the verdict,
  `aai-update.{sh,ps1}` for the sync incl. its canonical-repo guard (never
  auto-syncs the source of truth); no parallel engine. Offline degrades to a
  "could not check" note; an unknown mode is rejected on stderr and falls back
  to notify (a typo never auto-syncs); a `throttle_hours` window (default 24h,
  cache in gitignored `.aai/cache/update-check.json`) skips redundant probes,
  and a future-dated or unparseable cache timestamp self-heals (forces a probe
  instead of throttling forever). Bot-review hardening: auto-sync now runs
  against the SAME source layer-drift verified (the resolved pin/verdict remote,
  never a hardcoded default) so a pin naming an alternate canonical can't be
  overwritten from an unrelated upstream; the detached sync runs to COMPLETION
  with no watchdog (a slow clone is never SIGKILLed mid-copy into a partial
  layer); on Windows the check prefers `pwsh` and falls back to `powershell.exe`
  (PS 5.1) instead of ENOENT; a failed-sync message points at `git status` /
  `git diff` rather than falsely claiming nothing changed; `throttle_hours` is
  validated strict digits-only; a future-dated `running` marker no longer wedges
  the concurrent-sync guard. New `.aai/scripts/update-check.mjs` (core profile).
  Suite: `tests/skills/test-aai-update-check.sh` (23 tests, zero real network).

## [v2026.07.29] — fix(install): Windows PowerShell 5.1 sync fails copying .codex/.gemini skills (CHANGE-0092) [L2]

- A field install via `irm install.ps1 | iex` on Windows
  PowerShell 5.1 aborted with `Copy-Item ... DirectoryNotFoundException` on
  `.codex\skills`: 5.1's `Copy-Item -Recurse <dir> <nonexistent-dst>` does not
  create the destination root before copying a top-level file into it, and
  `.codex/skills` + `.gemini/skills` carry a top-level `README.md` alongside
  skill subfolders (PowerShell 7 and the bash installer are unaffected, so Linux
  CI and the 5.1 parse-check never caught it). `Copy-Replace` now creates the
  destination root first, then copies contents (version-safe on 5.1 and 7). The
  `ps1-quality` windows-5.1 CI job gained a FUNCTIONAL `aai-sync.ps1` smoke into
  a fresh target (a parse-check could not catch a runtime copy behavior).

## [v2026.07.29] — refactor(prompts): core-prompt diet — dedup into ROLE_COMMON + drop dead SKILL_TDD prose (CHANGE-0090) [L2]

- Folded four cross-prompt duplications
  (FRICTION HOOK, PYTHON MONTY SCRATCHPAD, PRE-HANDOFF AC-TABLE RECONCILIATION,
  WORKTREE GATE) into `.aai/ROLE_COMMON.md` as canonical blocks, pointer-ized
  the owning prompts, and deleted three dead SKILL_TDD prose sections — a net
  −3247 B corpus reduction with headroom held in-cap. New TEST-019 grep-contract
  pins dedup-once + surviving recipes; anti-dedup hostile pins (check-state
  INV-14, implementer AC-table literals) kept verbatim. Behaviour-preserving:
  no contract, fail-closed rule, exit-code branch, or CLI recipe lost.

## [v2026.07.28.1] — chore: product capability refinements — delivered_by provenance + telemetry consolidation (CHANGE-0089) [L2]

- delivered_by in the migrated product docs was seeded with the capability
  slug (tautological with the filename); reseeded each to its real work-item
  CHANGE ref (frontmatter-only, bodies byte-unchanged).
- Telemetry consolidation: the three per-ride product docs (token-capture-
  canary, prompt-hash-telemetry, token-economics-end-to-end) merged into one
  docs/product/telemetry.md keyed by the "telemetry" capability
  (delivered_by = CHANGE-0058/0070/0063) — the per-capability-not-per-ride
  consolidation the CHANGE-0088 model was built for. Content-coverage review
  caught 3 dropped how-to/contract claims; all restored (no user-facing
  loss). TEST-012's hardcoded >=12 doc-count floor delinted to per-doc
  invariants over the live set.

## [v2026.07.28.1] — feat: product docs become a capability-keyed doc family on shared engine primitives (CHANGE-0088 / SPEC-0105, fixes #189) [L2]

- Product docs were invisible to the doc engines (not in INDEX, not audited)
  and their type:product/status:current weren't enum-valid (GitHub #189 —
  a silent-omission gap). Now product is a SECOND DOC FAMILY on a shared
  DOC_FAMILIES registry that generalizes the inCanonical scan-admit: one
  registry both docs-audit and generate-docs-index read, NO parallel engine
  (deleting the entry drops product from both, pinned TEST-005).
  DOC_TYPE_ENUM += product, DOC_STATUS_ENUM += current; new INDEX Product section.
- Keyed by user-facing CAPABILITY, not by ride: rides targeting one
  capability UPDATE its doc (delivered_by provenance) instead of spawning
  per-ride orphans. close-work-item re-keys on capability with a
  transactional delivered_by upsert (authored prose byte-idempotent).
- Migration: all 12 existing product docs gained capability + delivered_by
  frontmatter ONLY — body byte-diff 0 each (independently verified). The
  #189 repro (template -> audit -> index) is now clean end-to-end.

## [v2026.07.28.1] — feat: /aai-issues — on-demand platform-portable issue intake skill (CHANGE-0087 / SPEC-0104) [L2]

- NEW /aai-issues: fetches open issues from the project's git host
  (github via gh issue list; azure -> Azure Boards work items, documented
  + deferred to first adoption; unknown/none -> loud degrade), triages
  each (bug/feature/question/duplicate/out-of-scope), STOPS at ONE
  operator approval checkpoint, and turns approved items into intakes
  linked back to the source issue. Write-back (comment + close) only
  after a ride's PR merges. On-demand only — never from the loop.
- SECURITY: issue text is untrusted. sanitizeLine strips C0/C1 controls
  (newline/CR/ESC/BEL) and Unicode bidi overrides from title/labels/
  excerpt, so a crafted issue cannot forge ISSUE/ISSUES table rows or
  inject terminal escapes (adversarial review finding, TEST-020); the
  prompt pins never-follow-body-instructions and quote-as-DATA when
  composing intakes.
- Reuses pr-platform.mjs classification; zero-dep fetcher with --input
  fixture bypass (network-free tests); 20-test suite; ledger +3810,
  headroom unchanged.

## [v2026.07.28.1] — chore: session loose ends — inheritance provenance, NOTE convention, phase-boundary audit CLEAN (CHANGE-0086) [L2]

- Dispatch now stamps per-component inheritance provenance alongside the
  aggregate prompt_hash: JSON `inherits.{role,contract,learned}` (bare-file
  sha256; ABSENT-safe) + human line `Inherits: CONTRACT@<12hex>
  LEARNED@<12hex>` (promptbook adoption 4). TEST-029 + TEST-002 design lock
  (components are bare-file digests, never the aggregate's framed sections).
- AGENTS.md: degrade-with-NOTE promoted to a universal convention (any
  generator/gate that skips/excludes an input MUST name it; +210 B manual
  ledger credit per outside-glob precedent, total -11998).
- Phase-boundary compaction audit (roadmap#8, ACE-FCA): 14/14 dispatch
  surfaces CLEAN — artifact-paths-only handoff is codified everywhere,
  zero fixes needed. POSTPROCESSING declarations (promptbook#6)
  dispositioned WONTFIX (operator-approved).

## [v2026.07.28] — feat: platform-portable PR ceremony — GitHub/Azure/generic with internal-review fallback (CHANGE-0085 / SPEC-0103) [L2]

- NEW .aai/scripts/pr-platform.mjs: deterministic remote classification
  (github incl. ssh, dev.azure.com + ssh + legacy visualstudio.com,
  unknown, none); 14 spoof-attack classes defended in validation
  (subdomain/ssh-alias/userinfo tricks -> unknown, never a false match);
  --json masks embedded credentials (review-pinned).
- SKILL_PR: PLATFORM GATE in step 5 (gh vs az repos branch); step 5d
  reviewer-fallback contract — on a platform without reviewer bots the
  internal SKILL_CODE_REVIEW dispatch is REQUIRED before merge-readiness,
  findings are PUBLISHED as PR threads with closing replies, and the PR
  records "internal review substituted for absent bot layer"; GENERIC
  MODE for any other git host (mandatory internal review, findings into
  repo artifacts, loud "merge is yours" handoff). Operator decisions
  2026-07-28.
- Azure live command forms deferred honestly (Spec-AC-06, Review-By
  2026-08-15; thread publication via az devops invoke pullRequestThreads
  is the concrete item to verify at first adoption).

## [v2026.07.28] — chore: follow-ups batch B — stalled_progress friction class, EARS AC guidance (CHANGE-0084) [L1]

- NEW seventh friction failure_class `stalled_progress` (dead-watcher
  parking, artifact-that-never-comes waits, no-state-change loops) across
  the taxonomy doc and all three enum sites; TEST-020 pins accept+reject.
- SPEC_TEMPLATE AC guidance: testable Description cells in EARS form
  (WHEN trigger the system SHALL response — Kiro pattern).
- Disposition recorded: metrics-report per-run hash display is
  resolved-as-designed (SPEC-0096 conditional grouping preserves report
  additivity; always-on variant stays rejected).

## [v2026.07.28] — chore: follow-ups batch A — single STATE creator, reaper raw capture, structured migration verdict (CHANGE-0083) [L2]

- autonomous-loop.sh create_state_file() delegates to check-state --repair
  (the canonical template path); the drifted inline heredoc creator is
  gone and grep-pinned against reintroduction; fail-loud when the checker
  is unavailable (closes the SPEC-0099 residual early).
- aai-reap-tests.sh emits an additive `reaped raw:` diagnostic — the
  verbatim ps snapshot line per reaped pid, on both exit paths — so the
  next CI flake shows which column produced an impossible age (SPEC-0083
  AC-04 data capture; decision surface verified unchanged, TEST-023).
- aai-doctor.mjs migrationVerdict() returns {msg, ok}; CAT-10 aggregates
  on booleans — wording changes can no longer flip verdicts (and the
  refactor fixed a latent false-WARN the string matching had).

## [v2026.07.28] — chore: journal + validate-report contracts reconciled with practice (CHANGE-0080 + CHANGE-0082) [L1]

- Session journal (operator decision): the LIVING convention is canonical —
  date-slug files, free form in the discussion's language, 3-column INDEX.
  The strict format (SESSION-<slug>, 14-element template — used once and
  deleted the same day as redundant) is retired; PROJECT_SESSION_TEMPLATE
  pruned. NEW hygiene pin test_091: every journal file must have an INDEX
  row (RED-first — it caught the real missing universality-proof row).
- Validate-report (operator decision): stays a STANDALONE, ON-DEMAND
  presentation skill; prompt now says so explicitly, its artifacts
  (LATEST.md, screenshots/) are documented as existing only from its own
  runs, and the report naming unifies with the loop's
  VALIDATION-<ts>-<slug>.md pattern. TEST-018 pins both contracts.
- Ledger -2132 RECLAIMED (total -15485); headroom 605/2048 with the +31 B
  PR #180 slack provenance recorded.

## [v2026.07.28] — fix: userguide rollup names every excluded product doc (CHANGE-0075) [L1]

- `generate-userguide-rollup.mjs` now prints
  `userguide-rollup: EXCLUDED docs/product/<slug>.md missing=<sections>`
  for every placeholder-failing doc instead of silently rendering a lower
  count (universality-proof finding F2; no-silent-truncation principle).
  Marker-delimited output byte-unchanged; TEST-014 pin RED-first.

## [v2026.07.28] — feat: skills catalog goes deterministic — 34/34 live, regenerated at every close (CHANGE-0078 / SPEC-0102) [L2]

- NEW .aai/scripts/generate-docs-hub.mjs: parses SKILL.md frontmatter +
  prompt Goal sections mechanically, emits self-contained searchable
  docs/SKILL_CATALOG.html + skill-catalog-data.json; byte-idempotent;
  degrade branches emit visible NOTEs; unknown flag exits 2 writing
  nothing (review-pinned TEST-008). Replaces a ~70-file LLM fan-out whose
  hand-authored catalog had drifted to 27/35 skills.
- close-work-item.mjs regenerates the catalog best-effort at every close
  (mirrors overview/rollup pattern) — the staleness class is gone.
- SKILL_DOCS_HUB 9 513 B/328 lines -> 3 409 B/63; ledger -6099 RECLAIMED
  (total -13353), headroom 636/2048; 8-test suite; wrapper mirror texts
  aligned across all four agent trees.

## [v2026.07.28] — chore: dashboard + test-skills prompts refit — −21.5 KB corpus, no phantom flags (CHANGE-0076 / SPEC-0101) [L2]

- SKILL_DASHBOARD 19 173 B/652 lines -> 4 152 B/77: dropped the ~330-line
  stale duplicate dump of generate-dashboard.mjs, documents BOTH real input
  shapes (work-item ledger primary + legacy flat) and the tokens-null
  reality; unimplemented --publish removed (publishing = /aai-share).
- SKILL_TEST_SKILLS 9 218 B/404 lines -> 2 722 B: stale 11-skill example +
  pytest/cargo snippet out; live fleet discovery in; --fix honestly marked
  a no-op (review finding — same phantom-flag class as --publish).
- TEST-017 pins all of it; ledger -21517 RECLAIMED entry — total goes
  NEGATIVE (-7254), analyzed sound in review (the floor RISES; regrowth
  trips TEST-010 sooner, not later); headroom exactly 636/2048.

## [v2026.07.28] — feat: /aai-doctor determinized — 13 categories in one script, prompt −70 % (CHANGE-0079 / SPEC-0100) [L2]

- NEW .aai/scripts/aai-doctor.mjs: all 13 doctor categories computed
  deterministically (file/hook/telemetry/git checks; CAT-11/13 stay
  subprocess calls honoring documented exit semantics; CAT-06 delegates
  structural STATE rules to check-state.mjs and degrades a CRASHING helper
  to WARN, never a false BROKEN — review finding). One line per category,
  `--json`, exit 0/1/2 contract, cwd-independent; suite of 22 tests.
- SKILL_DOCTOR.prompt.md 10 697 B -> 3 163 B thin wrapper; disclosed
  narrowings only (CAT-01 YAML validity moved to CAT-06; CAT-06 full
  invariants stay with /aai-check-state). Ledger -7534 RECLAIMED entry,
  TEST-012 pin 21738 -> 14204 RED-first, headroom 636/2048.
- Companion tests rewired to behavioral asserts (no JS source greps).

## [v2026.07.28] — chore: decapod integration pruned — only true dead code found by the skill-sweep (CHANGE-0077) [L2]

- Removed ~55 KB: SKILL_DECAPOD.prompt.md (9571 B file; ledger retires 9573 B incl. 2 B prior reword slack), 3 wrapper dirs,
  DECAPOD_INTEGRATION.md, docs/ai/compliance/*, config example, plus every
  live-tree pointer (AGENTS.md dispatch row, SKILLS.md, wrapper READMEs,
  USER_GUIDE section, copilot-instructions). The external `decapod` CLI was
  never shipped; zero consumers since 2026-03 (skill-sweep group C
  evidence). Git history is the archive.
- Governance: ledger -9573 RECLAIMED negative entry (precedent: SPEC-0059
  reconciliation), TEST-012 pin 31311 -> 21738 RED-first, headroom back to
  636/2048; layer-profiles 100% invariant holds (186 files).

## [v2026.07.28] — feat: STATE bootstrap template — virgin targets init mechanically (CHANGE-0074 / SPEC-0099) [L2]

- Universality-proof F1 closed: `.aai/templates/STATE_TEMPLATE.yaml` is now
  the TRACKED canonical schema source (the live docs/ai/STATE.yaml is
  gitignored on fresh checkouts, so it could never serve as the baseline),
  and `check-state.mjs --repair` creates a missing STATE from it —
  script-relative template resolution (symlink/cwd-attack proof), real UTC
  stamp, fail-loud on absent/unstampable template (exit 2/1, pinned
  TEST-006/007), existing-file behavior byte-unchanged.
- A fresh target's first dispatch now proceeds to `no_focus_ref` instead of
  dead-ending on `state_file_missing`. Ledger +286 B (SKILL_CHECK_STATE
  reword), TEST-012 pin 31311 RED-first.

## [v2026.07.28] — fix: skill-sweep batch — three verified tooling footguns + six findings intakes (CHANGE-0081) [L2]

- Hands-on sweep of ~20 previously untouched skills (three parallel
  auditors). Fixed with live repros: aai-canonicalize.sh crashed macOS
  default bash 3.2 on empty detection arrays (now empty-safe AND the
  "Not detected" defaults still render — the first fix idiom regressed
  them, caught by review); test-canon.mjs --help/typo'd flags silently ran
  a LIVE proposal-writing phase 1 (usage branch, exit 0/2, TEST-020);
  generate-dashboard.mjs positional args silently overwrote
  docs/ai/dashboard.html (consumed-slot booleans); bonus: pre-existing
  $ROOT$ROOT path doubling silently skipped the YAML->JSONL migration.
- Findings filed: CHANGE-0076..0080 + CHANGE-0082 (dashboard-refit,
  decapod-prune, docs-hub-generator, doctor-determinize,
  session-journal-contract, validate-report-contract). Legacy-prune
  roadmap item resolved with evidence: only decapod is dead.

## [v2026.07.28] — fix: suite-map maps factory doc trees — factory rides actually get selected mode (CHANGE-0073) [L1]

- CI impact selection (CHANGE-0071) fail-opened on every factory PR because
  generated/ledger doc paths (docs/INDEX.md, EVENTS/METRICS ledgers,
  USER_GUIDE, overview, session journals) had no map row. Each now maps to
  its natural owner suite; a typical ride doc-set selects 3 core + ~7 owner
  suites (DROPPED 45) instead of a 55-suite full run. Data-file-only;
  fail-open, always-on core, post-merge full gate and nightly unchanged.

## [v2026.07.28] — feat: prompt-hash runtime wiring — the loop records the hash dispatch computes (CHANGE-0072 / SPEC-0098) [L2]

- SKILL_LOOP's append-run boilerplate now instructs the orchestrator to pass
  the dispatch's full-hex `prompt_hash` (JSON field, not the truncated
  12-char display) as `--prompt-hash` — closing the consumer gap left by
  SPEC-0096: METRICS rows gain non-null prompt_hash from the next ride on.
- Prompt-corpus governed: +131 B exact ledger entry, TEST-012 pin
  30894 -> 31025 (RED-first), TEST-016 grep contract; ORCHESTRATION
  untouched at its 40/40-line cap.

## [v2026.07.28] — feat: CI test impact selection — PR pushes run affected suites, full framework moves to merge + nightly (CHANGE-0071 / SPEC-0097) [L2]

- PR CI now runs only the suites whose watched paths the diff touches
  (declarative `tests/skills/suite-map.yaml`, one row per suite, hygiene-
  pinned) plus a 3-suite always-on core; typical PR drops from ~25 min /
  55 suites to a targeted subset. The full framework moves to push-to-main,
  nightly cron, and an on-demand `ci-full` label.
- Fail-open safety: `.aai/scripts/select-suites.mjs` escalates to FULL_RUN
  whenever any changed path is unmapped, touches `.aai/scripts/lib/**`, or
  exactly matches a `protected_paths_l3` entry (read live from
  docs/ai/docs-audit.yaml); its own errors (malformed map, hostile core
  name, bad base-ref) degrade to `FULL_RUN reason=internal-error` with
  exit 0 — the selector can never fail or silently narrow the build.
- Auditable output: every `SELECTED` line names the matching path, one
  exact `DROPPED <n>` line — no silent truncation.
- Branch-protection continuity: an aggregating `gate` job keeps the
  pre-split required-check name and fails unless the mode-relevant leaf
  job succeeded (review finding, TEST-018).

## [v2026.07.28] — feat: prompt-hash telemetry — content-addressed identity of role instructions (CHANGE-0070 / SPEC-0096) [L3]

- Promptbook-inspired (adoption candidate 3): every orchestrated run can
  record a sha256 of the EFFECTIVE instructions it ran under (role prompt +
  SUBAGENT_CONTRACT + LEARNED snapshot) via the new additive append-run
  --prompt-hash flag; flush passes it to METRICS byte-unchanged;
  metrics-report groups runs by instruction version; dispatch prints the
  advisory hash. "Did this role change between run A and B" is now a
  mechanical query.
- L3 discipline: append-run byte-identical when the flag is absent (proven
  main-vs-branch by the independent validator); bad hex writes nothing.

## [v2026.07.28] — feat: learned-append gate — structurally enforced append-only self-learning (CHANGE-0069 / SPEC-0095)

- Promptbook-inspired (adoption candidate 2): the only sanctioned automated
  path to docs/knowledge/LEARNED.md is .aai/scripts/learned-append.mjs —
  persist ONLY when result == original + pure append (byte-exact), else
  exit 1 with nothing written (tree-hash proven). Atomic temp+rename,
  dry-run zero-write, house-format stamping.
- Wrap-up routes every proposed rule through a critic pass BEFORE the gate
  (ordering test-pinned); no self-improvement step can silently rewrite
  prior rules. Guardrail, not a security boundary (hand edits unaffected).

## [v2026.07.28] — feat: role output contracts — deterministic EXPECT validation of subagent results (CHANGE-0068 / SPEC-0094)

- Promptbook-inspired (adoption candidate 1): every dispatched subagent's
  result block is now validated by .aai/scripts/check-role-output.mjs —
  no model call, machine-readable ROLE-OUTPUT-VIOLATION lines, exit 0/1,
  one reject-and-re-prompt before any STATE merge. Seven violation codes
  incl. the negative-duration corner (review-hardened).
- EXAMPLE fixtures per role class run in CI (new test-aai-role-output.sh);
  SUBAGENT_CONTRACT carries a one-line EXPECT pointer (60-line cap held).

## [v2026.07.28] — feat: dev-progress view — the overview shows what the factory is doing right now (CHANGE-0067 / SPEC-0093)

- generate-overview.mjs gains an "In flight now" section: current focus
  (ref/type/phase/strategy/worktree), validation/review verdict chips, and
  the last 5 loop ticks newest-first — sourced from local STATE.yaml and
  LOOP_TICKS.jsonl with graceful omission on a fresh clone.
- Adversarially leak-tested: STATE free-text fields (notes, rationale,
  questions) never render; only enum/known scalars. Malformed tick lines
  are skipped without consuming a display slot.

## [v2026.07.28] — feat: product docs enforced at close + generated USER_GUIDE rollup (CHANGE-0066 / SPEC-0092)

- close-work-item.mjs gains a pre-write product-doc gate: a primary
  work-item doc opting in with `user_visible: true` must carry a real
  docs/product/<ref>.md (every required section filled, not left as an
  unfilled template placeholder) or the close warns loudly by default
  (`product_doc_gate: report-only`) or refuses outright, nothing written
  (`product_doc_gate: enforce`, new exit code 3). Absent `user_visible`
  stays byte-for-byte unaffected (fail-open, legacy-safe).
- New .aai/scripts/generate-userguide-rollup.mjs renders a marker-delimited
  "Delivered features (generated)" section in docs/USER_GUIDE.md from
  docs/product/*.md, sorted by `updated` descending, byte-idempotent
  (no timestamps inside the marker), placeholder docs excluded. Invoked
  best-effort as the last step of a successful close, mirroring the
  overview-regen hook (a generator failure never changes the close exit
  code).
- guard-config.mjs GUARD_DIALS extended with `product_doc_gate`; PROFILES.yaml
  classifies the new generator (extended) and its shared predicate module
  lib/product-doc.mjs (core, since close-work-item.mjs imports it).
  Refs: CHANGE-0066, SPEC-0092.

## [v2026.07.28] — feat: cheap-model routing in practice — lane-aware role overrides, Haiku for mechanical roles (CHANGE-0065 / SPEC-0091)

- MODEL_ROUTING roles map now supports the lane-aware key form
  role@lane (resolution: roles[role@lane] then roles[role] then
  tiers[tier] then null; validator-independence swap still applied last).
- Shipped pins: Metrics Flush -> claude-haiku-4-5 (first real cheap-tier
  binding — the per-role token rollup showed 0 haiku tokens across 15.9M
  recorded), Validation@lightweight -> claude-sonnet-5 (explicit, auditable;
  zero behavioral delta today by design — mechanism proven via sentinels).
- decide()/RULES/deriveLane byte-identical to main (validator-verified).
  Refs: CHANGE-0065, SPEC-0091.

## [v2026.07.28] — feat: allocator rewrites DRAFT references in all committed-class trees (CHANGE-0064 / SPEC-0090) [L3]

- allocate-doc-number.mjs now rewrites DRAFT->numbered references across ALL
  committed-class markdown trees (docs/product, docs/ai/reviews,
  docs/project-sessions, docs/knowledge, README, CHANGELOG) behind exported
  REWRITE_TREES/EXCLUDED_TREES constants — removing a recurring class of bot
  findings (10+ hand-sed fixes across PRs #158-#163) at the source.
- L3 protected-surface discipline: matcher byte-identical to main (verified
  independently), mutation-tested separator guard + committed TEST-109 probe,
  symlink no-escape, dry-run per-tree report, idempotence proven. First live
  run rewrote this very scope's own references with zero manual fixes.
  Refs: CHANGE-0064, SPEC-0090.

## [v2026.07.28] — feat: token economics end-to-end — reports and overview read real usage (CHANGE-0063 / SPEC-0089)

- metrics-report now aggregates the canonical usage_total_tokens markers:
  per-item "agent tokens (undecomposed)" column + a Per-Role Token Rollup
  (first live read: 35 items, 15.27M tokens; TDD Implementation 4.83M,
  Planning 3.50M). Tokens only — never a fabricated USD from an
  undecomposed total.
- Stakeholder overview shows tokens per delivered feature + grand total,
  groups Delivered by release (links.members frontmatter) with close-month
  fallback, and REGENERATES ITSELF at every successful close-work-item run
  (strictly best-effort — EISDIR-rig proven not to touch the close verdict).
- New single-source marker helper .aai/scripts/lib/usage-note.mjs (flush,
  report, overview all import it; grep-contract forbids literal reappearing).
  Refs: CHANGE-0063, SPEC-0089.

## [v2026.07.28] — feat: friction feedback loop activated — default-on capture + wrap-up triage (CHANGE-0062 / SPEC-0088)

- The RFC-0012 self-improvement loop had complete infrastructure and ZERO
  data (recall-dependent seam; planning root-caused all four of this
  session's real frictions as predictably missed). Capture is now the
  DEFAULT action at four deterministic hook points: validation FAIL,
  remediation dispatch, canon-file gate/lint/CI failure, and canon-surface
  check failure during implementation (the headroom-cap-trap class, added
  as the validation R2 disposition).
- SKILL_WRAP_UP step 6: a non-empty spool ALWAYS yields the offline triage
  report + proposed-intake one-liners; empty spool stays silent. Capture
  remains best-effort and never touches a primary exit code (negative
  controls TEST-011/016).
- First real observation recorded (prompt-diet headroom-cap trap) — the
  loop finally has data. Ledger +1881+453 B itemized (pin 30139).
  Refs: CHANGE-0062, SPEC-0088.

## [v2026.07.28] — refactor: subagent contract split — per-dispatch payload slimmed (CHANGE-0061 / SPEC-0087)

- New `.aai/SUBAGENT_CONTRACT.md` (58 lines): the ONLY per-dispatch payload a
  spawned subagent receives — result block + timing rules, single-writer
  duty, allowed-write list, self-report-usage prohibition. The 223-line
  SUBAGENT_PROTOCOL.md becomes orchestrator-side only (merge protocol,
  review anti-gaming, validator spawning, harness-usage capture) — a unit
  no longer pays ~2k words for ~400 words of duty, 4-6 times per work item.
- Validation FAIL round earned its keep: caught IMPLEMENTATION.prompt.md:121
  still injecting the full protocol into parallel unit payloads + two
  dangling result-block refs; remediated and permanently pinned by an
  extended hygiene TEST-082. Refs: CHANGE-0061, SPEC-0087.
## [v2026.07.28] — feat: SKILL_PR step 5d — post-open bot-review sweep before merge-readiness (CHANGE-0060)
- Codifies the PR-level review-response discipline as canon: after
  `gh pr create` + CI, poll bot inline comments (they never appear in
  `gh pr checks`), fix legitimate findings on the same branch or rebut them
  in a PR comment (never silent), push a review-response commit with one
  summary comment, and wait for the CI re-run before any merge-readiness
  claim. Merge stays operator-only.
- Evidence base: PR #158 (7 real bot findings) and #159 (3 + a fix-of-fix)
  — previously held only by session memory. Ref: CHANGE-0060.

## [v2026.07.28] — refactor: prompt dedup — canonical includes for ceremony rules, AC gate, role boilerplate (CHANGE-0059 / SPEC-0086)

- Prompt corpus shrinks 4687 B in the TEST-010 glob (net −3021 B): the
  ceremony-level table now lives ONLY in WORKFLOW.md (PLANNING/VALIDATION
  carry pointers), the VALIDATION AC gate delegates Rules 1/2/4-format to
  `docs-audit.mjs --gate` (Rule 3 + the 14-day anti-cheat window correctly
  RETAINED as prose — the script does not compute them), and the 5 copies of
  the D5 metrics carve-out fold into one `.aai/ROLE_COMMON.md`.
- Removes the divergence risk of two gate definitions for unattended runs;
  every role spawn now pays fewer duplicated context bytes.
- Prompt-diet ledger reconciled with a NEGATIVE −3021 B entry (29802 → 26781);
  grep-pinned stanzas retargeted to the pointer form. Refs: CHANGE-0059,
  SPEC-0086.

## [v2026.07.28] — feat: token-capture canary — loud telemetry-capture gaps (CHANGE-0058 / SPEC-0085)

- `metrics-flush.mjs` now classifies every agent run three ways — `decomposed`
  (numeric tokens), `undecomposed-note` (`usage_total_tokens=<N>` in the run
  note → INFO, cost unattributable by design), `capture-missing` (no numbers
  AND no note → WARNING, the real defect class) — replacing the single
  undifferentiated null-token warning. 255 nulls become a triaged signal.
- `state.mjs log-tick` emits loud stderr WARNINGs when the computed duration
  is 0 (caller passed a log-time `--started`) or when `--harness` is omitted
  — the two silent regressions observed across all 2026-07-25 ticks. Warn,
  never block: exit codes and written lines are unchanged.
- `SUBAGENT_PROTOCOL.md` merge protocol + `SKILL_LOOP.prompt.md` step 4 make
  recording the harness's undecomposed total MANDATORY whenever one is
  visible; D3 prose reclassified WARNING→INFO for honest totals.
- Reframed two stale L3 "landmine" stanzas (`test-aai-hitl-propagation.sh`
  TEST-014, `test-aai-tdd-evidence.sh` TEST-005) that froze a prior scope's
  one-time zero-diff constraint into a permanent invariant: a touched
  protected path now passes iff a frozen `ceremony_level: 3` spec ships in
  the same diff (anti-drive-by teeth preserved, verified by negative arms).
- Evidence: independent L3 validation PASS (framework 49/49), dual-verdict
  code review PASS/PASS (0 blocking). Refs: CHANGE-0058, SPEC-0085.

## [v2026.07.26] — docs: USER_GUIDE for docs-audit rollup / brief sweep + close RFC-0013 (CHANGE-0057)

- `docs/USER_GUIDE.md` gains a "Docs health & umbrella progress (docs-audit)"
  section documenting the `- Rollout:` line + `### Rollout progress` table
  (CHANGE-0055), the Rollout-Status-guarded closeout candidates (CHANGE-0056), and
  the stale-brief sweep (CHANGE-0054) — closing this session's operator-docs drift.
- Closes the completed **RFC-0013** (schema v2 + redaction): `implementing → done`
  (all proposals + its child spec done; it was a closeout candidate). RFC-0012's
  rollup consequently reads 11/11.

## [v2026.07.26] — fix: closeout candidate display-id match + Rollout guard (CHANGE-0056)

- `docs-audit`'s closeout-candidate pass ("all this umbrella's specs are done →
  suggest closing it") had the same latent bug CHANGE-0055 fixed for the rollup: it
  matched a child's reverse `links.rfc` against the parent's SLUG id only, while
  children link by DISPLAY id — so for a real slug-id RFC it resolved no children
  and never fired. Now matches on slug id OR display id.
- To avoid over-firing, closeout now SKIPS any umbrella whose body declares a
  `## Rollout Status` roadmap with a not-`done` phase (new
  `hasUnfinishedRolloutPhases`, Status column located by header name). Net effect on
  the real repo: RFC-0013 is now correctly suggested for close; RFC-0012 (phases 3-5
  not started) is correctly withheld. Report-only; 2 new tests, RED-proofed.

## [v2026.07.26] — feat: umbrella progress rollup + RFC Rollout Status (CHANGE-0055)

- `docs-audit` now surfaces an in-flight umbrella's PROGRESS, which its coarse
  `status: implementing` never showed. Every run prints a `- Rollout:` line
  (e.g. `RFC-0012 10/11 · RFC-0013 2/2`) and `--list` adds a `### Rollout progress`
  table — done/total child docs per non-terminal rfc/prd parent, matched on BOTH
  the slug id and the numbered display id (children link by display id). Report-only.
- RFC-0012 and RFC-0013 gain a human-maintained `## Rollout Status` phase/proposal
  roadmap (captures not-started phases the automatic rollup can't see); RFC_TEMPLATE
  ships a stub for future umbrellas.
- **Parser fix (root cause):** `parseFrontmatter` dropped `links.rfc` /
  `links.requirement` whenever the `links:` block also held a block-style list
  (`pr:\n  - 147`) — a block-list item clobbered the whole nested object, silently
  breaking every reverse-link consumer (the rollup AND closeout detection). Now
  tracks the nested key so block-list items attach correctly. No test regression.

## [v2026.07.26] — chore: AAI-level stale-brief sweep (CHANGE-0054)

- New `.aai/scripts/prune-stale-briefs.mjs` sweeps stale work-item briefs
  (`docs/ai/briefs/<REF-ID>.md`, gitignored Planning handoffs) across the repo in
  one pass, wired into `/aai-wrap-up` (step 6b) so every AAI project sweeps its own
  briefs at session end. It prunes only briefs whose work item is terminal
  (`done|deferred|rejected|superseded|legacy`) or orphaned, and KEEPS every brief
  whose item is still open (a live handoff). `--dry-run`/`--json`, `.gitkeep`
  preserved, exit 0 always. Complements CHANGE-0052's per-close prune (which never
  cleaned the backlog). Fixture suite: `test-aai-prune-stale-briefs.sh`.

## [v2026.07.26] — chore: close-work-item brief auto-cleanup (CHANGE-0052)

- The deterministic close ceremony (`.aai/scripts/close-work-item.mjs`) now prunes
  each closed doc's Planning-emitted work-item brief (`docs/ai/briefs/<REF-ID>.md`,
  both the slug- and display-id-named forms) once the close is durably
  self-verified. Briefs are gitignored runtime handoff
  artifacts; pruning at close keeps the dir scoped to in-flight work with no
  operator action. Best-effort: a missing brief / unlink error never fails the
  close (it runs downstream of self-verify), a path-escape guard blocks any ref
  that could reach outside `docs/ai/briefs/`, and the pruned brief(s) are named in
  the success line. Regression test: TEST-013 in `test-aai-close-work-item.sh`.

## [v2026.07.26] — feat: RFC-0012 friction feedback discovery + gh auth preflight + user docs (CHANGE-0051 / SPEC-0084)

- Makes the friction feedback loop VISIBLE and USABLE for a human operator (it was
  built but undiscoverable). New offline `.aai/scripts/aai-feedback-status.mjs`
  reports captured observations, drafts pending `--confirm`, and whether GitHub
  `gh` is authenticated (read-only `gh auth status`) + the next command — silent
  when nothing is captured.
- `/aai-wrap-up` now surfaces that nudge at session end. `aai-feedback-upsert.mjs`
  gains a `gh auth` preflight so publishing gives a clear up-front `run: gh auth
  login` instead of only failing reactively (the engine still holds no token — it
  borrows the operator's authenticated `gh` session).
- `docs/USER_GUIDE.md` gains a "Friction feedback loop" section documenting the
  capture -> discover -> triage -> prepare -> review -> `--confirm` workflow, the
  `gh auth login` prerequisite, and what is / isn't stored.

## [v2026.07.26] — fix: reaper CI-load flake root-cause — pre-epoch impossible-age clamp (CHANGE-0053)

- Root-cause fix for the recurring CI-load-only reaper flake in BOTH directions
  (`test-aai-run-tests.sh` TEST-018 legacy spare-fresh + TEST-006/015/016 epoch
  over-reach). The #149 `reaped ages:` diagnostic caught it on CI:
  `208482=38109073018720` — a just-forked process aged at ~38 trillion seconds
  because a mid-fork `/proc` `start_time` race makes `ps` render etime as a huge,
  grammar-valid ~441M-day form the charset guard can't catch.
- `etime_to_secs` now (1) clamps any age `>= SNAP_NOW` to 0 — a process cannot have
  started before the Unix epoch, so an impossible age is a garbled etime and the
  match is SPARED (fail-safe) in both legacy and epoch modes — and (2) enforces the
  strict ps grammar (ss/mm 00-59, hh 00-23) so a bare multi-digit column-shift word
  is rejected. Impossible/unparseable ages resolve to a distinct `-1` sentinel the
  reaper skips before EITHER mode's threshold — folding to 0 would still reap under
  the documented default `MIN_AGE=0` (`0 >= 0`). Both only ever spare more, never
  reap more. TEST-022 extended (RED-proofed against the pre-change parser). This is
  the root-cause fix SPEC-0083 AC-04 tracks; its closure stays CI-authoritative
  (Review-By 2026-08-15) — the flake must stay gone across subsequent PRs.

## [v2026.07.26] — feat: RFC-0012 Phase 2c / Slice C — review-mode GitHub upsert (CHANGE feedback-upsert-review / SPEC spec-feedback-upsert-review)

- The first network slice, approval-gated. New `/aai-feedback-upsert` +
  `.aai/scripts/aai-feedback-upsert.mjs` turns the triage report's
  `review_candidate` clusters into transmit-redacted, deduplicated, budget-checked
  GitHub issue drafts. **A plain run writes NOTHING to GitHub** — it prepares
  drafts to `docs/ai/friction/pending-issues/` and prints the exact command.
- A GitHub issue is filed ONLY via an explicit human `--publish <fp> --confirm`,
  which re-runs the transmit redaction + budget check immediately before the write
  — the single mutating `gh` call site. `auto` is refused (locked); `local`
  prepares nothing.
- Transmit-pass redaction reuses `.aai/scripts/lib/aai-redact.mjs` (the second half
  of RFC-0013's double redaction); dedup via a `<!-- aai-friction:<fp> -->` marker;
  budget `max_new_issues_per_7d` (default 3, local ledger); pinned `destination`
  repo. The engine holds no token — it shells to an authenticated `gh`; missing gh
  degrades to prepare-nothing. Tests mock `gh` (no real network call).

## [v2026.07.26] — feat: RFC-0012 Phase 2 / Slice B — offline friction triage (CHANGE-0048 / SPEC-0081)

- The offline triage core, now that schema v2 gives it real signal. New
  `/aai-feedback-triage` + `.aai/scripts/aai-feedback-triage.mjs`: reads the local
  spool, applies hard gates (schema, AAI-ownership taxonomy, sanitization), scores
  each observation from its v2 structured signals (impact + confidence +
  reproducible) with a v1 recurrence fallback, clusters by fingerprint, and writes
  a LOCAL triage report — offline, no GitHub token, no network, no issue writes.
- Per cluster the report records `failure_class`, `recurrence`, a composite
  `score`, a `decision` (`review_candidate` at/above the configured threshold, else
  `retain`), and `auto_publishable` — **always `false`** in this slice (auto is
  locked until a later slice). `review`/`auto` config modes are parsed but have no
  network effect here; config is fail-closed to `local`.
- Adds a `triage` section to `.aai/feedback.yaml`, a thin
  `.aai/SKILL_FEEDBACK_TRIAGE.prompt.md` wrapper, PROFILES.yaml classification,
  and a prompt-diet ledger true-up. The review-mode upsert that consumes this
  report is the next slice (Slice C).

## [v2026.07.26] — feat: RFC-0013 Slice A — friction schema v2 + hard redactor (CHANGE-0047 / SPEC-0080)

- First code slice of RFC-0013: extends the offline capture CLI to persist
  **schema v2 structured signal fields** and adds the **hard, fail-closed
  redactor** for the opt-in `summary`. Unblocks meaningful triage (Phase 2)
  while keeping the default record prose-free.
- `.aai/scripts/aai-friction.mjs`: accepts `schema_version` 1 or 2 (v1 records
  stay byte-identical). For v2 it persists `reproducible` (bool), `impact`,
  `confidence`, `workaround` (enums), and `evidence_ref` (a shape-restricted safe
  pointer — repo-relative `docs/…` path or AAI doc id; URLs/abs paths/free text
  rejected). All leak-free by construction and never redacted.
- `.aai/scripts/lib/aai-redact.mjs` (new): a pure, deny-by-default, fail-closed
  redactor. The opt-in free-text `summary` (schema v2, off by default via
  `.aai/feedback.yaml` `capture.summary_enabled`) is persisted only if the
  redactor certifies it clean; any secret/path/identity/host/ip/token/long-digit/
  control/over-length match DROPS the field (never kept class-redacted in the
  capture pass), recording `redaction_status: capture_dropped_fields`. This is
  the capture half of RFC-0013's double redaction; the transmit pass reuses it.
- `.aai/feedback.yaml` (new, minimal): `capture.summary_enabled: false` default.
  Companion: both new `.aai/**` files classified in PROFILES.yaml.

## [v2026.07.26] — feat: RFC-0012 Phase 1 — local shadow-mode friction capture wiring (CHANGE-0046 / SPEC-0079)

- Second implementation slice of RFC-0012 (shadow mode): wires the dormant
  Phase-0 capture CLI into the skill surface as ONE canonical seam, inherited by
  every universal skill via the shared guide — capture-only, no triage, no
  upstream, no network (all Phase 2+ still deferred).
- Adds a "Skill wiring (shadow capture)" section to `.aai/system/FRICTION_PROTOCOL.md`
  (when/how to record, by reference to the taxonomy; the offline
  `node .aai/scripts/aai-friction.mjs record --input <path|->` command; and the
  shadow best-effort / never-mask / swallow contract) and ONE thin inheriting
  pointer in `.aai/AGENTS.md` (`### Friction capture (shadow)`) — the protocol
  body is never duplicated per prompt (DRY).
- Enforced by a new skill-suite guard `tests/skills/test-aai-friction-wiring.sh`
  (7 tests) with a negative control proving the guard fails when either side of
  the seam is removed, and an end-to-end test crossing the prose→CLI seam.
- Companion prompt-diet ledger true-up: +488 B AGENTS.md pointer credited
  (TEST-012 checkpoint 20358 → 20846, headroom 488/2048). No new `.aai/**` file,
  so PROFILES.yaml is unaffected.
- Shadow observation window (>= 2 weeks) and Phase 2 (review mode + threshold
  calibration) remain tracked against RFC-0012 — this slice delivers only the
  code that enables shadow capture.

## [v2026.07.26] — feat: RFC-0012 Phase 0 — offline friction capture foundation (CHANGE-0045 / SPEC-0078)

- First implementation slice of the accepted RFC-0012 (AAI self-improvement /
  friction feedback loop): the OFFLINE local-capture foundation. Everything
  downstream of capture (triage/upsert, the maintainer skill, any GitHub/network
  write, `.aai/feedback.yaml` modes, budgets) is DEFERRED to later phases.
- Adds `.aai/system/FRICTION_PROTOCOL.md` (the canonical contract: failure-class
  taxonomy + exclusions, versioned observation schema v1, the D6 field allowlist,
  the v1 deterministic fingerprint, and the redaction/atomic-append policy) and a
  dependency-free `.aai/scripts/aai-friction.mjs record` CLI that writes one JSONL
  line per observation to a gitignored project-local spool (`docs/ai/friction/`).
  Node stdlib only; no npm; cross-platform.
- Privacy by construction (RFC-0012 D6): the persisted record is built by copying
  ONLY the 8 allowlisted keys (OS family, AAI pin, Node major, skill id + phase,
  failure class, fingerprint) into a fresh object — a DENY-BY-DEFAULT allowlist,
  not a denylist — so forbidden identity fields (hostnames, absolute paths, repo
  remotes, usernames, project ids) and any novel caller key are structurally
  dropped, and the derived fields use REAL local values (a caller cannot forge
  them). Capture performs NO network I/O and holds NO token. Both properties are
  skill-suite-enforced.
- Concurrency + integrity: appends via `appendFileSync` (O_APPEND) so parallel
  agents' captures don't lose lines; the atomic-append guarantee is made true by
  construction with 128-char caps on the free identifier fields plus an
  unconditional pre-append guard that rejects any serialized line reaching
  PIPE_BUF (4096 B). 19 skill-suite tests incl. a 20/30-way concurrent-writer
  test. Ceremony L2, no protected path, no prompt-corpus edit; the two new
  `.aai/**` files are classified in PROFILES.yaml.

## [v2026.07.24] — fix: test-canon TEST-006 asserts on phase2's drift report, not a first-file proxy (ISSUE-0031 / SPEC-0077)

- `test-aai-test-canon.sh` TEST-006 flaked on Ubuntu CI (`Phase 2 silently
  overwrote canonical tests despite drift`) on unrelated PRs; it does not
  reproduce locally (0/40 under load). It derived pass/fail from
  `sha256sum tests/canonical/* | head -c 40` before/after a post-drift Phase 2 —
  the first 40 chars of the FIRST canonical file's hash only, ignoring every other
  file and conflating "any canonical byte changed" with "the DRIFTED domain was
  overwritten" (Phase 2 legitimately rewrites the non-drifted domains every run).
  The canonical render is deterministic (no timestamp), so a spurious CI-load diff
  was reported as a phase2 data-loss bug the local model never exhibits.
- Rewrote TEST-006's assertion (test-only — the phase2 comparator in
  `test-canon-core.mjs` is UNCHANGED; no race was proven): it now asserts on Phase
  2's OWN authoritative report (`DRIFT (changed since synthesis, NOT rewritten): N
  (<domain>)` names the drifted domain), isolates the DRIFTED domain's canonical
  file and checks it byte-identical before/after (separate from the rewritten
  non-drifted domains), replaces `head -c 40` with a complete order-stable digest
  that dumps which file changed on mismatch, and pins a discriminating `--resync`
  case (which DOES change the drifted file + reports `Re-synced`). A mutation test
  proves the isolation assertion still fails on a genuine un-flagged overwrite —
  the de-flake does not weaken the test.
- HONEST SCOPE: does NOT claim to fix the underlying (non-reproducible) mechanism —
  de-flakes by attribution + complete measurement + instrumentation. CI is the sole
  authoritative validator; Spec-AC-06 (repeated green CI) is deferred (Review-By
  2026-08-10). Same family as the TEST-018 reaper attribution fix (SPEC-0076).
  Ceremony L1, no protected path, test-canon core untouched.

## [v2026.07.24] — fix: TEST-018 spare-fresh attributes the kill to the reaper (ISSUE-0030 / SPEC-0076)

- `test-aai-run-tests.sh` TEST-018 spare-fresh direction flaked on Ubuntu CI
  (`legacy MIN_AGE=60 must still spare the fresh match (reaper output: reaped: 1)`)
  and recurred AFTER both prior fixes — PR #123 (split-direction margins) and
  PR #128 (per-case workspace isolation). The failure is not derivable from the
  local model: legacy mode reaps iff `etime >= 60`, the fresh proc is ~0s old, and
  a 180-iteration load repro on macOS produced 0/180. The test blamed the reaper
  from a pure liveness proxy (`! alive fresh_pid`), but the reaper only reported a
  COUNT — so a fresh proc killed by ANY cause (a Linux `ps etime` read-race inside
  the reaper, an unrelated runner process it matched, external interference) was
  mis-attributed to a reaper spare-failure.
- The reaper now prints an ADDITIVE `reaped pids: <list>` line (echoing the pids it
  already decided to reap — its epoch/legacy DECISION is byte-behaviour-identical;
  TEST-006/013/015/016/017 unchanged-green, diff has zero removed/modified lines).
  TEST-018 spare-fresh now asserts `fresh_pid` is NOT in that list — attributable,
  immune to an external kill of fresh_pid — and dumps the `ps` snapshot + parsed
  etimes on any `reaped > 0`, so a recurrence in CI is captured with evidence
  instead of a bare `reaped: 1`.
- HONEST SCOPE: this does NOT claim to fix the underlying (non-reproducible)
  mechanism — it de-flakes by ATTRIBUTION and instruments for evidence. CI (Ubuntu,
  under load) is the sole authoritative validator; Spec-AC-06 (repeated green CI)
  is deferred (Review-By 2026-08-10). No margin widened, no retry added. Ceremony
  L1, no protected path (reaper decision logic untouched).

## [v2026.07.24] — fix: metrics-flush can retire a stranded non-work-item entry (ISSUE-0029 / SPEC-0075)

- `metrics-flush.mjs` had exactly two dispositions per `metrics.work_items` entry:
  flush (truth-gated) or SKIP. A post-merge review mis-recorded as a work item
  (`pr-67-post-merge-review`, a fable-5 dual-verdict review of PR #67) satisfies
  NEITHER flush predicate — no `last_validation` PASS names it, no committed
  `work_item_closed` event — so it printed a misleading `SKIP` on every flush
  forever, with no cleanup path, training operators to ignore SKIP.
- Added a fail-closed `--retire <ref> [--reason "..."]` mode: it REFUSES (no
  mutation) any ref that would flush by EITHER existing predicate — reusing those
  exact predicates so it can only over-refuse, never bypass the truth-gate — and
  refuses a ref absent from `metrics.work_items`. On a genuinely-stranded ref it
  appends a durable `metric_retired` audit event to `EVENTS.jsonl` (carrying the
  reason + a compact `discarded_runs` summary so the telemetry is preserved, not
  dropped) BEFORE removing the STATE entry (ledger-before-STATE, same
  refusal/rollback shape as flush). `--dry-run` reports the plan without writing
  and still refuses a flushable ref; the default no-`--retire` path is
  byte-unchanged. Documented in the script's own `--help`, NOT in
  `METRICS_FLUSH.prompt.md` (SPEC-0054 invariant).
- Dogfooded: retired `pr-67-post-merge-review` in this PR — the standing SKIP is
  gone and the `metric_retired` record preserves the discarded review's telemetry.
  Covered by TEST-001..008 in `test-aai-metrics.sh` incl. a 5-vector truth-gate
  bypass hunt. Ceremony L1, no protected path.

## [v2026.07.24] — fix: branch-guard passes recognized non-work-item branches (ISSUE-0028 / SPEC-0074, closes #135)

- `branch-guard.mjs` (the SKILL_PR "0. BRANCH HYGIENE" precondition, shipped in
  SPEC-0070) matched the current branch against `current_focus.ref_id` and assumed
  EVERY branch belongs to a work item. Branches that legitimately do not —
  `chore/*` (telemetry/cleanup), `release/v*` (the `/aai-release` cut), `docs/*` —
  hit the ref_id-mismatch check and exited 3 (or 4 on a cleared focus), so the
  precondition blocked them. Hit live committing post-merge telemetry on
  `chore/metrics-flush-telemetry` (PR #132).
- Added a closed, path-segment PREFIX allowlist (`chore/`, `release/`, `docs/`),
  checked AFTER the base-branch guard and BEFORE the ref_id checks: a matching
  branch exits 0 with a distinct "recognized non-work-item branch" message (no
  remediation line). The base check still fires first (a chore is never committed
  straight to `main`), and the #129 anti-drift guarantee is untouched — a
  work-item-type branch (`feat/`/`fix/`) whose name lacks the current ref_id still
  exits 3. Matching is a path-segment prefix (`startsWith('chore/')`), not a
  substring, so `documentation-foo`/`choreography/x`/`release-notes` do NOT leak
  through. STATE handling splits Tier A (unreadable/unparseable -> still exit 4,
  the allowlist never rescues a broken STATE) from Tier B (readable, empty ref_id
  -> allowlisted branch passes). Covered by TEST-009..012 in
  `test-aai-branch-guard.sh` (full suite 42/42 on CI). Ceremony L1, no protected
  path. Closes GitHub #135.

## [v2026.07.24] — fix: docs-audit false-open now reads METRICS + orders its signals (ISSUE-0027 / SPEC-0073, closes #133 #134)

- `docs-audit-core.mjs` `falseOpenEvidence()` decided drift from four evidence
  arms, all pure existence checks with no time ordering. Two reported defects, same
  function, opposite directions: (#133) it never read `docs/ai/METRICS.jsonl`, so a
  flushed intake doc — whose AC table lives in its spec and whose delivery commits
  name the spec, not the intake — matched no arm and sat "open" forever
  (downstream: 18 of 19 flushed docs invisible); (#134) because the arms were
  existence-only, delivery evidence was permanent, so a legitimately reopened doc
  (`done -> implementing`) still read as false-open and reddened the required
  `test-aai-docs-audit.sh` CI check.
- Added a fifth **METRICS arm** (`readMetricsFlushes()`: reads the JSONL ledger,
  skips the `#` header and unparseable lines, never throws; a flush whose `ref_id`
  matches `doc.id`/`doc.fileId` is delivery evidence) and a **supersession** rule:
  the latest `doc_lifecycle` transition to an open status suppresses the false-open
  verdict only when it is provably newer than delivery.
- Correctness took three review rounds and converged on one principle. Supersession
  must compare the reopen against `deliveryTs` = the MAX over EVERY dateable arm —
  `work_item_closed`/`ac_evidence` event ts, delivery-commit committer dates
  (`git show %cI`, normalized to UTC Z, fail-closed), AND the METRICS flush date —
  and it supersedes ONLY when `deliveryTs` is non-empty and strictly older than the
  reopen. The earlier "supersede when delivery time is unknown" fallback was
  backwards for a governance audit and blinded it for commit-only and
  AC-table-only docs; it is now fail-closed (unknown delivery time -> keep
  flagging). Covered by 12 synthetic sub-cases (a-k + a same-day boundary) in
  `test-aai-docs-audit.sh`; the real corpus proves nothing here (0 open docs), so
  every case builds its own fixture. Ceremony L1, no protected path touched.
  Closes GitHub #133 and #134.

## [v2026.07.24] — fix: move TEST-017 off the reaper's epoch ambiguity boundary (ISSUE-0026 / SPEC-0072)

- `tests/skills/test-aai-run-tests.sh` TEST-017 flaked intermittently on CI
  (`epoch mode failed to reap a genuine pre-step survivor … reaped: 0`), reddening
  unrelated PRs (hit on #129, whose diff never touches the reaper).
- Root cause was NOT a reaper defect: the reaper reaps iff
  `start_epoch < STEP_START - GRACE` with `GRACE=2` (documented as 1s `etime`
  truncation + 1s snapshot skew), and `start_epoch = SNAP_NOW - floor(etime)` can
  read up to ~1s LATER than the true start. TEST-017 gave the survivor a nominal
  **3s** pre-step gap — exactly `GRACE(2) + 1s truncation`, the minimum reapable
  gap with **zero slack** — so the outcome hinged on sub-second phase alignment and
  CI load flipped it. The test was asserting INSIDE the contract's resolution limit.
- Widened `test_017`'s gap to 6s with the arithmetic spelled out and an explicit
  anti-tuning note, and added **`test_021`**, which pins the spare/reap boundary
  DETERMINISTICALLY via an injected `AAI_REAP_STEP_START_EPOCH` (SPARE at
  `ref+GRACE`, REAP at `ref+GRACE+2`) — the property is now proven by arithmetic
  instead of wall-clock racing. Offsets were empirically confirmed against the real
  reaper (20 samples: k=0 SPARE 5/5, k≥1 REAP 5/5).
- **`.aai/scripts/aai-reap-tests.sh` is byte-unchanged** — `GRACE` stays 2.
  Raising it was explicitly rejected: GRACE is the truncation/skew budget, and
  widening it would make the reaper spare genuinely-leaked processes. No
  retry/loop-until-pass either — the boundary is removed, not masked. Cost: +10.2s
  suite runtime. Ceremony L1, no protected path touched.

## [v2026.07.24] — fix: Planning surfaces companion obligations (prompt-diet ledger + PROFILES) (ISSUE-0025 / SPEC-0071)

- Two repo invariants were enforced only at the CI trailing edge, so a scope that
  looked "done" at planning time shipped incomplete and reddened CI: (1) any edit
  that grows the prompt corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`) needs a
  `JUSTIFIED_ADDITIONS` true-up in `tests/skills/lib/prompt-diet-ledger.sh` or the
  byte-floor test cascades through half the suite; (2) any new `.aai/**` file needs
  a `.aai/system/PROFILES.yaml` classification or the layer-profiles manifest gate
  (and `aai-release` TEST-020) fails. Both were tripped repeatedly (three PRs in
  one session); rule (1) was already definition-of-done in `LEARNED.md` but lived
  nowhere the planner actually reads.
- Added a closed, two-entry **"3a) COMPANION OBLIGATIONS CHECK"** to
  `.aai/PLANNING.prompt.md`: each trigger → its required companion → the concrete
  file to edit, so the planner folds the companion into the spec's scope BEFORE
  freezing. It is a planner-facing checklist, not an auto-detection script.
- Self-demonstrating: because the change edits `.aai/PLANNING.prompt.md`, its own
  scope includes the prompt-diet ledger true-up (566 B measured, credited at 0 B
  headroom; TEST-012 checkpoint 19792 → 20358) — the fix obeys the rule it
  introduces. Verified by `tests/skills/test-aai-hygiene-pack.sh`
  (`test_070_companion_obligations`) + the byte-floor/manifest suites green on
  macOS + Linux CI. Ceremony L1, no protected path touched. Propagates downstream
  via `/aai-update`.

## [v2026.07.24] — fix: enforce one dedicated git branch per work item (ISSUE-0024 / SPEC-0070)

- The loop had NO deterministic step that creates or verifies a per-work-item
  branch on the INLINE strategy (the common L0-L2 path): `SKILL_PR` step 5 pushed
  *"the current branch"* whatever it was — branch creation existed only in
  `SKILL_WORKTREE` (the L3 path) and `AGENTS.md` gave no branch guidance at all.
  A downstream agent consequently piled successive work items onto one long-lived,
  misleadingly-named branch (`feat/change-158-…`) with nothing to catch that the
  branch did not correspond to the current `current_focus.ref_id`.
- Added `.aai/scripts/branch-guard.mjs` — a READ-ONLY guard (imports the same
  `lib/state-core` helpers `orchestration-dispatch.mjs` uses; never writes STATE)
  that FAILS CLOSED with a closed exit-code set: 0 pass; 1 on the base branch;
  2 detached HEAD; 3 branch name does not map to `current_focus.ref_id`; 4
  config-error (STATE/ref unresolvable — defaults closed). Every non-zero exit
  prints a copy-pasteable `git checkout -b <type>/<ref-id> origin/<base>`
  remediation; `--suggest` prints the canonical branch name for the current ref.
- Wired it as an additive **"0. BRANCH HYGIENE"** precondition in
  `.aai/SKILL_PR.prompt.md` (runs the guard, STOPS before any push on failure) and
  documented the one-branch-per-work-item rule in `.aai/AGENTS.md`. Fail-closed by
  design: it never rewrites history or force-pushes a mis-branched commit — it
  stops and tells the operator to re-branch. Covered by
  `tests/skills/test-aai-branch-guard.sh` (8 tests, all fail classes + `--suggest`,
  green on macOS + Linux CI).
- Design note: kept at ceremony **L1** by living entirely in a NEW non-protected
  script + prompt + docs — no `protected_paths_l3` file touched (no forced L3
  worktree). Propagates to every downstream project via `/aai-update`.

## [v2026.07.24] — fix: TEST-018 fresh per-case workspace removes residual reaper flake (ISSUE-0023 / SPEC-0069)

- `tests/skills/test-aai-run-tests.sh` TEST-018 (reaper legacy fail-safe) still
  flaked intermittently on CI **after** the SPEC-0064 split-direction margin fix
  (PR #123) — it blocked the release rollup PR #127 and other merges. Root cause of
  the RESIDUAL flake was NOT the margins: all six invalid-epoch cases
  (UNSET/EMPTY/abc/-5/0/future) shared **one** workspace `$ws` (a single `mktemp -d`
  above the `for invalid` loop). The reaper matches by `AAI_REAP_WORKSPACE`, so a
  `spare-fresh` reap in a later case could match/reap a process leaked from an
  earlier case's `reap-old` direction → the observed "must still spare the fresh
  match (reaper output: reaped: 1)".
- Fix is **state isolation, not another widened margin**: moved the `mktemp -d`
  workspace **inside** the loop (fresh `$ws` per case, so the reaper can only ever
  match that case's own two procs) and made teardown kill **both** `old_pid` and
  `fresh_pid` every iteration (previously only the fresh one), so a `reap-old` that
  missed under load cannot leak into a later case. The split-direction margins
  (MIN_AGE=1 reap-old / 60 spare-fresh) are **preserved unchanged**.
- **Test-only change**: the production reaper `.aai/scripts/aai-reap-tests.sh` is
  untouched (its epoch guard is correct and deterministically covered by
  TEST-006/016/017). Honest note: the flake is load-related and reproduces only
  under Linux CI — verified green on `skill-suite` across **two** runs at the same
  HEAD, the load-authoritative environment; the fix removes the shared-state
  MECHANISM rather than out-margining the race.

## [v2026.07.22] — feat: metrics-flush `--sweep` clears stranded completed refs (ISSUE-0022 / SPEC-0068)

- `metrics-flush` moved only the ref named by the transient `last_validation`
  singleton to the committed `METRICS.jsonl`, so a completed item that is not the
  CURRENT validation ref **strands** in `STATE.metrics.work_items` and never
  reaches the ledger the dashboard reads. Reported downstream (19 stranded);
  confirmed here (12 `done` items + `pr-67` SKIPPED on every tick this session).
- Added opt-in `--sweep` (default flush **byte-unchanged**): flushes every
  stranded entry whose ref carries **durable completion provenance** — a committed
  work-item close event in `docs/ai/EVENTS.jsonl` (the record `close-work-item.mjs`
  stamps only after its self-verify audit) **AND** `active_work_items` status
  `done`. **STRICT / fail-closed:** a `done`-without-close ref is reported, never
  flushed — the truth-scoring guarantee is preserved, re-anchored on durable proof
  instead of the transient singleton. `--sweep --ref <id>` targets one ref.
  EVENTS.jsonl is read-only; idempotent; reuses the existing integrity
  refusal / rollback / ledger-before-STATE ordering.
- Design note: deliberately kept ENTIRELY in `metrics-flush.mjs` (no STATE schema
  field → no `state.mjs` → no forced L3 worktree, the gate this class of fix keeps
  hitting) by using durable proof that already exists rather than a new field.

## [v2026.07.22] — fix: aai-release.ps1 native git/gh guarded against stderr-as-error on Windows PS 5.1 (ISSUE-0021 / SPEC-0067)

- `aai-release.ps1` ran `git push` (and `gh release create`) unguarded under
  `$ErrorActionPreference='Stop'`. On **Windows PowerShell 5.1**, `git push`'s
  normal `To <remote>…` **stderr** progress is promoted to a terminating
  `NativeCommandError`, so `/aai-release --confirm` aborted **after** the local
  commit+tag even though the push succeeded — a half-done release. (Same class as
  a downstream `aai-update.ps1` `git clone` report; that one was already guarded on
  `main`, their copy was stale.)
- Added `Invoke-NativeChecked`: localizes `$ErrorActionPreference='Continue'`, runs
  `& exe args 2>&1`, captures `$LASTEXITCODE`, returns on 0 (never throws on
  success-stderr), and **throws WITH the captured stderr on non-zero exit** —
  diagnostics-preserving on purpose (not a blanket `*> $null`, which would hide a
  real rejected/auth/network failure on an outward-facing publish). Routed the
  cut-path `add`/`commit`/`tag`/`push`/`push-tag`/`gh release` through it.
- Honest limit: the defect is Windows-PS-5.1-specific; pwsh 7 (CI's runtime) does
  not reproduce it and CI only parse-checks 5.1. The Pester tests prove the
  helper's logic; the actual 5.1 runtime fix is covered by a documented manual
  smoke, not CI.

## [v2026.07.22] — fix: HITL answers now reach the STATE field they gate (ISSUE-0020 / SPEC-0066)

- **Reported from a downstream AAI deployment, reproduced twice here.** Resolving a
  human-in-the-loop block was a **no-op for the loop**: `SKILL_HITL` was forbidden
  from writing anything but `human_input`, while dispatch **rule 8** gates on
  `worktree.user_decision`. An answered worktree question therefore stayed
  `undecided` — the question re-fired and the anti-stagnation guard halted the loop.
  The decision *looked* recorded (decision artifact + `decisions.jsonl`); only the
  loop's non-progress revealed it.
- Fix (prompt-only, deliberately avoiding a `protected_paths_l3` `state.mjs` schema
  change that would have forced L3 — whose mandatory-worktree rule would route this
  fix through the very gate it repairs):
  - `SKILL_HITL` gained an explicit **9-row trigger→target mapping** applied via the
    EXISTING typed `state.mjs` setters (`[HITL-7]` → `set-worktree --user-decision`,
    `[HITL-8]` → `set-code-review --scope`, `[HITL-9]` → `set-code-review --status`).
    `[HITL-6]` maps to `none` **deliberately** — `last_validation` has no waiver enum,
    so forcing `pass` would forge evidence.
  - The guardrail is **narrowed, not deleted**: `human_input` plus the ONE declared
    target field, via the typed CLI — nothing else.
  - **Write ordering:** the target setter runs BEFORE clearing `human_input`, so a
    crash leaves the block re-askable instead of silently losing the decision.
  - **Fail-closed:** free-text answers normalize to the setter enum; unmappable
    answers never guess (scoped to enum targets, so the no-gate triggers still resolve).
  - `ORCHESTRATION_HITL` stamps `[HITL-<n>]` into `blocking_reason` so the target is
    unambiguous rather than inferred.
- New `tests/skills/test-aai-hitl-propagation.sh` (15 tests) including a **seam test**
  that extracts the `[HITL-7]` command from the prompt, runs it against a fixture
  STATE, re-dispatches, and asserts rule 8 stops firing.

## [v2026.07.22] — fix: GNU-first `stat` for mtime in test-aai-test-canon.sh (ISSUE-0019 / SPEC-0065)

- `tests/skills/test-aai-test-canon.sh` read file mtimes at four sites via
  `stat -f %m … || stat -c %Y …` — the RC4 bug class: on GNU/Linux `stat -f`
  succeeds (it means `--file-system`), so the `stat -c` fallback never ran and the
  suite read a wrong value on the Linux runner. Swapped to GNU-first
  `stat -c %Y … || stat -f %m …`, matching the already-shipped
  `tests/skills/test-aai-update.sh`. Behavior-preserving on macOS. This finishes
  cleaning the RC4 class repo-wide; it is correctness hygiene and does NOT claim to
  fix the (separate, still-undiagnosed) intermittent test-canon flake.

## [v2026.07.22] — fix: deterministic reaper age guard — remove aai-run-tests CI flake (ISSUE-0018 / SPEC-0064)

- The test-process reaper (`.aai/scripts/aai-reap-tests.sh`) decided
  fresh-sibling-vs-survivor by comparing an overhead-inflated `ps etime` against a
  FIXED `AAI_REAP_MIN_AGE_SECS`, so on a loaded Linux CI runner a genuinely-fresh
  sibling could be sampled past the constant and wrongly reaped — flaking the
  `aai-run-tests` suite (a required check that blocked PR #118/#119). The prior
  2s→5s margin widen (CHANGE-0043) only lowered the probability.
- Fix: a **step-start-epoch-relative** decision that is invariant to reaper
  overhead — capture `SNAP_NOW=$(date +%s)` at the `ps` snapshot instant, compute
  `start_epoch = SNAP_NOW − etime`, and reap iff `start_epoch < STEP_START − GRACE`
  (both terms move together, so overhead cancels). `AAI_REAP_STEP_START_EPOCH`
  (valid: digits, >0, ≤ now) + `AAI_REAP_GRACE_SECS` (default 2); unset/invalid/
  future **fails safe to the exact legacy `MIN_AGE` behavior** — never a global
  kill, and Guards 1 (token) & 2 (workspace) are untouched.
- Producer wiring documented in `SKILL_LOOP` / `VALIDATION` (the step owner
  captures the epoch); PowerShell twin gains `-StepStart` contract parity. Portable
  (`ps etime` + `date +%s` only). RED-proofed: the old reaper flips spare→reap
  under an injected 7s delay; the new one is delay-invariant. Verified by two
  consecutive green Ubuntu `skill-suite` CI runs.

## [v2026.07.20] — feat: portable `/aai-release` skill — deterministic release-cut engine (CHANGE-0044 / SPEC-0063)

- Added `.aai/scripts/aai-release.{sh,ps1}` — a deterministic release-cut engine
  behind the new `/aai-release` skill (`.aai/SKILL_RELEASE.prompt.md` +
  `.claude/.codex/.gemini` wrappers). Rolls the root `CHANGELOG.md`'s
  `[unreleased]` blocks into a versioned section (line-surgical, idempotent,
  content byte-preserved), commits `chore(release): <version>` staging only
  `CHANGELOG.md`, creates an annotated git tag, publishes a GitHub release with
  notes derived from that same rolled section (SEAM-1: single source of truth),
  and pushes — behind an operator gate (`--confirm`/`--yes`) with a safe
  default plan-only mode (bare invocation and `--dry-run` behave identically:
  zero writes, exit 0).
- Fail-closed precondition matrix (zero writes on refusal): dirty working
  tree; missing/empty/malformed `[unreleased]` region; an existing tag for the
  resolved version; `gh` absent/unauthenticated on the publish path only (the
  plan path works fully offline). Version resolves from `--version <v>`
  verbatim (any scheme, incl. SemVer) or defaults to CalVer `vYYYY.MM.DD`
  (pinnable via `AAI_RELEASE_DATE` for deterministic tests/CI). A `--no-remote`
  flag / `AAI_RELEASE_NO_REMOTE=1` env twin skips `git push` + `gh release
  create` for local-only cuts and test safety.
- Generic by construction — the only inputs are the repo root, its
  `CHANGELOG.md`, and its git/`gh` remote, so it runs identically releasing AAI
  itself or a downstream project that has the AAI layer deployed.
- `tests/skills/test-aai-release.sh` (21 tests) exercises the rollup transform,
  the precondition matrix, the remote seam (stubbed `gh` + local `file://`
  bare remote — never a real publish/push), and portability, entirely in
  throwaway scratch repos.

## [v2026.07.20] — fix: make the skill test suites pass on the Linux CI runner (CHANGE-0043 / SPEC-0062)

- The new `skill-suite` CI gate (CHANGE-0042) was red on Ubuntu while every suite
  passed on macOS. Root-cause analysis (enabled by making `test-framework.sh`
  always dump failing-suite tails, not only under `--verbose`) reduced ~15
  failing suites to four causes, fixed here so the gate is green (39/39, 100%)
  and can be enforced:
  - **RC2 (BSD/GNU `mktemp`)** — `mktemp -t <bare-prefix>` errors "too few X's"
    on GNU; switched to a full `…​.XXXXXX` template (identical on both). This one
    line unblocked seven suites that run prompt-diet as a sub-check.
  - **RC1 (gitignored runtime files absent on a fresh checkout)** —
    `docs/ai/STATE.yaml` and a tdd fixture log are gitignored (per-dev) so they
    do not exist on CI; the suites that touched them now self-seed / soft-skip
    when absent (orchestration-mode, orchestration-dispatch, tdd-evidence).
  - **RC3 (`--base-ref main` on a detached checkout)** — the suites' own temp
    repos now `git init -b main` so the allocator's base ref resolves.
  - **RC4 (BSD/GNU `stat`)** — `stat -f` succeeds on GNU as `--file-system`
    (wrong data); try `stat -c` first, `stat -f` fallback.
  - **aai-run-tests reaper** — a CI-only timing race (not an `etime`-format bug);
    widened the age margins for runner-jitter headroom.
- `test-framework.sh` now always surfaces a failing suite's output tail, so a CI
  log alone explains a failure (previously diagnosable only with `--verbose`).

## [v2026.07.20] — fix: three hidden test-infra reds + gate the skill suite in CI (CHANGE-0042 / SPEC-0061)

- A serialized full-suite run (honoring each suite's shebang, not forced `sh`)
  surfaced three real reds on `main` that had accumulated invisibly because the
  skill test suites were not run in CI:
  - **`test-aai-layer-profiles`** — `.aai/system/PROFILES.yaml` did not classify
    six vendored files (`close-work-item.mjs`, `reconcile-telemetry.mjs`,
    `secrets-preflight.mjs`, `tdd-evidence-check.mjs`, `aai-reap-tests.ps1`,
    `aai-run-tests.ps1`); all six added to `core`.
  - **`test-aai-worktree`** — a `set -o pipefail` + `git log --oneline | grep -q`
    SIGPIPE false-failure (grep -q closes the pipe on the newest-commit match,
    `git log` gets SIGPIPE 141, pipefail propagates it, `if !` inverts to a false
    FAIL). Fixed by capturing `git log` to a variable first; both isolation
    assertions stay meaningful.
  - **`test-self-hosting-smoke`** — `aai-sync.sh` (and its companion
    `validate-skills.sh`, both invoked directly by the smoke) were committed
    non-executable (100644); restored to 100755.
- **Structural prevention:** added `.github/workflows/skill-suite.yml` — runs the
  skill suite on push/PR honoring each suite's shebang and failing the job on any
  red suite, with the slow self-hosting smoke in a separate timeboxed job. This
  closes the CI gap that let these reds (and the earlier verify-gate red) ship
  unseen.

## [v2026.07.20] — fix: unify the two prompt-diet byte floors into a shared ledger (ISSUE-0017 / SPEC-0060)

- Fixed a real red on `main`: `tests/skills/test-aai-verify-gate.sh` TEST-006
  failed (net reduction 20455 < 28672) because it applied the same
  `BASELINE_PROMPT_BYTES`/`REQUIRED_REDUCTION_BYTES` as
  `tests/skills/test-aai-prompt-diet.sh` TEST-010 but **without** the
  `JUSTIFIED_GROWTH_BYTES` credit (=9239) that TEST-010 gained during this
  session's ledger true-ups (CHANGE-0038/0039/0040) — the credited prompt
  growth double-counted as a floor violation in the second copy.
- Extracted the diet-floor constants, the `JUSTIFIED_ADDITIONS` ledger (3
  entries, sum 9239, verbatim), and the two pure helpers into a single
  sourceable `tests/skills/lib/prompt-diet-ledger.sh`; both suites now `source`
  it, so the two floors can never drift apart again — the structural fix for the
  recurring "two copies of one gate, only one maintained" pattern
  (docs/knowledge/LEARNED.md, DEBT-0002).
- `test-aai-verify-gate.sh` TEST-006 now uses the credited formula
  (`29694 >= 28672`, headroom 1022/2048); `test-aai-prompt-diet.sh`
  TEST-010/012/013 stay green (ledger sum unchanged); the third consumer
  `test-aai-ceremony-levels.sh` stays green. Test-infra only; no runtime change.

## [v2026.07.20] — docs: user-facing docs for the workflow-hardening + collision-guard changes (CHANGE-0041)

- `docs/USER_GUIDE.md` now documents five previously-undocumented user-visible
  features shipped this session, each described against the actual shipped
  behavior:
  - **Deterministic close ceremony** (`close-work-item.mjs`, CHANGE-0037 /
    SPEC-0053) — resolve-by-slug, status flip, `links` + close-event stamping,
    self-verify against the real docs-audit, byte-exact rollback on drift,
    idempotent, fail-closed on ambiguous/duplicate id; the loop's Validation/PR
    ceremonies run it automatically (no more hand-closing).
  - **Lightweight lane** (`ceremony_level` 0/1, SPEC-0041) — how to declare the
    level and what L0–L3 mean; L0/L1 run a leaner pipeline, L2/L3 (and any
    absent/invalid level, fail-closed) run the full one.
  - **docs-audit `duplicate-doc-id`** (SPEC-0057) — two docs sharing one
    frontmatter id; verdict-only NEEDS-TRIAGE, `--check`/CI exit unchanged; how
    to remediate.
  - **spec-lint `spec-id-shape`** + the **`spec-<slug>` id convention**
    (SPEC-0058) — a spec id must be `spec-<change-slug>` (or legacy `SPEC-NNNN`),
    never a bare slug that collides with its change.
  - **secrets-preflight** (`secrets-preflight.mjs`, SPEC-0045) — the
    `--env` / `--file`+`--key` grammar, the `exists|empty|missing` output, and
    the never-echo guarantee.
- Updated the affected skill descriptions: `aai-pr` (close step), `aai-docs-audit`
  (duplicate-doc-id), `aai-intake` (secrets preflight), `aai-loop` (lightweight
  lane). Docs-only change — no code/behavior change.

## [v2026.07.20] — feat: delta-spec lifecycle — close-time delta merge + provenance drift (CHANGE-0026 / SPEC-0038)

- Final stage of the RFC-0011 delta-spec lifecycle. New `delta-merge.mjs` applies
  a merging spec's `## Deltas` into `docs/canonical/<domain>.md` at PR ceremony:
  ADDED gets the next unused per-domain NNN, MODIFIED replaces the requirement's
  body, REMOVED retires it (a `<!-- RETIRED … -->` tombstone reserves the NNN so
  it is never reused). Line-surgical (untouched lines byte-identical), byte-
  idempotent, all-or-nothing fail-closed (zero writes on any delta violation,
  missing canonical doc, absent MODIFIED/REMOVED id, or ADDED title collision),
  deterministic (no LLM in the write path). Reuses the stage-1/2 parsers as the
  single grammar source.
- docs-audit `--check` gains a provenance drift check: every canonical
  requirement must trace to a merging spec (`untraced-canonical-requirement` /
  `broken-canonical-provenance`); a no-op with no false positives when
  `docs/canonical/` is empty. This is also the gate that resolves the NB-1
  obligation SPEC-0034 promoted.
- The PR ceremony (SKILL_PR) runs delta-merge after number allocation so the
  canonical diff is in the PR and reviewable (the RFC's chosen merge trigger);
  fail-closed STOP on any merge error; documented no-op when a spec has no
  `## Deltas` or the repo has no canonical layer. `docs/canonical/` is empty in
  this repo, so merge + drift are no-ops here — the engine ships fixture-tested
  and ready. Independent validation caught and drove remediation of a tombstone-
  deletion bug (retired-NNN reuse) before this passed; dual-verdict review PASS.

## [v2026.07.20] — feat: delta-spec lifecycle — SPEC `## Deltas` section + shape validation (CHANGE-0025 / SPEC-0037)

- Second stage of the RFC-0011 delta-spec lifecycle (builds on SPEC-0034's
  canonical Requirements contract): a SPEC may carry an optional `## Deltas`
  section declaring `### ADDED REQ-<DOMAIN> — …` (no number; assigned at merge),
  `### MODIFIED REQ-<DOMAIN>-NNN — …`, and `### REMOVED REQ-<DOMAIN>-NNN` blocks
  against named canonical domains. The target domain derives from the id
  (`reqDomainToSlug`, the reversible inverse of `domainToReqDomain`).
- spec-lint validates the section SHAPE only (operation keyword, id grammar per
  op, domain derivability, one-SHALL for ADDED/MODIFIED, empty body for REMOVED,
  no duplicate/conflicting ops) with precise `delta-*` finding codes. A spec with
  no `## Deltas` section is unaffected. One shared reader (`parseDeltasSection` in
  docs-model.mjs) that the close-time merge will reuse; grammar defined once.
  Commented content (the template ships the example commented) parses inert.
- Cross-doc resolution and the actual merge into `docs/canonical/` are the next
  stage. Independent validation PASS; dual-verdict review PASS after remediating
  a phantom-delta trap (template comment stripping), a weak test assertion, and
  a fail-closed consumption contract for the merge consumer.

## [v2026.07.20] — feat: level-aware close gate for L0/L1 lean specs (CHANGE-0024 / SPEC-0036)

- docs-audit's close gate and done-drift check become ceremony-level aware: a
  validly declared ceremony_level 0/1 "lean" spec (a `## Acceptance Criteria`
  table with Spec-AC + Status columns + a `Ceremony justification:` line) can
  now pass `--gate`/`--gate-file` and close CLEAN, instead of being blocked by
  the canonical `## Acceptance Criteria Status` table requirement. L2/absent
  specs keep byte-identical gate reasons and drift verdicts; a garbage
  ceremony_level fails closed to full canonical requirements. Surfaced by the
  first live L1 spec (SPEC-0032), whose own AC table is brought to the
  canonical lean shape here so it is genuinely gate-closeable.
- Silent-drop hardening: the shared lean parser splits rows on a naive `|`, so
  a row whose cell holds a literal pipe (plain or escaped) was dropped and the
  gate could PASS while a declared AC went unchecked. parseLeanAcTable now
  returns `declaredIds` from the same line set it parses; both the close gate
  and the done-drift check reconcile declared-vs-parsed and fail/flag naming
  any unparseable row (immune to indentation — one source of truth, no sibling
  regex to drift). spec-lint accepts the lean shape at L1 in step with the gate.
- Independent validation PASS; dual-verdict review PASS after remediating two
  reviewer-found silent-drop escapes (indented row; drift check not mirroring
  the gate). Regression tests: TEST-001..008 in test-aai-docs-audit.sh.

## [v2026.07.20] — feat: core/extended profiles for the vendored layer (CHANGE-0023 / SPEC-0035)

- aai-sync gains --profile core|extended (default extended = byte-identical
  for existing consumers): core = the workflow engine (orchestration, roles,
  intake, state/docs/gates scripts), extended = everything (dashboards, share,
  decapod, session tooling). PROFILES.yaml classifies 100% of the vendored
  tree (106 core / 41 extended / 147 total; a conformance test fails on any
  unclassified addition). Profile is sticky via an AAI_PIN 'Profile:' line and
  shown by /aai-doctor; layer-drift is profile-agnostic. OpenSpec pattern,
  RES-0001 P3.
- Review caught a real BLOCKING defect: an unquoted prefix-strip glob-
  interpreted the target path, mass-deleting the whole core layer on a target
  whose path contained [ ] * ? (only the pin survived, exit 0). Fixed
  (quoted strip) with a RED-proven bracket-path regression test; two sh↔ps1
  parser-parity drifts (F2/F3, trailing whitespace) fixed in the same pass.

## [v2026.07.20] — feat: delta-spec lifecycle stage 1 — canonical requirements contract (RFC-0011 / SPEC-0034)

- RFC-0011 stage 1 of 3: the canonical layer gains a Requirements contract —
  `### REQ-<DOMAIN>-NNN — <title>` + one SHALL + optional Scenario +
  Provenance line; ids stable (never renumbered/reused, gaps legal); domain =
  uppercase snake of the canonical doc's slug (digit-boundary unambiguous by
  construction). Grammar exported as REQ_ID_RE/REQ_HEADING_RE/
  domainToReqDomain/parseRequirementsSection for stages 2-3 to import (single
  source). docs-canon emits the (empty-valid) skeleton; CANONICAL_TEMPLATE.md
  documents it. Stages 2 (Deltas section + spec-lint) and 3 (delta-merge at PR
  ceremony) seam-noted in D6/D7.
- Review NB-2 remediated: validatePhase2Plan rejects an invalid domain slug at
  pre-flight, before archiveSource, so a bad key can't half-mutate the tree.
  NB-1 (old-shape migration re-render) promoted to a stage-2 obligation.

## [v2026.07.20] — feat: spec-lint — deterministic spec-structure validation (CHANGE-0022 / SPEC-0033)

- New .aai/scripts/spec-lint.mjs (report-only, exit 0/1/2, --json): AC-id
  uniqueness/sequence, done-needs-evidence, Test-Plan-to-AC mapping (list +
  NN..MM ranges), SPEC-FROZEN/strategy consistency, ceremony_level enum, and
  the new ac-row-unparseable class — rows silently DROPPED by the shared
  table parser (escaped pipes) are now loud. Boundary vs docs-audit written
  as a normative table (structure vs lifecycle, no duplication; shared
  parsers imported, not reimplemented).
- Paid for itself at birth: found SPEC-0012's Spec-AC-08 row invisible to
  docs-audit, the index AND the close gate since June (escaped-pipe Evidence
  cell) — fixed; corpus now 31 specs / 0 findings. Review F1 (compact-row
  false positive) remediated in-tree with a negative control; F2 promoted.
- 2-line advisory wiring in PLANNING + VALIDATION with degrade clauses.

## [v2026.07.20] — feat: truth-scoring on the metrics ledger (CHANGE-0021 / SPEC-0032)

- Flushed ledger entries gain reliability{validation_fails, review_fails,
  remediation_runs, first_pass_clean} + a strategy stamp — derived ONLY from
  recorded runs (normative rules R1-R6; R6 documents what is honestly NOT
  derivable: an unmarked FAIL is invisible to the marker counts but
  structurally witnessed by remediation_runs). metrics-report renders a
  Per-Strategy Reliability table; legacy lines render n/a.
- FIRST live ceremony_level: 1 scope — the lean L1 spec reviewed cleaner
  than a typical L2 (reviewer: "mechanical code-to-rule diff"), and its
  validation found the L1 close-gate machinery gap (gateContent demands the
  canonical AC-Status table regardless of level) — fixed in the companion
  l1-close-gate scope. Review: zero findings.

## [v2026.07.20] — feat: three optional advisory skills (CHANGE-0020 / SPEC-0031)

- SKILL_SCOUT (pre-implementation readiness 0-100 over 5 dimensions, GO/HOLD
  advisory at 70), SKILL_DESLOP (diff-scoped AI-slop removal with behavior-
  unchanged suite rule), SKILL_INTERROGATE (one-question decision walk with
  recommended answers and planning_decision ledger lines). pro-workflow
  patterns per RES-0001 P3, fidelity validated against the upstream source.
- Strictly ADVISORY: shared disclaimer literal, zero references from any
  gate/dispatch/workflow surface (negatively asserted by the suite).
  Validation NB (ledger key ref->ref_id) + review NB (pin the key in the
  test) both remediated.

## [v2026.07.20] — feat: scale-adaptive ceremony levels (RFC-0009 / SPEC-0030)

- Specs declare ceremony_level 0-3 at freeze (justified in-doc); the gate
  table prunes EXPLICITLY by level, never silently: L0 (typo-class) skips the
  frozen-SPEC form (tech-note in the CHANGE doc; justification line required
  at close); L1 lean; L2 = today's default (legacy specs implicitly L2, zero
  migration); L3 (protected surfaces via protected_paths_l3 config) ADDS
  protection — recorded worktree decision mandatory, review coerced required,
  waived review at L3 escalates to an operator checkpoint.
- Dispatch reads the level from spec frontmatter FAIL-CLOSED (absent/garbage
  -> L2; proven on a 9-value garbage matrix + bit-identical L2 legacy
  comparison against pre-change dispatch). Validation is never pruned at any
  level (constitution article 1 held by construction).
- Also fixes a latent loadConfig regex bug (digit-bearing config keys).
  Review NB-1/NB-2 remediated (real idempotence probe; L3 worktree cell
  aligned to house 'required' semantics).

## [v2026.07.20] — feat: hook-enforced gates overlay for Claude Code (RFC-0010 / SPEC-0029)

- Opt-in PreToolUse/Stop hooks template mirroring EXISTING script gates
  (zero new logic in hooks): git commit -> pre-commit-checks; git/gh merge ->
  ratified article-7 deny with the AAI_OPERATOR_MERGE ceremony escape;
  yaml.dump on STATE.yaml -> state.mjs pointer; Stop wrap-up nudge (never
  blocks). Fail-open everywhere; absence = unchanged behavior; Codex/Gemini
  unaffected (scripts remain the floor). Install via aai-bootstrap
  --with-claude-hooks (idempotent merge; refuses loud on unmergeable
  settings.json and now FAILS the run when the requested overlay cannot land
  — review NB-1 follow-through).
- Review caught two real edges pre-merge: hooks:[] silent false success and
  the 'git -C <worktree> merge' matcher bypass — both remediated with
  regression stanzas. Hooks schema verified against live docs by validation
  (one harmless assumption corrected).

## [v2026.07.20] — feat: project constitution with justified-exception tracking (CHANGE-0019 / SPEC-0028)

- docs/CONSTITUTION.md: 7 one-sentence articles distilled from scattered canon
  (evidence-before-claims, KISS/YAGNI, tri-platform portability,
  degrade-and-report, additive-first, single-writer STATE, operator-only
  merge), each pointing at its authoritative source. Merge of the introducing
  PR = ratification (header softened per validation axis-e finding — the
  original "Ratified by" overclaimed a review that had not happened).
- PLANNING freeze step checks the articles; specs carry a "Constitution
  deviations" section (required for new, optional for legacy — spec-kit
  accountable-deviation pattern, RES-0001 P2). This scope dogfoods it.
- Review NB: Article 7 carve-out question (strict operator-only vs
  operator-DIRECTED agent merges) promoted to the ratification decision;
  the session merge-direction practice is now recorded in decisions.jsonl.

## [v2026.07.20] — feat: systematic-debugging gate for remediation (CHANGE-0018 / SPEC-0027)

- New .aai/SKILL_DEBUG.prompt.md (68 lines): root-cause-first protocol —
  READ (full error, never tail-only) -> REPRODUCE (before any edit) ->
  ISOLATE (recent changes, boundary instrumentation, backward trace) ->
  FIX-AT-CAUSE (the fix must make the reproduction pass); 6-row
  rationalization table citing this repo's own fieldSpan near-miss as the
  motivating example; SKILL_VERIFY cross-link (DEBUG governs before-fix,
  VERIFY before-claim). Superpowers pattern, RES-0001 P2.
- REMEDIATION wires the gate in 2 purely additive lines before its fix step;
  wrappers x3; 8-test suite. Review NB (unbounded awk) fixed — and the fix
  itself exposed a second bug (prose-anchored pattern), root-caused via the
  new SKILL_DEBUG discipline; both landed anchored+bounded.
- Validation PASS (byte-for-byte RED reconstruction); dual-verdict review
  PASS.

## [v2026.07.20] — feat: work-item brief as subagent handoff (CHANGE-0017 / SPEC-0026)

- Planning now emits a self-contained brief per work item (BMAD story
  pattern, RES-0001 P2): Scope & why / AC-task map / canon POINTERS (never
  copies) / evidence contract / Return Record — the Record embeds the
  SUBAGENT_PROTOCOL result block byte-identical (mechanically diffed by the
  test). Briefs live in gitignored docs/ai/briefs/; SUBAGENT_PROTOCOL makes
  them the DEFAULT dispatch input with an explicit never-block degrade to
  spec paths. ORCHESTRATION wrapper untouched (40/40 cap).
- Validation PASS (functional probe: generated brief stands alone);
  dual-verdict review PASS (verbatim proof re-diffed independently; one
  accepted disposition on SPEC-0012's dated step citations).

## [v2026.07.20] — chore: dual-verdict measurement gate evaluated — KEEP (SPEC-0021 closed)

- 5/5 reviewed scopes collected; wall-clock parity-or-better vs the two-stage
  era (median -5%, mean -11%, spec-backed subset -27%); catch quality
  maintained incl. on operator code merged outside the pipeline (PR #67
  post-merge review: agent-hang risk + temp-path TOCTOU found). Token axis
  honestly UNMEASURABLE (null usage both eras) — the -50% claim stays
  imported, not demonstrated. Verdict: KEEP; revert path unexercised.
- PR #67 review NB-1 remediated here: anonymous clone attempt now sets
  GIT_TERMINAL_PROMPT=0 in both twins (a private canonical repo would hang an
  agent session on a username prompt); ps1 pin evidence grep gains the
  SPEC-0020 'canonical' widening (INFO-2). NB-2 (TOCTOU) promoted with
  disposition in decisions.jsonl.
- Ledger completed for CHANGE-0014/0015 review runs (archive recovery) so the
  gate had all five data points; pricing suite green.

## [v2026.07.20] — feat: verification-before-completion gate skill (CHANGE-0016 / SPEC-0025)

- New .aai/SKILL_VERIFY.prompt.md (71 lines): the Iron Law gate — IDENTIFY the
  claim -> RUN the check -> READ the output -> VERIFY it matches -> only then
  CLAIM; 7-row rationalization table (stale runs, partial checks, "passed
  earlier", trusting subagent self-reports, ...); subagent reports verified
  via git status/diff, never taken as evidence. Superpowers pattern, RES-0001
  P2 rec 7a.
- Wired into IMPLEMENTATION (replaces its 6-line rule block — move-not-loss
  validated), VALIDATION step 7b and SKILL_TDD Phase 4; wrappers in all three
  agent trees; 8-test grep suite.
- Delivered by the FIRST full /aai-loop run on the mechanized stack: 5 ticks
  (Planning->Implementation->Validation->Review->script Flush), dispatch by
  orchestration-dispatch.mjs (zero LLM orchestration ticks), tier-routed
  models per dispatch (implementation on Sonnet), validator independence
  enforced mechanically, tick telemetry in LOOP_TICKS. Validation PASS;
  dual-verdict review PASS (gate applied to its own review — measurement-gate
  data point #4).

## [v2026.07.20] — chore: orchestration surfaces aligned to the dual-verdict taxonomy (CHANGE-0014 / SPEC-0024)

- 15+2 occurrences of the retired Stage-1/Stage-2 + ERROR/WARNING review
  vocabulary reworded across REMEDIATION, SKILL_TDD, WORKFLOW,
  ORCHESTRATION_HITL, orchestration-dispatch (display string), AUTONOMOUS_LOOP
  and SUPERPOWERS_INTEGRATION. REMEDIATION's finding intake now names the
  dual-verdict report schema fields exactly (spec_compliance/ac_walk,
  BLOCKING/NON-BLOCKING/failure_scenario, cannot_verify as evidence gaps) —
  a review-FAIL dispatch buckets without guessing.
- New hygiene sweep test_043 keeps the old taxonomy from creeping back
  (whitelist anchored to the hit path prefix — review NB-1 remediated
  in-tree).
- Validation PASS (independent inventory MATCH; adversarial probe proved the
  sweep non-tautological); dual-verdict review PASS (measurement-gate data
  point #3).

## [v2026.07.20] — chore: session lessons promoted into the vendored layer (CHANGE-0015 / SPEC-0023)

- Universal workflow lessons from the 2026-07-15/16 sessions now live in the
  sync-managed layer (LEARNED.md never syncs — project-owned): SKILL_PR gains
  a MERGE-CONFLICT RESOLUTION step (INDEX regenerate / CHANGELOG stack both /
  EVENTS union / conflict-marker grep before git add), verify-the-merge-
  happened (MERGE_HEAD/2-parents — a dirty tree makes git merge abort
  silently) and cleanup-only-after-PR-reads-MERGED; INTAKE_COMMON + SKILL_PR
  carry never-predict-a-number-before-allocation.
- doc_number_guard default flipped to ENFORCE (template): staged DRAFT docs
  now block the commit; safe for the dev flow because drafts stay untracked
  until the ceremony allocates before staging (proven on the real hook incl.
  adversarial CRLF-config and number:null probes).
- SKILL_LOOP preflight runs layer-drift.mjs as one informational line (silent
  when absent) — vendored projects see layer drift at session start.
- Validation PASS (independent; enforce flip reproduced from scratch); dual-
  verdict review PASS (measurement-gate data point #2; one accepted
  disposition recorded in decisions.jsonl).

## [v2026.07.20] — fix: STATE list-field integrity (ISSUE-0007 / SPEC-0022)

- Three corruption sightings in one day traced to two engine defects:
  appendListItems hardcoded sibling indent at key+2 (mis-indented siblings on
  deeper lists), and fieldSpan's strict `>` excluded 0-relative block
  sequences under a bare key (whole-field rewrites -> orphaned `- ` lines =
  invalid YAML). Both fixed in lib/state-engine.mjs; 2-/4-relative behavior
  byte-invariant (golden-diffed).
- check-state gains structural lints that make this class fail LOUD:
  listIndentViolations (mixed item indents) + orphanItemViolations (orphan
  item after an inline-valued key) — no YAML dependency, wired into check and
  post-repair paths. Previously check-state passed on corrupted files while
  PyYAML crashed.
- metrics-flush ephemeral cleanup keeps dotfile keepers (.gitkeep swept in
  its first production run); STATE_FALLBACK gains last_validation.ref_id
  parity.
- Full gate history: validation FAIL (independent probe found the fieldSpan
  gap beyond the original scope) -> remediation -> fresh validation PASS
  (6/6) -> dual-verdict review PASS (first post-merge run of the new review
  contract; one accepted detection boundary recorded in decisions.jsonl).

## [v2026.07.20] — feat: single dual-verdict code review (RFC-0008 / SPEC-0021)

- Two-stage review replaced by ONE read-only pass returning two verdicts —
  spec_compliance (AC-table walk with per-AC citations) and code_quality
  (BLOCKING/NON-BLOCKING with file:line + failure scenario) — plus a MANDATORY
  cannot_verify list (silent gaps become named ones). SKILL_CODE_REVIEW
  766 -> 213 lines; H6 warnings policy and H3 external-review-response kept
  verbatim.
- Anti-gaming contract in SUBAGENT_PROTOCOL: no coaching, no pre-rating, no
  scope-exclusions by the dispatcher; diff handoff by path list; STATE write
  only when the dispatch grants it (single-writer in parallel mode).
- Measurement gate: deferred Spec-AC-05 row — compare review tokens/duration/
  remediation cycles over the next 5 reviewed scopes vs two-stage history in
  METRICS.jsonl; revert = git restore of the prior prompt.
- Dogfooded on its own delivery: first dual-verdict review returned PASS with
  2 NON-BLOCKING findings (NB-2 STATE-authority ambiguity remediated in-tree;
  NB-1 old-taxonomy drift filed as CHANGE-0014) and a meta-note feeding the
  measurement gate. Evidence base: RES-0001 F4 + Superpowers v6.0 evals
  (equal quality, ~50% tokens, 2x speed) + own telemetry (review+remediation
  ~= 88% of implementation wall-clock).

## [v2026.07.20] — feat: doctor reports vendored-layer drift (CHANGE-0013 / SPEC-0020)

- A target project's vendored .aai/ layer silently ages — fixes land in canon
  and nobody is told (operator hit this twice with ISSUE-0006/0008). New
  .aai/scripts/layer-drift.mjs compares the AAI_PIN commit against canonical
  main with honest tiers: local repo -> exact "BEHIND by N", ls-remote ->
  inequality only, offline/no pin -> unverifiable info (never a failure).
  Doctor gains CAT-13 wiring; exit 0/3/4/2 + --json.
- AAI_PIN contract extended with a "Canonical repo:" line stamped by both
  aai-sync.sh and aai-sync.ps1 (fork-safe: NO hardcoded upstream fallback).
- Review B1 caught pre-merge: the CLI main-guard never fired from paths with
  spaces (percent-encoding) or through symlinks (macOS /tmp) — silently exit
  0, which doctor would read as green. Fixed with decoded+realpath guard +
  TEST-014 regression; follow-up noted for the same latent pattern in other
  script guards.
- 14 fixture tests, zero real network; validation PASS (A/B hardening repro);
  re-review PASS.

## [v2026.07.20] — fix: empty-type width follows the project's dominant convention (ISSUE-0008)

- Operator follow-up to ISSUE-0006: the empty-type width defaults encoded this
  template repo's practice, so a vendored project with an ALL-3-digit
  convention would still get 4-digit for the first doc of a new type. Width
  cascade now: type's own docs -> project-dominant width (mode across all
  numbered governed docs) -> greenfield per-type defaults.
- TDD TEST-017 RED->GREEN (3-digit project mints RFC-001; type-own 4-digit
  inheritance still wins over dominant 3); SPEC-0015 amendment + INTAKE_COMMON
  wording extended same-day.

## [v2026.07.20] — feat: mechanize deterministic ticks (CHANGE-0009 / SPEC-0019)

- The orchestrator's 14-rule dispatch decision, metrics flush arithmetic, and
  metrics report aggregation were LLM ticks doing switch-statement work
  (RES-0001 F2). Now scripts: orchestration-dispatch.mjs (pure decide() over a
  read-only STATE snapshot; JSON dispatch block; exit 0 dispatch / 3 no-action
  / 4 needs-LLM fail-closed), metrics-flush.mjs (line-surgical STATE cleanup —
  never yaml.dump, header byte-preserved; ledger-before-reset; H5 partial
  reset; idempotent resume; --dry-run), metrics-report.mjs (byte-deterministic
  golden-testable).
- state.mjs line engine extracted to lib/state-engine.mjs (verbatim; 54-test
  suite guarded the refactor); shared lib/guard-config.mjs is now the single
  parser of docs-audit.yaml (hooks' greps anchored to column 0 to match —
  review W2; glued-comment token aligned); lib/pricing.mjs shares the
  lookup_rules resolver.
- Prompts shrunk to wrappers: ORCHESTRATION 181->40, METRICS_FLUSH 113->31,
  METRICS_REPORT 49->15 lines.
- docs-audit suite restored to a full green run (92 PASS): the CHANGE-0012
  regression stanza builds its own DRAFT fixture (the hardcoded repo path
  aborted the suite after allocation renamed it); self-containment guard
  de-vacuoused (review W1).
- TDD 19/19 RED->GREEN; independent validation PASS (sha256 zero-write proofs,
  header byte-diff, resume idempotence); review PASS (rule-fidelity FAITHFUL
  vs the old prose, flush-reset field diff complete, extraction VERBATIM;
  W1/W2 remediated, W3/W4 promoted with operational note).
- Dogfood: the dispatch script's first real decision (rule 11 -> Validation,
  must_differ on model) was executed as this scope's own validation run.

## [v2026.07.20] — fix: number width follows the type's convention (ISSUE-0006)

- SPEC-0015's allocator and the index generator hardcoded 4-digit padding,
  clashing with the pre-existing 3-digit PRD convention (PRD-001 examples
  across the canon). Reported by the operator. Parsing was already
  width-agnostic (no guard blindness — render-only bug).
- Allocator now inherits the display width from the type's highest-numbered
  existing doc (base ref preferred), with per-type defaults for empty types
  (PRD: 3-digit; everything else 4-digit). Width is stable within a batch.
- Index display id for a numbered file is taken from the FILENAME verbatim
  (PRD-001-x.md -> PRD-001, never re-padded to PRD-0001).
- Cross-padding duplicates (PRD-001 vs PRD-0001) still flagged (numeric key).
- TDD: TEST-016 RED->GREEN; doc-numbering + prompt-diet suites green; audit
  CLEAN; existing 4-digit sequences unchanged (regression-tested).

## [v2026.07.20] — feat: model tiering with teeth (CHANGE-0010 / SPEC-0018)

- The MODEL SELECTION tiering contract existed in one prompt and was enforced
  nowhere (RES-0001 F2). Now: MODEL is a required dispatch-contract field
  (SUBAGENT_PROTOCOL + ORCHESTRATION_PARALLEL gains the full tiering text);
  `state.mjs set-validation --model` mechanically checks validator vs
  implementer (normalized base id, [1m]-suffix aware; report-only default,
  `independence: enforce` refuses the write exit 1; invalid config value fails
  open WITH a stderr notice — review W1).
- PRICING.yaml refreshed: current Claude family prices, lookup_rules
  (strip-suffix -> aliases -> exact -> longest-prefix -> unknown), stale
  entries pruned, last_verified_utc stamped — every model id in METRICS.jsonl
  history now resolves.
- append-run warns (once, stderr) when tokens are omitted, so the never-fed
  cost pipeline becomes visible; 4 mechanical skill wrappers pinned to
  `model: haiku`.
- Hybrid TDD 11/11 RED->GREEN; independent validation PASS (probes reproduced,
  write-ordering verified); review PASS (W1 remediated, W2 promoted;
  cross-stream merge with CHANGE-0011 simulated clean).

## [v2026.07.20] — chore: prompt-layer diet phase 1 (CHANGE-0011 / SPEC-0017)

- Prompt corpus cut by ~35 KB (~10%): the 4 intake boilerplate blocks moved to
  one shared .aai/INTAKE_COMMON.md (8 files -> 1 pointer each; fixed the
  INTAKE_CHANGE metrics-question typo drift the duplication predicted);
  SKILL_PROFILE rewritten 737 -> 79 lines over real data sources (fictional
  Profiler deleted); ~22 state.mjs-absent FALLBACK blocks + 5 STATE-WRITE
  SAFETY footers consolidated into .aai/STATE_FALLBACK.md with 2-line pointers.
- SKILL_LOOP caching guidance fixed (frozen canon first, volatile STATE last —
  was inverted, guaranteeing a per-tick cache break) and the orchestrator
  payload switched to the ~1KB loop-digest.mjs --json summary instead of the
  full 27KB STATE.yaml (orchestrator reads STATE from disk itself).
- New suite tests/skills/test-aai-prompt-diet.sh (10 tests, grep-RED evidence).
- Loop validation PASS (independent, Sonnet; KB delta re-measured via stash);
  review PASS (digest-sufficiency analyzed SAFE; N1/N2 remediated, N3/N4
  promoted). RES-0001 finding F3, phase 1.

## [v2026.07.20] — fix: slug refs across the tooling family (CHANGE-0012 / SPEC-0016)

- SPEC-0015 made docs slug-first until merge, but `state.mjs` rejected slug refs
  (`REF_RE ^[A-Z]+-\d+$`) and DRAFT basenames were invisible to the whole
  docs-audit scan — so `--gate <slug>` missed them and `--check --path <DRAFT>`
  passed vacuously ("Scanned: 0 docs", exit 0). Root cause was the scan set,
  not gate resolution (found by Planning's code-reading, probe-verified).
- `state.mjs`: refFlag accepts the disjoint slug shape
  (`^(?=[a-z0-9-]{3,53}$)...`) beside TYPE-000N; bare YAML-keyword slugs
  (null/true/false/yes/off) refused pre-write (review W1 — unquoted they
  silently re-type as YAML booleans/null).
- `docs-audit-core.mjs`: `<TYPE>-DRAFT-<slug>.md` admitted to the scan;
  `gateDoc` two-pass resolution (frontmatter-id first, display-id second) with
  fail-closed ambiguity (exit 2 listing candidates — replaces silent
  first-file-wins).
- RES-0001 closeout metadata completed (links.pr/commits + ac_evidence event),
  clearing the pre-existing probable-false-done drift that blocked 5 real-repo
  CLEAN test assertions across suites.
- TDD 11/11 RED→GREEN; independent validation PASS (7/7 AC re-verified,
  stash-proofed pre-existing failures); code review PASS (W1 remediated,
  W2 promoted as documented limitation, W3 remediated).

## [v2026.07.20] — feat: collision-free doc numbering across parallel clones (RFC-0007 / SPEC-0015 / PR #48)

- Doc IDs were minted by a working-tree scan at intake, so two clones off the
  same `main` both minted the same `TYPE-000N` and collided at merge. New model:
  intake assigns a stable slug (`id: <slug>`, `number: null`,
  `<TYPE>-DRAFT-<slug>.md`); the sequential `TYPE-000N` is allocated at the merge
  serialization point — collision-proof by construction (merges to `main` are
  serialized, so the second brancher re-derives the next number).
- New `.aai/scripts/allocate-doc-number.mjs`: computes the next number from the
  BASE REF via `git ls-tree` (never the working tree), renames DRAFT→numbered,
  stamps `number`, rewrites references, regenerates the index. `--all`, `--path`,
  `--dry-run`, `--backfill`, `--guard`; exit codes 0/2/3/4.
- Guards in `pre-commit-checks.{sh,ps1}` (CHECK 8): no-DRAFT-at-merge and
  duplicate-number, report-only by default, flippable via
  `doc_number_guard: enforce` in `docs/ai/docs-audit.yaml`.
- `generate-docs-index.mjs` derives the display id from `number` and surfaces
  unnumbered drafts distinctly; backward compatible — legacy docs without a
  `number` field render byte-identically.
- Wiring: `SKILL_INTAKE` + all 8 `INTAKE_*` create DRAFT+slug; `SKILL_PR` runs the
  allocator before staging; RFC/SPEC templates carry `number` + a
  slug-as-primary-key note. Additive + degrade-and-report: allocator absent →
  intake falls back to scan-and-mint, the guard is the backstop.
- Realizes the cross-developer coordination RFC-0004 explicitly deferred;
  complementary to the machine-local `docs-lock.mjs`, not a replacement.
- Verification: 13/13 new tests green (TEST-006 concurrency centerpiece
  RED-proofed against a working-tree-only stub); `docs-audit --check --strict`
  CLEAN; existing suites unaffected.

## [v2026.07.20] — state/hygiene: post-release follow-ups (CHANGE-0008 / SPEC-0014)

- `state.mjs --clear <fields>` on set-worktree/set-code-review/set-validation/
  set-focus: closed per-subcommand whitelists (verdict/status fields excluded —
  reset-block owns them), scalars→null, lists→[], idempotent, atomic. Closes the
  "stale fields leak across scopes and need hand edits" gap observed in three
  consecutive loop runs.
- `set-phase --spec-path` now places `spec_path` inside the work-item block
  (was: spliced after the trailing blank line).
- `aai-auto-trigger` DEPRECATED: the .claude/triggers.json mechanism it
  configured has no runtime consumer (SPEC-0013 D8 grep-proof); prompt is now a
  deprecation notice, wrappers/USER_GUIDE/AGENTS/catalog aligned.
- Review hardening: E1 prototype-chain whitelist bypass (--clear toString wrote
  junk with exit 0) fixed via Object.hasOwn; repeated --clear accumulates
  (MULTI_FLAGS); fieldSpan handles blank-line paragraphs in block scalars.
  First live exercise of the SPEC-0012 review-FAIL reset-block transition.

## [v2026.07.20] — docs: canonical-surfaces refresh (TECHNOLOGY contract, PLAYBOOK, AGENTS, shims, catalogs)

- **docs/TECHNOLOGY.md** rewritten from the March auto-generated stub
  ("Unknown / Not detected") into an evidence-based contract following
  `.aai/templates/TECHNOLOGY_TEMPLATE.md`: dependency-free Node ESM tooling,
  bash-3.2 test compatibility, PowerShell 5.1/7 mirrors, ps1-quality CI,
  `state.mjs` STATE discipline, append-only JSONL ledgers.
- **.aai/PLAYBOOK.md** updated from the legacy four-role model to the six-phase
  loop (adds Implementation Preparation / worktree gate and Code Review) with a
  current lifecycle: intake, loop, `/aai-pr` (agent opens the PR, never merges),
  operator merge, closeout; names `state.mjs` as the only sanctioned STATE writer.
- **.aai/AGENTS.md** fixed stale paths (`ai/*.prompt.md`, bare `PLAYBOOK.md`),
  added `state.mjs` to canonical sources, added the missing skill prompt entries
  to the catalog, documented the docs-audit close gate / body lint hook keys
  under Quality Gates, and named `/aai-pr` as the closeout step.
- **SKILLS.md**, **docs/SKILL_CATALOG.html**, **CODEX.md**, **GEMINI.md**
  catalogs refreshed: missing skills (pr, docs-audit, docs-canon, test-canon)
  added as rows and detail blocks, catalog data regenerated to the full wrapper
  set with Code Review and Pull Request flow stages, and the shims' inline skill
  enumerations replaced with a deferral to SKILLS.md / USER_GUIDE (no hard-coded
  skill counts anywhere).
- **.aai/workflow/WORKFLOW.md**, **.aai/system/AUTONOMOUS_LOOP.md**,
  **docs/TODO.md** touched up: PR-ceremony gate line and `close_gate`/`body_lint`
  key names in the workflow, six-phase entity naming in the loop doc, and a
  "Shipped since" record (RFC-0002/0003/0006, SPEC-0011/0012/0013, v2026.07.04)
  in the TODO.

## [v2026.07.20] — docs: entry-point restructure (README/docs-README/USER_GUIDE)

- **README.md** rewritten as a lean landing page (~600 → ~250 lines): hero,
  install/sync surface, and a new Orientation section (six-phase loop with the
  worktree gate and Code Review, corrected repository map, runtime log catalog,
  intake language policy) plus a pointer block to canonical sources. Stale
  content removed: hard-coded skill counts, four-phase loop descriptions,
  duplicated skills overview/table, and stale common flows.
- **docs/README.md** rewritten as a thin index of the `docs/` tree (one line
  per subdir, correct set incl. requirements/roles/templates/workflow/ai),
  deferring to the root README for install and USER_GUIDE for usage.
- **docs/USER_GUIDE.md** gains the content moved out of README: shell loop
  runner reference (`autonomous-loop.sh/.ps1`) under Workflows, the
  self-hosting contract + smoke tests under Maintenance & Testing, and a FAQ
  subsection under Troubleshooting.
- Skill counts are no longer hard-coded anywhere in the entry-point docs —
  they defer to the USER_GUIDE Skills Catalog.

## [v2026.07.04] — hygiene: workflow hygiene pack (CHANGE-0007 / SPEC-0013)

Eight workflow-hygiene gaps closed in one pack (PR #36, closeout #37):
- **Body lint (H1):** `docs-audit.mjs --lint-body` / `--lint-body-file` — flags
  stray tool markup (`</content>`, `<result>`), unbalanced code fences, and
  leftover template placeholders in governed docs; fenced blocks and inline code
  spans are never flagged. Report-only by default, `--strict` promotes; wired
  into intake POST-SAVE and the pre-commit hook (`body_lint` config key,
  staged-blob discipline). First corpus scan caught a real legacy escape in
  SPEC-0007.
- **PR ceremony (H2):** new `/aai-pr` skill — scope-only staging (no `git add
  -A`), a mandatory staged-vs-scope audit, conventional commits, PR body
  template, and a hard NEVER-merge boundary (merging is operator-only).
- **Review-response flow + warnings policy (H3/H4/H6):** SKILL_CODE_REVIEW now
  codifies the external-PR-comment workflow (fetch → triage → RED-proofed fix →
  inline reply → push), mandates staging review reports with the scope commit,
  and requires every WARNING on a PASS to be remediated or recorded
  (decisions.jsonl / follow-up ref); wrap-up surfaces unrecorded ones.
- **Partial-flush verdict reset (H5):** METRICS_FLUSH resets
  `last_validation`/`code_review` when the flushed item was the current focus
  (ledger-before-reset), so verdicts no longer leak into the next scope.
- **Fixture diversity (H7):** SKILL_TDD + SKILL_TEST_CANON require degenerate
  fixtures (empty, fully-covered, multi-source, mid-operation failure).
- **Wrapper/trigger cleanup (H8):** consumer-less `triggers.json` promise
  removed; SUBAGENT-STOP added to aai-wrap-up/aai-flush; invoke lines unified;
  SKILL_META documented as the session-start-injected prompt.
- Post-review hardening: hooks read gate config from the staged/HEAD blob (both
  `body_lint` and `close_gate` — same TOCTOU class as SPEC-0011 F2), staged-file
  loops are space-safe, lint masking handles multi-line inline spans.

## [v2026.07.04] — loops: transactional STATE CLI + transition fixes (CHANGE-0006 / SPEC-0012)

Closes the root cause of repeated STATE.yaml corruption: runtime state edited
as free-text YAML by LLMs with no transactional primitive (PR #34, closeout #35).
- **`.aai/scripts/state.mjs`** — 11 subcommands (`set-focus/phase/validation/
  code-review/strategy/worktree/tdd-cycle/human-input`, `append-run`,
  `log-tick`, `reset-block`): closed-set enums (exit 2), integrity refusal on a
  corrupt STATE (exit 1), atomic tmp+rename writes with a crash-injection test
  hook, self-stamped timestamps, comment/key-order-preserving edits, optimistic
  concurrency check, strict per-subcommand flags (a misspelled `--flag` fails
  loud instead of silently dropping data).
- **`lib/state-core.mjs`** shared with `check-state.mjs` (CLI contract
  unchanged); inline-header conflict detection in both writer and validator.
- **Nine prompts migrated** (PLANNING, IMPLEMENTATION, VALIDATION, REMEDIATION,
  SKILL_TDD, ORCHESTRATION ×2, METRICS_FLUSH, SKILL_LOOP) to the CLI as the
  primary path, with a `state.mjs is absent` fallback for vendored repos.
- **Transition fixes:** REMEDIATION resets only failed verdict blocks and never
  writes its own verdict; ORCHESTRATION re-dispatches an independent
  Validation/Review after remediation (no more self-validation / rule-10 loop).
- **Implementer AC-table reconciliation:** IMPLEMENTATION step 9b / SKILL_TDD
  Phase 4 reconcile the spec's AC-Status table and run `docs-audit --gate`
  before handoff — validated live (first-try Validation PASS on both loops that
  ran after this landed).

## [v2026.07.04] — docs-audit: close-time guardrails (CHANGE-0005 / SPEC-0011)

Prevents "git-closed but AAI-unreconciled" specs (PR #27, closeout #28; evidence
from downstream fh-workspace):
- **G1 close gate:** `docs-audit.mjs --gate <DOC-ID>` — offline structural
  predicate (missing AC-Status table / non-terminal row / done row with empty
  Evidence / invalid Review-By ⇒ exit 1). Wired into the VALIDATION done-flip,
  METRICS_FLUSH, and wrap-up (advisory).
- **G2 close telemetry:** new `work_item_closed` + `code_review_completed`
  events; report-only missing-close-telemetry check for done docs without a
  close event.
- **G3 truthfulness:** `Review-By: code-review` claims without a corroborating
  event/artifact yield the report-only verdict `review-claim-unbacked`.
- **G4 near-miss detection:** almost-canonical AC tables (`Evidence (TEST)`
  columns, non-canonical headings) emit an explicit WARNING instead of being
  silently misread.
- **G5 pre-commit block (opt-in):** a staged `status: done` flip that fails the
  gate aborts the commit under `close_gate: enforce` (report-only default);
  the hook gates the STAGED blob (`--gate-file`), not the worktree.
- Post-review fixes: `work_item_closed` requires validation+code_review fields;
  digit-boundary artifact-id matching (SPEC-001 vs SPEC-0011).

## [v2026.07.04] — tests: canonicalization skill `aai-test-canon` (RFC-0006 / SPEC-0008) + engine fixes

Two-phase test-side twin of `aai-docs-canon` (PR #22): Phase 1 builds a
traceability matrix + coverage-gap report and proposes a per-domain test map
(HITL gate); Phase 2 consolidates tests into `tests/canonical/`, archives
originals with back-links, and scaffolds RED stubs for uncovered criteria
(hand-off to `aai-tdd`), with idempotent re-runs and `--drift`/`--resync`.
Post-merge review fixes (PR #29, #31): Phase 2 preserves source test logic (runs
archived copies instead of replacing them with all-RED stubs; stubs only for
genuinely uncovered criteria), verifyRunner gates on GREEN before archiving and
re-verifies after the rewrite to archived paths, native runners per test type
(.sh/.ps1/.py/.mjs), per-criterion Phase-1 coverage, atomic multi-source archive
with rollback, zero-stub domains generate valid bash.

## [v2026.07.04] — chore: test portability + repo hygiene

- `test_index_continue_on_error` realigned with the generator's
  degrade-and-report default (`--strict` is the gate) — the stale hard-fail
  expectation failed on every run (issue #30, PR #32).
- `test-aai-intake.sh` made bash-3.2 portable (`${var^^}` removed) — the suite
  errored on macOS default bash (PR #33).
- 11 orphaned code-review reports from prior sessions committed to
  `docs/ai/reviews/` (PR #33).

## [v2026.07.04] — ci: ps1-quality GitHub Actions workflow

First CI for the repo (`.github/workflows/ps1-quality.yml`), wiring the
PowerShell quality gate so the parse-error class that broke /aai-update is caught
on every PR/push that touches a `.ps1` (path-filtered, so unrelated changes do
not trigger it). Two jobs:
- **gate** (ubuntu, pwsh 7): runs `tests/skills/test-ps1-quality.sh` — parse-check
  every `.ps1` + PSScriptAnalyzer `PSUseCompatibleSyntax` (5.1 + 7.0) + the Pester
  smoke tests. Installs PSScriptAnalyzer + Pester (cached).
- **windows-5_1** (windows): parse-checks every `.ps1` under **real Windows
  PowerShell 5.1** (the environment that actually broke) and under pwsh 7.

## [v2026.07.04] — chore: PowerShell test infrastructure (lint + Pester + pre-commit parse gate)

Adds a real verification harness for the vendored `.ps1` scripts so the class of
failure that broke /aai-update (a PowerShell PARSE error that only surfaces when
a user runs the script) cannot reach `main`.

- **`tests/skills/test-ps1-quality.sh`** — bash gate (skip-42 if `pwsh` absent):
  (1) parse-checks every `.aai/scripts/*.ps1`; (2) PSScriptAnalyzer
  `PSUseCompatibleSyntax` against **Windows PowerShell 5.1 + pwsh 7.0** (blocking)
  plus parse-level Errors; (3) runs the Pester smoke tests. Quality warnings are
  reported but non-blocking. Result on the current tree: all `.ps1` parse,
  5.1+7.0 compatible, Pester 6/6.
- **`tests/skills/aai-update.Tests.ps1`** — Pester v5 smoke tests for
  `aai-update.ps1`: parses; the dry-run "Would run" line prints; native `-DryRun`
  and bash `--dry-run`/`--repo=`/`--ref` both work (flag parity from PR #16); the
  canonical-repo guard refuses (exit 2); unknown args warn without crashing.
- **`.aai/scripts/PSScriptAnalyzerSettings.psd1`** — codifies signal-vs-noise
  (CLI scripts intentionally use Write-Host etc.).
- **Pre-commit parse gate** — `pre-commit-checks.{sh,ps1}` gain CHECK 7:
  parse-check staged `.ps1` and block the commit on a parse error (no-op when
  `pwsh` is unavailable). RED-proofed (a deliberately broken staged `.ps1`
  blocks with exit 1).
- Fixed a real latent bug surfaced by the scan: `pre-commit-checks.ps1` assigned
  to the automatic variable `$matches` (renamed to `$hits`).

## [v2026.07.04] — fix(aai-update.ps1): PowerShell parse + flag parity

Fixes `/aai-update` failing under PowerShell. Two issues in
`.aai/scripts/aai-update.ps1`:

- **Parse error on the dry-run line.** The `-DryRun` "Would run:" message used a
  fragile nested doubled-quote literal (`"... -TargetRoot ""$Target"""`). While
  this parses in a pristine file, it is the kind of construct that gets mangled
  in the field (a dropped quote yields `The '<' operator is reserved for future
  use` / `The string is missing the terminator` and the script fails to parse
  before doing anything). Rewritten with a single-quoted format string —
  `('- Would run: SOURCE/...-TargetRoot "{0}"' -f $Target)` — which has no nested
  quoting and cannot be corrupted by an encoding/CRLF/ASCII sweep.
- **Flag-style mismatch.** The `/aai-update` skill forwards the user's flags
  verbatim in bash long-flag form (`--dry-run`, `--repo`, `--ref`, `--keep-temp`,
  `--force`), but the script only bound the native `-DryRun`/`-Repo`/... params,
  so any forwarded `--flag` raised a binding error. The script now also accepts
  the bash long-flag spellings (via a remaining-args normalizer), matching the
  bash twin's contract.

To unblock a project whose vendored copy already has the broken dry-run line:
replace that one `Write-Host "- Would run: ... -TargetRoot ""$Target"""` line
with `Write-Host ('- Would run: SOURCE/.aai/scripts/aai-sync.ps1 -TargetRoot "{0}"' -f $Target)`,
then re-run `/aai-update` to pull the rest.

## [v2026.07.04] — loops: automatic parallel-mode detection (RFC-0005)

Makes the existing parallel scheduler (`ORCHESTRATION_PARALLEL.prompt.md`, shipped
with RFC-0004's locks) actually reachable. Previously `SKILL_LOOP`'s "RUN
ORCHESTRATION" step hard-dispatched the single-agent orchestrator every tick, so
the parallel capability was operationally dead. RFC-0005
([SPEC-0005](docs/specs/SPEC-0005-automatic-parallel-mode-detection.md)) adds
**automatic, fail-closed detection** of when a tick may safely fan out, and the
wiring that routes the loop to the single or parallel orchestrator.

### Added
- **`.aai/scripts/orchestration-mode.mjs`** — a deterministic, unit-testable
  selector CLI (ESM, `docs-lock.mjs` conventions). Pure decision function over a
  normalized JSON input (stdin or `--input <file>`); prints `{mode,k,groups,reasons}`
  (exit 0; bad input/flag exit 2). Independence is computed by **path-overlap +
  fail-closed**: two scopes are independent only if their declared review-scope
  paths do not overlap (boundary-prefix test) and neither is the other's
  parent/child; a missing, empty, or bare-glob path is **uncertain -> sequential**
  (never co-scheduled). `mode=auto` goes parallel iff >=2 mutually independent
  scopes, `K = min(k_max, count, budget)`; `k_max` default 2. `effective_cap =
  min(k_max, max_k_budget, locks_available ? inf : 1)` — **docs-lock.mjs absent
  degrades to K=1**. Read roles parallelize across disjoint scopes; write roles
  need provably-disjoint inline paths or `isolation=worktree`. Override
  `orchestration_mode` in {auto,single,parallel}: `single` forces single,
  `parallel` is a safety-gated opt-in (still respects the overlap test).
- **`tests/skills/test-aai-orchestration-mode.sh`** — TEST-001..017. The SAFETY
  pair (disjoint -> parallel; overlapping -> never co-scheduled) is RED-proofed
  against a deliberately overlap-BLIND stub (the rejected Option C) via
  `DOCS_SELECTOR_SCRIPT`, mirroring SPEC-0004's non-O_EXCL stub.

### Changed
- **`SKILL_LOOP.prompt.md`** "RUN ORCHESTRATION" is now MODE-AWARE: it discovers
  actionable scopes, gathers their declared paths + `role_kind`/`isolation` +
  docs-lock presence, invokes the selector, dispatches `ORCHESTRATION.prompt.md`
  (single, the default) or `ORCHESTRATION_PARALLEL.prompt.md` (parallel), and
  records `orchestration.mode`/`k`/`groups` in STATE + the tick log.
- **`ORCHESTRATION.prompt.md`** and **`ORCHESTRATION_PARALLEL.prompt.md`** each
  cross-reference the selector as the upstream mode decision.
- **`docs/ai/STATE.yaml`** schema header documents the optional, non-breaking
  `orchestration.mode|k|groups` block (absent == `auto`).
- **`docs/USER_GUIDE.md`**: new "Parallel multi-agent orchestration" how-to
  (auto/single/parallel, the independence rule, `k_max=2`, the docs-lock
  degrade-to-single, and how to override).

### Note (retroactive — RFC-0004)
- The **`.aai/scripts/docs-lock.mjs`** atomic scope-lock primitive and the
  single-writer protocol shipped with RFC-0004
  ([SPEC-0004](docs/specs/SPEC-0004-enforced-multi-agent-state-locking.md)) but
  never received a CHANGELOG entry. Recorded here: `docs-lock` provides O_EXCL
  atomic per-scope leases (`acquire`/`release`/`list`/`reap`, TTL self-heal) under
  `docs/ai/locks/` (gitignored), and is the enforcement floor RFC-0005's selector
  degrades to single without.

## [v2026.07.04] — docs: canonicalization skill (`aai-docs-canon`, RFC-0003)

New re-runnable skill that consolidates **layered** documentation — an original
intake plus its chain of specs, sub-specs, addendums, and corrections — into a
single **canonical "current state" layer** categorized by functional domain,
while preserving the originals as an auditable history. Addresses the failure
mode where a doc set is exhaustive for audit but unusable as a working reference
(no single final view of what a feature does today).

- **Two-phase pipeline with a human gate** (`.aai/scripts/docs-canon.mjs`,
  `.aai/scripts/lib/docs-canon-core.mjs`): Phase 1 builds a supersession/
  dependency graph and proposes an AI domain map that the operator approves;
  Phase 2 auto-synthesizes one canonical doc per domain in `docs/canonical/`
  with five fixed layer sections (Overview/Intent · UI · Processes · Data model
  · Superseded decisions), moves originals to `docs/_archive/` with
  `status: archived` + a `canonical:` back-pointer, and harvests superseded docs
  into an audit trail. Re-runs report **drift** and never silently overwrite;
  `--phase2 --resync` re-synthesizes a drifted domain from current sources.
- **Safety**: an unsafe approved map (one source in two domains, archive
  destination collision, pre-existing destination) aborts before any file move
  (`validatePhase2Plan` pre-flight + `archiveSource` overwrite guard) — no
  partial mutation.
- **Shared-infra integration** (`docs-model.mjs`, `docs-audit-core.mjs`,
  `generate-docs-index.mjs`): new `canonical`/`archived` doc types and
  provenance frontmatter; `docs/canonical/` surfaced in `docs/INDEX.md`;
  `docs/_archive/` excluded from the active docs-audit scan so archived docs are
  not mis-flagged as orphans (the `_archive` vs `archive` EXCLUDE_DIRS
  reconciliation).
- Documented in `.aai/AGENTS.md` (Universal Skills) and `docs/USER_GUIDE.md`;
  contract in `docs/specs/SPEC-0002`, decision in `docs/rfc/RFC-0003`. Test
  suite `tests/skills/test-aai-docs-canon.sh` (RED-proofed TDD).

## [v2026.07.04] — loops: validator independence (separate context, not just a role)

Strengthens the anti-self-evaluation work below with the structural fix the
plan/build/judge demo actually relies on: the judge runs INDEPENDENTLY. An
adversarial prompt stance is hollow if the validator executes in the implementer's
own context — it inherits the builder's assumptions and rubber-stamps them.

- **Hard rule, validator independence** (`SKILL_LOOP.prompt.md` step 4,
  `VALIDATION.prompt.md`, `system/AUTONOMOUS_LOOP.md` §5): the Validation role must
  run in a context that did NOT produce the implementation — a dedicated validator
  subagent fed only the artifacts (spec, diff/paths, evidence, SUBAGENT_PROTOCOL),
  never the implementer's accumulated working context. Prefer a different model than
  the implementer (less likely to share blind spots). If true isolation is
  impossible, validate from a cleared/fresh context and record "validator shared
  context with implementer" as a residual risk — never silently self-validate.
  Previously dispatch only "preferred" a subagent and allowed an in-session
  fallback, which let the judge legally run inside the builder. New rationalization row.
- **Concrete "how to run the validator in another agent"**: `ORCHESTRATION.prompt.md`
  now emits a validator dispatch that requires an independent context AND a model
  different from the implementer (a separate axis from complexity right-sizing), and
  `SUBAGENT_PROTOCOL.md` gains a "Spawning a validator in a separate agent" recipe
  with the per-host mechanism (in-session agent/task tool with a model override;
  separate `claude -p`/CLI process headless; cleared-context fallback) — all sharing
  one INPUT contract (spec, diff/paths, evidence, STATE.yaml; never the builder's
  conversation).

## [v2026.07.04] — loops: anti self-evaluation (RED-proof + adversarial validation) + run-budget stop

Three guards drawn from loop-engineering practice (the Anthropic plan/build/judge
demo + "loops explained" guide): a loop must not grade itself, and its per-iteration
cost must be bounded.

- **RED-proof for AC-gating tests, any strategy** (`PLANNING.prompt.md`,
  `VALIDATION.prompt.md`): every test that gates a Spec-AC must be observed FAILING
  without the change before its passing counts — even under `loop`/`hybrid`, not
  just `tdd`. A test never seen failing may be tautological; requiring a real RED
  state stops the loop from rubber-stamping criteria it authored itself. Validation
  records missing RED-proof as a residual risk, or FAIL for security/data-integrity/
  bug-fix ACs. New rationalization rows on both sides.
- **Adversarial validation stance** (`VALIDATION.prompt.md`): the validator now
  defaults to FAIL and actively tries to REFUTE each done-claim. Self-evaluation is
  a trap — only reproducible external evidence (real exit codes, real-DB integration)
  counts; builder/self assertions are unmet claims. New invariant + rationalization rows.
- **Run-budget stop condition**: bound a loop's compounding cost. Runners
  (`autonomous-loop.{sh,ps1}`) gain `--max-run-seconds` / `-MaxRunSeconds`
  (cumulative wall-clock); the in-session loop (`SKILL_LOOP.prompt.md`) gains
  `max_run_tokens` / `max_run_cost_usd`, summed from best-effort usage telemetry
  (no-op when usage is absent — never fabricated). On exceed → escalate to HITL
  before starting another, costlier tick. Recorded as a `human_pause` stop reason.

## [v2026.07.04] — chore: make /aai-update deterministic (script, not narration)

`/aai-update` was a 113-line procedure the agent executed by narrating each of
seven steps (echoing clone/sync commands, reasoning per step) — slow and chatty.
The flow is fully deterministic, so it is now a script and the prompt is a thin
delegator:

- **New `.aai/scripts/aai-update.{sh,ps1}`**: one command does the whole update —
  auth-aware materialize of `main` (gh → git fallback, or a local checkout),
  canonical-repo guard (refuses to sync the AAI repo into itself; `--force`/`-Force`
  to override), runs `aai-sync`, prints concise post-sync evidence (changed files,
  AAI_PIN, conflict advisory), and cleans up the temp clone. `--dry-run` prints the
  plan without touching files; distinct exit codes (2 refused / 3 fetch failed /
  4 malformed source). The bash twin self-relocates to a temp copy so the sync
  overwriting `.aai/scripts/` mid-run can't pull the script out from under it.
- **`SKILL_UPDATE.prompt.md` slimmed** from ~113 to ~45 lines: run the one script,
  relay a short report, don't narrate steps or paste the full sync log. The agent
  now makes a single tool call instead of orchestrating seven by hand.

## [v2026.07.04] — unattended-safe loops: fresh-context recovery, propose-don't-ship, wake-up digest

Builds on the loop-hardening below to make an overnight/scheduled run genuinely
safe to leave alone — the gap between "a loop you babysit in chat" and "a loop
that works while you sleep". All three land in
`.aai/scripts/autonomous-loop.{sh,ps1}` (and the recovery semantics in
`SKILL_LOOP.prompt.md` / `system/AUTONOMOUS_LOOP.md`):

- **Fresh-context recovery before HITL**: on stagnation the loop now attempts ONE
  recovery tick in a clean context (a fresh agent process for the runners; a
  fresh subagent for the in-session loop) that re-derives state from the
  filesystem and is told via `AAI_RECOVERY=1` that it is stuck. A stuck loop is
  usually context rot, not an impossible task — re-introducing
  fresh-context-per-iteration (the Ralph Wiggum robustness trick we traded away
  for cache warmth) surgically unsticks it. Only if recovery also makes no
  progress does it escalate to HITL. Disable with `--no-recovery` / `-NoRecovery`.
  Logged as a `type: recovery` line in `LOOP_TICKS.jsonl`.
- **Propose, don't ship** (`--propose-only` / `-ProposeOnly`, optional
  `--propose-branch`): isolates all work on a dedicated `aai/loop-<timestamp>`
  branch, installs a temporary `pre-push` hook that HARD-blocks any push for the
  run (neither runner nor agent can ship), and prints a review summary at the
  end. The hook is restored on exit (success, error, or interrupt).
- **Wake-up digest** (`.aai/scripts/loop-digest.mjs`): turns `LOOP_TICKS.jsonl`
  into one human-readable summary (ticks, scopes, recovery outcome, stop reason,
  branch left for review, cost if recorded). Runners call it at the end and write
  `docs/ai/reports/loop-digest-<stamp>.md`; also runnable standalone
  (`--write`, `--json`). The chat/log becomes a status dashboard, not a babysit.

## [v2026.07.04] — loop hardening: stagnation guard, version + cost telemetry, L1 triage

Loop-engineering hardening informed by the Ralph Wiggum / loop-engineering
prior art (Huntley, Osmani, Anthropic "Building Effective Agents"). The AAI
loop already covered the core best practices (filesystem-as-memory, hard stop
conditions, maker≠checker, evidence-gated PASS); these close the remaining gaps:

- **Stagnation guard** (`SKILL_LOOP.prompt.md`, `system/AUTONOMOUS_LOOP.md`,
  `scripts/autonomous-loop.{sh,ps1}`): new `stagnation_limit` (default 3, also a
  `--stagnation-limit` / `-StagnationLimit` flag on the runners). When
  `focus_ref_id` and `validation_status` stay unchanged for that many
  consecutive ticks, the loop escalates to HITL (recording a `human_pause`)
  instead of spinning the remaining tick budget. Computed from existing
  `LOOP_TICKS.jsonl` fields — no new state.
- **Version drift telemetry**: each tick line now records `harness_version`
  (captured once at loop start, in both the in-session loop and the
  `autonomous-loop.{sh,ps1}` runners) so a behavior regression can be correlated
  with a harness upgrade. The runners also emit a per-tick `stagnation_count`.
- **Cost observability + caching discipline**: tick lines may carry optional,
  best-effort `input_tokens` / `output_tokens` / `cache_read_tokens` /
  `est_cost_usd` (only when the runtime exposes real usage — never fabricated).
  A new CACHING DISCIPLINE note codifies keeping the loop session-resident (not
  cron-per-tick) and a stable cacheable prefix, to stay inside the ~5 min cache
  TTL.
- **L1 triage** (`.aai/scripts/triage.{sh,ps1}`): cheapest rung of autonomy —
  a read-only health snapshot (docs drift via `docs-audit --quick`, state
  presence, working-tree, last tick). Writes nothing, safe to `/schedule`;
  `--check` exits 1 on real docs drift for use as a CI/daily alarm.

## [v2026.07.04] — chore: gitignore TDD evidence logs

`docs/ai/tdd/**` (red/green/refactor test-output logs) is now gitignored
with a `.gitkeep` placeholder — same policy as `docs/ai/reports/**`:
per-dev runtime evidence, pruned by METRICS_FLUSH after 7 days; durable
evidence lives in AC Status tables and EVENTS.jsonl.
`migrate-state-to-local.{sh,ps1}` additionally untracks any already
committed TDD logs and injects the ignore patterns in downstream projects.
Same treatment for `docs/ai/loop/` — ad-hoc per-tick scratch some loop
runs create; canonical loop state lives in STATE.yaml/LOOP_TICKS.jsonl
(local) and EVENTS.jsonl/METRICS.jsonl (committed). The migrate scripts'
gitignore checks are now CR-tolerant (CRLF downstream gitignores).

## [v2026.07.04] — CHANGE-0003: docs-audit verify mode

Adds the third skill mode
([CHANGE-0003](docs/issues/CHANGE-0003-docs-audit-verify-mode.md)):
semantic docs-vs-code reconciliation. The audit checks claims against
traces (commits, events); `verify` checks them against the code itself.

### Added
- `/aai-docs-audit verify <DOC-ID>`: the agent reads each acceptance
  criterion, probes the codebase (search, read, run existing tests —
  never writes code), and proposes per-AC verdicts (`implemented` with
  path:line or test evidence / `not-implemented` / `cannot-determine`).
  Operator approves per item; approved updates write the AC Status table
  and emit `ac_status`/`ac_evidence`/`doc_lifecycle` events, after which
  the standard gate and drift audit guard the doc. Expensive by design:
  one doc (or named small batch) per invocation.
- Guard test pinning that the skill prompt documents all three modes
  (audit / remediate / verify).
- USER_GUIDE: "three modes, three questions" overview and verify step in
  the retro-cleanup workflow.

## [v2026.07.04] — CHANGE-0002: docs-audit engine improvements, round 2

Triage and fixes for six further deficiencies from the downstream second
remediation pass
([CHANGE-0002](docs/issues/CHANGE-0002-docs-audit-engine-improvements-2.md)).
All six accepted (D11 partly already worked; verifying it exposed and
fixed a real prefix-match bug).

### Added
- Review-By accepts `<actor> <method>` composition: Claude model ids
  (`claude-sonnet-4-6`, ...) or `human`/`operator`(`:<name>`) plus a
  method from the label set, extended methods (`PlaywrightSuites`,
  `Validation`, `TDD-snapshot-scripts`; extensible via
  `review_by_methods` config), or `method:date`. Bare actor without a
  method stays invalid (D10).
- `PARENT-ID/<sub-item>` EVENTS refs documented (SKILL_LOOP,
  append-event header); engine evidence lookup now boundary-safe —
  `CHANGE-0045` events no longer count for `CHANGE-004` (D11).
- `plan_scan_mode` config (default `lenient`): `docs/plans/**` files
  without frontmatter inventory as operator plan files instead of
  orphans; `strict` restores the old behavior (D12).
- Index generator auto-demotes schema violations in legacy-classified
  docs (first commit before `legacy_until_date`) to the Skipped section,
  tagged `[legacy — auto-skipped]`; non-legacy violations still fail (D13).
- Suggested ID lists every ID shape in multi-ID filenames
  (`PRD-022 (primary) + PRD-024 + PRD-025`; `PRD-022 (primary) +
  TEST-021`) (D14).
- `category_prefixes` config (default `PHASE`, `MILESTONE`, `EPIC`):
  category-scoped filenames get unique slug IDs plus a Scope shown in
  `--list` (`DECISION-PHASE-0-scope` / scope `PHASE-0`) (D15).

### Fixed
- `firstCommitDate` no longer uses `git log --follow`, whose rename
  detection mis-attributed a file's add commit to an unrelated commit
  adding similar content — legacy/new classification could be wrong for
  similar-looking docs (found by the D13 fixture).

## [v2026.07.04] — CHANGE-0001: docs-audit engine improvements

Triage and fixes for nine deficiencies reported from the first real
downstream remediation run
([CHANGE-0001](docs/issues/CHANGE-0001-docs-audit-engine-improvements.md)).
All changes are relaxations or additive, default-off validators —
no breaking change for existing projects.

### Added
- Compound doc IDs (`SPEC-CHANGE-027`, `DECISION-RFC-002`,
  `SPEC-PROC-10`, `DECISION-SPEC-FE-13`, `SPEC-PRD-022`, ...) are now
  scanned: shared `DOC_ID_RE` allows letter segments between prefix and
  a 1-5 digit tail; the `→ DOC-ID` broken-ref matcher loosened
  identically (D1).
- Legacy `SPEC-FROZEN: true` body markers (bare, `**bold-key:**`,
  `**bold**: `, emoji-prefixed) make a `status: draft` doc effectively
  frozen — no more false probable-stale-open on frozen-in-body specs (D2).
- `amendment_note` / `amended_by` / `superseded_by` frontmatter fields
  recognized and surfaced in the digest Annotations section; enum
  unchanged (D3, option a).
- Review-By accepts skill literals (`TDD`, `Loop`, `code-review`,
  `manual`, `deferred`) and `label:YYYY-MM-DD` combos in both the audit
  and the INDEX generator; only dated forms feed overdue checks (D4).
- Drift digest gains a per-doc Triage commands block (`git log --grep`,
  `head -50 <path>`) (D5).
- Digest "Pending commit" notice lists scanned docs with uncommitted
  changes; regression test pins that verdicts always reflect the working
  tree, so adding frontmatter clears an orphan without committing (D6).
- `DOC_TYPE_ENUM` validation: unknown `type:` warns by default,
  `--strict-types` promotes it to a hard failure (D7).
- Orphan table gains a Suggested ID column inferred from the filename (D8).
- `generate-docs-index.mjs --continue-on-error`: renders a partial INDEX
  plus a "Skipped (schema violations)" section instead of hard-aborting;
  default CI behavior unchanged (D9).

## [v2026.07.04] — RFC-0002: docs hygiene and drift audit

Implements [RFC-0002](docs/rfc/RFC-0002-docs-hygiene-and-drift-audit.md)
([SPEC-0001](docs/specs/SPEC-0001-docs-hygiene-and-drift-audit.md)) in
response to a downstream triage brief documenting four drift classes:
orphan docs, false-done, stale-open, bulk frontmatter drift. The audit
REPORTS; the operator DECIDES — nothing is auto-fixed.

### Added
- `.aai/scripts/docs-audit.mjs`: classifies every prefixed doc under
  `docs/` (orphan / superseded / drifted / tracked-done / obsolete /
  tracked-open) and derives drift verdicts (`probable-false-done`,
  `probable-partial`, `probable-stale-open`) from frontmatter, AC tables,
  EVENTS.jsonl, and git evidence. Flags: `--check` (CI gate via exit
  code), `--quick` (counts only, no git probes), `--path`, `--strict`
  (enforce without config; intake post-save gate), `--no-event`.
- `.aai/scripts/lib/docs-model.mjs` + `lib/docs-audit-core.mjs`: shared
  doc-model parsers (extracted from the INDEX generator) and audit core.
- Optional committed config `docs/ai/docs-audit.yaml`
  (`legacy_until_date`, `stale_after_days`, `scan_exclude`,
  `backlog_globs`). Absent config means report-only — first runs never
  hard-fail legacy backlogs.
- `/aai-docs-audit` skill (`.aai/SKILL_DOCS_AUDIT.prompt.md` +
  `.claude/skills/aai-docs-audit/SKILL.md`) with an operator-approved
  interactive remediation mode for retroactive backfill.
- `docs/INDEX.md` sections: `Orphans (need triage)` and `Drift report`.
- `docs_audit` event type in `append-event.mjs` (counts payload), emitted
  best-effort by every non-quick engine run.
- `.aai/templates/DOCS_AUDIT_TEST_TEMPLATE.md`: portable CI gate wrappers
  (plain CI step, vitest, pytest).
- `tests/skills/test-aai-docs-audit.sh`: fixture-per-drift-class suite.

### Changed
- `SKILL_INTAKE.prompt.md` + all eight `INTAKE_*.prompt.md`: post-save
  template-compliance check (`--check --strict --path <artifact>`); an
  artifact cannot be reported saved while non-compliant.
- `SKILL_LOOP.prompt.md`: cheap `--quick` docs hygiene check once per
  tick, surfaced in the tick summary (never blocks).
- `VALIDATION.prompt.md`: step 8b done-transition assertion — a spec
  cannot move to `done` without a fully terminal, evidenced AC table.
- `SKILL_DOCTOR.prompt.md`: new CAT-11 Docs Hygiene category.
- `generate-docs-index.mjs`: now consumes the shared parser lib.

## [v2026.07.04] — RFC-0001: AC-level tracking and multi-dev STATE

Implements [RFC-0001](docs/rfc/RFC-0001-ac-tracking-and-multi-dev-state.md)
in three sequential PRs. Designed for zero breaking change in target
projects: the validation gate auto-detects opt-in by spec column, legacy
specs continue to behave exactly as before, and the STATE relocation
requires an explicit per-project migration step.

### Added
- Minimal frontmatter (`id`, `type`, `status`, `links`) on document
  templates: ISSUE, RFC, SPEC, REQUIREMENT, RELEASE, CHANGE, TECHDEBT,
  RESEARCH. Status enum: `draft | implementing | done | deferred | rejected | superseded`.
- SPEC_TEMPLATE: new "Acceptance Criteria Status" table with columns
  `Spec-AC | Description | Status | Evidence | Review-By | Notes`.
  Separate from the existing per-`TEST-xxx` lifecycle table.
- VALIDATION.prompt.md: AC STATUS GATE section with four rules
  (no silent partials, no unsubstantiated done, overdue Review-By blocks
  any PASS in the repo, anti-cheat minimum +14 days on Review-By).
- `.aai/scripts/generate-docs-index.mjs`: generates `docs/INDEX.md` with
  sections for Overdue / Active / Done / Drafts / Deferred / Blocked /
  Broken references / Rejected / Legacy. Tolerant to legacy docs. Marker
  discipline prevents overwriting hand-maintained INDEX.md.
- `.aai/scripts/append-event.mjs`: helper that appends a single audit
  event to `docs/ai/EVENTS.jsonl`. Event types: `ac_status`,
  `ac_evidence`, `defer_extended`, `doc_lifecycle`. Auto-fills `v`,
  `ts`, `actor`.
- `.aai/scripts/migrate-state-to-local.{sh,ps1}`: target-project
  migration helper. Untracks STATE.yaml + LOOP_TICKS.jsonl, adds
  gitignore entries, creates EVENTS.jsonl. Idempotent, dry-run flag,
  refuses dirty working tree, never auto-commits.
- `docs/ai/EVENTS.jsonl`: new shared append-only audit log.
- `.aai/scripts/install-pre-commit-hook.{sh,ps1}`: opt-in helper that
  installs a `.git/hooks/pre-commit` to auto-regenerate `docs/INDEX.md`
  when `docs/` changes.
- `SKILL_DOCTOR.prompt.md`: new CAT-10 health check for STATE migration
  consistency (gitignored vs tracked, missing EVENTS.jsonl).
- `aai-sync.{sh,ps1}`: auto-injects STATE.yaml and LOOP_TICKS.jsonl
  gitignore entries into the target `.gitignore` on every sync.

### Changed
- `docs/ai/STATE.yaml` and `docs/ai/LOOP_TICKS.jsonl` are now per-developer
  local (gitignored). Previously committed to git, this caused
  multi-developer merge conflicts. Cross-developer visibility moves to
  `docs/ai/EVENTS.jsonl` (committed, append-only).
- `SKILL_LOOP.prompt.md`, `VALIDATION.prompt.md`, `METRICS_FLUSH.prompt.md`:
  emit `ac_status`, `ac_evidence`, and `doc_lifecycle` events to
  `docs/ai/EVENTS.jsonl` via `append-event.mjs`. Emissions are best-effort;
  failure does not abort the primary operation.
- README.md: documented per-dev STATE policy, EVENTS.jsonl, and migration
  pointer; updated sync exclusion list to include `docs/rfc/`.
- `aai-sync.{sh,ps1}`: `docs/rfc/**` added to the documented project-owned
  exclusion list (implementation already never synced it).

### Migration (per target project)
1. `/aai-update` — pulls the new layer; gitignore entries auto-added.
2. `bash .aai/scripts/migrate-state-to-local.sh --dry-run` — preview.
3. `bash .aai/scripts/migrate-state-to-local.sh` — untrack STATE files.
4. Commit the resulting `.gitignore` change and the new `EVENTS.jsonl`.
5. `/aai-doctor` — verify migration completed cleanly.
6. (Optional) `bash .aai/scripts/install-pre-commit-hook.sh` to auto-regen
   `docs/INDEX.md` on every commit touching `docs/`.

Existing specs continue to validate exactly as before. The new AC STATUS
GATE activates only when a spec opts in by including a `Review-By` column
in its Acceptance Criteria Status table.

### Removed
- Nothing was removed. RFC-0001 is purely additive on the canonical layer.
- `docs/ai/STATE.yaml` and `docs/ai/LOOP_TICKS.jsonl` were untracked from
  the canonical repo (`git rm --cached`); the files remain on disk and
  continue to function as per-developer runtime state.

---

## Prior history

Earlier changes are recorded in `git log`. This CHANGELOG starts with
RFC-0001 — earlier features were tracked only in commit messages.
