#!/usr/bin/env bats
# Catalog parsing and validation.

load ../helpers/common

setup() { wvr_test_setup; }
teardown() { wvr_test_teardown; }

lab() { # id host [extra json fields]
  printf '{"id":"%s","name":"Lab %s","description":"d","category":"web","type":"image","image":"x/%s:1.0","ports":[{"name":"web","container":80,"host":%s}]%s}' \
    "$1" "$1" "$1" "$2" "${3:+,$3}"
}

@test "shipped catalog is valid" {
  run wvr_catalog_validate "$REPO_ROOT/src/catalog.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a minimal valid catalog passes" {
  f="$(write_catalog "[$(lab a 8001), $(lab b 8002)]")"
  run wvr_catalog_validate "$f"
  [ "$status" -eq 0 ]
}

@test "invalid JSON is rejected" {
  f="$STUB_DIR/broken.json"
  echo '{"labs": [' >"$f"
  run wvr_catalog_validate "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not valid JSON"* ]]
}

@test "empty catalog is rejected" {
  f="$(write_catalog "[]")"
  run wvr_catalog_validate "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no labs defined"* ]]
}

@test "duplicate lab ids are rejected" {
  f="$(write_catalog "[$(lab a 8001), $(lab a 8002)]")"
  run wvr_catalog_validate "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate id: a"* ]]
}

@test "two labs with the same default host port are rejected" {
  f="$(write_catalog "[$(lab a 8001), $(lab b 8001)]")"
  run wvr_catalog_validate "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"host port 8001"* ]]
}

@test "out of range ports are rejected" {
  f="$(write_catalog "[$(lab a 70000)]")"
  run wvr_catalog_validate "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"host must be 1-65535"* ]]
}

@test "image without a tag is rejected" {
  f="$(write_catalog '[{"id":"a","name":"A","description":"d","category":"web","type":"image","image":"x/a","ports":[{"name":"web","container":80,"host":8001}]}]')"
  run wvr_catalog_validate "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *'image must be "repository:tag"'* ]]
}

@test "unknown category and type are rejected" {
  f="$(write_catalog '[{"id":"a","name":"A","description":"d","category":"games","type":"vm","ports":[{"name":"web","container":80,"host":8001}]}]')"
  run wvr_catalog_validate "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"category must be one of"* ]]
  [[ "$output" == *'type must be "image" or "compose"'* ]]
}

@test "lab without ports is rejected" {
  f="$(write_catalog '[{"id":"a","name":"A","description":"d","category":"web","type":"image","image":"x/a:1","ports":[]}]')"
  run wvr_catalog_validate "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs at least one port"* ]]
}

@test "missing compose file is rejected" {
  f="$(write_catalog '[{"id":"a","name":"A","description":"d","category":"web","type":"compose","compose":"compose/a/compose.yml","ports":[{"name":"web","host":8001}]}]')"
  run wvr_catalog_validate "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"compose file missing: compose/a/compose.yml"* ]]
}

@test "health defaults to the first port's scheme and path" {
  run wvr_catalog_health dvga
  [ "$output" = "$(printf 'http\t/')" ]
  run wvr_catalog_health owasp-benchmark
  [ "$output" = "$(printf 'https\t/benchmark/')" ]
}

@test "explicit health path wins" {
  run wvr_catalog_health webgoat
  [ "$output" = "$(printf 'http\t/WebGoat/actuator/health')" ]
}

@test "catalog_ports lists every port of a lab" {
  run wvr_catalog_ports webgoat
  [ "${lines[0]}" = "$(printf 'web\t8080\t8080\thttp\t/WebGoat')" ]
  [ "${lines[1]}" = "$(printf 'webwolf\t9090\t9090\thttp\t/WebWolf')" ]
}

@test "descriptions longer than 50 characters are rejected" {
  f="$(write_catalog '[{"id":"a","name":"A","description":"This description is far too long to fit into the TUI menu","category":"web","type":"image","image":"x/a:1","ports":[{"name":"web","container":80,"host":8001}]}]')"
  run wvr_catalog_validate "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"at most 50 characters"* ]]
}
