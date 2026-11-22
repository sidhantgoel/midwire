#!/bin/bash
# One-time setup: create the key the Midwire apt repository is signed with.
#
#   scripts/make-signing-key.sh PRIVATE_KEY_DIR
#
# Writes the public key to midwire-base/keys/midwire-archive-keyring.asc
# (commit it: it is built into the midwire-base package) and the private key
# to PRIVATE_KEY_DIR/midwire-apt-signing-PRIVATE-key.asc.
#
# The private key has no passphrase, because GitHub Actions has to use it
# unattended. Paste its contents into the repository secret APT_SIGNING_KEY,
# keep one copy somewhere safe and offline, and delete any other copy.
# Whoever has it can push software to every Midwire device.
#
# PRIVATE_KEY_DIR must be outside this repository, so the key cannot be
# committed by accident. The script refuses to overwrite an existing key:
# devices trust the one already published, and a new key would lock them out
# of updates until they are given it by hand.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PUBLIC=$ROOT/midwire-base/keys/midwire-archive-keyring.asc
DIR=${1:?usage: make-signing-key.sh PRIVATE_KEY_DIR (a folder outside this repository)}

command -v gpg >/dev/null || { echo "make-signing-key.sh: gpg is required" >&2; exit 1; }

mkdir -p "$DIR"
DIR=$(cd "$DIR" && pwd)
PRIVATE=$DIR/midwire-apt-signing-PRIVATE-key.asc

case $DIR/ in
"$ROOT"/*)
	echo "make-signing-key.sh: $DIR is inside the repository. Choose a folder outside it." >&2
	exit 1
	;;
esac
if [ -e "$PUBLIC" ]; then
	echo "make-signing-key.sh: $PUBLIC already exists. Not replacing the key devices trust." >&2
	exit 1
fi
if [ -e "$PRIVATE" ]; then
	echo "make-signing-key.sh: $PRIVATE already exists. Not overwriting it." >&2
	exit 1
fi

GNUPGHOME=$(mktemp -d)
export GNUPGHOME
cleanup() {
	gpgconf --kill all >/dev/null 2>&1 || true
	rm -rf "$GNUPGHOME"
}
trap cleanup EXIT
chmod 700 "$GNUPGHOME"

# Ed25519, signing only, no expiry: a device that has been switched off for
# years must still be able to verify an update.
gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
	--quick-generate-key "Midwire apt repository" ed25519 sign never
fingerprint=$(gpg --batch --list-secret-keys --with-colons | awk -F: '$1 == "fpr" { print $10; exit }')

umask 077
gpg --batch --armor --pinentry-mode loopback --passphrase '' --export-secret-keys "$fingerprint" > "$PRIVATE"
umask 022
gpg --batch --armor --export "$fingerprint" > "$PUBLIC"

grep -q 'BEGIN PGP PRIVATE KEY BLOCK' "$PRIVATE"
grep -q 'BEGIN PGP PUBLIC KEY BLOCK' "$PUBLIC"
! grep -q 'PRIVATE KEY' "$PUBLIC"

echo "Created the Midwire apt repository key."
echo "  Fingerprint: $fingerprint"
echo "  Public key:  $PUBLIC   (commit this)"
echo "  Private key: $PRIVATE  (secret APT_SIGNING_KEY; never commit)"
