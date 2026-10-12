# Migrate

These steps switch a machine that still has a `~/.config/mise` checkout of setup-macos.sh, setup-termux.sh, setup-ubuntu.sh or setup-nanopi.

Do it once per machine, in this order: Mac, Termux, Ubuntu, NanoPi. Run from `~`, with no `MISE_ENV` exported:

```bash
git -C ~/.config/mise status -sb --ignored   # clean, nothing ahead of origin
bash <(curl -fsSL https://raw.githubusercontent.com/eggplants/mise-bootstrap/main/bootstrap.sh) --check
bash <(curl -fsSL https://raw.githubusercontent.com/eggplants/mise-bootstrap/main/bootstrap.sh) --migrate
```

Local changes and commits that this repo lacks would be lost by the switch, so `--migrate` refuses them, and committing them to the old repo does not help. `~/.zshrc` and `~/.zshenv` are symlinks into the checkout, so an installer that appends a line to them (a `PATH` setup, say) leaves such a change. Move that line to `~/.zshrc.d/<name>.zsh` or `~/.zshenv.d/<name>.zsh`, port anything else to this repo, and restore the file with `git -C ~/.config/mise checkout -- <file>`. `--check` shows the count on its `changes:` line.

`--migrate` switches `~/.config/mise` in place and applies nothing but the dotfile links and `gpg.program`. It takes no other arguments. Then, in order, it:
1. refuses to continue if `miserc.local.toml` already pins another selection (setup-ubuntu.sh's `env = ["desktop"]` is the one it replaces);
2. fetches this repo;
3. refuses to continue if the old branch has commits that this repo lacks (the old repo's final "moved" commit excepted);
4. refuses to continue if local files would be overwritten by the new tree;
5. checks the new config, guard included, from a temporary worktree;
6. pins the env;
7. switches to `main`. The old branch becomes `legacy-<branch>` and the old remote becomes `legacy`;
8. prints the commands to roll back (they also restore the old pin);
9. links the dotfiles again (and, on Termux, the `pkg` plugin) and, except on the NanoPi, writes `gpg.program` to `~/.gitconfig.local` as `setup:git` does: the shared gitconfig no longer names gpg, and GUI git clients on macOS need its absolute path to sign;
10. prints `mise bootstrap plan`.

A refusal leaves the checkout as it was. After the switch, open a new shell (`exec zsh -l`) rather than `source ~/.zshrc`, so nothing from the old zshrc is left over.

Review, then apply:

```bash
mise config ls        # config.toml + this machine's modules
MISE_TASK_RUN_AUTO_INSTALL=false mise run host:check   # exits 0 (the variable skips installing missing tools first)
mise bootstrap plan   # the guard shows "absent (template rendered empty)"
mise dot status       # the links point into ~/.config/mise/
bash ~/.config/mise/bootstrap.sh
```

Per platform:
- **Termux:** run `pkg upgrade mise` first. mise must be 2026.10.7 or newer.
- **Ubuntu:** the old `env = ["desktop"]` pin becomes `["linux", "ubuntu", "desktop"]`, and a backup is kept.
- **NanoPi:**
  - `tr -d '\0' </proc/device-tree/model` must contain "NanoPi" (any case).
  - `. /etc/os-release; echo $ID $VERSION_CODENAME; dpkg --print-architecture` must print `debian bookworm arm64`, which the shared `docker.sources` template relies on.
  - Choose a time with no recording scheduled.
  - Compose keeps running, and `compose/` and its data stay where they are.
  - Never run `git clean -x` in `~/.config/mise`.
