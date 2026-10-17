<div align="center">

<img src="assets/logo.png" alt="WebVuln-Runner Logo" width="400"/>

# WebVuln-Runner

[![CI](https://github.com/yusufarbc/webvuln-runner/actions/workflows/ci.yml/badge.svg)](https://github.com/yusufarbc/webvuln-runner/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/yusufarbc/webvuln-runner?style=flat-square)](https://github.com/yusufarbc/webvuln-runner/releases)
[![Stars](https://img.shields.io/github/stars/yusufarbc/webvuln-runner?style=flat-square)](https://github.com/yusufarbc/webvuln-runner/stargazers)
[![Issues](https://img.shields.io/github/issues/yusufarbc/webvuln-runner?style=flat-square)](https://github.com/yusufarbc/webvuln-runner/issues)
[![License](https://img.shields.io/github/license/yusufarbc/webvuln-runner?style=flat-square)](LICENSE)

Start deliberately vulnerable web apps, APIs and benchmark targets in Docker — from a terminal menu or one command — published on `127.0.0.1` by default.

</div>

---

## Table of Contents
- [Features](#features)
- [Safety model](#safety-model)
- [Quick start](#quick-start)
- [Usage](#usage)
- [Supported labs](#supported-labs)
- [Installation](#installation)
- [Adding a lab](#adding-a-lab)
- [Development and tests](#development-and-tests)
- [Web catalog](#web-catalog)
- [Roadmap](#roadmap)
- [Disclaimer](#disclaimer)
- [License](#license)

## Features
- **Lab manager, not a launcher:** create, start, stop, inspect, view logs and remove labs; several labs (and several copies of one lab) run side by side, each on its own port.
- **Safe defaults:** labs listen on `127.0.0.1` only; exposing one to your network is an explicit, warned opt-in.
- **Only touches its own containers:** everything WebVuln-Runner creates is labelled `io.webvuln-runner.managed=true`; nothing else on the host is listed, stopped or removed.
- **Readiness checks:** the container being "running" is not the same as the app being ready — WebVuln-Runner waits until the app answers and tells you when it does.
- **Single-container and Docker Compose labs:** multi-service labs such as OWASP crAPI and NodeGoat start as one unit.
- **Beyond classic web labs:** REST and GraphQL APIs, Node.js, Java, Python and PHP stacks, and the OWASP Benchmark for measuring SAST/DAST tools.
- **TUI and CLI:** a whiptail menu for interactive use, and a scriptable command line for automation and CI.
- **One catalog:** [`src/catalog.json`](src/catalog.json) drives the TUI, the CLI, this README's lab table and the [web catalog](https://yusufarbc.github.io/webvuln-runner/).

## Safety model
The labs are **intentionally vulnerable**. Treat every one of them as hostile code.

- Labs publish on `127.0.0.1`. Use `--bind 0.0.0.0` (or the TUI's bind option) only on an isolated lab network.
- Docker isolates processes, but it is not a security boundary you should rely on against a compromised container. Do not run labs on machines holding sensitive data, and never on production infrastructure.
- Running Docker requires root, or membership in the `docker` group — which is equivalent to root on that host. WebVuln-Runner itself does not need root; it needs access to the Docker daemon.
- Images come from third parties (see each lab's source link). The catalog pins version tags where upstream publishes them; a [weekly audit](.github/workflows/image-audit.yml) checks that every image can still be pulled.

## Quick start
```sh
# Download the installer of a tagged release, read it, then run it
curl -fsSLO https://raw.githubusercontent.com/yusufarbc/webvuln-runner/v2.0.0/installers/install.sh
less install.sh
sudo bash install.sh

# Start a lab and open the URL it prints
sudo webvuln-runner up juice-shop
```

## Usage
### Interactive menu
Run `webvuln-runner` without arguments. The main menu lists your labs with their state and URL. Choose **Add a new lab** to pick one from the catalog. You can give it a name and a host port; a free port is suggested. WebVuln-Runner then pulls the image, starts the lab and waits until it answers. Select an existing lab to start, stop, check readiness, read logs or remove it.

### Command line
```text
webvuln-runner catalog               list labs that can be started
webvuln-runner list                  list your labs and their state
webvuln-runner up <lab> [options]    create and start a lab
    --name NAME     instance name (default: wvr-<lab>)
    --port PORT     host port for the lab's main port (default: first free one)
    --bind ADDR     address to publish on (default: 127.0.0.1)
    --no-wait       do not wait for the app to answer
webvuln-runner start|stop|status <name>
webvuln-runner logs <name> [--tail N]
webvuln-runner rm <name> [--volumes]
webvuln-runner validate [catalog.json]
webvuln-runner uninstall
```

Example:
```console
$ webvuln-runner up dvga
Lab 'wvr-dvga' (dvga) started.
  web: http://127.0.0.1:5013/
Waiting for 'wvr-dvga' to answer (up to 90s)...
'wvr-dvga' is ready: http://127.0.0.1:5013/

$ webvuln-runner up dvga --name dvga-2      # a second copy gets the next free port
$ webvuln-runner list
NAME                     LAB                STATE        URL
dvga-2                   dvga               running      http://127.0.0.1:5014/
wvr-dvga                 dvga               running      http://127.0.0.1:5013/
```

Exit codes: `0` ok, `1` error, `2` usage error, `3` lab started but did not answer in time.
`WVR_BIND` changes the default bind address, and `WVR_HEALTH_TIMEOUT` changes the default readiness timeout in seconds.

## Supported labs
<!-- catalog:start -->
| Lab | ID | Category | Stack | Type | Default port(s) |
|---|---|---|---|---|---|
| [OWASP Juice Shop](https://github.com/juice-shop/juice-shop) | `juice-shop` | web | Node.js, Angular | image | 3000 |
| [DVWA](https://github.com/digininja/DVWA) | `dvwa` | web | PHP, MySQL | image | 8081 |
| [OWASP WebGoat](https://github.com/WebGoat/WebGoat) | `webgoat` | training | Java, Spring | image | 8080, 9090 |
| [bWAPP](http://www.itsecgames.com/) | `bwapp` | web | PHP, MySQL | image | 8082 |
| [OWASP Mutillidae II](https://github.com/webpwnized/mutillidae) | `mutillidae` | web | PHP, MySQL | image | 8083 |
| [XVWA](https://github.com/s4n7h0/xvwa) | `xvwa` | web | PHP, MySQL | image | 8084 |
| [VAmPI](https://github.com/erev0s/VAmPI) | `vampi` | rest-api | Python, Flask | image | 5000 |
| [DVNA](https://github.com/appsecco/dvna) | `dvna` | web | Node.js, SQLite | image | 9091 |
| [VulnLab](https://github.com/Yavuzlar/VulnLab) | `vulnlab` | web | PHP | image | 8085 |
| [SQLi-Labs](https://github.com/Audi-1/sqli-labs) | `sqli-labs` | web | PHP, MySQL | image | 8086 |
| [OWASP VulnerableApp](https://github.com/SasanLabs/VulnerableApp) | `vulnerableapp` | web | Java, Spring | image | 9092 |
| [PyGoat](https://github.com/adeyosemanputra/pygoat) | `pygoat` | web | Python, Django | image | 8100 |
| [DVGA](https://github.com/dolevf/Damn-Vulnerable-GraphQL-Application) | `dvga` | graphql | Python, GraphQL | image | 5013 |
| [Hackazon](https://github.com/rapid7/hackazon) | `hackazon` | web | PHP, MySQL | image | 8087 |
| [OWASP Benchmark](https://github.com/OWASP-Benchmark/BenchmarkJava) | `owasp-benchmark` | benchmark | Java | image | 8443 |
| [DVWS (PHP)](https://github.com/snoopysecurity/dvws) | `dvws` | rest-api | PHP, SOAP | image | 8088 |
| [DSVPWA](https://github.com/sgabe/DSVPWA) | `dsvpwa` | web | Python | image | 65413 |
| [APIGoat](https://github.com/yusufarbc/APIGoat) | `apigoat` | rest-api | Node.js, Express, MongoDB | image | 8000, 8001-8010 |
| [OWASP crAPI](https://github.com/OWASP/crAPI) | `crapi` | rest-api | Java, Go, Python, PostgreSQL, MongoDB | compose | 8888, 8025 |
| [OWASP NodeGoat](https://github.com/OWASP/NodeGoat) | `nodegoat` | web | Node.js, Express, MongoDB | compose | 4000 |

20 labs. Generated from `src/catalog.json` by `scripts/gen-readme-table.sh`.
<!-- catalog:end -->

Default credentials and first-run steps are shown after a lab starts. They are also listed in the catalog under `credentials` and `notes`.

## Installation
`installers/install.sh` supports **Debian / Ubuntu / Kali**, **Fedora / RHEL / CentOS / Rocky / AlmaLinux** and **Arch Linux**. It:

1. installs Docker (from Docker's own repository on Red Hat family systems), the Compose v2 plugin where available, `whiptail`, `jq` and `curl`, and enables the Docker service;
2. downloads the release tarball, verifies it against the release's `SHA256SUMS` and refuses to install on mismatch;
3. installs to `/usr/local/lib/webvuln-runner`, with `webvuln-runner` (and the 1.x name `WebVuln-Runner`) in `/usr/local/bin`.

Options are environment variables: `WVR_RELEASE=v2.0.0`, `WVR_DISTRO=debian|redhat|arch`, `WVR_SKIP_DEPS=1`.

**From a git checkout:** `sudo installers/install-files.sh` installs the files of the checkout. You can also run `src/webvuln-runner` directly without installing.

**Update:** run the installer of the newer release; your labs are kept.

**Uninstall:** `sudo webvuln-runner uninstall`. It asks before removing the labs it created and never touches other containers. Pass `--remove-labs` or `--keep-labs` to skip the question when calling `/usr/local/lib/webvuln-runner/uninstall.sh` directly.

**Upgrading from 1.x:** the installer removes the old `/bin/WebVuln-Runner` and `/bin/indexApp.lst`. Containers created by 1.x carry no WebVuln-Runner label, so they do not appear in the new menu. Remove them with `docker rm -f <name>`.

Without the Compose plugin, multi-container labs are shown as unavailable and everything else works.

## Adding a lab
Add an entry to [`src/catalog.json`](src/catalog.json):

```json
{
  "id": "my-lab",
  "name": "My Lab",
  "description": "One line about what it teaches",
  "category": "web",
  "stack": ["PHP", "MySQL"],
  "type": "image",
  "image": "vendor/my-lab:1.2.3",
  "ports": [{ "name": "web", "container": 80, "host": 8099, "scheme": "http", "path": "/" }],
  "ram_mb": 256,
  "credentials": "admin / admin",
  "source": "https://github.com/vendor/my-lab"
}
```

| Field | Meaning |
|---|---|
| `category` | `web`, `rest-api`, `graphql`, `grpc`, `ai-mcp`, `benchmark` or `training` |
| `type` | `image` (one container) or `compose` (a Compose project, see below) |
| `image` | `repository:tag`. Use a version tag whenever upstream publishes one |
| `ports` | first entry is the main port (shown as the URL and used for the readiness check); `host` defaults must be unique across the catalog |
| `scheme` | `http`, `https`, `tcp` or `grpc` |
| `health` | optional `{ "type": "http" \| "https" \| "tcp", "path": "/ready" }` override |
| `health_timeout` | seconds to wait for readiness (default 90) |
| `env`, `workdir`, `command` | optional container environment, working directory and command |

**Compose labs** set `"type": "compose"` and `"compose": "compose/<id>/compose.yml"`. In that file:
- every service carries the `x-wvr-labels` block (see [`src/compose/nodegoat/compose.yml`](src/compose/nodegoat/compose.yml));
- every published port is written as `"${WVR_BIND:-127.0.0.1}:${WVR_PORT_<NAME>:-<default>}:<container port>"`, where `<NAME>` is the upper-cased port name from the catalog;
- `container_name` is not used, so several instances can coexist.

Then run `src/webvuln-runner validate`, `scripts/gen-readme-table.sh` and start the lab once with `src/webvuln-runner up <id>`.

## Development and tests
```sh
src/webvuln-runner validate          # catalog schema checks
bats tests/unit                      # unit tests with a fake docker CLI
bash tests/integration.sh            # end-to-end against a real Docker daemon
shellcheck -x src/webvuln-runner src/lib/*.sh installers/*.sh installers/*/*.sh scripts/*.sh
```
CI runs all of these on every pull request. The integration test checks that labs bind to `127.0.0.1` and that busy ports are skipped. It also checks that a container not created by WebVuln-Runner survives every command.

## Web catalog
[`index.html`](index.html) ([GitHub Pages](https://yusufarbc.github.io/webvuln-runner/)) renders the catalog with search and category filters. It also shows the command that starts each lab. It is static and read-only on purpose: a browser page cannot safely control your Docker daemon, and exposing the Docker socket to one would hand over root on your machine.

## Roadmap
- More labs outside classic web apps: gRPC (gRPC Goat), MCP/AI (DVMCP), dvws-node, DjanGoat
- Optional resource limits per lab
- `webvuln-runner update` to pull newer catalog images
- Optional local API for the web catalog, with authentication

## Contributing
1. Create a branch: `git checkout -b feature/my-lab`
2. Add the lab as described in [Adding a lab](#adding-a-lab) and run the tests
3. Open a pull request describing the lab and how you tested it

Report bugs or request labs at https://github.com/yusufarbc/webvuln-runner/issues.

## Disclaimer
These applications are intentionally vulnerable. Do not expose them to the internet or run them on production infrastructure. Use them only on systems you own or are authorized to test.

## License
GNU General Public License v3.0 — see [`LICENSE`](LICENSE). Third-party lab images and the adapted Compose files keep their own licenses, noted at the top of each file under `src/compose/`.
