# ZeroClaw on Arch Linux with OSINT tools — headless daemon + agent tools
# Build: docker build -t zeroclaw:local -f zeroclaw/Dockerfile zeroclaw/
# ZeroClaw binary from https://github.com/zeroclaw-labs/zeroclaw/releases

FROM archlinux:base

# Match Docker TARGETARCH (amd64, arm64) to zeroclaw release asset names.
# Default amd64 when building without buildx.
ARG TARGETARCH=amd64
ARG ZEROCLAW_VERSION=v0.1.6
ARG ZEROCLAW_BASE_URL=https://github.com/zeroclaw-labs/zeroclaw/releases/download

RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
        base-devel \
        curl \
        wget \
        ca-certificates \
        git \
        sudo \
        # OSINT / network CLI tools
        nmap \
        bind-tools \
        whois \
        inetutils \
        jq \
    && pacman -Scc --noconfirm

# Install yay (AUR helper) — build as non-root user (makepkg requirement)
RUN useradd -m -s /bin/bash builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    su builder -c "git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin && cd /tmp/yay-bin && makepkg -si --noconfirm" && \
    rm -rf /tmp/yay-bin && \
    userdel -r builder 2>/dev/null || true && \
    sed -i '/builder ALL/d' /etc/sudoers

# Optional Python-based OSINT tools
RUN pacman -S --noconfirm --needed python python-pip && \
    pip install --no-cache-dir --break-system-packages \
        theHarvester \
        sherlock-project \
    && rm -rf /root/.cache/pip

# Install ZeroClaw prebuilt binary (x86_64 or aarch64)
RUN case "${TARGETARCH}" in \
        amd64)  ZEROCLAW_ARCH=x86_64-unknown-linux-gnu ;; \
        arm64)  ZEROCLAW_ARCH=aarch64-unknown-linux-gnu ;; \
        arm)    ZEROCLAW_ARCH=armv7-unknown-linux-gnueabihf ;; \
        *)      echo "Unsupported TARGETARCH: ${TARGETARCH}"; exit 1 ;; \
    esac && \
    ZEROCLAW_TAR="zeroclaw-${ZEROCLAW_ARCH}.tar.gz" && \
    curl -fsSL -o /tmp/zeroclaw.tar.gz "${ZEROCLAW_BASE_URL}/${ZEROCLAW_VERSION}/${ZEROCLAW_TAR}" && \
    tar -xzf /tmp/zeroclaw.tar.gz -C /tmp && \
    install -m 0755 /tmp/zeroclaw /usr/local/bin/zeroclaw && \
    rm /tmp/zeroclaw.tar.gz /tmp/zeroclaw

# Runtime layout: config and workspace under one data dir (mounted at runtime)
ENV ZEROCLAW_DATA=/zeroclaw-data
ENV HOME=/zeroclaw-data
RUN mkdir -p "${ZEROCLAW_DATA}/.zeroclaw" "${ZEROCLAW_DATA}/workspace"

# Non-root user (same pattern as openclaw)
RUN useradd -m -u 1000 -s /bin/bash zeroclaw && \
    chown -R zeroclaw:zeroclaw "${ZEROCLAW_DATA}" && \
    echo 'zeroclaw ALL=(ALL) NOPASSWD: /usr/bin/pacman, /usr/bin/yay, /usr/bin/makepkg' >> /etc/sudoers.d/zeroclaw && \
    chmod 440 /etc/sudoers.d/zeroclaw

USER zeroclaw
WORKDIR "${ZEROCLAW_DATA}"

EXPOSE 42617

# Daemon runs gateway + channels (including Telegram polling)
CMD ["zeroclaw", "daemon"]
