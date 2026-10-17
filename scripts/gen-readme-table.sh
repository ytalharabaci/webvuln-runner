#!/usr/bin/env bash
# Regenerates the lab table in README.md from src/catalog.json.
# Usage: scripts/gen-readme-table.sh [--check]
#   --check  exit 1 if README.md is out of date instead of rewriting it
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$ROOT/README.md"
CATALOG="$ROOT/src/catalog.json"
START='<!-- catalog:start -->'
END='<!-- catalog:end -->'

table="$(jq -r '
  "| Lab | ID | Category | Stack | Type | Default port(s) |",
  "|---|---|---|---|---|---|",
  (.labs[] |
    "| [\(.name)](\(.source)) | `\(.id)` | \(.category) | \(.stack // [] | join(", ")) | \(.type) | " +
    ( if (.ports | length) > 3
      then "\(.ports[0].host), \(.ports[1].host)-\(.ports[-1].host)"
      else (.ports | map(.host | tostring) | join(", ")) end ) + " |"),
  "",
  "\(.labs | length) labs. Generated from `src/catalog.json` by `scripts/gen-readme-table.sh`."
' "$CATALOG")"

grep -qF "$START" "$README" && grep -qF "$END" "$README" || {
  echo "README.md is missing the $START / $END markers" >&2
  exit 1
}

new="$(awk -v start="$START" -v end="$END" -v table="$table" '
  $0 == start { print; print table; skip = 1; next }
  $0 == end   { skip = 0 }
  !skip
' "$README")"

if [[ "${1:-}" == "--check" ]]; then
  if [[ "$new" != "$(cat "$README")" ]]; then
    echo "README.md lab table is out of date; run scripts/gen-readme-table.sh" >&2
    exit 1
  fi
  echo "README.md lab table is up to date"
else
  printf '%s\n' "$new" >"$README"
  echo "README.md updated"
fi
