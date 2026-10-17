# AGENTS.md

## What this repo is

The global [mise](https://mise.jdx.dev) config (`mise bootstrap`) for five kinds of machine: macOS (Apple Silicon), Termux, Ubuntu (Desktop or headless), a NanoPi R6S TV server (Debian 12, aarch64) and Windows (PowerShell 7). Every machine clones it as `~/.config/mise`. It replaces the archived setup-macos.sh, setup-termux.sh, setup-ubuntu.sh, setup-nanopi and SetupWindows.ps1 repos.

## Commands

```bash
bash ci/check.sh   # the only test: read-only lint, guard checks, and a dry-run of every selection in a throwaway HOME (CI runs it too)
mb --dry-run       # preview on this machine (zsh function in dotfiles/zshrc)
mb                 # git pull --ff-only, then `cd ~ && mise bootstrap`
```

- Never pass `-E`/`-P`, set `MISE_ENV`/`MISE_PROFILE`/`MISE_ENVIRONMENT`, or use `-C`: they *replace* the machine's env list. Always run mise from `~`, never from inside `conf.d/`.
- To preview another platform, use `bash ci/check.sh`; the guard intentionally rejects `mise -E <other platform>` on this host.
- `mise run autoinstall:validate` (Ubuntu module only) validates `docs/autoinstall.yaml` with Docker.

## Env selection

`miserc.local.toml` (gitignored, written once by `docs/bootstrap.sh` / `docs/bootstrap.ps1`) pins `env`. For each name, `conf.d/<name>/mise.<name>.toml` loads after `config.toml`, in order; a later module wins. Only six lists are valid:

| Machine | `env` |
|---|---|
| macOS | `["macos"]` |
| Termux | `["termux"]` |
| Ubuntu Desktop | `["linux", "ubuntu", "desktop"]` |
| Ubuntu headless | `["linux", "ubuntu"]` |
| NanoPi | `["linux", "nanopi"]` |
| Windows | `["windows"]` |

`linux` is the shared Ubuntu/NanoPi base (apt base, Docker repo, login shell) and must come first; `desktop` must come last because it only adds `depends_post = ["setup:desktop"]` to Ubuntu's `bootstrap` task. `miserc.toml` (committed) only pins `auto_env = false`.

**Fail closed.** A wrong or missing selection is stopped by `guard.tera` (rendered from `[bootstrap.files]`, plus a `[dotfiles]` copy for Windows and `--only dotfiles`), by the hidden `host:check` task (`tasks/host/check`, twin `tasks/host/check.ps1`) that every `bootstrap` task and destructive task depends on, by `mb()`, and by the bootstrap scripts. The allowed lists and host tests are duplicated in `guard.tera`, `tasks/host/check`, `tasks/host/check.ps1`, `docs/bootstrap.sh`, `docs/bootstrap.ps1` and `ci/check.sh` — change them together. A new destructive task gets `#MISE depends=["host:check"]`.

## Architecture

- `config.toml` holds only what is right on all five platforms: `min_version`, the guard, `[bootstrap.repos]` (zsh plugins, nano syntax), shared `[dotfiles]` (`dotfiles/`), shell activation, and a fallback `bootstrap` task that fails. It must not contain `[tools]`, packages, hooks, services, compose, `[settings]`, `include` or `/etc` files (`ci/check.sh` enforces this). Entries in `[bootstrap.files]`/`[bootstrap.directories]` there need `os = "unix"`.
- `conf.d/<platform>/` holds everything platform-specific. Each platform module replaces the `bootstrap` task with `depends = ["host:check"]` plus an ordered `run` of `setup:*` tasks, and sets `[settings] write_targets.{tools,packages,dotfiles}` to its own file so `mise use -g` / `mise dot add` never write into `config.toml` (a new module needs this too).
- `shared/workstation-tools.toml` is the `[tools]` that macOS and Ubuntu share via `include` (it may hold only `[tools]`). A tool for every machine (e.g. ripgrep, dockerfile-pin) goes there plus the NanoPi, Windows and Termux modules.
- `shared/tasks/{gpg,claude,workstation}/` are bash file tasks pulled in through `[task_config] includes`. No task name may be defined in two directories that load together (`ci/check.sh` checks).
- Package managers stay in their module: `brew:`/`brew-cask:`/`mas:` in macos, `apt:` in linux/ubuntu/desktop/nanopi, `pkg:` in termux, `winget:` in windows (checked by CI).
- `plugins/pkg/` adds the `pkg:` package manager for Termux (mise's `apt` is skipped on `android`). `bootstrap.sh` links it with `mise plugins link`.
- `compose/` is the NanoPi Compose project `tv` (mirakc, MariaDB, EPGStation, edcb-bridge). Its `scanned/` and EPGStation runtime dirs are gitignored data — never `git clean -x` on the NanoPi.
- `docs/` is served at <https://egpl.dev/mb/>: `bootstrap.sh`, `bootstrap.ps1`, `autoinstall.yaml`.

Prefer declarative `[bootstrap.*]`/`[dotfiles]`; use tasks or hooks only for the rest, and make them idempotent (they run on every `mise bootstrap`).

## Gotchas

- **Module-relative paths.** In `conf.d/<m>/`, relative `source` paths, `{{ config_root }}`, `$MISE_CONFIG_ROOT` and the task cwd are the module folder (in `config.toml`, `{{ config_root }}` is `$HOME`). Use absolute paths in tasks; a compose `project_dir` must be absolute.
- **Never call `mise` from module tasks/hooks** (their cwd is inside `conf.d/<m>/`, which reorders modules), except with a one-module `-E` like the Termux `pre-tools` hook, which installs `pkg:` packages before `[tools]` (cargo/go/pipx tools there build on pkg's toolchains).
- **Hooks accumulate** across files and cannot be removed by a later module; put them only in the module that needs them. Whole entries (files, dotfiles, services, compose) are replaced, not merged.
- `[bootstrap.files]` templates that call `exec()` need `os = "linux"`, or `plan` fails on macOS.
- Task shebangs are `#!/usr/bin/env bash` (Termux relies on `use_file_shell_for_executable_tasks`). Scripts outside mise are run as `bash <script>`. Never start a comment line with `# MISE` in a task file (parsed as a header).
- Windows tasks are non-executable `.ps1` files (`setup/pwsh.ps1` → `setup:pwsh`); keep them `chmod -x`, or Linux/macOS list them as tasks. Nothing in CI runs the PowerShell code.
- Termux: prebuilt glibc binaries don't run, so tools come from `pkg:` or are built locally (`cargo:`, `go:`, `pipx:`). Termux tasks must not depend on `/usr/bin/env` outside mise.
- `mise bootstrap unapply <module>` deletes what the module declares; only `mb unapply desktop` is supported.
- `config.toml` requires mise `min_version` 2026.10.7; bump it together with `MISE_VERSION` in `.github/workflows/check.yml`.
- Fix forward, don't `git revert` old commits: rename detection can carry a per-platform revert into a shared file. Use `git log -- <path>` / `git blame -C` for history (not `--follow`).

## Test Termux in Docker

```bash
docker run -d --name termux termux/termux-docker:latest sleep infinity
docker exec termux mkdir -p /data/data/com.termux/files/home/.config
docker cp . termux:/data/data/com.termux/files/home/.config/mise
docker exec termux chown -R 1000:1000 /data/data/com.termux/files/home/.config
docker exec -it termux /entrypoint.sh bash -lc '
  pkg upgrade -y && pkg install -y mise git rust &&
  cd ~/.config/mise && rm -f miserc.local.toml &&
  { git remote get-url origin || git remote add origin https://github.com/eggplants/mb.git; } &&
  cd ~ && mise trust -a && bash ~/.config/mise/docs/bootstrap.sh --dry-run'
docker rm -f termux
```

Run commands through `/entrypoint.sh` (pkg refuses root). `getprop` and `termux-setup-storage` fail in the container.
