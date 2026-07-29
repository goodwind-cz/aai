# AAI session-start hook - injects meta-skill context at session start.
# Compatible with: Claude Code, Cursor, Gemini CLI, Codex, GitHub Copilot.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $Utf8NoBom
$OutputEncoding = $Utf8NoBom

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$MetaSkill = Join-Path $ProjectRoot ".aai/SKILL_META.prompt.md"

if (-not (Test-Path $MetaSkill)) {
  exit 0
}

$MetaSkillContent = [string](Get-Content -Path $MetaSkill -Raw)

# Best-effort new-release check (spec-auto-update-config). Runs update-check.mjs
# and appends its notify/degrade/sync line onto the emitted content. This is
# RUNTIME-CRITICAL: a check failure, timeout, or slow network must NEVER break,
# block, or delay session start. The whole block is wrapped in try/catch (so
# $ErrorActionPreference = "Stop" can never abort the hook) and the child is
# bounded by WaitForExit(ms); on any problem the meta-skill content is emitted
# unchanged, exactly as before this hook existed.
$UpdateCheck = Join-Path $ProjectRoot ".aai/scripts/update-check.mjs"
if ((Test-Path $UpdateCheck) -and (Get-Command node -ErrorAction SilentlyContinue)) {
  try {
    $TimeoutS = 15
    if ($env:AAI_UPDATE_CHECK_TIMEOUT_S -match '^\d+$') { $TimeoutS = [int]$env:AAI_UPDATE_CHECK_TIMEOUT_S }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "node"
    $psi.Arguments = "`"$UpdateCheck`""
    $psi.WorkingDirectory = $ProjectRoot
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    try {
      # Drain BOTH pipes async so a full stdout OR stderr buffer can never
      # deadlock the wait (a full stderr pipe stalls the child just as a full
      # stdout one does). The stderr drain is discarded.
      $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
      $null = $proc.StandardError.ReadToEndAsync()
      if ($proc.WaitForExit($TimeoutS * 1000)) {
        $UpdateNote = $stdoutTask.Result
        if ($UpdateNote -and $UpdateNote.Trim().Length -gt 0) {
          $MetaSkillContent = $MetaSkillContent + "`n`n" + $UpdateNote.TrimEnd()
        }
      } else {
        # Timed out: kill and REAP (WaitForExit after Kill) so no lingering proc.
        # The detached auto-sync (if any) is a SEPARATE, already-detached node
        # process — it survives this Kill by design and reports next session.
        try { $proc.Kill() } catch {}
        try { $proc.WaitForExit() } catch {}
      }
    } finally {
      try { $proc.Dispose() } catch {}
    }
  } catch {
    # Swallow ALL errors/timeouts — the check must never break session start.
  }
}

if ($env:CLAUDE_PLUGIN_ROOT) {
  $Payload = @{
    hookSpecificOutput = @{
      hookEventName = "SessionStart"
      output = $MetaSkillContent
    }
  } | ConvertTo-Json -Compress -Depth 5
  [Console]::Out.Write($Payload)
}
elseif ($env:CURSOR_WORKSPACE_PATH -or $env:CURSOR_RULES_PATH) {
  $Payload = @{
    additional_context = $MetaSkillContent
  } | ConvertTo-Json -Compress -Depth 3
  [Console]::Out.Write($Payload)
}
elseif ($env:GEMINI_PROJECT_ROOT -or $env:GEMINI_CLI) {
  [Console]::Out.Write($MetaSkillContent)
}
else {
  [Console]::Out.Write($MetaSkillContent)
}
