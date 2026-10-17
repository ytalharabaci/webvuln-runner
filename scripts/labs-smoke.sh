#!/usr/bin/env bash
# Starts catalog labs for real and checks each one end to end:
#   up -> app answers -> stop shows "stopped" (not "failed") -> rm --volumes
# Pulls/builds images, so the first run takes a long time. Needs a Docker daemon.
#
# Usage: scripts/labs-smoke.sh [--update-verified] [lab ...]   (default: every lab)
#   --update-verified  write today's date into "verified" for every lab that passed
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

WVR=./src/webvuln-runner
update=0
if [[ "${1:-}" == "--update-verified" ]]; then update=1; shift; fi
labs=("$@")
(( ${#labs[@]} )) || mapfile -t labs < <(jq -r '.labs[].id' src/catalog.json)

passed=() failed=()
for lab in "${labs[@]}"; do
  name="smoke-$lab"
  echo "######## $lab  $(date +%T)"
  start=$SECONDS
  log="$(mktemp)"
  ok=1
  if ! "$WVR" up "$lab" --name "$name" >"$log" 2>&1; then
    ok=0
    echo "up/ready failed:"
    grep -a -E '^(error|warning)' "$log" | tail -5
    "$WVR" status "$name" 2>&1 | tail -25
  else
    echo "ready after $((SECONDS - start))s: $("$WVR" list | awk -v n="$name" '$1 == n { print $4 }')"
    "$WVR" stop "$name" >/dev/null 2>&1
    state="$("$WVR" list | awk -v n="$name" '$1 == n { print $3 }')"
    if [[ "$state" != "stopped" ]]; then
      ok=0
      echo "after stop the lab shows '$state' instead of 'stopped'"
      "$WVR" status "$name" 2>&1 | tail -25
    fi
  fi
  "$WVR" rm "$name" --volumes >/dev/null 2>&1
  rm -f "$log"
  if (( ok )); then passed+=("$lab"); else failed+=("$lab"); fi
done

echo
echo "passed (${#passed[@]}): ${passed[*]:-}"
echo "failed (${#failed[@]}): ${failed[*]:-}"

if (( update )) && (( ${#passed[@]} )); then
  today="$(date +%F)"
  tmp="$(mktemp)"
  jq --indent 2 --arg d "$today" --args '.labs |= map(if (.id | IN($ARGS.positional[])) then .verified = $d else . end)' \
    src/catalog.json "${passed[@]}" >"$tmp" && mv "$tmp" src/catalog.json
  echo "verified date set to $today for ${#passed[@]} lab(s)"
fi

(( ${#failed[@]} == 0 ))
