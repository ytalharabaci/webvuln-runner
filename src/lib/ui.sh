# shellcheck shell=bash
# Whiptail TUI. All Docker work is delegated to docker.sh.

WVR_TUI_BIND="$WVR_BIND"

# whiptail writes the selection to stderr; swap it onto stdout.
wvr_wt() {
  whiptail --backtitle "WebVuln-Runner $WVR_VERSION   |   new labs bind to: $WVR_TUI_BIND" "$@" 3>&1 1>&2 2>&3
}

wvr_msg() { wvr_wt --title "${2:-WebVuln-Runner}" --msgbox "$1" 16 78; }

wvr_textbox() {
  whiptail --backtitle "WebVuln-Runner $WVR_VERSION" --title "$2" --scrolltext --textbox "$1" 24 110
}

wvr_pause() { read -r -p "Press Enter to return to the menu... " _; }

# Dialog width that fits the terminal (whiptail draws long items outside the box otherwise).
wvr_tui_width() {
  local cols
  cols="$(tput cols 2>/dev/null || echo 80)"
  [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
  cols=$(( cols - 4 ))
  (( cols > 100 )) && cols=100
  (( cols < 50 )) && cols=50
  printf '%s\n' "$cols"
}

# wvr_fit <text> <max length> — shortens text with "..." so it fits.
wvr_fit() {
  if (( ${#1} > $2 )); then printf '%s...\n' "${1:0:$(( $2 - 3 ))}"; else printf '%s\n' "$1"; fi
}

wvr_tui_main() {
  local choice name lab state url width rows tagw
  local -a items
  while true; do
    width="$(wvr_tui_width)"
    rows="$(wvr_instances)"
    tagw="$(awk -F'\t' 'length($1) > m { m = length($1) } END { print (m > 5 ? m : 5) }' <<<"$rows")"
    items=()
    while IFS=$'\t' read -r name lab state url; do
      [[ -z "$name" ]] && continue
      items+=("$name" "$(wvr_fit "$(printf '%-9s %-15s %s' "$state" "$lab" "$url")" $(( width - tagw - 10 )))")
    done <<<"$rows"
    items+=(">add" "Add a new lab from the catalog")
    if [[ -n "$rows" ]]; then
      items+=(">stopall" "Stop all labs")
      items+=(">cleanup" "Remove all labs...")
    fi
    items+=(">bind" "$(wvr_fit "Where new labs listen (now $WVR_TUI_BIND)" $(( width - tagw - 10 )))")
    choice="$(wvr_wt --title "Your labs" --ok-button "Select" --cancel-button "Quit" \
      --menu "Select a lab to manage it, or add a new one." 22 "$width" 14 "${items[@]}")" || return 0
    case "$choice" in
      ">add")     wvr_tui_add ;;
      ">bind")    wvr_tui_bind ;;
      ">stopall") wvr_msg "$(wvr_stop_all 2>&1)" "Stop all labs" ;;
      ">cleanup") wvr_tui_cleanup ;;
      *)       wvr_tui_instance "$choice" ;;
    esac
  done
}

wvr_tui_add() {
  local id cat type desc note name plan first port summary out width tagw
  local -a items
  width="$(wvr_tui_width)"
  tagw="$(wvr_cjq '[.labs[].id | length] | max')"
  while IFS=$'\t' read -r id _ cat type desc; do
    note=""
    if [[ "$type" == "compose" ]] && ! wvr_have_compose; then note=" (needs compose)"; fi
    items+=("$id" "$(wvr_fit "[$cat] $desc$note" $(( width - tagw - 10 )))")
  done < <(wvr_catalog_list)

  id="$(wvr_wt --title "Add a lab" --menu "Choose a lab:" 22 "$width" 14 "${items[@]}")" || return 0
  if [[ "$(wvr_catalog_get "$id" .type)" == "compose" ]] && ! wvr_have_compose; then
    wvr_msg "'$id' consists of several containers and needs the Docker Compose v2 plugin ('docker compose').\n\nInstall it and try again." "Docker Compose required"
    return 0
  fi

  name="$(wvr_wt --title "Add $id" --inputbox \
    "Name for this lab (lowercase letters, digits, '-' and '_'):" 10 72 "$(wvr_default_name "$id")")" || return 0
  if ! wvr_valid_name "$name"; then
    wvr_msg "'$name' is not a valid name.\n\nUse lowercase letters, digits, '-' or '_', starting with a letter or digit." "Invalid name"
    return 0
  fi
  if wvr_name_taken "$name"; then
    wvr_msg "A container or Compose project named '$name' already exists." "Name in use"
    return 0
  fi

  if ! plan="$(wvr_plan_ports "$id" 2>&1)"; then
    wvr_msg "$plan" "No free port"
    return 0
  fi
  first="$(head -n1 <<<"$plan")"
  port="$(wvr_wt --title "Add $id" --inputbox \
    "Host port for '$(cut -f1 <<<"$first")' (container port $(cut -f2 <<<"$first")).\nA free port has been suggested:" \
    11 72 "$(cut -f3 <<<"$first")")" || return 0
  if ! wvr_valid_port "$port"; then
    wvr_msg "'$port' is not a valid port number." "Invalid port"
    return 0
  fi

  summary="Lab:   $(wvr_catalog_get "$id" .name)\nName:  $name\nBind:  $WVR_TUI_BIND\nPort:  $port"
  if (( $(wc -l <<<"$plan") > 1 )); then
    summary+="\n       (+ $(( $(wc -l <<<"$plan") - 1 )) more ports, picked automatically)"
  fi
  summary+="\nRAM:   ~$(wvr_catalog_get "$id" '.ram_mb // "?"') MB\n\nCreate and start it now?"
  wvr_wt --title "Add $id" --yesno "$summary" 16 72 || return 0

  clear
  if ! wvr_up "$id" "$name" "$WVR_TUI_BIND" "$port"; then
    wvr_pause
    return 0
  fi
  wvr_tui_wait "$name"
  out="$(wvr_catalog_get "$id" '[.credentials, .notes] | map(select(. != null)) | join("\n")')"
  [[ -n "$out" ]] && wvr_msg "$out" "Notes for $id"
  return 0
}

wvr_tui_wait() {
  local name="$1" url
  url="$(wvr_instance_label "$name" "$WVR_LABEL_URL")"
  if wvr_health_wait "$name" "" --progress |
    whiptail --backtitle "WebVuln-Runner $WVR_VERSION" --gauge "Waiting for '$name' to answer..." 8 78 0; then
    wvr_msg "'$name' is ready.\n\nOpen in your browser:\n  $url" "Lab ready"
  else
    wvr_msg "'$name' is running but did not answer in time.\n\nSome labs need several minutes on their first start. Use 'Status' or 'Logs' to check on it.\n\nURL: $url" "Still starting"
  fi
}

wvr_tui_cleanup() {
  local count vol=""
  count="$(wvr_instances | wc -l)"
  wvr_wt --title "Remove all labs" --defaultno --yesno \
    "Stop and remove all $count lab(s) created by WebVuln-Runner?\n\nOther containers on this host are not touched." 11 70 || return 0
  wvr_wt --title "Remove all labs" --defaultno --yesno \
    "Are you sure? This cannot be undone." 9 60 || return 0
  if wvr_wt --title "Remove all labs" --defaultno --yesno \
    "Also delete their data volumes?\n\nChoose 'No' to keep them." 11 60; then vol="--volumes"; fi
  wvr_msg "$(wvr_rm_all "$vol" 2>&1)" "Remove all labs"
}

wvr_tui_bind() {
  local choice
  choice="$(wvr_wt --title "Bind address" --menu "Where should NEW labs be published?" 14 80 2 \
    "127.0.0.1" "This machine only (recommended)" \
    "0.0.0.0"   "All interfaces - reachable from your network")" || return 0
  if [[ "$choice" == "0.0.0.0" ]]; then
    wvr_wt --title "Warning" --defaultno --yesno \
      "These applications are intentionally vulnerable.\n\nPublishing them on all interfaces lets anyone who can reach this machine attack them - and, through them, possibly this host.\n\nOnly do this on an isolated lab network. Continue?" 15 76 || return 0
  fi
  WVR_TUI_BIND="$choice"
}

wvr_tui_instance() {
  local name="$1" action line lab state url out tmp vol
  while true; do
    wvr_instance_exists "$name" || return 0
    line="$(wvr_instances | awk -F'\t' -v n="$name" '$1 == n')"
    lab="$(cut -f2 <<<"$line")"; state="$(cut -f3 <<<"$line")"; url="$(cut -f4 <<<"$line")"
    action="$(wvr_wt --title "$name" --ok-button "Select" --cancel-button "Back" \
      --menu "Lab:   $lab\nState: $state\nURL:   $url" 18 80 6 \
      start  "Start the lab" \
      stop   "Stop the lab" \
      status "Show readiness and ports" \
      logs   "Show recent logs" \
      remove "Remove the lab")" || return 0
    case "$action" in
      start)
        if out="$(wvr_start "$name" 2>&1)"; then wvr_tui_wait "$name"; else wvr_msg "Could not start '$name':\n\n$out" "Error"; fi ;;
      stop)
        if out="$(wvr_stop "$name" 2>&1)"; then wvr_msg "'$name' stopped."; else wvr_msg "Could not stop '$name':\n\n$out" "Error"; fi ;;
      status)
        wvr_wt --title "$name - status" --msgbox "$(wvr_status "$name" 2>&1)" 22 100 ;;
      logs)
        # Scrollable: Tab moves to the Ok button.
        tmp="$(mktemp)"
        wvr_logs "$name" 200 >"$tmp" 2>&1
        [[ -s "$tmp" ]] || echo "(no log output yet)" >"$tmp"
        wvr_textbox "$tmp" "$name - logs (arrows scroll, Tab then Enter to close)"
        rm -f "$tmp" ;;
      remove)
        wvr_wt --title "Remove $name" --defaultno --yesno "Stop and remove '$name'?" 10 60 || continue
        vol=""
        if wvr_wt --title "Remove $name" --defaultno --yesno \
          "Also delete its data volumes?\n\nChoose 'No' to keep them." 11 60; then vol="--volumes"; fi
        if out="$(wvr_rm "$name" ${vol:+"$vol"} 2>&1)"; then
          wvr_msg "'$name' removed."
          return 0
        fi
        wvr_msg "Could not remove '$name':\n\n$out" "Error" ;;
    esac
  done
}
