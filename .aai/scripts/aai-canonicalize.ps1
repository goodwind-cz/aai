param(
  [string]$TargetRoot = (Get-Location).Path,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
  param([string]$Path)
  return (Resolve-Path $Path).Path
}

function Ensure-Directory {
  param(
    [string]$Path,
    [bool]$Dry
  )
  if (Test-Path $Path) { return }
  if ($Dry) {
    Write-Host "DRYRUN create dir: $Path"
    return
  }
  New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Move-Safely {
  param(
    [string]$Source,
    [string]$Destination,
    [bool]$Dry
  )
  if (!(Test-Path $Source)) { return $false }
  $parent = Split-Path -Parent $Destination
  Ensure-Directory -Path $parent -Dry $Dry
  if ($Dry) {
    Write-Host "DRYRUN move: $Source -> $Destination"
    return $true
  }
  Move-Item -Path $Source -Destination $Destination -Force
  return $true
}

function Detect-Architecture {
  param([string]$Root)
  $detected = [ordered]@{
    languages = @()
    package_managers = @()
    test_tools = @()
    build_tools = @()
    ci = @()
  }

  if (Test-Path (Join-Path $Root "package.json")) {
    $detected.languages += "JavaScript/TypeScript"
    $detected.package_managers += "npm/pnpm/yarn (package.json)"
  }
  if ((Test-Path (Join-Path $Root "pyproject.toml")) -or (Test-Path (Join-Path $Root "requirements.txt"))) {
    $detected.languages += "Python"
    $detected.package_managers += "pip/poetry (python manifests)"
  }
  if (Test-Path (Join-Path $Root "go.mod")) {
    $detected.languages += "Go"
    $detected.package_managers += "go modules"
  }
  if (Test-Path (Join-Path $Root "Cargo.toml")) {
    $detected.languages += "Rust"
    $detected.package_managers += "cargo"
  }
  if ((Test-Path (Join-Path $Root "pom.xml")) -or (Test-Path (Join-Path $Root "build.gradle"))) {
    $detected.languages += "Java"
    $detected.package_managers += "maven/gradle"
  }

  $testFiles = @(
    "playwright.config.ts", "playwright.config.js", "cypress.config.ts", "cypress.config.js",
    "jest.config.ts", "jest.config.js", "vitest.config.ts", "vitest.config.js", "pytest.ini"
  )
  foreach ($f in $testFiles) {
    if (Test-Path (Join-Path $Root $f)) { $detected.test_tools += $f }
  }

  $buildFiles = @(
    "vite.config.ts", "vite.config.js", "webpack.config.js", "tsconfig.json", "Dockerfile"
  )
  foreach ($f in $buildFiles) {
    if (Test-Path (Join-Path $Root $f)) { $detected.build_tools += $f }
  }

  if (Test-Path (Join-Path $Root ".github/workflows")) {
    $detected.ci += ".github/workflows"
  }

  $keys = @($detected.Keys)
  foreach ($k in $keys) {
    $detected[$k] = @($detected[$k] | Sort-Object -Unique)
  }
  return $detected
}

$repoRoot = Resolve-RepoRoot -Path $TargetRoot
Write-Host "Canonicalizing AAI repository: $repoRoot"

$timestampUtc = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$reportDateUtc = (Get-Date).ToUniversalTime().ToString("o")
$reportPath = Join-Path $repoRoot "docs/ai/reports/MIGRATION_REPORT_$timestampUtc.md"
$techPath = Join-Path $repoRoot "docs/TECHNOLOGY.md"
$migratedRoot = Join-Path $repoRoot "docs/ai/reports/migrated/$timestampUtc"

$canonicalDirs = @(
  "ai",
  "docs",
  "docs/ai",
  "docs/ai/reports",
  "docs/knowledge",
  "docs/templates",
  "docs/workflow",
  "docs/roles",
  "docs/issues",
  "docs/specs",
  "docs/requirements",
  "docs/releases",
  "docs/rfc",
  "scripts",
  ".claude/skills",
  ".codex/skills",
  ".gemini/skills"
)
foreach ($d in $canonicalDirs) {
  Ensure-Directory -Path (Join-Path $repoRoot $d) -Dry $DryRun.IsPresent
}

$migrations = @()

# 1) Migrate legacy YAML runtime telemetry into JSONL if the helper exists.
$yamlLoop = Join-Path $repoRoot "docs/ai/LOOP_TICKS.yaml"
$yamlMetrics = Join-Path $repoRoot "docs/ai/METRICS.yaml"
$yamlMigrationScript = Join-Path $repoRoot ".aai/scripts/migrate-yaml-to-jsonl.ps1"
if ((Test-Path $yamlMigrationScript) -and ((Test-Path $yamlLoop) -or (Test-Path $yamlMetrics))) {
  if ($DryRun) {
    Write-Host "DRYRUN migrate yaml->jsonl: powershell -File $yamlMigrationScript -TargetRoot `"$repoRoot`""
  } else {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $yamlMigrationScript -TargetRoot $repoRoot
  }
  $migrations += "Migrated YAML runtime files into JSONL format."
}

# 2) Remove legacy runtime YAML files after successful migration to JSONL.
if (Test-Path $yamlLoop) {
  if ($DryRun) {
    Write-Host "DRYRUN remove: $yamlLoop"
  } else {
    Remove-Item -Path $yamlLoop -Force
  }
  $migrations += "Removed legacy docs/ai/LOOP_TICKS.yaml after JSONL migration."
}
if (Test-Path $yamlMetrics) {
  if ($DryRun) {
    Write-Host "DRYRUN remove: $yamlMetrics"
  } else {
    Remove-Item -Path $yamlMetrics -Force
  }
  $migrations += "Removed legacy docs/ai/METRICS.yaml after JSONL migration."
}

# 3) Move unsupported docs/* folders into canonical migrated location.
$supportedDocsDirs = @("ai", "workflow", "roles", "templates", "knowledge", "issues", "specs", "requirements", "releases", "rfc")
$docsRoot = Join-Path $repoRoot "docs"
if (Test-Path $docsRoot) {
  Get-ChildItem -Path $docsRoot -Directory | ForEach-Object {
    if ($supportedDocsDirs -notcontains $_.Name) {
      $src = $_.FullName
      $dst = Join-Path $migratedRoot ("docs/" + $_.Name)
      if (Move-Safely -Source $src -Destination $dst -Dry $DryRun.IsPresent) {
        $migrations += "Moved unsupported directory docs/$($_.Name) -> docs/ai/reports/migrated/$timestampUtc/docs/$($_.Name)"
      }
    }
  }
}

# 4) Move common legacy evidence folders into canonical docs/ai/reports/migrated.
$legacyEvidenceDirs = @("validation", "evidence", "reports")
foreach ($dir in $legacyEvidenceDirs) {
  $rootCandidate = Join-Path $repoRoot $dir
  if (Test-Path $rootCandidate) {
    $dst = Join-Path $migratedRoot ("legacy-root/" + $dir)
    if (Move-Safely -Source $rootCandidate -Destination $dst -Dry $DryRun.IsPresent) {
      $migrations += "Moved root-level legacy evidence directory $dir/ -> docs/ai/reports/migrated/$timestampUtc/legacy-root/$dir/"
    }
  }
}

# 5) Create or refresh architecture summary in docs/TECHNOLOGY.md.
$arch = Detect-Architecture -Root $repoRoot
$techContent = @"
# Technology Contract

Generated at (UTC): $reportDateUtc
Generator: .aai/scripts/aai-canonicalize.ps1

## Languages
$(
  if ($arch.languages.Count -gt 0) { ($arch.languages | ForEach-Object { "- $_" }) -join "`n" }
  else { "- Unknown (no common manifest detected)" }
)

## Package/Dependency Managers
$(
  if ($arch.package_managers.Count -gt 0) { ($arch.package_managers | ForEach-Object { "- $_" }) -join "`n" }
  else { "- Not detected" }
)

## Test Tooling (Detected by Files)
$(
  if ($arch.test_tools.Count -gt 0) { ($arch.test_tools | ForEach-Object { "- $_" }) -join "`n" }
  else { "- Not detected" }
)

## Build/Runtime Tooling (Detected by Files)
$(
  if ($arch.build_tools.Count -gt 0) { ($arch.build_tools | ForEach-Object { "- $_" }) -join "`n" }
  else { "- Not detected" }
)

## CI/CD Signals
$(
  if ($arch.ci.Count -gt 0) { ($arch.ci | ForEach-Object { "- $_" }) -join "`n" }
  else { "- Not detected" }
)

## Notes
- This is an inferred summary based on repository files.
- Refine this contract with .aai/TECH_EXTRACT.prompt.md when deeper accuracy is required.
"@

if ($DryRun) {
  Write-Host "DRYRUN write: $techPath"
} else {
  Set-Content -Path $techPath -Value $techContent -Encoding utf8
}
$migrations += "Updated docs/TECHNOLOGY.md from repository structure."

# 6) Write migration report with evidence pointers.
$report = @"
# AAI Canonicalization Report

- Generated at (UTC): $reportDateUtc
- Target root: $repoRoot
- DryRun: $($DryRun.IsPresent)

## Actions
$(
  if ($migrations.Count -gt 0) { ($migrations | ForEach-Object { "- $_" }) -join "`n" }
  else { "- No migration actions were necessary." }
)

## Canonical Outputs
- docs/TECHNOLOGY.md
- docs/ai/METRICS.jsonl
- docs/ai/LOOP_TICKS.jsonl
- docs/ai/reports/

## Migrated Legacy Content
$(
  $migratedItems = @($migrations | Where-Object { $_ -like "Moved*" })
  if ($migratedItems.Count -gt 0) { ($migratedItems | ForEach-Object { "- $_" }) -join "`n" }
  else { "- No legacy directories required migration." }
)

## Follow-up
- Run .aai/SKILL_CHECK_STATE.prompt.md to verify state invariants.
- Run .aai/ORCHESTRATION.prompt.md to continue normal workflow.
"@

if ($DryRun) {
  Write-Host "DRYRUN write: $reportPath"
} else {
  Set-Content -Path $reportPath -Value $report -Encoding utf8
}

Write-Host "Done."
Write-Host "Report: $reportPath"
