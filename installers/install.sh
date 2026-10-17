#!/usr/bin/env bash
# WebVuln-Runner installer.
# Supports Debian/Ubuntu/Kali, Fedora/RHEL/CentOS/Rocky/AlmaLinux and Arch Linux.
#
# Installs Docker (with the Compose v2 plugin where available), whiptail, jq and curl,
# then downloads a tagged release, verifies its SHA-256 checksum and installs it to
# /usr/local/lib/webvuln-runner with a 'webvuln-runner' command in /usr/local/bin.
#
# Environment:
#   WVR_RELEASE     release tag to install (default below)
#   WVR_DISTRO      force the distro family: debian | redhat | arch
#   WVR_SOURCE_DIR  install from this local checkout instead of downloading a release
#   WVR_SKIP_DEPS=1 do not install packages
set -euo pipefail

WVR_RELEASE="${WVR_RELEASE:-v2.0.0}"
REPO="yusufarbc/webvuln-runner"

say() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ "${EUID:-$(id -u)}" -eq 0 ]] || die "please run as root, e.g.: sudo bash install.sh"

detect_family() {
  [[ -n "${WVR_DISTRO:-}" ]] && { printf '%s\n' "$WVR_DISTRO"; return; }
  [[ -r /etc/os-release ]] || die "cannot detect the distribution (no /etc/os-release); set WVR_DISTRO"
  # shellcheck disable=SC1091
  . /etc/os-release
  case " ${ID:-} ${ID_LIKE:-} " in
    *" debian "*|*" ubuntu "*)                               echo debian ;;
    *" fedora "*|*" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*) echo redhat ;;
    *" arch "*)                                              echo arch ;;
    *) die "unsupported distribution '${ID:-unknown}'; set WVR_DISTRO=debian|redhat|arch to force one" ;;
  esac
}

deps_debian() {
  apt-get update -qq
  local pkgs=(whiptail jq curl ca-certificates tar)
  command -v docker >/dev/null 2>&1 || pkgs+=(docker.io)
  if ! docker compose version >/dev/null 2>&1; then
    if apt-cache show docker-compose-v2 >/dev/null 2>&1; then pkgs+=(docker-compose-v2)
    elif apt-cache show docker-compose-plugin >/dev/null 2>&1; then pkgs+=(docker-compose-plugin)
    else warn "no Docker Compose v2 package found; multi-container labs (crAPI, NodeGoat, ...) will be unavailable"
    fi
  fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkgs[@]}"
}

deps_redhat() {
  # shellcheck disable=SC1091
  . /etc/os-release
  if ! command -v docker >/dev/null 2>&1; then
    local repo
    case "${ID:-}" in
      fedora) repo="https://download.docker.com/linux/fedora/docker-ce.repo" ;;
      rhel)   repo="https://download.docker.com/linux/rhel/docker-ce.repo" ;;
      *)      repo="https://download.docker.com/linux/centos/docker-ce.repo" ;;
    esac
    say "Adding Docker's package repository ($repo)"
    dnf -y install dnf-plugins-core
    # dnf5 (Fedora 41+) and dnf4 spell this differently.
    dnf config-manager addrepo --from-repofile="$repo" 2>/dev/null ||
      dnf config-manager --add-repo "$repo"
    dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
  elif ! docker compose version >/dev/null 2>&1; then
    dnf -y install docker-compose-plugin || warn "could not install docker-compose-plugin; multi-container labs will be unavailable"
  fi
  dnf -y install newt jq curl tar
}

deps_arch() {
  local pkgs=(libnewt jq curl tar)
  command -v docker >/dev/null 2>&1 || pkgs+=(docker)
  docker compose version >/dev/null 2>&1 || pkgs+=(docker-compose)
  pacman -Sy --noconfirm --needed "${pkgs[@]}"
}

start_docker() {
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    systemctl enable --now docker.service || warn "could not start docker.service"
  fi
}

install_release() {
  local tmp name
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  name="webvuln-runner-${WVR_RELEASE#v}"
  local base="https://github.com/$REPO/releases/download/$WVR_RELEASE"
  say "Downloading WebVuln-Runner $WVR_RELEASE"
  curl -fsSL -o "$tmp/$name.tar.gz" "$base/$name.tar.gz" || die "download failed: $base/$name.tar.gz"
  curl -fsSL -o "$tmp/SHA256SUMS" "$base/SHA256SUMS" || die "download failed: $base/SHA256SUMS"
  say "Verifying checksum"
  (cd "$tmp" && grep " $name.tar.gz\$" SHA256SUMS | sha256sum -c -) || die "checksum mismatch - refusing to install"
  tar -xzf "$tmp/$name.tar.gz" -C "$tmp"
  bash "$tmp/$name/install-files.sh"
}

if [[ "${WVR_SKIP_DEPS:-0}" != 1 ]]; then
  family="$(detect_family)"
  say "Installing dependencies ($family)"
  "deps_$family"
  start_docker
fi

if [[ -n "${WVR_SOURCE_DIR:-}" ]]; then
  bash "$WVR_SOURCE_DIR/installers/install-files.sh"
else
  install_release
fi

if ! docker info >/dev/null 2>&1; then
  warn "the Docker daemon is not reachable yet; start it before running webvuln-runner"
fi
docker compose version >/dev/null 2>&1 || warn "'docker compose' is missing; multi-container labs are disabled"

cat <<EOF

WebVuln-Runner is installed. Run:  webvuln-runner      (or: webvuln-runner help)

Docker needs root. Either use 'sudo webvuln-runner', or add your user to the
'docker' group (sudo usermod -aG docker \$USER, then log in again). Note that
membership in the 'docker' group is equivalent to root access on this machine.
EOF
