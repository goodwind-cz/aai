# Shared role METRICS / append-run block (prompt-dedup-canonical-includes)

Applies to every role prompt that records `agent_runs` metrics at the end of
its run: `.aai/PLANNING.prompt.md`, `.aai/IMPLEMENTATION.prompt.md`,
`.aai/VALIDATION.prompt.md`, `.aai/REMEDIATION.prompt.md`, and
`.aai/SKILL_TDD.prompt.md`. Each references this file with a pointer line
naming its own `--role` value; apply the block below exactly as written,
substituting `<ThisRole>` with that role's declared value (quote it when it
contains a space, e.g. `"TDD Implementation"`).

## METRICS (record in docs/ai/STATE.yaml)
Subagent-mode carve-out (D5): dispatched as a subagent -> do NOT self-append; return the result block — the orchestrator appends with harness usage per SUBAGENT_PROTOCOL.md; direct execution -> self-append below, usage omitted.
Capture `started_utc` from the system clock (`date -u +%Y-%m-%dT%H:%M:%SZ`)
immediately before this role's first step begins.
PRIMARY PATH — after completing, append your agent run via the transactional CLI:
  node .aai/scripts/state.mjs append-run --ref <REF-ID> --role <ThisRole> \
    --model <your model identifier> --started <started_utc> \
    [--note "<summary>"] [--tokens-in N --tokens-out N]
The CLI self-stamps `ended_utc` and computes `duration_seconds` from the system
clock, keeps `cost_usd: null`, and auto-initializes a missing
metrics.work_items entry — never a second top-level `metrics:` key.
FALLBACK — if .aai/scripts/state.mjs is absent: read .aai/STATE_FALLBACK.md and
follow it (agent_runs hand-append + write-safety rules).
Do NOT estimate any timing or token values. Only record measured/platform values.

## FRICTION HOOK (canon-surface failure capture, default-on)
Applies to every default-on friction-capture point: `.aai/IMPLEMENTATION.prompt.md`
(canon-surface check failure), `.aai/VALIDATION.prompt.md` (canon-file gate/lint/CI
failure during discovery, AND a FAIL verdict at step 8), and
`.aai/REMEDIATION.prompt.md` (a failure categorized as AAI-owned). When the named
trigger fires, best-effort record it per `.aai/system/FRICTION_PROTOCOL.md`
"Skill wiring (shadow capture)" -> "Deterministic hook points" (schema v2);
swallow any capture failure — it must never affect, block, or change the
calling step's own outcome. Each caller prompt names only its own trigger and
the specific outcome the capture must never touch.

## PYTHON MONTY SCRATCHPAD (optional, pre-implementation only)
Applies to `.aai/IMPLEMENTATION.prompt.md` step 6c and `.aai/SKILL_TDD.prompt.md`
Phase 2 step 0b. If `.claude/skills/aai-python-monty/SKILL.md` exists and the
current unit of work is Python, you may read it and use pydantic-monty to
prototype small isolated logic before editing production code.
- Use it only for pure functions, data transformations, parser checks,
  type-hint checks, or agent-generated code that calls explicit narrow host
  functions.
- Do not use it for project imports, third-party libraries, filesystem/network
  access, framework behavior, database access, secrets, or final validation
  evidence.
A Monty pass is never completion by itself; each caller prompt names what
actually finishes the work.

## PRE-HANDOFF AC-TABLE RECONCILIATION (SPEC-0012 G4 — self-check, not a verdict)
Applies to `.aai/IMPLEMENTATION.prompt.md` step 9b and `.aai/SKILL_TDD.prompt.md`
Phase 4 step 1b. Before handing off to Validation, reconcile the spec's
`## Acceptance Criteria Status` table for every Spec-AC covered by the
completed work:
- Set each covered row to a terminal status (done | deferred | blocked |
  rejected) with Evidence naming the PROOF artifact: the cell MUST carry a
  `docs/ai/tdd/*.log` path; a RUN_ID or suite output path may accompany it,
  never replace it. NOT a commit SHA and NOT a PR reference — a delivery
  citation under a still-open `status` is the exact shape
  `docs-audit --check` reads as probable-false-open. The delivery citation is
  written by the close flip (`.aai/SKILL_PR.prompt.md` step 4c), in the same
  transaction as the frontmatter `status`.
- A row you truthfully cannot finish gets `deferred`/`blocked` with a FUTURE
  Review-By date plus Notes — never a fabricated `done`.
- Emit `ac_status` events (best-effort):
    node .aai/scripts/append-event.mjs --event ac_status --ref <SPEC-ID>/<Spec-AC-ID> --from planned --to done
- Then run BOTH self-checks and fix until each exits 0 before reporting
  complete:
    node .aai/scripts/docs-audit.mjs --gate <SPEC-ID>
    node .aai/scripts/docs-audit.mjs --ac-flip-check <SPEC-ID>
Validation's AC-STATUS GATE remains the enforcement backstop; this step stops
a gate-opted spec from reaching Validation with `planned` rows. Each caller
below names only its own "covered by" scope and its evidence shape.

## WORKTREE GATE (recommendation decision check)
Applies to `.aai/ORCHESTRATION_PARALLEL.prompt.md`, `.aai/IMPLEMENTATION.prompt.md`
step 5, and `.aai/SKILL_TDD.prompt.md` Phase 0 step 6.
Condition: `worktree.recommendation` is `recommended` or `required` AND
`worktree.user_decision` is `undecided`.
Action: dispatch `.aai/SKILL_WORKTREE.prompt.md` operation `recommendation gate`
and STOP until the user answers. Never create a worktree without user
confirmation. Each caller below adds its own handling for the already-decided
`worktree`/`inline` cases.
