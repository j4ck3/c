FROM archlinux:base

# ---------------------------------------------------------------
# System packages
# Add any extra tools you need to the pacman -S line below, then:
#   docker compose build && docker compose up -d openclaw-gateway
#
# Examples:
#   nmap python python-pip go rust metasploit nikto sqlmap whois
#   bind-tools net-tools inetutils traceroute openssh curl wget
# ---------------------------------------------------------------
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
        nodejs npm \
        git \
        base-devel \
        curl \
        unzip \
        chromium \
    && pacman -Scc --noconfirm

# agent-browser for web automation (uses system Chromium)
RUN npm install -g agent-browser
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium
ENV AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium

# Install Bun (used as package manager and build runner)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Install pnpm (needed by OpenClaw build scripts internally)
RUN npm install -g pnpm

# Optional: pass --build-arg GITHUB_TOKEN=ghp_xxx to avoid 429 rate limits when
# fetching git deps (e.g. libsignal-node). Or retry the build in a few minutes.
ARG GITHUB_TOKEN
RUN if [ -n "$GITHUB_TOKEN" ]; then git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"; fi

# Clone and build OpenClaw (retry on GitHub 500/429)
WORKDIR /app
RUN for i in 1 2 3 4 5; do \
    rm -rf /app/.git /app/.[!.]* /app/* 2>/dev/null; \
    git clone --depth 1 https://github.com/openclaw/openclaw.git . && break; \
    echo "Clone attempt $$i failed, retrying in 45s..."; sleep 45; \
  done && test -f /app/package.json
# Pass token into bun install so git deps (e.g. libsignal-node) get higher rate limit
RUN GITHUB_TOKEN=${GITHUB_TOKEN} bun install
RUN bun run build

# Add agent-browser skill so OpenClaw finds it at /app/skills/agent-browser/SKILL.md
COPY skills/agent-browser /app/skills/agent-browser

# Create non-root user for runtime
RUN useradd -m -u 1000 -s /bin/bash openclaw && \
    mkdir -p /home/openclaw/.openclaw /home/openclaw/workspace && \
    chown -R openclaw:openclaw /home/openclaw /app

USER openclaw
WORKDIR /app

# Set git identity for workspace commits
RUN git config --global user.email "openclaw@local" && \
    git config --global user.name "OpenClaw"

EXPOSE 18789

ENV NODE_ENV=production
CMD ["node", "dist/index.js", "gateway"]
