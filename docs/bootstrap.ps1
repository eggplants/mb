# First-time setup of a Windows machine from eggplants/mb; the twin of bootstrap.sh.
# Later runs: mb (pwsh/profile.ps1). Run it as yourself, not as Administrator: installers raise
# their own UAC prompts. It works in Windows PowerShell 5.1 and in PowerShell 7:
#
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/eggplants/mb/main/docs/bootstrap.ps1))) [mise bootstrap args]
#
# Installs Git, mise and PowerShell 7 with WinGet when missing, clones this repo to
# ~/.config/mise (unless it is already there), pins env = ["windows"] in miserc.local.toml
# (unless one exists), then runs `mise bootstrap`.
# The host tests mirror tasks/host/check(.ps1), guard.tera and bootstrap.sh (ci/check.sh compares them).
$ErrorActionPreference = 'Stop'

$repo = 'https://github.com/eggplants/mb.git'
$configDir = Join-Path $HOME '.config\mise'
# throw, not exit: run as a script block, exit would close the calling shell
function Die([string]$msg) { throw "bootstrap.ps1: $msg" }
function Update-SessionPath {
  # pick up what the installers added, without a new shell
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

if ((Test-Path Env:MISE_ENV) -or (Test-Path Env:MISE_PROFILE) -or (Test-Path Env:MISE_ENVIRONMENT)) {
  Die 'unset MISE_ENV / MISE_PROFILE / MISE_ENVIRONMENT first'
}
if ($env:OS -ne 'Windows_NT') { Die 'this is the Windows bootstrap; elsewhere run bootstrap.sh' }
$envList = '["windows"]'

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Die 'winget not found; install App Installer from the Microsoft Store first'
}

# repos need git, and mise starts the .ps1 tasks with pwsh, which must be on PATH before mise runs
foreach ($id in 'Git.Git', 'jdx.mise', 'Microsoft.PowerShell') {
  winget list --id $id --exact --accept-source-agreements | Out-Null
  if ($LASTEXITCODE) {
    winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE) { Die "winget install $id failed" }
  }
}
Update-SessionPath

if (-not (Test-Path $configDir)) {
  git clone $repo $configDir
  if ($LASTEXITCODE) { Die "git clone $repo failed" }
} elseif ((git -C $configDir config --get remote.origin.url) -notmatch 'eggplants/(mb|mise-bootstrap)(\.git)?/?$') {
  Die "$configDir exists and is not a checkout of $repo; move it away first"
}
$miserc = Join-Path $configDir 'miserc.local.toml'
# UTF-8 without a BOM (Set-Content -Encoding utf8 adds one in Windows PowerShell)
if (-not (Test-Path $miserc)) { [IO.File]::WriteAllText($miserc, "env = $envList`n") }

# WinGet's jdx.mise can trail the min_version that config.toml requires
$min = [version][regex]::Match((Get-Content (Join-Path $configDir 'config.toml') -Raw), '(?m)^min_version = "([0-9.]+)"').Groups[1].Value
function Get-MiseVersion {
  $v = [regex]::Match("$(mise --version)", '^[0-9]+\.[0-9]+\.[0-9]+').Value
  if ($v) { [version]$v } else { [version]'0.0.0' }
}
$have = Get-MiseVersion
if ($have -lt $min) {
  winget upgrade --id jdx.mise --exact --silent --accept-package-agreements --accept-source-agreements
  Update-SessionPath
  $have = Get-MiseVersion
  if ($have -lt $min) {
    Die "mise $have is older than min_version $min, and WinGet has nothing newer yet; install mise by hand (https://mise.jdx.dev/installing-mise.html#windows-manual) or wait, then run this again"
  }
}

# from ~: a project mise.toml / .miserc.toml in the cwd would join the run
Set-Location $HOME
mise bootstrap @args
if ($LASTEXITCODE) { throw "bootstrap.ps1: mise bootstrap failed (exit $LASTEXITCODE)" }
