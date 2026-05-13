# Changelog

All notable changes to the **Agent Zero Home Assistant Addon** are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).  
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [1.14.1] - 2026-05-13

### Fixed

- **Google Suite plugin dependencies restored after addon restart** — Plugin Hub installs the official `google` plugin into `/a0/usr/plugins/google`, but its Python packages are installed into the ephemeral Agent Zero venv through `initialize.py`/`hooks.install()`. The addon now reruns Google Suite's dependency initializer during startup, so packages such as `google-auth-oauthlib` are restored before Agent Zero starts while OAuth data remains persisted in `/a0/usr/plugins/google/data`.

---

## [1.14] - 2026-05-13

### Fixed

- **Aligned addon version with Agent Zero v1.14.**
- **Updated the HA local-access CORS startup patch for Agent Zero v1.14** — Socket.IO setup now lives in `/a0/helpers/ui_server.py`, so the addon patches that file instead of the retired `/a0/run_ui.py` location.
- **Reviewed v1.14 addon-impacting changes** — official startup still uses `self_update_manager.py docker-run-ui`, extension discovery still uses `/a0/extensions/python/...`, and the new Browser Playwright cache under `/a0/tmp/playwright` remains covered by the addon's persistent `/a0/tmp -> /a0/usr/tmp` mapping.

---

## [1.13.1] - 2026-05-07

### Fixed

- **Addon startup now delegates back to Agent Zero's official bootstrap manager** after HA-specific preflight steps. This keeps the addon aligned with upstream `self_update_manager.py docker-run-ui` startup behavior while preserving addon fixes for persistent `/a0/tmp`, plugin dependency restoration, branch selection, and CORS patching.
- **Built-in extension bootstrap path updated for Agent Zero v1.13** — the addon now installs its `agent_init` extension under `/a0/extensions/python/...`, matching upstream extension discovery.

---

## [1.4.12] - 2026-04-13

### Fixed

- **WhatsApp session lost on every addon restart** — users had to re-scan the QR code after each restart.
  - **Root cause**: HA Supervisor recreates the container on every addon restart (unlike regular Docker which preserves the container filesystem). Agent Zero stores the Baileys auth session in `tmp/whatsapp/session/` which is outside the persistent `/a0/usr/` volume.
  - **Fix**: symlink `/a0/tmp` → `/a0/usr/tmp` at startup so the entire `tmp/` directory persists across container restarts, matching standard Docker behaviour. Also fixes `tmp/settings.json` persistence (ref: agent0ai/agent-zero#952).

- **Plugin pip dependencies lost on every addon restart** — user-installed plugins with pip dependencies were broken after each restart.
  - **Root cause**: plugins install pip packages into the Python venv (`/opt/venv-a0/`) via `hooks.install()`, but this path is ephemeral and wiped on container recreation. The `install()` hook only runs on first plugin installation, not on restart.
  - **Fix**: on startup, scan `/a0/usr/plugins/` for `requirements.txt` files and reinstall dependencies. `PIP_CACHE_DIR` is set to persistent storage (`/a0/usr/.pip-cache`) so subsequent installs use local cache and complete in seconds.

---

## [1.4.11] - 2026-03-23

### Fixed

- **GitHub device auth code not visible in real time** (appeared only on error).
  - **Root cause**: `python run_ui.py 2>&1 | grep -v ...` introduces pipe buffering. Python's stdout is block-buffered when not connected to a TTY, so output (including "Please visit github.com/login/device and enter code XXXX") is held in a buffer and only flushed when the buffer fills or the process errors.
  - **Fix**: added `PYTHONUNBUFFERED=1` (forces Python to flush every write immediately) and `grep --line-buffered` (forces grep to pass each line through without accumulating). Auth codes now appear instantly in the HA addon logs.

---

## [1.4.10] - 2026-03-23

### Fixed

- **User configurations lost on restart** (regression introduced in v1.4.8).
  - **Root cause**: v1.4.8 removed `--exclude='usr'` from rsync to fix `FileNotFoundError: '/a0/usr/plugins'`. But `/a0/usr/` is also where agent-zero stores user settings, so removing the exclude caused every rsync to wipe user data. The per-file excludes added in v1.4.9 didn't help because user data lives inside `usr/`.
  - **Fix**: restored `--exclude='usr'` to protect all user data inside `/a0/usr/`. Application-owned subdirectories within `usr/` (currently just `plugins/`) are then explicitly synced in a second targeted `rsync` step. This preserves user settings while keeping application code up to date.

---

## [1.4.9] - 2026-03-23

### Fixed

- **User configurations wiped on every restart** when using the `development` branch.
  - **Root cause**: `rsync -a --delete` syncs the git repository onto `/a0`, and `--delete` removes any file in the destination that is not in the source. Agent Zero stores user data (memory, settings, working files, .env) in subdirectories of `/a0` that do not exist in the repository → they were deleted on every sync.
  - **Fix**: added `--exclude` flags for all user-data directories: `memory/`, `work_dir/`, `data/`, `logs/`, `tmp/`, and `.env`. These are preserved across restarts while application code is still fully updated from the branch.

---

## [1.4.8] - 2026-03-23

### Fixed

- **`FileNotFoundError: '/a0/usr/plugins'`** when starting `run_ui.py` with the `development` branch.
  - **Root cause**: the original `rsync` excluded the `usr` directory (`--exclude='usr'`) to avoid overwriting base-image OS files. The `development` branch of agent-zero moved plugins to `/a0/usr/plugins/`, which was silently dropped by rsync → directory didn't exist at startup.
  - **Fix**: removed `--exclude='usr'` from rsync. `/a0/usr` is agent-zero's own application directory, not the system `/usr`; it must be fully synced from the development branch.

---

## [1.4.7] - 2026-03-23

### Fixed

- **Race condition: `No module named 'watchdog'`** on `run_tunnel_api` second restart.
  - **Root cause**: `run_tunnel_api` is started by supervisord in parallel with `run_ui` (which runs `run_A0.sh`). The pip install loop runs inside `run_ui`'s startup script. When `run_tunnel_api` crashes and supervisord auto-restarts it, the install loop is still in progress → second startup attempt also fails with the missing module.
  - **Fix**: `supervisorctl stop run_tunnel_api` is called at the **very beginning** of `run_A0.sh` (after venv activation), before any git sync or pip install. After all setup is complete (sync + pycache clear + pip install + cors patch), `supervisorctl start run_tunnel_api` restarts it with a fully-ready environment.

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
