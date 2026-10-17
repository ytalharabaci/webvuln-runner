#!/usr/bin/env bash
# Installs WebVuln-Runner from this checkout inside a fresh distribution container,
# checks the result and uninstalls it again.
# Usage: tests/installer-smoke.sh <image>      e.g. debian:12, fedora:42, archlinux:latest
# The container has no Docker daemon or systemd, so the installer's warnings about them are expected.
set -uo pipefail

image="${1:?usage: tests/installer-smoke.sh <image>}"
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker run --rm -v "$repo:/src:ro" "$image" sh -c '
  set -e
  # Minimal images may lack bash; the installer needs it.
  command -v bash >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq bash >/dev/null; }
  cp -r /src /tmp/wvr
  exec bash -c "
    set -uo pipefail
    fail() { echo \"FAIL: \$*\"; exit 1; }
    cd /tmp/wvr
    WVR_SOURCE_DIR=/tmp/wvr bash installers/install.sh > /tmp/install.log 2>&1 || { tail -30 /tmp/install.log; fail \"installer exited non-zero\"; }
    grep -E \"^(==>|warning|error)\" /tmp/install.log
    for c in docker jq whiptail curl webvuln-runner WebVuln-Runner; do
      command -v \$c >/dev/null || fail \"\$c missing after install\"
    done
    webvuln-runner version
    webvuln-runner validate || fail \"installed catalog does not validate\"
    [ \"\$(webvuln-runner catalog | wc -l)\" -gt 2 ] || fail \"catalog is empty\"
    bash /usr/local/lib/webvuln-runner/uninstall.sh --keep-labs
    [ ! -e /usr/local/bin/webvuln-runner ] || fail \"command left behind after uninstall\"
    [ ! -e /usr/local/lib/webvuln-runner ] || fail \"files left behind after uninstall\"
    echo \"installer smoke test passed on '"$image"'\"
  "
'
