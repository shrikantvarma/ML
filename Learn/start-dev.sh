#!/bin/bash
# Start research dev container with Claude Code
# Works with Docker Desktop or OrbStack

set -e

IMAGE="mcr.microsoft.com/devcontainers/python:3.12"
CONTAINER_NAME="research-dev"

# Stop existing container if running
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo "Starting research container..."
docker run -it \
  --name "$CONTAINER_NAME" \
  --user vscode \
  -v "$(pwd):/workspace" \
  -v "$HOME/.claude:/home/vscode/.claude" \
  -v "$HOME/.claude.json:/home/vscode/.claude.json" \
  -e PROJECT_NAME="Research" \
  -w /workspace \
  "$IMAGE" \
  bash -c '
    echo "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - > /dev/null 2>&1
    sudo apt-get install -y -qq nodejs > /dev/null 2>&1

    echo "Installing Claude Code..."
    sudo npm install -g @anthropic-ai/claude-code > /dev/null 2>&1

    echo "Upgrading pip..."
    pip install --upgrade pip -q > /dev/null 2>&1

    echo ""
    echo "================================================"
    echo "  Research container ready!"
    echo "  Run: claude --dangerously-skip-permissions"
    echo "================================================"
    echo ""
    exec bash
  '
