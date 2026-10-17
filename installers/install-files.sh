#!/usr/bin/env bash
# Copies WebVuln-Runner into $PREFIX/lib/webvuln-runner and links the command into $PREFIX/bin.
# Works both from a release tarball (files next to this script) and from a git checkout
# (files in ../src). Run as root.
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
DEST="$PREFIX/lib/webvuln-runner"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$here/webvuln-runner" && -d "$here/lib" ]]; then
  payload="$here"
elif [[ -f "$here/../src/webvuln-runner" ]]; then
  payload="$(cd "$here/../src" && pwd)"
else
  echo "error: cannot find the WebVuln-Runner files next to $0" >&2
  exit 1
fi

[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "error: please run as root" >&2; exit 1; }

echo "==> Installing to $DEST"
rm -rf "$DEST.new"
mkdir -p "$DEST.new" "$PREFIX/bin"
cp -R "$payload/webvuln-runner" "$payload/lib" "$payload/catalog.json" "$payload/compose" "$DEST.new/"
cp "$here/uninstall.sh" "$DEST.new/uninstall.sh"
chmod 755 "$DEST.new/webvuln-runner" "$DEST.new/uninstall.sh"
rm -rf "$DEST"
mv "$DEST.new" "$DEST"

ln -sfn "$DEST/webvuln-runner" "$PREFIX/bin/webvuln-runner"
# Name used by WebVuln-Runner 1.x
ln -sfn "$DEST/webvuln-runner" "$PREFIX/bin/WebVuln-Runner"

# Files left behind by the 1.x installers.
for old in /bin/WebVuln-Runner /bin/indexApp.lst; do
  if [[ -f "$old" && ! -L "$old" ]]; then
    echo "==> Removing old $old"
    rm -f "$old"
  fi
done

echo "==> Installed $("$DEST/webvuln-runner" version)"
