#!/bin/bash
# Build raw-gadget-dkms in a throwaway Debian trixie container, so the host
# needs nothing but docker. The package is Architecture: all, so the
# container's CPU architecture does not matter.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:?usage: build-in-docker.sh OUTPUT_DIR}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

docker run --rm \
	-v "$ROOT:/src:ro" \
	-v "$OUT:/out" \
	-e HOST_OWNER="$(id -u):$(id -g)" \
	debian:trixie bash /src/raw-gadget-dkms/build.sh /out
