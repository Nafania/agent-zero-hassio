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

python /a0/prepare.py --dockerized=true
# python /a0/preload.py --dockerized=true # no need to run preload if it's done during container build

echo "Starting A0..."
exec python /a0/run_ui.py \
    --dockerized=true \
    --port=80 \
    --host="0.0.0.0"
    # --code_exec_ssh_enabled=true \
    # --code_exec_ssh_addr="localhost" \
    # --code_exec_ssh_port=22 \
    # --code_exec_ssh_user="root" \
    # --code_exec_ssh_pass="toor"
