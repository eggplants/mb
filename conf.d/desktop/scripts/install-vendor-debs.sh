#!/usr/bin/env bash
set -euo pipefail

# Wine needs i386 packages
if ! dpkg --print-foreign-architectures | grep -qx i386; then
  sudo dpkg --add-architecture i386
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# install_deb <package> <url>
install_deb() {
  if dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'ok installed'; then
    return
  fi
  curl -fL --retry 3 -o "$tmp/$1.deb" "$2"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp/$1.deb"
}

# Both packages add their own apt repository, so `apt upgrade` updates them.
install_deb google-chrome-stable \
  'https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb'
install_deb code \
  'https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64'

# Bitwarden (no apt repository): the newest desktop release at least 7 days old, as
# minimum_release_age keeps the tools, and again whenever a newer one passes that age. This
# build (Electron) reads its client certificate from ~/.pki/nssdb, where setup:bitwarden puts it.
if bitwarden="$(curl -fsSL 'https://api.github.com/repos/bitwarden/clients/releases?per_page=60' | python3 -I -c '
import datetime, json, sys
cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=7)
for r in json.load(sys.stdin):
    if not r["tag_name"].startswith("desktop-v") or r["prerelease"] or r["draft"]:
        continue
    if datetime.datetime.fromisoformat(r["published_at"].replace("Z", "+00:00")) > cutoff:
        continue
    for a in r["assets"]:
        if a["name"].endswith("-amd64.deb"):
            print(r["tag_name"].removeprefix("desktop-v"), a["browser_download_url"])
            sys.exit()
')" && [[ -n $bitwarden ]]; then
  read -r version url <<<"$bitwarden"
  installed="$(dpkg-query -W -f='${Version}' bitwarden 2>/dev/null || true)"
  if [[ -z $installed ]] || dpkg --compare-versions "$installed" lt "$version"; then
    curl -fL --retry 3 -o "$tmp/bitwarden.deb" "$url"
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp/bitwarden.deb"
  fi
else
  echo "install-vendor-debs: could not look up the Bitwarden desktop release; skipped" >&2
fi

# QNAP Qfinder Pro (no apt repository)
if ! dpkg-query -W -f='${Status}' qfinderpro 2>/dev/null | grep -q 'ok installed'; then
  curl -fsSL -o "$tmp/release.xml" 'https://eu1.qnap.com/Liveupdate/SoftwareRelease.xml'
  url="$(grep -oEm1 'https?://[^"<]+/QNAPQfinderProUbuntux64[^"<]+\.deb' "$tmp/release.xml")"
  curl -fL --retry 3 -o "$tmp/qfinder.deb" "$url"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp/qfinder.deb"
fi
