# Agent Zero Extension Repository Specification

This document defines how to build a repository that can be automatically managed by the Home Assistant Agent Zero addon.

## Goals

A managed extension repository should be:

- startup-safe (idempotent)
- installable automatically at every addon boot
- compatible with persistent storage (`/a0/usr`)
- explicit about optional auto-run behavior

## Repository layout

Minimum layout:

- `python/extensions/...` (recommended)
- optional installer script (`install_agent0_extension.sh`, `install_agent0_telegram_ext.sh`, or `install.sh`)
- optional manifest `agent0-extension.json`

Example:

- `python/extensions/agent_init/_60_my_extension.py`
- `python/extensions/response_stream/_60_capture.py`
- `install_agent0_extension.sh`
- `agent0-extension.json`
- `README.md`

## Automatic management rule

At startup the addon bootstrapper:

1. reads Home Assistant addon options from `/data/options.json`
2. for each URL in `extension_repositories`, clone/pull repository in `/a0/usr/extensions/repos/<repo-name>`
3. if installer auto-run is enabled and an installer script exists, execute it
4. otherwise copy Python files from `python/extensions/**` to `/a0/python/extensions/**`
5. if command auto-run is enabled, execute commands declared in manifest (`auto_run`)

## Manifest format (`agent0-extension.json`)

All keys are optional.

```json
{
  "name": "my-extension",
  "version": "1.0.0",
  "install_script": "install_agent0_extension.sh",
  "install_args": ["/a0"],
  "extension_paths": ["python/extensions"],
  "auto_run": [
    "./scripts/start-bridge.sh"
  ]
}
```

### Fields

- `name`: human-readable extension name.
- `version`: semantic version of your extension package.
- `install_script`: installer path relative to repository root.
- `install_args`: argument list for installer invocation.
- `extension_paths`: list of directories to copy from (fallback mode).
- `auto_run`: shell commands executed at startup (only if addon option is enabled).

## Installer best practices

If you provide an installer script:

- make it idempotent (safe on repeated runs)
- copy only changed files when possible
- avoid destructive operations outside `/a0` and `/a0/usr`
- exit with non-zero code on real failures
- use clear logs

Recommended script behavior:

- lock against concurrent runs (if possible)
- ensure destination directories exist
- copy core extension files to `/a0/python/extensions/...`
- keep optional files non-blocking

## Security guidance

- treat repositories as trusted code execution sources
- keep `extensions_auto_run_commands: false` unless required
- store secrets in Agent Zero Secrets (`/a0/usr/secrets.env` fallback)
- never commit production secrets in repository files

## Example: Telegram extension repository

The repository `https://github.com/Invernomut0/telegram_a0` follows this model with:

- extension files under `python/extensions/...`
- idempotent installer script `install_agent0_telegram_ext.sh`
- startup-safe strategy for environments that persist only `/a0/usr`

## Validation checklist

Before publishing an extension repository:

- [ ] fresh clone and installer run succeeds
- [ ] second run produces no harmful side effects (idempotent)
- [ ] extension loads after Agent Zero restart
- [ ] README documents required secrets and operational flow
- [ ] no secret values committed
