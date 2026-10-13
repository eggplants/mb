#MISE description="Install the latest nano-win build as ~/.local/bin/nano.exe"
# winget's GNU.Nano is stuck at 2.7.5, so take the newest nano-win build from its author.
# ~/.nanorc (dotfiles/nanorc, shared) includes the syntax files of the nano-highlight repo.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$base = 'https://files.lhmouse.com/nano-win/'
$bin = Join-Path $HOME '.local\bin'
$stamp = Join-Path $HOME '.local\share\nano-win\version'

# the listing is sorted newest first
$latest = [regex]::Match((Invoke-WebRequest -UseBasicParsing $base).Content, 'href="(nano-win_[^"]+\.7z)"').Groups[1].Value
if (-not $latest) { throw "setup:nano: no nano-win archive found at $base" }
if ((Test-Path (Join-Path $bin 'nano.exe')) -and (Test-Path $stamp) -and ((Get-Content $stamp -Raw).Trim() -eq $latest)) {
  exit 0
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force $tmp, $bin, (Split-Path $stamp) | Out-Null
try {
  Invoke-WebRequest -UseBasicParsing "$base$latest" -OutFile (Join-Path $tmp $latest)
  # Windows' bsdtar reads 7z
  & "$env:SystemRoot\System32\tar.exe" -xf (Join-Path $tmp $latest) -C $tmp
  if ($LASTEXITCODE) { throw "setup:nano: tar failed on $latest" }
  Copy-Item -Force (Join-Path $tmp 'pkg_x86_64-w64-mingw32\bin\nano.exe') $bin
  Set-Content -Path $stamp -Value $latest
  Write-Output "setup:nano: installed $latest"
} finally {
  Remove-Item -Recurse -Force $tmp
}
