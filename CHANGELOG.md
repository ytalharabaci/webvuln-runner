# Changelog

All notable changes to WebVuln-Runner. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).
The release workflow publishes the section of the tagged version as the GitHub release notes.

## [Unreleased]

## [2.3.0] - 2026-10-18

### Security
- Signal handling in `wvr_up`: partial containers and bridge networks are automatically cleaned up on SIGINT/SIGTERM (Ctrl+C), leaving no orphaned resources.
- Clear error diagnostics and automatic cleanup on host port bind collisions (`port is already allocated`).
- Added formal `SECURITY.md` establishing the project's vulnerability reporting process, threat model, and local isolation rules.

### Added
- **WebSocket GOAT** (`wsgoat`): Real-time WebSocket vulnerability training covering CSWSH, authentication bypass, and private messaging logic on port 8096.
- **VulnerableLightApp** (`vulnerablelightapp`): .NET / ASP.NET Core API security lab covering SQLi, command injection, SSRF, XXE, deserialization, and SIEM logging on port 8097.
- Catalog expanded to 30 labs across REST, GraphQL, gRPC, WebSocket, AI/MCP, and benchmark categories.
- Structured testing reports in `scripts/labs-smoke.sh`: `--report-json` and `--report-md` flags to generate verifiable reports with durations, readiness states, and failure diagnostics.
- Web catalog filters in `index.html`: Technology stack filter (Node.js, Java, Python, PHP, .NET, Go), lab type filter (Image / Compose), prominent Security Notice banner, and Troubleshooting & FAQ section.
- Open source community health files: `CONTRIBUTING.md`, GitHub issue templates (`bug_report.yml`, `lab_request.yml`, `config.yml`), and PR template.

## [2.2.1] - 2026-10-18

### Security
- Release tarballs carry a signed build provenance attestation; verify with `gh attestation verify <tarball> --repo yusufarbc/webvuln-runner`.

### Added
- Screenshots of the TUI in the README (step-by-step walkthrough) and on the web catalog.

### Changed
- README and web catalog present WebVuln-Runner as a TUI; commands are documented as a secondary way to use it. The README states the scope: it runs labs and never scans or modifies them.
- Vulnerability topics are grouped into 10 broader topics (`injection`, `xss-csrf`, `access-control`, `authentication`, `ssrf`, `files`, `api`, `secrets-config`, `dependencies`, `logic-llm`) instead of 24. The web catalog, the menu, the README and `catalog --topic` use the new topics.

## [2.2.0] - 2026-10-17

### Security
- Every single-container lab runs on its own Docker network; labs can no longer reach each other.
- Lab containers run with `no-new-privileges`, a process limit, a memory limit and a CPU limit.
- Every Compose service sets `no-new-privileges`; `scripts/check-compose-policy.sh` enforces the Compose rules in CI (labels, no `container_name`, no privileged mode, no host network or PID namespace, no Docker socket mounts, ports on `${WVR_BIND}`).

### Added
- Vulnerability catalog: every lab has topics (24 topics such as `sqli`, `ssrf`, `idor`, `jwt`, `llm-mcp`), a level, its license and the date it was last verified. `catalog --topic/--category/--level`, `topics`, "By topic" and "By level" in the menu, topic and level filters on the web catalog, and a "Labs by topic" table in the README.
- Lab states `failed`, `unhealthy`, `starting` and `restarting`; `status` explains failures with the exit code and the last log lines.
- `stop --all`, `rm --all --yes [--volumes]` and `stats`; stop-all and cleanup entries in the menu.
- `scripts/labs-smoke.sh` to start every lab for real; installer tests on six distributions in CI.
- This changelog; release notes are taken from it. README explains how to roll back to an earlier release.

## [2.1.0] - 2026-10-17

### Added
- Labs: OWASP WrongSecrets, BrokenCrystals, DjanGoat, OWASP Security Shepherd (28 labs).
- Warning that DVMCP's challenges target the MCP client that connects to it.

### Fixed
- Menus no longer draw items outside the dialog box: their width follows the terminal and long items are shortened. Lab descriptions are limited to 50 characters.

## [2.0.0] - 2026-10-17

First release of the rewritten tool.

### Security
- Labs publish on `127.0.0.1` by default; exposing one on the network is an explicit, warned opt-in.
- Only containers labelled `io.webvuln-runner.managed=true` are listed or touched; 1.x could stop or remove any container on the host.
- Installers download a tagged release and refuse to install unless its SHA-256 checksum matches.
- Root is no longer required, only access to the Docker daemon.

### Added
- Command line interface (`catalog`, `list`, `up`, `start`, `stop`, `status`, `logs`, `rm`, `validate`, `uninstall`) next to the menu.
- Readiness checks, logs and status; several labs (and several copies of one lab) side by side on free ports.
- JSON catalog with validation; Docker Compose labs: OWASP crAPI, NodeGoat, dvws-node, Snyk Goof, gRPC Goat, DVMCP (24 labs).
- Installer for Debian/Ubuntu/Kali, Fedora/RHEL/Rocky/AlmaLinux and Arch, and `uninstall`.
- Unit tests, integration tests, CI and a weekly image audit; README lab table and web catalog generated from the catalog.

### Fixed
- 1.x stopped the image name instead of the container and showed an empty name after creating a lab.
- Broken catalog entries: XVWA and Hackazon images Docker can no longer pull, the removed DVWS image, the wrong DSVPWA port, DVGA's missing `WEB_HOST`, the Benchmark start command.

[Unreleased]: https://github.com/yusufarbc/webvuln-runner/compare/v2.3.0...HEAD
[2.3.0]: https://github.com/yusufarbc/webvuln-runner/compare/v2.2.1...v2.3.0
[2.2.1]: https://github.com/yusufarbc/webvuln-runner/compare/v2.2.0...v2.2.1
[2.2.0]: https://github.com/yusufarbc/webvuln-runner/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/yusufarbc/webvuln-runner/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/yusufarbc/webvuln-runner/releases/tag/v2.0.0
