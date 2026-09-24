<#
.SYNOPSIS
  Install the AAI git hook SET: an opt-in pre-commit hook that auto-
  regenerates docs/INDEX.md whenever the commit touches docs/ (RFC-0001
  layer 4 convenience), and a reference-transaction hook, which refuses
  a refs/heads/main ref update unless AAI_GIT_WRITE=1 is set on that exact
  command (docs/specs/SPEC-0156-spec-agent-shell-can-write-the-shipping-repo.md).

.DESCRIPTION
  Both hooks are written to the EFFECTIVE hooks directory -- the one
  `git rev-parse --git-path hooks/<name>` resolves, which honours
  core.hooksPath and a linked worktree's shared git dir. It is usually
  .git/hooks, but never assume that.
  Idempotent per hook. Refuses to overwrite a non-AAI hook unless -Force is
  given (checked for BOTH hooks before writing either). A declared
  `ref_guard: declined` (docs/ai/docs-audit.yaml) is honoured by a plain
  install: the ref-guard hook is skipped, not silently re-armed. Override
  with -ArmRefGuard or -Force.

.PARAMETER Force
  Overwrite an existing hook that is not AAI-managed.

.PARAMETER Uninstall
  Remove the AAI-managed hooks. Leaves non-AAI hooks alone.

.PARAMETER Hooks
  Comma-separated selection over the closed set index, ref-guard, all
  (default all). Only the selected hook(s) are installed/uninstalled; a
  foreign file in an unselected slot never blocks the run (Spec-AC-01/02).

.PARAMETER DeclineRefGuard
  Remove an AAI-managed reference-transaction hook if present (refusing,
  unmodified, a foreign one) and record `ref_guard: declined` in
  docs/ai/docs-audit.yaml -- the same column-0 key the .sh twin writes, so
  one config file serves a repo checked out on either platform (Spec-AC-05,
  Amendment 1).

.PARAMETER ArmRefGuard
  (Re-)install the reference-transaction hook (same foreign-hook refusal as
  a normal install) and record `ref_guard: armed`.

.EXAMPLE
  .\.aai\scripts\install-pre-commit-hook.ps1

.EXAMPLE
  .\.aai\scripts\install-pre-commit-hook.ps1 -Uninstall

.EXAMPLE
  .\.aai\scripts\install-pre-commit-hook.ps1 -Hooks index

.EXAMPLE
  .\.aai\scripts\install-pre-commit-hook.ps1 -DeclineRefGuard
#>

[CmdletBinding()]
param(
  [switch]$Force,
  [switch]$Uninstall,
  [string]$Hooks = 'all',
  [switch]$DeclineRefGuard,
  [switch]$ArmRefGuard
)

$ErrorActionPreference = 'Stop'

# --Hooks <csv> over the closed set index/ref-guard/all (D6), mirroring the
# .sh twin's resolution: resolved once into the two booleans every
# selection-aware guard below consults. An unknown token exits 2 naming the
# closed set before any repo/hook state is touched.
$wantIndex = $false
$wantRefGuard = $false
foreach ($hooksTok in ($Hooks -split ',')) {
  switch ($hooksTok.Trim()) {
    'index' { $wantIndex = $true }
    'ref-guard' { $wantRefGuard = $true }
    'all' { $wantIndex = $true; $wantRefGuard = $true }
    default {
      # $ErrorActionPreference = 'Stop' makes Write-Error a TERMINATING error
      # that exits 1 before reaching an explicit `exit`, so the unknown-token
      # refusal below writes to stderr directly to keep the intended exit 2
      # (matching the .sh twin's closed-set refusal).
      [Console]::Error.WriteLine("Unknown -Hooks value: '$hooksTok' (closed set: index, ref-guard, all)")
      exit 2
    }
  }
}

$repoRoot = (& git rev-parse --show-toplevel 2>$null).Trim()
if (-not $repoRoot) {
  Write-Error "Not inside a git repository."
  exit 1
}

# Where git will ACTUALLY look for hooks.
#
# `git rev-parse --git-path hooks/<name>` is the resolution git itself performs
# to pick the file it executes, so it folds in BOTH things a hand-built path
# gets wrong: a linked worktree ships .git as a FILE, so a path built from
# --show-toplevel never exists there (PR #302 Codex P2); and `core.hooksPath`
# moves the hooks directory somewhere --git-common-dir knows nothing about
# (PR #304 Codex P1 -- that one shipped a false success: the installer wrote
# .git/hooks/reference-transaction, exited 0, and a marker-less commit still
# moved refs/heads/main because git ran the custom path instead).
# The result is relative to the CURRENT DIRECTORY, not the repo root, so a
# relative answer is resolved against the current location.
function Resolve-HookPath {
  param([Parameter(Mandatory = $true)][string]$Name)
  $p = & git rev-parse --git-path "hooks/$Name" 2>$null
  if ($p) { $p = ([string]$p).Trim() }
  if (-not $p) { return $null }
  if (-not [System.IO.Path]::IsPathRooted($p)) {
    $p = Join-Path (Get-Location).ProviderPath $p
  }
  return $p
}

# A path we cannot resolve is a path we cannot install into safely, and a guard
# installed somewhere git never looks is worse than no guard at all -- so this
# refuses loudly instead of exiting 0 on an inert hook.
$hookPath = Resolve-HookPath 'pre-commit'
if (-not $hookPath) {
  Write-Error "Could not resolve the effective git hooks path for pre-commit (git rev-parse --git-path failed). Refusing to install: a hook written to a guessed path would report success while git never runs it."
  exit 1
}
$reftxPath = Resolve-HookPath 'reference-transaction'
if (-not $reftxPath) {
  Write-Error "Could not resolve the effective git hooks path for reference-transaction (git rev-parse --git-path failed). Refusing to install: a guard written to a guessed path would report success while git never runs it."
  exit 1
}
$hooksDir   = Split-Path -Parent $reftxPath
$marker     = "# AAI:INDEX-AUTOGEN"
$reftxMarker = "# AAI:REF-GUARD"
# docs/ai/docs-audit.yaml -- the committed guard-policy surface (D2), the
# SAME file and the SAME column-0 `ref_guard: <value>` key the .sh twin
# reads/writes (Amendment 1: one config file must serve a repo checked out
# on either platform). Read by lib/guard-config.mjs's readRefGuardPolicy
# (the canonical JS reader); this script mirrors it with the identical
# grammar, never a node import (check-vendored-script-deps.mjs).
$configPath = Join-Path $repoRoot 'docs/ai/docs-audit.yaml'

# $reftxBody -- moved up from the normal install flow (below) so the early
# -DeclineRefGuard/-ArmRefGuard dispatch (also below) can install the SAME
# body Enable-RefGuard needs, without a second copy of the heredoc.
$reftxBody = @'
#!/bin/sh
# AAI:REF-GUARD -- refuses a refs/heads/main ref update unless AAI_GIT_WRITE=1.
# Installed by .aai/scripts/install-pre-commit-hook.ps1 (or the .sh twin).
# This is a git reference-transaction hook: it fires for EVERY ref update in
# this repository, from any process, at any nesting depth, through any
# subshell. See
# docs/specs/SPEC-0156-spec-agent-shell-can-write-the-shipping-repo.md.

aai_state="$1"

if [ "$aai_state" != "prepared" ]; then
  exit 0
fi

aai_guarded=0
while read -r aai_old aai_new aai_ref; do
  if [ "$aai_ref" = "refs/heads/main" ]; then
    aai_guarded=1
  fi
done

if [ "$aai_guarded" != "1" ]; then
  exit 0
fi

if [ "$AAI_GIT_WRITE" = "1" ]; then
  exit 0
fi

cat >&2 <<'AAI_REF_GUARD_MSG'
AAI:REF-GUARD refused this refs/heads/main update.
  Guard:  git reference-transaction hook, marker AAI:REF-GUARD.
  Reason: a write to refs/heads/main must be a deliberate, narrow exception,
          never an ambient default (agent-shell-can-write-the-shipping-repo).
  Fix:    re-run this ONE command with AAI_GIT_WRITE=1 set. PowerShell has no
          VAR=value command prefix, so scope it to a child process:
            pwsh -NoProfile -Command '$env:AAI_GIT_WRITE=1; git commit ...'
          From a POSIX shell on this machine:  AAI_GIT_WRITE=1 git commit ...
  Uninstall this guard: pwsh .aai/scripts/install-pre-commit-hook.ps1 -Uninstall
AAI_REF_GUARD_MSG
exit 1
'@

# Test-EffectiveHook -- re-ask git where it would look, and prove the file THERE
# is ours and runnable. This is the post-condition that makes the exit code
# mean something: exit 0 asserts "git will run this", not "a write succeeded
# somewhere". /aai-update reads that exit code as proof of protection.
function Test-EffectiveHook {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Marker
  )
  $p = Resolve-HookPath $Name
  if (-not $p) {
    Write-Host "ERROR: installed $Name but can no longer resolve the effective hooks path." -ForegroundColor Red
    return $false
  }
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
    Write-Host "ERROR: git resolves the $Name hook to $p, but no file is there." -ForegroundColor Red
    return $false
  }
  if (-not ((Get-Content $p -Raw) -match [regex]::Escape($Marker))) {
    Write-Host "ERROR: the $Name hook git would run ($p) does not carry $Marker." -ForegroundColor Red
    return $false
  }
  # Windows runs hooks through an interpreter regardless of mode bits; on POSIX
  # git silently skips a hook that is not executable (same carve as CAT-17).
  if ($IsLinux -or $IsMacOS) {
    & test -x $p
    if ($LASTEXITCODE -ne 0) {
      Write-Host "ERROR: the $Name hook git would run ($p) is not executable -- git skips it silently." -ForegroundColor Red
      return $false
    }
  }
  return $true
}

# Show-ForeignReftxRefusal -- the shared refusal text for a foreign
# (non-AAI) file occupying the reference-transaction slot: ONE function, not
# a second literal copy of the message. Mirrors the .sh twin's
# foreign_reftx_refusal() and the reason it exists as a function at all --
# a duplicate copy of a refusal string is exactly what broke TEST-612's
# mutation target on the .sh twin the first time it was written (a recorded
# --sed then hits whichever copy comes first and the row stops proving its
# property). Called from BOTH the normal selection-aware foreign check below
# and Enable-RefGuard.
function Show-ForeignReftxRefusal {
  Write-Error "$reftxPath already exists and is not AAI-managed. Pass -Force to overwrite."
}

# Read-RefGuardPolicy / Write-RefGuardPolicy -- the .ps1 twin of the .sh's
# read_ref_guard_policy / write_ref_guard_policy (Spec-AC-05/06, moved into
# this run's scope by Amendment 1): the IDENTICAL column-0 `ref_guard:
# <value>` key and the IDENTICAL fail-CLOSED grammar, so one
# docs/ai/docs-audit.yaml serves a repo checked out on either platform.
# 'declined' is recognized ONLY as a literal column-0 `ref_guard: declined`
# line; an absent file, an absent key, an indented/commented key, or any
# other value all read as 'armed' -- never silently disarm a safeguard on a
# typo (D3).
function Read-RefGuardPolicy {
  param([Parameter(Mandatory = $true)][string]$ConfigPath)
  if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    return 'armed'
  }
  foreach ($line in (Get-Content -LiteralPath $ConfigPath)) {
    if ($line -match '^ref_guard:\s*declined(\s|$)') {
      return 'declined'
    }
  }
  return 'armed'
}

# Write-RefGuardPolicy -- replace-or-append the column-0 `ref_guard: <value>`
# line, creating the file with only this key when it is absent, disturbing
# no other line. "Replace" is recognised ONLY via the same fail-CLOSED
# column-0 pattern Read-RefGuardPolicy uses, so a stray indented/commented/
# invalid line is never treated as the key to replace. Ends by reading the
# value back through Read-RefGuardPolicy and refusing if it disagrees -- the
# write is not trusted merely because it did not throw.
function Write-RefGuardPolicy {
  param(
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$Value
  )
  $dir = Split-Path -Parent $ConfigPath
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $existingLines = @()
  if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
    $existingLines = @(Get-Content -LiteralPath $ConfigPath)
  }
  $replaced = $false
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($line in $existingLines) {
    if ((-not $replaced) -and ($line -match '^ref_guard:\s*(armed|declined)(\s|$)')) {
      $out.Add("ref_guard: $Value")
      $replaced = $true
    } else {
      $out.Add($line)
    }
  }
  if (-not $replaced) {
    $out.Add("ref_guard: $Value")
  }
  Set-Content -LiteralPath $ConfigPath -Value $out
  $verify = Read-RefGuardPolicy -ConfigPath $ConfigPath
  if ($verify -ne $Value) {
    Write-Error "Wrote ref_guard: $Value to $ConfigPath but reading it back gives $verify."
    return $false
  }
  return $true
}

# Disable-RefGuard -- Spec-AC-05 (Amendment 1: .ps1 twin): remove an
# AAI-managed ref-guard hook if present, refuse (unmodified) a foreign one,
# and record ref_guard: declined.
function Disable-RefGuard {
  $reftxIsAai = $false
  if (Test-Path -LiteralPath $reftxPath -PathType Leaf) {
    $existing = Get-Content -LiteralPath $reftxPath -Raw
    if ($existing -match [regex]::Escape($reftxMarker)) { $reftxIsAai = $true }
  }
  if ((Test-Path -LiteralPath $reftxPath -PathType Leaf) -and (-not $reftxIsAai)) {
    Show-ForeignReftxRefusal
    Write-Host "Refusing to remove a foreign hook -- -DeclineRefGuard only removes an AAI-managed guard."
    return $false
  }
  if (Test-Path -LiteralPath $reftxPath -PathType Leaf) {
    Remove-Item -LiteralPath $reftxPath
    Write-Host "Uninstalled AAI reference-transaction hook (AAI:REF-GUARD) from $reftxPath"
  }
  if (-not (Write-RefGuardPolicy -ConfigPath $configPath -Value 'declined')) {
    return $false
  }
  Write-Host "Declined the AAI reference-transaction guard. Recorded ref_guard: declined in $configPath"
  Write-Host "Re-arm with: pwsh $repoRoot/.aai/scripts/install-pre-commit-hook.ps1 -ArmRefGuard"
  return $true
}

# Enable-RefGuard -- Spec-AC-05 (Amendment 1: .ps1 twin): (re-)install the
# ref-guard hook (same foreign-hook refusal as the normal write path) and
# record ref_guard: armed.
function Enable-RefGuard {
  if ((Test-Path -LiteralPath $reftxPath -PathType Leaf) -and (-not $Force)) {
    $existing = Get-Content -LiteralPath $reftxPath -Raw
    if (-not ($existing -match [regex]::Escape($reftxMarker))) {
      Show-ForeignReftxRefusal
      return $false
    }
  }
  Set-Content -Path $reftxPath -Value $reftxBody -NoNewline
  if ($IsLinux -or $IsMacOS) {
    & chmod +x $reftxPath | Out-Null
  }
  if (-not (Test-EffectiveHook -Name 'reference-transaction' -Marker $reftxMarker)) {
    return $false
  }
  if (-not (Write-RefGuardPolicy -ConfigPath $configPath -Value 'armed')) {
    return $false
  }
  Write-Host "Recorded ref_guard: armed in $configPath"
  return $true
}

# -DeclineRefGuard / -ArmRefGuard are single-purpose actions on the ref-guard
# hook alone: dispatched here (after path resolution, before the
# -Hooks-selected install/uninstall flow below) and exit before reaching it
# -- mirrors the .sh twin's dispatch ordering exactly.
if ($DeclineRefGuard -and $ArmRefGuard) {
  [Console]::Error.WriteLine("-DeclineRefGuard and -ArmRefGuard are contradictory.")
  exit 2
}
if ($DeclineRefGuard) {
  if (-not (Disable-RefGuard)) { exit 1 }
  exit 0
}
if ($ArmRefGuard) {
  if (-not (Enable-RefGuard)) { exit 1 }
  exit 0
}

if ($Uninstall) {
  if ($wantIndex) {
    if ((Test-Path $hookPath) -and ((Get-Content $hookPath -Raw) -match [regex]::Escape($marker))) {
      Remove-Item $hookPath
      Write-Host "Uninstalled AAI pre-commit hook from $hookPath"
    } else {
      Write-Host "No AAI pre-commit hook found (or hook is not AAI-managed). No action taken."
    }
  }
  if ($wantRefGuard) {
    if ((Test-Path $reftxPath) -and ((Get-Content $reftxPath -Raw) -match [regex]::Escape($reftxMarker))) {
      Remove-Item $reftxPath
      Write-Host "Uninstalled AAI reference-transaction hook (AAI:REF-GUARD) from $reftxPath"
    } else {
      Write-Host "No AAI reference-transaction hook found (or hook is not AAI-managed). No action taken."
    }
  }
  exit 0
}

# Selection-aware (Spec-AC-02): a foreign file in a slot this run was NOT
# asked to touch is not a reason to refuse.
$foreign = $false
if ($wantIndex -and (Test-Path $hookPath) -and (-not $Force)) {
  $existing = Get-Content $hookPath -Raw
  if (-not ($existing -match [regex]::Escape($marker))) {
    Write-Error "$hookPath already exists and is not AAI-managed. Pass -Force to overwrite."
    $foreign = $true
  }
}
if ($wantRefGuard -and (Test-Path $reftxPath) -and (-not $Force)) {
  $existingReftx = Get-Content $reftxPath -Raw
  if (-not ($existingReftx -match [regex]::Escape($reftxMarker))) {
    Show-ForeignReftxRefusal
    $foreign = $true
  }
}
if ($foreign) {
  exit 1
}

if ((Test-Path -LiteralPath $hooksDir) -and -not (Test-Path -LiteralPath $hooksDir -PathType Container)) {
  Write-Error "The effective git hooks path $hooksDir exists and is not a directory. Refusing to install rather than reporting success on a guard git cannot run."
  exit 1
}
New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null

$skipPreCommit = $false
if ($wantIndex -and (Test-Path $hookPath) -and (-not $Force)) {
  $existing = Get-Content $hookPath -Raw
  if ($existing -match [regex]::Escape($marker)) {
    Write-Host "AAI pre-commit hook already installed at $hookPath. No action taken."
    $skipPreCommit = $true
  }
}

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
# NOTE (CHANGE-0009 D8): the grep below is a deliberate THIN mirror of the guard
# dial; the CANONICAL reader of docs-audit.yaml is .aai/scripts/lib/guard-config.mjs
# (a conformance test asserts the grep pattern and the reader agree on fixtures).
if [[ -f .aai/scripts/docs-audit.mjs ]]; then
  # SPEC-0013 W1 (SPEC-0011-F2 class): the gate MODE must come from the config
  # that is actually being committed — the STAGED blob when docs-audit.yaml is
  # staged, else HEAD — never the worktree copy, whose UNSTAGED edit could
  # silently downgrade enforce -> warn. The worktree copy is the last resort
  # only when the config exists in neither the index nor HEAD (fresh repo).
  GATE_CFG="$(git show :docs/ai/docs-audit.yaml 2>/dev/null \
    || git show HEAD:docs/ai/docs-audit.yaml 2>/dev/null \
    || cat docs/ai/docs-audit.yaml 2>/dev/null \
    || true)"
  CLOSE_GATE_MODE="report-only"
  if printf '%s\n' "$GATE_CFG" | grep -Eq '^close_gate:[[:space:]]*enforce([[:space:]]|$)'; then
    CLOSE_GATE_MODE="enforce"
  fi
  CLOSE_GATE_FAILED=0
  STAGED_SPECS="$(git diff --cached --name-only --diff-filter=ACM | grep -E '^docs/specs/.*\.md$' || true)"
  # SPEC-0013 W2: newline-safe iteration — an unquoted `for` word-splits paths
  # with spaces into nonexistent fragments whose failed `git show` silently
  # SKIPS the gate (the worst failure shape for a gate).
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    # only when the STAGED diff ADDS a 'status: done' line (not an already-done spec)
    if git diff --cached -U0 -- "$f" | grep -Eq '^\+status:[[:space:]]*done([[:space:]]|$)'; then
      # Gate the STAGED content, not the worktree: materialize the staged blob so a
      # staged-but-unreconciled done cannot pass merely because the worktree carries
      # unstaged Evidence (SPEC-0011 G5). Read the id from the staged blob too.
      STAGED_TMP="$(mktemp)"
      if ! git show ":$f" > "$STAGED_TMP" 2>/dev/null; then
        rm -f "$STAGED_TMP"
        continue
      fi
      gid="$(sed -n 's/^id:[[:space:]]*//p' "$STAGED_TMP" | head -1)"
      if [[ -z "$gid" ]]; then
        gid="$(basename "$f" .md | grep -oE '^[A-Z]+(-[A-Z]+)*-[0-9]+' || true)"
      fi
      if [[ -z "$gid" ]]; then
        rm -f "$STAGED_TMP"
        continue
      fi
      if GATE_OUT="$(node .aai/scripts/docs-audit.mjs --gate-file "$STAGED_TMP" 2>&1)"; then
        :
      elif [[ "$CLOSE_GATE_MODE" == "enforce" ]]; then
        echo "AAI:INDEX-AUTOGEN close-gate: $gid fails the close gate (close_gate: enforce) — commit aborted." >&2
        echo "$GATE_OUT" >&2
        CLOSE_GATE_FAILED=1
      else
        echo "AAI:INDEX-AUTOGEN close-gate WARNING: $gid fails the close gate (report-only; commit allowed)." >&2
        echo "$GATE_OUT" >&2
      fi
      rm -f "$STAGED_TMP"
    fi
  done <<< "$STAGED_SPECS"
  if [[ "$CLOSE_GATE_FAILED" == 1 ]]; then
    exit 1
  fi
fi

# AAI:INDEX-AUTOGEN body-lint (SPEC-0013 H1): for each STAGED governed docs/**/*.md
# file, materialize the STAGED blob (git show ":$f" — LEARNED 2026-07-03: gate what
# is being committed, never the worktree copy) and body-lint it via
# docs-audit.mjs --lint-body-file. Block the commit only when docs/ai/docs-audit.yaml
# sets body_lint: enforce; otherwise warn and continue (report-only default,
# mirroring close_gate). Non-governed dirs (ai, knowledge, archive, _archive,
# project-sessions, templates, plans) and generated INDEX files are skipped.
if [[ -f .aai/scripts/docs-audit.mjs ]]; then
  # SPEC-0013 W1: same staged/HEAD-first config read as the close-gate block —
  # an unstaged worktree edit must not downgrade enforce -> warn.
  GATE_CFG="$(git show :docs/ai/docs-audit.yaml 2>/dev/null \
    || git show HEAD:docs/ai/docs-audit.yaml 2>/dev/null \
    || cat docs/ai/docs-audit.yaml 2>/dev/null \
    || true)"
  BODY_LINT_MODE="report-only"
  if printf '%s\n' "$GATE_CFG" | grep -Eq '^body_lint:[[:space:]]*enforce([[:space:]]|$)'; then
    BODY_LINT_MODE="enforce"
  fi
  BODY_LINT_FAILED=0
  STAGED_GOVERNED_DOCS="$(git diff --cached --name-only --diff-filter=ACM \
    | grep -E '^docs/.*\.md$' \
    | grep -Ev '^docs/(ai|knowledge|archive|_archive|project-sessions|templates|plans)/' \
    | grep -Ev '^docs/INDEX' || true)"
  # SPEC-0013 W2: newline-safe iteration (see the close-gate loop above).
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    STAGED_TMP="$(mktemp)"
    if ! git show ":$f" > "$STAGED_TMP" 2>/dev/null; then
      rm -f "$STAGED_TMP"
      continue
    fi
    if LINT_OUT="$(node .aai/scripts/docs-audit.mjs --lint-body-file "$STAGED_TMP" 2>&1)"; then
      :
    elif [[ "$BODY_LINT_MODE" == "enforce" ]]; then
      echo "AAI:INDEX-AUTOGEN body-lint: $f fails body lint (body_lint: enforce) — commit aborted." >&2
      echo "$LINT_OUT" >&2
      BODY_LINT_FAILED=1
    else
      echo "AAI:INDEX-AUTOGEN body-lint WARNING: $f fails body lint (report-only; commit allowed)." >&2
      echo "$LINT_OUT" >&2
    fi
    rm -f "$STAGED_TMP"
  done <<< "$STAGED_GOVERNED_DOCS"
  if [[ "$BODY_LINT_FAILED" == 1 ]]; then
    exit 1
  fi
fi
echo "AAI:INDEX-AUTOGEN: regenerated and staged docs/INDEX.md"
'@

if ($wantIndex) {
  if (-not $skipPreCommit) {
    Set-Content -Path $hookPath -Value $hookBody -NoNewline
    if ($IsLinux -or $IsMacOS) {
      & chmod +x $hookPath | Out-Null
    }
    Write-Host "Installed AAI pre-commit hook at $hookPath"
    Write-Host "Effect: on every commit that touches docs/, regenerate docs/INDEX.md and stage it."
  }
}

# N1 (validation round 1, mirrors the .sh twin): a declared decline must
# survive a plain re-install -- the shape SKILL_UPDATE step 4 runs on every
# successful sync, with no flags. -ArmRefGuard (dispatched above, before this
# whole -Hooks flow, and never consulting the policy) and -Force (whose
# existing contract is already "proceed past a protective refusal in this
# slot") stay the two explicit overrides.
if ($wantRefGuard -and (-not $Force) -and ((Read-RefGuardPolicy -ConfigPath $configPath) -eq 'declined')) {
  Write-Host "Skipped AAI reference-transaction hook (AAI:REF-GUARD): $configPath declares ref_guard: declined."
  Write-Host "Re-arm with: pwsh $repoRoot/.aai/scripts/install-pre-commit-hook.ps1 -ArmRefGuard (or pass -Force)."
  $wantRefGuard = $false
}

$skipReftx = $false
if ($wantRefGuard -and (Test-Path $reftxPath) -and (-not $Force)) {
  $existingReftx = Get-Content $reftxPath -Raw
  if ($existingReftx -match [regex]::Escape($reftxMarker)) {
    Write-Host "AAI reference-transaction hook already installed at $reftxPath. No action taken."
    $skipReftx = $true
  }
}

if ($wantRefGuard) {
  if (-not $skipReftx) {
    Set-Content -Path $reftxPath -Value $reftxBody -NoNewline
    if ($IsLinux -or $IsMacOS) {
      & chmod +x $reftxPath | Out-Null
    }
    Write-Host "Installed AAI reference-transaction hook (AAI:REF-GUARD) at $reftxPath"
    Write-Host "Effect: a refs/heads/main update is refused unless AAI_GIT_WRITE=1 is set on that command."
  }
}

# Post-condition (PR #304 Codex P1) -- see Test-EffectiveHook. Selection-aware
# (Spec-AC-02): attestation covers exactly the SELECTED set, mirroring the
# .sh twin.
$attestOk = $true
if ($wantIndex -and -not (Test-EffectiveHook -Name 'pre-commit' -Marker $marker)) { $attestOk = $false }
if ($wantRefGuard -and -not (Test-EffectiveHook -Name 'reference-transaction' -Marker $reftxMarker)) { $attestOk = $false }
if (-not $attestOk) {
  Write-Error "Installation did NOT leave an active hook at the path git resolves. Check 'git config core.hooksPath' and 'git rev-parse --git-path hooks/reference-transaction'."
  exit 1
}

Write-Host "Uninstall with: pwsh .aai/scripts/install-pre-commit-hook.ps1 -Uninstall"
