> **📘 SAMPLE GUIDANCE — delete this block in a real spec set.**
>
> The constitution holds unchanging project-level facts that every numbered
> spec inherits: package name and source layout, stack versions, entry point,
> environment-variable strategy, and Fabric deployment targets. If it's true
> for the whole project and won't change spec-to-spec, it belongs here.

# Constitution

Unchanging project-level facts. Every numbered spec inherits these.

## Package

- **Package name:** `pyspark_sjd_devops`
- **Source:** `src/pyspark_sjd_devops/`
- **Tests:** `tests/`


## Stack

- PySpark 3.5 + Delta Lake 3.2
- Python 3.11
- Microsoft Fabric Runtime 1.3 compatible

## Entry Point

- **File:** `main.py` (project root)

## Environment Configuration

- The `LOCAL_DEV` environment variable is set to `"1"` via `.vscode/settings.json` using `terminal.integrated.env.linux`.
- This tells the code it's running locally (see [Local Dev / Fabric Strategy](../local-dev-fabric-strategy.md) for details).
- In Fabric, `LOCAL_DEV` is not set — its absence signals the production runtime.

## Fabric Targets

- **Workspace:** `pyspark-sjd-devops`
- **Spark Job Definition:** `pyspark-sjd-devops-sjd`
- **Environment:** `pyspark-sjd-devops-env`
- **Default Lakehouse:** `pyspark-sjd-devops-lh` (schema-disabled)
