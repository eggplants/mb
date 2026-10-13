#MISE description="Install the PowerShell modules and load conf.d/windows/pwsh/profile.ps1 from $PROFILE"
# PowerShell 7 (pwsh) only. $PROFILE lives under Documents, which OneDrive may move, so this
# writes a one-line loader there instead of declaring a [dotfiles] target; the profile itself
# stays in the repo, and anything else in $PROFILE stays machine-local.
$ErrorActionPreference = 'Stop'

foreach ($m in 'PSColors') {
  if (-not (Get-Module -ListAvailable -Name $m)) {
    Install-Module $m -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck
  }
}

$profilePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1'
$loader = '. "$HOME\.config\mise\conf.d\windows\pwsh\profile.ps1"'
if (-not ((Test-Path $profilePath) -and (Select-String -Path $profilePath -SimpleMatch -Quiet -Pattern $loader))) {
  New-Item -ItemType Directory -Force (Split-Path $profilePath) | Out-Null
  Add-Content -Path $profilePath -Value $loader
  Write-Output "setup:pwsh: added the loader to $profilePath"
}
