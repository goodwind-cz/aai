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

function Write-Error-Check($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; $script:Errors++ }
function Write-Warn-Check($msg)  { Write-Host "WARN: $msg" -ForegroundColor Yellow; $script:Warnings++ }
function Write-Pass-Check($msg)  { Write-Host "PASS: $msg" -ForegroundColor Green }

Write-Host "-------------------------------------"
Write-Host "PRE-COMMIT QUALITY GATES"
Write-Host "-------------------------------------"
Write-Host ""

# --- CHECK 1: TDD Evidence ---
$StateFile = Join-Path $ProjectRoot "docs/ai/STATE.yaml"
if (Test-Path $StateFile) {
    $stateContent = Get-Content $StateFile -Raw
    $stateData = (($stateContent -split "\r?\n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    if ($stateData -match "phase:.*implementation") {
        $validationMatch = [regex]::Match($stateData, "last_validation:\s*([\s\S]*?)(?=\r?\n\S|\z)")
        $validationBlock = if ($validationMatch.Success) { $validationMatch.Groups[1].Value } else { "" }
        if ($validationBlock -notmatch "status:\s*pass") {
            Write-Warn-Check "TDD cycle may be incomplete - active implementation without validation pass"
        } else {
            Write-Pass-Check "TDD evidence appears complete"
        }
    } else {
        Write-Pass-Check "No active implementation phase"
    }
} else {
    Write-Warn-Check "STATE.yaml not found - skipping TDD check"
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

        if ($content -match '(api[_-]?key|api[_-]?secret|password|passwd|secret[_-]?key|access[_-]?token|private[_-]?key)\s*[:=]\s*[\x22\x27][^\x22\x27]{8,}') {
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

        $hits = Select-String -Path $filepath -Pattern 'console\.log|debugger\b|pdb\.set_trace|binding\.pry|var_dump' -ErrorAction SilentlyContinue
        if ($hits) {
            Write-Warn-Check "Debug statements in ${file}:"
            $hits | Select-Object -First 3 | ForEach-Object { Write-Host "    $_" }
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

        $hits = Select-String -Path $filepath -Pattern 'TODO|FIXME|HACK|XXX' -ErrorAction SilentlyContinue
        if ($hits) { $TodoCount += $hits.Count }
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
    $stateData = (($stateContent -split "\r?\n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    if ($stateData -match "phase:.*validation|last_validation:\s*[\s\S]*?status:\s*pass") {
        $reportsDir = Join-Path $ProjectRoot "docs/ai/reports"
        if ((Test-Path $reportsDir) -and (
            (Get-ChildItem "$reportsDir/validation-*.md" -ErrorAction SilentlyContinue) -or
            (Get-ChildItem "$reportsDir/VALIDATION_REPORT_*.md" -ErrorAction SilentlyContinue) -or
            (Test-Path (Join-Path $reportsDir "LATEST.md"))
        )) {
            Write-Pass-Check "Validation report exists"
        } else {
            Write-Warn-Check "No validation report found - consider running /aai-validate-report"
        }
    }
}

# --- CHECK 6: Code Review Gate ---
if (Test-Path $StateFile) {
    $stateContent = Get-Content $StateFile -Raw
    $stateData = (($stateContent -split "\r?\n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    $reviewMatch = [regex]::Match($stateData, "code_review:\s*([\s\S]*?)(?=\r?\n\S|\z)")
    if ($reviewMatch.Success) {
        $reviewBlock = $reviewMatch.Groups[1].Value
        if ($reviewBlock -match "required:\s*true") {
            if ($reviewBlock -match "status:\s*(pass|waived)") {
                Write-Pass-Check "Code review gate satisfied"
            } else {
                Write-Warn-Check "Code review required but not pass/waived"
            }
        }
    }
}

# --- CHECK 7: PowerShell parse gate ---
# A staged .ps1 with a parse error breaks /aai-update et al. silently for the
# next user who runs it. Parse-check every staged .ps1 so a broken script can't
# land. (This runs natively in PowerShell; the bash twin guards macOS/Linux.)
$stagedPs1 = @(git -C $ProjectRoot diff --cached --name-only --diff-filter=ACM 2>$null |
    Where-Object { $_ -match '\.ps1$' })
if ($stagedPs1.Count -gt 0) {
    $ps1Bad = 0
    foreach ($f in $stagedPs1) {
        $full = Join-Path $ProjectRoot $f
        if (-not (Test-Path $full)) { continue }
        $errs = $null
        [System.Management.Automation.Language.Parser]::ParseFile($full, [ref]$null, [ref]$errs) | Out-Null
        if ($errs -and $errs.Count) {
            Write-Error-Check "PowerShell parse error in staged ${f}:"
            $errs | Select-Object -First 3 | ForEach-Object { Write-Host "    $($_.Message)" }
            $ps1Bad++
        }
    }
    if ($ps1Bad -eq 0) { Write-Pass-Check "Staged .ps1 scripts parse cleanly" }
}

# --- CHECK 8: Doc-numbering guards (SPEC-0015 / RFC-0007) ---
# Two predicates, report-only by DEFAULT (mirroring close_gate / body_lint),
# flippable to enforce via docs/ai/docs-audit.yaml `doc_number_guard: enforce`:
#   - no-DRAFT-at-merge: any docs/*/*-DRAFT-*.md or governed `number: null` doc.
#   - duplicate-number: two governed docs resolving to the same TYPE-000N.
$DocNumberGuard = Join-Path $ProjectRoot ".aai/scripts/allocate-doc-number.mjs"
if ((Test-Path $DocNumberGuard) -and (Get-Command node -ErrorAction SilentlyContinue)) {
    $dnMode = "report-only"
    $auditCfg = Join-Path $ProjectRoot "docs/ai/docs-audit.yaml"
    if ((Test-Path $auditCfg) -and ((Get-Content $auditCfg -Raw) -match '(?m)^\s*doc_number_guard:\s*enforce(\s|$)')) {
        $dnMode = "enforce"
    }
    Push-Location $ProjectRoot
    $dnOut = node $DocNumberGuard --guard 2>&1
    $dnOk = ($LASTEXITCODE -eq 0)
    Pop-Location
    if ($dnOk) {
        Write-Pass-Check "Doc-numbering guards clean (no-DRAFT-at-merge + duplicate-number)"
    } elseif ($dnMode -eq "enforce") {
        Write-Error-Check "Doc-numbering guard failed (doc_number_guard: enforce) - commit blocked:"
        $dnOut | ForEach-Object { Write-Host "    $_" }
    } else {
        Write-Warn-Check "Doc-numbering guard found violations (report-only; commit allowed):"
        $dnOut | ForEach-Object { Write-Host "    $_" }
    }
} else {
    Write-Pass-Check "Doc-numbering guard skipped (allocator absent or node unavailable)"
}

# --- SUMMARY ---
Write-Host ""
Write-Host "-------------------------------------"
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
