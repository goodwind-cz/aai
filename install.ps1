[CmdletBinding()]
param(
  [string]$Repo = $env:AAI_REPO,
  [string]$Ref = $env:AAI_REF,
  [string]$TargetRoot = $env:AAI_TARGET_ROOT,
  [string]$SourceRoot = $env:AAI_SOURCE_ROOT,
  [switch]$KeepTemp
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Repo)) {
  $Repo = "goodwind-cz/aai"
}
if ([string]::IsNullOrWhiteSpace($Ref)) {
  $Ref = "main"
}
if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
  $TargetRoot = (Get-Location).Path
}

function Resolve-ExistingDirectory {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Label
  )

  if (!(Test-Path -LiteralPath $Path -PathType Container)) {
    throw "$Label directory does not exist: $Path"
  }
  return (Resolve-Path -LiteralPath $Path).Path
}

function Get-SyncScript {
  param(
    [Parameter(Mandatory=$true)][string]$Root
  )

  $syncScript = Join-Path $Root ".aai\scripts\aai-sync.ps1"
  if (!(Test-Path -LiteralPath $syncScript -PathType Leaf)) {
    throw "AAI sync script not found: $syncScript"
  }
  return $syncScript
}

function Invoke-AaiDownload {
  param(
    [Parameter(Mandatory=$true)][string]$RepoSlug,
    [Parameter(Mandatory=$true)][string]$GitRef,
    [Parameter(Mandatory=$true)][string]$TempRoot
  )

  if ($RepoSlug -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    throw "Repo must be a GitHub owner/repo slug, for example goodwind-cz/aai. Received: $RepoSlug"
  }
  if ($GitRef -match '[\r\n]') {
    throw "Ref must not contain newline characters."
  }

  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  } catch {
    # PowerShell Core does not require this; Windows PowerShell 5.1 often does.
  }

  $zipPath = Join-Path $TempRoot "aai.zip"
  $url = "https://codeload.github.com/$RepoSlug/zip/$GitRef"

  Write-Host "Downloading AAI from $url"

  $webRequestArgs = @{
    Uri = $url
    OutFile = $zipPath
    ErrorAction = "Stop"
  }
  if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey("UseBasicParsing")) {
    $webRequestArgs["UseBasicParsing"] = $true
  }

  Invoke-WebRequest @webRequestArgs
  Expand-Archive -Path $zipPath -DestinationPath $TempRoot -Force

  $source = Get-ChildItem -LiteralPath $TempRoot -Directory -Force |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName ".aai\scripts\aai-sync.ps1") -PathType Leaf } |
    Select-Object -First 1

  if (!$source) {
    throw "Downloaded archive does not contain .aai\scripts\aai-sync.ps1"
  }

  return $source.FullName
}

$TargetRoot = Resolve-ExistingDirectory -Path $TargetRoot -Label "Target"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("aai-install-" + [System.Guid]::NewGuid().ToString("N"))
$tempCreated = $false

try {
  if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $tempCreated = $true
    $SourceRoot = Invoke-AaiDownload -RepoSlug $Repo -GitRef $Ref -TempRoot $tempRoot
  } else {
    $SourceRoot = Resolve-ExistingDirectory -Path $SourceRoot -Label "Source"
  }

  $syncScript = Get-SyncScript -Root $SourceRoot

  Write-Host "Installing AAI into: $TargetRoot"
  & $syncScript -TargetRoot $TargetRoot

  foreach ($path in @(
    ".aai\AGENTS.md",
    ".aai\workflow\WORKFLOW.md",
    ".aai\scripts\aai-sync.ps1",
    "CODEX.md",
    "SKILLS.md"
  )) {
    if (!(Test-Path -LiteralPath (Join-Path $TargetRoot $path))) {
      throw "Install verification failed. Missing expected path: $path"
    }
  }

  Write-Host ""
  Write-Host "AAI installed."
  Write-Host "Next:"
  Write-Host "  git status"
  Write-Host "  git diff"
  Write-Host "  /aai-bootstrap"
  Write-Host "  /aai-doctor"
} finally {
  if ($tempCreated -and !$KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  } elseif ($tempCreated -and $KeepTemp) {
    Write-Host "Kept temporary installer files at: $tempRoot"
  }
}
