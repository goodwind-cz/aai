---
id: spec-hook-enforced-gates
type: spec
number: 29
status: draft
links:
  rfc: hook-enforced-gates
  research: RES-0001
  pr: []
  commits: []
---

# SPEC — Hook-Enforced Gates on Claude Code (opt-in overlay)

SPEC-FROZEN: true

## Links
- RFC: hook-enforced-gates (docs/rfc/RFC-0010-hook-enforced-gates.md, accepted
  2026-07-16 — "schvaluji oba, mergni a rozjed")
- Research: RES-0001 F1 (gate failures happen on the prompt-only layer) and the
  pro-workflow llm-gate sweep finding —
  docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md
- Constitution: docs/CONSTITUTION.md (ratified with STRICT article 7,
  operator-only merge — resolves the RFC's open question: the merge-deny hook
  SHIPS, as a guardrail for the ratified article)
- Directed-merge record: docs/ai/decisions.jsonl entry 2026-07-16T13:16:30Z
  (ref_id constitution — owner granted explicit per-request merge direction)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Implementation strategy
- Strategy: loop
- Rationale: one new adapter script + one JSON template + additive bootstrap
  flag + one prompt paragraph + one grep/behavioral suite. Every gating test is
  deterministic (JSON parse, exit-code assertions on fixtures, greps) and
  trivially RED-provable with one pre-change run of the new suite (none of the
  artifacts exist yet). RED-GREEN per test adds no signal over one focused pass
  plus a recorded RED run — the SPEC-0028 pattern.
- RED-proof obligation: before any edit, run
  `bash tests/skills/test-aai-hooks-overlay.sh` on the pre-change tree and save
  the failing output to `docs/ai/tdd/hooks-overlay-red.log` (expected:
  TEST-001..TEST-012 FAIL; TEST-013..TEST-015 pass pre-change by construction —
  survival invariants that must SURVIVE the change: repo stays uninstalled,
  prompt-diet byte floor holds after the SKILL_PR addition, repo-wide strict
  docs audit stays clean with the new spec present).

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: touches a protected prompt (.aai/SKILL_PR.prompt.md) and
  a vendored script (aai-bootstrap.sh); PR-bound feature work.
- User decision: worktree (already executing in
  /Users/ales/Projects/aai-feat-hooks, branch feat/hook-enforced-gates)
- Base ref: main
- Inline review scope (explicit paths):
  - .aai/templates/hooks/settings-hooks.json (new)
  - .aai/scripts/claude-hook-gate.sh (new)
  - .aai/scripts/aai-bootstrap.sh (additive --with-claude-hooks flag)
  - .aai/SKILL_PR.prompt.md (additive marker documentation in step 6)
  - docs/rfc/RFC-0010-hook-enforced-gates.md (links.spec + open-question
    resolution note)
  - tests/skills/test-aai-hooks-overlay.sh (new)
  - docs/specs/SPEC-0029-spec-hook-enforced-gates.md (this spec)
  - docs/INDEX.md (regenerated)

## Design decisions

### D1 — One thin adapter script: `.aai/scripts/claude-hook-gate.sh`
Claude Code PreToolUse matchers match TOOL NAMES only (`"Bash"`), never
command substrings; the invoked-command text arrives as JSON on the hook
command's stdin (`tool_input.command`). The stdin parse + dispatch therefore
cannot live in the settings JSON without unreviewable one-liners. One adapter
script holds ALL of it: `claude-hook-gate.sh <gate>` with gate one of
`commit | merge | state-dump | stop-nudge`. The adapter contains ZERO gate
logic — what blocks is decided by the existing script it invokes
(pre-commit-checks.sh, including its own doc_number_guard dial) or by rules
already ratified elsewhere (constitution article 7; article 6 / state.mjs
single-writer). Hook/script drift is impossible by construction: the adapter
never reimplements a predicate, it only routes.

### D2 — Fail-open at every layer (a broken hook must not brick the session)
- Adapter: runs under `set -u` WITHOUT `-e`; missing/failing node, unreadable
  stdin, malformed JSON, unknown gate argument, missing target script — all
  exit 0. Exit 2 (Claude's block code, stderr shown to the model) is emitted
  ONLY for a genuine gate verdict.
- Template commands: each `command` string guards the adapter's absence
  (`if [ -f "$G" ]; then bash "$G" <gate>; fi`) so a project that vendored the
  hooks but not the scripts layer degrades to a no-op exit 0.
- Path resolution uses `${CLAUDE_PROJECT_DIR:-.}` (hook cwd falls back to the
  project directory).
Fail-open silence is a deliberate, documented exception to article 4's
"never silently" clause — see Constitution deviations.

### D3 — Template `.aai/templates/hooks/settings-hooks.json`, NEVER auto-installed
The overlay lives as a TEMPLATE (aai-sync already vendors `.aai/templates/**`
recursively via `cp -a`, so target projects receive it automatically), but
nothing installs it into `.claude/settings.json` unless the operator opts in.
Absence of the overlay = behavior unchanged on every platform (Codex/Gemini/
older Claude) — the scripts remain the cross-platform floor. This repo itself
stays UNINSTALLED (opt-in means opt-in; tests exercise the template directly).
The four hooks:
1. PreToolUse/Bash → gate `commit`: command matches `git commit` → run
   `.aai/scripts/pre-commit-checks.sh`; non-zero → exit 2 with its output
   (secrets BLOCK; doc_number_guard per its docs-audit.yaml dial).
2. PreToolUse/Bash → gate `merge`: command matches `git merge` or `gh pr
   merge` → deny (exit 2) unless `AAI_OPERATOR_MERGE=1` — mechanizes ratified
   article 7 (strict wording). `git merge-base` and other `merge-*`
   subcommands do not match.
3. PreToolUse/Bash → gate `state-dump`: command contains
   `yaml.dump|safe_dump|dump_all` AND `STATE.yaml` → deny (exit 2) with a
   pointer to `.aai/scripts/state.mjs` (the SPEC-0019 manual-flush lesson:
   whole-file YAML serialization destroys the commented schema header;
   article 6 single-writer, mechanized).
4. Stop → gate `stop-nudge`: STATE has an `in_progress` work item and
   LOOP_TICKS.jsonl is absent or older than STATE (no tick logged after the
   last state change) → print a wrap-up reminder to stdout, ALWAYS exit 0
   (never blocks, by construction — the only gate with no exit-2 path).

### D4 — Bootstrap opt-in: `aai-bootstrap.sh --with-claude-hooks`
New flag, default OFF; a run without it never touches `.claude/settings.json`
(TEST-011 asserts this). With the flag:
- Template absent → WARN + skip (degrade and report; vendor via aai-sync).
- node absent → WARN with the exact manual-merge instruction (never a
  hand-rolled JSON write).
- Otherwise merge via node: parse existing `.claude/settings.json` (or start
  from `{}`), add ONLY the `hooks` key content, appending hook entries whose
  `command` string is not already present (idempotent re-run; foreign keys and
  foreign hooks preserved byte-for-byte in structure). An existing file that
  does not parse as JSON is REFUSED with a manual-merge instruction — never
  overwritten silently.
- `--dry-run` reports the planned merge without writing.

### D5 — Merge-deny marker documented in SKILL_PR step 6 (guardrail, not boundary)
.aai/SKILL_PR.prompt.md step 6 (MERGE BOUNDARY) gains an additive paragraph:
projects with the overlay installed deny `git merge`/`gh pr merge`
mechanically unless `AAI_OPERATOR_MERGE=1`. The agent NEVER sets the marker
for itself; it exists for the OPERATOR — or an agent acting on the operator's
explicit, recorded direction (cf. the decisions.jsonl directed-merge record
2026-07-16) — so a directed merge does not require disabling the overlay.
Article 7 is unchanged: the ceremony still ends at `gh pr create`. Honest
framing is mandatory: the marker is spoofable by the agent, so it is a
guardrail against habit, not a security boundary — setting it without the
operator's explicit direction is a constitution violation, not a technical
impossibility.

### D6 — Hooks-schema assumption ledger (flagged for Validation)
The Claude Code hooks schema was implemented from model knowledge of Claude
Code 2.x, cross-checked against the only local evidence available offline —
this repo's plugin hooks (hooks/hooks.json: the
`{"hooks": {"<Event>": [{"matcher": ..., "hooks": [{"type": "command",
"command": ...}]}]}}` shape). Assumptions Validation must verify against the
live hooks docs (https://docs.anthropic.com/en/docs/claude-code/hooks):
- A1: event names `PreToolUse` and `Stop`; `Stop` entries take no matcher.
- A2: PreToolUse `matcher` matches the TOOL NAME (regex allowed), e.g.
  `"Bash"`; it cannot match command content.
- A3: hook commands receive the event payload as JSON on stdin, with the Bash
  command text at `.tool_input.command`.
- A4: exit code 2 blocks the tool call and feeds stderr to the model; other
  non-zero exits are non-blocking; exit 0 allows.
- A5: `$CLAUDE_PROJECT_DIR` is exported to hook commands (fallback `.` kept
  regardless).
- A6: user/project hook config merge target is the `hooks` key of
  `.claude/settings.json`.
- A7 (limitation, not assumption): the overlay is POSIX-shell only; a
  hooks.windows-style PowerShell variant is out of scope v1 (mirrors the
  existing hooks/hooks.windows.json split; no ps1 twin gate exists for
  scripts).

## Acceptance Criteria Mapping
- Maps to: RFC-0010 recommended option, item list 1-4 + "zero new logic"
  - Spec-AC-01: `.aai/templates/hooks/settings-hooks.json` exists, is valid
    JSON, defines exactly the 4 hooks (3 PreToolUse command hooks under a
    `Bash` matcher: commit, merge, state-dump; 1 Stop command hook:
    stop-nudge), every hook `type: "command"`, every command string carries
    the adapter-absence guard, and every `.aai/scripts/*` path referenced by
    the template and the adapter exists in the repo (conformance — hooks only
    reference existing scripts).
  - Verification: TEST-001..TEST-004.
- Maps to: RFC-0010 constraints (fail-open, mirror existing gates, marker)
  - Spec-AC-02: adapter behavior proven by fixture exit codes — commit gate
    routes to pre-commit-checks.sh and blocks (2) only on its failure,
    fail-open (0) when the script is absent or the command is not a commit;
    merge gate denies (2) without the marker for both `git merge` and
    `gh pr merge`, allows (0) with `AAI_OPERATOR_MERGE=1`, ignores
    `git merge-base`; state-dump gate denies (2) with a state.mjs pointer only
    when a dump call targets STATE.yaml; malformed stdin and broken node are
    fail-open (0) on every PreToolUse gate; stop-nudge NEVER exits non-zero.
  - Verification: TEST-005..TEST-009.
- Maps to: RFC-0010 "opt-in via aai-bootstrap, never forced"
  - Spec-AC-03: `--with-claude-hooks` wired and documented in
    aai-bootstrap.sh; a default run writes no `.claude/settings.json`; a
    flagged run merges the hooks (idempotent on re-run, foreign settings keys
    preserved, unparseable existing file refused with manual instruction, not
    overwritten).
  - Verification: TEST-010, TEST-011.
- Maps to: RFC-0010 risks section (marker honesty) + ratified article 7
  - Spec-AC-04: SKILL_PR step 6 documents AAI_OPERATOR_MERGE with the
    guardrail-not-security-boundary framing while the "NEVER merge" boundary
    survives; this repo's own `.claude/settings.json` stays hook-free;
    prompt-diet byte floor holds; repo-wide strict docs audit stays clean;
    docs/INDEX.md regeneration is idempotent.
  - Verification: TEST-012..TEST-015 + index regen at validation.

## Constitution deviations

- Article 4 (degrade and report) — two accountable tensions, both justified:
  1. A hook BLOCKS a tool call outright instead of degrading. Justified: the
     hooks add no new policy — they mirror gates whose dials ALREADY allow
     enforce (pre-commit-checks.sh exits 1 on secrets; doc_number_guard ships
     `enforce` in this repo's docs-audit.yaml; article 7 is itself a hard
     boundary; article 6 names a single writer). The block is the existing
     gate's verdict delivered mechanically, with full context on stderr
     (fail fast with context). And the entire overlay is OPT-IN: absence =
     unchanged behavior.
  2. Adapter internal errors fail OPEN silently (exit 0 without a report).
     Justified: RFC-0010 hard constraint — a broken hook must not brick the
     session; a blocked session is strictly worse than a skipped mirror,
     because every mirrored gate still runs at its original call site
     (pre-commit hook, prompts, CI), so nothing is lost when the mirror
     fails open. Documented here and in the adapter header rather than
     silently assumed.
- All other articles: checked, no deviation. Article 3 (portability): the
  overlay is Claude-only but the durable artifacts are plain JSON/bash files
  and the scripts remain the tri-platform floor; absence changes nothing.
  Article 5: strictly additive (new files + one flag + one paragraph).
  Article 6/7: this change ENFORCES them.

## Acceptance Criteria Status

| Spec-AC    | Description                                              | Status | Evidence | Review-By | Notes |
|------------|----------------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | Template: 4 hooks, valid JSON, guarded commands, script conformance | done | TEST-001..004 green; docs/ai/tdd/hooks-overlay-red.log (RED) → docs/ai/tdd/hooks-overlay-green.log | — | .aai/templates/hooks/settings-hooks.json + claude-hook-gate.sh |
| Spec-AC-02 | Adapter gate behavior + fail-open, all by fixture exit codes | done | TEST-005..009 green; same logs | — | commit/merge/state-dump/stop-nudge |
| Spec-AC-03 | Bootstrap opt-in merge (idempotent, never silent overwrite) | done | TEST-010..011 green; same logs | — | --with-claude-hooks |
| Spec-AC-04 | SKILL_PR marker doc; repo uninstalled; diet floor; strict audit; index idempotent | done | TEST-012..015 green; audit exit 0; index regen no-op; sweep | — | see Verification |

## Implementation plan
- Components affected: template layer (.aai/templates/hooks/ new), script
  layer (claude-hook-gate.sh new; aai-bootstrap.sh additive flag), prompt
  layer (.aai/SKILL_PR.prompt.md step 6 additive paragraph), RFC frontmatter
  (links.spec), test layer (one new suite), docs/INDEX.md regeneration.
- Order: (1) RED run of the new suite on the pre-change tree → save log;
  (2) adapter script; (3) settings-hooks.json template; (4) bootstrap flag +
  merge; (5) SKILL_PR paragraph; (6) RFC links.spec + open-question note;
  (7) suite green → save log; (8) full sweep; (9) strict audit; (10) index
  regen twice (idempotent); (11) AC table reconciliation; (12) STATE updates
  via state.mjs.
- Edge cases: `git merge-base`/`merge --abort` (abort still matches `git
  merge` — acceptable: the operator escape or plain non-hook shells cover the
  rare agent-side abort; blocking an abort is safe-side); command text with
  newlines (grep -E over the whole string); settings.json with a `hooks` key
  from another tool (merge appends, never replaces); bootstrap usage() sed
  range must cover the new flag line.
- Seam analysis:
  - Seam S1 — pre-commit-checks.sh is consumed by the git pre-commit hook,
    skills, AND now the commit gate. Crossing test: TEST-005 invokes the real
    adapter against a fixture checks script and asserts the exit-2 routing
    (the gate never reimplements a check, so drift cannot diverge verdicts).
  - Seam S2 — .claude/settings.json is shared with user/other-tool settings.
    Crossing test: TEST-011 merges into a settings file carrying a foreign
    key and asserts it survives; unparseable file refused.
  - Seam S3 — the `.aai/*.prompt.md` byte corpus is shared with prompt-diet
    TEST-010. Crossing test: TEST-014 runs the real prompt-diet suite.
  - Seam S4 — docs/INDEX.md + strict audit consume the new spec/RFC edits.
    Crossing test: TEST-015 (repo-wide strict audit) + index regen at
    validation.
  - Residual risk (recorded): assumptions A1-A6 (D6) cannot be integration-
    tested offline — no hook actually fires in this repo (uninstalled by
    design). Mitigation: assumption ledger flagged for Validation against the
    live docs; local plugin-hooks evidence matches the shape.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                    | Description                                                                    | Status |
|----------|------------|-------------|------------------------------------------|--------------------------------------------------------------------------------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-hooks-overlay.sh   | Template exists and parses as JSON (node JSON.parse)                            | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-hooks-overlay.sh   | Structure: 3 PreToolUse command hooks under Bash matcher (commit/merge/state-dump) + 1 matcherless Stop hook (stop-nudge); all type command | green |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/test-aai-hooks-overlay.sh   | Conformance: every .aai/scripts path referenced by template+adapter exists; adapter routes to pre-commit-checks.sh and points at state.mjs | green |
| TEST-004 | Spec-AC-01 | integration | tests/skills/test-aai-hooks-overlay.sh   | Fail-open shape: every template command guards adapter absence; each runs exit-0 in an empty fixture dir | green |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-aai-hooks-overlay.sh   | Commit gate: non-commit→0; commit w/o checks script→0; commit w/ failing checks→2 + reason on stderr (S1) | green |
| TEST-006 | Spec-AC-02 | integration | tests/skills/test-aai-hooks-overlay.sh   | Merge gate: git merge→2, gh pr merge→2 (article-7 message names AAI_OPERATOR_MERGE); marker=1→0; git merge-base→0 | green |
| TEST-007 | Spec-AC-02 | integration | tests/skills/test-aai-hooks-overlay.sh   | State-dump gate: yaml.dump targeting STATE.yaml→2 + state.mjs pointer; dump w/o STATE.yaml→0 | green |
| TEST-008 | Spec-AC-02 | integration | tests/skills/test-aai-hooks-overlay.sh   | Fail-open: malformed stdin JSON→0 on all PreToolUse gates; broken node stub→0                | green |
| TEST-009 | Spec-AC-02 | integration | tests/skills/test-aai-hooks-overlay.sh   | Stop-nudge: never non-zero; nudges (stdout) only when in_progress + stale/absent ticks; silent otherwise | green |
| TEST-010 | Spec-AC-03 | unit        | tests/skills/test-aai-hooks-overlay.sh   | Bootstrap wiring grep: --with-claude-hooks flag parse + usage doc + template path literal    | green |
| TEST-011 | Spec-AC-03 | integration | tests/skills/test-aai-hooks-overlay.sh   | Bootstrap behavior in fixture: default run writes no settings.json; flagged run merges 4 hooks; re-run idempotent; foreign key preserved; invalid JSON refused untouched (S2) | green |
| TEST-012 | Spec-AC-04 | unit        | tests/skills/test-aai-hooks-overlay.sh   | SKILL_PR step 6: AAI_OPERATOR_MERGE documented, guardrail-not-security-boundary wording, NEVER-merge boundary survives | green |
| TEST-013 | Spec-AC-04 | unit        | tests/skills/test-aai-hooks-overlay.sh   | This repo stays uninstalled: .claude/settings.json absent or free of claude-hook-gate        | green |
| TEST-014 | Spec-AC-04 | integration | tests/skills/test-aai-hooks-overlay.sh   | Prompt-diet byte floor holds after the SKILL_PR addition: real suite exits 0 (S3)            | green |
| TEST-015 | Spec-AC-04 | integration | tests/skills/test-aai-hooks-overlay.sh   | Repo-wide strict docs audit exits 0 with the new docs present (S4)                           | green |

Notes:
- RED-proof: TEST-001..012 observed FAILING on the pre-change tree
  (docs/ai/tdd/hooks-overlay-red.log). TEST-013..015 are survival invariants
  (pass pre-change by construction, non-vacuous because the change adds prompt
  bytes, new governed docs, and could have installed hooks into this repo).
- Known environmental exception per LEARNED 2026-07-15:
  tests/skills/test-aai-worktree.sh fails deterministically on this machine
  pre-existing on clean main — verify via main comparison, do not chase.

## Verification
- `bash tests/skills/test-aai-hooks-overlay.sh` → exit 0, all 15 stanzas PASS.
- Full tests/skills sweep → green (worktree-suite exception above).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0.
- `node .aai/scripts/generate-docs-index.mjs` run twice → second run no-op.
- `node .aai/scripts/check-state.mjs` → healthy.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal with evidence.

## Evidence contract
For each implementation, validation, and code review artifact, record:
- ref_id: hook-enforced-gates
- Spec-AC and TEST-xxx links where applicable
- command or review scope, exit code or review verdict
- evidence path (docs/ai/tdd/hooks-overlay-red.log for RED;
  docs/ai/tdd/hooks-overlay-green.log for GREEN)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.
