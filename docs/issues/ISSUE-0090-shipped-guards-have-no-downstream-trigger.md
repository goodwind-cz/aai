---
id: shipped-guards-have-no-downstream-trigger
type: issue
number: 90
status: draft
links:
  pr: []
  commits: []
---

# The guards the canon relies on are shipped downstream with nothing to invoke them

## Summary
- Three GitHub issues (#392, #391, #390) report one defect from three angles: AAI vendors guards that are written, tested and documented, and ships them downstream with **no installed caller**. The prompts then cite those guards as the backstop.
- Verified in this repository, not taken from the reports: neither `install-pre-commit-hook.sh` nor `install-pre-commit-hook.ps1` contains a single reference to `pre-commit-checks.sh` (grep count 0 in both), and the only thing that invokes `close-reconcile.mjs` is `.github/workflows/close-gate.yml` — which is NOT vendored (`.aai/templates/` ships `WORKFLOW_TEMPLATE.md` and two hook JSONs, no CI definition, no pre-push).
- Consequence reported downstream: a real delivery merged with three unnumbered `*-DRAFT-*` documents, `links.pr: []`, no close events and a recorded `overall: fail` review — with no warning from any layer.

## Type
- bug

## Impact
- Every project that vendors the AAI layer. The factory's own repository is unaffected because it has the CI job the downstream never receives — which is exactly why this stayed invisible here.
- Severity: high. Three separate reporter analyses, all reproducible, all from a live Azure DevOps project on `aai_pin: v2026.09.09`.
- The failure is silent in both directions: nothing reports that the hook is unwired, and nothing reports that the close gate has no trigger.

## Current Behavior
- **The pre-commit backstop is never installed.** `SKILL_PR.prompt.md` step 1b names "the pre-commit guards are the backstop" for an unnumbered draft. The installed `.git/hooks/pre-commit` carries only the `AAI:INDEX-AUTOGEN` block; it regenerates and stages `docs/INDEX.md` and exits, so CHECK 8 (`no-DRAFT-at-merge` + `duplicate-number`) never executes.
- **And it would only warn.** CHECK 8 is gated at `pre-commit-checks.sh:215` on `doc_number_guard: enforce`. **Correction to the report:** `.aai/templates/docs-audit.template.yaml:45` DOES ship the key — set to `report-only`. The reporter's project has it absent, which is a version difference; the effect is identical either way, and the default is the thing in question.
- **The close gate has no trigger downstream.** `close-reconcile.mjs`'s own header states that "exactly one thing triggers the check". In a bootstrapped project nothing does: no CI definition is vendored, and the installed `pre-push` is the stock git-lfs hook.
- **On Azure it could not remediate even if it fired.** `close-reconcile.mjs:194` is `PR_SUBJECT_RE = /\(#(\d+)\)\s*$/`, the trailing `(#N)` GitHub appends on squash. Azure DevOps writes `Merged PR 811: <title>`, so `parsePrNumber` resolves nothing and every otherwise-resolvable item is refused by name.

## Expected Behavior
- A guard the canon cites as a backstop is invoked by something the installer put there, on every platform the layer supports — not only in the factory's own repository.
- A project where a shipped guard has no caller is reported as degraded by name, rather than passing silently.
- The close gate's remediation is runnable on the platforms the layer claims to support, or it refuses in a way that says which platform grammar it needs.

## Steps to Reproduce
1) Bootstrap an AAI project and install the hooks.
2) `grep -c pre-commit-checks .git/hooks/pre-commit` → `0`.
3) `grep -rl close-reconcile .` → the script and `PROFILES.yaml` only; `cat .git/hooks/pre-push` → stock git-lfs hook.
4) `git add docs/issues/CHANGE-DRAFT-example.md && git commit` → succeeds silently.
5) Open and merge a PR without `/aai-pr` → nothing reports the open documents.

## Verification
- A freshly bootstrapped project's installed `pre-commit` hook reaches `pre-commit-checks.sh`, proven by running a commit of an unnumbered draft and observing the guard's own output.
- A freshly bootstrapped project has an installed trigger for `close-reconcile --check` that works with NO CI present, and the trigger is exercised by a test that merges without `/aai-pr`.
- An Azure-style merge subject (`Merged PR 811: <title>`) resolves a PR number, asserted against a fixture carrying that exact subject form; the GitHub form keeps working.
- `aai-doctor` reports a project whose shipped guard has no caller, and the assertion fails when the wiring is removed.
- The installer is idempotent: running it twice leaves one hook that still reaches both responsibilities.

## Constraints / Risks
- **The installer must not clobber a project's own pre-commit hook.** The current one already owns `AAI:INDEX-AUTOGEN` by marker; adding a second responsibility has to stay marker-scoped and idempotent, or it becomes the same class of defect as GitHub issue #414 — a sync that destroys something the user authored.
- Two platforms and two shells: the fix must land in `install-pre-commit-hook.sh` AND `.ps1`, and any CI snippet has to exist for both GitHub Actions and Azure Pipelines or say plainly which it covers.
- Defaulting `doc_number_guard` to `enforce` changes behaviour for every existing downstream project on its next sync. The reporter argues `no-DRAFT-at-merge` has no legitimate false positive; that is a decision for the spec, not an assumption for the implementation.
- A pre-push hook that runs a close gate must not become a hard block in a repository with no CI and no operator to override it — report-only by default, dialled by the same `docs/ai/docs-audit.yaml` mechanism the other guards use.
- Scope risk: this could grow into "AAI supports Azure DevOps end to end". It should not. The Azure half here is the PR-subject grammar only.
- No secret referenced; secrets preflight skipped.

## Notes
- Sources, triaged via `/aai-issues`: https://github.com/goodwind-cz/aai/issues/392, https://github.com/goodwind-cz/aai/issues/391, https://github.com/goodwind-cz/aai/issues/390. The reporter analyses are quoted as DATA below and were each checked against this repository before filing.
- Filed as ONE work item on purpose. The three issues share a single cause — a shipped guard with no installed caller — and cutting them into three rides would mean solving "how does the downstream install and invoke what the layer ships" three times.
- Reporter's own summary of the systemic point, as data:

> The gate has to be remembered and run by hand, which is exactly the property the design set out to remove.

> That leaves the correct-ordering discipline living only in operator memory, which is the failure mode the deterministic scripts were built to replace.

- Reporter environment, as data: Azure DevOps hosted repo, Windows, node 24, harness Claude Code, `aai_pin: v2026.09.09`.
- Related and NOT in scope: GitHub issue #414 (merged as ISSUE-0089) fixed a sync that disarmed an installed hook. This one is the layer above — a hook that was never installed.
