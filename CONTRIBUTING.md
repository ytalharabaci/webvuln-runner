# Contributing to WebVuln-Runner

Thank you for your interest in contributing to **WebVuln-Runner**! This project aims to provide a safe, reliable, and user-friendly local lab manager for deliberately vulnerable web applications, APIs, and benchmarks.

---

## Code of Conduct & Principles

- **Security First:** Never weaken default isolation rules (`127.0.0.1` binding, `no-new-privileges`, process/memory limits).
- **Single Source of Truth:** `src/catalog.json` drives the TUI, CLI, README tables, and web catalog. Avoid duplicating catalog data elsewhere.
- **Strict Management Boundary:** WebVuln-Runner must only interact with resources labelled `io.webvuln-runner.managed=true`. Never touch external containers or networks.

---

## Prerequisites for Development

To develop and run the full test suite locally, ensure you have:
- **Bash** (v4.4+)
- **Docker** with daemon running and Docker Compose v2 plugin (`docker compose`)
- **jq** (v1.6+)
- **ShellCheck** (v0.8+)
- **Bats** (`bats-core`)
- **curl**

---

## Adding a New Lab

Before submitting a new lab, verify that:
1. The upstream image or project has a clear open-source license.
2. The image uses an immutable version tag (avoid `latest` unless upstream publishes no version tags).
3. The lab does not introduce security risks to the host (no privileged mode, no host socket mounts).

### 1. Update `src/catalog.json`
Add an entry to `.labs` in `src/catalog.json`:

```json
{
  "id": "example-lab",
  "name": "Example Lab",
  "description": "Short explanation of vulnerabilities taught (max 50 chars)",
  "category": "web",
  "stack": ["Node.js", "Express"],
  "type": "image",
  "image": "upstream/example-lab:1.2.0",
  "ports": [
    { "name": "web", "container": 3000, "host": 8095, "scheme": "http", "path": "/" }
  ],
  "ram_mb": 512,
  "credentials": "admin / admin",
  "topics": ["injection", "xss-csrf"],
  "level": "beginner",
  "license": "Apache-2.0",
  "verified": "2026-10-18",
  "source": "https://github.com/upstream/example-lab"
}
```

#### Fields Reference:
- `category`: Must be one of `web`, `rest-api`, `graphql`, `grpc`, `ai-mcp`, `benchmark`, `training`.
- `topics`: Must come from the standard vocabulary: `injection`, `xss-csrf`, `access-control`, `authentication`, `ssrf`, `files`, `api`, `secrets-config`, `dependencies`, `logic-llm`.
- `level`: `beginner`, `intermediate`, or `advanced`.
- `ports`: First port is the primary service used for readiness checks. Default `host` port must be unique across the catalog.

### 2. Multi-Service Labs (Docker Compose)
If the lab requires multiple services (e.g. database + web app):
1. Place the Compose file under `src/compose/<lab-id>/compose.yml`.
2. Ensure every service adheres to the Compose Security Policy:
   - Inherits `x-wvr-labels` with `io.webvuln-runner.managed=true`, `io.webvuln-runner.lab`, `io.webvuln-runner.instance`.
   - Sets `security_opt: ["no-new-privileges:true"]`.
   - Binds ports using `${WVR_BIND:-127.0.0.1}:${WVR_PORT_<NAME>:-<default>}:<container-port>`.
   - Does **not** set fixed `container_name` (so multiple instances can run).
   - Does **not** mount `/var/run/docker.sock` or host root filesystems.
   - Does **not** use `privileged: true` or `network_mode: host`.
3. Check policy compliance:
   ```bash
   scripts/check-compose-policy.sh
   ```

### 3. Regenerate README Table & Validate
Run:
```bash
./src/webvuln-runner validate
./scripts/gen-readme-table.sh
```

### 4. Smoke Test the Lab
Test starting, readiness check, and removal:
```bash
./scripts/labs-smoke.sh <lab-id>
```

---

## Running Quality Checks & Tests

Before opening a pull request, run the local CI test suite:

```bash
# Run all local CI checks in one go:
./scripts/ci-local.sh
```

Or run individual suites:
- **Syntax check:** `bash -n src/webvuln-runner src/lib/*.sh scripts/*.sh tests/*.sh`
- **ShellCheck:** `shellcheck -x src/webvuln-runner src/lib/*.sh scripts/*.sh`
- **Catalog schema & policy:** `./src/webvuln-runner validate && ./scripts/check-compose-policy.sh`
- **Unit tests:** `bats tests/unit`
- **Docker integration test:** `bash tests/integration.sh`

---

## Pull Request Guidelines

1. Fork the repository and create a feature branch (`git checkout -b feature/add-new-lab`).
2. Keep commits concise and informative.
3. Ensure all tests and linters pass (`./scripts/ci-local.sh`).
4. Submit a Pull Request targeting the `main` branch with a clear description of changes and test results.

