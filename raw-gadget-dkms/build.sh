#!/bin/bash
# Build raw-gadget-dkms_<version>_all.deb into the given directory.
# Runs on Debian trixie as root (see build-in-docker.sh): installs the
# build tools, fetches raw_gadget.c/.h at the pinned commit, and packages.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=../versions.env
. "$HERE/../versions.env"

OUT=${1:?usage: build.sh OUTPUT_DIR}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
	build-essential ca-certificates debhelper dh-dkms git >/dev/null

# The packaging tree may be mounted read-only, and must not have CRLF or
# missing exec bits from a Windows checkout: work on a copy.
cp -r "$HERE" "$WORK/raw-gadget-dkms"
cd "$WORK/raw-gadget-dkms"
chmod +x debian/rules

changelog_version=$(dpkg-parsechangelog -S Version)
if [ "$changelog_version" != "$RAW_GADGET_DKMS_VERSION" ]; then
	echo "debian/changelog is $changelog_version but versions.env says $RAW_GADGET_DKMS_VERSION" >&2
	exit 1
fi

# A commit hash is verified by git itself, so this pins the exact source.
git init -q "$WORK/raw-gadget"
git -C "$WORK/raw-gadget" remote add origin "$RAW_GADGET_REPO"
git -C "$WORK/raw-gadget" fetch -q --depth 1 origin "$RAW_GADGET_COMMIT"
git -C "$WORK/raw-gadget" checkout -q --detach FETCH_HEAD
cp "$WORK/raw-gadget/raw_gadget/raw_gadget.c" "$WORK/raw-gadget/raw_gadget/raw_gadget.h" src/

dpkg-buildpackage -b -us -uc
mkdir -p "$OUT"
cp ../raw-gadget-dkms_*_all.deb "$OUT/"
if [ -n "${HOST_OWNER:-}" ]; then
	chown "$HOST_OWNER" "$OUT"/raw-gadget-dkms_*_all.deb
fi
dpkg-deb --contents "$OUT"/raw-gadget-dkms_*_all.deb
