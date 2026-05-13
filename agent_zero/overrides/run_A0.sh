#!/bin/bash

. "/ins/setup_venv.sh" "$@"
. "/ins/copy_A0.sh" "$@"

# Stop run_tunnel_api while we sync and install dependencies to avoid race
# conditions where it starts with an incomplete environment.
supervisorctl stop run_tunnel_api 2>/dev/null || true

# Ensure giturlparse is available (known new dep)
pip install --quiet giturlparse 2>/dev/null || true

# ---------------------------------------------------------------------------
# Agent Zero branch selector
# Reads option 'agent_zero_branch' from /data/options.json.
# - "main"        → use files already copied from the base image (default)
# - "development" → clone/update https://github.com/agent0ai/agent-zero
#                   (branch: development) and overlay /a0 before starting
# ---------------------------------------------------------------------------
A0_BRANCH=$(python3 - <<'EOF'
import json, sys
try:
    data = json.loads(open('/data/options.json').read())
    print(str(data.get('agent_zero_branch', 'main')).strip().lower())
except Exception:
    print('main')
EOF
)

if [ "$A0_BRANCH" = "development" ]; then
    echo "[branch-selector] Branch: development — syncing from GitHub..."
    A0_SRC="/tmp/a0-dev-src"

    if [ -d "$A0_SRC/.git" ]; then
        echo "[branch-selector] Updating existing clone..."
        git -C "$A0_SRC" fetch --depth=1 origin development \
            && git -C "$A0_SRC" reset --hard origin/development \
            || echo "[branch-selector] Update failed — using cached clone."
    else
        echo "[branch-selector] Cloning development branch (depth=1)..."
        git clone --depth=1 --branch development \
            https://github.com/agent0ai/agent-zero.git "$A0_SRC" || {
                echo "[branch-selector] Clone failed — falling back to main (latest)."
                A0_BRANCH="main"
            }
    fi

    if [ "$A0_BRANCH" = "development" ]; then
        echo "[branch-selector] Applying development files to /a0 ..."
        rsync -a --delete \
            --exclude='.git' \
            --exclude='usr' \
            "$A0_SRC/" /a0/

        # Sync application-owned subdirs of usr/ (e.g. plugins) without touching
        # user-generated data. --exclude='usr' above protects user settings, but
        # the development branch keeps app code in usr/plugins/ which must exist.
        for app_dir in plugins; do
            if [ -d "$A0_SRC/usr/$app_dir" ]; then
                mkdir -p "/a0/usr/$app_dir"
                rsync -a --delete "$A0_SRC/usr/$app_dir/" "/a0/usr/$app_dir/"
            fi
        done

        # Clear stale bytecode so Python picks up new source files
        find /a0 -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

        # Install packages required by the development branch without upgrading
        # anything already present in the venv. Each package is handled
        # individually so one conflict doesn't block all others.
        if [ -f "/a0/requirements.txt" ]; then
            echo "[branch-selector] Installing new development requirements (no upgrades)..."
            python3 << 'INSTALL_DEPS'
import subprocess, re, sys

with open('/a0/requirements.txt') as f:
    reqs = f.readlines()

for req in reqs:
    req = req.strip()
    if not req or req.startswith('#') or req.startswith('-'):
        continue
    pkg_name = re.split(r'[>=<!;\[ ]', req)[0].strip().lower().replace('-', '_')
    if not pkg_name:
        continue
    # Skip if already installed
    if subprocess.run(['pip', 'show', pkg_name], capture_output=True).returncode == 0:
        continue
    result = subprocess.run(
        ['pip', 'install', '--quiet', req],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        print(f"[branch-selector] Installed: {pkg_name}")
    else:
        print(f"[branch-selector] Skipped (conflict): {pkg_name}", file=sys.stderr)
INSTALL_DEPS
        fi

        echo "[branch-selector] Development branch active."
    fi
else
    echo "[branch-selector] Branch: main (latest image — no sync needed)."
fi
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# CORS patch: allow all origins for Socket.IO
#
# Root cause: when accessed directly via local IP (e.g. http://10.0.0.50:50001),
# the browser does NOT send the Origin header for same-origin XHR GET requests
# (Socket.IO HTTP long-polling). Agent Zero's validate_ws_origin() returns
# (False, "missing_origin") and Socket.IO responds 400 to every polling request,
# causing the "Invalid HTTP request received." error in the browser.
# Tailscale works because the page is loaded cross-origin (HA frontend HTTPS vs
# Agent Zero HTTP), so the browser does send Origin.
#
# Fix: replace the origin-validation lambda with cors_allowed_origins="*".
# Security is handled by HA authentication; CORS enforcement is redundant here.
# ---------------------------------------------------------------------------
python3 << 'CORS_PATCH'
import re, pathlib, sys
p = pathlib.Path('/a0/helpers/ui_server.py')
if not p.exists():
    print('[cors-patch] helpers/ui_server.py not found – skipping', file=sys.stderr)
    sys.exit(0)
content = p.read_text()

# Target: comma BEFORE the comment so Python sees it as a valid argument separator
CORRECT = 'cors_allowed_origins="*",  # HA addon: allow local network access'

if CORRECT in content:
    print('[cors-patch] Already correctly patched – no changes needed')
    sys.exit(0)

# Case 1: original lambda form (trailing comma is part of the matched pattern)
patched = re.sub(
    r'cors_allowed_origins\s*=\s*lambda[^\n]+validate_ws_origin\(environ\)\[0\],',
    CORRECT,
    content,
)

# Case 2: broken form from previous patch run – comma ended up after the comment
# e.g.  cors_allowed_origins="*"  # HA addon: ...,
if patched == content:
    patched = re.sub(
        r'cors_allowed_origins\s*=\s*"[^"]*"\s+#[^\n]+,',
        CORRECT,
        content,
    )

if patched != content:
    p.write_text(patched)
    print('[cors-patch] Applied: cors_allowed_origins set to "*" for local network access')
else:
    print('[cors-patch] Pattern not found – no changes')
CORS_PATCH
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Persist /a0/tmp across container restarts
# HA Supervisor recreates the container on every addon restart, wiping
# ephemeral paths. In standard Docker, tmp/ survives between restarts.
# Symlink to persistent storage to match that behaviour.
# ---------------------------------------------------------------------------
if [ ! -L "/a0/tmp" ]; then
    mkdir -p /a0/usr/tmp
    rm -rf /a0/tmp
    ln -sf /a0/usr/tmp /a0/tmp
    echo "[persist] Symlinked /a0/tmp -> /a0/usr/tmp"
fi

# ---------------------------------------------------------------------------
# Plugin pip dependency restoration
# User-installed plugins may declare pip dependencies in requirements.txt.
# Since the venv is ephemeral, restore them on every startup.
# PIP_CACHE_DIR under /a0/usr makes subsequent installs near-instant.
# ---------------------------------------------------------------------------
export PIP_CACHE_DIR="/a0/usr/.pip-cache"
mkdir -p "$PIP_CACHE_DIR"

if [ -d "/a0/usr/plugins" ]; then
    PLUGIN_RESTORE_COUNT=0
    for plugin_dir in /a0/usr/plugins/*/; do
        [ -d "$plugin_dir" ] || continue
        plugin_name=$(basename "$plugin_dir")
        if [ -f "$plugin_dir/requirements.txt" ]; then
            echo "[plugin-deps] Restoring pip dependencies for $plugin_name..."
            pip install --quiet -r "$plugin_dir/requirements.txt" 2>&1 || \
                echo "[plugin-deps] WARNING: Failed to restore deps for $plugin_name"
            PLUGIN_RESTORE_COUNT=$((PLUGIN_RESTORE_COUNT + 1))
        fi
    done
    if [ "$PLUGIN_RESTORE_COUNT" -gt 0 ]; then
        echo "[plugin-deps] Restored dependencies for $PLUGIN_RESTORE_COUNT plugin(s)"
    fi
fi

# Environment is ready: restart run_tunnel_api now that deps are installed.
supervisorctl start run_tunnel_api 2>/dev/null || true

echo "Starting A0 bootstrap manager..."
export PYTHONUNBUFFERED=1
exec python /exe/self_update_manager.py docker-run-ui
