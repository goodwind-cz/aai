---
id: review-a-check-cannot-tell-silence-from-a-verdict
type: review
number: null
status: done
links:
  pr: []
  commits: []
---

# Code Review — a-check-cannot-tell-silence-from-a-verdict

Reviewer model: claude-sonnet-5 (independent of the implementer, claude-opus-5).
Base: `b843a716`. Scope: `git diff b843a716..working-tree` plus the two untracked
drafts. Validation had already recorded PASS.

## Verdict

- spec_compliance: **pass** — all 13 Spec-AC walked with a citation each.
- code_quality: **pass** — three findings, all NON-BLOCKING.
- overall: **pass**

## Findings

### 1. NON-BLOCKING — `.github/workflows/ps1-quality.yml:1061`

The CAT-17 PASS gate uses PowerShell's default **case-insensitive** `-notlike` /
`-like`, and nothing anchors the match to the renderer's `id status reason`
token position.

Failure scenario: if any future CAT-17 WARN/DECLINED/FAIL reason string ever
contains the substring `pass` in any case (`AAI_GIT_WRITE passed through`,
`bypass`), `$cat17 -notlike "* PASS *"` reads it as containing the token and the
step prints `AAI-WIN-CAT17-OK` and exits 0 on a verdict that was never PASS.
No current reason string collides (verified: the only `pass`-shaped substring in
the whole CAT-17 branch is the PASS literal itself), so this is latent, not live.

Remedy: `-cnotlike` (case-sensitive), or split the line and compare the status
field exactly. **Taken in-tree in this ride** — it is this ride's own defect
class in this ride's own new code.

### 2. NON-BLOCKING — `.aai/scripts/lib/guard-config.mjs:215`

`gitForWindowsShell`'s `w.isAbsolute(core)` guard does not fully prevent the
ambient dependence the adjacent comment claims. `path.win32.isAbsolute()`
returns true for a drive-relative rooted path with no drive letter, which is the
shape `git --exec-path` can print under MSYS/Git-Bash.

Measured: `gitForWindowsShell('/mingw64/libexec/git-core')` →
`\usr\bin\sh.exe`; `gitForWindowsShell('/c/Program Files/Git/mingw64/libexec/git-core')`
→ `\c\Program Files\Git\usr\bin\sh.exe`. Both resolve against the current
working drive at runtime.

Not live: the downstream `exists(gitShell)` gate means a wrong derived path
never spawns — it fails `exists()` and falls back to bare `sh`/`bash`, i.e. the
pre-ride behaviour already disclosed under R1/R2. Consequence is a silently
missed fast path on one shape, never a wrong verdict. TEST-1346 covers only the
clean `C:\...\git-core` shape.

Disposition: tracked follow-up, P3.

### 3. NON-BLOCKING — `.aai/scripts/lib/docs-model.mjs:1280`

The Spec-AC-10 widening evaluates status-vocabulary on any table gated in purely
by column-NAME reuse (`AC` + `Status` + (`Review-By` | `Evidence`)), not by
actually being a spec-AC table.

Failure scenario: an unrelated table whose headers happen to read
`AC | Status | Review-By` for a different domain (an access-control checklist
where `AC` means something else, statuses `Open`/`Closed`) now gets spurious
`status-vocabulary` findings quoting its own words, where before it got only the
already-present `column-set` finding.

This is the ride's own hazard class, but it is substantially the risk the spec's
D6/R3 already name and gate through the before/after live-corpus disposition
(Spec-AC-11, satisfied: 8 docs before and after). No fixture exercises a
different-domain table reusing these column names as a true negative.

Disposition: tracked follow-up, P3.

## Cannot verify

- The windows-wsl1 CI step's behavioural half (Spec-AC-07) on a real
  GitHub-hosted Windows PowerShell 5.1 + WSL runner. Closes with this ride's own
  PR run URL and step log. Deferred by the spec itself (D4/R1/R2), not a gap this
  review introduces.
- Whether `git --exec-path` ever returns a drive-relative/MSYS-rooted shape in
  the Windows environments this doctor actually runs in — bears on whether
  finding 2 is live anywhere. Closes with a sampled survey or field telemetry.
- That the four touched suites are green against this exact tree: the reviewer
  did not execute them, because a full sweep was already running in the worktree
  and a second writer would have tripped its dirty-tree tripwire. Verified
  instead by static tracing plus the stored RED/mutation/GREEN artifacts.
- `mutation-gate.mjs`'s own verdict over this spec — outside the review's file
  scope. (Separately measured by the orchestrator: GATE PASS 13/13.)

## Process note, recorded against the orchestrator

The dispatch prompt's eight "review angles" named concrete mechanisms and in
places leaned toward characterising the expected answer ("check it cannot have
side effects", "prove ... cannot widen"). That borders on the coaching
`SUBAGENT_PROTOCOL.md` "Review dispatch anti-gaming rules" #1 prohibits. The
reviewer recorded it and reviewed the full diff anyway — all 19 changed files
plus the two untracked drafts, not only the named angles. The finding is upheld:
a review dispatch should name where to look, not what the answer is.
