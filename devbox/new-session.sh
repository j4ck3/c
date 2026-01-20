#!/bin/bash
# new-session.sh - Creates a new tmux session with project selection
# Called by ttyd for each new browser connection

# Don't exit on error - handle errors gracefully
set +e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
    else
        # Use Docker context
        DOCKER_CONTEXT="$DOCKER_NAME"
        DOCKER_HOST=""
    fi
    
    echo -e "${GREEN}Selected: ${DOCKER_NAME}${NC}"
    if [ -n "$DOCKER_ENDPOINT" ] && [ "$DOCKER_ENDPOINT" != "N/A" ]; then
        echo -e "${BLUE}Endpoint: ${DOCKER_ENDPOINT}${NC}"
    fi
fi

echo ""

# Generate unique session name using project name and PID
SESSION_NAME="${PROJECT_NAME}-$$"

echo -e "${GREEN}Starting session: ${SESSION_NAME}${NC}"
echo -e "${BLUE}Project directory: ${PROJECT_DIR}${NC}"

# Determine Docker connection settings
if [ -n "$DOCKER_HOST" ]; then
    echo -e "${BLUE}Docker: Using DOCKER_HOST=$DOCKER_HOST${NC}"
    DOCKER_ENV="DOCKER_HOST=$DOCKER_HOST"
elif [ -n "$DOCKER_CONTEXT" ]; then
    echo -e "${BLUE}Docker: Using context $DOCKER_CONTEXT${NC}"
    # Switch to the context now
    docker context use "$DOCKER_CONTEXT" >/dev/null 2>&1 || echo -e "${RED}Warning: Could not set Docker context${NC}"
    DOCKER_ENV=""
else
    # Fallback to DinD
    echo -e "${BLUE}Docker: Using default DinD${NC}"
    DOCKER_HOST="tcp://dind:2375"
    DOCKER_ENV="DOCKER_HOST=$DOCKER_HOST"
fi

echo ""

# Create tmux session
echo "Creating tmux session..."
tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_DIR" -n "shell"
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create tmux session${NC}"
    exit 1
fi

# Set environment in the shell window
if [ -n "$DOCKER_ENV" ]; then
    tmux send-keys -t "$SESSION_NAME:shell" "export $DOCKER_ENV" Enter
fi

# Window 1: nvim
tmux new-window -t "$SESSION_NAME" -n "nvim" -c "$PROJECT_DIR"
tmux send-keys -t "$SESSION_NAME:nvim" "nvim ." Enter

# Window 2: lazygit
tmux new-window -t "$SESSION_NAME" -n "lazygit" -c "$PROJECT_DIR"
tmux send-keys -t "$SESSION_NAME:lazygit" "lazygit" Enter

# Window 3: lazydocker
tmux new-window -t "$SESSION_NAME" -n "lazydocker"
if [ -n "$DOCKER_ENV" ]; then
    tmux send-keys -t "$SESSION_NAME:lazydocker" "export $DOCKER_ENV && lazydocker" Enter
else
    tmux send-keys -t "$SESSION_NAME:lazydocker" "lazydocker" Enter
fi

# Window 4: opencode
tmux new-window -t "$SESSION_NAME" -n "opencode" -c "$PROJECT_DIR"
# Ensure TERM is set to screen-256color for tmux compatibility and opencode can access config
tmux send-keys -t "$SESSION_NAME:opencode" "export TERM=screen-256color && export COLORTERM=truecolor && cd $PROJECT_DIR && opencode" Enter

# Select the shell window first
tmux select-window -t "$SESSION_NAME:shell"

# Attach to the session
exec tmux attach -t "$SESSION_NAME"
