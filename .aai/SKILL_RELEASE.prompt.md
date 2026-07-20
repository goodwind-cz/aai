# Release Skill - Cut a Release

## Goal
Roll the current repo's `CHANGELOG.md` `[unreleased]` blocks into a versioned
section, commit, tag, publish a GitHub release, and push — in one
deterministic, operator-gated run. Works identically releasing AAI itself or
a downstream project that has the AAI layer deployed (its only inputs are the
repo root, its `CHANGELOG.md`, and its git/`gh` remote).

## Usage
```bash
/aai-release                        # plan-only (default-safe): prints the plan, changes nothing
/aai-release --dry-run              # same as bare invocation, explicit
/aai-release --version v1.2.3       # verbatim version (any scheme, incl. SemVer)
/aai-release --confirm              # THE CUT: roll + commit + tag (+ push + publish)
/aai-release --confirm --no-remote  # THE CUT, but skip push + gh release create
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
- `--no-remote` (env twin `AAI_RELEASE_NO_REMOTE=1`) — performs the full
  local cut (CHANGELOG rewrite, commit, annotated tag) but SKIPS `git push`
  and `gh release create`.

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
   matrix, the commit/tag, and — unless `--no-remote` — the push and GitHub
   release publish.

2. Relay the script's output as a SHORT report: resolved version, whether it
   was a plan or a cut, the tag name, and (on a cut) the commit SHA and
   whether push/publish ran or were skipped. Do not paste the full rollup
   preview verbatim unless the user asks for it.

3. If the script exits non-zero, report the cause plainly and stop — do not
   retry with different flags on the agent's own initiative:
   - exit 10 = not a git repository
   - exit 11 = no `CHANGELOG.md` at the repo root
   - exit 12 = malformed `[unreleased]` heading in `CHANGELOG.md` (fix the
     CHANGELOG by hand — the script never guesses at a malformed entry)
   - exit 13 = no rollable `[unreleased]` entries (absent or empty — nothing
     to release yet)
   - exit 14 = working tree is dirty (commit or stash first)
   - exit 15 = a tag for the resolved version already exists
   - exit 16 = `gh` absent or unauthenticated on the publish path (dry-run
     still works offline; pass `--no-remote` to skip publishing, or fix `gh
     auth login`)

## Safety
- NEVER pass `--confirm`/`--yes` on the agent's own initiative — publishing a
  release is an operator decision (mirrors the operator-only-merge boundary).
  Always run (or default to) `--dry-run` first and let the user review the
  plan before confirming.
- NEVER auto-publish. The script itself never pushes or calls `gh release
  create` under `--no-remote`/`AAI_RELEASE_NO_REMOTE=1`, and a bare/`--dry-run`
  invocation never writes anything at all.
- The CHANGELOG rewrite is line-surgical and idempotent — re-running after a
  successful cut with no new `[unreleased]` entries correctly REFUSES (there
  is nothing left to roll); that refusal is expected, not a bug.
