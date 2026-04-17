---
marp: true
theme: default
paginate: true
size: 16:9
title: Spec-Driven PySpark ETL for Microsoft Fabric
---

# Spec-Driven PySpark ETL for Microsoft Fabric

From SSIS packages → markdown specs → tested PySpark `.whl` → deployed SJD

**A local-first inner loop powered by custom Copilot agents**

---

## The problem

- Fabric notebook dev = browser IDE, slow clusters, no tests, no PRs
- Notebooks carry JSON wrappers, cell metadata, output blobs
- 2am outage → no commit history, no local repro
- Migrating **hundreds of SSIS packages** to PySpark by hand is untenable

---

## The approach

1. **Specs, not prompts** — markdown specs describe each ETL pipeline
2. **Packages, not notebooks** — deliverable is a tested `.whl`
3. **Local first** — dev container mirrors Fabric Runtime 1.3 exactly
4. **Agents do the typing** — custom Copilot agents read specs, write code, test, deploy

---

## Major components

![bg right:40% fit](images/sjd-builder-chat-mode.png)

- **GitHub repo** (template + PRs + CI)
- **Dev container** (Fabric Runtime 1.3 parity)
- **Custom Copilot agents** (spec-writer, sjd-builder, sjd-reviewer, sjd-plan-eval)
- **Agent skills** (SSIS, DACPAC, Fabric ops, local-spark, docs)
- **Spec sets** (CONSTITUTION + numbered specs)
- **devops_helpers/** (Fabric REST CLI)
- **Fabric workspace** (Environment + SJDs + Lakehouse)

---

## Dev container = Fabric Runtime 1.3 parity

| Layer | Version |
|---|---|
| Python | 3.11 |
| Spark | 3.5 |
| Java | 11 |
| Delta Lake | 3.2 |
| JDBC | mssql-jdbc preinstalled |
| Tooling | Azure CLI, GitHub CLI, ruff, pytest, pre-commit |

**Same code runs locally and on Fabric** — only 3-4 narrow branch points (see `docs/LOCAL_VS_FABRIC.md`).

---

## The agents

| Agent | Role |
|---|---|
| **spec-writer** | Reads `.ispac` / `.bacpac` → writes CONSTITUTION + numbered specs |
| **sjd-plan-eval** | Reviews an implementation plan before code is written |
| **sjd-builder** | Implements spec → code + tests → runs locally → deploys SJD |
| **sjd-reviewer** | Reviews PySpark for correctness, perf, Delta best practices |

Each has scoped tools and a tight system prompt — no single mega-agent.

---

## Agent skills (domain knowledge, reusable)

- **ssis-analyzer** — parses `.ispac` / `.dtsx` into component/dataflow graphs
- **dacpac-analyzer** — extracts schemas from `.bacpac` / `.dacpac`
- **fabric-ops** — REST patterns, `updateDefinition`, LRO polling, Livy logs
- **local-spark** — session creation, lakehouse paths, dual-env branching
- **microsoft-docs** / **microsoft-code-reference** — grounding
- **microsoft-skill-creator** — meta-skill for building new skills

Skills keep agents grounded and consistent across runs.

---

## Spec-driven workflow

```mermaid
flowchart LR
  A[SSIS .ispac / .bacpac] --> B(spec-writer)
  B --> C[CONSTITUTION.md + numbered specs]
  C --> D(sjd-plan-eval)
  D --> E(sjd-builder)
  E --> F[src/ package + tests]
  F --> G[pytest local Spark]
  G --> H[.whl → Fabric Environment]
  H --> I[Spark Job Definition]
  I --> J(sjd-reviewer)
```

---

## The inner loop (seconds, not minutes)

1. Edit `src/pyspark_sjd_devops_dailyetl/...`
2. `pytest -m "not integration"` → Spark session in container
3. Fix → repeat
4. Integration test against real lakehouse / SQL
5. `fabric_ops.py run` → deploy + run on Fabric
6. Pull logs, fix, repeat

**No browser. No cluster warmup. Git history the whole way.**

---

## devops_helpers/fabric_ops.py

CLI that wraps the Fabric REST API — the agent is instructed to use it **before** writing any raw HTTP.

```text
fabric_ops.py run        # Submit job, wait, show failure detail
fabric_ops.py status     # Latest run status
fabric_ops.py runs       # Recent runs
fabric_ops.py livy       # Livy session details
fabric_ops.py logs       # Driver stdout/stderr
```

Keeps Fabric interactions consistent; no reinvented API calls.

---

## Repo conventions that keep agents honest

- `.github/copilot-instructions.md` — global rules (Python 3.11, ruff, 120 cols, no `mssparkutils`, `DefaultAzureCredential` everywhere)
- `pyproject.toml` ruff rules: F, E, W, B, I, UP, S, PL
- `pytest` markers: `spark`, `integration`
- Pre-commit hooks enforce before the agent can push
- Source layout (`src/<package>/`) — production deliverable is a `.whl`

---

## What you might be missing / could add next

- **CI in GitHub Actions** — ruff + pytest on every PR, artifact the `.whl`
- **CD pipeline** — auto-deploy `.whl` to Fabric Environment on merge to `main`
- **Environment promotion** — dev / test / prod Fabric workspaces via variables
- **Secret management** — Key Vault + workspace identity (already partial)
- **Data quality gates** — Great Expectations or `dbt test`-style checks
- **Observability** — structured logging → Log Analytics, lineage via OpenLineage
- **Spec templates per pattern** — dim load, fact load, SCD2, CDC
- **Golden datasets** — small Delta fixtures checked in for deterministic tests
- **Cost guardrails** — Fabric capacity monitoring, job size limits
- **Agent evals** — measure spec → working SJD success rate over time

---

## Why this works

- **Specs are reviewable** — PRs on markdown before code is written
- **Code is testable** — plain Python package, not a notebook blob
- **Local ≈ Fabric** — parity container kills the "works on my cluster" class of bugs
- **Agents are scoped** — small system prompts + skills beat one giant prompt
- **Humans stay in the loop** — at the spec, the plan, and the review

---

# Questions?

Repo: `pyspark-sjd-devops-dailyetl`
Docs: `docs/LOCAL_VS_FABRIC.md`, `docs/AGENT_SKILLS_IN_DEVCONTAINERS.md`
Agents: `.github/agents/`
Skills: `.github/skills/`
