#MISE description="Write user.email/signingkey (or turn off signing) to ~/.gitconfig.local and log in to gh"
# Windows twin of shared/tasks/gpg/setup/git (bash). Without a GPG secret key, commits on this
# machine are unsigned and use the GitHub noreply address, since dotfiles/gitconfig signs by default.
$ErrorActionPreference = 'Stop'

$local = Join-Path $HOME '.gitconfig.local'
function Set-LocalGitConfig($key, $value) {
  & git config --file $local $key $value
  if ($LASTEXITCODE) { throw "setup:git: git config $key failed" }
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw 'setup:git: gh is not installed; run mise bootstrap packages apply (winget:GitHub.cli)'
}
& gh auth status --hostname github.com *> $null
if ($LASTEXITCODE) {
  # the device flow waits for the code to be entered in a browser; without a console it hangs
  if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
    & gh auth login --hostname github.com --git-protocol https --web
  } else {
    Write-Warning 'setup:git: not logged in to GitHub; run `gh auth login --web` from a terminal'
  }
}

$gpg = Get-Command gpg -ErrorAction SilentlyContinue
$secret = if ($gpg) { & gpg --list-secret-keys --with-colons 2>$null } else { @() }
if ($secret -match '^sec:') {
  # fingerprint of the last secret key, and the email of the first uid
  $key = (($secret -split "`n") | Select-String '^fpr:' | Select-Object -Last 1).Line.Split(':')[9]
  $uid = ((& gpg --list-keys --with-colons) | Select-String '^uid:' | Select-Object -First 1).Line.Split(':')[9]
  Set-LocalGitConfig user.signingkey $key
  Set-LocalGitConfig user.email ([regex]::Match($uid, '<(.*)>').Groups[1].Value)
  Set-LocalGitConfig gpg.program $gpg.Source
  Set-LocalGitConfig commit.gpgSign true
  Set-LocalGitConfig tag.gpgSign true
} else {
  Write-Warning 'setup:git: no GPG secret key; commits and tags on this machine are not signed'
  Set-LocalGitConfig commit.gpgSign false
  Set-LocalGitConfig tag.gpgSign false
  & gh auth status --hostname github.com *> $null
  if (-not $LASTEXITCODE) {
    $email = & gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"'
    if (-not $LASTEXITCODE -and $email) { Set-LocalGitConfig user.email $email }
  } else {
    Write-Warning 'setup:git: user.email is not set until gh is logged in; run mise run setup:git again'
  }
}
