#!/usr/bin/env bats
# Catalog parsing and validation.

load ../helpers/common

setup() { wvr_test_setup; }
teardown() { wvr_test_teardown; }

lab() { # id host [extra json fields]
  printf '{"id":"%s","name":"Lab %s","description":"d","category":"web","type":"image","image":"x/%s:1.0","level":"beginner","topics":["sqli"],"license":"MIT","verified":"2026-10-17","ports":[{"name":"web","container":80,"host":%s}]%s}' \
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

@test "hardening, mem_limit_mb and cpus are type checked" {
  f="$(write_catalog '[{"id":"a","name":"A","description":"d","category":"web","type":"image","image":"x/a:1","hardening":"no","mem_limit_mb":10,"cpus":0,"ports":[{"name":"web","container":80,"host":8001}]}]')"
  run wvr_catalog_validate "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"hardening must be true or false"* ]]
  [[ "$output" == *"mem_limit_mb must be a number >= 64"* ]]
  [[ "$output" == *"cpus must be a positive number"* ]]
}

@test "topics must come from the vocabulary and may not be empty" {
  f="$(write_catalog "[$(lab a 8001 '"topics":["sqli","telepathy"]'), $(lab b 8002 '"topics":[]')]")"
  run wvr_catalog_validate "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a: unknown topic: telepathy"* ]]
  [[ "$output" == *"b: needs a non-empty topics list"* ]]
}

@test "level, license and verified are checked" {
  f="$(write_catalog "[$(lab a 8001 '"level":"expert","license":"","verified":"last week"')]")"
  run wvr_catalog_validate "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"level must be one of beginner, intermediate, advanced"* ]]
  [[ "$output" == *"missing license"* ]]
  [[ "$output" == *"verified must be a YYYY-MM-DD date"* ]]
}

@test "an old verified date only warns" {
  f="$(write_catalog "[$(lab a 8001 '"verified":"2020-01-01"')]")"
  run wvr_catalog_validate "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not verified in the last 180 days"*"a (2020-01-01)"* ]]
}

@test "every shipped lab has topics, a level, a license and a verified date" {
  run jq -e '[.labs[] | select((.topics | length) == 0 or .level == null or .license == null or .verified == null)] | length == 0' "$REPO_ROOT/src/catalog.json"
  [ "$status" -eq 0 ]
}

@test "filtering by topic, category and level combines" {
  run wvr_catalog_list_filtered sqli "" ""
  [[ "$output" == *"sqli-labs"* ]]
  [[ "$output" != *"wrongsecrets"* ]]
  run wvr_catalog_list_filtered secrets "" beginner
  [ "$(cut -f1 <<<"$output" | sort | tr '\n' ' ')" = "goof wrongsecrets " ]
  run wvr_catalog_list_filtered "" graphql ""
  [ "$(cut -f1 <<<"$output")" = "dvga" ]
}

@test "topic counts match the catalog" {
  run wvr_catalog_topics
  [[ "$output" == *"$(printf 'grpc\t1')"* ]]
  [ "$(grep -P '^sqli\t' <<<"$output" | cut -f2)" -eq "$(jq '[.labs[] | select(.topics | index("sqli"))] | length' "$REPO_ROOT/src/catalog.json")" ]
}
