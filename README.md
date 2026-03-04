# Agent Zero — Home Assistant Addon Repository

> **v1.4.1** | Autonomous AI agent framework as a fully managed Home Assistant addon

[![HA Addon](https://img.shields.io/badge/Home%20Assistant-Addon-blue?logo=home-assistant)](https://github.com/Invernomut0/agent-zero-hassio)
[![Version](https://img.shields.io/badge/version-1.4.1-green)](CHANGELOG.md)
[![Arch](https://img.shields.io/badge/arch-amd64%20%7C%20aarch64-lightgrey)](#)

---

## What is this?

This repository is a **Home Assistant addon repository** that packages [Agent Zero](https://github.com/agent0ai/agent-zero) — an open-source, self-growing AI agent framework — as a first-class HA addon.

- Extends the official `agent0ai/agent-zero:latest` Docker image
- Adds **Bun** runtime, persistent storage wiring, and a built-in extension bootstrap system
- SearXNG web search enabled by default
- Architectures: `amd64`, `aarch64`

---

## Quick Install

1. Add this repository to Home Assistant:
   ```
   https://github.com/Invernomut0/agent-zero-hassio
   ```
2. Go to **Settings → Add-ons → Add-on Store**, find **Agent Zero** and install
3. Configure and start the addon
4. Add to sidebar via `panel_iframe` (see [DOCS.md](agent_zero/DOCS.md#sidebar-integration))

> Agent Zero is accessible at **`http://YOUR_HA_IP:50001`**

---

## Repository structure

```
agent_zero/          # Addon folder
├── config.yaml      # HA addon manifest (v1.3.0, ports, options, schema)
├── Dockerfile       # Extends agent0ai/agent-zero:latest + Bun
├── README.md        # Developer / contributor documentation
├── DOCS.md          # End-user documentation (shown in HA addon store)
├── EXTENSIONS.md    # Extension repository authoring specification
├── extensions/      # Built-in Agent Zero extension hooks
│   └── agent_init/
│       └── _05_extension_repo_bootstrap.py
├── overrides/
│   └── run_A0.sh    # Agent Zero launcher override
└── translations/
    └── en.yaml      # HA addon option labels

CHANGELOG.md         # Full version history
CUSTOM_SIDEBAR.md    # Custom Sidebar integration guide
repository.yaml      # HA addon repository metadata
```

---

## Extension repositories

From v1.2.0 the addon supports automatic management of community extension repositories. Configure one or more Git URLs in the addon options:

```yaml
extension_repositories:
  - https://github.com/Invernomut0/telegram_a0
extensions_auto_install: true
extensions_auto_run_installers: true
```

At every startup the addon clones/pulls the repositories and installs extensions automatically.

See [EXTENSIONS.md](agent_zero/EXTENSIONS.md) for the full authoring specification.

---

## Branch selection

From v1.4.0 you can choose which Agent Zero branch to run via the `agent_zero_branch` option:

| Value | Behaviour |
|---|---|
| `"main"` *(default)* | Uses the stable release baked into `agent0ai/agent-zero:latest` — fast startup, no network needed |
| `"development"` | Clones/updates the [`development` branch](https://github.com/agent0ai/agent-zero/tree/development) from GitHub at every startup and overlays `/a0` — bleeding-edge features, slightly slower boot |

> If the GitHub clone fails (e.g. no network), the addon falls back to the `main` image automatically.

```yaml
agent_zero_branch: "development"
```

---

## Documentation

| Document | Audience | Description |
|---|---|---|
| [agent_zero/DOCS.md](agent_zero/DOCS.md) | End users | Installation, configuration, troubleshooting |
| [agent_zero/README.md](agent_zero/README.md) | Developers | Architecture, local build, contributing |
| [agent_zero/EXTENSIONS.md](agent_zero/EXTENSIONS.md) | Extension authors | Extension repo spec and manifest format |
| [CUSTOM_SIDEBAR.md](CUSTOM_SIDEBAR.md) | End users | Custom Sidebar integration guide |
| [CHANGELOG.md](CHANGELOG.md) | All | Full version history |

---

## Changelog highlights

### v1.4.1 — 2026-03-04
Fix accesso da rete locale: patch CORS a runtime (`cors_allowed_origins="*"`) per risolvere "Invalid HTTP request received." causato da missing `Origin` header nelle richieste Socket.IO same-origin.

### v1.4.0 — 2026-03-04
Branch selector: nuova opzione `agent_zero_branch` per scegliere tra `main` (stable) e `development` (bleeding-edge da GitHub).

### v1.3.0 — 2026-03-03
**Breaking:** Extension bootstrap is now invoked exclusively via the `agent_init` hook.

### v1.2.0 — 2026-03-03
Extension repository management system: multi-repo support, installer auto-run, manifest-driven `auto_run` commands.

### v1.0.7 — 2026-03-02
GitHub CLI auth and all XDG paths persisted across restarts.

### v1.0.0 — 2026-02-27
Initial release: Dockerfile, Bun, SearXNG, port 50001, addon_config persistence.

→ [Full Changelog](CHANGELOG.md)

---

## Security

- `extensions_auto_run_commands` is **disabled by default** — enable only for fully trusted repositories
- Set `require_admin: true` in your `panel_iframe` configuration
- Never commit API keys to extension repositories

---

## Maintainer

**Lorenzo V** — `invernomuto0@gmail.com`  
Issues & PRs: [github.com/Invernomut0/agent-zero-hassio](https://github.com/Invernomut0/agent-zero-hassio)

---

## License

MIT
