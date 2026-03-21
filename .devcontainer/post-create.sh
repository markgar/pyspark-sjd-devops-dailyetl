#!/usr/bin/env bash
# post-create.sh — runs as vscode user after the dev container is created.
# Clones dev-loop into /opt, installs Copilot CLI plugins, and marks
# git safe directories.  Idempotent: safe to re-run on rebuilds.
set -euo pipefail

REPOS=(
    "markgar/dev-loop       /opt/dev-loop"
)

for entry in "${REPOS[@]}"; do
    repo=$(echo "$entry" | awk '{print $1}')
    dest=$(echo "$entry" | awk '{print $2}')

    # Create parent dir owned by vscode so clone doesn't need sudo
    if [ ! -d "$dest" ]; then
        sudo mkdir -p "$dest"
        sudo chown "$(id -u):$(id -g)" "$dest"
    fi

    # Clone if not already present (git uses VS Code's built-in credential forwarding)
    if [ ! -d "$dest/.git" ]; then
        git clone "https://github.com/${repo}.git" "$dest"
    else
        echo "$dest already cloned — pulling latest"
        git -C "$dest" pull --ff-only || true
    fi

    # Ensure ownership
    sudo chown -R "$(id -u):$(id -g)" "$dest"

    # Mark as safe directory for git
    git config --global --add safe.directory "$dest"
done

# Install GitHub Copilot CLI extension (needed by dev-loop)
if ! gh extension list 2>/dev/null | grep -q gh-copilot; then
    echo "Installing gh-copilot extension ..."
    gh extension install github/gh-copilot
else
    echo "gh-copilot extension already installed"
fi

# Install SSIS migration analysis plugins for Copilot CLI
echo "Installing ssis-migration plugins ..."
copilot plugin marketplace add markgar/ssis-migration
copilot plugin install ssis-analyzer@ssis-migration
copilot plugin install dacpac-analyzer@ssis-migration

echo "post-create.sh complete"
