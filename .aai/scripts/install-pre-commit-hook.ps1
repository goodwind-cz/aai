<#
.SYNOPSIS
  Install an opt-in .git/hooks/pre-commit that auto-regenerates docs/INDEX.md
  whenever the commit touches docs/. RFC-0001 layer 4 convenience.

.DESCRIPTION
  Idempotent. Refuses to overwrite a non-AAI hook unless -Force is given.

.PARAMETER Force
  Overwrite an existing hook that is not AAI-managed.

.PARAMETER Uninstall
  Remove the AAI-managed hook. Leaves non-AAI hooks alone.

.EXAMPLE
  .\.aai\scripts\install-pre-commit-hook.ps1

.EXAMPLE
  .\.aai\scripts\install-pre-commit-hook.ps1 -Uninstall
#>

[CmdletBinding()]
param(
  [switch]$Force,
  [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$repoRoot = (& git rev-parse --show-toplevel 2>$null).Trim()
if (-not $repoRoot) {
  Write-Error "Not inside a git repository."
  exit 1
}

$hookPath = Join-Path $repoRoot ".git/hooks/pre-commit"
$marker   = "# AAI:INDEX-AUTOGEN"

if ($Uninstall) {
  if ((Test-Path $hookPath) -and ((Get-Content $hookPath -Raw) -match [regex]::Escape($marker))) {
    Remove-Item $hookPath
    Write-Host "Uninstalled AAI pre-commit hook from $hookPath"
  } else {
    Write-Host "No AAI pre-commit hook found (or hook is not AAI-managed). No action taken."
  }
  exit 0
}

if ((Test-Path $hookPath) -and (-not $Force)) {
  $existing = Get-Content $hookPath -Raw
  if ($existing -match [regex]::Escape($marker)) {
    Write-Host "AAI pre-commit hook already installed at $hookPath. No action taken."
    exit 0
  }
  Write-Error "$hookPath already exists and is not AAI-managed. Pass -Force to overwrite."
  exit 1
}

New-Item -ItemType Directory -Force -Path (Join-Path $repoRoot ".git/hooks") | Out-Null

$hookBody = @'
#!/usr/bin/env bash
# AAI:INDEX-AUTOGEN - auto-regenerate docs/INDEX.md on docs/ changes.
# Installed by .aai/scripts/install-pre-commit-hook.ps1
set -euo pipefail

if ! command -v node >/dev/null 2>&1; then
  exit 0
fi

if ! git diff --cached --name-only | grep -qE '^docs/'; then
  exit 0
fi

GEN=".aai/scripts/generate-docs-index.mjs"
if [[ ! -f "$GEN" ]]; then
  exit 0
fi

if ! node "$GEN"; then
  echo "AAI:INDEX-AUTOGEN: generator failed; commit aborted." >&2
  exit 1
fi

git add docs/INDEX.md
# Companion violations report is created when docs are malformed, removed when clean.
if [[ -f docs/INDEX.violations.md ]]; then
  git add docs/INDEX.violations.md
else
  git rm --cached --quiet --ignore-unmatch docs/INDEX.violations.md
fi
# SPEC-0010 / ISSUE-0003: docs/INDEX.audit.md carries git-history-dependent
# Orphans + Drift sections; it is git-ignored and must NEVER be staged (staging it
# would reintroduce the committed-index non-idempotence). Belt-and-suspenders un-stage.
git rm --cached --quiet --ignore-unmatch docs/INDEX.audit.md

# AAI:INDEX-AUTOGEN close-gate (SPEC-0011 G5): for each staged spec whose diff ADDS
# a 'status: done' frontmatter line, run the offline close gate. Block the commit
# only when docs/ai/docs-audit.yaml sets close_gate: enforce; otherwise warn and
# continue (report-only default — absent config or close_gate: report-only never blocks).
if [[ -f .aai/scripts/docs-audit.mjs ]]; then
  CLOSE_GATE_MODE="report-only"
  if [[ -f docs/ai/docs-audit.yaml ]] && grep -Eq '^[[:space:]]*close_gate:[[:space:]]*enforce([[:space:]]|$)' docs/ai/docs-audit.yaml; then
    CLOSE_GATE_MODE="enforce"
  fi
  CLOSE_GATE_FAILED=0
  STAGED_SPECS="$(git diff --cached --name-only --diff-filter=ACM | grep -E '^docs/specs/.*\.md$' || true)"
  for f in $STAGED_SPECS; do
    # only when the STAGED diff ADDS a 'status: done' line (not an already-done spec)
    if git diff --cached -U0 -- "$f" | grep -Eq '^\+status:[[:space:]]*done([[:space:]]|$)'; then
      gid="$(sed -n 's/^id:[[:space:]]*//p' "$f" | head -1)"
      if [[ -z "$gid" ]]; then
        gid="$(basename "$f" .md | grep -oE '^[A-Z]+(-[A-Z]+)*-[0-9]+' || true)"
      fi
      [[ -z "$gid" ]] && continue
      if GATE_OUT="$(node .aai/scripts/docs-audit.mjs --gate "$gid" 2>&1)"; then
        :
      elif [[ "$CLOSE_GATE_MODE" == "enforce" ]]; then
        echo "AAI:INDEX-AUTOGEN close-gate: $gid fails the close gate (close_gate: enforce) — commit aborted." >&2
        echo "$GATE_OUT" >&2
        CLOSE_GATE_FAILED=1
      else
        echo "AAI:INDEX-AUTOGEN close-gate WARNING: $gid fails the close gate (report-only; commit allowed)." >&2
        echo "$GATE_OUT" >&2
      fi
    fi
  done
  if [[ "$CLOSE_GATE_FAILED" == 1 ]]; then
    exit 1
  fi
fi
echo "AAI:INDEX-AUTOGEN: regenerated and staged docs/INDEX.md"
'@

Set-Content -Path $hookPath -Value $hookBody -NoNewline

if ($IsLinux -or $IsMacOS) {
  & chmod +x $hookPath | Out-Null
}

Write-Host "Installed AAI pre-commit hook at $hookPath"
Write-Host "Effect: on every commit that touches docs/, regenerate docs/INDEX.md and stage it."
Write-Host "Uninstall with: pwsh .aai/scripts/install-pre-commit-hook.ps1 -Uninstall"
