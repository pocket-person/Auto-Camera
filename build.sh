#!/bin/bash

# If invoked with sh, re-exec under bash so bash-specific syntax works.
if [ -z "${BASH_VERSION:-}" ]; then
	exec bash "$0" "$@"
fi

set -euo pipefail

source "$(dirname "$0")/scripts/flavor-utils.sh"

# scan for versions
addonVersion="${1:-}"
if [ -z "$addonVersion" ]; then
	echo "usage: ./build.sh <addon-version>"
	exit 1
fi

rm -rf Auto-Camera
rm -f Auto-Camera*.zip

mkdir Auto-Camera
cp *.lua Auto-Camera
cp -r modules Auto-Camera
cp -r libs Auto-Camera
cp *.xml Auto-Camera

releaseEntries=()
shopt -s nullglob
tocFiles=(Auto-Camera*.toc)
shopt -u nullglob
declare -A seenFlavors

if [ ${#tocFiles[@]} -eq 0 ]; then
	echo "no TOC files found (expected Auto-Camera*.toc)"
	exit 1
fi

for tocFile in "${tocFiles[@]}"; do
	zipSuffix=$(toc_suffix_from_filename "$tocFile") || {
		echo "unsupported TOC filename format: $tocFile"
		exit 1
	}
	if [[ "$zipSuffix" == *ptr* ]] || [[ "$zipSuffix" == *beta* ]]; then
		echo "unsupported TOC file for release build (PTR/Beta): $tocFile"
		exit 1
	fi

	interfaceVersion=$(toc_interface_version "$tocFile" || true)
	if [ -z "$interfaceVersion" ]; then
		echo "missing interface version in TOC file: $tocFile"
		exit 1
	fi

	flavor=$(release_flavor_from_interface "$interfaceVersion") || {
		echo "unsupported interface '$interfaceVersion' in TOC file: $tocFile"
		exit 1
	}

	if [ -n "${seenFlavors[$flavor]:-}" ]; then
		echo "duplicate flavor '$flavor' detected from TOC file: $tocFile"
		exit 1
	fi
	seenFlavors["$flavor"]=1

	cp "$tocFile" Auto-Camera/Auto-Camera.toc

	artifactName="Auto-Camera-${addonVersion}.zip"
	if [ -n "$zipSuffix" ]; then
		artifactName="Auto-Camera-${addonVersion}-${zipSuffix}.zip"
	fi

	zip -rq "$artifactName" Auto-Camera
	releaseEntries+=("{\"name\":\"Auto-Camera\",\"version\":\"${addonVersion}\",\"filename\":\"${artifactName}\",\"nolib\": false,\"metadata\":[{\"flavor\":\"${flavor}\",\"interface\":${interfaceVersion}}]}")
done

# create release.json
printf '{"releases":[%s]}\n' "$(IFS=,; echo "${releaseEntries[*]}")" > release.json

# clean up
rm -r Auto-Camera
