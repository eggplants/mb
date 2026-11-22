#MISE description="Point the bw CLI at bw.egpl.dev and import its client certificate from ~/.bw.p12"
#MISE raw=true
# Windows twin of shared/tasks/bitwarden/setup/bitwarden (bash). The certificate goes into the
# user's store (CurrentUser\My), where Chrome, Edge and the desktop app look for it; cert.pem and
# key.pem are for the bw CLI (dotfiles/bw-mtls/preload.cjs, bw in pwsh/profile.ps1).
$ErrorActionPreference = 'Stop'

$server = 'https://bw.egpl.dev'
$p12 = Join-Path $HOME '.bw.p12'
$dir = Join-Path $HOME '.config\bw-mtls'

# bw keeps its data per server and refuses to switch while logged in to another one
if (Get-Command bw -ErrorAction SilentlyContinue) {
  if ((& bw config server 2>$null) -ne $server) {
    & bw config server $server | Out-Null
    if ($LASTEXITCODE) { Write-Warning 'setup:bitwarden: bw is logged in to another server; run `bw logout`, then re-run' }
  }
}

if (-not (Test-Path $p12)) {
  Write-Warning 'setup:bitwarden: no client certificate (place the .p12 for bw.egpl.dev at ~/.bw.p12 and re-run)'
  exit 0
}
$sum = (Get-FileHash $p12 -Algorithm SHA256).Hash.ToLowerInvariant()
$mark = Join-Path $dir 'p12.sha256'
if ((Test-Path $mark) -and (Get-Content $mark -Raw).Trim() -eq $sum) {
  exit 0
}
if ([Console]::IsInputRedirected) {
  Write-Warning 'setup:bitwarden: ~/.bw.p12 is new, but there is no terminal to ask its password on; re-run from one'
  exit 0
}

# OpenSSL 3 from Git for Windows, as setup:gpg uses its gpg
$git = Split-Path (Split-Path (Get-Command git).Source)
$openssl = 'mingw64\bin\openssl.exe', 'usr\bin\openssl.exe' |
  ForEach-Object { Join-Path $git $_ } | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $openssl) { throw "setup:bitwarden: no openssl.exe under $git; is Git for Windows installed?" }

$pw = Read-Host 'setup:bitwarden: password of ~/.bw.p12' -AsSecureString
New-Item -ItemType Directory -Force $dir | Out-Null
$certNew = Join-Path $dir 'cert.pem.new'
$keyNew = Join-Path $dir 'key.pem.new'
# openssl reads it from the environment of this process, not from its arguments
$env:BW_P12_PASSWORD = [Net.NetworkCredential]::new('', $pw).Password
try {
  & $openssl pkcs12 -in $p12 -passin env:BW_P12_PASSWORD -clcerts -nokeys -out $certNew 2>$null
  if ($LASTEXITCODE) {
    Remove-Item -ErrorAction SilentlyContinue $certNew
    throw 'setup:bitwarden: cannot open ~/.bw.p12 (wrong password?)'
  }
  & $openssl pkcs12 -in $p12 -passin env:BW_P12_PASSWORD -nocerts -noenc -out $keyNew 2>$null
  if ($LASTEXITCODE) { throw 'setup:bitwarden: cannot extract the key from ~/.bw.p12' }
} finally {
  Remove-Item Env:BW_P12_PASSWORD
}
Move-Item -Force $certNew (Join-Path $dir 'cert.pem')
Move-Item -Force $keyNew (Join-Path $dir 'key.pem')

# the last import, which a renewed .p12 replaces, goes with its key
$last = Join-Path $dir 'store.thumbprint'
if (Test-Path $last) {
  Remove-Item -ErrorAction SilentlyContinue -DeleteKey "Cert:\CurrentUser\My\$((Get-Content $last -Raw).Trim())"
}
$flags = [Security.Cryptography.X509Certificates.X509KeyStorageFlags]'UserKeySet, PersistKeySet'
$cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($p12, $pw, $flags)
$store = [Security.Cryptography.X509Certificates.X509Store]::new('My', 'CurrentUser')
$store.Open('ReadWrite')
try { $store.Add($cert) } finally { $store.Close() }

Set-Content -NoNewline $last $cert.Thumbprint
Set-Content -NoNewline $mark $sum
Write-Host "setup:bitwarden: imported ~/.bw.p12 ($($cert.Subject))"
