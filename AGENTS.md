# AGENTS.md

## What this repo is

The global [mise](https://mise.jdx.dev) config for four kinds of machine:
- macOS (Apple Silicon);
- [Termux](https://termux.dev);
- Ubuntu, Desktop or headless;
- a NanoPi R6S TV server (Debian 12 / FriendlyELEC image, aarch64).

Every machine clones it as `~/.config/mise`. `mise bootstrap` then sets the machine up from `config.toml`, which every machine loads, plus the modules in `conf.d/` that the machine's env list selects.

It replaces eggplants/setup-macos.sh, setup-termux.sh, setup-ubuntu.sh and setup-nanopi; their history stays in those (archived) repos.

## Apply the config

```bash
mb --dry-run   # preview
mb             # apply
```

`mb` is a zsh function in `dotfiles/zshrc`. It runs `mise bootstrap` from `~`, and refuses `-E`/`--env` (and its hidden alias `-P`/`--profile`), a set `MISE_ENV`, `MISE_PROFILE` or `MISE_ENVIRONMENT`, `-C`/`--cd` (another directory would add its project config to the run), and any `unapply` other than `unapply desktop`. Without the zsh setup, run `cd ~ && mise bootstrap` with no `-E`, `-C` or `MISE_ENV`.

## Env selection

`~/.config/mise/miserc.local.toml` pins the env list. It is gitignored and written by `bootstrap.sh` on the first run (it never overwrites an existing one). For each name in the list, `conf.d/<name>/mise.<name>.toml` loads after `config.toml`, in list order, and a later module wins. That order holds only while mise runs outside `conf.d/` (see Gotchas).

| Machine | `env =` | Detected by (tested in this order) |
|---|---|---|
| Termux | `["termux"]` | `$TERMUX_VERSION` is set, or `/data/data/com.termux/files/usr/bin/pkg` is executable |
| macOS | `["macos"]` | `uname -s` is `Darwin` |
| NanoPi R6S | `["linux", "nanopi"]` | Linux, and `/proc/device-tree/model` contains `nanopi` in any case |
| Ubuntu Desktop | `["linux", "ubuntu", "desktop"]` | `/etc/os-release` has `ID=ubuntu`. `bootstrap.sh` adds desktop when `ubuntu-desktop-minimal` is installed. |
| Ubuntu (headless) | `["linux", "ubuntu"]` | the same, without desktop. `DESKTOP=1` / `DESKTOP=0` override the choice. |

- **The order matters.**
  - `linux` comes first: it is the shared base, and the platform module can override any key in it.
  - `desktop` comes last: its `[tasks.bootstrap]` only adds `depends_post`, and that survives only when desktop is listed after ubuntu.
- **These five lists are the only valid selections.**
  - `guard.tera` throws on any other list, or on the wrong host, before step 1 of `mise bootstrap`, `plan`, `status` or `--dry-run`.
  - `host:check` does the same for the task step and for destructive tasks.
- **`-E` (alias `-P`), `MISE_ENV`, `MISE_PROFILE`, `MISE_ENVIRONMENT` and a project `.miserc*.toml` replace the list; they never add to it.** Never use them, and run mise from `~`. Unknown env names are silently ignored.
- **`miserc.toml` (committed) only pins `auto_env = false`.** Never set `env` in it.

## Architecture

| Path | Purpose |
|------|---------|
| `config.toml` | Every machine. It holds: `min_version`; the guard entries; `[bootstrap.repos]` for the zsh plugins and nano syntax; the shared `[dotfiles]`; shell activation; and a fallback `bootstrap` task that fails. The shared dotfiles are zshrc, zshenv and nanorc, plus gitconfig through `variants` on macOS, Termux and Ubuntu. |
| `guard.tera` | Renders empty when the env list is one of the five and matches this host; otherwise `throw()` stops mise before it changes anything |
| `miserc.toml` | `auto_env = false` |
| `bootstrap.sh` | First run only: detects the platform, installs git and mise, clones the repo (unless present), pins `miserc.local.toml` (unless present), runs the platform pre-steps (Termux: link the `pkg` plugin; NanoPi: `hdd:init`), then `exec mise bootstrap` (with `--update` on Ubuntu and the NanoPi). Extra arguments go to `mise bootstrap`. |
| `tasks/host/check` | `host:check` (hidden): fails unless `MISE_ENV` is a valid list that matches this host. `bash tasks/host/check --detect` prints the host's platform. |
| `dotfiles/` | Shared dotfiles: `zshrc` (with `mb()`), `zshenv`, `nanorc`, `gitconfig` |
| `shared/workstation-tools.toml` | The `[tools]` that macOS and Ubuntu share, pulled in by both modules with `include` |
| `shared/tasks/gpg/` | `setup:gpg`, `setup:git` (macOS, Termux, Ubuntu) |
| `shared/tasks/claude/` | `setup:claude` (macOS, Termux, Ubuntu) |
| `shared/tasks/workstation/` | `setup:vscode` (macOS, Ubuntu) |
| `conf.d/linux/` | Ubuntu and NanoPi: the apt base, including Docker CE; the Docker apt repo (one `docker.sources` template); the login shell |
| `conf.d/macos/` | `[tools]`; `brew:`, `brew-cask:` and `mas:` packages; the login shell; the colima LaunchAgent; gpg-agent and Ghostty dotfiles; the `stop-brew-colima.sh` hook; `setup:macos`, `setup:docker` |
| `conf.d/termux/` | `pkg:` packages, `cargo:termscp`, `pipx:claude-statusbar`, hushlogin and gpg-agent dotfiles, the `pre-tools` hook, `setup:shell`, `setup:storage`, `setup:claude-code` |
| `conf.d/ubuntu/` | Headless Ubuntu: `[tools]`, apt packages, rootless Docker, gpg-agent and `environment.d` dotfiles, `setup:docker`, `autoinstall:validate` |
| `conf.d/desktop/` | Ubuntu Desktop add-on: GUI apt packages, the WineHQ repo, the vendor `.deb` hook (`install-vendor-debs.sh`), Ghostty and Wine dotfiles, the TiMidity user unit, GNOME dconf, `setup:desktop` |
| `conf.d/nanopi/` | apt sources (Debian mirror, Tailscale, Grafana); system files; services; `[bootstrap.compose.tv]`; the `install-debs.sh` hook; `authorized_keys`; `setup:system`, `setup:docker`, `setup:konomitv`, `hdd:init`, `tv:playlist` |
| `compose/` | NanoPi Compose project `tv`: mirakc, MariaDB, EPGStation, edcb-bridge. `scanned/` and EPGStation's `data/`, `thumbnail/` and `logs/` are generated and gitignored. |
| `plugins/pkg/` | Package manager plugin that adds the `pkg:` manager for Termux (`pkg` / `dpkg-query`) |
| `docs/autoinstall.yaml` | Ubuntu unattended-install seed file, served via GitHub Pages at <https://egpl.dev/mise-bootstrap/autoinstall.yaml> |
| `ci/check.sh` | Read-only lint, guard and preview checks; run by `.github/workflows/check.yml` |
| `.github/workflows/validate-autoinstall.yml` | Validates `docs/autoinstall.yaml` when it changes |

### Key design decisions

#### All machines

- **Repo = global config, split by env.** Relative `source` paths resolve from the folder of the file that declares them: `~/.config/mise` for `config.toml`, `conf.d/<m>/` for a module. Tools in `[tools]` are global.
- **Declarative first, tasks for the rest.** Use `[bootstrap.*]` and `[dotfiles]` when mise can check the state. Hooks and the `bootstrap` task run on every `mise bootstrap`, so they must be idempotent: guard every step.
- **`config.toml` holds only what is right on all four platforms.** It has no `[tools]`, packages, hooks, services, compose, login shell, `[settings]` or `/etc` files, and `ci/check.sh` enforces this.
- **Fail closed.** These checks stop a wrong or missing selection:
  - `guard.tera`, from `[bootstrap.files]`, and a `[dotfiles]` copy for `--only dotfiles` and `mise dot apply`;
  - `host:check`, which every platform's `bootstrap` task and every destructive task depend on;
  - `mb()`;
  - `bootstrap.sh`, which refuses a set `MISE_ENV`, `MISE_PROFILE` or `MISE_ENVIRONMENT`, and changes to `~`.
- **`[tools]` per module.** Termux cannot run glibc builds, and the NanoPi needs almost none.
  - The 12 tools that macOS and Ubuntu share live in `shared/workstation-tools.toml`, which both modules `include`. It may hold only `[tools]`, and a module's own entry wins over it.
  - Versions that differ stay in the modules: python 3.14.2 and java latest on macOS, python latest and java 21 on Ubuntu.
  - `pipx:` tools need `uv`.
- **`write_targets`.** Every platform module sets `[settings] write_targets.tools`, `.packages` and `.dotfiles` to its own file. So `mise use -g`, `mise bootstrap packages use -g` and `mise dot add` write into this machine's module, never into `config.toml` or a shared include. Desktop sets none, so its writes go to the ubuntu module.
- **The `bootstrap` task.**
  - The base task only fails with "no platform env selected".
  - Each platform module replaces it with `depends = ["host:check"]` and an ordered `run`.
  - Desktop only adds `depends_post = ["setup:desktop"]`, so a step added to Ubuntu also reaches the desktop machine.
  - `setup:desktop` has `#MISE depends=["setup:vscode"]`, so VS Code comes first and the two never overlap. mise runs the entries of one `depends_post` list (and independent `depends`) in parallel; give a new interactive or sudo step an ordering like this one.
- **Git config.** `dotfiles/gitconfig` is static and installed on macOS, Termux and Ubuntu. The NanoPi has no GPG key, so no variant matches there.
  - `setup:git` derives `user.email` and `user.signingkey` from the GPG keyring.
  - It writes them, plus `gpg.program` as an absolute path (macOS GUI apps need it), to `~/.gitconfig.local`.
  - The credential helper is `!gh auth git-credential` (no `/usr/bin/env`, which Termux lacks without termux-exec).
  - `~/.config/git/{allowed_signers,ignore}` are not managed.
- **GPG.**
  - `setup:gpg` imports `~/.sec.key` once and writes the keygrips of the keys that can authenticate to `~/.gnupg/sshcontrol`, using the colon format.
  - Where `pass` is installed, it runs `pass init`. Then it deletes the key file.
  - `setup:gpg` (pinentry) and `setup:git` (`gh auth login --web`) want a terminal. Without one, `setup:gpg` leaves `GPG_TTY` unset, and `setup:git` skips the login with a hint instead of waiting for the device code.
  - `gpg-agent.conf` stays per module (copy, 0600), because the pinentry differs. The cache TTL is the same everywhere (`default-cache-ttl` / `max-cache-ttl` 34560000); change it in all three files.
- **Shell.**
  - `~/.zshrc` and `~/.zshenv` are whole-file dotfiles, so `~/.zshrc` activates mise itself. `[bootstrap.mise_shell_activate] zsh = true, bash = true` only writes shims into `~/.zprofile` and the bash files.
  - Platform lines are guarded at runtime, not split into copies. The guards are `$OSTYPE` (the shfmt wrapper is macOS-only, the wine wrapper Linux-only), `$TERMUX_VERSION`, `[[ -d … ]]`, and `[[ -f ~/.gnupg/gpg-agent.conf ]]` plus an installed `gpgconf`, which leaves the GPG agent off on the NanoPi.
  - Machine-local additions go in `~/.zshrc.d/*.zsh` and `~/.zshenv.d/*.zsh`, outside the repo; `~/.zshrc` and `~/.zshenv` source them last. Installers that append to `~/.zshrc` or `~/.zshenv` would otherwise edit the repo through the symlink.
  - `dotfiles/zshrc` runs `unalias mb` before defining `mb()`, so re-sourcing it in a shell that still has the old `mb` alias works.
  - `[bootstrap.repos]` clones the zsh plugins, and a generic loader skips any that are missing.

#### macOS

- **mise tools vs brew.**
  - CLIs and runtimes come from `[tools]` whenever the mise registry has a macOS build.
  - `brew:` keeps libraries, GNU tools, and CLIs that have no macOS build in the registry (e.g. `ttyd`, `nkf`, `docker`).
  - mise installs `brew:` and `brew-cask:` itself, so Homebrew is optional. `[bootstrap.brew] adopt = true` takes over casks that Homebrew installed.
  - Removing an entry does not uninstall it; use `mise bootstrap packages prune`.
- **Docker.**
  - colima and lima come from `[tools]` and run as the `dev.mise.colima` LaunchAgent (`[bootstrap.services.colima]`, via `~/.local/bin/mise exec`).
  - The docker CLI, buildx, compose and the credential helper stay in `brew:`, so `cliPluginsExtraDirs` can point at the stable `/opt/homebrew/lib/docker/cli-plugins`. `setup:docker` writes that setting and selects the `colima` context.
  - The `post-tools` hook unloads the old `brew services` colima agent.
- **mise itself** is installed by mise.run into `~/.local/bin`, not by Homebrew, because the colima service runs that path. `bootstrap.sh` uses that copy on macOS.
- **PATH.** `/etc/zprofile`'s `path_helper` reorders `PATH` in login shells. So `~/.zshrc` prepends `~/.local/bin` and `/opt/homebrew/bin` again, on Darwin only.
- **Mac App Store.** `mas` comes from `[tools]`, which installs after packages, so a brand-new Mac needs a second `mise bootstrap` to install the `mas:` entries.

#### Termux

- **`pkg:` plugin.**
  - mise reports Termux as `android`, where the built-in `apt` manager is skipped, so `plugins/pkg` adds a `pkg:` manager.
  - `[bootstrap.plugins]` only takes Git URLs, so `bootstrap.sh` runs `mise plugins link --force pkg ~/.config/mise/plugins/pkg` instead. Run that again by hand if the link is lost.
  - Termux's `*-repo` packages (`glibc-repo`, `x11-repo`, `tur-repo`, …) add apt sources. The plugin installs them first and runs `apt-get update`, then the rest, so a package from such a repo (e.g. `glibc-runner`) installs in the same apply.
- **pkg vs mise tools.** Prebuilt mise tools target glibc Linux, not Android, so everything comes from `pkg`. Only tools that are built or installed locally go in `[tools]`: `cargo:` tools (e.g. `termscp`, which `pkg` lacks; `cargo.binstall = false`) and pure-Python `pipx:` tools (e.g. `claude-statusbar`), which uv from `pkg` installs on `pkg`'s python.
- **Packages before tools.**
  - `mise bootstrap` installs `[tools]` before plugin packages, but `cargo:termscp` needs rust, perl, make, pkg-config, samba and dbus, and `pipx:` tools need python and uv, from `pkg`.
  - So the `pre-tools` hook runs `mise -E termux bootstrap packages apply --yes` first.
  - Hooks get no `MISE_ENV`, so the hook passes the selection explicitly, rendered from `{{ mise_env }}`.
- **Login shell.** There is no `[bootstrap.user]` on Termux. It would use `sudo`, `/etc/shells` and `chsh -s <path>`, but Termux's `chsh` takes a shell name and only links `~/.termux/shell`. So `setup:shell` runs `chsh -s zsh`. A dotfile symlink would fail before zsh is installed.
- **Claude Code.** No Android build exists and mise's `claude` is a glibc binary, so `setup:claude-code` runs [claude-code-android](https://github.com/ferrumclaudepilgrim/claude-code-android)'s `install.sh` (Path A), pinned to a commit and checked against a sha256; bump both together.
  - `glibc-repo`, `glibc-runner` and `patchelf-glibc` are `pkg:` packages; the task stops if they are missing, so install.sh never installs them itself. install.sh still runs `apt-get full-upgrade`, then patches the official linux-arm64 binary, and writes a wrapper at `$PREFIX/bin/claude` that updates claude once a day and sets `autoUpdates: false` in `~/.claude/settings.json`.
  - The task answers both installer questions with `n` (keep `$PREFIX/etc` configs, no extra packages) and skips once `~/.local/share/claude/.installer-rev` matches the pinned commit.
  - Its wrapper points Claude Code's own DNS at 8.8.8.8 / 8.8.4.4. Run it from a plain Termux shell, not inside a claude session.
  - `setup:claude` (the claude-statusbar statusLine, shared with macOS and Ubuntu) runs after it, so `~/.claude/settings.json` gets both keys.
- **Task shebangs.** Termux has no `/usr/bin/env` unless termux-exec is active. With `use_file_shell_for_executable_tasks = true`, mise starts a file task as `<interpreter> <file>`, taking the interpreter from the shebang with `/usr/bin/env` stripped. So every task, shared ones included, uses `#!/usr/bin/env bash`. Scripts run outside mise are started with `bash <script>` (for example `bash ~/.config/mise/bootstrap.sh`).

#### Ubuntu

- **Desktop is an add-on module.** `conf.d/ubuntu` is the headless machine and `conf.d/desktop` adds the GUI on top. To drop the desktop, set `env = ["linux", "ubuntu"]` in `miserc.local.toml`, then run `mb unapply desktop`.
- **apt vs mise tools.** System libraries, media tools and GUI apps come from apt. Language runtimes and dev CLIs come from `[tools]`. Ubuntu declares `gnupg`, not the transitional `gnupg2`, and gets `nano` and `ca-certificates` from `conf.d/linux`.
- **Vendor apt repos.**
  - Docker (in `conf.d/linux`) and WineHQ (in desktop) are declared in `[bootstrap.files]` with `phase = "pre-packages"`: a key plus a deb822 `.sources` file. The codename (and, for Docker, the distro and architecture) is rendered with `exec()`.
  - An old `docker.list` is removed, because a second `Signed-By` makes apt fail.
  - Run `mb --update` after the sources change, so apt metadata is refreshed (`bootstrap.sh` does this on the first run).
  - Chrome and VS Code are installed from their `.deb` by the desktop hook, because those packages write their own apt repo, and declaring it ourselves would conflict on `Signed-By`.
- **Docker (rootless).** The rootful `docker` and `docker.socket` system units are declared stopped and disabled, and `setup:docker` runs `dockerd-rootless-setuptool.sh install`. `dotfiles/zshenv` sets `DOCKER_HOST` only when the rootless user unit exists.
- **Wine/RPG2000 setup** is an XDG autostart `.desktop` entry, not a systemd unit. So the blocking GUI installer runs on the first graphical login, never during `mise bootstrap`.
- **GNOME settings.** `setup:desktop` runs `dconf load` (`conf.d/desktop/files/dconf/desktop.ini`) only when a D-Bus session exists. If it was skipped, run `mise run setup:desktop` again from a graphical login.
- **VS Code extensions.** One list, in `setup:vscode`, is run on macOS and on Ubuntu Desktop. Headless Ubuntu lists the task too (it comes with `shared/tasks/workstation`), but its `bootstrap` never runs it, and without `code` it does nothing.
- **`autoinstall.yaml`** installs only the minimum: curl, git, mise and the clone. `bootstrap.sh` does the rest after the first login.
  - Validate it with `mise run autoinstall:validate`, run inside a checkout of this repo. The task exists only in the ubuntu module; elsewhere, run its `docker run` line directly.
  - CI validates the file on every change.

#### NanoPi

- **Shared Linux base.** The apt base, the Docker repo and the login shell come from `conf.d/linux`, together with Ubuntu. This replaces the old "keep in sync with setup-ubuntu.sh" rule. The `docker.sources` template reads `/etc/os-release` and `dpkg --print-architecture`, which must give `debian bookworm arm64` here. The zsh files are the shared ones; the GPG agent block stays off because there is no `gpg-agent.conf`.
- **`.deb` from GitHub releases.** `apt:` entries cannot install a `.deb` by URL, so `install-debs.sh` installs px4_drv, recisdb, ISDBScanner and the rkmppenc deps at versions pinned in the script. To upgrade, bump the version and the URL together.
- **Run order matters.** The `post-packages` hook runs before files, services and compose. So the tuner driver and `compose/scanned/mirakc/config.yml` exist before `[bootstrap.compose.tv]` starts mirakc.
- **Compose runs with `sudo = true`.** The user is added to the `docker` group only by `setup:docker` at the end, and the group takes effect after re-login. `project_dir` is `{{ xdg_config_home }}/mise/compose`, which must be absolute and is unchanged from setup-nanopi.
- **KonomiTV** is installed by its interactive installer, with the answers piped in. It needs a reboot after the Mali driver is installed: the hook leaves `/run/setup-nanopi-reboot-required`, and `setup:konomitv` skips until the next boot.
- **Node.js** comes from apt (system-wide), because KonomiTV runs under `sudo pm2`, which cannot see mise shims.
- **External HDD.**
  - `hdd:init` formats and mounts the external storage at `/mnt/hdd1`. It is interactive and destructive.
  - `bootstrap.sh` runs it on the first run when `/mnt/hdd1` is not mounted.
  - It, like `setup:system` (which removes the `pi` user), has `#MISE depends=["host:check"]`.
- **Runtime data lives in the checkout.** `compose/scanned/` and EPGStation's `data/`, `thumbnail/` and `logs/` are gitignored and stay in place across updates.

## Gotchas

- **Module-relative paths.**
  - Inside `conf.d/<m>/`, these all resolve to the module folder: relative `source` paths, `{{ config_root }}` in hooks, the task cwd, and `$MISE_CONFIG_ROOT`. So hooks call `bash {{ config_root }}/scripts/…`.
  - In `config.toml`, `{{ config_root }}` is `$HOME`.
  - Root `tasks/` run with cwd `~`. Module tasks run with cwd `conf.d/<m>/` (the old repos ran them in `~`), and every task sees `MISE_ENV`. Use absolute paths in tasks.
  - A compose `project_dir` must be absolute.
- **Module order needs a cwd outside `conf.d/`.** With the cwd inside `conf.d/<m>/`, mise also loads `mise.<m>.toml` as a project config, last, so that module beats the ones listed after it (on the NanoPi, from `conf.d/linux/`, `linux` overrides `nanopi`). Module tasks and hooks run in exactly that folder, so never call `mise` from them, except with a one-module `-E` like the Termux `pre-tools` hook. `mb` and `bootstrap.sh` change to `~` first.
- **Hooks accumulate** across files, base first, and a later file cannot remove or replace them. Put a hook only in the module that needs it, never in `config.toml`.
- **Package managers stay in their module.** `brew:` is active on Linux too, `apt:` would reach both Ubuntu and the NanoPi, and an unlinked `pkg:` only warns. `ci/check.sh` checks this.
- **Entries are replaced whole.** A later module replaces whole files, dotfiles, services and compose entries. A module cannot disable a file or directory that an earlier file declares.
- **`os = "linux"`** goes on every `[bootstrap.files]` template that calls `exec()`; without it, `plan` fails on macOS.
- **No duplicate task names per selection.** `tasks/` and each loaded module's `[task_config] includes` load together. If two of those directories define the same name, which one wins depends on the cwd.
  - `setup:docker` exists three times only because macos, ubuntu and nanopi never load together.
  - `ci/check.sh` checks this.
- **No `# MISE` comments in task files.** A comment line that starts with `# MISE` is parsed as a `#MISE` header.
- **A new platform module needs `write_targets`,** or `mise use -g` writes into `config.toml`.
- **`mise dot add` saves the file under `~/.dotfiles`** (mise's `dotfiles.root`), even though the entry goes into the module. Pass `--source ~/.config/mise/conf.d/<platform>/dotfiles/<name>` to keep the file in this repo.
- **Keep the guard copies in sync.** The allowed lists appear in `guard.tera`, `tasks/host/check`, `bootstrap.sh` and `ci/check.sh`. The host tests are in `tasks/host/check` and `bootstrap.sh` (shell) and `guard.tera` (Tera); `ci/check.sh` checks all three for the same markers.
  - A new destructive task gets `#MISE depends=["host:check"]`.
  - The guard covers only runs that include files, dotfiles or the `bootstrap` task. An explicit wrong `-E` with any other `--only` selection (packages, services, compose, tools, repos, user, linux-systemd-units, mise-shell-activate, …) runs unchecked.
  - The dotfile copy of the guard writes an empty `~/.local/state/mise-bootstrap/dotfiles-guard`, which shows up in `mise dot status`.
- **Unapplying this machine's own env is destructive.** `mise bootstrap unapply <module>` removes the files, dotfiles, directories and user services that the module declares; mise only asks for confirmation (or not, with `--yes`). For example, `unapply nanopi` removes `~/.ssh/authorized_keys`. Only `mb unapply desktop` is supported.
  - The shared dotfiles survive, because `config.toml` still declares them.
- **Never run `git clean -x` in `~/.config/mise` on the NanoPi.** It deletes the gitignored runtime data under `compose/`.
- **`min_version`.** `config.toml` requires mise 2026.10.7 or newer.
  - An older mise fails on every call, including the shell hook. Termux gets mise from `pkg`.
  - Bump `min_version` and `MISE_VERSION` in `check.yml` together.
- **Previewing another platform.** On this host the guard rejects `mise -E <other platform>`, and that is intended. To preview, run `bash ci/check.sh`: it dry-runs every selection from a copy with the host test stripped.
- **macOS `plan` and `status` need Ruby 3 or newer on `PATH`**, to evaluate the `openai/tools` tap cask: mise's ruby, as in an activated shell (`/usr/bin/ruby` is 2.6). They also call the GitHub API: without `gh auth login` or a `GITHUB_TOKEN`, the 60-requests-an-hour anonymous limit applies.
- **History.** For files merged from the four repos, use `git log -- <path>` or `git blame -C`. `--follow` gets confused by the near-identical imported siblings.
- **Fix forward; do not `git revert` old commits.** Before the copies were merged, a fix touched one platform's copy. Git's rename detection carries a revert of such a commit into the shared file, without a conflict: reverting "fix: write the authentication keygrip to sshcontrol on macOS" rewrites `shared/tasks/gpg/setup/gpg` for Termux and Ubuntu too. If you must revert, check `git show --stat` before pushing.

## Check

```bash
bash ci/check.sh   # read-only: lint, guard, and a dry-run preview of every selection in a throwaway HOME
```

## Test in Docker (Termux)

```bash
docker run -d --name termux termux/termux-docker:latest sleep infinity
docker exec termux mkdir -p /data/data/com.termux/files/home/.config
docker cp . termux:/data/data/com.termux/files/home/.config/mise
docker exec termux chown -R 1000:1000 /data/data/com.termux/files/home/.config
docker exec -it termux /entrypoint.sh bash -lc '
  pkg upgrade -y && pkg install -y mise git rust &&
  cd ~/.config/mise && rm -f miserc.local.toml &&
  { git remote get-url origin || git remote add origin https://github.com/eggplants/mise-bootstrap.git; } &&
  cd ~ && mise trust -a && bash ~/.config/mise/bootstrap.sh'
docker rm -f termux
```

- Run commands through `/entrypoint.sh`, so they run as the Termux user; `pkg` refuses to run as root.
- `docker cp` needs the parent directory, and a fresh container has no `~/.config`.
- `rm -f miserc.local.toml` drops this host's pin, which `docker cp` copied in. `bootstrap.sh` then detects Termux (via `.../usr/bin/pkg`) and pins `env = ["termux"]`.
- `bootstrap.sh` refuses a `~/.config/mise` whose `origin` is not this repo.
- The container has no termux-exec (`LD_PRELOAD` is empty), so a `#!/usr/bin/env` script cannot be started directly there. Start scripts with `bash <script>`. File tasks still work, through `use_file_shell_for_executable_tasks`.
- The container has no Android framework, so `getprop` and `termux-setup-storage` fail there.
- For a quick check, end with `bash ~/.config/mise/bootstrap.sh --dry-run`.
