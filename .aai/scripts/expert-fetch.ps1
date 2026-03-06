# expert-fetch.ps1 — Fetch and cache expert subagent prompts from VoltAgent registry
#
# Usage:
#   expert-fetch.ps1 -ExpertKey <key>                     Fetch expert by registry key
#   expert-fetch.ps1 -ExpertKey <key> -Force              Fetch ignoring cache
#   expert-fetch.ps1 -Detect <ext|tech>...                Auto-detect experts
#   expert-fetch.ps1 -Body <expert-key>                   Print prompt body (no frontmatter)
#   expert-fetch.ps1 -List                                List all expert keys
#   expert-fetch.ps1 -Check <expert-key> -Phase <phase>   Check phase eligibility
#
# Exit codes: 0=success, 1=rejected/error, 2=not found

param(
    [string]$ExpertKey,
    [switch]$Force,
    [string[]]$Detect,
    [string]$Body,
    [switch]$List,
    [string]$Check,
    [string]$Phase
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
$Lines = $RegistryContent -split "`n"

# ── -List: dump all expert keys ──
if ($List) {
    foreach ($Line in $Lines) {
        if ($Line -match '^\s{2}([a-z][a-z0-9_-]*):\s*$') {
            Write-Output $Matches[1]
        }
    }
    exit 0
}

# ── -Detect: map extensions/keywords → expert keys ──
if ($Detect.Count -gt 0) {
    $ExtMap = @{
        'ts'='typescript'; 'tsx'='typescript'; 'typescript'='typescript'
        'js'='javascript'; 'jsx'='javascript'; 'javascript'='javascript'
        'py'='python'; 'python'='python'
        'rb'='rails'; 'ruby'='rails'; 'rails'='rails'
        'rs'='rust'; 'rust'='rust'
        'go'='golang'; 'golang'='golang'
        'java'='java'
        'cs'='csharp'; 'csharp'='csharp'
        'swift'='swift'
        'kt'='kotlin'; 'kotlin'='kotlin'
        'dart'='flutter'; 'flutter'='flutter'
        'php'='php'
        'ex'='elixir'; 'exs'='elixir'; 'elixir'='elixir'
        'cpp'='cpp'; 'cc'='cpp'; 'cxx'='cpp'; 'hpp'='cpp'; 'c++'='cpp'
        'sql'='sql'; 'psql'='sql'
        'ps1'='powershell'; 'powershell'='powershell'
        'graphql'='graphql'; 'gql'='graphql'
        'vue'='vue'; 'react'='react'; 'angular'='angular'
        'next'='nextjs'; 'nextjs'='nextjs'
        'django'='django'; 'laravel'='laravel'; 'spring'='spring'
        'dotnet'='dotnet'; '.net'='dotnet'
        'docker'='docker'; 'dockerfile'='docker'
        'k8s'='kubernetes'; 'kubernetes'='kubernetes'
        'terraform'='terraform'; 'tf'='terraform'; 'hcl'='terraform'
        'postgres'='postgres'; 'postgresql'='postgres'
        'security'='security'; 'owasp'='security'
        'performance'='performance'; 'perf'='performance'
        'accessibility'='accessibility'; 'a11y'='accessibility'
        'electron'='electron'; 'websocket'='websocket'; 'ws'='websocket'
        'blockchain'='blockchain'; 'web3'='blockchain'
        'gamedev'='gamedev'; 'game'='gamedev'
        'iot'='iot'; 'embedded'='embedded'; 'fintech'='fintech'
        'payment'='payment'; 'stripe'='payment'
        'seo'='seo'; 'slack'='slack'; 'mcp'='mcp'
        'azure'='azure'; 'aws'='cloud'; 'gcp'='cloud'; 'cloud'='cloud'
    }

    $Matches2 = @()
    foreach ($Token in $Detect) {
        $Normalized = $Token.ToLower().TrimStart('.')
        if ($ExtMap.ContainsKey($Normalized)) {
            $Matches2 += $ExtMap[$Normalized]
        } else {
            # Direct registry lookup
            $InExpert = $false
            foreach ($Line in $Lines) {
                if ($Line -match "^\s{2}${Normalized}:\s*$") { $Matches2 += $Normalized; break }
            }
        }
    }
    $Matches2 | Sort-Object -Unique | Select-Object -First 2 | ForEach-Object { Write-Output $_ }
    exit 0
}

# ── -Check: verify phase eligibility ──
if ($Check) {
    if (-not $Phase) { Write-Error "Usage: -Check <key> -Phase <phase>"; exit 1 }
    $InExpert = $false
    $UseIn = $null
    foreach ($Line in $Lines) {
        if ($Line -match "^\s{2}${Check}:\s*$") { $InExpert = $true; continue }
        if ($InExpert -and $Line -match 'use_in:') { $UseIn = $Line; break }
        if ($InExpert -and $Line -match '^\s{2}[a-z]') { break }
    }
    if (-not $UseIn) { Write-Output "not-found"; exit 2 }
    if ($UseIn -match $Phase) { Write-Output "eligible"; exit 0 }
    else { Write-Output "not-eligible"; exit 1 }
}

# ── -Body: print prompt body without frontmatter ──
if ($Body) {
    $CacheFile = Join-Path $CacheDir "$Body.md"
    if (-not (Test-Path $CacheFile)) {
        Write-Error "Expert '$Body' not cached. Run expert-fetch.ps1 -ExpertKey $Body first."
        exit 1
    }
    $Content = Get-Content $CacheFile -Raw
    # Strip YAML frontmatter (between --- markers)
    if ($Content -match '(?s)^---.*?---\s*(.+)$') {
        Write-Output $Matches[1].Trim()
    } else {
        Write-Output $Content
    }
    exit 0
}

# ── Standard fetch mode ──
if (-not $ExpertKey) {
    Write-Error "Specify -ExpertKey, -Detect, -Body, -Check, or -List"
    exit 1
}

$PinnedSha = if ($RegistryContent -match 'pinned_sha:\s*"([^"]+)"') { $Matches[1] } else { $null }
$MaxBytes = if ($RegistryContent -match 'max_prompt_bytes:\s*(\d+)') { [int]$Matches[1] } else { 8192 }
$RepoName = if ($RegistryContent -match 'repo:\s*(\S+)') { $Matches[1] } else { $null }
$BasePath = if ($RegistryContent -match 'base_path:\s*(\S+)') { $Matches[1] } else { $null }

if (-not $PinnedSha -or -not $RepoName) {
    Write-Error "Invalid registry - missing pinned_sha or repo"
    exit 1
}

# Find expert path
$ExpertPath = $null
$InExpert = $false
foreach ($Line in $Lines) {
    if ($Line -match "^\s{2}${ExpertKey}:\s*$") { $InExpert = $true; continue }
    if ($InExpert -and $Line -match '^\s+path:\s*(.+)$') { $ExpertPath = $Matches[1].Trim(); break }
    if ($InExpert -and $Line -match '^\s{2}[a-z]') { break }
}

if (-not $ExpertPath) { Write-Error "Expert '$ExpertKey' not found in registry"; exit 2 }

# Blocked category check
$Category = ($ExpertPath -split '/')[0]
if ($RegistryContent -match "blocked_categories:[\s\S]*?- $Category") {
    Write-Error "Category '$Category' is blocked in registry"
    exit 1
}

if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null }

$CacheFile = Join-Path $CacheDir "$ExpertKey.md"
$ShaFile = Join-Path $CacheDir ".sha_$ExpertKey"

# Cache check
if (-not $Force -and (Test-Path $CacheFile) -and (Test-Path $ShaFile)) {
    $CachedSha = (Get-Content $ShaFile -Raw).Trim()
    if ($CachedSha -eq $PinnedSha) { Write-Output $CacheFile; exit 0 }
}

# Fetch from pinned SHA
$FullPath = "$BasePath/$ExpertPath"
try {
    $Response = gh api "repos/$RepoName/contents/$($FullPath)?ref=$PinnedSha" --jq '.content' 2>$null
    $Bytes = [System.Convert]::FromBase64String($Response.Trim())
    $Content = [System.Text.Encoding]::UTF8.GetString($Bytes)
} catch {
    Write-Error "Failed to fetch $FullPath at SHA $PinnedSha"
    exit 1
}

# Size check
if ($Content.Length -gt $MaxBytes) {
    Write-Error "REJECTED: Expert prompt too large ($($Content.Length) > $MaxBytes bytes)"
    exit 1
}

# Injection check
$InjectionPatterns = @('ignore.*previous','disregard.*instruction','you are now','forget.*above','override.*system')
foreach ($Pattern in $InjectionPatterns) {
    if ($Content -match $Pattern) { Write-Error "REJECTED: Expert prompt contains injection patterns"; exit 1 }
}

# Strip dangerous patterns
$Content = ($Content -split "`n" |
    Where-Object { $_ -notmatch 'git push|git reset --hard|rm -rf|force.push|--no-verify' }) -join "`n"

$Content | Set-Content -Path $CacheFile -Encoding UTF8 -NoNewline
$PinnedSha | Set-Content -Path $ShaFile -Encoding UTF8 -NoNewline

Write-Output $CacheFile
