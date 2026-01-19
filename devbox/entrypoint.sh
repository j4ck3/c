#!/bin/bash
# entrypoint.sh - Container startup script
# Sets up dotfiles, configures environment, starts ttyd

set -e

echo "╔════════════════════════════════════════╗"
echo "║     Dev Container - Initializing...    ║"
echo "╚════════════════════════════════════════╝"

# Ensure home directory ownership
if [ -w /home/dev ]; then
    cd /home/dev
fi

# Copy opencode files from staging area if they don't exist or are empty
# This is needed because the persistent home volume overwrites /home/dev at runtime
if [ -d /opt/opencode-staging/config ]; then
    if [ ! -s /home/dev/.config/opencode/opencode.json ]; then
        echo "Copying opencode configuration from staging area..."
        mkdir -p /home/dev/.config/opencode
        rm -rf /home/dev/.config/opencode/* 2>/dev/null || true
        cp -r /opt/opencode-staging/config/* /home/dev/.config/opencode/
        chown -R dev:dev /home/dev/.config/opencode
    fi
fi

if [ -d /opt/opencode-staging/cache ]; then
    if [ ! -s /home/dev/.cache/opencode/package.json ]; then
        echo "Copying opencode cache from staging area..."
        mkdir -p /home/dev/.cache/opencode
        rm -rf /home/dev/.cache/opencode/* 2>/dev/null || true
        cp -r /opt/opencode-staging/cache/* /home/dev/.cache/opencode/
        chown -R dev:dev /home/dev/.cache/opencode
    fi
fi

if [ -d /opt/opencode-staging/data ]; then
    if [ ! -s /home/dev/.local/share/opencode/auth.json ]; then
        echo "Copying opencode data from staging area..."
        mkdir -p /home/dev/.local/share/opencode
        rm -rf /home/dev/.local/share/opencode/* 2>/dev/null || true
        cp -r /opt/opencode-staging/data/* /home/dev/.local/share/opencode/
        chown -R dev:dev /home/dev/.local/share/opencode
    fi
fi

# Set up auto-start tmux on SSH login (not for ttyd/browser)
# Add to .bashrc (since .bash_profile sources .bashrc, and .bash_profile might be a symlink from dotfiles)
# Check if the code is already there to avoid duplicates
if ! grep -q "# Auto-start tmux session for SSH" /home/dev/.bashrc 2>/dev/null; then
    cat >> /home/dev/.bashrc << 'EOF'

# Auto-start tmux session for SSH connections (not for ttyd/browser)
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_CONNECTION" ]; then
    # Only for interactive SSH sessions (not for non-interactive like 'ssh host command')
    if [ -t 0 ] && [ -z "$TMUX" ] && [ -z "$TTYD" ]; then
        # Check if new-session.sh exists and run it
        if [ -f /usr/local/bin/new-session.sh ]; then
            exec /usr/local/bin/new-session.sh
        fi
    fi
fi
EOF
    chown dev:dev /home/dev/.bashrc 2>/dev/null || true
fi

# First run: Set up dotfiles with stow
if [ ! -f /home/dev/.dotfiles_installed ]; then
    echo "Setting up dotfiles..."
    
    if [ -d /home/dev/.dotfiles ]; then
        cd /home/dev/.dotfiles
        
        # Stow available packages (bash, yazi)
        # Only stow packages that exist and are relevant for terminal
        for package in bash yazi; do
            if [ -d "$package" ]; then
                echo "  Stowing $package..."
                stow -t /home/dev "$package" 2>/dev/null || echo "  Warning: Could not stow $package"
            fi
        done
        
        touch /home/dev/.dotfiles_installed
        echo "Dotfiles setup complete!"
    else
        echo "Warning: Dotfiles directory not found, skipping stow setup"
    fi
fi

# Set up LazyVim if not already configured
if [ ! -d /home/dev/.config/nvim ]; then
    echo "Setting up LazyVim..."
    git clone https://github.com/LazyVim/starter /home/dev/.config/nvim 2>/dev/null || true
    # Remove .git so it's not a repo
    rm -rf /home/dev/.config/nvim/.git 2>/dev/null || true
    echo "LazyVim setup complete!"
fi

# Set up opencode config directory (ensure it's writable for opencode)
mkdir -p /home/dev/.config/opencode
# Ensure directory is owned by dev user (needed for opencode to write package.json)
sudo chown -R dev:dev /home/dev/.config/opencode 2>/dev/null || true
chmod 755 /home/dev/.config/opencode 2>/dev/null || true

# Pre-install opencode plugins if package.json exists to avoid runtime compilation
if [ -f /home/dev/.config/opencode/package.json ]; then
    echo "Pre-installing opencode plugins to avoid runtime compilation..."
    cd /home/dev/.config/opencode
    # Run bun install to ensure all dependencies are installed and compiled upfront
    bun install 2>/dev/null || true
    cd - >/dev/null 2>&1 || true
fi

# Pre-build/warm-up opencode to trigger any first-time initialization or compilation
# This runs in background so it doesn't block container startup
if command -v opencode >/dev/null 2>&1; then
    echo "Pre-warming opencode to trigger initialization/compilation..."
    # Run opencode --help in a subshell with timeout to trigger initialization
    # Redirect output to /dev/null to avoid cluttering logs
    (cd /tmp && timeout 30 opencode --help >/dev/null 2>&1 || true) &
    OPENCODE_WARMUP_PID=$!
    # Don't wait for it to complete - let it run in background
    echo "Opencode warm-up started (PID: $OPENCODE_WARMUP_PID)"
fi

# Configure opencode with environment variables if provided
if [ -n "$OPENCODE_GOOGLE_API_KEY" ] || [ -n "$OPENCODE_ANTHROPIC_API_KEY" ]; then
    echo "Configuring opencode API keys..."
    
    # Create opencode config if it doesn't exist
    if [ ! -f /home/dev/.config/opencode/opencode.json ]; then
        cat > /home/dev/.config/opencode/opencode.json << 'EOF'
{
  "$schema": "https://opencode.ai/config.json"
}
EOF
    fi
fi

# Fix opencode.json to use specific plugin versions instead of @latest
# This prevents Bun from trying to resolve/install at runtime (which can crash)
if [ -f /home/dev/.config/opencode/opencode.json ]; then
    # Check if opencode.json has @latest and replace with installed version
    if grep -q "opencode-antigravity-auth@latest" /home/dev/.config/opencode/opencode.json 2>/dev/null; then
        echo "Fixing opencode.json: pinning plugin versions to avoid runtime resolution..."
        cd /home/dev/.config/opencode
        # Use jq to replace @latest with 1.3.0 (or get from package.json)
        INSTALLED_VERSION=$(grep -o '"opencode-antigravity-auth": "[^"]*"' package.json 2>/dev/null | grep -o '[0-9.]*' | head -1 || echo "1.3.0")
        if command -v jq >/dev/null 2>&1; then
            jq --arg version "$INSTALLED_VERSION" 'if .plugin then .plugin = [.plugin[] | if contains("@latest") then sub("@latest"; "@\($version)") else . end] else . end' opencode.json > opencode.json.tmp && mv opencode.json.tmp opencode.json 2>/dev/null || true
        fi
        cd - >/dev/null 2>&1 || true
    fi
fi

# Ensure workspace directory exists and is writable
if [ ! -d /workspace ]; then
    sudo mkdir -p /workspace 2>/dev/null || true
    sudo chown dev:dev /workspace 2>/dev/null || true
fi

# Ensure workspace is writable by dev user
if [ -d /workspace ] && [ ! -w /workspace ]; then
    sudo chown -R dev:dev /workspace 2>/dev/null || true
fi


# Wait for Docker daemon to be ready (DinD)
echo "Waiting for Docker daemon to be ready..."
for i in {1..30}; do
    if docker info > /dev/null 2>&1; then
        echo "  Docker daemon is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "  Warning: Docker daemon not ready after 30 attempts"
    else
        sleep 1
    fi
done

# Configure Git to use SSH for GitHub and GitLab
git config --global url."git@github.com:".insteadOf "https://github.com/" 2>/dev/null || true
GITLAB_URL="${GITLAB_URL:-gitlab.com}"
git config --global url."git@${GITLAB_URL}:".insteadOf "https://${GITLAB_URL}/" 2>/dev/null || true

# Setup SSH keys for GitHub/GitLab
if [ -d /home/dev/.ssh ] && [ -n "$(ls -A /home/dev/.ssh/*.pub 2>/dev/null)" ]; then
    echo "SSH keys found, configuring SSH authentication..."
    
    # Set proper permissions on SSH directory and keys
    chmod 700 /home/dev/.ssh 2>/dev/null || true
    find /home/dev/.ssh -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} \; 2>/dev/null || true
    find /home/dev/.ssh -type f -name "*.pub" -exec chmod 644 {} \; 2>/dev/null || true
    
    # Start SSH agent
    eval "$(ssh-agent -s)" > /dev/null 2>&1 || true
    
    # Add all private keys to SSH agent
    for key in /home/dev/.ssh/id_*; do
        if [ -f "$key" ] && [ ! -f "${key}.pub" ]; then
            ssh-add "$key" 2>/dev/null || true
        fi
    done
    
    # Add known hosts for GitHub and GitLab
    mkdir -p /home/dev/.ssh
    if [ ! -f /home/dev/.ssh/known_hosts ] || [ ! -s /home/dev/.ssh/known_hosts ]; then
        echo "Adding GitHub and GitLab to known hosts..."
        ssh-keyscan github.com 2>/dev/null >> /home/dev/.ssh/known_hosts || true
        ssh-keyscan "$GITLAB_URL" 2>/dev/null >> /home/dev/.ssh/known_hosts || true
        chmod 644 /home/dev/.ssh/known_hosts 2>/dev/null || true
    fi
    
    # Set SSH config if it doesn't exist
    if [ ! -f /home/dev/.ssh/config ]; then
        cat > /home/dev/.ssh/config << 'EOF'
Host github.com
    HostName github.com
    User git
    StrictHostKeyChecking accept-new

Host gitlab.com
    HostName gitlab.com
    User git
    StrictHostKeyChecking accept-new
EOF
        # Add custom GitLab URL if provided
        if [ -n "$GITLAB_URL" ] && [ "$GITLAB_URL" != "gitlab.com" ]; then
            cat >> /home/dev/.ssh/config << EOF

Host ${GITLAB_URL}
    HostName ${GITLAB_URL}
    User git
    StrictHostKeyChecking accept-new
EOF
        fi
        chmod 600 /home/dev/.ssh/config 2>/dev/null || true
    fi
    
    echo "  SSH keys configured for GitHub and GitLab"
else
    echo "  Warning: No SSH keys found in ~/.ssh. GitHub/GitLab authentication will not work."
    echo "  Mount your SSH keys by ensuring ~/.ssh exists on host and is mounted to the container."
fi

# Create a sample project if workspace is empty
if [ -z "$(ls -A /workspace 2>/dev/null)" ] && [ -w /workspace ] 2>/dev/null; then
    echo "Creating sample project..."
    if mkdir -p /workspace/hello-world 2>/dev/null; then
        cat > /workspace/hello-world/README.md << 'EOF'
# Hello World

This is a sample project. You can:

1. Edit this project
2. Create new projects in /workspace
3. Clone existing repos

## Getting Started

```bash
# Create a new project
mkdir /workspace/my-project
cd /workspace/my-project
npm init -y

# Or clone a repo
git clone git@github.com:user/repo /workspace/repo
```
EOF
        echo "Sample project created at /workspace/hello-world"
    else
        echo "Warning: Could not create sample project (permission issue)"
    fi
fi

# Install opencode-ai using official installer script (if not already installed)
# This runs after persistent volumes are mounted, so installation persists
# Check if official installer version exists, not just any opencode command
if [ ! -f /home/dev/.opencode/bin/opencode ]; then
    echo "Installing opencode-ai using official installer..."
    # Remove old bun-installed opencode first so installer doesn't detect it
    rm -f /home/dev/.bun/bin/opencode 2>/dev/null || true
    # Temporarily remove from PATH so installer doesn't detect old version
    OLD_PATH="$PATH"
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    # Run installer (show full output for debugging)
    curl -fsSL https://opencode.ai/install | bash || echo "Warning: opencode installer failed"
    # Restore PATH and add .opencode/bin
    export PATH="/home/dev/.opencode/bin:$OLD_PATH"
    # Ensure ownership
    chown -R dev:dev /home/dev/.opencode 2>/dev/null || true
    echo "Opencode installation complete"
else
    echo "Opencode already installed via official installer"
    # Ensure .opencode/bin is in PATH
    export PATH="/home/dev/.opencode/bin:$PATH"
fi

# Configure and start Tailscale (if auth key provided)
if [ -n "$TAILSCALE_AUTH_KEY" ]; then
    echo "Configuring Tailscale..."
    
    # Create Tailscale state directory (persistent across restarts)
    sudo mkdir -p /var/lib/tailscale 2>/dev/null || true
    sudo chmod 755 /var/lib/tailscale 2>/dev/null || true
    
    # Start tailscaled in userspace-networking mode (works in containers without host network)
    # This allows Tailscale to work in Docker containers
    if ! pgrep -f tailscaled >/dev/null 2>&1; then
        echo "Starting Tailscale daemon..."
        # Use userspace-networking mode for container compatibility
        # --tun=userspace-networking: Use userspace networking instead of TUN device
        # --state: Persistent state file location
        # Create log file with proper permissions
        sudo touch /var/log/tailscaled.log
        sudo chmod 666 /var/log/tailscaled.log
        sudo tailscaled --state=/var/lib/tailscale/tailscaled.state --tun=userspace-networking >>/var/log/tailscaled.log 2>&1 &
        TAILSCALED_PID=$!
        sleep 3
        
        # Authenticate with provided auth key
        echo "Authenticating Tailscale..."
        sudo tailscale up \
            --authkey="$TAILSCALE_AUTH_KEY" \
            --accept-routes=false \
            --accept-dns=false \
            --hostname=devbox \
            2>&1 | tee -a /var/log/tailscaled.log || echo "Warning: Tailscale authentication failed"
        
        # Wait a moment for connection
        sleep 2
        
        # Show Tailscale status
        echo "Tailscale status:"
        sudo tailscale status 2>&1 | head -10 || echo "Tailscale connecting..."
        
        # Test connectivity to Tailscale hosts
        echo "Testing Tailscale connectivity..."
        ping -c 1 -W 2 100.109.213.78 >/dev/null 2>&1 && echo "  ✓ tower (100.109.213.78) reachable" || echo "  ✗ tower (100.109.213.78) not reachable"
        ping -c 1 -W 2 100.71.3.26 >/dev/null 2>&1 && echo "  ✓ instance (100.71.3.26) reachable" || echo "  ✗ instance (100.71.3.26) not reachable"
    else
        echo "Tailscale daemon already running"
        sudo tailscale status 2>&1 | head -5 || echo "Tailscale status unavailable"
    fi
else
    echo "Tailscale not configured (TAILSCALE_AUTH_KEY not set)"
    echo "  To enable Tailscale, set TAILSCALE_AUTH_KEY in your .env file"
fi

# Configure and start SSH server for local terminal access
echo "Configuring SSH server..."
sudo mkdir -p /var/run/sshd 2>/dev/null || true

# Use persistent SSH host keys if they exist, otherwise generate new ones
if [ -d /etc/ssh/keys ] && [ -n "$(ls -A /etc/ssh/keys/* 2>/dev/null)" ]; then
    echo "Using existing SSH host keys..."
    sudo cp /etc/ssh/keys/* /etc/ssh/ 2>/dev/null || true
    sudo chmod 600 /etc/ssh/ssh_host_*_key 2>/dev/null || true
    sudo chmod 644 /etc/ssh/ssh_host_*_key.pub 2>/dev/null || true
    sudo chown root:root /etc/ssh/ssh_host_* 2>/dev/null || true
else
    echo "Generating new SSH host keys..."
    sudo ssh-keygen -A 2>/dev/null || true
    # Save host keys to persistent volume for future container starts
    if [ -d /etc/ssh/keys ]; then
        sudo cp /etc/ssh/ssh_host_* /etc/ssh/keys/ 2>/dev/null || true
    fi
fi

# Set up SSH for dev user
# Copy public keys to writable authorized_keys location (since .ssh mount is read-only)
mkdir -p /home/dev/.ssh-local 2>/dev/null || true
chmod 700 /home/dev/.ssh-local 2>/dev/null || true

# Copy any public keys from mounted .ssh to writable location
if [ -d /home/dev/.ssh ] && ls /home/dev/.ssh/*.pub 1> /dev/null 2>&1; then
    cat /home/dev/.ssh/*.pub > /home/dev/.ssh-local/authorized_keys 2>/dev/null || true
fi

# Also copy existing authorized_keys if it exists
if [ -f /home/dev/.ssh/authorized_keys ]; then
    cat /home/dev/.ssh/authorized_keys >> /home/dev/.ssh-local/authorized_keys 2>/dev/null || true
fi

# Set permissions
chmod 600 /home/dev/.ssh-local/authorized_keys 2>/dev/null || true
chown -R dev:dev /home/dev/.ssh-local 2>/dev/null || true

# Configure SSH to use the writable authorized_keys location
sudo mkdir -p /etc/ssh/sshd_config.d 2>/dev/null || true
echo "AuthorizedKeysFile /home/dev/.ssh-local/authorized_keys /home/dev/.ssh/authorized_keys" | sudo tee /etc/ssh/sshd_config.d/devbox.conf > /dev/null 2>&1 || true

# Set dev user password to empty (allows SSH key auth)
# For password auth, user can set password manually: docker exec -it devbox sudo passwd dev

# Start SSH daemon in background
echo "Starting SSH server on port 22..."
sudo /usr/bin/sshd -D -e 2>&1 &
SSH_PID=$!

# Wait a moment for SSH to start
sleep 2

echo ""
echo "╔════════════════════════════════════════╗"
echo "║          Starting Web Terminal         ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "Access options:"
echo "  - SSH:     ssh dev@localhost -p 22"
echo "  - Web UI:  http://localhost:7681"
echo "Each new browser tab creates a new session."
echo ""

# Start ttyd in writable mode (-W) which spawns new-session.sh for each connection
# -W: Allow clients to write to the terminal
# -p 7681: Listen on port 7681
# Font settings: Nice modern fonts with good ligature support
# Color theme: Dracula (dark theme with nice colors)
exec ttyd \
    -W \
    -p 7681 \
    -t fontSize=14 \
    -t 'fontFamily="Cascadia Code", "SF Mono", "Monaco", "Inconsolata", "Fira Code", "JetBrains Mono", "Consolas", "Liberation Mono", monospace' \
    -t 'theme={"background":"#282A36","foreground":"#F8F8F2","cursor":"#F8F8F2","selectionBackground":"#44475A","black":"#21222C","red":"#FF5555","green":"#50FA7B","yellow":"#F1FA8C","blue":"#BD93F9","magenta":"#FF79C6","cyan":"#8BE9FD","white":"#F8F8F2","brightBlack":"#6272A4","brightRed":"#FF6E6E","brightGreen":"#69FF94","brightYellow":"#FFFFA5","brightBlue":"#D6ACFF","brightMagenta":"#FF92DF","brightCyan":"#A4FFFF","brightWhite":"#FFFFFF"}' \
    -t cursorStyle=underline \
    -t cursorBlink=true \
    /usr/local/bin/new-session.sh
