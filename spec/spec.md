# Project Spec: People CSV Generator

## Overview

A PySpark job that generates imaginary person data and writes it to CSV.
Built on the existing `spark_project` package structure.

## Package

- **Package name:** `spark_project` (default)
- **Source:** `src/spark_project/`
- **Tests:** `tests/`

## Stack

- PySpark 3.5 + Delta Lake 3.2
- Python 3.11
- Microsoft Fabric Runtime 1.3 compatible

## Modules

- [People to CSV](people_to_csv.md)
- [CSV to Delta](csv_to_delta.md)
- [Test SQL Connectivity](test_sql_connectivity.md)

## Entry Point

- **File:** `src/spark_project/main.py`
- Fabric Spark Job Definition main file
- Creates (or gets) the SparkSession
- Calls the three modules in order:
  1. People to CSV — generate person data and write CSV
  2. CSV to Delta — read the CSV and write to a `people` Delta table
  3. Test SQL Connectivity — verify JDBC connection to Azure SQL

## Development & Deployment Workflow

1. **Develop locally** — all modules are built and tested on the local PySpark environment first. No Fabric access is needed until the final step.
2. **Deploy to Fabric** — once everything works locally, deploy to Microsoft Fabric as a Spark Job Definition.
3. **Verify on Fabric:**
   - Check the **Livy endpoint** for job logs and execution status.
   - Check the **Lakehouse** to confirm the output files (CSV and Delta table) were written correctly.
