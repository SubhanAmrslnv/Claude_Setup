# Cortex Windows installer.
# Usage:
#   iwr -useb https://raw.githubusercontent.com/<org>/cortex/main/scripts/install.ps1 | iex

param(
  [string]$Ref = "main",
  [string]$Org = $env:CORTEX_REPO_ORG,
  [string]$Repo = $env:CORTEX_REPO_NAME
)

if (-not $Org)  { $Org  = "SubhanAmrslnv" }
if (-not $Repo) { $Repo = "Cortex" }

$raw = "https://raw.githubusercontent.com/$Org/$Repo/$Ref"
$target = (Get-Location).Path

Write-Host "[cortex] target: $target"

# Bash + curl required on Windows (Git Bash, WSL, or msys). We delegate to install-core.sh.
$bash = (Get-Command bash -ErrorAction SilentlyContinue)
if (-not $bash) {
  Write-Error "bash is required (install Git for Windows or WSL)."
  exit 1
}

$env:CORTEX_REPO_RAW = $raw
$env:CORTEX_TARGET = $target

$tmp = New-TemporaryFile
Invoke-WebRequest "$raw/scripts/lib/install-core.sh" -OutFile $tmp -UseBasicParsing
& bash $tmp.FullName
Remove-Item $tmp
