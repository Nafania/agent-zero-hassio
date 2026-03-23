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
            --exclude='memory/' \
            --exclude='work_dir/' \
            --exclude='data/' \
            --exclude='logs/' \
            --exclude='.env' \
            --exclude='tmp/' \
            "$A0_SRC/" /a0/

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
p = pathlib.Path('/a0/run_ui.py')
if not p.exists():
    print('[cors-patch] run_ui.py not found – skipping', file=sys.stderr)
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

# Environment is ready: restart run_tunnel_api now that deps are installed
supervisorctl start run_tunnel_api 2>/dev/null || true

python /a0/prepare.py --dockerized=true
# python /a0/preload.py --dockerized=true # no need to run preload if it's done during container build

echo "Starting A0..."
# Pipe output through a filter to suppress harmless Uvicorn TCP-probe warnings
# emitted by the HA Supervisor health-check (raw TCP connect without an HTTP request).
python /a0/run_ui.py \
    --dockerized=true \
    --port=80 \
    --host="0.0.0.0" 2>&1 | grep -v "WARNING:  Invalid HTTP request received\."
    # --code_exec_ssh_enabled=true \
    # --code_exec_ssh_addr="localhost" \
    # --code_exec_ssh_port=22 \
    # --code_exec_ssh_user="root" \
    # --code_exec_ssh_pass="toor"
