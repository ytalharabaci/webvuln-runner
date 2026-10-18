# shellcheck shell=bash
# Lab lifecycle on top of the docker CLI.
# Only containers labelled ${WVR_LABEL_MANAGED}=true are ever listed, started, stopped or removed.

wvr_ps_managed() {
  docker ps -a --filter "label=${WVR_LABEL_MANAGED}=true" "$@"
}

# One line per managed container: id, instance, lab, state, url, compose project, status
# ("status" is Docker's human text, e.g. "Up 2 minutes (healthy)" or "Exited (1) 3 seconds ago").
wvr_containers() {
  wvr_ps_managed "$@" --format "{{.ID}}\t{{.Label \"$WVR_LABEL_INSTANCE\"}}\t{{.Label \"$WVR_LABEL_LAB\"}}\t{{.State}}\t{{.Label \"$WVR_LABEL_URL\"}}\t{{.Label \"com.docker.compose.project\"}}\t{{.Status}}"
}

# Labs stopped through WebVuln-Runner. Many apps exit non-zero when stopped (Go services
# exit 2, some Node apps 1), so an exit code alone does not tell a stop from a crash.
wvr_mark_stopped()  { mkdir -p "$WVR_STATE_DIR/stopped" 2>/dev/null && : >"$WVR_STATE_DIR/stopped/$1"; }
wvr_clear_stopped() { rm -f "$WVR_STATE_DIR/stopped/$1" 2>/dev/null; return 0; }
wvr_stopped_list() {
  local f
  for f in "$WVR_STATE_DIR"/stopped/*; do [[ -e "$f" ]] && printf '%s ' "${f##*/}"; done
  return 0
}

# One line per instance: name, lab, state, url.
# State is the most important one among its containers:
#   failed > unhealthy > restarting > starting > partial n/m > running | stopped
# A container that exited with 0, 137 or 143 counts as stopped, and so does any container
# of a lab WebVuln-Runner stopped itself. Any other exit code means it failed.
wvr_instances() {
  wvr_containers | awk -F'\t' -v stopped=" $(wvr_stopped_list) " '
    function rank(s) { return s == "failed" ? 4 : s == "unhealthy" ? 3 : s == "restarting" ? 2 : s == "starting" ? 1 : 0 }
    $2 == "" { next }
    {
      k = $2
      if (!(k in lab)) { order[++n] = k; lab[k] = $3; worst[k] = "" }
      total[k]++
      cs = "stopped"
      if ($4 == "running") {
        cs = "running"
        if ($7 ~ /\(unhealthy\)/) cs = "unhealthy"
        else if ($7 ~ /health: starting/) cs = "starting"
      } else if ($4 == "restarting") {
        cs = "restarting"
      } else if ($4 == "exited" || $4 == "dead") {
        code = $7
        if (match(code, /\([0-9]+\)/)) {
          code = substr(code, RSTART + 1, RLENGTH - 2)
          if (code != "0" && code != "137" && code != "143" && index(stopped, " " k " ") == 0) cs = "failed"
        }
      }
      if (cs == "running" || cs == "unhealthy" || cs == "starting") run[k]++
      if (rank(cs) > rank(worst[k])) worst[k] = cs
      if ($5 != "" && url[k] == "") url[k] = $5
    }
    END {
      for (i = 1; i <= n; i++) {
        k = order[i]; r = run[k] + 0
        if (worst[k] != "" && worst[k] != "running" && worst[k] != "stopped") s = worst[k]
        else s = (r == total[k]) ? "running" : (r == 0 ? "stopped" : "partial " r "/" total[k])
        printf "%s\t%s\t%s\t%s\n", k, lab[k], s, url[k]
      }
    }' | sort
}

wvr_instance_ids() {
  wvr_ps_managed -q --filter "label=${WVR_LABEL_INSTANCE}=$1"
}

wvr_instance_exists() {
  wvr_valid_name "${1:-}" && [[ -n "$(wvr_instance_ids "$1")" ]]
}

# Prints the compose project of an instance, empty for single-container labs.
wvr_instance_project() {
  wvr_containers --filter "label=${WVR_LABEL_INSTANCE}=$1" | cut -f6 | head -n1
}

wvr_instance_label() {
  local id
  for id in $(wvr_instance_ids "$1"); do
    docker inspect --format "{{index .Config.Labels \"$2\"}}" "$id"
  done | grep -v '^$' | head -n1
}

wvr_require_instance() {
  if ! wvr_instance_exists "${1:-}"; then
    wvr_err "no WebVuln-Runner lab named '${1:-}' (only labs created by this tool can be managed)"
    return 1
  fi
}

# A name is taken if any container (managed or not) or any Compose project already uses it.
wvr_name_taken() {
  docker ps -a --format '{{.Names}}' | grep -Fxq -- "$1" ||
    [[ -n "$(docker ps -aq --filter "label=com.docker.compose.project=$1")" ]]
}

wvr_default_name() {
  local base="wvr-$1" name n=2
  name="$base"
  while wvr_name_taken "$name"; do
    name="$base-$n"
    n=$((n + 1))
  done
  printf '%s\n' "$name"
}

# Host ports already claimed by Docker: published ports of running containers,
# plus the bindings of stopped managed labs (they would collide when started again).
wvr_used_ports() {
  local running managed
  running="$(docker ps -q)"
  managed="$(wvr_ps_managed -q)"
  {
    # shellcheck disable=SC2086 # word splitting of container ids is intended
    [[ -n "$running" ]] && docker inspect --format \
      '{{range $p, $b := .NetworkSettings.Ports}}{{range $b}}{{.HostPort}}{{"\n"}}{{end}}{{end}}' $running
    # shellcheck disable=SC2086
    [[ -n "$managed" ]] && docker inspect --format \
      '{{range $p, $b := .HostConfig.PortBindings}}{{range $b}}{{.HostPort}}{{"\n"}}{{end}}{{end}}' $managed
  } 2>/dev/null | grep -E '^[0-9]+$' | sort -un
}

# True when something outside Docker is already listening on the port.
wvr_port_listening() {
  local out
  if wvr_have ss && out="$(ss -Hltn "sport = :$1" 2>/dev/null)"; then
    [[ -n "$out" ]]
    return
  fi
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# wvr_pick_port <start> <space separated ports to avoid>
wvr_pick_port() {
  local p="$1" avoid=" $2 " limit=$(( $1 + 200 ))
  (( limit > 65535 )) && limit=65535
  while (( p <= limit )); do
    if [[ "$avoid" != *" $p "* ]] && ! wvr_port_listening "$p"; then
      printf '%s\n' "$p"
      return 0
    fi
    p=$((p + 1))
  done
  wvr_err "no free host port found near $1"
  return 1
}

# wvr_plan_ports <lab id> [host port for the first port]
# Prints name, container port, host port, scheme, path for every port of the lab.
wvr_plan_ports() {
  local id="$1" want="${2:-}" used taken="" first=1 name cport host scheme path
  used="$(wvr_used_ports | tr '\n' ' ')"
  while IFS=$'\t' read -r name cport host scheme path; do
    if (( first )) && [[ -n "$want" ]]; then
      if [[ " $used " == *" $want "* ]] || wvr_port_listening "$want"; then
        wvr_err "host port $want is already in use"
        return 1
      fi
      host="$want"
    else
      host="$(wvr_pick_port "$host" "$used $taken")" || return 1
    fi
    first=0
    taken+=" $host"
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$cport" "$host" "$scheme" "$path"
  done < <(wvr_catalog_ports "$id")
}

# Where a browser on this machine reaches a lab published on <bind>.
wvr_display_host() {
  if [[ "$1" == "0.0.0.0" ]]; then printf '127.0.0.1\n'; else printf '%s\n' "$1"; fi
}

# wvr_port_url <bind> <host port> <scheme> <path>
wvr_port_url() {
  local h
  h="$(wvr_display_host "$1")"
  case "$3" in
    http|https) printf '%s://%s:%s%s\n' "$3" "$h" "$2" "$4" ;;
    *)          printf '%s://%s:%s\n' "$3" "$h" "$2" ;;
  esac
}

# wvr_up <lab id> <instance name> <bind address> [host port]
wvr_up() {
  local id="$1" name="$2" bind="$3" want="${4:-}"
  local type plan first url health_type health_path health pname host scheme path

  wvr_catalog_has "$id" || { wvr_err "unknown lab: $id (see 'webvuln-runner catalog')"; return 1; }
  wvr_valid_name "$name" || { wvr_err "invalid name '$name': use lowercase letters, digits, '-' or '_' (max 63)"; return 1; }
  wvr_valid_bind "$bind" || { wvr_err "invalid bind address: $bind"; return 1; }
  if [[ -n "$want" ]] && ! wvr_valid_port "$want"; then wvr_err "invalid port: $want"; return 1; fi
  if wvr_name_taken "$name"; then wvr_err "a container or Compose project named '$name' already exists"; return 1; fi

  type="$(wvr_catalog_get "$id" .type)"
  if [[ "$type" == "compose" ]] && ! wvr_have_compose; then
    wvr_err "lab '$id' needs the Docker Compose v2 plugin ('docker compose')"
    return 1
  fi

  plan="$(wvr_plan_ports "$id" "$want")" || return 1
  first="$(head -n1 <<<"$plan")"
  url="$(wvr_port_url "$bind" "$(cut -f3 <<<"$first")" "$(cut -f4 <<<"$first")" "$(cut -f5 <<<"$first")")"
  IFS=$'\t' read -r health_type health_path < <(wvr_catalog_health "$id")
  case "$health_type" in
    http|https) health="$health_type $health_type://$(wvr_display_host "$bind"):$(cut -f3 <<<"$first")$health_path" ;;
    *)          health="tcp $(wvr_display_host "$bind"):$(cut -f3 <<<"$first")" ;;
  esac

  if [[ "$type" == "compose" ]]; then
    wvr_up_compose "$id" "$name" "$bind" "$plan" "$url" "$health"
  else
    wvr_up_image "$id" "$name" "$bind" "$plan" "$url" "$health"
  fi || return 1

  wvr_clear_stopped "$name"
  wvr_info "Lab '$name' ($id) started."
  while IFS=$'\t' read -r pname _ host scheme path; do
    wvr_info "  $pname: $(wvr_port_url "$bind" "$host" "$scheme" "$path")"
  done <<<"$plan"
  if [[ "$bind" != 127.* ]]; then
    wvr_warn "'$name' is published on $bind and reachable from other machines. Only do this on an isolated network."
  fi
}

# Docker flags that limit what a lab container may do. Labs whose catalog entry sets
# "hardening": false (because a test showed the lab breaks) get none of them.
wvr_hardening_args() {
  local id="$1" mem cpus ncpu
  [[ "$(wvr_catalog_get "$id" 'if .hardening == false then "off" else "on" end')" == "on" ]] || return 0
  mem="$(wvr_catalog_get "$id" '.mem_limit_mb // ([512, ((.ram_mb // 256) * 2)] | max)')"
  cpus="$(wvr_catalog_get "$id" '.cpus // 2')"
  # --cpus may not exceed the CPUs Docker sees.
  ncpu="$(docker info --format '{{.NCPU}}' 2>/dev/null)"
  if [[ "$ncpu" =~ ^[0-9]+$ ]] && awk -v c="$cpus" -v n="$ncpu" 'BEGIN { exit !(c > n) }'; then cpus="$ncpu"; fi
  printf '%s\n' --security-opt no-new-privileges:true --pids-limit 1024 --memory "${mem}m" --cpus "$cpus"
}

# Each single-container lab gets its own bridge network, so labs cannot reach each other.
wvr_network_name() { printf 'wvr-%s\n' "$1"; }

wvr_rm_network() {
  local ids
  ids="$(docker network ls -q --filter "label=${WVR_LABEL_MANAGED}=true" --filter "label=${WVR_LABEL_INSTANCE}=$1")"
  # shellcheck disable=SC2086
  [[ -z "$ids" ]] || docker network rm $ids >/dev/null 2>&1
}

wvr_up_image() {
  local id="$1" name="$2" bind="$3" plan="$4" url="$5" health="$6"
  local image workdir cid cport host kv net created_net=0 created_cid="" err_out
  local -a args run_cmd hardening

  image="$(wvr_catalog_get "$id" .image)"
  net="$(wvr_network_name "$name")"
  if docker network inspect "$net" >/dev/null 2>&1; then
    wvr_err "a Docker network named '$net' already exists"
    return 1
  fi
  mapfile -t hardening < <(wvr_hardening_args "$id")
  args=(
    --name "$name"
    --label "${WVR_LABEL_MANAGED}=true"
    --label "${WVR_LABEL_LAB}=$id"
    --label "${WVR_LABEL_INSTANCE}=$name"
    --label "${WVR_LABEL_URL}=$url"
    --label "${WVR_LABEL_HEALTH}=$health"
    --network "$net"
    "${hardening[@]}"
  )
  while IFS=$'\t' read -r _ cport host _; do
    args+=(-p "$bind:$host:$cport")
  done <<<"$plan"
  while IFS= read -r kv; do
    [[ -n "$kv" ]] && args+=(-e "$kv")
  done < <(wvr_catalog_get "$id" '(.env // {}) | to_entries[] | "\(.key)=\(.value)"')
  workdir="$(wvr_catalog_get "$id" '.workdir // empty')"
  [[ -n "$workdir" ]] && args+=(-w "$workdir")
  mapfile -t run_cmd < <(wvr_catalog_get "$id" '(.command // [])[]')

  # shellcheck disable=SC2329 # invoked via trap on INT/TERM
  _wvr_cleanup_up_image() {
    trap - INT TERM
    [[ -n "$created_cid" ]] && docker rm -f "$created_cid" >/dev/null 2>&1
    (( created_net )) && wvr_rm_network "$name"
    return 1
  }
  trap '_wvr_cleanup_up_image; return 1 2>/dev/null || exit 1' INT TERM

  if ! docker image inspect "$image" >/dev/null 2>&1; then
    wvr_info "Pulling $image ..."
    if ! docker pull "$image"; then
      trap - INT TERM
      wvr_err "could not pull $image"
      return 1
    fi
  fi
  if ! docker network create \
    --label "${WVR_LABEL_MANAGED}=true" --label "${WVR_LABEL_LAB}=$id" --label "${WVR_LABEL_INSTANCE}=$name" \
    "$net" >/dev/null; then
    trap - INT TERM
    wvr_err "could not create network '$net'"
    return 1
  fi
  created_net=1
  if ! cid="$(docker create "${args[@]}" "$image" "${run_cmd[@]}")"; then
    trap - INT TERM
    wvr_err "could not create container '$name'"
    wvr_rm_network "$name"
    return 1
  fi
  created_cid="$cid"
  if ! err_out="$(docker start "$cid" 2>&1)"; then
    trap - INT TERM
    wvr_err "container '$name' was created but failed to start; removing it"
    if [[ -n "$err_out" ]] && grep -qi "port is already allocated\|address already in use" <<<"$err_out"; then
      wvr_err "port allocation conflict: host port is already bound by another process"
    fi
    docker rm -f "$cid" >/dev/null 2>&1
    wvr_rm_network "$name"
    return 1
  fi
  trap - INT TERM
}

wvr_up_compose() {
  local id="$1" name="$2" bind="$3" plan="$4" url="$5" health="$6"
  local file pname host var err_file
  local -a envs

  file="$WVR_HOME/$(wvr_catalog_get "$id" .compose)"
  envs=(
    "WVR_INSTANCE=$name" "WVR_LAB=$id" "WVR_BIND=$bind"
    "WVR_URL=$url" "WVR_HEALTH=$health"
  )
  while IFS=$'\t' read -r pname _ host _; do
    var="WVR_PORT_$(tr '[:lower:]' '[:upper:]' <<<"$pname")"
    envs+=("$var=$host")
  done <<<"$plan"

  # shellcheck disable=SC2329 # invoked via trap on INT/TERM
  _wvr_cleanup_up_compose() {
    trap - INT TERM
    env "${envs[@]}" docker compose -p "$name" -f "$file" down --remove-orphans >/dev/null 2>&1
    return 1
  }
  trap '_wvr_cleanup_up_compose; return 1 2>/dev/null || exit 1' INT TERM

  err_file="$(mktemp)"
  if ! env "${envs[@]}" docker compose -p "$name" -f "$file" up -d 2>"$err_file"; then
    trap - INT TERM
    wvr_err "docker compose failed for '$name'; cleaning up"
    if grep -qi "port is already allocated\|address already in use" "$err_file" 2>/dev/null; then
      wvr_err "port allocation conflict in Compose services: host port is already bound"
    fi
    rm -f "$err_file"
    env "${envs[@]}" docker compose -p "$name" -f "$file" down --remove-orphans >/dev/null 2>&1
    return 1
  fi
  rm -f "$err_file"
  trap - INT TERM
}

wvr_start() {
  local project ids
  wvr_require_instance "$1" || return 1
  wvr_clear_stopped "$1"
  project="$(wvr_instance_project "$1")"
  if [[ -n "$project" ]]; then
    docker compose -p "$project" start
  else
    ids="$(wvr_instance_ids "$1")"
    # shellcheck disable=SC2086
    docker start $ids >/dev/null
  fi
}

wvr_stop() {
  local project ids
  wvr_require_instance "$1" || return 1
  wvr_mark_stopped "$1"
  project="$(wvr_instance_project "$1")"
  if [[ -n "$project" ]]; then
    docker compose -p "$project" stop
  else
    ids="$(wvr_instance_ids "$1")"
    # shellcheck disable=SC2086
    docker stop $ids >/dev/null
  fi
}

# wvr_rm <name> [--volumes]
wvr_rm() {
  local name="$1" volumes="${2:-}" project ids
  wvr_require_instance "$name" || return 1
  project="$(wvr_instance_project "$name")"
  if [[ -n "$project" ]]; then
    if [[ "$volumes" == "--volumes" ]]; then
      docker compose -p "$project" down --remove-orphans --volumes
    else
      docker compose -p "$project" down --remove-orphans
    fi
  else
    ids="$(wvr_instance_ids "$name")"
    # shellcheck disable=SC2086
    if [[ "$volumes" == "--volumes" ]]; then docker rm -f -v $ids >/dev/null; else docker rm -f $ids >/dev/null; fi
    wvr_rm_network "$name"
  fi
  wvr_clear_stopped "$name"
}

# Bulk operations walk the managed instances only.
wvr_stop_all() {
  local name rc=0
  for name in $(wvr_instances | cut -f1); do
    if wvr_stop "$name" >/dev/null 2>&1; then wvr_info "stopped $name"; else wvr_err "could not stop $name"; rc=1; fi
  done
  return "$rc"
}

# wvr_rm_all [--volumes]
wvr_rm_all() {
  local name rc=0
  for name in $(wvr_instances | cut -f1); do
    if wvr_rm "$name" "${1:-}" >/dev/null 2>&1; then wvr_info "removed $name"; else wvr_err "could not remove $name"; rc=1; fi
  done
  return "$rc"
}

# CPU and memory of running managed containers (optionally of one instance).
wvr_stats() {
  local ids
  if [[ -n "${1:-}" ]]; then
    wvr_require_instance "$1" || return 1
    ids="$(wvr_ps_managed -q --filter status=running --filter "label=${WVR_LABEL_INSTANCE}=$1")"
  else
    ids="$(wvr_ps_managed -q --filter status=running)"
  fi
  if [[ -z "$ids" ]]; then
    wvr_info "No running labs."
    return 0
  fi
  # shellcheck disable=SC2086
  docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.PIDs}}' $ids
}

# wvr_logs <name> [lines]
wvr_logs() {
  local name="$1" lines="${2:-200}" project id
  wvr_require_instance "$name" || return 1
  project="$(wvr_instance_project "$name")"
  if [[ -n "$project" ]]; then
    docker compose -p "$project" logs --no-color --tail "$lines" 2>&1
  else
    for id in $(wvr_instance_ids "$name"); do
      docker logs --tail "$lines" "$id" 2>&1
    done
  fi
}

# wvr_probe "<type> <target>" — one readiness check.
# http/https: any HTTP answer below 500 counts as ready. tcp: the port accepts connections.
# Note: Docker's userland proxy accepts TCP connections on published loopback ports even
# before the app listens, so "tcp" is only a weak signal; prefer http checks where possible.
wvr_probe() {
  local type="${1%% *}" target="${1#* }" code
  case "$type" in
    http|https)
      code="$(curl -sk -o /dev/null --max-time 3 -w '%{http_code}' "$target" 2>/dev/null)"
      [[ "$code" =~ ^[1-4][0-9][0-9]$ ]]
      ;;
    tcp)
      (exec 3<>"/dev/tcp/${target%:*}/${target##*:}") 2>/dev/null
      ;;
    *) return 1 ;;
  esac
}

wvr_health_timeout() {
  local lab t
  lab="$(wvr_instance_label "$1" "$WVR_LABEL_LAB")"
  t="$(wvr_catalog_get "$lab" '.health_timeout // empty' 2>/dev/null)"
  printf '%s\n' "${t:-$WVR_HEALTH_TIMEOUT}"
}

# wvr_health_wait <name> [timeout] [--progress]
# With --progress, prints a percentage per second (for whiptail --gauge).
wvr_health_wait() {
  local name="$1" timeout="${2:-}" progress="${3:-}" health elapsed=0
  health="$(wvr_instance_label "$name" "$WVR_LABEL_HEALTH")"
  [[ -n "$health" ]] || return 1
  [[ -n "$timeout" ]] || timeout="$(wvr_health_timeout "$name")"
  while (( elapsed < timeout )); do
    if wvr_probe "$health"; then
      [[ -n "$progress" ]] && echo 100
      return 0
    fi
    [[ -n "$progress" ]] && echo $(( elapsed * 100 / timeout ))
    sleep 2
    elapsed=$((elapsed + 2))
  done
  return 1
}

wvr_status() {
  local name="$1" lab health state url line
  wvr_require_instance "$name" || return 1
  lab="$(wvr_instance_label "$name" "$WVR_LABEL_LAB")"
  health="$(wvr_instance_label "$name" "$WVR_LABEL_HEALTH")"
  line="$(wvr_instances | awk -F'\t' -v n="$name" '$1 == n')"
  state="$(cut -f3 <<<"$line")"
  url="$(cut -f4 <<<"$line")"
  wvr_info "Name:      $name"
  wvr_info "Lab:       $lab ($(wvr_catalog_get "$lab" .name 2>/dev/null))"
  wvr_info "Container: $state"
  if [[ "$state" == "stopped" || "$state" == "failed" ]]; then
    wvr_info "App:       not running"
  elif wvr_probe "$health"; then
    wvr_info "App:       ready"
  else
    wvr_info "App:       not responding yet (${health#* })"
  fi
  wvr_info "URL:       $url"
  wvr_info "Ports:"
  local id
  for id in $(wvr_instance_ids "$name"); do
    docker inspect --format \
      '{{$n := .Name}}{{range $p, $b := .NetworkSettings.Ports}}{{range $b}}  {{$n}} {{.HostIp}}:{{.HostPort}} -> {{$p}}{{"\n"}}{{end}}{{end}}' "$id"
  done | sed 's#  /#  #' | grep -v '^$'

  if [[ "$state" != "stopped" && "$state" != "failed" ]]; then
    wvr_info "Usage:"
    wvr_stats "$name" | sed 's/^/  /'
  fi

  # Explain failures: which container exited with which code, and its last log lines.
  if [[ "$state" == "failed" || "$state" == "unhealthy" || "$state" == "restarting" ]]; then
    for id in $(wvr_instance_ids "$name"); do
      local cname cstate code
      IFS=$'\t' read -r cname cstate code < <(docker inspect --format \
        '{{.Name}}{{"\t"}}{{.State.Status}}{{"\t"}}{{.State.ExitCode}}' "$id")
      [[ "$cstate" == "running" && "$state" != "unhealthy" ]] && continue
      wvr_info ""
      wvr_info "${cname#/}: $cstate (exit code $code). Last log lines:"
      docker logs --tail 20 "$id" 2>&1 | sed 's/^/  /'
    done
  fi
}
