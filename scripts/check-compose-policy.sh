#!/usr/bin/env bash
# Enforces WebVuln-Runner's rules on every Compose lab (see README "Adding a lab"):
#   - each service carries the managed label and no-new-privileges
#   - no container_name, privileged mode, host network/PID namespace or Docker socket mounts
#   - every published port binds to ${WVR_BIND}
# Usage: scripts/check-compose-policy.sh [compose.yml ...]   (default: src/compose/*/compose.yml)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# A sentinel bind address: a port that does not resolve to it ignores ${WVR_BIND}.
SENTINEL="203.0.113.7"
files=("$@")
(( ${#files[@]} )) || files=(src/compose/*/compose.yml)
failed=0

for f in "${files[@]}"; do
  if ! json="$(WVR_BIND="$SENTINEL" docker compose -f "$f" config --format json 2>&1)"; then
    printf '%s: docker compose config failed:\n%s\n' "$f" "$json"
    failed=1
    continue
  fi
  problems="$(jq -r --arg bind "$SENTINEL" '
    .services | to_entries[] | .key as $s | .value |
      ( if (.labels["io.webvuln-runner.managed"] // "") != "true" then "\($s): missing label io.webvuln-runner.managed=true" else empty end ),
      ( if has("container_name") then "\($s): container_name prevents several instances" else empty end ),
      ( if .privileged == true then "\($s): privileged mode is not allowed" else empty end ),
      ( if .network_mode == "host" then "\($s): host networking is not allowed" else empty end ),
      ( if .pid == "host" then "\($s): host PID namespace is not allowed" else empty end ),
      ( if ((.security_opt // []) | index("no-new-privileges:true")) == null
        then "\($s): security_opt must include no-new-privileges:true" else empty end ),
      ( (.volumes // [])[] | select((.source // "") | test("docker\\.sock"))
        | "\($s): mounting the Docker socket is not allowed" ),
      ( (.ports // [])[] | select(.published != null and .host_ip != $bind)
        | "\($s): port \(.published) is not bound to ${WVR_BIND}" )
  ' <<<"$json")"
  if [[ -n "$problems" ]]; then
    printf '%s\n' "$problems" | sed "s#^#$f: #"
    failed=1
  else
    echo "ok $f"
  fi
done

exit "$failed"
