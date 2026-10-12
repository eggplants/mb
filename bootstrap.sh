#!/usr/bin/env bash
# Set up this machine from eggplants/mise-bootstrap: one global mise config (~/.config/mise)
# for macOS (Apple Silicon), Termux, Ubuntu (desktop or headless) and the NanoPi R6S TV server.
#
#   new machine:        bash <(curl -fsSL https://raw.githubusercontent.com/eggplants/mise-bootstrap/main/bootstrap.sh)
#   re-run / update:    bash ~/.config/mise/bootstrap.sh [mise bootstrap args, e.g. --dry-run]
#   old setup-* clone:  bash <(curl -fsSL https://raw.githubusercontent.com/eggplants/mise-bootstrap/main/bootstrap.sh) --migrate
#                       (switches ~/.config/mise in place; applies nothing but the dotfile links
#                       and gpg.program in ~/.gitconfig.local)
#
# A dry run (-n/--dry-run, --dry-run=<any value>, or -n inside a group such as -yn) only
# previews `mise bootstrap`; the steps before it still run. They install missing prerequisites (macOS: Command Line Tools and
# mise; Termux: pkg upgrade, mise and git; Ubuntu/NanoPi: git, curl and mise), clone this repo
# when ~/.config/mise does not exist, pin miserc.local.toml and, on Termux, link the pkg plugin.
# A dry run refuses to move away a ~/.config/mise that is not a git checkout, and on the NanoPi
# it only reports a missing /mnt/hdd1 instead of running hdd:init. --check changes nothing.
#
# Options (anything else is passed to `mise bootstrap`):
#   --platform P            refuse to run unless this host is P (macos|termux|ubuntu|nanopi)
#   --desktop/--no-desktop  Ubuntu only: add or leave out the desktop module
#                           (default: keep the current choice, else add it when ubuntu-desktop-minimal is installed)
#   --check                 print what would happen, change nothing
#   --migrate               switch an old eggplants/setup-* checkout to this repo in place
#                           (no mise bootstrap args; preview with --check)
#   --detect                print this host's platform (macos|termux|ubuntu|nanopi|unknown) and exit;
#                           used by the host:check task. Keep detect_platform() in sync with guard.tera.
# Refused: -E/--env and -P/--profile, and a set MISE_ENV/MISE_PROFILE/MISE_ENVIRONMENT; they would
# replace the env list in miserc.local.toml. Also -C/--cd: mise runs from ~ here, and another
# directory would add its project config (mise.toml) to the run.
#
# Everything runs inside main(), and the last line exits, so `curl ... | bash` can never feed
# the rest of the script (or the terminal) to the shell; `bash <(curl ...)` is still preferred.
set -euo pipefail

repo_url="${MISE_BOOTSTRAP_REPO:-https://github.com/eggplants/mise-bootstrap.git}"
self_url=https://raw.githubusercontent.com/eggplants/mise-bootstrap/main/bootstrap.sh
min_mise=2026.10.7 # keep in sync with min_version in config.toml
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mise"
miserc="$config_dir/miserc.local.toml"
desktop_explicit=''
legacy_re='github\.com[:/]eggplants/(setup-macos\.sh|setup-termux\.sh|setup-ubuntu\.sh|setup-nanopi)(\.git)?/?$'

log() { printf 'bootstrap.sh: %s\n' "$*" >&2; }
die() {
  log "$*"
  exit 1
}

# The one shell copy of the host tests (guard.tera has the Tera copy; ci/check.sh compares them).
detect_platform() {
  local id=''
  if [[ -n "${TERMUX_VERSION:-}" || -x /data/data/com.termux/files/usr/bin/pkg ]]; then
    echo termux
  elif [[ "$(uname -s)" == Darwin ]]; then
    echo macos
  elif [[ "$(uname -s)" == Linux ]] && grep -aqsi nanopi /proc/device-tree/model; then
    echo nanopi
  else
    # shellcheck disable=SC1091
    [[ "$(uname -s)" == Linux && -r /etc/os-release ]] && id="$(. /etc/os-release && echo "${ID:-}")"
    if [[ "$id" == ubuntu ]]; then echo ubuntu; else echo unknown; fi
  fi
}

mise_bin() {
  # the macOS colima LaunchAgent runs ~/.local/bin/mise, so that copy must be the one in use
  if [[ "$platform" == macos ]]; then echo "$HOME/.local/bin/mise"; else command -v mise || echo mise; fi
}

check_mise_version() {
  local v
  v="$("$mise" --version 2>/dev/null | awk '{print $1}')" || true
  [[ -n "$v" ]] || die "mise not found"
  [[ "$(printf '%s\n%s\n' "$min_mise" "$v" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" == "$min_mise" ]] ||
    die "mise $v is older than $min_mise; upgrade it first (Termux: pkg upgrade mise; elsewhere: mise self-update)"
}

install_prereqs() {
  case "$platform" in
    macos)
      if ! xcode-select -p &>/dev/null; then
        xcode-select --install
        die "re-run this script after the Command Line Tools finish installing"
      fi
      [[ "$(uname -m)" == arm64 ]] || die "this config targets Apple Silicon (/opt/homebrew)"
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
}

origin_of() { git -C "$config_dir" remote get-url origin 2>/dev/null || echo '(none)'; }
is_this_repo() { [[ "$1" == "$repo_url" || "$1" =~ github\.com[:/]eggplants/mise-bootstrap(\.git)?/?$ ]]; }

checkout_state() {
  if [[ -d "$config_dir/.git" ]]; then
    local origin
    origin="$(origin_of)"
    if is_this_repo "$origin"; then
      echo current
    elif [[ "$origin" =~ $legacy_re ]]; then
      echo legacy
    else
      echo foreign
    fi
  elif [[ -e "$config_dir" ]]; then
    echo plain
  else
    echo missing
  fi
}

# Checks the env pin without changing anything. Sets pin_action to keep (already pinned),
# create (no miserc.local.toml) or replace, and refuses any other selection.
pin_action=''
pin_check() {
  local current flat
  if [[ ! -f "$miserc" ]]; then
    pin_action=create
    return 0
  fi
  current="$(grep -E '^[[:space:]]*env[[:space:]]*=' "$miserc" || true)"
  flat="$(tr -d '[:space:]' <<<"$current")"
  if [[ "$flat" == "$(tr -d '[:space:]' <<<"$env_line")" ]]; then
    pin_action=keep
  # Replace only (a) the selection the old repos wrote, setup-ubuntu.sh's env = ["desktop"], or
  # (b) an Ubuntu selection when --desktop/--no-desktop was passed explicitly.
  elif [[ "$platform" == ubuntu ]] && { [[ "$flat" == 'env=["desktop"]' ]] ||
    [[ -n "$desktop_explicit" && "$flat" =~ ^env=\[\"linux\",\"ubuntu\"(,\"desktop\")?\]$ ]]; }; then
    pin_action=replace
  else
    die "$miserc has '${current:-no env}', expected '$env_line'; fix it by hand, then run this again"
  fi
}

# Writes the env pin, or keeps an existing one. Never silently changes a different selection.
# Sets pin_undo to the command that restores the previous state (empty: nothing was changed).
pin_undo=''
pin_env() {
  local backup
  pin_check
  case "$pin_action" in
    keep) return 0 ;;
    replace)
      backup="$miserc.bak.$(date +%Y%m%d%H%M%S)"
      cp "$miserc" "$backup"
      pin_undo="mv \"$backup\" \"$miserc\""
      ;;
    create) pin_undo="rm \"$miserc\"" ;;
  esac
  printf '# Written by bootstrap.sh: the config modules this machine loads. Not committed.\n%s\n' "$env_line" >"$miserc"
  log "pinned $env_line in $miserc"
}

# After `remote add mise-bootstrap`: drop the remote again, then stop.
abort_migrate() {
  git -C "$config_dir" remote remove mise-bootstrap 2>/dev/null || true
  die "$@"
}

migrate() {
  local origin from old_ref old_sha ahead preview collide missing gpg_bin ok=true
  origin="$(origin_of)"
  [[ "$origin" =~ $legacy_re ]] || die "$config_dir is not a checkout of an old setup-* repo (origin: $origin)"
  case "${BASH_REMATCH[1]}" in
    setup-macos.sh) from=macos ;;
    setup-termux.sh) from=termux ;;
    setup-ubuntu.sh) from=ubuntu ;;
    setup-nanopi) from=nanopi ;;
  esac
  [[ "$from" == "$platform" ]] || die "the checkout is setup-$from, but this host is $platform"
  # Local changes would not survive the switch, and committing them to the old repo does not
  # carry them over either: the new tree only has the old history up to the import.
  if [[ -n "$(git -C "$config_dir" status --porcelain --untracked-files=no)" ]]; then
    git -C "$config_dir" status --short --untracked-files=no >&2
    die "tracked files in $config_dir have local changes (above); the switch would drop them, and so would committing them to $origin. Move lines that belong to this machine only (an installer's PATH line, say) to ~/.zshrc.d/<name>.zsh or ~/.zshenv.d/<name>.zsh, port anything else to eggplants/mise-bootstrap, discard the changes (git -C $config_dir checkout -- <file>), then run --migrate again"
  fi
  ahead="$(git -C "$config_dir" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)"
  [[ "$ahead" == 0 ]] || die "$ahead local commit(s) are not on $origin, and the switch would drop them: port their changes to eggplants/mise-bootstrap (or drop the commits), then run --migrate again"
  old_ref="$(git -C "$config_dir" symbolic-ref --short HEAD)"
  old_sha="$(git -C "$config_dir" rev-parse HEAD)"
  for b in "legacy-$old_ref" mise-bootstrap-main; do
    ! git -C "$config_dir" show-ref --verify --quiet "refs/heads/$b" || die "branch $b already exists in $config_dir; remove it first"
  done
  ! git -C "$config_dir" remote get-url legacy &>/dev/null || die "remote legacy already exists in $config_dir; remove it first"
  # The pin is written at step 5, but a selection it would refuse is refused here, before the
  # remote below exists.
  pin_check

  # 1. Download the new history first: if this fails, nothing has changed.
  git -C "$config_dir" remote remove mise-bootstrap 2>/dev/null || true
  git -C "$config_dir" remote add mise-bootstrap "$repo_url"
  git -C "$config_dir" fetch mise-bootstrap main || abort_migrate "could not fetch $repo_url; nothing was switched"
  # 2. Refuse if the old branch has commits that this repo lacks (the old history was imported
  #    with its SHAs, so everything up to the import is an ancestor of main). The old repo's
  #    final "moved" commit may be missing: it only touches README.md, bootstrap.sh and
  #    docs/autoinstall.yaml.
  missing="$(git -C "$config_dir" log --format='  %h %s' HEAD --not mise-bootstrap/main -- . \
    ':(exclude)README.md' ':(exclude)bootstrap.sh' ':(exclude)docs/autoinstall.yaml')"
  [[ -z "$missing" ]] || abort_migrate "these commits of $origin are not in eggplants/mise-bootstrap, and the switch would drop them:
$missing
Port their changes to eggplants/mise-bootstrap first; nothing was switched"
  # 3. Refuse if an untracked or ignored file sits where the new tree has a tracked file:
  #    git would refuse (untracked) or silently overwrite it (ignored, e.g. runtime data).
  collide="$(comm -12 <(git -C "$config_dir" ls-files --others | sort) \
    <(git -C "$config_dir" ls-tree -r --name-only mise-bootstrap/main | sort))"
  [[ -z "$collide" ]] || abort_migrate "these local files would be overwritten by the new tree; move them first: $collide"
  # 4. Check that the new config loads and passes the guard on this host, from a temporary
  #    worktree, before anything is switched.
  preview="$(mktemp -d "${TMPDIR:-/tmp}/mise-bootstrap-preview.XXXXXX")"
  git -C "$config_dir" worktree add --detach "$preview" mise-bootstrap/main >/dev/null ||
    abort_migrate "could not check out the new tree for the preview; nothing was switched"
  printf '%s\n' "$env_line" >"$preview/miserc.local.toml"
  (cd / && MISE_CONFIG_DIR="$preview" "$mise" bootstrap files status >/dev/null) || ok=false
  git -C "$config_dir" worktree remove --force "$preview"
  "$ok" || abort_migrate "the new config does not load or pass the guard on this host (see above); nothing was switched"
  # 5. Pin the env. The old layouts have no config.<env>.toml for these names, so they ignore it
  #    (old Ubuntu still loads its config.desktop.toml).
  pin_env
  # 6. Switch first, rename afterwards: if the switch fails, the old branch and remotes are untouched.
  #    The new branch gets a temporary name: the old one may already be main (setup-ubuntu.sh).
  git -C "$config_dir" switch -c mise-bootstrap-main --track mise-bootstrap/main ||
    die "git switch failed; still on $old_ref. Undo: git -C $config_dir remote remove mise-bootstrap${pin_undo:+ && $pin_undo}"
  git -C "$config_dir" branch -m "$old_ref" "legacy-$old_ref"
  git -C "$config_dir" branch -m mise-bootstrap-main main
  git -C "$config_dir" remote rename origin legacy
  git -C "$config_dir" remote rename mise-bootstrap origin
  cat >&2 <<MSG
bootstrap.sh: switched $config_dir from $origin ($old_ref @ ${old_sha:0:7}) to $repo_url (main).
To roll back:
  git -C "$config_dir" switch legacy-$old_ref && git -C "$config_dir" branch -D main &&
  git -C "$config_dir" remote remove origin && git -C "$config_dir" remote rename legacy origin &&
  git -C "$config_dir" branch -m legacy-$old_ref $old_ref && ${pin_undo:+$pin_undo && }(cd ~ && $mise bootstrap --only dotfiles --yes)
MSG
  # 7. Re-point what referenced old paths, then show what a full run would do; apply nothing else
  #    but gpg.program: the gitconfig no longer names gpg, and setup:git records its absolute path
  #    in ~/.gitconfig.local only on the next full run. Until then, GUI git clients on macOS (no
  #    shell PATH) could not sign. The NanoPi has no gitconfig.
  [[ "$platform" != termux ]] || "$mise" plugins link --force pkg "$config_dir/plugins/pkg"
  "$mise" bootstrap --only dotfiles --yes
  if [[ "$platform" != nanopi ]] && gpg_bin="$(command -v gpg)"; then
    git config --file "$HOME/.gitconfig.local" gpg.program "$gpg_bin"
    log "recorded gpg.program = $gpg_bin in ~/.gitconfig.local"
  fi
  "$mise" bootstrap plan || true
  log "switched. Open a new shell (exec zsh -l), review the plan above, then run: bash ~/.config/mise/bootstrap.sh"
}

# Local changes in a checkout (for --check): --migrate refuses both.
checkout_changes() {
  local dirty ahead
  [[ -d "$config_dir/.git" ]] || {
    echo '-'
    return 0
  }
  dirty="$(git -C "$config_dir" status --porcelain --untracked-files=no 2>/dev/null | wc -l | tr -d '[:space:]')"
  ahead="$(git -C "$config_dir" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo '?')"
  echo "$dirty tracked file(s) with local changes, $ahead commit(s) not on origin"
}

main() {
  local want='' desktop=auto mode=apply dry_run=false args=() extra=() group flags
  local env_msg='it replaces the env list in miserc.local.toml'
  local cd_msg='mise runs from ~ here, and another directory would add its project config to the run'
  while (($#)); do
    case "$1" in
      --platform)
        want="${2:?--platform needs a value}"
        shift 2
        ;;
      --platform=*)
        want="${1#*=}"
        shift
        ;;
      --desktop) desktop=yes desktop_explicit=1 && shift ;;
      --no-desktop) desktop=no desktop_explicit=1 && shift ;;
      --check) mode=check && shift ;;
      --migrate) mode=migrate && shift ;;
      --detect) mode=detect && shift ;;
      # mise's -E/--env and its hidden alias -P/--profile (short forms below)
      --env | --env=* | --profile | --profile=*) die "do not pass $1: $env_msg" ;;
      --cd | --cd=*) die "do not pass $1: $cd_msg" ;;
      # mise takes --dry-run=<any value>, even =false, as a dry run
      -n | --dry-run | --dry-run=*)
        dry_run=true
        args+=("$1")
        shift
        ;;
      # one short flag or a group of them (-yn); -C and -j take the rest of the group as their value
      -[!-]*)
        group="${1#-}"
        flags="${group%%[Cj]*}"
        case "$flags" in *[EP]*) die "do not pass $1: $env_msg" ;; esac
        [[ "$group" != "$flags"C* ]] || die "do not pass $1: $cd_msg"
        [[ "$flags" != *n* ]] || dry_run=true
        args+=("$1")
        shift
        ;;
      *) args+=("$1") && shift ;;
    esac
  done
  if [[ "$mode" == migrate && ${#args[@]} -gt 0 ]]; then
    die "--migrate takes no mise bootstrap arguments (got: ${args[*]}); preview with --check, which changes nothing"
  fi

  platform="$(detect_platform)"
  if [[ "$mode" == detect ]]; then
    echo "$platform"
    return 0
  fi
  [[ "$platform" != unknown ]] || die "unsupported host ($(uname -sm)); refusing to guess a platform"
  [[ -z "$want" || "$want" == "$platform" ]] || die "--platform $want, but this host looks like $platform"
  for v in MISE_ENV MISE_PROFILE MISE_ENVIRONMENT; do
    [[ -z "${!v+set}" ]] || die "unset $v first: it replaces the env list in miserc.local.toml"
  done

  case "$platform" in
    macos | termux) env_line="env = [\"$platform\"]" ;;
    nanopi) env_line='env = ["linux", "nanopi"]' ;;
    ubuntu)
      if [[ "$desktop" == auto ]]; then
        desktop=no
        if grep -qs '"desktop"' "$miserc" ||
          { ! grep -qs '^[[:space:]]*env' "$miserc" &&
            dpkg-query -W -f='${Status}' ubuntu-desktop-minimal 2>/dev/null | grep -q 'ok installed'; }; then
          desktop=yes
        fi
      fi
      env_line='env = ["linux", "ubuntu"]'
      [[ "$desktop" == no ]] || env_line='env = ["linux", "ubuntu", "desktop"]'
      ;;
  esac
  [[ "$desktop" != yes || "$platform" == ubuntu ]] || die "--desktop is only for Ubuntu"

  if [[ "$mode" == check ]]; then
    printf 'platform:  %s\nselection: %s\ncheckout:  %s (%s)\nchanges:   %s\nmiserc:    %s\n' "$platform" \
      "$env_line" "$(checkout_state)" "$config_dir" "$(checkout_changes)" \
      "$(grep -Es '^[[:space:]]*env' "$miserc" || echo none)"
    return 0
  fi

  # Interactive steps (sudo, hdd:init, setup:gpg, gh auth login) need the terminal, not the
  # pipe that `curl ... | bash` leaves on stdin. Safe because the last line of this file exits.
  if [[ ! -t 0 ]] && (exec </dev/tty) 2>/dev/null; then
    exec </dev/tty
  fi
  # A project .miserc.toml in the cwd (or a parent) would replace the env list.
  cd "$HOME"
  export PATH="$HOME/.local/bin:$PATH"

  install_prereqs
  mise="$(mise_bin)"
  check_mise_version

  if [[ "$mode" == migrate ]]; then
    migrate
    return 0
  fi

  case "$(checkout_state)" in
    current) ;;
    legacy) die "$config_dir is still the old $(origin_of) checkout; switch it with: bash <(curl -fsSL $self_url) --migrate" ;;
    foreign) die "$config_dir is a checkout of $(origin_of); move it away first" ;;
    plain)
      if "$dry_run"; then
        die "$config_dir exists but is not a git checkout; a real run moves it to $config_dir.bak.<time> and clones this repo. Run without --dry-run, or move it away yourself"
      fi
      local backup
      backup="$config_dir.bak.$(date +%Y%m%d%H%M%S)"
      mv "$config_dir" "$backup"
      log "moved the existing $config_dir to $backup"
      git clone "$repo_url" "$config_dir"
      ;;
    missing) git clone "$repo_url" "$config_dir" ;;
  esac

  pin_env

  case "$platform" in
    termux)
      # [bootstrap.plugins] only documents Git URLs; link the bundled local plugin here (proven path)
      "$mise" plugins link --force pkg "$config_dir/plugins/pkg"
      ;;
    nanopi)
      # recordings and MariaDB live on the external disk; hdd:init is interactive, runs mkfs,
      # and depends on host:check, so a dry run only reports it. Both are plain bash: do not
      # let `mise run` install the NanoPi's tools first.
      if ! mountpoint -q /mnt/hdd1; then
        if "$dry_run"; then
          log "/mnt/hdd1 is not mounted: a real run starts with \`mise run hdd:init\` (formats a new disk)"
        else
          MISE_TASK_RUN_AUTO_INSTALL=false "$mise" run hdd:init
        fi
      fi
      extra=(--update) # refresh apt metadata after [bootstrap.files] rewrites the apt sources
      ;;
    ubuntu)
      extra=(--update) # same: docker.sources (and winehq.sources) are written at pre-packages
      ;;
  esac

  exec "$mise" bootstrap ${extra[@]+"${extra[@]}"} ${args[@]+"${args[@]}"}
}

main "$@"; exit $?
