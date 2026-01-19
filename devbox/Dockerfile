# Arch Linux Dev Container
FROM archlinux:latest

# Set up locale
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen && \
    echo "LANG=en_US.UTF-8" > /etc/locale.conf

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV TERM=xterm-256color

# Update system and install base packages
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    # Base development
    base-devel \
    git \
    openssh \
    # Terminal
    tmux \
    # Editor
    neovim \
    # Utilities
    curl \
    wget \
    ripgrep \
    fd \
    fzf \
    unzip \
    zip \
    jq \
    tree \
    htop \
    # GitHub CLI
    github-cli \
    # Stow for dotfiles
    stow \
    # Node.js ecosystem
    nodejs \
    npm \
    # Docker CLI and Compose
    docker \
    docker-compose \
    # ttyd for web terminal
    ttyd \
    # Python (often needed)
    python \
    python-pip \
    # Tailscale for accessing remote Docker hosts
    tailscale && \
    # Clean up
    pacman -Scc --noconfirm

# Install pnpm globally
RUN npm install -g pnpm

# Install bun
RUN curl -fsSL https://bun.sh/install | bash
ENV BUN_INSTALL="/root/.bun"
ENV PATH="$BUN_INSTALL/bin:$PATH"

# Install lazygit from GitHub releases
RUN LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | jq -r '.tag_name' | sed 's/v//') && \
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" && \
    tar xf lazygit.tar.gz lazygit && \
    install lazygit /usr/local/bin && \
    rm lazygit lazygit.tar.gz

# Install lazydocker from GitHub releases
RUN LAZYDOCKER_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" | jq -r '.tag_name' | sed 's/v//') && \
    curl -Lo lazydocker.tar.gz "https://github.com/jesseduffield/lazydocker/releases/latest/download/lazydocker_${LAZYDOCKER_VERSION}_Linux_x86_64.tar.gz" && \
    tar xf lazydocker.tar.gz lazydocker && \
    install lazydocker /usr/local/bin && \
    rm lazydocker lazydocker.tar.gz

# Note: opencode-ai will be installed for dev user below

# Create dev user
RUN useradd -m -s /bin/bash -G wheel,docker dev && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    # Allow dev user to use SSH (create .ssh directory)
    mkdir -p /home/dev/.ssh && \
    chmod 700 /home/dev/.ssh && \
    chown dev:dev /home/dev/.ssh

# Switch to dev user for remaining setup
USER dev
WORKDIR /home/dev

# Install bun for dev user (set BUN_INSTALL to install in dev's home)
ENV BUN_INSTALL="/home/dev/.bun"
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL="/home/dev/.bun" bash
ENV PATH="/home/dev/.bun/bin:$PATH"

# Note: opencode-ai will be installed via official installer in entrypoint.sh
# This ensures it's installed after the persistent volume is mounted
# Ensure .opencode/bin comes before .bun/bin in PATH so official installer version is used
ENV PATH="/home/dev/.opencode/bin:/home/dev/.bun/bin:$PATH"

# Clone dotfiles repo
RUN git clone https://github.com/j4ck3/dotfiles /home/dev/.dotfiles

# Create necessary directories
RUN mkdir -p /home/dev/.config /home/dev/.local/share

# Note: /workspace is created by entrypoint.sh with proper permissions
# Copy scripts (will be added via COPY)
USER root

# Copy entrypoint and session scripts
COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY --chmod=755 new-session.sh /usr/local/bin/new-session.sh

# Copy opencode configuration to staging area (will be copied to final location by entrypoint)
# This is needed because the persistent home volume overwrites /home/dev at runtime
COPY --chown=dev:dev opencode-config /opt/opencode-staging/config
COPY --chown=dev:dev opencode-cache /opt/opencode-staging/cache
COPY --chown=dev:dev opencode-data /opt/opencode-staging/data

# Set ownership
RUN chown -R dev:dev /home/dev

# Expose ttyd port (7681) and SSH port (22)
EXPOSE 7681 22

# Set working directory
WORKDIR /workspace

# Run as dev user
USER dev

ENTRYPOINT ["/entrypoint.sh"]
