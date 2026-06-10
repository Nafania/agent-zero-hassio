# Extend official Agent Zero image (already includes Node.js and Python)
FROM agent0ai/agent-zero:latest

# Install dependencies for Bun and branch-selector (rsync used to overlay /a0)
RUN apt-get update && apt-get install -y unzip git ca-certificates rsync && rm -rf /var/lib/apt/lists/*

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash

# Add Bun to PATH
ENV PATH="/root/.bun/bin:${PATH}"

# Verify installations
RUN node --version && npm --version && bun --version

# Pre-install the built-in WhatsApp bridge dependencies. In Home Assistant the
# container filesystem is recreated on addon restart, and the bridge stops after
# repeated runtime npm install failures. Baking node_modules into the image keeps
# WhatsApp startup independent of npm/network availability.
RUN if [ -f /a0/plugins/_whatsapp_integration/whatsapp-bridge/package-lock.json ]; then \
        cd /a0/plugins/_whatsapp_integration/whatsapp-bridge && \
        npm ci --omit=dev --no-audit --no-fund; \
    elif [ -f /git/agent-zero/plugins/_whatsapp_integration/whatsapp-bridge/package-lock.json ]; then \
        cd /git/agent-zero/plugins/_whatsapp_integration/whatsapp-bridge && \
        npm ci --omit=dev --no-audit --no-fund; \
    fi

# Agent Zero extension repository bootstrapper (loaded as built-in agent_init extension)
COPY extensions/agent_init/_05_extension_repo_bootstrap.py /a0/extensions/python/agent_init/_05_extension_repo_bootstrap.py

# Override Agent Zero launcher to bootstrap extension repositories before starting UI
COPY overrides/run_A0.sh /exe/run_A0.sh
RUN chmod +x /exe/run_A0.sh

# Expose port (Agent Zero serves on port 80 internally)
EXPOSE 80
