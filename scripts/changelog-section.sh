#!/usr/bin/env bash
# Prints the CHANGELOG.md section of one version (used as GitHub release notes).
# Usage: scripts/changelog-section.sh 2.2.0     -> exit 1 if the section is missing or empty
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

version="${1#v}"
section="$(awk -v v="$version" '
  /^## \[/ { if (found) exit; if (index($0, "## [" v "]") == 1) { found = 1; next } }
  /^\[[^]]+\]: / { if (found) exit }
  found
' CHANGELOG.md | sed -e '/./,$!d')"

if [[ -z "${section//[[:space:]]/}" ]]; then
  echo "CHANGELOG.md has no section for $version" >&2
  exit 1
fi
printf '%s\n' "$section"
