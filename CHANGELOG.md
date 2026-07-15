# Changelog

All notable changes to AAI are documented in this file. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). AAI does not yet
follow semantic versioning — entries are grouped by date or release event.

For target projects: run `/aai-update` to pull the latest layer. After
updating, run `/aai-doctor` to surface any migration actions specific to
your project (for example, the STATE-to-local migration introduced in
RFC-0001).

## [unreleased] — feat: model tiering with teeth (CHANGE-0010 / SPEC-0018)

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

## [unreleased] — chore: prompt-layer diet phase 1 (CHANGE-0011 / SPEC-0017)

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

## [unreleased] — fix: slug refs across the tooling family (CHANGE-0012 / SPEC-0016)

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

## [unreleased] — feat: collision-free doc numbering across parallel clones (RFC-0007 / SPEC-0015 / PR #48)

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

## [unreleased] — state/hygiene: post-release follow-ups (CHANGE-0008 / SPEC-0014)

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

## [unreleased] — docs: canonical-surfaces refresh (TECHNOLOGY contract, PLAYBOOK, AGENTS, shims, catalogs)

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

## [unreleased] — docs: entry-point restructure (README/docs-README/USER_GUIDE)

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
