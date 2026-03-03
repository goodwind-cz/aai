param(
  [Parameter(Mandatory=$true)]
  [string]$DocumentPath
)

$ErrorActionPreference = "Stop"

if (!(Test-Path $DocumentPath)) {
  throw "Document not found: $DocumentPath"
}

$documentName = [System.IO.Path]::GetFileNameWithoutExtension($DocumentPath)
$publishDir = ".cloudflare-publish"

# Ensure clean publish dir
if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }
New-Item -ItemType Directory -Path $publishDir | Out-Null

Write-Host "Converting Markdown to HTML..."
node "$PSScriptRoot/share-convert.mjs" $DocumentPath $publishDir
if ($LASTEXITCODE -ne 0) { throw "Conversion failed" }

# Check for wrangler
if (!(Get-Command wrangler -ErrorAction SilentlyContinue)) {
  Remove-Item $publishDir -Recurse -Force
  throw "wrangler not found. Install: npm install -g wrangler"
}

# Derive branch name from git repo name (isolates projects in CF Pages)
$repoRoot = try { git rev-parse --show-toplevel 2>$null } catch { $PWD.Path }
$branchName = (Split-Path $repoRoot -Leaf).ToLower() -replace '[^a-z0-9-]', '-'

# Deploy to Cloudflare Pages
Write-Host "Deploying to Cloudflare Pages (branch: $branchName)..."
$projectName = "aai-reports"

$deployOutput = & wrangler pages deploy $publishDir --project-name=$projectName --branch=$branchName 2>&1 | Out-String

# Extract URL
$publishedUrl = [regex]::Match($deployOutput, 'https://[^\s]+\.pages\.dev').Value

if (!$publishedUrl) {
  Remove-Item $publishDir -Recurse -Force
  throw "Deployment failed or URL not found: $deployOutput"
}

$sizeKb = [math]::Round((Get-ChildItem $publishDir -Recurse | Measure-Object -Property Length -Sum).Sum / 1KB, 2)

# Cleanup
Remove-Item $publishDir -Recurse -Force

# Save record
New-Item -ItemType Directory -Path "docs/ai/published" -Force | Out-Null
$record = @{
  timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  document = $DocumentPath
  url = $publishedUrl
  size_kb = $sizeKb
} | ConvertTo-Json -Compress
Add-Content -Path "docs/ai/published/history.jsonl" -Value $record

Write-Host ""
Write-Host "Document published successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Document: $documentName"
Write-Host "URL: $publishedUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "Click to open: $publishedUrl" -ForegroundColor Cyan
Write-Host ""
