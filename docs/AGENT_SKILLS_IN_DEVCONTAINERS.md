# Agent Skills in Dev Containers

> **Date written**: March 2026
> **Status**: Workaround in place. Revisit after VS Code 1.114+.

## TL;DR

Four things make host-installed agent skills work inside a dev container:

**0. Install skills via Copilot CLI on your host machine:**
```bash
copilot plugin install <owner>/<repo>          # marketplace plugin
copilot plugin install --direct <owner>/<repo> # direct from GitHub
```
This puts skills in `~/.copilot/installed-plugins/`, which is the directory we mount into the container. Skills installed via the **VS Code marketplace UI** land in a different path (`agentPlugins/`) that is **not** mounted — use the CLI.

**1. Mount host skill directories** — add to `devcontainer.json`:
```json
"mounts": [
  "source=${localEnv:HOME}/.agents/skills,target=/home/vscode/.agents/skills,type=bind,readonly",
  "source=${localEnv:HOME}/.copilot,target=/home/vscode/.copilot,type=bind,readonly"
]
```

**2. Grant read access** — add to `devcontainer.json` settings:
```json
"github.copilot.chat.additionalReadAccessFolders": [
  "/home/vscode/.agents/skills",
  "/home/vscode/.copilot"
]
```

**3. Symlink plugin skills for discovery** — add to `post-create.sh`:
```bash
PLUGIN_DIR="/home/vscode/.copilot/installed-plugins"
SKILLS_DIR="<your-workspace>/.github/skills"

if [ -d "$PLUGIN_DIR" ]; then
    find "$PLUGIN_DIR" -name SKILL.md -path '*/skills/*/SKILL.md' | while read -r skill_md; do
        skill_folder=$(dirname "$skill_md")
        skill_name=$(basename "$skill_folder")
        target="$SKILLS_DIR/$skill_name"
        if [ ! -e "$target" ]; then
            ln -s "$skill_folder" "$target"
        fi
    done
fi
```

Add a `.github/skills/.gitignore` to keep symlinks out of version control (whitelist only your repo-native skills). Rebuild the container once after setup.

> **Windows users:** `${localEnv:HOME}` may not be set. Add `HOME=%USERPROFILE%` as a system environment variable, or the mounts will silently fail.

---

## The Problem

[Agent Skills](https://agentskills.io/) are an open standard for giving AI agents specialized capabilities. Skills are folders containing a `SKILL.md` file with instructions that agents discover and load on demand. The standard is supported by VS Code Copilot, Copilot CLI, Claude Code, Amp, Goose, Databricks, and [many others](https://agentskills.io/home).

Skills are installed on the **host machine** (e.g., `~/.agents/skills/`). When you develop inside a **dev container**, the container has its own filesystem — it can't see the host's skills. AI agents inside the container have no skills to work with.

## Background: How Skills Are Distributed

Skills can be published via the Copilot plugin marketplace and installed several ways. The install method determines where the skills land on disk:

| Source | Location |
|---|---|
| **Marketplace plugins** (installed via Copilot CLI) | `~/.copilot/installed-plugins/<plugin>/` |
| **Direct repo installs** (via Copilot CLI) | `~/.copilot/installed-plugins/_direct/<owner--repo>/` |
| **Personal skills** (hand-authored) | `~/.copilot/skills/` |
| **Platform built-ins** (bundled with Copilot) | `~/.agents/skills/` |
| **VS Code marketplace UI** | `~/Library/Application Support/Code/agentPlugins/` (macOS) or `%APPDATA%\Code\agentPlugins\` (Windows) |

### Key detail: `~/.copilot/` is the Copilot CLI home

The `~/.copilot/` directory is Copilot CLI's home directory (overridable via `COPILOT_HOME`). It stores config, MCP server definitions, installed plugins, and personal skills. The structure:

```
~/.copilot/
├── config.json              # CLI configuration
├── mcp-config.json          # MCP server definitions
├── ide/                     # IDE-specific state
├── installed-plugins/       # Marketplace & direct installs
│   ├── <plugin-name>/       # Marketplace plugin (extracted, no .git/)
│   └── _direct/             # Direct installs (full git clones)
│       └── <owner--repo>/
├── marketplace-cache/       # Cache for marketplace plugin sources
└── skills/                  # Personal hand-authored skills
```

The `~/.agents/skills/` path is the [Agent Skills specification](https://agentskills.io/specification) cross-client standard. The Azure/Microsoft skills there are platform built-ins — not installed via any marketplace. They are discovered by all compliant clients (Copilot CLI, Claude Code, Amp, Goose, etc.).

### Marketplace vs direct plugin installs

Both plugin types are installed from within Copilot CLI and both land under `~/.copilot/installed-plugins/`, but they differ in how they handle the source repo:

| | Marketplace | Direct |
|---|---|---|
| **Install command** | `/plugin install <owner>/<repo>` | `/plugin install --direct <owner>/<repo>` |
| **Has `plugin.json`** | No (managed by marketplace) | Yes (declares metadata, author, skills) |
| **Repo clone location** | `~/.copilot/marketplace-cache/` | `~/.copilot/installed-plugins/_direct/<owner--repo>/` |
| **Extracted skills** | Copied to `installed-plugins/<plugin-name>/` | Same folder as clone |
| **Has `.git/` in installed-plugins** | No | Yes |
| **Update mechanism** | Marketplace sync | Git pull |

**Marketplace** install is a two-step process:

1. Clones the repo to `~/.copilot/marketplace-cache/<url-encoded-repo>/` (e.g., `https---github-com-owner-repo/`)
2. Extracts just the skills and config into `~/.copilot/installed-plugins/<plugin-name>/` — no `.git/`, just the files needed

**Direct** install clones the repo in place:

1. Clones the entire repo (with `.git/` and all) directly into `~/.copilot/installed-plugins/_direct/<owner--repo>/`

Both are covered by a single `~/.copilot` mount in `devcontainer.json`.

## The Dev Container Gap

### Three AI clients, one container

Inside a dev container, you may run:

1. **VS Code Copilot** — discovers skills on the host, model reads files inside the container
2. **Copilot CLI (`ghcp`)** — runs entirely inside the container, scans `~/.agents/skills/`
3. **Claude Code** — runs entirely inside the container, scans `~/.agents/skills/` and `~/.claude/skills/`

### What goes wrong

- **No skills exist inside the container** — the host's `~/.agents/skills/` is a different filesystem
- **VS Code injects absolute host paths** — for UI-installed skills, VS Code tells the model to read `/Users/yourname/Library/Application Support/Code/agentPlugins/...` which doesn't exist inside the Linux container
- **VS Code UI-installed skills are invisible to other clients** — even on the host, Copilot CLI and Claude Code don't scan the `agentPlugins` path

### VS Code's split architecture makes this worse

VS Code runs across both host and container:

| Component | Runs where | Path space |
|---|---|---|
| Skill discovery (plugin scanning) | **Host** | Host paths |
| Skill path injected into prompt | From **host** discovery | Host path string |
| `read_file` tool call | **Container** (VS Code Server) | Container filesystem |

Skills are discovered on the host with host paths, but read inside the container where those paths don't exist.

## The Workaround

### Step 1: Mount in devcontainer.json

Add this to your `devcontainer.json`:

```json
"mounts": [
  "source=${localEnv:HOME}/.agents/skills,target=/home/vscode/.agents/skills,type=bind,readonly",
  "source=${localEnv:HOME}/.copilot,target=/home/vscode/.copilot,type=bind,readonly"
]
```

This bind-mounts both skill directories from the host into the container:

| Mount | What it brings in |
|---|---|
| `~/.agents/skills/` | Platform built-in skills (Azure, Microsoft Foundry, etc.) |
| `~/.copilot/` | Marketplace plugins, direct installs, personal skills, CLI config |

- `${localEnv:HOME}` resolves to each developer's home directory (no hardcoded usernames)
- `readonly` because skills shouldn't be modified from inside the container
- If a developer doesn't have either directory, the mount source doesn't exist and the container starts normally

Also add `additionalReadAccessFolders` so the model can read skill scripts inside the mounted paths:

```json
"settings": {
  "github.copilot.chat.additionalReadAccessFolders": [
    "/home/vscode/.agents/skills",
    "/home/vscode/.copilot"
  ]
}
```

### Step 2: Install skills via Copilot CLI on the host

Install skills using the Copilot CLI **on your host machine** so they land in `~/.copilot/installed-plugins/`:

```bash
copilot plugin install <owner>/<repo>
```

This installs the plugin into `~/.copilot/installed-plugins/<plugin-name>/`. Each plugin can contain multiple skills, each with their own `skills/<name>/SKILL.md`. The bind mount from Step 1 makes these files visible inside the container automatically.

### Step 3: Symlink plugin skills into `.github/skills/` for discovery

The bind mounts make skill files readable inside the container, but VS Code only auto-discovers skills from certain paths — including `.github/skills/` inside the workspace. Marketplace plugins under `~/.copilot/installed-plugins/` have a deeply nested layout that VS Code's scanner doesn't traverse.

The solution is to create symlinks in `.github/skills/` (a path VS Code reliably scans) pointing to each skill's folder inside the mounted `~/.copilot/installed-plugins/`. This is done automatically by `post-create.sh`:

```bash
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
```

This finds every `SKILL.md` under the installed-plugins tree and symlinks that skill's folder into `.github/skills/<skill-name>`. It's idempotent — existing folders (like repo-native skills) are skipped.

To keep the symlinked skills out of git, a `.github/skills/.gitignore` ignores everything except explicitly tracked repo-native skills:

```gitignore
# Ignore symlinked plugin skills (created by post-create.sh).
# Repo-native skills are tracked explicitly via git add -f.
*
!.gitignore
!fabric-ops/
!fabric-ops/**
!local-spark/
!local-spark/**
```

### Why not `chat.agentSkillsLocations`?

> **Tested and failed (March 2026).** The `chat.agentSkillsLocations` VS Code setting was the first approach tried. Even after a full container rebuild with the setting applied, skills under `~/.copilot/installed-plugins/` were not discovered. The likely cause is that the scanner does not recurse deeply enough — plugin skills are 3-4 levels deep (`installed-plugins/<plugin>/<sub>/skills/<name>/SKILL.md`).
>
> Additionally, `chat.agentSkillsLocations` has known path resolution bugs in WSL ([#301167](https://github.com/microsoft/vscode/issues/301167)) and Remote SSH ([#293768](https://github.com/microsoft/vscode/issues/293768)) contexts.
>
> The symlink approach bypasses all of this — it puts skills exactly where VS Code already knows to look.

### Why the mounts work

Both `~/.agents/skills/` and `~/.copilot/` are **relative to home**. Inside the container, `~` is `/home/vscode`. The mounts put skill files exactly where clients expect to find them. Both discovery and file reading happen in the container's path space — no host paths leak in.

Compare to VS Code UI-installed skills: VS Code discovers them on the host at an absolute path like `/Users/<username>/Library/Application Support/Code/agentPlugins/...`, injects that path into the prompt, and the model tries to read it inside the container where it doesn't exist.

## Known Limitations

### Windows

`${localEnv:HOME}` may not be set on Windows (Windows uses `USERPROFILE`). Developers on Windows may need to:

- Set `HOME` in their environment
- Or use `${localEnv:USERPROFILE}` in a separate mount (but you can't conditionally pick one in `devcontainer.json`)

This is currently a macOS/Linux solution. VS Code 1.114+ may improve the Windows story.

### VS Code UI-installed skills

Skills installed via the VS Code marketplace UI land in the `agentPlugins/` path (platform-specific), not in `~/.copilot/installed-plugins/` or `~/.agents/skills/`. They won't be picked up by either mount. Developers who install via the VS Code UI should also install via the Copilot CLI to get skills into `~/.copilot/installed-plugins/` where the mount makes them available.

> **Future option:** It's possible to also mount the `agentPlugins/` directory and extend the `post-create.sh` symlink script to scan it. The paths are OS-specific (`~/Library/Application Support/Code/agentPlugins/` on macOS, `%APPDATA%/Code/agentPlugins/` on Windows, `~/.config/Code/agentPlugins/` on Linux). The symlink script's `find` pattern already handles the plugin folder layout. This would let UI-installed skills work without needing the CLI — worth trying if the CLI-only workflow becomes a friction point.

### Container rebuilds

The mount is live — it reflects the current state of the host's `~/.agents/skills/` and `~/.copilot/` directories. No data is lost on container rebuild. The symlinks are recreated automatically by `post-create.sh` on every rebuild.

## VS Code Issues Tracking This

| Issue | Status (as of March 2026) | Summary |
|---|---|---|
| [#292297](https://github.com/microsoft/vscode/issues/292297) | Fixed (Feb 2026) | Skills outside workspace can now be read in WSL |
| [#298701](https://github.com/microsoft/vscode/issues/298701) | Fix committed, milestone 1.114 | Plugin install works in remote/WSL contexts |
| [#293768](https://github.com/microsoft/vscode/issues/293768) | Open, assigned | `chat.agentSkillsLocations` resolves on remote instead of local |
| [#301167](https://github.com/microsoft/vscode/issues/301167) | Open, assigned | `chat.pluginLocations` path resolution broken in remote |

### What VS Code 1.114 changes

[PR #303606](https://github.com/microsoft/vscode/pull/303606) ("agentPlugins: clone locally when in a remote") fixes **installing** marketplace plugins from the VS Code UI while inside a dev container, WSL, or SSH remote. Previously, the install silently failed in remote contexts.

After 1.114, a simple user flow is possible:

1. Open project in dev container
2. Install skills from the VS Code marketplace UI
3. Skills are cloned inside the container and work immediately

**Trade-offs of this approach:**
- Skills are stored inside the container filesystem — **lost on every container rebuild**
- The user must reinstall after each rebuild
- Only works for VS Code Copilot — Copilot CLI and Claude Code inside the container won't find them
- No persistence, no cross-client support

For users who tolerate reinstalling after rebuilds and only use VS Code Copilot, this is the simplest path. For anyone who wants persistence or cross-client support, the CLI install + mount remains the right approach.

### What 1.114 does NOT change

The broader path resolution issues ([#293768](https://github.com/microsoft/vscode/issues/293768), [#301167](https://github.com/microsoft/vscode/issues/301167)) — where already-installed host-side skills can't be read inside the container — are still open with no milestone. The mount workaround described above addresses this.

## Agent Skills Ecosystem Discussions

| Discussion | Summary |
|---|---|
| [agentskills #151](https://github.com/agentskills/agentskills/discussions/151) | Containerized CLI for skill scripts — isolation and portability |
| [agentskills #166](https://github.com/agentskills/agentskills/discussions/166) | Skill portability across operating systems |
| [agentskills #42](https://github.com/agentskills/agentskills/issues/42) | RFC: Remote Agent Skills — URL-based skill import (would eliminate filesystem dependency) |

## The Ideal Future

1. **VS Code marketplace UI** writes skills to `~/.copilot/installed-plugins/` (matching what Copilot CLI already does) instead of the VS Code-specific `agentPlugins/` path
2. **VS Code** properly resolves skill paths across the host→container boundary (1.114 partially addresses this)
3. **The mounts become the only thing needed** — two lines in `devcontainer.json` that make all skills available to all clients inside the container

## References

- [Agent Skills specification](https://agentskills.io/specification)
- [Agent Skills client implementation guide](https://agentskills.io/client-implementation/adding-skills-support) — specifically the "Cloud-hosted and sandboxed agents" section
- [GitHub Copilot CLI documentation](https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli)
- [Creating agent skills for GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-skills)
