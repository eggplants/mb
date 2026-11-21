#MISE description="Install Claude Code's user-scope plugins, skills and MCP servers"
# Windows twin of shared/tasks/claude/setup/claude (bash): keep the lists below in step with it.
# There is no mclaude or claude-statusbar on Windows, so only the default config dir is set up.
$ErrorActionPreference = 'Stop'

# user-scope plugin marketplaces (name=source) and plugins (name@marketplace)
$marketplaces = @(
  'agent-plugins-for-eggplants=eggplants/agent-plugins'
  'claude-community=anthropics/claude-plugins-community'
  'claude-plugins-official=anthropics/claude-plugins-official'
  'cursor-plugins=cursor/plugins'
  'googlechrome=GoogleChrome/modern-web-guidance'
  'humanize-writing-skill=eggplants/humanize-writing-skill'
  'natural-japanese=coji/natural-japanese'
  'yomiyasu=nanaism/yomiyasu'
)
$plugins = @(
  'claude-security@claude-plugins-official'
  'commit@agent-plugins-for-eggplants'
  'copilot-review@agent-plugins-for-eggplants'
  'eli5@claude-community'
  'humanize-writing@humanize-writing-skill'
  'modern-web-guidance@googlechrome'
  'natural-japanese@natural-japanese'
  'pstack@cursor-plugins'
  'yomiyasu@yomiyasu'
  # after eli5 and yomiyasu, its dependencies, so that they are not installed twice
  'japanese-oss-handbook@agent-plugins-for-eggplants'
)
# user-scope MCP servers (name=command), added only when the command is installed
$mcpServers = @(
  'trivy=trivy mcp'
)
# skills installed into ~/.claude/skills by gh skill (name=repo), only when gh is installed
$ghSkills = @(
  'security-audit=cloudflare/security-audit-skill'
)

# a failure is reported at the end, so that one broken marketplace does not stop the rest
$failed = @()
function Invoke-Claude {
  & claude @args
  if ($LASTEXITCODE) {
    $script:failed += "claude $args"
    Write-Warning "setup:claude: claude $args failed"
  }
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  throw 'setup:claude: claude is not installed; run mise bootstrap packages apply (winget:Anthropic.ClaudeCode)'
}

# trivy MCP server plugin
if (Get-Command trivy -ErrorAction SilentlyContinue) {
  & trivy plugin info mcp *> $null
  if ($LASTEXITCODE) { & trivy plugin install mcp }
}

# gh skills
foreach ($s in $ghSkills) {
  $name, $repo = $s -split '=', 2
  if (Test-Path (Join-Path $HOME ".claude\skills\$name")) { continue }
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Warning "setup:claude: skipping skill ${name}: gh is not installed"
    continue
  }
  & gh auth status *> $null
  if ($LASTEXITCODE) {
    Write-Warning "setup:claude: skipping skill ${name}: run gh auth login first"
    continue
  }
  & gh skill install $repo $name --agent claude-code --scope user
}

# plugins
$have = (claude plugin marketplace list --json | ConvertFrom-Json).name
$missing = @()
foreach ($m in $marketplaces) {
  $name, $source = $m -split '=', 2
  if ($have -notcontains $name) {
    Invoke-Claude plugin marketplace add --scope user $source
    if ($LASTEXITCODE) { $missing += $name }
  }
}
$have = (claude plugin list --json | ConvertFrom-Json | Where-Object scope -EQ 'user').id
foreach ($p in $plugins) {
  if ($have -notcontains $p -and $missing -notcontains ($p -split '@', 2)[1]) {
    Invoke-Claude plugin install --scope user $p
  }
}
foreach ($s in $mcpServers) {
  $name, $command = $s -split '=', 2
  $cmd = -split $command
  if (-not (Get-Command $cmd[0] -ErrorAction SilentlyContinue)) { continue }
  & claude mcp get $name *> $null
  if ($LASTEXITCODE) { Invoke-Claude mcp add --scope user $name -- @cmd }
}
if ($failed) { throw "setup:claude: failed: $($failed -join '; ')" }
