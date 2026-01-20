#!/bin/bash
# new-session.sh - Creates a new tmux session with project selection
# Called by ttyd for each new browser connection

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${CYAN}"
echo "╔════════════════════════════════════════╗"
echo "║       Dev Container - Session Setup    ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

# Find all directories in /workspace (max depth 1, excluding hidden dirs and .git)
# This includes both git repos and regular project directories
PROJECTS=$(find /workspace -maxdepth 1 -mindepth 1 -type d ! -name ".*" 2>/dev/null | sort)

# Add option to create new project or use workspace root
OPTIONS="[New Project]\n[Workspace Root]\n${PROJECTS}"

# Check if there are any projects
if [ -z "$PROJECTS" ]; then
    echo -e "${BLUE}No existing projects found in /workspace${NC}"
    OPTIONS="[New Project]\n[Workspace Root]"
fi

echo -e "${GREEN}Select a project to work on:${NC}\n"

# Use fzf to select project
SELECTED=$(echo -e "$OPTIONS" | fzf \
    --prompt="Project: " \
    --height=60% \
    --layout=reverse \
    --border=rounded \
    --header="Use arrow keys to navigate, Enter to select" \
    --preview='if [[ {} == "[New Project]" ]]; then 
        echo "Create a new project directory"
    elif [[ {} == "[Workspace Root]" ]]; then 
        echo "Work in /workspace root"
        ls -la /workspace 2>/dev/null || echo "Empty workspace"
    else 
        echo "Project: {}"
        echo ""
        if [ -f "{}/README.md" ]; then
            head -20 "{}/README.md"
        elif [ -f "{}/package.json" ]; then
            echo "package.json:"
            cat "{}/package.json" | head -15
        else
            ls -la "{}" 2>/dev/null
        fi
    fi' \
    --preview-window=right:50%:wrap)

# Handle selection
case "$SELECTED" in
    "[New Project]")
        echo -e "${CYAN}Enter new project name:${NC}"
        read -r PROJECT_NAME
        if [ -z "$PROJECT_NAME" ]; then
            echo -e "${RED}No project name provided. Using workspace root.${NC}"
            PROJECT_DIR="/workspace"
            PROJECT_NAME="workspace"
        else
            PROJECT_DIR="/workspace/$PROJECT_NAME"
            mkdir -p "$PROJECT_DIR"
            echo -e "${GREEN}Created project directory: $PROJECT_DIR${NC}"
        fi
        ;;
    "[Workspace Root]")
        PROJECT_DIR="/workspace"
        PROJECT_NAME="workspace"
        ;;
    "")
        echo -e "${RED}No selection made. Exiting.${NC}"
        exit 1
        ;;
    *)
        PROJECT_DIR="$SELECTED"
        PROJECT_NAME=$(basename "$PROJECT_DIR")
        ;;
esac

# Docker host/context selection
echo -e "${GREEN}Select Docker connection:${NC}\n"

# Build Docker connection options
DOCKER_OPTIONS="Docker-in-Docker (Local)|tcp://dind:2375"

# Get available Docker contexts (skip default and empty contexts)
if command -v docker &> /dev/null; then
    CONTEXTS=$(docker context ls --format "{{.Name}}" 2>/dev/null | grep -v "^default$" || true)
    if [ -n "$CONTEXTS" ]; then
        while IFS= read -r context; do
            # Get context endpoint
            endpoint=$(docker context inspect "$context" --format '{{.Endpoints.docker.Host}}' 2>/dev/null || echo "N/A")
            DOCKER_OPTIONS="${DOCKER_OPTIONS}\n${context}|${endpoint}"
        done <<< "$CONTEXTS"
    fi
fi

# Use fzf to select Docker connection
DOCKER_SELECTED=$(echo -e "$DOCKER_OPTIONS" | fzf \
    --prompt="Docker: " \
    --height=50% \
    --layout=reverse \
    --border=rounded \
    --header="Use arrow keys to navigate, Enter to select" \
    --delimiter="|" \
    --with-nth=1 \
    --preview='echo "Docker Connection: {1}"
echo "Endpoint: {2}"' \
    --preview-window=right:50%:wrap)

if [ -z "$DOCKER_SELECTED" ]; then
    echo -e "${RED}No Docker connection selected. Using default (DinD).${NC}"
    DOCKER_HOST="tcp://dind:2375"
    DOCKER_CONTEXT=""
else
    DOCKER_NAME=$(echo "$DOCKER_SELECTED" | cut -d'|' -f1)
    DOCKER_ENDPOINT=$(echo "$DOCKER_SELECTED" | cut -d'|' -f2)
    
    if [[ "$DOCKER_NAME" == "Docker-in-Docker (Local)" ]]; then
        DOCKER_HOST="$DOCKER_ENDPOINT"
        DOCKER_CONTEXT=""
        echo -e "${GREEN}Selected: ${DOCKER_NAME}${NC}"
        echo -e "${BLUE}Endpoint: ${DOCKER_ENDPOINT}${NC}"
    else
        # Use Docker context endpoint via DOCKER_HOST (per-session, not global)
        # Always extract endpoint directly from context name for reliability
        echo -e "${GREEN}Selected context: ${DOCKER_NAME}${NC}"
        echo -e "${CYAN}Extracting endpoint from context...${NC}"
        
        # Try to get endpoint from the context
        echo -e "${CYAN}Inspecting context '$DOCKER_NAME'...${NC}"
        EXTRACTED_ENDPOINT=$(docker context inspect "$DOCKER_NAME" --format '{{.Endpoints.docker.Host}}' 2>/dev/null || echo "")
        echo -e "${CYAN}  Extracted endpoint: '${EXTRACTED_ENDPOINT}'${NC}"
        echo -e "${CYAN}  Endpoint from selection: '${DOCKER_ENDPOINT}'${NC}"
        
        # Use extracted endpoint if valid, otherwise fall back to endpoint from selection list
        if [ -n "$EXTRACTED_ENDPOINT" ] && [ "$EXTRACTED_ENDPOINT" != "N/A" ] && [ "$EXTRACTED_ENDPOINT" != "<no value>" ] && [ "$EXTRACTED_ENDPOINT" != "" ]; then
            DOCKER_HOST="$EXTRACTED_ENDPOINT"
            echo -e "${BLUE}✓ Using endpoint extracted from context: ${EXTRACTED_ENDPOINT}${NC}"
        elif [ -n "$DOCKER_ENDPOINT" ] && [ "$DOCKER_ENDPOINT" != "N/A" ] && [ "$DOCKER_ENDPOINT" != "<no value>" ] && [ "$DOCKER_ENDPOINT" != "" ]; then
            echo -e "${YELLOW}⚠ Using endpoint from selection list: ${DOCKER_ENDPOINT}${NC}"
            DOCKER_HOST="$DOCKER_ENDPOINT"
        else
            echo -e "${RED}✗ ERROR: Could not extract endpoint from context '$DOCKER_NAME'${NC}"
            echo -e "${RED}  Extracted: '${EXTRACTED_ENDPOINT}'${NC}"
            echo -e "${RED}  From selection: '${DOCKER_ENDPOINT}'${NC}"
            echo -e "${RED}  Falling back to default Docker-in-Docker${NC}"
            DOCKER_HOST="tcp://dind:2375"
        fi
        
        # Ensure DOCKER_HOST uses tcp:// protocol
        if [[ ! "$DOCKER_HOST" =~ ^tcp:// ]] && [[ ! "$DOCKER_HOST" =~ ^unix:// ]] && [[ ! "$DOCKER_HOST" =~ ^ssh:// ]]; then
            DOCKER_HOST="tcp://${DOCKER_HOST#tcp://}"
        fi
        
        DOCKER_CONTEXT=""
    fi
fi

echo ""

# Generate unique session name using project name and PID
SESSION_NAME="${PROJECT_NAME}-$$"

echo -e "${GREEN}Starting session: ${SESSION_NAME}${NC}"
echo -e "${BLUE}Project directory: ${PROJECT_DIR}${NC}"

# Determine Docker connection settings
# Always use DOCKER_HOST environment variable (per-session, not global)
if [ -z "$DOCKER_HOST" ]; then
    DOCKER_HOST="tcp://dind:2375"
fi
export DOCKER_HOST

# Debug: Show which Docker endpoint will be used
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo -e "${CYAN}Docker Configuration:${NC}"
echo -e "${CYAN}  DOCKER_HOST will be set to: ${DOCKER_HOST}${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""

# Verify DOCKER_HOST is set correctly before proceeding
if [ -z "$DOCKER_HOST" ]; then
    echo -e "${RED}ERROR: DOCKER_HOST is empty!${NC}"
    exit 1
fi

# Ensure TERM is set to a valid value for tmux (fixes "xterm-ghostty" issue)
export TERM="${TERM:-screen-256color}"
if [[ "$TERM" == *"ghostty"* ]] || [[ "$TERM" == *"unknown"* ]]; then
    export TERM="screen-256color"
fi

# Create tmux session with windows
# Window 0: shell
# Always use DOCKER_HOST environment variable (per-session, not global)
# Set DOCKER_HOST in tmux environment AND ensure it's exported in shell
tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_DIR" -n "shell" \
    -e "DOCKER_HOST=$DOCKER_HOST" \
    -e "DOCKER_CONTEXT=" \
    -e "TERM=$TERM"

# Set DOCKER_HOST in shell window and show connection info
# Use a more persistent method: create a .docker_env file and source it
# IMPORTANT: Switch to "default" context so Docker uses DOCKER_HOST instead of active context
DOCKER_ENV_FILE="/tmp/docker_env_${SESSION_NAME}.sh"
cat > "$DOCKER_ENV_FILE" << 'ENVEOF'
# Docker environment for session - switch to default context first
# This ensures Docker uses DOCKER_HOST instead of active context
docker context use default >/dev/null 2>&1 || true
ENVEOF
cat >> "$DOCKER_ENV_FILE" << EOF
# Set DOCKER_HOST - this takes precedence over context
# IMPORTANT: DOCKER_HOST must be set BEFORE any docker commands
export DOCKER_HOST='$DOCKER_HOST'
unset DOCKER_CONTEXT
# Verify DOCKER_HOST is set correctly
if [ -z "\$DOCKER_HOST" ]; then
    echo "ERROR: DOCKER_HOST is not set!" >&2
    exit 1
fi
# Switch to default context to avoid conflicts (DOCKER_HOST will still take precedence)
docker context use default >/dev/null 2>&1 || true
EOF
chmod 644 "$DOCKER_ENV_FILE"

# Source the env file in shell and show connection info
# Add to .bashrc to ensure it's sourced on every new shell in this session
BASHRC_SESSION_FILE="$HOME/.bashrc_session_${SESSION_NAME}"
echo "source '$DOCKER_ENV_FILE'" > "$BASHRC_SESSION_FILE"
if ! grep -q "source.*bashrc_session_${SESSION_NAME}" ~/.bashrc 2>/dev/null; then
    echo "[ -f \"$BASHRC_SESSION_FILE\" ] && source \"$BASHRC_SESSION_FILE\"" >> ~/.bashrc 2>/dev/null || true
fi

# Create a docker wrapper function to ensure DOCKER_HOST is always set
# This ensures DOCKER_HOST is set even if the env file wasn't sourced
DOCKER_WRAPPER_FILE="/tmp/docker_wrapper_${SESSION_NAME}.sh"
cat > "$DOCKER_WRAPPER_FILE" << EOF
# Docker wrapper to ensure DOCKER_HOST is always set
docker() {
    # Source the env file if DOCKER_HOST is not set
    if [ -z "\$DOCKER_HOST" ] && [ -f "$DOCKER_ENV_FILE" ]; then
        source "$DOCKER_ENV_FILE" 2>/dev/null || true
    fi
    # Call the real docker command
    command docker "\$@"
}
EOF
chmod 644 "$DOCKER_WRAPPER_FILE"
# Add wrapper to .bashrc so it's available in all shells
if ! grep -q "source.*docker_wrapper_${SESSION_NAME}" ~/.bashrc 2>/dev/null; then
    echo "source '$DOCKER_WRAPPER_FILE' 2>/dev/null || true" >> ~/.bashrc 2>/dev/null || true
fi

# Create initialization script to set up Docker environment (silently)
DOCKER_INIT_SCRIPT="/tmp/docker_init_${SESSION_NAME}.sh"
cat > "$DOCKER_INIT_SCRIPT" << EOF
#!/bin/bash
# Initialize Docker environment
source '$DOCKER_ENV_FILE' 2>/dev/null || true
source '$DOCKER_WRAPPER_FILE' 2>/dev/null || true
EOF
chmod +x "$DOCKER_INIT_SCRIPT"

# Execute the initialization script silently
tmux send-keys -t "$SESSION_NAME:shell" "$DOCKER_INIT_SCRIPT" Enter

# Window 1: nvim
tmux new-window -t "$SESSION_NAME" -n "nvim" -c "$PROJECT_DIR"
tmux send-keys -t "$SESSION_NAME:nvim" "source '$DOCKER_ENV_FILE' && nvim ." Enter

# Window 2: lazygit
tmux new-window -t "$SESSION_NAME" -n "lazygit" -c "$PROJECT_DIR"
tmux send-keys -t "$SESSION_NAME:lazygit" "source '$DOCKER_ENV_FILE' && lazygit" Enter

# Window 3: lazydocker
tmux new-window -t "$SESSION_NAME" -n "lazydocker"
tmux send-keys -t "$SESSION_NAME:lazydocker" "source '$DOCKER_ENV_FILE' && lazydocker" Enter

# Window 4: opencode
tmux new-window -t "$SESSION_NAME" -n "opencode" -c "$PROJECT_DIR"
# Ensure TERM is set to screen-256color for tmux compatibility and opencode can access config
tmux send-keys -t "$SESSION_NAME:opencode" "source '$DOCKER_ENV_FILE' && export TERM=screen-256color && export COLORTERM=truecolor && cd '$PROJECT_DIR' && opencode" Enter

# Select the shell window first
tmux select-window -t "$SESSION_NAME:shell"

# Attach to the session
exec tmux attach -t "$SESSION_NAME"
