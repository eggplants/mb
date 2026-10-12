#!/usr/bin/env bash
# Switch Ubuntu's ~/.config/mise from eggplants/setup-ubuntu.sh to eggplants/mise-bootstrap.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/eggplants/mise-bootstrap/main/migrate-ubuntu.sh)
#
# The desktop module is selected when the old checkout pinned env = ["desktop"] or
# ubuntu-desktop-minimal is installed; DESKTOP=1 / DESKTOP=0 overrides that.
# The old checkout is kept as ~/.config/mise.setup-ubuntu. Nothing but the dotfile links is
# applied; the script prints the commands to review and apply the rest.
set -euo pipefail

repo=https://github.com/eggplants/mise-bootstrap.git
min_mise=2026.10.7
config_dir="$HOME/.config/mise"
backup="$HOME/.config/mise.setup-ubuntu"
export PATH="$HOME/.local/bin:$PATH"

die() {
  echo "migrate-ubuntu.sh: $*" >&2
  exit 1
}

# shellcheck disable=SC1091
[[ "$(. /etc/os-release && echo "$ID")" == ubuntu ]] || die "this is not Ubuntu"
[[ -z "${MISE_ENV+x}${MISE_PROFILE+x}${MISE_ENVIRONMENT+x}" ]] || die "unset MISE_ENV / MISE_PROFILE / MISE_ENVIRONMENT first"
[[ ! -e "$backup" ]] || die "$backup already exists"
cd ~

# 1. mise must be new enough for conf.d modules and the guard
mise self-update --yes || true
v="$(mise --version | awk '{print $1}')"
[[ "$(printf '%s\n%s\n' "$min_mise" "$v" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" == "$min_mise" ]] ||
  die "mise $v is older than $min_mise"

# 2. the old checkout must be setup-ubuntu.sh, clean and pushed
origin="$(git -C "$config_dir" remote get-url origin)"
[[ "$origin" =~ eggplants/setup-ubuntu\.sh ]] || die "$config_dir is not a setup-ubuntu.sh checkout (origin: $origin)"
if [[ -n "$(git -C "$config_dir" status --porcelain --untracked-files=no)" ]]; then
  git -C "$config_dir" status --short --untracked-files=no >&2
  die "local changes (above): move machine-only lines to ~/.zshrc.d/<name>.zsh or ~/.zshenv.d/<name>.zsh, then git -C $config_dir checkout -- <file>"
fi
[[ "$(git -C "$config_dir" rev-list --count '@{upstream}..HEAD')" == 0 ]] || die "local commits are not pushed"

# 3. desktop or headless
if [[ -z "${DESKTOP:-}" ]]; then
  DESKTOP=0
  if grep -qs '"desktop"' "$config_dir/miserc.local.toml" ||
    dpkg-query -W -f='${Status}' ubuntu-desktop-minimal 2>/dev/null | grep -q 'ok installed'; then
    DESKTOP=1
  fi
fi
env_line='env = ["linux", "ubuntu"]'
[[ "$DESKTOP" == 0 ]] || env_line='env = ["linux", "ubuntu", "desktop"]'
echo "selection: $env_line"

# 4. preview the new config without changing anything
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone -q "$repo" "$tmp/mise"
echo "$env_line" >"$tmp/mise/miserc.local.toml"
MISE_CONFIG_DIR="$tmp/mise" mise bootstrap plan || die "the new config does not load or pass the guard; nothing was changed"
read -r -p "Switch $config_dir to mise-bootstrap? [y/N] " ans </dev/tty
[[ "$ans" == [yY]* ]] || die "cancelled; nothing was changed"

# 5. switch: ~/.zshrc etc. keep pointing at the same paths, so they work again right after the clone
mv "$config_dir" "$backup"
git clone -q "$repo" "$config_dir"
echo "$env_line" >"$config_dir/miserc.local.toml"
mise bootstrap --only dotfiles --yes ||
  echo "migrate-ubuntu.sh: relinking failed; if a file conflicts, run: mise bootstrap --only dotfiles --force-dotfiles" >&2

cat <<EOF

Switched $config_dir to mise-bootstrap (old checkout: $backup). Next:
  exec zsh -l
  mise config ls                 # config.toml + conf.d/linux + conf.d/ubuntu (+ conf.d/desktop)
  MISE_TASK_RUN_AUTO_INSTALL=false mise run host:check
  mb --update --dry-run
  mb --update                    # --update: apt metadata after the apt sources change

Roll back:
  cd ~ && rm -rf $config_dir && mv $backup $config_dir && mise bootstrap --only dotfiles --yes
EOF
