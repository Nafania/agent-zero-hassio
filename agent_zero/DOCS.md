# Agent Zero - Home Assistant Addon

## Overview

Agent Zero is an open-source AI agent framework designed as a personal, organic, and dynamically growing assistant. It operates on a prompt-based architecture where the entire behavior is guided by system prompts.

### Key Features

- Multi-agent hierarchy
- Persistent memory
- Full transparency and customizability
- Skills system (SKILL.md standard)
- MCP Support
- A2A Protocol

## Installation

**⚠️ System Requirements:**
- Minimum 2GB RAM available for the addon
- Recommended 4GB+ RAM for optimal performance
- If running on low-memory systems (< 4GB total), you may need to increase swap space

### Steps

1. Add this repository to Home Assistant: `https://github.com/Invernomut0/agent-zero-hassio`
2. Go to Settings > Add-ons > Add-on Store
3. Find "Agent Zero" and click Install
4. Configure the addon (see Configuration section below)
5. Start the addon
6. **Add to sidebar** (see Sidebar Integration section)

**Note:** Initial startup may take 1-2 minutes as Agent Zero initializes.

## Development Tools Included

This addon extends the official Agent Zero image with additional development tools:
- **Node.js** - JavaScript runtime (included in base image)
- **npx** - Node package runner (included in base image)
- **Bun** - Fast JavaScript runtime and package manager (added)

These tools are available in the addon container for development and debugging purposes.

## Configuration

LLM provider settings, API keys and model choices are still configured in the Agent Zero web UI, but the addon now exposes **extension repository options** in the Home Assistant configuration flow.

### Extension repositories configuration

Available addon options:

- `extension_repositories` (array of git URLs)
- `extensions_auto_install` (`true/false`)
- `extensions_auto_run_installers` (`true/false`)
- `extensions_auto_run_commands` (`true/false`, advanced)
- `extensions_debug` (`true/false`, verbose extension bootstrap logs)

Example:

```yaml
extension_repositories:
   - https://github.com/Invernomut0/telegram_a0
   - https://github.com/example/another_agent0_extension
extensions_auto_install: true
extensions_auto_run_installers: true
extensions_auto_run_commands: false
extensions_debug: true
```

At addon startup, a built-in bootstrap extension does:

1. clone/pull of each configured repository into `/a0/usr/extensions/repos/`
2. installer execution when present (idempotent scripts recommended)
3. fallback copy of `python/extensions/**` into `/a0/python/extensions/**`
4. optional execution of `auto_run` commands declared in `agent0-extension.json`

When `extensions_debug=true`, addon logs include:

- raw options loading summary
- parsed repository list and count
- per-repository processing details
- installer selection and execution arguments
- each `auto_run` command before execution and its outcome

Extension repository bootstrap now runs during addon startup (before `run_ui.py`), so you will see logs immediately in Home Assistant addon logs, for example:

- `Starting extension repository bootstrap...`
- `[ext-repo-bootstrap] [startup] Starting extension bootstrap: ...`
- `[ext-repo-bootstrap] Cloned repository: ...` / `Updated repository: ...`
- `[ext-repo-bootstrap] auto_run command #... executed ...`

> [!WARNING]
> `extensions_auto_run_commands` executes shell commands from repository manifests.
> Enable this only for trusted repositories.

The addon will automatically persist all your data including:
- Agent memory and conversation history
- Custom skills and knowledge base
- User profiles and configurations
- API keys and LLM settings

All data is stored in Home Assistant's `addon_config` storage and mounted to Agent Zero's `/a0/usr` directory for full persistence across restarts and updates.

> [!IMPORTANT]
> Following the official Agent Zero documentation, the addon maps **only** `/a0/usr` for persistence.
> Do **not** map the entire `/a0` directory, as it also contains application/runtime files and can cause upgrade or configuration issues.

## Sidebar Integration

**Important:** Due to Agent Zero's URL structure, it cannot use Home Assistant's built-in Ingress system. Instead, add it to your sidebar using `panel_iframe`.

### Method 1: Via UI (Recommended)

1. Go to **Settings** > **Dashboards** > **Add Dashboard**
2. Or edit existing dashboard settings
3. Add a new panel with:
   - **Title:** Agent Zero
   - **Icon:** mdi:robot
   - **URL:** `http://YOUR_HA_IP:50001`

### Method 2: Via configuration.yaml

Add this to your Home Assistant `configuration.yaml`:

```yaml
panel_iframe:
  agent_zero:
    title: "Agent Zero"
    icon: mdi:robot
    url: "http://YOUR_HA_IP:50001"
    require_admin: true
```

Replace `YOUR_HA_IP` with your Home Assistant IP address (e.g., `192.168.1.100`).

Then restart Home Assistant or reload the configuration.

### Accessing Agent Zero

- **Via Sidebar:** Click "Agent Zero" in your Home Assistant sidebar
- **Direct Access:** Navigate to `http://YOUR_HA_IP:50001`
- **Port:** Default is 50001 (matches Agent Zero's default)

## Security

**⚠️ WARNING:** This addon has significant capabilities including:
- Code execution
- Terminal/shell access
- File system access
- External API calls

**Recommendations:**
- Use strong passwords
- Only expose to trusted networks
- Enable `require_admin: true` in panel_iframe config
- Keep API keys secure in addon configuration
- Monitor addon logs regularly

## Troubleshooting

### Addon keeps restarting / OOM errors

If you see `exit status 137` or processes being killed in logs:

1. **Check available memory:** The addon requires ~1-2GB RAM during operation
2. **Increase system memory:** If your HA system has < 4GB total RAM, consider:
   - Increasing VM/system RAM allocation
   - Adding swap space (see [HA swap guide](https://community.home-assistant.io/t/how-to-increase-the-swap-file-size-on-home-assistant-os/272226))
   - Stopping other heavy addons temporarily
3. **Wait for initialization:** First startup can take 2-3 minutes - be patient

### "Cannot connect" or blank page

1. **Check addon is running:** Go to Settings > Add-ons > Agent Zero
2. **Verify logs:** Look for "Agent Zero is running" and "Uvicorn running on http://0.0.0.0:80"
3. **Check URL:** Ensure you're using `http://YOUR_HA_IP:50001`
4. **Port conflicts:** Make sure no other service is using port 50001
5. **Browser cache:** Clear browser cache or try incognito mode

### Authentication issues

1. Verify username/password in addon configuration match what you're entering
2. Check addon logs for authentication errors
3. Try restarting the addon after changing credentials

### API key errors

1. Ensure your LLM provider API key is correctly set in addon configuration
2. Verify the key has sufficient credits/permissions
3. Check provider-specific requirements (e.g., Anthropic needs `sk-ant-` prefix)

### Other Issues

- **Container won't start:** Check Home Assistant system logs
- **Black screen:** Wait 2-3 minutes for full initialization, then refresh
- **Performance issues:** Increase context_length or switch to a lighter model

## Data Persistence

**✅ Automatic Persistence:** All Agent Zero data is automatically persisted in Home Assistant `addon_config` storage.

The addon maps Home Assistant `addon_config` storage to Agent Zero's `/a0/usr` directory, which contains:
- **Memory:** Agent memory and conversation history
- **Skills:** Custom uploaded skills (SKILL.md modules)
- **Knowledge:** Knowledge base documents
- **Profiles:** Agent profiles and configurations
- **Settings:** API keys, LLM provider settings, and preferences
- **GitHub auth:** GitHub CLI/Copilot device auth session files

Additionally, user-level configuration/state is forced under `/a0/usr`:
- `HOME=/a0/usr`
- `XDG_CONFIG_HOME=/a0/usr/.config`
- `XDG_DATA_HOME=/a0/usr/.local/share`
- `XDG_STATE_HOME=/a0/usr/.local/state`
- `GH_CONFIG_DIR=/a0/usr/.config/gh`

This ensures device logins and user settings do not need to be repeated after addon restarts.

**This data persists across:**
- Addon restarts
- Addon updates
- Home Assistant restarts
- Container rebuilds

**Note:** The first time you start the addon, you'll need to configure your LLM provider and API keys in the Agent Zero web interface. These settings will be saved and persist automatically.

## Support

- **GitHub Issues:** https://github.com/Invernomut0/agent-zero-hassio/issues
- **Agent Zero Documentation:** https://github.com/agent0ai/agent-zero
- **Home Assistant Community:** https://community.home-assistant.io

## License

MIT License
