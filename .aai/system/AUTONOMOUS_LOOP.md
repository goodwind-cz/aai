# AAI Autonomous Loop

## 1) Purpose & Scope
- This document defines how AAI operates autonomously in a documentation-driven repository.
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
- **Specialized agents** (mapping to the six workflow phases in `.aai/workflow/WORKFLOW.md`)
  - **Planner**: converts intake/requirements into SPEC/TASK artifacts.
  - **Tech extractor/updater**: maintains `docs/TECHNOLOGY.md` when missing/outdated.
  - **Implementation preparation (worktree gate)**: records the human worktree-vs-inline decision and review scope before implementation.
  - **Implementer**: executes changes only when implementation gate is open.
  - **Validator**: verifies traceability and evidence, returns PASS/FAIL.
  - **Code reviewer**: dual-verdict review (one pass returning spec_compliance and code_quality verdicts plus a mandatory cannot_verify list) after Validation; gates merge/PR readiness.
  - **Remediator**: applies minimal corrective changes after a Validation or Code Review FAIL.
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
   - or `project_status = paused`,
   - or **stagnation**: no change to focus or validation status across the
     configured number of consecutive ticks → first attempt ONE fresh-context
     recovery tick (clean context re-derives state from the filesystem; a stuck
     loop is usually context rot, not an impossible task), and only escalate to
     HITL if that also makes no progress — rather than spinning the remaining
     tick budget.
   - or **run budget exhausted**: cumulative cost/time for the run reaches a
     configured limit (wall-clock on the runners; tokens/USD in-session from
     best-effort usage telemetry) → escalate to HITL before starting another,
     costlier tick. A loop's per-iteration cost compounds; bound it so unattended
     spend cannot grow unchecked.

## 5) Gates and prohibitions (hard rules)
- No implementation without locked scope and SPEC.
- No PASS without executable evidence.
- Validator independence: the Validation role runs in a context that did NOT
  produce the implementation (maker≠checker is contextual, not just a role label) —
  a dedicated validator subagent fed only the artifacts, ideally on a different
  model. If isolation is impossible, validate from a cleared context and record the
  shared-context limitation as a residual risk. No silent self-validation.
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

### 6a) Post-freeze spec amendments (the additive-with-disclosure convention)

A frozen spec that proves incomplete mid-ride is amended, never quietly
rewritten: the new text is ADDITIVE, the original sentence stays, and the
change is DISCLOSED on `docs/ai/decisions.jsonl`. Amending a frozen spec is a
scope change, so section 6 assigns the decision to the owner. Waiting for that
decision would strand an autonomous ride at exactly the moment the convention
earns its keep — so the ride proceeds AND the sign-off it defers becomes a
tracked obligation the owner can drain, rather than a sentence in a ledger
nobody is obliged to read.

Record it with the writer, never by hand:

```
node .aai/scripts/spec-amend.mjs add --spec <path-to-spec> --ref <ride-ref> \
     --what "<one line>" --why "<one line>" --signoff none
```

`add --signoff none` appends the `spec_amendment` record AND files the
follow-up naming the spec and the sign-off still owed, in one invocation. It
never refuses for want of a tracked item — the obligation is created, not
demanded — so this path cannot block a remediation round. Use
`--signoff owner --authority "<evidence>"` only when the owner actually
decided, naming the record that proves it. Two rules hold this together:

- **The classifier is the `owner_signoff` field, never heading text and never
  prose.** A record with the field absent is `unclassified`, its own bucket:
  deciding after the fact which of the other two an old record "must have
  been" is precisely the laundering this convention has already suffered.
  SPEC-0164 carries three unsigned amendments and no `## Amendment` heading at
  all, so heading text could not classify them even in principle.
- **The obligation is drained through the registry.** The tracked item is
  keyed on the spec's frontmatter `id` — one per SPEC, because the owner's
  decision is per spec — and it appears in
  `node .aai/scripts/follow-ups.mjs list --status open`, which Planning
  already reads. Closing it is the owner's sign-off, not the ride's. The id is
  `fu-amend-<spec frontmatter id>` only when that FITS the registry's 40-char
  grammar; longer ids are shortened or truncated-and-hashed, so two of the five
  live ids are not the plain concatenation. Let the script derive it — never
  compose it by hand from this sentence.

`node .aai/scripts/spec-amend.mjs list --strict` exits 1 while any amendment
on the ledger is untracked or unclassified. It runs at the PR/close gate.

**When that gate refuses, run what it prints.** It emits one runnable
`spec-amend.mjs classify --ts … --ref …` line per offending record, already
carrying that record's own pair. Under `--signoff none` that one call
back-classifies the record AND files the tracked item it owes, so the record
leaves the violating bucket and the gate reaches 0. Two commands that look like
remedies are not: `spec-amend.mjs add` records a NEW amendment and leaves the
offending record exactly as untracked as it was, and `follow-ups.mjs add` files
an item attached to nothing. A gate whose named remedy does not clear the gate
is the same defect as an amendment whose disclosure has no outflow, one level
up — which is why the refusal names only the command that works.

**SPEC-0132 is NOT precedent for proceeding unsigned.** Its amendment is
headed `## Amendment (owner decision, 2026-08-15T08:14:24Z)` and cites a real
`hitl_decision` record on `docs/ai/decisions.jsonl` —
`ref_id: deslop-scope-and-unrequested-engine`, timestamp
`2026-08-15T08:14:24.000Z`, actor `ales_holubec.net`. The owner decided that
one. Citing it as the precedent that makes an UNSIGNED amendment routine
conflates a decision the owner made with a notice nobody read, and is the
transmission mechanism this section exists to break. Cite this section
instead; it is the convention's only statement.

## 7) Parallelism policy
- Allowed parallelism:
  - multiple planning threads on different scope IDs,
  - validation on independent scopes in parallel.
- Collision avoidance:
  - ownership by `work_item.id` / document,
  - active lock for scope in `docs/ai/STATE.yaml` (and optionally `.aai/system/LOCKS.md`).
- Merge strategy:
  - docs first (SPEC/TASK/EVIDENCE),
  - code second,
  - validation closeout last.

## 8) Unattended-safe execution (run while you sleep)
An overnight/scheduled run must never (a) ship unreviewed changes, (b) spin
forever on a stuck scope, or (c) leave you to reconstruct what happened from raw
telemetry. The runners (`.aai/scripts/autonomous-loop.{sh,ps1}`) provide three
guarantees for this:
- **Propose, don't ship** (`--propose-only` / `-ProposeOnly`): all work is
  isolated on a dedicated `aai/loop-<timestamp>` branch, a temporary `pre-push`
  hook HARD-blocks any push for the duration of the run (so neither the runner
  nor the agent can ship), and a review summary is printed at the end. You merge
  when you wake up. Recommended for any scheduled/headless run.
- **Self-recovery before HITL**: stagnation triggers one fresh-context recovery
  tick before escalating (see §4.7) — a stuck loop usually just needs a clean
  context, not a human at 3am.
- **Wake-up digest** (`.aai/scripts/loop-digest.mjs`): at the end of a run the
  runner writes one human-readable summary (ticks, scopes, recovery outcome,
  stop reason, branch left for review, cost if recorded) to
  `docs/ai/reports/loop-digest-<stamp>.md`. The chat/log becomes a status
  dashboard you skim, not a session you babysit.

## 9) Short flow example
- `.aai/INTAKE_CHANGE.prompt.md` creates CHANGE-123 intake.
- Planner creates `docs/specs/SPEC-123.md` plus tasks and locks the scope.
- Implementer performs only allowed-scope changes.
- Validator runs checks and stores evidence (for example `docs/ai/reports/validation-20260301-120000Z.md`).
- On PASS, `docs/ai/STATE.yaml` closes the scope; on FAIL, remediation is dispatched.
