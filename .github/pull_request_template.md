## Description
<!-- Provide a clear description of the change, motivation, and context. -->

## Type of Change
- [ ] New lab added to catalog
- [ ] Bug fix in runner lifecycle or CLI
- [ ] Security / hardening improvement
- [ ] Documentation / website enhancement
- [ ] Test suite improvement

## Pre-Submit Checklist
- [ ] Bash syntax is valid (`bash -n`)
- [ ] ShellCheck passes without warnings (`shellcheck -x ...`)
- [ ] Catalog schema validates (`./src/webvuln-runner validate`)
- [ ] Compose policies pass if Compose files were touched (`./scripts/check-compose-policy.sh`)
- [ ] README lab table was updated if catalog changed (`./scripts/gen-readme-table.sh`)
- [ ] All bats unit tests pass (`bats tests/unit`)
- [ ] Tested locally with Docker (`tests/integration.sh` or `scripts/labs-smoke.sh <lab>`)

