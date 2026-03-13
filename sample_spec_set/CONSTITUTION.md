> **📘 SAMPLE GUIDANCE — delete this block in a real spec set.**
>
> The constitution holds unchanging project-level facts that every numbered
> spec inherits: package name and source layout, stack versions, entry point,
> environment-variable strategy, and Fabric deployment targets. If it's true
> for the whole project and won't change spec-to-spec, it belongs here.

# Constitution

Unchanging project-level facts. Every numbered spec inherits these.

## Package

- **Package name:** `hello_pyspark_local_dev`
- **Source:** `src/hello_pyspark_local_dev/`
- **Tests:** `tests/`

> **IMPORTANT:** The existing repo is a template. The package **must** be renamed to match the package name specified above — including the `src/` directory, `pyproject.toml` `[project] name`, all imports, and any other references. Do not keep the template's original package name.

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

- **Workspace:** `daily_etl`
- **Spark Job Definition:** `hello_pyspark_local_dev`
- **Environment:** `hello_pyspark_local_dev`
- **Default Lakehouse:** `pyspark_devops` (schema-disabled)
