# browser-use image plus the Bitwarden Agent Access CLI (aac).
ARG BROWSER_USE_TAG=main
FROM browseruse/browseruse:${BROWSER_USE_TAG}

ARG AAC_VERSION=v0.11.0
USER root
RUN curl -fsSL "https://github.com/bitwarden/agent-access/releases/download/${AAC_VERSION}/aac-linux-x86_64.tar.gz" \
      | tar xz -C /usr/local/bin aac \
    && chmod 0755 /usr/local/bin/aac \
    && aac --version
USER browseruse
WORKDIR /workspace
ENTRYPOINT []
CMD ["sleep", "infinity"]
