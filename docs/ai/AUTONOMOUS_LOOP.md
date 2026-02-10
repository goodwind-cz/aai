# AI-OS Autonomous Loop

## 1) Purpose & Scope
- This document defines how AI-OS operates autonomously in a documentation-driven repository.
- "Autonomy" means: evaluate state, select the next role, produce/update artifacts, and persist the new state.
- "Autonomy" explicitly does **not** mean:
  - uncontrolled commits,
  - silent changes without artifact traceability,
  - bypassing validation gates,
  - relying on chat history.

## 2) Entities
- **Orchestrator**
  - Reads `docs/ai/STATE.yaml` and workflow documents.
  - Chooses the next step and allowed role(s).
- **Specialized agents**
  - **Planner**: converts intake/requirements into SPEC/TASK artifacts.
  - **Researcher**: enriches facts, risks, and technical constraints.
  - **Implementer**: executes changes only when implementation gate is open.
  - **Validator**: verifies traceability and evidence, returns PASS/FAIL.
- **HITL (Human-in-the-loop)**
  - Resolves disputed decisions, scope changes, and high-impact risk decisions.

## 3) Triggers
- A new or updated INTAKE document.
- Validator FAIL or missing evidence.
- Drift detection event (conceptual: mismatch between docs, state, and implementation).
- Scheduled check (conceptual: periodic health review).

## 4) State-driven loop
1. **Read state** from `docs/ai/STATE.yaml`.
2. **Determine allowed actions** from locks, phase, and invariants.
3. **Select role(s)** for current focus (`current_focus`).
4. **Produce artifacts** by phase: PRD/SPEC/TASK/EVIDENCE.
5. **Run validator (conceptual)**:
   - check Requirement → Spec → Implementation → Evidence chain,
   - verify measurable acceptance criteria,
   - verify reproducible commands/evidence,
   - emit strict PASS/FAIL verdict.
6. **Update `docs/ai/STATE.yaml`** (work status, validation status, HITL need).
7. **Stop conditions**:
   - `last_validation.status = pass` and no open items,
   - or `human_input.required = true` (waiting for decision),
   - or `project_status = paused`.

## 5) Gates and prohibitions (hard rules)
- No implementation without locked scope and SPEC.
- No PASS without executable evidence.
- No direct edits to protected paths unless state explicitly allows it.
- No "discussion reread"; repository artifacts are the only source of truth.

## 6) HITL policy
- Stop and request human decision when:
  - scope/priority decision is missing,
  - requirements conflict,
  - protected area edits are needed,
  - risk exceeds predefined limits.
- Human request must be minimal:
  - one question,
  - max 2–3 options,
  - one recommended option with impact summary.
- If input is missing:
  - set `human_input.required = true`,
  - mark work as blocked,
  - do not perform speculative implementation.

## 7) Parallelism policy
- Allowed parallelism:
  - multiple planning/research threads on different scope IDs,
  - validation on independent scopes in parallel.
- Collision avoidance:
  - ownership by `work_item.id` / document,
  - active lock for scope in `docs/ai/STATE.yaml` (and optionally `docs/ai/LOCKS.md`).
- Merge strategy:
  - docs first (SPEC/TASK/EVIDENCE),
  - code second,
  - validation closeout last.

## 8) Short flow example
- `ai/INTAKE_CHANGE.prompt.md` creates CHANGE-123 intake.
- Planner creates `docs/specs/SPEC-123.md` plus tasks and locks the scope.
- Implementer performs only allowed-scope changes.
- Validator runs checks and stores evidence (for example `docs/validation/VAL-123.md`).
- On PASS, `docs/ai/STATE.yaml` closes the scope; on FAIL, remediation is dispatched.
