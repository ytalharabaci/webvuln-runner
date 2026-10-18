# shellcheck shell=bash
# Shared constants and helpers for WebVuln-Runner.
# shellcheck disable=SC2034 # constants are used by the other lib files

WVR_VERSION="2.3.1"

# Every container/network/volume created by this tool carries these labels.
# Anything without them is never listed, started, stopped or removed.
WVR_LABEL_NS="io.webvuln-runner"
WVR_LABEL_MANAGED="${WVR_LABEL_NS}.managed"
WVR_LABEL_LAB="${WVR_LABEL_NS}.lab"
WVR_LABEL_URL="${WVR_LABEL_NS}.url"
WVR_LABEL_INSTANCE="${WVR_LABEL_NS}.instance"
WVR_LABEL_HEALTH="${WVR_LABEL_NS}.health"

# Labs are published on loopback unless the user explicitly opts in to LAN exposure.
WVR_BIND="${WVR_BIND:-127.0.0.1}"
WVR_HEALTH_TIMEOUT="${WVR_HEALTH_TIMEOUT:-90}"

# Remembers which labs were stopped on purpose, so their exit codes are not reported as failures.
WVR_STATE_DIR="${WVR_STATE_DIR:-${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/webvuln-runner}"

wvr_info() { printf '%s\n' "$*"; }
wvr_warn() { printf 'warning: %s\n' "$*" >&2; }
wvr_err()  { printf 'error: %s\n' "$*" >&2; }
wvr_die()  { wvr_err "$*"; exit 1; }

wvr_have() { command -v "$1" >/dev/null 2>&1; }

# Check required tools. Prints one line per missing tool, returns 1 if any is missing.
wvr_check_deps() {
  local missing=0 dep
  for dep in "$@"; do
    if ! wvr_have "$dep"; then
      wvr_err "required command not found: $dep"
      missing=1
    fi
  done
  return "$missing"
}

wvr_check_docker() {
  if ! docker info >/dev/null 2>&1; then
    wvr_err "cannot talk to the Docker daemon."
    wvr_err "Start Docker, then run WebVuln-Runner with sudo or as a member of the 'docker' group."
    wvr_err "Note: membership in the 'docker' group is equivalent to root access on this host."
    return 1
  fi
}

wvr_have_compose() { docker compose version >/dev/null 2>&1; }

# Instance names become container names or Compose project names, so they must
# satisfy both: lowercase letters, digits, '-' and '_', starting with a letter or digit.
wvr_valid_name() {
  [[ "${1:-}" =~ ^[a-z0-9][a-z0-9_-]{0,62}$ ]]
}

wvr_valid_port() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

wvr_valid_bind() {
  [[ "${1:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}
