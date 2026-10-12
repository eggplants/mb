#!/usr/bin/env bash
# First-time setup of a machine from eggplants/mise-bootstrap. Later runs: mb (or mise bootstrap).
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/eggplants/mise-bootstrap/main/bootstrap.sh) [mise bootstrap args]
#
# Installs git and mise when missing, clones this repo to ~/.config/mise (unless it is already
# there, as after Ubuntu's autoinstall.yaml), pins this machine's env list in miserc.local.toml
# (unless one exists), runs the platform pre-steps, then `mise bootstrap`.
# Ubuntu: DESKTOP=1 / DESKTOP=0 overrides the desktop detection (ubuntu-desktop-minimal).
# The host tests mirror tasks/host/check and guard.tera (ci/check.sh compares them).
set -euo pipefail

repo=https://github.com/eggplants/mise-bootstrap.git
config_dir="$HOME/.config/mise"
export PATH="$HOME/.local/bin:$PATH"
die() {
  echo "bootstrap.sh: $*" >&2
  exit 1
}

[[ -z "${MISE_ENV+x}${MISE_PROFILE+x}${MISE_ENVIRONMENT+x}" ]] || die "unset MISE_ENV / MISE_PROFILE / MISE_ENVIRONMENT first"

# shellcheck disable=SC1091 # /etc/os-release
if [[ -n "${TERMUX_VERSION:-}" || -x /data/data/com.termux/files/usr/bin/pkg ]]; then
  platform=termux env='["termux"]'
elif [[ "$(uname -s)" == Darwin ]]; then
  platform=macos env='["macos"]'
elif grep -aqsi nanopi /proc/device-tree/model; then
  platform=nanopi env='["linux", "nanopi"]'
elif [[ "$(. /etc/os-release 2>/dev/null && echo "$ID")" == ubuntu ]]; then
  platform=ubuntu env='["linux", "ubuntu"]'
  if [[ "${DESKTOP:-}" == 1 ]] || { [[ -z "${DESKTOP:-}" ]] &&
    dpkg-query -W -f='${Status}' ubuntu-desktop-minimal 2>/dev/null | grep -q 'ok installed'; }; then
    env='["linux", "ubuntu", "desktop"]'
  fi
else
  die "unsupported host ($(uname -sm))"
fi

case "$platform" in
  macos)
    if ! xcode-select -p &>/dev/null; then
      xcode-select --install
      die "re-run this after the Command Line Tools finish installing"
    fi
    # the colima LaunchAgent runs ~/.local/bin/mise, so install it there (not with Homebrew)
    [[ -x "$HOME/.local/bin/mise" ]] || curl -fsSL https://mise.run | sh
    ;;
  termux)
    if ! command -v mise &>/dev/null || ! command -v git &>/dev/null; then
      pkg upgrade -y
      pkg install -y mise git
    fi
    ;;
  ubuntu | nanopi)
    if ! command -v git &>/dev/null || ! command -v curl &>/dev/null; then
      sudo apt-get update
      sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl git
    fi
    command -v mise &>/dev/null || curl -fsSL https://mise.run | sh
    ;;
esac

if [[ ! -e "$config_dir" ]]; then
  git clone "$repo" "$config_dir"
elif [[ "$(git -C "$config_dir" remote get-url origin 2>/dev/null)" != *eggplants/mise-bootstrap* ]]; then
  die "$config_dir exists and is not a checkout of $repo; move it away first"
fi
[[ -f "$config_dir/miserc.local.toml" ]] || echo "env = $env" >"$config_dir/miserc.local.toml"

# from ~: a project mise.toml / .miserc.toml in the cwd would join the run
cd ~
extra=()
case "$platform" in
  termux)
    # [bootstrap.plugins] only takes Git URLs, so link the bundled pkg plugin
    mise plugins link --force pkg "$config_dir/plugins/pkg"
    ;;
  nanopi)
    # recordings and MariaDB live on the external disk; hdd:init asks, then formats it
    mountpoint -q /mnt/hdd1 || MISE_TASK_RUN_AUTO_INSTALL=false mise run hdd:init
    extra=(--update) # refresh apt metadata after [bootstrap.files] rewrites the apt sources
    ;;
  ubuntu)
    extra=(--update)
    ;;
esac

exec mise bootstrap ${extra[@]+"${extra[@]}"} "$@"
