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

# ── Symlink Copilot plugin skills into .github/skills/ for auto-discovery ──
PLUGIN_DIR="/home/vscode/.copilot/installed-plugins"
SKILLS_DIR="/workspaces/pyspark-sjd-devops-dailyetl/.github/skills"

if [ -d "$PLUGIN_DIR" ]; then
    find "$PLUGIN_DIR" -name SKILL.md -path '*/skills/*/SKILL.md' | while read -r skill_md; do
        skill_folder=$(dirname "$skill_md")
        skill_name=$(basename "$skill_folder")
        target="$SKILLS_DIR/$skill_name"
        if [ ! -e "$target" ]; then
            ln -s "$skill_folder" "$target"
            echo "Linked skill: $skill_name -> $skill_folder"
        fi
    done
fi

echo "post-create.sh complete"
