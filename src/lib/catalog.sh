# shellcheck shell=bash
# Catalog access and validation. The catalog is src/catalog.json; see README "Adding a lab".

WVR_CATEGORIES='["web","rest-api","graphql","grpc","ai-mcp","benchmark","training"]'

wvr_catalog_init() {
  WVR_CATALOG="${WVR_CATALOG:-$WVR_HOME/catalog.json}"
  [[ -r "$WVR_CATALOG" ]] || { wvr_err "catalog not found: $WVR_CATALOG"; return 1; }
}

wvr_cjq() { jq -r "$@" "$WVR_CATALOG"; }

wvr_catalog_has() {
  [[ -n "$(wvr_cjq --arg id "$1" '.labs[] | select(.id == $id) | .id')" ]]
}

# wvr_catalog_get <id> <jq filter applied to the lab object>
wvr_catalog_get() {
  wvr_cjq --arg id "$1" ".labs[] | select(.id == \$id) | $2"
}

# One line per lab: id, name, category, type, description (tab separated)
wvr_catalog_list() {
  wvr_cjq '.labs[] | [.id, .name, .category, .type, .description] | @tsv'
}

# One line per port of a lab: name, container port, default host port, scheme, path
wvr_catalog_ports() {
  wvr_catalog_get "$1" '.ports[] | [.name, (.container // 0), .host, (.scheme // "http"), (.path // "/")] | @tsv'
}

# Health check of a lab: type and path. Defaults to the first port's scheme and path.
wvr_catalog_health() {
  wvr_catalog_get "$1" '
    (.ports[0].scheme // "http") as $s
    | [ (.health.type // (if $s == "http" or $s == "https" then $s else "tcp" end)),
        (.health.path // .ports[0].path // "/") ] | @tsv'
}

# Prints one problem per line and returns 1 when the catalog is invalid.
wvr_catalog_validate() {
  local file="${1:-$WVR_CATALOG}" problems
  if ! jq empty "$file" 2>/dev/null; then
    wvr_err "$file: not valid JSON"
    return 1
  fi

  problems="$(jq -r --argjson cats "$WVR_CATEGORIES" '
    def lab_err($m): "\(.id // "<no id>"): \($m)";
    def is_port: type == "number" and . == floor and . >= 1 and . <= 65535;

    if (type != "object") or ((.labs | type) != "array") then
      "catalog: top level must be an object with a \"labs\" array"
    elif (.labs | length) == 0 then
      "catalog: no labs defined"
    else
      .labs as $labs
      | ( [$labs[] | .id | strings] | group_by(.) | map(select(length > 1) | "duplicate id: \(.[0])") | .[] ),
        ( [$labs[] | . as $l | (.ports // [])[] | {host, id: $l.id}]
          | group_by(.host) | map(select(length > 1))
          | .[] | "host port \(.[0].host) is the default of more than one port: \(map(.id) | unique | join(", "))" ),
        ( $labs[] |
            ( if (.id | type) != "string" or (.id | test("^[a-z0-9][a-z0-9-]*$") | not)
              then lab_err("id must match ^[a-z0-9][a-z0-9-]*$") else empty end ),
            ( if (.name | type) != "string" or .name == "" then lab_err("missing name") else empty end ),
            ( if (.description | type) != "string" or .description == "" then lab_err("missing description")
              elif (.description | length) > 50 then lab_err("description must be at most 50 characters (it is shown in the TUI menu)")
              else empty end ),
            ( if (.category as $c | $cats | index($c)) == null
              then lab_err("category must be one of \($cats | join(", "))") else empty end ),
            ( if .type == "image" then
                ( if (.image | type) != "string" or (.image | test("^[a-z0-9][a-z0-9._/-]*:[A-Za-z0-9._-]+$") | not)
                  then lab_err("image must be \"repository:tag\"") else empty end )
              elif .type == "compose" then
                ( if (.compose | type) != "string" or (.compose | test("^compose/[a-z0-9-]+/compose\\.ya?ml$") | not)
                  then lab_err("compose must be \"compose/<id>/compose.yml\"") else empty end )
              else lab_err("type must be \"image\" or \"compose\"") end ),
            ( if (.ports | type) != "array" or (.ports | length) == 0 then lab_err("needs at least one port")
              else
                ( . as $l | [.ports[].name] | group_by(.) | map(select(length > 1) | .[0])
                  | .[] | . as $n | $l | lab_err("duplicate port name: \($n)") ),
                ( . as $l | .ports[] |
                  ( if (.name | type) != "string" or (.name | test("^[a-z][a-z0-9]*$") | not)
                    then ($l | lab_err("port name must match ^[a-z][a-z0-9]*$")) else empty end ),
                  ( if (.host | is_port | not) then ($l | lab_err("port \(.name): host must be 1-65535")) else empty end ),
                  ( if $l.type == "image" and (.container | is_port | not)
                    then ($l | lab_err("port \(.name): container must be 1-65535")) else empty end ),
                  ( if ((.scheme // "http") | IN("http", "https", "tcp", "grpc") | not)
                    then ($l | lab_err("port \(.name): scheme must be http, https, tcp or grpc")) else empty end ) )
              end ),
            ( if .health != null and ((.health.type // "http") | IN("http", "https", "tcp") | not)
              then lab_err("health.type must be http, https or tcp") else empty end ),
            ( if .env != null and (.env | type) != "object" then lab_err("env must be an object") else empty end ),
            ( if .command != null and ((.command | type) != "array" or (.command | all(type == "string") | not))
              then lab_err("command must be an array of strings") else empty end )
        )
    end' "$file")"

  # Compose files are resolved relative to the catalog.
  local dir rel
  dir="$(dirname "$file")"
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    [[ -f "$dir/$rel" ]] || problems+="${problems:+$'\n'}compose file missing: $rel"
  done < <(jq -r '.labs[]? | select(.type == "compose") | .compose | strings' "$file")

  if [[ -n "$problems" ]]; then
    printf '%s\n' "$problems" >&2
    return 1
  fi
}
