# `mb`: My `mise bootstrap` Configurations

[![Check config](https://github.com/eggplants/mb/actions/workflows/check.yml/badge.svg)](https://github.com/eggplants/mb/actions/workflows/check.yml)
[![Validate autoinstall.yaml](https://github.com/eggplants/mb/actions/workflows/validate-autoinstall.yml/badge.svg)](https://github.com/eggplants/mb/actions/workflows/validate-autoinstall.yml)

| Machine | `env` in `miserc.local.toml` |
|---|---|
| macOS (Apple Silicon) | `["macos"]` |
| Termux | `["termux"]` |
| Ubuntu Desktop | `["linux", "ubuntu", "desktop"]` |
| Ubuntu Server | `["linux", "ubuntu"]` |
| NanoPi R6S | `["linux", "nanopi"]` |
| Windows | `["windows"]` |

## Update

```bash
mb --update
mb packages upgrade
```

## Setup

### macOS

```zsh
# Locate keys
mv ~/Downloads/sec ~/.sec.key
mv ~/Downloads/pcs.p12 ~/.bw.p12

bash <(curl -fsSL https://egpl.dev/mb/bootstrap.sh)
mb
```

### Termux

After [Termux](https://termux.dev) installed:

```bash
# Select `Single mirror` > `default` to make `pkg` faster
termux-change-repo

# Enable to access local storage
termux-setup-storage

# Locate keys
mv ~/storage/downloads/sec ~/.sec.key
mv ~/storage/downloads/android.p12 ~/.bw.p12

# Setup
bash <(curl -fsSL https://egpl.dev/mb/bootstrap.sh)
```

### Ubuntu

Install [Ubuntu Desktop](https://ubuntu.com/download/desktop) with [`autoinstall.yaml`](./docs/autoinstall.yaml)
- <https://egpl.dev/mb/autoinstall.yaml>

It installs mise and clones this repo to `~/.config/mise`. After restarted:

```bash
mv ~/Downloads/sec ~/.sec.key
mv ~/Downloads/android.p12 ~/.bw.p12

bash ~/.config/mise/docs/bootstrap.sh
```

### Windows

In PowerShell, as yourself (not as Administrator):

```powershell
mv ~\Downloads\sec ~/.sec.key
mv ~\Downloads\pcs.p12 ~/.bw.p12

& ([scriptblock]::Create((irm https://egpl.dev/mb/bootstrap.ps1)))
```

### NanoPi R6S

<details>

- Machine: [NanoPi R6S](https://www.friendlyelec.com/index.php?route=product/product&product_id=289)
- Tuner: [PX-W3U4](https://plex-net.co.jp/itemreco/px-w3u4/) (driven over libusb by [denpa](https://github.com/danything/denpa); `px4_drv` is blacklisted)
- OS: Debian 13 trixie with the FriendlyELEC kernel

Connect a display and keyboard, log in as `pi`, and create your user:

```bash
sudo useradd -m -G "$(id -Gn pi | tr ' ' '\n' | grep -vx pi | paste -sd,)" eggplants
sudo passwd eggplants
```

Log in as `eggplants`, then:

```bash
bash <(curl -fsSL https://egpl.dev/mb/bootstrap.sh)
sudo reboot

mb
```

If `/mnt/hdd1` is not mounted, `bootstrap.sh` first runs `mise run hdd:init`. It asks you to insert the external disk, then **formats** it after a confirmation.

On a new disk, open denpa, check the tuners and the card reader in Settings > Reception, and scan the channels there.

#### Check

- denpa: <https://npi01.home.arpa>
  Trust Caddy's internal CA root:
  ```bash
  sudo docker exec denpa-genkan-1 cat /data/caddy/pki/authorities/local/root.crt > ~/root.crt
  ```
- Tuner agent: `sudo docker exec denpa-tuner-agent-1 denpa-agent --status | jq` on the NanoPi
- Grafana: <http://npi01.home.arpa:3000>

</details>

## Family

- [eggplants/mb](https://github.com/eggplants/mb) <- here
  - [~eggplants/setup-ubuntu.sh~](https://github.com/eggplants/setup-ubuntu.sh)
  - [~eggplants/setup-termux.sh~](https://github.com/eggplants/setup-termux.sh)
  - [~eggplants/setup-macos.zsh~](https://github.com/eggplants/setup-macos.zsh)
  - [~eggplants/setup-nanopi~](https://github.com/eggplants/setup-nanopi)
  - [~eggplants/SetupWindows.ps1~](https://github.com/eggplants/SetupWindows.ps1)
