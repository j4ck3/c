#!/bin/bash
# setup-docker-contexts.sh - Helper script to set up Docker contexts for Tailscale hosts
# Run this inside the devbox container after SSH keys are configured

set -e

echo "Setting up Docker contexts for Tailscale hosts..."

# Tower (100.109.213.78)
if ! docker context ls --format "{{.Name}}" | grep -q "^tower$"; then
    echo "Creating context for tower (100.109.213.78)..."
    if docker context create tower --docker "host=tcp://100.109.213.78:2375" --description "Tower server via Tailscale" 2>/dev/null; then
        echo "  ✓ Created context 'tower'"
    else
        echo "  ✗ Failed to create context 'tower'"
    fi
else
    echo "  Context 'tower' already exists, skipping..."
fi

# Instance (100.71.3.26)
if ! docker context ls --format "{{.Name}}" | grep -q "^instance-20251201-2024$"; then
    CONTEXT_NAME="instance-20251201-2024"
    echo "Creating context for $CONTEXT_NAME (100.71.3.26)..."
    if docker context create "$CONTEXT_NAME" --docker "host=tcp://100.71.3.26:2375" --description "Instance server via Tailscale" 2>/dev/null; then
        echo "  ✓ Created context '$CONTEXT_NAME'"
    else
        echo "  ✗ Failed to create context '$CONTEXT_NAME'"
    fi
else
    echo "  Context 'instance-20251201-2024' already exists, skipping..."
fi

echo ""
echo "Available Docker contexts:"
docker context ls

echo ""
echo "To use a context:"
echo "  docker context use tower"
echo "  docker context use instance-20251201-2024"
echo ""
echo "Or select from the menu when starting a new session in the devbox!"
