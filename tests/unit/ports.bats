#!/usr/bin/env bats
# Names, ports and URLs.

load ../helpers/common

setup() { wvr_test_setup; }
teardown() { wvr_test_teardown; }

@test "valid instance names" {
  for n in wvr-juice-shop lab1 a_b 0x; do
    run wvr_valid_name "$n"
    [ "$status" -eq 0 ]
  done
}

@test "invalid instance names" {
  for n in "" "Bad" "has space" "-lead" "_lead" "a.b" "a/b" "$(printf 'a%.0s' {1..64})"; do
    run wvr_valid_name "$n"
    [ "$status" -ne 0 ]
  done
}

@test "port validation" {
  run wvr_valid_port 1;     [ "$status" -eq 0 ]
  run wvr_valid_port 65535; [ "$status" -eq 0 ]
  run wvr_valid_port 0;     [ "$status" -ne 0 ]
  run wvr_valid_port 65536; [ "$status" -ne 0 ]
  run wvr_valid_port 80a;   [ "$status" -ne 0 ]
  run wvr_valid_port "";    [ "$status" -ne 0 ]
}

@test "pick_port returns the start port when free" {
  run wvr_pick_port 8080 ""
  [ "$output" = "8080" ]
}

@test "pick_port skips ports used by docker and by other programs" {
  TEST_LISTENING="8081"
  run wvr_pick_port 8080 "8080 8082"
  [ "$output" = "8083" ]
}

@test "plan_ports moves every port off a busy one" {
  wvr_used_ports() { printf '8080\n'; }
  run wvr_plan_ports webgoat
  [ "$status" -eq 0 ]
  [ "$(cut -f3 <<<"${lines[0]}")" = "8081" ]
  [ "$(cut -f3 <<<"${lines[1]}")" = "9090" ]
}

@test "plan_ports never gives two ports of one lab the same host port" {
  wvr_used_ports() { printf '8001\n'; }
  run wvr_plan_ports apigoat
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -f3 | sort | uniq -d)" = "" ]
}

@test "plan_ports refuses an explicitly requested busy port" {
  wvr_used_ports() { printf '9000\n'; }
  run wvr_plan_ports dvga 9000
  [ "$status" -eq 1 ]
  [[ "$output" == *"host port 9000 is already in use"* ]]
}

@test "plan_ports honours an explicit free port" {
  run wvr_plan_ports dvga 9999
  [ "$(cut -f3 <<<"${lines[0]}")" = "9999" ]
}

@test "urls" {
  [ "$(wvr_port_url 127.0.0.1 8080 http /WebGoat)" = "http://127.0.0.1:8080/WebGoat" ]
  [ "$(wvr_port_url 0.0.0.0 8443 https /)" = "https://127.0.0.1:8443/" ]
  [ "$(wvr_port_url 127.0.0.1 50051 grpc /)" = "grpc://127.0.0.1:50051" ]
}

@test "default bind is loopback" {
  [ "$WVR_BIND" = "127.0.0.1" ]
}
