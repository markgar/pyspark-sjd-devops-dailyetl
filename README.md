# pyspark-sjd-devops

Local-first PySpark development environment for Microsoft Fabric Spark Job Definitions (SJDs), powered by a custom VS Code Copilot agent called **sjd-builder**.

## Why this exists

Most PySpark development on Fabric happens in online notebooks — editing code in a browser, waiting for clusters to start, running cells one at a time, no version control, no tests, no CI/CD. It works for exploration, but it gets difficult to manage when going to production. Notebooks carry a lot of ceremony — JSON wrappers, cell metadata, output blobs — and when something breaks at 2am, you're debugging in a browser with no commit history and no way to reproduce it locally.

**This repo lets you do spec-driven PySpark development.** Write a markdown spec describing your ETL pipeline. A custom Copilot agent called **sjd-builder** reads it, writes the code and tests, runs everything locally, then deploys to Fabric as a Spark Job Definition. You describe what you want; the agent builds it.

Two things make this possible:

1. **Python packages instead of notebooks.** What you might spread across multiple notebooks becomes modules in a single package — easy to navigate, easy to test, easy to review in a PR. The code is more readable and maintainable. Your production deliverable is a `.whl`, not a notebook. And because it's just Python files, the agent can read and write them naturally.

2. **Local dev is way faster than on Fabric.** A dev container mirrors Fabric Runtime 1.3 — Spark 3.5, Java 11, Delta Lake 3.2, JDBC drivers — so your code runs the same locally as it does on Fabric. No cluster startup wait, no browser IDE. The agent uses this fast local loop to iterate — write, test, fix, re-run — in seconds instead of minutes.

## Quick start

### Prerequisites

- A **Fabric workspace** with its workspace identity enabled (the sample specs use `pyspark-sjd-devops`).
- If your pipeline reads from a SQL database, grant the workspace identity **db_datareader** on that database (the sample specs use `wideworldimporters` — grab the [Standard bacpac](https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Standard.bacpac) from the [sql-server-samples](https://github.com/Microsoft/sql-server-samples/releases/tag/wide-world-importers-v1.0) repo and import it into Azure SQL).
- The sample specs reference specific item names (workspace, lakehouse, environment, SQL server/database). Review `sample_spec_set/CONSTITUTION.md` and update them to match your environment.

### Steps

1. **Open in the dev container** — VS Code will build the container with Spark, Delta, JDBC drivers, Azure CLI, and all Python dependencies pre-installed.

2. **Write a spec** — describe your ETL pipeline in markdown (see `sample_spec_set/` for the format).

3. **Build with sjd-builder** — select **sjd-builder** from the Copilot chat mode dropdown, then hand it one spec at a time:

   ![sjd-builder chat mode](docs/images/sjd-builder-chat-mode.png)
   ```
   implement sample_spec_set/01_people_to_csv.md
   implement sample_spec_set/02_csv_to_delta.md
   ```

   Or point it at the whole directory to build everything in order:
   ```
   implement the spec in sample_spec_set/
   ```
   It reads the spec, writes the code and tests, runs locally, and deploys to Fabric.

## The sjd-builder agent

**sjd-builder** is a custom Copilot agent (defined in `.github/agents/sjd-builder.agent.md`) that owns the full lifecycle of a PySpark SJD — from reading a spec all the way to a running job on Fabric. Select it from the Copilot chat mode dropdown in VS Code.


1. **Scaffold** the Python package (if it doesn't exist yet)
2. **Implement** modules in `src/` based on the spec
3. **Write tests** and run pytest locally
4. **Run locally** against the dev container's Spark — fast inner loop, seconds not minutes
5. **Deploy to Fabric** — build `.whl`, upload to Environment, publish, create/update the SJD
6. **Run on Fabric** and check logs
7. **Fix loop** — if Fabric errors, fix locally, re-run locally, redeploy

The agent has two skills that give it domain knowledge beyond what's in its prompt:

- **fabric-ops** — Fabric REST API patterns, deployment gotchas, LRO polling, log retrieval
- **local-spark** — dual-environment patterns for sessions, paths, auth, and SQL connectivity

These skills, along with the workspace-wide `copilot-instructions.md`, keep the agent grounded in the project's conventions so it writes code that works identically local and on Fabric.

## `devops_helpers/`

`devops_helpers/fabric_ops.py` is a CLI that wraps the Fabric REST API for Spark job operations. It exists for the agent — you shouldn't need to call it directly. The agent (and its skills) are instructed to **check devops_helpers first** before making any raw Fabric API call. If a helper exists, use it; if not, raw API calls are fine.

Requires `WS_ID` and `SJD_ID` environment variables.

```
fabric_ops.py run        # Submit job, wait for completion, show failure details
fabric_ops.py status     # Latest run status
fabric_ops.py runs       # List recent runs
fabric_ops.py livy       # Livy session details
fabric_ops.py logs       # Driver stdout/stderr
```

This keeps Fabric interactions consistent and avoids the agent reinventing API calls that already work.

## Project structure

Directories and files for the **template Python package** the agent will build:

| Component | Purpose |
|---|---|
| `src/` | Your PySpark package (source layout, `pip install -e .`) |
| `tests/` | pytest + pytest-cov, Spark-aware markers (`spark`, `integration`) |
| `main.py` | SJD entry point — created by sjd-builder when you implement a spec |
| `pyproject.toml` | Package metadata, dependencies, ruff/pytest config |
| `lakehouse/` | Local lakehouse mirror for testing (Files + Delta Tables) |

Files that define the **custom Copilot agent** and support it:

| Component | Purpose |
|---|---|
| Dev container | Fabric Runtime 1.3 parity: Spark 3.5, Java 11, Python 3.11, Delta Lake 3.2 |
| `.github/agents/sjd-builder.agent.md` | The sjd-builder agent definition |
| `.github/copilot-instructions.md` | Global rules: code style, testing, Fabric constraints |
| `.github/skills/` | Agent skills for Fabric ops, local Spark patterns |
| `devops_helpers/` | CLI tools for Fabric deployment, monitoring, and log retrieval |
| `sample_spec_set/` | Example spec set demonstrating the sjd-builder workflow |

## Stack

- Python 3.11
- PySpark 3.5 + Delta Lake 3.2
- ruff (lint + format)
- pytest + pytest-cov
- pre-commit
- Azure CLI + GitHub CLI
- Microsoft Fabric Runtime 1.3 compatible

Same code runs locally and on Fabric — only 3–4 narrow branch points separate the two environments. See [docs/LOCAL_VS_FABRIC.md](docs/LOCAL_VS_FABRIC.md) for details.
