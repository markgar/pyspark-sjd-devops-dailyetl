# Module: Test SQL Connectivity

## Description

Verify JDBC connectivity to an Azure SQL Database by reading the `Application.Cities` table and returning the results as a DataFrame.

## Connection Details

- **Server:** `adventureworksltmg.database.windows.net`
- **Database:** `wideworldimporters`
- **Driver:** JDBC (SQL Server / `com.microsoft.sqlserver.jdbc.SQLServerDriver`)
- **Table:** `Application.Cities`

## Authentication

| Environment       | Method                                                                 |
|-------------------|------------------------------------------------------------------------|
| Local development | Azure AD credentials of the logged-in developer (`DefaultAzureCredential` / interactive) |
| Microsoft Fabric  | Workspace identity (managed identity)                                  |

The module should detect the runtime environment and select the appropriate authentication method automatically.

> **Local dev note:** The developer may not be logged in to Azure yet. If `DefaultAzureCredential` fails during a local run, stop and ask the user to run `az login` before retrying.

## Module

- **File:** `src/spark_project/test_sql_connectivity.py`
- **Entry point:** `run(spark)` function
- Helper functions:
  - `get_jdbc_url()` — builds the JDBC connection URL
  - `get_jdbc_properties(spark)` — returns JDBC connection properties with the appropriate auth token
  - `read_cities(spark)` — reads the `Application.Cities` table via JDBC and returns it as a DataFrame
