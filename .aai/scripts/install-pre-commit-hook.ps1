<#
.SYNOPSIS
  Install the AAI git hook SET: a pre-commit hook (token index, marker
  AAI:INDEX-AUTOGEN) whose first lines are a marker-scoped AAI:GUARD-CHECKS
  block running .aai/scripts/pre-commit-checks.sh on every commit and which
  auto-regenerates docs/INDEX.md whenever the commit touches docs/
  (RFC-0001 layer 4 convenience); a reference-transaction hook (token
  ref-guard, marker AAI:REF-GUARD), which refuses a refs/heads/main ref
  update unless AAI_GIT_WRITE=1 is set on that exact command
  (docs/specs/SPEC-0156-spec-agent-shell-can-write-the-shipping-repo.md);
  and a pre-push hook (token close-gate, marker AAI:CLOSE-GATE) running
  .aai/scripts/close-reconcile.mjs --check over every pushed range
  (docs/specs/SPEC-0201-spec-shipped-guards-have-no-downstream-trigger.md).

.DESCRIPTION
  Every hook is written to the EFFECTIVE hooks directory -- the one
  `git rev-parse --git-path hooks/<name>` resolves, which honours
  core.hooksPath and a linked worktree's shared git dir. It is usually
  .git/hooks, but never assume that.
  Idempotent per hook. Refuses to overwrite a non-AAI hook unless -Force is
  given (checked for EVERY selected slot before writing any). A declared
  `ref_guard: declined` (docs/ai/docs-audit.yaml) is honoured by a plain
  install: the ref-guard hook is skipped, not silently re-armed. Override
  with -ArmRefGuard or -Force. An AAI pre-commit hook installed before the
  guard block existed is UPGRADED in place: the block is inserted after the
  shebang line and every other byte is left as it was; a hook this script
  cannot prove it owns (no AAI marker, a symlinked slot, a CR-terminated
  first line, more than one guard block) is refused by name and left
  byte-identical. The bash hook bodies are the same bytes the .sh twin
  writes (git runs hooks under its own sh on Windows); `bash
  .aai/scripts/install-pre-commit-hook.sh --print guard-checks|pre-push`
  emits them for a manual merge into a foreign hook.

.PARAMETER Force
  Overwrite an existing hook that is not AAI-managed.

.PARAMETER Uninstall
  Remove the AAI-managed hooks. Leaves non-AAI hooks alone.

.PARAMETER Hooks
  Comma-separated selection over the closed set index, ref-guard,
  close-gate, all (default all). Only the selected hook(s) are
  installed/uninstalled; a foreign file in an unselected slot never blocks
  the run (Spec-AC-01/02).

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

# -Hooks is contradictory with -DeclineRefGuard/-ArmRefGuard (frozen
# Implementation plan edge case; code review 20260924T124304Z D-1; mirrors
# the .sh twin's check above its own -Hooks resolution). Both single-purpose
# actions dispatch-and-exit before the -Hooks-selected flow below is ever
# reached, so an EXPLICIT -Hooks on the same command line can never do
# anything -- exit 2 naming the contradiction. $PSBoundParameters, not
# $Hooks -ne 'all', so a bare -DeclineRefGuard (the 'all' default,
# unconsulted) is unaffected. TEST-645.
$hooksExplicit = $PSBoundParameters.ContainsKey('Hooks')
if (($DeclineRefGuard -or $ArmRefGuard) -and $hooksExplicit) {
  [Console]::Error.WriteLine("-Hooks is contradictory with -DeclineRefGuard/-ArmRefGuard (these act on the reference-transaction hook alone).")
  exit 2
}

# --Hooks <csv> over the closed set index/ref-guard/all (D6), mirroring the
# .sh twin's resolution: resolved once into the two booleans every
# selection-aware guard below consults. An unknown token exits 2 naming the
# closed set before any repo/hook state is touched.
$wantIndex = $false
$wantRefGuard = $false
$wantCloseGate = $false
foreach ($hooksTok in ($Hooks -split ',')) {
  switch ($hooksTok.Trim()) {
    'index' { $wantIndex = $true }
    'ref-guard' { $wantRefGuard = $true }
    'close-gate' { $wantCloseGate = $true }
    'all' { $wantIndex = $true; $wantRefGuard = $true; $wantCloseGate = $true }
    default {
      # $ErrorActionPreference = 'Stop' makes Write-Error a TERMINATING error
      # that exits 1 before reaching an explicit `exit`, so the unknown-token
      # refusal below writes to stderr directly to keep the intended exit 2
      # (matching the .sh twin's closed-set refusal).
      [Console]::Error.WriteLine("Unknown -Hooks value: '$hooksTok' (closed set: index, ref-guard, close-gate, all)")
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
$prePushPath = Resolve-HookPath 'pre-push'
if (-not $prePushPath) {
  Write-Error "Could not resolve the effective git hooks path for pre-push (git rev-parse --git-path failed). Refusing to install: a guard written to a guessed path would report success while git never runs it."
  exit 1
}
$hooksDir   = Split-Path -Parent $reftxPath
$marker     = "# AAI:INDEX-AUTOGEN"
$reftxMarker = "# AAI:REF-GUARD"
$prePushMarker = "# AAI:CLOSE-GATE"
$guardBlockBegin = "# AAI:GUARD-CHECKS BEGIN"
$guardBlockEnd = "# AAI:GUARD-CHECKS END"

# The four hook bodies are plain files in .aai/templates/git-hooks/, resolved
# from THIS script's own location (never from the target repository) and shared
# with the .sh twin, so both installers write the same bytes from one copy.
$templateDir = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'templates') 'git-hooks'

# Get-TemplateBytes -- a template's bytes with every CR removed, so a template
# that arrives with CRLF line endings still yields an LF-only hook (git runs
# hooks under sh).
function Get-TemplateBytes {
  param([Parameter(Mandatory = $true)][string]$Name)
  $b = [System.IO.File]::ReadAllBytes((Join-Path $templateDir $Name))
  $b = $b -ne 13
  return ,[byte[]]$b
}

# Test-HookTemplates -- refuse, naming each missing file, before any write.
# [Console]::Error.WriteLine, never Write-Error (which terminates before the
# explicit exit and so changes the exit code).
function Test-HookTemplates {
  param([Parameter(Mandatory = $true)][string[]]$Names)
  $ok = $true
  foreach ($n in $Names) {
    $tp = Join-Path $templateDir $n
    if (-not (Test-Path -LiteralPath $tp -PathType Leaf)) {
      [Console]::Error.WriteLine("ERROR: AAI hook template missing: $tp")
      $ok = $false
    }
  }
  return $ok
}

# Write-BytesViaTemp -- write bytes to a temp sibling and rename over the
# target, so a failed write can never truncate what was there.
function Write-BytesViaTemp {
  param([string]$Path, [byte[]]$Bytes)
  if (Test-Path -LiteralPath $Path -PathType Container) {
    throw "$Path is a directory, not a regular file. Nothing was written."
  }
  $tmp = "$Path.aai-tmp.$PID"
  [System.IO.File]::WriteAllBytes($tmp, $Bytes)
  Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# Set-HookExecutable -- set the executable bit where the platform has one.
function Set-HookExecutable {
  param([string]$Path)
  if ($IsLinux -or $IsMacOS) { & chmod +x $Path | Out-Null }
}

# Find-MarkerLines -- the byte spans of every line that carries $Marker,
# found on the file's BYTES, never on decoded text: Get-Content transcodes a
# UTF-16 file into readable text and re-encodes a Latin-1 one into U+FFFD,
# so a marker found that way says nothing about the bytes on disk
# (validation B2 / NB2). Each span is @{ Start; End; Next; Line }: the
# line's first byte, the byte after its last content byte (its LF, or EOF),
# the first byte of the following line, and its 1-based line number.
# -Exact: the line is the marker and nothing else (the GUARD-CHECKS markers;
# the .sh twin's grep -cxF). Otherwise the marker must OPEN the line --
# column 0, followed by a space, LF, CR or EOF -- the shape every shipped
# body carries (the .sh twin's has_marker_line): a foreign hook that merely
# mentions a marker in a comment, or quotes it in a string, is not owned.
function Find-MarkerLines {
  param([byte[]]$Bytes, [string]$Marker, [switch]$Exact)
  $m = [System.Text.Encoding]::ASCII.GetBytes($Marker)
  $spans = New-Object System.Collections.Generic.List[object]
  $n = $Bytes.Length
  $start = 0
  $lineNo = 0
  while ($start -lt $n) {
    $lineNo++
    $nl = [Array]::IndexOf($Bytes, [byte]10, $start)
    $end = if ($nl -lt 0) { $n } else { $nl }
    $len = $end - $start
    $hit = $false
    if ($len -ge $m.Length) {
      $hit = $true
      for ($i = 0; $i -lt $m.Length; $i++) {
        if ($Bytes[$start + $i] -ne $m[$i]) { $hit = $false; break }
      }
      if ($hit) {
        if ($Exact) {
          $hit = ($len -eq $m.Length)
        } elseif ($len -gt $m.Length) {
          $after = $Bytes[$start + $m.Length]
          $hit = ($after -eq 32 -or $after -eq 13)
        }
      }
    }
    if ($hit) {
      $next = if ($nl -lt 0) { $n } else { $nl + 1 }
      $spans.Add(@{ Start = $start; End = $end; Next = $next; Line = $lineNo })
    }
    if ($nl -lt 0) { break }
    $start = $nl + 1
  }
  return ,$spans.ToArray()
}

# Test-MarkerOwned -- the ownership test for the three hook markers
# (INDEX-AUTOGEN, REF-GUARD, CLOSE-GATE), on bytes: the marker opens a line
# of the file at $Path. The one predicate every foreign check, "already
# installed" check, -Uninstall and attestation below consult, so a hook the
# installer would delete is exactly a hook it would also refresh.
function Test-MarkerOwned {
  param([string]$Path, [string]$Marker)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $b = [System.IO.File]::ReadAllBytes($Path)
  return ((Find-MarkerLines -Bytes $b -Marker $Marker).Count -gt 0)
}
# docs/ai/docs-audit.yaml -- the committed guard-policy surface (D2), the
# SAME file and the SAME column-0 `ref_guard: <value>` key the .sh twin
# reads/writes (Amendment 1: one config file must serve a repo checked out
# on either platform). Read by lib/guard-config.mjs's readRefGuardPolicy
# (the canonical JS reader); this script mirrors it with the identical
# grammar, never a node import (check-vendored-script-deps.mjs).
$configPath = Join-Path $repoRoot 'docs/ai/docs-audit.yaml'

# Show-ForeignPrePushRefusal -- the pre-push slot's twin of
# Show-ForeignReftxRefusal: one function, one sentence, naming the .sh twin's
# --print pre-push (this twin has no -Print of its own).
function Show-ForeignPrePushRefusal {
  Write-Error "$prePushPath already exists and is not AAI-managed. Pass -Force to overwrite, or merge the AAI:CLOSE-GATE body with: bash .aai/scripts/install-pre-commit-hook.sh --print pre-push"
}

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
  if (-not (Test-MarkerOwned -Path $p -Marker $Marker)) {
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

# Confirm-HooksDir -- create or validate the EFFECTIVE git hooks directory
# ($hooksDir, the parent of $reftxPath) before anything writes into it.
# Mirrors the .sh twin's ensure_hooks_dir (TEST-647): `core.hooksPath` can
# name a directory that does not exist yet (measured: a scratch repo with
# `git config core.hooksPath missing-dir`), and Enable-RefGuard -- the
# -ArmRefGuard dispatch below, which runs BEFORE the normal install flow's own
# New-Item further down -- must not hand Set-Content a parent directory that
# is not there. Under this script's own $ErrorActionPreference = 'Stop' a
# missing parent turns Set-Content into an immediate terminating error rather
# than a false "Installed" line (the .sh twin's worse failure mode), but the
# net effect for the operator is the same defect this finding names: an
# explicit -ArmRefGuard that should simply create the directory instead dies.
function Confirm-HooksDir {
  if ((Test-Path -LiteralPath $hooksDir) -and -not (Test-Path -LiteralPath $hooksDir -PathType Container)) {
    Write-Error "The effective git hooks path $hooksDir exists and is not a directory. Refusing to install rather than reporting success on a guard git cannot run."
    return $false
  }
  New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null
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
# no other line. "Replace" recognises ANY column-0 `ref_guard:` line carrying
# a non-blank token as the key to replace -- the SAME "is this line the key"
# grammar lib/guard-config.mjs's readRefGuardPolicy uses (Spec-AC-06), not
# the narrower armed|declined set an earlier version of this gate used.
# Ends by reading the value back through Read-RefGuardPolicy and refusing if
# it disagrees -- the write is not trusted merely because it did not throw.
#
# WHY "any token", not a closed set (validation round 2, B2, cross-twin: the
# .sh's write_ref_guard_policy carries the full account): the earlier gate
# matched ONLY an existing armed|declined line, so a config already carrying
# an out-of-vocabulary `ref_guard:` value (a typo) fell to the APPEND branch
# below and the file ended up with TWO `ref_guard:` lines -- violating
# Spec-AC-05's "leaving exactly one ref_guard: line" and leaving the
# canonical JS reader (first-occurrence-wins) disagreeing with this file's
# own Read-RefGuardPolicy mirror (a whole-file scan) about a file this
# script had just written. Widening the gate makes -ArmRefGuard /
# -DeclineRefGuard self-healing: they correct a stray value in place instead
# of shadowing it behind a second line, and they keep succeeding (Spec-AC-05
# is a SHALL on the value it writes) rather than trading the violation for a
# loud but still-unhelpful refusal.
#
# CREATION (code review 20260924T124304Z B2): the mere EXISTENCE of
# docs/ai/docs-audit.yaml flips docs-audit from report-only to enforced mode
# (lib/docs-audit-core.mjs -- any parsed config, however sparse, makes
# `mode = 'enforced'`; same measurement as the .sh twin's comment above
# Write-RefGuardPolicy's counterpart). aai-sync already creates this same
# file and discloses that consequence; a -DeclineRefGuard/-ArmRefGuard run
# that creates it silently was a second, undisclosed creation path. SEED
# from the same template aai-sync uses (so this command creates the same
# object a sync would have) and print the SAME disclosure line, before
# setting the ref_guard key; when the template is not present, a NOTE names
# the same consequence instead. Governs only the first write to an absent
# file (TEST-644 is this twin's arm of TEST-643).
function Write-RefGuardPolicy {
  param(
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$Value
  )
  $dir = Split-Path -Parent $ConfigPath
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $configWasAbsent = -not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)
  if ($configWasAbsent) {
    $docsAuditTemplate = Join-Path $repoRoot '.aai/templates/docs-audit.template.yaml'
    if (Test-Path -LiteralPath $docsAuditTemplate -PathType Leaf) {
      Copy-Item -LiteralPath $docsAuditTemplate -Destination $ConfigPath
      Write-Host "SEED docs/ai/docs-audit.yaml from .aai/templates/docs-audit.template.yaml (dials report-only; docs-audit --check now runs enforced)"
    } else {
      Write-Host "NOTE: creating docs/ai/docs-audit.yaml -- this switches docs-audit from report-only to enforced mode (docs-audit --check may now hard-fail on pre-existing orphans/violations it previously only reported)."
    }
  }
  $existingLines = @()
  if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
    $existingLines = @(Get-Content -LiteralPath $ConfigPath)
  }
  $replaced = $false
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($line in $existingLines) {
    if ((-not $replaced) -and ($line -match '^ref_guard:\s*\S')) {
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
#
# ORDER (code review 20260924T124304Z B1 -- this twin never got round 1's
# B1b fix; the .sh's decline_ref_guard writes the declaration BEFORE
# removing the hook, this function did the opposite): write the declaration
# FIRST. The D6 discipline this file already applies to the two hook slots
# ("check both before writing either") now applies to the decline's own two
# effects here too -- a Write-RefGuardPolicy failure (an unwritable config:
# read-only fs, permissions) must never leave the guard removed with no
# record of why. Writing first means that failure returns $false with the
# guard still installed and still armed; disarmed-but-silent is not
# reachable, not merely rare. Mirrors the .sh twin exactly (TEST-635); the
# .ps1 arm here is TEST-642.
function Disable-RefGuard {
  $reftxIsAai = $false
  if (Test-Path -LiteralPath $reftxPath -PathType Leaf) {
    if (Test-MarkerOwned -Path $reftxPath -Marker $reftxMarker) { $reftxIsAai = $true }
  }
  if ((Test-Path -LiteralPath $reftxPath -PathType Leaf) -and (-not $reftxIsAai)) {
    Show-ForeignReftxRefusal
    Write-Host "Refusing to remove a foreign hook -- -DeclineRefGuard only removes an AAI-managed guard."
    return $false
  }
  if (-not (Write-RefGuardPolicy -ConfigPath $configPath -Value 'declined')) {
    return $false
  }
  if (Test-Path -LiteralPath $reftxPath -PathType Leaf) {
    Remove-Item -LiteralPath $reftxPath
    Write-Host "Uninstalled AAI reference-transaction hook (AAI:REF-GUARD) from $reftxPath"
  }
  Write-Host "Declined the AAI reference-transaction guard. Recorded ref_guard: declined in $configPath"
  Write-Host "Re-arm with: pwsh $repoRoot/.aai/scripts/install-pre-commit-hook.ps1 -ArmRefGuard"
  return $true
}

# Enable-RefGuard -- Spec-AC-05 (Amendment 1: .ps1 twin): (re-)install the
# ref-guard hook (same foreign-hook refusal as the normal write path) and
# record ref_guard: armed.
function Enable-RefGuard {
  if (-not (Test-HookTemplates -Names @('reference-transaction.sh'))) { return $false }
  $reftxBytes = Get-TemplateBytes 'reference-transaction.sh'
  if ((Test-Path -LiteralPath $reftxPath -PathType Leaf) -and (-not $Force)) {
    if (-not (Test-MarkerOwned -Path $reftxPath -Marker $reftxMarker)) {
      Show-ForeignReftxRefusal
      return $false
    }
  }
  if (-not (Confirm-HooksDir)) { return $false }  # TEST-647: core.hooksPath may name a directory that does not exist yet
  Write-BytesViaTemp -Path $reftxPath -Bytes $reftxBytes
  Set-HookExecutable $reftxPath
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
    if (Test-MarkerOwned -Path $hookPath -Marker $marker) {
      Remove-Item $hookPath
      Write-Host "Uninstalled AAI pre-commit hook from $hookPath"
    } else {
      Write-Host "No AAI pre-commit hook found (or hook is not AAI-managed). No action taken."
    }
  }
  if ($wantRefGuard) {
    if (Test-MarkerOwned -Path $reftxPath -Marker $reftxMarker) {
      Remove-Item $reftxPath
      Write-Host "Uninstalled AAI reference-transaction hook (AAI:REF-GUARD) from $reftxPath"
    } else {
      Write-Host "No AAI reference-transaction hook found (or hook is not AAI-managed). No action taken."
    }
  }
  if ($wantCloseGate) {
    if (Test-MarkerOwned -Path $prePushPath -Marker $prePushMarker) {
      Remove-Item $prePushPath
      Write-Host "Uninstalled AAI pre-push hook (AAI:CLOSE-GATE) from $prePushPath"
    } else {
      Write-Host "No AAI pre-push hook found (or hook is not AAI-managed). No action taken."
    }
  }
  exit 0
}

# Selection-aware (Spec-AC-02): a foreign file in a slot this run was NOT
# asked to touch is not a reason to refuse.
$foreign = $false
if ($wantIndex -and (Test-Path $hookPath) -and (-not $Force)) {
  if (-not (Test-MarkerOwned -Path $hookPath -Marker $marker)) {
    Write-Error "$hookPath already exists and is not AAI-managed. Pass -Force to overwrite, or merge the snippets with: bash .aai/scripts/install-pre-commit-hook.sh --print (the AAI:INDEX-AUTOGEN body) and --print guard-checks (the AAI:GUARD-CHECKS block, put it first)."
    $foreign = $true
  }
}
if ($wantCloseGate -and (Test-Path $prePushPath) -and (-not $Force)) {
  if (-not (Test-MarkerOwned -Path $prePushPath -Marker $prePushMarker)) {
    Show-ForeignPrePushRefusal
    $foreign = $true
  }
}
if ($wantRefGuard -and (Test-Path $reftxPath) -and (-not $Force)) {
  if (-not (Test-MarkerOwned -Path $reftxPath -Marker $reftxMarker)) {
    Show-ForeignReftxRefusal
    $foreign = $true
  }
}
if ($foreign) {
  exit 1
}

$needTemplates = @()
if ($wantIndex) { $needTemplates += @('pre-commit-index.sh', 'pre-commit-guard-checks.sh') }
if ($wantRefGuard -and ($Force -or ((Read-RefGuardPolicy -ConfigPath $configPath) -ne 'declined'))) { $needTemplates += 'reference-transaction.sh' }
if ($wantCloseGate) { $needTemplates += 'pre-push.sh' }
if ($needTemplates.Count -gt 0 -and -not (Test-HookTemplates -Names $needTemplates)) { exit 1 }

if (-not (Confirm-HooksDir)) { exit 1 }

# An AAI-marked file already in the pre-commit slot (and no -Force) takes the
# marker-scoped UPGRADE path (Update-PreCommitHook below) instead of a fresh
# write: the block is inserted, or its interior refreshed, and nothing else
# is touched.
$upgradePreCommit = $false
if ($wantIndex -and ((Test-Path -LiteralPath $hookPath) -or ((Get-Item -LiteralPath $hookPath -Force -ErrorAction SilentlyContinue) -ne $null)) -and (-not $Force)) {
  $upgradePreCommit = $true
}

# Get-GuardBlockBytes -- the AAI:GUARD-CHECKS block as LF-terminated bytes:
# the guard-checks template itself (never a second copy).
function Get-GuardBlockBytes {
  return ,(Get-TemplateBytes 'pre-commit-guard-checks.sh')
}

# Get-GuardBlockInterior -- the lines strictly between the two markers of a
# LF-split line array (the only range an upgrade compares and replaces).
function Get-GuardBlockInterior {
  param([string[]]$Lines)
  $out = New-Object System.Collections.Generic.List[string]
  $inBlock = $false
  foreach ($line in $Lines) {
    if ($line -eq $guardBlockBegin) { $inBlock = $true; continue }
    if ($line -eq $guardBlockEnd) { $inBlock = $false; continue }
    if ($inBlock) { $out.Add($line) }
  }
  return ,$out.ToArray()
}

# Update-PreCommitHook -- the pre-commit slot already holds an AAI-marked
# file and -Force was not given. The #414 / SPEC-0199 discipline, mirroring
# the .sh twin's upgrade_precommit_hook: rewrite only what this script can
# PROVE it owns, otherwise leave the file alone and say so. Works on BYTES
# on EVERY path -- insertion and refresh alike -- never a Get-Content /
# UTF8.GetString round-trip: decoding re-encodes every non-UTF-8 byte
# outside the markers as U+FFFD (validation B2: `e9 ... ff fe` became
# `ef bf bd ...` under a message claiming "every other byte unchanged"), and
# a UTF-16 file decodes into a marker it does not carry on disk (NB2). The
# file's encoding and line endings outside the touched range are preserved
# as-is (fu-ps1-setcontent-rewrites-seed-eol). Marker order is checked
# BEFORE any write (validation B1: END above BEGIN dropped 150 user lines).
function Update-PreCommitHook {
  $item = Get-Item -LiteralPath $hookPath -Force
  if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
    [Console]::Error.WriteLine("$hookPath is a symlink. Refusing to rewrite through a symlink (the target may be outside this repository); replace the link with a regular file, or pass -Force.")
    return $false
  }
  $bytes = [System.IO.File]::ReadAllBytes($hookPath)
  $nl = [Array]::IndexOf($bytes, [byte]10)
  if ($nl -lt 0) {
    [Console]::Error.WriteLine("$hookPath has no newline-terminated line; refusing to insert the AAI:GUARD-CHECKS block into it. Pass -Force to rewrite the whole slot.")
    return $false
  }
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    [Console]::Error.WriteLine("$hookPath starts with a UTF-8 byte-order mark (EF BB BF); sh cannot start a hook whose first bytes are not '#!', so the AAI:GUARD-CHECKS block is not inserted into it. File left as it was. Strip the BOM, or pass -Force to rewrite the whole slot.")
    return $false
  }
  if ($nl -gt 0 -and $bytes[$nl - 1] -eq 13) {
    [Console]::Error.WriteLine("$hookPath has a CR-terminated first line (CRLF hook). Refusing to insert an LF block under it -- sh could not start the result. Convert the hook to LF, or pass -Force to rewrite the whole slot.")
    return $false
  }
  $beginSpans = Find-MarkerLines -Bytes $bytes -Marker $guardBlockBegin -Exact
  $endSpans = Find-MarkerLines -Bytes $bytes -Marker $guardBlockEnd -Exact
  $begins = $beginSpans.Count
  $ends = $endSpans.Count
  # Latin-1 (ISO-8859-1) maps every byte to one char, so this substring test
  # sees the raw bytes and mirrors the .sh twin's `grep -qF` exactly: a BEGIN
  # marker anywhere (even quoted inside a string) routes to the count check
  # below, never to insertion.
  $hasBeginSubstring = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes).Contains($guardBlockBegin)
  if (-not $hasBeginSubstring) {
    if ($ends -ne 0) {
      [Console]::Error.WriteLine("$hookPath carries $ends '$guardBlockEnd' line(s) and no '$guardBlockBegin'; refusing to insert a block above a stray END marker. File left as it was. Remove the END line by hand, or pass -Force to rewrite the whole slot.")
      return $false
    }
    $block = Get-GuardBlockBytes
    $hasShebang = ($bytes.Length -ge 2 -and $bytes[0] -eq 35 -and $bytes[1] -eq 33)
    if ($hasShebang) {
      $head = $bytes[0..$nl]
      $tail = if ($bytes.Length -gt ($nl + 1)) { $bytes[($nl + 1)..($bytes.Length - 1)] } else { @() }
      $new = [byte[]]($head + $block + $tail)
    } else {
      $new = [byte[]]($block + $bytes)
    }
    Write-BytesViaTemp -Path $hookPath -Bytes $new
    if ($IsLinux -or $IsMacOS) { & chmod +x $hookPath | Out-Null }
    Write-Host "Upgraded AAI pre-commit hook at ${hookPath}: added the AAI:GUARD-CHECKS block (pre-commit-checks.sh now runs on every commit; secrets detection blocks)"
    return $true
  }
  if ($begins -ne 1 -or $ends -ne 1) {
    [Console]::Error.WriteLine("$hookPath carries $begins '$guardBlockBegin' and $ends '$guardBlockEnd' line(s); refusing to guess which block is the installer's. File left as it was. Remove the extra markers by hand, or pass -Force to rewrite the whole slot.")
    return $false
  }
  $beginLn = $beginSpans[0].Line
  $endLn = $endSpans[0].Line
  if ($beginLn -gt $endLn) {
    [Console]::Error.WriteLine("$hookPath carries '$guardBlockEnd' (line $endLn) BEFORE '$guardBlockBegin' (line $beginLn): the markers are inverted, so no interior can be located and a refresh would drop every line after the BEGIN. File left as it was. Move the BEGIN line above the END line by hand, or pass -Force to rewrite the whole slot.")
    return $false
  }
  # The interior is the byte range from the byte after the BEGIN line's LF to
  # the first byte of the END line; the shipped interior is LF-terminated
  # UTF-8 (the block is engine-owned ASCII). Compared and spliced as bytes.
  $shippedInterior = Get-GuardBlockInterior -Lines ([System.Text.Encoding]::ASCII.GetString((Get-GuardBlockBytes)) -split "\n")
  $shippedBytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($shippedInterior -join "`n") + "`n")
  $curStart = $beginSpans[0].Next
  $curEnd = $endSpans[0].Start
  $currentBytes = if ($curEnd -gt $curStart) { [byte[]]$bytes[$curStart..($curEnd - 1)] } else { [byte[]]@() }
  if ([Convert]::ToBase64String($currentBytes) -eq [Convert]::ToBase64String($shippedBytes)) {
    Write-Host "AAI pre-commit hook already installed at $hookPath. No action taken."
    return $true
  }
  $head = $bytes[0..($curStart - 1)]
  $tail = $bytes[$curEnd..($bytes.Length - 1)]
  $new = [byte[]]($head + $shippedBytes + $tail)
  Write-BytesViaTemp -Path $hookPath -Bytes $new
  if ($IsLinux -or $IsMacOS) { & chmod +x $hookPath | Out-Null }
  Write-Host "Refreshed the AAI:GUARD-CHECKS block at $hookPath (interior between the markers replaced; every other byte unchanged)"
  return $true
}

if ($wantIndex) {
  if ($upgradePreCommit) {
    if (-not (Update-PreCommitHook)) { exit 1 }
  } else {
    $idxBytes = Get-TemplateBytes 'pre-commit-index.sh'
    $guardBytes = Get-GuardBlockBytes
    $firstNl = [Array]::IndexOf($idxBytes, [byte]10)
    $preCommitBytes = [byte[]]($idxBytes[0..$firstNl] + $guardBytes + $idxBytes[($firstNl + 1)..($idxBytes.Length - 1)])
    Write-BytesViaTemp -Path $hookPath -Bytes $preCommitBytes
    Set-HookExecutable $hookPath
    Write-Host "Installed AAI pre-commit hook at $hookPath"
    Write-Host "Effect: pre-commit-checks.sh now runs on every commit (secrets detection blocks; roughly four seconds per commit); on every commit that touches docs/, regenerate docs/INDEX.md and stage it."
  }
}

# N1 (validation round 1, mirrors the .sh twin): a declared decline must
# survive a plain re-install -- the shape SKILL_UPDATE step 4 runs on every
# successful sync, with no flags. -ArmRefGuard (dispatched above, before this
# whole -Hooks flow, and never consulting the policy) and -Force (whose
# existing contract is already "proceed past a protective refusal in this
# slot") stay the two explicit overrides.
#
# -Force is intentionally scoped to the HOOK, not the DECLARATION
# (validation round 2, NB3, same decision as the .sh twin): after a -Force
# past a decline, the guard is installed but docs/ai/docs-audit.yaml still
# reads `ref_guard: declined`. Left as-is: -Force's contract predates this
# scope and already means something narrower than "also change the
# committed declaration" -- conflating the two would make a one-off
# override on THIS run silently rewrite a file D2 defines as a deliberate,
# reviewable act. D4 makes every reader trust an actually-installed hook
# over a stale declaration, so the gap is inert; -ArmRefGuard is the command
# for changing the declaration too.
if ($wantRefGuard -and (-not $Force) -and ((Read-RefGuardPolicy -ConfigPath $configPath) -eq 'declined')) {
  Write-Host "Skipped AAI reference-transaction hook (AAI:REF-GUARD): $configPath declares ref_guard: declined."
  Write-Host "Re-arm with: pwsh $repoRoot/.aai/scripts/install-pre-commit-hook.ps1 -ArmRefGuard (or pass -Force)."
  $wantRefGuard = $false
}

$skipReftx = $false
if ($wantRefGuard -and (Test-Path $reftxPath) -and (-not $Force)) {
  if (Test-MarkerOwned -Path $reftxPath -Marker $reftxMarker) {
    Write-Host "AAI reference-transaction hook already installed at $reftxPath. No action taken."
    $skipReftx = $true
  }
}

if ($wantRefGuard) {
  if (-not $skipReftx) {
    $reftxBytes = Get-TemplateBytes 'reference-transaction.sh'
    Write-BytesViaTemp -Path $reftxPath -Bytes $reftxBytes
    Set-HookExecutable $reftxPath
    Write-Host "Installed AAI reference-transaction hook (AAI:REF-GUARD) at $reftxPath"
    Write-Host "Effect: a refs/heads/main update is refused unless AAI_GIT_WRITE=1 is set on that command."
  }
}

# No decline dial of its own: the pre-push verdict is already dialled by
# `close_gate` in docs/ai/docs-audit.yaml (D8), read from the pushed commit.
if ($wantCloseGate) {
  $skipPrePush = $false
  if ((Test-Path $prePushPath) -and (-not $Force)) {
    if (Test-MarkerOwned -Path $prePushPath -Marker $prePushMarker) {
      Write-Host "AAI pre-push hook already installed at $prePushPath. No action taken."
      $skipPrePush = $true
    }
  }
  if (-not $skipPrePush) {
    $prePushBytes = Get-TemplateBytes 'pre-push.sh'
    Write-BytesViaTemp -Path $prePushPath -Bytes $prePushBytes
    Set-HookExecutable $prePushPath
    Write-Host "Installed AAI pre-push hook (AAI:CLOSE-GATE) at $prePushPath"
    Write-Host "Effect: every push runs close-reconcile.mjs --check over the pushed range (report-only; close_gate: enforce refuses a default-branch push only)."
  }
}

# Post-condition (PR #304 Codex P1) -- see Test-EffectiveHook. Selection-aware
# (Spec-AC-02): attestation covers exactly the SELECTED set, mirroring the
# .sh twin.
$attestOk = $true
if ($wantIndex -and -not (Test-EffectiveHook -Name 'pre-commit' -Marker $marker)) { $attestOk = $false }
if ($wantRefGuard -and -not (Test-EffectiveHook -Name 'reference-transaction' -Marker $reftxMarker)) { $attestOk = $false }
if ($wantCloseGate -and -not (Test-EffectiveHook -Name 'pre-push' -Marker $prePushMarker)) { $attestOk = $false }
if (-not $attestOk) {
  Write-Error "Installation did NOT leave an active hook at the path git resolves. Check 'git config core.hooksPath' and 'git rev-parse --git-path hooks/reference-transaction'."
  exit 1
}

Write-Host "Uninstall with: pwsh .aai/scripts/install-pre-commit-hook.ps1 -Uninstall"
