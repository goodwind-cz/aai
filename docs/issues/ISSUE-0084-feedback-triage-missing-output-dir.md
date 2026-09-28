---
id: feedback-triage-missing-output-dir
type: issue
number: 84
status: draft
links:
  pr: []
  commits: []
---

# Issue — Feedback triage fails with ENOENT when docs/ai/friction does not exist

## Summary
- `node .aai/scripts/aai-feedback-triage.mjs` writes `docs/ai/friction/triage-report.json` via `writeFileSync` without creating the parent directory.
- In a project that has never captured friction (no `docs/ai/friction`), the command exits with `ENOENT` instead of writing a local empty report.
- Documented behavior is that missing configuration or an empty spool is not an error; a local report is still produced.

## Type
- bug

## Impact
- Who/what is affected: first-run `/aai-feedback-triage` in a clean vendored project, and any operator following USER_GUIDE / skill docs that say missing config or an empty spool is fine.
- Severity/priority: medium — blocks the offline triage skill until a human mkdir; workaround is one command.

## Current Behavior
- `.aai/scripts/aai-feedback-triage.mjs` imports `writeFileSync` only (no `mkdirSync`) and writes `args.out` after building the report.
- Default output path is `docs/ai/friction/triage-report.json`.
- Observed on Windows, project without `docs/ai/friction`:

```text
Error: ENOENT: no such file or directory,
open '...\docs\ai\friction\triage-report.json'
```

- Workaround: `New-Item -ItemType Directory -Path 'docs/ai/friction' -Force` then re-run; stdout then `triaged 0 observation(s): 0 kept, 0 cluster(s)`.
- CHANGE-0048 (`feedback-triage-offline`) AC-008 covers malformed `feedback.yaml` failing closed to local mode. It does not require creating the output directory. The help text still promises a LOCAL report write.

## Expected Behavior
- Before writing the report, the engine creates the parent directory of `--out` (`mkdirSync(dirname(outputPath), { recursive: true })`).
- A clean project with no `docs/ai/friction` and no spool still exits 0 and writes a local report (zero observations, zero clusters).
- Missing/invalid config remains non-fatal (existing CHANGE-0048 contract).

## Steps to Reproduce (if applicable)
1. In a project without `docs/ai/friction` (or point `--out` at a path whose parent does not exist).
2. Run `node .aai/scripts/aai-feedback-triage.mjs`.
3. Observe `ENOENT` on `triage-report.json` and a non-zero exit.

## Verification
- Fixture: empty project / missing `docs/ai/friction` / missing spool -> exit 0, report file created, summary line names 0 observations.
- Existing `tests/skills/test-aai-feedback-triage.sh` stays green.
- No network I/O (existing offline invariant).

## Constraints / Risks
- Known risks or constraints: do not start creating a tracked `docs/ai/friction/` tree in the shipping repo; the directory is gitignored except where a `.gitkeep` already exists. Creating it at runtime is the intended fix. No secret is involved.
- Secrets preflight results (if any secret referenced): none — no local secret is referenced.

## Notes
- Source: local Windows usage report 2026-09-24 (`internal/windows-usage-report.md` in the project store). Not previously filed upstream.
- Related done work that does **not** close this: CHANGE-0048 (`feedback-triage-offline`).
- Assumption: creating only the `--out` parent is enough; the spool path may stay absent and read as empty (existing `readSpoolRows` degrade).
