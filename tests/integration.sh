#!/usr/bin/env bash
# End-to-end test against a real Docker daemon, using the small labs in tests/fixtures.
# Creates containers named it-* and wvr-it-outsider, and removes them again.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WVR_HOME="$ROOT/tests/fixtures"
WVR=("$ROOT/src/webvuln-runner")
OUTSIDER="wvr-it-outsider"
failures=0

pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
check() { local desc="$1"; shift; if "$@"; then pass "$desc"; else fail "$desc"; fi; }

cleanup() {
  for n in it-a it-b it-c it-crash; do "${WVR[@]}" rm "$n" --volumes >/dev/null 2>&1; done
  docker rm -f "$OUTSIDER" >/dev/null 2>&1
}
trap cleanup EXIT
cleanup

host_binding() { docker port "$1" "$2" | head -n1; }
running() { [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == "true" ]]; }

# A container that does not belong to WebVuln-Runner, sitting on the lab's default port.
docker run -d --name "$OUTSIDER" -p 127.0.0.1:18080:80 nginx:1.27-alpine >/dev/null

check "validate fixture catalog" "${WVR[@]}" validate
check "up test-image" "${WVR[@]}" up test-image --name it-a
check "busy default port is skipped, binding is loopback" \
  test "$(host_binding it-a 80/tcp)" = "127.0.0.1:18081"
check "second port of the lab gets its own host port" \
  test "$(host_binding it-a 8080/tcp)" = "127.0.0.1:18082"
check "catalog env is passed" \
  bash -c "docker inspect -f '{{.Config.Env}}' it-a | grep -q WVR_TEST=1"
check "lab answers over http" curl -fsS -o /dev/null http://127.0.0.1:18081/

check "second instance of the same lab" "${WVR[@]}" up test-image --name it-b
check "second instance does not reuse ports" test "$(host_binding it-b 80/tcp)" = "127.0.0.1:18083"

check "each lab is on its own network" \
  test "$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' it-a)" = "wvr-it-a"
ip_b="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' it-b)"
check "labs cannot reach each other by name" bash -c "! docker exec it-a wget -q -T 3 -O /dev/null http://it-b/"
check "labs cannot reach each other by IP" bash -c "! docker exec it-a wget -q -T 3 -O /dev/null http://$ip_b/"
check "no-new-privileges is set" \
  bash -c "docker inspect -f '{{.HostConfig.SecurityOpt}}' it-a | grep -q no-new-privileges:true"
check "memory, pids and cpu limits are set" \
  bash -c "docker inspect -f '{{.HostConfig.Memory}} {{.HostConfig.PidsLimit}} {{.HostConfig.NanoCpus}}' it-a | grep -Eq '^[1-9][0-9]* 1024 [1-9]'"
check "stats shows running labs" bash -c "'${WVR[0]}' stats | grep -q it-a"

list="$("${WVR[@]}" list)"
check "list shows managed labs" grep -q '^it-a ' <<<"$list"
check "list hides foreign containers" bash -c "! grep -q '$OUTSIDER' <<<'$list'"

check "rm refuses a foreign container" bash -c "! '${WVR[0]}' rm $OUTSIDER"
check "stop refuses a foreign container" bash -c "! '${WVR[0]}' stop $OUTSIDER"
check "foreign container still running" running "$OUTSIDER"

check "explicit busy port is refused" bash -c "! '${WVR[0]}' up test-image --name it-x --port 18081 --no-wait"
check "taken name is refused" bash -c "! '${WVR[0]}' up test-image --name $OUTSIDER --no-wait"

check "stop" "${WVR[@]}" stop it-a
check "stopped lab is not running" bash -c "! docker inspect -f '{{.State.Running}}' it-a | grep -q true"
check "stopped lab keeps its port reserved" bash -c \
  "'${WVR[0]}' up test-image --name it-x --port 18081 --no-wait; rc=\$?; docker rm -f it-x >/dev/null 2>&1; [ \$rc -ne 0 ]"
check "start" "${WVR[@]}" start it-a
check "status reports ready" bash -c "'${WVR[0]}' status it-a | grep -q 'App:       ready'"

if docker compose version >/dev/null 2>&1; then
  check "up compose lab" "${WVR[@]}" up test-compose --name it-c
  check "compose lab binds to loopback" \
    bash -c "docker ps --filter label=com.docker.compose.project=it-c --format '{{.Ports}}' | grep -q '127.0.0.1:18090->80'"
  check "compose lab is one running instance" bash -c "'${WVR[0]}' list | grep -Eq '^it-c +test-compose +running'"
  check "stop compose lab" "${WVR[@]}" stop it-c
  check "start compose lab" "${WVR[@]}" start it-c
  check "logs of compose lab" bash -c "'${WVR[0]}' logs it-c --tail 5 >/dev/null"
  check "rm compose lab" "${WVR[@]}" rm it-c --volumes
  check "compose lab is gone" test -z "$(docker ps -aq --filter label=com.docker.compose.project=it-c)"
else
  echo "skip compose tests: docker compose not available"
fi

check "up crashing lab" "${WVR[@]}" up test-crash --name it-crash --no-wait
sleep 4
check "a crashed lab is reported as failed" bash -c "'${WVR[0]}' list | grep -Eq '^it-crash +test-crash +failed'"
check "status explains the failure" bash -c "'${WVR[0]}' status it-crash | grep -q 'exit code 3'"
check "stop --all stops every lab" bash -c "'${WVR[0]}' stop --all && ! docker inspect -f '{{.State.Running}}' it-a | grep -q true"
check "rm --all needs --yes" bash -c "! '${WVR[0]}' rm --all"
check "rm --all --yes removes every lab" "${WVR[@]}" rm --all --yes
check "no managed test containers left" \
  test -z "$(docker ps -aq --filter label=io.webvuln-runner.managed=true --filter label=io.webvuln-runner.lab=test-image)"
check "lab networks are removed" test -z "$(docker network ls -q --filter label=io.webvuln-runner.managed=true --filter label=io.webvuln-runner.lab=test-image)"
check "foreign container survived everything" running "$OUTSIDER"

echo
if (( failures )); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
