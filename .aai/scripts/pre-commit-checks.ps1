# Pre-commit quality gate checks for AAI projects (PowerShell)
# Source: Inspired by pro-workflow quality gates (https://github.com/rohitg00/pro-workflow)
#
# Usage: Called from AAI skills before git commit, or as a standalone check.
#   powershell -File .aai/scripts/pre-commit-checks.ps1 [-Strict]
#
# Exit codes:
#   0 = all checks pass (warnings may exist)
#   1 = blocking errors found (commit should be prevented)

param([switch]$Strict)

$ProjectRoot = git rev-parse --show-toplevel 2>$null
if (-not $ProjectRoot) { $ProjectRoot = Get-Location }

$Errors = 0
$Warnings = 0

function Write-Error-Check($msg) { Write-Host "✗ $msg" -ForegroundColor Red; $script:Errors++ }
function Write-Warn-Check($msg)  { Write-Host "⚠ $msg" -ForegroundColor Yellow; $script:Warnings++ }
function Write-Pass-Check($msg)  { Write-Host "✓ $msg" -ForegroundColor Green }

Write-Host "─────────────────────────────────────"
Write-Host "PRE-COMMIT QUALITY GATES"
Write-Host "─────────────────────────────────────"
Write-Host ""

# --- CHECK 1: TDD Evidence ---
$StateFile = Join-Path $ProjectRoot "docs/ai/STATE.yaml"
if (Test-Path $StateFile) {
    $stateContent = Get-Content $StateFile -Raw
    if ($stateContent -match "phase:.*implementation") {
        if ($stateContent -notmatch "status:.*pass") {
            Write-Warn-Check "TDD cycle may be incomplete — active implementation without validation pass"
        } else {
            Write-Pass-Check "TDD evidence appears complete"
        }
    } else {
        Write-Pass-Check "No active implementation phase"
    }
} else {
    Write-Warn-Check "STATE.yaml not found — skipping TDD check"
}

# --- CHECK 2: Secrets Detection ---
$StagedFiles = git -C $ProjectRoot diff --cached --name-only 2>$null
$SecretsFound = $false

if ($StagedFiles) {
    foreach ($file in $StagedFiles) {
        $filepath = Join-Path $ProjectRoot $file
        if (-not (Test-Path $filepath)) { continue }

        $content = Get-Content $filepath -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        if ($content -match '(api[_-]?key|api[_-]?secret|password|passwd|secret[_-]?key|access[_-]?token|private[_-]?key)\s*[:=]\s*["''][^"'']{8,}') {
            Write-Error-Check "Potential secret detected in $file"
            $SecretsFound = $true
        }

        if ($file -match '(?i)(secret|credentials|\.env)') {
            Write-Error-Check "Sensitive file staged: $file"
            $SecretsFound = $true
        }
    }

    if (-not $SecretsFound) {
        Write-Pass-Check "No secrets detected in staged files"
    }
} else {
    Write-Pass-Check "No staged files to check"
}

# --- CHECK 3: Debug Statements ---
$DebugFound = $false
if ($StagedFiles) {
    foreach ($file in $StagedFiles) {
        if ($file -match '\.(md|yaml|yml|json|jsonl|txt|sh|ps1|gitignore)$') { continue }

        $filepath = Join-Path $ProjectRoot $file
        if (-not (Test-Path $filepath)) { continue }

        $matches = Select-String -Path $filepath -Pattern 'console\.log|debugger\b|pdb\.set_trace|binding\.pry|var_dump' -ErrorAction SilentlyContinue
        if ($matches) {
            Write-Warn-Check "Debug statements in ${file}:"
            $matches | Select-Object -First 3 | ForEach-Object { Write-Host "    $_" }
            $DebugFound = $true
        }
    }

    if (-not $DebugFound) {
        Write-Pass-Check "No debug statements found"
    }
}

# --- CHECK 4: TODO/FIXME ---
$TodoCount = 0
if ($StagedFiles) {
    foreach ($file in $StagedFiles) {
        if ($file -match '\.(md|yaml|yml|txt|sh|ps1)$') { continue }

        $filepath = Join-Path $ProjectRoot $file
        if (-not (Test-Path $filepath)) { continue }

        $matches = Select-String -Path $filepath -Pattern 'TODO|FIXME|HACK|XXX' -ErrorAction SilentlyContinue
        if ($matches) { $TodoCount += $matches.Count }
    }

    if ($TodoCount -gt 0) {
        Write-Warn-Check "$TodoCount TODO/FIXME markers in staged files"
    } else {
        Write-Pass-Check "No TODO/FIXME markers"
    }
}

# --- CHECK 5: Validation Report ---
if (Test-Path $StateFile) {
    $stateContent = Get-Content $StateFile -Raw
    if ($stateContent -match "phase:.*validation|status:.*pass") {
        $reportsDir = Join-Path $ProjectRoot "docs/ai/reports"
        if ((Test-Path $reportsDir) -and (Get-ChildItem "$reportsDir/VALIDATION_REPORT_*.md" -ErrorAction SilentlyContinue)) {
            Write-Pass-Check "Validation report exists"
        } else {
            Write-Warn-Check "No validation report found — consider running /aai-validate-report"
        }
    }
}

# --- SUMMARY ---
Write-Host ""
Write-Host "─────────────────────────────────────"
if ($Errors -gt 0) {
    Write-Host "BLOCKED: $Errors error(s), $Warnings warning(s)" -ForegroundColor Red
    Write-Host "Fix errors before committing."
    exit 1
} elseif ($Warnings -gt 0 -and $Strict) {
    Write-Host "BLOCKED (strict mode): $Warnings warning(s)" -ForegroundColor Yellow
    exit 1
} elseif ($Warnings -gt 0) {
    Write-Host "PASS WITH WARNINGS: $Warnings warning(s)" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "ALL CHECKS PASS" -ForegroundColor Green
    exit 0
}
