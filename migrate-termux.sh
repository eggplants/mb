#!/usr/bin/env bash
# Switch Termux's ~/.config/mise from eggplants/setup-termux.sh to eggplants/mise-bootstrap.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/eggplants/mise-bootstrap/main/migrate-termux.sh)
#
# The old checkout is kept as ~/.config/mise.setup-termux. Nothing but the dotfile links is
# applied; the script prints the commands to review and apply the rest.
set -euo pipefail

repo=https://github.com/eggplants/mise-bootstrap.git
min_mise=2026.10.7
config_dir="$HOME/.config/mise"
backup="$HOME/.config/mise.setup-termux"
env_line='env = ["termux"]'

die() {
  echo "migrate-termux.sh: $*" >&2
  exit 1
}

[[ -n "${TERMUX_VERSION:-}" || -x /data/data/com.termux/files/usr/bin/pkg ]] || die "this is not Termux"
[[ -z "${MISE_ENV+x}${MISE_PROFILE+x}${MISE_ENVIRONMENT+x}" ]] || die "unset MISE_ENV / MISE_PROFILE / MISE_ENVIRONMENT first"
[[ ! -e "$backup" ]] || die "$backup already exists"
cd ~

# 1. mise must be new enough for conf.d modules and the guard
pkg install -y mise # installs or upgrades
v="$(mise --version | awk '{print $1}')"
[[ "$(printf '%s\n%s\n' "$min_mise" "$v" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" == "$min_mise" ]] ||
  die "mise $v is older than $min_mise"

# 2. the old checkout must be setup-termux.sh, clean and pushed
origin="$(git -C "$config_dir" remote get-url origin)"
[[ "$origin" =~ eggplants/setup-termux\.sh ]] || die "$config_dir is not a setup-termux.sh checkout (origin: $origin)"
if [[ -n "$(git -C "$config_dir" status --porcelain --untracked-files=no)" ]]; then
  git -C "$config_dir" status --short --untracked-files=no >&2
  die "local changes (above): move machine-only lines to ~/.zshrc.d/<name>.zsh or ~/.zshenv.d/<name>.zsh, then git -C $config_dir checkout -- <file>"
fi
[[ "$(git -C "$config_dir" rev-list --count '@{upstream}..HEAD')" == 0 ]] || die "local commits are not pushed"

# 3. preview the new config without changing anything
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone -q "$repo" "$tmp/mise"
echo "$env_line" >"$tmp/mise/miserc.local.toml"
MISE_CONFIG_DIR="$tmp/mise" mise bootstrap plan || die "the new config does not load or pass the guard; nothing was changed"
read -r -p "Switch $config_dir to mise-bootstrap? [y/N] " ans </dev/tty
[[ "$ans" == [yY]* ]] || die "cancelled; nothing was changed"

# 4. switch: ~/.zshrc etc. keep pointing at the same paths, so they work again right after the clone
mv "$config_dir" "$backup"
git clone -q "$repo" "$config_dir"
echo "$env_line" >"$config_dir/miserc.local.toml"
mise plugins link --force pkg "$config_dir/plugins/pkg"
mise bootstrap --only dotfiles --yes ||
  echo "migrate-termux.sh: relinking failed; if a file conflicts, run: mise bootstrap --only dotfiles --force-dotfiles" >&2

cat <<EOF

Switched $config_dir to mise-bootstrap (old checkout: $backup). Next:
  exec zsh -l
  mise config ls                 # config.toml + conf.d/termux/mise.termux.toml
  MISE_TASK_RUN_AUTO_INSTALL=false mise run host:check
  mb --dry-run
  mb
  gpgconf --reload gpg-agent     # pick up the new cache TTL

Roll back:
  cd ~ && rm -rf $config_dir && mv $backup $config_dir && mise plugins link --force pkg $config_dir/plugins/pkg && mise bootstrap --only dotfiles --yes
EOF
