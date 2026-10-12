# mise-bootstrap

[![Check config](https://github.com/eggplants/mise-bootstrap/actions/workflows/check.yml/badge.svg)](https://github.com/eggplants/mise-bootstrap/actions/workflows/check.yml)
[![Validate autoinstall.yaml](https://github.com/eggplants/mise-bootstrap/actions/workflows/validate-autoinstall.yml/badge.svg)](https://github.com/eggplants/mise-bootstrap/actions/workflows/validate-autoinstall.yml)

| Machine | `env` in `miserc.local.toml` |
|---|---|
| macOS (Apple Silicon) | `["macos"]` |
| Termux | `["termux"]` |
| Ubuntu Desktop | `["linux", "ubuntu", "desktop"]` |
| Ubuntu Server | `["linux", "ubuntu"]` |
| NanoPi R6S | `["linux", "nanopi"]` |

## Update

```bash
git -C ~/.config/mise pull --ff-only && mb --only dotfiles
mb --dry-run
mb
mise bootstrap status
```

## Setup

### macOS

```zsh
# Place your GPG secret key at ~/.sec.key, then:
bash <(curl -fsSL https://raw.githubusercontent.com/eggplants/mise-bootstrap/main/bootstrap.sh)

# Run again to install `mas` packages
mb
```

### Termux

After [Termux](https://termux.dev) installed:

```bash
# select `Single mirror` > `default` to make `pkg` faster
termux-change-repo

# enable to access local storage
termux-setup-storage

# locate my.gpg key
mv ~/storage/downloads/sec ~/.sec.key

# setup
bash <(curl -fsSL https://raw.githubusercontent.com/eggplants/mise-bootstrap/main/bootstrap.sh)
```

### Ubuntu

Install [Ubuntu Desktop](https://ubuntu.com/download/desktop) with [`autoinstall.yaml`](./docs/autoinstall.yaml)
- <https://egpl.dev/mise-bootstrap/autoinstall.yaml>

It installs mise and clones this repo to `~/.config/mise`. After restarted:

```bash
# Place your GPG secret key at ~/.sec.key, then:
bash ~/.config/mise/bootstrap.sh
```

### NanoPi R6S

<details>

- Machine: [NanoPi R6S](https://www.friendlyelec.com/index.php?route=product/product&product_id=289)
- Tuner: [PX-W3U4](https://plex-net.co.jp/itemreco/px-w3u4/) (`/dev/px4video{0..3}`)
- Card reader: [SCR3310 v2.0](https://www.ntt.com/business/services/application/authentication/jpki/download10.html)
- OS: [rk3568-sd-debian-bookworm-core-6.1-arm64-20250811.img](https://drive.google.com/file/d/1hA3pUcZzdfSN1htq-3Nxn5ECr0EA1sa6/view?usp=drive_link) (Debian 12 / Linux 6.1, aarch64)

Connect a display and keyboard, log in as `pi`, and create your user:

```bash
sudo useradd -m -G "$(id -Gn pi | tr ' ' '\n' | grep -vx pi | paste -sd,)" eggplants
sudo passwd eggplants
```

Log in as `eggplants`, then:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eggplants/mise-bootstrap/main/bootstrap.sh)
sudo reboot

mb
```

If `/mnt/hdd1` is not mounted, `bootstrap.sh` first runs `mise run hdd:init`. It asks you to insert the external disk, then **formats** it after a confirmation.

#### Tasks

```bash
mise run tv:playlist                           # writes channels.m3u8 to the current directory
rm -rf ~/.config/mise/compose/scanned && mb    # scan the channels again
```

#### Check

- mirakc: `http://npi01.<tailnet>.ts.net:40772/api/version`
- EPGStation: `http://npi01.<tailnet>.ts.net:8888/#/`
- KonomiTV: `https://<tailscale-ip-with-dashes>.local.konomi.tv:7000/tv/`
- Grafana: `http://npi01.<tailnet>.ts.net:3000`

</details>

## Family

- [eggplants/mise-bootstrap](https://github.com/eggplants/mise-bootstrap) <- here
- [eggplants/SetupWindows.ps1](https://github.com/eggplants/SetupWindows.ps1)
