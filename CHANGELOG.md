# Changelog

All notable changes to AAI are documented in this file. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). AAI does not yet
follow semantic versioning — entries are grouped by date or release event.

For target projects: run `/aai-update` to pull the latest layer. After
updating, run `/aai-doctor` to surface any migration actions specific to
your project (for example, the STATE-to-local migration introduced in
RFC-0001).

## [unreleased] — fix: test-canon TEST-006 asserts on phase2's drift report, not a first-file proxy (ISSUE-0031 / SPEC-0077)

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

## [unreleased] — fix: TEST-018 spare-fresh attributes the kill to the reaper (ISSUE-0030 / SPEC-0076)

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

## [unreleased] — fix: metrics-flush can retire a stranded non-work-item entry (ISSUE-0029 / SPEC-0075)

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

## [unreleased] — fix: branch-guard passes recognized non-work-item branches (ISSUE-0028 / SPEC-0074, closes #135)

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

## [unreleased] — fix: docs-audit false-open now reads METRICS + orders its signals (ISSUE-0027 / SPEC-0073, closes #133 #134)

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

## [unreleased] — fix: move TEST-017 off the reaper's epoch ambiguity boundary (ISSUE-0026 / SPEC-0072)

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

## [unreleased] — fix: Planning surfaces companion obligations (prompt-diet ledger + PROFILES) (ISSUE-0025 / SPEC-0071)

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

## [unreleased] — fix: enforce one dedicated git branch per work item (ISSUE-0024 / SPEC-0070)

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

## [unreleased] — fix: TEST-018 fresh per-case workspace removes residual reaper flake (ISSUE-0023 / SPEC-0069)

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
