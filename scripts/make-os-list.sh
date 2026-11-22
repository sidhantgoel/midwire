#!/bin/bash
# Write deploy/os_list_midwire.json, a Raspberry Pi Imager repository file
# for one release. It fills imager/os_list.template.json with the sizes and
# checksums pi-gen recorded in deploy/midwire-<version>-arm64.os.json.
#
#   scripts/make-os-list.sh VERSION [BASE_URL]
#
# BASE_URL is where the release files are downloaded from. The default is
# this repository's GitHub release for v<VERSION>.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${1:?usage: make-os-list.sh VERSION [BASE_URL]}
REPO=${GITHUB_REPOSITORY:-sidhantgoel/midwire}
BASE_URL=${2:-https://github.com/$REPO/releases/download/v$VERSION}

python3 - "$ROOT" "$VERSION" "$BASE_URL" "$REPO" << 'EOF'
import json
import sys
from pathlib import Path

root, version, base_url, repo = Path(sys.argv[1]), sys.argv[2], sys.argv[3].rstrip("/"), sys.argv[4]
built = json.loads((root / "deploy" / f"midwire-{version}-arm64.os.json").read_text())
doc = json.loads((root / "imager" / "os_list.template.json").read_text())

entry = doc["os_list"][0]
entry["name"] = f"Midwire {version}"
entry["url"] = f"{base_url}/{built['image_filename']}"
for key in ("extract_size", "extract_sha256", "image_download_size",
            "image_download_sha256", "release_date"):
    entry[key] = built[key]
# Imager shows an icon next to the name. Add one as imager/icon.png (40x40).
if (root / "imager" / "icon.png").exists():
    entry["icon"] = f"https://raw.githubusercontent.com/{repo}/main/imager/icon.png"

out = root / "deploy" / "os_list_midwire.json"
out.write_text(json.dumps(doc, indent=2) + "\n")
print(f"wrote {out}")
EOF
