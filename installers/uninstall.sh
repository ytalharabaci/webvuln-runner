#!/usr/bin/env bash
# Removes WebVuln-Runner from $PREFIX (default /usr/local).
# Labs created by WebVuln-Runner are only removed when you confirm (or pass --remove-labs).
# Containers, images and volumes that WebVuln-Runner did not create are never touched.
#
# Usage: uninstall.sh [--remove-labs | --keep-labs]
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
DEST="$PREFIX/lib/webvuln-runner"
mode="${1:-ask}"

[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "error: please run as root" >&2; exit 1; }

if [[ -x "$DEST/webvuln-runner" ]] && command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  mapfile -t labs < <("$DEST/webvuln-runner" list 2>/dev/null | awk 'NR > 1 { print $1 }')
  if (( ${#labs[@]} )); then
    echo "Labs created by WebVuln-Runner:"
    printf '  %s\n' "${labs[@]}"
    if [[ "$mode" == "ask" ]]; then
      answer=""
      if [[ -r /dev/tty ]]; then
        read -r -p "Remove these labs and their data volumes too? [y/N] " answer </dev/tty || true
      fi
      if [[ "$answer" =~ ^[Yy]$ ]]; then mode="--remove-labs"; else mode="--keep-labs"; fi
    fi
    if [[ "$mode" == "--remove-labs" ]]; then
      for lab in "${labs[@]}"; do
        "$DEST/webvuln-runner" rm "$lab" --volumes || echo "warning: could not remove $lab" >&2
      done
    else
      echo "Keeping the labs. Remove them later with 'docker rm -f <name>'"
      echo "(multi-container labs: 'docker compose -p <name> down')."
    fi
  fi
fi

for link in "$PREFIX/bin/webvuln-runner" "$PREFIX/bin/WebVuln-Runner"; do
  if [[ -L "$link" && "$(readlink "$link")" == "$DEST/"* ]]; then
    rm -f "$link"
  fi
done
rm -rf "$DEST"

echo "WebVuln-Runner removed. Downloaded lab images are kept; free the space with 'docker image prune -a' if you like."
