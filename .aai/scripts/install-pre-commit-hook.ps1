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

# $prePushBody -- the AAI:CLOSE-GATE pre-push hook, byte-identical to the .sh
# twin's pre_push_body modulo this file's own "Installed by" line
# (shipped-guards-have-no-downstream-trigger D9; TEST-813 diffs the two).
$prePushBody = @'
#!/usr/bin/env bash
# AAI:CLOSE-GATE -- runs close-reconcile.mjs --check over every pushed range.
# Installed by .aai/scripts/install-pre-commit-hook.ps1 (or the .sh twin).
# Per pushed ref (stdin: <local ref> <local sha> <remote ref> <remote sha>):
#   - a deletion (all-zero local sha) is skipped;
#   - the default branch (refs/remotes/origin/HEAD, else main) is checked as
#     <remote sha>..<local sha>; a first push (all-zero remote sha) as
#     <local sha>^..<local sha> -- the rule .github/workflows/close-gate.yml
#     applies;
#   - any other ref as merge-base(refs/remotes/<remote>/<default>, local)..local.
# Verdict: `close_gate` read from the PUSHED commit's docs/ai/docs-audit.yaml
# (never the worktree copy). report-only (default): print, exit 0. enforce:
# refuse ONLY a push to the default branch; every other ref stays report-
# only, because WIP pushes legitimately precede the close ceremony.
# See docs/specs/SPEC-0201-spec-shipped-guards-have-no-downstream-trigger.md.

_cg_remote="${1:-origin}"
_cg_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
_cg_script="$_cg_root/.aai/scripts/close-reconcile.mjs"

if ! command -v node >/dev/null 2>&1; then
  echo "AAI:CLOSE-GATE NOTE: node not found; close gate skipped" >&2
  exit 0
fi
if [ ! -f "$_cg_script" ]; then
  echo "AAI:CLOSE-GATE NOTE: $_cg_script absent; close gate skipped" >&2
  exit 0
fi

# R1 -- default branch: refs/remotes/origin/HEAD with the origin/ prefix
# stripped; else main, and say so.
_cg_default="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
_cg_default="${_cg_default#origin/}"
if [ -z "$_cg_default" ]; then
  _cg_default="main"
  echo "AAI:CLOSE-GATE NOTE: default branch assumed main (refs/remotes/origin/HEAD unset)" >&2
fi
echo "AAI:CLOSE-GATE: default branch $_cg_default (remote $_cg_remote)"

_cg_refused=0
while read -r _cg_lref _cg_local _cg_rref _cg_remote_sha; do
  [ -n "$_cg_lref" ] || continue
  case "$_cg_local" in
    *[!0]*) ;;
    *) echo "AAI:CLOSE-GATE: $_cg_rref is a deletion; nothing to check"; continue ;;
  esac
  # The dial, read from what is being PUSHED (the same "gate what ships,
  # never the worktree copy" discipline the pre-commit body applies).
  _cg_mode="report-only"
  _cg_cfg="$(git show "$_cg_local:docs/ai/docs-audit.yaml" 2>/dev/null || true)"
  if grep -Eq '^close_gate:[[:space:]]*enforce([[:space:]]|$)' <<<"$_cg_cfg"; then
    _cg_mode="enforce"
  fi
  _cg_is_default=0
  if [ "$_cg_rref" = "refs/heads/$_cg_default" ]; then
    _cg_is_default=1
  fi
  if [ "$_cg_is_default" = 1 ]; then
    case "$_cg_remote_sha" in
      *[!0]*) _cg_range="$_cg_remote_sha..$_cg_local" ;;
      *) _cg_range="$_cg_local^..$_cg_local" ;;
    esac
  else
    # Codex P2 on PR #417: git hands the pre-push hook whatever the user typed
    # as the remote, which may be a PATH or a URL rather than a configured
    # name (see the githooks pre-push contract). `refs/remotes/<url>/<default>`
    # is then an impossible ref, the NOTE fires and close-reconcile is skipped
    # -- so `git push <url> HEAD:feat` slipped past the gate this hook exists to
    # provide. Use the named remote when it IS one; otherwise fall back to the
    # origin tracking ref, which is what R1 already resolved the default from.
    if git config --get "remote.$_cg_remote.url" >/dev/null 2>&1; then
      _cg_track="refs/remotes/$_cg_remote/$_cg_default"
    else
      _cg_track="refs/remotes/origin/$_cg_default"
    fi
    _cg_base="$(git merge-base "$_cg_track" "$_cg_local" 2>/dev/null || true)"
    if [ -z "$_cg_base" ]; then
      echo "AAI:CLOSE-GATE NOTE: $_cg_rref skipped -- $_cg_track unresolvable" >&2
      continue
    fi
    _cg_range="$_cg_base..$_cg_local"
  fi
  echo "AAI:CLOSE-GATE: $_cg_rref range=$_cg_range close_gate=$_cg_mode"
  _cg_rc=0
  _cg_out="$(node "$_cg_script" --check --range "$_cg_range" --root "$_cg_root" 2>&1)" || _cg_rc=$?
  printf '%s\n' "$_cg_out"
  if [ "$_cg_rc" -eq 0 ]; then
    continue
  fi
  if [ "$_cg_rc" -eq 2 ]; then
    echo "AAI:CLOSE-GATE NOTE: close-reconcile.mjs could not resolve range $_cg_range (rc=2)" >&2
  fi
  if [ "$_cg_mode" = "enforce" ] && [ "$_cg_is_default" = 1 ]; then
    echo "AAI:CLOSE-GATE refused: push of $_cg_rref (close_gate: enforce, default branch $_cg_default) -- the close ceremony did not run for range $_cg_range (rc=$_cg_rc)." >&2
    echo "  Fix: run the close ceremony (/aai-pr, or the close-work-item.mjs command printed above), or set close_gate: report-only in docs/ai/docs-audit.yaml on the pushed commit." >&2
    _cg_refused=1
  else
    echo "AAI:CLOSE-GATE: reported for $_cg_rref (close_gate=$_cg_mode; push allowed)"
  fi
done
exit "$_cg_refused"
'@

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
  if ((Test-Path -LiteralPath $reftxPath -PathType Leaf) -and (-not $Force)) {
    if (-not (Test-MarkerOwned -Path $reftxPath -Marker $reftxMarker)) {
      Show-ForeignReftxRefusal
      return $false
    }
  }
  if (-not (Confirm-HooksDir)) { return $false }  # TEST-647: core.hooksPath may name a directory that does not exist yet
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

if (-not (Confirm-HooksDir)) { exit 1 }

# An AAI-marked file already in the pre-commit slot (and no -Force) takes the
# marker-scoped UPGRADE path (Update-PreCommitHook below) instead of a fresh
# write: the block is inserted, or its interior refreshed, and nothing else
# is touched.
$upgradePreCommit = $false
if ($wantIndex -and ((Test-Path -LiteralPath $hookPath) -or ((Get-Item -LiteralPath $hookPath -Force -ErrorAction SilentlyContinue) -ne $null)) -and (-not $Force)) {
  $upgradePreCommit = $true
}

$hookBody = @'
#!/usr/bin/env bash
# AAI:GUARD-CHECKS BEGIN
# managed by install-pre-commit-hook; edit outside these markers
# Runs .aai/scripts/pre-commit-checks.sh (secrets detection blocks; the
# doc-numbering guard reports or blocks per docs/ai/docs-audit.yaml) on
# every commit, before the AAI:INDEX-AUTOGEN body below.
_gc_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
_gc_script="$_gc_root/.aai/scripts/pre-commit-checks.sh"
if [ -f "$_gc_script" ]; then
  echo "AAI:GUARD-CHECKS: running .aai/scripts/pre-commit-checks.sh"
  _gc_rc=0
  bash "$_gc_script" || _gc_rc=$?
  if [ "$_gc_rc" -ne 0 ]; then
    echo "AAI:GUARD-CHECKS: pre-commit-checks.sh blocked this commit (rc=$_gc_rc)" >&2
    exit "$_gc_rc"
  fi
else
  echo "AAI:GUARD-CHECKS NOTE: .aai/scripts/pre-commit-checks.sh absent; guard checks skipped" >&2
fi
# AAI:GUARD-CHECKS END
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

# Get-GuardBlockBytes -- the AAI:GUARD-CHECKS block as LF-terminated UTF-8
# bytes, extracted from $hookBody itself (never a second copy).
function Get-GuardBlockBytes {
  $lines = $hookBody -split "\n"
  $out = New-Object System.Collections.Generic.List[string]
  $inBlock = $false
  foreach ($line in $lines) {
    if ($line -eq $guardBlockBegin) { $inBlock = $true }
    if ($inBlock) { $out.Add($line) }
    if ($line -eq $guardBlockEnd) { break }
  }
  return [System.Text.UTF8Encoding]::new($false).GetBytes(($out -join "`n") + "`n")
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

# Write-BytesViaTemp -- write bytes to a temp sibling and rename over the
# target, so a failed write can never truncate what was there.
function Write-BytesViaTemp {
  param([string]$Path, [byte[]]$Bytes)
  $tmp = "$Path.aai-tmp.$PID"
  [System.IO.File]::WriteAllBytes($tmp, $Bytes)
  Move-Item -LiteralPath $tmp -Destination $Path -Force
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
  $shippedInterior = Get-GuardBlockInterior -Lines ($hookBody -split "\n")
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
    Set-Content -Path $hookPath -Value $hookBody -NoNewline
    if ($IsLinux -or $IsMacOS) {
      & chmod +x $hookPath | Out-Null
    }
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
    Set-Content -Path $reftxPath -Value $reftxBody -NoNewline
    if ($IsLinux -or $IsMacOS) {
      & chmod +x $reftxPath | Out-Null
    }
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
    Set-Content -Path $prePushPath -Value $prePushBody -NoNewline
    if ($IsLinux -or $IsMacOS) {
      & chmod +x $prePushPath | Out-Null
    }
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
