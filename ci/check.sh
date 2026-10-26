#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
status=0
fail() {
  echo "FAIL: $*" >&2
  status=1
}
selections=("macos" "termux" "linux,ubuntu" "linux,ubuntu,desktop" "linux,nanopi" "windows")
platform_of() { # <selection> -> the host it is meant for
  case "$1" in
    linux,ubuntu | linux,ubuntu,desktop) echo ubuntu ;;
    linux,nanopi) echo nanopi ;;
    *) echo "$1" ;;
  esac
}

# 1. The base config must be right on every platform; miserc.toml never selects an env.
for re in '^\[tools\]' '^\[bootstrap\.packages\]' '^\[bootstrap\.hooks' '^\[bootstrap\.services' \
  '^\[bootstrap\.compose' '^\[bootstrap\.user\]' '^\[bootstrap\.linux' '"/etc/' '^\[settings' '^include'; do
  ! grep -qE "$re" config.toml || fail "config.toml must not contain $re (platform-specific)"
done
! grep -qE '^[[:space:]]*env[[:space:]]*=' miserc.toml || fail "miserc.toml must not set env (per machine: miserc.local.toml)"
grep -qx 'auto_env = false' miserc.toml || fail "miserc.toml must pin auto_env = false"
# In ~/.config/mise, mise.toml would be global config on every machine; dev tasks are .mise.toml.
[[ ! -e mise.toml ]] || fail "mise.toml must not exist at the repo root (dev config: .mise.toml)"

# 2. conf.d holds only folder modules named after their folder: mise loads conf.d/*.toml and
#    conf.d/<m>/mise.toml on every machine, and conf.d/<m>/mise.<x>.toml for env <x>.
for f in conf.d/*; do
  m="${f#conf.d/}"
  [[ -d "$f" ]] || fail "$f: only module folders belong in conf.d/"
  [[ ! -d "$f" || -f "$f/mise.$m.toml" ]] || fail "$f has no mise.$m.toml"
done
for f in conf.d/*/*.toml; do
  m="${f#conf.d/}"
  m="${m%%/*}"
  [[ "$f" == "conf.d/$m/mise.$m.toml" ]] || fail "$f: a module folder holds only mise.$m.toml"
done

# 3. Package managers stay in the modules of their platform; shared/*.toml hold [tools] only.
check_only() { # <pattern> <allowed module folders...>
  local pat="$1" f
  shift
  while read -r f; do fail "$pat in $f"; done < <(
    grep -rlE "$pat" --include='*.toml' . | grep -vE "^\./conf\.d/($(
      IFS='|'
      echo "$*"
    ))/" || true
  )
}
check_only '^"brew(-cask)?:|^"mas:' macos
check_only '^"apt:' linux ubuntu desktop nanopi
check_only '^"flatpak(-user)?:' desktop
check_only '^"pkg:' termux
check_only '^"winget:' windows
if compgen -G 'shared/*.toml' >/dev/null; then
  while read -r f; do fail "shared/ may only hold [tools]: $f"; done < <(grep -HE '^\[' shared/*.toml | grep -v ':\[tools\]$' || true)
fi

# 4. No task name may come from two directories that load together (which one wins would
#    be up to mise). Directories: tasks/ plus every loaded module's [task_config] includes.
task_dirs() { # <selection>
  local m f inc
  echo tasks
  for m in ${1//,/ }; do
    f="conf.d/$m/mise.$m.toml"
    [[ -f "$f" ]] || continue
    for inc in $(sed -n 's/^includes = \[\(.*\)\]$/\1/p' "$f" | tr -d '",'); do
      echo "conf.d/$m/$inc"
    done
  done
}
for sel in "${selections[@]}"; do
  for d in $(task_dirs "$sel"); do [[ -d "$d" ]] || fail "[$sel]: task directory $d does not exist"; done
  dups="$(for d in $(task_dirs "$sel"); do (cd "$d" 2>/dev/null && find . -type f); done | sort | uniq -d)"
  [[ -z "$dups" ]] || fail "duplicate task file(s) for [$sel]: $dups"
done

# 5. Runtime data and machine pins stay ignored; scripts and tasks stay executable.
#    PowerShell scripts stay non-executable: an executable tasks/host/check.ps1 would be a second
#    host:check task on Linux and macOS (mise picks the .ps1 of a pair only on Windows).
for p in /compose/scanned/ /compose/epgstation/data/ /compose/epgstation/thumbnail/ /compose/epgstation/logs/ \
  miserc.local.toml '*.local.toml'; do
  grep -qxF "$p" .gitignore || fail ".gitignore lacks $p"
done
while read -r f; do
  if [[ "$f" == *.ps1 ]]; then
    [[ ! -x "$f" ]] || fail "$f is executable; PowerShell scripts must not be (chmod -x)"
    continue
  fi
  [[ -x "$f" ]] || fail "$f is not executable"
done < <({
  echo docs/bootstrap.ps1
  echo docs/bootstrap.sh
  echo ci/check.sh
  find tasks shared/tasks conf.d/*/tasks conf.d/*/scripts conf.d/*/bin conf.d/*/pwsh -type f 2>/dev/null
} | sort)

# 6. guard.tera, tasks/host/check and bootstrap.sh detect hosts with the same tests, and every
#    allowed list is known to the guard and to tasks/host/check; on Windows, tasks/host/check.ps1
#    and bootstrap.ps1 take their place, and the guard runs only from [dotfiles].
for marker in 'grep -aqsi nanopi /proc/device-tree/model' '/data/data/com.termux/files/usr/bin/pkg' \
  'TERMUX_VERSION' '/etc/os-release'; do
  grep -qF "$marker" guard.tera || fail "guard.tera lacks the host test '$marker'"
  grep -qF "$marker" tasks/host/check || fail "tasks/host/check lacks the host test '$marker'"
  grep -qF "$marker" docs/bootstrap.sh || fail "docs/bootstrap.sh lacks the host test '$marker'"
done
grep -qF 'os() == "windows"' guard.tera || fail "guard.tera lacks the Windows host test"
for f in tasks/host/check tasks/host/check.ps1 docs/bootstrap.ps1; do
  grep -qF 'Windows_NT' "$f" || fail "$f lacks the Windows host test 'Windows_NT'"
done
grep -qF "= '[\"windows\"]'" docs/bootstrap.ps1 || fail "docs/bootstrap.ps1 does not pin env = [\"windows\"]"
grep -q '^{#- host check' guard.tera || fail "guard.tera lacks the '{#- host check' line that previews cut at"
if ! grep -qE '^\[dotfiles\."~/\.local/state/mise-bootstrap/dotfiles-guard"\]' config.toml ||
  ! grep -qx 'os = "unix"' config.toml; then
  fail "config.toml must keep the [dotfiles] guard and limit the [bootstrap.files] guard to unix"
fi
for sel in "${selections[@]}"; do
  grep -qF "\"$sel\"" guard.tera || fail "guard.tera does not allow [$sel]"
  grep -qF "$sel" tasks/host/check || fail "tasks/host/check does not allow [$sel]"
  grep -qF "'$sel'" tasks/host/check.ps1 || fail "tasks/host/check.ps1 does not allow [$sel]"
done

# 7. mise, in a throwaway HOME: every selection loads exactly its modules, has a platform
#    bootstrap task that runs host:check first, and dry-runs cleanly in a preview copy whose
#    guard has no host test; the guard rejects bad selections, and the real guard accepts
#    only this host's own selections.
command -v mise >/dev/null || {
  echo "FAIL: mise not found" >&2
  exit 1
}
sb="$(mktemp -d "${TMPDIR:-/tmp}/mise-bootstrap-check.XXXXXX")"
trap 'rm -rf "$sb"' EXIT
export HOME="$sb/home" XDG_CONFIG_HOME="$sb/home/.config" XDG_DATA_HOME="$sb/home/.local/share" \
  XDG_STATE_HOME="$sb/home/.local/state" XDG_CACHE_HOME="$sb/home/.cache" \
  MISE_DATA_DIR="$sb/data" MISE_STATE_DIR="$sb/state" MISE_CACHE_DIR="$sb/cache" MISE_SYSTEM_CONFIG_DIR="$sb/etc"
unset MISE_ENV MISE_PROFILE MISE_ENVIRONMENT MISE_CONFIG_DIR MISE_GLOBAL_CONFIG_FILE MISE_OVERRIDE_CONFIG_FILENAMES
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE # set when run from a git hook
mkdir -p "$XDG_CONFIG_HOME"
cp -R "$repo" "$XDG_CONFIG_HOME/mise"
cp -R "$repo" "$sb/preview"
rm -f "$XDG_CONFIG_HOME"/mise/*.local.toml "$sb"/preview/*.local.toml
export MISE_CONFIG_DIR="$XDG_CONFIG_HOME/mise"
sed -i.bak '/^{#- host check/,$d' "$sb/preview/guard.tera"
cd "$HOME"
for sel in "${selections[@]}"; do
  want=config.toml
  for m in ${sel//,/ }; do want="$want conf.d/$m/mise.$m.toml"; done
  if mise -E "$sel" config ls >"$sb/out" 2>"$sb/err"; then
    got="$(awk '{print $1}' "$sb/out" | sed 's#^~/\.config/mise/##' | tr '\n' ' ')"
    [[ "${got% }" == "$want" ]] || fail "[$sel] loads [${got% }], expected [$want]"
  else
    fail "config for [$sel] does not load: $(tail -3 "$sb/err")"
  fi
  info="$(mise -E "$sel" tasks info bootstrap 2>&1 || true)"
  grep -q 'conf.d/' <<<"$info" || fail "[$sel] has no platform bootstrap task"
  grep -q 'Depends on: host:check' <<<"$info" || fail "[$sel] bootstrap task does not depend on host:check"
  tasks="$(mise -E "$sel" tasks ls 2>/dev/null | awk '{print $1}')"
  if [[ "$sel" != linux,nanopi ]] && grep -qx 'hdd:init' <<<"$tasks"; then
    fail "[$sel] lists the NanoPi-only hdd:init task"
  fi
  # from /: under $HOME, ~/.config/mise would be read as a (untrusted) project config
  (cd / && MISE_CONFIG_DIR="$sb/preview" mise -E "$sel" bootstrap --dry-run --skip packages,tools,task,compose) \
    >/dev/null 2>"$sb/err" || fail "preview dry-run for [$sel] fails: $(tail -3 "$sb/err")"
done
post="$(sed -n 's/^depends_post = \[\(.*\)\]$/\1/p' "$repo/conf.d/desktop/mise.desktop.toml" | tr -d '"')"
grep -qF "Depends post: $post" <<<"$(mise -E linux,ubuntu,desktop tasks info bootstrap 2>/dev/null)" ||
  fail "desktop does not append [$post] to the bootstrap task"
for bad in "" desktop ubuntu nanopi linux linux,desktop,ubuntu desktop,linux,ubuntu ubuntu,linux macos,nanopi \
  linux,ubunut termux,macos linux,windows windows,desktop; do
  out="$(MISE_ENV="$bad" mise bootstrap files status 2>&1 || true)"
  grep -q 'mise-bootstrap guard: env selection' <<<"$out" || fail "guard accepted [$bad]"
done
host="$(bash "$repo/tasks/host/check" --detect)"
for sel in "${selections[@]}"; do
  out="$(MISE_ENV="$sel" mise bootstrap files status 2>&1)" && rc=0 || rc=$?
  if [[ "$(platform_of "$sel")" == "$host" ]]; then
    [[ "$rc" == 0 ]] || fail "the guard rejects [$sel] on this $host host: $(tail -3 <<<"$out")"
  else
    grep -q "but this host is $host" <<<"$out" || fail "the guard accepts [$sel] on this $host host"
  fi
done
# The CI runner is Ubuntu: the real plan must work there.
if [[ "$host" == ubuntu ]]; then
  MISE_ENV=linux,ubuntu,desktop mise bootstrap plan >/dev/null 2>"$sb/err" ||
    fail "plan for linux,ubuntu,desktop fails: $(tail -3 "$sb/err")"
fi
[[ "$status" == 0 ]] && echo "ci/check.sh: all checks passed" >&2
exit "$status"
