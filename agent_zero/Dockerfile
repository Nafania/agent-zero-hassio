# Extend official Agent Zero image (already includes Node.js and Python)
FROM agent0ai/agent-zero:latest

# Install dependencies for Bun
RUN apt-get update && apt-get install -y unzip git ca-certificates && rm -rf /var/lib/apt/lists/*

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash

# Add Bun to PATH
ENV PATH="/root/.bun/bin:${PATH}"

# Verify installations
RUN node --version && npm --version && bun --version

# Agent Zero extension repository bootstrapper (loaded as built-in agent_init extension)
COPY extensions/agent_init/_05_extension_repo_bootstrap.py /a0/python/extensions/agent_init/_05_extension_repo_bootstrap.py

# Override Agent Zero launcher to bootstrap extension repositories before starting UI
COPY overrides/run_A0.sh /exe/run_A0.sh
RUN chmod +x /exe/run_A0.sh

# Expose port (Agent Zero serves on port 80 internally)
EXPOSE 80