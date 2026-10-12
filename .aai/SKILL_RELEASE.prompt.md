# Release Skill - Cut a Release

## Goal
Roll the current repo's `CHANGELOG.md` `[unreleased]` blocks into a versioned
section, commit on `chore/release-<version>` in an isolated temporary worktree,
and open a release PR — in one deterministic, operator-gated run. On merge of
the PR, CI (via `.github/workflows/release.yml`) creates the annotated tag and
publishes the GitHub release. Downstream repos lacking that workflow tag and
publish after merge (or vendor `release.yml`). Inputs: repo root,
`CHANGELOG.md`, and git/`gh` remote.

## Usage
```bash
/aai-release                        # plan-only (default-safe): prints the plan, changes nothing
/aai-release --dry-run              # same as bare invocation, explicit
/aai-release --version v1.2.3       # verbatim version (any scheme, incl. SemVer)
/aai-release --confirm              # THE CUT: open release PR
/aai-release --confirm --no-remote  # THE CUT, but skip push + gh pr create
```

Flags:
- `--dry-run` — print the plan (resolved version, CHANGELOG rollup preview,
  tag name, release-notes preview); changes NOTHING. Default-safe: a bare
  invocation (neither `--dry-run` nor `--confirm`) behaves identically.
- `--version <v>` — use this version verbatim (any scheme). Omitted → CalVer
  `vYYYY.MM.DD` (env `AAI_RELEASE_DATE` pins the date for testing/CI; unset
  uses the real UTC clock).
- `--confirm` (alias `--yes`) — required to actually cut. If `--dry-run` is
  also present, `--dry-run` wins (never auto-publish by accident).
- `--no-remote` (env twin `AAI_RELEASE_NO_REMOTE=1`) — performs the cut on a
  local `chore/release-<version>` branch but SKIPS `git push` and `gh pr create`.

## Instructions

The whole cut flow is scripted. Do NOT re-implement the CHANGELOG rollup or
the precondition checks by hand and do NOT narrate the steps — run the one
script for the current OS, forwarding the user's flags verbatim, and relay
its output.

1. From the target project root (or anywhere inside it), run:

   ```bash
   .aai/scripts/aai-release.sh            # bash / macOS / Linux
   ```
   ```powershell
   .aai/scripts/aai-release.ps1           # PowerShell / Windows
   ```

   The script handles everything: version resolution, the CHANGELOG rollup
   transform (byte-preserving, idempotent), the fail-closed precondition
   matrix, the temporary worktree commit, and — unless `--no-remote` — the push
   and release PR creation.

2. Relay the script's output as a SHORT report: resolved version, whether it
   was a plan or a cut, the release branch name, and (on a cut) the commit SHA
   and the opened PR URL. Do not paste the full rollup preview verbatim unless
   the user asks for it.

3. If the script exits non-zero, report the cause plainly and stop — do not
   retry with different flags on the agent's own initiative:
   - exit 1 = bad argument (the script prints its own usage)
   - exit 10 = not a git repository
   - exit 11 = no `CHANGELOG.md` at the repo root
   - exit 12 = malformed `[unreleased]` heading in `CHANGELOG.md` (fix the
     CHANGELOG by hand — the script never guesses at a malformed entry)
   - exit 13 = no rollable `[unreleased]` entries (absent or empty — nothing
     to release yet)
   - exit 15 = a tag for the resolved version already exists
   - exit 16 = `gh` absent or unauthenticated on the publish path (dry-run
     still works offline; pass `--no-remote` to skip publishing, or fix `gh
     auth login`)

## Safety
- NEVER pass `--confirm`/`--yes` on the agent's own initiative — cutting a
  release is an operator decision (mirrors the operator-only-merge boundary).
  Always run (or default to) `--dry-run` first and let the user review the
  plan before confirming.
- NEVER auto-publish. The script opens a `chore/release-<version>` PR; it calls
  neither `gh pr merge` nor `gh release create` directly — tagging and release
  publication occur automatically in CI upon PR merge.
- Under `--no-remote`/`AAI_RELEASE_NO_REMOTE=1`, the script never pushes or
  calls `gh pr create`, and a bare/`--dry-run` invocation never writes anything
  at all.
- The cut builds in an isolated temporary worktree from `origin/main` (or the
  target branch), so the caller's working tree is never touched or dirtied.
- The CHANGELOG rewrite is line-surgical and idempotent — re-running after a
  successful cut with no new `[unreleased]` entries correctly REFUSES (there
  is nothing left to roll); that refusal is expected, not a bug.
