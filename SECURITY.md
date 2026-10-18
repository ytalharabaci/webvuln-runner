# Security Policy

## Supported Versions

| Version | Supported | Notes |
|---------|-----------|-------|
| 2.2.x   | :white_check_mark: | Current active release line |
| < 2.2   | :x: | Legacy releases; please upgrade to 2.2+ |

---

## Security Model & Scope

WebVuln-Runner is a local manager for **deliberately vulnerable** web applications, APIs, and benchmarks.

### Deliberately Vulnerable Lab Software
The targets started by this tool (such as OWASP Juice Shop, DVWA, WebGoat, crAPI, etc.) are **intentionally vulnerable by design**.
- Do **not** report vulnerabilities in the target lab applications (e.g. SQL injection in DVWA or IDOR in crAPI) to WebVuln-Runner.
- Report upstream lab issues directly to the respective upstream project repositories.

### What Is in Scope for WebVuln-Runner
Security reports concerning the **runner itself** are welcomed and treated with high priority. Examples include:
- Unintended host filesystem, network, or PID namespace access.
- Accidental exposure on non-loopback interfaces when loopback binding (`127.0.0.1`) was requested.
- Destruction or mutation of Docker containers, images, volumes, or networks **not** labelled `io.webvuln-runner.managed=true`.
- Command injection or arbitrary code execution via catalog parameters (`src/catalog.json`) or CLI inputs.
- Supply chain weaknesses or provenance tampering in the installer (`installers/install.sh`) or release archives.

---

## Operational Safety Guidelines for Users

1. **Host Isolation:** Docker isolates processes, but a container boundary is not an impenetrable sandbox. **Never run WebVuln-Runner on production servers or hosts storing sensitive data.**
2. **Loopback by Default:** All labs bind to `127.0.0.1` by default. Do not use `--bind 0.0.0.0` or expose ports to external networks unless working inside a dedicated, isolated test network.
3. **Daemon Privileges:** Running Docker commands requires access to the Docker daemon, which is equivalent to root access on the host. Be conscious of what commands and scripts you run with daemon access.
4. **AI & MCP Lab Cautions:** Certain targets (e.g. `dvmcp`) test the security of the connecting AI client (prompt injection, tool poisoning, token theft). Connect to them only using throwaway test clients with no access to production tokens or sensitive local files.

---

## Reporting a Vulnerability

If you discover a security vulnerability in WebVuln-Runner:

1. **Do not** open a public GitHub issue.
2. Please use **GitHub Private Vulnerability Reporting** via the [Security Advisories tab](https://github.com/yusufarbc/webvuln-runner/security/advisories/new) of this repository.
3. Alternatively, report by emailing the maintainer directly at the contact address listed on their GitHub profile ([@yusufarbc](https://github.com/yusufarbc)).

### What to Include
- Detailed description of the vulnerability.
- Step-by-step reproduction instructions or a minimal Proof of Concept (PoC).
- Potential impact and affected platforms or configurations.
- Any suggested fix or remediation if known.

### Response Timeline
- We will acknowledge receipt of your report within **48 hours**.
- We will provide regular updates on triage, remediation, and release planning.
- Once fixed, a security release will be published along with appropriate credit to the reporter.

