param(
  [Parameter(Mandatory=$true)]
  [string]$DocumentPath
)

$ErrorActionPreference = "Stop"

if (!(Test-Path $DocumentPath)) {
  throw "Document not found: $DocumentPath"
}

$documentDir = Split-Path $DocumentPath -Parent
$documentName = [System.IO.Path]::GetFileNameWithoutExtension($DocumentPath)
$documentTitle = $documentName

$publishDir = ".cloudflare-publish-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $publishDir | Out-Null

Write-Host "📦 Preparing document for publishing..."

# HTML template
$htmlTemplate = @'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>DOCUMENT_TITLE_PLACEHOLDER</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
      line-height: 1.6;
      color: #24292e;
      background-color: #ffffff;
      max-width: 900px;
      margin: 40px auto;
      padding: 20px;
    }
    h1, h2, h3, h4, h5, h6 {
      margin-top: 24px;
      margin-bottom: 16px;
      font-weight: 600;
      line-height: 1.25;
    }
    h1 { font-size: 2em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
    h2 { font-size: 1.5em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
    h3 { font-size: 1.25em; }
    code {
      background-color: rgba(27,31,35,0.05);
      border-radius: 3px;
      padding: 0.2em 0.4em;
      font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
      font-size: 85%;
    }
    pre {
      background-color: #f6f8fa;
      border-radius: 6px;
      padding: 16px;
      overflow: auto;
      line-height: 1.45;
    }
    pre code {
      background-color: transparent;
      padding: 0;
      font-size: 100%;
    }
    img {
      max-width: 100%;
      height: auto;
      border-radius: 6px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.12);
      margin: 20px 0;
    }
    table {
      border-collapse: collapse;
      width: 100%;
      margin: 20px 0;
    }
    table th, table td {
      border: 1px solid #dfe2e5;
      padding: 6px 13px;
    }
    table tr:nth-child(2n) {
      background-color: #f6f8fa;
    }
    blockquote {
      border-left: 4px solid #dfe2e5;
      padding: 0 15px;
      color: #6a737d;
      margin: 20px 0;
    }
    a {
      color: #0366d6;
      text-decoration: none;
    }
    a:hover {
      text-decoration: underline;
    }
    .timestamp {
      color: #6a737d;
      font-size: 0.9em;
      margin-top: 40px;
      padding-top: 20px;
      border-top: 1px solid #eaecef;
    }
  </style>
</head>
<body>
CONTENT_PLACEHOLDER
  <div class="timestamp">
    Published: TIMESTAMP_PLACEHOLDER<br>
    Source: SOURCE_PATH_PLACEHOLDER
  </div>
</body>
</html>
'@

# Basic markdown conversion (simplified)
Write-Host "📝 Converting Markdown..."
$content = Get-Content $DocumentPath -Raw
$content = $content -replace '(?m)^# (.+)$', '<h1>$1</h1>'
$content = $content -replace '(?m)^## (.+)$', '<h2>$1</h2>'
$content = $content -replace '(?m)^### (.+)$', '<h3>$1</h3>'
$content = $content -replace '(?m)^(.+)$', '<p>$1</p>'

# Replace placeholders
$html = $htmlTemplate -replace 'DOCUMENT_TITLE_PLACEHOLDER', $documentTitle
$html = $html -replace 'TIMESTAMP_PLACEHOLDER', (Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')
$html = $html -replace 'SOURCE_PATH_PLACEHOLDER', $DocumentPath
$html = $html -replace 'CONTENT_PLACEHOLDER', $content

$html | Out-File -FilePath "$publishDir/index.html" -Encoding UTF8

# Copy images
Write-Host "🖼️  Processing images..."
$imageCount = 0
$mdContent = Get-Content $DocumentPath -Raw
$imageMatches = [regex]::Matches($mdContent, '!\[.*?\]\(([^)]+)\)')
foreach ($match in $imageMatches) {
  $imgPath = $match.Groups[1].Value
  $fullImgPath = Join-Path $documentDir $imgPath
  if (Test-Path $fullImgPath) {
    $imgDir = Split-Path $imgPath -Parent
    if ($imgDir) {
      New-Item -ItemType Directory -Path "$publishDir/$imgDir" -Force | Out-Null
    }
    Copy-Item $fullImgPath -Destination "$publishDir/$imgPath"
    $imageCount++
  }
}
Write-Host "   Found $imageCount images"

# Check for wrangler
if (!(Get-Command wrangler -ErrorAction SilentlyContinue)) {
  throw "wrangler not found. Install: npm install -g wrangler"
}

# Publish
Write-Host "🚀 Publishing to Cloudflare Pages..."
$projectName = "ai-os-reports"

$publishOutput = & wrangler pages publish $publishDir --project-name=$projectName --branch=main 2>&1 | Out-String

# Extract URL
$publishedUrl = [regex]::Match($publishOutput, 'https://[^\s]+\.pages\.dev').Value

if (!$publishedUrl) {
  throw "Publishing failed or URL not found: $publishOutput"
}

# Calculate size
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

# Output
Write-Host ""
Write-Host "✅ Document published successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "📄 Document: $documentName"
Write-Host "🔗 URL: $publishedUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "Click to open: $publishedUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "Details:"
Write-Host "- Images: $imageCount"
Write-Host "- Size: $sizeKb KB"
Write-Host ""
