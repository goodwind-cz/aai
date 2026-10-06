---
id: worktree-lacks-vendored-aai-layer-downstream
type: issue
number: 93
status: draft
links:
  pr: []
  commits: []
---

# Issue — In a downstream project a new worktree has no `.aai/` layer and no skills, so the worktree flow breaks at its first step

## Summary
- In every project that installs AAI via `aai-sync.sh`, the vendored layer is
  gitignored on purpose: `.aai/scripts/aai-sync.sh:676-680` appends
  `# AAI infrastructure (vendored, not committed)` + `.aai/` to the target's
  `.gitignore`, and the managed block also ignores `.claude/skills/`,
  `.agents/skills/`, `.codex/skills/`, `.gemini/skills/`.
- `git worktree add` checks out only tracked files. A fresh worktree in a
  downstream project therefore has **no `.aai/` and no skills**.
- `.aai/SKILL_WORKTREE.prompt.md` step 3 creates the worktree with
  `git worktree add`, and step 4 immediately runs
  `node .aai/scripts/check-state.mjs --repair` inside it. Downstream that file
  does not exist, so the canonical worktree flow fails at its first command.
- Nothing in the worktree flow seeds the vendored layer or the skills into the
  new checkout.
- This never showed in the AAI source repository because that repository
  TRACKS `.aai/`. The defect only exists where the layer is vendored, which is
  every real consumer.

## Type
- bug

## Impact
- Who/what is affected: every downstream AAI project that uses a worktree —
  `/aai-worktree setup`, the rule-8 worktree gate, the `/aai-ship` autopilot
  default `recommended -> worktree`, and any ride carried into a worktree
  mid-flight.
- Worse than the crash: the worktree DOES contain the tracked shims
  (`CLAUDE.md` was present in the reproduction), and those shims point to
  `.aai/AGENTS.md`, `.aai/ORCHESTRATION.prompt.md`, the canonical role prompts
  and `docs/knowledge/LEARNED.md` routing. An agent started in that worktree
  reads instructions that point at files which are not there. Depending on the
  harness it either stops, or improvises the workflow without the canon, the
  guards and the skills — silently, with no AAI rules applied.
- Role scripts invoked by relative path (`node .aai/scripts/state.mjs ...`,
  `orchestration-dispatch.mjs`, `canon.mjs build`) all fail the same way from
  inside the worktree.
- Severity/priority: high. It breaks a canonical, autopilot-default path in
  every downstream project, and its quieter failure mode runs a ride with no
  rules at all.

## Current Behavior
Reproduced on 2026-10-03 with a scratch downstream project, not inferred:

```
git init demo && commit README
bash .aai/scripts/aai-sync.sh demo --profile core          # rc=0
grep -nE '^\.aai/|skills/' demo/.gitignore
  3:.aai/   41:.aai/cache/   44:.agents/skills/   45:.claude/skills/
  46:.codex/skills/   48:.gemini/skills/
git -C demo add -A && git -C demo commit -m "install AAI"
git -C demo ls-files .aai | wc -l                           # 0
git -C demo worktree add ../demo-wt -b feat/x
ls -d demo-wt/.aai demo-wt/.claude/skills demo-wt/AGENTS.md
  -> No such file or directory   (all three)
ls -d demo-wt/CLAUDE.md                                     # present
cd demo-wt && node .aai/scripts/check-state.mjs --repair
  -> node:internal/modules/cjs/loader ... throw err  (MODULE_NOT_FOUND)
```

## Expected Behavior
- A worktree created by the AAI worktree flow in a downstream project has the
  SAME vendored layer the main checkout has: `.aai/` and every synced skills
  directory, at the same installed version and profile.
- The worktree flow's first AAI command succeeds downstream exactly as it does
  in the source repository.
- If the layer cannot be made available, the flow refuses loudly before any
  role is dispatched into that worktree — never a worktree whose shims point at
  missing canon.
- The fix holds on both supported shells (bash and PowerShell; the repo keeps
  `.sh`/`.ps1` parity) and on Windows, where symlinks are not reliably
  available without privileges.
- The AAI source repository, which tracks `.aai/`, keeps working unchanged.

## Steps to Reproduce (if applicable)
1. Create an empty git repository and commit one file.
2. From the AAI repo: `bash .aai/scripts/aai-sync.sh <that repo> --profile core`.
3. In the target: `git add -A && git commit -m "install AAI"`; confirm
   `git ls-files .aai` prints nothing.
4. `git worktree add ../<repo>-wt -b feat/x`.
5. In the new worktree: `ls .aai` fails; `node .aai/scripts/check-state.mjs
   --repair` fails with MODULE_NOT_FOUND; `CLAUDE.md` exists and points at the
   missing `.aai/AGENTS.md`.

## Verification
- A fixture that performs steps 1-4 (real `aai-sync.sh`, real `git worktree
  add`, no mocks) and then runs the worktree flow's seeding: afterwards `.aai/`
  and the synced skills directories exist in the worktree and
  `node .aai/scripts/check-state.mjs` succeeds there.
- Version parity: the worktree's layer matches the main checkout's installed
  version/profile (the sync pin), asserted, not assumed.
- The same fixture on the AAI source repository layout (`.aai/` tracked) proves
  nothing regresses there and nothing is double-copied over tracked files.
- A refusal arm: when the layer cannot be seeded, the flow exits non-zero with a
  named reason and records no `worktree` decision.
- PowerShell parity for whatever bash path the fix adds.
- Fixture git setup survives CI: fixtures that commit set their own
  `user.email`/`user.name`; no unchecked setup subshell exit codes.

## Constraints / Risks
- Copying vs linking. A copy can drift from the main checkout if `/aai-update`
  runs while the worktree lives; a symlink stays in sync but is unreliable on
  Windows and lets a worktree edit the shared vendored layer. Planning chooses;
  the drift and the Windows case must both be addressed, not one.
- The worktree must not start TRACKING `.aai/`. Whatever is seeded stays
  ignored, so a commit from the worktree cannot accidentally vendor the layer
  into the project's history.
- Related but distinct, so do not merge them without Planning deciding to:
  - the live-STATE carry when the worktree decision comes after a role has run
    (gitignored `docs/ai/STATE.yaml` and briefs) — same gitignore root cause,
    different files;
  - CHANGE-0152 `suites-run-in-a-disposable-worktree`: `aai-run-tests.sh` seeds
    untracked-but-NOT-ignored files into its throwaway checkout, so it would
    not seed `.aai/` either. Whether that isolation ever applies to a
    downstream invocation was NOT measured — Planning should check.
- Same family as CHANGE-0177 `lessons-that-must-hold-downstream-are-guards`:
  the source repo's own layout hides defects that only exist downstream. A
  guard that runs only in the source repository would not have caught this.
- No local secret is referenced by this scope; the secrets preflight is skipped.

## Notes
Implementation mode (user choice): tdd — owner chose full TDD at intake
2026-10-03 (recommended: behavioral, multi-surface across prompt, bash and
PowerShell, affects every downstream project; the reproduction above is a
natural RED). Recorded here because `set-strategy` exited 2: `current_focus`
is held by the live, concurrent ride `ci-test-selection-narrowing-and-sharding`
(INTAKE_COMMON, LIVE OTHER FOCUS — the legitimate case this time).

- Raised by the owner on 2026-10-03 while a ride in this repository was being
  carried into a worktree: "if they install AAI into another project, `.aai` is
  in .gitignore".
- An earlier answer in the same session claimed `.aai/` is never gitignored;
  that was true only for the AAI source repository and was corrected by the
  reproduction above.
