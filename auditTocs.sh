#!/bin/bash

# If invoked with sh, re-exec under bash so bash-specific syntax works.
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

source "$(dirname "$0")/scripts/flavor-utils.sh"

onlineCheck=1
if [ "${1:-}" = "--offline" ]; then
  onlineCheck=0
fi

shopt -s nullglob
tocFiles=(Auto-Camera*.toc)
shopt -u nullglob

if [ ${#tocFiles[@]} -eq 0 ]; then
  echo "ERROR: no TOC files found (expected Auto-Camera*.toc)"
  exit 1
fi

if [ ! -f "Auto-Camera.toc" ]; then
  echo "ERROR: missing base TOC file Auto-Camera.toc"
  exit 1
fi

baseVersion=$(toc_version Auto-Camera.toc || true)
if [ -z "$baseVersion" ]; then
  echo "ERROR: Auto-Camera.toc is missing a ## Version field"
  exit 1
fi

latestBuildsJson=""
declare -A liveInterfaceByMajor
if [ "$onlineCheck" -eq 1 ]; then
  if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: online check requires curl (use --offline to skip)"
    exit 1
  fi

  latestBuildsJson=$(curl -fsSL https://wago.tools/api/builds/latest)

  tmpInterfacesFile=$(mktemp)
  extract_live_interfaces "$latestBuildsJson" > "$tmpInterfacesFile"
  while IFS= read -r iface; do
    [ -z "$iface" ] && continue
    major=$((10#${iface} / 10000))
    liveInterfaceByMajor["$major"]="$iface"
  done < "$tmpInterfacesFile"
  rm -f "$tmpInterfacesFile"
fi

declare -A tocInterfaceByFile
declare -A tocInterfaceByMajor

for tocFile in "${tocFiles[@]}"; do
  suffix=$(toc_suffix_from_filename "$tocFile") || {
    echo "ERROR: unsupported TOC filename format: $tocFile"
    exit 1
  }
  if [[ "$suffix" == *ptr* ]] || [[ "$suffix" == *beta* ]]; then
    echo "ERROR: PTR/Beta TOC files should not be part of release set: $tocFile"
    exit 1
  fi

  interfaceVersion=$(toc_interface_version "$tocFile" || true)
  if [ -z "$interfaceVersion" ]; then
    echo "ERROR: $tocFile has an invalid or missing ## Interface field"
    exit 1
  fi
  tocInterfaceByFile["$tocFile"]="$interfaceVersion"

  major=$((10#${interfaceVersion} / 10000))
  if [ -n "${tocInterfaceByMajor[$major]:-}" ]; then
    echo "ERROR: duplicate TOC coverage for interface major '$major' ($tocFile and ${tocInterfaceByMajor[$major]})"
    exit 1
  fi
  tocInterfaceByMajor["$major"]="$tocFile"

  tocVersion=$(toc_version "$tocFile" || true)
  if [ -z "$tocVersion" ]; then
    echo "ERROR: $tocFile is missing a ## Version field"
    exit 1
  fi

  if [ "$tocVersion" != "$baseVersion" ]; then
    echo "ERROR: version mismatch in $tocFile (found '$tocVersion', expected '$baseVersion')"
    exit 1
  fi
done

if [ "$onlineCheck" -eq 1 ]; then
  for major in "${!liveInterfaceByMajor[@]}"; do
    expectedIface="${liveInterfaceByMajor[$major]}"
    if [ -z "${tocInterfaceByMajor[$major]:-}" ]; then
      echo "ERROR: missing TOC for current live interface '$expectedIface' (major $major) from wago.tools"
      exit 1
    fi
  done

  for tocFile in "${tocFiles[@]}"; do
    iface="${tocInterfaceByFile[$tocFile]}"
    major=$((10#${iface} / 10000))
    expectedIface="${liveInterfaceByMajor[$major]:-}"

    if [ -z "$expectedIface" ]; then
      echo "ERROR: $tocFile uses interface '$iface' (major $major), but no live non-PTR product with this major was found from wago.tools"
      exit 1
    fi

    if [ "$iface" != "$expectedIface" ]; then
      echo "ERROR: $tocFile is not at current interface version (found '$iface', expected '$expectedIface' from wago.tools)"
      exit 1
    fi
  done
fi

echo "TOC audit passed."
echo "Base version: $baseVersion"
echo "Discovered TOCs: ${#tocFiles[@]}"
if [ "$onlineCheck" -eq 1 ]; then
  echo "Online interface check: enabled (wago.tools/api/builds/latest, non-PTR products only)"
else
  echo "Online interface check: disabled (--offline)"
fi
