---
id: altitude-replay-protocol
type: research
number: null
status: draft
links:
  pr: []
  commits: []
---

# Analysis — replay protocol for the altitude-prompt experiment (PLANNING pilot)

Phase 1 of `docs/issues/CHANGE-0113-altitude-prompt-experiment.md`. This document
fixes the exact per-run shape **before** any run happens, so the orchestrator
executes rather than improvises. Phase 1 produced no runs; the orchestrator
executes the 27-cell matrix (9 tasks × 3 variants) from here.

## Inputs, all committed on this branch

| artifact | path |
|---|---|
| V0 (status quo, byte-copy of the shipped prompt) | `docs/analysis/altitude-variants/V0-PLANNING.md` |
| V1 (compression control) | `docs/analysis/altitude-variants/V1-PLANNING.md` |
| V2 (altitude / unhobbled) | `docs/analysis/altitude-variants/V2-PLANNING.md` |
| task set, refs and sanitization rule | `docs/analysis/altitude-tasks.md` |
| rubric, D1-D4, blinding plan | `docs/analysis/altitude-judging.md` |
| sealed label→variant key | `docs/analysis/altitude-blinding.b64` |
| rule dispositions and pin map | `docs/analysis/altitude-disposition-PLANNING.md` |

Byte counts (measured, `wc -c`): **V0 11,526** · **V1 8,109** (−29.6 % vs V0) ·
**V2 7,841** (−32.0 % vs V0, **−3.3 % vs V1** — inside the ±5 % equal-budget
requirement, which is what makes H2 testable).

## Per-run procedure

For each task T in T1..T9 and each variant X in {V0, V1, V2} — 27 runs:

1. **Isolate.** `git worktree add <tmp> <base_ref(T)>` — the tree as it stood
   immediately before the ride landed. The intake is absent, the ground-truth
   spec is absent, and nothing the ride produced is present. Never run two cells
   of the matrix in the same worktree.
2. **Materialize the intake.** For T1-T6, write
   `git show <intake_ref(T)>:<intake path>` into the worktree at its original
   path. For T7-T9 the intake is already present at `base_ref` — leave it where
   it is. Then apply the sanitization from `altitude-tasks.md`
   (`status: draft`, `links.pr: []`, `links.commits: []`) to all nine, so the
   treatment is identical. Body untouched.
3. **Seed STATE minimally.** `node .aai/scripts/state.mjs set-focus --type change
   --ref <REF-ID> --path <intake path>` in that worktree, so the run has a real
   focus without being handed the answer. Record `usage_capture=none` if the
   harness exposes no usage.
4. **Dispatch** with the prompt shape below, same model and same effort for all
   27 cells. Vary **nothing** but the attached PROMPT TEXT.
5. **Capture**: the produced spec, the produced brief, the run's
   `usage_total_tokens`, wall-clock, and the run's own final message. Write them
   to `docs/analysis/altitude-runs/<T>/<X>/` (gitignored working area; only the
   aggregate table is committed).
6. **Never** let a run see another cell's output, the ground-truth spec, or any
   other variant.

## The exact per-run prompt shape

Sent verbatim; only the two attachments change:

> You are the Planning role for this repository.
>
> Your ENTIRE role instruction is the attached PROMPT TEXT. Follow only it. Do
> not consult `.aai/PLANNING.prompt.md` or any other role prompt for guidance
> about how to plan, and do not blend in prior knowledge of how this repo's
> Planning role normally behaves. If the attached PROMPT TEXT and your own
> instincts disagree, the attached PROMPT TEXT wins.
>
> The task intake is attached. The repository is checked out at the commit that
> preceded this work; treat it as the current state of the world.
>
> Produce the frozen spec and the work-item brief.
>
> --- PROMPT TEXT ---
> {contents of docs/analysis/altitude-variants/<X>-PLANNING.md}
> --- END PROMPT TEXT ---
>
> --- TASK INTAKE ---
> {sanitized intake for task T}
> --- END TASK INTAKE ---

## Honest methodological note (read before believing any result)

**The variant is delivered as an attachment inside a user turn, not as the
agent's system prompt.** A real dispatch installs the role prompt as the system
prompt, where it is cached, ordered first, and carries different weight than
in-context user content. This replay therefore measures *"how well does this text
steer a planning run when supplied as instructions"*, which is close to but not
identical to *"how well does this text work as a system prompt"*.

Why the result still supports a decision:

- **The treatment is identical across all three variants.** Whatever discount
  attachment-delivery imposes, it is applied equally to V0, V1 and V2, and the
  design reports only **paired within-task differences**. A shared bias cancels;
  it cannot manufacture a V2>V0 or V1>V2 gap.
- **The direction of any residual bias is knowable and against V2.** Attached
  text tends to be treated as reference material rather than as identity. A
  principles-first prompt (V2) depends more on being adopted as identity than a
  step-list (V0) does, so the attachment framing, if anything, *handicaps* V2. A
  V2 win under this framing is therefore conservative; a V2 loss is partially
  confounded and must be reported as such rather than as a clean refutation.
- **The prompt-as-attachment framing is stated in the results doc**, not buried
  here, and the production-confirmation phase (ship the winner, compare
  remediation-per-ride over the next 10 rides) is what closes the gap. Replay
  picks a candidate; production confirms it.

Two things this replay explicitly cannot measure, and must not be claimed to:
prompt-cache economics (the stable-prefix saving only exists for a real system
prompt) and multi-turn drift (each cell is a single planning run).

## Guardrails during execution

- **V0 stays the shipped prompt.** No cell writes to `.aai/`. The experiment
  touches `docs/analysis/**` only, so no prompt-diet ledger entry and no
  `PROFILES.yaml` classification is owed — the variants are not `.aai/**` files.
  (This is disposition row R16 applied to the experiment itself.)
- **Pin suites and CI stay green throughout** (intake AC-005). Run
  `tests/skills/test-aai-prompt-diet.sh` and `test-aai-hygiene-pack.sh` once at
  the start and once at the end of the matrix to prove nothing drifted.
- **Judging happens only after all 27 cells complete**, so a partial matrix
  cannot bias label assignment.
- **The seal is opened last.**
  `base64 --decode < docs/analysis/altitude-blinding.b64` only after every M1-M6
  score is recorded, and only after verifying the sha256 in
  `altitude-judging.md`.
- **A null is a result.** If the paired sign test does not separate the variants,
  the finding is "compression suffices — altitude unproven here", and it gets
  written up with the same care as a win (intake AC-004).

## Cost estimate, restated for this pilot

27 planning runs. Planning's measured median is ~115 K tokens/run (n=37), so the
matrix is ≈3.1 M tokens, plus 9 tasks × 2 judges ≈ 0.3-0.4 M. Roughly one heavy
ride-day. The prompt itself is 3-9 % of a run, so no variant can win on direct
prompt bytes; the wager is entirely on planning quality and avoided rework.
