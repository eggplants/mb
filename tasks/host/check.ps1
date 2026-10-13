#MISE description="Fail unless this machine's env selection (miserc.local.toml) is valid and matches this host"
#MISE hide=true
# The Windows twin of tasks/host/check: on Windows mise runs this file as host:check and drops
# the bash script; elsewhere this file is not executable, so it is no task there (keep it so).
# `--detect` prints this host's platform. The host tests mirror tasks/host/check, guard.tera,
# bootstrap.sh and bootstrap.ps1 (ci/check.sh compares them).
$ErrorActionPreference = 'Stop'
if ($env:OS -eq 'Windows_NT') {
  $hostPlatform = 'windows'
} else {
  $hostPlatform = 'unknown'
}
if ($args[0] -eq '--detect') {
  Write-Output $hostPlatform
  exit 0
}
$sel = "$env:MISE_ENV"
switch -CaseSensitive ($sel) {
  'macos' { $want = 'macos' }
  'termux' { $want = 'termux' }
  { $_ -in 'linux,ubuntu', 'linux,ubuntu,desktop' } { $want = 'ubuntu' }
  'linux,nanopi' { $want = 'nanopi' }
  'windows' { $want = 'windows' }
  default {
    [Console]::Error.WriteLine("host:check: env selection [$sel] is not one of: macos | termux | linux,ubuntu | linux,ubuntu,desktop | linux,nanopi | windows")
    exit 1
  }
}
if ($hostPlatform -ne $want) {
  [Console]::Error.WriteLine("host:check: env [$sel] is for $want, but this host is $hostPlatform")
  exit 1
}
