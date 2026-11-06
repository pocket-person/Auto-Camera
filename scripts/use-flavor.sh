#!/bin/bash

set -euo pipefail

scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repoRoot="$(dirname "$scriptDir")"

if [ "$#" -gt 1 ]; then
  echo "usage: ./scripts/use-flavor.sh [retail|anniversary|classic-era|mop-classic|forever]" >&2
  exit 1
fi

flavor="${1:-retail}"
normalizedFlavor=$(printf '%s' "$flavor" | tr '[:upper:]' '[:lower:]')
case "$normalizedFlavor" in
  retail)
    tocFile="Auto-Camera-Retail.toc"
    ;;
  anniversary)
    tocFile="Auto-Camera-Anniversary.toc"
    ;;
  classic-era)
    tocFile="Auto-Camera-Classic-Era.toc"
    ;;
  mop-classic)
    tocFile="Auto-Camera-MoP-Classic.toc"
    ;;
  forever|wow-forever)
    tocFile="Auto-Camera-Forever.toc"
    ;;
  *)
    echo "unknown flavor '$flavor'" >&2
    echo "usage: ./scripts/use-flavor.sh [retail|anniversary|classic-era|mop-classic|forever]" >&2
    exit 1
    ;;
esac

sourceToc="$repoRoot/$tocFile"
if [ ! -f "$sourceToc" ]; then
  echo "missing flavor TOC file: $tocFile" >&2
  exit 1
fi

cp "$sourceToc" "$repoRoot/Auto-Camera.toc"
