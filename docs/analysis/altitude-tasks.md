---
id: altitude-tasks
type: research
number: null
status: draft
links:
  pr: []
  commits: []
---

# Analysis — replay task set for the altitude-prompt experiment (9 closed rides)

Phase 1 of `docs/issues/CHANGE-0113-altitude-prompt-experiment.md`. Nine real
CLOSED rides merged since 2026-07-25, selected small/medium and diverse across
ride flavour (fix / feat / refactor) and touched surface (script, prompt corpus,
config, template, test-harness, generator). Each row carries everything a replay
run needs: the intake as it existed **before planning**, the frozen spec that
actually resulted (ground truth), the PR, and the repo ref to plan against.

## Selection rules applied

1. **Closed and merged** on `origin/main` after 2026-07-25.
2. **Has a real frozen spec.** Many rides in this window shipped through the
   spec-less fast lane (CHANGE-0104/0105/0108-0112/0114-0122) and were excluded:
   with no spec there is no ground truth for scope fidelity.
3. **Small/medium**: 6-20 changed files. The largest excluded candidates were
   CHANGE-0066 (20 files / 1,853 insertions), CHANGE-0068 (25 files) and
   CHANGE-0087 (24 files).
4. **Recoverable pre-planning intake.** Preferred rides whose intake blob still
   exists in a `status: draft` form (frontmatter not yet flipped by the close
   ceremony). Eight of nine qualify; the one exception is flagged.
5. **Diversity**, deliberately spread: 3 fix-flavoured, 3 feat, 2 refactor,
   1 template/bootstrap; surfaces span `.aai/scripts/`, `.aai/*.prompt.md`,
   `.aai/system/*.yaml`, `.aai/templates/`, `tests/skills/` and a generator.

## The nine tasks

| # | ref | task statement (one line) | flavour / surface | PR | ground-truth spec | intake path | `intake_ref` (blob) | `base_ref` (tree) | size |
|---|---|---|---|---|---|---|---|---|---|
| T1 | CHANGE-0050 | Make the test reaper fail safe when `ps -o etime` returns an unparseable shape instead of flaking test-018. | fix / `.aai/scripts` + `tests/skills` | #149 | `docs/specs/SPEC-0083-spec-reaper-test-018-etime-shape-guard.md` | `docs/issues/CHANGE-0050-reaper-test-018-etime-shape-guard.md` | `8bd6e74` ⚠ | `609d15c` | 6 files, +245/-5 |
| T2 | CHANGE-0058 | Make silent telemetry-capture gaps loud: a canary that fails when a flush records zero tokens. | feat / telemetry scripts + prompts + tests | #158 | `docs/specs/SPEC-0085-spec-token-capture-canary.md` | `docs/issues/CHANGE-0058-token-capture-canary.md` | `b2d8041` | `d1e4c99` | 19 files, +977/-38 |
| T3 | CHANGE-0059 | Dedup the prompt corpus: one canonical home each for ceremony rules, the AC gate and role boilerplate. | refactor / prompt corpus | #159 | `docs/specs/SPEC-0086-spec-prompt-dedup-canonical-includes.md` | `docs/issues/CHANGE-0059-prompt-dedup-canonical-includes.md` | `bd4142d` | `ec048b3` | 19 files, +736/-113 |
| T4 | CHANGE-0061 | Slim the per-dispatch subagent contract to a brief-first, result-block-only handoff. | refactor / protocol + prompts | #161 | `docs/specs/SPEC-0087-spec-subagent-protocol-slim.md` | `docs/issues/CHANGE-0061-subagent-protocol-slim.md` | `397d00d` | `454f152` | 20 files, +751/-82 |
| T5 | CHANGE-0065 | Route mechanical roles to a cheap model with tier-appropriate validation, driven by config not prose. | feat / dispatch script + `MODEL_ROUTING.yaml` | #165 | `docs/specs/SPEC-0091-spec-cheap-model-in-practice.md` | `docs/issues/CHANGE-0065-cheap-model-in-practice.md` | `cd140d6` | `b862070` | 13 files, +774/-23 |
| T6 | CHANGE-0072 | Wire the orchestrator to actually record the prompt hash that dispatch already computes. | feat / prompt + runtime wiring | #172 | `docs/specs/SPEC-0098-spec-prompt-hash-runtime-wiring.md` | `docs/issues/CHANGE-0072-prompt-hash-runtime-wiring.md` | `f3015f6` | `c9059af` | 10 files, +348/-8 |
| T7 | CHANGE-0074 | Ship `STATE_TEMPLATE.yaml` and teach `check-state --repair` to create a missing STATE file. | fix-flavoured feat / template + script | #176 | `docs/specs/SPEC-0099-spec-state-bootstrap-template.md` | `docs/issues/CHANGE-0074-state-bootstrap-template.md` | `f7320bb` ★ | `6df1e2a` | 14 files, +557/-15 |
| T8 | CHANGE-0076 | Drop the dashboard prompt's dead source dump, fix its schema docs, and decide the `--publish` behaviour. | fix / skill prompts + generator | #179 | `docs/specs/SPEC-0101-spec-dashboard-refit.md` | `docs/issues/CHANGE-0076-dashboard-refit.md` | `85c040e` ★ | `ddb7eca` | 10 files, +384/-1043 |
| T9 | CHANGE-0079 | Replace `aai-doctor`'s prose-computed categories with one deterministic script. | fix / skill prompt + `aai-doctor.mjs` | #178 | `docs/specs/SPEC-0100-spec-doctor-determinize.md` | `docs/issues/CHANGE-0079-doctor-determinize.md` | `85c040e` ★ | `19a9675` | 16 files, +1568/-229 |

★ = **CLEAN**: at `intake_ref` the intake exists and the ground-truth spec does
**not** exist anywhere in the tree. T7's intake landed in PR #174 and T8/T9's in
PR #175, both intake-only batches; the specs arrived one to five PRs later.

⚠ = **T1 needs sanitizing** (see below): its intake first appears on `main`
already flipped to `status: done` by the close ceremony, because that ride
pre-dates the split-intake practice.

## How to read `intake_ref` and `base_ref`

- **`intake_ref`** is the commit whose blob of the intake file is the
  **pre-planning** text. Verified per row: at that ref the frontmatter reads
  `status: draft` and `links.pr` is empty (except T1).
  Extract with `git show <intake_ref>:<intake path>`.
- **`base_ref`** is `<delivery-commit>^1` — the tip of `main` immediately before
  the ride landed. **Verified for all nine**: the ground-truth spec is absent at
  `base_ref`, and nothing the ride produced is present.
- For **T7, T8 and T9 the intake is already present at `base_ref`** (it landed in
  the earlier intake-only PRs #174/#175), in its `status: draft` form. Those three
  need no materialization step — sanitize in place. For T1-T6 the intake must be
  written into the tree from `intake_ref`.

**Honest note on "the commit that added the intake".** For only three of the nine
(T7, T8, T9) does a commit exist in `main`'s history where the intake is present
and the spec is absent. AAI's own PR ceremony stages the whole ride at once, so
for the other six the intake and the spec landed in the same commit. The
two-ref construction above (`base_ref` for the tree, `intake_ref` for the blob)
reproduces the pre-planning condition exactly, and is what the replay protocol
uses for all nine so the treatment is identical across tasks.

## Intake sanitization (mandatory before any run)

The merged intake leaks the outcome. Before handing an intake to a replay run,
normalize its frontmatter:

```
status: <anything>   ->  status: draft
links:
  spec: <path|null>  ->  spec: null     (T1 only — its frontmatter carries the key)
  pr:
    - 149            ->  pr: []
  commits:
    - a2f5a47…       ->  commits: []
```

Nothing in the body is edited. This matters only for T1, whose one recoverable
blob is post-close (`status: done`, `pr: [149]`, `commits: [a2f5a47…]`); the
other eight `intake_ref` blobs are already `status: draft` with empty `pr` and
`commits` (verified), so the normalization is a no-op there — but it is run on
all nine so every task receives identical treatment.

## Ground-truth caveats

- The frozen specs are the **actual** planning output of the shipped V0 prompt,
  produced by a model of the day against a repo of the day. They are ground truth
  for *scope* and *evidence contract*, not a gold standard for AC prose — a
  variant may legitimately beat V0 on measurability while matching its scope.
  The rubric in `docs/analysis/altitude-judging.md` scores these separately for
  exactly that reason.
- T3, T4 and T6 touch the prompt corpus, so their correct specs must carry the
  prompt-diet companion obligation. That makes them the sharpest probe of
  disposition row R16 — a variant that drops the COMPANION OBLIGATIONS block
  should visibly fail scope fidelity on these three.
- T8's ride is net-negative in lines (+384/-1043). Rides that mostly delete are
  the ones where an over-eager planner invents requirements; expect the
  hallucinated-requirements metric to do its work here.
