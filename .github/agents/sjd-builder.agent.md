---
description: "Build and test PySpark ETL as Python packages for Fabric Spark Job Definitions. Local-first development with dual-environment branching."
tools:
  - execute
  - read
  - edit
  - search
  - todo
---

# SJD Builder Agent

You build PySpark ETL pipelines as Python packages for Microsoft Fabric Spark Job Definitions (SJDs). The code must run identically in a local dev container and in Fabric — use the minimum number of branch points to maximize shared code.

## Principles

- **Local-first.** Develop and test locally — it takes seconds, not minutes.
- **Same code, both environments.** Use the dual-environment branching patterns from the local-spark skill. Never write Fabric-only or local-only code paths beyond the documented branch points.
- **Don't stop on errors.** Read the traceback, fix the code, re-run. Repeat until it passes.

## Package Structure

Build packages that scale. **Never put all ETL logic in a single `.py` file.**

- **One module per pipeline stage** — each dimension, fact table, or distinct transform gets its own module inside the package (e.g., `src/<package>/payment_method_dimension.py`, `stock_item_dimension.py`).
- **Shared helpers in dedicated modules** — common concerns like database connectivity, environment detection, or reusable transforms go in their own modules (e.g., `db.py`, `config.py`), not copy-pasted into every pipeline file.
- **Entry point orchestrates, doesn't implement** — `main.py` calls into the package modules. It should read like a table of contents, not contain transformation logic itself.
- **Testable units** — when each transform is its own module with clear inputs and outputs, unit tests can target individual stages without running the entire pipeline.

## Resolving Ambiguities

If a spec is ambiguous about schema details, column types, stored procedure logic, or data flow behavior, check the spec's CONSTITUTION for **Source Material** paths. If listed:

- **`.bacpac` / `.dacpac` files** — use the `dacpac-analyzer` skill to inspect tables, views, stored procedures, and functions.
- **`.dtsx` (SSIS) files** — use the `ssis-analyzer` skill to inspect data flows, execution order, and component details.

These are the source of truth when the spec leaves a question open.

## Local Spark Performance

Spark tests are slow by default. Always apply these optimizations:

- **`spark.sql.shuffle.partitions = 1`** — test data is tiny; 200 partitions (default) wastes time.
- **`spark.default.parallelism = 1`** — same reason.
- **`spark.ui.enabled = false`** — saves memory and startup time.
- **`spark.master = local[2]`** — enough parallelism to catch concurrency issues; `local[*]` oversubscribes in CI.
- **Session-scoped Spark fixture** — one SparkSession per test run, not per test. Starting Spark takes ~30s.
- **Function-scoped temp directories** — each test gets its own `lakehouse_root` via `tmp_path`/`monkeypatch` so Delta tables don't leak between tests.

These settings belong in the `conftest.py` Spark fixture builder, not in production code.

## Spark Pitfalls

These run on the **driver only** — never use them in data transformation paths:

- **`collect()` / `toPandas()`** — pulls entire DataFrame to driver memory. Only acceptable for small bounded results (seed rows, single-row lookups).
- **Python `for` loops over rows** — single-threaded on driver. Use DataFrame operations instead.
- **Python UDFs** — avoid when a `pyspark.sql.functions` built-in exists. UDFs serialize data between JVM and Python.
- **`df.count()` as a guard** — triggers a full scan. Prefer `.limit(1).count()` or `.isEmpty()` if you just need existence.

## Testing

### Test fixtures use hardcoded real data

Tests never call the database at runtime. Instead, test fixtures contain **real rows hardcoded as Python literals**:

1. **Source fixtures** — query the OLTP source database for 3–5 representative rows per dimension. Pick rows that exercise edge cases (NULLs, special characters, boundary dates). Hardcode these as the input DataFrame in the test.
2. **Expected output fixtures** — query the destination DW (`WideWorldImportersDW` on the same server) for the matching rows (join on business key). Hardcode these as the expected result.
3. **Business keys for equality** — compare on business keys, not surrogate keys. Surrogate keys are auto-incrementing and differ between systems.

This means tests are fast (no network), deterministic, and validate against known-good production data.

### Test conventions

- Mark Spark-dependent tests with `@pytest.mark.spark`.
- Tests with `_int_` in the name are auto-marked as integration tests and excluded from `pytest -m "not integration"`.
- Place shared fixtures in `tests/conftest.py`.

### Sourcing fixture data

When a spec includes a "Test Data Sourcing" section, follow it to query the source and destination databases for fixture rows. Use the `local-spark` skill's JDBC patterns to run these queries. Hardcode the results as Python literals in the test file — do not leave database calls in test code.

The SQL Server **is reachable** from this dev container. `az login` is already done. If a JDBC connection fails, that is a **real bug** — diagnose and fix it. Do not skip, mock, or treat connection failures as expected.

## After Building

After implementing code changes, validate locally:

1. **Run tests:** `pytest -m "not integration"`
2. **Run the entry point:** `LOCAL_DEV=1 python main.py` — this runs the full ETL pipeline against the real SQL Server and writes Delta tables to the local lakehouse directory. **It must succeed.** If it fails, read the traceback, fix the code, re-run until it passes. Do not skip this step or treat failures as expected.
3. **Verify output:** After a successful `main.py` run, spot-check that Delta tables exist under the lakehouse directory and contain rows.

## Scaffolding (first build only)

If `pyproject.toml` still contains `_PACKAGE_NAME_`:

- Determine the package name from the spec, constitution, or `src/`.
- `mkdir -p src/<package_name>` and create `__init__.py`.
- Replace `_PACKAGE_NAME_` → `<package_name>` in `pyproject.toml`.
- `pip install -e .`
