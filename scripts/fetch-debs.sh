#!/bin/bash
# Collect the four .debs the image installs, and the apt repository
# publishes, into the given directory.
#
# For each package, a matching file in debs/ at the repo root wins. That is
# how to build with unreleased packages. Otherwise usb-proxy and
# midwire-web-ui are downloaded from their pinned GitHub releases, and
# raw-gadget-dkms and midwire-base are built from this repo.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source-path=SCRIPTDIR source=../versions.env
. "$ROOT/versions.env"

OUT=${1:?usage: fetch-debs.sh OUTPUT_DIR}
mkdir -p "$OUT"
rm -f "$OUT"/*.deb

# local_override NAME: copy debs/NAME_*.deb if there is exactly one.
local_override() {
	local name=$1 matches=()
	shopt -s nullglob
	matches=("$ROOT"/debs/"$name"_*.deb)
	shopt -u nullglob
	case ${#matches[@]} in
	0) return 1 ;;
	1)
		echo "$name: using local ${matches[0]##*/}"
		cp "${matches[0]}" "$OUT/"
		;;
	*)
		echo "fetch-debs.sh: more than one $name .deb in debs/" >&2
		exit 1
		;;
	esac
}

# from_release NAME REPO VERSION ARCH
from_release() {
	local name=$1 repo=$2 version=$3 arch=$4
	local file="${name}_${version}_${arch}.deb"
	local url="https://github.com/$repo/releases/download/v$version/$file"
	echo "$name: downloading $url"
	if ! curl -fsSL --retry 3 -o "$OUT/$file" "$url"; then
		rm -f "$OUT/$file"
		echo "fetch-debs.sh: could not download $file." >&2
		echo "Publish release v$version of $repo, or put the .deb in debs/." >&2
		exit 1
	fi
}

local_override usb-proxy ||
	from_release usb-proxy "$USB_PROXY_REPO" "$USB_PROXY_VERSION" arm64

local_override midwire-web-ui ||
	from_release midwire-web-ui "$MIDWIRE_WEB_UI_REPO" "$MIDWIRE_WEB_UI_VERSION" all

if ! local_override raw-gadget-dkms; then
	echo "raw-gadget-dkms: building from raw-gadget $RAW_GADGET_COMMIT"
	"$ROOT/raw-gadget-dkms/build-in-docker.sh" "$OUT"
fi

if ! local_override midwire-base; then
	echo "midwire-base: building $MIDWIRE_BASE_VERSION"
	"$ROOT/midwire-base/build-in-docker.sh" "$OUT"
fi

ls -l "$OUT"
