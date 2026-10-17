#!/usr/bin/env bash
# Kept so that installation links from WebVuln-Runner 1.x keep working.
# Downloads and runs the universal installer of the same release with the distro family forced.
set -euo pipefail
WVR_RELEASE="${WVR_RELEASE:-v2.0.0}"
url="https://raw.githubusercontent.com/yusufarbc/webvuln-runner/$WVR_RELEASE/installers/install.sh"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
{ curl -fsSL -o "$tmp" "$url" 2>/dev/null || wget -qO "$tmp" "$url"; } || { echo "error: download failed: $url" >&2; exit 1; }
WVR_DISTRO=arch WVR_RELEASE="$WVR_RELEASE" bash "$tmp" "$@"
