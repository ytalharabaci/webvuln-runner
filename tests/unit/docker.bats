#!/usr/bin/env bats
# Lifecycle against a fake docker CLI (tests/helpers/bin/docker).

load ../helpers/common

setup() { wvr_test_setup; }
teardown() { wvr_test_teardown; }

create_call() { grep '^create ' "$STUB_LOG"; }

@test "up publishes on 127.0.0.1 and labels the container" {
  run wvr_up dsvpwa wvr-dsvpwa 127.0.0.1
  [ "$status" -eq 0 ]
  c="$(create_call)"
  [[ "$c" == *"-p 127.0.0.1:65413:65413"* ]]
  [[ "$c" == *"--label io.webvuln-runner.managed=true"* ]]
  [[ "$c" == *"--label io.webvuln-runner.lab=dsvpwa"* ]]
  [[ "$c" == *"--label io.webvuln-runner.instance=wvr-dsvpwa"* ]]
  [[ "$c" == *"--label io.webvuln-runner.url=http://127.0.0.1:65413/"* ]]
  [[ "$c" == *" sgabe/dsvpwa:0.2.1" ]]
}

@test "up never publishes on all interfaces unless asked" {
  run wvr_up apigoat wvr-apigoat 127.0.0.1
  [ "$status" -eq 0 ]
  ! create_call | grep -q -- '-p 0.0.0.0:' || false
  [ "$(create_call | grep -o -- '-p 127.0.0.1:' | wc -l)" -eq 11 ]
}

@test "up with --bind 0.0.0.0 publishes there and warns" {
  run wvr_up vampi wvr-vampi 0.0.0.0
  [ "$status" -eq 0 ]
  [[ "$(create_call)" == *"-p 0.0.0.0:5000:5000"* ]]
  [[ "$output" == *"reachable from other machines"* ]]
}

@test "up passes env, workdir and command from the catalog" {
  run wvr_up dvga wvr-dvga 127.0.0.1
  [[ "$(create_call)" == *"-e WEB_HOST=0.0.0.0"* ]]
  : >"$STUB_LOG"
  run wvr_up owasp-benchmark wvr-bench 127.0.0.1
  c="$(create_call)"
  [[ "$c" == *"-w /owasp/BenchmarkJava"* ]]
  [[ "$c" == *"owasp/benchmark:latest ./runRemoteAccessibleBenchmark.sh" ]]
}

@test "up refuses a name that is already used by any container" {
  echo "someone-elses-app" >"$STUB_DIR/names"
  run wvr_up dsvpwa someone-elses-app 127.0.0.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
  ! create_call || false
}

@test "up rejects invalid names, binds and ports before calling docker" {
  run wvr_up dsvpwa "Bad Name" 127.0.0.1
  [ "$status" -eq 1 ]
  run wvr_up dsvpwa ok 999.1
  [ "$status" -eq 1 ]
  run wvr_up dsvpwa ok 127.0.0.1 99999
  [ "$status" -eq 1 ]
  ! create_call || false
}

@test "up removes the container again when it fails to start" {
  export STUB_START_RC=1
  run wvr_up dsvpwa wvr-dsvpwa 127.0.0.1
  [ "$status" -eq 1 ]
  grep -q '^rm -f c0ffee000001' "$STUB_LOG"
}

@test "up reports pull failures" {
  export STUB_IMAGE_RC=1 STUB_PULL_RC=1
  run wvr_up dsvpwa wvr-dsvpwa 127.0.0.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not pull sgabe/dsvpwa:0.2.1"* ]]
  ! create_call || false
}

@test "stop, start and rm refuse containers not created by WebVuln-Runner" {
  echo "postgres" >"$STUB_DIR/names"
  for op in wvr_stop wvr_start wvr_rm wvr_logs wvr_status; do
    run "$op" postgres
    [ "$status" -eq 1 ]
    [[ "$output" == *"only labs created by this tool can be managed"* ]]
  done
  ! grep -Eq '^(stop|start|rm|logs) ' "$STUB_LOG" || false
}

@test "stop and rm act on the instance's container ids only" {
  add_managed aaa111 lab-one dsvpwa running http://127.0.0.1:65413/
  add_managed bbb222 lab-two vampi running http://127.0.0.1:5000/
  run wvr_stop lab-one
  [ "$status" -eq 0 ]
  grep -qx 'stop aaa111' "$STUB_LOG"
  run wvr_rm lab-one --volumes
  grep -qx 'rm -f -v aaa111' "$STUB_LOG"
  ! grep -q 'bbb222' <(grep -E '^(stop|rm) ' "$STUB_LOG") || false
}

@test "compose instances are managed through their project" {
  add_managed ccc333 my-crapi crapi running http://127.0.0.1:8888/ my-crapi
  run wvr_rm my-crapi
  [ "$status" -eq 0 ]
  grep -qx 'compose -p my-crapi down --remove-orphans' "$STUB_LOG"
}

@test "instances are aggregated per name" {
  add_managed c1 stack1 test-compose running http://127.0.0.1:18090/ stack1
  add_managed c2 stack1 test-compose exited "" stack1
  add_managed c3 solo dsvpwa exited http://127.0.0.1:65413/
  run wvr_instances
  [ "${lines[0]}" = "$(printf 'solo\tdsvpwa\tstopped\thttp://127.0.0.1:65413/')" ]
  [ "${lines[1]}" = "$(printf 'stack1\ttest-compose\tpartial 1/2\thttp://127.0.0.1:18090/')" ]
}

@test "listing only ever asks docker for managed containers" {
  run wvr_instances
  grep -q '^ps ' "$STUB_LOG"
  [ -z "$(grep '^ps ' "$STUB_LOG" | grep -v 'label=io.webvuln-runner.managed=true')" ]
}

@test "compose labs get their ports and bind via environment" {
  export WVR_CATALOG="$REPO_ROOT/tests/fixtures/catalog.json" WVR_HOME="$REPO_ROOT/tests/fixtures"
  run wvr_up test-compose stack1 127.0.0.1
  [ "$status" -eq 0 ]
  grep -q "compose -p stack1 -f $REPO_ROOT/tests/fixtures/compose/test-compose/compose.yml up -d" "$STUB_LOG"
  grep -qx 'WVR_BIND=127.0.0.1' "$STUB_DIR/compose_env"
  grep -qx 'WVR_PORT_WEB=18090' "$STUB_DIR/compose_env"
  grep -qx 'WVR_INSTANCE=stack1' "$STUB_DIR/compose_env"
}

@test "compose labs are refused without the compose plugin" {
  export WVR_CATALOG="$REPO_ROOT/tests/fixtures/catalog.json" WVR_HOME="$REPO_ROOT/tests/fixtures"
  export STUB_COMPOSE_RC=1
  run wvr_up test-compose stack1 127.0.0.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs the Docker Compose v2 plugin"* ]]
}

@test "default names skip names already in use" {
  printf 'wvr-dvga\nwvr-dvga-2\n' >"$STUB_DIR/names"
  run wvr_default_name dvga
  [ "$output" = "wvr-dvga-3" ]
}
