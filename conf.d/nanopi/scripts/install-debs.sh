#!/usr/bin/env bash
set -euo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mise"
reboot_marker=/run/setup-nanopi-reboot-required

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# install_deb <package> <version> <url>
# Installs when the package is missing or at another version, and sets $changed.
changed=false
install_deb() {
  changed=false
  local installed
  installed="$(dpkg-query -W -f='${Status} ${Version}' "$1" 2>/dev/null || true)"
  if [[ "$installed" == "install ok installed $2" ]]; then
    return
  fi
  local deb="$tmp/$1.deb"
  curl -fL --retry 3 -o "$deb" "$3"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$deb"
  changed=true
}

# px4_drv (PX-W3U4) needs the kernel headers shipped with the FriendlyELEC image
kernel="$(uname -r)"
if ! dpkg-query -W -f='${Status}' "linux-headers-$kernel" 2>/dev/null | grep -q 'ok installed'; then
  headers=(/opt/archives/linux-headers-"${kernel}_${kernel}"-*_arm64.deb)
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${headers[0]}"
fi

# https://github.com/tsukumijima/px4_drv/releases
install_deb px4-drv-dkms 0.6.1 \
  https://github.com/tsukumijima/px4_drv/releases/download/v0.6.1/px4-drv-dkms_0.6.1_all.deb
lsmod | grep -q '^px4_drv ' || sudo modprobe px4_drv

# https://github.com/kazuki0824/recisdb-rs/releases
install_deb recisdb 1.3.0-1 \
  https://github.com/kazuki0824/recisdb-rs/releases/download/1.3.0/recisdb_1.3.0-1_arm64.deb

# https://github.com/tsukumijima/ISDBScanner/releases
isdb_scanner_version=1.3.3
if [[ "$(isdb-scanner --version 2>/dev/null || true)" != *"$isdb_scanner_version"* ]]; then
  curl -fL --retry 3 -o "$tmp/isdb-scanner" \
    "https://github.com/tsukumijima/ISDBScanner/releases/download/v$isdb_scanner_version/isdb-scanner-arm"
  sudo install -m 755 "$tmp/isdb-scanner" /usr/local/bin/isdb-scanner
fi

# rkmppenc (KonomiTV) needs the Mali GPU driver; a reboot is required after installing it
install_deb libmali-valhall-g610-g13p0-wayland-gbm 1.9-1 \
  https://github.com/tsukumijima/libmali-rockchip/releases/download/v1.9-1-20260312-bd33ee2/libmali-valhall-g610-g13p0-wayland-gbm_1.9-1_arm64.deb
if "$changed"; then sudo touch "$reboot_marker"; fi
install_deb rockchip-multimedia-config 1.0.2-1 \
  https://github.com/tsukumijima/rockchip-multimedia-config/releases/download/v1.0.2-1/rockchip-multimedia-config_1.0.2-1_all.deb
if "$changed"; then sudo touch "$reboot_marker"; fi

# Scan receivable channels for mirakc (takes ~6 minutes).
# Delete compose/scanned/ and re-run to scan again.
if [[ ! -f "$config_dir/compose/scanned/mirakc/config.yml" ]]; then
  (cd "$config_dir/compose" && isdb-scanner)
fi
