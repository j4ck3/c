# DeepSeek Harness (dsh) — Web UI behind Netbird reverse proxy
FROM node:24-bookworm-slim

ARG GH_VERSION=2.67.0

# python3/make/g++: native deps for plugins (node-pty via dsh-better-sidebar, etc.)
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
      ca-certificates \
      chromium \
      curl \
      g++ \
      git \
      iproute2 \
      make \
      openssh-client \
      python3 \
      socat \
      tini \
  && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN arch="$(dpkg --print-architecture)" \
  && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${arch}.tar.gz" \
     | tar -xz -C /tmp \
  && mv "/tmp/gh_${GH_VERSION}_linux_${arch}/bin/gh" /usr/local/bin/gh \
  && rm -rf "/tmp/gh_${GH_VERSION}_linux_${arch}" \
  && gh --version

# Install DeepSeek's coherent release package. Building the monorepo and using
# pnpm deploy mixes workspace module identities, which breaks scoped presets.
ARG DSH_VERSION=0.1.6-alpha.2
COPY patch-dsh-reliability.mjs /tmp/patch-dsh-reliability.mjs
RUN npm config set allow-scripts '@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs' \
  && npm install -g "@deepseek-ai/dsh@${DSH_VERSION}" \
  && node /tmp/patch-dsh-reliability.mjs \
  && rm -f /tmp/patch-dsh-reliability.mjs \
  && npm cache clean --force

# dsh plugin add needs pnpm
RUN corepack enable \
  && corepack prepare pnpm@10.14.0 --activate

# Match t3code identity: uid 1000, gid 100 (users), docker group 281.
RUN groupadd -g 281 docker || true \
  && usermod -g 100 node \
  && usermod -aG docker node \
  && usermod -s /bin/bash node \
  && mkdir -p /home/node/.dsh /workspace \
  && chown -R node:users /home/node /workspace

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/install-remote-vscode-cli.sh /opt/dsh/scripts/install-remote-vscode-cli.sh
COPY patches /opt/dsh/patches
COPY skills /opt/dsh/skills
RUN chmod +x /usr/local/bin/entrypoint.sh /opt/dsh/scripts/install-remote-vscode-cli.sh

# Do not set NODE_ENV=production. Agents inherit this env; npm then omits
# devDependencies (StyleX, Vite, svelte-check, …) and workspace installs fail.
ENV HOME=/home/t3 \
    DSH_HOME=/home/t3/.dsh \
    PATH="/home/t3/.local/bin:/usr/local/bin:${PATH}"

USER node
WORKDIR /workspace

EXPOSE 3080

ENTRYPOINT ["tini", "-g", "--", "/usr/local/bin/entrypoint.sh"]
