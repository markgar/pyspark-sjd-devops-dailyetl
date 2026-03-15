# Constitution

Unchanging project-level facts. Every numbered spec inherits these.

## Package

- **Package name:** `pyspark_sjd_devops_dailyetl`
- **Source:** `src/pyspark_sjd_devops_dailyetl/`
- **Tests:** `tests/`

## Stack

- PySpark 3.5 + Delta Lake 3.2
- Python 3.11
- Microsoft Fabric Runtime 1.3 compatible

## Entry Point

- **File:** `main.py` (project root)

## Source Database

- **Server:** `adventureworksltmg.database.windows.net`
- **Database:** `WideWorldImporters`
- **Driver (local):** JDBC (`com.microsoft.sqlserver.jdbc.SQLServerDriver`)

## Destination

- **Target:** Fabric Lakehouse (Delta tables)
- **Table naming:** Replace spaces and special characters with underscores to satisfy Delta naming rules. Keep names as close to the SQL Server originals as possible.
- **Column naming:** Same rule — replace spaces with underscores. No Delta column mapping.

## Authentication

| Environment       | Connector                                             | Auth mechanism                                                     |
|-------------------|-------------------------------------------------------|--------------------------------------------------------------------|
| Local development | JDBC (`spark.read.jdbc(...)`)                         | `DefaultAzureCredential` → access token (`az login` required)     |
| Microsoft Fabric  | Built-in Spark SQL connector (`spark.read...mssql()`) | Workspace identity (automatic Entra auth, no token needed)         |

The module auto-detects the runtime environment and selects the appropriate connector and auth method.

### Local

- Uses `DefaultAzureCredential` to obtain an access token scoped to `https://database.windows.net/.default`.
- Connects via JDBC with the token as an `accessToken` connection property.

### Fabric

- Uses the built-in `.mssql()` Spark SQL connector (pre-registered in Fabric runtime).
- Auth is automatic via the workspace's Entra identity — no tokens needed.
- `.mssql()` does not exist outside Fabric.

## Environment Configuration

- The `LOCAL_DEV` environment variable is set to `"1"` via `.vscode/settings.json` using `terminal.integrated.env.linux`.
- This tells the code it's running locally.
- In Fabric, `LOCAL_DEV` is not set — its absence signals the production runtime.

## Fabric Targets

- **Workspace:** `pyspark-sjd-devops-dailyetl`
- **Spark Job Definition:** `pyspark-sjd-devops-dailyetl-sjd`
- **Environment:** `pyspark-sjd-devops-dailyetl-env`
- **Default Lakehouse:** `pyspark-sjd-devops-dailyetl-lh` (schema-disabled)

## Testing Strategy

- **Unit tests** use hardcoded sample data as input fixtures — no live database queries at test time.
- **Sample data** is pulled from the source database during development (not by the build agent, but by the spec author or developer writing the tests) and embedded in the test files.
- **Expected outputs** are pulled from the destination DW (`WideWorldImportersDW` on `adventureworksltmg.database.windows.net`) during development and hardcoded as expected results.
- **Business keys** (not surrogate keys) are used for equality checks, since surrogate keys are auto-incrementing and may differ between systems.
- Mark Spark-dependent tests with `@pytest.mark.spark`.
- Integration tests (those with `_int_` in the name) are auto-marked and excluded from fast local runs.

## Migration Context

This spec set documents the migration of the **WideWorldImporters DailyETL** from SQL Server Integration Services (SSIS) to native PySpark running in Microsoft Fabric. The original SSIS package (`DailyETLMain.dtsx`) performs incremental dimension and fact loads from the `WideWorldImporters` OLTP database into the `WideWorldImportersDW` data warehouse. Each spec in this set covers one dimension or fact table.
