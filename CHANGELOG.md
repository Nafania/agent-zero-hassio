# Changelog

All notable changes to the **Agent Zero Home Assistant Addon** are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).  
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [1.4.6] - 2026-03-23

### Fixed

- **`ModuleNotFoundError: No module named 'watchdog'`** persisted despite constraints-based install (v1.4.5).
  - **Root cause**: using `pip install -r requirements.txt -c constraints.txt` fails **entirely** when any single package (e.g. `lxml_html_clean`) has a dependency conflict — pip aborts before reaching `watchdog` and other needed packages.
  - **Fix**: replaced the constraints approach with a per-package install loop (Python script). Each package from `requirements.txt` is installed individually only if not already present (`pip show` check). Conflicts on individual packages are warned and skipped, but do not block installation of the remaining packages.

---

## [1.4.5] - 2026-03-23

### Fixed

- **`ModuleNotFoundError: No module named 'watchdog'`** (and future missing packages) when using the `development` branch.
  - **Root cause**: the `development` branch adds new Python packages over time (`giturlparse`, `watchdog`, …) that are not in the base image's venv. Installing the full `requirements.txt` naively causes upgrade conflicts; skipping it leaves new packages missing.
  - **Fix**: after rsync, run `pip install -r /a0/requirements.txt` but pass the current venv state as a **constraints file** (`pip freeze > /tmp/pip_constraints.txt`). This installs any new packages while preventing upgrades to packages already present, avoiding dependency conflicts (e.g. `openai` version pinned by `litellm`).

---

## [1.4.4] - 2026-03-23

### Fixed

- **`ImportError: cannot import name 'whisper' from 'python.helpers' (unknown location)`** when using the `development` branch.
  - **Root cause**: `pip install -r /a0/requirements.txt` (added in v1.4.3) was upgrading/installing packages from the development branch's `requirements.txt`, which caused Python to resolve the `helpers` package from an installed location instead of the filesystem, breaking module resolution. The `(unknown location)` in the traceback was the tell-tale sign.
  - **Fix**: removed the `requirements.txt` install step entirely. The specific missing package (`giturlparse`) is already installed at startup before any service runs. Additionally, `__pycache__` directories are now purged after each rsync to prevent stale bytecode from shadowing new source files.

---

## [1.4.3] - 2026-03-23

### Fixed

- **Docker build failure: `No module named pip`** when installing `giturlparse`.
  - **Root cause**: `agent0ai/agent-zero:latest` uses a Python virtualenv activated at runtime via `setup_venv.sh`. At Docker build time neither `pip` nor `python3 -m pip` are available.
  - **Fix**: removed the `RUN pip install` from the `Dockerfile`; instead `giturlparse` is now installed via `pip install --quiet giturlparse` in `run_A0.sh` immediately after the venv is activated, where `pip` is always available.

---

## [1.4.2] - 2026-03-23

### Fixed

- **`ModuleNotFoundError: No module named 'giturlparse'`** when using the `development` branch.
  - **Root cause**: the `development` branch of agent-zero added `giturlparse` as a dependency in `helpers/git.py`, but the package was not present in the base image.
  - **Fix (Dockerfile)**: added `RUN python3 -m pip install --no-cache-dir giturlparse` at build time (using `python3 -m pip` because the base image does not expose `pip` in `$PATH`).
  - **Fix (run_A0.sh)**: after rsyncing the development branch, `python3 -m pip install -r /a0/requirements.txt` is executed to catch any future new dependencies automatically.

---

## [1.4.1] - 2026-03-04

### Fixed

- **"Invalid HTTP request received." / 400 errors when accessing from local network** (e.g. `http://10.0.0.x:50001`).
  - **Root cause**: Agent Zero's `validate_ws_origin()` rejects Socket.IO HTTP long-polling requests when the browser does not include an `Origin` header. For same-origin direct access (local IP, no HA proxy), Chrome/Firefox do not send `Origin` on XHR GET requests → origin check fails with `missing_origin` → Socket.IO returns 400 for all polling requests → frontend displays "Invalid HTTP request received." Tailscale/HA-proxy access worked because it is cross-origin (browser always sends `Origin`).
  - **Fix**: a startup patch in `run_A0.sh` replaces the validation lambda in `run_ui.py` with `cors_allowed_origins="*"`. In the HA addon context, security relies on HA authentication; Socket.IO CORS enforcement is redundant and breaks direct local access.

---

## [1.4.0] - 2026-03-04

### Added

- **Branch selector** — new addon option `agent_zero_branch` (values: `"main"` | `"development"`, default `"main"`).
  - `"main"`: uses the stable Agent Zero release already baked into the base image (`agent0ai/agent-zero:latest`). No extra download at startup.
  - `"development"`: on every startup, clones/updates the [development branch](https://github.com/agent0ai/agent-zero/tree/development) from GitHub and overlays `/a0` via `rsync` before launching Agent Zero. Falls back to `"main"` gracefully if the network is unavailable.
- `rsync` added to Dockerfile dependencies (required for the overlay step).

---

## [1.3.0] - 2026-03-03

### Breaking Changes

- **Extension bootstrap invocation is now exclusively via the `agent_init` hook.**  
  The `_05_extension_repo_bootstrap.py` extension is loaded as a standard Agent Zero `agent_init` hook. Any custom loading mechanism from previous versions that triggered bootstrap outside of `agent_init` must be removed.

### Changed

- Simplified bootstrap lifecycle: removed alternative invocation paths, the `agent_init` hook is the single entry point for extension repository management.
- Updated documentation to reflect the single invocation model.

---

## [1.2.0] - 2026-03-03

### Added

- **Extension repository management system** — configure one or more Git repository URLs in `extension_repositories`; they are cloned/pulled automatically at every addon startup.
- `extensions_auto_install` option (default `true`): automatically copy `python/extensions/**` files from each repository into Agent Zero's extension path.
- `extensions_auto_run_installers` option (default `true`): if an installer script is found in the repository (`install_agent0_extension.sh`, `install_agent0_telegram_ext.sh`, or `install.sh`), execute it automatically.
- `extensions_auto_run_commands` option (default `false`, advanced): execute startup shell commands declared in `auto_run` array of repository manifest (`agent0-extension.json`).
- `extensions_debug` option (default `false`): enable verbose bootstrap logs prefixed with `[ext-repo-bootstrap]`.
- `agent0-extension.json` manifest format support: `name`, `version`, `install_script`, `install_args`, `extension_paths`, `auto_run`.
- Built-in bootstrapper `_05_extension_repo_bootstrap.py` baked into the image at build time.
- New `EXTENSIONS.md` document: full specification for authoring extension repositories.
- Repositories cloned into `/a0/usr/extensions/repos/<slug>` (persisted via `addon_config`).

### Changed

- Extension files are now isolated per repository under `/a0/usr/extensions/repos/` instead of a flat directory.
- Installer execution is now fully idempotent by design — safe to re-run on every addon restart.

### Security

- `extensions_auto_run_commands` is disabled by default. Enable only for fully trusted repositories.

---

## [1.0.7] - 2026-03-02

### Added

- GitHub CLI / Copilot authentication is now **persisted across restarts**: `GH_CONFIG_DIR` is set to `/a0/usr/.config/gh`, which is inside the persistent `addon_config` volume.
- Full XDG path pinning to persistent storage: `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` all point inside `/a0/usr`.

### Fixed

- Switched to `addon_config` map type with explicit `path: /a0/usr` — resolves data loss on addon restart.
- Corrected Home Assistant addon `map` syntax from legacy `config` type to `addon_config`.

---

## [1.0.1] - 2026-02-27

### Fixed

- Added `unzip` as explicit system dependency in the Dockerfile — required by the Bun installer script.
- Fixed Home Assistant addon `map` declaration to use the correct `type: addon_config` / `path: /a0/usr` syntax for `/a0/usr` persistence.
- Added `git` and `ca-certificates` to Dockerfile system dependencies for extension repository support.

---

## [1.0.0] - 2026-02-27

### Added

- Initial release of the **Agent Zero Home Assistant Addon**.
- Custom `Dockerfile` extending the official `agent0ai/agent-zero:latest` image.
- **Bun** JavaScript runtime installed alongside the Node.js and npm already present in the base image.
- Internal port 80 → host port `50001` mapping (Agent Zero default).
- **SearXNG** search enabled by default via `A0_SET_searxng_server_enabled=true` environment variable.
- Cloudflare Tunnel disabled by default (`A0_SET_cloudflare_tunnel_enabled=false`).
- `hassio_api` and `homeassistant_api` enabled for HA integration.
- `SYS_ADMIN` privilege for container operations.
- Addon options: `extension_repositories`, `extensions_auto_install`, `extensions_auto_run_installers`, `extensions_auto_run_commands`, `extensions_debug`.
- Persistence: `addon_config` mapped to `/a0/usr` (Agent Zero user data directory).
- Sidebar integration documented via `panel_iframe` (Ingress not supported due to Agent Zero URL structure).
- `CUSTOM_SIDEBAR.md` guide for Custom Sidebar integration.
- HA addon translations (`en.yaml`).
- `repository.yaml` for Home Assistant addon repository registration.
- Architecture support: `aarch64`, `amd64`.

---

[1.3.0]: https://github.com/Invernomut0/agent-zero-hassio/compare/1.2.0...1.3.0
[1.2.0]: https://github.com/Invernomut0/agent-zero-hassio/compare/1.0.7...1.2.0
[1.0.7]: https://github.com/Invernomut0/agent-zero-hassio/compare/1.0.1...1.0.7
[1.0.1]: https://github.com/Invernomut0/agent-zero-hassio/compare/1.0.0...1.0.1
[1.0.0]: https://github.com/Invernomut0/agent-zero-hassio/releases/tag/1.0.0
