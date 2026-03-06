# expert-fetch.ps1 — Fetch and cache expert subagent prompts from VoltAgent registry
# Usage: expert-fetch.ps1 -ExpertKey <key> [-Force]
#
# Returns: path to cached expert prompt file
# Exit codes: 0=success, 1=rejected/error, 2=not found

param(
    [Parameter(Mandatory)]
    [string]$ExpertKey,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path "$ScriptDir\..\..").Path
$Registry = Join-Path $RepoRoot '.aai\system\EXPERT_REGISTRY.yaml'
$CacheDir = Join-Path $RepoRoot '.aai\cache\experts'

if (-not (Test-Path $Registry)) {
    Write-Error "Registry not found at $Registry"
    exit 1
}

$RegistryContent = Get-Content $Registry -Raw

# Parse registry values
$PinnedSha = if ($RegistryContent -match 'pinned_sha:\s*"([^"]+)"') { $Matches[1] } else { $null }
$MaxBytes = if ($RegistryContent -match 'max_prompt_bytes:\s*(\d+)') { [int]$Matches[1] } else { 8192 }
$RepoName = if ($RegistryContent -match 'repo:\s*(\S+)') { $Matches[1] } else { $null }
$BasePath = if ($RegistryContent -match 'base_path:\s*(\S+)') { $Matches[1] } else { $null }

if (-not $PinnedSha -or -not $RepoName) {
    Write-Error "Invalid registry - missing pinned_sha or repo"
    exit 1
}

# Find expert path
$Lines = $RegistryContent -split "`n"
$ExpertPath = $null
$InExpert = $false
foreach ($Line in $Lines) {
    if ($Line -match "^\s{2}${ExpertKey}:\s*$") {
        $InExpert = $true
        continue
    }
    if ($InExpert -and $Line -match '^\s+path:\s*(.+)$') {
        $ExpertPath = $Matches[1].Trim()
        break
    }
    if ($InExpert -and $Line -match '^\s{2}[a-z]') {
        break
    }
}

if (-not $ExpertPath) {
    Write-Error "Expert '$ExpertKey' not found in registry"
    exit 2
}

# Check blocked categories
$Category = ($ExpertPath -split '/')[0]
if ($RegistryContent -match "blocked_categories:[\s\S]*?- $Category") {
    Write-Error "Category '$Category' is blocked in registry"
    exit 1
}

if (-not (Test-Path $CacheDir)) {
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
}

$CacheFile = Join-Path $CacheDir "$ExpertKey.md"
$ShaFile = Join-Path $CacheDir ".sha_$ExpertKey"

# Cache check
if (-not $Force -and (Test-Path $CacheFile) -and (Test-Path $ShaFile)) {
    $CachedSha = Get-Content $ShaFile -Raw
    if ($CachedSha.Trim() -eq $PinnedSha) {
        Write-Output $CacheFile
        exit 0
    }
}

# Fetch from pinned SHA
$FullPath = "$BasePath/$ExpertPath"
try {
    $Response = gh api "repos/$RepoName/contents/$($FullPath)?ref=$PinnedSha" --jq '.content' 2>$null
    $Bytes = [System.Convert]::FromBase64String($Response.Trim())
    $Content = [System.Text.Encoding]::UTF8.GetString($Bytes)
}
catch {
    Write-Error "Failed to fetch $FullPath at SHA $PinnedSha"
    exit 1
}

# Size check
if ($Content.Length -gt $MaxBytes) {
    Write-Error "REJECTED: Expert prompt too large ($($Content.Length) > $MaxBytes bytes)"
    exit 1
}

# Injection pattern check
$InjectionPatterns = @(
    'ignore.*previous',
    'disregard.*instruction',
    'you are now',
    'forget.*above',
    'override.*system'
)
foreach ($Pattern in $InjectionPatterns) {
    if ($Content -match $Pattern) {
        Write-Error "REJECTED: Expert prompt contains injection patterns"
        exit 1
    }
}

# Strip dangerous patterns
$Content = ($Content -split "`n" |
    Where-Object { $_ -notmatch 'git push|git reset --hard|rm -rf|force.push|--no-verify' }) -join "`n"

# Write cache
$Content | Set-Content -Path $CacheFile -Encoding UTF8 -NoNewline
$PinnedSha | Set-Content -Path $ShaFile -Encoding UTF8 -NoNewline

Write-Output $CacheFile
