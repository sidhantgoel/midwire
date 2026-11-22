#!/bin/bash
# Upload an apt repository built by make-apt-repo.sh to the GitHub release
# tagged "apt", whose assets are what devices download:
#
#   scripts/publish-apt-repo.sh OUT_DIR/apt
#
# Needs the gh command, logged in (in GitHub Actions: GH_TOKEN) and run
# inside a checkout of the repository, or with GH_REPO set.
#
# The release is created on first use with --latest=false. It must never be
# the "latest" release: Raspberry Pi Imager is pointed at
# releases/latest/download/os_list_midwire.json, which lives on the image
# releases (v1.2.3).
#
# Replacing the files of a release is not atomic. A device that checks for
# updates during the few seconds of an upload may see a mismatch, reports
# that the repository is being published, and is fine on its next check.
set -euo pipefail

DIR=${1:?usage: publish-apt-repo.sh REPO_DIR}
TAG=apt

for file in InRelease Release Release.gpg Packages Packages.gz; do
	if [ ! -s "$DIR/$file" ]; then
		echo "publish-apt-repo.sh: $DIR/$file is missing. Run make-apt-repo.sh first." >&2
		exit 1
	fi
done
shopt -s nullglob
debs=("$DIR"/*.deb)
shopt -u nullglob
if [ ${#debs[@]} -eq 0 ]; then
	echo "publish-apt-repo.sh: no .deb files in $DIR" >&2
	exit 1
fi

if ! gh release view "$TAG" >/dev/null 2>&1; then
	echo "Creating the $TAG release"
	gh release create "$TAG" --latest=false \
		--title "Midwire apt repository" \
		--notes "The package repository Midwire devices update from. These files are written by the \"Publish\" workflow; do not edit them by hand. To install Midwire, use the newest image release instead."
fi

# Packages first: the old index does not mention them, so nothing breaks.
# Then the index, in one go. Old packages stay until the new index is up.
gh release upload "$TAG" "${debs[@]}" --clobber
gh release upload "$TAG" "$DIR/Packages" "$DIR/Packages.gz" "$DIR/Release" "$DIR/Release.gpg" \
	"$DIR/InRelease" --clobber

# Remove packages the new index no longer lists.
while IFS= read -r asset; do
	case $asset in
	*.deb)
		if [ ! -e "$DIR/$asset" ]; then
			echo "Removing old package $asset"
			gh release delete-asset "$TAG" "$asset" --yes
		fi
		;;
	esac
done < <(gh release view "$TAG" --json assets --jq '.assets[].name')

echo "Published:"
gh release view "$TAG" --json assets --jq '.assets[] | "  \(.name)  \(.size) bytes"'
