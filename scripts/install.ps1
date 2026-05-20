# Cortex Windows installer.
# Usage:
#   iwr -useb https://raw.githubusercontent.com/<org>/cortex/main/scripts/install.ps1 | iex

param(
  [string]$Ref = "main",
  [string]$Org = $env:CORTEX_REPO_ORG,
  [string]$Repo = $env:CORTEX_REPO_NAME,
  [string]$RepoUrl = $env:CORTEX_REPO_URL
)

if (-not $Org)  { $Org  = "SubhanAmrslnv" }
if (-not $Repo) { $Repo = "Cortex" }
if (-not $RepoUrl) { $RepoUrl = "https://github.com/$Org/$Repo.git" }

$raw = "https://raw.githubusercontent.com/$Org/$Repo/$Ref"
$target = (Get-Location).Path

Write-Host "[cortex] target: $target"

# Bash + git required on Windows (Git for Windows provides both). install-core.sh does the git clone.
$bash = (Get-Command bash -ErrorAction SilentlyContinue)
if (-not $bash) {
  Write-Error "bash is required (install Git for Windows or WSL)."
  exit 1
}
$git = (Get-Command git -ErrorAction SilentlyContinue)
if (-not $git) {
  Write-Error "git is required (install Git for Windows)."
  exit 1
}

$env:CORTEX_REPO_RAW = $raw
$env:CORTEX_REPO_URL = $RepoUrl
$env:CORTEX_REF      = $Ref
$env:CORTEX_TARGET   = $target

$tmp = New-TemporaryFile
Invoke-WebRequest "$raw/scripts/lib/install-core.sh" -OutFile $tmp -UseBasicParsing
& bash $tmp.FullName
Remove-Item $tmp
