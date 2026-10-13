# PowerShell 7 profile, dot-sourced from $PROFILE by the loader line that setup:pwsh writes.
# Edits here apply to the next shell (Alt+R reloads); add machine-local lines to $PROFILE itself.

# PATH: nano.exe (setup:nano) and Sign.ps1
$env:Path = "$HOME\.local\bin;$HOME\.config\mise\conf.d\windows\bin;$env:Path"

# mise
if (Get-Command mise -ErrorAction SilentlyContinue) {
  (& mise activate pwsh) | Out-String | Invoke-Expression
}

# mb: pull this repo, then `mise bootstrap` from ~ with miserc.local.toml's env list (the zsh
# mb() in dotfiles/zshrc, minus `unapply desktop`: Windows has no module to unapply).
function mb {
  if ((Test-Path Env:MISE_ENV) -or (Test-Path Env:MISE_PROFILE) -or (Test-Path Env:MISE_ENVIRONMENT)) {
    Write-Error "mb: unset MISE_ENV / MISE_PROFILE / MISE_ENVIRONMENT first; they replace miserc.local.toml's env list"
    return
  }
  foreach ($a in $args) {
    $a = [string]$a
    # the short flags of a group (-nE) up to -C or -j, which take the rest as their value
    $f = ''
    if ($a -cmatch '^-[^-]') { $f = ($a.Substring(1) -csplit '[Cj]', 2)[0] }
    # -E/--env and its hidden alias -P/--profile
    if ($f -cmatch '[EP]' -or $a -ceq '--env' -or $a -clike '--env=*' -or $a -ceq '--profile' -or $a -clike '--profile=*') {
      Write-Error "mb: do not pass $a; the env list lives in ~/.config/mise/miserc.local.toml"
      return
    }
    # -C/--cd: another directory would add its project config to the run
    if ($a -ceq '--cd' -or $a -clike '--cd=*' -or ($a -cmatch '^-[^-]' -and $a.Substring(1).StartsWith("${f}C", [StringComparison]::Ordinal))) {
      Write-Error "mb: do not pass $a; mb runs mise from ~, and another directory would add its project config"
      return
    }
  }
  if ($args -ccontains 'unapply') {
    Write-Error "mb: unapply is not supported on Windows; unapplying this machine's platform removes the files and dotfiles it declares"
    return
  }
  git -C "$HOME\.config\mise" pull --ff-only --quiet
  if ($LASTEXITCODE) { Write-Warning 'mb: git pull failed; applying the local checkout' }
  Push-Location $HOME
  try { mise bootstrap @args } finally { Pop-Location }
}

function CustomListChildItems {
  Get-ChildItem $args[0] -Force |
    Sort-Object -Property @{ Expression = 'LastWriteTime'; Descending = $true },
                          @{ Expression = 'Name'; Ascending = $true } |
    Format-Table -AutoSize -Property Mode, Length, LastWriteTime, Name
}
Set-Alias -Name ll -Value CustomListChildItems

function CustomHosts { Start-Process notepad C:\Windows\System32\drivers\etc\hosts -Verb RunAs }
Set-Alias -Name hosts -Value CustomHosts

function CustomUpdate {
  explorer ms-settings:windowsupdate
  winget upgrade --all --silent
}
Set-Alias -Name update -Value CustomUpdate

function CustomHome { Set-Location \\wsl$\Ubuntu\home\eggplants }
Set-Alias -Name wslh -Value CustomHome

Set-PSReadLineKeyHandler -Key 'alt+r' -BriefDescription 'reloadPROFILE' -LongDescription 'reloadPROFILE' -ScriptBlock {
  [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
  [Microsoft.PowerShell.PSConsoleReadLine]::Insert('<#SKIPHISTORY#> . $PROFILE')
  [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

# zsh-like completion
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# fish-like completion
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -Colors @{ InlinePrediction = 'DarkGreen' }

# PSColors (setup:pwsh installs it)
if (Import-Module PSColors -PassThru -ErrorAction SilentlyContinue) {
  $global:PSColors = @{
    File    = @{
      Default    = @{ Color = 'White' }
      Directory  = @{ Color = 'Cyan' }
      Hidden     = @{ Color = 'DarkGray'; Pattern = '^\.' }
      Code       = @{ Color = 'Magenta'; Pattern = '\.(java|c|cpp|cs|js|css|html)$' }
      Executable = @{ Color = 'Red'; Pattern = '\.(exe|bat|cmd|py|pl|ps1|psm1|vbs|rb|reg)$' }
      Text       = @{ Color = 'Yellow'; Pattern = '\.(txt|cfg|conf|ini|csv|log|config|xml|yml|md|markdown)$' }
      Compressed = @{ Color = 'Green'; Pattern = '\.(zip|tar|gz|rar|jar|war)$' }
    }
    Service = @{
      Default = @{ Color = 'White' }
      Running = @{ Color = 'DarkGreen' }
      Stopped = @{ Color = 'DarkRed' }
    }
    Match   = @{
      Default    = @{ Color = 'White' }
      Path       = @{ Color = 'Cyan' }
      LineNumber = @{ Color = 'Yellow' }
      Line       = @{ Color = 'White' }
    }
    NoMatch = @{
      Default    = @{ Color = 'White' }
      Path       = @{ Color = 'Cyan' }
      LineNumber = @{ Color = 'Yellow' }
      Line       = @{ Color = 'White' }
    }
  }
}

# prompt; without the bundled theme (POSH_THEMES_PATH unset or missing it), load it by URL
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
  $theme = if ($env:POSH_THEMES_PATH -and (Test-Path "$env:POSH_THEMES_PATH\montys.omp.json")) {
    "$env:POSH_THEMES_PATH\montys.omp.json"
  } else {
    'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/montys.omp.json'
  }
  oh-my-posh init pwsh --config $theme | Invoke-Expression
}
