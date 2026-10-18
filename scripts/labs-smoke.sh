#!/usr/bin/env bash
# Starts catalog labs for real and checks each one end to end:
#   up -> app answers -> stop shows "stopped" (not "failed") -> rm --volumes
# Pulls/builds images, so the first run takes a long time. Needs a Docker daemon.
#
# Usage: scripts/labs-smoke.sh [options] [lab ...]   (default: every lab)
#   --update-verified       write today's date into "verified" for every lab that passed
#   --report-json [FILE]    generate structured JSON report (default: smoke-report.json)
#   --report-md [FILE]      generate Markdown summary report (default: smoke-report.md)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

WVR=./src/webvuln-runner
update=0
report_json=""
report_md=""
labs=()

while (( $# )); do
  case "$1" in
    --update-verified)
      update=1
      shift
      ;;
    --report-json)
      if [[ $# -ge 2 && "$2" != --* ]]; then
        report_json="$2"
        shift 2
      else
        report_json="smoke-report.json"
        shift
      fi
      ;;
    --report-md)
      if [[ $# -ge 2 && "$2" != --* ]]; then
        report_md="$2"
        shift 2
      else
        report_md="smoke-report.md"
        shift
      fi
      ;;
    -*)
      echo "unknown option: $1" >&2
      exit 2
      ;;
    *)
      labs+=("$1")
      shift
      ;;
  esac
done

(( ${#labs[@]} )) || mapfile -t labs < <(jq -r '.labs[].id' src/catalog.json)

passed=() failed=()
declare -a results_json=()

for lab in "${labs[@]}"; do
  name="smoke-$lab"
  echo "######## $lab  $(date +%T)"
  start=$SECONDS
  log="$(mktemp)"
  ok=1
  lab_url=""
  err_detail=""

  if ! "$WVR" up "$lab" --name "$name" >"$log" 2>&1; then
    ok=0
    echo "up/ready failed:"
    err_detail="$(grep -a -E '^(error|warning)' "$log" | tail -5)"
    printf '%s\n' "$err_detail"
    "$WVR" status "$name" 2>&1 | tail -25
  else
    lab_url="$("$WVR" list | awk -v n="$name" '$1 == n { print $4 }')"
    echo "ready after $((SECONDS - start))s: $lab_url"
    "$WVR" stop "$name" >/dev/null 2>&1
    state="$("$WVR" list | awk -v n="$name" '$1 == n { print $3 }')"
    if [[ "$state" != "stopped" ]]; then
      ok=0
      err_detail="after stop the lab shows '$state' instead of 'stopped'"
      echo "$err_detail"
      "$WVR" status "$name" 2>&1 | tail -25
    fi
  fi
  "$WVR" rm "$name" --volumes >/dev/null 2>&1
  rm -f "$log"
  duration=$((SECONDS - start))

  if (( ok )); then
    passed+=("$lab")
    status_str="passed"
  else
    failed+=("$lab")
    status_str="failed"
  fi

  # Record single JSON item
  results_json+=( "$(jq -n \
    --arg id "$lab" \
    --arg status "$status_str" \
    --argjson duration "$duration" \
    --arg url "$lab_url" \
    --arg err "$err_detail" \
    '{id: $id, status: $status, duration_seconds: $duration, url: $url, error: (if $err == "" then null else $err end)}')" )
done

echo
echo "passed (${#passed[@]}): ${passed[*]:-}"
echo "failed (${#failed[@]}): ${failed[*]:-}"

# Write JSON report if requested
if [[ -n "$report_json" ]]; then
  tmp_items="$(mktemp)"
  printf '%s\n' "${results_json[@]}" | jq -s '.' >"$tmp_items"
  jq -n \
    --arg date "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --argjson passed "${#passed[@]}" \
    --argjson failed "${#failed[@]}" \
    --slurpfile results "$tmp_items" \
    '{timestamp: $date, passed_count: $passed, failed_count: $failed, results: $results[0]}' >"$report_json"
  rm -f "$tmp_items"
  echo "Smoke report (JSON) written to: $report_json"
fi

# Write Markdown report if requested
if [[ -n "$report_md" ]]; then
  {
    echo "# WebVuln-Runner Smoke Test Report"
    echo ""
    echo "- **Execution Date:** $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
    echo "- **Total Tested:** $((${#passed[@]} + ${#failed[@]}))"
    echo "- **Passed:** ${#passed[@]} :white_check_mark:"
    echo "- **Failed:** ${#failed[@]} :x:"
    echo ""
    echo "| Lab ID | Status | Duration | URL | Details / Error |"
    echo "|---|---|---|---|---|"
    for item in "${results_json[@]}"; do
      r_id="$(jq -r '.id' <<<"$item")"
      r_status="$(jq -r '.status' <<<"$item")"
      r_dur="$(jq -r '.duration_seconds' <<<"$item")"
      r_url="$(jq -r '.url // "-"' <<<"$item")"
      r_err="$(jq -r '.error // "-"' <<<"$item" | tr '\n' ' ')"
      if [[ "$r_status" == "passed" ]]; then
        s_badge=":white_check_mark: passed"
      else
        s_badge=":x: failed"
      fi
      echo "| \`$r_id\` | $s_badge | ${r_dur}s | \`$r_url\` | $r_err |"
    done
  } >"$report_md"
  echo "Smoke report (Markdown) written to: $report_md"
fi

if (( update )) && (( ${#passed[@]} )); then
  today="$(date +%F)"
  tmp="$(mktemp)"
  jq --indent 2 --arg d "$today" --args '.labs |= map(if (.id | IN($ARGS.positional[])) then .verified = $d else . end)' \
    src/catalog.json "${passed[@]}" >"$tmp" && mv "$tmp" src/catalog.json
  echo "verified date set to $today for ${#passed[@]} lab(s)"
fi

(( ${#failed[@]} == 0 ))
