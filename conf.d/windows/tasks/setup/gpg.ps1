#MISE description="Import the GPG secret key from ~/.sec.key into Git for Windows' gpg"
# Windows twin of shared/tasks/gpg/setup/gpg (bash), without the GPG SSH agent and pass.
# gpg is the one bundled with Git for Windows (keyring ~/.gnupg, pinentry-w32), which is not on
# PowerShell's PATH; on Windows it only signs commits, so Gpg4win is not needed.
$ErrorActionPreference = 'Stop'

$gpg = Join-Path (Split-Path (Split-Path (Get-Command git).Source)) 'usr\bin\gpg.exe'
if (-not (Test-Path $gpg)) { throw "setup:gpg: $gpg not found; is Git for Windows installed?" }

if ((& $gpg --list-secret-keys 2>$null) -match '^ *EE3A') {
  exit 0
}
$key = Join-Path $HOME '.sec.key'
if (-not (Test-Path $key)) {
  Write-Warning 'setup:gpg: skipped (place your GPG secret key at ~/.sec.key and re-run)'
  exit 0
}

& $gpg --import $key
if ($LASTEXITCODE) { throw 'setup:gpg: gpg --import failed' }
# the key is our own: trust it ultimately, as a key made on this machine would be
$fpr = ((& $gpg --with-colons --list-secret-keys) | Select-String '^fpr:' | Select-Object -First 1).Line.Split(':')[9]
"${fpr}:6:" | & $gpg --import-ownertrust
Remove-Item $key
