FROM openclaw:local AS base

USER root

# Varlock binary (resolves env vars from Bitwarden Secrets Manager at startup)
RUN curl -fsSL https://github.com/dmno-dev/varlock/releases/download/varlock%400.4.2/varlock-linux-x64.tar.gz \
    | tar -xz -C /usr/local/bin/ && chmod +x /usr/local/bin/varlock

# Add OpenViking skill for long-term memory via the OpenViking server
COPY skills/openviking /app/skills/openviking

# Home Assistant REST API — Varlock injects HA_URL / HA_TOKEN; skill tells the agent to use them
COPY skills/home-assistant /app/skills/home-assistant

# OpenViking CLI config (points to the openviking container on the Docker network)
RUN mkdir -p /home/openclaw/.openviking
COPY ovcli.conf /home/openclaw/.openviking/ovcli.conf
RUN chown -R openclaw:openclaw /home/openclaw/.openviking /app/skills/openviking /app/skills/home-assistant
ENV OPENVIKING_CLI_CONFIG_FILE=/home/openclaw/.openviking/ovcli.conf

USER openclaw
WORKDIR /app

ENV NODE_ENV=production
CMD ["varlock", "run", "--", "node", "dist/index.js", "gateway"]
