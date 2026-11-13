# DeepSeek Harness (dsh) — Web UI behind Netbird reverse proxy
FROM node:24-bookworm-slim

ARG GH_VERSION=2.101.0

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
ARG DSH_VERSION=0.2.1-rc.5
# Refresh model metadata without changing the DSH/plugin runtime APIs.
ARG PI_AI_CATALOG_VERSION=0.87.1
ARG CODEX_CATALOG_VERSION=0.99.1
COPY patch-dsh-reliability.mjs patch-dsh-proxy-origin.mjs /tmp/
RUN npm config set allow-scripts '@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs' \
  && npm install -g "@deepseek-ai/dsh@${DSH_VERSION}" \
  && node /tmp/patch-dsh-reliability.mjs \
  && mkdir -p /tmp/pi-ai-catalog /opt/dsh/model-catalog \
  && npm pack "@earendil-works/pi-ai@${PI_AI_CATALOG_VERSION}" --pack-destination /tmp/pi-ai-catalog >/dev/null \
  && tar -xzf /tmp/pi-ai-catalog/earendil-works-pi-ai-${PI_AI_CATALOG_VERSION}.tgz -C /tmp/pi-ai-catalog \
  && for catalog in openrouter openai-codex; do \
       cp "/tmp/pi-ai-catalog/package/dist/providers/data/${catalog}.json" "/opt/dsh/model-catalog/${catalog}.json"; \
       cp "/tmp/pi-ai-catalog/package/dist/providers/data/${catalog}.json" "/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@earendil-works/pi-ai/dist/providers/data/${catalog}.json"; \
     done \
  && rm -rf /tmp/pi-ai-catalog /tmp/patch-dsh-*.mjs \
  && npm cache clean --force

# dsh plugin add needs pnpm.
RUN corepack enable \
  && corepack prepare pnpm@10.33.2 --activate

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
# Bake a current, legacy-key-compatible Codex fallback for offline startup.
RUN mkdir -p /tmp/codex-catalog \
  && npm pack "@earendil-works/pi-ai@${CODEX_CATALOG_VERSION}" --pack-destination /tmp/codex-catalog >/dev/null \
  && tar -xzf "/tmp/codex-catalog/earendil-works-pi-ai-${CODEX_CATALOG_VERSION}.tgz" -C /tmp/codex-catalog \
  && node --input-type=module -e 'import {normalizeCatalog} from "/opt/dsh/patches/refresh-codex-catalog.mjs"; import {readFileSync,writeFileSync} from "node:fs"; const data=JSON.stringify(normalizeCatalog(JSON.parse(readFileSync("/tmp/codex-catalog/package/dist/providers/data/openai-codex.json","utf8")))); for(const path of ["/opt/dsh/model-catalog/openai-codex.json","/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@earendil-works/pi-ai/dist/providers/data/openai-codex.json"]) writeFileSync(path,data);' \
  && rm -rf /tmp/codex-catalog
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
