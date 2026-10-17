#!/usr/bin/env bats
# Command line parsing and error handling of src/webvuln-runner.

load ../helpers/common

setup() { wvr_test_setup; }
teardown() { wvr_test_teardown; }

@test "help and version exit 0" {
  run "$WVR_CLI" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  run "$WVR_CLI" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "webvuln-runner "* ]]
}

@test "unknown command is a usage error" {
  run "$WVR_CLI" frobnicate
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown command: frobnicate"* ]]
}

@test "up without a lab is a usage error" {
  run "$WVR_CLI" up
  [ "$status" -eq 2 ]
  run "$WVR_CLI" up dvga --port
  [ "$status" -eq 2 ]
  run "$WVR_CLI" up dvga --bogus
  [ "$status" -eq 2 ]
}

@test "up with an unknown lab fails" {
  run "$WVR_CLI" up no-such-lab
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown lab: no-such-lab"* ]]
}

@test "validate works without docker" {
  export STUB_INFO_RC=1
  run "$WVR_CLI" validate
  [ "$status" -eq 0 ]
  [[ "$output" == "catalog OK: "* ]]
}

@test "validate reports a broken catalog" {
  f="$(write_catalog '[{"id":"x"}]')"
  run "$WVR_CLI" validate "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing name"* ]]
}

@test "a clear error when the docker daemon is unreachable" {
  export STUB_INFO_RC=1
  run "$WVR_CLI" list
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot talk to the Docker daemon"* ]]
}

@test "list with no labs explains how to start one" {
  run "$WVR_CLI" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"No labs yet"* ]]
}

@test "catalog lists every lab" {
  run "$WVR_CLI" catalog
  [ "$status" -eq 0 ]
  [ "$(( ${#lines[@]} - 1 ))" -eq "$(jq '.labs | length' "$REPO_ROOT/src/catalog.json")" ]
}

@test "rm of a foreign container fails without touching it" {
  echo "postgres" >"$STUB_DIR/names"
  run "$WVR_CLI" rm postgres
  [ "$status" -eq 1 ]
  ! grep -q '^rm ' "$STUB_LOG" || false
}

@test "rm --all requires --yes" {
  run "$WVR_CLI" rm --all
  [ "$status" -eq 2 ]
  [[ "$output" == *"add --yes to confirm"* ]]
  ! grep -q '^rm ' "$STUB_LOG" || false
}

@test "rm --all and a lab name cannot be combined" {
  run "$WVR_CLI" rm wvr-x --all --yes
  [ "$status" -eq 2 ]
}

@test "stop --all and stats work with no labs" {
  run "$WVR_CLI" stop --all
  [ "$status" -eq 0 ]
  run "$WVR_CLI" stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"No running labs"* ]]
}
