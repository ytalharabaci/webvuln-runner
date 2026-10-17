# shellcheck shell=bash
# Shared setup for the Bats unit tests.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
WVR_CLI="$REPO_ROOT/src/webvuln-runner"

wvr_test_setup() {
  STUB_DIR="$(mktemp -d)"
  STUB_LOG="$STUB_DIR/calls.log"
  : >"$STUB_LOG"
  export STUB_DIR STUB_LOG
  export PATH="$REPO_ROOT/tests/helpers/bin:$PATH"
  export WVR_HOME="$REPO_ROOT/src"
  unset WVR_BIND WVR_CATALOG

  WVR_ROOT="$REPO_ROOT/src"
  # shellcheck source=../../src/lib/common.sh
  source "$WVR_ROOT/lib/common.sh"
  # shellcheck source=../../src/lib/catalog.sh
  source "$WVR_ROOT/lib/catalog.sh"
  # shellcheck source=../../src/lib/docker.sh
  source "$WVR_ROOT/lib/docker.sh"
  wvr_catalog_init

  # Nothing is listening on the test machine unless a test says so.
  wvr_port_listening() { [[ " ${TEST_LISTENING:-} " == *" $1 "* ]]; }
}

wvr_test_teardown() {
  rm -rf "$STUB_DIR"
}

# Write a catalog file from a JSON "labs" array and point WVR_CATALOG at it.
write_catalog() {
  local dir
  dir="$(mktemp -d "$STUB_DIR/cat.XXXX")"
  printf '{"schema":1,"labs":%s}\n' "$1" >"$dir/catalog.json"
  printf '%s\n' "$dir/catalog.json"
}

add_managed() { # id instance lab state url [project]
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "${6:-}" >>"$STUB_DIR/managed"
}

docker_calls() { cat "$STUB_LOG"; }
