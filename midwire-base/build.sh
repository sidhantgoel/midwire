#!/bin/bash
# Build midwire-base_<version>_all.deb into the given directory.
# Runs on Debian trixie as root (see build-in-docker.sh).
#
# The package carries the public key of the apt repository, from
# keys/midwire-archive-keyring.asc. For a test build with another key, set
# MIDWIRE_ARCHIVE_KEY to the path of an ASCII-armored public key.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=../versions.env
. "$HERE/../versions.env"

OUT=${1:?usage: build.sh OUTPUT_DIR}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends build-essential debhelper gnupg >/dev/null

# The packaging tree may be mounted read-only, and must not have CRLF or
# missing exec bits from a Windows checkout: work on a copy.
cp -r "$HERE" "$WORK/midwire-base"
cd "$WORK/midwire-base"
chmod +x debian/rules update

if [ -n "${MIDWIRE_ARCHIVE_KEY:-}" ]; then
	echo "midwire-base: using the key in $MIDWIRE_ARCHIVE_KEY instead of keys/"
	cp "$MIDWIRE_ARCHIVE_KEY" keys/midwire-archive-keyring.asc
fi

changelog_version=$(dpkg-parsechangelog -S Version)
if [ "$changelog_version" != "$MIDWIRE_BASE_VERSION" ]; then
	echo "debian/changelog is $changelog_version but versions.env says $MIDWIRE_BASE_VERSION" >&2
	exit 1
fi

dpkg-buildpackage -b -us -uc
mkdir -p "$OUT"
cp ../midwire-base_*_all.deb "$OUT/"
if [ -n "${HOST_OWNER:-}" ]; then
	chown "$HOST_OWNER" "$OUT"/midwire-base_*_all.deb
fi
dpkg-deb --contents "$OUT"/midwire-base_*_all.deb
