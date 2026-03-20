param()

$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$fixture = Join-Path $root "tests\fixtures\target-project"
$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("aai-self-hosting-" + [System.Guid]::NewGuid().ToString("N"))
$target = Join-Path $tmpRoot "target-project"

try {
  New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
  Copy-Item $fixture $target -Recurse -Force

  & (Join-Path $root ".aai\scripts\aai-sync.ps1") -TargetRoot $target | Out-Null

  foreach ($path in @(
    ".aai\templates\TECHNOLOGY_TEMPLATE.md",
    ".aai\system\SELF_HOSTING.md",
    "docs\TECHNOLOGY.md"
  )) {
    if (!(Test-Path (Join-Path $target $path))) {
      throw "Missing expected path: $path"
    }
  }

  $technology = Get-Content -Raw (Join-Path $target "docs\TECHNOLOGY.md")
  if ($technology -notmatch "AAI-TEMPLATE: TECHNOLOGY_TEMPLATE v1") {
    throw "Seeded docs/TECHNOLOGY.md is missing template marker."
  }

  $gitignore = Get-Content -Raw (Join-Path $target ".gitignore")
  if ($gitignore -notmatch [regex]::Escape("docs/ai/reports/**")) {
    throw "Target .gitignore is missing runtime reports ignore rule."
  }
  if ($gitignore -notmatch [regex]::Escape("!docs/ai/reports/.gitkeep")) {
    throw "Target .gitignore is missing reports placeholder exception."
  }

  & (Join-Path $root ".aai\scripts\validate-skills.ps1") -TargetRoot $target | Out-Null

  Write-Output "PASS: self-hosting smoke"
}
finally {
  if (Test-Path $tmpRoot) {
    Remove-Item $tmpRoot -Recurse -Force
  }
}
