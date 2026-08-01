---
id: lightweight-e2e-lane
type: change
status: draft
user_visible: true
links:
  pr: []
  commits: []
---

# Change — Lightweight end-to-end lane: cut the flat ceremony tax on small, safe rides

## Summary
- The factory's end-to-end process cost is nearly FLAT regardless of change
  size. A 7-line prompt trim (CHANGE-0095 contract-headroom, PR #198) paid the
  same governance envelope as a subsystem change: intake doc -> lean SPEC ->
  ledger/TEST-012 governance -> INDEX regen -> Planning freeze -> Validation ->
  Code Review -> close ceremony (its own commit) -> CHANGELOG entry -> PR ->
  ~15-16 min full-framework CI (paid TWICE: feature commit + close commit) ->
  5d bot sweep (bounded 10-min poll window) -> merge.
- Real owner pain (verbatim, recorded on CHANGE-0100): "Neni to tak velka
  zmena a nechci pouzivat TDD, aby to nespalilo tolik tokenu." A comparable
  small change burns roughly 3-5% of a weekly token limit
  (docs/issues/CHANGE-0100-implementation-mode-choice.md:19-20).
- CHANGE-0100 fixed only the IMPLEMENTATION phase (strategy lanes
  direct/untested). The GOVERNANCE ENVELOPE around implementation — validation,
  review, the two CI rounds, the separate close-ceremony commit, and the 5d bot
  sweep — is unchanged for every ride. This change proposes a DETERMINISTIC
  fast-path that lightens the governance envelope for provably-small,
  provably-safe rides, with a named compensating control for every lightened
  step, and the heavy lane staying the default for everything else.

## Motivation / Business Value
- The token tax and the wall-clock tax are the two costs the owner feels. The
  wall-clock tax on a minimal ride is dominated by CEREMONY, not by the work:
  two ~15-16 min CI rounds plus a ~10 min sweep window that, on small rides,
  finds nothing (evidence below).
- Value: a small, safe ride should cost roughly one implementation pass, one
  narrowed CI round, and one internal review — not the full L2 envelope twice
  over. The expensive lane must never be silently forced on a trivial scope,
  and the cheap lane must never be a silent downgrade of rigor — it must be a
  DETERMINISTIC classification, never agent judgment.

## Analysis

### 1. Cost breakdown of a minimal ride today (walk: CHANGE-0095 / PR #198)

CHANGE-0095 was a prose-only trim of `.aai/SUBAGENT_CONTRACT.md` (60 -> 53
lines) plus one additive test — commit f1ff21b, diff 5 files
+116/-22 (docs/issues/CHANGE-0095-contract-headroom.md; `git show --stat`).
Ceremony L1. Its PR carried exactly two commits: the feature commit (7eacbbe)
and a SEPARATE `chore(close): CHANGE-0095 close ceremony (pr #198)` commit
(b33dc24) — `git log --grep "#198"`.

| Phase | Fixed or variable | Est. cost | Notes |
|-------|-------------------|-----------|-------|
| Intake doc (CHANGE-DRAFT) | FIXED | ~1 agent pass | full template regardless of scope |
| Lean SPEC (AC table) / tech-note | FIXED at L1 | Planning role ~330-660s wall | L0 folds spec into the CHANGE doc; L1 still needs a lean SPEC |
| Ledger / TEST-012 / PROFILES governance | CONDITIONAL | 0 here | not triggered — contract file is not a `.aai/*.prompt.md` (Planning step 3a closed list) |
| Planning freeze + brief | FIXED | ~100K harness tokens | frontmatter, AC map, Test Plan, brief emit |
| Implementation / TDD | VARIABLE | scope-dependent | already lightened by CHANGE-0100 strategy lanes |
| Validation role | FIXED (depth scoped) | ~74-130K tokens, ~7-22 min | SPEC-0041 already scopes L0/L1 to declared suites, not full sweep |
| Code Review role | FIXED | ~68-80K tokens, ~4-11 min | L1 = one dual-verdict pass (required) |
| INDEX regen | mechanical | cheap, auto-staged | pre-commit companion |
| Close ceremony | FIXED | SEPARATE commit -> 2nd CI round | `close-work-item.mjs` needs `--pr <N>`, so it runs AFTER PR open as its own commit |
| CHANGELOG per-entry heading | FIXED | folded into feature commit | already batched by SKILL_PR step 3b |
| PR open | FIXED | one `gh pr create` | |
| Full-framework CI | FIXED | ~15-16 min PER PUSH | async-HITL 16:23->16:39 = ~16.7 min; cache-friendly ~14 min; intake ~16 min (`gh run list`) |
| 5d bot sweep | FIXED | bounded 10-min poll window | SKILL_PR step 5d; often a fix round + another ~16 min CI |
| Merge | operator | — | Constitution art. 7, never the agent |

Token magnitude for a comparable small ride (harness `usage_total_tokens`,
cumulative-per-role — overcounts if summed, magnitude only): the L1 ride
prompt-diet-itemized-growth-ledger recorded Planning 100298 / TDD 132981 /
Validation 73983 / Review 67930 across its 4 non-mechanical role dispatches
(docs/ai/METRICS.jsonl). CHANGE-0095 itself was never flushed to METRICS
(`grep -c contract-headroom` = 0), so its neighbours stand in.

WALL-CLOCK ceremony floor for a clean small ride: feature-commit CI (~16 min)
+ close-commit CI (~16 min) + sweep window (~10 min) = ~42 min that is
INDEPENDENT of change size. A ride that trips a remediation round pays a third
~16 min CI (CHANGE-0100 / PR #203 shows FOUR full CI runs at 08:51/09:20/
09:52/10:21, `gh run list`).

FIXED-COST STEPS (flat regardless of scope): intake doc, Planning freeze,
Validation, Code Review, close ceremony (as a second CI round), CHANGELOG, PR,
full-framework CI (x2 rounds minimum), 5d sweep window.

### 2. What the existing lanes already lighten (and what they do NOT touch)

| Knob (source) | Phases it lightens | Phases it does NOT touch |
|---------------|--------------------|--------------------------|
| RFC-0009 ceremony levels (WORKFLOW.md ceremony table) | spec artifact weight (L0 tech-note, L1 lean SPEC); review optionality (L0 review optional); worktree gate | validation existence, CI, close ceremony, CHANGELOG, bot sweep, PR |
| SPEC-0041 ceremony-aware dispatch (`lane.validation_depth`) | Validation DEPTH — L0/L1 = declared-scope, no full-repo sweep (SPEC-0041 D2/D3) | CI wall-clock, close ceremony, bot sweep, review budget (still one dual-verdict), CHANGELOG |
| SPEC-0097 CI test-impact selection (`select-suites.mjs`) | CI SUITE SELECTION on PR pushes (affected suites only) | but FAIL-OPEN triad (protected-l3 / `.aai/scripts/lib/**` / unmapped) forces FULL_RUN — framework-self rides usually hit it; close-commit docs churn can be "unmapped" -> FULL_RUN |
| CHANGE-0100 strategy lanes (`direct` / `untested`) | IMPLEMENTATION rigor + RED ceremony; Validation's RED-proof demand | close ceremony, bot sweep, CI rounds, review existence, CHANGELOG, intake doc, PR |

Net: the four existing knobs lighten spec weight, validation DEPTH, CI SUITE
count, and implementation rigor. NONE of them touches the two biggest flat
wall-clock costs — the SECOND CI round (close-ceremony commit) and the 5d bot
sweep window — nor the intake doc itself.

### 3. Where the fat is (per fixed-cost step)

| Fixed step | Classification | Rationale |
|------------|----------------|-----------|
| 5d bot sweep on L0/L1 + docs/prose diffs | (a) SAFE TO SKIP (make optional-on-demand) | 0 yield on the L1 ride (see 4); internal dual-verdict review still runs |
| Second CI round (close-ceremony commit) | (b) SAFE TO BATCH / narrow | close commit touches only docs frontmatter + EVENTS.jsonl + INDEX; must route to CORE suites, never FULL_RUN, or fold into one CI round |
| Full-framework CI on PR push (small mapped diff) | (b) already narrowable via SPEC-0097 | ensure a small mapped diff is not escalated to FULL_RUN by an over-broad suite-map row |
| CHANGELOG entry | (b) already batched | folded into feature commit (SKILL_PR 3b) — keep |
| Validation full sweep | (b) already scoped at L0/L1 | SPEC-0041 declared-scope — keep, do not weaken |
| Code Review (dual-verdict) | (c) MUST STAY at L1 | it is the compensating control that lets the bot sweep become optional |
| doc-number guard (allocator) | (c) MUST STAY | RFC-0007 collision safety |
| docs-audit close gate + justification line | (c) MUST STAY | level-inflation backstop |
| check-state / single-writer STATE | (c) MUST STAY | Constitution art. 6 |
| Evidence-before-claims (Validation existence) | (c) MUST STAY at every level | Constitution art. 1 — never pruned |
| Operator-only merge | (c) MUST STAY | Constitution art. 7 |

### 4. Risk analysis — where the heavy process EARNED its cost this week

Bot-sweep yield, small/L1 ride vs feature rides (from `git log` fix-commit
evidence):

| Ride | Class | Sweep yield |
|------|-------|-------------|
| PR #198 contract-headroom | L1 prose trim | 0 findings — only feature + close commits exist; NO `fix(...) bot sweep` commit |
| PR #194 auto-update config | feature | 7 findings incl. 2 P1 (commit 3875895, branch feat/auto-update-config) |
| PR #205 async HITL | feature | 8 findings (commit 1f9148f) |
| PR #196 atomic-lock | feature / L3 | 4 findings + doc-drift (commit 637627c) |
| PR #203 implementation-mode | feature / L3 | findings — INV-11 enum, fresh-checkout fallback, choice-before-complete (f70ec2a) |
| PR #204 cache-friendly dispatch | feature / L2 | findings — one real reorder + back-compat wording (1aa7528) |

Reading: the 5d sweep has EARNED its cost on feature/L2-L3 rides — it caught 2
P1 defects on #194 alone. On the one small L1 ride in scope (#198) it yielded
NOTHING. That asymmetry is the entire case for making the sweep
optional-on-demand for L0/L1 + docs/prose diffs while keeping it MANDATORY for
everything else.

What each lightening gives up, and the compensating control:
- Skipping the sweep on L1/docs gives up the redundant EXTERNAL review layer.
  Compensating control: the INTERNAL dual-verdict code review (WORKFLOW rule
  13, required at L1) still runs on the same diff — the sweep was the second,
  redundant pass, not the only one.
- Batching/narrowing the close-ceremony CI gives up a full re-run of suites
  that a docs-only commit cannot break. Compensating control: the CORE suites
  (docs-audit, check-state, spec-lint) still run on that commit, and the
  post-merge push-to-main + nightly FULL run (SPEC-0097) remain the backstop.
- Anti-gaming — who decides a ride is "light"? NEVER the agent. The lane is a
  deterministic conjunction of machine-read predicates (ceremony_level from
  frozen frontmatter, strategy from STATE, protected-l3 from docs-audit.yaml,
  diff surface classes + FULL_RUN triad from `select-suites.mjs`, changed-file
  count from `git diff --numstat`). A bad or inflated declaration can only ever
  select the HEAVY lane (fail-closed, inheriting the SPEC-0041 / SPEC-0097
  philosophy). Review may re-classify a level upward as a recorded finding
  (RFC-0009), and that reclassification re-arms the sweep.

## Design

### Recommended option — Option A: deterministic L1 fast-path with compensating controls

A single deterministic gate (evaluated in SKILL_PR, reusing `select-suites.mjs`
outputs and STATE/spec reads — NO new agent judgment) fires the fast path IFF
ALL of the following hold, else the heavy lane runs unchanged:

1. `ceremony_level` in {0, 1} (from the frozen spec / tech-note frontmatter).
2. `implementation_strategy.selected` in {direct, untested, loop} (STATE).
3. The diff trips NONE of the SPEC-0097 FULL_RUN triad — no `protected_paths_l3`
   path, no `.aai/scripts/lib/**`, no unmapped path (`select-suites.mjs`
   returns a narrowed list, not `FULL_RUN`).
4. Diff surface classes subset of {docs, prose, a single test file, a single
   non-core script}, AND changed-file count < N (default 5).

When it fires:
- CI runs the SELECTED suites only (already SPEC-0097 behavior for a mapped
  diff) — for both the feature commit AND the close-ceremony commit (AC-004
  makes the docs-only close commit route to CORE suites, never FULL_RUN).
- The 5d bot sweep is OPTIONAL-on-demand: skipped by default, run only if the
  operator asks. Compensating control: the mandatory internal dual-verdict
  review already ran on the diff.
- The close ceremony is BATCHED onto the narrowed CI lane (one narrowed round
  for feature + one CORE-only round for close), removing the second
  full-framework round.
- Validation stays at SPEC-0041 declared-scope (unchanged); internal review
  stays required (unchanged); doc-number guard, docs-audit close gate,
  check-state, evidence gate, operator-merge all UNCHANGED.

Why recommended: it targets the two flat costs the existing knobs miss — the
second full CI round and the sweep window — with the strongest evidence behind
each (0 sweep yield on #198; docs-only close commit cannot break framework
suites). Every predicate is deterministic; the heavy lane is the fail-closed
default. It composes with, rather than duplicates, SPEC-0041 and SPEC-0097.

### Rejected alternative — Option B: governance batching only

Keep ALL steps and gates (including the sweep on every ride); only merge the
close ceremony onto a narrowed CI lane so there is one full round instead of
two, and ensure docs-only commits route to CORE suites.

Why rejected: it leaves the largest evidenced waste in place — the ~10 min
sweep window that yielded 0 on the L1 ride. It saves roughly one ~16 min CI
round but not the sweep wait, and it does nothing about the token-heavy
redundant external review layer. Option A keeps every compensating control
Option B keeps, and additionally retires the provably-empty sweep — for the
same anti-gaming guarantees (deterministic predicates, fail-closed heavy
default). Option B's only advantage is a smaller blast radius; given the
sweep-yield evidence, that caution is not worth the retained tax.

## Acceptance Criteria
- AC-001: A deterministic `lightweight-lane` predicate exists that fires IFF all
  four conditions hold (ceremony_level in {0,1}; strategy in
  {direct,untested,loop}; `select-suites.mjs` returns a narrowed list — no
  FULL_RUN triad hit; diff classes subset {docs,prose,single test,single
  non-core script} AND changed-file count < N). It reads ONLY machine sources
  (frozen frontmatter, STATE, docs-audit.yaml, `select-suites.mjs`,
  `git diff --numstat`) and contains NO agent-judgment branch. Verified by a
  table-driven test over fixtures: each condition individually false -> heavy
  lane; all true -> light lane.
- AC-002 (fail-closed / anti-gaming): every degenerate input (absent/garbage
  ceremony_level, absent strategy, missing spec file, any FULL_RUN triad path,
  file count >= N) resolves to the HEAVY lane. No input combination reachable
  by a mis-declaration selects the light lane. Verified by negative-control
  fixtures.
- AC-003 (bot sweep — lightened step + compensating control): when the light
  lane fires, SKILL_PR step 5d is OPTIONAL-on-demand (default skipped); the
  MANDATORY internal dual-verdict code review (rule 13) still runs on the diff
  and its PASS is still a merge-readiness precondition. When the light lane does
  NOT fire, step 5d is unchanged (mandatory). Verified by grep-contract on
  SKILL_PR + a lane-conditional test.
- AC-004 (second CI round — batched step + compensating control): a close-
  ceremony commit whose diff is only docs frontmatter + EVENTS.jsonl + INDEX
  routes to CORE suites (docs-audit, check-state, spec-lint) via
  `select-suites.mjs`, NEVER FULL_RUN; the post-merge push-to-main + nightly
  FULL run (SPEC-0097) remain the backstop. Verified by a `select-suites.mjs`
  fixture over a docs-only diff asserting mode != full.
- AC-005 (heavy lane is default for L2+): any ride with ceremony_level >= 2, or
  any FULL_RUN triad hit, or file count >= N, runs the UNCHANGED full envelope
  (full CI, mandatory sweep, full validation). Byte-for-byte parity of the
  heavy path is asserted for at least one existing L2 fixture.
- AC-006 (no new escape hatch; governance intact): docs-audit close gate,
  justification-line check, doc-number allocator, check-state, single-writer
  STATE, and operator-only merge are UNTOUCHED at every lane;
  `git diff` over the close-gate / allocator / state-engine surfaces is empty
  for this scope. `node .aai/scripts/docs-audit.mjs --check --strict
  --no-event` exits 0 before and after.
- AC-007 (lane is auditable): the selected lane and the predicate values that
  chose it are emitted (dispatch payload / PR body line) so a reviewer can see
  WHY a ride went light — never a hidden decision.

## Verification
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> exit 0.
- Table-driven lane-predicate suite (AC-001/002/005): each of the four
  conditions independently false -> heavy; all true -> light; every degenerate
  input -> heavy.
- `select-suites.mjs` fixture over a docs-only close-commit diff -> mode !=
  full, CORE suites present (AC-004).
- Grep-contract over SKILL_PR asserting the lane-conditional 5d branch and the
  retained mandatory internal review (AC-003).
- `git diff --exit-code` over close-work-item.mjs / allocate-doc-number.mjs /
  state engine surfaces -> empty (AC-006).
- Live: run one real L1 ride through the fast path and record its CI-round
  count + wall-clock against the ~42-min heavy floor (deferred live evidence,
  captured on the first real lightweight ride, per SPEC-0041's precedent).

## Constraints / Risks
- PROTECTED PATHS: `close-work-item.mjs`, `allocate-doc-number.mjs`, the state
  engine, and `.aai/workflow/WORKFLOW.md` are L3-protected. Any edit that
  touches them forces this change itself to L3. The recommended design edits
  SKILL_PR (prompt) + a new predicate helper + tests, and REUSES existing
  `select-suites.mjs` outputs — aiming to avoid the protected surfaces; if the
  close-commit routing requires a WORKFLOW.md canon row edit, that arm escalates
  to L3 and needs the operator checkpoint.
- The HEAVY lane stays the DEFAULT for L2+ and for any FULL_RUN-triad or
  over-count diff. The change can only ever REMOVE ceremony from a
  deterministically-classified small/safe ride; it can never add risk to a
  large one (fail-closed).
- Threshold N (changed-file count) is a policy knob; start conservative
  (N = 5) and widen only with evidence.
- Sweep-skip risk: a real defect on a docs/prose diff that only the external
  bots would catch. Bounded by (a) the retained internal dual-verdict review,
  (b) operator-on-demand sweep, (c) the post-merge FULL run. The #198 evidence
  (0 external-only findings on an L1 ride) sizes this risk as low.
- No secret referenced; SECRETS PREFLIGHT skipped.

## Notes
- Parking pattern: intake DRAFT authored on an isolated branch, pushed for
  later scheduling — no PR opened here.
- Evidence sources: docs/issues/CHANGE-0095-contract-headroom.md (walked ride),
  docs/issues/CHANGE-0100-implementation-mode-choice.md (owner quote + prior
  fix), docs/rfc/RFC-0009-scale-adaptive-ceremony.md,
  docs/specs/SPEC-0041-spec-loop-ceremony-aware-dispatch.md,
  docs/specs/SPEC-0097-spec-ci-test-impact-selection.md,
  .aai/SKILL_PR.prompt.md (close ceremony 5c + bot sweep 5d),
  .aai/workflow/WORKFLOW.md (ceremony table), docs/ai/METRICS.jsonl,
  `gh run list` / `gh pr view` CI timings, and `git log` sweep-fix commits.
