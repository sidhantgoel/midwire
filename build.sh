#!/bin/bash
# Build the Midwire image: clone pi-gen at the pinned commit, add our config
# and stage, collect the .debs, and run pi-gen's Docker build.
#
#   ./build.sh                 build deploy/midwire-<version>-arm64.img.xz
#   CONTINUE=1 ./build.sh      resume a failed build in the kept container
#   MIDWIRE_VERSION=1.2.3 ./build.sh
#   ASSEMBLE_ONLY=1 ./build.sh prepare build/pi-gen and stop before building
#
# Needs Linux (or WSL2) with docker and git. See README.md.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=versions.env
. "$ROOT/versions.env"

BUILD=${MIDWIRE_BUILD_DIR:-$ROOT/build}
PIGEN=$BUILD/pi-gen
STAGE=$PIGEN/stage-midwire

version=${MIDWIRE_VERSION:-}
if [ -z "$version" ]; then
	version=$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || true)
	version=${version#v}
	version=${version:-dev}
fi

for tool in docker git; do
	command -v "$tool" >/dev/null || { echo "build.sh: $tool is required" >&2; exit 1; }
done
case $BUILD in
/mnt/[a-z]/*)
	echo "build.sh: $BUILD is on a Windows drive. Clone this repo inside the" >&2
	echo "WSL filesystem (for example ~/midwire); pi-gen needs Linux file modes." >&2
	exit 1
	;;
esac

echo "== Midwire $version"

echo "== pi-gen at $PI_GEN_REF"
if [ ! -d "$PIGEN/.git" ]; then
	mkdir -p "$PIGEN"
	git -C "$PIGEN" init -q
	git -C "$PIGEN" remote add origin "$PI_GEN_REPO"
fi
if [ "$(git -C "$PIGEN" rev-parse -q --verify HEAD 2>/dev/null || true)" != "$PI_GEN_REF" ]; then
	git -C "$PIGEN" -c core.autocrlf=false fetch -q --depth 1 origin "$PI_GEN_REF"
	git -C "$PIGEN" -c core.autocrlf=false checkout -q --detach FETCH_HEAD
fi

echo "== packages"
"$ROOT/scripts/fetch-debs.sh" "$BUILD/debs"

echo "== stage"
rm -rf "$STAGE"
cp -r "$ROOT/stage-midwire" "$STAGE"
mkdir -p "$STAGE/files/debs"
cp "$BUILD"/debs/*.deb "$STAGE/files/debs/"
# pi-gen silently skips scripts that are not executable.
find "$STAGE" -name '*.sh' -exec chmod +x {} +
# Only export our image, not the plain Lite one from stage2.
touch "$PIGEN/stage2/SKIP_IMAGES"

{
	cat "$ROOT/config"
	echo
	echo "# Added by build.sh"
	echo "IMG_FILENAME=midwire-$version-arm64"
	echo "ARCHIVE_FILENAME=midwire-$version-arm64"
} > "$PIGEN/config"

if [ "${ASSEMBLE_ONLY:-0}" = "1" ]; then
	echo "== assembled $PIGEN, not building (ASSEMBLE_ONLY=1)"
	exit 0
fi

echo "== pi-gen build"
if [ "${CONTINUE:-0}" != "1" ] && [ -n "$(docker ps -aq --filter name='^pigen_work$')" ]; then
	docker rm -v pigen_work >/dev/null
fi
(cd "$PIGEN" && ./build-docker.sh)

mkdir -p "$ROOT/deploy"
cp "$PIGEN"/deploy/midwire-"$version"-arm64.* "$ROOT/deploy/"
(cd "$ROOT/deploy" && sha256sum "midwire-$version-arm64.img.xz" > "midwire-$version-arm64.img.xz.sha256")
echo "== done"
ls -lh "$ROOT/deploy"
