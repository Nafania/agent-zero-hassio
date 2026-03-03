#!/bin/bash

. "/ins/setup_venv.sh" "$@"
. "/ins/copy_A0.sh" "$@"

echo "Starting extension repository bootstrap..."
if [ -f /a0/python/extensions/agent_init/_05_extension_repo_bootstrap.py ]; then
    python /a0/python/extensions/agent_init/_05_extension_repo_bootstrap.py startup
else
    echo "[ext-repo-bootstrap] Bootstrap script not found at /a0/python/extensions/agent_init/_05_extension_repo_bootstrap.py"
fi

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
