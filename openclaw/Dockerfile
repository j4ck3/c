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
    && pacman -Scc --noconfirm

# Install Bun (used as package manager and build runner)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Install pnpm (needed by OpenClaw build scripts internally)
RUN npm install -g pnpm

# Clone and build OpenClaw
WORKDIR /app
RUN git clone --depth 1 https://github.com/openclaw/openclaw.git .
RUN bun install
RUN bun run build

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
