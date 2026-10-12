#!/usr/bin/env bash
# Switch the NanoPi's ~/.config/mise from eggplants/setup-nanopi to eggplants/mise-bootstrap.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/eggplants/mise-bootstrap/main/migrate-nanopi.sh)
#
# Unlike the other machines, the checkout is switched IN PLACE: compose/ keeps its path and
# content, so the running tv project and its gitignored data (compose/scanned/,
# compose/epgstation/{data,thumbnail,logs}/) are not touched. The old branch stays as
# legacy-<branch> and the old remote as "legacy". Nothing but the dotfile links is applied;
# the script prints the commands to review and apply the rest. Never `git clean -x` here.
set -euo pipefail

repo=https://github.com/eggplants/mise-bootstrap.git
min_mise=2026.10.7
config_dir="$HOME/.config/mise"
env_line='env = ["linux", "nanopi"]'
export PATH="$HOME/.local/bin:$PATH"

die() {
  echo "migrate-nanopi.sh: $*" >&2
  exit 1
}

grep -aqsi nanopi /proc/device-tree/model || die "this is not the NanoPi (/proc/device-tree/model)"
# the shared docker.sources template renders these from the host
# shellcheck disable=SC1091
read -r id codename arch < <(. /etc/os-release && echo "$ID $VERSION_CODENAME $(dpkg --print-architecture)")
[[ "$id $codename $arch" == "debian bookworm arm64" ]] || die "expected debian bookworm arm64, got: $id $codename $arch"
[[ -z "${MISE_ENV+x}${MISE_PROFILE+x}${MISE_ENVIRONMENT+x}" ]] || die "unset MISE_ENV / MISE_PROFILE / MISE_ENVIRONMENT first"
cd ~

# 1. mise must be new enough for conf.d modules and the guard
mise self-update --yes || true
v="$(mise --version | awk '{print $1}')"
[[ "$(printf '%s\n%s\n' "$min_mise" "$v" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" == "$min_mise" ]] ||
  die "mise $v is older than $min_mise"

# 2. the old checkout must be setup-nanopi, clean and pushed
origin="$(git -C "$config_dir" remote get-url origin)"
[[ "$origin" =~ eggplants/setup-nanopi ]] || die "$config_dir is not a setup-nanopi checkout (origin: $origin)"
if [[ -n "$(git -C "$config_dir" status --porcelain --untracked-files=no)" ]]; then
  git -C "$config_dir" status --short --untracked-files=no >&2
  die "local changes (above): move machine-only lines to ~/.zshrc.d/<name>.zsh or ~/.zshenv.d/<name>.zsh, then git -C $config_dir checkout -- <file>"
fi
[[ "$(git -C "$config_dir" rev-list --count '@{upstream}..HEAD')" == 0 ]] || die "local commits are not pushed"
old_branch="$(git -C "$config_dir" symbolic-ref --short HEAD)"
! git -C "$config_dir" remote get-url legacy &>/dev/null || die "remote legacy already exists"
! git -C "$config_dir" show-ref --verify --quiet "refs/heads/legacy-$old_branch" || die "branch legacy-$old_branch already exists"

# 3. fetch the new tree and refuse if it would overwrite untracked or ignored (runtime) files
git -C "$config_dir" fetch -q "$repo" main
collide="$(comm -12 <(git -C "$config_dir" ls-files --others | sort) \
  <(git -C "$config_dir" ls-tree -r --name-only FETCH_HEAD | sort))"
[[ -z "$collide" ]] || die "these local files would be overwritten by the new tree; move them first: $collide"

# 4. preview the new config without changing anything (compose's project_dir still resolves to
#    the real ~/.config/mise/compose, so the plan compares against the running project)
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone -q "$repo" "$tmp/mise"
echo "$env_line" >"$tmp/mise/miserc.local.toml"
MISE_CONFIG_DIR="$tmp/mise" mise bootstrap plan || die "the new config does not load or pass the guard; nothing was changed"
echo "Expect: compose tv and /etc/apt/sources.list.d/docker.sources unchanged."
read -r -p "Switch $config_dir to mise-bootstrap in place? [y/N] " ans </dev/tty
[[ "$ans" == [yY]* ]] || die "cancelled; nothing was changed"

# 5. switch in place
git -C "$config_dir" remote rename origin legacy
git -C "$config_dir" remote add origin "$repo"
git -C "$config_dir" fetch -q origin
git -C "$config_dir" branch -m "$old_branch" "legacy-$old_branch"
git -C "$config_dir" switch -q -c main --track origin/main
[[ ! -f "$config_dir/miserc.local.toml" ]] || mv "$config_dir/miserc.local.toml" "$config_dir/miserc.local.toml.bak"
echo "$env_line" >"$config_dir/miserc.local.toml"
mise bootstrap --only dotfiles --yes ||
  echo "migrate-nanopi.sh: relinking failed; if a file conflicts, run: mise bootstrap --only dotfiles --force-dotfiles" >&2

cat <<EOF

Switched $config_dir to mise-bootstrap in place (old branch: legacy-$old_branch). Next:
  exec zsh -l
  mise config ls                 # config.toml + conf.d/linux + conf.d/nanopi
  MISE_TASK_RUN_AUTO_INSTALL=false mise run host:check
  mise bootstrap plan            # compose tv unchanged
  mb --update --dry-run
  mb --update                    # pick a time with no recording scheduled

Roll back:
  cd $config_dir && git switch -q legacy-$old_branch && git branch -D main && git remote remove origin &&
  git remote rename legacy origin && git branch -m legacy-$old_branch $old_branch && rm miserc.local.toml &&
  cd ~ && mise bootstrap --only dotfiles --yes
EOF
