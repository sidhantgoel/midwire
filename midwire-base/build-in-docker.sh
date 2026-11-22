#!/bin/bash
# Build midwire-base in a throwaway Debian trixie container, so the host
# needs nothing but docker. The package is Architecture: all, so the
# container's CPU architecture does not matter.
#
# MIDWIRE_ARCHIVE_KEY=/path/to/public-key.asc builds with that key instead
# of keys/midwire-archive-keyring.asc (for tests).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:?usage: build-in-docker.sh OUTPUT_DIR}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

key_args=()
if [ -n "${MIDWIRE_ARCHIVE_KEY:-}" ]; then
	key=$(cd "$(dirname "$MIDWIRE_ARCHIVE_KEY")" && pwd)/$(basename "$MIDWIRE_ARCHIVE_KEY")
	key_args=(-v "$key:/archive-key.asc:ro" -e MIDWIRE_ARCHIVE_KEY=/archive-key.asc)
fi

docker run --rm \
	-v "$ROOT:/src:ro" \
	-v "$OUT:/out" \
	-e HOST_OWNER="$(id -u):$(id -g)" \
	${key_args[@]+"${key_args[@]}"} \
	debian:trixie bash /src/midwire-base/build.sh /out
