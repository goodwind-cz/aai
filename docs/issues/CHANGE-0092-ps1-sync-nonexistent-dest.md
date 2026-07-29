---
id: ps1-sync-nonexistent-dest
number: 92
type: change
status: done
user_visible: false
links:
  pr:
    - 195
  commits:
    - 7c02e5bd9333d47613c8c045a3da4924e4324b73
---

# Change — fix: Windows PowerShell 5.1 install fails copying .codex/.gemini skills

## Summary
- A real field install on Windows failed: `irm .../install.ps1 | iex` aborted with
  `Copy-Item : ... C:\...\.codex\skills nebyla nalezena` /
  `DirectoryNotFoundException` at `aai-sync.ps1` `Copy-Replace`
  (`Copy-Item $Src $Dst -Recurse -Force`).
- Root cause: **Windows PowerShell 5.1**'s `Copy-Item -Recurse <dir>
  <nonexistent-dst>` does not reliably create the destination ROOT before
  copying a top-level file into it. `.codex/skills` and `.gemini/skills` carry a
  top-level `README.md` ALONGSIDE skill subfolders; `Copy-Replace` removes the
  destination then recursively copies, so 5.1 throws on the loose README.md.
  PowerShell 7 and the bash installer (`cp -a`) are unaffected — which is why
  Linux CI, the self-hosting smoke, and the 5.1 PARSE-check all passed while a
  real 5.1 install broke.
- `.claude/skills` never hit this because it is copied entry-by-entry into a
  pre-created, non-removed parent.

## Fix
- `Copy-Replace` (aai-sync.ps1): for a directory source, create the destination
  root FIRST (`New-Item -ItemType Directory -Force`), then copy the CONTENTS
  (`Get-ChildItem -Force` → `Copy-Item -LiteralPath ... -Recurse`). Version-safe
  (works on 5.1 and 7); empty-dir safe; file sources copy directly.
- Regression guard: the `windows-5_1` job in `.github/workflows/ps1-quality.yml`
  now runs a FUNCTIONAL `aai-sync.ps1` smoke into a fresh target on real Windows
  PowerShell 5.1 and asserts `.codex/skills` + `.gemini/skills` are fully
  populated (README + nested SKILL.md). A parse-check could never catch this
  runtime behavior.

## Acceptance Criteria
- AC-001: on Windows PowerShell 5.1, a fresh `aai-sync.ps1 -Profile extended`
  into a new target populates `.codex/skills/README.md`,
  `.gemini/skills/README.md`, and the nested per-skill SKILL.md files without a
  DirectoryNotFoundException (CI-verified by the new functional smoke on
  windows-latest / shell: powershell).
- AC-002: no regression on PowerShell 7 / bash — the extended and core sync
  still produce the identical target layer (ps1-quality gate green; existing
  sync behavior unchanged for directories without loose top-level files).
- AC-003: Copy-Replace remains correct for file sources and empty directories.

## Verification
- CI: ps1-quality windows-5_1 functional sync smoke (the environment that broke);
  ps1-quality Linux gate (PSScriptAnalyzer 5.1/7.0 compat + Pester); local
  pwsh7 end-to-end sync into a temp target (README + 30 nested SKILL.md + gemini,
  verified before commit).

## Constraints / Risks
- Ceremony L2. Windows-only runtime behavior; the definitive proof is the new
  functional smoke on the real 5.1 runner (pwsh7/bash cannot reproduce the bug,
  so a green pwsh7 run is necessary but not sufficient — the windows-5_1 job is
  the authoritative gate).

## Notes
- Discovered from a live owner install log (2026-07-29). Fix is surgical to
  Copy-Replace; no behavior change on the already-working platforms.
