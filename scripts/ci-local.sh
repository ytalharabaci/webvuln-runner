#!/usr/bin/env bash
# Runs the same checks as .github/workflows/ci.yml on this machine.
# Needs bash, jq, curl, shellcheck, bats and a reachable Docker daemon with the Compose plugin.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

scripts=(src/webvuln-runner src/lib/*.sh installers/*.sh installers/*/*.sh scripts/*.sh tests/integration.sh tests/helpers/bin/docker)
failed=()
step() { local name="$1"; shift; echo "== $name"; "$@" || failed+=("$name"); }

syntax() { local f; for f in "${scripts[@]}"; do bash -n "$f" || return 1; done; }
policy_rejects_violations() { ! ./scripts/check-compose-policy.sh tests/fixtures/policy-violations.yml >/dev/null; }

step "bash -n"       syntax
step "shellcheck"    shellcheck -x "${scripts[@]}"
step "catalog"       ./src/webvuln-runner validate
step "compose policy" ./scripts/check-compose-policy.sh
step "policy rejects violations" policy_rejects_violations
step "readme table"  ./scripts/gen-readme-table.sh --check
step "unit tests"    bats tests/unit
step "integration"   bash tests/integration.sh

echo
if (( ${#failed[@]} )); then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "all CI checks passed"
