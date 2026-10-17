# shellcheck shell=bash
# Catalog access and validation. The catalog is src/catalog.json; see README "Adding a lab".

WVR_CATEGORIES='["web","rest-api","graphql","grpc","ai-mcp","benchmark","training"]'
WVR_LEVELS='["beginner","intermediate","advanced"]'
# What a lab lets you practise. Keep in sync with README "Adding a lab" and index.html.
# injection: SQL/NoSQL, OS command, template (SSTI), XXE   xss-csrf: XSS, CSRF
# access-control: IDOR/BOLA, authorization                 authentication: login, sessions, JWT
# files: path traversal, file upload                       api: REST API Top 10, GraphQL, gRPC
# secrets-config: secrets, misconfiguration, crypto        dependencies: vulnerable components, deserialization
# logic-llm: business logic, LLM/MCP
WVR_TOPICS='["injection","xss-csrf","access-control","authentication","ssrf",
  "files","api","secrets-config","dependencies","logic-llm"]'
# Labs not re-verified (scripts/labs-smoke.sh --update-verified) for this long get a warning.
WVR_VERIFIED_MAX_DAYS=180

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
  wvr_catalog_list_filtered "" "" "" | cut -f1-5
}

# wvr_catalog_list_filtered <topic> <category> <level>   (empty = any; filters combine)
# One line per matching lab: id, name, category, type, description, level, topics (comma separated)
wvr_catalog_list_filtered() {
  wvr_cjq --arg t "$1" --arg c "$2" --arg l "$3" '
    .labs[]
    | select($t == "" or ((.topics // []) | index($t)) != null)
    | select($c == "" or .category == $c)
    | select($l == "" or .level == $l)
    | [.id, .name, .category, .type, .description, (.level // ""), ((.topics // []) | join(","))] | @tsv'
}

# One line per topic that at least one lab covers: topic, number of labs (tab separated)
wvr_catalog_topics() {
  wvr_cjq --argjson all "$WVR_TOPICS" '
    [.labs[].topics // [] | .[]] as $used
    | $all[] | . as $t | ($used | map(select(. == $t)) | length) as $n
    | select($n > 0) | [$t, $n] | @tsv'
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

  problems="$(jq -r --argjson cats "$WVR_CATEGORIES" --argjson topics "$WVR_TOPICS" --argjson levels "$WVR_LEVELS" '
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
            ( if (.topics | type) != "array" or (.topics | length) == 0 then lab_err("needs a non-empty topics list")
              else (.topics[] | select(. as $t | $topics | index($t) | not) | . as $t | "unknown topic: \($t)") as $m | lab_err($m) end ),
            ( if (.level as $l | $levels | index($l)) == null then lab_err("level must be one of \($levels | join(", "))") else empty end ),
            ( if (.license | type) != "string" or .license == "" then lab_err("missing license (SPDX id, or \"unknown\")") else empty end ),
            ( if (.verified | type) != "string" or (.verified | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") | not)
              then lab_err("verified must be a YYYY-MM-DD date") else empty end ),
            ( if .hardening != null and (.hardening | type) != "boolean" then lab_err("hardening must be true or false") else empty end ),
            ( if .mem_limit_mb != null and ((.mem_limit_mb | type) != "number" or .mem_limit_mb < 64)
              then lab_err("mem_limit_mb must be a number >= 64") else empty end ),
            ( if .cpus != null and ((.cpus | type) != "number" or .cpus <= 0) then lab_err("cpus must be a positive number") else empty end ),
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

  # Not an error: old "verified" dates only mean nobody re-ran the smoke test lately.
  local stale
  stale="$(jq -r --argjson days "$WVR_VERIFIED_MAX_DAYS" '
    (now - $days * 86400) as $limit
    | .labs[] | select((.verified + "T00:00:00Z" | fromdateiso8601) < $limit) | "\(.id) (\(.verified))"' "$file" 2>/dev/null)"
  if [[ -n "$stale" ]]; then
    wvr_warn "not verified in the last $WVR_VERIFIED_MAX_DAYS days (run scripts/labs-smoke.sh --update-verified): $(tr '\n' ' ' <<<"$stale")"
  fi
}
