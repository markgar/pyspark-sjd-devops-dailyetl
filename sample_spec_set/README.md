> **📘 SAMPLE GUIDANCE — delete this block in a real spec set.**
>
> The README is the front door to your spec set. Summarise what the pipeline
> does, list the specs in order, and explain how to hand them to the
> sjd-builder agent. Keep it short — the specs themselves carry the detail.

# Sample Spec Set

A trivial three-step PySpark ETL pipeline that demonstrates the spec format used by the **sjd-builder** agent.

## What it builds

1. **People to CSV** — generate fake person data and write it as CSV
2. **CSV to Delta** — read that CSV and write a `people` Delta table
3. **Test SQL Connectivity** — verify JDBC/mssql connectivity to Azure SQL

## How to use

Select **sjd-builder** from the Copilot chat mode dropdown, then hand it specs one at a time:

```
implement sample_spec_set/01_people_to_csv.md
implement sample_spec_set/02_csv_to_delta.md
```

Or point it at the whole directory to build everything in order:

```
implement the spec in sample_spec_set/
```

The agent reads `CONSTITUTION.md` for project-level facts, then works through the numbered specs in order.

## Structure

| File | Purpose |
|---|---|
| `CONSTITUTION.md` | Package name, stack, entry point, environment config, Fabric targets — shared across all specs |
| `01_people_to_csv.md` | Step 1: generate data → CSV |
| `02_csv_to_delta.md` | Step 2: CSV → Delta table |
| `03_test_sql_connectivity.md` | Step 3: verify Azure SQL access |
