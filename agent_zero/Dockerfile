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

# Pre-install bundled Node package dependencies. In Home Assistant the container
# filesystem is recreated on addon restart, so repo-owned Node packages should
# not depend on runtime npm/network availability.
RUN set -eu; \
    find /git/agent-zero /a0 \
        -path '*/node_modules' -prune -o \
        -name package-lock.json -print 2>/dev/null \
    | sort -u \
    | while IFS= read -r lockfile; do \
        package_dir="$(dirname "$lockfile")"; \
        if [ -f "$package_dir/package.json" ]; then \
            echo "[node-deps] Installing $package_dir"; \
            (cd "$package_dir" && npm ci --omit=dev --no-audit --no-fund); \
        fi; \
    done

# Agent Zero extension repository bootstrapper (loaded as built-in agent_init extension)
COPY extensions/agent_init/_05_extension_repo_bootstrap.py /a0/extensions/python/agent_init/_05_extension_repo_bootstrap.py

# Override Agent Zero launcher to bootstrap extension repositories before starting UI
COPY overrides/run_A0.sh /exe/run_A0.sh
RUN chmod +x /exe/run_A0.sh

# Expose port (Agent Zero serves on port 80 internally)
EXPOSE 80
