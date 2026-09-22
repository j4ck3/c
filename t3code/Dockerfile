# T3 Code server + Cursor CLI agent for Unraid
# Node 24 satisfies T3's engines: ^22.16 || ^23.11 || >=24.10
FROM node:24-bookworm-slim

ARG TARGETARCH
ARG DOCKER_VERSION=27.5.1
ARG GH_VERSION=2.67.0
# Must match the desktop app (npm `t3` / GitHub T3 Code release).
ARG T3_VERSION=0.0.38

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/t3 \
    npm_config_cache=/home/t3/.npm \
    PATH="/home/t3/.local/bin:/usr/local/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      git \
      gnupg \
      gosu \
      jq \
      openssh-client \
      openssh-server \
      python3 \
      tini \
      unzip \
      wget \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/run/sshd /etc/ssh/sshd_config.d \
    && printf '%s\n' \
         'Port 22' \
         'PermitRootLogin no' \
         'PasswordAuthentication no' \
         'KbdInteractiveAuthentication no' \
         'PubkeyAuthentication yes' \
         'ChallengeResponseAuthentication no' \
         'UsePAM no' \
         'X11Forwarding no' \
         'AllowTcpForwarding yes' \
         'ClientAliveInterval 30' \
         'ClientAliveCountMax 10' \
         'StrictModes no' \
         > /etc/ssh/sshd_config.d/t3code.conf \
    && printf '%s\n' \
         'export PATH="/home/t3/.local/bin:/usr/local/bin:/opt/cursor-cli:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"' \
         'export HOME=/home/t3' \
         > /etc/profile.d/t3code-path.sh \
    && chmod 644 /etc/profile.d/t3code-path.sh

# Docker CLI + Compose v2 plugin (talks to host Unraid engine via mounted sock)
RUN arch="$(uname -m)" \
    && case "$arch" in \
         x86_64) darch=x86_64 ;; \
         aarch64) darch=aarch64 ;; \
         *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
       esac \
    && curl -fsSL "https://download.docker.com/linux/static/stable/${darch}/docker-${DOCKER_VERSION}.tgz" \
       | tar -xz -C /tmp \
    && mv /tmp/docker/docker /usr/local/bin/docker \
    && rm -rf /tmp/docker \
    && mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fsSL "https://github.com/docker/compose/releases/download/v2.32.4/docker-compose-linux-${darch}" \
       -o /usr/local/lib/docker/cli-plugins/docker-compose \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose \
    && docker --version \
    && docker compose version

# GitHub CLI
RUN arch="$(dpkg --print-architecture)" \
    && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${arch}.tar.gz" \
       | tar -xz -C /tmp \
    && mv "/tmp/gh_${GH_VERSION}_linux_${arch}/bin/gh" /usr/local/bin/gh \
    && rm -rf "/tmp/gh_${GH_VERSION}_linux_${arch}" \
    && gh --version

# Unraid documents are owned by jacob (uid 1000 / gid 100). Docker sock is root:docker (gid 281).
# node:24 image already has uid 1000 as user `node` — reuse it as `t3`.
RUN groupadd -g 281 docker || true \
    && usermod -l t3 -d /home/t3 -m node \
    && usermod -g users t3 \
    && usermod -aG docker t3 \
    && usermod -s /bin/bash t3 \
    && usermod -p '*' t3 \
    && mkdir -p /workspace /home/t3/.local/bin /home/t3/.t3 /home/t3/.cursor /home/t3/.config \
    && chown -R t3:users /home/t3 /workspace

# Cursor CLI into /opt so a mounted /home/t3 volume cannot hide it.
USER root
RUN curl -fsS https://cursor.com/install | bash \
    && echo "=== locating agent binary ===" \
    && AGENT_SRC="$(command -v agent || true)" \
    && if [ -z "$AGENT_SRC" ]; then \
         for cand in /root/.local/bin/agent /root/.cursor/bin/agent /usr/local/bin/agent; do \
           if [ -e "$cand" ]; then AGENT_SRC="$cand"; break; fi; \
         done; \
       fi \
    && if [ -z "$AGENT_SRC" ] || [ ! -e "$AGENT_SRC" ]; then \
         echo "Cursor CLI install did not produce an agent binary" >&2; \
         find /root -name 'agent' -o -name 'cursor-agent' 2>/dev/null | head -50; \
         exit 1; \
       fi \
    && echo "Using agent at: $AGENT_SRC" \
    && mkdir -p /opt/cursor-cli \
    && if [ -L "$AGENT_SRC" ]; then \
         real="$(readlink -f "$AGENT_SRC")" \
         && cp -a "$(dirname "$real")/." /opt/cursor-cli/; \
       else \
         cp -a "$(dirname "$AGENT_SRC")/." /opt/cursor-cli/; \
       fi \
    && if [ -x /opt/cursor-cli/cursor-agent ]; then \
         ln -sf /opt/cursor-cli/cursor-agent /usr/local/bin/agent \
         && ln -sf /opt/cursor-cli/cursor-agent /usr/local/bin/cursor-agent; \
       elif [ -x /opt/cursor-cli/agent ]; then \
         ln -sf /opt/cursor-cli/agent /usr/local/bin/agent \
         && ln -sf /opt/cursor-cli/agent /usr/local/bin/cursor-agent; \
       else \
         echo "No cursor-agent/agent executable under /opt/cursor-cli" >&2; \
         ls -la /opt/cursor-cli; \
         exit 1; \
       fi \
    && /usr/local/bin/agent --version

# Install T3 Code globally (node-pty needs allow-scripts on npm 11).
ENV HOME=/root \
    npm_config_cache=/root/.npm
RUN npm install -g "t3@${T3_VERSION}" --allow-scripts=node-pty,msgpackr-extract \
    && t3 --version \
    && chown -R t3:users /home/t3

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace
ENV HOME=/home/t3 \
    npm_config_cache=/home/t3/.npm \
    PATH="/home/t3/.local/bin:/usr/local/bin:/opt/cursor-cli:${PATH}"
EXPOSE 22
# tini reaps zombies when this image is run without Compose `init: true`.
# With Compose init enabled, docker-init is PID 1 instead; both are fine.
ENTRYPOINT ["tini", "-g", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
