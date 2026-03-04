#!/bin/bash

. "/ins/setup_venv.sh" "$@"
. "/ins/copy_A0.sh" "$@"

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
patched = re.sub(
    r'cors_allowed_origins\s*=\s*lambda[^\n]+validate_ws_origin\(environ\)\[0\]',
    'cors_allowed_origins="*"  # HA addon: allow local network access',
    content,
)
if patched != content:
    p.write_text(patched)
    print('[cors-patch] Applied: cors_allowed_origins set to "*" for local network access')
else:
    print('[cors-patch] Already patched or pattern not found – no changes')
CORS_PATCH
# ---------------------------------------------------------------------------

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
