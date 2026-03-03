# Agent Zero - Home Assistant Addon

AI Assistant addon for Home Assistant based on Agent Zero.

## Installation

1. Copy this folder to your Home Assistant addons directory
2. Restart Home Assistant
3. Install the addon from the Add-on Store
4. Configure and start

## Architecture

This addon uses a wrapper approach:
- No Dockerfile modifications needed
- Uses Home Assistant's default base image
- Pulls Agent Zero image at runtime
- Runs nginx for URL rewriting
- Starts Agent Zero in a separate container

This avoids the `build_from` limitation in Home Assistant addon builds.

## Extension repositories (new)

This addon now supports one or more **extension repositories** that are fetched and applied automatically at startup.

### Add repositories from addon configuration

In the Home Assistant addon configuration, use:

- `extension_repositories`: array of Git URLs
- `extensions_auto_install`: copy extension files automatically (`true` by default)
- `extensions_auto_run_installers`: execute repo installer script if present (`true` by default)
- `extensions_auto_run_commands`: execute manifest startup commands (`false` by default, advanced)
- `extensions_debug`: verbose bootstrap logs (`false` by default)

Example configuration:

```yaml
extension_repositories:
	- https://github.com/Invernomut0/telegram_a0
	- https://github.com/example/another_agent0_extension
extensions_auto_install: true
extensions_auto_run_installers: true
extensions_auto_run_commands: false
extensions_debug: true
```

At startup, the addon bootstrapper will:

1. Clone/pull repositories into `/a0/usr/extensions/repos/<repo-name>`
2. Run installer scripts when available (idempotent flow recommended)
3. Fallback-copy Python extension files from `python/extensions/**` to `/a0/python/extensions/**`
4. Optionally run `auto_run` commands declared in manifest `agent0-extension.json`

You can verify this in addon logs right after startup via lines prefixed with `[ext-repo-bootstrap]`.

> Security note: only use trusted repositories. Enabling auto-run commands means arbitrary startup commands can be executed.

For extension repo authoring rules, see `EXTENSIONS.md`.

### Required extension repository structure

Recommended tree:

- `python/extensions/agent_init/*.py` → startup hooks
- `python/extensions/response_stream/*.py` → response parsing hooks
- `python/extensions/message_loop_end/*.py` → end-of-loop notification hooks
- `agent0-extension.json` (optional manifest)
- `install_agent0_extension.sh` (optional installer, idempotent)

If `install_agent0_extension.sh` is present (or another known installer), it will be executed when installer auto-run is enabled.
If no installer is found, files under `python/extensions/**` are copied automatically.

`agent0-extension.json` may define:

- `install_script`
- `install_args`
- `extension_paths`
- `auto_run` (startup commands, executed only when `extensions_auto_run_commands=true`)

## Notes

- GitHub device authentication (used by GitHub CLI/Copilot tooling inside the addon) is persisted across restarts.
- User-level config/state is pinned to `/a0/usr` (mounted from Home Assistant `addon_config`), so settings survive addon restarts.
- If you authenticated once and still get prompted again, update to addon version `1.0.7` or newer and restart the addon once.