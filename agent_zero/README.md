# Agent Zero — Home Assistant Addon

> **Current version: 1.18** | [Changelog](../CHANGELOG.md)

Home Assistant addon that packages [Agent Zero](https://github.com/agent0ai/agent-zero) — an open-source, self-growing AI agent framework — as a fully managed HA addon.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Repository structure](#repository-structure)
3. [Building locally](#building-locally)
4. [Configuration reference](#configuration-reference)
5. [Extension repositories](#extension-repositories)
6. [Persistence model](#persistence-model)
7. [Sidebar integration](#sidebar-integration)
8. [Security](#security)
9. [Contributing](#contributing)

---

## Architecture

The addon extends the official `agent0ai/agent-zero:latest` Docker image:

```
agent0ai/agent-zero:latest   ← upstream base
    └── Dockerfile           ← adds Bun runtime, bootstrapper, overrides
          └── run_A0.sh      ← launcher override (setup venv → copy A0 → run UI)
          └── _05_extension_repo_bootstrap.py  ← built-in agent_init hook
```

**Why not Ingress?**  
Agent Zero's URL structure is incompatible with Home Assistant's built-in Ingress proxy. The addon exposes port `50001` directly and users add it via `panel_iframe`. See [DOCS.md](DOCS.md) for setup.

### Runtime components

| Component | Purpose |
|---|---|
| `agent0ai/agent-zero:latest` | Official Agent Zero image (Python, Node.js, npm) |
| **Bun** | Additional JS/TS runtime injected at build time |
| `run_A0.sh` | Overrides the default launcher; sets up venv, copies A0 files, starts `run_ui.py` |
| `_05_extension_repo_bootstrap.py` | `agent_init` hook — clones/updates extension repos at every startup |

---

## Repository structure

```
agent_zero/
├── config.yaml                          # HA addon manifest (version, ports, options, schema)
├── Dockerfile                           # Extends agent0ai/agent-zero:latest
├── README.md                            # This file (developer / contributor docs)
├── DOCS.md                              # End-user documentation (shown in HA addon store)
├── EXTENSIONS.md                        # Extension repository authoring specification
├── extensions/
│   └── agent_init/
│       └── _05_extension_repo_bootstrap.py  # Built-in bootstrap hook
├── overrides/
│   └── run_A0.sh                        # Agent Zero launcher override
└── translations/
    └── en.yaml                          # HA addon option labels/descriptions
CHANGELOG.md                             # (repo root) Full version history
CUSTOM_SIDEBAR.md                        # (repo root) Custom Sidebar integration guide
repository.yaml                          # HA addon repository metadata
```

---

## Building locally

```bash
# Clone
git clone https://github.com/Invernomut0/agent-zero-hassio
cd agent-zero-hassio/agent_zero

# Build image
docker build -t agent-zero-hassio:dev .

# Run locally (maps port 50001)
docker run --rm -p 50001:80 agent-zero-hassio:dev
```

---

## Configuration reference

All options are declared in `config.yaml` under `options` / `schema` and exposed in the HA addon configuration UI.

| Option | Type | Default | Description |
|---|---|---|---|
| `extension_repositories` | `[str]` | `[]` | List of Git repository URLs to bootstrap at startup |
| `extensions_auto_install` | `bool` | `true` | Copy `python/extensions/**` files from each repo automatically |
| `extensions_auto_run_installers` | `bool` | `true` | Execute detected installer script (`install_agent0_extension.sh`, `install_agent0_telegram_ext.sh`, `install.sh`) |
| `extensions_auto_run_commands` | `bool` | `false` | Execute `auto_run` commands from repo manifest (advanced, trusted repos only) |
| `extensions_debug` | `bool` | `false` | Verbose bootstrap logs prefixed with `[ext-repo-bootstrap]` |

### Environment variables (set in config.yaml)

| Variable | Value | Purpose |
|---|---|---|
| `A0_SET_searxng_server_enabled` | `"true"` | Enable SearXNG search |
| `A0_SET_cloudflare_tunnel_enabled` | `"false"` | Disable Cloudflare Tunnel |
| `HOME` | `/a0/usr` | Pin home dir to persistent volume |
| `XDG_CONFIG_HOME` | `/a0/usr/.config` | XDG config persistence |
| `XDG_DATA_HOME` | `/a0/usr/.local/share` | XDG data persistence |
| `XDG_STATE_HOME` | `/a0/usr/.local/state` | XDG state persistence |
| `GH_CONFIG_DIR` | `/a0/usr/.config/gh` | GitHub CLI auth persistence |

---

## Extension repositories

The bootstrap hook `_05_extension_repo_bootstrap.py` runs during every Agent Zero `agent_init` phase and:

1. Reads addon options from `/data/options.json`
2. For each URL in `extension_repositories`:
   - Clones (first run) or pulls (subsequent runs) the repo into `/a0/usr/extensions/repos/<slug>`
   - If `extensions_auto_run_installers=true` and a known installer script exists → executes it
   - Otherwise (fallback) copies `python/extensions/**` → `/a0/python/extensions/**`
3. If `extensions_auto_run_commands=true` → executes `auto_run` commands from `agent0-extension.json`

Log prefix: `[ext-repo-bootstrap] [agent_init]`

**Extension repository structure:**

```
<repo>/
├── python/extensions/
│   ├── agent_init/          # startup hooks (_NN_name.py)
│   ├── response_stream/     # response parsing hooks
│   └── message_loop_end/    # end-of-loop notification hooks
├── agent0-extension.json    # optional manifest
├── install_agent0_extension.sh  # optional idempotent installer
└── README.md
```

**Manifest (`agent0-extension.json`) fields** — all optional:

```json
{
  "name": "my-extension",
  "version": "1.0.0",
  "install_script": "install_agent0_extension.sh",
  "install_args": ["/a0"],
  "extension_paths": ["python/extensions"],
  "auto_run": ["./scripts/start-bridge.sh"]
}
```

> See [EXTENSIONS.md](EXTENSIONS.md) for the full authoring specification, installer best practices, and security guidance.

---

## Persistence model

The addon maps Home Assistant `addon_config` storage to `/a0/usr` (Agent Zero user data directory).

```yaml
# config.yaml
map:
  - type: addon_config
    read_only: false
    path: /a0/usr
```

What persists across restarts and updates:

- Agent memory, conversation history, skills, knowledge base
- User profiles, API keys, LLM settings
- GitHub CLI authentication (`/a0/usr/.config/gh`)
- Extension repositories (`/a0/usr/extensions/repos/`)
- All XDG config/data/state directories

> **Do not map the entire `/a0` directory** — it also contains application runtime files and causes issues on upgrades.

---

## Sidebar integration

Home Assistant Ingress is not supported. Add Agent Zero to the sidebar via `panel_iframe`:

```yaml
# configuration.yaml
panel_iframe:
  agent_zero:
    title: "Agent Zero"
    icon: mdi:robot
    url: "http://YOUR_HA_IP:50001"
    require_admin: true
```

See [CUSTOM_SIDEBAR.md](../CUSTOM_SIDEBAR.md) for the Custom Sidebar integration guide.

---

## Security

- `extensions_auto_run_commands` is **disabled by default** — enabling it allows arbitrary shell command execution from repo manifests.
- Use `require_admin: true` in `panel_iframe` configuration.
- Never commit API keys or secrets to extension repositories.
- Store secrets in Agent Zero's secrets manager (`/a0/usr/secrets.env`).
- Only add trusted repositories to `extension_repositories`.

---

## Contributing

1. Fork the repository: `https://github.com/Invernomut0/agent-zero-hassio`
2. Create a feature branch: `git checkout -b feat/your-feature`
3. Make changes and bump `version` in `config.yaml`
4. Update [CHANGELOG.md](../CHANGELOG.md) following Keep a Changelog format
5. Open a pull request

**Maintainer:** Lorenzo V — `invernomuto0@gmail.com`
