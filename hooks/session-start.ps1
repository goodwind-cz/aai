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
