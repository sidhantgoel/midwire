#!/bin/bash
# Build the signed apt repository that devices update from.
#
#   APT_SIGNING_KEY="$(cat private-key.asc)" scripts/make-apt-repo.sh DEBS_DIR OUT_DIR
#
# Writes OUT_DIR/apt/ with the .debs, Packages, Packages.gz, Release,
# Release.gpg and InRelease. The files in OUT_DIR/apt/ are then uploaded as
# the assets of the GitHub release tagged "apt" (see the workflow), where
# midwire-base's /etc/apt/sources.list.d/midwire.sources finds them:
#
#   URIs:   https://github.com/sidhantgoel/midwire/releases/download/
#   Suites: apt/
#
# That is a "flat" apt repository: apt asks for <URI>apt/InRelease, and
# every Filename in Packages is relative to the URI, so "apt/<file>.deb".
#
# APT_SIGNING_KEY is the ASCII-armored private key, without a passphrase.
# It is imported into a temporary keyring that is removed afterwards.
# The result is checked against the public key midwire-base ships
# (midwire-base/keys/midwire-archive-keyring.asc, or MIDWIRE_ARCHIVE_KEY),
# so a repository that devices would reject is never published.
#
# Needs apt-ftparchive (apt-utils), gpg and gpgv.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEBS=${1:?usage: make-apt-repo.sh DEBS_DIR OUT_DIR}
OUT=${2:?usage: make-apt-repo.sh DEBS_DIR OUT_DIR}
PUBLIC_KEY=${MIDWIRE_ARCHIVE_KEY:-$ROOT/midwire-base/keys/midwire-archive-keyring.asc}

if [ -z "${APT_SIGNING_KEY:-}" ]; then
	echo "make-apt-repo.sh: APT_SIGNING_KEY is empty." >&2
	echo "Set it to the ASCII-armored private key of the Midwire apt repository" >&2
	echo "(in GitHub Actions: the repository secret APT_SIGNING_KEY)." >&2
	exit 1
fi
if [ ! -s "$PUBLIC_KEY" ]; then
	echo "make-apt-repo.sh: the public key $PUBLIC_KEY is missing." >&2
	exit 1
fi
for tool in apt-ftparchive gpg gpgv dpkg-deb; do
	command -v "$tool" >/dev/null || { echo "make-apt-repo.sh: $tool is required" >&2; exit 1; }
done

shopt -s nullglob
debs=("$DEBS"/*.deb)
shopt -u nullglob
if [ ${#debs[@]} -eq 0 ]; then
	echo "make-apt-repo.sh: no .deb files in $DEBS" >&2
	exit 1
fi

rm -rf "$OUT/apt"
mkdir -p "$OUT/apt"
OUT=$(cd "$OUT" && pwd)

# GitHub release asset names keep only letters, digits, '.', '_' and '-'.
# apt does not care what a file is called, only what Packages says.
for deb in "${debs[@]}"; do
	name=$(basename "$deb" | tr -c 'A-Za-z0-9._\n-' '.')
	if [ -e "$OUT/apt/$name" ]; then
		echo "make-apt-repo.sh: two packages map to the file name $name" >&2
		exit 1
	fi
	cp "$deb" "$OUT/apt/$name"
done

cd "$OUT"
apt-ftparchive packages apt > apt/Packages
gzip -9 -n -k apt/Packages

# Written outside apt/ first, so the Release file does not list itself.
# Origin, Label, Suite and Codename must never change: apt refuses a
# repository whose values differ from the ones it saw before. Suite and
# Codename are "apt" because the source says "Suites: apt/"; without them
# apt warns about a "conflicting distribution" on every refresh.
apt-ftparchive \
	-o APT::FTPArchive::Release::Origin=Midwire \
	-o APT::FTPArchive::Release::Label=Midwire \
	-o APT::FTPArchive::Release::Suite=apt \
	-o APT::FTPArchive::Release::Codename=apt \
	-o APT::FTPArchive::Release::Description="Midwire packages" \
	release apt > Release.new
mv Release.new apt/Release

GNUPGHOME=$(mktemp -d)
export GNUPGHOME
cleanup() {
	gpgconf --kill all >/dev/null 2>&1 || true
	rm -rf "$GNUPGHOME"
}
trap cleanup EXIT
chmod 700 "$GNUPGHOME"

printf '%s\n' "$APT_SIGNING_KEY" | gpg --batch --quiet --import
fingerprint=$(gpg --batch --list-secret-keys --with-colons | awk -F: '$1 == "fpr" { print $10; exit }')
if [ -z "$fingerprint" ]; then
	echo "make-apt-repo.sh: APT_SIGNING_KEY holds no private key." >&2
	exit 1
fi

sign=(gpg --batch --yes --pinentry-mode loopback --passphrase '' --digest-algo SHA512 --local-user "$fingerprint")
"${sign[@]}" --clearsign --output apt/InRelease apt/Release
"${sign[@]}" --armor --detach-sign --output apt/Release.gpg apt/Release

# Would a device accept this? Check with the key that midwire-base ships.
gpg --batch --yes --no-default-keyring --keyring "$GNUPGHOME/device.gpg" --quiet --import "$PUBLIC_KEY"
if ! gpgv --quiet --keyring "$GNUPGHOME/device.gpg" apt/InRelease >/dev/null 2>"$GNUPGHOME/verify.log"; then
	echo "make-apt-repo.sh: the repository was signed with a key that is not $PUBLIC_KEY." >&2
	echo "Devices would reject it. APT_SIGNING_KEY and the committed public key must be a pair." >&2
	cat "$GNUPGHOME/verify.log" >&2
	exit 1
fi

echo "apt repository in $OUT/apt, signed by $fingerprint:"
ls -l apt
