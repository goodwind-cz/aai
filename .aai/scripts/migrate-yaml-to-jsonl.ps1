param(
  [string]$TargetRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

# Migrate legacy AAI YAML runtime files to JSONL format.
#
# Run this in the target project root BEFORE aai-sync so the JSONL files
# are populated and the sync script will preserve them.
#
# Usage:
#   .\scripts\migrate-yaml-to-jsonl.ps1 [-TargetRoot <path>]
#   (defaults to current directory)
#
# Requires: python3 + PyYAML  (pip install pyyaml)
#
# What it does:
#   docs/ai/LOOP_TICKS.yaml  (events list)  -> appended to  docs/ai/LOOP_TICKS.jsonl
#   docs/ai/METRICS.yaml     (entries list)  -> appended to  docs/ai/METRICS.jsonl
#
# Significance filter (keeps only meaningful entries):
#   - explicit significant=true
#   - errors/warnings/exceptions
#   - result not in noop/no_change/skipped/none/ok/success
#   - any change-ish fields (changes/diff/files_changed/summary/notes/decision/action)
#   - numeric value/delta/count != 0

$TargetRoot = (Resolve-Path $TargetRoot).Path
Write-Host "Target project: $TargetRoot"

$aiDir = Join-Path $TargetRoot "docs/ai"
if (!(Test-Path $aiDir)) {
  throw "docs/ai not found in $TargetRoot. Is this an AAI project?"
}

# Check python3 + PyYAML
$py = $null
foreach ($cmd in @("python3", "python", "py")) {
  try {
    $out = & $cmd -c "import yaml; print('ok')" 2>$null
    if ($out -eq "ok") { $py = $cmd; break }
  } catch {}
}
if (!$py) {
  throw "python3 + PyYAML required. Install with: pip install pyyaml"
}

$pyScript = @"
import yaml, json, sys

def _truthy(v):
    if v is None:
        return False
    if isinstance(v, (list, dict, str)):
        return len(v) > 0
    return bool(v)

def _significant(item):
    if not isinstance(item, dict):
        return True

    if item.get("significant") is True:
        return True

    for k in ("error", "errors", "warning", "warnings", "exception", "traceback"):
        if _truthy(item.get(k)):
            return True

    result = str(item.get("result", "")).strip().lower()
    if result and result not in ("noop", "no_change", "skipped", "none", "ok", "success"):
        return True

    for k in (
        "changes", "change", "diff", "patch", "files_changed", "file_changes",
        "updated_files", "applied", "writes", "writes_count", "edits",
        "summary", "notes", "decision", "action", "step", "event",
    ):
        if _truthy(item.get(k)):
            return True

    for k in ("value", "delta", "count", "errors", "warnings"):
        v = item.get(k)
        if isinstance(v, (int, float)) and v != 0:
            return True

    return False

src, dst, key = sys.argv[1], sys.argv[2], sys.argv[3]

with open(src, encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}

items = data.get(key) or []
total = len(items)
items = [i for i in items if _significant(i)]
kept = len(items)

if items:
    with open(dst, 'a', encoding='utf-8') as out:
        for item in items:
            out.write(json.dumps(item, separators=(',', ':'), ensure_ascii=False) + '\n')

print(f"{kept} {total}")
"@

# Write the Python script to a temp file (avoids quoting issues on Windows)
$tmpPy = [System.IO.Path]::GetTempFileName() + ".py"
Set-Content -Path $tmpPy -Value $pyScript -Encoding utf8

function Migrate-YamlToJsonl {
  param([string]$Src, [string]$Dst, [string]$Key)

  if (!(Test-Path $Src)) {
    Write-Host "  SKIP (not found):  $(Split-Path $Src -Leaf)"
    return
  }

  # Ensure destination JSONL exists
  if (!(Test-Path $Dst)) { New-Item -ItemType File -Path $Dst -Force | Out-Null }

  $counts = & $py $tmpPy $Src $Dst $Key
  $parts = $counts -split '\s+'
  $kept = if ($parts.Length -ge 1) { [int]$parts[0] } else { 0 }
  $total = if ($parts.Length -ge 2) { [int]$parts[1] } else { $kept }
  $filtered = $total - $kept

  if ($total -eq 0) {
    Write-Host "  SKIP (empty):      $(Split-Path $Src -Leaf) has no '$Key' entries"
  } elseif ($kept -gt 0) {
    Write-Host "  MIGRATED: $kept of $total entries (filtered $filtered)  $(Split-Path $Src -Leaf) -> $(Split-Path $Dst -Leaf)"
  } else {
    Write-Host "  SKIP (no significant): $(Split-Path $Src -Leaf) filtered $filtered of $total"
  }
}

try {
  Migrate-YamlToJsonl `
    -Src (Join-Path $TargetRoot "docs/ai/LOOP_TICKS.yaml") `
    -Dst (Join-Path $TargetRoot "docs/ai/LOOP_TICKS.jsonl") `
    -Key "events"

  Migrate-YamlToJsonl `
    -Src (Join-Path $TargetRoot "docs/ai/METRICS.yaml") `
    -Dst (Join-Path $TargetRoot "docs/ai/METRICS.jsonl") `
    -Key "entries"
} finally {
  Remove-Item $tmpPy -Force -ErrorAction SilentlyContinue
}

Write-Host "Done. Review: git -C `"$TargetRoot`" diff docs/ai/"
