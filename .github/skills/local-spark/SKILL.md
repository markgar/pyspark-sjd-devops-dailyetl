---
description: "SparkSession creation, lakehouse paths, environment detection, LOCAL_DEV, is_local_dev, JDBC, mssql, DefaultAzureCredential, SQL connectivity, Delta Lake local setup, dual-environment branching patterns"
---

# Local Spark — Dual-Environment Development Patterns

Fast local PySpark development that runs identically in a local dev container and in Microsoft Fabric Spark Job Definitions. There are only 3–4 narrow branch points between local and Fabric. Everything else is identical.

---

## 1. Environment Detection

A single environment variable, `LOCAL_DEV`, tells the code where it's running.

| Variable | Local Dev | Fabric |
|---|---|---|
| `LOCAL_DEV` | `"1"` | Not set |

```python
import os

def is_local_dev() -> bool:
    """True when running in the local dev container, False in Fabric."""
    return os.environ.get("LOCAL_DEV") == "1"
```

Set `LOCAL_DEV=1` in `.vscode/settings.json` via `terminal.integrated.env.linux`:

```json
{
    "terminal.integrated.env.linux": {
        "LOCAL_DEV": "1"
    }
}
```

Never set it in Fabric — its absence is the signal.

Centralize this check in a helper and import it everywhere. Don't scatter `os.environ.get("LOCAL_DEV")` throughout the codebase.

---

## 2. Lakehouse File/Path Strategy

Fabric Spark jobs see the attached lakehouse as the working directory, so `Files/data.csv` and `Tables/my_table` resolve directly. Locally, those same files live under a `lakehouse/` folder in the repo.

```python
def _default_lakehouse_root():
    return "lakehouse" if os.environ.get("LOCAL_DEV") == "1" else ""

LAKEHOUSE_ROOT = os.environ.get("LAKEHOUSE_ROOT", _default_lakehouse_root())
```

| Environment | `LAKEHOUSE_ROOT` | Resolved path example |
|---|---|---|
| Local Dev | `"lakehouse"` | `lakehouse/Files/people.csv` |
| Fabric | `""` (empty) | `Files/people.csv` |

All file and table access uses `os.path.join(LAKEHOUSE_ROOT, ...)`:

```python
csv_path = os.path.join(LAKEHOUSE_ROOT, "Files", "people.csv")
table_path = os.path.join(LAKEHOUSE_ROOT, "Tables", "my_table")
df.write.format("delta").mode("overwrite").save(table_path)
```

**Local folder structure mirrors Fabric's lakehouse layout:**

```
lakehouse/
├── Files/        ← unstructured data (CSV, JSON, Parquet, etc.)
└── Tables/       ← Delta tables
    └── my_table/
        └── _delta_log/
```

Add `lakehouse/` to `.gitignore` — never check in generated data. `LAKEHOUSE_ROOT` can also be overridden for non-standard setups.

---

## 3. SparkSession Creation

Fabric provides Delta Lake and cluster management. Locally, you configure both yourself.

```python
from pyspark.sql import SparkSession

builder = SparkSession.builder.appName("my-job")

if is_local_dev():
    from delta import configure_spark_with_delta_pip

    builder = (
        builder
        .master("local[*]")
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config("spark.sql.catalog.spark_catalog",
                "org.apache.spark.sql.delta.catalog.DeltaCatalog")
    )
    spark = configure_spark_with_delta_pip(builder).getOrCreate()
else:
    spark = builder.getOrCreate()
```

### Test-Optimized SparkSession

The production SparkSession pattern above is for `main.py`. In **`conftest.py`**, use these additional settings to cut test runtime dramatically:

```python
builder = (
    SparkSession.builder
    .master("local[2]")
    .appName("tests")
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
    .config("spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog")
    .config("spark.sql.shuffle.partitions", "1")
    .config("spark.default.parallelism", "1")
    .config("spark.ui.enabled", "false")
)
```

| Setting | Default | Test value | Why |
|---|---|---|---|
| `spark.sql.shuffle.partitions` | 200 | 1 | Test data is tiny — 200 partitions wastes time |
| `spark.default.parallelism` | cores | 1 | Same reason |
| `spark.ui.enabled` | true | false | Saves memory and startup time |
| `master` | `local[*]` | `local[2]` | Enough parallelism to catch issues; `local[*]` oversubscribes |

The Spark fixture should be **session-scoped** (one startup per test run). Each test gets its own `lakehouse_root` via `tmp_path`/`monkeypatch` so Delta tables don't leak between tests.

| Aspect | Local | Fabric |
|---|---|---|
| Spark master | `local[*]` (multi-threaded, single machine) | Managed by Fabric (multi-node cluster) |
| Delta Lake | `configure_spark_with_delta_pip()` required | Pre-installed in runtime |
| `delta-spark` import | Required | Not needed (never imported on Fabric) |

The conditional import of `delta` inside the `if is_local_dev()` block means Fabric never tries to import it from your code.

---

## 4. Authentication & SQL Connectivity

SQL requires **different connectors** per environment — the one true branch point where the code paths diverge.

### Why two paths?

| Concern | Local Dev | Fabric |
|---|---|---|
| SQL connector | JDBC (`spark.read.jdbc(...)`) | Built-in `.mssql()` connector |
| Auth mechanism | `DefaultAzureCredential` → access token | Workspace identity (automatic Entra auth) |
| JDBC driver JAR | Must be on classpath (dev container provides it) | Not needed |
| `azure-identity` | Required (`pip install azure-identity`) | Not used for SQL |

### Local Dev — JDBC + DefaultAzureCredential

Developer must be logged in via `az login`. `DefaultAzureCredential` obtains an access token scoped to Azure SQL.

```python
from azure.identity import DefaultAzureCredential

def _get_local_access_token() -> str:
    return DefaultAzureCredential().get_token("https://database.windows.net/.default").token

def _read_table_local(spark: SparkSession) -> DataFrame:
    url = f"jdbc:sqlserver://{SERVER}:1433;database={DATABASE};encrypt=true;trustServerCertificate=false;"
    props = {"driver": DRIVER, "accessToken": _get_local_access_token()}
    return spark.read.jdbc(url=url, table=TABLE, properties=props)
```

### Fabric — Built-in .mssql() Connector

`.mssql()` auto-authenticates using the workspace's Entra identity. No tokens, no imports, no credential objects.

```python
def _read_table_fabric(spark: SparkSession) -> DataFrame:
    url = f"jdbc:sqlserver://{SERVER}:1433;database={DATABASE};"
    return spark.read.option("url", url).mssql(TABLE)
```

> **Important:** `.mssql()` does not exist locally — never call it outside a Fabric code path. The conditional `import` of `azure.identity` inside the local path means Fabric never loads that package either.

### Public API — Branch on Environment

Expose a single function that branches internally. Callers never know which connector is used.

```python
def read_table(spark: SparkSession) -> DataFrame:
    if is_local_dev():
        return _read_table_local(spark)
    return _read_table_fabric(spark)
```

### Pattern Summary

1. Define constants for server, database, table, and driver at module level.
2. Write `_read_*_local()` using JDBC + `DefaultAzureCredential` access token.
3. Write `_read_*_fabric()` using `.mssql()` with just a URL option.
4. Write a public `read_*()` that calls `is_local_dev()` and delegates.
5. Keep `azure.identity` imports **inside** the local-only function so Fabric never loads them.

### General Auth (non-SQL Azure services)

For services other than SQL (Storage, Key Vault, etc.), `DefaultAzureCredential` works identically in both environments:

| Environment | Credential source |
|---|---|
| Local Dev | Azure CLI (`az login`) |
| Fabric | Workspace Managed Identity (automatic) |

```python
from azure.identity import DefaultAzureCredential
token = DefaultAzureCredential().get_token("https://storage.azure.com/.default").token
```

Use environment variables for config values that differ between environments (server names, database names, storage URLs).
