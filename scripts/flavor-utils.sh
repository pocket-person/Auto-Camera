#!/bin/bash

set -euo pipefail

toc_suffix_from_filename() {
  local tocFile="$1"
  if [ "$tocFile" = "Auto-Camera.toc" ]; then
    echo ""
    return 0
  fi

  if [[ "$tocFile" =~ ^Auto-Camera-(.+)\.toc$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]'
    return 0
  fi

  return 1
}

toc_interface_version() {
  local tocFile="$1"
  local interfaceVersion
  interfaceVersion=$(grep "^## Interface:" "$tocFile" | head -n1 | grep -oE '[0-9]+' | head -n1)
  if [ -z "$interfaceVersion" ]; then
    return 1
  fi
  echo "$interfaceVersion"
}

toc_version() {
  local tocFile="$1"
  local version
  version=$(grep "^## Version:" "$tocFile" | head -n1 | sed -E 's/^## Version:[[:space:]]*//' | tr -d '\r')
  if [ -z "$version" ]; then
    return 1
  fi
  echo "$version"
}

release_flavor_from_interface() {
  local interfaceVersion="$1"
  local major=$((10#${interfaceVersion} / 10000))
  case "$major" in
    12)
      echo "mainline"
      ;;
    1)
      echo "classic"
      ;;
    2)
      echo "bcc"
      ;;
    3)
      echo "wrath"
      ;;
    4)
      echo "cata"
      ;;
    5)
      echo "mists"
      ;;
    6)
      echo "wod"
      ;;
    7)
      echo "legion"
      ;;
    8)
      echo "bfa"
      ;;
    9)
      echo "shadowlands"
      ;;
    *)
      return 1
      ;;
  esac
}

is_live_product_target() {
  local product="$1"
  if [[ "$product" == *ptr* ]] || [[ "$product" == *beta* ]]; then
    return 1
  fi
  case "$product" in
    wow|wow_classic_era|wow_anniversary|wow_classic)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

extract_live_interfaces() {
  local buildsJson="$1"
  local compact
  compact=$(printf '%s' "$buildsJson" | tr -d '\r\n ')

  printf '%s' "$compact" | grep -oE '"[^"]+":\{"product":"[^"]+","version":"[^"]+"' | while IFS= read -r pair; do
    local product version
    product=$(printf '%s' "$pair" | sed -E 's/^"([^"]+)":\{.*/\1/')
    version=$(printf '%s' "$pair" | sed -E 's/.*"version":"([^"]+)".*/\1/')

    if ! is_live_product_target "$product"; then
      continue
    fi

    interface_from_semver "$version"
  done
}

# Returns the latest version string for a product from wago.tools builds JSON.
latest_version_for_product() {
  local buildsJson="$1"
  local product="$2"
  local version

  version=$(printf '%s' "$buildsJson" | tr -d '\r\n' | sed -E "s/.*\"${product}\":\{[^}]*\"version\":\"([^\"]+)\".*/\1/")
  if [ -z "$version" ] || [ "$version" = "$buildsJson" ]; then
    return 1
  fi

  echo "$version"
}

# Converts a semantic game version (e.g. 12.0.7) to a WoW interface integer (120007).
interface_from_semver() {
  local version="$1"
  IFS='.' read -r major minor patch _ <<< "$version"

  if [[ ! "$major" =~ ^[0-9]+$ ]] || [[ ! "$minor" =~ ^[0-9]+$ ]] || [[ ! "$patch" =~ ^[0-9]+$ ]]; then
    echo "invalid semver: $version" >&2
    return 1
  fi

  printf '%d\n' $((10#$major * 10000 + 10#$minor * 100 + 10#$patch))
}
